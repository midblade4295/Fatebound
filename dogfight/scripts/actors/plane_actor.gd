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
## pitch, the fin and rudder steer and steady the nose, flaps slow the landing,
## the engine pulls, the fuselage holds the fuel and the control runs. A hurt
## part does its job worse; a destroyed one comes off (taking whatever is
## attached to it) and stops doing it at all. Nothing ever "kills" a plane
## directly. It is destroyed when it hits the sea, the ground, a ship, or
## another aircraft hard enough. Until then the pilot keeps whatever control
## the remaining parts give, all the way down.
##
## The controls are simple (stick sideways = turn, stick back = nose up) but
## what they act on is physics. Lift goes with the square of airspeed and is
## counted in g. The stick asks the wings for lift: enough upward to hold or
## change the flight path, and some sideways to turn, which the plane gets by
## banking. The wings can only give what the airspeed allows, so:
##  - a turn is a bank, it is wider the faster the plane flies and tightest
##    at the speed where the wings can just reach the g limit;
##  - pulling hard costs speed (drag from making lift), so a turn held too
##    long gets slower and wider;
##  - too slow, the wings cannot hold the plane up and its path curves
##    downward. Nothing drops it: it descends, picks up speed, and flies
##    again. Putting the nose down gets the speed back sooner;
##  - with the engine stopped or idling it is a glider, trading height for
##    speed at about 1 in 6.
##
## Planes start on the ground. The pilot starts the engine, opens the throttle
## and rolls down the runway on real wheels: it swings, it has to be held
## straight, the tail has to be lifted, and it leaves the ground when the
## wings lift it. Coming home works the other way round: gear down, throttle
## back, and put it on the island. How gently each wheel (or anything else)
## meets the ground decides what it costs: nothing, strained wings, a
## collapsed undercarriage leg, a scraped wingtip, a smashed propeller (see
## _ground_strike). Only flying into the ground destroys the plane. Standing still on its own
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

# --- The pilot's hands and feet ---------------------------------------------------
# The aeroplane itself is FlightDynamics: a rigid body in real gravity. These
# are only about how a pilot works its controls.
## Control surfaces move at a finite rate (full travel per second).
const CONTROL_SLEW: float = 6.0
## The pilot cannot hold the stick right back against a heavy load: full pull
## is there up to G_EASE_START, and none of it by G_EASE_END. Likewise pushing.
## With the rudder held hard over the pilot is asking for a stall or a spin,
## and the stick will take the wing to this multiple of its stalling angle.
const CROSSED_CONTROLS_ATTACK: float = 2.0
const G_EASE_START: float = 5.5
const G_EASE_END: float = 8.5
const NEGATIVE_G_EASE_START: float = -1.5
const NEGATIVE_G_EASE_END: float = -3.5
## Feet: unless the pilot uses the pedals himself, they keep the slip ball
## centred (rudder per radian of sideslip). They are no help in a spin.
const COORDINATION_GAIN: float = 3.0
## ...and how hard they check the nose swinging from side to side (rudder per
## radian a second of changing sideslip).
const COORDINATION_DAMPING: float = 0.9
## With the wing stalled his feet are only this much less use: enough to keep
## an honest stall from turning into a spin, not enough to stop one he has
## kicked the plane into.
const STALLED_FEET_LOSS: float = 0.5
## How quickly yaw follows the stick on the ground (1/s).
const STICK_RESPONSE: float = 5.0
## The wing counts as stalled (for warnings and the bots) past this share, and
## the plane as spinning when it is also yawing this fast (rad/s).
const STALL_WARNING: float = 0.25
const SPIN_YAW_RATE: float = 0.7

# --- What damage does to the aeroplane -------------------------------------------
## Share of a side's lift that comes from the inner panel and from the tip.
const INNER_WING_LIFT: float = 0.6
const WINGTIP_LIFT: float = 0.4
## A panel shot to ribbons (but still attached) keeps this much of its lift,
## and a holed tailplane or fin this much of its grip.
const HOLED_WING_LIFT: float = 0.5
const HOLED_TAIL_GRIP: float = 0.55
## Extra drag coefficient from a missing wing panel's stub, and from a panel,
## tail or fuselage full of holes (at full damage).
const STUB_DRAG: float = 0.006
const HOLE_DRAG: float = 0.004
## A shot-up fuselage means stretched cables: sloppier controls.
const FUSELAGE_FEEL_LOSS: float = 0.35
## How fast the flaps can travel (share of their travel per second).
const FLAP_SPEED: float = 2.2

# --- Engine and fuel -------------------------------------------------------------
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

# --- Undercarriage ---------------------------------------------------------------
## Seconds for the wheels to travel fully up or down.
const GEAR_TRAVEL_TIME: float = 2.1
## Used if the model has no undercarriage to measure (metres).
const DEFAULT_WHEEL_HEIGHT: float = 3.4
const DEFAULT_BELLY_HEIGHT: float = 1.9

# --- On the ground ---------------------------------------------------------------
# Nothing here moves the plane. Its wheels are sprung legs with tyres and its
# belly, nose, wingtips and tail are hard points (see FlightDynamics); the
# actor only says what ground is under it and reads off how hard things hit.
## Rolling resistance as a share of the load on a wheel: tarmac and grass.
const ROLL_RUNWAY: float = 0.03
const ROLL_GRASS: float = 0.09
## Wheel brakes come on by themselves when the throttle is closed.
const BRAKE_THROTTLE: float = 0.04
## The plane counts as on the ground while the ground carries more than this
## share of its weight, and as flying again once nothing has touched for
## this long (a bounce is not a take-off).
## Miles an hour in a metre a second: every speed shown to the player is in
## mph, as on these aeroplanes' own instruments. Everything inside is SI.
const MPH: float = 2.236936
const ON_GROUND_WEIGHT: float = 0.02
const AIRBORNE_AFTER: float = 0.3
## While a wheel is on the ground the stick's sideways travel works the rudder
## bar as well as this share of the ailerons; the rudder part fades out over
## this long (s) after the last wheel leaves it.
const GROUND_AILERON_SHARE: float = 0.5
const STICK_STEERS_FADE: float = 0.7
## Running into a hangar faster than this destroys the plane (m/s).
const GROUND_CRASH_SPEED: float = 10.0

