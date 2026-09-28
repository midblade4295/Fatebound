extends SceneTree
# Diagnostic: timeline of gates, Oracle pickups/drops/carries for one 16v16 match.
const Sim = preload("res://scripts/siege/siege_sim.gd")
func _init() -> void:
	var seed_value := int(OS.get_environment("SEED")) if OS.has_environment("SEED") else 33
	var s = Sim.new()
	s.setup(16, seed_value)
	s.by_id["you"].bot = true
	var carry_start := [{}, {}]
	var best := [INF, INF]
	var first_at_cell := [-1.0, -1.0]
	var raiders_near_cell := [0, 0]
	while not s.ended:
		s.step()
		for t in 2:
			var o: Dictionary = s.oracles[t]
			if o.state == "carried" and int(o.carry_team) == t:
				best[t] = minf(best[t], o.pos.distance_to(Sim.throne(t)))
			if first_at_cell[t] < 0.0:
				for u in s.units:
					if u.team == t and s.alive(u) and u.pos.distance_to(o.pos) < 4.0 and o.state == "cell":
						first_at_cell[t] = s.time
						print("%6.1f team %d FIRST RESCUER AT CELL (%s %s)" % [s.time, t, u.id, u.cls])
						break
		for e in s.drain_events():
			match str(e.k):
				"gate_broken", "gate_rebuilt":
					print("%6.1f %s gate %d (team %d)" % [s.time, e.k, e.gate, e.team])
				"pickup":
					var o2: Dictionary = s.oracles[int(e.team)]
					var who := "RESCUERS" if int(e.carry_team) == int(e.team) else "captors"
					print("%6.1f oracle %d picked up by %s (%s) at dist-to-throne %.0f m, stage %d needs %d" % [s.time, e.team, who, e.id,
						o2.pos.distance_to(Sim.throne(int(e.team))), int(o2.get("weight", 0)), s.lifters_needed(o2)])
					if int(e.carry_team) == int(e.team):
						carry_start[int(e.team)] = {"at": s.time, "d": o2.pos.distance_to(Sim.throne(int(e.team)))}
						best[int(e.team)] = INF
				"drop":
					var o3: Dictionary = s.oracles[int(e.team)]
					var cause := "thrown" if e.thrown else "carrier down/left"
					print("%6.1f oracle %d DROPPED (%s, %s) at dist-to-throne %.0f m; closest this carry %.0f m" % [s.time, e.team, cause, e.id,
						o3.pos.distance_to(Sim.throne(int(e.team))), best[int(e.team)]])
				"rescue":
					print("%6.1f RESCUE team %d" % [s.time, e.team])
				"recaptured":
					print("%6.1f oracle %d back in her cell" % [s.time, e.team])
				"tantrum":
					print("%6.1f oracle %d TANTRUM hit %d" % [s.time, e.team, int(e.hit)])
	print("END t=%.0f score=%s reason=%s weights=%s" % [s.time, str(s.score), s.end_reason, str([s.oracles[0].get("weight",0), s.oracles[1].get("weight",0)])])
	quit(0)
