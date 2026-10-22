extends Control
# 0.31.198 THE HERALD'S WELCOME (Kevin, with the server wiped so everyone starts fresh: "Have the game ask their name and
# after they do that it'll briefly say what game is and then ask if they would like to play tutorial. Make the tutorial
# guy pop up while doing this and voice it. Do the same type of messages and model like he is in tutorial. Make it very
# funny"; and "Also have him briefly take player through menus").
# On Home, for a player with no name yet (the profile's "Player": a new install, or anyone after the wipe), the Royal
# Herald pops up with his proclamation scroll exactly as in the tutorial (scripts/siege/tutorial.gd: his eight poses,
# each line typed out on the parchment as he says it, TAP TO CONTINUE): he asks the player's name (a field over the
# scroll; a few names get a word from him, unvoiced), announces it, says what Fatebound is, walks them round Home
# (PLAY, the chests, SHOP, PASS, ARMORY (0.31.204: was LOCKER), ALLIANCE, the menu: the shade lifts off each in turn, ringed and labelled, the
# scroll at the top of the screen while what he shows is below), then offers the tutorial -- SHOW ME HOW
# (siege_app.start_tutorial) or I'LL WING IT (Home). VOICE: assets/vo/tutorial/intro_*.ogg and tour_*.ogg, his voice
# (ElevenLabs; art_sources/tutorial/intro_script.json, tools/build_tutorial_assets.py). The captions are that script's
# lines without their spoken [directions] (tests/herald_intro_test.gd checks).
const Tut = preload("res://scripts/siege/tutorial.gd")
const VisualTheme = preload("res://scripts/ui/visual_theme.gd")
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const VO_DIR := "res://assets/vo/tutorial/"
const NAME_MAX := 16
const DEFAULT_NAME := "Player"                # (Profile.defaults: no name chosen yet)
const GOLD := Color("#ffd257")                # (frames and rings only: no yellow text -- 0.31.195)
const INK := Color("#2a1604")

# [voice id, caption, pose]; the flow: hello -> (the name) -> named -> what -> the tour -> ask -> (the choice) -> yes / no
const LINES := {
	"hello": ["intro_hello", "Oh! Hello. Didn't see you there. I'm the Royal Herald. I announce people. Which is awkward, because I have no idea who you are. What's your name? And do pick something I can say out loud. In public. Near children.", "peeking"],
	"named": ["intro_named", "Hear ye, hear ye! Presenting... that. Lovely. I've written it on the royal scroll. In permanent ink. I've regretted that before.", "hold"],
	"what": ["intro_what", "Right. This is Fatebound. Five heroes versus five. Three lanes. Two castles. Each with a King sitting on a very comfortable chair. Knock their King off his chair, keep ours on his, and try not to die in ways I'll have to announce.", "lying"],
	"tour_play": ["tour_play", "First, the big button. PLAY. It throws you straight into a battle. It is the most important button in the kingdom. Please don't sit on it.", "pointing"],
	"tour_chests": ["tour_chests", "Win, and you'll earn chests. They wait down here, unlocking slower than a royal tax refund. Then, gold, gems, and the odd hero shard.", "leaning"],
	"tour_shop": ["tour_shop", "The Shop. Heroes, outfits, gems. Everything a growing hero needs, and several things he doesn't.", "hold"],
	"tour_pass": ["tour_pass", "The Pass. Play matches, climb its tiers, collect prizes. It's a ladder. Made of presents.", "sitting"],
	"tour_locker": ["tour_locker", "Your Armory. Your heroes, their outfits, your titles. Dress to impress. Or at least to intimidate.", "peeking"],
	"tour_alliance": ["tour_alliance", "Alliance. Friends, parties, and your clan. Five of you on one side. The enemy hates it. I adore it.", "hanging"],
	"tour_menu": ["tour_menu", "And up here, the menu. Daily orders, quests, the rankings, and my lessons. Do read the orders. They pay. I don't.", "lying"],
	"ask": ["intro_ask", "Now. I could teach you the basics. It's quick, it's mostly painless, and there's gold at the end. Or you can skip it and learn by losing. Loudly. In front of everyone. Your call.", "pointing"],
	"yes": ["intro_yes", "Excellent. A recruit with sense. That's a first. Follow me, and mind the King's chair. He's very particular about it.", "hold"],
	"no": ["intro_no", "Bold. Foolish, but bold. If you change your mind, the lessons are in the menu. I'll be right here. Napping. Heroically.", "napping"],
}
const NEXT := {"named": "what", "what": "tour_play", "tour_play": "tour_chests", "tour_chests": "tour_shop",
	"tour_shop": "tour_pass", "tour_pass": "tour_locker", "tour_locker": "tour_alliance", "tour_alliance": "tour_menu",
	"tour_menu": "ask"}
