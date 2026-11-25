extends Node2D
## The battle screen: runs the rules engine and the bot, turns taps into deploys, and draws the
## HUD over the 3D battlefield (battle_world.gd). It also plays the sounds.

const Sim = preload("res://scripts/sim/battle_sim.gd")
const Bot = preload("res://scripts/sim/bot.gd")
const World = preload("res://scripts/view/battle_world.gd")

const DECK := ["line_infantry", "skirmishers", "militia", "scouts", "heavy_cavalry", "field_gun", "fire", "rally"]

# Layout. The design space is 540 wide; the game fills whatever screen it is given, so the
# height (and on tablets the width) is whatever the display's shape makes it. _layout() works
# out where the top bar and the card tray sit, clear of any notch or gesture bar.
const CARD_W := 104.0
const CARD_BAND := 24.0             # the coloured strip across a card's top, and the name strip
const POWDER_H := 20.0
const BAR_H := 50.0
const CARD_X0 := 84.0
const CARD_STEP := 112.0
const AUDIO_DIR := "res://assets/audio/"
const CARD_ART_DIR := "res://assets/cards/"

const COL_BLUE := Color("2456c9")
const COL_RED := Color("c81e3a")
const COL_INK := Color("15233a")
const COL_PAPER := Color("f6f2e6")
const COL_BRASS := Color("f2b632")
const COL_AMBER := Color("ffb000")
const COL_CREAM := Color("f6ead0")
const COL_WOOD_DARK := Color("2a1a0f")
const COL_BRASS_DARK := Color("7a5a1e")
const COL_BRASS_MID := Color("c9a03c")
const COL_BRASS_LIGHT := Color("f5d98a")

var cards: Dictionary
var sim: Sim
var bot: Bot
var auto_bot: Bot = null            # set by autoplay: a bot also plays the local side
var world: World
var local_side: int = 0
var autoplay: bool = false
var match_seed: int = 0
var acc: float = 0.0

var selected: int = -1
var pointer: Vector2 = Vector2.ZERO
var pointer_down: bool = false
var notice: String = ""
var notice_time: float = 0.0

var words: Array = []               # floating words over the field: {pos, age, life, text, colour}
var font: Font
var font_bold: FontVariation
var _wood: NoiseTexture2D
var _boxes: Dictionary = {}
var _players: Array = []
var _next_player: int = 0
var _streams: Dictionary = {}
var _music: AudioStreamPlayer
var _last_played: Dictionary = {}
var _clock: float = 0.0
var _card_art: Dictionary = {}

var screen: Vector2 = Vector2(540.0, 960.0)   # the visible area, in design units
var top: float = 0.0                # height kept clear at the top (camera notch)
var bottom: float = 0.0             # ... and at the bottom (gesture bar)
var ox: float = 0.0                 # left edge of the centred 540-wide HUD column
var hud_y: float = 816.0            # top of the card tray
var _laid_out: bool = false
var art_h: float = 64.0             # height of a card's portrait; taller screens get more
var card_size: Vector2 = Vector2(104.0, 112.0)
var _vignette: GradientTexture2D


func _ready() -> void:
	font = ThemeDB.fallback_font
	font_bold = FontVariation.new()
	font_bold.base_font = font
	font_bold.variation_embolden = 0.85
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED      # the wood grain tiles
	_wood = _make_wood()
	cards = Sim.load_cards()
	if match_seed == 0:
		match_seed = int(Time.get_unix_time_from_system()) % 1000000 + 1
	sim = Sim.new(match_seed, cards, DECK, DECK)
	world = World.new()
	world.sim = sim
	world.local_side = local_side
	add_child(world)
	_setup_audio()
	start_match(match_seed)


func start_match(seed_value: int) -> void:
	match_seed = seed_value
	sim = Sim.new(seed_value, cards, DECK, DECK)
	bot = Bot.new(1 - local_side, seed_value)
	auto_bot = Bot.new(local_side, seed_value + 99) if autoplay else null
	world.reset(sim)
	words.clear()
	selected = -1
	acc = 0.0
	notice = ""
	if _music != null and _music.stream != null and not _music.playing:
		_music.play()