# --- Close to the ground ----------------------------------------------------------
## Within this height of an airfield (metres under the wheels) the air
## trapped under the wings helps: more lift and less drag (ground effect).
## That is all the help there is: the flare is the pilot's to fly.
const GROUND_EFFECT_HEIGHT: float = 10.0
## A plane this far under the surface as it crosses the edge of the island has
## caught the lip with its wheels; further under, it has flown into the cliff.
const LIP_DEPTH: float = 1.5
const CLIFF_DEPTH: float = 6.0

# --- Landing -----------------------------------------------------------------------
# How fast (m/s, straight down) a wheel or a hard point meets the ground. See _ground_strike().
## Up to this is a good landing.
const FIRM_LANDING_SINK: float = 6.0
## A leg that meets the ground faster than this collapses. Each leg is
## judged on its own arrival: level, both go together; one wing low, the
## low one takes it all.
const GEAR_COLLAPSE_SINK: float = 9.5
## Above this, or steeper or more banked than these, the plane is destroyed.
## Everything short of it is survivable.
const FATAL_SINK: float = 22.0
const FATAL_NOSE_DOWN: float = deg_to_rad(30.0)
const FATAL_BANK: float = deg_to_rad(70.0)
## With the nose about this low on its wheels the propeller reaches the
## ground (the HUD warns of it; the propeller's own tip decides).
const PROP_STRIKE_PITCH: float = deg_to_rad(9.0)
## A wingtip that meets the ground faster than this (m/s), or with the plane
## banked more than this, is torn off; slower, it is scraped.
const WINGTIP_TORN_SPEED: float = 6.0
const WINGTIP_TORN_BANK: float = deg_to_rad(42.0)
## A tip dragging along the ground wears away at this rate (share of its
## strength per second at 30 m/s).
const WINGTIP_SCRAPE_RATE: float = 0.12
## How far the propeller's tips reach below the cowling (m).
const PROP_BELOW_COWLING: float = 0.35
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

## A plane put straight into the air starts at this share of its top speed.
const CRUISE_SPEED_RATIO: float = 0.8
const SPAWN_SHIELD_TIME: float = 2.5
## A plane that has just been wheeled out cannot be hurt until it leaves the
## ground, or until this long has passed, whichever comes first.
const GROUND_SHIELD_TIME: float = 25.0
## A crash is credited to the last enemy who hit this plane within this long.
## It is generous because a crippled plane can take a while to come down.
const CRASH_CREDIT_WINDOW: float = 45.0
const GUN_CONVERGENCE: float = 260.0
const AIM_ASSIST_CONE: float = deg_to_rad(3.5)
const BOUNDS_BLEND_DISTANCE: float = 300.0
## The most g the pilot is helped to pull when he is being turned back inside
## the battle area.
const BOUNDS_LOAD: float = 3.0
## How quickly a shove on the ground fades (1/s).
const KNOCK_DAMPING: float = 2.5

# status_flags bits (replicated so remote peers can drive cosmetics).
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
## Where the rudder is: -1 (nose left) .. +1 (nose right).
@export var rudder_state: float = 0.0
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
var arena_radius: float = 3200.0
var arena_ceiling: float = 9000.0

## Places a plane can land. Set by the match manager; with none, there is no
## ground to stand on and every surface is a crash.
var airfields: Array[Airfield] = []

var plane_data: PlaneData
## Giving the plane a new stat block gives it a new flight model to match.
var stats: PlaneStats: set = _set_stats
## What bullets and other planes collide with. Built from the model in _ready().
var hitboxes: PlaneHitboxes
var bullet_system: BulletSystem
## While true the trigger does nothing (pre-match countdown, post-match).
var weapons_locked: bool = false
## The enemy this plane's pilot is currently attacking (set by its controller).
## The HUD uses it to flag enemies that are hunting the player.
var current_target: PlaneActor

## The aeroplane itself: a rigid body with real mass, in real gravity, flown by
## the air on its surfaces and, when they are touching, by the ground under
## its wheels. It owns the plane's motion all the time.
var flight: FlightDynamics
## Attitude in radians, read off the plane's orientation every tick. yaw: 0
## faces -Z, positive turns left. pitch: positive is nose up. bank: positive is
## left wing down. In the air these are read-outs only: a plane that is
## looping or rolling goes through every attitude there is.
var yaw: float = 0.0
var pitch: float = 0.0
var bank: float = 0.0

