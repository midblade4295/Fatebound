extends Node2D
## The battle screen: runs the rules engine and the bot, turns taps into deploys, and draws the
## HUD over the 3D battlefield (battle_world.gd). It also plays the sounds.

const Sim = preload("res://scripts/sim/battle_sim.gd")
const Bot = preload("res://scripts/sim/bot.gd")
const World = preload("res://scripts/view/battle_world.gd")
const Kit = preload("res://scripts/view/ui_kit.gd")
const CardView = preload("res://scripts/view/card_view.gd")
const Quality = preload("res://scripts/view/quality.gd")
const Bench = preload("res://scripts/view/bench.gd")

const DECK := ["line_infantry", "skirmishers", "militia", "scouts", "heavy_cavalry", "field_gun", "fire", "rally"]

# Layout. The design space is 540 wide; the game fills whatever screen it is given, so the
# height (and on tablets the width) is whatever the display's shape makes it. _layout() works
# out where the banner and the card tray float, clear of any notch or gesture bar. The
# battlefield runs on behind both of them.
const CARD_W := 91.0
const POWDER_H := 24.0
const CARD_X0 := 111.0
const CARD_STEP := 99.5
const TRAY_X := 28.0                # the tray floats: this far in from each side of the column
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
var kit: Kit
var hand_cards: Array = []          # the four CardView nodes, one per hand slot
var _overlay: Control               # draws the result plate above the cards
var _press_slot: int = -1           # the card under the finger when it went down
var _press_at: Vector2 = Vector2.ZERO
var _dragging: bool = false
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
var hud_y: float = 776.0            # top of the card tray
var tray: Rect2 = Rect2(28, 776, 484, 178)
var banner: Rect2 = Rect2(50, 14, 440, 42)     # the plank across the top
var plaque: Rect2 = Rect2(210, 8, 120, 56)     # the clock's plaque in its middle
var _laid_out: bool = false
var art_h: float = 78.0             # height of a card's picture; taller screens get a little more
var card_size: Vector2 = Vector2(91.0, 126.0)
var _bar_lag: Dictionary = {}       # id -> the strength a bar still shows as "just lost"
var _bar_flash: Dictionary = {}     # id -> seconds of white flash left on a bar
var _melee_clock: float = 0.0
var _curtain: float = 1.0           # 1 while the first match loads behind a wood curtain, fading to 0
var _warmed: bool = false
var _fps_frames: int = 0
var _fps_since: int = 0             # real milliseconds
var _fps_last: int = 0
var _fps_worst: float = 0.0
var _fps_text: String = ""
var show_fps: bool = true
var quality: Quality
var bench: Bench
var _hud_hidden: bool = false
var _script_usec: int = 0
var script_ms: float = 0.0          # this screen's and the world's script time per frame, last second


func _ready() -> void:
	kit = Kit.new()
	quality = Quality.new()
	bench = Bench.new()
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED      # the wood grain tiles
	cards = Sim.load_cards()
	if match_seed == 0:
		match_seed = int(Time.get_unix_time_from_system()) % 1000000 + 1
	sim = Sim.new(match_seed, cards, DECK, DECK)
	world = World.new()
	world.sim = sim
	world.local_side = local_side
	add_child(world)
	_setup_audio()
	for i in Sim.HAND_SIZE:
		var card := CardView.new()
		card.kit = kit
		add_child(card)
		hand_cards.append(card)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_overlay.draw.connect(_draw_result)
	add_child(_overlay)
	start_match(match_seed)


