extends SceneTree
# Godot's side of the animation parity test (tools/parity/anim.sh; the C# side: tools/guitest/AnimTest.cs, `guitest
# anim`). Run with --fixed-fps 60 (process and physics deltas exactly 1/60) and --path <the game's godot project>.
#
# Part 1 (synthetic): a 7-bone skeleton with scaled/rotated rests, a skin, a BoneAttachment3D added at runtime with a
# child, and an AnimationPlayer with two libraries (linear/cubic/nearest/angle tracks, linear/ping-pong/no loop, large
# quaternion angles, a bone only some clips animate, value tracks -- continuous, angle, discrete -- and a method track);
# first the *_track_interpolate results at a set of times, then a scripted frame sequence (play, blends, seek,
# speed_scale, queue, MANUAL + advance, pause, process_mode DISABLED, play_backwards, PHYSICS, stop) printing the bone
# global poses, the attachment, the skin transforms and the player's state at the start of every frame.
# Part 2 (real assets): the Meshy knight's skeleton prepared as the game's meshy_body() does, its anims_g/anims_mb
# libraries; their stored properties and the skeleton are dumped (var_to_bytes) to $FB_ANIM_OUT/anim_dump.bin for the C#
# side, then interpolations of every clip and a MANUAL playback with blends are printed from the real resources.
# Each line: "<key>|<value>".

var frame := 0
var body: Node3D
var skel: Skeleton3D
var player: AnimationPlayer
var att: BoneAttachment3D
var weapon: Node3D
var pivot: Node3D
var skin: Skin
var has_cur := false
var twist: Node
var skin_xf := []     # the skin transforms as Godot sends them to the RenderingServer (captured on skeleton_updated)
var out_dir := "/tmp/fb-anim"

# part 2
var rbody: Node3D
var rskel: Skeleton3D
var rplayer: AnimationPlayer
var rskin: Skin
var rhas := false

const RENAME := {"Hips":"hips", "Spine02":"spine", "Spine":"chest", "Head":"head",
	"LeftArm":"upperarm.l", "LeftForeArm":"lowerarm.l", "LeftHand":"wrist.l",
	"RightArm":"upperarm.r", "RightForeArm":"lowerarm.r", "RightHand":"wrist.r",
	"LeftUpLeg":"upperleg.l", "LeftLeg":"lowerleg.l", "LeftFoot":"foot.l", "LeftToeBase":"toes.l",
	"RightUpLeg":"upperleg.r", "RightLeg":"lowerleg.r", "RightFoot":"foot.r", "RightToeBase":"toes.r"}

func p(k: String, v) -> void:
	print(k + "|" + str(v))

class Marker:
	extends Node
	func mark(what: String, n: int) -> void:
		print("call|mark|" + what + "|" + str(n))

# a skeleton modifier (the ragdoll's hook): turns arm.l on top of the animation, pins tail's global pose
class Twist:
	extends SkeletonModifier3D
	func _process_modification_with_delta(_delta: float) -> void:
		var sk := get_skeleton()
		var b := sk.find_bone("arm.l")
		sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b) * Quaternion(Vector3(1, 0, 0), 0.7))
		sk.set_bone_global_pose(sk.find_bone("tail"), Transform3D(Basis(Vector3(0, 1, 0), 0.4), Vector3(0.1, 0.5, -0.3)))

func xf(axis: Vector3, angle: float, sc: Vector3, origin: Vector3) -> Transform3D:
	return Transform3D(Basis(axis.normalized(), angle).scaled(sc), origin)

