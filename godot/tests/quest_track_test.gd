extends SceneTree
# Class quests in a match (0.31.97): siege_mode credits what my unit does to the class I'm wearing at the time -- the
# seconds played, knockouts, rescues, gate damage, healing, repairs (events), King lifts (events) and the best burst
# (events) -- a Knight apart from a Crusader, nothing while a villager; the match summary carries it to the profile.
const Mode = preload("res://scripts/siege/siege_mode.gd")
var mode
var frames := 0
var fails: Array = []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	mode = Mode.new()
	mode.size = Vector2(420, 780)
	root.add_child(mode)

func _process(_d: float) -> bool:
	frames += 1
	var u: Dictionary = mode.sim.by_id.get("you", {}) if mode.sim != null else {}
	if u.is_empty():
		return false
	match frames:
		3:
			u.bot = false
			u.cls = "villager"
			u.up = false
			u.kills = 2                                   # as a villager: not credited
		6:
			u.cls = "knight"
			u.state = "idle"
		9:
			u.kills = 5                                   # +3 as a Knight
			u.rescues = 1
			u.gate_dmg = 250.0
			mode._count({"k": "repair", "id": "you"})
			mode._count({"k": "multikill", "id": "you", "n": 3})
		12:
			u.up = true                                   # the Crusader hat
		15:
			u.kills = 9                                   # +4 as a Crusader
			u["healed"] = 300.0
			mode._count({"k": "lift_join", "id": "you", "team": int(u.team)})
		20:
			var q: Dictionary = mode.title_summary().get("q", {})
			var kn: Dictionary = q.get("knight", {})
			var cr: Dictionary = q.get("crusader", {})
			check(int(kn.get("kills", -1)) == 3 and int(cr.get("kills", -1)) == 4, "knockouts split by the class worn (knight %s, crusader %s)" % [str(kn.get("kills")), str(cr.get("kills"))])
			check(not q.has("villager"), "nothing credited to a villager")
			check(int(kn.get("rescues", 0)) == 1 and int(kn.get("gates", 0)) == 2 and int(kn.get("repaired", 0)) > 0 and int(kn.get("best_multi", 0)) == 3,
				"the Knight's rescue, gate damage (per 100), repair and burst")
			check(int(cr.get("healed", 0)) == 300 and int(cr.get("lifts", 0)) == 1, "the Crusader's healing and King lift")
			check(float(kn.get("t", 0.0)) > 0.0 and float(cr.get("t", 0.0)) > 0.0, "time played as each")
			print("QUEST_TRACK_PASS" if fails.is_empty() else "QUEST_TRACK_FAIL %s" % str(fails))
			quit(0 if fails.is_empty() else 1)
	return false
