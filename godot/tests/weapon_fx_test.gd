extends SceneTree
# Weapon effects (0.31.100, Kevin: "I want the effects to look better for the forge weapons. I also want to add effects
# for all the legendary weapons"): every legendary's pieces have their own effects, with real presets and sprites;
# the Forge's stars build glints, then runes, then the element's set; particles are sized to the piece in the world
# whatever it is scaled by; the swing ribbon draws only on a blade that moves fast, never on a staff; the still icons
# and plain weapons get nothing.
#   godot --headless --fixed-fps 30 --path godot -s res://tests/weapon_fx_test.gd
const Eco = preload("res://scripts/meta/economy.gd")
const View = preload("res://scripts/siege/siege_view.gd")
const WeaponFx = preload("res://scripts/siege/weapon_fx.gd")
const WeaponPose = preload("res://scripts/app/weapon_pose.gd")
var fails: Array = []
var frames := 0
var stage: Node3D
var made := {}
var still: Node3D
var forge: Node3D
var spin_from := 0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	# ---- the tables
	var missing := []
	var leg_files := {}
	for id in Eco.CATALOG:
		var it: Dictionary = Eco.CATALOG[id]
		if str(it.get("kind", "")) == "weapon" and str(it.get("rarity", "")) == "legendary":
			for hand in ["r", "l"]:
				var f := str(it.get(hand, ""))
				if f != "":
					leg_files[f] = true
					if WeaponFx.legendary(f).is_empty() or not WeaponFx.legendary(f).has("col"):
						missing.append(f)
	check(missing.is_empty() and leg_files.size() >= 22, "every legendary weapon's pieces have effects (%d pieces) %s" % [leg_files.size(), str(missing)])
	var bad := []
	for k in WeaponFx.LEGENDARY:
		if not leg_files.has("mw/" + k) or not View.MESHY_WEAPON_LIKE.has(k):
			bad.append(k)
	check(bad.is_empty(), "the table names only legendary pieces %s" % str(bad))
	var used: Array = []
	for k in WeaponFx.LEGENDARY:
		for e in WeaponFx.LEGENDARY[k].get("fx", []):
			used.append(str(e.p))
	for el in WeaponFx.ELEMENT_FX:
		for e in WeaponFx.ELEMENT_FX[el]:
			used.append(str(e.p))
	for st in WeaponFx.STAR_FX:
		used.append_array(WeaponFx.STAR_FX[st])
	var bad_p := []
	for name in used:
		var pr: Dictionary = WeaponFx.PRESETS.get(name, {})
		if pr.is_empty() or not ResourceLoader.exists("res://assets/vfx/weapon/%s.png" % str(pr.get("tex", ""))):
			bad_p.append(name)
	check(bad_p.is_empty(), "every preset used exists, with its sprite %s" % str(bad_p))
	var no_el := []
	for el in Eco.ELEMENTS:
		if not WeaponFx.ELEMENT_FX.has(el):
			no_el.append(el)
	check(no_el.is_empty(), "every element has its own set %s" % str(no_el))
	# ---- in a scene
	stage = Node3D.new()
	root.add_child(stage)
	_body("k1", "knight", {"r": "mw/highguard_sword", "l": "mw/highguard_shield", "forge": {"stars": 1, "rarity": "rare"}})
	_body("k2", "knight", {"r": "mw/highguard_sword", "l": "mw/highguard_shield", "forge": {"stars": 2, "rarity": "rare"}})
	_body("k3", "knight", {"r": "mw/highguard_sword", "l": "mw/highguard_shield", "forge": {"stars": 3, "rarity": "rare", "element": "fire"}})
	_body("plain", "knight", {"r": "mw/highguard_sword", "l": "mw/highguard_shield"})
	_body("seraph", "priest", {"r": "mw/seraph_staff"})
	_body("small", "barbarian", {"r": "mw/worldsplitter_axe"})
	var big := Node3D.new()
	big.scale = Vector3.ONE * 3.0
	stage.add_child(big)
	_body("big", "barbarian", {"r": "mw/worldsplitter_axe"}, big)
	still = Node3D.new()
	stage.add_child(still)
	WeaponPose.compose(still, "mw/archon_staff", "", {}, false)
	forge = Node3D.new()
	stage.add_child(forge)
	WeaponPose.compose(forge, "mw/archon_staff", "", {})

func _body(key: String, cls: String, cos: Dictionary, parent: Node3D = null) -> void:
	var m: Dictionary = View.make_body(cls, cos)
	(parent if parent != null else stage).add_child(m.body)
	made[key] = m.body

func _fx(n: Node, what: String) -> Array:
	return n.find_children("Fx_" + what, "", true, false)

func _ribbon(n: Node) -> MeshInstance3D:
	var r := n.find_children("Ribbon", "MeshInstance3D", true, false)
	return r[0] if not r.is_empty() else null

func _process(_d: float) -> bool:
	frames += 1
	if frames == 4:
		var k1: Node = made.k1
		var k2: Node = made.k2
		var k3: Node = made.k3
		check(_fx(k1, "sparkle").size() == 1 and _fx(k1, "runes").is_empty() and _ribbon(k1) == null, "1 star: glints, no runes, no ribbon")
		check(_fx(k2, "sparkle").size() == 1 and _fx(k2, "runes").size() == 1 and _ribbon(k2) != null, "2 stars: + runes and a faint ribbon")
		check(_fx(k3, "flame").size() == 1 and _fx(k3, "dot").size() == 1 and _ribbon(k3) != null, "3 stars, fire: flames, embers and a ribbon")
		check((made.plain as Node).find_children("WeaponFx", "", true, false).is_empty(), "a plain weapon: nothing")
		var sr: Node = made.seraph
		check(_fx(sr, "ring").size() == 1 and _fx(sr, "feather").size() == 1 and _ribbon(sr) == null, "Seraph's Grace: its halo and feathers, no ribbon on a staff")
		var a: Array = _fx(made.small, "dot")
		var b: Array = _fx(made.big, "dot")
		var sa := ((a[0] as GPUParticles3D).draw_pass_1 as QuadMesh).size.x if not a.is_empty() else 0.0
		var sb := ((b[0] as GPUParticles3D).draw_pass_1 as QuadMesh).size.x if not b.is_empty() else 0.0
		check(sa > 0.0 and absf(sb / sa - 3.0) < 0.05, "an ember is sized to the piece in the world (x%.2f at 3x)" % (sb / maxf(sa, 0.0001)))
		check(still.find_children("WeaponFx", "", true, false).is_empty() and forge.find_children("WeaponFx", "", true, false).size() == 1 and _fx(forge, "sigil").size() == 1,
			"a still icon has none; the Forge's piece has its sigil")
		var r3 := _ribbon(k3)
		check(r3 != null and (r3.mesh as ImmediateMesh).get_surface_count() == 0, "a blade at rest draws no ribbon")
		spin_from = frames
	if spin_from > 0 and frames > spin_from and frames <= spin_from + 6:
		(made.k3 as Node3D).rotate_y(0.6)          # a fast turn: the blade sweeps
	if spin_from > 0 and frames == spin_from + 6:
		var r3 := _ribbon(made.k3)
		check(r3 != null and (r3.mesh as ImmediateMesh).get_surface_count() == 1, "a fast swing draws the ribbon")
		print("WEAPON_FX_PASS" if fails.is_empty() else "WEAPON_FX_FAIL %s" % str(fails))
		quit(0 if fails.is_empty() else 1)
	return false
