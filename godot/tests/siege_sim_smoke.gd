extends SceneTree
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Castle = preload("res://scripts/siege/siege_castle.gd")

func _init() -> void:
	# Hat rules (Round 8, Fat Princess style).
	var hs = Sim.new()
	hs.setup(4, 1)
	for hu in hs.units: hu.bot = false; hu.move = Vector2.ZERO; hu.pos = Vector2(0, 0)
	var me: Dictionary = hs.by_id["you"]
	var st: Dictionary = hs.stands.filter(func(x): return x.team == 0 and x.cls == "knight")[0]
	me.pos = st.p + Vector2(0.9, 0)
	hs.step(Sim.TICK)
	assert(me.cls == "knight" and not me.up and int(st.stock) == Sim.HAT_STOCK_MAX - 1, "villager takes a hat at a stand")
	hs._kill({}, me)
	assert(me.cls == "villager" and hs.hats.size() == 1 and hs.hats[0].cls == "knight", "death drops the hat")
	var foe: Dictionary = hs.units.filter(func(x): return x.team == 1)[0]
	foe.pos = hs.hats[0].pos
	hs.step(Sim.TICK)
	assert(foe.cls == "knight" and hs.hats.is_empty(), "an enemy villager picks the dropped hat up")
	var ally: Dictionary = hs.units.filter(func(x): return x.team == 0 and x.id != "you")[0]
	hs._set_class(ally, "ranger", false)
	var rst: Dictionary = hs.stands.filter(func(x): return x.team == 0 and x.cls == "rogue")[0]
	ally.pos = rst.p + Vector2(0.9, 0)
	assert(hs.context_action(ally) == "hat" and hs.act(ally.id, "hat_swap") and ally.cls == "rogue" and hs.hats.size() == 1 and hs.hats[0].cls == "ranger", "swap at a stand drops the old hat")
	hs.levels[0]["hat_mage"] = 1
	var mst: Dictionary = hs.stands.filter(func(x): return x.team == 0 and x.cls == "mage")[0]
	var ally2: Dictionary = hs.units.filter(func(x): return x.team == 0 and x.id != "you" and x.id != ally.id)[0]
	ally2.pos = mst.p + Vector2(0.9, 0)
	hs.step(Sim.TICK)
	assert(ally2.cls == "mage" and ally2.up, "upgraded stand gives the upgraded hat")
	for i in int(Sim.HAT_REGEN / Sim.TICK) + 2: hs.step(Sim.TICK)
	assert(int(st.stock) == Sim.HAT_STOCK_MAX, "stands refill")
	for i in int(Sim.HAT_LIFETIME / Sim.TICK) + 2: hs.step(Sim.TICK)
	assert(hs.hats.is_empty(), "dropped hats expire")
	# Fat Princess rules (0.15.1): enemy stands work for whoever gets inside; outposts have no hats;
	# workers drop off at held outposts; attackers respawn forward only near a dropped hat.
	var red: Dictionary = hs.units.filter(func(x): return x.team == 1 and x.cls == "villager")[0]
	var bst: Dictionary = hs.stands.filter(func(x): return x.team == 0 and x.cls == "mage")[0]
	bst.stock = 1
	red.pos = bst.p + Vector2(0.9, 0)
	assert(Sim.in_castle(red.pos, 0), "the blue stand is inside the blue castle")
	hs.step(Sim.TICK)
	assert(red.cls == "mage" and red.up, "a red villager uses a blue stand (blue's upgrade applies)")
	var op: Dictionary = hs.outposts[0]
	op.owner = 0
	op.prog = 1.0
	var v2: Dictionary = hs.units.filter(func(x): return x.team == 0 and x.cls == "villager")[0]
	v2.pos = (op.p as Vector2) + Vector2(2.0, 0)
	for i in 30: hs.step(Sim.TICK)
	assert(v2.cls == "villager", "outposts give no hats")
	hs._set_class(v2, "worker", false)
	v2.load = {"kind":"wood", "n":4}
	var w0: int = hs.stock[0].wood
	v2.pos = (op.p as Vector2) + Vector2(2.4, 0)
	hs.step(Sim.TICK)
	assert(hs.stock[0].wood == w0 + 4, "workers drop off at an outpost their team holds")
	hs.hats.clear()
	var r1: Dictionary = hs.units.filter(func(x): return x.team == 0 and x.id != "you")[0]
	r1.role = "raid"
	r1.bot = false                              # the hat-near rule is for human respawns
	hs._respawn(r1)
	assert(r1.pos.distance_to(Sim.spawn(0)) < 10.0, "no dropped hat near the outpost -> respawn at the castle")
	hs.hats.append({"id":777, "cls":"knight", "up":false, "pos":(op.p as Vector2) + Vector2(12, 0), "t":0.0})
	hs._respawn(r1)
	assert(r1.pos.distance_to(op.p) < 4.0, "a dropped hat near the forward outpost -> respawn there")
	# Priest (Round 9): holding ATTACK beams the nearest injured ally; Sanctuary heals around.
	var ps = Sim.new()
	ps.setup(4, 2)
	for pu in ps.units: pu.bot = false; pu.move = Vector2.ZERO; pu.pos = Vector2(0, 0)
	var pr: Dictionary = ps.by_id["you"]
	ps._set_class(pr, "priest", false)
	var blues: Array = ps.units.filter(func(x): return x.team == 0 and x.id != "you")
	var near: Dictionary = blues[0]
	var far: Dictionary = blues[1]
	near.pos = Vector2(4, 0); far.pos = Vector2(20, 0)
	near.hp = near.max_hp * 0.4; far.hp = far.max_hp * 0.4
	var h0: float = near.hp
	for i in 30:
		ps.act("you", "attack")                     # held ATTACK = called every frame
		ps.step(Sim.TICK)
	assert(str(pr.beam) == near.id and near.hp > h0 + 15.0 and far.hp < far.max_hp * 0.41, "beam heals the nearest injured ally (%.0f -> %.0f)" % [h0, near.hp])
	for i in 12: ps.step(Sim.TICK)
	assert(str(pr.beam) == "", "releasing ATTACK drops the beam")
	near.hp = near.max_hp * 0.5; near.pos = Vector2(2, 0)
	var h1: float = near.hp
	pr.cd_ability = 0.0
	assert(ps.act("you", "ability"), "sanctuary starts")
	for i in 30: ps.step(Sim.TICK)
	assert(near.hp >= minf(near.max_hp, h1 + Sim.SANCTUARY_HEAL) - 0.5, "sanctuary heals allies close by (capped at max HP)")
	assert(Sim.HAT_CLASSES.has("priest") and ps.stands.any(func(x): return x.cls == "priest"), "priest hat stand exists")
	print("priest rules ok")
	# Knight block + berserker whirlwind (Round 11).
	var bs = Sim.new()
	bs.setup(4, 3)
	for bu in bs.units: bu.bot = false; bu.move = Vector2.ZERO; bu.pos = Vector2(0, -20) if bu.team == 1 else Vector2(0, 20)
	var kn: Dictionary = bs.by_id["you"]
	bs._set_class(kn, "knight", false)
	kn.pos = Vector2.ZERO; kn.face = Sim.angle_of(Vector2(0, -1))
	var behind: Dictionary = bs.units.filter(func(x): return x.team == 0 and x.id != "you")[0]
	behind.pos = Vector2(0, 1.5)
	var foe2: Dictionary = bs.units.filter(func(x): return x.team == 1)[0]
	foe2.pos = Vector2(0, -1.6)
	assert(bs.act("you", "ability") and bs.blocking(kn), "hold ability raises the shield")
	bs._blockers = bs.units.filter(func(x): return bs.blocking(x))
	var k0: float = kn.hp
	var b0: float = behind.hp
	bs._damage(foe2, kn, 30.0)
	bs._damage(foe2, behind, 30.0)
	assert(kn.hp == k0 and behind.hp == b0, "the shield stops hits on the knight (front) and on allies behind it")
	foe2.pos = Vector2(0, 3.0)
	bs._damage(foe2, kn, 10.0)
	assert(kn.hp < k0, "no protection from behind")
	for i in 12: bs.step(Sim.TICK)
	assert(not bs.blocking(kn), "releasing ability lowers the shield")
	var bz: Dictionary = behind
	bs._set_class(bz, "barbarian", true)
	bz.pos = Vector2(8, 0); bz.cd_ability = 0.0
	assert(bs.ability_of(bz) == "whirlwind" and bs.act(bz.id, "ability"), "berserker whirlwind starts")
	var t_start: float = bs.time
	while bs.whirling(bz): bs.step(Sim.TICK)
	assert(absf(bs.time - t_start - Sim.WHIRL_TIME) < 0.1, "whirlwind lasts 3 s")
	print("block + whirlwind rules ok")
	# Hat upgrades are bought at the hat shop, not the workshop (Round 12).
	var us = Sim.new()
	us.setup(4, 5)
	for uu in us.units: uu.bot = false; uu.move = Vector2.ZERO; uu.pos = Vector2(0, -20) if uu.team == 1 else Vector2(0, 20)
	var up_me: Dictionary = us.by_id["you"]
	us.stock[0] = {"wood": 50, "stone": 50}
	up_me.pos = us.workshop(0)
	assert(not us.act("you", "buy", "hat_knight"), "the workshop menu can't buy hat upgrades")
	var kst: Dictionary = us.stands.filter(func(x): return x.team == 0 and x.cls == "knight")[0]
	us._set_class(up_me, "knight", false)
	up_me.pos = kst.p + Vector2(0.9, 0)
	assert(us.context_action(up_me) == "hat_up", "at your class's hat shop the action is UPGRADE (was %s)" % us.context_action(up_me))
	assert(us.act("you", "interact") and int(us.levels[0].hat_knight) == 1, "upgrading at the hat shop works")
	assert(us.context_action(up_me) != "hat_up", "no second upgrade offered")
	var ally3: Dictionary = us.units.filter(func(x): return x.team == 0 and x.id != "you")[0]
	ally3.pos = kst.p + Vector2(-0.9, 0)
	us.step(Sim.TICK)
	assert(ally3.cls == "knight" and ally3.up, "the upgraded shop now gives Paladin hats")
	var rst2: Dictionary = us.stands.filter(func(x): return x.team == 0 and x.cls == "rogue")[0]
	up_me.pos = rst2.p + Vector2(0.9, 0)
	assert(us.context_action(up_me) == "hat", "at another class's shop the action is NEW HAT")
	print("hat shop upgrade rules ok")
	# The dungeon wing's jail door (Round 13): lifts for the castle's team, blocks and must be
	# smashed by the enemy, locks again when the King is back in his cell.
	var js = Sim.new()
	js.setup(4, 9)
	var jail: Dictionary = js.gates.filter(func(x): return x.team == 0 and str(x.get("kind", "")) == "jail")[0]
	var inside: Vector2 = Sim._c(0, Castle.CELL_C)
	var outside: Vector2 = (jail.c as Vector2) + ((jail.c as Vector2) - inside).normalized() * 1.2
	assert(js._push_out(inside, Sim.UNIT_R, 0).distance_to(inside) < 0.05, "the King's own cell floor is clear for the castle's team")
	var through: Vector2 = jail.c
	assert(js._push_out(through, Sim.UNIT_R, 0).distance_to(through) < 0.05, "the castle's own players walk through the jail door")
	assert(js._push_out(through, Sim.UNIT_R, 1).distance_to(through) > 0.3, "the enemy is pushed back by the jail door")
	var jfoe: Dictionary = js.units.filter(func(x): return x.team == 1)[0]
	js._set_class(jfoe, "barbarian", false)
	jfoe.bot = false
	jfoe.pos = outside
	jfoe.face = Sim.angle_of((jail.c as Vector2) - outside)
	for i in 400:
		if jail.broken: break
		js.act(jfoe.id, "attack")
		js.step(Sim.TICK)
	assert(jail.broken, "the enemy can smash the jail door (hp %d)" % int(jail.hp))
	# It re-locks once the King is back in his cell -- but not on top of an enemy in the doorway.
	jfoe.pos = jail.c
	js._return_to_cell(1)
	assert(jail.broken, "the jail door waits while an enemy stands in the doorway")
	jfoe.pos = Vector2(0, -40)
	js.step(Sim.TICK)
	assert(not jail.broken and jail.hp >= jail.max_hp, "the jail door locks again when the King is back in his cell")
	# It lifts for a defender, but not while an enemy is near it.
	var def: Dictionary = js.units.filter(func(x): return x.team == 0)[0]
	def.bot = false
	def.move = Vector2.ZERO
	def.pos = (jail.c as Vector2) + ((jail.c as Vector2) - inside).normalized() * 1.0
	jfoe.pos = Vector2(0, -40)
	jfoe.bot = false
	js.step(Sim.TICK)
	assert(jail.open, "the jail door lifts for a defender")
	jfoe.pos = (jail.c as Vector2) + ((jail.c as Vector2) - inside).normalized() * 2.5
	jfoe.hp = jfoe.max_hp
	js.step(Sim.TICK)
	assert(not jail.open, "the jail door stays shut while an enemy is near it")
	print("jail rules ok")
	# Fishing (Round 19): ACTION on a river bank casts, the fish comes FISH_TIME later unless you're hit;
	# away from the river there's nothing to do; the fish fattens their King like the cake did.
	var fs = Sim.new()
	fs.setup(4, 17)
	var fisher: Dictionary = fs.units.filter(func(x): return x.team == 0)[0]
	for u in fs.units:
		u.bot = false
		u.move = Vector2.ZERO
		if u.id != fisher.id: u.pos = Vector2(0, -50)
	fisher.pos = Vector2(0.0, 30.0)
	fs.act(fisher.id, "interact")
	assert(str(fisher.task.get("kind", "")) != "fish", "no fishing away from the river")
	fisher.pos = fs._fish_spot(fisher)
	assert(fs.at_river_bank(fisher.pos), "the fish spot is on the bank")
	fs.act(fisher.id, "interact")
	assert(str(fisher.task.get("kind", "")) == "fish", "ACTION on the bank casts")
	for i in int((Sim.FISH_TIME + 0.3) / Sim.TICK):
		fs.step(Sim.TICK)
	assert(fisher.offering, "a fish after %.1f s on the bank" % Sim.FISH_TIME)
	fisher.offering = false
	fs.act(fisher.id, "interact")
	for i in int(1.0 / Sim.TICK):
		fs.step(Sim.TICK)
	fs._damage({"team": 1, "id": "x"}, fisher, 1.0)
	for i in int(2.0 / Sim.TICK):
		fs.step(Sim.TICK)
	assert(not fisher.offering, "a hit makes the fish get away")
	fisher.offering = true
	var cap: Dictionary = fs.oracles[1]
	var fed0 := int(cap.cakes)
	fisher.pos = (cap.pos as Vector2) + Vector2(0.6, 0.0)
	fs.act(fisher.id, "interact")
	assert(int(cap.cakes) == fed0 + 1 and not fisher.offering, "the fish feeds their King")
	print("fishing rules ok")
	# The rampart (Round 15): at L1 height behind the front wall, stairs down; arrows from up there
	# fly over the wall, arrows from the courtyard floor don't.
	var rs = Sim.new()
	rs.setup(4, 5)
	var walk_p: Vector2 = Sim._c(0, Vector2(2.5, 5.0))
	assert(absf(Sim.height_at(walk_p) - Castle.WALK_H) < 0.01, "the rampart is at %.1f m" % Sim.height_at(walk_p))
	var sh := Sim.height_at(Sim._c(0, Vector2(0.0, 7.5)))
	assert(sh > 0.3 and sh < Castle.WALK_H, "the rampart stairs climb from the courtyard (%.2f m midway)" % sh)
	var wall_z: float = Sim._c(0, Vector2(0.0, Castle.FRONT_Z)).y
	var outward: float = Sim.angle_of(Sim._c(0, Vector2(2.5, -10.0)) - walk_p)
	var arch: Dictionary = rs.units.filter(func(x): return x.team == 0)[0]
	arch.bot = false
	for u in rs.units:
		if u.id != arch.id: u.pos = Vector2(-25, 0); u.bot = false
	var results := []
	for spot in [walk_p, Sim._c(0, Vector2(2.5, 7.4))]:
		rs.projectiles.clear()
		arch.pos = spot
		rs._shoot(arch, outward, 1.0, 0.0, 22.0, 14.0)
		var passed := false
		for i in 40:
			rs.step(Sim.TICK)
			for rpr in rs.projectiles:
				if absf(float(rpr.pos.y)) < absf(wall_z) - 1.5:
					passed = true
		results.append(passed)
	assert(results[0], "an arrow from the rampart flies over the front wall")
	assert(not results[1], "an arrow from the courtyard floor is stopped by the wall")
	print("rampart rules ok")
	# Bots man it (Round 16): enemies at the blue front put blue's ranged defenders on its posts, and
	# they shoot over the wall from there.
	var rbs = Sim.new()
	rbs.setup(8, 13)
	var archers := []
	for u in rbs.units:
		u.bot = u.team == 0
		if u.team == 0:
			if archers.size() < 3:
				rbs._set_class(u, "ranger", false)
				u.role = "defend"
				u.pos = Sim._c(0, Vector2(-6.0 + archers.size() * 6.0, 11.0))
				archers.append(u)
			else:
				u.pos = Sim._c(0, Vector2(0.0, 26.0))
				u.bot = false
				u.move = Vector2.ZERO
		else:
			u.bot = false
			u.move = Vector2.ZERO
			u.pos = Sim._c(0, Vector2(-8.0 + (rbs.units.find(u) % 6) * 3.0, -2.5))   # just outside the wall
			u.max_hp = 9999.0
			u.hp = 9999.0
	var high_shots := 0
	var seen := {}
	for i in int(20.0 / Sim.TICK):
		rbs.step(Sim.TICK)
		for pr2 in rbs.projectiles:
			if bool(pr2.get("high", false)) and not seen.has(pr2.id):
				seen[pr2.id] = true
				high_shots += 1
	var manned := archers.filter(func(x): return Sim.height_at(x.pos) >= 1.7 and int(x.get("post", -1)) >= 0).size()
	assert(manned >= 2, "ranged defenders man the rampart when the front is threatened (%d of 3 up)" % manned)
	assert(high_shots >= 5, "and shoot over the wall from it (%d high shots)" % high_shots)
	print("rampart bots ok (%d up, %d shots)" % [manned, high_shots])
	# Projectiles hit what their path crosses (regression: from 0.16.0 to 0.18.1 arrows and bolts
	# hit NO units -- the per-team position arrays were appended through a copy).
	var ps2 = Sim.new()
	ps2.setup(2, 7)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 5
	for cls in ["ranger", "mage"]:
		var hits := 0
		for i in 60:
			for pu in ps2.units: pu.bot = false; pu.move = Vector2.ZERO; pu.pos = Vector2(-25, 0) if pu.team == 0 else Vector2(25, 0); pu.hp = 9999; pu.max_hp = 9999
			ps2.projectiles.clear()
			var shooter: Dictionary = ps2.units.filter(func(x): return x.team == 0)[0]
			var target: Dictionary = ps2.units.filter(func(x): return x.team == 1)[0]
			ps2._set_class(shooter, cls, false)
			shooter.pos = Vector2(-8.0, 20.0)
			target.pos = Vector2(-8.0 + rng2.randf_range(-0.66, 0.66), 20.0 + rng2.randf_range(0.4, 9.0))
			ps2._shoot(shooter, Sim.angle_of(Vector2(0, 1)), 1.0, float(Sim.CLASSES[cls].aoe), float(Sim.CLASSES[cls].proj_speed), 14.0)
			for k in 40:
				ps2.step(Sim.TICK)
				if ps2.projectiles.is_empty(): break
			if target.hp < 9999: hits += 1
		assert(hits == 60, "%s projectiles hit %d/60 targets on their path" % [cls, hits])
	print("projectile hit rules ok")
	print("hat rules ok")
	var seeds := [11, 22, 33, 44, 55, 66]
	if OS.has_environment("SEEDS"):
		seeds = []
		for s in OS.get_environment("SEEDS").split(","): seeds.append(int(s))
	var totals := {"matches":0,"rescues":0,"kills":0,"gate_broken":0,"gate_rebuilt":0,"repairs":0,"delivered":0,
		"upgrades":0,"pickups":0,"fed":0,"max_weight":0,"ladders":0,"ladders_down":0,"catapult_shots":0,"tantrums":0,"carried_back":0,"outpost_caps":0,"outpost_lost":0,"hat_take":0,"hat_pick":0,"hat_drop":0,"beams":0,"heal_bursts":0,"max_lift":0,"rescue_lifters":[],"wall_violations":0,"gate_violations":0,"wins":[0,0,0],"first_rescue":[]}
	for seed_value in seeds:
		var sim = Sim.new()
		sim.setup(16, seed_value)
		sim.by_id["you"].bot = true
		var first := -1.0
		var steps := 0
		var t0 := Time.get_ticks_msec()
		while not sim.ended and steps < int(Sim.MATCH_TIME / Sim.TICK) + 5:
			sim.step()
			steps += 1
			for e in sim.drain_events():
				match str(e.k):
					"rescue":
						totals.rescues += 1
						totals.rescue_lifters.append(int(e.get("n", 1)))
						if first < 0.0: first = sim.time
					"death": totals.kills += 1
					"gate_broken": totals.gate_broken += 1
					"gate_rebuilt": totals.gate_rebuilt += 1
					"repair": totals.repairs += 1
					"deliver": totals.delivered += int(e.n)
					"upgrade": totals.upgrades += 1
					"pickup": totals.pickups += 1
					"ladder_up": totals.ladders += 1
					"ladder_down": totals.ladders_down += 1
					"catapult_fire": totals.catapult_shots += 1
					"tantrum": totals.tantrums += 1
					"outpost_captured": totals.outpost_caps += 1
					"hat_take": totals.hat_take += 1
					"hat_pick": totals.hat_pick += 1
					"hat_drop": totals.hat_drop += 1
					"beam": totals.beams += 1
					"sanctuary": totals.heal_bursts += 1
					"outpost_lost": totals.outpost_lost += 1
					"recaptured":
						if str(e.id) != "": totals.carried_back += 1
					"lift_join": totals.max_lift = maxi(totals.max_lift, int(e.n))
					"fed":
						totals.fed += 1
						totals.max_weight = maxi(totals.max_weight, int(e.weight))
			if steps % 3 == 0:
				for u in sim.units:
					if u.state == "dead": continue
					for wi in sim.walls.size():
						var w: Dictionary = sim.walls[wi]
						if w.kind == "wall" and sim.on_ladder(u.pos, wi, u.team):
							continue   # crossing their own team's ladder is allowed
						if u.pos.distance_to(Sim.seg_closest(u.pos, w.a, w.b)) < w.r + Sim.UNIT_R - 0.05:
							totals.wall_violations += 1
							if totals.wall_violations <= 3:
								print("WALL VIOLATION t=%.1f %s cls=%s state=%s pos=%s wall=%s-%s" % [sim.time, u.id, u.cls, u.state, str(u.pos), str(w.a), str(w.b)])
					for g in sim.gates:
						if g.team != u.team and sim.gate_blocks(g) and u.pos.distance_to(Sim.seg_closest(u.pos, g.a, g.b)) < float(g.get("r", Sim.WALL_R)) + Sim.UNIT_R - 0.05:
							totals.gate_violations += 1
							if totals.gate_violations <= 3:
								print("GATE VIOLATION t=%.1f %s team=%d state=%s pos=%s gate=%d hp=%.0f broken=%s" % [sim.time, u.id, u.team, u.state, str(u.pos), g.id, g.hp, g.broken])
			for t in 2:
				var o: Dictionary = sim.oracles[t]
				if o.state == "carried":
					var lead: Dictionary = sim.by_id[o.carrier]
					assert(lead.carrying and lead.team == int(o.carry_team) and int(lead.lifting) == t)
					assert(o.lifters.size() >= 1 and o.lifters[0] == o.carrier)
		assert(sim.ended)
		totals.matches += 1
		totals.wins[sim.winner + 1] += 1
		totals.first_rescue.append(snappedf(first, 1.0))
		print("seed=%d time=%.0fs score=%s kills=%s winner=%d reason=%s stock=%s levels=%s gates_hp=%s ms=%d" % [seed_value, sim.time, str(sim.score), str(sim.kills),
			sim.winner, sim.end_reason, str(sim.stock), str(sim.levels), str(sim.gates.map(func(g): return int(g.hp))), Time.get_ticks_msec() - t0])
	print("violations wall=%d gate=%d" % [totals.wall_violations, totals.gate_violations])
	if totals.wall_violations != 0 or totals.gate_violations != 0:
		# Fail loudly and quit (a failed assert() in _init keeps Godot running until the runner's
		# 10-minute timeout).
		print("SIEGE_SIM_FAIL wall/gate violations")
		quit(1)
		return
	print("usage fed=%d max_weight=%d ladders=%d ladders_down=%d catapult_shots=%d upgrades=%d" % [totals.fed, totals.max_weight, totals.ladders, totals.ladders_down, totals.catapult_shots, totals.upgrades])
	print("outposts captured=%d lost=%d" % [totals.outpost_caps, totals.outpost_lost])
	print("hats taken at stands=%d picked up=%d dropped=%d | priest beams=%d sanctuaries=%d" % [totals.hat_take, totals.hat_pick, totals.hat_drop, totals.beams, totals.heal_bursts])
	print("oracle rescues=%d (lifters per rescue %s) pickups=%d tantrums=%d carried_back=%d max_lift=%d first_rescue=%s" % [totals.rescues, str(totals.rescue_lifters), totals.pickups, totals.tantrums, totals.carried_back, totals.max_lift, str(totals.first_rescue)])
	print("kills=%d delivered=%d gate_broken=%d fed=%d" % [totals.kills, totals.delivered, totals.gate_broken, totals.fed])
	# Catapults and ladders depend on each match's economy: reported above, not required.
	# With Priests healing defenders and the Workers repairing, gates hold more often and attackers
	# come over the walls on ladders instead: either counts as breaching a castle.
	var ok: bool = totals.kills > 0 and totals.delivered > 0 and totals.gate_broken + totals.ladders > 0 and totals.fed > 0 and totals.rescues > 0
	if not ok:
		# (A failed assert() inside _init doesn't end the process: the runner then waited out its
		# 10-minute timeout. Fail loudly and quit.)
		print("SIEGE_SIM_FAIL kills=%d delivered=%d gates+ladders=%d fed=%d rescues=%d" % [totals.kills, totals.delivered, totals.gate_broken + totals.ladders, totals.fed, totals.rescues])
		quit(1)
		return
	print("SIEGE_SIM_PASS ", totals)
	quit(0)