func build_animations() -> Array:
	var lib := AnimationLibrary.new()
	var lib2 := AnimationLibrary.new()
	var P := "Armature/Skeleton3D:"

	# idle: looping, linear; hips position + rotation, spine rotation and scale, chest rotation
	var idle := Animation.new()
	idle.length = 1.2
	idle.loop_mode = Animation.LOOP_LINEAR
	var t := idle.add_track(Animation.TYPE_POSITION_3D)
	idle.track_set_path(t, P + "hips")
	idle.track_insert_key(t, 0.0, Vector3(0, 1.0, 0))
	idle.track_insert_key(t, 0.4, Vector3(0.05, 1.04, -0.02))
	idle.track_insert_key(t, 0.9, Vector3(-0.03, 0.97, 0.01))
	t = idle.add_track(Animation.TYPE_ROTATION_3D)
	idle.track_set_path(t, P + "hips")
	idle.track_insert_key(t, 0.0, Quaternion(Vector3(0, 1, 0), 0.2))
	idle.track_insert_key(t, 0.6, Quaternion(Vector3(0, 1, 0.3).normalized(), -0.35))
	idle.track_insert_key(t, 1.1, Quaternion(Vector3(1, 0, 0), 0.15))
	t = idle.add_track(Animation.TYPE_ROTATION_3D)
	idle.track_set_path(t, P + "spine")
	idle.track_insert_key(t, 0.1, Quaternion(Vector3(1, 0, 0), 0.3))
	idle.track_insert_key(t, 0.7, Quaternion(Vector3(1, 0.2, 0).normalized(), -0.4), 0.5)
	t = idle.add_track(Animation.TYPE_SCALE_3D)
	idle.track_set_path(t, P + "spine")
	idle.track_insert_key(t, 0.0, Vector3(1, 1, 1))
	idle.track_insert_key(t, 0.6, Vector3(1.1, 0.95, 1.05), -2.0)
	t = idle.add_track(Animation.TYPE_ROTATION_3D)
	idle.track_set_path(t, P + "chest")
	idle.track_insert_key(t, 0.0, Quaternion(Vector3(0, 0, 1), 0.1))
	idle.track_insert_key(t, 1.2, Quaternion(Vector3(0, 0, 1), -0.1))
	t = idle.add_track(Animation.TYPE_VALUE)
	idle.track_set_path(t, "Pivot:position")
	idle.track_insert_key(t, 0.0, Vector3(0, 0, 0))
	idle.track_insert_key(t, 0.5, Vector3(0.3, 0.1, -0.2))
	lib.add_animation("idle", idle)

	# walk: looping, cubic; big rotations crossing 180 degrees, head and arm.l, value tracks (cubic, angle, discrete)
	var walk := Animation.new()
	walk.length = 0.8
	walk.loop_mode = Animation.LOOP_LINEAR
	t = walk.add_track(Animation.TYPE_POSITION_3D)
	walk.track_set_path(t, P + "hips")
	walk.track_set_interpolation_type(t, Animation.INTERPOLATION_CUBIC)
	walk.track_insert_key(t, 0.0, Vector3(0, 0.95, 0))
	walk.track_insert_key(t, 0.2, Vector3(0.02, 1.02, 0.1))
	walk.track_insert_key(t, 0.4, Vector3(0, 0.95, 0.2))
	walk.track_insert_key(t, 0.65, Vector3(-0.02, 1.03, 0.1))
	t = walk.add_track(Animation.TYPE_ROTATION_3D)
	walk.track_set_path(t, P + "hips")
	walk.track_set_interpolation_type(t, Animation.INTERPOLATION_CUBIC)
	walk.track_insert_key(t, 0.0, Quaternion(Vector3(0, 1, 0), 2.9))
	walk.track_insert_key(t, 0.3, Quaternion(Vector3(0, 1, 0), -2.8))
	walk.track_insert_key(t, 0.55, Quaternion(Vector3(0.3, 1, 0).normalized(), 3.1))
	walk.track_insert_key(t, 0.8, Quaternion(Vector3(0, 1, 0), 2.9))
	t = walk.add_track(Animation.TYPE_ROTATION_3D)
	walk.track_set_path(t, P + "head")
	walk.track_set_interpolation_type(t, Animation.INTERPOLATION_CUBIC_ANGLE)
	walk.track_insert_key(t, 0.0, Quaternion(Vector3(1, 0, 0), -0.3))
	walk.track_insert_key(t, 0.4, Quaternion(Vector3(0, 0, 1), 1.2))
	t = walk.add_track(Animation.TYPE_ROTATION_3D)
	walk.track_set_path(t, P + "arm.l")
	walk.track_insert_key(t, 0.0, Quaternion(Vector3(0, 0, 1), 1.5))
	walk.track_insert_key(t, 0.4, Quaternion(Vector3(0, 0, 1), -1.5))
	t = walk.add_track(Animation.TYPE_VALUE)
	walk.track_set_path(t, "Pivot:position")
	walk.track_set_interpolation_type(t, Animation.INTERPOLATION_CUBIC)
	walk.track_insert_key(t, 0.0, Vector3(0, 0.5, 0))
	walk.track_insert_key(t, 0.3, Vector3(0.2, 0.1, 0.4))
	walk.track_insert_key(t, 0.6, Vector3(-0.1, 0.3, 0.1))
	t = walk.add_track(Animation.TYPE_VALUE)
	walk.track_set_path(t, "Pivot:rotation:y")
	walk.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR_ANGLE)
	walk.track_insert_key(t, 0.0, 3.0)
	walk.track_insert_key(t, 0.4, -3.0)
	t = walk.add_track(Animation.TYPE_VALUE)
	walk.track_set_path(t, "Pivot:visible")
	walk.value_track_set_update_mode(t, Animation.UPDATE_DISCRETE)
	walk.track_insert_key(t, 0.0, true)
	walk.track_insert_key(t, 0.3, false)
	walk.track_insert_key(t, 0.6, true)
	t = walk.add_track(Animation.TYPE_METHOD)
	walk.track_set_path(t, "Marker")
	walk.track_insert_key(t, 0.1, {"method": "mark", "args": ["step", 1]})
	walk.track_insert_key(t, 0.5, {"method": "mark", "args": ["step", 2]})
	lib.add_animation("walk", walk)

	# hit: no loop, linear; arm.l and hand.l (bones idle doesn't animate), ease transitions
	var hit := Animation.new()
	hit.length = 0.5
	t = hit.add_track(Animation.TYPE_ROTATION_3D)
	hit.track_set_path(t, P + "arm.l")
	hit.track_insert_key(t, 0.0, Quaternion(Vector3(0, 0, 1), 0.2), 2.0)
	hit.track_insert_key(t, 0.25, Quaternion(Vector3(0, 1, 1).normalized(), 2.0), 0.4)
	hit.track_insert_key(t, 0.5, Quaternion(Vector3(0, 0, 1), 0.3))
	t = hit.add_track(Animation.TYPE_POSITION_3D)
	hit.track_set_path(t, P + "hand.l")
	hit.track_insert_key(t, 0.05, Vector3(0.1, 0.3, 0))
	hit.track_insert_key(t, 0.45, Vector3(0.2, 0.5, 0.1))
	t = hit.add_track(Animation.TYPE_ROTATION_3D)
	hit.track_set_path(t, P + "hips")
	hit.track_insert_key(t, 0.0, Quaternion(Vector3(1, 0, 0), -0.5))
	hit.track_insert_key(t, 0.3, Quaternion(Vector3(1, 0, 0), 0.6))
	lib.add_animation("hit", hit)

	# x/spin: ping-pong, linear; a full turn in three keys; x/snap: nearest
	var spin := Animation.new()
	spin.length = 0.6
	spin.loop_mode = Animation.LOOP_PINGPONG
	t = spin.add_track(Animation.TYPE_ROTATION_3D)
	spin.track_set_path(t, P + "chest")
	spin.track_insert_key(t, 0.0, Quaternion(Vector3(0, 1, 0), 0.0))
	spin.track_insert_key(t, 0.2, Quaternion(Vector3(0, 1, 0), 2.1))
	spin.track_insert_key(t, 0.4, Quaternion(Vector3(0, 1, 0), -2.1))
	t = spin.add_track(Animation.TYPE_SCALE_3D)
	spin.track_set_path(t, P + "head")
	spin.track_set_interpolation_type(t, Animation.INTERPOLATION_CUBIC)
	spin.track_insert_key(t, 0.0, Vector3(1, 1, 1))
	spin.track_insert_key(t, 0.3, Vector3(1.3, 1.3, 1.3))
	spin.track_insert_key(t, 0.6, Vector3(0.8, 1, 1.2))
	lib2.add_animation("spin", spin)

	var snap := Animation.new()
	snap.length = 1.0
	snap.loop_mode = Animation.LOOP_LINEAR
	t = snap.add_track(Animation.TYPE_POSITION_3D)
	snap.track_set_path(t, P + "tail")
	snap.track_set_interpolation_type(t, Animation.INTERPOLATION_NEAREST)
	snap.track_insert_key(t, 0.0, Vector3(0, -0.2, -0.1))
	snap.track_insert_key(t, 0.5, Vector3(0, -0.3, -0.3))
	t = snap.add_track(Animation.TYPE_ROTATION_3D)
	snap.track_set_path(t, P + "tail")
	snap.track_set_interpolation_loop_wrap(t, false)
	snap.track_insert_key(t, 0.2, Quaternion(Vector3(1, 0, 0), 1.0))
	snap.track_insert_key(t, 0.8, Quaternion(Vector3(1, 0, 0), -1.0))
	lib2.add_animation("snap", snap)
	return [lib, lib2]

