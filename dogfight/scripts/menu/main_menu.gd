extends Node3D
## Main menu / Hangar (scenes/menu/MainMenu.tscn).
##
## The selected plane stands in the middle, engine stopped, and the player can
## look it over: drag with one finger to move the camera round it, pinch to
## zoom in and out, drag with two fingers to slide the plane about the screen,
## double-tap to put the view back. (With a mouse: drag, wheel, right-drag.)
## The UI on top is the whole progression loop:
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

# --- Looking round the plane ---------------------------------------------------
## Where the camera starts: off the nose to one side, looking slightly down.
const VIEW_YAW: float = deg_to_rad(148.0)
const VIEW_PITCH: float = deg_to_rad(14.0)
const VIEW_DISTANCE: float = 41.0
## The plane sits left of and above the middle of the screen, clear of the
## panels: this far from the middle, as a share of the screen's height.
const VIEW_OFFSET: Vector2 = Vector2(0.106, -0.113)
const MIN_PITCH: float = deg_to_rad(-3.0)
const MAX_PITCH: float = deg_to_rad(78.0)
const MIN_DISTANCE: float = 13.0
const MAX_DISTANCE: float = 75.0
## How far the plane can be slid from where it starts, as a share of the
## screen's height.
const MAX_PAN: float = 0.32
## Radians of orbit per pixel dragged.
const ORBIT_SPEED: float = 0.006
## Zoom per notch of a mouse wheel.
const WHEEL_ZOOM: float = 0.9
## How quickly the camera settles onto where it has been sent (1/s).
const VIEW_SMOOTHING: float = 12.0
const DOUBLE_TAP_TIME: float = 0.3
const TAP_SLOP: float = 14.0

var _plane_index: int = 0
var _selected_card_id: StringName = &""
## The mount tile that was tapped, or -1 when a collection card was.
var _selected_mount: int = -1
## The loadout the turntable plane was last built with.
var _shown_fittings: String = ""
var _preview: PlaneVisual
# Where the camera has been sent (the camera itself eases toward it).
var _view_yaw: float = VIEW_YAW
var _view_pitch: float = VIEW_PITCH
var _view_distance: float = VIEW_DISTANCE
var _view_pan: Vector2 = Vector2.ZERO
# And where it is now.
var _shown_yaw: float = VIEW_YAW
var _shown_pitch: float = VIEW_PITCH
var _shown_distance: float = VIEW_DISTANCE
var _shown_pan: Vector2 = Vector2.ZERO
## Fingers on the empty part of the screen: touch index -> position.
var _touches: Dictionary[int, Vector2] = {}
var _last_tap_time: float = -1.0
var _tap_start: Vector2 = Vector2.ZERO
var _tap_moved: bool = false
var _clock: float = 0.0
var _collection_views: Array[CardView] = []
var _slot_views: Array[CardView] = []

@onready var _turntable: Node3D = $Stage/Turntable
@onready var _camera: Camera3D = $Camera3D
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
	_build_view_hint()
	_place_camera()


func _process(delta: float) -> void:
	_clock += delta
	var blend: float = 1.0 - exp(-VIEW_SMOOTHING * delta)
	_shown_yaw = lerp_angle(_shown_yaw, _view_yaw, blend)
	_shown_pitch = lerpf(_shown_pitch, _view_pitch, blend)
	_shown_distance = lerpf(_shown_distance, _view_distance, blend)
	_shown_pan = _shown_pan.lerp(_view_pan, blend)
	_place_camera()


## Touches that land on a panel never get here, so anything that does is on
## the open part of the screen around the plane.
func _unhandled_input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			_touches[touch.index] = touch.position
			if _touches.size() == 1:
				_tap_start = touch.position
				_tap_moved = false
		else:
			var was_only_touch: bool = _touches.size() == 1 and _touches.has(touch.index)
			_touches.erase(touch.index)
			if was_only_touch and not _tap_moved:
				# A tap. Two in quick succession put the view back.
				if _clock - _last_tap_time <= DOUBLE_TAP_TIME:
					reset_view()
					_last_tap_time = -1.0
				else:
					_last_tap_time = _clock
		return
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag != null and _touches.has(drag.index):
		_drag_touch(drag.index, drag.position)
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_view(WHEEL_ZOOM)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_view(1.0 / WHEEL_ZOOM)
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null and motion.button_mask & MOUSE_BUTTON_MASK_RIGHT != 0:
		pan_view(motion.relative)


