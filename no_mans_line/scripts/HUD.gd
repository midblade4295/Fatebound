extends CanvasLayer
## HUD.gd -- everything the player touches.
##
## * Card hand: shows cost, greys out unaffordable cards, draws the cooldown
##   wipe and plays the card through GameManager.play_card().
## * Touch targeting: Mortar Strike / Mustard Gas arm the TargetingOverlay; the
##   next tap (or click) on the battlefield is converted to world coordinates
##   and sent with the card. Tapping the armed card again cancels.
## * Top bar: match clock, bunker health and the tug-of-war meter.
## * Whistle Charge button and the end-of-match screen.
##
## The HUD never changes game state itself: it only calls GameManager methods.

const PLAYER_TEAM := GameManager.TEAM_BLUE

const AFFORDABLE_TINT := Color(1.0, 1.0, 1.0)
const UNAFFORDABLE_TINT := Color(0.55, 0.53, 0.5)
const ARMED_TINT := Color(1.25, 1.15, 0.75)
const SECTOR_COLORS := {
	GameManager.TEAM_NONE: Color(0.45, 0.43, 0.4),
	GameManager.TEAM_BLUE: Color(0.3, 0.55, 0.85),
	GameManager.TEAM_RED: Color(0.82, 0.25, 0.2),
}
## Reticle radius per targeted card (matches the ability's area of effect).
const RETICLE_RADIUS := {
	GameManager.Card.MORTAR: 150.0,
	GameManager.Card.GAS: 170.0,
}

var game: GameManager

## Card id currently waiting for a battlefield tap, or -1.
var _targeting_card := -1
var _tug_display := 0.5
var _cards := {}
var _banner_tween: Tween

@onready var timer_label: Label = $Root/TopBar/TimerPlate/TimerLabel
@onready var blue_score: Label = $Root/TopBar/BluePanel/ScoreLabel
@onready var red_score: Label = $Root/TopBar/RedPanel/ScoreLabel
@onready var tug_back: ColorRect = $Root/TopBar/TugOfWar/Back
@onready var tug_fill: ColorRect = $Root/TopBar/TugOfWar/BlueFill
@onready var tug_marker: ColorRect = $Root/TopBar/TugOfWar/Marker
@onready var sector_pips: HBoxContainer = $Root/TopBar/TugOfWar/SectorPips
@onready var supply_label: Label = $Root/SupplyPanel/SupplyValue
@onready var supply_bar: ProgressBar = $Root/SupplyPanel/SupplyBar
@onready var whistle_button: Button = $Root/WhistleButton
@onready var whistle_shade: ColorRect = $Root/WhistleButton/CooldownShade
@onready var targeting_overlay: Control = $Root/TargetingOverlay
@onready var targeting_hint: Label = $Root/TargetingOverlay/HintLabel
@onready var reticle: Node2D = $Root/TargetingOverlay/Reticle
@onready var reticle_ring: Line2D = $Root/TargetingOverlay/Reticle/Ring
@onready var banner: Label = $Root/Banner
@onready var end_screen: Control = $Root/EndScreen
@onready var end_title: Label = $Root/EndScreen/Center/Box/TitleLabel
@onready var end_reason: Label = $Root/EndScreen/Center/Box/ReasonLabel


func _ready() -> void:
	_cards = {
		GameManager.Card.RIFLEMEN: $Root/CardHand/RiflemenCard,
		GameManager.Card.RAIDERS: $Root/CardHand/RaidersCard,
		GameManager.Card.MORTAR: $Root/CardHand/MortarCard,
		GameManager.Card.GAS: $Root/CardHand/GasCard,
	}
	# Fill in names and costs from the single source of truth in GameManager.
	for card_id in _cards:
		var button: Button = _cards[card_id]
		button.get_node("NameLabel").text = GameManager.CARDS[card_id]["name"]
		button.get_node("CostBadge").text = str(GameManager.CARDS[card_id]["cost"])
		button.get_node("CooldownLabel").visible = false
		button.get_node("CooldownShade").visible = false

	targeting_overlay.visible = false
	end_screen.visible = false
	banner.modulate.a = 0.0
	whistle_shade.visible = false


## Called by GameManager._ready(). Match signals are connected in Main.tscn.
func setup(p_game: GameManager) -> void:
	game = p_game
	supply_bar.max_value = game.supply_max


