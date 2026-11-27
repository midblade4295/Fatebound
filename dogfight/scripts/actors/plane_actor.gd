class_name PlaneActor
extends CharacterBody3D
## One aircraft: arcade flight model, the guns that are fitted, evade roll, and a
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
## Planes start on the ground. The pilot starts the engine, opens the throttle
## and rolls down the runway; the wheels stay on the ground until there is
## enough speed for the wings to carry the plane *and* the stick is eased back.
## Coming home works the other way round: gear down, throttle back, and put it
## on the island. How gently decides what it costs: nothing, strained wings, a
## collapsed undercarriage leg or two, a smashed propeller (see _touch_down).
## Only flying into the ground destroys the plane. Standing still on its own
## airfield, a plane is repaired.
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
## A part crossed into a new PartState (damaged, critical, destroyed, or repaired).
signal part_state_changed(plane: PlaneActor, part: Part, state: PartState)
## The wheels (or the belly, if [param on_wheels] is false) met the ground and
## the plane survived. [param sink_speed] is how fast it was coming down (m/s).
signal touched_down(plane: PlaneActor, sink_speed: float, on_wheels: bool)
signal lifted_off(plane: PlaneActor)
signal engine_started(plane: PlaneActor)
## The pilot shut the engine down (not: it was shot dead).
signal engine_stopped(plane: PlaneActor)
## The undercarriage lever was moved.
signal gear_moved(plane: PlaneActor, going_down: bool)
## Ground crew have finished: everything is repaired and the tank is full.
signal serviced(plane: PlaneActor)

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
## Which wing panel each gun station is in (left inner, right inner, left
## outer, right outer). A wing that comes off takes its guns with it.
const GUN_STATION_PARTS: Array[Part] = [Part.LEFT_WING, Part.RIGHT_WING, Part.LEFT_WING, Part.RIGHT_WING]

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

# --- Throttle and engine start -------------------------------------------------
## Seconds from pressing the starter until the engine answers the throttle fully.
const ENGINE_START_TIME: float = 2.3
const ENGINE_STOP_TIME: float = 1.2
## How fast the engine follows the lever (full travel per second).
const THROTTLE_SLEW: float = 1.4
## With the throttle closed the plane slows this quickly toward gliding speed
## (1/s). Much gentler than a dead engine's windmilling propeller.
const IDLE_RESPONSE: float = 0.14

# --- Undercarriage ---------------------------------------------------------------
## Seconds for the wheels to travel fully up or down.
const GEAR_TRAVEL_TIME: float = 2.1
## Share of top speed lost with the wheels hanging in the airflow.
const GEAR_DRAG: float = 0.18
## Used if the model has no undercarriage to measure (metres).
const DEFAULT_WHEEL_HEIGHT: float = 3.4
const DEFAULT_BELLY_HEIGHT: float = 1.9

# --- On the ground ---------------------------------------------------------------
## Acceleration at full throttle from a standstill (m/s^2) for a plane with
## PlaneStats.acceleration of 0.6. A take-off run is a few hundred metres.
const GROUND_THRUST: float = 5.6
const REFERENCE_ACCELERATION: float = 0.6
## Rolling resistance (m/s^2): tarmac, grass, and sliding on the belly.
const ROLL_RUNWAY: float = 0.5
const ROLL_GRASS: float = 2.4
const BELLY_FRICTION: float = 8.5
## Wheel brakes come on by themselves when the throttle is closed.
const WHEEL_BRAKES: float = 5.0
const BRAKE_THROTTLE: float = 0.04
## Speed bled off by the air when the throttle is pulled back on the ground (1/s).
const GROUND_AIR_BRAKE: float = 0.05
## Steering on the ground: the tightest turn, and the most sideways grip.
const GROUND_TURN_RATE: float = deg_to_rad(42.0)
const GROUND_GRIP: float = 5.5
const GROUND_PITCH_RATE: float = deg_to_rad(16.0)
## The tail comes up between these fractions of take-off speed.
const TAIL_UP_START: float = 0.35
const TAIL_UP_END: float = 0.65
## Ease the stick back at least this far to leave the ground.
const LIFTOFF_STICK: float = 0.15
## Near flying speed, easing the stick back lifts the nose this far while the
## wheels are still rolling; the plane leaves the ground once it is up
## LIFTOFF_PITCH and the wings can carry it.
const ROTATE_PITCH: float = deg_to_rad(6.5)
const ROTATE_LIFT_START: float = 0.8
const LIFTOFF_PITCH: float = deg_to_rad(2.0)
const LIFTOFF_GRACE: float = 0.8
## After leaving the ground the flight model is eased in rather than switched
## on: the climb builds over LIFTOFF_CLIMB_TIME, the stick's pitch authority
## over LIFTOFF_CONTROL_TIME, and the engine's pull over LIFTOFF_THRUST_TIME
## (from what it had on the runway up to LIFTOFF_THRUST_GAIN times that).
const LIFTOFF_CLIMB_TIME: float = 1.6
const LIFTOFF_CONTROL_TIME: float = 2.5
const LIFTOFF_CONTROL_START: float = 0.3
const LIFTOFF_THRUST_TIME: float = 5.0
const LIFTOFF_THRUST_GAIN: float = 3.5
## The landing flaps stay down after the wheels come up until the plane is
## going this share of top speed, so cleaning up does not drop it.
const CLEAN_UP_SPEED_RATIO: float = 0.68
## Running into a hangar faster than this destroys the plane (m/s).
const GROUND_CRASH_SPEED: float = 10.0

# --- Close to the ground ----------------------------------------------------------
## Within this height of an airfield (metres under the wheels) the air
## trapped under the wings helps: more lift, and a softer arrival.
const GROUND_EFFECT_HEIGHT: float = 10.0
const GROUND_EFFECT_LIFT: float = 0.15
## Share of the rate of descent left at the surface. It applies in full up to
## CUSHION_FULL_SINK m/s of descent and not at all from CUSHION_NO_SINK.
const GROUND_CUSHION: float = 0.6
const CUSHION_FULL_SINK: float = 10.0
const CUSHION_NO_SINK: float = 15.0
## With the wheels down the nose is eased up toward -FLARE_PITCH in the last
## few metres, as a pilot would flare, unless the stick is held forward.
const FLARE_PITCH: float = deg_to_rad(2.0)
const FLARE_RATE: float = deg_to_rad(16.0)
## A plane this far under the surface as it crosses the edge of the island has
## caught the lip with its wheels; further under, it has flown into the cliff.
const LIP_DEPTH: float = 1.5
const CLIFF_DEPTH: float = 6.0

