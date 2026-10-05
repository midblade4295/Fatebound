extends SceneTree
# 0.31.28: the player launcher -- bought at the workshop, a lever, a 5 s countdown, everyone on the pad flies into the
# enemy castle in real time, untouchable in the air, and lands with a short stagger.
const Sim = preload("res://scripts/siege/siege_sim.gd")
var fails := []
func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok: fails.append(what)
func _init():
	var s = Sim.new()
	s.setup(4, 2)
	for u in s.units: u.bot = false; u.move = Vector2.ZERO; u.pos = Sim.spawn(u.team)
	var me: Dictionary = s.by_id["you"]
	me.pos = s.launch_lever(0)
	check(s.context_action(me) != "launch_lever", "no lever before it's built")
	s.stock[0].wood = 10
	s.stock[0].stone = 10
	check(not s.buy_upgrade(0, "launcher"), "it can't be bought cheap (60 wood, 45 stone)")
	s.stock[0].wood = 100
	s.stock[0].stone = 100
	check(s.buy_upgrade(0, "launcher") and s.launcher_built(0), "bought at the workshop")
	var mates: Array = s.units.filter(func(x): return x.team == 0 and x.id != "you").slice(0, 2)
	var foe: Dictionary = s.units.filter(func(x): return x.team == 1)[0]
	for k in mates.size():
		mates[k].pos = s.launch_pad(0) + Vector2(k * 1.0 - 0.5, 0.4)
	foe.pos = s.launch_pad(0) + Vector2(0.0, -0.8)         # an enemy on the pad goes too
	check(s.context_action(me) == "launch_lever", "ACTION at the lever offers PULL LEVER")
	s.act("you", "interact")
	check(float(s.launchers[0].count_at) >= 0.0, "the countdown started")
	for i in int(4.5 / Sim.TICK): s.step(); s.drain_events()
	check(mates[0].state != "fly", "nobody flies before 5 s")
	var launched := false
	var mid_h := 0.0
	var in_air_hit := true
	for i in int(1.0 / Sim.TICK):
		s.step()
		for e in s.drain_events():
			if e.k == "launch": launched = (e.flown as Array).size() == 3
	check(launched, "at 5 s the three on the pad were launched (two friends, one enemy), not the one at the lever")
	check(mates[0].state == "fly" and foe.state == "fly" and me.state != "fly", "they're in the air")
	var hp0: float = mates[0].hp
	var enemy: Dictionary = s.units.filter(func(x): return x.team == 1 and x.id != foe.id)[0]
	enemy.pos = mates[0].pos + Vector2(1.0, 0.0)
	check(s.nearest_enemy(enemy, 5.0).get("id", "") != mates[0].id, "nobody can target a flyer")
	for i in int(1.0 / Sim.TICK): s.step(); s.drain_events()
	mid_h = s.flight_height(mates[0])
	check(mid_h > 8.0, "it's a high arc (%.1f m up mid-flight)" % mid_h)
	var landed := false
	for i in int(4.0 / Sim.TICK):
		s.step()
		for e in s.drain_events():
			if e.k == "land" and e.id == mates[0].id: landed = true
	check(landed and mates[0].state != "fly", "they land")
	check(Sim.in_castle(mates[0].pos, 1), "inside the enemy castle")
	check(float(s.launchers[0].ready_at) > s.time, "the lever is reloading")
	print("LAUNCHER_PASS" if fails.is_empty() else "LAUNCHER_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
