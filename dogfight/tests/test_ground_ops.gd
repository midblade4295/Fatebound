extends Node
## Headless test of everything that happens with the wheels on the ground:
## the parked start, starting the engine, the take-off run, the undercarriage,
## the throttle, landing well, landing steeply, landing with no wheels, what
## each degree of rough landing breaks, repairs at the home airfield, and the
## bots getting themselves into the air.
##
##   godot --headless --fixed-fps 60 --path . res://tests/TestGroundOps.tscn
##
## Prints GROUND_OPS_OK on success.
##
## The player's plane flies one long scripted sortie. Four more blue planes and
## two red ones are each dropped onto a different approach to the blue airfield
## to make one kind of landing. Three red bots are left to their own devices
## and are expected to take off.

## Seconds into the match at which the landing cases are set up (the player
## has left the runway by then).
const LANDINGS_START: float = 30.0
const TEST_TIMEOUT: float = 190.0
## The take-off run is left unsteered for this long, to see the swing.
const SWING_WATCH_TIME: float = 5.0
## Approaches begin this far above the runway (metres, at the plane's origin),
## at this multiple of the stalling speed with flaps and wheels down.
const APPROACH_HEIGHT: float = 30.0
const APPROACH_SPEED: float = 1.35
## Throttle held on the approaches: enough to keep flying speed, no more.
const APPROACH_THROTTLE: float = 0.3

var _manager: MatchManager5v5
var _player: PlaneActor
var _field: Airfield
var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0
var _clock: float = -1.0
var _stage: int = 0
var _stage_clock: float = 0.0

# --- The player's sortie -----------------------------------------------------
var _shots: int = 0
var _engine_starts: int = 0
var _liftoffs: int = 0
var _liftoff_speed: float = 0.0
var _liftoff_time: float = 0.0
var _roll_start: Vector3 = Vector3.ZERO
var _roll_start_time: float = 0.0
var _roll_distance: float = 0.0
var _tail_pitch_at_speed: float = INF
## How far the nose swung left before anyone corrected it, and the most right
## stick it then took to hold the runway.
var _swing: float = 0.0
var _most_right_stick: float = 0.0
var _gear_moves: Array[bool] = []
var _speed_gear_down: float = 0.0
var _speed_half_throttle: float = 0.0
var _speed_idle: float = 0.0
var _altitude_mark: float = 0.0
# Smoothness of the take-off: the biggest change from one physics tick to the
# next, from the start of the run until a few seconds after leaving the ground.
var _smooth_tracking: bool = false
var _last_pitch: float = 0.0
var _last_climb: float = 0.0
var _last_speed: float = 0.0
var _last_acceleration: float = 0.0
var _last_height: float = 0.0
var _max_pitch_step: float = 0.0
var _max_climb_step: float = 0.0
var _max_acceleration_step: float = 0.0
var _max_height_step: float = 0.0

# --- Landing cases -----------------------------------------------------------
var _cases_started: bool = false
var _cases: Array[LandingCase] = []
var _bots: Array[PlaneActor] = []
var _bots_checked: bool = false
## The plane used for the rough-landing grades, left wrecked at home at the end.
var _wreck: PlaneActor
var _wreck_serviced: bool = false
var _wreck_deadline: float = 0.0
## Undercarriage strength the next _drop() gives its plane (1 = standard).
var _drop_gear_strength: float = 1.0


## One plane making one scripted approach.
class LandingCase:
	extends RefCounted
	var label: String = ""
	var plane: PlaneActor
	var approach_pitch: float = 0.0
	var touchdowns: Array[float] = []
	var on_wheels: bool = false
	var died: bool = false
	var died_on_ground: bool = false
	var death_height: float = 0.0
	var serviced: bool = false
	var serviced_at: float = 0.0
	var stopped_at: float = -1.0
	var stop_distance: float = 0.0
	var touchdown_point: Vector3 = Vector3.ZERO
	var touchdown_time: float = 0.0
	var damage_done: bool = false
	var part_changes: int = 0
	## Damage to the two inner wing panels straight after the first touchdown.
	var wing_damage: Vector2 = Vector2.ZERO
	## What was broken straight after the first touchdown.
	var broken_legs: int = 0
	var broken_prop: bool = false