# --- Landing -----------------------------------------------------------------------
# Rates of descent (m/s) at the surface, after the cushion. See _touch_down().
## Up to this is a good landing.
const FIRM_LANDING_SINK: float = 6.0
## Above this one undercarriage leg collapses; above the next, both.
const GEAR_COLLAPSE_SINK: float = 9.5
const BOTH_LEGS_SINK: float = 12.5
## Above this, or steeper or more banked than these, the plane is destroyed.
## Everything short of it is survivable.
const FATAL_SINK: float = 22.0
const FATAL_NOSE_DOWN: float = deg_to_rad(30.0)
const FATAL_BANK: float = deg_to_rad(70.0)
## Nose lower than this at touchdown and the propeller hits the runway; lower
## than the second and the undercarriage folds as well.
const PROP_STRIKE_PITCH: float = deg_to_rad(9.0)
const NOSE_COLLAPSE_PITCH: float = deg_to_rad(18.0)
## A wing this low scrapes its tip; this low and the tip is torn off and the
## leg on that side goes with it.
const WINGTIP_STRIKE_BANK: float = deg_to_rad(14.0)
const WINGTIP_TORN_BANK: float = deg_to_rad(30.0)
## Damage, as a share of each part's strength.
const FIRM_LANDING_WING_DAMAGE: float = 0.3
const FIRM_LANDING_FUSELAGE_DAMAGE: float = 0.2
const BELLY_FUSELAGE_DAMAGE: float = 0.3
const WINGTIP_STRIKE_DAMAGE: float = 0.6
## At the very edge of survivable (FATAL_SINK); proportionally less below it.
const CRASH_WING_DAMAGE: float = 0.8
const CRASH_FUSELAGE_DAMAGE: float = 0.7
const CRASH_ENGINE_DAMAGE: float = 0.9
const CRASH_TAIL_DAMAGE: float = 0.5
## Bits of the broken-undercarriage mask.
const GEAR_LEFT: int = 1
const GEAR_RIGHT: int = 2
## A plane on one leg: how far it leans, how high it sits between belly and
## wheels, how hard the dragging wingtip slows it and swings it round.
const ONE_LEG_BANK: float = deg_to_rad(9.0)
const ONE_LEG_HEIGHT: float = 0.5
const ONE_LEG_FRICTION: float = 6.5
const ONE_LEG_YAW_RATE: float = deg_to_rad(14.0)

# --- Repairs at the home airfield ---------------------------------------------------
## The plane must be standing this still, for this long, before work starts.
const SERVICE_MAX_SPEED: float = 1.0
const SERVICE_DELAY: float = 1.5
## Damage mended per second on every part, and seconds to fit each new part.
const SERVICE_RATE: float = 0.22
const SERVICE_REFIT_TIME: float = 1.1
const SERVICE_FUEL_RATE: float = 0.2
## A plane that comes to rest anywhere but its own airfield is not coming home:
## after this long its pilot abandons it and it counts as lost.
const STRANDED_TIME: float = 6.0

const EVADE_DURATION: float = 0.75
const EVADE_COOLDOWN: float = 4.0
const EVADE_SIDE_SPEED: float = 34.0
const EVADE_DAMAGE_MULTIPLIER: float = 0.35
## An evade roll needs working ailerons.
const EVADE_MIN_AILERONS: float = 0.3

const SPAWN_SHIELD_TIME: float = 2.5
## A plane that has just been wheeled out cannot be hurt until it leaves the
## ground, or until this long has passed, whichever comes first.
const GROUND_SHIELD_TIME: float = 25.0
## A crash is credited to the last enemy who hit this plane within this long.
## It is generous because a crippled plane can take a while to come down.
const CRASH_CREDIT_WINDOW: float = 45.0
const GUN_CONVERGENCE: float = 320.0
const AIM_ASSIST_CONE: float = deg_to_rad(3.5)
const BOUNDS_BLEND_DISTANCE: float = 220.0
## How quickly a shove from a mid-air collision fades (1/s).
const KNOCK_DAMPING: float = 2.5

# status_flags bits (replicated so remote peers can drive cosmetics).
const FLAG_EVADING: int = 4
const FLAG_BURNING: int = 8
const FLAG_SHIELDED: int = 16
const FLAG_OUT_OF_BOUNDS: int = 32
const FLAG_GOING_DOWN: int = 64
const FLAG_ON_GROUND: int = 128
const FLAG_ENGINE_ON: int = 256
const FLAG_GEAR_DOWN: int = 512
const FLAG_SERVICING: int = 1024
const FLAG_GEAR_LEFT_BROKEN: int = 2048
const FLAG_GEAR_RIGHT_BROKEN: int = 4096
const FLAG_PROP_BROKEN: int = 8192

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
## What is fitted to each mount, as item ids and Marks, so every peer can
## build the same stats and show the same aeroplane.
@export var fitting_ids: PackedStringArray = PackedStringArray()
@export var fitting_marks: PackedInt32Array = PackedInt32Array()
## Where the engine's throttle actually is, 0..1 (it follows the lever).
@export var throttle: float = 1.0
## How far the undercarriage is down: 0 = up and locked, 1 = down and locked.
@export var gear_deploy: float = 0.0

# --- Arena limits, set by the match manager ---------------------------------
var arena_center: Vector3 = Vector3.ZERO
var arena_radius: float = 1500.0
var arena_ceiling: float = 750.0

## Places a plane can land. Set by the match manager; with none, there is no
## ground to stand on and every surface is a crash.
var airfields: Array[Airfield] = []

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
## Seconds until each gun station can fire again, and where each one's muzzle
## is (in this node's space; from the model).
var _gun_cooldowns: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _gun_muzzles: Array[Vector3] = []
var _was_firing: bool = false
var _evade_time: float = 0.0
var _evade_cooldown: float = 0.0
var _evade_direction: float = 1.0
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

# --- Engine, undercarriage and ground state (server side) ---------------------
var _on_ground: bool = false
## Sliding on the fuselage instead of rolling on wheels.
var _belly: bool = false
var _engine_running: bool = true
## 0 = stopped .. 1 = running and answering the throttle.
var _engine_spool: float = 1.0
## Where the undercarriage lever is (the wheels take a while to follow).
var _gear_lever_down: bool = false
var _ground_field: Airfield
## Height of the plane's origin above the surface right now.
var _ground_height: float = 0.0
var _liftoff_grace: float = 0.0
var _service_time: float = 0.0
var _refit_timer: float = 0.0
var _service_start_load: float = 0.0
var _stranded_time: float = 0.0
## Collapsed undercarriage legs (GEAR_LEFT | GEAR_RIGHT) and a smashed propeller.
var _gear_broken: int = 0
var _prop_broken: bool = false
## Seconds since the wheels left the ground; INF for a plane that did not
## take off from a runway (so nothing is being eased in).
var _airborne_time: float = INF
## Landing flaps held down after take-off until there is speed to spare.
var _takeoff_flaps: bool = false
# Undercarriage geometry, measured from the model in _ready().
## Origin height with the tail up and the main wheels on the ground.
var _wheel_height: float = DEFAULT_WHEEL_HEIGHT
## Origin height and nose-up angle sitting on all three wheels.
var _rest_height: float = DEFAULT_WHEEL_HEIGHT
var _rest_pitch: float = deg_to_rad(12.0)
var _belly_height: float = DEFAULT_BELLY_HEIGHT

