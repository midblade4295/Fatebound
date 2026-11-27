class_name PlaneActor
extends CharacterBody3D
## One aircraft: arcade flight model, guns, evade roll, tactical gadget, and a
## damage model with no health bar.
##
## The plane has no idea who flies it. It reads its PlaneInput child every
## physics tick; PlayerController or SquadAIController write to that node.
##
## Damage is physical. The airframe is fifteen parts (see Part). Each takes
## damage on its own and each does a job: wings lift, ailerons roll, elevators
## pitch, the fin and rudder steer and steady the nose, flaps tighten turns,
## the engine pulls, the fuselage holds the fuel and the control runs. A hurt
## part does its job worse; a destroyed one comes off (taking whatever is
## attached to it) and stops doing it at all. Nothing ever "kills" a plane
## directly. It is destroyed when it hits the sea, the ground, a ship, or
## another aircraft hard enough. Until then the pilot keeps whatever control
## the remaining parts give, all the way down.
##
## Flight is still deliberately simple: the plane flies where its nose points,
## the stick sets yaw/pitch rates and banking is automatic. On top of that sits
## a lift check: too little wing or too little speed and the plane sinks and
## its nose drops, whatever the stick says.
##
## Networking: the server (multiplayer authority of this node) runs all of
## _physics_process. Everyone else only runs _process for cosmetics and gets
## transform/speed/damage/flags through the StateSync MultiplayerSynchronizer.
## Offline there is no peer, so this instance is always the authority.

signal died(victim: PlaneActor, killer: PlaneActor)
## Something struck the plane. [param amount] is in the same units as bullet damage.
signal damaged(victim: PlaneActor, amount: float, attacker: PlaneActor)
signal respawned(plane: PlaneActor)
signal shot_fired(plane: PlaneActor)
signal evade_started(plane: PlaneActor)
signal gadget_used(plane: PlaneActor, gadget_type: int)
## A part crossed into a new PartState (damaged, critical, destroyed, or repaired).
signal part_state_changed(plane: PlaneActor, part: Part, state: PartState)

## Every separately damageable piece of the airframe. The names match the
## pieces of the model (see PlaneVisual.PART_NODES).
enum Part {
	FUSELAGE, ENGINE,
	LEFT_WING, RIGHT_WING, LEFT_WINGTIP, RIGHT_WINGTIP,
	TAIL, FIN, RUDDER,
	LEFT_FLAP, RIGHT_FLAP, LEFT_AILERON, RIGHT_AILERON, LEFT_ELEVATOR, RIGHT_ELEVATOR,
}
enum PartState { OK, DAMAGED, CRITICAL, DESTROYED }

const PART_COUNT: int = 15
const PART_NAMES: Array[String] = [
	"Fuselage", "Engine", "Left wing", "Right wing", "Left wingtip", "Right wingtip",
	"Tail", "Fin", "Rudder", "Left flap", "Right flap", "Left aileron", "Right aileron",
	"Left elevator", "Right elevator",
]
## What each part is bolted to (-1 = nothing). When a part comes off,
## everything attached to it goes with it.
const PART_PARENT: Array[int] = [-1, 0, 0, 0, 2, 3, 0, 6, 7, 2, 3, 4, 5, 6, 6]
## Whether a destroyed part falls off. The fuselage and the engine stay where
## they are: a destroyed engine is dead, a destroyed fuselage has lost its fuel.
const PART_DETACHES: Array[bool] = [false, false, true, true, true, true, true, true, true, true, true, true, true, true, true]
## How much punishment each part takes before it is destroyed, as a fraction of
## the plane's toughness (PlaneStats.max_hp). Control surfaces are light.
const PART_STRENGTH: Array[float] = [0.6, 0.35, 0.4, 0.4, 0.3, 0.3, 0.35, 0.25, 0.2, 0.18, 0.18, 0.18, 0.18, 0.18, 0.18]
## Share of a bullet's energy that carries on after passing through each part.
## Fabric surfaces barely slow it, the fuselage soaks up more, and nothing
## comes out the far side of the engine block.
const PART_PASS_THROUGH: Array[float] = [0.3, 0.0, 0.6, 0.6, 0.65, 0.65, 0.45, 0.7, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8]
## Below this share of its energy a bullet is spent.
const SPENT_BULLET_ENERGY: float = 0.1
## Part damage (0 = pristine, 1 = gone) at which each PartState begins.
const PART_DAMAGED_AT: float = 0.4
const PART_CRITICAL_AT: float = 0.75
## Which wing panel each gun is mounted in (same order as the Muzzles nodes).
const GUN_PARTS: Array[Part] = [Part.LEFT_WING, Part.RIGHT_WING]

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
const MIN_SPEED_RATIO: float = 0.35
const DIVE_SPEED_RATIO: float = 1.3

