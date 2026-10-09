extends SceneTree
# Forced update on a protocol mismatch (0.31.73, Kevin: "when server has newer version than players installed game
# it'll force them to update"). REAL time (WebSockets).
#  1. Net.version_verdict / Net.refused_version for newer, older, equal, unknown, and the legacy close-only refusal.
#  2. The real server (server/siege_server.gd): a wrong-protocol hello gets the bye with "need" BEFORE the close
#     (code 4001, reason "version:<n>"), and the menu's version check ({"t":"ver"}) is answered without joining.
#  3. The real game client (SiegeMode online) against fake servers: newer (bye + close), newer with the bye lost
#     (close reason only), and a LEGACY older server (today's live behaviour: close 4001 "version", bye lost).
#  4. The app: the start-up check against a newer server shows the blocking Update screen; ONLINE and PLAY online
#     re-show it; UPDATE opens the Play Store page; "Play offline" unlocks offline only; a refused connect from PLAY
#     shows it too; an older server only says "Servers are updating" and blocks nothing.
const Net = preload("res://scripts/siege/siege_net.gd")
const Mode = preload("res://scripts/siege/siege_mode.gd")
const App = preload("res://scripts/app/siege_app.gd")
const VersionCheck = preload("res://scripts/app/version_check.gd")
const UpdateScreen = preload("res://scripts/app/update_screen.gd")

var port := 8096          # the real server
var fport := 8097         # the fake server (this process)
var pid := -1
var fails: Array = []
var t := 0.0
var phase := "unit"
var wait_until := 0.0

# fake server: behaviour in fake_mode = "newer" | "newer_lost_bye" | "legacy_old"
var ftcp := TCPServer.new()
var fpeers: Array = []      # [{ws, close_at, code, reason}]
var fake_mode := "newer"
var fake_hellos := 0

var raw: WebSocketPeer
var raw_sent := false
var raw_bye := {}
var raw_bye_state := -1
var checker_result := -99
var mode
var mismatch_signal: Array = []
var app
var opened: Array = []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	OS.set_environment("SIEGE_PORT", str(port))
	OS.set_environment("SIEGE_HOST", "127.0.0.1")
	pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://server/siege_server.gd"])
	check(pid > 0, "server process started")
	check(ftcp.listen(fport, "127.0.0.1") == OK, "fake server listening on %d" % fport)

