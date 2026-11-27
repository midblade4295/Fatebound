class_name SquadAIController
extends Node
## Bot pilot for one plane. Wingmen and enemies run the same brain; only the
## plane's team differs. The match manager attaches one of these to every slot
## that has no human, and can swap it for a PlayerController (or back) at any
## time, because both only write to the plane's PlaneInput.
##
## Structure: a slow "think" (5 Hz, staggered between bots) chooses a state and
## a target; a fast "fly" (every physics tick) turns that into stick input.
##
##   TAKEOFF  parked on the airfield -> start up, roll, lift off, wheels up, climb out.
##   RECOVER  about to hit the sea/a cliff or above the ceiling -> pull away. Always wins.
##   EVADE    someone is shooting us from behind -> break turn, roll, smoke.
##   ENGAGE   chase the chosen target, lead it, fire when the guns bear.
##   PATROL   nobody in range -> loop around the middle of the arena.
##
## Bots are built to fly like people, not like turrets:
##  - They react late. Aiming uses where the target was `_reaction_time` ago,
##    projected forward along its old velocity, so a target flying straight is
##    easy and one that jinks or rolls leaves them shooting at empty sky.
##  - Their aim wanders around the target instead of sitting on it, more so
##    for rookies, when they are being shot at, and when their plane is hurt.
##  - They misjudge deflection for a few seconds at a time, then correct.
##  - Their hands are not instant: stick movement is rate-limited.
##  - They squeeze the trigger a beat after the shot appears, hold it a beat
##    after it has gone, and fire in bursts.
##
## Anti-clumping has three layers: target scoring penalises enemies that
## team-mates already claimed (SquadBlackboard), every bot approaches from its
## own offset "lane", and a separation force pushes nearby planes apart.

enum State { PATROL, ENGAGE, EVADE, RECOVER, TAKEOFF }

const THINK_INTERVAL: float = 0.2
const DETECT_RANGE: float = 1500.0
const SEPARATION_RADIUS: float = 75.0
const SEPARATION_WEIGHT: float = 1.4
## Closer than this to the target the bot breaks off instead of ramming it.
const BREAK_OFF_RANGE: float = 55.0
const BREAK_OFF_TIME: float = 1.3
## In a fast closing pass, break away when this many seconds from the merge.
const HEAD_ON_BREAK_TIME: float = 0.6
## Any plane that will pass within this distance inside AVOID_LOOKAHEAD
## seconds is dodged, friend or foe.
const AVOID_MISS_DISTANCE: float = 14.0
const AVOID_LOOKAHEAD: float = 1.2
const MIN_SAFE_ALTITUDE: float = 90.0
## Seconds of look-ahead used for the "am I about to hit something" checks.
const TERRAIN_LOOKAHEAD: float = 5.0
## Straight steps used to follow the curve of a turn when looking ahead.
const PATH_STEPS: int = 3
## Number of physics ticks of target history kept for the reaction delay.
const TRACK_SAMPLES: int = 40
const LANE_OFFSET: float = 70.0
## Bots drift back into this height band: above the tallest island, which a
## plane cannot turn away from in the room it has once it is among them, and
## below the ceiling so the fight does not creep ever higher.
const PREFERRED_ALTITUDE_MIN: float = 280.0
const PREFERRED_ALTITUDE_MAX: float = 560.0
## A shot is taken when the gun line passes within this many metres of the
## aim point, even if the angular fire cone says no (close-range snapshots).
const SNAPSHOT_MISS_DISTANCE: float = 7.0
## After take-off the bot climbs straight ahead to this height above the
## airfield before it thinks about anything else.
const TAKEOFF_CLIMB_HEIGHT: float = 120.0
const TAKEOFF_CLIMB_PITCH: float = deg_to_rad(13.0)
## Wheels come up once this far off the ground.
const GEAR_UP_HEIGHT: float = 10.0
## Planes parked further back wait this much longer per metre before starting
## up, so the line leaves from the front.
const START_DELAY_PER_METRE: float = 0.07
## A plane on the ground this close ahead in the same lane means "wait".
const TAXI_HOLD_DISTANCE: float = 55.0
const TAXI_LANE_WIDTH: float = 11.0

