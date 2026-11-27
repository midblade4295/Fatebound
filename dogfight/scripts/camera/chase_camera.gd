class_name ChaseCamera
extends Node3D
## Third-person chase camera that sits behind and slightly above the tail.
##
## Scene tree (scenes/camera/ChaseCamera.tscn):
##   ChaseCamera (Node3D, this script)   - free in the world, never parented to the plane
##   └─ Pivot (Node3D)                   - lagged copy of the plane's position/orientation
##      └─ SpringArm3D                   - pulls the camera in if a cliff gets in the way
##         └─ Camera3D
##
## Feel comes from four separate pieces, each with its own export group:
##  - Rotation lag: the pivot slerps toward the plane's heading, so in a hard
##    turn the plane swings across the screen before the camera catches up.
##  - Position lag: only the *sideways/vertical* error is smoothed. The camera
##    is carried along at the plane's velocity first, so cruising produces no
##    lag at all and the plane does not shrink into the distance at speed.
##  - Speed FOV: field of view and arm length open up with speed.
##  - Trauma shake: add_trauma() from gunfire/hits; shake = trauma squared.
##  - Looking around: look_by() swings the camera round the plane, as far as
##    looking straight back over the tail or down from above. It is only the
##    view that turns, never the plane. When the pilot lets go the camera
##    waits a moment and then eases back behind the tail.
##
## Runs in _process and reads the plane's *interpolated* transform, so it is
## smooth at any refresh rate even though the plane moves at the physics rate.

@export_group("Follow")
## Metres from the pivot back to the camera at cruise speed.
@export var follow_distance: float = 13.5
## How far above the plane's centre the pivot sits.
@export var height_offset: float = 2.6
## Degrees the arm is tilted up, so the camera looks slightly down over the tail.
@export_range(0.0, 30.0) var arm_pitch_deg: float = 8.0
## Extra arm length at top/dive speed, as a fraction of follow_distance.
@export_range(0.0, 1.0) var speed_pullback: float = 0.22

@export_group("Lag")
## Higher = stiffer. 1/s rate at which the pivot catches up with position error.
@export var position_stiffness: float = 7.0
## Higher = stiffer. 1/s rate at which the pivot catches up with rotation.
@export var rotation_stiffness: float = 4.5
## Hard limit on positional lag so the plane can never leave the frame.
@export var max_position_lag: float = 5.0
## 0 keeps the horizon level, 1 rolls the camera fully with the plane's bank.
@export_range(0.0, 1.0) var roll_follow: float = 0.3

@export_group("Field Of View")
@export_range(40.0, 100.0) var base_fov: float = 66.0
## Degrees added as speed goes from cruise to maximum dive speed.
@export var speed_fov_boost: float = 12.0
@export var fov_stiffness: float = 3.5

@export_group("Look Around")
## Radians the view turns per pixel of drag.
@export var look_speed: float = 0.006
## How far up and down the camera can be taken (degrees above / below the tail).
@export_range(0.0, 89.0) var look_up_limit_deg: float = 70.0
@export_range(0.0, 60.0) var look_down_limit_deg: float = 20.0
## Seconds after letting go before the view starts back, and how fast it goes (1/s).
@export var look_return_delay: float = 0.7
@export var look_return_rate: float = 4.0

@export_group("Shake")
@export var trauma_decay: float = 1.8
@export var max_shake_offset: float = 0.45
@export var max_shake_roll_deg: float = 2.2
@export var shake_frequency: float = 26.0
@export var fire_trauma: float = 0.05
@export var fire_trauma_cap: float = 0.28
@export var hit_trauma: float = 0.42

var target: PlaneActor

var _smoothed_position: Vector3 = Vector3.ZERO
var _smoothed_basis: Basis = Basis.IDENTITY
var _trauma: float = 0.0
var _shake_time: float = 0.0
var _noise: FastNoiseLite = FastNoiseLite.new()
## Where the pilot is looking, relative to straight ahead from behind the
## tail: x = round the plane (radians, positive = camera swings to the plane's
## right side), y = up over it.
var _look: Vector2 = Vector2.ZERO
var _look_held: bool = false
var _look_idle: float = 0.0

@onready var camera: Camera3D = $Pivot/SpringArm3D/Camera3D
@onready var _pivot: Node3D = $Pivot
@onready var _arm: SpringArm3D = $Pivot/SpringArm3D


func _ready() -> void:
	# The rig is driven every rendered frame from an already-interpolated
	# target, so the engine must not interpolate it a second time.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 1.0
	_arm.spring_length = follow_distance
	_arm.rotation = Vector3(-deg_to_rad(arm_pitch_deg), 0.0, 0.0)
	_arm.collision_mask = PlaneActor.COLLISION_LAYER_WORLD
	camera.fov = base_fov
	camera.current = true
	# The camera is the ears. Tracking its velocity lets planes that pass it
	# drop in pitch as they go by.
	camera.doppler_tracking = Camera3D.DOPPLER_TRACKING_IDLE_STEP


## Starts following [param plane] and hooks its fire/hit events up to the shake.
func set_target(plane: PlaneActor) -> void:
	if target != null and is_instance_valid(target):
		target.shot_fired.disconnect(_on_target_shot_fired)
		target.damaged.disconnect(_on_target_damaged)
		target.respawned.disconnect(_on_target_respawned)
	target = plane
	if target == null:
		return
	target.shot_fired.connect(_on_target_shot_fired)
	target.damaged.connect(_on_target_damaged)
	target.respawned.connect(_on_target_respawned)
	snap_to_target()


