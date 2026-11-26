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
##   RECOVER  about to hit the sea/a cliff or above the ceiling -> pull away. Always wins.
##   EVADE    someone is shooting us from behind -> break turn, roll, smoke.
##   ENGAGE   chase the chosen target, lead it, fire when the guns bear.
##   PATROL   nobody in range -> loop around the middle of the arena.
##
## Anti-clumping has three layers: target scoring penalises enemies that
## team-mates already claimed (SquadBlackboard), every bot approaches from its
## own offset "lane", and a separation force pushes nearby planes apart.

enum State { PATROL, ENGAGE, EVADE, RECOVER }

const THINK_INTERVAL: float = 0.2
const DETECT_RANGE: float = 1500.0
const SEPARATION_RADIUS: float = 75.0
const SEPARATION_WEIGHT: float = 1.4
## Closer than this to the target the bot breaks off instead of ramming it.
const BREAK_OFF_RANGE: float = 55.0
const BREAK_OFF_TIME: float = 1.3
const MIN_SAFE_ALTITUDE: float = 70.0
## Seconds of look-ahead used for the "am I about to hit something" checks.
const TERRAIN_LOOKAHEAD: float = 2.6
const STEER_GAIN: float = 9.0
const LANE_OFFSET: float = 70.0
## Bots drift back into this height band so the fight stays between the
## cliff tops and the ceiling instead of creeping ever higher.
const PREFERRED_ALTITUDE_MIN: float = 140.0
const PREFERRED_ALTITUDE_MAX: float = 480.0
## A shot is taken when the gun line passes within this many metres of the
## aim point, even if the angular fire cone says no (close-range snapshots).
const SNAPSHOT_MISS_DISTANCE: float = 7.0

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
var _aim_error: Vector3 = Vector3.ZERO
var _aim_error_timer: float = 0.0
## Personal approach lane: x = sideways, y = vertical, both -1..1.
var _lane: Vector2 = Vector2.ZERO
var _patrol_phase: float = 0.0
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
	plane.damaged.connect(_on_plane_damaged)
	plane.died.connect(_on_plane_died)


func _exit_tree() -> void:
	_set_target(null)
	if plane != null and is_instance_valid(plane):
		if plane.damaged.is_connected(_on_plane_damaged):
			plane.damaged.disconnect(_on_plane_damaged)
		if plane.died.is_connected(_on_plane_died):
			plane.died.disconnect(_on_plane_died)


func _physics_process(delta: float) -> void:
	if plane == null or not is_instance_valid(plane) or not multiplayer.is_server():
		return
	if not plane.alive:
		_set_target(null)
		return
	_threat_age += delta
	_evade_timer = maxf(_evade_timer - delta, 0.0)
	_break_timer = maxf(_break_timer - delta, 0.0)
	_aim_error_timer -= delta
	_think_timer -= delta
	if _think_timer <= 0.0:
		# Rookies also think a little slower.
		_think_timer = THINK_INTERVAL * lerpf(1.6, 1.0, skill)
		_think()
	_fly()


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
	_consider_gadget()


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
	score += (1.0 - enemy.hp_ratio()) * 220.0
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


func _is_valid_target(other: PlaneActor) -> bool:
	return other != null and is_instance_valid(other) and other.alive \
			and plane.is_hostile_to(other) and not other.is_concealed()


func _set_target(new_target: PlaneActor) -> void:
	if new_target == target:
		return
	if target != null:
		blackboard.release(target)
	target = new_target
	if target != null:
		blackboard.claim(target)
	if plane != null and is_instance_valid(plane):
		plane.current_target = target


func _consider_gadget() -> void:
	if not plane.is_gadget_ready():
		return
	match plane.stats.gadget_type:
		ComponentCard.GadgetType.NITRO_BOOST:
			# Close a long gap to a target that is roughly ahead.
			if target != null and plane.global_position.distance_to(target.global_position) > 550.0 \
					and Ballistics.angle_off_nose(plane.global_position, plane.forward(), target.global_position) < 0.5:
				plane.input.press_gadget()
		ComponentCard.GadgetType.REPAIR_PULSE:
			if plane.hp_ratio() < 0.55:
				plane.input.press_gadget()
		ComponentCard.GadgetType.SMOKE_SCREEN:
			if _threat_age < 1.0 and plane.hp_ratio() < 0.6:
				plane.input.press_gadget()


