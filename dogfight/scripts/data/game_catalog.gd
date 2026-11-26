class_name GameCatalog
extends RefCounted
## Every card and plane in the game, preloaded so the list survives export
## (scanning res:// with DirAccess breaks once resources are remapped in a PCK).
## To add content: drop a .tres in resources/ and add one line here.

const PLANES: Array[PlaneData] = [
	preload("res://resources/planes/hurricane.tres"),
	preload("res://resources/planes/spitfire.tres"),
	preload("res://resources/planes/mustang.tres"),
]

const CARDS: Array[ComponentCard] = [
	preload("res://resources/cards/engine_merlin.tres"),
	preload("res://resources/cards/engine_turbo.tres"),
	preload("res://resources/cards/engine_griffon.tres"),
	preload("res://resources/cards/arm_brownings.tres"),
	preload("res://resources/cards/arm_hispano.tres"),
	preload("res://resources/cards/arm_incendiary.tres"),
	preload("res://resources/cards/arm_dragon.tres"),
	preload("res://resources/cards/air_clipped.tres"),
	preload("res://resources/cards/air_armor.tres"),
	preload("res://resources/cards/air_laminar.tres"),
	preload("res://resources/cards/gad_nitro.tres"),
	preload("res://resources/cards/gad_smoke.tres"),
	preload("res://resources/cards/gad_repair.tres"),
]

## Cards every new pilot owns, in loadout-slot order (engine, armament, gadget).
const STARTER_CARD_IDS: Array[StringName] = [&"engine_merlin", &"arm_brownings", &"gad_nitro"]
const STARTER_PLANE_ID: StringName = &"hurricane"


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


static func cards_in_category(category: ComponentCard.Category) -> Array[ComponentCard]:
	var result: Array[ComponentCard] = []
	for card: ComponentCard in CARDS:
		if card.category == category:
			result.append(card)
	return result


## Best plane a pilot of [param commander_level] has unlocked (used for bots).
static func best_plane_for_level(commander_level: int) -> PlaneData:
	var best: PlaneData = PLANES[0]
	for plane: PlaneData in PLANES:
		if plane.is_unlocked(commander_level) and plane.unlock_commander_level >= best.unlock_commander_level:
			best = plane
	return best
