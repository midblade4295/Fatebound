extends Node
## AIController.gd -- timer / state-driven opponent (Red by default).
##
## Every ThinkTimer tick the AI reads the battlefield, picks a Mode and takes
## at most one action:
##   BUILD_UP : fill the trench, counter-picking what the enemy fields
##   DEFEND   : the enemy is coming over the top -- reinforce the trench
##   ASSAULT  : we outnumber them -- (gas, then) blow the whistle
## On top of that it drops a mortar on any tight cluster of enemy soldiers.
##
## It plays by exactly the same rules as the player: the same Supply, the same
## card costs / cooldowns and the same GameManager API (play_card, trigger_whistle).

enum Mode { BUILD_UP, DEFEND, ASSAULT }

@export_enum("Blue:0", "Red:1") var team: int = 1
@export var enabled := true
## Seconds between decisions. Raise it for an easier opponent.
@export var think_interval := 1.0
@export_group("Charging")
## Minimum stationed soldiers before the AI considers a charge.
@export var min_charge_force := 4
## The AI charges when its stationed force >= all enemy soldiers + this margin.
@export var outnumber_margin := 2
## With this little time left and fewer sectors, the AI gambles on a charge.
@export var desperate_time := 30.0
@export_group("Artillery")
## Mortar fires when a cluster's score reaches this. A soldier in the open
## scores 1, a soldier in trench cover only 0.5 (shells are weaker there).
@export var mortar_cluster_size := 4.0
@export var mortar_cluster_radius := 130.0
## Think ticks to wait between releasing gas and blowing the whistle, so the
## AI's own troops arrive as the cloud clears.
@export var gas_to_charge_ticks := 3

var game: GameManager
var mode: Mode = Mode.BUILD_UP

var _enemy_team := GameManager.TEAM_BLUE
var _pending_charge_ticks := -1

@onready var think_timer: Timer = $ThinkTimer


## Called by GameManager._ready().
func setup(p_game: GameManager) -> void:
	game = p_game
	_enemy_team = GameManager.enemy_of(team)
	think_timer.start(think_interval)


func _on_think_timer_timeout() -> void:
	if game == null or game.match_over or not enabled:
		return

	# --- 1. Read the battlefield -------------------------------------------
	var my_units := game.get_units(team)
	var enemy_units := game.get_units(_enemy_team)
	var my_stationed := _count_in_state(my_units, Unit.State.IN_COVER)
	var home := game.get_home_trench(team)
	var intruders := home.count_inside(_enemy_team)
	var attackers := _count_attackers(enemy_units)

	# A charge queued behind a gas cloud goes ahead no matter what.
	if _pending_charge_ticks >= 0:
		_pending_charge_ticks -= 1
		if _pending_charge_ticks < 0:
			game.trigger_whistle(team)
		return

	# Our trench is being gassed: get the men out of it -- forward.
	if my_stationed >= 2 and _is_gassed(home) and game.trigger_whistle(team):
		return

	# --- 2. Pick a mode -----------------------------------------------------
	mode = _choose_mode(my_stationed, enemy_units.size(), intruders, attackers)

	# --- 3. Act (one action per tick) --------------------------------------
	var cluster := _find_best_cluster(enemy_units, my_units)
	if not cluster.is_empty() and game.play_card(team, GameManager.Card.MORTAR, cluster["position"]):
		return
	# A juicy cluster exists but we cannot afford the shell yet: save up,
	# as long as the trench has a basic garrison.
	var saving_for_mortar := (
		not cluster.is_empty()
		and game.get_card_cooldown(team, GameManager.Card.MORTAR) <= 1.0
		and my_stationed >= 3
	)

	match mode:
		Mode.DEFEND:
			_act_defend(intruders)
		Mode.ASSAULT:
			_act_assault(my_stationed, enemy_units.size())
		Mode.BUILD_UP:
			if not saving_for_mortar:
				_act_build_up(my_units, enemy_units)


# ----------------------------------------------------------------------------
# Mode selection
# ----------------------------------------------------------------------------
func _choose_mode(my_stationed: int, enemy_total: int, intruders: int, attackers: int) -> Mode:
	if intruders > 0 or attackers >= 2:
		return Mode.DEFEND
	# Outnumbering the enemy: go over the top.
	if _outnumbers(my_stationed, enemy_total):
		return Mode.ASSAULT
	# Trench packed and nowhere left to put reinforcements: prepare a
	# full-strength push (gas first, see _act_assault).
	if my_stationed >= min_charge_force and not _has_room():
		return Mode.ASSAULT
	# Behind on sectors with the clock running out: all in.
	var behind := game.count_sectors(team) < game.count_sectors(_enemy_team)
	if behind and game.get_time_left() <= desperate_time and my_stationed >= 2:
		return Mode.ASSAULT
	return Mode.BUILD_UP


