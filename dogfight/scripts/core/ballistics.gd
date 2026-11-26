class_name Ballistics
extends RefCounted
## Shared gunnery maths. The HUD lead reticle, the aim assist and the AI all call
## the same function, so "where the reticle says to shoot" is exactly where a
## bullet fired now will meet the target.


## Returns the world position to aim at so that a bullet leaving [param shooter_pos]
## now hits a target flying in a straight line.
## Bullets inherit the shooter's velocity (see PlaneActor._fire), so the intercept
## is solved in the shooter's moving frame: |rel_pos + rel_vel * t| = bullet_speed * t.
## Falls back to the target's current position when no intercept exists.
static func lead_point(
		shooter_pos: Vector3,
		shooter_vel: Vector3,
		target_pos: Vector3,
		target_vel: Vector3,
		bullet_speed: float) -> Vector3:
	var time: float = intercept_time(shooter_pos, shooter_vel, target_pos, target_vel, bullet_speed)
	if time < 0.0:
		return target_pos
	# In the shooter's frame the bullet flies straight at (rel_pos + rel_vel * t).
	return target_pos + (target_vel - shooter_vel) * time


## Time for a bullet fired now to reach the target, or -1.0 if it never can.
static func intercept_time(
		shooter_pos: Vector3,
		shooter_vel: Vector3,
		target_pos: Vector3,
		target_vel: Vector3,
		bullet_speed: float) -> float:
	var rel_pos: Vector3 = target_pos - shooter_pos
	var rel_vel: Vector3 = target_vel - shooter_vel
	var a: float = rel_vel.length_squared() - bullet_speed * bullet_speed
	var b: float = 2.0 * rel_pos.dot(rel_vel)
	var c: float = rel_pos.length_squared()
	if absf(a) < 0.0001:
		# Bullet and target equally fast: the quadratic degenerates to a line.
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


## Angle in radians between a nose direction and the direction to a point.
static func angle_off_nose(origin: Vector3, forward: Vector3, point: Vector3) -> float:
	var to_point: Vector3 = point - origin
	if to_point.length_squared() < 0.0001:
		return 0.0
	return forward.angle_to(to_point)
