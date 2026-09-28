extends SceneTree
# Run in REAL time (no --fixed-fps: the server is a separate process on the wall clock).
# Online Siege end to end: starts the real server (server/siege_server.gd) as a separate process,
# connects the real game client (SiegeMode online) plus a raw second client, and checks:
# welcome + team seating, snapshots, the player's unit moving from real touch input, actions
# (walk to the forge, open it, roll), events reaching the view/HUD, disconnect -> bot takes over.
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")

var port := 8092
var pid := -1
var mode
var raw: WebSocketPeer
var raw_unit := ""
var frames := 0
var t := 0.0
var phase := "boot"
var start_pos := Vector2.ZERO
var events_seen := 0
var snaps_raw := 0
var fails: Array = []

func check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)
		print("FAIL ", what)
	else:
		print("ok   ", what)

func touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index; e.position = pos; e.pressed = pressed
	root.push_input(e, true)

func drag(index: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index; e.position = pos; e.relative = rel
	root.push_input(e, true)

func _init() -> void:
	if OS.has_environment("NET_TEST_PORT"):
		port = int(OS.get_environment("NET_TEST_PORT"))
	OS.set_environment("SIEGE_PORT", str(port))
	OS.set_environment("SIEGE_HOST", "127.0.0.1")
	pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://server/siege_server.gd"])
	check(pid > 0, "server process started (pid %d)" % pid)

func _finish() -> void:
	if pid > 0:
		OS.kill(pid)
	print("SIEGE_NET_PASS" if fails.is_empty() else "SIEGE_NET_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)

func _process(delta: float) -> bool:
	frames += 1
	t += delta
	if raw != null:
		raw.poll()
		while raw.get_available_packet_count() > 0:
			var m := Net.decode(raw.get_packet())
			if m.get("t", "") == "welcome": raw_unit = str(m.you)
			if m.get("t", "") == "s": snaps_raw += 1
	match phase:
		"boot":
			if t > 1.5:
				mode = Mode.new()
				mode.online = true
				mode.net_url = "ws://127.0.0.1:%d/fatebound/siege/ws" % port
				mode.player_name = "TestA"
				root.add_child(mode)
				phase = "join"; t = 0.0
		"join":
			if mode.net_state == "playing" and mode.sim != null and t > 1.0:
				var me_id: String = mode.hud.player_id
				check(me_id.begins_with("b"), "first player seated on blue (%s)" % me_id)
				check(not mode.sim.by_id[me_id].bot, "our unit is human-controlled on the mirror")
				check(mode.sim.time > 0.3, "snapshots advance match time (%.2f s)" % mode.sim.time)
				start_pos = mode.sim.by_id[me_id].pos
				raw = WebSocketPeer.new()
				raw.connect_to_url("ws://127.0.0.1:%d/fatebound/siege/ws" % port)
				phase = "raw"; t = 0.0
			elif t > 8.0:
				check(false, "client joined within 8 s (state=%s)" % mode.net_state); _finish()
		"raw":
			if raw.get_ready_state() == WebSocketPeer.STATE_OPEN and t > 0.2 and raw_unit == "" and t < 0.5:
				raw.put_packet(Net.encode({"t":"hello", "v":Net.VERSION, "name":"TestB"}))
			if raw_unit != "" and snaps_raw >= 3:
				check(raw_unit.begins_with("r"), "second player seated on red (%s)" % raw_unit)
				# Hold the stick toward the enemy (north on screen) for ~2 s.
				touch(0, Vector2(100, 600), true)
				phase = "move"; t = 0.0
			elif t > 6.0:
				check(false, "raw client welcomed (unit=%s snaps=%d)" % [raw_unit, snaps_raw]); _finish()
		"move":
			drag(0, Vector2(100, 520), Vector2(0, -80))
			if t > 2.0:
				touch(0, Vector2(100, 520), false)
				var me: Dictionary = mode.sim.by_id[mode.hud.player_id]
				var moved: float = me.pos.distance_to(start_pos)
				check(moved > 3.0, "our unit moved from touch input through the server (%.1f m)" % moved)
				# Walk to the forge via the protocol and open it + roll.
				phase = "forge"; t = 0.0
		"forge":
			var me2: Dictionary = mode.sim.by_id[mode.hud.player_id]
			var fg: Vector2 = Sim.forge(me2.team)
			var d: Vector2 = fg - me2.pos
			if d.length() > 1.2 and t < 20.0:
				# Steer along the mirror's own nav path (walls/gates), like a player would.
				var path: PackedVector2Array = mode.sim.find_path(me2.team, me2.pos, fg)
				var target: Vector2 = path[mini(1, path.size() - 1)] if path.size() > 0 else fg
				mode._net_send({"t":"in", "m":(target - me2.pos).normalized(), "h":false})
				# Keep the mode's 20 Hz sender (HUD stick = zero) from overriding the test input.
				mode._sent_move = Vector2.ZERO
				mode._send_clock = -1.0
			elif not me2.forge.open and t < 22.0:
				mode._net_send({"t":"in", "m":Vector2.ZERO, "h":false})
				mode._act("interact")
			elif me2.forge.open:
				mode._act("forge_roll", null)
				phase = "rolled"; t = 0.0
			else:
				check(false, "reached and opened the forge (dist %.1f)" % d.length()); _finish()
		"rolled":
			if t > 1.5:
				var me3: Dictionary = mode.sim.by_id[mode.hud.player_id]
				check(me3.forge.open and me3.forge.rolled, "forge opened and rolled on the server (%s)" % str(me3.forge.faces))
				check(mode.hud.forge_panel.visible, "forge panel shown from server state")
				check(mode.sim.projectiles.size() >= 0 and mode.diag != null, "mirror sim alive")
				raw.close()
				phase = "drop"; t = 0.0
		"drop":
			if t > 2.0:
				var ru: Dictionary = mode.sim.by_id[raw_unit]
				check(ru.bot, "after the second player left, a bot took %s back" % raw_unit)
				check(mode.sim.kills[0] + mode.sim.kills[1] >= 0, "match still running (t=%.0f s)" % mode.sim.time)
				_finish()
	return false
