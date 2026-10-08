extends SceneTree
# CPU cost of a frame in a big fight (16 v 16 at the blue gate, everyone a bot), headless: the sim's ticks, the view's
# sync and the HUD's process/draw, from SiegeDiag's timers. Relative numbers: this box is not the phone.
#   godot --headless --fixed-fps 30 --path godot -s res://tests/fight_bench.gd      (FRAMES=<n>, default 600)
const Mode = preload("res://scripts/siege/siege_mode.gd")
var mode
var frames := 0
var n_frames := 600
var totals := {}

func _init() -> void:
	if OS.has_environment("FRAMES"):
		n_frames = int(OS.get_environment("FRAMES"))
	mode = Mode.new()
	mode.hq_gfx = true
	root.add_child(mode)

func _process(_d: float) -> bool:
	frames += 1
	mode._guard_clock = -1.0e9
	var s = mode.sim
	if frames == 3:
		var gate: Vector2 = s.gates.filter(func(g): return g.team == 0 and not g.has("kind"))[0].c
		var k := 0
		for u in s.units:
			u.bot = true
			s._set_class(u, ["ranger", "mage", "knight", "barbarian", "ranger", "rogue", "mage", "priest"][k % 8], k % 5 == 0)
			u.pos = gate + Vector2(randf_range(-7.0, 7.0), (-4.0 if u.team == 0 else -9.0) + randf_range(-2.0, 2.0)) if u.team == 1 else gate + Vector2(randf_range(-6.0, 6.0), 2.5 + randf_range(0.0, 3.0))
			k += 1
		mode.view.snap_camera()
	if frames > 40:
		for k in mode.diag._times:
			var t: Array = mode.diag._times[k]
			var tot: Array = totals.get(k, [0, 0, 0])
			tot[0] += t[0]
			tot[1] = maxi(tot[1], t[1])
			tot[2] += t[2]
			totals[k] = tot
		mode.diag._times.clear()
	if frames >= 40 + n_frames:
		for k in totals:
			var t: Array = totals[k]
			print("FIGHT_BENCH %-6s avg %6.2f ms  worst %6.2f ms  (%d calls)" % [k, t[0] / 1000.0 / maxf(1, t[2]), t[1] / 1000.0, t[2]])
		print("FIGHT_BENCH actors %d, fx %d, projectiles %d" % [mode.view.actors.size(), mode.view._fx.size(), s.projectiles.size()])
		print("FIGHT_BENCH_DONE")
		quit(0)
	return false
