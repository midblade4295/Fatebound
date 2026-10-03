extends SceneTree
# A flat plan of the battlefield from the land/sim data (no rendering needed): terrain shaded by
# height, water, rock, brick paths, walls, bridges, towers with their capture rings, resources.
#   godot --headless --path godot -s res://tools/map_plan.gd   -> /tmp/map_plan.png
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Land = preload("res://scripts/siege/siege_land.gd")
const PPM := 6.0

func _init() -> void:
	var s = Sim.new()
	s.setup(4, 1)
	var r := Land.bake_rect()
	var w := int(r.size.x * PPM)
	var h := int(r.size.y * PPM)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for j in h:
		for i in w:
			var p := r.position + Vector2(i + 0.5, j + 0.5) / PPM
			var ht := Land.terrain_height(p)
			var c := Color("#6fb24a")
			var ed := Land.edge_dist(p)
			if Land.shore(p) < 0.0 and ed <= 2.0:
				c = Color("#2f86c9")
			elif ed > 0.4:
				c = Color("#7d7a72")
			else:
				var rs := Land.ledge_rim(p)
				if rs.x > 0.5:
					c = Color("#8a857a")
				if Land.dist_to_paths(p) < Land.PATH_HALF_W and rs.x <= 0.5:
					c = Color("#c9a46a")
				c = c.lightened(clampf(ht / 6.0, 0.0, 0.35)) if ht > 0.2 else c
			if Land.on_bridge(p, 0.0):
				c = Color("#8b5a2b")
			if absf(p.x) <= Sim.CASTLE_HX and absf(p.y) >= Sim.CASTLE_SHIFT + Sim.FRONT_Z:
				c = c.lerp(Color("#d8c9a0"), 0.6)
			img.set_pixel(i, j, c)
	var px := func(q: Vector2) -> Vector2i:
		return Vector2i(int((q.x - r.position.x) * PPM), int((q.y - r.position.y) * PPM))
	var disc := func(q: Vector2, rad: float, col: Color):
		var cpt: Vector2i = px.call(q)
		var rr := int(rad * PPM)
		for dy in range(-rr, rr + 1):
			for dx in range(-rr, rr + 1):
				if dx * dx + dy * dy <= rr * rr:
					var x := cpt.x + dx
					var y := cpt.y + dy
					if x >= 0 and y >= 0 and x < w and y < h:
						img.set_pixel(x, y, col)
	for wl in s.walls:
		var a: Vector2 = wl.a
		var b: Vector2 = wl.b
		var n := int(a.distance_to(b) * PPM) + 1
		var col := Color("#202020") if str(wl.kind) in ["wall", "backwall", "edge"] else (Color("#5a3a1a") if str(wl.kind) == "rail" else Color("#404040"))
		for k in n + 1:
			var q: Vector2i = px.call(a.lerp(b, float(k) / n))
			if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h:
				img.set_pixel(q.x, q.y, col)
	for nd in s.nodes:
		disc.call(nd.p, 1.0, Color("#1e5e1e") if nd.kind == "wood" else Color("#b0b0b0"))
	for ob in s.obstacles:
		if str(ob.kind) == "rock" and not ob.has("node"):
			disc.call(ob.p, 1.2, Color("#6a6a6a"))
	for op in s.outposts:
		for k in 64:
			var q: Vector2i = px.call((op.p as Vector2) + Vector2(cos(k * TAU / 64), sin(k * TAU / 64)) * Land.OUTPOST_R)
			img.set_pixel(clampi(q.x, 0, w - 1), clampi(q.y, 0, h - 1), Color.WHITE)
		disc.call(op.p, Land.OUTPOST_TOWER_R, Color("#f0e0a0"))
	for t in 2:
		disc.call(Sim.spawn(t), 1.0, [Color("#3fa9f5"), Color("#ff6a3d")][t])
	img.save_png("/tmp/map_plan.png")
	print("MAP_PLAN ", w, "x", h)
	quit()
