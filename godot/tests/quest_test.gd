extends SceneTree
# Class quests (0.31.97, Kevin: "Build the quest system and I want quests for each class"): the table (13 classes, 3
# steps; the last gives 100 gems and a Royal chest -- 0.31.189; 150 in 0.31.188, a legendary weapon until then), counting a match per
# class worn (a base class counts its upgrade, an upgrade only itself, a match only after a minute), claiming in order
# with the rewards, saving, and the screens -- Home's QUESTS button, the Quests screen's CLAIM. (The Locker's quest card
# went with its ARMORY, 0.31.188.)
const Eco = preload("res://scripts/meta/economy.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const View = preload("res://scripts/siege/siege_view.gd")
const App = preload("res://scripts/app/siege_app.gd")
const Screens = preload("res://scripts/app/screens.gd")
var fails: Array = []
var app
var frames := 0
var step := 0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func fresh(tag: String) -> Profile:
	var p := Profile.new("user://quest_test_%s_%d.json" % [tag, Time.get_ticks_usec()], "user://none_%d.json" % Time.get_ticks_usec())
	p.load_or_create()
	return p

func me(q: Dictionary) -> Dictionary:
	return {"cls":"knight", "kills":0, "rescues":0, "gathered":0, "fed":0, "gate_dmg":0.0, "lifts":0, "q":q}

func _init() -> void:
	# ---- the table
	check(Eco.QUESTS.size() == 13, "a quest for each of the 13 classes (%d)" % Eco.QUESTS.size())
	var bad := []
	for cls in Eco.CLASSES + Eco.UP_CLASSES:
		var q: Dictionary = Eco.QUESTS.get(cls, {})
		var ok: bool = not q.is_empty() and q.steps.size() == 3 and not q.has("item") and Eco.quest_reward(cls, 2) == Eco.QUEST_FINAL
		for s in q.get("steps", []):
			ok = ok and int(s.n) > 0 and str(s.task) != "" and (str(s.stat) in Eco.QUEST_COUNTS or str(s.stat) in ["wins", "matches", "best_multi"])
		if not ok:
			bad.append(cls)
	check(bad.is_empty(), "each quest: 3 steps, the last 100 gems and a Royal chest (no weapon, 0.31.188) %s" % str(bad))
	check(Eco.QUEST_FINAL == {"gems": 100, "chest": "royal"}, "the final reward: %s" % str(Eco.QUEST_FINAL))
	check(Eco.quest_family("knight") == ["knight", "crusader"] and Eco.quest_family("crusader") == ["crusader"] and Eco.quest_family("worker") == ["worker"],
		"a base class counts its upgrade; an upgrade counts itself")
	# ---- counting
	var p := fresh("count")
	var out: Dictionary = p.apply_match(me({"knight": {"t": 120.0, "kills": 5, "rescues": 2}, "crusader": {"t": 90.0, "kills": 3, "best_multi": 2}}), true, false, false)
	var st: Dictionary = p.d.stats
	check(int(st.get("q_knight_wins", 0)) == 1 and int(st.get("q_knight_matches", 0)) == 1, "a won match as Knight and Crusader is one Knight win")
	check(int(st.get("q_knight_kills", 0)) == 8 and int(st.get("q_knight_rescues", 0)) == 2, "the Knight quest counts the Crusader's knockouts too (%d)" % int(st.get("q_knight_kills", 0)))
	check(int(st.get("q_crusader_kills", 0)) == 3 and int(st.get("q_crusader_wins", 0)) == 1 and int(st.get("q_crusader_best_multi", 0)) == 2,
		"the Crusader quest counts only the Crusader")
	check(int(st.get("q_barbarian_matches", 0)) == 0 and int(st.get("q_berserker_kills", 0)) == 0, "other classes untouched")
	var lines: Array = out.get("quests", [])
	var kl: Array = lines.filter(func(x): return str(x.cls) == "knight")
	check(kl.size() == 1 and int(kl[0].progress) == 1 and int(kl[0].goal) == 3 and not bool(kl[0].done), "the results line: Knight step 1, 1 of 3 wins")
	p.apply_match(me({"rogue": {"t": 40.0, "kills": 4}}), true, false, false)
	check(int(p.d.stats.get("q_rogue_matches", 0)) == 0 and int(p.d.stats.get("q_rogue_kills", 0)) == 4, "under a minute as a class: its knockouts count, the match doesn't")
	p.apply_match(me({"crusader": {"t": 70.0, "best_multi": 1}}), false, false, false)
	check(int(p.d.stats.get("q_crusader_best_multi", 0)) == 2 and int(p.d.stats.get("q_crusader_wins", 0)) == 1 and int(p.d.stats.get("q_crusader_matches", 0)) == 2,
		"a best stays the best; a loss counts as played, not won")
	# ---- claiming, in order
	var g0 := int(p.d.gold)
	check(not p.quest_ready("knight") and not bool(p.claim_quest("knight").ok), "nothing to claim before the step is done")
	p.d.stats["q_knight_wins"] = 3
	p.d.stats["q_knight_kills"] = 999          # step 3's goal reached early: still claimed in order
	check(p.quest_ready("knight") and p.quests_ready() == 1, "step 1 ready")
	var r1: Dictionary = p.claim_quest("knight")
	check(bool(r1.ok) and int(p.d.gold) == g0 + 700 and p.quest_step("knight") == 1, "step 1 pays 700 gold (0.31.184: 400 gold and 30 Embers)")
	check(not p.quest_ready("knight") and not bool(p.claim_quest("knight").ok), "step 3's goal reached doesn't skip step 2")
	p.d.stats["q_knight_towers"] = 10            # (0.31.164: step 2 is 10 towers -- it was 10 King rescues)
	var gem0 := int(p.d.gems)
	var ch0: int = p.d.chests.slots.size()
	var r2: Dictionary = p.claim_quest("knight")
	check(bool(r2.ok) and int(p.d.gems) == gem0 + 50 and p.d.chests.slots.size() == ch0 + 1 and str(p.d.chests.slots[-1].kind) == "gold", "step 2 pays 50 gems and a Gold chest")
	var gem1 := int(p.d.gems)
	var royal0: int = p.d.chests.slots.filter(func(c): return str(c.kind) == "royal").size() + p.chests_waiting()
	var r3: Dictionary = p.claim_quest("knight")
	var royal1: int = p.d.chests.slots.filter(func(c): return str(c.kind) == "royal").size() + p.chests_waiting()
	check(bool(r3.ok) and int(p.d.gems) == gem1 + 100 and royal1 == royal0 + 1 and not r3.has("item") and p.quest_done("knight"),
		"step 3 gives 100 gems and a Royal chest; the quest is done")
	check(not bool(p.claim_quest("knight").ok) and p.quests_ready() == 0, "nothing more to claim")
	# ---- saved and loaded
	p.d.quests["rogue"] = 9
	p.d.quests["nobody"] = 2
	p.save()
	var p2 := Profile.new(p.path, "user://none.json")
	p2.load_or_create()
	check(p2.quest_step("knight") == 3 and p2.quest_step("rogue") == 3 and not p2.d.quests.has("nobody") and int(p2.d.stats.get("q_knight_towers", 0)) == 10,
		"quests survive a reload; a bad value is clamped, an unknown class dropped")
	# ---- the screens
	var base := "user://quest_ui-%d" % Time.get_ticks_usec()
	app = App.new()
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	app.now_override = 1791000000
	root.add_child(app)

func _live(n: Node) -> bool:
	while n != null:
		if n.is_queued_for_deletion():
			return false
		n = n.get_parent()
	return true

func btn(key: String) -> Button:
	for c in root.find_children("*", "Button", true, false):
		if str(c.get_meta("action_key", "")) == key and (c as Control).is_visible_in_tree() and _live(c):
			return c
	return null

func press(key: String) -> bool:
	var b := btn(key)
	if b == null or b.disabled:
		check(false, "button %s present and enabled" % key)
		return false
	b.pressed.emit()
	return true

func _process(_d: float) -> bool:
	frames += 1
	if frames < 8:
		return false
	var p = app.profile
	match step:
		0:
			p.d.stats["q_mage_kills"] = 40
			app.rebuild()
			press("home_menu")                          # 0.31.194: QUESTS is in the top bar's menu
			check(btn("side_quests") != null, "Home's menu has QUESTS")
			press("side_quests")
			check(app.tab == "quests" and str(app.quest_cls) == "mage", "QUESTS opens on the class with a step ready (%s)" % str(app.quest_cls))
			check(btn("quest_claim_mage") != null and btn("quest_knight") != null and btn("quest_archmage") != null, "the Quests screen: the 12 hero classes and CLAIM")
		1:
			var g0 := int(p.d.gold)
			press("quest_claim_mage")
			check(p.quest_step("mage") == 1 and int(p.d.gold) == g0 + 700, "CLAIM pays step 1 (700 gold)")
			p.d.stats["q_mage_camps"] = 15            # (0.31.164: step 2 is 15 jungle camps -- it was 15 King lifts)
			p.d.stats["q_mage_wins"] = 60
			app.rebuild()
		2:
			press("quest_claim_mage")
			check(p.quest_step("mage") == 2, "step 2 claimed")
		3:
			var gm := int(p.d.gems)
			press("quest_claim_mage")
			check(p.quest_done("mage") and int(p.d.gems) == gm + 100 and btn("shop_preview_equip") == null, "the last step: 100 gems and a Royal chest, nothing to equip (0.31.188)")
		4:
			press("quests_back")
			check(app.tab == "home", "back to Home")
			app.show_tab("locker")
		5:
			check(btn("locker_quest_knight") == null and btn("locker_tab_heroes") != null, "the Armory (0.31.204, was the Locker): HEROES, OUTFITS, TITLES, no quest card")
			print("QUEST_PASS" if fails.is_empty() else "QUEST_FAIL %s" % str(fails))
			quit(0 if fails.is_empty() else 1)
	step += 1
	return false
