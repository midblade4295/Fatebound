extends SceneTree
# 0.31.135 (Crown War step 2): the war map through the app's real buttons, against the real server (its own process,
# port 8121), in REAL time. Alice is the app, leader of [LION] Lion Hearts (House Lions, which holds the Mill); Bob is a
# second phone in her clan; Sam leads [STAG] Stag Party (House Stags, which holds the Old Tower). Home's CROWN WAR opens
# the war table; tapping the Old Tower (where it is drawn) shows it held by the Stags with ATTACK; the High Pass isn't
# linked to Lions land, so no ATTACK there. ATTACK (calling the clan) takes Alice's app into the battle -- Bob is
# called, Sam is alarmed -- a 6-second battle the attackers win (SIEGE_TEST_SCORE); the results show what it did to the
# clan's bar and WAR MAP takes her back to the table, on the Tower, with the bar and 4 attempts. Then Bob attacks the
# Ford and calls the clan: a JOIN banner drops on Alice's screen and the table shows the battle with JOIN THE BATTLE.
# With a display and SHOT_DIR set, screenshots go there.
#   godot --headless --path godot -s res://tests/war_ui_test.gd
const App = preload("res://scripts/app/siege_app.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const ClientSocial = preload("res://scripts/meta/social.gd")
const WarTable = preload("res://scripts/app/war_table.gd")
const SocialUIRef = preload("res://scripts/app/social_ui.gd")
const EcoAccounts = preload("res://server/eco_accounts.gd")
const Social = preload("res://server/social.gd")
const Leaderboard = preload("res://server/leaderboard.gd")

var port := 8121
var server_pid := -1
var fails: Array = []
var phase := "boot"
var t := 0.0
var t_phase := 0.0
var accts := {}
var app
var bob
var sam
var shots := ""
var bid := ""

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func btn(key: String, node: Node = null) -> Button:
	# the app's buttons carry "action_key", the match HUD's "key"
	if node == null:
		node = root
	if node is Button and (str(node.get_meta("action_key", "")) == key or str(node.get_meta("key", "")) == key) and node.is_visible_in_tree():
		return node
	for c in node.get_children():
		var r := btn(key, c)
		if r != null:
			return r
	return null

func press(key: String) -> bool:
	var b := btn(key)
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
	var sd := OS.get_user_data_dir().path_join("warui-srv-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(sd)
	var eco := EcoAccounts.new(sd)
	for n in ["Alice", "Bob", "Sam"]:
		var e: Dictionary = eco.create({})
		e.p.d.name = n
		e.p.d.level = 10
		e.p.d.tutorial_done = true
		e.p.save()
		accts[n] = [str(e.id), str(e.key_plain)]
	var now := int(Time.get_unix_time_from_system())
	var pa := Social.pid_of(accts.Alice[0])
	var pb := Social.pid_of(accts.Bob[0])
	var ps := Social.pid_of(accts.Sam[0])
	var clans := {"clion": {"id":"clion", "name":"Lion Hearts", "tag":"LION", "house":"lions", "join":"open", "min_lv":1, "leader":pa,
		"officers":[], "members":{pa: now, pb: now}, "req":{}, "created":now},
		"cstag": {"id":"cstag", "name":"Stag Party", "tag":"STAG", "house":"stags", "join":"open", "min_lv":1, "leader":ps,
		"officers":[], "members":{ps: now}, "req":{}, "created":now}}
	_write(sd.path_join("clans.json"), {"v":1, "clans":clans, "inv":{}, "cool":{}})
	_write(sd.path_join("world.json"), {"v":1, "week":Leaderboard.week_of(now), "owners":{
		"mill": {"h":"lions", "c":"clion", "ct":"LION", "cn":"Lion Hearts", "at":now},
		"tower": {"h":"stags", "c":"cstag", "ct":"STAG", "cn":"Stag Party", "at":now}}, "bars":{}, "attempts":{}, "tally":{}, "last":{}})
	OS.set_environment("SIEGE_PORT", str(port))
	OS.set_environment("SIEGE_HOST", "127.0.0.1")
	OS.set_environment("SIEGE_LOBBY", "1.0")
	OS.set_environment("SIEGE_WAR_LOBBY", "4.0")
	OS.set_environment("SIEGE_TEST_MATCH_S", "6")
	OS.set_environment("SIEGE_TEST_SCORE", "0:1")
	OS.set_environment("STATE_DIRECTORY", sd)
	OS.set_environment("SIEGE_MIN_BUILD", "off")
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:%d" % port)
	OS.set_environment("FB_ECO", "1")
	server_pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://server/siege_server.gd"])
	check(server_pid > 0, "server process started")

func _write(path: String, d: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()

func _phone(n: String, base: String):
	var p = Profile.new(base + "-%s.json" % n, base + "-none.json")
	p.load_or_create()
	p.d.account = {"id":accts[n][0], "key":accts[n][1], "seq":0}
	var so = ClientSocial.new()
	so.url = "ws://127.0.0.1:%d" % port
	so.setup(p)
	root.add_child(so)
	so.war_went.connect(func(m): so.set_meta("seen_war_go", m))
	so.war_called.connect(func(m): so.set_meta("seen_war_call", m))
	so.war_alarmed.connect(func(m): so.set_meta("seen_war_alarm", m))
	so.set_active(true)
	return so

func _go(next: String) -> void:
	phase = next
	t_phase = 0.0

func _shot(name: String) -> void:
	if shots == "":
		return
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(shots.path_join(name + ".png"))

func _table():
	return app.modal if is_instance_valid(app.modal) and app.modal is WarTable else null

func _process(delta: float) -> bool:
	t += delta
	t_phase += delta
	if t > 150.0:
		check(false, "timed out in phase %s" % phase)
		return _finish()
	match phase:
		"boot":
			if t_phase > 1.5:
				var base := "user://warui-%d" % Time.get_ticks_usec()
				var p = Profile.new(base + "-profile.json", base + "-none.json")
				p.load_or_create()
				p.d.name = "Alice"
				p.d.level = 10
				p.d.account = {"id":accts.Alice[0], "key":accts.Alice[1], "seq":0}
				p.d.tutorial_done = true
				p.save()
				app = App.new()
				app.profile_path = base + "-profile.json"
				app.legacy_path = base + "-none.json"
				root.add_child(app)
				app.social.set_active(true)
				bob = _phone("Bob", base)
				sam = _phone("Sam", base)
				_go("online")
		"online":
			if app.social.online() and app.social.in_clan() and bob.online() and sam.online() and t_phase > 1.0:
				check(app.social.has_war, "the server has the war map")
				_go("home")
		"home":
			if t_phase > 0.6:
				var hb := btn("home_war")
				check(hb != null and hb.text.contains("HOUSE LIONS"), "Home: CROWN WAR · HOUSE LIONS at the top (in a clan)")
				_shot("war_home")
				press("home_war")
				_go("table")
		"table":
			var tb = _table()
			if tb != null and not app.social.war.is_empty() and t_phase > (2.5 if shots != "" else 0.6):
				check(has_text(tb, "ATTEMPTS 5/5") and has_text(tb, "WEEK ENDS IN") and has_text(tb, "THE WAR TABLE"),
					"the war table: the week's end, 5 attempts, how it works")
				check(not has_text(tb, "Saltport") and not has_text(tb, "[STAG]"), "a clean table: no names until a place is picked")
				press("war_names")
				var hold: PackedColorArray = tb._land_mat.get_shader_parameter("holder")
				var ti: int = tb.LandData.IDS.find("tower")
				check(hold.size() == 18 and hold[ti].a > 0.5 and hold[ti].is_equal_approx(Color(SocialUIRef.house_color("stags"), 1.0))
					and hold[tb.LandData.IDS.find("pass")].a < 0.5, "the Tower's land in Stags green (the High Pass nobody's)")
				check((tb._tiles.tower.node as Node3D).get_child(0).scene_file_path.ends_with("war/tower.glb")
					and (tb._tiles.home_lions.node as Node3D).get_child(0).scene_file_path.ends_with("war/home_lions.glb")
					and tb._tiles.lake.node == null, "the miniatures stand in the land (Silver Lake is the water itself)")
				check(tb.region_at(tb.screen_of("woods")) == "woods" and tb.region_at(Vector2(4, 50)) == "", "a point on Kingswood's land is Kingswood; the sea is nobody's")
				_shot("war_table")
				# tap the High Pass where the table draws it
				var at: Vector2 = tb.screen_of("pass")
				check(tb.pick_at(at) == "pass" and str(tb.sel) == "pass", "a tap on the High Pass picks it (%s)" % str(at))
				_go("pass")
		"pass":
			if t_phase > 0.5:
				var tb = _table()
				check(has_text(tb, "[STAG]") and has_text(tb, "[LION]") and has_text(tb, "Old Tower") and has_text(tb, "Saltport"),
					"NAMES: each place is named on the table, the holders' tags under theirs")
				if phase == "pass" and shots != "":
					_shot("war_names")
				press("war_names")
				var ab := btn("war_attack")
				check(has_text(tb, "HIGH PASS") and ab != null and ab.disabled and has_text(tb, "isn't linked"),
					"the High Pass: ATTACK off -- it isn't linked to Lions land")
				var at: Vector2 = tb.screen_of("tower")
				check(tb.pick_at(at) == "tower", "a tap on the Old Tower picks it")
				_go("tower")
		"tower":
			if t_phase > (1.0 if shots != "" else 0.5):
				var tb = _table()
				var ab := btn("war_attack")
				check(has_text(tb, "OLD TOWER") and has_text(tb, "Held by House Stags") and has_text(tb, "[STAG] Stag Party") and ab != null and not ab.disabled
					and btn("war_call_toggle") != null and has_text(tb, "1,000 points take it"), "the Old Tower: held by [STAG], 1,000 to take it, ATTACK and CALL CLAN")
				_shot("war_tower")
				press("war_attack")
				_go("going")
		"going":
			if app.siege != null:
				bid = str(app.siege.war_bid)
				check(bid != "" and app.modal == null, "ATTACK: the app goes into the battle (%s)" % bid)
				_go("calls")
		"calls":
			var call: Dictionary = bob.get_meta("seen_war_call", {})
			var alarm: Dictionary = sam.get_meta("seen_war_alarm", {})
			if not call.is_empty() and not alarm.is_empty():
				check(str(call.bid) == bid and str(call.by) == "Alice" and str(alarm.bid) == bid, "Bob is called, Sam is alarmed")
				_go("lobby")
		"lobby":
			if app.siege.sim != null:
				check(false, "the battle's countdown shows before it starts")
				_go("seated")
			elif is_instance_valid(app.siege.lobby) and int(app.siege.lobby_msgs) > 0 and t_phase > (1.0 if shots != "" else 0.2):
				check(has_text(app.siege.lobby, "BATTLE FOR OLD TOWER") and has_text(app.siege.lobby, "House Lions attack House Stags"),
					"the countdown says which battle: Lions attack Stags at the Old Tower")
				_shot("war_lobby")
				_go("seated")
		"seated":
			if app.siege.sim != null and app.siege.hud != null and str(app.siege.hud.player_id) != "" and t_phase > (2.0 if shots != "" else 0.2):
				check(str(app.siege.war_info.get("tid", "")) == "tower" and str(app.siege.hud.player_id).begins_with("r"),
					"the battle for the Tower, Alice on the attackers' (red) side (%s)" % str(app.siege.hud.player_id))
				_shot("war_battle")
				_go("result")
		"result":
			var hud = app.siege.hud if app.siege != null else null
			if hud != null and btn("war_map") != null and not app.siege.war_result.is_empty() and t_phase > 1.0:
				check(not has_text(hud, "PLAY AGAIN") and has_text(hud, "BATTLE FOR OLD TOWER") and has_text(hud, "/ 1000 to take it"),
					"the results: the battle's frame (crowns, points, the bar) and WAR MAP instead of PLAY AGAIN")
				_shot("war_result")
				press("war_map")
				_go("back")
		"back":
			var tb = _table()
			if app.siege == null and tb != null and t_phase > (1.5 if shots != "" else 0.6):
				check(str(tb.sel) == "tower" and has_text(tb, "ATTEMPTS 4/5"), "WAR MAP: back at the table, on the Tower, 4 attempts left")
				check(has_text(tb, "[LION]") and (tb._sheet as Node).find_children("*", "ProgressBar", true, false).size() >= 1,
					"the Lions' bar on the Tower")
				_shot("war_back")
				bob.war_go("ford", true)
				_go("banner")
		"banner":
			var go := btn("war_banner_go")
			if go != null and t_phase > 0.5:
				check(go.text == "JOIN" and has_text(app, "BATTLE FOR THE FORD") and has_text(app, "Bob calls the clan"),
					"Bob attacks the Ford: a JOIN banner drops on Alice's screen")
				var tb = _table()
				tb.select("ford")
				_go("ford")
		"ford":
			if t_phase > 0.6:
				var tb = _table()
				var bat: PackedFloat32Array = tb._land_mat.get_shader_parameter("battle")
				check(bat[tb.LandData.IDS.find("ford")] > 0.5 and (tb._tiles.ford.swords as Sprite3D).visible and btn("war_join") != null and has_text(tb, "BATTLE ON"),
					"the map: the Ford's land pulses, crossed swords over it, JOIN THE BATTLE")
				# a pinch brings the map closer, then a drag moves it (no pick)
				var c: Vector2 = tb._vpc.size * 0.5
				var was: String = tb.sel
				tb._on_table_input(_touch_ev(0, c - Vector2(40, 0), true))
				tb._on_table_input(_touch_ev(1, c + Vector2(40, 0), true))
				tb._on_table_input(_drag_ev(1, c + Vector2(120, 0), Vector2(80, 0)))
				tb._on_table_input(_touch_ev(1, c + Vector2(120, 0), false))
				tb._on_table_input(_touch_ev(0, c - Vector2(40, 0), false))
				var zoomed: float = tb._zoom
				tb._on_table_input(_touch_ev(0, c, true))
				tb._on_table_input(_drag_ev(0, c + Vector2(30, 40), Vector2(30, 40)))
				tb._on_table_input(_drag_ev(0, c + Vector2(60, 80), Vector2(30, 40)))
				tb._on_table_input(_touch_ev(0, c + Vector2(60, 80), false))
				check(tb.sel == was and zoomed > 1.3 and tb._pan.length() > 0.0, "a pinch zooms in (%.2f), a drag moves the map without picking (pan %s)" % [zoomed, str(tb._pan)])
				_shot("war_banner")
				press("war_banner_no")
				_go("end")
		"end":
			if t_phase > 0.5:
				check(btn("war_banner_go") == null, "✕ dismisses the banner")
				return _finish()
	return false

func _touch_ev(i: int, at: Vector2, down: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = at
	e.pressed = down
	return e

func _drag_ev(i: int, at: Vector2, rel: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = at
	e.relative = rel
	return e

func _finish() -> bool:
	if server_pid > 0:
		OS.kill(server_pid)
	print("WAR_UI_PASS" if fails.is_empty() else "WAR_UI_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
	return true
