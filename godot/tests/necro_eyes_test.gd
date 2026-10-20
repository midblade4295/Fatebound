extends SceneTree
# The Necromancer's eyes (0.31.192, Kevin: "add glow/smoky effects to the necromancers eyes"): siege_view.EYE_FX /
# eye_fx.gd -- on his own look and both outfits each eye glows (a halo and a white-hot core) in the outfit's colour and
# streams wisps and smoke; with fewer effects on ("lite") the glow only; the eyes sit on his face (in front of his head,
# a hair apart -- where the painted eyes are) and follow the head; nobody else gets them.
#   godot --headless --path godot -s res://tests/necro_eyes_test.gd
const View = preload("res://scripts/siege/siege_view.gd")
const Eco = preload("res://scripts/meta/economy.gd")
var fails: Array = []
var bodies: Array = []       # [label, body, player, lite, colour]
var f := 0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	var e: Dictionary = View.EYE_FX["meshy:necromancer"]
	var looks: Array = [["own", {}, str(e.col)]]
	for id in Eco.skins_of("necromancer"):
		looks.append([id, {"skin": id}, str((e.skins as Dictionary).get(id, e.col))])
	check(looks.size() == 3 and (e.skins as Dictionary).size() == 2, "his own look and both outfits (%d)" % looks.size())
	for l in looks:
		for lite in [false, true]:
			var cos: Dictionary = (l[1] as Dictionary).duplicate()
			if lite:
				cos["lite"] = true
			var made: Dictionary = View.make_body("necromancer", cos)
			root.add_child(made.body)
			var pl: AnimationPlayer = made.player
			pl.play(str(View.LOOKS.necromancer.idle))
			bodies.append(["%s%s" % [l[0], " lite" if lite else ""], made.body, pl, lite, Color(str(l[2]))])
	var other: Dictionary = View.make_body("mage", {})
	root.add_child(other.body)
	bodies.append(["mage", other.body, other.player, false, Color.BLACK])

func _process(_d: float) -> bool:
	f += 1
	if f < 6:
		return false
	for b in bodies:
		var body: Node3D = b[1]
		var fx: Node3D = body.find_child("EyeFx", true, false)
		if str(b[0]) == "mage":
			check(fx == null, "the Mage has no glowing eyes")
			continue
		if fx == null:
			check(false, "%s: eyes" % b[0])
			continue
		var eyes: Array = fx.get_children()
		var glows := 0
		var smokes := 0
		var col_ok := true
		for eye in eyes:
			for c in (eye as Node).get_children():
				if c is MeshInstance3D:
					glows += 1
					var m: ShaderMaterial = (c as MeshInstance3D).material_override
					var t: Color = m.get_shader_parameter("tint")
					col_ok = col_ok and (str(c.name) != "Glow" or Color(t, 1.0).is_equal_approx(Color(b[4] as Color, 1.0)))
				elif c is GPUParticles3D:
					smokes += 1
					col_ok = col_ok and (c as GPUParticles3D).emitting
		var want_smoke := 0 if bool(b[3]) else 4
		check(eyes.size() == 2 and glows == 4 and smokes == want_smoke and col_ok,
			"%s: two eyes, each a glow and a core in %s%s (eyes %d, glows %d, smoke %d)" % [b[0], (b[4] as Color).to_html(false),
			"" if bool(b[3]) else ", wisps and smoke", eyes.size(), glows, smokes])
		# on his face: in front of the head bone, level with it, a hand's width apart
		var sk: Skeleton3D = body.find_child("Skeleton3D", true, false)
		var head := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("head"))).origin
		var front: Vector3 = body.global_transform.basis.z.normalized()
		if eyes.size() == 2:
			var p0: Vector3 = (eyes[0] as Node3D).global_position
			var p1: Vector3 = (eyes[1] as Node3D).global_position
			var gap := p0.distance_to(p1)
			var mid := (p0 + p1) * 0.5
			check(gap > 0.08 and gap < 0.4 and (mid - head).dot(front) > 0.05 and (mid - head).length() < 0.6 and absf(p0.y - p1.y) < 0.05,
				"%s: the eyes on his face (%.2f apart, %.2f in front of the head, %.2f above it)" % [b[0], gap, (mid - head).dot(front), mid.y - head.y])
	print("NECRO_EYES_PASS" if fails.is_empty() else "NECRO_EYES_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
	return false
