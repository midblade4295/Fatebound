extends Control
# 0.31.208 (Kevin: "Make a all new loading screen graphic and as players join it'll show their character along with
# cosmetics they are wearing in the loading screen"): the match's loading screen -- one screen from PLAY until the battle
# shows. A painted courtyard at dusk (assets/ui/v2/bg_loading.webp; art_sources/loading), the title over its sky, and on
# its plaza, in 3D, the players coming to the battle: each one's hero in the outfit they wear on him, dropping in as they
# join (a burst of gold where they land), their name and the outfit's under them; you in the middle, ringed in gold.
#   connecting  you on the plaza, the ring spinning
#   lobby       the server's "lobby" messages (every half second): the countdown to the battle, who's joining -- their
#               heroes and outfits from its "hr"/"sk" (a server before 0.31.208 sends only names: a shadow for each of
#               the others), how many players are on, whether a battle is already running
#   loading     the battle's being built behind it (siege_mode's loading card; offline it's the only state): PREPARING
#               THE BATTLEFIELD, no LEAVE; it lifts with the match's warm-up
#   failed      CAN'T JOIN and why
# (0.31.82-0.31.207: lobby_panel.gd -- a countdown and a list of names; and the FATEBOUND card on the castle wall.)
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const View = preload("res://scripts/siege/siege_view.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const Moba = preload("res://scripts/siege/moba.gd")
const TitleLogo = preload("res://scripts/app/title_logo.gd")

signal leave

const BG := "res://assets/ui/v2/bg_loading.webp"
const MAX_FIGS := 10
const GOLD := Color("#ffd65a")
const HOT := Color("#ff8a3d")
const SPACING := 1.45                 # metres between heroes in a row
const ROW_MAX := 5
const BACK_Z := -1.7                  # the second row: behind, between, on the step
const BACK_Y := 0.8
const STAGE_TOP := 0.03               # the 3D stage's band of the screen (of its height; 0.22-0.74 in portrait)
const STAGE_BOTTOM := 0.84
const CAM_MIN := 10.0                 # the camera at least this far back (7.2 in portrait: the band was narrower)
const SIDE_W := 200.0                 # 0.31.216 (landscape): the countdown's column on the left, the words and LEAVE's on the right
const VFOV := 30.0
const DROP_H := 4.0                   # a joining hero drops from this high...
const DROP_T := 0.37                  # ...in this long: the second half of his own leap in (the rig's Spawn_Air, from
const LEAP_FROM := 0.37               # its top at 0.37 s to its landing at 0.74 s), on top of it
const RES_SCALE := 0.75               # the stage drawn at 3/4 of the screen's pixels

var audio: Node = null
var my_hero := ""                     # (siege_mode: the hero I play and the outfit I wear on him -- shown at once)
var my_skin := ""
var my_name := ""
var state := "connecting"
var left := -1.0
var wait := 20.0
var note_text := ""
var _last_sec := -1
var _spin := 0.0
var _first := true

# the stage
var viewport: SubViewport
var stage_tex: TextureRect
var world: Node3D
var cam: Camera3D
var _cam_d := 8.0                     # the camera's distance now (eases to _cam_want as heroes come and go)
var _cam_want := 8.0
var _cam_z := 0.0
var _cam_z_want := 0.0
var _vis_w := 4.0
var _cam_lift := 0.0                  # (two rows: the camera higher, to see the second over the first)
var _cam_lift_want := 0.0
var figs := {}                        # key ("name#n") -> {key, name, hero, skin, me, unknown, holder, body, player, shadow, plate, at, t0, drop, gone}
var _order: Array = []                # keys in join order
var plates_layer: Control

# the UI
var title: Label
var ring: Control
var number: Label
var mode_lbl: Label
var count_row: Control
var count_lbl: Label
var sub_lbl: Label
var leave_btn: Button
var status_box: VBoxContainer
var joined_n := 0                     # (tests: heroes that dropped in)

var _built := false                   # the stage and the words (built the frame after the painting: PLAY stays quick)
var _pending: Dictionary = {}         # a lobby message before then
var _fail_why := ""

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 50                                   # over the HUD (100 as the loading card: loading())
	_build_bg()
	_build_top()

func _ready() -> void:
	_build_rest.call_deferred()

func _build_rest() -> void:
	# the plaza's stage and the countdown, then whatever came before them; my hero drops in
	if _built or not is_inside_tree():
		return
	_build_stage()
	_build_status()
	_built = true
	resized.connect(_resize)
	_resize()
	if state == "loading":
		_apply_loading()
	elif state == "failed":
		_apply_fail()
	if not _pending.is_empty():
		var m := _pending
		_pending = {}
		update(m)
	if note_text != "":
		sub_lbl.text = note_text
	if my_hero != "" and figs.is_empty():
		_set_lineup([{"key":"me", "name":my_name if my_name != "" else "You", "hero":my_hero, "skin":my_skin, "me":true}])

# ---------------- the painting ----------------
func _build_bg() -> void:
	var tex := UI2.tex(BG)
	if tex != null:
		var bg := TextureRect.new()
		bg.texture = tex
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.name = "Background"
		add_child(bg)
	else:
		# (no ui pack yet: dusk in a gradient)
		var g := TextureRect.new()
		var gt := GradientTexture2D.new()
		var gr := Gradient.new()
		gr.set_color(0, Color("#5a2a4a"))
		gr.set_color(1, Color("#0c0a14"))
		gt.gradient = gr
		gt.fill_from = Vector2(0.5, 0.0)
		gt.fill_to = Vector2(0.5, 1.0)
		gt.width = 8
		gt.height = 128
		g.texture = gt
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_SCALE
		g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(g)
	# the bottom darkened a little more under the words and the button
	var shade := TextureRect.new()
	var st := GradientTexture2D.new()
	var sg := Gradient.new()
	sg.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	sg.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0.03, 0.02, 0.05, 0.0), Color(0.03, 0.02, 0.05, 0.78)])
	st.gradient = sg
	st.fill_from = Vector2(0.5, 0.0)
	st.fill_to = Vector2(0.5, 1.0)
	st.width = 4
	st.height = 256
	shade.texture = st
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

