class_name DamageDiagram
extends Control
## Top-down drawing of the player's plane showing the state of every part:
## green = fine, yellow = damaged, orange (flashing) = critical, and a part
## that has been shot off is simply missing, with a red stump where it joined.
## Nose is up, so the left wing is on the left.
##
## This is the game's only damage display. There is no health bar, because
## there is no health: what matters is which parts you still have.

const COLOR_OK: Color = Color(0.42, 0.88, 0.5, 0.92)
const COLOR_DAMAGED: Color = Color(1.0, 0.85, 0.25, 0.95)
const COLOR_CRITICAL: Color = Color(1.0, 0.5, 0.15, 1.0)
const COLOR_DESTROYED: Color = Color(0.8, 0.14, 0.1, 1.0)
const COLOR_GONE: Color = Color(0.8, 0.14, 0.1, 0.28)

## Where each PlaneActor.Part is drawn, as a rectangle on a unit square.
const PART_SHAPES: Array[Rect2] = [
	Rect2(0.42, 0.26, 0.16, 0.36),   # Fuselage
	Rect2(0.41, 0.08, 0.18, 0.18),   # Engine
	Rect2(0.24, 0.32, 0.18, 0.15),   # Left wing (inner panel)
	Rect2(0.58, 0.32, 0.18, 0.15),   # Right wing
	Rect2(0.04, 0.33, 0.2, 0.12),    # Left wingtip
	Rect2(0.76, 0.33, 0.2, 0.12),    # Right wingtip
	Rect2(0.445, 0.62, 0.11, 0.2),   # Tail
	Rect2(0.475, 0.74, 0.05, 0.1),   # Fin
	Rect2(0.475, 0.85, 0.05, 0.1),   # Rudder
	Rect2(0.25, 0.48, 0.16, 0.055),  # Left flap
	Rect2(0.59, 0.48, 0.16, 0.055),  # Right flap
	Rect2(0.06, 0.46, 0.17, 0.05),   # Left aileron
	Rect2(0.77, 0.46, 0.17, 0.05),   # Right aileron
	Rect2(0.3, 0.76, 0.145, 0.07),   # Left elevator
	Rect2(0.555, 0.76, 0.145, 0.07), # Right elevator
]

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
	for index: int in range(PlaneActor.PART_COUNT):
		var part: PlaneActor.Part = index as PlaneActor.Part
		var shape: Rect2 = PART_SHAPES[index]
		var rect: Rect2 = Rect2(origin + shape.position * unit, shape.size * unit)
		var gone: bool = plane.alive and plane.is_part_gone(part)
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.set_corner_radius_all(int(minf(rect.size.x, rect.size.y) * 0.35))
		if gone:
			# Shot off: just a faint outline of where it used to be.
			style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
			style.border_color = COLOR_GONE
			style.set_border_width_all(2)
		else:
			style.bg_color = _part_color(part)
			style.border_color = UiStyle.OUTLINE
			style.set_border_width_all(2)
		draw_style_box(style, rect)


func _part_color(part: PlaneActor.Part) -> Color:
	if not plane.alive:
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
