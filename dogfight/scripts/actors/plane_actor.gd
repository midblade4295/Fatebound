class_name PlaneActor
extends CharacterBody3D
## One aircraft: arcade flight model, guns, evade roll, tactical gadget, damage.
##
## The plane has no idea who flies it. It reads its PlaneInput child every
## physics tick; PlayerController or SquadAIController write to that node.
##
## Flight is deliberately not a physics simulation. The plane always flies
## where its nose points, the stick sets yaw/pitch *rates*, and banking is
## cosmetic auto-bank. That is what makes it controllable with one thumb.
##
## Networking: the server (multiplayer authority of this node) runs all of
## _physics_process. Everyone else only runs _process for cosmetics and gets
## transform/speed/hp/flags through the StateSync MultiplayerSynchronizer.
## Offline there is no peer, so this instance is always the authority.

signal died(victim: PlaneActor, killer: PlaneActor)
signal damaged(victim: PlaneActor, amount: float, attacker: PlaneActor)
signal respawned(plane: PlaneActor)
signal shot_fired(plane: PlaneActor)
signal evade_started(plane: PlaneActor)
signal gadget_used(plane: PlaneActor, gadget_type: int)
## A part crossed into a new PartState (damaged, critical, destroyed, or repaired).
signal part_state_changed(plane: PlaneActor, part: Part, state: PartState)

## Sections of the airframe that take damage separately from the hull.
## HULL is everything else: cockpit, fuel tanks, the middle of the fuselage.
enum Part { HULL, ENGINE, LEFT_WING, RIGHT_WING, TAIL }
enum PartState { OK, DAMAGED, CRITICAL, DESTROYED }

const PART_NAMES: Array[String] = ["Hull", "Engine", "Left wing", "Right wing", "Tail"]
## Each part's own health pool as a fraction of the plane's max HP. Smaller than
## the hull, so concentrated fire knocks a part out before the hull gives way.
const PART_HEALTH_FRACTION: Array[float] = [1.0, 0.5, 0.5, 0.5, 0.45]
## Hull damage multiplier by where the bullet lands. Centre hits find the
## pilot and the fuel tanks; wing and tail hits mostly chew up the part.
const PART_HULL_DAMAGE: Array[float] = [1.2, 1.0, 0.9, 0.9, 0.9]
## Part damage (0 = pristine, 1 = gone) at which each PartState begins.
const PART_DAMAGED_AT: float = 0.4
const PART_CRITICAL_AT: float = 0.75
## A bullet whose path passes further than this from the centre line hit a wing.
const HIT_WING_OFFSET: float = 1.5
## Along the fuselage, entry points beyond this are the tail / the nose.
const HIT_END_OFFSET: float = 1.3

# --- How damage changes handling (all scale with the part's damage 0..1) -----
## Turn and pitch authority lost per fully damaged wing.
const WING_LIFT_LOSS: float = 0.3
## The plane yaws and hangs a wing toward its more damaged side.
const WING_PULL_YAW: float = deg_to_rad(11.0)
const WING_PULL_BANK: float = deg_to_rad(26.0)
## Extra authority lost when turning *away* from the damaged wing.
const WING_OPPOSITE_TURN_LOSS: float = 0.35
## Shot-up ailerons / elevator make the stick slow to answer.
const WING_RESPONSE_LOSS: float = 0.45
const TAIL_RESPONSE_LOSS: float = 0.3
const WING_DRAG: float = 0.1
const TAIL_PITCH_LOSS: float = 0.65
const TAIL_YAW_LOSS: float = 0.35
## Past half damage the elevator can no longer hold the nose up on its own.
const TAIL_TRIM_RATE: float = deg_to_rad(7.0)
## With the tail gone the nose drops this fast and the stick barely matters.
const TAIL_GONE_DIVE_RATE: float = deg_to_rad(16.0)
const TAIL_GONE_PITCH_AUTHORITY: float = 0.1
const ENGINE_SPEED_LOSS: float = 0.4
const ENGINE_ACCEL_LOSS: float = 0.6
## Dead engine: the plane is a glider. It settles at this fraction of top
## speed and stalls (nose forced down) unless it dives to keep its speed up.
const ENGINE_DEAD_SPEED_RATIO: float = 0.45
const STALL_SPEED_RATIO: float = 0.6
const STALL_RECOVER_SPEED_RATIO: float = 0.74
const STALL_PITCH: float = deg_to_rad(-14.0)
## A destroyed engine burns: fraction of max HP lost per second.
const ENGINE_FIRE_RATE: float = 0.07
## A plane that loses a wing spins for this long, then breaks up.
const SPIN_OUT_TIME: float = 2.6
const SPIN_YAW_RATE: float = deg_to_rad(95.0)
const SPIN_ROLL_RATE: float = deg_to_rad(430.0)

