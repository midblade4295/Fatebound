extends RefCounted
## A simple computer opponent. It plays through the same deploy() call a player uses and
## sees nothing a player could not see. Seeded, so bot-versus-bot matches are repeatable.
##
## It does not know cards by name: it sorts whatever is in its hand into roles (for regiments)
## and effects (for orders and works) from the card data, so it can play any deck.
## Three levels differ in how quickly it thinks, how much Powder it saves before attacking,
## how readily it answers a threat and how often it remembers its orders.

const Sim = preload("res://scripts/sim/battle_sim.gd")
const GsRng = preload("res://scripts/sim/sim_rng.gd")

# "powder" is how fast that level's Powder comes, as a share of the player's. Tuning how the
# Veteran plays (thinking faster, attacking sooner or later, bigger waves, backing up survivors)
# did not make him win more against the Regular over 400 matches each, so his edge is an honest
# and stated one: more Powder.
const LEVELS := [
	{"name": "Recruit", "think": [1.3, 2.1], "wave_at": 10.0, "wave": 2, "orders": 0.3, "counter": false, "edge": -1, "powder": 1.0,
			"about": "Slow to react, and forgets his orders."},
	{"name": "Regular", "think": [0.5, 0.9], "wave_at": 9.0, "wave": 3, "orders": 1.0, "counter": true, "edge": 0, "powder": 1.0,
			"about": "Plays by exactly the rules you do."},
	{"name": "Veteran", "think": [0.3, 0.5], "wave_at": 9.0, "wave": 3, "orders": 1.0, "counter": true, "edge": 1, "powder": 1.1,
			"about": "Quick to react, and his Powder comes a tenth faster."},
]
# The order in which roles go into an attack.
const ATTACK_RANK := {"line": 0.0, "horse": 1.0, "gun": 2.0, "horse_gun": 2.5, "mob": 3.0, "sapper": 3.5, "light": 4.0,
		"dragoons": 4.5, "general": 5.0, "light_horse": 5.5, "short_gun": 6.0}

var side: int
var rng: GsRng
var level: int = 1
var cfg: Dictionary
var think_timer: float = 1.5
var attack_flank: int = 0
var push_left: int = 0        # cards still to play in the current attack wave
var push_clock: float = 0.0


func _init(bot_side: int, seed_value: int, bot_level: int = 1) -> void:
	side = bot_side
	level = clampi(bot_level, 0, LEVELS.size() - 1)
	cfg = LEVELS[level]
	rng = GsRng.new(seed_value * 7919 + bot_side * 104729 + 13)
	attack_flank = rng.range_i(0, 1)


## What a card is for, worked out from its data.
static func role(def: Dictionary) -> String:
	if def["type"] == "order":
		return "order"
	if def["type"] == "work":
		return "work"
	if def.has("demolish"):
		return "sapper"
	match String(def.get("arm", "")):
		"command":
			return "general"
		"cavalry":
			if def.has("dismount"):
				return "dragoons"
			return "horse" if int(def["cost"]) >= 4 else "light_horse"
		"artillery":
			if float(def.get("speed", 0.0)) > 0.0:
				return "horse_gun"
			# A gun that cannot reach across the creek from our own ground is for holding it.
			return "gun" if float(def.get("range", 0.0)) >= 11.0 else "short_gun"
	if bool(def.get("can_square", false)):
		return "line"
	return "light" if bool(def.get("loose", false)) else "mob"


## Eight cards for a computer opponent: always enough regiments that can march and fight,
## at least one that can form square, and the rest drawn at random.
static func pick_deck(cards: Dictionary, seed_value: int) -> Array:
	var pick_rng := GsRng.new(seed_value * 31 + 7)
	var lines: Array = []
	var movers: Array = []
	var rest: Array = []
	for id: String in cards:
		var r := role(cards[id])
		if r == "line":
			lines.append(id)
		elif r in ["mob", "light", "horse", "light_horse", "dragoons"]:
			movers.append(id)
		else:
			rest.append(id)
	pick_rng.shuffle(lines)
	pick_rng.shuffle(movers)
	var deck: Array = [lines[0]]
	deck.append_array(movers.slice(0, 3))
	rest.append_array(lines.slice(1))
	rest.append_array(movers.slice(3))
	pick_rng.shuffle(rest)
	var commanders := 0
	for id: String in rest:
		if deck.size() >= 8:
			break
		if bool(cards[id].get("unique", false)):
			if commanders > 0:
				continue                  # one commander to a deck
			commanders += 1
		deck.append(id)
	return deck


