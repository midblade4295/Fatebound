class_name FlightPilot
extends RefCounted
## How to fly an aeroplane somewhere with a stick: the hands of every bot, and
## of the invisible instructor who turns a player back into the battle area.
##
## An aeroplane cannot be pointed. It is turned by rolling until its lift
## points the way you want to go and then pulling, and all the while part of
## that lift has to go on holding it up. So the pilot here thinks in lift:
## "to bend my path toward that point and not fall, the wings must pull this
## hard in this direction". Then: roll until the top of the plane faces that
## way, and pull as much of it as is lined up yet.
##
## It knows what a pilot knows: the stalling speed, and roughly how much stick
## is how much g. It does not reach into the flight model, and the bots stall
## and spin like anyone else when they ask for too much.

## Wanted turn rate (rad/s) per radian the nose is off the mark.
const TURN_GAIN: float = 2.0
## Wanted roll rate (rad/s) per radian of bank error, and the most ever asked for.
const ROLL_GAIN: float = 3.5
const MAX_ROLL_RATE: float = 2.2
## Aileron per rad/s of roll rate still to find.
const ROLL_STICK: float = 0.55
## Elevator per g still to find, on top of the estimate for the g wanted.
const LOAD_STICK: float = 0.12
## Share of the lift the wing could make that the pilot will use.
const LIFT_IN_HAND: float = 0.82
## The pilot backs off as the angle of attack passes this share of the stall
## (elevator per radian beyond it).
const ATTACK_LIMIT: float = 0.8
const ATTACK_STICK: float = 8.0
## Pulling to the buffet: the share of the wing's most lift that is held
## there, how far ahead the hand feels the angle of attack coming (s), and
## stick per radian of angle of attack still in hand.
const BUFFET_LIFT: float = 0.95
const BUFFET_FORESIGHT: float = 0.18
const BUFFET_STICK: float = 7.0
## On the ground: the share of the side load that would lift a wheel that a
## pilot will turn at, where below it he starts easing the rudder bar, and
## how light (as a share of an even load) he lets the inside wheel get.
const LEVEL_STICK: float = 3.0
const LEVEL_DAMPING: float = 0.3
const WHEEL_SIDE_SHARE: float = 0.7
const WHEEL_SIDE_EASE: float = 0.5
const LIGHT_WHEEL: float = 0.45
## Lift across the nose smaller than this (g) says nothing about which way
## up to be.
const ROLL_MEANING: float = 0.35
## Turning round after something behind, the pilot climbs or dives no more
## steeply than this (rise over run).
const BEHIND_SLOPE: float = 0.25
## Aiming the nose: within FINE_AIM_START of the mark, sideways corrections
## are made with rudder (RUDDER_AIM of it per radian off) and RUDDER_SHARE of
## the banking that would otherwise be asked for is left out. That fades away
## by FINE_AIM_END.
const FINE_AIM_START: float = deg_to_rad(5.0)
const FINE_AIM_END: float = deg_to_rad(14.0)
const RUDDER_AIM: float = 5.0
const RUDDER_SHARE: float = 0.75
## The least g the pilot will push to while he is still rolling the lift round.
const LEAST_LOAD: float = -0.3


## A pilot pulling hard pulls to the buffet and holds it there by feel: the
## wing is making all the lift it can, and more stick would only stall it.
## This is that feel, for a hand on a touch screen that has none. Given how
## far back the stick is being held ([param stick], 0..1), it returns how far
## back it actually goes: no further than holds the wing at
## [param edge] (an angle of attack, radians). [param attack_rate] is how fast
## the angle of attack is rising (rad/s), so a snatched pull is checked
## before it overshoots. It never pushes: with the wing already past the
## edge the stick only comes back to where it was trimmed, and the nose
## comes down by itself.
static func pull_to_the_buffet(flight: FlightDynamics, stick: float, edge: float, attack_rate: float) -> float:
	if stick <= 0.0:
		return stick
	var speed: float = maxf(flight.airspeed, 15.0)
	var holding: float = flight.elevator_for_load(flight.available_load(speed) * BUFFET_LIFT)
	var coming: float = flight.alpha + attack_rate * BUFFET_FORESIGHT
	return clampf(holding + (edge - coming) * BUFFET_STICK, 0.0, stick)


