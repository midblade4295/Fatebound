extends Control
# 0.31.135 (Kevin, Crown War step 2): the war map. 0.31.137 (Kevin: "I don't like how static the map looks. I want it
# to look like a real natural land mass but in map form"): one continent in a living sea (tools/war_land.py makes it:
# coast, mountains, the river through Silver Lake, marsh and fen, farmland, forests, roads along the links, a ridge on
# every border without one), each place's land tinted with the colour of the house that holds it and outlined, its
# Meshy miniature (0.31.136) standing in it, the sea's waves and foam moving, cloud shadows drifting over it all.
# Tap a place's land to pick it. Under the map: the place picked -- who holds it, the clans' capture bars, the battle
# on it (JOIN for your house, DEFEND for the holders) and ATTACK (with CALL CLAN), or why not. Above it: the week's
# end and each house's land (0.31.135-0.31.149: your attempts today too). The state is the server's (server/world.gd), pushed to
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
const Tour = preload("res://scripts/app/war_tour.gd")   # 0.31.147: the Herald's tour of the map
# 0.31.147 (Kevin: "then the map opens up have camera zoom to it as animation"): the window fades in while the camera
# dives from high and far onto the land, settling where _fit_camera put it (reduce motion: none of it)
const INTRO_SECS := 1.0
const INTRO_FADE := 0.3
const INTRO_FAR := 1.75                    # how much farther away it starts
const INTRO_RISE := 14.0                   # how much higher (CAM_DIR's height): it starts looking down on the land

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
var _hot: VBoxContainer                # 0.31.149: BATTLES NOW, the hot zones (QUICK BATTLE's place, 0.31.145-0.31.148)
var _join_after := ""                  # 0.31.149: a battle to go into once the house clan has taken us in
var _join_house := ""
var _join_at := 0.0
const HOT_ROWS := 2                    # battles listed under the map (the rest glow on it)
var _held_room: Node = null            # 0.31.145: Home's 3D, held still behind the window
var _held_mode := Node.PROCESS_MODE_INHERIT
var calm := false                      # reduce motion: no swoop, no glides
var _intro_on := false                 # 0.31.147: the opening swoop running
var _intro_t := 0.0
var _intro_frames := 0
var _cam_tw: Tween = null              # the tour's camera glides
var _tour: Control = null              # 0.31.147: the Herald's tour (war_tour.gd), while it runs
var _tour_checked := false             # (the first-time tour: looked at once the map has the war on it)
var _touched := false                  # the player has tapped or moved the map (the first-time tour then waits)
var _help_btn: Button

func open(a, first := "", swoop := true) -> void:
	app = a
	social = a.social
	sel = first
	calm = bool(a.profile.d.settings.get("reduce_motion", false)) if a.get("profile") != null else false
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
	_help_button()
	var sf := UI2.frame(body, "glass", 10, 16.0)
	sf.add_theme_constant_override("separation", 6)
	sf.custom_minimum_size.y = 150          # (the table doesn't jump about as the sheet changes)
	_sheet = sf
	# 0.31.149 (Kevin: "Remove the quick play so the player needs to choose where to fight. Maybe show hot zones where
	# players are actively fighting and players can jump right into that battle"): QUICK BATTLE (0.31.145) is gone; at
	# the map's foot, BATTLES NOW -- the battles on the map, the ones you can fight in first, each with JOIN / DEFEND (not
	# in a clan: JOIN <its house>, which puts you in that house's clan and into the battle in one tap)
	_hot = UI2.frame(body, "night", 8, 14.0, "orange")
	_hot.add_theme_constant_override("separation", 4)
	(_hot.get_parent() as Control).name = "HotZones"
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
	_intro_on = swoop and not calm
	if _intro_on:
		modulate.a = 0.0

