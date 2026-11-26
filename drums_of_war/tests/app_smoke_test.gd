extends SceneTree
## Drives the real game: through the menu and the deck builder into a battle, selects and
## deploys cards by tap and by drag, checks a bad placement is refused, lets a full match play
## out on autoplay, then uses the result buttons, the pause button and the way back to the menu.
## Run with --fixed-fps 30. Prints DRUMS_APP_PASS.

const Sim = preload("res://scripts/sim/battle_sim.gd")

var app: Node
var screen: Node
var battle_from: int = -1        # the frame the battle was entered on
var shell_step: int = 0
var frame: int = 0
var failures: int = 0
var unit_slot: int = -1
var drag_slot: int = -1
var before_drag: int = 0
var finished: bool = false
var finished_at: int = 1000000
var paused_at: int = -1


func check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
		print("  FAIL: ", what)


func _initialize() -> void:
	app = load("res://scenes/Main.tscn").instantiate()
	app.match_seed = 4               # the first battle is then seed 5
	app.use_saved_profile = false    # never read or write the player's own file
	root.add_child(app)


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


## The menu and the deck builder, one step every other frame, ending with TO BATTLE.
func _shell() -> void:
	var menu: Control = app.menu
	var deck: Control = app.deck_screen
	screen = app.battle
	shell_step += 1
	match shell_step:
		3:
			check(app.where == "menu" and menu.visible and screen.backdrop, "the game opens on the menu, over an idle field")
			check(screen.sim.regiments.is_empty(), "nobody is on the field behind the menu")
			check(menu.rect_of("battle").size.x > 100.0, "the menu has drawn its buttons")
			tap(menu.rect_of("level2").get_center())
		5:
			check(app.profile.level == 2, "tapping an opponent level chooses it")
			tap(menu.rect_of("fps").get_center())
		7:
			check(app.profile.show_fps and screen.show_fps, "the FPS readout can be switched on from the menu")
			tap(menu.rect_of("deck").get_center())
		9:
			check(app.where == "deck" and deck.visible and not menu.visible, "CHANGE DECK opens the deck builder")
			check(deck.deck.size() == 8 and deck.rect_of("card:zouaves").size.x > 50.0, "which shows the deck and all the cards")
			tap(deck.rect_of("card:zouaves").get_center())
		11:
			check(deck.chosen == "zouaves", "tapping a card chooses it")
			tap(deck.rect_of("toggle").get_center())
		13:
			check(deck.deck.size() == 8 and not deck.deck.has("zouaves"), "a ninth card is refused")
			tap(deck.rect_of("slot:militia").get_center())
		15:
			check(deck.chosen == "militia", "a card in the deck can be chosen from its slot")
			tap(deck.rect_of("toggle").get_center())
		17:
			check(deck.deck.size() == 7 and not deck.deck.has("militia"), "and taken out")
			tap(deck.rect_of("done").get_center())
		19:
			check(app.where == "deck", "a deck of seven cannot be finished")
			tap(deck.rect_of("card:zouaves").get_center())
		21:
			tap(deck.rect_of("toggle").get_center())
		23:
			check(deck.deck.size() == 8 and deck.deck.has("zouaves"), "a card can be added in its place")
			tap(deck.rect_of("done").get_center())
		25:
			check(app.where == "menu" and app.profile.deck.has("zouaves") and not app.profile.deck.has("militia"), "DONE keeps the new deck")
			tap(menu.rect_of("battle").get_center())
		27:
			check(app.where == "battle" and not screen.backdrop and not menu.visible, "TO BATTLE starts a battle")
			check(screen.sim.decks[0].has("zouaves") and screen.bot.level == 2, "with the chosen deck against the chosen opponent")
			check(screen.sim.decks[1].size() == 8, "who has a deck of their own")
			battle_from = frame


func _process(_delta: float) -> bool:
	frame += 1
	if battle_from < 0:
		_shell()
		return false
	frame -= battle_from             # the steps below count from the start of the battle
	var keep_going := _battle()
	frame += battle_from
	return keep_going


func _battle() -> bool:
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
			finished_at = frame
			check(sim.winner >= 0, "the match reaches a result")
	elif frame == finished_at + 2:
		check(app.profile.wins + app.profile.losses + app.profile.draws == 1, "the result goes on the record")
		check(screen._hot.has("rematch") and screen._hot.has("leave"), "the result offers another fight or the menu")
		tap((screen._hot["rematch"] as Rect2).get_center())
	elif frame == finished_at + 4:
		check(screen.sim.phase != Sim.PHASE_OVER and screen.sim.time < 1.0, "FIGHT AGAIN starts a new match")
		tap(screen._pause_rect().get_center())
	elif frame == finished_at + 6:
		check(screen.paused, "the pause button stops the battle")
		paused_at = screen.sim.tick_count
	elif frame == finished_at + 10:
		check(screen.sim.tick_count == paused_at, "nothing moves while it is paused")
		tap((screen._hot["leave"] as Rect2).get_center())
	elif frame == finished_at + 12:
		check(app.where == "menu" and screen.backdrop and app.menu.visible, "LEAVE THE FIELD goes back to the menu")
		check(screen.sim.regiments.is_empty(), "and the field is cleared")
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