# ---------------- the stage (3D) ----------------
func _build_stage() -> void:
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED        # (as the menus' hero: MSAA's pipelines aren't pre-compiled)
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport)
	stage_tex = TextureRect.new()
	stage_tex.texture = viewport.get_texture()
	stage_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stage_tex.stretch_mode = TextureRect.STRETCH_SCALE
	stage_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_tex.name = "Stage"
	add_child(stage_tex)
	plates_layer = Control.new()
	plates_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plates_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plates_layer)
	world = Node3D.new()
	viewport.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#e6cfd6")
	env.ambient_light_energy = 0.6 * View.VULKAN_AMBIENT
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.9 * View.VULKAN_EXPOSURE
	env.tonemap_white = 3.0
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	# the painting's light: the sunset low behind (a warm rim), the braziers either side, a soft key from the front
	var key := DirectionalLight3D.new()
	key.light_color = Color("#ffe6c8")
	key.light_energy = 1.1
	key.rotation_degrees = Vector3(-24, 18, 0)
	world.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("#ff9a5a")
	rim.light_energy = 1.4
	rim.rotation_degrees = Vector3(-14, 180, 0)
	world.add_child(rim)
	for sx in [-1.0, 1.0]:
		var fire := OmniLight3D.new()
		fire.light_color = Color("#ff8a3a")
		fire.light_energy = 2.4
		fire.omni_range = 9.0
		fire.position = Vector3(sx * 5.5, 2.2, -2.5)
		world.add_child(fire)
	cam = Camera3D.new()
	cam.fov = VFOV
	cam.current = true
	world.add_child(cam)
	_place_cam()