const COLLISION_LAYER_WORLD: int = 1
const COLLISION_LAYER_PLANES: int = 2

const MAX_PITCH: float = deg_to_rad(72.0)
const MAX_BANK: float = deg_to_rad(62.0)
## How quickly yaw/pitch rates follow the stick (1/s), scaled by roll_rate.
const STICK_RESPONSE: float = 5.0
const BANK_RESPONSE: float = 4.0
## Nose drifts back to level when the stick's pitch axis is released.
const AUTO_LEVEL_RATE: float = 0.35
## Speed gained/lost per second when flying straight down/up (m/s^2).
const GRAVITY_ACCEL: float = 18.0
const MIN_SPEED_RATIO: float = 0.55
const DIVE_SPEED_RATIO: float = 1.3

const EVADE_DURATION: float = 0.75
const EVADE_COOLDOWN: float = 4.0
const EVADE_SIDE_SPEED: float = 34.0
const EVADE_DAMAGE_MULTIPLIER: float = 0.35

const SPAWN_SHIELD_TIME: float = 2.5
const CRASH_CREDIT_WINDOW: float = 6.0
const GUN_CONVERGENCE: float = 320.0
const AIM_ASSIST_CONE: float = deg_to_rad(3.5)
const REPAIR_RADIUS: float = 260.0
const BOUNDS_BLEND_DISTANCE: float = 220.0

# status_flags bits (replicated so remote peers can drive cosmetics).
const FLAG_BOOSTING: int = 1
const FLAG_CONCEALED: int = 2
const FLAG_EVADING: int = 4
const FLAG_BURNING: int = 8
const FLAG_SHIELDED: int = 16
const FLAG_OUT_OF_BOUNDS: int = 32
const FLAG_SPINNING: int = 64

# --- Identity (replicated once at spawn) ------------------------------------
@export var team: Teams.Id = Teams.Id.TEAM_BLUE
@export var pilot_name: String = "Pilot"
@export var plane_id: StringName = &""
## Peer that owns this plane's PlaneInput. 1 = server/offline, also used by bots.
@export var owner_peer_id: int = 1
@export var is_human: bool = false

# --- Live state (replicated continuously by StateSync) ----------------------
@export var speed: float = 0.0
@export var hp: float = 1.0
@export var alive: bool = true: set = _set_alive
@export var status_flags: int = 0
## Extra barrel-roll angle shown by the visual during an evade.
@export var visual_roll: float = 0.0
## Damage per part, 0 (pristine) to 1 (destroyed):
## x = engine, y = left wing, z = right wing, w = tail.
@export var part_damage: Vector4 = Vector4.ZERO

# --- Arena limits, set by the match manager ---------------------------------
var arena_center: Vector3 = Vector3.ZERO
var arena_radius: float = 1500.0
var arena_ceiling: float = 750.0

var plane_data: PlaneData
var stats: PlaneStats
var bullet_system: BulletSystem
## While true the trigger does nothing (pre-match countdown, post-match).
var weapons_locked: bool = false
## The enemy this plane's pilot is currently attacking (set by its controller).
## The HUD uses it to flag enemies that are hunting the player.
var current_target: PlaneActor

## Heading angles in radians. yaw: 0 faces -Z, positive turns left.
var yaw: float = 0.0
var pitch: float = 0.0
var bank: float = 0.0

var _yaw_rate: float = 0.0
var _pitch_rate: float = 0.0
var _fire_cooldown: float = 0.0
var _next_muzzle: int = 0
var _evade_time: float = 0.0
var _evade_cooldown: float = 0.0
var _evade_direction: float = 1.0
var _gadget_cooldown: float = 0.0
var _nitro_time: float = 0.0
var _smoke_time: float = 0.0
var _spawn_shield: float = 0.0
var _burn_time: float = 0.0
var _burn_dps: float = 0.0
var _burn_source: PlaneActor
var _last_attacker: PlaneActor
var _last_attacker_age: float = INF
## Whoever destroyed a part: they get the credit however the plane then dies.
var _doomed_by: PlaneActor
var _spin_time: float = 0.0
var _spin_direction: float = 1.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _rng_seeded: bool = false