# --- Lift ---------------------------------------------------------------------
## Each side's lift comes 60% from the inner wing panel and 40% from the tip.
const INNER_WING_LIFT: float = 0.6
const WINGTIP_LIFT: float = 0.4
## A panel shot full of holes (but still attached) keeps this much of its lift.
const HOLED_WING_LIFT: float = 0.5
## Below this fraction of top speed the wings stop carrying the plane.
const STALL_SPEED_RATIO: float = 0.6
## Dropped flaps add this much lift, which is what makes them useful when slow.
const FLAP_LIFT_BONUS: float = 0.12
## With no lift at all the plane falls this fast (m/s) and its nose drops this
## quickly; with part of its lift, proportionally less.
const SINK_SPEED: float = 42.0
const NOSE_DROP_RATE: float = deg_to_rad(30.0)

# --- What the parts do for the controls ----------------------------------------
## Uneven lift drags the plane toward its weaker side: yaw rate and bank angle
## with one whole wing missing.
const WING_PULL_YAW: float = deg_to_rad(22.0)
const WING_PULL_BANK: float = deg_to_rad(52.0)
## Extra authority lost when turning *away* from the weaker side.
const WING_OPPOSITE_TURN_LOSS: float = 0.35
## Turning is mostly banking: with no ailerons only this much turn is left.
const TURN_WITHOUT_AILERONS: float = 0.4
## The rudder supplies this share of what remains.
const RUDDER_TURN_SHARE: float = 0.35
## With no elevators only this much pitch authority is left.
const PITCH_WITHOUT_ELEVATORS: float = 0.08
## Fishtailing: the nose hunts from side to side when the rudder is hurt, and
## far worse when the whole fin is gone.
const FISHTAIL_RATE: float = deg_to_rad(8.0)
const FISHTAIL_HZ: float = 0.9
const FIN_GONE_FISHTAIL: float = 2.2
## A weakened tail lets the nose drop; with the tail gone it drops fast.
const TAIL_TRIM_RATE: float = deg_to_rad(7.0)
const TAIL_GONE_DIVE_RATE: float = deg_to_rad(18.0)
## Damage to the fuselage and tail structure makes the stick slow to answer.
const FUSELAGE_FEEL_LOSS: float = 0.35
const TAIL_FEEL_LOSS: float = 0.3
## Combat flaps drop automatically when the stick is pulled past this much.
const FLAP_DEPLOY_STICK: float = 0.6
const FLAP_SPEED: float = 2.2
const FLAP_TURN_BONUS: float = 0.18
const FLAP_DRAG: float = 0.12
const FLAP_PULL_YAW: float = deg_to_rad(6.0)
const FLAP_PULL_BANK: float = deg_to_rad(14.0)
## Ragged or missing wing panels are draggy.
const WING_DRAG: float = 0.12

# --- Engine and fuel -------------------------------------------------------------
const ENGINE_SPEED_LOSS: float = 0.4
const ENGINE_ACCEL_LOSS: float = 0.6
## Engine stopped: the windmilling propeller drags the plane down to this
## fraction of top speed unless it dives.
const DEAD_ENGINE_SPEED_RATIO: float = 0.3
const DEAD_ENGINE_RESPONSE: float = 0.5
## A holed fuselage leaks fuel: fraction of the tank lost per second at full
## damage (it leaks with the square of the damage, so light damage weeps).
const FUEL_LEAK_RATE: float = 0.05
## A destroyed fuselage empties the tank in a few seconds.
const FUEL_DUMP_RATE: float = 0.25

const EVADE_DURATION: float = 0.75
const EVADE_COOLDOWN: float = 4.0
const EVADE_SIDE_SPEED: float = 34.0
const EVADE_DAMAGE_MULTIPLIER: float = 0.35
## An evade roll needs working ailerons.
const EVADE_MIN_AILERONS: float = 0.3

