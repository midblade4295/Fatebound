extends SceneTree
# 0.31.167 5V5 KITS AND ROLES (scripts/siege/moba_kits.gd), Kevin: "We need more characters and class roles like League
# of Legends and heroes of the storm have" -> League's six roles, three abilities and the ultimate:
#  1. every hero has a role -- two of the twelve each of TANK, FIGHTER, ASSASSIN, MAGE, MARKSMAN, SUPPORT -- and a kit:
#     Q (his class's ability), W and E;
#  2. W comes at level 2, E at 3; a cast goes on its recharge (abilities' speed counts);
#  3. each of the 24 W/E does what it says, on a scene: a hero of each against an enemy hero 3 m off, a hurt ally beside;
#  4. shields take hits first, slows slow, marks and curses make hits land harder, poison ticks, a fallen hero keeps
#     nothing;
#  5. whole bot matches: the bots cast their W and E.
#   godot --headless --path godot -s res://tests/moba_kits_test.gd
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Moba = preload("res://scripts/siege/moba.gd")
const Kits = preload("res://scripts/siege/moba_kits.gd")

const P0 := Vector2(0.0, 40.0)              # open ground (the middle lane; no brush near: they see each other)

var fails: Array = []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _new(hero: String, seed_value: int) -> Object:
	var s = Sim.new()
	s.setup(5, seed_value)
	s.setup_moba(hero, seed_value)
	return s

func _run(s, secs: float) -> Array:
	var evs := []
	for i in int(secs / Sim.TICK):
		s.step()
		evs.append_array(s.drain_events())
	return evs

func _quiet(s) -> void:
	s.moba.wave_at = INF
	for c in s.moba.camps:
		c.next = INF
	for tw in s.moba.towers:
		tw.dead = true
	for u in s.units.duplicate():
		if bool(u.get("minion", false)) or u.has("mon"):
			s.units.erase(u)
			s.by_id.erase(u.id)
	for u in s.units:
		if bool(u.get("hero", false)):
			u.bot = false
			u.pos = Sim.spawn(int(u.team))
			u.move = Vector2.ZERO

func _to_level(s, u: Dictionary, lv: int) -> void:
	while int(u.level) < lv:
		s.moba.add_xp(u, s.moba.need(int(u.level)))
	u.picks = []

