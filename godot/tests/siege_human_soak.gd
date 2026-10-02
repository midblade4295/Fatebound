extends SceneTree
# Plays as the human through real touch events on the HUD (stick, ATTACK, ability, DODGE, ACTION,
# hat stands) and checks the match keeps advancing: sim time must track frame time, no errors.
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
var mode
var hud
var frames := 0
var rng := RandomNumberGenerator.new()
var stick_down := false
var last_time := 0.0
var stalls := 0
var last_report := 0.0
var t0 := 0
var worst_ms := 0.0
func _init() -> void:
	rng.seed = int(OS.get_environment("SEED")) if OS.has_environment("SEED") else 5
	mode = Mode.new()
	mode.size = Vector2(420, 780)
	root.add_child(mode)
func touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index; e.position = pos; e.pressed = pressed
	root.push_input(e, true)
func drag(index: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index; e.position = pos
	root.push_input(e, true)
func button_pos(id: String) -> Vector2:
	for b in hud._buttons():
		if b.id == id: return b.c
	return Vector2(-1, -1)
func _process(delta: float) -> bool:
	frames += 1
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	if frames > 5: worst_ms = maxf(worst_ms, ms)
	hud = mode.hud
	var s = mode.sim
	var me: Dictionary = s.by_id["you"]
	# Stall detector: sim time must keep moving while the match is live and not paused.
	if frames > 10 and not s.ended and not hud.paused():
		if s.time <= last_time: stalls += 1
	last_time = s.time
	if me.state != "dead":
		# Steer with the stick toward a goal: the hat stands while a villager, else our Oracle, else home.
		var goal: Vector2
		if me.cls == "villager": goal = Sim.forge(0)
		elif me.carrying: goal = Sim.throne(0)
		elif s.oracles[0].state != "carried": goal = s.oracles[0].pos
		else: goal = s.oracles[0].pos
		var foe: Dictionary = s.nearest_enemy(me, 4.0)
		if not foe.is_empty() and not me.carrying: goal = foe.pos
		var dir: Vector2 = (goal - me.pos).normalized()
		# Screen up is -z for the blue side, matching the camera.
		var origin := Vector2(110, 640)
		if not stick_down:
			touch(0, origin, true); stick_down = true
		drag(0, origin + dir * 55.0 + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6)))
		# Second finger taps buttons while the stick is held.
		if frames % 9 == 0:
			var id := "attack"
			var r := rng.randf()
			if s.context_action(me) != "" and r < 0.5: id = "action"
			elif r < 0.12: id = "ability"
			elif r < 0.18: id = "dodge"
			var p := button_pos(id)
			if p.x >= 0:
				touch(1, p, true)
		if frames % 9 == 3:
			touch(1, button_pos("attack"), false)
	elif stick_down:
		touch(0, Vector2(100, 600), false); stick_down = false
	if s.time - last_report >= 30.0:
		last_report = s.time
		print("t=%3.0f frame=%d nodes=%d objs=%d cls=%s st=%s pos=(%.1f,%.1f) score=%s stalls=%d worst_ms=%.1f" % [s.time, frames,
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT),
			me.cls, me.state, me.pos.x, me.pos.y, str(s.score), stalls, worst_ms])
		worst_ms = 0.0
	if s.ended or frames > 30 * 400:
		print("HUMAN_SOAK_DONE t=%.1f ended=%s reason=%s score=%s winner=%d stalls=%d kills=%d deaths=%d rescues=%d" % [s.time, s.ended, s.end_reason, str(s.score), s.winner, stalls, me.kills, me.deaths, me.rescues])
		quit(0)
	return false