func _help_button() -> void:
	# 0.31.147: "?" beside NAMES -- the Herald's tour again
	_help_btn = UI2.button(_overlay, "?", "grey", func():
		app.sfx("menuOpen")
		start_tour(), "war_help", 14, 28.0, 9.0)
	_help_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_help_btn.offset_left = -112
	_help_btn.offset_right = -76
	_help_btn.offset_top = 6
	_help_btn.offset_bottom = 34

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
	if what in ["war", "state", "clan", "me", "party"]:
		_dirty = true
	if what == "clan" and str(social.clan.get("house", "")) != str(social.war.get("house", "")):
		social.war_open()                      # (0.31.149: joined or left a clan -- the map again, for your house now)

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
	if ev is InputEventScreenTouch or ev is InputEventScreenDrag or ev is InputEventMouseButton or ev is InputEventMagnifyGesture \
			or ev is InputEventPanGesture or (ev is InputEventMouseMotion and _mouse_down):
		_touched = true                          # (the player's hands on the map: the swoop and any glide give way)
		if _intro_on:
			_end_intro()
		if _cam_tw != null and _cam_tw.is_valid():
			_cam_tw.kill()
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
	var e := _intro_ease()
	var dir := (CAM_DIR + Vector3(0.0, INTRO_RISE * (1.0 - e), 0.0)).normalized()
	var at := _cam_at + Vector3(_pan.x, 0.0, _pan.y)
	_cam.transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), at + dir * (_cam_dist / _zoom) * lerpf(INTRO_FAR, 1.0, e))

func _intro_ease() -> float:
	# the opening swoop's progress, eased out (1: done)
	if not _intro_on:
		return 1.0
	var f := clampf(_intro_t / INTRO_SECS, 0.0, 1.0)
	return 1.0 - pow(1.0 - f, 3.0)

func _end_intro() -> void:
	_intro_on = false
	modulate.a = 1.0
	if _cam != null:
		_apply_cam()

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
	if _intro_on:
		if _intro_frames < 2:
			_intro_frames += 1                   # (the window's first frames are its slowest: the swoop starts after them)
		else:
			_intro_t += delta
		modulate.a = clampf(_intro_t / INTRO_FADE, 0.0, 1.0)
		if _intro_t >= INTRO_SECS:
			_end_intro()
		else:
			_apply_cam()
	elif not _tour_checked:
		_first_tour()
	_join_tick()
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
			var fighting := int(t.b.get("na", 0)) + int(t.b.get("nd", 0))
			tag = ("⚔ %d FIGHTING" % fighting) if fighting > 0 else "⚔ BATTLE"
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
	_render_hot()
	if w.is_empty():
		# 0.31.146: PLAY always opens the map -- not connected, or a server from before the war map: say so
		var msg := "Not connected to the server"
		if social.online():
			msg = "Loading the war map..." if social.has_war else "The war map comes with the next server update"
		var l := UI.label(_stats, msg, 12, UI2.MUTED, UI.HEAVY_FONT)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
	else:
		var left := maxi(0, int(w.get("ends", 0)) - int(Time.get_unix_time_from_system()))
		var el := UI.label(_stats, "WEEK ENDS IN %dd %dh" % [left / 86400, (left % 86400) / 3600], 12, UI2.SOFT, UI.HEAVY_FONT)
		el.autowrap_mode = TextServer.AUTOWRAP_OFF
		# (0.31.135-0.31.149: ATTEMPTS n/5 here. 0.31.150, Kevin: "Remove the 5 battle daily" -- every battle counts)
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
			UI2.button(_sheet, "JOIN A CLAN", "purple", func():
				app.sfx("menuOpen")
				app.open_clan("join"), "war_find_clan", 15, 40.0)
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
		elif mine_house == "" and not social.in_clan():
			# 0.31.149: not in a clan -- either side's house clan and into the battle
			var jr := UI.row(_sheet, 8)
			var ah := str(on.get("ah", ""))
			UI.grow(UI2.button(jr, "JOIN %s" % SocialUI.house_name(ah).to_upper(), SocialUI.house_button(ah), func():
				_fight_for(ah, bid), "war_fight_att", 15, 44.0))
			if h != "":
				UI.grow(UI2.button(jr, "DEFEND FOR %s" % SocialUI.house_name(h).to_upper(), SocialUI.house_button(h), func():
					_fight_for(h, bid), "war_fight_def", 15, 44.0))
		return
	if mine_house == "":
		UI2.button(_sheet, "JOIN A CLAN TO FIGHT", "purple", func():
			app.sfx("menuOpen")
			app.open_clan("join"), "war_find_clan", 15, 40.0)
		return
	var why := str(t.get("why", ""))
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