const SPAWN_SHIELD_TIME: float = 2.5
## A crash is credited to the last enemy who hit this plane within this long.
## It is generous because a crippled plane can take a while to come down.
const CRASH_CREDIT_WINDOW: float = 45.0
const GUN_CONVERGENCE: float = 320.0
const AIM_ASSIST_CONE: float = deg_to_rad(3.5)
const REPAIR_RADIUS: float = 260.0
const BOUNDS_BLEND_DISTANCE: float = 220.0
## How quickly a shove from a mid-air collision fades (1/s).
const KNOCK_DAMPING: float = 2.5

# status_flags bits (replicated so remote peers can drive cosmetics).
const FLAG_BOOSTING: int = 1
const FLAG_CONCEALED: int = 2
const FLAG_EVADING: int = 4
const FLAG_BURNING: int = 8
const FLAG_SHIELDED: int = 16
const FLAG_OUT_OF_BOUNDS: int = 32
const FLAG_GOING_DOWN: int = 64

# --- Identity (replicated once at spawn) ------------------------------------
@export var team: Teams.Id = Teams.Id.TEAM_BLUE
@export var pilot_name: String = "Pilot"
@export var plane_id: StringName = &""
## Peer that owns this plane's PlaneInput. 1 = server/offline, also used by bots.
@export var owner_peer_id: int = 1
@export var is_human: bool = false

# --- Live state (replicated continuously by StateSync) ----------------------
@export var speed: float = 0.0
@export var alive: bool = true: set = _set_alive
@export var status_flags: int = 0
## Extra barrel-roll angle shown by the visual during an evade.
@export var visual_roll: float = 0.0
## Damage per part, 0 (pristine) to 1 (destroyed), indexed by Part.
@export var part_damage: PackedFloat32Array = PackedFloat32Array([
	0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
])
## Fuel left, 1 (full) to 0 (dry). Only a leaking fuselage uses it up.
@export var fuel: float = 1.0
## What the control surfaces are doing, for the model to animate on every
## peer: x = aileron/rudder (-1 left .. +1 right), y = elevator (-1 down ..
## +1 up), z = how far the flaps are dropped (0..1).
@export var control_state: Vector3 = Vector3.ZERO

# --- Arena limits, set by the match manager ---------------------------------
var arena_center: Vector3 = Vector3.ZERO
var arena_radius: float = 1500.0
var arena_ceiling: float = 750.0

var plane_data: PlaneData
var stats: PlaneStats
## What bullets and other planes collide with. Built from the model in _ready().
var hitboxes: PlaneHitboxes
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
var _burn_part: Part = Part.FUSELAGE
var _burn_source: PlaneActor
var _last_attacker: PlaneActor
var _last_attacker_age: float = INF
## Whoever destroyed a part: they get the credit however the plane then dies.
var _doomed_by: PlaneActor
var _flap_deploy: float = 0.0
var _fishtail_phase: float = 0.0
var _lift_ratio: float = 1.0
var _knock_velocity: Vector3 = Vector3.ZERO
## One bit per Part that is no longer on the plane (itself or its parent gone).
var _gone_mask: int = 0
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
		speed = stats.top_speed * 0.85
	visual.build(plane_data, team)
	hitboxes = PlaneHitboxes.from_visual(visual)
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
		return  # Flew into something during this tick.
	_tick_weapons(delta)
	_tick_burn(delta)
	_refresh_status_flags()


func _process(_delta: float) -> void:
	# Cosmetics only: runs on every peer from replicated state.
	if not alive:
		return
	visual.set_throttle(speed / maxf(stats.top_speed, 1.0) if engine_power() > 0.0 else 0.0)
	visual.set_roll_angle(visual_roll)
	visual.set_part_damage(part_damage, velocity, has_flag(FLAG_BURNING))
	visual.set_controls(control_state)
	visual.set_boosting(has_flag(FLAG_BOOSTING))
	visual.set_smoke_screen(has_flag(FLAG_CONCEALED))


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func forward() -> Vector3:
	return -global_transform.basis.z


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


## True when the plane can no longer hold itself in the air: not enough lift,
## no engine, or no tail. It is still flying and still dangerous, but it is on
## its way down. Bots stop wasting ammunition on it.
func is_going_down() -> bool:
	return has_flag(FLAG_GOING_DOWN)


## 0.0 = pristine .. 1.0 = destroyed.
func part_damage_of(part: Part) -> float:
	return part_damage[part]