## Jumps straight behind the target with no lag (spawn, respawn, target swap).
func snap_to_target() -> void:
	if target == null or not is_instance_valid(target):
		return
	var target_transform: Transform3D = target.global_transform
	_smoothed_basis = _desired_basis(target_transform.basis)
	_smoothed_position = target_transform.origin + Vector3.UP * height_offset
	_trauma = 0.0
	_look = Vector2.ZERO
	_apply_rig()


## A finger has gone down to look around: the view stops returning.
func begin_look() -> void:
	_look_held = true


## Swings the view by [param pixels] of drag (right and down positive). The
## scene follows the finger, as it does in the hangar.
func look_by(pixels: Vector2) -> void:
	_look_idle = 0.0
	_look.x = wrapf(_look.x - pixels.x * look_speed, -PI, PI)
	_look.y = clampf(_look.y + pixels.y * look_speed, -deg_to_rad(look_down_limit_deg), deg_to_rad(look_up_limit_deg))


## The finger has lifted: after a moment the view eases back behind the tail.
func end_look() -> void:
	_look_held = false
	_look_idle = 0.0


## Where the pilot is looking: x = radians round the plane, y = radians up
## over it. Zero is the normal view from behind the tail.
func look_angles() -> Vector2:
	return _look


## Adds camera shake. 0.0-1.0; the visible shake is trauma squared, so small
## values (gunfire) are a subtle buzz and big ones (hits) are a real jolt.
func add_trauma(amount: float, cap: float = 1.0) -> void:
	_trauma = minf(maxf(_trauma, minf(_trauma + amount, cap)), 1.0)


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	_trauma = maxf(_trauma - trauma_decay * delta, 0.0)
	_shake_time += delta
	if not _look_held and _look != Vector2.ZERO:
		_look_idle += delta
		if _look_idle >= look_return_delay:
			_look = _look.lerp(Vector2.ZERO, 1.0 - exp(-look_return_rate * delta))
			if _look.length() < 0.002:
				_look = Vector2.ZERO

	if not target.alive:
		# Death cam: hold position and drift slowly around the wreck.
		_smoothed_basis = Basis(Vector3.UP, 0.3 * delta) * _smoothed_basis
		_update_fov(delta, 0.0)
		_apply_rig()
		return

	var target_transform: Transform3D = target.get_global_transform_interpolated()
	var anchor: Vector3 = target_transform.origin + Vector3.UP * height_offset

	# Rotation lag.
	var rotation_blend: float = 1.0 - exp(-rotation_stiffness * delta)
	_smoothed_basis = _smoothed_basis.slerp(_desired_basis(target_transform.basis), rotation_blend).orthonormalized()

	# Position lag: ride along with the plane, then ease out the remaining error.
	_smoothed_position += target.velocity * delta
	_smoothed_position = _smoothed_position.lerp(anchor, 1.0 - exp(-position_stiffness * delta))
	var lag: Vector3 = _smoothed_position - anchor
	if lag.length() > max_position_lag:
		_smoothed_position = anchor + lag.normalized() * max_position_lag

	# Speed feel: longer arm and wider lens the faster we go.
	var top_speed: float = maxf(target.stats.top_speed, 1.0)
	var speed_factor: float = clampf((target.speed - top_speed * 0.85) / (top_speed * 0.6), 0.0, 1.0)
	var arm_target: float = follow_distance * (1.0 + speed_pullback * speed_factor)
	_arm.spring_length = lerpf(_arm.spring_length, arm_target, 1.0 - exp(-fov_stiffness * delta))
	_update_fov(delta, speed_factor)
	_apply_rig()


## Heading the pivot wants: the plane's yaw and pitch, with only part of its roll.
func _desired_basis(target_basis: Basis) -> Basis:
	var plane_basis: Basis = target_basis.orthonormalized()
	var nose: Vector3 = -plane_basis.z
	var up: Vector3 = Vector3.UP if absf(nose.y) < 0.98 else plane_basis.y
	var level_basis: Basis = Basis.looking_at(nose, up)
	return level_basis.slerp(plane_basis, roll_follow)


func _update_fov(delta: float, speed_factor: float) -> void:
	var fov_target: float = base_fov + speed_fov_boost * speed_factor
	camera.fov = lerpf(camera.fov, fov_target, 1.0 - exp(-fov_stiffness * delta))


func _apply_rig() -> void:
	# Looking around turns the rig about the plane; the arm and the camera on
	# the end of it come round with it.
	var look: Basis = Basis(Vector3.UP, _look.x) * Basis(Vector3.RIGHT, -_look.y)
	_pivot.global_transform = Transform3D(_smoothed_basis * look, _smoothed_position)
	# Shake is applied to the camera itself so it never fights the follow maths.
	var shake: float = _trauma * _trauma
	var sample: float = _shake_time * shake_frequency
	camera.h_offset = max_shake_offset * shake * _noise.get_noise_2d(sample, 0.0)
	camera.v_offset = max_shake_offset * shake * _noise.get_noise_2d(0.0, sample)
	camera.rotation.z = deg_to_rad(max_shake_roll_deg) * shake * _noise.get_noise_2d(sample, 100.0)


func _on_target_shot_fired(_plane: PlaneActor) -> void:
	add_trauma(fire_trauma, fire_trauma_cap)


func _on_target_damaged(_victim: PlaneActor, amount: float, _attacker: PlaneActor) -> void:
	var severity: float = clampf(amount / maxf(target.stats.max_hp * 0.05, 1.0), 0.4, 1.0)
	add_trauma(hit_trauma * severity)


func _on_target_respawned(_plane: PlaneActor) -> void:
	snap_to_target()