func start_match(seed_value: int) -> void:
	match_seed = seed_value
	sim = Sim.new(seed_value, cards, DECK, DECK)
	bot = Bot.new(1 - local_side, seed_value)
	auto_bot = Bot.new(local_side, seed_value + 99) if autoplay else null
	world.reset(sim)
	words.clear()
	for card: CardView in hand_cards:
		card.card_id = ""             # so the new hand is dealt out afresh
	_dragging = false
	_press_slot = -1
	_bar_lag.clear()
	_bar_flash.clear()
	selected = -1
	acc = 0.0
	notice = ""
	if not _warmed:
		# First match only: load and draw one of everything behind the curtain (see _process).
		_warmed = true
		_curtain = 1.0
		var in_play := {}
		for id: String in DECK:
			in_play[id] = cards[id]
			_art(id)
		world.warm_up(in_play)
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
	# The tray: four cards, the Powder trough under them, floating a little clear of the sides
	# and the bottom edge.
	art_h = clampf(78.0 + (screen.y - 960.0) * 0.08, 78.0, 98.0)
	card_size = Vector2(CARD_W, Kit.CARD_HEAD + art_h + Kit.CARD_NAME)
	var tray_h := 13.0 + card_size.y + 8.0 + POWDER_H + 10.0
	tray = Rect2(ox + TRAY_X, screen.y - maxf(bottom, 2.0) - 7.0 - tray_h, 540.0 - TRAY_X * 2.0, tray_h)
	hud_y = tray.position.y
	banner = Rect2(ox + 50.0, top + 14.0, 440.0, 42.0)
	plaque = Rect2(ox + 210.0, top + 8.0, 120.0, 56.0)
	quality.apply(world, get_viewport())
	# The field fits between the banner and the tray; its near edge tucks just under the tray.
	var field_top := plaque.end.y + 12.0
	world.field_rect_design = Rect2(22.0, field_top, screen.x - 44.0, hud_y + 8.0 - field_top)
	world.fit_camera()
	for i in hand_cards.size():
		var home := _card_rect(i)
		(hand_cards[i] as CardView).position = home.position
		(hand_cards[i] as CardView).size = home.size


func _process(delta: float) -> void:
	var began := Time.get_ticks_usec()
	_step(delta)
	_script_usec += Time.get_ticks_usec() - began


func _step(delta: float) -> void:
	_layout()
	_clock += delta
	_count_frames()
	if world.warming():
		_overlay.visible = true
		_overlay.queue_redraw()
		queue_redraw()
		return                         # the battle starts once everything it needs is loaded
	_curtain = maxf(0.0, _curtain - delta * 2.5)
	if bench.running or bench.done:
		# The cost meter is at work (or showing its list): the battle waits.
		bench.tick()
		_overlay.visible = true
		_overlay.queue_redraw()
		queue_redraw()
		return
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
	_sync_hand(delta)
	_overlay.visible = sim.phase == Sim.PHASE_OVER or _curtain > 0.0
	_overlay.queue_redraw()
	_melee_clock -= delta
	if _melee_clock <= 0.0 and sim.phase != Sim.PHASE_OVER:
		for r: Sim.Regiment in sim.regiments:
			if r.in_melee and r.state != Sim.ST_ROUT:
				_sfx("melee", -5.0, 0.5)
				_melee_clock = randf_range(0.7, 1.1)
				break
	for id in _bar_flash.keys():
		_bar_flash[id] = float(_bar_flash[id]) - delta
		if float(_bar_flash[id]) <= 0.0:
			_bar_flash.erase(id)
	queue_redraw()


# ==========================================================================================
# Input
# ==========================================================================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		pointer = event.position
		if pointer_down and _press_slot >= 0 and not _dragging and pointer.distance_to(_press_at) > 12.0:
			# The finger has moved off where it landed: this is a drag, not a tap.
			_dragging = true
			selected = _press_slot
			(hand_cards[selected] as CardView).begin_drag(pointer)
			_sfx("card_select")
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
	if bench.running:
		return
	if bench.done:
		bench.done = false                # the list has been read: back to the battle
		return
	if show_fps and _fps_rect().has_point(p):
		bench.start(self)                 # tap the readout: measure what each part of the picture costs
		return
	_press_slot = _card_at(p)
	_press_at = p


func _on_release(p: Vector2) -> void:
	var pressed_slot := _press_slot
	_press_slot = -1
	if sim.phase == Sim.PHASE_OVER:
		return
	var on_field := _on_field(p)
	if _dragging:
		# A card dragged onto the field is played where it is let go; anywhere else it goes back.
		_dragging = false
		var card: CardView = hand_cards[selected]
		var played := on_field and _try_deploy(selected, to_field(p))
		card.end_drag(played)
		selected = -1
		return
	if pressed_slot >= 0:
		if _card_at(p) == pressed_slot:
			selected = -1 if selected == pressed_slot else pressed_slot      # a tap chooses or puts down
			_sfx("card_select")
		return
	if selected >= 0 and on_field and _try_deploy(selected, to_field(p)):
		selected = -1