## The gun that fired most recently (PlaneAudio reads it for the right sound).
var last_fired_gun: ComponentCard
## This plane's engine, guns and break-up sounds.
var audio: PlaneAudio

@onready var input: PlaneInput = $PlaneInput
@onready var visual: PlaneVisual = $VisualRoot
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D


## Call right after instancing and *before* add_child(), so the values are part
## of the MultiplayerSpawner's spawn state.
func setup(data: PlaneData, plane_stats: PlaneStats, plane_team: Teams.Id, display_name: String, peer_id: int = 1) -> void:
	plane_data = data
	plane_id = data.id
	stats = plane_stats
	fitting_ids = stats.fitting_ids()
	fitting_marks = PackedInt32Array(stats.fitting_marks)
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
		stats = _stats_from_fitting_ids()
		speed = stats.top_speed * 0.85
	visual.build(plane_data, team, stats.fittings)
	hitboxes = PlaneHitboxes.from_visual(visual)
	_measure_undercarriage()
	_gun_muzzles = visual.gun_muzzles()
	input.set_multiplayer_authority(owner_peer_id)
	_read_angles_from_transform()
	audio = PlaneAudio.new()
	audio.name = "Audio"
	add_child(audio)
	audio.setup(self)


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
	visual.set_propeller(_propeller_ratio())
	visual.set_gear(gear_deploy, broken_gear_mask(), velocity)
	visual.set_propeller_broken(is_propeller_broken())
	visual.set_roll_angle(visual_roll)
	visual.set_part_damage(part_damage, velocity, has_flag(FLAG_BURNING))
	visual.set_controls(control_state)


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func forward() -> Vector3:
	return -global_transform.basis.z


func has_flag(flag: int) -> bool:
	return status_flags & flag != 0


func is_evading() -> bool:
	return has_flag(FLAG_EVADING)


func is_out_of_bounds() -> bool:
	return has_flag(FLAG_OUT_OF_BOUNDS)


## True when the plane can no longer hold itself in the air: not enough lift,
## no engine, or no tail. It is still flying and still dangerous, but it is on
## its way down. Bots stop wasting ammunition on it.
func is_going_down() -> bool:
	return has_flag(FLAG_GOING_DOWN)


## Wheels (or belly) on the ground.
func is_on_ground() -> bool:
	return has_flag(FLAG_ON_GROUND)


## The engine is turning: switched on, not destroyed, and with fuel to burn.
func is_engine_running() -> bool:
	return has_flag(FLAG_ENGINE_ON) and engine_power() > 0.0


## Where the undercarriage lever is. See gear_deploy for the wheels themselves.
func is_gear_down() -> bool:
	return has_flag(FLAG_GEAR_DOWN)


## Ground crew are working on the plane right now.
func is_servicing() -> bool:
	return has_flag(FLAG_SERVICING)


## True when there is something for ground crew to fix or fill.
func needs_service() -> bool:
	if fuel < 1.0 or _burn_time > 0.0 or _belly or _gear_broken != 0 or _prop_broken:
		return true
	for damage: float in part_damage:
		if damage > 0.0:
			return true
	return false


## How far through the current repair job the ground crew are, 0..1.
func service_progress() -> float:
	if _service_start_load <= 0.0:
		return 1.0
	return clampf(1.0 - _service_load() / _service_start_load, 0.0, 1.0)


## Speed (m/s) at which this plane, undamaged and with its wheels and flaps
## down, has enough lift to leave the ground.
func takeoff_speed() -> float:
	return stats.stall_speed / sqrt(1.0 + FLAP_LIFT_BONUS)


## Both wheels are down, locked, unbroken and still attached to their wings.
func gear_usable() -> bool:
	return _legs_standing() == 2


## Which undercarriage legs have collapsed: GEAR_LEFT | GEAR_RIGHT bits.
func broken_gear_mask() -> int:
	var mask: int = 0
	if has_flag(FLAG_GEAR_LEFT_BROKEN):
		mask |= GEAR_LEFT
	if has_flag(FLAG_GEAR_RIGHT_BROKEN):
		mask |= GEAR_RIGHT
	return mask


## The propeller has been smashed on the ground: the engine cannot pull.
func is_propeller_broken() -> bool:
	return has_flag(FLAG_PROP_BROKEN)


## The rate of descent (m/s) the plane would arrive with if it met an
## airfield at its present rate of descent, after the cushion near the ground.
func predicted_touchdown_sink() -> float:
	return _cushioned_sink(maxf(-velocity.y, 0.0), 1.0)


## The airfield whose flat top [param world_position] is over, or null.
func airfield_at(world_position: Vector3) -> Airfield:
	for field: Airfield in airfields:
		if is_instance_valid(field) and field.contains(world_position):
			return field
	return null


## This plane's own base, or null.
func home_airfield() -> Airfield:
	for field: Airfield in airfields:
		if is_instance_valid(field) and field.team == team:
			return field
	return null


## Height of the wheels (or the belly, with the wheels up) above whatever is
## underneath: the airfield if the plane is over one, otherwise the sea.
func height_above_ground() -> float:
	var field: Airfield = airfield_at(global_position)
	var floor_y: float = field.surface_y() if field != null else 0.0
	return global_position.y - floor_y - _ride_height()


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
	if fuel <= 0.0 or part_damage[Part.ENGINE] >= 1.0 or _prop_broken:
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


func is_evade_ready() -> bool:
	return _evade_cooldown <= 0.0 and _evade_time <= 0.0 and alive and _aileron_health() >= EVADE_MIN_AILERONS


## True when at least one fitted gun is still attached to the plane.
func has_guns() -> bool:
	for station: int in range(CommanderProgression.GUN_STATION_COUNT):
		if stats.gun_at(station) != null and not is_part_gone(GUN_STATION_PARTS[station]):
			return true
	return false


## Rate of descent (m/s, at the surface) up to which this plane's
## undercarriage makes a clean landing, and above which a leg collapses.
func firm_landing_sink() -> float:
	return FIRM_LANDING_SINK * stats.gear_strength


func gear_collapse_sink() -> float:
	return GEAR_COLLAPSE_SINK * stats.gear_strength


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


