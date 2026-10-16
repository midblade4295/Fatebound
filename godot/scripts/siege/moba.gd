extends RefCounted
# 0.31.155 5V5 (the test). Kevin: "What about putting in moba mechanics" -> "5v5" -> "Minions should spawn in a group of
# 1 healer, 2 ranged and 1 knight" -> "Remove the hat system. Minions will stack up if opportunity happens. If minions
# still alive then the new mions that spawn will eventually join them just like in league of legends. Make sure to have
# same tower mechanics as league of legends".
# The rules on top of siege_sim.gd (its hooks call in here; nothing changes unless setup_moba() made one of these):
# - Heroes: five a side (you and four bots; five bots), each keeping its class all match -- no hats, no stands, no
#   villagers. Levels 1-10 from XP (minions dying near you, hero kills, towers); every level a little more health and
#   damage, and a choice of 1 of 3 upgrades. A hero who falls comes back as himself at his castle, later the higher his
#   level; standing in your own castle heals you.
# - Lanes: the three crossings -- the west bridge, the island, the east bridge -- each a track of points from one
#   castle's gate to the other's (the dirt paths). Every 30 s each castle sends a group down each lane: 1 Priest, 2
#   Archers, 1 Knight (WAVE). Minions march, fight what's in front of them and push on; a wave that's still alive when
#   the next comes is simply caught up with -- waves stack.
# - Towers (League's rules): two per lane per side (outer, inner) beside the track. A tower shoots the nearest enemy
#   minion in range; an enemy hero who hurts one of its heroes in range becomes its target at once (call for help);
#   otherwise heroes only when no minion is in range. Shots home in (no dodging); on a hero each shot in a row hits
#   harder (+40 %, up to 3 times), on a minion a share of its health (a Knight 45 %, the others 70 %). A lane's inner
#   tower can't be damaged while its outer one stands; a castle gate can't be damaged while an inner tower of a lane
#   that leads to it stands. Without your minions near it a tower takes a third of the damage (backdoor protection).
#   Only basic attacks (and arrows / fire) hurt towers.
# - The heart is the King (0.31.156, Kevin: "Have the enemy king be the "heart" and players will have to defeat him"):
#   each King sits on his own throne, KING_HP of health, untouchable until one of his castle's front gates is down;
#   then he can be hit (basic attacks, arrows, fire) and he fights back -- a slam round him every KING_EVERY s. Left
#   alone a while he heals. Defeat theirs and the match is won; at 12 minutes, the side that did more to the other's
#   King wins, then more towers down, then hero knockouts. No rescues, no lifting. When an enemy gate is down two of
#   each side's bots go for that King; bots near their own King under attack defend him.

const HEROES := {
	"knight": {"name":"Knight", "cls":"knight", "up":false}, "barbarian": {"name":"Barbarian", "cls":"barbarian", "up":false},
	"rogue": {"name":"Rogue", "cls":"rogue", "up":false}, "ranger": {"name":"Archer", "cls":"ranger", "up":false},
	"mage": {"name":"Mage", "cls":"mage", "up":false}, "priest": {"name":"Priest", "cls":"priest", "up":false},
	"crusader": {"name":"Crusader", "cls":"knight", "up":true}, "berserker": {"name":"Berserker", "cls":"barbarian", "up":true},
	"assassin": {"name":"Assassin", "cls":"rogue", "up":true}, "sniper": {"name":"Ranger", "cls":"ranger", "up":true},
	"archmage": {"name":"Archmage", "cls":"mage", "up":true}, "necromancer": {"name":"Necromancer", "cls":"priest", "up":true},
}
const HERO_ORDER := ["knight", "barbarian", "rogue", "ranger", "mage", "priest", "crusader", "berserker", "assassin", "sniper",
	"archmage", "necromancer"]
const HERO_LINE := {"knight":"Shield up: blocks everything from the front.", "barbarian":"Spins through a crowd.",
	"rogue":"Lunges in, quick and sharp.", "ranger":"Arrows from range, a volley of five.", "mage":"Fireballs, and a nova all round.",
	"priest":"Heals with a beam; Sanctuary heals everyone near.", "crusader":"Throws his hammer through a line, and blocks.",
	"berserker":"A whirlwind that keeps moving.", "assassin":"Vanishes, then strikes twice as hard.",
	"sniper":"A piercing shot through everyone in a line.", "archmage":"Calls down a meteor.",
	"necromancer":"Drains enemies to heal friends; raises the fallen."}

# the lanes as world points from the blue (team 0) gate to the red (team 1) gate; red walks them backwards. Point
# symmetric: lane 0 backwards and mirrored is lane 2 (the castles are point mirrors).
const LANES := [
	[Vector2(-7, 41), Vector2(-9.5, 39), Vector2(-13.5, 34.5), Vector2(-15.5, 29), Vector2(-15.8, 22), Vector2(-18, 14.5),
		Vector2(-22, 9.5), Vector2(-24, 6.6), Vector2(-24, -4.7), Vector2(-21, -8.5), Vector2(-20, -13.5), Vector2(-19.5, -21),
		Vector2(-19, -28.5), Vector2(-13, -35), Vector2(-5, -38.5), Vector2(-7, -41)],
	[Vector2(7, 41), Vector2(5, 38.5), Vector2(2, 31), Vector2(0.5, 22), Vector2(0, 13.6), Vector2(0, -13.6), Vector2(-0.5, -22),
		Vector2(-2, -31), Vector2(-5, -38.5), Vector2(-7, -41)],
	[Vector2(7, 41), Vector2(5, 38.5), Vector2(13, 35), Vector2(19, 28.5), Vector2(19.5, 21), Vector2(20, 13.5), Vector2(21, 8.5),
		Vector2(24, 4.7), Vector2(24, -6.6), Vector2(22, -9.5), Vector2(18, -14.5), Vector2(15.8, -22), Vector2(15.5, -29),
		Vector2(13.5, -34.5), Vector2(9.5, -39), Vector2(7, -41)],
]
const LANE_NAMES := ["west", "middle", "east"]
# blue's towers [lane, tier (1 outer, 2 inner), position] -- beside the track, on its inner side; red's are the mirror
const TOWERS_BLUE := [[0, 1, Vector2(-15.0, 14.5)], [0, 2, Vector2(-12.5, 28.5)], [1, 1, Vector2(3.3, 19.0)],
	[1, 2, Vector2(5.2, 30.0)], [2, 1, Vector2(17.0, 13.5)], [2, 2, Vector2(16.2, 26.0)]]

