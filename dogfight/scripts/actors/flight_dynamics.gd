class_name FlightDynamics
extends RefCounted
## Six-degree-of-freedom flight model for one aeroplane: a rigid body with real
## mass and inertia, in real gravity, pushed about by the air on each of its
## surfaces and by its propeller.
##
## Nothing here is scripted. There is no "stall rule", no "spin mode" and no
## turn rate: every tick each surface (four wing panels, two tailplane halves,
## the fin and the fuselage) works out the air it meets, including what the
## plane's own rotation adds, and from that its angle of attack, lift and
## drag. The sum of those forces, where they act, moves and turns the plane.
## What a real aeroplane does then follows by itself:
##  - lift goes with the square of airspeed and with angle of attack, up to
##    the stalling angle; beyond it lift collapses and drag soars;
##  - a wing that stalls before the other drops, and with yaw the plane
##    autorotates: a spin. Unstalling it (stick forward, opposite rudder)
##    is the only way out;
##  - the tail keeps the nose pointing into the airflow; lose it and it will not;
##  - turning is banking and pulling; loops and rolls are just more of the same;
##  - a missing wing panel simply makes no lift, and the plane rolls.
##
## The propeller is modelled too, and it is not polite:
##  - thrust falls off with speed (power = thrust x speed), from a static
##    limit, so there is far more push at low speed than at high;
##  - torque: the airframe tries to roll opposite to the propeller, most
##    at low speed and high power;
##  - slipstream: faster air over the tail and inner wings under power, and
##    its spiral pushes the fin sideways, swinging the nose;
##  - P-factor: at a high angle of attack the thrust moves off-centre, yawing;
##  - gyroscopic precession: pitching makes it yaw and yawing makes it pitch.
## These planes all have propellers turning clockwise seen from the cockpit,
## so the effects pull to the left.
##
## The air is the standard atmosphere, and it thins with height: every force
## above goes with its density, so up high the plane needs more true airspeed
## to make the same lift, the propeller has less to bite, and above the
## supercharger's critical altitude the engine fades. The speed of sound falls
## with the cold too, and near it drag climbs steeply and the controls go
## heavy.
##
## The ground is part of it as well. Each wheel is a sprung, damped leg with a
## tyre that grips sideways, rolls forward and can be braked; the belly, nose,
## wingtips and tail are hard points that scrape. Nothing tells the plane it
## is "taking off" or "landing": it leaves the ground when the wings lift it
## and comes back when a wheel touches, and it can bounce, swing, ground-loop,
## tip on to a wingtip or stand on its nose on the way.
##
## Axes are Godot's: +X is the right wing, +Y is up, -Z is the nose.
## Units are SI: metres, kilograms, seconds, newtons, radians.

const GRAVITY: float = 9.81

# --- The air: International Standard Atmosphere, troposphere ---------------------
## Sea-level density (kg/m^3) and temperature (K), and how fast it cools with
## height (K per metre).
const AIR_DENSITY: float = 1.225
const SEA_LEVEL_TEMPERATURE: float = 288.15
const LAPSE_RATE: float = 0.0065
## Density goes with temperature ratio to this power.
const DENSITY_EXPONENT: float = 4.2559
## Speed of sound is sqrt(this x temperature): 340 m/s at sea level.
const SOUND_SPEED_FACTOR: float = 401.87
## Above its critical altitude an engine loses power a little faster than the
## air thins (Gagg and Farrar): share = 1.132 x density ratio - 0.132.
const POWER_LAPSE: float = 0.132
## Compressibility: past this Mach number drag rises with the square of the
## excess (doubling about 0.12 beyond it), and the controls lose their grip.
const CRITICAL_MACH: float = 0.68
const MACH_DRAG: float = 70.0
const MACH_CONTROL_LOSS: float = 40.0

# --- Aerofoil behaviour -------------------------------------------------------
## Lift-curve slopes (per radian) of the wing, tailplane and fin.
const WING_LIFT_SLOPE: float = 4.5
const TAIL_LIFT_SLOPE: float = 3.6
const FIN_LIFT_SLOPE: float = 3.0
## The most lift coefficient the tail surfaces make before they stall.
const TAIL_CL_MAX: float = 1.15
## How abruptly a surface stalls: the transition takes about this many
## radians of angle of attack either side of the stalling angle.
const STALL_SHARPNESS: float = 0.035
## Fully stalled, a surface behaves like a flat plate: the air simply pushes
## square on to it, this hard (normal-force coefficient at 90 degrees). Both
## the lift and the drag left over are that one push, seen from the airflow.
const FLAT_PLATE_NORMAL: float = 1.9
## Share of the wing's angle of attack that its downwash takes off the tail's.
const DOWNWASH: float = 0.38

# --- Geometry, as shares of the wing ---------------------------------------------
## Each half-wing is two panels: inner (to 57% of the half-span) and tip.
const INNER_PANEL_AREA: float = 0.6
const INNER_PANEL_ARM: float = 0.29
const TIP_PANEL_ARM: float = 0.78
const WING_DIHEDRAL: float = deg_to_rad(5.5)
## The wing is set at this angle to the fuselage, and its section is cambered
## by about as much again.
const WING_INCIDENCE: float = deg_to_rad(4.0)
## The wing's lift acts this share of the span behind the centre of gravity:
## a little ahead of it, in fact, as on the real aeroplanes. On its own a wing
## like that is unstable, and its cambered section is forever trying to tuck
## the nose under (WING_PITCHING, a moment coefficient on the mean chord). The
## tail is what holds it all straight. Shoot the tail off and nothing does.
const WING_AFT: float = -0.008
const WING_PITCHING: float = -0.035
const TAILPLANE_AREA: float = 0.17
const FIN_AREA: float = 0.085
const TAIL_ARM: float = 0.44
const FIN_HEIGHT: float = 0.06
const PROP_RADIUS: float = 0.137
## The tailplane's setting to the fuselage. It sits in the wing's downwash,
## so in cruise it still carries a small download.
const TAIL_INCIDENCE: float = deg_to_rad(1.6)
## The tips are twisted nose-down by this much (washout), so the wing stalls
## from the root outward and the ailerons keep working into the stall.
const TIP_WASHOUT: float = deg_to_rad(2.0)

# --- Controls -----------------------------------------------------------------------
## How far each surface moves at full stick, and how much of that it is worth
## as a change in its panel's angle of attack.
const AILERON_TRAVEL: float = deg_to_rad(17.0)
const AILERON_POWER: float = 0.4
const ELEVATOR_TRAVEL: float = deg_to_rad(26.0)
const ELEVATOR_POWER: float = 0.5
const RUDDER_TRAVEL: float = deg_to_rad(26.0)
const RUDDER_POWER: float = 0.6
## Flaps fully down: extra angle of attack, extra maximum lift, extra drag.
const FLAP_ANGLE: float = deg_to_rad(10.0)
const FLAP_CL_MAX: float = 0.75
const FLAP_DRAG: float = 0.09
## Wheels down add this to the drag coefficient (of wing area).
const GEAR_DRAG: float = 0.018
## The stick gets heavy with speed: at this airspeed (m/s) a pilot can hold
## about 70% of full aileron, and less beyond.
const AILERON_HEAVY_SPEED: float = 135.0
const ELEVATOR_HEAVY_SPEED: float = 90.0
const RUDDER_HEAVY_SPEED: float = 150.0

