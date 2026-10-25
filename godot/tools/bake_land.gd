extends SceneTree
# Bakes the landscape for the terrain renderer (run after changing scripts/siege/siege_land.gd):
#   godot --headless --path godot -s res://tools/bake_land.gd
# Writes assets/terrain/height.res (Image FORMAT_RF, one sample per BAKE_STEP m over bake_rect)
# and assets/terrain/pathmask.res (Image FORMAT_RGBA8, MASK_PPM px per m; R = dirt path (Land.path_r: 1 on the track's
# middle, 0.5 at its frayed edge, 0 in the grass -- 0.31.126; was a brick path's 0.6 m edge),
# G = ledge rim rock, B = shadow at the cliff foot, A = the lanes' paving (0.31.216; painted grass bands until then)).
# tests/siege_land_check.gd fails if these no longer match siege_land.gd.
const Land = preload("res://scripts/siege/siege_land.gd")
const Keep = preload("res://scripts/siege/keep.gd")

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
	# Path mask (0.31.126): Land.path_r of the distance to the nearest smoothed centre line. The segments are bucketed in
	# CELL-metre squares (each into every square within REACH of it), so a pixel only measures the few nearby.
	# 0.31.216: R the jungle trails' (and the pits' arenas') earth only; A the lanes' paving (Land.lane_pave) -- the
	# painted bands A carried until then are gone with the Fat Princess grass.
	var mw := int(round(r.size.x * Land.MASK_PPM))
	var mh := int(round(r.size.y * Land.MASK_PPM))
	var md := PackedByteArray()
	md.resize(mw * mh * 4)
	const CELL := 4.0
	var reach := Land.PATH_CORE + Land.PATH_FADE + 1.0          # (beyond this R is 0 whatever the wobble)
	reach = maxf(reach, Land.LANE_PAVE_HALF + 2.0)
	var buckets := {}
	# the lanes (kind 1), then the jungle trails (kind 0: narrower, their distance pushed out by the difference)
	var lines := []
	for pl in Land.paths():
		lines.append([pl, 0.0, 1])
	for pl in Land.trails():
		lines.append([pl, Land.PATH_HALF_W - Land.TRAIL_HALF, 0])
	for ln in lines:
		var pl: Array = ln[0]
		for i in range(pl.size() - 1):
			var a0: Vector2 = pl[i]
			var b0: Vector2 = pl[i + 1]
			var lo := Vector2(minf(a0.x, b0.x), minf(a0.y, b0.y)) - Vector2(reach, reach)
			var hi := Vector2(maxf(a0.x, b0.x), maxf(a0.y, b0.y)) + Vector2(reach, reach)
			for cx in range(int(floor(lo.x / CELL)), int(floor(hi.x / CELL)) + 1):
				for cz in range(int(floor(lo.y / CELL)), int(floor(hi.y / CELL)) + 1):
					var key := Vector2i(cx, cz)
					if not buckets.has(key):
						buckets[key] = []
					(buckets[key] as Array).append([a0, b0 - a0, float(ln[1]), int(ln[2])])
	for j in mh:
		for i in mw:
			var p := r.position + (Vector2(i, j) + Vector2(0.5, 0.5)) / Land.MASK_PPM
			var best := INF
			var lane := INF
			for sg in buckets.get(Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL))), []):
				var a: Vector2 = sg[0]
				var ab: Vector2 = sg[1]
				var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
				var d := p.distance_to(a + ab * t)
				if int(sg[3]) == 1:
					lane = minf(lane, d)
				else:
					best = minf(best, d + float(sg[2]))
			var k := (j * mw + i) * 4
			var gd := Land.ground_dist(p, best)                    # (0.31.127: and the pits' trodden arenas)
			md[k] = int(255.0 * Land.path_r(gd, p)) if gd < INF else 0
			var rs := Land.ledge_rim(p)
			md[k + 1] = int(255.0 * rs.x)
			md[k + 2] = int(255.0 * rs.y)
			md[k + 3] = int(255.0 * Land.lane_pave(lane, p)) if lane < INF else 0
	var mimg := Image.create_from_data(mw, mh, false, Image.FORMAT_RGBA8, md)
	var e2 := ResourceSaver.save(mimg, Land.MASK_RES)
	print("BAKE_LAND height %dx%d (err %d)  mask %dx%d (err %d)  in %d ms" % [nx, nz, e1, mw, mh, e2, Time.get_ticks_msec() - t0])
	_bake_minimap(mimg)
	_bake_cache()
	quit(0 if e1 == OK and e2 == OK else 1)

# 0.31.216 (the landscape HUD's minimap, minimap.gd): the field as a flat painted plan in world orientation (x right,
# y down) over Land.bake_rect, MINIMAP_PX square -- grass, the lanes' paving, the trails, the river, the rock walls and
# tree lines, the keeps' floors, dark beyond the edge. The HUD turns it to the camera's view.
const MINIMAP_PX := 256
const MINIMAP_RES := "res://assets/terrain/minimap.png"

func _bake_minimap(mask: Image) -> void:
	var r := Land.bake_rect()
	var img := Image.create(MINIMAP_PX, MINIMAP_PX, false, Image.FORMAT_RGBA8)
	for j in MINIMAP_PX:
		for i in MINIMAP_PX:
			var p := r.position + Vector2((i + 0.5) / MINIMAP_PX * r.size.x, (j + 0.5) / MINIMAP_PX * r.size.y)
			var mx := clampi(int((p.x - r.position.x) * Land.MASK_PPM), 0, mask.get_width() - 1)
			var my := clampi(int((p.y - r.position.y) * Land.MASK_PPM), 0, mask.get_height() - 1)
			var mk := mask.get_pixel(mx, my)
			var c := Color("#5c9a3c").lerp(Color("#6fae47"), 0.5 + 0.5 * Land.wobble(p * 0.13))
			var ed := Land.edge_dist(p)
			var wet := Land.shore(p) < 0.0
			if ed > 0.6 and not (wet and absf(p.y) < 16.0):
				c = Color("#26372a")
			elif Land.keep_dist(p) < Keep.R + 0.4:
				c = Color("#d8c38e")
			elif mk.a > 0.5:
				c = Color("#cbc3ab")
			elif wet:
				c = Color("#3fa9b8")
			elif mk.r > 0.5:
				c = Color("#a3824f")
			else:
				var rd := Land.ridge_dist(p)
				if rd.x < rd.y + 0.5:
					c = Color("#6d7682")
			img.set_pixel(i, j, c)
	var err := img.save_png(ProjectSettings.globalize_path(MINIMAP_RES))
	print("BAKE_MINIMAP %dpx (err %d)" % [MINIMAP_PX, err])

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
	sim.setup(5, 1)
	sim.setup_moba("knight", 1)                  # (0.31.165: the 5v5's towers and Kings stand clear of the grass)
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
