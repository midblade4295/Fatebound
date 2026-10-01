extends SceneTree
# Round 35 (Kevin: "fps dropping here" -- a big fight at his front gate, 21 fps): the same kind of fight, measured
# per graphics configuration. CPU: Performance TIME_PROCESS (sim + view sync + HUD). GPU side: the 3D viewport's
# draw calls (main and shadow pass), objects, primitives, and its measured render time (this software renderer
# rasterises on the CPU: fill- and triangle-bound like a phone GPU, so the relative costs carry over).
#   Xvfb ... FB_FORCE_HQ=1 godot --rendering-method mobile --resolution 540x1200 --path godot -s res://tests/battle_bench.gd
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
var mode
var frames := 0
var configs := ["hq_full", "no_shadows", "msaa_2x", "no_glow", "no_water_sim_motes", "hq_off_like", "fix"]
var ci := -1
var samples := []
var stage_end := 0
func _init() -> void:
	if OS.has_environment("CONFIGS"):
		configs = Array(OS.get_environment("CONFIGS").split(","))
	mode = Mode.new()
	mode.hq_gfx = true
	root.add_child(mode)
func _vp() -> SubViewport:
	return mode.viewport
func _apply(cfg: String) -> void:
	var v = mode.view
	var sun: DirectionalLight3D = v.find_children("*", "DirectionalLight3D", true, false)[0]
	var env: Environment = (v.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment).environment
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 80.0
	_vp().msaa_3d = Viewport.MSAA_4X
	env.glow_enabled = true
	if v._motes != null: v._motes.visible = true
	v.set_meta("bench_no_rip", false)
	match cfg:
		"no_shadows": sun.shadow_enabled = false
		"msaa_2x": _vp().msaa_3d = Viewport.MSAA_2X
		"no_glow": env.glow_enabled = false
		"no_water_sim_motes":
			if v._motes != null: v._motes.visible = false
			v._rip_vp.clear()
		"fix":
			# the candidate: MSAA 2x; one shadow pass (orthogonal) covering 45 m
			_vp().msaa_3d = Viewport.MSAA_2X
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			sun.directional_shadow_max_distance = 45.0
		"hq_off_like":
			sun.shadow_enabled = false
			_vp().msaa_3d = Viewport.MSAA_2X
			env.glow_enabled = false
			if v._motes != null: v._motes.visible = false
func _process(d: float) -> bool:
	frames += 1
	mode._guard_clock = -1.0e9
	var s = mode.sim
	if frames == 3:
		mode._guard_res_low = -100000
		RenderingServer.viewport_set_measure_render_time(_vp().get_viewport_rid(), true)
		# A big fight at the blue front gate: everyone a bot, lots of archers and mages on both sides.
		var gate: Vector2 = s.gates.filter(func(g): return g.team == 0 and not g.has("kind"))[0].c
		var k := 0
		for u in s.units:
			u.bot = true
			var cls: String = ["ranger", "mage", "knight", "barbarian", "ranger", "rogue", "mage", "priest"][k % 8]
			s._set_class(u, cls, false)
			u.pos = gate + Vector2(randf_range(-7.0, 7.0), (-4.0 if u.team == 0 else -9.0) + randf_range(-2.0, 2.0)) if u.team == 1 else gate + Vector2(randf_range(-6.0, 6.0), 2.5 + randf_range(0.0, 3.0))
			k += 1
		var me: Dictionary = s.by_id[mode.hud.player_id]
		me.bot = true
		mode.view.snap_camera()
		stage_end = frames + int(OS.get_environment("STAGE")) if OS.has_environment("STAGE") else frames + 300
	if stage_end > 0 and frames == stage_end:
		ci = 0
		_apply(configs[ci])
	if ci >= 0 and ci < configs.size():
		var since: int = frames - stage_end - ci * 30
		if since > 8:
			var vrid := _vp().get_viewport_rid()
			samples.append([
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				RenderingServer.viewport_get_measured_render_time_gpu(vrid) + RenderingServer.viewport_get_measured_render_time_cpu(vrid),
				RenderingServer.viewport_get_render_info(vrid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
				RenderingServer.viewport_get_render_info(vrid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
				RenderingServer.viewport_get_render_info(vrid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
				RenderingServer.viewport_get_render_info(vrid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
				RenderingServer.viewport_get_render_info(vrid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)])
		if since == 30:
			var n := float(samples.size())
			var avg := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
			for smp in samples:
				for j in 7: avg[j] += float(smp[j]) / n
			print("BENCH %-20s cpu_process %5.1f ms | render %6.1f ms | draws %4d + shadow %4d | objects %4d | tris %7d + shadow %7d" % [configs[ci], avg[0], avg[1], avg[2], avg[3], avg[4], avg[5], avg[6]])
			samples.clear()
			ci += 1
			if ci < configs.size():
				_apply(configs[ci])
	if ci >= configs.size():
		var v = mode.view
		var arrows := 0
		var meshes: int = v.find_children("*", "MeshInstance3D", true, false).size()
		print("BENCH scene: %d MeshInstance3D under the view, %d projectiles in the sim, %d units alive" % [meshes, s.projectiles.size(), s.units.filter(func(u): return s.alive(u)).size()])
		quit(0)
	return false