# --- Propeller ------------------------------------------------------------------------
## Share of shaft power the propeller turns into thrust at speed.
const PROP_EFFICIENCY: float = 0.8
## The exhaust stacks point backwards and the hot gas is a small jet: newtons
## of thrust per watt of shaft power (about 150 lb from a Merlin's ejector
## exhausts). Little beside the propeller at take-off, a tenth of the push at
## top speed, where the propeller's thrust has fallen away.
const EXHAUST_THRUST: float = 0.00065
## Share of the ideal (momentum-theory) static thrust it actually makes.
const STATIC_THRUST_SHARE: float = 0.5
## Propeller speed at full power (rad/s; about 1,250 rpm) and its inertia as a
## share of mass x radius^2.
const PROP_RATE: float = 131.0
const PROP_INERTIA_SHARE: float = 0.0032
## How much of the slipstream's extra speed reaches the tail and inner wing.
const SLIPSTREAM_AT_TAIL: float = 0.75
const SLIPSTREAM_AT_INNER_WING: float = 0.1
## Sideways speed the slipstream's spiral gives the air at the fin, as a share
## of the slipstream's extra speed.
const SLIPSTREAM_SPIRAL: float = 0.07
## Share of the propeller's torque that the wing and tail take back out of the
## spinning slipstream.
const SWIRL_RECOVERY: float = 0.35
## How far off-centre (in propeller radii) the thrust moves per radian of
## angle of attack.
const P_FACTOR: float = 0.25
## Drag of a propeller windmilling on a stopped engine, as a coefficient on
## its disc area.
const WINDMILL_DRAG: float = 0.03
## The stall break sits this many "sharpnesses" past the angle where the
## straight part of the lift curve would reach its peak.
const STALL_OFFSET: float = 2.2
# --- On the ground --------------------------------------------------------------------
enum Contact { LEFT_WHEEL, RIGHT_WHEEL, TAIL_WHEEL, BELLY, NOSE, LEFT_TIP, RIGHT_TIP, TAIL }
const CONTACT_COUNT: int = 8
## How far each main leg and the tail wheel are squashed by the standing
## plane's weight (m), and how well they are damped (share of critical).
const MAIN_LEG_SAG: float = 0.2
const TAIL_LEG_SAG: float = 0.08
const LEG_DAMPING: float = 0.5
## An oleo leg lets go far more slowly than it gives: damping on the way back
## out is this many times stronger, which is what stops a plane bouncing.
const LEG_REBOUND: float = 3.0
## Past this much more squash a leg is on its stops: it stiffens this many times.
const LEG_TRAVEL: float = 0.22
const BOTTOMED_STIFFENING: float = 6.0
## Hard points (belly, nose, wingtips, tail): how stiff the airframe is on the
## ground (natural frequency, rad/s) and how dead it lands (share of critical).
const HARD_POINT_RATE: float = 26.0
const HARD_POINT_DAMPING: float = 0.7
## Nothing is ever pushed further into the ground than this (m): beyond it the
## plane is simply stopped.
const DEEPEST_DENT: float = 0.3
## Tyres: sideways grip as a share of the load on the wheel, reached at this
## slip angle (or, crawling, at this sideways speed in m/s).
const TYRE_SIDE_GRIP: float = 0.6
const TYRE_SLIP_PEAK: float = deg_to_rad(9.0)
const TYRE_CRAWL_SPEED: float = 0.6
## Full braking, as a share of the load on the wheel, and how much of it the
## rudder bar moves from one wheel to the other.
const BRAKE_GRIP: float = 0.32
const BRAKE_STEER: float = 0.7
## Below this speed (m/s) rolling and braking forces fade, so a wheel stops
## instead of shuddering to and fro.
const WHEEL_STOP_SPEED: float = 0.35
## Metal on the ground: grip as a share of load.
const SKID_GRIP: float = 0.55
## The tail wheel turns with the rudder bar, this far.
const TAIL_WHEEL_STEER: float = deg_to_rad(24.0)
## A plane standing still under brakes with nothing moving goes to sleep
## after this long (s), and stays put until something pushes it.
const SLEEP_SPEED: float = 0.06
const SLEEP_SPIN: float = 0.03
const SLEEP_TIME: float = 0.6

## Trim tabs: how often the pilot's trimming is worked out (s), and how fast
## the elevator and the aileron/rudder tabs follow (time constants, s).
const TRIM_INTERVAL: float = 0.1
const SLOWEST_TRIM: float = 1.3
const ELEVATOR_TRIM_TIME: float = 0.35
const LATERAL_TRIM_TIME: float = 2.5

# --- Airframe: set once by configure() ----------------------------------------------
var mass: float = 3000.0
var wing_area: float = 23.0
var wing_span: float = 12.0
## Full shaft power, watts.
var power: float = 770000.0
## Drag coefficient of the clean aeroplane at zero lift.
var cd0: float = 0.024
## The most lift coefficient the clean wing makes.
var cl_max: float = 1.45
## Multipliers a loadout applies: static thrust (the propeller's bite at low
## speed) and aileron power (roll rate).
var static_thrust_factor: float = 1.0
var roll_factor: float = 1.0
## Moments of inertia about the pitch (X), yaw (Y) and roll (Z) axes.
var inertia: Vector3 = Vector3(10000.0, 17000.0, 7000.0)
## Height (m above sea level) up to which the supercharger holds the boost,
## and the share of sea-level power the engine still gives there. Driving
## the supercharger hard enough to hold the pressure that high costs power,
## so the share falls steadily on the way up; above the critical altitude
## the boost itself falls away with the air.
var critical_altitude: float = 3500.0
var altitude_power: float = 1.0

# --- State: integrated by step() -------------------------------------------------------
## Velocity in the world, m/s.
var velocity: Vector3 = Vector3.ZERO
## Orientation in the world.
var basis: Basis = Basis.IDENTITY
## Rotation rate about the plane's own axes, rad/s: x pitches the nose up,
## y yaws it left, z rolls the left wing down.
var angular_velocity: Vector3 = Vector3.ZERO

# --- Where it is: set by the actor before each step -------------------------------------
## Height above sea level, metres. Sets the air it flies in.
var altitude: float = 0.0: set = _set_altitude
## Height of the plane's centre above the ground under it, metres. INF when
## there is no ground under it (open sea is not something to stand on).
var ground_gap: float = INF
## Rolling resistance of that ground, as a share of the load on a wheel:
## about 0.03 on tarmac, 0.09 on grass.
var rolling_drag: float = 0.03

# --- Controls: set by the actor before each step ---------------------------------------
## -1 (roll left) .. +1 (roll right).
var aileron: float = 0.0
## -1 (nose down) .. +1 (nose up).
var elevator: float = 0.0
## -1 (nose left) .. +1 (nose right).
var rudder: float = 0.0
var throttle: float = 1.0
var flaps: float = 0.0
var gear: float = 0.0
## Wheel brakes, 0 (off) .. 1 (hard on).
var brake: float = 0.0

# --- Condition: set by the actor from its damage -----------------------------------------
## How much of its lift each wing panel still makes: left inner, right inner,
## left tip, right tip. 0 = shot off.
var panel_lift: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
## Aileron effectiveness, left and right.
var aileron_health: Vector2 = Vector2.ONE
var flap_health: Vector2 = Vector2.ONE
## Tailplane halves (0 = gone) and their elevators, left and right.
var tailplane: Vector2 = Vector2.ONE
var elevator_health: Vector2 = Vector2.ONE
var fin: float = 1.0
var rudder_health: float = 1.0
## Share of full power the engine can still give (0 = dead or switched off).
var engine_output: float = 1.0
## Whether the propeller is being driven (as opposed to windmilling or stopped dead).
var engine_turning: bool = true
## Extra drag coefficient from ragged or missing parts.
var damage_drag: float = 0.0
## 0 far from the ground .. 1 with the wheels on it (more lift, less drag).
var ground_effect: float = 0.0

