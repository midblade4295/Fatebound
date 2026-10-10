extends SceneTree
# 0.31.93 Armory Reforged: the Forge (stars, Embers and where they come from, the third star's wins and element), the
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
	# ---- the table
	check(Eco.forge_cost(1) == {"embers":40, "gold":500} and Eco.forge_cost(3) == {"embers":300, "gold":4000} and Eco.forge_cost(4).is_empty(), "star costs: 40/500, 120/1500, 300/4000")
	check(Eco.forge_id("knight", "") == "default_knight" and Eco.forge_name("default_knight") == "Squire's Blade" and Eco.forge_rarity("default_knight") == "common", "a starter is forged as default_<class>, by its name")
	check(Eco.forge_name("knight_wpn_oath") == "Kingsoath" and Eco.forge_class("knight_wpn_oath") == "knight", "the Knight's weapons have their new names")
	# ---- forging
	var p := fresh("a")
	var wid := "default_knight"
	check(p.forge_owns(wid) and not p.forge_owns("knight_wpn_oath"), "a starter is always yours, a catalog weapon once owned")
	check(str(p.can_forge(wid).why) == "embers", "no Embers: can't forge")
	p.d.embers = 1000
	p.d.gold = 10000
	check(bool(p.forge(wid).ok) and p.forge_stars(wid) == 1 and int(p.d.embers) == 960 and int(p.d.gold) == 9500, "star 1 costs 40 Embers and 500 gold")
	check(bool(p.forge(wid).ok) and p.forge_stars(wid) == 2 and int(p.d.embers) == 840, "star 2: 120 Embers")
	check(str(p.can_forge(wid, "fire").why) == "wins", "star 3 needs %d wins with the weapon" % Eco.FORGE_WINS)
	p.d.forge.wins[wid] = Eco.FORGE_WINS
	check(str(p.can_forge(wid).why) == "element", "... and an element")
	check(bool(p.forge(wid, "frost").ok) and p.forge_stars(wid) == 3 and p.forge_element(wid) == "frost" and int(p.d.embers) == 540, "star 3 with Frost")
	check(str(p.can_forge(wid, "fire").why) == "maxed", "three stars is the most")
	check(p.set_forge_element(wid, "void") and p.forge_element(wid) == "void" and int(p.d.embers) == 540, "an Ascended weapon changes element for free")
	var fx: Dictionary = p.look_for("knight").get("forge", {})
	check(int(fx.get("stars", 0)) == 3 and str(fx.element) == "void" and str(fx.rarity) == "common", "the battle look carries the stars: %s" % str(fx))
	check(not p.look_for("barbarian").has("forge"), "an unforged weapon has none")
	# ---- Embers in
	var q := fresh("b")
	check(not bool(q.buy_embers("embers_s").ok), "Embers for gems: not without the gems")
	q.d.gems = 200
	check(bool(q.buy_embers("embers_m").ok) and int(q.d.embers) == 170 and int(q.d.gems) == 50, "150 gems -> 170 Embers")
	var me := {"cls":"knight", "cls_main":"knight", "kills":2, "rescues":0, "gathered":0, "fed":0, "gate_dmg":0.0, "lifts":0}
	var e0 := int(q.d.embers)
	var r1: Dictionary = q.apply_match(me, false, false, false)
	check(int(q.d.embers) == e0 + Eco.EMBERS_MATCH and int(r1.embers) == Eco.EMBERS_MATCH, "a lost match: +%d Embers" % Eco.EMBERS_MATCH)
	q.d.owned.append("knight_wpn_oath")
	q.equip("knight_wpn_oath")
	q.apply_match(me, true, false, false)
	check(int(q.d.embers) == e0 + Eco.EMBERS_MATCH + Eco.EMBERS_WIN, "a win: +%d Embers" % Eco.EMBERS_WIN)
	check(q.forge_wins("knight_wpn_oath") == 1 and q.forge_wins("default_knight") == 0, "a win counts for the equipped weapon of the class played most")
	q.d.challenges.daily[0].progress = 9999
	var e1 := int(q.d.embers)
	var cr: Dictionary = q.claim_challenge("daily", 0)
	check(bool(cr.ok) and int(q.d.embers) == e1 + Eco.EMBERS_DAILY, "a daily order: +%d Embers" % Eco.EMBERS_DAILY)
	var dup := Eco.roll_chest("royal", 7, Eco.chest_pool("epic") + Eco.chest_pool("legendary") + Eco.chest_pool("rare"), 0)
	check(int(dup.dupe_embers) > 0 and not dup.has("dupe_gold"), "a duplicate in a chest becomes Embers (%d)" % int(dup.dupe_embers))
	var pe := {"free": 0, "prem": 0}
	for t in range(1, Eco.PASS_TIERS + 1):
		pe.free += int(Eco.pass_reward(1, t, false).get("embers", 0))
		pe.prem += int(Eco.pass_reward(1, t, true).get("embers", 0))
	check(pe.free >= 100 and pe.prem >= 150, "Embers on both pass tracks (%d free, %d premium a season)" % [pe.free, pe.prem])
	var e2 := int(q.d.embers)
	q._grant({"embers": 20})
	check(int(q.d.embers) == e2 + 20, "a reward of Embers is granted")
	# ---- a bad save is cleaned up
	var bad := fresh("c")
	bad.d.forge = {"stars": {"x": 9, "y": -2}, "wins": "nope"}
	bad.d.embers = -5
	var clean: Dictionary = bad._normalized(bad.d)
	check(int(clean.forge.stars.x) == 3 and int(clean.forge.stars.y) == 0 and clean.forge.wins is Dictionary and int(clean.embers) == 0, "a damaged Forge save is put right")
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
	var particles := body.find_children("ForgeAura", "GPUParticles3D", true, false).size() + body.find_children("ForgeTrail", "GPUParticles3D", true, false).size()
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.get_surface_override_material_count() > 0 and m.get_surface_override_material(0) != null and m.get_surface_override_material(0).next_pass is ShaderMaterial:
			glowing += 1
	check(glowing >= 2 and particles == 2, "three stars: both pieces glow (%d), the sword has an aura and a trail (%d)" % [glowing, particles])
	var plain: Dictionary = View.make_body("knight", {"r": "mw/kingsoath_sword", "l": "mw/kingsoath_shield"})
	check((plain.body as Node3D).find_children("ForgeAura", "", true, false).is_empty(), "no stars, no effects")
	body.free()
	(plain.body as Node3D).free()
	print("FORGE_PASS" if fails.is_empty() else "FORGE_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
