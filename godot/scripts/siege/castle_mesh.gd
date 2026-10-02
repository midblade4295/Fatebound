extends RefCounted
# Fatebound castle geometry (Round 10 K3): tall sandstone walls with crenellations, round towers,
# gatehouse lintels, terraces with brick faces + parapets, walled grand stairs, paved floors.
# Built once per team from the sim walls + siege_castle.gd, merged into one mesh per material
# (bricks, paving) so a castle is a couple of draw calls. UVs are world-scaled: one 2 m texture
# tile covers 2 m of wall whatever a wall's length.
const Castle = preload("res://scripts/siege/siege_castle.gd")

const MERLON_W := 0.75
const MERLON_H := 0.9
const MERLON_STEP := 1.5
const TILE := 2.0                  # metres per texture tile
const FLOOR_TILE := 3.2            # the herringbone path texture's period (as on the map paths)

var bricks := SurfaceTool.new()      # step risers / sides (darker stone)
var paving := SurfaceTool.new()      # floors (herringbone)
var treads := SurfaceTool.new()      # step tops (light stone)

func _init() -> void:
	bricks.begin(Mesh.PRIMITIVE_TRIANGLES)
	paving.begin(Mesh.PRIMITIVE_TRIANGLES)
	treads.begin(Mesh.PRIMITIVE_TRIANGLES)

# ---------- primitives ----------
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uva: Vector2, uvb: Vector2, uvc: Vector2, uvd: Vector2) -> void:
	# a-b-c-d counter-clockwise seen from the front (normal = (b-a) x (d-a)). Godot's front faces
	# are CLOCKWISE, so the triangles are emitted reversed (a,c,b / a,d,c): emitting them in a-b-c
	# order built every face inside-out (floors vanished from above).
	var n := (b - a).cross(d - a).normalized()
	for v in [[a, uva], [c, uvc], [b, uvb], [a, uva], [d, uvd], [c, uvc]]:
		st.set_normal(n)
		st.set_uv(v[1])
		st.add_vertex(v[0])

func box(st: SurfaceTool, p0: Vector2, p1: Vector2, y0: float, y1: float, thick: float, top: SurfaceTool = null) -> void:
	# A wall-like box along p0->p1 (world xz), from height y0 to y1, `thick` across. World-scaled
	# UVs: u along the length (or across on the ends), v up. `top` (if given) gets the lid.
	var d := p1 - p0
	var L := d.length()
	if L < 0.01:
		return
	var dir := d / L
	var nrm := Vector2(-dir.y, dir.x) * (thick * 0.5)
	var c := [p0 + nrm, p1 + nrm, p1 - nrm, p0 - nrm]   # left-front, left-back ... around
	var h := y1 - y0
	var sides := [[c[0], c[1], L], [c[1], c[2], thick], [c[2], c[3], L], [c[3], c[0], thick]]
	var u0 := 0.0
	for sd in sides:
		var a2: Vector2 = sd[0]
		var b2: Vector2 = sd[1]
		var w: float = sd[2]
		# The outward face: from a2 to b2 seen from outside is clockwise in xz for this corner
		# order, so build it as (b, a) bottom -> top to face outward.
		_quad(st, Vector3(b2.x, y0, b2.y), Vector3(a2.x, y0, a2.y), Vector3(a2.x, y1, a2.y), Vector3(b2.x, y1, b2.y),
			Vector2((u0 + w) / TILE, -y0 / TILE), Vector2(u0 / TILE, -y0 / TILE), Vector2(u0 / TILE, -y1 / TILE), Vector2((u0 + w) / TILE, -y1 / TILE))
		u0 += w
	var lid: SurfaceTool = top if top != null else st
	# The lid must face up whatever the corner order / team mirror: pick the order whose normal
	# points +y (a fixed order turned the step treads face-down after the winding fix).
	var l := [c[0], c[3], c[2], c[1]]
	var ln := (Vector3(l[1].x, 0, l[1].y) - Vector3(l[0].x, 0, l[0].y)).cross(Vector3(l[3].x, 0, l[3].y) - Vector3(l[0].x, 0, l[0].y))
	if ln.y < 0.0:
		l = [c[0], c[1], c[2], c[3]]
	_quad(lid, Vector3(l[0].x, y1, l[0].y), Vector3(l[1].x, y1, l[1].y), Vector3(l[2].x, y1, l[2].y), Vector3(l[3].x, y1, l[3].y),
		Vector2(l[0].x, l[0].y) / TILE, Vector2(l[1].x, l[1].y) / TILE, Vector2(l[2].x, l[2].y) / TILE, Vector2(l[3].x, l[3].y) / TILE)