# ---------------- BATTLES NOW: the hot zones (0.31.149) ----------------
func hot_list() -> Array:
	# the battles on the map now -- {tid, b, h (who holds it), n (players in it), can: "att" / "def" / "free" (not in a
	# clan: either side) / "" (two other houses' war)} -- the ones you can fight in first, then the busiest
	var out := []
	var mine := str(social.war.get("house", ""))
	var free: bool = mine == "" and not social.in_clan()
	for id in Map.T:
		var t := _terr(id)
		if not t.has("b"):
			continue
		var b: Dictionary = t.b
		var h := str(t.get("h", ""))
		var can := ""
		if free:
			can = "free"
		elif mine != "" and mine == str(b.get("ah", "")):
			can = "att"
		elif mine != "" and h != "" and mine == h:
			can = "def"
		out.append({"tid":id, "b":b, "h":h, "n":int(b.get("na", 0)) + int(b.get("nd", 0)), "can":can})
	out.sort_custom(func(x, y):
		if (str(x.can) != "") != (str(y.can) != ""):
			return str(x.can) != ""
		return int(x.n) > int(y.n))
	return out

func _render_hot() -> void:
	for c in _hot.get_children():
		_hot.remove_child(c)
		c.queue_free()
	var hot := hot_list()
	var hr := UI.row(_hot, 6)
	var tl := UI2.text(hr, "🔥 BATTLES NOW", 14, Color("#ffb066"))
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not hot.is_empty():
		var nl := UI.label(hr, "%d ON" % hot.size(), 12, UI2.MUTED, UI.HEAVY_FONT)
		nl.autowrap_mode = TextServer.AUTOWRAP_OFF
	if social.war.is_empty():
		if social.online() and not social.has_war:
			# a server from before the war map: nowhere to pick -- a match from matchmaking until it's updated
			UI2.button(_hot, "PLAY A MATCH", "green", func():
				app.sfx("confirm")
				app.quick_battle(), "war_old_play", 15, 42.0)
		else:
			UI2.body(_hot, "Not connected to the server" if not social.online() else "Loading the war map...", 12, UI2.MUTED)
		return
	if hot.is_empty():
		var tip := "No battles right now. Tap a land and ATTACK to start one."
		if str(social.war.get("house", "")) == "" and not social.in_clan():
			tip = "No battles right now. Join a clan, then tap a land and ATTACK to start one."
		UI2.body(_hot, tip, 12, UI2.SOFT)
		return
	for i in mini(HOT_ROWS, hot.size()):
		_hot_row(hot[i])
	if hot.size() > HOT_ROWS:
		UI2.body(_hot, "+%d more glowing on the map" % (hot.size() - HOT_ROWS), 11, UI2.MUTED)

func _hot_row(z: Dictionary) -> void:
	var tid := str(z.tid)
	var b: Dictionary = z.b
	var bid := str(b.get("bid", ""))
	var ah := str(b.get("ah", ""))
	var h := str(z.h)
	var r := UI.row(_hot, 8)
	var ic := UI2.icon(r, "swords", 30.0)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.modulate = Color("#ffb066")
	# the place and who's fighting: a tap shows it on the map
	var nb := Button.new()
	nb.flat = true
	nb.focus_mode = Control.FOCUS_NONE
	nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nb.clip_text = true
	nb.custom_minimum_size = Vector2(0, 42)
	for st_name in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		nb.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	nb.set_meta("action_key", "war_hot_" + tid)
	nb.pressed.connect(func():
		app.sfx("tab")
		_touched = true
		tour_camera(["focus", tid, 1.8], tid))
	r.add_child(nb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -3)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nb.add_child(v)
	var name_l := UI2.text(v, Map.name_of(tid).to_upper(), 15, Color.WHITE)
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_l.clip_text = true
	var who := "%s attack %s" % [SocialUI.house_name(ah), SocialUI.house_name(h) if h != "" else "free land"]
	var n := int(z.n)
	var state := ("%d fighting" % n) if n > 0 else ("starting" if str(b.get("state", "")) == "lobby" else "bots only")
	var sl := UI.label(v, "%s  ·  %s" % [who, state], 11, Color("#ffcf9a"), UI.HEAVY_FONT)
	sl.autowrap_mode = TextServer.AUTOWRAP_OFF
	sl.clip_text = true
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var go: Button
	match str(z.can):
		"att":
			go = UI2.button(r, "JOIN", "green", func():
				app.sfx("confirm")
				app.start_war(bid), "war_hot_join_" + tid, 15, 40.0, 12.0)
		"def":
			go = UI2.button(r, "DEFEND", "red", func():
				app.sfx("confirm")
				app.start_war(bid), "war_hot_defend_" + tid, 15, 40.0, 12.0)
		"free":
			go = UI2.button(r, "JOIN %s" % SocialUI.house_name(ah).to_upper(), SocialUI.house_button(ah), func():
				_fight_for(ah, bid), "war_hot_fight_" + tid, 13, 40.0, 12.0)
		_:
			var ol := UI.label(r, "NOT YOUR\nHOUSE", 10, UI2.MUTED, UI.HEAVY_FONT)
			ol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if go != null:
		go.custom_minimum_size.x = 96
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER

