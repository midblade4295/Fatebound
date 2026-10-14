extends Control
# 0.31.135 (Kevin, Crown War step 2: "3D table map"): the war map as a war table. Each place of scripts/meta/war_map.gd
# is a KayKit hex tile on a wooden table (the model of what stands there: a mill, a church, a mine, a castle for the
# homes), on a plinth in the colour of the house that holds it, with that house's banner; links run between them. A
# battle on now pulses in orange. Under the table: the place tapped -- who holds it, the clans' capture bars, the
# battle on it (JOIN for your house, DEFEND for the holders) and ATTACK (with CALL MY CLAN), or why not. Above it:
# the week's end, your attempts today, and each house's land. The state is the server's (server/world.gd), pushed to
# scripts/meta/social.gd while this is open.
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const SocialUI = preload("res://scripts/app/social_ui.gd")
const Map = preload("res://scripts/meta/war_map.gd")
const Stage = preload("res://scripts/siege/asset_cache.gd")
const HEX := "res://assets/kaykit/hex/"
const S := 2.0                         # map units -> table units
const NEUTRAL := Color("#6f6a60")
const CAM_POS := Vector3(0.0, 17.0, 7.4)
const CAM_AT := Vector3(0.0, -0.6, 0.55)
const CAM_FOV := 33.0
const PLINTH_YAW := 0.0
const GROUND_TINT := Color(0.72, 0.9, 0.62)   # KayKit's grass is a yellow-green: a deeper green on the table
# what stands on each kind of place: [base tile, [model, scale, offset x, offset z, yaw]...]
const LOOKS := {
	"castle": ["hex_grass", [["building_castle_blue", 0.62, 0.0, 0.0, 0.0]]],
	"mill":   ["hex_grass", [["building_lumbermill_blue", 0.85, -0.1, 0.0, 0.6], ["tree_single_A", 1.6, 0.6, 0.45, 0.0]]],
	"tower":  ["hex_grass", [["building_tower_A_blue", 0.85, 0.0, 0.0, 0.0], ["tree_single_B", 1.4, -0.6, 0.4, 0.0]]],
	"abbey":  ["hex_grass", [["building_church_blue", 0.95, 0.0, 0.0, 0.3]]],
	"pass":   ["hex_grass", [["mountain_A_grass_trees", 0.78, 0.0, 0.0, 0.0]]],
	"quarry": ["hex_grass", [["rock_single_A", 2.6, -0.35, -0.2, 0.0], ["rock_single_C", 2.4, 0.35, 0.25, 1.0], ["resource_stone", 1.2, 0.1, -0.5, 0.0]]],
	"ford":   ["hex_road_A", [["tree_single_A", 1.5, 0.55, -0.45, 0.0], ["tree_single_B", 1.3, -0.55, 0.45, 0.0]]],
	"lake":   ["hex_water", []],
	"bridge": ["hex_road_B", [["building_tower_base_blue", 0.55, 0.0, 0.0, 0.0]]],
	"mine":   ["hex_grass", [["building_mine_blue", 0.8, 0.0, 0.0, 0.0]]],
	"marsh":  ["hex_grass", [["hills_C_trees", 0.85, 0.0, 0.0, 0.0]]],
	"woods":  ["hex_grass", [["trees_A_large", 0.95, 0.0, 0.0, 0.0]]],
	"forge":  ["hex_grass", [["building_blacksmith_blue", 0.95, 0.0, 0.0, 0.2]]],
	"cliffs": ["hex_grass", [["mountain_B_grass_trees", 0.72, 0.0, 0.0, 0.0]]],
	"fen":    ["hex_water", [["tree_single_B", 1.4, 0.3, 0.2, 0.0]]],
	"port":   ["hex_grass", [["building_market_blue", 0.85, 0.0, 0.0, -0.4], ["barrel", 1.6, 0.6, 0.5, 0.0]]],
}

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
var _tiles := {}                       # id -> {"pos": Vector3, "node": Node3D, "plinth": MeshInstance3D, "flag": Node3D, "ring": MeshInstance3D}
var _labels := {}                      # id -> PanelContainer over the table
var _mats := {}
var _clock := 0.0
var _press_at := Vector2.INF

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
	var sf := UI2.frame(body, "glass", 10, 16.0)
	sf.add_theme_constant_override("separation", 6)
	sf.custom_minimum_size.y = 150          # (the table doesn't jump about as the sheet changes)
	_sheet = sf
	_build_table()
	social.changed.connect(_on_changed)
	social.war_went.connect(_on_went)
	social.war_open()
	_render()