## Sideslip last tick, for the pilot's feet.
var _last_slip: float = 0.0
## Angle of attack last tick, to feel how fast it is rising.
var _last_attack: float = 0.0
## How much the stick's sideways travel is working the rudder bar: 1 on the
## ground, fading to 0 just after leaving it.
var _stick_steers: float = 0.0
## Seconds until each gun station can fire again, and where each one's muzzle
## is (in this node's space; from the model).
var _gun_cooldowns: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _gun_muzzles: Array[Vector3] = []
var _was_firing: bool = false
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
var _service_time: float = 0.0
var _refit_timer: float = 0.0
var _service_start_load: float = 0.0
var _stranded_time: float = 0.0
## Collapsed undercarriage legs (GEAR_LEFT | GEAR_RIGHT) and a smashed propeller.
var _gear_broken: int = 0
var _prop_broken: bool = false
## Seconds since anything last touched the ground, and whether it has been
## properly in the air since (so that arriving counts as a touchdown).
var _air_time: float = INF
var _was_flying: bool = true
## The hardest any part met the ground in the arrival now going on, m/s, and
## how much of a crash's airframe damage (0..1) that arrival has already done.
var _arrival_sink: float = 0.0
var _crash_taken: float = 0.0
var _underside_scraped: bool = false
## How fast the plane was coming down just before this tick's step, m/s.
var _sink_before: float = 0.0
## Whether the plane was over an airfield last tick (to notice the edge).
var _over_field: bool = false
## How far the bottom of the fuselage is below the plane's centre (from the model).
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
	speed = stats.top_speed * CRUISE_SPEED_RATIO


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
		speed = stats.top_speed * CRUISE_SPEED_RATIO
	visual.build(plane_data, team, stats.fittings)
	hitboxes = PlaneHitboxes.from_visual(visual)
	_measure_undercarriage()
	_gun_muzzles = visual.gun_muzzles()
	input.set_multiplayer_authority(owner_peer_id)
	_read_angles_from_transform()
	flight.reset(global_transform.basis, forward() * speed)
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
	visual.set_part_damage(part_damage, velocity, has_flag(FLAG_BURNING))
	visual.set_controls(control_state, rudder_state)


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func forward() -> Vector3:
	return -global_transform.basis.z


func has_flag(flag: int) -> bool:
	return status_flags & flag != 0


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
## down, will leave the ground with the stick eased back.
func takeoff_speed() -> float:
	return stats.takeoff_speed()


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
## airfield right now.
func predicted_touchdown_sink() -> float:
	return maxf(-velocity.y, 0.0)


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


## Height of the lowest part of the plane that could touch (its wheels if they
## are down, otherwise its belly, propeller or a wingtip) above whatever is
## underneath: the airfield if the plane is over one, otherwise the sea.
func height_above_ground() -> float:
	var field: Airfield = airfield_at(global_position)
	var floor_y: float = field.surface_y() if field != null else 0.0
	return flight.clearance(global_position.y - floor_y)


## What the airspeed indicator reads, m/s: true airspeed scaled for the
## thinner air up high. The stall, take-off and approach speeds are all in
## these terms, at any height.
func indicated_speed() -> float:
	return flight.indicated_airspeed if is_multiplayer_authority() else speed


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


## Fraction of the lift needed to stay level that the wings could make at
## this speed. Below 1.0 the plane cannot hold itself up, whatever the pilot does.
func lift_ratio() -> float:
	return clampf(flight.available_load(flight.airspeed) * _wing_lift(), 0.0, 1.0)


## How hard the wings are pulling right now, in g: 1 in level flight, more in
## a turn or a pull-up, nothing in a free fall, negative when pushing over.
func load_factor() -> float:
	return 1.0 if is_on_ground() else flight.load_factor


## True when the plane is flying and its wing has stalled: the angle of attack
## is past where the air will follow it, so it has let go. That is a matter
## of angle, not of speed alone: pull hard enough and it happens fast. Easing
## the stick forward is what cures it.
func is_stalling() -> bool:
	return alive and not is_on_ground() and flight.stall > STALL_WARNING


## How much of the wing has stalled, 0 (flying) to 1 (all of it).
func stall_amount() -> float:
	return 0.0 if is_on_ground() else flight.stall


## Angle of attack as a share of the stalling angle: 1.0 is the edge.
func attack_ratio() -> float:
	if is_on_ground():
		return 0.0
	return (flight.alpha + FlightDynamics.WING_INCIDENCE) / maxf(flight.stall_alpha() + FlightDynamics.WING_INCIDENCE, 0.01)


## True when the plane is spinning: stalled and whirling round.
func is_spinning() -> bool:
	return is_stalling() and absf(flight.angular_velocity.y) > SPIN_YAW_RATE


## Sideslip in radians: positive when the air is coming from the right.
func sideslip() -> float:
	return 0.0 if is_on_ground() else flight.beta


## Rate of climb, m/s.
func climb_speed() -> float:
	return velocity.y


## Rough overall state for the AI, 1 = factory fresh, 0 = wreck: the weakest of
## lift, engine and pitch control.
func condition() -> float:
	var elevators: float = 0.5 * (part_health(Part.LEFT_ELEVATOR) + part_health(Part.RIGHT_ELEVATOR))
	return minf(_wing_lift(), minf(engine_power(), elevators))


## How far the landing flaps are down right now, 0..1.
func flap_deploy() -> float:
	return _flap_deploy


func is_hostile_to(other: PlaneActor) -> bool:
	return other != null and other != self and Teams.are_hostile(team, other.team)


func altitude() -> float:
	return global_position.y


## Indicated airspeed in miles an hour, as on the HUD.
func speed_mph() -> float:
	return indicated_speed() * MPH


## True airspeed in miles an hour: how fast it is really covering the sky.
func true_speed_mph() -> float:
	return speed * MPH


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


## Shows where a bullet went in (cosmetic). The bullet came from
## [param world_origin] along [param world_direction], as this plane saw it,
## and passed through [param parts_in_path] in that order. [param damage] is
## the round's, and sets how big a hole it makes.
func show_bullet_strike(world_origin: Vector3, world_direction: Vector3, parts_in_path: PackedInt32Array, damage: float) -> void:
	if visual == null:
		return
	var world_to_plane: Basis = hit_basis().transposed()
	visual.add_bullet_holes(world_to_plane * (world_origin - global_position), world_to_plane * world_direction, parts_in_path, damage)


## Orientation of the hit boxes in the world: the body's basis (which has no
## scale).
func hit_basis() -> Basis:
	return global_transform.basis


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


