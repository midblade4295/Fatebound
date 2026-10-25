extends Control
# The match's minimap (0.31.216, Kevin: "make fatebound more like [Honor of Kings]" -- the landscape HUD's map in the
# top-left corner). The field as the camera sees it: the square, your keep bottom-left (siege_view.gd screen_up) --
# the painted plan tools/bake_land.gd bakes (assets/terrain/minimap.png), turned to the view. Over it: the towers
# (your side blue, theirs red, a fallen one a grey cross), the Kings, the jungle's camps that are up, the epic
# monsters, the minions and the heroes -- yours always, theirs only where your side sees them (moba_vision.gd: the fog
# of war) -- you ringed in white, your wards. Redrawn REDRAW times a second; the plan is one texture.
const Land = preload("res://scripts/siege/siege_land.gd")
const Keep = preload("res://scripts/siege/keep.gd")
const View = preload("res://scripts/siege/siege_view.gd")
const VisualTheme = preload("res://scripts/ui/visual_theme.gd")
const PLAN := "res://assets/terrain/minimap.png"
const SPAN := 168.0                       # metres across the minimap (the 156 m square and a little of its edge)
const REDRAW := 0.2
const BLUE := Color("#4fc3ff")
const RED := Color("#ff5a4a")
const MONSTER := Color("#c58bff")

var hud                                   # siege_hud.gd (its sim, player_id)
var _plan: Texture2D = null
var _clock := 0.0
var _frame: StyleBoxFlat = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	if ResourceLoader.exists(PLAN):
		_plan = load(PLAN)

func _process(dt: float) -> void:
	_clock -= dt
	if _clock <= 0.0:
		_clock = REDRAW
		queue_redraw()

func team() -> int:
	if hud == null or hud.sim == null:
		return 0
	return int(hud.sim.by_id.get(hud.player_id, {}).get("team", 0))

func to_map(p: Vector2) -> Vector2:
	# a world point on the minimap: along the screen's right and up, as the camera sees it
	var up := View.screen_up(team())
	var right := Vector2(-up.y, up.x)
	var k := size.x / SPAN
	return size * 0.5 + Vector2(p.dot(right), -p.dot(up)) * k

func _draw() -> void:
	if _frame == null:
		_frame = StyleBoxFlat.new()
		_frame.bg_color = Color(0.02, 0.04, 0.06, 0.82)
		_frame.border_color = Color(VisualTheme.GOLD_DARK, 0.9)
		_frame.set_border_width_all(2)
		_frame.set_corner_radius_all(6)
		_frame.anti_aliasing = true
	draw_style_box(_frame, Rect2(Vector2.ZERO, size))
	if hud == null or hud.sim == null:
		return
	var sim = hud.sim
	var me_team := team()
	var k := size.x / SPAN
	if _plan != null:
		# the plan covers Land.bake_rect in world orientation: turned and scaled to the view
		var r := Land.bake_rect()
		var up := View.screen_up(me_team)
		var ang := atan2(up.x, -up.y)                 # the world's -y is the screen's up when this is 0
		draw_set_transform(size * 0.5, -ang, Vector2(k, k))
		draw_texture_rect(_plan, Rect2(r.position, r.size), false, Color(1, 1, 1, 0.92))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var m = sim.moba
	if m == null:
		return
	var vis = m.vision
	# the camps that are up and the epic monsters
	for camp in m.camps:
		var up_now := bool(camp.get("alive", false)) if camp.has("alive") else float(camp.get("next", 0.0)) <= float(sim.time)
		if not up_now:
			continue
		var cp := to_map(camp.p)
		var epic := str(camp.kind) in ["lord", "wyrm"]
		draw_circle(cp, 4.2 if epic else 2.6, Color(0.05, 0.03, 0.08, 0.9))
		draw_circle(cp, 3.2 if epic else 1.8, MONSTER if epic else Color("#e8d7a0"))
	# the towers and the Kings
	for tw in m.towers:
		var tp := to_map(tw.p)
		var col := BLUE if int(tw.team) == me_team else RED
		if bool(tw.dead):
			draw_line(tp - Vector2(3, 3), tp + Vector2(3, 3), Color(0.6, 0.6, 0.6, 0.8), 1.5)
			draw_line(tp - Vector2(3, -3), tp + Vector2(3, -3), Color(0.6, 0.6, 0.6, 0.8), 1.5)
			continue
		draw_rect(Rect2(tp - Vector2(4, 4), Vector2(8, 8)), Color(0.02, 0.03, 0.05, 0.95))
		draw_rect(Rect2(tp - Vector2(3, 3), Vector2(6, 6)), col)
	for t in 2:
		var kp := to_map(sim._m(t, Keep.KING))
		draw_circle(kp, 5.5, Color(0.02, 0.03, 0.05, 0.95))
		draw_circle(kp, 4.5, Color("#ffd65a"))
		draw_circle(kp, 2.5, BLUE if t == me_team else RED)
	# your wards
	for w in vis.wards if vis != null else []:
		if int(w.team) == me_team:
			draw_circle(to_map(w.p), 2.2, Color("#9cff8a"))
	# the minions, then the heroes (yours always; theirs where your side sees them)
	var mine_id := str(hud.player_id)
	var heroes := []
	for u in sim.units:
		if str(u.get("state", "")) == "dead" or int(u.get("team", 0)) > 1:
			continue
		var ally := int(u.team) == me_team
		if not ally and vis != null and not vis.can_see(me_team, u):
			continue
		if bool(u.get("hero", false)):
			heroes.append(u)
			continue
		draw_circle(to_map(u.pos), 1.4, Color(BLUE if ally else RED, 0.9))
	for u in heroes:
		var hp := to_map(u.pos)
		var ally := int(u.team) == me_team
		var col := BLUE if ally else RED
		draw_circle(hp, 5.0, Color(0.02, 0.03, 0.05, 0.95))
		draw_circle(hp, 4.0, col)
		if str(u.id) == mine_id:
			draw_arc(hp, 6.0, 0.0, TAU, 20, Color.WHITE, 1.6, true)
	# where the camera looks: a thin frame round your view
	var me: Dictionary = sim.by_id.get(mine_id, {})
	if not me.is_empty():
		var c := to_map(me.pos)
		var half: Vector2 = Vector2(15.0, 8.0) * k * (float(hud.size.x) / maxf(float(hud.size.y), 1.0)) / 1.8
		draw_rect(Rect2(c - half, half * 2.0), Color(1, 1, 1, 0.35), false, 1.0)
