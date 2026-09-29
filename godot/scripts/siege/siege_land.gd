extends RefCounted
# Fatebound Siege landscape (Round 7): field size, the river and its bridges, raised grassy ledges
# with rock faces and ramps, rolling slopes, outposts and the brick path routes.
# Pure static data + functions: the sim turns it into walls/nav/heights, the view into terrain.
# Everything is defined for blue's half (+z) and point-mirrored for red: (x, z) -> (-x, -z).

const HALF_W := 32.0
const HALF_L := 64.0

# ---------------- river + bridges ----------------
const RIVER_AMP := 1.5
const RIVER_K := 0.16
const RIVER_HW := 3.0            # half-width of the water
const RIVER_WALL_R := 0.5
const BRIDGE_X := [-20.0, 0.0, 20.0]
const BRIDGE_HALF := 2.1         # rails at bx +/- this; the deck model is 4.9 m wide
const BRIDGE_HALF_LEN := 5.2     # the deck model is 10.4 m long (Blender bridge.glb)
const BRIDGE_ARCH := 0.55
const RAIL_R := 0.25
const WATER_Y := -0.45
const BED_Y := -0.95

static func river_c(x: float) -> float:
	# Odd in x, so the river is its own point mirror: c(-x) = -c(x).
	return RIVER_AMP * sin(RIVER_K * x)

static func bridge_centre(i: int) -> Vector2:
	var bx: float = BRIDGE_X[i]
	return Vector2(bx, river_c(bx))

static func bridge_deck(p: Vector2) -> float:
	# Deck height if p is on a bridge, else -INF.
	for bx in BRIDGE_X:
		if absf(p.x - bx) <= BRIDGE_HALF + 0.35:
			var t := (p.y - river_c(bx)) / BRIDGE_HALF_LEN
			if absf(t) <= 1.0:
				return BRIDGE_ARCH * (1.0 - t * t) + 0.12
	return -INF

# ---------------- ledges (raised grassy terraces with rock faces) ----------------
# Blue-half rectangles; each ramp is a gap in one edge that slopes down RAMP_L metres outward.
const LEDGE_H := 1.5
const RAMP_L := 4.0
const RAMP_HALF := 2.3
const TERRACES := [
	{"x0": -31.0, "x1": -15.0, "z0": 16.0, "z1": 32.0,
		"ramps": [{"side": "E", "at": 24.0}, {"side": "S", "at": -20.0}]},
	{"x0": 14.0, "x1": 31.0, "z0": 8.0, "z1": 22.0,
		"ramps": [{"side": "S", "at": 20.0}, {"side": "N", "at": 22.0}, {"side": "W", "at": 15.0}]},
]

static func _mirror_terraces() -> Array:
	var out := []
	for t in TERRACES:
		out.append(t)
		var rm := []
		for r in t.ramps:
			rm.append({"side": {"E": "W", "W": "E", "N": "S", "S": "N"}[r.side], "at": -float(r.at)})
		out.append({"x0": -float(t.x1), "x1": -float(t.x0), "z0": -float(t.z1), "z1": -float(t.z0), "ramps": rm})
	return out

static var _terraces: Array = []
static func terraces() -> Array:
	if _terraces.is_empty():
		_terraces = _mirror_terraces()
	return _terraces

static func _ramp_height(t: Dictionary, p: Vector2, base: float) -> float:
	# Height on one of this terrace's ramps, or -INF if p is not on one.
	for r in t.ramps:
		var along := 0.0
		var out := 0.0
		match str(r.side):
			"E": along = p.y; out = p.x - float(t.x1)
			"W": along = p.y; out = float(t.x0) - p.x
			"N": along = p.x; out = p.y - float(t.z1)
			"S": along = p.x; out = float(t.z0) - p.y
		if absf(along - float(r.at)) <= RAMP_HALF and out >= -0.01 and out <= RAMP_L:
			return lerpf(LEDGE_H, base, clampf(out / RAMP_L, 0.0, 1.0))
	return -INF

# ---------------- outposts ----------------
const OUTPOST_R := 5.0           # capture radius
const OUTPOST_TOWER_R := 1.3     # solid tower in the middle
const OUTPOSTS_BLUE_HALF := [Vector2(-23.0, 25.0), Vector2(22.5, 15.0)]

static func outpost_positions() -> Array:
	var out := []
	for p in OUTPOSTS_BLUE_HALF:
		out.append(p)
		out.append(-p)
	return out

# ---------------- brick paths (visual) ----------------
# Blue-half polylines from the gates (castle front at z=50) to the bridges, through the ledge ramps.
const PATHS_BLUE_HALF := [
	[Vector2(-5.2, 50.0), Vector2(-6.5, 44.0), Vector2(-11.0, 36.0), Vector2(-13.0, 24.0), Vector2(-20.0, 22.5),
		Vector2(-20.0, 12.0), Vector2(-20.0, 5.6)],
	[Vector2(5.2, 50.0), Vector2(6.0, 42.0), Vector2(4.0, 30.0), Vector2(0.5, 18.0), Vector2(0.0, 5.6)],
	[Vector2(6.0, 42.0), Vector2(14.0, 35.0), Vector2(22.0, 27.0), Vector2(22.0, 17.0), Vector2(20.0, 11.0), Vector2(20.0, 5.6)],
]
const PATH_HALF_W := 2.1

