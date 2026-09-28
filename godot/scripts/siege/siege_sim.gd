extends RefCounted
# Fatebound Siege: real-time capture-the-Oracle between two castles. Pure simulation with no scene
# nodes, stepped at a fixed rate, so the same rules can later run on an authoritative server.
# Coordinates: Vector2(x, z) on the ground plane. Blue (team 0) holds the south end (+z), red
# (team 1) the north end (-z). Red's castle is the point mirror of blue's: (x, z) -> (-x, -z).

const TICK := 1.0 / 30.0
const HALF_W := 26.0
const HALF_L := 52.0
# Castle layouts are authored in "castle-local" blue-space coordinates (x -13..13, z 15..29 with
# the back at z=29) and placed at each end of the field by _c(): shifted so the castle's back
# sits on the field edge, then mirrored for red.
const CASTLE_BACK := 29.0
const CASTLE_SHIFT := HALF_L - CASTLE_BACK
const CASTLE_HX := 13.0
const UNIT_R := 0.45
const WIN_RESCUES := 3
const MATCH_TIME := 720.0
const RESPAWN_TIME := 5.0
const DROP_RETURN := 25.0        # a dropped Oracle nobody moves goes back to her cell
const FORGE_RADIUS := 2.6
const WORKSHOP_RADIUS := 2.8
const PICKUP_RADIUS := 1.5
const THRONE_RADIUS := 2.2
const ROLL_TIME := 0.7

# ---- castle geometry (blue side; red mirrored) ----
const WALL_SCALE := 2.6          # KayKit wall_straight is 2.0 long -> 5.2 m
const SEG := 5.2
const WALL_R := 1.0              # collision half-thickness of a wall
const FRONT_Z := 15.0            # outer wall with the two gates
const INNER_Z := 21.0            # wall between courtyard and the back rooms
const GATE_X := [-5.2, 5.2]      # gate centres on the front wall
const DOOR_X := [-5.2, 5.2]      # open doorways in the inner wall (behind each gate)
const KEEP_X := 2.6              # keep block spans x -2.6..2.6, z 21..29
const GATE_HP := 1500.0
const GATE_HALF := 1.3           # half-width of the passable doorway
const GATE_SOLID_AT := 0.35      # a broken gate blocks again once repaired to 35 %
const GATE_OPEN_RADIUS := 4.0    # allies within this distance swing the doors open (visual)
const REPAIR_LOCK := 3.0         # no repairs while the gate was hit in the last 3 s
const RUBBLE_TIME := 20.0        # a broken gate can't be rebuilt for 20 s ...
const RUBBLE_CLEAR := 6.0        # ... or while any enemy is within 6 m of it

# ---- layers (heights are for the view; the sim stays 2D, ledges are walls) ----
const PLAT_H := 1.6              # throne room + dungeon platforms
const STAIR_Z0 := 21.0           # stairs climb from the inner doorway...
const STAIR_Z1 := 23.0           # ...to the platform
const STAIR_X0 := 3.9            # stair channel |x| range (inside the 3.2 m doorway)
const STAIR_X1 := 6.5
const HILL_H := 1.2              # midfield plateau around the ruin
const HILL_X := 4.5
const HILL_Z := 3.0
const HILL_STAIR_X := 1.3
const HILL_STAIR_Z := 5.0
const LEDGE_R := 0.35

# ---- fate offerings (the "cake") ----
const ALTAR_P := Vector2(-3.5, 17.0)   # blue courtyard; mirrored for red
const OFFERING_EVERY := 30.0
const CAKE_EVERY := 60.0            # a cake tree ripens a cake every 60 s
const CAKE_PER_STAGE := 3           # three cakes fatten her one size stage
const LIFTERS := [1, 2, 3, 4, 5, 6] # players needed to lift her at each stage (skinny .. fully fattened)
const LIFT_RING := 1.15             # followers hold her from a ring around the lead lifter
const TANTRUM_AFTER := 6.0          # left on the ground this long -> tantrum
const TANTRUM_EVERY := 6.0
const TANTRUM_R := 5.0
const TANTRUM_PUSH := 4.0
const TANTRUM_STUN := 1.6
const HEAL_R := 3.2                 # captive Oracle heals her own team standing next to her
const HEAL_RATE := 12.0             # hp per second
const BLESS_R := 4.2                # while her own team carries her, she heals them within this
const EXTRA_LIFTER := 0.10          # each lifter beyond the minimum: +10 % carry speed
const MAX_WEIGHT := 5
const WEIGHT_SLOW := 0.08            # carrier speed -8 % per weight level
const FEED_RADIUS := 1.9

# ---- catapults (upgrade) ----
const CATAPULT_X := 12.3
const CATAPULT_EVERY := 4.5
const CATAPULT_MIN := 5.0
const CATAPULT_MAX := 22.0
const CATAPULT_FLIGHT := 1.4
const CATAPULT_DMG := 45.0
const CATAPULT_AOE := 2.6

# ---- siege ladders ----
const LADDER_COST := 8
const LADDER_BUILD := 3.0
const LADDER_HP := 250.0
const LADDER_HALF := 1.1          # half-width of the passage along the wall
const LADDER_CLIMB := 0.5         # speed while crossing the wall

# ---- gathering / crafting ----
const CARRY_MAX := 5
const GATHER_TIME := 0.9         # seconds per unit gathered
const REPAIR_TICK := 0.5
const REPAIR_HP := 30.0          # per tick, costs 1 wood
const UPGRADES := {
	"gates":  {"name":"Reinforced Gates", "max":2, "cost":[{"wood":15,"stone":10},{"wood":25,"stone":20}],
		"desc":"+50% gate HP per level, and repairs all gates"},
	"armory": {"name":"Armory", "max":3, "cost":[{"wood":10,"stone":15},{"wood":20,"stone":25},{"wood":30,"stone":35}],
		"desc":"+12% HP and damage per level for your fighters"},
	"forge":  {"name":"Fourth Die", "max":1, "cost":[{"wood":10,"stone":20}],
		"desc":"The forge rolls four dice: easier pairs and triples"},
	"catapult": {"name":"Catapults", "max":1, "cost":[{"wood":15,"stone":25}],
		"desc":"Your corner towers lob stones at enemies 5-22 m away"},
}

const FACES := ["knight","barbarian","rogue","ranger","mage","fate"]
const UPGRADE_NAME := {"knight":"Paladin","barbarian":"Berserker","rogue":"Assassin","ranger":"Sniper","mage":"Archmage"}

# range: melee reach or projectile travel. arc: cosine of the half-angle a melee swing covers.
# gate: damage multiplier against gates.
const CLASSES := {
	"villager": {"name":"Villager","hp":60,"speed":5.2,"dmg":8,"range":1.3,"arc":0.5,"windup":0.2,"recover":0.3,
		"ranged":false,"ability":"","ab_cd":0.0,"carry":0.65,"gate":0.5},
	"worker": {"name":"Worker","hp":95,"speed":5.0,"dmg":12,"range":1.5,"arc":0.4,"windup":0.28,"recover":0.4,
		"ranged":false,"ability":"","ab_cd":0.0,"carry":0.65,"gate":1.2},
	"knight": {"name":"Knight","hp":150,"speed":4.6,"dmg":18,"range":1.7,"arc":0.4,"windup":0.24,"recover":0.4,
		"ranged":false,"ability":"bash","ab_cd":7.0,"carry":0.65,"gate":1.0},
	"barbarian": {"name":"Barbarian","hp":130,"speed":4.8,"dmg":26,"range":2.0,"arc":0.25,"windup":0.36,"recover":0.45,
		"ranged":false,"ability":"spin","ab_cd":7.0,"carry":0.65,"gate":1.6},
	"rogue": {"name":"Rogue","hp":85,"speed":6.2,"dmg":14,"range":1.4,"arc":0.5,"windup":0.13,"recover":0.22,
		"ranged":false,"ability":"lunge","ab_cd":5.0,"carry":0.72,"gate":0.6},
	"ranger": {"name":"Ranger","hp":80,"speed":5.4,"dmg":15,"range":11.0,"arc":0.0,"windup":0.3,"recover":0.45,
		"ranged":true,"proj_speed":22.0,"aoe":0.0,"ability":"volley","ab_cd":7.0,"carry":0.65,"gate":0.35},
	"mage": {"name":"Mage","hp":75,"speed":5.0,"dmg":20,"range":9.0,"arc":0.0,"windup":0.4,"recover":0.5,
		"ranged":true,"proj_speed":15.0,"aoe":1.6,"ability":"nova","ab_cd":8.0,"carry":0.65,"gate":1.0},
}

var time := 0.0
var ended := false
var winner := -1
var end_reason := ""
var units: Array = []
var by_id: Dictionary = {}
var projectiles: Array = []
var oracles: Array = []
var score := [0, 0]
var kills := [0, 0]
var events: Array = []
var obstacles: Array = []      # circles: trees, rocks, ruin, buildings  {p, r, kind, team?}
var walls: Array = []          # segments {a, b, r, team, kind}
var gates: Array = []          # {id, team, a, b, c, hp, max_hp, broken, open}
var nodes: Array = []          # resource nodes {id, kind:"wood"/"stone", p, r, amount, max, regen, t}
var stock := [{"wood":0, "stone":0}, {"wood":0, "stone":0}]
var levels := [{"gates":0, "armory":0, "forge":0, "catapult":0}, {"gates":0, "armory":0, "forge":0, "catapult":0}]
var cake_trees: Array = []     # {id, p, ready, t}  neutral, across the land
var catapults: Array = []      # {team, p, t, side}
var shells: Array = []         # catapult stones in flight {id, team, from, to, t, flight}
var ladders: Array = []        # {id, team (owner), wall (index), p, hp, cells}
var _next_shell := 1
var _next_ladder := 1
var rng := RandomNumberGenerator.new()
var nav: Array = []            # AStarGrid2D per team
var nav_version := 0
var _ai_clock := 0.0
var _cmd_clock := 0.0
var _next_proj := 1

# ---------- map ----------
static func _m(team: int, p: Vector2) -> Vector2:
	return p if team == 0 else -p

static func _c(team: int, p: Vector2) -> Vector2:
	# Castle-local (blue space) -> world.
	return _m(team, p + Vector2(0.0, CASTLE_SHIFT))

static func throne(team: int) -> Vector2:
	# Where a team brings its rescued Oracle: its own throne room (east back room for blue).
	return _c(team, Vector2(8.0, 26.0))

const CELL_C := Vector2(-9.0, 27.0)   # cell centre (blue dungeon); bars x -10.8..-7.2, z 25.4..28.6
const CELL_HX := 1.8
const CELL_HZ := 1.6

static func cell(team: int) -> Vector2:
	# Where a team's own Oracle is held captive: the ENEMY castle's dungeon.
	return _c(1 - team, CELL_C)

static func height_at(p: Vector2) -> float:
	# Ground height for rendering. Castles are evaluated in blue space (mirror for red).
	var q := (p if p.y >= 0.0 else -p) - Vector2(0.0, CASTLE_SHIFT)
	var ax := absf(q.x)
	if q.y >= STAIR_Z0 and ax >= KEEP_X and ax <= CASTLE_HX:
		if ax >= STAIR_X0 and ax <= STAIR_X1 and q.y < STAIR_Z1:
			return PLAT_H * clampf((q.y - STAIR_Z0) / (STAIR_Z1 - STAIR_Z0), 0.0, 1.0)
		return PLAT_H
	# Midfield plateau (symmetric in both axes), stairs on its north and south faces.
	var az := absf(p.y)
	var bx := absf(p.x)
	if bx <= HILL_X and az <= HILL_Z:
		return HILL_H
	if bx <= HILL_STAIR_X and az > HILL_Z and az < HILL_STAIR_Z:
		return HILL_H * clampf((HILL_STAIR_Z - az) / (HILL_STAIR_Z - HILL_Z), 0.0, 1.0)
	return 0.0