func _finish() -> void:
	if pid > 0:
		OS.execute("kill", ["-9", str(pid)])
	print("VERSION_GATE_PASS" if fails.is_empty() else "VERSION_GATE_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)

func _fake_poll() -> void:
	while ftcp.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.accept_stream(ftcp.take_connection())
		fpeers.append({"ws":ws, "close_at":-1.0})
	var now := Time.get_ticks_msec() / 1000.0
	for p in fpeers.duplicate():
		var ws: WebSocketPeer = p.ws
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			fpeers.erase(p)
			continue
		if float(p.close_at) >= 0.0 and now >= float(p.close_at):
			ws.close(int(p.code), str(p.reason))
			p.close_at = -1.0
		while ws.get_available_packet_count() > 0:
			var m := Net.decode(ws.get_packet())
			var newer := Net.VERSION + 1
			var older := Net.VERSION - 1
			match str(m.get("t", "")):
				"ver":
					if fake_mode != "legacy_old":       # a legacy server ignores "ver"
						ws.put_packet(Net.encode({"t":"ver", "v":newer}))
						p.close_at = now + 0.25; p.code = 1000; p.reason = "ver"
				"hello":
					fake_hellos += 1
					match fake_mode:
						"newer":
							ws.put_packet(Net.encode({"t":"bye", "why":"version", "need":newer}))
							p.close_at = now + 0.25; p.code = Net.CLOSE_VERSION; p.reason = "version:%d" % newer
						"newer_lost_bye":
							ws.close(Net.CLOSE_VERSION, "version:%d" % newer)
						"legacy_old":
							# Exactly what the 0.31.72 server does: bye and close in the same frame (the bye is lost)
							ws.put_packet(Net.encode({"t":"bye", "why":"version", "need":older}))
							ws.close(Net.CLOSE_VERSION, "version")

func _btn(key: String, node: Node) -> Button:
	if node is Button and str(node.get_meta("action_key", "")) == key and node.is_visible_in_tree():
		return node
	for c in node.get_children():
		var r := _btn(key, c)
		if r != null:
			return r
	return null

func _new_mode(url: String) -> void:
	mismatch_signal = []
	mode = Mode.new()
	mode.online = true
	mode.net_url = url
	mode.player_name = "OldPhone"
	mode.version_mismatch.connect(func(sv, verdict): mismatch_signal = [sv, verdict])
	root.add_child(mode)

func _process(delta: float) -> bool:
	t += delta
	_fake_poll()
	if raw != null:
		raw.poll()
		if raw.get_ready_state() == WebSocketPeer.STATE_OPEN and not raw_sent:
			raw.put_packet(Net.encode({"t":"hello", "v":Net.VERSION - 1, "name":"OldClient"}))
			raw_sent = true
		while raw.get_available_packet_count() > 0:
			var m := Net.decode(raw.get_packet())
			if str(m.get("t", "")) == "bye":
				raw_bye = m
				raw_bye_state = raw.get_ready_state()
	if t > 90.0:
		check(false, "finished within 90 s (stuck in phase %s)" % phase)
		_finish()
		return true
	if t < wait_until:
		return false
	var furl := "ws://127.0.0.1:%d/fatebound/siege/ws" % fport
	var surl := "ws://127.0.0.1:%d/fatebound/siege/ws" % port
	match phase:
		"unit":
			var v := Net.VERSION
			check(Net.version_verdict(v + 1) == "update", "server newer -> update")
			check(Net.version_verdict(v + 7) == "update", "any newer protocol -> update (no hard-coded numbers)")
			check(Net.version_verdict(v - 1) == "server_old", "server older -> servers are updating")
			check(Net.version_verdict(v) == "ok", "same protocol -> ok")
			check(Net.version_verdict(-1) == "unknown", "no answer -> unknown")
			check(Net.refused_version({"t":"bye", "why":"version", "need":v + 1}, -1, "") == v + 1, "bye need read")
			check(Net.refused_version({}, Net.CLOSE_VERSION, "version:%d" % (v + 2)) == v + 2, "close reason version:<n> read")
			check(Net.version_verdict(Net.refused_version({}, Net.CLOSE_VERSION, "version")) == "server_old",
				"legacy close-only refusal (no number) = a server older than this build")
			check(Net.refused_version({"t":"bye", "why":"full"}, Net.CLOSE_FULL, "full") == -1, "server full is not a version refusal")
			check(Net.refused_version({}, 1006, "") == -1, "a dropped connection is not a version refusal")
			var tried := []
			UpdateScreen.open_store(func(u): return OK, tried)
			check(tried[-1] == UpdateScreen.WEB_URL and UpdateScreen.WEB_URL == "https://play.google.com/store/apps/details?id=com.fatebound.game"
				and UpdateScreen.MARKET_URL == "market://details?id=com.fatebound.game", "store URLs (market:// on Android, https fallback)")
			phase = "server_boot"; wait_until = t + 1.5
		"server_boot":
			raw = WebSocketPeer.new()
			raw.connect_to_url(surl)
			var vc := VersionCheck.new()
			vc.url = surl
			vc.done.connect(func(sv): checker_result = sv)
			root.add_child(vc)
			phase = "server_check"; t = 0.0; wait_until = 0.0
		"server_check":
			if raw.get_ready_state() == WebSocketPeer.STATE_CLOSED and checker_result != -99:
				check(str(raw_bye.get("why", "")) == "version" and int(raw_bye.get("need", -1)) == Net.VERSION, "real server: bye with need=%d" % Net.VERSION)
				check(raw_bye_state == WebSocketPeer.STATE_OPEN, "real server: the bye arrives before the close (it used to be lost)")
				check(raw.get_close_code() == Net.CLOSE_VERSION and raw.get_close_reason() == "version:%d" % Net.VERSION,
					"real server: close %d '%s'" % [raw.get_close_code(), raw.get_close_reason()])
				check(checker_result == Net.VERSION, "real server answers the menu's version check (%d)" % checker_result)
				raw = null
				fake_mode = "newer"
				_new_mode(furl)
				phase = "mode_newer"; t = 0.0
			elif t > 8.0:
				check(false, "real server refusal + version check within 8 s"); _finish()
		"mode_newer":
			if mode.net_state == "closed" and t > 0.3:
				check(mode.net_verdict == "update" and mode.net_server_version == Net.VERSION + 1, "client vs newer server -> update (%s %d)" % [mode.net_verdict, mode.net_server_version])
				check(mismatch_signal == [Net.VERSION + 1, "update"], "version_mismatch signal (update)")
				mode.queue_free()
				fake_mode = "newer_lost_bye"
				_new_mode(furl)
				phase = "mode_lost"; t = 0.0
			elif t > 6.0:
				check(false, "client refused by newer server within 6 s (state %s)" % mode.net_state); _finish()
		"mode_lost":
			if mode.net_state == "closed" and t > 0.3:
				check(mode.net_verdict == "update" and mode.net_server_version == Net.VERSION + 1, "newer server, bye lost: close reason still -> update")
				mode.queue_free()
				fake_mode = "legacy_old"
				_new_mode(furl)
				phase = "mode_legacy"; t = 0.0
			elif t > 6.0:
				check(false, "client refused (close only) within 6 s"); _finish()
		"mode_legacy":
			if mode.net_state == "closed" and t > 0.3:
				check(mode.net_verdict == "server_old", "legacy older server (close 4001 'version', bye lost) -> servers are updating (%s)" % mode.net_verdict)
				check(mismatch_signal.size() == 2 and mismatch_signal[1] == "server_old", "version_mismatch signal (server_old)")
				phase = "mode_legacy_exit"; t = 0.0
			elif t > 6.0:
				check(false, "client refused by legacy server within 6 s"); _finish()
		"mode_legacy_exit":
			if t > 3.0:
				check(mode.is_inside_tree(), "standalone mode is still up until the app frees it (no crash on the exit timer)")
				mode.queue_free()
				# ---- the app: start-up check against a newer server ----
				fake_mode = "newer"
				fake_hellos = 0
				var base := "user://vgate-%d" % Time.get_ticks_usec()
				app = App.new()
				app.profile_path = base + "-profile.json"
				app.legacy_path = base + "-none.json"
				app.version_check = true
				app.version_check_url = furl
				app.open_url = func(u): opened.append(u); return OK
				root.add_child(app)
				phase = "app_check"; t = 0.0
		"app_check":
			if is_instance_valid(app.update_screen):
				var us = app.update_screen
				check(app.update_required and app.server_version == Net.VERSION + 1, "start-up check: server newer -> update required")
				check(us.get_index() == app.get_child_count() - 1 and us.mouse_filter == Control.MOUSE_FILTER_STOP and us.is_visible_in_tree(), "Update screen covers everything and blocks input")
				check(fake_hellos == 0, "the version check did not send a hello / join a match")
				check(_btn("update_now", us) != null, "big UPDATE button")
				_btn("update_now", us).pressed.emit()
				check(opened.size() >= 1 and opened[-1] == UpdateScreen.WEB_URL, "UPDATE opens the Play Store page (%s)" % str(opened))
				# offline escape (ALLOW_OFFLINE)
				if UpdateScreen.ALLOW_OFFLINE:
					_btn("update_offline", us).pressed.emit()
				phase = "app_offline"; wait_until = t + 0.3
			elif t > 8.0:
				check(false, "Update screen shown within 8 s of start-up"); _finish()
		"app_offline":
			if UpdateScreen.ALLOW_OFFLINE:
				check(not is_instance_valid(app.update_screen) and app.siege != null and not app.siege.online, "Play offline closes the screen and starts an offline match")
				app._end_match()
				check(is_instance_valid(app.update_screen), "the Update screen comes back after the offline match")
			_btn("play", app).pressed.emit()
			check(app.siege == null and is_instance_valid(app.update_screen), "PLAY (online) re-shows the Update screen")
			app.hide_update_screen()
			app.start_match(true)
			check(app.siege == null and is_instance_valid(app.update_screen), "PLAY online is blocked by the Update screen")
			app.hide_update_screen()
			# ---- connect path: no start-up answer (unknown), PLAY online gets refused by a newer server ----
			app.update_required = false
			app.server_version = -1
			app.version_check_url = furl
			OS.set_environment("SIEGE_URL", furl)
			app.rebuild()
			app.start_match(true)                  # siege_mode reads SIEGE_URL when it is created
			phase = "app_connect"; t = 0.0
		"app_connect":
			if is_instance_valid(app.update_screen) and app.siege == null:
				check(app.update_required, "refused connect (server newer) -> Update screen, back out of the match")
				app.hide_update_screen()
				app.update_required = false
				fake_mode = "legacy_old"
				app.start_match(true)
				phase = "app_old"; t = 0.0
			elif t > 6.0:
				check(false, "Update screen after a refused connect within 6 s"); _finish()
		"app_old":
			if app.siege == null and t > 0.5:
				check(not is_instance_valid(app.update_screen) and not app.update_required, "older server: no Update screen")
				check(app.server_updating and app._toast_box.visible and app._toast.text == app.SERVER_UPDATING, "older server: 'Servers are updating' on Home")
				_finish()
			elif t > 8.0:
				check(false, "older-server refusal back home within 8 s"); _finish()
	return false