static func paths() -> Array:
	var out := []
	for pl in PATHS_BLUE_HALF:
		out.append(pl)
		var m := []
		for q in pl:
			m.append(-q)
		out.append(m)
	return out

static func dist_to_paths(p: Vector2) -> float:
	var best := INF
	for pl in paths():
		for i in range(pl.size() - 1):
			var a: Vector2 = pl[i]
			var b: Vector2 = pl[i + 1]
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			best = minf(best, p.distance_to(a + ab * t))
	return best

# ---------------- heights ----------------
const CASTLE_ZONE := 44.0        # |z| beyond this: castle grounds, flat

static func _smooth(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static func rolling(p: Vector2) -> float:
	# Gentle hills. sin*sin and cos*cos are even under (x,z)->(-x,-z), so both halves match.
	var h := 0.34 * sin(0.19 * p.x) * sin(0.23 * p.y) + 0.26 * cos(0.13 * p.x) * cos(0.11 * p.y)
	var fade := 1.0 - _smooth(CASTLE_ZONE - 6.0, CASTLE_ZONE, absf(p.y))
	fade *= _smooth(RIVER_HW + 1.5, RIVER_HW + 6.0, absf(p.y - river_c(p.x)))
	# (No fade near paths: that needed a distance to every path segment per sample, far too slow
	# for building the terrain; the brick paths follow the gentle slopes instead.)
	return h * fade

static func ground_height(p: Vector2) -> float:
	# The terrain surface (castle floors/platforms are drawn separately and handled by the sim).
	var deck := bridge_deck(p)
	if deck > -INF:
		return deck
	var dr := absf(p.y - river_c(p.x))
	if dr < RIVER_HW + 0.8:
		return lerpf(BED_Y, 0.0, _smooth(RIVER_HW - 0.6, RIVER_HW + 0.8, dr))
	var base := rolling(p)
	for t in terraces():
		if p.x >= t.x0 and p.x <= t.x1 and p.y >= t.z0 and p.y <= t.z1:
			return LEDGE_H
		var r := _ramp_height(t, p, base)
		if r > -INF:
			return r
	return base

# ---------------- walls (for the sim) ----------------
static func walls() -> Array:
	# {a, b, r, team:-1, kind}: "river" banks (units stay out of the water, arrows fly over),
	# bridge "rail"s, and "ledge" faces of the terraces (gaps where the ramps are) + ramp sides.
	var out := []
	# River banks, broken at the bridges.
	for side in [-1.0, 1.0]:
		var pts := []
		var x := -HALF_W - 1.0
		while x <= HALF_W + 1.0:
			pts.append(Vector2(x, river_c(x) + side * RIVER_HW))
			x += 1.0
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var mid := (a + b) * 0.5
			var on_bridge := false
			for bx in BRIDGE_X:
				if absf(mid.x - bx) < BRIDGE_HALF:
					on_bridge = true
			if not on_bridge:
				out.append({"a": a, "b": b, "r": RIVER_WALL_R, "team": -1, "kind": "river"})
	# Bridge rails from bank to bank (a little past each bank).
	for bx in BRIDGE_X:
		var c := river_c(bx)
		for s in [-1.0, 1.0]:
			out.append({"a": Vector2(bx + s * BRIDGE_HALF, c - BRIDGE_HALF_LEN + 0.6), "b": Vector2(bx + s * BRIDGE_HALF, c + BRIDGE_HALF_LEN - 0.6),
				"r": RAIL_R, "team": -1, "kind": "rail"})
	# Terrace faces with ramp gaps, plus the ramp side walls.
	for t in terraces():
		var edges := {"S": [Vector2(t.x0, t.z0), Vector2(t.x1, t.z0)], "N": [Vector2(t.x0, t.z1), Vector2(t.x1, t.z1)],
			"W": [Vector2(t.x0, t.z0), Vector2(t.x0, t.z1)], "E": [Vector2(t.x1, t.z0), Vector2(t.x1, t.z1)]}
		for side in edges:
			var a: Vector2 = edges[side][0]
			var b: Vector2 = edges[side][1]
			var cuts := []
			for r in t.ramps:
				if r.side == side:
					cuts.append(float(r.at))
			cuts.sort()
			var horiz: bool = side in ["N", "S"]
			var start: float = a.x if horiz else a.y
			var stop: float = b.x if horiz else b.y
			var fixed: float = a.y if horiz else a.x
			var cur := start
			for c in cuts:
				_edge(out, horiz, fixed, cur, c - RAMP_HALF)
				cur = c + RAMP_HALF
				# ramp sides: from the gap corners straight out, RAMP_L long
				var dirv := {"E": Vector2(1, 0), "W": Vector2(-1, 0), "N": Vector2(0, 1), "S": Vector2(0, -1)}[side] as Vector2
				for e in [c - RAMP_HALF, c + RAMP_HALF]:
					var p0 := Vector2(e, fixed) if horiz else Vector2(fixed, e)
					out.append({"a": p0, "b": p0 + dirv * (RAMP_L - 0.4), "r": 0.3, "team": -1, "kind": "ledge"})
			_edge(out, horiz, fixed, cur, stop)
	return out

static func _edge(out: Array, horiz: bool, fixed: float, from: float, to: float) -> void:
	if to - from < 0.2:
		return
	var a := Vector2(from, fixed) if horiz else Vector2(fixed, from)
	var b := Vector2(to, fixed) if horiz else Vector2(fixed, to)
	out.append({"a": a, "b": b, "r": 0.35, "team": -1, "kind": "ledge"})
