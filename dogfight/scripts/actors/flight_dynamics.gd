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
## Axes are Godot's: +X is the right wing, +Y is up, -Z is the nose.
## Units are SI: metres, kilograms, seconds, newtons, radians.

const GRAVITY: float = 9.81
## Sea-level air (kg/m^3). The battlefield is all below 2 km.
const AIR_DENSITY: float = 1.225

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
const FLAP_ANGLE: float = deg_to_rad(7.0)
const FLAP_CL_MAX: float = 0.32
const FLAP_DRAG: float = 0.055
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
## Share of the ideal (momentum-theory) static thrust it actually makes.
const STATIC_THRUST_SHARE: float = 0.5
## Propeller speed at full power (rad/s; about 1,250 rpm) and its inertia as a
## share of mass x radius^2.
const PROP_RATE: float = 131.0
const PROP_INERTIA_SHARE: float = 0.0032
## How much of the slipstream's extra speed reaches the tail and inner wing.
const SLIPSTREAM_AT_TAIL: float = 0.75
const SLIPSTREAM_AT_INNER_WING: float = 0.2
## Sideways speed the slipstream's spiral gives the air at the fin, as a share
## of the slipstream's extra speed.
const SLIPSTREAM_SPIRAL: float = 0.07
## How far off-centre (in propeller radii) the thrust moves per radian of
## angle of attack.
const P_FACTOR: float = 0.25
## Drag of a propeller windmilling on a stopped engine, as a coefficient on
## its disc area.
const WINDMILL_DRAG: float = 0.03
## The stall break sits this many "sharpnesses" past the angle where the
## straight part of the lift curve would reach its peak.
const STALL_OFFSET: float = 2.2
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

# --- State: integrated by step() -------------------------------------------------------
## Velocity in the world, m/s.
var velocity: Vector3 = Vector3.ZERO
## Orientation in the world.
var basis: Basis = Basis.IDENTITY
## Rotation rate about the plane's own axes, rad/s: x pitches the nose up,
## y yaws it left, z rolls the left wing down.
var angular_velocity: Vector3 = Vector3.ZERO

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

# --- Read-outs: filled in by step() --------------------------------------------------------
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
		thrust_factor: float = 1.0, roll: float = 1.0) -> void:
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
	_measure_performance()


## Puts the plane in the air at [param start_velocity], pointing as given, not
## rotating and trimmed for that speed.
func reset(start_basis: Basis, start_velocity: Vector3) -> void:
	basis = start_basis.orthonormalized()
	velocity = start_velocity
	angular_velocity = Vector3.ZERO
	airspeed = velocity.length()
	alpha = 0.0
	beta = 0.0
	load_factor = 1.0
	stall = 0.0
	settle_trim()


## Advances the plane by [param delta] seconds, in [param substeps] slices.
func step(delta: float, substeps: int = 2) -> void:
	var slice: float = delta / float(substeps)
	for _slice: int in range(substeps):
		_advance(slice)


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
		_improve_trim(maxf(airspeed, stall_speed(flaps) * SLOWEST_TRIM))
	var quick: float = 1.0 - exp(-delta / ELEVATOR_TRIM_TIME)
	var slow: float = 1.0 - exp(-delta / LATERAL_TRIM_TIME)
	trim.x = lerpf(trim.x, _trim_target.x, quick)
	trim.y = lerpf(trim.y, _trim_target.y, slow)
	trim.z = lerpf(trim.z, _trim_target.z, slow)


## Trims the plane for its present speed at once (after a respawn).
func settle_trim() -> void:
	var speed: float = maxf(airspeed, stall_speed(flaps) * SLOWEST_TRIM)
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

## Speed (m/s) below which the wing cannot hold the plane up in level flight,
## with the flaps at [param flap_setting] (0 up .. 1 down). Measured from the
## model itself, engine idling.
func stall_speed(flap_setting: float = 0.0) -> float:
	return lerpf(_clean_stall_speed, _flapped_stall_speed, clampf(flap_setting, 0.0, 1.0))


## Top speed in level flight at full power, m/s, clean and undamaged.
func level_top_speed() -> float:
	return _top_speed


## Best rate of climb at full power (m/s), and the airspeed that gives it.
func best_climb_rate() -> float:
	return _climb_rate


func best_climb_speed() -> float:
	return _climb_speed


