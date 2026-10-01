extends SceneTree
# Game icon render (Round 27): one of Kevin's King models, lit like a portrait, on a transparent background.
#   KING=blue_fatter SIDE=1 OUT=/tmp/icon/king.png SIZE=1024 [CAM="x,y,z" LOOK="x,y,z" FOV=26]
#     godot --rendering-method mobile --path . -s res://tools/icon_render.gd
var vp: SubViewport
var frames := 0

func _v3(s: String, d: Vector3) -> Vector3:
	if s == "":
		return d
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))

func _init() -> void:
	var size := int(OS.get_environment("SIZE")) if OS.has_environment("SIZE") else 1024
	vp = SubViewport.new()
	vp.size = Vector2i(size, size)
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#ffe9c8")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color("#fff1d6")
	key.light_energy = 1.35
	key.rotation_degrees = Vector3(-35, 25, 0)
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("#9fd0ff")
	rim.light_energy = 0.9
	rim.rotation_degrees = Vector3(-20, 160, 0)
	vp.add_child(rim)
	var king := OS.get_environment("KING") if OS.has_environment("KING") else "blue_fatter"
	var m: Node3D = (load("res://assets/kings/king_%s.glb" % king) as PackedScene).instantiate()
	var side := float(OS.get_environment("SIDE")) if OS.has_environment("SIDE") else 1.0
	m.rotation.y = 0.0 if side > 0.0 else PI
	vp.add_child(m)
	# Aim at the head, measured: the models aren't centred on their origin.
	var ab := AABB()
	var first := true
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var gb: AABB = _global_xf(mi as Node3D) * (mi as MeshInstance3D).get_aabb()
		ab = gb if first else ab.merge(gb)
		first = false
	var head := Vector3(ab.get_center().x, ab.end.y - ab.size.y * 0.24, ab.get_center().z)
	print("ICON king AABB %s head %s" % [ab, head])
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.has_environment("FOV") else 26.0
	vp.add_child(cam)
	var off := _v3(OS.get_environment("CAM") if OS.has_environment("CAM") else "", Vector3(-0.45, 0.12, 2.1))
	var look := _v3(OS.get_environment("LOOK") if OS.has_environment("LOOK") else "", Vector3(0.0, 0.0, 0.0))
	cam.look_at_from_position(head + off, head + look)        # (look_at needs the node in the tree)

func _global_xf(n: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p is Node3D:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf

func _process(_d: float) -> bool:
	frames += 1
	if frames == 8:
		var img := vp.get_texture().get_image()
		img.save_png(OS.get_environment("OUT") if OS.has_environment("OUT") else "/tmp/icon/king.png")
		quit(0)
	return false
