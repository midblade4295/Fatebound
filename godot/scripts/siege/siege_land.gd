extends RefCounted
# Fatebound Siege landscape (Round 7; reshaped in 0.26.0 after Kevin's Fat Princess reference):
# a bigger field with a natural edge (rock walls on the west and behind the castles, a sheer drop
# with a waterfall on the east -- the "cliff side"), the river widening into a lake round an island
# tower reached by one narrow bridge lane from each bank, two normal bridges, rounded plateaus with
# rock faces and ramps, rolling slopes, the towers (outposts) and the brick path routes.
# Pure static data + functions: the sim turns it into walls/nav/heights, the view into terrain.
# Everything is defined for blue's half (+z) and point-mirrored for red: (x, z) -> (-x, -z).
# (Only the scenery OUTSIDE the field -- which side drops away -- is not mirrored; it can't be walked.)

const HALF_W := 44.0             # 32 until 0.26.0
const HALF_L := 70.0             # 64 until 0.26.0

# ---------------- river, lake, island, bridges ----------------
const RIVER_AMP := 1.5
const RIVER_K := 0.16
const RIVER_HW := 3.0            # half-width of the water away from the lake
const LAKE_EXTRA := 9.5          # extra half-width in the middle (Gaussian in x): the lake
const LAKE_SIGMA := 12.0
const ISLAND_RX := 9.0           # the island: an ellipse in the middle of the lake
const ISLAND_RZ := 5.5
const RIVER_WALL_R := 0.5
const BRIDGE_ARCH := 0.55
const RAIL_R := 0.25
const WATER_Y := -0.45
const BED_Y := -0.95
const SIDE_BRIDGE_X := 24.0
const LANE_HALF := 1.25          # the island lane: rails at +-this (side bridges 2.1): one lane

static func river_c(x: float) -> float:
	# Odd in x, so the river is its own point mirror: c(-x) = -c(x).
	return RIVER_AMP * sin(RIVER_K * x)

static func river_hw(x: float) -> float:
	# Even in x, so the banks stay point-symmetric with the lake in the middle.
	return RIVER_HW + LAKE_EXTRA * exp(-(x / LAKE_SIGMA) * (x / LAKE_SIGMA))

static func river_off(p: Vector2) -> float:
	# How far p is out of the river band (negative: in the band, island or not).
	return absf(p.y - river_c(p.x)) - river_hw(p.x)

static func island_off(p: Vector2) -> float:
	# Radial distance from the island's shore: negative on the island.
	var r := p.length()
	if r < 0.001:
		return -ISLAND_RZ
	var c := p.x / r
	var s := p.y / r
	return r - 1.0 / sqrt((c / ISLAND_RX) * (c / ISLAND_RX) + (s / ISLAND_RZ) * (s / ISLAND_RZ))

static func shore(p: Vector2) -> float:
	# Distance onto dry land: > 0 on land (field or island), < 0 in the water.
	return maxf(river_off(p), -island_off(p))

static var _bridges: Array = []
static func bridges() -> Array:
	# {c, half_w (rails), half_len (deck), sx, sz (deck model scale), lane}
	if _bridges.is_empty():
		for s in [-1.0, 1.0]:
			var x: float = s * SIDE_BRIDGE_X
			_bridges.append({"c": Vector2(x, river_c(x)), "half_w": 2.1, "half_len": 5.2, "sx": 1.0, "sz": 1.0, "lane": false})
		# The island lane: one narrow bridge from each bank, meeting the island at its tips.
		var bank := river_hw(0.0)
		var mid := (bank + ISLAND_RZ) * 0.5
		var hl := (bank - ISLAND_RZ) * 0.5 + 0.9
		for s in [1.0, -1.0]:
			_bridges.append({"c": Vector2(0.0, s * mid), "half_w": LANE_HALF, "half_len": hl, "sx": LANE_HALF / 2.1, "sz": hl / 5.2, "lane": true})
	return _bridges

static func bridge_deck(p: Vector2) -> float:
	# Deck height if p is on a bridge, else -INF.
	for b in bridges():
		var c: Vector2 = b.c
		if absf(p.x - c.x) <= float(b.half_w) + 0.35:
			var t := (p.y - c.y) / float(b.half_len)
			if absf(t) <= 1.0:
				return BRIDGE_ARCH * (1.0 - t * t) + 0.12
	return -INF

