extends Node2D
## Grey-box battle screen: draws the rules engine's state with plain shapes and turns
## taps and drags into deploy commands. No art assets; everything is drawn in _draw().

const Sim = preload("res://scripts/sim/battle_sim.gd")
const Bot = preload("res://scripts/sim/bot.gd")

const DECK := ["line_infantry", "skirmishers", "militia", "scouts", "heavy_cavalry", "field_gun", "fire", "rally"]

# Layout, in the 540 x 960 design space.
const S := 24.0                                  # pixels per pace
const FIELD_POS := Vector2(54.0, 44.0)           # field is 432 x 768
const FIELD_SIZE := Vector2(Sim.FIELD_W * 24.0, Sim.FIELD_H * 24.0)
const HUD_Y := 816.0
const CARD_SIZE := Vector2(104.0, 96.0)
const CARD_X0 := 84.0
const CARD_STEP := 112.0

const COL_BG := Color("16202b")
const COL_GRASS := Color("6cc24a")
const COL_GRASS_DARK := Color("5fb141")
const COL_CREEK := Color("3fa9f5")
const COL_FORD := Color("8fd0f7")
const COL_BRIDGE := Color("b9b2a3")
const COL_BLUE := Color("2456c9")
const COL_RED := Color("c81e3a")
const COL_INK := Color("15233a")
const COL_PAPER := Color("f6f2e6")
const COL_BRASS := Color("f2b632")
const COL_AMBER := Color("ffb000")
const COL_SMOKE := Color("fff8ec")

var cards: Dictionary
var sim: Sim
var bot: Bot
var auto_bot: Bot = null            # set by autoplay: a bot also plays the local side
var local_side: int = 0
var autoplay: bool = false
var match_seed: int = 0
var acc: float = 0.0

var selected: int = -1
var pointer: Vector2 = Vector2.ZERO
var pointer_down: bool = false
var notice: String = ""
var notice_time: float = 0.0

var fx: Array = []                  # short-lived effects: smoke, flashes, shot lines, floating words
var shown_pos: Dictionary = {}      # regiment id -> smoothed field position
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font
	cards = Sim.load_cards()
	if match_seed == 0:
		match_seed = int(Time.get_unix_time_from_system()) % 1000000 + 1
	start_match(match_seed)


func start_match(seed_value: int) -> void:
	match_seed = seed_value
	sim = Sim.new(seed_value, cards, DECK, DECK)
	bot = Bot.new(1 - local_side, seed_value)
	auto_bot = Bot.new(local_side, seed_value + 99) if autoplay else null
	fx.clear()
	shown_pos.clear()
	selected = -1
	acc = 0.0
	notice = ""


func _process(delta: float) -> void:
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
	for e: Dictionary in fx:
		e["age"] = float(e["age"]) + delta
	fx = fx.filter(func(e: Dictionary) -> bool: return float(e["age"]) < float(e["life"]))
	if notice_time > 0.0:
		notice_time -= delta
	var k := 1.0 - exp(-18.0 * delta)
	var seen := {}
	for r: Sim.Regiment in sim.regiments:
		seen[r.id] = true
		var p: Vector2 = shown_pos.get(r.id, r.pos)
		shown_pos[r.id] = p.lerp(r.pos, k)
	for id in shown_pos.keys():
		if not seen.has(id):
			shown_pos.erase(id)
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


func _on_release(p: Vector2) -> void:
	if selected < 0 or sim.phase == Sim.PHASE_OVER:
		return
	if not Rect2(FIELD_POS, FIELD_SIZE).has_point(p):
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
	return Rect2(Vector2(CARD_X0 + CARD_STEP * i, HUD_Y + 8.0), CARD_SIZE)


func to_screen(p: Vector2) -> Vector2:
	var y := Sim.FIELD_H - p.y if local_side == 0 else p.y
	var x := p.x if local_side == 0 else Sim.FIELD_W - p.x
	return FIELD_POS + Vector2(x, y) * S


