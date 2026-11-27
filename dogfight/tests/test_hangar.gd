extends Node
## Headless test of the hangar screen: the plane stands with its propeller
## stopped, and the player can move the camera round it, zoom, slide the plane
## about the screen and put the view back.
##
##   godot --headless --fixed-fps 60 --path . res://tests/TestHangar.tscn
##
## Prints HANGAR_OK on success. Gestures are fed to the menu as the touch
## events a phone would send.

const SETTLE_FRAMES: int = 45

var _menu: Node3D
var _camera: Camera3D
var _turntable: Node3D
var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0
var _frame: int = 0
var _stage: int = 0
var _propeller_start: Basis = Basis.IDENTITY
var _start_position: Vector3 = Vector3.ZERO
## Where the plane sits on the screen, as a share of its height from the middle.
var _start_place: Vector2 = Vector2.ZERO
var _mark: Vector3 = Vector3.ZERO
var _mark_distance: float = 0.0
var _mark_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	Profile.persistence_enabled = false
	Profile.reset_to_new_profile(false)
	_menu = (load(GameSession.SCENE_HANGAR) as PackedScene).instantiate() as Node3D
	add_child(_menu)
	_camera = _menu.get_node("Camera3D") as Camera3D
	_turntable = _menu.get_node("Stage/Turntable") as Node3D


func _process(_delta: float) -> void:
	if _stage < 0:
		return
	_frame += 1
	if _frame < SETTLE_FRAMES:
		return
	_frame = 0
	match _stage:
		0:
			_propeller_start = _propeller().global_transform.basis
			_start_position = _camera.global_position
			_start_place = _place()
			_check(_distance() > 20.0 and _camera.global_position.y > _turntable.global_position.y, "the camera starts back from the plane and above it (%.0f m)" % _distance())
		1:
			_check(_propeller().global_transform.basis.is_equal_approx(_propeller_start), "the propeller is not turning in the hangar")
			_check(_turntable.global_transform.is_equal_approx(Transform3D.IDENTITY), "and the plane is not being spun round")
			# One finger dragged across: the camera goes round the plane.
			_mark_distance = _distance()
			_touch(0, Vector2(900.0, 420.0), true)
			_drag(0, Vector2(900.0, 420.0), Vector2(1100.0, 420.0))
			_touch(0, Vector2(1100.0, 420.0), false)
		2:
			_check(_camera.global_position.distance_to(_start_position) > 10.0, "dragging one finger moves the camera round the plane (%.0f m)" % _camera.global_position.distance_to(_start_position))
			_check(absf(_distance() - _mark_distance) < 0.5, "at the same distance (%.1f -> %.1f m)" % [_mark_distance, _distance()])
			_check(_looks_at_plane(), "still looking at the plane")
			_mark = _camera.global_position
			_touch(0, Vector2(900.0, 300.0), true)
			_drag(0, Vector2(900.0, 300.0), Vector2(900.0, 420.0))
			_touch(0, Vector2(900.0, 420.0), false)
		3:
			_check(_camera.global_position.y > _mark.y + 3.0, "dragging down lifts the camera to look from above (%.1f -> %.1f m)" % [_mark.y, _camera.global_position.y])
			# Drag a very long way: it must stop short of going under the floor
			# or over the top.
			_touch(0, Vector2(900.0, 900.0), true)
			_drag(0, Vector2(900.0, 900.0), Vector2(900.0, -3000.0))
			_touch(0, Vector2(900.0, -3000.0), false)
		4:
			_check(_camera.global_position.y > _turntable.global_position.y - 4.0, "the camera cannot be dragged under the floor (%.1f m)" % _camera.global_position.y)
			_check(_looks_at_plane(), "and still looks at the plane")
			# Two fingers moving apart: zoom in.
			_mark_distance = _distance()
			_touch(0, Vector2(850.0, 400.0), true)
			_touch(1, Vector2(950.0, 400.0), true)
			_drag(0, Vector2(850.0, 400.0), Vector2(750.0, 400.0))
			_drag(1, Vector2(950.0, 400.0), Vector2(1050.0, 400.0))
			_touch(0, Vector2(750.0, 400.0), false)
			_touch(1, Vector2(1050.0, 400.0), false)
		5:
			_check(_distance() < _mark_distance * 0.6, "spreading two fingers zooms in (%.1f -> %.1f m)" % [_mark_distance, _distance()])
			_check(_place().distance_to(_start_place) < 0.05, "and the plane stays where it was on the screen (moved %.3f of its height)" % _place().distance_to(_start_place))
			_mark_distance = _distance()
			_touch(0, Vector2(700.0, 400.0), true)
			_touch(1, Vector2(1100.0, 400.0), true)
			_drag(0, Vector2(700.0, 400.0), Vector2(880.0, 400.0))
			_drag(1, Vector2(1100.0, 400.0), Vector2(920.0, 400.0))
			_touch(0, Vector2(880.0, 400.0), false)
			_touch(1, Vector2(920.0, 400.0), false)
		6:
			_check(_distance() > _mark_distance * 1.5, "pinching zooms out (%.1f -> %.1f m)" % [_mark_distance, _distance()])
			for _notch: int in range(60):
				_wheel(MOUSE_BUTTON_WHEEL_UP)
		7:
			_check(_distance() > 8.0 and _distance() < 16.0, "zooming in stops before the camera is inside the plane (%.1f m)" % _distance())
			for _notch: int in range(120):
				_wheel(MOUSE_BUTTON_WHEEL_DOWN)
		8:
			_check(_distance() > 60.0 and _distance() < 80.0, "and zooming out stops before the plane is a dot (%.1f m)" % _distance())
			# Two fingers moving together: the plane slides across the screen.
			_mark_offset = _place()
			_touch(0, Vector2(800.0, 400.0), true)
			_touch(1, Vector2(900.0, 400.0), true)
			_drag(0, Vector2(800.0, 400.0), Vector2(860.0, 440.0))
			_drag(1, Vector2(900.0, 400.0), Vector2(960.0, 440.0))
			_touch(0, Vector2(860.0, 440.0), false)
			_touch(1, Vector2(960.0, 440.0), false)
		9:
			var slid: Vector2 = _place() - _mark_offset
			_check(slid.x > 0.03 and slid.y > 0.02, "dragging two fingers right and down slides the plane right and down (%.3f, %.3f of the screen's height)" % [slid.x, slid.y])
			# However far it is dragged, it stays on the screen.
			_touch(0, Vector2(800.0, 400.0), true)
			_touch(1, Vector2(900.0, 400.0), true)
			for _sweep: int in range(8):
				_drag(0, Vector2(800.0, 400.0), Vector2(1800.0, 400.0))
				_touches_follow(1, Vector2(900.0, 400.0), Vector2(1900.0, 400.0))
			_touch(0, Vector2(1800.0, 400.0), false)
			_touch(1, Vector2(1900.0, 400.0), false)
		10:
			var total: Vector2 = _place() - _start_place
			_check(total.length() > 0.2 and total.length() <= 0.4, "it can be slid a good way but not off the screen (%.2f of its height)" % total.length())
			# Double tap: back to where it started.
			_touch(0, Vector2(900.0, 400.0), true)
			_touch(0, Vector2(900.0, 400.0), false)
			_touch(0, Vector2(902.0, 401.0), true)
			_touch(0, Vector2(902.0, 401.0), false)
		11:
			_check(_camera.global_position.distance_to(_start_position) < 0.5, "a double tap puts the camera back (%.1f m away)" % _camera.global_position.distance_to(_start_position))
			_check(_place().distance_to(_start_place) < 0.01, "and the plane back in its place")
			# Fitting something rebuilds the model: it must stay still afterwards.
			Profile.unequip_mount(1)
		12:
			_propeller_start = _propeller().global_transform.basis
			_check(not _preview().has_gun_at(1) and _preview().has_gun_at(0), "taking a gun off shows on the plane in the hangar")
		13:
			_check(_propeller().global_transform.basis.is_equal_approx(_propeller_start), "and its propeller is still stopped")
			_finish()
			return
	_stage += 1