## True when the part is no longer on the plane: shot off itself, or attached
## to something that was.
func is_part_gone(part: Part) -> bool:
	return _gone_mask & (1 << part) != 0


## Bit mask of parts that are no longer on the plane (bit index = Part).
func gone_mask() -> int:
	return _gone_mask


## How well a part still does its job: 1 pristine, 0 destroyed or gone.
func part_health(part: Part) -> float:
	if is_part_gone(part):
		return 0.0
	return clampf(1.0 - part_damage[part], 0.0, 1.0)


func part_state(part: Part) -> PartState:
	if is_part_gone(part):
		return PartState.DESTROYED
	var damage: float = part_damage[part]
	if damage >= 1.0:
		return PartState.DESTROYED
	if damage >= PART_CRITICAL_AT:
		return PartState.CRITICAL
	if damage >= PART_DAMAGED_AT:
		return PartState.DAMAGED
	return PartState.OK


func is_part_destroyed(part: Part) -> bool:
	return part_state(part) == PartState.DESTROYED


## Engine output 0..1: what is left of the engine, as long as there is fuel.
func engine_power() -> float:
	if fuel <= 0.0 or part_damage[Part.ENGINE] >= 1.0:
		return 0.0
	return 1.0 - part_damage[Part.ENGINE]


## Fraction of the lift needed to stay level that the plane has right now.
## Below 1.0 it is sinking.
func lift_ratio() -> float:
	return _lift_ratio


## Rough overall state for the AI, 1 = factory fresh, 0 = wreck: the weakest of
## lift, engine and pitch control.
func condition() -> float:
	var elevators: float = 0.5 * (part_health(Part.LEFT_ELEVATOR) + part_health(Part.RIGHT_ELEVATOR))
	return minf(_wing_lift(), minf(engine_power(), elevators))


## How far the combat flaps are dropped right now, 0..1.
func flap_deploy() -> float:
	return _flap_deploy


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
	return _evade_cooldown <= 0.0 and _evade_time <= 0.0 and alive and _aileron_health() >= EVADE_MIN_AILERONS


## True when at least one gun is still attached to the plane.
func has_guns() -> bool:
	for gun_part: Part in GUN_PARTS:
		if not is_part_gone(gun_part):
			return true
	return false


# ---------------------------------------------------------------------------
# Taking damage
# ---------------------------------------------------------------------------

## Traces a straight path through this plane's hit boxes (see PlaneHitboxes).
## [param world_origin] is a point on the path and [param world_direction] its
## normalised direction; pass the bullet's motion *relative to this plane* so a
## moving target is handled correctly. The outputs list every part the path
## enters within [param max_distance], nearest first. Parts that have been
## shot off are not there to hit. An evade roll rolls the boxes with the plane.
func trace_parts(world_origin: Vector3, world_direction: Vector3, max_distance: float,
		out_parts: PackedInt32Array, out_distances: PackedFloat32Array) -> void:
	var world_to_plane: Basis = hit_basis().transposed()
	hitboxes.trace(world_to_plane * (world_origin - global_position), world_to_plane * world_direction,
			max_distance, _gone_mask, out_parts, out_distances)


## Orientation of the hit boxes in the world: the body's basis (which has no
## scale) with the evade roll on top.
func hit_basis() -> Basis:
	return global_transform.basis * Basis(Vector3.BACK, visual_roll)


## Applies one bullet that travelled through [param parts_in_path] in that
## order. The first part takes the full [param damage]; each part after it
## takes what is left of the bullet's energy once it has punched through
## everything before. An incendiary round sets fire to the first part it hits.
func take_bullet(parts_in_path: PackedInt32Array, damage: float, attacker: PlaneActor,
		burn_dps: float = 0.0, burn_duration: float = 0.0) -> void:
	var energy: float = 1.0
	for index: int in range(parts_in_path.size()):
		if not alive:
			return
		var part: Part = parts_in_path[index] as Part
		if index == 0:
			apply_damage(damage, attacker, part, burn_dps, burn_duration)
		else:
			apply_damage(damage * energy, attacker, part)
		energy *= PART_PASS_THROUGH[part]
		if energy < SPENT_BULLET_ENERGY:
			return


