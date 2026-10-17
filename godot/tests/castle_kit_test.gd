extends SceneTree
# The Meshy castle kits (0.31.74, castle_kit.gd): every piece and floor texture is there, each team has a kit, and the
# props stand where nobody needs to walk (0.31.165: in the Rift's keeps -- see below). The keep's layout itself is the
# sim's (siege_land_check covers it).
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Castle = preload("res://scripts/siege/siege_castle.gd")
const Keep = preload("res://scripts/siege/keep.gd")
const CastleKit = preload("res://scripts/siege/castle_kit.gd")
var fails := []

func check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)
		print("FAIL ", what)
	else:
		print("ok   ", what)

func _in_rect(p: Vector2, x0: float, x1: float, z0: float, z1: float, pad: float) -> bool:
	return p.x > minf(x0, x1) - pad and p.x < maxf(x0, x1) + pad and p.y > minf(z0, z1) - pad and p.y < maxf(z0, z1) + pad

func _init() -> void:
	# Both teams build a described kit (0.31.75: both Royal, red in its own colours by team_swap).
	check(CastleKit.STYLE_OF_TEAM.size() == 2 and CastleKit.STYLE_OF_TEAM.all(func(s): return CastleKit.KITS.has(s)),
		"each team builds a known kit (%s)" % [CastleKit.STYLE_OF_TEAM])
	for t in 2:
		check(CastleKit.kit(t) == CastleKit.KITS[CastleKit.STYLE_OF_TEAM[t]], "kit(%d) is %s" % [t, CastleKit.STYLE_OF_TEAM[t]])
	# Kits the teams don't build are left out of the APK (export_presets.cfg) -- only the used ones are checked here.
	var used := {}
	for s in CastleKit.STYLE_OF_TEAM:
		used[s] = true
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	var filters := []
	for line in presets.split("\n"):
		if line.begins_with("exclude_filter="):
			filters.append(line)
	check(not filters.is_empty(), "export presets read (%d exclude filters)" % filters.size())
	for style in CastleKit.KITS:
		var pat := "assets/meshy/castle/%s_*" % style
		var n := filters.filter(func(f): return pat in f).size()
		if used.has(style):
			check(n == 0, "%s kit is built, so it ships (no preset excludes %s)" % [style, pat])
		else:
			check(n == filters.size() and filters.all(func(f): return ("assets/meshy/castle/floors/%s_*" % style) in f),
				"%s kit is unused, so every preset leaves its models and floors out of the APK" % style)
	for style in used:
		var kit: Dictionary = CastleKit.KITS[style]
		var models := {}
		for part in ["wall", "terrace", "gatehouse", "tower", "dungeon", "throne"]:
			models[str(kit[part].m)] = true
		for pr in kit.props:
			models[str(pr[0])] = true
		var missing := []
		for m in models:
			if not ResourceLoader.exists(CastleKit.DIR + m + ".glb"):
				missing.append(m)
		check(missing.is_empty(), "%s: all %d models imported %s" % [style, models.size(), missing])
		for area in ["court", "walk", "l1", "l2", "dungeon"]:
			var f: Array = kit.floors[area]
			check(ResourceLoader.exists(CastleKit.DIR + "floors/%s.jpg" % f[0]), "%s: %s floor texture" % [style, area])
		for fm in kit.fires:
			check(models.has(fm), "%s: fires on a model it uses (%s)" % [style, fm])
		# 0.31.165: the Rift's keeps (keep.gd) build from the kit too -- their props and fountain models are the kit's,
		# inside the ring, clear of the King towers, the throne, the fountain's ring and the way from each gate to the
		# King. (Until then: the Siege castles' props on their terraces, off the stairs, the wall-walk and the way to the
		# dungeon -- that castle isn't built any more.)
		var s = Sim.new()
		s.setup(2, 3)
		check(ResourceLoader.exists(CastleKit.DIR + Keep.FOUNTAIN_MODEL + ".glb"), "%s: the keep's fountain model" % style)
		for pr in Keep.PROPS:
			var spot: Vector2 = pr[1]
			var name := "%s %s at %s" % [style, pr[0], spot]
			check(ResourceLoader.exists(CastleKit.DIR + str(pr[0]) + ".glb"), "%s: its model" % name)
			var clear := Keep.inside(spot) and spot.distance_to(Keep.C) < Keep.R - 1.8
			for kt in Keep.KING_TOWERS:
				clear = clear and spot.distance_to(kt) > 3.0
			clear = clear and spot.distance_to(Keep.THRONE_SEAT) > 2.2 and spot.distance_to(Keep.KING) > 2.5
			clear = clear and spot.distance_to(Keep.FOUNTAIN) > Keep.FOUNTAIN_R + 1.0
			for i in Keep.GATE_ANG.size():
				var g: Vector2 = Keep.gate_c(i)
				clear = clear and spot.distance_to(Sim.seg_closest(spot, g, Keep.KING)) > 2.6
			check(clear, "%s is out of the way" % name)
	print("CASTLE_KIT_PASS" if fails.is_empty() else "CASTLE_KIT_FAIL %s" % [fails])
	quit(0 if fails.is_empty() else 1)