# --- Undercarriage and hard points: set by set_undercarriage() and the actor --------------
## Where each Contact touches the ground, in the plane's own axes. For the
## wheels that is the tyre's lowest point with the leg fully extended.
var contact_points: PackedVector3Array = PackedVector3Array()
## Whether each is there to touch at all (a wheel that is up or broken off, a
## wingtip that has been shot away, are not).
var contact_enabled: PackedByteArray = PackedByteArray()
## Load on each right now, newtons.
var contact_load: PackedFloat32Array = PackedFloat32Array()
## For each, how fast it met the ground (m/s, straight down) when it last
## touched; 0 once the actor has read it and cleared it.
var contact_impact: PackedFloat32Array = PackedFloat32Array()

# --- Read-outs: filled in by step() --------------------------------------------------------
## How far the plane moved during the last step(), metres.
var displacement: Vector3 = Vector3.ZERO
## Share of the plane's weight the ground is carrying: 0 flying, 1 standing.
var weight_on_ground: float = 0.0
## Standing still with nothing acting on it (see SLEEP_TIME).
var asleep: bool = false
## The air here: density (kg/m^3), as a share of sea level's, and the speed of
## sound (m/s).
var density: float = AIR_DENSITY
var density_ratio: float = 1.0
var sound_speed: float = 340.3
## What the airspeed indicator reads: true airspeed scaled by the root of the
## density ratio. Lift, drag and the stall all go by this, not by true speed.
var indicated_airspeed: float = 0.0
var mach: float = 0.0
var airspeed: float = 0.0
## Angle of attack and sideslip of the whole aeroplane, radians.
var alpha: float = 0.0
var beta: float = 0.0
## Lift along the plane's own up axis, in units of its weight.
var load_factor: float = 1.0
## 0 = wing flying .. 1 = wing fully stalled (the average of its panels).
var stall: float = 0.0
## Thrust now, newtons.
var thrust: float = 0.0
## Where the trim tabs sit, as stick positions: x = elevator, y = aileron,
## z = rudder. They are added to the pilot's own inputs; see update_trim().
var trim: Vector3 = Vector3.ZERO

var _prop_radius: float = 1.6
var _prop_disc: float = 8.0
var _static_thrust: float = 11000.0
var _prop_inertia: float = 25.0
var _induced: float = 0.05
var _tail_arm: float = 5.3
## Results of the last _loads() / _surface() call (body axes).
var _force: Vector3 = Vector3.ZERO
var _torque: Vector3 = Vector3.ZERO
var _surface_force: Vector3 = Vector3.ZERO
var _last_separation: float = 0.0
## The trimmer's running solution: angle of attack and control positions for
## steady level flight at the present speed.
var _trim_alpha: float = 0.0
var _trim_target: Vector3 = Vector3.ZERO
var _trim_clock: float = 0.0
## How much g one unit of elevator is worth at the trimmed speed.
var _load_per_elevator: float = 4.0
var _contact_stiffness: PackedFloat32Array = PackedFloat32Array()
var _contact_damping: PackedFloat32Array = PackedFloat32Array()
var _contact_touching: PackedByteArray = PackedByteArray()
var _still_time: float = 0.0
## Share of sea-level power the engine can give at this height.
var _power_share: float = 1.0
## Worked out once by configure().
var _clean_stall_speed: float = 38.0
var _flapped_stall_speed: float = 35.0
var _top_speed: float = 130.0
var _climb_rate: float = 14.0
var _climb_speed: float = 70.0

## Performance figures by airframe, so a squadron of the same type only does
## the sums once.
static var _performance_cache: Dictionary = {}


## Sets the aeroplane up from its vital statistics.
func configure(plane_mass: float, area: float, span: float, shaft_power: float, zero_lift_drag: float, max_lift: float,
		thrust_factor: float = 1.0, roll: float = 1.0, full_power_height: float = 3500.0, power_at_height: float = 1.0) -> void:
	critical_altitude = full_power_height
	altitude_power = power_at_height
	mass = plane_mass
	wing_area = area
	wing_span = span
	power = shaft_power
	cd0 = zero_lift_drag
	cl_max = max_lift
	static_thrust_factor = thrust_factor
	roll_factor = roll
	# Mass spread like a single-engined fighter's: radii of gyration as shares
	# of the span (roll) and of the length (pitch), which is about 0.8 span.
	var roll_inertia: float = mass * pow(0.125 * span, 2.0)
	var pitch_inertia: float = mass * pow(0.15 * span, 2.0)
	inertia = Vector3(pitch_inertia, roll_inertia + pitch_inertia, roll_inertia)
	_tail_arm = TAIL_ARM * span
	_prop_radius = PROP_RADIUS * span
	_prop_disc = PI * _prop_radius * _prop_radius
	_static_thrust = STATIC_THRUST_SHARE * pow(2.0 * AIR_DENSITY * _prop_disc * power * power, 1.0 / 3.0) * static_thrust_factor
	_prop_inertia = PROP_INERTIA_SHARE * mass * _prop_radius * _prop_radius
	var aspect_ratio: float = span * span / area
	_induced = 1.0 / (PI * 0.8 * aspect_ratio)
	if contact_points.is_empty():
		# Until the model says otherwise: a plain undercarriage of about the right size.
		set_undercarriage(Vector3(-0.16 * span, -0.3 * span, -0.15 * span), Vector3(0.0, -0.18 * span, 0.38 * span),
				0.15 * span, Vector3(0.0, -0.14 * span, -0.5 * span), Vector3(0.5 * span, -0.04 * span, -0.1 * span),
				Vector3(0.0, -0.1 * span, 0.42 * span))
	altitude = altitude  # (works out the air for wherever it already is)
	_measure_performance()


## Says where the plane meets the ground, all in its own axes: the lowest
## point of the left main wheel and of the tail wheel when the plane is
## standing on them, how far the belly is below the centre, the lowest point
## of the propeller's disc, the left wingtip, and the bottom of the tail.
## Springs are sized so that the standing plane sits exactly as those points
## say, with the legs squashed by its weight.
func set_undercarriage(main_wheel: Vector3, tail_wheel: Vector3, belly_depth: float, nose: Vector3, wingtip: Vector3, tail_bottom: Vector3) -> void:
	var half_track: float = absf(main_wheel.x)
	var wingtip_reach: float = absf(wingtip.x)
	contact_points = PackedVector3Array([
		Vector3(-half_track, main_wheel.y - MAIN_LEG_SAG, main_wheel.z), Vector3(half_track, main_wheel.y - MAIN_LEG_SAG, main_wheel.z),
		Vector3(0.0, tail_wheel.y - TAIL_LEG_SAG, tail_wheel.z), Vector3(0.0, -belly_depth, 0.0), nose,
		Vector3(-wingtip_reach, wingtip.y, wingtip.z), Vector3(wingtip_reach, wingtip.y, wingtip.z), tail_bottom])
	contact_enabled = PackedByteArray([1, 1, 1, 1, 1, 1, 1, 1])
	contact_load.resize(CONTACT_COUNT)
	contact_load.fill(0.0)
	contact_impact.resize(CONTACT_COUNT)
	contact_impact.fill(0.0)
	_contact_touching.resize(CONTACT_COUNT)
	_contact_touching.fill(0)
	_contact_stiffness.resize(CONTACT_COUNT)
	_contact_damping.resize(CONTACT_COUNT)
	# How the standing weight is shared between the main wheels and the tail.
	var weight: float = mass * GRAVITY
	var wheelbase: float = maxf(tail_wheel.z - main_wheel.z, 0.5)
	var tail_share: float = clampf(-main_wheel.z / wheelbase, 0.04, 0.6)
	var main_load: float = weight * (1.0 - tail_share) * 0.5
	var tail_load: float = weight * tail_share
	for index: int in range(CONTACT_COUNT):
		var stiffness: float
		var carried: float
		if index <= Contact.RIGHT_WHEEL:
			stiffness = main_load / MAIN_LEG_SAG
			carried = main_load / GRAVITY
			_contact_damping[index] = 2.0 * LEG_DAMPING * sqrt(stiffness * carried)
		elif index == Contact.TAIL_WHEEL:
			stiffness = tail_load / TAIL_LEG_SAG
			carried = tail_load / GRAVITY
			_contact_damping[index] = 2.0 * LEG_DAMPING * sqrt(stiffness * carried)
		else:
			# A hard point feels less of the plane the further out it is: a
			# wingtip can be pushed up by rolling the whole aeroplane.
			var place: Vector3 = contact_points[index]
			carried = 1.0 / (1.0 / mass + place.x * place.x / inertia.z + place.z * place.z / inertia.x)
			stiffness = carried * HARD_POINT_RATE * HARD_POINT_RATE
			_contact_damping[index] = 2.0 * HARD_POINT_DAMPING * carried * HARD_POINT_RATE
		_contact_stiffness[index] = stiffness


