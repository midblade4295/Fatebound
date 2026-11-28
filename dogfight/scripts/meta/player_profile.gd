extends Node
## Autoload "Profile": everything the player owns and has chosen.
##
## Gold, the planes bought, the items bought (how many units of each and
## which Mark), the selected plane, what is fitted to each of its mounts, and
## whether sorties are insured. There is no experience and there are no
## levels: a pilot has what they have paid for. All the rules live in
## ComponentCard, PlaneData and PlaneMounts; this node only holds state,
## applies those rules and saves the result. Purely local: no real money, no
## server.
##
## Gold comes from sorties (MatchManager5v5): every kill adds to a bounty the
## pilot carries, and bank_bounty() pays it in when they land and cash out.
## A pilot who is killed loses the bounty and, unless the sortie was insured,
## the plane: lose_plane() takes it away and it has to be bought again.
## What was fitted to it is never lost.

signal changed
signal card_upgraded(card: ComponentCard, new_mark: int)

const DEFAULT_SAVE_PATH: String = "user://squadron_profile.json"
## 3: gold only, planes are bought (2 had Hangar XP and spares; 1 levelled cards).
const SAVE_VERSION: int = 3
const STARTING_GOLD: int = 500
## Insuring a sortie costs this share of the plane's price, paid at take-off
## whether or not the plane comes back.
const INSURANCE_RATE: float = 0.15
## Hangar XP at which older saves had unlocked each plane: those pilots keep them.
const LEGACY_PLANE_XP: Dictionary[StringName, int] = {&"spitfire": 70, &"mustang": 770}

var pilot_name: String = "You"
var gold: int = STARTING_GOLD
var selected_plane_id: StringName = GameCatalog.STARTER_PLANE_ID
## What is fitted to each mount (always MOUNT_COUNT long); &"" means empty.
var loadout: Array[StringName] = []
## Whether to insure each sortie (when the plane is worth insuring and the
## premium can be paid).
var insure_sorties: bool = false
## Stick up = nose up by default; true flips it to flight-sim style.
var invert_pitch: bool = false
## Tests switch this off so they never touch the real save file.
var persistence_enabled: bool = true
var save_path: String = DEFAULT_SAVE_PATH

## The planes the player has bought and still has (free ones are never listed).
var _planes: Dictionary[StringName, bool] = {}
## Units of each item (never more than the item's max_units), and its Mark.
var _units: Dictionary[StringName, int] = {}
var _marks: Dictionary[StringName, int] = {}


func _ready() -> void:
	reset_to_new_profile(false)
	load_profile()


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func owns_card(card_id: StringName) -> bool:
	return card_units(card_id) > 0


## How many of an item the player has to fit (a gun station takes one each).
func card_units(card_id: StringName) -> int:
	return _units.get(card_id, 0)


## The item's Mark, 1 (Mk I) to ComponentCard.MAX_MARK. 0 if not owned.
func card_mark(card_id: StringName) -> int:
	return _marks.get(card_id, 1) if owns_card(card_id) else 0


## How many mounts currently hold this item.
func fitted_count(card_id: StringName) -> int:
	return loadout.count(card_id) if card_id != &"" else 0


## Whether one more unit of an item can be bought: there is room for it on a
## plane and the gold to pay for it.
func can_buy_card(card_id: StringName) -> bool:
	var card: ComponentCard = GameCatalog.find_card(card_id)
	return card != null and card_units(card_id) < card.max_units() and gold >= card.price()


func can_upgrade_card(card_id: StringName) -> bool:
	var card: ComponentCard = GameCatalog.find_card(card_id)
	if card == null or not owns_card(card_id):
		return false
	return card.can_upgrade(card_mark(card_id), gold)


## Free planes are everyone's; the rest have to be bought (and bought again
## if they are lost).
func owns_plane(plane_id: StringName) -> bool:
	var plane: PlaneData = GameCatalog.find_plane(plane_id)
	return plane != null and (plane.is_free() or _planes.has(plane_id))


func can_buy_plane(plane_id: StringName) -> bool:
	var plane: PlaneData = GameCatalog.find_plane(plane_id)
	return plane != null and not owns_plane(plane_id) and gold >= plane.price


func selected_plane() -> PlaneData:
	var plane: PlaneData = GameCatalog.find_plane(selected_plane_id)
	if plane == null or not owns_plane(plane.id):
		plane = GameCatalog.find_plane(GameCatalog.STARTER_PLANE_ID)
	return plane