func _ready() -> void:
	Profile.persistence_enabled = false
	Profile.reset_to_new_profile(false)
	GameSession.local_player_enabled = true
	GameSession.ground_start = true
	GameSession.match_seed = 21
	GameSession.match_duration = 400.0
	GameSession.bot_skill = 0.5
	var arena: Node = (load(GameSession.SCENE_ARENA) as PackedScene).instantiate()
	add_child(arena)
	_manager = arena.get_node("MatchManager") as MatchManager5v5
	_player = _manager.local_slot().plane
	_field = _player.home_airfield()
	_check(_field != null, "the player has a home airfield")
	_check(_manager.arena != null and _manager.arena.airfields.size() == 2, "the arena has an airfield for each team")
	# Bots stay parked unless this test lets them go; nobody shoots.
	var red_seen: int = 0
	for slot: PilotSlot in _manager.get_roster():
		if slot.is_local:
			continue
		if slot.team == Teams.Id.TEAM_RED:
			red_seen += 1
			# The three at the front of the red line are left free to take off.
			if red_seen <= 3:
				_bots.append(slot.plane)
				continue
		slot.controller.set_physics_process(false)
	_manager.local_slot().controller.set_physics_process(false)
	_player.shot_fired.connect(func(_plane: PlaneActor) -> void: _shots += 1)
	_player.engine_started.connect(func(_plane: PlaneActor) -> void: _engine_starts += 1)
	_player.lifted_off.connect(_on_player_lifted_off)
	_player.died.connect(func(_victim: PlaneActor, _killer: PlaneActor) -> void:
		if OS.get_cmdline_user_args().has("verbose=1"):
			print("player died at stage %d (%.1f s in): speed %.0f height %.0f pitch %.0f bank %.0f stalling %s" % [_stage, _stage_clock, _player.speed, _player.global_position.y,
					rad_to_deg(_player.pitch), rad_to_deg(_player.bank), _player.flight.stall > 0.25])
			for other: PlaneActor in _manager.get_planes():
				if other != _player and other.global_position.distance_to(_player.global_position) < 400.0:
					print("  near: %s team %d at %.0f m, alive %s, position %s" % [other.name, int(other.team), other.global_position.distance_to(_player.global_position), other.alive, str(other.global_position.round())])
			print("  player at %s" % str(_player.global_position.round())))
	_player.gear_moved.connect(func(_plane: PlaneActor, going_down: bool) -> void: _gear_moves.append(going_down))
	_test_parked_start()


## Everyone starts on their own runway, wheels down, engine off.
func _test_parked_start() -> void:
	var planes: Array[PlaneActor] = _manager.get_planes()
	var parked: int = 0
	for plane: PlaneActor in planes:
		var home: Airfield = plane.home_airfield()
		if plane.is_on_ground() and home != null and home.is_on_runway(plane.global_position) and not plane.is_engine_running() \
				and plane.is_gear_down() and plane.gear_usable() and is_zero_approx(plane.speed):
			parked += 1
	_check(parked == 10, "all ten planes start parked on their own runway, wheels down, engines off (%d)" % parked)
	var closest: float = INF
	for first: int in range(planes.size()):
		for second: int in range(first + 1, planes.size()):
			closest = minf(closest, planes[first].global_position.distance_to(planes[second].global_position))
	_check(closest > 25.0, "no two are parked on top of each other (closest %.0f m)" % closest)
	var wheel_gap: float = _player.height_above_ground()
	_check(absf(wheel_gap) < 0.3, "the player's plane stands on its wheels (%.2f m off the ground)" % wheel_gap)
	_check(_player.pitch > deg_to_rad(6.0) and _player.pitch < deg_to_rad(20.0), "sitting tail-down (nose up %.0f degrees)" % rad_to_deg(_player.pitch))
	_check(_player.visual.undercarriage_contacts().size() == 2, "the model has an undercarriage to stand on")
	_check(is_zero_approx(_player.input.throttle), "the throttle starts closed")
	_check(not _player.needs_service(), "a new plane needs no repairs")
	var takeoff: float = _player.takeoff_speed()
	_check(takeoff > _player.stats.top_speed * 0.25 and takeoff < _player.stats.top_speed * 0.45, "take-off speed is a sensible share of top speed (%.0f of %.0f m/s)" % [takeoff, _player.stats.top_speed])


func _physics_process(delta: float) -> void:
	if _stage < 0 or _manager.phase != MatchManager5v5.Phase.ACTIVE:
		return
	if _clock < 0.0:
		_clock = 0.0
		for plane: PlaneActor in _manager.get_planes():
			plane.weapons_locked = plane != _player
	_clock += delta
	_stage_clock += delta
	_track_smoothness(delta)
	_fly_player()
	if _clock >= LANDINGS_START and not _cases_started:
		_cases_started = true
		_start_landing_cases()
	for case: LandingCase in _cases:
		_fly_case(case)
	if _clock >= 46.0 and not _bots_checked:
		_bots_checked = true
		_check_bots()
	if _stage >= 100 and _cases_started and _cases_done() and _wreck == null:
		_check_cases()
		_check_touchdown_grades()
	if _wreck != null and (_wreck_serviced or _clock > _wreck_deadline):
		_check_wreck_repaired()
		_finish()
	elif _clock > TEST_TIMEOUT:
		_check(false, "the test ran out of time at stage %d (%s)" % [_stage, _unfinished_cases()])
		_finish()


func _next_stage() -> void:
	_stage += 1
	_stage_clock = 0.0


# ---------------------------------------------------------------------------
# The player's sortie
# ---------------------------------------------------------------------------

