extends SceneTree
# The lake with the real terrain, water and lighting setup (no units): to look for the white patch on the water.
const View = preload("res://scripts/siege/siege_view.gd")
const Land = preload("res://scripts/siege/siege_land.gd")
var frames := 0
var cam: Camera3D
var v
var shots := [["lake_hq", true, Vector3(6.0, 21.0, 25.0), Vector3(4.0, 0.0, 6.0)], ["lake_std", false, Vector3(6.0, 21.0, 25.0), Vector3(4.0, 0.0, 6.0)]]
var si := 0
var water: MeshInstance3D

func _init() -> void:
	v = View.new()
	root.add_child(v)
	v._build_lighting()
	for m in View._make_terrain_meshes():
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = View._terrain_material()
		v.add_child(mi)
	var posts := []
	var rings := []
	var caps := []
	for p in Land.outpost_positions():
		posts.append(Vector4(p.x, p.y, Land.OUTPOST_R, 0.0))
		rings.append(Vector4(1, 1, 1, 0.75))
		caps.append(Vector4(0, 0, 0, 0))
	posts.append(Vector4.ZERO)
	rings.append(Vector4.ZERO)
	caps.append(Vector4.ZERO)
	View._terrain_material().set_shader_parameter("posts", posts)
	View._terrain_material().set_shader_parameter("post_ring", rings)
	View._terrain_material().set_shader_parameter("post_cap", caps)
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.current = true
	v.add_child(cam)
	_setup(0)
	RenderingServer.frame_post_draw.connect(func():
		if frames > 0 and frames % 4 == 0 and si < shots.size():
			root.get_texture().get_image().save_png("/tmp/%s.png" % shots[si][0])
			print("SHOT ", shots[si][0])
			si += 1
			if si < shots.size():
				_setup(si))

func _setup(k: int) -> void:
	if water != null:
		water.queue_free()
	v._water_mat = v._water_hq_material() if shots[k][1] else null
	if v._water_mat == null:
		v._build_water()                      # standard water (adds its own strips)
	else:
		v._water_strip(-Land.HALF_W - 7.0, Land.FALL_X, Land.WATER_Y, 2.0 * (Land.HALF_W + 7.0), "water")
		if v._rip_vp.is_empty():
			v._build_ripples()                  # compile + run the ripple step shader too
		for vp in v._rip_vp:
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		v._water_mat.set_shader_parameter("rip_tex", (v._rip_vp[0] as SubViewport).get_texture())
	cam.position = shots[k][2]
	cam.look_at_from_position(shots[k][2], shots[k][3], Vector3.UP)
	cam.make_current()

func _process(_d: float) -> bool:
	frames += 1
	if si >= shots.size():
		quit(0)
	return false
