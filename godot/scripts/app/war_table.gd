extends Control
# 0.31.135 (Kevin, Crown War step 2): the war map. 0.31.137 (Kevin: "I don't like how static the map looks. I want it
# to look like a real natural land mass but in map form"): one continent in a living sea (tools/war_land.py makes it:
# coast, mountains, the river through Silver Lake, marsh and fen, farmland, forests, roads along the links, a ridge on
# every border without one), each place's land tinted with the colour of the house that holds it and outlined, its
# Meshy miniature (0.31.136) standing in it, the sea's waves and foam moving, cloud shadows drifting over it all.
# Tap a place's land to pick it. Under the map: the place picked -- who holds it, the clans' capture bars, the battle
# on it (JOIN for your house, DEFEND for the holders) and ATTACK (with CALL CLAN), or why not. Above it: the week's
# end, your attempts today, and each house's land. The state is the server's (server/world.gd), pushed to
# scripts/meta/social.gd while this is open.
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const SocialUI = preload("res://scripts/app/social_ui.gd")
const Map = preload("res://scripts/meta/war_map.gd")
const Stage = preload("res://scripts/siege/asset_cache.gd")
const LandData = preload("res://scripts/app/war_land_data.gd")   # (tools/war_land.py: the grid, each place's spot)
const LandView = preload("res://scripts/app/war_land_view.gd")   # (0.31.138: the land, sea, trees and miniatures)
const CAM_DIR := Vector3(0.0, 15.0, 11.0)   # where the camera looks from (how far: _fit_camera)
const CAM_FOV := 32.0

var app
var social
var sel := ""                          # the place tapped
var call_clan := true
var _going := false                    # ATTACK sent, waiting for the server
var _dirty := false
var _vpc: SubViewportContainer
var _vp: SubViewport
var _cam: Camera3D
var _overlay: Control
var _sheet: VBoxContainer
var _stats: HBoxContainer
var _land: Node3D                      # the land (war_land_view.gd)
var _tiles := {}                       # id -> {"pos": Vector3 (its ground), "node": Node3D (its miniature, or null), "swords": Sprite3D}
var _land_mat: ShaderMaterial
var _region_img: Image                 # (picking: which place's land a tap is on)
var _names_btn: Button
var _fit_size := Vector2i.ZERO
var names := false                     # every place's name on the table (NAMES); else the one picked and battles only
var _labels := {}                      # id -> PanelContainer over the table
var _clock := 0.0
var _press_at := Vector2.INF
var _touch := {}                       # finger index -> where it is
var _dragged := false
var _mouse_down := false
var _cam_at := Vector3.ZERO            # (_fit_camera: where the camera aims and how far back, at zoom 1)
var _cam_dist := 20.0
var _zoom := 1.0
var _pan := Vector2.ZERO
var _held_room: Node = null            # 0.31.145: Home's 3D, held still behind the window
var _held_mode := Node.PROCESS_MODE_INHERIT