## Fits the HUD and the battlefield to the screen as it is right now.
func _layout() -> void:
	var now := get_viewport_rect().size
	var new_top := 0.0
	var new_bottom := 0.0
	if OS.has_feature("mobile"):
		var window := Vector2(DisplayServer.window_get_size())
		var safe := DisplayServer.get_display_safe_area()
		if window.y > 0.0 and safe.size.y > 0:
			var per_pixel := now.y / window.y
			new_top = clampf(float(safe.position.y) * per_pixel, 0.0, 90.0)
			new_bottom = clampf((window.y - float(safe.end.y)) * per_pixel, 0.0, 90.0)
	if now == screen and new_top == top and new_bottom == bottom and world.field_rect_design.size.x > 0.0 and _laid_out:
		return
	_laid_out = true
	screen = now
	top = new_top
	bottom = new_bottom
	ox = (screen.x - 540.0) * 0.5
	# The tray: cards with a portrait tall enough to show the whole figure where there is room,
	# the Powder bar under them, and a margin so nothing sits in a rounded corner.
	art_h = clampf(64.0 + (screen.y - 960.0) * 0.22, 64.0, 112.0)
	card_size = Vector2(CARD_W, CARD_BAND + art_h + CARD_BAND)
	hud_y = screen.y - (14.0 + card_size.y + 12.0 + POWDER_H + maxf(bottom, 14.0) + 8.0)
	var field_top := top + BAR_H + 20.0
	world.field_rect_design = Rect2(22.0, field_top, screen.x - 44.0, hud_y - field_top - 10.0)
	world.fit_camera()


func _process(delta: float) -> void:
	_layout()
	_clock += delta
	acc += delta
	var steps := 0
	while acc >= Sim.DT and steps < 6:
		acc -= Sim.DT
		steps += 1
		bot.tick(sim)
		if auto_bot != null:
			auto_bot.tick(sim)
		sim.tick()
		_take_events()
	if steps == 6:
		acc = 0.0
	for w: Dictionary in words:
		w["age"] = float(w["age"]) + delta
	words = words.filter(func(w: Dictionary) -> bool: return float(w["age"]) < float(w["life"]))
	if notice_time > 0.0:
		notice_time -= delta
	queue_redraw()


# ==========================================================================================
# Input
# ==========================================================================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		pointer = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pointer = event.position
		if event.pressed:
			pointer_down = true
			_on_press(pointer)
		else:
			pointer_down = false
			_on_release(pointer)


func _on_press(p: Vector2) -> void:
	if sim.phase == Sim.PHASE_OVER:
		start_match(match_seed + 1)
		return
	var slot := _card_at(p)
	if slot >= 0:
		selected = -1 if selected == slot else slot
		_sfx("card_select")


func _on_release(p: Vector2) -> void:
	if selected < 0 or sim.phase == Sim.PHASE_OVER:
		return
	if p.y >= hud_y or p.y < top + BAR_H:
		return
	var where := to_field(p)
	var why := sim.deploy_error(local_side, selected, where)
	if why == "":
		sim.deploy(local_side, selected, where)
		selected = -1
	else:
		notice = why
		notice_time = 1.6


func _card_at(p: Vector2) -> int:
	for i in Sim.HAND_SIZE:
		if _card_rect(i).has_point(p):
			return i
	return -1


func _card_rect(i: int) -> Rect2:
	return Rect2(Vector2(ox + CARD_X0 + CARD_STEP * i, hud_y + 14.0), card_size)


func to_screen(p: Vector2, height: float = 0.0) -> Vector2:
	return world.project(p, height)


func to_field(p: Vector2) -> Vector2:
	return world.pick(p)


func team_colour(side: int) -> Color:
	return COL_BLUE if side == local_side else COL_RED


# ==========================================================================================
# Sound
# ==========================================================================================

func _setup_audio() -> void:
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -14.0
	add_child(_music)
	var music := _stream("music_battle")
	if music != null:
		if music is AudioStreamOggVorbis:
			(music as AudioStreamOggVorbis).loop = true
		_music.stream = music


func _stream(sound: String) -> AudioStream:
	if not _streams.has(sound):
		var path := AUDIO_DIR + sound + ".ogg"
		_streams[sound] = load(path) if ResourceLoader.exists(path) else null
	return _streams[sound]


## Plays a sound if its file exists. The same sound is not restarted within min_gap seconds,
## so a dozen volleys in one instant do not stack into noise.
func _sfx(sound: String, volume_db: float = 0.0, min_gap: float = 0.08) -> void:
	var stream := _stream(sound)
	if stream == null:
		return
	if _clock - float(_last_played.get(sound, -10.0)) < min_gap:
		return
	_last_played[sound] = _clock
	var p: AudioStreamPlayer = _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = randf_range(0.94, 1.06)
	p.play()


# ==========================================================================================
# Rule events: sound, floating words, and the 3D effects
# ==========================================================================================

