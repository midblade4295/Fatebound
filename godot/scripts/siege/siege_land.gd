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
const CLIFF_W := 1.2             # rock band sloping down outside each ledge edge (visible from the camera)
const WALL_OUT := 0.6            # ledge walls sit mid-band: tops stay on the flat, feet at the base
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
# Round 10: the castle front moved from z=50 to z=38 and the gates to x=+-7.
const PATHS_BLUE_HALF := [
	[Vector2(-7.0, 38.0), Vector2(-8.5, 33.0), Vector2(-12.0, 28.0), Vector2(-13.0, 24.0), Vector2(-20.0, 22.5),
		Vector2(-20.0, 12.0), Vector2(-20.0, 5.6)],
	[Vector2(7.0, 38.0), Vector2(5.5, 33.0), Vector2(4.0, 28.0), Vector2(0.5, 18.0), Vector2(0.0, 5.6)],
	[Vector2(5.5, 33.0), Vector2(14.0, 31.0), Vector2(22.0, 27.0), Vector2(22.0, 17.0), Vector2(20.0, 11.0), Vector2(20.0, 5.6)],
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
const CASTLE_ZONE := 36.0        # |z| beyond this: castle grounds, flat (front wall at 38 since Round 10)

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

static func ground_height(p: Vector2, with_decks := true) -> float:
	# Where units stand (castle floors/platforms are drawn separately and handled by the sim).
	# with_decks=false gives the visual terrain: under a bridge that is the river, so the wooden
	# deck model shows instead of grass drawn at deck height over it.
	if with_decks:
		var deck := bridge_deck(p)
		if deck > -INF:
			return deck
	var dr := absf(p.y - river_c(p.x))
	if dr < RIVER_HW + 0.8:
		return lerpf(BED_Y, 0.0, _smooth(RIVER_HW - 0.6, RIVER_HW + 0.8, dr))
	var base := rolling(p)
	var best := base
	for t in terraces():
		if p.x >= t.x0 and p.x <= t.x1 and p.y >= t.z0 and p.y <= t.z1:
			return LEDGE_H
		var r := _ramp_height(t, p, base)
		if r > -INF:
			return r
		# Cliff band just outside the edge: steep rock from LEDGE_H down to the ground.
		var dx := maxf(maxf(float(t.x0) - p.x, p.x - float(t.x1)), 0.0)
		var dz := maxf(maxf(float(t.z0) - p.y, p.y - float(t.z1)), 0.0)
		var d := sqrt(dx * dx + dz * dz)
		if d < CLIFF_W:
			best = maxf(best, lerpf(LEDGE_H, base, _smooth(0.0, 1.0, d / CLIFF_W)))
	return best

static func ledge_rim(p: Vector2) -> Vector2:
	# (rim, shadow) for the terrain mask: rim = rocky lip on top + the cliff band; shadow = a dark
	# band on the ground at the cliff foot. Ramps stay clean. Point-symmetric like everything else.
	var rim := 0.0
	var shadow := 0.0
	for t in terraces():
		if _ramp_height(t, p, 0.0) > -INF:
			continue
		var dx := maxf(float(t.x0) - p.x, p.x - float(t.x1))
		var dz := maxf(float(t.z0) - p.y, p.y - float(t.z1))
		var d: float                                  # signed distance to the rectangle edge
		if dx > 0.0 and dz > 0.0:
			d = sqrt(dx * dx + dz * dz)
		else:
			d = maxf(dx, dz)
		# on the ramps' sides (d measured from the gap corners) keep a rim too: handled by d
		rim = maxf(rim, 1.0 - _smooth(-0.7, -0.35, -d) if d < 0.0 else (1.0 - _smooth(CLIFF_W, CLIFF_W + 0.25, d)))
		if d > CLIFF_W - 0.2:
			shadow = maxf(shadow, 1.0 - _smooth(CLIFF_W, CLIFF_W + 1.4, d))
	return Vector2(clampf(rim, 0.0, 1.0), clampf(shadow, 0.0, 1.0))

# ---------------- baked terrain (visual) ----------------
const BAKE_MARGIN := 7.0          # terrain extends this far past the field edge
const BAKE_STEP := 1.0            # metres between height samples (0.5 m cost ~45k more triangles
                                  # for no visible difference at the game camera; 0.14.3)
const MASK_PPM := 4.0             # path-mask pixels per metre
const HEIGHT_RES := "res://assets/terrain/height.res"
const MASK_RES := "res://assets/terrain/pathmask.res"

# The castles' sunken dungeon wings (siege_castle.gd, Round 13): the terrain dips to the dungeon
# floor there, or the grass would cover the pit. (Blue space; red is point-mirrored.)
const _CastleL = preload("res://scripts/siege/siege_castle.gd")

static func in_dungeon_pit(p: Vector2) -> bool:
	var q := (p if p.y >= 0.0 else -p) - Vector2(0.0, HALF_L - _CastleL.BACK)
	return q.x >= _CastleL.ANNEX_X0 and q.x <= -_CastleL.HX and q.y >= _CastleL.ANNEX_Z0 and q.y <= _CastleL.ANNEX_Z1

static func terrain_height(p: Vector2) -> float:
	if in_dungeon_pit(p):
		return _CastleL.DUNGEON_H
	# ground_height inside the field; beyond it a rim of low hills (not playable, just scenery).
	var out := maxf(absf(p.x) - HALF_W, absf(p.y) - HALF_L)
	var inside := Vector2(clampf(p.x, -HALF_W, HALF_W), clampf(p.y, -HALF_L, HALF_L))
	var h := ground_height(inside, false)
	if out <= 0.0:
		return h
	var rim := 1.9 * _smooth(0.0, 5.0, out) + 0.5 * sin(0.37 * p.x + 0.9) * sin(0.29 * p.y + 0.4) * _smooth(1.0, 6.0, out)
	return maxf(h, 0.0) + rim

# Painted sweeping bands (0.14.4, like the Fat Princess references): concentric light/dark arcs
# around a few centres, blended where neighbouring ring sets meet, gently warped. Baked into the
# terrain mask's alpha, so the shader pays nothing extra for them.
const BAND_W := 5.0                # a few cells wide, like the references
# Few centres, mostly at or beyond the field edges, so the play area sees long sweeping arcs
# rather than bullseyes (the first version's 16 centres read as targets).
const BAND_CENTRES := [Vector2(-44.0, 40.0), Vector2(46.0, 8.0), Vector2(-10.0, 78.0), Vector2(42.0, 54.0)]

static func grass_band(p: Vector2) -> float:
	var q := p + Vector2(1.3 * sin(0.13 * p.y + 0.4), 1.3 * cos(0.11 * p.x + 1.1))
	var d1 := INF
	var d2 := INF
	for c in BAND_CENTRES:
		for cc in [c, -c]:
			var d := q.distance_to(cc)
			if d < d1:
				d2 = d1
				d1 = d
			elif d < d2:
				d2 = d
	var ring := func(d: float) -> float:
		return _smooth(0.32, 0.68, 0.5 + 0.5 * sin(TAU * d / BAND_W))
	# Blend the two nearest ring sets across their meeting line (4 m wide).
	var t := _smooth(-2.0, 2.0, d2 - d1)
	return lerpf(0.5 * (ring.call(d1) + ring.call(d2)), ring.call(d1), t)

# ---------------- the world beyond the playfield (0.19.4, Kevin: "land on the edges of the map") ----------------
# View-only scenery out to OUTER_REACH past the baked terrain: it starts at the terrain's own edge
# height, rolls into meadows and hills, rises to a ring of mountains, and the river carries on out
# through a valley of its own (river_c is defined for any x). Nothing here touches the sim.
const OUTER_REACH := 260.0

static func outer_height(p: Vector2) -> float:
	var r := bake_rect()
	var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	var d := p.distance_to(q)
	var hills := 1.2 * sin(p.x * 0.07 + 1.3) * sin(p.y * 0.055 + 0.4) + 0.9 * sin(p.x * 0.031 - p.y * 0.043 + 2.0)
	# Hills close in within ~30 m and mountains rise from 40 m (0.19.5, Kevin: "mountains or something"
	# at the edges): from the play camera the field reads as a valley between rocky slopes.
	var rise := clampf((d - 5.0) / 28.0, 0.0, 1.0)
	var h := hills * (0.6 + 4.0 * rise) + rise * rise * 7.0
	var mtn := smoothstep(40.0, 130.0, d)
	h += mtn * (28.0 + 14.0 * sin(p.x * 0.021 + 0.7) * sin(p.y * 0.017 + 1.9) + 8.0 * sin(p.x * 0.05 + p.y * 0.037))
	h = lerpf(terrain_height(q), h, smoothstep(0.0, 14.0, d))      # meets the playfield's edge exactly
	if d > 0.0:
		var off := absf(p.y - river_c(p.x))
		h = lerpf(WATER_Y - 0.7, h, smoothstep(RIVER_HW - 0.5, RIVER_HW + 6.0 + d * 0.05, off))
	return h

static func bake_rect() -> Rect2:
	return Rect2(-HALF_W - BAKE_MARGIN, -HALF_L - BAKE_MARGIN, 2.0 * (HALF_W + BAKE_MARGIN), 2.0 * (HALF_L + BAKE_MARGIN))

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
		var o := WALL_OUT
		var x0: float = float(t.x0) - o
		var x1: float = float(t.x1) + o
		var z0: float = float(t.z0) - o
		var z1: float = float(t.z1) + o
		var edges := {"S": [Vector2(x0, z0), Vector2(x1, z0)], "N": [Vector2(x0, z1), Vector2(x1, z1)],
			"W": [Vector2(x0, z0), Vector2(x0, z1)], "E": [Vector2(x1, z0), Vector2(x1, z1)]}
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
					out.append({"a": p0, "b": p0 + dirv * (RAMP_L - 0.4 - WALL_OUT), "r": 0.3, "team": -1, "kind": "ledge"})
			_edge(out, horiz, fixed, cur, stop)
	# A wall that ends just short of the field edge leaves a slot narrower than a unit between its
	# end cap and the boundary clamp; a knight dodged into one and stuck (1,057 violation ticks,
	# Round 12). Walls ending within 1.5 m of an edge run 1 m past it instead (like the castle's).
	for w in out:
		for key in ["a", "b"]:
			var q: Vector2 = w[key]
			if absf(q.x) > HALF_W - 1.5 and absf(q.x) < HALF_W + 0.5:
				q.x = signf(q.x) * (HALF_W + 1.0)
			if absf(q.y) > HALF_L - 1.5 and absf(q.y) < HALF_L + 0.5:
				q.y = signf(q.y) * (HALF_L + 1.0)
			w[key] = q
	return out

static func _edge(out: Array, horiz: bool, fixed: float, from: float, to: float) -> void:
	if to - from < 0.2:
		return
	var a := Vector2(from, fixed) if horiz else Vector2(fixed, from)
	var b := Vector2(to, fixed) if horiz else Vector2(fixed, to)
	out.append({"a": a, "b": b, "r": 0.35, "team": -1, "kind": "ledge"})
