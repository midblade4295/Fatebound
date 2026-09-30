extends RefCounted
# Fatebound Siege castle layout (Round 10, Kevin: "castles much larger and more 3D, like the Fat
# Princess pictures"). Castle-local coordinates, blue space: x across (-HX..HX), z from the front
# wall (FRONT_Z, facing midfield) to the back of the field (BACK). Red is the point mirror.
# The sim builds walls/nav/heights from this; the view builds the castle geometry from it.
#
#   z 29 ─────────────────────────────── field edge
#        L2 terrace (3.6 m): throne room
#   z 22 ──── ledge ──[ grand stairs ]── ledge ────
#        L1 terrace (1.8 m): dungeon (west wing), catapult walks
#   z 14 ─ ledge ─[side]─ ledge ─[ grand stairs ]─ ledge ─[side]─ ledge
#        L0 courtyard (0 m): spawn, hat stands (west), workshop (east)
#   z  3 ═══ wall ═══[gate]═══ wall ═══[gate]═══ wall ═══   (front, towers either side of each gate)

const HX := 20.0                  # half width (was 13)
const BACK := 29.0                # field edge in castle space
const FRONT_Z := 3.0              # front wall (was 15)
const GATE_X := [-7.0, 7.0]       # gate centres on the front wall
const GATE_PIECE := 2.6           # half width of the gatehouse wall piece (5.2 m model)

# Terraces: full width, each a step up from the one in front.
const L1_Z := 14.0
const L2_Z := 22.0
const L1_H := 1.8
const L2_H := 3.6
# Staircases: {x0, x1, z0, z1, h0, h1}; they rise with z, from the lower level to the terrace.
const STAIRS := [
	{"x0": -4.0, "x1": 4.0, "z0": 14.0, "z1": 17.0, "h0": 0.0, "h1": 1.8},    # grand stairs to L1
	{"x0": -11.5, "x1": -8.0, "z0": 14.0, "z1": 17.0, "h0": 0.0, "h1": 1.8},  # west side stairs (3.5 m:
	{"x0": 8.0, "x1": 11.5, "z0": 14.0, "z1": 17.0, "h0": 0.0, "h1": 1.8},    # KayKit terrace walls are thicker)
	{"x0": -3.0, "x1": 3.0, "z0": 22.0, "z1": 25.0, "h0": 1.8, "h1": 3.6},    # grand stairs to L2
	{"x0": -1.6, "x1": 1.6, "z0": 6.0, "z1": 9.0, "h0": 1.8, "h1": 0.0},      # down from the rampart (descends to +z)
]
# The rampart (Round 15, Kevin: "a stair to this platform on the wall so players can walk on the wall
# and shoot arrows from it"): a walkway behind the front wall's middle section, between the two
# gatehouses, at L1 height (the wall top is 2.86 m: a waist-high parapet), 2 m deep, stairs down into
# the courtyard at its centre. Arrows shot from up here fly over the castle walls (siege_sim.gd).
const WALK_X := 4.4                # |x| extent: the middle wall runs between the gatehouse pieces
const WALK_Z1 := 6.0               # from the wall's inner face (FRONT_Z + 1) to here
const WALK_H := 1.8
# Where defending bots stand on it: on the walkway's walkable nav row (z ~4.5, |x| <= 2.5 -- the end
# ledges and the front edge make the cells beyond solid; a post there was unreachable and bots wandered).
const RAMPART_POSTS := [Vector2(-2.5, 4.6), Vector2(2.5, 4.6), Vector2(-1.0, 4.6), Vector2(1.0, 4.6)]
const STAIR_STEPS := 6.0          # steps per flight (castle_mesh.gd draws exactly this many); 0.5 m deep so the
                                  # step stripes read from the overhead camera (9 thin ones looked like a slab)
const LEDGE_R := 0.55             # the KayKit wall pieces on terrace edges are ~1.1 m thick

# Key places (castle-local).
const THRONE := Vector2(0.0, 26.8)
# Dungeon cell (L1 west wing); bars on 3 sides, open front. Its back bars sit ON the L2 face
# (z = 22): at z 20.6 they left a 0.55 m squeeze slot a knight got wedged into (Round 11).
# ---- The dungeon wing (Round 13, Kevin: "make the dungeon down steps where I circled", option A):
# a walled, sunken wing off the west wall. Stairs lead down from the L1 west wing through a doorway
# in the west wall; the King's jail cell sits in the wing's front-west corner (two of its sides are
# the wing's own walls), iron bars on the east side and a barred DOOR on the north side -- a "jail"
# gate: it lifts for the castle's own team and has to be smashed by the enemy.
const ANNEX_X0 := -33.0               # the wing's outer wall line: wholly outside the field (inner face = the
                                      # field edge, -32), so no rounded wall end sits inside it (Round 12 rule)