## A shove from a collision with another aircraft: the plane is pushed by
## [param push] (m/s) and its nose is kicked round by [param yaw_kick] rad/s.
## What happens next is up to the air, or the ground.
func knock(push: Vector3, yaw_kick: float) -> void:
	flight.wake()
	flight.velocity += push
	flight.angular_velocity.y += yaw_kick
	# A glancing blow rolls the plane as well as swinging it.
	flight.angular_velocity.z += yaw_kick * 0.6


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
	var field: Airfield = airfield_at(global_position) if parked else null
	_on_ground = field != null
	_ground_field = field
	_over_field = field != null
	_belly = false
	_engine_running = not _on_ground
	_engine_spool = 1.0 if _engine_running else 0.0
	throttle = 1.0 if _engine_running else 0.0
	input.throttle = throttle
	_gear_lever_down = _on_ground
	gear_deploy = 1.0 if _on_ground else 0.0
	_service_time = 0.0
	_service_start_load = 0.0
	_stranded_time = 0.0
	_gear_broken = 0
	_prop_broken = false
	_air_time = 0.0 if _on_ground else INF
	_was_flying = not _on_ground
	_arrival_sink = 0.0
	_crash_taken = 0.0
	_underside_scraped = false
	part_damage.fill(0.0)
	_gone_mask = 0
	fuel = 1.0
	control_state = Vector3.ZERO
	rudder_state = 0.0
	_flap_deploy = 1.0 if _on_ground else 0.0
	_burn_time = 0.0
	_burn_dps = 0.0
	_burn_source = null
	_last_attacker = null
	_last_attacker_age = INF
	_doomed_by = null
	_gun_cooldowns.fill(0.0)
	_was_firing = false
	_spawn_shield = GROUND_SHIELD_TIME if _on_ground else SPAWN_SHIELD_TIME
	current_target = null
	input.clear()
	visual.restore()
	alive = true
	_apply_condition()
	flight.aileron = 0.0
	flight.elevator = 0.0
	flight.rudder = 0.0
	if _on_ground:
		_stand_on_wheels(field)
	else:
		speed = stats.top_speed * CRUISE_SPEED_RATIO
		velocity = forward() * speed
		flight.altitude = global_position.y
		flight.ground_gap = INF
		flight.reset(global_transform.basis, velocity)
	_read_angles_from_transform()
	_refresh_status_flags()
	# Without this the interpolator would smear the plane across the map.
	reset_physics_interpolation()
	respawned.emit(self)


## Stands the plane on its three wheels where it is, pointing the way it is
## pointing, at rest. (A new plane wheeled out; a wreck jacked up.)
func _stand_on_wheels(field: Airfield) -> void:
	_set_contacts()
	var stand: Vector2 = flight.standing_attitude()
	var heading: float = global_transform.basis.get_euler().y
	global_transform = Transform3D(Basis.from_euler(Vector3(stand.x, heading, 0.0)), Vector3(global_position.x, field.surface_y() + stand.y, global_position.z))
	speed = 0.0
	velocity = Vector3.ZERO
	flight.altitude = global_position.y
	flight.reset(global_transform.basis, Vector3.ZERO)
	flight.ground_gap = stand.y
	flight.weight_on_ground = 1.0


## Moves the plane somewhere else as it is, damage and all, with no spawn
## protection, and flying straight along its nose at its present speed.
## For tests, cutscenes and editor tools.
func teleport(new_transform: Transform3D) -> void:
	_on_ground = false
	_belly = false
	_air_time = INF
	_was_flying = true
	_arrival_sink = 0.0
	_crash_taken = 0.0
	_underside_scraped = false
	_over_field = airfield_at(new_transform.origin) != null
	_spawn_shield = 0.0
	global_transform = new_transform.orthonormalized()
	velocity = forward() * speed
	_apply_condition()
	flight.altitude = global_position.y
	flight.ground_gap = INF
	flight.reset(global_transform.basis, velocity)
	_read_angles_from_transform()
	_refresh_status_flags()
	reset_physics_interpolation()


## Gives the plane a velocity (m/s, in the world) where it is, flying or not.
## For tests and editor tools: a plane dropped on to a runway, say.
func throw(new_velocity: Vector3) -> void:
	flight.wake()
	flight.velocity = new_velocity
	flight.angular_velocity = Vector3.ZERO
	velocity = new_velocity
	speed = new_velocity.length()


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
	_set_contacts()
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


func _set_stats(value: PlaneStats) -> void:
	stats = value
	if stats == null:
		return
	flight = stats.make_flight()
	if is_node_ready():
		_measure_undercarriage()
		_apply_condition()
		flight.altitude = global_position.y
		flight.reset(global_transform.basis, velocity)


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


func _integrate_flight(delta: float) -> void:
	var steer: Vector2 = input.steer.limit_length(1.0)
	_tick_engine(delta)
	_tick_gear(delta)
	_apply_condition()
	_fly(steer, delta)