## 0 = rookie (slow, sloppy aim) .. 1 = ace.
@export_range(0.0, 1.0) var skill: float = 0.55

var plane: PlaneActor
var match_manager: MatchManager5v5
var blackboard: SquadBlackboard
var state: State = State.PATROL
var target: PlaneActor

var _think_timer: float = 0.0
var _threat: PlaneActor
var _threat_age: float = INF
var _evade_timer: float = 0.0
var _evade_side: float = 1.0
var _break_timer: float = 0.0
var _break_side: float = 1.0
var _avoid_side: float = 1.0
var _obstacle_ahead: bool = false
## For judging how fast the plane is turning between one think and the next.
var _last_yaw: float = 0.0
var _think_gap: float = THINK_INTERVAL
# --- Human factors, all derived from `skill` in setup() ---------------------
## Seconds between seeing the target do something and responding to it.
var _reaction_time: float = 0.25
## How hard the stick is pushed per radian of aiming error.
var _steer_gain: float = 6.0
## Stick travel per second (2.0 = centre to full deflection in half a second).
var _stick_speed: float = 5.0
## Size of the aim wander, in radians at the target.
var _wobble_amplitude: float = 0.02
var _wobble_phase: Vector2 = Vector2.ZERO
var _wobble_rate: Vector2 = Vector2.ONE
## Current misjudgement of lead: 0.2 means "pulling 20% too much deflection".
var _lead_bias: float = 0.0
var _lead_bias_timer: float = 0.0
var _trigger_delay: float = 0.15
var _trigger_linger: float = 0.2
var _on_target_time: float = 0.0
var _off_target_time: float = INF
var _burst_time: float = 0.0
var _burst_pause: float = 0.0
var _stick: Vector2 = Vector2.ZERO
## Ring buffer of where the target has been (see _perceive_target).
var _track_positions: Array[Vector3] = []
var _track_velocities: Array[Vector3] = []
var _track_head: int = 0
var _track_count: int = 0
## Personal approach lane: x = sideways, y = vertical, both -1..1.
var _lane: Vector2 = Vector2.ZERO
var _patrol_phase: float = 0.0
## Take-off: seconds left before pressing the starter, and the line on the
## runway (metres right of the centre line) this bot rolls along.
var _start_delay: float = 0.0
var _takeoff_lane: float = 0.0
var _starter_wait: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## Binds this brain to a plane. [param seed_value] makes bots differ from each
## other deterministically (same seed = same personality).
func setup(controlled_plane: PlaneActor, manager: MatchManager5v5, shared_blackboard: SquadBlackboard, seed_value: int) -> void:
	plane = controlled_plane
	match_manager = manager
	blackboard = shared_blackboard
	_rng.seed = seed_value
	_lane = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.8, 0.8))
	_patrol_phase = _rng.randf_range(0.0, TAU)
	_think_timer = _rng.randf_range(0.0, THINK_INTERVAL)  # Stagger bots across frames.
	_evade_side = 1.0 if _rng.randf() > 0.5 else -1.0
	# Personality: every number a little different per bot, all tied to skill.
	_reaction_time = lerpf(0.40, 0.15, skill) + _rng.randf_range(-0.03, 0.03)
	_steer_gain = lerpf(4.5, 8.0, skill)
	_stick_speed = lerpf(3.5, 8.0, skill)
	_wobble_amplitude = deg_to_rad(lerpf(2.4, 0.6, skill))
	_wobble_phase = Vector2(_rng.randf_range(0.0, TAU), _rng.randf_range(0.0, TAU))
	_wobble_rate = Vector2(_rng.randf_range(1.1, 2.2), _rng.randf_range(1.3, 2.6))
	_trigger_delay = lerpf(0.30, 0.08, skill)
	_trigger_linger = _rng.randf_range(0.15, 0.3)
	_track_positions.resize(TRACK_SAMPLES)
	_track_velocities.resize(TRACK_SAMPLES)
	plane.damaged.connect(_on_plane_damaged)
	plane.died.connect(_on_plane_died)
	plane.respawned.connect(_on_plane_respawned)
	if plane.is_node_ready() and plane.alive:
		_on_plane_respawned(plane)


