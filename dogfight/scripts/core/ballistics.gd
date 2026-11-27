class_name Ballistics
extends RefCounted
## How bullets fly, and the gunnery maths that goes with it.
##
## A bullet leaves the muzzle at the gun's muzzle speed *plus* the firing
## plane's own velocity, then:
##  - gravity pulls it down (it drops about 1.7 m by 250 m, 5 m by 420 m), and
##  - air drag slows it (at sea level it has lost roughly a fifth of its speed
##    after 1 s), which also means it hits softer at long range. Drag is the
##    air's doing, so it scales with the air's density: every function takes
##    [code]air[/code], the density there as a share of sea level's. High up a
##    bullet keeps its speed longer and shoots flatter.
##
## BulletSystem integrates exactly this model every physics tick. The bots (and
## the optional player aim assist) use lead_point() below, which solves the
## same model, so a shot aimed at that point really meets the target.

## Downward acceleration on bullets, m/s^2.
const GRAVITY: float = 9.8
## Linear air drag at sea level: fraction of speed lost per second.
const DRAG: float = 0.22
## Drag never quite reaches nothing in these formulas (they divide by it).
const THINNEST_AIR: float = 0.05
## Beyond this share of the bullet's theoretical maximum reach, treat the
## target as out of range rather than return a wild solution.
const MAX_REACH_FRACTION: float = 0.95


## Advances a bullet's velocity by one time step (gravity + drag).
static func step(velocity: Vector3, delta: float, air: float = 1.0) -> Vector3:
	return velocity + (Vector3.DOWN * GRAVITY - velocity * drag_in(air)) * delta


## The drag rate in air of that density (1.0 = sea level).
static func drag_in(air: float) -> float:
	return DRAG * maxf(air, THINNEST_AIR)


## The air's density at [param height], as a share of sea level's.
static func air_at(height: float) -> float:
	return FlightDynamics.density_at(height) / FlightDynamics.AIR_DENSITY


## Drag turns "seconds flown" into fewer "seconds' worth of distance". A bullet
## launched at velocity v has moved v * drag_time(t) after t seconds (before
## gravity). With no drag this would simply be t.
static func drag_time(time: float, air: float = 1.0) -> float:
	var drag: float = drag_in(air)
	return (1.0 - exp(-drag * time)) / drag


## How far a bullet has fallen after [param time] seconds of flight.
static func drop_after(time: float, air: float = 1.0) -> float:
	return GRAVITY * (time - drag_time(time, air)) / drag_in(air)


## Seconds for a bullet launched at [param speed] to cover [param distance],
## or -1.0 if drag stops it first.
static func time_to_travel(distance: float, speed: float, air: float = 1.0) -> float:
	var needed: float = distance / maxf(speed, 0.001)
	var drag: float = drag_in(air)
	if needed * drag >= MAX_REACH_FRACTION:
		return -1.0
	return -log(1.0 - drag * needed) / drag


## Where a bullet is, relative to its launch point, after [param time] seconds.
static func bullet_offset(launch_velocity: Vector3, time: float, air: float = 1.0) -> Vector3:
	return launch_velocity * drag_time(time, air) + Vector3.DOWN * drop_after(time, air)


## Returns the world position to point the guns at so that a bullet fired now
## hits a target flying in a straight line: ahead of it for its motion and
## above it for bullet drop. Falls back to the target's current position when
## the target cannot be reached.
static func lead_point(
		shooter_pos: Vector3,
		shooter_vel: Vector3,
		target_pos: Vector3,
		target_vel: Vector3,
		bullet_speed: float,
		air: float = 1.0) -> Vector3:
	var time: float = intercept_time(shooter_pos, shooter_vel, target_pos, target_vel, bullet_speed, air)
	if time < 0.0:
		return target_pos
	return shooter_pos + _muzzle_displacement(shooter_pos, shooter_vel, target_pos, target_vel, time, air)


## Time for a bullet fired now to reach the target, or -1.0 if it never can.
static func intercept_time(
		shooter_pos: Vector3,
		shooter_vel: Vector3,
		target_pos: Vector3,
		target_vel: Vector3,
		bullet_speed: float,
		air: float = 1.0) -> float:
	var drag: float = drag_in(air)
	# Start from the classic no-drag, no-gravity answer...
	var time: float = _vacuum_intercept_time(shooter_pos, shooter_vel, target_pos, target_vel, bullet_speed)
	if time < 0.0:
		return -1.0
	# ...then refine. Each pass asks "how far must the muzzle velocity alone
	# carry the bullet to be at the target at this time?" and converts that
	# distance back into a flight time under drag. Bullets are much faster
	# than planes, so this settles within a few passes.
	for _pass: int in range(8):
		var needed: float = _muzzle_displacement(shooter_pos, shooter_vel, target_pos, target_vel, time, air).length() / maxf(bullet_speed, 0.001)
		if needed * drag >= MAX_REACH_FRACTION:
			return -1.0
		var refined: float = -log(1.0 - drag * needed) / drag
		var settled: bool = absf(refined - time) < 0.0005
		time = refined
		if settled:
			break
	return time


## Angle in radians between a nose direction and the direction to a point.
static func angle_off_nose(origin: Vector3, forward: Vector3, point: Vector3) -> float:
	var to_point: Vector3 = point - origin
	if to_point.length_squared() < 0.0001:
		return 0.0
	return forward.angle_to(to_point)


## The displacement the *muzzle* part of the bullet's velocity has to provide
## for the bullet to be where the target is at [param time]. Everything else
## acting on the bullet is moved to the other side of the equation: the share
## of the shooter's velocity it inherited, and gravity (hence the upward term).
## Its direction is the direction to aim.
static func _muzzle_displacement(shooter_pos: Vector3, shooter_vel: Vector3, target_pos: Vector3, target_vel: Vector3, time: float, air: float = 1.0) -> Vector3:
	return target_pos + target_vel * time - shooter_pos - shooter_vel * drag_time(time, air) + Vector3.UP * drop_after(time, air)


static func _vacuum_intercept_time(shooter_pos: Vector3, shooter_vel: Vector3, target_pos: Vector3, target_vel: Vector3, bullet_speed: float) -> float:
	var rel_pos: Vector3 = target_pos - shooter_pos
	var rel_vel: Vector3 = target_vel - shooter_vel
	var a: float = rel_vel.length_squared() - bullet_speed * bullet_speed
	var b: float = 2.0 * rel_pos.dot(rel_vel)
	var c: float = rel_pos.length_squared()
	if absf(a) < 0.0001:
		if absf(b) < 0.0001:
			return -1.0
		var linear_time: float = -c / b
		return linear_time if linear_time > 0.0 else -1.0
	var discriminant: float = b * b - 4.0 * a * c
	if discriminant < 0.0:
		return -1.0
	var root: float = sqrt(discriminant)
	var t1: float = (-b - root) / (2.0 * a)
	var t2: float = (-b + root) / (2.0 * a)
	var best: float = -1.0
	if t1 > 0.0:
		best = t1
	if t2 > 0.0 and (best < 0.0 or t2 < best):
		best = t2
	return best
