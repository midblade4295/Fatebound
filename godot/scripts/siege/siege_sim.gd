extends RefCounted
# Fatebound Siege: real-time capture-the-Oracle between two castles. Pure simulation with no scene
# nodes, stepped at a fixed rate, so the same rules can later run on an authoritative server.
# Coordinates: Vector2(x, z) on the ground plane. Blue (team 0) holds the south end (+z), red
# (team 1) the north end (-z). Red's castle is the point mirror of blue's: (x, z) -> (-x, -z).

const TICK := 1.0 / 30.0
const Land = preload("res://scripts/siege/siege_land.gd")
const Castle = preload("res://scripts/siege/siege_castle.gd")
const HALF_W := Land.HALF_W
const HALF_L := Land.HALF_L
# Castle layouts are authored in "castle-local" blue-space coordinates (x -13..13, z 15..29 with
# the back at z=29) and placed at each end of the field by _c(): shifted so the castle's back
# sits on the field edge, then mirrored for red.
const CASTLE_BACK := Castle.BACK
const CASTLE_SHIFT := HALF_L - CASTLE_BACK
const CASTLE_HX := Castle.HX          # 20 since Round 10 (was 13)
const UNIT_R := 0.45
const WIN_RESCUES := 3
const MATCH_TIME := 720.0
const RESPAWN_TIME := 5.0
const DROP_RETURN := 25.0        # a dropped Oracle nobody moves goes back to her cell
const WORKSHOP_RADIUS := 2.8
const PICKUP_RADIUS := 1.5
const THRONE_RADIUS := 2.2

# ---- castle geometry (blue side; red mirrored) ----
const WALL_SCALE := 2.6          # KayKit wall_straight is 2.0 long -> 5.2 m
const SEG := 5.2
const WALL_R := 1.0              # collision half-thickness of a wall
const FRONT_Z := Castle.FRONT_Z         # front wall with the two gates (3 since Round 10)
const GATE_X := Castle.GATE_X
const GATE_HP := 1100.0
const JAIL_SHUT_R := 3.5         # an enemy this close keeps the jail door shut, defenders or not
const RAMPART_THREAT_R := 26.0   # enemies this close to a castle's front put its ranged defenders on the rampart
const RAMPART_HOLD := 8.0        # ... and they stay up there this long after the last one left
const GATE_HALF := 1.3           # half-width of the passable doorway
const GATE_SOLID_AT := 0.35      # a broken gate blocks again once repaired to 35 %
const GATE_OPEN_RADIUS := 4.0    # allies within this distance swing the doors open (visual)
const REPAIR_LOCK := 3.0         # no repairs while the gate was hit in the last 3 s
const RUBBLE_TIME := 20.0        # a broken gate can't be rebuilt for 20 s ...
const RUBBLE_CLEAR := 6.0        # ... or while any enemy is within 6 m of it

# ---- layers (heights are for the view; the sim stays 2D, ledges are walls) ----
const LEDGE_R := 0.35                # landscape ledges; castle terraces use Castle.LEDGE_R
# Round 7 layout (blue half; mirrored). Checked by tests/siege_land_check.gd.
# Resource nodes and cover rocks, blue half (0.26.0 land); tests/siege_land_check.gd checks the spacing.
const RES_WOOD := [Vector2(-29.5, 43.0), Vector2(26.0, 40.5), Vector2(26.5, 53.0), Vector2(-11.0, 20.0), Vector2(12.0, 19.0),
	Vector2(9.0, 32.5)]
const RES_STONE := [Vector2(26.0, 62.0), Vector2(-26.5, 45.0), Vector2(-6.0, 26.5), Vector2(9.0, 16.5), Vector2(-31.0, 10.0)]
const COVER_ROCKS := [Vector2(-4.0, 18.5), Vector2(15.5, 26.0), Vector2(-10.0, 31.0)]
const OUTPOST_TRICKLE := 15.0    # owners get +1 wood +1 stone this often per outpost

# ---- fate offerings (the "cake") ----
const CAKE_PER_STAGE := 3           # three fish fatten him one size stage (name kept from the cake days)
# Fishing (Round 19, Kevin: the cake trees are gone -- catch fish from the river and feed them to the
# enemy King). ACTION on a river bank casts; FISH_TIME later you hold a fish, if nothing hit you.
const FISH_TIME := 2.5
const FISH_REACH := 2.4            # how far back from the water's edge you can still fish
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
const CATAPULT_X := Castle.CATAPULT_X
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
const WATER_MOVE := 0.45         # wading speed in the river (Round 33)
const WATER_NAV_COST := 2.5      # river cells cost this much in the nav grid: bots still prefer a nearby bridge
# The island lane (0.30.0) is the shortest way across but one lane wide: every bot raider took it and the
# whole army died in the bottleneck (no King picked up in two 12-minute bot matches). Costing its cells a
# little more spreads the bots over the side bridges too; players still take whichever way they like.
const LANE_NAV_COST := 2.2
# Climbing (Round 25, Kevin: "when players use a ladder they climb up it and over the wall"): the ladder stands
# 1.35 m out from the wall and reaches its top; climbers go up the rungs, over the top, and drop down inside.
const LADDER_FOOT := 1.35         # where the ladder meets the ground, out from the wall line
const LADDER_TOP := 2.9           # the height they go over at

# ---- gathering / crafting ----
const CARRY_MAX := 6              # 3 logs or 3 rocks (0.31.0; was 5 units)
const GATHER_TIME := 0.9         # seconds per unit gathered
const REPAIR_TICK := 0.5
const REPAIR_HP := 20.0          # per tick, costs 1 wood (30 made gates unbreakable once classes stopped persisting)
const UPGRADES := {
	"gates":  {"name":"Reinforced Gates", "max":2, "cost":[{"wood":15,"stone":10},{"wood":25,"stone":20}],
		"desc":"+50% gate HP per level, and repairs all gates"},
	"armory": {"name":"Armory", "max":3, "cost":[{"wood":10,"stone":15},{"wood":20,"stone":25},{"wood":30,"stone":35}],
		"desc":"+12% HP and damage per level for your fighters"},
	"hat_knight":    {"name":"Crusader Hats", "max":1, "cost":[{"wood":12,"stone":12}], "desc":"The Knight stand makes Crusader hats: Hammer Throw"},
	"hat_barbarian": {"name":"Berserker Hats", "max":1, "cost":[{"wood":12,"stone":12}], "desc":"The Barbarian stand makes Berserker hats"},
	"hat_rogue":     {"name":"Assassin Hats", "max":1, "cost":[{"wood":12,"stone":12}], "desc":"The Rogue stand makes Assassin hats"},
	"hat_ranger":    {"name":"Sniper Hats", "max":1, "cost":[{"wood":12,"stone":12}], "desc":"The Ranger stand makes Sniper hats"},
	"hat_mage":      {"name":"Archmage Hats", "max":1, "cost":[{"wood":12,"stone":12}], "desc":"The Mage stand makes Archmage hats"},
	"hat_priest":    {"name":"Necromancer Hats", "max":1, "cost":[{"wood":12,"stone":12}], "desc":"The Priest stand makes Necromancer hats: drain enemies, heal allies, raise the fallen"},
	"catapult": {"name":"Catapults", "max":1, "cost":[{"wood":15,"stone":25}],
		"desc":"Your corner towers lob stones at enemies 5-22 m away"},
	"launcher": {"name":"Player Launcher", "max":1, "cost":[{"wood":60,"stone":45}],
		"desc":"A launch pad in your castle: pull its lever, and 5 s later everyone on it flies into the enemy castle"},
}

# ---- hats (Round 8, Fat Princess style; replaced the dice forge) ----
# Five stands in each courtyard's west corner (castle-local coords). Villagers walking into a stand
# take its hat and become that class; dying drops your hat where you fall and anyone -- ally or
# enemy -- who walks over it as a Villager takes it. Classed units swap at a stand with ACTION.
const HAT_CLASSES := ["knight", "barbarian", "rogue", "ranger", "mage", "priest"]
const HAT_STANDS := Castle.HAT_STANDS
const HAT_HALL := Castle.HAT_HALL
const HAT_TAKE_R := 1.3
const HAT_STOCK_MAX := 3
# 0.31.4 (Kevin: no per-class caps after all): the stands steer the mix instead -- the strong/rare classes hold fewer hats
# and restock more slowly. (CLASS_CAP left empty: class_full() is always false.)
const CLASS_CAP := {}
const STAND_STOCK := {"knight":3, "barbarian":3, "rogue":3, "ranger":3, "mage":2, "priest":2}
const STAND_REGEN := {"knight":6.0, "barbarian":6.0, "rogue":6.0, "ranger":8.0, "mage":10.0, "priest":12.0}
# Healing doesn't stack (0.31.4): one Sanctuary per target every SANCT_ONCE s; a second healer beam on a target already
# healed by a beam this tick heals at BEAM_STACK.
const SANCT_ONCE := 3.0
const BEAM_STACK := 0.5
const HAT_REGEN := 6.0           # seconds per new hat, per stand (10 s starved 16-player teams)
const HAT_LIFETIME := 30.0       # a dropped hat vanishes after this
const HAT_PICK_R := 1.0
# Fat Princess rules (Kevin, 0.15.1): stands exist only inside the castles, but ANY team may use
# them (sneak into the enemy courtyard to switch class). Outposts have no hat dispenser: they are a
# respawn point (attackers respawn there only when a dropped hat is close by) and a resource
# drop-off for Workers.
const OUTPOST_DROP_R := 4.4       # workers deliver within this of an outpost their team holds (wider towers, 0.30.3)
# Towers (0.26.0, Kevin): the team holding an outpost can climb its tower -- archers and mages only --
# and shoot down from the top. Up there they can't be reached by melee; arrows, fire and catapult
# stones still hit them. Lose the tower and everyone on it is thrown off. No respawning at towers.
const TOWERS_CLIMBABLE := true    # 0.30.2, Kevin: "make it so players can climb up captured towers" (any class)
const TOWER_CLASSES := ["villager", "worker", "knight", "barbarian", "rogue", "ranger", "mage", "priest"]
const TOWER_SHOOTERS := ["ranger", "mage"]   # Kevin: "only mages and archers can shoot from top"
const TOWER_BOTS := false        # bots stay on the ground for now (players climb)
const TOWER_SLOTS := 8            # the deck is wide now (0.30.3): people walk about on it
const TOWER_ENTER_R := 4.0        # from the tower's centre (its wall is 3 m out)
const TOWER_RANGE := 1.3          # range bonus from the top
const TOWER_BOT_MAX := 2          # bots leave the other places for players
                                  # there. Bot attackers always respawn forward and scavenge (like
                                  # Fat Princess players choosing an outpost spawn).
const BOT_HAT_SEARCH := 32.0      # villager bots scavenge dropped hats this far (14 m: most expired unused)
const UPGRADE_NAME := {"knight":"Crusader","barbarian":"Berserker","rogue":"Assassin","ranger":"Sniper","mage":"Archmage","priest":"Necromancer"}
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
	"villager": {"name":"Villager","hp":60,"speed":5.2,"dmg":8,"range":1.3,"arc":0.5,"windup":0.2,"recover":0.3,
		"ranged":false,"ability":"","ab_cd":0.0,"carry":0.65,"gate":0.5},
	"worker": {"name":"Worker","hp":80,"speed":5.0,"dmg":12,"range":1.5,"arc":0.4,"windup":0.28,"recover":0.4,
		"ranged":false,"ability":"","ab_cd":0.0,"carry":0.65,"gate":1.2},
	"knight": {"name":"Knight","hp":150,"speed":4.6,"dmg":21,"range":2.0,"arc":0.4,"windup":0.24,"recover":0.4,
		"ranged":false,"ability":"block","ab_cd":0.0,"carry":0.65,"gate":1.0},
	"barbarian": {"name":"Barbarian","hp":130,"speed":4.8,"dmg":26,"range":2.0,"arc":0.25,"windup":0.36,"recover":0.45,
		"ranged":false,"ability":"spin","ab_cd":7.0,"carry":0.65,"gate":1.6},
	"rogue": {"name":"Rogue","hp":85,"speed":6.2,"dmg":14,"range":1.4,"arc":0.5,"windup":0.13,"recover":0.22,
		"ranged":false,"ability":"lunge","ab_cd":5.0,"carry":0.72,"gate":0.6},
	"ranger": {"name":"Ranger","hp":80,"speed":5.4,"dmg":15,"range":11.0,"arc":0.0,"windup":0.3,"recover":0.45,
		"ranged":true,"proj_speed":33.0,"aoe":0.0,"ability":"volley","ab_cd":7.0,"carry":0.65,"gate":0.35},
	"mage": {"name":"Mage","hp":75,"speed":5.0,"dmg":20,"range":9.0,"arc":0.0,"windup":0.4,"recover":0.5,
		"ranged":true,"proj_speed":24.0,"aoe":1.6,"ability":"nova","ab_cd":8.0,"carry":0.65,"gate":1.0},
	# Healer (Round 9, Kevin): hold ATTACK to channel a healing beam into the nearest injured ally
	# (range = beam reach); the ability heals every ally close by. No damage.
	"priest": {"name":"Priest","hp":90,"speed":5.2,"dmg":0,"range":9.0,"arc":0.0,"windup":0.3,"recover":0.4,
		"ranged":true,"proj_speed":0.0,"aoe":0.0,"ability":"sanctuary","ab_cd":9.0,"carry":0.65,"gate":0.3,"heal":18.0},
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
var nodes: Array = []
var items: Array = []               # loose logs and rocks on the ground (0.31.0)
# The bomb (0.31.19, Kevin): each workshop makes one powerful bomb at a time. Anyone can pick it up (ACTION) and throw
# it (ACTION or ATTACK); the throw lights the fuse. It kills everyone in BOMB_R -- friends too -- takes half of any
# door's health and all of a jail door's. Per team: {} when there is none, else
# {"id","team","state" ready|carried|flying|lit|loose, "p","h","carrier","by","from","to","t0","lit_at"}.
var bombs: Array = [{}, {}]
# The shove of the killing blow (0.31.20): callers set it before _damage; _kill sends it with the death so bodies,
# weapons and hats go the way the blow went. Reset after every _damage.
var _next_push := Vector3.ZERO
var bomb_next: Array = [0.0, 0.0]
var outposts: Array = []       # {id, p, owner (-1 neutral), prog (-1 red .. +1 blue), t}          # resource nodes {id, kind:"wood"/"stone", p, r, amount, max, regen, t}
var stock := [{"wood":0, "stone":0}, {"wood":0, "stone":0}]
var levels := [_zero_levels(), _zero_levels()]
var stands: Array = []         # {id, team, cls, p, stock, t}
var hats: Array = []           # dropped hats on the ground: {id, cls, up, pos, t}
var _hat_id := 0

static func _zero_levels() -> Dictionary:
	var d := {}
	for k in UPGRADES:
		d[k] = 0
	return d
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
	return _c(team, Castle.THRONE)

const CELL_C := Castle.CELL_C      # dungeon cell centre (L1 west wing since Round 10)
const CELL_HX := Castle.CELL_HX
const CELL_HZ := Castle.CELL_HZ

static func cell(team: int) -> Vector2:
	# Where a team's own Oracle is held captive: the ENEMY castle's dungeon.
	return _c(1 - team, CELL_C)

static func height_at(p: Vector2) -> float:
	# Ground height for rendering. Castles are evaluated in blue space (mirror for red).
	var q := (p if p.y >= 0.0 else -p) - Vector2(0.0, CASTLE_SHIFT)
	if Castle.inside(q):
		return Castle.height_local(q)                # courtyard, terraces, grand stairs
	# Just around the castle is flat; everything else is the landscape (slopes, ledges, bridges).
	if absf(q.x) <= CASTLE_HX + 1.0 and q.y >= FRONT_Z - 1.0:
		return 0.0
	return Land.ground_height(p)

static func forge(team: int) -> Vector2:
	# The hat stands' corner (kept under the old name: HUD hints, bots and tests aim here).
	return _c(team, HAT_HALL)

static func workshop(team: int) -> Vector2:
	return _c(team, Castle.WORKSHOP)

static func spawn(team: int) -> Vector2:
	return _c(team, Castle.SPAWN)

static func gate_front(g: Dictionary) -> Vector2:
	# Standing point just outside a gate (the side facing midfield).
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

func _add_wall(team: int, a: Vector2, b: Vector2, kind := "wall") -> void:
	walls.append({"a":_c(team, a), "b":_c(team, b), "r":WALL_R, "team":team, "kind":kind})

