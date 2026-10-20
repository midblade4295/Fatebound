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
#  - 0.31.190 (Kevin, with the Privateer Musketeer and the Red Ribbon Assassin: "There are various weapons being held
#    backwards or upside down. Go through all models and make sure weapons and shields are being held correctly and try
#    to make hands actually gripping them"): every blade is held blade up (the hand low on the piece: the Red Ribbon
#    daggers were point-down); the guns muzzle forward, upright (the butt behind the hand and dropping below it: the
#    Musketeer's own musket and the Privateer's blunderbuss were held by the muzzle, lying on their sides); and every
#    Meshy body's weapon hand is a fist round the handle (tools/meshy_hand_pose.py: rig.json's grip_<hand>), but for
#    the Knight, Rogue and Assassin, made with closed hands (and a tome's, which lies on the open hand).
#    Then (Kevin: "Now some of weapons are upside down like the musketeer weapons"): the right hand's crossbows and guns
#    had been upside down in the world since 0.31.46 (siege_view _fit_weapon) -- upright now, idle and aiming.
#    0.31.192: the Wolfstalker's crossbow turned over, the wolf's head up (Kevin).
#   godot --headless --path godot -s res://tests/weapon_grip_test.gd
const Eco = preload("res://scripts/meta/economy.gd")
const View = preload("res://scripts/siege/siege_view.gd")
const END := ["wand", "bits/wand_A", "bits/wand_B", "axe_1handed", "bits/axe_A", "bits/axe_C", "bits/hammer_A",
	"bits/hammer_B", "bits/hammer_C", "bits/hammer_D"]
var fails: Array = []
var bows := []          # [label, body]
var guns := []          # [label, body] (0.31.190: crossbows and guns in the right hand)
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

func _sample(file: String, n := 300) -> PackedVector3Array:
	# about n of the piece's vertices, in its own space
	var inst: Node3D = (load(View.weapon_path(file)) as PackedScene).instantiate()
	var pts := _points(inst, func(m: MeshInstance3D, p: Vector3) -> Vector3: return _rel(m, inst) * p)
	inst.free()
	var out := PackedVector3Array()
	var step := maxf(1.0, float(pts.size()) / n)
	var i := 0.0
	while int(i) < pts.size():
		out.append(pts[int(i)])
		i += step
	return out

