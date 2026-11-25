extends SkeletonModifier3D
## Makes a rigged soldier handle his musket properly.
##
## The body (legs, hips, spine, head) comes from the animation clips. This modifier runs after
## them every frame: it moves the musket through the positions of the manual of arms and then
## places the hands on it with two-bone inverse kinematics, so the musket is always actually
## held, whatever the clip's own arms are doing.
##
## Positions are worked out in the model's own space (Y up, facing +Z, the soldier's right is
## -X, metres at the rig's 1.7 m height) and converted into the skeleton's space.

enum Drill {
	NONE,       # no musket (thrown away in a rout)
	SHOULDER,   # marching: sloped on the right shoulder, butt in the right hand
	PORT,       # standing ready: diagonally across the chest
	AIM,        # levelled from the right shoulder
	RECOIL,     # the instant after firing
	LOAD,       # butt on the ground, right hand working the ramrod
	CHARGE,     # levelled at the hip, bayonet forward
	DROPPED,    # lying where it fell
}

const LENGTH := 1.3          # musket with bayonet, metres
const GRIP_T := 0.24         # where the right hand holds it, as a fraction from the butt
const FORE_T := 0.52         # where the left hand holds it
const BLEND := 11.0

var musket: Node3D
var drill: int = Drill.PORT
var jab: float = 0.0         # 0..1, a forward thrust added to CHARGE

var _pending: int = Drill.PORT
var _delay: float = 0.0
var _clock: float = 0.0
var _ready_done: bool = false
var _to_skel: Transform3D
var _to_model: Transform3D
var _hips: int
var _arm_r: int
var _fore_r: int
var _hand_r: int
var _arm_l: int
var _fore_l: int
var _hand_l: int
var _shoulder_r: Vector3     # model space, at rest
var _shoulder_l: Vector3
var _hips_rest: Vector3      # skeleton space
var _thick: float = 0.05
var _pos: Vector3
var _rot: Quaternion
var _weight_r: float = 1.0
var _weight_l: float = 1.0
var _shown: float = 1.0
var _first: bool = true


## Call once, after the modifier and the musket (already scaled to LENGTH along its X axis, in
## model units) are children of the skeleton. to_model converts skeleton space to model space.
func setup(sk: Skeleton3D, to_model: Transform3D, musket_node: Node3D, thickness: float) -> bool:
	if sk == null:
		return false
	_to_model = to_model
	_to_skel = to_model.affine_inverse()
	musket = musket_node
	_thick = thickness
	_hips = sk.find_bone("Hips")
	_arm_r = sk.find_bone("RightArm")
	_fore_r = sk.find_bone("RightForeArm")
	_hand_r = sk.find_bone("RightHand")
	_arm_l = sk.find_bone("LeftArm")
	_fore_l = sk.find_bone("LeftForeArm")
	_hand_l = sk.find_bone("LeftHand")
	for b: int in [_hips, _arm_r, _fore_r, _hand_r, _arm_l, _fore_l, _hand_l]:
		if b < 0:
			return false
	_shoulder_r = to_model * sk.get_bone_global_rest(_arm_r).origin
	_shoulder_l = to_model * sk.get_bone_global_rest(_arm_l).origin
	_hips_rest = sk.get_bone_global_rest(_hips).origin
	_ready_done = true
	return true


## Changes position after a short delay, so a rank does not move as one machine.
func set_drill(next: int, delay: float = 0.0) -> void:
	if next == _pending:
		return
	_pending = next
	_delay = delay


func snap_drill(next: int) -> void:
	_pending = next
	_delay = 0.0
	drill = next


# --- The positions ---------------------------------------------------------------------------

## For a drill position: [reference point on the musket (fraction from the butt), where that
## point goes, the way the muzzle points, which way the lock faces, right weight, left weight].
func _target(which: int) -> Array:
	var mid := (_shoulder_r + _shoulder_l) * 0.5
	match which:
		Drill.SHOULDER:
			return [0.03, _shoulder_r + Vector3(-0.01, -0.5, 0.13), Vector3(0.03, 0.96, -0.27), Vector3(0, 0, 1), 1.0, 0.0]
		Drill.AIM:
			return [0.0, _shoulder_r + Vector3(0.05, -0.03, 0.05), Vector3(0.07, -0.01, 1.0), Vector3.UP, 1.0, 1.0]
		Drill.RECOIL:
			return [0.0, _shoulder_r + Vector3(0.05, -0.01, -0.03), Vector3(0.07, 0.22, 1.0), Vector3.UP, 1.0, 1.0]
		Drill.LOAD:
			return [0.0, Vector3(mid.x + 0.1, 0.03, mid.z + 0.3), Vector3(-0.05, 1.0, -0.1), Vector3(0, 0, 1), 1.0, 1.0]
		Drill.CHARGE:
			return [GRIP_T, _shoulder_r + Vector3(0.03, -0.43, 0.1 + 0.3 * jab), Vector3(0.2, 0.05, 1.0), Vector3.UP, 1.0, 1.0]
		Drill.DROPPED:
			return [0.5, Vector3(mid.x - 0.25, 0.04, mid.z + 0.3), Vector3(0.9, 0.0, 0.4), Vector3.UP, 0.0, 0.0]
		_:      # PORT, and NONE keeps the musket where PORT would have it while it fades
			return [GRIP_T, _shoulder_r + Vector3(0.06, -0.36, 0.2), Vector3(0.58, 0.8, 0.12), Vector3(0, 0.3, 1), 1.0, 1.0]