func _build_map() -> void:
	walls.clear()
	gates.clear()
	stands.clear()
	hats.clear()
	obstacles.clear()
	nodes.clear()
	for t in 2:
		# Front wall (Round 10: z=3, 40 m wide) with a gatehouse piece around each gate. Pieces that
		# meet the field edge run 1 m past it (no rounded wall end for a unit to be clamped into).
		var gp: float = Castle.GATE_PIECE
		var gx0: float = GATE_X[0]
		var gx1: float = GATE_X[1]
		_add_wall(t, Vector2(-CASTLE_HX, FRONT_Z), Vector2(gx0 - gp, FRONT_Z))
		_add_wall(t, Vector2(gx0 + gp, FRONT_Z), Vector2(gx1 - gp, FRONT_Z))
		_add_wall(t, Vector2(gx1 + gp, FRONT_Z), Vector2(CASTLE_HX, FRONT_Z))
		# Side walls: the field is wider than the castle, so it needs its own flanks.
		# West wall with the doorway down to the dungeon wing (Round 13); the wing's three walls.
		_add_wall(t, Vector2(-CASTLE_HX, FRONT_Z), Vector2(-CASTLE_HX, Castle.DOOR_Z0 - 1.0))
		_add_wall(t, Vector2(-CASTLE_HX, Castle.DOOR_Z1 + 1.0), Vector2(-CASTLE_HX, CASTLE_BACK + 1.0))
		_add_wall(t, Vector2(Castle.ANNEX_X0, Castle.ANNEX_Z0), Vector2(Castle.ANNEX_X0, Castle.ANNEX_Z1))
		# (They stop 1 m inside the west wall's thickness: ending on its inner face, their rounded ends
		# made a squeeze slot with the knight's barracks -- Round 20.)
		_add_wall(t, Vector2(Castle.ANNEX_X0, Castle.ANNEX_Z0), Vector2(-CASTLE_HX - 1.0, Castle.ANNEX_Z0))
		_add_wall(t, Vector2(Castle.ANNEX_X0, Castle.ANNEX_Z1), Vector2(-CASTLE_HX - 1.0, Castle.ANNEX_Z1))
		_add_wall(t, Vector2(CASTLE_HX, FRONT_Z), Vector2(CASTLE_HX, CASTLE_BACK + 1.0))
		for gx in GATE_X:
			# The gate model is a wall piece with a ~2.3 m doorway; only the doorway is the gate.
			# The neighbouring wall ends (radius 1.0) cover the stone pillars either side.
			var a := _c(t, Vector2(gx - GATE_HALF, FRONT_Z))
			var b := _c(t, Vector2(gx + GATE_HALF, FRONT_Z))
			# "in": the gate's inward normal (toward its castle) -- enemies on that side may walk out (lets_out).
			var inw: Vector2 = Vector2(-(b - a).y, (b - a).x).normalized()
			if inw.dot(_c(t, Vector2(0.0, 16.0)) - (a + b) * 0.5) < 0.0:
				inw = -inw
			gates.append({"id":gates.size(), "team":t, "a":a, "b":b, "c":(a + b) * 0.5, "hp":GATE_HP, "max_hp":GATE_HP,
				"broken":false, "open":false, "side":"west" if gx < 0.0 else "east", "in":inw})
		# Terrace faces (L1 at z=14, L2 at z=22) open only at the staircases, and ledges along each
		# staircase's sides (siege_castle.gd).
		for seg in Castle.ledges():
			walls.append({"a":_c(t, seg[0]), "b":_c(t, seg[1]), "r":Castle.LEDGE_R, "team":t, "kind":"ledge"})
		# The dungeon wing (Round 13): walls along both sides of the stairs down; the jail cell in
		# the wing's front-west corner -- iron bars on its east side and the barred door on its north
		# side (a "jail" gate: lifts for this castle's team, the enemy has to smash it). The other two
		# sides are the wing's own walls.
		# The back wall along the L2 back edge and the throne against it (Round 14).
		_add_wall(t, Vector2(-CASTLE_HX, Castle.BACK_WALL_Z), Vector2(CASTLE_HX, Castle.BACK_WALL_Z), "backwall")
		obstacles.append({"p":_c(t, Castle.THRONE_SEAT), "r":0.9, "kind":"castle_building", "team":t})
		for seg in Castle.dungeon_ledges():
			walls.append({"a":_c(t, seg[0]), "b":_c(t, seg[1]), "r":Castle.LEDGE_R, "team":t, "kind":"ledge"})
		var wall_in_x: float = Castle.ANNEX_X0 + WALL_R
		var wall_in_z: float = Castle.ANNEX_Z0 + WALL_R
		walls.append({"a":_c(t, Vector2(Castle.JAIL_X1, wall_in_z)), "b":_c(t, Vector2(Castle.JAIL_X1, Castle.JAIL_Z1)),
			"r":Castle.JAIL_R, "team":t, "kind":"bars"})
		var ja := _c(t, Vector2(wall_in_x, Castle.JAIL_Z1))
		var jb := _c(t, Vector2(Castle.JAIL_X1, Castle.JAIL_Z1))
		gates.append({"id":gates.size(), "team":t, "a":ja, "b":jb, "c":(ja + jb) * 0.5, "hp":Castle.JAIL_HP,
			"max_hp":Castle.JAIL_HP, "broken":false, "open":false, "side":"jail", "kind":"jail", "r":Castle.JAIL_R})
		# Hat stands (solid posts) in the west corner; the workshop against the east wall.
		for i in HAT_CLASSES.size():
			var sp := _c(t, HAT_STANDS[i])
			# The shop is the building (Round 20): solid, and you take the hat at its door (sp). b / top: where
			# its name plate goes (over the roof).
			var shop: Dictionary = Castle.HAT_SHOPS[i]
			var bpos := _c(t, shop.b)
			stands.append({"id":stands.size(), "team":t, "cls":HAT_CLASSES[i], "p":sp, "stock":int(STAND_STOCK.get(HAT_CLASSES[i], HAT_STOCK_MAX)), "t":0.0,
				"b":bpos, "top":float(shop.y) + 4.4})
			obstacles.append({"p":bpos, "r":float(shop.r), "kind":"castle_building", "team":t})
		for bd in Castle.BUILDINGS:
			obstacles.append({"p":_c(t, bd.p), "r":float(bd.r), "kind":"castle_building", "team":t})
		# Resource nodes on each half (world coords, point-mirrored), placed off the paths, clear of
		# the river, the ledge faces and the outposts (tests/siege_land_check.gd verifies this).
		for tp in RES_WOOD:
			_add_node(t, "wood", tp)
		for sp in RES_STONE:
			_add_node(t, "stone", sp)
		for rp in COVER_ROCKS:
			obstacles.append({"p":_m(t, rp), "r":1.2, "kind":"rock"})
	# Landscape: river banks, bridge rails, ledge faces and ramp sides (Round 7).
	walls.append_array(Land.walls())
	_fill_squeeze_slots()
	# Outposts: a solid tower in the middle of each capture ring.
	outposts = []
	for op in Land.outpost_positions():
		outposts.append({"id":outposts.size(), "p":op, "owner":-1, "prog":0.0, "t":0.0, "occ":[]})
		obstacles.append({"p":op, "r":Land.OUTPOST_TOWER_R, "kind":"outpost_tower"})

func _add_node(team: int, kind: String, p: Vector2) -> void:
	var pos := _m(team, p)
	# 0.31.0: "amount" counts the chops/hits left; at 0 the tree falls into logs (the boulder breaks into rocks),
	# a stump/rubble stays, and it grows back whole after NODE_REGROW.
	var hits: int = TREE_CHOPS if kind == "wood" else ROCK_HITS
	var n := {"id":nodes.size(), "kind":kind, "p":pos, "r":0.9 if kind == "wood" else 1.0,
		"amount":hits, "max":hits, "regen":float(NODE_REGROW[kind]), "t":0.0}
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
const PROJ_PASS_KINDS := ["ledge", "bars", "river", "rail", "edge"]
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
			if TOWERS_CLIMBABLE == false or str(ob.kind) != "outpost_tower":
				_bucket_obs_proj[bi].append(oi)        # nobody shoots from inside a tower: towers stop shots again

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
	solid.append_array(_outside_cells())
	for c in solid:
		for t in 2:
			(nav[t] as AStarGrid2D).set_point_solid(c, true)
	# The river is walkable but slow: its cells cost more, so a path crosses at a bridge unless one is far.
	var grid0: AStarGrid2D = nav[0]
	for ix in range(grid0.region.position.x, grid0.region.end.x):
		for iz in range(grid0.region.position.y, grid0.region.end.y):
			var cc := Vector2i(ix, iz)
			if water_depth(nav_point(cc)) > 0.15:
				for t in 2:
					(nav[t] as AStarGrid2D).set_point_weight_scale(cc, WATER_NAV_COST)
			elif _lane_cell(nav_point(cc)):
				for t in 2:
					(nav[t] as AStarGrid2D).set_point_weight_scale(cc, LANE_NAV_COST)
	_gate_cells.clear()
	for g in gates:
		_gate_cells.append(_cells_across_segment(g.a, g.b, float(g.get("r", WALL_R)) + UNIT_R * 0.9))
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
	# broken. Not the jail door.
	return g.has("in") and (p - (g.c as Vector2)).dot(g["in"]) > 0.0

func _path_gate(u: Dictionary) -> Dictionary:
	# The intact enemy gate the bot's current path runs through within the next few steps, if any.
	var path: PackedVector2Array = u.path
	for i in range(u.path_i, mini(u.path_i + 5, path.size())):
		for g in gates:
			if g.team != u.team and gate_blocks(g) and not lets_out(g, u.pos) \
					and path[i].distance_to(seg_closest(path[i], g.a, g.b)) < float(g.get("r", WALL_R)) + 0.6:
				return g
	return {}

# ---------- setup ----------
func setup(team_size: int, seed_value: int, player_team := 0) -> void:
	meteors = []
	launchers = [{"count_at":-1.0, "ready_at":0.0}, {"count_at":-1.0, "ready_at":0.0}]
	bombs = [{}, {}]
	bomb_next = [BOMB_FIRST, BOMB_FIRST]
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
	_reset_jail(1 - t)

func _reset_jail(castle_team: int) -> void:
	# Whenever a King is back in his cell, the jail door of the castle holding him is whole again --
	# as soon as no enemy stands in the doorway or the cell (Round 15: snapping shut on a rescuer put
	# him inside the door; anyone in the cell would have been locked in with the King).
	for g in gates:
		if int(g.team) == castle_team and str(g.get("kind", "")) == "jail" and (g.broken or g.hp < g.max_hp):
			g["relock"] = true
			_try_relock(g)

func _try_relock(g: Dictionary) -> void:
	var cell := _c(int(g.team), CELL_C)
	var reach: float = float(g.get("r", WALL_R)) + UNIT_R + 0.3
	for u in units:
		if u.team != g.team and alive(u) and (u.pos.distance_to(cell) < 3.0 or u.pos.distance_to(seg_closest(u.pos, g.a, g.b)) < reach):
			return                                  # someone's in the way: try again next tick
	g.erase("relock")
	g.hp = g.max_hp
	g.broken = false
	g.erase("broken_at")
	_update_gate_nav()
	_event("jail_reset", {"gate":g.id, "team":g.team})

func lifters_needed(o: Dictionary) -> int:
	return int(LIFTERS[clampi(int(o.weight), 0, LIFTERS.size() - 1)])

func _new_unit(id: String, team: int, bot: bool, role: String) -> Dictionary:
	return {"id":id,"team":team,"bot":bot,"role":role,"cls":"villager","up":false,"hp":60.0,"max_hp":60.0,
		"pos":Vector2.ZERO,"face":0.0,"move":Vector2.ZERO,"state":"idle","t":0.0,"atk":"","cd_dodge":0.0,
		"cd_ability":0.0,"stun":0.0,"carrying":false,"respawn_at":0.0,"kills":0,"deaths":0,"rescues":0,
		"dodge_dir":Vector2.ZERO,"target":"","ai_goal":Vector2.ZERO,"lunge_hit":false,
		"unstick":0.0,"unstick_dir":Vector2.ZERO,"stuck_t":0.0,"last_pos":Vector2.ZERO,
		"lifting":-1, "tower":-1, "beam":"", "beam2":"", "drain_acc":0.0, "beam_until":0.0, "block_until":0.0, "whirl_until":0.0, "whirl_t":0.0, "load":{"kind":"", "n":0}, "task":{}, "workshop_open":false, "gathered":0, "repaired":0.0, "gate_dmg":0.0, "offering":false, "fed":0,
		"path":PackedVector2Array(), "path_i":0, "path_goal":Vector2(INF, INF), "path_at":-10.0, "path_ver":-1}

func armory_mult(team: int) -> float:
	return 1.0 + 0.08 * float(levels[team].armory)        # +12 % a level until 0.31.4

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

func nearest_enemy(u: Dictionary, max_d: float, prefer_front := false) -> Dictionary:
	var best := {}
	var best_score := INF
	var fwd := dir_of(u.face)
	var reach_top: bool = CLASSES[u.cls].ranged
	for o in units:
		if o.team == u.team or not alive(o):
			continue
		if int(o.tower) >= 0 and not reach_top:
			continue                           # up a tower: out of a sword's reach
		if o.state == "fly":
			continue                           # in the air off the launcher
		var off: Vector2 = o.pos - u.pos
		var d := off.length()
		if d > max_d:
			continue
		if vanished(o) and d > 1.6:
			continue                           # 0.31.32: an Assassin in Vanish can't be picked out (until he's on you)
		var s := d
		if prefer_front and d > 0.01:
			s += (1.0 - fwd.dot(off / d)) * 2.0
		# 0.31.25 (smarter bots): a wounded enemy is worth a few metres' detour; archers and mages go for the
		# enemy's healers and casters first
		if u.bot:
			if o.hp < o.max_hp * 0.35:
				s -= 3.0
			if reach_top and o.cls in ["priest", "mage"]:
				s -= 2.0
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
		"attack":
			if bool(u.get("bomb_held", false)):
				return _throw_bomb(u)
			return _beam(u) if u.cls == "priest" else _start_attack(u, "attack")
		"ability":
			match ability_of(u):
				"block": return _block(u)
				"whirlwind": return _whirl(u)
				"hammer": return _throw_hammer(u)
				"resurrect": return _resurrect(u)
				"vanish": return _vanish(u)
				_: return _start_attack(u, "ability")
		"dodge": return _dodge(u)
		"interact": return _interact(u)
		"hat_swap": return _swap_hat(u)
		"take_tools": return _take_tools(u)
		"buy":
			# Hat upgrades are bought AT the hat shop (Round 12), not through the workshop menu.
			if str(arg).begins_with("hat_"):
				return false
			return buy_upgrade(u.team, str(arg), u)
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
	return alive(u) and u.stun <= 0.0 and u.state in ["idle","move"] and not u.workshop_open

func _aim(u: Dictionary, reach: float) -> void:
	var target := nearest_enemy(u, reach, true)
	u["aim_d"] = 0.0
	if not target.is_empty():
		u.face = angle_of(target.pos - u.pos)
		u["aim_d"] = u.pos.distance_to(target.pos)

func _start_attack(u: Dictionary, kind: String, aim := true) -> bool:
	if not can_act(u) or u.carrying or u.offering or blocking(u) or whirling(u):
		return false
	var on_tower := int(u.get("tower", -1)) >= 0
	if int(u.get("hammer_out", -1)) >= 0:
		return false                           # the Crusader's hammer is still flying
	if on_tower and not TOWER_SHOOTERS.has(u.cls):
		return false                           # up a tower only archers and mages can attack
	if kind == "ability":
		if CLASSES[u.cls].ability == "" or u.cd_ability > 0.0:
			return false
		if on_tower and CLASSES[u.cls].ability != "volley":
			return false                       # the mage's nova is a blast round her feet
		u.cd_ability = float(CLASSES[u.cls].ab_cd)
	var reach := float(stat(u,"range")) * (1.0 if CLASSES[u.cls].ranged else 1.9)
	if kind == "ability" and CLASSES[u.cls].ability == "lunge":
		reach = 6.0
	if on_tower:
		reach *= TOWER_RANGE
	if aim:
		_aim(u, reach)
	u.task = {}
	u.state = "wind"
	u.atk = kind
	u.t = float(stat(u,"windup")) * (1.3 if kind == "ability" else 1.0)
	u.lunge_hit = false
	_event("attack", {"id":u.id,"kind":kind,"ability":CLASSES[u.cls].ability if kind == "ability" else ""})
	return true

# ---------- knight block / berserker whirlwind ----------
func ability_of(u: Dictionary) -> String:
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
	if int(u.get("tower", -1)) >= 0:
		return false                           # nothing but bows and spells up a tower
	if not alive(u) or u.stun > 0.0 or u.carrying or u.state in ["wind", "recover", "dodge"] or u.workshop_open:
		return false
	if not blocking(u):
		_event("block_up", {"id":u.id})
	u.block_until = time + BLOCK_HOLD
	return true

func _whirl(u: Dictionary) -> bool:
	if int(u.get("tower", -1)) >= 0:
		return false                           # nothing but bows and spells up a tower
	if u.cd_ability > 0.0 or not can_act(u) or u.carrying or u.offering:
		return false
	u.whirl_until = time + WHIRL_TIME
	u.whirl_t = 0.0
	u.cd_ability = WHIRL_CD
	_event("whirl", {"id":u.id})
	return true

func _step_whirl(u: Dictionary, dt: float) -> void:
	if not whirling(u):
		return
	if u.stun > 0.0 or u.carrying:
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
	if int(u.get("tower", -1)) >= 0:
		return false                           # nothing but bows and spells up a tower
	if not alive(u) or u.stun > 0.0 or u.carrying or u.state in ["wind", "recover", "dodge"] or u.workshop_open:
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
	t.hp = minf(t.max_hp, t.hp + rate * dt * _beam_share(t))

