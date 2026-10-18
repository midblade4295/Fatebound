extends RefCounted
# Fatebound Siege: real-time capture-the-Oracle between two castles. Pure simulation with no scene
# nodes, stepped at a fixed rate, so the same rules can later run on an authoritative server.
# Coordinates: Vector2(x, z) on the ground plane. Blue (team 0) holds the south end (+z), red
# (team 1) the north end (-z). Red's castle is the point mirror of blue's: (x, z) -> (-x, -z).

const TICK := 1.0 / 30.0
const Land = preload("res://scripts/siege/siege_land.gd")
const Keep = preload("res://scripts/siege/keep.gd")              # 0.31.165: the Rift's keeps (the world is the 5v5's map)
const Moba = preload("res://scripts/siege/moba.gd")
# 0.31.155 5V5 (the test; scripts/siege/moba.gd): heroes, minion waves, towers. null unless setup_moba() was called:
# then these hooks hand over to it (stat, step, _think, _damage, _kill, gates, melee and arrows on towers, ACTION).
var moba = null
const HALF_W := Land.HALF_W
const HALF_L := Land.HALF_L
const UNIT_R := 0.45
const MATCH_TIME := 720.0
var match_time := MATCH_TIME     # 0.31.153: (COMMANDER's matches are shorter: CMD_MATCH_TIME)
const RESPAWN_TIME := 5.0
# ---- castle geometry (blue side; red mirrored) ----
const WALL_SCALE := 2.6          # KayKit wall_straight is 2.0 long -> 5.2 m
const SEG := 5.2
const WALL_R := 1.0              # collision half-thickness of a wall
const GATE_HP := 1100.0
const GATE_OPEN_RADIUS := 4.0    # allies within this distance swing the doors open (visual)
const WATER_MOVE := 0.45         # wading speed in the river (Round 33; the Rift's river is shallow: ~0.8 at its deepest)
const WATER_NAV_COST := 1.6      # river cells cost this much in the nav grid: paths still prefer a nearby ford (2.5 and
                                 # depth > 0.15 on the Siege field, for its bridges)
const WATER_NAV_DEPTH := 0.05
# Healing doesn't stack (0.31.4): one Sanctuary per target every SANCT_ONCE s; a second healer beam on a target already
# healed by a beam this tick heals at BEAM_STACK.
const SANCT_ONCE := 3.0
const BEAM_STACK := 0.5
const UPGRADE_NAME := {"knight":"Crusader","barbarian":"Berserker","rogue":"Assassin","ranger":"Ranger","mage":"Archmage","priest":"Necromancer"}
const BEAM_HOLD := 0.22
# Knight BLOCK (Round 11, Kevin): hold ABILITY -> shield up, walk forward slowly; the shield (a
# segment in front of the knight) stops every hit whose path crosses it -- for the knight (from the
# front) and for anyone behind it -- and destroys projectiles that fly into it.
const BLOCK_HOLD := 0.22
const BLOCK_MOVE := 0.4
const SHIELD_FWD := 0.7
const SHIELD_HALF := 1.3          # (the Knight; its upgrade, the Crusader, throws a hammer instead since 0.30.5)
# Berserker WHIRLWIND (upgraded barbarian, two-handed sword): 3 s of spinning, moving freely,
# hitting everything within WHIRL_R every WHIRL_TICK.
const WHIRL_TIME := 3.0
const WHIRL_TICK := 0.3
const WHIRL_R := 2.4
const WHIRL_DMG := 0.55           # x barbarian damage per tick
const WHIRL_CD := 9.0           # the beam stays up this long after the last ATTACK (held ATTACK refreshes it)
const BEAM_MOVE := 0.7            # walking speed while channelling
const SANCTUARY_R := 6.5          # 4.5 until 0.31.1 (Kevin: bigger priest heal)
const NOVA_R := 4.8               # the mage's nova, 3.3 until 0.31.1 (Kevin: bigger wizard AoE)
const SANCTUARY_HEAL := 35.0