const WAVE := ["knight", "ranger", "ranger", "priest"]      # Kevin: 1 healer, 2 ranged, 1 knight (front to back)
const WAVE_FIRST := 15.0
const WAVE_EVERY := 30.0
const MINION_CAP := 40                                      # per side alive (a phone-safety ceiling; waves stack below it)
const MINION_HP := 0.5
const MINION_DMG := 0.45
const MINION_SPD := 0.88
const MINION_GONE := 3.0                                    # a fallen minion's body, then it's gone
const HERO_HP := 1.8                                        # heroes outlast minions
const LEVEL_MAX := 10
const LEVEL_GROW := 0.06                                    # +6 % health and damage a level
const XP_BASE := 60.0
const XP_STEP := 30.0
const MINION_XP := 15.0
const XP_R := 12.0
const HERO_XP := 40.0
const HERO_XP_LVL := 12.0
const TOWER_XP := 50.0
const RESPAWN_BASE := 4.0
const RESPAWN_LVL := 1.6
const FOUNTAIN := 0.06                                      # of max health a second, in your own castle
const TOWER_R := 1.5
const TOWER_RANGE := 11.5
const TOWER_HP := [0.0, 1000.0, 1300.0]
const TOWER_EVERY := 0.9
const TOWER_FLIGHT := 0.3
const TOWER_HERO_DMG := 40.0
const TOWER_RAMP := 0.4
const TOWER_RAMP_MAX := 3
const TOWER_GROW := 0.04                                    # +4 % a minute
const TOWER_PCT := {"knight":0.45}                          # a share of a minion's health a shot (others 0.7)
const TOWER_PCT_ELSE := 0.7
const BACKDOOR := 0.34
const HELP_FOR := 2.0
const UPGRADES := {
	"dmg":{"name":"+15% DAMAGE"}, "hp":{"name":"+15% HEALTH"}, "spd":{"name":"+8% SPEED"}, "as":{"name":"+12% ATTACK SPEED"},
	"cdr":{"name":"ABILITY +25% FASTER"}, "ls":{"name":"8% LIFESTEAL"}, "regen":{"name":"REGEN 1%/s"},
}
const UP_MAX := 3
const KING_HP := 3500.0
const KING_R := 1.0
const KING_REACH := 4.5
const KING_SLAM := 50.0
const KING_EVERY := 1.6
const KING_REGEN := 0.015                                   # of his health a second, once left alone KING_QUIET s
const KING_QUIET := 6.0
const KING_GUARD := 14.0                                    # enemies this near: he's under attack (bots come to help)

var s                                     # the sim
var rng := RandomNumberGenerator.new()
var towers: Array = []                    # {id, team, lane, tier, p, hp, max_hp, dead, target, ramp, ramp_id, next}
var shots: Array = []                     # {tw, target, t, dmg}
var wave_at := WAVE_FIRST
var waves := 0
var _mid := 0
var heroes: Array = [[], []]              # unit ids
var hero_of := {}                         # unit id -> hero id
var _immune_note := -10.0
var kings: Array = [{}, {}]               # per side: {hp, max_hp, dead, next, quiet}

# ---------- setup ----------
func begin(sim, my_hero: String, seed_value: int) -> void:
	s = sim
	rng.seed = seed_value
	for st in s.stands:
		st.stock = 0                      # (the shops stay as buildings; nothing to take)
	s.hats = []
	s.bomb_next = [INF, INF]
	for b in TOWERS_BLUE:
		_add_tower(0, int(b[0]), int(b[1]), b[2])
	for b in TOWERS_BLUE:
		_add_tower(1, 2 - int(b[0]), int(b[1]), -(b[2] as Vector2))
	for t in 2:                           # the Kings, home on their thrones: the hearts
		var o: Dictionary = s.oracles[t]
		o.state = "home"
		o.pos = s.throne(t)
		o.lifters = []
		o.carrier = ""
		kings[t] = {"hp":KING_HP, "max_hp":KING_HP, "dead":false, "next":0.0, "quiet":0.0}
		s.obstacles.append({"p":o.pos, "r":KING_R, "kind":"moba_king", "kg":t, "team":t})
	s._build_buckets()
	s._build_nav()                        # (the towers block the way and stop arrows)
	for t in 2:                           # the island lane at its plain cost: minions walk mid
		var grid: AStarGrid2D = s.nav[t]
		for ix in range(grid.region.position.x, grid.region.end.x):
			for iz in range(grid.region.position.y, grid.region.end.y):
				var cc := Vector2i(ix, iz)
				if s._lane_cell(s.nav_point(cc)) and s.water_depth(s.nav_point(cc)) <= 0.15:
					grid.set_point_weight_scale(cc, 1.0)
	# the heroes: yours, then the bots' (no two the same on a side)
	var pool: Array = HERO_ORDER.duplicate()
	var lanes := [[-1, 0, 1, 2, 2], [0, 1, 2, 2, 1]]
	for t in 2:
		var taken := []
		if t == 0:
			taken.append(my_hero if HEROES.has(my_hero) else "knight")
		var i := 0
		for u in s.units:
			if int(u.team) != t:
				continue
			var hid := ""
			if t == 0 and i == 0:
				hid = str(taken[0])
			else:
				var left := pool.filter(func(h): return not taken.has(h))
				hid = str(left[rng.randi_range(0, left.size() - 1)])
				taken.append(hid)
			_make_hero(u, hid, int(lanes[t][mini(i, 4)]), (i in [1, 2]) if t == 0 else (i in [0, 1]))
			i += 1

