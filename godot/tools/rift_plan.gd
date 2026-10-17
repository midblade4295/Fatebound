extends SceneTree
# 0.31.165: a flat plan of the Rift from the land / sim / 5v5 data (no rendering needed) -- ground and water, the fords,
# the dirt lanes and trails, the ridges and pits' rims, the keeps' walls and gates, the towers with their reach, the
# camps, the brush, the Kings and fountains.
#   godot --headless --path godot -s res://tools/rift_plan.gd   -> /tmp/rift_plan.png  (OUT=path to change)
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Land = preload("res://scripts/siege/siege_land.gd")
const Moba = preload("res://scripts/siege/moba.gd")
const PPM := 5.0

var img: Image
var r: Rect2

func _init() -> void:
	var s = Sim.new()
	s.setup(5, 1)
	s.setup_moba("knight", 1)
	var m = s.moba
	r = Land.bake_rect()
	var w := int(r.size.x * PPM)
	var h := int(r.size.y * PPM)
	img = Image.create(w, h, false, Image.FORMAT_RGB8)
	for j in h:
		for i in w:
			var p := r.position + Vector2(i + 0.5, j + 0.5) / PPM
			var c := Color("#6fb24a")
			var ed := Land.edge_dist(p)
			if ed > 0.4:
				c = Color("#7d7a72")
			elif Land.shore(p) < 0.0:
				c = Color("#2f86c9") if not Land.on_ford(p) else Color("#b8b09a")
			else:
				var ht := Land.ground_height(p)
				c = c.lightened(clampf(ht * 0.25, 0.0, 0.2)) if ht > 0.0 else c.darkened(clampf(-ht * 0.25, 0.0, 0.2))
			if Sim.in_castle(p, 0) or Sim.in_castle(p, 1):
				c = c.lerp(Color("#d8c9a0"), 0.6)
			img.set_pixel(i, j, c)
	for pl in Land.paths():
		for k in range(0, pl.size() - 1, 2):
			_seg(pl[k], pl[mini(k + 2, pl.size() - 1)], Land.PATH_HALF_W, Color("#c9a46a"), 0.8)
	for pl in Land.trails():
		for k in range(0, pl.size() - 1, 2):
			_seg(pl[k], pl[mini(k + 2, pl.size() - 1)], Land.TRAIL_HALF, Color("#c9a46a"), 0.6)
	for b in m.vision.brushes:
		_disc(b.p, float(b.r), Color("#2e6b2a"), 0.75)
	for wl in s.walls:
		var col := Color("#3b3b3b") if str(wl.kind) == "wall" else (Color("#5a5650") if str(wl.kind) == "rock" else Color("#444"))
		_seg(wl.a, wl.b, float(wl.r), col)
	for g in s.gates:
		_seg(g.a, g.b, 0.6, Color("#b5651d"))
	for ob in s.obstacles:
		if str(ob.kind) == "castle_building":
			_disc(ob.p, float(ob.r), Color("#7a5a2a"), 1.0)
	for tw in m.towers:
		var tc := Color("#3a6fd8") if int(tw.team) == 0 else Color("#d83a3a")
		_ring(tw.p, Moba.TOWER_RANGE, tc)
		_disc(tw.p, Moba.TOWER_R, tc, 1.0)
		_disc(tw.p, 0.5, Color.WHITE if int(tw.tier) == 4 else Color.BLACK, 1.0)
	for c in m.camps:
		var cc := {"pack":Color("#9b59d0"), "archers":Color("#9b59d0"), "arcane":Color("#5ad0ff"), "ember":Color("#ff8a2a"), "lord":Color("#222244")}
		_disc(c.p, 2.2 if str(c.kind) != "lord" else 3.0, cc.get(str(c.kind), Color.MAGENTA), 0.9)
		_ring(c.p, Moba.LEASH, Color(0.6, 0.3, 0.8))
	for t in 2:
		_disc(s.throne(t), 1.2, Color("#ffd700"), 1.0)
		_ring(s.spawn(t), 3.2, Color("#aee8ff"))
	for i in 2:
		_ring(Land.pit_c(i), Land.PIT_R + 1.0, Color("#222"))
	# 20 m scale bar
	_seg(r.position + Vector2(4, r.size.y - 4), r.position + Vector2(24, r.size.y - 4), 0.4, Color.WHITE)
	var out := OS.get_environment("OUT") if OS.has_environment("OUT") else "/tmp/rift_plan.png"
	img.save_png(out)
	print("RIFT_PLAN ", out, " walls ", s.walls.size(), " fills ", s.squeeze_fills, " towers ", m.towers.size(), " camps ", m.camps.size(),
		" brushes ", m.vision.brushes.size())
	quit(0)

func _px(q: Vector2) -> Vector2:
	return (q - r.position) * PPM

func _disc(q: Vector2, rad: float, col: Color, a: float) -> void:
	var c := _px(q)
	var rr := rad * PPM
	for y in range(int(c.y - rr), int(c.y + rr) + 1):
		for x in range(int(c.x - rr), int(c.x + rr) + 1):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and Vector2(x, y).distance_to(c) <= rr:
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(col, a))

func _ring(q: Vector2, rad: float, col: Color) -> void:
	var n := int(rad * PPM * 6.0)
	for k in n:
		var p := _px(q + Vector2.from_angle(TAU * k / n) * rad)
		if p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height():
			img.set_pixel(int(p.x), int(p.y), col)

func _seg(a: Vector2, b: Vector2, rad: float, col: Color, al := 1.0) -> void:
	var lo := _px(Vector2(minf(a.x, b.x) - rad, minf(a.y, b.y) - rad))
	var hi := _px(Vector2(maxf(a.x, b.x) + rad, maxf(a.y, b.y) + rad))
	for y in range(int(lo.y), int(hi.y) + 1):
		for x in range(int(lo.x), int(hi.x) + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var q := r.position + Vector2(x + 0.5, y + 0.5) / PPM
			if q.distance_to(Sim.seg_closest(q, a, b)) <= rad:
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(col, al))