## For the cost meter: draws nothing of the HUD and hides the cards, to see what they cost.
func set_hud_hidden(hidden: bool) -> void:
	_hud_hidden = hidden
	for card: CardView in hand_cards:
		card.visible = not hidden


func _fps_rect() -> Rect2:
	return Rect2(ox + 16.0, plaque.end.y - 2.0, 300.0, 34.0)


## Frames a second, and the longest single frame in the last second (a hitch shows there even
## when the average looks fine). Measured in real time, so hit-stop does not distort it.
func _count_frames() -> void:
	var now := Time.get_ticks_msec()
	if _fps_last > 0:
		_fps_worst = maxf(_fps_worst, float(now - _fps_last))
	_fps_last = now
	_fps_frames += 1
	if now - _fps_since >= 1000:
		var fps := _fps_frames * 1000.0 / maxf(1.0, float(now - _fps_since))
		script_ms = (_script_usec + world.script_usec) / 1000.0 / maxf(1.0, float(_fps_frames))
		_script_usec = 0
		world.script_usec = 0
		# Judge the frame rate only while a battle is actually running in front of the player.
		if not world.warming() and _curtain <= 0.0 and sim.phase != Sim.PHASE_OVER and not bench.running and not bench.done:
			quality.report(fps, world, get_viewport())
		_fps_text = "%d FPS   worst %d ms   Q%d   tap to measure" % [int(round(fps)), int(_fps_worst), quality.level]
		_fps_frames = 0
		_fps_since = now
		_fps_worst = 0.0


## Plays a hand slot at a field position if the rules allow, and says why not if they do not.
func _try_deploy(slot: int, where: Vector2) -> bool:
	var why := sim.deploy_error(local_side, slot, where)
	if why != "":
		notice = why
		notice_time = 1.6
		return false
	sim.deploy(local_side, slot, where)
	return true


## True where a tap or a dropped card lands on the battlefield rather than on the HUD.
func _on_field(p: Vector2) -> bool:
	return p.y < hud_y and not banner.grow(6.0).has_point(p) and not plaque.grow(4.0).has_point(p)


## Where the NEXT card is shown, in screen space; new cards are dealt from here.
func _next_rect() -> Rect2:
	return Rect2(ox + 49.0, hud_y + 32.0, 52.0, 54.0)


## Keeps the four card nodes in step with the hand: deals a card in when a slot's card changes,
## tells each whether Powder covers it, and moves the one being dragged.
func _sync_hand(delta: float) -> void:
	var hand: Array = sim.hand(local_side)
	var have: float = sim.powder[local_side]
	for i in hand_cards.size():
		var card: CardView = hand_cards[i]
		if i >= hand.size():
			continue
		var id: String = hand[i]
		if card.card_id != id:
			var fresh := card.card_id == ""
			card.deal(id, cards[id], _art(id), _next_rect(), 0.12 + 0.09 * i if fresh else 0.1)
		card.set_affordable(have + 0.0001 >= float(cards[id]["cost"]))
		card.set_selected(i == selected)
		if _dragging and i == selected:
			card.drag_to(pointer, pointer.y < hud_y, delta)


func _card_at(p: Vector2) -> int:
	for i in Sim.HAND_SIZE:
		if _card_rect(i).has_point(p):
			return i
	return -1


