class_name LookArea
extends Control
## Lets the pilot look around during a match: a finger dragged anywhere on the
## screen that is not a control swings the chase camera round the plane.
## Letting go returns the view to behind the tail (see ChaseCamera.look_by).
##
## It only ever turns the camera. The stick, buttons and throttle lever claim
## their own touches first, so this sees just the ones that land on open sky,
## and looking around never moves a control or steers the plane.

## The camera to turn. Set by the HUD.
var camera: ChaseCamera

var _touch_index: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _exit_tree() -> void:
	_release()


func _unhandled_input(event: InputEvent) -> void:
	if camera == null or not is_instance_valid(camera) or not is_visible_in_tree():
		return
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		if touch.pressed and _touch_index == -1:
			_touch_index = touch.index
			camera.begin_look()
		elif not touch.pressed and touch.index == _touch_index:
			_release()
		return
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag != null and drag.index == _touch_index:
		camera.look_by(drag.relative)


func _release() -> void:
	if _touch_index == -1:
		return
	_touch_index = -1
	if camera != null and is_instance_valid(camera):
		camera.end_look()
