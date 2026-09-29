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
]
const LEDGE_R := 0.55             # the KayKit wall pieces on terrace edges are ~1.1 m thick

# Key places (castle-local).
const THRONE := Vector2(0.0, 26.8)
const CELL_C := Vector2(-15.5, 19.0)  # dungeon cell (L1 west wing); bars on 3 sides, open front
const CELL_HX := 1.8
const CELL_HZ := 1.6
const SPAWN := Vector2(0.0, 8.5)
const WORKSHOP := Vector2(13.5, 9.0)
# Buildings (KayKit, team-coloured "%s" = blue/red): solid in the sim (obstacle radius r), placed
# where gameplay doesn't need the floor. y = the level they stand on; rot in degrees (blue space).
const BUILDINGS := [
	{"model": "building_blacksmith_%s", "p": Vector2(17.2, 9.0), "rot": -90.0, "scale": 2.8, "r": 1.7, "y": 0.0},   # the workshop
	{"model": "building_archeryrange_%s", "p": Vector2(16.0, 19.2), "rot": 180.0, "scale": 2.4, "r": 1.9, "y": 1.8},
	{"model": "building_church_%s", "p": Vector2(14.5, 26.0), "rot": 180.0, "scale": 2.6, "r": 1.6, "y": 3.6},
	{"model": "building_tavern_%s", "p": Vector2(-14.5, 26.0), "rot": 180.0, "scale": 2.6, "r": 1.7, "y": 3.6},
	{"model": "building_tower_B_%s", "p": Vector2(-6.5, 27.4), "rot": 0.0, "scale": 2.2, "r": 1.4, "y": 3.6},
	{"model": "building_tower_B_%s", "p": Vector2(6.5, 27.4), "rot": 0.0, "scale": 2.2, "r": 1.4, "y": 3.6},
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
const HAT_HALL := Vector2(-15.0, 8.5)
# Six hat stands in two rows of three, 3 m apart: every stand reachable from outside (1.3 m gaps).
const HAT_STANDS := [Vector2(-18.0, 6.5), Vector2(-15.0, 6.5), Vector2(-12.0, 6.5),
	Vector2(-18.0, 10.5), Vector2(-15.0, 10.5), Vector2(-12.0, 10.5)]

static func _smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

static func height_local(q: Vector2) -> float:
	# Floor height inside the castle footprint (q in castle-local coords).
	for st in STAIRS:
		if q.x >= float(st.x0) and q.x <= float(st.x1) and q.y >= float(st.z0) and q.y < float(st.z1):
			return lerpf(float(st.h0), float(st.h1), (q.y - float(st.z0)) / (float(st.z1) - float(st.z0)))
	if q.y >= L2_Z:
		return L2_H
	if q.y >= L1_Z:
		return L1_H
	return 0.0

static func inside(q: Vector2) -> bool:
	return absf(q.x) <= HX and q.y >= FRONT_Z

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
	return out