@onready var input: PlaneInput = $PlaneInput
@onready var visual: PlaneVisual = $VisualRoot
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D
@onready var _muzzles: Array[Marker3D] = [$Muzzles/MuzzleL as Marker3D, $Muzzles/MuzzleR as Marker3D]


## Call right after instancing and *before* add_child(), so the values are part
## of the MultiplayerSpawner's spawn state.
func setup(data: PlaneData, plane_stats: PlaneStats, plane_team: Teams.Id, display_name: String, peer_id: int = 1) -> void:
	plane_data = data
	plane_id = data.id
	stats = plane_stats
	team = plane_team
	pilot_name = display_name
	owner_peer_id = peer_id
	hp = stats.max_hp
	speed = stats.top_speed * 0.85


## Makes this plane's gun spread repeatable. The match manager seeds every
## plane from the match seed so a seeded match replays the same way.
func seed_random(seed_value: int) -> void:
	_rng.seed = seed_value
	_rng_seeded = true


func _ready() -> void:
	add_to_group(&"planes")
	collision_layer = COLLISION_LAYER_PLANES
	collision_mask = COLLISION_LAYER_WORLD
	if not _rng_seeded:
		_rng.randomize()
	# Remote peers arrive here with only the replicated identity: rebuild the rest.
	if plane_data == null:
		plane_data = GameCatalog.find_plane(plane_id)
		if plane_data == null:
			plane_data = GameCatalog.find_plane(GameCatalog.STARTER_PLANE_ID)
	if stats == null:
		stats = plane_data.build_base_stats(1)
		hp = stats.max_hp
		speed = stats.top_speed * 0.85
	visual.build(plane_data, team)
	var offsets: Array[Vector3] = visual.gun_offsets()
	for index: int in range(mini(offsets.size(), _muzzles.size())):
		_muzzles[index].position = offsets[index]
	input.set_multiplayer_authority(owner_peer_id)
	_read_angles_from_transform()


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_tick_timers(delta)
	if not alive:
		return
	_integrate_flight(delta)
	if not alive:
		return  # Crashed or broke up during this tick.
	_tick_weapons(delta)
	_tick_burn(delta)
	_refresh_status_flags()


func _process(_delta: float) -> void:
	# Cosmetics only: runs on every peer from replicated state.
	if not alive:
		return
	visual.set_throttle(speed / maxf(stats.top_speed, 1.0))
	visual.set_roll_angle(visual_roll)
	visual.set_damage_state(hp_ratio(), has_flag(FLAG_BURNING))
	visual.set_part_damage(part_damage)
	visual.set_boosting(has_flag(FLAG_BOOSTING))
	visual.set_smoke_screen(has_flag(FLAG_CONCEALED))


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func forward() -> Vector3:
	return -global_transform.basis.z


func hp_ratio() -> float:
	return clampf(hp / maxf(stats.max_hp, 1.0), 0.0, 1.0)


func has_flag(flag: int) -> bool:
	return status_flags & flag != 0


func is_boosting() -> bool:
	return has_flag(FLAG_BOOSTING)


## Smoke screen active: enemies cannot target this plane or lead it.
func is_concealed() -> bool:
	return has_flag(FLAG_CONCEALED)


func is_evading() -> bool:
	return has_flag(FLAG_EVADING)


func is_out_of_bounds() -> bool:
	return has_flag(FLAG_OUT_OF_BOUNDS)


## A wing is gone and the plane is spinning in; nothing the pilot does matters.
func is_spinning_out() -> bool:
	return has_flag(FLAG_SPINNING)


## 0.0 = pristine .. 1.0 = destroyed. The hull has no part damage of its own.
func part_damage_of(part: Part) -> float:
	match part:
		Part.ENGINE:
			return part_damage.x
		Part.LEFT_WING:
			return part_damage.y
		Part.RIGHT_WING:
			return part_damage.z
		Part.TAIL:
			return part_damage.w
	return 0.0


func part_state(part: Part) -> PartState:
	var damage: float = part_damage_of(part)
	if damage >= 1.0:
		return PartState.DESTROYED
	if damage >= PART_CRITICAL_AT:
		return PartState.CRITICAL
	if damage >= PART_DAMAGED_AT:
		return PartState.DAMAGED
	return PartState.OK