func _fly_player() -> void:
	var input: PlaneInput = _player.input
	var top: float = _player.stats.top_speed
	match _stage:
		0:
			# Guns are safe on the ground.
			input.firing = true
			if _stage_clock >= 0.5:
				_check(_shots == 0, "the guns do not fire on the ground (%d shots)" % _shots)
				input.firing = false
				input.throttle = 1.0
				_next_stage()
		1:
			# Throttle wide open, engine off: nothing happens.
			if _stage_clock >= 1.5:
				_check(is_zero_approx(_player.speed) and _player.is_on_ground(), "an open throttle does nothing with the engine off (%.1f m/s)" % _player.speed)
				input.throttle = 0.0
				# Hand over to the real player controller for the keys.
				_manager.local_slot().controller.set_physics_process(true)
				Input.action_press(GameSession.ACTION_ENGINE)
				_next_stage()
		2:
			if _stage_clock >= 0.1:
				Input.action_release(GameSession.ACTION_ENGINE)
				Input.action_press(GameSession.ACTION_THROTTLE_UP)
				_next_stage()
		3:
			if _stage_clock >= 1.0:
				Input.action_release(GameSession.ACTION_THROTTLE_UP)
				_manager.local_slot().controller.set_physics_process(false)
				_check(_engine_starts == 1 and _player.has_flag(PlaneActor.FLAG_ENGINE_ON), "the ENGINE key starts the engine (%d starts)" % _engine_starts)
				_check(input.throttle > 0.5 and input.throttle < 0.9, "holding the throttle key for a second opens it most of the way (%.2f)" % input.throttle)
				_check((_player.audio.get_node("Starter") as AudioStreamPlayer3D).playing, "the starter can be heard")
				input.throttle = 1.0
				# Haul the stick back from the very start: it must not fly early.
				input.steer = Vector2(0.0, 1.0)
				_roll_start = _player.global_position
				_roll_start_time = _clock
				_next_stage()
		4:
			if _player.is_on_ground():
				# For the first few seconds nobody holds it straight; after that
				# the pilot steers down the runway, stick still hard back.
				var steer_x: float = 0.0
				if _stage_clock < SWING_WATCH_TIME:
					_swing = wrapf(_player.yaw - _runway_yaw(), -PI, PI)
				else:
					var place: Vector2 = _field.runway_coordinates(_player.global_position)
					steer_x = clampf(-wrapf(_runway_yaw() + atan(place.x / 70.0) - _player.yaw, -PI, PI) * 5.0, -1.0, 1.0)
					_most_right_stick = maxf(_most_right_stick, steer_x)
				input.steer = Vector2(steer_x, 1.0)
				if _player.speed >= _player.takeoff_speed() * 0.68 and _tail_pitch_at_speed == INF:
					_tail_pitch_at_speed = _player.pitch
				if _stage_clock > 40.0:
					_check(false, "the plane never left the ground (%.0f m/s after 40 s)" % _player.speed)
					_stage = 100
			elif _liftoffs > 0:
				_check(_liftoff_speed >= _player.stats.landing_stall_speed * 0.9, "it stays down until it has flying speed, however hard the stick is pulled (left at %.0f, needs %.0f m/s)" % [_liftoff_speed, _player.takeoff_speed()])
				_check(_roll_distance > 200.0 and _roll_distance < 600.0, "the take-off run uses a good part of the runway (%.0f m of %.0f)" % [_roll_distance, Airfield.RUNWAY_LENGTH])
				var run_time: float = _liftoff_time - _roll_start_time
				_check(run_time > 8.0 and run_time < 25.0, "and takes a believable time (%.1f s)" % run_time)
				_check(_swing > deg_to_rad(1.5), "left to itself the plane swings to the left under power (%.1f degrees in %.0f s)" % [rad_to_deg(_swing), SWING_WATCH_TIME])
				_check(_most_right_stick > 0.05 and absf(_field.runway_coordinates(_player.global_position).x) < Airfield.RUNWAY_WIDTH * 0.5, "and it takes right stick to keep it on the runway (%.2f)" % _most_right_stick)
				_check(_tail_pitch_at_speed < deg_to_rad(4.0), "the tail comes up during the run (nose up %.1f degrees at two-thirds of take-off speed)" % rad_to_deg(_tail_pitch_at_speed))
				_check((_player.audio.get_node("EngineCockpit") as AudioStreamPlayer).playing, "the engine is running in the cockpit")
				_altitude_mark = _player.global_position.y
				_next_stage()
		5:
			# Climb out with the wheels still down.
			input.steer = Vector2(_level_wings(_player), _hold_pitch(_player, deg_to_rad(9.0)))
			if _stage_clock >= 9.0:
				_check(_player.alive and not _player.is_on_ground(), "it climbs away")
				if OS.get_cmdline_user_args().has("verbose=1"):
					print("take-off smoothness per tick: pitch %.3f deg, climb rate %.3f m/s, acceleration %.2f m/s2, height hop %.3f m" % [
							rad_to_deg(_max_pitch_step), _max_climb_step, _max_acceleration_step, _max_height_step])
				_check(_max_pitch_step < deg_to_rad(0.5), "the nose never snaps during the take-off (largest step %.2f degrees in a tick)" % rad_to_deg(_max_pitch_step))
				_check(_max_climb_step < 0.35, "the climb builds smoothly from nothing (largest change %.2f m/s in a tick)" % _max_climb_step)
				_check(_max_acceleration_step < 1.5, "the pull of the engine does not jump at lift-off (largest change %.2f m/s2 in a tick)" % _max_acceleration_step)
				_check(_max_height_step < 0.1, "and the plane never hops (largest %.3f m)" % _max_height_step)
				_check(_player.global_position.y > _altitude_mark + 15.0, "gaining height (%.0f m in 9 s)" % (_player.global_position.y - _altitude_mark))
				_next_stage()
		6:
			# Level off: with the wheels hanging down it is slow.
			input.steer = Vector2(_level_wings(_player), _hold_climb(_player, 5.0))
			if _stage_clock >= 8.0:
				_speed_gear_down = _player.speed
				_check(_speed_gear_down < top * 0.85, "wheels down is draggy (%.0f of %.0f m/s)" % [_speed_gear_down, top])
				input.press_gear()
				_next_stage()
		7:
			input.steer = Vector2(_level_wings(_player), _hold_climb(_player, 5.0))
			if _stage_clock >= 9.0:
				_check(_gear_moves == [false], "the GEAR lever raised the wheels (%s)" % str(_gear_moves))
				_check(is_zero_approx(_player.gear_deploy) and not _player.is_gear_down(), "they are up and locked (%.2f)" % _player.gear_deploy)
				_check((_player.audio.get_node("Gear") as AudioStreamPlayer3D).stream != null, "the undercarriage has a sound")
				_check(_player.speed > _speed_gear_down + top * 0.06, "and the plane is faster for it (%.0f -> %.0f m/s)" % [_speed_gear_down, _player.speed])
				input.throttle = 0.5
				_altitude_mark = _player.global_position.y
				_next_stage()
		8:
			# Half throttle holds a lower speed; closing it altogether leaves a
			# glider that slows for as long as it is held level.
			input.steer = Vector2(_level_wings(_player), _hold_level(_player))
			if _stage_clock >= 8.0 and input.throttle > 0.0:
				_check(_player.speed < top * 0.85 and _player.speed > _player.stats.stall_speed and not _player.is_stalling(),
						"half throttle holds a lower speed, still flying (%.0f of %.0f m/s)" % [_player.speed, top])
				_speed_half_throttle = _player.speed
				input.throttle = 0.0
			if _stage_clock >= 17.0:
				_check(_player.speed < _speed_half_throttle - 5.0, "closing the throttle and holding height slows the plane (%.0f from %.0f m/s)" % [_player.speed, _speed_half_throttle])
				_check(_player.alive and not _player.is_stalling() and _player.speed > _player.stats.stall_speed, "but it is still flying (%.0f m/s; stalls at %.0f)" % [_player.speed, _player.stats.stall_speed])
				_check(_player.is_engine_running(), "the engine is still running with the throttle closed")
				input.throttle = 1.0
				_speed_idle = _player.speed
				_next_stage()
		9:
			input.steer = Vector2(_level_wings(_player), _hold_level(_player))
			if _stage_clock >= 7.0:
				_check(_player.alive and _player.speed > _speed_idle + 6.0, "opening the throttle again brings the speed back (%.0f from %.0f m/s)" % [_player.speed, _speed_idle])
				input.press_engine()
				_next_stage()
		10:
			input.steer = Vector2(_level_wings(_player), _hold_level(_player))
			if _stage_clock >= 2.0:
				_check(not _player.is_engine_running(), "the ENGINE button also switches the engine off")
				_check(not _player.is_going_down() or _player.speed < top * 0.6, "a switched-off engine is not a shot-down plane")
				input.press_engine()
				_stage = 100
		_:
			if _player.alive:
				input.steer = Vector2(_level_wings(_player), _hold_pitch(_player, deg_to_rad(4.0)))


