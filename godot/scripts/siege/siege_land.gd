extends RefCounted
# The Rift (0.31.165, Kevin: "I think we need to design a new map now to accommodate the games new play style" ->
# "Replace it", "112 x 220 m, 3 towers per lane", "Open keep with 3 gates", "A new epic monster"): the 5v5's field.
# Each side's keep (keep.gd) at its end; three lanes from its gates -- the middle straight down the field, the two side
# lanes out along the edges -- three towers a lane (moba.gd); a shallow river across the middle with stone fords where
# the lanes cross it and a pool on either side round a rocky island: the pits, the Bone Lord's (west) and the Grave
# Wyrm's (east), each walled with a mouth toward either bank; the jungle between the lanes on each half, its camps in
# pockets of rock ridges and tree lines, brush (moba_vision.gd) at its ways in.
# Pure static data + functions: the sim turns it into walls / nav / heights, the view into terrain. Everything is
# defined for blue's half (+y) and point-mirrored for red: (x, y) -> (-x, -y). (Until 0.31.165 this file was the Siege
# field: a valley with a lake, an island tower, two bridges, hills and five outposts.)

const Keep = preload("res://scripts/siege/keep.gd")

const HALF_W := 56.0             # (44 on the Siege field)
const HALF_L := 110.0            # (70)

# ---------------- the lanes ----------------
# World points from blue's gate to red's (moba.gd walks them; red walks them backwards). Point symmetric: lane 0
# backwards and mirrored is lane 2; the middle is its own mirror. Each leaves its gate straight out through the wall.
const LANES := [
	[Vector2(-12.1, 89.0), Vector2(-16.4, 86.5), Vector2(-22.0, 83.0), Vector2(-28.5, 78.6), Vector2(-35.0, 73.4),
		Vector2(-40.5, 67.0), Vector2(-44.3, 60.0), Vector2(-46.0, 52.0), Vector2(-46.0, 26.0), Vector2(-46.0, 0.0),
		Vector2(-46.0, -26.0), Vector2(-46.0, -52.0), Vector2(-44.3, -60.0), Vector2(-40.5, -67.0), Vector2(-35.0, -73.4),
		Vector2(-28.5, -78.6), Vector2(-22.0, -83.0), Vector2(-16.4, -86.5), Vector2(-12.1, -89.0)],
	[Vector2(0.0, 82.1), Vector2(0.0, 74.0), Vector2(0.0, 50.0), Vector2(0.0, 26.0), Vector2(0.0, 0.0),
		Vector2(0.0, -26.0), Vector2(0.0, -50.0), Vector2(0.0, -74.0), Vector2(0.0, -82.1)],
	[Vector2(12.1, 89.0), Vector2(16.4, 86.5), Vector2(22.0, 83.0), Vector2(28.5, 78.6), Vector2(35.0, 73.4),
		Vector2(40.5, 67.0), Vector2(44.3, 60.0), Vector2(46.0, 52.0), Vector2(46.0, 26.0), Vector2(46.0, 0.0),
		Vector2(46.0, -26.0), Vector2(46.0, -52.0), Vector2(44.3, -60.0), Vector2(40.5, -67.0), Vector2(35.0, -73.4),
		Vector2(28.5, -78.6), Vector2(22.0, -83.0), Vector2(16.4, -86.5), Vector2(12.1, -89.0)],
]

# ---------------- the river, its fords and the pits ----------------
const RIVER_AMP := 4.0
const RIVER_K := 0.07
const RIVER_HW := 4.5            # half-width of the water away from the pools
const POOL_X := 26.0             # the pits: a pool on the river at x = -POOL_X (the Bone Lord) and +POOL_X (the Wyrm)
const POOL_EXTRA := 7.5          # the pool's extra half-width at its middle (Gaussian in x)
const POOL_SIGMA := 9.0
const LAKE_EXTRA := POOL_EXTRA   # (the view's ripples reach the widest water)
const PIT_R := 7.0               # the island arena in each pool: its rim of rocks
const PIT_WALL_R := 0.8
const PIT_MOUTH := 2.6           # half-width of each mouth through the rim (one toward either bank)
const WATER_Y := -0.45
const BED_Y := -0.58             # shallow: wading is a little slower (Sim.move_mult), nothing more
const FORD_Y := -0.4             # the fords' stones stand just out of the water: no wading on a lane
# [x, half-width] -- across the whole river at that x: the three lanes, and a causeway out to each pit's two mouths
const FORDS := [[0.0, 3.4], [46.0, 3.4], [-46.0, 3.4], [POOL_X, PIT_MOUTH], [-POOL_X, PIT_MOUTH]]

