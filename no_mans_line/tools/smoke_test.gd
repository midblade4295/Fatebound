extends SceneTree
## Headless smoke test: plays full matches with an AI on BOTH sides at high
## speed, exercises every card + the whistle, and reports the results.
##
##   godot --headless --path . -s tools/smoke_test.gd -- [matches]
##
## Prints "SMOKE TEST PASSED" when every match reaches an end state.

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const AI_SCRIPT := preload("res://scripts/AIController.gd")
const TIME_SCALE := 12.0

var _matches_left := 3
var _game: GameManager
var _stats := {}
var _results: Array[String] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_matches_left = int(args[0])
	Engine.time_scale = TIME_SCALE
		# time_scale also stretches the physics delta, so raise the tick rate to
	# keep every physics step at 1/60 s of game time.
	Engine.physics_ticks_per_second = int(60 * Engine.time_scale)
	Engine.max_physics_steps_per_frame = 64
	_start_match.call_deferred()


func _start_match() -> void:
	_game = MAIN_SCENE.instantiate()
	root.add_child(_game)
	_stats = {"cards": [0, 0, 0, 0], "whistles": [0, 0], "blue_cards": 0, "red_cards": 0, "flips": 0, "captures": [0, 0]}
	for trench in _game.trenches:
		trench.owner_changed.connect(func(_t: Trench, new_owner: int) -> void: _stats["captures"][new_owner] += 1)
	_game.sector_control_changed.connect(func(_o: Array[int]) -> void: _stats["flips"] += 1)
	# Give Blue a second AIController so nobody needs to touch the screen.
	var blue_ai := Node.new()
	blue_ai.set_script(AI_SCRIPT)
	blue_ai.set("team", GameManager.TEAM_BLUE)
	var timer := Timer.new()
	timer.name = "ThinkTimer"
	blue_ai.add_child(timer)
	_game.add_child(blue_ai)
	timer.timeout.connect(Callable(blue_ai, "_on_think_timer_timeout"))
	blue_ai.call("setup", _game)

	_game.card_played.connect(_on_card_played)
	_game.whistle_charge.connect(func(team: int) -> void: _stats["whistles"][team] += 1)
	_game.match_ended.connect(_on_match_ended)


func _on_card_played(team: int, card_id: int) -> void:
	_stats["cards"][card_id] += 1
	_stats["blue_cards" if team == GameManager.TEAM_BLUE else "red_cards"] += 1


func _on_match_ended(winner: int, reason: String) -> void:
	var line := "winner=%d reason='%s' time_left=%.0f blue_hp=%.0f red_hp=%.0f sectors=%s cards[rifle,raider,mortar,gas]=%s whistles=%s blue_cards=%d red_cards=%d sector_flips=%d trench_captures=%s" % [
		winner, reason, _game.get_time_left(), _game.blue_bunker.health, _game.red_bunker.health,
		str(_game.sector_owners), str(_stats["cards"]), str(_stats["whistles"]),
		_stats["blue_cards"], _stats["red_cards"], _stats["flips"], str(_stats["captures"]),
	]
	print("MATCH: ", line)
	_results.append(line)
	_matches_left -= 1
	_game.queue_free()
	if _matches_left > 0:
		_start_match.call_deferred()
	else:
		print("SMOKE TEST PASSED (%d matches)" % _results.size())
		quit(0)