const ANNEX_Z0 := 8.0                 # front wall line of the wing
const ANNEX_Z1 := 24.0                # back wall line of the wing
const DUNGEON_H := -1.6               # the wing's floor, below ground
const DOOR_Z0 := 17.0                 # clear doorway in the west wall (the wall stops 1 m short of it)
const DOOR_Z1 := 20.0
# Stairs down: along x, from the doorway (L1, 1.8 m) west to the dungeon floor.
const DSTAIR := {"x0": -25.8, "x1": -20.0, "z0": 17.0, "z1": 20.0, "h0": -1.6, "h1": 1.8, "steps": 11.0}
const JAIL_X1 := -28.6                # east bars (the cell is 3.4 m wide, like before)
const JAIL_Z1 := 12.4                 # the door (north side)
const JAIL_HP := 500.0
# The back of the castle (Round 14, Kevin): a wall along the L2 back edge (not a "wall" kind -- no
# ladders from off the map), the throne against it (Blender model, assets/props/throne.glb).
const BACK_WALL_Z := 30.2              # wall line; its face (29.2) is just past the field edge (29)
const THRONE_SEAT := Vector2(0.0, 28.3) # the throne model, flush with the back wall; THRONE (the rescue point) is 1.5 m in front
const JAIL_R := 0.35                  # collision half-thickness of bars and door (walls are 1.0)
const CELL_C := Vector2(-30.3, 10.6)  # the King stands here: inside the jail cell
const CELL_HX := 1.6
const CELL_HZ := 1.6

static func in_annex(q: Vector2) -> bool:
	return q.x >= ANNEX_X0 - 1.0 and q.x < -HX and q.y >= ANNEX_Z0 - 1.0 and q.y <= ANNEX_Z1 + 1.0

static func dungeon_ledges() -> Array:
	# The stairs down have walls on both sides (the dungeon floor is 1.6 m below the ground and the
	# stairs rise to the L1 floor, 1.8 m above it).
	return [[Vector2(DSTAIR.x0, DSTAIR.z0), Vector2(DSTAIR.x1, DSTAIR.z0)],
		[Vector2(DSTAIR.x0, DSTAIR.z1), Vector2(DSTAIR.x1, DSTAIR.z1)]]
const SPAWN := Vector2(0.0, 10.5)     # in front of the rampart stairs (8.5 until Round 15: now the stairs)
const WORKSHOP := Vector2(13.5, 9.0)
# Buildings (KayKit, team-coloured "%s" = blue/red): solid in the sim (obstacle radius r), placed
# where gameplay doesn't need the floor. y = the level they stand on; rot in degrees (blue space).
const BUILDINGS := [
	# Buildings against a wall TOUCH it (no squeeze slot behind them).
	{"model": "building_blacksmith_%s", "p": Vector2(17.35, 9.0), "rot": -90.0, "scale": 2.8, "r": 1.7, "y": 0.0},   # the workshop
	{"model": "building_archeryrange_%s", "p": Vector2(16.0, 19.6), "rot": 180.0, "scale": 2.4, "r": 1.9, "y": 1.8},
	{"model": "building_church_%s", "p": Vector2(14.5, 26.0), "rot": 180.0, "scale": 2.6, "r": 1.6, "y": 3.6},
	{"model": "building_tavern_%s", "p": Vector2(-14.5, 26.0), "rot": 180.0, "scale": 2.6, "r": 1.7, "y": 3.6},
]
# Small props (visual only), tucked against walls and terrace faces.
const PROPS := [
	["barrel", Vector2(-19.0, 4.6), 2.2], ["barrel", Vector2(-18.2, 4.4), 2.0], ["crate_A_big", Vector2(19.0, 4.8), 2.2],
	["crate_B_small", Vector2(18.2, 4.3), 2.4], ["weaponrack", Vector2(4.6, 13.2), 3.2], ["target", Vector2(-5.6, 13.1), 3.4],
	["target", Vector2(-7.0, 13.1), 3.4], ["sack", Vector2(15.0, 12.9), 2.4], ["wheelbarrow", Vector2(11.4, 12.8), 3.0],
	["barrel", Vector2(-19.2, 21.2), 2.2], ["crate_long_A", Vector2(-11.0, 21.3), 2.2], ["bucket_arrows", Vector2(12.6, 21.2), 3.0],
	["flag_%s", Vector2(-3.4, 25.4), 2.0], ["flag_%s", Vector2(3.4, 25.4), 2.0],
]
const ALTAR := Vector2(-4.0, 11.5)
const CATAPULT_X := 17.0
# Hat machines spread around the castle (Round 11, Kevin), one per class, each >= 1 m from any wall
# or building (tests/siege_land_check.gd: no squeeze traps). Order = Sim.HAT_CLASSES:
# knight (courtyard west, by the gate), barbarian (courtyard east, by the blacksmith), rogue
# (courtyard back-west corner), ranger (L1 east, by the archery range), mage (L2 west, by the
# tavern), priest (L2 east, by the church).
const HAT_STANDS := [Vector2(-13.0, 5.6), Vector2(14.5, 12.0), Vector2(-16.5, 11.0),
	Vector2(12.2, 19.6), Vector2(-9.5, 25.0), Vector2(9.5, 25.0)]