## Attitude and height at which the plane stands at rest on its three wheels:
## x = nose-up angle (radians), y = height of its centre above the ground.
func standing_attitude() -> Vector2:
	var main: Vector3 = contact_points[Contact.LEFT_WHEEL] + Vector3(0.0, MAIN_LEG_SAG, 0.0)
	var tail: Vector3 = contact_points[Contact.TAIL_WHEEL] + Vector3(0.0, TAIL_LEG_SAG, 0.0)
	var line: Vector2 = Vector2(tail.z - main.z, tail.y - main.y)
	var nose_up: float = atan2(line.y, line.x)
	# Distance from the centre to the line through both contact points.
	var height: float = absf(main.z * tail.y - main.y * tail.z) / maxf(line.length(), 0.01)
	return Vector2(nose_up, height)


## How far the lowest thing that could touch the ground is above it (negative:
## how far into it), for a plane at [param gap] above the ground in its
## present attitude.
func clearance(gap: float) -> float:
	var lowest: float = INF
	for index: int in range(CONTACT_COUNT):
		if contact_enabled[index] != 0:
			lowest = minf(lowest, (basis * contact_points[index]).y)
	return gap + lowest


## True while this Contact is on the ground.
func is_touching(contact: Contact) -> bool:
	return _contact_touching[contact] != 0


## Wakes a plane that has gone to sleep on the ground (see SLEEP_TIME).
func wake() -> void:
	asleep = false
	_still_time = 0.0


## Puts the plane in the air at [param start_velocity], pointing as given, not
## rotating and trimmed for that speed.
func reset(start_basis: Basis, start_velocity: Vector3) -> void:
	basis = start_basis.orthonormalized()
	velocity = start_velocity
	angular_velocity = Vector3.ZERO
	airspeed = velocity.length()
	indicated_airspeed = airspeed * sqrt(density_ratio)
	alpha = 0.0
	beta = 0.0
	load_factor = 1.0
	stall = 0.0
	displacement = Vector3.ZERO
	weight_on_ground = 0.0
	contact_load.fill(0.0)
	contact_impact.fill(0.0)
	_contact_touching.fill(0)
	wake()
	settle_trim()


## Advances the plane by [param delta] seconds, in [param substeps] slices.
## Near the ground it takes more of them: undercarriage legs are stiff springs.
func step(delta: float, substeps: int = 2) -> void:
	displacement = Vector3.ZERO
	if asleep:
		if not _should_wake():
			return
		wake()
	var slices: int = substeps
	if is_finite(ground_gap) and clearance(ground_gap) < 6.0:
		slices = maxi(substeps, 4)
	var slice: float = delta / float(slices)
	for _slice: int in range(slices):
		_advance(slice)
	_consider_sleeping(delta)


# ---------------------------------------------------------------------------
# The air
# ---------------------------------------------------------------------------

## Air temperature (K) at [param height] metres above sea level.
static func temperature_at(height: float) -> float:
	return SEA_LEVEL_TEMPERATURE - LAPSE_RATE * clampf(height, -500.0, 11000.0)


## Air density (kg/m^3) at [param height] metres above sea level.
static func density_at(height: float) -> float:
	return AIR_DENSITY * pow(temperature_at(height) / SEA_LEVEL_TEMPERATURE, DENSITY_EXPONENT)


## Speed of sound (m/s) at [param height] metres above sea level.
static func sound_speed_at(height: float) -> float:
	return sqrt(SOUND_SPEED_FACTOR * temperature_at(height))


## Share of its sea-level power the engine gives at [param height]: easing
## down to altitude_power at the supercharger's critical altitude, then
## falling with the air.
func power_share_at(height: float) -> float:
	if height <= critical_altitude:
		return lerpf(1.0, altitude_power, clampf(height / maxf(critical_altitude, 1.0), 0.0, 1.0))
	var thinner: float = density_at(height) / density_at(critical_altitude)
	return altitude_power * clampf((1.0 + POWER_LAPSE) * thinner - POWER_LAPSE, 0.0, 1.0)


func _set_altitude(value: float) -> void:
	altitude = value
	density = density_at(value)
	density_ratio = density / AIR_DENSITY
	sound_speed = sound_speed_at(value)
	_power_share = power_share_at(value)


# ---------------------------------------------------------------------------
# Trim
# ---------------------------------------------------------------------------

## The pilot's trimming. Works out where the three trim tabs should sit for
## the plane to fly straight and level, hands off, at its present speed and
## power, and winds [member trim] toward that: the elevator tab quickly, the
## aileron and rudder tabs slowly. So a steady cruise needs no effort, but
## every change (opening the throttle, slowing at the top of a loop, dropping
## the flaps) is felt until the tabs catch up. Nobody trims for speeds near
## the stall: slower than SLOWEST_TRIM times the stalling speed the tabs stay
## where they were, the pilot has to hold the nose up himself, and letting go
## of the stick lets the nose drop and the speed come back. Call every
## physics tick while flying.
func update_trim(delta: float) -> void:
	_trim_clock += delta
	if _trim_clock >= TRIM_INTERVAL:
		_trim_clock = 0.0
		_improve_trim(maxf(airspeed, true_speed(stall_speed(flaps) * SLOWEST_TRIM)))
	var quick: float = 1.0 - exp(-delta / ELEVATOR_TRIM_TIME)
	var slow: float = 1.0 - exp(-delta / LATERAL_TRIM_TIME)
	trim.x = lerpf(trim.x, _trim_target.x, quick)
	trim.y = lerpf(trim.y, _trim_target.y, slow)
	trim.z = lerpf(trim.z, _trim_target.z, slow)


## Trims the plane for its present speed at once (after a respawn).
func settle_trim() -> void:
	var speed: float = maxf(airspeed, true_speed(stall_speed(flaps) * SLOWEST_TRIM))
	_trim_alpha = 0.0
	_trim_target = Vector3.ZERO
	for _pass: int in range(8):
		_improve_trim(speed)
	trim = _trim_target
	_trim_clock = 0.0


