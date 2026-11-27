extends Node
## Headless test of the human path: 1 player + 9 bots, driven only through the
## same Input actions the touch HUD presses.
##
##   godot --headless --fixed-fps 60 --path . res://tests/TestPlayerFlow.tscn
##
## Script: fly level and fire -> evade roll -> take a gun off and fire again ->
## look around with a finger on the open sky -> dive into the sea. Checks both fitted guns fire, the roll goes on cooldown,
## a plane with one gun fires one gun, the crash gives RED a ticket and the
## player is back in the air 5 seconds later.
## Prints PLAYER_FLOW_OK on success.

enum Step { WAIT_START, FIRE, ROLL, ONE_GUN, LOOK, LOOK_BACK, STICK_TOUCH, DIVE, WAIT_RESPAWN, DONE }

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
var _evades: int = 0


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
	_player.evade_started.connect(func(_plane: PlaneActor) -> void: _evades += 1)
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
				_check(_player.yaw < -0.2, "steering right turned the plane right (yaw %.2f)" % _player.yaw)
				_check(_player.bank < -0.2, "the plane banks into the turn (bank %.2f)" % _player.bank)
				Input.action_press(GameSession.ACTION_EVADE)
				_next(Step.ROLL)
		Step.ROLL:
			if _step_time >= 0.3:
				Input.action_release(GameSession.ACTION_EVADE)
				_check(_evades == 1, "evade roll started")
				_check(_player.is_evading(), "plane reports it is evading")
				_check(_player.evade_cooldown_ratio() > 0.5, "evade roll is on cooldown")
				_next(Step.ONE_GUN)
		Step.ONE_GUN:
			# Once the roll is over, take the right-hand gun off and fire again.
			if _step_time >= 1.2 and _shots_before_one_gun == 0:
				_player.stats.fittings[1] = null
				_shots_before_one_gun = _shots
				Input.action_press(GameSession.ACTION_FIRE)
			if _step_time >= 2.2:
				Input.action_release(GameSession.ACTION_FIRE)
				var fired: int = _shots - _shots_before_one_gun
				_check(fired >= 5 and fired <= 7, "with one gun fitted, one gun fires: about six shots in a second (got %d)" % fired)
				_check(_player.last_fired_gun != null and _player.last_fired_gun.id == &"gun_browning_303", "and it is the .303 that is firing")
				_next(Step.LOOK)
		Step.LOOK:
			# A finger dragged across open sky turns the camera, not the plane.
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
			Input.action_press(GameSession.ACTION_PITCH_DOWN)
			if not _player.alive:
				Input.action_release(GameSession.ACTION_PITCH_DOWN)
				_check(_manager.team_score(Teams.Id.TEAM_RED) >= _red_before_crash + 1, "crashing gives RED a ticket")
				_check(_manager.local_slot().deaths == 1, "the crash counts as a loss for the player")
				_check(_max_fov > _camera.base_fov + 6.0, "camera FOV widened in the dive (max %.1f)" % _max_fov)
				_next(Step.WAIT_RESPAWN)
			elif _step_time > 20.0:
				_check(false, "plane never hit the sea")
				_finish()
		Step.WAIT_RESPAWN:
			if _player.alive:
				var waited: float = _clock - _death_time
				_check(absf(waited - GameSession.respawn_delay) < 0.1, "respawned after %.2fs (expected %.1f)" % [waited, GameSession.respawn_delay])
				var worst: float = 0.0
				for part_index: int in range(PlaneActor.PART_COUNT):
					worst = maxf(worst, _player.part_damage_of(part_index as PlaneActor.Part))
				_check(is_zero_approx(worst) and is_equal_approx(_player.fuel, 1.0), "respawned with every part intact and a full tank")
				_check(_player.visual.has_piece(PlaneActor.Part.LEFT_WING) and _player.visual.has_piece(PlaneActor.Part.RUDDER), "the model is whole again")
				_check(_player.global_position.z > 1000.0, "respawned over the BLUE base")
				_check(_player.has_flag(PlaneActor.FLAG_SHIELDED), "spawn protection is active")
				_finish()
			elif _step_time > 8.0:
				_check(false, "player never respawned")
				_finish()


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
	for action: StringName in [GameSession.ACTION_FIRE, GameSession.ACTION_EVADE,
			GameSession.ACTION_PITCH_DOWN, GameSession.ACTION_STEER_RIGHT]:
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