func build_scene() -> void:
	body = Node3D.new()
	body.name = "Body"
	body.position = Vector3(1, 0, -2)
	body.rotation = Vector3(0, 0.7, 0)
	var arm := Node3D.new()
	arm.name = "Armature"
	arm.scale = Vector3(0.5, 0.5, 0.5)
	body.add_child(arm)
	skel = Skeleton3D.new()
	skel.name = "Skeleton3D"
	arm.add_child(skel)
	var names := ["hips", "spine", "chest", "head", "arm.l", "hand.l", "tail"]
	var parents := [-1, 0, 1, 2, 2, 4, 0]
	var rests := [
		xf(Vector3(0, 1, 0), 0.3, Vector3(1, 1, 1), Vector3(0, 1.0, 0)),
		xf(Vector3(1, 0.2, 0), 0.25, Vector3(1.1, 0.9, 1.0), Vector3(0, 0.3, 0.02)),
		xf(Vector3(0.1, 0, 1), -0.2, Vector3(1, 1, 1), Vector3(0, 0.35, 0)),
		xf(Vector3(0, 1, 0.3), 0.5, Vector3(0.9, 0.9, 0.9), Vector3(0, 0.3, 0.05)),
		xf(Vector3(0, 0, 1), 1.4, Vector3(1, 1.2, 1), Vector3(0.2, 0.25, 0)),
		xf(Vector3(1, 1, 0), -0.6, Vector3(1, 1, 1), Vector3(0, 0.35, 0)),
		xf(Vector3(1, 0, 0), 2.6, Vector3(1, 1, 1), Vector3(0, -0.1, -0.15)),
	]
	for i in names.size():
		skel.add_bone(names[i])
	for i in names.size():
		skel.set_bone_parent(i, parents[i])
		skel.set_bone_rest(i, rests[i])
	skel.reset_bone_poses()
	skin = Skin.new()
	skin.add_named_bind("hips", xf(Vector3(0, 1, 0), 0.1, Vector3(1, 1, 1), Vector3(0, -1, 0)))
	skin.add_named_bind("hand.l", xf(Vector3(1, 0, 0), 0.4, Vector3(1, 1, 1), Vector3(-0.2, -1.9, 0)))
	skin.add_bind(3, xf(Vector3(0, 0, 1), -0.3, Vector3(1, 1, 1), Vector3(0, -2.0, 0.1)))
	skel.skeleton_updated.connect(capture_skin)
	pivot = Node3D.new()
	pivot.name = "Pivot"
	body.add_child(pivot)
	var marker := Marker.new()
	marker.name = "Marker"
	body.add_child(marker)
	player = AnimationPlayer.new()
	player.name = "AnimationPlayer"
	body.add_child(player)
	player.root_node = NodePath("..")
	var libs := build_animations()
	player.add_animation_library("", libs[0])
	player.add_animation_library("x", libs[1])
	player.animation_started.connect(func(n): p("sig|started", n))
	player.animation_finished.connect(func(n): p("sig|finished", n))
	player.animation_changed.connect(func(a, b): p("sig|changed", str(a) + ">" + str(b)))
	player.current_animation_changed.connect(func(n): p("sig|current", n))
	root.add_child(body)
	att = BoneAttachment3D.new()
	att.name = "Hand"
	att.bone_name = "hand.l"
	skel.add_child(att)
	weapon = Node3D.new()
	weapon.position = Vector3(0, 0.2, 0.05)
	weapon.rotation = Vector3(0.1, 0.2, 0.3)
	att.add_child(weapon)