func _chamfer(a: PackedVector3Array, b: PackedVector3Array) -> float:
	# the mean distance from each point to the other set's nearest, both ways
	var s := 0.0
	for pair in [[a, b], [b, a]]:
		for p in pair[0]:
			var best := INF
			for q in pair[1]:
				best = minf(best, p.distance_squared_to(q))
			s += sqrt(best) / float((pair[0] as PackedVector3Array).size())
	return s

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
	# ---- 0.31.190: blades up (the piece lies over its KayKit template better as it is than turned upside down)
	var down := []
	var n_blade := 0
	for k in View.MESHY_WEAPON_LIKE:
		var t := str(View.MESHY_WEAPON_LIKE[k])
		if not ["dagger", "bits/dagger_A", "sword_1handed", "bits/sword_E"].has(t):
			continue
		n_blade += 1
		var a: PackedVector3Array = _sample(k.insert(0, "mw/"))
		var tp: PackedVector3Array = _sample(t)
		var lo := INF
		var hi := -INF
		for q in a:
			lo = minf(lo, q.y)
			hi = maxf(hi, q.y)
		var flipped := PackedVector3Array()
		for q in a:
			flipped.append(Vector3(-q.x, lo + hi - q.y, q.z))  # (turned about Z, over the same height)
		var ratio := _chamfer(flipped, tp) / maxf(_chamfer(a, tp), 0.0001)
		if ratio < 1.03:
			down.append("%s %.2f" % [k, ratio])
	check(n_blade >= 12 and down.is_empty(), "every dagger and sword is held blade up: it fits its template better than upside down (%d) %s" % [n_blade, str(down)])
	var guns_bad := []
	for k in ["musket", "brass_blunderbuss"]:
		var inst: Node3D = (load(View.weapon_path("mw/" + k)) as PackedScene).instantiate()
		var pts := _points(inst, func(m: MeshInstance3D, p: Vector3) -> Vector3: return _rel(m, inst) * p)
		inst.free()
		var z0 := INF
		var z1 := -INF
		for p in pts:
			z0 = minf(z0, p.z)
			z1 = maxf(z1, p.z)
		var q := (z1 - z0) * 0.25
		var rear := AABB()
		var front := AABB()
		var nr := 0
		var nf := 0
		for p in pts:
			if p.z < z0 + q:
				rear = AABB(p, Vector3.ZERO) if nr == 0 else rear.expand(p)
				nr += 1
			elif p.z > z1 - q:
				front = AABB(p, Vector3.ZERO) if nf == 0 else front.expand(p)
				nf += 1
		# the butt (the rear quarter, behind the hand at the origin) drops below the muzzle and stands taller than wide
		if not (z0 < 0.0 and rear.position.y < front.position.y - 0.05 and rear.size.y > rear.size.x * 1.3):
			guns_bad.append("%s rear y %.2f/%.2fx%.2f front y %.2f" % [k, rear.position.y, rear.size.y, rear.size.x, front.position.y])
	check(guns_bad.is_empty(), "the musket and the blunderbuss: muzzle forward (+Z), the butt behind the hand, upright %s" % str(guns_bad))
	# 0.31.192 (Kevin: "Flip the wolf stalker crossbow over so the wolf head is facing the sky"): turned over about its
	# length through the stock at the hand (tools/meshy_weapon.py roll) -- the wolf's head and jaws, which hung under the
	# front, stand over it: the piece reaches 0.41 over the hand and only 0.12 under (it was 0.33 over, 0.20 under)
	var wolf := _sample("mw/wolf_crossbow", 4000)
	var wlo := INF
	var whi := -INF
	for q in wolf:
		wlo = minf(wlo, q.y)
		whi = maxf(whi, q.y)
	check(whi > 0.38 and wlo > -0.15, "the Wolfstalker's crossbow: the wolf's head up (%.2f over the hand, %.2f under)" % [whi, -wlo])
	# ---- 0.31.190: the hands close round the handle
	var open := []
	var n_hand := 0
	for hero in View.LOOKS:
		var look: Dictionary = View.LOOKS[hero]
		if not str(look.model).begins_with("meshy:"):
			continue
		var body := str(look.model).substr(6)
		if ["knight", "rogue", "assassin"].has(body):
			continue
		var rig = JSON.parse_string(FileAccess.get_file_as_string("res://assets/meshy/%s/rig.json" % body))
		for side in ["r", "l"]:
			var held := str(look.get(side, ""))
			if held == "" or str(View.MESHY_WEAPON_LIKE.get(held.substr(3), "")).contains("book"):
				continue                                    # (a tome lies on an open hand)
			n_hand += 1
			if not (rig is Dictionary and (rig as Dictionary).has("grip_" + side)):
				open.append("%s.%s" % [body, side])
	check(n_hand >= 20 and open.is_empty(), "every Meshy body's weapon hand is posed as a fist round the handle (%d hands) %s" % [n_hand, str(open)])
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
	# ---- 0.31.190: the right hand's crossbows and guns upright in the world (0.31.46's -90 about X turned them upside
	# down: the trigger and a stock's drop on top) -- the piece's up (template +Y) points up, in the idle and the aim
	for hero in ["musketeer", "sniper", "minion_caster"]:
		var looks: Array = [{}]
		for id in Eco.skins_of(hero):
			looks.append({"skin": id})
		for cos in looks:
			for an_key in ["idle", "ability"]:
				var made3: Dictionary = View.make_body(hero, cos)
				root.add_child(made3.body)
				var pl3: AnimationPlayer = made3.player
				pl3.play(str(View.LOOKS[hero][an_key]))
				pl3.seek(0.5 * pl3.current_animation_length, true)
				pl3.speed_scale = 0.0
				guns.append(["%s %s %s" % [hero, str(cos.get("skin", "own")), an_key], made3.body])
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
	var upside := []
	for gb in guns:
		var held: MeshInstance3D = null
		for s in (gb[1] as Node).find_children("*", "BoneAttachment3D", true, false):
			if str((s as BoneAttachment3D).bone_name) == "handslot.r":
				var ms: Array = (s as Node).find_children("*", "MeshInstance3D", true, false)
				if not ms.is_empty():
					held = ms[0]
		if held == null:
			upside.append("%s: nothing held" % gb[0])
			continue
		var b: Basis = held.global_transform.basis.orthonormalized()
		var up: Vector3 = b * Vector3.UP
		var front: Vector3 = b * Vector3.BACK
		var body_front: Vector3 = (gb[1] as Node3D).global_transform.basis.z.normalized()
		if up.y < 0.4 or front.dot(body_front) < 0.4:
			upside.append("%s up %s front %s" % [gb[0], str(up.snapped(Vector3.ONE * 0.01)), str(front.snapped(Vector3.ONE * 0.01))])
	check(guns.size() >= 14 and upside.is_empty(), "the right hand's crossbows and guns are upright and point forward, idle and aiming (%d) %s" % [guns.size(), str(upside)])
	print("WEAPON_GRIP_PASS" if fails.is_empty() else "WEAPON_GRIP_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
	return false
