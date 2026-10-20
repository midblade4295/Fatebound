extends SceneTree
# Weapon grips (0.31.104, Kevin with screenshots of Brickbreaker, Ravenclaws, Twin Sparks, Bloodmoon, Hawkeye and the Eye
# of the Archon: "A lot of the weapons are still not gripped correctly"):
#  - every bow, held in its class's idle, has its string on the archer's side (the tips, where the string is tied, nearer
#    the body than the hand on the riser) -- the Bits bows (Hawkeye, Stag Hunter, Galeshot, Longshot, Heartseeker) had it
#    on the far side;
#  - a one-handed hammer, mace, axe or wand is held at the end of its handle: the hand in the bottom part of the piece,
#    not halfway up it under the head (tools/weapon_grip.py END);
#  - (0.31.104-0.31.187: the Eye of the Archon and the Lich-Crown held on their shafts -- gone with the catalog's weapons)
#    0.31.188: each outfit's staff is held like the hero's own (the same length, the hand as far down it).
#   godot --headless --path godot -s res://tests/weapon_grip_test.gd
const Eco = preload("res://scripts/meta/economy.gd")
const View = preload("res://scripts/siege/siege_view.gd")
const END := ["wand", "bits/wand_A", "bits/wand_B", "axe_1handed", "bits/axe_A", "bits/axe_C", "bits/hammer_A",
	"bits/hammer_B", "bits/hammer_C", "bits/hammer_D"]
var fails: Array = []
var bows := []          # [label, body]
var f := 0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _rel(m: Node3D, top: Node) -> Transform3D:
	# m's transform in top's space (for a piece not in the tree)
	var t := Transform3D.IDENTITY
	var n: Node = m
	while n != null and n != top:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t

func _points(n: Node, xf: Callable) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or str(m.name).begins_with("Fx") or str(m.name) == "Ribbon":
			continue
		for si in m.mesh.get_surface_count():
			var v: PackedVector3Array = m.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			for k in range(0, v.size(), 2):
				pts.append(xf.call(m, v[k]))
	return pts

func _init() -> void:
	# ---- one-handed pieces: the hand (the origin of the template space) low on the piece
	var high := []
	var n_end := 0
	for k in View.MESHY_WEAPON_LIKE:
		if not END.has(str(View.MESHY_WEAPON_LIKE[k])):
			continue
		var inst: Node3D = (load(View.weapon_path("mw/" + k)) as PackedScene).instantiate()
		var pts := _points(inst, func(m: MeshInstance3D, p: Vector3) -> Vector3: return _rel(m, inst) * p)
		var lo := INF
		var hi := -INF
		for p in pts:
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
		var frac := -lo / maxf(hi - lo, 0.001)
		if frac > 0.28:
			high.append("%s %.2f" % [k, frac])
		n_end += 1
		inst.free()
	check(n_end >= 6 and high.is_empty(), "every one-handed hammer, mace, axe and wand is held at the end of its handle (%d) %s" % [n_end, str(high)])
	# ---- the outfits' staffs: held like the hero's own staff (0.31.188)
	var span := func(k: String) -> Vector2:
		var inst: Node3D = (load(View.weapon_path("mw/" + k)) as PackedScene).instantiate()
		var pts := _points(inst, func(m: MeshInstance3D, p: Vector3) -> Vector3: return _rel(m, inst) * p)
		var lo := INF
		var hi := -INF
		for p in pts:
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
		inst.free()
		return Vector2(hi - lo, hi / maxf(hi - lo, 0.001))
	var own: Vector2 = span.call("apprentice_staff")
	var off := []
	var n_staff := 0
	for id in Eco.SKINS:
		for hand in (Eco.SKINS[id].get("weapon", {}) as Dictionary).values():
			var k := str(hand).substr(3)
			if str(View.MESHY_WEAPON_LIKE.get(k, "")) != "staff":
				continue
			n_staff += 1
			var sp: Vector2 = span.call(k)
			if absf(sp.x - own.x) > own.x * 0.15 or absf(sp.y - own.y) > 0.06:
				off.append("%s %.2f/%.2f" % [k, sp.x, sp.y])
	check(n_staff >= 5 and off.is_empty(), "the outfits' staffs are held like the hero's own (%d; %.2f long, %.2f ahead of the hand) %s" % [n_staff, own.x, own.y, str(off)])
	# ---- every bow in its class's idle (0.31.188: the outfits' bows -- the catalog's weapons are gone)
	for id in Eco.SKINS:
		var sk: Dictionary = Eco.SKINS[id]
		var l := str((sk.get("weapon", {}) as Dictionary).get("l", ""))
		if l.contains("bow") and not l.contains("crossbow"):
			var cls := str(sk.hero)
			var made: Dictionary = View.make_body(cls, {"skin": id})
			root.add_child(made.body)
			var pl: AnimationPlayer = made.player
			pl.play(str(View.LOOKS[cls].idle))
			pl.seek(0.6, true)
			pl.speed_scale = 0.0
			bows.append([str(sk.name), made.body])
	for cls in ["ranger"]:
		var made2: Dictionary = View.make_body(cls, {})
		root.add_child(made2.body)
		(made2.player as AnimationPlayer).play(str(View.LOOKS[cls].idle))
		bows.append(["(the Archer's own)", made2.body])

func _process(_d: float) -> bool:
	f += 1
	if f < 4:
		return false
	var away := []
	for b in bows:
		var slot: BoneAttachment3D = null
		for s in (b[1] as Node).find_children("*", "BoneAttachment3D", true, false):
			if str((s as BoneAttachment3D).bone_name) == "handslot.l":
				slot = s
		if slot == null:
			away.append("%s: no bow hand" % b[0])
			continue
		var pts := _points(slot, func(m: MeshInstance3D, p: Vector3) -> Vector3: return m.global_transform * p)
		var c := Vector3.ZERO
		for p in pts:
			c += p
		c /= maxf(pts.size(), 1)
		var t1 := c
		for p in pts:
			if p.distance_to(c) > t1.distance_to(c):
				t1 = p
		var t2 := t1
		for p in pts:
			if p.distance_to(t1) > t2.distance_to(t1):
				t2 = p
		var g := slot.global_position
		var tips := (t1 + t2) * 0.5
		var to_body := Vector3(-g.x, 0, -g.z)
		if (tips - g).dot(to_body) <= 0.0:
			away.append(b[0])
	check(bows.size() >= 2 and away.is_empty(), "every bow's string is on the archer's side (%d bows) %s" % [bows.size(), str(away)])
	print("WEAPON_GRIP_PASS" if fails.is_empty() else "WEAPON_GRIP_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
	return false