func capture_skin() -> void:
	skin_xf.clear()
	for b in skin.get_bind_count():
		var bi: int = skel.find_bone(skin.get_bind_name(b)) if str(skin.get_bind_name(b)) != "" else skin.get_bind_bone(b)
		skin_xf.append(skel.get_bone_global_pose(bi) * skin.get_bind_pose(b))

func interp_dump(prefix: String, anim: Animation, times: Array) -> void:
	for i in anim.get_track_count():
		var tt := anim.track_get_type(i)
		for ti in times.size():
			var tm: float = times[ti]
			var k := prefix + "|" + str(i) + "|" + str(tm)
			match tt:
				Animation.TYPE_POSITION_3D:
					p(k, anim.position_track_interpolate(i, tm))
				Animation.TYPE_ROTATION_3D:
					p(k, anim.rotation_track_interpolate(i, tm))
					p(k + "|bw", anim.rotation_track_interpolate(i, tm, true))
				Animation.TYPE_SCALE_3D:
					p(k, anim.scale_track_interpolate(i, tm))
				Animation.TYPE_VALUE:
					p(k, anim.value_track_interpolate(i, tm))
					p(k + "|bw", anim.value_track_interpolate(i, tm, true))

func state() -> void:
	var f := "f" + str(frame)
	p(f + "|cur", player.current_animation + "|" + player.assigned_animation + "|" + str(player.is_playing()))
	if has_cur:
		p(f + "|pos", player.current_animation_position)
	for i in skel.get_bone_count():
		p(f + "|b" + str(i), skel.get_bone_global_pose(i))
	p(f + "|att", att.global_transform)
	p(f + "|wpn", weapon.global_transform)
	p(f + "|pivot", str(pivot.position) + "|" + str(pivot.rotation.y) + "|" + str(pivot.visible))
	for b in skin_xf.size():
		p(f + "|skin" + str(b), skin_xf[b])

