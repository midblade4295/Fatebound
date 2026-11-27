class_name PlaneData
extends Resource
## Definition of one base aircraft: when it unlocks, its base stats, and the
## handful of proportions PlaneVisual needs to build its chunky primitive model.
##
## Final in-match numbers come from build_stats():
##   base stats  x  Commander Level bonus  x  everything fitted to the mounts.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Commander Level that unlocks this plane (Hurricane 1, Spitfire 3, Mustang 6).
@export_range(1, 14) var unlock_commander_level: int = 1

## Share of a change in span that shows up as a change in wing area (the tips
## are the narrow end of the wing).
const WING_AREA_PER_SPAN: float = 0.6

@export_group("Base Stats")
@export var base_max_hp: float = 1000.0
## The real aeroplane's figures. Everything it can do (top speed, stalling
## speed, climb, turn, take-off run) is worked out from these by the flight
## model, not stated here.
## Weight ready to fly but with nothing fitted to the mounts, kg.
@export var base_mass: float = 2900.0
## Wing area in square metres and span in metres.
@export var base_wing_area: float = 22.5
@export var base_span: float = 11.2
## Full engine power, kilowatts.
@export var base_power_kw: float = 1100.0
## Drag coefficient of the clean aeroplane at zero lift.
@export var base_drag: float = 0.021
## The most lift coefficient the wing makes before it stalls.
@export var base_max_lift: float = 1.5
## Aileron power: 1.0 rolls like a Spitfire.
@export var base_roll: float = 1.0

@export_group("Sound")
## Seamless loop of this aircraft's engine at cruise power.
@export var engine_sound: AudioStream

@export_group("Visuals")
@export var body_color: Color = Color("6f8f5a")
@export var camo_color: Color = Color("8a6f4a")
@export var belly_color: Color = Color("bfe3f2")
@export var nose_color: Color = Color("ffd23f")
## Metres, before PlaneVisual's global chunkiness scale.
@export var wing_span: float = 10.0
@export var wing_chord: float = 2.6
@export var fuselage_length: float = 7.5
@export var fuselage_radius: float = 1.0
@export_range(2, 5) var prop_blades: int = 3
## Bubble canopy (Mustang) instead of a framed one.
@export var bubble_canopy: bool = false


func is_unlocked(commander_level: int) -> bool:
	return commander_level >= unlock_commander_level


## The bare aeroplane with only the Commander Level bonus: nothing fitted, so
## no guns. See build_stats() and build_stock_stats().
func build_base_stats(commander_level: int) -> PlaneStats:
	var stats: PlaneStats = _begin_stats(commander_level)
	_finish_stats(stats)
	return stats


func _begin_stats(commander_level: int) -> PlaneStats:
	var stats: PlaneStats = PlaneStats.new()
	stats.max_hp = base_max_hp * CommanderProgression.hp_multiplier(commander_level)
	stats.speed_factor = CommanderProgression.speed_multiplier(commander_level)
	stats.max_lift = base_max_lift
	stats.roll_power = base_roll
	stats.fittings.resize(CommanderProgression.MOUNT_COUNT)
	stats.fitting_marks.resize(CommanderProgression.MOUNT_COUNT)
	stats.fitting_marks.fill(1)
	return stats


## Turns what the fittings asked for into the aeroplane's real figures, then
## flies it on paper to find out what it can do.
func _finish_stats(stats: PlaneStats) -> void:
	# Weight: everything fitted has to be dragged into the air and round the turns.
	stats.mass = base_mass * stats.weight
	stats.engine_power = base_power_kw * 1000.0 * stats.power_factor
	# Clipped or extended tips change the span, and with it the area.
	stats.wing_span = base_span * stats.wing_factor
	stats.wing_area = base_wing_area * (1.0 + WING_AREA_PER_SPAN * (stats.wing_factor - 1.0))
	# Top speed goes with the cube root of power over drag. A fitting that
	# promises speed is a cleaner one: it gets its promise in less drag, over
	# and above whatever extra power it brings.
	stats.drag = base_drag * stats.power_factor / pow(stats.speed_factor, 3.0)
	var flight: FlightDynamics = stats.make_flight()
	stats.top_speed = flight.level_top_speed()
	stats.stall_speed = flight.stall_speed(0.0)
	stats.landing_stall_speed = flight.stall_speed(1.0)
	stats.climb_rate = flight.best_climb_rate()
	stats.climb_speed = flight.best_climb_speed()


## The plane as it leaves the factory: stock fittings, all Mk I.
func build_stock_stats(commander_level: int) -> PlaneStats:
	return build_stats(commander_level, GameCatalog.stock_fittings(), GameCatalog.stock_marks())


## Full stat block for a match. [param fittings] and [param marks] are parallel
## arrays in mount order (CommanderProgression.MOUNT_*); null entries are empty
## mounts. An item in the wrong kind of mount, or in a mount this Commander
## Level has not opened, is left off, so a stale loadout can never smuggle
## anything on.
func build_stats(commander_level: int, fittings: Array[ComponentCard], marks: Array[int]) -> PlaneStats:
	var stats: PlaneStats = _begin_stats(commander_level)
	var count: int = mini(mini(fittings.size(), marks.size()), CommanderProgression.MOUNT_COUNT)
	var shots_per_second: float = 0.0
	var damage_per_second: float = 0.0
	var speed_weighted: float = 0.0
	for mount: int in range(count):
		var card: ComponentCard = fittings[mount]
		if card == null or not CommanderProgression.mount_accepts(mount, card):
			continue
		if not CommanderProgression.is_mount_unlocked(mount, commander_level):
			continue
		var mark: int = clampi(marks[mount], 1, ComponentCard.MAX_MARK)
		stats.fittings[mount] = card
		stats.fitting_marks[mount] = mark
		card.apply_to(stats, mark)
		if card.is_gun():
			shots_per_second += card.fire_rate
			damage_per_second += card.fire_rate * card.damage_at(mark)
			speed_weighted += card.fire_rate * card.muzzle_speed
			stats.gun_range = maxf(stats.gun_range, card.gun_range)
	if shots_per_second > 0.0:
		stats.fire_rate = shots_per_second
		stats.bullet_damage = damage_per_second / shots_per_second
		stats.bullet_speed = speed_weighted / shots_per_second
	_finish_stats(stats)
	return stats