static func forge(team: int) -> Vector2:
	return _c(team, Vector2(-8.5, 18.0))

static func workshop(team: int) -> Vector2:
	return _c(team, Vector2(8.5, 18.0))

static func altar(team: int) -> Vector2:
	return _c(team, ALTAR_P)

static func spawn(team: int) -> Vector2:
	return _c(team, Vector2(0.0, 18.2))

static func gate_front(g: Dictionary) -> Vector2:
	# Standing point just outside a gate (the side facing midfield).
	var outward := Vector2(0, -1) if g.team == 0 else Vector2(0, 1)
	return g.c + outward * 2.2

func _add_wall(team: int, a: Vector2, b: Vector2, kind := "wall") -> void:
	walls.append({"a":_c(team, a), "b":_c(team, b), "r":WALL_R, "team":team, "kind":kind})

func _build_map() -> void:
	walls.clear()
	gates.clear()
	obstacles.clear()
	nodes.clear()
	for t in 2:
		# Front wall at z=15 with two gates; pieces are one 5.2 m wall model each.
		# Pieces that meet the field edge run 1 m past it, so there is no rounded wall end at the
		# edge for a unit to be pushed around and clamped back into.
		_add_wall(t, Vector2(-CASTLE_HX, FRONT_Z), Vector2(-7.8, FRONT_Z))
		_add_wall(t, Vector2(-2.6, FRONT_Z), Vector2(2.6, FRONT_Z))
		_add_wall(t, Vector2(7.8, FRONT_Z), Vector2(CASTLE_HX, FRONT_Z))
		# Side walls: the field is wider than the castle, so it needs its own flanks. They run
		# 1 m past the field edge at the back (no rounded end for a unit to be clamped into).
		_add_wall(t, Vector2(-CASTLE_HX, FRONT_Z), Vector2(-CASTLE_HX, CASTLE_BACK + 1.0))
		_add_wall(t, Vector2(CASTLE_HX, FRONT_Z), Vector2(CASTLE_HX, CASTLE_BACK + 1.0))
		for gx in GATE_X:
			# The gate model is a 5.2 m wall piece with a ~2.3 m doorway; only the doorway is the
			# gate. The neighbouring wall ends (radius 1.0) cover the stone pillars either side.
			var a := _c(t, Vector2(gx - GATE_HALF, FRONT_Z))
			var b := _c(t, Vector2(gx + GATE_HALF, FRONT_Z))
			gates.append({"id":gates.size(), "team":t, "a":a, "b":b, "c":(a + b) * 0.5, "hp":GATE_HP, "max_hp":GATE_HP,
				"broken":false, "open":false, "side":"west" if gx < 0.0 else "east"})
		# The back rooms are a raised terrace: its front edge at z=21 is a ledge (retaining wall +
		# parapet), open only where the two staircases climb it.
		for seg in [[-CASTLE_HX, -STAIR_X1], [-STAIR_X0, -KEEP_X], [KEEP_X, STAIR_X0], [STAIR_X1, CASTLE_HX]]:
			walls.append({"a":_c(t, Vector2(seg[0], INNER_Z)), "b":_c(t, Vector2(seg[1], INNER_Z)), "r":LEDGE_R, "team":t, "kind":"ledge"})
		# Keep block between the dungeon (west) and the throne room (east).
		_add_wall(t, Vector2(-KEEP_X, INNER_Z + 0.5), Vector2(KEEP_X, INNER_Z + 0.5), "keep")
		_add_wall(t, Vector2(-KEEP_X, INNER_Z + 0.5), Vector2(-KEEP_X, CASTLE_BACK + 1.0), "keep")
		_add_wall(t, Vector2(KEEP_X, INNER_Z + 0.5), Vector2(KEEP_X, CASTLE_BACK + 1.0), "keep")
		# The cell in the dungeon: bars on three sides, open towards the doorway (front).
		# The back bars sit exactly on the field edge: a narrower gap between them and the edge
		# (it was 0.4 m) trapped units between the bars and the boundary clamp.
		var cc := CELL_C
		var back := CASTLE_BACK
		walls.append({"a":_c(t, cc + Vector2(-CELL_HX, -CELL_HZ)), "b":_c(t, Vector2(cc.x - CELL_HX, back)), "r":0.3, "team":t, "kind":"bars"})
		walls.append({"a":_c(t, cc + Vector2(CELL_HX, -CELL_HZ)), "b":_c(t, Vector2(cc.x + CELL_HX, back)), "r":0.3, "team":t, "kind":"bars"})
		walls.append({"a":_c(t, Vector2(cc.x - CELL_HX, back)), "b":_c(t, Vector2(cc.x + CELL_HX, back)), "r":0.3, "team":t, "kind":"bars"})
		# Stair channels up to the platforms: ledges on both sides so you can't step off.
		for sx in [-1.0, 1.0]:
			for lx in [STAIR_X0, STAIR_X1]:
				walls.append({"a":_c(t, Vector2(sx * lx, STAIR_Z0)), "b":_c(t, Vector2(sx * lx, STAIR_Z1)), "r":LEDGE_R, "team":t, "kind":"ledge"})
		# Courtyard buildings (solid): forge + workshop sit against the side walls.
		obstacles.append({"p":_c(t, Vector2(-11.2, 18.0)), "r":1.4, "kind":"forge_building", "team":t})
		obstacles.append({"p":_c(t, Vector2(11.2, 18.0)), "r":1.4, "kind":"workshop_building", "team":t})
		# Resource nodes on each half (world coords, point-mirrored): forests on both flanks,
		# quarries between the lanes, and a few trees near the castle approaches.
		for tp in [Vector2(-21.0, 33.0), Vector2(-23.0, 26.0), Vector2(-19.5, 19.0), Vector2(-23.5, 12.0), Vector2(-20.0, 5.0),
				Vector2(21.0, 31.0), Vector2(23.5, 23.0), Vector2(19.0, 15.0), Vector2(22.0, 7.0), Vector2(-9.0, 33.5)]:
			_add_node(t, "wood", tp)
		for sp in [Vector2(-12.0, 22.0), Vector2(13.0, 26.0), Vector2(1.5, 17.0), Vector2(-14.0, 8.0)]:
			_add_node(t, "stone", sp)
		# Cover between the lanes.
		for rp in [Vector2(-6.0, 25.0), Vector2(8.0, 11.0), Vector2(-16.0, 30.0)]:
			obstacles.append({"p":_m(t, rp), "r":1.2, "kind":"rock"})
	obstacles.append({"p":Vector2(0, 0), "r":1.8, "kind":"ruin"})
	# Cake trees across the land (point-mirrored pairs); any team can pick a cake. The trunk is
	# solid; the cake is picked from beside it.
	cake_trees = []
	for cp in [Vector2(-17.0, 20.0), Vector2(6.5, 7.0), Vector2(-24.0, 0.0)]:
		for t in 2:
			var ctp := _m(t, cp)
			cake_trees.append({"id":cake_trees.size(), "p":ctp, "ready":true, "t":0.0})
			obstacles.append({"p":ctp, "r":0.6, "kind":"cake_tree"})
	for s in [-1.0, 1.0]:
		walls.append({"a":Vector2(s * HILL_X, -HILL_Z), "b":Vector2(s * HILL_X, HILL_Z), "r":LEDGE_R, "team":-1, "kind":"ledge"})
		walls.append({"a":Vector2(-HILL_X, s * HILL_Z), "b":Vector2(-HILL_STAIR_X, s * HILL_Z), "r":LEDGE_R, "team":-1, "kind":"ledge"})
		walls.append({"a":Vector2(HILL_STAIR_X, s * HILL_Z), "b":Vector2(HILL_X, s * HILL_Z), "r":LEDGE_R, "team":-1, "kind":"ledge"})
		for sx in [-1.0, 1.0]:
			walls.append({"a":Vector2(sx * HILL_STAIR_X, s * HILL_Z), "b":Vector2(sx * HILL_STAIR_X, s * HILL_STAIR_Z), "r":LEDGE_R, "team":-1, "kind":"ledge"})
	_add_node(0, "wood", Vector2(-12.0, 0.5))
	_add_node(1, "wood", Vector2(-12.0, 0.5))

func _add_node(team: int, kind: String, p: Vector2) -> void:
	var pos := _m(team, p)
	var n := {"id":nodes.size(), "kind":kind, "p":pos, "r":0.9 if kind == "wood" else 1.0,
		"amount":10 if kind == "wood" else 15, "max":10 if kind == "wood" else 15,
		"regen":10.0 if kind == "wood" else 12.0, "t":0.0}
	nodes.append(n)
	obstacles.append({"p":pos, "r":n.r, "kind":"tree" if kind == "wood" else "rock", "node":n.id})

# ---------- navigation ----------
const NAV_W := int(HALF_W * 2.0)
const NAV_H := int(HALF_L * 2.0)

static func nav_cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(floor(p.x + HALF_W)), 0, NAV_W - 1), clampi(int(floor(p.y + HALF_L)), 0, NAV_H - 1))

static func nav_point(c: Vector2i) -> Vector2:
	return Vector2(c.x - HALF_W + 0.5, c.y - HALF_L + 0.5)

