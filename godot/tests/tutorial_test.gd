extends SceneTree
# 0.31.181 (Kevin: "create a tutorial walking player through the basics of a match ... Make it voiced and make it
# humorous and sarcastic"): the 5v5 tutorial (scripts/siege/tutorial.gd) played through in a real match.
#  - every line has its voice (assets/vo/tutorial/<id>.ogg) and its caption is the recorded script's
#    (art_sources/tutorial/script.json); (0.31.182) each line's pose of the Herald with his scroll is there, and the line
#    fits the clear part of its parchment at 13 px or more on the narrowest phone (420 x 933);
#  - the match is quiet: every other hero held at his fountain, no waves or camps of its own; the match waits while the
#    Herald talks (the HUD's buttons too), and steps during a task; you can't fall;
#  - each task done the way a player does it: walk; two last hits on the wave put down for it; the scoreboard; HOME (a
#    hit cancels it, then home); a buy at the shop; Q held, W, E and the upgrade cards; the Grave Archers cleared;
#    (0.31.206) a ward: on open ground it's refused (the charge back), in the brush it's done;
#    three hits on their outer tower with our minions under it; then the talk to the end, which leaves the match
#    ("tutorial" -- nothing to pay here: no profile).
#   godot --headless --path godot -s res://tests/tutorial_test.gd
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Tut = preload("res://scripts/siege/tutorial.gd")
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

func _talk_through(tut) -> void:
	# tap until the Herald stops talking (a task, the next step's talk is talk too: stop at a task or the end)
	var guard := 0
	while tut.holds() and not exited and guard < 200:
		tut.next()
		guard += 1
		await process_frame
		if tut.phase == "task":
			return

func _until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await process_frame
	return cond.call()