func open(a, first := "") -> void:
	app = a
	social = a.social
	sel = first
	var w := SocialUI.window(self, "CROWN WAR", "swords", func():
		app.sfx("menuClose")
		app.close_modal(), 56.0 + float(app.safe_top), 24.0)
	var body: VBoxContainer = w.body
	_stats = UI.row(body, 8)
	_vpc = SubViewportContainer.new()
	_vpc.stretch = true
	_vpc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vpc.custom_minimum_size = Vector2(0, 300)
	_vpc.mouse_filter = Control.MOUSE_FILTER_STOP
	_vpc.gui_input.connect(_on_table_input)
	_vpc.set_meta("action_key", "war_table")
	body.add_child(_vpc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vpc.add_child(_vp)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vpc.add_child(_overlay)
	_names_button()
	var sf := UI2.frame(body, "glass", 10, 16.0)
	sf.add_theme_constant_override("separation", 6)
	sf.custom_minimum_size.y = 150          # (the table doesn't jump about as the sheet changes)
	_sheet = sf
	# 0.31.145 (Kevin: "Play open war map"): Home's PLAY opens this map; the match PLAY started until now is at its foot --
	# matchmaking, 16 vs 16, for any house or none (bots in the empty seats)
	var qb := UI2.button(body, "QUICK BATTLE  ·  16 VS 16", "green", func():
		app.sfx("confirm")
		app.quick_battle(), "war_quick", 18, 50.0, 14.0, UI2.icon_path("swords"))
	qb.name = "QuickBattle"
	# Home's war table and heroes (war_room.gd) are behind this window: held on their last frame while it's open
	var room = app.get("hero_node")
	if is_instance_valid(room) and room.process_mode != Node.PROCESS_MODE_DISABLED:
		_held_room = room
		_held_mode = room.process_mode
		room.process_mode = Node.PROCESS_MODE_DISABLED
	_build_table()
	social.changed.connect(_on_changed)
	social.war_went.connect(_on_went)
	social.war_open()
	_render()

func _names_button() -> void:
	# NAMES, in the table's corner: every place's name on the table, or (off) only the one picked and the battles
	if is_instance_valid(_names_btn):
		_names_btn.queue_free()
	_names_btn = UI2.button(_overlay, "NAMES", "blue" if names else "grey", func():
		app.sfx("tab")
		names = not names
		_names_button()
		_dirty = true, "war_names", 11, 28.0, 9.0)
	_names_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_names_btn.offset_left = -70
	_names_btn.offset_right = -6
	_names_btn.offset_top = 6
	_names_btn.offset_bottom = 34

func _exit_tree() -> void:
	if is_instance_valid(_held_room):
		_held_room.process_mode = _held_mode
	_held_room = null
	if social != null:
		social.war_close()
		if social.changed.is_connected(_on_changed):
			social.changed.disconnect(_on_changed)
		if social.war_went.is_connected(_on_went):
			social.war_went.disconnect(_on_went)

func _on_changed(what: String) -> void:
	if what in ["war", "state", "clan", "me"]:
		_dirty = true

func _on_went(ans: Dictionary) -> void:
	_going = false
	if bool(ans.get("ok", false)):
		app.sfx("matchStart")
		app.start_war(str(ans.get("bid", "")))
	else:
		app.sfx("error")
		app.toast(str(ans.get("why", "Can't attack there")), UI.RED)
		_dirty = true

# ---------------- the map (3D) ----------------
static func tile_pos(id: String) -> Vector3:
	return LandView.tile_pos(id)

func _build_table() -> void:
	var root := Node3D.new()
	_vp.add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#0a1a33")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#cfdcff")
	e.ambient_light_energy = 0.62
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color("#0d2140")
	e.fog_density = 0.005
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(-38.0), 0.0)
	sun.light_energy = 1.25
	sun.light_color = Color("#fff3dc")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	root.add_child(sun)
	# the land, the sea, the trees, the miniatures and the swords (war_land_view.gd, 0.31.138: Home's table has it too)
	_land = LandView.new()
	root.add_child(_land)
	_land.build()
	_land_mat = _land.land_mat
	_region_img = _land.region_img
	_tiles = _land.tiles
	_cam = Camera3D.new()
	_cam.fov = CAM_FOV
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT       # (_fit_camera moves it so the land fills whatever room it has)
	_cam.transform = Transform3D(Basis.looking_at(-CAM_DIR, Vector3.UP), CAM_DIR)   # (not in the tree yet)
	_cam.far = 120.0
	root.add_child(_cam)
	_cam.current = true
	for id in Map.T:
		var lp := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.02, 0.03, 0.08, 0.72)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 1
		sb.content_margin_bottom = 2
		lp.add_theme_stylebox_override("panel", sb)
		lp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lv := VBoxContainer.new()
		lv.add_theme_constant_override("separation", -3)
		lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lp.add_child(lv)
		var nl := Label.new()
		nl.text = Map.name_of(id)
		nl.add_theme_font_override("font", UI.HEAVY_FONT)
		nl.add_theme_font_size_override("font_size", 10)
		nl.add_theme_color_override("font_color", Color.WHITE)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lv.add_child(nl)
		var sl := Label.new()
		sl.add_theme_font_override("font", UI.HEAVY_FONT)
		sl.add_theme_font_size_override("font_size", 9)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sl.visible = false
		lv.add_child(sl)
		lp.set_meta("sub", sl)
		lp.set_meta("name", nl)
		_overlay.add_child(lp)
		_labels[id] = lp

