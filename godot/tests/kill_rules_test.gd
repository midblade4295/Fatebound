extends SceneTree
# 0.31.180 (Kevin: League's kill rules for the 5v5): moba.gd's kill credit, assists, multi-kill windows, FIRST BLOOD,
# ACE and bounties, and the "kb" / "ace" events the banners are drawn from.
#  - the kill: the last enemy hero to touch him within 15 s (a tower finishing him: still his) -- not after 15 s;
#  - assists: hurt him or held him (a slow, a stun) in the last 10 s, or healed the killer then -- not 12 s ago, not
#    for standing near;
#  - multi-kills 10 s apart (DOUBLE, TRIPLE), a gap of 11 s starts again; after a QUADRA a PENTA within 30 s -- not if
#    one of the enemy came back first;
#  - FIRST BLOOD on the match's first kill only; ACE when the whole side is down;
#  - bounty: a quarter of kill and assist gold, a twentieth of minions' and monsters'; shown from 150 in steps of 50;
#    paid up to 700 on top of the kill's 300 (the rest carried to his next life); a SHUTDOWN banner when the board
#    showed one; a side well behind in gold has its bounties devalued (20 % to 80 %).
#   godot --headless --path godot -s res://tests/kill_rules_test.gd
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Moba = preload("res://scripts/siege/moba.gd")
var fails := []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

static func _fresh(seed_v := 81):
	var s = Sim.new()
	s.setup(5, seed_v)
	s.setup_moba("knight", seed_v)
	for u in s.units:
		if bool(u.get("hero", false)):
			u.pos = Vector2(-60.0 + float(s.units.find(u)) * 6.0, 120.0 if int(u.team) == 0 else -120.0)
	return s

static func _tower(s, team: int) -> Dictionary:
	return {"id":"tower0", "team":team, "pos":Vector2.ZERO, "state":"idle"}

# src finishes dst (a big hit)
static func _finish(s, src: Dictionary, dst: Dictionary) -> Array:
	s.drain_events()
	dst.hp = 1.0
	s._damage(src, dst, 9999.0)
	return s.drain_events()

static func _ev(evs: Array, k: String) -> Dictionary:
	for e in evs:
		if str(e.get("k", "")) == k:
			return e
	return {}