func _dodge(u: Dictionary) -> bool:
	if not alive(u) or u.stun > 0.0 or u.carrying or u.cd_dodge > 0.0 or u.state in ["wind","dodge"] or u.workshop_open \
			or int(u.tower) >= 0:
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
	if bool(u.get("bomb_held", false)):
		return _throw_bomb(u)
	if can_pull_lever(u):
		return pull_lever(u)
	var bm := bomb_to_pick(u)
	if not bm.is_empty():
		return _pick_bomb(u, bm)
	if _offering_action(u) != "":
		return _do_offering(u)
	if int(u.get("tower", -1)) >= 0:
		return _leave_tower(u)
	var tw := tower_to_enter(u)
	if not tw.is_empty():
		return _enter_tower(u, tw)
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
		var it := item_to_pick(u)
		if not it.is_empty():
			return _pick_item(u, it)
		if not n.is_empty():
			u.task = {"kind":"gather", "node":n.id, "t":GATHER_TIME}
			u.face = angle_of(n.p - u.pos)
			return true
	if u.cls == "villager":
		# 0.31.22 (Kevin: "don't have hats be auto pickup"): a player takes a hat with ACTION -- a dropped one, else a stand's
		var dh := hat_to_pick(u)
		if not dh.is_empty():
			return _pick_dropped_hat(u, dh)
		var vst := stand_near(u)
		if not vst.is_empty():
			return _take_hat(u, vst)
	var hs := hat_shop_upgrade(u)
	if hs != "":
		var ok := buy_upgrade(u.team, hs, u)
		if ok:
			_event("hat_upgrade", {"id":u.id, "team":u.team, "up":hs})
			_equip_upgrade(u)                         # the one who paid for it wears it straight away
		return ok
	if can_equip_upgrade(u):
		return _equip_upgrade(u)
	if u.cls != "villager" and _swap_hat(u):
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

func at_river_bank(p: Vector2) -> bool:
	# On the field, 0.2 .. FISH_REACH m back from the river's edge (not on a bridge: that's over it).
	var off := Land.river_off(p)
	return absf(p.x) <= HALF_W - 1.0 and off >= 0.2 and off <= FISH_REACH and Land.inside_field(p) and not Land.on_bridge(p, 0.5)

func _offering_action(u: Dictionary) -> String:
	if u.carrying:
		return ""
	if u.offering:
		var captive: Dictionary = oracles[1 - u.team]
		if captive.state == "cell" and int(captive.cakes) < MAX_WEIGHT * CAKE_PER_STAGE \
				and (u.pos.distance_to(captive.pos) <= FEED_RADIUS or u.pos.distance_to(jail_outside(u.team)) <= JAIL_FEED_R):
			return "feed"                              # beside him, or through the bars of his cell door
		return ""
	if u.load.n == 0 and u.task.is_empty() and at_river_bank(u.pos):
		return "fish"
	return ""

func _do_offering(u: Dictionary) -> bool:
	match _offering_action(u):
		"fish":
			u.move = Vector2.ZERO
			u.face = angle_of(Vector2(0.0, Land.river_c(u.pos.x) - u.pos.y))    # face the water
			u.task = {"kind":"fish", "t":FISH_TIME}
			_event("fish_cast", {"id":u.id, "team":u.team, "pos":u.pos})
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
	if bool(u.get("bomb_held", false)):
		return "bomb_throw"
	if can_pull_lever(u):
		return "launch_lever"
	if not bomb_to_pick(u).is_empty():
		return "bomb_pick"
	var off := _offering_action(u)
	if off != "":
		return off
	if int(u.get("tower", -1)) >= 0:
		return "tower_down"
	if not tower_to_enter(u).is_empty():
		return "tower_up"
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
		if not item_to_pick(u).is_empty():
			return "pick_up"
		if not n.is_empty():
			return "chop" if n.kind == "wood" else "mine"
	if u.cls == "villager":
		if not hat_to_pick(u).is_empty():
			return "hat_pick"
		var vst := stand_near(u)
		if not vst.is_empty() and int(vst.stock) > 0:
			return "hat" if can_take_class(u, str(vst.cls)) else "class_full"
	if u.cls != "villager":
		if hat_shop_upgrade(u) != "":
			return "hat_up"
		if can_equip_upgrade(u):
			return "hat_equip_up"
		var st := stand_near(u)
		if not st.is_empty() and st.cls != u.cls and int(st.stock) > 0:
			return "hat" if can_take_class(u, str(st.cls)) else "class_full"
	if u.pos.distance_to(workshop(u.team)) <= WORKSHOP_RADIUS:
		return "workshop"
	return ""

# ---------- hats ----------
func stand_near(u: Dictionary) -> Dictionary:
	# Any team's stand: a stand inside the enemy courtyard works for whoever gets in there.
	for st in stands:
		if u.pos.distance_to(st.p) <= HAT_TAKE_R:
			return st
	return {}

static func in_castle(p: Vector2, team: int) -> bool:
	# Inside team's walls (courtyard or back rooms), in that castle's local coordinates.
	var q := (p if team == 0 else -p) - Vector2(0.0, CASTLE_SHIFT)
	return Castle.inside(q)

func class_count(team: int, cls: String) -> int:
	var n := 0
	for o in units:
		if o.team == team and alive(o) and o.cls == cls:
			n += 1
	return n

func class_full(team: int, cls: String) -> bool:
	return CLASS_CAP.has(cls) and class_count(team, cls) >= int(CLASS_CAP[cls])

func can_take_class(u: Dictionary, cls: String) -> bool:
	return u.cls == cls or not class_full(u.team, cls)

func _take_hat(u: Dictionary, st: Dictionary) -> bool:
	if int(st.stock) <= 0:
		return false
	if not can_take_class(u, str(st.cls)):
		_class_full_note(u, str(st.cls))
		return false
	if u.cls != "villager":
		_drop_hat(u)                                  # swapping: the old hat goes on the ground
	st.stock = int(st.stock) - 1
	_set_class(u, st.cls, int(levels[int(st.team)].get("hat_" + str(st.cls), 0)) > 0)
	_event("hat_take", {"id":u.id, "cls":st.cls, "team":u.team, "stand":st.id, "enemy":int(st.team) != u.team})
	return true

func hat_shop_upgrade(u: Dictionary) -> String:
	# At your own team's hat shop for your current class, with that upgrade not owned yet: the
	# upgrade id you can buy here ("" otherwise). Players upgrade hats only at the shops.
	var st := stand_near(u)
	if st.is_empty() or int(st.team) != u.team or str(st.cls) != u.cls:
		return ""
	var id := "hat_" + str(st.cls)
	if int(levels[u.team].get(id, 0)) >= int(UPGRADES[id].max):
		return ""
	return id

func _swap_hat(u: Dictionary) -> bool:
	var st := stand_near(u)
	if st.is_empty() or st.cls == u.cls:
		return false
	return _take_hat(u, st)

func _drop_hat(u: Dictionary) -> void:
	if u.cls == "villager":
		return
	var dp: Vector3 = u.get("death_push", Vector3.ZERO)
	var fling := Vector2(dp.x, dp.z) * 0.75 + dir_of(rng.randf() * TAU) * 0.6
	var h := {"id":_hat_id, "cls":u.cls, "up":u.up, "pos":u.pos, "t":0.0, "vel":fling}
	_hat_id += 1
	hats.append(h)
	_event("hat_drop", {"hat":h.id, "cls":h.cls, "pos":h.pos, "team":u.team})

func _step_hats(dt: float) -> void:
	for st in stands:
		if int(st.stock) < int(STAND_STOCK.get(st.cls, HAT_STOCK_MAX)):
			st.t += dt
			if st.t >= float(STAND_REGEN.get(st.cls, HAT_REGEN)):
				st.t = 0.0
				st.stock = int(st.stock) + 1
		else:
			st.t = 0.0
	for i in range(hats.size() - 1, -1, -1):
		hats[i].t += dt
		if hats[i].t >= HAT_LIFETIME:
			_event("hat_expire", {"hat":hats[i].id})
			hats.remove_at(i)
	# Bot Villagers take a hat by walking over one (dropped hats first, then any stand they reach); players press ACTION
	# (0.31.22). Bots also swap to the upgraded hat at their stand once the team owns the upgrade.
	for u in units:
		if alive(u) and u.bot and u.cls != "villager" and can_equip_upgrade(u):
			_equip_upgrade(u)
		if not alive(u) or u.cls != "villager" or u.carrying or u.stun > 0.0 or not u.bot:
			continue
		var picked := false
		for i in hats.size():
			var h: Dictionary = hats[i]
			if u.pos.distance_to(h.pos) <= HAT_PICK_R and can_take_class(u, str(h.cls)):
				hats.remove_at(i)
				_set_class(u, h.cls, h.up)
				_event("hat_pick", {"id":u.id, "cls":h.cls, "team":u.team, "hat":h.id})
				picked = true
				break
		if not picked:
			var st := stand_near(u)
			if not st.is_empty():
				_take_hat(u, st)

func nearest_hat(p: Vector2, max_d: float) -> Dictionary:
	var best := {}
	var bd := max_d
	for h in hats:
		var d: float = p.distance_to(h.pos)
		if d < bd:
			bd = d
			best = h
	return best

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
	if not can_take_class(u, "worker"):
		_class_full_note(u, "worker")
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
				if g.team == team and str(g.get("kind", "gate")) != "jail":      # not the jail door
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

func drop_point(u: Dictionary) -> Vector2:
	# The nearest place to deliver a load: the workshop, or an outpost the team holds.
	var best: Vector2 = workshop(u.team)
	var bd: float = u.pos.distance_to(best)
	for op in outposts:
		if int(op.owner) == u.team:
			var p: Vector2 = (op.p as Vector2) + ((u.pos - (op.p as Vector2)).normalized() * 2.2)
			var d: float = u.pos.distance_to(p)
			if d < bd:
				bd = d
				best = p
	return best

func _deliver(u: Dictionary) -> void:
	if u.load.n <= 0:
		return
	var here: bool = u.pos.distance_to(workshop(u.team)) <= WORKSHOP_RADIUS + 0.4
	if not here:
		for op in outposts:
			if int(op.owner) == u.team and u.pos.distance_to(op.p) <= OUTPOST_DROP_R:
				here = true
	if not here:
		return
	stock[u.team][u.load.kind] += u.load.n
	u.gathered += u.load.n
	_event("deliver", {"id":u.id, "team":u.team, "kind":u.load.kind, "n":u.load.n})
	u.load = {"kind":"", "n":0}

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
	dst.hp -= amount
	_stat_add(src, "dmg", amount)
	_stat_add(dst, "taken", amount)
	if stun > 0.0:
		dst.stun = maxf(dst.stun, stun)
	if str(dst.task.get("kind", "")) == "fish":
		_event("fish_lost", {"id":dst.id, "team":dst.team, "pos":dst.pos})
	dst.task = {}
	_event("hit", {"id":dst.id,"by":src.get("id",""),"dmg":int(round(amount))})
	if src.has("pos") and str(src.get("id", "")) != "" and int(src.get("team", -1)) != int(dst.team):
		dst["hurt_by"] = str(src.id)                  # 0.31.27: bots answer whoever is hurting them (or a friend nearby)
		dst["hurt_at"] = time
	if dst.hp <= 0.0:
		_kill(src, dst)
	_next_push = Vector3.ZERO

func _kill(src: Dictionary, dst: Dictionary) -> void:
	if dst.carrying:
		_leave_lift(dst, false)
	if int(dst.tower) >= 0:
		_free_tower_slot(dst)
	dst["hammer_out"] = -1                     # its hammer, if out, drops (_step_hammer)
	_drop_bomb(dst)
	dst.hp = 0.0
	dst.state = "dead"
	dst.beam = ""
	dst.beam2 = ""
	dst.block_until = 0.0
	dst.whirl_until = 0.0
	# Fat Princess rule: your hat falls where you die; you come back as a Villager. (A High Priest can bring you
	# back where you fell before you respawn: remember what you were and which hat you dropped.)
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
	_multi_kill(src, dst)
	_stat_add(src, "kills", 1.0)
	_stat_add(dst, "deaths", 1.0)
	dst["died_cls"] = dst.cls
	dst["died_up"] = dst.up
	dst["died_at"] = time
	var hats_before := hats.size()
	_drop_hat(dst)
	dst["died_hat"] = int(hats[hats.size() - 1].id) if hats.size() > hats_before else -1
	dst.cls = "villager"
	dst.up = false
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
	_event("death", {"id":dst.id,"by":src.get("id",""), "push":[snappedf(push.x, 0.01), snappedf(push.y, 0.01), snappedf(push.z, 0.01)]})

func _damage_gate(src: Dictionary, g: Dictionary, amount: float) -> void:
	if not gate_blocks(g):
		return
	g.hp = maxf(0.0, g.hp - amount)
	g["hit_at"] = time
	if src.has("gate_dmg"):
		src.gate_dmg += amount
	_stat_add(src, "gate", amount)
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
		if o.team == u.team or not alive(o) or int(o.tower) >= 0:
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
		if d2 > reach + float(g.get("r", WALL_R)) + 0.3:
			continue
		if arc > -1.0 and d2 > 0.3 and fwd.dot(off2 / d2) < arc - 0.2:
			continue
		_damage_gate(u, g, dmg * float(CLASSES[u.cls].gate))
		hits += 1
	return hits

static func on_rampart(p: Vector2) -> bool:
	# On a castle's rampart walkway (behind the front wall's middle, Castle.WALK_*).
	var q := (p if p.y >= 0.0 else -p) - Vector2(0.0, CASTLE_SHIFT)
	return absf(q.x) <= Castle.WALK_X and q.y >= FRONT_Z + 0.5 and q.y < Castle.WALK_Z1

func _lob_at_rampart(u: Dictionary, d: Vector2, reach: float) -> bool:
	# A shot aimed (within ~11 deg) at an enemy on a rampart, in range: lobbed over the parapet (Round 38, Kevin:
	# "players should be able to shoot other players on the wall"). Only the walkway -- not every raised floor, or
	# arrows from outside would drop on the terraces deep inside.
	for o in units:
		if o.team == u.team or not alive(o) or not on_rampart(o.pos):
			continue
		var off: Vector2 = o.pos - u.pos
		var dist := off.length()
		if dist < 0.5 or dist > reach + 1.0:
			continue
		if absf(d.angle_to(off)) <= 0.2:
			return true
	return false

func _shoot(u: Dictionary, angle: float, dmg: float, aoe: float, speed: float, reach: float) -> void:
	var d := dir_of(angle)
	projectiles.append({"id":_next_proj,"team":u.team,"owner":u.id,"pos":u.pos + d*0.6,"from":u.pos,"vel":d*speed,
		"dmg":dmg,"aoe":aoe,"life":reach/speed,"kind":"fire" if aoe > 0.0 else "arrow",
		"gate_mult":float(CLASSES[u.cls].gate),
		# Shot from the rampart (or a terrace), or aimed at an enemy ON a rampart, or from the top of a tower:
		# flies over the castle walls and gates (Round 15; Round 38; towers 0.30.0).
		"high":height_at(u.pos) >= 1.5 or _lob_at_rampart(u, d, reach) or int(u.get("tower", -1)) >= 0})
	if int(u.get("tower", -1)) >= 0:
		# Shot from a tower's deck (0.30.4, Kevin: "projectiles are firing from the base"): the view starts it up
		# at the shooter and brings it down onto the aimed target (or over its full reach).
		var pj: Dictionary = projectiles[projectiles.size() - 1]
		pj["h0"] = Land.TOWER_FLOOR
		pj["o"] = u.pos
		var ad := float(u.get("aim_d", 0.0))
		pj["dd"] = ad if ad > 0.5 else reach
	_event("proj", {"pid":_next_proj,"kind":"fire" if aoe > 0.0 else "arrow"})
	_next_proj += 1