func _resize() -> void:
	var top := size.y * STAGE_TOP
	var h := size.y * (STAGE_BOTTOM - STAGE_TOP)
	stage_tex.position = Vector2(0.0, top)
	stage_tex.size = Vector2(size.x, h)
	var logical := get_viewport().get_visible_rect().size if is_inside_tree() else size
	var window := Vector2(DisplayServer.window_get_size())
	var ratio := 1.0
	if logical.x > 0.0 and window.x > 0.0:
		ratio = clampf(window.x / logical.x, 1.0, 4.0)
	ratio *= RES_SCALE
	viewport.size = Vector2i(maxi(64, int(size.x * ratio)), maxi(64, int(h * ratio)))
	_fit()
	_size_plates()

func _fit() -> void:
	# the camera far enough back that the widest row fits (closer for one or two: they stand tall)
	var n := 0
	for k in _order:
		if not bool(figs[k].gone):
			n += 1
	var per_row := mini(maxi(n, 1), ROW_MAX)
	var width := float(per_row - 1) * SPACING + (1.9 if per_row == 1 else 3.1) + (SPACING * 0.5 if n > ROW_MAX else 0.0)
	var aspect := float(viewport.size.x) / maxf(1.0, float(viewport.size.y))
	var half_h := tan(deg_to_rad(VFOV) * 0.5) * aspect
	_cam_want = clampf(width / (2.0 * half_h), CAM_MIN, 16.0)
	_vis_w = 2.0 * _cam_want * half_h                # (the plaza's width across the screen at the heroes)
	_cam_z_want = BACK_Z * 0.35 if n > ROW_MAX else 0.0
	_cam_lift_want = 1.1 if n > ROW_MAX else 0.0

func _place_cam() -> void:
	# a little above the heroes' heads, looking down at their waists (more from farther back)
	var eye := Vector3(0.0, 1.55 + 0.1 * _cam_d + _cam_lift, _cam_z + _cam_d)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0.0, 0.95, _cam_z) - eye, Vector3.UP), eye)

func _slots(n: int) -> Array:
	# n places: the front row first, the middle first then out to either side; past five, a second row behind,
	# between them and a step up
	var out := []
	var front := mini(n, ROW_MAX)
	var back := n - front
	for row in [[front, 0.0, 0.0, 0.0], [back, BACK_Z, BACK_Y, SPACING * 0.5]]:
		var cnt := int(row[0])
		var order := []
		for i in cnt:
			order.append(0 if i == 0 else (int((i + 1) / 2) * (1 if i % 2 == 1 else -1)))
		# centred: a row of an even count shifts half a place
		var shift := 0.0 if cnt % 2 == 1 else -0.5
		for o in order:
			var x := (float(o) + shift) * SPACING + (float(row[3]) if cnt % 2 == 1 else 0.0)
			out.append(Vector3(x, float(row[2]), float(row[1]) - absf(float(o)) * 0.18))
	return out

# ---------------- the heroes ----------------
static func look_of(hero: String) -> String:
	return str(Eco.UP_LOOK.get(hero, hero)) if View.LOOKS.has(str(Eco.UP_LOOK.get(hero, hero))) else "knight"

func _set_lineup(list: Array) -> void:
	# list: [{key, name, hero, skin, me, unknown}] in the server's order (who came first first)
	var keys := {}
	for e in list.slice(0, MAX_FIGS):
		keys[str(e.key)] = true
	for k in _order.duplicate():
		if not keys.has(k) and not bool(figs[k].gone):
			_remove_fig(k)
	var joined := false
	var delay := 0.0
	for e in list.slice(0, MAX_FIGS):
		var k := str(e.key)
		var f: Dictionary = figs.get(k, {})
		if not f.is_empty() and not bool(f.gone) and (str(f.hero) != str(e.hero) or str(f.skin) != str(e.get("skin", "")) or bool(f.unknown) != bool(e.get("unknown", false))):
			_remove_fig(k, true)                      # (a different hero or outfit: built again)
			f = {}
		if f.is_empty() or bool(f.gone):
			_add_fig(e, delay)
			delay += 0.12
			if not _first and not bool(e.get("me", false)):
				joined = true
		else:
			f["name"] = str(e.name)
			(f.plate_name as Label).text = str(e.name)        # (now with their title and clan tag)
	# me in the middle: my key first, then the others in the order they came
	var mine := _order.filter(func(k): return bool(figs[k].me) and not bool(figs[k].gone))
	var rest := _order.filter(func(k): return not bool(figs[k].me) and not bool(figs[k].gone))
	var live: Array = mine + rest
	var slots := _slots(live.size())
	for i in live.size():
		figs[live[i]]["at"] = slots[i]
	_fit()
	_size_plates()
	if joined:
		_sfx("flip")

