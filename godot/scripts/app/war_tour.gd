extends Control
# 0.31.147 (Kevin: "Create a tutorial for everyone that walks them through how the map works and joining a clan. When
# they click join clan it put the list of available clans or they have option to start clan"): the Royal Herald's tour
# of the war map, over the war table (war_table.gd). It runs by itself the first time a player's map has the war on it
# (once a phone: settings.war_tour), and again from the map's "?" corner button.
# Each step: the Herald's line (typewriter; NEXT finishes it, then moves on; a tap on the dimmed screen does the same),
# a spotlight on the part of the window it's about (the map, the place's sheet, the strip over the map, QUICK BATTLE),
# and the map's camera taking you there (war_table.tour_camera: the whole land, or close on a place, picking it).
# The last step: not in a clan -- JOIN A CLAN (the CLAN window on its list of clans, with START MY OWN CLAN) or LATER;
# in a clan -- your house and tag, FINISH.
# VOICEOVER: every line has an id; drop res://assets/vo/war_tour/<id>.ogg in and it plays with the text (as the match
# tutorial's res://assets/vo/tutorial/). Missing files are skipped.
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const SocialUI = preload("res://scripts/app/social_ui.gd")
const Map = preload("res://scripts/meta/war_map.gd")
const VO_DIR := "res://assets/vo/war_tour/"
const TYPE_CPS := 52.0
const DIM := Color(0.0, 0.01, 0.04, 0.6)
const GLOW := Color("#ffd36b")

signal finished(how: String)           # "done" (FINISH / LATER), "skip", "join" (JOIN A CLAN)

var table                              # war_table.gd
var app
var steps: Array = []
var step := 0
var shown := 0.0
var _clock := 0.0
var _panel: PanelContainer
var _box: VBoxContainer
var _text: Label
var _count: Label
var _buttons: HBoxContainer
var _target := Rect2()                 # what the spotlight is on (this control's pixels); empty: nothing
var _hole := Rect2()                   # the spotlight as drawn (eases toward _target)
var _done := false
var voice: AudioStreamPlayer

static func make_steps(war: Dictionary, in_clan: bool, house: String, tag: String) -> Array:
	# the tour's steps, for this player and this week's map: [{id, text, target, cam: [], pick}]
	var home: String = Map.HOMES.get(house, "home_lions")
	var ex := example_place(war, house)
	var out := [
		{"id":"tour_intro", "target":"map", "cam":["overview"], "pick":"",
			"text":"Ah, the war table! Every land in the realm is on it, and three great houses want all of it: the Lions, the Stags and the Ravens."},
		{"id":"tour_homes", "target":"map", "cam":["focus", home, 2.3], "pick":"",
			"text":"Each house has a keep. Keeps can never be taken. People have tried. People have regretted it. Everything else is up for grabs."},
		{"id":"tour_land", "target":"sheet", "cam":["focus", ex, 1.9], "pick":ex,
			"text":"A land's colour shows which house holds it. Tap a land to see who holds it, and how close each clan is to taking it."},
		{"id":"tour_bars", "target":"sheet", "cam":["focus", ex, 1.9], "pick":ex,
			"text":"Clans fight for their house. Every crown your side wins in a battle adds %d points to your clan's bar. A lost battle takes %d away." % [Map.PTS_CROWN, Map.PTS_LOSS]},
		{"id":"tour_take", "target":"sheet", "cam":["focus", ex, 1.9], "pick":ex,
			"text":"The first clan to fill its bar takes the land for its house: %s points for land another house holds, %s for free land." % [_num(Map.NEED_OWNED), _num(Map.NEED_NEUTRAL)]},
		{"id":"tour_links", "target":"map", "cam":["overview"], "pick":"",
			"text":"You can only attack along the roads, from land your house already holds. A mountain ridge means no road. Plan accordingly."},
		{"id":"tour_attempts", "target":"stats", "cam":["overview"], "pick":"",
			"text":"You get %d battles a day that count for your clan, started or joined. After that you can still fight beside your clan to help. Defending is always free." % Map.ATTEMPTS},
		{"id":"tour_week", "target":"stats", "cam":["overview"], "pick":"",
			"text":"Every Monday the war ends. The house holding the most land wins the week, and the map is wiped clean for the next one."},
		{"id":"tour_quick", "target":"quick", "cam":["overview"], "pick":"",
			"text":"Just want a scrap? QUICK BATTLE throws you straight into a 16 vs 16 match. No clan needed. No paperwork either."},
	]
	if in_clan:
		out.append({"id":"tour_ready", "target":"none", "cam":["focus", home, 1.6], "pick":"", "end":"clan",
			"text":"You fight for House %s with [%s]. Go take some land. And do try to keep your own." % [str(Map.HOUSE_NAMES.get(house, "?")), tag]})
	else:
		out.append({"id":"tour_clan", "target":"none", "cam":["overview"], "pick":"", "end":"free",
			"text":"To fight for land, you need a clan. Every house has its own, free and open to all. Or join a players' clan, or start your own. The realm won't conquer itself!"})
	return out

