extends SceneTree
# Dev tool (0.31.174, Kevin: "Go through and audit the pathing of map. There's a lot of paths that go through
# unpassable walls"): the Rift's dirt paths -- the baked mask the terrain draws (assets/terrain/pathmask.res) -- against
# the walls the 5v5's sim stops units at (the ridges' rock and tree lines, the pits' rims, the field's edge, the keeps'
# ring walls; a gate's doorway is a way through).
#   godot --headless --path godot -s res://tools/path_audit.gd        [OUT=/tmp/path_audit.png] [MASK=another pathmask.res]
# Every dirt pixel (R >= 0.5: the track's edge and in) within MARGIN of a wall's body (MARGIN_TREES of a tree line's:
# the canopies reach further) is a conflict: under its rocks or trees, or in it. A pit's own trodden floor inside its
# rim isn't (the arena is meant to meet its rocks). Conflicts are grouped by wall and listed (where, how much dirt,
# which path runs there); the map is written to OUT (4 px a metre, blue's keep at the bottom: grass, dirt, the walls
# dark, conflicts red, gates cyan).
# Prints PATH_AUDIT_CLEAN when there are none.
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Land = preload("res://scripts/siege/siege_land.gd")
const Keep = preload("res://scripts/siege/keep.gd")
const MARGIN := 1.0          # dirt this close to a wall's body (its r) is under its rocks
const MARGIN_TREES := 1.5    # ...or under a tree line's canopies
const GATE_CLEAR := 3.0      # a lane's dirt this close to a gate's doorway is going through it

func _init() -> void:
	var sim = Sim.new()
	sim.setup(5, 1)
	sim.setup_moba("knight", 1)
	var ppm := Land.MASK_PPM
	var img := Image.create(int(Sim.HALF_W * 2.0 * ppm), int(Sim.HALF_L * 2.0 * ppm), false, Image.FORMAT_RGB8)
	var res := audit(sim, img, OS.get_environment("MASK") if OS.has_environment("MASK") else Land.MASK_RES)
	for line in res.lines:
		print(line)
	var out := OS.get_environment("OUT") if OS.has_environment("OUT") else "/tmp/path_audit.png"
	img.save_png(out)
	print("PATH_AUDIT %d walls touched, %.1f m2 of %.1f m2 of dirt; map %s" % [res.lines.size(), res.area, res.dirt, out])
	if res.lines.is_empty():
		print("PATH_AUDIT_CLEAN")
	quit(0)

