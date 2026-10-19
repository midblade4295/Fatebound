extends SceneTree
# 0.31.181 (Kevin: "Also add a teleport back to castle mechanic"): the 5v5's RECALL (siege_sim.gd _recall).
#  - HOME: stand still RECALL_TIME s and you're at your fountain ("recall", then "recall_done" from where to where);
#  - moving, attacking, any damage, or a stun ends it ("recall_cancel"); at the fountain already: not started;
#  - a hurt bot with no enemy hero near recalls instead of walking home, and gets there;
#  - the HUD: the HOME button (B on a keyboard) starts it in a match; the bar under you while it channels.
#   godot --headless --path godot -s res://tests/recall_test.gd
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Mode = preload("res://scripts/siege/siege_mode.gd")
var mode
var frames := 0
var fails := []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

static func _fresh(seed_v: int):
	var s = Sim.new()
	s.setup(5, seed_v)
	s.setup_moba("knight", seed_v)
	for u in s.units:
		if bool(u.get("hero", false)):
			u.bot = false
	return s

static func _run(s, secs: float) -> Array:
	var evs := []
	var n := int(round(secs / Sim.TICK))
	for i in n:
		s.step(Sim.TICK)
		evs.append_array(s.drain_events())
	return evs

static func _has(evs: Array, k: String, id: String) -> bool:
	for e in evs:
		if str(e.get("k", "")) == k and str(e.get("id", "")) == id:
			return true
	return false

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")
	var s = _fresh(91)
	var me: Dictionary = s.by_id["you"]
	var home: Vector2 = s.spawn(int(me.team))
	check(not s.act("you", "recall"), "at the fountain: no recall")
	me.pos = Vector2(0, 30.0 if int(me.team) == 0 else -30.0)      # (out in mid, nobody about at 0:00)
	s.drain_events()
	check(s.act("you", "recall") and s.recalling(me), "out in the field: HOME starts the recall")
	var evs := _run(s, Sim.RECALL_TIME - 0.3)
	check(s.recalling(me) and (me.pos as Vector2).distance_to(home) > 20.0, "after %.1f s still standing there" % (Sim.RECALL_TIME - 0.3))
	evs = _run(s, 0.5)
	check(not s.recalling(me) and (me.pos as Vector2).distance_to(home) < 4.0 and _has(evs, "recall_done", "you"),
		"at %.0f s: home at the fountain (%.1f m from it)" % [Sim.RECALL_TIME, (me.pos as Vector2).distance_to(home)])
	# what ends it
	for why in ["move", "attack", "hurt", "stun"]:
		s = _fresh(92)
		me = s.by_id["you"]
		me.pos = Vector2(0, 30.0 if int(me.team) == 0 else -30.0)
		s.act("you", "recall")
		_run(s, 1.0)
		s.drain_events()
		match why:
			"move":
				s.set_move("you", Vector2(1, 0))
			"attack":
				s.act("you", "attack")
			"hurt":
				s._damage({"id":"tower0", "team":1 - int(me.team), "pos":Vector2.ZERO}, me, 5.0)
			"stun":
				me.stun = 0.5
		evs = _run(s, 0.2)
		check(not s.recalling(me) and _has(evs, "recall_cancel", "you"), "%s: the recall's off" % why)
	# a hurt bot recalls home
	s = _fresh(93)
	var b: Dictionary = s.by_id["b1"]
	b.bot = true
	b.pos = Vector2(-30.0, 20.0 if int(b.team) == 0 else -20.0)
	b.hp = float(b.max_hp) * 0.2
	var started := false
	for i in int(2.0 / Sim.TICK):
		s.step(Sim.TICK)
		started = started or s.recalling(b)
		b.hp = minf(float(b.hp), float(b.max_hp) * 0.2)
	check(started, "a hurt bot with no enemy near: recalls")
	_run(s, Sim.RECALL_TIME + 0.5)
	check(s.in_castle(b.pos, int(b.team)), "...and is home")
	# the HUD
	mode = Mode.new()
	mode.moba_hero = "knight"
	mode.match_seed = 4411
	root.add_child(mode)

func _process(_d: float) -> bool:
	frames += 1
	if mode.sim == null or not mode._build_queue.is_empty() or frames < 30:
		return false
	var s = mode.sim
	var hud = mode.hud
	var me: Dictionary = s.by_id["you"]
	if frames == 30:
		var ids: Array = hud._buttons().map(func(b): return str(b.id))
		check(ids.has("recall"), "the HOME button is there")
		me.pos = Vector2(0, 30.0 if int(me.team) == 0 else -30.0)
		hud.action_pressed.emit("recall")
		check(s.recalling(me), "HOME pressed in a match: recalling")
		return false
	if frames == 40:
		hud.queue_redraw()
		check(s.recalling(me), "...still, the bar under you")
		print("RECALL_%s" % ("PASS" if fails.is_empty() else "FAIL %s" % str(fails)))
		quit(0 if fails.is_empty() else 1)
		return true
	return false
