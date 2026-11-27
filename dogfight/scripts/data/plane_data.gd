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

## The clean wing stops carrying the bare aeroplane below this share of its
## top speed.
const STALL_SPEED_RATIO: float = 0.6

@export_group("Base Stats")
@export var base_max_hp: float = 1000.0
## Level-flight top speed in m/s.
@export var base_top_speed: float = 85.0
@export var base_acceleration: float = 0.6
@export var base_climb_rate: float = 1.0
@export var base_turn_rate_deg: float = 58.0
@export var base_pitch_rate_deg: float = 52.0
@export var base_roll_rate: float = 1.0

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
	var stats: PlaneStats = PlaneStats.new()
	stats.max_hp = base_max_hp * CommanderProgression.hp_multiplier(commander_level)
	stats.top_speed = base_top_speed * CommanderProgression.speed_multiplier(commander_level)
	stats.acceleration = base_acceleration
	stats.climb_rate = base_climb_rate
	stats.turn_rate = deg_to_rad(base_turn_rate_deg)
	stats.pitch_rate = deg_to_rad(base_pitch_rate_deg)
	stats.roll_rate = base_roll_rate
	stats.stall_speed = stats.top_speed * STALL_SPEED_RATIO
	stats.fittings.resize(CommanderProgression.MOUNT_COUNT)
	stats.fitting_marks.resize(CommanderProgression.MOUNT_COUNT)
	stats.fitting_marks.fill(1)
	return stats


## The plane as it leaves the factory: stock fittings, all Mk I.
func build_stock_stats(commander_level: int) -> PlaneStats:
	return build_stats(commander_level, GameCatalog.stock_fittings(), GameCatalog.stock_marks())


## Full stat block for a match. [param fittings] and [param marks] are parallel
## arrays in mount order (CommanderProgression.MOUNT_*); null entries are empty
## mounts. An item in the wrong kind of mount, or in a mount this Commander
## Level has not opened, is left off, so a stale loadout can never smuggle
## anything on.
func build_stats(commander_level: int, fittings: Array[ComponentCard], marks: Array[int]) -> PlaneStats:
	var stats: PlaneStats = build_base_stats(commander_level)
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
	# Weight: everything fitted has to be dragged into the air and round the turns.
	stats.acceleration /= stats.weight
	stats.climb_rate /= stats.weight
	stats.turn_rate /= sqrt(stats.weight)
	stats.pitch_rate /= sqrt(stats.weight)
	stats.stall_speed *= sqrt(stats.weight / maxf(stats.lift, 0.1))
	return stats
