extends Control
## Match lobby (scenes/lobby/MatchLobby.tscn): shows the two squadrons filling
## up, then launches the arena.
##
## Offline it is a short piece of theatre: the roster is generated up front
## from a seed (the same seed the arena then uses, so the names match) and
## revealed seat by seat. Online, this is the screen that would wait for real
## peers; any seat still empty when the timer runs out stays a bot.

const REVEAL_INTERVAL: float = 0.22
const LAUNCH_COUNTDOWN: float = 3.0

var _roster: Array[PilotSlot] = []
var _rows: Array[Label] = []
var _revealed: int = 0
var _reveal_timer: float = 0.4
var _countdown: float = LAUNCH_COUNTDOWN
var _launched: bool = false

@onready var _title: Label = %Title
@onready var _blue_list: VBoxContainer = %BlueList
@onready var _red_list: VBoxContainer = %RedList
@onready var _blue_title: Label = %BlueTitle
@onready var _red_title: Label = %RedTitle
@onready var _vs_label: Label = %VsLabel
@onready var _status: Label = %Status
@onready var _cancel: Button = %CancelButton


func _ready() -> void:
	GameSession.local_player_enabled = true
	GameSession.match_seed = int(randi() % 1000000) + 1
	_roster = MatchManager5v5.build_roster(GameSession.match_seed)

	(%BluePanel as PanelContainer).add_theme_stylebox_override(&"panel", UiStyle.panel(Color(Teams.COLOR_BLUE_DARK, 0.92), 24, Teams.COLOR_BLUE, 5, 20))
	(%RedPanel as PanelContainer).add_theme_stylebox_override(&"panel", UiStyle.panel(Color(Teams.COLOR_RED_DARK, 0.92), 24, Teams.COLOR_RED, 5, 20))
	UiStyle.style_label(_title, 64, UiStyle.GOLD, 12)
	UiStyle.style_label(_blue_title, 36)
	UiStyle.style_label(_red_title, 36)
	UiStyle.style_label(_vs_label, 80, UiStyle.WHITE, 14)
	UiStyle.style_label(_status, 36)
	UiStyle.style_button(_cancel, Color("7b8698"), 30)
	_title.text = "AIR SUPREMACY  %dv%d" % [GameSession.team_size, GameSession.team_size]
	_cancel.pressed.connect(GameSession.goto_hangar)

	for slot: PilotSlot in _roster:
		var row: Label = Label.new()
		row.text = "Searching..."
		UiStyle.style_label(row, 30, Color(1.0, 1.0, 1.0, 0.45), 6)
		row.custom_minimum_size.y = 58.0
		row.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		(_blue_list if slot.team == Teams.Id.TEAM_BLUE else _red_list).add_child(row)
		_rows.append(row)


func _process(delta: float) -> void:
	if _launched:
		return
	if _revealed < _roster.size():
		_status.text = "Assembling squadrons..."
		_reveal_timer -= delta
		if _reveal_timer <= 0.0:
			_reveal_timer = REVEAL_INTERVAL
			_reveal_next()
		return
	_countdown -= delta
	_status.text = "Take-off in %d" % maxi(ceili(_countdown), 0)
	if _countdown <= 0.0:
		_launched = true
		GameSession.goto_arena()


func _reveal_next() -> void:
	var slot: PilotSlot = _roster[_revealed]
	var row: Label = _rows[_revealed]
	var plane: PlaneData = Profile.selected_plane() if slot.is_local else GameCatalog.best_plane_for_level(slot.commander_level)
	var tag: String = "YOU" if slot.is_local else "BOT"
	row.text = "Lv %d   %s   [%s]   %s" % [slot.commander_level, slot.display_name, tag, plane.display_name]
	UiStyle.style_label(row, 30, UiStyle.GOLD if slot.is_local else UiStyle.WHITE, 6)
	_revealed += 1