func to_field(p: Vector2) -> Vector2:
	var q := (p - FIELD_POS) / S
	if local_side == 0:
		return Vector2(q.x, Sim.FIELD_H - q.y)
	return Vector2(Sim.FIELD_W - q.x, q.y)


func dir_to_screen(d: Vector2) -> Vector2:
	return Vector2(d.x, -d.y) if local_side == 0 else Vector2(-d.x, d.y)


func team_colour(side: int) -> Color:
	return COL_BLUE if side == local_side else COL_RED


# ==========================================================================================
# Effects from rule events
# ==========================================================================================

func _take_events() -> void:
	for e: Dictionary in sim.events:
		var pos: Vector2 = e.get("pos", Vector2.ZERO)
		match e["type"]:
			"volley":
				var dir: Vector2 = (Vector2(e["to"]) - pos).normalized()
				var side_dir := Vector2(-dir.y, dir.x)
				var men := int(e.get("men", 4))
				for i in mini(men, 6):
					var off := side_dir * ((i - (mini(men, 6) - 1) * 0.5) * 0.4) + dir * 0.6
					_puff(pos + off, 0.34, 2.6)
				fx.append({"kind": "flash", "pos": pos + dir * 0.5, "age": 0.0, "life": 0.12, "r": 0.5})
			"cannon", "canister":
				var to: Vector2 = e["to"]
				var d2: Vector2 = (to - pos).normalized()
				for i in 4:
					_puff(pos + d2 * (0.6 + 0.3 * i), 0.5 - 0.05 * i, 3.2)
				fx.append({"kind": "flash", "pos": pos + d2 * 0.6, "age": 0.0, "life": 0.15, "r": 0.8})
				fx.append({"kind": "shot", "pos": pos, "to": to, "age": 0.0, "life": 0.22, "wide": e["type"] == "canister"})
			"rout":
				_word(pos, "ROUT!", Color("ffe14d"))
			"rally":
				_word(pos, "RALLIED", COL_PAPER)
			"square":
				_word(pos, "SQUARE", COL_PAPER)
			"charge":
				_word(pos, "CHARGE!", Color("ff8a1f"))
			"repelled":
				_word(pos, "REPELLED", COL_PAPER)
			"order":
				fx.append({"kind": "ring", "pos": pos, "age": 0.0, "life": 0.5, "r": float(e["radius"])})
				_word(pos, String(cards[e["card"]]["name"]).to_upper(), COL_AMBER)
			"destroyed":
				for i in 8:
					_puff(pos + Vector2(cos(i * 0.8), sin(i * 0.8)) * 0.8, 0.7, 3.5)
				_word(pos, "DESTROYED", Color("ff8a1f"))
			"overtime":
				notice = "OVERTIME: first structure to fall decides it"
				notice_time = 3.0
	sim.events.clear()


func _puff(pos: Vector2, r: float, life: float) -> void:
	if fx.size() < 260:
		fx.append({"kind": "smoke", "pos": pos, "age": 0.0, "life": life, "r": r})


func _word(pos: Vector2, text: String, colour: Color) -> void:
	fx.append({"kind": "word", "pos": pos, "age": 0.0, "life": 1.1, "text": text, "colour": colour})


# ==========================================================================================
# Drawing
# ==========================================================================================

func _draw() -> void:
	draw_rect(Rect2(0, 0, 540, 960), COL_BG)
	_draw_field()
	if selected >= 0:
		_draw_deploy_zone()
	for s: Sim.Structure in sim.structures:
		_draw_structure(s)
	for r: Sim.Regiment in sim.regiments:
		_draw_regiment(r)
	_draw_fx()
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