func _init() -> void:
	_roles()
	_unlocks()
	_each()
	_effects()
	_bots()
	print("MOBA_KITS_PASS" if fails.is_empty() else "MOBA_KITS_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)

# ---------------------------------------------------------------- 1. roles
func _roles() -> void:
	var per := {}
	var kits_ok := true
	for hid in Moba.HERO_ORDER:
		var r := Kits.role_of(str(hid))
		per[r] = int(per.get(r, 0)) + 1
		kits_ok = kits_ok and not Kits.kit(str(hid), "q").is_empty() and not Kits.kit(str(hid), "w").is_empty() \
			and not Kits.kit(str(hid), "e").is_empty() and Moba.ULTS.has(str(hid))
	check(Kits.ROLE_ORDER.all(func(r): return int(per.get(r, 0)) == 2) and per.size() == 6,
		"every hero a role, two of each of the six (%s)" % str(per))
	check(kits_ok, "...and a kit: Q, W, E and the ultimate")
	# the draft: League's five places, filled by role; you in your role's place
	var s = _new("mage", 61)
	var ok := true
	for t in 2:
		var posts := {}
		for hid in s.moba.heroes[t]:
			var u: Dictionary = s.by_id[hid]
			posts[str(u.post)] = u
			var want: Array = Moba.POST_ROLES[str(u.post)]
			ok = ok and (want.has(Kits.role_of(str(u.hid))) or (t == 0 and hid == "you"))
			ok = ok and (hid == "you" or int(u.lane) == int(Moba.POST_LANE[str(u.post)]))
		ok = ok and posts.size() == 5
	var me: Dictionary = s.by_id["you"]
	check(ok and str(me.post) == "mid" and int(me.lane) == -1, "each side drafted by role: top, jungle, mid, bottom and support (you a Mage: mid)")
	var duo := true
	for t in 2:
		var bots: Array = (s.moba.heroes[t] as Array).map(func(h): return s.by_id[h]).filter(func(u): return str(u.post) in ["bot", "support"])
		duo = duo and bots.size() == 2 and bots.all(func(u): return int(u.lane) == 2)
	check(duo, "...the marksman and the support share the east lane, on both sides")
	for hid in ["knight", "rogue", "ranger", "priest"]:
		var d: Array = s.moba.draft(hid)
		check(str(d[0][0]) == hid and str(d[0][1]) == str(Moba.ROLE_POST[Kits.role_of(hid)]) and d.size() == 5,
			"you a %s: %s" % [hid.to_upper(), str(d[0][1])])

# ---------------------------------------------------------------- 2. unlocks and recharges
func _scene(hero: String, lv := 3) -> Array:
	var s = _new(hero, 51)
	_quiet(s)
	var me: Dictionary = s.by_id["you"]
	_to_level(s, me, lv)
	me.pos = P0
	me.face = s.angle_of(Vector2(0, 1))
	var foe: Dictionary = s.by_id["r1"]
	foe.pos = P0 + Vector2(0, 3)
	foe.face = s.angle_of(Vector2(0, -1))
	foe.max_hp = 50000.0
	foe.hp = 50000.0
	var mate: Dictionary = s.by_id["b1"]
	mate.pos = P0 + Vector2(1.5, 0)
	mate.hp = float(mate.max_hp) * 0.4
	_run(s, 0.35)                                   # (the fog of war catches up: they see each other)
	return [s, me, foe, mate]

func _unlocks() -> void:
	var sc := _scene("barbarian", 1)
	var s = sc[0]
	var me: Dictionary = sc[1]
	check(not s.act("you", "spell", "w") and not s.act("you", "spell", "e"), "level 1: no W, no E")
	_to_level(s, me, 2)
	check(s.act("you", "spell", "w") and float(me.cd_w) > 0.0, "level 2: W (and its recharge)")
	_run(s, 1.0)
	check(not s.act("you", "spell", "w"), "...not again while it recharges")
	check(s.act("you", "spell", "e") == false, "...E still locked")
	_to_level(s, me, 3)
	check(s.act("you", "spell", "e") and float(me.cd_e) > 0.0, "level 3: E")
	var cd0 := float(me.cd_w)
	_run(s, 1.0)
	check(absf(cd0 - float(me.cd_w) - 1.0) < 0.1, "W recharges a second a second (%.2f)" % (cd0 - float(me.cd_w)))
	me["m_cdr"] = 1.5
	cd0 = float(me.cd_w)
	_run(s, 1.0)
	check(absf(cd0 - float(me.cd_w) - 1.5) < 0.1, "...faster with ability speed (%.2f)" % (cd0 - float(me.cd_w)))

# ---------------------------------------------------------------- 3. every W and E
func _cast(hero: String, slot: String) -> Array:
	var sc := _scene(hero)
	var s = sc[0]
	var before := {"p":sc[1].pos, "f_hp":float(sc[2].hp), "m_hp":float(sc[3].hp)}
	var ok: bool = s.act("you", "spell", slot)
	var evs: Array = s.drain_events()
	sc.append(ok)
	sc.append(evs.filter(func(e): return e.k == "spell"))
	sc.append(before)
	return sc

func _each() -> void:
	for hid in Moba.HERO_ORDER:
		for slot in ["w", "e"]:
			var k := Kits.kit(str(hid), slot)
			if bool(k.get("hold", false)):
				continue
			var sc := _cast(str(hid), slot)
			var s = sc[0]
			var me: Dictionary = sc[1]
			var foe: Dictionary = sc[2]
			var mate: Dictionary = sc[3]
			var cast_ok: bool = sc[4]
			var spells: Array = sc[5]
			var p0: Vector2 = sc[6].p
			var f_hp := float(sc[6].f_hp)
			var m_hp := float(sc[6].m_hp)
			var seen := {"stun":false, "slow":false}
			for i in int(1.5 / Sim.TICK):
				s.step()
				s.drain_events()
				seen.stun = seen.stun or float(foe.stun) > 0.0
				seen.slow = seen.slow or s.time < float(foe.get("slow_until", -1.0))
			var ok := false
			var why := ""
			match str(k.id):
				"bash":
					ok = seen.stun and float(foe.hp) < f_hp and (me.pos as Vector2).distance_to(p0) > 1.0
				"rally":
					ok = float(me.get("shield", 0.0)) > 0.0 and float(mate.get("shield", 0.0)) > 0.0
				"consecrate":
					ok = seen.slow and float(foe.hp) < f_hp and float(mate.hp) > m_hp
				"leap":
					ok = (me.pos as Vector2).distance_to(foe.pos) < 2.0 and seen.slow and float(foe.hp) < f_hp
				"bloodlust":
					ok = s.time < float(me.get("ls_until", -1.0)) and s.moba.kits.speed_mult(me) > 1.1
				"charge":
					ok = float(foe.hp) < f_hp and (me.pos as Vector2).distance_to(p0) > 5.0
				"frenzy":
					ok = s.time < float(me.get("as_until", -1.0)) and s.moba.kits.swing_mult(me) < 0.8
				"caltrops", "pillar", "knives", "curse", "dazzle", "snare":
					var want_slow: bool = str(k.id) in ["caltrops", "knives", "curse"]
					var want_stun: bool = str(k.id) in ["pillar", "dazzle", "snare"]
					ok = (not want_slow or seen.slow) and (not want_stun or seen.stun) \
						and (str(k.id) in ["curse", "dazzle"] or float(foe.hp) < f_hp)
				"poison":
					ok = int(me.get("poison_n", 0)) == int(k.n)
				"shadowstep":
					ok = (me.pos as Vector2).distance_to(foe.pos) < 1.8 and float(foe.hp) < f_hp
				"tumble":
					ok = (me.pos as Vector2).distance_to(p0) > 3.0 and int(me.get("emp_n", 0)) == 1
				"trap":
					ok = s.moba.kits.traps.size() == 1
				"mark":
					ok = s.time < float(foe.get("amp_until", -1.0)) and s.time < float(foe.get("rev_until", -1.0))
				"blink":
					ok = absf((me.pos as Vector2).distance_to(p0) - float(k.dist)) < 1.0
				"missiles":
					ok = float(foe.hp) < f_hp
				"manashield":
					ok = float(me.get("shield", 0.0)) > float(me.max_hp) * 0.2
				"holylight":
					ok = float(mate.hp) > m_hp + float(mate.max_hp) * 0.15
				"boneshield":
					ok = float(mate.get("shield", 0.0)) > 0.0
			check(cast_ok and spells.size() == 1 and str(spells[0].spell) == str(k.id) and ok,
				"%s %s: %s %s" % [str(hid).to_upper(), slot.to_upper(), str(k.name), why])

# ---------------------------------------------------------------- 4. the effects
func _effects() -> void:
	var sc := _scene("archmage")
	var s = sc[0]
	var me: Dictionary = sc[1]
	var foe: Dictionary = sc[2]
	s.act("you", "spell", "e")
	var sh := float(me.shield)
	var hp0 := float(me.hp)
	s._damage(foe, me, sh * 0.5)
	check(float(me.hp) == hp0 and absf(float(me.shield) - sh * 0.5) < 0.01, "a shield takes the hit first")
	s._damage(foe, me, sh)
	check(float(me.shield) == 0.0 and float(me.hp) < hp0 and float(me.hp) > hp0 - sh * 0.75, "...and only what's left of it")
	_run(s, 5.0)
	check(s.moba.kits.taken({}, me, 10.0) == 10.0, "...and it's gone after its time")
	# slows
	var sp0 := float(s.stat(foe, "speed"))
	s.moba.kits._slow(foe, 0.4, 1.0)
	check(absf(float(s.stat(foe, "speed")) - sp0 * 0.6) < 0.01, "a slow: 40 % slower")
	_run(s, 1.2)
	check(absf(float(s.stat(foe, "speed")) - sp0) < 0.01, "...for its time")
	# marks
	var d0: float = s.moba.mod_damage(me, foe, 100.0)
	s.moba.kits._amp(foe, 0.2, 2.0)
	check(absf(s.moba.mod_damage(me, foe, 100.0) - d0 * 1.2) < 0.01, "marked: 20 % more damage taken")
	# poison
	var r = _scene("rogue")
	var s2 = r[0]
	var me2: Dictionary = r[1]
	var foe2: Dictionary = r[2]
	s2.act("you", "spell", "e")
	me2.face = s2.angle_of((foe2.pos as Vector2) - (me2.pos as Vector2))
	foe2.pos = (me2.pos as Vector2) + Vector2(0, 1.2)
	var hp1 := float(foe2.hp)
	s2.act("you", "attack")
	_run(s2, 0.6)
	var after_hit := float(foe2.hp)
	_run(s2, 2.2)
	check(int(me2.poison_n) == 2 and foe2.has("dots") and float(foe2.hp) < after_hit and after_hit < hp1,
		"POISON BLADES: a hit spends a charge, and the poison ticks (%.0f, then %.0f)" % [hp1 - after_hit, after_hit - float(foe2.hp)])
	s2._kill(me2, foe2)
	check(not foe2.has("dots") and not foe2.has("slow_until") and not foe2.has("shield"), "a fallen hero keeps nothing")

# ---------------------------------------------------------------- 5. bots
func _bots() -> void:
	var casts := {}
	for mi in 2:
		var sm = _new(Moba.HERO_ORDER[(mi * 7 + 2) % Moba.HERO_ORDER.size()], 4200 + mi)
		sm.by_id["you"].bot = true
		while sm.time < 600.0 and not sm.ended:
			sm.step()
			for e in sm.drain_events():
				if e.k == "spell":
					casts[str(e.spell)] = int(casts.get(str(e.spell), 0)) + 1
	print("  bots' casts in two 10-minute matches: %s" % str(casts))
	check(casts.size() >= 12, "bots cast their W and E (%d kinds)" % casts.size())
