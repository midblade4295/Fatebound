extends Control
# The Forge's preview (0.31.93): the chosen weapon set, posed like its icon (weapon_pose.gd), turning slowly, with the
# stars it has (or is about to get) -- sheen, runes, aura and trail exactly as in battle. Its own small world in a
# transparent SubViewport at the screen's resolution.
const View = preload("res://scripts/siege/siege_view.gd")
const WeaponPose = preload("res://scripts/app/weapon_pose.gd")

var viewport: SubViewport
var holder: Node3D
var _key := ""
var _t := 0.0

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
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tex)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#cfd6ea")
	env.ambient_light_energy = 0.6 * View.VULKAN_AMBIENT
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85 * View.VULKAN_EXPOSURE
	env.tonemap_white = 3.0
	var we := WorldEnvironment.new()
	we.environment = env
	viewport.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color("#fff0d6")
	key.light_energy = 1.3
	key.rotation_degrees = Vector3(-28, -30, 0)
	viewport.add_child(key)
	var rim := OmniLight3D.new()
	rim.light_color = Color("#ffb070")
	rim.light_energy = 1.8
	rim.omni_range = 8.0
	rim.position = Vector3(2.2, 2.0, -2.0)
	viewport.add_child(rim)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.3
	cam.transform = Transform3D(Basis.IDENTITY, Vector3(0, 0, 6))
	viewport.add_child(cam)
	holder = Node3D.new()
	viewport.add_child(holder)
	resized.connect(_resize)
	_resize()

func _resize() -> void:
	var logical := get_viewport().get_visible_rect().size
	var window := Vector2(DisplayServer.window_get_size())
	var ratio := 1.0
	if logical.x > 0 and window.x > 0:
		ratio = clampf(window.x / logical.x, 1.0, 3.0)
	var side := maxi(64, int(minf(size.x, size.y) * ratio))
	viewport.size = Vector2i(side, side)

func show_set(r_file: String, l_file: String, fx: Dictionary) -> void:
	var k := "%s|%s|%s" % [r_file, l_file, str(fx)]
	if k == _key:
		return
	_key = k
	for c in holder.get_children():
		holder.remove_child(c)
		c.queue_free()
	WeaponPose.compose(holder, r_file, l_file, fx)

func _process(delta: float) -> void:
	_t += delta
	holder.rotation.y = sin(_t * 0.6) * 0.45             # a slow turn to show the depth and the effects
