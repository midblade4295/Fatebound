extends SceneTree
# 0.31.4 balance: no class caps; per-class stand stock and restock; heals don't stack; armory +8 %/level; Workers 80 hp;
# per-class combat stats are recorded.
const Sim = preload("res://scripts/siege/siege_sim.gd")
var fails := []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	var s = Sim.new()
	s.setup(16, 5)
	for u in s.units:
		u.bot = false
		u.move = Vector2.ZERO
		u.pos = Sim.spawn(u.team) + Vector2(randf_range(-6, 6), 0)
		s._set_class(u, "villager", false)
	var mine: Array = s.units.filter(func(u): return u.team == 0)
	for k in 6:
		s._set_class(mine[k], "knight", false)
	var st: Dictionary = s.stands.filter(func(x): return int(x.team) == 0 and x.cls == "knight")[0]
	var v: Dictionary = mine[7]
	v.pos = st.p
	s.step()
	check(v.cls == "villager", "0.31.22: a player doesn't take a hat just by walking up")
	check(s.context_action(v) == "hat", "the button offers the hat at the stand")
	s.act(v.id, "interact")
	s.step()
	check(v.cls == "knight", "no cap: a 7th knight takes a hat (ACTION)")
	# 0.31.22: once the team owns the Crusader upgrade, a Knight can put on the upgraded hat at the stand
	var kup: Dictionary = mine[0]
	kup.pos = st.p
	s.levels[0]["hat_knight"] = 1
	check(s.context_action(kup) == "hat_equip_up", "the button offers the upgraded hat to a Knight at his stand")
	s.act(kup.id, "interact")
	check(kup.up and kup.cls == "knight", "the Knight now wears the upgraded hat")
	s.levels[0]["hat_knight"] = 0
	s._set_class(kup, "knight", false)              # back to an ordinary Knight for the checks below
	var ps: Dictionary = s.stands.filter(func(x): return int(x.team) == 0 and x.cls == "priest")[0]
	var ms: Dictionary = s.stands.filter(func(x): return int(x.team) == 0 and x.cls == "mage")[0]
	check(int(ps.stock) == 2 and int(ms.stock) == 2 and int(st.stock) == 2, "priest and mage stands hold 2 hats (knight 3, one taken)")
	ps.stock = 0
	ps.t = 0.0
	for i in int(11.0 / Sim.TICK):
		s.step()
	check(int(ps.stock) == 0, "a priest hat takes longer than 11 s to come back")
	for i in int(1.5 / Sim.TICK):
		s.step()
	check(int(ps.stock) == 1, "and arrives by 12.5 s")
	# Sanctuary once per target per 3 s
	var p1: Dictionary = mine[8]
	var p2: Dictionary = mine[9]
	s._set_class(p1, "priest", false)
	s._set_class(p2, "priest", false)
	var hurt: Dictionary = mine[10]
	var base := Vector2(-8.0, 22.0)
	p1.pos = base
	p2.pos = base + Vector2(1.0, 0.0)
	hurt.pos = base + Vector2(0.0, 2.0)
	hurt.max_hp = 500.0
	hurt.hp = 100.0
	s.act(p1.id, "ability")
	s.act(p2.id, "ability")
	for i in 20: s.step()
	check(absf(hurt.hp - (100.0 + Sim.SANCTUARY_HEAL)) < 1.0, "two Sanctuaries at once heal a target once (%.0f)" % (hurt.hp - 100.0))
	# two beams on one target: 1.5x, not 2x
	hurt.hp = 100.0
	for i in int(2.0 / Sim.TICK):
		s.act(p1.id, "attack")
		s.act(p2.id, "attack")
		s.step()
	var one := float(Sim.CLASSES["priest"].heal) * 2.0
	check(hurt.hp - 100.0 < one * 1.7 and hurt.hp - 100.0 > one * 1.3, "two healing beams on one target heal 1.5x (%.0f vs %.0f for one)" % [hurt.hp - 100.0, one])
	# armory and workers
	s.levels[0].armory = 3
	var kn: Dictionary = mine[0]
	check(absf(float(s.stat(kn, "hp")) - 150.0 * 1.24) < 0.5, "armory 3 gives +24 %% (knight %.0f)" % float(s.stat(kn, "hp")))
	check(int(Sim.CLASSES["worker"].hp) == 80, "Workers have 80 health")
	# stats
	var s3 = Sim.new()
	s3.setup(16, 22)
	for i in int(120.0 / Sim.TICK):
		s3.step()
	check(s3.class_stats.has("Knight") and float(s3.class_stats["Knight"].time) > 0.0 and float(s3.class_stats["Knight"].dmg) > 0.0, "bot matches record per-class stats (%d classes)" % s3.class_stats.size())
	print("STANDS_PASS" if fails.is_empty() else "STANDS_FAIL %d" % fails.size())
	quit()
