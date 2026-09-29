extends SceneTree
# Relative render cost of the Round 7 features, measured on whatever renderer runs this (the
# software Vulkan renderer here: CPU rasterisation, so like a phone GPU it is fill-rate bound).
#   Xvfb ... godot --rendering-method mobile --resolution 540x960 --path godot -s res://tests/perf_bench.gd
# Prints ms per frame of the 3D SubViewport for each configuration.
const Mode = preload("res://scripts/siege/siege_mode.gd")
var mode
var frames := 0
var configs: Array = []
var ci := -1
var samples: Array = []
var results := {}
var warm := 0
var simple_mat: StandardMaterial3D
var orig_meshes := {}
var per_cfg := {}

func _init() -> void:
	mode = Mode.new()
	root.add_child(mode)
	var only := OS.get_environment("BENCH")
	configs = ["full", "no_foliage", "no_terrain_shader", "no_water", "no_adjust", "nothing_new"] if only == "" else only.split(",")

func _nodes(tag: String) -> Array:
	return mode.view.find_children("*", "", true, false).filter(func(n): return n.get_meta("perf", "") == tag)

func _apply(cfg: String) -> void:
	for tag in ["terrain", "water", "foliage", "castle"]:
		for n in _nodes(tag):
			(n as Node3D).visible = true
	for n in _nodes("terrain"):
		n.material_override = mode.view._terrain_material()
		if not orig_meshes.has(n):
			orig_meshes[n] = (n as MeshInstance3D).mesh
		(n as MeshInstance3D).mesh = orig_meshes[n]
	if absf(mode.render_scale - 1.0) > 0.01:
		mode.set_render_scale(1.0)
	var env: Environment = mode.view.find_children("*", "WorldEnvironment", true, false)[0].environment
	# Restore each build's own settings (don't force them on).
	if not has_meta("env0"):
		set_meta("env0", [env.adjustment_enabled, env.glow_enabled])
	env.adjustment_enabled = get_meta("env0")[0]
	env.glow_enabled = get_meta("env0")[1]
	if simple_mat == null:
		simple_mat = StandardMaterial3D.new()
		simple_mat.albedo_texture = load("res://assets/terrain/grass.png")
		simple_mat.uv1_triplanar = true
		simple_mat.uv1_world_triplanar = true
		simple_mat.uv1_scale = Vector3(0.11, 0.11, 0.11)
	match cfg:
		"no_foliage":
			for n in _nodes("foliage"): n.visible = false
		"no_flowers":
			for n in _nodes("foliage"):
				if str(n.get_meta("perf_kind", "")) in ["red", "blue", "yellow", "white"]: n.visible = false
		"no_tufts":
			for n in _nodes("foliage"):
				if str(n.get_meta("perf_kind", "")).begins_with("Grass"): n.visible = false
		"scale90":
			mode.set_render_scale(0.9)
		"scale90_nomsaa":
			mode.set_render_scale(0.9)
			mode.viewport.msaa_3d = Viewport.MSAA_DISABLED
		"terrain_1m":
			# Rebuild the terrain from every other baked sample (1 m spacing).
			for n in _nodes("terrain"):
				var m: ArrayMesh = (n as MeshInstance3D).mesh
				var arr := m.surface_get_arrays(0)
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var nx := 157
				var rows := verts.size() / nx
				var idx := PackedInt32Array()
				var jj := 0
				while jj + 2 < rows:
					var i := 0
					while i + 2 < nx:
						var a := jj * nx + i
						idx.append_array([a, a + 2, a + 2 * nx, a + 2, a + 2 * nx + 2, a + 2 * nx])
						i += 2
					jj += 2
				arr[Mesh.ARRAY_INDEX] = idx
				var am := ArrayMesh.new()
				am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
				(n as MeshInstance3D).mesh = am
		"no_units":
			for a in mode.view.actors.values():
				if is_instance_valid(a.root): (a.root as Node3D).visible = false
		"no_terrain_shader":
			for n in _nodes("terrain"): n.material_override = simple_mat
		"no_water":
			for n in _nodes("water"): n.visible = false
		"no_adjust":
			env.adjustment_enabled = false
		"no_glow":
			env.glow_enabled = false
		"no_castle":
			for n in _nodes("castle"): n.visible = false
		"nothing_new":
			for n in _nodes("foliage"): n.visible = false
			for n in _nodes("water"): n.visible = false
			for n in _nodes("terrain"): n.material_override = simple_mat
			env.adjustment_enabled = false

func _process(d: float) -> bool:
	frames += 1
	if frames == 3:
		# A static scene: every unit frozen where it stands (bots walking in and out of view
		# swamped the differences between configs), and a few placed near the camera.
		for u in mode.sim.units:
			u.bot = false
			u.move = Vector2.ZERO
		var me: Dictionary = mode.sim.by_id["you"]
		me.pos = Vector2(4.0, 30.0)
		var k := 0
		for u in mode.sim.units:
			if u.id != "you" and k < 10:
				u.pos = Vector2(-6.0 + (k % 5) * 3.0, 24.0 + (k / 5) * 6.0)
				k += 1
		RenderingServer.viewport_set_measure_render_time(mode.viewport.get_viewport_rid(), true)
	if frames < 12:
		return false
	var vp: RID = mode.viewport.get_viewport_rid()
	if ci == -1 or (warm >= 10 and samples.size() >= 40):
		if ci >= 0:
			samples.sort()
			results[configs[ci]] = samples[samples.size() / 2]
			if not per_cfg.has(configs[ci]):
				per_cfg[configs[ci]] = []
			per_cfg[configs[ci]].append(samples[samples.size() / 2])
			print("%-18s median 3D %.2f ms (cpu %.2f)  draws %d  prims %dk  objects %d" % [configs[ci], samples[samples.size() / 2], RenderingServer.viewport_get_measured_render_time_cpu(vp),
				RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
				RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME) / 1000,
				RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)])
		ci += 1
		if ci >= configs.size():
			for c in per_cfg:
				var v: Array = per_cfg[c]
				v.sort()
				print("SUMMARY %-16s runs %s -> median %.1f ms" % [c, str(v.map(func(x): return snappedf(x, 0.1))), v[v.size() / 2]])
			print("PERF_BENCH_DONE")
			quit(0)
			return false
		_apply(configs[ci])
		samples = []
		warm = 0
		return false
	warm += 1
	if warm > 10:
		var g := RenderingServer.viewport_get_measured_render_time_gpu(vp)
		samples.append(g if g > 0.0 else d * 1000.0)
	return false