## Tells the flight model what state the aeroplane is in: what is left of
## each surface, what the engine is giving, and where the levers are. Nothing
## here says how the plane should then behave. A missing wing panel makes no
## lift, a dead elevator moves no air, and the rest follows.
func _apply_condition() -> void:
	var fuselage_damage: float = part_damage[Part.FUSELAGE]
	var cables: float = 1.0 - FUSELAGE_FEEL_LOSS * fuselage_damage
	flight.panel_lift[0] = _panel_lift(Part.LEFT_WING)
	flight.panel_lift[1] = _panel_lift(Part.RIGHT_WING)
	flight.panel_lift[2] = _panel_lift(Part.LEFT_WINGTIP)
	flight.panel_lift[3] = _panel_lift(Part.RIGHT_WINGTIP)
	flight.aileron_health = Vector2(part_health(Part.LEFT_AILERON), part_health(Part.RIGHT_AILERON)) * cables
	flight.flap_health = Vector2(part_health(Part.LEFT_FLAP), part_health(Part.RIGHT_FLAP))
	var tail: float = 0.0 if is_part_gone(Part.TAIL) else lerpf(1.0, HOLED_TAIL_GRIP, part_damage[Part.TAIL])
	flight.tailplane = Vector2(tail, tail)
	flight.elevator_health = Vector2(part_health(Part.LEFT_ELEVATOR), part_health(Part.RIGHT_ELEVATOR)) * cables
	flight.fin = 0.0 if is_part_gone(Part.FIN) else lerpf(1.0, HOLED_TAIL_GRIP, part_damage[Part.FIN])
	flight.rudder_health = part_health(Part.RUDDER) * cables
	flight.engine_output = engine_power() * _engine_spool
	flight.engine_turning = _engine_running and not _prop_broken
	flight.throttle = throttle
	flight.flaps = _flap_deploy
	flight.gear = gear_deploy
	var ragged: float = HOLE_DRAG * (fuselage_damage + (1.0 if is_part_gone(Part.TAIL) else part_damage[Part.TAIL]))
	for panel: Part in [Part.LEFT_WING, Part.RIGHT_WING, Part.LEFT_WINGTIP, Part.RIGHT_WINGTIP]:
		ragged += STUB_DRAG if is_part_gone(panel) else HOLE_DRAG * part_damage[panel]
	flight.damage_drag = ragged


## One tick, in the air or on the ground: it is the same aeroplane and the
## same physics either way. The pilot moves the controls, the actor says where
## the ground is and how thick the air is, and FlightDynamics does the rest.
func _fly(steer: Vector2, delta: float) -> void:
	# Fuel: a holed fuselage leaks, a destroyed one dumps the lot.
	var fuselage_damage: float = part_damage[Part.FUSELAGE]
	if fuel > 0.0 and fuselage_damage > 0.0 and not _on_ground:
		var leak: float = FUEL_DUMP_RATE if fuselage_damage >= 1.0 else FUEL_LEAK_RATE * fuselage_damage * fuselage_damage
		leak *= stats.fuel_leak  # Self-sealing tanks.
		fuel = maxf(fuel - leak * delta, 0.0)

	# The landing flaps are on the same lever as the wheels: they come down
	# with them and go up with them, over the same two seconds. Raising them
	# takes lift away, so cleaning up too slow lets the plane sink. They are
	# for landing and nothing else: these were not combat flaps, and their
	# drag would take the speed out of every turn.
	_flap_deploy = move_toward(_flap_deploy, gear_deploy, FLAP_SPEED * delta)
	flight.flaps = _flap_deploy

	# Where it is: how thick the air, and what ground (if any) is under it.
	var field: Airfield = airfield_at(global_position)
	flight.altitude = global_position.y
	if field != null:
		if not _over_field and not _cross_the_lip(field):
			return
		flight.ground_gap = global_position.y - field.surface_y()
		flight.rolling_drag = ROLL_RUNWAY if field.is_on_runway(global_position) else ROLL_GRASS
	else:
		flight.ground_gap = INF
	_over_field = field != null
	_ground_field = field
	_set_contacts()
	flight.brake = 1.0 if input.throttle <= BRAKE_THROTTLE else 0.0
	flight.ground_effect = _ground_closeness()

	var wanted: Vector3 = _pilot_controls(steer, delta)
	flight.aileron = move_toward(flight.aileron, wanted.x, CONTROL_SLEW * delta)
	flight.elevator = move_toward(flight.elevator, wanted.y, CONTROL_SLEW * delta)
	flight.rudder = move_toward(flight.rudder, wanted.z, CONTROL_SLEW * delta)
	flight.update_trim(delta)
	_sink_before = maxf(-flight.velocity.y, 0.0)
	flight.step(delta)

	velocity = flight.velocity
	speed = flight.airspeed
	global_transform = Transform3D(flight.basis, global_position)
	_read_angles_from_transform()
	control_state = Vector3(flight.aileron, flight.elevator, _flap_deploy)
	rudder_state = flight.rudder
	_read_the_ground(delta)
	if not alive:
		return
	var collision: KinematicCollision3D = move_and_collide(flight.displacement)
	if collision != null:
		if _on_ground and speed <= GROUND_CRASH_SPEED:
			# Taxied into a hangar: it stops there.
			flight.velocity = Vector3.ZERO
			flight.angular_velocity = Vector3.ZERO
		else:
			# Hit the sea, a cliff or a building. Apart from flying into the
			# runway this is the only way a plane dies on its own; credit
			# whoever put it in this state.
			_die(recent_attacker())
			return
	if _on_ground and field != null:
		_tick_service(field, delta)
		if field.team != team and speed < SERVICE_MAX_SPEED:
			_stranded_time += delta
			if _stranded_time >= STRANDED_TIME:
				_die(recent_attacker())
		else:
			_stranded_time = 0.0


