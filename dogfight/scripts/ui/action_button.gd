class_name ActionButton
extends Control
## Chunky right-thumb button (FIRE, EVADE ROLL, Tactical Gadget).
##
## Presses and releases an Input action, so it works for both "hold" actions
## (fire) and "tap" actions (roll, gadget). Tracks its own touch index, which
## lets the player hold FIRE with one finger and tap ROLL with another while
## the left thumb is on the stick.
##
## Draws itself: beveled rounded square, simple vector icon, caption, and a
## radial cooldown sweep with the seconds remaining.

enum IconKind { CROSSHAIR, ROLL_ARROW, BOLT }

@export var action: StringName = &"fire"
@export var caption: String = "FIRE"
@export var color: Color = Color("f0433a")
@export var icon_kind: IconKind = IconKind.CROSSHAIR

## 0.0 = ready, 1.0 = cooldown just started. Set every frame by the HUD.
var cooldown_ratio: float = 0.0: set = _set_cooldown_ratio
## Seconds shown in the middle while cooling down (0 hides the number).
var cooldown_seconds: float = 0.0
## Greyed out and ignoring touches (dead, or no gadget equipped).
var disabled: bool = false: set = _set_disabled

var _touch_index: int = -1
var _pressed: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _exit_tree() -> void:
	_set_pressed(false)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch == null:
		return
	if touch.pressed and _touch_index == -1 and get_global_rect().has_point(touch.position):
		_touch_index = touch.index
		if not disabled:
			_set_pressed(true)
		get_viewport().set_input_as_handled()
	elif not touch.pressed and touch.index == _touch_index:
		_touch_index = -1
		_set_pressed(false)


func _draw() -> void:
	var press_offset: Vector2 = Vector2(0.0, 6.0) if _pressed else Vector2.ZERO
	var face_color: Color = color
	if disabled:
		face_color = Color(0.4, 0.43, 0.5)
	elif _pressed:
		face_color = color.darkened(0.15)
	var rect: Rect2 = Rect2(press_offset, size - Vector2(0.0, 10.0))
	var corner: int = int(minf(size.x, size.y) * 0.2)

	# Bottom "shelf" that the face sinks into when pressed.
	var shelf: StyleBoxFlat = StyleBoxFlat.new()
	shelf.bg_color = face_color.darkened(0.5)
	shelf.set_corner_radius_all(corner)
	shelf.set_border_width_all(5)
	shelf.border_color = UiStyle.OUTLINE
	draw_style_box(shelf, Rect2(Vector2(0.0, 10.0), size - Vector2(0.0, 10.0)))

	var face: StyleBoxFlat = StyleBoxFlat.new()
	face.bg_color = face_color
	face.set_corner_radius_all(corner)
	face.set_border_width_all(5)
	face.border_color = UiStyle.OUTLINE
	draw_style_box(face, rect)
	# Glossy top highlight.
	var gloss: StyleBoxFlat = StyleBoxFlat.new()
	gloss.bg_color = Color(1.0, 1.0, 1.0, 0.16)
	gloss.set_corner_radius_all(maxi(corner - 8, 4))
	draw_style_box(gloss, Rect2(rect.position + Vector2(12.0, 12.0), Vector2(rect.size.x - 24.0, rect.size.y * 0.36)))

	var center: Vector2 = rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.42)
	_draw_icon(center, minf(rect.size.x, rect.size.y) * 0.24)
	var caption_size: int = int(clampf(rect.size.x * 0.15, 18.0, 34.0))
	UiStyle.draw_outlined_text(self, caption, rect.position + Vector2(0.0, rect.size.y - 22.0), caption_size, UiStyle.WHITE, rect.size.x)

	if cooldown_ratio > 0.001:
		_draw_cooldown(rect)


