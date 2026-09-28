extends Control
# 3D hero showcase: the player's equipped look for a class, idling on a stone dais in front of a
# castle. Rendered in its own SubViewport at physical-pixel resolution, shown via a TextureRect.
# Only transforms change per frame (no per-frame material or buffer writes).
const View = preload("res://scripts/siege/siege_view.gd")
const HEX := "res://assets/kaykit/hex/"

var viewport: SubViewport
var world: Node3D
var holder: Node3D
var body: Node3D
var player: AnimationPlayer
var cls := "knight"
var cosmetic: Dictionary = {}
var _key := ""
var spin := 0.35

func _ready() -> void:
	clip_contents = true
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

func _place(path: String, pos: Vector3, rot: float, s: float) -> Node3D:
	var packed: PackedScene = load(path)
	if packed == null:
		return null
	var n: Node3D = packed.instantiate()
	n.position = pos
	n.rotation.y = rot
	n.scale = Vector3.ONE * s
	world.add_child(n)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n

func _mat(c: Color, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.75
	m.metallic = metal
	return m

func _build_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#c9d3e6")
	var vk := RenderingServer.get_current_rendering_method() != "gl_compatibility"
	# Same measured Vulkan compensation as the battle view.
	env.ambient_light_energy = 0.55 * (View.VULKAN_AMBIENT if vk else 1.0)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.8 * (View.VULKAN_EXPOSURE if vk else 1.0)
	env.tonemap_white = 3.0
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.05
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color("#ffe6c2")
	key.light_energy = 1.2
	key.rotation_degrees = Vector3(-35, -30, 0)
	world.add_child(key)
	var rim := OmniLight3D.new()
	rim.light_color = Color("#6fb8ff")
	rim.light_energy = 1.6
	rim.omni_range = 7.0
	rim.position = Vector3(-2.2, 2.6, -1.8)
	world.add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 32.0
	cam.position = Vector3(0, 1.85, 5.6)
	world.add_child(cam)
	cam.look_at(Vector3(0, 1.05, 0), Vector3.UP)
	# Dais: a six-sided stone plinth with a gold rim on a dark ground disc (built from primitives
	# so the colours are controlled; the hex grass tile read as harsh yellow-green here).
	var ground := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 9.0
	gm.bottom_radius = 9.0
	gm.height = 0.1
	gm.radial_segments = 48
	ground.mesh = gm
	ground.material_override = _mat(Color("#2c4033"))
	ground.position = Vector3(0, -0.72, -2.0)
	world.add_child(ground)
	var edge := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 1.42
	rm.bottom_radius = 1.5
	rm.height = 0.18
	rm.radial_segments = 6
	edge.mesh = rm
	edge.material_override = _mat(Color("#c99a3a"), 0.35)
	edge.position = Vector3(0, -0.58, 0)
	world.add_child(edge)
	var dais := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 1.3
	dm.bottom_radius = 1.36
	dm.height = 0.28
	dm.radial_segments = 6
	dais.mesh = dm
	dais.material_override = _mat(Color("#6b7892"))
	dais.position = Vector3(0, -0.46, 0)
	world.add_child(dais)
	_place(HEX + "building_castle_blue.gltf", Vector3(0.4, -1.2, -9.5), 0.0, 3.2)
	_place(HEX + "building_tower_A_blue.gltf", Vector3(-4.2, -1.2, -7.5), 0.0, 2.2)
	_place(HEX + "building_tower_A_blue.gltf", Vector3(4.8, -1.2, -7.8), 0.0, 2.2)
	for x in [-1.9, 1.9]:
		_place(HEX + "flag_blue.gltf", Vector3(x, -0.35, -0.9), 0.0, 1.6)
	holder = Node3D.new()
	holder.position = Vector3(0, -0.32, 0)
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
	var made: Dictionary = View.make_body(cls, cosmetic)
	if made.is_empty():
		return
	body = made.body
	player = made.player
	holder.add_child(body)
	body.scale = Vector3.ONE * 1.05
	var idle: String = str(View.LOOKS.get(cls, View.LOOKS.knight).idle)
	if player.has_animation(idle):
		player.play(idle)

func _process(delta: float) -> void:
	if holder != null and is_visible_in_tree():
		holder.rotation.y = sin(Time.get_ticks_msec() / 1000.0 * spin) * 0.45
