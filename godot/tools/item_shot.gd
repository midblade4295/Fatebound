extends SceneTree
# Close-up of the 0.31.0 resources: a boulder node, its rubble, logs and rocks lying about (terrain + real meshes).
const View = preload("res://scripts/siege/siege_view.gd")
const Land = preload("res://scripts/siege/siege_land.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
var frames := 0
func _init() -> void:
	var v = View.new()
	root.add_child(v)
	v._build_lighting()
	for m in View._make_terrain_meshes():
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = View._terrain_material()
		v.add_child(mi)
	var c := Vector2(-6.0, 26.5)
	var y := Sim.height_at(c)
	v._mesh_node(View.boulder_mesh(3, 1.25, 2), Vector3(c.x, y - 0.28, c.y), 0.4)
	v._mesh_node(View.boulder_mesh(5, 1.25, 2), Vector3(c.x + 4.0, Sim.height_at(c + Vector2(4, 0)) - 0.28, c.y), 1.4)
	for k in 4:
		var rp := c + Vector2(-2.2 + k * 0.9, 2.2 + (k % 2) * 0.5)
		v._mesh_node(View.boulder_mesh(k, Sim.ROCK_R + 0.04, 1), Vector3(rp.x, Sim.height_at(rp) + Sim.ROCK_R, rp.y), k * 1.3)
	for k in 3:
		var lp := c + Vector2(2.5 + k * 0.65, 3.2 + k * 0.2)
		var lg: Node3D = v._log_node()
		var ang := 0.3 + k * 0.4
		lg.position = Vector3(lp.x, Sim.height_at(lp) + Sim.LOG_R, lp.y)
		lg.basis = Basis(Vector3(cos(ang), 0, sin(ang)), k) * Basis(Vector3.UP, -ang) * Basis(Vector3(0, 0, 1), PI * 0.5)
	var cam := Camera3D.new()
	cam.fov = 45.0
	v.add_child(cam)
	cam.current = true
	cam.look_at_from_position(Vector3(c.x + 1.0, y + 7.5, c.y + 10.5), Vector3(c.x + 1.0, y, c.y + 1.5), Vector3.UP)
	RenderingServer.frame_post_draw.connect(func():
		if frames == 5:
			root.get_texture().get_image().save_png("/tmp/items.png")
			print("SHOT items"))
func _process(_d: float) -> bool:
	frames += 1
	return frames > 7