func _draw_field() -> void:
	draw_rect(Rect2(FIELD_POS, FIELD_SIZE), COL_GRASS)
	# Mown stripes, so movement reads against the grass.
	for i in range(0, int(Sim.FIELD_H), 2):
		draw_rect(Rect2(FIELD_POS + Vector2(0, i * S), Vector2(FIELD_SIZE.x, S)), COL_GRASS_DARK)
	var creek_top := to_screen(Vector2(0, Sim.CREEK_Y1 if local_side == 0 else Sim.CREEK_Y0)).y
	var creek_h := (Sim.CREEK_Y1 - Sim.CREEK_Y0) * S
	draw_rect(Rect2(FIELD_POS.x, creek_top, FIELD_SIZE.x, creek_h), COL_CREEK)
	for c: Dictionary in Sim.CROSSINGS:
		var cx := to_screen(Vector2(float(c["x"]), 0)).x
		var half := float(c["half"]) * S
		if bool(c["ford"]):
			draw_rect(Rect2(cx - half, creek_top, half * 2.0, creek_h), COL_FORD)
			for k in 6:
				draw_circle(Vector2(cx - half + 8.0 + k * 11.0, creek_top + 12.0 + (k % 2) * 22.0), 3.0, COL_PAPER)
		else:
			draw_rect(Rect2(cx - half, creek_top - 6.0, half * 2.0, creek_h + 12.0), COL_BRIDGE)
			draw_rect(Rect2(cx - half, creek_top - 6.0, 5.0, creek_h + 12.0), COL_INK.lightened(0.45))
			draw_rect(Rect2(cx + half - 5.0, creek_top - 6.0, 5.0, creek_h + 12.0), COL_INK.lightened(0.45))
	draw_rect(Rect2(FIELD_POS, FIELD_SIZE), COL_INK, false, 2.0)


func _draw_deploy_zone() -> void:
	var def: Dictionary = cards[sim.hand(local_side)[selected]]
	var tint := Color(1, 1, 1, 0.16)
	if def["type"] == "order":
		draw_rect(Rect2(FIELD_POS, FIELD_SIZE), tint)
	else:
		for flank in 2:
			var x0 := flank * Sim.FIELD_W * 0.5
			var depth := sim.deploy_depth(local_side, x0 + 1.0)
			var a := to_screen(Sim.from_local(local_side, Vector2(x0, 0.0)))
			var b := to_screen(Sim.from_local(local_side, Vector2(x0 + Sim.FIELD_W * 0.5, depth)))
			draw_rect(Rect2(a, b - a).abs(), tint)
	if Rect2(FIELD_POS, FIELD_SIZE).has_point(pointer):
		var ok := sim.deploy_error(local_side, selected, to_field(pointer)) == ""
		var ring := COL_PAPER if ok else Color("ff5a4d")
		var radius := float(def.get("radius", 1.0)) * S
		draw_arc(pointer, radius, 0.0, TAU, 40, ring, 2.5)
		draw_circle(pointer, 4.0, ring)


func _draw_structure(s: Sim.Structure) -> void:
	var p := to_screen(s.pos)
	var col := team_colour(s.side)
	if s.dead:
		draw_circle(p, s.radius * S * 0.8, Color(0.2, 0.2, 0.2, 0.55))
		_text(p + Vector2(0, 5), "RUINS", 12, COL_PAPER)
		return
	if s.kind == "hq":
		var half := Vector2(s.radius * S, s.radius * S * 0.8)
		draw_rect(Rect2(p - half, half * 2.0), Color("c9a57a"))
		draw_colored_polygon(PackedVector2Array([p + Vector2(-half.x - 5, -half.y + 14), p + Vector2(0, -half.y - 18), p + Vector2(half.x + 5, -half.y + 14)]), col)
		draw_rect(Rect2(p - half, half * 2.0), COL_INK, false, 2.0)
		draw_line(p + Vector2(0, -half.y - 18), p + Vector2(0, -half.y - 40), COL_INK, 2.0)
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -half.y - 40), p + Vector2(18, -half.y - 34), p + Vector2(0, -half.y - 28)]), col)
	else:
		draw_circle(p, s.radius * S, Color("a8834f"))
		draw_arc(p, s.radius * S, 0.0, TAU, 32, COL_INK, 2.0)
		draw_rect(Rect2(p + Vector2(-14, -14), Vector2(28, 12)), col)
		var aim := dir_to_screen(Vector2(0, Sim.fwd(s.side)))
		draw_line(p, p + aim * 20.0, COL_BRASS, 7.0)
		draw_circle(p, 6.0, COL_INK)
	var w := 46.0
	var bar := p + Vector2(-w * 0.5, s.radius * S + 6.0)
	draw_rect(Rect2(bar, Vector2(w, 6)), COL_INK)
	draw_rect(Rect2(bar + Vector2(1, 1), Vector2((w - 2) * s.hp / s.max_hp, 4)), col.lightened(0.25))


