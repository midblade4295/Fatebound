extends RefCounted
# Fatebound Siege landscape (Round 7; reshaped in 0.26.0 after Kevin's Fat Princess reference):
# a bigger field with a natural edge (rock walls rising all round -- the field lies in a valley; the east was a sheer
# drop with a waterfall until 0.31.13), the river widening into a lake round an island
# tower reached by one narrow bridge lane from each bank, two normal bridges, natural hills (walkable,
# with a few steep rock scarps), rolling slopes, the towers (outposts) and the brick path routes.
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

# 0.31.13 (Kevin: "make the cliff side look like the other side ... in a valley instead of a cliff"): the east no longer
# drops away to a waterfall; the field lies in a valley with rock walls and hills rising on every side, the river running
# on out east through its own gorge as it does west.
const RISE_H := 6.5               # the rock walls round the field

# ---------------- hills and scarps (0.30.2, Kevin: "naturally formed ... slight hills where players can climb up
# in a lot of it and maybe there will be steeper spots") ----------------
# Hills are smooth rises you can walk up from almost anywhere (no walls): a flat-ish top out to r0, easing down to
# the surrounding ground at r1, the outline wobbling. A scarp cuts one flank of a hill into a short rock face:
# on its outer side the hill drops away within SCARP_W, tapering off toward both ends so the face fades back into
# slope; only the steep middle has a wall. Blue half (z > 0); red is the point mirror.
const HILLS := [
	{"c": Vector2(-33.0, 25.0), "h": 2.2, "r0": 7.5, "r1": 15.0},     # the west highland (its tower on top)
	{"c": Vector2(36.0, 18.0), "h": 2.4, "r0": 7.0, "r1": 13.0},      # the east rise at the cliff edge (its tower on top, 0.30.3)
	{"c": Vector2(8.0, 26.0), "h": 1.1, "r0": 1.5, "r1": 8.0},        # a knoll mid-field
]
const SCARPS := [
	{"hill": 0, "pts": [Vector2(-40.5, 19.0), Vector2(-34.0, 16.5), Vector2(-28.0, 17.0)]},
	{"hill": 0, "pts": [Vector2(-40.0, 30.0), Vector2(-35.5, 33.0)]},
	{"hill": 1, "pts": [Vector2(33.5, 10.0), Vector2(38.5, 9.0), Vector2(42.5, 9.5)]},
]
const SCARP_W := 1.0             # the face's horizontal run
const SCARP_TAPER := 2.6         # metres at each end where the face fades back into slope
const SCARP_WALL_OUT := 0.5      # its wall sits mid-face

static func _hill_raw(hl: Dictionary, q: Vector2) -> float:
	var off: Vector2 = q - (hl.c as Vector2)
	var d := off.length() * (1.0 + 0.14 * wobble(off * 0.8))
	return float(hl.h) * (1.0 - _smooth(float(hl.r0), float(hl.r1), d))

static func _scarp_cut(sc: Dictionary, q: Vector2) -> float:
	# 1 = no cut; toward 0 just outside the face (strength tapers to nothing at the ends).
	var pts: Array = sc.pts
	var cen: Vector2 = (HILLS[int(sc.hill)] as Dictionary).c
	var best := INF
	var along := 0.0
	var acc := 0.0
	var total := 0.0
	var side := 0.0
	var interior := false
	for i in pts.size() - 1:
		total += (pts[i] as Vector2).distance_to(pts[i + 1])
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var ab := b - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var cp := a + ab * t
		var d := q.distance_to(cp)
		if d < best:
			best = d
			along = acc + ab.length() * t
			var n := Vector2(ab.y, -ab.x).normalized()
			if n.dot(cen - (a + b) * 0.5) > 0.0:
				n = -n
			side = (q - cp).dot(n)
			interior = not ((i == 0 and t <= 0.0) or (i == pts.size() - 2 and t >= 1.0))
		acc += ab.length()
	if not interior or side <= 0.0 or best > SCARP_W + 0.6:
		return 1.0 if not interior or side <= 0.0 else 1.0 - _taper(along, total)
	return 1.0 - _taper(along, total) * _smooth(0.0, SCARP_W, best)

static func _taper(along: float, total: float) -> float:
	return _smooth(0.0, SCARP_TAPER, along) * _smooth(0.0, SCARP_TAPER, total - along)

static func hills_height(p: Vector2) -> float:
	var q := p if p.y >= 0.0 else -p
	var best := 0.0
	for k in HILLS.size():
		var hl: Dictionary = HILLS[k]
		if q.distance_to(hl.c) > float(hl.r1) * 1.2:
			continue
		var h := _hill_raw(hl, q)
		for sc in SCARPS:
			if int(sc.hill) == k:
				h *= _scarp_cut(sc, q)
		best = maxf(best, h)
	return best

