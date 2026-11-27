extends Node3D
## Main menu / Hangar (scenes/menu/MainMenu.tscn).
##
## A turntable shows the selected plane in 3D; the UI on top is the whole
## progression loop:
##   - Commander Level badge + Hangar XP bar, coin counter
##   - plane picker (planes unlock by Commander Level)
##   - the mounts on the plane: four gun stations, propeller, engine,
##     wingtips, armour, undercarriage. Tap one to see what is in it or
##     take it off.
##   - the collection of weapons and components: tap one to inspect, UPGRADE
##     its Mark (coins + spares -> XP) or FIT it to the plane
##   The plane on the turntable always shows exactly what is fitted: fit one
##   gun and it has one gun.
##   - BATTLE -> match lobby
##
## Everything is rebuilt from Profile whenever it emits `changed`, so the
## screen can never show stale numbers.

const TURNTABLE_SPEED: float = 0.5

var _plane_index: int = 0
var _selected_card_id: StringName = &""
## The mount tile that was tapped, or -1 when a collection card was.
var _selected_mount: int = -1
## The loadout the turntable plane was last built with.
var _shown_fittings: String = ""
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
@onready var _slots: VBoxContainer = %Slots
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
	# Mounts: guns on the top row, everything else underneath.
	var gun_row: HBoxContainer = HBoxContainer.new()
	var part_row: HBoxContainer = HBoxContainer.new()
	for row: HBoxContainer in [gun_row, part_row]:
		row.add_theme_constant_override(&"separation", 8)
		_slots.add_child(row)
	for mount: int in range(CommanderProgression.MOUNT_COUNT):
		var view: CardView = CardView.new()
		view.compact = true
		view.slot_index = mount
		view.pressed.connect(_on_slot_pressed)
		(gun_row if CommanderProgression.is_gun_station(mount) else part_row).add_child(view)
		_slot_views.append(view)


func _show_plane() -> void:
	var data: PlaneData = GameCatalog.PLANES[_plane_index]
	if _preview == null:
		_preview = PlaneVisual.new()
		_preview.name = "PlanePreview"
		_turntable.add_child(_preview)
	_shown_fittings = ",".join(Profile.loadout)
	_preview.build(data, GameSession.local_team, Profile.equipped_cards())
	_preview.set_propeller(0.25)
	_preview.set_gear(1.0)
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
		var fitted: int = Profile.fitted_count(card.id)
		view.show_card(card, maxi(Profile.card_mark(card.id), 1), Profile.card_spares(card.id), Profile.owns_card(card.id),
				fitted > 0, Profile.can_upgrade_card(card.id), Profile.card_units(card.id), fitted)
		view.selected = card.id == _selected_card_id and _selected_mount == -1
	for mount: int in range(_slot_views.size()):
		var view: CardView = _slot_views[mount]
		var fitted_id: StringName = Profile.loadout[mount]
		var fitted_card: ComponentCard = GameCatalog.find_card(fitted_id)
		if not CommanderProgression.is_mount_unlocked(mount, level):
			view.show_empty(CommanderProgression.mount_label(mount), CommanderProgression.mount_unlock_level(mount))
		elif fitted_card == null:
			view.show_empty(CommanderProgression.mount_label(mount))
		else:
			view.empty_title = CommanderProgression.mount_label(mount)
			view.show_card(fitted_card, maxi(Profile.card_mark(fitted_id), 1), Profile.card_spares(fitted_id), true, true,
					Profile.can_upgrade_card(fitted_id))
		view.selected = mount == _selected_mount
	_refresh_detail()
	_refresh_plane_panel()
	# The plane on the turntable is rebuilt whenever what is fitted changes.
	if _preview != null and ",".join(Profile.loadout) != _shown_fittings:
		_show_plane()