func _formation_offsets(r: Sim.Regiment) -> Array:
	var out: Array = []
	var n := maxi(r.men, 1)
	var sp := 10.0
	if r.arm == "cavalry":
		for i in n:
			out.append(Vector2((i - (n - 1) * 0.5) * 15.0, 0.0))
	elif r.formation == "rout":
		for i in n:
			out.append(Vector2(sin(i * 12.99 + r.id) * 12.0, cos(i * 78.23 + r.id * 2.0) * 12.0))
	elif r.formation == "square":
		for i in n:
			var v := Vector2.from_angle(TAU * i / n + PI * 0.25)
			out.append(v / maxf(absf(v.x), absf(v.y)) * 10.0)
	elif bool(r.def.get("loose", false)):
		for i in n:
			out.append(Vector2((i - (n - 1) * 0.5) * 16.0, (i % 2) * 9.0))
	elif r.formation == "column":
		for i in n:
			out.append(Vector2((i % 2 - 0.5) * sp, (i / 2) * sp - (n / 4.0) * sp))
	else:
		var cols := int(ceil(n / 2.0))
		for i in n:
			var row := i / cols
			var c := i % cols
			out.append(Vector2((c - (cols - 1) * 0.5) * sp, row * sp))
	return out


func _draw_regiment(r: Sim.Regiment) -> void:
	var p := to_screen(shown_pos.get(r.id, r.pos))
	var col := team_colour(r.side)
	if r.state == Sim.ST_ROUT:
		col = col.lerp(Color.WHITE, 0.55)
	var f := dir_to_screen(r.facing)
	draw_set_transform(p, f.angle() + PI * 0.5, Vector2.ONE)
	if r.arm == "artillery":
		draw_circle(Vector2(-9, 2), 6.0, COL_INK)
		draw_circle(Vector2(9, 2), 6.0, COL_INK)
		draw_rect(Rect2(-4, -18, 8, 24), COL_BRASS)
		draw_rect(Rect2(-4, -18, 8, 24), COL_INK, false, 1.5)
		for i in r.men:
			draw_rect(Rect2(-13.0 + i * 10.0, 12, 7, 7), col)
			draw_rect(Rect2(-13.0 + i * 10.0, 12, 7, 7), COL_INK, false, 1.0)
	else:
		for o: Vector2 in _formation_offsets(r):
			if r.arm == "cavalry":
				var tri := PackedVector2Array([o + Vector2(0, -11), o + Vector2(6.5, 8), o + Vector2(-6.5, 8)])
				draw_colored_polygon(tri, col)
				draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), COL_INK, 1.5)
			else:
				draw_rect(Rect2(o - Vector2(4, 4), Vector2(8, 8)), col)
				draw_rect(Rect2(o - Vector2(4, 4), Vector2(8, 8)), COL_INK, false, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Strength and nerve bars, and a pip while reloading.
	var w := 30.0
	var top := p + Vector2(-w * 0.5, -30.0)
	draw_rect(Rect2(top, Vector2(w, 9)), COL_INK)
	draw_rect(Rect2(top + Vector2(1, 1), Vector2((w - 2) * r.hp / r.max_hp, 3)), Color("7be36b"))
	draw_rect(Rect2(top + Vector2(1, 5), Vector2((w - 2) * maxf(r.morale, 0.0) / r.morale_max, 3)), COL_BRASS)
	if r.reload > 0.0 and r.def.has("reload") and r.state != Sim.ST_ROUT:
		var frac := clampf(r.reload / float(r.def["reload"]), 0.0, 1.0)
		draw_arc(p + Vector2(w * 0.5 + 7.0, -26.0), 4.5, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - frac), 16, COL_PAPER, 2.5)
	if r.state == Sim.ST_FORMING:
		draw_arc(p, 17.0, 0.0, TAU * (1.0 - r.form_timer / Sim.SQUARE_FORM_TIME_RELOADING), 24, COL_PAPER, 2.0)