func region_at(at: Vector2) -> String:
	# which place's land is under a point of the map's rectangle ("" for the sea)
	if _region_img == null or _cam == null:
		return ""
	var sp := at * (Vector2(_vp.size) / _vpc.size) if _vpc.size.x > 0 else at
	var o := _cam.project_ray_origin(sp)
	var d := _cam.project_ray_normal(sp)
	if absf(d.y) < 0.0001:
		return ""
	return _land.region_of(o + d * ((0.15 - o.y) / d.y))

# ---------------- input ----------------
func _on_table_input(ev: InputEvent) -> void:
	# a tap picks the place under it; one finger (or the mouse) drags the map, two pinch it closer (or the wheel)
	if ev is InputEventMouse and (ev as InputEventMouse).device == InputEvent.DEVICE_ID_EMULATION:
		return                                   # (the phone's touches arrive as touches; skip their mouse copies)
	if ev is InputEventScreenTouch:
		var st := ev as InputEventScreenTouch
		if st.pressed:
			_touch[st.index] = st.position
			if _touch.size() == 1:
				_press_at = st.position
				_dragged = false
		else:
			_touch.erase(st.index)
			if _touch.is_empty():
				if not _dragged and _press_at != Vector2.INF and st.position.distance_to(_press_at) < 24.0:
					pick_at(st.position)
				_press_at = Vector2.INF
		return
	if ev is InputEventScreenDrag:
		var sd := ev as InputEventScreenDrag
		var before: Vector2 = _touch.get(sd.index, sd.position - sd.relative)
		_touch[sd.index] = sd.position
		if _touch.size() >= 2:
			var keys := _touch.keys()
			var other: Vector2 = _touch[keys[0] if keys[0] != sd.index else keys[1]]
			var d0 := before.distance_to(other)
			var d1 := sd.position.distance_to(other)
			if d0 > 4.0:
				_zoom *= d1 / d0
			_dragged = true
		else:
			if _press_at != Vector2.INF and sd.position.distance_to(_press_at) > 24.0:
				_dragged = true
			if _dragged:
				_pan_by(sd.relative)
		_apply_cam()
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom *= 1.12 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12
			_apply_cam()
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_press_at = mb.position
			_dragged = false
			_mouse_down = true
		else:
			if _mouse_down and not _dragged and _press_at != Vector2.INF and mb.position.distance_to(_press_at) < 24.0:
				pick_at(mb.position)
			_mouse_down = false
			_press_at = Vector2.INF
		return
	if ev is InputEventMouseMotion and _mouse_down:
		var mm := ev as InputEventMouseMotion
		if _press_at != Vector2.INF and mm.position.distance_to(_press_at) > 24.0:
			_dragged = true
		if _dragged:
			_pan_by(mm.relative)
			_apply_cam()
		return
	if ev is InputEventMagnifyGesture:
		_zoom *= (ev as InputEventMagnifyGesture).factor
		_apply_cam()
	elif ev is InputEventPanGesture:
		_pan_by(-(ev as InputEventPanGesture).delta * 12.0)
		_apply_cam()

func _pan_by(rel: Vector2) -> void:
	# the land follows the finger: a pixel is so much ground at the camera's distance
	if _cam == null or _vp.size.y <= 0:
		return
	var rel_vp := rel * (Vector2(_vp.size) / _vpc.size) if _vpc.size.x > 0 else rel
	var wpp := 2.0 * (_cam_dist / _zoom) * tan(deg_to_rad(CAM_FOV) * 0.5) / float(_vp.size.y)
	var elev := atan2(CAM_DIR.y, Vector2(CAM_DIR.x, CAM_DIR.z).length())
	_pan.x -= rel_vp.x * wpp
	_pan.y -= rel_vp.y * wpp / maxf(0.3, sin(elev))

func _apply_cam() -> void:
	# the camera: where _fit_camera put it, closer by the zoom, moved by the pan (kept over the land)
	_zoom = clampf(_zoom, 1.0, 3.2)
	var k := 1.0 - 1.0 / _zoom
	_pan.x = clampf(_pan.x, -4.0 * k, 4.0 * k)
	_pan.y = clampf(_pan.y, -7.0 * k, 7.0 * k)
	var dir := CAM_DIR.normalized()
	var at := _cam_at + Vector3(_pan.x, 0.0, _pan.y)
	_cam.transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), at + dir * (_cam_dist / _zoom))