static func river_c(x: float) -> float:
	# Odd in x, so the river is its own point mirror: c(-x) = -c(x).
	return RIVER_AMP * sin(RIVER_K * x)

static func river_hw(x: float) -> float:
	# Even in x, so the banks stay point-symmetric: a pool round each pit.
	var d := absf(x) - POOL_X
	return RIVER_HW + POOL_EXTRA * exp(-(d / POOL_SIGMA) * (d / POOL_SIGMA))

static func river_off(p: Vector2) -> float:
	# How far p is out of the river band (negative: in the band, island or not).
	return absf(p.y - river_c(p.x)) - river_hw(p.x)

static func pit_c(i: int) -> Vector2:
	# 0: the Bone Lord's (west), 1: the Grave Wyrm's (east) -- each other's point mirror
	var x := -POOL_X if i == 0 else POOL_X
	return Vector2(x, river_c(x))

static func island_off(p: Vector2) -> float:
	# Distance from the nearer island's shore: negative on it.
	return minf(p.distance_to(pit_c(0)), p.distance_to(pit_c(1))) - PIT_R

static func shore(p: Vector2) -> float:
	# Distance onto dry land: > 0 on land (field or island), < 0 in the water.
	return maxf(river_off(p), -island_off(p))

static func on_ford(p: Vector2, margin := 0.0) -> bool:
	if river_off(p) > 1.0:
		return false
	for f in FORDS:
		if absf(p.x - float(f[0])) <= float(f[1]) + margin:
			return true
	return false

# ---------------- the field's edge ----------------
# Blue's chain, from the river on the east round the keep to the river on the west; red's is its point mirror, and the
# two close the loop out past the field edge where the river leaves. It meets the keep's wall either side (no wall
# behind the keep: the keep's own).
const EDGE_BLUE := [
	Vector2(57.5, 2.5), Vector2(55.0, 9.0), Vector2(55.5, 24.0), Vector2(54.6, 40.0), Vector2(55.2, 56.0),
	Vector2(53.4, 66.5), Vector2(48.0, 77.5), Vector2(39.0, 86.5), Vector2(28.0, 94.5), Vector2(17.5, 100.5),
	Vector2(11.9, 104.3), Vector2(8.72, 108.45), Vector2(3.93, 110.68), Vector2(0.0, 111.2), Vector2(-3.93, 110.68),
	Vector2(-8.72, 108.45), Vector2(-11.9, 104.3),
	Vector2(-17.5, 100.5), Vector2(-28.0, 94.5), Vector2(-39.0, 86.5), Vector2(-48.0, 77.5), Vector2(-53.4, 66.5),
	Vector2(-55.2, 56.0), Vector2(-54.6, 40.0), Vector2(-55.5, 24.0), Vector2(-55.0, 9.0), Vector2(-57.5, 8.0),
]
const EDGE_R := 0.6
const EDGE_SKIP := [10, 11, 12, 13, 14, 15]   # the runs round behind the keep, just outside its wall (its wall is the edge there)

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
	if absf(p.x) < 46.0 and absf(p.y) < 72.0:
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

const RISE_H := 6.5               # the rock walls round the field