func step() -> void:
	match frame:
		0:
			player.play("idle")
			has_cur = true
		8:
			player.play("walk", 0.2)
		20:
			player.playback_default_blend_time = 0.05
			player.play("x/spin")
		30:
			player.seek(0.3, true)
		32:
			player.speed_scale = 1.5
		33:
			player.seek(0.1)
		40:
			player.play("hit", 0.15)
			player.queue("idle")
		64:
			player.play("x/snap", 0.1)
		70:
			player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			player.advance(0.13)
		71, 72, 73, 76, 77, 78, 79:
			player.advance(0.13)
		74:
			player.set_blend_time("x/snap", "walk", 0.25)
		75:
			player.play("walk")
			player.advance(0.13)
		80:
			player.pause()
		82:
			player.advance(0.1)
		84:
			player.play()
			player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		86:
			player.get_animation("walk").track_set_enabled(4, false)
		88:
			player.get_animation("walk").track_set_enabled(4, true)
		90:
			player.process_mode = Node.PROCESS_MODE_DISABLED
		95:
			player.process_mode = Node.PROCESS_MODE_INHERIT
		100:
			player.stop(true)
			has_cur = false
		102:
			player.play_backwards("hit")
			has_cur = true
		104:
			twist = Twist.new()
			twist.name = "Twist"
			skel.add_child(twist)
		108:
			twist.influence = 0.6
		112:
			player.deterministic = true
		116:
			player.deterministic = false
		124:
			player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
			player.speed_scale = 1.0
			player.play("idle", 0.2)
		128:
			twist.queue_free()
		134:
			player.stop()
			has_cur = false

# ---------------------------------------------------------------- part 2: the game's real assets
const SYN_TIMES := [-0.1, 0.0, 0.05, 0.1234, 0.25, 0.3, 0.5, 0.61, 0.79, 0.8, 0.95, 1.2, 1.37, 2.7]