func is_part_destroyed(part: Part) -> bool:
	return part_damage_of(part) >= 1.0


## Which part a bullet struck, from where it entered the (spherical) hit volume
## and the direction it was travelling. Bullets passing well off the centre
## line hit a wing; the rest are sorted nose / middle / tail by entry point.
func locate_hit(world_position: Vector3, world_direction: Vector3) -> Part:
	var world_to_plane: Transform3D = global_transform.affine_inverse()
	var entry: Vector3 = world_to_plane * world_position
	var direction: Vector3 = world_to_plane.basis * world_direction
	if direction.length_squared() < 0.000001:
		return Part.HULL
	direction = direction.normalized()
	# Point on the bullet's path nearest the plane's centre.
	var closest: Vector3 = entry - direction * entry.dot(direction)
	if absf(closest.x) > HIT_WING_OFFSET:
		return Part.RIGHT_WING if closest.x > 0.0 else Part.LEFT_WING
	if entry.z > HIT_END_OFFSET:
		return Part.TAIL
	if entry.z < -HIT_END_OFFSET:
		return Part.ENGINE
	return Part.HULL


func is_hostile_to(other: PlaneActor) -> bool:
	return other != null and other != self and Teams.are_hostile(team, other.team)


func altitude() -> float:
	return global_position.y


func speed_kmh() -> float:
	return speed * 3.6


## 1.0 right after use, 0.0 when ready. For the HUD's radial cooldown.
func evade_cooldown_ratio() -> float:
	return clampf(_evade_cooldown / maxf(EVADE_COOLDOWN / maxf(stats.roll_rate, 0.1), 0.01), 0.0, 1.0)


func gadget_cooldown_ratio() -> float:
	if stats.gadget_type == ComponentCard.GadgetType.NONE or stats.gadget_cooldown <= 0.0:
		return 0.0
	return clampf(_gadget_cooldown / stats.gadget_cooldown, 0.0, 1.0)


func has_gadget() -> bool:
	return stats.gadget_type != ComponentCard.GadgetType.NONE


func is_gadget_ready() -> bool:
	return has_gadget() and _gadget_cooldown <= 0.0 and alive


func is_evade_ready() -> bool:
	return _evade_cooldown <= 0.0 and _evade_time <= 0.0 and alive and _spin_time <= 0.0


# ---------------------------------------------------------------------------
# Damage, death, respawn
# ---------------------------------------------------------------------------

## Server-side. Friendly fire is rejected here as a second line of defence
## (BulletSystem already lets bullets pass through team-mates).
## [param part] is where the hit landed (see locate_hit). The hull always takes
## the damage; any other part also loses some of its own, smaller, health pool.
func apply_damage(amount: float, attacker: PlaneActor, burn_dps: float = 0.0, burn_duration: float = 0.0,
		part: Part = Part.HULL) -> void:
	if not alive or amount <= 0.0 or _spawn_shield > 0.0:
		return
	if attacker != null and attacker != self and not Teams.are_hostile(team, attacker.team):
		return
	var final_amount: float = amount
	if _evade_time > 0.0:
		final_amount *= EVADE_DAMAGE_MULTIPLIER
	if part != Part.HULL:
		_damage_part(part, final_amount, attacker)
	final_amount *= PART_HULL_DAMAGE[part]
	hp = maxf(hp - final_amount, 0.0)
	if attacker != null:
		_last_attacker = attacker
		_last_attacker_age = 0.0
	if burn_dps > 0.0 and burn_duration > 0.0:
		_burn_dps = maxf(_burn_dps, burn_dps)
		_burn_time = maxf(_burn_time, burn_duration)
		_burn_source = attacker
	damaged.emit(self, final_amount, attacker)
	if hp <= 0.0:
		_die(attacker)


func heal(amount: float) -> void:
	if alive and amount > 0.0:
		hp = minf(hp + amount, stats.max_hp)


## Field repairs: patches every part by [param amount] (0..1 of a part's
## health). A part that has been shot clean off cannot be patched.
func repair_parts(amount: float) -> void:
	if not alive or amount <= 0.0:
		return
	for part: Part in [Part.ENGINE, Part.LEFT_WING, Part.RIGHT_WING, Part.TAIL]:
		var damage: float = part_damage_of(part)
		if damage <= 0.0 or damage >= 1.0:
			continue
		var before: PartState = part_state(part)
		_set_part_damage(part, maxf(damage - amount, 0.0))
		var after: PartState = part_state(part)
		if after != before:
			part_state_changed.emit(self, part, after)