# the tour: what each line shows (a button's action_key, or "@<meta>" for every node carrying that meta), its label, and
# (if not the side away from the screen's edge) where the arrow and label go
const TOUR := {
	"tour_play": ["play", "PLAY"],
	"tour_chests": ["@chest_plate", "CHESTS", "below"],          # (above them is PLAY)
	"tour_shop": ["tab_shop", "SHOP"],
	"tour_pass": ["tab_pass", "PASS"],
	"tour_locker": ["tab_locker", "ARMORY"],         # (0.31.204: the Locker renamed, his line voiced again)
	"tour_alliance": ["tab_alliance", "ALLIANCE"],
	"tour_menu": ["home_menu", "MENU"],
}
# a word from him for some names (written, not voiced: the name field stays up)
const NAME_QUIPS := {
	"": "The quill refuses to write nothing. It has tried before. Nobody noticed.",
	"player": "'Player'? That's what I call people I've forgotten. Try again.",
	"herald": "There's room for one Herald in this kingdom. It's me. Pick another.",
	"royal herald": "Flattering. Still me, though. Pick another.",
	"king": "The King is busy sitting on his chair. You can be someone else.",
	"admin": "Nice try. The royal records have seen that trick. Twice today.",
}
# the shade, with a hole where the tour is looking (soft-edged, rounded)
const SHADE_CODE := """
shader_type canvas_item;
uniform vec2 size = vec2(1.0, 1.0);
uniform vec4 hole = vec4(0.0);                 // x, y, w, h in px (w 0: none)
uniform float radius = 18.0;
uniform float soft = 8.0;
uniform vec4 shade : source_color = vec4(0.0, 0.01, 0.04, 0.6);
void fragment() {
	vec2 p = UV * size;
	float a = shade.a;
	if (hole.z > 0.5) {
		vec2 h = hole.zw * 0.5;
		float r = min(radius, min(h.x, h.y));
		vec2 q = abs(p - (hole.xy + h)) - (h - vec2(r));
		float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
		a *= smoothstep(-1.0, soft, d);
	}
	COLOR = vec4(shade.rgb, a);
}
"""

var app
var step := ""
var shown := 0.0
var pose := ""
var lines_said: Array = []                  # (tests) every line id shown, in order
var quip := ""                              # a written word about the name (no voice), shown instead of the line
var _time := 0.0
var _pose_tex := {}
var voice: AudioStreamPlayer
var dim: ColorRect
var marker: Control
var scroll: TextureRect
var text_label: Label
var hint_label: Label
var name_box: Control
var name_edit: LineEdit
var choice_box: Control
var banner: Label
var _kb := 0.0
var hole_want := Rect2()                    # where the tour is looking (this control's px; empty: nowhere)
var hole_now := Rect2()                     # ...and the shade's hole on its way there
var at_top := false                         # the scroll at the top of the screen (what he shows is below)
var _y_off := 0.0                           # the scroll's way to its place, eased off
var _y_last := NAN

