extends SceneTree
## Drives the real battle screen: selects a card with a click, deploys it with a second click,
## checks a bad placement is refused, then lets a full match play out on autoplay.
## Run with --fixed-fps 30. Prints DRUMS_APP_PASS.

const Sim = preload("res://scripts/sim/battle_sim.gd")

var screen: Node
var frame: int = 0
var failures: int = 0
var unit_slot: int = -1
var drag_slot: int = -1
var before_drag: int = 0
var finished: bool = false


func check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
		print("  FAIL: ", what)


func _initialize() -> void:
	screen = load("res://scenes/Main.tscn").instantiate()
	screen.match_seed = 5
	root.add_child(screen)


func click(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	root.push_input(ev, true)


func move(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	root.push_input(ev, true)


func tap(pos: Vector2) -> void:
	click(pos, true)
	click(pos, false)


func _process(_delta: float) -> bool:
	frame += 1
	var sim: Sim = screen.sim
	if frame == 5:
		check(sim != null and sim.structures.size() == 6, "a match starts with six structures")
		var hand: Array = sim.hand(0)
		for i in 4:
			if screen.cards[hand[i]]["type"] == "unit":
				unit_slot = i
				break
		check(unit_slot >= 0, "a unit card is in hand")
		sim.powder[0] = 10.0
		tap(screen._card_rect(unit_slot).get_center())
	elif frame == 7:
		check(screen.selected == unit_slot, "tapping a card selects it")
		tap(screen.to_screen(Vector2(9, 24)))       # the enemy half: must be refused
	elif frame == 9:
		check(screen.selected == unit_slot and screen.notice != "", "a bad placement is refused with a reason")
		var mine := 0
		for r: Sim.Regiment in sim.regiments:
			if r.side == 0:
				mine += 1
		check(mine == 0, "nothing was deployed by the refused tap")
		tap(screen.to_screen(Vector2(9, 10)))
	elif frame == 11:
		var mine := 0
		for r: Sim.Regiment in sim.regiments:
			if r.side == 0:
				mine += 1
		check(mine == 1, "tapping your own half deploys the regiment")
		check(screen.selected == -1, "the card is put down after deploying")
		check(absf(screen.to_field(screen.to_screen(Vector2(4.5, 20.25))).y - 20.25) < 0.001, "screen and field coordinates round-trip")
		# Now by dragging: press a card, move out onto your half, let go.
		sim.powder[0] = 10.0
		var hand2: Array = sim.hand(0)
		drag_slot = -1
		for i in 4:
			if screen.cards[hand2[i]]["type"] == "unit":
				drag_slot = i
				break
		check(drag_slot >= 0, "a unit card is in hand for the drag")
		before_drag = 0
		for r: Sim.Regiment in sim.regiments:
			if r.side == 0:
				before_drag += 1
		click(screen._card_rect(drag_slot).get_center(), true)
	elif frame == 12:
		move(screen._card_rect(drag_slot).get_center() + Vector2(0, -60))
	elif frame == 13:
		check(screen._dragging and screen.hand_cards[drag_slot].dragging, "moving off a pressed card starts a drag")
		move(screen.to_screen(Vector2(5, 9)))
	elif frame == 15:
		check(screen.hand_cards[drag_slot].shrink < 0.99, "the dragged card shrinks over the field")
		click(screen.to_screen(Vector2(5, 9)), false)
	elif frame == 17:
		var after_drag := 0
		for r: Sim.Regiment in sim.regiments:
			if r.side == 0:
				after_drag += 1
		check(after_drag == before_drag + 1, "letting a dragged card go on your half deploys it")
		check(not screen._dragging and screen.selected == -1, "the drag ends and nothing stays chosen")
	elif frame == 24:
		check(screen.hand_cards[drag_slot].card_id == sim.hand(0)[drag_slot], "the next card is dealt into the emptied slot")
		check(screen.hand_cards[drag_slot].fade > 0.5, "and it has slid into view")
		# Hand the local side to a bot and let the match run to its end.
		screen.autoplay = true
		screen.start_match(11)
	elif frame > 24 and not finished:
		# Run the rules faster than real time; the screen still draws every frame.
		for i in 12:
			if sim.phase != Sim.PHASE_OVER:
				screen.bot.tick(sim)
				screen.auto_bot.tick(sim)
				sim.tick()
				screen._take_events()
		if sim.phase == Sim.PHASE_OVER:
			finished = true
			check(sim.winner >= 0, "the match reaches a result")
			tap(screen.screen * 0.5)
	elif finished:
		check(screen.sim.phase != Sim.PHASE_OVER and screen.sim.time < 1.0, "tapping the result starts a new match")
		print("frames: %d, failures: %d" % [frame, failures])
		if failures == 0:
			print("DRUMS_APP_PASS")
		quit(0 if failures == 0 else 1)
		return true
	if frame > 4000:
		print("  FAIL: the match never ended")
		quit(1)
		return true
	return false