func _resolve_attack(u: Dictionary) -> void:
	var c: Dictionary = CLASSES[u.cls]
	var dmg := float(stat(u,"dmg"))
	if u.atk == "attack":
		if c.ranged:
			# 0.31.5 balance: the Mage's fireball does 10 % less (MAGE_BOLT); her nova keeps its damage and size.
			_shoot(u, u.face, dmg * (MAGE_BOLT if u.cls == "mage" else 1.0), float(c.aoe), float(c.proj_speed), float(c.range) * tower_range(u))
		else:
			_melee(u, float(c.range), float(c.arc), dmg)
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
				_shoot(u, u.face + (i-2)*0.13, dmg*0.8, 0.0, float(c.proj_speed), float(c.range) * tower_range(u))
		"nova":
			_melee(u, NOVA_R, -2.0, dmg*1.4)
			_event("nova", {"id":u.id})
		"sanctuary":
			var amount := SANCTUARY_HEAL * (1.4 if u.up else 1.0)
			for a in units:
				if alive(a) and a.team == u.team and a.pos.distance_to(u.pos) <= SANCTUARY_R \
						and time - float(a.get("sanct_t", -INF)) >= SANCT_ONCE:
					a["sanct_t"] = time
					a.hp = minf(a.max_hp, a.hp + amount)
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
	_ai_clock += dt
	_cmd_clock += dt
	var t0 := Time.get_ticks_usec() if profile else 0
	if _ai_clock >= 0.15:
		_ai_clock = 0.0
		_update_rampart_alert()
		for u in units:
			if u.bot:
				_think(u)
	if profile: t0 = _p("think", t0)
	if _cmd_clock >= 2.0:
		_cmd_clock = 0.0
		for t in 2:
			_commander(t)
	_blockers = units.filter(func(k): return blocking(k))
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
	if u.state == "fly":
		_step_flight(u)
		return
	u.cd_dodge = maxf(0.0, u.cd_dodge - dt)
	u.cd_ability = maxf(0.0, u.cd_ability - dt)
	if u.workshop_open and u.pos.distance_to(workshop(u.team)) > WORKSHOP_RADIUS + 0.8:
		u.workshop_open = false
	if u.load.n > 0:
		_deliver(u)
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
	if u.workshop_open:
		u.state = "idle"
		return
	if int(u.tower) >= 0:
		# Up on the deck (0.30.3, Kevin: "walk around on top"): free movement, kept on the deck by _separate.
		if u.move.length() > 0.08:
			u.pos += u.move * speed * dt
			u.face = lerp_angle(u.face, angle_of(u.move), minf(1.0, dt * 14.0))
			u.state = "move"
			# Running off the edge (0.30.4, Kevin): jump down on that side.
			var off: Vector2 = u.pos - ((outposts[int(u.tower)] as Dictionary).p as Vector2)
			if off.length() > Land.TOWER_TOP_R + 0.05 and off.dot(u.move) > 0.0:
				_leave_tower(u)
		else:
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
	mult = move_mult(u, mult)
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
# unit itself. Server-driven states (dead, stunned, carrying, lunging, tasks) stay server-side.
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
	# Speed multipliers for free movement (not the Oracle carry, handled by the caller).
	# Wading (Round 33): slower the deeper it gets, down to WATER_MOVE past ~0.35 m.
	var wd := water_depth(u.pos)
	if wd > 0.0:
		mult *= lerpf(1.0, WATER_MOVE, clampf(wd / 0.35, 0.0, 1.0))
	if u.offering:
		mult = minf(mult, 0.9)
	if not ladders.is_empty():
		var ld := ladder_depth(u.pos, u.team)
		if ld != INF:
			# Slow on the rungs (so the climb reads), quicker over the top, quicker still dropping down.
			mult *= 0.3 if ld >= 0.35 else (0.45 if ld >= -0.35 else 0.7)
	if u.load.n > 0:
		mult = minf(mult, 0.85)
	if str(u.beam) != "":
		mult = minf(mult, BEAM_MOVE)
	if blocking(u):
		mult = minf(mult, BLOCK_MOVE)
	return mult

func client_drivable(u: Dictionary) -> bool:
	if not alive(u) or u.stun > 0.0 or u.carrying or not u.task.is_empty() or u.workshop_open or int(u.get("tower", -1)) >= 0 \
			or u.state == "fly":
		return false
	if u.state == "wind" and CLASSES[u.cls].ability == "lunge" and u.atk == "ability":
		return false
	return u.state in ["idle", "move", "recover", "dodge", "wind"]

func _net_moves(u: Dictionary) -> bool:
	return bool(u.get("net_driven", false)) and client_drivable(u)

func predict_step(u: Dictionary, move: Vector2, dt: float) -> void:
	# The phone's copy of _step_unit's movement for its own unit (same speeds, same collision).
	if int(u.get("tower", -1)) >= 0:
		return                                     # on a tower: the server places it
	var speed := float(stat(u, "speed"))
	if bool(u.get("bomb_held", false)):
		speed *= BOMB_SLOW
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

func _step_task(u: Dictionary, dt: float) -> void:
	var task: Dictionary = u.task
	u.state = str(task.kind)
	task.t -= dt
	if task.t > 0.0:
		return
	match str(task.kind):
		"fish":
			u.task = {}
			u.state = "idle"
			if at_river_bank(u.pos) and not u.offering:
				u.offering = true
				_event("fish_caught", {"id":u.id, "team":u.team, "pos":u.pos})
		"gather":
			var n: Dictionary = nodes[int(task.node)]
			if n.amount <= 0 or u.pos.distance_to(n.p) - n.r > 1.6:
				u.task = {}
				u.state = "idle"
				return
			n.amount -= 1
			_event("gather", {"id":u.id, "node":n.id, "kind":n.kind, "n":u.load.n})
			task.t = GATHER_TIME
			if n.amount <= 0:
				n.t = 0.0
				_fell_node(n, u.pos)
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
			if team >= 0 and w.kind == "wall" and not ladders.is_empty() and on_ladder(p, wi, team):
				continue
			p = _push_seg(p, w.a, w.b, w.r + r)
		if p.distance_squared_to(before) < 0.000001:
			break
	for g in gates:
		# Gates only stop the other team, and only while standing.
		if team != g.team and gate_blocks(g) and not lets_out(g, p):
			p = _push_seg(p, g.a, g.b, float(g.get("r", WALL_R)) + r)
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

func ladder_depth(p: Vector2, team: int) -> float:
	# How far across one of `team`'s ladders p is: + on the ladder's side of the wall (where it stands),
	# - on the far side; INF when not on one.
	for l in ladders:
		if int(l.team) != team:
			continue
		var w: Dictionary = walls[int(l.wall)]
		var along: Vector2 = seg_closest(p, w.a, w.b)
		if along.distance_to(l.p) > LADDER_HALF:
			continue
		var outward := Vector2(0, 1) if int(l.team) == 0 else Vector2(0, -1)
		var d: float = (p - along).dot(outward)
		if absf(d) <= float(w.r) + UNIT_R + 0.6:
			return d
	return INF

static func ladder_lift(d: float, ground: float) -> float:
	# A climber's height at depth d: up the rungs (LADDER_FOOT -> 0.35), a little arc over the top, then a drop
	# to the ground on the far side (accelerating).
	if d == INF or d >= LADDER_FOOT:
		return ground
	if d >= 0.35:
		return maxf(ground, LADDER_TOP * (LADDER_FOOT - d) / (LADDER_FOOT - 0.35))
	if d >= -0.35:
		return LADDER_TOP + 0.15 * (1.0 - (d / 0.35) * (d / 0.35))
	var k := clampf((-0.35 - d) / 1.5, 0.0, 1.0)
	return lerpf(LADDER_TOP, ground, k * k)

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
			if not alive(b) or int(b.tower) != int(a.tower):
				continue                           # the ground and a tower's deck don't touch
			var off: Vector2 = b.pos - a.pos
			var d := off.length()
			if d < UNIT_R*2.0 and d > 0.0001:
				var push := off / d * (UNIT_R*2.0 - d) * 0.5
				a.pos -= push
				b.pos += push
	for u in units:
		if alive(u) and int(u.tower) >= 0:
			u.pos = tower_deck_clamp(u)            # kept on the tower's deck
		elif alive(u):
			# Clamp first: pushing a unit that is slightly past the field edge off a wall end can
			# send it diagonally, and clamping afterwards drops it back inside the wall.
			u.pos = _clamp_to_field(_push_out(_clamp_to_field(u.pos), UNIT_R, u.team))

func _step_projectiles(dt: float) -> void:
	if projectiles.is_empty():
		return
	# Each team's living units as packed positions, built once per tick: a projectile only checks
	# the other team, without dictionary lookups (was ~830 checks/tick through alive(); 1 ms/tick).
	# (Packed arrays are VALUES in Godot 4: appending through `tpos[t] as PackedVector2Array`
	# appended to a copy, so these stayed empty and arrows/bolts hit NO units from 0.16.0 to
	# 0.18.1. Build them as locals.)
	var pos0 := PackedVector2Array()
	var pos1 := PackedVector2Array()
	var tunit := [[], []]
	for o in units:
		if alive(o):
			if o.team == 0:
				pos0.append(o.pos)
			else:
				pos1.append(o.pos)
			(tunit[o.team] as Array).append(o)
	var tpos := [pos0, pos1]
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
		# Swept test: the whole path since last tick (from the shooter on the first tick) against
		# each enemy's hit circle -- an arrow moves 0.73 m a tick, and checking only its new point
		# let glancing shots skip past a target. The nearest hit along the path wins.
		var from: Vector2 = p.get("from", prev)
		p.erase("from")
		var best_t := INF
		var impact := Vector2.ZERO
		for t in ([et] if et >= 0 else [0, 1]):
			var arr: PackedVector2Array = tpos[t]
			for k in arr.size():
				var c: Vector2 = arr[k]
				var cp := seg_closest(c, from, p.pos)
				if c.distance_squared_to(cp) < hit_r2:
					var o: Dictionary = tunit[t][k]
					var along := from.distance_squared_to(cp)
					if alive(o) and o.state != "fly" and along < best_t:        # another projectile may have killed it this tick
						best_t = along
						hit = o
						impact = cp
		if str(p.kind) == "pierce":
			# 0.31.32: the Sniper's shot goes through everyone in its path, each once
			var already: Array = p.get("hit", [])
			var owner_p: Dictionary = by_id.get(str(p.owner), {})
			for t2 in ([et] if et >= 0 else [0, 1]):
				var arr2: PackedVector2Array = tpos[t2]
				for k2 in arr2.size():
					var o2: Dictionary = tunit[t2][k2]
					if already.has(o2.id) or not alive(o2) or o2.state == "fly":
						continue
					if arr2[k2].distance_squared_to(seg_closest(arr2[k2], from, p.pos)) < hit_r2:
						already.append(o2.id)
						_next_push = _push_along(p.vel, 4.0, 1.4)
						_damage(owner_p, o2, float(p.dmg))
						_event("pierce_hit", {"id":o2.id, "pos":o2.pos})
			p["hit"] = already
			hit = {}
		if not hit.is_empty():
			p.pos = impact                            # explode / stop where it struck, not past it
		var blocked := false
		var hit_gate := {}
		var pb := _bucket(p.pos)
		for oi in _bucket_obs_proj[pb]:
			var ob: Dictionary = obstacles[oi]
			if p.pos.distance_to(ob.p) < ob.r:
				blocked = true
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
		# Gates only exist at the castle fronts (|z| = CASTLE_SHIFT + FRONT_Z): skip the check anywhere
		# else (it was ~30 % of the projectile step, measured).
		if not blocked and not bool(p.get("high", false)) and absf(p.pos.y) >= CASTLE_SHIFT + FRONT_Z - 3.0:
			for g in gates:
				if g.team != p.team and gate_blocks(g) and p.pos.distance_to(seg_closest(p.pos, g.a, g.b)) < float(g.get("r", WALL_R)) * 0.8:
					hit_gate = g
					blocked = true
					break
		if hit.is_empty() and not blocked and p.life > 0.0 and absf(p.pos.x) < HALF_W + 2 and absf(p.pos.y) < HALF_L + 2:
			continue
		var owner: Dictionary = by_id.get(p.owner, {"team":p.team})
		if not hit_gate.is_empty():
			_damage_gate(owner, hit_gate, p.dmg * float(p.gate_mult))
		if p.aoe > 0.0:
			if not hit.is_empty():
				_next_push = _push_along(p.vel, 3.6, 1.4)
				_damage(owner, hit, p.dmg)                 # the struck unit: full damage, always
			for o in units:
				if o != hit and o.team != p.team and alive(o) and o.pos.distance_to(p.pos) <= p.aoe:
					_next_push = _push_from(p.pos, o.pos, 4.0, 2.4)
					_damage(owner, o, p.dmg * 0.6)
			_event("boom", {"pos":p.pos})
		elif not hit.is_empty():
			_next_push = _push_along(p.vel, 3.2, 1.2)
			_damage(owner, hit, p.dmg)
		_event("proj_end", {"pid":p.id, "pos":p.pos})      # pos = the impact point (clients fly it there)
		projectiles.remove_at(i)

const DIGEST_EVERY := 75.0          # 0.31.26 (Kevin): a King works off one fish every 75 s -- feeding has to be kept up (40 s made him never fat)

func _step_oracles(dt: float) -> void:
	for o in oracles:
		if int(o.cakes) <= 0:
			o["digest_t"] = 0.0
			continue
		o["digest_t"] = float(o.get("digest_t", 0.0)) + dt
		if float(o.digest_t) >= DIGEST_EVERY:
			o.digest_t = 0.0
			o.cakes = int(o.cakes) - 1
			var w := mini(MAX_WEIGHT, int(o.cakes) / CAKE_PER_STAGE)
			if w != int(o.weight):
				o.weight = w
				_event("digest", {"team":int(o.team), "weight":w, "cakes":int(o.cakes)})
	_step_oracles_inner(dt)

func _step_oracles_inner(dt: float) -> void:
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
						_reset_jail(1 - t)
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
func _step_outposts(dt: float) -> void:
	for op in outposts:
		var n := [0, 0]
		for u in units:
			if alive(u) and int(u.tower) < 0 and u.pos.distance_to(op.p) <= Land.OUTPOST_R:
				n[u.team] += 1
		var dir := 0
		var count := 0
		if n[0] > 0 and n[1] == 0:
			dir = 1
			count = n[0]
		elif n[1] > 0 and n[0] == 0:
			dir = -1
			count = n[1]
		var prog: float = op.prog
		if dir != 0:
			# One unit takes ~9.5 s from neutral to captured, four or more ~4.8 s.
			prog = clampf(prog + dir * (0.07 + 0.035 * mini(count, 4)) * dt, -1.0, 1.0)
		elif n[0] == 0 and n[1] == 0:
			var target := 1.0 if int(op.owner) == 0 else (-1.0 if int(op.owner) == 1 else 0.0)
			prog = move_toward(prog, target, 0.04 * dt)
		# (both teams inside: contested, nothing moves)
		var owner: int = op.owner
		if (owner == 0 and prog <= 0.0) or (owner == 1 and prog >= 0.0):
			op.owner = -1
			_eject_tower(op)
			_event("outpost_lost", {"id":op.id, "team":owner})
		if prog >= 1.0 and int(op.owner) != 0:
			op.owner = 0
			op.t = 0.0
			_event("outpost_captured", {"id":op.id, "team":0})
		elif prog <= -1.0 and int(op.owner) != 1:
			op.owner = 1
			op.t = 0.0
			_event("outpost_captured", {"id":op.id, "team":1})
		op.prog = prog
		if int(op.owner) >= 0:
			op.t += dt
			if op.t >= OUTPOST_TRICKLE:
				op.t = 0.0
				stock[int(op.owner)].wood += 1
				stock[int(op.owner)].stone += 1

func _step_world(dt: float) -> void:
	_step_outposts(dt)
	_step_hats(dt)
	# Gates swing open for allies nearby (visual state), resource nodes regrow.
	for g in gates:
		if g.has("relock"):
			_try_relock(g)
		var open := false
		if gate_blocks(g):
			for u in units:
				if u.team == g.team and alive(u) and u.pos.distance_to(g.c) < GATE_OPEN_RADIUS:
					open = true
					break
			# It also swings open for an enemy walking out (lets_out).
			if not open and g.has("in"):
				for u in units:
					if u.team != g.team and alive(u) and lets_out(g, u.pos) and u.pos.distance_to(g.c) < GATE_OPEN_RADIUS:
						open = true
						break
			# The jail door stays shut while any enemy is near it (Round 14, Kevin).
			if open and str(g.get("kind", "")) == "jail":
				for u in units:
					if u.team != g.team and alive(u) and u.pos.distance_to(g.c) < JAIL_SHUT_R:
						open = false
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
				_next_push = _push_from(sh.to, u.pos, 4.4, 3.6)
				_damage({"team":int(sh.team), "id":"catapult"}, u, CATAPULT_DMG)
		_blast_push(sh.to, CATAPULT_AOE + 1.5, 4.5)
		_blast_nodes(sh.to, CATAPULT_AOE + 0.6, 7.0)     # 0.31.34 (Kevin): a catapult stone breaks trees and boulders too
		_event("catapult_hit", {"team":int(sh.team), "pos":sh.to, "shell":sh.id})
		shells.remove_at(i)
	for n in nodes:
		if n.amount <= 0:
			n.t += dt
			if n.t >= n.regen:
				n.t = 0.0
				n.amount = n.max
				_event("node_regrow", {"node":n.id})
	_step_items(dt)
	_step_meteors(dt)
	_step_hat_motion(dt)
	_step_bombs()
	_step_launchers()
	_stat_time(dt)

func _commander(team: int) -> void:
	# Team quartermaster. Works down a plan and saves for the next item instead of buying
	# whatever is cheapest (which starved the stone-heavy upgrades). A badly damaged gate is the
	# one exception. On the human's team it only spends surplus (2x the cost) so the player gets
	# to choose at the workshop first.
	var human_team := false
	for u in units:
		if not u.bot and u.team == team:
			human_team = true
	var plan := ["armory", "catapult", "hat_knight", "gates", "hat_ranger", "hat_priest", "armory", "launcher", "hat_barbarian", "gates", "hat_mage", "armory", "hat_rogue"]
	if human_team:
		plan.erase("launcher")                       # (0.31.28) a team with a player leaves that big buy to the players
	var seen := {}
	var target := ""
	for id in plan:
		seen[id] = int(seen.get(id, 0)) + 1
		if int(levels[team][id]) < int(seen[id]) and int(levels[team][id]) < int(UPGRADES[id].max):
			target = id
			break
	var damaged := false
	for g in gates:
		if g.team == team and str(g.get("kind", "gate")) != "jail" and (g.broken or g.hp < g.max_hp * 0.5):
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

