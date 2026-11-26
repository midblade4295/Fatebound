class_name Trench
extends Area2D
## Trench.gd -- a trench sector.
##
## * Slot capacity: every Marker2D under $Slots is one firing position.
##   Units reserve a slot, walk to it, then call occupy() when they arrive.
## * Cover: units stationed in a slot multiply incoming bullet / blast damage
##   by the multipliers below.
## * Sector ownership: the trench belongs to the last team that stationed a
##   soldier in it while no enemy was inside.
##
## Collision setup: layer 4 (sectors), mask 1 + 2 (blue_units, red_units).

signal owner_changed(trench: Trench, new_owner: int)

const FLAG_COLORS := {
	GameManager.TEAM_NONE: Color(0.55, 0.52, 0.46),
	GameManager.TEAM_BLUE: Color(0.3, 0.55, 0.85),
	GameManager.TEAM_RED: Color(0.82, 0.25, 0.2),
}

@export_enum("Neutral:-1", "Blue:0", "Red:1") var initial_owner: int = -1
## Bullet damage multiplier for stationed units (0.4 = 60% damage reduction).
@export_range(0.0, 1.0, 0.05) var cover_damage_multiplier := 0.4
## Mortar damage multiplier for stationed units.
@export_range(0.0, 1.0, 0.05) var blast_damage_multiplier := 0.5

var owner_team := GameManager.TEAM_NONE

var _slot_markers: Array[Marker2D] = []
## Unit holding each slot (null = free). Same indices as _slot_markers.
var _slot_units: Array[Unit] = []

@onready var flag_cloth: Polygon2D = $Flag/Cloth


func _ready() -> void:
	for child in $Slots.get_children():
		if child is Marker2D:
			_slot_markers.append(child)
			_slot_units.append(null)
	owner_team = initial_owner
	_update_flag()


# ----------------------------------------------------------------------------
# Slots
# ----------------------------------------------------------------------------
func get_capacity() -> int:
	return _slot_markers.size()


func get_free_slot_count() -> int:
	return _slot_units.count(null)


## Reserves the free slot closest to `unit`. Returns its index, or -1 if full.
func reserve_slot(unit: Unit) -> int:
	var best := -1
	var best_distance := INF
	for i in _slot_markers.size():
		if _slot_units[i] != null:
			continue
		var distance := absf(_slot_markers[i].global_position.x - unit.global_position.x)
		if distance < best_distance:
			best = i
			best_distance = distance
	if best >= 0:
		_slot_units[best] = unit
	return best


func release_slot(unit: Unit) -> void:
	var index := _slot_units.find(unit)
	if index >= 0:
		_slot_units[index] = null


func get_slot_position(index: int) -> Vector2:
	return _slot_markers[index].global_position


## Called by a unit when it reaches its slot and enters IN_COVER.
func occupy(unit: Unit) -> void:
	_try_capture(unit.team)


## True while `unit` still holds a reservation here and no enemy is inside.
func can_hold(unit: Unit) -> bool:
	return _slot_units.has(unit) and not has_enemies_of(unit.team)


## "Friendly / unoccupied": there is room and no living enemy is inside.
func can_accept(team: int) -> bool:
	return get_free_slot_count() > 0 and not has_enemies_of(team)


# ----------------------------------------------------------------------------
# Occupancy / ownership
# ----------------------------------------------------------------------------
## Any living soldier of the other team physically inside the trench area?
func has_enemies_of(team: int) -> bool:
	for body in get_overlapping_bodies():
		var unit := body as Unit
		if unit != null and unit.is_alive() and unit.team != team:
			return true
	return false


## Enemy trench for a Whistle Charge: owned by someone else, or contested.
func is_hostile_to(team: int) -> bool:
	return owner_team != team or has_enemies_of(team)


## Number of `team` soldiers stationed (IN_COVER) in this trench.
func count_stationed(team: int) -> int:
	var total := 0
	for unit in _slot_units:
		if unit != null and unit.team == team and unit.state == Unit.State.IN_COVER:
			total += 1
	return total


## Number of living `team` soldiers physically inside the trench area.
func count_inside(team: int) -> int:
	var total := 0
	for body in get_overlapping_bodies():
		var unit := body as Unit
		if unit != null and unit.is_alive() and unit.team == team:
			total += 1
	return total


func _try_capture(team: int) -> void:
	if owner_team == team or has_enemies_of(team):
		return
	owner_team = team
	_update_flag()
	owner_changed.emit(self, owner_team)


func _update_flag() -> void:
	flag_cloth.color = FLAG_COLORS[owner_team]


# ----------------------------------------------------------------------------
# Area2D signals (connected in Trench.tscn)
# ----------------------------------------------------------------------------
func _on_body_entered(body: Node2D) -> void:
	var unit := body as Unit
	if unit != null:
		unit.zone_trench = self


func _on_body_exited(body: Node2D) -> void:
	var unit := body as Unit
	if unit != null and unit.zone_trench == self:
		unit.zone_trench = null
