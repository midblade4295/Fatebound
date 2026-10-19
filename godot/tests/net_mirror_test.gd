extends SceneTree
# 0.31.170 (the online 5v5): the snapshot protocol end to end, without sockets -- a server's 5v5 of bots, every snapshot
# encoded, decoded and applied to a phone's mirror. After each one the mirror must hold what the server has: the same
# units in the same order (minions, monsters and summons coming and going), every key the snapshot carries on each of
# them and no key the server's unit lost, the towers, Kings, gates and camps, the zones, traps, wards and the Wyrm's
# stacks, the projectiles; and the fog of war worked out on the phone must be the server's. Midway a hero is swapped for
# a player's (moba.swap_hero) and a second phone joins from a keyframe between two snapshots. Prints the bandwidth and
# what a snapshot costs the server.
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Net = preload("res://scripts/siege/siege_net.gd")

var fails := 0
const EDGE := 0.03                     # (positions travel to the phone to the centimetre: a unit this near a sight's edge)

func _fail(why: String) -> void:
	fails += 1
	if fails <= 25:
		print("MISMATCH ", why)

func _init() -> void:
	var seed_v := int(OS.get_environment("NET_MIRROR_SEED")) if OS.has_environment("NET_MIRROR_SEED") else 77
	var dur := float(OS.get_environment("NET_MIRROR_S")) if OS.has_environment("NET_MIRROR_S") else 480.0
	var srv = Sim.new()
	srv.setup(5, seed_v, -1)
	srv.setup_moba("", seed_v)
	var cli = Sim.new()
	cli.setup(5, seed_v, -1)
	cli.setup_moba("", seed_v)
	var late = null
	var late_kf: PackedByteArray = PackedByteArray()
	var pending: Array = []
	var bytes := 0
	var kf_bytes := 0
	var snaps := 0
	var units_sum := 0
	var t_snap := 0
	var t_apply := 0
	var max_snap := 0
	var next_snap := 0.0
	var swapped := ""
	var checks := 0
	while srv.time < dur and not srv.ended:
		srv.step(1.0 / 30.0)
		pending.append_array(srv.drain_events())
		if swapped == "" and srv.time >= 200.0:
			# a player takes blue's top seat as a hero blue doesn't have
			var u: Dictionary = srv.by_id[srv.moba.heroes[0][0]]
			var have: Array = srv.moba.heroes[0].map(func(h): return str(srv.by_id[h].hid))
			for hid in ["druid", "golem", "musketeer", "duelist", "stormcaller", "dragoon", "necromancer"]:
				if not have.has(hid):
					srv.moba.swap_hero(u, hid)
					swapped = hid
					print("swapped %s to %s" % [str(u.id), hid])
					break
		if srv.time < next_snap:
			if late == null and late_kf.is_empty() and srv.time >= 300.0:
				late_kf = Net.encode(Net.keyframe(srv), true)       # (between two snapshots, as a seat happens)
				kf_bytes = late_kf.size()
			continue
		next_snap += 1.0 / Net.SNAP_HZ
		var t0 := Time.get_ticks_usec()
		var msg := Net.snapshot(srv, "", pending)
		var b := Net.encode(msg, true)
		var dt := Time.get_ticks_usec() - t0
		t_snap += dt
		max_snap = maxi(max_snap, dt)
		pending = []
		bytes += b.size()
		snaps += 1
		units_sum += srv.units.size()
		if not late_kf.is_empty() and late == null:
			late = Sim.new()
			late.setup(5, seed_v, -1)
			late.setup_moba("", seed_v)
			Net.apply(late, Net.decode(late_kf), "")
		var t1 := Time.get_ticks_usec()
		Net.apply(cli, Net.decode(b), "")
		t_apply += Time.get_ticks_usec() - t1
		_compare(srv, cli, "phone")
		if late != null:
			Net.apply(late, Net.decode(b), "")
			_compare(srv, late, "late phone")
		checks += 1
		if checks % 40 == 0:
			_compare_fog(srv, cli)
		if fails > 25:
			break
	var secs: float = srv.time
	print("match %.0f s, %d snapshots, %.0f units on average; swapped to %s; keyframe %.1f kB" % [secs, snaps,
		float(units_sum) / maxf(1.0, float(snaps)), swapped, kf_bytes / 1024.0])
	print("NET_MIRROR bandwidth %.1f kB/s a phone, snapshot %.2f ms (worst %.1f), apply %.2f ms" % [bytes / 1024.0 / maxf(1.0, secs),
		t_snap / 1000.0 / maxf(1.0, float(snaps)), max_snap / 1000.0, t_apply / 1000.0 / maxf(1.0, float(snaps))])
	if swapped == "":
		_fail("no hero swapped")
	if late == null:
		_fail("the late phone never joined")
	if fails > 0:
		print("NET_MIRROR_FAIL %d mismatches" % fails)
		quit(1)
		return
	print("NET_MIRROR_PASS")
	quit(0)