## Puts the plane at [param spawn_transform], factory fresh. By default it is
## already flying. With [param parked] it stands on the airfield under that
## point instead (the transform's origin is then a point on the ground): engine
## off, wheels down, throttle closed, waiting for its pilot.
func respawn(spawn_transform: Transform3D, parked: bool = false) -> void:
	global_transform = spawn_transform.orthonormalized()
	_read_angles_from_transform()
	bank = 0.0
	_yaw_rate = 0.0
	_pitch_rate = 0.0
	var field: Airfield = airfield_at(global_position) if parked else null
	_on_ground = field != null
	_ground_field = field
	_belly = false
	_engine_running = not _on_ground
	_engine_spool = 1.0 if _engine_running else 0.0
	throttle = 1.0 if _engine_running else 0.0
	input.throttle = throttle
	_gear_lever_down = _on_ground
	gear_deploy = 1.0 if _on_ground else 0.0
	_liftoff_grace = 0.0
	_service_time = 0.0
	_service_start_load = 0.0
	_stranded_time = 0.0
	_gear_broken = 0
	_prop_broken = false
	_airborne_time = INF
	_takeoff_flaps = _on_ground
	if _on_ground:
		pitch = _rest_pitch
		_ground_height = _rest_height
		global_position.y = field.surface_y() + _ground_height
		speed = 0.0
	else:
		speed = stats.top_speed * 0.85
	rotation = Vector3(pitch, yaw, bank)
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
	_burn_time = 0.0
	_burn_dps = 0.0
	_burn_source = null
	_last_attacker = null
	_last_attacker_age = INF
	_doomed_by = null
	_gun_cooldowns.fill(0.0)
	_was_firing = false
	_spawn_shield = GROUND_SHIELD_TIME if _on_ground else SPAWN_SHIELD_TIME
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
## protection, and flying. For tests, cutscenes and editor tools.
func teleport(new_transform: Transform3D) -> void:
	_on_ground = false
	_belly = false
	_airborne_time = INF
	_spawn_shield = 0.0
	global_transform = new_transform.orthonormalized()
	_read_angles_from_transform()
	bank = 0.0
	rotation = Vector3(pitch, yaw, bank)
	_yaw_rate = 0.0
	_pitch_rate = 0.0
	_knock_velocity = Vector3.ZERO
	velocity = forward() * speed
	_refresh_status_flags()
	reset_physics_interpolation()


## Starts or stops the engine at once, with no starter and no spool-up.
## For tests, cutscenes and editor tools.
func set_engine_running(running: bool) -> void:
	_engine_running = running and engine_power() > 0.0
	_engine_spool = 1.0 if _engine_running else 0.0
	_refresh_status_flags()


## Puts the undercarriage up or down at once, with no travel time.
## For tests, cutscenes and editor tools.
func set_gear_down(down: bool) -> void:
	_gear_lever_down = down
	gear_deploy = 1.0 if down else 0.0
	_refresh_status_flags()


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
	var steer: Vector2 = input.steer.limit_length(1.0)
	_tick_engine(delta)
	_tick_gear(delta)
	_liftoff_grace = maxf(_liftoff_grace - delta, 0.0)
	_airborne_time += delta
	if _on_ground:
		# No rolls with the wheels on the ground.
		input.consume_evade()
		if _integrate_ground(steer, delta):
			return
		# Left the ground this tick (took off, or ran off the edge): fly on.
	steer = _apply_bounds_assist(steer)

	if input.consume_evade():
		_try_start_evade(steer.x)

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
		leak *= stats.fuel_leak  # Self-sealing tanks.
		fuel = maxf(fuel - leak * delta, 0.0)

	# Combat flaps: pulling hard drops them for a tighter turn at the cost of
	# speed. A shot-up flap gives less, and uneven flaps pull the plane round.
	var flap_demand: float = clampf((steer.length() - FLAP_DEPLOY_STICK) / (1.0 - FLAP_DEPLOY_STICK), 0.0, 1.0)
	# The landing flaps come down with the wheels, and after a take-off they
	# stay down until the plane has speed in hand.
	if gear_deploy > 0.5:
		_takeoff_flaps = true
	elif speed >= stats.top_speed * CLEAN_UP_SPEED_RATIO:
		_takeoff_flaps = false
	flap_demand = maxf(flap_demand, maxf(gear_deploy, 1.0 if _takeoff_flaps else 0.0))
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
	var speed_fraction: float = speed / maxf(stats.stall_speed, 1.0)
	var speed_lift: float = clampf(speed_fraction * speed_fraction, 0.0, 1.0)
	var closeness: float = _ground_closeness()
	_lift_ratio = clampf(wing_lift * speed_lift * (1.0 + FLAP_LIFT_BONUS * flap_effect) * (1.0 + GROUND_EFFECT_LIFT * closeness), 0.0, 1.0)
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
	if _airborne_time < LIFTOFF_CONTROL_TIME:
		# Just off the runway: the stick comes alive gradually, not all at once.
		pitch_target *= lerpf(LIFTOFF_CONTROL_START, 1.0, _airborne_time / LIFTOFF_CONTROL_TIME)
	if closeness > 0.0 and gear_deploy > 0.5 and pitch < -FLARE_PITCH and steer.y > -0.5:
		# The flare: ease the nose up over the last few metres.
		pitch_target += FLARE_RATE * closeness * clampf((-FLARE_PITCH - pitch) / deg_to_rad(6.0), 0.0, 1.0)
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

	# --- Speed: the throttle sets what the engine is asked for; climbing ------
	# bleeds speed and diving builds it.
	var drive: float = _drive()
	var drag: float = (1.0 - WING_DRAG * (2.0 - left_lift - right_lift)) * (1.0 - FLAP_DRAG * _flap_deploy) * (1.0 - GEAR_DRAG * gear_deploy)
	var powered_speed: float = stats.top_speed * (1.0 - ENGINE_SPEED_LOSS * (1.0 - power)) * drag
	var powered_response: float = stats.acceleration * (1.0 - ENGINE_ACCEL_LOSS * (1.0 - power))
	# With no drive at all the plane settles to a glide: quickly behind a dead
	# engine's windmilling propeller, gently behind one that is merely idling.
	var glide_response: float = IDLE_RESPONSE if power > 0.0 else DEAD_ENGINE_RESPONSE
	var target_speed: float = lerpf(stats.top_speed * DEAD_ENGINE_SPEED_RATIO, powered_speed, drive)
	var engine_response: float = lerpf(glide_response, powered_response, drive)
	var gravity_pull: float = -sin(pitch) * GRAVITY_ACCEL
	if pitch > 0.0:
		gravity_pull /= maxf(stats.climb_rate, 0.1)
		if _airborne_time < LIFTOFF_CLIMB_TIME:
			# The climb is still building (see below), and so is its cost.
			gravity_pull *= smoothstep(0.0, 1.0, _airborne_time / LIFTOFF_CLIMB_TIME)
	var engine_pull: float = (target_speed - speed) * engine_response
	if _airborne_time < LIFTOFF_THRUST_TIME and engine_pull > 0.0:
		# Fresh off the runway the engine pulls no harder than it did on it,
		# then works up to its full effect.
		engine_pull = minf(engine_pull, _ground_thrust(drive, power) * lerpf(1.0, LIFTOFF_THRUST_GAIN, _airborne_time / LIFTOFF_THRUST_TIME))
	speed += (engine_pull + gravity_pull) * delta
	speed = clampf(speed, 0.0, stats.top_speed * DIVE_SPEED_RATIO)

	control_state = Vector3(steer.x, steer.y, _flap_deploy)
	_knock_velocity = _knock_velocity.lerp(Vector3.ZERO, 1.0 - exp(-KNOCK_DAMPING * delta))
	velocity = forward() * speed + Vector3.DOWN * SINK_SPEED * lift_deficit + _evade_velocity() + _knock_velocity
	if _airborne_time < LIFTOFF_CLIMB_TIME and velocity.y > 0.0:
		# The climb builds from nothing instead of starting with a jump.
		velocity.y *= smoothstep(0.0, 1.0, _airborne_time / LIFTOFF_CLIMB_TIME)
	if velocity.y < 0.0:
		velocity.y = -_cushioned_sink(-velocity.y, closeness)
	if _meet_the_ground(delta):
		return
	var collision: KinematicCollision3D = move_and_collide(velocity * delta)
	if collision != null:
		# Hit the sea, a cliff or a building. Apart from a bad landing this is
		# the only way a plane dies on its own; credit whoever put it in this state.
		_die(recent_attacker())


