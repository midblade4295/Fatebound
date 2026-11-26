extends Node
## Autoload "Profile": everything the player owns and has chosen.
##
## Coins, lifetime Hangar XP, per-card level/copies, the selected plane and the
## equipped loadout. All progression rules live in ComponentCard and
## CommanderProgression; this node only holds state, applies those rules and
## saves the result. Purely local and cosmetic: no real money, no server.

signal changed
signal commander_leveled_up(new_level: int)
signal card_upgraded(card: ComponentCard, new_level: int)

const DEFAULT_SAVE_PATH: String = "user://squadron_profile.json"
const SAVE_VERSION: int = 1
const STARTING_COINS: int = 300
const STARTER_SPARE_COPIES: int = 2

var pilot_name: String = "You"
var coins: int = STARTING_COINS
## Lifetime Hangar XP. The Commander Level is always derived from this.
var commander_xp: int = 0
var selected_plane_id: StringName = GameCatalog.STARTER_PLANE_ID
## One entry per card slot (always MAX_CARD_SLOTS long); &"" means empty.
var loadout: Array[StringName] = []
## Stick up = nose up by default; true flips it to flight-sim style.
var invert_pitch: bool = false
## Tests switch this off so they never touch the real save file.
var persistence_enabled: bool = true
var save_path: String = DEFAULT_SAVE_PATH

var _card_levels: Dictionary[StringName, int] = {}
var _card_copies: Dictionary[StringName, int] = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	reset_to_new_profile(false)
	load_profile()


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func commander_level() -> int:
	return CommanderProgression.level_for_total_xp(commander_xp)


func card_slot_count() -> int:
	return CommanderProgression.card_slot_count(commander_level())


func owns_card(card_id: StringName) -> bool:
	return _card_levels.has(card_id)


func card_level(card_id: StringName) -> int:
	return _card_levels.get(card_id, 0)


func card_copies(card_id: StringName) -> int:
	return _card_copies.get(card_id, 0)


func can_upgrade_card(card_id: StringName) -> bool:
	var card: ComponentCard = GameCatalog.find_card(card_id)
	if card == null or not owns_card(card_id):
		return false
	return card.can_upgrade(card_level(card_id), card_copies(card_id), coins)


func selected_plane() -> PlaneData:
	var plane: PlaneData = GameCatalog.find_plane(selected_plane_id)
	if plane == null or not plane.is_unlocked(commander_level()):
		plane = GameCatalog.find_plane(GameCatalog.STARTER_PLANE_ID)
	return plane


## Equipped cards in slot order; null for empty or still-locked slots.
func equipped_cards() -> Array[ComponentCard]:
	var cards: Array[ComponentCard] = []
	var level: int = commander_level()
	for slot: int in range(CommanderProgression.MAX_CARD_SLOTS):
		var card: ComponentCard = null
		if CommanderProgression.is_slot_unlocked(slot, level) and loadout[slot] != &"":
			card = GameCatalog.find_card(loadout[slot])
		cards.append(card)
	return cards


func equipped_card_levels() -> Array[int]:
	var levels: Array[int] = []
	for slot: int in range(CommanderProgression.MAX_CARD_SLOTS):
		levels.append(card_level(loadout[slot]))
	return levels


## The stat block the player's plane flies with right now.
func build_player_stats() -> PlaneStats:
	return selected_plane().build_stats(commander_level(), equipped_cards(), equipped_card_levels())


# ---------------------------------------------------------------------------
# Mutations
# ---------------------------------------------------------------------------

## Spends coins + copies to raise a card one level and awards Hangar XP.
## Returns false (and changes nothing) when the upgrade is not affordable.
func try_upgrade_card(card_id: StringName) -> bool:
	var card: ComponentCard = GameCatalog.find_card(card_id)
	if card == null or not owns_card(card_id):
		return false
	var level: int = card_level(card_id)
	if not card.can_upgrade(level, card_copies(card_id), coins):
		return false
	var level_before: int = commander_level()
	coins -= card.coin_cost(level)
	_card_copies[card_id] = card_copies(card_id) - card.copies_required(level)
	commander_xp += card.xp_reward(level)
	_card_levels[card_id] = level + 1
	card_upgraded.emit(card, level + 1)
	var level_after: int = commander_level()
	if level_after > level_before:
		commander_leveled_up.emit(level_after)
	_commit()
	return true


