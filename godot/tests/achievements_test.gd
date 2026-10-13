extends SceneTree
# 0.31.119 (Kevin: "Do all" -- 8. Google Play Games achievements): scripts/meta/achievements.gd and play_games.gd
# against a fake of the Play Games plugin.
#   - every achievement has an id slot for Play Console (play_achievement_ids.gd) and a name/description within Play's
#     limits; goals within Play's incremental limits (2-10,000 steps)
#   - read from the profile (the server's account): tutorial, knockouts, wins, classes played, the Forge's 3 stars, level
#   - signed in: incremental ones as their steps (capped), standard ones unlocked once met; only what changed is sent
#     again; an achievement with no id yet is skipped
#   - Settings: ACHIEVEMENTS opens Google's screen when signed in
#   godot --headless --path godot -s res://tests/achievements_test.gd
const Achievements = preload("res://scripts/meta/achievements.gd")
const Ids = preload("res://scripts/meta/play_achievement_ids.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const PlayGames = preload("res://scripts/meta/play_games.gd")

var fails: Array = []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

class FakePlay extends Node:
	signal userAuthenticated(ok: bool)
	signal currentPlayerLoaded(json: String)
	signal gameLoaded(json: String)
	signal gameSaved(ok: bool, name: String, desc: String)
	signal conflictEmitted(json: String)
	var calls := []
	var shown := 0
	func initialize() -> void:
		pass
	func isAuthenticated() -> void:
		userAuthenticated.emit(true)
	func loadCurrentPlayer(_f: bool) -> void:
		currentPlayerLoaded.emit(JSON.stringify({"displayName":"Midblade"}))
	func loadGame(_n: String, _c: bool) -> void:
		gameLoaded.emit("null")
	func saveGame(name: String, desc: String, _b: PackedByteArray, _t: int, _p: int) -> void:
		gameSaved.emit(true, name, desc)
	func setAchievementSteps(id: String, n: int) -> void:
		calls.append(["steps", id, n])
	func unlockAchievement(id: String) -> void:
		calls.append(["unlock", id])
	func showAchievements() -> void:
		shown += 1

var frames := 0
var pg
var fake
var prof

func _init() -> void:
	var keys := {}
	var ok_list := true
	for a in Achievements.LIST:
		keys[a.key] = true
		ok_list = ok_list and Ids.IDS.has(a.key) and str(a.name).length() <= 100 and str(a.desc).length() <= 500 \
			and (not bool(a.inc) or (int(a.n) >= 2 and int(a.n) <= 10000))
	check(ok_list and keys.size() == Achievements.LIST.size() and Ids.IDS.size() == keys.size(), "%d achievements, each with an id slot, within Play's limits" % keys.size())
	var p = Profile.new("user://achtest-%d.json" % Time.get_ticks_usec(), "user://none.json")
	p.load_or_create()
	p.d.tutorial_done = true
	p.d.stats.kills = 140
	p.d.stats.wins = 3
	p.d.stats.best_streak = 2
	p.d.stats["main_knight"] = 2
	p.d.stats["main_mage"] = 1
	p.d.forge.stars["knight_wpn_oath"] = 3
	p.d.level = 7
	check(Achievements.value(p, "tutorial") == 1 and Achievements.value(p, "classes") == 2 and Achievements.value(p, "forge3") == 1
		and Achievements.value(p, "level") == 7 and Achievements.value(p, "kills") == 140, "read from the profile")
	var a = Achievements.new()
	var f := FakePlay.new()
	var ids := {}
	for k in Ids.IDS:
		ids[k] = "ID_" + k
	ids["slayer"] = ""                                       # (not made in Play Console yet)
	a.ids = ids
	a.sync(p, f)
	var unl: Array = f.calls.filter(func(c): return c[0] == "unlock").map(func(c): return c[1])
	var steps := {}
	for c in f.calls:
		if c[0] == "steps":
			steps[c[1]] = c[2]
	check(unl.has("ID_welcome") and unl.has("ID_first_blood") and unl.has("ID_first_victory") and unl.has("ID_master_smith")
		and not unl.has("ID_relentless") and not unl.has("ID_kings_rescue"), "standard ones unlocked once met: %s" % str(unl))
	check(int(steps.get("ID_centurion", -1)) == 100 and int(steps.get("ID_many_hats", -1)) == 2 and int(steps.get("ID_siege_lord", -1)) == 3
		and int(steps.get("ID_seasoned", -1)) == 7 and not steps.has("ID_slayer") and not steps.has("ID_fattening"),
		"incremental ones as steps, capped at the goal; no id yet: skipped; nothing for 0: %s" % str(steps))
	var n1: int = f.calls.size()
	a.sync(p, f)
	check(f.calls.size() == n1, "the same again: nothing sent")
	p.d.stats.wins = 4
	p.d.stats.best_streak = 5
	a.sync(p, f)
	check(f.calls.size() == n1 + 3 and f.calls.has(["steps", "ID_legend", 4]) and f.calls.has(["steps", "ID_siege_lord", 4]) and f.calls.has(["unlock", "ID_relentless"]), "what changed goes up: %s" % str(f.calls.slice(n1)))
	# play_games.gd: synced while signed in; Settings' button
	prof = Profile.new("user://achtest2-%d.json" % Time.get_ticks_usec(), "user://none.json")
	prof.load_or_create()
	prof.d.tutorial_done = true
	fake = FakePlay.new()
	root.add_child(fake)
	pg = PlayGames.new()
	root.add_child(pg)
	pg.achievements.ids = ids
	pg.setup(prof, fake)

func _process(delta: float) -> bool:
	frames += 1
	if frames == 3:
		check(pg.signed_in(), "signed in (the fake)")
		pg._ach_clock = PlayGames.ACH_EVERY            # (the next look now)
	elif frames == 6:
		check(fake.calls.has(["unlock", "ID_welcome"]), "signed in: play_games.gd sends them on its own")
		pg.show_achievements()
		check(fake.shown == 1, "ACHIEVEMENTS: Google's screen")
		var src := FileAccess.get_file_as_string("res://scripts/app/screens.gd")
		check(src.contains("\"ACHIEVEMENTS\"") and src.contains("pg.show_achievements()"), "Settings > GOOGLE PLAY has ACHIEVEMENTS when signed in")
		print("ACHIEVEMENTS_PASS" if fails.is_empty() else "ACHIEVEMENTS_FAIL %s" % str(fails))
		quit(0 if fails.is_empty() else 1)
	return false
