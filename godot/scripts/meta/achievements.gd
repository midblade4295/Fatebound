extends RefCounted
# 0.31.119 (Kevin: "Do all" -- 8. Play Games achievements): what the game reports to Google Play Games. Each achievement
# reads the profile -- the account the server keeps (0.31.108), so they can't be faked by editing a save -- and is sent
# through the Play Games plugin (scripts/meta/play_games.gd) while the player is signed in: an "incremental" one as its
# steps (setAchievementSteps: never goes back, so sending the total again is harmless), a standard one unlocked once
# its goal is met. Only what changed since the last send goes out. The ids are Play Console's
# (scripts/meta/play_achievement_ids.gd, empty until they're made there -- see godot/PLAY_ACHIEVEMENTS_HANDOFF.md).
# 0.31.130 (the iOS port): the same list goes to Game Center (scripts/meta/game_center.gd) with Apple's ids
# (gc_achievement_ids.gd) as percentages -- sync_percent; what is counted and when it is sent is the same code.
const Eco = preload("res://scripts/meta/economy.gd")
const Ids = preload("res://scripts/meta/play_achievement_ids.gd")

# key, name, description (as Play Console shows them), what's counted, the goal, incremental (steps) or not, the icon
const LIST := [
	{"key":"welcome", "name":"Welcome to the Siege", "desc":"Finish the tutorial.", "stat":"tutorial", "n":1, "inc":false, "icon":"castle", "xp":5},
	{"key":"first_blood", "name":"First Blood", "desc":"Knock out an enemy.", "stat":"kills", "n":1, "inc":false, "icon":"skull", "xp":5},
	{"key":"first_victory", "name":"First Victory", "desc":"Win a match.", "stat":"wins", "n":1, "inc":false, "icon":"trophy", "xp":10},
	{"key":"kings_rescue", "name":"Long Live the King", "desc":"Carry your King home from the enemy dungeon.", "stat":"rescues", "n":1, "inc":false, "icon":"crown", "xp":10},
	{"key":"many_hats", "name":"Many Hats", "desc":"Play a match as each of the 7 classes.", "stat":"classes", "n":7, "inc":true, "icon":"helmet", "xp":20},
	{"key":"fattening", "name":"Fattening Season", "desc":"Feed 25 fish to the enemy King.", "stat":"fed", "n":25, "inc":true, "icon":"fish", "xp":15},
	{"key":"lumberjack", "name":"Lumberjack", "desc":"Gather 500 wood or stone.", "stat":"gathered", "n":500, "inc":true, "icon":"stall", "xp":15},
	{"key":"gatecrasher", "name":"Gatecrasher", "desc":"Deal 10,000 damage to enemy gates.", "stat":"gates", "n":100, "inc":true, "icon":"swords", "xp":20},
	{"key":"heavy_lifting", "name":"Heavy Lifting", "desc":"Help lift your King 50 times.", "stat":"lifts", "n":50, "inc":true, "icon":"crown", "xp":20},
	{"key":"centurion", "name":"Centurion", "desc":"Knock out 100 enemies.", "stat":"kills", "n":100, "inc":true, "icon":"skull", "xp":20},
	{"key":"relentless", "name":"Relentless", "desc":"Win 5 matches in a row.", "stat":"best_streak", "n":5, "inc":false, "icon":"banner", "xp":30},
	{"key":"unstoppable", "name":"Unstoppable", "desc":"Knock out 5 enemies in one burst.", "stat":"best_multi", "n":5, "inc":false, "icon":"swords", "xp":40},
	{"key":"bodyguard", "name":"Royal Bodyguard", "desc":"Rescue your King 25 times.", "stat":"rescues", "n":25, "inc":true, "icon":"crown", "xp":40},
	{"key":"seasoned", "name":"Seasoned", "desc":"Reach level 20.", "stat":"level", "n":20, "inc":true, "icon":"banner", "xp":40},
	{"key":"siege_lord", "name":"Siege Lord", "desc":"Win 50 matches.", "stat":"wins", "n":50, "inc":true, "icon":"castle", "xp":60},
	{"key":"slayer", "name":"Slayer of Thousands", "desc":"Knock out 1,000 enemies.", "stat":"kills", "n":1000, "inc":true, "icon":"skull", "xp":80},
	{"key":"legend", "name":"Legend of the Siege", "desc":"Win 250 matches.", "stat":"wins", "n":250, "inc":true, "icon":"trophy", "xp":100},
]

# 0.31.188: gone from the game but published -- Play Console and Game Center keep them (Kevin can hide them there); this
# app no longer reports them. "master_smith", Master Smith: forge a weapon to 3 stars (0.31.119-0.31.187, the Forge).
const RETIRED := ["master_smith"]

var sent := {}                     # key -> the value last sent (this run)
var ids: Dictionary = Ids.IDS      # (tests put their own)

static func value(profile, stat: String) -> int:
	var d: Dictionary = profile.d
	match stat:
		"tutorial":
			return 1 if bool(d.get("tutorial_done", false)) else 0
		"classes":
			var n := 0
			for c in Eco.CLASSES:
				if int(d.stats.get("main_" + c, 0)) > 0:
					n += 1
			return n
		"level":
			return int(d.get("level", 1))
	return int(d.stats.get(stat, 0))

func id_of(key: String) -> String:
	return str(ids.get(key, ""))

func sync(profile, plugin) -> int:
	# -> calls made. Google Play Games: standard ones unlocked once their goal is met, incremental ones as their steps
	# (capped at the goal) when they grew.
	if profile == null or plugin == null:
		return 0
	return _each_change(profile, func(id: String, v: int, _n: int, inc: bool) -> void:
		if inc:
			plugin.setAchievementSteps(id, v)
		else:
			plugin.unlockAchievement(id))

func sync_percent(profile, report: Callable) -> int:
	# 0.31.130 (the iOS port): Game Center has no incremental kind -- each one is reported as its percent done
	# (100 * steps / goal, the same steps as Play), a standard one as 100 once met. report(id, percent).
	if profile == null or not report.is_valid():
		return 0
	return _each_change(profile, func(id: String, v: int, n: int, inc: bool) -> void:
		report.call(id, 100.0 * v / n if inc else 100.0))

func _each_change(profile, send: Callable) -> int:
	# what changed since the last send (this run), the same for every service: send(id, steps, goal, incremental)
	var calls := 0
	for a in LIST:
		var id := id_of(str(a.key))
		if id == "":
			continue
		var n := int(a.n)
		var v := mini(value(profile, str(a.stat)), n)
		if v <= int(sent.get(a.key, 0)):
			continue
		if not bool(a.inc) and v < n:
			continue
		send.call(id, v, n, bool(a.inc))
		calls += 1
		sent[a.key] = v
	return calls

static func configured() -> int:
	# the achievements in the game with a Play Console id (0.31.188: not the retired ones)
	var n := 0
	for a in LIST:
		if str(Ids.IDS.get(str(a.key), "")) != "":
			n += 1
	return n
