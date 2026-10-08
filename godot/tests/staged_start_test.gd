extends SceneTree
# The app's match start (0.31.78): the loading card is up on the first frame after PLAY, the world is built behind it
# one step per frame, the match clock waits, and the card lifts once the warm-up tour is done.
#   FB_STAGED_START=1 FB_FORCE_WARMUP=1 godot --headless --fixed-fps 30 --path godot -s res://tests/staged_start_test.gd
const Mode = preload("res://scripts/siege/siege_mode.gd")
const View = preload("res://scripts/siege/siege_view.gd")
const Assets = preload("res://scripts/siege/asset_cache.gd")
var mode
var frames := 0
var fails := []
var built_at := -1
var lifted_at := -1
var worst_step_ms := 0.0
var _last_us := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)
	print(("ok   " if ok else "FAIL ") + what)

func _init() -> void:
	Assets.preload_async()                 # as the app does while the menus are up

func _process(_d: float) -> bool:
	if mode == null:
		Assets.poll()
		if Assets.pending() > 0:
			return false
		mode = Mode.new()
		root.add_child(mode)
		check(mode.sim == null and mode._cover != null, "after add_child: nothing built yet, the card is up")
		check(int(Mode.ready_times["_ready total"]) < 200, "_ready itself is quick (%d ms)" % int(Mode.ready_times["_ready total"]))
		_last_us = Time.get_ticks_usec()
		return false
	frames += 1
	mode._guard_clock = -1.0e9
	var now := Time.get_ticks_usec()
	if built_at < 0:
		worst_step_ms = maxf(worst_step_ms, (now - _last_us) / 1000.0)
	_last_us = now
	if built_at < 0 and mode.hud.sim != null and mode._build_queue.is_empty():
		built_at = frames
		check(mode.sim != null and mode.view != null, "built over %d frames" % frames)
		check(mode.sim.time == 0.0, "the match clock waited (sim time %.2f)" % mode.sim.time)
		check(View.build_times.size() >= 9, "every view step timed: %s" % str(View.build_times))
	if built_at > 0 and lifted_at < 0 and mode._cover == null:
		lifted_at = frames
		check(lifted_at > built_at, "the card lifted after the build (frame %d)" % lifted_at)
		check(mode.view.actors.size() == mode.sim.units.size(), "every unit has an actor when the card lifts")
	if lifted_at > 0 and frames >= lifted_at + 30:
		check(mode.sim.time > 0.5, "the match runs after the card (sim time %.2f)" % mode.sim.time)
		check(worst_step_ms < 400.0, "no build frame over 400 ms here (longest %.0f ms)" % worst_step_ms)
		print("staged start: built by frame %d, card lifted at frame %d, longest build frame %.0f ms; ready %s view %s" % [built_at, lifted_at, worst_step_ms, str(Mode.ready_times), str(View.build_times)])
		print("STAGED_START_PASS" if fails.is_empty() else "STAGED_START_FAIL %s" % [fails])
		quit(0 if fails.is_empty() else 1)
	if frames > 600:
		print("STAGED_START_FAIL timeout (built %d, lifted %d)" % [built_at, lifted_at])
		quit(1)
	return false