# range: melee reach or projectile travel. arc: cosine of the half-angle a melee swing covers.
# gate: damage multiplier against gates.
const CLASSES := {
	"knight": {"name":"Knight","hp":150,"speed":4.6,"dmg":21,"range":2.0,"arc":0.4,"windup":0.24,"recover":0.4,
		"ranged":false,"ability":"block","ab_cd":0.0,"gate":1.0},
	"barbarian": {"name":"Barbarian","hp":130,"speed":4.8,"dmg":26,"range":2.0,"arc":0.25,"windup":0.36,"recover":0.45,
		"ranged":false,"ability":"spin","ab_cd":7.0,"gate":1.6},
	"rogue": {"name":"Rogue","hp":85,"speed":6.2,"dmg":14,"range":1.4,"arc":0.5,"windup":0.13,"recover":0.22,
		"ranged":false,"ability":"lunge","ab_cd":5.0,"gate":0.6},
	"ranger": {"name":"Archer","hp":80,"speed":5.4,"dmg":15,"range":11.0,"arc":0.0,"windup":0.3,"recover":0.45,
		"ranged":true,"proj_speed":33.0,"aoe":0.0,"ability":"volley","ab_cd":7.0,"gate":0.35},
	"mage": {"name":"Mage","hp":75,"speed":5.0,"dmg":20,"range":9.0,"arc":0.0,"windup":0.4,"recover":0.5,
		"ranged":true,"proj_speed":24.0,"aoe":1.6,"ability":"nova","ab_cd":8.0,"gate":1.0},
	# Healer (Round 9, Kevin): hold ATTACK to channel a healing beam into the nearest injured ally
	# (range = beam reach); the ability heals every ally close by. No damage.
	"priest": {"name":"Priest","hp":90,"speed":5.2,"dmg":0,"range":9.0,"arc":0.0,"windup":0.3,"recover":0.4,
		"ranged":true,"proj_speed":0.0,"aoe":0.0,"ability":"sanctuary","ab_cd":9.0,"gate":0.3,"heal":18.0},
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
# The shove of the killing blow (0.31.20): callers set it before _damage; _kill sends it with the death so bodies,
# weapons and hats go the way the blow went. Reset after every _damage.
var _next_push := Vector3.ZERO
var rng := RandomNumberGenerator.new()
var nav: Array = []            # AStarGrid2D per team
var nav_version := 0
const AI_EVERY := 0.15            # seconds between a bot's decisions (_think; _unstick_check counts in these)
const AI_SPREAD := 5              # the bots' first decisions fall on this many consecutive ticks (0.15 s = 4.5 ticks)
var _next_proj := 1
var _basic_by := ""                  # 0.31.167: whose basic attack is landing right now (POISON BLADES), else ""

# ---------- map ----------
static func _m(team: int, p: Vector2) -> Vector2:
	return p if team == 0 else -p

static func throne(team: int) -> Vector2:
	# Where a team's King stands (0.31.165: in front of his throne at the back of his keep).
	return _m(team, Keep.KING)

static func height_at(p: Vector2) -> float:
	# Ground height for rendering (0.31.165: the Rift's; the keeps' floors are level).
	return Land.ground_height(p)

static func spawn(team: int) -> Vector2:
	# 0.31.165: the fountain at the back of the keep
	return _m(team, Keep.FOUNTAIN)

static func gate_front(g: Dictionary) -> Vector2:
	# Standing point just outside a gate (the side facing midfield).
	if g.has("in"):
		return (g.c as Vector2) - (g["in"] as Vector2) * 2.2
	var outward := Vector2(0, -1) if g.team == 0 else Vector2(0, 1)
	return g.c + outward * 2.2

static func seg_seg_closest(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> Array:
	# Closest points between two segments (sampled; walls are short or straight).
	var best := INF
	var pa := a0
	var pb := b0
	for k in 17:
		var q: Vector2 = a0.lerp(a1, k / 16.0)
		var c: Vector2 = seg_closest(q, b0, b1)
		if q.distance_squared_to(c) < best:
			best = q.distance_squared_to(c); pa = q; pb = c
		var q2: Vector2 = b0.lerp(b1, k / 16.0)
		var c2: Vector2 = seg_closest(q2, a0, a1)
		if q2.distance_squared_to(c2) < best:
			best = q2.distance_squared_to(c2); pa = c2; pb = q2
	return [pa, pb]

func _fill_squeeze_slots() -> void:
	# Any two walls closer together than a unit is wide (but not touching) make a slot a unit can
	# be shoved into and never pushed out of -- the push-out resolves walls one at a time (a knight
	# stuck behind the dungeon cell, then at a river bank / bridge rail, Round 11-12). Bridge every
	# such slot with a filler segment. Fillers between walls arrows fly over stay arrow-passable.
	var need := UNIT_R * 2.0 + 0.1
	var fills := []
	var n := walls.size()
	for i in n:
		var A: Dictionary = walls[i]
		for j in range(i + 1, n):
			var B: Dictionary = walls[j]
			var reach: float = float(A.r) + float(B.r) + need
			if minf(A.a.x, A.b.x) - reach > maxf(B.a.x, B.b.x) or minf(B.a.x, B.b.x) - reach > maxf(A.a.x, A.b.x) \
					or minf(A.a.y, A.b.y) - reach > maxf(B.a.y, B.b.y) or minf(B.a.y, B.b.y) - reach > maxf(A.a.y, A.b.y):
				continue
			var cp: Array = seg_seg_closest(A.a, A.b, B.a, B.b)
			var gap: float = (cp[0] as Vector2).distance_to(cp[1]) - float(A.r) - float(B.r)
			if gap <= 0.02 or gap >= need:
				continue
			# Already closed by a third wall? (e.g. two segments of one river bank)
			var mid: Vector2 = ((cp[0] as Vector2) + (cp[1] as Vector2)) * 0.5
			var covered := false
			for k in n:
				if k == i or k == j:
					continue
				var C: Dictionary = walls[k]
				if mid.distance_to(seg_closest(mid, C.a, C.b)) < float(C.r):
					covered = true
					break
			if covered:
				continue
			var passable: bool = PROJ_PASS_KINDS.has(A.kind) and PROJ_PASS_KINDS.has(B.kind)
			fills.append({"a":cp[0], "b":cp[1], "r":maxf(float(A.r), float(B.r)), "team":A.team if int(A.team) == int(B.team) else -1,
				"kind":"ledge" if passable else "fill"})
	walls.append_array(fills)
	squeeze_fills = fills.size()

func _build_map() -> void:
	# 0.31.165: the Rift (siege_land.gd) -- the keeps (keep.gd), the ridges, the pits' rims and the field's edge. (The
	# Siege castles, their hat stands, the resource nodes, the cover rocks and the outposts are gone with the Siege.)
	walls.clear()
	gates.clear()
	obstacles.clear()
	for t in 2:
		_build_keep(t)
	walls.append_array(Land.walls())
	_fill_squeeze_slots()

func _build_keep(t: int) -> void:
	# The ring wall between the gatehouses (a wall end's cap covers the gatehouse's pillar, as on the Siege castles),
	# the three gates (the doorways: "west" / "mid" / "east", by the lane that ends there) and the throne behind the King.
	for seg in Keep.ring():
		walls.append({"a":_m(t, seg[0]), "b":_m(t, seg[1]), "r":WALL_R, "team":t, "kind":"wall"})
	for i in Keep.GATE_ANG.size():
		var gd: Array = Keep.gate_ends(i)
		var a := _m(t, gd[0])
		var b := _m(t, gd[1])
		# "in": the gate's inward normal (toward its keep) -- enemies on that side may walk out (lets_out).
		var inw := (_m(t, Keep.C) - (a + b) * 0.5).normalized()
		gates.append({"id":gates.size(), "team":t, "a":a, "b":b, "c":(a + b) * 0.5, "hp":GATE_HP, "max_hp":GATE_HP,
			"broken":false, "open":false, "side":str(Keep.GATE_SIDE[i]), "lane":i, "in":inw})
	obstacles.append({"p":_m(t, Keep.THRONE_SEAT), "r":Keep.THRONE_R, "kind":"castle_building", "team":t})

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

func _cells_across_segment(a: Vector2, b: Vector2, reach: float) -> Array:
	# Like _cells_near_segment, but only cells whose centre projects INSIDE a-b (a rectangle, no
	# rounded ends). Gate doorways use this: the rounded ends of a capsule reached 1.35 m past the
	# doorway into the wall's end cap, so paths led units into solid wall (Round 10 finding).
	var out := []
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 0.0001)
	for c in _cells_near_segment(a, b, reach):
		var t := (nav_point(c) - a).dot(ab) / len2
		if t >= 0.0 and t <= 1.0:
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
var _blockers: Array = []             # knights with their shield up this tick
var squeeze_fills := 0                # slots closed by _fill_squeeze_slots (see there)
var _bucket_walls_proj: Array = []   # only walls that stop projectiles (not ledges/bars/river/rails)
const PROJ_PASS_KINDS := ["ledge", "bars", "river", "rail", "edge", "rock"]     # (0.31.165: shots fly over the Rift's ridges)
var _bucket_obs: Array = []
var _bucket_obs_proj: Array = []      # obstacles that stop shots (not the towers)

func _build_buckets() -> void:
	_bw = int(ceil(HALF_W * 2.0 / BUCKET)) + 1
	_bh = int(ceil(HALF_L * 2.0 / BUCKET)) + 1
	_bucket_walls = []
	_bucket_walls_proj = []
	_bucket_obs = []
	_bucket_obs_proj = []
	for i in _bw * _bh:
		_bucket_walls.append(PackedInt32Array())
		_bucket_walls_proj.append(PackedInt32Array())
		_bucket_obs.append(PackedInt32Array())
		_bucket_obs_proj.append(PackedInt32Array())
	for wi in walls.size():
		var w: Dictionary = walls[wi]
		for bi in _buckets_in(minf(w.a.x, w.b.x) - w.r - BUCKET_REACH, minf(w.a.y, w.b.y) - w.r - BUCKET_REACH,
				maxf(w.a.x, w.b.x) + w.r + BUCKET_REACH, maxf(w.a.y, w.b.y) + w.r + BUCKET_REACH):
			_bucket_walls[bi].append(wi)
			if not PROJ_PASS_KINDS.has(w.kind):
				_bucket_walls_proj[bi].append(wi)
	for oi in obstacles.size():
		var ob: Dictionary = obstacles[oi]
		for bi in _buckets_in(ob.p.x - ob.r - BUCKET_REACH, ob.p.y - ob.r - BUCKET_REACH, ob.p.x + ob.r + BUCKET_REACH, ob.p.y + ob.r + BUCKET_REACH):
			_bucket_obs[bi].append(oi)
			_bucket_obs_proj[bi].append(oi)

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

static var _outside: Array = []

static func _outside_cells() -> Array:
	# Nav cells beyond the field's natural edge (walls alone left closed-off pockets pathable).
	if _outside.is_empty():
		for x in NAV_W:
			for y in NAV_H:
				var c := Vector2i(x, y)
				if not Land.inside_field(nav_point(c)):
					_outside.append(c)
	return _outside

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
	solid.append_array(_outside_cells())
	for c in solid:
		for t in 2:
			(nav[t] as AStarGrid2D).set_point_solid(c, true)
	# The river is walkable but slow: its cells cost more, so a path crosses at a bridge unless one is far.
	var grid0: AStarGrid2D = nav[0]
	for ix in range(grid0.region.position.x, grid0.region.end.x):
		for iz in range(grid0.region.position.y, grid0.region.end.y):
			var cc := Vector2i(ix, iz)
			if water_depth(nav_point(cc)) > WATER_NAV_DEPTH:
				for t in 2:
					(nav[t] as AStarGrid2D).set_point_weight_scale(cc, WATER_NAV_COST)
	_gate_cells.clear()
	for g in gates:
		_gate_cells.append(_cells_across_segment(g.a, g.b, float(g.get("r", WALL_R)) + UNIT_R * 0.9))
	_update_gate_nav()

var _gate_cells: Array = []

func _update_gate_nav() -> void:
	_po_epoch += 1                              # (a gate broke or stood again: everyone's push-out is re-checked)
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
	var grid: AStarGrid2D = nav[team if team <= 1 else 0]     # (0.31.157: a jungle monster, team 2, walks blue's grid)
	# Starting inside an enemy castle: its intact gates are a way out (lets_out), not an obstacle, for this search.
	var opened := []
	for gi in gates.size():
		var g: Dictionary = gates[gi]
		if g.team != team and gate_blocks(g) and lets_out(g, from):
			opened.append(gi)
			for c in _gate_cells[gi]:
				grid.set_point_weight_scale(c, 1.0)
	var a := _free_cell(grid, nav_cell(from))
	var b := _free_cell(grid, nav_cell(to))
	var ids := grid.get_id_path(a, b, true)
	for gi in opened:
		for c in _gate_cells[gi]:
			grid.set_point_weight_scale(c, 60.0)
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

static func lets_out(g: Dictionary, p: Vector2) -> bool:
	# Castle gates are one-way for the enemy (Round 29, Kevin: he couldn't get back out of their castle in the
	# tutorial): an enemy already inside may walk out through an intact gate; from outside it still blocks until
	# broken.
	return g.has("in") and (p - (g.c as Vector2)).dot(g["in"]) > 0.0

# ---------- setup ----------
func setup(team_size: int, seed_value: int, player_team := 0) -> void:
	# The field and a side of team_size each (you the first of player_team's); setup_moba() makes them heroes.
	meteors = []
	rng.seed = seed_value
	_build_map()
	_build_buckets()
	_build_nav()
	oracles = [_new_king(0), _new_king(1)]
	for t in 2:
		for i in team_size:
			var human := t == player_team and i == 0
			var id := "you" if human else "%s%d" % ["b" if t == 0 else "r", i]
			var u := _new_unit(id, t, not human)
			u.think_at = float(units.size() % AI_SPREAD) * TICK      # the bots' thinking spread over the ticks
			units.append(u)
			by_id[id] = u
			_respawn(u, true)

func _new_king(team: int) -> Dictionary:
	# a side's King, home before his throne (moba.gd: the heart -- his health, his strikes; the view draws him)
	return {"team":team, "state":"home", "pos":throne(team)}

func _new_unit(id: String, team: int, bot: bool) -> Dictionary:
	return {"id":id,"team":team,"bot":bot,"cls":"knight","up":false,"hp":60.0,"max_hp":60.0,
		"pos":Vector2.ZERO,"face":0.0,"move":Vector2.ZERO,"state":"idle","t":0.0,"atk":"","cd_dodge":0.0,
		"cd_ability":0.0,"stun":0.0,"respawn_at":0.0,"kills":0,"deaths":0,
		"dodge_dir":Vector2.ZERO,"lunge_hit":false,
		"unstick":0.0,"unstick_dir":Vector2.ZERO,"stuck_t":0.0,"last_pos":Vector2.ZERO,
		"beam":"", "beam2":"", "drain_acc":0.0, "beam_until":0.0, "block_until":0.0, "whirl_until":0.0, "whirl_t":0.0, "gate_dmg":0.0,
		"path":PackedVector2Array(), "path_i":0, "path_goal":Vector2(INF, INF), "path_at":-10.0, "path_ver":-1, "think_at":0.0}

func stat(u: Dictionary, key: String) -> Variant:
	var base: Variant = CLASSES[u.cls][key]
	if moba != null:
		return moba.stat(u, key, base)
	if key in ["hp","dmg"]:
		return float(base) * (1.25 if u.up else 1.0)
	return base

func _set_class(u: Dictionary, cls: String, up: bool) -> void:
	# a unit as another class, its health kept in proportion (tests and tools; a 5v5 hero's comes from moba.gd)
	var ratio: float = u.hp / maxf(1.0, u.max_hp)
	u.cls = cls
	u.up = up
	u.max_hp = float(stat(u,"hp"))
	u.hp = maxf(1.0, u.max_hp * maxf(ratio, 0.75))
	u.cd_ability = 0.0

func class_label(u: Dictionary) -> String:
	if moba != null and u.has("kq"):
		return str(moba.HEROES[str(u.hid)].name)    # 0.31.168: a new hero is himself, not his class's frame
	return UPGRADE_NAME.get(u.cls,"") if u.up else str(CLASSES[u.cls].name)


func _respawn(u: Dictionary, first := false) -> void:
	var sp := spawn(u.team)
	u.pos = sp + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * (Keep.FOUNTAIN_R - 0.6)   # (0.31.165: round the fountain)
	u.face = PI if u.team == 0 else 0.0
	u.max_hp = float(stat(u,"hp"))
	u.hp = u.max_hp
	u.state = "idle"
	u.t = 0.0
	u.stun = 0.0
	u.path = PackedVector2Array()
	if not first:
		_event("spawn", {"id":u.id})

func _event(kind: String, data: Dictionary) -> void:
	data["k"] = kind
	data["at"] = time
	events.append(data)

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

func nearest_enemy(u: Dictionary, max_d: float, prefer_front := false) -> Dictionary:
	var best := {}
	var best_score := INF
	var fwd := dir_of(u.face)
	var ranged: bool = CLASSES[u.cls].ranged
	for o in units:
		if o.team == u.team or not alive(o):
			continue
		var off: Vector2 = o.pos - u.pos
		var d := off.length()
		if d > max_d:
			continue
		if vanished(o) and d > 1.6:
			continue                           # 0.31.32: an Assassin in Vanish can't be picked out (until he's on you)
		if moba != null and not moba.can_see(int(u.team), o):
			continue                           # 0.31.158 5V5: in the fog (or hidden in brush) -- not to be picked out
		var s := d
		if prefer_front and d > 0.01:
			s += (1.0 - fwd.dot(off / d)) * 2.0
		# 0.31.25 (smarter bots): a wounded enemy is worth a few metres' detour; archers and mages go for the
		# enemy's healers and casters first
		if u.bot:
			if o.hp < o.max_hp * 0.35:
				s -= 3.0
			if ranged and o.cls in ["priest", "mage"]:
				s -= 2.0
		if s < best_score:
			best_score = s
			best = o
	return best

# ---------- input (from HUD or bot brain) ----------
func act(id: String, action: String, arg: Variant = null) -> bool:
	var u: Dictionary = by_id.get(id, {})
	if not u.is_empty() and not ended and moba != null and action in ["shop_buy", "shop_sell"]:
		return moba.buy(u, str(arg)) if action == "shop_buy" else moba.sell(u, int(arg))     # (0.31.157: down too)
	if u.is_empty() or ended or not alive(u):
		return false
	match action:
		"attack":
			return _beam(u) if u.cls == "priest" else _start_attack(u, "attack")
		"ability":
			if moba != null and u.has("kq"):
				return moba.kits.spell(u, "q")           # 0.31.168: a new hero's Q is a kit spell
			match ability_of(u):
				"block": return _block(u)
				"whirlwind": return _whirl(u)
				"hammer": return _throw_hammer(u)
				"resurrect": return _resurrect(u)
				"vanish": return _vanish(u)
				_: return _start_attack(u, "ability")
		"block":                                     # 0.31.61 (Kevin): the Crusader blocks too, on its own button
			return _block(u) if u.cls == "knight" else false
		"dodge": return _dodge(u)
		"pick":                                      # 0.31.155: a 5v5 hero's level-up choice (arg: 0-2)
			return moba != null and moba.pick(u, int(arg))
		"ult":                                       # 0.31.157 5V5: the ultimate (level 6)
			return moba != null and moba.ult(u)
		"spell":                                     # 0.31.167 5V5: W or E (arg: "w" / "e")
			return moba != null and moba.kits.spell(u, str(arg))
		"ward":                                      # 0.31.158 5V5: a ward at your feet (the fog of war)
			return moba != null and moba.ward(u)
		"shop_buy":                                  # 0.31.157 5V5: an item (arg: its id) -- in your castle or while down
			return moba != null and moba.buy(u, str(arg))
		"shop_sell":                                 # (arg: the slot)
			return moba != null and moba.sell(u, int(arg))
	return false

func set_move(id: String, v: Vector2) -> void:
	var u: Dictionary = by_id.get(id, {})
	if not u.is_empty():
		u.move = v.limit_length(1.0)

func can_act(u: Dictionary) -> bool:
	return alive(u) and u.stun <= 0.0 and u.state in ["idle","move"]

func _aim(u: Dictionary, reach: float) -> void:
	var target := nearest_enemy(u, reach, true)
	u["aim_d"] = 0.0
	if not target.is_empty():
		u.face = angle_of(target.pos - u.pos)
		u["aim_d"] = u.pos.distance_to(target.pos)

const COMBO_GAP := 0.9

func _start_attack(u: Dictionary, kind: String, aim := true) -> bool:
	if kind == "ability" and moba != null and u.has("kq"):
		return moba.kits.spell(u, "q")               # 0.31.168: a new hero's Q (the bots' fights call this)
	if not can_act(u) or blocking(u) or whirling(u):
		return false
	if int(u.get("hammer_out", -1)) >= 0:
		return false                           # the Crusader's hammer is still flying
	if kind == "ability":
		if CLASSES[u.cls].ability == "" or u.cd_ability > 0.0:
			return false
		u.cd_ability = float(CLASSES[u.cls].ab_cd)
	var reach := float(stat(u,"range")) * (1.0 if CLASSES[u.cls].ranged else 1.9)
	if kind == "ability" and str(CLASSES[u.cls].ability) == "lunge":
		reach = 6.0
	if aim:
		_aim(u, reach)
	u.state = "wind"
	u.atk = kind
	u.t = float(stat(u,"windup")) * (1.3 if kind == "ability" else 1.0)
	u.lunge_hit = false
	# 0.31.62 (Kevin): melee swings run in a three-hit combo -- another attack within COMBO_GAP of the last one's end
	# is the next swing; the view picks the animation from it. Damage is the same on every swing.
	var combo := 0
	if kind == "attack":
		if time - float(u.get("combo_t", -99.0)) <= float(stat(u, "windup")) + float(stat(u, "recover")) + COMBO_GAP:
			combo = (int(u.get("combo", -1)) + 1) % 3
		u["combo"] = combo
		u["combo_t"] = time
	_event("attack", {"id":u.id,"kind":kind,"ability":CLASSES[u.cls].ability if kind == "ability" else "", "combo":combo})
	return true

# ---------- knight block / berserker whirlwind ----------
func ability_of(u: Dictionary) -> String:
	if u.has("kq"):
		return str(u.kq)                         # 0.31.168: a new hero's Q (moba_kits.gd)
	if u.cls == "barbarian" and u.up:
		return "whirlwind"
	if u.cls == "knight" and u.up:
		return "hammer"
	if u.cls == "priest" and u.up:
		return "resurrect"
	if u.cls == "rogue" and u.up:
		return "vanish"                         # 0.31.32: the Assassin
	if u.cls == "ranger" and u.up:
		return "pierce"                         # 0.31.32: the Sniper
	if u.cls == "mage" and u.up:
		return "meteor"                         # 0.31.32: the Archmage                     # the Necromancer (High Priest until 0.31.2; Resurrection 0.31.1, Kevin)                        # the Crusader (0.30.5, Kevin): Hammer Throw instead of the shield
	return str(CLASSES[u.cls].ability)

func blocking(u: Dictionary) -> bool:
	return u.cls == "knight" and time < float(u.get("block_until", 0.0)) and alive(u)

func whirling(u: Dictionary) -> bool:
	return time < float(u.get("whirl_until", 0.0)) and alive(u)

func shield_seg(k: Dictionary) -> Array:
	var f := Vector2(sin(k.face), cos(k.face))
	var c: Vector2 = k.pos + f * SHIELD_FWD
	var side := Vector2(f.y, -f.x) * SHIELD_HALF * (1.4 if k.up else 1.0)
	return [c - side, c + side]

static func _seg_cross(p1: Vector2, p2: Vector2, q1: Vector2, q2: Vector2) -> bool:
	var d1 := (p2 - p1).cross(q1 - p1)
	var d2 := (p2 - p1).cross(q2 - p1)
	var d3 := (q2 - q1).cross(p1 - q1)
	var d4 := (q2 - q1).cross(p2 - q1)
	return d1 * d2 < 0.0 and d3 * d4 < 0.0

func shield_blocks(from: Vector2, dst: Dictionary) -> bool:
	# A hit from `from` on dst is stopped by a raised shield of dst's team: the knight itself from
	# the front, or anyone the shield stands between.
	for k in _blockers:
		if int(k.team) != int(dst.team):
			continue
		if k == dst:
			if Vector2(sin(k.face), cos(k.face)).dot(from - k.pos) > 0.0:
				return true
			continue
		var s: Array = shield_seg(k)
		if _seg_cross(from, dst.pos, s[0], s[1]):
			return true
	return false

func _block(u: Dictionary) -> bool:
	if u.has("kq"):
		return false                           # (0.31.168: a new hero on a Knight's frame -- the Dragoon -- has no shield)
	if not alive(u) or u.stun > 0.0 or u.state in ["wind", "recover", "dodge"]:
		return false
	if not blocking(u):
		_event("block_up", {"id":u.id})
	u.block_until = time + BLOCK_HOLD
	return true

func _whirl(u: Dictionary) -> bool:
	if u.cd_ability > 0.0 or not can_act(u):
		return false
	u.whirl_until = time + WHIRL_TIME
	u.whirl_t = 0.0
	u.cd_ability = WHIRL_CD
	_event("whirl", {"id":u.id})
	return true

func _step_whirl(u: Dictionary, dt: float) -> void:
	if not whirling(u):
		return
	if u.stun > 0.0:
		u.whirl_until = 0.0
		return
	u.face += dt * 26.0                        # ~4 turns a second (the view reads the face)
	u.whirl_t -= dt
	if u.whirl_t > 0.0:
		return
	u.whirl_t = WHIRL_TICK
	var dmg := float(stat(u, "dmg")) * WHIRL_DMG
	for o in units:
		if o.team != u.team and alive(o) and o.pos.distance_to(u.pos) <= WHIRL_R:
			_damage(u, o, dmg)
	for g in gates:
		if g.team != u.team and gate_blocks(g) and u.pos.distance_to(seg_closest(u.pos, g.a, g.b)) <= WHIRL_R:
			_damage_gate(u, g, dmg * float(CLASSES[u.cls].gate))

# ---------- priest beam ----------
func beam_target(u: Dictionary) -> Dictionary:
	# The nearest injured ally in reach, else the nearest ally in reach (the beam shows, heals 0).
	var reach := float(CLASSES["priest"].range)
	var best := {}
	var bd := INF
	var any := {}
	var ad := INF
	for a in units:
		if a.id == u.id or a.team != u.team or not alive(a):
			continue
		var d: float = u.pos.distance_to(a.pos)
		if d > reach:
			continue
		if d < ad:
			ad = d
			any = a
		if a.hp < a.max_hp - 0.5 and d < bd:
			bd = d
			best = a
	return best if not best.is_empty() else any

func _beam(u: Dictionary) -> bool:
	if not alive(u) or u.stun > 0.0 or u.state in ["wind", "recover", "dodge"]:
		return false
	if is_necro(u):
		return _necro_beam(u)
	var cur: Dictionary = by_id.get(str(u.beam), {})
	# Keep a locked, still-injured target in reach; otherwise pick again.
	if cur.is_empty() or not alive(cur) or cur.hp >= cur.max_hp - 0.5 or u.pos.distance_to(cur.pos) > float(CLASSES["priest"].range) + 1.0:
		cur = beam_target(u)
	if cur.is_empty():
		u.beam = ""
		return false
	if str(u.beam) != str(cur.id):
		_event("beam", {"id":u.id, "to":cur.id})
	u.beam = cur.id
	u.beam_until = time + BEAM_HOLD
	u.face = angle_of(cur.pos - u.pos)
	return true

func _step_beam(u: Dictionary, dt: float) -> void:
	if str(u.beam) == "":
		return
	var t: Dictionary = by_id.get(str(u.beam), {})
	if time > u.beam_until or u.cls != "priest" or not alive(u) or t.is_empty() or not alive(t) \
			or u.pos.distance_to(t.pos) > float(CLASSES["priest"].range) + 1.0:
		u.beam = ""
		u.beam2 = ""
		return
	if is_necro(u):
		_step_drain(u, t, dt)
		return
	var rate := float(CLASSES["priest"].heal) * (1.4 if u.up else 1.0)
	_heal(u, t, rate * dt * _beam_share(t))

func _heal(by: Dictionary, t: Dictionary, amount: float) -> void:
	# Heal t; what an ally gets (not yourself) counts toward the healer's "healed" (0.31.87: the Merciful title).
	amount *= float(by.get("m_heal", 1.0))           # 0.31.157 5V5: the Holy Relic
	var before: float = t.hp
	t.hp = minf(t.max_hp, t.hp + amount)
	if by != t:
		by["healed"] = float(by.get("healed", 0.0)) + (t.hp - before)

func _dodge(u: Dictionary) -> bool:
	if not alive(u) or u.stun > 0.0 or u.cd_dodge > 0.0 or u.state in ["wind","dodge"]:
		return false
	var d: Vector2 = u.move if u.move.length() > 0.2 else dir_of(u.face)
	u.dodge_dir = d.normalized()
	u.face = angle_of(u.dodge_dir)
	u.state = "dodge"
	u.t = 0.3
	u.cd_dodge = 2.2
	_event("dodge", {"id":u.id})
	return true

static func in_castle(p: Vector2, team: int) -> bool:
	# Inside team's keep (0.31.165), in blue space.
	return Keep.inside(p if team == 0 else -p)

# ---------- damage ----------
func _damage(src: Dictionary, dst: Dictionary, amount: float, stun := 0.0) -> void:
	if not src.is_empty() and vanished(src):
		amount *= VANISH_STRIKE                   # 0.31.32: the first strike out of Vanish
		_unvanish(src)
	if vanished(dst):
		_unvanish(dst)
	if not alive(dst) or dst.state == "dodge":
		return
	if not _blockers.is_empty() and src.has("pos") and shield_blocks(src.pos, dst):
		_event("blocked", {"id":dst.id, "pos":dst.pos})
		return
	if moba != null:
		amount = moba.mod_damage(src, dst, amount)    # 0.31.157: ultimates, items, buffs (more dealt, less taken, UNDYING)
	dst.hp -= amount
	if moba != null:
		moba.on_damage(src, dst, amount)          # 0.31.155: lifesteal; who hit a hero (the towers' and minions' call for help)
	if stun > 0.0:
		dst.stun = maxf(dst.stun, stun)
	_event("hit", {"id":dst.id,"by":src.get("id",""),"dmg":int(round(amount))})
	if src.has("pos") and str(src.get("id", "")) != "" and int(src.get("team", -1)) != int(dst.team):
		dst["hurt_by"] = str(src.id)                  # 0.31.27: bots answer whoever is hurting them (or a friend nearby)
		dst["hurt_at"] = time
	if dst.hp <= 0.0:
		_kill(src, dst)
	_next_push = Vector3.ZERO

func _kill(src: Dictionary, dst: Dictionary) -> void:
	dst["hammer_out"] = -1                     # its hammer, if out, drops (_step_hammer)
	dst.hp = 0.0
	dst.state = "dead"
	dst.beam = ""
	dst.beam2 = ""
	dst.block_until = 0.0
	dst.whirl_until = 0.0
	# which way the blow threw him (x, up, z in m/s): melee and beams push straight away from the killer
	var push := _next_push
	_next_push = Vector3.ZERO
	if push == Vector3.ZERO:
		var away := Vector2.ZERO
		if src.has("pos"):
			away = (dst.pos as Vector2) - (src.pos as Vector2)
		away = away.normalized() if away.length() > 0.01 else dir_of(float(dst.face) + PI)
		push = Vector3(away.x * 3.2, 1.6, away.y * 3.2)
	dst["death_push"] = push
	if moba != null:
		moba.on_kill(src, dst)                     # 0.31.155: heroes come back as themselves, minions go
		return
	# (no 5v5 -- the tests' plain sims: counted, back after RESPAWN_TIME)
	_multi_kill(src, dst)
	dst["died_at"] = time
	dst.respawn_at = time + RESPAWN_TIME
	dst.deaths += 1
	if not src.is_empty() and src.has("team"):
		kills[src.team] += 1
		if src.has("kills"):
			src.kills += 1
	_event("death", {"id":dst.id,"by":src.get("id",""), "push":[snappedf(push.x, 0.01), snappedf(push.y, 0.01), snappedf(push.z, 0.01)]})

func _damage_gate(src: Dictionary, g: Dictionary, amount: float) -> void:
	if not gate_blocks(g):
		return
	if moba != null and (not moba.gate_open(g) or int(src.get("team", 0)) > 1):
		return                                    # 0.31.155: a gate behind standing towers can't be touched (0.31.157: nor by a monster)
	if moba != null:
		amount *= moba.gate_mult(src)             # 0.31.157: minions hit gates harder
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

func _melee(u: Dictionary, reach: float, arc: float, dmg: float, stun := 0.0) -> int:
	var fwd := dir_of(u.face)
	var hits := 0
	var spare_mon: bool = moba != null and bool(u.get("minion", false)) and not bool(u.get("summon", false))
	for o in units:
		if o.team == u.team or not alive(o):
			continue
		if spare_mon and int(o.team) > 1:
			continue                                 # (0.31.157: lane minions leave the jungle's monsters alone)
		var off: Vector2 = o.pos - u.pos
		var d := off.length()
		if d > reach + UNIT_R:
			continue
		if arc > -1.0 and d > 0.3 and fwd.dot(off / d) < arc:
			continue
		_damage(u, o, dmg, stun)
		hits += 1
	# Swings also land on an enemy gate in reach.
	for g in gates:
		if g.team == u.team or not gate_blocks(g):
			continue
		var cp := seg_closest(u.pos, g.a, g.b)
		var off2: Vector2 = cp - u.pos
		var d2 := off2.length()
		if d2 > reach + float(g.get("r", WALL_R)) + 0.3:
			continue
		if arc > -1.0 and d2 > 0.3 and fwd.dot(off2 / d2) < arc - 0.2:
			continue
		_damage_gate(u, g, dmg * float(CLASSES[u.cls].gate))
		hits += 1
	if moba != null and str(u.get("atk", "")) == "attack":
		hits += moba.melee_towers(u, reach, arc, dmg)    # 0.31.155: basic attacks hit towers
	return hits

func _shoot(u: Dictionary, angle: float, dmg: float, aoe: float, speed: float, reach: float) -> void:
	var d := dir_of(angle)
	projectiles.append({"id":_next_proj,"team":u.team,"owner":u.id,"pos":u.pos + d*0.6,"from":u.pos,"vel":d*speed,
		"dmg":dmg,"aoe":aoe,"life":reach/speed,"kind":_shot_kind(u, aoe), "basic":u.atk == "attack",
		"gate_mult":float(CLASSES[u.cls].gate),
		"high":height_at(u.pos) >= 1.5})              # (shot from high ground: over walls and gates)
	_event("proj", {"pid":_next_proj,"kind":_shot_kind(u, aoe)})
	_next_proj += 1

func _shot_kind(u: Dictionary, aoe: float) -> String:
	# a fireball if it splashes, else an arrow -- 0.31.168: or the hero's own (a bolt, a musket ball, a thorn)
	return str(u.get("shot", "fire" if aoe > 0.0 else "arrow"))

func _resolve_attack(u: Dictionary) -> void:
	var c: Dictionary = CLASSES[u.cls]
	var dmg := float(stat(u,"dmg"))
	if u.atk == "attack":
		if moba != null:
			dmg *= moba.kits.on_basic(u)               # 0.31.167: TUMBLE's shot
		if c.ranged:
			if float(c.proj_speed) <= 0.0:
				return                                 # 0.31.157: a Priest's "attack" is his beam -- no shot (a bot's swing
				                                       # made a still, endless arrow: hundreds piled up in a 5v5 match)
			# 0.31.5 balance: the Mage's fireball does 10 % less (MAGE_BOLT); her nova keeps its damage and size.
			# (0.31.168: stat() -- the new heroes' own range, splash and shot speed)
			_shoot(u, u.face, dmg * (MAGE_BOLT if u.cls == "mage" else 1.0), float(stat(u, "aoe")), float(stat(u, "proj_speed")),
				float(stat(u, "range")))
		else:
			_basic_by = str(u.id)                      # (0.31.167: the hit is a basic attack -- POISON BLADES)
			_melee(u, float(stat(u, "range")), float(stat(u, "arc")), dmg)
			_basic_by = ""
		return
	match ability_of(u):
		"pierce":
			_pierce_shot(u, dmg)
			u.cd_ability = PIERCE_CD
			return
		"meteor":
			_call_meteor(u, dmg)
			u.cd_ability = METEOR_CD
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
			_melee(u, NOVA_R, -2.0, dmg*1.4)
			_event("nova", {"id":u.id})
		"sanctuary":
			var amount := SANCTUARY_HEAL * (1.4 if u.up else 1.0)
			for a in units:
				if alive(a) and a.team == u.team and a.pos.distance_to(u.pos) <= SANCTUARY_R \
						and time - float(a.get("sanct_t", -INF)) >= SANCT_ONCE:
					a["sanct_t"] = time
					_heal(u, a, amount)
			_event("sanctuary", {"id":u.id, "team":u.team})

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
	var t0 := Time.get_ticks_usec() if profile else 0
	# Each bot thinks every AI_EVERY seconds, on its own schedule: 0.31.78 spread over the ticks (all 31 thought on the
	# same tick before -- a 10-20 ms spike every 0.15 s, with the path searches, where the other ticks took 2 ms).
	for u in units:
		if u.bot and time >= float(u.think_at):
			u.think_at = time + AI_EVERY
			_think(u)
		elif u.bot and u.cls == "knight" and not projectiles.is_empty() and alive(u) and not blocking(u) and not u.has("kq"):
			_shield_reflex(u)                        # (a Knight or a Crusader: the shield between decisions too)
	if profile: t0 = _p("think", t0)
	_blockers = units.filter(func(k): return blocking(k))
	for u in units:
		_step_unit(u, dt)
	if profile: t0 = _p("units", t0)
	_separate()
	if profile: t0 = _p("separate", t0)
	_step_projectiles(dt)
	if profile: t0 = _p("projectiles", t0)
	_step_world(dt)
	if profile: t0 = _p("world", t0)
	if moba != null:
		moba.step(dt)
		if profile: t0 = _p("moba", t0)
	if time >= match_time:
		_finish("time")

func _step_unit(u: Dictionary, dt: float) -> void:
	if u.state == "dead":
		if time >= u.respawn_at:
			_respawn(u)
		return
	if u.state == "idle" and u.has("mon") and u.stun <= 0.0 and (u.move as Vector2) == Vector2.ZERO:
		# 0.31.165: a jungle monster standing at home (most of the Rift's 37, most of the time): nothing to step but
		# its recharges
		u.cd_dodge = maxf(0.0, u.cd_dodge - dt)
		u.cd_ability = maxf(0.0, u.cd_ability - dt)
		return
	u.cd_dodge = maxf(0.0, u.cd_dodge - dt)
	u.cd_ability = maxf(0.0, u.cd_ability - dt * float(u.get("m_cdr", 1.0)))     # (0.31.155: a 5v5 hero's faster recharge)
	_step_beam(u, dt)
	_step_whirl(u, dt)
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
			if not _net_moves(u):
				u.pos += u.move * speed * 0.25 * dt
			if u.t <= 0.0:
				u.state = "idle"
			return
		"dodge":
			u.t -= dt
			if not _net_moves(u):
				u.pos += u.dodge_dir * DODGE_SPEED * dt
			if u.t <= 0.0:
				u.state = "idle"
			return
		"dash":                                       # 0.31.167 5V5: a W/E's charge, leap or roll (moba_kits.gd)
			if moba != null:
				moba.kits.step_dash(u, dt)
			else:
				u.state = "idle"
			return
	var mult := move_mult(u)
	var beaming: bool = str(u.beam) != ""
	var shield_up := blocking(u)
	if u.move.length() > 0.08:
		if _net_moves(u):
			pass                                      # the player's phone moves it (validated, see server)
		else:
			u.pos += u.move * speed * mult * dt
		if _net_moves(u):
			pass                                      # facing comes from the phone too
		elif whirling(u):
			pass                                      # spinning: _step_whirl turns the face
		elif shield_up:
			u.face = lerp_angle(u.face, angle_of(u.move), minf(1.0, dt*2.5))   # a slow turn behind the shield
		elif not beaming:                             # a channelling priest keeps facing the target
			u.face = lerp_angle(u.face, angle_of(u.move), minf(1.0, dt*14.0))
		u.state = "move"
	else:
		u.state = "idle"

# ---------- client-side prediction (0.18.4, Kevin: "on the server the controls lag") ----------
# Online, the player's phone moves its own unit immediately with the same code (predict_step) and
# sends the position; the server takes it if it's plausible (siege_server.gd) instead of moving the
# unit itself. Server-driven states (dead, stunned, lunging) stay server-side.
const DODGE_SPEED := 13.0

static func water_depth(p: Vector2) -> float:
	# How far the river's surface is above the ground here (0 on land and on the bridges, ~0.5 m mid-channel).
	# Only within the river's band (Round 39, Kevin: "movement slows down in the dungeon like there is water"): the
	# dungeon floor (-1.6 m) is below the waterline, so it counted as 1.15 m of water -- wading speed, river nav
	# cost, no blood, splashes.
	if Land.river_off(p) > 1.6:                    # (lake-aware since 0.30.0; the island is dry land)
		return 0.0
	return maxf(0.0, Land.WATER_Y - height_at(p))

func move_mult(u: Dictionary, mult := 1.0) -> float:
	# Speed multipliers for free movement. Wading (Round 33): slower the deeper it gets, down to WATER_MOVE past ~0.35 m.
	var wd := water_depth(u.pos)
	if wd > 0.0:
		mult *= lerpf(1.0, WATER_MOVE, clampf(wd / 0.35, 0.0, 1.0))
	if str(u.beam) != "":
		mult = minf(mult, BEAM_MOVE)
	if blocking(u):
		mult = minf(mult, BLOCK_MOVE)
	return mult

func client_drivable(u: Dictionary) -> bool:
	if not alive(u) or u.stun > 0.0:
		return false
	if u.state == "wind" and CLASSES[u.cls].ability == "lunge" and u.atk == "ability":
		return false
	return u.state in ["idle", "move", "recover", "dodge", "wind"]

func _net_moves(u: Dictionary) -> bool:
	return bool(u.get("net_driven", false)) and client_drivable(u)

func predict_step(u: Dictionary, move: Vector2, dt: float) -> void:
	# The phone's copy of _step_unit's movement for its own unit (same speeds, same collision).
	var speed := float(stat(u, "speed"))
	match str(u.state):
		"dodge":
			u.pos += u.dodge_dir * DODGE_SPEED * dt
			u.t -= dt
			if u.t <= 0.0:
				u.state = "idle"
		"recover":
			u.pos += move * speed * 0.25 * dt
			u.t -= dt
			if u.t <= 0.0:
				u.state = "idle"
		"wind":
			u.t -= dt                               # a locally predicted swing: animation only
			if u.t <= 0.0:
				u.state = "recover"
				u.t = float(stat(u, "recover"))
		_:
			if move.length() > 0.08:
				u.pos += move * speed * move_mult(u) * dt
				if not whirling(u) and str(u.beam) == "":
					u.face = lerp_angle(u.face, angle_of(move), minf(1.0, dt * (2.5 if blocking(u) else 14.0)))
				u.state = "move"
			else:
				u.state = "idle"
	u.pos = _clamp_to_field(_push_out(_clamp_to_field(u.pos), UNIT_R, u.team))

func accept_client_pos(u: Dictionary, p: Vector2, face: float, elapsed: float) -> bool:
	# Server side: take a phone-reported position if the unit could have got there (its speed,
	# or dodge speed, over the time since the last report, plus slack) and it isn't in a wall.
	if not client_drivable(u):
		return false
	var top := maxf(float(stat(u, "speed")) * move_mult(u), DODGE_SPEED if u.state == "dodge" else 0.0)
	if p.distance_to(u.pos) > top * clampf(elapsed, 0.0, 0.5) * 1.35 + 0.6:
		return false
	u.pos = _clamp_to_field(_push_out(_clamp_to_field(p), UNIT_R, u.team))
	u.face = face
	return true

func _blocked_point(p: Vector2, team: int, r: float) -> bool:
	for wi in _bucket_walls[_bucket(p)]:
		var w: Dictionary = walls[wi]
		if p.distance_to(seg_closest(p, w.a, w.b)) < w.r + r:
			return true
	for g in gates:
		if g.team != team and gate_blocks(g) and p.distance_to(seg_closest(p, g.a, g.b)) < float(g.get("r", WALL_R)) + r:
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
	# Walls one at a time, repeated while a pass still moves the unit: at a concave corner between
	# two segments, pushing off the second shoves it back into the first, and a dodging knight
	# (0.43 m per tick into a river-bank corner) stayed inside for the whole dodge (Round 12).
	for pass_i in 3:
		var before := p
		for wi in _bucket_walls[bi]:
			var w: Dictionary = walls[wi]
			p = _push_seg(p, w.a, w.b, w.r + r)
		if p.distance_squared_to(before) < 0.000001:
			break
	for g in gates:
		# Gates only stop the other team, and only while standing.
		if team != g.team and gate_blocks(g) and not lets_out(g, p):
			p = _push_seg(p, g.a, g.b, float(g.get("r", WALL_R)) + r)
	return p

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

var _po_cache := {}                         # unit id -> [the position its last push-out gave, _po_epoch then]
var _po_epoch := 0
var _po_tick := 0

const SEP_CELL := 0.9                # (UNIT_R * 2: two units that touch are in neighbouring cells)

func _separate() -> void:
	# Pairs of living units pushed apart (0.31.78: on packed arrays -- the 496 pair checks of a 16 v 16 went through
	# dictionary lookups each; same pushes, in the same order).
	var live: Array = []
	for u in units:
		if alive(u):
			live.append(u)
	var n := live.size()
	var pos := PackedVector2Array()
	pos.resize(n)
	for i in n:
		pos[i] = live[i].pos
	var r2 := UNIT_R * 2.0
	# 0.31.165 (the Rift's longer lanes keep ~75 units alive by 5:30, 130 late on; every pair was 2,800 checks a tick, and
	# 8,000): only the pairs in neighbouring SEP_CELL squares -- two units that touch are never further apart than one.
	# Same pushes, in the order each unit's neighbours were listed (by index).
	var cells := {}
	var keys: Array[Vector2i] = []
	keys.resize(n)
	for i in n:
		var k := Vector2i(floori(pos[i].x / SEP_CELL), floori(pos[i].y / SEP_CELL))
		keys[i] = k
		var lst = cells.get(k)
		if lst == null:
			cells[k] = PackedInt32Array([i])
		else:
			(lst as PackedInt32Array).append(i)
			cells[k] = lst
	for i in n:
		var pa := pos[i]
		var ck: Vector2i = keys[i]
		for dx in 3:
			for dy in 3:
				var lst = cells.get(Vector2i(ck.x + dx - 1, ck.y + dy - 1))
				if lst == null:
					continue
				for j in (lst as PackedInt32Array):
					if j <= i:
						continue
					var off := pos[j] - pa
					var dd := off.length_squared()                # (0.31.160: the square root only for the pairs that touch)
					if dd < r2 * r2 and dd > 0.00000001:
						var d := sqrt(dd)
						var push := off / d * (r2 - d) * 0.5
						pa -= push
						pos[j] += push
		pos[i] = pa
	for i in n:
		live[i].pos = pos[i]
	var tsp := Time.get_ticks_usec() if profile else 0
	# 0.31.160: a unit standing where its push-out last left it is skipped (most of a 5v5's -- the jungle's monsters, a
	# fighting wave -- stand still; the walls were half the separation's cost); everyone is re-checked once a second
	# and whenever a gate's state changes (_po_epoch)
	_po_tick += 1
	if _po_tick % 30 == 0:
		_po_epoch += 1
		_po_cache.clear()
	for u in units:
		if alive(u):
			var pc: Array = _po_cache.get(u.id, [])
			if not pc.is_empty() and int(pc[1]) == _po_epoch and (pc[0] as Vector2) == (u.pos as Vector2):
				continue
			# Clamp first: pushing a unit that is slightly past the field edge off a wall end can
			# send it diagonally, and clamping afterwards drops it back inside the wall.
			u.pos = _clamp_to_field(_push_out(_clamp_to_field(u.pos), UNIT_R, u.team))
			_po_cache[u.id] = [u.pos, _po_epoch]
	if profile: _p("sep.pushout", tsp)

func _step_projectiles(dt: float) -> void:
	if projectiles.is_empty():
		return
	# Each team's living units as packed positions, built once per tick: a projectile only checks
	# the other team, without dictionary lookups (was ~830 checks/tick through alive(); 1 ms/tick).
	# (Packed arrays are VALUES in Godot 4: appending through `tpos[t] as PackedVector2Array`
	# appended to a copy, so these stayed empty and arrows/bolts hit NO units from 0.16.0 to
	# 0.18.1. Build them as locals.)
	# (0.31.157: a third list for the 5v5 jungle's monsters, team 2 -- everyone's enemy)
	var pos0 := PackedVector2Array()
	var pos1 := PackedVector2Array()
	var pos2 := PackedVector2Array()
	var tunit := [[], [], []]
	for o in units:
		if alive(o):
			if o.team == 0:
				pos0.append(o.pos)
			elif o.team == 1:
				pos1.append(o.pos)
			else:
				pos2.append(o.pos)
			(tunit[clampi(int(o.team), 0, 2)] as Array).append(o)
	var tpos := [pos0, pos1, pos2]
	var hit_r2 := (UNIT_R + 0.25) * (UNIT_R + 0.25)
	for i in range(projectiles.size()-1, -1, -1):
		var p: Dictionary = projectiles[i]
		if str(p.kind) == "hammer":
			if _step_hammer(p, dt, tunit):
				projectiles.remove_at(i)
			continue
		var prev: Vector2 = p.pos
		p.pos += p.vel * dt
		var shielded := false
		for k in _blockers:
			if int(k.team) != int(p.team):
				var sg: Array = shield_seg(k)
				if _seg_cross(prev, p.pos, sg[0], sg[1]):
					shielded = true
					break
		if shielded:
			_event("blocked", {"pos":p.pos})
			_event("proj_end", {"pid":p.id, "pos":p.pos})
			projectiles.remove_at(i)
			continue
		p.life -= dt
		var hit := {}
		var et: int = (1 - int(p.team)) if int(p.team) >= 0 else -1
		var foe_teams: Array = [0, 1, 2] if et < 0 else ([et, 2] if int(p.team) <= 1 else [0, 1])
		if et >= 0 and moba != null and moba.lane_minion(str(p.owner)):
			foe_teams = [et]                         # (a lane minion's arrow flies past the jungle's monsters)
		# Swept test: the whole path since last tick (from the shooter on the first tick) against
		# each enemy's hit circle -- an arrow moves 0.73 m a tick, and checking only its new point
		# let glancing shots skip past a target. The nearest hit along the path wins.
		var from: Vector2 = p.get("from", prev)
		p.erase("from")
		var best_t := INF
		var impact := Vector2.ZERO
		for t in foe_teams:
			var arr: PackedVector2Array = tpos[t]
			for k in arr.size():
				var c: Vector2 = arr[k]
				var cp := seg_closest(c, from, p.pos)
				if c.distance_squared_to(cp) < hit_r2:
					var o: Dictionary = tunit[t][k]
					var along := from.distance_squared_to(cp)
					if alive(o) and along < best_t:        # another projectile may have killed it this tick
						best_t = along
						hit = o
						impact = cp
		if str(p.kind) == "pierce":
			# 0.31.32: the Sniper's shot goes through everyone in its path, each once
			var already: Array = p.get("hit", [])
			var owner_p: Dictionary = by_id.get(str(p.owner), {})
			for t2 in foe_teams:
				var arr2: PackedVector2Array = tpos[t2]
				for k2 in arr2.size():
					var o2: Dictionary = tunit[t2][k2]
					if already.has(o2.id) or not alive(o2):
						continue
					if arr2[k2].distance_squared_to(seg_closest(arr2[k2], from, p.pos)) < hit_r2:
						already.append(o2.id)
						_next_push = _push_along(p.vel, 4.0, 1.4)
						_damage(owner_p, o2, float(p.dmg), float(p.get("stun", 0.0)))     # (0.31.157: the Ranger's DEADEYE stuns)
						_event("pierce_hit", {"id":o2.id, "pos":o2.pos})
			p["hit"] = already
			hit = {}
		if not hit.is_empty():
			p.pos = impact                            # explode / stop where it struck, not past it
		var blocked := false
		var hit_gate := {}
		var hit_tw := -1
		var hit_kg := -1
		var pb := _bucket(p.pos)
		for oi in _bucket_obs_proj[pb]:
			var ob: Dictionary = obstacles[oi]
			if p.pos.distance_to(ob.p) < ob.r:
				blocked = true
				hit_tw = int(ob.get("tw", -1))           # 0.31.155: a 5v5 tower
				hit_kg = int(ob.get("kg", -1))           # 0.31.156: a 5v5 King (the heart)
				break
		if not blocked:
			# Pre-filtered at build time: ledges, cell bars, river banks and rails don't stop arrows or
			# fire (the old per-wall `kind in [...]` built an array every check: 1.2 ms/tick).
			var high: bool = bool(p.get("high", false))
			for wi in _bucket_walls_proj[pb]:
				var w: Dictionary = walls[wi]
				if high and (w.kind == "wall" or w.kind == "backwall"):
					continue                           # over the parapet
				if p.pos.distance_to(seg_closest(p.pos, w.a, w.b)) < w.r * 0.8:
					blocked = true
					break
		# Gates only exist in the keeps' walls (0.31.165: a ring Keep.R round each keep's middle): skip the check
		# anywhere else (it was ~30 % of the projectile step, measured).
		if not blocked and not bool(p.get("high", false)) and Land.keep_dist(p.pos) >= Keep.R - 3.0 and Land.keep_dist(p.pos) <= Keep.R + 3.0:
			for g in gates:
				if g.team != p.team and gate_blocks(g) and p.pos.distance_to(seg_closest(p.pos, g.a, g.b)) < float(g.get("r", WALL_R)) * 0.8:
					hit_gate = g
					blocked = true
					break
		if hit.is_empty() and not blocked and p.life > 0.0 and absf(p.pos.x) < HALF_W + 2 and absf(p.pos.y) < HALF_L + 2:
			continue
		var owner: Dictionary = by_id.get(p.owner, {"team":p.team})
		var spell_p := p.has("spell")                  # (0.31.167: a W/E's shot: heroes and minions only)
		if not hit_gate.is_empty() and not spell_p:
			_damage_gate(owner, hit_gate, p.dmg * float(p.gate_mult))
		if hit_tw >= 0 and moba != null and hit.is_empty() and not spell_p:
			moba.hit_tower(owner, hit_tw, float(p.dmg))
		if hit_kg >= 0 and moba != null and hit.is_empty() and not spell_p:
			moba.hit_king(owner, hit_kg, float(p.dmg))
		_basic_by = str(p.owner) if bool(p.get("basic", false)) else ""
		if p.aoe > 0.0:
			if not hit.is_empty():
				_next_push = _push_along(p.vel, 3.6, 1.4)
				_damage(owner, hit, p.dmg)                 # the struck unit: full damage, always
			var spare_mon: bool = moba != null and moba.lane_minion(str(p.owner))     # (0.31.158: a siege minion's fire)
			for o in units:
				if o != hit and o.team != p.team and alive(o) and o.pos.distance_to(p.pos) <= p.aoe and not (spare_mon and int(o.team) > 1):
					_next_push = _push_from(p.pos, o.pos, 4.0, 2.4)
					_damage(owner, o, p.dmg * 0.6)
			_event("boom", {"pos":p.pos})
		elif not hit.is_empty():
			_next_push = _push_along(p.vel, 3.2, 1.2)
			_damage(owner, hit, p.dmg, float(p.get("stun", 0.0)))      # (0.31.167: SNARE ARROW roots)
			if spell_p and moba != null:
				moba.kits.proj_hit(p, hit)
		_basic_by = ""
		_event("proj_end", {"pid":p.id, "pos":p.pos})      # pos = the impact point (clients fly it there)
		projectiles.remove_at(i)

var _gate_tick := 0

func _step_world(dt: float) -> void:
	var tw0 := Time.get_ticks_usec() if profile else 0
	# Gates swing open for allies nearby (visual state). (0.31.160: whether a gate swings open -- its look and sound
	# only; gate_blocks doesn't use it -- every third tick)
	_gate_tick += 1
	var gate_look := _gate_tick % 3 == 0
	for g in gates:
		if not gate_look:
			continue
		var open := false
		if gate_blocks(g):
			# (0.31.165: in a 5v5 only the units near it -- six gates, 80-130 units)
			var near: Array = moba.units_near(g.c, GATE_OPEN_RADIUS) if moba != null else units
			for u in near:
				if u.team == g.team and alive(u) and u.pos.distance_to(g.c) < GATE_OPEN_RADIUS:
					open = true
					break
			# It also swings open for an enemy walking out (lets_out).
			if not open and g.has("in"):
				for u in near:
					if u.team != g.team and alive(u) and lets_out(g, u.pos) and u.pos.distance_to(g.c) < GATE_OPEN_RADIUS:
						open = true
						break
		if open != g.open:
			g.open = open
			_event("gate_open" if open else "gate_close", {"gate":g.id, "team":g.team})
	if profile: tw0 = _p("w.gates", tw0)
	_step_meteors(dt)
	if profile: tw0 = _p("w.meteors", tw0)

func _finish(reason: String) -> void:
	ended = true
	end_reason = reason
	if score[0] != score[1]:
		winner = 0 if score[0] > score[1] else 1
	elif moba != null and moba.tiebreak() >= 0:
		winner = moba.tiebreak()                   # 0.31.156: time's up -- more done to their King, then their towers, then KOs
	elif kills[0] != kills[1]:
		winner = 0 if kills[0] > kills[1] else 1
	else:
		winner = -1
	_event("end", {"winner":winner,"reason":reason})

func setup_moba(hero: String, seed_value: int) -> void:
	# 0.31.155 5V5: after setup(5, ...): you (hero) and four bot heroes against five
	moba = Moba.new()
	moba.begin(self, hero, seed_value)

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

func _unstick_check(u: Dictionary) -> void:
	# If a bot wanted to move but barely did, sidestep for a moment.
	u.unstick = maxf(0.0, u.unstick - AI_EVERY)
	if u.move.length() > 0.1 and u.pos.distance_to(u.last_pos) < 0.1:
		u.stuck_t += AI_EVERY
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
	if moba != null:
		moba.think(u)                              # 0.31.155: heroes and minions

func _think_priest(u: Dictionary) -> bool:
	# Priest bots: go to the most hurt ally close by and beam them; true if that's what it did.
	if ability_of(u) == "resurrect" and u.cd_ability <= 0.0 and not resurrect_target(u).is_empty():
		u.move = Vector2.ZERO
		return _resurrect(u)
	if is_necro(u):
		# The Necromancer drains the nearest enemy in reach (healing himself and an ally); closes in on one nearby.
		var reach := float(CLASSES["priest"].range)
		var foe := nearest_enemy(u, reach)
		if not foe.is_empty():
			u.move = Vector2.ZERO
			return _beam(u)
		var near := nearest_enemy(u, 16.0)
		if not near.is_empty():
			_nav_to(u, near.pos, reach * 0.8)
			return true
		return false
	var best := {}
	var worst := 0.98
	for a in units:
		if a.id == u.id or a.team != u.team or not alive(a):
			continue
		var d: float = u.pos.distance_to(a.pos)
		var ratio: float = a.hp / maxf(1.0, a.max_hp)
		if d <= 16.0 and ratio < worst:
			worst = ratio
			best = a
	if best.is_empty():
		return false
	if u.pos.distance_to(best.pos) > float(CLASSES["priest"].range) * 0.7:
		_nav_to(u, best.pos, 1.0)
	else:
		u.move = Vector2.ZERO
	_beam(u)
	var near := 0
	for a in units:
		if a.team == u.team and alive(a) and a.pos.distance_to(u.pos) <= SANCTUARY_R and a.hp < a.max_hp * 0.7:
			near += 1
	if near >= 2 and ability_of(u) == "sanctuary":
		_start_attack(u, "ability")
	return true

func _shield_reflex(u: Dictionary) -> bool:
	# The shield up against an enemy shot that will pass within 1.3 m in the next 0.7 s (it covers allies behind too),
	# unless an enemy is at arm's length and we're healthy (then swing). 0.31.78: checked every tick for shield-bearing
	# bots (step), not only when they think: an arrow is in the air for 0.1-0.2 s, less than the 0.15 s between a bot's
	# decisions, so whether one was blocked depended on where the bot's decisions fell between the archer's.
	var incoming := Vector2.ZERO
	var soonest := 0.7
	for p in projectiles:
		if int(p.team) == u.team:
			continue
		var v: Vector2 = p.vel
		var vv := v.length_squared()
		if vv < 0.01:
			continue
		var t: float = (u.pos - (p.pos as Vector2)).dot(v) / vv          # time of closest approach
		if t < 0.0 or t > soonest:
			continue
		if ((p.pos as Vector2) + v * t).distance_to(u.pos) < 1.3:
			soonest = t
			incoming = -v.normalized()
	if incoming == Vector2.ZERO:
		return false
	if u.hp >= u.max_hp * 0.5 and not nearest_enemy(u, float(stat(u, "range")) + UNIT_R + 0.3).is_empty():
		return false
	u.face = angle_of(incoming)
	_block(u)
	return true

func _fight(u: Dictionary, foe: Dictionary) -> void:
	var c: Dictionary = CLASSES[u.cls]
	var d: float = u.pos.distance_to(foe.pos)
	if u.bot and u.up and u.cls in ["rogue", "ranger", "mage"] and _bot_upgrade_ability(u, foe):
		return
	var reach := float(stat(u, "range"))           # (0.31.168: a new hero's own)
	var kq := u.has("kq")                          # (0.31.168: his Q is cast by the kit's bot rules, not at random here)
	if c.ranged:
		if d < reach * 0.45:
			u.move = (u.pos - foe.pos).normalized()
		elif d > reach * 0.85:
			_nav_to(u, foe.pos, 0.5)
		else:
			u.move = Vector2.ZERO
		if d <= reach * 0.9:
			u.face = angle_of(foe.pos - u.pos)
			var nova_now: bool = str(c.ability) == "nova" and _melee_count(u, NOVA_R) >= 2      # 0.31.26: a burst, not a single-target nova
			if not kq and u.cd_ability <= 0.0 and (nova_now or (str(c.ability) != "nova" and rng.randf() < 0.35)):
				_start_attack(u, "ability")
			else:
				_start_attack(u, "attack")
		return
	if d <= reach + UNIT_R + 0.1:
		u.move = Vector2.ZERO
		u.face = angle_of(foe.pos - u.pos)
		var ab := str(c.ability)
		var crowd := _melee_count(u, 2.8)
		if not kq and u.cd_ability <= 0.0 and ((ab == "spin" and crowd >= 2) or ab == "bash" or rng.randf() < 0.3):
			_start_attack(u, "ability")
		else:
			_start_attack(u, "attack")
		return
	if not kq and str(c.ability) == "lunge" and d < 5.5 and u.cd_ability <= 0.0:
		u.face = angle_of(foe.pos - u.pos)
		_start_attack(u, "ability")
		return
	_nav_to(u, foe.pos, reach * 0.8)

func _melee_count(u: Dictionary, r: float) -> int:
	var n := 0
	for o in units:
		if o.team != u.team and alive(o) and o.pos.distance_to(u.pos) <= r:
			n += 1
	return n


# ---------- the Crusader's Hammer Throw (0.30.5, Kevin: the Knight's upgrade) ----------
# The hammer flies HAMMER_RANGE straight ahead through everyone in its path, then comes back to wherever the
# Crusader is now, hitting each enemy once going out and once coming back (one swing's damage each time). Walls
# and gates turn it round early. No swinging while it is out; not from a tower's deck (only bows and spells there).
const HAMMER_RANGE := 9.0
const HAMMER_SPEED := 17.0
const HAMMER_CD := 10.0
const HAMMER_HIT_R := 0.55

func _throw_hammer(u: Dictionary) -> bool:
	if not alive(u) or u.stun > 0.0 or u.cd_ability > 0.0 or u.state in ["wind", "dodge"] or int(u.get("hammer_out", -1)) >= 0:
		return false
	_aim(u, HAMMER_RANGE)
	var d := dir_of(u.face)
	var id := _next_proj
	projectiles.append({"id":id, "team":u.team, "owner":u.id, "pos":u.pos + d * 0.6, "from":u.pos, "vel":d * HAMMER_SPEED,
		"dmg":float(stat(u, "dmg")), "aoe":0.0, "life":99.0, "kind":"hammer", "gate_mult":0.0, "high":false,
		"out":true, "trav":0.0, "hit":[]})
	_event("proj", {"pid":id, "kind":"hammer"})
	_next_proj += 1
	u["hammer_out"] = id
	u.cd_ability = HAMMER_CD
	u.state = "recover"
	u.t = 0.25
	_event("attack", {"id":u.id, "kind":"ability", "ability":"hammer"})
	return true

func _step_hammer(p: Dictionary, dt: float, tunit: Array) -> bool:
	# True when the hammer is done (back in hand, or its thrower fell).
	var owner: Dictionary = by_id.get(p.owner, {})
	if owner.is_empty() or not alive(owner) or int(owner.get("hammer_out", -1)) != int(p.id):
		return true
	var prev: Vector2 = p.pos
	if bool(p.out):
		p.pos += (p.vel as Vector2) * dt
		p.trav = float(p.trav) + (p.vel as Vector2).length() * dt
		if float(p.trav) >= HAMMER_RANGE or _blocked_point(p.pos, int(p.team), 0.15) \
				or absf((p.pos as Vector2).x) > HALF_W or absf((p.pos as Vector2).y) > HALF_L:
			p.pos = prev if _blocked_point(p.pos, int(p.team), 0.15) else p.pos
			p.out = false
			p.hit = []                             # on the way back everyone can be hit again
	else:
		var to: Vector2 = (owner.pos as Vector2) - (p.pos as Vector2)
		var step := HAMMER_SPEED * dt
		if to.length() <= maxf(step, 0.7):
			owner["hammer_out"] = -1
			return true
		p.vel = to.normalized() * HAMMER_SPEED
		p.pos += (p.vel as Vector2) * dt
	var r := UNIT_R + HAMMER_HIT_R
	for o in (tunit[1 - int(p.team)] as Array) + (tunit[2] as Array):        # (0.31.157: and the jungle's monsters)
		if (p.hit as Array).has(o.id) or not alive(o):
			continue
		if (o.pos as Vector2).distance_to(p.pos) < r:
			(p.hit as Array).append(o.id)
			_next_push = _push_along(p.vel, 4.6, 2.2)      # a hammer kill throws him the way it was going
			_damage(owner, o, float(p.dmg))
	return false

# ---------- the High Priest's Resurrection (0.31.1, Kevin) ----------
# Brings back the ally who fell most recently within RESURRECT_R, where they fell, at RESURRECT_HP of their health -- before
# their respawn takes them back to the castle. They get their class back if their hat is still lying there.
const RESURRECT_R := 6.0
const RESURRECT_CD := 30.0
const RESURRECT_HP := 0.4

func resurrect_target(u: Dictionary) -> Dictionary:
	var best := {}
	var latest := -INF
	for a in units:
		if a.team != u.team or a.state != "dead" or a.id == u.id:
			continue
		if (a.pos as Vector2).distance_to(u.pos) <= RESURRECT_R and float(a.get("died_at", -INF)) > latest:
			latest = float(a.get("died_at", -INF))
			best = a
	return best

func _resurrect(u: Dictionary) -> bool:
	if not alive(u) or u.stun > 0.0 or u.cd_ability > 0.0 or u.state in ["wind", "dodge"]:
		return false
	var a := resurrect_target(u)
	if a.is_empty():
		return false
	a.max_hp = float(stat(a, "hp"))
	a.hp = a.max_hp * RESURRECT_HP
	a.state = "idle"
	a.t = 0.0
	a.stun = 0.0
	a.respawn_at = INF
	u.cd_ability = RESURRECT_CD
	u.face = angle_of((a.pos as Vector2) - u.pos)
	u.state = "recover"
	u.t = 0.4
	_event("resurrect", {"id":a.id, "by":u.id, "team":u.team, "pos":a.pos})
	return true


# ---------- the Necromancer's drain (0.31.2, Kevin: "cast on enemy (green beam) which sucks their life out and then it heals
# player and also shoot another beam (white beam) to a near ally and heals") ----------
# The upgraded Priest's beam: a green beam locks onto the nearest enemy in reach and drains DRAIN_DPS of their life, which
# heals the Necromancer; while it drains, a white beam heals the nearest injured ally in reach by NECRO_ALLY_HEAL. No enemy in
# reach, no beams. Damage lands in DRAIN_CHUNK pieces so a drain isn't 30 hits a second.
const DRAIN_DPS := 14.0
const NECRO_ALLY_HEAL := 22.0
const DRAIN_CHUNK := 7.0
const DRAIN_SELF := 0.5          # share of the drain that heals the Necromancer (all of it until 0.31.5)
const MAGE_BOLT := 0.9           # the Mage's fireball damage factor (0.31.5)

func is_necro(u: Dictionary) -> bool:
	return u.cls == "priest" and bool(u.up)

func _necro_beam(u: Dictionary) -> bool:
	var reach := float(CLASSES["priest"].range)
	var foe: Dictionary = by_id.get(str(u.beam), {})
	if foe.is_empty() or not alive(foe) or foe.team == u.team or u.pos.distance_to(foe.pos) > reach + 1.0:
		foe = nearest_enemy(u, reach)
	if foe.is_empty():
		u.beam = ""
		u.beam2 = ""
		return false
	if str(u.beam) != str(foe.id):
		_event("drain", {"id":u.id, "to":foe.id})
	u.beam = foe.id
	u.beam_until = time + BEAM_HOLD
	u.face = angle_of((foe.pos as Vector2) - u.pos)
	var ally := beam_target(u)
	u.beam2 = ally.id if not ally.is_empty() and ally.hp < ally.max_hp - 0.5 else ""
	return true

func _step_drain(u: Dictionary, foe: Dictionary, dt: float) -> void:
	var take := DRAIN_DPS * dt
	u.hp = minf(u.max_hp, u.hp + take * DRAIN_SELF)
	u.drain_acc = float(u.get("drain_acc", 0.0)) + take
	if float(u.drain_acc) >= DRAIN_CHUNK:
		var chunk := float(u.drain_acc)
		u.drain_acc = 0.0
		_damage(u, foe, chunk)
	var ally: Dictionary = by_id.get(str(u.get("beam2", "")), {})
	if not ally.is_empty() and alive(ally) and u.pos.distance_to(ally.pos) <= float(CLASSES["priest"].range) + 1.0:
		_heal(u, ally, NECRO_ALLY_HEAL * dt * _beam_share(ally))
	else:
		u.beam2 = ""


func _beam_share(t: Dictionary) -> float:
	# The first beam to heal t this tick heals in full; any more heal at BEAM_STACK.
	if float(t.get("beam_heal_t", -1.0)) == time:
		return BEAM_STACK
	t["beam_heal_t"] = time
	return 1.0

# ---------- the killing blow's push (0.31.20) ----------
func _push_along(v: Vector2, speed: float, up: float) -> Vector3:
	var d := v.normalized() if v.length() > 0.01 else Vector2(0.0, 1.0)
	return Vector3(d.x * speed, up, d.y * speed)

func _push_from(from: Vector2, to: Vector2, speed: float, up: float) -> Vector3:
	var d := to - from
	d = d.normalized() if d.length() > 0.01 else dir_of(rng.randf() * TAU)
	return Vector3(d.x * speed, up, d.y * speed)

# ---------- predicted ability starts (0.31.23, online) ----------
func predict_ability(u: Dictionary) -> bool:
	# The client shows the start of its own ability at once: the state and cooldown the server will set, and the
	# events the view draws from. Nothing that hurts or heals anyone happens here (the client never steps the sim).
	if not can_act(u) or u.cd_ability > 0.0:
		return false
	match ability_of(u):
		"block":
			return _block(u)
		"whirlwind":
			return _whirl(u)                                   # the spin's damage is dealt in step(), server-side only
		"hammer":
			u.cd_ability = HAMMER_CD
			return _start_attack(u, "ability")                 # the throw animation; the hammer itself is the server's
		"resurrect":
			u.cd_ability = RESURRECT_CD
			return _start_attack(u, "ability")
		_:
			return _start_attack(u, "ability")                 # nova, sanctuary, ...: the wind-up; the burst comes from the server


# ---------- multi-kills (0.31.29, Kevin) ----------
# Kills by the same player each within MULTI_WINDOW s of the last chain: 2 DOUBLE, 3 TRIPLE, 4 QUADRA, 5 PENTA, 6+
# LEGENDARY. Enemy kills only (a bomb on your own side counts for nothing). Each step is an event; the best a player
# reaches is kept for the match stats ("best_multi").
const MULTI_WINDOW := 4.0
const MULTI_NAMES := ["", "", "DOUBLE KILL", "TRIPLE KILL", "QUADRA KILL", "PENTA KILL", "LEGENDARY"]

func _multi_kill(src: Dictionary, dst: Dictionary) -> void:
	if src.is_empty() or not src.has("pos") or int(src.get("team", -1)) == int(dst.team) or not by_id.has(str(src.get("id", ""))):
		return
	var n := 1
	if time - float(src.get("mk_t", -99.0)) <= MULTI_WINDOW:
		n = int(src.get("mk_n", 1)) + 1
	src["mk_n"] = n
	src["mk_t"] = time
	if n >= 2:
		src["best_multi"] = maxi(int(src.get("best_multi", 0)), n)
		_event("multikill", {"id":src.id, "team":int(src.team), "n":n, "name":MULTI_NAMES[mini(n, MULTI_NAMES.size() - 1)]})


# ---------- the three upgrades' own abilities (0.31.32, Kevin) ----------
# ASSASSIN -- Vanish: VANISH_TIME s unseen (no one can pick him out as a target until he's within 1.6 m; the view shows
# his own side a shimmer and the enemy almost nothing); his first strike out of it does VANISH_STRIKE x and reveals him,
# as does taking any hit.
const VANISH_TIME := 4.0
const VANISH_CD := 14.0
const VANISH_STRIKE := 2.0

func vanished(u: Dictionary) -> bool:
	return time < float(u.get("vanish_until", 0.0)) and alive(u)

func _vanish(u: Dictionary) -> bool:
	if not can_act(u) or u.cd_ability > 0.0:
		return false
	u["vanish_until"] = time + VANISH_TIME
	u.cd_ability = VANISH_CD
	_event("vanish", {"id":u.id, "team":u.team, "until":time + VANISH_TIME})
	return true

func _unvanish(u: Dictionary) -> void:
	if float(u.get("vanish_until", 0.0)) > time:
		u.vanish_until = time
		_event("unvanish", {"id":u.id})

# SNIPER -- Piercing Shot: a heavy arrow that flies PIERCE_RANGE and passes through everyone in its path.
const PIERCE_RANGE := 30.0
const PIERCE_SPEED := 42.0
const PIERCE_DMG := 2.2
const PIERCE_CD := 9.0

func _pierce_shot(u: Dictionary, dmg: float) -> void:
	var d := dir_of(u.face)
	projectiles.append({"id":_next_proj, "team":u.team, "owner":u.id, "pos":u.pos + d * 0.6, "from":u.pos, "vel":d * PIERCE_SPEED,
		"dmg":dmg * PIERCE_DMG, "aoe":0.0, "life":PIERCE_RANGE / PIERCE_SPEED, "kind":"pierce", "gate_mult":0.6, "hit":[],
		"high":height_at(u.pos) >= 1.5})
	_event("proj", {"pid":_next_proj, "kind":"pierce"})
	_next_proj += 1

# ARCHMAGE -- Meteor: on the nearest enemy within METEOR_RANGE (else that far ahead), a warning circle for METEOR_DELAY,
# then the strike: METEOR_DMG x damage at the centre (half at the edge of METEOR_R), bodies and loose things blown out,
# and the ground burning for METEOR_BURN s (BURN_DPS to enemies standing in it).
const METEOR_RANGE := 12.0
const METEOR_DELAY := 1.0
const METEOR_R := 3.2
const METEOR_DMG := 2.4
const METEOR_BURN := 3.5
const BURN_DPS := 9.0
const METEOR_CD := 12.0
var meteors: Array = []

func _call_meteor(u: Dictionary, dmg: float) -> void:
	var foe := nearest_enemy(u, METEOR_RANGE, true)
	var at: Vector2 = foe.pos if not foe.is_empty() else u.pos + dir_of(u.face) * METEOR_RANGE * 0.75
	at = _push_out(at, 0.2)
	meteors.append({"team":u.team, "owner":u.id, "at":at, "t_hit":time + METEOR_DELAY, "dmg":dmg * METEOR_DMG, "burn_until":-1.0})
	_event("meteor_warn", {"id":u.id, "team":u.team, "pos":at, "delay":METEOR_DELAY})

func _step_meteors(dt: float) -> void:
	for i in range(meteors.size() - 1, -1, -1):
		var m: Dictionary = meteors[i]
		var owner: Dictionary = by_id.get(str(m.owner), {})
		if float(m.burn_until) < 0.0:
			if time < float(m.t_hit):
				continue
			for o in units:
				if o.team == int(m.team) or not alive(o):
					continue
				var d: float = (o.pos as Vector2).distance_to(m.at)
				if d <= METEOR_R:
					_next_push = _push_from(m.at, o.pos, 4.6, 3.8)
					_damage(owner if not owner.is_empty() else {"team":int(m.team), "id":""}, o, float(m.dmg) * (1.0 - 0.5 * d / METEOR_R), 0.4)
			m.burn_until = time + METEOR_BURN
			_event("meteor_hit", {"team":int(m.team), "pos":m.at, "burn":METEOR_BURN})
			continue
		if time >= float(m.burn_until):
			meteors.remove_at(i)
			continue
		for o in units:
			if o.team != int(m.team) and alive(o) and (o.pos as Vector2).distance_to(m.at) <= METEOR_R * 0.8:
				o.hp -= BURN_DPS * dt
				if o.hp <= 0.0:
					o.hp = 0.1
					_damage(owner if not owner.is_empty() else {"team":int(m.team), "id":""}, o, 1.0)

# Bots: when to use them (called from _fight).
func _bot_upgrade_ability(u: Dictionary, foe: Dictionary) -> bool:
	if u.cd_ability > 0.0 or not can_act(u) or foe.is_empty():
		return false
	var d: float = u.pos.distance_to(foe.pos)
	match ability_of(u):
		"vanish":
			if d > 3.0 and d < 11.0 and not vanished(u):
				return _vanish(u)                       # slip in unseen, strike from it
		"pierce":
			if d > 6.0 and d < PIERCE_RANGE * 0.9:
				var line := 0                            # worth it if two or more stand along the line
				var dirv: Vector2 = (foe.pos - u.pos).normalized()
				for o in units:
					if o.team != u.team and alive(o):
						var off: Vector2 = o.pos - u.pos
						var along: float = off.dot(dirv)
						if along > 0.0 and along < PIERCE_RANGE and absf(off.cross(dirv)) < 1.0:
							line += 1
				if line >= 2 or d > 16.0:
					u.face = angle_of(foe.pos - u.pos)
					return _start_attack(u, "ability")
		"meteor":
			if d < METEOR_RANGE:
				var crowd := 0
				for o in units:
					if o.team != u.team and alive(o) and (o.pos as Vector2).distance_to(foe.pos) <= METEOR_R:
						crowd += 1
				if crowd >= 2 or (d > 5.0 and rng.randf() < 0.2):
					u.face = angle_of(foe.pos - u.pos)
					return _start_attack(u, "ability")
	return false