func _card_rect(i: int) -> Rect2:
	return Rect2(Vector2(ox + CARD_X0 + CARD_STEP * i, hud_y + 13.0), card_size)


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
	# Read every sound now: the first volley of a battle is a bad moment to open a file.
	var dir := DirAccess.open(AUDIO_DIR)
	if dir != null:
		for file: String in dir.get_files():
			if file.ends_with(".ogg") or file.ends_with(".ogg.import"):
				_stream(file.get_basename().get_basename() if file.ends_with(".import") else file.get_basename())
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
				if from_structure:
					_sfx("redoubt_gun", -4.0, 0.1)
				else:
					# The layered take has the hard crack of the new cannon over the low body of the old.
					var boom := "cannon"
					for candidate: String in ["cannon_big_layered", "cannon_big"]:
						if _stream(candidate) != null:
							boom = candidate
							break
					_sfx(boom, 0.0, 0.1)
					_buzz(22)
			"canister":
				_sfx("canister", 1.0)
				_buzz(28)
			"hit":
				var amount := float(e["amount"])
				_bar_flash[e["id"]] = 0.12
				if amount >= 130.0:
					_sfx("hit_shot", -1.0, 0.18)
				elif amount >= 45.0:
					_sfx("hit_volley", -4.0, 0.14)
			"struct_hit":
				_bar_flash[e["id"]] = 0.12
				if float(e["amount"]) >= 30.0:
					_sfx("hit_structure", -3.0, 0.22)
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
				_sfx("charge_hit", 0.0, 0.3)
				_buzz(45)
			"repelled":
				_word(pos, "REPELLED", COL_PAPER)
				_sfx("repelled", -2.0, 0.5)
			"order":
				_word(pos, String(cards[e["card"]]["name"]).to_upper(), COL_AMBER)
				_sfx("order")
			"destroyed":
				_word(pos, "DESTROYED", Color("ff8a1f"))
				_sfx("destroyed", 1.0)
				_buzz(130)
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


## A short buzz in the hand for the heavy moments. Does nothing where there is no vibrator.
func _buzz(milliseconds: int) -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(milliseconds)


func _word(pos: Vector2, text: String, colour: Color) -> void:
	# Callouts raised at the same spot in quick succession stack upward instead of piling up.
	var row := 0
	for w: Dictionary in words:
		if float(w["age"]) < 0.7 and Vector2(w["pos"]).distance_to(pos) < 2.2:
			row = maxi(row, int(w["row"]) + 1)
	words.append({"pos": pos, "age": 0.0, "life": 1.1, "text": text, "colour": colour, "row": row})


# ==========================================================================================
# Drawing (everything here is 2D, over the 3D view)
# ==========================================================================================

func _draw() -> void:
	if _hud_hidden:
		return
	var began := Time.get_ticks_usec()
	_draw_all()
	_script_usec += Time.get_ticks_usec() - began


func _draw_all() -> void:
	if selected >= 0:
		_draw_deploy_zone()
	for s: Sim.Structure in sim.structures:
		_draw_structure_bar(s)
	for r: Sim.Regiment in sim.regiments:
		_draw_regiment_bars(r)
	_draw_words()
	_draw_top_bar()
	_draw_hud()
	if show_fps and _fps_text != "":
		var at := Vector2(ox + 30.0, plaque.end.y + 18.0)
		draw_string_outline(kit.font_bold, at, _fps_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.8))
		draw_string(kit.font_bold, at, _fps_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("d8ff8a"))


func _text(pos: Vector2, text: String, size: int, colour: Color, align: int = HORIZONTAL_ALIGNMENT_CENTER, width: float = 200.0, bold: bool = false) -> void:
	kit.text(self, pos, text, size, colour, align, width, bold)


## Bold lettering with a thick dark outline and a drop shadow, legible over grass, smoke and
## troops alike.
func _outlined(pos: Vector2, text: String, size: int, colour: Color, width: float = 320.0, outline: int = 7) -> void:
	kit.outlined(self, pos, text, size, colour, width, outline)


## A rounded box with an optional border and soft shadow; made once per look and reused.
func _box(key: String, fill: Color, radius: float, border: float = 0.0, border_colour: Color = Color.BLACK,
		shadow: float = 0.0, shadow_colour: Color = Color(0, 0, 0, 0.5), shadow_drop: float = 0.0) -> StyleBoxFlat:
	return kit.box(key, fill, radius, border, border_colour, shadow, shadow_colour, shadow_drop)


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
	if _on_field(pointer):
		var at := to_field(pointer)
		var ok := sim.deploy_error(local_side, selected, at) == ""
		var ring := COL_PAPER if ok else Color("ff5a4d")
		var radius := float(def.get("radius", 1.0))
		var pts := PackedVector2Array()
		for k in 33:
			pts.append(to_screen(at + Vector2.from_angle(TAU * k / 32.0) * radius, 0.05))
		draw_polyline(pts, ring, 2.5)
		draw_circle(pointer, 4.0, ring)


