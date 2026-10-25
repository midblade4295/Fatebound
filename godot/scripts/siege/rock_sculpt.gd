extends RefCounted
# The jungle's rock formations (0.31.216, Kevin: "need new models for grass and rock formations"; he chose them sculpted
# in code): Honor of Kings' chunky blue-grey stone along each of the Rift's rock walls (siege_land.gd ridges(): the
# sim's "rock" walls, the pits' rims too) -- boulders shouldered together along the wall's line, each a few big flat
# facets with a mossy top, a slab or two at their feet. Built here once per run (seeded: the same every match), one
# ArrayMesh per wall, drawn with rock_formation.gdshader (the painted rock texture from ElevenLabs, triplanar; moss
# where a face turns up). The formations stand a little wider than the wall the sim keeps you out of, as a cliff's
# foot does.
#   COLOR: r = the boulder's tint (0..1), g = the height up the boulder (0 at its foot .. 1 at its top), b = 1 on the
#   slabs at the feet (they take more moss)
const Land = preload("res://scripts/siege/siege_land.gd")

const SEED := 216
const SINK := 0.35                 # how far a boulder's foot sits in the ground
const H_MIN := 2.3                 # a wall boulder's height (a hero is ~1.8)
const H_MAX := 3.3
const RIM_H_MIN := 1.2             # the pits' rims are lower: you see the monster over them
const RIM_H_MAX := 1.8

static var _meshes: Array = []     # [{mesh, aabb}] -- built once per run

static func meshes() -> Array:
	if _meshes.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = SEED
		for rg in Land.ridges():
			if str(rg.look) != "rock":
				continue
			var m := _wall(rg.pts, float(rg.r), rg.has("pit"), rng)
			if m != null:
				_meshes.append(m)
	return _meshes

static func _wall(pts: Array, r: float, rim: bool, rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# walk the wall's line: a boulder every so often, overlapping its neighbours
	var total := 0.0
	for i in pts.size() - 1:
		total += (pts[i] as Vector2).distance_to(pts[i + 1])
	var step := maxf(1.2, r * (1.25 if rim else 1.55))
	var n := maxi(2, int(ceil(total / step)) + 1)
	for k in n:
		var s := total * float(k) / float(n - 1)
		var at := _along(pts, s)
		var q: Vector2 = at[0]
		var d: Vector2 = at[1]
		var w := (2.0 * r + (0.5 if rim else 0.8)) * rng.randf_range(0.85, 1.1)
		var l := w * rng.randf_range(1.0, 1.35)
		var h := rng.randf_range(RIM_H_MIN, RIM_H_MAX) if rim else rng.randf_range(H_MIN, H_MAX)
		if not rim and (k == 0 or k == n - 1):
			h *= 0.78                                   # the ends step down
		var yaw := atan2(d.x, d.y) + rng.randf_range(-0.35, 0.35)
		var off := Vector2(-d.y, d.x) * rng.randf_range(-0.25, 0.25) * r
		_boulder(st, q + off, l, w, h, yaw, rng.randf(), rng, 0.0)
		# a slab or two at its feet, out to the sides
		for side in [-1.0, 1.0]:
			if rng.randf() < (0.35 if rim else 0.55):
				var sq: Vector2 = q + Vector2(-d.y, d.x) * side * (w * 0.5 + rng.randf_range(0.1, 0.6)) + d * rng.randf_range(-0.8, 0.8)
				var sw := rng.randf_range(0.8, 1.5)
				_boulder(st, sq, sw * rng.randf_range(1.0, 1.4), sw, rng.randf_range(0.35, 0.7), rng.randf() * TAU, rng.randf(), rng, 1.0)
	st.generate_normals()                              # (flat: every face has its own vertices -- the chunky facets)
	return st.commit()

static func _along(pts: Array, s: float) -> Array:
	# the point s metres along the polyline, and its direction there
	var acc := 0.0
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var L := a.distance_to(b)
		if acc + L >= s or i == pts.size() - 2:
			var t := clampf((s - acc) / maxf(L, 0.001), 0.0, 1.0)
			return [a.lerp(b, t), (b - a) / maxf(L, 0.001)]
		acc += L
	return [pts[0], Vector2(0, 1)]

static var _ico: Array = []          # [verts, faces] of a once-subdivided icosahedron (42 vertices, 80 faces)

static func _icosphere() -> Array:
	if not _ico.is_empty():
		return _ico
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v: Array = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
		Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in v.size():
		v[i] = (v[i] as Vector3).normalized()
	var f: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6],
		[7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var mids := {}
	var mid := func(a: int, b: int) -> int:
		var key := Vector2i(mini(a, b), maxi(a, b))
		if mids.has(key):
			return mids[key]
		v.append(((v[a] as Vector3) + (v[b] as Vector3)).normalized())
		mids[key] = v.size() - 1
		return v.size() - 1
	var f2 := []
	for tri in f:
		var a: int = mid.call(tri[0], tri[1])
		var b: int = mid.call(tri[1], tri[2])
		var c: int = mid.call(tri[2], tri[0])
		f2.append_array([[tri[0], a, c], [tri[1], b, a], [tri[2], c, b], [a, b, c]])
	_ico = [v, f2]
	return _ico

static func _boulder(st: SurfaceTool, at: Vector2, l: float, w: float, h: float, yaw: float, tint: float,
		rng: RandomNumberGenerator, slab: float) -> void:
	# A rounded block cut into big facets: the icosphere stretched to l x h x w, each vertex pushed in or out a little,
	# its top pressed flat into a plateau (the moss sits there) and its foot sunk into the ground.
	var ico := _icosphere()
	var verts: Array = ico[0]
	var faces: Array = ico[1]
	var base_y := Land.terrain_height(at) - SINK
	var basis := Basis(Vector3.UP, yaw)
	var top := h * rng.randf_range(0.72, 0.85)         # where the top starts to flatten
	var tilt := Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12))
	var jit := []
	for i in verts.size():
		jit.append(rng.randf_range(-0.13, 0.13))
	var pts := []
	for i in verts.size():
		var u: Vector3 = verts[i]
		var p := Vector3(u.x * l * 0.5, (u.y * 0.5 + 0.5) * h, u.z * w * 0.5) * (1.0 + float(jit[i]))
		if p.y > top:
			p.y = top + (p.y - top) * 0.45 + tilt.x * p.x + tilt.y * p.z
		if p.y < SINK * 0.5:
			p.y = SINK * 0.5 + (p.y - SINK * 0.5) * 0.3     # a flat-ish foot
		p.x *= 1.0 + 0.18 * (1.0 - p.y / maxf(h, 0.01)) - 0.1     # wider at the foot, narrower at the top
		p.z *= 1.0 + 0.18 * (1.0 - p.y / maxf(h, 0.01)) - 0.1
		pts.append(basis * p + Vector3(at.x, base_y, at.y))
	var hi := top + 0.25 * (h - top)
	for tri in faces:
		for k in [0, 2, 1]:                            # (the icosphere winds the other way round for Godot's front faces)
			var p: Vector3 = pts[tri[k]]
			st.set_color(Color(tint, clampf((p.y - base_y) / maxf(hi, 0.01), 0.0, 1.0), slab))
			st.add_vertex(p)
