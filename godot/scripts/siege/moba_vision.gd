extends RefCounted
# 0.31.158 5V5 fog of war (Kevin: "Add a fog of war system like league of legends does it"), League's rules from its
# wiki (Sight, Brush): each side sees what's within the sight radius of its heroes, minions, towers, wards and its own
# castle; everything else is fog -- enemies there aren't shown, bots can't pick them out, the auto-aim passes them by.
# Sight radii at League's ratios to each other (heroes, towers, super minions and the Bone Lord 1350, minions 1200,
# wards 900) but set to the phone's screen, not League's units: at League's scale (a tower's 750 reach being our
# 11.5 m) a hero would see 20.5 m, past the top of a portrait screen -- the fog would never show. 15 m: it shows up
# the screen ahead of you and in the corners, as League's does. Brush: a unit inside a patch is
# hidden from the other side unless one of theirs (a ward too) is inside the same patch; looking in from outside shows
# nothing. Attacking reveals the attacker for 2 s (League: 300 around him, 2 s). Wards: each hero carries a trinket --
# WARD_CHARGES charges, one back every WARD_RECHARGE s; a ward stands WARD_LIFE s where it's put, unseen by the enemy;
# at most WARD_MAX of a hero's own at once (the oldest goes). The jungle's monsters see everything (League's aggroed
# monsters chase whoever they can't see too); towers shoot what's in their reach.
const SIGHT_HERO := 15.0
const SIGHT_MINION := 13.5
const SIGHT_BIG := 15.0
const SIGHT_TOWER := 15.0                                  # (its reach is 11.5)
const SIGHT_WARD := 10.0
const SIGHT_CASTLE := 18.0
const REVEAL := 2.0
const WARD_LIFE := 90.0
const WARD_RECHARGE := 45.0
const WARD_CHARGES := 2
const WARD_MAX := 3
const EVERY := 0.2                                         # seconds between vision updates
# blue's brush patches [centre, radius] (red's are the point mirror). 0.31.165, the Rift: beside each side lane (outside
# it), at the jungle's ways in -- from the river, from the middle lane, inside the buff camps' pockets -- and outside the
# side lanes by the keep.
const BRUSH_BLUE := [[Vector2(-51.0, 22.0), 2.8], [Vector2(-50.5, 46.0), 2.6], [Vector2(-40.5, 9.5), 2.6],
	[Vector2(-14.0, 11.0), 2.6], [Vector2(-31.0, 41.0), 2.4], [Vector2(-14.0, 42.5), 2.4], [Vector2(-33.0, 82.0), 2.4],
	[Vector2(51.0, 26.0), 2.8], [Vector2(50.5, 50.0), 2.6], [Vector2(40.5, 12.0), 2.6], [Vector2(14.0, 15.0), 2.6],
	[Vector2(30.5, 43.5), 2.4], [Vector2(14.5, 43.0), 2.4], [Vector2(33.0, 82.0), 2.4]]
const BRUSH_MID := []                                      # (the Siege field's: one on the island's east end)

var m                                                      # moba.gd
var s                                                      # the sim
var brushes: Array = []                                    # {id, p, r}
var wards: Array = []                                      # {id, team, owner, p, until, brush}
var seen: Array = [{}, {}]                                 # side -> {unit id: true}: the other sides' units it sees
var _clock := 0.0
var _wid := 0
var _bot_clock := 0.0

func setup(moba) -> void:
	m = moba
	s = moba.s
	for t in 2:
		for b in BRUSH_BLUE:
			brushes.append({"id":brushes.size(), "p":b[0] if t == 0 else -(b[0] as Vector2), "r":float(b[1])})
	for b in BRUSH_MID:
		brushes.append({"id":brushes.size(), "p":b[0], "r":float(b[1])})
	for u in s.units:
		if bool(u.get("hero", false)):
			u["ward_ch"] = float(WARD_CHARGES)
	_update()

func brush_at(p: Vector2) -> int:
	for b in brushes:
		if p.distance_squared_to(b.p) <= float(b.r) * float(b.r):
			return int(b.id)
	return -1