## A strength bar that shows the piece just knocked off it: the lost part lingers pale for a
## moment and then drains, so a heavy hit reads as a chunk and a light one as a nibble.
func _strength_bar(id: int, at: Vector2, width: float, height: float, fraction: float, colour: Color) -> void:
	var lag: float = maxf(float(_bar_lag.get(id, fraction)), fraction)
	lag = maxf(fraction, lag - get_process_delta_time() * 0.55)
	_bar_lag[id] = lag
	kit.strength_bar(self, at, width, height, fraction, lag, colour, _bar_flash.has(id))


## A structure's strength, in a frame above it. The enemy's are always shown; your own appear
## once they have been hit.
func _draw_structure_bar(s: Sim.Structure) -> void:
	if s.dead:
		return
	var mine := s.side == local_side
	if mine and s.hp >= s.max_hp - 0.5:
		return
	var w := 60.0 if s.kind == "hq" else 52.0
	var p := to_screen(s.pos, 4.9 if s.kind == "hq" else 2.5) + Vector2(-w * 0.5, -17.0)
	var fraction := s.hp / s.max_hp
	var lag: float = maxf(float(_bar_lag.get(s.id, fraction)), fraction)
	lag = maxf(fraction, lag - get_process_delta_time() * 0.55)
	_bar_lag[s.id] = lag
	var deep := Color("2a66de") if mine else Color("d8243a")
	var hot := Color("7fd6ff") if mine else Color("ffa23c")
	kit.framed_bar(self, p, w, 10.0, fraction, lag, deep, hot, _bar_flash.has(s.id))


func _draw_regiment_bars(r: Sim.Regiment) -> void:
	var tall := 3.5 if r.arm == "cavalry" else 2.6
	var p := to_screen(r.pos, tall)
	var w := 32.0
	var top := p + Vector2(-w * 0.5, -6.0)
	_strength_bar(r.id, top, w, 5.0, r.hp / r.max_hp, team_colour(r.side).lightened(0.18))
	draw_rect(Rect2(top + Vector2(-1.5, 6.5), Vector2(w + 3.0, 5.0)), Color(0.07, 0.05, 0.04))
	draw_rect(Rect2(top + Vector2(0, 7.0), Vector2(w * maxf(r.morale, 0.0) / r.morale_max, 3.0)), COL_BRASS)
	if r.reload > 0.0 and r.def.has("reload") and r.state != Sim.ST_ROUT:
		var frac := clampf(r.reload / float(r.def["reload"]), 0.0, 1.0)
		var c := p + Vector2(w * 0.5 + 9.0, 0.0)
		draw_circle(c, 6.5, Color(0.07, 0.05, 0.04))
		draw_arc(c, 3.8, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - frac), 16, COL_CREAM, 2.5)
	if r.state == Sim.ST_FORMING:
		draw_arc(to_screen(r.pos, 0.6), 18.0, 0.0, TAU * (1.0 - r.form_timer / Sim.SQUARE_FORM_TIME_RELOADING), 24, COL_CREAM, 2.5)


func _draw_words() -> void:
	for e: Dictionary in words:
		var t := float(e["age"]) / float(e["life"])
		# Pops in large, settles, then lifts away as it fades.
		var pop := 1.0 + 0.45 * maxf(0.0, 1.0 - t * 7.0)
		var p := to_screen(e["pos"], 1.6) + Vector2(0, -10.0 - 30.0 * t * t - 25.0 * int(e["row"]))
		_outlined(p, e["text"], int(23.0 * pop), Color(e["colour"], 1.0 - pow(t, 4.0)))