func screen_of(id: String) -> Vector2:
	# where a place's centre is on the table, in this window's table rectangle
	return _screen(_tiles[id].pos)

func _screen(p: Vector3) -> Vector2:
	var sp := _cam.unproject_position(p)
	return sp * (_vpc.size / Vector2(_vp.size)) if _vp.size.x > 0 else sp

func pick_at(at: Vector2) -> String:
	# the place whose land is under the tap (or, on the sea, the nearest place's spot within reach)
	var best := region_at(at)
	if best == "":
		var best_d := 60.0
		for id in _tiles:
			var d := screen_of(id).distance_to(at)
			if d < best_d:
				best = id
				best_d = d
	if best != "":
		select(best)
	return best

func select(id: String) -> void:
	if id == sel:
		return
	app.sfx("tab")
	sel = id
	_dirty = true

# ---------------- every frame ----------------
func _fit_camera() -> void:
	# the camera looks at the land from CAM_DIR; how far back, and where it aims, are set so the whole land fills the
	# map's rectangle, under the NAMES button -- tall phone or short
	var sz := Vector2(_vp.size)
	_fit_size = _vp.size
	if sz.x < 8.0 or sz.y < 8.0:
		return
	var dir := CAM_DIR.normalized()
	var pts: Array[Vector3] = []
	for id in _tiles:
		var p: Vector3 = _tiles[id].pos
		for c in [Vector3(-1.5, 0.0, 0.0), Vector3(1.5, 0.0, 0.0), Vector3(0.0, 0.0, 1.4), Vector3(0.0, 0.0, -1.4), Vector3(0.0, 1.2, 0.0)]:
			pts.append(Vector3(p.x, 0.0, p.z) + c)
	var at := Vector3.ZERO
	var top := 42.0
	for pass_n in 3:
		var lo := 4.0
		var hi := 80.0
		for i in 22:
			var d := (lo + hi) * 0.5
			_cam.transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), at + dir * d)
			if _fits(pts, sz, top):
				hi = d
			else:
				lo = d
		_cam.transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), at + dir * hi)
		_cam_at = at
		_cam_dist = hi
		if pass_n == 2:
			break
		# centre it in the room left under the button
		var ymin := INF
		var ymax := -INF
		for q in pts:
			var sp := _cam.unproject_position(q)
			ymin = minf(ymin, sp.y)
			ymax = maxf(ymax, sp.y)
		var off_px := (ymin + ymax) * 0.5 - (top + sz.y - 8.0) * 0.5
		var per_px := 2.0 * hi * tan(deg_to_rad(_cam.fov) * 0.5) / sz.y
		at -= _cam.transform.basis.y * off_px * per_px
	_apply_cam()

func _fits(pts: Array[Vector3], sz: Vector2, top: float) -> bool:
	for q in pts:
		if _cam.is_position_behind(q):
			return false
		var sp := _cam.unproject_position(q)
		if sp.x < 6.0 or sp.y < top or sp.x > sz.x - 6.0 or sp.y > sz.y - 6.0:
			return false
	return true

func _process(delta: float) -> void:
	_clock += delta
	if _vp.size != _fit_size:
		_fit_camera()
	if _dirty:
		_dirty = false
		_render()
	# labels follow their places; the place picked lifts its miniature; crossed swords bob over a battle
	for id in _labels:
		var lp: PanelContainer = _labels[id]
		var p := _screen(_tiles[id].pos + Vector3(0, 0, 0.55))
		lp.position = (p - Vector2(lp.size.x * 0.5, 0.0)).round()
	_land.step(delta, sel)

# ---------------- the state ----------------
func _terr(id: String) -> Dictionary:
	return (social.war.get("terr", {}) as Dictionary).get(id, {})