const ROLE_HATS := {"raid":["rogue", "knight", "barbarian"], "escort":["knight", "priest", "barbarian", "mage"],
	"defend":["ranger", "mage", "priest", "knight"]}

func _bot_hat_goal(u: Dictionary) -> Vector2:
	# A villager bot's way to a class: a dropped hat close by, else a stand of its role's classes
	# (rotated per bot for variety), else any stand with stock. Vector2.INF = no hat to be had.
	var h := nearest_hat(u.pos, BOT_HAT_SEARCH)
	if not h.is_empty() and can_take_class(u, str(h.cls)) and (str(h.cls) != "worker" or u.role == "gather"):
		return h.pos                                  # (0.31.25: raiders no longer pick up a dead worker's tools)
	# Already inside the enemy castle: their stands are right here.
	if in_castle(u.pos, 1 - u.team):
		var best_e := {}
		for st in stands:
			if int(st.team) != u.team and int(st.stock) > 0 and can_take_class(u, str(st.cls)) \
					and (best_e.is_empty() or u.pos.distance_to(st.p) < u.pos.distance_to(best_e.p)):
				best_e = st
		if not best_e.is_empty():
			return best_e.p
	var prefs: Array = (ROLE_HATS.get(u.role, HAT_CLASSES) as Array).duplicate()
	var rot := absi(hash(u.id)) % prefs.size()
	prefs = prefs.slice(rot) + prefs.slice(0, rot)
	for c in prefs + HAT_CLASSES:
		for st in stands:
			if int(st.team) == u.team and st.cls == c and int(st.stock) > 0 and can_take_class(u, c):
				return st.p
	# 0.31.25: every stand is empty -- wait at the preferred one for the next hat (6-12 s) instead of marching out as a
	# Villager and dying
	for st in stands:
		if int(st.team) == u.team and st.cls == prefs[0]:
			return st.p
	return Vector2.INF

func _unstick_check(u: Dictionary) -> void:
	# If a bot wanted to move but barely did, sidestep for a moment.
	u.unstick = maxf(0.0, u.unstick - 0.15)
	if u.move.length() > 0.1 and u.task.is_empty() and u.pos.distance_to(u.last_pos) < 0.1:
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
	# Run from a lit bomb (or one in the air) before anything else.
	for b in bombs:
		if not b.is_empty() and (b.state == "lit" or b.state == "flying") and u.pos.distance_to(b.to if b.state == "flying" else b.p) < BOMB_R + 1.5:
			var away: Vector2 = u.pos - (b.to if b.state == "flying" else b.p)
			u.move = away.normalized() if away.length() > 0.01 else dir_of(u.face + PI)
			return
	if not alive(u) or u.stun > 0.0 or u.state in ["wind","recover","dodge"]:
		return
	if int(u.tower) >= 0:
		_think_tower(u)
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
		var hg := _bot_hat_goal(u)
		if hg != Vector2.INF:
			_nav_to(u, hg, 0.4)
			return
		_think_fighter(u)                         # no hats left anywhere: fight as a villager
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
	# Deliver a full (or stranded) load: no room for another log/rock.
	if u.load.n + ITEM_VALUE > CARRY_MAX:
		_nav_to(u, drop_point(u), 0.8)
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
	# Logs/rocks lying about come first (ours or anyone's): walk to the nearest and pick it up.
	var bi := {}
	var bis := 32.0
	for itm in items:
		if u.load.n > 0 and itm.res != u.load.kind:
			continue
		var si: float = u.pos.distance_to(itm.pos) + (0.0 if itm.res == want else 8.0)
		if si < bis:
			bis = si
			bi = itm
	if not bi.is_empty():
		if _item_dist(u.pos, bi) <= PICK_R:
			u.move = Vector2.ZERO
			_pick_item(u, bi)
		else:
			_nav_to(u, bi.pos, 0.3)
		return
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
			_nav_to(u, drop_point(u), 0.8)
		return
	var stand: Vector2 = best.p + (u.pos - best.p).normalized() * (best.r + 0.8)
	if u.pos.distance_to(best.p) - best.r <= 1.2:
		if u.load.n > 0 and u.load.kind != best.kind:
			_nav_to(u, drop_point(u), 0.8)
			return
		u.move = Vector2.ZERO
		u.face = angle_of(best.p - u.pos)
		u.task = {"kind":"gather", "node":best.id, "t":GATHER_TIME}
	else:
		_nav_to(u, stand, 0.4)

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

func _think_shields(u: Dictionary) -> void:
	if ability_of(u) == "hammer":
		_think_hammer(u)
		return
	# Knight bots raise the shield toward archers/mages in range, or toward anyone close when hurt;
	# berserker bots whirl into a crowd. Movement (the goal) is decided by the rest of the brain.
	if u.carrying:
		return
	if u.cls == "knight":
		_think_knight_shield(u)
	elif ability_of(u) == "whirlwind" and u.cd_ability <= 0.0:
		var near := 0
		for o in units:
			if o.team != u.team and alive(o) and o.pos.distance_to(u.pos) <= 3.0:
				near += 1
		if near >= 2:
			_whirl(u)

func _think_knight_shield(u: Dictionary) -> void:
	# Round 17 (Kevin: "all they do is hold block when enemies are near" -- measured: blocking 98 % of
	# the time, 0 swings, because any archer within 12 m raised the shield). Now the shield goes up only
	# when it matters, and the rest of the time the knight fights:
	#  - an enemy shot will pass within 1.3 m in the next 0.7 s (the shield covers allies behind it too),
	#    unless an enemy is at arm's length and we're healthy (then swing);
	#  - badly hurt with an enemy at arm's length: short guard bursts (1 s, at most every 2.6 s).
	var arm := float(stat(u, "range")) + UNIT_R + 0.3
	var adjacent := nearest_enemy(u, arm)
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
	if incoming != Vector2.ZERO and (adjacent.is_empty() or u.hp < u.max_hp * 0.5):
		u.face = angle_of(incoming)
		_block(u)
		return
	if not adjacent.is_empty() and u.hp < u.max_hp * 0.35:
		if time < float(u.get("guard_until", -1.0)):
			u.face = angle_of(adjacent.pos - u.pos)
			_block(u)
		elif time >= float(u.get("guard_next", 0.0)) and rng.randf() < 0.5:
			u.guard_until = time + 1.0
			u.guard_next = time + 2.6
			u.face = angle_of(adjacent.pos - u.pos)
			_block(u)

func _think_fighter(u: Dictionary) -> void:
	# Shield / whirlwind first; the normal brain below still moves the unit (its attacks are
	# refused while blocking or whirling, so knights advance behind the shield and berserkers
	# chase through the crowd). (u.ai_goal is never set: don't steer by it.)
	_think_shields(u)
	if u.cls == "priest" and not u.carrying and _think_priest(u):
		return
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
	if _bot_climb(u):
		return
	if u.bot and _think_bomb(u):
		return
	if u.bot and _think_launcher(u):
		return
	var goal: Vector2 = u.pos
	var enemy_carrier := oracle_carrier(1 - u.team)    # enemies carrying their Oracle home: stop them
	var ally_carrier := oracle_carrier(u.team)         # we're carrying ours home
	var our_returner := oracle_returner(u.team)        # enemies hauling OUR Oracle back to their cell
	var alarm: Dictionary = _gate_alarm[u.team]
	var short_hands: bool = not ally_carrier.is_empty() and mine.lifters.size() < lifters_needed(mine)
	var captive_loose: bool = theirs.state == "dropped" or (theirs.state == "carried" and int(theirs.carry_team) == u.team and theirs.lifters.size() < lifters_needed(theirs))
	var fish_runner: bool = is_fish_runner(u)
	# A rampart post belongs to a ranged defender that isn't a fish runner; drop it otherwise (a post
	# kept after dying and coming back as another class blocked fishing for the rest of the match).
	if u.has("post") and (not c.ranged or u.role != "defend" or fish_runner):
		u.erase("post")
	if not enemy_carrier.is_empty() and (u.role == "defend" or u.pos.distance_to(enemy_carrier.pos) < 16.0):
		goal = enemy_carrier.pos
	elif not our_returner.is_empty() and (u.role in ["raid", "escort"] or u.pos.distance_to(our_returner.pos) < 16.0):
		goal = our_returner.pos
	elif short_hands and u.role in ["raid", "escort"] and u.pos.distance_to(mine.pos) < 60.0:
		goal = mine.pos
	elif captive_loose and u.role in ["defend", "escort"] and u.pos.distance_to(theirs.pos) < 30.0:
		goal = theirs.pos
	elif u.role == "defend" and c.ranged and not fish_runner and _rampart_post(u) != Vector2.INF:
		goal = _rampart_post(u)                     # man the rampart (Round 16, Kevin)
	elif u.role == "defend" and time - float(alarm.at) < 4.0 and alarm.gate >= 0:
		goal = gates[int(alarm.gate)].c + _inward(u.team) * 2.4
	elif u.role == "escort" and ally_carrier.is_empty() and not _capture_target(u).is_empty():
		# Escorts take outposts the team doesn't hold (forward respawns + resources).
		var cap := _capture_target(u)
		goal = (cap.p as Vector2) + dir_of(float(hash(u.id) % 628) / 100.0) * 2.8
	elif mine.state in ["cell", "dropped"] and u.role in ["raid", "escort", "gather"]:
		goal = mine.pos
		if u.bot and u.role != "gather" and not _assault_on(u):
			goal = _rally_spot(u)                      # 0.31.25: gather outside their castle and go in together
	elif not ally_carrier.is_empty():
		goal = ally_carrier.pos + dir_of(u.face) * 2.0
	elif u.role == "defend":
		# Guard the captive from outside his cell door (0.31.10: the old spot, 2 m from the King, lay behind the cell's
		# back wall, so defenders walked into the cell and ran into that wall all match).
		var side := Vector2(-(jail_outside(u.team) - _c(u.team, CELL_C)).normalized().y, (jail_outside(u.team) - _c(u.team, CELL_C)).normalized().x)
		goal = jail_outside(u.team) + side * (float(absi(hash(u.id)) % 5) - 2.0) * 0.8
	else:
		goal = mine.pos
	var aggro := {"raid":3.5,"escort":6.5,"defend":8.0}.get(u.role, 5.0) as float
	if u.bot and u.role == "raid" and time < float(_assault[u.team].until) and not in_castle(u.pos, 1 - u.team):
		aggro = 2.0                                  # 0.31.25: pushing in, don't get drawn into the field brawl
	if u.cls == "knight":
		aggro += KNIGHT_AGGRO                 # 0.31.7: bot Knights (mostly escorts) step in to fight instead of standing by
	if c.ranged:
		aggro = maxf(aggro, float(c.range) * (0.6 if u.role == "raid" else 0.95))
	var foe := nearest_enemy(u, aggro)
	if u.bot and not u.carrying and not u.offering:
		var hitter := _attacker_to_answer(u)
		if not hitter.is_empty() and (foe.is_empty() or u.pos.distance_to(foe.pos) > 2.5):
			foe = hitter
	if u.cls == "knight" and (foe.is_empty() or u.pos.distance_to(foe.pos) > float(stat(u, "range")) + UNIT_R + 0.6):
		# Knights go for the archers and mages (their shield is made for it) -- Round 17.
		var hunt := {}
		var hd := maxf(aggro, 9.0)
		for o in units:
			if o.team != u.team and alive(o) and bool(CLASSES[o.cls].ranged) and u.pos.distance_to(o.pos) < hd:
				hd = u.pos.distance_to(o.pos)
				hunt = o
		if not hunt.is_empty():
			foe = hunt
	for carrier in [enemy_carrier, our_returner]:
		if not carrier.is_empty() and u.pos.distance_to(carrier.pos) < aggro + 3.0:
			foe = carrier
	var high_shot: bool = c.ranged and (height_at(u.pos) >= 1.5 or (not foe.is_empty() and on_rampart(foe.pos)))
	if not foe.is_empty() and not high_shot and _blocked_line(u.pos, foe.pos, u.team):
		foe = {}   # can't reach through a wall; keep pathing instead (from the rampart they shoot over it)
	if not foe.is_empty() and int(u.get("post", -1)) >= 0 and u.pos.distance_to(goal) >= 0.9 \
			and u.pos.distance_to(foe.pos) > 3.0:
		foe = {}   # on the way up to a rampart post: don't get pulled out through a gate (Round 16)
	if not foe.is_empty() and int(u.get("post", -1)) >= 0 and u.pos.distance_to(goal) < 0.9:
		# On a rampart post: hold it and shoot -- no kiting off the wall.
		u.move = Vector2.ZERO
		if u.pos.distance_to(foe.pos) <= float(c.range) * 0.95:
			u.face = angle_of(foe.pos - u.pos)
			_start_attack(u, "ability" if u.cd_ability <= 0.0 and rng.randf() < 0.3 else "attack")
		return
	if u.hp < u.max_hp * 0.3 and not foe.is_empty() and u.cd_dodge <= 0.0 and rng.randf() < 0.25:
		u.move = (u.pos - foe.pos).normalized()
		_dodge(u)
		return
	if u.bot and u.hp < u.max_hp * 0.35 and not u.carrying and not u.offering and u.cls != "priest" and u.cls != "villager" \
			and (foe.is_empty() or u.pos.distance_to(foe.pos) > 2.2):
		# 0.31.26: badly hurt -- to the nearest priest of ours (its beam and Sanctuary), else back toward the rally
		var healer := {}
		for o in units:
			if o.team == u.team and alive(o) and o.cls == "priest" and o.id != u.id and u.pos.distance_to(o.pos) < 22.0 \
					and (healer.is_empty() or u.pos.distance_to(o.pos) < u.pos.distance_to(healer.pos)):
				healer = o
		if not healer.is_empty():
			if u.pos.distance_to(healer.pos) > 2.0:
				_nav_to(u, healer.pos, 1.6)
			else:
				u.move = Vector2.ZERO
			return
		if not foe.is_empty() and u.role in ["raid", "escort"] and not in_castle(u.pos, 1 - u.team):
			_nav_to(u, _rally_spot(u), 1.0)
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
			if _offering_action(u) == "feed":
				u.move = Vector2.ZERO
				_do_offering(u)
			else:
				_nav_to(u, jail_outside(u.team), 0.4)        # feed through the bars; never walk into the cell
			return
	elif fish_runner and captive.state == "cell" and int(captive.cakes) < MAX_WEIGHT * CAKE_PER_STAGE \
			and time - float(alarm.at) > 3.0 and enemy_carrier.is_empty() and int(u.get("post", -1)) < 0:
		# Fish runs (Round 19): to a spot on our bank of the river, cast, then carry the catch to the cell.
		if str(u.task.get("kind", "")) == "fish":
			u.move = Vector2.ZERO
			return
		var spot := _fish_spot(u)
		if spot != Vector2.INF:
			if u.pos.distance_to(spot) <= 0.8 and at_river_bank(u.pos):
				_do_offering(u)
			else:
				_nav_to(u, spot, 0.4)
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

func _capture_target(u: Dictionary) -> Dictionary:
	var best := {}
	var bd := 70.0
	for op in outposts:
		if int(op.owner) == u.team:
			continue
		var d: float = u.pos.distance_to(op.p)
		if int(op.owner) == -1:
			d *= 0.8                              # neutral ones first
		if d < bd:
			bd = d
			best = op
	return best

func _fish_spot(u: Dictionary) -> Vector2:
	# A clear spot on this team's own bank of the river, the nearest to the unit; cached per unit.
	if u.has("fish_spot"):
		return u.fish_spot
	var side := 1.0 if spawn(u.team).y > 0.0 else -1.0
	var best := Vector2.INF
	for i in range(-20, 21):
		var x := i * 2.0
		var p := Vector2(x, Land.river_c(x) + side * (Land.river_hw(x) + 1.3))
		if not at_river_bank(p) or _blocked_point(p, u.team, UNIT_R + 0.1):
			continue
		if best == Vector2.INF or u.pos.distance_to(p) < u.pos.distance_to(best):
			best = p
	u["fish_spot"] = best
	return best

var _rampart_alert := [-100.0, -100.0]     # when an enemy was last near each castle's front

func _update_rampart_alert() -> void:
	for t in 2:
		var front: Vector2 = _c(t, Vector2(0.0, FRONT_Z - 6.0))
		for u in units:
			if u.team != t and alive(u) and u.pos.distance_to(front) < RAMPART_THREAT_R:
				_rampart_alert[t] = time
				break

func _rampart_post(u: Dictionary) -> Vector2:
	# A post on our rampart while the front is threatened (or was, recently); INF otherwise. Posts are
	# handed out to the first ranged defenders who ask, one each.
	if time - float(_rampart_alert[u.team]) > RAMPART_HOLD:
		u.erase("post")
		return Vector2.INF
	var mine := int(u.get("post", -1))
	if mine < 0:
		var taken := {}
		for o in units:
			if o.team == u.team and o.id != u.id and alive(o) and int(o.get("post", -1)) >= 0:
				taken[int(o.post)] = true
		for i in Castle.RAMPART_POSTS.size():
			if not taken.has(i):
				mine = i
				break
		if mine < 0:
			return Vector2.INF
		u["post"] = mine
	return _c(u.team, Castle.RAMPART_POSTS[mine])

func _blocked_line(a: Vector2, b: Vector2, team: int) -> bool:
	for i in range(1, 6):
		if _blocked_point(a.lerp(b, float(i) / 6.0), team, 0.1):
			return true
	return false

