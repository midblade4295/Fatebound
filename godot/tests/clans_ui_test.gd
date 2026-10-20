extends SceneTree
# 0.31.134: clans through the app's real buttons, against the real server (its own process, port
# 8118), in REAL time. Alice is the app (an account with 25,000 gold); Bob is a second phone (scripts/meta/social.gd +
# a raw match socket). Home's SOCIAL opens FRIENDS with a CLAN tab; Alice starts [WOLF] Iron Wolves of House Stags
# (the server takes 5,000 gold -- 0.31.148 -- and her app shows it); Bob finds and joins it; Bob's clan line reaches Alice's CLAN
# chat with his tag; she makes him an officer from MANAGE; his tag is on her chat and on his name card (0.31.164: the
# online match carrying it went with Siege; 0.31.169: its phases too); he leaves and waits 24 hours.
# 0.31.196 (Kevin: "Do clan chest, clan camp, crest, shard requests, 5 - stack, lfg button, league"): the starter
# clans; START A CLAN with a crest (no house); her clan opens on its CAMP (the camp painting at stage 1, its banner in
# the crest's colours with the crest on it, the crest, name and level over it), CAMP / MEMBERS / LEAGUE; the CLAN CHEST;
# CHANGE CREST; Bob asks for a Golem shard and Alice GIVEs hers from clan chat (her melt gold, the request over); her
# LOOKING FOR GROUP call and Bob JOINs her party (of 5); the LEAGUE tab; MANAGE from MEMBERS.
# 0.31.197 (Kevin: "make the camp screen fill the entire screen ... and incorporate the clan buttons into the screen"):
# in a clan the window is the camp, full screen, its buttons standing in it (the CLAN CHEST and SHARDS on the ground,
# CHAT / MEMBERS / LEAGUE / CLAN, LOOKING FOR GROUP); each part opens its sheet over the camp.
# With a display and SHOT_DIR set, screenshots of each window go there.
#   godot --headless --path godot -s res://tests/clans_ui_test.gd
const App = preload("res://scripts/app/siege_app.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const ClientSocial = preload("res://scripts/meta/social.gd")
const FriendsPanel = preload("res://scripts/app/friends_panel.gd")
const ClanPanel = preload("res://scripts/app/clan_panel.gd")
const ChatPanel = preload("res://scripts/app/chat_panel.gd")
const EcoAccounts = preload("res://server/eco_accounts.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const ClanCamp = preload("res://scripts/app/clan_camp.gd")

var port := 8118
var server_pid := -1
var fails: Array = []
var phase := "boot"
var t := 0.0
var t_phase := 0.0
var raw := {}
var accts := {}
var app
var bob
var shots := ""
var clan_id := ""
var _gold0 := 0

func _find_meta(node: Node, key: String) -> String:
	if node.has_meta(key):
		return str(node.get_meta(key))
	for c in node.get_children():
		var r := _find_meta(c, key)
		if r != "":
			return r
	return ""

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func btn(key: String, node: Node = null, text := "") -> Button:
	if node == null:
		node = app
	if node is Button and str(node.get_meta("action_key", "")) == key and node.is_visible_in_tree() and (text == "" or (node as Button).text == text):
		return node
	for c in node.get_children():
		var r := btn(key, c, text)
		if r != null:
			return r
	return null

func press(key: String, text := "") -> bool:
	var b := btn(key, null, text)
	if b == null or b.disabled:
		check(false, "button %s present and enabled" % key)
		return false
	b.pressed.emit()
	return true

func has_text(node: Node, s: String) -> bool:
	if (node is Label and (node as Label).text.contains(s)) or (node is Button and (node as Button).text.contains(s)):
		return node.is_visible_in_tree()
	for c in node.get_children():
		if has_text(c, s):
			return true
	return false

func _init() -> void:
	shots = OS.get_environment("SHOT_DIR") if DisplayServer.get_name() != "headless" else ""
	var sd := OS.get_user_data_dir().path_join("clanui-srv-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(sd)
	# the accounts, made before the server starts (Alice has the gold for a clan)
	var eco := EcoAccounts.new(sd)
	for n in [["alice", "Alice", 25000], ["bob", "Bob", 300]]:
		var e: Dictionary = eco.create({})
		e.p.d.name = str(n[1])
		e.p.d.gold = int(n[2])
		e.p.d.level = 8
		e.p.d.tutorial_done = true
		if str(n[0]) == "alice":
			e.p.d.shards = ["golem"]                     # 0.31.196: one to give Bob
		e.p.save()
		accts[n[0]] = [str(e.id), str(e.key_plain)]
	OS.set_environment("SIEGE_PORT", str(port))
	OS.set_environment("SIEGE_HOST", "127.0.0.1")
	OS.set_environment("SIEGE_LOBBY", "1.0")
	OS.set_environment("STATE_DIRECTORY", sd)
	OS.set_environment("SIEGE_MIN_BUILD", "off")
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:%d" % port)
	OS.set_environment("FB_ECO", "1")
	server_pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://server/siege_server.gd"])
	check(server_pid > 0, "server process started")

func _ws(name: String, first: Dictionary) -> void:
	var ws := WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 21
	ws.connect_to_url("ws://127.0.0.1:%d" % port)
	raw[name] = {"ws":ws, "sent":false, "first":first, "msgs":[]}

func _poll_raw() -> void:
	for n in raw:
		var r: Dictionary = raw[n]
		var ws: WebSocketPeer = r.ws
		ws.poll()
		var now_s := Time.get_ticks_msec() / 1000.0
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED and not bool(r.sent) and now_s - float(r.get("dialed", 0.0)) > 0.5:
			# 0.31.145: the server (its own process) may not be listening yet on a slow machine -- dial again
			r.dialed = now_s
			ws.connect_to_url("ws://127.0.0.1:%d" % port)
			continue
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN and not bool(r.sent):
			ws.put_packet(Net.encode(r.first))
			r.sent = true
		while ws.get_available_packet_count() > 0:
			(r.msgs as Array).append(Net.decode(ws.get_packet()))

func _raw_got(name: String, kind: String) -> Array:
	return (raw.get(name, {}).get("msgs", []) as Array).filter(func(m): return str(m.get("t", "")) == kind)

func _go(next: String) -> void:
	phase = next
	t_phase = 0.0

func _shot(name: String) -> void:
	if shots == "":
		return
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(shots.path_join(name + ".png"))

func _process(delta: float) -> bool:
	t += delta
	t_phase += delta
	_poll_raw()
	if t > 200.0:
		check(false, "timed out in phase %s" % phase)
		return _finish()
	match phase:
		"boot":
			if t_phase > 1.5:
				var base := "user://clanui-%d" % Time.get_ticks_usec()
				var p = Profile.new(base + "-profile.json", base + "-none.json")
				p.load_or_create()
				p.d.name = "Alice"
				p.d.gold = 25000
				p.d.level = 8
				p.d.account = {"id":accts.alice[0], "key":accts.alice[1], "seq":0}
				p.d.tutorial_done = true
				p.d.shards = ["golem"]
				p.save()
				app = App.new()
				app.profile_path = base + "-profile.json"
				app.legacy_path = base + "-none.json"
				root.add_child(app)
				app.social.set_active(true)
				var bp = Profile.new(base + "-bob.json", base + "-none.json")
				bp.load_or_create()
				bp.d.account = {"id":accts.bob[0], "key":accts.bob[1], "seq":0}
				bob = ClientSocial.new()
				bob.url = "ws://127.0.0.1:%d" % port
				bob.setup(bp)
				root.add_child(bob)
				bob.set_active(true)
				_go("online")
		"online":
			if app.social.online() and bob.online() and t_phase > 1.0:
				check(app.social.has_clans and bob.has_clans, "the server has clans")
				# 0.31.147 (Kevin: "When they click join clan it put the list of available clans or they have option to
				# start clan"): JOIN A CLAN opens the CLAN window on joining
				app.open_clan("join")
				_go("join_view")
		"join_view":
			if t_phase > 0.8:
				check(app.modal is ClanPanel and has_text(app.modal, "JOIN A CLAN") and has_text(app.modal, "FIND A CLAN") and has_text(app.modal, "be the first")
					and btn("clan_to_start") != null,
					"JOIN A CLAN: the clans to join (no players' clans yet: be the first), START MY OWN CLAN")
				# 0.31.148 (Kevin: "make a default clan for each faction that the new players can choose"): the house clans first
				check(has_text(app.modal, "STARTER CLANS") and has_text(app.modal, "The Lion Guard") and has_text(app.modal, "The Stag Guard")
					and has_text(app.modal, "The Raven Guard") and btn("clan_house_join_lions") != null and btn("clan_house_join_stags") != null
					and btn("clan_house_join_ravens") != null and app.social.house_clans.size() == 3, "STARTER CLANS: the Lion, Stag and Raven Guards, JOIN on each")
				_shot("clan_join_view")
				press("clan_to_start")
				_go("join_scrolled")
		"join_scrolled":
			if t_phase > 0.3:
				var sc: ScrollContainer = app.modal._scroll
				check(sc.scroll_vertical > 50 or sc.get_v_scroll_bar().max_value <= sc.size.y + 1.0,
					"START MY OWN CLAN goes down to START A CLAN (%d)" % sc.scroll_vertical)
				press("clan_house_join_lions")
				_go("in_house")
		"in_house":
			if app.social.in_house_clan() and t_phase > 0.6:
				check(str(app.social.clan.get("name", "")) == "The Lion Guard" and str(app.social.my_tag()) != "" and str(app.social.clan.get("role", "")) == "member",
					"JOIN: Alice is in The Lion Guard (free), a member")
				check(str(app.modal.mode) == "full" and app.modal.camp is ClanCamp and has_text(app.modal, "STARTER CLAN") and btn("clan_open_starter") != null
					and btn("clan_open_chest") == null and btn("clan_lfg") != null and btn("clan_open_shards") != null and btn("clan_chat") != null,
					"a starter clan: its camp, full screen -- STARTER CLAN on the ground (no Clan Chest), SHARDS, CHAT, LOOKING FOR GROUP")
				_shot("clan_house")
				press("clan_open_clan")
				_go("house_sheet")
			elif t_phase > 8.0:
				check(false, "Alice joins The Lion Guard")
				_go("left_house")
		"house_sheet":
			if t_phase > 0.5:
				check(str(app.modal.sheet) == "clan" and has_text(app.modal, "A CLAN OF YOUR OWN?") and has_text(app.modal, "MOVE TO A PLAYERS' CLAN")
					and btn("clan_start") != null and btn("clan_invite_code") == null and btn("clan_disband") == null and has_text(app.modal, "no wait")
					and btn("clan_crest_edit") == null, "its CLAN sheet: the players' clans to move to, START A CLAN; no crest, invites or disbanding; leaving has no wait")
				_shot("clan_house_sheet")
				press("clan_leave")
				press("clan_leave")
				_go("left_house")
			elif t_phase > 8.0:
				check(false, "Alice joins The Lion Guard")
				_go("left_house")
		"left_house":
			if not app.social.in_clan() and t_phase > 0.5:
				check(app.social.clan_cool_left() == 0, "she leaves it with no wait")
				app.close_modal()
				app.social_tab = "friends"               # (ALLIANCE opens on the tab last open: FRIENDS, as a fresh app)
				_go("online2")
		"online2":
			if t_phase > 0.3:
				check(btn("tab_alliance") != null and btn("side_friends") == null, "ALLIANCE is in the tab bar (0.31.139: SOCIAL's medallion is gone)")
				press("tab_alliance")
				check(app.modal is FriendsPanel and btn("social_tab_clan") != null and btn("social_tab_friends") != null, "ALLIANCE opens FRIENDS, with FRIENDS and CLAN tabs")
				_go("to_clan")
		"to_clan":
			if t_phase > 0.3:
				press("social_tab_clan")
				check(app.modal is ClanPanel, "the CLAN tab opens the clan window")
				_go("clan_none")
		"clan_none":
			if t_phase > 0.8:
				check(has_text(app.modal, "START A CLAN") and has_text(app.modal, "FIND A CLAN") and has_text(app.modal, "5,000"),
					"not in a clan: FIND A CLAN and START A CLAN (0.31.148: 5,000 gold)")
				check(btn("clan_start") != null and btn("crest_e_0") != null and btn("crest_e_15") != null and btn("crest_f_9") != null and btn("crest_c_7") != null
					and btn("crest_random") != null and btn("clan_house_lions") == null, "a crest to make: 16 emblems, 10 shield colours, 8 emblem colours, SHUFFLE (no houses)")
				_shot("clan_none")
				(app.modal._fields["new_name"] as LineEdit).text = "Iron Wolves"
				(app.modal._fields["new_tag"] as LineEdit).text = "wolf"
				(app.modal._fields["new_tag"] as LineEdit).text_changed.emit("wolf")
				press("crest_e_3")
				_go("pick_field")
		"pick_field":
			if t_phase > 0.3:
				press("crest_f_5")
				_go("pick_charge")
		"pick_charge":
			if t_phase > 0.3:
				press("crest_c_1")
				_go("pick_join")
		"pick_join":
			if t_phase > 0.3:
				press("clan_join_mode_request")
				_go("lv_up")
		"lv_up":
			if t_phase > 0.3:
				check(str(app.modal._join) == "request" and Eco.crest_code(app.modal._crest) == "3.5.1"
					and _find_meta(app.modal, "crest_preview") == "3.5.1", "the crest (a wolf in gold on the night shield) in the preview; join by request")
				press("clan_new_lv_up")
				_go("start")
		"start":
			if t_phase > 0.3:
				check(int(app.modal._min_lv) == 2 and (app.modal._fields["new_tag"] as LineEdit).text == "WOLF", "lowest level 2; the tag in capitals")
				_shot("clan_new_form")
				press("clan_start")
				_go("made")
		"made":
			if app.social.in_clan():
				var c: Dictionary = app.social.clan
				check(str(c.tag) == "WOLF" and str(c.name) == "Iron Wolves" and str(c.get("cc", "")) == "3.5.1" and str(c.join) == "request"
					and int(c.min_lv) == 2 and str(c.role) == "leader" and int(c.get("cv", 0)) == 2 and int(c.get("lv", 0)) == 1,
					"Alice leads [WOLF] Iron Wolves (its crest, by request, level 2+), a level-1 clan")
				clan_id = str(c.id)
				_go("gold")
		"gold":
			if int(app.profile.d.gold) == 20000:
				check(true, "the server took 5,000 gold and her app shows 20,000")
				_go("mine")
			elif t_phase > 8.0:
				check(false, "her gold is 20,000 after the clan (it's %d)" % int(app.profile.d.gold))
				_go("mine")
		"mine":
			if t_phase > 0.6:
				check(has_text(app.modal, "Iron Wolves") and has_text(app.modal, "LEVEL 1") and btn("clan_chat") != null and btn("clan_open_members") != null
					and btn("clan_open_league") != null and btn("clan_open_clan") != null and btn("clan_open_chest") != null and btn("clan_open_shards") != null
					and btn("clan_lfg") != null and btn("clan_close") != null and btn("social_tab_friends") != null,
					"her clan: the camp with its name and level, the CLAN CHEST and SHARDS, CHAT / MEMBERS / LEAGUE / CLAN, LOOKING FOR GROUP, FRIENDS, close")
				var cp = app.modal.camp
				check(cp is ClanCamp and int(cp.stage) == 1 and str(cp.code) == "3.5.1" and cp.crests.size() == 1 and cp.size.is_equal_approx(app.modal.size)
					and cp.size.y > 600.0, "the camp fills the screen (%s): stage 1, its banner with the crest on it" % str(cp.size if cp != null else ""))
				check(has_text(app.modal, "0 / 60 pts"), "the Clan Chest on the ground: 0 / 60 points")
				_shot("clan_mine")
				press("clan_open_chest")
				_go("chest_sheet")
		"chest_sheet":
			if t_phase > 0.5:
				check(str(app.modal.sheet) == "chest" and has_text(app.modal, "NO CHEST YET") and has_text(app.modal, "0 / 60 points") and has_text(app.modal, "WOODEN"),
					"CLAN CHEST opens its sheet: no chest yet, 0 / 60 to the Wooden Chest, the four tiers")
				_shot("clan_chest_sheet")
				press("clan_sheet_close")
				_go("clan_sheet")
		"clan_sheet":
			if t_phase > 0.4:
				check(str(app.modal.sheet) == "", "✕ closes the sheet")
				press("clan_open_clan")
				_go("clan_sheet2")
		"clan_sheet2":
			if t_phase > 0.5:
				check(btn("clan_crest_edit") != null and btn("clan_leave") != null and btn("clan_disband") != null and btn("clan_set_save") != null,
					"CLAN: CHANGE CREST, the settings, LEAVE, DISBAND")
				_shot("clan_clan_sheet")
				press("clan_crest_edit")
				_go("crest_edit")
		"crest_edit":
			if t_phase > 0.5:
				check(btn("crest_edit_e_0") != null and btn("clan_crest_save") != null and btn("clan_crest_save").disabled, "CHANGE CREST opens the editor (SAVE waits for a change)")
				press("crest_edit_e_0")
				_go("crest_edit2")
		"crest_edit2":
			if t_phase > 0.4:
				_shot("clan_crest_edit")
				press("clan_crest_save")
				_go("crest_saved")
		"crest_saved":
			if str(app.social.clan.get("cc", "")) == "0.5.1":
				check(true, "SAVE CREST: the clan's crest is the lion now")
				_go("crest_redrawn")
			elif t_phase > 8.0:
				check(false, "the crest changes (it's %s)" % str(app.social.clan.get("cc", "")))
				_go("crest_redrawn")
		"crest_redrawn":
			if t_phase > 0.6:
				check(app.modal.camp != null and str(app.modal.camp.code) == "0.5.1", "the camp's banner carries the new crest")
				press("clan_sheet_close")
				bob.clan_find("wolf")
				_go("bob_find")
		"bob_find":
			if not bob.clan_list.is_empty():
				check(str(bob.clan_list[0].tag) == "WOLF" and str(bob.clan_list[0].join) == "request", "Bob finds the Wolves")
				bob.clan_join(clan_id)
				_go("request")
		"request":
			if app.social.clan_requests() == 1:
				check(true, "Bob's request reaches Alice")
				_go("accept0")
		"accept0":
			if t_phase > 0.5:
				press("clan_open_members")
				_go("accept")
		"accept":
			if t_phase > 0.6:
				check(btn("clan_accept_" + str(bob.me.pid)) != null and has_text(app.modal, "REQUESTS"), "REQUESTS shows Bob with ACCEPT")
				_shot("clan_request")
				press("clan_accept_" + str(bob.me.pid))
				_go("joined")
		"joined":
			if bob.in_clan() and int(app.social.clan.get("n", 0)) == 2:
				check(str(bob.my_tag()) == "WOLF" and str(bob.clan.role) == "member" and bob.my_crest() == "0.5.1", "Bob is in, a member, tagged WOLF, the lion crest")
				bob.say("clan", "hello wolves")
				_go("clan_line")
		"clan_line":
			if not app.social.lines.clan.is_empty() and str(app.social.lines.clan[-1].get("x", "")) == "hello wolves":
				check(str(app.social.lines.clan[-1].get("ct", "")) == "WOLF" and str(app.social.lines.clan[-1].get("cc", "")) == "0.5.1",
					"Bob's clan line reaches Alice, with his tag and crest")
				bob.clan_ask("golem")
				_go("asked")
		"asked":
			if app.social.ask_open(str(bob.me.pid), "golem") and app.social.lines.clan.any(func(l): return str(l.get("ask", "")) == "golem"):
				check(true, "Bob asks for a Golem shard: on Alice's clan state and in clan chat")
				_go("open_chat")
			elif t_phase > 8.0:
				check(false, "Bob's shard request reaches Alice")
				_go("open_chat")
		"open_chat":
			if t_phase > 0.5:
				press("clan_chat")
				check(app.modal is ChatPanel and str(app.modal.ch) == "clan", "CLAN CHAT opens the chat on its CLAN tab")
				_go("chat_seen")
		"chat_seen":
			if t_phase > 0.6:
				check(has_text(app.modal, "hello wolves") and btn("chat_name", null, "[WOLF] Bob") != null, "the line shows, his name as [WOLF] Bob")
				var gb := btn("chat_give")
				check(gb != null and gb.text.begins_with("GIVE") and not gb.disabled, "his request's line: GIVE (she holds a Golem shard) -- %s" % (gb.text if gb != null else "none"))
				_shot("clan_chat")
				_gold0 = int(app.profile.d.gold)
				press("chat_give")
				_go("given")
		"given":
			if not app.social.ask_open(str(bob.me.pid), "golem") and app.profile.shards_of("golem") == 0 and int(app.profile.d.gold) > _gold0:
				check(app.social.lines.clan.any(func(l): return str(l.get("x", "")).contains("gave Bob a Golem shard")) and btn("chat_give") == null,
					"GIVE: the shard is Bob's, Alice's account (pulled) has its melt gold (+%d), the line in chat, the button gone" % (int(app.profile.d.gold) - _gold0))
				_go("tap_bob")
			elif t_phase > 10.0:
				check(false, "Alice gives Bob the shard (ask open %s, her shards %d, gold %d)" % [str(app.social.ask_open(str(bob.me.pid), "golem")),
					app.profile.shards_of("golem"), int(app.profile.d.gold)])
				_go("tap_bob")
		"tap_bob":
			if t_phase > 0.4:
				press("chat_name", "[WOLF] Bob")
				_go("card")
		"card":
			if t_phase > 0.6:
				check(has_text(app.modal, "[WOLF]") and btn("card_clan_invite") == null, "his name card shows [WOLF] (no INVITE TO CLAN: he's in one)")
				_shot("clan_name_card")
				_go("to_clan2")
		"to_clan2":
			if t_phase > 0.4:
				app.open_clan()
				_go("lfg")
		"lfg":
			if t_phase > 0.6:
				press("clan_lfg")
				_go("lfg_up")
		"lfg_up":
			if not bob.lfg_call(str(app.social.me.pid)).is_empty():
				check(app.social.lines.clan.any(func(l): return str(l.get("lfg", "")) == str(app.social.me.pid)), "LOOKING FOR GROUP: her call reaches Bob, a line in clan chat")
				bob.lfg_join(str(app.social.me.pid))
				_go("lfg_joined")
			elif t_phase > 8.0:
				check(false, "her LFG call reaches Bob")
				_go("lfg_joined")
		"lfg_joined":
			if app.social.in_party() and app.social.party_size() == 2:
				check(app.social.is_leader() and int(app.social.party.get("max", 0)) == 5 and bob.in_my_party(str(app.social.me.pid)),
					"Bob JOINs: a party of 2 (of 5), led by Alice")
				_go("lfg_view")
			elif t_phase > 8.0:
				check(false, "Bob joins her party from her call")
				_go("lfg_view")
		"lfg_view":
			if t_phase > 0.8:
				check(has_text(app.modal, "CALLING YOUR CLAN") and btn("clan_lfg_cancel") != null, "her call: CALLING YOUR CLAN, CANCEL")
				_shot("clan_lfg")
				press("clan_open_league")
				_go("league")
		"league":
			if t_phase > 1.0:
				check(not app.social.league.is_empty() and has_text(app.modal, "CLAN LEAGUE") and has_text(app.modal, "100 GEMS")
					and has_text(app.modal, "No clan has points yet"), "LEAGUE: the table (no points yet this week), the prizes")
				_shot("clan_league")
				press("clan_sheet_close")
				press("clan_open_members")
				_go("members")
		"members":
			if t_phase > 0.6:
				check(has_text(app.modal, "0 pts") and btn("clan_manage_" + str(bob.me.pid)) != null, "MEMBERS: points this week, MANAGE")
				_shot("clan_members")
				_go("manage")
		"manage":
			if t_phase > 0.3:
				press("clan_manage_" + str(bob.me.pid))
				_go("officer")
		"officer":
			if t_phase > 0.5:
				check(btn("clan_m_officer") != null and btn("clan_m_kick") != null and btn("clan_m_lead") != null, "MANAGE: make officer, make leader, remove")
				_shot("clan_manage")
				_go("press_officer")
		"press_officer":
			if t_phase > 0.4:
				press("clan_m_officer")
				_go("is_officer")
		"is_officer":
			if str(bob.clan.get("role", "")) == "officer":
				check(true, "Bob is an officer")
				app.close_modal()
				# 0.31.164 (Kevin: "5v5 only"): no war map battle to take the clan into (PLAY is the offline 5v5) -- the match's
				# plates and names with the tag went with Siege's online matches; Bob leaves the clan from here
				bob.clan_leave()
				_go("left")
		"left":
			if not bob.in_clan() and int(app.social.clan.get("n", 0)) == 1:
				check(bob.clan_cool_left() > 23 * 3600, "Bob left: Alice's clan is back to 1, Bob waits 24 hours")
				_go("end")
		"end":
			if t_phase > 0.5:
				return _finish()
	return false

func _finish() -> bool:
	if server_pid > 0:
		OS.kill(server_pid)
	print("CLANS_UI_PASS" if fails.is_empty() else "CLANS_UI_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
	return true
