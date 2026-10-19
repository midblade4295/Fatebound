extends SceneTree
# 0.31.186 (League's way, the fourth part: hero skins). The Frostbound line -- every hero repainted by Meshy's
# retexture with his own UVs kept (tools/meshy_retexture.py, tools/build_skins.py).
#  1. The catalog: 18 skins, one a hero, epic at 750 gems; each one's texture (assets/skins) and portrait (assets/ui/skins).
#  2. Buying: gems only; a locked hero's skin brings him (League); worn at once; another hero's skin can't be worn on
#     him; wear "" = his own look; a damaged save keeps only real, owned skins worn by their own heroes.
#  3. Online: the looks carry "_sk" (the skins worn); clean_looks keeps good ids only; the server's account looks hold
#     only the skins the account owns; buy_skin / wear_skin replay to the same profile.
#  4. The view: a skinned body's own meshes take the skin's texture (one material shared per skin), his weapons keep
#     theirs; my hero wears my skin, another player's hero his (from "_sk"), a bot none -- and unit_cosmetic gives the
#     same dictionary every frame.
#   godot --headless --path godot -s res://tests/skins_test.gd
const Profile = preload("res://scripts/meta/profile.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const View = preload("res://scripts/siege/siege_view.gd")
const Accounts = preload("res://server/eco_accounts.gd")
var fails: Array = []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func fresh(tag: String) -> Profile:
	var p := Profile.new("user://skins_%s_%d.json" % [tag, Time.get_ticks_usec()], "user://none_%d.json" % Time.get_ticks_usec())
	p.load_or_create()
	return p

func _init() -> void:
	# ---- 1. the catalog
	var heroes := {}
	var missing := []
	for id in Eco.SKINS:
		var sk: Dictionary = Eco.SKINS[id]
		heroes[str(sk.hero)] = true
		if not ResourceLoader.exists(Eco.skin_texture(id)):
			missing.append(Eco.skin_texture(id))
		if not ResourceLoader.exists("res://assets/ui/skins/%s.png" % id):
			missing.append("portrait " + id)
		if int(sk.gems) != 750 or str(sk.rarity) != "epic":
			missing.append("price " + id)
	check(Eco.SKINS.size() == 18 and heroes.size() == 18 and missing.is_empty(), "18 Frostbound skins, one a hero, 750 gems, each with its texture and portrait %s" % str(missing))
	check(Eco.SKINS.knight_frost.name == "Frostbound Knight" and Eco.skins_of("golem") == ["golem_frost"], "named by line and hero")
	# ---- 2. buying and wearing
	var p := fresh("buy")
	p.d.gems = 1000
	check(not bool(p.buy_skin("nope_frost").ok), "an unknown skin isn't sold")
	var r: Dictionary = p.buy_skin("golem_frost")
	check(bool(r.ok) and bool(r.hero) and p.owns_hero("golem") and p.owns_skin("golem_frost") and p.worn_skin("golem") == "golem_frost"
		and int(p.d.gems) == 250, "the Frostbound Golem: 750 gems, the Golem with it (League), worn at once")
	check(not bool(p.buy_skin("knight_frost").ok) and int(p.d.gems) == 250, "not enough gems: no")
	check(not bool(p.buy_skin("golem_frost").ok), "...and a skin once")
	p.d.gems = 2000
	check(bool(p.buy_skin("knight_frost").ok) and not bool(p.buy_skin("mage_frost").get("hero", true)), "a free hero's skin: no hero to add")
	check(not bool(p.wear_skin("mage", "knight_frost").ok) and bool(p.wear_skin("knight", "").ok) and p.worn_skin("knight") == ""
		and bool(p.wear_skin("knight", "knight_frost").ok) and p.worn_skin("knight") == "knight_frost", "worn on its own hero only; an empty id: his own look")
	var bad := fresh("bad")
	bad.d.skins = ["knight_frost", "fake_skin", "knight_frost"]
	bad.d.skin_on = {"knight": "knight_frost", "mage": "knight_frost", "golem": "golem_frost"}
	var n: Dictionary = bad._normalized(bad.d)
	check(n.skins == ["knight_frost"] and n.skin_on == {"knight": "knight_frost"}, "a damaged save: real skins, owned, on their own heroes (%s)" % str(n.skin_on))
	# ---- 3. online
	var wl: Dictionary = p.wire_looks()
	check(str(wl.get("_sk", "")) == "golem_frost,knight_frost,mage_frost", "the looks carry the skins worn (%s)" % str(wl.get("_sk", "")))
	var cl: Dictionary = Net.clean_looks({"_sk": "knight_frost,BAD-ID,golem_frost,knight_frost", "knight": "|2|"})
	check(str(cl.get("_sk", "")) == "knight_frost,golem_frost" and cl.has("knight"), "clean_looks keeps good skin ids, once each (%s)" % str(cl))
	var a := fresh("opa")
	var b := fresh("opb")
	a.d.gems = 3000
	b.d = b._normalized(a.d.duplicate(true))
	var log: Array = []
	a.on_op = func(op, args): log.append([op, args.duplicate(true)])
	a.buy_skin("druid_frost")
	a.buy_skin("rogue_frost")
	a.wear_skin("rogue", "")
	for e in log:
		b.apply_op(str(e[0]), JSON.parse_string(JSON.stringify(e[1])))
	check(log.size() == 3 and b.d.skins == a.d.skins and b.d.skin_on == a.d.skin_on and int(b.d.gems) == int(a.d.gems)
		and b.owns_hero("druid"), "buy_skin / wear_skin replay to the same profile")
	var tmp := OS.get_user_data_dir().path_join("skins-srv-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var acc = Accounts.new(tmp)
	var made: Dictionary = acc.handle({"t":"eco", "new":true})
	var id := str(made.acct)
	var key := str(made.key)
	var e: Dictionary = acc.open(id, key)
	e.p.d.gems = 800
	acc.handle({"t":"eco", "acct":id, "key":key, "ops":[{"s":1, "op":"buy_skin", "a":["musketeer_frost"]}]})
	var w: Dictionary = acc.wear(id, key)
	check(str(w.looks.get("_sk", "")) == "musketeer_frost" and (w.heroes as Array).has("musketeer"), "the server: the account wears the skin it bought (%s)" % str(w.looks))
	# ---- 4. the view
	var made_b: Dictionary = View.make_body("knight", {"skin": "knight_frost"})
	var plain: Dictionary = View.make_body("knight", {})
	var skinned := _albedos(made_b.body)
	var own := _albedos(plain.body)
	check(skinned.has(Eco.skin_texture("knight_frost")) and not own.has(Eco.skin_texture("knight_frost")), "a skinned body wears the skin's texture (%s)" % str(skinned))
	var made_c: Dictionary = View.make_body("knight", {"skin": "knight_frost"})
	var m1 := _first_override(made_b.body)
	var m2 := _first_override(made_c.body)
	check(m1 != null and m1 == m2, "one material per skin, shared")
	var weapon_ok := true
	for mi in made_b.body.find_children("*", "MeshInstance3D", true, false):
		if mi.get_parent() is BoneAttachment3D or (mi.get_parent() != null and mi.get_parent().get_parent() is BoneAttachment3D):
			for surf in (mi as MeshInstance3D).mesh.get_surface_count():
				if (mi as MeshInstance3D).get_surface_override_material(surf) != null and _tex_path((mi as MeshInstance3D).get_surface_override_material(surf)) == Eco.skin_texture("knight_frost"):
					weapon_ok = false
	check(weapon_ok, "his weapons keep their own paint")
	var v := View.new()
	v.player_id = "you"
	v.player_skins = {"knight": "knight_frost"}
	v.set_unit_looks({"b3": {"_sk": "golem_frost,mage_frost"}})
	var me := {"id": "you", "cls": "knight", "up": false, "hid": "knight", "hero": true}
	var them := {"id": "b3", "cls": "barbarian", "up": false, "hid": "golem", "hero": true, "look": "golem"}
	var bot := {"id": "b4", "cls": "knight", "up": false, "hid": "knight", "hero": true}
	var c1: Dictionary = v.unit_cosmetic(me)
	check(str(c1.get("skin", "")) == "knight_frost" and is_same(c1, v.unit_cosmetic(me)), "my Knight wears my skin -- the same dictionary every frame")
	check(str(v.unit_cosmetic(them).get("skin", "")) == "golem_frost" and str(v.unit_cosmetic(bot).get("skin", "")) == "", "their Golem wears theirs; a bot none")
	v.free()
	made_b.body.free()
	made_c.body.free()
	plain.body.free()
	print("SKINS_%s" % ("PASS" if fails.is_empty() else "FAIL %s" % str(fails)))
	quit(0 if fails.is_empty() else 1)

func _tex_path(m: Material) -> String:
	if m is BaseMaterial3D and (m as BaseMaterial3D).albedo_texture != null:
		return (m as BaseMaterial3D).albedo_texture.resource_path
	return ""

func _albedos(body: Node) -> Array:
	var out := []
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		if m3.mesh == null:
			continue
		for surf in m3.mesh.get_surface_count():
			var t := _tex_path(m3.get_active_material(surf))
			if t != "" and not out.has(t):
				out.append(t)
	return out

func _first_override(body: Node) -> Material:
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		if m3.mesh != null and m3.mesh.get_surface_count() > 0 and m3.get_surface_override_material(0) != null:
			return m3.get_surface_override_material(0)
	return null
