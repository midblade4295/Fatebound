extends SceneTree
# 0.31.62: melee attacks run in a three-swing combo (same damage); a pause resets it.
const Sim = preload("res://scripts/siege/siege_sim.gd")
const View = preload("res://scripts/siege/siege_view.gd")
func _init():
	var s = Sim.new()
	s.setup(4, 5)
	var k: Dictionary = s.units.filter(func(x): return x.team == 0)[1]
	s._set_class(k, "knight", false)
	for u in s.units: u.bot = false; u.move = Vector2.ZERO; u.pos = Sim.spawn(u.team)
	var seen := []
	var swings := 0
	for i in 400:
		if swings < 4 and s.can_act(k):
			s.act(k.id, "attack")
		for e in s.drain_events():
			if str(e.k) == "attack" and str(e.id) == str(k.id) and str(e.kind) == "attack":
				seen.append(int(e.combo))
				swings += 1
		s.step()
		if swings >= 4:
			break
	print("combo indices while attacking: ", seen)
	for i in int(2.5 / Sim.TICK):
		s.step(); s.drain_events()
	s.act(k.id, "attack")
	var after := -1
	for e in s.drain_events():
		if str(e.k) == "attack" and str(e.id) == str(k.id):
			after = int(e.combo)
	print("after a 2.5 s pause: ", after)
	var ok: bool = seen.slice(0, 4) == [0, 1, 2, 0] and after == 0
	for cls in ["knight", "crusader", "barbarian", "berserker", "rogue", "assassin", "worker", "villager"]:
		var look: Dictionary = View.LOOKS[cls]
		ok = ok and look.has("combo") and (look.combo as Array).size() == 3
	print("COMBO_PASS" if ok else "COMBO_FAIL")
	quit(0 if ok else 1)
