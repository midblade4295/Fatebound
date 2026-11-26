class_name GameManager
extends Node2D
## GameManager.gd -- root script of Main.tscn.
##
## Owns the match rules: the 3-minute clock, the Supply economy for both teams,
## card play (spawns / mortar / gas), the Whistle Charge signal, sector control
## and the win / loss states. Units, the HUD and the AI all talk to the match
## through this node.

# ----------------------------------------------------------------------------
# Signals
# ----------------------------------------------------------------------------
signal supply_changed(team: int, amount: float)
signal time_changed(seconds_left: int)
## Emitted when a team blows the whistle. Every Unit listens to this.
signal whistle_charge(team: int)
## owners runs left to right: Blue Bunker, every trench, Red Bunker.
## Each entry is TEAM_BLUE, TEAM_RED or TEAM_NONE.
signal sector_control_changed(owners: Array[int])
signal bunker_health_changed(team: int, health: float, max_health: float)
signal card_played(team: int, card_id: int)
## The last `final_push_seconds` have started: Supply income is multiplied.
signal final_push_started()
signal match_ended(winner: int, reason: String)

# ----------------------------------------------------------------------------
# Constants
# ----------------------------------------------------------------------------
const TEAM_NONE := -1
const TEAM_BLUE := 0
const TEAM_RED := 1

## Y coordinate of the ground line every unit walks on.
const GROUND_Y := 700.0
## Width of the battlefield in world pixels, bunker to bunker plus a margin.
## The camera zooms so exactly this much is on screen.
const FIELD_VIEW_WIDTH := 2520.0
## How far above the bottom of the screen the ground line sits (room for the
## card hand), in screen pixels.
const GROUND_ABOVE_SCREEN_BOTTOM := 390.0
## Tappable X range for mortar / gas (the whole battlefield fits one screen).
const FIELD_MIN_X := 40.0
const FIELD_MAX_X := FIELD_VIEW_WIDTH - 40.0

enum Card { RIFLEMEN, RAIDERS, MORTAR, GAS }

## Card data. `targeted` cards need a battlefield position (HUD targeting mode).
const CARDS := {
	Card.RIFLEMEN: {"name": "Riflemen", "cost": 2, "cooldown": 3.0, "targeted": false},
	Card.RAIDERS: {"name": "Trench Raiders", "cost": 4, "cooldown": 5.0, "targeted": false},
	Card.MORTAR: {"name": "Mortar Strike", "cost": 5, "cooldown": 8.0, "targeted": true},
	Card.GAS: {"name": "Mustard Gas", "cost": 6, "cooldown": 12.0, "targeted": true},
}

const UNIT_SCENE := preload("res://scenes/Unit.tscn")
const MORTAR_SCENE := preload("res://scenes/MortarStrike.tscn")
const GAS_SCENE := preload("res://scenes/GasCloud.tscn")
const CRATER_SCENE := preload("res://scenes/Crater.tscn")

# ----------------------------------------------------------------------------
# Tunables (editable in the Inspector on the Main node)
# ----------------------------------------------------------------------------
@export_group("Match")
@export var match_length := 180.0
@export var whistle_cooldown := 8.0
@export_group("Supply")
@export var supply_max := 10.0
## Base income. Deliberately slow: every card should be a decision, not a reflex.
@export var supply_per_second := 0.5
@export var supply_start := 5.0
## Extra income per sector held beyond the ones you start with.
@export var supply_per_extra_sector := 0.1
## In the last `final_push_seconds` of the match income is multiplied.
@export var final_push_seconds := 45.0
@export var final_push_multiplier := 2.0
@export_group("Cards")
@export var riflemen_per_card := 3
@export var raiders_per_card := 2
@export var max_craters := 8
## Gas snaps onto a trench when the tap lands within this distance of it.
@export var gas_snap_distance := 130.0

# ----------------------------------------------------------------------------
# State
# ----------------------------------------------------------------------------
var match_over := false
var winner := TEAM_NONE
## Current Supply per team, indexed by TEAM_BLUE / TEAM_RED.
var supply: Array[float] = [0.0, 0.0]
## Every Trench under Battlefield/Sectors, ordered left to right (Blue's
## rearmost trench first, Red's rearmost last).
var trenches: Array[Trench] = []
## Blue Bunker, each trench left to right, Red Bunker.
var sector_owners: Array[int] = []
## Sectors each team holds at kick-off (its bunker + its own trenches).
var _starting_sectors: Array[int] = [1, 1]