## Server-side. Damages one part. There is no hull health: the only thing that
## changes is how well that part can still do its job. [param attacker] may be
## null (a collision, a fire). Friendly fire from a team-mate's guns is
## rejected here as a second line of defence.
func apply_damage(amount: float, attacker: PlaneActor, part: Part, burn_dps: float = 0.0, burn_duration: float = 0.0) -> void:
	if not alive or amount <= 0.0 or _spawn_shield > 0.0:
		return
	if attacker != null and attacker != self and not Teams.are_hostile(team, attacker.team):
		return
	if is_part_gone(part):
		return
	var final_amount: float = amount
	if _evade_time > 0.0:
		final_amount *= EVADE_DAMAGE_MULTIPLIER
	if attacker != null:
		_last_attacker = attacker
		_last_attacker_age = 0.0
	if burn_dps > 0.0 and burn_duration > 0.0:
		_burn_dps = maxf(_burn_dps, burn_dps)
		_burn_time = maxf(_burn_time, burn_duration)
		_burn_part = part
		_burn_source = attacker
	_damage_part(part, final_amount, attacker)
	damaged.emit(self, final_amount, attacker)


## Field repairs: patches every part by [param amount] (0..1 of a part's
## strength). A part that has been shot off cannot be patched, and neither can
## a dead engine or an emptied tank.
func repair_parts(amount: float) -> void:
	if not alive or amount <= 0.0:
		return
	for index: int in range(PART_COUNT):
		var part: Part = index as Part
		var damage: float = part_damage[part]
		if damage <= 0.0 or damage >= 1.0 or is_part_gone(part):
			continue
		var before: PartState = part_state(part)
		part_damage[part] = maxf(damage - amount, 0.0)
		var after: PartState = part_state(part)
		if after != before:
			part_state_changed.emit(self, part, after)


## A shove from a mid-air collision: the plane is pushed along [param push]
## (m/s, fading quickly) and its nose is kicked round by [param yaw_kick] rad/s.
func knock(push: Vector3, yaw_kick: float) -> void:
	_knock_velocity += push
	_yaw_rate += yaw_kick


## Destroys the plane outright. Only for things that really would: flying
## into the ground, or a mid-air collision too violent to survive.
func destroy(killer: PlaneActor) -> void:
	_die(killer if killer != null else recent_attacker())


## Puts the plane back in the air at [param spawn_transform], factory fresh.
func respawn(spawn_transform: Transform3D) -> void:
	global_transform = spawn_transform.orthonormalized()
	_read_angles_from_transform()
	bank = 0.0
	rotation = Vector3(pitch, yaw, bank)
	_yaw_rate = 0.0
	_pitch_rate = 0.0
	speed = stats.top_speed * 0.85
	velocity = forward() * speed
	part_damage.fill(0.0)
	_gone_mask = 0
	fuel = 1.0
	control_state = Vector3.ZERO
	_flap_deploy = 0.0
	_lift_ratio = 1.0
	_knock_velocity = Vector3.ZERO
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
	_fire_cooldown = 0.0
	_spawn_shield = SPAWN_SHIELD_TIME
	visual_roll = 0.0
	current_target = null
	input.clear()
	visual.restore()
	alive = true
	_refresh_status_flags()
	# Without this the interpolator would smear the plane across the map.
	reset_physics_interpolation()
	respawned.emit(self)


## Moves the plane somewhere else as it is, damage and all, with no spawn
## protection. For tests, cutscenes and editor tools.
func teleport(new_transform: Transform3D) -> void:
	global_transform = new_transform.orthonormalized()
	_read_angles_from_transform()
	bank = 0.0
	rotation = Vector3(pitch, yaw, bank)
	_yaw_rate = 0.0
	_pitch_rate = 0.0
	_knock_velocity = Vector3.ZERO
	velocity = forward() * speed
	reset_physics_interpolation()


## The enemy to credit if this plane is destroyed right now: whoever shot a
## part off it, otherwise the last enemy to hit it recently.
func recent_attacker() -> PlaneActor:
	if _doomed_by != null and is_instance_valid(_doomed_by):
		return _doomed_by
	if _last_attacker_age <= CRASH_CREDIT_WINDOW and is_instance_valid(_last_attacker):
		return _last_attacker
	return null


