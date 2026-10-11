extends SceneTree
# What the players wear, for everyone to see (0.31.101, Kevin: "I want players to see everything the other players are
# wearing"): my weapons and Forge stars go out in my hello as "weapon id|stars|element" per class, the server keeps only
# well-formed entries (Net.clean_looks), and each app dresses the other players' units from its own catalog -- the
# same look I see on my own unit, the starter for an id it doesn't know, a lighter version with fewer effects on.
# (The relay through the real server: siege_net_smoke.)
#   godot --headless --path godot -s res://tests/shared_looks_test.gd
const Eco = preload("res://scripts/meta/economy.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const View = preload("res://scripts/siege/siege_view.gd")
var fails: Array = []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	# ---- the wire's rules match the game's
	var classes: Array = Eco.CLASSES + Eco.UP_CLASSES
	var same: bool = classes.size() == Net.LOOK_CLASSES.size()
	for c in classes:
		same = same and Net.LOOK_CLASSES.has(c)
	check(same and Net.LOOK_STARS == Eco.FORGE_STARS.size(), "the server's classes and star limit are the game's")
	# ---- the server keeps only well-formed entries
	var dirty := {"knight": "knight_wpn_oath|3|holy", "rogue": "rogue_wpn_moonfang|9|", "mage": "Mage Wpn<b>|1|",
		"priest": "priest_wpn_sun|2|Lava!", "ranger": "|0|", "worker": "worker_wpn_sledge|x|", "nobody": "a|1|",
		"barbarian": 42, "archmage": "a".repeat(70) + "|1|", "crusader": "|2|"}
	var clean := Net.clean_looks(dirty)
	check(clean == {"knight": "knight_wpn_oath|3|holy", "rogue": "rogue_wpn_moonfang|3|", "priest": "priest_wpn_sun|2|", "crusader": "|2|"},
		"clean_looks: stars clamped, a bad element dropped, bad ids / classes / numbers / sizes refused (%s)" % str(clean))
	check(Net.clean_looks("knight") == {} and Net.clean_looks(null) == {}, "anything but a dictionary is nothing")
	# ---- my looks out and back are what I see on my own unit
	var p := Profile.new("user://shared_looks_%d.json" % Time.get_ticks_usec(), "user://none_%d.json" % Time.get_ticks_usec())
	p.load_or_create()
	for id in ["knight_wpn_oath", "rogue_wpn_moonfang", "crus_wpn_maul"]:
		p.d.owned.append(id)
		p.equip(id)
	p.d.forge.stars["knight_wpn_oath"] = 3
	p.d.forge.element["knight_wpn_oath"] = "holy"
	p.d.forge.stars["default_mage"] = 2
	var wire := p.wire_looks()
	check(wire == {"knight": "knight_wpn_oath|3|holy", "rogue": "rogue_wpn_moonfang|0|", "crusader": "crus_wpn_maul|0|", "mage": "|2|"},
		"my hello's looks: equipped weapons, their stars, a forged starter (%s)" % str(wire))
	check(Net.clean_looks(wire) == wire, "the server passes them through unchanged")
	var back := Eco.looks_from_wire(wire)
	var match_all := back.size() == wire.size()
	for cls in wire:
		match_all = match_all and back.get(cls, {}) == p.look_for(cls)
	check(match_all, "the others see exactly my looks (%s)" % str(back))
	var odd := Eco.looks_from_wire({"knight": "knight_wpn_from_the_future|1|", "barbarian": "rogue_wpn_moonfang|0|"})
	check(not odd.get("knight", {}).has("r") and int(odd.get("knight", {}).get("forge", {}).get("stars", 0)) == 1 and not odd.has("barbarian"),
		"an id this app doesn't know (or another class's) is the starter (%s)" % str(odd))
	# ---- the battle view dresses another player's unit
	var view = View.new()
	view.player_id = "b0"
	view.set_unit_looks({"b0": {"knight": "knight_wpn_kingsguard|0|"}, "r3": {"knight": "knight_wpn_oath|3|holy", "rogue": "rogue_wpn_moonfang|0|"}})
	check(not view.unit_looks.has("b0") and view.unit_looks.has("r3"), "the others' looks, not mine (mine come from my profile)")
	var kn: Dictionary = view.unit_cosmetic({"id": "r3", "cls": "knight", "up": false})
	check(str(kn.get("r", "")) == "mw/kingsoath_sword" and int(kn.get("forge", {}).get("stars", 0)) == 3, "their Knight carries Kingsoath with 3 stars")
	check(view.unit_cosmetic({"id": "r3", "cls": "knight", "up": true}).is_empty() and view.unit_cosmetic({"id": "r4", "cls": "knight", "up": false}).is_empty(),
		"as a Crusader (nothing equipped there) and for a bot: the defaults")
	var body: Node3D = View.make_body("knight", kn).body
	var has_fx := not body.find_children("WeaponFx", "", true, false).is_empty()
	check(_glows(body) and has_fx, "their body glows and has its effects")
	body.free()
	view.low_fx = true
	view.set_unit_looks({"r3": {"knight": "knight_wpn_oath|3|holy"}})
	var lite: Dictionary = view.unit_cosmetic({"id": "r3", "cls": "knight", "up": false})
	var lb: Node3D = View.make_body("knight", lite).body
	check(bool(lite.get("lite", false)) and _glows(lb) and lb.find_children("WeaponFx", "", true, false).is_empty(),
		"with fewer effects on: their weapon glows, no particles")
	lb.free()
	view.free()
	print("SHARED_LOOKS_PASS" if fails.is_empty() else "SHARED_LOOKS_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)

func _glows(body: Node3D) -> bool:
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.get_surface_override_material_count() > 0 and m.get_surface_override_material(0) != null and m.get_surface_override_material(0).next_pass != null:
			return true
	return false