var _card_cooldowns := [[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]]
var _whistle_cooldowns: Array[float] = [0.0, 0.0]
var _last_seconds := -1
var _final_push := false
var _shake := 0.0

@onready var camera: Camera2D = $Camera2D
@onready var match_timer: Timer = $MatchTimer
@onready var blue_bunker: Bunker = $Battlefield/Sectors/BlueBunker
@onready var sectors_root: Node2D = $Battlefield/Sectors
@onready var red_bunker: Bunker = $Battlefield/Sectors/RedBunker
@onready var craters_root: Node2D = $Battlefield/Craters
@onready var units_root: Node2D = $Battlefield/Units
@onready var effects_root: Node2D = $Battlefield/Effects
@onready var ai_controller: Node = $AIController
@onready var hud: CanvasLayer = $HUD


# ----------------------------------------------------------------------------
# Lifecycle
# ----------------------------------------------------------------------------
func _ready() -> void:
	randomize()
	# Collect the trenches from the scene, so adding or removing a Trench
	# instance under Battlefield/Sectors is all it takes to change the map.
	for child in sectors_root.get_children():
		if child is Trench:
			trenches.append(child)
	trenches.sort_custom(func(a: Trench, b: Trench) -> bool: return a.global_position.x < b.global_position.x)
	for trench in trenches:
		trench.owner_changed.connect(_on_trench_owner_changed)
		if trench.initial_owner != TEAM_NONE:
			_starting_sectors[trench.initial_owner] += 1
	sector_owners = _read_sector_owners()
	supply = [supply_start, supply_start]

	# Children are ready before their parent, so everything below exists.
	blue_bunker.setup(self)
	red_bunker.setup(self)
	hud.setup(self)
	ai_controller.setup(self)

	for team in [TEAM_BLUE, TEAM_RED]:
		supply_changed.emit(team, supply[team])
		# Each side starts with one rifle squad already at its front trench.
		var front := get_front_trench(team)
		spawn_squad(team, Unit.Type.RIFLEMAN, riflemen_per_card, Vector2(front.global_position.x, GROUND_Y))

	_fit_camera()
	get_viewport().size_changed.connect(_fit_camera)

	sector_control_changed.emit(sector_owners)
	match_timer.start(match_length)
	_emit_time()


func _process(delta: float) -> void:
	_update_camera_shake(delta)
	if match_over:
		return

	if not _final_push and get_time_left() <= final_push_seconds:
		_final_push = true
		final_push_started.emit()

	for team in [TEAM_BLUE, TEAM_RED]:
		# Supply economy: see get_supply_rate(). Capped at supply_max.
		if supply[team] < supply_max:
			supply[team] = minf(supply_max, supply[team] + get_supply_rate(team) * delta)
			supply_changed.emit(team, supply[team])
		_whistle_cooldowns[team] = maxf(0.0, _whistle_cooldowns[team] - delta)
		for card_id in CARDS:
			_card_cooldowns[team][card_id] = maxf(0.0, _card_cooldowns[team][card_id] - delta)

	_emit_time()


# ----------------------------------------------------------------------------
# Team helpers
# ----------------------------------------------------------------------------
static func enemy_of(team: int) -> int:
	return TEAM_RED if team == TEAM_BLUE else TEAM_BLUE


## +1 for Blue (advances right), -1 for Red (advances left).
static func advance_dir(team: int) -> float:
	return 1.0 if team == TEAM_BLUE else -1.0


func get_bunker(team: int) -> Bunker:
	return blue_bunker if team == TEAM_BLUE else red_bunker


## The trench right in front of a team's bunker.
func get_home_trench(team: int) -> Trench:
	return trenches[0] if team == TEAM_BLUE else trenches[trenches.size() - 1]


## The forward-most trench a team owns (its home trench if it owns none).
func get_front_trench(team: int) -> Trench:
	var front := get_home_trench(team)
	for trench in _trenches_from_home(team):
		if trench.owner_team == team:
			front = trench
	return front


func get_time_left() -> float:
	return 0.0 if match_timer.is_stopped() else match_timer.time_left