func _exit_tree() -> void:
	_set_target(null)
	if plane != null and is_instance_valid(plane):
		if plane.damaged.is_connected(_on_plane_damaged):
			plane.damaged.disconnect(_on_plane_damaged)
		if plane.died.is_connected(_on_plane_died):
			plane.died.disconnect(_on_plane_died)
		if plane.respawned.is_connected(_on_plane_respawned):
			plane.respawned.disconnect(_on_plane_respawned)


func _physics_process(delta: float) -> void:
	if plane == null or not is_instance_valid(plane) or not multiplayer.is_server():
		return
	if not plane.alive:
		_set_target(null)
		return
	_threat_age += delta
	_evade_timer = maxf(_evade_timer - delta, 0.0)
	_break_timer = maxf(_break_timer - delta, 0.0)
	_burst_pause = maxf(_burst_pause - delta, 0.0)
	_wobble_phase += _wobble_rate * delta
	_lead_bias_timer -= delta
	if _lead_bias_timer <= 0.0:
		# Settle on a new (wrong) idea of how much to lead for a few seconds.
		_lead_bias_timer = _rng.randf_range(2.0, 4.5)
		_lead_bias = _rng.randfn(0.0, lerpf(0.35, 0.08, skill))
	if state == State.TAKEOFF or plane.is_on_ground():
		# Getting off the ground is a job of its own: no fighting until it is done.
		state = State.TAKEOFF
		_set_target(null)
		_fly_takeoff(delta)
		_stick = _stick.move_toward(plane.input.steer, _stick_speed * delta)
		plane.input.steer = _stick
		return
	plane.input.throttle = 1.0
	_record_target()
	_think_timer -= delta
	if _think_timer <= 0.0:
		# Rookies also think a little slower.
		_think_timer = THINK_INTERVAL * lerpf(1.6, 1.0, skill)
		_think_gap = _think_timer
		_think()
	_fly()
	# Hands are not instant: move the real stick toward the wanted position.
	_stick = _stick.move_toward(plane.input.steer, _stick_speed * delta)
	plane.input.steer = _stick


# ---------------------------------------------------------------------------
# Think: choose a state and a target
# ---------------------------------------------------------------------------

func _think() -> void:
	if target != null and not _is_valid_target(target):
		_set_target(null)
	_obstacle_ahead = _check_obstacle_ahead()
	if _obstacle_ahead or _is_altitude_unsafe():
		state = State.RECOVER
		return
	if _evade_timer > 0.0:
		state = State.EVADE
		return
	_set_target(_choose_target())
	state = State.ENGAGE if target != null else State.PATROL


## Best enemy to attack right now, or null. Higher score wins.
func _choose_target() -> PlaneActor:
	var best: PlaneActor = null
	var best_score: float = -INF
	for other: PlaneActor in match_manager.get_planes():
		if not _is_valid_target(other):
			continue
		var score: float = _score_target(other)
		if score > best_score:
			best_score = score
			best = other
	return best


func _score_target(enemy: PlaneActor) -> float:
	var offset: Vector3 = enemy.global_position - plane.global_position
	var distance: float = offset.length()
	if distance > DETECT_RANGE:
		return -INF
	var score: float = 1000.0 - distance
	# Prefer enemies already in front of the nose: less turning, faster shots.
	score += plane.forward().dot(offset / maxf(distance, 0.01)) * 260.0
	# Finish off the wounded.
	score += (1.0 - enemy.condition()) * 220.0
	# A plane that is already on its way down is not worth the ammunition.
	if enemy.is_going_down():
		score -= 650.0
	# Spread out: each team-mate already on this enemy makes it less attractive.
	var others_on_it: int = blackboard.claim_count(enemy)
	if enemy == target:
		others_on_it -= 1
		score += 160.0  # Stick with the current target unless something is much better.
	score -= float(maxi(others_on_it, 0)) * 300.0
	# Turn on whoever is shooting us.
	if enemy == _threat and _threat_age < 4.0:
		score += 140.0
	return score


