class_name DamageDiagram
extends Control
## Small top-down silhouette of the player's plane that shows which parts are
## hurt: green = fine, yellow = damaged, orange (flashing) = critical,
## red = destroyed. Nose is up, so the left wing is on the left.
## It explains at a glance why the plane has started pulling to one side.

const COLOR_OK: Color = Color(0.42, 0.88, 0.5, 0.9)
const COLOR_DAMAGED: Color = Color(1.0, 0.85, 0.25, 0.95)
const COLOR_CRITICAL: Color = Color(1.0, 0.5, 0.15, 1.0)
const COLOR_DESTROYED: Color = Color(0.75, 0.12, 0.1, 1.0)

var plane: PlaneActor

var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if plane == null or not is_instance_valid(plane):
		return
	var backing: StyleBoxFlat = UiStyle.panel(Color(UiStyle.NAVY, 0.72), 18, UiStyle.OUTLINE, 3, 0)
	draw_style_box(backing, Rect2(Vector2.ZERO, size))
	# Everything is laid out on a unit square and scaled to the control.
	var unit: float = minf(size.x, size.y)
	var origin: Vector2 = (size - Vector2(unit, unit)) * 0.5
	var alive: bool = plane.alive

	var hull_color: Color = COLOR_OK.lerp(COLOR_DESTROYED, 1.0 - plane.hp_ratio()) if alive else COLOR_DESTROYED
	var wing_y: float = 0.36
	_draw_part(origin, unit, Rect2(0.07, wing_y, 0.36, 0.2), _part_color(PlaneActor.Part.LEFT_WING, alive))
	_draw_part(origin, unit, Rect2(0.57, wing_y, 0.36, 0.2), _part_color(PlaneActor.Part.RIGHT_WING, alive))
	_draw_part(origin, unit, Rect2(0.41, 0.3, 0.18, 0.4), hull_color)
	_draw_part(origin, unit, Rect2(0.39, 0.1, 0.22, 0.2), _part_color(PlaneActor.Part.ENGINE, alive))
	var tail_color: Color = _part_color(PlaneActor.Part.TAIL, alive)
	_draw_part(origin, unit, Rect2(0.44, 0.7, 0.12, 0.2), tail_color)
	_draw_part(origin, unit, Rect2(0.3, 0.8, 0.4, 0.1), tail_color)


func _part_color(part: PlaneActor.Part, alive: bool) -> Color:
	if not alive:
		return COLOR_DESTROYED
	match plane.part_state(part):
		PlaneActor.PartState.DAMAGED:
			return COLOR_DAMAGED
		PlaneActor.PartState.CRITICAL:
			# Flash so a failing part catches the eye.
			return COLOR_CRITICAL.lerp(Color.WHITE, 0.35 * (0.5 + 0.5 * sin(_time * 12.0)))
		PlaneActor.PartState.DESTROYED:
			return COLOR_DESTROYED
	return COLOR_OK


func _draw_part(origin: Vector2, unit: float, shape: Rect2, color: Color) -> void:
	var rect: Rect2 = Rect2(origin + shape.position * unit, shape.size * unit)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = UiStyle.OUTLINE
	style.set_border_width_all(3)
	style.set_corner_radius_all(int(minf(rect.size.x, rect.size.y) * 0.4))
	draw_style_box(style, rect)
