class_name ComponentCard
extends Resource
## A collectible, upgradable component card (Clash Royale style).
##
## This resource is the shared *definition* of a card. What a player owns
## (current level, spare copies) lives in PlayerProfile, never in here, so one
## .tres can be shared by every plane and every player.
##
## Upgrade rules:
##  - Every card tops out at MAX_LEVEL. Rarer cards *start* at a higher level
##    (Common 1, Rare 3, Epic 6, Legendary 9), so they have fewer upgrades left.
##  - Upgrading from level L costs coins (by absolute level) and spare copies
##    (by how many upgrades the card has already had).
##  - Each upgrade grants Hangar XP, which feeds the Commander Level.
##  - Every level multiplies the card's bonuses by (1 + growth_per_level).

enum Category { ENGINE, ARMAMENT, AIRFRAME, GADGET }
enum Rarity { COMMON, RARE, EPIC, LEGENDARY }
enum GadgetType { NONE, NITRO_BOOST, SMOKE_SCREEN, REPAIR_PULSE }

const MAX_LEVEL: int = 13

## Level a freshly unlocked card starts at, indexed by Rarity.
const START_LEVEL_BY_RARITY: Array[int] = [1, 3, 6, 9]

## Spare copies consumed by the Nth upgrade of a card (index 0 = its first upgrade).
const COPIES_BY_UPGRADE_STEP: Array[int] = [2, 4, 10, 20, 50, 100, 200, 400, 800, 1000, 2000, 5000]

## Coins to upgrade *from* a level (index 0 = level 1 -> 2).
const COIN_COST_BY_LEVEL: Array[int] = [5, 20, 50, 150, 400, 1000, 2000, 4000, 8000, 20000, 50000, 100000]

## Hangar XP awarded for upgrading *from* a level (index 0 = level 1 -> 2).
const XP_REWARD_BY_LEVEL: Array[int] = [4, 5, 6, 10, 25, 50, 100, 200, 400, 600, 800, 1600]

const CATEGORY_NAMES: Array[String] = ["Engine", "Armament", "Airframe", "Gadget"]
const RARITY_NAMES: Array[String] = ["Common", "Rare", "Epic", "Legendary"]
## Frame colours: Common blue, Rare orange, Epic purple. Legendary is drawn as a
## rainbow by CardView; this entry is its fallback/base tint.
const RARITY_COLORS: Array[Color] = [
	Color("4aa3ff"), Color("ff9a2e"), Color("b455ff"), Color("ffe14a"),
]

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var category: Category = Category.ENGINE
@export var rarity: Rarity = Rarity.COMMON
## Short glyph drawn on the card face until real art exists.
@export var glyph: String = "?"
@export var icon: Texture2D
## Fraction added to every bonus per level above 1 (0.10 = +10% per level).
@export_range(0.0, 0.25, 0.005) var growth_per_level: float = 0.10

# All bonuses below are "level 1 equivalent" fractions: 0.05 means +5%.
@export_group("Engine")
@export_range(0.0, 0.5, 0.005) var top_speed_bonus: float = 0.0
@export_range(0.0, 1.0, 0.005) var climb_rate_bonus: float = 0.0
@export_range(0.0, 1.0, 0.005) var acceleration_bonus: float = 0.0

@export_group("Armament")
@export_range(-0.5, 1.0, 0.005) var fire_rate_bonus: float = 0.0
@export_range(0.0, 1.0, 0.005) var damage_bonus: float = 0.0
## Flat incendiary damage per second at level 1 (scales with level).
@export_range(0.0, 200.0, 0.5) var burn_dps: float = 0.0
@export_range(0.0, 10.0, 0.1) var burn_duration: float = 0.0

@export_group("Airframe")
@export_range(0.0, 0.5, 0.005) var turn_rate_bonus: float = 0.0
@export_range(0.0, 1.0, 0.005) var roll_rate_bonus: float = 0.0
@export_range(0.0, 1.0, 0.005) var max_hp_bonus: float = 0.0

@export_group("Gadget")
@export var gadget_type: GadgetType = GadgetType.NONE
@export_range(0.0, 120.0, 0.5) var gadget_cooldown: float = 0.0
@export_range(0.0, 30.0, 0.1) var gadget_duration: float = 0.0
## Level 1 strength. Nitro: +speed fraction. Repair pulse: heal fraction of max HP.
@export_range(0.0, 2.0, 0.01) var gadget_power: float = 0.0


# ---------------------------------------------------------------------------
# Upgrade maths
# ---------------------------------------------------------------------------

## Level this card has the moment it is first unlocked.
func start_level() -> int:
	return START_LEVEL_BY_RARITY[rarity]


func is_max_level(level: int) -> bool:
	return level >= MAX_LEVEL