## Adds copies of a card, unlocking it at its rarity's start level if new.
func add_card_copies(card_id: StringName, amount: int) -> void:
	var card: ComponentCard = GameCatalog.find_card(card_id)
	if card == null or amount <= 0:
		return
	var remaining: int = amount
	if not owns_card(card_id):
		_card_levels[card_id] = card.start_level()
		_card_copies[card_id] = 0
		remaining -= 1  # The first copy is the card itself.
	_card_copies[card_id] = card_copies(card_id) + remaining
	_commit()


func add_coins(amount: int) -> void:
	coins = maxi(coins + amount, 0)
	_commit()


## Equips an owned card. Returns false if the slot is locked, the category does
## not fit the slot, or the card is already equipped elsewhere.
func equip_card(slot: int, card_id: StringName) -> bool:
	var card: ComponentCard = GameCatalog.find_card(card_id)
	if card == null or not owns_card(card_id):
		return false
	if not CommanderProgression.is_slot_unlocked(slot, commander_level()):
		return false
	if not CommanderProgression.slot_accepts(slot, card):
		return false
	var existing_slot: int = loadout.find(card_id)
	if existing_slot != -1 and existing_slot != slot:
		return false
	loadout[slot] = card_id
	_commit()
	return true


func unequip_slot(slot: int) -> void:
	if slot < 0 or slot >= loadout.size():
		return
	loadout[slot] = &""
	_commit()


## First open slot that would accept [param card], or -1.
func find_slot_for(card: ComponentCard) -> int:
	var level: int = commander_level()
	var fallback: int = -1
	for slot: int in range(CommanderProgression.MAX_CARD_SLOTS):
		if not CommanderProgression.is_slot_unlocked(slot, level):
			continue
		if not CommanderProgression.slot_accepts(slot, card):
			continue
		if loadout[slot] == &"":
			return slot
		if fallback == -1:
			fallback = slot
	return fallback


func select_plane(plane_id: StringName) -> bool:
	var plane: PlaneData = GameCatalog.find_plane(plane_id)
	if plane == null or not plane.is_unlocked(commander_level()):
		return false
	selected_plane_id = plane_id
	_commit()
	return true


## End-of-match payout: coins plus a small "crate" of card copies.
func grant_match_rewards(won: bool, kills: int) -> MatchRewards:
	var rewards: MatchRewards = MatchRewards.new()
	rewards.coins = 30 + 6 * maxi(kills, 0) + (50 if won else 0)
	coins += rewards.coins
	var drops: int = 3 if won else 2
	for _drop: int in range(drops):
		var card: ComponentCard = _roll_card_drop()
		var copies: int = _copies_for_drop(card)
		rewards.card_ids.append(card.id)
		rewards.card_counts.append(copies)
		add_card_copies(card.id, copies)
	_commit()
	return rewards


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func reset_to_new_profile(save_now: bool = true) -> void:
	coins = STARTING_COINS
	commander_xp = 0
	selected_plane_id = GameCatalog.STARTER_PLANE_ID
	invert_pitch = false
	_card_levels.clear()
	_card_copies.clear()
	loadout.clear()
	loadout.resize(CommanderProgression.MAX_CARD_SLOTS)
	loadout.fill(&"")
	for card_id: StringName in GameCatalog.STARTER_CARD_IDS:
		var card: ComponentCard = GameCatalog.find_card(card_id)
		_card_levels[card_id] = card.start_level()
		_card_copies[card_id] = STARTER_SPARE_COPIES
		var slot: int = find_slot_for(card)
		if slot != -1:
			loadout[slot] = card_id
	if save_now:
		_commit()
	else:
		changed.emit()


