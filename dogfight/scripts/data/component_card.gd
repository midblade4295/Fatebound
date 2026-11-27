class_name ComponentCard
extends Resource
## One collectible fitting: a real weapon or a real aircraft component.
##
## Every item is something that is bolted to the aeroplane and can be seen on
## it. A gun goes in a wing gun station, and a plane shows (and fires) exactly
## the guns that are fitted: one gun fitted is one gun on the wing. Propellers,
## engines, wingtips, armour and undercarriage each have their own mount.
## Nothing here is a gadget or a magic bonus.
##
## This resource is the shared *definition*. What a player owns (how many
## units, which Mark, how many spares) lives in PlayerProfile.
##
## Collecting and upgrading:
##  - A drop is one unit of the item. Units are what you fit: a gun station
##    needs one unit each, so four of a gun type lets you fit four. Other
##    mounts need one.
##  - Units beyond the most you could fit become spares.
##  - Spares and coins raise the item's Mark (Mk I to Mk V, as real weapons
##    and engines were developed). Each Mark improves what the item is good
##    at by `growth_per_mark`; its weight and its drawbacks do not change.
##  - Most items cost something: weight above all. Weight lengthens the
##    take-off run, raises the stalling speed and dulls climb and turn, so a
##    plane hung with four cannon and armour is not simply "better".

## Where on the aeroplane an item goes.
enum Slot { GUN, PROPELLER, ENGINE, WINGTIPS, ARMOUR, UNDERCARRIAGE }
enum Rarity { COMMON, RARE, EPIC, LEGENDARY }

const MAX_MARK: int = 5
const SLOT_NAMES: Array[String] = ["Gun", "Propeller", "Engine", "Wingtips", "Armour", "Undercarriage"]
## The most units of one item that can be fitted at once, by Slot.
const MAX_UNITS_BY_SLOT: Array[int] = [4, 1, 1, 1, 1, 1]
## Slots that may be left empty. A plane cannot fly without the others.
const OPTIONAL_SLOTS: Array[Slot] = [Slot.GUN, Slot.ARMOUR]
const RARITY_NAMES: Array[String] = ["Common", "Rare", "Epic", "Legendary"]
const MARK_NAMES: Array[String] = ["Mk I", "Mk II", "Mk III", "Mk IV", "Mk V"]
## Frame colours: Common blue, Rare orange, Epic purple. Legendary is drawn as a
## rainbow by CardView; this entry is its fallback/base tint.
const RARITY_COLORS: Array[Color] = [
	Color("4aa3ff"), Color("ff9a2e"), Color("b455ff"), Color("ffe14a"),
]
## Spares consumed to go from a Mark to the next (index 0 = Mk I -> Mk II),
## multiplied down for rarer items, which drop less often.
const SPARES_BY_MARK: Array[int] = [2, 4, 8, 16]
const SPARES_DIVISOR_BY_RARITY: Array[int] = [1, 2, 4, 8]
const COIN_COST_BY_MARK: Array[int] = [60, 250, 800, 2500]
const XP_REWARD_BY_MARK: Array[int] = [15, 40, 100, 250]

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var slot: Slot = Slot.GUN
@export var rarity: Rarity = Rarity.COMMON
## Short glyph drawn on the card face until real art exists.
@export var glyph: String = "?"
@export var icon: Texture2D
## Which pieces of the aircraft model this item shows (see PlaneVisual).
@export var model_variant: StringName = &""
## Added weight as a share of the bare aeroplane's (0.02 = 2% heavier).
@export_range(0.0, 0.2, 0.001) var weight: float = 0.0
## How much better each Mark above Mk I makes the item's benefits (0.04 = 4%).
@export_range(0.0, 0.1, 0.005) var growth_per_mark: float = 0.04

@export_group("Gun")
## Rounds per second from one gun.
@export_range(0.0, 30.0, 0.1) var fire_rate: float = 0.0
@export_range(0.0, 1000.0, 1.0) var damage: float = 0.0
## Muzzle velocity, m/s (game scale).
@export_range(0.0, 1000.0, 1.0) var muzzle_speed: float = 0.0
@export_range(0.0, 1500.0, 1.0) var gun_range: float = 0.0
@export_range(0.0, 5.0, 0.05) var spread_deg: float = 0.0
## One-shot samples for a single round; one is picked at random per round.
@export var gun_sounds: Array[AudioStream] = []
@export_range(0.5, 2.0, 0.01) var gun_pitch: float = 1.0

@export_group("Performance")
# Fractions: 0.05 = +5%, -0.03 = 3% worse. Marks scale only the positive ones.
@export_range(-0.5, 0.5, 0.005) var top_speed_bonus: float = 0.0
@export_range(-0.5, 1.0, 0.005) var climb_rate_bonus: float = 0.0
@export_range(-0.5, 1.0, 0.005) var acceleration_bonus: float = 0.0
@export_range(-0.5, 0.5, 0.005) var turn_rate_bonus: float = 0.0
@export_range(-0.5, 1.0, 0.005) var roll_rate_bonus: float = 0.0
## More wing (positive) lowers the stalling and take-off speed; less raises it.
@export_range(-0.5, 0.5, 0.005) var lift_bonus: float = 0.0

@export_group("Protection")
## How much more punishment every part of the airframe takes.
@export_range(0.0, 1.0, 0.005) var toughness_bonus: float = 0.0
## Share of a fuel leak that self-sealing tanks stop.
@export_range(0.0, 1.0, 0.01) var leak_reduction: float = 0.0
## How much harder a landing the undercarriage stands before it gives way.
@export_range(0.0, 1.0, 0.005) var gear_strength_bonus: float = 0.0