## Where the pilot puts the controls this tick: x = aileron (+ rolls right),
## y = elevator (+ pulls the nose up), z = rudder (+ swings the nose right).
## All are measured from the trimmed position (see FlightDynamics.update_trim).
##
## There is one stick for a thumb. Sideways it is always the ailerons; while
## any wheel is on the ground it works the rudder bar as well (which is also
## the tail wheel and, with the brakes on, which wheel is braked harder), and
## the ailerons only partly. So holding the stick against the swing on the
## take-off run holds the wing down against the engine's torque too, which is
## what a pilot's hands and feet would be doing. The rudder part fades out
## over the moment after the wheels leave the ground. The pedals are always
## the rudder.
func _pilot_controls(steer: Vector2, delta: float) -> Vector3:
	var touching: float = 1.0 if flight.weight_on_ground > ON_GROUND_WEIGHT else 0.0
	_stick_steers = move_toward(_stick_steers, touching, delta / (STICK_STEERS_FADE if touching < _stick_steers else 0.1))
	var on_wheels: float = _stick_steers
	var roll_stick: float = steer.x * lerpf(1.0, GROUND_AILERON_SHARE, on_wheels)
	var pitch_stick: float = steer.y
	var feet: float = clampf(input.rudder + steer.x * on_wheels, -1.0, 1.0)
	# Leaving the battle area, the pilot is turned back toward it.
	var urgency: float = _bounds_urgency() * (1.0 - on_wheels)
	if urgency > 0.0:
		var help: Vector3 = FlightPilot.fly_toward(self, _bounds_direction(), BOUNDS_LOAD)
		roll_stick = lerpf(roll_stick, help.x, urgency)
		pitch_stick = lerpf(pitch_stick, help.y, urgency)
	# Nobody can hold the stick against eight times their own weight.
	var attack_rate: float = (flight.alpha - _last_attack) / maxf(delta, 0.001)
	_last_attack = flight.alpha
	if pitch_stick > 0.0:
		pitch_stick *= 1.0 - smoothstep(G_EASE_START, G_EASE_END, flight.load_factor)
		# And a pilot pulls to the buffet, not through it. Crossing the
		# controls (stick back, a boot of rudder) is how he asks for more: a
		# stall, a flick, a spin.
		if on_wheels < 1.0:
			var edge: float = lerpf(flight.best_alpha(), flight.stall_alpha() * CROSSED_CONTROLS_ATTACK, smoothstep(0.3, 0.9, absf(input.rudder)))
			pitch_stick = FlightPilot.pull_to_the_buffet(flight, pitch_stick, edge, attack_rate)
	elif pitch_stick < 0.0:
		pitch_stick *= 1.0 - smoothstep(-NEGATIVE_G_EASE_START, -NEGATIVE_G_EASE_END, -flight.load_factor)
	# Feet, in the air: push the ball back to the middle, and check its swing.
	var slip_rate: float = (flight.beta - _last_slip) / maxf(delta, 0.001)
	_last_slip = flight.beta
	if absf(input.rudder) < 0.05 and on_wheels < 1.0:
		feet += (1.0 - on_wheels) * clampf(flight.beta * COORDINATION_GAIN + slip_rate * COORDINATION_DAMPING, -1.0, 1.0) * (1.0 - STALLED_FEET_LOSS * clampf(flight.stall * 2.0, 0.0, 1.0))
	return Vector3(clampf(roll_stick, -1.0, 1.0), clampf(pitch_stick, -1.0, 1.0), feet)


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


## Reads off the model where the plane meets the ground (wheels, belly,
## propeller, wingtips, tail) and gives that to the flight model.
func _measure_undercarriage() -> void:
	if visual == null or hitboxes == null or flight == null:
		return
	_belly_height = maxf(visual.belly_depth(), 0.5)
	var main_wheel: Vector3 = Vector3(-_belly_height, -DEFAULT_WHEEL_HEIGHT, -_belly_height)
	var tail_wheel: Vector3 = Vector3(0.0, -(DEFAULT_WHEEL_HEIGHT - 1.4), _belly_height * 2.3)
	var contacts: Array[Vector3] = visual.undercarriage_contacts()
	if contacts.size() >= 2:
		main_wheel = contacts[0]
		tail_wheel = contacts[1]
	var engine: AABB = _part_bounds(Part.ENGINE)
	var wingtip: AABB = _part_bounds(Part.LEFT_WINGTIP)
	var tail: AABB = _part_bounds(Part.TAIL)
	# The propeller's disc reaches a little below the cowling.
	var nose: Vector3 = Vector3(0.0, minf(engine.position.y, -_belly_height) - PROP_BELOW_COWLING, engine.position.z)
	var tip: Vector3 = Vector3(wingtip.position.x, wingtip.position.y, wingtip.get_center().z)
	var tail_bottom: Vector3 = Vector3(0.0, tail.position.y, tail.end.z)
	flight.set_undercarriage(main_wheel, tail_wheel, _belly_height, nose, tip, tail_bottom)
	_set_contacts()


## The whole extent of a part (a part can be several boxes), in the plane's axes.
func _part_bounds(part: Part) -> AABB:
	var bounds: AABB = AABB()
	var found: bool = false
	for index: int in range(hitboxes.solid_boxes.size()):
		if hitboxes.parts[index] != part:
			continue
		bounds = hitboxes.solid_boxes[index] if not found else bounds.merge(hitboxes.solid_boxes[index])
		found = true
	if not found:
		bounds = AABB(Vector3(-0.5, -_belly_height, -0.5), Vector3.ONE)
	return bounds


## Tells the flight model which wheels and hard points are there to touch
## the ground: a wheel that is up, broken off or gone with its wing is not.
func _set_contacts() -> void:
	if flight.contact_enabled.size() < FlightDynamics.CONTACT_COUNT:
		return
	# (A plane lying on its belly has no wheels under it until it is jacked up.)
	var wheels_down: bool = gear_deploy >= 0.98 and not _belly
	var left_wing: bool = not is_part_gone(Part.LEFT_WING)
	var right_wing: bool = not is_part_gone(Part.RIGHT_WING)
	var tail: bool = not is_part_gone(Part.TAIL)
	flight.contact_enabled[FlightDynamics.Contact.LEFT_WHEEL] = 1 if wheels_down and left_wing and _gear_broken & GEAR_LEFT == 0 else 0
	flight.contact_enabled[FlightDynamics.Contact.RIGHT_WHEEL] = 1 if wheels_down and right_wing and _gear_broken & GEAR_RIGHT == 0 else 0
	flight.contact_enabled[FlightDynamics.Contact.TAIL_WHEEL] = 1 if tail else 0
	flight.contact_enabled[FlightDynamics.Contact.LEFT_TIP] = 1 if left_wing else 0
	flight.contact_enabled[FlightDynamics.Contact.RIGHT_TIP] = 1 if right_wing else 0
	flight.contact_enabled[FlightDynamics.Contact.TAIL] = 1 if tail else 0


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


