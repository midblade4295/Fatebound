extends SceneTree
# 0.31.37: chests -- earned by playing, four slots, one unlocking at a time, gems to skip, contents rolled on opening.
const Profile = preload("res://scripts/meta/profile.gd")
const Eco = preload("res://scripts/meta/economy.gd")
var fails := []
func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok: fails.append(what)
func _init():
	randomize()
	var base := "user://chest-test-%d-%d" % [int(Time.get_unix_time_from_system() * 1000.0), randi()]
	var p := Profile.new(base + "-profile.json", base + "-legacy.json")
	p.now_override = 1791000000
	p.load_or_create()
	var me := {"team":0, "cls":"knight", "rescues":0, "kills":5}
	var r1: Dictionary = p.apply_match(me, true, false, false)
	check(r1.chests.size() == 2 and r1.chests[0].kind == "wooden" and r1.chests[1].kind == "silver", "a win: a Wooden chest, plus a Silver for the first win of the day (%s)" % str(r1.chests))
	var r2: Dictionary = p.apply_match({"team":0, "cls":"knight", "rescues":1}, true, false, false)
	check(r2.chests.size() == 1 and r2.chests[0].kind == "silver", "a win with a rescue: Silver")
	var r3: Dictionary = p.apply_match({"team":0, "cls":"knight", "best_multi":2}, true, false, false)
	check(r3.chests[0].kind == "silver", "a win with a multi-kill: Silver")
	check(p.chests().size() == 4, "four slots filled")
	var gold0: int = p.d.gold
	var r4: Dictionary = p.apply_match({"team":0, "cls":"knight"}, true, false, false)
	check(bool(r4.chests[0].full) and int(p.d.gold) >= gold0 + int(Eco.CHEST_FULL_GOLD.wooden), "slots full: the chest becomes gold")
	var r5: Dictionary = p.apply_match({"team":0, "cls":"knight", "rescues":3}, false, false, false)
	check(r5.chests.is_empty(), "a loss earns no chest")
	# unlocking
	check(p.start_unlock(0) and not p.start_unlock(1), "one chest unlocks at a time")
	check(p.chest_left(p.chests()[0]) == int(Eco.CHESTS.wooden.unlock), "the timer starts at the chest's full time")
	p.now_override += 1000
	check(not p.chest_ready(p.chests()[0]), "not ready before its time")
	p.now_override += int(Eco.CHESTS.wooden.unlock)
	check(p.chest_ready(p.chests()[0]), "ready when the time is up")
	var o: Dictionary = p.open_chest(0)
	check(bool(o.ok) and int(o.gold) >= 60 and p.chests().size() == 3, "opened: gold and the slot freed (%s)" % str(o))
	# skipping with gems
	var silver: Dictionary = p.chests()[0]
	var cost := Eco.skip_cost(p.chest_left(silver))
	check(cost == 18, "skipping a 3 h Silver chest costs 18 gems (%d)" % cost)
	p.d.gems = 5
	check(not bool(p.skip_chest(0).ok), "not without the gems")
	p.d.gems = 100
	check(bool(p.skip_chest(0).ok) and int(p.d.gems) == 82 and p.chest_ready(p.chests()[0]), "with them: ready at once, gems paid")
	check(bool(p.open_chest(0).ok), "and opened")
	# rolls: deterministic, bad-luck protection on Gold chests
	check(str(Eco.roll_chest("gold", 42, [], 0)) == str(Eco.roll_chest("gold", 42, [], 0)), "the same chest always rolls the same (no re-roll by reloading)")
	var pity := 0
	var since := 0
	var worst := 0
	for i in 200:
		var rr := Eco.roll_chest("gold", i * 7919, [], pity)
		pity = int(rr.pity)
		var rar := str(Eco.item(str(rr.item)).get("rarity", "")) if str(rr.item) != "" else ""
		since = 0 if rar in ["epic", "legendary"] else since + 1
		worst = maxi(worst, since)
	check(worst < Eco.PITY_EPIC, "an epic at least every %d Gold chests (longest gap %d)" % [Eco.PITY_EPIC, worst])
	var all_owned: Array = Eco.chest_pool("epic") + Eco.chest_pool("legendary") + Eco.chest_pool("rare") + Eco.chest_pool("common")
	var dup := Eco.roll_chest("royal", 7, all_owned, 0)
	check(str(dup.item) == "" and int(dup.dupe_gold) >= 600, "a cosmetic you own turns into gold (%d)" % int(dup.dupe_gold))
	check(Eco.chest_odds("silver").contains("75%") and Eco.chest_odds("gold").contains("every 10"), "the odds read out plainly")
	check(Eco.level_reward(5).get("chest", "") == "gold" and Eco.level_reward(10).get("chest", "") == "royal", "levels 5 and 10 give Gold and Royal chests")
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with(base.get_file()):
			DirAccess.remove_absolute("user://" + f)
	print("CHEST_PASS" if fails.is_empty() else "CHEST_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
