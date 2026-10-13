extends RefCounted
# 0.31.119 (Kevin: "Do all" -- 8. Play Games achievements): what the game reports to Google Play Games. Each achievement
# reads the profile -- the account the server keeps (0.31.108), so they can't be faked by editing a save -- and is sent
# through the Play Games plugin (scripts/meta/play_games.gd) while the player is signed in: an "incremental" one as its
# steps (setAchievementSteps: never goes back, so sending the total again is harmless), a standard one unlocked once
# its goal is met. Only what changed since the last send goes out. The ids are Play Console's
# (scripts/meta/play_achievement_ids.gd, empty until they're made there -- see godot/PLAY_ACHIEVEMENTS_HANDOFF.md).
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
	{"key":"master_smith", "name":"Master Smith", "desc":"Forge a weapon to 3 stars.", "stat":"forge3", "n":1, "inc":false, "icon":"anvil", "xp":40},
	{"key":"seasoned", "name":"Seasoned", "desc":"Reach level 20.", "stat":"level", "n":20, "inc":true, "icon":"banner", "xp":40},
	{"key":"siege_lord", "name":"Siege Lord", "desc":"Win 50 matches.", "stat":"wins", "n":50, "inc":true, "icon":"castle", "xp":60},
	{"key":"slayer", "name":"Slayer of Thousands", "desc":"Knock out 1,000 enemies.", "stat":"kills", "n":1000, "inc":true, "icon":"skull", "xp":80},
	{"key":"legend", "name":"Legend of the Siege", "desc":"Win 250 matches.", "stat":"wins", "n":250, "inc":true, "icon":"trophy", "xp":100},
]

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
		"forge3":
			for w in d.forge.get("stars", {}):
				if int(d.forge.stars[w]) >= 3:
					return 1
			return 0
		"level":
			return int(d.get("level", 1))
	return int(d.stats.get(stat, 0))

func id_of(key: String) -> String:
	return str(ids.get(key, ""))

func sync(profile, plugin) -> int:
	# -> calls made. Standard: unlocked once its goal is met. Incremental: its steps (capped at the goal) when they grew.
	if profile == null or plugin == null:
		return 0
	var calls := 0
	for a in LIST:
		var id := id_of(str(a.key))
		if id == "":
			continue
		var n := int(a.n)
		var v := mini(value(profile, str(a.stat)), n)
		if v <= int(sent.get(a.key, 0)):
			continue
		if bool(a.inc):
			plugin.setAchievementSteps(id, v)
			calls += 1
		elif v >= n:
			plugin.unlockAchievement(id)
			calls += 1
		else:
			continue
		sent[a.key] = v
	return calls

static func configured() -> int:
	var n := 0
	for k in Ids.IDS:
		if str(Ids.IDS[k]) != "":
			n += 1
	return n