## What insuring one sortie in [param plane] costs. 0 for a free plane, which
## needs none.
func insurance_cost(plane: PlaneData) -> int:
	if plane == null or plane.is_free():
		return 0
	return ceili(float(plane.price) * INSURANCE_RATE)


## What is fitted, in mount order; null for an empty mount.
func equipped_cards() -> Array[ComponentCard]:
	var cards: Array[ComponentCard] = []
	for mount: int in range(PlaneMounts.MOUNT_COUNT):
		cards.append(GameCatalog.find_card(loadout[mount]) if loadout[mount] != &"" else null)
	return cards


## The Mark of whatever is in each mount (1 for an empty one).
func equipped_card_marks() -> Array[int]:
	var marks: Array[int] = []
	for mount: int in range(PlaneMounts.MOUNT_COUNT):
		marks.append(maxi(card_mark(loadout[mount]), 1))
	return marks


## The stat block the player's plane flies with right now.
func build_player_stats() -> PlaneStats:
	return selected_plane().build_stats(equipped_cards(), equipped_card_marks())


# ---------------------------------------------------------------------------
# Buying
# ---------------------------------------------------------------------------

## Buys a plane (or buys back one that was lost) and selects it. Returns
## false, and changes nothing, if it is already owned or cannot be afforded.
func try_buy_plane(plane_id: StringName) -> bool:
	if not can_buy_plane(plane_id):
		return false
	gold -= GameCatalog.find_plane(plane_id).price
	_planes[plane_id] = true
	selected_plane_id = plane_id
	_commit()
	return true


## Buys one unit of an item: one gun, one propeller. Returns false if no
## more of it could be fitted or it cannot be afforded.
func try_buy_card(card_id: StringName) -> bool:
	if not can_buy_card(card_id):
		return false
	gold -= GameCatalog.find_card(card_id).price()
	add_card_units(card_id, 1)
	return true


## Spends gold to raise an item one Mark. Returns false (and changes
## nothing) when it cannot be afforded or is already at the top Mark.
func try_upgrade_card(card_id: StringName) -> bool:
	var card: ComponentCard = GameCatalog.find_card(card_id)
	if card == null or not owns_card(card_id):
		return false
	var mark: int = card_mark(card_id)
	if not card.can_upgrade(mark, gold):
		return false
	gold -= card.upgrade_cost(mark)
	_marks[card_id] = mark + 1
	card_upgraded.emit(card, mark + 1)
	_commit()
	return true


## Gives units of an item without charge (the stock fittings, and tests), up
## to the most that could be fitted.
func add_card_units(card_id: StringName, amount: int) -> void:
	var card: ComponentCard = GameCatalog.find_card(card_id)
	if card == null or amount <= 0:
		return
	if not _marks.has(card_id):
		_marks[card_id] = 1
	_units[card_id] = mini(card_units(card_id) + amount, card.max_units())
	_commit()


func add_gold(amount: int) -> void:
	gold = maxi(gold + amount, 0)
	_commit()


## Takes [param amount] of gold if there is that much. Returns whether it did.
func spend_gold(amount: int) -> bool:
	if amount < 0 or gold < amount:
		return false
	gold -= amount
	_commit()
	return true


func set_insure_sorties(insure: bool) -> void:
	insure_sorties = insure
	_commit()


# ---------------------------------------------------------------------------
# Sorties
# ---------------------------------------------------------------------------

## Called as a sortie starts. Pays the premium if sorties are being insured,
## the plane is worth insuring and the gold is there. Returns whether this
## sortie is covered.
func pay_insurance() -> bool:
	var cost: int = insurance_cost(selected_plane())
	if not insure_sorties or cost <= 0 or gold < cost:
		return false
	gold -= cost
	_commit()
	return true


## Home safe: the bounty carried is paid in.
func bank_bounty(amount: int) -> void:
	add_gold(maxi(amount, 0))


## The plane did not come back. A free plane is simply issued again; any
## other is gone until it is bought again. What was fitted to it is kept.
## Returns true if a plane was actually lost.
func lose_plane(plane_id: StringName) -> bool:
	if not _planes.has(plane_id):
		return false
	_planes.erase(plane_id)
	if selected_plane_id == plane_id:
		selected_plane_id = GameCatalog.STARTER_PLANE_ID
	_commit()
	return true


# ---------------------------------------------------------------------------
# Fitting
# ---------------------------------------------------------------------------

## Fits an owned item to a mount. Returns false if the item does not go
## there, or every unit of it is already fitted elsewhere.
func equip_card(mount: int, card_id: StringName) -> bool:
	var card: ComponentCard = GameCatalog.find_card(card_id)
	if card == null or not owns_card(card_id):
		return false
	if not PlaneMounts.mount_accepts(mount, card):
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