static func example_place(war: Dictionary, house: String) -> String:
	# the place the tour shows: one another house holds next to your house's land (what you'd attack), else any held
	# one, else the Mill
	var terr: Dictionary = war.get("terr", {})
	var held := ""
	for id in Map.T:
		if Map.is_home(id):
			continue
		var h := str((terr.get(id, {}) as Dictionary).get("h", ""))
		if h == "":
			continue
		if held == "":
			held = id
		if house != "" and h != house and str((terr.get(id, {}) as Dictionary).get("why", "")) == "":
			return id
	return held if held != "" else "mill"

static func _num(n: int) -> String:
	var s := str(n)
	return s if s.length() <= 3 else s.left(s.length() - 3) + "," + s.right(3)

func begin(t, a) -> void:
	table = t
	app = a
	var soc = a.social
	var war: Dictionary = soc.war if soc != null else {}
	var house := str(war.get("house", ""))
	if house == "" and soc != null and soc.in_clan():
		house = str(soc.clan.get("house", ""))
	var in_clan: bool = soc != null and soc.in_clan()
	steps = make_steps(war, in_clan, house, soc.my_tag() if soc != null else "")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_dim_input)
	voice = AudioStreamPlayer.new()
	voice.bus = "Master"
	add_child(voice)
	_box = UI2.frame(self, "night", 12, 18.0, "gold")
	_panel = _box.get_parent() as PanelContainer
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS        # (a tap on the Herald's words is a tap on the screen: NEXT)
	_box.add_theme_constant_override("separation", 6)
	var head := UI.row(_box, 10)
	var horn := UI2.icon(head, "horn", 46.0)
	horn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(v)
	var nr := UI.row(v, 6)
	var nl := UI.label(nr, "THE ROYAL HERALD", 12, UI2.GOLD, UI.HEAVY_FONT)
	nl.autowrap_mode = TextServer.AUTOWRAP_OFF
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count = UI.label(nr, "", 11, UI2.MUTED, UI.HEAVY_FONT)
	_count.autowrap_mode = TextServer.AUTOWRAP_OFF
	_text = UI.label(v, "", 15, Color.WHITE, UI.BODY_FONT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(0, 62)
	_buttons = UI.row(_box, 8)
	_show()

func _on_dim_input(ev: InputEvent) -> void:
	# a tap on the dimmed screen: the same as NEXT (not on the last step: its buttons decide)
	var up: bool = (ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and not ev.pressed) \
		or (ev is InputEventScreenTouch and not ev.pressed)
	if up and not steps[step].has("end"):
		next()
	accept_event()

# ---------------- flow ----------------
func next() -> void:
	if _done:
		return
	var full := str(steps[step].text).length()
	if shown < float(full):
		shown = float(full)
		_text.visible_characters = -1
		return
	if step + 1 >= steps.size():
		_finish("done")
		return
	app.sfx("tap")
	step += 1
	_show()

func _finish(how: String) -> void:
	if _done:
		return
	_done = true
	voice.stop()
	finished.emit(how)

func _show() -> void:
	var st: Dictionary = steps[step]
	shown = 0.0
	_text.text = str(st.text)
	_text.visible_characters = 0
	_count.text = "%d / %d" % [step + 1, steps.size()]
	for c in _buttons.get_children():
		_buttons.remove_child(c)               # (out of the row now: freed later, it would still widen the panel)
		c.queue_free()
	var end := str(st.get("end", ""))
	if end == "free":
		var later := UI2.button(_buttons, "LATER", "ghost", func():
			app.sfx("menuClose")
			_finish("done"), "war_tour_later", 14, 44.0, 12.0)
		later.custom_minimum_size.x = 96
		var jb := UI2.button(_buttons, "JOIN A CLAN", "green", func():
			app.sfx("confirm")
			_finish("join"), "war_tour_join", 17, 44.0, 12.0, UI2.icon_path("castle"))
		UI.grow(jb)
	else:
		var sk := UI2.button(_buttons, "SKIP", "ghost", func():
			app.sfx("menuClose")
			_finish("skip"), "war_tour_skip", 13, 40.0, 12.0)
		sk.custom_minimum_size.x = 80
		sk.visible = end == ""
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_buttons.add_child(sp)
		var nb := UI2.button(_buttons, "FINISH ✔" if end == "clan" else "NEXT ▶", "gold", func(): next(), "war_tour_next", 16, 44.0, 12.0)
		nb.custom_minimum_size.x = 132
	# the map: where the camera goes and what's picked
	if table != null:
		table.tour_camera(st.get("cam", ["overview"]), str(st.get("pick", "")))
	_play_line(str(st.id))
	_place.call_deferred()

func _play_line(id: String) -> void:
	voice.stop()
	var au = app.audio if app != null else null
	var master := 1.0
	if au != null:
		if au.get("levels") is Dictionary:
			master = float((au.get("levels") as Dictionary).get("master", 1.0))
		if bool(au.get("muted")):
			return
	if master <= 0.0:
		return
	voice.volume_db = linear_to_db(master * 0.5)
	for ext in [".ogg", ".wav", ".mp3"]:
		var p: String = VO_DIR + id + ext
		if ResourceLoader.exists(p):
			voice.stream = load(p)
			voice.play()
			return

# ---------------- where things are ----------------
func _place() -> void:
	# the spotlight on the step's target; the Herald's panel on the other side of it (under a target in the top half,
	# over one in the bottom half; in the middle when there's none)
	if not is_inside_tree():
		return
	var st: Dictionary = steps[step]
	var r: Rect2 = table.tour_rect(str(st.target)) if table != null else Rect2()
	if r.size != Vector2.ZERO:
		r = Rect2(r.position - global_position, r.size).grow(6.0)
	_target = r
	if _hole.size == Vector2.ZERO:
		_hole = r
	var w := size.x - 24.0
	_panel.size = Vector2(w, 0)
	_panel.reset_size()
	_panel.size.x = w
	var ph := _panel.get_combined_minimum_size().y
	var top: float = 64.0 + float(app.safe_top)
	var y: float
	if r.size == Vector2.ZERO:
		y = size.y * 0.42 - ph * 0.5
	elif r.get_center().y > size.y * 0.5:
		y = r.position.y - ph - 12.0
	else:
		y = r.end.y + 12.0
	_panel.position = Vector2(12.0, clampf(y, top, size.y - ph - 12.0))

func _process(delta: float) -> void:
	_clock += delta
	if steps.is_empty():
		return
	var full := str(steps[step].text).length()
	if shown < float(full):
		shown = minf(float(full), shown + delta * TYPE_CPS)
		_text.visible_characters = int(shown) if shown < float(full) else -1
	# the spotlight eases to its target (the map may move under it: follow the target's rect)
	if table != null and is_inside_tree():
		var r: Rect2 = table.tour_rect(str(steps[step].target))
		_target = Rect2(r.position - global_position, r.size).grow(6.0) if r.size != Vector2.ZERO else Rect2()
	var k := 1.0 - exp(-delta * 10.0)
	if _target.size == Vector2.ZERO:
		# nothing to show: the spotlight closes on its middle
		var keep := _hole.size * (1.0 - k)
		_hole = Rect2() if keep.length() < 4.0 else Rect2(_hole.get_center() - keep * 0.5, keep)
	elif _hole.size == Vector2.ZERO:
		_hole = _target
	else:
		_hole = Rect2(_hole.position.lerp(_target.position, k), _hole.size.lerp(_target.size, k))
	queue_redraw()

func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	if _hole.size.x < 2.0 or _hole.size.y < 2.0:
		draw_rect(full, DIM)
		return
	var h := _hole.intersection(full)
	draw_rect(Rect2(0, 0, size.x, h.position.y), DIM)
	draw_rect(Rect2(0, h.end.y, size.x, size.y - h.end.y), DIM)
	draw_rect(Rect2(0, h.position.y, h.position.x, h.size.y), DIM)
	draw_rect(Rect2(h.end.x, h.position.y, size.x - h.end.x, h.size.y), DIM)
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_corner_radius_all(14)
	var pulse := 0.55 + 0.45 * sin(_clock * 4.0)
	sb.border_color = Color(GLOW, 0.5 + 0.5 * pulse)
	sb.set_border_width_all(3)
	sb.shadow_color = Color(GLOW, 0.35 * pulse)
	sb.shadow_size = 10
	draw_style_box(sb, h)