## Watches the player's plane for sudden changes while it takes off.
func _track_smoothness(delta: float) -> void:
	var watching: bool = _stage == 4 or (_stage == 5 and _stage_clock < 5.0)
	var acceleration: float = (_player.speed - _last_speed) / delta
	var height: float = _player.global_position.y
	if watching and _smooth_tracking:
		_max_pitch_step = maxf(_max_pitch_step, absf(_player.pitch - _last_pitch))
		_max_climb_step = maxf(_max_climb_step, absf(_player.velocity.y - _last_climb))
		_max_acceleration_step = maxf(_max_acceleration_step, absf(acceleration - _last_acceleration))
		# Height should change by what the climb rate says, never by a hop.
		_max_height_step = maxf(_max_height_step, absf(height - _last_height) - absf(_player.velocity.y) * delta)
	_smooth_tracking = watching
	_last_pitch = _player.pitch
	_last_climb = _player.velocity.y
	_last_speed = _player.speed
	_last_acceleration = acceleration
	_last_height = height


func _on_player_lifted_off(_plane: PlaneActor) -> void:
	_liftoffs += 1
	if _liftoffs == 1:
		_liftoff_speed = _player.speed
		_liftoff_time = _clock
		_roll_distance = _player.global_position.distance_to(_roll_start)