func _preview() -> PlaneVisual:
	return _turntable.get_node("PlanePreview") as PlaneVisual


func _propeller() -> Node3D:
	return _preview().find_child(String(_preview().propeller_piece_name()), true, false) as Node3D


## Where the plane's centre is drawn: right and down from the middle of the
## screen, as a share of the screen's height.
func _place() -> Vector2:
	var view_height: float = 2.0 * _distance() * tan(deg_to_rad(_camera.fov) * 0.5)
	return Vector2(-_camera.h_offset, _camera.v_offset) / view_height


func _distance() -> float:
	return _camera.global_position.distance_to(_turntable.global_position)


## The camera's line of sight passes through the turntable (the lens shift
## that places the plane on screen does not turn the camera).
func _looks_at_plane() -> bool:
	var to_plane: Vector3 = (_turntable.global_position - _camera.global_position).normalized()
	return to_plane.dot(-_camera.global_transform.basis.z) > 0.999


func _touch(index: int, at: Vector2, pressed: bool) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	_menu._unhandled_input(event)


## A drag in ten steps, as a finger would make it.
func _drag(index: int, from: Vector2, to: Vector2) -> void:
	var previous: Vector2 = from
	for step: int in range(1, 11):
		var event: InputEventScreenDrag = InputEventScreenDrag.new()
		event.index = index
		event.position = from.lerp(to, float(step) / 10.0)
		event.relative = event.position - previous
		previous = event.position
		_menu._unhandled_input(event)


## Moves a second finger without it counting as a new gesture step: straight
## to where it would be after following the first.
func _touches_follow(index: int, from: Vector2, to: Vector2) -> void:
	_drag(index, from, to)
	# Lift both back to the start so the sweep can be repeated.
	_touch(0, Vector2.ZERO, false)
	_touch(1, Vector2.ZERO, false)
	_touch(0, Vector2(800.0, 400.0), true)
	_touch(1, Vector2(900.0, 400.0), true)


func _wheel(button: MouseButton) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	_menu._unhandled_input(event)


func _finish() -> void:
	_stage = -1
	if _failures.is_empty():
		print("%d checks passed" % _checks)
		print("HANGAR_OK")
	else:
		for failure: String in _failures:
			print("FAIL: " + failure)
		print("HANGAR_FAILED")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