func floor_rect(x0: float, x1: float, z0: float, z1: float, y: float, to_world: Callable) -> void:
	# A paved floor (castle-local rect -> world via to_world), world-scaled UVs.
	var a: Vector2 = to_world.call(Vector2(x0, z0))
	var b: Vector2 = to_world.call(Vector2(x1, z0))
	var c: Vector2 = to_world.call(Vector2(x1, z1))
	var d: Vector2 = to_world.call(Vector2(x0, z1))
	var pts := [a, b, c, d]
	# Make it face up whatever the mirror did to the winding.
	var n := (Vector3(b.x, 0, b.y) - Vector3(a.x, 0, a.y)).cross(Vector3(d.x, 0, d.y) - Vector3(a.x, 0, a.y))
	if n.y < 0.0:
		pts = [a, d, c, b]
	_quad(paving, Vector3(pts[0].x, y, pts[0].y), Vector3(pts[1].x, y, pts[1].y), Vector3(pts[2].x, y, pts[2].y), Vector3(pts[3].x, y, pts[3].y),
		pts[0] / FLOOR_TILE, pts[1] / FLOOR_TILE, pts[2] / FLOOR_TILE, pts[3] / FLOOR_TILE)

func tread_band(x0: float, x1: float, z0: float, z1: float, y: float, col: Color, to_world: Callable) -> void:
	# One coloured band of a step's tread (vertex colours), facing up whatever the team mirror.
	var a: Vector2 = to_world.call(Vector2(x0, z0))
	var b2: Vector2 = to_world.call(Vector2(x1, z0))
	var c: Vector2 = to_world.call(Vector2(x1, z1))
	var d: Vector2 = to_world.call(Vector2(x0, z1))
	var pts := [a, b2, c, d]
	var n := (Vector3(b2.x, 0, b2.y) - Vector3(a.x, 0, a.y)).cross(Vector3(d.x, 0, d.y) - Vector3(a.x, 0, a.y))
	if n.y < 0.0:
		pts = [a, d, c, b2]
	for v in [pts[0], pts[2], pts[1], pts[0], pts[3], pts[2]]:
		treads.set_color(col)
		treads.set_normal(Vector3.UP)
		treads.add_vertex(Vector3(v.x, y, v.y))

func crenellations(p0: Vector2, p1: Vector2, y: float, thick: float) -> void:
	var L := p0.distance_to(p1)
	var n := int(floor(L / MERLON_STEP))
	if n < 1:
		return
	var dir := (p1 - p0) / L
	var start := (L - (n - 1) * MERLON_STEP) * 0.5
	for i in n:
		var m := p0 + dir * (start + i * MERLON_STEP)
		box(bricks, m - dir * MERLON_W * 0.5, m + dir * MERLON_W * 0.5, y, y + MERLON_H, thick)

func tower(p: Vector2, y0: float, h: float, r: float) -> void:
	var seg := 16
	var circ := TAU * r
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var q0 := p + Vector2(cos(a0), sin(a0)) * r
		var q1 := p + Vector2(cos(a1), sin(a1)) * r
		var u0 := circ * i / seg / TILE
		var u1 := circ * (i + 1) / seg / TILE
		_quad(bricks, Vector3(q1.x, y0, q1.y), Vector3(q0.x, y0, q0.y), Vector3(q0.x, y0 + h, q0.y), Vector3(q1.x, y0 + h, q1.y),
			Vector2(u1, -y0 / TILE), Vector2(u0, -y0 / TILE), Vector2(u0, -(y0 + h) / TILE), Vector2(u1, -(y0 + h) / TILE))
		# Paved top (fan from the centre), clockwise seen from above.
		var cp := Vector3(p.x, y0 + h, p.y)
		for v in [[cp, p / TILE], [Vector3(q1.x, y0 + h, q1.y), q1 / TILE], [Vector3(q0.x, y0 + h, q0.y), q0 / TILE]]:
			paving.set_normal(Vector3.UP)
			paving.set_uv(v[1])
			paving.add_vertex(v[0])
	# A crenellated ring.
	for i in 10:
		var a := TAU * (i + 0.5) / 10.0
		var m := p + Vector2(cos(a), sin(a)) * (r - 0.25)
		var t := Vector2(-sin(a), cos(a)) * 0.45
		box(bricks, m - t, m + t, y0 + h, y0 + h + MERLON_H, 0.5)

func commit(st: SurfaceTool) -> ArrayMesh:
	return st.commit()

