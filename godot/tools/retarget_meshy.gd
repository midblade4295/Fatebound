extends SceneTree
# Bakes ALL the game's KayKit animations onto a Meshy-rigged character (0.31.52, Kevin: a new Assassin from Meshy).
#   NAME=archmage godot --headless --path godot -s res://tools/retarget_meshy.gd    (NAME: the folder under assets/meshy)
# 1. rig.json: "fit" scales the Meshy model to the KayKit body's height; "slot_r"/"slot_l" are hand-slot bone rests
#    (children of the wrists) placed and turned like KayKit's handslot bones, so weapons sit as they do on KayKit hands.
# 2. anims_<g|m|r|mb|ma|t>.res: each KayKit library re-baked frame by frame. For a mapped bone, its GLOBAL rotation
#    relative to its KayKit rest is applied to the Meshy bone's rest and turned back into a LOCAL rotation; the hips also
#    carry their motion (scaled by the hip heights). Unmapped bones (Spine01, neck, shoulders) hold their rest.
const View = preload("res://scripts/siege/siege_view.gd")
const FPS := 30.0
const KK_FOR := {"assassin": "rogue_kaykit", "archmage": "mage_kaykit", "crusader": "knight_kaykit", "berserker": "barbarian_kaykit",
	"sniper": "ranger_kaykit", "necromancer": "necromancer_kaykit", "villager": "villager_kaykit", "worker": "villager_kaykit",
	"knight": "knight_kaykit", "barbarian": "barbarian_kaykit", "rogue": "rogue_kaykit", "ranger": "ranger_kaykit",
	"mage": "mage_kaykit", "priest": "mage_kaykit"}   # the KayKit body it replaces: source skeleton and height (0.31.80: the
	# base classes are Meshy bodies now, so every entry names a stock *_kaykit body)

func _initialize() -> void:
	_run()

func _xa(t: Transform3D) -> Array:
	return [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z, t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z]

