extends SceneTree
# 0.31.111: the chat, Friends, the party and quick chat through the app's real buttons, against the real server (its
# own process, port 8095), in REAL time. Alice is the app; Bob is a second phone (scripts/meta/social.gd + a raw match
# socket). Bob's line shows on Home's chat line; Alice opens the chat, sends a line, taps Bob's name and adds him; he
# accepts; she opens Friends from Home and invites him; he joins; Home shows the party (0.31.164: the rest -- a war map
# battle with the party, the quick chat in it -- went with Siege's online matches); 0.31.149 (Kevin:
# "Remove the quick play so the player needs to choose where to fight. Maybe show hot zones where players are actively
# fighting and players can jump right into that battle"): Bob joins The Lion Guard and starts a battle; it shows under
# Alice's war map (BATTLES NOW); she has no clan, so JOIN LIONS puts her in The Lion Guard and into the battle, and as the
# party's leader she takes Bob along ("go" with the battle); both are seated on one side; Alice's quick chat reaches Bob
# and Bob's shows over his head on her HUD.
# With a display and SHOT_DIR set, screenshots of each window go there.
#   godot --headless --path godot -s res://tests/social_ui_test.gd
const App = preload("res://scripts/app/siege_app.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const ClientSocial = preload("res://scripts/meta/social.gd")
const ChatPanel = preload("res://scripts/app/chat_panel.gd")
const FriendsPanel = preload("res://scripts/app/friends_panel.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const WarMap = preload("res://scripts/meta/war_map.gd")

var port := 8095
var server_pid := -1
var fails: Array = []
var phase := "boot"
var t := 0.0
var t_phase := 0.0
var raw := {}
var accts := {}
var app
var bob
var bob_unit := ""
var lion_tid := ""
var bid := ""
var shots := ""

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
	var sd := OS.get_user_data_dir().path_join("socialui-srv-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(sd)
	OS.set_environment("SIEGE_PORT", str(port))
	OS.set_environment("SIEGE_HOST", "127.0.0.1")
	OS.set_environment("SIEGE_LOBBY", "1.0")
	OS.set_environment("SIEGE_WAR_LOBBY", "2.0")           # (0.31.149: the party's match is a battle on the war map)
	OS.set_environment("STATE_DIRECTORY", sd)
	OS.set_environment("SIEGE_MIN_BUILD", "off")
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:%d" % port)
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
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED and not bool(r.sent) and t - float(r.get("dialed", 0.0)) > 0.5:
			# 0.31.144: the server (its own process) may not be listening yet on a slow machine -- dial again
			r.dialed = t
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
	if t > 120.0:
		check(false, "timed out in phase %s" % phase)
		return _finish()
	match phase:
		"boot":
			if t_phase > 1.5:
				for n in ["alice", "bob"]:
					var imp := Profile.defaults()
					imp.name = n.capitalize()
					imp.title = "title_victor"
					imp.owned = ["title_victor"]
					_ws("eco_" + n, {"t":"eco", "v":Net.VERSION, "new":true, "import":imp})
				_go("accounts")
		"accounts":
			for n in ["alice", "bob"]:
				var e := _raw_got("eco_" + n, "eco")
				if not e.is_empty() and not accts.has(n):
					accts[n] = [str(e[0].acct), str(e[0].key)]
			if accts.size() == 2:
				var base := "user://socialui-%d" % Time.get_ticks_usec()
				var p = Profile.new(base + "-profile.json", base + "-none.json")
				p.load_or_create()
				p.d.name = "Alice"
				p.d.account = {"id":accts.alice[0], "key":accts.alice[1], "seq":0}
				p.d.tutorial_done = true
				p.d.settings["war_tour"] = true          # (0.31.147: the Herald's tour has its own test)
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
				bob.war_went.connect(func(m): bob.set_meta("seen_war_go", m))
				bob.set_active(true)
				_go("online")
		"online":
			if app.social.online() and bob.online():
				check(app.chat_ticker.is_visible_in_tree(), "Home shows the chat line")
				bob.say("global", "hi from bob")
				_go("ticker")
		"ticker":
			if app.chat_ticker._text.text == "hi from bob":
				check(app.chat_ticker._name.text == "Bob:" and app.chat_ticker._badge.visible, "Bob's line on Home's chat line, with an unread count")
				_shot("social_home_ticker")
				_go("open_chat")
		"open_chat":
			if t_phase > 0.3:
				press("chat_ticker")
				check(app.modal is ChatPanel and int(app.social.unread.global) == 0, "the chat line opens the chat (read)")
				check(btn("chat_name", null, "Bob") != null and has_text(app.modal, "hi from bob"), "Bob's line in the chat, his name a button")
				app.modal._input.text = "hello bob"
				press("chat_send")
				_go("sent")
		"sent":
			if not bob.lines.global.is_empty() and str(bob.lines.global[-1].x) == "hello bob":
				check(str(bob.lines.global[-1].n) == "Alice", "Alice's line from the chat window reaches Bob")
				check(btn("chat_name", null, "Alice") != null, "her own line shows in her chat")
				_shot("social_chat")
				_go("tap_name")
		"tap_name":
			if t_phase > 0.5:
				press("chat_name", "Bob")
				check(btn("card_add") != null and btn("card_block") != null and btn("card_report") != null, "tapping Bob's name: ADD FRIEND, BLOCK, REPORT")
				_shot("social_name_card")
				_go("card_add")
		"card_add":
			if t_phase > 0.5:
				press("card_add")
				_go("request")
		"request":
			if not bob.rin.is_empty():
				check(str(bob.rin[0].n) == "Alice", "Bob gets Alice's friend request")
				bob.add(str(bob.rin[0].pid))
				_go("friends")
		"friends":
			if app.social.relation(str(bob.me.pid)) == "friend":
				check(true, "Alice and Bob are friends")
				app.close_modal()
				_go("open_friends")
		"open_friends":
			if t_phase > 0.3:
				press("tab_alliance")
				check(app.modal is FriendsPanel, "ALLIANCE in the tab bar opens Friends")
				_go("invite")
		"invite":
			if t_phase > 0.3:
				check(btn("friend_" + str(bob.me.pid)) != null and has_text(app.modal, "Online"), "Bob in her friends list, online")
				check(has_text(app.modal, ClientSocial.code_of(str(app.social.me.pid))), "her friend code shows")
				_shot("social_friends")
				_go("press_invite")
		"press_invite":
			if t_phase > 0.5:
				press("friend_invite_" + str(bob.me.pid))
				_go("bob_join")
		"bob_join":
			if not bob.invites.is_empty():
				bob.join(bob.invites.keys()[0])
				_go("party")
		"party":
			if app.social.party_size() == 2:
				if t_phase > 0.5:
					check(has_text(app.modal, "YOUR PARTY") and btn("party_play") != null, "Friends shows the party with PLAY TOGETHER")
					_shot("social_party")
					_go("close_party")
		"close_party":
			if t_phase > 0.5:
				app.close_modal()
				_go("home_party")
		"home_party":
			if t_phase > 0.5:
				# 0.31.164 (Kevin: "5v5 only"): PLAY is the offline 5v5 -- no party count on it, and no war map battle to take the
				# party into (the battle, the seating and the in-match quick chat were Siege's online matches)
				check(has_text(app.content, "PARTY 2/4") and has_text(app.content, "PLAY") and not has_text(app.content, "PLAY ×2"),
					"Home shows the party (0.31.139: at the top); PLAY has no party count")
				_shot("social_home_party")
				_go("end")
		"press_play":
			if t_phase > 0.6:
				bob.clan_join("h_lions")                 # (0.31.148: the Lions' own clan)
				_go("bob_clan")
		"bob_clan":
			if bob.in_clan():
				for id in WarMap.T:
					if lion_tid == "" and not WarMap.is_home(id) and WarMap.neighbours(id).has("home_lions"):
						lion_tid = id
				bob.war_go(lion_tid, false)
				_go("bob_battle")
		"bob_battle":
			var gone: Dictionary = bob.get_meta("seen_war_go", {})
			if bool(gone.get("ok", false)):
				bid = str(gone.bid)
				check(bob.in_house_clan() and bid != "", "Bob joins The Lion Guard and starts a battle for %s" % WarMap.name_of(lion_tid))
				press("play")
				_go("party_map")
			elif not gone.is_empty():
				check(false, "Bob's battle starts (%s)" % str(gone.get("why", "")))
				return _finish()
		"party_map":
			# 0.31.146: a party's PLAY opens the war map too (0.31.147: after Home's push into the table)
			var tb = app.modal if is_instance_valid(app.modal) and str(app.modal.get_script().resource_path).ends_with("war_table.gd") else null
			if tb != null and not tb._intro_on and not app.social.war.is_empty() and btn("war_hot_fight_" + lion_tid) != null and t_phase > 0.5:
				check(btn("war_quick") == null and has_text(tb, "BATTLES NOW") and has_text(tb, WarMap.name_of(lion_tid).to_upper())
					and btn("war_hot_fight_" + lion_tid).text == "JOIN LIONS", "no QUICK BATTLE; BATTLES NOW shows Bob's battle with JOIN LIONS (Alice has no clan)")
				_shot("social_hot_zone")
				press("war_hot_fight_" + lion_tid)
				_go("go")
			elif t_phase > 15.0:
				check(false, "Bob's battle shows under Alice's war map")
				return _finish()
		"go":
			if bob.party_play != "" and bob.party_war != "":
				check(app.siege != null and str(app.siege.war_bid) == bid and str(bob.party_war) == bid and app.social.in_house_clan()
					and str(app.social.clan.get("house", "")) == "lions",
					"JOIN LIONS: Alice into The Lion Guard and the battle -- the party's leader, she takes Bob along (\"go\" with the battle)")
				_ws("match_bob", {"t":"hello", "v":Net.VERSION, "name":"bob", "build":"0.31.149-fatebound", "pred":false,
					"acct":accts.bob[0], "key":accts.bob[1], "war":bid})
				_go("seated")
			elif t_phase > 15.0:
				check(false, "Alice goes into the battle and Bob is told to follow")
				return _finish()
		"seated":
			var w := _raw_got("match_bob", "welcome")
			if not w.is_empty() and app.siege != null and app.siege.sim != null and app.siege.hud != null and str(app.siege.hud.player_id) != "":
				bob_unit = str(w[0].you)
				var mine := str(app.siege.hud.player_id)
				check(mine[0] == bob_unit[0], "the party is on one side: Alice %s, Bob %s" % [mine, bob_unit])
				_go("open_qc")
		"open_qc":
			if t_phase > (2.0 if shots != "" else 0.1):
				app.siege.hud._toggle_qc()
				check(app.siege.hud.qc_panel.visible, "the horn opens the quick chat")
				_shot("social_quick_chat")
				_go("say_qc")
		"say_qc":
			if t_phase > 0.5:
				press("qc_1")
				_go("qc")
		"qc":
			var q := _raw_got("match_bob", "qc")
			if not q.is_empty():
				check(int(q[0].i) == 1 and str(q[0].u) == str(app.siege.hud.player_id), "Alice's \"Defend the gate!\" reaches Bob")
				(raw.match_bob.ws as WebSocketPeer).put_packet(Net.encode({"t":"qc", "i":5}))
				_go("qc_back")
		"qc_back":
			var hud = app.siege.hud
			var seen := false
			for p in hud._pings:
				if str(p.u) == bob_unit and int(p.i) == 5:
					seen = true
			if seen:
				check(true, "Bob's \"Follow me!\" shows on Alice's HUD")
				_shot("social_ping")
				_go("end")
			elif t_phase > 5.0:
				check(false, "Bob's quick chat shows on Alice's HUD")
				return _finish()
		"end":
			if t_phase > 0.5:
				return _finish()
	return false

func _finish() -> bool:
	if server_pid > 0:
		OS.kill(server_pid)
	print("SOCIAL_UI_PASS" if fails.is_empty() else "SOCIAL_UI_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
	return true
