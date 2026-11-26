extends Node
## AIController.gd -- timer / state-driven opponent (Red by default).
##
## Every ThinkTimer tick the AI reads the battlefield, picks a Mode and takes
## at most one action:
##   BUILD_UP : garrison the trench up to `garrison_target`, then bank Supply
##   DEFEND   : the enemy is coming over the top -- reinforce the trench
##   ASSAULT  : set up a push -- barrage the objective, then blow the whistle
## On top of that it drops a mortar on any tight group of enemies caught in the
## open, which pins a charge in No Man's Land.
##
## It plays by exactly the same rules as the player: the same Supply, the same
## card costs / cooldowns and the same GameManager API (play_card, trigger_whistle).

enum Mode { BUILD_UP, DEFEND, ASSAULT }

@export_enum("Blue:0", "Red:1") var team: int = 1
@export var enabled := true
## Seconds between decisions. Raise it for an easier opponent.
@export var think_interval := 1.0
@export_group("Garrison")
## The AI stops buying troops at this many living soldiers and saves Supply
## for mortars and gas instead.
@export var garrison_target := 6
@export_group("Charging")
## No advances during the first seconds of a match, so the player can settle in.
@export var opening_truce := 15.0
## Minimum stationed soldiers before the AI considers a charge.
@export var min_charge_force := 4
## Without a barrage the AI only charges when its stationed force >= all
## enemy soldiers + this margin.
@export var outnumber_margin := 2
## With a barrage it accepts being outnumbered by this many defenders.
@export var barrage_deficit := 2
## With this little time left and fewer sectors, the AI gambles on a charge.
@export var desperate_time := 30.0
@export_group("Artillery")
## Enemies in the open, close together, needed for a defensive mortar.
@export var mortar_cluster_size := 3
@export var mortar_cluster_radius := 75.0
## Defenders in a trench needed before gas is preferred over a mortar.
@export var gas_garrison := 4
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
	var intruders := _count_intruders()
	var attackers := _count_attackers(enemy_units)

	# A charge queued behind a gas cloud goes ahead no matter what.
	if _pending_charge_ticks >= 0:
		_pending_charge_ticks -= 1
		if _pending_charge_ticks < 0:
			game.trigger_whistle(team)
		return

	# Our trench is being gassed: get the men out of it -- forward.
	if _garrison_is_gassed() and game.trigger_whistle(team):
		return

	# --- 2. Pick a mode -----------------------------------------------------
	mode = _choose_mode(my_stationed, enemy_units.size(), intruders, attackers)

	# --- 3. Act (one action per tick) --------------------------------------
	# Enemies bunched up in the open: a shell pins them where our rifles can
	# reach them. This is the answer to an enemy Whistle Charge.
	var cluster := _find_exposed_cluster(enemy_units, my_units)
	if not cluster.is_empty() and game.play_card(team, GameManager.Card.MORTAR, cluster["position"]):
		return

	match mode:
		Mode.DEFEND:
			_act_defend(intruders)
		Mode.ASSAULT:
			_act_assault(my_stationed, enemy_units.size())
		Mode.BUILD_UP:
			_act_build_up(my_units, enemy_units)


# ----------------------------------------------------------------------------
# Mode selection
# ----------------------------------------------------------------------------
func _choose_mode(my_stationed: int, enemy_total: int, intruders: int, attackers: int) -> Mode:
	if intruders > 0 or attackers >= 2:
		return Mode.DEFEND
	var elapsed := game.match_length - game.get_time_left()
	# Undefended ground ahead (the neutral middle trench, or one the enemy
	# abandoned): walk in and take it.
	if elapsed >= opening_truce and my_stationed >= 3 and _objective_is_undefended():
		return Mode.ASSAULT
	if elapsed >= opening_truce and my_stationed >= min_charge_force:
		# Clearly outnumbering the enemy: go over the top.
		if _outnumbers(my_stationed, enemy_total):
			return Mode.ASSAULT
		# Otherwise a push needs a barrage to pin the defenders first.
		if _barrage_ready() and my_stationed + barrage_deficit >= _objective_garrison():
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


## A push in three flavours, best first:
##   gas    -> wait for the cloud to thin -> whistle
##   mortar -> whistle at once (the shell lands while the men are crossing and
##             the defenders stay pinned as they arrive)
##   whistle alone, only with clear numbers
func _act_assault(my_stationed: int, enemy_total: int) -> void:
	if not game.can_whistle(team):
		return
	var objective := _get_objective()
	var garrison := _objective_garrison()

	if objective is Trench:
		if garrison >= gas_garrison and game.play_card(team, GameManager.Card.GAS, objective.global_position):
			_pending_charge_ticks = gas_to_charge_ticks
			return
		if garrison >= 2 and game.play_card(team, GameManager.Card.MORTAR, objective.global_position):
			game.trigger_whistle(team)
			return
	elif objective is Bunker:
		# A shell on the bunker silences its machine gun for the run-in.
		if game.play_card(team, GameManager.Card.MORTAR, objective.global_position):
			game.trigger_whistle(team)
			return

	if _outnumbers(my_stationed, enemy_total) or garrison == 0:
		game.trigger_whistle(team)