func _draw_icon(center: Vector2, icon_size: float) -> void:
	var ink: Color = UiStyle.WHITE
	match icon_kind:
		IconKind.CROSSHAIR:
			draw_arc(center, icon_size, 0.0, TAU, 32, UiStyle.OUTLINE, 11.0, true)
			draw_arc(center, icon_size, 0.0, TAU, 32, ink, 6.0, true)
			for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(center + direction * icon_size * 0.55, center + direction * icon_size * 1.4, UiStyle.OUTLINE, 11.0)
				draw_line(center + direction * icon_size * 0.6, center + direction * icon_size * 1.35, ink, 6.0)
			draw_circle(center, 6.0, ink)
		IconKind.ROLL_ARROW:
			draw_arc(center, icon_size, -PI * 0.15, PI * 1.35, 28, UiStyle.OUTLINE, 13.0, true)
			draw_arc(center, icon_size, -PI * 0.15, PI * 1.35, 28, ink, 7.0, true)
			var tip: Vector2 = center + Vector2.from_angle(-PI * 0.15) * icon_size
			var head: PackedVector2Array = PackedVector2Array([
				tip + Vector2(-2.0, -22.0), tip + Vector2(20.0, 8.0), tip + Vector2(-20.0, 10.0)])
			draw_colored_polygon(head, ink)
			draw_polyline(PackedVector2Array([head[0], head[1], head[2], head[0]]), UiStyle.OUTLINE, 3.0, true)
		IconKind.BOLT:
			var bolt: PackedVector2Array = PackedVector2Array([
				center + Vector2(0.25, -1.3) * icon_size, center + Vector2(-0.75, 0.15) * icon_size,
				center + Vector2(-0.1, 0.15) * icon_size, center + Vector2(-0.3, 1.3) * icon_size,
				center + Vector2(0.75, -0.25) * icon_size, center + Vector2(0.08, -0.25) * icon_size])
			draw_colored_polygon(bolt, UiStyle.GOLD)
			var outline: PackedVector2Array = bolt.duplicate()
			outline.append(bolt[0])
			draw_polyline(outline, UiStyle.OUTLINE, 4.0, true)


## Dark wedge sweeping clockwise from 12 o'clock, clipped to the button face.
func _draw_cooldown(rect: Rect2) -> void:
	var center: Vector2 = rect.get_center()
	var half: Vector2 = rect.size * 0.5 - Vector2(6.0, 6.0)
	var sweep: float = TAU * clampf(cooldown_ratio, 0.0, 1.0)
	var steps: int = maxi(int(sweep / 0.08), 2)
	var shade: PackedColorArray = PackedColorArray([Color(0.03, 0.05, 0.12, 0.62), Color(0.03, 0.05, 0.12, 0.62), Color(0.03, 0.05, 0.12, 0.62)])
	var previous: Vector2 = Vector2.ZERO
	for step: int in range(steps + 1):
		var angle: float = -PI * 0.5 + sweep * float(step) / float(steps)
		var direction: Vector2 = Vector2.from_angle(angle)
		# Project the ray onto the square outline so the wedge fills the corners.
		var reach: float = minf(half.x / maxf(absf(direction.x), 0.0001), half.y / maxf(absf(direction.y), 0.0001))
		var point: Vector2 = center + direction * reach
		# Drawn as a fan of triangles: one big polygon would need triangulating
		# and that fails when the sweep closes on itself at a full cooldown.
		if step > 0:
			draw_primitive(PackedVector2Array([center, previous, point]), shade, PackedVector2Array())
		previous = point
	if cooldown_seconds > 0.05:
		UiStyle.draw_outlined_text(self, "%d" % ceili(cooldown_seconds), rect.position + Vector2(0.0, rect.size.y * 0.55), 54, UiStyle.WHITE, rect.size.x, 10)


func _set_pressed(pressed: bool) -> void:
	if _pressed == pressed:
		return
	_pressed = pressed
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)
	queue_redraw()


func _set_cooldown_ratio(ratio: float) -> void:
	if not is_equal_approx(ratio, cooldown_ratio):
		cooldown_ratio = ratio
		queue_redraw()


func _set_disabled(is_disabled: bool) -> void:
	if disabled == is_disabled:
		return
	disabled = is_disabled
	if disabled:
		_set_pressed(false)
	queue_redraw()
