extends Node
## Headless test of the human path: 1 player + 9 bots, driven only through the
## same Input actions the touch HUD presses.
##
##   godot --headless --fixed-fps 60 --path . res://tests/TestPlayerFlow.tscn
##
## Script: fire while rolling right -> pull into the turn -> level out -> a
## touch of rudder -> take a gun off and fire again -> look around with a
## finger on the open sky -> dive into the sea. Checks both fitted guns fire,
## the stick rolls and the pull turns, the pedals yaw, a plane with one gun
## fires one gun, the crash gives RED a ticket and the player is back in the
## air 5 seconds later.
## Prints PLAYER_FLOW_OK on success.

enum Step { WAIT_START, FIRE, TURN, LEVEL, RUDDER, ONE_GUN, LOOK, LOOK_BACK, STICK_TOUCH, DIVE, WAIT_RESPAWN, DONE }

var _manager: MatchManager5v5
var _player: PlaneActor
var _hud: Hud
var _camera: ChaseCamera
var _step: Step = Step.WAIT_START
var _step_time: float = 0.0
var _failures: PackedStringArray = PackedStringArray()
var _shots: int = 0
var _death_time: float = -1.0
var _clock: float = 0.0
var _red_before_crash: int = 0
var _shots_before_one_gun: int = 0
var _yaw_before_look: float = 0.0
var _look_sent: bool = false
var _stick_point: Vector2 = Vector2.ZERO
var _look_from: Vector2 = Vector2.ZERO
var _max_fov: float = 0.0
var _yaw_before_turn: float = 0.0
var _yaw_before_rudder: float = 0.0
var _most_rudder: float = 0.0
var _most_slip: float = 0.0


func _ready() -> void:
	Profile.persistence_enabled = false
	Profile.reset_to_new_profile(false)
	GameSession.local_player_enabled = true
	GameSession.match_seed = 11
	GameSession.ground_start = false  # This test is about flying: start in the air.
	GameSession.match_duration = 180.0
	GameSession.bot_skill = 0.0  # Gentle bots: this test is about the player.
	var arena: Node = (load(GameSession.SCENE_ARENA) as PackedScene).instantiate()
	add_child(arena)
	_manager = arena.get_node("MatchManager") as MatchManager5v5
	_hud = arena.get_node("HUD") as Hud
	_camera = arena.get_node("ChaseCamera") as ChaseCamera
	var slot: PilotSlot = _manager.local_slot()
	_check(slot != null and slot.is_human and slot.controller is PlayerController, "seat 0 on BLUE is the local player")
	_check(_manager.get_planes().size() == 10, "ten planes spawned")
	var bots: int = 0
	for other: PilotSlot in _manager.get_roster():
		if other.controller is SquadAIController:
			bots += 1
	_check(bots == 9, "nine seats are filled by bots (got %d)" % bots)
	if slot == null:
		_finish()
		return
	_player = slot.plane
	_check(_player.team == Teams.Id.TEAM_BLUE and _player.is_human, "player plane is a human BLUE plane")
	_check(_camera.target == _player, "chase camera follows the player")
	_check(_hud.player == _player, "HUD is bound to the player")
	_player.shot_fired.connect(func(_plane: PlaneActor) -> void: _shots += 1)
	_player.died.connect(func(_victim: PlaneActor, _killer: PlaneActor) -> void: _death_time = _clock)