func _add_tower(team: int, lane: int, tier: int, p: Vector2) -> void:
	var id := towers.size()
	towers.append({"id":id, "team":team, "lane":lane, "tier":tier, "p":p, "hp":TOWER_HP[tier], "max_hp":TOWER_HP[tier],
		"dead":false, "target":"", "ramp":0, "ramp_id":"", "next":0.0})
	s.obstacles.append({"p":p, "r":TOWER_R, "kind":"moba_tower", "tw":id, "team":team})

func _make_hero(u: Dictionary, hid: String, lane: int, king_runner: bool) -> void:
	var h: Dictionary = HEROES[hid]
	u.cls = str(h.cls)
	u.up = bool(h.up)
	u["hero"] = true
	u["hid"] = hid
	u["lane"] = lane
	u["kr"] = king_runner and u.bot
	u["level"] = 1
	u["xp"] = 0.0
	u["picks"] = []
	u["ups"] = {}
	u.role = "escort"
	heroes[int(u.team)].append(u.id)
	hero_of[u.id] = hid
	_apply(u)
	s._respawn(u, true)

# ---------- stats ----------
func stat(u: Dictionary, key: String, base: Variant) -> Variant:
	match key:
		"hp":
			return float(base) * (1.15 if u.up else 1.0) * float(u.get("m_hp", 1.0))
		"dmg":
			return float(base) * (1.1 if u.up else 1.0) * float(u.get("m_dmg", 1.0))
		"speed":
			return float(base) * float(u.get("m_spd", 1.0))
		"windup", "recover":
			return float(base) * float(u.get("m_as", 1.0))
	return base

func _apply(u: Dictionary) -> void:
	# the multipliers stat() reads, from the level and the upgrades picked
	var ups: Dictionary = u.get("ups", {})
	var lv := float(int(u.get("level", 1)) - 1)
	var before: float = float(u.get("max_hp", 0.0))
	u["m_hp"] = HERO_HP * (1.0 + LEVEL_GROW * lv) * (1.0 + 0.15 * float(ups.get("hp", 0)))
	u["m_dmg"] = (1.0 + LEVEL_GROW * lv) * (1.0 + 0.15 * float(ups.get("dmg", 0)))
	u["m_spd"] = 1.0 + 0.08 * float(ups.get("spd", 0))
	u["m_as"] = pow(0.88, float(ups.get("as", 0)))
	u["m_cdr"] = 1.0 + 0.25 * float(ups.get("cdr", 0))
	u["m_ls"] = 0.08 * float(ups.get("ls", 0))
	u["m_regen"] = 0.01 * float(ups.get("regen", 0))
	var after := float(s.stat(u, "hp"))
	u.max_hp = after
	if before > 0.0 and s.alive(u):
		u.hp = minf(after, float(u.hp) + maxf(0.0, after - before))      # the health a level brings comes with it

func need(level: int) -> float:
	return XP_BASE + XP_STEP * float(level - 1)

func add_xp(u: Dictionary, x: float) -> void:
	if not bool(u.get("hero", false)) or int(u.level) >= LEVEL_MAX:
		return
	u.xp = float(u.xp) + x
	while int(u.level) < LEVEL_MAX and float(u.xp) >= need(int(u.level)):
		u.xp = float(u.xp) - need(int(u.level))
		u.level = int(u.level) + 1
		(u.picks as Array).append(_offer(u))
		_apply(u)
		s._event("level", {"id":u.id, "team":u.team, "level":int(u.level)})
		if u.bot:
			pick(u, rng.randi_range(0, 2))
	if int(u.level) >= LEVEL_MAX:
		u.xp = 0.0

func _offer(u: Dictionary) -> Array:
	var pool := []
	for k in UPGRADES:
		if int((u.ups as Dictionary).get(k, 0)) >= UP_MAX:
			continue
		if u.cls == "priest" and k in ["dmg", "ls"]:
			continue                                  # (a healer's beam does no damage)
		pool.append(k)
	var out := []
	while out.size() < 3 and not pool.is_empty():
		out.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return out

func pick(u: Dictionary, i: int) -> bool:
	var picks: Array = u.get("picks", [])
	if picks.is_empty():
		return false
	var offer: Array = picks[0]
	if i < 0 or i >= offer.size():
		return false
	var k := str(offer[i])
	u.ups[k] = int((u.ups as Dictionary).get(k, 0)) + 1
	picks.pop_front()
	_apply(u)
	s._event("pick", {"id":u.id, "up":k})
	return true

