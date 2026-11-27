extends Node
## Autoload "Profile": everything the player owns and has chosen.
##
## Coins, lifetime Hangar XP, the items collected (how many units of each, how
## many spares, which Mark), the selected plane and what is fitted to each of
## its mounts. All the rules live in ComponentCard and CommanderProgression;
## this node only holds state, applies those rules and saves the result.
## Purely local: no real money, no server.

signal changed
signal commander_leveled_up(new_level: int)
signal card_upgraded(card: ComponentCard, new_mark: int)

const DEFAULT_SAVE_PATH: String = "user://squadron_profile.json"
## 2: items are fittings with units, spares and Marks (1 was levelled cards).
const SAVE_VERSION: int = 2
const STARTING_COINS: int = 300

var pilot_name: String = "You"
var coins: int = STARTING_COINS
## Lifetime Hangar XP. The Commander Level is always derived from this.
var commander_xp: int = 0
var selected_plane_id: StringName = GameCatalog.STARTER_PLANE_ID
## What is fitted to each mount (always MOUNT_COUNT long); &"" means empty.
var loadout: Array[StringName] = []
## Stick up = nose up by default; true flips it to flight-sim style.
var invert_pitch: bool = false
## Tests switch this off so they never touch the real save file.
var persistence_enabled: bool = true
var save_path: String = DEFAULT_SAVE_PATH

## Units of each item that can be fitted (never more than the item's max_units).
var _units: Dictionary[StringName, int] = {}
## Units beyond that: what Mark upgrades are paid in.
var _spares: Dictionary[StringName, int] = {}
var _marks: Dictionary[StringName, int] = {}
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


func owns_card(card_id: StringName) -> bool:
	return card_units(card_id) > 0


## How many of an item the player has to fit (a gun station takes one each).
func card_units(card_id: StringName) -> int:
	return _units.get(card_id, 0)


## Extra units, good only for raising the item's Mark.
func card_spares(card_id: StringName) -> int:
	return _spares.get(card_id, 0)


## The item's Mark, 1 (Mk I) to ComponentCard.MAX_MARK. 0 if not owned.
func card_mark(card_id: StringName) -> int:
	return _marks.get(card_id, 1) if owns_card(card_id) else 0


## How many mounts currently hold this item.
func fitted_count(card_id: StringName) -> int:
	return loadout.count(card_id) if card_id != &"" else 0


func can_upgrade_card(card_id: StringName) -> bool:
	var card: ComponentCard = GameCatalog.find_card(card_id)
	if card == null or not owns_card(card_id):
		return false
	return card.can_upgrade(card_mark(card_id), card_spares(card_id), coins)


func selected_plane() -> PlaneData:
	var plane: PlaneData = GameCatalog.find_plane(selected_plane_id)
	if plane == null or not plane.is_unlocked(commander_level()):
		plane = GameCatalog.find_plane(GameCatalog.STARTER_PLANE_ID)
	return plane


## What is fitted, in mount order; null for empty or still-locked mounts.
func equipped_cards() -> Array[ComponentCard]:
	var cards: Array[ComponentCard] = []
	var level: int = commander_level()
	for mount: int in range(CommanderProgression.MOUNT_COUNT):
		var card: ComponentCard = null
		if CommanderProgression.is_mount_unlocked(mount, level) and loadout[mount] != &"":
			card = GameCatalog.find_card(loadout[mount])
		cards.append(card)
	return cards


## The Mark of whatever is in each mount (1 for an empty one).
func equipped_card_marks() -> Array[int]:
	var marks: Array[int] = []
	for mount: int in range(CommanderProgression.MOUNT_COUNT):
		marks.append(maxi(card_mark(loadout[mount]), 1))
	return marks


## The stat block the player's plane flies with right now.
func build_player_stats() -> PlaneStats:
	return selected_plane().build_stats(commander_level(), equipped_cards(), equipped_card_marks())


# ---------------------------------------------------------------------------
# Mutations
# ---------------------------------------------------------------------------