## Aileron (+ rolls right) that keeps the wings level, as a pilot's hands do
## on the take-off and landing run.
static func hold_wings_level(flight: FlightDynamics) -> float:
	# Right wing down is positive here; roll rate is positive rolling left.
	var right_wing_down: float = atan2(-flight.basis.x.y, flight.basis.y.y)
	return clampf(-right_wing_down * LEVEL_STICK + flight.angular_velocity.z * LEVEL_DAMPING, -1.0, 1.0)


## On its wheels: [param feet] (the rudder bar, + swings the nose right) as
## far as a pilot would push it. He turns as tightly as the undercarriage will
## take and no tighter: the bar is eased as the swing builds toward the side
## load that would lift the inside wheel (WHEEL_SIDE_SHARE of it), and when he
## feels that wheel go light. Rudder against the swing is never held back.
static func feet_within_the_wheels(flight: FlightDynamics, feet: float) -> float:
	if is_zero_approx(feet) or flight.weight_on_ground <= 0.0:
		return feet
	var ground_speed: float = Vector2(flight.velocity.x, flight.velocity.z).length()
	# (Yaw rate is positive to the left; the bar is positive to the right.)
	var swing: float = maxf(-flight.angular_velocity.y * signf(feet), 0.0)
	var side_load: float = swing * ground_speed / FlightDynamics.GRAVITY
	var limit: float = flight.wheel_side_limit() * WHEEL_SIDE_SHARE
	var room: float = 1.0 - smoothstep(limit * WHEEL_SIDE_EASE, limit, side_load)
	# Turning right leans the plane on its left wheel and lightens the right.
	var left: float = flight.contact_load[FlightDynamics.Contact.LEFT_WHEEL]
	var right: float = flight.contact_load[FlightDynamics.Contact.RIGHT_WHEEL]
	var even: float = (left + right) * 0.5
	if left > 0.0 and right > 0.0:
		var inside: float = (right if feet > 0.0 else left) / even
		room = minf(room, smoothstep(LIGHT_WHEEL * 0.4, LIGHT_WHEEL, inside))
	return feet * room


## Stick positions that bend the plane's flight path toward [param direction]
## (a direction in the world, any length) without pulling more than
## [param max_load] g: x = aileron (+ rolls right), y = elevator (+ pulls),
## z = rudder (0 leaves it to the plane's own feet, which keep the ball centred).
##
## With [param aim_nose] it is the nose, not the flight path, that is brought
## onto the direction: the two differ by the angle of attack, which is several
## degrees in a hard turn, and guns fire where the nose points. Close to the
## mark the pilot then stops banking for every small correction and nudges the
## nose across with rudder instead.
static func fly_toward(plane: PlaneActor, direction: Vector3, max_load: float, aim_nose: bool = false) -> Vector3:
	var flight: FlightDynamics = plane.flight
	var speed: float = maxf(flight.airspeed, 15.0)
	var path: Vector3 = flight.velocity / speed if flight.airspeed > 15.0 else -flight.basis.z
	var wanted: Vector3 = direction.normalized()
	var pointer: Vector3 = -flight.basis.z if aim_nose else path
	var along: float = wanted.dot(pointer)
	var across: Vector3 = wanted - pointer * along
	var off: float = atan2(across.length(), along)
	var rudder: float = 0.0
	if aim_nose and off < FINE_AIM_END:
		# Fine aim: how far the mark is to the right of the nose, in the
		# plane's own axes. The sideways part of it is the rudder's job.
		var fine: float = 1.0 - smoothstep(FINE_AIM_START, FINE_AIM_END, off)
		var mark: Vector3 = flight.basis.transposed() * wanted
		var right_of_nose: float = atan2(mark.x, -mark.z)
		rudder = clampf(right_of_nose * RUDDER_AIM, -1.0, 1.0) * fine
		across -= flight.basis.x * across.dot(flight.basis.x) * fine * RUDDER_SHARE
	if along < 0.0:
		# It is behind. Go round on the level, a little up or down toward it,
		# rather than over the top or (far worse, low down) underneath.
		var level: Vector3 = Vector3(across.x, 0.0, across.z)
		if level.length() < 0.05:
			level = Vector3(flight.basis.x.x, 0.0, flight.basis.x.z)
		across = level.normalized() + Vector3.UP * clampf(wanted.y, -BEHIND_SLOPE, BEHIND_SLOPE)
	var gravity: float = FlightDynamics.GRAVITY
	# What the wings can give at this speed, and what the pilot will ask of them.
	var limit: float = clampf(minf(max_load, flight.available_load(speed) * LIFT_IN_HAND), 0.3, 9.0)
	var turn: Vector3 = Vector3.ZERO
	if across.length() > 0.0001:
		turn = across.normalized() * minf(TURN_GAIN * off * speed, limit * gravity)
	# Holding the path up against gravity comes out of the same lift.
	var hold: Vector3 = (Vector3.UP - path * path.y) * gravity
	var lift: Vector3 = (turn + hold).limit_length(limit * gravity)
	var lift_in_plane: Vector3 = flight.basis.transposed() * lift
	var sticks: Vector3 = _fly_lift(flight, lift_in_plane, limit)
	sticks.z = rudder
	return sticks


