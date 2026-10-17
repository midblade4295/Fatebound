extends SceneTree
# a 5v5 of bots on the Rift, sim only: what falls when, who wins, stuck units
const Sim = preload("res://scripts/siege/siege_sim.gd")
func _init() -> void:
	var seed_v := int(OS.get_environment("SEED")) if OS.has_environment("SEED") else 3
	var s = Sim.new()
	s.setup(5, seed_v)
	s.setup_moba(["knight","mage","ranger","rogue","priest"][seed_v % 5], seed_v)
	s.by_id["you"].bot = true
	var m = s.moba
	if OS.has_environment("MATCH"):
		s.match_time = float(OS.get_environment("MATCH"))
	var t0 := Time.get_ticks_msec()
	var last := {}
	var stuck := {}
	var next_rep := 60.0
	var evs := []
	var maxu := 0
	while not s.ended and s.time < 2400.0:
		s.step()
		maxu = maxi(maxu, s.units.size())
		for e in s.drain_events():
			if str(e.k) in ["tower_down", "gate_broken", "gate_down", "gate_rebuilt", "king_down", "king_dead", "lord_down", "end"]:
				evs.append("%5.0f %s %s" % [s.time, e.k, str(e).substr(0, 110)])
		if s.time >= next_rep:
			next_rep += 60.0
			# stuck: alive non-monster units that moved < 0.3 m in 60 s while not fighting
			for u in s.units:
				if not s.alive(u) or u.has("mon"):
					continue
				var p0: Vector2 = last.get(u.id, Vector2.INF)
				if p0 != Vector2.INF and p0.distance_to(u.pos) < 0.3 and not s.in_castle(u.pos, int(u.team)):
					stuck[u.id] = "%s@%s t%.0f" % [u.cls, str(u.pos.snapped(Vector2(0.1,0.1))), s.time]
				last[u.id] = u.pos
			print("t %4.0f towers down b/r %d/%d  gates down %d/%d  kings %.2f/%.2f  kills %s  units %d  ms %d" % [s.time, m.towers_down(0), m.towers_down(1),
				m._gates_down(0), m._gates_down(1), m.king_frac(0), m.king_frac(1), str(s.kills), s.units.size(), Time.get_ticks_msec() - t0])
	for e in evs:
		print(e)
	print("END t %.0f ended %s winner %s  max units %d  stuck %s" % [s.time, s.ended, str(s.winner), maxu, str(stuck)])
	quit(0)