## Planes on the ground are left alone: strafing an airfield is a good way
## for a bot to fly into it.
func _is_valid_target(other: PlaneActor) -> bool:
	return other != null and is_instance_valid(other) and other.alive \
			and plane.is_hostile_to(other) and not other.is_on_ground()


func _set_target(new_target: PlaneActor) -> void:
	if new_target == target:
		return
	if target != null:
		blackboard.release(target)
	target = new_target
	# New target: nothing is known about how it has been flying yet.
	_track_count = 0
	_on_target_time = 0.0
	_off_target_time = INF
	if target != null:
		blackboard.claim(target)
	if plane != null and is_instance_valid(plane):
		plane.current_target = target


# ---------------------------------------------------------------------------
# Fly: turn the decision into stick input
# ---------------------------------------------------------------------------

func _fly() -> void:
	var input: PlaneInput = plane.input
	input.firing = false
	# Not flying into another aircraft comes before everything except the ground.
	var hazard: PlaneActor = _imminent_collision()
	if hazard != null and state != State.RECOVER:
		_fly_avoid(input, hazard)
		return
	match state:
		State.RECOVER:
			_fly_recover(input)
		State.EVADE:
			_fly_evade(input)
		State.ENGAGE:
			_fly_engage(input)
		State.PATROL:
			_fly_patrol(input)


## Start up, roll down the runway in this bot's own lane, lift off when there
## is flying speed, raise the wheels and climb straight out.
func _fly_takeoff(delta: float) -> void:
	var input: PlaneInput = plane.input
	input.firing = false
	var field: Airfield = plane.airfield_at(plane.global_position)
	var steer: Vector2 = Vector2.ZERO
	if plane.is_on_ground() and field != null:
		_start_delay -= delta
		if not plane.has_flag(PlaneActor.FLAG_ENGINE_ON):
			input.throttle = 0.0
			_starter_wait -= delta
			if _start_delay <= 0.0 and _starter_wait <= 0.0:
				input.press_engine()
				_starter_wait = 1.0  # Give the press a moment before trying again.
			input.steer = steer
			return
		var place: Vector2 = field.runway_coordinates(plane.global_position)
		input.throttle = 0.0 if _taxi_blocked(field, place) else 1.0
		# Hold the lane: aim a little toward it, then straight down the runway.
		var direction: Vector3 = field.takeoff_direction()
		var runway_yaw: float = atan2(-direction.x, -direction.z)
		var desired_yaw: float = runway_yaw - atan((_takeoff_lane - place.x) / 70.0)
		steer.x = clampf(-wrapf(desired_yaw - plane.yaw, -PI, PI) * 4.0, -1.0, 1.0)
		if plane.speed >= plane.takeoff_speed() * 1.05:
			steer.y = 0.6
		input.steer = steer
		return
	if plane.is_on_ground():
		# On the ground somewhere that is not an airfield top: nothing to do.
		input.throttle = 0.0
		input.steer = steer
		return
	# Airborne: wheels up, hold a steady climb, then go and fight.
	input.throttle = 1.0
	var home: Airfield = plane.home_airfield()
	var field_height: float = home.surface_y() if home != null else 0.0
	var height: float = plane.global_position.y - field_height
	if plane.is_gear_down() and height > GEAR_UP_HEIGHT:
		_starter_wait -= delta
		if _starter_wait <= 0.0:
			input.press_gear()
			_starter_wait = 1.0
	steer.y = clampf((TAKEOFF_CLIMB_PITCH - plane.pitch) * 4.0, -1.0, 1.0)
	input.steer = steer
	if height >= TAKEOFF_CLIMB_HEIGHT:
		state = State.PATROL
		_think_timer = 0.0