# ---------------- the jungle's rock ridges and tree lines ----------------
# Blue half; red's are the point mirror. Each a line of points the units can't cross (r: its half-thickness), drawn as
# a ridge of rocks ("rock") or a stand of trees ("trees"). Clear of the lanes, the towers (>= 3 m) and the camps.
const RIDGES_BLUE := [
	# the west jungle (blue's Arcane Wraith, Bone Pack, Grave Archers)
	{"pts": [Vector2(-36.5, 14.0), Vector2(-35.5, 26.0), Vector2(-36.0, 37.0)], "r": 1.3, "look": "rock"},
	{"pts": [Vector2(-31.5, 33.5), Vector2(-26.0, 36.0), Vector2(-18.5, 33.5)], "r": 1.3, "look": "rock"},
	{"pts": [Vector2(-8.5, 22.0), Vector2(-9.0, 36.0)], "r": 1.2, "look": "trees"},
	{"pts": [Vector2(-35.0, 55.5), Vector2(-27.0, 59.5), Vector2(-19.0, 57.5)], "r": 1.3, "look": "trees"},
	{"pts": [Vector2(-9.0, 49.0), Vector2(-9.5, 61.0)], "r": 1.2, "look": "rock"},
	{"pts": [Vector2(-25.5, 63.5), Vector2(-23.5, 68.5)], "r": 1.2, "look": "rock"},
	# the east jungle (blue's Ember Brute, Bone Pack, Grave Archers)
	{"pts": [Vector2(36.5, 18.0), Vector2(35.5, 30.0), Vector2(36.0, 41.0)], "r": 1.3, "look": "rock"},
	{"pts": [Vector2(19.0, 36.0), Vector2(26.0, 39.0), Vector2(31.0, 37.2)], "r": 1.3, "look": "rock"},
	{"pts": [Vector2(10.0, 22.0), Vector2(10.0, 36.0)], "r": 1.2, "look": "trees"},
	{"pts": [Vector2(19.0, 57.5), Vector2(27.0, 60.5), Vector2(35.0, 56.5)], "r": 1.3, "look": "trees"},
	{"pts": [Vector2(10.0, 49.0), Vector2(10.5, 61.0)], "r": 1.2, "look": "rock"},
	{"pts": [Vector2(23.5, 63.5), Vector2(25.5, 68.5)], "r": 1.2, "look": "rock"},
]
const PIT_ROCK_LOOK := "rock"

static var _ridges: Array = []
static func ridges() -> Array:
	# both halves, and the pits' rims: {pts, r, look}
	if not _ridges.is_empty():
		return _ridges
	for rg in RIDGES_BLUE:
		_ridges.append(rg)
		var m := []
		for q in rg.pts:
			m.append(-(q as Vector2))
		_ridges.append({"pts": m, "r": rg.r, "look": rg.look})
	for i in 2:
		for side in [1.0, -1.0]:
			# each rim a half-ring from one mouth round to the other (the mouths face the two banks: +y and -y)
			var c := pit_c(i)
			var da := asin(PIT_MOUTH / PIT_R) + 0.12
			var a0 := PI * 0.5 + da if side > 0.0 else -PI * 0.5 + da
			var a1 := a0 + PI - 2.0 * da
			var pts := []
			var n := 6
			for k in n + 1:
				var a := lerpf(a0, a1, float(k) / n)
				pts.append(c + Vector2(cos(a), sin(a)) * PIT_R)
			_ridges.append({"pts": pts, "r": PIT_WALL_R, "look": PIT_ROCK_LOOK, "pit": i})
	return _ridges

static func ridge_dist(p: Vector2) -> Vector2:
	# (distance to the nearest ridge's line, its half-thickness)
	var best := INF
	var br := 0.0
	for rg in ridges():
		var pts: Array = rg.pts
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			if p.distance_to(a) > a.distance_to(b) + 6.0:
				continue
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			if d < best:
				best = d
				br = float(rg.r)
	return Vector2(best, br)

# ---------------- dirt paths (visual) ----------------
# The lanes (LANES) as trodden dirt, and a few jungle trails between the camps (blue half; red's mirrored).
# paths() curves through the control points (Catmull-Rom every PATH_STEP m) and path_wobble() makes the track swell,
# narrow and fray -- baked into the mask's R as a distance (path_r), which terrain.gdshader draws as trodden dirt.
# 0.31.174 (Kevin: "There's a lot of paths that go through unpassable walls"): every trail goes where a unit can --
# round a ridge's end, never through it (tools/path_audit.gd: no dirt under a ridge's rocks or trees). The side lanes'
# trails to the Bone Packs went through the end of the outer rock ridges; the Packs' trails to the middle lane through
# the tree lines (now round their river ends); the Archers' trail brushed the tree line's end.
const TRAILS_BLUE := [
	[Vector2(-45.0, 9.0), Vector2(-39.0, 7.5), Vector2(-33.0, 10.5), Vector2(-31.0, 16.0), Vector2(-31.0, 20.0)],
	[Vector2(-31.0, 20.0), Vector2(-24.0, 23.0), Vector2(-16.0, 21.5), Vector2(-10.5, 16.5), Vector2(-4.0, 15.0)],
	[Vector2(-37.0, 44.0), Vector2(-30.0, 45.0), Vector2(-24.0, 46.0), Vector2(-14.0, 44.0), Vector2(-4.0, 44.0)],
	[Vector2(-24.0, 46.0), Vector2(-16.0, 51.0), Vector2(-13.8, 57.5), Vector2(-14.0, 63.0), Vector2(-14.0, 70.0)],
	[Vector2(45.0, 10.0), Vector2(39.0, 9.5), Vector2(33.0, 13.0), Vector2(31.0, 19.0), Vector2(32.0, 24.0)],
	[Vector2(32.0, 24.0), Vector2(25.0, 25.0), Vector2(17.0, 21.5), Vector2(11.0, 16.5), Vector2(4.0, 16.0)],
	[Vector2(37.0, 48.0), Vector2(30.0, 48.0), Vector2(24.0, 48.0), Vector2(15.0, 45.0), Vector2(5.0, 44.0)],
	[Vector2(24.0, 48.0), Vector2(16.0, 53.0), Vector2(15.0, 62.0), Vector2(14.0, 70.0)],
]
const PATH_HALF_W := 2.1
const TRAIL_HALF := 1.3          # a trail is narrower than a lane (its distance is pushed out by the difference)
const PATH_STEP := 0.75
const PATH_FADE := 3.2           # path_r falls from 1 to 0 over this many metres (0.5 at the track's edge)
const PATH_CORE := 0.5           # path_r is 1 within this of the (wobbled) centre line
static var _paths: Array = []
static var _trails: Array = []