# ---------------------------------------------------------------------------
# Fly: turn the decision into stick input
# ---------------------------------------------------------------------------

func _fly() -> void:
	var input: PlaneInput = plane.input
	input.firing = false
	match state:
		State.RECOVER:
			_fly_recover(input)
		State.EVADE:
			_fly_evade(input)
		State.ENGAGE:
			_fly_engage(input)
		State.PATROL:
			_fly_patrol(input)


func _fly_recover(input: PlaneInput) -> void:
	var steer: Vector2 = Vector2(0.0, 1.0)
	if plane.global_position.y > plane.arena_ceiling - 40.0 and not _obstacle_ahead:
		steer.y = -0.5  # Too high rather than too low.
	if _obstacle_ahead:
		steer.x = _avoid_side
	input.steer = steer


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

	# Too close: peel away for a moment so we do not fly through the target.
	if distance < BREAK_OFF_RANGE and _break_timer <= 0.0:
		_break_timer = BREAK_OFF_TIME
		_break_side = 1.0 if _rng.randf() > 0.5 else -1.0
	if _break_timer > 0.0:
		input.steer = Vector2(_break_side, _vertical_escape()) * _max_stick()
		return

	var lead: Vector3 = Ballistics.lead_point(my_position, plane.velocity,
			target.global_position, target.velocity, plane.stats.bullet_speed)
	var aim_point: Vector3 = lead + _current_aim_error(distance)

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

	# Fire only when the nose is actually on the lead point and in gun range.
	# Rookies spray a wider cone; everyone takes point-blank snapshots.
	var angle_off: float = Ballistics.angle_off_nose(my_position, plane.forward(), aim_point)
	var fire_cone: float = maxf(deg_to_rad(lerpf(5.5, 2.5, skill)), atan(SNAPSHOT_MISS_DISTANCE / maxf(distance, 1.0)))
	input.firing = distance < plane.stats.gun_range * 0.95 and angle_off < fire_cone


func _fly_patrol(input: PlaneInput) -> void:
	# Lazy orbit around the arena centre at a personal height.
	_patrol_phase += 0.004
	var radius: float = plane.arena_radius * 0.35
	var point: Vector3 = plane.arena_center + Vector3(cos(_patrol_phase) * radius, 0.0, sin(_patrol_phase) * radius)
	point.y = 260.0 + _lane.y * 90.0
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
			clampf(-yaw_error * STEER_GAIN, -1.0, 1.0),
			clampf(pitch_error * STEER_GAIN, -1.0, 1.0))


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


## Slowly wandering aim offset: rookies drift metres off, aces barely at all.
func _current_aim_error(distance: float) -> Vector3:
	if _aim_error_timer <= 0.0:
		_aim_error_timer = _rng.randf_range(0.4, 0.9)
		var spread: float = lerpf(0.02, 0.003, skill)
		_aim_error = Vector3(_rng.randfn(0.0, spread), _rng.randfn(0.0, spread), _rng.randfn(0.0, spread))
	return _aim_error * distance


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


## Ray ahead along the flight path against the world layer. Also probes left
## and right to decide which way to turn away.
func _check_obstacle_ahead() -> bool:
	var space: PhysicsDirectSpaceState3D = plane.get_world_3d().direct_space_state
	var origin: Vector3 = plane.global_position
	var nose: Vector3 = plane.forward()
	var reach: float = maxf(plane.speed, 40.0) * TERRAIN_LOOKAHEAD
	if not _ray_blocked(space, origin, origin + nose * reach):
		return false
	var right: Vector3 = Vector3(cos(plane.yaw), 0.0, -sin(plane.yaw))
	var right_blocked: bool = _ray_blocked(space, origin, origin + (nose + right * 0.7).normalized() * reach)
	var left_blocked: bool = _ray_blocked(space, origin, origin + (nose - right * 0.7).normalized() * reach)
	if right_blocked != left_blocked:
		_avoid_side = -1.0 if right_blocked else 1.0
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
	if attacker_behind and _rng.randf() < lerpf(0.25, 0.7, skill) * (1.5 - plane.hp_ratio()):
		_evade_timer = _rng.randf_range(1.4, 2.6)
		_evade_side = 1.0 if _rng.randf() > 0.5 else -1.0


func _on_plane_died(_victim: PlaneActor, _killer: PlaneActor) -> void:
	_set_target(null)
	_threat = null
	_evade_timer = 0.0
	_break_timer = 0.0
	state = State.PATROL