func _die(killer: PlaneActor) -> void:
	if not alive:
		return
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
	var strength: float = maxf(stats.max_hp * PART_STRENGTH[part], 1.0)
	part_damage[part] = minf(part_damage[part] + amount / strength, 1.0)
	var after: PartState = part_state(part)
	if after == before:
		return
	if after == PartState.DESTROYED:
		if attacker != null and attacker != self and Teams.are_hostile(team, attacker.team):
			_doomed_by = attacker
		_refresh_gone_mask()
	part_state_changed.emit(self, part, after)


## Recomputes which parts are no longer on the plane.
func _refresh_gone_mask() -> void:
	var mask: int = 0
	# Parents always have a lower index than their children, so one pass is enough.
	for index: int in range(PART_COUNT):
		var gone: bool = part_damage[index] >= 1.0 and PART_DETACHES[index]
		var parent: int = PART_PARENT[index]
		if parent >= 0 and mask & (1 << parent) != 0:
			gone = true
		if gone:
			mask |= 1 << index
	_gone_mask = mask


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

## Lift from the wings alone, 0..1: each side is its inner panel plus its tip.
func _wing_lift() -> float:
	return 0.5 * (_side_lift(Part.LEFT_WING, Part.LEFT_WINGTIP) + _side_lift(Part.RIGHT_WING, Part.RIGHT_WINGTIP))


func _side_lift(inner: Part, tip: Part) -> float:
	return INNER_WING_LIFT * _panel_lift(inner) + WINGTIP_LIFT * _panel_lift(tip)


## A panel that is gone lifts nothing; one that is merely full of holes still
## lifts, just less.
func _panel_lift(panel: Part) -> float:
	if is_part_gone(panel):
		return 0.0
	return lerpf(1.0, HOLED_WING_LIFT, part_damage[panel])


func _aileron_health() -> float:
	return 0.5 * (part_health(Part.LEFT_AILERON) + part_health(Part.RIGHT_AILERON))


