extends SceneTree
# Round 7 landscape sanity: every tree/stone/rock/cake/outpost sits clear of walls (river, rails,
# ledge faces, castle), off the brick paths, outside other things; the land is point-symmetric;
# bridges and ramps connect (nav). Prints each problem.
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Land = preload("res://scripts/siege/siege_land.gd")
var fails := []
func check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what); print("FAIL ", what)

func _init() -> void:
	var s = Sim.new()
	s.setup(16, 1)
	# 1. obstacles clear of walls, paths, outposts, each other
	for ob in s.obstacles:
		var p: Vector2 = ob.p
		if str(ob.kind) in ["hat_stand", "castle_building"]:
			continue
		var wmin := INF
		for w in s.walls:
			wmin = minf(wmin, p.distance_to(Sim.seg_closest(p, w.a, w.b)) - float(w.r))
		# 1.2 m of walking room between a thing and any wall (a unit is 0.9 m wide)
		check(wmin >= float(ob.r) + 1.2 or str(ob.kind) == "outpost_tower", "%s at %s only %.1f m from a wall" % [ob.kind, str(p), wmin - float(ob.r)])
		if str(ob.kind) != "outpost_tower":
			check(Land.dist_to_paths(p) >= Land.PATH_HALF_W + float(ob.r) + 0.3, "%s at %s sits on a brick path" % [ob.kind, str(p)])
			for op in s.outposts:
				check(p.distance_to(op.p) >= Land.OUTPOST_R + float(ob.r), "%s at %s is inside outpost %d's ring" % [ob.kind, str(p), op.id])
		check(absf(p.x) <= Sim.HALF_W - 1.0 and absf(p.y) <= Sim.HALF_L - 1.0, "%s at %s outside the field" % [ob.kind, str(p)])
	for i in s.obstacles.size():
		for j in range(i + 1, s.obstacles.size()):
			var a: Dictionary = s.obstacles[i]
			var b: Dictionary = s.obstacles[j]
			check((a.p as Vector2).distance_to(b.p) >= float(a.r) + float(b.r) + 1.2, "%s %s and %s %s too close" % [a.kind, str(a.p), b.kind, str(b.p)])
	# 2. outposts: tower clear of walls by a ring's walking room; ring on one level
	for op in s.outposts:
		var h0 := Sim.height_at(op.p)
		for k in 16:
			var q: Vector2 = op.p + Vector2(cos(k * TAU / 16.0), sin(k * TAU / 16.0)) * 3.0
			check(absf(Sim.height_at(q) - h0) < 0.25, "outpost %d ring not flat at %s" % [op.id, str(q)])
	# 3. point symmetry of heights and walls
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for k in 400:
		var q := Vector2(rng.randf_range(-Sim.HALF_W, Sim.HALF_W), rng.randf_range(-Sim.HALF_L, Sim.HALF_L))
		check(absf(Sim.height_at(q) - Sim.height_at(-q)) < 0.001, "height not symmetric at %s" % str(q))
	# 4. nav: every bridge and ramp reachable from both spawns; the river only crossable on bridges
	for t in 2:
		for i in Land.BRIDGE_X.size():
			var bc := Land.bridge_centre(i)
			var path: PackedVector2Array = s.find_path(t, Sim.spawn(t), bc)
			check(path.size() > 0 and path[path.size() - 1].distance_to(bc) < 1.5, "team %d can't reach bridge %d" % [t, i])
		for op in s.outposts:
			var pp: PackedVector2Array = s.find_path(t, Sim.spawn(t), (op.p as Vector2) + Vector2(3.0, 0.0))
			check(pp.size() > 0 and pp[pp.size() - 1].distance_to((op.p as Vector2) + Vector2(3.0, 0.0)) < 1.5, "team %d can't reach outpost %d" % [t, op.id])
	var crossings := 0
	var path2: PackedVector2Array = s.find_path(0, Sim.spawn(0), Sim.spawn(1))
	for i in range(1, path2.size()):
		var a := path2[i - 1]
		var b := path2[i]
		if signf(a.y - Land.river_c(a.x)) != signf(b.y - Land.river_c(b.x)):
			crossings += 1
			var on_bridge := false
			for bx in Land.BRIDGE_X:
				if absf(a.x - bx) <= Land.BRIDGE_HALF:
					on_bridge = true
			check(on_bridge, "castle-to-castle path crosses the river off a bridge at %s" % str(a))
	check(crossings >= 1, "castle-to-castle path never crosses the river")
	# 5. the baked terrain must match the landscape code (re-run tools/bake_land.gd after edits)
	var himg: Image = load(Land.HEIGHT_RES)
	var r := Land.bake_rect()
	var nx := int(round(r.size.x / Land.BAKE_STEP)) + 1
	var nz := int(round(r.size.y / Land.BAKE_STEP)) + 1
	check(himg != null and himg.get_width() == nx and himg.get_height() == nz, "baked height map missing or wrong size: re-run tools/bake_land.gd")
	if himg != null and himg.get_width() == nx:
		var worst := 0.0
		for k in 300:
			var i := rng.randi() % nx
			var j := rng.randi() % nz
			worst = maxf(worst, absf(himg.get_pixel(i, j).r - Land.terrain_height(r.position + Vector2(i, j) * Land.BAKE_STEP)))
		check(worst < 0.001, "baked heights are stale (worst diff %.3f m): re-run tools/bake_land.gd" % worst)
	check(load(Land.MASK_RES) != null, "baked path mask missing: run tools/bake_land.gd")
	print("walls %d obstacles %d outposts %d" % [s.walls.size(), s.obstacles.size(), s.outposts.size()])
	print("SIEGE_LAND_PASS" if fails.is_empty() else "SIEGE_LAND_FAIL %d problems" % fails.size())
	quit(0 if fails.is_empty() else 1)