func _act_build_up(my_units: Array[Unit], enemy_units: Array[Unit]) -> void:
	if not _has_room():
		return  # Nowhere to put more soldiers: bank the Supply.
	if my_units.size() >= garrison_target:
		return  # Garrison is strong enough: save up for a barrage.

	# Counter-pick. Raiders beat an entrenched rifle line; riflemen beat
	# raiders, who die quickly while crossing open ground.
	var my_rifles := _count_type(my_units, Unit.Type.RIFLEMAN)
	var my_raiders := _count_type(my_units, Unit.Type.RAIDER)
	var enemy_rifles := _count_type(enemy_units, Unit.Type.RIFLEMAN)
	var enemy_raiders := _count_type(enemy_units, Unit.Type.RAIDER)

	var want_raiders := my_rifles >= 3 and my_raiders < 2 and enemy_rifles >= enemy_raiders
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
	return game.find_cover_trench(team, Vector2.ZERO) != null


## Our most advanced trench with soldiers stationed in it (or, with nobody
## stationed anywhere, the most advanced trench we own).
func _get_front_trench() -> Trench:
	var dir := GameManager.advance_dir(team)
	var front: Trench = null
	for trench in game.trenches:
		if trench.count_stationed(team) == 0:
			continue
		if front == null or (trench.global_position.x - front.global_position.x) * dir > 0.0:
			front = trench
	return front if front != null else game.get_front_trench(team)


## What a Whistle Charge would go for right now: a Trench or the enemy Bunker.
func _get_objective() -> Node2D:
	var front := _get_front_trench()
	return game.find_charge_objective(team, front.global_position.x, front)


## True when the next trench ahead has no enemy in it at all.
func _objective_is_undefended() -> bool:
	var objective := _get_objective() as Trench
	return objective != null and objective.is_hostile_to(team) and objective.count_inside(_enemy_team) == 0


## Enemy soldiers standing inside any trench we own or garrison.
func _count_intruders() -> int:
	var total := 0
	for trench in game.trenches:
		if trench.owner_team == team or trench.count_stationed(team) > 0:
			total += trench.count_inside(_enemy_team)
	return total


## Is a trench holding two or more of our soldiers under a gas cloud?
func _garrison_is_gassed() -> bool:
	for trench in game.trenches:
		if trench.count_stationed(team) >= 2 and _is_gassed(trench):
			return true
	return false


## Enemy soldiers stationed in the trench we would assault (0 for a bunker).
func _objective_garrison() -> int:
	var objective := _get_objective()
	if objective is Trench:
		return (objective as Trench).count_stationed(_enemy_team)
	return 0


## Can we pay for a mortar or gas right now?
func _barrage_ready() -> bool:
	return game.can_play_card(team, GameManager.Card.MORTAR) or game.can_play_card(team, GameManager.Card.GAS)


func _is_gassed(trench: Trench) -> bool:
	for node in get_tree().get_nodes_in_group("gas_clouds"):
		var cloud := node as GasCloud
		if cloud != null and cloud.is_active() and absf(cloud.global_position.x - trench.global_position.x) < 100.0:
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


## Enemy soldiers out of cover who are closing on (or past) our front trench.
func _count_attackers(enemy_units: Array[Unit]) -> int:
	var enemy_dir := GameManager.advance_dir(_enemy_team)
	var front_x := _get_front_trench().global_position.x
	var total := 0
	for unit in enemy_units:
		if unit.state == Unit.State.IN_COVER:
			continue
		# True once the enemy is within 170 px of our front line.
		if (unit.global_position.x - front_x) * enemy_dir > -170.0:
			total += 1
	return total


## Best defensive mortar target: the tightest group of enemies OUT of cover.
## Returns {} or {"position": Vector2, "count": int}.
func _find_exposed_cluster(enemy_units: Array[Unit], my_units: Array[Unit]) -> Dictionary:
	if not game.can_play_card(team, GameManager.Card.MORTAR):
		return {}
	# Only troops that have gone past their own front trench count: shelling
	# reinforcements on their way up the line is a waste of Supply.
	var enemy_dir := GameManager.advance_dir(_enemy_team)
	var enemy_line := game.get_front_trench(_enemy_team).global_position.x
	var exposed: Array[Unit] = []
	for unit in enemy_units:
		if unit.state == Unit.State.IN_COVER:
			continue
		if (unit.global_position.x - enemy_line) * enemy_dir > 70.0:
			exposed.append(unit)

	var best := {}
	var best_count := mortar_cluster_size - 1
	for center in exposed:
		var count := 0
		var sum := Vector2.ZERO
		var drift := Vector2.ZERO
		for other in exposed:
			if other.global_position.distance_to(center.global_position) <= mortar_cluster_radius:
				count += 1
				sum += other.global_position
				drift += other.velocity
		if count <= best_count:
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
		best_count = count
		best = {"position": aim, "count": count}
	return best