func save_profile() -> void:
	if not persistence_enabled:
		return
	var cards: Dictionary = {}
	for card_id: StringName in _card_levels:
		cards[String(card_id)] = {"level": _card_levels[card_id], "copies": card_copies(card_id)}
	var slots: Array[String] = []
	for card_id: StringName in loadout:
		slots.append(String(card_id))
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"pilot_name": pilot_name,
		"coins": coins,
		"commander_xp": commander_xp,
		"selected_plane_id": String(selected_plane_id),
		"invert_pitch": invert_pitch,
		"loadout": slots,
		"cards": cards,
	}
	var file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("Profile: could not write %s (error %d)" % [save_path, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(data, "\t"))


func load_profile() -> void:
	if not persistence_enabled or not FileAccess.file_exists(save_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not parsed is Dictionary:
		push_warning("Profile: save file is not valid JSON, keeping a fresh profile.")
		return
	var data: Dictionary = parsed
	pilot_name = _read_string(data, "pilot_name", pilot_name)
	coins = maxi(_read_int(data, "coins", coins), 0)
	commander_xp = maxi(_read_int(data, "commander_xp", commander_xp), 0)
	selected_plane_id = StringName(_read_string(data, "selected_plane_id", String(selected_plane_id)))
	invert_pitch = _read_bool(data, "invert_pitch", invert_pitch)
	var saved_cards: Variant = data.get("cards", {})
	if saved_cards is Dictionary:
		var card_dict: Dictionary = saved_cards
		for key: Variant in card_dict:
			var card: ComponentCard = GameCatalog.find_card(StringName(str(key)))
			var entry: Variant = card_dict[key]
			if card == null or not entry is Dictionary:
				continue  # Card removed from the game since this save was written.
			var entry_dict: Dictionary = entry
			_card_levels[card.id] = clampi(_read_int(entry_dict, "level", card.start_level()), card.start_level(), ComponentCard.MAX_LEVEL)
			_card_copies[card.id] = maxi(_read_int(entry_dict, "copies", 0), 0)
	var saved_loadout: Variant = data.get("loadout", [])
	if saved_loadout is Array:
		var slots: Array = saved_loadout
		for slot: int in range(mini(slots.size(), loadout.size())):
			var card_id: StringName = StringName(str(slots[slot]))
			var card: ComponentCard = GameCatalog.find_card(card_id)
			var valid: bool = card != null and owns_card(card_id) and CommanderProgression.slot_accepts(slot, card)
			loadout[slot] = card_id if valid else &""
	changed.emit()


# JSON hands everything back as Variant (and every number as float), so each
# field is type-checked on the way in instead of trusting the file.
func _read_int(data: Dictionary, key: String, fallback: int) -> int:
	var value: Variant = data.get(key)
	if value is float:
		var number: float = value
		return roundi(number)
	if value is int:
		var whole: int = value
		return whole
	return fallback


func _read_bool(data: Dictionary, key: String, fallback: bool) -> bool:
	var value: Variant = data.get(key)
	if value is bool:
		var flag: bool = value
		return flag
	return fallback


func _read_string(data: Dictionary, key: String, fallback: String) -> String:
	var value: Variant = data.get(key)
	if value is String:
		var text: String = value
		return text
	return fallback


func _commit() -> void:
	save_profile()
	changed.emit()


func _roll_card_drop() -> ComponentCard:
	# Rarity odds: Common 70%, Rare 22%, Epic 7%, Legendary 1%.
	var roll: float = _rng.randf()
	var rarity: ComponentCard.Rarity = ComponentCard.Rarity.COMMON
	if roll > 0.99:
		rarity = ComponentCard.Rarity.LEGENDARY
	elif roll > 0.92:
		rarity = ComponentCard.Rarity.EPIC
	elif roll > 0.70:
		rarity = ComponentCard.Rarity.RARE
	var pool: Array[ComponentCard] = []
	for card: ComponentCard in GameCatalog.CARDS:
		if card.rarity == rarity:
			pool.append(card)
	if pool.is_empty():
		pool = GameCatalog.CARDS.duplicate()
	return pool[_rng.randi_range(0, pool.size() - 1)]


func _copies_for_drop(card: ComponentCard) -> int:
	match card.rarity:
		ComponentCard.Rarity.COMMON:
			return _rng.randi_range(3, 8)
		ComponentCard.Rarity.RARE:
			return _rng.randi_range(1, 3)
		_:
			return 1