## Puts the plane back in the air at [param spawn_transform], fully repaired.
func respawn(spawn_transform: Transform3D) -> void:
	global_transform = spawn_transform.orthonormalized()
	_read_angles_from_transform()
	bank = 0.0
	rotation = Vector3(pitch, yaw, bank)
	_yaw_rate = 0.0
	_pitch_rate = 0.0
	speed = stats.top_speed * 0.85
	velocity = forward() * speed
	hp = stats.max_hp
	_evade_time = 0.0
	_evade_cooldown = 0.0
	_nitro_time = 0.0
	_smoke_time = 0.0
	_burn_time = 0.0
	_burn_dps = 0.0
	_burn_source = null
	_last_attacker = null
	_last_attacker_age = INF
	_doomed_by = null
	_spin_time = 0.0
	part_damage = Vector4.ZERO
	_fire_cooldown = 0.0
	_spawn_shield = SPAWN_SHIELD_TIME
	visual_roll = 0.0
	current_target = null
	input.clear()
	alive = true
	_refresh_status_flags()
	# Without this the interpolator would smear the plane across the map.
	reset_physics_interpolation()
	respawned.emit(self)


## Attacker to credit if this plane dies right now without a direct killer.
func recent_attacker() -> PlaneActor:
	if _doomed_by != null and is_instance_valid(_doomed_by):
		return _doomed_by
	if _last_attacker_age <= CRASH_CREDIT_WINDOW and is_instance_valid(_last_attacker):
		return _last_attacker
	return null


func _die(killer: PlaneActor) -> void:
	if not alive:
		return
	hp = 0.0
	velocity = Vector3.ZERO
	current_target = null
	input.clear()
	alive = false
	status_flags = 0
	died.emit(self, killer)


func _damage_part(part: Part, amount: float, attacker: PlaneActor) -> void:
	var before: PartState = part_state(part)
	if before == PartState.DESTROYED:
		return
	var pool: float = maxf(stats.max_hp * PART_HEALTH_FRACTION[part], 1.0)
	_set_part_damage(part, minf(part_damage_of(part) + amount / pool, 1.0))
	var after: PartState = part_state(part)
	if after == before:
		return
	if after == PartState.DESTROYED:
		if attacker != null:
			_doomed_by = attacker
		if part == Part.LEFT_WING or part == Part.RIGHT_WING:
			_start_spin_out(part)
	part_state_changed.emit(self, part, after)


func _set_part_damage(part: Part, value: float) -> void:
	match part:
		Part.ENGINE:
			part_damage.x = value
		Part.LEFT_WING:
			part_damage.y = value
		Part.RIGHT_WING:
			part_damage.z = value
		Part.TAIL:
			part_damage.w = value


## A wing has come off: the plane rolls and yaws toward the missing wing and
## falls out of the sky. The pilot is a passenger from here on.
func _start_spin_out(lost_wing: Part) -> void:
	_spin_time = SPIN_OUT_TIME
	# Positive yaw and roll are to the left, which is where a lost left wing drags.
	_spin_direction = 1.0 if lost_wing == Part.LEFT_WING else -1.0
	_evade_time = 0.0
	_nitro_time = 0.0
	current_target = null
	input.clear()


func _set_alive(value: bool) -> void:
	var was_alive: bool = alive
	alive = value
	if not is_node_ready():
		return
	visual.visible = alive
	_collision_shape.set_deferred(&"disabled", not alive)
	if was_alive and not alive:
		visual.stop_effects()
		ExplosionFx.spawn(get_parent(), global_position, Teams.color_of(team))


# ---------------------------------------------------------------------------
# Flight model
# ---------------------------------------------------------------------------

