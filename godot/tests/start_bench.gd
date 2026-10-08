extends SceneTree
# Where the time goes between pressing PLAY and the first playable frame (the app's own path: the models preloaded on a
# thread while the menus are up, then SiegeMode built and its first frames). Prints Mode.ready_times, View.build_times,
# the resources loaded synchronously during the build and the first frames, and the slowest of the first frames.
#   godot --headless --path godot -s res://tests/start_bench.gd          (PRELOAD=0 skips the app's background preload)
#   Xvfb :98 ...; DISPLAY=:98 godot --rendering-method mobile --resolution 540x1200 --path godot -s res://tests/start_bench.gd
const Mode = preload("res://scripts/siege/siege_mode.gd")
const View = preload("res://scripts/siege/siege_view.gd")
const Assets = preload("res://scripts/siege/asset_cache.gd")
var mode
var frames := 0
var phase := "preload"
var t0 := 0
var frame_times: Array = []
var _last_us := 0

func _init() -> void:
	t0 = Time.get_ticks_msec()
	if OS.get_environment("PRELOAD") == "0":
		phase = "start"
	else:
		Assets.preload_async()

func _start_match() -> void:
	var t := Time.get_ticks_msec()
	mode = Mode.new()
	mode.hq_gfx = true
	root.add_child(mode)
	print("START_BENCH add_child(mode): %d ms" % (Time.get_ticks_msec() - t))
	print("START_BENCH ready_times: ", Mode.ready_times)
	print("START_BENCH build_times: ", View.build_times)
	phase = "frames"
	_last_us = Time.get_ticks_usec()

func _process(_delta: float) -> bool:
	frames += 1
	match phase:
		"preload":
			Assets.poll()
			if Assets._pending.is_empty():
				print("START_BENCH preload done in %d ms, %d scenes cached" % [Time.get_ticks_msec() - t0, Assets._cache.size()])
				phase = "start"
		"start":
			_start_match()
		"frames":
			mode._guard_clock = -1.0e9
			var now := Time.get_ticks_usec()
			frame_times.append([(now - _last_us) / 1000.0, (now - _last_us) / 1000.0, mode.view.actors.size()])   # wall clock per frame
			_last_us = now
			if frame_times.size() >= 120:
				var worst := frame_times.duplicate()
				worst.sort_custom(func(a, b): return a[1] > b[1])
				print("START_BENCH first %d frames: wall ms (actors): %s" % [frame_times.size(),
					", ".join(frame_times.slice(0, 12).map(func(f): return "%.0f(%d)" % [f[1], f[2]]))])
				print("START_BENCH worst frames: %s" % ", ".join(worst.slice(0, 6).map(func(f): return "%.0f ms" % f[1])))
				var total := 0.0
				for f in frame_times.slice(10):
					total += float(f[1])
				print("START_BENCH steady: %.2f ms/frame" % (total / maxf(1.0, frame_times.size() - 10)))
				var t2 := Time.get_ticks_msec()
				mode._restart()                            # a rematch: the session's caches (terrain, castle walls) in use
				print("START_BENCH rematch _restart: %d ms, build_times %s" % [Time.get_ticks_msec() - t2, View.build_times])
				print("START_BENCH_DONE")
				quit(0)
	return false