## One round of Newton's method on the trim: angle of attack and elevator for
## lift = weight and no pitching, then aileron and rudder for no rolling or
## yawing.
func _improve_trim(speed: float) -> void:
	var weight: float = mass * GRAVITY
	var step_alpha: float = 0.01
	var step_control: float = 0.05
	_loads(_flow(_trim_alpha, speed), Vector3.ZERO, _trim_target.x, _trim_target.y, _trim_target.z, false)
	var lift: float = _force.y
	var moment: Vector3 = _torque
	_loads(_flow(_trim_alpha + step_alpha, speed), Vector3.ZERO, _trim_target.x, _trim_target.y, _trim_target.z, false)
	var lift_by_alpha: float = (_force.y - lift) / step_alpha
	var pitch_by_alpha: float = (_torque.x - moment.x) / step_alpha
	_loads(_flow(_trim_alpha, speed), Vector3.ZERO, _trim_target.x + step_control, _trim_target.y, _trim_target.z, false)
	var lift_by_elevator: float = (_force.y - lift) / step_control
	var pitch_by_elevator: float = (_torque.x - moment.x) / step_control
	var determinant: float = lift_by_alpha * pitch_by_elevator - lift_by_elevator * pitch_by_alpha
	if pitch_by_alpha < -1.0:
		# Steady pull: elevator changes the angle of attack until the tail
		# balances it, and that angle of attack is the extra lift.
		_load_per_elevator = clampf(-pitch_by_elevator / pitch_by_alpha * lift_by_alpha / weight, 0.3, 30.0)
	if absf(determinant) > 1.0:
		var miss: float = weight - lift
		var alpha_change: float = (miss * pitch_by_elevator + lift_by_elevator * moment.x) / determinant
		var elevator_change: float = (-lift_by_alpha * moment.x - pitch_by_alpha * miss) / determinant
		_trim_alpha = clampf(_trim_alpha + clampf(alpha_change, -0.06, 0.06), -0.2, 0.3)
		_trim_target.x = clampf(_trim_target.x + clampf(elevator_change, -0.3, 0.3), -1.0, 1.0)
	# Roll and yaw: each tab mostly does its own job, so treat them apart.
	_loads(_flow(_trim_alpha, speed), Vector3.ZERO, _trim_target.x, _trim_target.y + step_control, _trim_target.z, false)
	var roll_by_aileron: float = (_torque.z - moment.z) / step_control
	_loads(_flow(_trim_alpha, speed), Vector3.ZERO, _trim_target.x, _trim_target.y, _trim_target.z + step_control, false)
	var yaw_by_rudder: float = (_torque.y - moment.y) / step_control
	if absf(roll_by_aileron) > 1.0:
		_trim_target.y = clampf(_trim_target.y - clampf(moment.z / roll_by_aileron, -0.2, 0.2), -0.6, 0.6)
	if absf(yaw_by_rudder) > 1.0:
		_trim_target.z = clampf(_trim_target.z - clampf(moment.y / yaw_by_rudder, -0.2, 0.2), -0.6, 0.6)


## Velocity in body axes of a plane flying at [param speed] and angle of
## attack [param attack] with no sideslip.
func _flow(attack: float, speed: float) -> Vector3:
	return Vector3(0.0, -sin(attack), -cos(attack)) * speed


# ---------------------------------------------------------------------------
# What the aeroplane can do (for the HUD, the hangar and the bots)
# ---------------------------------------------------------------------------

## Indicated airspeed (m/s) below which the wing cannot hold the plane up in
## level flight, with the flaps at [param flap_setting] (0 up .. 1 down).
## Measured from the model itself, engine idling. It is the same on the
## airspeed indicator at any height; the true speed it stands for is not.
func stall_speed(flap_setting: float = 0.0) -> float:
	return lerpf(_clean_stall_speed, _flapped_stall_speed, clampf(flap_setting, 0.0, 1.0))


## Top speed in level flight at full power at sea level, m/s, clean and undamaged.
func level_top_speed() -> float:
	return _top_speed


## The true airspeed (m/s) that reads [param indicated] on the airspeed
## indicator at the plane's present height.
func true_speed(indicated: float) -> float:
	return indicated / sqrt(maxf(density_ratio, 0.05))


## Top true airspeed (m/s) in level flight at full power at [param height]
## metres, clean and undamaged. Thinner air is less drag, so this rises with
## height until the engine runs out of supercharger.
func top_speed_at(height: float) -> float:
	var key: String = "%s@%.0f" % [_performance_key(), height]
	if _performance_cache.has(key):
		var known: PackedFloat32Array = _performance_cache[key]
		return known[0]
	var kept: Array[float] = [throttle, flaps, gear, engine_output, damage_drag, ground_effect, altitude]
	var kept_turning: bool = engine_turning
	var kept_trim_alpha: float = _trim_alpha
	var kept_trim_target: Vector3 = _trim_target
	flaps = 0.0
	gear = 0.0
	damage_drag = 0.0
	ground_effect = 0.0
	engine_output = 1.0
	engine_turning = true
	throttle = 1.0
	altitude = height
	var low: float = true_speed(_clean_stall_speed * 1.3)
	var high: float = 330.0
	for _pass: int in range(14):
		var middle: float = (low + high) * 0.5
		if _level_excess(middle) > 0.0:
			low = middle
		else:
			high = middle
	throttle = kept[0]
	flaps = kept[1]
	gear = kept[2]
	engine_output = kept[3]
	damage_drag = kept[4]
	ground_effect = kept[5]
	altitude = kept[6]
	engine_turning = kept_turning
	_trim_alpha = kept_trim_alpha
	_trim_target = kept_trim_target
	_performance_cache[key] = PackedFloat32Array([low])
	return low


## Best rate of climb at full power (m/s), and the airspeed that gives it.
func best_climb_rate() -> float:
	return _climb_rate


func best_climb_speed() -> float:
	return _climb_speed


## The most g the wing can pull at true airspeed [param speed], at the
## plane's present height, before it stalls.
func available_load(speed: float) -> float:
	var slowest: float = stall_speed(flaps)
	return speed * speed * density_ratio / maxf(slowest * slowest, 1.0)


## How much stick (beyond the trimmed position) holds [param load] g at the
## present speed. An estimate for autopilots: it ignores the stall.
func elevator_for_load(load: float) -> float:
	return (load - 1.0) / _load_per_elevator


## Angle of attack (radians, of the fuselage) at which the wing lets go.
func stall_alpha() -> float:
	return cl_max / WING_LIFT_SLOPE + STALL_OFFSET * STALL_SHARPNESS - WING_INCIDENCE


## Angle of attack (radians, of the fuselage) at which the clean wing makes
## the most lift it ever will: the edge of the buffet. A little more angle
## gets less lift and a great deal more drag.
func best_alpha() -> float:
	var best_angle: float = 0.0
	var best_lift: float = 0.0
	var break_angle: float = cl_max / WING_LIFT_SLOPE + STALL_OFFSET * STALL_SHARPNESS
	var attack: float = 0.1
	while attack < 0.7:
		var attached: float = minf(WING_LIFT_SLOPE * attack, cl_max)
		var plate: float = 0.5 * FLAT_PLATE_NORMAL * sin(2.0 * attack)
		var lift: float = lerpf(attached, plate, 1.0 / (1.0 + exp(-(attack - break_angle) / STALL_SHARPNESS)))
		if lift > best_lift:
			best_lift = lift
			best_angle = attack
		attack += 0.002
	return best_angle - WING_INCIDENCE


## Thrust (N) at full throttle and [param forward_speed], engine healthy.
func full_thrust(forward_speed: float) -> float:
	return _thrust_at(forward_speed, 1.0, 1.0)


