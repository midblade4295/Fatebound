extends RefCounted
## What the game remembers between launches: the player's deck, the opponent's level, the
## settings and the record. Kept in user://profile.cfg; anything missing or no longer valid
## falls back to a default, so an old file never stops the game starting.

const PATH := "user://profile.cfg"
const STARTER := ["line_infantry", "skirmishers", "militia", "scouts", "heavy_cavalry", "field_gun", "fire", "rally"]
const DECK_SIZE := 8

var deck: Array = STARTER.duplicate()
var level: int = 1
var show_fps: bool = false
var sound: bool = true
var wins: int = 0
var losses: int = 0
var draws: int = 0
var persist: bool = true          # tests switch this off so they never touch the player's file


func load_from_disk(cards: Dictionary) -> void:
	var file := ConfigFile.new()
	if file.load(PATH) != OK:
		return
	var saved: Variant = file.get_value("game", "deck", [])
	if saved is Array and is_valid_deck(saved, cards):
		deck = (saved as Array).duplicate()
	level = clampi(int(file.get_value("game", "level", 1)), 0, 2)
	show_fps = bool(file.get_value("settings", "show_fps", false))
	sound = bool(file.get_value("settings", "sound", true))
	wins = maxi(0, int(file.get_value("record", "wins", 0)))
	losses = maxi(0, int(file.get_value("record", "losses", 0)))
	draws = maxi(0, int(file.get_value("record", "draws", 0)))


func save() -> void:
	if not persist:
		return
	var file := ConfigFile.new()
	file.set_value("game", "deck", deck)
	file.set_value("game", "level", level)
	file.set_value("settings", "show_fps", show_fps)
	file.set_value("settings", "sound", sound)
	file.set_value("record", "wins", wins)
	file.set_value("record", "losses", losses)
	file.set_value("record", "draws", draws)
	file.save(PATH)


## A deck is eight different cards that all exist, with at most one commander (the General
## or the Marshal).
static func is_valid_deck(candidate: Array, cards: Dictionary) -> bool:
	if candidate.size() != DECK_SIZE:
		return false
	var seen := {}
	var generals := 0
	for id: Variant in candidate:
		if not (id is String) or not cards.has(id) or seen.has(id):
			return false
		seen[id] = true
		if bool(cards[id].get("unique", false)):
			generals += 1
	return generals <= 1
