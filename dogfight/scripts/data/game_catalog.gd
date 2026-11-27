class_name GameCatalog
extends RefCounted
## Every item and plane in the game, preloaded so the list survives export
## (scanning res:// with DirAccess breaks once resources are remapped in a PCK).
## To add content: drop a .tres in resources/ and add one line here.

const PLANES: Array[PlaneData] = [
	preload("res://resources/planes/hurricane.tres"),
	preload("res://resources/planes/spitfire.tres"),
	preload("res://resources/planes/mustang.tres"),
]

const CARDS: Array[ComponentCard] = [
	preload("res://resources/cards/gun_browning_303.tres"),
	preload("res://resources/cards/gun_browning_m2.tres"),
	preload("res://resources/cards/gun_hispano_20mm.tres"),
	preload("res://resources/cards/prop_three_blade.tres"),
	preload("res://resources/cards/prop_four_blade.tres"),
	preload("res://resources/cards/engine_merlin_iii.tres"),
	preload("res://resources/cards/engine_merlin_61.tres"),
	preload("res://resources/cards/engine_griffon_65.tres"),
	preload("res://resources/cards/tips_standard.tres"),
	preload("res://resources/cards/tips_clipped.tres"),
	preload("res://resources/cards/tips_extended.tres"),
	preload("res://resources/cards/armour_seat.tres"),
	preload("res://resources/cards/armour_full.tres"),
	preload("res://resources/cards/gear_standard.tres"),
	preload("res://resources/cards/gear_reinforced.tres"),
]
## What a factory-fresh plane is fitted with, by mount (see
## CommanderProgression.MOUNT_*): two .303s in the inner stations and the
## standard propeller, engine, wingtips and undercarriage. &"" = empty.
const STOCK_FITTING_IDS: Array[StringName] = [
	&"gun_browning_303", &"gun_browning_303", &"", &"",
	&"prop_three_blade", &"engine_merlin_iii", &"tips_standard", &"", &"gear_standard",
]
const STARTER_PLANE_ID: StringName = &"hurricane"


## The stock fittings as items, in mount order (null for an empty mount).
static func stock_fittings() -> Array[ComponentCard]:
	var fittings: Array[ComponentCard] = []
	for card_id: StringName in STOCK_FITTING_IDS:
		fittings.append(find_card(card_id))
	return fittings


## Mk I for every mount: the Marks that go with stock_fittings().
static func stock_marks() -> Array[int]:
	var marks: Array[int] = []
	marks.resize(STOCK_FITTING_IDS.size())
	marks.fill(1)
	return marks


## The standard item for a slot a plane cannot fly without, or null.
static func stock_card_for(slot: ComponentCard.Slot) -> ComponentCard:
	var mount: int = CommanderProgression.mount_for_slot(slot)
	if slot == ComponentCard.Slot.GUN or mount < 0:
		return null
	return find_card(STOCK_FITTING_IDS[mount])


static func find_card(card_id: StringName) -> ComponentCard:
	for card: ComponentCard in CARDS:
		if card.id == card_id:
			return card
	return null


static func find_plane(plane_id: StringName) -> PlaneData:
	for plane: PlaneData in PLANES:
		if plane.id == plane_id:
			return plane
	return null


static func cards_in_slot(slot: ComponentCard.Slot) -> Array[ComponentCard]:
	var result: Array[ComponentCard] = []
	for card: ComponentCard in CARDS:
		if card.slot == slot:
			result.append(card)
	return result


## Best plane a pilot of [param commander_level] has unlocked (used for bots).
static func best_plane_for_level(commander_level: int) -> PlaneData:
	var best: PlaneData = PLANES[0]
	for plane: PlaneData in PLANES:
		if plane.is_unlocked(commander_level) and plane.unlock_commander_level >= best.unlock_commander_level:
			best = plane
	return best
