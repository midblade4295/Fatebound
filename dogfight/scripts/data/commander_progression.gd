class_name CommanderProgression
extends RefCounted
## Commander Level ("King Level") rules. Pure static maths, no state: the
## player's total Hangar XP lives in PlayerProfile and everything else is
## derived from it here, so the level can never drift out of sync with the XP.

const MAX_LEVEL: int = 14

## Hangar XP needed to go from a level to the next (index 0 = level 1 -> 2).
const XP_TO_NEXT_BY_LEVEL: Array[int] = [
	20, 50, 100, 200, 400, 800, 1500, 2500, 4000, 6000, 9000, 14000, 20000,
]

## Every Commander Level above 1 adds this much to all planes.
const HP_BONUS_PER_LEVEL: float = 0.07
const SPEED_BONUS_PER_LEVEL: float = 0.01

## Number of wing gun stations. They are the first mounts, in this order:
## left inner, right inner, left outer, right outer.
const GUN_STATION_COUNT: int = 4
## Every place on the aeroplane something can be fitted.
const MOUNT_COUNT: int = 9
## What kind of item each mount takes.
const MOUNT_SLOTS: Array[ComponentCard.Slot] = [
	ComponentCard.Slot.GUN, ComponentCard.Slot.GUN, ComponentCard.Slot.GUN, ComponentCard.Slot.GUN,
	ComponentCard.Slot.PROPELLER, ComponentCard.Slot.ENGINE, ComponentCard.Slot.WINGTIPS,
	ComponentCard.Slot.ARMOUR, ComponentCard.Slot.UNDERCARRIAGE,
]
const MOUNT_NAMES: Array[String] = [
	"Left inner gun", "Right inner gun", "Left outer gun", "Right outer gun",
	"Propeller", "Engine", "Wingtips", "Armour", "Undercarriage",
]
## Short labels for the loadout tiles.
const MOUNT_LABELS: Array[String] = ["GUN L1", "GUN R1", "GUN L2", "GUN R2", "PROP", "ENGINE", "TIPS", "ARMOUR", "GEAR"]
## Commander Level at which each mount opens. The inner guns and the parts a
## plane cannot fly without are always open.
const MOUNT_UNLOCK_LEVELS: Array[int] = [1, 1, 3, 3, 1, 1, 1, 2, 1]


## Commander Level reached with [param total_xp] lifetime Hangar XP.
static func level_for_total_xp(total_xp: int) -> int:
	var level: int = 1
	var remaining: int = maxi(total_xp, 0)
	while level < MAX_LEVEL and remaining >= XP_TO_NEXT_BY_LEVEL[level - 1]:
		remaining -= XP_TO_NEXT_BY_LEVEL[level - 1]
		level += 1
	return level


## XP already earned inside the current level (the filled part of the XP bar).
static func xp_into_level(total_xp: int) -> int:
	var level: int = level_for_total_xp(total_xp)
	return maxi(total_xp, 0) - total_xp_for_level(level)


## XP needed to finish [param level]. 0 at MAX_LEVEL.
static func xp_to_next(level: int) -> int:
	if level >= MAX_LEVEL:
		return 0
	return XP_TO_NEXT_BY_LEVEL[clampi(level, 1, MAX_LEVEL - 1) - 1]


## Lifetime XP at which [param level] begins.
static func total_xp_for_level(level: int) -> int:
	var total: int = 0
	for index: int in range(clampi(level, 1, MAX_LEVEL) - 1):
		total += XP_TO_NEXT_BY_LEVEL[index]
	return total


## 0.0-1.0 progress through the current level (1.0 when maxed).
static func level_progress(total_xp: int) -> float:
	var level: int = level_for_total_xp(total_xp)
	var needed: int = xp_to_next(level)
	if needed <= 0:
		return 1.0
	return clampf(float(xp_into_level(total_xp)) / float(needed), 0.0, 1.0)


static func mount_unlock_level(mount: int) -> int:
	return MOUNT_UNLOCK_LEVELS[clampi(mount, 0, MOUNT_COUNT - 1)]


static func is_mount_unlocked(mount: int, level: int) -> bool:
	return mount >= 0 and mount < MOUNT_COUNT and level >= MOUNT_UNLOCK_LEVELS[mount]


## True when [param card] is the kind of item [param mount] takes.
static func mount_accepts(mount: int, card: ComponentCard) -> bool:
	return card != null and mount >= 0 and mount < MOUNT_COUNT and card.slot == MOUNT_SLOTS[mount]


static func is_gun_station(mount: int) -> bool:
	return mount >= 0 and mount < GUN_STATION_COUNT


## The first mount that takes items of [param slot] (the only one, except for guns).
static func mount_for_slot(slot: ComponentCard.Slot) -> int:
	return MOUNT_SLOTS.find(slot)


static func mount_name(mount: int) -> String:
	return MOUNT_NAMES[clampi(mount, 0, MOUNT_COUNT - 1)]


static func mount_label(mount: int) -> String:
	return MOUNT_LABELS[clampi(mount, 0, MOUNT_COUNT - 1)]


static func hp_multiplier(level: int) -> float:
	return 1.0 + HP_BONUS_PER_LEVEL * float(clampi(level, 1, MAX_LEVEL) - 1)


static func speed_multiplier(level: int) -> float:
	return 1.0 + SPEED_BONUS_PER_LEVEL * float(clampi(level, 1, MAX_LEVEL) - 1)