func _integrate_flight(delta: float) -> void:
	if _spin_time > 0.0:
		_integrate_spin_out(delta)
		return
	var steer: Vector2 = _apply_bounds_assist(input.steer.limit_length(1.0))

	if input.consume_evade():
		_try_start_evade(steer.x)
	if input.consume_gadget():
		_try_activate_gadget()

	# --- What the damage has done to the controls ---------------------------
	var engine_damage: float = part_damage.x
	var left_damage: float = part_damage.y
	var right_damage: float = part_damage.z
	var tail_damage: float = part_damage.w
	var engine_dead: bool = engine_damage >= 1.0
	var tail_gone: bool = tail_damage >= 1.0
	# Less wing = less lift = wider turns and weaker pull-ups.
	var lift: float = maxf(1.0 - WING_LIFT_LOSS * (left_damage + right_damage), 0.35)
	# Positive when the right wing is worse: the plane then drags to the right.
	var asymmetry: float = right_damage - left_damage
	var yaw_authority: float = lift * (1.0 - TAIL_YAW_LOSS * tail_damage)
	if steer.x * asymmetry < 0.0:
		# Turning away from the damaged wing means lifting it with what is left of it.
		yaw_authority *= 1.0 - WING_OPPOSITE_TURN_LOSS * absf(asymmetry)
	var pitch_authority: float = lift * (1.0 - TAIL_PITCH_LOSS * tail_damage)
	if tail_gone:
		pitch_authority = TAIL_GONE_PITCH_AUTHORITY
	var control_feel: float = (1.0 - WING_RESPONSE_LOSS * maxf(left_damage, right_damage)) * (1.0 - TAIL_RESPONSE_LOSS * tail_damage)

	# Stick -> turn rates, eased so the plane has a little weight.
	var response: float = 1.0 - exp(-STICK_RESPONSE * stats.roll_rate * control_feel * delta)
	var yaw_target: float = -steer.x * stats.turn_rate * yaw_authority - asymmetry * WING_PULL_YAW
	var pitch_target: float = steer.y * stats.pitch_rate * pitch_authority
	if tail_gone:
		pitch_target -= TAIL_GONE_DIVE_RATE
	elif tail_damage > 0.5:
		pitch_target -= TAIL_TRIM_RATE * (tail_damage - 0.5) * 2.0
	_yaw_rate = lerpf(_yaw_rate, yaw_target, response)
	_pitch_rate = lerpf(_pitch_rate, pitch_target, response)
	yaw = wrapf(yaw + _yaw_rate * delta, -PI, PI)
	pitch = clampf(pitch + _pitch_rate * delta, -MAX_PITCH, MAX_PITCH)
	if absf(steer.y) < 0.05 and tail_damage <= 0.5:
		pitch = lerpf(pitch, 0.0, 1.0 - exp(-AUTO_LEVEL_RATE * delta))
	if engine_dead:
		# Gliding: too slow and the nose drops whether the pilot likes it or not.
		var stall: float = 1.0 - smoothstep(STALL_SPEED_RATIO, STALL_RECOVER_SPEED_RATIO, speed / maxf(stats.top_speed, 1.0))
		var highest_pitch: float = lerpf(MAX_PITCH, STALL_PITCH, stall)
		if pitch > highest_pitch:
			pitch = lerpf(pitch, highest_pitch, 1.0 - exp(-4.0 * delta))

	# Auto-bank into the turn (cosmetic: guns fire along the nose regardless),
	# hanging the more damaged wing low.
	var bank_target: float = -steer.x * MAX_BANK - asymmetry * WING_PULL_BANK
	bank = lerpf(bank, bank_target, 1.0 - exp(-BANK_RESPONSE * stats.roll_rate * control_feel * delta))
	rotation = Vector3(pitch, yaw, bank)

	# Throttle is automatic. Climbing bleeds speed, diving builds it.
	var nitro_multiplier: float = 1.0 + stats.gadget_power if _nitro_time > 0.0 else 1.0
	var drag: float = 1.0 - WING_DRAG * (left_damage + right_damage)
	var target_speed: float = stats.top_speed * (1.0 - ENGINE_SPEED_LOSS * engine_damage) * drag * nitro_multiplier
	if engine_dead:
		target_speed = stats.top_speed * ENGINE_DEAD_SPEED_RATIO
	var gravity_pull: float = -sin(pitch) * GRAVITY_ACCEL
	if pitch > 0.0:
		gravity_pull /= maxf(stats.climb_rate, 0.1)
	var engine_response: float = stats.acceleration * (1.0 - ENGINE_ACCEL_LOSS * engine_damage) * (3.0 if _nitro_time > 0.0 else 1.0)
	speed += ((target_speed - speed) * engine_response + gravity_pull) * delta
	speed = clampf(speed, stats.top_speed * MIN_SPEED_RATIO, stats.top_speed * DIVE_SPEED_RATIO * nitro_multiplier)

	velocity = forward() * speed + _evade_velocity()
	var collision: KinematicCollision3D = move_and_collide(velocity * delta)
	if collision != null:
		# Hit the sea, a cliff or the carrier. Credit whoever shot us last.
		_die(recent_attacker())