# ---------- the match ----------
func step(dt: float) -> void:
	if s.time >= wave_at:
		wave_at += WAVE_EVERY
		waves += 1
		for t in 2:
			for l in 3:
				_spawn_wave(t, l)
	_step_towers(dt)
	_step_kings(dt)
	var gone := []
	for u in s.units:
		if not s.alive(u):
			if bool(u.get("minion", false)) and s.time >= float(u.get("gone_at", INF)):
				gone.append(u)
			continue
		if bool(u.get("hero", false)):
			var heal := float(u.get("m_regen", 0.0))
			if s.in_castle(u.pos, int(u.team)):
				heal += FOUNTAIN
			if heal > 0.0 and u.hp < u.max_hp:
				u.hp = minf(u.max_hp, u.hp + u.max_hp * heal * dt)
	for u in gone:
		s.units.erase(u)
		s.by_id.erase(u.id)

func _spawn_wave(t: int, l: int) -> void:
	var alive := 0
	for u in s.units:
		if bool(u.get("minion", false)) and int(u.team) == t and s.alive(u):
			alive += 1
	var start := wp(t, l, 0)
	var ahead := (wp(t, l, 1) - start).normalized()
	var side := Vector2(-ahead.y, ahead.x)
	var ids := []
	for k in WAVE.size():
		if alive >= MINION_CAP:
			break
		alive += 1
		_mid += 1
		var id := "m%d" % _mid
		var u: Dictionary = s._new_unit(id, t, true, "raid")
		u.cls = str(WAVE[k])
		u["minion"] = true
		u["lane"] = l
		u["wp"] = 1
		u["m_hp"] = MINION_HP
		u["m_dmg"] = MINION_DMG
		u["m_spd"] = MINION_SPD
		u.max_hp = float(s.stat(u, "hp"))
		u.hp = u.max_hp
		# (front to back from the gate out: the Knight ahead, the Priest at the gate -- behind it is the castle wall)
		u.pos = start + ahead * (1.4 * float(WAVE.size() - 1 - k)) + side * (0.9 if k == 1 else (-0.9 if k == 2 else 0.0))
		u.face = s.angle_of(ahead)
		u.think_at = s.time + s.TICK * float(k + 1)
		s.units.append(u)
		s.by_id[id] = u
		ids.append(id)
	if not ids.is_empty():
		s._event("wave", {"team":t, "lane":l, "ids":ids})

func wp(t: int, l: int, i: int) -> Vector2:
	# point i of lane l walked by team t (red walks it backwards)
	var pts: Array = LANES[l]
	i = clampi(i, 0, pts.size() - 1)
	return pts[i] if t == 0 else pts[pts.size() - 1 - i]

func lane_len(l: int) -> int:
	return (LANES[l] as Array).size()

# ---------- towers ----------
func vulnerable(tw: Dictionary) -> bool:
	if bool(tw.dead):
		return false
	if int(tw.tier) == 1:
		return true
	for o in towers:
		if int(o.team) == int(tw.team) and int(o.lane) == int(tw.lane) and int(o.tier) == int(tw.tier) - 1 and not bool(o.dead):
			return false
	return true

func towers_down(team: int) -> int:
	var n := 0
	for tw in towers:
		if int(tw.team) == team and bool(tw.dead):
			n += 1
	return n

func gate_open(g: Dictionary) -> bool:
	# a castle gate can be hit once an inner tower of a lane that ends at it is down (the jail: once a front gate is)
	if str(g.get("kind", "")) == "jail":
		for o in s.gates:
			if int(o.team) == int(g.team) and str(o.get("kind", "")) != "jail" and not s.gate_blocks(o):
				return true
		return false
	for l in 3:
		var end := wp(1 - int(g.team), l, lane_len(l) - 1)        # where the attackers' track ends: at this castle
		if end.distance_to(g.c) > 6.0:
			continue
		for tw in towers:
			if int(tw.team) == int(g.team) and int(tw.lane) == l and int(tw.tier) == 2 and bool(tw.dead):
				return true
	return false

func _step_towers(dt: float) -> void:
	for tw in towers:
		if bool(tw.dead):
			continue
		var cur: Dictionary = s.by_id.get(str(tw.target), {})
		if cur.is_empty() or not s.alive(cur) or (cur.pos as Vector2).distance_to(tw.p) > TOWER_RANGE + s.UNIT_R:
			cur = {}
		# call for help: an enemy hero in range who hurt one of our heroes in range just now
		var help := {}
		for h in s.units:
			if not bool(h.get("hero", false)) or int(h.team) != int(tw.team) or not s.alive(h):
				continue
			if s.time - float(h.get("hh_at", -99.0)) > HELP_FOR or (h.pos as Vector2).distance_to(tw.p) > TOWER_RANGE:
				continue
			var a: Dictionary = s.by_id.get(str(h.get("hh_by", "")), {})
			if not a.is_empty() and s.alive(a) and (a.pos as Vector2).distance_to(tw.p) <= TOWER_RANGE + s.UNIT_R:
				help = a
				break
		if not help.is_empty() and (cur.is_empty() or not bool(cur.get("hero", false))):
			cur = help
		if cur.is_empty():
			var best := {}
			var bd := INF
			for heroes_pass in [false, true]:                    # minions first; heroes only when there are none
				for o in s.units:
					if int(o.team) == int(tw.team) or not s.alive(o) or bool(o.get("hero", false)) != heroes_pass:
						continue
					var d: float = (o.pos as Vector2).distance_to(tw.p)
					if d <= TOWER_RANGE + s.UNIT_R and d < bd:
						bd = d
						best = o
				if not best.is_empty():
					break
			cur = best
		tw.target = str(cur.get("id", ""))
		if cur.is_empty() or s.time < float(tw.next):
			continue
		tw.next = s.time + TOWER_EVERY
		var dmg := 0.0
		if bool(cur.get("hero", false)):
			if str(tw.ramp_id) == str(cur.id):
				tw.ramp = mini(int(tw.ramp) + 1, TOWER_RAMP_MAX)
			else:
				tw.ramp_id = str(cur.id)
				tw.ramp = 0
			dmg = TOWER_HERO_DMG * (1.0 + TOWER_RAMP * float(tw.ramp)) * (1.0 + TOWER_GROW * s.time / 60.0)
		else:
			tw.ramp_id = ""
			tw.ramp = 0
			dmg = float(cur.max_hp) * float(TOWER_PCT.get(str(cur.cls), TOWER_PCT_ELSE))
		shots.append({"tw":int(tw.id), "target":str(cur.id), "t":TOWER_FLIGHT, "dmg":dmg})
		s._event("tshot", {"tw":int(tw.id), "id":str(cur.id), "flight":TOWER_FLIGHT, "ramp":int(tw.ramp)})
	for i in range(shots.size() - 1, -1, -1):
		var sh: Dictionary = shots[i]
		sh.t = float(sh.t) - dt
		if float(sh.t) > 0.0:
			continue
		shots.remove_at(i)
		var tw2: Dictionary = towers[int(sh.tw)]
		var u: Dictionary = s.by_id.get(str(sh.target), {})
		if not u.is_empty() and s.alive(u):
			s._next_push = Vector3.ZERO
			s._damage({"id":"tower%d" % int(tw2.id), "team":int(tw2.team), "pos":tw2.p, "state":"idle"}, u, float(sh.dmg))