## The most g the wing can pull at [param speed] before it stalls.
func available_load(speed: float) -> float:
	var slowest: float = stall_speed(flaps)
	return speed * speed / maxf(slowest * slowest, 1.0)


## How much stick (beyond the trimmed position) holds [param load] g at the
## present speed. An estimate for autopilots: it ignores the stall.
func elevator_for_load(load: float) -> float:
	return (load - 1.0) / _load_per_elevator


## Rolling along the ground at [param speed] with the nose [param attack]
## radians up: x = lift as a share of the plane's weight, y = what thrust less
## air drag gives along the ground (m/s^2).
func ground_roll(attack: float, speed: float) -> Vector2:
	# Counted without the help of the ground's air cushion: a plane that only
	# flies because it is a wingspan off the runway is not flying yet.
	var kept: float = ground_effect
	ground_effect = 0.0
	_loads(_flow(attack, maxf(speed, 0.0)), Vector3.ZERO, 0.0, 0.0, 0.0, true)
	ground_effect = kept
	var up: float = _force.y * cos(attack) - _force.z * sin(attack)
	var along: float = -_force.y * sin(attack) - _force.z * cos(attack)
	return Vector2(up / (mass * GRAVITY), along / mass)


## Angle of attack (radians, of the fuselage) at which the wing lets go.
func stall_alpha() -> float:
	return cl_max / WING_LIFT_SLOPE + STALL_OFFSET * STALL_SHARPNESS - WING_INCIDENCE


## Thrust (N) at full throttle and [param forward_speed], engine healthy.
func full_thrust(forward_speed: float) -> float:
	return _thrust_at(forward_speed, 1.0, 1.0)


## Flies the clean, undamaged aeroplane on paper to find its stalling speeds,
## top speed and best climb.
func _measure_performance() -> void:
	var key: String = "%.1f/%.3f/%.3f/%.0f/%.5f/%.3f/%.3f" % [mass, wing_area, wing_span, power, cd0, cl_max, static_thrust_factor]
	if _performance_cache.has(key):
		var known: PackedFloat32Array = _performance_cache[key]
		_clean_stall_speed = known[0]
		_flapped_stall_speed = known[1]
		_top_speed = known[2]
		_climb_rate = known[3]
		_climb_speed = known[4]
		return
	# Remember the state this borrows.
	var kept: Array[float] = [throttle, flaps, gear, engine_output, damage_drag, ground_effect]
	var kept_turning: bool = engine_turning
	var kept_trim_alpha: float = _trim_alpha
	var kept_trim_target: Vector3 = _trim_target
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
	engine_turning = kept_turning
	_trim_alpha = kept_trim_alpha
	_trim_target = kept_trim_target
	_performance_cache[key] = PackedFloat32Array([_clean_stall_speed, _flapped_stall_speed, _top_speed, _climb_rate, _climb_speed])


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
	alpha = atan2(-body_velocity.y, maxf(-body_velocity.z, 0.01)) if airspeed > 1.0 else 0.0
	beta = asin(clampf(body_velocity.x / maxf(airspeed, 1.0), -1.0, 1.0))
	_loads(body_velocity, angular_velocity,
			clampf(elevator + trim.x, -1.0, 1.0), clampf(aileron + trim.y, -1.0, 1.0), clampf(rudder + trim.z, -1.0, 1.0), true)
	load_factor = _force.y / (mass * GRAVITY)
	# --- Move ------------------------------------------------------------------------
	velocity += (basis * _force / mass + Vector3(0.0, -GRAVITY, 0.0)) * delta
	# --- Turn: Euler's equations for a rigid body ------------------------------------
	var momentum: Vector3 = Vector3(inertia.x * angular_velocity.x, inertia.y * angular_velocity.y, inertia.z * angular_velocity.z)
	var spin_up: Vector3 = _torque - angular_velocity.cross(momentum)
	angular_velocity += Vector3(spin_up.x / inertia.x, spin_up.y / inertia.y, spin_up.z / inertia.z) * delta
	var turn: float = angular_velocity.length() * delta
	if turn > 1.0e-7:
		basis = (basis * Basis(angular_velocity.normalized(), turn)).orthonormalized()