## Spends coins and spares to raise an item one Mark and awards Hangar XP.
## Returns false (and changes nothing) when the upgrade is not affordable.
func try_upgrade_card(card_id: StringName) -> bool:
	var card: ComponentCard = GameCatalog.find_card(card_id)
	if card == null or not owns_card(card_id):
		return false
	var mark: int = card_mark(card_id)
	if not card.can_upgrade(mark, card_spares(card_id), coins):
		return false
	var level_before: int = commander_level()
	coins -= card.coin_cost(mark)
	_spares[card_id] = card_spares(card_id) - card.spares_required(mark)
	commander_xp += card.xp_reward(mark)
	_marks[card_id] = mark + 1
	card_upgraded.emit(card, mark + 1)
	var level_after: int = commander_level()
	if level_after > level_before:
		commander_leveled_up.emit(level_after)
	_commit()
	return true


## Adds units of an item. Up to the most that could be fitted they are units
## to fit; any more become spares.
func add_card_units(card_id: StringName, amount: int) -> void:
	var card: ComponentCard = GameCatalog.find_card(card_id)
	if card == null or amount <= 0:
		return
	if not _marks.has(card_id):
		_marks[card_id] = 1
	var room: int = maxi(card.max_units() - card_units(card_id), 0)
	var fitted: int = mini(amount, room)
	_units[card_id] = card_units(card_id) + fitted
	_spares[card_id] = card_spares(card_id) + amount - fitted
	_commit()


func add_coins(amount: int) -> void:
	coins = maxi(coins + amount, 0)
	_commit()


## Fits an owned item to a mount. Returns false if the mount is locked, the
## item does not go there, or every unit of it is already fitted elsewhere.
func equip_card(mount: int, card_id: StringName) -> bool:
	var card: ComponentCard = GameCatalog.find_card(card_id)
	if card == null or not owns_card(card_id):
		return false
	if not CommanderProgression.is_mount_unlocked(mount, commander_level()):
		return false
	if not CommanderProgression.mount_accepts(mount, card):
		return false
	var fitted_elsewhere: int = fitted_count(card_id) - (1 if loadout[mount] == card_id else 0)
	if fitted_elsewhere >= card_units(card_id):
		return false
	loadout[mount] = card_id
	_commit()
	return true


## Takes whatever is in a mount off. Returns false for a mount the plane cannot
## fly with empty (propeller, engine, wingtips, undercarriage): swap those.
func unequip_mount(mount: int) -> bool:
	if mount < 0 or mount >= loadout.size() or loadout[mount] == &"":
		return false
	var card: ComponentCard = GameCatalog.find_card(loadout[mount])
	if card != null and not card.is_optional():
		return false
	loadout[mount] = &""
	_commit()
	return true


## Where [param card] would go if fitted now: an empty open mount of its kind,
## else one holding something different, else -1 (nowhere, or no unit spare).
func find_mount_for(card: ComponentCard) -> int:
	if card == null or fitted_count(card.id) >= card_units(card.id):
		return -1
	var level: int = commander_level()
	var replace: int = -1
	for mount: int in range(CommanderProgression.MOUNT_COUNT):
		if not CommanderProgression.is_mount_unlocked(mount, level) or not CommanderProgression.mount_accepts(mount, card):
			continue
		if loadout[mount] == &"":
			return mount
		if replace == -1 and loadout[mount] != card.id:
			replace = mount
	return replace


func select_plane(plane_id: StringName) -> bool:
	var plane: PlaneData = GameCatalog.find_plane(plane_id)
	if plane == null or not plane.is_unlocked(commander_level()):
		return false
	selected_plane_id = plane_id
	_commit()
	return true


## End-of-match payout: coins plus a small crate of items.
func grant_match_rewards(won: bool, kills: int) -> MatchRewards:
	var rewards: MatchRewards = MatchRewards.new()
	rewards.coins = 30 + 6 * maxi(kills, 0) + (50 if won else 0)
	coins += rewards.coins
	var drops: int = 3 if won else 2
	for _drop: int in range(drops):
		var card: ComponentCard = _roll_card_drop()
		var units: int = _units_for_drop(card)
		rewards.card_ids.append(card.id)
		rewards.card_counts.append(units)
		add_card_units(card.id, units)
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
	_units.clear()
	_spares.clear()
	_marks.clear()
	_fit_stock()
	if save_now:
		_commit()
	else:
		changed.emit()