func _add_fig(e: Dictionary, delay: float) -> void:
	var k := str(e.key)
	if figs.has(k):
		_free_fig(k)
	var hero := str(e.get("hero", ""))
	var unknown := bool(e.get("unknown", false)) or hero == ""
	var skin := str(e.get("skin", ""))
	if skin != "" and not (Eco.SKINS.has(skin) and str(Eco.SKINS[skin].hero) == hero):
		skin = ""
	var holder := Node3D.new()
	world.add_child(holder)
	var shadow := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.62
	sm.bottom_radius = 0.62
	sm.height = 0.01
	sm.radial_segments = 32
	shadow.mesh = sm
	var shm := StandardMaterial3D.new()
	shm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shm.albedo_color = Color(1.0, 0.82, 0.3, 0.55) if bool(e.get("me", false)) else Color(0.0, 0.0, 0.0, 0.45)
	shadow.material_override = shm
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(shadow)
	var body: Node3D = null
	var player: AnimationPlayer = null
	var look := look_of(hero if not unknown else "knight")
	var made: Dictionary = View.make_body(look, {"skin":skin} if skin != "" else {})
	if not made.is_empty():
		body = made.body
		player = made.player
		holder.add_child(body)
		body.scale = Vector3.ONE * View.BODY_SCALE * float(Moba.HERO_SCALE.get(hero, 1.0))
		if unknown:
			_shadow_body(body)                        # (an older server: who they'll be isn't known -- a shadow)

	var f := {"key":k, "name":str(e.name), "hero":hero, "skin":skin, "me":bool(e.get("me", false)), "unknown":unknown,
		"holder":holder, "body":body, "player":player, "shadow":shadow, "look":look, "at":Vector3.ZERO,
		"t0":_spin + delay, "landed":false, "gone":false}
	holder.visible = false
	shadow.visible = false
	_make_plate(f)
	figs[k] = f
	_order.append(k)

func _shadow_body(body: Node3D) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.07, 0.05, 0.12)
	m.roughness = 1.0
	m.emission_enabled = true
	m.emission = Color(0.25, 0.18, 0.45)
	m.emission_energy_multiplier = 0.25
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = m

func _make_plate(f: Dictionary) -> void:
	var me := bool(f.me)
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.1, 0.03, 0.82) if me else Color(0.05, 0.04, 0.09, 0.78)
	sb.border_color = Color(GOLD, 0.95) if me else Color(1, 1, 1, 0.22)
	sb.set_border_width_all(2 if me else 1)
	sb.set_corner_radius_all(9)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 2
	sb.content_margin_bottom = 3
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(v)
	var nm := UI2.body(v, str(f.name), 13, Color("#fff4d6") if me else Color("#e8ecfb"), false)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var sub := ""
	var sub_col := Color("#b9c2dd")
	if bool(f.unknown):
		sub = "joining..."
	elif str(f.skin) != "":
		sub = str(Eco.SKINS[str(f.skin)].name)         # the outfit ("Frost Knight")
		sub_col = Color("#ffcf6a")
	else:
		sub = str((Moba.HEROES.get(str(f.hero), {}) as Dictionary).get("name", str(f.hero).capitalize()))
	var sl := UI2.body(v, sub, 10, sub_col, false)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.clip_text = true
	sl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if me:
		var you := UI2.chip(v, "YOU", GOLD, Color("#3a1c02"))
		you.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pc.modulate.a = 0.0
	plates_layer.add_child(pc)
	f["plate"] = pc
	f["plate_name"] = nm
	f["plate_sub"] = sl