static func scarp_rim(p: Vector2) -> Vector2:
	# (rock, shadow) near a scarp: the face and a ragged lip above it; a dark band at its foot.
	var q := p if p.y >= 0.0 else -p
	var rim := 0.0
	var shadow := 0.0
	for sc in SCARPS:
		var pts: Array = sc.pts
		var cen: Vector2 = (HILLS[int(sc.hill)] as Dictionary).c
		var total := 0.0
		for i in pts.size() - 1:
			total += (pts[i] as Vector2).distance_to(pts[i + 1])
		var acc := 0.0
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var ab := b - a
			var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			var cp := a + ab * t
			var n := Vector2(ab.y, -ab.x).normalized()
			if n.dot(cen - (a + b) * 0.5) > 0.0:
				n = -n
			var sd := (q - cp).dot(n)                 # + outside (down the face), - up on the hill
			var tp := _taper(acc + ab.length() * t, total)
			if q.distance_to(cp) < SCARP_W + 2.5:
				rim = maxf(rim, tp * (1.0 - _smooth(-0.55, -0.25, -sd) if sd < 0.0 else 1.0 - _smooth(SCARP_W, SCARP_W + 0.3, sd)))
				if sd > SCARP_W - 0.2:
					shadow = maxf(shadow, tp * (1.0 - _smooth(SCARP_W, SCARP_W + 1.4, sd)))
			acc += ab.length()
	return Vector2(rim, shadow)

# ---------------- outposts (towers) ----------------
const OUTPOST_R := 6.5           # capture radius (5 until 0.30.3; the towers are wider)
const OUTPOST_TOWER_R := 3.0     # solid tower in the middle (0.30.3, Kevin: "widen"; the same for every model)
const TOWER_TOP_R := 1.85        # how far from the centre a unit up there can walk (inside the parapet, ~2.2 m)
# Each outpost its own Meshy keep (0.31.73, Kevin: "redo the outposts" with Meshy, "a different model for each outpost
# so it shows variety"), by outpost id (outpost_positions order: 0 blue highland, 1 red highland, 2 blue east rise,
# 3 red east rise, 4 the island). The models keep the proportions of the approved concepts, so their decks are at
# different heights; the walkable radius and the solid radius above are the same everywhere (fair, and the sim's
# rules don't change).
#   model  assets/meshy/<model>/ (drawn by siege_view.gd, OUTPOST_MODELS: where its deck and foot are in the model)
#   s      its scale: its wall about as wide as the solid radius, the inside of its parapet >= 2.2 m from the middle
#   sy     how much taller than that (the squat keeps stretched a little, decks ~3 m up; the rook is tall already)
#   yaw    its door faces its own side's castle (blue +z, red -z); the island's faces east, side-on to both
#   floor  the deck's height above the ground: units up there stand on it, shots from it start there (visual only)
#   block  [x, z, r] something standing on the deck that units keep out of (the beacon's fire basket): its middle,
#          in metres from the tower's middle before yaw, and how close a unit's centre may come
const OUTPOST_LOOKS := [
	{"model": "outpost_watchtower", "s": 4.0, "sy": 1.3, "yaw": 0.0, "floor": 2.71},
	{"model": "outpost_fort", "s": 3.5, "sy": 1.12, "yaw": PI, "floor": 2.98},
	{"model": "outpost_ruin", "s": 3.55, "sy": 1.25, "yaw": 0.0, "floor": 2.91},
	{"model": "outpost_rook", "s": 4.46, "sy": 1.0, "yaw": PI, "floor": 4.08},
	{"model": "outpost_beacon", "s": 3.7, "sy": 1.12, "yaw": PI * 0.5, "floor": 2.95, "block": [0.08, -2.19, 1.08]},
]

static func tower_floor(id: int) -> float:
	return float(OUTPOST_LOOKS[id].floor) if id >= 0 and id < OUTPOST_LOOKS.size() else 0.0

static func tower_block(id: int) -> Vector3:
	# The deck's no-go spot as (x, z, r) from the tower's middle in the world (after yaw); r = 0: none.
	if id < 0 or id >= OUTPOST_LOOKS.size() or not OUTPOST_LOOKS[id].has("block"):
		return Vector3.ZERO
	var b: Array = OUTPOST_LOOKS[id].block
	var o := Vector2(float(b[0]), float(b[1])).rotated(-float(OUTPOST_LOOKS[id].yaw))
	return Vector3(o.x, o.y, float(b[2]))
