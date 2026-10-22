extends SceneTree
# Online projectile smoothness (0.18.5, Kevin: "the projectiles skip across the screen online").
# A real server sim fires an arrow at a target; every snapshot goes through the real
# snapshot -> encode -> decode -> Net.apply path into a client mirror, and the client samples
# Net.interpolate at 5 points per snapshot interval (like frames between snapshots). Checks: no
# jumps, no stalls while it flies, and it reaches the target before it vanishes.
# 0.31.207 (Kevin: "the projectiles aren't smooth when traveling"): drawn as the game draws them -- at 60 fps on the
# render clock (Net.interpolate_at, INTERP_DELAY behind the newest snapshot), three frames a snapshot: every step
# between frames the arrow's own (22 m/s / 60 = 0.37 m) within 15 %, and it reaches the target before it goes. (The
# from/to slide it had flown on since 0.31.23 stepped 0 to 0.55 m on the same clock: a stall, then a jump.)
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
	shooter.pos = Vector2(0.0, -20.0)              # (0.31.170: open ground on the Rift; (-8, 20) was the Siege field's)
	target.pos = Vector2(0.0, -8.0)
	target.hp = 9999.0
	target.max_hp = 9999.0
	s._shoot(shooter, Sim.angle_of(Vector2(0, 1)), 1.0, 0.0, 22.0, 14.0)
	var pid: int = s.projectiles[0].id
	var ticks := int(round(1.0 / Net.SNAP_HZ / Sim.TICK))        # sim ticks per snapshot
	var samples := []
	var old_jump := 0.0                                           # what the old code showed
	var last_raw := Vector2.INF
	var rt := -1.0
	var seen_it := false
	var o_from := Vector2.INF                                     # (0.31.23-0.31.206's slide, on the same clock)
	var o_to := Vector2.INF
	var o_t0 := 0.0
	var o_dt := 0.05
	var o_t := -1.0
	var o_steps := []
	var o_last := Vector2.INF
	for k in 60:
		var events := []
		for t in ticks:
			s.step(Sim.TICK)
			events.append_array(s.drain_events())
		var snap := Net.snapshot(s, "", events)
		var msg := Net.decode(Net.encode(snap, true))
		Net.apply(m, msg, "you")
		if rt < 0.0:
			rt = float(msg.tm) - Net.INTERP_DELAY
		var pb: PackedByteArray = msg.get("p", PackedByteArray())
		for pi in pb.size() / 12:                                 # (6 x 16 bits a projectile)
			if pb.decode_s16(pi * 12) + 32768 == pid:
				var raw := Vector2(pb.decode_s16(pi * 12 + 2) / 100.0, pb.decode_s16(pi * 12 + 4) / 100.0)
				if last_raw != Vector2.INF:
					old_jump = maxf(old_jump, last_raw.distance_to(raw))
				last_raw = raw
				o_from = raw if o_to == Vector2.INF else o_to
				o_to = raw
				o_t0 = float(msg.tm) - 1.0 / Net.SNAP_HZ if o_t < 0.0 else o_t
				o_dt = maxf(float(msg.tm) - o_t0, 0.001)
				o_t = float(msg.tm)
		var here := false
		for f in 3:                                              # three frames at 60 fps a snapshot (20 Hz)
			rt += 1.0 / 60.0
			Net.interpolate_at(m, rt, "you")
			if o_to != Vector2.INF:
				var op := o_from.lerp(o_to, clampf((rt - o_t0) / o_dt, 0.0, 1.2))
				if o_last != Vector2.INF and (op.distance_to(o_last) > 0.001 or not o_steps.is_empty()):
					o_steps.append(op.distance_to(o_last))
				o_last = op
			for p in m.projectiles:
				if p.id == pid:
					samples.append(p.pos)
					here = true
		if here:
			seen_it = true
		elif seen_it:
			break
	check(samples.size() >= 10, "the arrow was drawn for %d frames" % samples.size())
	var step := 22.0 / 60.0
	var uneven := 0
	var worst := 0.0
	var moving := []
	for i in range(1, samples.size()):
		var d: float = (samples[i] as Vector2).distance_to(samples[i - 1])
		if d > 0.001 or not moving.is_empty():
			moving.append(d)
	for i in range(1, moving.size() - 1):                         # (its first frame leaving the hand and its last, the impact: parts of a step)
		var d2: float = moving[i]
		worst = maxf(worst, absf(d2 - step))
		if absf(d2 - step) > step * 0.15:
			uneven += 1
	var o_min := 99.0
	var o_max := 0.0
	for i in range(1, maxi(1, o_steps.size() - 1)):
		o_min = minf(o_min, float(o_steps[i]))
		o_max = maxf(o_max, float(o_steps[i]))
	check(uneven == 0, "every step between frames its own speed's (%.2f m), within 15 %% (worst off by %.2f m; %d uneven; the snapshots jumped %.2f m; the old slide stepped %.2f to %.2f m)" % [step, worst, uneven, old_jump, o_min, o_max])
	var end: Vector2 = samples[-1]
	check(end.distance_to(target.pos) < 1.0, "it reaches the target before vanishing (ends %.2f m from it)" % end.distance_to(target.pos))
	check(target.hp < 9999.0, "the arrow hit the target on the server")
	_jitter_check()
	print("NET_INTERP_PASS" if fails.is_empty() else "NET_INTERP_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)

func _jitter_check() -> void:
	# 0.31.23: a remote unit walking a straight line at 5 m/s, snapshots at SNAP_HZ arriving with +-25 ms of jitter and
	# one late (0.31.170: not dropped -- see below), drawn at 60 fps through the render clock (as siege_mode does). Steps between frames must stay even:
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
			# 0.31.170: a snapshot carries what changed since the one before, over a socket that delivers each in order --
			# so none is lost or overtaken: one held up 120 ms instead (the ones behind it wait for it), the rest jittered
			var at := wall + rng.randf_range(-0.025, 0.025) + 0.04 + (0.12 if frame == 90 else 0.0)
			if not arrivals.is_empty():
				at = maxf(at, float(arrivals[-1][0]))
			arrivals.append([at, Net.decode(Net.encode(Net.snapshot(srv, "", []), true))])
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
	check(worst < mean * 1.5, "under jitter and a late snapshot, the worst frame step is within 1.5x the mean (%.3f vs %.3f)" % [worst, mean])
	check(stalls <= 2, "no more than 2 near-stalled frames (%d)" % stalls)
