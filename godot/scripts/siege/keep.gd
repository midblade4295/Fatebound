extends RefCounted
# The keep (0.31.165, Kevin: "I think we need to design a new map now to accommodate the games new play style" ->
# "Open keep with 3 gates"): each side's base at its end of the Rift (siege_land.gd). A round curtain wall with a gate
# facing each lane -- a lane's last stop, League's inhibitor: it falls once the lane's third tower is down, and stands
# again GATE_BACK later (moba.gd) -- and inside it the open floor: the King on his throne at the back, the two King
# towers in front of him, and the fountain behind him where heroes come back and heal.
# World coordinates for blue (team 0, the +y end); red's keep is the point mirror (x, y) -> (-x, -y). The sim builds
# its walls, gates and nav from this (siege_sim.gd _build_keep), the view the stonework (siege_view.gd _build_keep).
#
#            back wall (y 110: the field's end)
#        .-'~~~~~~~~~~~~~~~~~~~'-.
#      /       ( fountain )        \        y 104.5
#     |          [King]             |       y  99
#     |     [T]           [T]       |       y  90.5   King towers
#     [gate]                   [gate]       west / east: -135 and -45 degrees round C (toward the side lanes; -150 / -30
#        '-.______[gate]______.-'          until 0.31.216)        middle: -90 degrees (down the middle lane)
# 0.31.216 (the Honor of Kings square, siege_land.gd): the keep fills blue's corner, its back wall the corner itself; seen
# from the yawed camera its side gates face straight up and straight right, along the square's edges.

const C := Vector2(0.0, 96.0)        # the ring's middle
const R := 14.0                      # the wall's line (its faces WALL_R either side: the sim's walls are 1 m thick)
const BACK := 110.0                  # C.y + R: the back of the wall is the field's end
# the gates, by lane (moba.gd LANES: 0 west, 1 middle, 2 east): their angle round C (-PI/2 faces the middle of the field)
const GATE_ANG := [-0.75 * PI, -0.5 * PI, -0.25 * PI]
const GATE_SIDE := ["west", "middle", "east"]
const GATE_HALF := 1.75              # half the doorway: two minions abreast and a hero beside them (1.3 on the Siege castles)
const GATE_PIECE := 3.2              # the walls either side of a gate end this far from its middle (the gatehouse covers them)
const GATEHOUSE_K := 1.2             # the view's kit gatehouse (and its doors) this much bigger than on the Siege castles:
                                     # its arch ~3.6 m round the 3.5 m doorway
const SEG := 5.6                     # the ring's wall chords are about this long
const KING := Vector2(0.0, 99.0)     # where the King stands (his throne just behind him)
const THRONE_SEAT := Vector2(0.0, 100.6)
const THRONE_R := 0.9
const FOUNTAIN := Vector2(0.0, 104.5)
const FOUNTAIN_R := 3.2              # heroes come back within this of the fountain
const KING_TOWERS := [Vector2(-5.0, 90.5), Vector2(5.0, 90.5)]
const ZONE := R + 3.0                # the ground round the keep is level out to this from C
# the castle kit's props (castle_kit.gd: the Royal kit's models) against the back of the wall, clear of the fighting in
# the middle, the King towers, the throne and the fountain: [model, spot (blue), turn (deg; 0 = its front to the gates),
# height]. (The view also stands the kit's fountain on FOUNTAIN.)
const PROPS := [["royal_banner", Vector2(-3.4, 101.6), 0.0, 3.4], ["royal_banner", Vector2(3.4, 101.6), 0.0, 3.4],
	["royal_statue", Vector2(-7.6, 104.2), 25.0, 2.6], ["royal_statue", Vector2(7.6, 104.2), -25.0, 2.6],
	["royal_topiary", Vector2(-10.6, 99.5), 0.0, 2.2], ["royal_topiary", Vector2(10.6, 99.5), 0.0, 2.2]]
const FOUNTAIN_MODEL := "royal_fountain"

static func ring_point(a: float, r := R) -> Vector2:
	return C + Vector2(cos(a), sin(a)) * r

static func gate_c(i: int) -> Vector2:
	return ring_point(float(GATE_ANG[i]))

static func gate_ends(i: int) -> Array:
	# the doorway (the gate's line): a chord across the wall
	var a: float = GATE_ANG[i]
	var da := 2.0 * asin(GATE_HALF / (2.0 * R))
	return [ring_point(a - da), ring_point(a + da)]

static func gatehouse_ends(i: int) -> Array:
	var a: float = GATE_ANG[i]
	var da := 2.0 * asin(GATE_PIECE / (2.0 * R))
	return [ring_point(a - da), ring_point(a + da)]

static func inside(q: Vector2) -> bool:
	# inside the ring (blue space)
	return q.distance_squared_to(C) < R * R

static var _ring: Array = []
static func ring() -> Array:
	# the wall's chords [a, b] (blue space) between the gatehouses, round the back from the east gate to the west one
	if not _ring.is_empty():
		return _ring
	var da := 2.0 * asin(GATE_PIECE / (2.0 * R))
	var arcs := []
	for i in range(GATE_ANG.size() - 1):
		arcs.append([float(GATE_ANG[i]) + da, float(GATE_ANG[i + 1]) - da])
	arcs.append([float(GATE_ANG[GATE_ANG.size() - 1]) + da, float(GATE_ANG[0]) + TAU - da])
	for arc in arcs:
		var a0: float = arc[0]
		var a1: float = arc[1]
		var n := maxi(1, int(round((a1 - a0) * R / SEG)))
		for k in n:
			_ring.append([ring_point(lerpf(a0, a1, float(k) / n)), ring_point(lerpf(a0, a1, float(k + 1) / n))])
	return _ring

static func joints() -> Array:
	# where two of the ring's chords meet (not at a gatehouse): the view stands a tower on every other one
	var out := []
	var rg := ring()
	for k in range(rg.size() - 1):
		if (rg[k][1] as Vector2).distance_to(rg[k + 1][0]) < 0.01:
			out.append(rg[k][1])
	return out