static func seg_closest(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return a + ab * t

func _cells_near_segment(a: Vector2, b: Vector2, reach: float) -> Array:
	# Nav cells whose centre lies within `reach` of segment a-b (bounding-box scan only).
	var out := []
	var lo := nav_cell(Vector2(minf(a.x, b.x) - reach, minf(a.y, b.y) - reach))
	var hi := nav_cell(Vector2(maxf(a.x, b.x) + reach, maxf(a.y, b.y) + reach))
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			var c := Vector2i(x, y)
			var p := nav_point(c)
			if p.distance_to(seg_closest(p, a, b)) < reach:
				out.append(c)
	return out

# ---------- spatial buckets (collision culling) ----------
# Walls and obstacles never move after _build_map, so each 6 m bucket lists the ones that can
# touch a unit standing in it. _separate was 1.7 of 2.4 ms per tick at 16v16 testing everything.
const BUCKET := 6.0
const BUCKET_REACH := 1.6      # widest wall/obstacle radius + unit radius, with margin
var _bw := 0
var _bh := 0
var _bucket_walls: Array = []
var _bucket_obs: Array = []

func _build_buckets() -> void:
	_bw = int(ceil(HALF_W * 2.0 / BUCKET)) + 1
	_bh = int(ceil(HALF_L * 2.0 / BUCKET)) + 1
	_bucket_walls = []
	_bucket_obs = []
	for i in _bw * _bh:
		_bucket_walls.append(PackedInt32Array())
		_bucket_obs.append(PackedInt32Array())
	for wi in walls.size():
		var w: Dictionary = walls[wi]
		for bi in _buckets_in(minf(w.a.x, w.b.x) - w.r - BUCKET_REACH, minf(w.a.y, w.b.y) - w.r - BUCKET_REACH,
				maxf(w.a.x, w.b.x) + w.r + BUCKET_REACH, maxf(w.a.y, w.b.y) + w.r + BUCKET_REACH):
			_bucket_walls[bi].append(wi)
	for oi in obstacles.size():
		var ob: Dictionary = obstacles[oi]
		for bi in _buckets_in(ob.p.x - ob.r - BUCKET_REACH, ob.p.y - ob.r - BUCKET_REACH, ob.p.x + ob.r + BUCKET_REACH, ob.p.y + ob.r + BUCKET_REACH):
			_bucket_obs[bi].append(oi)

func _buckets_in(x0: float, y0: float, x1: float, y1: float) -> Array:
	var out := []
	var bx0 := clampi(int(floor((x0 + HALF_W) / BUCKET)), 0, _bw - 1)
	var by0 := clampi(int(floor((y0 + HALF_L) / BUCKET)), 0, _bh - 1)
	var bx1 := clampi(int(floor((x1 + HALF_W) / BUCKET)), 0, _bw - 1)
	var by1 := clampi(int(floor((y1 + HALF_L) / BUCKET)), 0, _bh - 1)
	for bx in range(bx0, bx1 + 1):
		for by in range(by0, by1 + 1):
			out.append(by * _bw + bx)
	return out

func _bucket(p: Vector2) -> int:
	return clampi(int(floor((p.y + HALF_L) / BUCKET)), 0, _bh - 1) * _bw + clampi(int(floor((p.x + HALF_W) / BUCKET)), 0, _bw - 1)

func _build_nav() -> void:
	nav.clear()
	for t in 2:
		var g := AStarGrid2D.new()
		g.region = Rect2i(0, 0, NAV_W, NAV_H)
		g.cell_size = Vector2(1, 1)
		g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		g.update()
		nav.append(g)
	# Stamp walls and obstacles into both grids by bounding box instead of testing every cell
	# against everything (the 52x104 field made the full scan ~1M distance checks).
	var solid := []
	for w in walls:
		solid.append_array(_cells_near_segment(w.a, w.b, w.r + UNIT_R * 0.9))
	for ob in obstacles:
		solid.append_array(_cells_near_segment(ob.p, ob.p, ob.r + UNIT_R * 0.8))
	for c in solid:
		for t in 2:
			(nav[t] as AStarGrid2D).set_point_solid(c, true)
	_gate_cells.clear()
	for g in gates:
		_gate_cells.append(_cells_near_segment(g.a, g.b, WALL_R + UNIT_R * 0.9))
	_update_gate_nav()

var _gate_cells: Array = []

func _update_gate_nav() -> void:
	# Own gates are free to walk through. Intact enemy gates are walkable but very expensive, so
	# a path uses one only when there is no other way in; the bot then has to break it.
	for gi in gates.size():
		var g: Dictionary = gates[gi]
		for c in _gate_cells[gi]:
			for t in 2:
				var grid: AStarGrid2D = nav[t]
				grid.set_point_solid(c, false)
				grid.set_point_weight_scale(c, 1.0 if (t == g.team or not gate_blocks(g)) else 60.0)
	nav_version += 1

func find_path(team: int, from: Vector2, to: Vector2) -> PackedVector2Array:
	var grid: AStarGrid2D = nav[team]
	var a := _free_cell(grid, nav_cell(from))
	var b := _free_cell(grid, nav_cell(to))
	var ids := grid.get_id_path(a, b, true)
	var out := PackedVector2Array()
	for i in range(1, ids.size()):
		out.append(nav_point(ids[i]))
	return out

func _free_cell(grid: AStarGrid2D, c: Vector2i) -> Vector2i:
	if not grid.is_point_solid(c):
		return c
	for r in range(1, 5):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var n := Vector2i(c.x + dx, c.y + dy)
				if grid.is_in_boundsv(n) and not grid.is_point_solid(n):
					return n
	return c

func gate_blocks(g: Dictionary) -> bool:
	return not g.broken and g.hp > 0.0

func _path_gate(u: Dictionary) -> Dictionary:
	# The intact enemy gate the bot's current path runs through within the next few steps, if any.
	var path: PackedVector2Array = u.path
	for i in range(u.path_i, mini(u.path_i + 5, path.size())):
		for g in gates:
			if g.team != u.team and gate_blocks(g) and path[i].distance_to(seg_closest(path[i], g.a, g.b)) < WALL_R + 0.6:
				return g
	return {}

# ---------- setup ----------
func setup(team_size: int, seed_value: int, player_team := 0) -> void:
	rng.seed = seed_value
	_build_map()
	_build_buckets()
	_build_nav()
	oracles = [_new_oracle(0), _new_oracle(1)]

	for t in 2:
		for cx in [-CATAPULT_X, CATAPULT_X]:
			catapults.append({"team":t, "p":_c(t, Vector2(cx, FRONT_Z + 0.3)), "t":rng.randf() * CATAPULT_EVERY})
	# One gatherer per team from 4 players up, two from 8.
	# 16 per team: 7 raiders (incl. the human), 3 escorts, 3 defenders, 3 workers. Smaller teams
	# take the first N slots.
	var roles := ["raid","gather","defend","raid","escort","raid","gather","defend","raid","escort","raid","gather","raid","defend","escort","raid"]
	for t in 2:
		for i in team_size:
			var human := t == player_team and i == 0
			var id := "you" if human else "%s%d" % ["b" if t == 0 else "r", i]
			var u := _new_unit(id, t, not human, roles[i % roles.size()])
			units.append(u)
			by_id[id] = u
			_respawn(u, true)

func _new_oracle(team: int, cakes := 0) -> Dictionary:
	return {"team":team, "state":"cell", "pos":cell(team), "carrier":"", "lifters":[], "carry_team":-1,
		"dropped_at":0.0, "tantrum_at":0.0, "cakes":cakes, "weight":mini(MAX_WEIGHT, cakes / CAKE_PER_STAGE)}

func _return_to_cell(t: int) -> void:
	# Returned / timed-out Oracles go back to the cell but keep everything they were fed.
	for id in oracles[t].lifters:
		var lu: Dictionary = by_id.get(id, {})
		if not lu.is_empty():
			lu.carrying = false
			lu.lifting = -1
	oracles[t] = _new_oracle(t, int(oracles[t].get("cakes", 0)))

func lifters_needed(o: Dictionary) -> int:
	return int(LIFTERS[clampi(int(o.weight), 0, LIFTERS.size() - 1)])

func _new_unit(id: String, team: int, bot: bool, role: String) -> Dictionary:
	return {"id":id,"team":team,"bot":bot,"role":role,"cls":"villager","up":false,"hp":60.0,"max_hp":60.0,
		"pos":Vector2.ZERO,"face":0.0,"move":Vector2.ZERO,"state":"idle","t":0.0,"atk":"","cd_dodge":0.0,
		"cd_ability":0.0,"stun":0.0,"carrying":false,"respawn_at":0.0,"kills":0,"deaths":0,"rescues":0,
		"dodge_dir":Vector2.ZERO,"target":"","forge":{"open":false,"faces":["fate","fate","fate"],"held":[false,false,false],
		"rolling":0.0,"rolled":false},"ai_goal":Vector2.ZERO,"lunge_hit":false,
		"unstick":0.0,"unstick_dir":Vector2.ZERO,"stuck_t":0.0,"last_pos":Vector2.ZERO,
		"lifting":-1, "load":{"kind":"", "n":0}, "task":{}, "workshop_open":false, "gathered":0, "repaired":0.0, "gate_dmg":0.0, "offering":false, "fed":0,
		"path":PackedVector2Array(), "path_i":0, "path_goal":Vector2(INF, INF), "path_at":-10.0, "path_ver":-1}

func armory_mult(team: int) -> float:
	return 1.0 + 0.12 * float(levels[team].armory)

func stat(u: Dictionary, key: String) -> Variant:
	var base: Variant = CLASSES[u.cls][key]
	if key in ["hp","dmg"]:
		var v := float(base) * (1.25 if u.up else 1.0)
		if u.cls != "villager" and u.cls != "worker":
			v *= armory_mult(u.team)
		return v
	return base

func class_label(u: Dictionary) -> String:
	return UPGRADE_NAME.get(u.cls,"") if u.up else str(CLASSES[u.cls].name)

func dice_count(team: int) -> int:
	return 3 + int(levels[team].forge)

func _respawn(u: Dictionary, first := false) -> void:
	var sp := spawn(u.team)
	u.pos = sp + Vector2(rng.randf_range(-8.0, 8.0), rng.randf_range(-1.5, 1.5))
	u.face = PI if u.team == 0 else 0.0
	u.max_hp = float(stat(u,"hp"))
	u.hp = u.max_hp
	u.state = "idle"
	u.t = 0.0
	u.stun = 0.0
	u.carrying = false
	u.lifting = -1
	u.forge.open = false
	u.workshop_open = false
	u.task = {}
	u.load = {"kind":"", "n":0}
	u.path = PackedVector2Array()
	if not first:
		_event("spawn", {"id":u.id})

func _event(kind: String, data: Dictionary) -> void:
	data["k"] = kind
	data["at"] = time
	events.append(data)
	if kind == "gate_hit":
		_note_gate_alarm(data)

func drain_events() -> Array:
	var out := events
	events = []
	return out

# ---------- helpers ----------
static func dir_of(angle: float) -> Vector2:
	# Facing angle uses the same convention as a Node3D's rotation.y looking down +z.
	return Vector2(sin(angle), cos(angle))

static func angle_of(v: Vector2) -> float:
	return atan2(v.x, v.y)

func alive(u: Dictionary) -> bool:
	return u.state != "dead"

func enemies_of(u: Dictionary) -> Array:
	return units.filter(func(o): return o.team != u.team and alive(o))

func nearest_enemy(u: Dictionary, max_d: float, prefer_front := false) -> Dictionary:
	var best := {}
	var best_score := INF
	var fwd := dir_of(u.face)
	for o in units:
		if o.team == u.team or not alive(o):
			continue
		var off: Vector2 = o.pos - u.pos
		var d := off.length()
		if d > max_d:
			continue
		var s := d
		if prefer_front and d > 0.01:
			s += (1.0 - fwd.dot(off / d)) * 2.0
		if s < best_score:
			best_score = s
			best = o
	return best

func oracle_carrier(team: int) -> Dictionary:
	# Lead lifter of this team's Oracle while her OWN team is carrying her home.
	var o: Dictionary = oracles[team]
	return by_id.get(o.carrier, {}) if o.state == "carried" and int(o.carry_team) == team else {}

func oracle_returner(team: int) -> Dictionary:
	# Lead lifter while the CAPTORS are carrying her back to their dungeon.
	var o: Dictionary = oracles[team]
	return by_id.get(o.carrier, {}) if o.state == "carried" and int(o.carry_team) != team else {}

func lifting_oracle(u: Dictionary) -> Dictionary:
	return oracles[int(u.lifting)] if int(u.get("lifting", -1)) >= 0 else {}

func _liftable(u: Dictionary) -> Dictionary:
	# The Oracle this unit could start lifting or join right now, if any.
	if u.carrying or u.offering or u.load.n > 0:
		return {}
	for o in oracles:
		if u.pos.distance_to(o.pos) > PICKUP_RADIUS + (LIFT_RING if o.state == "carried" else 0.0):
			continue
		if o.state == "cell" and int(o.team) == u.team:
			return o                                   # rescue her from the enemy dungeon
		if o.state == "dropped":
			return o                                   # either side may pick her up
		if o.state == "carried" and int(o.carry_team) == u.team and o.lifters.size() < LIFTERS[LIFTERS.size() - 1]:
			return o                                   # join the lift
	return {}

# ---------- input (from HUD or bot brain) ----------
func act(id: String, action: String, arg: Variant = null) -> bool:
	var u: Dictionary = by_id.get(id, {})
	if u.is_empty() or ended or not alive(u):
		return false
	match action:
		"attack": return _start_attack(u, "attack")
		"ability": return _start_attack(u, "ability")
		"dodge": return _dodge(u)
		"interact": return _interact(u)
		"forge_roll": return _forge_roll(u, arg)
		"forge_take": return _forge_take(u)
		"forge_leave":
			u.forge.open = false
			return true
		"take_tools": return _take_tools(u)
		"buy": return buy_upgrade(u.team, str(arg), u)
		"workshop_leave":
			u.workshop_open = false
			return true
	return false

func set_move(id: String, v: Vector2) -> void:
	var u: Dictionary = by_id.get(id, {})
	if not u.is_empty():
		u.move = v.limit_length(1.0)
		# Walking away cancels a gather/repair task.
		if not u.bot and v.length() > 0.35 and not u.task.is_empty():
			u.task = {}

func can_act(u: Dictionary) -> bool:
	return alive(u) and u.stun <= 0.0 and u.state in ["idle","move"] and not u.forge.open and not u.workshop_open

func _aim(u: Dictionary, reach: float) -> void:
	var target := nearest_enemy(u, reach, true)
	if not target.is_empty():
		u.face = angle_of(target.pos - u.pos)

func _start_attack(u: Dictionary, kind: String, aim := true) -> bool:
	if not can_act(u) or u.carrying or u.offering:
		return false
	if kind == "ability":
		if CLASSES[u.cls].ability == "" or u.cd_ability > 0.0:
			return false
		u.cd_ability = float(CLASSES[u.cls].ab_cd)
	var reach := float(stat(u,"range")) * (1.0 if CLASSES[u.cls].ranged else 1.9)
	if kind == "ability" and CLASSES[u.cls].ability == "lunge":
		reach = 6.0
	if aim:
		_aim(u, reach)
	u.task = {}
	u.state = "wind"
	u.atk = kind
	u.t = float(stat(u,"windup")) * (1.3 if kind == "ability" else 1.0)
	u.lunge_hit = false
	_event("attack", {"id":u.id,"kind":kind,"ability":CLASSES[u.cls].ability if kind == "ability" else ""})
	return true

func _dodge(u: Dictionary) -> bool:
	if not alive(u) or u.stun > 0.0 or u.carrying or u.cd_dodge > 0.0 or u.state in ["wind","dodge"] or u.forge.open or u.workshop_open:
		return false
	var d: Vector2 = u.move if u.move.length() > 0.2 else dir_of(u.face)
	u.dodge_dir = d.normalized()
	u.face = angle_of(u.dodge_dir)
	u.state = "dodge"
	u.t = 0.3
	u.cd_dodge = 2.2
	u.task = {}
	_event("dodge", {"id":u.id})
	return true

func near_node(u: Dictionary) -> Dictionary:
	var best := {}
	var best_d := INF
	for n in nodes:
		var d: float = u.pos.distance_to(n.p) - n.r
		if d < 1.3 and n.amount > 0 and d < best_d:
			best = n
			best_d = d
	return best

func repair_stock(team: int) -> int:
	return int(stock[team].wood) + int(stock[team].stone)

func near_repair_gate(u: Dictionary) -> Dictionary:
	for g in gates:
		if g.team == u.team and g.hp < g.max_hp and u.pos.distance_to(seg_closest(u.pos, g.a, g.b)) < 3.2:
			return g
	return {}

func _interact(u: Dictionary) -> bool:
	if u.stun > 0.0 or not u.state in ["idle","move"]:
		return false
	if u.carrying:
		var ho := lifting_oracle(u)
		_leave_lift(u, not ho.is_empty() and ho.lifters.size() == 1 and lifters_needed(ho) == 1)
		return true
	if _offering_action(u) != "":
		return _do_offering(u)
	var lo := _liftable(u)
	if not lo.is_empty():
		_join_lift(u, lo)
		return true
	if u.cls == "worker" and not ladder_spot(u).is_empty() and u.load.n == 0:
		u.task = {"kind":"build_ladder", "t":LADDER_BUILD}
		return true
	if u.cls == "worker":
		var g := near_repair_gate(u)
		if not g.is_empty() and repair_stock(u.team) > 0:
			u.task = {"kind":"repair", "gate":g.id, "t":REPAIR_TICK}
			return true
		var n := near_node(u)
		if not n.is_empty() and (u.load.n == 0 or u.load.kind == n.kind) and u.load.n < CARRY_MAX:
			u.task = {"kind":"gather", "node":n.id, "t":GATHER_TIME}
			u.face = angle_of(n.p - u.pos)
			return true
	if u.pos.distance_to(forge(u.team)) <= FORGE_RADIUS:
		u.forge.open = true
		u.forge.rolled = false
		u.forge.held = []
		for i in dice_count(u.team):
			u.forge.held.append(false)
		return true
	if u.pos.distance_to(workshop(u.team)) <= WORKSHOP_RADIUS:
		u.workshop_open = true
		return true
	return false

func ladder_spot(u: Dictionary) -> Dictionary:
	# Where a worker could raise a ladder: an enemy front-wall piece right in front of them.
	if u.cls != "worker" or stock[u.team].wood < LADDER_COST:
		return {}
	for wi in walls.size():
		var w: Dictionary = walls[wi]
		if w.kind != "wall" or int(w.team) == u.team:
			continue
		var cp: Vector2 = seg_closest(u.pos, w.a, w.b)
		if u.pos.distance_to(cp) > w.r + UNIT_R + 0.5 or absf(cp.x) > HALF_W - 1.0:
			continue
		# Not on top of a gate, and not doubling up on an existing ladder.
		var ok := true
		for g in gates:
			if cp.distance_to(g.c) < GATE_HALF + 1.6:
				ok = false
		for l in ladders:
			if int(l.wall) == wi and cp.distance_to(l.p) < LADDER_HALF * 2.5:
				ok = false
		if ok:
			return {"wall":wi, "p":cp}
	return {}

func _raise_ladder(u: Dictionary, spot: Dictionary) -> void:
	stock[u.team].wood -= LADDER_COST
	var l := {"id":_next_ladder, "team":u.team, "wall":int(spot.wall), "p":spot.p, "hp":LADDER_HP, "cells":[]}
	_next_ladder += 1
	# Open the passage on the owner's nav grid (walkable but costly).
	var grid: AStarGrid2D = nav[u.team]
	var w: Dictionary = walls[int(spot.wall)]
	for x in NAV_W:
		for y in NAV_H:
			var c := Vector2i(x, y)
			var np := nav_point(c)
			var along: Vector2 = seg_closest(np, w.a, w.b)
			if along.distance_to(l.p) <= LADDER_HALF and np.distance_to(along) <= w.r + UNIT_R + 0.6 and grid.is_point_solid(c):
				grid.set_point_solid(c, false)
				grid.set_point_weight_scale(c, 4.0)
				l.cells.append(c)
	ladders.append(l)
	nav_version += 1
	_event("ladder_up", {"id":u.id, "team":u.team, "ladder":l.id, "pos":l.p})

func _damage_ladder(src: Dictionary, l: Dictionary, amount: float) -> void:
	l.hp -= amount
	_event("ladder_hit", {"ladder":l.id, "team":l.team, "dmg":int(round(amount))})
	if l.hp <= 0.0:
		var grid: AStarGrid2D = nav[int(l.team)]
		for c in l.cells:
			grid.set_point_solid(c, true)
		ladders.erase(l)
		nav_version += 1
		_event("ladder_down", {"ladder":l.id, "team":l.team, "pos":l.p, "by":src.get("id","")})

func near_cake(u: Dictionary) -> Dictionary:
	for ct in cake_trees:
		if ct.ready and u.pos.distance_to(ct.p) <= 1.9:
			return ct
	return {}

func _offering_action(u: Dictionary) -> String:
	if u.carrying:
		return ""
	if u.offering:
		var captive: Dictionary = oracles[1 - u.team]
		if captive.state == "cell" and u.pos.distance_to(captive.pos) <= FEED_RADIUS and int(captive.cakes) < MAX_WEIGHT * CAKE_PER_STAGE:
			return "feed"
		return ""
	if u.load.n == 0 and not near_cake(u).is_empty():
		return "cake"
	return ""

func _do_offering(u: Dictionary) -> bool:
	match _offering_action(u):
		"cake":
			var ct := near_cake(u)
			ct.ready = false
			ct.t = 0.0
			u.offering = true
			u.task = {}
			_event("offering_taken", {"id":u.id, "team":u.team, "tree":ct.id})
			return true
		"feed":
			var captive: Dictionary = oracles[1 - u.team]
			var before: int = captive.weight
			captive.cakes = int(captive.cakes) + 1
			captive.weight = mini(MAX_WEIGHT, int(captive.cakes) / CAKE_PER_STAGE)
			u.offering = false
			u.fed += 1
			_event("fed", {"id":u.id, "team":1 - u.team, "weight":int(captive.weight), "cakes":int(captive.cakes),
				"stage_up":int(captive.weight) > before, "need":lifters_needed(captive)})
			return true
	return false

func context_action(u: Dictionary) -> String:
	# What the ACTION button does right now, for the HUD label.
	if not alive(u):
		return ""
	if u.carrying:
		var ho := lifting_oracle(u)
		return "throw" if (not ho.is_empty() and ho.lifters.size() == 1 and lifters_needed(ho) == 1) else "letgo"
	var off := _offering_action(u)
	if off != "":
		return off
	var lo := _liftable(u)
	if not lo.is_empty():
		return "join" if lo.state == "carried" else "grab"
	if u.cls == "worker":
		if not u.task.is_empty():
			return str(u.task.kind)
		if not ladder_spot(u).is_empty() and u.load.n == 0:
			return "ladder"
		if not near_repair_gate(u).is_empty() and repair_stock(u.team) > 0:
			return "repair"
		var n := near_node(u)
		if not n.is_empty() and (u.load.n == 0 or u.load.kind == n.kind) and u.load.n < CARRY_MAX:
			return "chop" if n.kind == "wood" else "mine"
	if u.pos.distance_to(forge(u.team)) <= FORGE_RADIUS:
		return "forge"
	if u.pos.distance_to(workshop(u.team)) <= WORKSHOP_RADIUS:
		return "workshop"
	return ""

# ---------- forge dice ----------
func _forge_roll(u: Dictionary, held: Variant) -> bool:
	var f: Dictionary = u.forge
	if not f.open or f.rolling > 0.0 or u.pos.distance_to(forge(u.team)) > FORGE_RADIUS + 0.6:
		return false
	var n := dice_count(u.team)
	while f.faces.size() < n:
		f.faces.append("fate")
	while f.held.size() < n:
		f.held.append(false)
	for i in n:
		f.held[i] = bool(held[i]) if (held is Array and f.rolled and i < held.size()) else false
	for i in n:
		if not f.held[i]:
			f.faces[i] = FACES[rng.randi() % FACES.size()]
	f.rolling = ROLL_TIME
	f.rolled = true
	u.state = "idle"
	_event("forge_roll", {"id":u.id,"faces":f.faces.duplicate()})
	return true

static func forge_result(faces: Array) -> Dictionary:
	# Pair of a class (fate faces are wild) grants it; three of a kind grants the upgraded form.
	var wild := faces.count("fate")
	var best := ""
	var best_n := 0
	for c in ["knight","barbarian","rogue","ranger","mage"]:
		var n: int = faces.count(c)
		if n > best_n:
			best_n = n
			best = c
	if best == "":
		return {"cls":"", "up":false, "n":wild}
	var total := best_n + wild
	return {"cls":best if total >= 2 else "", "up":total >= 3, "n":total}

func _forge_take(u: Dictionary) -> bool:
	var f: Dictionary = u.forge
	if not f.open or f.rolling > 0.0 or not f.rolled:
		return false
	var r := forge_result(f.faces)
	if r.cls == "" and f.faces.count("fate") == f.faces.size():
		r = {"cls":FACES[rng.randi() % 5], "up":true}
	if r.cls == "":
		return false
	_set_class(u, r.cls, r.up)
	f.open = false
	return true

func _set_class(u: Dictionary, cls: String, up: bool) -> void:
	var ratio: float = u.hp / maxf(1.0, u.max_hp)
	u.cls = cls
	u.up = up
	u.max_hp = float(stat(u,"hp"))
	u.hp = maxf(1.0, u.max_hp * maxf(ratio, 0.75))
	u.cd_ability = 0.0
	u.task = {}
	if cls != "worker":
		u.load = {"kind":"", "n":0}
	_event("class", {"id":u.id,"cls":u.cls,"up":u.up})

# ---------- workshop: tools and team upgrades ----------
func _take_tools(u: Dictionary) -> bool:
	if u.pos.distance_to(workshop(u.team)) > WORKSHOP_RADIUS + 0.6 or u.carrying:
		return false
	_set_class(u, "worker", false)
	u.workshop_open = false
	return true

func upgrade_cost(team: int, id: String) -> Dictionary:
	var up: Dictionary = UPGRADES[id]
	var lvl: int = levels[team][id]
	return {} if lvl >= int(up.max) else up.cost[lvl]

func can_buy(team: int, id: String) -> bool:
	var cost := upgrade_cost(team, id)
	return not cost.is_empty() and stock[team].wood >= int(cost.wood) and stock[team].stone >= int(cost.stone)

func buy_upgrade(team: int, id: String, by: Dictionary = {}) -> bool:
	if not UPGRADES.has(id) or not can_buy(team, id):
		return false
	var cost := upgrade_cost(team, id)
	stock[team].wood -= int(cost.wood)
	stock[team].stone -= int(cost.stone)
	levels[team][id] += 1
	match id:
		"gates":
			for g in gates:
				if g.team == team:
					g.max_hp = GATE_HP * (1.0 + 0.5 * float(levels[team].gates))
					g.hp = minf(g.max_hp, g.hp + g.max_hp * 0.5)
					if g.broken and g.hp >= g.max_hp * GATE_SOLID_AT:
						g.broken = false
			_update_gate_nav()
		"armory":
			for u in units:
				if u.team == team and alive(u):
					var ratio: float = u.hp / maxf(1.0, u.max_hp)
					u.max_hp = float(stat(u, "hp"))
					u.hp = u.max_hp * ratio
	_event("upgrade", {"team":team, "upgrade":id, "level":levels[team][id], "id":by.get("id", "")})
	return true

func _deliver(u: Dictionary) -> void:
	if u.load.n <= 0 or u.pos.distance_to(workshop(u.team)) > WORKSHOP_RADIUS + 0.4:
		return
	stock[u.team][u.load.kind] += u.load.n
	u.gathered += u.load.n
	_event("deliver", {"id":u.id, "team":u.team, "kind":u.load.kind, "n":u.load.n})
	u.load = {"kind":"", "n":0}

# ---------- damage ----------
func _damage(src: Dictionary, dst: Dictionary, amount: float, stun := 0.0) -> void:
	if not alive(dst) or dst.state == "dodge":
		return
	dst.hp -= amount
	if stun > 0.0:
		dst.stun = maxf(dst.stun, stun)
	dst.task = {}
	_event("hit", {"id":dst.id,"by":src.get("id",""),"dmg":int(round(amount))})
	if dst.hp <= 0.0:
		_kill(src, dst)

func _kill(src: Dictionary, dst: Dictionary) -> void:
	if dst.carrying:
		_leave_lift(dst, false)
	dst.hp = 0.0
	dst.state = "dead"
	dst.forge.open = false
	dst.workshop_open = false
	dst.task = {}
	dst.load = {"kind":"", "n":0}
	dst.offering = false
	dst.respawn_at = time + RESPAWN_TIME
	dst.deaths += 1
	if not src.is_empty() and src.has("team"):
		kills[src.team] += 1
		if src.has("kills"):
			src.kills += 1
	_event("death", {"id":dst.id,"by":src.get("id","")})

func _damage_gate(src: Dictionary, g: Dictionary, amount: float) -> void:
	if not gate_blocks(g):
		return
	g.hp = maxf(0.0, g.hp - amount)
	g["hit_at"] = time
	if src.has("gate_dmg"):
		src.gate_dmg += amount
	_event("gate_hit", {"gate":g.id, "team":g.team, "by":src.get("id",""), "dmg":int(round(amount))})
	if g.hp <= 0.0:
		g.broken = true
		g["broken_at"] = time
		_update_gate_nav()
		_event("gate_broken", {"gate":g.id, "team":g.team, "by":src.get("id","")})

func _join_lift(u: Dictionary, o: Dictionary) -> void:
	var t: int = o.team
	if o.state != "carried":
		o.state = "carried"
		o.carry_team = u.team
		o.lifters = []
		_event("pickup", {"id":u.id, "team":t, "carry_team":u.team})
	# A human who joins takes the lead so the player steers the group.
	if not u.bot:
		o.lifters.push_front(u.id)
	else:
		o.lifters.append(u.id)
	o.carrier = o.lifters[0]
	u.carrying = true
	u.lifting = t
	u.forge.open = false
	u.workshop_open = false
	u.task = {}
	_event("lift_join", {"id":u.id, "team":t, "n":o.lifters.size(), "need":lifters_needed(o)})

func _leave_lift(u: Dictionary, thrown: bool) -> void:
	var o := lifting_oracle(u)
	u.carrying = false
	u.lifting = -1
	if o.is_empty():
		return
	o.lifters.erase(u.id)
	if not o.lifters.is_empty():
		o.carrier = o.lifters[0]
		_event("lift_leave", {"id":u.id, "team":o.team, "n":o.lifters.size(), "need":lifters_needed(o)})
		return
	_drop_oracle(o, u, thrown)

func _drop_oracle(o: Dictionary, u: Dictionary, thrown: bool) -> void:
	for id in o.lifters:
		var lu: Dictionary = by_id.get(id, {})
		if not lu.is_empty():
			lu.carrying = false
			lu.lifting = -1
	o.state = "dropped"
	o.carrier = ""
	o.lifters = []
	o.carry_team = -1
	o.dropped_at = time
	o.tantrum_at = time
	var p: Vector2 = o.pos if u.is_empty() else u.pos
	if thrown and not u.is_empty():
		var to: Vector2 = u.pos + dir_of(u.face) * 4.5
		# Don't throw her through a wall: stop at the last clear point.
		p = u.pos
		for i in range(1, 10):
			var q: Vector2 = u.pos.lerp(to, float(i) / 9.0)
			if _blocked_point(q, u.team, 0.4):
				break
			p = q
	o.pos = _clamp_to_field(_push_out(p, 0.6, int(o.team)))
	_event("drop", {"team":o.team, "thrown":thrown, "id":u.get("id", "")})
func _melee(u: Dictionary, reach: float, arc: float, dmg: float, stun := 0.0) -> int:
	var fwd := dir_of(u.face)
	var hits := 0
	for o in units:
		if o.team == u.team or not alive(o):
			continue
		var off: Vector2 = o.pos - u.pos
		var d := off.length()
		if d > reach + UNIT_R:
			continue
		if arc > -1.0 and d > 0.3 and fwd.dot(off / d) < arc:
			continue
		_damage(u, o, dmg, stun)
		hits += 1
	# Swings knock at enemy ladders in reach.
	for l in ladders.duplicate():
		if int(l.team) == u.team:
			continue
		var offl: Vector2 = l.p - u.pos
		if offl.length() <= reach + LADDER_HALF and (arc <= -1.0 or offl.length() < 0.3 or fwd.dot(offl.normalized()) >= arc - 0.3):
			_damage_ladder(u, l, dmg)
			hits += 1
	# Swings also land on an enemy gate in reach.
	for g in gates:
		if g.team == u.team or not gate_blocks(g):
			continue
		var cp := seg_closest(u.pos, g.a, g.b)
		var off2: Vector2 = cp - u.pos
		var d2 := off2.length()
		if d2 > reach + WALL_R + 0.3:
			continue
		if arc > -1.0 and d2 > 0.3 and fwd.dot(off2 / d2) < arc - 0.2:
			continue
		_damage_gate(u, g, dmg * float(CLASSES[u.cls].gate))
		hits += 1
	return hits

func _shoot(u: Dictionary, angle: float, dmg: float, aoe: float, speed: float, reach: float) -> void:
	var d := dir_of(angle)
	projectiles.append({"id":_next_proj,"team":u.team,"owner":u.id,"pos":u.pos + d*0.6,"vel":d*speed,
		"dmg":dmg,"aoe":aoe,"life":reach/speed,"kind":"fire" if aoe > 0.0 else "arrow",
		"gate_mult":float(CLASSES[u.cls].gate)})
	_event("proj", {"pid":_next_proj,"kind":"fire" if aoe > 0.0 else "arrow"})
	_next_proj += 1

func _resolve_attack(u: Dictionary) -> void:
	var c: Dictionary = CLASSES[u.cls]
	var dmg := float(stat(u,"dmg"))
	if u.atk == "attack":
		if c.ranged:
			_shoot(u, u.face, dmg, float(c.aoe), float(c.proj_speed), float(c.range))
		else:
			_melee(u, float(c.range), float(c.arc), dmg)
		return
	match str(c.ability):
		"bash":
			_melee(u, 2.3, 0.3, dmg*0.7, 1.3)
		"spin":
			_melee(u, 2.8, -2.0, dmg*1.15)
		"volley":
			for i in 5:
				_shoot(u, u.face + (i-2)*0.13, dmg*0.8, 0.0, float(c.proj_speed), float(c.range))
		"nova":
			_melee(u, 3.3, -2.0, dmg*1.4)
			_event("nova", {"id":u.id})

# ---------- stepping ----------
var profile := false          # tests only: accumulate microseconds per phase in `prof`
var prof := {}

func _p(key: String, t0: int) -> int:
	var now := Time.get_ticks_usec()
	prof[key] = int(prof.get(key, 0)) + (now - t0)
	return now

func step(dt: float = TICK) -> void:
	if ended:
		return
	time += dt
	_ai_clock += dt
	_cmd_clock += dt
	var t0 := Time.get_ticks_usec() if profile else 0
	if _ai_clock >= 0.15:
		_ai_clock = 0.0
		for u in units:
			if u.bot:
				_think(u)
	if profile: t0 = _p("think", t0)
	if _cmd_clock >= 2.0:
		_cmd_clock = 0.0
		for t in 2:
			_commander(t)
	for u in units:
		_step_unit(u, dt)
	if profile: t0 = _p("units", t0)
	_separate()
	if profile: t0 = _p("separate", t0)
	_step_projectiles(dt)
	if profile: t0 = _p("projectiles", t0)
	_step_oracles(dt)
	_step_world(dt)
	if profile: t0 = _p("world", t0)
	if time >= MATCH_TIME:
		_finish("time")

func _step_unit(u: Dictionary, dt: float) -> void:
	if u.state == "dead":
		if time >= u.respawn_at:
			_respawn(u)
		return
	u.cd_dodge = maxf(0.0, u.cd_dodge - dt)
	u.cd_ability = maxf(0.0, u.cd_ability - dt)
	var f: Dictionary = u.forge
	if f.rolling > 0.0:
		f.rolling = maxf(0.0, f.rolling - dt)
	if f.open and u.pos.distance_to(forge(u.team)) > FORGE_RADIUS + 0.8:
		f.open = false
	if u.workshop_open and u.pos.distance_to(workshop(u.team)) > WORKSHOP_RADIUS + 0.8:
		u.workshop_open = false
	if u.load.n > 0:
		_deliver(u)
	if u.stun > 0.0:
		u.stun -= dt
		return
	var speed := float(stat(u,"speed"))
	match u.state:
		"wind":
			u.t -= dt
			if CLASSES[u.cls].ability == "lunge" and u.atk == "ability":
				u.pos += dir_of(u.face) * 15.0 * dt
				if not u.lunge_hit:
					var hit := _melee(u, 1.1, 0.2, float(stat(u,"dmg"))*2.0)
					u.lunge_hit = hit > 0
			if u.t <= 0.0:
				if not (CLASSES[u.cls].ability == "lunge" and u.atk == "ability"):
					_resolve_attack(u)
				u.state = "recover"
				u.t = float(stat(u,"recover"))
			return
		"recover":
			u.t -= dt
			u.pos += u.move * speed * 0.25 * dt
			if u.t <= 0.0:
				u.state = "idle"
			return
		"dodge":
			u.t -= dt
			u.pos += u.dodge_dir * 13.0 * dt
			if u.t <= 0.0:
				u.state = "idle"
			return
	if f.open or u.workshop_open:
		u.state = "idle"
		return
	if not u.task.is_empty():
		_step_task(u, dt)
		return
	var mult := float(CLASSES[u.cls].carry) if u.carrying else 1.0
	if u.carrying:
		var ho := lifting_oracle(u)
		if ho.is_empty() or ho.carrier != u.id:
			# Followers hold her from the ring; _step_oracles places them. No steering of their own.
			u.state = "lift"
			return
		# Extra hands beyond the minimum speed the carry up, to full walking speed at most.
		var extra: int = ho.lifters.size() - lifters_needed(ho)
		if extra > 0:
			mult = minf(1.0, mult + EXTRA_LIFTER * float(extra))
		mult *= 1.0 - WEIGHT_SLOW * float(ho.weight)
		# Not enough hands: she won't budge.
		if ho.lifters.size() < lifters_needed(ho):
			mult = 0.0
	if u.offering:
		mult = minf(mult, 0.9)
	if not ladders.is_empty() and ladder_climb(u):
		mult *= LADDER_CLIMB
	if u.load.n > 0:
		mult = minf(mult, 0.85)
	if u.move.length() > 0.08:
		u.pos += u.move * speed * mult * dt
		u.face = lerp_angle(u.face, angle_of(u.move), minf(1.0, dt*14.0))
		u.state = "move"
	else:
		u.state = "idle"

func _step_task(u: Dictionary, dt: float) -> void:
	var task: Dictionary = u.task
	u.state = str(task.kind)
	task.t -= dt
	if task.t > 0.0:
		return
	match str(task.kind):
		"gather":
			var n: Dictionary = nodes[int(task.node)]
			if n.amount <= 0 or u.load.n >= CARRY_MAX or u.pos.distance_to(n.p) - n.r > 1.6:
				u.task = {}
				u.state = "idle"
				return
			n.amount -= 1
			u.load = {"kind":n.kind, "n":u.load.n + 1}
			_event("gather", {"id":u.id, "node":n.id, "kind":n.kind, "n":u.load.n})
			task.t = GATHER_TIME
			if u.load.n >= CARRY_MAX or n.amount <= 0:
				u.task = {}
				u.state = "idle"
		"build_ladder":
			var spot := ladder_spot(u)
			if not spot.is_empty():
				_raise_ladder(u, spot)
			u.task = {}
			u.state = "idle"
		"repair":
			var g: Dictionary = gates[int(task.gate)]
			if g.hp >= g.max_hp or repair_stock(u.team) <= 0 or u.pos.distance_to(seg_closest(u.pos, g.a, g.b)) > 3.6:
				u.task = {}
				u.state = "idle"
				return
			# Under attack: workers can't out-heal an assault; they wait until it lets up.
			if time - float(g.get("hit_at", -100.0)) < REPAIR_LOCK:
				task.t = REPAIR_TICK
				return
			# Rubble: a broken gate stays down for a while, and can't be rebuilt with enemies in it.
			if g.broken and (time - float(g.get("broken_at", -100.0)) < RUBBLE_TIME or _enemy_near(g.c, int(g.team), RUBBLE_CLEAR)):
				task.t = REPAIR_TICK
				return
			# One unit of material (whichever the team has more of) buys three repair ticks.
			task["paid"] = int(task.get("paid", 0)) + 1
			if int(task.paid) % 3 == 1:
				var mat := "wood" if stock[u.team].wood >= stock[u.team].stone else "stone"
				stock[u.team][mat] -= 1
			var was_broken: bool = g.broken
			g.hp = minf(g.max_hp, g.hp + REPAIR_HP)
			u.repaired += REPAIR_HP
			if was_broken and g.hp >= g.max_hp * GATE_SOLID_AT:
				g.broken = false
				_update_gate_nav()
				_event("gate_rebuilt", {"gate":g.id, "team":g.team, "id":u.id})
			_event("repair", {"gate":g.id, "id":u.id})
			task.t = REPAIR_TICK

func _blocked_point(p: Vector2, team: int, r: float) -> bool:
	for wi in _bucket_walls[_bucket(p)]:
		var w: Dictionary = walls[wi]
		if p.distance_to(seg_closest(p, w.a, w.b)) < w.r + r:
			return true
	for g in gates:
		if g.team != team and gate_blocks(g) and p.distance_to(seg_closest(p, g.a, g.b)) < WALL_R + r:
			return true
	return false

func _push_out(p: Vector2, r: float, team := -1) -> Vector2:
	var bi := _bucket(p)
	for oi in _bucket_obs[bi]:
		var ob: Dictionary = obstacles[oi]
		var off: Vector2 = p - ob.p
		var min_d: float = ob.r + r
		var d := off.length()
		if d < min_d:
			p = ob.p + (off / d if d > 0.001 else Vector2(1,0)) * min_d
	for wi in _bucket_walls[bi]:
		var w: Dictionary = walls[wi]
		if team >= 0 and w.kind == "wall" and not ladders.is_empty() and on_ladder(p, wi, team):
			continue
		p = _push_seg(p, w.a, w.b, w.r + r)
	for g in gates:
		# Gates only stop the other team, and only while standing.
		if team != g.team and gate_blocks(g):
			p = _push_seg(p, g.a, g.b, WALL_R + r)
	return p

func on_ladder(p: Vector2, wall_index: int, team: int) -> bool:
	# Inside a ladder passage over this wall, for the ladder's own team.
	for l in ladders:
		if int(l.team) == team and int(l.wall) == wall_index:
			var w: Dictionary = walls[wall_index]
			var along: Vector2 = seg_closest(p, w.a, w.b)
			if along.distance_to(l.p) <= LADDER_HALF and p.distance_to(along) <= w.r + UNIT_R + 0.6:
				return true
	return false

func ladder_climb(u: Dictionary) -> bool:
	for l in ladders:
		if int(l.team) == u.team and u.pos.distance_to(l.p) <= LADDER_HALF + 0.8:
			return true
	return false

func _hands_near(p: Vector2, team: int, r: float) -> int:
	var n := 0
	for o in units:
		if o.team == team and alive(o) and not o.carrying and o.pos.distance_to(p) <= r:
			n += 1
	return n

func _enemy_near(p: Vector2, team: int, r: float) -> bool:
	for o in units:
		if o.team != team and alive(o) and o.pos.distance_to(p) <= r:
			return true
	return false

func _knockback(u: Dictionary, push: Vector2) -> void:
	# Knockbacks run after collision for the tick, so move in short steps and stop at the first
	# wall; a 4 m shove in one go ended units inside (or through) a 2 m wall.
	var steps := maxi(1, int(ceil(push.length() / 0.25)))
	var p: Vector2 = u.pos
	for i in steps:
		var q: Vector2 = _clamp_to_field(p + push / float(steps))
		if _blocked_point(q, int(u.team), UNIT_R):
			break
		p = q
	u.pos = _clamp_to_field(_push_out(p, UNIT_R, int(u.team)))

func _push_seg(p: Vector2, a: Vector2, b: Vector2, min_d: float) -> Vector2:
	var cp := seg_closest(p, a, b)
	var off := p - cp
	var d := off.length()
	if d >= min_d:
		return p
	if d < 0.001:
		# Exactly on the line: push along the wall normal.
		var n := Vector2(-(b - a).y, (b - a).x).normalized()
		return cp + n * min_d
	return cp + off / d * min_d

func _clamp_to_field(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, -HALF_W, HALF_W), clampf(p.y, -HALF_L, HALF_L))