func _fight(u: Dictionary, foe: Dictionary) -> void:
	var c: Dictionary = CLASSES[u.cls]
	var d: float = u.pos.distance_to(foe.pos)
	if u.bot and u.up and u.cls in ["rogue", "ranger", "mage"] and _bot_upgrade_ability(u, foe):
		return
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
			var nova_now: bool = str(c.ability) == "nova" and _melee_count(u, NOVA_R) >= 2      # 0.31.26: a burst, not a single-target nova
			if u.cd_ability <= 0.0 and (nova_now or (str(c.ability) != "nova" and rng.randf() < 0.35)):
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

func _melee_count(u: Dictionary, r: float) -> int:
	var n := 0
	for o in units:
		if o.team != u.team and alive(o) and o.pos.distance_to(u.pos) <= r:
			n += 1
	return n


# ---------- towers (0.26.0) ----------
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

func tower_range(u: Dictionary) -> float:
	return TOWER_RANGE if int(u.get("tower", -1)) >= 0 else 1.0

func tower_deck_clamp(u: Dictionary) -> Vector2:
	var c: Vector2 = (outposts[int(u.tower)] as Dictionary).p
	var off: Vector2 = u.pos - c
	return c + off.limit_length(Land.TOWER_TOP_R)

func tower_to_enter(u: Dictionary) -> Dictionary:
	# The tower this unit could climb right now: archers and mages, at a tower their team holds.
	if not TOWERS_CLIMBABLE or not alive(u) or not TOWER_CLASSES.has(u.cls) or u.carrying or u.offering or int(u.get("tower", -1)) >= 0:
		return {}
	for op in outposts:
		if int(op.owner) == u.team and u.pos.distance_to(op.p) <= TOWER_ENTER_R and (op.occ as Array).size() < TOWER_SLOTS:
			return op
	return {}

func _enter_tower(u: Dictionary, op: Dictionary) -> bool:
	(op.occ as Array).append(u.id)
	u.tower = int(op.id)
	u.task = {}
	u.move = Vector2.ZERO
	u.path = PackedVector2Array()
	u["tower_seen"] = time
	var side: Vector2 = (u.pos - (op.p as Vector2))
	u.pos = (op.p as Vector2) + (side.normalized() if side.length() > 0.01 else Vector2(1, 0)) * Land.TOWER_TOP_R * 0.7
	_event("tower_up", {"id":u.id, "tower":op.id, "team":u.team})
	return true

func _free_tower_slot(u: Dictionary) -> Vector2:
	# Off the tower: back on the ground beside it, on the side the unit faces. Returns that spot.
	var op: Dictionary = outposts[int(u.tower)]
	(op.occ as Array).erase(u.id)
	u.tower = -1
	var off: Vector2 = u.pos - (op.p as Vector2)
	var dirv: Vector2 = off.normalized() if off.length() > 0.3 else dir_of(u.face)     # down the side they stand on
	var spot: Vector2 = (op.p as Vector2) + dirv * (Land.OUTPOST_TOWER_R + UNIT_R + 0.35)
	u.pos = _clamp_to_field(_push_out(_clamp_to_field(spot), UNIT_R, u.team))
	return u.pos

func _leave_tower(u: Dictionary, thrown := false) -> bool:
	if int(u.get("tower", -1)) < 0:
		return false
	var tid := int(u.tower)
	_free_tower_slot(u)
	u.state = "idle"
	if thrown:
		u.stun = maxf(u.stun, 0.8)
	_event("tower_down", {"id":u.id, "tower":tid, "team":u.team, "thrown":thrown})
	return true

func _eject_tower(op: Dictionary) -> void:
	for id in (op.occ as Array).duplicate():
		var o: Dictionary = by_id.get(id, {})
		if not o.is_empty():
			_leave_tower(o, true)
	(op.occ as Array).clear()

func _think_tower(u: Dictionary) -> void:
	# A bot on a tower shoots whatever comes in range and climbs down once things go quiet (or our
	# King needs everyone).
	u.move = Vector2.ZERO
	var foe := nearest_enemy(u, float(CLASSES[u.cls].range) * TOWER_RANGE * 0.95)
	if not foe.is_empty():
		u["tower_seen"] = time
		u.face = angle_of(foe.pos - u.pos)
		_start_attack(u, "ability" if u.cls == "ranger" and u.cd_ability <= 0.0 and rng.randf() < 0.3 else "attack")
		return
	var urgent: bool = not oracle_carrier(1 - u.team).is_empty() or not oracle_returner(u.team).is_empty() \
		or not oracle_carrier(u.team).is_empty()
	if urgent or time - float(u.get("tower_seen", time)) > 8.0:
		_leave_tower(u)

func _bot_climb(u: Dictionary) -> bool:
	# Archer and mage bots climb a tower we hold when a fight comes near it (not raiders, not while a
	# King is on the move). True when this tick's move is decided.
	if not TOWERS_CLIMBABLE or not TOWER_BOTS or not TOWER_SHOOTERS.has(u.cls) or u.role == "raid" or u.offering or u.has("post") or u.carrying:
		return false
	if not oracle_carrier(1 - u.team).is_empty() or not oracle_carrier(u.team).is_empty() or not oracle_returner(u.team).is_empty():
		return false
	var best := {}
	var bd := 14.0
	for op in outposts:
		if int(op.owner) != u.team:
			continue
		var d: float = u.pos.distance_to(op.p)
		if d > bd:
			continue
		var bots := 0
		for id in op.occ:
			if bool((by_id.get(id, {}) as Dictionary).get("bot", false)):
				bots += 1
		if bots >= TOWER_BOT_MAX or (op.occ as Array).size() >= TOWER_SLOTS:
			continue
		var threat := false
		for o in units:
			if o.team != u.team and alive(o) and (o.pos as Vector2).distance_to(op.p) < 18.0:
				threat = true
				break
		if threat:
			bd = d
			best = op
	if best.is_empty():
		return false
	if u.pos.distance_to(best.p) <= TOWER_ENTER_R - 0.3:
		u.move = Vector2.ZERO
		return _enter_tower(u, best)
	var side: Vector2 = (u.pos - (best.p as Vector2)).normalized()
	_nav_to(u, (best.p as Vector2) + side * (Land.OUTPOST_TOWER_R + 1.0), 0.4)
	return true


static func _lane_cell(p: Vector2) -> bool:
	# On the island lane: its two bridges or the island between them.
	if Land.island_off(p) < 0.5:
		return true
	for b in Land.bridges():
		if bool(b.lane) and absf(p.x - (b.c as Vector2).x) <= float(b.half_w) + 0.6 and absf(p.y - (b.c as Vector2).y) <= float(b.half_len):
			return true
	return false


# ---------- the Crusader's Hammer Throw (0.30.5, Kevin: the Knight's upgrade) ----------
# The hammer flies HAMMER_RANGE straight ahead through everyone in its path, then comes back to wherever the
# Crusader is now, hitting each enemy once going out and once coming back (one swing's damage each time). Walls
# and gates turn it round early. No swinging while it is out; not from a tower's deck (only bows and spells there).
const HAMMER_RANGE := 9.0
const HAMMER_SPEED := 17.0
const HAMMER_CD := 10.0
const HAMMER_HIT_R := 0.55

func _throw_hammer(u: Dictionary) -> bool:
	if not alive(u) or u.stun > 0.0 or u.carrying or u.cd_ability > 0.0 or int(u.get("tower", -1)) >= 0 \
			or u.state in ["wind", "dodge"] or int(u.get("hammer_out", -1)) >= 0 or u.workshop_open:
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
	for o in tunit[1 - int(p.team)]:
		if (p.hit as Array).has(o.id) or not alive(o):
			continue
		if (o.pos as Vector2).distance_to(p.pos) < r:
			(p.hit as Array).append(o.id)
			_next_push = _push_along(p.vel, 4.6, 2.2)      # a hammer kill throws him the way it was going
			_damage(owner, o, float(p.dmg))
	return false

func _think_hammer(u: Dictionary) -> void:
	# Bots throw when two or more enemies line up within reach, or one stands back out of sword range.
	if u.cd_ability > 0.0 or int(u.get("hammer_out", -1)) >= 0 or u.carrying or int(u.get("tower", -1)) >= 0:
		return
	var foe := nearest_enemy(u, HAMMER_RANGE - 0.5)
	if foe.is_empty():
		return
	var d: Vector2 = ((foe.pos as Vector2) - u.pos).normalized()
	var lined := 0
	for o in units:
		if o.team == u.team or not alive(o) or int(o.tower) >= 0:
			continue
		var q: Vector2 = (o.pos as Vector2) - u.pos
		var along := q.dot(d)
		if along > 0.0 and along < HAMMER_RANGE and absf(q.cross(d)) < 1.0:
			lined += 1
	if lined >= 2 or (lined >= 1 and u.pos.distance_to(foe.pos) > 3.5):
		u.face = angle_of(d)
		_throw_hammer(u)


# ---------- loose logs and rocks (0.31.0, Kevin: "when chopping down a tree I want it to turn into logs and give the logs
# physics where they will roll and can get pushed around if player walk into them. Player will then have to click to pick
# the logs up. Do the same with the iron") ----------
# A felled tree drops LOGS_PER_TREE logs, a broken boulder ROCKS_PER_BOULDER rocks, each worth ITEM_VALUE. They are simple
# 2D bodies: units shove them as they walk into them (logs spin when hit off-centre), they roll down slopes (a log rolls
# sideways easily and slides along its length hardly at all), logs float off downstream in the river and rocks drag,
# walls and gates stop them. A Worker picks one up with ACTION. Unclaimed ones vanish after ITEM_LIFE.
const TREE_CHOPS := 5
const ROCK_HITS := 6
const NODE_REGROW := {"wood":35.0, "stone":45.0}
const LOGS_PER_TREE := 4
const ROCKS_PER_BOULDER := 4
const ITEM_VALUE := 2
const ITEM_LIFE := 150.0
const LOG_HALF := 0.85
const LOG_R := 0.24
const ROCK_R := 0.32
const PICK_R := 1.25
const ITEM_SLOPE_G := 7.0
const RIVER_FLOW := Vector2(-0.7, 0.0)
var _next_item := 1
var _item_last := {}

func _fell_node(n: Dictionary, from: Vector2, blast := 0.0) -> void:
	var is_log := str(n.kind) == "wood"
	var cnt := LOGS_PER_TREE if is_log else ROCKS_PER_BOULDER
	var away: Vector2 = ((n.p as Vector2) - from).normalized() if from.distance_to(n.p) > 0.1 else Vector2(1, 0)
	for k in cnt:
		var p: Vector2
		var vel: Vector2
		var ang := 0.0
		if blast > 0.0:
			# 0.31.33: blown apart by an explosion -- every piece flung away from the blast, spread a little
			var spread := away.rotated(rng.randf_range(-0.7, 0.7))
			p = (n.p as Vector2) + spread * (n.r * 0.6) + Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3))
			vel = spread * blast * rng.randf_range(0.7, 1.15)
			ang = rng.randf() * TAU
		elif is_log:
			# The trunk falls away from the axe and lies in pieces along where it fell, rolling apart a little.
			var side := Vector2(-away.y, away.x)
			p = (n.p as Vector2) + away * (n.r + 0.6 + k * 1.15) + side * rng.randf_range(-0.35, 0.35)
			ang = angle_of(side) + rng.randf_range(-0.25, 0.25)
			vel = side * rng.randf_range(-1.2, 1.2) + away * 0.6
		else:
			var a := TAU * k / cnt + rng.randf_range(-0.5, 0.5)
			var d := Vector2(cos(a), sin(a))
			p = (n.p as Vector2) + d * (n.r + 0.45)
			vel = d * rng.randf_range(1.8, 3.2)
		p = _clamp_to_field(_push_out(p, LOG_R if is_log else ROCK_R))
		items.append({"id":_next_item, "kind":"log" if is_log else "rock", "res":n.kind, "pos":p, "vel":vel, "ang":ang,
			"spin":rng.randf_range(-4.0, 4.0) if blast > 0.0 else 0.0, "roll":0.0, "rax":angle_of(vel), "born":time, "val":ITEM_VALUE})
		if blast > 0.0:
			var vz := rng.randf_range(BLAST_VZ * 0.85, BLAST_VZ * 1.15)
			items[items.size() - 1]["air_vz"] = vz
			items[items.size() - 1]["air_end"] = time + 2.0 * vz / ITEM_G
		_next_item += 1
	_event("node_fell", {"node":n.id, "kind":n.kind, "pos":n.p, "blast":blast, "from":from})

const BLAST_VZ := 7.5             # m/s up for a piece thrown by a blast (its flight: 2 vz / ITEM_G, about 0.9 s)
const ITEM_G := 16.0               # the view's fall for logs and rocks matches this

func _blast_nodes(at: Vector2, radius: float, speed: float) -> void:
	# 0.31.33 (Kevin): an explosion fells the trees and shatters the boulders in its reach; the logs and rocks fly
	# away from it (they regrow as if worked out)
	for n in nodes:
		if int(n.amount) <= 0:
			continue
		if (n.p as Vector2).distance_to(at) <= radius + float(n.r):
			n.amount = 0
			n.t = 0.0
			_fell_node(n, at, speed)

func _item_axis(it: Dictionary) -> Vector2:
	return dir_of(float(it.ang))

func _item_dist(p: Vector2, it: Dictionary) -> float:
	# Distance from p to the item's surface (logs are capsules, rocks are balls).
	if it.kind == "log":
		var ax := _item_axis(it)
		var t := clampf((p - (it.pos as Vector2)).dot(ax), -LOG_HALF, LOG_HALF)
		return p.distance_to((it.pos as Vector2) + ax * t) - LOG_R
	return p.distance_to(it.pos) - ROCK_R

func item_to_pick(u: Dictionary) -> Dictionary:
	if not alive(u) or u.cls != "worker" or u.carrying or int(u.get("tower", -1)) >= 0:
		return {}
	var best := {}
	var bd := PICK_R
	for it in items:
		if u.load.n + int(it.val) > CARRY_MAX or (u.load.n > 0 and u.load.kind != it.res):
			continue
		var d := _item_dist(u.pos, it)
		if d <= bd:
			bd = d
			best = it
	return best

func _pick_item(u: Dictionary, it: Dictionary) -> bool:
	items.erase(it)
	u.load = {"kind":it.res, "n":u.load.n + int(it.val)}
	u.face = angle_of((it.pos as Vector2) - u.pos)
	_event("item_pickup", {"id":u.id, "kind":it.kind, "item":it.id, "n":u.load.n})
	return true

func _ground_grad(p: Vector2) -> Vector2:
	var e := 0.5
	return Vector2(height_at(p + Vector2(e, 0)) - height_at(p - Vector2(e, 0)),
		height_at(p + Vector2(0, e)) - height_at(p - Vector2(0, e))) / (2.0 * e)