func _run() -> void:
	# ---- the script and its voice
	var script: Array = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../art_sources/tutorial/script.json")))
	var text := {}
	if script != null:
		for l in script:
			text[str(l[0])] = str(l[2])
	var lines := []
	for st in Tut.STEPS:
		for k in ["talk", "done"]:
			for l in st.get(k, []):
				if str(l[0]) != "@pay":
					lines.append(l)
	lines.append(Tut.END_GOLD)
	lines.append(Tut.END_NOGOLD)
	var missing := []
	var differ := []
	for l in lines:
		if not ResourceLoader.exists(Tut.VO_DIR + str(l[0]) + ".ogg"):
			missing.append(l[0])
		if text.is_empty() or str(text.get(str(l[0]), "")) != str(l[1]):
			differ.append(l[0])
	check(lines.size() == 36 and missing.is_empty(), "%d lines, every one voiced (missing %s)" % [lines.size(), str(missing)])
	check(differ.is_empty(), "the captions are the recorded script's (differ: %s)" % str(differ))
	var bad := []
	var small := []
	var used := {}
	for l in lines:
		var pz := str(l[2]) if (l as Array).size() > 2 else ""
		used[pz] = true
		if not Tut.Poses.POSES.has(pz) or not ResourceLoader.exists(Tut.POSE_PATH % pz):
			bad.append("%s:%s" % [l[0], pz])
			continue
		var r: Dictionary = Tut.scroll_rects(pz, Vector2(933, 420))        # (0.31.216: landscape)
		var px: int = Tut.fit_px(str(l[1]), (r.text as Rect2).size)
		var hgt: float = Tut.text_height(str(l[1]), (r.text as Rect2).size.x, px)
		if px < 13 or hgt > (r.text as Rect2).size.y or not Rect2(0, 0, 933, 420).encloses((r.art as Rect2).grow(-1.0)):
			small.append("%s:%s %dpx" % [l[0], pz, px])
	check(bad.is_empty() and used.size() == 8, "every line posed, all 8 poses used (%s)" % str(bad))
	check(small.is_empty(), "every line fits its scroll at 13 px or more, the Herald all on the screen (%s)" % str(small))
	# ---- the match
	mode = Mode.new()
	mode.tutorial = true
	mode.moba_hero = "knight"
	mode.match_seed = 5150
	mode.exited.connect(func(): exited = true)
	root.add_child(mode)
	await _until(func(): return mode.sim != null and mode._build_queue.is_empty() and mode.tutorial_ui != null, 300)
	var s = mode.sim
	var hud = mode.hud
	var tut = mode.tutorial_ui
	check(tut != null and tut.get_parent() == hud and tut.get_index() == 1, "the overlay over the HUD, under its buttons")
	await _until(func(): return tut.phase == "talk", 120)
	var me: Dictionary = s.by_id["you"]
	check(tut.lines_said == ["t5_intro_1"] and hud.tut_modal and hud._modal_open(), "the Herald's first line; the HUD's buttons wait")
	check(tut.pose == "hold" and tut.scroll.visible and tut.scroll.texture != null, "...on his scroll, holding it open")
	var held := true
	for t in 2:
		for hid in s.moba.heroes[t]:
			if hid != "you" and bool(s.by_id[hid].bot):
				held = false
	check(held and s.moba.wave_at == INF and not hud.qc_btn.visible, "the others on a tea break, no waves, no quick chat")
	var t0: float = s.time
	await _frames(20)
	check(s.time == t0, "the match waits while he talks (%.2f)" % s.time)
	# ---- move
	await _talk_through(tut)
	check(str(tut.STEPS[tut.step].id) == "move" and tut.phase == "task" and not hud.tut_modal, "move: the task, the stick free")
	me.pos = (me.pos as Vector2) + Vector2(0, -7.0)
	await _frames(3)
	check(s.time > t0, "the match steps during a task")
	check(tut.phase == "done", "walked: done")
	# ---- lane: two last hits
	await _talk_through(tut)
	check(str(tut.STEPS[tut.step].id) == "lane" and tut._alive_ids(tut._red).size() == 6, "lane: a wave of theirs put down (and ours)")
	check((me.pos as Vector2).distance_to(Vector2(3.0, 24.0)) < 1.0, "...and you hopped over to it")
	for i in 2:
		var m: Dictionary = s.by_id[str(tut._alive_ids(tut._red)[0])]
		m.hp = 1.0
		s._damage(me, m, 50.0)
	await _frames(3)
	check(int(me.get("lh", 0)) >= 2 and tut.phase == "done", "two last hits: done (lh %d)" % int(me.get("lh", 0)))
	# ---- eco: the scoreboard
	await _talk_through(tut)
	check(str(tut.STEPS[tut.step].id) == "eco", "eco")
	hud.open_board()
	await _frames(3)
	check(tut.phase == "done", "the scoreboard opened: done")
	hud.close_board()
	# ---- recall: a hit cancels it, then home
	await _talk_through(tut)
	check(str(tut.STEPS[tut.step].id) == "recall" and not s.in_castle(me.pos, 0), "recall, out in the field")
	for id in tut._alive_ids(tut._red):
		s._kill({}, s.by_id[str(id)])               # (nobody about to cancel it but us)
	hud.action_pressed.emit("recall")
	await _frames(2)
	check(s.recalling(me), "HOME: recalling")
	s._damage({"id":"tower9", "team":1, "pos":Vector2.ZERO}, me, 5.0)
	await _frames(3)
	check(not s.recalling(me) and tut.note_label.visible, "hit: cancelled, and the Herald says so")
	hud.action_pressed.emit("recall")
	await _frames(2)
	me.recall_until = float(s.time) + 0.2
	await _until(func(): return tut.phase == "done", 60)
	check(tut.phase == "done" and s.in_castle(me.pos, 0), "home: done")
	# ---- shop
	await _talk_through(tut)
	check(str(tut.STEPS[tut.step].id) == "shop" and s.moba.can_shop(me), "shop, at home")
	me.gold = 2000.0
	hud.open_shop()
	hud.action_pressed.emit("shop_buy:boots")
	await _frames(3)
	check(tut.phase == "done" and (me.items as Array).has("boots") and not hud.shop_open(), "bought: done (the shop closed)")
	# ---- abilities
	await _talk_through(tut)
	check(str(tut.STEPS[tut.step].id) == "abilities" and int(me.level) >= 3, "abilities: promoted to level %d" % int(me.level))
	hud._ability_held = true
	await _until(func(): return tut._shield_t >= tut.SHIELD_FOR, 90)
	hud._ability_held = false
	check(tut._shield_t >= tut.SHIELD_FOR, "Q held: the shield up %.1f s" % tut._shield_t)
	hud.action_pressed.emit("w")
	await _frames(25)
	hud.action_pressed.emit("e")
	await _frames(3)
	check(tut._w_done and tut._e_done, "W and E")
	var guard := 0
	while not (me.picks as Array).is_empty() and guard < 10:
		hud.action_pressed.emit("pick0")
		guard += 1
		await _frames(2)
	await _frames(2)
	check(tut.phase == "done", "the upgrades picked: done")
	# ---- jungle
	await _talk_through(tut)
	var camp: Dictionary = tut._camp
	check(str(tut.STEPS[tut.step].id) == "jungle" and not camp.is_empty() and s.moba.camp_live(camp).size() == 3, "jungle: our Grave Archers up")
	for mob in s.moba.camp_live(camp):
		s._damage(me, mob, 99999.0)
	await _frames(4)
	check(tut.phase == "done", "cleared: done")
	# ---- ward (0.31.206, Kevin: "Also teach players about how wards work in the training")
	await _talk_through(tut)
	var br: Dictionary = tut._brush
	var vis = s.moba.vision
	check(str(tut.STEPS[tut.step].id) == "ward" and not br.is_empty() and ((br.p as Vector2).y > 0.0) == (int(me.team) == 0)
		and float(me.ward_ch) >= 1.0 and (me.pos as Vector2).distance_to(br.p) <= Tut.WARD_NEAR and vis.brush_at(me.pos) < 0,
		"ward: a brush of ours (you were at the castle: a hop to %.0f m short of it), a charge to put down" % (me.pos as Vector2).distance_to(br.p))
	var info: Dictionary = tut.task_info()
	check(info.get("label", "") == "BRUSH" and not info.has("button"), "...the way to the brush shown")
	var open := (br.p as Vector2) + Vector2(float(br.r) + 4.0, 0.0)
	if vis.brush_at(open) >= 0:
		open = (br.p as Vector2) - Vector2(float(br.r) + 4.0, 0.0)
	me.pos = open
	var ch0 := float(me.ward_ch)
	s.act("you", "ward")
	await _frames(3)
	check(tut.phase == "task" and float(me.ward_ch) >= ch0 - 0.01 and tut.note_label.visible, "a ward on open ground: not it (the charge back, a word from him)")
	me.pos = br.p
	await _frames(2)
	check(tut.task_info().get("button", "") == "ward", "in the brush: TAP on WARD")
	s.act("you", "ward")
	await _frames(3)
	check(tut.phase == "done" and vis.wards.any(func(w): return int(w.brush) == int(br.id) and int(w.team) == int(me.team)), "a ward in the brush: done")
	# ---- tower
	await _talk_through(tut)
	var tw: Dictionary = tut._tw
	check(str(tut.STEPS[tut.step].id) == "tower" and not tw.is_empty() and int(tw.team) == 1 and int(tw.tier) == 1, "tower: their outer mid")
	check(tut._alive_ids(tut._ours).size() == 6, "...our minions put down to go first")
	me.pos = (tw.p as Vector2) + Vector2(0, 4.0)
	for i in 3:
		s.moba.hit_tower(me, int(tw.id), 10.0, me.pos)
	await _frames(3)
	check(tut.phase == "done", "three hits: done")
	# can't fall
	me.hp = 1.0
	await _frames(2)
	check(float(me.hp) >= float(me.max_hp) * 0.29, "you can't fall (health held at %.0f %%)" % (float(me.hp) / float(me.max_hp) * 100.0))
	# ---- the talk to the end
	await _talk_through(tut)
	await _until(func(): return exited, 30)
	var ids: Array = tut.lines_said
	check(ids.has("t5_die_1") and ids.has("t5_win_2") and ids.has("t5_end_1") and ids.back() == "t5_end_nogold",
		"dying, winning, the end (no profile: no pay)")
	check(exited and mode.exit_note == "tutorial", "the last tap: out of the match (%s)" % mode.exit_note)
	for t in 2:
		for hid in s.moba.heroes[t]:
			if hid != "you" and not s.in_castle(s.by_id[hid].pos, t):
				held = false
	check(held, "the others never left their fountains")
	print("TUTORIAL_%s" % ("PASS" if fails.is_empty() else "FAIL %s" % str(fails)))
	quit(0 if fails.is_empty() else 1)