func _separate() -> void:
	for i in units.size():
		var a: Dictionary = units[i]
		if not alive(a):
			continue
		for j in range(i+1, units.size()):
			var b: Dictionary = units[j]
			if not alive(b):
				continue
			var off: Vector2 = b.pos - a.pos
			var d := off.length()
			if d < UNIT_R*2.0 and d > 0.0001:
				var push := off / d * (UNIT_R*2.0 - d) * 0.5
				a.pos -= push
				b.pos += push
	for u in units:
		if alive(u):
			# Clamp first: pushing a unit that is slightly past the field edge off a wall end can
			# send it diagonally, and clamping afterwards drops it back inside the wall.
			u.pos = _clamp_to_field(_push_out(_clamp_to_field(u.pos), UNIT_R, u.team))

func _step_projectiles(dt: float) -> void:
	for i in range(projectiles.size()-1, -1, -1):
		var p: Dictionary = projectiles[i]
		p.pos += p.vel * dt
		p.life -= dt
		var hit := {}
		for o in units:
			if o.team != p.team and alive(o) and o.pos.distance_to(p.pos) < UNIT_R + 0.25:
				hit = o
				break
		var blocked := false
		var hit_gate := {}
		var pb := _bucket(p.pos)
		for oi in _bucket_obs[pb]:
			var ob: Dictionary = obstacles[oi]
			if p.pos.distance_to(ob.p) < ob.r:
				blocked = true
				break
		if not blocked:
			for wi in _bucket_walls[pb]:
				var w: Dictionary = walls[wi]
				if w.kind in ["ledge", "bars"]:
					continue   # low ledges and cell bars don't stop arrows or fire
				if p.pos.distance_to(seg_closest(p.pos, w.a, w.b)) < w.r * 0.8:
					blocked = true
					break
		if not blocked:
			for g in gates:
				if g.team != p.team and gate_blocks(g) and p.pos.distance_to(seg_closest(p.pos, g.a, g.b)) < WALL_R * 0.8:
					hit_gate = g
					blocked = true
					break
		if hit.is_empty() and not blocked and p.life > 0.0 and absf(p.pos.x) < HALF_W + 2 and absf(p.pos.y) < HALF_L + 2:
			continue
		var owner: Dictionary = by_id.get(p.owner, {"team":p.team})
		if not hit_gate.is_empty():
			_damage_gate(owner, hit_gate, p.dmg * float(p.gate_mult))
		if p.aoe > 0.0:
			for o in units:
				if o.team != p.team and alive(o) and o.pos.distance_to(p.pos) <= p.aoe:
					_damage(owner, o, p.dmg * (1.0 if o == hit else 0.6))
			_event("boom", {"pos":p.pos})
		elif not hit.is_empty():
			_damage(owner, hit, p.dmg)
		_event("proj_end", {"pid":p.id})
		projectiles.remove_at(i)

