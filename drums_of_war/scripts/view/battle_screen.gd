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
const HUD_H := 144.0
const BAR_H := 44.0
const CARD_SIZE := Vector2(104.0, 96.0)
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


func _ready() -> void:
	font = ThemeDB.fallback_font
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
	hud_y = screen.y - HUD_H - bottom
	var field_top := top + BAR_H + 14.0
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
	return Rect2(Vector2(ox + CARD_X0 + CARD_STEP * i, hud_y + 8.0), CARD_SIZE)


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


func _text(pos: Vector2, text: String, size: int, colour: Color, align: int = HORIZONTAL_ALIGNMENT_CENTER, width: float = 200.0) -> void:
	var origin := pos
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		origin.x -= width * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		origin.x -= width
	draw_string(font, origin, text, align, width, size, colour)


func _outlined(pos: Vector2, text: String, size: int, colour: Color, width: float = 200.0) -> void:
	for off: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1), Vector2(1, 2)]:
		_text(pos + off, text, size, Color(COL_INK, colour.a))
	_text(pos, text, size, colour, HORIZONTAL_ALIGNMENT_CENTER, width)


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
		var p := to_screen(e["pos"], 1.6) + Vector2(0, -8.0 - 26.0 * t)
		_outlined(p, e["text"], 17, Color(e["colour"], 1.0 - t * t))


func _draw_top_bar() -> void:
	var enemy := 1 - local_side
	draw_rect(Rect2(0, 0, screen.x, top + BAR_H), Color(COL_INK, 0.92))
	draw_set_transform(Vector2(ox, top), 0.0, Vector2.ONE)
	_text(Vector2(16, 29), "ENEMY", 16, COL_RED.lightened(0.35), HORIZONTAL_ALIGNMENT_LEFT)
	_text(Vector2(524, 29), "YOU", 16, COL_BLUE.lightened(0.45), HORIZONTAL_ALIGNMENT_RIGHT)
	for i in 2:
		var lost_enemy := i < sim.redoubts_lost(enemy)
		var lost_mine := i < sim.redoubts_lost(local_side)
		draw_rect(Rect2(86 + i * 20, 15, 14, 14), COL_BLUE.lightened(0.3) if lost_enemy else Color(1, 1, 1, 0.18))
		draw_rect(Rect2(406 + i * 20, 15, 14, 14), COL_RED.lightened(0.2) if lost_mine else Color(1, 1, 1, 0.18))
	var left := int(ceil(sim.time_left()))
	var clock := "%d:%02d" % [left / 60, left % 60]
	var clock_col := COL_PAPER
	if sim.phase == Sim.PHASE_OVERTIME:
		clock_col = Color("ff8a1f")
	_text(Vector2(270, 32), clock, 24, clock_col)
	if sim.phase == Sim.PHASE_OVERTIME:
		_outlined(Vector2(270, 64), "OVERTIME", 14, Color("ff8a1f"))
	elif sim.double_powder() and sim.phase != Sim.PHASE_OVER:
		_outlined(Vector2(270, 64), "DOUBLE POWDER", 14, COL_AMBER)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if notice_time > 0.0:
		var a := clampf(notice_time, 0.0, 1.0)
		var mid := Vector2(screen.x * 0.5, (top + BAR_H + hud_y) * 0.5)
		draw_rect(Rect2(mid.x - 200.0, mid.y - 17.0, 400, 34), Color(0, 0, 0, 0.6 * a))
		_text(mid + Vector2(0, 6), notice, 15, Color(COL_PAPER, a), HORIZONTAL_ALIGNMENT_CENTER, 400.0)


