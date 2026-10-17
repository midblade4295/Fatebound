extends SceneTree
# 0.31.164 (Kevin, for the new map: "Remove them now: 5v5 only"): the 5v5 is the game's match --
#  1. it counts what the rewards and challenges ask for on your hero: minion last hits, jungle camps cleared (whoever
#     finishes one), epic monsters (every hero of the slaying side), towers destroyed (by you or near you), damage to
#     towers and the King (with the gates: "gates");
#  2. the rewards itemise them; the challenges are the 5v5's (no King rescues, fish, gathering or lifts); a saved Siege
#     challenge is swapped in place for a 5v5 one on refresh -- the same on every copy of the profile (the server's too),
#     claimed ones staying claimed; the Siege titles and the Worker's quest aren't shown to earn;
#  3. the server holds a phone's 5v5 numbers to what one match can give (clamp_me);
#  4. a 5v5 played through Profile.apply_match pays and moves the challenges and the class quests.
#   godot --headless --path godot -s res://tests/five_only_test.gd
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Moba = preload("res://scripts/siege/moba.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const EcoAccounts = preload("res://server/eco_accounts.gd")

var fails: Array = []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	# ---- 1. the counts on the hero
	var s = Sim.new()
	s.setup(5, 7)
	s.setup_moba("knight", 7)
	var m = s.moba
	var me: Dictionary = s.by_id["you"]
	while s.time < Moba.WAVE_FIRST + 1.0:
		s.step()
	var foe := {}
	for u in s.units:
		if bool(u.get("minion", false)) and int(u.team) == 1 and s.alive(u):
			foe = u
			break
	check(not foe.is_empty(), "a red minion out")
	foe.pos = (me.pos as Vector2) + Vector2(1.0, 0.0)
	s._kill(me, foe)
	check(int(me.get("lh", 0)) == 1, "a minion you finish is a last hit (%d)" % int(me.get("lh", 0)))
	# a camp: kill all its monsters, the last one by you
	var camp: Dictionary = m.camps[0]
	if not bool(camp.alive):
		m._spawn_camp(camp)
	var live: Array = m.camp_live(camp)
	check(not live.is_empty(), "a camp up")
	for i in live.size():
		s._kill(me if i == live.size() - 1 else {}, live[i])
	check(int(me.get("camps", 0)) == 1 and not bool(camp.alive), "a camp you finish counts (%d)" % int(me.get("camps", 0)))
	# the Bone Lord: every hero of the side
	var lord: Dictionary = m._lord_unit()
	if lord.is_empty():
		for c in m.camps:
			if str(c.kind) == "lord":
				m._spawn_camp(c)
		lord = m._lord_unit()
	check(not lord.is_empty(), "the Bone Lord up")
	var mates := 0
	for hid in m.heroes[0]:
		mates += int(s.by_id[hid].get("epics", 0))
	s._kill(me, lord)
	var mates2 := 0
	for hid in m.heroes[0]:
		mates2 += int(s.by_id[hid].get("epics", 0))
	check(mates2 - mates == 5 and int(me.get("epics", 0)) == 1, "the Lord counts for all five of the side (+%d)" % (mates2 - mates))
	# a tower: damage counts as gate damage; destroyed near you
	var tw: Dictionary = {}
	for t in m.towers:
		if int(t.team) == 1 and int(t.tier) == 1:
			tw = t
			break
	me.pos = (tw.p as Vector2) + Vector2(0.0, 4.0)
	var mn := {}
	for u in s.units:
		if bool(u.get("minion", false)) and int(u.team) == 0 and s.alive(u):
			mn = u
			break
	if not mn.is_empty():
		mn.pos = (tw.p as Vector2) + Vector2(2.0, 3.0)        # (no backdoor protection)
	var g0 := float(me.gate_dmg)
	m.hit_tower(me, int(tw.id), 100.0)
	check(float(me.gate_dmg) > g0, "damage to a tower counts as gate damage (+%.0f)" % (float(me.gate_dmg) - g0))
	m.hit_tower(me, int(tw.id), 1.0e6)
	check(bool(tw.dead) and int(me.get("towers", 0)) == 1, "a tower destroyed by you counts (%d)" % int(me.get("towers", 0)))
	# ---- 2. rewards and challenges
	var st := Eco.match_stats(me, true, false)
	check(int(st.lh) == 1 and int(st.camps) == 1 and int(st.epics) == 1 and int(st.towers) == 1, "match_stats carries them: %s" % str([st.lh, st.camps, st.epics, st.towers]))
	var r := Eco.match_rewards(st, true, false, false, false)
	var labels: Array = (r.lines as Array).map(func(l): return str(l.label))
	check(labels.has("Towers destroyed x1") and labels.has("Jungle camps x1") and labels.has("Minion last hits x1") and labels.has("Epic monsters x1"),
		"the rewards itemise them: %s" % str(labels))
	var siege_words := false
	for id in Eco.CHALLENGES:
		var tx := str(Eco.CHALLENGES[id].text)
		siege_words = siege_words or tx.contains("Rescue") or tx.contains("fish") or tx.contains("Gather") or tx.contains("lift")
	check(not siege_words and Eco.CHALLENGES.has("tower2") and Eco.CHALLENGES.has("epic1"), "the challenges are the 5v5's")
	# a saved profile with Siege challenges
	var base := "user://five-%d" % Time.get_ticks_usec()
	var p := Profile.new(base + "-a.json", base + "-none.json")
	p.load_or_create()
	p.d.challenges.daily = [{"id":"rescue1", "progress":1, "claimed":true}, {"id":"win1", "progress":0, "claimed":false},
		{"id":"feed3", "progress":2, "claimed":false}]
	p.d.challenges.weekly = [{"id":"w_rescue4", "progress":0, "claimed":false}, {"id":"w_win5", "progress":3, "claimed":false},
		{"id":"w_feed12", "progress":0, "claimed":false}]
	var copy: Dictionary = p.d.challenges.duplicate(true)
	p.refresh()
	var d: Array = p.d.challenges.daily
	var w: Array = p.d.challenges.weekly
	var all_ok := true
	for c in d + w:
		all_ok = all_ok and Eco.CHALLENGES.has(str(c.id))
	check(all_ok and d.size() == 3 and w.size() == 3, "Siege challenges swapped for 5v5 ones: %s / %s" % [str(d.map(func(c): return c.id)), str(w.map(func(c): return c.id))])
	check(str(d[1].id) == "win1" and str(w[1].id) == "w_win5" and int(w[1].progress) == 3, "the others kept in their slots, with their progress")
	check(bool(d[0].claimed) and not bool(d[2].claimed), "a claimed one stays claimed")
	var ids := d.map(func(c): return c.id)
	check(ids.size() == 3 and ids[0] != ids[2] and ids[0] != "win1" and ids[2] != "win1", "no repeats")
	# the same swap on another copy (the server's)
	var p2 := Profile.new(base + "-b.json", base + "-none.json")
	p2.load_or_create()
	p2.d.challenges = copy
	p2.now_override = p.now_override
	p2.refresh()
	check(p2.d.challenges.daily.map(func(c): return c.id) == ids and p2.d.challenges.weekly.map(func(c): return c.id) == w.map(func(c): return c.id),
		"the same swap on every copy of the profile")
	var shown := 0
	for id in Eco.TITLE_GOALS:
		if Eco.retired(Eco.TITLE_GOALS[id]):
			shown += 1
	check(shown == 9 and Eco.retired(Eco.TITLE_GOALS.title_fishmonger) and not Eco.retired(Eco.TITLE_GOALS.title_gatebreaker),
		"Siege's titles retired (%d); Gatebreaker earned on towers and gates now" % shown)
	check(not Eco.HERO_CLASSES.has("worker") and str(Eco.QUESTS.knight.steps[1].stat) == "towers" and str(Eco.QUESTS.mage.steps[1].stat) == "camps",
		"no Worker hero; the quests' King steps ask for towers and camps")
	# ---- 3. the server's clamp
	var cl: Dictionary = EcoAccounts.clamp_me({"towers":99, "camps":5, "lh":9999, "epics":2, "cls":"knight",
		"q":{"knight":{"t":600.0, "towers":99, "lh":40, "camps":2, "epics":1}}}, 900)
	check(int(cl.towers) == 12 and int(cl.camps) == 5 and int(cl.lh) == 300 and int(cl.epics) == 2, "clamp_me caps the 5v5 numbers: %s" % str([cl.towers, cl.camps, cl.lh, cl.epics]))
	check(int(cl.q.knight.towers) == 12 and int(cl.q.knight.lh) == 40 and int(cl.q.knight.camps) == 2, "...and the class quest's")
	# ---- 4. a 5v5 through apply_match
	var p3 := Profile.new(base + "-c.json", base + "-none.json")
	p3.load_or_create()
	p3.d.challenges.daily = [{"id":"tower2", "progress":0, "claimed":false}, {"id":"camps4", "progress":0, "claimed":false},
		{"id":"lh60", "progress":0, "claimed":false}]
	p3.d.challenges.day = Eco.day_key(p3.now())
	var gold0 := int(p3.d.gold)
	var mine := {"cls":"knight", "kills":2, "gate_dmg":800.0, "towers":2, "camps":3, "lh":45, "epics":1,
		"q":{"knight":{"t":600.0, "kills":2, "towers":2, "camps":3, "lh":45, "epics":1}}}
	var out: Dictionary = p3.apply_match(mine, true, false, false)
	check(int(p3.d.gold) > gold0 and int(p3.d.stats.get("towers", 0)) == 2 and int(p3.d.stats.get("lh", 0)) == 45, "a 5v5 pays (+%d gold) and keeps its numbers" % (int(p3.d.gold) - gold0))
	var prog: Array = p3.d.challenges.daily.map(func(c): return int(c.progress))
	check(prog == [2, 3, 45], "the challenges move: %s" % str(prog))
	check(int(p3.d.stats.get("q_knight_towers", 0)) == 2, "the Knight's quest counts his towers")
	print("FIVE_ONLY_PASS" if fails.is_empty() else "FIVE_ONLY_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