func _init() -> void:
	# ---- kill credit
	var s = _fresh()
	var h: Dictionary = s.by_id["b1"]
	var v: Dictionary = s.by_id["r1"]
	s._damage(h, v, 5.0)
	s.time += 5.0
	var g0 := float(h.gold)
	var evs := _finish(s, _tower(s, 0), v)
	var kb := _ev(evs, "kb")
	check(int(h.kills) == 1 and str(kb.get("by", "")) == "b1" and is_equal_approx(float(h.gold) - g0, 300.0),
		"a tower finishes him 5 s after b1's hit: b1's kill and its 300 gold (+%.0f)" % (float(h.gold) - g0))
	check(str(kb.get("kind", "")) == "first_blood", "the match's first: FIRST BLOOD")
	var v2: Dictionary = s.by_id["r2"]
	s._damage(h, v2, 5.0)
	s.time += 16.0
	var k0 := int(h.kills)
	var kills0 := int(s.kills[0])
	evs = _finish(s, _tower(s, 0), v2)
	check(int(h.kills) == k0 and _ev(evs, "kb").is_empty() and int(s.kills[0]) == kills0 + 1,
		"16 s after: no one's kill (no banner; the side's count still)")
	# ---- assists
	s = _fresh(82)
	var killer: Dictionary = s.by_id["b1"]
	v = s.by_id["r1"]
	var a_hit: Dictionary = s.by_id["b2"]
	var a_old: Dictionary = s.by_id["b3"]
	var a_cc: Dictionary = s.by_id["b4"]
	var a_heal: Dictionary = s.by_id["you"]
	s._damage(a_old, v, 2.0)
	s.time += 4.0
	s._damage(a_hit, v, 2.0)
	s.moba.kits._slow(v, 0.3, 1.0, a_cc)
	killer.hp = float(killer.max_hp) * 0.5
	s._heal(a_heal, killer, 10.0)
	s.time += 8.0                                   # (a_old's hit 12 s ago; the others 8)
	for u in [a_hit, a_old, a_cc, a_heal]:
		u.assists = 0
	_finish(s, killer, v)
	check(int(a_hit.get("assists", 0)) == 1 and int(a_cc.get("assists", 0)) == 1 and int(a_heal.get("assists", 0)) == 1,
		"assists: a hit 8 s ago, a slow, a heal on the killer")
	check(int(a_old.get("assists", 0)) == 0, "no assist for a hit 12 s ago")
	var near: Dictionary = s.by_id["b2"]
	var v3: Dictionary = s.by_id["r3"]
	near.assists = 0
	near.pos = (v3.pos as Vector2) + Vector2(1.5, 0)
	s.time += 30.0
	_finish(s, killer, v3)
	check(int(near.get("assists", 0)) == 0, "none for standing by")
	# ---- multi-kills
	s = _fresh(83)
	killer = s.by_id["b1"]
	var ns := []
	for i in 3:
		evs = _finish(s, killer, s.by_id["r%d" % i])
		ns.append(int(_ev(evs, "kb").get("n", 0)))
		s.time += 8.0
	check(ns == [1, 2, 3] and str(_ev(evs, "kb").kind) == "multi", "kills 8 s apart: 1, DOUBLE, TRIPLE (%s)" % str(ns))
	s.time += 3.5                                   # (11.5 s since the last)
	evs = _finish(s, killer, s.by_id["r3"])
	check(int(_ev(evs, "kb").n) == 1, "11.5 s after: a new chain")
	s = _fresh(84)
	killer = s.by_id["b1"]
	for i in 4:
		evs = _finish(s, killer, s.by_id["r%d" % i])
		s.time += 5.0
	check(int(_ev(evs, "kb").n) == 4 and _ev(evs, "multikill").get("name", "") == "QUADRA KILL", "four: QUADRA KILL")
	s.time += 20.0                                  # (25 s after the QUADRA)
	evs = _finish(s, killer, s.by_id["r4"])
	check(int(_ev(evs, "kb").n) == 5 and str(_ev(evs, "multikill").get("name", "")) == "PENTAKILL", "the fifth 25 s later: PENTAKILL")
	check(not _ev(evs, "ace").is_empty() and str(_ev(evs, "ace").by) == "b1", "...and the whole side down: ACE")
	s = _fresh(85)
	killer = s.by_id["b1"]
	for i in 4:
		_finish(s, killer, s.by_id["r%d" % i])
		s.time += 2.0
	s._respawn(s.by_id["r0"])                       # (one of them back)
	s.time += 3.0
	evs = _finish(s, killer, s.by_id["r4"])
	check(int(_ev(evs, "kb").n) == 1 and _ev(evs, "ace").is_empty(), "an enemy back first: no PENTA (and no ACE)")
	# ---- bounty
	s = _fresh(86)
	h = s.by_id["r1"]
	s.moba.add_gold(h, 400.0, Vector2.ZERO, "kill")
	s.moba.add_gold(h, 400.0, Vector2.ZERO, "cs")
	s.moba.add_gold(h, 400.0, Vector2.ZERO)
	check(is_equal_approx(float(h.bounty), 120.0), "bounty: 400 kill gold 100, 400 farm 20, 400 else 0 (%.0f)" % float(h.bounty))
	var shows := []
	for b in [149.0, 150.0, 199.0, 260.0, 900.0]:
		h.bounty = b
		shows.append(s.moba.bounty_shown(h))
	check(shows == [0, 150, 150, 250, 700], "shown from 150 in steps of 50, at most 700 (%s)" % str(shows))
	h.bounty = 1000.0
	killer = s.by_id["b1"]
	g0 = float(killer.gold)
	evs = _finish(s, killer, h)
	kb = _ev(evs, "kb")
	check(is_equal_approx(float(killer.gold) - g0, 1000.0) and is_equal_approx(float(h.bounty), 300.0) and int(kb.bounty) == 700,
		"a 1000 bounty: his killer paid 300 + 700, 300 left for his next life (+%.0f, %.0f)" % [float(killer.gold) - g0, float(h.bounty)])
	check(str(kb.kind) in ["shutdown", "first_blood"] and bool(kb.shut), "the banner: SHUTDOWN (the gold on it)")
	var h2: Dictionary = s.by_id["r2"]
	h2.bounty = 400.0
	s.time += 30.0
	evs = _finish(s, killer, h2)
	check(str(_ev(evs, "kb").kind) == "shutdown", "...and a plain kill of one with a bounty: SHUTDOWN")
	# a side behind in gold: its bounties count for less
	s = _fresh(87)
	for hid in s.moba.heroes[0]:
		s.by_id[hid].gold = 3000.0
	for hid in s.moba.heroes[1]:
		s.by_id[hid].gold = 1500.0                 # (red 50 % behind: the most)
	h = s.by_id["r1"]
	h.bounty = 500.0
	var dv: float = s.moba.devalue(1)
	check(is_equal_approx(dv, 0.8) and is_equal_approx(s.moba.devalue(0), 0.0) and s.moba.bounty_shown(h) == 0,
		"red far behind: its bounties at a fifth (devalued %.0f %%), blue's not" % (dv * 100.0))
	for hid in s.moba.heroes[1]:
		s.by_id[hid].gold = 2550.0                 # (15 % behind)
	dv = s.moba.devalue(1)
	check(dv > 0.2 and dv < 0.4, "15 %% behind: devalued %.0f %%" % (dv * 100.0))
	print("KILL_RULES_%s" % ("PASS" if fails.is_empty() else "FAIL %s" % str(fails)))
	quit(0 if fails.is_empty() else 1)