static func on_bridge(p: Vector2, margin := 0.0) -> bool:
	for b in bridges():
		var c: Vector2 = b.c
		if absf(p.x - c.x) <= float(b.half_w) + margin and absf(p.y - c.y) <= float(b.half_len) + margin:
			return true
	return false

# ---------------- the field's edge ----------------
# Blue's chain, from the river on the east round behind the castle to the river on the west; red's
# is its point mirror, and the two close the loop out past the field edge where the river leaves.
# West of the castle it hugs the dungeon wing's outer wall (x = -33, 1 m thick).
const EDGE_BLUE := [
	Vector2(45.5, 5.5), Vector2(42.0, 9.0), Vector2(40.5, 14.0), Vector2(40.0, 20.0), Vector2(41.0, 26.0),
	Vector2(39.0, 32.0), Vector2(35.5, 37.5), Vector2(33.0, 43.0), Vector2(32.0, 50.0), Vector2(32.5, 58.0),
	Vector2(31.0, 65.0), Vector2(30.5, 71.5),
	Vector2(-34.6, 71.5), Vector2(-34.6, 48.0), Vector2(-37.5, 43.0), Vector2(-41.0, 38.5), Vector2(-44.6, 33.0),
	Vector2(-44.6, 19.0), Vector2(-41.8, 11.5), Vector2(-44.6, 6.5), Vector2(-45.5, 5.0),
]
const EDGE_R := 0.6
const EDGE_SKIP := 11            # the segment from index 11 to 12 runs behind the castle (no wall needed)

static var _loop: PackedVector2Array = PackedVector2Array()
static func edge_loop() -> PackedVector2Array:
	if _loop.is_empty():
		for q in EDGE_BLUE:
			_loop.append(q)
		for q in EDGE_BLUE:
			_loop.append(-q)
	return _loop

static func inside_field(p: Vector2) -> bool:
	if absf(p.x) > HALF_W or absf(p.y) > HALF_L:
		return false
	return Geometry2D.is_point_in_polygon(p, edge_loop())

static func edge_dist(p: Vector2) -> float:
	# Signed distance to the field's edge: + outside, - inside. Far inside: a cheap constant.
	if absf(p.x) < 26.0 and absf(p.y) < 64.0:
		return -8.0
	var lp := edge_loop()
	var best := INF
	for i in lp.size():
		var a: Vector2 = lp[i]
		var b: Vector2 = lp[(i + 1) % lp.size()]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return -best if Geometry2D.is_point_in_polygon(p, lp) else best

static func drop_weight(p: Vector2) -> float:
	# Scenery only: 1 where the land beyond the edge falls away (the east side between the
	# castles -- Kevin's "cliff side"), 0 where it rises into rock walls.
	return _smooth(-4.0, 4.0, p.x) * (1.0 - _smooth(37.0, 41.0, absf(p.y)))

const DROP_DEPTH := 24.0          # the valley below the cliff side
const RISE_H := 6.5               # the rock walls elsewhere
const VALLEY_WATER_Y := WATER_Y - DROP_DEPTH
const FALL_X := 45.6              # where the river pours over the cliff

# ---------------- plateaus (raised grassy land with rock faces) ----------------
# Blue-half outlines (rounded); each ramp is a gap in one edge that slopes down RAMP_L metres
# outward. Points beyond the field edge make a plateau run into the rock walls / cliff.
const LEDGE_H := 1.5
const RAMP_L := 4.0
const CLIFF_W := 1.2             # rock band sloping down outside each plateau edge
const WALL_OUT := 0.6            # plateau walls sit mid-band: tops stay on the flat, feet at the base
const RAMP_HALF := 2.3
const PLATEAUS := [
	# The west highland: the tower nearest each castle stands up here.
	{"pts": [Vector2(-47.0, 18.5), Vector2(-37.5, 16.0), Vector2(-30.0, 15.0), Vector2(-23.5, 16.5), Vector2(-19.5, 21.5),
		Vector2(-19.5, 28.5), Vector2(-23.0, 33.5), Vector2(-30.0, 35.5), Vector2(-38.0, 35.0), Vector2(-47.0, 33.0)],
		"ramps": [{"edge": 4, "t": 0.5}, {"edge": 2, "t": 0.5}, {"edge": 6, "t": 0.5}]},
	# The east bluff on the cliff edge, with its own tower.
	{"pts": [Vector2(24.5, 9.5), Vector2(31.0, 7.5), Vector2(47.0, 8.5), Vector2(47.0, 26.5), Vector2(37.0, 27.5),
		Vector2(30.0, 26.5), Vector2(25.0, 22.0), Vector2(23.5, 15.5)],
		"ramps": [{"edge": 6, "t": 0.5}, {"edge": 4, "t": 0.5}]},
]

