extends SceneTree
# 0.31.119 (Kevin: "Do all" -- 2. idle players): the REAL server (port 8103, SIEGE_IDLE_BOT=2, SIEGE_IDLE_KICK=7) and
# the real game client (SiegeMode online), real time.
#   - a player who doesn't touch anything: after 2 s a bot plays their unit -- the server says so ("idle" on, with the
#     time left), the snapshots carry the unit as a bot, the phone stops predicting it and draws it where the server has
#     it (it walks off on its own), and the HUD's banner has a countdown
#   - any input: the unit is theirs again ("idle" off, bot flag off, prediction back on)
#   - idle again until the limit: bye "idle", close 4006; the phone leaves the match and tells Home why (exit_note)
#   - a second player who keeps moving is never touched
#   godot --headless --path godot -s res://tests/idle_test.gd
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Net = preload("res://scripts/siege/siege_net.gd")

var fails: Array = []
var port := 8103
var pid := -1
var mode
var raw: WebSocketPeer
var raw_sent := false
var raw_msgs: Array = []
var raw_clock := 0.0
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
	if raw != null:
		raw.poll()
		if raw.get_ready_state() == WebSocketPeer.STATE_OPEN:
			if not raw_sent:
				raw.put_packet(Net.encode({"t":"hello", "v":Net.VERSION, "name":"Busy", "build":"0.31.119-fatebound"}))
				raw_sent = true
			raw_clock += delta
			if raw_clock > 0.1:                      # a player who keeps moving
				raw_clock = 0.0
				var a := Time.get_ticks_msec() / 700.0
				raw.put_packet(Net.encode({"t":"in", "m":Vector2(cos(a), sin(a)), "h":false, "b":false}))
		while raw.get_available_packet_count() > 0:
			raw_msgs.append(Net.decode(raw.get_packet()))
	match phase:
		"boot":
			if t_phase > 2.0:
				mode = Mode.new()
				mode.online = true
				mode.net_url = "ws://127.0.0.1:%d/fatebound/siege/ws" % port
				mode.player_name = "Sleepy"
				mode.exited.connect(func(): exited = true)
				root.add_child(mode)
				raw = WebSocketPeer.new()
				raw.connect_to_url("ws://127.0.0.1:%d/" % port)
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
				check(since > 1.8 and since < 4.5, "no input for 2 s: a bot plays for us (%.1f s after the match came up)" % since)
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
					var raw_bye := raw_msgs.filter(func(m): return str(m.get("t", "")) in ["bye", "idle"])
					check(raw_bye.is_empty() and raw.get_ready_state() == WebSocketPeer.STATE_OPEN, "the player who kept moving was never touched")
					_finish()
			elif t_phase > 16.0:
				check(false, "removed within 16 s (state %s, note %s)" % [mode.net_state, mode.exit_note])
				_finish()
	return false

func _finish() -> void:
	if pid > 0:
		OS.kill(pid)
		OS.execute("kill", ["-9", str(pid)])
		pid = -1
	print("IDLE_PASS" if fails.is_empty() else "IDLE_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
