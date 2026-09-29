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

func _init() -> void:
	mode = Mode.new()
	root.add_child(mode)
	var only := OS.get_environment("BENCH")
	configs = ["full", "no_foliage", "no_terrain_shader", "no_water", "no_adjust", "nothing_new"] if only == "" else only.split(",")

func _nodes(tag: String) -> Array:
	return mode.view.find_children("*", "", true, false).filter(func(n): return n.get_meta("perf", "") == tag)

func _apply(cfg: String) -> void:
	for tag in ["terrain", "water", "foliage"]:
		for n in _nodes(tag):
			(n as Node3D).visible = true
	for n in _nodes("terrain"):
		n.material_override = mode.view._terrain_material()
	var env: Environment = mode.view.find_children("*", "WorldEnvironment", true, false)[0].environment
	env.adjustment_enabled = true
	if simple_mat == null:
		simple_mat = StandardMaterial3D.new()
		simple_mat.albedo_texture = load("res://assets/terrain/grass.png")
		simple_mat.uv1_triplanar = true
		simple_mat.uv1_world_triplanar = true
		simple_mat.uv1_scale = Vector3(0.11, 0.11, 0.11)
	match cfg:
		"no_foliage":
			for n in _nodes("foliage"): n.visible = false
		"no_terrain_shader":
			for n in _nodes("terrain"): n.material_override = simple_mat
		"no_water":
			for n in _nodes("water"): n.visible = false
		"no_adjust":
			env.adjustment_enabled = false
		"nothing_new":
			for n in _nodes("foliage"): n.visible = false
			for n in _nodes("water"): n.visible = false
			for n in _nodes("terrain"): n.material_override = simple_mat
			env.adjustment_enabled = false

func _process(d: float) -> bool:
	frames += 1
	if frames == 3:
		var me: Dictionary = mode.sim.by_id["you"]
		me.bot = false
		me.pos = Vector2(4.0, 30.0)
		RenderingServer.viewport_set_measure_render_time(mode.viewport.get_viewport_rid(), true)
	if frames < 12:
		return false
	var vp: RID = mode.viewport.get_viewport_rid()
	if ci == -1 or (warm >= 10 and samples.size() >= 40):
		if ci >= 0:
			samples.sort()
			results[configs[ci]] = samples[samples.size() / 2]
			print("%-18s median 3D %.2f ms (cpu %.2f)" % [configs[ci], samples[samples.size() / 2], RenderingServer.viewport_get_measured_render_time_cpu(vp)])
		ci += 1
		if ci >= configs.size():
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