## A point on the musket, a fraction t from the butt, in the musket's own space. The model lies
## along X with the bayonet tip at -X and rests on y = 0.
func _on_musket(t: float) -> Vector3:
	return Vector3(LENGTH * 0.5 - t * LENGTH, _thick * 0.5, 0.0)


func _process_modification_with_delta(delta: float) -> void:
	if not _ready_done or musket == null:
		return
	var sk := get_skeleton()
	_clock += delta
	if drill != _pending:
		_delay -= delta
		if _delay <= 0.0:
			drill = _pending

	var spec := _target(drill)
	var muzzle: Vector3 = (spec[2] as Vector3).normalized()
	var x_axis := -muzzle
	var lock: Vector3 = spec[3]
	var up := lock - muzzle * lock.dot(muzzle)
	up = up.normalized() if up.length() > 0.01 else Vector3.UP
	var basis := Basis(x_axis, up, x_axis.cross(up))
	var want_rot := basis.get_rotation_quaternion()
	var want_pos: Vector3 = (spec[1] as Vector3) - basis * _on_musket(float(spec[0]))
	var k := 1.0 if _first else 1.0 - exp(-BLEND * delta)
	_first = false
	_pos = _pos.lerp(want_pos, k)
	_rot = _rot.slerp(want_rot, k) if _rot.length_squared() > 0.5 else want_rot
	_weight_r = lerpf(_weight_r, float(spec[4]), k)
	_weight_l = lerpf(_weight_l, float(spec[5]), k)
	_shown = lerpf(_shown, 0.0 if drill == Drill.NONE else 1.0, k)
	musket.visible = _shown > 0.05

	# Ride the body's bob: follow the hips, except when the butt is planted on the ground.
	var bob: Vector3 = _to_model.basis * (sk.get_bone_global_pose(_hips).origin - _hips_rest)
	if drill == Drill.LOAD or drill == Drill.DROPPED:
		bob.y = 0.0
	var held := Transform3D(Basis(_rot), _pos + bob)
	musket.transform = _to_skel * held

	if drill == Drill.DROPPED or _shown <= 0.05:
		return
	var right_t := GRIP_T
	var left_t := FORE_T
	if drill == Drill.SHOULDER:
		right_t = 0.03
	elif drill == Drill.LOAD:
		# Left hand steadies the barrel; the right drives the ramrod up and down above the muzzle.
		left_t = 0.6
		right_t = 0.78 + 0.16 * (0.5 + 0.5 * sin(_clock * 9.0))
	var right_at := _to_skel * (held * _on_musket(right_t))
	var left_at := _to_skel * (held * _on_musket(left_t))
	_reach(sk, _arm_r, _fore_r, _hand_r, right_at, _to_skel.basis * Vector3(-0.7, -0.6, -0.35), _weight_r * _shown)
	_reach(sk, _arm_l, _fore_l, _hand_l, left_at, _to_skel.basis * Vector3(0.7, -0.6, -0.2), _weight_l * _shown)


## Two-bone inverse kinematics: turns the upper arm and forearm so the hand lands on the target.
## elbow_hint is the side the elbow should bend toward. All in skeleton space.
func _reach(sk: Skeleton3D, arm: int, fore: int, hand: int, target: Vector3, elbow_hint: Vector3, weight: float) -> void:
	if weight <= 0.01:
		return
	var g_arm := sk.get_bone_global_pose(arm)
	var goal := sk.get_bone_global_pose(hand).origin.lerp(target, clampf(weight, 0.0, 1.0))
	var shoulder := g_arm.origin
	var upper := sk.get_bone_pose_position(fore).length()
	var lower := sk.get_bone_pose_position(hand).length()
	if upper < 0.0001 or lower < 0.0001:
		return
	var to_goal := goal - shoulder
	var dist := clampf(to_goal.length(), absf(upper - lower) + 0.001 * upper, (upper + lower) * 0.999)
	var dir := to_goal.normalized()
	var along := (upper * upper - lower * lower + dist * dist) / (2.0 * dist)
	var out := sqrt(maxf(0.0, upper * upper - along * along))
	var side := elbow_hint - dir * elbow_hint.dot(dir)
	side = side.normalized() if side.length() > 0.0001 else dir.cross(Vector3.UP).normalized()
	var elbow := shoulder + dir * along + side * out
	var wrist := shoulder + dir * dist

	var bone_axis := sk.get_bone_pose_position(fore).normalized()
	var now := (g_arm.basis * bone_axis).normalized()
	g_arm.basis = Basis(Quaternion(now, (elbow - shoulder).normalized())) * g_arm.basis
	sk.set_bone_global_pose(arm, g_arm)

	var g_fore := sk.get_bone_global_pose(fore)
	bone_axis = sk.get_bone_pose_position(hand).normalized()
	now = (g_fore.basis * bone_axis).normalized()
	g_fore.basis = Basis(Quaternion(now, (wrist - g_fore.origin).normalized())) * g_fore.basis
	sk.set_bone_global_pose(fore, g_fore)
