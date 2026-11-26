extends Node3D
## Main menu / Hangar (scenes/menu/MainMenu.tscn).
##
## A turntable shows the selected plane in 3D; the UI on top is the whole
## progression loop:
##   - Commander Level badge + Hangar XP bar, coin counter
##   - plane picker (planes unlock by Commander Level)
##   - loadout slots (3 to 5, opening with Commander Level)
##   - card collection: tap a card to inspect, UPGRADE (coins + copies -> XP)
##     or EQUIP it into the matching slot
##   - BATTLE -> match lobby
##
## Everything is rebuilt from Profile whenever it emits `changed`, so the
## screen can never show stale numbers.

const TURNTABLE_SPEED: float = 0.5

var _plane_index: int = 0
var _selected_card_id: StringName = &""
var _preview: PlaneVisual
var _collection_views: Array[CardView] = []
var _slot_views: Array[CardView] = []

@onready var _turntable: Node3D = $Stage/Turntable
@onready var _level_label: Label = %LevelLabel
@onready var _commander_title: Label = %CommanderTitle
@onready var _xp_bar: ProgressBar = %XpBar
@onready var _xp_label: Label = %XpLabel
@onready var _coin_label: Label = %CoinLabel
@onready var _crate_button: Button = %CrateButton
@onready var _plane_name: Label = %PlaneName
@onready var _plane_info: Label = %PlaneInfo
@onready var _prev_plane: Button = %PrevPlane
@onready var _next_plane: Button = %NextPlane
@onready var _select_plane: Button = %SelectPlane
@onready var _slots: HBoxContainer = %Slots
@onready var _grid: GridContainer = %Grid
@onready var _detail_name: Label = %DetailName
@onready var _detail_stats: Label = %DetailStats
@onready var _upgrade_button: Button = %UpgradeButton
@onready var _equip_button: Button = %EquipButton
@onready var _battle_button: Button = %BattleButton


func _ready() -> void:
	_apply_style()
	_build_stage_floor()
	_plane_index = maxi(GameCatalog.PLANES.find(Profile.selected_plane()), 0)
	_build_card_views()
	_prev_plane.pressed.connect(_on_cycle_plane.bind(-1))
	_next_plane.pressed.connect(_on_cycle_plane.bind(1))
	_select_plane.pressed.connect(_on_select_plane)
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	_equip_button.pressed.connect(_on_equip_pressed)
	_battle_button.pressed.connect(_on_battle_pressed)
	_crate_button.pressed.connect(_on_crate_pressed)
	Profile.changed.connect(_refresh)
	Profile.commander_leveled_up.connect(_on_commander_leveled_up)
	_selected_card_id = Profile.loadout[0]
	_refresh()
	_show_plane()


func _process(delta: float) -> void:
	_turntable.rotate_y(TURNTABLE_SPEED * delta)


# ---------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------

func _build_stage_floor() -> void:
	var disc: CylinderMesh = CylinderMesh.new()
	disc.top_radius = 7.6
	disc.bottom_radius = 8.4
	disc.height = 0.8
	disc.radial_segments = 32
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	floor_mesh.name = "Floor"
	floor_mesh.mesh = disc
	floor_mesh.material_override = ToonMaterials.toon(Color("3b4a66"), 0.0, 0.15)
	floor_mesh.position = Vector3(0.0, -3.4, 0.0)
	$Stage.add_child(floor_mesh)


func _build_card_views() -> void:
	for _card: ComponentCard in GameCatalog.CARDS:
		var view: CardView = CardView.new()
		view.pressed.connect(_on_collection_card_pressed)
		_grid.add_child(view)
		_collection_views.append(view)
	for slot: int in range(CommanderProgression.MAX_CARD_SLOTS):
		var view: CardView = CardView.new()
		view.slot_index = slot
		view.pressed.connect(_on_slot_pressed)
		_slots.add_child(view)
		_slot_views.append(view)


func _show_plane() -> void:
	var data: PlaneData = GameCatalog.PLANES[_plane_index]
	if _preview == null:
		_preview = PlaneVisual.new()
		_preview.name = "PlanePreview"
		_turntable.add_child(_preview)
	_preview.build(data, GameSession.local_team)
	_preview.set_throttle(0.25)
	_refresh_plane_panel()


