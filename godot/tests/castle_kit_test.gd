extends SceneTree
# The Meshy castle kits (0.31.74, castle_kit.gd): every piece and floor texture is there, each team has a kit, and the
# props stand where nobody needs to walk -- on their level, off the stairs, the wall-walk and the way to the dungeon,
# clear of the gates, the hat shops and the workshop. The castle's layout itself is the sim's and unchanged
# (siege_land_check covers it).
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Castle = preload("res://scripts/siege/siege_castle.gd")
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
	check(CastleKit.STYLE_OF_TEAM.size() == 2 and CastleKit.STYLE_OF_TEAM[0] != CastleKit.STYLE_OF_TEAM[1],
		"each team its own castle (%s)" % [CastleKit.STYLE_OF_TEAM])
	for style in CastleKit.KITS:
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
		# Props: on their level, clear of where people walk.
		var s = Sim.new()
		s.setup(2, 3)
		for pr in kit.props:
			var spot: Vector2 = pr[1]
			var y := float(pr[2])
			var name := "%s %s at %s" % [style, pr[0], spot]
			var w: Vector2 = Sim._c(0, spot)
			check(absf(Sim.height_at(w) - y) < 0.06, "%s stands on its level (%.2f, ground %.2f)" % [name, y, Sim.height_at(w)])
			var clear := true
			var why := ""
			for st in Castle.STAIRS:
				if _in_rect(spot, float(st.x0), float(st.x1), float(st.z0), float(st.z1), 0.6):
					clear = false
					why = "on a stair"
			if _in_rect(spot, -Castle.WALK_X, Castle.WALK_X, Castle.FRONT_Z, Castle.WALK_Z1, 0.3):
				clear = false
				why = "on the wall-walk"
			for gx in Castle.GATE_X:
				if spot.distance_to(Vector2(float(gx), Castle.FRONT_Z + 1.0)) < 2.6:
					clear = false
					why = "in a gateway"
			for hs in Castle.HAT_SHOPS:
				if spot.distance_to(hs.b) < float(hs.r) + 1.2 or spot.distance_to(hs.door) < 1.4:
					clear = false
					why = "at the %s shop" % hs.cls
			for bd in Castle.BUILDINGS:
				if spot.distance_to(bd.p) < float(bd.r) + 1.2:
					clear = false
					why = "at the workshop"
			# The way to the dungeon: from the west stairs' top along the first terrace to its doorway.
			if spot.y > Castle.L1_Z + 2.5 and spot.y < Castle.DOOR_Z1 + 0.6 and spot.x < -7.5:
				clear = false
				why = "on the way to the dungeon"
			if spot.distance_to(Castle.THRONE) < Sim.THRONE_RADIUS + 1.2:
				clear = false
				why = "at the throne"
			check(clear, "%s is out of the way%s" % [name, "" if clear else " (" + why + ")"])
	print("CASTLE_KIT_PASS" if fails.is_empty() else "CASTLE_KIT_FAIL %s" % [fails])
	quit(0 if fails.is_empty() else 1)