func stored(anim: Animation) -> Dictionary:
	# the properties a .res/.tscn stores for an Animation, in order (what the C# loader feeds SetStoredProperty)
	var props := {}
	for pr in anim.get_property_list():
		if pr.usage & PROPERTY_USAGE_STORAGE and not (str(pr.name) in ["script", "resource_local_to_scene", "resource_path"]):
			props[pr.name] = anim.get(pr.name)
	return props

func prepare_real() -> void:
	var packed: PackedScene = load("res://assets/meshy/knight/rigged.glb")
	var src: Node3D = packed.instantiate()
	for ap in src.find_children("*", "AnimationPlayer", true, false):
		ap.free()
	var sk: Skeleton3D = src.find_child("Skeleton3D", true, false)
	for i in sk.get_bone_count():
		if RENAME.has(sk.get_bone_name(i)):
			sk.set_bone_name(i, RENAME[sk.get_bone_name(i)])
	var sks: Array = []
	for mi in src.find_children("*", "MeshInstance3D", true, false):
		var s: Skin = (mi as MeshInstance3D).skin
		if s != null:
			s = s.duplicate()
			sks.append(s)
			for b in s.get_bind_count():
				if RENAME.has(str(s.get_bind_name(b))):
					s.set_bind_name(b, RENAME[str(s.get_bind_name(b))])
	var rig: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/meshy/knight/rig.json"))
	for hand in ["r", "l"]:
		if rig.has("slot_" + hand) and sk.find_bone("handslot." + hand) < 0:
			var a: Array = rig["slot_" + hand]
			var bi := sk.get_bone_count()
			sk.add_bone("handslot." + hand)
			sk.set_bone_parent(bi, sk.find_bone("wrist." + hand))
			sk.set_bone_rest(bi, Transform3D(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8]), Vector3(a[9], a[10], a[11])))
	var fit := float(rig.get("fit", 1.0))
	var n: Node = sk
	while n != null and n != src:
		if n is Node3D:
			fit *= (n as Node3D).scale.x
		n = n.get_parent()
	var bones := []
	for i in sk.get_bone_count():
		var r := sk.get_bone_rest(i)
		bones.append([sk.get_bone_name(i), sk.get_bone_parent(i), Transform3D(r.basis, r.origin * fit)])
	var S := Transform3D(Basis.from_scale(Vector3.ONE * fit), Vector3.ZERO)
	var binds := []
	if not sks.is_empty():
		var s0: Skin = sks[0]
		for b in s0.get_bind_count():
			binds.append([str(s0.get_bind_name(b)), s0.get_bind_bone(b), S * s0.get_bind_pose(b)])
	src.free()
	var libs := {}
	var dump_libs := {}
	for key in ["g", "mb"]:
		var lib: AnimationLibrary = load("res://assets/meshy/knight/anims_%s.res" % key)
		libs[key] = lib
		var d := {}
		for an in lib.get_animation_list():
			d[an] = stored(lib.get_animation(an))
		dump_libs[key] = d
	# part 1's animations too (value, method, scale, cubic tracks: the stored formats the real libraries don't have)
	var synth := {}
	for an in player.get_animation_list():
		synth[an] = stored(player.get_animation(an))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var f := FileAccess.open(out_dir + "/anim_dump.bin", FileAccess.WRITE)
	f.store_buffer(var_to_bytes({"bones": bones, "binds": binds, "libs": dump_libs, "synth": synth}))
	f.close()

	# the same structure as part 1, from the dumped data
	rbody = Node3D.new()
	rbody.name = "Knight"
	var arm := Node3D.new()
	arm.name = "Armature"
	rbody.add_child(arm)
	rskel = Skeleton3D.new()
	rskel.name = "Skeleton3D"
	arm.add_child(rskel)
	for b in bones:
		rskel.add_bone(b[0])
	for i in bones.size():
		rskel.set_bone_parent(i, bones[i][1])
		rskel.set_bone_rest(i, bones[i][2])
	rskel.reset_bone_poses()
	rskin = Skin.new()
	for b in binds:
		if b[0] != "":
			rskin.add_named_bind(b[0], b[2])
		else:
			rskin.add_bind(b[1], b[2])
	rplayer = AnimationPlayer.new()
	rplayer.name = "AnimationPlayer"
	rbody.add_child(rplayer)
	rplayer.root_node = NodePath("..")
	for key in ["g", "mb"]:
		rplayer.add_animation_library(key, libs[key])
	rplayer.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	rplayer.animation_started.connect(func(n): p("rsig|started", n))
	rplayer.animation_finished.connect(func(n): p("rsig|finished", n))
	rplayer.animation_changed.connect(func(a, b): p("rsig|changed", str(a) + ">" + str(b)))
	root.add_child(rbody)
	p("real|bones", rskel.get_bone_count())
	p("real|binds", rskin.get_bind_count())
	for an in synth:
		var rebuilt := Animation.new()          # (as the resource loader builds it: the stored properties in order)
		var props: Dictionary = synth[an]
		for k in props:
			rebuilt.set(k, props[k])
		interp_dump("si|" + an, rebuilt, SYN_TIMES)
	var times := [0.0, 0.0333, 0.1, 0.37, 0.5, 0.8, 1.0, 2.3]
	for key in ["g", "mb"]:
		var lib: AnimationLibrary = libs[key]
		for an in lib.get_animation_list():
			var anim: Animation = lib.get_animation(an)
			p("real|" + key + "/" + an, str(anim.length) + "|" + str(anim.loop_mode) + "|" + str(anim.get_track_count()))
			for i in range(0, anim.get_track_count(), 3):
				for tm in times:
					var k: String = "ri|" + key + "/" + an + "|" + str(i) + "|" + str(tm)
					match anim.track_get_type(i):
						Animation.TYPE_POSITION_3D: p(k, anim.position_track_interpolate(i, tm))
						Animation.TYPE_ROTATION_3D: p(k, anim.rotation_track_interpolate(i, tm))
						Animation.TYPE_SCALE_3D: p(k, anim.scale_track_interpolate(i, tm))