func _take_events() -> void:
	for e: Dictionary in sim.events:
		world.on_event(e)
		var pos: Vector2 = e.get("pos", Vector2.ZERO)
		match e["type"]:
			"volley":
				_sfx("volley_1" if (int(pos.x * 7.0) + sim.tick_count) % 2 == 0 else "volley_2", -3.0, 0.12)
			"cannon":
				var from_structure := false
				for s: Sim.Structure in sim.structures:
					if s.pos.distance_to(pos) < 0.01:
						from_structure = true
				_sfx("redoubt_gun" if from_structure else "cannon", -5.0 if from_structure else -1.0, 0.1)
			"canister":
				_sfx("canister")
			"deploy":
				_sfx("deploy", -4.0)
			"rout":
				_word(pos, "ROUT!", Color("ffe14d"))
				_sfx("rout", -3.0, 0.5)
			"rally":
				_word(pos, "RALLIED", COL_PAPER)
				_sfx("rally", -4.0, 0.5)
			"square":
				_word(pos, "SQUARE", COL_PAPER)
				_sfx("square", -3.0, 0.3)
			"charge":
				_word(pos, "CHARGE!", Color("ff8a1f"))
				_sfx("charge", -2.0, 0.6)
			"repelled":
				_word(pos, "REPELLED", COL_PAPER)
				_sfx("repelled", -2.0, 0.5)
			"order":
				_word(pos, String(cards[e["card"]]["name"]).to_upper(), COL_AMBER)
				_sfx("order")
			"destroyed":
				_word(pos, "DESTROYED", Color("ff8a1f"))
				_sfx("destroyed")
			"overtime":
				notice = "OVERTIME: first structure to fall decides it"
				notice_time = 3.0
				_sfx("overtime")
			"over":
				if _music != null:
					_music.stop()
				if int(e["winner"]) == local_side:
					_sfx("victory")
				elif int(e["winner"]) == 1 - local_side:
					_sfx("defeat")
	sim.events.clear()


func _word(pos: Vector2, text: String, colour: Color) -> void:
	words.append({"pos": pos, "age": 0.0, "life": 1.1, "text": text, "colour": colour})


# ==========================================================================================
# Drawing (everything here is 2D, over the 3D view)
# ==========================================================================================

func _draw() -> void:
	_draw_vignette()
	if selected >= 0:
		_draw_deploy_zone()
	for s: Sim.Structure in sim.structures:
		_draw_structure_bar(s)
	for r: Sim.Regiment in sim.regiments:
		_draw_regiment_bars(r)
	_draw_words()
	_draw_top_bar()
	_draw_hud()
	if sim.phase == Sim.PHASE_OVER:
		_draw_result()


func _text(pos: Vector2, text: String, size: int, colour: Color, align: int = HORIZONTAL_ALIGNMENT_CENTER, width: float = 200.0, bold: bool = false) -> void:
	var origin := pos
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		origin.x -= width * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		origin.x -= width
	draw_string(font_bold if bold else font, origin, text, align, width, size, colour)


## Bold lettering with a thick dark outline and a drop shadow, legible over grass, smoke and
## troops alike.
func _outlined(pos: Vector2, text: String, size: int, colour: Color, width: float = 320.0, outline: int = 7) -> void:
	var origin := pos - Vector2(width * 0.5, 0.0)
	var dark := Color(0.09, 0.06, 0.05, colour.a)
	draw_string_outline(font_bold, origin + Vector2(0, 3), text, HORIZONTAL_ALIGNMENT_CENTER, width, size, outline, Color(0, 0, 0, 0.45 * colour.a))
	draw_string_outline(font_bold, origin, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, outline, dark)
	draw_string(font_bold, origin, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, colour)


# --- Wood and brass --------------------------------------------------------------------------

## A strip of wood grain, made once: noise much longer one way than the other, in browns.
func _make_wood() -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.035
	n.fractal_octaves = 4
	n.seed = 1861
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.4, 0.62, 0.8, 1.0])
	ramp.colors = PackedColorArray([Color("38230f"), Color("4a2f17"), Color("5a3a1d"), Color("4f3319"), Color("6a4624")])
	var t := NoiseTexture2D.new()
	t.width = 48
	t.height = 256
	t.seamless = true
	t.noise = n
	t.color_ramp = ramp
	return t


## A panel of dark planks: grain running across, a seam every plank's width.
func _wood_panel(rect: Rect2, tint: Color = Color.WHITE) -> void:
	draw_rect(rect, Color("4a2f17") * tint)
	if _wood != null:
		draw_texture_rect_region(_wood, rect, Rect2(0, 0, rect.size.x / 9.0, rect.size.y / 1.1), tint)
	var plank := 46.0
	var y := rect.position.y + plank
	while y < rect.end.y - 4.0:
		draw_rect(Rect2(rect.position.x, y, rect.size.x, 2.0), Color(0.08, 0.05, 0.03, 0.55))
		draw_rect(Rect2(rect.position.x, y + 2.0, rect.size.x, 1.0), Color(1, 0.9, 0.7, 0.07))
		y += plank


