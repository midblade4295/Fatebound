extends SceneTree
# Dev tool (0.31.172): look at a GLB from round about and from above, without importing it into the project.
#   Xvfb :98 & DISPLAY=:98 MODELS=/abs/a.glb,/abs/b.glb OUT=/tmp/ms_ godot --rendering-method mobile --resolution 1200x800 \
#     --path godot -s res://tools/model_shots.gd
# One PNG per model: <OUT><name>.png, a 3 x 2 sheet -- front, right, back, left at the game camera's pitch, straight
# down, and close on the top. Each model is centred on its bounds and scaled to 4 m tall; a 1 m grid on the ground.
var models: Array = []
var out := "/tmp/ms_"
var frames := 0
var mi := 0
var view := 0
var cam: Camera3D
var holder: Node3D
var shots: Array = []
var bounds := AABB()
const VIEWS := [["front", 0.0, 35.0, 1.0], ["right", 90.0, 35.0, 1.0], ["back", 180.0, 35.0, 1.0], ["left", 270.0, 35.0, 1.0],
	["down", 0.0, 89.0, 1.0], ["top", 30.0, 50.0, 0.5]]

func _init() -> void:
	models = Array(OS.get_environment("MODELS").split(","))
	if OS.has_environment("OUT"):
		out = OS.get_environment("OUT")
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.6, 0.62)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.8)
	e.ambient_light_energy = 0.6
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 12)
	pm.subdivide_width = 11
	pm.subdivide_depth = 11
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.5, 0.3)
	ground.material_override = gm
	root.add_child(ground)
	cam = Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	_load(0)

func _load(i: int) -> void:
	if holder != null:
		holder.queue_free()
	holder = Node3D.new()
	root.add_child(holder)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(str(models[i]), st) != OK:
		push_error("can't read " + str(models[i]))
		return
	var scene: Node3D = doc.generate_scene(st)
	holder.add_child(scene)
	var box := AABB()
	var first := true
	for m in scene.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	var s := 4.0 / maxf(box.size.y, 0.001)
	holder.scale = Vector3.ONE * s
	holder.position = Vector3(-box.get_center().x * s, -box.position.y * s, -box.get_center().z * s)
	bounds = AABB(Vector3(-box.size.x * s * 0.5, 0, -box.size.z * s * 0.5), box.size * s)
	print("MODEL %s size %s (model units %s)" % [str(models[i]).get_file(), str(bounds.size), str(box.size)])

func _process(_d: float) -> bool:
	frames += 1
	if frames < 4:
		return false
	if frames % 3 == 1:
		var v: Array = VIEWS[view]
		var yaw := deg_to_rad(float(v[1]))
		var pitch := deg_to_rad(float(v[2]))
		var dist := 9.5 * float(v[3])
		var tgt := Vector3(0, 2.0 if float(v[3]) >= 1.0 else 3.4, 0)
		cam.position = tgt + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
		cam.look_at(tgt, Vector3.UP if float(v[2]) < 85.0 else Vector3(0, 0, -1))
	elif frames % 3 == 0:
		shots.append(root.get_texture().get_image())
		view += 1
		if view >= VIEWS.size():
			_sheet()
			shots = []
			view = 0
			mi += 1
			if mi >= models.size():
				return true
			_load(mi)
	return false

func _sheet() -> void:
	var w: int = shots[0].get_width()
	var h: int = shots[0].get_height()
	var sheet := Image.create(w * 3, h * 2, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var im: Image = shots[i]
		im.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(im, Rect2i(0, 0, w, h), Vector2i((i % 3) * w, (i / 3) * h))
	var name := str(models[mi]).get_file().get_basename()
	sheet.save_png(out + name + ".png")
	print("SHEET ", out + name + ".png")
