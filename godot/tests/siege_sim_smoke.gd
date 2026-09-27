extends SceneTree
const Sim = preload("res://scripts/siege/siege_sim.gd")

func _init() -> void:
	# Forge dice rules.
	assert(Sim.forge_result(["knight","knight","mage"]).cls == "knight")
	assert(not Sim.forge_result(["knight","knight","mage"]).up)
	assert(Sim.forge_result(["rogue","fate","fate"]).up)
	assert(Sim.forge_result(["ranger","mage","knight"]).cls == "")
	assert(Sim.forge_result(["barbarian","fate","ranger"]).cls != "")
	var totals := {"matches":0,"rescues":0,"kills":0,"classes":0,"pickups":0,"drops":0,"recaptures":0,"wins":[0,0,0]}
	for seed_value in [11, 22, 33, 44, 55, 66, 77, 88]:
		var sim = Sim.new()
		sim.setup(6, seed_value)
		# Make the human a bot too so the whole match plays itself.
		sim.by_id["you"].bot = true
		var steps := 0
		while not sim.ended and steps < int(Sim.MATCH_TIME / Sim.TICK) + 5:
			sim.step()
			steps += 1
			for e in sim.drain_events():
				match str(e.k):
					"rescue": totals.rescues += 1
					"death": totals.kills += 1
					"class": totals.classes += 1
					"pickup": totals.pickups += 1
					"drop": totals.drops += 1
					"recaptured": totals.recaptures += 1
			for u in sim.units:
				assert(absf(u.pos.x) <= Sim.HALF_W + 0.01 and absf(u.pos.y) <= Sim.HALF_L + 0.01)
				assert(u.hp <= u.max_hp + 0.01)
			for t in 2:
				var o: Dictionary = sim.oracles[t]
				if o.state == "carried":
					assert(sim.by_id[o.carrier].carrying and sim.by_id[o.carrier].team == t)
		assert(sim.ended)
		totals.matches += 1
		totals.wins[sim.winner + 1] += 1
		print("seed=%d time=%.0fs score=%s kills=%s winner=%d reason=%s" % [seed_value, sim.time, str(sim.score), str(sim.kills), sim.winner, sim.end_reason])
	assert(totals.classes > 0 and totals.kills > 0 and totals.pickups > 0)
	print("SIEGE_SIM_PASS ", totals)
	quit(0)
