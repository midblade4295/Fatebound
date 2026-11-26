class_name TouchFlightStick
extends Control
## Left-thumb flight stick.
##
## The control's rectangle is the *touch zone* (the whole bottom-left of the
## screen). In floating mode the stick base jumps to wherever the thumb lands
## inside that zone; in fixed mode it stays at its rest position.
##
## Output goes through Input actions (steer_left/right, pitch_up/down) with
## analogue strength, so PlayerController reads touch and keyboard identically.
## Touches are tracked by index in _input(), which makes the stick fully
## independent of the action buttons under the other thumb.

## True: the base re-centres under the thumb. False: classic fixed stick.
@export var floating: bool = true
## Stick travel in pixels at full deflection.
@export var radius: float = 120.0
## Fraction of the travel ignored around the centre.
@export_range(0.0, 0.5) var deadzone: float = 0.12
## Rest position of the base, measured from the zone's bottom-left corner.
@export var rest_offset: Vector2 = Vector2(250.0, -230.0)

## Current stick value: x -1 (left) .. +1 (right), y -1 (down) .. +1 (up).
var value: Vector2 = Vector2.ZERO

var _touch_index: int = -1
var _base_center: Vector2 = Vector2.ZERO
var _knob_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_reset_base)
	_reset_base()


func _exit_tree() -> void:
	_release()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		if touch.pressed and _touch_index == -1 and get_global_rect().has_point(touch.position):
			_touch_index = touch.index
			var local: Vector2 = touch.position - global_position
			if floating:
				_base_center = _clamp_base(local)
			_update_knob(local)
			get_viewport().set_input_as_handled()
		elif not touch.pressed and touch.index == _touch_index:
			_release()
		return
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag != null and drag.index == _touch_index:
		_update_knob(drag.position - global_position)
		get_viewport().set_input_as_handled()


func _draw() -> void:
	var active: bool = _touch_index != -1
	var ring_alpha: float = 0.5 if active else 0.3
	draw_circle(_base_center, radius + 26.0, Color(0.05, 0.1, 0.2, 0.28))
	draw_arc(_base_center, radius + 26.0, 0.0, TAU, 64, Color(1.0, 1.0, 1.0, ring_alpha), 5.0, true)
	# Direction ticks.
	for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var tip: Vector2 = _base_center + direction * (radius + 6.0)
		var side: Vector2 = direction.orthogonal() * 12.0
		draw_colored_polygon(PackedVector2Array([tip, tip - direction * 18.0 + side, tip - direction * 18.0 - side]),
				Color(1.0, 1.0, 1.0, ring_alpha))
	var knob: Vector2 = _base_center + _knob_offset
	draw_circle(knob + Vector2(0.0, 6.0), 56.0, Color(0.0, 0.0, 0.0, 0.3))
	draw_circle(knob, 56.0, Color(0.85, 0.9, 0.97, 0.92 if active else 0.7))
	draw_circle(knob - Vector2(0.0, 6.0), 44.0, Color(1.0, 1.0, 1.0, 0.95 if active else 0.75))
	draw_arc(knob, 56.0, 0.0, TAU, 48, Color(0.04, 0.07, 0.15, 0.9), 4.0, true)


func _update_knob(local_position: Vector2) -> void:
	_knob_offset = (local_position - _base_center).limit_length(radius)
	var raw: Vector2 = _knob_offset / radius
	var magnitude: float = raw.length()
	if magnitude <= deadzone:
		value = Vector2.ZERO
	else:
		# Rescale so the output still starts at 0 just outside the deadzone.
		var scaled: float = (magnitude - deadzone) / (1.0 - deadzone)
		value = raw / magnitude * scaled
		value.y = -value.y  # Screen up is negative Y; stick up means nose up.
	_push_actions()
	queue_redraw()


func _release() -> void:
	_touch_index = -1
	_knob_offset = Vector2.ZERO
	value = Vector2.ZERO
	_push_actions()
	if is_inside_tree():
		_reset_base()


func _reset_base() -> void:
	if _touch_index == -1:
		_base_center = Vector2(rest_offset.x, size.y + rest_offset.y)
	queue_redraw()


## Keeps a floating base far enough from the screen edge to allow full travel.
func _clamp_base(local_position: Vector2) -> Vector2:
	var margin: float = radius * 0.6
	return Vector2(
			clampf(local_position.x, margin, maxf(size.x - margin, margin)),
			clampf(local_position.y, margin, maxf(size.y - margin, margin)))


func _push_actions() -> void:
	_set_action(GameSession.ACTION_STEER_RIGHT, maxf(value.x, 0.0))
	_set_action(GameSession.ACTION_STEER_LEFT, maxf(-value.x, 0.0))
	_set_action(GameSession.ACTION_PITCH_UP, maxf(value.y, 0.0))
	_set_action(GameSession.ACTION_PITCH_DOWN, maxf(-value.y, 0.0))


func _set_action(action: StringName, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	elif Input.is_action_pressed(action):
		Input.action_release(action)