## True when another plane is on the ground just ahead in this bot's lane.
func _taxi_blocked(field: Airfield, place: Vector2) -> bool:
	for other: PlaneActor in match_manager.get_planes():
		if other == plane or not other.alive or not other.is_on_ground():
			continue
		var where: Vector2 = field.runway_coordinates(other.global_position)
		var ahead: float = where.y - place.y
		if ahead > 0.0 and ahead < TAXI_HOLD_DISTANCE and absf(where.x - place.x) < TAXI_LANE_WIDTH and other.speed < plane.speed + 4.0:
			return true
	return false


func _fly_recover(input: PlaneInput) -> void:
	var steer: Vector2 = Vector2(0.0, 1.0)
	if plane.global_position.y > plane.arena_ceiling - 40.0 and not _obstacle_ahead:
		steer.y = -0.5  # Too high rather than too low.
	if _obstacle_ahead:
		# Turning is what clears an island; some pull as well, but not so
		# much that the turn is starved of lift.
		steer = Vector2(_avoid_side, 0.45)
	input.steer = steer


## The plane, if any, that this one will pass dangerously close to very soon
## if both carry on as they are.
func _imminent_collision() -> PlaneActor:
	var my_position: Vector3 = plane.global_position
	for other: PlaneActor in match_manager.get_planes():
		if other == plane or not other.alive:
			continue
		var offset: Vector3 = other.global_position - my_position
		var relative_velocity: Vector3 = other.velocity - plane.velocity
		var closing_squared: float = relative_velocity.length_squared()
		if closing_squared < 1.0:
			continue
		# Time at which the two are closest, on straight paths.
		var time: float = -offset.dot(relative_velocity) / closing_squared
		if time <= 0.0 or time > AVOID_LOOKAHEAD:
			continue
		if (offset + relative_velocity * time).length() < AVOID_MISS_DISTANCE:
			return other
	return null


## Turn and pull away from [param hazard]: to whichever side and height it is not.
func _fly_avoid(input: PlaneInput, hazard: PlaneActor) -> void:
	var offset: Vector3 = hazard.global_position - plane.global_position
	var right: Vector3 = Vector3(cos(plane.yaw), 0.0, -sin(plane.yaw))
	var turn: float = -1.0 if offset.dot(right) > 0.0 else 1.0
	var pull: float = -0.7 if offset.y > 0.0 else 0.7
	input.steer = Vector2(turn, pull)


func _fly_evade(input: PlaneInput) -> void:
	# Break turn, climbing or diving toward open sky; roll if the attacker is
	# close on our tail.
	input.steer = Vector2(_evade_side, _vertical_escape())
	if _threat != null and is_instance_valid(_threat) and _threat.alive and plane.is_evade_ready():
		var to_threat: Vector3 = _threat.global_position - plane.global_position
		if to_threat.length() < 380.0 and plane.forward().dot(to_threat) < 0.0:
			input.press_evade()


