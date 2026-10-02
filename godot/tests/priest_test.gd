extends SceneTree
# 0.31.1: the High Priest's Resurrection; the Priest's Sanctuary and the Mage's nova reach further.
const Sim = preload("res://scripts/siege/siege_sim.gd")
var fails := []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _fresh(seed_n := 5) -> Object:
	var s = Sim.new()
	s.setup(6, seed_n)
	for u in s.units:
		u.bot = false
		u.move = Vector2.ZERO
		u.pos = Sim.spawn(u.team) + Vector2(randf_range(-6, 6), 0)
	return s

func _init() -> void:
	var s = _fresh()
	var mine: Array = s.units.filter(func(u): return u.team == 0)
	var hp: Dictionary = mine[0]
	s._set_class(hp, "priest", true)
	var pr: Dictionary = mine[1]
	s._set_class(pr, "priest", false)
	check(s.ability_of(hp) == "resurrect" and s.ability_of(pr) == "sanctuary", "the High Priest resurrects; the Priest keeps Sanctuary")
	var base := Vector2(-8.0, 22.0)
	var k: Dictionary = mine[2]
	s._set_class(k, "knight", false)
	k.pos = base + Vector2(4.0, 0.0)
	hp.pos = base
	s._kill({}, k)
	check(k.state == "dead" and k.cls == "villager" and not s.hats.is_empty(), "a knight falls and drops his hat")
	check(s.act(hp.id, "ability"), "the High Priest raises him")
	check(k.state != "dead" and k.cls == "knight" and (k.pos as Vector2).distance_to(base + Vector2(4.0, 0.0)) < 0.1, "back on his feet where he fell, a knight again")
	check(absf(k.hp - k.max_hp * Sim.RESURRECT_HP) < 0.5, "at %d%% health (%.0f of %.0f)" % [int(Sim.RESURRECT_HP * 100), k.hp, k.max_hp])
	check(s.hats.filter(func(h): return h.cls == "knight").is_empty(), "his dropped hat is gone from the ground")
	for i in int((Sim.RESPAWN_TIME + 1.0) / Sim.TICK):
		s.step()
	check((k.pos as Vector2).distance_to(base + Vector2(4.0, 0.0)) < 3.0, "and the old respawn doesn't whisk him back to the castle")
	var v: Dictionary = mine[3]
	v.pos = base + Vector2(0.0, 3.0)
	s._kill({}, v)
	check(not s.act(hp.id, "ability"), "then it's on cooldown (%.0f s)" % Sim.RESURRECT_CD)
	hp.cd_ability = 0.0
	hp.state = "idle"
	v.pos = base + Vector2(0.0, Sim.RESURRECT_R + 1.0)
	check(not s.act(hp.id, "ability"), "nobody in reach: nothing happens")
	# a bot High Priest uses it
	var s2 = _fresh(8)
	var m2: Array = s2.units.filter(func(u): return u.team == 0)
	var bh: Dictionary = m2[0]
	s2._set_class(bh, "priest", true)
	bh.bot = true
	bh.pos = base
	var fallen: Dictionary = m2[1]
	fallen.pos = base + Vector2(3.0, 0.0)
	s2._kill({}, fallen)
	for i in 30:
		s2.step()
		if fallen.state != "dead":
			break
	check(fallen.state != "dead", "a High Priest bot raises a fallen ally next to it")
	# bigger heal and nova
	var s3 = _fresh(3)
	var m3: Array = s3.units.filter(func(u): return u.team == 0)
	var p3: Dictionary = m3[0]
	s3._set_class(p3, "priest", false)
	p3.pos = base
	var hurt: Dictionary = m3[1]
	hurt.pos = base + Vector2(6.0, 0.0)
	hurt.hp = 10.0
	s3.act(p3.id, "ability")
	for i in 30: s3.step()
	check(hurt.hp > 10.0, "Sanctuary now heals an ally 6 m away (radius %.1f m)" % Sim.SANCTUARY_R)
	var mg: Dictionary = m3[2]
	s3._set_class(mg, "mage", false)
	mg.pos = base + Vector2(0.0, 6.0)
	var foe: Dictionary = s3.units.filter(func(u): return u.team == 1)[0]
	foe.pos = mg.pos + Vector2(4.3, 0.0)
	foe.hp = 200.0
	foe.max_hp = 200.0
	mg.state = "idle"
	mg.cd_ability = 0.0
	s3.act(mg.id, "ability")
	for i in 30: s3.step()
	check(foe.hp < 200.0, "the Mage's nova now reaches 4.3 m (radius %.1f m)" % Sim.NOVA_R)
	print("PRIEST_PASS" if fails.is_empty() else "PRIEST_FAIL %d" % fails.size())
	quit()