func _integrate_flight(delta: float) -> void:
	var steer: Vector2 = _apply_bounds_assist(input.steer.limit_length(1.0))

	if input.consume_evade():
		_try_start_evade(steer.x)
	if input.consume_gadget():
		_try_activate_gadget()

	# --- What is left of the aeroplane -------------------------------------
	var left_lift: float = _side_lift(Part.LEFT_WING, Part.LEFT_WINGTIP)
	var right_lift: float = _side_lift(Part.RIGHT_WING, Part.RIGHT_WINGTIP)
	var wing_lift: float = 0.5 * (left_lift + right_lift)
	# Positive when the right side is weaker: the plane then drags to the right.
	var asymmetry: float = left_lift - right_lift
	var ailerons: float = _aileron_health()
	var elevators: float = 0.5 * (part_health(Part.LEFT_ELEVATOR) + part_health(Part.RIGHT_ELEVATOR))
	var rudder: float = part_health(Part.RUDDER)
	var fin_gone: bool = is_part_gone(Part.FIN)
	var tail_gone: bool = is_part_gone(Part.TAIL)
	var tail_damage: float = 1.0 if tail_gone else part_damage[Part.TAIL]
	var left_flap: float = part_health(Part.LEFT_FLAP)
	var right_flap: float = part_health(Part.RIGHT_FLAP)
	var power: float = engine_power()

	# Fuel: a holed fuselage leaks, a destroyed one dumps the lot.
	var fuselage_damage: float = part_damage[Part.FUSELAGE]
	if fuel > 0.0 and fuselage_damage > 0.0:
		var leak: float = FUEL_DUMP_RATE if fuselage_damage >= 1.0 else FUEL_LEAK_RATE * fuselage_damage * fuselage_damage
		fuel = maxf(fuel - leak * delta, 0.0)

	# Combat flaps: pulling hard drops them for a tighter turn at the cost of
	# speed. A shot-up flap gives less, and uneven flaps pull the plane round.
	var flap_demand: float = clampf((steer.length() - FLAP_DEPLOY_STICK) / (1.0 - FLAP_DEPLOY_STICK), 0.0, 1.0)
	_flap_deploy = move_toward(_flap_deploy, flap_demand, FLAP_SPEED * delta)
	var flap_effect: float = _flap_deploy * 0.5 * (left_flap + right_flap)
	var flap_asymmetry: float = (left_flap - right_flap) * _flap_deploy

	# --- Control authority --------------------------------------------------
	# Less wing means wider turns and weaker pull-ups.
	var agility: float = (0.4 + 0.6 * wing_lift) * (1.0 + FLAP_TURN_BONUS * flap_effect)
	var yaw_authority: float = agility * lerpf(TURN_WITHOUT_AILERONS, 1.0, ailerons) * lerpf(1.0 - RUDDER_TURN_SHARE, 1.0, rudder)
	if steer.x * asymmetry < 0.0:
		# Turning away from the weak side means lifting it with what is left of it.
		yaw_authority *= 1.0 - WING_OPPOSITE_TURN_LOSS * minf(absf(asymmetry), 1.0)
	var pitch_authority: float = agility * lerpf(PITCH_WITHOUT_ELEVATORS, 1.0, elevators)
	var control_feel: float = (1.0 - FUSELAGE_FEEL_LOSS * fuselage_damage) * (1.0 - TAIL_FEEL_LOSS * tail_damage)

	# --- Lift: is there enough of it to stay up? -----------------------------
	var speed_fraction: float = speed / maxf(stats.top_speed * STALL_SPEED_RATIO, 1.0)
	var speed_lift: float = clampf(speed_fraction * speed_fraction, 0.0, 1.0)
	_lift_ratio = clampf(wing_lift * speed_lift * (1.0 + FLAP_LIFT_BONUS * flap_effect), 0.0, 1.0)
	var lift_deficit: float = 1.0 - _lift_ratio

	# --- Stick -> turn rates, eased so the plane has a little weight ---------
	var response: float = 1.0 - exp(-STICK_RESPONSE * stats.roll_rate * control_feel * delta)
	var yaw_target: float = -steer.x * stats.turn_rate * yaw_authority - asymmetry * WING_PULL_YAW - flap_asymmetry * FLAP_PULL_YAW
	var wander: float = (1.0 - rudder) + (FIN_GONE_FISHTAIL if fin_gone else 0.0)
	if wander > 0.0:
		# Nothing is holding the nose straight, so it swings from side to side.
		_fishtail_phase = wrapf(_fishtail_phase + TAU * FISHTAIL_HZ * delta, 0.0, TAU)
		yaw_target += sin(_fishtail_phase) * FISHTAIL_RATE * wander
	var pitch_target: float = steer.y * stats.pitch_rate * pitch_authority
	# The nose falls through when the wings are not carrying the plane.
	pitch_target -= NOSE_DROP_RATE * lift_deficit
	if tail_gone:
		pitch_target -= TAIL_GONE_DIVE_RATE
	elif tail_damage > 0.5:
		pitch_target -= TAIL_TRIM_RATE * (tail_damage - 0.5) * 2.0
	_yaw_rate = lerpf(_yaw_rate, yaw_target, response)
	_pitch_rate = lerpf(_pitch_rate, pitch_target, response)
	yaw = wrapf(yaw + _yaw_rate * delta, -PI, PI)
	pitch = clampf(pitch + _pitch_rate * delta, -MAX_PITCH, MAX_PITCH)
	if absf(steer.y) < 0.05 and tail_damage <= 0.5 and lift_deficit < 0.05 and elevators > 0.2:
		pitch = lerpf(pitch, 0.0, 1.0 - exp(-AUTO_LEVEL_RATE * delta))

	# Auto-bank into the turn (cosmetic: guns fire along the nose regardless),
	# hanging the weaker side low.
	var bank_target: float = -steer.x * MAX_BANK * lerpf(0.3, 1.0, ailerons) - asymmetry * WING_PULL_BANK - flap_asymmetry * FLAP_PULL_BANK
	bank = lerpf(bank, bank_target, 1.0 - exp(-BANK_RESPONSE * stats.roll_rate * control_feel * delta))
	rotation = Vector3(pitch, yaw, bank)

	# --- Speed: throttle is automatic. Climbing bleeds it, diving builds it. --
	var nitro_multiplier: float = 1.0 + stats.gadget_power if _nitro_time > 0.0 and power > 0.0 else 1.0
	var drag: float = (1.0 - WING_DRAG * (2.0 - left_lift - right_lift)) * (1.0 - FLAP_DRAG * _flap_deploy)
	var target_speed: float = stats.top_speed * (1.0 - ENGINE_SPEED_LOSS * (1.0 - power)) * drag * nitro_multiplier
	var engine_response: float = stats.acceleration * (1.0 - ENGINE_ACCEL_LOSS * (1.0 - power)) * (3.0 if nitro_multiplier > 1.0 else 1.0)
	if power <= 0.0:
		# Dead stick: only a dive keeps the speed up now.
		target_speed = stats.top_speed * DEAD_ENGINE_SPEED_RATIO
		engine_response = DEAD_ENGINE_RESPONSE
	var gravity_pull: float = -sin(pitch) * GRAVITY_ACCEL
	if pitch > 0.0:
		gravity_pull /= maxf(stats.climb_rate, 0.1)
	speed += ((target_speed - speed) * engine_response + gravity_pull) * delta
	speed = clampf(speed, stats.top_speed * MIN_SPEED_RATIO, stats.top_speed * DIVE_SPEED_RATIO * nitro_multiplier)

	control_state = Vector3(steer.x, steer.y, _flap_deploy)
	_knock_velocity = _knock_velocity.lerp(Vector3.ZERO, 1.0 - exp(-KNOCK_DAMPING * delta))
	velocity = forward() * speed + Vector3.DOWN * SINK_SPEED * lift_deficit + _evade_velocity() + _knock_velocity
	var collision: KinematicCollision3D = move_and_collide(velocity * delta)
	if collision != null:
		# Hit the sea, a cliff or the carrier. This is the only way a plane dies
		# on its own; credit whoever put it in this state.
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
	if stats.gadget_type == ComponentCard.GadgetType.NITRO_BOOST and engine_power() <= 0.0:
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
					ally.repair_parts(stats.gadget_power * 2.0)
	gadget_used.emit(self, stats.gadget_type)


