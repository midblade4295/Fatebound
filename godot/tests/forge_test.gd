extends SceneTree
# 0.31.93 Armory Reforged: the Forge (stars, their gold -- 0.31.184: Embers folded into gold --, the third star's wins and element), the
# Meshy weapons' table, and the star effects on a model.
#   godot --headless --path godot -s res://tests/forge_test.gd
const Eco = preload("res://scripts/meta/economy.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const View = preload("res://scripts/siege/siege_view.gd")
var fails: Array = []

func check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)
		print("FAIL ", what)
	else:
		print("ok   ", what)

func fresh(tag: String) -> Profile:
	var path := "user://forge_test_%s_%d.json" % [tag, Time.get_ticks_usec()]
	var p := Profile.new(path, "user://none_%d.json" % Time.get_ticks_usec())
	p.load_or_create()
	return p

func _init() -> void:
	# ---- the table (0.31.184: gold only -- each star's Embers in its gold, Eco.EMBER_GOLD each)
	check(Eco.forge_cost(1) == {"gold":1400} and Eco.forge_cost(2) == {"gold":4200} and Eco.forge_cost(3) == {"gold":11000} and Eco.forge_cost(4).is_empty(), "star costs (0.31.184): 1,400, 4,200, 11,000 gold")
	check(Eco.forge_id("knight", "") == "default_knight" and Eco.forge_name("default_knight") == "Squire's Blade" and Eco.forge_rarity("default_knight") == "common", "a starter is forged as default_<class>, by its name")
	check(Eco.forge_name("knight_wpn_oath") == "Kingsoath" and Eco.forge_class("knight_wpn_oath") == "knight", "the Knight's weapons have their new names")
	# ---- forging
	var p := fresh("a")
	var wid := "default_knight"
	check(p.forge_owns(wid) and not p.forge_owns("knight_wpn_oath"), "a starter is always yours, a catalog weapon once owned")
	p.d.gold = 1000
	check(str(p.can_forge(wid).why) == "gold", "not enough gold: can't forge")
	p.d.gold = 20000
	check(bool(p.forge(wid).ok) and p.forge_stars(wid) == 1 and int(p.d.gold) == 18600, "star 1 costs 1,400 gold")
	check(bool(p.forge(wid).ok) and p.forge_stars(wid) == 2 and int(p.d.gold) == 14400, "star 2: 4,200 gold")
	check(str(p.can_forge(wid, "fire").why) == "wins", "star 3 needs %d wins with the weapon" % Eco.FORGE_WINS)
	p.d.forge.wins[wid] = Eco.FORGE_WINS
	check(str(p.can_forge(wid).why) == "element", "... and an element")
	check(bool(p.forge(wid, "frost").ok) and p.forge_stars(wid) == 3 and p.forge_element(wid) == "frost" and int(p.d.gold) == 3400, "star 3 with Frost: 11,000 gold")
	check(str(p.can_forge(wid, "fire").why) == "maxed", "three stars is the most")
	check(p.set_forge_element(wid, "void") and p.forge_element(wid) == "void" and int(p.d.gold) == 3400, "an Ascended weapon changes element for free")
	var fx: Dictionary = p.look_for("knight").get("forge", {})
	check(int(fx.get("stars", 0)) == 3 and str(fx.element) == "void" and str(fx.rarity) == "common", "the battle look carries the stars: %s" % str(fx))
	check(not p.look_for("barbarian").has("forge"), "an unforged weapon has none")
	# ---- 0.31.184: what gave Embers gives their gold (EMBER_GOLD each)
	var q := fresh("b")
	check(not Profile.OPS.has("buy_embers") and not q.has_method("buy_embers"), "no Embers to buy any more")
	var me := {"cls":"knight", "cls_main":"knight", "kills":0, "rescues":0, "gathered":0, "fed":0, "gate_dmg":0.0, "lifts":0}
	check(int(Eco.match_rewards(Eco.match_stats(me, false, false), false, false, false, false).gold) == 75 + 2 * Eco.EMBER_GOLD
		and int(Eco.match_rewards(Eco.match_stats(me, true, false), true, false, false, false).gold) == 150 + 5 * Eco.EMBER_GOLD,
		"a match's 2 Embers (a win's 5) are in its gold: 95, 200")
	q.d.owned.append("knight_wpn_oath")
	q.equip("knight_wpn_oath")
	var r1: Dictionary = q.apply_match(me, true, false, false)
	check(not r1.has("embers") and not q.d.has("embers"), "no Embers from a match")
	check(q.forge_wins("knight_wpn_oath") == 1 and q.forge_wins("default_knight") == 0, "a win counts for the equipped weapon of the class played most")
	q.d.challenges.daily[0].progress = 9999
	var g1 := int(q.d.gold)
	var def: Dictionary = Eco.CHALLENGES[str(q.d.challenges.daily[0].id)]
	var cr: Dictionary = q.claim_challenge("daily", 0)
	check(bool(cr.ok) and int(q.d.gold) == g1 + int(def.get("gold", 0)) + Eco.DAILY_GOLD and int(cr.gold) == int(def.get("gold", 0)) + Eco.DAILY_GOLD,
		"a daily order: its gold + %d (its 15 Embers)" % Eco.DAILY_GOLD)
	var dup := Eco.roll_chest("royal", 7, Eco.chest_pool("epic") + Eco.chest_pool("legendary") + Eco.chest_pool("rare"), 0)
	check(int(dup.get("dupe_gold", 0)) >= Eco.DUPE_GOLD.epic and not dup.has("dupe_embers"), "a duplicate in a chest becomes gold (%d)" % int(dup.get("dupe_gold", 0)))
	var pe := {"free": 0, "prem": 0, "embers": 0}
	for t in range(1, Eco.PASS_TIERS + 1):
		for prem in [false, true]:
			for sid in [1, 2]:
				pe.embers += int(Eco.pass_reward(sid, t, prem).get("embers", 0))
		pe.free += int(Eco.pass_reward(1, t, false).get("gold", 0)) if t % 4 == 2 else 0
		pe.prem += int(Eco.pass_reward(1, t, true).get("gold", 0)) if t % 4 == 2 else 0
	# (0.31.185: premium tier 2 holds the first weapon now -- tier 1 is the Hero Token's -- so 3 premium gold tiers, not 4)
	check(pe.embers == 0 and Eco.pass_reward(1, 2, false) == {"gold": Eco.PASS_GOLD_FREE} and Eco.pass_reward(1, 6, true) == {"gold": Eco.PASS_GOLD_PREMIUM}
		and Eco.pass_reward(2, 4, true) == {"gold": Eco.PASS_GOLD_GEM_TIER} and pe.free == 6 * Eco.PASS_GOLD_FREE and pe.prem == 3 * Eco.PASS_GOLD_PREMIUM,
		"the pass's Ember tiers give their gold (%d free, %d premium in season 1; no Embers anywhere)" % [pe.free, pe.prem])
	# ---- an old save's Embers are turned into gold, once
	var old := fresh("c")
	old.d["embers"] = 520
	old.d.gold = 1000
	var turned: Dictionary = old._normalized(old.d)
	check(int(turned.gold) == 1000 + 520 * Eco.EMBER_GOLD and not turned.has("embers"), "an old save: 520 Embers -> 5,200 gold (%d)" % int(turned.gold))
	check(int(old._normalized(turned).gold) == int(turned.gold), "... once")
	# ---- a bad save is cleaned up
	var bad := fresh("d")
	bad.d.forge = {"stars": {"x": 9, "y": -2}, "wins": "nope"}
	bad.d["embers"] = -5
	var clean: Dictionary = bad._normalized(bad.d)
	check(int(clean.forge.stars.x) == 3 and int(clean.forge.stars.y) == 0 and clean.forge.wins is Dictionary and not clean.has("embers")
		and int(clean.gold) == int(bad.d.gold), "a damaged Forge save is put right (negative Embers: nothing)")
	# ---- the Meshy weapons
	var ok_files := true
	for id in View.MESHY_WEAPON_LIKE:
		if not ResourceLoader.exists("res://assets/meshy/weapons/%s.glb" % id) or not ResourceLoader.exists(View.weapon_path(str(View.MESHY_WEAPON_LIKE[id]))):
			ok_files = false
			print("   missing ", id)
	check(ok_files, "every Meshy weapon and the KayKit model it is held like exist (%d)" % View.MESHY_WEAPON_LIKE.size())
	var used_ok := true
	for id in Eco.CATALOG:
		for hand in ["r", "l"]:
			var f := str(Eco.CATALOG[id].get(hand, ""))
			if f.begins_with("mw/") and not View.MESHY_WEAPON_LIKE.has(f.substr(3)):
				used_ok = false
	for cls in View.LOOKS:
		for hand in ["r", "l"]:
			var f2 := str(View.LOOKS[cls].get(hand, ""))
			if f2.begins_with("mw/") and not View.MESHY_WEAPON_LIKE.has(f2.substr(3)):
				used_ok = false
	check(used_ok, "every mw/ weapon used has a hold")
	for id in ["knight_wpn_arming", "knight_wpn_greatsword", "knight_wpn_crest", "knight_wpn_tower", "knight_wpn_crimson", "knight_wpn_bastion", "knight_wpn_halberd", "knight_wpn_longsword", "knight_wpn_spiked", "knight_wpn_oath"]:
		if not str(Eco.CATALOG[id].r).begins_with("mw/") or not str(Eco.CATALOG[id].l).begins_with("mw/"):
			check(false, "%s uses its new models" % id)
	# ---- the star effects on a body
	var made: Dictionary = View.make_body("knight", {"r": "mw/kingsoath_sword", "l": "mw/kingsoath_shield", "forge": {"stars": 3, "rarity": "legendary", "element": "holy"}})
	var body: Node3D = made.body
	var glowing := 0
	var particles := body.find_children("WeaponFx", "", true, false).size()      # 0.31.100: built in the tree (weapon_fx_test)
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.get_surface_override_material_count() > 0 and m.get_surface_override_material(0) != null and m.get_surface_override_material(0).next_pass is ShaderMaterial:
			glowing += 1
	check(glowing >= 2 and particles == 1, "three stars: both pieces glow (%d), the sword has its effects (%d)" % [glowing, particles])
	var plain: Dictionary = View.make_body("knight", {"r": "mw/highguard_sword", "l": "mw/highguard_shield"})
	var plain_glow := 0
	for mi in (plain.body as Node3D).find_children("*", "MeshInstance3D", true, false):
		var pm := mi as MeshInstance3D
		if pm.get_surface_override_material_count() > 0 and pm.get_surface_override_material(0) != null and pm.get_surface_override_material(0).next_pass != null:
			plain_glow += 1
	check((plain.body as Node3D).find_children("WeaponFx", "", true, false).is_empty() and plain_glow == 0, "no stars (and not a legendary), no effects")
	body.free()
	(plain.body as Node3D).free()
	print("FORGE_PASS" if fails.is_empty() else "FORGE_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
