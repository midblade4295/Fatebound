extends SceneTree
# Minimum app build on the server (server 0.31.84-minbuild, Kevin: "Can you have the server put a update now message in
# game?"). REAL time (WebSockets), two real servers:
#   A :8098  SIEGE_MIN_BUILD=0.31.99 (newer than this app's Diag.BUILD, so THIS app plays an outdated vc32-style build)
#   B :8099  SIEGE_MIN_BUILD_FILE=<tmp file> "0.31.84", re-read every 0.5 s
#  1. parse_build / compare_builds / build_too_old (unknown builds and "no minimum" always pass).
#  2. B over raw sockets: hello build 0.31.78 (vc32) and 0.31.72 (vc31) -> bye why=version need=VERSION+1 (+ msg,
#     min_build) BEFORE close 4001 "version:<VERSION+1>"; 0.31.84 (vc33), a newer build and a hello WITHOUT a build
#     (tools) are let in; the menu's "ver" still answers the real protocol; "status" carries build/min_build.
#  3. B's file is changed to "off" -> a 0.31.78 hello is let in (no restart, no code change).
#  4. The real app against A: the start-up version check sees the same protocol (no screen); PLAY online is refused
#     -> the full-screen Update screen (update_required, server_version VERSION+1, UPDATE opens Google Play).
#  5. The real app against B (min 0.31.84 == this build): PLAY online connects (lobby), no Update screen.
const Net = preload("res://scripts/siege/siege_net.gd")
const Server = preload("res://server/siege_server.gd")
const Diag = preload("res://scripts/siege/siege_diag.gd")
const App = preload("res://scripts/app/siege_app.gd")
const UpdateScreen = preload("res://scripts/app/update_screen.gd")

var port_a := 8098
var port_b := 8099
var pids: Array = []
var fails: Array = []
var t := 0.0
var phase := "unit"
var wait_until := 0.0
var cfg_path := ""
var raws: Array = []        # [{ws, hello, sent, bye, bye_state, welcome, lobby, ver}]
var app
var opened: Array = []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _start_server(port: int, env: Dictionary) -> void:
	for k in ["SIEGE_MIN_BUILD", "SIEGE_MIN_BUILD_FILE", "SIEGE_MIN_BUILD_RELOAD"]:
		OS.unset_environment(k)
	OS.set_environment("SIEGE_PORT", str(port))
	OS.set_environment("SIEGE_HOST", "127.0.0.1")
	OS.set_environment("SIEGE_LOBBY", "1")
	for k in env:
		OS.set_environment(k, str(env[k]))
	var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://server/siege_server.gd"])
	check(pid > 0, "server :%d started (%s)" % [port, str(env)])
	pids.append(pid)

func _write_cfg(v: String) -> void:
	var f := FileAccess.open(cfg_path, FileAccess.WRITE)
	f.store_line(v)
	f.close()

func _init() -> void:
	cfg_path = ProjectSettings.globalize_path("user://min_build_test-%d.cfg" % Time.get_ticks_usec())
	_write_cfg("0.31.84")
	_start_server(port_a, {"SIEGE_MIN_BUILD":"0.31.99"})
	_start_server(port_b, {"SIEGE_MIN_BUILD_FILE":cfg_path, "SIEGE_MIN_BUILD_RELOAD":"0.5"})
	for k in ["SIEGE_MIN_BUILD", "SIEGE_MIN_BUILD_FILE", "SIEGE_MIN_BUILD_RELOAD", "SIEGE_LOBBY"]:
		OS.unset_environment(k)