## All living units of a team.
func get_units(team: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for node in get_tree().get_nodes_in_group("team_%d" % team):
		var unit := node as Unit
		if unit != null and unit.is_alive():
			result.append(unit)
	return result


## Supply per second for `team` right now: base income, plus a bonus for every
## sector held beyond the ones you start with, doubled during the final push.
func get_supply_rate(team: int) -> float:
	var extra_sectors := maxi(0, count_sectors(team) - _starting_sectors[team])
	var rate := supply_per_second + supply_per_extra_sector * extra_sectors
	if _final_push:
		rate *= final_push_multiplier
	return rate


func is_final_push() -> bool:
	return _final_push


func count_stationed(team: int) -> int:
	var total := 0
	for unit in get_units(team):
		if unit.state == Unit.State.IN_COVER:
			total += 1
	return total


## Where units wait when every reachable trench is full.
func get_rally_point(team: int) -> Vector2:
	return Vector2(get_bunker(team).global_position.x + advance_dir(team) * 110.0, GROUND_Y)


# ----------------------------------------------------------------------------
# Trench / objective queries used by Unit.gd
# ----------------------------------------------------------------------------
## Trenches ordered from a team's own bunker outward.
func _trenches_from_home(team: int) -> Array[Trench]:
	var ordered: Array[Trench] = trenches.duplicate()
	if team == TEAM_RED:
		ordered.reverse()
	return ordered


## Where fresh troops go: the forward-most trench their side owns that still has
## a free slot, so reinforcements flow to the front line. If none has room they
## walk back into one of their own original trenches that stands empty. Units cannot pass an
## enemy-held trench, so the scan stops there. Capturing an enemy trench always
## takes a Whistle Charge.
func find_cover_trench(team: int, _from_position: Vector2) -> Trench:
	var front: Trench = null
	var fallback: Trench = null
	for trench in _trenches_from_home(team):
		if trench.has_enemies_of(team):
			break
		if not trench.can_accept(team):
			continue
		if trench.owner_team == team:
			front = trench  # Later in the loop = further forward.
		elif trench.initial_owner == team and fallback == null:
			fallback = trench
	return front if front != null else fallback


## First enemy-occupied trench on the way out from a team's bunker (or null).
func find_blocking_trench(team: int) -> Trench:
	for trench in _trenches_from_home(team):
		if trench.has_enemies_of(team):
			return trench
	return null


## Whistle Charge target: "advance one line". The next trench ahead of
## `from_x` is assaulted if the enemy holds it, or moved up into if it is ours
## and has room. With no such trench ahead the target is the enemy Command Bunker.
func find_charge_objective(team: int, from_x: float, ignore: Trench = null) -> Node2D:
	var dir := advance_dir(team)
	var best: Trench = null
	var best_ahead := INF
	for trench in trenches:
		if trench == ignore:
			continue
		if not trench.is_hostile_to(team) and trench.get_free_slot_count() == 0:
			continue  # Ours and already full: run past it.
		var ahead := (trench.global_position.x - from_x) * dir
		if ahead < -30.0:
			continue  # Behind us.
		if ahead < best_ahead:
			best = trench
			best_ahead = ahead
	if best != null:
		return best
	return get_bunker(enemy_of(team))


# ----------------------------------------------------------------------------
# Cards
# ----------------------------------------------------------------------------
func get_card_cost(card_id: int) -> float:
	return float(CARDS[card_id]["cost"])


func get_card_cooldown(team: int, card_id: int) -> float:
	return _card_cooldowns[team][card_id]


func can_play_card(team: int, card_id: int) -> bool:
	if match_over:
		return false
	return supply[team] >= get_card_cost(card_id) and get_card_cooldown(team, card_id) <= 0.0


## Spends Supply and resolves a card. `target` is only used by targeted cards.
## Returns false (and spends nothing) if the card cannot be played right now.
func play_card(team: int, card_id: int, target: Vector2 = Vector2.ZERO) -> bool:
	if not can_play_card(team, card_id):
		return false

	supply[team] -= get_card_cost(card_id)
	supply_changed.emit(team, supply[team])
	_card_cooldowns[team][card_id] = float(CARDS[card_id]["cooldown"])

	match card_id:
		Card.RIFLEMEN:
			spawn_squad(team, Unit.Type.RIFLEMAN, riflemen_per_card)
		Card.RAIDERS:
			spawn_squad(team, Unit.Type.RAIDER, raiders_per_card)
		Card.MORTAR:
			launch_mortar(team, target)
		Card.GAS:
			release_gas(team, target)

	card_played.emit(team, card_id)
	return true


## Spawns `count` soldiers in a short column. They appear at their bunker
## unless `at` is given.
func spawn_squad(team: int, unit_type: Unit.Type, count: int, at: Vector2 = Vector2.INF) -> void:
	var origin := at if at != Vector2.INF else get_bunker(team).get_spawn_position()
	var dir := advance_dir(team)
	for i in count:
		var unit: Unit = UNIT_SCENE.instantiate()
		unit.setup(self, team, unit_type)
		# Stagger the squad in a short column behind the spawn point.
		unit.position = origin + Vector2(-dir * 24.0 * i, randf_range(-5.0, 8.0))
		units_root.add_child(unit)


func launch_mortar(team: int, target: Vector2) -> void:
	var strike: MortarStrike = MORTAR_SCENE.instantiate()
	strike.setup(self, team)
	strike.position = Vector2(clampf(target.x, FIELD_MIN_X, FIELD_MAX_X), GROUND_Y)
	effects_root.add_child(strike)
	get_bunker(team).play_mortar_recoil()


func release_gas(team: int, target: Vector2) -> void:
	var x := clampf(target.x, FIELD_MIN_X, FIELD_MAX_X)
	# Gas is meant for trenches: snap to the closest one if the tap was near it.
	var nearest := gas_snap_distance
	var snapped_x := x
	for trench in trenches:
		var distance := absf(trench.global_position.x - x)
		if distance <= nearest:
			nearest = distance
			snapped_x = trench.global_position.x
	x = snapped_x
	var cloud: GasCloud = GAS_SCENE.instantiate()
	cloud.source_team = team
	cloud.position = Vector2(x, GROUND_Y)
	effects_root.add_child(cloud)


# ----------------------------------------------------------------------------
# Whistle Charge
# ----------------------------------------------------------------------------
func get_whistle_cooldown(team: int) -> float:
	return _whistle_cooldowns[team]


func can_whistle(team: int) -> bool:
	return not match_over and _whistle_cooldowns[team] <= 0.0 and count_stationed(team) > 0


## Orders every stationed unit of `team` over the top.
func trigger_whistle(team: int) -> bool:
	if not can_whistle(team):
		return false
	_whistle_cooldowns[team] = whistle_cooldown
	whistle_charge.emit(team)
	return true


# ----------------------------------------------------------------------------
# Combat helpers (explosions, craters, tracers, camera shake)
# ----------------------------------------------------------------------------
## Area damage with linear falloff. Shells do not care whose side you are on.
## Everyone caught in (or just outside) the blast is also PINNED for `pin_time`
## seconds, even in cover: this is what opens the window for a charge. A shell
## landing on a bunker silences its machine gun for the same time.
func apply_explosion(center: Vector2, radius: float, max_damage: float, min_damage: float, pin_time: float = 0.0) -> void:
	for node in get_tree().get_nodes_in_group("units"):
		var unit := node as Unit
		if unit == null or not unit.is_alive():
			continue
		var distance := unit.global_position.distance_to(center)
		if distance <= radius * 1.2 and pin_time > 0.0:
			unit.pin(pin_time)
		if distance <= radius:
			var damage := lerpf(max_damage, min_damage, distance / radius)
			unit.take_damage(damage, Unit.DamageKind.EXPLOSION, null)

	for bunker: Bunker in [blue_bunker, red_bunker]:
		if absf(bunker.global_position.x - center.x) <= bunker.half_width + radius * 0.5:
			bunker.take_damage(max_damage * 0.8, Unit.DamageKind.EXPLOSION, null)
			if pin_time > 0.0:
				bunker.suppress(pin_time)


## Leaves a crater (cover zone) on open ground.
func add_crater(at: Vector2) -> void:
	for trench in trenches:
		if absf(trench.global_position.x - at.x) < 105.0:
			return  # No craters inside the trench works.
	for bunker: Bunker in [blue_bunker, red_bunker]:
		if absf(bunker.global_position.x - at.x) < bunker.half_width + 30.0:
			return

	var crater: Crater = CRATER_SCENE.instantiate()
	crater.position = Vector2(at.x, GROUND_Y)
	craters_root.add_child(crater)
	if craters_root.get_child_count() > max_craters:
		(craters_root.get_child(0) as Crater).remove()


## Short orange bullet streak between two points.
func spawn_tracer(from: Vector2, to: Vector2) -> void:
	var tracer := Line2D.new()
	tracer.width = 2.0
	tracer.default_color = Color(1.0, 0.74, 0.32, 0.95)
	tracer.points = PackedVector2Array([from, to])
	tracer.z_index = 6
	effects_root.add_child(tracer)
	var tween := tracer.create_tween()
	tween.tween_property(tracer, "modulate:a", 0.0, 0.12)
	tween.tween_callback(tracer.queue_free)


## Keeps the whole battlefield on one screen, edge to edge, on any aspect
## ratio: the camera zooms until FIELD_VIEW_WIDTH world pixels span the screen
## (zooming out on 16:9, barely at all on a 20:9 phone), then moves vertically
## so the ground line stays just above the card hand.
func _fit_camera() -> void:
	var view := get_viewport_rect().size
	var zoom := clampf(view.x / FIELD_VIEW_WIDTH, 0.5, 1.25)
	camera.zoom = Vector2(zoom, zoom)
	var ground_screen_y := view.y - GROUND_ABOVE_SCREEN_BOTTOM
	camera.position = Vector2(
		FIELD_VIEW_WIDTH * 0.5,
		GROUND_Y - (ground_screen_y - view.y * 0.5) / zoom
	)


func shake_camera(strength: float) -> void:
	_shake = maxf(_shake, strength)


func _update_camera_shake(delta: float) -> void:
	if _shake <= 0.05:
		camera.offset = Vector2.ZERO
		_shake = 0.0
		return
	camera.offset = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
	_shake = lerpf(_shake, 0.0, minf(1.0, delta * 9.0))


# ----------------------------------------------------------------------------
# Sector control and the tug-of-war meter
# ----------------------------------------------------------------------------
func count_sectors(team: int) -> int:
	return sector_owners.count(team)


## 0.0 = Red is dominating, 0.5 = even, 1.0 = Blue is dominating.
func get_tug_of_war() -> float:
	var swing := maxf(1.0, trenches.size() * 0.5 + 0.5)
	var sector_term := clampf((count_sectors(TEAM_BLUE) - count_sectors(TEAM_RED)) / swing, -1.0, 1.0)
	var health_term := blue_bunker.get_health_fraction() - red_bunker.get_health_fraction()
	return clampf(0.5 + 0.5 * (0.7 * sector_term + 0.3 * health_term), 0.0, 1.0)


func _read_sector_owners() -> Array[int]:
	var owners: Array[int] = [TEAM_BLUE if blue_bunker.is_alive() else TEAM_RED]
	for trench in trenches:
		owners.append(trench.owner_team)
	owners.append(TEAM_RED if red_bunker.is_alive() else TEAM_BLUE)
	return owners


func _update_sector_control() -> void:
	var owners := _read_sector_owners()
	if owners != sector_owners:
		sector_owners = owners
		sector_control_changed.emit(sector_owners)


func _on_sector_timer_timeout() -> void:
	if not match_over:
		_update_sector_control()


func _on_trench_owner_changed(_trench: Trench, _new_owner: int) -> void:
	_update_sector_control()


# ----------------------------------------------------------------------------
# Win / loss
# ----------------------------------------------------------------------------
func _emit_time() -> void:
	var seconds := ceili(get_time_left())
	if seconds != _last_seconds:
		_last_seconds = seconds
		time_changed.emit(seconds)


func _on_bunker_health_changed(team: int, health: float, max_health: float) -> void:
	bunker_health_changed.emit(team, health, max_health)


## A destroyed Command Bunker ends the match immediately.
func _on_bunker_destroyed(team: int) -> void:
	shake_camera(18.0)
	var victor := enemy_of(team)
	var loser_name := "Blue" if team == TEAM_BLUE else "Red"
	end_match(victor, "%s Command Bunker destroyed" % loser_name)


## 00:00 -- whoever controls the most sectors wins.
func _on_match_timer_timeout() -> void:
	if match_over:
		return
	_update_sector_control()
	var blue := count_sectors(TEAM_BLUE)
	var red := count_sectors(TEAM_RED)
	if blue > red:
		end_match(TEAM_BLUE, "Blue holds %d sectors to %d" % [blue, red])
	elif red > blue:
		end_match(TEAM_RED, "Red holds %d sectors to %d" % [red, blue])
	else:
		# Sector tie: the healthier bunker takes it, otherwise it is a draw.
		var blue_hp := blue_bunker.health
		var red_hp := red_bunker.health
		if blue_hp > red_hp:
			end_match(TEAM_BLUE, "Sectors tied %d-%d - Blue bunker stands stronger" % [blue, red])
		elif red_hp > blue_hp:
			end_match(TEAM_RED, "Sectors tied %d-%d - Red bunker stands stronger" % [blue, red])
		else:
			end_match(TEAM_NONE, "Sectors tied %d-%d" % [blue, red])


func end_match(p_winner: int, reason: String) -> void:
	if match_over:
		return
	match_over = true
	winner = p_winner
	match_timer.stop()
	match_ended.emit(winner, reason)


func restart_match() -> void:
	get_tree().reload_current_scene()