# The conflicts in a 5v5 sim's walls: {lines: one per wall touched, area: m2 of dirt in conflict, dirt: m2 of dirt in
# the field}; img (optional, 4 px a metre) gets the map. (tests/path_clear_test.gd runs it.)
static func audit(sim, img: Image = null, mask_path := Land.MASK_RES) -> Dictionary:
	var mask: Image = load(mask_path)
	var rect := Land.bake_rect()
	var ppm := Land.MASK_PPM
	var walls: Array = sim.walls
	var lines := []                      # [name, smoothed points]
	for i in Land.paths().size():
		lines.append(["lane %d" % i, Land.paths()[i]])
	for i in Land.trails().size():
		lines.append(["trail %d%s" % [i / 2, " (red's)" if i % 2 == 1 else ""], Land.trails()[i]])
	var w_img := int(Sim.HALF_W * 2.0 * ppm)
	var h_img := int(Sim.HALF_L * 2.0 * ppm)
	var groups := {}                     # wall index -> {n, in, sum, paths}
	var dirt_px := 0
	for j in h_img:
		for i in w_img:
			# image row 0 = red's end (y -HALF_L) .. blue's keep at the bottom
			var p := Vector2(-Sim.HALF_W + (i + 0.5) / ppm, -Sim.HALF_L + (j + 0.5) / ppm)
			var mx := int((p.x - rect.position.x) * ppm)
			var my := int((p.y - rect.position.y) * ppm)
			var mp := mask.get_pixel(clampi(mx, 0, mask.get_width() - 1), clampi(my, 0, mask.get_height() - 1))
			var inside := Land.inside_field(p)
			var col := Color(0.35, 0.62, 0.3) if inside else Color(0.25, 0.25, 0.25)
			var dirt := (mp.r >= 0.5 or mp.a >= 0.5) and inside          # (0.31.216: the lanes' paving is A)
			if dirt:
				col = Color(0.62, 0.45, 0.26)
				dirt_px += 1
			var near_wall := -1
			var near_d := INF
			for wi in sim._bucket_walls[sim._bucket(p)]:          # (every wall that reaches within 1.6 m of here)
				var w: Dictionary = walls[wi]
				var d: float = p.distance_to(Sim.seg_closest(p, w.a, w.b)) - float(w.r)
				if d < near_d:
					near_d = d
					near_wall = wi
			if near_d < 0.0:
				col = Color(0.12, 0.12, 0.14) if str(walls[near_wall].kind) != "rock" else Color(0.3, 0.3, 0.32)
			for g in sim.gates:
				if p.distance_to(Sim.seg_closest(p, g.a, g.b)) < 0.6:
					col = Color(0.2, 0.85, 0.9)
			var look := _look(walls[near_wall]) if near_wall >= 0 else ""
			if dirt and near_d < (MARGIN_TREES if look.begins_with("(trees") else MARGIN):
				var w2: Dictionary = walls[near_wall]
				var by_gate := look.contains("pit rim") and Land.island_off(p) < 0.0      # (the pit's floor)
				if str(w2.kind) == "wall":
					for g in sim.gates:
						if p.distance_to(g.c) < (g.a as Vector2).distance_to(g.b) * 0.5 + GATE_CLEAR:
							by_gate = true
				if not by_gate:
					col = Color(0.95, 0.1, 0.1) if near_d < 0.0 else Color(1.0, 0.55, 0.1)
					if not groups.has(near_wall):
						groups[near_wall] = {"n": 0, "in": 0, "sum": Vector2.ZERO, "paths": {}}
					var gr: Dictionary = groups[near_wall]
					gr.n += 1
					gr["in"] += 1 if near_d < 0.0 else 0
					gr.sum += p
					var best := ""
					var bd := INF
					for ln in lines:
						var dl := _dist_line(p, ln[1])
						if dl < bd:
							bd = dl
							best = str(ln[0])
					gr.paths[best] = true
			if img != null:
				img.set_pixel(i, j, col)
	var keys := groups.keys()
	keys.sort_custom(func(a, b): return (groups[a].sum / groups[a].n).y > (groups[b].sum / groups[b].n).y)
	var total := 0
	var out := []
	for wi in keys:
		var gr: Dictionary = groups[wi]
		var w: Dictionary = walls[wi]
		total += int(gr.n)
		out.append("CONFLICT %-26s at (%6.1f, %6.1f): %5.1f m2 of dirt under it (%4.1f m2 in it) -- %s" % [
			"%s %s" % [str(w.kind), _look(w)], (gr.sum / gr.n).x, (gr.sum / gr.n).y, gr.n / (ppm * ppm), gr["in"] / (ppm * ppm),
			", ".join(PackedStringArray(gr.paths.keys()))])
	return {"lines": out, "area": total / (ppm * ppm), "dirt": dirt_px / (ppm * ppm)}

static var _looks := {}
static func _look(w: Dictionary) -> String:
	if str(w.kind) != "rock":
		return ""
	var key := "%s|%s" % [str(w.a), str(w.b)]
	if _looks.has(key):
		return _looks[key]
	_looks[key] = _find_look(w)
	return _looks[key]

static func _find_look(w: Dictionary) -> String:
	for rg in Land.ridges():
		var pts: Array = rg.pts
		for i in pts.size() - 1:
			if (pts[i] as Vector2).distance_to(w.a) < 0.01 or (pts[i + 1] as Vector2).distance_to(w.b) < 0.01:
				return "(%s%s)" % [str(rg.look), ", pit rim" if rg.has("pit") else ""]
	return ""

static func _dist_line(p: Vector2, pl: Array) -> float:
	var best := INF
	for i in range(pl.size() - 1):
		best = minf(best, p.distance_to(Sim.seg_closest(p, pl[i], pl[i + 1])))
	return best