func _remove_fig(k: String, now := false) -> void:
	var f: Dictionary = figs[k]
	f.gone = true
	f["t_gone"] = _spin
	if now:
		_free_fig(k)

func _free_fig(k: String) -> void:
	var f: Dictionary = figs.get(k, {})
	if f.is_empty():
		return
	for n in [f.holder, f.shadow, f.plate]:
		if is_instance_valid(n):
			(n as Node).queue_free()
	figs.erase(k)
	_order.erase(k)

func _land(f: Dictionary) -> void:
	# where a hero lands: a ring of gold racing out over the stones and a column of light fading up
	f.landed = true
	joined_n += 1
	var at: Vector3 = f.at
	var ring_mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.82
	tm.outer_radius = 1.0
	tm.rings = 40
	tm.ring_segments = 4
	ring_mi.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rm.albedo_color = Color(1.0, 0.78, 0.3, 0.9)
	ring_mi.material_override = rm
	ring_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring_mi.position = at + Vector3(0, 0.03, 0)
	ring_mi.scale = Vector3(0.3, 0.05, 0.3)
	world.add_child(ring_mi)
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.04
	cm.bottom_radius = 0.28
	cm.height = 7.0
	cm.radial_segments = 16
	cm.cap_top = false
	cm.cap_bottom = false
	beam.mesh = cm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.albedo_color = Color(1.0, 0.85, 0.45, 0.32)
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position = at + Vector3(0, 3.5, -0.45)            # (behind him: a streak of light, not a wash over him)
	world.add_child(beam)
	var tw := ring_mi.create_tween().set_parallel()
	tw.tween_property(ring_mi, "scale", Vector3(2.4, 0.05, 2.4), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(rm, "albedo_color:a", 0.0, 0.55)
	tw.chain().tween_callback(ring_mi.queue_free)
	var tb := beam.create_tween().set_parallel()
	tb.tween_property(bm, "albedo_color:a", 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tb.tween_property(beam, "scale", Vector3(0.2, 1.0, 0.2), 0.45)
	tb.chain().tween_callback(beam.queue_free)

func _leap(f: Dictionary) -> void:
	# his leap in from its top, the landing crouch and up, then his idle
	var p: AnimationPlayer = f.player
	if p == null or not is_instance_valid(p):
		return
	var idle := str((View.LOOKS.get(str(f.look), View.LOOKS.knight) as Dictionary).idle)
	if not p.has_animation(idle):
		idle = "g/Idle_A"
	if p.has_animation("g/Spawn_Air"):
		p.play("g/Spawn_Air", 0.0)
		p.seek(LEAP_FROM, true)
		p.queue(idle)
	elif p.has_animation(idle):
		p.play(idle)

func _step_figs(delta: float) -> void:
	for k in _order.duplicate():
		var f: Dictionary = figs[k]
		var holder: Node3D = f.holder
		var shadow: MeshInstance3D = f.shadow
		var at: Vector3 = f.at
		var age := _spin - float(f.t0)
		if bool(f.gone):
			var gt := _spin - float(f.get("t_gone", _spin))
			var s := clampf(1.0 - gt / 0.25, 0.0, 1.0)
			holder.scale = Vector3.ONE * maxf(s, 0.001)
			shadow.scale = Vector3.ONE * maxf(s, 0.001)
			(f.plate as Control).modulate.a = s
			if s <= 0.0:
				_free_fig(k)
			continue
		if age < 0.0:
			continue
		if not holder.visible:
			holder.visible = true
			shadow.visible = true
			_leap(f)
		# down out of the sky onto its place; landed, it slides over when the line-up changes
		var fall := clampf(age / DROP_T, 0.0, 1.0)
		if not bool(f.landed):
			holder.position = at + Vector3(0.0, DROP_H * (1.0 - fall * fall), 0.0)
			if fall >= 1.0:
				_land(f)
		else:
			holder.position = holder.position.lerp(at, 1.0 - exp(-delta * 8.0))
		shadow.position = Vector3(holder.position.x, at.y + 0.02, holder.position.z)
		var sc := clampf(0.35 + 0.65 * fall, 0.0, 1.0)
		shadow.scale = Vector3(sc, 1.0, sc)
		# a slow sway toward the camera
		holder.rotation.y = sin(_spin * 0.5 + float(hash(k) % 100) * 0.1) * 0.18
		(f.plate as Control).modulate.a = clampf((age - DROP_T) / 0.25, 0.0, 1.0)

func _size_plates() -> void:
	# each name plate as wide as its words, at most a row's share of the screen
	var n := 0
	for k in _order:
		n += 0 if bool(figs[k].gone) else 1
	var max_w := clampf(size.x * SPACING / maxf(_vis_w, 0.1) - 6.0, 68.0, 170.0) - 14.0   # (a hero's share of the width)
	for k in _order:
		var f: Dictionary = figs[k]
		for key in ["plate_name", "plate_sub"]:
			var l: Label = f[key]
			var font: Font = l.get_theme_font("font")
			var tw := font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x + 2.0
			l.custom_minimum_size.x = minf(tw, max_w)
		var pc: PanelContainer = f.plate
		pc.size = pc.get_combined_minimum_size()

func _place_plates() -> void:
	if not is_instance_valid(cam) or not cam.is_inside_tree():
		return
	var vs := Vector2(viewport.size)
	if vs.x <= 0.0:
		return
	var scale_v := stage_tex.size / vs
	for k in _order:
		var f: Dictionary = figs[k]
		var pc: PanelContainer = f.plate
		var back := float((f.at as Vector3).z) < BACK_Z * 0.5
		# under the feet (the second row: over the head)
		var anchor_p: Vector3 = (f.holder as Node3D).position + (Vector3(0, 2.75, 0) if back else Vector3(0, -0.05, 0))
		if bool(f.landed):
			anchor_p = (f.at as Vector3) + (Vector3(0, 2.75, 0) if back else Vector3(0, -0.05, 0))
		if cam.is_position_behind(anchor_p):
			continue
		var sp := cam.unproject_position(anchor_p) * scale_v + stage_tex.position
		pc.position = Vector2(sp.x - pc.size.x * 0.5, maxf(4.0, sp.y - (pc.size.y if back else -2.0))).round()   # (on the screen)

# ---------------- the words ----------------
func _build_top() -> void:
	# the title over the sky (0.31.216, landscape: in the top-left corner; across the top in portrait)
	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	top.offset_top = 6
	top.offset_left = 14
	top.alignment = BoxContainer.ALIGNMENT_BEGIN
	top.add_theme_constant_override("separation", -4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	var lw := SIDE_W
	var logo := TitleLogo.new()
	logo.custom_minimum_size = Vector2(lw, lw * TitleLogo.aspect())
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top.add_child(logo)
	UI2.center(UI2.text(top, "5 VS 5", 15, Color("#ffe9c4"), Color("#2a1206"), 5))

func _build_status() -> void:
	# the countdown and who's coming: 0.31.216 (landscape) a column on the left beside the plaza's heroes -- the ring over
	# the words; what's going on and LEAVE in the bottom-right corner (under the plaza's ring, one column, in portrait)
	status_box = VBoxContainer.new()
	status_box.anchor_top = 0.5
	status_box.anchor_bottom = 0.5
	status_box.offset_left = 14
	status_box.offset_right = 14 + SIDE_W
	status_box.offset_top = -44
	status_box.offset_bottom = 130
	status_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	status_box.add_theme_constant_override("separation", 6)
	status_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status_box)
	var row := VBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_box.add_child(row)
	ring = Control.new()
	ring.custom_minimum_size = Vector2(72, 72)
	ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ring)
	ring.draw.connect(_draw_ring)
	number = UI2.text(ring, "", 38, Color.WHITE, Color("#2a1604"), 8)
	number.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.resized.connect(func(): number.pivot_offset = number.size * 0.5)
	var words := VBoxContainer.new()
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 2)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)
	title = UI2.text(words, "FINDING A BATTLE", 20, Color.WHITE, Color("#2a1206"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.x = SIDE_W
	var cr := HBoxContainer.new()
	cr.alignment = BoxContainer.ALIGNMENT_CENTER
	cr.add_theme_constant_override("separation", 7)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(cr)
	count_row = cr
	var dot := Panel.new()
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color("#5fdc86")
	ds.set_corner_radius_all(5)
	ds.shadow_color = Color(0.37, 0.86, 0.53, 0.7)
	ds.shadow_size = 4
	dot.add_theme_stylebox_override("panel", ds)
	dot.custom_minimum_size = Vector2(9, 9)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cr.add_child(dot)
	count_lbl = UI2.text(cr, "5 vs 5", 17, Color("#8cf0a8"), Color("#0b2a14"))
	var foot := VBoxContainer.new()
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	foot.offset_left = -14 - SIDE_W
	foot.offset_right = -14
	foot.offset_top = -150
	foot.offset_bottom = -10
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", 6)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(foot)
	mode_lbl = UI2.center(UI2.body(foot, "Connecting to the server...", 13, Color("#fff4d6")))
	sub_lbl = UI2.center(UI2.body(foot, "bots fill the empty slots", 11, Color("#b9c2dd")))
	var lc := CenterContainer.new()
	lc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(lc)
	leave_btn = UI2.button(lc, "LEAVE", "grey", func():
		_sfx("menuClose")
		leave.emit(), "lobby_leave", 17, 44.0)
	leave_btn.custom_minimum_size.x = 170

func _sfx(cue: String) -> void:
	if audio != null and audio.has_method("play"):
		audio.play(cue)

# ---------------- server messages ----------------
func update(msg: Dictionary) -> void:
	# A "lobby" message: {left, wait, names, me, online, in_match, slots, running, tt, ct, hr, sk}
	if state == "loading" or state == "failed":
		return
	if not _built:
		_pending = msg
		return
	state = "lobby"
	wait = maxf(1.0, float(msg.get("wait", wait)))
	var l := float(msg.get("left", 0.0))
	if left < 0.0 or absf(l - left) > 0.35:        # (between messages the clock runs here; resync on drift)
		left = l
	title.text = "BATTLE STARTS IN"
	var slots := int(msg.get("slots", 10))
	var online := int(msg.get("online", 1))
	count_lbl.text = "%d / %d PLAYERS" % [mini(online, slots), slots]
	if bool(msg.get("running", false)):
		var n := int(msg.get("in_match", 0))
		mode_lbl.text = "A battle is on -- %d player%s fighting. You join it at zero." % [n, "" if n == 1 else "s"]
	else:
		mode_lbl.text = "A new 5 vs 5 battle starts at zero"
	sub_lbl.text = note_text if note_text != "" else "bots fill the empty slots"
	var names: Array = (msg.get("names", []) as Array).duplicate()
	var tt: Array = msg.get("tt", []) if msg.get("tt", []) is Array else []
	var ct: Array = msg.get("ct", []) if msg.get("ct", []) is Array else []
	var hr: Array = msg.get("hr", []) if msg.get("hr", []) is Array else []
	var sk: Array = msg.get("sk", []) if msg.get("sk", []) is Array else []
	var me := int(msg.get("me", -1))
	var seen := {}
	var list := []
	for i in names.size():
		var raw := str(names[i])
		seen[raw] = int(seen.get(raw, 0)) + 1
		var shown := raw
		if i < tt.size() and str(tt[i]) != "":
			shown = Net.title_text(raw, str(tt[i]))          # (with their titles, punctuated)
		if i < ct.size() and str(ct[i]) != "":
			shown = "[%s] %s" % [str(ct[i]), shown]          # their clan's tag
		var is_me := i == me
		var hero := str(hr[i]) if i < hr.size() else ""
		var skin := str(sk[i]) if i < sk.size() else ""
		if is_me:
			hero = my_hero if my_hero != "" else hero        # (mine I know: the server may be older)
			skin = my_skin if my_hero != "" else skin
		elif hero != "" and not Moba.HEROES.has(hero):
			hero = ""
		var key := "me" if is_me else "%s#%d" % [raw, seen[raw]]
		list.append({"key":key, "name":shown, "hero":hero, "skin":skin, "me":is_me, "unknown":hero == ""})
	if me < 0 and my_hero != "":
		list.push_front({"key":"me", "name":my_name if my_name != "" else "You", "hero":my_hero, "skin":my_skin, "me":true})
	_set_lineup(list)
	_first = false

func note(t: String) -> void:
	note_text = t
	if sub_lbl != null:
		sub_lbl.text = t

func fail(why: String) -> void:
	state = "failed"
	_fail_why = why
	if _built:
		_apply_fail()

func _apply_fail() -> void:
	title.text = "CAN'T JOIN"
	title.add_theme_color_override("font_color", Color("#ff6b5e"))
	number.text = ""
	mode_lbl.text = _fail_why
	sub_lbl.text = "Back to the menu..."
	ring.queue_redraw()

func loading() -> void:
	# the battle's being built behind this (siege_mode's loading card): no countdown, no LEAVE
	state = "loading"
	z_index = 100
	if _built:
		_apply_loading()

func _apply_loading() -> void:
	number.text = ""                               # (the ring spins)
	count_row.visible = false
	leave_btn.visible = false
	leave_btn.disabled = true
	title.text = "PREPARING THE BATTLEFIELD"
	title.add_theme_font_size_override("font_size", 18)
	mode_lbl.visible = false
	sub_lbl.visible = false

# ---------------- clock ----------------
func _process(delta: float) -> void:
	_spin += delta
	if not _built:
		return
	if state == "lobby":
		left = maxf(0.0, left - delta)
		var sec := int(ceil(left))
		if sec != _last_sec:
			number.text = str(sec)
			if _last_sec >= 0 and sec < _last_sec:
				# each second lands with a little punch; the last five tick (and go orange)
				number.scale = Vector2(1.22, 1.22) if sec <= 5 else Vector2(1.1, 1.1)
				number.create_tween().tween_property(number, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				if sec <= 5 and sec >= 1:
					_sfx("countdown")
			number.add_theme_color_override("font_color", Color("#ffd2a8") if sec <= 5 else Color.WHITE)
			_last_sec = sec
		if left <= 0.0:
			title.text = "STARTING"
	_step_figs(delta)
	_cam_d = lerpf(_cam_d, _cam_want, 1.0 - exp(-delta * 3.0))
	_cam_z = lerpf(_cam_z, _cam_z_want, 1.0 - exp(-delta * 3.0))
	_cam_lift = lerpf(_cam_lift, _cam_lift_want, 1.0 - exp(-delta * 3.0))
	_place_cam()
	_place_plates()
	if ring.visible:
		ring.queue_redraw()

func _draw_ring() -> void:
	var c := ring.size * 0.5
	var r := minf(c.x, c.y) - 5.0
	ring.draw_circle(c, r + 4.0, Color(0.03, 0.02, 0.06, 0.62))
	ring.draw_arc(c, r, 0.0, TAU, 64, Color(1, 1, 1, 0.14), 6.0, true)
	if state == "connecting" or state == "loading":
		var a := _spin * 4.0
		ring.draw_arc(c, r, a, a + 1.6, 24, GOLD, 6.0, true)
	elif state == "lobby":
		var f := clampf(left / wait, 0.0, 1.0)
		var col := HOT if left <= 5.0 else GOLD
		if f > 0.0:
			ring.draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * f, maxi(8, int(64 * f)), col, 6.0, true)
	elif state == "failed":
		ring.draw_arc(c, r, 0.0, TAU, 64, Color("#ff6b5e"), 6.0, true)
