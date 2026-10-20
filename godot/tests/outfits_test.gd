extends SceneTree
# 0.31.188 (Kevin: "Remove the forge and the individual weapon skins. I only want the cosmetics to be an entire outfit.
# Each outfit has its own specific looking weapon" / "Make all new sets for every hero and make each one unique to their
# class and lore along with the weapons to go along with each skin" / "Remove, no refund"):
#  1. no weapons in the catalog (titles stay), no Arsenals, no Forge -- the ops, the profile's keys and the economy's;
#  2. an old save: its weapons, what was equipped and forged, the chests' pity and the pass's weapon swaps drop out; no
#     refund; its titles, gold and gems as they were;
#  3. chests: gold, gems and a shard -- nothing else; the odds say so;
#  4. the pass: no cosmetics on any tier of any season -- chests, gems and shards where the weapons were;
#  5. a quest's last step: gems and a Royal chest; the quests hold no weapon;
#  6. the starter pack: 500 gems, 3,000 gold and a Hero Token;
#  7. outfits: every hero has his own set (its own weapon model, the files there) and the Frostbound (his own weapon
#     repainted); an outfit on a body puts its weapon in his hands, or paints his own; a bust (r/l "") holds nothing;
#  8. the looks: what I wear is the outfit ("_sk"), the server keeps only that; look_for is the outfit worn.
#   godot --headless --path godot -s res://tests/outfits_test.gd
const Eco = preload("res://scripts/meta/economy.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const View = preload("res://scripts/siege/siege_view.gd")
var fails: Array = []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func fresh(tag: String) -> Profile:
	var p := Profile.new("user://outfits_%s_%d.json" % [tag, Time.get_ticks_usec()], "user://none_%d.json" % Time.get_ticks_usec())
	p.load_or_create()
	return p

func _hand_files(body: Node3D) -> Dictionary:
	# hand ("r"/"l") -> the weapon scene file in it
	var out := {}
	for slot in body.find_children("*", "BoneAttachment3D", true, false):
		var hand := str((slot as BoneAttachment3D).bone_name).get_extension()
		for n in slot.find_children("*", "Node3D", true, false):
			if str(n.scene_file_path) != "":
				out[hand] = str(n.scene_file_path)
				break
	return out

func _painted(body: Node3D, tex_path: String) -> bool:
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for surf in m.get_surface_override_material_count():
			var mat := m.get_surface_override_material(surf)
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture != null and (mat as BaseMaterial3D).albedo_texture.resource_path == tex_path:
				return true
	return false

func _init() -> void:
	# ---- 1. nothing of the weapons or the Forge left
	var kinds := {}
	for id in Eco.CATALOG:
		kinds[str(Eco.CATALOG[id].kind)] = true
	var consts: Dictionary = Eco.new().get_script().get_script_constant_map()
	check(kinds.keys() == ["title"] and not consts.has("PACKS") and not consts.has("FORGE_STARS") and not consts.has("DUPE_GOLD")
		and not consts.has("ELEMENTS") and consts.has("EMBER_GOLD") and consts.has("DAILY_GOLD"), "the catalog is titles only; no Arsenals, Forge or duplicates")
	check(not Profile.OPS.has("buy") and not Profile.OPS.has("buy_pack") and not Profile.OPS.has("forge") and not Profile.OPS.has("set_forge_element")
		and Profile.OPS.has("equip") and Profile.OPS.has("buy_skin"), "the ops: no buying weapons or packs, no forging; titles still worn, outfits bought")
	var d0 := Profile.defaults()
	check(not d0.has("equip") and not d0.has("forge") and not (d0.chests as Dictionary).has("pity"), "a new save has no weapons, Forge or pity")
	# ---- 2. an old save
	var old := fresh("old")
	var v := old.d.duplicate(true)
	v["owned"] = ["knight_wpn_oath", "title_squire", "barb_wpn_raider"]
	v["equip"] = {"knight": {"skin": "", "weapon": "knight_wpn_oath"}}
	v["forge"] = {"stars": {"knight_wpn_oath": 3}, "wins": {}, "element": {"knight_wpn_oath": "fire"}}
	v.chests["pity"] = 7
	v.pass["swaps"] = {"f10": {"item": "rogue_wpn_bolt", "swap": "rogue_wpn_bomb"}, "f5": {"shard": "golem"}}
	v.gold = 1234
	v.gems = 56
	v.title = "title_squire"
	var n: Dictionary = old._normalized(v)
	check(n.owned == ["title_squire"] and not n.has("equip") and not n.has("forge") and not (n.chests as Dictionary).has("pity")
		and n.pass.swaps == {"f5": {"shard": "golem"}} and int(n.gold) == 1234 and int(n.gems) == 56 and str(n.title) == "title_squire",
		"an old save: weapons, Forge, pity and weapon swaps gone, no refund; titles, gold, gems and a shard tier kept")
	# ---- 3. chests
	var keys_ok := true
	var shards := 0
	for i in 400:
		var r: Dictionary = Eco.roll_chest("royal", 1000 + i)
		keys_ok = keys_ok and r.keys().size() == 3 and r.has("gold") and r.has("gems") and r.has("shard")
		shards += 1 if str(r.shard) != "" else 0
	check(keys_ok and shards > 160 and shards < 240, "a Royal chest: gold, gems and a hero shard half the time (0.31.189), nothing else (%d / 400)" % shards)
	var odds := ""
	for k in Eco.CHESTS:
		odds += Eco.chest_odds(k) + " | "
	check(not odds.contains("cosmetic") and not odds.contains("duplicate") and odds.contains("hero shard"), "the odds: gold, gems, shards (%s)" % odds.substr(0, 120))
	var p := fresh("chest")
	p.add_chest("gold", {}, true)
	p.now_override = 1791000000
	p.start_unlock(0)
	p.now_override += int(Eco.CHESTS.gold.unlock) + 5
	var got: Dictionary = p.open_chest(0)
	check(bool(got.get("ok", false)) and not got.has("item") and int(got.gold) > 0, "opening one: no weapon in it (%s)" % str(got.keys()))
	# ---- 4. the pass
	var items := 0
	var shard_tiers := 0
	for sid in [1, 2, 3]:
		for t in range(1, Eco.PASS_TIERS + 1):
			for prem in [false, true]:
				var r := Eco.pass_reward(sid, t, prem)
				items += 1 if r.has("item") else 0
				shard_tiers += 1 if r.has("shard") else 0
	check(items == 0 and Eco.pass_reward(1, 10, false) == {"chest": "gold"} and Eco.pass_reward(1, 30, true) == {"chest": "royal", "gems": 100}
		and shard_tiers == 3 * 3, "the pass: no cosmetics on any tier -- chests, gems and shards where the weapons were (0.31.189: 3 shards a season)")
	var pp := fresh("pass")
	pp.d.pass.season = 1
	pp.d.pass.premium = true
	pp.d.pass.xp = Eco.PASS_TIERS * Eco.TIER_XP
	var gems0 := int(pp.d.gems)
	var claimed: Array = pp.claim_all()
	check(claimed.size() == 2 * Eco.PASS_TIERS and int(pp.d.gems) > gems0 and pp.d.owned.is_empty() and (pp.d.shards as Array).size() == 3,
		"claiming the whole pass: gems, chests and three shards -- nothing owned")
	# ---- 5. quests
	var no_item := true
	for cls in Eco.QUESTS:
		no_item = no_item and not (Eco.QUESTS[cls] as Dictionary).has("item")
	check(no_item and Eco.quest_reward("knight", 2) == {"gems": 100, "chest": "royal"}, "a quest's last step: 100 gems and a Royal chest (0.31.189: 150)")
	var q := fresh("quest")
	q.d.quests["knight"] = 2
	q.d.stats["q_knight_kills"] = 500
	var qg := int(q.d.gems)
	var qr: Dictionary = q.claim_quest("knight")
	check(bool(qr.ok) and int(q.d.gems) == qg + 100 and q.quest_done("knight") and q.d.owned.is_empty(), "claimed: the gems, the chest, no weapon")
	# ---- 6. the starter pack
	var sp: Dictionary = Net.IAP.starter_pack
	var s := fresh("starter")
	var g: Dictionary = s.grant_iap("starter_pack", "tok-outfits-1")
	check(not sp.has("weapon") and int(sp.get("token", 0)) == 1 and int(g.gems) == 500 and int(g.gold) == 3000 and int(g.token) == 1
		and int(s.d.tokens) == 1 and bool(s.d.iap.starter), "the starter pack: 500 gems, 3,000 gold and a Hero Token")
	# ---- 7. outfits
	var heroes: Array = Eco.SKIN_HEROES.keys()
	var own_sets := {}
	var files_ok := true
	for id in Eco.SKINS:
		var sk: Dictionary = Eco.SKINS[id]
		if sk.has("weapon"):
			own_sets[str(sk.hero)] = int(own_sets.get(str(sk.hero), 0)) + 1
			for hand in sk.weapon:
				var f := str(sk.weapon[hand])
				if f != "" and (not ResourceLoader.exists(View.weapon_path(f)) or not View.MESHY_WEAPON_LIKE.has(f.substr(3))):
					files_ok = false
					print("   missing ", id, " ", f)
		elif str(sk.get("weapon_tex", "")) == "":
			files_ok = false
		if not ResourceLoader.exists(Eco.skin_texture(id)) or not ResourceLoader.exists("res://assets/ui/skins/%s.png" % id):
			files_ok = false
			print("   missing art ", id)
	var each := heroes.all(func(h): return int(own_sets.get(h, 0)) >= 1 and Eco.SKINS.has(h + "_frost"))
	check(each and files_ok, "every hero: his own set with a weapon of its own, and the Frostbound -- every file there (%d outfits)" % Eco.SKINS.size())
	var names := {}
	for id in Eco.SKINS:
		names[str(Eco.SKINS[id].set)] = true
	check(names.size() == 1 + heroes.size() and int(Eco.SKINS.knight_frost.gems) == 390 and str(Eco.SKINS.knight_frost.rarity) == "rare",
		"18 sets of their own and the Frostbound line (390 gems)")
	var own_id := ""
	for id in Eco.skins_of("knight"):
		if Eco.SKINS[id].has("weapon"):
			own_id = str(id)
	var made: Dictionary = View.make_body("knight", {"skin": own_id})
	var hands := _hand_files(made.body)
	check(own_id != "" and hands.get("r", "") == View.weapon_path(str(Eco.SKINS[own_id].weapon.r)) and hands.get("l", "") == View.weapon_path(str(Eco.SKINS[own_id].weapon.l)),
		"the Knight in %s holds its own sword and shield (%s)" % [own_id, str(hands)])
	var plain: Dictionary = View.make_body("knight", {})
	check(_hand_files(plain.body).get("r", "") == View.weapon_path(str(View.LOOKS.knight.r)), "his own look: his own sword")
	var frost: Dictionary = View.make_body("knight", {"skin": "knight_frost"})
	var frost_tex := Eco.skin_weapon_texture(str(View.LOOKS.knight.r), "frost")
	check(_hand_files(frost.body).get("r", "") == View.weapon_path(str(View.LOOKS.knight.r)) and ResourceLoader.exists(frost_tex) and _painted(frost.body, frost_tex),
		"the Frostbound Knight: his own sword, repainted in frost")
	var bust: Dictionary = View.make_body("mage", {"skin": "mage_phoenix", "r": "", "l": ""})
	check(_hand_files(bust.body).is_empty(), "a portrait's bust holds nothing (the Phoenix Mage: no staff; a Knight keeps his shield, 0.31.41)")
	for b in [made.body, plain.body, frost.body, bust.body]:
		(b as Node).free()
	# ---- 8. the looks
	var w := fresh("wear")
	w.d.skins = ["knight_frost", own_id]
	w.wear_skin("knight", own_id)
	check(w.wire_looks() == {"_sk": own_id} and w.look_for("knight") == {"skin": own_id} and w.look_for("mage").is_empty(),
		"what I wear online is the outfit; look_for is the outfit worn")
	check(Net.clean_looks({"knight": "knight_wpn_oath|3|fire", "_sk": own_id}) == {"_sk": own_id}, "the server keeps the outfits only (an old app's weapons dropped)")
	print("OUTFITS_PASS" if fails.is_empty() else "OUTFITS_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