static func _prep_plateau(pts: Array, ramps: Array) -> Dictionary:
	var poly := PackedVector2Array(pts)
	var cen := Vector2.ZERO
	for q in pts:
		cen += q
	cen /= pts.size()
	var rp := []
	for r in ramps:
		var a: Vector2 = pts[int(r.edge)]
		var b: Vector2 = pts[(int(r.edge) + 1) % pts.size()]
		var u := (b - a).normalized()
		var n := Vector2(u.y, -u.x)
		var mid := (a + b) * 0.5
		if n.dot(cen - mid) > 0.0:
			n = -n
		rp.append({"a": a, "u": u, "n": n, "s0": a.distance_to(b) * float(r.t), "edge": int(r.edge)})
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q in pts:
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	return {"pts": pts, "poly": poly, "cen": cen, "ramps": rp, "lo": lo - Vector2(RAMP_L + 2.0, RAMP_L + 2.0), "hi": hi + Vector2(RAMP_L + 2.0, RAMP_L + 2.0)}

static var _plateaus: Array = []
static func plateaus() -> Array:
	if _plateaus.is_empty():
		for pl in PLATEAUS:
			_plateaus.append(_prep_plateau(pl.pts, pl.ramps))
			var m := []
			for q in pl.pts:
				m.append(-q)
			_plateaus.append(_prep_plateau(m, pl.ramps))
	return _plateaus

static func _poly_dist(pl: Dictionary, p: Vector2) -> float:
	# Signed distance to the plateau's outline: negative inside.
	var pts: Array = pl.pts
	var best := INF
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return -best if Geometry2D.is_point_in_polygon(p, pl.poly) else best

static func _near(pl: Dictionary, p: Vector2) -> bool:
	return p.x >= pl.lo.x and p.x <= pl.hi.x and p.y >= pl.lo.y and p.y <= pl.hi.y

static func ramp_height(pl: Dictionary, p: Vector2, base: float) -> float:
	# Height on one of this plateau's ramps, or -INF if p is not on one.
	for r in pl.ramps:
		var q: Vector2 = p - (r.a as Vector2)
		var along := q.dot(r.u)
		var out := q.dot(r.n)
		if absf(along - float(r.s0)) <= RAMP_HALF and out >= -0.01 and out <= RAMP_L:
			return lerpf(LEDGE_H, base, clampf(out / RAMP_L, 0.0, 1.0))
	return -INF

# ---------------- outposts (towers) ----------------
const OUTPOST_R := 5.0           # capture radius
const OUTPOST_TOWER_R := 1.8     # solid tower in the middle
const TOWER_FLOOR := 4.48        # its walkable top (KayKit tower_A floor at 1.40, scaled 3.2)
const OUTPOSTS_BLUE_HALF := [Vector2(-31.0, 25.0), Vector2(34.0, 17.5)]
const ISLAND_TOWER := Vector2.ZERO

static func outpost_positions() -> Array:
	var out := []
	for p in OUTPOSTS_BLUE_HALF:
		out.append(p)
		out.append(-p)
	out.append(ISLAND_TOWER)       # its own mirror
	return out

