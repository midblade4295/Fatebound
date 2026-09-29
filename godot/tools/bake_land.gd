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
	quit(0 if e1 == OK and e2 == OK else 1)