func _step_oracles(dt: float) -> void:
	for t in 2:
		var o: Dictionary = oracles[t]
		match o.state:
			"carried":
				# Blessing: while her own team carries her, she heals them and their escort.
				if int(o.carry_team) == t:
					for u in units:
						if u.team == t and alive(u) and u.hp < u.max_hp and u.pos.distance_to(o.pos) <= BLESS_R:
							u.hp = minf(u.max_hp, u.hp + HEAL_RATE * dt)
				# Drop lifters who died or let go; promote the next one if the lead is gone.
				var keep := []
				for id in o.lifters:
					var lu: Dictionary = by_id.get(id, {})
					if not lu.is_empty() and alive(lu) and lu.carrying and int(lu.lifting) == t:
						keep.append(id)
				o.lifters = keep
				if o.lifters.is_empty():
					_drop_oracle(o, {}, false)
					continue
				o.carrier = o.lifters[0]
				var lead: Dictionary = by_id[o.carrier]
				o.pos = lead.pos
				# Followers hold her from a ring around the lead lifter.
				for i in range(1, o.lifters.size()):
					var f: Dictionary = by_id[o.lifters[i]]
					var ang: float = lead.face + TAU * float(i) / float(o.lifters.size())
					# Placed after the collision pass, so resolve walls here (the ring can overlap
					# cell bars, ledges and doorways).
					f.pos = _clamp_to_field(_push_out(_clamp_to_field(lead.pos + dir_of(ang) * LIFT_RING), UNIT_R, f.team))
					f.face = lead.face
				if int(o.carry_team) == t:
					if lead.pos.distance_to(throne(t)) <= THRONE_RADIUS:
						score[t] += 1
						for id in o.lifters:
							var ru: Dictionary = by_id[id]
							ru.rescues += 1
							ru.carrying = false
							ru.lifting = -1
						_event("rescue", {"team":t, "id":lead.id, "n":o.lifters.size()})
						oracles[t] = _new_oracle(t)       # a rescue resets her weight
						if score[t] >= WIN_RESCUES:
							_finish("rescue")
				elif lead.pos.distance_to(cell(t)) <= THRONE_RADIUS:
					_event("recaptured", {"team":t, "id":lead.id})
					_return_to_cell(t)
			"dropped":
				if time - float(o.dropped_at) >= DROP_RETURN:
					_return_to_cell(t)
					_event("recaptured", {"team":t, "id":""})
					continue
				# Left on the ground too long: she throws a tantrum that knocks back and stuns
				# everyone nearby, which gives her own team a window to reach her.
				if time - float(o.dropped_at) >= TANTRUM_AFTER and time - float(o.tantrum_at) >= TANTRUM_EVERY:
					o.tantrum_at = time
					var hit := 0
					for u in units:
						if not alive(u):
							continue
						var off: Vector2 = u.pos - o.pos
						var d := off.length()
						if d > TANTRUM_R:
							continue
						var dir := off / d if d > 0.05 else dir_of(rng.randf() * TAU)
						_knockback(u, dir * TANTRUM_PUSH * (1.0 - 0.5 * d / TANTRUM_R))
						u.stun = maxf(u.stun, TANTRUM_STUN)
						u.task = {}
						if u.state in ["wind", "recover"]:
							u.state = "idle"
						hit += 1
					_event("tantrum", {"team":t, "pos":o.pos, "hit":hit})
			"cell":
				# Sanctuary: her own team heals while standing next to her in the enemy dungeon.
				for u in units:
					if u.team == t and alive(u) and u.hp < u.max_hp and u.pos.distance_to(o.pos) <= HEAL_R:
						u.hp = minf(u.max_hp, u.hp + HEAL_RATE * dt)