func sources(team: int) -> Array:
	# what gives side `team` sight: [position, radius, brush] each
	var out := []
	for u in s.units:
		if int(u.team) != team or not s.alive(u):
			continue
		var r := SIGHT_MINION
		if bool(u.get("hero", false)) or bool(u.get("super", false)) or bool(u.get("lordling", false)) or bool(u.get("summon", false)):
			r = SIGHT_HERO if bool(u.get("hero", false)) else SIGHT_BIG
		elif not bool(u.get("minion", false)):
			continue
		out.append([u.pos, r, brush_at(u.pos)])
	for tw in m.towers:
		if int(tw.team) == team and not bool(tw.dead):
			out.append([tw.p, SIGHT_TOWER, -1])
	for w in wards:
		if int(w.team) == team:
			out.append([w.p, SIGHT_WARD, int(w.brush)])
	out.append([m.king_pos(team), SIGHT_CASTLE, -1])
	return out

func step(dt: float) -> void:
	for i in range(wards.size() - 1, -1, -1):
		if s.time >= float(wards[i].until):
			s._event("ward_gone", {"ward":int(wards[i].id), "team":int(wards[i].team)})
			wards.remove_at(i)
	for t in 2:
		for hid in m.heroes[t]:
			var h: Dictionary = s.by_id.get(hid, {})
			if not h.is_empty():
				h["ward_ch"] = minf(float(WARD_CHARGES), float(h.get("ward_ch", 0.0)) + dt / WARD_RECHARGE)
	_bot_clock += dt
	if _bot_clock >= 1.0:
		_bot_clock = 0.0
		_bot_wards()
	_clock += dt
	if _clock >= EVERY:
		_clock = 0.0
		_update()

func _update() -> void:
	var ub := {}
	for t in 2:
		var src := sources(t)
		var vis := {}
		for u in s.units:
			if int(u.team) == t or not s.alive(u):
				continue
			if s.time < float(u.get("rev_until", -1.0)):
				vis[u.id] = true
				continue
			if not ub.has(u.id):
				ub[u.id] = brush_at(u.pos)
			var b: int = ub[u.id]
			var p: Vector2 = u.pos
			for sr in src:
				var r: float = sr[1]
				if p.distance_squared_to(sr[0]) <= r * r and (b < 0 or int(sr[2]) == b):
					vis[u.id] = true
					break
		seen[t] = vis

func can_see(team: int, u: Dictionary) -> bool:
	if team < 0 or team > 1 or int(u.get("team", -1)) == team:
		return true
	return (seen[team] as Dictionary).has(u.get("id", "")) or s.time < float(u.get("rev_until", -1.0))

func reveal(u: Dictionary) -> void:
	if int(u.get("team", -1)) in [0, 1]:
		u["rev_until"] = s.time + REVEAL

func ward_ready(u: Dictionary) -> bool:
	return float(u.get("ward_ch", 0.0)) >= 1.0 and s.alive(u)

func place_ward(u: Dictionary) -> bool:
	if not bool(u.get("hero", false)) or not ward_ready(u):
		return false
	var mine := wards.filter(func(w): return str(w.owner) == str(u.id))
	if mine.size() >= WARD_MAX:
		wards.erase(mine[0])
		s._event("ward_gone", {"ward":int(mine[0].id), "team":int(mine[0].team)})
	_wid += 1
	var w := {"id":_wid, "team":int(u.team), "owner":str(u.id), "p":u.pos, "until":s.time + WARD_LIFE, "brush":brush_at(u.pos)}
	wards.append(w)
	u.ward_ch = float(u.ward_ch) - 1.0
	s._event("ward", {"ward":_wid, "team":int(u.team), "id":u.id, "pos":u.pos})
	_update()
	return true

func _bot_wards() -> void:
	# a bot with a charge puts a ward in a brush patch it's standing in, when none of its side's is there
	for t in 2:
		for hid in m.heroes[t]:
			var h: Dictionary = s.by_id.get(hid, {})
			if h.is_empty() or not bool(h.bot) or not ward_ready(h):
				continue
			var b := brush_at(h.pos)
			if b < 0:
				continue
			var have := false
			for w in wards:
				if int(w.team) == t and int(w.brush) == b:
					have = true
					break
			if not have:
				place_ward(h)