func hit_tower(src: Dictionary, id: int, amount: float) -> void:
	if id < 0 or id >= towers.size():
		return
	var tw: Dictionary = towers[id]
	if bool(tw.dead) or int(src.get("team", -1)) == int(tw.team) or int(src.get("team", -1)) < 0:
		return
	if not vulnerable(tw):
		if s.time - _immune_note > 1.5 and not bool(src.get("bot", true)):
			_immune_note = s.time
			s._event("tower_immune", {"tw":id, "team":int(tw.team)})
		return
	var minions_near := false
	for o in s.units:
		if bool(o.get("minion", false)) and int(o.team) == int(src.team) and s.alive(o) and (o.pos as Vector2).distance_to(tw.p) <= TOWER_RANGE:
			minions_near = true
			break
	if not minions_near:
		amount *= BACKDOOR                      # no minions with you: the tower barely feels it
	tw.hp = maxf(0.0, float(tw.hp) - amount)
	s._event("tower_hit", {"tw":id, "dmg":int(round(amount))})
	if float(tw.hp) <= 0.0:
		tw.dead = true
		tw.target = ""
		s._event("tower_down", {"tw":id, "team":int(tw.team), "lane":int(tw.lane), "tier":int(tw.tier), "by":str(src.get("id", ""))})
		for hid in heroes[1 - int(tw.team)]:
			add_xp(s.by_id.get(hid, {}), TOWER_XP)
		s._update_gate_nav()

func melee_towers(u: Dictionary, reach: float, arc: float, dmg: float) -> int:
	var fwd: Vector2 = s.dir_of(u.face)
	var hits := 0
	for tw in towers:
		if bool(tw.dead) or int(tw.team) == int(u.team):
			continue
		var off: Vector2 = (tw.p as Vector2) - (u.pos as Vector2)
		var d := off.length()
		if d - TOWER_R > reach + 0.3:
			continue
		if arc > -1.0 and d > 0.3 and fwd.dot(off / d) < arc - 0.3:
			continue
		hit_tower(u, int(tw.id), dmg)
		hits += 1
	var t2 := 1 - int(u.team)
	var off2: Vector2 = king_pos(t2) - (u.pos as Vector2)
	var d2 := off2.length()
	if not bool(kings[t2].dead) and d2 - KING_R <= reach + 0.3 and (arc <= -1.0 or d2 < 0.3 or fwd.dot(off2 / d2) >= arc - 0.3):
		hit_king(u, t2, dmg)
		hits += 1
	return hits

func tower_in_range(team_of_tower: int, p: Vector2, extra := 0.0) -> Dictionary:
	for tw in towers:
		if int(tw.team) == team_of_tower and not bool(tw.dead) and p.distance_to(tw.p) <= TOWER_RANGE + extra:
			return tw
	return {}

# ---------- the Kings, the hearts (0.31.156) ----------
func king_pos(t: int) -> Vector2:
	return s.oracles[t].pos

func king_open(t: int) -> bool:
	# hittable once a front gate of his castle is down
	if bool(kings[t].dead):
		return false
	for g in s.gates:
		if int(g.team) == t and str(g.get("kind", "")) != "jail" and not s.gate_blocks(g):
			return true
	return false

func king_frac(t: int) -> float:
	return float(kings[t].hp) / float(kings[t].max_hp)

func tiebreak() -> int:
	# at time: who did more to the other's King, then towers, then hero knockouts (-1: level)
	if absf(king_frac(0) - king_frac(1)) > 0.001:
		return 0 if king_frac(1) < king_frac(0) else 1
	if towers_down(0) != towers_down(1):
		return 0 if towers_down(1) > towers_down(0) else 1
	if s.kills[0] != s.kills[1]:
		return 0 if s.kills[0] > s.kills[1] else 1
	return -1

func king_threat(t: int) -> Dictionary:
	# the nearest enemy within KING_GUARD of King t ({} when none)
	var best := {}
	var bd := KING_GUARD
	for o in s.units:
		if int(o.team) != t and s.alive(o):
			var d: float = (o.pos as Vector2).distance_to(king_pos(t))
			if d < bd:
				bd = d
				best = o
	return best