## Wing gone: an unrecoverable spin that ends in the sea, a cliff, or a
## mid-air break-up when the timer runs out.
func _integrate_spin_out(delta: float) -> void:
	_spin_time -= delta
	# Swallow button presses so they do not fire on respawn.
	input.consume_evade()
	input.consume_gadget()
	_yaw_rate = lerpf(_yaw_rate, _spin_direction * SPIN_YAW_RATE, 1.0 - exp(-3.0 * delta))
	yaw = wrapf(yaw + _yaw_rate * delta, -PI, PI)
	pitch = move_toward(pitch, -MAX_PITCH * 0.85, deg_to_rad(45.0) * delta)
	bank = lerpf(bank, 0.0, 1.0 - exp(-4.0 * delta))
	visual_roll = wrapf(visual_roll + _spin_direction * SPIN_ROLL_RATE * delta, -PI, PI)
	rotation = Vector3(pitch, yaw, bank)
	speed = move_toward(speed, stats.top_speed * 0.8, 15.0 * delta)
	velocity = forward() * speed + Vector3.DOWN * 14.0
	var collision: KinematicCollision3D = move_and_collide(velocity * delta)
	if collision != null or _spin_time <= 0.0:
		_die(recent_attacker())


## Soft arena limits: past the edge the plane is steered back toward the
## centre, past the ceiling the nose is pushed down. Works for bots and humans.
func _apply_bounds_assist(steer: Vector2) -> Vector2:
	var result: Vector2 = steer
	var offset: Vector3 = global_position - arena_center
	offset.y = 0.0
	var distance: float = offset.length()
	if distance > arena_radius:
		var yaw_to_center: float = atan2(offset.x, offset.z)
		var yaw_error: float = wrapf(yaw_to_center - yaw, -PI, PI)
		var strength: float = clampf((distance - arena_radius) / BOUNDS_BLEND_DISTANCE, 0.0, 1.0)
		result.x = lerpf(result.x, clampf(-yaw_error * 2.0, -1.0, 1.0), strength)
	if global_position.y > arena_ceiling:
		var push: float = clampf((global_position.y - arena_ceiling) / 80.0, 0.0, 1.0)
		result.y = minf(result.y, lerpf(result.y, -0.7, push))
	return result


func _try_start_evade(steer_x: float) -> void:
	if not is_evade_ready():
		return
	if absf(steer_x) > 0.15:
		_evade_direction = signf(steer_x)
	else:
		_evade_direction = -_evade_direction  # Alternate sides on a neutral stick.
	_evade_time = EVADE_DURATION
	_evade_cooldown = EVADE_COOLDOWN / maxf(stats.roll_rate, 0.1)
	evade_started.emit(self)


## Sideways slide during the evade roll, eased in and out.
func _evade_velocity() -> Vector3:
	if _evade_time <= 0.0:
		return Vector3.ZERO
	var progress: float = 1.0 - _evade_time / EVADE_DURATION
	var right: Vector3 = Vector3(cos(yaw), 0.0, -sin(yaw))
	return right * _evade_direction * EVADE_SIDE_SPEED * sin(progress * PI)


func _try_activate_gadget() -> void:
	if not is_gadget_ready():
		return
	if stats.gadget_type == ComponentCard.GadgetType.NITRO_BOOST and is_part_destroyed(Part.ENGINE):
		return  # Nothing left to boost.
	_gadget_cooldown = stats.gadget_cooldown
	match stats.gadget_type:
		ComponentCard.GadgetType.NITRO_BOOST:
			_nitro_time = stats.gadget_duration
		ComponentCard.GadgetType.SMOKE_SCREEN:
			_smoke_time = stats.gadget_duration
		ComponentCard.GadgetType.REPAIR_PULSE:
			for node: Node in get_tree().get_nodes_in_group(&"planes"):
				var ally: PlaneActor = node as PlaneActor
				if ally == null or not ally.alive or ally.team != team:
					continue
				if ally.global_position.distance_to(global_position) <= REPAIR_RADIUS:
					ally.heal(ally.stats.max_hp * stats.gadget_power)
					ally.repair_parts(stats.gadget_power * 2.0)
	gadget_used.emit(self, stats.gadget_type)


# ---------------------------------------------------------------------------
# Weapons
# ---------------------------------------------------------------------------