## Flies the clean, undamaged aeroplane on paper to find its stalling speeds,
## top speed and best climb.
func _measure_performance() -> void:
	var key: String = _performance_key()
	if _performance_cache.has(key):
		var known: PackedFloat32Array = _performance_cache[key]
		_clean_stall_speed = known[0]
		_flapped_stall_speed = known[1]
		_top_speed = known[2]
		_climb_rate = known[3]
		_climb_speed = known[4]
		return
	# Remember the state this borrows. It is all measured at sea level.
	var kept: Array[float] = [throttle, flaps, gear, engine_output, damage_drag, ground_effect, altitude]
	var kept_turning: bool = engine_turning
	var kept_trim_alpha: float = _trim_alpha
	var kept_trim_target: Vector3 = _trim_target
	altitude = 0.0
	gear = 0.0
	damage_drag = 0.0
	ground_effect = 0.0
	engine_output = 1.0
	engine_turning = true
	# Stall: the most lift it can make at any angle, engine idling.
	throttle = 0.0
	var weight: float = mass * GRAVITY
	var probe_speed: float = 50.0
	var probe_pressure: float = 0.5 * AIR_DENSITY * probe_speed * probe_speed
	for setting: int in range(2):
		flaps = float(setting)
		var most: float = 0.0
		var attack: float = deg_to_rad(4.0)
		while attack < deg_to_rad(24.0):
			_loads(_flow(attack, probe_speed), Vector3.ZERO, 0.4, 0.0, 0.0, false)
			most = maxf(most, _force.y)
			attack += deg_to_rad(0.5)
		var slowest: float = sqrt(weight / maxf(most / probe_pressure, 1.0) / (0.5 * AIR_DENSITY))
		if setting == 0:
			_clean_stall_speed = slowest
		else:
			_flapped_stall_speed = slowest
	flaps = 0.0
	# Speed: where full thrust just balances drag, trimmed level.
	throttle = 1.0
	var low: float = _clean_stall_speed * 1.3
	var high: float = 320.0
	for _pass: int in range(14):
		var middle: float = (low + high) * 0.5
		if _level_excess(middle) > 0.0:
			low = middle
		else:
			high = middle
	_top_speed = low
	# Climb: the speed with the most power to spare.
	_climb_rate = 0.0
	_climb_speed = _clean_stall_speed * 1.4
	var speed: float = _clean_stall_speed * 1.25
	while speed < _top_speed:
		var rate: float = _level_excess(speed) * speed / weight
		if rate > _climb_rate:
			_climb_rate = rate
			_climb_speed = speed
		speed += 6.0
	throttle = kept[0]
	flaps = kept[1]
	gear = kept[2]
	engine_output = kept[3]
	damage_drag = kept[4]
	ground_effect = kept[5]
	altitude = kept[6]
	engine_turning = kept_turning
	_trim_alpha = kept_trim_alpha
	_trim_target = kept_trim_target
	_performance_cache[key] = PackedFloat32Array([_clean_stall_speed, _flapped_stall_speed, _top_speed, _climb_rate, _climb_speed])


func _performance_key() -> String:
	return "%.1f/%.3f/%.3f/%.0f/%.5f/%.3f/%.3f/%.0f/%.3f" % [mass, wing_area, wing_span, power, cd0, cl_max, static_thrust_factor, critical_altitude, altitude_power]


## Force to spare along the nose (thrust minus drag, N) in trimmed level
## flight at [param speed] with the present throttle.
func _level_excess(speed: float) -> float:
	_trim_alpha = 0.03
	_trim_target = Vector3.ZERO
	for _pass: int in range(6):
		_improve_trim(speed)
	_loads(_flow(_trim_alpha, speed), Vector3.ZERO, _trim_target.x, _trim_target.y, _trim_target.z, false)
	# Along the flight path, not the nose.
	return -(_force.z * cos(_trim_alpha) + _force.y * sin(_trim_alpha))


# ---------------------------------------------------------------------------
# The physics
# ---------------------------------------------------------------------------

func _advance(delta: float) -> void:
	var body_velocity: Vector3 = basis.transposed() * velocity
	airspeed = body_velocity.length()
	indicated_airspeed = airspeed * sqrt(density_ratio)
	mach = airspeed / sound_speed
	alpha = atan2(-body_velocity.y, maxf(-body_velocity.z, 0.01)) if airspeed > 1.0 else 0.0
	beta = asin(clampf(body_velocity.x / maxf(airspeed, 1.0), -1.0, 1.0))
	_loads(body_velocity, angular_velocity,
			clampf(elevator + trim.x, -1.0, 1.0), clampf(aileron + trim.y, -1.0, 1.0), clampf(rudder + trim.z, -1.0, 1.0), true)
	load_factor = _force.y / (mass * GRAVITY)
	# The ground pushes back wherever the plane is touching it.
	var ground_push: Vector3 = Vector3.ZERO
	if is_finite(ground_gap):
		ground_push = _ground_loads()
	else:
		_leave_the_ground()
	# --- Move ------------------------------------------------------------------------
	velocity += ((basis * _force + ground_push) / mass + Vector3(0.0, -GRAVITY, 0.0)) * delta
	# --- Turn: Euler's equations for a rigid body ------------------------------------
	var momentum: Vector3 = Vector3(inertia.x * angular_velocity.x, inertia.y * angular_velocity.y, inertia.z * angular_velocity.z)
	var spin_up: Vector3 = _torque - angular_velocity.cross(momentum)
	angular_velocity += Vector3(spin_up.x / inertia.x, spin_up.y / inertia.y, spin_up.z / inertia.z) * delta
	var turn: float = angular_velocity.length() * delta
	if turn > 1.0e-7:
		basis = (basis * Basis(angular_velocity.normalized(), turn)).orthonormalized()
	var moved: Vector3 = velocity * delta
	displacement += moved
	if is_finite(ground_gap):
		ground_gap += moved.y
		# Solid ground: whatever the springs made of it, nothing goes deeper
		# than a dent. The plane is stopped there.
		var dent: float = -clearance(ground_gap) - _deepest_allowed()
		if dent > 0.0:
			ground_gap += dent
			displacement.y += dent
			if velocity.y < 0.0:
				velocity.y = 0.0


# ---------------------------------------------------------------------------
# The ground
# ---------------------------------------------------------------------------

## What the ground does to the plane this instant: returns its push in world
## axes and adds its twist to _torque. Notes the load on every Contact, and
## how hard each one arrived if it has only just touched.
func _ground_loads() -> Vector3:
	var push: Vector3 = Vector3.ZERO
	var carried: float = 0.0
	var to_plane: Basis = basis.transposed()
	# Which way the wheels roll: along the nose, flat on the ground.
	var ahead: Vector3 = Vector3(-basis.z.x, 0.0, -basis.z.z)
	if ahead.length() < 0.05:
		ahead = Vector3(basis.y.x, 0.0, basis.y.z)  # Standing on its nose or tail.
	ahead = ahead.normalized()
	# The rudder bar itself (not the trim tab) works the tail wheel and brakes.
	var rudder_bar: float = clampf(rudder, -1.0, 1.0)
	for index: int in range(CONTACT_COUNT):
		if contact_enabled[index] == 0:
			contact_load[index] = 0.0
			_contact_touching[index] = 0
			continue
		var place: Vector3 = contact_points[index]
		var dent: float = -(ground_gap + (basis * place).y)
		if dent <= 0.0:
			contact_load[index] = 0.0
			_contact_touching[index] = 0
			continue
		var motion: Vector3 = velocity + basis * angular_velocity.cross(place)
		var closing: float = -motion.y
		if _contact_touching[index] == 0:
			_contact_touching[index] = 1
			contact_impact[index] = maxf(contact_impact[index], maxf(closing, 0.01))
		var wheel: bool = index <= Contact.TAIL_WHEEL
		var stiffness: float = _contact_stiffness[index]
		var load: float = stiffness * dent + _contact_damping[index] * closing
		if wheel:
			if closing < 0.0:
				load = stiffness * dent + _contact_damping[index] * LEG_REBOUND * closing
			var limit: float = (MAIN_LEG_SAG if index != Contact.TAIL_WHEEL else TAIL_LEG_SAG) + LEG_TRAVEL
			if dent > limit:
				load += stiffness * BOTTOMED_STIFFENING * (dent - limit)
		load = maxf(load, 0.0)
		contact_load[index] = load
		carried += load
		var across_ground: Vector3 = Vector3(motion.x, 0.0, motion.z)
		var grip: Vector3
		if wheel:
			var rolling: Vector3 = ahead
			var braking: float = clampf(brake * (1.0 + BRAKE_STEER * rudder_bar * (1.0 if index == Contact.RIGHT_WHEEL else -1.0)), 0.0, 1.0)
			if index == Contact.TAIL_WHEEL:
				# Rudder right turns the tail wheel to run out to the left.
				rolling = ahead.rotated(Vector3.UP, rudder_bar * TAIL_WHEEL_STEER)
				braking = 0.0
			var sideways: Vector3 = rolling.cross(Vector3.UP)
			var along: float = across_ground.dot(rolling)
			var slip: float = across_ground.dot(sideways)
			var side_grip: float = -TYRE_SIDE_GRIP * load * clampf(slip / maxf(absf(along) * TYRE_SLIP_PEAK, TYRE_CRAWL_SPEED), -1.0, 1.0)
			var roll_grip: float = -(rolling_drag + BRAKE_GRIP * braking) * load * clampf(along / WHEEL_STOP_SPEED, -1.0, 1.0)
			grip = rolling * roll_grip + sideways * side_grip
			grip = grip.limit_length(maxf(TYRE_SIDE_GRIP, BRAKE_GRIP + rolling_drag) * load)
		else:
			# Metal, scraping: it drags against whichever way it is sliding.
			grip = -across_ground * (SKID_GRIP * load / maxf(across_ground.length(), TYRE_CRAWL_SPEED))
		var total: Vector3 = Vector3(grip.x, load, grip.z)
		push += total
		_torque += place.cross(to_plane * total)
	weight_on_ground = clampf(carried / (mass * GRAVITY), 0.0, 3.0)
	return push


