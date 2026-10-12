extends SceneTree
# 0.31.110 (Kevin: "I want more menu sound effects. Also make it so the audio sliders are max by default"):
#  - every cue the menus play (sfx("...") in the app's scripts, and the ones picked at run time) has its WAV and plays
#    on the effects slider (native_audio's menu list), not the combat one;
#  - a new profile's sliders are at 100%, and native_audio starts at 100% before the profile's levels arrive;
#  - once, a slider still on its old default (80 / 80 / 60) goes to 100%; one someone moved stays, and after that
#    a slider set to 80% stays at 80%.
#   godot --headless --path godot -s res://tests/menu_sound_test.gd
const Profile = preload("res://scripts/meta/profile.gd")
const Audio = preload("res://scripts/native_audio.gd")

var fails: Array = []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _scan(dir: String, out: Array) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	for f in da.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in da.get_directories():
		_scan(dir.path_join(d), out)

func _init() -> void:
	# ---- the cues
	var files: Array = []
	_scan("res://scripts/app", files)
	var re := RegEx.new()
	re.compile("sfx\\(\"([A-Za-z]+)\"")
	var cues := {}
	for f in files:
		var src := FileAccess.get_file_as_string(f)
		for m in re.search_all(src):
			cues[m.get_string(1)] = true
	# picked at run time: the chest card by rarity, the results by the match, the Forge's shop open / close, a quest's legendary
	for c in ["revealRare", "revealEpic", "revealLegendary", "resultWin", "resultLose", "levelUp", "tierUp", "menuOpen",
			"menuClose", "gemPack", "purchase", "ember", "coin", "gem", "slider", "toggle", "unlock", "premium", "tab"]:
		cues[c] = true
	var audio_src := FileAccess.get_file_as_string("res://scripts/native_audio.gd")
	var missing := []
	var not_ui := []
	for c in cues:
		if not ResourceLoader.exists("res://assets/sounds/%s.wav" % c):
			missing.append(c)
		if audio_src.find("\"%s\"" % c) < 0:
			not_ui.append(c)
	check(cues.size() >= 25 and missing.is_empty(), "every menu cue has its sound (%d cues) %s" % [cues.size(), str(missing)])
	check(not_ui.is_empty(), "and plays on the effects slider %s" % str(not_ui))
	for c in ["tab", "menuOpen", "toggle", "slider", "unlock", "premium", "tierUp", "revealRare", "revealEpic", "revealLegendary",
			"gemPack", "levelUp", "resultWin", "resultLose"]:
		var st = load("res://assets/sounds/%s.wav" % c)
		var n: float = st.get_length() if st != null else 0.0
		check(n > 0.02 and n < 2.0, "%s: %.2f s" % [c, n])
	# ---- 100% by default
	var a = Audio.new()
	check(a.levels.values().all(func(v): return is_equal_approx(float(v), 1.0)), "native_audio starts at 100%")
	a.free()
	var p = Profile.new("user://snd-%d.json" % Time.get_ticks_usec(), "user://none.json")
	p.load_or_create()
	var s: Dictionary = p.d.settings
	check(is_equal_approx(float(s.master), 1.0) and is_equal_approx(float(s.sfx), 1.0) and is_equal_approx(float(s.music), 1.0),
		"a new profile's sliders are at 100%")
	p.d.settings.master = 0.8                         # set by hand on a new install, before the app restarts
	p.save()
	var p2 = Profile.new(p.path, "user://none.json")
	p2.load_or_create()
	check(is_equal_approx(float(p2.d.settings.master), 0.8), "a new install's slider set to 80% stays 80% after a restart (%.2f)" % float(p2.d.settings.master))
	# ---- the old defaults move up once
	var old: Dictionary = p.d.duplicate(true)
	old.settings = {"master":0.8, "music":0.6, "sfx":0.8, "reduce_motion":false}
	var n1: Dictionary = p._normalized(old).settings
	check(is_equal_approx(float(n1.master), 1.0) and is_equal_approx(float(n1.sfx), 1.0) and is_equal_approx(float(n1.music), 1.0) and bool(n1.audio_max),
		"an old profile on the old defaults: 100%")
	var moved: Dictionary = p.d.duplicate(true)
	moved.settings = {"master":0.8, "music":0.3, "sfx":0.45, "reduce_motion":true}
	var n2: Dictionary = p._normalized(moved).settings
	check(is_equal_approx(float(n2.master), 1.0) and is_equal_approx(float(n2.music), 0.3) and is_equal_approx(float(n2.sfx), 0.45) and bool(n2.reduce_motion),
		"moved sliders stay where they were put (master %.2f, music %.2f, effects %.2f)" % [float(n2.master), float(n2.music), float(n2.sfx)])
	var later: Dictionary = p.d.duplicate(true)
	later.settings = {"master":0.8, "music":0.6, "sfx":0.8, "audio_max":true}
	var n3: Dictionary = p._normalized(JSON.parse_string(JSON.stringify(later))).settings
	check(is_equal_approx(float(n3.master), 0.8) and is_equal_approx(float(n3.music), 0.6), "after that, 80% set by hand stays 80% (saved and loaded)")
	print("MENU_SOUND_PASS" if fails.is_empty() else "MENU_SOUND_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