## Heading of the home runway, as a yaw angle.
func _runway_yaw() -> float:
	var direction: Vector3 = _field.takeoff_direction()
	return atan2(-direction.x, -direction.z)


## Stick position that eases the nose toward [param target] radians.
func _hold_pitch(plane: PlaneActor, target: float) -> float:
	return clampf((target - plane.pitch) * 2.5 - plane.flight.angular_velocity.x * 0.8, -0.6, 0.6)


## Stick position that stops the plane climbing or sinking.
func _hold_level(plane: PlaneActor) -> float:
	return _hold_climb(plane, 0.0)


## Stick position that holds a rate of climb (m/s).
func _hold_climb(plane: PlaneActor, rate: float) -> float:
	return clampf((rate - plane.climb_speed()) * 0.03 - plane.flight.angular_velocity.x * 0.4, -0.5, 0.5)


## Aileron that rolls the wings level. (Positive bank is left wing down.)
func _level_wings(plane: PlaneActor) -> float:
	return clampf(plane.bank * 2.0 + plane.flight.angular_velocity.z * 0.4, -1.0, 1.0)


# ---------------------------------------------------------------------------
# Bots
# ---------------------------------------------------------------------------

func _check_bots() -> void:
	var flying: int = 0
	var wheels_up: int = 0
	var lowest: float = INF
	for bot: PlaneActor in _bots:
		var home: Airfield = bot.home_airfield()
		var height: float = bot.global_position.y - home.surface_y()
		lowest = minf(lowest, height)
		if bot.alive and not bot.is_on_ground() and height > 40.0:
			flying += 1
		if not bot.is_gear_down():
			wheels_up += 1
	_check(flying == _bots.size(), "all %d bots left to themselves have taken off (%d flying, lowest at %.0f m)" % [_bots.size(), flying, lowest])
	_check(wheels_up == _bots.size(), "and raised their wheels (%d)" % wheels_up)


# ---------------------------------------------------------------------------
# Landing cases
# ---------------------------------------------------------------------------

func _start_landing_cases() -> void:
	var blue: Array[PlaneActor] = []
	var red: Array[PlaneActor] = []
	for slot: PilotSlot in _manager.get_roster():
		if slot.is_local or _bots.has(slot.plane):
			continue
		if slot.team == Teams.Id.TEAM_BLUE:
			blue.append(slot.plane)
		else:
			red.append(slot.plane)
	# label, plane, metres right of the centre line, metres along the runway,
	# nose angle on the approach, wheels down?, heading across the island?
	_add_case("good landing", blue[0], 0.0, -50.0, -3.0, true, false)
	_add_case("steep approach", blue[1], 75.0, 150.0, -9.0, true, false)
	_add_case("dive", blue[2], -75.0, 300.0, -45.0, true, false)
	_add_case("belly landing", blue[3], -130.0, 0.0, -2.5, false, false)
	_add_case("enemy airfield", red[0], 38.0, -50.0, -3.0, true, false)
	_add_case("off the edge", red[1], -190.0, 440.0, -3.0, true, true)


func _add_case(label: String, plane: PlaneActor, across: float, along: float, pitch_deg: float, wheels: bool, sideways: bool) -> void:
	var case: LandingCase = LandingCase.new()
	case.label = label
	case.plane = plane
	case.approach_pitch = deg_to_rad(pitch_deg)
	var direction: Vector3 = _field.takeoff_direction()
	var right: Vector3 = direction.cross(Vector3.UP).normalized()
	# The one that is meant to run out of island starts lower, to be down in time.
	var origin: Vector3 = _field.runway_start() + direction * along + right * across + Vector3.UP * (APPROACH_HEIGHT * (0.5 if sideways else 1.0))
	var heading: Vector3 = right if sideways else direction
	if pitch_deg < -20.0:
		# A dive: already pointing at the ground, from higher up.
		origin += Vector3.UP * 60.0
		heading = heading.rotated(heading.cross(Vector3.UP).normalized(), case.approach_pitch)
	plane.set_engine_running(true)
	plane.set_gear_down(wheels)
	plane.input.throttle = APPROACH_THROTTLE
	plane.throttle = APPROACH_THROTTLE
	plane.speed = plane.stats.landing_stall_speed * APPROACH_SPEED
	plane.teleport(Transform3D(Basis.looking_at(heading.normalized(), Vector3.UP), origin))
	plane.touched_down.connect(func(_plane: PlaneActor, sink: float, wheels_down: bool) -> void:
		if case.touchdowns.is_empty():
			case.on_wheels = wheels_down
			case.touchdown_point = plane.global_position
			case.touchdown_time = _clock
			case.wing_damage = Vector2(plane.part_damage_of(PlaneActor.Part.LEFT_WING), plane.part_damage_of(PlaneActor.Part.RIGHT_WING))
			case.broken_legs = plane.broken_gear_mask()
			case.broken_prop = plane.is_propeller_broken()
		case.touchdowns.append(sink))
	plane.died.connect(func(_victim: PlaneActor, _killer: PlaneActor) -> void:
		if not case.died:
			case.died = true
			case.died_on_ground = not case.touchdowns.is_empty() and _field.contains(plane.global_position)
			case.death_height = plane.global_position.y - _field.surface_y())
	plane.serviced.connect(func(_plane: PlaneActor) -> void:
		case.serviced = true
		case.serviced_at = _clock)
	plane.part_state_changed.connect(func(_plane: PlaneActor, _part: PlaneActor.Part, _state: PlaneActor.PartState) -> void: case.part_changes += 1)
	_cases.append(case)


