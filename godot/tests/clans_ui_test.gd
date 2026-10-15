extends SceneTree
# 0.31.134 (Crown War step 1): clans through the app's real buttons, against the real server (its own process, port
# 8118), in REAL time. Alice is the app (an account with 25,000 gold); Bob is a second phone (scripts/meta/social.gd +
# a raw match socket). Home's SOCIAL opens FRIENDS with a CLAN tab; Alice starts [WOLF] Iron Wolves of House Stags
# (the server takes 10,000 gold and her app shows it); Bob finds and joins it; Bob's clan line reaches Alice's CLAN
# chat with his tag; she makes him an officer from MANAGE; his tag is on her chat and on his name card, and the match's
# lobby and "pn" carry it for everyone in the match; he leaves and waits 24 hours.
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
	if t > 150.0:
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
				check(has_text(app.modal, "START A CLAN") and has_text(app.modal, "FIND A CLAN") and has_text(app.modal, "10,000"),
					"not in a clan: FIND A CLAN and START A CLAN (10,000 gold)")
				check(btn("clan_start") != null and btn("clan_house_lions") != null and btn("clan_house_stags") != null and btn("clan_house_ravens") != null,
					"the three houses to pick from")
				_shot("clan_none")
				(app.modal._fields["new_name"] as LineEdit).text = "Iron Wolves"
				(app.modal._fields["new_tag"] as LineEdit).text = "wolf"
				(app.modal._fields["new_tag"] as LineEdit).text_changed.emit("wolf")
				press("clan_house_stags")
				_go("pick_join")
		"pick_join":
			if t_phase > 0.3:
				press("clan_join_mode_request")
				_go("lv_up")
		"lv_up":
			if t_phase > 0.3:
				check(str(app.modal._join) == "request" and str(app.modal._house) == "stags", "House Stags, join by request")
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
				check(str(c.tag) == "WOLF" and str(c.name) == "Iron Wolves" and str(c.house) == "stags" and str(c.join) == "request"
					and int(c.min_lv) == 2 and str(c.role) == "leader", "Alice leads [WOLF] Iron Wolves (House Stags, by request, level 2+)")
				clan_id = str(c.id)
				_go("gold")
		"gold":
			if int(app.profile.d.gold) == 15000:
				check(true, "the server took 10,000 gold and her app shows 15,000")
				_go("mine")
			elif t_phase > 8.0:
				check(false, "her gold is 15,000 after the clan (it's %d)" % int(app.profile.d.gold))
				_go("mine")
		"mine":
			if t_phase > 0.6:
				check(has_text(app.modal, "Iron Wolves") and has_text(app.modal, "HOUSE STAGS") and btn("clan_chat") != null and btn("clan_leave") != null
					and btn("clan_disband") != null and has_text(app.modal, "INVITE A PLAYER"), "her clan window: the banner, CLAN CHAT, invite, LEAVE, DISBAND")
				_shot("clan_mine")
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
				_go("accept")
		"accept":
			if t_phase > 0.6:
				check(btn("clan_accept_" + str(bob.me.pid)) != null and has_text(app.modal, "REQUESTS"), "REQUESTS shows Bob with ACCEPT")
				_shot("clan_request")
				press("clan_accept_" + str(bob.me.pid))
				_go("joined")
		"joined":
			if bob.in_clan() and int(app.social.clan.get("n", 0)) == 2:
				check(str(bob.my_tag()) == "WOLF" and str(bob.clan.role) == "member", "Bob is in, a member, tagged WOLF")
				bob.say("clan", "hello wolves")
				_go("clan_line")
		"clan_line":
			if not app.social.lines.clan.is_empty() and str(app.social.lines.clan[-1].get("x", "")) == "hello wolves":
				check(str(app.social.lines.clan[-1].get("ct", "")) == "WOLF", "Bob's clan line reaches Alice, with his tag")
				_go("open_chat")
		"open_chat":
			if t_phase > 0.5:
				press("clan_chat")
				check(app.modal is ChatPanel and str(app.modal.ch) == "clan", "CLAN CHAT opens the chat on its CLAN tab")
				_go("chat_seen")
		"chat_seen":
			if t_phase > 0.6:
				check(has_text(app.modal, "hello wolves") and btn("chat_name", null, "[WOLF] Bob") != null, "the line shows, his name as [WOLF] Bob")
				_shot("clan_chat")
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
				_go("manage")
		"manage":
			if t_phase > 0.6:
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
				_go("play")
		"play":
			if t_phase > 0.5:
				press("play")
				# 0.31.145: PLAY opens the war map; its QUICK BATTLE is the match from matchmaking
				check(app.modal != null and str(app.modal.get_script().resource_path).ends_with("war_table.gd") and app.siege == null,
					"PLAY opens the war map (in a clan, not in a party)")
				press("war_quick")
				check(app.siege != null and app.modal == null, "...its QUICK BATTLE starts a match")
				_ws("match_bob", {"t":"hello", "v":Net.VERSION, "name":"bob", "build":"0.31.134-fatebound", "pred":false,
					"acct":accts.bob[0], "key":accts.bob[1]})
				_go("in_match")
		"in_match":
			if app.siege != null and app.siege.sim != null and app.siege.hud != null and str(app.siege.hud.player_id) != "" and is_instance_valid(app.siege.view):
				if t_phase > (3.0 if shots != "" else 0.2):
					var mine := ""
					for b in app.siege.view.bars():
						if str(b.get("name", "")).ends_with("Alice"):
							mine = str(b.name)
					check(mine == "[WOLF] Alice", "her own plate in the match reads [WOLF] Alice (%s)" % mine)
					_shot("clan_match")
					_go("match")
		"match":
			var lob := _raw_got("match_bob", "lobby")
			var pn := _raw_got("match_bob", "pn")
			if not pn.is_empty() and not lob.is_empty():
				var ct: Dictionary = pn[-1].get("ct", {})
				check((lob[0].get("ct", []) as Array).has("WOLF"), "the lobby carries Bob's tag")
				check(ct.values().has("WOLF"), "the match's names carry his tag for everyone: %s" % str(ct))
				(raw.match_bob.ws as WebSocketPeer).close()
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
