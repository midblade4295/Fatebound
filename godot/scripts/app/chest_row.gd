extends Control
# 0.31.79: Home's chest slots in 3D -- one transparent SubViewport across the row, an orthographic camera, each chest
# standing over its slot (x = the slot's centre in this control). A ready chest teases (hops and rattles, light leaking
# from the lid); the others breathe.
const Chest3D = preload("res://scripts/app/chest3d.gd")

var slots: Array = []                  # [{kind, mode: "tease"|"idle", x}]
var chest_px := 84.0                   # how wide a chest looks on screen
var base_y := 0.82                     # where the chests' feet sit, as a fraction of the height
var viewport: SubViewport
var world: Node3D
var cam: Camera3D
var _chests: Array = []
var _t := 0.0
const YAW := 28.0
const PITCH := 22.0

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
	Chest3D.stage(world)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.add_child(cam)
	for s in slots:
		var c := Chest3D.make(str(s.kind))
		world.add_child(c)
		_chests.append(c)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var r := Chest3D.viewport_ratio(self)
	viewport.size = Vector2i(maxi(64, int(size.x * r)), maxi(32, int(size.y * r)))
	var upp := 1.95 / chest_px                         # metres per pixel (a chest seen at this angle is ~1.95 m across)
	cam.size = size.y * upp
	var yaw := deg_to_rad(YAW)
	var pitch := deg_to_rad(PITCH)
	var fwd := Vector3(-sin(yaw) * cos(pitch), -sin(pitch), -cos(yaw) * cos(pitch))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var up := right.cross(fwd).normalized()
	# the point at the viewport's centre: chests stand on y = 0, their feet base_y down the frame
	var centre := up * ((base_y - 0.5) * size.y * upp)
	cam.transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), centre - fwd * 20.0)
	for i in _chests.size():
		var x: float = float(slots[i].x)
		(_chests[i] as Node3D).position = right * ((x - size.x * 0.5) * upp)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	for i in _chests.size():
		Chest3D.pose(_chests[i], str(slots[i].mode), _t, i * 0.7)