# ---------------------------------------------------------------------------
# Engine, throttle and undercarriage
# ---------------------------------------------------------------------------

## Share of the engine's available power that is being used right now, 0..1:
## the throttle, once the engine is running.
func _drive() -> float:
	if engine_power() <= 0.0:
		return 0.0
	return clampf(throttle * _engine_spool, 0.0, 1.0)


func _tick_engine(delta: float) -> void:
	if input.consume_engine():
		if _engine_running:
			_engine_running = false
			engine_stopped.emit(self)
		elif engine_power() > 0.0:
			_engine_running = true
			engine_started.emit(self)
	if _engine_running and engine_power() <= 0.0:
		_engine_running = false  # Shot dead or out of fuel; it will not restart.
	if _engine_running:
		_engine_spool = move_toward(_engine_spool, 1.0, delta / ENGINE_START_TIME)
	else:
		_engine_spool = move_toward(_engine_spool, 0.0, delta / ENGINE_STOP_TIME)
	throttle = move_toward(throttle, clampf(input.throttle, 0.0, 1.0), THROTTLE_SLEW * delta)


func _tick_gear(delta: float) -> void:
	# The lever is locked while the plane's weight is on the wheels.
	if input.consume_gear() and not _on_ground:
		_gear_lever_down = not _gear_lever_down
		gear_moved.emit(self, _gear_lever_down)
	gear_deploy = move_toward(gear_deploy, 1.0 if _gear_lever_down else 0.0, delta / GEAR_TRAVEL_TIME)


## How fast the propeller should look like it is turning, 0..1.
func _propeller_ratio() -> float:
	if is_engine_running():
		return lerpf(0.3, 1.0, throttle)
	# A stopped engine still windmills in the airflow.
	return 0.0 if is_on_ground() else clampf(speed / maxf(stats.top_speed, 1.0), 0.0, 1.0) * 0.25


## Reads the wheel positions off the model: how high the plane stands with its
## tail up, and how high and how nose-up it sits on all three wheels.
func _measure_undercarriage() -> void:
	var contacts: Array[Vector3] = visual.undercarriage_contacts()
	_belly_height = maxf(visual.belly_depth(), 0.5)
	if contacts.size() < 2:
		_wheel_height = _belly_height + (DEFAULT_WHEEL_HEIGHT - DEFAULT_BELLY_HEIGHT)
		_rest_height = _wheel_height
		_rest_pitch = 0.0
		return
	# Side view: x = distance behind the origin (+Z), y = height.
	var main_wheel: Vector2 = Vector2(contacts[0].z, contacts[0].y)
	var tail_wheel: Vector2 = Vector2(contacts[1].z, contacts[1].y)
	var ground_line: Vector2 = tail_wheel - main_wheel
	_wheel_height = maxf(-main_wheel.y, _belly_height)
	_rest_pitch = clampf(atan2(ground_line.y, ground_line.x), 0.0, deg_to_rad(20.0))
	# Distance from the origin to the line through both contact points.
	_rest_height = absf(main_wheel.x * tail_wheel.y - main_wheel.y * tail_wheel.x) / maxf(ground_line.length(), 0.01)


## How many main undercarriage legs the plane can stand on right now: 2, 1
## (one has collapsed or gone with its wing) or 0 (wheels up, or both gone).
func _legs_standing() -> int:
	if gear_deploy < 0.98:
		return 0
	var legs: int = 0
	if _gear_broken & GEAR_LEFT == 0 and not is_part_gone(Part.LEFT_WING):
		legs += 1
	if _gear_broken & GEAR_RIGHT == 0 and not is_part_gone(Part.RIGHT_WING):
		legs += 1
	return legs


## Which way a plane on one leg leans: +1 with the left leg missing (left wing
## on the ground), -1 with the right leg missing, 0 if it is not on one leg.
func _lean_side() -> float:
	if _legs_standing() != 1:
		return 0.0
	var left_missing: bool = _gear_broken & GEAR_LEFT != 0 or is_part_gone(Part.LEFT_WING)
	return 1.0 if left_missing else -1.0


## Origin height above the ground for the plane's attitude and wheels.
func _ride_height() -> float:
	var legs: int = _legs_standing()
	if legs == 0:
		return _belly_height
	if legs == 1:
		return lerpf(_belly_height, _wheel_height, ONE_LEG_HEIGHT)
	var tail_down: float = clampf(pitch / maxf(_rest_pitch, 0.001), 0.0, 1.0)
	return lerpf(_wheel_height, _rest_height, tail_down)


## How close the wheels are to an airfield's surface: 0 at GROUND_EFFECT_HEIGHT
## or more (and anywhere that is not over an airfield), 1 touching it.
func _ground_closeness() -> float:
	var field: Airfield = airfield_at(global_position)
	if field == null:
		return 0.0
	var gap: float = global_position.y - field.surface_y() - _ride_height()
	return clampf(1.0 - gap / GROUND_EFFECT_HEIGHT, 0.0, 1.0)


## What is left of a rate of descent ([param descent], m/s, positive down)
## once the cushion of air under the wings near the ground has done its work.
## Gentle and moderate descents are softened; a dive is not.
func _cushioned_sink(descent: float, closeness: float) -> float:
	if descent <= 0.0 or closeness <= 0.0:
		return descent
	var softening: float = 1.0 - smoothstep(CUSHION_FULL_SINK, CUSHION_NO_SINK, descent)
	return descent * lerpf(1.0, GROUND_CUSHION, closeness * softening)


# ---------------------------------------------------------------------------
# On the ground
# ---------------------------------------------------------------------------