## Swings the camera round the plane: [param pixels] of drag, right and down.
func orbit_view(pixels: Vector2) -> void:
	_view_yaw = wrapf(_view_yaw - pixels.x * ORBIT_SPEED, -PI, PI)
	_view_pitch = clampf(_view_pitch + pixels.y * ORBIT_SPEED, MIN_PITCH, MAX_PITCH)


## Moves the camera in (factor below 1) or out (above 1).
func zoom_view(factor: float) -> void:
	_view_distance = clampf(_view_distance * factor, MIN_DISTANCE, MAX_DISTANCE)


## Slides the plane about the screen by [param pixels].
func pan_view(pixels: Vector2) -> void:
	# Kept as a share of the screen's height, so the plane stays under the
	# fingers, and stays put on the screen while zooming.
	_view_pan = (_view_pan + pixels / maxf(float(get_viewport().get_visible_rect().size.y), 1.0)).limit_length(MAX_PAN)


## Puts the camera and the plane back where they started.
func reset_view() -> void:
	_view_yaw = VIEW_YAW
	_view_pitch = VIEW_PITCH
	_view_distance = VIEW_DISTANCE
	_view_pan = Vector2.ZERO


func _drag_touch(index: int, new_position: Vector2) -> void:
	var old_position: Vector2 = _touches[index]
	if new_position.distance_to(_tap_start) > TAP_SLOP:
		_tap_moved = true
	if _touches.size() == 1:
		orbit_view(new_position - old_position)
	elif _touches.size() >= 2:
		# Two fingers: the change in their spread zooms, the movement of the
		# point between them slides the plane.
		var other: Vector2 = Vector2.ZERO
		for other_index: int in _touches:
			if other_index != index:
				other = _touches[other_index]
				break
		var old_spread: float = maxf(old_position.distance_to(other), 1.0)
		var new_spread: float = maxf(new_position.distance_to(other), 1.0)
		zoom_view(old_spread / new_spread)
		pan_view((new_position - old_position) * 0.5)
		_tap_moved = true
	_touches[index] = new_position


func _place_camera() -> void:
	var orbit: Basis = Basis(Vector3.UP, _shown_yaw) * Basis(Vector3.RIGHT, -_shown_pitch)
	_camera.global_transform = Transform3D(orbit, _turntable.global_position + orbit * Vector3(0.0, 0.0, _shown_distance))
	# Sliding the plane is done by shifting the lens, so the camera still
	# circles the plane itself wherever it has been slid to. The shift is a
	# share of what the lens sees at this distance, so zooming does not move
	# the plane across the screen.
	var view_height: float = 2.0 * _shown_distance * tan(deg_to_rad(_camera.fov) * 0.5)
	_camera.h_offset = (VIEW_OFFSET.x - _shown_pan.x) * view_height
	_camera.v_offset = (VIEW_OFFSET.y + _shown_pan.y) * view_height


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


## One line under the top bar saying how to look round the plane.
func _build_view_hint() -> void:
	var hint: Label = Label.new()
	hint.name = "ViewHint"
	hint.text = "Drag to look round  -  pinch to zoom\nTwo fingers to move  -  double-tap to reset"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	# Between the Commander panel and the coin counter.
	hint.offset_left = -340.0
	hint.offset_right = 300.0
	hint.offset_top = 30.0
	hint.offset_bottom = 96.0
	UiStyle.style_label(hint, 20, Color(0.85, 0.93, 1.0, 0.85), 5)
	$UI/Root.add_child(hint)


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
	# Parked in the hangar: engine stopped, wheels down.
	_preview.set_propeller(0.0, true)
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
	# All of these are measured from the flight model, not stated: change what
	# is fitted and they move as the real aeroplane's would.
	_plane_info.text = "%s\n\nTop speed %d km/h (%d at %d m)\nStalls at %d    Climb %d m/s    %d kg    %d hp\nToughness %d    Guns %d    %d damage/s" % [
			data.description, roundi(stats.top_speed * 3.6), roundi(stats.top_speed_high * 3.6), roundi(PlaneStats.HIGH_ALTITUDE), roundi(stats.stall_speed * 3.6),
			roundi(stats.climb_rate), roundi(stats.mass), roundi(stats.engine_power / 745.7),
			roundi(stats.max_hp), stats.gun_count(), roundi(stats.fire_rate * stats.bullet_damage)]
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
