extends SceneTree
# 0.31.85 (Kevin: "When on the other team, it still thinks I'm on the other team and controls are inverted and health
# bars are red for my team"): a match seated on each team through the online welcome path (_build_online_match) --
# the stick moves you the way it points on screen, and your side is drawn blue (bars, rings, HUD) and the other red.
# 0.31.88: and your own nameplate is over your bar.
const Mode = preload("res://scripts/siege/siege_mode.gd")
const View = preload("res://scripts/siege/siege_view.gd")
const IDS := ["b0", "r0"]
var mode
var frames := 0
var fails: Array = []

func check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)
		print("FAIL ", what)
	else:
		print("ok   ", what)

func _init() -> void:
	mode = Mode.new()
	mode.online = false
	mode.player_name = "Midblade"
	root.add_child(mode)

func _seat(i: int) -> void:
	mode._build_online_match({"team_size": 16, "seed": 4242, "you": IDS[i], "match": i + 1})

func _stick(off: Vector2) -> Vector2:
	var hud = mode.hud
	hud._stick_active = true
	hud._stick_origin = Vector2(100, 600)
	hud._stick_pos = Vector2(100, 600) + off
	var mv: Vector2 = mode._move_input()
	hud._stick_active = false
	return mv

func _verify(i: int) -> void:
	var me_id: String = IDS[i]
	var sim = mode.sim
	var view = mode.view
	var me: Dictionary = sim.by_id[me_id]
	var team := int(me.team)
	check(team == i, "%s is on team %d" % [me_id, i])
	check(int(view.my_side) == i, "the view draws for side %d (my_side %d)" % [i, int(view.my_side)])
	check(mode.hud.vt(team) == 0 and mode.hud.vt(1 - team) == 1, "HUD: our team drawn blue, theirs red")
	# Health bars: allies blue, enemies red, me green.
	var by_pos := {}
	for b in view.bars():
		by_pos[str((b.pos as Vector3).snapped(Vector3.ONE * 0.01))] = b.color
	var ally_ok := 0
	var ally_bad := 0
	var foe_ok := 0
	var foe_bad := 0
	for u in sim.units:
		var a: Dictionary = view.actors.get(u.id, {})
		if u.id == me_id or a.is_empty() or u.state == "dead":
			continue
		var key := str(((a.root as Node3D).position + Vector3(0, 2.7, 0)).snapped(Vector3.ONE * 0.01))
		if not by_pos.has(key):
			continue
		var c: Color = by_pos[key]
		if int(u.team) == team:
			if c == View.TEAM_COLORS[0]: ally_ok += 1
			else: ally_bad += 1
		else:
			if c == View.TEAM_COLORS[1]: foe_ok += 1
			else: foe_bad += 1
	check(ally_ok > 5 and ally_bad == 0, "ally health bars blue (%d ok, %d not)" % [ally_ok, ally_bad])
	check(foe_ok > 5 and foe_bad == 0, "enemy health bars red (%d ok, %d not)" % [foe_ok, foe_bad])
	# 0.31.88 (Kevin: "Show the nameplate for the players own name also"): my plate from my profile, with no "pn" from
	# a server; nobody else gets one without it.
	var mine := 0
	var others := 0
	for b in view.bars():
		if b.has("name"):
			if str(b.name) == "Midblade" and b.name_color == Color("#ffd65a") and b.color == Color("#7dff8a"): mine += 1
			else: others += 1
	check(mine == 1 and others == 0 and mode.net_names.is_empty(), "my own nameplate, gold, with no names from a server (%d mine, %d others)" % [mine, others])
	# The stick: pushed up the unit heads up the screen, pushed right it heads right.
	var p0 := Vector3(me.pos.x, Sim_height(me.pos), me.pos.y)
	var s0: Vector2 = view.screen_point(p0)
	var up := _stick(Vector2(0, -60))
	var su: Vector2 = view.screen_point(p0 + Vector3(up.x, 0, up.y) * 3.0)
	check(su.y < s0.y - 10.0 and absf(su.x - s0.x) < 0.3 * absf(su.y - s0.y), "team %d: stick up moves up the screen (%s -> %s)" % [i, str(s0), str(su)])
	var rt := _stick(Vector2(60, 0))
	var sr: Vector2 = view.screen_point(p0 + Vector3(rt.x, 0, rt.y) * 3.0)
	check(sr.x > s0.x + 10.0 and absf(sr.y - s0.y) < 0.3 * absf(sr.x - s0.x), "team %d: stick right moves right on screen (%s -> %s)" % [i, str(s0), str(sr)])

func Sim_height(p: Vector2) -> float:
	return mode.sim.height_at(p)

func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		_seat(0)
	elif frames == 15:
		_verify(0)
		_seat(1)
	elif frames == 27:
		_verify(1)
		print("SIDE_VIEW_PASS" if fails.is_empty() else "SIDE_VIEW_FAIL %s" % str(fails))
		quit(0 if fails.is_empty() else 1)
	return false