func _process(delta: float) -> void:
	if game == null:
		return
	_update_cards()
	_update_whistle()
	_update_tug_of_war(delta)


# ----------------------------------------------------------------------------
# Card hand
# ----------------------------------------------------------------------------
func _update_cards() -> void:
	for card_id in _cards:
		var button: Button = _cards[card_id]
		var shade: ColorRect = button.get_node("CooldownShade")
		var cooldown_label: Label = button.get_node("CooldownLabel")
		var cooldown := game.get_card_cooldown(PLAYER_TEAM, card_id)
		var total: float = GameManager.CARDS[card_id]["cooldown"]

		# Cooldown wipe: a dark shade that drains from the top of the card.
		var fraction := clampf(cooldown / total, 0.0, 1.0)
		shade.visible = fraction > 0.0
		shade.size = Vector2(button.size.x, button.size.y * fraction)
		shade.position = Vector2(0.0, button.size.y - shade.size.y)
		cooldown_label.visible = cooldown > 0.0
		cooldown_label.text = "%d" % ceili(cooldown)

		if card_id == _targeting_card:
			button.modulate = ARMED_TINT
		elif game.supply[PLAYER_TEAM] >= game.get_card_cost(card_id):
			button.modulate = AFFORDABLE_TINT
		else:
			button.modulate = UNAFFORDABLE_TINT


## Connected from each card's `pressed` signal in HUD.tscn (card id is bound).
func _on_card_pressed(card_id: int) -> void:
	if game == null or game.match_over:
		return
	if _targeting_card == card_id:
		_cancel_targeting()
		return
	_cancel_targeting()

	if game.get_card_cooldown(PLAYER_TEAM, card_id) > 0.0:
		show_banner("%s is not ready yet" % GameManager.CARDS[card_id]["name"])
		return
	if game.supply[PLAYER_TEAM] < game.get_card_cost(card_id):
		show_banner("Not enough Supply")
		return

	if GameManager.CARDS[card_id]["targeted"]:
		_begin_targeting(card_id)
	else:
		game.play_card(PLAYER_TEAM, card_id)


# ----------------------------------------------------------------------------
# Touch targeting (Mortar Strike / Mustard Gas)
# ----------------------------------------------------------------------------
func _begin_targeting(card_id: int) -> void:
	_targeting_card = card_id
	targeting_overlay.visible = true
	targeting_hint.text = "%s - tap the battlefield to fire (tap the card again to cancel)" % [
		str(GameManager.CARDS[card_id]["name"]).to_upper()
	]
	_build_reticle(RETICLE_RADIUS[card_id])
	reticle.visible = false


func _cancel_targeting() -> void:
	_targeting_card = -1
	targeting_overlay.visible = false


func _build_reticle(radius: float) -> void:
	var points := PackedVector2Array()
	for i in 49:
		var angle := TAU * i / 48.0
		points.append(Vector2(cos(angle) * radius, sin(angle) * radius * 0.3))
	reticle_ring.points = points


## Connected from TargetingOverlay.gui_input in HUD.tscn. The overlay covers the
## whole screen but sits BELOW the cards in the tree, so the cards stay tappable.
func _on_targeting_overlay_gui_input(event: InputEvent) -> void:
	if _targeting_card < 0:
		return

	# Touchscreens send InputEventScreenTouch AND an emulated mouse click.
	# Ignore the emulated copy so one tap never fires twice.
	var is_emulated_mouse := event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION

	if event is InputEventScreenTouch:
		_move_reticle(event.position)
		if not event.pressed:
			_fire_targeted_card(event.position)
	elif event is InputEventScreenDrag:
		_move_reticle(event.position)
	elif event is InputEventMouseMotion and not is_emulated_mouse:
		_move_reticle(event.position)
	elif event is InputEventMouseButton and not is_emulated_mouse:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_cancel_targeting()
		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_fire_targeted_card(event.position)


func _move_reticle(screen_position: Vector2) -> void:
	reticle.visible = true
	# Keep the reticle glued to the ground line so the aim reads clearly.
	var world := _screen_to_world(screen_position)
	world.y = GameManager.GROUND_Y
	reticle.position = get_viewport().get_canvas_transform() * world


