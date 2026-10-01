extends SceneTree
# Terrain-only renders (the baked land, its shader, the cliff stones, a flat water sheet): a quick look at
# cliffs and rock without the whole game.  Xvfb ... godot --rendering-method mobile -s res://tools/terrain_shot.gd
const View = preload("res://scripts/siege/siege_view.gd")
const Land = preload("res://scripts/siege/siege_land.gd")
var frames := 0
var cams := [
	["west", Vector3(-12.0, 15.0, 33.0), Vector3(-24.0, 0.0, 22.0)],
	["east", Vector3(28.0, 16.0, 30.0), Vector3(40.0, 0.0, 16.0)],
	["tower", Vector3(25.0, 13.0, 27.0), Vector3(25.0, 0.0, 17.0)],
]
var cam: Camera3D
var ci := 0

func _init() -> void:
	var root3 := Node3D.new()
	root.add_child(root3)
	for m in View._make_terrain_meshes():
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = View._terrain_material()
		root3.add_child(mi)
	var plan: Dictionary = View._plan_cliff_rocks()
	for kind in plan:
		var sc: Node = load(View.FOREST + kind + ".gltf").instantiate()
		var src: MeshInstance3D = sc.find_children("*", "MeshInstance3D", true, false)[0]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = src.mesh
		mm.instance_count = (plan[kind] as Array).size()
		for i in mm.instance_count:
			mm.set_instance_transform(i, plan[kind][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		root3.add_child(mmi)
	for p in [Vector2(-31.0, 25.0), Vector2(25.0, 17.0)]:
		var t: Node3D = load(View.HEX + "building_tower_A_blue.gltf").instantiate()
		t.position = Vector3(p.x, Land.ground_height(p, false) - 0.14, p.y)
		t.scale = Vector3.ONE * 4.0
		root3.add_child(t)
	var water := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(Land.HALF_W * 2.0 + 3.0, 26.0)
	water.mesh = pm
	water.position = Vector3(0.0, Land.WATER_Y, 0.0)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.16, 0.5, 0.75)
	water.material_override = wm
	root3.add_child(water)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.95, 0.6, 0.0)
	sun.light_energy = 1.1
	root3.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.75, 0.95)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.environment.ambient_light_energy = 0.7
	root3.add_child(env)
	cam = Camera3D.new()
	cam.fov = 55.0
	root3.add_child(cam)
	_aim()
	RenderingServer.frame_post_draw.connect(func():
		if frames > 0 and frames % 3 == 0 and ci < cams.size():
			root.get_texture().get_image().save_png("/tmp/terrain_%s.png" % cams[ci][0])
			print("SHOT ", cams[ci][0])
			ci += 1
			if ci < cams.size():
				_aim())

func _aim() -> void:
	cam.position = cams[ci][1]
	cam.look_at(cams[ci][2], Vector3.UP)

func _process(_d: float) -> bool:
	frames += 1
	if ci >= cams.size():
		quit(0)
	return false