func _tick_weapons(delta: float) -> void:
	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)
	if not input.firing or weapons_locked or bullet_system == null or _evade_time > 0.0 or _spin_time > 0.0:
		return
	if _fire_cooldown > 0.0:
		return
	_fire_cooldown = 1.0 / maxf(stats.fire_rate, 0.1)
	_fire()


func _fire() -> void:
	var muzzle: Marker3D = _muzzles[_next_muzzle]
	visual.flash_muzzle(_next_muzzle)
	_next_muzzle = (_next_muzzle + 1) % _muzzles.size()
	var origin: Vector3 = muzzle.global_position
	var nose: Vector3 = forward()
	# Wing guns converge on the centre line a few hundred metres out.
	var direction: Vector3 = (global_position + nose * GUN_CONVERGENCE - origin).normalized()
	# Aim assist: only ever a small correction, validated here on the server.
	if input.assist_active:
		var to_assist: Vector3 = (input.assist_point - origin).normalized()
		if nose.angle_to(to_assist) <= AIM_ASSIST_CONE:
			direction = to_assist
	var spread: float = tan(deg_to_rad(stats.gun_spread_deg))
	var plane_basis: Basis = global_transform.basis
	direction = (direction + plane_basis.x * _rng.randfn(0.0, spread) + plane_basis.y * _rng.randfn(0.0, spread)).normalized()
	# Bullets inherit the plane's velocity; Ballistics.lead_point assumes this.
	bullet_system.spawn(origin, direction * stats.bullet_speed + velocity, self,
			stats.gun_range / stats.bullet_speed, stats.bullet_damage, stats.burn_dps, stats.burn_duration)
	shot_fired.emit(self)


func _tick_burn(delta: float) -> void:
	# A destroyed engine is on fire until the plane goes in.
	if is_part_destroyed(Part.ENGINE):
		hp = maxf(hp - stats.max_hp * ENGINE_FIRE_RATE * delta, 0.0)
		if hp <= 0.0:
			_die(recent_attacker())
			return
	if _burn_time <= 0.0:
		return
	_burn_time -= delta
	# Applied directly (no `damaged` signal) so a burn does not shake the
	# camera or re-trigger AI reactions sixty times a second.
	hp = maxf(hp - _burn_dps * delta, 0.0)
	if hp <= 0.0:
		_die(_burn_source if is_instance_valid(_burn_source) else null)
	elif _burn_time <= 0.0:
		_burn_dps = 0.0
		_burn_source = null


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _tick_timers(delta: float) -> void:
	_evade_cooldown = maxf(_evade_cooldown - delta, 0.0)
	_gadget_cooldown = maxf(_gadget_cooldown - delta, 0.0)
	_nitro_time = maxf(_nitro_time - delta, 0.0)
	_smoke_time = maxf(_smoke_time - delta, 0.0)
	_spawn_shield = maxf(_spawn_shield - delta, 0.0)
	_last_attacker_age += delta
	if _evade_time > 0.0:
		_evade_time = maxf(_evade_time - delta, 0.0)
		var progress: float = 1.0 - _evade_time / EVADE_DURATION
		# One full barrel roll, smooth-stepped so it snaps in and settles out.
		visual_roll = -_evade_direction * TAU * smoothstep(0.0, 1.0, progress)
		if _evade_time <= 0.0:
			visual_roll = 0.0


func _refresh_status_flags() -> void:
	var flags: int = 0
	if _nitro_time > 0.0:
		flags |= FLAG_BOOSTING
	if _smoke_time > 0.0:
		flags |= FLAG_CONCEALED
	if _evade_time > 0.0:
		flags |= FLAG_EVADING
	if _burn_time > 0.0 or part_damage.x >= 1.0:
		flags |= FLAG_BURNING
	if _spin_time > 0.0:
		flags |= FLAG_SPINNING
	if _spawn_shield > 0.0:
		flags |= FLAG_SHIELDED
	var offset: Vector3 = global_position - arena_center
	offset.y = 0.0
	if offset.length() > arena_radius:
		flags |= FLAG_OUT_OF_BOUNDS
	status_flags = flags


func _read_angles_from_transform() -> void:
	var nose: Vector3 = -global_transform.basis.z
	yaw = atan2(-nose.x, -nose.z)
	pitch = clampf(asin(clampf(nose.y, -1.0, 1.0)), -MAX_PITCH, MAX_PITCH)