func tick(sim: Sim) -> void:
	if sim.phase == Sim.PHASE_OVER:
		return
	think_timer -= Sim.DT
	if think_timer > 0.0:
		return
	think_timer = rng.range_f(float(cfg["think"][0]), float(cfg["think"][1]))
	if _try_orders(sim):
		return
	if _try_defend(sim):
		return
	if _try_attack(sim):
		return
	_try_spend(sim)


func _play(sim: Sim, card_id: String, local_pos: Vector2) -> bool:
	var idx: int = sim.hand(side).find(card_id)
	if idx < 0:
		return false
	var p := Sim.from_local(side, local_pos)
	p.x = clampf(p.x, 0.8, Sim.FIELD_W - 0.8)
	return sim.deploy(side, idx, p)


## The cards in hand with one of the given roles, in that order of role.
func _in_hand(sim: Sim, roles: Array) -> Array:
	var out: Array = []
	var hand: Array = sim.hand(side)
	for want: String in roles:
		for id: String in hand:
			if role(sim.cards[id]) == want and not out.has(id):
				out.append(id)
	return out


func _play_role(sim: Sim, roles: Array, local_pos: Vector2) -> bool:
	for id: String in _in_hand(sim, roles):
		if _play(sim, id, local_pos):
			return true
	return false


## The first card in hand whose order or work has that effect, or "".
func _with_effect(sim: Sim, effect: String) -> String:
	for id: String in sim.hand(side):
		if String(sim.cards[id].get("effect", "")) == effect:
			return id
	return ""


## The most advanced enemy regiment on our half of the field, and how far from our baseline.
func _intruder(sim: Sim) -> Array:
	var threat: Sim.Regiment = null
	var threat_y := Sim.FIELD_H * 0.5 + 0.5
	for o: Sim.Regiment in sim.regiments:
		if o.side == side or o.dead or o.state == Sim.ST_ROUT:
			continue
		var ly := Sim.local_y(side, o.pos.y)
		if ly < threat_y:
			threat_y = ly
			threat = o
	return [threat, threat_y]


func _try_orders(sim: Sim) -> bool:
	if rng.next_f() > float(cfg["orders"]):
		return false
	var rally := _with_effect(sim, "rally")
	var fire := _with_effect(sim, "fire")
	for r: Sim.Regiment in sim.regiments:
		if r.side != side or r.dead:
			continue
		# Rally is for a regiment worth saving that is still a long run from home, where it
		# would rally by itself: not for one about to reach the farmhouse anyway.
		if rally != "" and r.state == Sim.ST_ROUT and r.men * 2 >= r.men_max and int(r.def["cost"]) >= 3 \
				and Sim.local_y(side, r.pos.y) > 11.0:
			if _play(sim, rally, Sim.from_local(side, r.pos)):
				return true
		var reach := float(r.def.get("range", 0.0))
		if fire != "" and reach > 0.0 and r.arm == "infantry" and r.men >= 4 and r.reload > 1.6 and r.state == Sim.ST_MARCH and rng.next_f() < 0.5:
			for o: Sim.Regiment in sim.regiments:
				if o.side != side and not o.dead and o.state != Sim.ST_ROUT and r.pos.distance_to(o.pos) <= reach:
					if _play(sim, fire, Sim.from_local(side, r.pos)):
						return true
					break
	for id: String in sim.hand(side):
		var def: Dictionary = sim.cards[id]
		var done := false
		match String(def.get("effect", "")):
			"barrage":
				done = _try_bombard(sim, id)
			"cover":
				done = _try_dig(sim, id)
			"spotter":
				done = _try_balloon(sim, id, false)
			"volley":
				done = _try_volley(sim, id)
			"steady":
				done = _try_steady(sim, id)
			"haste":
				done = _try_haste(sim, id)
			"bugle":
				done = _try_bugle(sim, id)
			"raid":
				done = sim.powder[1 - side] >= 7.0 and _play(sim, id, Vector2(9.0, 3.0))
			"ambush":
				done = sim.powder[side] >= float(def["cost"]) + 1.0 and _try_ambush(sim, id)
			"supply":
				done = sim.powder[side] >= 7.0 and _intruder(sim)[0] == null and _play(sim, id, Vector2(5.0, 3.0))
			"depot":
				done = sim.powder[side] >= 8.0 and _intruder(sim)[0] == null and _play(sim, id, Vector2(9.0 + rng.range_f(-3.0, 3.0), 7.0))
			"abatis":
				done = _try_abatis(sim, id)
			"hospital":
				done = _try_hospital(sim, id)
			"mine":
				done = _try_mine(sim, id)
		if done:
			return true
	if _try_general(sim):
		return true
	return false