# ---------------------------------------------------------------------------
# Collecting and upgrading
# ---------------------------------------------------------------------------

func is_gun() -> bool:
	return slot == Slot.GUN


## The most units of this item that can be fitted at once.
func max_units() -> int:
	return MAX_UNITS_BY_SLOT[slot]


## Whether a plane may fly with nothing in this item's mount.
func is_optional() -> bool:
	return OPTIONAL_SLOTS.has(slot)


func is_max_mark(mark: int) -> bool:
	return mark >= MAX_MARK


## Spares needed to go from [param mark] to the next. 0 at the top Mark.
func spares_required(mark: int) -> int:
	if is_max_mark(mark):
		return 0
	var base: int = SPARES_BY_MARK[clampi(mark - 1, 0, SPARES_BY_MARK.size() - 1)]
	return maxi(ceili(float(base) / float(SPARES_DIVISOR_BY_RARITY[rarity])), 1)


## Coins needed to go from [param mark] to the next. 0 at the top Mark.
func coin_cost(mark: int) -> int:
	if is_max_mark(mark):
		return 0
	return COIN_COST_BY_MARK[clampi(mark - 1, 0, COIN_COST_BY_MARK.size() - 1)] * (int(rarity) + 1)


## Hangar XP granted for going from [param mark] to the next.
func xp_reward(mark: int) -> int:
	if is_max_mark(mark):
		return 0
	return XP_REWARD_BY_MARK[clampi(mark - 1, 0, XP_REWARD_BY_MARK.size() - 1)]


func can_upgrade(mark: int, spares: int, coins: int) -> bool:
	if is_max_mark(mark):
		return false
	return spares >= spares_required(mark) and coins >= coin_cost(mark)


## Spares needed in total to take this item from Mk I to the top Mark.
func total_spares_to_max() -> int:
	var total: int = 0
	for mark: int in range(1, MAX_MARK):
		total += spares_required(mark)
	return total


# ---------------------------------------------------------------------------
# What it does
# ---------------------------------------------------------------------------

## Multiplier on this item's benefits at [param mark] (1.0 at Mk I).
func mark_multiplier(mark: int) -> float:
	return 1.0 + growth_per_mark * float(clampi(mark, 1, MAX_MARK) - 1)


## A bonus at [param mark]: benefits grow with the Mark, drawbacks do not.
func scaled(bonus: float, mark: int) -> float:
	return bonus * mark_multiplier(mark) if bonus > 0.0 else bonus


## Damage of one round from this gun at [param mark].
func damage_at(mark: int) -> float:
	return damage * mark_multiplier(mark)


## Folds this item (at [param mark]) into [param stats]. Guns are not handled
## here: PlaneData.build_stats() puts each one in its station.
func apply_to(stats: PlaneStats, mark: int) -> void:
	stats.weight += weight
	stats.top_speed *= 1.0 + scaled(top_speed_bonus, mark)
	stats.climb_rate *= 1.0 + scaled(climb_rate_bonus, mark)
	stats.acceleration *= 1.0 + scaled(acceleration_bonus, mark)
	stats.turn_rate *= 1.0 + scaled(turn_rate_bonus, mark)
	stats.pitch_rate *= 1.0 + scaled(turn_rate_bonus, mark)
	stats.roll_rate *= 1.0 + scaled(roll_rate_bonus, mark)
	stats.lift *= 1.0 + scaled(lift_bonus, mark)
	stats.max_hp *= 1.0 + scaled(toughness_bonus, mark)
	stats.fuel_leak *= 1.0 - clampf(scaled(leak_reduction, mark), 0.0, 0.95)
	stats.gear_strength *= 1.0 + scaled(gear_strength_bonus, mark)


## Human-readable lines for the card UI, e.g. "Top speed +5.2%".
func stat_lines(mark: int) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if is_gun():
		lines.append("%d damage x %.1f rounds/s" % [roundi(damage_at(mark)), fire_rate])
		lines.append("Range %d m" % roundi(gun_range))
	_append_percent(lines, "Top speed", top_speed_bonus, mark)
	_append_percent(lines, "Climb", climb_rate_bonus, mark)
	_append_percent(lines, "Acceleration", acceleration_bonus, mark)
	_append_percent(lines, "Turn", turn_rate_bonus, mark)
	_append_percent(lines, "Roll", roll_rate_bonus, mark)
	_append_percent(lines, "Lift", lift_bonus, mark)
	_append_percent(lines, "Toughness", toughness_bonus, mark)
	if leak_reduction > 0.0:
		lines.append("Fuel leaks %d%% slower" % roundi(clampf(scaled(leak_reduction, mark), 0.0, 0.95) * 100.0))
	_append_percent(lines, "Undercarriage strength", gear_strength_bonus, mark)
	if weight > 0.0:
		lines.append("Weight +%.1f%%" % (weight * 100.0))
	if lines.is_empty():
		lines.append("Standard fit")
	return lines


func slot_name() -> String:
	return SLOT_NAMES[slot]


func rarity_name() -> String:
	return RARITY_NAMES[rarity]


func rarity_color() -> Color:
	return RARITY_COLORS[rarity]


static func mark_name(mark: int) -> String:
	return MARK_NAMES[clampi(mark, 1, MAX_MARK) - 1]


func _append_percent(lines: PackedStringArray, label: String, bonus: float, mark: int) -> void:
	if is_zero_approx(bonus):
		return
	lines.append("%s %+.1f%%" % [label, scaled(bonus, mark) * 100.0])
