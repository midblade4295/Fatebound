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

const MIN_CARD_SLOTS: int = 3
const MAX_CARD_SLOTS: int = 5
## Commander Level at which each card slot opens (slots 1-3 are always open).
const SLOT_UNLOCK_LEVELS: Array[int] = [1, 1, 1, 4, 8]
## Slot index reserved for "any passive category".
const WILDCARD_CATEGORY: int = -1
## Which ComponentCard.Category each slot accepts.
const SLOT_CATEGORIES: Array[int] = [
	ComponentCard.Category.ENGINE,
	ComponentCard.Category.ARMAMENT,
	ComponentCard.Category.GADGET,
	ComponentCard.Category.AIRFRAME,
	WILDCARD_CATEGORY,
]


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


## Number of equipped-card slots open at [param level] (3 to 5).
static func card_slot_count(level: int) -> int:
	var count: int = 0
	for unlock_level: int in SLOT_UNLOCK_LEVELS:
		if level >= unlock_level:
			count += 1
	return clampi(count, MIN_CARD_SLOTS, MAX_CARD_SLOTS)


static func slot_unlock_level(slot_index: int) -> int:
	return SLOT_UNLOCK_LEVELS[clampi(slot_index, 0, MAX_CARD_SLOTS - 1)]


static func is_slot_unlocked(slot_index: int, level: int) -> bool:
	return slot_index >= 0 and slot_index < MAX_CARD_SLOTS and level >= SLOT_UNLOCK_LEVELS[slot_index]


## True when [param card] may be equipped in [param slot_index]. The wildcard
## slot takes any passive card but never a second gadget (one gadget button).
static func slot_accepts(slot_index: int, card: ComponentCard) -> bool:
	if card == null or slot_index < 0 or slot_index >= MAX_CARD_SLOTS:
		return false
	var wanted: int = SLOT_CATEGORIES[slot_index]
	if wanted == WILDCARD_CATEGORY:
		return card.category != ComponentCard.Category.GADGET
	return int(card.category) == wanted


static func slot_label(slot_index: int) -> String:
	var wanted: int = SLOT_CATEGORIES[clampi(slot_index, 0, MAX_CARD_SLOTS - 1)]
	if wanted == WILDCARD_CATEGORY:
		return "Wildcard"
	return ComponentCard.CATEGORY_NAMES[wanted]


static func hp_multiplier(level: int) -> float:
	return 1.0 + HP_BONUS_PER_LEVEL * float(clampi(level, 1, MAX_LEVEL) - 1)


static func speed_multiplier(level: int) -> float:
	return 1.0 + SPEED_BONUS_PER_LEVEL * float(clampi(level, 1, MAX_LEVEL) - 1)