## Where [param card] would go if fitted now: an empty mount of its kind,
## else one holding something different, else -1 (nowhere, or no unit spare).
func find_mount_for(card: ComponentCard) -> int:
	if card == null or fitted_count(card.id) >= card_units(card.id):
		return -1
	var replace: int = -1
	for mount: int in range(PlaneMounts.MOUNT_COUNT):
		if not PlaneMounts.mount_accepts(mount, card):
			continue
		if loadout[mount] == &"":
			return mount
		if replace == -1 and loadout[mount] != card.id:
			replace = mount
	return replace


func select_plane(plane_id: StringName) -> bool:
	if not owns_plane(plane_id):
		return false
	selected_plane_id = plane_id
	_commit()
	return true


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func reset_to_new_profile(save_now: bool = true) -> void:
	gold = STARTING_GOLD
	selected_plane_id = GameCatalog.STARTER_PLANE_ID
	invert_pitch = false
	insure_sorties = false
	_planes.clear()
	_units.clear()
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
		items[String(card_id)] = {"units": card_units(card_id), "mark": card_mark(card_id)}
	var mounts: Array[String] = []
	for card_id: StringName in loadout:
		mounts.append(String(card_id))
	var planes: Array[String] = []
	for plane_id: StringName in _planes:
		planes.append(String(plane_id))
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"pilot_name": pilot_name,
		"gold": gold,
		"planes": planes,
		"selected_plane_id": String(selected_plane_id),
		"insure_sorties": insure_sorties,
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
	var version: int = _read_int(data, "version", 1)
	pilot_name = _read_string(data, "pilot_name", pilot_name)
	# Older saves called it coins. It is the same money.
	gold = maxi(_read_int(data, "gold", _read_int(data, "coins", gold)), 0)
	insure_sorties = _read_bool(data, "insure_sorties", false)
	invert_pitch = _read_bool(data, "invert_pitch", invert_pitch)
	var saved_planes: Variant = data.get("planes", [])
	if saved_planes is Array:
		var plane_list: Array = saved_planes
		for entry: Variant in plane_list:
			var plane: PlaneData = GameCatalog.find_plane(StringName(str(entry)))
			if plane != null and not plane.is_free():
				_planes[plane.id] = true
	if version < 3:
		# Planes used to unlock with Hangar XP, which no longer exists: a
		# pilot who had earned one keeps it.
		var old_xp: int = _read_int(data, "commander_xp", 0)
		for plane_id: StringName in LEGACY_PLANE_XP:
			if old_xp >= LEGACY_PLANE_XP[plane_id]:
				_planes[plane_id] = true
	selected_plane_id = StringName(_read_string(data, "selected_plane_id", String(selected_plane_id)))
	# A version 1 save holds the old levelled cards, which no longer exist:
	# its fittings start from stock.
	if version >= 2:
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
				_marks[card.id] = clampi(_read_int(entry_dict, "mark", 1), 1, ComponentCard.MAX_MARK)
		var saved_loadout: Variant = data.get("loadout", [])
		if saved_loadout is Array:
			var mounts: Array = saved_loadout
			loadout.fill(&"")
			for mount: int in range(mini(mounts.size(), loadout.size())):
				var card_id: StringName = StringName(str(mounts[mount]))
				var card: ComponentCard = GameCatalog.find_card(card_id)
				if card != null and PlaneMounts.mount_accepts(mount, card) and fitted_count(card_id) < card_units(card_id):
					loadout[mount] = card_id
	_repair_loadout()
	changed.emit()


## Gives the player the stock items and fits them: what every pilot starts with.
func _fit_stock() -> void:
	loadout.clear()
	loadout.resize(PlaneMounts.MOUNT_COUNT)
	loadout.fill(&"")
	for mount: int in range(PlaneMounts.MOUNT_COUNT):
		var card_id: StringName = GameCatalog.STOCK_FITTING_IDS[mount]
		if card_id == &"":
			continue
		_units[card_id] = card_units(card_id) + 1
		_marks[card_id] = 1
		loadout[mount] = card_id


## Makes sure nothing is missing that a plane cannot fly without: any such
## mount found empty gets the standard item back (which every pilot owns).
func _repair_loadout() -> void:
	for mount: int in range(PlaneMounts.MOUNT_COUNT):
		if loadout[mount] != &"":
			continue
		var stock: ComponentCard = GameCatalog.stock_card_for(PlaneMounts.MOUNT_SLOTS[mount])
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