func hit_king(src: Dictionary, t: int, amount: float) -> void:
	var k: Dictionary = kings[t]
	if bool(k.dead) or int(src.get("team", -1)) == t or int(src.get("team", -1)) < 0 or s.ended:
		return
	if not king_open(t):
		if s.time - _immune_note > 1.5 and not bool(src.get("bot", true)):
			_immune_note = s.time
			s._event("king_immune", {"team":t})
		return
	k.hp = maxf(0.0, float(k.hp) - amount)
	k.quiet = 0.0
	s._event("king_hit", {"team":t, "dmg":int(round(amount))})
	if float(k.hp) <= 0.0:
		k.dead = true
		s.score[1 - t] += 1
		s._event("king_down", {"team":t, "by":str(src.get("id", ""))})
		s._finish("king")

func _step_kings(dt: float) -> void:
	for t in 2:
		var k: Dictionary = kings[t]
		if bool(k.dead):
			continue
		var kp := king_pos(t)
		var near := []
		var any := false
		for o in s.units:
			if int(o.team) == t or not s.alive(o):
				continue
			var d: float = (o.pos as Vector2).distance_to(kp)
			if d <= KING_GUARD:
				any = true
			if d <= KING_REACH + s.UNIT_R:
				near.append(o)
		if not near.is_empty() and s.time >= float(k.next):
			k.next = s.time + KING_EVERY
			var dmg: float = KING_SLAM * (1.0 + TOWER_GROW * float(s.time) / 60.0)
			s._event("king_slam", {"team":t})
			for o in near:
				s._next_push = s._push_from(kp, o.pos, 5.0, 2.6)
				s._damage({"id":"king%d" % t, "team":t, "pos":kp, "state":"idle"}, o, dmg)
		if any:
			k.quiet = 0.0
		else:
			k.quiet = float(k.quiet) + dt
			if float(k.quiet) >= KING_QUIET and float(k.hp) < float(k.max_hp):
				k.hp = minf(float(k.max_hp), float(k.hp) + float(k.max_hp) * KING_REGEN * dt)

# ---------- hits and knockouts ----------
func on_damage(src: Dictionary, dst: Dictionary, amount: float) -> void:
	if src.is_empty() or int(src.get("team", -1)) == int(dst.team):
		return
	var ls := float(src.get("m_ls", 0.0))
	if ls > 0.0 and amount > 0.0 and src.has("hp") and s.alive(src):
		s._heal(src, src, amount * ls)
	if bool(dst.get("hero", false)) and bool(src.get("hero", false)):
		dst["hh_by"] = str(src.id)
		dst["hh_at"] = s.time

func on_kill(src: Dictionary, dst: Dictionary) -> void:
	dst["died_at"] = s.time
	dst["died_hat"] = -1
	dst.task = {}
	dst.load = {"kind":"", "n":0}
	dst.offering = false
	dst.deaths = int(dst.deaths) + 1
	var push: Vector3 = dst.get("death_push", Vector3.ZERO)
	if bool(dst.get("minion", false)):
		dst.respawn_at = INF
		dst["gone_at"] = s.time + MINION_GONE
		var near := []
		for hid in heroes[1 - int(dst.team)]:
			var h: Dictionary = s.by_id.get(hid, {})
			if not h.is_empty() and s.alive(h) and (h.pos as Vector2).distance_to(dst.pos) <= XP_R:
				near.append(h)
		for h in near:
			add_xp(h, MINION_XP * (1.0 if near.size() == 1 else 0.65))
	elif bool(dst.get("hero", false)):
		dst.respawn_at = s.time + RESPAWN_BASE + RESPAWN_LVL * float(int(dst.level))
		if not src.is_empty() and src.has("team") and int(src.team) != int(dst.team):
			s.kills[int(src.team)] += 1
			if bool(src.get("hero", false)):
				src.kills = int(src.kills) + 1
				s._multi_kill(src, dst)
				s._stat_add(src, "kills", 1.0)
		var reward := HERO_XP + HERO_XP_LVL * float(int(dst.level))
		if bool(src.get("hero", false)):
			add_xp(src, reward)
		for hid in heroes[1 - int(dst.team)]:
			var h2: Dictionary = s.by_id.get(hid, {})
			if not h2.is_empty() and h2 != src and s.alive(h2) and (h2.pos as Vector2).distance_to(dst.pos) <= XP_R:
				add_xp(h2, reward * 0.5)
	s._event("death", {"id":dst.id, "by":src.get("id", ""), "push":[snappedf(push.x, 0.01), snappedf(push.y, 0.01), snappedf(push.z, 0.01)],
		"minion":bool(dst.get("minion", false))})

# ---------- ACTION: only the King ----------
func context(u: Dictionary) -> String:
	if true:
		return ""                                # (0.31.156: the Kings are the hearts -- nothing to lift)
	if u.carrying:
		var ho: Dictionary = s.lifting_oracle(u)
		return "throw" if (not ho.is_empty() and ho.lifters.size() == 1 and s.lifters_needed(ho) == 1) else "letgo"
	var lo: Dictionary = s._liftable(u)
	if not lo.is_empty():
		return "join" if lo.state == "carried" else "grab"
	return ""

func interact(u: Dictionary) -> bool:
	if true:
		return false
	if u.carrying:
		var ho: Dictionary = s.lifting_oracle(u)
		s._leave_lift(u, not ho.is_empty() and ho.lifters.size() == 1 and s.lifters_needed(ho) == 1)
		return true
	var lo: Dictionary = s._liftable(u)
	if not lo.is_empty():
		s._join_lift(u, lo)
		return true
	return false