static func paths() -> Array:
	# the smoothed lanes, then the trails (both halves)
	if not _paths.is_empty():
		return _paths
	var out := []
	for pl in LANES:
		out.append(smooth_line(pl))
	_paths = out
	return out

static func trails() -> Array:
	if not _trails.is_empty():
		return _trails
	for pl in TRAILS_BLUE:
		var sm := smooth_line(pl)
		_trails.append(sm)
		var m := []
		for q in sm:
			m.append(-q)
		_trails.append(m)
	return _trails

static func smooth_line(pl: Array) -> Array:
	# a Catmull-Rom curve through the control points (it passes through each, so spurs still meet their paths)
	var out: Array = [pl[0]]
	for i in range(pl.size() - 1):
		var p0: Vector2 = pl[maxi(i - 1, 0)]
		var p1: Vector2 = pl[i]
		var p2: Vector2 = pl[i + 1]
		var p3: Vector2 = pl[mini(i + 2, pl.size() - 1)]
		var n := maxi(1, int(ceil(p1.distance_to(p2) / PATH_STEP)))
		for k in range(1, n + 1):
			out.append(p1.cubic_interpolate(p2, p0, p3, float(k) / n))
	return out

static func path_wobble(p: Vector2) -> float:
	# How much wider (+) or narrower (-) the track is here, in metres -- a slow swell along the way and a trodden,
	# fraying edge. Even in p (cos of a linear form; sin * sin), so both halves match.
	var slow := 0.32 * cos(0.21 * p.x + 0.17 * p.y) * cos(0.13 * p.x - 0.19 * p.y)
	var rag := 0.20 * cos(1.3 * p.x + 0.9 * p.y) + 0.13 * cos(2.3 * p.x - 1.9 * p.y) + 0.08 * sin(3.7 * p.x) * sin(4.1 * p.y)
	return slow + rag

const APRON_BLEND := 2.2

static func smooth_min(a: float, b: float, k: float) -> float:
	if a == INF:
		return b
	if b == INF:
		return a
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)

static func ground_dist(p: Vector2, d_path: float) -> float:
	# the distance path_r measures: to the nearest path, or into a pit's trodden arena, blended where they meet (the
	# Siege field's towers had patches of earth here)
	var best := d_path
	for i in 2:
		best = smooth_min(best, maxf(0.0, p.distance_to(pit_c(i)) - (PIT_R - 2.6)), APRON_BLEND)
	return best

static func path_r(d: float, p: Vector2) -> float:
	# the mask's R for a point d metres from the nearest centre line: 1 on the track's middle, 0.5 at its edge
	return 1.0 - clampf((d - path_wobble(p) - PATH_CORE) / PATH_FADE, 0.0, 1.0)

static func dist_to_paths(p: Vector2) -> float:
	var best := INF
	for pl in paths():
		best = minf(best, _dist_line(p, pl))
	for pl in trails():
		best = minf(best, _dist_line(p, pl) + PATH_HALF_W - TRAIL_HALF)
	return best