# ---------------------------------------------------------------------------
# Refresh from Profile
# ---------------------------------------------------------------------------

func _refresh() -> void:
	var level: int = Profile.commander_level()
	_level_label.text = str(level)
	_commander_title.text = "COMMANDER LEVEL"
	_xp_bar.value = CommanderProgression.level_progress(Profile.commander_xp) * 100.0
	var needed: int = CommanderProgression.xp_to_next(level)
	_xp_label.text = "HANGAR XP  MAX" if needed <= 0 else "HANGAR XP  %d / %d" % [CommanderProgression.xp_into_level(Profile.commander_xp), needed]
	_coin_label.text = "COINS  %d" % Profile.coins

	for index: int in range(_collection_views.size()):
		var card: ComponentCard = GameCatalog.CARDS[index]
		var view: CardView = _collection_views[index]
		view.show_card(card, Profile.card_level(card.id), Profile.card_copies(card.id), Profile.owns_card(card.id),
				Profile.loadout.has(card.id), Profile.can_upgrade_card(card.id))
		view.selected = card.id == _selected_card_id

	for slot: int in range(_slot_views.size()):
		var view: CardView = _slot_views[slot]
		var equipped_id: StringName = Profile.loadout[slot]
		var equipped_card: ComponentCard = GameCatalog.find_card(equipped_id)
		if not CommanderProgression.is_slot_unlocked(slot, level):
			view.show_empty(CommanderProgression.slot_label(slot), CommanderProgression.slot_unlock_level(slot))
		elif equipped_card == null:
			view.show_empty(CommanderProgression.slot_label(slot))
		else:
			view.show_card(equipped_card, Profile.card_level(equipped_id), Profile.card_copies(equipped_id), true, false,
					Profile.can_upgrade_card(equipped_id))
		view.selected = equipped_card != null and equipped_id == _selected_card_id
	_refresh_detail()
	_refresh_plane_panel()


func _refresh_plane_panel() -> void:
	var data: PlaneData = GameCatalog.PLANES[_plane_index]
	var level: int = Profile.commander_level()
	var unlocked: bool = data.is_unlocked(level)
	_plane_name.text = data.display_name.to_upper()
	# Show the numbers the plane would fly with the current loadout.
	var stats: PlaneStats = data.build_stats(level, Profile.equipped_cards(), Profile.equipped_card_levels())
	_plane_info.text = "%s\n\nArmor %d    Speed %d km/h\nTurn %d deg/s    Damage %d x %.1f/s" % [
			data.description, roundi(stats.max_hp), roundi(stats.top_speed * 3.6),
			roundi(rad_to_deg(stats.turn_rate)), roundi(stats.bullet_damage), stats.fire_rate]
	if not unlocked:
		_select_plane.text = "COMMANDER LV %d" % data.unlock_commander_level
		_select_plane.disabled = true
	elif data.id == Profile.selected_plane().id:
		_select_plane.text = "SELECTED"
		_select_plane.disabled = true
	else:
		_select_plane.text = "SELECT"
		_select_plane.disabled = false


func _refresh_detail() -> void:
	var card: ComponentCard = GameCatalog.find_card(_selected_card_id)
	if card == null:
		_detail_name.text = "TAP A CARD"
		_detail_stats.text = ""
		_upgrade_button.disabled = true
		_upgrade_button.text = "UPGRADE"
		_equip_button.disabled = true
		return
	var owned: bool = Profile.owns_card(card.id)
	var level: int = Profile.card_level(card.id) if owned else card.start_level()
	_detail_name.text = "%s   (%s %s)" % [card.display_name.to_upper(), card.rarity_name(), card.category_name()]
	_detail_name.add_theme_color_override(&"font_color", card.rarity_color().lightened(0.3))
	var lines: PackedStringArray = PackedStringArray([card.description])
	lines.append("Level %d:  %s" % [level, ",  ".join(card.stat_lines(level))])
	if owned and not card.is_max_level(level):
		lines.append("Level %d:  %s   (+%d XP)" % [level + 1, ",  ".join(card.stat_lines(level + 1)), card.xp_reward(level)])
	_detail_stats.text = "\n".join(lines)

	if not owned:
		_upgrade_button.text = "NOT FOUND YET"
		_upgrade_button.disabled = true
		_equip_button.disabled = true
		_equip_button.text = "EQUIP"
		return
	if card.is_max_level(level):
		_upgrade_button.text = "MAX LEVEL"
		_upgrade_button.disabled = true
	else:
		_upgrade_button.text = "UPGRADE  %d" % card.coin_cost(level)
		_upgrade_button.disabled = not Profile.can_upgrade_card(card.id)
	var equipped_slot: int = Profile.loadout.find(card.id)
	if equipped_slot != -1:
		_equip_button.text = "REMOVE"
		_equip_button.disabled = false
	else:
		_equip_button.text = "EQUIP"
		_equip_button.disabled = Profile.find_slot_for(card) == -1


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _on_collection_card_pressed(view: CardView) -> void:
	_selected_card_id = view.card.id
	_refresh()