## One tick of rolling (or sliding) along the airfield. Returns false if the
## plane left the ground this tick, so the caller carries on with flight.
func _integrate_ground(steer: Vector2, delta: float) -> bool:
	var field: Airfield = airfield_at(global_position)
	if field == null:
		# Ran off the edge of the island. Whatever happens next is flying.
		_on_ground = false
		_belly = false
		_ground_field = null
		_airborne_time = INF
		return false
	_ground_field = field
	if not _belly and not gear_usable():
		_belly = true  # A leg, or the wing it hangs from, has just gone.
	var lean: float = _lean_side()

	# --- Lift: is it going fast enough to fly? -------------------------------
	_takeoff_flaps = true
	_flap_deploy = move_toward(_flap_deploy, gear_deploy, FLAP_SPEED * delta)
	var left_lift: float = _side_lift(Part.LEFT_WING, Part.LEFT_WINGTIP)
	var right_lift: float = _side_lift(Part.RIGHT_WING, Part.RIGHT_WINGTIP)
	var flap_effect: float = _flap_deploy * 0.5 * (part_health(Part.LEFT_FLAP) + part_health(Part.RIGHT_FLAP))
	var speed_fraction: float = speed / maxf(stats.stall_speed, 1.0)
	var raw_lift: float = 0.5 * (left_lift + right_lift) * speed_fraction * speed_fraction * (1.0 + FLAP_LIFT_BONUS * flap_effect)
	_lift_ratio = clampf(raw_lift, 0.0, 1.0)
	var elevators: float = 0.5 * (part_health(Part.LEFT_ELEVATOR) + part_health(Part.RIGHT_ELEVATOR))
	var pull: float = clampf(steer.y, 0.0, 1.0) * lerpf(PITCH_WITHOUT_ELEVATORS, 1.0, elevators)
	# The nose is already up (see "Attitude" below) by the time the wings take
	# the weight, so leaving the ground changes nothing suddenly.
	if not _belly and raw_lift >= 1.0 and pull > LIFTOFF_STICK and pitch >= LIFTOFF_PITCH:
		_lift_off()
		return false

	# --- Speed: thrust against rolling resistance and brakes ------------------
	var power: float = engine_power()
	var drive: float = _drive()
	var drag: float = (1.0 - WING_DRAG * (2.0 - left_lift - right_lift)) * (1.0 - FLAP_DRAG * _flap_deploy) * (1.0 - GEAR_DRAG * gear_deploy)
	var target_speed: float = stats.top_speed * (1.0 - ENGINE_SPEED_LOSS * (1.0 - power)) * drive * drag
	var acceleration: float
	if target_speed > speed and not _belly:
		acceleration = minf((target_speed - speed) * stats.acceleration, _ground_thrust(drive, power))
	else:
		acceleration = minf((target_speed - speed) * GROUND_AIR_BRAKE, 0.0)
	var resistance: float = BELLY_FRICTION
	if lean != 0.0:
		resistance = ONE_LEG_FRICTION
	elif not _belly:
		resistance = ROLL_RUNWAY if field.is_on_runway(global_position) else ROLL_GRASS
		if input.throttle <= BRAKE_THROTTLE:
			resistance += WHEEL_BRAKES
	speed = maxf(speed + (acceleration - resistance) * delta, 0.0)

	# --- Steering: rudder and tail wheel, limited by grip at speed ------------
	var turn_limit: float = minf(GROUND_TURN_RATE, GROUND_GRIP / maxf(speed, 0.1)) * clampf(speed / 2.0, 0.0, 1.0)
	if _belly:
		turn_limit *= 0.15
	var yaw_target: float = -steer.x * turn_limit * lerpf(0.5, 1.0, part_health(Part.RUDDER))
	# On one leg the dragging wingtip pulls the plane round toward itself.
	yaw_target += lean * ONE_LEG_YAW_RATE * clampf(speed / 20.0, 0.0, 1.0)
	_yaw_rate = lerpf(_yaw_rate, yaw_target, 1.0 - exp(-STICK_RESPONSE * delta))
	_pitch_rate = 0.0
	yaw = wrapf(yaw + _yaw_rate * delta, -PI, PI)

	# --- Attitude: tail down at rest, coming up as the speed builds, and then --
	# the nose lifting as the pilot eases the stick back near flying speed.
	var tail_up: float = smoothstep(TAIL_UP_START, TAIL_UP_END, speed / maxf(takeoff_speed(), 1.0))
	var pitch_target: float = 0.0
	if not _belly:
		var nose_lift: float = pull * smoothstep(ROTATE_LIFT_START, 1.0, raw_lift)
		pitch_target = maxf(_rest_pitch * (1.0 - tail_up), ROTATE_PITCH * nose_lift)
	pitch = move_toward(pitch, pitch_target, GROUND_PITCH_RATE * delta)
	bank = lerpf(bank, lean * ONE_LEG_BANK, 1.0 - exp(-6.0 * delta))
	rotation = Vector3(pitch, yaw, bank)
	_ground_height = move_toward(_ground_height, _ride_height(), 3.0 * delta)

	# --- Move ------------------------------------------------------------------
	control_state = Vector3(steer.x, steer.y, _flap_deploy)
	_knock_velocity = _knock_velocity.lerp(Vector3.ZERO, 1.0 - exp(-KNOCK_DAMPING * delta))
	var heading: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))
	velocity = heading * speed + Vector3(_knock_velocity.x, 0.0, _knock_velocity.z)
	var collision: KinematicCollision3D = move_and_collide(velocity * delta)
	if collision != null:
		if speed > GROUND_CRASH_SPEED:
			_die(recent_attacker())
			return true
		speed = 0.0
	global_position.y = field.surface_y() + _ground_height
	_tick_service(field, delta)
	if field.team != team and speed < SERVICE_MAX_SPEED:
		_stranded_time += delta
		if _stranded_time >= STRANDED_TIME:
			_die(recent_attacker())
	else:
		_stranded_time = 0.0
	return true


## Most the engine can accelerate the plane (m/s^2) at this throttle and state
## of repair, before drag is counted.
func _ground_thrust(drive: float, power: float) -> float:
	return GROUND_THRUST * (stats.acceleration / REFERENCE_ACCELERATION) * drive * (1.0 - ENGINE_ACCEL_LOSS * (1.0 - power))


func _lift_off() -> void:
	_on_ground = false
	_belly = false
	_ground_field = null
	_service_time = 0.0
	_liftoff_grace = LIFTOFF_GRACE
	# From here the flight model eases in: see _airborne_time in _integrate_flight.
	_airborne_time = 0.0
	# Protection for a freshly wheeled-out plane ends once it is flying.
	_spawn_shield = minf(_spawn_shield, SPAWN_SHIELD_TIME)
	lifted_off.emit(self)


## Called in flight just before moving. If this tick would take the plane into
## the top of an airfield it lands there, however well or badly, and this
## returns true.
func _meet_the_ground(delta: float) -> bool:
	var field: Airfield = airfield_at(global_position)
	if field == null:
		return false
	var floor_y: float = field.surface_y() + _ride_height()
	var below: float = floor_y - global_position.y
	if below > CLIFF_DEPTH:
		# Well under the surface: it flew into the side of the island.
		_die(recent_attacker())
		return true
	if global_position.y + velocity.y * delta > floor_y:
		return false
	var sink: float = -velocity.y
	if below > LIP_DEPTH:
		# Too low over the edge: the lip of the island takes the wheels off.
		sink = maxf(sink, gear_collapse_sink() + below)
	elif sink <= 0.0 or (_liftoff_grace > 0.0 and sink < 2.0):
		return false  # Skimming the surface on the way up.
	_touch_down(field, sink)
	return true


