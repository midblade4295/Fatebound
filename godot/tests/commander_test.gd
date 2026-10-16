extends SceneTree
# 0.31.153 COMMANDER (the prototype; scripts/meta/cards.gd, siege_sim.gd's COMMANDER section):
#  1. the start: each side's hero out, its 15 soldiers in the barracks, a hand of 4 and 4 waiting, 5 points;
#  2. a card: its points, its squad out of the castle in its hat and role, the next card in its place, it at the back;
#     not enough points / nobody in the barracks: refused, and why;
#  3. a soldier who falls drops his hat and is back in the barracks CMD_RETURN s later (not before), hidden from then;
#     the hero comes back by himself as before;
#  4. the points fill (twice as fast near the end) up to 10;
#  5. the enemy commander plays: Workers first, an army out within the first minute;
#  6. whole matches, AI against AI: cards played, fights, the workshop bought from (MATCHES=n for more, PRINT=1 for stats).
#   godot --headless --path godot -s res://tests/commander_test.gd
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Cards = preload("res://scripts/meta/cards.gd")

var fails: Array = []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _new(seed_value: int, ai: Array) -> Object:
	var s = Sim.new()
	s.setup(16, seed_value)
	s.setup_commander([Cards.DEFAULT_DECK, Cards.ai_deck(seed_value)], ai)
	return s