# ---------------------------------------------------------------------------
# Weapons
# ---------------------------------------------------------------------------

func _tick_weapons(delta: float) -> void:
	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)
	if not input.firing or weapons_locked or bullet_system == null or _evade_time > 0.0:
		return
	if _fire_cooldown > 0.0 or not has_guns():
		return
	_fire_cooldown = 1.0 / maxf(stats.fire_rate, 0.1)
	_fire()


func _fire() -> void:
	# Alternate between the wing guns, skipping one whose wing has gone. With
	# one gun left the rate of fire halves, because every other shot is missing.
	var muzzle_index: int = _next_muzzle
	_next_muzzle = (_next_muzzle + 1) % _muzzles.size()
	if is_part_gone(GUN_PARTS[muzzle_index]):
		return
	var muzzle: Marker3D = _muzzles[muzzle_index]
	visual.flash_muzzle(muzzle_index)
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
	# They live a little longer than range / speed because drag slows them.
	bullet_system.spawn(origin, direction * stats.bullet_speed + velocity, self,
			stats.gun_range / stats.bullet_speed * 1.15, stats.bullet_damage, stats.bullet_speed,
			stats.burn_dps, stats.burn_duration)
	shot_fired.emit(self)


## An incendiary hit keeps eating the part it set alight.
func _tick_burn(delta: float) -> void:
	if _burn_time <= 0.0:
		return
	_burn_time -= delta
	# Applied directly (no `damaged` signal) so a fire does not shake the
	# camera or re-trigger AI reactions sixty times a second.
	_damage_part(_burn_part, _burn_dps * delta, _burn_source if is_instance_valid(_burn_source) else null)
	if _burn_time <= 0.0 or is_part_gone(_burn_part):
		_burn_time = 0.0
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
	# On fire: an incendiary hit, a destroyed engine, or fuel pouring from a
	# destroyed fuselage.
	if _burn_time > 0.0 or part_damage[Part.ENGINE] >= 1.0 or (part_damage[Part.FUSELAGE] >= 1.0 and fuel > 0.0):
		flags |= FLAG_BURNING
	if _spawn_shield > 0.0:
		flags |= FLAG_SHIELDED
	if engine_power() <= 0.0 or _wing_lift() < 0.75 or is_part_gone(Part.TAIL):
		flags |= FLAG_GOING_DOWN
	var offset: Vector3 = global_position - arena_center
	offset.y = 0.0
	if offset.length() > arena_radius:
		flags |= FLAG_OUT_OF_BOUNDS
	status_flags = flags


func _read_angles_from_transform() -> void:
	var nose: Vector3 = -global_transform.basis.z
	yaw = atan2(-nose.x, -nose.z)
	pitch = clampf(asin(clampf(nose.y, -1.0, 1.0)), -MAX_PITCH, MAX_PITCH)