# ---------------- brick paths (visual) ----------------
# Blue-half polylines: gates (x = +-7, z = 44) to the bridges and the island lane, with spurs up
# the plateau ramps to the towers.
const PATHS_BLUE_HALF := [
	[Vector2(-7.0, 44.0), Vector2(-9.5, 39.0), Vector2(-13.5, 34.5), Vector2(-15.5, 29.0), Vector2(-15.8, 22.0),
		Vector2(-18.0, 14.5), Vector2(-22.0, 9.5), Vector2(-24.0, 6.6)],
	[Vector2(-15.6, 25.0), Vector2(-19.5, 25.0), Vector2(-25.5, 25.0)],
	[Vector2(-25.85, 11.9), Vector2(-26.75, 15.75), Vector2(-28.5, 20.5)],
	[Vector2(-9.5, 39.0), Vector2(-18.5, 40.5), Vector2(-27.6, 38.4), Vector2(-26.5, 34.5), Vector2(-28.0, 30.0)],
	[Vector2(7.0, 44.0), Vector2(5.0, 38.5), Vector2(2.0, 31.0), Vector2(0.5, 22.0), Vector2(0.0, 13.6)],
	[Vector2(-9.5, 39.0), Vector2(-4.0, 35.0), Vector2(2.0, 31.0)],
	[Vector2(5.0, 38.5), Vector2(13.0, 35.0), Vector2(19.0, 28.5), Vector2(19.5, 21.0), Vector2(20.0, 13.5),
		Vector2(21.0, 8.5), Vector2(24.0, 4.7)],
	[Vector2(20.2, 19.6), Vector2(24.25, 18.75), Vector2(29.0, 18.0)],
	[Vector2(19.0, 28.5), Vector2(26.5, 31.5), Vector2(32.9, 31.0), Vector2(33.5, 27.0), Vector2(33.8, 22.5)],
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
const _CastleZ = preload("res://scripts/siege/siege_castle.gd")
const CASTLE_ZONE := HALF_L - _CastleZ.BACK + _CastleZ.FRONT_Z - 2.0   # |z| beyond this: castle grounds, flat

static func _smooth(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static func rolling(p: Vector2) -> float:
	# Gentle hills. sin*sin and cos*cos are even under (x,z)->(-x,-z), so both halves match.
	var h := 0.34 * sin(0.19 * p.x) * sin(0.23 * p.y) + 0.26 * cos(0.13 * p.x) * cos(0.11 * p.y)
	var fade := 1.0 - _smooth(CASTLE_ZONE - 6.0, CASTLE_ZONE, absf(p.y))
	fade *= _smooth(1.5, 6.0, river_off(p))       # flat by the water (and on the island)
	return h * fade

static func ground_height(p: Vector2, with_decks := true) -> float:
	# Where units stand (castle floors/platforms are drawn separately and handled by the sim).
	# with_decks=false gives the visual terrain: under a bridge that is the river, so the wooden
	# deck model shows instead of grass drawn at deck height over it.
	if with_decks:
		var deck := bridge_deck(p)
		if deck > -INF:
			return deck
	var sh := shore(p)
	if sh < 0.8:
		return lerpf(BED_Y, 0.0, _smooth(-0.6, 0.8, sh))
	var base := rolling(p)
	var best := base
	for pl in plateaus():
		if not _near(pl, p):
			continue
		var d := _poly_dist(pl, p)
		if d <= 0.0:
			return LEDGE_H
		var r := ramp_height(pl, p, base)
		if r > -INF:
			return r
		if d < CLIFF_W:
			best = maxf(best, lerpf(LEDGE_H, base, _smooth(0.0, 1.0, d / CLIFF_W)))
	return best

static func ledge_rim(p: Vector2) -> Vector2:
	# (rim, shadow) for the terrain mask: rim = rocky lip on top + the cliff band (plateaus) and the
	# rock beyond the field's edge; shadow = a dark band on the ground at each cliff foot. Ramps stay
	# clean. The plateau part is point-symmetric; the edge part follows the scenery.
	var rim := 0.0
	var shadow := 0.0
	for pl in plateaus():
		if not _near(pl, p):
			continue
		if ramp_height(pl, p, 0.0) > -INF:
			continue
		var d := _poly_dist(pl, p)
		rim = maxf(rim, 1.0 - _smooth(-0.7, -0.35, -d) if d < 0.0 else (1.0 - _smooth(CLIFF_W, CLIFF_W + 0.25, d)))
		if d > CLIFF_W - 0.2:
			shadow = maxf(shadow, 1.0 - _smooth(CLIFF_W, CLIFF_W + 1.4, d))
	var ed := edge_dist(p)
	if ed > -3.0:
		var rise := 1.0 - drop_weight(p)
		rim = maxf(rim, _smooth(-0.3, 0.6, ed) * (0.55 + 0.45 * rise))
		shadow = maxf(shadow, (1.0 - _smooth(0.0, 2.2, -ed)) * rise * 0.9)
	return Vector2(clampf(rim, 0.0, 1.0), clampf(shadow, 0.0, 1.0))

# ---------------- baked terrain (visual) ----------------
const BAKE_MARGIN := 7.0          # terrain extends this far past the field edge
const BAKE_STEP := 1.0            # metres between height samples
const MASK_PPM := 4.0             # path-mask pixels per metre
const HEIGHT_RES := "res://assets/terrain/height.res"
const MASK_RES := "res://assets/terrain/pathmask.res"

# The castles' sunken dungeon wings (siege_castle.gd, Round 13): the terrain dips to the dungeon
# floor there, or the grass would cover the pit. (Blue space; red is point-mirrored.)
const _CastleL = preload("res://scripts/siege/siege_castle.gd")

static func in_dungeon_pit(p: Vector2, margin := 0.0) -> bool:
	var q := (p if p.y >= 0.0 else -p) - Vector2(0.0, HALF_L - _CastleL.BACK)
	return q.x >= _CastleL.ANNEX_X0 - margin and q.x <= -_CastleL.HX + margin and q.y >= _CastleL.ANNEX_Z0 - margin and q.y <= _CastleL.ANNEX_Z1 + margin

static func terrain_height(p: Vector2) -> float:
	if in_dungeon_pit(p):
		return _CastleL.DUNGEON_H
	var inside := Vector2(clampf(p.x, -HALF_W - 1.5, HALF_W + 1.5), clampf(p.y, -HALF_L, HALF_L))
	var h := ground_height(inside, false)
	var ed := edge_dist(p)
	if ed <= 0.0:
		return h
	# Beyond the edge (scenery): rock walls rising on most sides, a sheer drop on the cliff side.
	var dw := drop_weight(p)
	var rise := RISE_H * _smooth(0.0, 2.6, ed) + 1.3 * _smooth(3.0, 10.0, ed) * (0.5 + 0.5 * sin(0.41 * p.x + 0.7) * sin(0.33 * p.y + 1.3))
	var fall := -DROP_DEPTH * _smooth(0.2, 3.4, ed)
	var top := maxf(h, 0.0)
	var out := top + lerpf(rise, fall, dw)
	# The river carries on through: a gorge between the rock walls (the cliff side has the falls).
	if dw < 0.5:
		out = lerpf(BED_Y, out, _smooth(-0.4, 2.8, river_off(p)))
	return out

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
	var h := RISE_H + hills * (0.6 + 4.0 * rise) + rise * rise * 7.0
	var mtn := smoothstep(40.0, 130.0, d)
	h += mtn * (28.0 + 14.0 * sin(p.x * 0.021 + 0.7) * sin(p.y * 0.017 + 1.9) + 8.0 * sin(p.x * 0.05 + p.y * 0.037))
	# Below the cliff side (0.26.0): a wooded valley, mountains only far off.
	var dw := drop_weight(p)
	if dw > 0.0:
		var valley := -DROP_DEPTH + hills * 0.8 + smoothstep(70.0, 190.0, d) * (40.0 + 10.0 * sin(p.y * 0.019 + 0.4))
		h = lerpf(h, valley, dw)
	h = lerpf(terrain_height(q), h, smoothstep(0.0, 14.0, d))      # meets the baked terrain's edge exactly
	if d > 0.0:
		var off := absf(p.y - river_c(p.x))
		var wl := lerpf(WATER_Y, VALLEY_WATER_Y, dw)
		h = lerpf(wl - 0.7, h, smoothstep(RIVER_HW - 0.5, RIVER_HW + 6.0 + d * 0.05, off))
	return h

static func bake_rect() -> Rect2:
	return Rect2(-HALF_W - BAKE_MARGIN, -HALF_L - BAKE_MARGIN, 2.0 * (HALF_W + BAKE_MARGIN), 2.0 * (HALF_L + BAKE_MARGIN))

# ---------------- walls (for the sim) ----------------
static func walls() -> Array:
	# {a, b, r, team:-1, kind}: "river" banks and island shore (units stay out of the water, arrows
	# fly over), bridge "rail"s, "ledge" faces of the plateaus (gaps where the ramps are) + ramp sides,
	# and the field's "edge".
	var out := []
	# River banks: none since Round 33 (Kevin: "let players walk through it, but much slower") -- the river and
	# the lake are waded (Sim.move_mult); the island too. The loops stay for the record, skipped.
	for side in ([] as Array):
		var pts := []
		var x := -HALF_W - 1.0
		while x <= HALF_W + 1.0:
			pts.append(Vector2(x, river_c(x) + side * river_hw(x)))
			x += 1.0
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			if not _bridge_gap((a + b) * 0.5):
				out.append({"a": a, "b": b, "r": RIVER_WALL_R, "team": -1, "kind": "river"})
	# The island's shore, open at the two lane landings.
	var n := 48
	for k in (range(0) if true else range(n)):        # wadeable since Round 33: no shore walls
		var a1 := Vector2(cos(TAU * k / n) * ISLAND_RX, sin(TAU * k / n) * ISLAND_RZ)
		var b1 := Vector2(cos(TAU * (k + 1) / n) * ISLAND_RX, sin(TAU * (k + 1) / n) * ISLAND_RZ)
		if not _bridge_gap((a1 + b1) * 0.5):
			out.append({"a": a1, "b": b1, "r": RIVER_WALL_R, "team": -1, "kind": "river"})
	# Bridge rails from bank to bank (a little past each end of the water).
	for br in bridges():
		var c: Vector2 = br.c
		var hw: float = br.half_w
		var hl: float = br.half_len
		for s in [-1.0, 1.0]:
			out.append({"a": Vector2(c.x + s * hw, c.y - hl + 0.6), "b": Vector2(c.x + s * hw, c.y + hl - 0.6),
				"r": RAIL_R, "team": -1, "kind": "rail"})
	# Plateau faces with ramp gaps, plus the ramp side walls.
	for pl in plateaus():
		var pts: Array = pl.pts
		var cnt := pts.size()
		# Offset the outline outward by WALL_OUT (vertex normals = averaged edge normals).
		var off := []
		for i in cnt:
			var p0: Vector2 = pts[(i - 1 + cnt) % cnt]
			var p1: Vector2 = pts[i]
			var p2: Vector2 = pts[(i + 1) % cnt]
			var n1 := _out_normal(p0, p1, pl.cen)
			var n2 := _out_normal(p1, p2, pl.cen)
			var bis := (n1 + n2).normalized()
			off.append(p1 + bis * WALL_OUT / maxf(0.5, bis.dot(n2)))
		for i in cnt:
			var a: Vector2 = off[i]
			var b: Vector2 = off[(i + 1) % cnt]
			var cuts := []
			for r in pl.ramps:
				if int(r.edge) == i:
					cuts.append(r)
			if cuts.is_empty():
				_edge(out, a, b, 0.35, "ledge")
				continue
			# One ramp per edge (by construction): wall up to the gap, after it, and the ramp's sides.
			var r0: Dictionary = cuts[0]
			var u := (b - a).normalized()
			var s0 := ((r0.a as Vector2) + (r0.u as Vector2) * float(r0.s0) - a).dot(u)
			var g0 := a + u * (s0 - RAMP_HALF)
			var g1 := a + u * (s0 + RAMP_HALF)
			_edge(out, a, g0, 0.35, "ledge")
			_edge(out, g1, b, 0.35, "ledge")
			for e in [g0, g1]:
				_edge(out, e, e + (r0.n as Vector2) * (RAMP_L - 0.4 - WALL_OUT), 0.3, "ledge")
	# The field's edge.
	var lp := edge_loop()
	var half := EDGE_BLUE.size()
	for i in lp.size():
		var k := i % half
		if k == half - 1 or k == EDGE_SKIP:
			continue                         # the closing runs past the field / behind the castles
		_edge(out, lp[i], lp[(i + 1) % lp.size()], EDGE_R, "edge")
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

static func _bridge_gap(mid: Vector2) -> bool:
	for br in bridges():
		var c: Vector2 = br.c
		# The lane's rails are close together: its banks open wider than the deck, or the wall ends
		# would close the walkway at both landings (the rails seal the sides).
		var open := float(br.half_w) + (0.9 if bool(br.lane) else 0.0)
		if absf(mid.x - c.x) < open and absf(mid.y - c.y) < float(br.half_len) + 1.5:
			return true
	return false

static func _out_normal(a: Vector2, b: Vector2, cen: Vector2) -> Vector2:
	var u := (b - a).normalized()
	var n := Vector2(u.y, -u.x)
	return -n if n.dot(cen - (a + b) * 0.5) > 0.0 else n

static func _edge(out: Array, a: Vector2, b: Vector2, r: float, kind: String) -> void:
	# Clip to the field rectangle (+1 m); skip slivers.
	var lim := Vector2(HALF_W + 1.0, HALF_L + 1.0)
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for axis in 2:
		var p0: float = a[axis]
		var dd: float = d[axis]
		for s in [-1.0, 1.0]:
			# keep s * (p0 + t*dd) <= lim
			var num: float = lim[axis] - s * p0
			var den: float = s * dd
			if absf(den) < 0.000001:
				if num < 0.0:
					return
			elif den > 0.0:
				t1 = minf(t1, num / den)
			else:
				t0 = maxf(t0, num / den)
	if t1 - t0 <= 0.0:
		return
	var ca := a + d * t0
	var cb := a + d * t1
	if ca.distance_to(cb) < 0.2:
		return
	out.append({"a": ca, "b": cb, "r": r, "team": -1, "kind": kind})