## Leaders go where two or more of our regiments are fighting together: a little behind the
## foremost of them. Only one commander (General or Marshal) at a time.
func _try_general(sim: Sim) -> bool:
	var leaders: Array = []
	for id: String in _in_hand(sim, ["general"]):
		if not bool(sim.cards[id].get("unique", false)) or sim.general(side) == null:
			leaders.append(id)
	if leaders.is_empty():
		return false
	var lead: Sim.Regiment = null
	for r: Sim.Regiment in sim.regiments:
		if r.side != side or r.dead or r.state == Sim.ST_ROUT or r.arm == "artillery" or r.arm == "command":
			continue
		var company := 0
		for o: Sim.Regiment in sim.regiments:
			if o != r and o.side == side and not o.dead and o.state != Sim.ST_ROUT and o.arm != "command" and o.pos.distance_to(r.pos) <= 5.0:
				company += 1
		if company >= 2 and (lead == null or Sim.local_y(side, r.pos.y) > Sim.local_y(side, lead.pos.y)):
			lead = r
	if lead == null:
		return false
	var behind := Sim.from_local(side, lead.pos)
	behind.y = clampf(behind.y - 2.5, 1.5, sim.deploy_depth(side, lead.pos.x))
	for id: String in leaders:
		if _play(sim, id, behind):
			return true
	return false


## A bombardment lands seconds after it is called, so it goes on things that will still be
## there: squares, guns, a knot of regiments, or a battery that is nearly done for.
func _try_bombard(sim: Sim, id: String) -> bool:
	var radius := float(sim.cards[id]["radius"])
	var best_pos := Vector2.ZERO
	var best := 1.9
	for o: Sim.Regiment in sim.regiments:
		if o.side == side or o.dead or o.state == Sim.ST_ROUT:
			continue
		var still := o.state == Sim.ST_SQUARE or o.state == Sim.ST_FORMING or float(o.def.get("speed", 0.0)) <= 0.0 or o.in_melee
		var score := 1.0 if still else 0.3
		if o.state == Sim.ST_SQUARE or o.state == Sim.ST_FORMING:
			score += 1.2
		for other: Sim.Regiment in sim.regiments:
			if other != o and other.side != side and not other.dead and other.pos.distance_to(o.pos) <= radius * 0.8:
				score += 0.8
		if score > best:
			best = score
			best_pos = o.pos
	if best > 1.9:
		return _play(sim, id, Sim.from_local(side, best_pos))
	for st: Sim.Structure in sim.structures:
		if st.side != side and not st.dead and (st.hp <= 300.0 or sim.phase == Sim.PHASE_OVERTIME):
			return _play(sim, id, Sim.from_local(side, st.pos))
	return false


## Earthworks go in front of something of ours that is standing and being shot at.
func _try_dig(sim: Sim, id: String) -> bool:
	for r: Sim.Regiment in sim.regiments:
		if r.side != side or r.dead or r.state == Sim.ST_ROUT or r.arm == "cavalry" or r.arm == "command":
			continue
		if r.since_hit > 2.0 or r.hp < r.max_hp * 0.6:
			continue
		# Worth digging for something that is going to stay put: a gun, men on foot holding.
		var staying := r.arm == "artillery" or r.def.has("dismount") or r.state == Sim.ST_SQUARE
		if not staying and sim.powder[side] < 6.0:
			continue
		var front := r.pos + Vector2(0.0, Sim.fwd(side) * 0.6)
		if sim.cover_mult(r, r.pos + Vector2(0.0, Sim.fwd(side) * 6.0)) < 1.0:
			continue
		if _play(sim, id, Sim.from_local(side, front)):
			return true
	return false