## How close the lowest part of the plane is to an airfield's surface: 0 at
## GROUND_EFFECT_HEIGHT or more (and anywhere that is not over an airfield),
## 1 touching it.
func _ground_closeness() -> float:
	if not is_finite(flight.ground_gap):
		return 0.0
	return clampf(1.0 - flight.clearance(flight.ground_gap) / GROUND_EFFECT_HEIGHT, 0.0, 1.0)


# ---------------------------------------------------------------------------
# On the ground
# ---------------------------------------------------------------------------

## The plane has just come in over the edge of an airfield. If it is above
## the surface that is all there is to it. A little under, it has caught the
## lip with whatever is lowest: it is lifted on to the top with its
## undercarriage wrecked. Well under, it has flown into the cliff. Returns
## false if the plane was destroyed.
func _cross_the_lip(field: Airfield) -> bool:
	var gap: float = global_position.y - field.surface_y()
	var under: float = -flight.clearance(gap)
	if under <= 0.05:
		return true
	if under > CLIFF_DEPTH:
		_die(recent_attacker())
		return false
	global_position.y += under
	if under > LIP_DEPTH:
		_break_gear(GEAR_LEFT | GEAR_RIGHT)
		_impact_damage(Part.FUSELAGE, BELLY_FUSELAGE_DAMAGE)
	flight.velocity.y = maxf(flight.velocity.y, 0.0)
	return true


## Reads off what the ground did to the plane this tick: which wheels and
## hard points met it and how fast, what that broke, and whether the plane
## is now on the ground or back in the air.
func _read_the_ground(delta: float) -> void:
	var hardest: float = 0.0
	for index: int in range(FlightDynamics.CONTACT_COUNT):
		var hit: float = flight.contact_impact[index]
		if hit <= 0.0:
			continue
		flight.contact_impact[index] = 0.0
		hardest = maxf(hardest, hit)
		_ground_strike(index as FlightDynamics.Contact, hit)
		if not alive:
			return
	_arrival_sink = maxf(_arrival_sink, hardest)
	if flight.weight_on_ground > ON_GROUND_WEIGHT:
		_air_time = 0.0
		# A propeller that reaches the ground is finished, whatever the speed.
		if flight.is_touching(FlightDynamics.Contact.NOSE):
			_break_propeller()
		# Metal dragged along the ground wears away.
		var ground_speed: float = Vector2(velocity.x, velocity.z).length()
		if ground_speed > 3.0:
			var wear: float = WINGTIP_SCRAPE_RATE * delta * ground_speed / 30.0
			if flight.is_touching(FlightDynamics.Contact.LEFT_TIP):
				_scrape(Part.LEFT_WINGTIP, wear)
			if flight.is_touching(FlightDynamics.Contact.RIGHT_TIP):
				_scrape(Part.RIGHT_WINGTIP, wear)
		# Once it is lying on its belly it stays there until it is jacked up.
		if not gear_usable():
			_belly = true
		if not _on_ground:
			_on_ground = true
			_service_time = 0.0
			if _was_flying:
				_was_flying = false
				touched_down.emit(self, _arrival_sink, not _belly)
		return
	_air_time += delta
	if _air_time < AIRBORNE_AFTER:
		return  # A hop. It may yet come down again.
	if _on_ground:
		_on_ground = false
		_belly = false
		_service_time = 0.0
		# Protection for a freshly wheeled-out plane ends once it is flying.
		_spawn_shield = minf(_spawn_shield, SPAWN_SHIELD_TIME)
		lifted_off.emit(self)
	_was_flying = true
	_arrival_sink = 0.0
	_crash_taken = 0.0
	_underside_scraped = false


