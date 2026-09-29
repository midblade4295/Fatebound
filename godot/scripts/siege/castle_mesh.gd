extends RefCounted
# Fatebound castle geometry (Round 10 K3): tall sandstone walls with crenellations, round towers,
# gatehouse lintels, terraces with brick faces + parapets, walled grand stairs, paved floors.
# Built once per team from the sim walls + siege_castle.gd, merged into one mesh per material
# (bricks, paving) so a castle is a couple of draw calls. UVs are world-scaled: one 2 m texture
# tile covers 2 m of wall whatever a wall's length.
const Castle = preload("res://scripts/siege/siege_castle.gd")

const WALL_H := 5.5
const WALL_T := 1.8                # a little inside the 2 m collision thickness
const MERLON_W := 0.75
const MERLON_H := 0.9
const MERLON_STEP := 1.5
const TOWER_R := 2.1
const GATE_TOWER_R := 1.35         # gate half-doorway 1.15 + margin: never over the doorway
const TOWER_H := 7.4
const PARAPET_H := 0.75
const PARAPET_T := 0.45
const TILE := 2.0                  # metres per texture tile
const FLOOR_TILE := 3.2            # the herringbone path texture's period (as on the map paths)

var bricks := SurfaceTool.new()
var paving := SurfaceTool.new()

func _init() -> void:
	bricks.begin(Mesh.PRIMITIVE_TRIANGLES)
	paving.begin(Mesh.PRIMITIVE_TRIANGLES)

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
	_quad(lid, Vector3(c[0].x, y1, c[0].y), Vector3(c[3].x, y1, c[3].y), Vector3(c[2].x, y1, c[2].y), Vector3(c[1].x, y1, c[1].y),
		Vector2(c[0].x, c[0].y) / TILE, Vector2(c[3].x, c[3].y) / TILE, Vector2(c[2].x, c[2].y) / TILE, Vector2(c[1].x, c[1].y) / TILE)

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
	b.floor_rect(-hx, hx, Castle.L1_Z, Castle.L2_Z, Castle.L1_H + 0.03, to_world)
	b.floor_rect(-hx, hx, Castle.L2_Z, Castle.BACK + 1.0, Castle.L2_H + 0.03, to_world)
	for st in Castle.STAIRS:
		var x0: float = st.x0
		var x1: float = st.x1
		var z0: float = st.z0
		var z1: float = st.z1
		var h0: float = st.h0
		var h1: float = st.h1
		var steps := 9
		for i in steps:
			var za := z0 + (z1 - z0) * i / steps
			var zb := z0 + (z1 - z0) * (i + 1) / steps
			var hy := h0 + (h1 - h0) * (i + 1) / steps
			b.box(b.bricks, to_world.call(Vector2((x0 + x1) * 0.5, za)), to_world.call(Vector2((x0 + x1) * 0.5, zb)), 0.0, hy, x1 - x0)
	return {"steps":b.bricks.commit(), "floor":b.paving.commit()}
