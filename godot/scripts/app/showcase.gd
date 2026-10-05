extends Control
const Eco = preload("res://scripts/meta/economy.gd")
# 3D hero: the player's equipped look for a class idling on a small stone dais. Transparent
# background so it sits on the pre-rendered Blender backdrop (assets/ui/hero_backdrop.jpg).
# Rendered in its own SubViewport at physical-pixel resolution; only transforms change per frame.
const View = preload("res://scripts/siege/siege_view.gd")
const BACKDROP := "res://assets/ui/hero_backdrop.jpg"

var viewport: SubViewport
var world: Node3D
var holder: Node3D
var body: Node3D
var player: AnimationPlayer
var cls := "knight"
var cosmetic: Dictionary = {}
var _key := ""
# Camera framing (set before the node enters the tree): distance, height, look-at height.
var cam_z := 7.4
var cam_y := 1.45
var look_y := 0.88

static func backdrop(parent: Control) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load(BACKDROP)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	return t

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport)
	var tex := TextureRect.new()
	tex.texture = viewport.get_texture()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tex)
	world = Node3D.new()
	viewport.add_child(world)
	_build_scene()
	resized.connect(_resize)
	_resize()
	_rebuild()

func _resize() -> void:
	# Physical pixels: the canvas is stretched, so scale by window size over logical size.
	var logical := get_viewport().get_visible_rect().size
	var window := Vector2(DisplayServer.window_get_size())
	var ratio := 1.0
	if logical.x > 0 and window.x > 0:
		ratio = clampf(window.x / logical.x, 1.0, 4.0)
	viewport.size = Vector2i(maxi(64, int(size.x * ratio)), maxi(64, int(size.y * ratio)))

func _mat(c: Color, metal := 0.0, rough := 0.75) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _build_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#d8cfe6")
	var vk := RenderingServer.get_current_rendering_method() != "gl_compatibility"
	# Same measured Vulkan compensation as the battle view.
	env.ambient_light_energy = 0.55 * (View.VULKAN_AMBIENT if vk else 1.0)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85 * (View.VULKAN_EXPOSURE if vk else 1.0)
	env.tonemap_white = 3.0
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	# Matches the backdrop: low warm sun behind-left (rim), soft key from the front-right.
	var key := DirectionalLight3D.new()
	key.light_color = Color("#ffe2bd")
	key.light_energy = 1.25
	key.rotation_degrees = Vector3(-28, 28, 0)
	world.add_child(key)
	var sun := OmniLight3D.new()
	sun.light_color = Color("#ff9a4a")
	sun.light_energy = 3.2
	sun.omni_range = 9.0
	sun.position = Vector3(-2.6, 2.4, -2.2)
	world.add_child(sun)
	var cool := OmniLight3D.new()
	cool.light_color = Color("#7f92ff")
	cool.light_energy = 0.9
	cool.omni_range = 8.0
	cool.position = Vector3(2.8, 1.2, 2.4)
	world.add_child(cool)
	var cam := Camera3D.new()
	cam.fov = 30.0
	# Vertical FOV 30 at 7.4 m sees ~4 m of height: the 2.2 m character fills about half the
	# frame, feet at ~78% down (below them the menu's class name and picker sit on the fade).
	cam.position = Vector3(0, cam_y, cam_z)
	world.add_child(cam)
	cam.look_at(Vector3(0, look_y, 0), Vector3.UP)
	# Dais: dark disc shadow, gold-rimmed hex plinth.
	var shadow := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 1.9
	sm.bottom_radius = 1.9
	sm.height = 0.02
	sm.radial_segments = 40
	shadow.mesh = sm
	var shm := StandardMaterial3D.new()
	shm.albedo_color = Color(0, 0, 0, 0.32)
	shm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow.material_override = shm
	shadow.position = Vector3(0, -0.6, 0)
	world.add_child(shadow)
	var edge := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 1.42
	rm.bottom_radius = 1.5
	rm.height = 0.18
	rm.radial_segments = 6
	edge.mesh = rm
	edge.material_override = _mat(Color("#d9a441"), 0.5, 0.35)
	edge.position = Vector3(0, -0.5, 0)
	world.add_child(edge)
	var dais := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 1.3
	dm.bottom_radius = 1.36
	dm.height = 0.28
	dm.radial_segments = 6
	dais.mesh = dm
	dais.material_override = _mat(Color("#77839e"))
	dais.position = Vector3(0, -0.38, 0)
	world.add_child(dais)
	holder = Node3D.new()
	holder.position = Vector3(0, -0.24, 0)
	world.add_child(holder)

func show_look(new_cls: String, new_cosmetic: Dictionary) -> void:
	cls = new_cls
	cosmetic = new_cosmetic
	if is_inside_tree():
		_rebuild()

func _rebuild() -> void:
	var key := "%s|%s" % [cls, str(cosmetic)]
	if key == _key or holder == null:
		return
	_key = key
	if body != null:
		body.queue_free()
	var body_key := str(Eco.UP_LOOK.get(cls, cls))          # 0.31.38: a Crusader is built as a Knight, etc.
	var made: Dictionary = View.make_body(body_key, cosmetic)
	if made.is_empty():
		return
	body = made.body
	player = made.player
	holder.add_child(body)
	body.scale = Vector3.ONE * 1.12
	var idle: String = str(View.LOOKS.get(body_key, View.LOOKS.knight).idle)
	if player.has_animation(idle):
		player.play(idle)

func _process(_delta: float) -> void:
	if holder != null and is_visible_in_tree():
		holder.rotation.y = sin(Time.get_ticks_msec() / 1000.0 * 0.4) * 0.32 - 0.12