# ---------- the bots ----------
func think(u: Dictionary) -> void:
	if not s.alive(u) or u.stun > 0.0 or u.state in ["wind", "recover", "dodge"]:
		return
	s._unstick_check(u)
	if bool(u.get("minion", false)):
		_think_minion(u)
	else:
		_think_hero(u)

func _forward(u: Dictionary) -> Vector2:
	return Vector2(0, -1) if int(u.team) == 0 else Vector2(0, 1)

func _think_minion(u: Dictionary) -> void:
	var c: Dictionary = s.CLASSES[u.cls]
	var aggro := 9.0 if bool(c.ranged) else 5.5
	if u.cls == "priest":
		if s._think_priest(u):
			return
		# follow the wave: a step behind the nearest friend of the lane who isn't a priest
		var lead := {}
		var ld := 14.0
		for o in s.units:
			if o != u and int(o.team) == int(u.team) and s.alive(o) and bool(o.get("minion", false)) and int(o.lane) == int(u.lane) \
					and o.cls != "priest" and (o.pos as Vector2).distance_to(u.pos) < ld:
				ld = (o.pos as Vector2).distance_to(u.pos)
				lead = o
		if not lead.is_empty():
			s._nav_to(u, (lead.pos as Vector2) - _forward(u) * 2.0, 1.2)
			return
		_march(u)
		return
	var foe := _minion_unit_target(u, aggro, false)
	if not foe.is_empty():
		u["mt"] = str(foe.id)
		s._fight(u, foe)
		return
	var tw := _enemy_tower_near(u, aggro + TOWER_R)
	if not tw.is_empty():
		_hit_structure(u, tw)
		return
	var eteam := 1 - int(u.team)
	if king_open(eteam) and (u.pos as Vector2).distance_to(king_pos(eteam)) < aggro + KING_R + 2.0:
		_hit_point(u, king_pos(eteam), KING_R)
		return
	foe = _minion_unit_target(u, aggro, true)
	if not foe.is_empty():
		u["mt"] = str(foe.id)
		s._fight(u, foe)
		return
	_march(u)

func _minion_unit_target(u: Dictionary, aggro: float, heroes_too: bool) -> Dictionary:
	# a minion's target: an enemy hero who just hurt one of our heroes near me (call for help), the one I'm on, the
	# nearest enemy minion -- heroes only on the second pass (after towers)
	for h in s.units:
		if int(h.team) != int(u.team) or not bool(h.get("hero", false)) or not s.alive(h):
			continue
		if s.time - float(h.get("hh_at", -99.0)) <= HELP_FOR and (h.pos as Vector2).distance_to(u.pos) < 9.0:
			var a: Dictionary = s.by_id.get(str(h.get("hh_by", "")), {})
			if not a.is_empty() and s.alive(a) and (a.pos as Vector2).distance_to(u.pos) < aggro + 3.0:
				return a
	var cur: Dictionary = s.by_id.get(str(u.get("mt", "")), {})
	if not cur.is_empty() and s.alive(cur) and (cur.pos as Vector2).distance_to(u.pos) < aggro + 2.5 \
			and (heroes_too or not bool(cur.get("hero", false))):
		return cur
	var best := {}
	var bd := aggro
	for o in s.units:
		if int(o.team) == int(u.team) or not s.alive(o) or o.state == "fly":
			continue
		if bool(o.get("hero", false)) and not heroes_too:
			continue
		var d: float = (o.pos as Vector2).distance_to(u.pos)
		if d < bd:
			bd = d
			best = o
	return best

func _enemy_tower_near(u: Dictionary, r: float) -> Dictionary:
	var best := {}
	var bd := r
	for tw in towers:
		if int(tw.team) == int(u.team) or bool(tw.dead):
			continue
		var d: float = (u.pos as Vector2).distance_to(tw.p)
		if d < bd:
			bd = d
			best = tw
	return best

func _hit_structure(u: Dictionary, tw: Dictionary) -> void:
	# up to it and swing / shoot (an invulnerable one too: it's in the way -- the hit does nothing)
	_hit_point(u, tw.p, TOWER_R)

func _hit_point(u: Dictionary, p: Vector2, r: float) -> void:
	var c: Dictionary = s.CLASSES[u.cls]
	var d: float = (u.pos as Vector2).distance_to(p) - r
	var reach: float = float(c.range) * (0.85 if bool(c.ranged) else 1.0)
	if d > reach:
		s._nav_to(u, p, r + reach * 0.8)
		return
	u.move = Vector2.ZERO
	u.face = s.angle_of(p - (u.pos as Vector2))
	s._start_attack(u, "attack", false)

func _march(u: Dictionary) -> void:
	var l := int(u.lane)
	var i := int(u.get("wp", 1))
	var goal := wp(int(u.team), l, i)
	if (u.pos as Vector2).distance_to(goal) < 2.5 and i < lane_len(l) - 1:
		u.wp = i + 1
		goal = wp(int(u.team), l, i + 1)
	if i >= lane_len(l) - 1:
		# the lane's end: the enemy gate -- in through it once it's down (to whatever's inside)
		var g := _gate_at(1 - int(u.team), goal)
		if not g.is_empty() and s.gate_blocks(g):
			_hit_gate(u, g)
			return
		goal = s.throne(1 - int(u.team))
	s._nav_to(u, goal, 0.8)

func _gate_at(team: int, p: Vector2) -> Dictionary:
	for g in s.gates:
		if int(g.team) == team and str(g.get("kind", "")) != "jail" and (g.c as Vector2).distance_to(p) < 6.0:
			return g
	return {}

