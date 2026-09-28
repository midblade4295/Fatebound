extends SceneTree
const Sim = preload("res://scripts/siege/siege_sim.gd")

func _init() -> void:
	# Forge dice rules (3 and 4 dice).
	assert(Sim.forge_result(["knight","knight","mage"]).cls == "knight")
	assert(not Sim.forge_result(["knight","knight","mage"]).up)
	assert(Sim.forge_result(["rogue","fate","fate"]).up)
	assert(Sim.forge_result(["ranger","mage","knight"]).cls == "")
	assert(Sim.forge_result(["ranger","mage","knight","ranger"]).cls == "ranger")
	var seeds := [11, 22, 33, 44, 55, 66]
	if OS.has_environment("SEEDS"):
		seeds = []
		for s in OS.get_environment("SEEDS").split(","): seeds.append(int(s))
	var totals := {"matches":0,"rescues":0,"kills":0,"gate_broken":0,"gate_rebuilt":0,"repairs":0,"delivered":0,
		"upgrades":0,"pickups":0,"fed":0,"max_weight":0,"ladders":0,"ladders_down":0,"catapult_shots":0,"tantrums":0,"carried_back":0,"max_lift":0,"rescue_lifters":[],"wall_violations":0,"gate_violations":0,"wins":[0,0,0],"first_rescue":[]}
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
						if g.team != u.team and sim.gate_blocks(g) and u.pos.distance_to(Sim.seg_closest(u.pos, g.a, g.b)) < Sim.WALL_R + Sim.UNIT_R - 0.05:
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
	assert(totals.wall_violations == 0 and totals.gate_violations == 0)
	print("usage fed=%d max_weight=%d ladders=%d ladders_down=%d catapult_shots=%d upgrades=%d" % [totals.fed, totals.max_weight, totals.ladders, totals.ladders_down, totals.catapult_shots, totals.upgrades])
	print("oracle rescues=%d (lifters per rescue %s) pickups=%d tantrums=%d carried_back=%d max_lift=%d first_rescue=%s" % [totals.rescues, str(totals.rescue_lifters), totals.pickups, totals.tantrums, totals.carried_back, totals.max_lift, str(totals.first_rescue)])
	# Catapults and ladders depend on each match's economy: reported above, not required.
	assert(totals.kills > 0 and totals.delivered > 0 and totals.gate_broken > 0 and totals.fed > 0)
	assert(totals.rescues > 0, "no rescues at all")
	print("SIEGE_SIM_PASS ", totals)
	quit(0)