## A balloon goes up over a flank where we have a gun, or (to use the card) over either.
func _try_balloon(sim: Sim, id: String, anywhere: bool) -> bool:
	for flank in 2:
		var x := 3.5 if flank == 0 else 14.5
		if sim.balloon_over(side, x):
			continue
		var guns := anywhere
		for r: Sim.Regiment in sim.regiments:
			if r.side == side and not r.dead and r.arm == "artillery" and (r.pos.x < Sim.FIELD_W * 0.5) == (flank == 0):
				guns = true
		if guns and _play(sim, id, Vector2(x, 6.0)):
			return true
	return false


## Volley Fire! is worth its Powder where two or more of ours are reloading with targets in reach.
func _try_volley(sim: Sim, id: String) -> bool:
	for r: Sim.Regiment in sim.regiments:
		if r.side != side or r.dead or r.state == Sim.ST_ROUT or float(r.def.get("range", 0.0)) <= 0.0 or r.reload < 1.0:
			continue
		var busy := 0
		for o: Sim.Regiment in sim.regiments:
			if o.side == side and not o.dead and o.reload >= 1.0 and float(o.def.get("range", 0.0)) > 0.0 and o.pos.distance_to(r.pos) <= 3.5:
				for e: Sim.Regiment in sim.regiments:
					if e.side != side and not e.dead and e.pos.distance_to(o.pos) <= float(o.def["range"]):
						busy += 1
						break
		if busy >= 2:
			return _play(sim, id, Sim.from_local(side, r.pos))
	return false


## Hold the Line! for a regiment of some worth that is fighting hard and wavering.
func _try_steady(sim: Sim, id: String) -> bool:
	for r: Sim.Regiment in sim.regiments:
		if r.side != side or r.dead or r.state == Sim.ST_ROUT or r.arm == "command" or int(r.def["cost"]) < 3:
			continue
		if (r.in_melee or r.since_hit < 1.0) and r.morale < r.morale_max * 0.45 and r.hp > r.max_hp * 0.4:
			return _play(sim, id, Sim.from_local(side, r.pos))
	return false


## Forced March for two or more regiments going forward with nobody yet in front of them.
func _try_haste(sim: Sim, id: String) -> bool:
	if rng.next_f() > 0.25:
		return false
	for r: Sim.Regiment in sim.regiments:
		if r.side != side or r.dead or r.state == Sim.ST_ROUT or r.arm == "artillery" or r.arm == "command":
			continue
		var ly := Sim.local_y(side, r.pos.y)
		if ly < Sim.DEPLOY_DEPTH - 4.0 or ly > 28.0 or r.in_melee:
			continue
		var clear := true
		for o: Sim.Regiment in sim.regiments:
			if o.side != side and not o.dead and o.pos.distance_to(r.pos) <= 7.0:
				clear = false
				break
		var company := 0
		for o: Sim.Regiment in sim.regiments:
			if o != r and o.side == side and not o.dead and o.arm != "artillery" and o.pos.distance_to(r.pos) <= 4.0:
				company += 1
		if clear and company >= 1:
			return _play(sim, id, Sim.from_local(side, r.pos))
	return false


## Bugle Call for horsemen with something worth charging close by.
func _try_bugle(sim: Sim, id: String) -> bool:
	for r: Sim.Regiment in sim.regiments:
		if r.side != side or r.dead or r.state == Sim.ST_ROUT or r.arm != "cavalry" or r.runup >= Sim.CHARGE_RUNUP or r.recoil > 0.0:
			continue
		for o: Sim.Regiment in sim.regiments:
			if o.side != side and not o.dead and o.state != Sim.ST_SQUARE and o.state != Sim.ST_FORMING and o.pos.distance_to(r.pos) <= 6.0:
				return _play(sim, id, Sim.from_local(side, r.pos))
	return false


## An ambush behind an enemy gun that stands well clear of the enemy's own works (whose guns
## would make short work of four riflemen).
func _try_ambush(sim: Sim, id: String) -> bool:
	for o: Sim.Regiment in sim.regiments:
		if o.side == side or o.dead or o.arm != "artillery":
			continue
		var spot := Sim._fix_pos(o.pos + Vector2(0.0, -Sim.fwd(side) * 2.0))
		var exposed := false
		for st: Sim.Structure in sim.structures:
			if st.side != side and not st.dead and st.pos.distance_to(spot) <= st.gun_range + 0.5:
				exposed = true
				break
		if not exposed and _play(sim, id, Sim.from_local(side, spot)):
			return true
	return false


