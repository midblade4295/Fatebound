extends SceneTree
# Match sound (0.30.8): play a bot match with a recording stand-in for the audio player and check the sounds that
# should play do, that every cue named exists as a file, and that far-off units are culled.
const Mode = preload("res://scripts/siege/siege_mode.gd")
var mode
var rec: Node
var frames := 0
var fails := []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	var sc := GDScript.new()
	sc.source_code = "extends Node\nvar played := {}\nvar vols := []\nvar muted := false\nvar levels := {\"master\":0.75, \"combat\":0.8, \"ui\":0.75}\nfunc play(cue: String, quiet := false, vol := 1.0) -> void:\n\tplayed[cue] = int(played.get(cue, 0)) + 1\n\tvols.append(vol)\n"
	sc.reload()
	rec = Node.new()
	rec.set_script(sc)
	root.add_child(rec)
	mode = Mode.new()
	mode.audio = rec
	root.add_child(mode)

func _process(_d: float) -> bool:
	frames += 1
	if mode.sim != null and frames > 5:
		for i in 6:
			mode.sim.step(mode.Sim.TICK)
		for e in mode.sim.drain_events():
			mode._event_sound(e)
		var me: Dictionary = mode.sim.by_id.get(str(mode.hud.player_id), {})
		if not me.is_empty():
			mode.sim.set_move(mode.hud.player_id, Vector2(0.3, -1.0).normalized())
		mode._footsteps(0.2)
	if frames < 900:
		return false
	var played: Dictionary = rec.played
	print("cues: ", played)
	var missing := []
	for cue in played:
		if not ResourceLoader.exists("res://assets/sounds/%s.wav" % cue):
			missing.append(cue)
	check(missing.is_empty(), "every cue played exists as a file (missing: %s)" % str(missing))
	var src := FileAccess.get_file_as_string("res://scripts/siege/siege_mode.gd")
	var rx := RegEx.new()
	rx.compile("_cue\\(\"(tm_[a-z_]+)\", (\\d)")
	var bad := []
	for m in rx.search_all(src):
		var n := int(m.get_string(2))
		for k in range(1, n + 1):
			var f := "res://assets/sounds/%s%s.wav" % [m.get_string(1), str(k) if n > 1 else ""]
			if not ResourceLoader.exists(f):
				bad.append(f)
	for surf in ["dirt", "stone", "wood", "water"]:
		for ch in ["", "_chain"]:
			for k in range(1, 6):
				if not ResourceLoader.exists("res://assets/sounds/tm_step_%s%s%d.wav" % [surf, ch, k]):
					bad.append("tm_step_%s%s%d" % [surf, ch, k])
	for a in ["forest_day", "river", "waterfall"]:
		if not ResourceLoader.exists("res://assets/sounds/ambience/%s.ogg" % a):
			bad.append(a)
	check(bad.is_empty(), "every sound the code can ask for exists (%s)" % str(bad))
	var swings := 0
	var hits := 0
	var steps := 0
	for cue in played:
		if cue.begins_with("tm_sword_swing") or cue.begins_with("tm_bow_shot") or cue.begins_with("tm_fireball"):
			swings += int(played[cue])
		if cue.begins_with("tm_sword_hit") or cue.begins_with("tm_bow_hit") or cue.begins_with("tm_spell_hit"):
			hits += int(played[cue])
		if cue.begins_with("tm_step_"):
			steps += int(played[cue])
	check(swings > 0 and hits > 0, "attacks and hits near you are heard (%d, %d)" % [swings, hits])
	# Footsteps by surface, under control: walk the player across known spots.
	var me: Dictionary = mode.sim.by_id.get(str(mode.hud.player_id), {})
	var Land = preload("res://scripts/siege/siege_land.gd")
	var spots := {"dirt": Vector2(-11.0, 24.0), "water": Vector2(10.0, Land.river_c(10.0)),
		"wood": (Land.bridges()[0].c as Vector2), "stone": Vector2(0.0, mode.Sim.CASTLE_SHIFT + mode.Sim.FRONT_Z + 6.0)}
	for surf in spots:
		me.hp = me.max_hp
		me.state = "idle"
		var start: Vector2 = spots[surf]
		me.pos = start
		mode._footsteps(0.1)
		var before := 0
		for cue in rec.played:
			if str(cue).begins_with("tm_step_" + surf):
				before += int(rec.played[cue])
		for i in 12:
			me.pos = start + Vector2(0.0, 0.5 * (i + 1) * (1.0 if surf != "stone" else 0.4))
			mode._footsteps(0.1)
		var after := 0
		for cue in rec.played:
			if str(cue).begins_with("tm_step_" + surf):
				after += int(rec.played[cue])
		check(after - before >= 2, "walking on %s plays %s footsteps (%d)" % [surf, surf, after - before])
	var quiet := 0
	for v in rec.vols:
		if float(v) < 0.99:
			quiet += 1
	check(quiet > 0, "sounds further off play quieter (%d of %d)" % [quiet, rec.vols.size()])
	print("MATCH_AUDIO_PASS" if fails.is_empty() else "MATCH_AUDIO_FAIL %d" % fails.size())
	quit()
	return true