const OUTPOSTS_BLUE_HALF := [Vector2(-31.0, 25.0), Vector2(35.0, 18.5)]   # on the highland; on the east rise (Kevin's circle)
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
	[Vector2(-9.5, 39.0), Vector2(-18.5, 40.5), Vector2(-27.6, 38.4), Vector2(-26.5, 34.5), Vector2(-28.0, 30.0)],
	[Vector2(7.0, 44.0), Vector2(5.0, 38.5), Vector2(2.0, 31.0), Vector2(0.5, 22.0), Vector2(0.0, 13.6)],
	[Vector2(-9.5, 39.0), Vector2(-4.0, 35.0), Vector2(2.0, 31.0)],
	[Vector2(5.0, 38.5), Vector2(13.0, 35.0), Vector2(19.0, 28.5), Vector2(19.5, 21.0), Vector2(20.0, 13.5),
		Vector2(21.0, 8.5), Vector2(24.0, 4.7)],
	[Vector2(19.0, 28.5), Vector2(27.0, 31.5), Vector2(34.5, 30.5), Vector2(35.5, 25.5)],
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
const Castle = preload("res://scripts/siege/siege_castle.gd")
const CASTLE_ZONE := HALF_L - Castle.BACK + Castle.FRONT_Z - 2.0   # |z| beyond this: castle grounds, flat