func _fight_for(house: String, bid: String) -> void:
	# 0.31.149: not in a clan -- into that house's own clan (free, open to all), then into the battle
	var hc := {}
	for c in social.house_clans:
		if str(c.get("house", "")) == house:
			hc = c
	if hc.is_empty():
		app.sfx("menuOpen")
		app.open_clan("join")
		return
	if not social.clan_join(str(hc.get("id", ""))):
		app.sfx("error")
		app.toast("Not connected to the server right now", UI.RED)
		return
	app.sfx("confirm")
	app.toast("Joining %s..." % str(hc.get("name", "the house's clan")), UI.GOLD)
	_join_after = bid
	_join_house = house
	_join_at = _clock

func _join_tick() -> void:
	# into the battle once the house clan has us (or give up after a while)
	if _join_after == "":
		return
	if social.in_clan() and str(social.clan.get("house", "")) == _join_house:
		var b := _join_after
		_join_after = ""
		app.start_war(b)
	elif _clock - _join_at > 8.0:
		_join_after = ""
		app.toast("Couldn't join right now -- try again", UI.RED)

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

# ---------------- the Herald's tour (0.31.147, war_tour.gd) ----------------
func _first_tour() -> void:
	# the first time this phone's map has the war on it (and the player hasn't started using it): the tour, by itself
	if social.war.is_empty():
		return
	_tour_checked = true
	if not _touched and app.has_method("war_tour_due") and app.war_tour_due():
		start_tour()

func start_tour() -> void:
	if is_instance_valid(_tour):
		return
	_tour_checked = true
	if _intro_on:
		_end_intro()
	_tour = Tour.new()
	add_child(_tour)
	_tour.finished.connect(_on_tour_finished)
	_tour.begin(self, app)

func touring() -> bool:
	return is_instance_valid(_tour)

func _on_tour_finished(how: String) -> void:
	if app.has_method("war_tour_seen"):
		app.war_tour_seen()
	if is_instance_valid(_tour):
		_tour.queue_free()
	_tour = null
	tour_camera(["overview"], "")
	if how == "join":
		app.open_clan("join")

func tour_camera(cmd: Array, pick: String) -> void:
	# the tour's camera: the whole land (["overview"]), or close on a place (["focus", id, zoom]); `pick` is picked
	if pick != sel:
		sel = pick
		_dirty = true
	var z := 1.0
	var pan := Vector2.ZERO
	if cmd.size() >= 2 and str(cmd[0]) == "focus" and _tiles.has(str(cmd[1])):
		z = float(cmd[2]) if cmd.size() >= 3 else 2.0
		var p: Vector3 = _tiles[str(cmd[1])].pos
		pan = Vector2(p.x - _cam_at.x, p.z - _cam_at.z)
	_glide(z, pan)

func _glide(z: float, pan: Vector2, secs := 0.9) -> void:
	if _cam_tw != null and _cam_tw.is_valid():
		_cam_tw.kill()
	if calm:
		_zoom = z
		_pan = pan
		_apply_cam()
		return
	var z0 := _zoom
	var p0 := _pan
	_cam_tw = create_tween()
	_cam_tw.tween_method(func(f: float):
		_zoom = lerpf(z0, z, f)
		_pan = p0.lerp(pan, f)
		_apply_cam(), 0.0, 1.0, secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func tour_rect(what: String) -> Rect2:
	# where a part of this window is on the screen (the tour's spotlight)
	match what:
		"map":
			return _vpc.get_global_rect()
		"sheet":
			return (_sheet.get_parent() as Control).get_global_rect()
		"stats":
			return _stats.get_global_rect()
		"hot":
			return (_hot.get_parent() as Control).get_global_rect()
	return Rect2()
