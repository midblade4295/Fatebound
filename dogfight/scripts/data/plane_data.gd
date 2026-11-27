class_name PlaneData
extends Resource
## Definition of one base aircraft: when it unlocks, its base stats, and the
## handful of proportions PlaneVisual needs to build its chunky primitive model.
##
## Final in-match numbers come from build_stats():
##   base stats  x  Commander Level bonus  x  every equipped ComponentCard.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Commander Level that unlocks this plane (Hurricane 1, Spitfire 3, Mustang 6).
@export_range(1, 14) var unlock_commander_level: int = 1

@export_group("Base Stats")
@export var base_max_hp: float = 1000.0
## Level-flight top speed in m/s.
@export var base_top_speed: float = 85.0
@export var base_acceleration: float = 0.6
@export var base_climb_rate: float = 1.0
@export var base_turn_rate_deg: float = 58.0
@export var base_pitch_rate_deg: float = 52.0
@export var base_roll_rate: float = 1.0

@export_group("Guns")
@export var base_fire_rate: float = 10.0
@export var base_bullet_damage: float = 150.0
@export var bullet_speed: float = 420.0
@export var gun_range: float = 480.0
@export var gun_spread_deg: float = 0.6

@export_group("Sound")
## Seamless loop of this aircraft's engine at cruise power.
@export var engine_sound: AudioStream
## One-shot samples for a single round from this aircraft's guns. One is
## picked at random for every round fired.
@export var gun_sounds: Array[AudioStream] = []
## Pitch the gun samples are played at (1.0 = as recorded).
@export_range(0.5, 2.0, 0.01) var gun_pitch: float = 1.0

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


## Base stats with only the Commander Level bonus applied (no cards).
func build_base_stats(commander_level: int) -> PlaneStats:
	var stats: PlaneStats = PlaneStats.new()
	stats.max_hp = base_max_hp * CommanderProgression.hp_multiplier(commander_level)
	stats.top_speed = base_top_speed * CommanderProgression.speed_multiplier(commander_level)
	stats.acceleration = base_acceleration
	stats.climb_rate = base_climb_rate
	stats.turn_rate = deg_to_rad(base_turn_rate_deg)
	stats.pitch_rate = deg_to_rad(base_pitch_rate_deg)
	stats.roll_rate = base_roll_rate
	stats.fire_rate = base_fire_rate
	stats.bullet_damage = base_bullet_damage
	stats.bullet_speed = bullet_speed
	stats.gun_range = gun_range
	stats.gun_spread_deg = gun_spread_deg
	return stats


## Full stat block for a match. [param cards] and [param card_levels] are
## parallel arrays; null entries (empty slots) are skipped. Only the first
## CommanderProgression.card_slot_count() entries count, so a stale loadout can
## never smuggle in a card from a slot the player has not unlocked.
func build_stats(commander_level: int, cards: Array[ComponentCard], card_levels: Array[int]) -> PlaneStats:
	var stats: PlaneStats = build_base_stats(commander_level)
	var open_slots: int = CommanderProgression.card_slot_count(commander_level)
	var count: int = mini(mini(cards.size(), card_levels.size()), open_slots)
	for index: int in range(count):
		var card: ComponentCard = cards[index]
		if card == null:
			continue
		card.apply_to(stats, card_levels[index])
	return stats
