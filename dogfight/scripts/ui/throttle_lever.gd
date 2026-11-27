class_name ThrottleLever
extends Control
## Throttle lever for the right thumb: slide up for power, all the way down to
## close the throttle (which also puts the wheel brakes on, on the ground).
##
## Unlike the stick it does not spring back: it stays where it is left. It
## moves the plane's PlaneInput.throttle directly, because a lever has a
## position and Input actions only have "pressed". Keyboard throttle keys go
## through PlayerController and move the same value, so the lever always shows
## the truth whichever was used.

## Empty space above and below the slot, in pixels.
const TRACK_MARGIN: float = 44.0
const TRACK_WIDTH: float = 26.0
const KNOB_SIZE: Vector2 = Vector2(104.0, 58.0)
const POWER_COLOR: Color = Color("ffb52e")
const IDLE_COLOR: Color = Color("7fd6ff")

## The plane whose throttle this moves. Set by the HUD.
var plane: PlaneActor

var _touch_index: int = -1
var _shown: float = -1.0
var _shown_engine: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if plane == null or not is_instance_valid(plane):
		return
	var engine_on: bool = plane.is_engine_running()
	if not is_equal_approx(plane.input.throttle, _shown) or engine_on != _shown_engine:
		_shown = plane.input.throttle
		_shown_engine = engine_on
		queue_redraw()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or plane == null or not is_instance_valid(plane):
		return
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		if touch.pressed and _touch_index == -1 and get_global_rect().has_point(touch.position):
			_touch_index = touch.index
			_set_from(touch.position.y - global_position.y)
			get_viewport().set_input_as_handled()
		elif not touch.pressed and touch.index == _touch_index:
			_touch_index = -1
			queue_redraw()
		return
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag != null and drag.index == _touch_index:
		_set_from(drag.position.y - global_position.y)
		get_viewport().set_input_as_handled()


func _draw() -> void:
	var value: float = clampf(_shown, 0.0, 1.0)
	var top: float = TRACK_MARGIN
	var bottom: float = size.y - TRACK_MARGIN
	var middle: float = size.x * 0.5
	var slot: StyleBoxFlat = StyleBoxFlat.new()
	slot.bg_color = Color(0.05, 0.1, 0.2, 0.55)
	slot.set_corner_radius_all(13)
	slot.set_border_width_all(4)
	slot.border_color = Color(1.0, 1.0, 1.0, 0.45)
	draw_style_box(slot, Rect2(middle - TRACK_WIDTH * 0.5, top - 10.0, TRACK_WIDTH, bottom - top + 20.0))
	# Quarter marks.
	for mark: int in range(5):
		var y: float = lerpf(bottom, top, float(mark) / 4.0)
		draw_line(Vector2(middle + 24.0, y), Vector2(middle + 40.0, y), Color(1.0, 1.0, 1.0, 0.5), 3.0)
	var knob_y: float = lerpf(bottom, top, value)
	var fill_color: Color = POWER_COLOR if _shown_engine else Color(0.6, 0.64, 0.7)
	if value > 0.01:
		var fill: StyleBoxFlat = StyleBoxFlat.new()
		fill.bg_color = fill_color
		fill.set_corner_radius_all(8)
		draw_style_box(fill, Rect2(middle - TRACK_WIDTH * 0.5 + 6.0, knob_y, TRACK_WIDTH - 12.0, bottom - knob_y + 4.0))
	var knob_rect: Rect2 = Rect2(Vector2(middle, knob_y) - KNOB_SIZE * 0.5, KNOB_SIZE)
	var shelf: StyleBoxFlat = StyleBoxFlat.new()
	shelf.bg_color = Color(0.0, 0.0, 0.0, 0.3)
	shelf.set_corner_radius_all(16)
	draw_style_box(shelf, Rect2(knob_rect.position + Vector2(0.0, 7.0), knob_rect.size))
	var knob: StyleBoxFlat = StyleBoxFlat.new()
	knob.bg_color = Color(0.92, 0.95, 1.0, 0.97 if _touch_index != -1 else 0.82)
	knob.set_corner_radius_all(16)
	knob.set_border_width_all(4)
	knob.border_color = UiStyle.OUTLINE
	draw_style_box(knob, knob_rect)
	for grip: int in range(3):
		var y: float = knob_y + (float(grip) - 1.0) * 12.0
		draw_line(Vector2(middle - 30.0, y), Vector2(middle + 30.0, y), Color(0.2, 0.26, 0.4, 0.7), 4.0)
	var label: String = "BRAKES" if value <= PlaneActor.BRAKE_THROTTLE and plane != null and plane.is_on_ground() else "%d%%" % roundi(value * 100.0)
	UiStyle.draw_outlined_text(self, "THROTTLE", Vector2(0.0, 22.0), 20, UiStyle.WHITE, size.x, 6)
	UiStyle.draw_outlined_text(self, label, Vector2(0.0, size.y - 6.0), 24, fill_color if value > 0.01 else IDLE_COLOR, size.x, 6)


func _set_from(local_y: float) -> void:
	var top: float = TRACK_MARGIN
	var bottom: float = size.y - TRACK_MARGIN
	plane.input.throttle = clampf((bottom - local_y) / maxf(bottom - top, 1.0), 0.0, 1.0)