# ----------------------------------------------------------------------------
# Actions
# ----------------------------------------------------------------------------
## The enemy is charging: raiders win the brawl inside our trench, riflemen
## shoot attackers down while they are still in the open.
func _act_defend(intruders: int) -> void:
	if intruders > 0 and game.play_card(team, GameManager.Card.RAIDERS):
		return
	game.play_card(team, GameManager.Card.RIFLEMEN)


func _act_assault(my_stationed: int, enemy_total: int) -> void:
	if not game.can_whistle(team):
		return
	# Soften a garrisoned trench with gas first, then follow the cloud in.
	var gas_target := _find_gas_target(3)
	if gas_target != null and game.get_card_cooldown(team, GameManager.Card.GAS) <= 0.0:
		if game.play_card(team, GameManager.Card.GAS, gas_target.global_position):
			_pending_charge_ticks = gas_to_charge_ticks
			return
		if gas_target.count_stationed(_enemy_team) >= 4:
			return  # Strong garrison: bank Supply until the gas is affordable.
	if _outnumbers(my_stationed, enemy_total):
		game.trigger_whistle(team)


func _act_build_up(my_units: Array[Unit], enemy_units: Array[Unit]) -> void:
	if not _has_room():
		return  # Nowhere to put more soldiers: bank the Supply.

	# Counter-pick. Raiders beat an entrenched rifle line; riflemen beat
	# raiders, who die quickly while crossing open ground.
	var my_rifles := _count_type(my_units, Unit.Type.RIFLEMAN)
	var my_raiders := _count_type(my_units, Unit.Type.RAIDER)
	var enemy_rifles := _count_type(enemy_units, Unit.Type.RIFLEMAN)
	var enemy_raiders := _count_type(enemy_units, Unit.Type.RAIDER)

	var want_raiders := my_rifles >= 3 and my_raiders < 4 and enemy_rifles >= enemy_raiders
	if want_raiders:
		# Not enough Supply yet? Wait for it rather than spamming riflemen.
		game.play_card(team, GameManager.Card.RAIDERS)
	else:
		game.play_card(team, GameManager.Card.RIFLEMEN)


# ----------------------------------------------------------------------------
# Battlefield reading
# ----------------------------------------------------------------------------
func _outnumbers(my_stationed: int, enemy_total: int) -> bool:
	return my_stationed >= min_charge_force and my_stationed >= enemy_total + outnumber_margin


## Is there still a free trench slot our reinforcements could walk to?
func _has_room() -> bool:
	return game.find_cover_trench(team, game.get_home_trench(team).global_position) != null


func _is_gassed(trench: Trench) -> bool:
	for node in get_tree().get_nodes_in_group("gas_clouds"):
		var cloud := node as GasCloud
		if cloud != null and cloud.is_active() and absf(cloud.global_position.x - trench.global_position.x) < 200.0:
			return true
	return false


func _count_in_state(units: Array[Unit], wanted: Unit.State) -> int:
	var total := 0
	for unit in units:
		if unit.state == wanted:
			total += 1
	return total


func _count_type(units: Array[Unit], wanted: Unit.Type) -> int:
	var total := 0
	for unit in units:
		if unit.unit_type == wanted:
			total += 1
	return total


## Enemy soldiers out of cover who have reached the middle of the field.
func _count_attackers(enemy_units: Array[Unit]) -> int:
	var enemy_dir := GameManager.advance_dir(_enemy_team)
	var total := 0
	for unit in enemy_units:
		if unit.state == Unit.State.IN_COVER:
			continue
		if (unit.global_position.x - 960.0) * enemy_dir > -120.0:
			total += 1
	return total


## Best mortar target: the enemy soldier with the most friends around them.
## Returns {} or {"position": Vector2, "score": float}.
func _find_best_cluster(enemy_units: Array[Unit], my_units: Array[Unit]) -> Dictionary:
	var best := {}
	var best_score := mortar_cluster_size - 0.01
	for center in enemy_units:
		var score := 0.0
		var count := 0
		var sum := Vector2.ZERO
		var drift := Vector2.ZERO
		for other in enemy_units:
			if other.global_position.distance_to(center.global_position) <= mortar_cluster_radius:
				score += 0.5 if other.state == Unit.State.IN_COVER else 1.0
				count += 1
				sum += other.global_position
				drift += other.velocity
		if score <= best_score:
			continue
		# Lead moving targets: the shell takes ~1.6 s to land.
		var aim: Vector2 = sum / count + (drift / count) * 1.6
		# Do not shell our own men.
		var friendly := 0
		for mine in my_units:
			if mine.global_position.distance_to(aim) <= mortar_cluster_radius:
				friendly += 1
		if friendly * 2 >= count:
			continue
		best_score = score
		best = {"position": aim, "score": score}
	return best


## Trench holding at least `min_stationed` enemy soldiers and none of ours.
func _find_gas_target(min_stationed: int) -> Trench:
	var best: Trench = null
	var best_count := min_stationed - 1
	for trench in game.trenches:
		if trench.count_inside(team) > 0:
			continue
		var count := trench.count_stationed(_enemy_team)
		if count > best_count:
			best = trench
			best_count = count
	return best