## A bevelled brass strip: dark edge, bright face, dark edge.
func _brass_strip(rect: Rect2) -> void:
	draw_rect(rect, COL_BRASS_DARK)
	draw_rect(Rect2(rect.position + Vector2(0, 1), Vector2(rect.size.x, maxf(1.0, rect.size.y - 2.0))), COL_BRASS_MID)
	draw_rect(Rect2(rect.position + Vector2(0, 1), Vector2(rect.size.x, 1.0)), COL_BRASS_LIGHT)


func _brass_frame(rect: Rect2, width: float = 3.0) -> void:
	draw_rect(rect, COL_BRASS_DARK, false, width + 2.0)
	draw_rect(rect, COL_BRASS_MID, false, width)
	draw_rect(rect.grow(width * 0.5 - 0.5), COL_BRASS_LIGHT, false, 1.0)


func _rivet(at: Vector2) -> void:
	draw_circle(at + Vector2(0, 1.5), 5.0, Color(0, 0, 0, 0.45))
	draw_circle(at, 5.0, COL_BRASS_DARK)
	draw_circle(at, 3.8, COL_BRASS_MID)
	draw_circle(at + Vector2(-1.2, -1.2), 1.5, COL_BRASS_LIGHT)


## A rounded box with an optional border and soft shadow; made once per look and reused.
func _box(key: String, fill: Color, radius: float, border: float = 0.0, border_colour: Color = Color.BLACK,
		shadow: float = 0.0, shadow_colour: Color = Color(0, 0, 0, 0.5), shadow_drop: float = 0.0) -> StyleBoxFlat:
	if not _boxes.has(key):
		var sb := StyleBoxFlat.new()
		sb.bg_color = fill
		sb.set_corner_radius_all(int(radius))
		sb.set_border_width_all(int(border))
		sb.border_color = border_colour
		sb.shadow_size = int(shadow)
		sb.shadow_color = shadow_colour
		sb.shadow_offset = Vector2(0, shadow_drop)
		sb.anti_aliasing = true
		_boxes[key] = sb
	return _boxes[key]


## The Powder cost as an embossed gold coin.
func _coin(at: Vector2, cost: int, can_pay: bool) -> void:
	var dull := 1.0 if can_pay else 0.62
	draw_circle(at + Vector2(0, 2.5), 15.5, Color(0, 0, 0, 0.5))
	draw_circle(at, 15.5, Color("7a5510") * Color(dull, dull, dull))
	draw_circle(at, 14.0, Color("f7d868") * Color(dull, dull, dull))
	draw_circle(at, 11.5, Color("e0a626") * Color(dull, dull, dull))
	draw_arc(at, 12.6, PI * 1.05, PI * 1.6, 12, Color(1.0, 0.97, 0.75, 0.9 * dull), 1.6)
	draw_arc(at, 12.6, PI * 0.05, PI * 0.6, 12, Color(0.45, 0.3, 0.05, 0.7), 1.6)
	var text := str(cost)
	_text(at + Vector2(0, 7.5), text, 19, Color(1.0, 0.93, 0.6, dull), HORIZONTAL_ALIGNMENT_CENTER, 30.0, true)
	_text(at + Vector2(0, 6.5), text, 19, Color("4a3206"), HORIZONTAL_ALIGNMENT_CENTER, 30.0, true)


