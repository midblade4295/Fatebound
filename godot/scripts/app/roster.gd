extends Control
# 0.31.79 (Kevin: "just show all the heros instead of player having selection"): Home's line-up -- the seven base
# classes, each in the player's equipped weapon, idling together on the painted dais of the home backdrop. One
# transparent SubViewport at physical resolution, covering only the band the heroes stand in; only transforms and
# skeleton poses change per frame.
const View = preload("res://scripts/siege/siege_view.gd")
const Eco = preload("res://scripts/meta/economy.gd")

# class, x, z (metres on the dais; +z is toward the camera), yaw (turned a little toward the middle)
const SPOTS := [  # class, x, z, yaw, lift -- one arc across the dais, the Knight in front in the middle
	["rogue", -2.85, -0.18, 0.34, 0.0], ["ranger", -1.9, 0.22, 0.23, 0.0], ["barbarian", -1.0, 0.42, -0.35, 0.0],
	["knight", 0.0, 0.95, 0.0, 0.0],
	["mage", 1.0, 0.42, 0.35, 0.0], ["priest", 1.9, 0.22, -0.23, 0.0], ["worker", 2.85, -0.18, -0.34, 0.0],
]

var cam_pos := Vector3(0.0, 3.45, 15.3)          # ~12.7 degrees up, like the painted dais' ellipse
var look_at_pt := Vector3(0.0, 0.9, 0.0)
const FEET_Y := 226.0                           # where a hero standing at the dais' centre has his feet (control px)
var fov := 27.0
var viewport: SubViewport
var world: Node3D
var stage: Node3D
var cam: Camera3D
var looks := {}
var _built := {}

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
	var logical := get_viewport().get_visible_rect().size
	var window := Vector2(DisplayServer.window_get_size())
	var ratio := 1.0
	if logical.x > 0 and window.x > 0:
		ratio = clampf(window.x / logical.x, 1.0, 4.0)
	viewport.size = Vector2i(maxi(64, int(size.x * ratio)), maxi(64, int(size.y * ratio)))

func _build_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#e6d8e8")
	env.ambient_light_energy = 0.6 * View.VULKAN_AMBIENT
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.88 * View.VULKAN_EXPOSURE
	env.tonemap_white = 3.0
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	# The backdrop's sun sits low behind the far castle: a warm rim from behind, a soft key from the front-right.
	var key := DirectionalLight3D.new()
	key.light_color = Color("#ffe6c4")
	key.light_energy = 1.2
	key.rotation_degrees = Vector3(-30, 24, 0)
	world.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("#ffb060")
	rim.light_energy = 1.4
	rim.rotation_degrees = Vector3(-18, 168, 0)
	world.add_child(rim)
	var cool := OmniLight3D.new()
	cool.light_color = Color("#8fa2ff")
	cool.light_energy = 0.8
	cool.omni_range = 12.0
	cool.position = Vector3(-4.0, 2.0, 5.0)
	world.add_child(cool)
	cam = Camera3D.new()
	cam.fov = fov
	world.add_child(cam)
	cam.look_at_from_position(cam_pos, look_at_pt, Vector3.UP)
	stage = Node3D.new()
	world.add_child(stage)

func set_looks(d: Dictionary) -> void:
	looks = d
	if is_inside_tree():
		_rebuild()

func _blob() -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.5, 1.5)
	q.orientation = PlaneMesh.FACE_Y
	m.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var g := Gradient.new()
	g.set_color(0, Color(0.05, 0.03, 0.08, 0.55))
	g.set_color(1, Color(0.05, 0.03, 0.08, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	mat.albedo_texture = gt
	m.material_override = mat
	m.position.y = 0.01
	return m

func _rebuild() -> void:
	if stage == null:
		return
	var i := 0
	for spot in SPOTS:
		var cls: String = spot[0]
		var look: Dictionary = looks.get(cls, {})
		var key := str(look)
		var slot: Node3D = _built.get(cls, {}).get("node", null)
		if slot != null and str(_built[cls].key) == key:
			i += 1
			continue
		if slot != null:
			slot.queue_free()
		slot = Node3D.new()
		slot.position = Vector3(spot[1], spot[4], spot[2])
		slot.rotation.y = spot[3]
		stage.add_child(slot)
		slot.add_child(_blob())
		var made: Dictionary = View.make_body(cls, look)
		if not made.is_empty():
			var body: Node3D = made.body
			body.scale = Vector3.ONE * 1.12
			slot.add_child(body)
			var player: AnimationPlayer = made.player
			var idle: String = str(View.LOOKS.get(cls, View.LOOKS.knight).idle)
			if player != null and player.has_animation(idle):
				player.play(idle)
				player.seek(fmod(0.37 * i, maxf(0.1, player.get_animation(idle).length)), true)
		_built[cls] = {"node": slot, "key": key}
		i += 1