func _box(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

func _run() -> void:
	await process_frame
	var name := OS.get_environment("NAME") if OS.has_environment("NAME") else "assassin"
	var dir: String = View.MESHY[name]
	var made: Dictionary = View.make_body(str(KK_FOR.get(name, "rogue")), {"r": "", "l": ""})
	root.add_child(made.body)
	var player: AnimationPlayer = made.player
	var src: Skeleton3D = made.body.find_child("Skeleton3D", true, false)
	await process_frame
	# --- 1. rig.json ---
	var raw: Node3D = (load(dir + "rigged.glb") as PackedScene).instantiate()
	root.add_child(raw)
	await process_frame
	var kk_h := _box(made.body).size.y
	var me_h := 0.0                                      # a skinned mesh renders at its bind-space size (the
	for mi in raw.find_children("*", "MeshInstance3D", true, false):    # Armature's 0.01 is undone by the cm bones)
		me_h = maxf(me_h, (mi as MeshInstance3D).mesh.get_aabb().size.y)
	var fit := kk_h / me_h
	var rsk: Skeleton3D = raw.find_child("Skeleton3D", true, false)
	var unit := 1.0                                      # metres per Meshy skeleton unit at scale 1
	var n: Node = rsk
	while n != null and n != raw:
		if n is Node3D:
			unit *= (n as Node3D).scale.x
		n = n.get_parent()
	# 0.31.76: FIT=neck matches the height of the head bone (the neck) instead of the overall height -- for a model whose
	# hat stands well above its head (the farmer's straw brim), where the overall fit would shrink the body under it.
	var me_floor := INF
	for mi in raw.find_children("*", "MeshInstance3D", true, false):
		me_floor = minf(me_floor, (mi as MeshInstance3D).mesh.get_aabb().position.y)
	var kk_neck: float = (src.global_transform * src.get_bone_global_rest(src.find_bone("head"))).origin.y - _box(made.body).position.y
	var me_neck: float = rsk.get_bone_global_rest(rsk.find_bone("Head")).origin.y * unit - me_floor
	print("fit by height ", fit, ", by neck ", kk_neck / me_neck, " (KayKit neck ", kk_neck, " m, Meshy ", me_neck, ")")
	if OS.get_environment("FIT") == "neck":
		fit = kk_neck / me_neck
	var rig := {"fit": fit}
	for hand in ["r", "l"]:
		var kw: Transform3D = src.get_bone_global_rest(src.find_bone("wrist." + hand))
		var ks: Transform3D = src.get_bone_global_rest(src.find_bone("handslot." + hand))
		var mw: Transform3D = rsk.get_bone_global_rest(rsk.find_bone(("Right" if hand == "r" else "Left") + "Hand"))
		var off: Vector3 = (ks.origin - kw.origin) / (unit * fit)     # KayKit metres -> Meshy skeleton units
		var slot_g := Transform3D(ks.basis.orthonormalized(), mw.origin + off)
		rig["slot_" + hand] = _xa(mw.affine_inverse() * slot_g)
	# 0.31.77: a hand posed round its weapon by tools/meshy_hand_pose.py keeps the slot where it put the handle.
	var old_rig: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + "rig.json")) if FileAccess.file_exists(dir + "rig.json") else null
	if old_rig is Dictionary:
		for hand in ["r", "l"]:
			if (old_rig as Dictionary).has("grip_" + hand):
				var grip: Array = old_rig["grip_" + hand]
				var sl: Array = rig["slot_" + hand]
				for i in 3:
					sl[9 + i] = float(grip[i])
				rig["grip_" + hand] = grip
	var f := FileAccess.open(dir + "rig.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(rig))
	f.close()
	View._meshy_rig.erase(name)
	raw.free()
	print("rig.json: fit ", fit, " (KayKit height ", kk_h, ", Meshy ", me_h, ")")
	# --- 2. the target: the game's own Meshy body (renamed bones, hand slots) ---
	var mb: Dictionary = View.meshy_body(name)
	var body: Node3D = mb.body
	root.add_child(body)
	await process_frame
	var tgt: Skeleton3D = mb.skeleton
	var tgt_path := String(body.get_path_to(tgt))
	var src_rest := {}
	for i in src.get_bone_count():
		src_rest[src.get_bone_name(i)] = src.get_bone_global_rest(i)
	var tgt_rest := []
	for i in tgt.get_bone_count():
		tgt_rest.append(tgt.get_bone_global_rest(i))
	var hip_ratio: float = tgt_rest[tgt.find_bone("hips")].origin.y / maxf(0.001, (src_rest["hips"] as Transform3D).origin.y)
	var mapped := {}
	for k in View.MESHY_RENAME.values() + ["handslot.r", "handslot.l"]:     # (the slots too: KayKit turns its hands,
		if src.find_bone(k) >= 0 and tgt.find_bone(k) >= 0:                  # a bone the Meshy rig doesn't have)
			mapped[k] = true
	var total := 0
	for key in View.libraries():
		var srclib: AnimationLibrary = View.libraries()[key]
		var lib := AnimationLibrary.new()
		for an in srclib.get_animation_list():
			var srca: Animation = srclib.get_animation(an)
			var anim := Animation.new()
			anim.length = srca.length
			anim.loop_mode = srca.loop_mode
			var tracks := {}
			for bn in mapped:
				var tr := anim.add_track(Animation.TYPE_ROTATION_3D)
				anim.track_set_path(tr, NodePath(tgt_path + ":" + bn))
				tracks[bn] = tr
			var hip_tr := anim.add_track(Animation.TYPE_POSITION_3D)
			anim.track_set_path(hip_tr, NodePath(tgt_path + ":hips"))
			player.play("%s/%s" % [key, an])
			var frames := maxi(1, int(ceil(srca.length * FPS)))
			for fr in frames + 1:
				var t := minf(srca.length, fr / FPS)
				player.seek(t, true)
				src.force_update_all_bone_transforms()
				var tg := []
				tg.resize(tgt.get_bone_count())
				for i in tgt.get_bone_count():
					var bn := tgt.get_bone_name(i)
					var parent := tgt.get_bone_parent(i)
					var pg: Transform3D = tg[parent] if parent >= 0 else Transform3D.IDENTITY
					if mapped.has(bn):
						var sgp: Transform3D = src.get_bone_global_pose(src.find_bone(bn))
						var delta := Basis.IDENTITY             # (some KayKit clips scale a bone to zero: hold it still)
						if absf(sgp.basis.determinant()) > 1e-6:
							delta = sgp.basis.orthonormalized() * (src_rest[bn] as Transform3D).basis.orthonormalized().inverse()
						var gb: Basis = delta * tgt_rest[i].basis.orthonormalized()
						var lb: Basis = pg.basis.orthonormalized().inverse() * gb
						var origin: Vector3 = pg * tgt.get_bone_rest(i).origin
						if bn == "hips":
							origin = tgt_rest[i].origin + (sgp.origin - (src_rest["hips"] as Transform3D).origin) * hip_ratio
							anim.position_track_insert_key(hip_tr, t, pg.affine_inverse() * origin)
						tg[i] = Transform3D(gb, origin)
						anim.rotation_track_insert_key(tracks[bn], t, lb.get_rotation_quaternion())
					else:
						tg[i] = pg * tgt.get_bone_rest(i)
			lib.add_animation(an, anim)
			total += 1
		var err := ResourceSaver.save(lib, dir + "anims_%s.res" % key, ResourceSaver.FLAG_COMPRESS)
		print("  library ", key, ": ", lib.get_animation_list().size(), " animations (err ", err, ")")
	print("RETARGET_DONE ", total, " animations")
	quit(0)