func _draw_fx() -> void:
	for e: Dictionary in fx:
		var t := float(e["age"]) / float(e["life"])
		var p := to_screen(e["pos"])
		match e["kind"]:
			"smoke":
				var r := float(e["r"]) * S * (0.7 + 0.9 * t)
				draw_circle(p + Vector2(8.0 * t, -10.0 * t), r, Color(COL_SMOKE, 0.75 * (1.0 - t)))
			"flash":
				draw_circle(p, float(e["r"]) * S * (1.0 - 0.5 * t), Color(1.0, 0.54, 0.12, 1.0 - t))
			"shot":
				draw_line(p, to_screen(e["to"]), Color(1, 1, 1, 0.8 * (1.0 - t)), 6.0 if e["wide"] else 2.5)
			"ring":
				draw_arc(p, float(e["r"]) * S * (0.6 + 0.4 * t), 0.0, TAU, 48, Color(COL_AMBER, 1.0 - t), 3.0)
			"word":
				var col: Color = e["colour"]
				_text(p + Vector2(0, -34.0 - 22.0 * t) + Vector2(1, 1), e["text"], 15, Color(0, 0, 0, 0.6 * (1.0 - t)))
				_text(p + Vector2(0, -34.0 - 22.0 * t), e["text"], 15, Color(col, 1.0 - t * t))


func _draw_top_bar() -> void:
	var enemy := 1 - local_side
	_text(Vector2(16, 30), "ENEMY", 16, COL_RED.lightened(0.3), HORIZONTAL_ALIGNMENT_LEFT)
	_text(Vector2(524, 30), "YOU", 16, COL_BLUE.lightened(0.4), HORIZONTAL_ALIGNMENT_RIGHT)
	for i in 2:
		var lost_enemy := i < sim.redoubts_lost(enemy)
		var lost_mine := i < sim.redoubts_lost(local_side)
		draw_rect(Rect2(86 + i * 20, 16, 14, 14), COL_BLUE.lightened(0.3) if lost_enemy else Color(1, 1, 1, 0.18))
		draw_rect(Rect2(440 - 20 + i * 20 - 14, 16, 14, 14), COL_RED.lightened(0.2) if lost_mine else Color(1, 1, 1, 0.18))
	var left := int(ceil(sim.time_left()))
	var clock := "%d:%02d" % [left / 60, left % 60]
	var clock_col := COL_PAPER
	if sim.phase == Sim.PHASE_OVERTIME:
		clock_col = Color("ff8a1f")
	_text(Vector2(270, 32), clock, 24, clock_col)
	if sim.phase == Sim.PHASE_OVERTIME:
		_text(Vector2(270, 60), "OVERTIME", 13, Color("ff8a1f"))
	elif sim.double_powder():
		_text(Vector2(270, 60), "DOUBLE POWDER", 13, COL_AMBER)
	if notice_time > 0.0:
		var a := clampf(notice_time, 0.0, 1.0)
		draw_rect(Rect2(70, 392, 400, 34), Color(0, 0, 0, 0.6 * a))
		_text(Vector2(270, 415), notice, 15, Color(COL_PAPER, a), HORIZONTAL_ALIGNMENT_CENTER, 400.0)