func real_state() -> void:
	var f := "r" + str(frame)
	p(f + "|cur", rplayer.current_animation + "|" + rplayer.assigned_animation + "|" + str(rplayer.is_playing()))
	if rhas:
		p(f + "|pos", rplayer.current_animation_position)
	for bn in ["hips", "chest", "head", "wrist.r", "handslot.r", "foot.l"]:
		var bi := rskel.find_bone(bn)
		if bi >= 0:
			p(f + "|" + bn, rskel.get_bone_global_pose(bi))
	for b in [0, 5, 11]:
		if b < rskin.get_bind_count():
			var bi: int = rskel.find_bone(rskin.get_bind_name(b)) if str(rskin.get_bind_name(b)) != "" else rskin.get_bind_bone(b)
			p(f + "|skin" + str(b), rskel.get_bone_global_pose(bi) * rskin.get_bind_pose(b))

func real_step() -> void:
	match frame:
		142:
			rplayer.play("g/Idle_A")
			rhas = true
		147:
			rplayer.play("mb/Running_A", 0.1)
			rplayer.speed_scale = 1.2
			rplayer.advance(1.0 / 30.0)
		151:
			rplayer.play("g/Hit_A", 0.1)
			rplayer.queue("g/Idle_B")
			rplayer.advance(1.0 / 30.0)
		176:
			rplayer.stop(true)
			rhas = false
		177:
			rplayer.play("mb/Walking_B", 0.2)
			rhas = true
			rplayer.advance(1.0 / 30.0)
		_:
			if frame > 142:
				rplayer.advance(1.0 / 30.0)

func _initialize() -> void:
	var e := OS.get_environment("FB_ANIM_OUT")
	if e != "":
		out_dir = e
	build_scene()
	for an in player.get_animation_list():
		interp_dump("i|" + an, player.get_animation(an), SYN_TIMES)
	prepare_real()

func _process(_delta: float) -> bool:
	if frame < 140:
		state()
		step()
	elif frame >= 142:
		real_state()
		real_step()
	frame += 1
	return frame > 186