static func _dist_line(p: Vector2, pl: Array) -> float:
	var best := INF
	for i in range(pl.size() - 1):
		var a: Vector2 = pl[i]
		var b: Vector2 = pl[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best

# ---------------- heights ----------------
static func _smooth(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static func wobble(p: Vector2) -> float:
	# Smooth -1..1 noise, even in p (so both halves match).
	return 0.5 * cos(0.9 * p.x + 0.7 * p.y) + 0.3 * cos(2.1 * p.x - 1.7 * p.y) + 0.2 * sin(1.3 * p.x) * sin(2.9 * p.y)

static func edge_jit(p: Vector2) -> float:
	# The field's edge as drawn: the rock face wanders a metre in and out of the wall line (scenery only).
	return edge_dist(p) + 0.9 * (0.6 * sin(0.37 * p.x + 1.1) * sin(0.41 * p.y + 0.3) + 0.4 * sin(1.13 * p.x - 0.9 * p.y))

static func keep_dist(p: Vector2) -> float:
	# from the nearer keep's middle
	var q := p if p.y >= 0.0 else -p
	return q.distance_to(Keep.C)

static func rolling(p: Vector2) -> float:
	# Gentle undulation. sin*sin and cos*cos are even under (x,y)->(-x,-y), so both halves match. Level round the keeps,
	# by the water and on the lanes' fords.
	var h := 0.42 * sin(0.19 * p.x) * sin(0.23 * p.y) + 0.32 * cos(0.13 * p.x) * cos(0.11 * p.y)
	var fade := _smooth(Keep.ZONE, Keep.ZONE + 8.0, keep_dist(p))
	fade *= _smooth(1.5, 6.0, river_off(p))
	return h * fade

static func ground_height(p: Vector2, _with_decks := true) -> float:
	# Where units stand. Inside the keeps: level (the view lays the keep's floor over it).
	if keep_dist(p) < Keep.ZONE:
		return 0.0
	var sh := shore(p)
	if sh < 0.8:
		var bed := lerpf(BED_Y, 0.0, _smooth(-0.6, 0.8, sh))
		if on_ford(p):
			bed = maxf(bed, FORD_Y)
		return bed
	return rolling(p)

static func ledge_rim(p: Vector2) -> Vector2:
	# (rim, shadow) for the terrain mask: rock under and round the ridges (and the rock beyond the field's edge); a dark
	# band at their feet.
	var rim := 0.0
	var shadow := 0.0
	var rd := ridge_dist(p)
	if rd.x < rd.y + 2.5:
		var ragged := 0.35 * wobble(p * 1.7)
		rim = 1.0 - _smooth(rd.y * 0.6, rd.y + 0.9 + ragged, rd.x)
		shadow = (1.0 - _smooth(rd.y + 0.2, rd.y + 2.2, rd.x)) * 0.55
	var ed := edge_jit(p)
	if ed > -3.0:
		var face := _smooth(-0.4, 0.4, ed) * (1.0 - _smooth(3.2, 4.4, ed))
		var patches := _smooth(0.35, 0.8, 0.5 + 0.5 * sin(0.53 * p.x + 0.2) * sin(0.47 * p.y + 1.7)) * _smooth(3.0, 5.0, ed) * 0.7
		rim = maxf(rim, maxf(face, patches))
		shadow = maxf(shadow, (1.0 - _smooth(0.0, 2.2, -ed)) * 0.8)
	return Vector2(clampf(rim, 0.0, 1.0), clampf(shadow, 0.0, 1.0))

static func bake_key() -> String:
	# Changes whenever the land's shape data changes: the baked cache (tools/bake_land.gd) is only trusted when it matches.
	var parts := [HALF_W, HALF_L, RIVER_AMP, RIVER_K, RIVER_HW, POOL_X, POOL_EXTRA, POOL_SIGMA, PIT_R, PIT_MOUTH, BED_Y,
		FORD_Y, FORDS, EDGE_BLUE, RIDGES_BLUE, LANES, TRAILS_BLUE, TRAIL_HALF, BAKE_MARGIN, BAKE_STEP, "rift-v1", PATH_STEP,
		PATH_FADE, PATH_CORE, Keep.C, Keep.R, Keep.ZONE, RIDGE_H]
	return str(hash(str(parts)))

# ---------------- baked terrain (visual) ----------------
const BAKE_MARGIN := 7.0          # terrain extends this far past the field edge
const BAKE_STEP := 1.0            # metres between height samples
const MASK_PPM := 4.0             # path-mask pixels per metre
const HEIGHT_RES := "res://assets/terrain/height.res"
const MASK_RES := "res://assets/terrain/pathmask.res"
const RIDGE_H := 1.1              # the ground swells under a ridge's rocks (drawn only: nobody stands there)

static func in_dungeon_pit(_p: Vector2, _margin := 0.0) -> bool:
	return false                  # (the Siege castles' sunken dungeon wings)

static func terrain_height(p: Vector2) -> float:
	var inside := Vector2(clampf(p.x, -HALF_W - 1.5, HALF_W + 1.5), clampf(p.y, -HALF_L, HALF_L))
	var h := ground_height(inside, false)
	if edge_dist(p) <= 0.0:
		var rd := ridge_dist(p)
		if rd.x < rd.y + 0.6:
			h += RIDGE_H * (1.0 - _smooth(rd.y * 0.3, rd.y + 0.6, rd.x)) * (0.75 + 0.25 * wobble(p * 0.9))
		return h
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

# Painted sweeping bands (0.14.4, like the Fat Princess references): concentric light/dark arcs round a few centres,
# blended where neighbouring ring sets meet, gently warped. Baked into the terrain mask's alpha.
const BAND_W := 5.0
const BAND_CENTRES := [Vector2(-60.0, 40.0), Vector2(60.0, 10.0), Vector2(-14.0, 118.0), Vector2(56.0, 80.0)]

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
	var t := _smooth(-2.0, 2.0, d2 - d1)
	return lerpf(0.5 * (ring.call(d1) + ring.call(d2)), ring.call(d1), t)

# ---------------- the world beyond the playfield (view only) ----------------
const OUTER_REACH := 260.0

static func outer_height(p: Vector2) -> float:
	var r := bake_rect()
	var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	var d := p.distance_to(q)
	var hills := 1.2 * sin(p.x * 0.07 + 1.3) * sin(p.y * 0.055 + 0.4) + 0.9 * sin(p.x * 0.031 - p.y * 0.043 + 2.0)
	var rise := clampf((d - 5.0) / 28.0, 0.0, 1.0)
	var h := RISE_H + hills * (0.6 + 4.0 * rise) + rise * rise * 7.0
	var mtn := smoothstep(40.0, 130.0, d)
	h += mtn * (28.0 + 14.0 * sin(p.x * 0.021 + 0.7) * sin(p.y * 0.017 + 1.9) + 8.0 * sin(p.x * 0.05 + p.y * 0.037))
	h = lerpf(terrain_height(q), h, smoothstep(0.0, 14.0, d))      # meets the baked terrain's edge exactly
	if d > 0.0:
		var off := absf(p.y - river_c(p.x))
		h = lerpf(WATER_Y - 0.7, h, smoothstep(RIVER_HW - 0.5, RIVER_HW + 6.0 + d * 0.32, off))
	return h

static func bake_rect() -> Rect2:
	return Rect2(-HALF_W - BAKE_MARGIN, -HALF_L - BAKE_MARGIN, 2.0 * (HALF_W + BAKE_MARGIN), 2.0 * (HALF_L + BAKE_MARGIN))

# ---------------- walls (for the sim) ----------------
static func walls() -> Array:
	# {a, b, r, team:-1, kind}: the ridges and the pits' rims ("rock": arrows fly over, nobody walks through) and the
	# field's "edge". (The river is waded: no banks.)
	var out := []
	for rg in ridges():
		var pts: Array = rg.pts
		for i in pts.size() - 1:
			_edge(out, pts[i], pts[i + 1], float(rg.r), "rock")
	var lp := edge_loop()
	var half := EDGE_BLUE.size()
	for i in lp.size():
		var k := i % half
		if k == half - 1 or EDGE_SKIP.has(k):
			continue                         # the closing runs past the field / behind the keeps
		_edge(out, lp[i], lp[(i + 1) % lp.size()], EDGE_R, "edge")
	# A wall that ends just short of the field edge leaves a slot narrower than a unit between its end cap and the
	# boundary clamp (a knight stuck in one, Round 12): walls ending within 1.5 m of it run 1 m past it instead.
	for w in out:
		for key in ["a", "b"]:
			var q: Vector2 = w[key]
			if absf(q.x) > HALF_W - 1.5 and absf(q.x) < HALF_W + 0.5:
				q.x = signf(q.x) * (HALF_W + 1.0)
			if absf(q.y) > HALF_L - 1.5 and absf(q.y) < HALF_L + 0.5:
				q.y = signf(q.y) * (HALF_L + 1.0)
			w[key] = q
	return out

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