static func _smooth(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static func wobble(p: Vector2) -> float:
	# Smooth -1..1 noise, even in p (so the plateaus stay point-symmetric): it pushes cliff faces in and out.
	return 0.5 * cos(0.9 * p.x + 0.7 * p.y) + 0.3 * cos(2.1 * p.x - 1.7 * p.y) + 0.2 * sin(1.3 * p.x) * sin(2.9 * p.y)

static func edge_jit(p: Vector2) -> float:
	# The field's edge as drawn: the rock face wanders a metre in and out of the wall line (scenery only).
	return edge_dist(p) + 0.9 * (0.6 * sin(0.37 * p.x + 1.1) * sin(0.41 * p.y + 0.3) + 0.4 * sin(1.13 * p.x - 0.9 * p.y))

static func rolling(p: Vector2) -> float:
	# Gentle hills. sin*sin and cos*cos are even under (x,z)->(-x,-z), so both halves match.
	var h := 0.42 * sin(0.19 * p.x) * sin(0.23 * p.y) + 0.32 * cos(0.13 * p.x) * cos(0.11 * p.y)
	var fade := 1.0 - _smooth(CASTLE_ZONE - 6.0, CASTLE_ZONE, absf(p.y))
	fade *= _smooth(1.5, 6.0, river_off(p))       # flat by the water (and on the island)
	for q in OUTPOSTS_BLUE_HALF:                    # a level patch round each tower's foot (0.30.1)
		fade *= _smooth(7.0, 11.0, minf(p.distance_to(q), p.distance_to(-q)))
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
	return rolling(p) + hills_height(p)

static func ledge_rim(p: Vector2) -> Vector2:
	# (rim, shadow) for the terrain mask: rim = rocky lip on top + the cliff band (plateaus) and the
	# rock beyond the field's edge; shadow = a dark band on the ground at each cliff foot. Ramps stay
	# clean. The plateau part is point-symmetric; the edge part follows the scenery.
	var sr := scarp_rim(p)
	var rim := sr.x
	var shadow := sr.y
	var ed := edge_jit(p)
	if ed > -3.0:
		var rise := 1.0
		# The face (and a ragged lip above it) is stone; the top of the rock walls is grass again, with stony
		# patches -- not one flat brown sheet (0.30.1, Kevin: "more natural, like actual stone, and blend").
		var face := _smooth(-0.4, 0.4, ed) * (1.0 - _smooth(3.2, 4.4, ed))
		var patches := _smooth(0.35, 0.8, 0.5 + 0.5 * sin(0.53 * p.x + 0.2) * sin(0.47 * p.y + 1.7)) * _smooth(3.0, 5.0, ed) * 0.7
		rim = maxf(rim, maxf(face, patches) * (0.6 + 0.4 * rise))
		shadow = maxf(shadow, (1.0 - _smooth(0.0, 2.2, -ed)) * rise * 0.8)
	return Vector2(clampf(rim, 0.0, 1.0), clampf(shadow, 0.0, 1.0))

static func bake_key() -> String:
	# Changes whenever the land's shape data changes: the baked cache (tools/bake_land.gd) is only trusted when it matches.
	var parts := [HALF_W, HALF_L, RIVER_AMP, RIVER_K, RIVER_HW, LAKE_EXTRA, LAKE_SIGMA, ISLAND_RX, ISLAND_RZ, SIDE_BRIDGE_X, LANE_HALF,
		EDGE_BLUE, HILLS, SCARPS, OUTPOSTS_BLUE_HALF, PATHS_BLUE_HALF, BAKE_MARGIN, BAKE_STEP, "cache-v1"]
	return str(hash(str(parts)))

# ---------------- baked terrain (visual) ----------------
const BAKE_MARGIN := 7.0          # terrain extends this far past the field edge
const BAKE_STEP := 1.0            # metres between height samples
const MASK_PPM := 4.0             # path-mask pixels per metre
const HEIGHT_RES := "res://assets/terrain/height.res"
const MASK_RES := "res://assets/terrain/pathmask.res"

# The castles' sunken dungeon wings (siege_castle.gd, Round 13): the terrain dips to the dungeon
# floor there, or the grass would cover the pit. (Blue space; red is point-mirrored.)

static func in_dungeon_pit(p: Vector2, margin := 0.0) -> bool:
	var q := (p if p.y >= 0.0 else -p) - Vector2(0.0, HALF_L - Castle.BACK)
	return q.x >= Castle.ANNEX_X0 - margin and q.x <= -Castle.HX + margin and q.y >= Castle.ANNEX_Z0 - margin and q.y <= Castle.ANNEX_Z1 + margin

static func terrain_height(p: Vector2) -> float:
	if in_dungeon_pit(p):
		return Castle.DUNGEON_H
	var inside := Vector2(clampf(p.x, -HALF_W - 1.5, HALF_W + 1.5), clampf(p.y, -HALF_L, HALF_L))
	var h := ground_height(inside, false)
	if edge_dist(p) <= 0.0:
		return h                                   # the field itself is exactly the walkable ground
	var ed := maxf(edge_jit(p), 0.0)
	# Beyond the edge (scenery): rock walls rising all round. The face wanders (edge_jit), steps once on the way up, and
	# its height varies, so it reads as rock rather than a wall.
	var hi := RISE_H * (0.85 + 0.3 * sin(0.21 * p.x + 0.5) * sin(0.17 * p.y + 1.1))
	var rise := hi * (0.55 * _smooth(0.0, 1.6, ed) + 0.45 * _smooth(2.2, 3.6, ed)) \
		+ 1.3 * _smooth(4.0, 10.0, ed) * (0.5 + 0.5 * sin(0.41 * p.x + 0.7) * sin(0.33 * p.y + 1.3))
	var top := maxf(h, 0.0)
	var out := top + rise
	# The river carries on through, both ways: a gorge between the rock walls.
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
	h = lerpf(terrain_height(q), h, smoothstep(0.0, 14.0, d))      # meets the baked terrain's edge exactly
	if d > 0.0:
		var off := absf(p.y - river_c(p.x))
		# The river's own valley widens as it runs out between the hills (0.31.13: it was a 6 m-wide cut, so out among the
		# mountains its sides stood as sheer flat rock), a soft V rather than a canyon.
		h = lerpf(WATER_Y - 0.7, h, smoothstep(RIVER_HW - 0.5, RIVER_HW + 6.0 + d * 0.32, off))
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
	# Scarp faces: a wall along the steep middle of each (the tapered ends are walkable slope).
	for half in [1.0, -1.0]:
		for sc in SCARPS:
			var pts: Array = sc.pts
			var cen: Vector2 = (HILLS[int(sc.hill)] as Dictionary).c
			var total := 0.0
			for i in pts.size() - 1:
				total += (pts[i] as Vector2).distance_to(pts[i + 1])
			var acc := 0.0
			for i in pts.size() - 1:
				var a: Vector2 = pts[i]
				var b: Vector2 = pts[i + 1]
				var L := a.distance_to(b)
				var nrm := Vector2((b - a).y, -(b - a).x).normalized()
				if nrm.dot(cen - (a + b) * 0.5) > 0.0:
					nrm = -nrm
				var t0 := clampf((SCARP_TAPER * 0.55 - acc) / L, 0.0, 1.0)
				var t1 := clampf((total - SCARP_TAPER * 0.55 - acc) / L, 0.0, 1.0)
				if t1 > t0:
					var wa := a.lerp(b, t0) + nrm * SCARP_WALL_OUT
					var wb := a.lerp(b, t1) + nrm * SCARP_WALL_OUT
					_edge(out, wa * half, wb * half, 0.35, "ledge")
				acc += L
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