## Wings level (or as near as the path allows), holding [param load] g.
## For the moments when nothing matters but not hitting the ground.
static func pull_up(plane: PlaneActor, load: float) -> Vector3:
	var flight: FlightDynamics = plane.flight
	var speed: float = maxf(flight.airspeed, 15.0)
	var limit: float = clampf(minf(load, flight.available_load(speed) * LIFT_IN_HAND), 0.3, 9.0)
	var lift_in_plane: Vector3 = flight.basis.transposed() * (Vector3.UP * limit * FlightDynamics.GRAVITY)
	return _fly_lift(flight, lift_in_plane, limit)


## Stick positions for a plane upset or spinning: throttle is the caller's
## business; this centres the ailerons, pushes the stick forward to unstall
## the wing and stands on the rudder against the turn.
static func recover_spin(plane: PlaneActor) -> Vector3:
	var flight: FlightDynamics = plane.flight
	return Vector3(0.0, -0.5, clampf(flight.angular_velocity.y * 3.0, -1.0, 1.0))


## Roll the top of the plane toward [param lift_in_plane] (the lift wanted,
## in the plane's own axes, m/s^2) and pull what is lined up.
static func _fly_lift(flight: FlightDynamics, lift_in_plane: Vector3, limit: float) -> Vector3:
	var gravity: float = FlightDynamics.GRAVITY
	# Positive: the lift is wanted further to the right, so roll right.
	var bank_error: float = atan2(lift_in_plane.x, lift_in_plane.y)
	var meaning: float = clampf(Vector2(lift_in_plane.x, lift_in_plane.y).length() / (ROLL_MEANING * gravity), 0.0, 1.0)
	var roll_wanted: float = clampf(ROLL_GAIN * bank_error * meaning, -MAX_ROLL_RATE, MAX_ROLL_RATE)
	var roll_now: float = -flight.angular_velocity.z
	var aileron: float = clampf((roll_wanted - roll_now) * ROLL_STICK, -1.0, 1.0)
	# Pull only the part of the lift the plane is already facing: none of it
	# while it is still rolling over, which is also when it rolls fastest.
	var load: float = clampf(lift_in_plane.y / gravity, LEAST_LOAD, limit)
	var elevator: float = flight.elevator_for_load(load) + LOAD_STICK * (load - flight.load_factor)
	var edge: float = flight.stall_alpha() * ATTACK_LIMIT
	if flight.alpha > edge:
		elevator -= (flight.alpha - edge) * ATTACK_STICK
	return Vector3(aileron, clampf(elevator, -1.0, 1.0), 0.0)
