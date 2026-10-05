extends SceneTree
# Online projectile smoothness (0.18.5, Kevin: "the projectiles skip across the screen online").
# A real server sim fires an arrow at a target; every snapshot goes through the real
# snapshot -> encode -> decode -> Net.apply path into a client mirror, and the client samples
# Net.interpolate at 5 points per snapshot interval (like frames between snapshots). Checks: no
# jumps, no stalls while it flies, and it reaches the target before it vanishes.
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
var fails := []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	var s = Sim.new()
	s.setup(4, 3)
	var m = Sim.new()
	m.setup(4, 3)
	for u in s.units:
		u.bot = false
		u.move = Vector2.ZERO
		u.pos = Vector2(-25, 0) if u.team == 0 else Vector2(25, 0)
	var shooter: Dictionary = s.units.filter(func(x): return x.team == 0)[0]
	var target: Dictionary = s.units.filter(func(x): return x.team == 1)[0]
	s._set_class(shooter, "ranger", false)
	shooter.pos = Vector2(-8.0, 20.0)
	target.pos = Vector2(-8.0, 32.0)
	target.hp = 9999.0
	target.max_hp = 9999.0
	s._shoot(shooter, Sim.angle_of(Vector2(0, 1)), 1.0, 0.0, 22.0, 14.0)
	var pid: int = s.projectiles[0].id
	var ticks := int(round(1.0 / Net.SNAP_HZ / Sim.TICK))        # sim ticks per snapshot
	var samples := []
	var old_jump := 0.0                                           # what the old code showed
	var last_raw := Vector2.INF
	for k in 40:
		var events := []
		for t in ticks:
			s.step(Sim.TICK)
			events.append_array(s.drain_events())
		var snap := Net.snapshot(s, "", events)
		var msg := Net.decode(Net.encode(Net.for_player(snap, s, "you"), true))
		Net.apply(m, msg, "you")
		var pb: PackedByteArray = msg.get("p", PackedByteArray())
		for pi in pb.size() / 22:
			if pb.decode_s16(pi * 22) + 32768 == pid:
				var raw := Vector2(pb.decode_s16(pi * 22 + 2) / 100.0, pb.decode_s16(pi * 22 + 4) / 100.0)
				if last_raw != Vector2.INF:
					old_jump = maxf(old_jump, last_raw.distance_to(raw))
				last_raw = raw
		var here := false
		for a in [0.2, 0.4, 0.6, 0.8, 1.0]:
			Net.interpolate(m, a)
			for p in m.projectiles:
				if p.id == pid:
					samples.append(p.pos)
					here = true
		if not here and not samples.is_empty():
			break
	check(samples.size() >= 10, "the arrow was drawn for %d samples" % samples.size())
	var worst := 0.0
	var stalls := 0
	for i in range(1, samples.size()):
		var d: float = (samples[i] as Vector2).distance_to(samples[i - 1])
		worst = maxf(worst, d)
		if d < 0.01 and i > 5:                                   # the first interval sits at the spawn
			stalls += 1
	check(worst < 0.5, "no jumps: largest step between frames %.2f m (the old snapshot-only drawing jumped %.2f m)" % [worst, old_jump])
	check(stalls == 0, "no stalls while it flies (%d)" % stalls)
	var end: Vector2 = samples[-1]
	check(end.distance_to(target.pos) < 1.0, "it reaches the target before vanishing (ends %.2f m from it)" % end.distance_to(target.pos))
	check(target.hp < 9999.0, "the arrow hit the target on the server")
	_jitter_check()
	print("NET_INTERP_PASS" if fails.is_empty() else "NET_INTERP_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)

func _jitter_check() -> void:
	# 0.31.23: a remote unit walking a straight line at 5 m/s, snapshots at SNAP_HZ arriving with +-25 ms of jitter and
	# one dropped, drawn at 60 fps through the render clock (as siege_mode does). Steps between frames must stay even:
	# no freezes, no jumps -- the old slide-to-the-newest scheme stalled and leapt under the same jitter.
	var srv = Sim.new()
	srv.setup(2, 5)
	var cli = Sim.new()
	cli.setup(2, 5)
	for u in srv.units:
		u.bot = false
		u.move = Vector2.ZERO
	var walker: Dictionary = srv.units[1]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var rt := -1.0
	var latest := 0.0
	var next_snap := 0.0
	var arrivals := []                               # [arrival wall time, msg]
	var wall := 0.0
	var steps := []
	var lastp := Vector2.INF
	var cu: Dictionary = cli.units[1]
	for frame in 240:
		var dt := 1.0 / 60.0
		wall += dt
		walker.pos += Vector2(5.0 * dt, 0.0)
		srv.time += dt
		if srv.time >= next_snap:
			next_snap += 1.0 / Net.SNAP_HZ
			if frame != 90:                          # one snapshot lost
				arrivals.append([wall + rng.randf_range(-0.025, 0.025) + 0.04, Net.snapshot(srv, "", [])])
		arrivals.sort_custom(func(x, y): return x[0] < y[0])
		while not arrivals.is_empty() and arrivals[0][0] <= wall:
			var msg: Dictionary = arrivals.pop_front()[1]
			Net.apply(cli, msg, "you")
			latest = float(msg.tm)
			if rt < 0.0:
				rt = latest - Net.INTERP_DELAY
		if rt >= 0.0:
			rt += dt
			var want := latest - Net.INTERP_DELAY
			var err := want - rt
			rt = want if absf(err) > 0.3 else rt + err * minf(1.0, dt * 3.0)
			Net.interpolate_at(cli, rt, "you")
			if lastp != Vector2.INF and frame > 40:
				steps.append((cu.pos as Vector2).distance_to(lastp))
			lastp = cu.pos
	var mean := 0.0
	for st in steps:
		mean += st
	mean /= maxf(steps.size(), 1)
	var worst := 0.0
	var stalls := 0
	for st in steps:
		worst = maxf(worst, absf(st - mean))
		if st < mean * 0.25:
			stalls += 1
	check(mean > 0.06 and mean < 0.1, "the walker advances ~5 m/s on screen (%.3f m per frame)" % mean)
	check(worst < mean * 1.5, "under jitter and a dropped snapshot, the worst frame step is within 1.5x the mean (%.3f vs %.3f)" % [worst, mean])
	check(stalls <= 2, "no more than 2 near-stalled frames (%d)" % stalls)