func open(a) -> void:
	app = a
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	voice = AudioStreamPlayer.new()
	voice.bus = "Master"
	add_child(voice)
	dim = ColorRect.new()
	var sh := Shader.new()
	sh.code = SHADE_CODE
	var sm := ShaderMaterial.new()
	sm.shader = sh
	dim.material = sm
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent):
		if (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
			accept_event()
			next())
	add_child(dim)
	marker = Marker.new()
	marker.intro = self
	marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(marker)
	scroll = TextureRect.new()
	scroll.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scroll.stretch_mode = TextureRect.STRETCH_SCALE
	scroll.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scroll)
	text_label = Label.new()
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.add_theme_font_override("font", VisualTheme.BOLD_FONT)
	text_label.add_theme_font_size_override("font_size", 16)
	text_label.add_theme_color_override("font_color", Tut.INK_TEXT)
	text_label.add_theme_constant_override("line_spacing", Tut.LINE_GAP)
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(text_label)
	hint_label = Label.new()
	hint_label.text = "TAP TO CONTINUE  >"
	hint_label.add_theme_font_override("font", VisualTheme.BOLD_FONT)
	hint_label.add_theme_font_size_override("font_size", 12)
	hint_label.add_theme_color_override("font_color", Color.WHITE)
	hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hint_label.add_theme_constant_override("outline_size", 4)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint_label)
	# the name, announced: big over the scroll
	banner = Label.new()
	banner.add_theme_font_override("font", UI2.LG)
	banner.add_theme_font_size_override("font_size", 34)
	banner.add_theme_color_override("font_color", Color.WHITE)
	banner.add_theme_color_override("font_outline_color", Color("#5a3208"))
	banner.add_theme_constant_override("outline_size", 12)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.visible = false
	add_child(banner)
	_build_name_box()
	_build_choice_box()
	# he pops up: the scroll rises into place
	scroll.modulate.a = 0.0
	text_label.modulate.a = 0.0
	_say("hello")
	_y_off = 300.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(scroll, "modulate:a", 1.0, 0.25)
	tw.tween_property(text_label, "modulate:a", 1.0, 0.25)
	if app != null:
		app.sfx("menuOpen")