func _physics_process(delta: float) -> void:
	if _step == Step.DONE:
		return
	_clock += delta
	_step_time += delta
	_max_fov = maxf(_max_fov, _camera.camera.fov)
	match _step:
		Step.WAIT_START:
			# Weapons are locked during the countdown.
			Input.action_press(GameSession.ACTION_FIRE)
			if _manager.phase == MatchManager5v5.Phase.ACTIVE:
				_check(_shots == 0, "no shots during the countdown (got %d)" % _shots)
				_next(Step.FIRE)
		Step.FIRE:
			Input.action_press(GameSession.ACTION_FIRE)
			Input.action_press(GameSession.ACTION_STEER_RIGHT, 0.6)
			if _step_time >= 1.0:
				Input.action_release(GameSession.ACTION_FIRE)
				Input.action_release(GameSession.ACTION_STEER_RIGHT)
				# Two .303s at 6 rounds a second each.
				_check(_player.stats.gun_count() == 2, "the player's plane has its two stock guns")
				_check(_shots >= 10 and _shots <= 14, "about twelve shots in one second from two guns (got %d)" % _shots)
				_check(_player.bank < -0.25, "stick to the right rolls the plane to the right (bank %.2f rad)" % _player.bank)
				_yaw_before_turn = _player.yaw
				_next(Step.TURN)
		Step.TURN:
			# Banked, then pull: that is what turns an aeroplane.
			Input.action_press(GameSession.ACTION_PITCH_UP, 0.7)
			if _step_time >= 1.5:
				Input.action_release(GameSession.ACTION_PITCH_UP)
				var turned: float = wrapf(_player.yaw - _yaw_before_turn, -PI, PI)
				_check(turned < -0.1, "banked and pulling, it turns to the right (%.2f rad in 1.5 s)" % turned)
				_check(_player.load_factor() > 1.5, "at more than 1 g (%.1f)" % _player.load_factor())
				_next(Step.LEVEL)
		Step.LEVEL:
			_level_wings()
			if _step_time >= 2.5:
				_check(absf(_player.bank) < 0.12, "stick the other way rolls it level again (bank %.2f rad)" % _player.bank)
				_yaw_before_rudder = _player.yaw
				_next(Step.RUDDER)
		Step.RUDDER:
			# A pedal swings the nose without banking: the plane skids.
			_level_wings()
			if _step_time < 1.0:
				Input.action_press(GameSession.ACTION_RUDDER_RIGHT)
				_most_rudder = maxf(_most_rudder, _player.rudder_state)
				_most_slip = minf(_most_slip, _player.sideslip())
			else:
				Input.action_release(GameSession.ACTION_RUDDER_RIGHT)
			if _step_time >= 3.0:
				_check(_most_rudder > 0.6, "the right pedal puts the rudder over (%.2f)" % _most_rudder)
				_check(_most_slip < -deg_to_rad(1.0), "and skids the nose to the right (%.1f degrees of slip)" % rad_to_deg(-_most_slip))
				_check(absf(_player.sideslip()) < deg_to_rad(2.0), "which the plane straightens out of once the pedal is let go (%.1f degrees)" % rad_to_deg(_player.sideslip()))
				_next(Step.ONE_GUN)
		Step.ONE_GUN:
			# Take the right-hand gun off and fire again.
			_level_wings()
			if _step_time >= 0.2 and _shots_before_one_gun == 0:
				_player.stats.fittings[1] = null
				_shots_before_one_gun = _shots
				Input.action_press(GameSession.ACTION_FIRE)
			if _step_time >= 1.2:
				Input.action_release(GameSession.ACTION_FIRE)
				var fired: int = _shots - _shots_before_one_gun
				_check(fired >= 5 and fired <= 7, "with one gun fitted, one gun fires: about six shots in a second (got %d)" % fired)
				_check(_player.last_fired_gun != null and _player.last_fired_gun.id == &"gun_browning_303", "and it is the .303 that is firing")
				_next(Step.LOOK)
		Step.LOOK:
			# A finger dragged across open sky turns the camera, not the plane.
			_level_wings()
			if not _look_sent:
				_look_sent = true
				_yaw_before_look = _player.yaw
				_check(_behind_the_tail() > 0.9, "the camera starts behind the tail (%.2f)" % _behind_the_tail())
				_look_from = _on_screen(Vector2(960.0, 300.0))
				_send_touch(5, _look_from, true)
				_send_drag(5, _look_from, _look_from + Vector2(300.0, 80.0))
			if _step_time >= 0.5:
				_check(absf(_camera.look_angles().x) > 1.2 and _camera.look_angles().y > 0.2, "dragging on open sky swings the view round and up (%.2f, %.2f rad)" % [_camera.look_angles().x, _camera.look_angles().y])
				_check(_behind_the_tail() < 0.3, "the camera has come round from behind the tail (%.2f)" % _behind_the_tail())
				_check(absf(wrapf(_player.yaw - _yaw_before_look, -PI, PI)) < 0.05, "and the plane flew straight on (yaw changed %.3f)" % wrapf(_player.yaw - _yaw_before_look, -PI, PI))
				var arm: float = _camera.camera.global_position.distance_to(_player.global_position)
				_check(arm > 6.0 and arm < 25.0, "the camera is still on its arm (%.1f m from the plane)" % arm)
				_send_touch(5, _look_from + Vector2(300.0, 80.0), false)
				_release_stick()
				_next(Step.LOOK_BACK)
		Step.LOOK_BACK:
			if _step_time >= 0.4 and _step_time < 0.5:
				_check(absf(_camera.look_angles().x) > 1.0, "the view holds for a moment after letting go")
			if _step_time >= 3.0:
				_check(_camera.look_angles().length() < 0.02, "then returns by itself (%.3f rad left)" % _camera.look_angles().length())
				_check(_behind_the_tail() > 0.9, "to behind the tail (%.2f)" % _behind_the_tail())
				# A finger on the flight stick steers; it must not turn the camera.
				_stick_point = _on_screen((_hud.get_node("%Joystick") as Control).get_global_rect().get_center())
				_send_touch(6, _stick_point, true)
				_send_drag(6, _stick_point, _stick_point + Vector2(90.0, 0.0))
				_next(Step.STICK_TOUCH)
		Step.STICK_TOUCH:
			if _step_time >= 0.4:
				_check(_camera.look_angles().length() < 0.02, "a finger on the stick does not turn the camera (%.3f rad)" % _camera.look_angles().length())
				_check(Input.get_action_strength(GameSession.ACTION_STEER_RIGHT) > 0.2, "it moves the stick")
				_send_touch(6, _stick_point + Vector2(90.0, 0.0), false)
				_red_before_crash = _manager.team_score(Teams.Id.TEAM_RED)
				_next(Step.DIVE)
		Step.DIVE:
			# Stick forward until the nose is well down, then let it go in.
			if _player.pitch > deg_to_rad(-55.0):
				Input.action_press(GameSession.ACTION_PITCH_DOWN)
			else:
				Input.action_release(GameSession.ACTION_PITCH_DOWN)
			if not _player.alive:
				Input.action_release(GameSession.ACTION_PITCH_DOWN)
				_check(_max_fov > _camera.base_fov + 6.0, "camera FOV widened in the dive (max %.1f)" % _max_fov)
				_next(Step.WAIT_RESPAWN)
			elif _step_time > 30.0:
				_check(false, "plane never hit the sea")
				_finish()
		Step.WAIT_RESPAWN:
			# One life: there is no other plane, and the sortie is over.
			if _step_time >= 6.0:
				_check(_death_time > 0.0 and not _player.alive, "killed, the player stays killed: no new plane is wheeled out")
				_check(_manager.local_slot().out and _manager.pilots_left(Teams.Id.TEAM_BLUE) == 4, "BLUE is a pilot short (%d left)" % _manager.pilots_left(Teams.Id.TEAM_BLUE))
				_check(_manager.team_score(Teams.Id.TEAM_RED) >= _red_before_crash + 1, "and the loss is RED's gain")
				_check(_manager.outcome == MatchManager5v5.Outcome.LOST and _manager.phase == MatchManager5v5.Phase.FINISHED, "the sortie has ended, lost")
				_check((_hud.get_node("%Results") as Control).visible and (_hud.get_node("%ResultTitle") as Label).text == "KILLED", "and the screen says so")
				_finish()