func _exit_tree() -> void:
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

# ---------------- the table (3D) ----------------
static func tile_pos(id: String) -> Vector3:
	# the map lies on its side so it fits a phone held upright: map y across, map x away from you (Lions near)
	var p: Vector2 = Map.T[id].p
	return Vector3((p.y - 2.65) * S, 0.0, (3.8 - p.x) * S)

func _mat(key: String, col: Color, emit := 0.0) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.85
		if emit > 0.0:
			m.emission_enabled = true
			m.emission = col
			m.emission_energy_multiplier = emit
		_mats[key] = m
	return _mats[key]

func _model(parent: Node3D, name: String, at: Vector3, scale: float, yaw := 0.0) -> Node3D:
	var ps: PackedScene = Stage.scene(HEX + name + ".gltf")
	if ps == null:
		return null
	var n := ps.instantiate() as Node3D
	n.position = at
	n.scale = Vector3.ONE * scale
	n.rotation.y = yaw
	parent.add_child(n)
	return n

func _tint(n: Node, col: Color) -> void:
	# the base tile only (the models share one atlas material): a tinted copy of it, kept for the whole table
	if n == null:
		return
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).get_active_material(0) as StandardMaterial3D
		if m == null:
			continue
		var key := "tint_%d" % m.get_instance_id()
		if not _mats.has(key):
			var d := m.duplicate() as StandardMaterial3D
			d.albedo_color = m.albedo_color * col
			_mats[key] = d
		(mi as MeshInstance3D).material_override = _mats[key]

func _build_table() -> void:
	var root := Node3D.new()
	_vp.add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#0b1024")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#c8d4ff")
	e.ambient_light_energy = 0.32
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-58.0), deg_to_rad(-32.0), 0.0)
	sun.light_energy = 0.8
	sun.light_color = Color("#fff1d8")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	root.add_child(sun)
	# the table and its cloth
	var table := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(10.6, 0.5, 16.0)
	table.mesh = tb
	table.position = Vector3(0, -1.32, 0)
	table.material_override = _mat("wood", Color("#5a3a22"))
	root.add_child(table)
	var cloth := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(9.6, 0.04, 15.0)
	cloth.mesh = cm
	cloth.position = Vector3(0, -1.06, 0)
	cloth.material_override = _mat("cloth", Color("#c9b48a"))
	root.add_child(cloth)
	# links: planks between the places (seen in the gaps between the tiles)
	for l in Map.LINKS:
		var a := tile_pos(str(l[0]))
		var b := tile_pos(str(l[1]))
		var mid := (a + b) * 0.5
		var d := b - a
		var lk := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(0.3, 0.1, d.length())
		lk.mesh = lb
		lk.position = Vector3(mid.x, -0.33, mid.z)
		lk.rotation.y = atan2(d.x, d.z)
		lk.material_override = _mat("link", Color("#b08a52"))
		root.add_child(lk)
	# the places
	for id in Map.T:
		var pos := tile_pos(id)
		var t := Node3D.new()
		t.position = pos
		root.add_child(t)
		var plinth := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.radial_segments = 6
		pm.top_radius = 1.3
		pm.bottom_radius = 1.36
		pm.height = 0.9
		plinth.mesh = pm
		plinth.position = Vector3(0, -0.72, 0)                # (its top a ledge just under the tile's -- and the water's -- in the holder's colour)
		plinth.rotation.y = PLINTH_YAW
		plinth.material_override = _mat("neutral", NEUTRAL)
		t.add_child(plinth)
		var look: Array = LOOKS.get(str(Map.T[id].look), LOOKS.lake)
		var tile := _model(t, str(look[0]), Vector3.ZERO, 1.0, PI * 0.5)
		_tint(tile, GROUND_TINT)
		for d in look[1]:
			_model(t, str(d[0]), Vector3(float(d[2]), 0.0, float(d[3])), float(d[1]), float(d[4]))
		var ring := MeshInstance3D.new()
		var rm := TorusMesh.new()
		rm.inner_radius = 1.2
		rm.outer_radius = 1.42
		rm.rings = 24
		rm.ring_segments = 6
		ring.mesh = rm
		ring.position = Vector3(0, 0.08, 0)
		ring.material_override = _mat("battle", Color("#ff8a2a"), 2.0)
		ring.visible = false
		t.add_child(ring)
		_tiles[id] = {"pos":pos, "node":t, "plinth":plinth, "tile":tile, "flag":null, "ring":ring}
	_cam = Camera3D.new()
	_cam.fov = CAM_FOV
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_cam.transform = Transform3D(Basis.looking_at(CAM_AT - CAM_POS, Vector3.UP), CAM_POS)   # (not in the tree yet)
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

