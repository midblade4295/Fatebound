extends SceneTree
const Sim = preload("res://scripts/siege/siege_sim.gd")
# Knight bots (Round 17, Kevin: "all they do is hold block when enemies are near" -- measured before
# the fix: blocking 98 % of the time, 0 swings, 0 damage). A knight with a barbarian in its face and a
# ranger 8 m away must fight; a knight against a ranger alone must block some shots and still attack.
var fails := []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func run(label: String, with_barb: bool) -> Dictionary:
	var s = Sim.new()
	s.setup(4, 21)
	var k: Dictionary = s.units.filter(func(x): return x.team == 0)[0]
	var foes: Array = s.units.filter(func(x): return x.team == 1)
	for u in s.units:
		u.bot = false
		u.move = Vector2.ZERO
		u.pos = Vector2(-25.0, 0.0) if u.team == 0 else Vector2(25.0, 0.0)
	s._set_class(k, "knight", false)
	k.bot = true
	k.role = "raid"
	k.pos = Vector2(0.0, 18.0)
	var ranger: Dictionary = foes[0]
	s._set_class(ranger, "ranger", false)
	ranger.bot = true
	ranger.pos = Vector2(0.0, 18.0 - 8.0)
	var barb: Dictionary = foes[1]
	if with_barb:
		s._set_class(barb, "barbarian", false)
		barb.bot = true
		barb.pos = Vector2(0.0, 18.0 - 1.6)
	for f in [ranger, barb]:
		f.max_hp = 5000.0
		f.hp = 5000.0
	k.max_hp = 5000.0
	k.hp = 5000.0
	var ticks := 0
	var blocking := 0
	var swings := 0
	var blocked := 0
	var dmg_dealt := 0.0
	var hp0 := {}
	for f in [ranger, barb]:
		hp0[f.id] = f.hp
	for i in int(12.0 / Sim.TICK):
		s.step(Sim.TICK)
		ticks += 1
		if s.blocking(k):
			blocking += 1
		for e in s.drain_events():
			if str(e.k) == "attack" and str(e.get("id", "")) == k.id:
				swings += 1
			if str(e.k) == "blocked":
				blocked += 1
	for f in [ranger, barb]:
		dmg_dealt += float(hp0[f.id]) - float(f.hp)
	var r := {"block": 100.0 * blocking / ticks, "swings": swings, "blocked": blocked, "dmg": dmg_dealt}
	print("%s: blocking %d%% of the time, %d swings, %d shots blocked, %.0f damage dealt" % [label, int(r.block), swings, blocked, dmg_dealt])
	return r

func _init() -> void:
	var a := run("knight vs barbarian + ranger", true)
	check(a.block < 30.0 and a.swings >= 6 and a.dmg > 0.0, "in melee the knight fights (blocking %d%%, %d swings, %.0f dmg)" % [int(a.block), a.swings, a.dmg])
	var b := run("knight vs ranger alone", false)
	check(b.blocked >= 1 and b.swings >= 3 and b.dmg > 0.0, "against an archer it blocks shots and still attacks (%d blocked, %d swings)" % [b.blocked, b.swings])
	check(b.block < 60.0, "it doesn't turtle against an archer (blocking %d%%)" % int(b.block))
	print("KNIGHT_AI_PASS" if fails.is_empty() else "KNIGHT_AI_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