func _fly_engage(input: PlaneInput) -> void:
	if target == null or not _is_valid_target(target):
		_fly_patrol(input)
		return
	var my_position: Vector3 = plane.global_position
	var distance: float = my_position.distance_to(target.global_position)

	# Too close, or closing too fast to pull out later: peel away for a moment
	# so we do not fly through the target.
	var closing_speed: float = (plane.velocity - target.velocity).dot((target.global_position - my_position) / maxf(distance, 0.01))
	var about_to_ram: bool = distance < BREAK_OFF_RANGE or (closing_speed > 60.0 and distance < closing_speed * HEAD_ON_BREAK_TIME)
	if about_to_ram and _break_timer <= 0.0:
		_break_timer = BREAK_OFF_TIME
		_break_side = 1.0 if _rng.randf() > 0.5 else -1.0
	if _break_timer > 0.0:
		input.steer = Vector2(_break_side, _vertical_escape()) * _max_stick()
		return

	var aim_point: Vector3 = _human_aim_point(my_position, distance)

	# Far away, fly toward a personal lane beside/above the target so bots
	# converge from different angles; the lane fades out as they close in.
	var lane_strength: float = clampf((distance - 220.0) / 500.0, 0.0, 1.0)
	var right: Vector3 = Vector3(cos(plane.yaw), 0.0, -sin(plane.yaw))
	var pursuit_point: Vector3 = aim_point + (right * _lane.x + Vector3.UP * _lane.y) * LANE_OFFSET * lane_strength

	var desired: Vector3 = (pursuit_point - my_position).normalized()
	desired = (desired + _separation() * SEPARATION_WEIGHT).normalized()
	# The height bias fades out when lined up for a shot so it never spoils aim.
	desired.y += _altitude_bias() * lane_strength
	input.steer = _steer_toward(desired.normalized()) * _max_stick()

	# The trigger follows what the pilot *thinks* is a good shot: the nose near
	# their own (imperfect) aim point. Whether bullets land is up to physics.
	var angle_off: float = Ballistics.angle_off_nose(my_position, plane.forward(), aim_point)
	var fire_cone: float = maxf(deg_to_rad(lerpf(6.0, 3.0, skill)), atan(SNAPSHOT_MISS_DISTANCE / maxf(distance, 1.0)))
	var looks_good: bool = distance < plane.stats.gun_range * 0.95 and angle_off < fire_cone
	input.firing = _pull_trigger(looks_good, get_physics_process_delta_time())


## Where this pilot is trying to put the gunsight. Starts from the true lead
## solution for the target *as perceived* (late), then adds the pilot's own
## errors: misjudged deflection and a wandering hand.
func _human_aim_point(my_position: Vector3, distance: float) -> Vector3:
	var seen_position: Vector3 = target.global_position
	var seen_velocity: Vector3 = target.velocity
	if _track_count > 0:
		var ticks_ago: int = clampi(roundi(_reaction_time * float(Engine.physics_ticks_per_second)), 0, _track_count - 1)
		var index: int = posmod(_track_head - 1 - ticks_ago, TRACK_SAMPLES)
		seen_velocity = _track_velocities[index]
		# The pilot assumes the target kept doing what it was last seen doing.
		seen_position = _track_positions[index] + seen_velocity * (float(ticks_ago) / float(Engine.physics_ticks_per_second))
	var lead: Vector3 = Ballistics.lead_point(my_position, plane.velocity, seen_position, seen_velocity, plane.stats.bullet_speed)
	var aim_point: Vector3 = seen_position + (lead - seen_position) * (1.0 + _lead_bias)

	# Wander: two slow sine waves per axis, never repeating in step. Worse
	# under fire and when the pilot is fighting a damaged plane.
	var stress: float = 1.0
	if _threat_age < 1.5:
		stress += 0.7
	# A plane with missing lift or surfaces is hard to hold steady.
	stress += 0.6 * (1.0 - plane.condition())
	var wander: Vector2 = Vector2(
			0.65 * sin(_wobble_phase.x) + 0.35 * sin(_wobble_phase.x * 2.7 + 1.3),
			0.65 * sin(_wobble_phase.y) + 0.35 * sin(_wobble_phase.y * 2.3 + 0.4))
	var right: Vector3 = Vector3(cos(plane.yaw), 0.0, -sin(plane.yaw))
	return aim_point + (right * wander.x + Vector3.UP * wander.y) * _wobble_amplitude * stress * distance


## Remembers where the target is each tick so aiming can look into the past.
func _record_target() -> void:
	if target == null or not is_instance_valid(target) or not target.alive:
		_track_count = 0
		return
	_track_positions[_track_head] = target.global_position
	_track_velocities[_track_head] = target.velocity
	_track_head = (_track_head + 1) % TRACK_SAMPLES
	_track_count = mini(_track_count + 1, TRACK_SAMPLES)


