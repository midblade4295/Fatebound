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
## units and which Mark) lives in PlayerProfile.
##
## Buying and upgrading:
##  - Items are bought with gold, one unit at a time. Units are what you fit:
##    a gun station needs one unit each, so four of a gun type lets you fit
##    four. Other mounts need one. Nobody can own more than could be fitted.
##  - Gold also raises an item's Mark (Mk I to Mk V, as real weapons and
##    engines were developed). Each Mark improves what the item is good at
##    by `growth_per_mark`; its weight and its drawbacks do not change.
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
## What one unit costs in gold, by Rarity.
const PRICE_BY_RARITY: Array[int] = [150, 450, 1100, 2500]
## Gold to go from a Mark to the next (index 0 = Mk I -> Mk II), times the
## item's rarity rank (Common x1 .. Legendary x4).
const UPGRADE_COST_BY_MARK: Array[int] = [60, 250, 800, 2500]

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
## Muzzle velocity, m/s.
@export_range(0.0, 1000.0, 1.0) var muzzle_speed: float = 0.0
@export_range(0.0, 1500.0, 1.0) var gun_range: float = 0.0
@export_range(0.0, 5.0, 0.05) var spread_deg: float = 0.0
## One-shot samples for a single round; one is picked at random per round.
@export var gun_sounds: Array[AudioStream] = []
@export_range(0.5, 2.0, 0.01) var gun_pitch: float = 1.0

@export_group("Performance")
# Fractions: 0.05 = +5%, -0.03 = 3% worse. Marks scale only the positive ones.
# Each is a real change to the aeroplane; what it does to the flying follows
# from the flight model (see PlaneData._finish_stats).
## Level top speed (a cleaner, less draggy fitting).
@export_range(-0.5, 0.5, 0.005) var top_speed_bonus: float = 0.0
## Engine power: climb, acceleration and a little top speed.
@export_range(-0.5, 1.0, 0.005) var climb_rate_bonus: float = 0.0
## The propeller's pull at low speed: the take-off run and slow climbing.
@export_range(-0.5, 1.0, 0.005) var acceleration_bonus: float = 0.0
## The most lift the wing makes before it stalls: how hard it can turn.
@export_range(-0.5, 0.5, 0.005) var turn_rate_bonus: float = 0.0
## Aileron power: how fast it rolls.
@export_range(-0.5, 1.0, 0.005) var roll_rate_bonus: float = 0.0
## Wing span. More wing (positive) lowers the stalling and take-off speed and
## the drag of a hard turn; less raises them.
@export_range(-0.5, 0.5, 0.005) var lift_bonus: float = 0.0
## Metres added to the height up to which the engine holds full power (a
## better supercharger). Not scaled by Mark.
@export_range(0.0, 4000.0, 50.0) var altitude_bonus: float = 0.0

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


## Gold to buy one unit of this item: one gun, one propeller, one engine.
func price() -> int:
	return PRICE_BY_RARITY[rarity]


## Gold to take this item from [param mark] to the next. 0 at the top Mark.
func upgrade_cost(mark: int) -> int:
	if is_max_mark(mark):
		return 0
	return UPGRADE_COST_BY_MARK[clampi(mark - 1, 0, UPGRADE_COST_BY_MARK.size() - 1)] * (int(rarity) + 1)


func can_upgrade(mark: int, gold: int) -> bool:
	return not is_max_mark(mark) and gold >= upgrade_cost(mark)


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
	stats.speed_factor *= 1.0 + scaled(top_speed_bonus, mark)
	stats.power_factor *= 1.0 + scaled(climb_rate_bonus, mark)
	stats.static_thrust *= 1.0 + scaled(acceleration_bonus, mark)
	stats.max_lift *= 1.0 + scaled(turn_rate_bonus, mark)
	stats.roll_power *= 1.0 + scaled(roll_rate_bonus, mark)
	stats.wing_factor *= 1.0 + scaled(lift_bonus, mark)
	stats.critical_altitude += altitude_bonus
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
	_append_percent(lines, "Engine power", climb_rate_bonus, mark)
	_append_percent(lines, "Take-off thrust", acceleration_bonus, mark)
	_append_percent(lines, "Wing lift", turn_rate_bonus, mark)
	_append_percent(lines, "Roll", roll_rate_bonus, mark)
	_append_percent(lines, "Wing span", lift_bonus, mark)
	if altitude_bonus > 0.0:
		lines.append("Full power %d m higher" % roundi(altitude_bonus))
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