func _step_world(dt: float) -> void:
	# Gates swing open for allies nearby (visual state), resource nodes regrow.
	for g in gates:
		var open := false
		if gate_blocks(g):
			for u in units:
				if u.team == g.team and alive(u) and u.pos.distance_to(g.c) < GATE_OPEN_RADIUS:
					open = true
					break
		if open != g.open:
			g.open = open
			_event("gate_open" if open else "gate_close", {"gate":g.id, "team":g.team})
	if levels[0].catapult > 0 or levels[1].catapult > 0:
		for cat in catapults:
			if levels[int(cat.team)].catapult <= 0:
				continue
			cat.t += dt
			if cat.t < CATAPULT_EVERY:
				continue
			var target := {}
			var best := INF
			for u in units:
				if u.team == int(cat.team) or not alive(u):
					continue
				var d: float = u.pos.distance_to(cat.p)
				if d >= CATAPULT_MIN and d <= CATAPULT_MAX and d < best:
					best = d
					target = u
			if target.is_empty():
				continue
			cat.t = 0.0
			shells.append({"id":_next_shell, "team":int(cat.team), "from":cat.p, "to":target.pos, "t":0.0, "flight":CATAPULT_FLIGHT})
			_event("catapult_fire", {"team":int(cat.team), "shell":_next_shell, "from":cat.p, "to":target.pos, "flight":CATAPULT_FLIGHT})
			_next_shell += 1
	for i in range(shells.size() - 1, -1, -1):
		var sh: Dictionary = shells[i]
		sh.t += dt
		if sh.t < sh.flight:
			continue
		for u in units:
			if u.team != int(sh.team) and alive(u) and u.pos.distance_to(sh.to) <= CATAPULT_AOE:
				_damage({"team":int(sh.team), "id":"catapult"}, u, CATAPULT_DMG)
		_event("catapult_hit", {"team":int(sh.team), "pos":sh.to, "shell":sh.id})
		shells.remove_at(i)
	for ct in cake_trees:
		if not ct.ready:
			ct.t += dt
			if ct.t >= CAKE_EVERY:
				ct.ready = true
				_event("cake_ready", {"tree":ct.id})
	for n in nodes:
		if n.amount < n.max:
			n.t += dt
			if n.t >= n.regen:
				n.t = 0.0
				n.amount += 1
				if n.amount == 1:
					_event("node_regrow", {"node":n.id})