func _on_slot_pressed(view: CardView) -> void:
	if view.card != null:
		_selected_card_id = view.card.id
		_refresh()


func _on_upgrade_pressed() -> void:
	Profile.try_upgrade_card(_selected_card_id)


func _on_equip_pressed() -> void:
	var card: ComponentCard = GameCatalog.find_card(_selected_card_id)
	if card == null:
		return
	var equipped_slot: int = Profile.loadout.find(card.id)
	if equipped_slot != -1:
		Profile.unequip_slot(equipped_slot)
	else:
		Profile.equip_card(Profile.find_slot_for(card), card.id)


func _on_cycle_plane(step: int) -> void:
	_plane_index = posmod(_plane_index + step, GameCatalog.PLANES.size())
	_show_plane()


func _on_select_plane() -> void:
	if Profile.select_plane(GameCatalog.PLANES[_plane_index].id):
		_refresh_plane_panel()


func _on_battle_pressed() -> void:
	GameSession.goto_lobby()


## Development shortcut: hands out a win's worth of coins and cards so the
## upgrade loop can be tried without playing ten matches first.
func _on_crate_pressed() -> void:
	Profile.grant_match_rewards(true, 5)


func _on_commander_leveled_up(new_level: int) -> void:
	_commander_title.text = "LEVEL UP!  NOW LEVEL %d" % new_level


# ---------------------------------------------------------------------------
# Styling
# ---------------------------------------------------------------------------

func _apply_style() -> void:
	for panel_name: String in ["CommanderPanel", "CoinPanel", "PlanePanel", "LoadoutPanel", "CollectionPanel", "DetailPanel"]:
		var panel: PanelContainer = get_node("%" + panel_name) as PanelContainer
		panel.add_theme_stylebox_override(&"panel", UiStyle.panel(Color(UiStyle.NAVY, 0.9), 22))
	(%LevelBadge as PanelContainer).add_theme_stylebox_override(&"panel", UiStyle.panel(Teams.COLOR_BLUE, 20, UiStyle.WHITE, 4, 6))
	UiStyle.style_label(_level_label, 54)
	UiStyle.style_label(_commander_title, 26)
	UiStyle.style_label(_xp_label, 20, Color(0.8, 0.93, 1.0), 5)
	UiStyle.style_bar(_xp_bar, UiStyle.XP_CYAN, 22.0)
	UiStyle.style_label(_coin_label, 34, UiStyle.GOLD)
	UiStyle.style_label(_plane_name, 40, UiStyle.GOLD)
	UiStyle.style_label(_plane_info, 20, Color(0.88, 0.94, 1.0), 5)
	UiStyle.style_label(%LoadoutTitle as Label, 26)
	UiStyle.style_label(%CollectionTitle as Label, 26)
	UiStyle.style_label(_detail_name, 24)
	UiStyle.style_label(_detail_stats, 18, Color(0.88, 0.94, 1.0), 4)
	UiStyle.style_button(_prev_plane, Teams.COLOR_BLUE, 34)
	UiStyle.style_button(_next_plane, Teams.COLOR_BLUE, 34)
	UiStyle.style_button(_select_plane, UiStyle.GREEN, 26)
	UiStyle.style_button(_upgrade_button, UiStyle.GREEN, 26)
	UiStyle.style_button(_equip_button, Teams.COLOR_BLUE, 26)
	UiStyle.style_button(_crate_button, Color("8a5cf0"), 22)
	UiStyle.style_button(_battle_button, UiStyle.GOLD, 56)