func _fire_targeted_card(screen_position: Vector2) -> void:
	var card_id := _targeting_card
	_cancel_targeting()
	if not game.play_card(PLAYER_TEAM, card_id, _screen_to_world(screen_position)):
		show_banner("Not enough Supply")


## HUD (CanvasLayer) coordinates -> battlefield coordinates under the Camera2D.
func _screen_to_world(screen_position: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_position


# ----------------------------------------------------------------------------
# Whistle Charge
# ----------------------------------------------------------------------------
func _update_whistle() -> void:
	var cooldown := game.get_whistle_cooldown(PLAYER_TEAM)
	var fraction := clampf(cooldown / game.whistle_cooldown, 0.0, 1.0)
	whistle_shade.visible = fraction > 0.0
	whistle_shade.size = Vector2(whistle_button.size.x, whistle_button.size.y * fraction)
	whistle_shade.position = Vector2(0.0, whistle_button.size.y - whistle_shade.size.y)
	whistle_button.modulate = AFFORDABLE_TINT if game.can_whistle(PLAYER_TEAM) else Color(0.7, 0.68, 0.62)


## Connected from WhistleButton.pressed in HUD.tscn.
func _on_whistle_button_pressed() -> void:
	if game == null or game.match_over:
		return
	_cancel_targeting()
	if game.get_whistle_cooldown(PLAYER_TEAM) > 0.0:
		show_banner("The men are catching their breath")
	elif not game.trigger_whistle(PLAYER_TEAM):
		show_banner("No troops stationed in a trench")


# ----------------------------------------------------------------------------
# Top bar
# ----------------------------------------------------------------------------
func _update_tug_of_war(delta: float) -> void:
	_tug_display = lerpf(_tug_display, game.get_tug_of_war(), minf(1.0, delta * 4.0))
	var width := tug_back.size.x
	tug_fill.size.x = width * _tug_display
	tug_marker.position.x = width * _tug_display - tug_marker.size.x * 0.5


func _on_time_changed(seconds_left: int) -> void:
	timer_label.text = "%02d:%02d" % [seconds_left / 60, seconds_left % 60]
	# Last 30 seconds: the clock turns red.
	timer_label.modulate = Color(1.0, 0.45, 0.35) if seconds_left <= 30 else Color.WHITE


func _on_supply_changed(team: int, amount: float) -> void:
	if team != PLAYER_TEAM:
		return
	supply_bar.value = amount
	supply_label.text = "%d / %d" % [floori(amount), int(game.supply_max)]


func _on_bunker_health_changed(team: int, health: float, _max_health: float) -> void:
	var label := blue_score if team == GameManager.TEAM_BLUE else red_score
	label.text = str(ceili(health))


func _on_sector_control_changed(owners: Array[int]) -> void:
	for i in mini(owners.size(), sector_pips.get_child_count()):
		(sector_pips.get_child(i) as ColorRect).color = SECTOR_COLORS[owners[i]]


func _on_whistle_charge(team: int) -> void:
	if team == PLAYER_TEAM:
		show_banner("OVER THE TOP!", Color(1.0, 0.85, 0.35))
	else:
		show_banner("ENEMY WHISTLE - THEY ARE COMING!", Color(1.0, 0.45, 0.35))


## Short fading message under the tug-of-war bar.
func show_banner(text: String, color: Color = Color(0.95, 0.9, 0.8)) -> void:
	banner.text = text
	banner.modulate = color
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_interval(1.4)
	_banner_tween.tween_property(banner, "modulate:a", 0.0, 0.5)


# ----------------------------------------------------------------------------
# End of match
# ----------------------------------------------------------------------------
func _on_match_ended(winner: int, reason: String) -> void:
	_cancel_targeting()
	end_screen.visible = true
	end_reason.text = reason
	match winner:
		GameManager.TEAM_BLUE:
			end_title.text = "VICTORY"
			end_title.modulate = Color(0.55, 0.8, 1.0)
		GameManager.TEAM_RED:
			end_title.text = "DEFEAT"
			end_title.modulate = Color(1.0, 0.45, 0.35)
		_:
			end_title.text = "STALEMATE"
			end_title.modulate = Color(0.9, 0.85, 0.75)


## Connected from RestartButton.pressed in HUD.tscn.
func _on_restart_button_pressed() -> void:
	game.restart_match()