func _fly_case(case: LandingCase) -> void:
	var plane: PlaneActor = case.plane
	if case.died or not plane.alive:
		return
	if not plane.is_on_ground():
		plane.input.steer = Vector2(_level_wings(plane), _hold_pitch(plane, case.approach_pitch))
		plane.input.throttle = APPROACH_THROTTLE
		return
	# Down: stick neutral, throttle closed, which puts the brakes on. The one
	# that is meant to run out of island keeps some power on instead.
	plane.input.steer = Vector2.ZERO
	plane.input.throttle = 0.35 if case.label == "off the edge" else 0.0
	if case.stopped_at < 0.0 and plane.speed < 0.2:
		case.stopped_at = _clock
		case.stop_distance = plane.global_position.distance_to(case.touchdown_point)
		if case.label == "good landing" and not case.damage_done:
			# Now that it is home and stopped: shoot it up and see it mended.
			case.damage_done = true
			plane.apply_damage(1000000.0, null, PlaneActor.Part.RIGHT_WINGTIP)
			plane.apply_damage(1000000.0, null, PlaneActor.Part.RUDDER)
			plane.apply_damage(plane.stats.max_hp * PlaneActor.PART_STRENGTH[PlaneActor.Part.ENGINE] * 0.6, null, PlaneActor.Part.ENGINE)
			plane.fuel = 0.4
			_check(plane.is_part_gone(PlaneActor.Part.RIGHT_AILERON), "losing a wingtip takes its aileron with it")
			case.serviced = false


func _cases_done() -> bool:
	return _unfinished_cases().is_empty()


func _unfinished_cases() -> String:
	var waiting: PackedStringArray = PackedStringArray()
	for case: LandingCase in _cases:
		var done: bool = case.died
		match case.label:
			"good landing":
				done = case.damage_done and case.serviced
			"steep approach":
				done = case.died or case.stopped_at >= 0.0
			"belly landing":
				done = case.died or (case.serviced and case.plane.gear_usable())
		if not done:
			waiting.append(case.label)
	return ", ".join(waiting)