## One wheel or hard point has just met the ground, coming down at
## [param hit] m/s. What that does depends on what it was and how hard.
##
## Gently, on the wheels, is a landing. Rougher than that and the aeroplane
## pays for it, a piece at a time: strained wings, a collapsed undercarriage
## leg (it then drops on to that wingtip and the propeller), a scraped or
## torn-off wingtip, a wrecked airframe. The pilot walks away from all of
## those, and at home the ground crew can mend them. Only flying into the
## ground (a dive, on its side, or upside down) destroys the plane outright.
func _ground_strike(contact: FlightDynamics.Contact, hit: float) -> void:
	if _was_flying and not _on_ground:
		# First touch of an arrival: was it a landing at all?
		if hit > FATAL_SINK or -pitch > FATAL_NOSE_DOWN or absf(bank) > FATAL_BANK:
			_die(recent_attacker())
			return
	var firm_sink: float = firm_landing_sink()
	var collapse_sink: float = gear_collapse_sink()
	match contact:
		FlightDynamics.Contact.LEFT_WHEEL, FlightDynamics.Contact.RIGHT_WHEEL:
			var left: bool = contact == FlightDynamics.Contact.LEFT_WHEEL
			if hit > firm_sink:
				# A heavy arrival strains whatever the leg is bolted to.
				var strain: float = clampf((hit - firm_sink) / (collapse_sink - firm_sink), 0.0, 1.0)
				_impact_damage(Part.LEFT_WING if left else Part.RIGHT_WING, FIRM_LANDING_WING_DAMAGE * strain)
				_impact_damage(Part.FUSELAGE, FIRM_LANDING_FUSELAGE_DAMAGE * strain * 0.5)
			if hit > collapse_sink:
				_break_gear(GEAR_LEFT if left else GEAR_RIGHT)
		FlightDynamics.Contact.TAIL_WHEEL:
			if hit > collapse_sink:
				_impact_damage(Part.TAIL, CRASH_TAIL_DAMAGE * clampf(hit / FATAL_SINK, 0.0, 1.0))
		FlightDynamics.Contact.BELLY:
			_scrape_underside(hit)
		FlightDynamics.Contact.NOSE:
			_break_propeller()
			if not gear_usable():
				# No wheels under it: the cowling is the underside too.
				_scrape_underside(hit)
		FlightDynamics.Contact.LEFT_TIP, FlightDynamics.Contact.RIGHT_TIP:
			var tip: Part = Part.LEFT_WINGTIP if contact == FlightDynamics.Contact.LEFT_TIP else Part.RIGHT_WINGTIP
			if hit > WINGTIP_TORN_SPEED or absf(bank) > WINGTIP_TORN_BANK:
				_impact_damage(tip, 1.0)
			else:
				_impact_damage(tip, WINGTIP_STRIKE_DAMAGE * clampf(hit / WINGTIP_TORN_SPEED, 0.25, 1.0))
		FlightDynamics.Contact.TAIL:
			_impact_damage(Part.TAIL, CRASH_TAIL_DAMAGE * clampf(hit / GEAR_COLLAPSE_SINK, 0.1, 1.0))
	if contact >= FlightDynamics.Contact.BELLY and hit > GEAR_COLLAPSE_SINK:
		# Airframe on the ground at a speed no undercarriage would have taken.
		# It is how fast the whole aeroplane was coming down that wrecks it,
		# not how fast one corner of it was whipped into the ground. (Several
		# hard points arrive in one crash; the airframe pays once.)
		var crash: float = clampf((minf(hit, _sink_before) - GEAR_COLLAPSE_SINK) / (FATAL_SINK - GEAR_COLLAPSE_SINK), 0.0, 1.0) - _crash_taken
		if crash > 0.0:
			_crash_taken += crash
			_impact_damage(Part.LEFT_WING, CRASH_WING_DAMAGE * crash)
			_impact_damage(Part.RIGHT_WING, CRASH_WING_DAMAGE * crash)
			_impact_damage(Part.FUSELAGE, CRASH_FUSELAGE_DAMAGE * crash)
			_impact_damage(Part.ENGINE, CRASH_ENGINE_DAMAGE * crash)
			_impact_damage(Part.TAIL, CRASH_TAIL_DAMAGE * crash)


## The underside has met the ground with no wheels in between. Once per arrival.
func _scrape_underside(hit: float) -> void:
	if _underside_scraped:
		return
	_underside_scraped = true
	_impact_damage(Part.FUSELAGE, BELLY_FUSELAGE_DAMAGE * clampf(hit / 3.0, 0.4, 1.0))


## Wear on a part being dragged along the ground (no alert for every tick of it).
func _scrape(part: Part, share: float) -> void:
	if share <= 0.0 or is_part_gone(part):
		return
	_damage_part(part, share * maxf(stats.max_hp * PART_STRENGTH[part], 1.0), null)


## Collapses undercarriage legs ([param legs] is GEAR_LEFT, GEAR_RIGHT or both).
func _break_gear(legs: int) -> void:
	var newly: int = legs & ~_gear_broken
	if newly == 0:
		return
	_gear_broken |= newly
	_set_contacts()
	damaged.emit(self, stats.max_hp * 0.1, null)


## The propeller has hit the ground. The engine is unhurt but can do nothing.
func _break_propeller() -> void:
	if _prop_broken:
		return
	_prop_broken = true
	_engine_running = false
	damaged.emit(self, stats.max_hp * 0.1, null)


## Damage from hitting the ground: [param share] of the part's strength.
## Spawn protection does not soften the ground.
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
	# (A new propeller is no use to a plane still lying on its nose.)
	if _refit_timer <= 0.0 and _prop_broken and not _belly:
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
			_stand_on_wheels(field)
	if not needs_service():
		_doomed_by = null
		_last_attacker = null
		_last_attacker_age = INF
		_service_start_load = 0.0
		serviced.emit(self)


## Soft arena limits: 0 inside the battle area, rising to 1 well past its edge
## or above its ceiling. Works for bots and humans.
func _bounds_urgency() -> float:
	var offset: Vector3 = global_position - arena_center
	offset.y = 0.0
	var outside: float = clampf((offset.length() - arena_radius) / BOUNDS_BLEND_DISTANCE, 0.0, 1.0)
	var above: float = clampf((global_position.y - arena_ceiling) / BOUNDS_BLEND_DISTANCE, 0.0, 1.0)
	return maxf(outside, above)


## Which way a plane that has left the battle area is turned: back toward the
## middle, and down if it is above the ceiling.
func _bounds_direction() -> Vector3:
	var offset: Vector3 = global_position - arena_center
	offset.y = 0.0
	var direction: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if offset.length() > arena_radius:
		direction = -offset
	if direction.length() < 0.01:
		direction = Vector3.FORWARD
	direction = direction.normalized()
	if global_position.y > arena_ceiling:
		direction.y = -0.35
	return direction.normalized()


# ---------------------------------------------------------------------------
# Weapons
# ---------------------------------------------------------------------------

## Every fitted gun fires on its own clock, at its own rate. A plane with one
## gun fitted fires one gun.
func _tick_weapons(delta: float) -> void:
	for station: int in range(_gun_cooldowns.size()):
		_gun_cooldowns[station] = maxf(_gun_cooldowns[station] - delta, 0.0)
	var firing: bool = input.firing and not weapons_locked and bullet_system != null and not _on_ground
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
	_spawn_shield = maxf(_spawn_shield - delta, 0.0)
	_last_attacker_age += delta


func _refresh_status_flags() -> void:
	var flags: int = 0
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
	var angles: Vector3 = global_transform.basis.get_euler()
	pitch = angles.x
	yaw = angles.y
	bank = angles.z
