extends SceneTree
# 0.31.217 (Kevin, with Honor of Kings' training: "Here is how I want the training to go in fatebound. The helper will
# be another character and voiced by the herald"): the two trainings (scripts/siege/training.gd) played through in real
# matches.
#  - Kael's 58 lines are the recorded script's (art_sources/training/script.json), every one voiced
#    (assets/vo/training/<id>.ogg); the key words in his bar lit gold;
#  - TRAINING 1: one of our bots is Kael the Dragoon, driven by the training; every other hero at his fountain, no
#    waves or camps; you and he behind our outer tower, the match running while he talks (his line in the bar, the
#    task in the box, TUTORIAL 1/5). Each lesson done the way a player does it: walk to the marked spot; their wave
#    (6) beaten; the + tapped (a skill learnt); the enemy hero beaten; level 2, the second skill; two heroes; level 3, a
#    rank 2; level 4, the ultimate learnt, then used on three heroes; the quick-buy tapped; their outer tower (our
#    army sent in), the inner one taken with it, the high ground tower, the King -> VICTORY, the card, CONTINUE (home;
#    no profile here, so nothing paid). His bubbles: "Well done!", "Wow, you're on fire!", "You're a natural!";
#    you can't fall;
#  - TRAINING 2 (as the Archer): a real match -- the bots playing, Kael at your side (not a bot); the map tour first
#    with the match waiting, a tap a line; then "To the bottom lane. Follow me!" and the walk there; missions 1/4..4/4
#    as their towers fall; the towers' lesson the first time you're by one (the match waits); their King -> VICTORY.
#   godot --headless --path godot -s res://tests/training_test.gd
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Tr = preload("res://scripts/siege/training.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
var mode
var fails := []
var exited := false

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await process_frame
	return cond.call()

func _start(which: int, hero: String, seed_value: int) -> void:
	exited = false
	mode = Mode.new()
	mode.tutorial = true
	mode.training = which
	mode.moba_hero = hero
	mode.match_seed = seed_value
	mode.exited.connect(func(): exited = true)
	root.add_child(mode)
	await _until(func(): return mode.sim != null and mode._build_queue.is_empty() and mode.tutorial_ui != null, 400)
	await _until(func(): return mode.tutorial_ui.phase == "play", 200)

func _kill(s, u: Dictionary) -> void:
	if not u.is_empty() and s.alive(u):
		s._damage(s.by_id["you"], u, 1.0e6)

func _step(trn) -> String:
	return trn.step_id()

func _run() -> void:
	# ---- the script and its voice
	var script: Array = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../art_sources/training/script.json")))
	var differ := []
	var missing := []
	for l in script:
		if str(Tr.LINES.get(str(l[0]), "")) != str(l[2]):
			differ.append(l[0])
		if not ResourceLoader.exists(Tr.VO_DIR + str(l[0]) + ".ogg"):
			missing.append(l[0])
	check(script.size() == 58 and Tr.LINES.size() == 58 and differ.is_empty(), "Kael's 58 lines, the recorded script's word for word (differ %s)" % str(differ))
	check(missing.is_empty(), "every line voiced (missing %s)" % str(missing))
	var used := []
	for st in Tr.K1 + Tr.K2:
		used.append_array(st.get("say", []) + st.get("after", []))
	used.append_array(Tr.TOUR + Tr.TOWER_TALK + Tr.POST_GO.values())
	check(used.all(func(id): return Tr.LINES.has(str(id))), "every line a step says is in the script")
	check(Tr.lit("Tap ATTACK to strike.") == "Tap [color=#ffd65a]ATTACK[/color] to strike."
		and Tr.lit("The Rift has three lanes.") == "The Rift has three [color=#ffd65a]lanes[/color].",
		"his bar lights the key words (%s)" % Tr.lit("Tap ATTACK to strike."))
	await _training1()
	await _training2()
	print("TRAINING_PASS" if fails.is_empty() else "TRAINING_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)

# ================================================================ training 1
func _training1() -> void:
	await _start(1, "knight", 5150)
	var s = mode.sim
	var hud = mode.hud
	var trn = mode.tutorial_ui
	var me: Dictionary = s.by_id["you"]
	var t := int(me.team)
	var kael: Dictionary = trn.kael
	check(trn.get_parent() == hud and trn.get_index() == 1, "the training over the HUD, under its buttons")
	check(not kael.is_empty() and str(kael.hid) == "dragoon" and str(kael.bot_name) == "Kael" and not bool(kael.bot) and int(kael.team) == t,
		"one of ours is Kael the Dragoon, driven by the training")
	var held := true
	for tt in 2:
		for hid in s.moba.heroes[tt]:
			if bool(s.by_id[hid].bot):
				held = false
	check(held and s.moba.wave_at == INF and (me.pos as Vector2).distance_to(Tr._side(t, Tr.P_START)) < 0.5,
		"the others at their fountains, no waves; you behind our outer tower")
	await _frames(3)
	check(_step(trn) == "move" and trn.box.visible and trn.box_head.text == "TUTORIAL 1/5" and trn.lines_said == ["k1_hello"] and trn.bar.visible,
		"TUTORIAL 1/5: the task in the box, his first line in the bar (%s)" % str(trn.lines_said))
	var t0: float = s.time
	await _frames(20)
	check(s.time > t0 and not trn.holds() and not hud.tut_modal, "the match runs while he talks")
	check(trn.guide().has("stick") and trn.guide().get("route", false), "a hand on the stick, the dotted path to the spot")
	# -- move
	me.pos = trn._goal
	await _until(func(): return _step(trn) == "minions", 30)
	check(_step(trn) == "minions" and trn._alive(trn._wave).size() == 6 and trn.box_head.text == "TUTORIAL 2/5", "there: TUTORIAL 2/5, their wave (6)")
	await _frames(2)
	check(str(trn.guide().get("button", "")) == "attack" and trn.progress() == "0/6", "a hand on ATTACK; 0/6")
	for id in trn._wave.duplicate():
		_kill(s, s.by_id.get(str(id), {}))
	await _until(func(): return _step(trn) == "learn", 30)
	check(_step(trn) == "learn" and trn.bubbles_said.has("b_well_done"), "the wave beaten -- \"Well done!\" -- TUTORIAL 3/5: learn a skill")
	await _frames(2)
	check(str(trn.guide().get("learn", "")) != "" and not hud.learn_spots(me).is_empty(), "a hand on a + (%s)" % str(trn.guide()))
	hud.action_pressed.emit("learn_q")
	await _until(func(): return _step(trn) == "hero", 30)
	check(_step(trn) == "hero" and trn._alive(trn.foes).size() == 1 and s.moba.rank(me, "q") == 1, "Q learnt: an enemy hero comes")
	var foe: Dictionary = s.by_id[str(trn.foes[0])]
	check(float(foe.hp) <= float(foe.max_hp) * 0.51 and float(foe.m_out) == Tr.SOFT and str(trn.guide().get("button", "")) == "ability",
		"...at half health, hitting softer; a hand on Q")
	await _frames(40)
	check(float(me.hp) >= float(me.max_hp) * Tr.HP_FLOOR - 0.01, "you can't fall")
	_kill(s, foe)
	await _until(func(): return _step(trn) == "learn2", 30)
	check(_step(trn) == "learn2" and int(me.level) >= 2 and trn.bubbles_said.has("b_on_fire") and trn.box_head.text == "TUTORIAL 4/5",
		"beaten -- \"Wow, you're on fire!\" -- level 2: TUTORIAL 4/5")
	hud.action_pressed.emit("learn_w")
	await _until(func(): return _step(trn) == "combo", 30)
	check(_step(trn) == "combo" and trn._alive(trn.foes).size() == 2, "W learnt: two of them")
	for id in trn.foes.duplicate():
		_kill(s, s.by_id[str(id)])
	await _until(func(): return _step(trn) == "upgrade", 30)
	check(_step(trn) == "upgrade" and int(me.level) >= 3 and trn.bubbles_said.has("b_natural"), "both beaten -- \"You're a natural!\" -- level 3")
	hud.action_pressed.emit("learn_q")
	await _until(func(): return _step(trn) == "ult", 30)
	check(_step(trn) == "ult" and s.moba.rank(me, "q") == 2 and int(me.level) >= 4 and trn.box_head.text == "TUTORIAL 5/5", "Q at rank 2; level 4: TUTORIAL 5/5")
	await _frames(2)
	check(str(trn.guide().get("learn", "")) == "r", "a hand on the ultimate's +")
	hud.action_pressed.emit("learn_r")
	await _until(func(): return _step(trn) == "ult_use", 30)
	check(_step(trn) == "ult_use" and trn._alive(trn.foes).size() == 3 and s.moba.ult_ready(me), "R learnt: three of them, the ultimate ready")
	await _frames(2)
	check(str(trn.guide().get("button", "")) == "ult", "a hand on the ultimate")
	hud.action_pressed.emit("ult")
	await _until(func(): return trn._ult_used, 30)
	check(trn._ult_used, "...used")
	for id in trn.foes.duplicate():
		_kill(s, s.by_id[str(id)])
	await _until(func(): return _step(trn) == "shop", 30)
	check(_step(trn) == "shop" and trn.box_head.text == "QUICK-BUY", "beaten: the quick-buy")
	await _frames(2)
	var qr: Array = hud.quick_rects(me)
	check(not qr.is_empty() and s.moba.buy_why(me, str(qr[0].id)) == "" and trn.guide().has("rect"), "a hand on the item on the left, its gold there")
	var n0 := (me.items as Array).size()
	hud._touch(0, (qr[0].r as Rect2).get_center(), true)
	hud._touch(0, (qr[0].r as Rect2).get_center(), false)
	await _until(func(): return _step(trn) == "tower1", 30)
	check(_step(trn) == "tower1" and (me.items as Array).size() == n0 + 1 and trn.box_head.text == "CHALLENGE 1/3", "bought, out in the lane: CHALLENGE 1/3")
	var tw1: Dictionary = trn._tw
	check(int(tw1.tier) == 1 and int(tw1.team) != t and int(tw1.lane) == 1 and float(tw1.hp) <= float(tw1.max_hp) * Tr.TOWER_LEFT + 0.1,
		"their middle outer tower, weakened")
	await _frames(10)
	check(not trn._ours.is_empty() and (trn.lines_said.has("k1_towers") or trn._queue.has("k1_towers")), "our army sent in; \"Now we break their towers\"")
	me.pos = (tw1.p as Vector2) + Tr._side(t, Vector2(0.0, 9.0))
	await _until(func(): return trn.lines_said.has("k1_tower") or trn._queue.has("k1_tower"), 60)
	check(trn._once.has("tower"), "in its range: \"Let our minions walk in first\"")
	s.moba.hit_tower(me, int(tw1.id), 1.0e9)
	await _until(func(): return _step(trn) == "tower3", 30)
	var inner: Dictionary = trn._tower(1 - t, 1, 2)
	check(_step(trn) == "tower3" and bool(tw1.dead) and bool(inner.dead) and trn.box_head.text == "CHALLENGE 2/3",
		"down -- our army took the inner one too -- CHALLENGE 2/3: the high ground")
	s.moba.hit_tower(me, int(trn._tw.id), 1.0e9)
	await _until(func(): return _step(trn) == "king", 30)
	var et := 1 - t
	check(_step(trn) == "king" and s.moba.king_open(et) and s.moba.king_frac(et) <= Tr.KING_LEFT + 0.01 and trn.box_head.text == "CHALLENGE 3/3",
		"the lane broken: their King open -- CHALLENGE 3/3")
	s.moba.hit_king(me, et, 1.0e9)
	await _until(func(): return trn.phase == "over", 60)
	check(trn.phase == "over" and trn.won and mode._result_shown and mode.match_result.is_empty() and hud.tut_modal,
		"their King down: VICTORY -- the training's own end, no match rewards")
	await _until(func(): return trn.end_layer != null and trn.end_layer.find_child("Card", true, false) != null, 200)
	var big: Label = trn.end_layer.find_child("Big", true, false)
	check(big != null and big.text == "VICTORY" and trn.lines_said.has("k1_victory"), "VICTORY, \"Victory! You're a natural.\"")
	var go: Button = null
	for b in trn.end_layer.find_children("*", "Button", true, false):
		if str(b.get_meta("action_key", "")) == "training_continue":
			go = b
	check(go != null, "TRAINING 1 COMPLETE, CONTINUE")
	if go != null:
		go.pressed.emit()
	await _until(func(): return exited, 30)
	check(exited and mode.exit_note == "tutorial", "CONTINUE: home (nothing to pay with no profile)")
	mode.queue_free()
	await _frames(3)

# ================================================================ training 2
func _training2() -> void:
	await _start(2, "ranger", 7)
	var s = mode.sim
	var hud = mode.hud
	var trn = mode.tutorial_ui
	var me: Dictionary = s.by_id["you"]
	var t := int(me.team)
	var et := 1 - t
	var bots := 0
	for tt in 2:
		for hid in s.moba.heroes[tt]:
			if bool(s.by_id[hid].bot):
				bots += 1
	check(not trn.kael.is_empty() and not bool(trn.kael.bot) and bots == 8 and s.moba.wave_at < INF, "a real match: eight bots playing, Kael at your side")
	await _frames(3)
	check(_step(trn) == "tour" and trn.holds() and trn.map != null and trn.map.visible and trn.tapper.visible and trn.lines_said == ["k2_welcome"],
		"the map first: \"Welcome to the Rift\", the match waiting")
	var t0: float = s.time
	await _frames(15)
	check(s.time == t0, "...it waits (%.2f)" % s.time)
	var guard := 0
	while _step(trn) == "tour" and guard < 80:
		trn.next()
		trn.next()
		guard += 1
		await process_frame
	check(_step(trn) == "go" and not trn.holds() and not trn.map.visible, "a tap a line, to the end of the tour")
	check(trn.lines_said.slice(0, 12) == Tr.TOUR, "...every line of it, in order")
	await _until(func(): return trn.lines_said.has("k2_go_bot"), 400)
	check(str(me.post) == "bot" and trn.lines_said.has("k2_go_bot") and trn.box_task.text == "Follow Kael to the bottom lane",
		"the Archer: \"To the bottom lane. Follow me!\"")
	me.pos = trn._goal
	await _until(func(): return _step(trn) == "m1", 30)
	check(_step(trn) == "m1" and trn.box_head.text == "MISSION 1/4", "there: MISSION 1/4 (an outer tower)")
	# the towers' lesson, the first time you're by one of theirs
	var tw: Dictionary = trn._tower(et, 2, 1)
	me.pos = (tw.p as Vector2) + Tr._side(t, Vector2(0.0, 13.0))
	await _until(func(): return trn.hold_kind == "towers", 30)
	t0 = s.time
	await _frames(10)
	check(trn.hold_kind == "towers" and s.time == t0 and trn.lines_said.has("k2_tw1"), "by their tower: the towers' lesson, the match waiting")
	guard = 0
	while trn.hold_kind == "towers" and guard < 60:
		trn.next()
		trn.next()
		guard += 1
		await process_frame
	check(trn.hold_kind == "" and Tr.TOWER_TALK.all(func(id): return trn.lines_said.has(id)), "...seven lines, then on")
	for tier in [1, 2, 3]:
		var x: Dictionary = trn._tower(et, 2, tier)
		s.moba.hit_tower(me, int(x.id), 1.0e9)
		await _until(func(): return _step(trn) == "m%d" % (tier + 1), 30)
		check(_step(trn) == "m%d" % (tier + 1) and trn.box_head.text == "MISSION %d/4" % (tier + 1), "their tier %d tower down: MISSION %d/4" % [tier, tier + 1])
	await _until(func(): return trn._once.has("king"), 30)
	check(s.moba.king_open(et) and trn._once.has("king"), "their King open: \"Their King hits incredibly hard\"")
	s.moba.hit_king(me, et, 1.0e9)
	await _until(func(): return trn.phase == "over", 60)
	check(trn.phase == "over" and trn.won and mode.match_result.is_empty(), "their King down: VICTORY, no match rewards")
	await _until(func(): return trn.lines_said.has("k2_victory"), 60)
	check(trn.lines_said.has("k2_victory"), "\"Victory! You're ready for the real thing.\"")
	mode.queue_free()
	await _frames(3)