## The plane has reached the surface, coming down at [param sink] m/s.
##
## Gently and level, on its wheels, is a landing. Rougher than that and the
## aeroplane pays for it, a piece at a time: strained wings, a collapsed
## undercarriage leg (then it slides on a wingtip), both legs (then it slides
## on its belly), a smashed propeller, a torn-off wingtip, a wrecked airframe.
## The pilot walks away from all of those, and at home the ground crew can
## mend them. Only flying into the ground (a dive, or upside down) destroys
## the plane outright.
func _touch_down(field: Airfield, sink: float) -> void:
	global_position.y = field.surface_y() + _ride_height()
	var nose_down: float = -pitch
	if sink > FATAL_SINK or nose_down > FATAL_NOSE_DOWN or absf(bank) > FATAL_BANK:
		_die(recent_attacker())
		return
	# +1 = left wing low, -1 = right wing low. Level: whichever luck picks.
	var low_side: float = signf(bank)
	if absf(bank) < deg_to_rad(1.0):
		low_side = 1.0 if _rng.randf() < 0.5 else -1.0
	var low_leg: int = GEAR_LEFT if low_side > 0.0 else GEAR_RIGHT
	var low_wingtip: Part = Part.LEFT_WINGTIP if low_side > 0.0 else Part.RIGHT_WINGTIP

	# Stronger legs move every threshold the undercarriage is responsible for.
	var firm_sink: float = firm_landing_sink()
	var collapse_sink: float = gear_collapse_sink()
	if gear_usable():
		if sink > firm_sink:
			# A heavy arrival strains whatever the legs are bolted to.
			var strain: float = clampf((sink - firm_sink) / (collapse_sink - firm_sink), 0.0, 1.0)
			_impact_damage(Part.LEFT_WING, FIRM_LANDING_WING_DAMAGE * strain)
			_impact_damage(Part.RIGHT_WING, FIRM_LANDING_WING_DAMAGE * strain)
			_impact_damage(Part.FUSELAGE, FIRM_LANDING_FUSELAGE_DAMAGE * strain)
		if sink > BOTH_LEGS_SINK * stats.gear_strength or nose_down > NOSE_COLLAPSE_PITCH:
			_break_gear(GEAR_LEFT | GEAR_RIGHT)
		elif sink > collapse_sink or absf(bank) > WINGTIP_TORN_BANK:
			_break_gear(low_leg)
		if nose_down > PROP_STRIKE_PITCH:
			_break_propeller()
	if not gear_usable():
		# No wheels under it, or not enough of them: the nose goes down, the
		# propeller digs in and the underside takes the scrape.
		_break_propeller()
		_impact_damage(Part.FUSELAGE, BELLY_FUSELAGE_DAMAGE)
	if sink > GEAR_COLLAPSE_SINK:
		# Beyond what the undercarriage can absorb, the airframe takes the rest.
		var crash: float = clampf((sink - GEAR_COLLAPSE_SINK) / (FATAL_SINK - GEAR_COLLAPSE_SINK), 0.0, 1.0)
		_impact_damage(Part.LEFT_WING, CRASH_WING_DAMAGE * crash)
		_impact_damage(Part.RIGHT_WING, CRASH_WING_DAMAGE * crash)
		_impact_damage(Part.FUSELAGE, CRASH_FUSELAGE_DAMAGE * crash)
		_impact_damage(Part.ENGINE, CRASH_ENGINE_DAMAGE * crash)
		_impact_damage(Part.TAIL, CRASH_TAIL_DAMAGE * crash)
	if absf(bank) > WINGTIP_TORN_BANK:
		_impact_damage(low_wingtip, 1.0)
	elif absf(bank) > WINGTIP_STRIKE_BANK:
		_impact_damage(low_wingtip, WINGTIP_STRIKE_DAMAGE)

	_on_ground = true
	_belly = not gear_usable()
	_ground_field = field
	_ground_height = global_position.y - field.surface_y()
	speed = Vector2(velocity.x, velocity.z).length()
	_pitch_rate = 0.0
	_yaw_rate *= 0.3
	_evade_time = 0.0
	visual_roll = 0.0
	_service_time = 0.0
	_airborne_time = INF
	_refresh_status_flags()
	touched_down.emit(self, sink, not _belly)


## Collapses undercarriage legs ([param legs] is GEAR_LEFT, GEAR_RIGHT or both).
func _break_gear(legs: int) -> void:
	var newly: int = legs & ~_gear_broken
	if newly == 0:
		return
	_gear_broken |= newly
	damaged.emit(self, stats.max_hp * 0.1, null)


## The propeller has hit the ground. The engine is unhurt but can do nothing.
func _break_propeller() -> void:
	if _prop_broken:
		return
	_prop_broken = true
	_engine_running = false
	damaged.emit(self, stats.max_hp * 0.1, null)


## Damage from hitting the ground: [param share] of the part's strength.
## Spawn protection and evade rolls do not soften the ground.
func _impact_damage(part: Part, share: float) -> void:
	if share <= 0.0 or is_part_gone(part):
		return
	var amount: float = share * maxf(stats.max_hp * PART_STRENGTH[part], 1.0)
	_damage_part(part, amount, null)
	damaged.emit(self, amount, null)


## Everything ground crew still have to put right, as one number.
func _service_load() -> float:
	var total: float = 1.0 - fuel
	for damage: float in part_damage:
		total += damage
	if _gear_broken & GEAR_LEFT != 0:
		total += 1.0
	if _gear_broken & GEAR_RIGHT != 0:
		total += 1.0
	if _prop_broken:
		total += 1.0
	if _belly:
		total += 1.0
	return total