func _render() -> void:
	var w: Dictionary = social.war
	# the table: holders, battles, the place picked (war_land_view.gd); the labels
	_land.paint(w, sel)
	for id in _tiles:
		var t := _terr(id)
		var h := str(t.get("h", ""))
		var col: Color = SocialUI.house_color(h) if h != "" else Color(0.85, 0.85, 0.8)
		var lp: PanelContainer = _labels[id]
		var sub: Label = lp.get_meta("sub")
		var tag := ""
		if t.has("b"):
			tag = "⚔ BATTLE"
			sub.add_theme_color_override("font_color", Color("#ffb066"))
		elif str(t.get("ct", "")) != "":
			tag = "[%s]" % str(t.ct)
			sub.add_theme_color_override("font_color", col.lightened(0.3))
		sub.text = tag
		sub.visible = tag != ""
		lp.visible = names or id == sel or t.has("b")
		var sb := lp.get_theme_stylebox("panel") as StyleBoxFlat
		sb.border_color = Color.WHITE if id == sel else Color(0, 0, 0, 0)
		sb.set_border_width_all(2 if id == sel else 0)
	# the strip over the map
	for c in _stats.get_children():
		c.queue_free()
	if w.is_empty():
		var l := UI.label(_stats, "Loading the war map..." if social.online() else "Not connected to the server", 12, UI2.MUTED, UI.HEAVY_FONT)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
	else:
		var left := maxi(0, int(w.get("ends", 0)) - int(Time.get_unix_time_from_system()))
		var el := UI.label(_stats, "WEEK ENDS IN %dd %dh" % [left / 86400, (left % 86400) / 3600], 12, UI2.SOFT, UI.HEAVY_FONT)
		el.autowrap_mode = TextServer.AUTOWRAP_OFF
		if str(w.get("house", "")) != "":
			var al := UI.label(_stats, "ATTEMPTS %d/%d" % [int(w.get("att", 0)), int(w.get("max", 5))], 12, UI2.GOLD, UI.HEAVY_FONT)
			al.autowrap_mode = TextServer.AUTOWRAP_OFF
			al.set_meta("action_key", "war_attempts")
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_stats.add_child(sp)
		var counts: Dictionary = w.get("counts", {})
		for h in Map.HOUSES:
			SocialUI.house_chip(_stats, h, 12.0)
			var cl := UI.label(_stats, str(int(counts.get(h, 0))), 13, SocialUI.house_color(h), UI.HEAVY_FONT)
			cl.autowrap_mode = TextServer.AUTOWRAP_OFF

	_render_sheet()

