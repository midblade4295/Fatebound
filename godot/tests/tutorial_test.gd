extends SceneTree
# Plays the Herald's tutorial end to end like a player (tutorial.gd): advance the talk, then do
# each task through the sim (walk, hat shop, hit the dummy, dodge, block, workshop, upgrade at the
# hat shop, capture the outpost, head for the river), and finish. Also checks the script itself:
# every line has a unique voice id and text.
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Tutorial = preload("res://scripts/siege/tutorial.gd")
var mode
var frames := 0
var done_steps := []
var exited := false
var fails := []
var last_step := -1
var t_step := 0.0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	# The script: unique ids, no empty lines.
	var ids := {}
	var n := 0
	for st in Tutorial.STEPS:
		for key in ["talk", "done"]:
			for ln in st.get(key, []):
				n += 1
				var id := str(ln[0])
				if not id.begins_with("t_") or ids.has(id) or str(ln[1]).length() <= 10:
					check(false, "line %s has a unique id and text" % id)
				ids[id] = true
	check(ids.size() == n and n >= 25, "script: %d lines, all ids unique" % n)
	# The Herald's recordings (Kevin's ElevenLabs read, split per line): every line has one.
	var missing := []
	var short := []
	for id in ids:
		var path := "res://assets/vo/tutorial/%s.ogg" % id
		if not ResourceLoader.exists(path):
			missing.append(id)
			continue
		var st: AudioStream = load(path)
		if st == null or st.get_length() < 1.5:
			short.append(id)
	check(missing.is_empty(), "every line has its voice file (missing: %s)" % str(missing))
	check(short.is_empty(), "every voice file loads and is a real line (>= 1.5 s; bad: %s)" % str(short))
	mode = Mode.new()
	mode.tutorial = true
	root.add_child(mode)
	mode.exited.connect(func(): exited = true)

func _process(delta: float) -> bool:
	frames += 1
	if frames == 3:
		mode.set_fps_cap(0)
	if frames < 5:
		return false
	var tut = mode.tut
	var s = mode.sim
	if frames == 5 and tut != null:
		check(tut.voice.playing and tut.voice.stream != null, "the Herald's first line plays its recording")
	if tut == null:
		check(false, "the tutorial overlay exists"); quit(1); return false
	var me: Dictionary = s.by_id[mode.hud.player_id]
	if tut.step != last_step:
		last_step = tut.step
		t_step = 0.0
	t_step += delta
	if t_step > 40.0:
		check(false, "step %s finished within 40 s (phase %s)" % [str(Tutorial.STEPS[tut.step].id), tut.phase]); _end(); return false
	if exited:
		_end(); return false
	if tut.finished:
		check(done_steps.size() >= 12, "all %d tasks done: %s" % [done_steps.size(), str(done_steps)])
		check(int(s.score[int(me.team)]) >= 1, "the rescue scored")
		tut.next()                             # FINISH
		return false
	match str(tut.phase):
		"talk", "done":
			tut.next()
		"task":
			var id := str(Tutorial.STEPS[tut.step].id)
			if not done_steps.has(id):
				done_steps.append(id)
			match id:
				"move":
					me.pos += Vector2(0, -7.0)
				"hat", "upgrade":
					var st: Dictionary = tut._stand(me.team, "knight")
					me.pos = st.p + (Sim.spawn(me.team) - (st.p as Vector2)).normalized() * 0.9
					if id == "upgrade":
						s.act(mode.hud.player_id, "interact")
				"attack":
					var foe: Dictionary = s.by_id.get(tut._dummy_id, {})
					if not foe.is_empty():
						# Walk up to it (it stands in the open courtyard now), then swing.
						if me.pos.distance_to(foe.pos) > 1.6:
							me.pos = (foe.pos as Vector2) + Vector2(1.2, 0)
						me.face = Sim.angle_of(foe.pos - me.pos)
						s.act(mode.hud.player_id, "attack")
				"dodge":
					s.act(mode.hud.player_id, "dodge")
				"block":
					s.act(mode.hud.player_id, "ability")
				"workshop":
					me.pos = Sim.workshop(me.team)
				"outpost":
					var op: Dictionary = tut._outpost(me.team)
					me.pos = (op.p as Vector2) + Vector2(2.2, 0)
				"cake":
					var ct: Dictionary = tut._cake_tree(me)
					me.pos = (ct.p as Vector2) + Vector2(1.3, 0)
					s.act(mode.hud.player_id, "interact")
				"feed":
					me.pos = (s.oracles[1 - int(me.team)].pos as Vector2) + Vector2(0.6, 0)
					s.act(mode.hud.player_id, "interact")
				"grab":
					me.pos = (s.oracles[int(me.team)].pos as Vector2) + Vector2(0.6, 0)
					s.act(mode.hud.player_id, "interact")
				"carry":
					me.pos = Sim.throne(me.team)
	return false

func _end() -> void:
	check(exited, "finishing the tutorial returns to the menu")
	print("TUTORIAL_PASS" if fails.is_empty() else "TUTORIAL_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