func _commander(team: int) -> void:
	# Team quartermaster. Works down a plan and saves for the next item instead of buying
	# whatever is cheapest (which starved the stone-heavy upgrades). A badly damaged gate is the
	# one exception. On the human's team it only spends surplus (2x the cost) so the player gets
	# to choose at the workshop first.
	var human_team := false
	for u in units:
		if not u.bot and u.team == team:
			human_team = true
	var plan := ["armory", "catapult", "gates", "forge", "armory", "gates", "armory"]
	var seen := {}
	var target := ""
	for id in plan:
		seen[id] = int(seen.get(id, 0)) + 1
		if int(levels[team][id]) < int(seen[id]) and int(levels[team][id]) < int(UPGRADES[id].max):
			target = id
			break
	var damaged := false
	for g in gates:
		if g.team == team and (g.broken or g.hp < g.max_hp * 0.5):
			damaged = true
	var choice := ""
	if damaged and can_buy(team, "gates"):
		choice = "gates"
	elif target != "" and can_buy(team, target):
		choice = target
	if choice == "":
		return
	if human_team:
		var cost := upgrade_cost(team, choice)
		if stock[team].wood < int(cost.wood) * 2 or stock[team].stone < int(cost.stone) * 2:
			return
	buy_upgrade(team, choice)

func _finish(reason: String) -> void:
	ended = true
	end_reason = reason
	if score[0] != score[1]:
		winner = 0 if score[0] > score[1] else 1
	elif kills[0] != kills[1]:
		winner = 0 if kills[0] > kills[1] else 1
	else:
		winner = -1
	_event("end", {"winner":winner,"reason":reason})

# ---------- bots ----------
var _gate_alarm := [{"gate":-1, "at":-100.0}, {"gate":-1, "at":-100.0}]

func _note_gate_alarm(e: Dictionary) -> void:
	if e.k == "gate_hit":
		_gate_alarm[int(e.team)] = {"gate":int(e.gate), "at":time}

func _inward(team: int) -> Vector2:
	return Vector2(0, 1) if team == 0 else Vector2(0, -1)

func _nav_to(u: Dictionary, goal: Vector2, stop := 0.5) -> void:
	if u.pos.distance_to(goal) <= stop:
		u.move = Vector2.ZERO
		return
	if u.unstick > 0.0:
		u.move = u.unstick_dir
		return
	var replan: bool = u.path.is_empty() or u.path_goal.distance_to(goal) > 1.5 or time - float(u.path_at) > 1.5 \
		or int(u.path_ver) != nav_version or int(u.path_i) >= u.path.size()
	if replan:
		if profile: prof["replans"] = int(prof.get("replans", 0)) + 1
		var tp := Time.get_ticks_usec() if profile else 0
		u.path = find_path(u.team, u.pos, goal)
		if profile: _p("pathfind", tp)
		u.path_i = 0
		u.path_goal = goal
		u.path_at = time
		u.path_ver = nav_version
	var path: PackedVector2Array = u.path
	while u.path_i < path.size() and u.pos.distance_to(path[u.path_i]) < 0.75:
		u.path_i += 1
	var target: Vector2 = goal if u.path_i >= path.size() else path[u.path_i]
	var d: Vector2 = target - u.pos
	u.move = d.normalized() if d.length() > 0.05 else Vector2.ZERO

func _bot_forge(u: Dictionary) -> void:
	var f: Dictionary = u.forge
	u.move = Vector2.ZERO
	if not f.open:
		_interact(u)
		return
	if f.rolling > 0.0:
		return
	if f.rolled:
		var r := forge_result(f.faces)
		if r.cls != "" or f.faces.count("fate") == f.faces.size():
			_forge_take(u)
			return
		var held := []
		for i in f.faces.size():
			held.append(f.faces[i] == "fate")
		_forge_roll(u, held)
	else:
		_forge_roll(u, null)

func _unstick_check(u: Dictionary) -> void:
	# If a bot wanted to move but barely did, sidestep for a moment.
	u.unstick = maxf(0.0, u.unstick - 0.15)
	if u.move.length() > 0.1 and u.task.is_empty() and not u.forge.open and u.pos.distance_to(u.last_pos) < 0.1:
		u.stuck_t += 0.15
		if u.stuck_t >= 0.75:
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			u.unstick_dir = (Vector2(-u.move.y, u.move.x) * side - u.move * 0.3).normalized()
			u.unstick = 0.6
			u.stuck_t = 0.0
			u.path = PackedVector2Array()
	else:
		u.stuck_t = 0.0
	u.last_pos = u.pos

func _think(u: Dictionary) -> void:
	if not alive(u) or u.stun > 0.0 or u.state in ["wind","recover","dodge"]:
		return
	_unstick_check(u)
	if u.cls == "villager" and not u.carrying:
		if u.role == "gather":
			var ws := workshop(u.team)
			if u.pos.distance_to(ws) <= WORKSHOP_RADIUS - 0.3:
				u.move = Vector2.ZERO
				_take_tools(u)
			else:
				_nav_to(u, ws, 0.6)
			return
		var fg := forge(u.team)
		if u.pos.distance_to(fg) <= FORGE_RADIUS - 0.4:
			_bot_forge(u)
		else:
			u.forge.open = false
			_nav_to(u, fg, 0.6)
		return
	if u.cls == "worker" and not u.carrying:
		_think_worker(u)
		return
	_think_fighter(u)