# ---------- the castle ----------
static func build(sim, team: int) -> Dictionary:
	# Since the KayKit rebuild (Kevin: "utilize the KayKit assets for the walls") only the parts
	# the kit doesn't have are generated: herringbone floors and the stone steps.
	var b = new()
	var to_world := func(q: Vector2) -> Vector2: return sim._c(team, q)
	var hx: float = Castle.HX
	b.floor_rect(-hx, hx, Castle.FRONT_Z + 0.4, Castle.L1_Z, 0.03, to_world)
	# Terrace floors with OPENINGS where their stairs climb (a full-width floor covered the steps
	# and hid anyone climbing: Kevin's screenshot, 0.17.1).
	for lv in [[Castle.L1_Z, Castle.L2_Z, Castle.L1_H], [Castle.L2_Z, Castle.BACK + 1.0, Castle.L2_H]]:
		var tz: float = lv[0]
		var z_end: float = lv[1]
		var h: float = lv[2]
		var gaps := []
		var stair_end := tz
		for st in Castle.STAIRS:
			if absf(float(st.z0) - tz) < 0.01:
				gaps.append([float(st.x0), float(st.x1)])
				stair_end = maxf(stair_end, float(st.z1))
		gaps.sort_custom(func(a, c): return a[0] < c[0])
		b.floor_rect(-hx, hx, stair_end, z_end, h + 0.03, to_world)
		var x := -hx
		for g in gaps:
			if g[0] - x > 0.05:
				b.floor_rect(x, g[0], tz, stair_end, h + 0.03, to_world)
			x = g[1]
		if hx - x > 0.05:
			b.floor_rect(x, hx, tz, stair_end, h + 0.03, to_world)
	for st in Castle.STAIRS:
		var x0: float = st.x0
		var x1: float = st.x1
		var z0: float = st.z0
		var z1: float = st.z1
		var h0: float = st.h0
		var h1: float = st.h1
		var steps := int(Castle.STAIR_STEPS)
		for i in steps:
			# Each step overlaps the one below by 3 cm (bodies only; the tread bands tile exactly): edge-to-edge blocks left hairline seams
			# that showed the grass underneath.
			var za := z0 + (z1 - z0) * i / steps - (0.03 if i > 0 else 0.0)
			var zb := z0 + (z1 - z0) * (i + 1) / steps
			# A step's top is the higher of its two ends (flights may descend along +z: the rampart's).
			var hy := maxf(h0 + (h1 - h0) * i / steps, h0 + (h1 - h0) * (i + 1) / steps)
			b.box(b.bricks, to_world.call(Vector2((x0 + x1) * 0.5, za)), to_world.call(Vector2((x0 + x1) * 0.5, zb)), 0.0, hy, x1 - x0)
			# From the (nearly overhead) game camera the risers are invisible: stairs read by
			# their stripes. Tread = bright nosing at the front edge, mid stone, dark band at the
			# back where the next riser shades it; lower steps a little darker (Kevin: "the stairs
			# still don't look like stairs", 0.18.1).
			var k := 0.8 + 0.2 * float(i) / steps
			var zf: float = z0 + (z1 - z0) * i / steps
			var dz := zb - zf
			var y := hy + 0.004
			if h1 >= h0:
				b.tread_band(x0, x1, zf, zf + dz * 0.12, y, Color(0.92, 0.88, 0.8), to_world)
				b.tread_band(x0, x1, zf + dz * 0.12, zf + dz * 0.62, y, Color(0.64, 0.6, 0.53) * k, to_world)
				b.tread_band(x0, x1, zf + dz * 0.62, zb, y, Color(0.31, 0.28, 0.24) * k, to_world)
			else:
				# Descending: the nosing is the step's far (+z, downhill) edge; the shadow by the riser above.
				var k2 := 0.8 + 0.2 * float(steps - 1 - i) / steps
				b.tread_band(x0, x1, zf, zf + dz * 0.38, y, Color(0.31, 0.28, 0.24) * k2, to_world)
				b.tread_band(x0, x1, zf + dz * 0.38, zf + dz * 0.88, y, Color(0.64, 0.6, 0.53) * k2, to_world)
				b.tread_band(x0, x1, zf + dz * 0.88, zb, y, Color(0.92, 0.88, 0.8), to_world)
	# The rampart's walkway (Round 15), from just inside the front wall to its edge.
	b.floor_rect(-Castle.WALK_X, Castle.WALK_X, Castle.FRONT_Z + 0.9, Castle.WALK_Z1, Castle.WALK_H + 0.03, to_world)
	# The dungeon wing (Round 13): its sunken floor and the stairs down, which run along x.
	b.floor_rect(Castle.ANNEX_X0, -hx, Castle.ANNEX_Z0, Castle.ANNEX_Z1, Castle.DUNGEON_H + 0.03, to_world)
	var ds: Dictionary = Castle.DSTAIR
	var dsteps := int(ds.steps)
	var dz0: float = ds.z0
	var dz1: float = ds.z1
	var dx := (float(ds.x1) - float(ds.x0)) / dsteps
	for i in dsteps:
		var xa: float = float(ds.x0) + dx * i - (0.03 if i > 0 else 0.0)
		var xb: float = float(ds.x0) + dx * (i + 1)
		var hy: float = float(ds.h0) + (float(ds.h1) - float(ds.h0)) * (i + 1) / dsteps
		var zc := (dz0 + dz1) * 0.5
		b.box(b.bricks, to_world.call(Vector2(xa, zc)), to_world.call(Vector2(xb, zc)), Castle.DUNGEON_H, hy, dz1 - dz0)
		var k := 0.8 + 0.2 * float(i) / dsteps
		var xf: float = float(ds.x0) + dx * i
		var y := hy + 0.004
		b.tread_band(xf, xf + dx * 0.12, dz0, dz1, y, Color(0.92, 0.88, 0.8), to_world)
		b.tread_band(xf + dx * 0.12, xf + dx * 0.62, dz0, dz1, y, Color(0.64, 0.6, 0.53) * k, to_world)
		b.tread_band(xf + dx * 0.62, xf + dx, dz0, dz1, y, Color(0.31, 0.28, 0.24) * k, to_world)
	return {"steps":b.bricks.commit(), "floor":b.paving.commit(), "treads":b.treads.commit()}