## Works the stick through its Input actions to roll the wings level.
func _level_wings() -> void:
	var wanted: float = clampf(_player.bank * 2.5 + _player.flight.angular_velocity.z * 0.5, -1.0, 1.0)
	_release_stick()
	if wanted > 0.0:
		Input.action_press(GameSession.ACTION_STEER_RIGHT, pow(wanted, 1.0 / PlayerController.STICK_CURVE))
	elif wanted < 0.0:
		Input.action_press(GameSession.ACTION_STEER_LEFT, pow(-wanted, 1.0 / PlayerController.STICK_CURVE))


func _release_stick() -> void:
	Input.action_release(GameSession.ACTION_STEER_LEFT)
	Input.action_release(GameSession.ACTION_STEER_RIGHT)


## How squarely the camera sits behind the plane: 1 = dead astern, 0 = abeam,
## -1 = ahead of the nose.
func _behind_the_tail() -> float:
	var to_camera: Vector3 = (_camera.camera.global_position - _player.global_position).normalized()
	return -to_camera.dot(_player.forward())


## A point in the HUD's layout, as the place on the window a finger would
## have to touch to hit it (the window may not be the layout's size).
func _on_screen(layout_point: Vector2) -> Vector2:
	return _hud.get_viewport().get_final_transform() * layout_point


func _send_touch(index: int, at: Vector2, pressed: bool) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	Input.parse_input_event(event)


## A drag in ten steps, as a finger would make it.
func _send_drag(index: int, from: Vector2, to: Vector2) -> void:
	var previous: Vector2 = from
	for step: int in range(1, 11):
		var event: InputEventScreenDrag = InputEventScreenDrag.new()
		event.index = index
		event.position = from.lerp(to, float(step) / 10.0)
		event.relative = event.position - previous
		previous = event.position
		Input.parse_input_event(event)


func _next(step: Step) -> void:
	_step = step
	_step_time = 0.0


func _finish() -> void:
	_step = Step.DONE
	for action: StringName in [GameSession.ACTION_FIRE, GameSession.ACTION_RUDDER_RIGHT, GameSession.ACTION_PITCH_UP,
			GameSession.ACTION_PITCH_DOWN, GameSession.ACTION_STEER_RIGHT, GameSession.ACTION_STEER_LEFT]:
		Input.action_release(action)
	if _failures.is_empty():
		print("PLAYER_FLOW_OK")
	else:
		for failure: String in _failures:
			print("FAIL: " + failure)
		print("PLAYER_FLOW_FAILED")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