## Trigger discipline. [param looks_good] is "the sight picture is right now".
## Returns whether the guns fire this tick.
func _pull_trigger(looks_good: bool, delta: float) -> bool:
	if looks_good:
		_on_target_time += delta
		_off_target_time = 0.0
	else:
		_off_target_time += delta
		_on_target_time = 0.0
	# Squeeze a beat late, and keep squeezing a beat after the shot has gone.
	var squeezing: bool = _on_target_time >= _trigger_delay or (plane.input.firing and _off_target_time < _trigger_linger)
	if not squeezing or _burst_pause > 0.0:
		return false
	# Short bursts with a breath between them, not one endless stream.
	if _burst_time <= 0.0:
		_burst_time = _rng.randf_range(0.5, 1.3)
	_burst_time -= delta
	if _burst_time <= 0.0:
		_burst_pause = _rng.randf_range(0.2, 0.55)
	return true


func _fly_patrol(input: PlaneInput) -> void:
	# Lazy orbit around the arena centre at a personal height.
	_patrol_phase += 0.004
	# Inside the ring of islands, and above the tallest of them.
	var radius: float = plane.arena_radius * 0.26
	var point: Vector3 = plane.arena_center + Vector3(cos(_patrol_phase) * radius, 0.0, sin(_patrol_phase) * radius)
	point.y = 330.0 + _lane.y * 50.0
	var desired: Vector3 = (point - plane.global_position).normalized()
	desired = (desired + _separation() * SEPARATION_WEIGHT).normalized()
	desired.y += _altitude_bias()
	input.steer = _steer_toward(desired.normalized()) * 0.8


## Converts a desired world direction into stick deflection using the plane's
## yaw/pitch angles (not its banked basis, which would mix the two axes).
func _steer_toward(direction: Vector3) -> Vector2:
	var desired_yaw: float = atan2(-direction.x, -direction.z)
	var desired_pitch: float = asin(clampf(direction.y, -1.0, 1.0))
	var yaw_error: float = wrapf(desired_yaw - plane.yaw, -PI, PI)
	var pitch_error: float = desired_pitch - plane.pitch
	return Vector2(
			clampf(-yaw_error * _steer_gain, -1.0, 1.0),
			clampf(pitch_error * _steer_gain, -1.0, 1.0))


## Push away from every nearby plane (either team) so formations stay loose.
func _separation() -> Vector3:
	var push: Vector3 = Vector3.ZERO
	var my_position: Vector3 = plane.global_position
	for other: PlaneActor in match_manager.get_planes():
		if other == plane or other == target or not other.alive:
			continue
		var away: Vector3 = my_position - other.global_position
		var distance: float = away.length()
		if distance < SEPARATION_RADIUS and distance > 0.01:
			push += away / distance * (1.0 - distance / SEPARATION_RADIUS)
	return push


func _max_stick() -> float:
	return lerpf(0.78, 1.0, skill)


## Stick pitch for "get out of here" manoeuvres: up when low, down when high,
## so escapes use the whole height of the arena instead of always climbing.
func _vertical_escape() -> float:
	var middle: float = (PREFERRED_ALTITUDE_MIN + PREFERRED_ALTITUDE_MAX) * 0.5
	return 0.45 if plane.global_position.y < middle else -0.4


## Gentle vertical nudge back toward the preferred height band.
func _altitude_bias() -> float:
	var height: float = plane.global_position.y
	if height > PREFERRED_ALTITUDE_MAX:
		return -clampf((height - PREFERRED_ALTITUDE_MAX) / 220.0, 0.0, 0.7)
	if height < PREFERRED_ALTITUDE_MIN:
		return clampf((PREFERRED_ALTITUDE_MIN - height) / 90.0, 0.0, 0.7)
	return 0.0


# ---------------------------------------------------------------------------
# Safety checks
# ---------------------------------------------------------------------------

func _is_altitude_unsafe() -> bool:
	var height: float = plane.global_position.y
	var sink_rate: float = -plane.velocity.y
	if height - sink_rate * TERRAIN_LOOKAHEAD < MIN_SAFE_ALTITUDE:
		return true
	return height > plane.arena_ceiling