## Spare copies needed to upgrade from [param level]. 0 when already maxed.
func copies_required(level: int) -> int:
	if is_max_level(level):
		return 0
	var step: int = clampi(level - start_level(), 0, COPIES_BY_UPGRADE_STEP.size() - 1)
	return COPIES_BY_UPGRADE_STEP[step]


## Coins needed to upgrade from [param level]. 0 when already maxed.
func coin_cost(level: int) -> int:
	if is_max_level(level):
		return 0
	return COIN_COST_BY_LEVEL[clampi(level - 1, 0, COIN_COST_BY_LEVEL.size() - 1)]


## Hangar XP granted by upgrading from [param level]. 0 when already maxed.
func xp_reward(level: int) -> int:
	if is_max_level(level):
		return 0
	return XP_REWARD_BY_LEVEL[clampi(level - 1, 0, XP_REWARD_BY_LEVEL.size() - 1)]


func can_upgrade(level: int, copies: int, coins: int) -> bool:
	if is_max_level(level):
		return false
	return copies >= copies_required(level) and coins >= coin_cost(level)


## Total copies a player must collect to take this card from unlock to MAX_LEVEL.
func total_copies_to_max() -> int:
	var total: int = 0
	for level: int in range(start_level(), MAX_LEVEL):
		total += copies_required(level)
	return total


# ---------------------------------------------------------------------------
# Stat scaling
# ---------------------------------------------------------------------------

## Multiplier applied to every bonus at [param level] (1.0 at level 1).
func level_multiplier(level: int) -> float:
	return pow(1.0 + growth_per_level, float(clampi(level, 1, MAX_LEVEL) - 1))


func scaled(bonus: float, level: int) -> float:
	return bonus * level_multiplier(level)


## Folds this card's bonuses (at [param level]) into [param stats].
## Percentage bonuses multiply, so cards stack without order mattering.
func apply_to(stats: PlaneStats, level: int) -> void:
	stats.top_speed *= 1.0 + scaled(top_speed_bonus, level)
	stats.climb_rate *= 1.0 + scaled(climb_rate_bonus, level)
	stats.acceleration *= 1.0 + scaled(acceleration_bonus, level)
	stats.fire_rate *= maxf(0.2, 1.0 + scaled(fire_rate_bonus, level))
	stats.bullet_damage *= 1.0 + scaled(damage_bonus, level)
	stats.turn_rate *= 1.0 + scaled(turn_rate_bonus, level)
	stats.pitch_rate *= 1.0 + scaled(turn_rate_bonus, level)
	stats.roll_rate *= 1.0 + scaled(roll_rate_bonus, level)
	stats.max_hp *= 1.0 + scaled(max_hp_bonus, level)
	if burn_dps > 0.0:
		stats.burn_dps += scaled(burn_dps, level)
		stats.burn_duration = maxf(stats.burn_duration, burn_duration)
	if category == Category.GADGET and gadget_type != GadgetType.NONE:
		stats.gadget_type = gadget_type
		stats.gadget_cooldown = gadget_cooldown
		stats.gadget_duration = gadget_duration
		stats.gadget_power = scaled(gadget_power, level)
		stats.gadget_name = display_name


## Human-readable stat lines for the card UI, e.g. "Top Speed +6.6%".
func stat_lines(level: int) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	_append_percent(lines, "Top Speed", top_speed_bonus, level)
	_append_percent(lines, "Climb", climb_rate_bonus, level)
	_append_percent(lines, "Acceleration", acceleration_bonus, level)
	_append_percent(lines, "Fire Rate", fire_rate_bonus, level)
	_append_percent(lines, "Damage", damage_bonus, level)
	if burn_dps > 0.0:
		lines.append("Burn %d/s for %.1fs" % [roundi(scaled(burn_dps, level)), burn_duration])
	_append_percent(lines, "Turn", turn_rate_bonus, level)
	_append_percent(lines, "Roll", roll_rate_bonus, level)
	_append_percent(lines, "Armor", max_hp_bonus, level)
	match gadget_type:
		GadgetType.NITRO_BOOST:
			lines.append("+%d%% speed for %.1fs" % [roundi(scaled(gadget_power, level) * 100.0), gadget_duration])
		GadgetType.SMOKE_SCREEN:
			lines.append("Untargetable for %.1fs" % gadget_duration)
		GadgetType.REPAIR_PULSE:
			lines.append("Squad heal %d%% HP" % roundi(scaled(gadget_power, level) * 100.0))
	if gadget_type != GadgetType.NONE:
		lines.append("Cooldown %ds" % roundi(gadget_cooldown))
	return lines


func category_name() -> String:
	return CATEGORY_NAMES[category]


func rarity_name() -> String:
	return RARITY_NAMES[rarity]


func rarity_color() -> Color:
	return RARITY_COLORS[rarity]


func _append_percent(lines: PackedStringArray, label: String, bonus: float, level: int) -> void:
	if is_zero_approx(bonus):
		return
	lines.append("%s %+.1f%%" % [label, scaled(bonus, level) * 100.0])