## Felled trees across the path of enemy horse on our half.
func _try_abatis(sim: Sim, id: String) -> bool:
	var found := _intruder(sim)
	var threat: Sim.Regiment = found[0]
	if threat == null or threat.arm != "cavalry":
		return false
	var depth := sim.deploy_depth(side, threat.pos.x)
	return _play(sim, id, Vector2(threat.pos.x, clampf(float(found[1]) - 2.5, 1.5, depth)))


## A field hospital beside a hurt regiment that is out of the fighting, if none is up yet.
func _try_hospital(sim: Sim, id: String) -> bool:
	for w: Sim.Work in sim.works:
		if w.side == side and w.effect == "hospital":
			return false
	for r: Sim.Regiment in sim.regiments:
		if r.side != side or r.dead or r.in_melee or r.hp > r.max_hp * 0.6 or int(r.def["cost"]) < 3 or r.arm == "artillery":
			continue
		if _play(sim, id, Sim.from_local(side, r.pos)):
			return true
	return false


## A torpedo in the path of an enemy regiment coming across our half, if none is laid yet.
func _try_mine(sim: Sim, id: String) -> bool:
	for w: Sim.Work in sim.works:
		if w.side == side and w.effect == "mine":
			return false
	var found := _intruder(sim)
	var threat: Sim.Regiment = found[0]
	if threat == null or float(threat.def.get("speed", 0.0)) <= 0.0 or float(found[1]) > 14.0:
		return false
	var depth := sim.deploy_depth(side, threat.pos.x)
	return _play(sim, id, Vector2(threat.pos.x, clampf(float(found[1]) - 2.2, 1.5, depth)))


func _try_defend(sim: Sim) -> bool:
	# The most advanced enemy on our half of the field.
	var threat: Sim.Regiment = null
	var threat_y := Sim.FIELD_H * 0.5 + 0.5
	for o: Sim.Regiment in sim.regiments:
		if o.side == side or o.dead or o.state == Sim.ST_ROUT:
			continue
		var ly := Sim.local_y(side, o.pos.y)
		if ly < threat_y:
			threat_y = ly
			threat = o
	if threat == null:
		return _try_counter_battery(sim) if bool(cfg["counter"]) else false
	var defenders := 0
	var attackers := 0
	for o: Sim.Regiment in sim.regiments:
		if o.dead or o.state == Sim.ST_ROUT or o.pos.distance_to(threat.pos) > 7.5:
			continue
		if o.side == side:
			defenders += 1
		else:
			attackers += 1
	if defenders >= attackers + int(cfg["edge"]):
		return false
	var tx := threat.pos.x
	var depth := sim.deploy_depth(side, tx)
	if threat.arm == "cavalry":
		# Infantry far enough back to close its square before the horses arrive, or a gun.
		var y := clampf(threat_y - 6.5, 1.5, depth)
		if _play_role(sim, ["line"], Vector2(tx, y)):
			return true
		if _play_role(sim, ["short_gun", "gun", "horse_gun"], Vector2(tx, clampf(threat_y - 7.5, 1.5, depth))):
			return true
		return _play_role(sim, ["mob", "dragoons", "light"], Vector2(tx, y))
	# Against muskets and guns: cavalry dropped close on the flank, else a firing line in front.
	var side_x := tx + (3.5 if tx < Sim.FIELD_W * 0.5 else -3.5)
	var cav_y := clampf(threat_y - 1.0, 1.5, depth)
	if not Sim.in_creek(Sim.from_local(side, Vector2(side_x, cav_y)).y):
		if _play_role(sim, ["light_horse", "horse"], Vector2(side_x, cav_y)):
			return true
	var line_y := clampf(threat_y - 5.0, 1.5, depth)
	return _play_role(sim, ["line", "short_gun", "light", "mob", "dragoons", "gun", "horse_gun"], Vector2(tx + rng.range_f(-0.8, 0.8), line_y))