func _render_sheet() -> void:
	for c in _sheet.get_children():
		c.queue_free()
	var w: Dictionary = social.war
	if sel == "" or not Map.T.has(sel):
		UI2.text(_sheet, "THE WAR TABLE", 17, UI2.GOLD)
		var lines := ["Tap a territory to see who holds it and to attack it."]
		var house := str(w.get("house", ""))
		if house == "":
			lines.append("Join a clan to fight for a house: each clan's battles move its bars, and the first clan to fill a bar takes the territory.")
		else:
			lines.append("You fight for House %s. Attack along the links from land your house holds." % SocialUI.house_name(house))
		var last: Dictionary = w.get("last", {})
		if str(last.get("won", "")) != "":
			lines.append("Last week: House %s won." % SocialUI.house_name(str(last.won)))
		UI2.body(_sheet, " ".join(lines), 12, UI2.SOFT)
		if house == "":
			UI2.button(_sheet, "FIND A CLAN", "purple", func():
				app.sfx("menuOpen")
				app.open_clan(), "war_find_clan", 15, 40.0)
		return
	var t := _terr(sel)
	var h := str(t.get("h", ""))
	var hr := UI.row(_sheet, 8)
	if h != "":
		SocialUI.house_chip(hr, h, 16.0)
	UI.grow(UI2.text(hr, Map.name_of(sel).to_upper(), 18, Color.WHITE))
	if Map.is_home(sel):
		UI2.body(_sheet, "House %s's home -- it can never be lost. Homes come under attack on King's Day (coming later)." % SocialUI.house_name(h), 12, UI2.SOFT)
		return
	var held := "Free -- nobody holds it" if h == "" else "Held by House %s%s" % [SocialUI.house_name(h),
		("  ·  [%s] %s" % [str(t.get("ct", "")), str(t.get("cn", ""))]) if str(t.get("ct", "")) != "" else ""]
	var hl := UI.label(_sheet, held, 12, SocialUI.house_color(h) if h != "" else UI2.SOFT, UI.HEAVY_FONT)
	hl.autowrap_mode = TextServer.AUTOWRAP_OFF
	hl.clip_text = true
	var need := int(t.get("need", 0))
	for b in t.get("bars", []):
		_bar(_sheet, b, need)
	if (t.get("bars", []) as Array).is_empty():
		UI2.body(_sheet, "No clan has points here yet. %s points take it." % _num(need), 12, UI2.MUTED)
	var mine_house := str(w.get("house", ""))
	var on: Dictionary = t.get("b", {})
	if not on.is_empty():
		var bl := UI.label(_sheet, "⚔  BATTLE ON  ·  [%s] of House %s attacking" % [str(on.get("act", "")), SocialUI.house_name(str(on.get("ah", "")))], 12, Color("#ffb066"), UI.HEAVY_FONT)
		bl.autowrap_mode = TextServer.AUTOWRAP_OFF
		bl.clip_text = true
		var bid := str(on.get("bid", ""))
		if mine_house != "" and mine_house == str(on.get("ah", "")):
			UI2.button(_sheet, "JOIN THE BATTLE", "green", func():
				app.sfx("confirm")
				app.start_war(bid), "war_join", 16, 44.0)
		elif mine_house != "" and mine_house == h:
			UI2.button(_sheet, "DEFEND IT", "red", func():
				app.sfx("confirm")
				app.start_war(bid), "war_defend", 16, 44.0)
		return
	if mine_house == "":
		UI2.button(_sheet, "JOIN A CLAN TO FIGHT", "purple", func():
			app.sfx("menuOpen")
			app.open_clan(), "war_find_clan", 15, 40.0)
		return
	var why := str(t.get("why", ""))
	if why == "" and int(w.get("att", 0)) <= 0:
		why = "No battles left today -- join your clan's battles to help"
	var ar := UI.row(_sheet, 8)
	var ab := UI2.button(ar, "WAITING..." if _going else "ATTACK", "orange", func(): _attack(), "war_attack", 17, 46.0)
	UI.grow(ab)
	UI2.dim_button(ab, why != "" or _going)
	var cb := UI2.button(ar, ("☑" if call_clan else "☐") + " CALL CLAN", "blue" if call_clan else "grey", func():
		app.sfx("tab")
		call_clan = not call_clan
		_dirty = true, "war_call_toggle", 13, 46.0, 12.0)
	cb.custom_minimum_size.x = 128
	if why != "":
		UI2.body(_sheet, why, 12, Color("#ffb0a0"))

func _bar(parent: Node, b: Dictionary, need: int) -> void:
	var r := UI.row(parent, 6)
	var mine: bool = str(b.get("c", "")) == str(social.war.get("clan", ""))
	var tl := UI.label(r, "[%s]" % str(b.get("ct", "")), 12, SocialUI.house_color(str(b.get("h", ""))), UI.HEAVY_FONT)
	tl.autowrap_mode = TextServer.AUTOWRAP_OFF
	tl.custom_minimum_size.x = 52
	var pb := ProgressBar.new()
	pb.min_value = 0
	pb.max_value = maxi(1, need)
	pb.value = mini(int(b.get("p", 0)), need)
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 12)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(6)
	var fg := StyleBoxFlat.new()
	fg.bg_color = SocialUI.house_color(str(b.get("h", "")))
	fg.set_corner_radius_all(6)
	if mine:
		fg.border_color = Color.WHITE
		fg.set_border_width_all(1)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fg)
	r.add_child(pb)
	var nl := UI.label(r, "%s/%s" % [_num(int(b.get("p", 0))), _num(need)], 11, Color.WHITE if mine else UI2.SOFT, UI.HEAVY_FONT)
	nl.autowrap_mode = TextServer.AUTOWRAP_OFF

func _attack() -> void:
	if _going or sel == "":
		return
	if not social.war_go(sel, call_clan):
		app.sfx("error")
		app.toast("Not connected to the server right now", UI.RED)
		return
	app.sfx("tap")
	_going = true
	_dirty = true

static func _num(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out
