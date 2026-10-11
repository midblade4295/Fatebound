extends SceneTree
# Class quests (0.31.97, Kevin: "Build the quest system and I want quests for each class"): the table (13 classes, 3
# steps, a legendary each that is never sold), counting a match per class worn (a base class counts its upgrade, an
# upgrade only itself, a match only after a minute), claiming in order with the rewards, saving, and the screens --
# Home's QUESTS button, the Quests screen's CLAIM, the legendary shown with EQUIP, the Locker's quest card.
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
	var items := {}
	for cls in Eco.CLASSES + Eco.UP_CLASSES:
		var q: Dictionary = Eco.QUESTS.get(cls, {})
		var it: Dictionary = Eco.CATALOG.get(str(q.get("item", "")), {})
		var ok: bool = not q.is_empty() and q.steps.size() == 3 and not it.is_empty() and str(it.kind) == "weapon" \
			and str(it["class"]) == cls and str(it.rarity) == "legendary" and str(it.source) == "quest" and not it.has("gold") and not it.has("gems")
		for s in q.get("steps", []):
			ok = ok and int(s.n) > 0 and str(s.task) != "" and (str(s.stat) in Eco.QUEST_COUNTS or str(s.stat) in ["wins", "matches", "best_multi"])
		for hand in ["r", "l"]:
			var f := str(it.get(hand, ""))
			if f != "":
				ok = ok and f.begins_with("mw/") and View.MESHY_WEAPON_LIKE.has(f.substr(3)) and ResourceLoader.exists(View.weapon_path(f))
		if not ok:
			bad.append(cls)
		items[str(q.get("item", ""))] = true
	check(bad.is_empty(), "each quest: 3 steps, a legendary of its class, earned not sold, its models in the game %s" % str(bad))
	check(items.size() == 13, "13 different legendaries")
	var leaked := []
	for d in 60:
		for id in Eco.shop_daily(1791000000 + d * 86400) + Eco.shop_featured(1791000000 + d * 86400):
			if items.has(id):
				leaked.append(id)
	for sid in range(1, 8):
		for id in Eco.pass_items(sid):
			if items.has(id):
				leaked.append(id)
	for rar in ["common", "rare", "epic", "legendary"]:
		for id in Eco.chest_pool(rar):
			if items.has(id):
				leaked.append(id)
	check(leaked.is_empty(), "no quest legendary in the shop, the pass or a chest %s" % str(leaked))
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
	var e0 := int(p.d.embers)
	var r1: Dictionary = p.claim_quest("knight")
	check(bool(r1.ok) and int(p.d.gold) == g0 + 400 and int(p.d.embers) == e0 + 30 and p.quest_step("knight") == 1, "step 1 pays 400 gold and 30 Embers")
	check(not p.quest_ready("knight") and not bool(p.claim_quest("knight").ok), "step 3's goal reached doesn't skip step 2")
	p.d.stats["q_knight_rescues"] = 10
	var gem0 := int(p.d.gems)
	var ch0: int = p.d.chests.slots.size()
	var r2: Dictionary = p.claim_quest("knight")
	check(bool(r2.ok) and int(p.d.gems) == gem0 + 50 and p.d.chests.slots.size() == ch0 + 1 and str(p.d.chests.slots[-1].kind) == "gold", "step 2 pays 50 gems and a Gold chest")
	check(not p.owns("knight_wpn_kingsguard"), "the legendary isn't yours yet")
	var r3: Dictionary = p.claim_quest("knight")
	check(bool(r3.ok) and str(r3.item) == "knight_wpn_kingsguard" and p.owns("knight_wpn_kingsguard") and p.quest_done("knight"), "step 3 gives Kingsguard; the quest is done")
	check(not bool(p.claim_quest("knight").ok) and p.quests_ready() == 0, "nothing more to claim")
	check(bool(p.equip("knight_wpn_kingsguard").ok) and str(p.look_for("knight").get("r", "")) == "mw/kingsguard_sword", "Kingsguard equips like any weapon")
	# ---- saved and loaded
	p.d.quests["rogue"] = 9
	p.d.quests["nobody"] = 2
	p.save()
	var p2 := Profile.new(p.path, "user://none.json")
	p2.load_or_create()
	check(p2.quest_step("knight") == 3 and p2.quest_step("rogue") == 3 and not p2.d.quests.has("nobody") and int(p2.d.stats.get("q_knight_rescues", 0)) == 10,
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
			check(btn("side_quests") != null, "Home has a QUESTS button")
			press("side_quests")
			check(app.tab == "quests" and str(app.quest_cls) == "mage", "QUESTS opens on the class with a step ready (%s)" % str(app.quest_cls))
			check(btn("quest_claim_mage") != null and btn("quest_knight") != null and btn("quest_archmage") != null, "the Quests screen: all 13 classes and CLAIM")
		1:
			var g0 := int(p.d.gold)
			press("quest_claim_mage")
			check(p.quest_step("mage") == 1 and int(p.d.gold) == g0 + 400, "CLAIM pays step 1")
			p.d.stats["q_mage_lifts"] = 15
			p.d.stats["q_mage_wins"] = 60
			app.rebuild()
		2:
			press("quest_claim_mage")
			check(p.quest_step("mage") == 2, "step 2 claimed")
		3:
			press("quest_claim_mage")
			check(p.owns("mage_wpn_emberheart") and app.modal != null and btn("shop_preview_equip") != null, "the legendary shows off with EQUIP")
			press("shop_preview_equip")
			check(str(p.d.equip.mage.weapon) == "mage_wpn_emberheart", "Emberheart equipped from there")
			press("shop_preview_close")
		4:
			press("quests_back")
			check(app.tab == "home", "back to Home")
			app.locker_class = "worker"
			app.show_tab("locker")
		5:
			check(btn("locker_quest_worker") != null, "the Locker shows the Worker's quest")
			press("locker_quest_worker")
			check(app.tab == "quests" and str(app.quest_cls) == "worker", "and opens it")
			print("QUEST_PASS" if fails.is_empty() else "QUEST_FAIL %s" % str(fails))
			quit(0 if fails.is_empty() else 1)
	step += 1
	return false
