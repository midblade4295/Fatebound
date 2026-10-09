extends SceneTree
# 0.31.87 titles (Kevin: "make it so their titles show (use correct punctuation)", "players have to earn the titles
# instead by doing tasks in the game", "more titles for each class", no camping title): the table, the punctuation,
# earning from match stats and from a veteran's old stats, streaks, the pass / shop / pack changes, the sim's healing.
const Net = preload("res://scripts/siege/siege_net.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
var fails: Array = []

func check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)
		print("FAIL ", what)
	else:
		print("ok   ", what)

func fresh(tag: String) -> Profile:
	var path := "user://title_test_%s_%d.json" % [tag, Time.get_ticks_usec()]
	var p := Profile.new(path, "user://none_%d.json" % Time.get_ticks_usec())
	p.load_or_create()
	return p

func me(extra: Dictionary) -> Dictionary:
	var m := {"cls":"knight", "kills":0, "rescues":0, "gathered":0, "fed":0, "gate_dmg":0.0, "lifts":0}
	m.merge(extra, true)
	return m

func _init() -> void:
	# ---- the table
	check(Net.TITLES.size() == 37, "37 titles (%d)" % Net.TITLES.size())
	var by_cls := {}
	var bad := []
	for id in Net.TITLES:
		var t: Array = Net.TITLES[id]
		var it: Dictionary = Eco.CATALOG.get(id, {})
		var g: Dictionary = Eco.TITLE_GOALS.get(id, {})
		if it.is_empty() or g.is_empty() or str(it.kind) != "title" or str(it.name) != str(t[0]) or str(it.rarity) != str(t[2]) \
				or str(it.source) != "earn" or not (str(t[1]) in ["the", "of", "prefix", "office"]):
			bad.append(id)
		var c := str(g.get("cls", "?"))
		by_cls[c] = by_cls.get(c, []) + [str(t[2])]
	check(bad.is_empty(), "every title: catalog name/rarity = the table's, earned, a goal, a known form %s" % str(bad))
	var cls_ok := true
	for c in Eco.CLASSES:
		var rs: Array = by_cls.get(c, [])
		rs.sort()
		cls_ok = cls_ok and rs == ["epic", "legendary", "rare"]
	check(cls_ok and by_cls.get("", []).size() == 16, "each of the 7 classes has a rare, an epic and a legendary; 16 for everyone")
	var catalog_titles := 0
	for id in Eco.CATALOG:
		if str(Eco.CATALOG[id].kind) == "title":
			catalog_titles += 1
	check(catalog_titles == 37, "no title in the catalog outside the table (%d)" % catalog_titles)
	check(not Net.TITLES.has("title_unbroken"), "no win-without-dying title (Kevin: players would just camp)")
	# ---- punctuation
	check(Net.title_text("Midblade", "title_gatebreaker") == "Midblade the Gatebreaker", "epithet: no comma (%s)" % Net.title_text("Midblade", "title_gatebreaker"))
	check(Net.title_text("Midblade", "title_squire") == "Squire Midblade", "rank in front (%s)" % Net.title_text("Midblade", "title_squire"))
	check(Net.title_text("Midblade", "title_siege_lord") == "Midblade, Siege Lord", "office after a comma (%s)" % Net.title_text("Midblade", "title_siege_lord"))
	check(Net.title_text("Midblade", "title_many_hats") == "Midblade of Many Hats", "of-phrase (%s)" % Net.title_text("Midblade", "title_many_hats"))
	check(Net.title_text("Midblade", "title_hammer_realm") == "Midblade, Hammer of the Realm", "class legendary (%s)" % Net.title_text("Midblade", "title_hammer_realm"))
	check(Net.title_text("Midblade", "") == "Midblade" and Net.title_text("Midblade", "made_up") == "Midblade", "no title / an unknown id: just the name")
	var parts := Net.title_parts("Aria", "title_siege_lord")
	check(parts.size() == 2 and not parts[0][1] and parts[1][1] and str(parts[1][0]) == " Siege Lord", "parts: the title marked for its colour (%s)" % str(parts))

	# ---- earning from matches
	var p := fresh("earn")
	var r := p.apply_match(me({"kills":60, "gathered":210, "fed":12}), false, false, true)
	var got: Array = r.get("titles", [])
	check(got.has("title_brawler") and got.has("title_woodcutter") and got.has("title_fishmonger") and not got.has("title_squire"),
		"one big match: Brawler, Woodcutter, Fishmonger (%s)" % str(got))
	check(p.owns("title_brawler") and p.equip("title_brawler").ok and str(p.d.title) == "title_brawler", "an earned title can be worn")
	check(not p.equip("title_legend").ok, "an unearned one can't")
	for i in 4:
		p.apply_match(me({"cls_main":"knight"}), true, false, true)
	check(p.d.stats.streak == 4 and not p.owns("title_relentless"), "4 wins in a row: no Relentless yet")
	r = p.apply_match(me({"cls_main":"knight"}), true, false, true)
	check(p.owns("title_relentless") and p.owns("title_victor") and p.owns("title_squire") and (r.titles as Array).has("title_relentless"),
		"the 5th win in a row: Relentless (and Victor, Squire) %s" % str(r.titles))
	p.apply_match(me({}), false, true, true)
	check(p.d.stats.streak == 0 and p.d.stats.best_streak == 5, "a draw ends the run; the best stays")
	for i in 5:
		p.apply_match(me({"cls_main":"knight", "kills_cls":{"knight":50}}), true, false, true)
	check(p.owns("title_sir") and int(p.d.stats.win_knight) == 10 and p.owns("title_shieldwall") and int(p.d.stats.kills_knight) == 250,
		"10 Knight wins: Sir; 250 Knight knockouts: the Shieldwall")
	check(Net.title_text("Kevin", "title_sir") == "Sir Kevin", "Sir Kevin")
	r = p.apply_match(me({"best_multi":3, "healed":25000.0, "repaired":20000.0}), false, false, true)
	check((r.titles as Array).has("title_tempest") and p.owns("title_merciful") and p.owns("title_mason"),
		"a triple knockout, 25,000 healed, 20,000 repaired: Tempest, Merciful, Mason (%s)" % str(r.titles))
	check((r.titles as Array)[0] == "title_tempest" or Eco.TITLE_RARITY_ORDER.find(str(Eco.CATALOG[(r.titles as Array)[0]].rarity)) >= 2, "newly earned listed rarest first")
	for c in ["barbarian", "rogue", "ranger", "mage", "priest", "worker"]:
		p.apply_match(me({"cls_main":c}), false, false, true)
	check(p.owns("title_many_hats"), "a match as each of the 7 classes: of Many Hats")
	check(p.title_progress("title_legend") == int(p.d.stats.wins), "progress reads the lifetime stats")

	# ---- a veteran's first start with titles: earned from the stats already there, a note for Home
	var path := "user://title_test_vet_%d.json" % Time.get_ticks_usec()
	var v := Profile.new(path, "user://none.json")
	v.load_or_create()
	v.d.stats = {"matches":30, "wins":12, "rescues":3, "kills":120, "gates":140, "gathered":90, "fed":4}
	v.d.owned.append("title_oracle_sworn")                        # bought in the shop before 0.31.87
	v.d.title = "title_oracle_sworn"
	v.save()
	var v2 := Profile.new(path, "user://none.json")
	v2.load_or_create()
	check(v2.owns("title_squire") and v2.owns("title_victor") and v2.owns("title_brawler") and v2.owns("title_gatebreaker") \
		and not v2.owns("title_woodcutter"), "a veteran's old stats earn their titles on load")
	check(v2.d.has("title_note") and (v2.d.title_note as Array).size() == 4, "and Home is told how many (%s)" % str(v2.d.get("title_note", [])))
	check(v2.owns("title_oracle_sworn") and str(v2.d.title) == "title_oracle_sworn", "a title bought before stays owned and worn")

	# ---- the pass, the shop, the pack
	check(Eco.pass_reward(1, 5, true) == {"gems": 50} and Eco.pass_reward(1, 9, true) == {"gems": 50} and Eco.pass_reward(1, 21, true) == {"gems": 100},
		"season 1: premium tiers 5, 9, 21 (the old titles) give 50, 50, 100 gems")
	var names := []
	for id in Eco.pass_items(1):
		names.append(str(Eco.CATALOG[id].name))
	check(names.slice(0, 5) == ["Axe & Ale", "Twin Wands", "War Mallet", "Sun Staff", "Brass Knuckles"] and names[15] == "Reaper",
		"the rest of season 1's pass is unchanged %s" % str(names))
	check(int(Eco.pass_cosmetics(1).n) == 10 and int(Eco.pass_cosmetics(1).legendary) == 5, "the premium offer counts 10 cosmetics, 5 legendary (%s)" % str(Eco.pass_cosmetics(1)))
	var shop_titles := []
	for day in 60:
		for id in Eco.shop_daily(1791000000 + day * 86400) + Eco.shop_featured(1791000000 + day * 86400):
			if str(Eco.CATALOG[id].kind) == "title":
				shop_titles.append(id)
	check(shop_titles.is_empty(), "no title in 60 days of shop rotations")
	check(not Eco.PACKS.pack_crusader.items.has("title_gatebreaker") and int(Eco.PACKS.pack_crusader.gems) == 280, "Knight Arsenal: no title, 280 gems")
	var chest_titles := []
	for rar in Eco.TITLE_RARITY_ORDER:
		for id in Eco.chest_pool(rar):
			if str(Eco.CATALOG[id].kind) == "title":
				chest_titles.append(id)
	check(chest_titles.is_empty(), "no title in the chests")

	# ---- the sim counts healing (the Merciful title): a priest's beam on a hurt ally, not himself
	var sim := Sim.new()
	sim.setup(4, 7, -1)
	var pr: Dictionary = {}
	var ally: Dictionary = {}
	for u in sim.units:
		if u.team == 0 and pr.is_empty():
			pr = u
		elif u.team == 0 and ally.is_empty():
			ally = u
	pr.cls = "priest"
	ally.max_hp = 100.0
	ally.hp = 40.0
	sim._heal(pr, ally, 25.0)
	sim._heal(pr, pr, 25.0)
	sim._heal(pr, ally, 100.0)
	check(is_equal_approx(float(pr.healed), 60.0) and is_equal_approx(float(ally.hp), 100.0), "healing counts what the ally got, capped at full, not self (%.1f)" % float(pr.get("healed", 0)))

	print("TITLE_PASS" if fails.is_empty() else "TITLE_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
