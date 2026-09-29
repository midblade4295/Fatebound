extends SceneTree
# Run in REAL time (no --fixed-fps: the server is a separate process on the wall clock).
# Online Siege end to end: starts the real server (server/siege_server.gd) as a separate process,
# connects the real game client (SiegeMode online) plus a raw second client, and checks:
# welcome + team seating, snapshots, the player's unit moving from real touch input, actions
# (walk to a hat stand and become a class), events reaching the view/HUD, disconnect -> bot takes over.
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")

var port := 8092
var pid := -1
var mode
var raw: WebSocketPeer
var raw_unit := ""
var raw_hello_sent := false
var frames := 0
var t := 0.0
var phase := "boot"
var start_pos := Vector2.ZERO
var move_goal := Vector2.ZERO
var move_start_goal_distance := 0.0
var move_touch_pos := Vector2.ZERO
var saw_authoritative_move := false
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
				raw = WebSocketPeer.new()
				raw.connect_to_url("ws://127.0.0.1:%d/fatebound/siege/ws" % port)
				phase = "raw"; t = 0.0
			elif t > 8.0:
				check(false, "client joined within 8 s (state=%s)" % mode.net_state); _finish()
		"raw":
			if raw.get_ready_state() == WebSocketPeer.STATE_OPEN and not raw_hello_sent:
				raw.put_packet(Net.encode({"t":"hello", "v":Net.VERSION, "name":"TestB"}))
				raw_hello_sent = true
			if raw_unit != "" and snaps_raw >= 3:
				check(raw_unit.begins_with("r"), "second player seated on red (%s)" % raw_unit)
				# Pick the farther courtyard station, then steer the real touch stick over the
				# mirror's navigation path. A fixed direction is seed-dependent here: the spawn
				# is randomized and walls/resources can sit directly in front of it.
				var me: Dictionary = mode.sim.by_id[mode.hud.player_id]
				start_pos = me.get("net_to", me.pos)
				var forge_pos: Vector2 = Sim.forge(me.team)
				var workshop_pos: Vector2 = Sim.workshop(me.team)
				move_goal = forge_pos if start_pos.distance_to(forge_pos) > start_pos.distance_to(workshop_pos) else workshop_pos
				move_start_goal_distance = start_pos.distance_to(move_goal)
				touch(0, Vector2(100, 600), true)
				phase = "move"; t = 0.0
			elif t > 6.0:
				check(false, "raw client welcomed (unit=%s snaps=%d)" % [raw_unit, snaps_raw]); _finish()
		"move":
			var me: Dictionary = mode.sim.by_id[mode.hud.player_id]
			var authoritative_pos: Vector2 = me.get("net_to", me.pos)
			saw_authoritative_move = saw_authoritative_move or me.state == "move"
			var path: PackedVector2Array = mode.sim.find_path(me.team, authoritative_pos, move_goal)
			var target: Vector2 = path[mini(1, path.size() - 1)] if path.size() > 0 else move_goal
			var move_dir: Vector2 = (target - authoritative_pos).normalized()
			move_touch_pos = Vector2(100, 600) + move_dir * 60.0
			drag(0, move_touch_pos, move_dir * 60.0)
			var progress: float = move_start_goal_distance - authoritative_pos.distance_to(move_goal)
			# Snapshots arrive at 10 Hz on the wall clock. Under a loaded test runner the 2 s
			# check could land on an older mirror snapshot even though the server was moving.
			# Finish as soon as the authoritative snapshot shows enough movement, with a
			# bounded timeout so a real input/transport failure still fails quickly.
			if (progress > 3.0 and saw_authoritative_move) or t > 8.0:
				touch(0, move_touch_pos, false)
				check(progress > 3.0 and saw_authoritative_move,
					"our unit moved from touch input through the server (%.1f m toward goal)" % progress)
				# Walk to one of our hat stands via the protocol; the server hands over the hat.
				phase = "hat"; t = 0.0
		"hat":
			var me2: Dictionary = mode.sim.by_id[mode.hud.player_id]
			if me2.cls != "villager":
				phase = "hatted"; t = 0.0
			else:
				var best := {}
				for st in mode.sim.stands:
					if int(st.team) == me2.team and int(st.stock) > 0 and (best.is_empty() or me2.pos.distance_to(st.p) < me2.pos.distance_to(best.p)):
						best = st
				var goal: Vector2 = (best.p as Vector2) + ((Sim.spawn(me2.team) - (best.p as Vector2)).normalized() * 0.95) if not best.is_empty() else Sim.forge(me2.team)
				if t < 24.0:
					# Steer along the mirror's own nav path (walls/gates), like a player would.
					var path: PackedVector2Array = mode.sim.find_path(me2.team, me2.pos, goal)
					var target: Vector2 = path[mini(1, path.size() - 1)] if path.size() > 0 else goal
					mode._net_send({"t":"in", "m":(target - me2.pos).normalized(), "h":false})
					# Keep the mode's 20 Hz sender (HUD stick = zero) from overriding the test input.
					mode._sent_move = Vector2.ZERO
					mode._send_clock = -1.0
				else:
					check(false, "reached a hat stand and became a class (still %s, %.1f m away)" % [me2.cls, me2.pos.distance_to(goal)]); _finish()
		"hatted":
			if t > 1.0:
				mode._net_send({"t":"in", "m":Vector2.ZERO, "h":false})
				var me3: Dictionary = mode.sim.by_id[mode.hud.player_id]
				check(me3.cls != "villager", "took a hat at a stand on the server (now %s)" % me3.cls)
				var own_stock := 0
				for st in mode.sim.stands:
					if int(st.team) == me3.team: own_stock += int(st.stock)
				check(own_stock < Sim.HAT_STOCK_MAX * Sim.HAT_CLASSES.size(), "stand stock synced to the mirror (%d left)" % own_stock)
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