func _draw_hud() -> void:
	draw_rect(Rect2(0, hud_y, screen.x, screen.y - hud_y), COL_INK)
	draw_rect(Rect2(0, hud_y, screen.x, 3), COL_BRASS.darkened(0.2))
	draw_set_transform(Vector2(ox, 0.0), 0.0, Vector2.ONE)       # the tray's contents sit in a centred column
	var hand: Array = sim.hand(local_side)
	var have: float = sim.powder[local_side]
	var next_id := sim.next_card(local_side)
	draw_rect(Rect2(14, hud_y + 30, 58, 62), Color(1, 1, 1, 0.12))
	_text(Vector2(43, hud_y + 24), "NEXT", 11, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_CENTER, 58.0)
	if next_id != "":
		_draw_card_words(Vector2(43, hud_y + 56), String(cards[next_id]["name"]), 10, Color(1, 1, 1, 0.75), 56.0)
	for i in hand.size():
		var def: Dictionary = cards[hand[i]]
		var rect := _card_rect(i)
		rect.position.x -= ox
		var can_pay := have + 0.0001 >= float(def["cost"])
		if i == selected:
			rect.position.y -= 10.0
			draw_rect(rect.grow(4.0), COL_AMBER)
		draw_rect(rect, COL_PAPER if can_pay else Color("9a9a94"))
		var band := COL_BLUE if def["type"] == "unit" else Color("7a4bb5")
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 22)), band)
		var kind := "ORDER" if def["type"] == "order" else String(def["arm"]).to_upper()
		_text(rect.position + Vector2(rect.size.x * 0.5 + 8.0, 16), kind, 11, COL_PAPER, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 20.0)
		var art := _art(hand[i])
		if art != null:
			# Portrait in the middle, name on a strip underneath.
			var art_rect := Rect2(rect.position + Vector2(0, 22), Vector2(rect.size.x, 52))
			draw_texture_rect(art, art_rect, false, Color.WHITE if can_pay else Color(0.62, 0.62, 0.62))
			draw_rect(Rect2(rect.position + Vector2(0, 74), Vector2(rect.size.x, 22)), COL_INK.lightened(0.08))
			_text(rect.position + Vector2(rect.size.x * 0.5, 90), String(def["name"]), 12, COL_PAPER, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 4.0)
		else:
			_draw_card_words(rect.position + Vector2(rect.size.x * 0.5, 50), String(def["name"]), 15, COL_INK, rect.size.x - 8.0)
			if def["type"] == "unit":
				_text(rect.position + Vector2(rect.size.x * 0.5, 88), "%d men" % int(def["men"]), 11, COL_INK.lightened(0.3), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
		draw_circle(rect.position + Vector2(13, 12), 13.0, COL_AMBER)
		draw_arc(rect.position + Vector2(13, 12), 13.0, 0.0, TAU, 24, COL_INK, 2.0)
		_text(rect.position + Vector2(13, 18), str(int(def["cost"])), 17, COL_INK, HORIZONTAL_ALIGNMENT_CENTER, 26.0)
	var seg := 44.0
	var y := hud_y + 116.0
	for i in int(Sim.POWDER_MAX):
		var cell := Rect2(CARD_X0 + i * seg, y, seg - 4.0, 18)
		draw_rect(cell, Color(1, 1, 1, 0.12))
		var fill := clampf(have - i, 0.0, 1.0)
		if fill > 0.0:
			draw_rect(Rect2(cell.position, Vector2(cell.size.x * fill, cell.size.y)), COL_AMBER if fill >= 1.0 else COL_AMBER.darkened(0.35))
	_text(Vector2(43, y + 15), "%d" % int(have), 20, COL_AMBER, HORIZONTAL_ALIGNMENT_CENTER, 58.0)
	_text(Vector2(43, y - 4), "POWDER", 10, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_CENTER, 58.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
	draw_rect(Rect2(Vector2.ZERO, screen), Color(0, 0, 0, 0.55))
	var cx := screen.x * 0.5
	var cy := screen.y * 0.44
	var text := "DRAW"
	var col := COL_PAPER
	if sim.winner == local_side:
		text = "VICTORY"
		col = COL_AMBER
	elif sim.winner == 1 - local_side:
		text = "DEFEAT"
		col = Color("ff6a5a")
	_text(Vector2(cx, cy), text, 64, col, HORIZONTAL_ALIGNMENT_CENTER, 520.0)
	var how := "Time ran out"
	if sim.hq(0).dead or sim.hq(1).dead:
		how = "The Colours were captured"
	elif sim.time > Sim.MATCH_TIME + 0.5 and sim.time < Sim.MATCH_TIME + Sim.OVERTIME:
		how = "Decided in overtime"
	_text(Vector2(cx, cy + 42.0), how, 18, COL_PAPER, HORIZONTAL_ALIGNMENT_CENTER, 520.0)
	_text(Vector2(cx, cy + 100.0), "Tap to play again", 18, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 520.0)