func _draw_hud() -> void:
	draw_rect(Rect2(0, HUD_Y, 540, 960 - HUD_Y), COL_INK)
	var hand: Array = sim.hand(local_side)
	var have: float = sim.powder[local_side]
	# Next card
	var next_id := sim.next_card(local_side)
	draw_rect(Rect2(14, HUD_Y + 30, 58, 62), Color(1, 1, 1, 0.12))
	_text(Vector2(43, HUD_Y + 24), "NEXT", 11, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_CENTER, 58.0)
	if next_id != "":
		_draw_card_words(Vector2(43, HUD_Y + 56), String(cards[next_id]["name"]), 10, Color(1, 1, 1, 0.75), 56.0)
	for i in hand.size():
		var def: Dictionary = cards[hand[i]]
		var rect := _card_rect(i)
		var can_pay := have + 0.0001 >= float(def["cost"])
		if i == selected:
			rect.position.y -= 10.0
			draw_rect(rect.grow(4.0), COL_AMBER)
		draw_rect(rect, COL_PAPER if can_pay else Color("9a9a94"))
		var band := COL_BLUE if def["type"] == "unit" else Color("7a4bb5")
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 22)), band)
		var kind := "ORDER" if def["type"] == "order" else String(def["arm"]).to_upper()
		_text(rect.position + Vector2(rect.size.x * 0.5 + 8.0, 16), kind, 11, COL_PAPER, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 20.0)
		_draw_card_words(rect.position + Vector2(rect.size.x * 0.5, 50), String(def["name"]), 15, COL_INK, rect.size.x - 8.0)
		if def["type"] == "unit":
			_text(rect.position + Vector2(rect.size.x * 0.5, 88), "%d men" % int(def["men"]), 11, COL_INK.lightened(0.3), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
		draw_circle(rect.position + Vector2(13, 12), 13.0, COL_AMBER)
		draw_arc(rect.position + Vector2(13, 12), 13.0, 0.0, TAU, 24, COL_INK, 2.0)
		_text(rect.position + Vector2(13, 18), str(int(def["cost"])), 17, COL_INK, HORIZONTAL_ALIGNMENT_CENTER, 26.0)
	# Powder
	var x0 := CARD_X0
	var seg := 44.0
	var y := HUD_Y + 116.0
	for i in int(Sim.POWDER_MAX):
		var cell := Rect2(x0 + i * seg, y, seg - 4.0, 18)
		draw_rect(cell, Color(1, 1, 1, 0.12))
		var fill := clampf(have - i, 0.0, 1.0)
		if fill > 0.0:
			draw_rect(Rect2(cell.position, Vector2(cell.size.x * fill, cell.size.y)), COL_AMBER if fill >= 1.0 else COL_AMBER.darkened(0.35))
	_text(Vector2(43, y + 15), "%d" % int(have), 20, COL_AMBER, HORIZONTAL_ALIGNMENT_CENTER, 58.0)
	_text(Vector2(43, y - 4), "POWDER", 10, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_CENTER, 58.0)


func _draw_card_words(centre: Vector2, name: String, size: int, colour: Color, width: float) -> void:
	var words := name.split(" ")
	var y := centre.y - (words.size() - 1) * (size + 2) * 0.5
	for w: String in words:
		_text(Vector2(centre.x, y), w, size, colour, HORIZONTAL_ALIGNMENT_CENTER, width)
		y += size + 2


func _draw_result() -> void:
	draw_rect(Rect2(0, 0, 540, 960), Color(0, 0, 0, 0.55))
	var text := "DRAW"
	var col := COL_PAPER
	if sim.winner == local_side:
		text = "VICTORY"
		col = COL_AMBER
	elif sim.winner == 1 - local_side:
		text = "DEFEAT"
		col = Color("ff6a5a")
	_text(Vector2(270, 420), text, 64, col, HORIZONTAL_ALIGNMENT_CENTER, 520.0)
	var how := "Time ran out"
	if sim.hq(0).dead or sim.hq(1).dead:
		how = "The Colours were captured"
	elif sim.time > Sim.MATCH_TIME + 0.5 and sim.time < Sim.MATCH_TIME + Sim.OVERTIME:
		how = "Decided in overtime"
	_text(Vector2(270, 462), how, 18, COL_PAPER, HORIZONTAL_ALIGNMENT_CENTER, 520.0)
	_text(Vector2(270, 520), "Tap to play again", 18, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 520.0)