## Repairs at the plane's own airfield, once it is standing still: fires are
## put out, the tank is filled, holes are patched and missing or broken parts
## are replaced one at a time (the wing before the flap that hangs on it, and
## before the undercarriage leg under it).
func _tick_service(field: Airfield, delta: float) -> void:
	if field.team != team or speed > SERVICE_MAX_SPEED or not needs_service():
		_service_time = 0.0
		return
	if _service_time <= 0.0:
		_service_start_load = _service_load()
		_refit_timer = SERVICE_REFIT_TIME
	_service_time += delta
	if _service_time < SERVICE_DELAY:
		return
	_burn_time = 0.0
	_burn_dps = 0.0
	_burn_source = null
	fuel = minf(fuel + SERVICE_FUEL_RATE * delta, 1.0)
	_refit_timer -= delta
	for index: int in range(PART_COUNT):
		var part: Part = index as Part
		var damage: float = part_damage[index]
		if damage <= 0.0:
			continue
		var parent: int = PART_PARENT[index]
		if parent >= 0 and is_part_gone(parent as Part):
			continue  # Nothing to bolt it to yet.
		var before: PartState = part_state(part)
		if damage >= 1.0:
			# Destroyed: a new one is fitted, which takes a moment.
			if _refit_timer > 0.0:
				continue
			_refit_timer = SERVICE_REFIT_TIME
			part_damage[index] = 0.0
			_refresh_gone_mask()
		else:
			part_damage[index] = maxf(damage - SERVICE_RATE * delta, 0.0)
		var after: PartState = part_state(part)
		if after != before:
			part_state_changed.emit(self, part, after)
	if _refit_timer <= 0.0 and _prop_broken:
		_prop_broken = false
		_refit_timer = SERVICE_REFIT_TIME
	if _refit_timer <= 0.0 and _gear_broken & GEAR_LEFT != 0 and not is_part_gone(Part.LEFT_WING):
		_gear_broken &= ~GEAR_LEFT
		_refit_timer = SERVICE_REFIT_TIME
	if _refit_timer <= 0.0 and _gear_broken & GEAR_RIGHT != 0 and not is_part_gone(Part.RIGHT_WING):
		_gear_broken &= ~GEAR_RIGHT
		_refit_timer = SERVICE_REFIT_TIME
	if _belly and _gear_broken == 0 and not is_part_gone(Part.LEFT_WING) and not is_part_gone(Part.RIGHT_WING):
		# Jacked up and the wheels lowered under it.
		_gear_lever_down = true
		if gear_deploy >= 0.98:
			_belly = false
	if not needs_service():
		_doomed_by = null
		_last_attacker = null
		_last_attacker_age = INF
		_service_start_load = 0.0
		serviced.emit(self)


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


# ---------------------------------------------------------------------------
# Weapons
# ---------------------------------------------------------------------------

## Every fitted gun fires on its own clock, at its own rate. A plane with one
## gun fitted fires one gun.
func _tick_weapons(delta: float) -> void:
	for station: int in range(_gun_cooldowns.size()):
		_gun_cooldowns[station] = maxf(_gun_cooldowns[station] - delta, 0.0)
	var firing: bool = input.firing and not weapons_locked and bullet_system != null and _evade_time <= 0.0 and not _on_ground
	if firing and not _was_firing:
		_stagger_guns()
	_was_firing = firing
	if not firing:
		return
	for station: int in range(CommanderProgression.GUN_STATION_COUNT):
		var gun: ComponentCard = stats.gun_at(station)
		if gun == null or _gun_cooldowns[station] > 0.0 or is_part_gone(GUN_STATION_PARTS[station]):
			continue
		_gun_cooldowns[station] = 1.0 / maxf(gun.fire_rate, 0.1)
		_fire_gun(station, gun)


## As the trigger is pressed the guns are set a fraction of a beat apart, so
## they rattle one after another instead of all firing on the same instant.
func _stagger_guns() -> void:
	var count: int = maxi(stats.gun_count(), 1)
	var order: int = 0
	for station: int in range(CommanderProgression.GUN_STATION_COUNT):
		var gun: ComponentCard = stats.gun_at(station)
		if gun == null:
			continue
		_gun_cooldowns[station] = maxf(_gun_cooldowns[station], float(order) / (float(count) * maxf(gun.fire_rate, 0.1)))
		order += 1


func _fire_gun(station: int, gun: ComponentCard) -> void:
	visual.flash_muzzle(station)
	var muzzle: Vector3 = _gun_muzzles[station] if station < _gun_muzzles.size() else Vector3.ZERO
	var origin: Vector3 = global_transform * muzzle
	var nose: Vector3 = forward()
	# Wing guns converge on the centre line a few hundred metres out.
	var direction: Vector3 = (global_position + nose * GUN_CONVERGENCE - origin).normalized()
	# Aim assist: only ever a small correction, validated here on the server.
	if input.assist_active:
		var to_assist: Vector3 = (input.assist_point - origin).normalized()
		if nose.angle_to(to_assist) <= AIM_ASSIST_CONE:
			direction = to_assist
	var spread: float = tan(deg_to_rad(gun.spread_deg))
	var plane_basis: Basis = global_transform.basis
	direction = (direction + plane_basis.x * _rng.randfn(0.0, spread) + plane_basis.y * _rng.randfn(0.0, spread)).normalized()
	# Bullets inherit the plane's velocity; Ballistics.lead_point assumes this.
	# They live a little longer than range / speed because drag slows them.
	bullet_system.spawn(origin, direction * gun.muzzle_speed + velocity, self,
			gun.gun_range / gun.muzzle_speed * 1.15, gun.damage_at(stats.gun_mark(station)), gun.muzzle_speed)
	last_fired_gun = gun
	shot_fired.emit(self)


## Stats for a plane that arrived with only its replicated fitting ids (a
## remote peer), or with nothing at all (then: as it left the factory).
func _stats_from_fitting_ids() -> PlaneStats:
	if fitting_ids.size() != CommanderProgression.MOUNT_COUNT:
		return plane_data.build_stock_stats(1)
	var fittings: Array[ComponentCard] = []
	var marks: Array[int] = []
	for mount: int in range(CommanderProgression.MOUNT_COUNT):
		fittings.append(GameCatalog.find_card(StringName(fitting_ids[mount])))
		marks.append(fitting_marks[mount] if mount < fitting_marks.size() else 1)
	return plane_data.build_stats(1, fittings, marks)


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
	if _evade_time > 0.0:
		flags |= FLAG_EVADING
	# On fire: an incendiary hit, a destroyed engine, or fuel pouring from a
	# destroyed fuselage.
	if _burn_time > 0.0 or part_damage[Part.ENGINE] >= 1.0 or (part_damage[Part.FUSELAGE] >= 1.0 and fuel > 0.0):
		flags |= FLAG_BURNING
	if _spawn_shield > 0.0:
		flags |= FLAG_SHIELDED
	if _on_ground:
		flags |= FLAG_ON_GROUND
		if _service_time >= SERVICE_DELAY and needs_service():
			flags |= FLAG_SERVICING
	elif engine_power() <= 0.0 or _wing_lift() < 0.75 or is_part_gone(Part.TAIL):
		flags |= FLAG_GOING_DOWN
	if _engine_running:
		flags |= FLAG_ENGINE_ON
	if _gear_lever_down:
		flags |= FLAG_GEAR_DOWN
	if _gear_broken & GEAR_LEFT != 0:
		flags |= FLAG_GEAR_LEFT_BROKEN
	if _gear_broken & GEAR_RIGHT != 0:
		flags |= FLAG_GEAR_RIGHT_BROKEN
	if _prop_broken:
		flags |= FLAG_PROP_BROKEN
	var offset: Vector3 = global_position - arena_center
	offset.y = 0.0
	if offset.length() > arena_radius:
		flags |= FLAG_OUT_OF_BOUNDS
	status_flags = flags


func _read_angles_from_transform() -> void:
	var nose: Vector3 = -global_transform.basis.z
	yaw = atan2(-nose.x, -nose.z)
	pitch = clampf(asin(clampf(nose.y, -1.0, 1.0)), -MAX_PITCH, MAX_PITCH)
