extends SceneTree
# Bakes the landscape for the terrain renderer (run after changing scripts/siege/siege_land.gd):
#   godot --headless --path godot -s res://tools/bake_land.gd
# Writes assets/terrain/height.res (Image FORMAT_RF, one sample per BAKE_STEP m over bake_rect)
# and assets/terrain/pathmask.res (Image FORMAT_RGBA8, MASK_PPM px per m; R = brick path,
# G = ledge rim rock, B = shadow at the cliff foot, A = painted grass bands).
# tests/siege_land_check.gd fails if these no longer match siege_land.gd.
const Land = preload("res://scripts/siege/siege_land.gd")

func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var r := Land.bake_rect()
	var nx := int(round(r.size.x / Land.BAKE_STEP)) + 1
	var nz := int(round(r.size.y / Land.BAKE_STEP)) + 1
	var hf := PackedFloat32Array()
	hf.resize(nx * nz)
	for j in nz:
		for i in nx:
			hf[j * nx + i] = Land.terrain_height(r.position + Vector2(i, j) * Land.BAKE_STEP)
	var himg := Image.create_from_data(nx, nz, false, Image.FORMAT_RF, hf.to_byte_array())
	var e1 := ResourceSaver.save(himg, Land.HEIGHT_RES)
	# Path mask: 1 inside the path, soft 0.6 m edge.
	var mw := int(round(r.size.x * Land.MASK_PPM))
	var mh := int(round(r.size.y * Land.MASK_PPM))
	var md := PackedByteArray()
	md.resize(mw * mh * 4)
	var segs := []
	for pl in Land.paths():
		for i in range(pl.size() - 1):
			segs.append([pl[i], pl[i + 1]])
	for j in mh:
		for i in mw:
			var p := r.position + (Vector2(i, j) + Vector2(0.5, 0.5)) / Land.MASK_PPM
			var best := INF
			for sg in segs:
				var a: Vector2 = sg[0]
				var ab: Vector2 = (sg[1] as Vector2) - a
				var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
				best = minf(best, p.distance_to(a + ab * t))
			var k := (j * mw + i) * 4
			md[k] = int(255.0 * (1.0 - clampf((best - (Land.PATH_HALF_W - 0.3)) / 0.6, 0.0, 1.0)))
			var rs := Land.ledge_rim(p)
			md[k + 1] = int(255.0 * rs.x)
			md[k + 2] = int(255.0 * rs.y)
			md[k + 3] = int(255.0 * Land.grass_band(p))
	var mimg := Image.create_from_data(mw, mh, false, Image.FORMAT_RGBA8, md)
	var e2 := ResourceSaver.save(mimg, Land.MASK_RES)
	print("BAKE_LAND height %dx%d (err %d)  mask %dx%d (err %d)  in %d ms" % [nx, nz, e1, mw, mh, e2, Time.get_ticks_msec() - t0])
	_bake_cache()
	quit(0 if e1 == OK and e2 == OK else 1)

func _bake_cache() -> void:
	# 0.31.8: the start-up cache (see scripts/siege/terrain_cache.gd).
	var tc := Time.get_ticks_msec()
	var View = load("res://scripts/siege/siege_view.gd")
	var Sim = load("res://scripts/siege/siege_sim.gd")
	var cache = load("res://scripts/siege/terrain_cache.gd").new()
	cache.key = Land.bake_key()
	View._terrain_meshes = []
	View._outer_meshes = []
	cache.terrain = View._make_terrain_meshes()
	cache.outer = View._make_outer_meshes()
	var sim = Sim.new()
	sim.setup(16, 1)
	var v = View.new()
	v.sim = sim
	cache.foliage = v._plan_foliage()
	cache.outer_trees = View._plan_outer_trees()
	v.free()
	for k in 4:
		cache.blood.append(View._blood_image(71 + k * 13, false))
	cache.blood.append(View._blood_image(503, true))
	var err := ResourceSaver.save(cache, "res://assets/terrain/cache.res")
	var fol := 0
	for kind in cache.foliage:
		fol += (cache.foliage[kind] as Array).size()
	var trees := 0
	for k in cache.outer_trees:
		trees += (cache.outer_trees[k] as Array).size()
	print("BAKE_CACHE terrain %d meshes, outer %d, foliage %d instances, outer trees %d, blood %d (err %d) in %d ms" % [cache.terrain.size(), cache.outer.size(), fol, trees, cache.blood.size(), err, Time.get_ticks_msec() - tc])