func _check_cases() -> void:
	for case: LandingCase in _cases:
		if OS.get_cmdline_user_args().has("verbose=1"):
			print("%s: touchdowns %s wheels %s died %s (on ground %s, height %.1f) stopped %.1f after %.0f m serviced %s" % [
					case.label, str(case.touchdowns), case.on_wheels, case.died, case.died_on_ground, case.death_height,
					case.stopped_at, case.stop_distance, case.serviced])
		var plane: PlaneActor = case.plane
		var first_sink: float = case.touchdowns[0] if not case.touchdowns.is_empty() else -1.0
		match case.label:
			"good landing":
				_check(not case.touchdowns.is_empty() and case.on_wheels and not case.died, "a gentle approach lands on its wheels and survives")
				_check(first_sink > 0.0 and first_sink <= PlaneActor.FIRM_LANDING_SINK, "coming down gently enough to do no damage (%.1f m/s)" % first_sink)
				_check(case.stop_distance > 120.0 and case.stop_distance < 560.0, "closing the throttle brakes it to a stop on the runway (%.0f m)" % case.stop_distance)
				_check(_field.contains(plane.global_position), "it is still on the airfield")
				_check(case.serviced, "standing still at home, a shot-up plane is repaired")
				var worst: float = 0.0
				for damage: float in plane.part_damage:
					worst = maxf(worst, damage)
				_check(is_zero_approx(worst) and plane.gone_mask() == 0, "every part is as new and the missing ones are back on (worst %.2f)" % worst)
				_check(is_equal_approx(plane.fuel, 1.0), "the tank is full (%.2f)" % plane.fuel)
				_check(plane.visual.has_piece(PlaneActor.Part.RIGHT_WINGTIP) and plane.visual.has_piece(PlaneActor.Part.RIGHT_AILERON) and plane.visual.has_piece(PlaneActor.Part.RUDDER),
						"and the model shows the new wingtip, aileron and rudder")
				var repair_time: float = case.serviced_at - case.stopped_at
				_check(repair_time > 3.0 and repair_time < 30.0, "repairs take a little while, not forever (%.1f s)" % repair_time)
				_check(not plane.needs_service() and plane.engine_power() >= 1.0, "it is ready to fly again")
			"steep approach":
				_check(not case.touchdowns.is_empty() and not case.died, "a steep approach (nose 9 degrees down) is still a landing")
				_check(first_sink < 9.0 and first_sink <= PlaneActor.GEAR_COLLAPSE_SINK, "the flare takes something off the arrival, which is firm (%.1f m/s)" % first_sink)
				_check(case.broken_legs == 0 and not case.broken_prop and case.on_wheels, "nothing breaks")
			"dive":
				_check(case.died and case.touchdowns.is_empty(), "diving straight into the runway does destroy the plane")
				_check(absf(case.death_height) < 8.0, "on the runway, not in the sea (%.1f m above it)" % case.death_height)
			"belly landing":
				_check(not case.touchdowns.is_empty() and not case.on_wheels and not case.died, "with the wheels up it can still be slid on")
				_check(case.stop_distance > 20.0 and case.stop_distance < 330.0, "sliding to a stop sooner than on wheels (%.0f m)" % case.stop_distance)
				_check(case.broken_prop, "at the cost of the propeller")
				_check(case.serviced and plane.gear_usable() and plane.is_on_ground(), "at home it is jacked up, mended and put back on its wheels")
				_check(not plane.is_propeller_broken() and plane.engine_power() >= 1.0, "with a new propeller")
			"enemy airfield":
				_check(not case.touchdowns.is_empty() and case.died, "a plane that stops on the enemy's airfield is lost")
				_check(case.died_on_ground, "there, after landing")
			"off the edge":
				_check(not case.touchdowns.is_empty() and case.died, "running off the edge of the island ends in the sea")
				_check(not case.died_on_ground and case.death_height < -3.0, "it fell off rather than blowing up on the grass (%.1f m)" % case.death_height)
	_check(_manager.team_score(Teams.Id.TEAM_BLUE) >= 2, "planes lost on the ground count as losses (blue has %d)" % _manager.team_score(Teams.Id.TEAM_BLUE))


# ---------------------------------------------------------------------------
# What each degree of rough landing breaks
# ---------------------------------------------------------------------------

## Puts a fresh plane just above the home runway at the given attitude and
## lets it meet the ground at [param sink] m/s.
func _drop(plane: PlaneActor, sink: float, pitch_deg: float, bank_deg: float, wheels: bool) -> void:
	var direction: Vector3 = _field.takeoff_direction()
	plane.respawn(_field.parking_transform(0), true)
	# Whatever undercarriage this bot happened to be given, test the standard one.
	plane.stats.gear_strength = _drop_gear_strength
	plane.set_engine_running(true)
	plane.set_gear_down(wheels)
	plane.speed = plane.stats.landing_stall_speed * 1.3
	plane.teleport(Transform3D(Basis.looking_at(direction, Vector3.UP), _field.runway_start() + direction * 380.0 + Vector3.UP * 20.0))
	plane.pitch = deg_to_rad(pitch_deg)
	plane.bank = deg_to_rad(bank_deg)
	plane._touch_down(_field, sink)