func save_profile() -> void:
	if not persistence_enabled:
		return
	var items: Dictionary = {}
	for card_id: StringName in _units:
		items[String(card_id)] = {"units": card_units(card_id), "spares": card_spares(card_id), "mark": card_mark(card_id)}
	var mounts: Array[String] = []
	for card_id: StringName in loadout:
		mounts.append(String(card_id))
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"pilot_name": pilot_name,
		"coins": coins,
		"commander_xp": commander_xp,
		"selected_plane_id": String(selected_plane_id),
		"invert_pitch": invert_pitch,
		"loadout": mounts,
		"items": items,
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
	# A version 1 save holds the old levelled cards, which no longer exist.
	# Coins, XP and the chosen plane carry over; the fittings start from stock.
	if _read_int(data, "version", 1) >= 2:
		var saved_items: Variant = data.get("items", {})
		if saved_items is Dictionary:
			var item_dict: Dictionary = saved_items
			for key: Variant in item_dict:
				var card: ComponentCard = GameCatalog.find_card(StringName(str(key)))
				var entry: Variant = item_dict[key]
				if card == null or not entry is Dictionary:
					continue  # Item removed from the game since this save was written.
				var entry_dict: Dictionary = entry
				var units: int = clampi(_read_int(entry_dict, "units", 0), 0, card.max_units())
				if units <= 0:
					continue
				_units[card.id] = maxi(units, card_units(card.id))
				_spares[card.id] = maxi(_read_int(entry_dict, "spares", 0), 0)
				_marks[card.id] = clampi(_read_int(entry_dict, "mark", 1), 1, ComponentCard.MAX_MARK)
		var saved_loadout: Variant = data.get("loadout", [])
		if saved_loadout is Array:
			var mounts: Array = saved_loadout
			loadout.fill(&"")
			for mount: int in range(mini(mounts.size(), loadout.size())):
				var card_id: StringName = StringName(str(mounts[mount]))
				var card: ComponentCard = GameCatalog.find_card(card_id)
				if card != null and CommanderProgression.mount_accepts(mount, card) and fitted_count(card_id) < card_units(card_id):
					loadout[mount] = card_id
	_repair_loadout()
	changed.emit()


## Gives the player the stock items and fits them: what every pilot starts with.
func _fit_stock() -> void:
	loadout.clear()
	loadout.resize(CommanderProgression.MOUNT_COUNT)
	loadout.fill(&"")
	for mount: int in range(CommanderProgression.MOUNT_COUNT):
		var card_id: StringName = GameCatalog.STOCK_FITTING_IDS[mount]
		if card_id == &"":
			continue
		_units[card_id] = card_units(card_id) + 1
		_marks[card_id] = 1
		loadout[mount] = card_id


## Makes sure nothing is missing that a plane cannot fly without: any such
## mount found empty gets the standard item back (which every pilot owns).
func _repair_loadout() -> void:
	for mount: int in range(CommanderProgression.MOUNT_COUNT):
		if loadout[mount] != &"":
			continue
		var stock: ComponentCard = GameCatalog.stock_card_for(CommanderProgression.MOUNT_SLOTS[mount])
		if stock == null:
			continue
		if not owns_card(stock.id):
			_units[stock.id] = 1
			_marks[stock.id] = 1
		loadout[mount] = stock.id


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
	# Rarity odds: Common 70%, Rare 22%, Epic 7%, Legendary 1% (falls back to
	# any item while there are no Legendary ones).
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


## A drop is one of the thing: one gun, one propeller. Common items sometimes
## come in pairs.
func _units_for_drop(card: ComponentCard) -> int:
	if card.rarity == ComponentCard.Rarity.COMMON:
		return _rng.randi_range(1, 2)
	return 1