static func _eq(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b

func _compare(srv, m, who: String) -> void:
	var at := "%s t=%.2f" % [who, srv.time]
	if m.units.size() != srv.units.size():
		_fail("%s: %d units, server %d" % [at, m.units.size(), srv.units.size()])
		return
	for i in srv.units.size():
		var su: Dictionary = srv.units[i]
		var mu: Dictionary = m.units[i]
		if str(su.id) != str(mu.id):
			_fail("%s: unit %d is %s, server %s" % [at, i, mu.id, su.id])
			return
		var id := str(su.id)
		if m.by_id.get(id) != mu:
			_fail("%s: by_id of %s" % [at, id])
		var hp := float(su.hp)
		if absf(float(mu.hp) - (ceilf(hp) if hp > 0.0 else 0.0)) > 0.001:
			_fail("%s: %s hp %.2f, server %.2f" % [at, id, mu.hp, hp])
		var to: Vector2 = mu.get("net_to", mu.pos)
		if to.distance_to(su.pos) > 0.008:
			_fail("%s: %s at %s, server %s" % [at, id, str(to), str(su.pos)])
		if absf(angle_difference(float(mu.face), float(su.face))) > 0.002:
			_fail("%s: %s facing %.3f, server %.3f" % [at, id, mu.face, su.face])
		if str(mu.state) != str(su.state):
			_fail("%s: %s %s, server %s" % [at, id, mu.state, su.state])
		for k in ["stun", "cd_ability"]:
			if absf(float(mu[k]) - float(su[k])) > 0.006:
				_fail("%s: %s %s %.3f, server %.3f" % [at, id, k, mu[k], su[k]])
		if bool(su.get("hero", false)):
			if absf(float(mu.get("gold", -1.0)) - round(float(su.gold))) > 0.51:
				_fail("%s: %s gold %.1f, server %.1f" % [at, id, mu.get("gold", -1.0), su.gold])
			for k in ["cd_w", "cd_e", "ult_cd", "ward_ch"]:
				if absf(float(mu.get(k, -1.0)) - float(su.get(k, 0.0))) > 0.006:
					_fail("%s: %s %s %.3f, server %.3f" % [at, id, k, mu.get(k, -1.0), su.get(k, 0.0)])
		for k in su:
			if Net.NO_SYNC.has(k) or Net.FAST_KEYS.has(k):
				continue
			if not mu.has(k) or not _eq(mu[k], su[k]):
				_fail("%s: %s.%s = %s, server %s" % [at, id, k, str(mu.get(k, "<none>")), str(su[k])])
		for k in mu:
			if not su.has(k) and not Net._client_key(str(k)):
				_fail("%s: %s keeps %s (%s), the server's lost it" % [at, id, k, str(mu[k])])
	for pair in Net._objs(srv):
		var pre: String = pair[0]
		var mlist: Array = []
		for mp in Net._objs(m):
			if mp[0] == pre:
				mlist = mp[1]
		var slist: Array = pair[1]
		if mlist.size() != slist.size():
			_fail("%s: %d %s, server %d" % [at, mlist.size(), pre, slist.size()])
			continue
		for j in slist.size():
			var so: Dictionary = slist[j]
			var mo: Dictionary = mlist[j]
			for k in so:
				if Net.OBJ_SKIP[pre].has(k):
					continue
				if not mo.has(k) or not _eq(mo[k], so[k]):
					_fail("%s: %s:%d.%s = %s, server %s" % [at, pre, j, k, str(mo.get(k, "<none>")), str(so[k])])
			for k in mo:
				if not so.has(k) and not Net.OBJ_SKIP[pre].has(k):
					_fail("%s: %s:%d keeps %s" % [at, pre, j, k])
	var sb := Net._blobs(srv)
	var mb := Net._blobs(m)
	for k in sb:
		if not _eq(mb.get(k), sb[k]):
			_fail("%s: %s = %s, server %s" % [at, k, str(mb.get(k)), str(sb[k])])
	var sp := {}
	for p in srv.projectiles:
		sp[int(p.id) % 65536] = p
	var live := 0
	for p in m.projectiles:
		if bool(p.get("ghost", false)):
			continue
		live += 1
		var s: Dictionary = sp.get(int(p.id) % 65536, {})
		if s.is_empty():
			_fail("%s: projectile %d not on the server" % [at, p.id])
		elif str(s.kind) != str(p.kind) or bool(s.get("big", false)) != bool(p.get("big", false)) or (p.net_to as Vector2).distance_to(s.pos) > 0.008:
			_fail("%s: projectile %d %s/%s, server %s/%s" % [at, p.id, p.kind, str(p.net_to), s.kind, str(s.pos)])
	if live != srv.projectiles.size():
		_fail("%s: %d projectiles, server %d" % [at, live, srv.projectiles.size()])
	if m.time != srv.time or m.score != srv.score or m.kills != srv.kills or m.ended != srv.ended:
		_fail("%s: time/score/kills/ended" % at)

func _compare_fog(srv, m) -> void:
	# the phone's fog from what it was sent (its units drawn where the snapshot put them) against the server's
	for u in m.units:
		u.pos = u.get("net_to", u.pos)
	srv.moba.vision._update()
	m.moba.vision._update()
	for t in 2:
		var a: Dictionary = srv.moba.vision.seen[t]
		var b: Dictionary = m.moba.vision.seen[t]
		var srcs: Array = srv.moba.vision.sources(t)
		for k in a.keys() + b.keys():
			if a.has(k) == b.has(k):
				continue
			# 0.31.181: a unit right on the edge of a sight (within the snapshot's centimetre) may fall either side of it
			# on the phone -- one of the monsters, 14.998 m from a hero's 15 m sight on the server, 15.001 on the phone
			var up: Vector2 = srv.by_id.get(k, {}).get("pos", Vector2.INF)
			if srcs.any(func(sr): return absf((sr[0] as Vector2).distance_to(up) - float(sr[1])) < EDGE):
				continue
			_fail("fog t=%.1f side %d: %s seen by the phone %s, by the server %s" % [srv.time, t, k, str(b.has(k)), str(a.has(k))])
