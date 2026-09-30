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
		for p in msg.get("p", []):
			if p[0] == pid:
				if last_raw != Vector2.INF:
					old_jump = maxf(old_jump, last_raw.distance_to(p[1]))
				last_raw = p[1]
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
	print("NET_INTERP_PASS" if fails.is_empty() else "NET_INTERP_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