func _check_touchdown_grades() -> void:
	var plane: PlaneActor = _cases[1].plane
	var both: int = PlaneActor.GEAR_LEFT | PlaneActor.GEAR_RIGHT
	var wing: PlaneActor.Part = PlaneActor.Part.LEFT_WING

	_drop(plane, 4.0, 0.0, 0.0, true)
	_check(plane.alive and plane.is_on_ground() and plane.gear_usable() and not plane.needs_service(), "4 m/s on the wheels: a landing, nothing hurt")

	_drop(plane, 8.0, 0.0, 0.0, true)
	_check(plane.alive and plane.gear_usable() and not plane.is_propeller_broken(), "8 m/s: firm, but the undercarriage holds")
	_check(plane.part_damage_of(wing) > 0.05 and plane.part_damage_of(wing) < 0.4, "and the wings are strained (%.2f)" % plane.part_damage_of(wing))

	_drop(plane, 11.0, 0.0, 0.0, true)
	var one_leg: int = plane.broken_gear_mask()
	_check(plane.alive and (one_leg == PlaneActor.GEAR_LEFT or one_leg == PlaneActor.GEAR_RIGHT), "11 m/s: one undercarriage leg collapses, and the plane is not destroyed (mask %d)" % one_leg)
	_check(plane.is_propeller_broken() and plane.engine_power() <= 0.0 and not plane.is_engine_running(), "the propeller hits the runway and the engine can no longer pull")
	_check(plane.is_on_ground() and not plane.gear_usable(), "it is down, sliding on a wingtip")

	_drop(plane, 14.0, 0.0, 0.0, true)
	_check(plane.alive and plane.broken_gear_mask() == both and plane.is_propeller_broken(), "14 m/s: both legs collapse, still not destroyed")

	# The reinforced undercarriage stands a landing that folds the standard one.
	_drop_gear_strength = GameCatalog.find_card(&"gear_reinforced").gear_strength_bonus + 1.0
	_drop(plane, 11.0, 0.0, 0.0, true)
	_check(plane.alive and plane.broken_gear_mask() == 0 and plane.gear_usable() and not plane.is_propeller_broken(), "11 m/s on reinforced undercarriage: it holds")
	_drop_gear_strength = 1.0

	_drop(plane, 20.0, 0.0, 0.0, true)
	_check(plane.alive and plane.is_on_ground(), "20 m/s: a wreck, but one the pilot walks away from")
	_check(plane.part_damage_of(PlaneActor.Part.ENGINE) > 0.5 and plane.part_damage_of(PlaneActor.Part.FUSELAGE) > 0.5,
			"with the engine and fuselage badly damaged (%.2f, %.2f)" % [plane.part_damage_of(PlaneActor.Part.ENGINE), plane.part_damage_of(PlaneActor.Part.FUSELAGE)])

	_drop(plane, 26.0, 0.0, 0.0, true)
	_check(not plane.alive, "26 m/s is flying into the ground: destroyed")

	_drop(plane, 3.0, -12.0, 0.0, true)
	_check(plane.alive and plane.is_propeller_broken() and plane.broken_gear_mask() == 0, "nose 12 degrees down: the propeller is smashed, the undercarriage survives")

	_drop(plane, 3.0, -22.0, 0.0, true)
	_check(plane.alive and plane.is_propeller_broken() and plane.broken_gear_mask() == both, "nose 22 degrees down: the undercarriage folds too")

	_drop(plane, 3.0, -35.0, 0.0, true)
	_check(not plane.alive, "nose 35 degrees down is a dive into the ground: destroyed")

	_drop(plane, 3.0, 0.0, 20.0, true)
	_check(plane.alive and plane.broken_gear_mask() == 0 and plane.part_damage_of(PlaneActor.Part.LEFT_WINGTIP) > 0.3 and is_zero_approx(plane.part_damage_of(PlaneActor.Part.RIGHT_WINGTIP)),
			"left wing 20 degrees low: that wingtip scrapes (%.2f)" % plane.part_damage_of(PlaneActor.Part.LEFT_WINGTIP))

	_drop(plane, 3.0, 0.0, -35.0, true)
	_check(plane.alive and plane.is_part_gone(PlaneActor.Part.RIGHT_WINGTIP) and plane.broken_gear_mask() == PlaneActor.GEAR_RIGHT,
			"right wing 35 degrees low: the wingtip is torn off and that leg collapses (mask %d)" % plane.broken_gear_mask())

	_drop(plane, 3.0, 0.0, 80.0, true)
	_check(not plane.alive, "arriving on a wingtip, nearly on its side: destroyed")

	_drop(plane, 4.0, 0.0, 0.0, false)
	_check(plane.alive and plane.is_propeller_broken() and plane.broken_gear_mask() == 0 and not plane.gear_usable(), "wheels up at 4 m/s: slides on its belly with a smashed propeller")

	# Leave one wrecked at home, standing still, and see it mended.
	_drop(plane, 14.0, 0.0, 0.0, true)
	plane.speed = 0.0
	_wreck = plane
	_wreck_deadline = _clock + 40.0
	plane.serviced.connect(func(_plane: PlaneActor) -> void: _wreck_serviced = true)


func _check_wreck_repaired() -> void:
	_check(_wreck_serviced, "a plane wrecked on its own airfield is repaired there")
	_check(_wreck.broken_gear_mask() == 0 and not _wreck.is_propeller_broken(), "new undercarriage legs and a new propeller are fitted (mask %d)" % _wreck.broken_gear_mask())
	_check(_wreck.gear_usable() and _wreck.engine_power() >= 1.0 and not _wreck.needs_service(), "and it is back on its wheels, ready to fly")
	_check(_wreck.visual.has_gear_leg(0) and _wreck.visual.has_gear_leg(1), "the model shows both legs again")


func _finish() -> void:
	_stage = -1
	for action: StringName in [GameSession.ACTION_ENGINE, GameSession.ACTION_THROTTLE_UP]:
		Input.action_release(action)
	if _failures.is_empty():
		print("%d checks passed" % _checks)
		print("GROUND_OPS_OK")
	else:
		for failure: String in _failures:
			print("FAIL: " + failure)
		print("GROUND_OPS_FAILED")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