func _field_quad(x0: float, x1: float, depth0: float, depth1: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for corner: Vector2 in [Vector2(x0, depth0), Vector2(x1, depth0), Vector2(x1, depth1), Vector2(x0, depth1)]:
		pts.append(to_screen(Sim.from_local(local_side, corner), 0.05))
	return pts


func _draw_deploy_zone() -> void:
	var def: Dictionary = cards[sim.hand(local_side)[selected]]
	var tint := Color(1, 1, 1, 0.2)
	var edge := Color(1, 1, 1, 0.75)
	if def["type"] == "order":
		var all := _field_quad(0.0, Sim.FIELD_W, 0.0, Sim.FIELD_H)
		draw_colored_polygon(all, Color(1, 1, 1, 0.1))
	else:
		for flank in 2:
			var x0 := flank * Sim.FIELD_W * 0.5
			var depth := sim.deploy_depth(local_side, x0 + 1.0)
			var quad := _field_quad(x0, x0 + Sim.FIELD_W * 0.5, 0.0, depth)
			draw_colored_polygon(quad, tint)
			draw_line(quad[2], quad[3], edge, 2.0)
	if pointer.y < hud_y and pointer.y > top + BAR_H:
		var at := to_field(pointer)
		var ok := sim.deploy_error(local_side, selected, at) == ""
		var ring := COL_PAPER if ok else Color("ff5a4d")
		var radius := float(def.get("radius", 1.0))
		var pts := PackedVector2Array()
		for k in 33:
			pts.append(to_screen(at + Vector2.from_angle(TAU * k / 32.0) * radius, 0.05))
		draw_polyline(pts, ring, 2.5)
		draw_circle(pointer, 4.0, ring)


func _draw_structure_bar(s: Sim.Structure) -> void:
	if s.dead:
		return
	var p := to_screen(s.pos, 0.0) + Vector2(0, 14.0 if s.side == local_side else -64.0)
	if s.kind == "redoubt":
		p = to_screen(s.pos, 0.0) + Vector2(0, 26.0 if s.side == local_side else -46.0)
	var w := 54.0 if s.kind == "hq" else 44.0
	var col := team_colour(s.side)
	draw_rect(Rect2(p + Vector2(-w * 0.5, 0), Vector2(w, 8)), COL_INK)
	draw_rect(Rect2(p + Vector2(-w * 0.5 + 1, 1), Vector2((w - 2) * s.hp / s.max_hp, 6)), col.lightened(0.3))


func _draw_regiment_bars(r: Sim.Regiment) -> void:
	var tall := 3.5 if r.arm == "cavalry" else 2.6
	var p := to_screen(r.pos, tall)
	var w := 30.0
	var top := p + Vector2(-w * 0.5, -6.0)
	var col := team_colour(r.side)
	draw_rect(Rect2(top - Vector2(1, 1), Vector2(w + 2, 11)), COL_INK)
	draw_rect(Rect2(top, Vector2(w * r.hp / r.max_hp, 4)), col.lightened(0.35))
	draw_rect(Rect2(top + Vector2(0, 5), Vector2(w * maxf(r.morale, 0.0) / r.morale_max, 4)), COL_BRASS)
	if r.reload > 0.0 and r.def.has("reload") and r.state != Sim.ST_ROUT:
		var frac := clampf(r.reload / float(r.def["reload"]), 0.0, 1.0)
		var c := p + Vector2(w * 0.5 + 8.0, -1.0)
		draw_circle(c, 6.0, COL_INK)
		draw_arc(c, 3.6, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - frac), 16, COL_PAPER, 2.5)
	if r.state == Sim.ST_FORMING:
		draw_arc(to_screen(r.pos, 0.6), 18.0, 0.0, TAU * (1.0 - r.form_timer / Sim.SQUARE_FORM_TIME_RELOADING), 24, COL_PAPER, 2.5)


func _draw_words() -> void:
	for e: Dictionary in words:
		var t := float(e["age"]) / float(e["life"])
		# Pops in large, settles, then lifts away as it fades.
		var pop := 1.0 + 0.45 * maxf(0.0, 1.0 - t * 7.0)
		var p := to_screen(e["pos"], 1.6) + Vector2(0, -10.0 - 30.0 * t * t)
		_outlined(p, e["text"], int(23.0 * pop), Color(e["colour"], 1.0 - pow(t, 4.0)))