func _think_worker(u: Dictionary) -> void:
	var foe := nearest_enemy(u, 2.6)
	if not foe.is_empty():
		u.task = {}
		if u.hp > u.max_hp * 0.45:
			u.move = Vector2.ZERO
			u.face = angle_of(foe.pos - u.pos)
			_start_attack(u, "attack")
		else:
			_nav_to(u, spawn(u.team), 1.0)
		return
	if not u.task.is_empty():
		u.move = Vector2.ZERO
		return
	# Deliver a full (or stranded) load.
	if u.load.n >= CARRY_MAX:
		_nav_to(u, workshop(u.team), WORKSHOP_RADIUS - 0.6)
		return
	# Repair a gate that is broken or badly damaged, if there is material for it.
	if repair_stock(u.team) >= 2:
		for g in gates:
			if g.team == u.team and (g.broken or g.hp < g.max_hp * 0.4):
				var inside: Vector2 = g.c + _inward(u.team) * 2.0
				if u.pos.distance_to(inside) > 1.2:
					_nav_to(u, inside, 0.8)
				else:
					u.move = Vector2.ZERO
					u.face = angle_of(g.c - u.pos)
					u.task = {"kind":"repair", "gate":g.id, "t":REPAIR_TICK}
				return
	# The stone-duty worker raises one ladder on the enemy wall when their gates are holding.
	if u.get("duty", "") == "stone" and stock[u.team].wood >= LADDER_COST + 4 and u.load.n == 0:
		var own_ladders := 0
		for l in ladders:
			if int(l.team) == u.team:
				own_ladders += 1
		var enemy_gates_up := 0
		for g in gates:
			if g.team != u.team and gate_blocks(g):
				enemy_gates_up += 1
		if own_ladders == 0 and enemy_gates_up >= 1 and time > 60.0:
			var spot_p: Vector2 = _c(1 - u.team, Vector2(0.0, FRONT_Z)) + _inward(u.team) * 1.6
			if u.pos.distance_to(spot_p) > 0.8:
				_nav_to(u, spot_p, 0.5)
			else:
				u.move = Vector2.ZERO
				if not ladder_spot(u).is_empty():
					u.face = angle_of(_c(1 - u.team, Vector2(0.0, FRONT_Z)) - u.pos)
					u.task = {"kind":"build_ladder", "t":LADDER_BUILD}
			return
	# Gather whatever the stockpile is shorter on; prefer nodes on our own half.
	var want := "stone" if stock[u.team].stone < stock[u.team].wood else "wood"
	if u.get("duty", "") == "":
		var n_workers := 0
		for o in units:
			if o.team == u.team and o != u and o.get("duty", "") != "":
				n_workers += 1
		u["duty"] = "wood" if n_workers % 2 == 0 else "stone"
	if stock[u.team][u.duty] < 30:
		want = u.duty
	if u.load.n > 0:
		want = u.load.kind
	var best := {}
	var best_score := INF
	for n in nodes:
		if n.amount <= 0:
			continue
		var s: float = u.pos.distance_to(n.p) + (0.0 if n.kind == want else 12.0)
		if (n.p.y > 0.0) != (u.team == 0):
			s += 10.0
		if s < best_score:
			best_score = s
			best = n
	if best.is_empty():
		if u.load.n > 0:
			_nav_to(u, workshop(u.team), WORKSHOP_RADIUS - 0.6)
		return
	var stand: Vector2 = best.p + (u.pos - best.p).normalized() * (best.r + 0.8)
	if u.pos.distance_to(best.p) - best.r <= 1.2:
		if u.load.n > 0 and u.load.kind != best.kind:
			_nav_to(u, workshop(u.team), WORKSHOP_RADIUS - 0.6)
			return
		u.move = Vector2.ZERO
		u.face = angle_of(best.p - u.pos)
		u.task = {"kind":"gather", "node":best.id, "t":GATHER_TIME}
	else:
		_nav_to(u, stand, 0.4)

func _think_fighter(u: Dictionary) -> void:
	var c: Dictionary = CLASSES[u.cls]
	var mine: Dictionary = oracles[u.team]
	var theirs: Dictionary = oracles[1 - u.team]
	if u.carrying:
		var ho := lifting_oracle(u)
		if ho.is_empty() or ho.carrier != u.id:
			u.move = Vector2.ZERO          # followers just hold on
			return
		var dest: Vector2 = throne(u.team) if int(ho.team) == u.team else cell(int(ho.team))
		if ho.lifters.size() < lifters_needed(ho):
			u.move = Vector2.ZERO          # too heavy: wait for more hands
		else:
			_nav_to(u, dest, 0.3)
		return
	var goal: Vector2 = u.pos
	var enemy_carrier := oracle_carrier(1 - u.team)    # enemies carrying their Oracle home: stop them
	var ally_carrier := oracle_carrier(u.team)         # we're carrying ours home
	var our_returner := oracle_returner(u.team)        # enemies hauling OUR Oracle back to their cell
	var alarm: Dictionary = _gate_alarm[u.team]
	var short_hands: bool = not ally_carrier.is_empty() and mine.lifters.size() < lifters_needed(mine)
	var captive_loose: bool = theirs.state == "dropped" or (theirs.state == "carried" and int(theirs.carry_team) == u.team and theirs.lifters.size() < lifters_needed(theirs))
	var cake_runner: bool = u.role == "defend" and absi(u.id.hash()) % 2 == 0
	if not enemy_carrier.is_empty() and (u.role == "defend" or u.pos.distance_to(enemy_carrier.pos) < 16.0):
		goal = enemy_carrier.pos
	elif not our_returner.is_empty() and (u.role in ["raid", "escort"] or u.pos.distance_to(our_returner.pos) < 16.0):
		goal = our_returner.pos
	elif short_hands and u.role in ["raid", "escort"] and u.pos.distance_to(mine.pos) < 60.0:
		goal = mine.pos
	elif captive_loose and u.role in ["defend", "escort"] and u.pos.distance_to(theirs.pos) < 30.0:
		goal = theirs.pos
	elif u.role == "defend" and time - float(alarm.at) < 4.0 and alarm.gate >= 0:
		goal = gates[int(alarm.gate)].c + _inward(u.team) * 2.4
	elif mine.state in ["cell", "dropped"] and u.role in ["raid", "escort", "gather"]:
		goal = mine.pos
	elif not ally_carrier.is_empty():
		goal = ally_carrier.pos + dir_of(u.face) * 2.0
	elif u.role == "defend":
		goal = theirs.pos + _inward(u.team) * -2.0
	else:
		goal = mine.pos
	var aggro := {"raid":3.5,"escort":6.5,"defend":8.0}.get(u.role, 5.0) as float
	if c.ranged:
		aggro = maxf(aggro, float(c.range) * (0.6 if u.role == "raid" else 0.95))
	var foe := nearest_enemy(u, aggro)
	for carrier in [enemy_carrier, our_returner]:
		if not carrier.is_empty() and u.pos.distance_to(carrier.pos) < aggro + 3.0:
			foe = carrier
	if not foe.is_empty() and _blocked_line(u.pos, foe.pos, u.team):
		foe = {}   # can't reach through a wall; keep pathing instead
	if u.hp < u.max_hp * 0.3 and not foe.is_empty() and u.cd_dodge <= 0.0 and rng.randf() < 0.25:
		u.move = (u.pos - foe.pos).normalized()
		_dodge(u)
		return
	if not foe.is_empty():
		if u.offering:
			pass   # hands full: keep walking to the cell, dodge if needed
		else:
			_fight(u, foe)
			return
	# Cake runs: some defenders fetch cake from the nearest ripe tree and feed the captive.
	var captive: Dictionary = theirs
	if u.offering:
		if captive.state == "cell" and int(captive.cakes) < MAX_WEIGHT * CAKE_PER_STAGE:
			if u.pos.distance_to(captive.pos) <= FEED_RADIUS - 0.3:
				u.move = Vector2.ZERO
				_do_offering(u)
			else:
				_nav_to(u, captive.pos, FEED_RADIUS - 0.5)
			return
	elif cake_runner and captive.state == "cell" and int(captive.cakes) < MAX_WEIGHT * CAKE_PER_STAGE \
			and time - float(alarm.at) > 6.0 and enemy_carrier.is_empty():
		var tree := {}
		var td := INF
		for ct in cake_trees:
			var d: float = u.pos.distance_to(ct.p)
			if ct.ready and d < td and d < 45.0:
				td = d
				tree = ct
		if not tree.is_empty():
			if td <= 1.5:
				u.move = Vector2.ZERO
				_do_offering(u)
			else:
				_nav_to(u, tree.p, 1.2)
			return
	# Lift: start or join a lift when standing at an Oracle we should be moving.
	var lo := _liftable(u)
	if not lo.is_empty():
		var ours: bool = int(lo.team) == u.team
		var wanted: bool = lo.state != "carried" or lo.lifters.size() < lifters_needed(lo)
		# Don't start a lift she can't move yet: a lone lifter just stands in the enemy dungeon
		# and dies. Wait beside her (her aura heals us) until enough hands are here.
		if lo.state != "carried" and _hands_near(lo.pos, u.team, 3.5) < lifters_needed(lo):
			wanted = false
		if wanted and (ours or lo.state == "dropped" or int(lo.carry_team) == u.team):
			u.move = Vector2.ZERO
			_join_lift(u, lo)
			return
	_nav_to(u, goal, 0.8)
	# Siege: our route runs through a standing enemy gate -> break it.
	var sg := _path_gate(u)
	if not sg.is_empty():
		var cp := seg_closest(u.pos, sg.a, sg.b)
		var d: float = u.pos.distance_to(cp)
		if c.ranged:
			if d <= float(c.range) * 0.8:
				u.move = Vector2.ZERO
				u.face = angle_of(sg.c - u.pos)
				_start_attack(u, "attack", false)
		elif d <= float(c.range) + WALL_R + 0.2:
			u.move = Vector2.ZERO
			u.face = angle_of(cp - u.pos)
			if u.cd_ability <= 0.0 and str(c.ability) in ["spin","bash"] and rng.randf() < 0.3:
				_start_attack(u, "ability", false)
			else:
				_start_attack(u, "attack", false)

func _blocked_line(a: Vector2, b: Vector2, team: int) -> bool:
	for i in range(1, 6):
		if _blocked_point(a.lerp(b, float(i) / 6.0), team, 0.1):
			return true
	return false

func _fight(u: Dictionary, foe: Dictionary) -> void:
	var c: Dictionary = CLASSES[u.cls]
	var d: float = u.pos.distance_to(foe.pos)
	var reach := float(c.range)
	if c.ranged:
		if d < reach * 0.45:
			u.move = (u.pos - foe.pos).normalized()
		elif d > reach * 0.85:
			_nav_to(u, foe.pos, 0.5)
		else:
			u.move = Vector2.ZERO
		if d <= reach * 0.9:
			u.face = angle_of(foe.pos - u.pos)
			if u.cd_ability <= 0.0 and rng.randf() < 0.35:
				_start_attack(u, "ability")
			else:
				_start_attack(u, "attack")
		return
	if d <= reach + UNIT_R + 0.1:
		u.move = Vector2.ZERO
		u.face = angle_of(foe.pos - u.pos)
		var ab := str(c.ability)
		var crowd := _melee_count(u, 2.8)
		if u.cd_ability <= 0.0 and ((ab == "spin" and crowd >= 2) or ab == "bash" or rng.randf() < 0.3):
			_start_attack(u, "ability")
		else:
			_start_attack(u, "attack")
		return
	if str(c.ability) == "lunge" and d < 5.5 and u.cd_ability <= 0.0:
		u.face = angle_of(foe.pos - u.pos)
		_start_attack(u, "ability")
		return
	_nav_to(u, foe.pos, reach * 0.8)

# ---------- rewards ----------
static func match_rewards(sim_winner: int, me: Dictionary) -> Dictionary:
	# Pure function of the result and the player's contribution, credited through progression.
	var won: bool = sim_winner == int(me.team)
	var draw: bool = sim_winner == -1
	var base: Dictionary = {"gold":120, "xp":60, "pts":12, "chest":1} if won else ({"gold":70, "xp":40, "pts":8, "chest":0} if draw else {"gold":40, "xp":25, "pts":5, "chest":0})
	var gold: int = int(base.gold) + 40 * int(me.rescues) + 4 * int(me.kills) + int(me.gathered) + int(float(me.gate_dmg) / 50.0)
	return {"gold":gold, "xp":int(base.xp) + 15 * int(me.rescues), "pts":int(base.pts), "chest":int(base.chest)}

func _melee_count(u: Dictionary, r: float) -> int:
	var n := 0
	for o in units:
		if o.team != u.team and alive(o) and o.pos.distance_to(u.pos) <= r:
			n += 1
	return n
