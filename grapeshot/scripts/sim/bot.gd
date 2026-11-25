extends RefCounted
## A simple computer opponent. It plays through the same deploy() call a player uses and
## sees nothing a player could not see. Seeded, so bot-versus-bot matches are repeatable.

const Sim = preload("res://scripts/sim/battle_sim.gd")
const GsRng = preload("res://scripts/sim/sim_rng.gd")

const ATTACK_ORDER := ["line_infantry", "heavy_cavalry", "field_gun", "militia", "skirmishers", "scouts"]

var side: int
var rng: GsRng
var think_timer: float = 1.5
var attack_flank: int = 0
var push_left: int = 0        # cards still to play in the current attack wave
var push_clock: float = 0.0


func _init(bot_side: int, seed_value: int) -> void:
	side = bot_side
	rng = GsRng.new(seed_value * 7919 + bot_side * 104729 + 13)
	attack_flank = rng.range_i(0, 1)


func tick(sim: Sim) -> void:
	if sim.phase == Sim.PHASE_OVER:
		return
	think_timer -= Sim.DT
	if think_timer > 0.0:
		return
	think_timer = rng.range_f(0.5, 0.9)
	if _try_orders(sim):
		return
	if _try_defend(sim):
		return
	_try_attack(sim)


func _play(sim: Sim, card_id: String, local_pos: Vector2) -> bool:
	var idx: int = sim.hand(side).find(card_id)
	if idx < 0:
		return false
	var p := Sim.from_local(side, local_pos)
	p.x = clampf(p.x, 0.8, Sim.FIELD_W - 0.8)
	return sim.deploy(side, idx, p)


func _try_orders(sim: Sim) -> bool:
	for r: Sim.Regiment in sim.regiments:
		if r.side != side or r.dead:
			continue
		if r.state == Sim.ST_ROUT and r.men * 2 >= r.men_max:
			if _play(sim, "rally", Sim.from_local(side, r.pos)):
				return true
		var reach := float(r.def.get("range", 0.0))
		if reach > 0.0 and r.arm == "infantry" and r.reload > 1.6 and r.state == Sim.ST_MARCH and rng.next_f() < 0.5:
			for o: Sim.Regiment in sim.regiments:
				if o.side != side and not o.dead and o.state != Sim.ST_ROUT and r.pos.distance_to(o.pos) <= reach:
					if _play(sim, "fire", Sim.from_local(side, r.pos)):
						return true
					break
	return false


func _try_defend(sim: Sim) -> bool:
	# The most advanced enemy on our half of the field.
	var threat: Sim.Regiment = null
	var threat_y := 16.5
	for o: Sim.Regiment in sim.regiments:
		if o.side == side or o.dead or o.state == Sim.ST_ROUT:
			continue
		var ly := Sim.local_y(side, o.pos.y)
		if ly < threat_y:
			threat_y = ly
			threat = o
	if threat == null:
		return _try_counter_battery(sim)
	var defenders := 0
	var attackers := 0
	for o: Sim.Regiment in sim.regiments:
		if o.dead or o.state == Sim.ST_ROUT or o.pos.distance_to(threat.pos) > 7.5:
			continue
		if o.side == side:
			defenders += 1
		else:
			attackers += 1
	if defenders >= attackers:
		return false
	var tx := threat.pos.x
	var depth := sim.deploy_depth(side, tx)
	if threat.arm == "cavalry":
		# Infantry far enough back to close its square before the horses arrive.
		var y := clampf(threat_y - 6.5, 1.5, depth)
		if _play(sim, "line_infantry", Vector2(tx, y)):
			return true
		return _play(sim, "field_gun", Vector2(tx, clampf(threat_y - 7.5, 1.5, depth)))
	# Against muskets and guns: cavalry dropped close on the flank, else a firing line in front.
	var side_x := tx + (3.5 if tx < Sim.FIELD_W * 0.5 else -3.5)
	var cav_y := clampf(threat_y - 1.0, 1.5, depth)
	if not Sim.in_creek(Sim.from_local(side, Vector2(side_x, cav_y)).y):
		if _play(sim, "scouts", Vector2(side_x, cav_y)) or _play(sim, "heavy_cavalry", Vector2(side_x, cav_y)):
			return true
	var line_y := clampf(threat_y - 5.0, 1.5, depth)
	for card_id: String in ["line_infantry", "skirmishers", "militia", "field_gun"]:
		if _play(sim, card_id, Vector2(tx + rng.range_f(-0.8, 0.8), line_y)):
			return true
	return false


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
		if _play(sim, "field_gun", Vector2(x, 13.6)):
			return true
		if _play(sim, "scouts", Vector2(x, 13.5)):
			return true
		if _play(sim, "skirmishers", Vector2(x, 13.5)):
			return true
	return false


func _try_attack(sim: Sim) -> bool:
	# Attack in waves: save up, then put several regiments over the same crossing together.
	if push_left <= 0:
		var need := 7.0 if sim.double_powder() else 9.0
		if sim.powder[side] < need:
			return false
		push_left = 3
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
	var front_y := 13.0 if depth <= Sim.DEPLOY_DEPTH else depth - 1.0
	for card_id: String in ATTACK_ORDER:
		var x := base_x + rng.range_f(-1.0, 1.0)
		var y := front_y + rng.range_f(-0.8, 0.0)
		if card_id == "field_gun":
			x = 3.5 if attack_flank == 0 else 14.5
			y = 13.8
		elif card_id == "skirmishers":
			y -= 1.5
		if _play(sim, card_id, Vector2(x, y)):
			push_left -= 1
			return true
	return false