func _build_name_box() -> void:
	name_box = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#fff4dc")
	sb.border_color = Color("#6b4420")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 10
	name_box.add_theme_stylebox_override("panel", sb)
	name_box.visible = false
	add_child(name_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	name_box.add_child(v)
	var t := Label.new()
	t.text = "WHAT SHALL THE HERALD CALL YOU?"
	t.add_theme_font_override("font", UI2.LG)
	t.add_theme_font_size_override("font_size", 15)
	t.add_theme_color_override("font_color", Color("#7a3c14"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 8)
	v.add_child(r)
	name_edit = LineEdit.new()
	name_edit.max_length = NAME_MAX
	name_edit.placeholder_text = "Your name"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.custom_minimum_size = Vector2(0, 46)
	name_edit.add_theme_font_override("font", UI.HEAVY_FONT)
	name_edit.add_theme_font_size_override("font_size", 18)
	name_edit.add_theme_color_override("font_color", Color("#3e2610"))
	name_edit.add_theme_color_override("font_placeholder_color", Color(0.24, 0.15, 0.06, 0.45))
	name_edit.add_theme_color_override("caret_color", Color("#3e2610"))
	var es := StyleBoxFlat.new()
	es.bg_color = Color("#ffffff")
	es.border_color = Color("#a8763c")
	es.set_border_width_all(2)
	es.set_corner_radius_all(10)
	es.content_margin_left = 12
	es.content_margin_right = 12
	name_edit.add_theme_stylebox_override("normal", es)
	name_edit.add_theme_stylebox_override("focus", es)
	name_edit.text_submitted.connect(func(_t): submit_name(name_edit.text))
	r.add_child(name_edit)
	var ok := UI2.button(r, "THAT'S ME", "green", func(): submit_name(name_edit.text), "intro_name_ok", 15, 46.0, 12.0)
	ok.custom_minimum_size.x = 112

func _build_choice_box() -> void:
	choice_box = VBoxContainer.new()
	(choice_box as VBoxContainer).add_theme_constant_override("separation", 10)
	choice_box.visible = false
	add_child(choice_box)
	UI2.button(choice_box, "SHOW ME HOW", "green", func(): choose(true), "intro_tutorial_yes", 20, 58.0, 16.0)
	UI2.button(choice_box, "I'LL WING IT", "blue", func(): choose(false), "intro_tutorial_no", 16, 46.0, 14.0)

# ---------------- the lines ----------------
static func line_of(id: String) -> Array:
	return LINES.get(id, ["", "", "hold"])

func _say(id: String) -> void:
	step = id
	quip = ""
	shown = 0.0
	var l := line_of(id)
	lines_said.append(str(l[0]))
	_set_pose(str(l[2]))
	text_label.text = str(l[1])
	_play(str(l[0]))
	name_box.visible = false
	choice_box.visible = false
	banner.visible = id == "named"
	if id == "named":
		banner.text = "★ %s ★" % str(app.profile.d.name if app != null else "").to_upper()
		banner.pivot_offset = Vector2(banner.size.x * 0.5, 20.0)
		banner.scale = Vector2(0.4, 0.4)
		create_tween().tween_property(banner, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if app != null:
			app.sfx("confirm")
	elif TOUR.has(id) and app != null:
		app.sfx("tap")
	_aim()
	_layout()

func _play(id: String) -> void:
	voice.stop()
	if app == null or app.audio == null:
		return
	var master := float(app.audio.levels.get("master", 1.0))
	var muted := bool(app.audio.get("muted"))
	var p := VO_DIR + id + ".ogg"
	if id != "" and not muted and master > 0.0 and ResourceLoader.exists(p):
		voice.stream = load(p)
		voice.volume_db = linear_to_db(master * Tut.VOICE_GAIN)
		voice.play()

func _set_pose(p: String) -> void:
	if p == pose:
		return
	pose = p
	if not _pose_tex.has(p):
		var path := Tut.POSE_PATH % p
		_pose_tex[p] = load(path) if ResourceLoader.exists(path) else null
	scroll.texture = _pose_tex[p]
	# he changes how he's holding it: the scroll pops a little
	var r: Dictionary = Tut.scroll_rects(p, size)
	scroll.pivot_offset = Vector2((r.art as Rect2).size.x * 0.5, (r.art as Rect2).size.y)
	scroll.scale = Vector2(0.94, 0.94)
	var tw := create_tween()
	tw.tween_property(scroll, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func typed() -> bool:
	return shown >= float(text_label.text.length())

func next() -> void:
	# a tap: the line typed out first; then on (the name and the choice wait for their own buttons)
	if not typed():
		shown = 9999.0
		return
	match step:
		"hello":
			_ask_name()
		"ask":
			choice_box.visible = true
		"yes", "no":
			_done()
		_:
			if NEXT.has(step):
				_say(str(NEXT[step]))

func _ask_name() -> void:
	name_box.visible = true
	_layout()
	name_edit.grab_focus()
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_show(name_edit.text)

static func name_quip(n: String) -> String:
	# what he says to a name he won't write ("" for a name he will)
	var k := n.strip_edges().to_lower()
	if NAME_QUIPS.has(k):
		return str(NAME_QUIPS[k])
	return ""

func submit_name(raw: String) -> void:
	if step != "hello":
		return
	var n := Profile.clean_name(raw).left(NAME_MAX)
	var q := name_quip(n)
	if q != "":
		quip = q
		text_label.text = q
		shown = 0.0
		_set_pose("leaning")
		voice.stop()
		if app != null:
			app.sfx("error")
		_layout()
		return
	if app != null:
		app.profile.set_name(n)                     # (an op: the server has it too)
		app.refresh_top()
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_hide()
	name_edit.release_focus()
	_say("named")

func choose(tutorial: bool) -> void:
	if step != "ask":
		return
	if app != null:
		app.sfx("confirm" if tutorial else "tap")
	_say("yes" if tutorial else "no")

func _done() -> void:
	voice.stop()
	var tutorial := step == "yes"
	if app == null:
		queue_free()
		return
	app.close_modal()
	if tutorial:
		app.start_tutorial()
	else:
		app.toast("The tutorial waits in the menu at the top, whenever you want it", UI.CYAN)
		app.offer_daily.call_deferred()

# ---------------- the tour ----------------
func target_rect(key: String) -> Rect2:
	# what the tour shows, in this control's px: the button with that action_key on the screen (or, "@meta", every node
	# carrying that meta, together); empty if it isn't there
	if app == null:
		return Rect2()
	var found: Array = []
	_find(app, key, found)
	var out := Rect2()
	for n in found:
		var g: Rect2 = (n as Control).get_global_rect()
		out = g if out.has_area() == false else out.merge(g)
	if not out.has_area():
		return Rect2()
	out.position -= get_global_rect().position
	return out

func _find(n: Node, key: String, out: Array) -> void:
	if n == self:
		return
	if n is Control and (n as Control).is_visible_in_tree():
		var hit := false
		if key.begins_with("@"):
			hit = n.has_meta(key.substr(1))
		else:
			hit = str(n.get_meta("action_key", "")) == key
		if hit:
			out.append(n)
			if not key.begins_with("@"):
				return
	for c in n.get_children():
		_find(c, key, out)
		if not key.begins_with("@") and not out.is_empty():
			return

func tour_key() -> String:
	return str(TOUR[step][0]) if TOUR.has(step) else ""

func tour_label() -> String:
	return str(TOUR[step][1]) if TOUR.has(step) else ""

func tour_side() -> String:
	return str(TOUR[step][2]) if TOUR.has(step) and (TOUR[step] as Array).size() > 2 else ""

func _aim() -> void:
	# where the shade opens, and where the scroll goes (out of its way)
	var k := tour_key()
	var r := target_rect(k) if k != "" else Rect2()
	if r.has_area():
		r = r.grow(8.0)
		if not hole_now.has_area():
			hole_now = Rect2(r.get_center(), Vector2.ZERO)   # (it opens out of the middle of the thing)
		at_top = r.get_center().y > size.y * 0.42
	else:
		at_top = false
	hole_want = r

# ---------------- every frame ----------------
func _process(delta: float) -> void:
	_time += delta
	var full := text_label.text.length()
	if shown < 9000.0:
		shown = minf(shown + delta * Tut.TYPE_CPS, float(full))
	text_label.visible_characters = -1 if shown >= float(full) else int(shown)
	var waiting := name_box.visible or choice_box.visible
	hint_label.visible = not waiting
	hint_label.modulate.a = (0.55 + 0.45 * sin(_time * 5.0)) if typed() and not voice.playing else 0.35
	if step == "ask" and typed() and not choice_box.visible and not voice.playing:
		choice_box.visible = true                   # (the choice comes up once he's asked)
	var kh := float(DisplayServer.virtual_keyboard_get_height())
	var want := 0.0
	if kh > 0.0:
		want = kh * (get_viewport_rect().size.y / maxf(1.0, float(DisplayServer.window_get_size().y)))
	if absf(want - _kb) > 1.0:
		_kb = want
	# the shade's hole: on its way to what's shown (the layout may move under it), or shut
	if TOUR.has(step):
		_aim()
	var goal := hole_want
	if not goal.has_area() and hole_now.has_area():
		goal = Rect2(hole_now.get_center(), Vector2.ZERO)
	var e := 1.0 - exp(-delta * 10.0)
	hole_now = Rect2(hole_now.position.lerp(goal.position, e), hole_now.size.lerp(goal.size, e))
	if not hole_want.has_area() and hole_now.size.length() < 3.0:
		hole_now = Rect2()
	var m := dim.material as ShaderMaterial
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("hole", Vector4(hole_now.position.x, hole_now.position.y, hole_now.size.x, hole_now.size.y) if hole_now.has_area() else Vector4.ZERO)
	_y_off = move_toward(_y_off, 0.0, maxf(700.0, absf(_y_off) * 9.0) * delta)
	marker.queue_redraw()
	_layout()

func _layout() -> void:
	if scroll == null or size.x <= 0.0:
		return
	var r: Dictionary = Tut.scroll_rects(pose if pose != "" else "hold", size)
	var art: Rect2 = r.art
	var tr: Rect2 = r.text
	var top_y := 10.0 + float(app.safe_top if app != null else 0.0)
	var dy := (top_y - art.position.y) if at_top else 0.0
	var want_y := art.position.y + dy
	if not is_nan(_y_last) and absf(want_y - _y_last) > 0.5:
		_y_off += _y_last - want_y                  # (from where it was: it slides there)
	_y_last = want_y
	scroll.position = Vector2(art.position.x, want_y + _y_off)
	scroll.size = art.size
	text_label.position = tr.position + Vector2(0, dy + _y_off)
	text_label.size = tr.size
	text_label.add_theme_font_size_override("font_size", Tut.fit_px(text_label.text, tr.size))
	var foot := size.y - Tut.SCROLL_BOTTOM + 13.0
	if at_top:
		foot = minf(art.end.y + dy + 2.0, size.y - 30.0)
	hint_label.position = Vector2(size.x * 0.5, foot + _y_off)
	hint_label.size = Vector2(size.x * 0.5 - Tut.SCROLL_SIDE, 18)
	var top := art.position.y + dy
	var w := minf(size.x - 32.0, 420.0)
	banner.size = Vector2(size.x - 24.0, 46.0)
	banner.position = Vector2(12.0, top - 64.0 + _y_off)
	name_box.size = Vector2(w, 0)
	name_box.reset_size()
	var nb_h := name_box.size.y
	var ny := top - nb_h - 18.0
	if _kb > 0.0:
		ny = minf(ny, size.y - _kb - nb_h - 12.0)
	name_box.position = Vector2((size.x - w) * 0.5, maxf(12.0 + float(app.safe_top if app != null else 0.0), ny))
	choice_box.size = Vector2(w, 0)
	choice_box.reset_size()
	choice_box.position = Vector2((size.x - w) * 0.5, top - choice_box.size.y - 18.0)

# the ring round what the tour shows, an arrow at it and its name
class Marker extends Control:
	var intro
	var _ring: StyleBoxFlat
	var _ink: StyleBoxFlat

	func _ready() -> void:
		_ring = StyleBoxFlat.new()
		_ring.draw_center = false
		_ring.border_color = GOLD
		_ring.set_border_width_all(4)
		_ring.set_corner_radius_all(16)
		_ink = _ring.duplicate()
		_ink.border_color = INK
		_ink.set_border_width_all(9)
		_ink.set_corner_radius_all(19)

	func _draw() -> void:
		if intro == null or not intro.hole_want.has_area() or not intro.hole_now.has_area():
			return
		var pulse := 0.5 + 0.5 * sin(float(intro._time) * 5.0)
		var r: Rect2 = intro.hole_now.grow(2.0 + 4.0 * pulse)
		_ink.draw(get_canvas_item(), r.grow(2.5))
		_ring.draw(get_canvas_item(), r)
		if intro.hole_now.size.distance_to(intro.hole_want.size) > 12.0:
			return                                  # (the arrow and name once it's there)
		var down: bool = r.get_center().y > size.y * 0.5     # (below the middle: the arrow comes from above)
		var side := str(intro.tour_side())
		if side != "":
			down = side == "above"
		var x := clampf(r.get_center().x, 40.0, size.x - 40.0)
		var tip := Vector2(x, r.position.y - 6.0 - 10.0 * pulse) if down else Vector2(x, r.end.y + 6.0 + 10.0 * pulse)
		_arrow(tip, 1.0, not down)
		_plate(tip + Vector2(0, -74.0 if down else 74.0), str(intro.tour_label()))

	func _arrow(tip: Vector2, s: float, up := false) -> void:
		# a fat outlined arrow pointing down at tip (or up) -- the tutorial's
		var k := -1.0 if up else 1.0
		var pts := PackedVector2Array([tip, tip + Vector2(-22, -26 * k) * s, tip + Vector2(-9, -26 * k) * s, tip + Vector2(-9, -52 * k) * s,
			tip + Vector2(9, -52 * k) * s, tip + Vector2(9, -26 * k) * s, tip + Vector2(22, -26 * k) * s])
		var c := Vector2.ZERO
		for q in pts:
			c += q
		c /= pts.size()
		var out := PackedVector2Array()
		for q in pts:
			out.append(c + (q - c) * 1.18)
		draw_colored_polygon(out, INK)
		draw_colored_polygon(pts, GOLD)

	func _plate(center: Vector2, text: String) -> void:
		var font: Font = UI2.LG
		var fs := 18
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 26.0
		var r := Rect2(clampf(center.x - w * 0.5, 6.0, size.x - 6.0 - w), center.y - 16, w, 32)
		draw_rect(r.grow(2), INK)
		draw_rect(r, Color(0.12, 0.09, 0.03, 0.95))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), GOLD)
		draw_string(font, Vector2(r.position.x + 13, r.position.y + 23), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
