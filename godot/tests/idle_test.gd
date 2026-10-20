extends SceneTree
# 0.31.119 (Kevin: "Do all" -- 2. idle players): the REAL server (port 8103, SIEGE_IDLE_BOT=2, SIEGE_IDLE_KICK=7) and
# the real game client (SiegeMode online), real time.
#   - a player who doesn't touch anything: after 2 s a bot plays their unit -- the server says so ("idle" on, with the
#     time left), the snapshots carry the unit as a bot, the phone stops predicting it and draws it where the server has
#     it (it walks off on its own), and the HUD's banner has a countdown
#   - any input: the unit is theirs again ("idle" off, bot flag off, prediction back on)
#   - idle again until the limit: bye "idle", close 4006; the phone leaves the match and tells Home why (exit_note)
#   - a second player who keeps moving is never touched
#     (0.31.193: that player runs on a thread of its own -- on the main loop it went quiet for as long as the phone took
#     to build the match, which under the suite's load passed the 2 s, and the server rightly put a bot on it)
#   godot --headless --path godot -s res://tests/idle_test.gd
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Net = preload("res://scripts/siege/siege_net.gd")

var fails: Array = []
var port := 8103
var pid := -1
var mode
var raw_thread: Thread
var raw_lock := Mutex.new()
var raw_stop := false
var raw_open := false
var raw_msgs: Array = []
var phase := "boot"
var t_phase := 0.0
var notes := {}
var exited := false

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	OS.set_environment("SIEGE_PORT", str(port))
	OS.set_environment("SIEGE_HOST", "127.0.0.1")
	OS.set_environment("SIEGE_LOBBY", "0.5")
	OS.set_environment("SIEGE_IDLE_BOT", "2")
	OS.set_environment("SIEGE_IDLE_KICK", "7")
	OS.set_environment("SIEGE_MIN_BUILD", "off")
	OS.set_environment("STATE_DIRECTORY", OS.get_user_data_dir().path_join("idle-srv-%d" % Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(OS.get_environment("STATE_DIRECTORY"))
	pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://server/siege_server.gd"])
	check(pid > 0, "server process started")

func _go(ph: String) -> void:
	phase = ph
	t_phase = 0.0

func _me() -> Dictionary:
	return mode.sim.by_id.get(mode.hud.player_id, {}) if mode != null and mode.sim != null else {}

func _process(delta: float) -> bool:
	t_phase += delta
	match phase:
		"boot":
			if t_phase > 2.0:
				mode = Mode.new()
				mode.online = true
				mode.net_url = "ws://127.0.0.1:%d/fatebound/siege/ws" % port
				mode.player_name = "Sleepy"
				mode.exited.connect(func(): exited = true)
				root.add_child(mode)
				raw_thread = Thread.new()
				raw_thread.start(_raw_loop)
				_go("join")
		"join":
			if mode.net_state == "playing" and not notes.has("seat_at"):  # (the match is up: idle time counts from our first input)
				notes.seat_at = Time.get_ticks_msec() / 1000.0
			if mode.net_state == "playing" and not _me().is_empty() and mode.sim.time > 0.3:
				check(not bool(_me().bot) and not mode._me_bot and mode.hud.idle_kick_at < 0.0, "seated: the unit is ours")
				notes.p0 = _me().pos
				_go("idle")
			elif t_phase > 10.0:
				check(false, "joined within 10 s (%s)" % mode.net_state)
				_finish()
		"idle":
			if mode._me_bot and mode.hud.idle_kick_at > 0.0:
				var left: float = mode.hud.idle_kick_at - Time.get_ticks_msec() / 1000.0
				var since: float = Time.get_ticks_msec() / 1000.0 - float(notes.seat_at)
				# (counted from the phone's first input, sent as its match came up -- the frame that builds the 5v5's view is long)
				check(since > 1.5 and since < 4.5, "no input for 2 s: a bot plays for us (%.1f s after the match came up)" % since)
				check(left > 3.0 and left <= 5.5, "the banner counts down to removal (%.1f s left)" % left)
				notes.p1 = _me().pos
				_go("bot_walks")
			elif t_phase > 8.0:
				check(false, "idle noticed within 8 s (me_bot %s, kick_at %.1f)" % [mode._me_bot, mode.hud.idle_kick_at])
				_finish()
		"bot_walks":
			if t_phase > 1.5:
				var moved: float = (_me().pos as Vector2).distance_to(notes.p1)
				check(moved > 0.5, "the bot walks our unit and the phone draws it there (%.1f m)" % moved)
				mode._net_send({"t":"in", "m":Vector2(1, 0), "h":false, "b":false})     # we're back
				_go("back")
		"back":
			if not mode._me_bot and mode.hud.idle_kick_at < 0.0:
				check(not bool(_me().bot), "any input: the unit is ours again (bot off, banner gone)")
				_go("idle2")
			elif t_phase > 4.0:
				check(false, "control back within 4 s")
				_finish()
		"idle2":
			if exited or mode.exit_note == "idle":
				if not notes.has("kicked_at"):
					notes.kicked_at = t_phase
					check(t_phase > 5.0 and t_phase < 10.5, "idle again until the limit (7 s): removed after %.1f s" % t_phase)
					check(mode.exit_note == "idle" and str(mode._net_bye.get("why", "")) == "idle", "the phone knows why (bye idle)")
				if exited:
					check(true, "the phone leaves the match on its own (back to Home, which says why)")
					raw_lock.lock()
					var raw_bye := raw_msgs.filter(func(m): return str(m.get("t", "")) in ["bye", "idle"])
					var still_open := raw_open
					var got := raw_msgs.size()
					raw_lock.unlock()
					check(got > 0 and raw_bye.is_empty() and still_open, "the player who kept moving was never touched")
					_finish()
			elif t_phase > 16.0:
				check(false, "removed within 16 s (state %s, note %s)" % [mode.net_state, mode.exit_note])
				_finish()
	return false

func _raw_loop() -> void:
	# the second player, who keeps moving: input ten times a second, whatever the main loop is doing
	var ws := WebSocketPeer.new()
	ws.connect_to_url("ws://127.0.0.1:%d/" % port)
	var hello := false
	var last := 0
	while true:
		raw_lock.lock()
		var stop := raw_stop
		raw_lock.unlock()
		if stop:
			break
		ws.poll()
		var st := ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN:
			if not hello:
				ws.put_packet(Net.encode({"t":"hello", "v":Net.VERSION, "five":Net.FIVE, "name":"Busy", "build":"0.31.119-fatebound"}))
				hello = true
			var now := Time.get_ticks_msec()
			if now - last >= 100:
				last = now
				var a := now / 700.0
				ws.put_packet(Net.encode({"t":"in", "m":Vector2(cos(a), sin(a)), "h":false, "b":false}))
		var got: Array = []
		while ws.get_available_packet_count() > 0:
			got.append(Net.decode(ws.get_packet()))
		raw_lock.lock()
		raw_msgs.append_array(got)
		raw_open = st == WebSocketPeer.STATE_OPEN
		raw_lock.unlock()
		OS.delay_msec(10)
	ws.close()

func _finish() -> void:
	if raw_thread != null:
		raw_lock.lock()
		raw_stop = true
		raw_lock.unlock()
		raw_thread.wait_to_finish()
		raw_thread = null
	if pid > 0:
		OS.kill(pid)
		OS.execute("kill", ["-9", str(pid)])
		pid = -1
	print("IDLE_PASS" if fails.is_empty() else "IDLE_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
