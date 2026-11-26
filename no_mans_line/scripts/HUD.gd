extends CanvasLayer
## HUD.gd -- everything the player touches.
##
## * Card hand: four TextureButtons showing the sliced card art. The HUD draws
##   the live cost badge, greys out unaffordable cards, runs the cooldown wipe
##   and plays the card through GameManager.play_card().
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
## TextureButtons have no "pressed" art, so a held button is simply darkened.
const PRESSED_DIM := Color(0.78, 0.78, 0.78)
const BADGE_COLOR := Color(0.95, 0.9, 0.75)
const BADGE_COOLDOWN_COLOR := Color(1.0, 0.65, 0.35)
## Shown one after another when a match starts.
const OPENING_TIPS: Array[String] = [
	"Supply is slow. Spend it on a plan, not on reflex.",
	"Mortars and gas PIN troops: pinned men cannot fight back.",
	"Shell the enemy trench, THEN blow the whistle.",
]
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
## Card id -> TextureButton.
var _cards := {}
## Card id -> text shown in the top-right badge when the card is ready.
var _info_text := {}
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
@onready var rate_label: Label = $Root/SupplyPanel/RateLabel
@onready var whistle_button: TextureButton = $Root/WhistleButton
@onready var whistle_wipe: TextureProgressBar = $Root/WhistleButton/CooldownWipe
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
	# The card art has a name and badge circles painted in. The live Supply
	# cost is drawn over the left circle so it always matches GameManager.CARDS.
	for card_id in _cards:
		var button: TextureButton = _cards[card_id]
		button.get_node("CostBadge").text = str(GameManager.CARDS[card_id]["cost"])
		(button.get_node("CooldownWipe") as TextureProgressBar).value = 0.0

	targeting_overlay.visible = false
	end_screen.visible = false
	banner.modulate.a = 0.0
	whistle_wipe.value = 0.0


## Called by GameManager._ready(). Match signals are connected in Main.tscn.
func setup(p_game: GameManager) -> void:
	game = p_game
	supply_bar.max_value = game.supply_max
	# Top-right badge: squad size for troop cards, "+" for tap-to-aim cards.
	_show_opening_tips()
	_info_text = {
		GameManager.Card.RIFLEMEN: "x%d" % game.riflemen_per_card,
		GameManager.Card.RAIDERS: "x%d" % game.raiders_per_card,
		GameManager.Card.MORTAR: "+",
		GameManager.Card.GAS: "+",
	}


func _process(delta: float) -> void:
	if game == null:
		return
	_update_cards()
	_update_whistle()
	_update_tug_of_war(delta)
	_update_supply_rate()


# ----------------------------------------------------------------------------
# Card hand
# ----------------------------------------------------------------------------
func _update_cards() -> void:
	for card_id in _cards:
		var button: TextureButton = _cards[card_id]
		var wipe: TextureProgressBar = button.get_node("CooldownWipe")
		var info: Label = button.get_node("InfoBadge")
		var cooldown := game.get_card_cooldown(PLAYER_TEAM, card_id)
		var total: float = GameManager.CARDS[card_id]["cooldown"]

		# Cooldown wipe: a dark copy of the card art that drains downward.
		wipe.value = clampf(cooldown / total, 0.0, 1.0)
		if cooldown > 0.0:
			info.text = "%d" % ceili(cooldown)
			info.add_theme_color_override("font_color", BADGE_COOLDOWN_COLOR)
		else:
			info.text = _info_text.get(card_id, "")
			info.add_theme_color_override("font_color", BADGE_COLOR)

		var tint := UNAFFORDABLE_TINT
		if card_id == _targeting_card:
			tint = ARMED_TINT
		elif game.supply[PLAYER_TEAM] >= game.get_card_cost(card_id):
			tint = AFFORDABLE_TINT
		button.modulate = tint * PRESSED_DIM if button.is_pressed() else tint


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
	whistle_wipe.value = clampf(cooldown / game.whistle_cooldown, 0.0, 1.0)
	var tint := AFFORDABLE_TINT if game.can_whistle(PLAYER_TEAM) else Color(0.7, 0.68, 0.62)
	whistle_button.modulate = tint * PRESSED_DIM if whistle_button.is_pressed() else tint


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


## Income readout under the Supply bar: turns green while territory is paying a
## bonus and gold during the final push.
func _update_supply_rate() -> void:
	var rate := game.get_supply_rate(PLAYER_TEAM)
	var text := "+%.1f per second" % rate
	var color := Color(0.6, 0.56, 0.48)
	if game.is_final_push():
		text += "  (final push)"
		color = Color(1.0, 0.82, 0.4)
	elif rate > game.supply_per_second + 0.001:
		text += "  (ground held)"
		color = Color(0.6, 0.85, 0.55)
	rate_label.text = text
	rate_label.add_theme_color_override("font_color", color)


## Connected from Main.final_push_started in Main.tscn.
func _on_final_push_started() -> void:
	show_banner("FINAL PUSH - SUPPLY DOUBLED", Color(1.0, 0.85, 0.35), 2.6)


func _show_opening_tips() -> void:
	var tween := create_tween()
	for tip in OPENING_TIPS:
		tween.tween_callback(show_banner.bind(tip, Color(0.95, 0.9, 0.8), 3.2))
		tween.tween_interval(3.9)


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
func show_banner(text: String, color: Color = Color(0.95, 0.9, 0.8), hold: float = 1.4) -> void:
	banner.text = text
	banner.modulate = color
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_interval(hold)
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