func _draw_top_bar() -> void:
	var enemy := 1 - local_side
	kit.banner(self, banner, plaque)
	var base := banner.position.y + 27.0
	_text(Vector2(banner.position.x + 32.0, base + 1.5), "ENEMY", 15, Color(0, 0, 0, 0.55), HORIZONTAL_ALIGNMENT_LEFT, 120.0, true)
	_text(Vector2(banner.position.x + 32.0, base), "ENEMY", 15, Color("f29080"), HORIZONTAL_ALIGNMENT_LEFT, 120.0, true)
	_text(Vector2(banner.end.x - 32.0, base + 1.5), "YOU", 15, Color(0, 0, 0, 0.55), HORIZONTAL_ALIGNMENT_RIGHT, 120.0, true)
	_text(Vector2(banner.end.x - 32.0, base), "YOU", 15, Color("8ab8ff"), HORIZONTAL_ALIGNMENT_RIGHT, 120.0, true)
	# Batteries taken: an inset slot for each, lit in the taker's colour.
	for i in 2:
		for mine in 2:
			var x := banner.position.x + 96.0 + i * 20.0 if mine == 0 else banner.end.x - 112.0 - (1 - i) * 20.0
			var slot := Rect2(x, banner.position.y + 13.0, 16.0, 16.0)
			var lost := i < (sim.redoubts_lost(enemy) if mine == 0 else sim.redoubts_lost(local_side))
			draw_rect(slot.grow(1.5), COL_BRASS_DARK)
			draw_rect(slot, Color("1a110a"))
			draw_rect(Rect2(slot.position, Vector2(slot.size.x, 3.0)), Color(0, 0, 0, 0.5))
			if lost:
				draw_rect(slot.grow(-2.0), COL_BLUE.lightened(0.25) if mine == 0 else COL_RED.lightened(0.15))
				draw_rect(Rect2(slot.position + Vector2(2, 2), Vector2(slot.size.x - 4.0, 3.0)), Color(1, 1, 1, 0.35))
	var left := int(ceil(sim.time_left()))
	var clock := "%d:%02d" % [left / 60, left % 60]
	var clock_col := COL_CREAM
	if sim.phase == Sim.PHASE_OVERTIME or (left <= 10 and sim.phase == Sim.PHASE_REGULAR):
		clock_col = Color("ff9a3c")
	var mid := plaque.get_center()
	_text(mid + Vector2(0, 13.0), clock, 31, Color(0, 0, 0, 0.6), HORIZONTAL_ALIGNMENT_CENTER, 200.0, true)
	_text(mid + Vector2(0, 11.0), clock, 31, clock_col, HORIZONTAL_ALIGNMENT_CENTER, 200.0, true)
	if sim.phase == Sim.PHASE_OVERTIME:
		_outlined(Vector2(mid.x, plaque.end.y + 26.0), "OVERTIME", 16, Color("ff9a3c"))
	elif sim.double_powder() and sim.phase != Sim.PHASE_OVER:
		_outlined(Vector2(mid.x, plaque.end.y + 26.0), "DOUBLE POWDER", 16, COL_AMBER)
	if notice_time > 0.0:
		var a := clampf(notice_time, 0.0, 1.0)
		var centre := Vector2(screen.x * 0.5, (plaque.end.y + hud_y) * 0.5)
		draw_style_box(_box("notice", Color(0.1, 0.06, 0.03, 0.82), 8.0, 2.0, COL_BRASS_MID), Rect2(centre.x - 210.0, centre.y - 20.0, 420.0, 40.0))
		_text(centre + Vector2(0, 6), notice, 15, Color(COL_CREAM, a), HORIZONTAL_ALIGNMENT_CENTER, 400.0, true)


func _draw_hud() -> void:
	kit.tray(self, tray)
	var hand: Array = sim.hand(local_side)
	var have: float = sim.powder[local_side]
	var column := ox + 75.0                 # the centre line of NEXT and POWDER, left of the cards
	# The next card, small, at the left.
	var next_id := sim.next_card(local_side)
	_text(Vector2(column, hud_y + 24.0), "NEXT", 12, Color(0, 0, 0, 0.5), HORIZONTAL_ALIGNMENT_CENTER, 70.0, true)
	_text(Vector2(column, hud_y + 23.0), "NEXT", 12, COL_CREAM, HORIZONTAL_ALIGNMENT_CENTER, 70.0, true)
	if next_id != "":
		kit.mini_card(self, _next_rect(), _art(next_id), String(cards[next_id]["name"]))
	# The four cards in hand are nodes of their own (card_view.gd) and draw themselves above this.
	var cheapest := 99.0
	for i in hand.size():
		cheapest = minf(cheapest, float(cards[hand[i]]["cost"]))
	# Powder: the count at the left, and a trough of ten charges under the cards.
	var trough := Rect2(ox + CARD_X0 - 4.0, hud_y + 13.0 + card_size.y + 8.0, CARD_STEP * 3.0 + CARD_W + 8.0, POWDER_H)
	var ready := have + 0.0001 >= cheapest
	var spend := int(cards[hand[selected]]["cost"]) if selected >= 0 and selected < hand.size() else 0
	kit.powder_bar(self, trough, have, int(Sim.POWDER_MAX), ready, 0.5 + 0.5 * sin(_clock * 4.0), spend)
	_text(Vector2(column, trough.position.y - 3.0), "POWDER", 11, COL_CREAM, HORIZONTAL_ALIGNMENT_CENTER, 70.0, true)
	_text(Vector2(column, trough.end.y + 0.5), "%d" % int(have), 24, Color(0, 0, 0, 0.6), HORIZONTAL_ALIGNMENT_CENTER, 70.0, true)
	_text(Vector2(column, trough.end.y - 1.5), "%d" % int(have), 24, COL_AMBER if ready else COL_CREAM, HORIZONTAL_ALIGNMENT_CENTER, 70.0, true)