func _draw_top_bar() -> void:
	var enemy := 1 - local_side
	var bar := Rect2(0, 0, screen.x, top + BAR_H)
	_wood_panel(bar)
	draw_rect(Rect2(0, bar.end.y - 10.0, screen.x, 10.0), Color(0, 0, 0, 0.25))
	_brass_strip(Rect2(0, bar.end.y - 4.0, screen.x, 4.0))
	draw_rect(Rect2(0, bar.end.y, screen.x, 5.0), Color(0, 0, 0, 0.28))            # the bar's shadow on the field
	draw_set_transform(Vector2(ox, top), 0.0, Vector2.ONE)
	_rivet(Vector2(10, 12))
	_rivet(Vector2(530, 12))
	_text(Vector2(26, 33), "ENEMY", 16, Color("f08a78"), HORIZONTAL_ALIGNMENT_LEFT, 200.0, true)
	_text(Vector2(514, 33), "YOU", 16, Color("86b4ff"), HORIZONTAL_ALIGNMENT_RIGHT, 200.0, true)
	# Redoubts taken: an inset slot for each, lit in the taker's colour.
	for i in 2:
		for mine in 2:
			var slot := Rect2(98.0 + i * 22.0, 19.0, 17.0, 17.0) if mine == 0 else Rect2(403.0 + i * 22.0, 19.0, 17.0, 17.0)
			var lost := i < (sim.redoubts_lost(enemy) if mine == 0 else sim.redoubts_lost(local_side))
			draw_rect(slot.grow(1.5), COL_BRASS_DARK)
			draw_rect(slot, Color("1a110a"))
			if lost:
				draw_rect(slot.grow(-2.0), COL_BLUE.lightened(0.25) if mine == 0 else COL_RED.lightened(0.15))
				draw_rect(Rect2(slot.position + Vector2(2, 2), Vector2(slot.size.x - 4.0, 3.0)), Color(1, 1, 1, 0.35))
	# The clock sits on a plaque that hangs below the bar.
	var plaque := PackedVector2Array([Vector2(194, -top), Vector2(346, -top), Vector2(346, BAR_H - 2.0), Vector2(330, BAR_H + 13.0),
			Vector2(210, BAR_H + 13.0), Vector2(194, BAR_H - 2.0)])
	draw_colored_polygon(plaque, COL_WOOD_DARK)
	var edge := PackedVector2Array([plaque[1], plaque[2], plaque[3], plaque[4], plaque[5], plaque[0]])
	draw_polyline(edge, COL_BRASS_DARK, 5.0)
	draw_polyline(edge, COL_BRASS_MID, 3.0)
	var left := int(ceil(sim.time_left()))
	var clock := "%d:%02d" % [left / 60, left % 60]
	var clock_col := COL_CREAM
	if sim.phase == Sim.PHASE_OVERTIME or (left <= 10 and sim.phase == Sim.PHASE_REGULAR):
		clock_col = Color("ff9a3c")
	_text(Vector2(270, 41), clock, 28, Color(0, 0, 0, 0.6), HORIZONTAL_ALIGNMENT_CENTER, 200.0, true)
	_text(Vector2(270, 39), clock, 28, clock_col, HORIZONTAL_ALIGNMENT_CENTER, 200.0, true)
	if sim.phase == Sim.PHASE_OVERTIME:
		_outlined(Vector2(270, BAR_H + 40.0), "OVERTIME", 16, Color("ff9a3c"))
	elif sim.double_powder() and sim.phase != Sim.PHASE_OVER:
		_outlined(Vector2(270, BAR_H + 40.0), "DOUBLE POWDER", 16, COL_AMBER)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if notice_time > 0.0:
		var a := clampf(notice_time, 0.0, 1.0)
		var mid := Vector2(screen.x * 0.5, (top + BAR_H + hud_y) * 0.5)
		draw_style_box(_box("notice", Color(0.1, 0.06, 0.03, 0.82), 8.0, 2.0, COL_BRASS_MID), Rect2(mid.x - 210.0, mid.y - 20.0, 420.0, 40.0))
		_text(mid + Vector2(0, 6), notice, 15, Color(COL_CREAM, a), HORIZONTAL_ALIGNMENT_CENTER, 400.0, true)


## One card face: coloured strip with its kind, the portrait, the name, and the Powder cost.
func _draw_card(rect: Rect2, card_id: String, can_pay: bool, chosen: bool) -> void:
	var def: Dictionary = cards[card_id]
	var is_order: bool = def["type"] == "order"
	# Frame: drop shadow, then brass in three steps for a bevel. A playable card has a faint
	# amber halo; the chosen one a strong one.
	if chosen:
		draw_style_box(_box("card_glow", Color(1, 0.75, 0.1, 0.0), 10.0, 0.0, Color.BLACK, 14.0, Color(1.0, 0.72, 0.1, 0.95)), rect.grow(3.0))
	elif can_pay:
		draw_style_box(_box("card_ready", Color(1, 0.75, 0.1, 0.0), 10.0, 0.0, Color.BLACK, 7.0, Color(1.0, 0.72, 0.1, 0.4)), rect.grow(3.0))
	draw_style_box(_box("card_edge", COL_BRASS_DARK, 9.0, 0.0, Color.BLACK, 9.0, Color(0, 0, 0, 0.6), 5.0), rect.grow(4.0))
	draw_style_box(_box("card_face", COL_BRASS_LIGHT, 8.0), rect.grow(2.5))
	draw_style_box(_box("card_inner", COL_BRASS_MID, 6.0, 1.0, COL_BRASS_DARK), rect.grow(1.0))
	var inner := rect.grow(-2.0)
	var band := Color("6a3fa8") if is_order else Color("2456c9")
	var band_rect := Rect2(inner.position, Vector2(inner.size.x, CARD_BAND - 2.0))
	draw_rect(band_rect, band)
	draw_rect(Rect2(band_rect.position, Vector2(band_rect.size.x, band_rect.size.y * 0.45)), Color(1, 1, 1, 0.14))
	draw_rect(Rect2(band_rect.position.x, band_rect.end.y - 2.0, band_rect.size.x, 2.0), Color(0, 0, 0, 0.3))
	var kind := "ORDER" if is_order else String(def["arm"]).to_upper()
	_text(band_rect.position + Vector2(band_rect.size.x * 0.5 + 10.0, 16), kind, 11, COL_CREAM, HORIZONTAL_ALIGNMENT_CENTER, band_rect.size.x - 24.0, true)
	var name_rect := Rect2(Vector2(inner.position.x, inner.end.y - CARD_BAND + 2.0), Vector2(inner.size.x, CARD_BAND - 2.0))
	var art_rect := Rect2(Vector2(inner.position.x, band_rect.end.y), Vector2(inner.size.x, name_rect.position.y - band_rect.end.y))
	var art := _art(card_id)
	if art != null:
		# The portrait is drawn from the top of the picture down, as much as the card has room for.
		var src_w := float(art.get_width())
		var src_h := minf(float(art.get_height()), src_w * art_rect.size.y / art_rect.size.x)
		draw_texture_rect_region(art, art_rect, Rect2(0, 0, src_w, src_h))
	else:
		draw_rect(art_rect, band.lightened(0.55))
		_draw_card_words(art_rect.get_center() + Vector2(0, 6), String(def["name"]), 15, COL_INK, rect.size.x - 8.0)
	draw_rect(Rect2(art_rect.position, Vector2(art_rect.size.x, 5.0)), Color(0, 0, 0, 0.18))      # the frame's shadow on the picture
	draw_rect(name_rect, COL_WOOD_DARK)
	draw_rect(Rect2(name_rect.position, Vector2(name_rect.size.x, 1.5)), COL_BRASS_MID)
	_text(name_rect.position + Vector2(name_rect.size.x * 0.5, 16), String(def["name"]), 13, COL_CREAM, HORIZONTAL_ALIGNMENT_CENTER, name_rect.size.x - 4.0, true)
	if not can_pay:
		draw_rect(inner, Color(0.06, 0.05, 0.08, 0.4))
	_coin(rect.position + Vector2(9, 9), int(def["cost"]), can_pay)