func _leave_the_ground() -> void:
	if weight_on_ground > 0.0:
		weight_on_ground = 0.0
		contact_load.fill(0.0)
		_contact_touching.fill(0)


## How far the deepest Contact may go into the ground before the plane is
## simply stopped: a leg's whole travel and a little more, or a dent.
func _deepest_allowed() -> float:
	var lowest_index: int = -1
	var lowest: float = INF
	for index: int in range(CONTACT_COUNT):
		if contact_enabled[index] != 0:
			var height: float = (basis * contact_points[index]).y
			if height < lowest:
				lowest = height
				lowest_index = index
	if lowest_index == Contact.TAIL_WHEEL:
		return TAIL_LEG_SAG + LEG_TRAVEL + DEEPEST_DENT
	if lowest_index >= 0 and lowest_index <= Contact.RIGHT_WHEEL:
		return MAIN_LEG_SAG + LEG_TRAVEL + DEEPEST_DENT
	return DEEPEST_DENT


## Standing still on the ground with the brakes holding and nothing else
## happening, the plane is put to sleep: no more sums until something moves it.
func _consider_sleeping(delta: float) -> void:
	var holding: bool = weight_on_ground > 0.7 and velocity.length() < SLEEP_SPEED and angular_velocity.length() < SLEEP_SPIN \
			and _standing_thrust() < _holding_force()
	if not holding:
		_still_time = 0.0
		return
	_still_time += delta
	if _still_time >= SLEEP_TIME:
		asleep = true
		velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO


func _should_wake() -> bool:
	return _standing_thrust() >= _holding_force() or not is_finite(ground_gap)


## Thrust standing still at the present throttle, and the most the wheels
## can hold against at the present brake setting.
func _standing_thrust() -> float:
	if not engine_turning or engine_output <= 0.0:
		return 0.0
	return _thrust_at(0.0, throttle, engine_output)


func _holding_force() -> float:
	return (rolling_drag + BRAKE_GRIP * brake) * mass * GRAVITY * 0.7


## Thrust (N) at [param forward_speed] for a throttle setting and engine health.
func _thrust_at(forward_speed: float, throttle_setting: float, output: float) -> float:
	var shaft_power: float = power * _power_share * clampf(throttle_setting, 0.0, 1.0) * clampf(output, 0.0, 1.0)
	if shaft_power <= 0.0:
		return 0.0
	# Static thrust goes with power to the two-thirds and with the cube root
	# of the air's density; at speed, thrust is power over speed. The
	# propeller gives the lesser, blended smoothly.
	var standing: float = _static_thrust * pow(shaft_power / power, 2.0 / 3.0) * pow(density_ratio, 1.0 / 3.0)
	var moving: float = PROP_EFFICIENCY * shaft_power / maxf(forward_speed, 5.0)
	return 1.0 / sqrt(1.0 / (standing * standing) + 1.0 / (moving * moving)) + EXHAUST_THRUST * shaft_power