func _art(card_id: String) -> Texture2D:
	if not _card_art.has(card_id):
		var path := CARD_ART_DIR + card_id + ".png"
		_card_art[card_id] = load(path) if ResourceLoader.exists(path) else null
	return _card_art[card_id]


## The result plate, and the curtain at the start. Drawn on the overlay node so that both sit
## above the cards.
func _draw_result() -> void:
	var c: CanvasItem = _overlay
	if bench.running:
		kit.outlined(c, Vector2(screen.x * 0.5, screen.y * 0.5), bench.progress, 18, Kit.CREAM, 520.0, 6)
		return
	if bench.done:
		var rows := bench.lines
		var panel := Rect2(8.0, plaque.end.y + 30.0, screen.x - 16.0, 26.0 + rows.size() * 19.0)
		c.draw_style_box(kit.box("bench_panel", Color(0.08, 0.05, 0.03, 0.93), 8.0, 2.0, Kit.BRASS_MID), panel)
		for i in rows.size():
			c.draw_string(kit.font, panel.position + Vector2(12.0, 26.0 + i * 19.0), rows[i], HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 20.0, 11,
					Kit.CREAM if i != 2 else Kit.AMBER)
		return
	if _curtain > 0.0:
		c.draw_rect(Rect2(Vector2.ZERO, screen), Color(0.13, 0.08, 0.04, _curtain))
		kit.outlined(c, Vector2(screen.x * 0.5, screen.y * 0.45), "DRUMS OF WAR", 34, Color(Kit.CREAM, _curtain), 500.0, 8)
		if sim.phase != Sim.PHASE_OVER:
			return
	c.draw_rect(Rect2(Vector2.ZERO, screen), Color(0.05, 0.03, 0.02, 0.6))
	var cx := screen.x * 0.5
	var cy := screen.y * 0.42
	var text := "DRAW"
	var col := Kit.CREAM
	if sim.winner == local_side:
		text = "VICTORY"
		col = Color("ffd24a")
	elif sim.winner == 1 - local_side:
		text = "DEFEAT"
		col = Color("ff7a66")
	var plate := Rect2(cx - 220.0, cy - 78.0, 440.0, 190.0)
	c.draw_style_box(kit.box("result_edge", Kit.BRASS_DARK, 14.0, 0.0, Color.BLACK, 16.0, Color(0, 0, 0, 0.7), 6.0), plate.grow(5.0))
	c.draw_style_box(kit.box("result_face", Kit.BRASS_MID, 12.0), plate.grow(2.0))
	c.draw_style_box(kit.box("result_wood", Kit.WOOD_DARK, 10.0), plate)
	kit.outlined(c, Vector2(cx, cy), text, 62, col, 440.0, 9)
	var how := "Time ran out"
	if sim.hq(0).dead or sim.hq(1).dead:
		how = "The Colours were captured"
	elif sim.time > Sim.MATCH_TIME + 0.5 and sim.time < Sim.MATCH_TIME + Sim.OVERTIME:
		how = "Decided in overtime"
	kit.text(c, Vector2(cx, cy + 40.0), how, 18, Kit.CREAM, HORIZONTAL_ALIGNMENT_CENTER, 420.0, true)
	kit.text(c, Vector2(cx, cy + 86.0), "Tap to play again", 17, Color(Kit.CREAM, 0.6 + 0.4 * sin(_clock * 3.0)), HORIZONTAL_ALIGNMENT_CENTER, 420.0, true)