const HAT_HALL := Vector2(-13.0, 7.4)     # open floor by the knight machine (hints / tests)

static func _smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

static func height_local(q: Vector2) -> float:
	# Floor height inside the castle footprint (q in castle-local coords).
	if q.x < -HX:
		# The dungeon wing: the stairs down (along x, one riser above the ramp as on the other
		# stairs), else the sunken floor.
		if q.x >= float(DSTAIR.x0) and q.y >= float(DSTAIR.z0) and q.y < float(DSTAIR.z1):
			var t := clampf((q.x - float(DSTAIR.x0)) / (float(DSTAIR.x1) - float(DSTAIR.x0)), 0.0, 1.0)
			var riser := (float(DSTAIR.h1) - float(DSTAIR.h0)) / float(DSTAIR.steps)
			return minf(float(DSTAIR.h1), lerpf(float(DSTAIR.h0), float(DSTAIR.h1), t) + riser)
		return DUNGEON_H
	for st in STAIRS:
		if q.x >= float(st.x0) and q.x <= float(st.x1) and q.y >= float(st.z0) and q.y < float(st.z1):
			# One riser above the ramp: the drawn steps are blocks whose tops sit above the straight
			# ramp for most of each step, so feet on the ramp sank into them. Ramp + one riser is
			# >= the tread under the unit everywhere on the flight. Works for flights that descend
			# along +z too (the rampart's).
			var t := (q.y - float(st.z0)) / (float(st.z1) - float(st.z0))
			var riser := absf(float(st.h1) - float(st.h0)) / STAIR_STEPS
			return minf(maxf(float(st.h0), float(st.h1)), lerpf(float(st.h0), float(st.h1), t) + riser)
	if absf(q.x) <= WALK_X and q.y >= FRONT_Z and q.y < WALK_Z1:
		return WALK_H                               # the rampart
	if q.y >= L2_Z:
		return L2_H
	if q.y >= L1_Z:
		return L1_H
	return 0.0

static func inside(q: Vector2) -> bool:
	return (absf(q.x) <= HX and q.y >= FRONT_Z) or in_annex(q)

static func ledges() -> Array:
	# Terrace faces with gaps where the stairs are, plus a ledge along each stair side (you can't
	# step off a staircase sideways). [a, b] pairs in castle-local coords.
	var out := []
	for z in [L1_Z, L2_Z]:
		var gaps := []
		for st in STAIRS:
			if absf(float(st.z0) - z) < 0.01:
				gaps.append([float(st.x0), float(st.x1)])
		gaps.sort_custom(func(a, b): return a[0] < b[0])
		var x := -HX
		for g in gaps:
			if g[0] - x > 0.2:
				out.append([Vector2(x, z), Vector2(g[0], z)])
			x = g[1]
		if HX - x > 0.2:
			out.append([Vector2(x, z), Vector2(HX, z)])
	for st in STAIRS:
		for sx in [float(st.x0), float(st.x1)]:
			out.append([Vector2(sx, float(st.z0)), Vector2(sx, float(st.z1))])
	# The rampart's inner edge (open at its stairs) and its two ends above the gate passages.
	var rs: Dictionary = STAIRS[STAIRS.size() - 1]
	out.append([Vector2(-WALK_X, WALK_Z1), Vector2(float(rs.x0), WALK_Z1)])
	out.append([Vector2(float(rs.x1), WALK_Z1), Vector2(WALK_X, WALK_Z1)])
	for sx in [-WALK_X, WALK_X]:
		out.append([Vector2(sx, FRONT_Z + 1.0), Vector2(sx, WALK_Z1)])
	return out