## Thrust (N) at [param forward_speed] for a throttle setting and engine health.
func _thrust_at(forward_speed: float, throttle_setting: float, output: float) -> float:
	var shaft_power: float = power * clampf(throttle_setting, 0.0, 1.0) * clampf(output, 0.0, 1.0)
	if shaft_power <= 0.0:
		return 0.0
	# Static thrust goes with power to the two-thirds; at speed, thrust is
	# power over speed. The propeller gives the lesser, blended smoothly.
	var standing: float = _static_thrust * pow(shaft_power / power, 2.0 / 3.0)
	var moving: float = PROP_EFFICIENCY * shaft_power / maxf(forward_speed, 5.0)
	return 1.0 / sqrt(1.0 / (standing * standing) + 1.0 / (moving * moving))


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
		slipstream = sqrt(forward_speed * forward_speed + 2.0 * pull / (AIR_DENSITY * _prop_disc)) - forward_speed
	# Heavy controls at speed.
	var aileron_reach: float = AILERON_TRAVEL * AILERON_POWER * roll_factor * _lightness(speed, AILERON_HEAVY_SPEED)
	var elevator_reach: float = ELEVATOR_TRAVEL * ELEVATOR_POWER * _lightness(speed, ELEVATOR_HEAVY_SPEED)
	var rudder_reach: float = RUDDER_TRAVEL * RUDDER_POWER * _lightness(speed, RUDDER_HEAVY_SPEED)
	var lift_boost: float = 1.0 + 0.14 * ground_effect
	var induced: float = _induced * (1.0 - 0.45 * ground_effect)

	var force: Vector3 = Vector3.ZERO
	var torque: Vector3 = Vector3.ZERO
	var stalled_share: float = 0.0
	var attack_now: float = atan2(-body_velocity.y, maxf(-body_velocity.z, 0.01))
	var wing_alpha: float = clampf(attack_now + WING_INCIDENCE, -0.35, 0.35)

	# --- Wing: four panels -------------------------------------------------------
	var panel_drag: float = cd0 * 0.45
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
		torque.x += 0.5 * AIR_DENSITY * panel_air * area * (wing_area / wing_span) * WING_PITCHING * (1.0 - _last_separation)

	# --- Tailplane: two halves, each with its elevator --------------------------
	var tail_drag: float = cd0 * 0.6
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
	var body_drag: float = cd0 * 0.4 + GEAR_DRAG * gear + damage_drag
	var air: Vector3 = -body_velocity
	var fuselage: Vector3 = 0.5 * AIR_DENSITY * air.length() * wing_area * Vector3(air.x * 0.28, air.y * 0.42, air.z * body_drag)
	force += fuselage
	# It acts a little behind the centre of gravity, which helps the tail.
	torque += Vector3(0.0, 0.0, 0.06 * wing_span).cross(Vector3(fuselage.x, fuselage.y, 0.0))
	# Whirling round, every part of the plane meets air that a point at its
	# centre does not: that soaks up rotation even when nothing is flying.
	var damping: float = 0.5 * AIR_DENSITY * wing_area * wing_span * wing_span * maxf(speed, 20.0)
	torque -= Vector3(rotation.x * 0.012, rotation.y * 0.012, rotation.z * 0.004) * damping

	# --- Propeller ---------------------------------------------------------------
	force.z -= pull
	if driven:
		var shaft_power: float = power * throttle * engine_output
		var prop_rate: float = PROP_RATE * lerpf(0.45, 1.0, throttle)
		# Torque: the engine turns the propeller one way and the airframe the other.
		torque.z += shaft_power / prop_rate
		# P-factor: nose-high, the down-going blade bites harder, off to one side.
		torque.y += pull * P_FACTOR * _prop_radius * sin(clampf(attack_now, -0.6, 0.6))
		# Gyroscope: the spinning propeller resists being tilted, at right angles.
		torque -= rotation.cross(Vector3(0.0, 0.0, -_prop_inertia * prop_rate))
	elif forward_speed > 1.0:
		# A dead propeller is a drag.
		force.z += 0.5 * AIR_DENSITY * forward_speed * forward_speed * _prop_disc * WINDMILL_DRAG
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
	_surface_force = 0.5 * AIR_DENSITY * speed_squared * area * (lift_direction * lift + drag_direction * drag)
	return separation


## How much of full deflection a pilot can hold at [param speed].
func _lightness(speed: float, heavy_speed: float) -> float:
	return 1.0 / sqrt(1.0 + pow(speed / heavy_speed, 4.0))