func _draw_hud() -> void:
	var tray := Rect2(0, hud_y, screen.x, screen.y - hud_y)
	draw_rect(Rect2(0, hud_y - 5.0, screen.x, 5.0), Color(0, 0, 0, 0.28))             # the tray's shadow on the field
	_wood_panel(tray)
	_brass_strip(Rect2(0, hud_y, screen.x, 4.0))
	draw_set_transform(Vector2(ox, 0.0), 0.0, Vector2.ONE)       # the tray's contents sit in a centred column
	_brass_frame(Rect2(7, hud_y + 9.0, 526, tray.size.y - 9.0 - maxf(bottom, 6.0) - 6.0), 2.0)
	for corner: Vector2 in [Vector2(15, hud_y + 17.0), Vector2(525, hud_y + 17.0)]:
		_rivet(corner)
	var hand: Array = sim.hand(local_side)
	var have: float = sim.powder[local_side]
	var cards_y := hud_y + 14.0
	# The next card, small, at the left.
	var next_id := sim.next_card(local_side)
	_text(Vector2(43, cards_y + 13), "NEXT", 11, COL_CREAM, HORIZONTAL_ALIGNMENT_CENTER, 58.0, true)
	var next_rect := Rect2(17, cards_y + 20, 52, 52)
	draw_style_box(_box("next_edge", COL_BRASS_DARK, 6.0, 0.0, Color.BLACK, 6.0, Color(0, 0, 0, 0.55), 3.0), next_rect.grow(3.0))
	draw_style_box(_box("next_face", COL_BRASS_MID, 5.0), next_rect.grow(1.5))
	if next_id != "":
		var next_art := _art(next_id)
		if next_art != null:
			var w := float(next_art.get_width())
			draw_texture_rect_region(next_art, next_rect, Rect2(0, 0, w, w))
		else:
			draw_rect(next_rect, COL_WOOD_DARK)
			_draw_card_words(next_rect.get_center() + Vector2(0, 4), String(cards[next_id]["name"]), 10, COL_CREAM, 50.0)
	var cheapest := 99.0
	for i in hand.size():
		cheapest = minf(cheapest, float(cards[hand[i]]["cost"]))
		var rect := _card_rect(i)
		rect.position.x -= ox
		if i == selected:
			rect.position.y -= 12.0
		_draw_card(rect, hand[i], have + 0.0001 >= float(cards[hand[i]]["cost"]), i == selected)

	# Powder: ten framed slots. Full charges are bevelled amber, and they glow while there is
	# enough to play something. With a card chosen, the charges it would spend are outlined.
	var seg := 44.0
	var y := cards_y + card_size.y + 13.0
	var ready := have + 0.0001 >= cheapest
	var throb := 0.5 + 0.5 * sin(_clock * 4.0)
	var spend := int(cards[hand[selected]]["cost"]) if selected >= 0 and selected < hand.size() else 0
	for i in int(Sim.POWDER_MAX):
		var cell := Rect2(CARD_X0 + i * seg, y, seg - 5.0, POWDER_H)
		var fill := clampf(have - i, 0.0, 1.0)
		if fill >= 1.0 and ready:
			draw_style_box(_box("keg_glow", Color(1, 0.7, 0.1, 0.0), 5.0, 0.0, Color.BLACK, 7.0, Color(1.0, 0.68, 0.1, 0.55)), cell)
			draw_rect(cell.grow(1.0 + throb), Color(1.0, 0.72, 0.15, 0.1 + 0.16 * throb))
		draw_style_box(_box("keg_slot", Color("140c06"), 4.0, 2.0, COL_BRASS_DARK), cell.grow(1.5))
		if fill > 0.0:
			var bar := Rect2(cell.position + Vector2(2, 2), Vector2((cell.size.x - 4.0) * fill, cell.size.y - 4.0))
			var dim := 1.0 if fill >= 1.0 else 0.55
			draw_rect(bar, Color("f2a31a") * Color(dim, dim, dim))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x, bar.size.y * 0.45)), Color(1.0, 0.86, 0.42, dim))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x, 1.5)), Color(1.0, 0.97, 0.8, dim))
			draw_rect(Rect2(bar.position.x, bar.end.y - 3.0, bar.size.x, 3.0), Color(0.72, 0.42, 0.04, dim))
		if i < spend:
			draw_rect(cell.grow(2.5), COL_CREAM, false, 2.0)
	_text(Vector2(43, y + 18), "%d" % int(have), 24, Color(0, 0, 0, 0.6), HORIZONTAL_ALIGNMENT_CENTER, 58.0, true)
	_text(Vector2(43, y + 16), "%d" % int(have), 24, COL_AMBER if ready else COL_CREAM, HORIZONTAL_ALIGNMENT_CENTER, 58.0, true)
	_text(Vector2(43, y - 8), "POWDER", 10, COL_CREAM, HORIZONTAL_ALIGNMENT_CENTER, 58.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A soft darkening toward the corners of the battlefield, drawn under the bars.
func _draw_vignette() -> void:
	if _vignette == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
		g.colors = PackedColorArray([Color(0.1, 0.05, 0.02, 0.0), Color(0.1, 0.05, 0.02, 0.0), Color(0.1, 0.05, 0.02, 0.42)])
		_vignette = GradientTexture2D.new()
		_vignette.gradient = g
		_vignette.fill = GradientTexture2D.FILL_RADIAL
		_vignette.fill_from = Vector2(0.5, 0.5)
		_vignette.fill_to = Vector2(1.0, 1.0)
		_vignette.width = 128
		_vignette.height = 128
	draw_texture_rect(_vignette, Rect2(0, top + BAR_H, screen.x, hud_y - top - BAR_H), false)


func _art(card_id: String) -> Texture2D:
	if not _card_art.has(card_id):
		var path := CARD_ART_DIR + card_id + ".png"
		_card_art[card_id] = load(path) if ResourceLoader.exists(path) else null
	return _card_art[card_id]


func _draw_card_words(centre: Vector2, name: String, size: int, colour: Color, width: float) -> void:
	var parts := name.split(" ")
	var y := centre.y - (parts.size() - 1) * (size + 2) * 0.5
	for w: String in parts:
		_text(Vector2(centre.x, y), w, size, colour, HORIZONTAL_ALIGNMENT_CENTER, width)
		y += size + 2


func _draw_result() -> void:
	draw_rect(Rect2(Vector2.ZERO, screen), Color(0.05, 0.03, 0.02, 0.6))
	var cx := screen.x * 0.5
	var cy := screen.y * 0.42
	var text := "DRAW"
	var col := COL_CREAM
	if sim.winner == local_side:
		text = "VICTORY"
		col = Color("ffd24a")
	elif sim.winner == 1 - local_side:
		text = "DEFEAT"
		col = Color("ff7a66")
	var plate := Rect2(cx - 220.0, cy - 78.0, 440.0, 190.0)
	draw_style_box(_box("result_edge", COL_BRASS_DARK, 14.0, 0.0, Color.BLACK, 16.0, Color(0, 0, 0, 0.7), 6.0), plate.grow(5.0))
	draw_style_box(_box("result_face", COL_BRASS_MID, 12.0), plate.grow(2.0))
	draw_style_box(_box("result_wood", COL_WOOD_DARK, 10.0), plate)
	_outlined(Vector2(cx, cy), text, 62, col, 440.0, 9)
	var how := "Time ran out"
	if sim.hq(0).dead or sim.hq(1).dead:
		how = "The Colours were captured"
	elif sim.time > Sim.MATCH_TIME + 0.5 and sim.time < Sim.MATCH_TIME + Sim.OVERTIME:
		how = "Decided in overtime"
	_text(Vector2(cx, cy + 40.0), how, 18, COL_CREAM, HORIZONTAL_ALIGNMENT_CENTER, 420.0, true)
	_text(Vector2(cx, cy + 86.0), "Tap to play again", 17, Color(COL_CREAM, 0.6 + 0.4 * sin(_clock * 3.0)), HORIZONTAL_ALIGNMENT_CENTER, 420.0, true)