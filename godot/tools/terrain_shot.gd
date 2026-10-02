extends SceneTree
# Terrain-only renders (the baked land, its shader, two towers, a flat water sheet): a quick look at
# cliffs and rock without the whole game.  Xvfb ... godot --rendering-method mobile -s res://tools/terrain_shot.gd
const View = preload("res://scripts/siege/siege_view.gd")
const Land = preload("res://scripts/siege/siege_land.gd")
var frames := 0
var cams := [
	["east_tower", Vector3(35.0, 16.0, 31.0), Vector3(35.0, 2.0, 18.5)],
	["west_tower", Vector3(-24.0, 15.0, 36.0), Vector3(-31.0, 2.0, 25.0)],
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
	var posts := []
	var rings := []
	var caps := []
	for p in [Vector2(-31.0, 25.0), Vector2(35.0, 18.5)]:
		var t: Node3D = load(View.HEX + "building_tower_A_blue.gltf").instantiate()
		t.position = Vector3(p.x, Land.ground_height(p, false) - 0.14, p.y)
		t.scale = Land.TOWER_SCALE
		for c in t.find_children("*", "Node3D", true, false):
			if "_top_" in str(c.name):
				c.visible = false
		root3.add_child(t)
		var deck := MeshInstance3D.new()
		var dm := CylinderMesh.new()
		dm.top_radius = 2.35
		dm.bottom_radius = 2.35
		dm.height = 0.12
		deck.mesh = dm
		deck.position = Vector3(p.x, Land.ground_height(p, false) + Land.TOWER_FLOOR - 0.06, p.y)
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color("#9c7a52")
		deck.material_override = wood
		root3.add_child(deck)
		posts.append(Vector4(p.x, p.y, Land.OUTPOST_R, 0.45))
		rings.append(Vector4(0.37, 0.82, 0.94, 0.9))
		caps.append(Vector4(1.0, 0.48, 0.32, 0.42 if p.x > 0.0 else 0.0))
	for k in 4:
		posts.append(Vector4.ZERO)
		rings.append(Vector4.ZERO)
		caps.append(Vector4.ZERO)
	View._terrain_material().set_shader_parameter("posts", posts)
	View._terrain_material().set_shader_parameter("post_ring", rings)
	View._terrain_material().set_shader_parameter("post_cap", caps)
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