func _hit_gate(u: Dictionary, g: Dictionary) -> void:
	var c: Dictionary = s.CLASSES[u.cls]
	var cp: Vector2 = s.seg_closest(u.pos, g.a, g.b)
	var d: float = (u.pos as Vector2).distance_to(cp)
	var reach: float = float(c.range) * (0.8 if bool(c.ranged) else 1.0)
	if d > reach + s.WALL_R:
		s._nav_to(u, cp + (g["in"] as Vector2) * -1.2, 0.6)
		return
	u.move = Vector2.ZERO
	u.face = s.angle_of(cp - (u.pos as Vector2))
	s._start_attack(u, "attack", false)

func _think_hero(u: Dictionary) -> void:
	var c: Dictionary = s.CLASSES[u.cls]
	var reach := float(c.range)
	# our King under attack: those near come back and fight whoever's at him
	var th := king_threat(int(u.team))
	if not th.is_empty() and (u.pos as Vector2).distance_to(king_pos(int(u.team))) < 45.0 and u.hp > u.max_hp * 0.35:
		s._fight(u, th)
		return
	# their King open (a gate of his down): the King runners go for him -- their heroes in the way first
	var eteam := 1 - int(u.team)
	if bool(u.get("kr", false)) and king_open(eteam) and u.hp > u.max_hp * 0.45:
		for o in s.units:
			if int(o.team) == eteam and s.alive(o) and bool(o.get("hero", false)) and (o.pos as Vector2).distance_to(u.pos) < reach + 3.0:
				s._fight(u, o)
				return
		_hit_point(u, king_pos(eteam), KING_R)
		return
	# hurt: home to heal
	if bool(u.get("back", false)):
		if u.hp >= u.max_hp * 0.92:
			u.back = false
		else:
			s._nav_to(u, s.spawn(int(u.team)), 1.5)
			return
	if u.hp < u.max_hp * 0.3 and not s.in_castle(u.pos, int(u.team)):
		u["back"] = true
		s._nav_to(u, s.spawn(int(u.team)), 1.5)
		return
	if u.cls == "priest" and s._think_priest(u):
		return
	# under an enemy tower that would shoot me (no minion of ours for it to shoot first, or it's on me): step out
	var tw := tower_in_range(1 - int(u.team), u.pos, 0.6)
	if not tw.is_empty() and (str(tw.target) == str(u.id) or not _our_minions_near(int(u.team), tw.p)):
		var away: Vector2 = ((u.pos as Vector2) - (tw.p as Vector2)).normalized()
		u.move = (away - _forward(u) * 0.6).normalized()
		return
	# an enemy hero in reach and not under his tower
	var foe := {}
	var fd := reach + 4.0
	for o in s.units:
		if int(o.team) == int(u.team) or not s.alive(o) or not bool(o.get("hero", false)):
			continue
		var d: float = (o.pos as Vector2).distance_to(u.pos)
		if d < fd and (tower_in_range(1 - int(u.team), o.pos).is_empty() or _our_minions_near(int(u.team), o.pos)):
			fd = d
			foe = o
	if not foe.is_empty():
		s._fight(u, foe)
		return
	# minions near
	var m := {}
	var md := maxf(reach + 2.0, 7.0)
	for o in s.units:
		if int(o.team) == int(u.team) or not s.alive(o) or not bool(o.get("minion", false)):
			continue
		var d2: float = (o.pos as Vector2).distance_to(u.pos)
		if d2 < md and tower_in_range(1 - int(u.team), o.pos).is_empty():
			md = d2
			m = o
	if not m.is_empty():
		s._fight(u, m)
		return
	# their tower, while our minions take its shots
	var et := _enemy_tower_near(u, reach + 8.0)
	if not et.is_empty() and vulnerable(et) and _our_minions_near(int(u.team), et.p) and str(et.target) != str(u.id):
		_hit_structure(u, et)
		return
	# follow our wave in my lane (a few steps behind its front); none out: wait by my lane's front tower
	var l := int(u.get("lane", 1))
	if l < 0:
		l = 1
	var front := {}
	var fi := -1
	for o in s.units:
		if int(o.team) != int(u.team) or not s.alive(o) or not bool(o.get("minion", false)) or int(o.lane) != l:
			continue
		if int(o.wp) > fi or (int(o.wp) == fi and (o.pos as Vector2).dot(_forward(u)) > (front.pos as Vector2).dot(_forward(u))):
			fi = int(o.wp)
			front = o
	var goal: Vector2
	if not front.is_empty():
		goal = (front.pos as Vector2) - _forward(u) * 3.0
	else:
		goal = _home_tower_spot(int(u.team), l)
	s._nav_to(u, goal, 1.2)

func _our_minions_near(team: int, p: Vector2) -> bool:
	for o in s.units:
		if bool(o.get("minion", false)) and int(o.team) == team and s.alive(o) and (o.pos as Vector2).distance_to(p) <= TOWER_RANGE:
			return true
	return false

func _home_tower_spot(team: int, l: int) -> Vector2:
	# behind our frontmost standing tower of the lane (or at the gate)
	var best := {}
	for tw in towers:
		if int(tw.team) == team and int(tw.lane) == l and not bool(tw.dead) and (best.is_empty() or int(tw.tier) < int(best.tier)):
			best = tw
	if best.is_empty():
		return wp(team, l, 1)
	var fwd := Vector2(0, -1) if team == 0 else Vector2(0, 1)
	return (best.p as Vector2) - fwd * 3.0

func _enemy_gate_down(team: int) -> bool:
	for g in s.gates:
		if int(g.team) != team and str(g.get("kind", "")) != "jail" and not s.gate_blocks(g):
			return true
	return false
