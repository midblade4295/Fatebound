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
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

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


func _ready() -> void:
	add_to_group(&"planes")
	collision_layer = COLLISION_LAYER_PLANES
	collision_mask = COLLISION_LAYER_WORLD
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
	return _evade_cooldown <= 0.0 and _evade_time <= 0.0 and alive


# ---------------------------------------------------------------------------
# Damage, death, respawn
# ---------------------------------------------------------------------------

## Server-side. Friendly fire is rejected here as a second line of defence
## (BulletSystem already lets bullets pass through team-mates).
func apply_damage(amount: float, attacker: PlaneActor, burn_dps: float = 0.0, burn_duration: float = 0.0) -> void:
	if not alive or amount <= 0.0 or _spawn_shield > 0.0:
		return
	if attacker != null and attacker != self and not Teams.are_hostile(team, attacker.team):
		return
	var final_amount: float = amount
	if _evade_time > 0.0:
		final_amount *= EVADE_DAMAGE_MULTIPLIER
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
	var steer: Vector2 = _apply_bounds_assist(input.steer.limit_length(1.0))

	if input.consume_evade():
		_try_start_evade(steer.x)
	if input.consume_gadget():
		_try_activate_gadget()

	# Stick -> turn rates, eased so the plane has a little weight.
	var response: float = 1.0 - exp(-STICK_RESPONSE * stats.roll_rate * delta)
	_yaw_rate = lerpf(_yaw_rate, -steer.x * stats.turn_rate, response)
	_pitch_rate = lerpf(_pitch_rate, steer.y * stats.pitch_rate, response)
	yaw = wrapf(yaw + _yaw_rate * delta, -PI, PI)
	pitch = clampf(pitch + _pitch_rate * delta, -MAX_PITCH, MAX_PITCH)
	if absf(steer.y) < 0.05:
		pitch = lerpf(pitch, 0.0, 1.0 - exp(-AUTO_LEVEL_RATE * delta))

	# Auto-bank into the turn (cosmetic: guns fire along the nose regardless).
	var bank_target: float = -steer.x * MAX_BANK
	bank = lerpf(bank, bank_target, 1.0 - exp(-BANK_RESPONSE * stats.roll_rate * delta))
	rotation = Vector3(pitch, yaw, bank)

	# Throttle is automatic. Climbing bleeds speed, diving builds it.
	var nitro_multiplier: float = 1.0 + stats.gadget_power if _nitro_time > 0.0 else 1.0
	var target_speed: float = stats.top_speed * nitro_multiplier
	var gravity_pull: float = -sin(pitch) * GRAVITY_ACCEL
	if pitch > 0.0:
		gravity_pull /= maxf(stats.climb_rate, 0.1)
	var engine_response: float = stats.acceleration * (3.0 if _nitro_time > 0.0 else 1.0)
	speed += ((target_speed - speed) * engine_response + gravity_pull) * delta
	speed = clampf(speed, stats.top_speed * MIN_SPEED_RATIO, stats.top_speed * DIVE_SPEED_RATIO * nitro_multiplier)

	velocity = forward() * speed + _evade_velocity()
	var collision: KinematicCollision3D = move_and_collide(velocity * delta)
	if collision != null:
		# Hit the sea, a cliff or the carrier. Credit whoever shot us last.
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
	gadget_used.emit(self, stats.gadget_type)


# ---------------------------------------------------------------------------
# Weapons
# ---------------------------------------------------------------------------

func _tick_weapons(delta: float) -> void:
	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)
	if not input.firing or weapons_locked or bullet_system == null or _evade_time > 0.0:
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
	if _burn_time > 0.0:
		flags |= FLAG_BURNING
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