func _init() -> void:
	# --- 1. the start
	var s = _new(1234, [false, true])
	var heroes: Array = s.units.filter(func(u): return bool(u.get("hero", false)))
	check(heroes.size() == 2 and s.by_id["you"].get("hero", false) and s.alive(s.by_id["you"]) and s.alive(s.by_id["r0"]),
		"each side's hero is out (you, and the enemy commander's r0)")
	check(s.cmd_ready(0).size() == 15 and s.cmd_ready(1).size() == 15 and s.cmd_army(0) == 0 and s.cmd_soldiers(0) == 15,
		"15 soldiers a side, all in the barracks")
	check((s.cmd[0].hand as Array).size() == 4 and (s.cmd[0].queue as Array).size() == 4 and float(s.cmd[0].pts) == Sim.CMD_START
		and s.match_time == Sim.CMD_MATCH_TIME, "a hand of 4, 4 waiting, %d points, an %d-minute match" % [int(Sim.CMD_START), int(Sim.CMD_MATCH_TIME / 60.0)])
	var all: Array = (s.cmd[0].hand as Array) + (s.cmd[0].queue as Array)
	all.sort()
	var dd: Array = Cards.DEFAULT_DECK.duplicate()
	dd.sort()
	check(all == dd, "the hand and the queue are the deck")
	# --- 2. a card
	s.cmd[0].hand[0] = "knights"
	s.cmd[0].pts = 5.0
	var nxt := str(s.cmd[0].queue[0])
	check(s.cmd_why(0, 0) == "" and s.play_card(0, 0), "KNIGHTS played")
	var kn: Array = s.units.filter(func(u): return int(u.team) == 0 and s.alive(u) and not u.get("hero", false))
	check(kn.size() == 2 and kn.all(func(u): return u.cls == "knight" and not u.up and u.role == "escort" and not u.has("reserve") and Sim.in_castle(u.pos, 0)),
		"two Knights out of our castle, escorts")
	check(is_equal_approx(float(s.cmd[0].pts), 2.0) and str(s.cmd[0].hand[0]) == nxt and str(s.cmd[0].queue[-1]) == "knights",
		"3 points spent; the next card in its place; Knights at the back of the deck")
	var evs: Array = s.drain_events().filter(func(e): return e.k == "card")
	check(evs.size() == 1 and str(evs[0].card) == "knights" and (evs[0].ids as Array).size() == 2, "a \"card\" event with the squad")
	s.cmd[0].hand[1] = "archmage"
	check(s.cmd_why(0, 1) == "points" and not s.play_card(0, 1), "the Archmage (5) with 2 points: refused (points)")
	s.cmd[0].pts = 10.0
	check(s.play_card(0, 1), "...with 10: played")
	var am: Array = s.units.filter(func(u): return int(u.team) == 0 and s.alive(u) and u.cls == "mage" and u.up)
	check(am.size() == 1 and am[0].role == "defend" and is_equal_approx(float(am[0].hp), float(s.stat(am[0], "hp"))), "one Archmage, a defender, full health")
	# --- 3. falling
	var k: Dictionary = kn[0]
	s._kill({}, k)
	check(k.state == "dead" and bool(k.get("reserve", false)) and k.respawn_at == INF and k.cls == "villager"
		and s.hats.any(func(h): return h.cls == "knight"), "a Knight falls: his hat on the ground, he's for the barracks")
	check(not s.cmd_ready(0).has(k) and s.cmd_fallen(k), "...not back yet")
	for i in int((Sim.CMD_RETURN + 0.5) / Sim.TICK):
		s.step()
	check(s.cmd_ready(0).has(k) and k.state == "dead", "...back in the barracks %d s later (and stays there: no respawn)" % int(Sim.CMD_RETURN))
	var me: Dictionary = s.by_id["you"]
	s._kill({}, me)
	check(me.respawn_at < INF and not me.has("reserve"), "the hero comes back by himself")
	# all out: the army is full
	s.cmd[0].pts = 10.0
	var guard := 0
	while not s.cmd_ready(0).is_empty() and guard < 30:
		s.cmd[0].pts = 10.0
		s.cmd[0].hand[0] = "peasants"
		s.play_card(0, 0)
		guard += 1
	s.cmd[0].pts = 10.0
	check(s.cmd_army(0) == 15 and s.cmd_why(0, 0) == "army" and not s.play_card(0, 0), "15 out: the next card waits (army)")
	var vill: Array = s.units.filter(func(u): return int(u.team) == 0 and s.alive(u) and u.cls == "villager" and not u.get("hero", false))
	for i in 90:
		s.step()
	check(vill.all(func(u): return u.cls == "villager" or not s.alive(u)), "Peasants take no hats from the stands")
	# --- 4. the points
	var s2 = _new(99, [false, false])
	s2.cmd[0].pts = 0.0
	for i in int(2.8 / Sim.TICK) + 1:
		s2.step()
	check(absf(float(s2.cmd[0].pts) - 1.0) < 0.05, "a point every 2.8 s")
	s2.time = s2.match_time - Sim.CMD_DOUBLE + 1.0
	s2.cmd[0].pts = 0.0
	for i in int(1.4 / Sim.TICK) + 1:
		s2.step()
	check(absf(float(s2.cmd[0].pts) - 1.0) < 0.05, "twice as fast in the last 2 minutes")
	s2.cmd[0].pts = 9.9
	for i in 60:
		s2.step()
	check(float(s2.cmd[0].pts) == Sim.CMD_MAX, "no more than 10")
	# --- 5. the enemy commander
	var s3 = _new(5, [false, true])
	var first := ""
	for i in int(60.0 / Sim.TICK):
		s3.step()
		for e in s3.drain_events():
			if e.k == "card" and int(e.team) == 1 and first == "":
				first = str(e.card)
	check(int(s3.cmd[1].played) >= 4 and s3.cmd_army(1) >= 6, "the enemy commander plays: %d cards, %d soldiers out in a minute" % [int(s3.cmd[1].played), s3.cmd_army(1)])
	check(s3.class_count(1, "worker") >= 1, "...Workers among them (first card: %s)" % first)
	check(int(s3.cmd[0].played) == 0 and s3.cmd_army(0) == 0, "our side plays nothing by itself")
	# --- 6. whole matches, AI against AI
	var n := int(OS.get_environment("MATCHES")) if OS.has_environment("MATCHES") else 1
	for m in n:
		var sm = _new(1000 + m, [true, true])
		sm.by_id["you"].bot = true                # (the hero plays himself too)
		var kills0 := 0
		var t0 := Time.get_ticks_msec()
		while not sm.ended:
			sm.step()
			sm.drain_events()
		var played: Array = [int(sm.cmd[0].played), int(sm.cmd[1].played)]
		var ups := 0
		for t in 2:
			for k2 in sm.levels[t]:
				ups += int(sm.levels[t][k2])
		if OS.has_environment("PRINT") or m == 0:
			print("  match %d: %.0f s, winner %d (%s), score %s, kills %s, cards %s, upgrades %d, gathered %d, %d ms" % [m, sm.time, sm.winner,
				sm.end_reason, str(sm.score), str(sm.kills), str(played), ups, int(sm.units.reduce(func(a, u): return a + int(u.gathered), 0)),
				Time.get_ticks_msec() - t0])
		if m == 0:
			check(played[0] >= 20 and played[1] >= 20 and sm.kills[0] + sm.kills[1] >= 30 and ups >= 2,
				"a whole match: both commanders play (%s cards), they fight (%s), the workshop sells (%d upgrades)" % [str(played), str(sm.kills), ups])
	print("COMMANDER_PASS" if fails.is_empty() else "COMMANDER_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