func _flag(id: String, col: Color, big: bool) -> void:
	# the holder's banner on a place (or none)
	var t: Dictionary = _tiles[id]
	if t.flag != null:
		(t.flag as Node3D).queue_free()
		t.flag = null
	if col == Color.TRANSPARENT:
		return
	var f := Node3D.new()
	f.position = Vector3(0.62, 0.0, 0.5) if not big else Vector3(0.75, 0.0, 0.62)
	var h := 1.5 if not big else 2.3
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.035
	pm.bottom_radius = 0.045
	pm.height = h
	pole.mesh = pm
	pole.position = Vector3(0, h * 0.5, 0)
	pole.material_override = _mat("pole", Color("#3b2a1a"))
	f.add_child(pole)
	var cloth := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.62 if not big else 0.9, 0.42 if not big else 0.6, 0.04)
	cloth.mesh = cm
	cloth.position = Vector3(cm.size.x * 0.5 + 0.03, h - cm.size.y * 0.5 - 0.04, 0)
	cloth.material_override = _mat("flag_" + col.to_html(), col, 0.25)
	f.add_child(cloth)
	(t.node as Node3D).add_child(f)
	t.flag = f

# ---------------- input ----------------
func _on_table_input(ev: InputEvent) -> void:
	var at := Vector2.INF
	var down := false
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		at = (ev as InputEventMouseButton).position
		down = ev.pressed
	elif ev is InputEventScreenTouch:
		at = (ev as InputEventScreenTouch).position
		down = ev.pressed
	if at == Vector2.INF:
		return
	if down:
		_press_at = at
		return
	if _press_at != Vector2.INF and at.distance_to(_press_at) < 24.0:
		pick_at(at)
	_press_at = Vector2.INF

func screen_of(id: String) -> Vector2:
	# where a place's centre is on the table, in this window's table rectangle
	return _screen(_tiles[id].pos)

func _screen(p: Vector3) -> Vector2:
	var sp := _cam.unproject_position(p)
	return sp * (_vpc.size / Vector2(_vp.size)) if _vp.size.x > 0 else sp

func pick_at(at: Vector2) -> String:
	var best := ""
	var best_d := 70.0
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
func _process(delta: float) -> void:
	_clock += delta
	if _dirty:
		_dirty = false
		_render()
	# labels follow their places; the battle rings pulse; the place picked stands up a little
	for id in _labels:
		var lp: PanelContainer = _labels[id]
		var p := _screen(_tiles[id].pos + Vector3(0, 0, 0.7))     # (on the tile's near edge, clear of what stands on it)
		lp.position = (p - Vector2(lp.size.x * 0.5, 0.0)).round()
	for id in _tiles:
		var t: Dictionary = _tiles[id]
		var n: Node3D = t.node
		var want := 0.28 if id == sel else 0.0
		n.position.y = lerpf(n.position.y, want, minf(1.0, delta * 10.0))
		var r: MeshInstance3D = t.ring
		if r.visible:
			var k := 0.5 + 0.5 * sin(_clock * 5.0)
			r.scale = Vector3.ONE * (1.0 + 0.06 * k)

# ---------------- the state ----------------
func _terr(id: String) -> Dictionary:
	return (social.war.get("terr", {}) as Dictionary).get(id, {})

func _render() -> void:
	var w: Dictionary = social.war
	# the table: holders, banners, battles
	for id in _tiles:
		var t := _terr(id)
		var h := str(t.get("h", ""))
		var col: Color = SocialUI.house_color(h) if h != "" else NEUTRAL
		(_tiles[id].plinth as MeshInstance3D).material_override = _mat("plinth_" + h, col.darkened(0.15)) if h != "" else _mat("neutral", NEUTRAL)
		_flag(id, SocialUI.house_color(h) if h != "" else Color.TRANSPARENT, Map.is_home(id))
		(_tiles[id].ring as MeshInstance3D).visible = t.has("b")
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
		var sb := lp.get_theme_stylebox("panel") as StyleBoxFlat
		sb.border_color = Color.WHITE if id == sel else Color(0, 0, 0, 0)
		sb.set_border_width_all(2 if id == sel else 0)
	# the strip over the table
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