func _finish() -> void:
	for pid in pids:
		OS.execute("kill", ["-9", str(pid)])
	DirAccess.remove_absolute(cfg_path)
	print("MIN_BUILD_PASS" if fails.is_empty() else "MIN_BUILD_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)

func _raw(port: int, first: Dictionary) -> Dictionary:
	var ws := WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 20
	ws.connect_to_url("ws://127.0.0.1:%d/fatebound/siege/ws" % port)
	var r := {"ws":ws, "hello":first, "sent":false, "bye":{}, "bye_state":-1, "welcome":false, "lobby":false, "ver":{}, "status":{}}
	raws.append(r)
	return r

func _poll_raws() -> void:
	for r in raws:
		var ws: WebSocketPeer = r.ws
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN and not r.sent:
			ws.put_packet(Net.encode(r.hello))
			r.sent = true
		while ws.get_available_packet_count() > 0:
			var m := Net.decode(ws.get_packet())
			match str(m.get("t", "")):
				"bye":
					r.bye = m
					r.bye_state = ws.get_ready_state()
				"welcome": r.welcome = true
				"lobby": r.lobby = true
				"ver": r.ver = m
				"status": r.status = m

func _refused_update(r: Dictionary) -> bool:
	var ws: WebSocketPeer = r.ws
	var need := Net.VERSION + 1
	return str(r.bye.get("why", "")) == "version" and int(r.bye.get("need", -1)) == need and r.bye_state == WebSocketPeer.STATE_OPEN \
		and ws.get_ready_state() == WebSocketPeer.STATE_CLOSED and ws.get_close_code() == Net.CLOSE_VERSION \
		and ws.get_close_reason() == "version:%d" % need and str(r.bye.get("msg", "")).contains("Update") \
		and Net.version_verdict(Net.refused_version(r.bye, ws.get_close_code(), ws.get_close_reason())) == "update"

func _let_in(r: Dictionary) -> bool:
	return (r.lobby or r.welcome) and r.bye.is_empty()

func _hello(build) -> Dictionary:
	var h := {"t":"hello", "v":Net.VERSION, "name":"MB", "pred":true}
	if build != null:
		h.build = build
	return h

var r78; var r72; var r84; var r90; var rnone; var rver; var rstat; var r78b

func _process(delta: float) -> bool:
	t += delta
	_poll_raws()
	if t > 80.0:
		check(false, "finished within 80 s (stuck in phase %s)" % phase)
		_finish()
		return true
	if t < wait_until:
		return false
	match phase:
		"unit":
			check(Server.parse_build("0.31.78-fatebound") == [0, 31, 78], "parse 0.31.78-fatebound")
			check(Server.parse_build("") == [] and Server.parse_build("probe") == [] and Server.parse_build("x.1") == [], "unreadable builds -> []")
			check(Server.build_too_old("0.31.78-fatebound", "0.31.84"), "0.31.78 < 0.31.84")
			check(Server.build_too_old("0.31.72-fatebound", "0.31.84"), "0.31.72 < 0.31.84")
			check(not Server.build_too_old("0.31.84-fatebound", "0.31.84"), "0.31.84 == 0.31.84 passes")
			check(not Server.build_too_old("0.31.100-fatebound", "0.31.84"), "0.31.100 > 0.31.84 (numeric, not string order)")
			check(not Server.build_too_old("0.32.0", "0.31.84") and Server.build_too_old("0.30.99", "0.31.84"), "minor version compare")
			check(not Server.build_too_old("", "0.31.84") and not Server.build_too_old("probe", "0.31.84"), "unknown build passes")
			check(not Server.build_too_old("0.31.78-fatebound", ""), "no minimum -> everyone passes")
			check(not Server.build_too_old(Server.SERVER_BUILD + "-probe", Server.SERVER_BUILD), "the probe's default build is current")
			check(Diag.BUILD.begins_with(Server.SERVER_BUILD), "server SERVER_BUILD %s matches the app's Diag.BUILD %s" % [Server.SERVER_BUILD, Diag.BUILD])
			phase = "raw_start"; wait_until = t + 2.0
		"raw_start":
			r78 = _raw(port_b, _hello("0.31.78-fatebound"))
			r72 = _raw(port_b, _hello("0.31.72-fatebound"))
			r84 = _raw(port_b, _hello(Diag.BUILD))
			r90 = _raw(port_b, _hello("0.31.90-fatebound"))
			rnone = _raw(port_b, _hello(null))
			rver = _raw(port_b, {"t":"ver", "v":Net.VERSION})
			rstat = _raw(port_b, {"t":"status"})
			phase = "raw_wait"; t = 0.0
		"raw_wait":
			if t > 2.5:
				check(_refused_update(r78), "vc32 build 0.31.78: bye need=%d (+msg) before close 4001 'version:%d' -> 'update' (bye %s, close %d '%s')" % [
					Net.VERSION + 1, Net.VERSION + 1, str(r78.bye), r78.ws.get_close_code(), r78.ws.get_close_reason()])
				check(_refused_update(r72), "vc31 build 0.31.72 refused the same way (its app says 'Update the game to play online')")
				check(_let_in(r84), "vc33 build %s let in (lobby)" % Diag.BUILD)
				check(_let_in(r90), "a newer build let in")
				check(_let_in(rnone), "a hello without a build (tools) let in")
				check(int(rver.ver.get("v", -1)) == Net.VERSION and str(rver.ver.get("min_build", "")) == "0.31.84", "menu 'ver' still answers protocol %d (+min_build) %s" % [Net.VERSION, str(rver.ver)])
				check(str(rstat.status.get("min_build", "")) == "0.31.84" and str(rstat.status.get("build", "")) == Server.SERVER_BUILD, "status carries build/min_build")
				for r in raws:
					r.ws.close()
				raws.clear()
				_write_cfg("off")
				phase = "cfg_off"; wait_until = t + 1.5
		"cfg_off":
			r78b = _raw(port_b, _hello("0.31.78-fatebound"))
			phase = "cfg_off_wait"; t = 0.0
		"cfg_off_wait":
			if t > 2.0:
				check(_let_in(r78b), "min-build file changed to 'off' -> 0.31.78 let in, no restart")
				r78b.ws.close()
				raws.clear()
				_write_cfg("0.31.84")
				var base := "user://mbuild-%d" % Time.get_ticks_usec()
				var aurl := "ws://127.0.0.1:%d/fatebound/siege/ws" % port_a
				OS.set_environment("SIEGE_URL", aurl)
				app = App.new()
				app.profile_path = base + "-profile.json"
				app.legacy_path = base + "-none.json"
				app.version_check = true
				app.version_check_url = aurl
				app.open_url = func(u): opened.append(u); return OK
				root.add_child(app)
				phase = "app_startup"; t = 0.0
		"app_startup":
			if t > 3.0:
				check(not is_instance_valid(app.update_screen) and not app.update_required and app.server_version == Net.VERSION,
					"start-up check: same protocol -> no screen yet (server_version %d)" % app.server_version)
				app.start_match(true)
				phase = "app_refused"; t = 0.0
		"app_refused":
			if is_instance_valid(app.update_screen) and app.siege == null:
				var us = app.update_screen
				check(app.update_required and app.server_version == Net.VERSION + 1, "outdated build: PLAY online refused -> update required (server_version %d)" % app.server_version)
				check(us.is_visible_in_tree() and us.mouse_filter == Control.MOUSE_FILTER_STOP and us.get_index() == app.get_child_count() - 1,
					"the full-screen Update screen covers everything")
				var b: Button = _btn("update_now", us)
				check(b != null, "UPDATE button")
				if b != null:
					b.pressed.emit()
				check(opened.size() >= 1 and opened[-1] == UpdateScreen.WEB_URL, "UPDATE opens Google Play (%s)" % str(opened))
				app.start_match(true)
				check(app.siege == null and is_instance_valid(app.update_screen), "PLAY online stays locked")
				# ---- same app, server B (min 0.31.84 = this build) ----
				app.hide_update_screen()
				app.update_required = false
				app.server_version = -1
				OS.set_environment("SIEGE_URL", "ws://127.0.0.1:%d/fatebound/siege/ws" % port_b)
				app.rebuild()
				app.start_match(true)
				phase = "app_ok"; t = 0.0
			elif t > 8.0:
				check(false, "Update screen after the min-build refusal within 8 s (siege %s)" % str(app.siege)); _finish()
		"app_ok":
			if t > 3.0:
				check(app.siege != null and app.siege.net_state in ["waiting", "playing"] and not app.update_required
					and not is_instance_valid(app.update_screen), "up-to-date build: PLAY online connects (state %s), no Update screen" % (app.siege.net_state if app.siege != null else "none"))
				_finish()
	return false

func _btn(key: String, node: Node) -> Button:
	if node is Button and str(node.get_meta("action_key", "")) == key and node.is_visible_in_tree():
		return node
	for c in node.get_children():
		var r := _btn(key, c)
		if r != null:
			return r
	return null
