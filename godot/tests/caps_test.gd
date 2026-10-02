extends SceneTree
# Class caps per team (0.31.3): stands, dropped hats and the workshop refuse a full class; upgraded classes count as their
# base; bots never go over; the cap frees up when someone dies.
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
	for k in 4:
		s._set_class(mine[k], "knight", false)
	var st: Dictionary = s.stands.filter(func(x): return int(x.team) == 0 and x.cls == "knight")[0]
	var v: Dictionary = mine[5]
	v.pos = st.p
	var stock0: int = int(st.stock)
	check(s.context_action(v) == "class_full" or s.context_action(v) == "", "the knight stand offers nothing to a 5th knight (%s)" % s.context_action(v))
	s.step()
	check(v.cls == "villager" and int(st.stock) == stock0, "walking onto the stand doesn't make a 5th knight")
	var ko: Dictionary = mine[0]
	ko.pos = Sim.spawn(0) + Vector2(10, 0)
	s._kill({}, ko)
	v.pos = Sim.spawn(0) + Vector2(20, 3)
	var dropped: Dictionary = s.hats[s.hats.size() - 1]
	var v2: Dictionary = mine[6]
	s._set_class(mine[7], "knight", false)                       # someone else fills the place first
	v2.pos = dropped.pos
	s.step()
	check(v2.cls == "villager" and s.hats.has(dropped), "a dropped knight hat can't be picked up while knights are full")
	s._kill({}, mine[7])
	v2.pos = dropped.pos
	s.step()
	check(v2.cls == "knight", "once a knight falls, the hat can be picked up")
	# workers
	for k in [8, 9, 10]:
		s._set_class(mine[k], "worker", false)
	var w4: Dictionary = mine[11]
	w4.pos = s.workshop(0)
	check(not s._take_tools(w4) and w4.cls == "villager", "a 4th worker can't take tools")
	# upgraded counts as base
	var s2 = Sim.new()
	s2.setup(16, 6)
	var m2: Array = s2.units.filter(func(u): return u.team == 0)
	for u in s2.units:
		u.bot = false
		s2._set_class(u, "villager", false)
	s2._set_class(m2[0], "priest", true)
	s2._set_class(m2[1], "priest", false)
	check(s2.class_full(0, "priest"), "a Necromancer and a Priest fill the two priest places")
	# bots stay within the caps all match long
	var s3 = Sim.new()
	s3.setup(16, 22)
	var worst := {}
	for i in int(300.0 / Sim.TICK):
		s3.step()
		if i % 30 == 0:
			for t in 2:
				for c in Sim.CLASS_CAP:
					var n: int = s3.class_count(t, c)
					worst[c] = maxi(int(worst.get(c, 0)), n)
	var over := []
	for c in Sim.CLASS_CAP:
		if int(worst.get(c, 0)) > int(Sim.CLASS_CAP[c]):
			over.append("%s %d>%d" % [c, worst[c], Sim.CLASS_CAP[c]])
	check(over.is_empty(), "16v16 bots never exceed a cap in 5 minutes (peaks %s)" % str(worst))
	print("CAPS_PASS" if fails.is_empty() else "CAPS_FAIL %d" % fails.size())
	quit()