## Looks ahead for something solid, both straight off the nose and round the
## curve the plane is actually flying (a turning plane does not go where its
## nose points). Also probes left and right to decide which way to turn away;
## if that does not settle it, it turns toward the middle of the arena, where
## there is nothing to hit.
func _check_obstacle_ahead() -> bool:
	var space: PhysicsDirectSpaceState3D = plane.get_world_3d().direct_space_state
	var origin: Vector3 = plane.global_position
	var nose: Vector3 = plane.forward()
	var reach: float = maxf(plane.speed, 40.0) * TERRAIN_LOOKAHEAD
	var blocked: bool = _ray_blocked(space, origin, origin + nose * reach)
	if not blocked:
		# Along the turn: a few straight steps, each swung round by how far
		# the plane will have turned by then.
		var turn_rate: float = wrapf(plane.yaw - _last_yaw, -PI, PI) / maxf(_think_gap, 0.01)
		var step_time: float = TERRAIN_LOOKAHEAD / float(PATH_STEPS)
		var point: Vector3 = origin
		for step: int in range(PATH_STEPS):
			var heading: Vector3 = nose.rotated(Vector3.UP, turn_rate * step_time * (float(step) + 0.5))
			var next: Vector3 = point + heading * maxf(plane.speed, 40.0) * step_time
			if _ray_blocked(space, point, next):
				blocked = true
				break
			point = next
	_last_yaw = plane.yaw
	if not blocked:
		return false
	var right: Vector3 = Vector3(cos(plane.yaw), 0.0, -sin(plane.yaw))
	var right_blocked: bool = _ray_blocked(space, origin, origin + (nose + right * 0.7).normalized() * reach)
	var left_blocked: bool = _ray_blocked(space, origin, origin + (nose - right * 0.7).normalized() * reach)
	if right_blocked != left_blocked:
		_avoid_side = -1.0 if right_blocked else 1.0
	else:
		var to_center: Vector3 = plane.arena_center - origin
		_avoid_side = 1.0 if to_center.dot(right) >= 0.0 else -1.0
	return true


func _ray_blocked(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, PlaneActor.COLLISION_LAYER_WORLD)
	return not space.intersect_ray(query).is_empty()


# ---------------------------------------------------------------------------
# Reactions
# ---------------------------------------------------------------------------

func _on_plane_damaged(_victim: PlaneActor, _amount: float, attacker: PlaneActor) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return
	_threat = attacker
	_threat_age = 0.0
	if _evade_timer > 0.0:
		return
	# Only break when the attacker is behind us; if it is in front we would
	# rather keep our guns on it. Better pilots react more often.
	var attacker_behind: bool = plane.forward().dot(attacker.global_position - plane.global_position) < 0.0
	if attacker_behind and _rng.randf() < lerpf(0.25, 0.7, skill) * (1.5 - plane.condition()):
		_evade_timer = _rng.randf_range(1.4, 2.6)
		_evade_side = 1.0 if _rng.randf() > 0.5 else -1.0


## A new plane: if it is parked, work out when to start up and which line to
## roll along. The further back in the queue, the longer the wait.
func _on_plane_respawned(_plane: PlaneActor) -> void:
	_stick = Vector2.ZERO
	_starter_wait = 0.0
	if not plane.is_on_ground():
		state = State.PATROL
		plane.input.throttle = 1.0
		return
	state = State.TAKEOFF
	plane.input.throttle = 0.0
	_start_delay = _rng.randf_range(0.4, 1.3)
	_takeoff_lane = 0.0
	var field: Airfield = plane.airfield_at(plane.global_position)
	if field != null:
		var place: Vector2 = field.runway_coordinates(plane.global_position)
		_takeoff_lane = place.x
		_start_delay += maxf(Airfield.PARKING_SPOTS[0].y - place.y, 0.0) * START_DELAY_PER_METRE


func _on_plane_died(_victim: PlaneActor, _killer: PlaneActor) -> void:
	_set_target(null)
	_threat = null
	_evade_timer = 0.0
	_break_timer = 0.0
	state = State.PATROL
