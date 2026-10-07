extends SceneTree
# The outposts' Meshy keeps (0.31.73, Kevin: "a different model for each outpost so it shows variety"): five different
# models, each scaled so units walking its deck stay inside its parapet, its deck height (Land.OUTPOST_LOOKS.floor,
# where units up there are drawn and shots start) matching the model, doors towards their own side, the beacon's
# fire basket kept clear, and the owner's colours set on the one material.
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Land = preload("res://scripts/siege/siege_land.gd")
const View = preload("res://scripts/siege/siege_view.gd")
var fails := []

func check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)
		print("FAIL ", what)
	else:
		print("ok   ", what)

func _init() -> void:
	var looks: Array = Land.OUTPOST_LOOKS
	var posts: Array = Land.outpost_positions()
	check(looks.size() == posts.size(), "a look for every outpost (%d)" % posts.size())
	var models := {}
	for i in looks.size():
		var lk: Dictionary = looks[i]
		models[lk.model] = true
		var spec: Dictionary = View.OUTPOST_MODELS.get(lk.model, {})
		check(not spec.is_empty(), "%s is described in OUTPOST_MODELS" % lk.model)
		if spec.is_empty():
			continue
		var s := float(lk.s)
		var floor_m := (float(spec.deck) - float(spec.sink)) * s * float(lk.get("sy", 1.0))
		check(absf(floor_m - float(lk.floor)) < 0.02, "%s: deck height %.2f matches the model (%.2f)" % [lk.model, float(lk.floor), floor_m])
		check(float(spec.inner) * s >= Land.TOWER_TOP_R + 0.3, "%s: parapet inside at %.2f m, units walk to %.2f m" % [lk.model, float(spec.inner) * s, Land.TOWER_TOP_R])
		check(float(lk.get("sy", 1.0)) >= 1.0 and float(lk.get("sy", 1.0)) <= 1.35, "%s: stretched at most 35 %% taller" % lk.model)
		check(float(spec.base) * s <= 6.5, "%s: foot (%.1f m) inside the level patch / capture ring" % [lk.model, float(spec.base) * s])
		check(ResourceLoader.exists("res://assets/meshy/%s/%s.glb" % [lk.model, lk.model]) and
			ResourceLoader.exists("res://assets/meshy/%s/%s_glow.png" % [lk.model, lk.model]), "%s: model and glow mask imported" % lk.model)
		var p: Vector2 = posts[i]
		var want := 0.0 if p.y > 0.5 else (PI if p.y < -0.5 else float(lk.yaw))
		check(is_equal_approx(float(lk.yaw), want), "%s: its door faces its own side's castle" % lk.model)
		check(absf(Land.tower_floor(i) - float(lk.floor)) < 0.001, "tower_floor(%d)" % i)
	check(models.size() == looks.size(), "every outpost a different model (%d)" % models.size())
	check(Land.tower_floor(-1) == 0.0 and Land.tower_floor(99) == 0.0, "no deck height for a bad id")

	# The beacon's fire basket: a no-go spot on the island deck, off the middle, within the walkable radius.
	var island := posts.find(Land.ISLAND_TOWER)
	var b := Land.tower_block(island)
	var bc := Vector2(b.x, b.y)
	check(b.z > 0.0 and bc.length() > b.z and bc.length() - b.z < Land.TOWER_TOP_R, "the island deck keeps units out of the fire basket, the middle free")
	check(Land.tower_block(0).z == 0.0, "other decks have none")
	var sim = Sim.new()
	sim.setup(2, 7)
	var op: Dictionary = sim.outposts[island]
	op.owner = 0
	var u: Dictionary = sim.units.filter(func(x): return x.team == 0)[0]
	sim._set_class(u, "ranger", false)
	u.bot = false
	u.pos = (op.p as Vector2) + bc * 0.2
	check(sim._enter_tower(u, op), "a ranger climbs the beacon")
	var worst := INF
	for k in 60:
		u.move = bc.normalized()                          # walking straight at the fire
		sim.step()
		if int(u.tower) != island:
			break
		worst = minf(worst, (u.pos - (op.p as Vector2)).distance_to(bc))
	check(int(u.tower) == island and worst >= b.z - 0.05, "walking at the fire stops at its edge (%.2f m from it, keep %.2f)" % [worst, b.z])

	# The keep and its owner's colours (one ShaderMaterial on every mesh of the model).
	var root := View.outpost_model(island)
	check(root != null, "the beacon keep builds")
	if root != null:
		var mat: ShaderMaterial = root.get_meta("mat")
		var meshes := root.find_children("*", "MeshInstance3D", true, false)
		check(not meshes.is_empty() and meshes.all(func(m): return (m as MeshInstance3D).material_override == mat), "its meshes use the team material")
		check(mat.get_shader_parameter("albedo_tex") != null, "with the model's own texture")
		for t in [-1, 0, 1]:
			View._set_outpost_owner(root, t)
			check(int(mat.get_shader_parameter("team")) == t, "owner %d sets the colours" % t)
		check((mat.get_shader_parameter("glow_color") as Color).is_equal_approx(View.OUTPOST_GLOW[1]), "the beacon glows in the holder's colour")
		var top := root.transform * (View.outpost_point(root, Vector3(0.0, float(View.OUTPOST_MODELS.outpost_beacon.deck) - float(View.OUTPOST_MODELS.outpost_beacon.foot), 0.0)))
		check(absf(top.y - (Sim.height_at(Land.ISLAND_TOWER) + Land.tower_floor(island))) < 0.02, "its deck is where units are drawn")
		root.free()
	print("OUTPOST_LOOK_PASS" if fails.is_empty() else "OUTPOST_LOOK_FAIL %s" % [fails])
	quit(0 if fails.is_empty() else 1)