func _step_items(dt: float) -> void:
	if items.is_empty():
		_item_last.clear()
		return
	# How each unit moved this tick (its shove).
	var uvel := {}
	for u in units:
		if alive(u) and int(u.get("tower", -1)) < 0:
			var last: Vector2 = _item_last.get(u.id, u.pos)
			uvel[u.id] = ((u.pos as Vector2) - last) / maxf(dt, 0.001)
			_item_last[u.id] = u.pos
	for i in range(items.size() - 1, -1, -1):
		var it: Dictionary = items[i]
		if time - float(it.born) > ITEM_LIFE:
			items.remove_at(i)
			_event("item_gone", {"item":it.id})
			continue
		var is_log: bool = it.kind == "log"
		var r := LOG_R if is_log else ROCK_R
		var vel: Vector2 = it.vel
		if time < float(it.get("air_end", -1.0)):
			# 0.31.35: thrown by a blast -- in the air, flying straight out at its launch speed (no ground friction,
			# slopes, river or shoves until it lands; walls still stop it)
			it.pos = _clamp_to_field(_push_out((it.pos as Vector2) + vel * dt, r))
			it.roll = float(it.roll) + vel.length() * dt / r * 0.5
			it["asleep"] = false
			continue
		if it.has("air_end"):
			it.erase("air_end")
			it.vel = vel * 0.55                         # it lands: some of the speed is lost, the rest slides/rolls on
			vel = it.vel
		# Resting and nobody near: nothing to do (0.31.8 perf: most logs lie still most of the time).
		var near_unit := false
		for u in units:
			if uvel.has(u.id) and (u.pos as Vector2).distance_squared_to(it.pos) < 9.0:
				near_unit = true
				break
		if vel == Vector2.ZERO and not near_unit and bool(it.get("asleep", false)):
			continue
		# Shoves: anyone walking into it pushes it out of the way (logs spin when hit off-centre).
		for u in units:
			if not uvel.has(u.id) or (u.pos as Vector2).distance_squared_to(it.pos) > 16.0:
				continue
			var up: Vector2 = u.pos
			var cp: Vector2 = it.pos
			if is_log:
				var ax0 := _item_axis(it)
				cp = (it.pos as Vector2) + ax0 * clampf((up - (it.pos as Vector2)).dot(ax0), -LOG_HALF, LOG_HALF)
			var dvec := cp - up
			var dist := dvec.length()
			if dist >= UNIT_R + r or dist < 0.0001:
				continue
			var nrm := dvec / dist
			it.pos = (it.pos as Vector2) + nrm * (UNIT_R + r - dist)
			var push: float = maxf(0.0, (uvel[u.id] as Vector2).dot(nrm))
			var vn := vel.dot(nrm)
			if vn < push * 1.1:
				vel += nrm * (push * 1.1 - vn)
			if is_log:
				var lever := (cp - (it.pos as Vector2))
				it.spin = float(it.spin) + (lever.x * nrm.y - lever.y * nrm.x) * push * 0.9
		# Slopes: downhill; a log rolls sideways, barely slides lengthways. (The ground's slope is re-read every 6th tick.)
		if not it.has("grad") or int(it.get("grad_t", 0)) <= 0 or (it.pos as Vector2).distance_squared_to(it.get("grad_p", Vector2.INF)) > 0.25:
			it["grad"] = _ground_grad(it.pos)
			it["grad_p"] = it.pos
			it["grad_t"] = 6
		it["grad_t"] = int(it.grad_t) - 1
		var acc: Vector2 = -(it.grad as Vector2) * ITEM_SLOPE_G
		var wet := water_depth(it.pos) > 0.15
		if is_log:
			var ax := _item_axis(it)
			var side := Vector2(-ax.y, ax.x)
			acc = side * acc.dot(side) + ax * acc.dot(ax) * 0.12
		vel += acc * dt
		if wet:
			if is_log:
				vel = vel.lerp(RIVER_FLOW, minf(1.0, dt * 1.2))      # floats off downstream
			else:
				vel *= exp(-6.0 * dt)
		# Friction.
		if is_log:
			var ax2 := _item_axis(it)
			var sd := Vector2(-ax2.y, ax2.x)
			var vs := vel.dot(sd) * (1.0 if wet else exp(-1.1 * dt))       # afloat: the current's drag only
			var va := vel.dot(ax2) * (1.0 if wet else exp(-7.0 * dt))
			vel = sd * vs + ax2 * va
			it.roll = float(it.roll) + vs * dt / LOG_R
			it.ang = float(it.ang) + float(it.spin) * dt
			it.spin = float(it.spin) * exp(-3.5 * dt)
		else:
			vel *= exp(-2.2 * dt)
			if vel.length() > 0.05:
				it.rax = angle_of(vel)
			it.roll = float(it.roll) + vel.length() * dt / ROCK_R
		if not wet and vel.length() < 0.04 and acc.length() < 0.6:
			vel = Vector2.ZERO                         # settled (in the river a log keeps drifting)
		it["asleep"] = vel == Vector2.ZERO and not wet and acc.length() < 0.6
		# Move; walls, gates, trees and towers stop it (a little bounce).
		var want: Vector2 = (it.pos as Vector2) + vel * dt
		var got := _push_out(want, r + (0.2 if is_log else 0.0))
		if is_log:
			var ax3 := _item_axis(it)
			for end in [-1.0, 1.0]:
				var e: Vector2 = got + ax3 * LOG_HALF * end
				var fixed := _push_out(e, r)
				got += (fixed - e) * 0.5
		got = _clamp_to_field(got)
		if got.distance_to(want) > 0.001:
			var hit := (got - want).normalized()
			var into := vel.dot(hit)
			if into < 0.0:
				vel -= hit * into * 1.3
		it.pos = got
		it.vel = vel
	# Items keep apart from each other.
	for a in items.size():
		for b in range(a + 1, items.size()):
			var ia: Dictionary = items[a]
			var ib: Dictionary = items[b]
			var ra: float = 0.55 if ia.kind == "log" else ROCK_R
			var rb: float = 0.55 if ib.kind == "log" else ROCK_R
			var off: Vector2 = (ib.pos as Vector2) - (ia.pos as Vector2)
			var d := off.length()
			if d < ra + rb and d > 0.0001:
				var push := off / d * (ra + rb - d) * 0.5
				ia.pos = (ia.pos as Vector2) - push
				ib.pos = (ib.pos as Vector2) + push


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
	if not alive(u) or u.stun > 0.0 or u.cd_ability > 0.0 or u.carrying or int(u.get("tower", -1)) >= 0 or u.state in ["wind", "dodge"]:
		return false
	var a := resurrect_target(u)
	if a.is_empty():
		return false
	var hid := int(a.get("died_hat", -1))
	for h in hats:
		if int(h.id) == hid and can_take_class(a, str(a.get("died_cls", "villager"))):
			hats.erase(h)
			a.cls = str(a.get("died_cls", "villager"))
			a.up = bool(a.get("died_up", false))
			_event("hat_pick", {"hat":hid, "id":a.id, "cls":a.cls})
			break
	a.max_hp = float(stat(a, "hp"))
	a.hp = a.max_hp * RESURRECT_HP
	a.state = "idle"
	a.t = 0.0
	a.stun = 0.0
	a.respawn_at = INF
	a.task = {}
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
		ally.hp = minf(ally.max_hp, ally.hp + NECRO_ALLY_HEAL * dt * _beam_share(ally))
	else:
		u.beam2 = ""


func _class_full_note(u: Dictionary, cls: String) -> void:
	# Tell the player once per try (bots never ask for a full class).
	if not bool(u.get("bot", false)) and time - float(u.get("full_note_t", -10.0)) > 1.5:
		u["full_note_t"] = time
		_event("class_full", {"id":u.id, "cls":cls, "team":u.team, "n":class_count(u.team, cls), "cap":int(CLASS_CAP.get(cls, 0))})


func _beam_share(t: Dictionary) -> float:
	# The first beam to heal t this tick heals in full; any more heal at BEAM_STACK.
	if float(t.get("beam_heal_t", -1.0)) == time:
		return BEAM_STACK
	t["beam_heal_t"] = time
	return 1.0

# Per-class combat stats for balance tuning (0.31.4): {label: {dmg, taken, kills, deaths, time}} -- "time" is seconds
# alive in that class (sampled each step by _stat_time). Labels are class_label() (upgrades counted separately).
var class_stats := {}

func _stat_add(u: Dictionary, key: String, v: float) -> void:
	if u.is_empty() or not u.has("cls"):
		return
	var lbl: String = class_label(u)
	if not class_stats.has(lbl):
		class_stats[lbl] = {"dmg":0.0, "taken":0.0, "kills":0.0, "deaths":0.0, "time":0.0, "gate":0.0}
	class_stats[lbl][key] = float(class_stats[lbl][key]) + v

func _stat_time(dt: float) -> void:
	for u in units:
		if alive(u):
			_stat_add(u, "time", dt)


# Fish runners (0.31.6, Kevin: "I don't think bots fish and feed the King"): measured, they did, but only the defenders whose id
# hashed even -- one per team on average, none in some matches (seed 22: one team fed the enemy King 0 times in 12 minutes).
# Now the first FISH_RUNNERS defenders of each team are runners, every match.
const FISH_RUNNERS := 1           # one per team: the other defenders keep their rampart posts
var _fish_runners := {}

func is_fish_runner(u: Dictionary) -> bool:
	if not _fish_runners.has(u.team):
		var ids := []
		for o in units:
			if o.team == u.team and o.role == "defend" and ids.size() < FISH_RUNNERS:
				ids.append(o.id)
		_fish_runners[u.team] = ids
	return (_fish_runners[u.team] as Array).has(u.id)


# 0.31.7 (Kevin: make the bot Knight change). Measured: bot Knights hit 80 % of their swings and block under 1 % of the time --
# they just swung a quarter as often as Rogues because, as escorts, they only engaged within 6.5 m. They now engage further.
const KNIGHT_AGGRO := 3.0


# The jail door's outer side (0.31.10): where bots guard the captive and feed him through the bars.
const JAIL_FEED_R := 1.3

func jail_outside(castle_team: int) -> Vector2:
	var cell: Vector2 = _c(castle_team, CELL_C)
	for g in gates:
		if int(g.team) == castle_team and str(g.get("kind", "")) == "jail":
			var c: Vector2 = g.c
			return c + (c - cell).normalized() * 1.5
	return cell


# ---------- the bomb (0.31.19) ----------
const BOMB_FIRST := 40.0          # the first bomb at each workshop
const BOMB_RESPAWN := 45.0        # the next, after one goes off
const BOMB_PICK_R := 1.6
const BOMB_THROW := 9.0           # how far it's thrown
const BOMB_FLIGHT := 0.75
const BOMB_FUSE := 2.4            # from the throw that lit it
const BOMB_R := 4.5               # blast radius: everyone inside dies
const BOMB_GATE := 0.5            # of a door's full health
const BOMB_SLOW := 0.85           # a carrier's speed

func bomb_spot(team: int) -> Vector2:
	# beside the workshop, towards the middle of the castle, outside its ACTION ring
	var w := workshop(team)
	return w + (_c(team, Vector2(0.0, 18.0)) - w).normalized() * (WORKSHOP_RADIUS + 1.0)

func bomb_to_pick(u: Dictionary) -> Dictionary:
	if u.carrying or u.offering or int(u.get("tower", -1)) >= 0 or not u.task.is_empty() or bool(u.get("bomb_held", false)):
		return {}
	for b in bombs:
		if not b.is_empty() and b.state in ["ready", "loose", "lit"] and u.pos.distance_to(b.p) <= BOMB_PICK_R:
			return b
	return {}

func _pick_bomb(u: Dictionary, b: Dictionary) -> bool:
	b.state = "carried"
	b.carrier = u.id
	b.h = 1.9
	u["bomb_held"] = true
	u.workshop_open = false
	_event("bomb_pick", {"id":u.id, "team":u.team, "bomb":b.team, "lit":float(b.lit_at) >= 0.0})
	return true

func held_bomb(u: Dictionary) -> Dictionary:
	for b in bombs:
		if not b.is_empty() and b.state == "carried" and str(b.carrier) == str(u.id):
			return b
	return {}

func _throw_bomb(u: Dictionary) -> bool:
	var b := held_bomb(u)
	u["bomb_held"] = false
	if b.is_empty() or not alive(u):
		return false
	var to := _push_out(u.pos + dir_of(u.face) * BOMB_THROW, 0.3)
	b.state = "flying"
	b.from = u.pos
	b.to = to
	b.t0 = time
	b.by = u.id
	b.carrier = ""
	if float(b.lit_at) < 0.0:
		b.lit_at = time                        # the throw lights the fuse (a re-thrown lit bomb keeps its fuse)
	_event("bomb_throw", {"id":u.id, "team":u.team, "from":u.pos, "to":to, "fuse":BOMB_FUSE - (time - float(b.lit_at))})
	return true

func _drop_bomb(u: Dictionary) -> void:
	if not bool(u.get("bomb_held", false)):
		return
	u["bomb_held"] = false
	var b := held_bomb(u)
	if b.is_empty():
		return
	b.state = "lit" if float(b.lit_at) >= 0.0 else "loose"
	b.p = u.pos
	b.h = 0.0
	b.carrier = ""
	_event("bomb_drop", {"id":u.id, "team":u.team})

func _step_bombs() -> void:
	for t in 2:
		var b: Dictionary = bombs[t]
		if b.is_empty():
			if time >= float(bomb_next[t]):
				bombs[t] = {"id":t, "team":t, "state":"ready", "p":bomb_spot(t), "h":0.0, "carrier":"", "by":"",
					"from":Vector2.ZERO, "to":Vector2.ZERO, "t0":0.0, "lit_at":-1.0}
				_event("bomb_spawn", {"team":t, "pos":bomb_spot(t)})
			continue
		match str(b.state):
			"carried":
				var c: Dictionary = by_id.get(str(b.carrier), {})
				if c.is_empty() or not alive(c) or not bool(c.get("bomb_held", false)):
					b.state = "lit" if float(b.lit_at) >= 0.0 else "loose"
					b.h = 0.0
					b.carrier = ""
				else:
					b.p = c.pos
			"flying":
				var k := clampf((time - float(b.t0)) / BOMB_FLIGHT, 0.0, 1.0)
				b.p = (b.from as Vector2).lerp(b.to, k)
				b.h = lerpf(1.7, 0.0, k) + 3.0 * k * (1.0 - k)
				if k >= 1.0:
					b.state = "lit"
					b.h = 0.0
					_event("bomb_land", {"team":t, "pos":b.p})
		if float(b.lit_at) >= 0.0 and time >= float(b.lit_at) + BOMB_FUSE:
			_explode_bomb(b)

func _explode_bomb(b: Dictionary) -> void:
	var at: Vector2 = b.p
	if b.state == "carried":                   # it went off in someone's hands
		var c: Dictionary = by_id.get(str(b.carrier), {})
		if not c.is_empty():
			c["bomb_held"] = false
	var thrower: Dictionary = by_id.get(str(b.by), {})
	var killed := 0
	for u in units:
		if alive(u) and u.pos.distance_to(at) <= BOMB_R:
			# kill credit only for enemies: blowing up your own side scores nothing
			var close := 1.0 - 0.45 * clampf(u.pos.distance_to(at) / BOMB_R, 0.0, 1.0)
			_next_push = _push_from(at, u.pos, 5.2 * close, 4.2 * close)      # blown off their feet, away from it
			_kill(thrower if (not thrower.is_empty() and thrower.team != u.team) else {}, u)
			killed += 1
	var src: Dictionary = thrower if not thrower.is_empty() else {"id":""}
	for g in gates:
		if g.broken or at.distance_to(seg_closest(at, g.a, g.b)) > BOMB_R:
			continue
		if str(g.get("kind", "")) == "jail":
			g.hp = 0.0                          # the whole jail door
			g.broken = true
			g["broken_at"] = time
			_update_gate_nav()
			_event("gate_broken", {"gate":g.id, "team":g.team, "by":src.get("id", "")})
		else:
			var was_open: bool = not gate_blocks(g)
			if was_open:
				g.hp = maxf(0.0, g.hp - float(g.max_hp) * BOMB_GATE)    # an open door still takes the blast
				if g.hp <= 0.0:
					g.broken = true
					g["broken_at"] = time
					_update_gate_nav()
					_event("gate_broken", {"gate":g.id, "team":g.team, "by":src.get("id", "")})
			else:
				_damage_gate(src, g, float(g.max_hp) * BOMB_GATE)
	_blast_push(at, BOMB_R + 2.0, 7.0)
	_blast_nodes(at, BOMB_R, 9.0)
	_event("bomb_boom", {"team":b.team, "pos":at, "killed":killed, "by":str(b.by)})
	bombs[int(b.team)] = {}
	bomb_next[int(b.team)] = time + BOMB_RESPAWN


# ---------- the killing blow's push, and hats that slide (0.31.20) ----------
func _push_along(v: Vector2, speed: float, up: float) -> Vector3:
	var d := v.normalized() if v.length() > 0.01 else Vector2(0.0, 1.0)
	return Vector3(d.x * speed, up, d.y * speed)

func _push_from(from: Vector2, to: Vector2, speed: float, up: float) -> Vector3:
	var d := to - from
	d = d.normalized() if d.length() > 0.01 else dir_of(rng.randf() * TAU)
	return Vector3(d.x * speed, up, d.y * speed)

const HAT_FRICTION := 3.2           # m/s lost per second on the ground
const HAT_R := 0.26
var _hat_last := {}
func _step_hat_motion(dt: float) -> void:
	if hats.is_empty():
		_hat_last.clear()
		return
	# 0.31.21 (Kevin: "weapons and hats pushed around on the ground"): whoever walks into a hat kicks it along, as with
	# the logs and rocks (a Villager who can wear it picks it up instead -- _step_hats).
	var uvel := {}
	for u in units:
		if alive(u) and int(u.get("tower", -1)) < 0:
			var last: Vector2 = _hat_last.get(u.id, u.pos)
			uvel[u.id] = ((u.pos as Vector2) - last) / maxf(dt, 0.001)
			_hat_last[u.id] = u.pos
	for h in hats:
		for u in units:
			if not uvel.has(u.id) or (u.pos as Vector2).distance_squared_to(h.pos) > 1.0:
				continue
			if u.cls == "villager" and can_take_class(u, str(h.cls)):
				continue
			var dvec: Vector2 = (h.pos as Vector2) - (u.pos as Vector2)
			var dist := dvec.length()
			if dist >= UNIT_R + HAT_R or dist < 0.0001:
				continue
			var nrm := dvec / dist
			h.pos = (h.pos as Vector2) + nrm * (UNIT_R + HAT_R - dist)
			var kick: float = maxf(0.0, (uvel[u.id] as Vector2).dot(nrm))
			var hv: Vector2 = h.get("vel", Vector2.ZERO)
			if hv.dot(nrm) < kick * 1.25:
				h["vel"] = hv + nrm * (kick * 1.25 - hv.dot(nrm))
	for h in hats:
		var v: Vector2 = h.get("vel", Vector2.ZERO)
		var wet := water_depth(h.pos) > 0.15
		if v == Vector2.ZERO and not wet:
			continue
		if wet:
			v = v.lerp(RIVER_FLOW, minf(1.0, dt * 1.2))                          # floats off downstream, as the logs do
		else:
			v += -_ground_grad(h.pos) * ITEM_SLOPE_G * 0.6 * dt                  # rolls a little downhill
		var sp := v.length()
		if sp > 0.0:
			var drop := (HAT_FRICTION * (0.3 if wet else 1.0)) * dt
			v = Vector2.ZERO if sp <= drop else v * ((sp - drop) / sp)
		h.pos = _push_out((h.pos as Vector2) + v * dt, 0.25)
		h["vel"] = v if v.length() > 0.04 or wet else Vector2.ZERO