## Everything that pushes on the aeroplane except gravity (the air on every
## surface, and the propeller), in its own axes, flying at [param body_velocity]
## and rotating at [param rotation] with the controls as given. Leaves the
## force in _force and the torque about the centre of gravity in _torque. With
## [param record] set it also notes thrust and how stalled the wing is.
func _loads(body_velocity: Vector3, rotation: Vector3, elevator_setting: float, aileron_setting: float, rudder_setting: float, record: bool) -> void:
	var half_span: float = wing_span * 0.5
	var speed: float = body_velocity.length()
	var forward_speed: float = maxf(-body_velocity.z, 0.0)
	var driven: bool = engine_turning and engine_output > 0.0 and throttle > 0.0
	var pull: float = _thrust_at(forward_speed, throttle, engine_output) if driven else 0.0
	# Slipstream: the propeller throws air back faster than the plane meets it.
	var slipstream: float = 0.0
	if driven:
		slipstream = sqrt(forward_speed * forward_speed + 2.0 * pull / (density * _prop_disc)) - forward_speed
	# Heavy controls at speed: it is the push of the air that the pilot fights,
	# so this goes by indicated airspeed. Near the speed of sound the airflow
	# over the surfaces breaks down as well.
	var indicated: float = speed * sqrt(density_ratio)
	var mach_excess: float = maxf(speed / sound_speed - CRITICAL_MACH, 0.0)
	var grip_left: float = 1.0 / (1.0 + MACH_CONTROL_LOSS * mach_excess * mach_excess)
	var wave_drag: float = 1.0 + MACH_DRAG * mach_excess * mach_excess
	var aileron_reach: float = AILERON_TRAVEL * AILERON_POWER * roll_factor * _lightness(indicated, AILERON_HEAVY_SPEED) * grip_left
	var elevator_reach: float = ELEVATOR_TRAVEL * ELEVATOR_POWER * _lightness(indicated, ELEVATOR_HEAVY_SPEED) * grip_left
	var rudder_reach: float = RUDDER_TRAVEL * RUDDER_POWER * _lightness(indicated, RUDDER_HEAVY_SPEED) * grip_left
	var lift_boost: float = 1.0 + 0.14 * ground_effect
	var induced: float = _induced * (1.0 - 0.45 * ground_effect)

	var force: Vector3 = Vector3.ZERO
	var torque: Vector3 = Vector3.ZERO
	var stalled_share: float = 0.0
	var attack_now: float = atan2(-body_velocity.y, maxf(-body_velocity.z, 0.01))
	var wing_alpha: float = clampf(attack_now + WING_INCIDENCE, -0.35, 0.35)

	# --- Wing: four panels -------------------------------------------------------
	var panel_drag: float = cd0 * 0.45 * wave_drag
	for panel: int in range(4):
		var share: float = panel_lift[panel]
		if share <= 0.0:
			continue
		var left: bool = panel % 2 == 0
		var tip: bool = panel >= 2
		var side: float = -1.0 if left else 1.0
		var arm: float = (TIP_PANEL_ARM if tip else INNER_PANEL_ARM) * half_span
		var area: float = wing_area * 0.5 * ((1.0 - INNER_PANEL_AREA) if tip else INNER_PANEL_AREA) * share
		var place: Vector3 = Vector3(side * arm, arm * sin(WING_DIHEDRAL) - 0.3, WING_AFT * wing_span)
		# Dihedral: each wing's "up" leans in toward the fuselage.
		var normal: Vector3 = Vector3(-side * sin(WING_DIHEDRAL), cos(WING_DIHEDRAL), 0.0)
		var incidence: float = WING_INCIDENCE
		var best_lift: float = cl_max
		var drag: float = panel_drag
		if tip:
			# Ailerons: stick right lowers the left one and raises the right.
			var aileron_share: float = aileron_health.x if left else aileron_health.y
			incidence += -TIP_WASHOUT - side * aileron_setting * aileron_reach * aileron_share
		else:
			var flap_share: float = flaps * (flap_health.x if left else flap_health.y)
			incidence += FLAP_ANGLE * flap_share
			best_lift += FLAP_CL_MAX * flap_share
			drag += FLAP_DRAG * flap_share
		var wash: float = slipstream * (0.0 if tip else SLIPSTREAM_AT_INNER_WING)
		_last_separation = _surface(place, normal, area, incidence, WING_LIFT_SLOPE, best_lift, drag, induced, lift_boost,
				body_velocity, rotation, wash, 0.0)
		stalled_share += 0.25 * _last_separation
		force += _surface_force
		torque += place.cross(_surface_force)
		# The cambered section's own nose-down twist, for as long as the air
		# still follows it.
		var panel_air: float = body_velocity.z * body_velocity.z + body_velocity.y * body_velocity.y
		torque.x += 0.5 * density * panel_air * area * (wing_area / wing_span) * WING_PITCHING * (1.0 - _last_separation)

	# --- Tailplane: two halves, each with its elevator --------------------------
	var tail_drag: float = cd0 * 0.6 * wave_drag
	for half: int in range(2):
		var present: float = tailplane.x if half == 0 else tailplane.y
		if present <= 0.0:
			continue
		var side: float = -1.0 if half == 0 else 1.0
		var place: Vector3 = Vector3(side * 0.16 * half_span, 0.25, _tail_arm)
		var area: float = wing_area * TAILPLANE_AREA * 0.5 * present
		var elevator_share: float = elevator_health.x if half == 0 else elevator_health.y
		# The wing's downwash meets the tail from above; back stick raises the
		# elevators, pushing the tail down.
		var incidence: float = TAIL_INCIDENCE - DOWNWASH * wing_alpha - elevator_setting * elevator_reach * elevator_share
		_surface(place, Vector3.UP, area, incidence, TAIL_LIFT_SLOPE, TAIL_CL_MAX, tail_drag, 0.08, 1.0,
				body_velocity, rotation, slipstream * SLIPSTREAM_AT_TAIL, 0.0)
		force += _surface_force
		torque += place.cross(_surface_force)

	# --- Fin and rudder ----------------------------------------------------------
	if fin > 0.0:
		var place: Vector3 = Vector3(0.0, FIN_HEIGHT * wing_span, _tail_arm)
		# Rudder right swings the tail left.
		var incidence: float = -rudder_setting * rudder_reach * rudder_health
		_surface(place, Vector3.RIGHT, wing_area * FIN_AREA * fin, incidence, FIN_LIFT_SLOPE, TAIL_CL_MAX, tail_drag, 0.1, 1.0,
				body_velocity, rotation, slipstream * SLIPSTREAM_AT_TAIL, slipstream * SLIPSTREAM_SPIRAL)
		force += _surface_force
		torque += place.cross(_surface_force)

	# --- Fuselage, wheels and battle damage: plain drag --------------------------
	# Slender nose-on, a barn door sideways or flat-on.
	var body_drag: float = cd0 * 0.4 * wave_drag + GEAR_DRAG * gear + damage_drag
	var air: Vector3 = -body_velocity
	var fuselage: Vector3 = 0.5 * density * air.length() * wing_area * Vector3(air.x * 0.28, air.y * 0.42, air.z * body_drag)
	force += fuselage
	# It acts a little behind the centre of gravity, which helps the tail.
	torque += Vector3(0.0, 0.0, 0.06 * wing_span).cross(Vector3(fuselage.x, fuselage.y, 0.0))
	# Whirling round, every part of the plane meets air that a point at its
	# centre does not: that soaks up rotation even when nothing is flying.
	var damping: float = 0.5 * density * wing_area * wing_span * wing_span * maxf(speed, 20.0)
	torque -= Vector3(rotation.x * 0.012, rotation.y * 0.012, rotation.z * 0.004) * damping

	# --- Propeller ---------------------------------------------------------------
	force.z -= pull
	if driven:
		var shaft_power: float = power * _power_share * throttle * engine_output
		var prop_rate: float = PROP_RATE * lerpf(0.45, 1.0, throttle)
		# Torque: the engine turns the propeller one way and the airframe the
		# other. Some of it comes back: the slipstream leaves the propeller
		# spinning, and the wings and tail it then meets straighten it out.
		torque.z += shaft_power / prop_rate * (1.0 - SWIRL_RECOVERY)
		# P-factor: nose-high, the down-going blade bites harder, off to one side.
		torque.y += pull * P_FACTOR * _prop_radius * sin(clampf(attack_now, -0.6, 0.6))
		# Gyroscope: the spinning propeller resists being tilted, at right angles.
		torque -= rotation.cross(Vector3(0.0, 0.0, -_prop_inertia * prop_rate))
	elif forward_speed > 1.0:
		# A dead propeller is a drag.
		force.z += 0.5 * density * forward_speed * forward_speed * _prop_disc * WINDMILL_DRAG
	if record:
		stall = stalled_share
		thrust = pull
	_force = force
	_torque = torque


## One lifting surface: where it is, which way is "up" for it, and what it
## does in the air it meets. Leaves its force (body axes) in _surface_force
## and returns how stalled it is (0..1).
func _surface(place: Vector3, normal: Vector3, area: float, incidence: float, lift_slope: float, best_lift: float,
		zero_lift_drag: float, induced: float, lift_boost: float, body_velocity: Vector3, rotation: Vector3,
		wash: float, sidewash: float) -> float:
	# The air this surface meets: the plane's motion, plus its own motion as
	# the plane rotates, plus whatever the propeller is throwing at it.
	var air: Vector3 = -(body_velocity + rotation.cross(place))
	air.z += wash
	air.x += sidewash
	var along: float = air.z
	var across: float = air.dot(normal)
	var speed_squared: float = along * along + across * across
	if speed_squared < 0.01:
		_surface_force = Vector3.ZERO
		return 0.0
	var speed: float = sqrt(speed_squared)
	var attack: float = atan2(across, along) + incidence
	# Attached flow: lift rises steadily with angle of attack.
	var attached: float = clampf(lift_slope * attack, -best_lift, best_lift)
	# Separated flow: a flat plate.
	var plate: float = 0.5 * FLAT_PLATE_NORMAL * sin(2.0 * attack)
	var break_angle: float = best_lift / lift_slope + STALL_OFFSET * STALL_SHARPNESS
	var separation: float = 1.0 / (1.0 + exp(-(absf(attack) - break_angle) / STALL_SHARPNESS))
	var lift: float = lerpf(attached, plate, separation) * lift_boost
	var drag: float = lerpf(zero_lift_drag + induced * attached * attached, zero_lift_drag + FLAT_PLATE_NORMAL * pow(sin(attack), 2.0), separation)
	# Lift acts at right angles to the airflow, drag along it.
	var lift_direction: Vector3 = (normal * along - Vector3.BACK * across) / speed
	var drag_direction: Vector3 = (Vector3.BACK * along + normal * across) / speed
	_surface_force = 0.5 * density * speed_squared * area * (lift_direction * lift + drag_direction * drag)
	return separation


## How much of full deflection a pilot can hold at [param speed].
func _lightness(speed: float, heavy_speed: float) -> float:
	return 1.0 / sqrt(1.0 + pow(speed / heavy_speed, 4.0))
