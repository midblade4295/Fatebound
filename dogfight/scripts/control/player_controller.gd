class_name PlayerController
extends Node
## Drives one PlaneActor from the local player's input.
##
## It only reads Input *actions* (see GameSession for the names). The touch HUD
## presses those same actions, so keyboard, gamepad and touch all arrive here
## the same way and this script never references a HUD widget.
##
## It also picks the player's current target (the enemy nearest the nose). The
## HUD reads `plane.current_target` to label that enemy; nothing aims for the
## player. An optional aim assist exists (see aim_assist_enabled) but is off.

## Enemies further than this are never auto-targeted (metres).
const TARGET_RANGE: float = 1600.0
## Half-angle of the cone in front of the nose that is searched for a target.
const TARGET_CONE: float = deg_to_rad(32.0)
## Keeps the current target unless another is clearly better (prevents flicker).
const TARGET_STICKINESS: float = deg_to_rad(5.0)
const RETARGET_INTERVAL: float = 0.15
## Stick movement is raised to this power, so the first half of the travel
## gives about a third of the control.
const STICK_CURVE: float = 1.5
## Throttle lever travel per second while a throttle key is held.
const THROTTLE_KEY_RATE: float = 0.7

var plane: PlaneActor
## Supplies the list of planes to pick targets from.
var match_manager: MatchManager5v5
## Off by default: with it on, bullets fired within a few degrees of the
## correct lead are nudged onto it. The game is tuned for unassisted gunnery
## (no lead reticle, real drop and drag), so this is only an accessibility hook.
var aim_assist_enabled: bool = false

var _retarget_timer: float = 0.0


func _physics_process(delta: float) -> void:
	if plane == null or not is_instance_valid(plane):
		return
	if not plane.alive:
		plane.input.clear()
		plane.current_target = null
		return

	var steer: Vector2 = Vector2(
			Input.get_axis(GameSession.ACTION_STEER_LEFT, GameSession.ACTION_STEER_RIGHT),
			Input.get_axis(GameSession.ACTION_PITCH_DOWN, GameSession.ACTION_PITCH_UP))
	if Profile.invert_pitch:
		steer.y = -steer.y
	# A real stick is long: small movements near the middle are fine ones.
	plane.input.steer = Vector2(_shape(steer.x), _shape(steer.y))
	plane.input.rudder = Input.get_axis(GameSession.ACTION_RUDDER_LEFT, GameSession.ACTION_RUDDER_RIGHT)
	plane.input.firing = Input.is_action_pressed(GameSession.ACTION_FIRE)
	if Input.is_action_just_pressed(GameSession.ACTION_ENGINE):
		plane.input.press_engine()
	if Input.is_action_just_pressed(GameSession.ACTION_GEAR):
		plane.input.press_gear()
	# Keys nudge the throttle lever; the touch lever on the HUD sets it directly.
	var throttle_change: float = Input.get_axis(GameSession.ACTION_THROTTLE_DOWN, GameSession.ACTION_THROTTLE_UP)
	if throttle_change != 0.0:
		plane.input.throttle = clampf(plane.input.throttle + throttle_change * THROTTLE_KEY_RATE * delta, 0.0, 1.0)

	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = RETARGET_INTERVAL
		plane.current_target = _pick_target()
	_update_aim_assist()


func _shape(deflection: float) -> float:
	return signf(deflection) * pow(absf(deflection), STICK_CURVE)


## The enemy closest to the gun line, within range and the targeting cone.
func _pick_target() -> PlaneActor:
	if match_manager == null:
		return null
	var origin: Vector3 = plane.global_position
	var nose: Vector3 = plane.forward()
	var best: PlaneActor = null
	var best_angle: float = TARGET_CONE
	for other: PlaneActor in match_manager.get_planes():
		if not other.alive or not plane.is_hostile_to(other):
			continue
		var distance: float = origin.distance_to(other.global_position)
		if distance > TARGET_RANGE:
			continue
		var angle: float = Ballistics.angle_off_nose(origin, nose, other.global_position)
		if other == plane.current_target:
			angle -= TARGET_STICKINESS
		if angle < best_angle:
			best_angle = angle
			best = other
	return best


func _update_aim_assist() -> void:
	var enemy: PlaneActor = plane.current_target
	var usable: bool = aim_assist_enabled and enemy != null and is_instance_valid(enemy) and enemy.alive
	if not usable:
		plane.input.assist_active = false
		return
	plane.input.assist_point = Ballistics.lead_point(plane.global_position, plane.velocity,
			enemy.global_position, enemy.velocity, plane.stats.bullet_speed, plane.flight.density_ratio)
	plane.input.assist_active = true