## An enemy gun shelling one of our structures from across the creek: answer it with a gun
## of our own, or send light horse over the ford after it.
func _try_counter_battery(sim: Sim) -> bool:
	for o: Sim.Regiment in sim.regiments:
		if o.side == side or o.dead or o.arm != "artillery":
			continue
		var shelling := false
		for st: Sim.Structure in sim.structures:
			if st.side == side and not st.dead and o.pos.distance_to(st.pos) - st.radius <= float(o.def["range"]):
				shelling = true
				break
		if not shelling:
			continue
		var answered := false
		for mine: Sim.Regiment in sim.regiments:
			if mine.side == side and not mine.dead and mine.state != Sim.ST_ROUT and mine.pos.distance_to(o.pos) <= 12.0:
				if mine.arm == "artillery" or mine.arm == "cavalry":
					answered = true
					break
		if answered:
			continue
		var x := o.pos.x
		if _play_role(sim, ["gun", "horse_gun"], Vector2(x, Sim.DEPLOY_DEPTH - 0.4)):
			return true
		if _play_role(sim, ["light_horse", "light", "dragoons"], Vector2(x, Sim.DEPLOY_DEPTH - 0.5)):
			return true
	return false


func _try_attack(sim: Sim) -> bool:
	# Attack in waves: save up, then put several regiments over the same crossing together.
	if push_left <= 0:
		var need := float(cfg["wave_at"]) - (2.0 if sim.double_powder() else 0.0)
		if sim.powder[side] < need:
			return false
		push_left = int(cfg["wave"])
		push_clock = 7.0
		# Lean on the flank whose redoubt is weaker; switch now and then.
		var left := sim.redoubt(1 - side, 0)
		var right := sim.redoubt(1 - side, 1)
		if left.dead != right.dead:
			attack_flank = 1 if left.dead else 0
		elif absf(left.hp - right.hp) > 150.0:
			attack_flank = 0 if left.hp < right.hp else 1
		elif rng.next_f() < 0.35:
			attack_flank = 1 - attack_flank
	push_clock -= 0.7
	if push_clock <= 0.0:
		push_left = 0
		return false
	var base_x := 3.0 if attack_flank == 0 else 15.0
	var depth := sim.deploy_depth(side, base_x)
	var front_y := depth - 1.0
	var choices: Array = _in_hand(sim, ["line", "horse", "gun", "horse_gun", "mob", "sapper", "light", "dragoons", "general", "light_horse"])
	choices.sort_custom(func(a: String, b: String) -> bool:
		var ra := float(ATTACK_RANK[role(sim.cards[a])])
		var rb := float(ATTACK_RANK[role(sim.cards[b])])
		return ra < rb if ra != rb else a < b)
	for card_id: String in choices:
		var kind := role(sim.cards[card_id])
		var x := base_x + rng.range_f(-1.0, 1.0)
		var y := front_y + rng.range_f(-0.8, 0.0)
		if kind == "gun" or kind == "horse_gun":
			x = 3.5 if attack_flank == 0 else 14.5
			y = Sim.DEPLOY_DEPTH - 0.2
		elif kind == "light":
			y -= 1.5
		elif kind == "general":
			continue                    # he is placed by _try_general, with troops to lead
		if _play(sim, card_id, Vector2(x, y)):
			push_left -= 1
			return true
	return false


## With the Powder pouch full and nothing better to do, play whatever will go down, so a hand
## of orders and works does not sit there for the rest of the battle.
func _try_spend(sim: Sim) -> bool:
	if sim.powder[side] < Sim.POWDER_MAX - 0.3:
		return false
	var flank_x := 3.5 if attack_flank == 0 else 14.5
	for id: String in sim.hand(side):
		var def: Dictionary = sim.cards[id]
		var done := false
		match String(def.get("effect", "")):
			"spotter":
				done = _try_balloon(sim, id, true)
			"cover":
				done = _play(sim, id, Vector2(flank_x, 10.6))
			"barrage":
				var mark: Sim.Structure = null
				for st: Sim.Structure in sim.structures:
					if st.side != side and not st.dead and st.kind == "redoubt" and (mark == null or st.hp < mark.hp):
						mark = st
				if mark == null:
					mark = sim.hq(1 - side)
				done = _play(sim, id, Sim.from_local(side, mark.pos))
			"raid":
				done = _play(sim, id, Vector2(9.0, 3.0))
			"ambush":
				done = _try_ambush(sim, id)
			"supply", "depot":
				done = _play(sim, id, Vector2(flank_x, 6.0))
		if done:
			return true
	if _try_general(sim):
		return true
	return _play_role(sim, ["line", "mob", "light", "sapper", "dragoons", "horse", "light_horse", "horse_gun", "gun", "short_gun"],
			Vector2(3.0 if attack_flank == 0 else 15.0, sim.deploy_depth(side, 3.0 if attack_flank == 0 else 15.0) - 1.5))