func _refresh_plane_panel() -> void:
	var data: PlaneData = GameCatalog.PLANES[_plane_index]
	var level: int = Profile.commander_level()
	var unlocked: bool = data.is_unlocked(level)
	_plane_name.text = data.display_name.to_upper()
	# Show the numbers the plane would fly with what is fitted now.
	var stats: PlaneStats = data.build_stats(level, Profile.equipped_cards(), Profile.equipped_card_marks())
	var take_off: float = stats.stall_speed / sqrt(1.0 + PlaneActor.FLAP_LIFT_BONUS)
	_plane_info.text = "%s\n\nSpeed %d km/h    Take-off %d km/h\nTurn %d deg/s    Toughness %d\nGuns %d    %d damage/s    Weight +%d%%" % [
			data.description, roundi(stats.top_speed * 3.6), roundi(take_off * 3.6),
			roundi(rad_to_deg(stats.turn_rate)), roundi(stats.max_hp),
			stats.gun_count(), roundi(stats.fire_rate * stats.bullet_damage), roundi((stats.weight - 1.0) * 100.0)]
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
	_equip_button.text = "FIT"
	if card == null:
		_detail_name.text = "TAP AN ITEM OR A MOUNT"
		_detail_stats.text = "Empty gun station: pick a gun from the collection and press FIT." if _selected_mount >= 0 else ""
		_upgrade_button.disabled = true
		_upgrade_button.text = "UPGRADE"
		_equip_button.disabled = true
		return
	var owned: bool = Profile.owns_card(card.id)
	var mark: int = maxi(Profile.card_mark(card.id), 1)
	var units: int = Profile.card_units(card.id)
	var fitted: int = Profile.fitted_count(card.id)
	_detail_name.text = "%s   (%s %s)" % [card.display_name.to_upper(), card.rarity_name(), card.slot_name()]
	_detail_name.add_theme_color_override(&"font_color", card.rarity_color().lightened(0.3))
	var lines: PackedStringArray = PackedStringArray([card.description])
	lines.append("%s:  %s" % [ComponentCard.mark_name(mark), ",  ".join(card.stat_lines(mark))])
	if owned and not card.is_max_mark(mark):
		lines.append("%s:  %s   (+%d XP)" % [ComponentCard.mark_name(mark + 1), ",  ".join(card.stat_lines(mark + 1)), card.xp_reward(mark)])
	if owned and card.is_gun():
		lines.append("You have %d (each gun station takes one).  %d fitted." % [units, fitted])
	_detail_stats.text = "\n".join(lines)
	if not owned:
		_upgrade_button.text = "NOT FOUND YET"
		_upgrade_button.disabled = true
		_equip_button.disabled = true
		return
	if card.is_max_mark(mark):
		_upgrade_button.text = "TOP MARK"
		_upgrade_button.disabled = true
	else:
		_upgrade_button.text = "UPGRADE  %d" % card.coin_cost(mark)
		_upgrade_button.disabled = not Profile.can_upgrade_card(card.id)
	if _selected_mount >= 0:
		# A mount was tapped: the button takes its item off, if the plane can
		# fly without one there.
		_equip_button.text = "REMOVE" if card.is_optional() else "FITTED"
		_equip_button.disabled = not card.is_optional()
	elif Profile.find_mount_for(card) != -1:
		_equip_button.text = "FIT ANOTHER" if card.is_gun() and fitted > 0 else "FIT"
		_equip_button.disabled = false
	else:
		_equip_button.text = "ALL FITTED" if card.is_gun() and fitted > 0 else "FITTED"
		_equip_button.disabled = true


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _on_collection_card_pressed(view: CardView) -> void:
	_selected_card_id = view.card.id
	_selected_mount = -1
	_refresh()


func _on_slot_pressed(view: CardView) -> void:
	if view.locked_until_level > 0:
		return
	_selected_mount = view.slot_index
	_selected_card_id = Profile.loadout[view.slot_index]
	_refresh()


func _on_upgrade_pressed() -> void:
	Profile.try_upgrade_card(_selected_card_id)


func _on_equip_pressed() -> void:
	var card: ComponentCard = GameCatalog.find_card(_selected_card_id)
	if card == null:
		return
	if _selected_mount >= 0:
		if Profile.unequip_mount(_selected_mount):
			_selected_card_id = &""
			_refresh()
		return
	Profile.equip_card(Profile.find_mount_for(card), card.id)


func _on_cycle_plane(step: int) -> void:
	_plane_index = posmod(_plane_index + step, GameCatalog.PLANES.size())
	_show_plane()


func _on_select_plane() -> void:
	if Profile.select_plane(GameCatalog.PLANES[_plane_index].id):
		_refresh_plane_panel()


func _on_battle_pressed() -> void:
	GameSession.goto_lobby()


## Development shortcut: hands out a win's worth of coins and items so the
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