func _blast_push(at: Vector2, radius: float, speed: float) -> void:
	# a blast throws the loose things lying round it: hats, logs and rocks (0.31.21)
	for h in hats:
		var d: Vector2 = (h.pos as Vector2) - at
		if d.length() < radius:
			var dir := d.normalized() if d.length() > 0.05 else dir_of(rng.randf() * TAU)
			h["vel"] = (h.get("vel", Vector2.ZERO) as Vector2) + dir * speed * (1.0 - 0.5 * d.length() / radius)
	for it in items:
		var d2: Vector2 = (it.pos as Vector2) - at
		if d2.length() < radius:
			var dir2 := d2.normalized() if d2.length() > 0.05 else dir_of(rng.randf() * TAU)
			var close := 1.0 - 0.5 * d2.length() / radius
			it.vel = (it.vel as Vector2) + dir2 * speed * 0.9 * close
			it["asleep"] = false
			var vz := BLAST_VZ * (0.6 + 0.5 * close)       # 0.31.35: into the air too, flying out
			it["air_vz"] = vz
			it["air_end"] = time + 2.0 * vz / ITEM_G
			if it.kind == "log":
				it.spin = float(it.spin) + rng.randf_range(-3.0, 3.0)


# ---------- hats by hand, and putting on the upgrade (0.31.22) ----------
func hat_to_pick(u: Dictionary) -> Dictionary:
	if u.cls != "villager" or u.carrying or not alive(u):
		return {}
	for h in hats:
		if u.pos.distance_to(h.pos) <= HAT_PICK_R + 0.3 and can_take_class(u, str(h.cls)):
			return h
	return {}

func _pick_dropped_hat(u: Dictionary, h: Dictionary) -> bool:
	hats.erase(h)
	_set_class(u, h.cls, h.up)
	_event("hat_pick", {"id":u.id, "cls":h.cls, "team":u.team, "hat":h.id})
	return true

func can_equip_upgrade(u: Dictionary) -> bool:
	# Kevin: "the player can equip the upgraded hat at the shop when it gets upgraded": at your own team's stand for
	# your class, once the team owns that hat upgrade, an ordinary hat can be traded for the upgraded one.
	if not alive(u) or u.cls == "villager" or u.up or u.carrying:
		return false
	var st := stand_near(u)
	if st.is_empty() or int(st.team) != u.team or str(st.cls) != u.cls:
		return false
	return int(levels[u.team].get("hat_" + str(u.cls), 0)) > 0

func _equip_upgrade(u: Dictionary) -> bool:
	if u.up or u.cls == "villager":
		return false
	var hp_frac: float = u.hp / maxf(1.0, float(stat(u, "hp")))
	_set_class(u, u.cls, true)
	u.hp = maxf(u.hp, float(stat(u, "hp")) * hp_frac)
	_event("hat_equip_up", {"id":u.id, "cls":u.cls, "team":u.team})
	return true


# ---------- predicted ability starts (0.31.23, online) ----------
func predict_ability(u: Dictionary) -> bool:
	# The client shows the start of its own ability at once: the state and cooldown the server will set, and the
	# events the view draws from. Nothing that hurts or heals anyone happens here (the client never steps the sim).
	if not can_act(u) or u.cd_ability > 0.0 or u.carrying or u.offering or int(u.get("tower", -1)) >= 0:
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


# ---------- smarter raids (0.31.25) ----------
# Raiders used to trickle at the enemy castle one at a time and die to the defenders on the wall, so a bot team almost
# never got a King out. Now the raid gathers at a rally spot outside their castle (beyond the catapults' aim), and goes
# in together once enough hands are there (or after a wait); if the push dwindles it falls back to gather again.
const RALLY_OUT := 21.0            # m outside the enemy front wall
const RALLY_HANDS := 4             # go in together with at least this many, or after RALLY_WAIT
const RALLY_WAIT := 28.0
const ASSAULT_LEN := 70.0
var _assault: Array = [{"until":-1.0, "first":-1.0}, {"until":-1.0, "first":-1.0}]

func _rally_spot(u: Dictionary) -> Vector2:
	var eg := _enemy_front_gate(u.team)
	var spot: Vector2 = ((eg.c as Vector2) + _inward(1 - u.team) * -RALLY_OUT) if not eg.is_empty() else spawn(u.team)
	return spot + dir_of(float(absi(hash(u.id)) % 628) / 100.0) * 2.6

func _enemy_front_gate(team: int) -> Dictionary:
	var best := {}
	for g in gates:
		if int(g.team) != 1 - team or str(g.get("kind", "")) == "jail":
			continue
		if best.is_empty() or (g.broken and not best.broken) or (g.broken == best.broken and g.hp < best.hp):
			best = g
	return best

func _assault_on(u: Dictionary) -> bool:
	var a: Dictionary = _assault[u.team]
	if time < float(a.until):
		return true
	var spot := _rally_spot(u) - dir_of(float(absi(hash(u.id)) % 628) / 100.0) * 2.6
	var ready := 0
	for o in units:
		if o.team == u.team and o.bot and alive(o) and o.role in ["raid", "escort"] and o.cls != "villager" \
				and o.hp >= o.max_hp * 0.5 and o.pos.distance_to(spot) < 9.0:
			ready += 1
	if ready > 0 and float(a.first) < 0.0:
		a.first = time
	if ready == 0:
		a.first = -1.0
	var home_guard := 0                              # 0.31.26: how many of theirs are at home
	for o in units:
		if o.team != u.team and alive(o) and in_castle(o.pos, 1 - u.team):
			home_guard += 1
	var waited: float = time - float(a.first) if float(a.first) >= 0.0 else 0.0
	var quiet: bool = home_guard <= 6 or waited > RALLY_WAIT * 1.5
	if (ready >= RALLY_HANDS and quiet) or (float(a.first) >= 0.0 and waited > RALLY_WAIT and ready >= 2 and quiet) or waited > RALLY_WAIT * 2.5:
		a.until = time + ASSAULT_LEN
		a.first = -1.0
		return true
	return false

func _think_bomb(u: Dictionary) -> bool:
	# The workshop's bomb: a raider takes it on the way out and throws it at the enemy gate (or, once that's down,
	# at the jail door). Only one bot goes for it.
	if u.carrying or u.offering or u.role not in ["raid", "escort"] or int(u.get("tower", -1)) >= 0:
		return false
	if bool(u.get("bomb_held", false)):
		var eg := _enemy_front_gate(u.team)
		var target := Vector2.INF
		if not eg.is_empty() and not eg.broken:
			target = eg.c
		else:
			for g in gates:
				if int(g.team) == 1 - u.team and str(g.get("kind", "")) == "jail" and not g.broken:
					target = g.c
		if target == Vector2.INF:
			return false                               # nothing worth it: carry on as a fighter (it goes off on a foe)
		var d: float = (u.pos as Vector2).distance_to(target)
		if d <= BOMB_THROW * 0.9 and not _blocked_line(u.pos, u.pos + (target - u.pos).normalized() * 1.5, u.team):
			u.face = angle_of(target - u.pos)
			u.move = Vector2.ZERO
			_throw_bomb(u)
			return true
		_nav_to(u, target, BOMB_THROW * 0.8)
		return true
	var b: Dictionary = bombs[u.team]
	if b.is_empty() or b.state != "ready":
		return false
	var claim := str(b.get("bot_claim", ""))
	if claim != "" and claim != u.id and by_id.has(claim) and alive(by_id[claim]):
		return false
	if u.pos.distance_to(b.p) > 26.0:
		return false
	b["bot_claim"] = u.id
	if not bomb_to_pick(u).is_empty():
		_pick_bomb(u, b)
		return true
	_nav_to(u, b.p, 0.6)
	return true


# ---------- answering fire (0.31.27, Kevin: bots waiting at their rally point didn't react to being shot) ----------
# A bot that was hit in the last ANSWER_FOR s -- or sees a friend within ANSWER_FRIEND m hit -- takes the attacker as its
# target if he's within ANSWER_R: melee bots go for the archer, ranged ones shoot back. Before, a bot only looked for
# enemies within its role's aggro (3.5 m for a raider), so an archer at 10 m could pick off a waiting raid untouched.
const ANSWER_FOR := 3.0
const ANSWER_R := 22.0
const ANSWER_FRIEND := 9.0

func _attacker_to_answer(u: Dictionary) -> Dictionary:
	# (0.31.28: measured -- answering everything made raids chase archers on the walls and stop rescuing (3-2/3-1 became
	# 0-0). A raider on the push only answers within 6 m; swords never chase someone on a rampart.)
	var best := {}
	var bd := ANSWER_R
	if u.role == "raid" and time < float(_assault[u.team].until):
		bd = 6.0
	for o in units:
		if o.team != u.team or not alive(o) or time - float(o.get("hurt_at", -99.0)) > ANSWER_FOR:
			continue
		if o.id != u.id and u.pos.distance_to(o.pos) > ANSWER_FRIEND:
			continue
		var a: Dictionary = by_id.get(str(o.get("hurt_by", "")), {})
		if a.is_empty() or not alive(a) or a.team == u.team:
			continue
		if (int(a.get("tower", -1)) >= 0 or on_rampart(a.pos)) and not bool(CLASSES[u.cls].ranged):
			continue                                  # up a tower or on a wall: a sword can't answer it
		var d: float = u.pos.distance_to(a.pos)
		if d < bd:
			bd = d
			best = a
	return best


# ---------- the player launcher (0.31.28, Kevin) ----------
# Built at the workshop ("launcher", 60 wood + 45 stone): a launch pad in the castle courtyard with a lever beside it.
# ACTION at the lever starts a LAUNCH_COUNT s countdown; then everyone standing on the pad (any side -- an enemy on it
# goes too) is thrown in a high arc into the enemy castle, flying in real time (LAUNCH_SPEED, 2.6-4 s), untouchable in
# the air, landing spread round the middle of their courtyard with a short stagger. The lever needs LAUNCH_RELOAD s
# before it can be pulled again. Carriers of a King, fish, a bomb, tower archers and workers on a task stay behind.
const LAUNCH_PAD := Vector2(-5.0, 10.0)        # castle-local, a clear patch of the courtyard
const LAUNCH_LEVER := Vector2(-1.4, 10.0)
const LAUNCH_PAD_R := 2.5
const LAUNCH_LEVER_R := 1.5
const LAUNCH_COUNT := 5.0
const LAUNCH_RELOAD := 20.0
const LAUNCH_LAND := Vector2(0.0, 10.0)        # castle-local, in the ENEMY castle
const LAUNCH_SPEED := 32.0
const LAUNCH_STAGGER := 0.45
var launchers: Array = [{"count_at":-1.0, "ready_at":0.0}, {"count_at":-1.0, "ready_at":0.0}]

func launch_pad(team: int) -> Vector2:
	return _c(team, LAUNCH_PAD)

func launch_lever(team: int) -> Vector2:
	return _c(team, LAUNCH_LEVER)

func launcher_built(team: int) -> bool:
	return int(levels[team].get("launcher", 0)) > 0

func can_pull_lever(u: Dictionary) -> bool:
	if not alive(u) or u.carrying or u.state == "fly" or not launcher_built(u.team):
		return false
	var l: Dictionary = launchers[u.team]
	return float(l.count_at) < 0.0 and time >= float(l.ready_at) and u.pos.distance_to(launch_lever(u.team)) <= LAUNCH_LEVER_R

func pull_lever(u: Dictionary) -> bool:
	if not can_pull_lever(u):
		return false
	launchers[u.team].count_at = time
	_event("launch_count", {"team":u.team, "id":u.id, "pos":launch_pad(u.team), "secs":LAUNCH_COUNT})
	return true

func on_pad(u: Dictionary, team: int) -> bool:
	return alive(u) and u.state != "fly" and int(u.get("tower", -1)) < 0 and u.pos.distance_to(launch_pad(team)) <= LAUNCH_PAD_R

func _step_launchers() -> void:
	for t in 2:
		var l: Dictionary = launchers[t]
		if float(l.count_at) < 0.0 or time < float(l.count_at) + LAUNCH_COUNT:
			continue
		l.count_at = -1.0
		l.ready_at = time + LAUNCH_RELOAD
		var flown := []
		var land := _c(1 - t, LAUNCH_LAND)
		var k := 0
		for u in units:
			if not on_pad(u, t) or u.carrying or u.offering or bool(u.get("bomb_held", false)) or not u.task.is_empty():
				continue
			var spot := _push_out(land + dir_of(float(k) * 2.4) * (1.2 + 0.7 * float(k % 3)), UNIT_R, 1 - t)
			var dist: float = u.pos.distance_to(spot)
			u.state = "fly"
			u["fly"] = {"from":u.pos, "to":spot, "t0":time, "dur":clampf(dist / LAUNCH_SPEED, 2.6, 4.0)}
			u.move = Vector2.ZERO
			u.path = PackedVector2Array()
			u.workshop_open = false
			u.face = angle_of(spot - u.pos)
			flown.append({"id":u.id, "from":u.pos, "to":spot, "dur":float(u.fly.dur)})
			k += 1
		_event("launch", {"team":t, "pos":launch_pad(t), "flown":flown, "t0":time})

func _step_flight(u: Dictionary) -> void:
	var f: Dictionary = u.get("fly", {})
	if f.is_empty():
		u.state = "idle"
		return
	var k := clampf((time - float(f.t0)) / float(f.dur), 0.0, 1.0)
	u.pos = (f.from as Vector2).lerp(f.to, k)
	if k >= 1.0:
		u.state = "idle"
		u.stun = LAUNCH_STAGGER
		u.erase("fly")
		u.pos = _push_out(u.pos, UNIT_R, u.team)
		_event("land", {"id":u.id, "pos":u.pos})

func flight_height(u: Dictionary) -> float:
	# the arc's height above the straight line (for the view): high and quick, peaking mid-flight
	var f: Dictionary = u.get("fly", {})
	if f.is_empty():
		return 0.0
	var k := clampf((time - float(f.t0)) / float(f.dur), 0.0, 1.0)
	return 4.0 * (8.0 + 3.0 * float(f.dur)) * k * (1.0 - k)

func _think_launcher(u: Dictionary) -> bool:
	# Raiders use it when it's built: gather on the pad; the first there pulls the lever once 3 are on it (or after 8 s).
	if u.role not in ["raid", "escort"] or u.cls in ["villager", "worker"] or u.carrying or u.offering \
			or not launcher_built(u.team) or in_castle(u.pos, 1 - u.team) or u.hp < u.max_hp * 0.5:
		return false
	var l: Dictionary = launchers[u.team]
	if float(l.count_at) < 0.0 and time < float(l.ready_at) - 4.0:
		return false
	if u.pos.distance_to(launch_pad(u.team)) > 40.0:
		return false
	if float(l.count_at) >= 0.0:
		if on_pad(u, u.team):
			u.move = Vector2.ZERO
		else:
			_nav_to(u, launch_pad(u.team) + dir_of(float(absi(hash(u.id)) % 628) / 100.0) * 1.2, 0.3)
		return true
	var aboard := 0
	for o in units:
		if o.team == u.team and o.bot and on_pad(o, u.team):
			aboard += 1
	if on_pad(u, u.team):
		u["pad_since"] = float(u.get("pad_since", time))
		if aboard >= 3 or time - float(u.pad_since) > 8.0:
			if u.pos.distance_to(launch_lever(u.team)) > LAUNCH_LEVER_R - 0.2:
				_nav_to(u, launch_lever(u.team), 0.3)
			else:
				pull_lever(u)
		else:
			u.move = Vector2.ZERO
		return true
	u.erase("pad_since")
	_nav_to(u, launch_pad(u.team) + dir_of(float(absi(hash(u.id)) % 628) / 100.0) * 1.2, 0.3)
	return true


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
	if not can_act(u) or u.cd_ability > 0.0 or u.carrying or u.offering or bool(u.get("bomb_held", false)):
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
		"high":height_at(u.pos) >= 1.5 or int(u.get("tower", -1)) >= 0})
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
				if o.team == int(m.team) or not alive(o) or o.state == "fly":
					continue
				var d: float = (o.pos as Vector2).distance_to(m.at)
				if d <= METEOR_R:
					_next_push = _push_from(m.at, o.pos, 4.6, 3.8)
					_damage(owner if not owner.is_empty() else {"team":int(m.team), "id":""}, o, float(m.dmg) * (1.0 - 0.5 * d / METEOR_R), 0.4)
			_blast_push(m.at, METEOR_R + 1.5, 5.0)
			_blast_nodes(m.at, METEOR_R, 7.5)
			m.burn_until = time + METEOR_BURN
			_event("meteor_hit", {"team":int(m.team), "pos":m.at, "burn":METEOR_BURN})
			continue
		if time >= float(m.burn_until):
			meteors.remove_at(i)
			continue
		for o in units:
			if o.team != int(m.team) and alive(o) and o.state != "fly" and (o.pos as Vector2).distance_to(m.at) <= METEOR_R * 0.8:
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
				if crowd >= 2 or foe.carrying or (d > 5.0 and rng.randf() < 0.2):
					u.face = angle_of(foe.pos - u.pos)
					return _start_attack(u, "ability")
	return false
