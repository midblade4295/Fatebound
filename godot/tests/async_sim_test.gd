extends SceneTree
# 0.31.219: the sim's ticks on a worker thread while the frame is drawn (siege_mode.async_sim) play the same match as
# ticks run in _process: a 5v5 of bots from one seed, 20 s of it each way -- every unit's place, health and state the
# same at the same sim time; the async ticks ran on another thread, in the drawing's window (frame_pre_draw ..
# frame_post_draw, sent here by hand: headless no frame is drawn).
const Mode = preload("res://scripts/siege/siege_mode.gd")
const SECONDS := 20.0
var fails := []
var phase := 0
var mode
var frames := 0
var want_hash := 0
var want_time := 0.0
var drawn := false

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")
	_start(false)

func _start(async: bool) -> void:
	mode = Mode.new()
	mode.moba_hero = "knight"
	mode.match_seed = 4401
	mode.async_sim = async
	root.add_child(mode)
	frames = 0

func _hash(s) -> int:
	var parts := []
	for u in s.units:
		parts.append([str(u.id), snappedf(float(u.pos.x), 0.001), snappedf(float(u.pos.y), 0.001), snappedf(float(u.hp), 0.01), str(u.state)])
	return str(parts).hash()

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)

func _process(_delta: float) -> bool:
	frames += 1
	if phase == 2:
		if frames > 3:
			_check(not is_instance_valid(mode), "the match gone")
			_check(RenderingServer.frame_pre_draw.get_connections().filter(func(c): return str(c.callable.get_method()) == "_sim_launch").is_empty(), "unhooked on leaving")
			if fails.is_empty():
				print("ASYNC_SIM_PASS")
				quit(0)
			else:
				print("ASYNC_SIM_FAIL ", fails)
				quit(1)
			return true
		return false
	if mode.async_sim and drawn:
		# the frame's drawing: its ticks launched as it starts, waited for as it ends
		RenderingServer.frame_pre_draw.emit()
		OS.delay_msec(1)
		RenderingServer.frame_post_draw.emit()
	if mode.sim == null or not mode._build_queue.is_empty():
		return false
	var s = mode.sim
	if not s.by_id.has("you"):
		return false
	s.by_id["you"].bot = true
	drawn = true
	if phase == 0 and s.time >= SECONDS:
		want_time = s.time
		want_hash = _hash(s)
		print("ASYNC sync run: t=%.3f units %d" % [s.time, s.units.size()])
		_check(mode.sim_tasks == 0, "the sync run launched no tasks (%d)" % mode.sim_tasks)
		mode.queue_free()
		phase = 1
		drawn = false
		_start(true)
		return false
	if phase == 1 and s.time >= want_time - 0.0001:
		var h := _hash(s)
		print("ASYNC async run: t=%.3f units %d, tasks %d" % [s.time, s.units.size(), mode.sim_tasks])
		_check(absf(s.time - want_time) < 0.0001, "the same sim time (%.4f vs %.4f)" % [s.time, want_time])
		_check(h == want_hash, "the same match: every unit's place, health and state")
		_check(mode.sim_tasks >= int(SECONDS * 25.0), "its ticks ran as tasks (%d)" % mode.sim_tasks)
		_check(mode.sim_task_thread != OS.get_main_thread_id() and mode.sim_task_thread != 0, "on a worker thread")
		_check(mode.sim_hooked, "hooked to the drawing")
		mode.queue_free()
		phase = 2
		frames = 0
		return false
	if frames > 6000:
		print("ASYNC_SIM_FAIL timeout phase %d t=%.1f" % [phase, s.time])
		quit(1)
		return true
	return false
