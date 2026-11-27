class_name Hud
extends CanvasLayer
## In-match HUD for landscape phones (scenes/hud/HUD.tscn).
##
##   top-left     Commander Level badge, Hangar XP, speed / altitude / fuel,
##                and under it the damage diagram: the only "health" display
##                there is, because planes have no health bar
##   top-centre   compact score bar:  BLUE score | 5v5 + clock | RED score
##   top-right    circular radar
##   bottom-left  virtual flight stick
##   bottom-right FIRE, EVADE ROLL and the Tactical Gadget button, with the
##                throttle lever beside them and ENGINE / GEAR above
##   centre       countdown / respawn / out-of-bounds messages, results panel
##   world layer  target diamonds, threat arrows, gun pipper, and a marker
##                on the player's own airfield (HudWorldOverlay)
##
## The centre line under the headline talks the pilot through whatever comes
## next: start the engine, open the throttle, the speed to lift off at, raise
## the wheels, and on the way home the approach speed and rate of descent.
##
## The HUD never changes gameplay state. It reads the match manager and the
## player's plane every frame and the touch controls press Input actions.

const KILL_FEED_LINES: int = 4
const KILL_FEED_TIME: float = 5.0
const ALERT_TIME: float = 2.8
## What losing or hurting each part means for the pilot, indexed by PlaneActor.Part.
const PART_EFFECTS: Array[String] = [
	"leaking fuel", "losing power", "pulling left", "pulling right", "pulling left", "pulling right",
	"nose heavy", "nose wandering", "weak turns", "uneven in hard turns", "uneven in hard turns",
	"weak roll", "weak roll", "weak pitch", "weak pitch",
]
## Headline for each PlaneActor.PartState (0 = repaired).
const STATE_WORDS: Array[String] = ["PATCHED", "HIT", "CRITICAL", "SHOT OFF"]
## How long the "land to repair" reminder stays up after the plane is damaged.
const REPAIR_HINT_TIME: float = 7.0
## Approach guidance appears inside this distance of home with the wheels down.
const APPROACH_RANGE: float = 1600.0

var match_manager: MatchManager5v5
var player: PlaneActor
var camera: ChaseCamera

var _feed_ages: Array[float] = []
var _alert_text: String = ""
var _alert_time: float = 0.0
var _repair_hint_time: float = 0.0
var _home: Airfield

@onready var _overlay: HudWorldOverlay = %WorldOverlay
@onready var _radar: Radar = %Radar
@onready var _damage_diagram: DamageDiagram = %DamageDiagram
@onready var _level_label: Label = %LevelLabel
@onready var _title_label: Label = %TitleLabel
@onready var _xp_bar: ProgressBar = %XpBar
@onready var _flight_label: Label = %FlightLabel
@onready var _blue_score: Label = %BlueScore
@onready var _red_score: Label = %RedScore
@onready var _mode_label: Label = %ModeLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _kill_feed: VBoxContainer = %KillFeed
@onready var _center_message: Label = %CenterMessage
@onready var _sub_message: Label = %SubMessage
@onready var _joystick: TouchFlightStick = %Joystick
@onready var _fire_button: ActionButton = %FireButton
@onready var _roll_button: ActionButton = %RollButton
@onready var _gadget_button: ActionButton = %GadgetButton
@onready var _engine_button: ActionButton = %EngineButton
@onready var _gear_button: ActionButton = %GearButton
@onready var _throttle_lever: ThrottleLever = %ThrottleLever
@onready var _results: PanelContainer = %Results
@onready var _result_title: Label = %ResultTitle
@onready var _result_score: Label = %ResultScore
@onready var _reward_label: Label = %RewardLabel
@onready var _hangar_button: Button = %HangarButton


func _ready() -> void:
	_apply_style()
	_results.visible = false
	_center_message.text = ""
	_sub_message.text = ""
	_hangar_button.pressed.connect(_on_hangar_pressed)


## Connects the HUD to a running match. [param local_plane] may be null when
## spectating a bots-only match; the flight controls are hidden in that case.
func bind(manager: MatchManager5v5, chase_camera: ChaseCamera, local_plane: PlaneActor) -> void:
	match_manager = manager
	camera = chase_camera
	player = local_plane
	var view_team: Teams.Id = player.team if player != null else Teams.Id.TEAM_BLUE
	_overlay.match_manager = manager
	_overlay.camera = chase_camera.camera
	_overlay.player = player
	_overlay.view_team = view_team
	_radar.match_manager = manager
	_radar.player = player if player != null else chase_camera.target
	_radar.view_team = view_team

	manager.score_changed.connect(_on_score_changed)
	manager.takedown.connect(_on_takedown)
	manager.match_ended.connect(_on_match_ended)
	manager.bullet_system.bullet_hit.connect(_on_bullet_hit)
	_on_score_changed(manager.team_score(Teams.Id.TEAM_BLUE), manager.team_score(Teams.Id.TEAM_RED))
	_mode_label.text = "%dv%d" % [manager.team_size(), manager.team_size()]

	var has_player: bool = player != null
	_joystick.visible = has_player
	_fire_button.visible = has_player
	_roll_button.visible = has_player
	_gadget_button.visible = has_player
	_engine_button.visible = has_player
	_gear_button.visible = has_player
	_throttle_lever.visible = has_player
	_throttle_lever.plane = player
	_home = player.home_airfield() if has_player else null
	_overlay.home = _home
	_radar.home = _home
	_damage_diagram.plane = player
	_damage_diagram.visible = has_player
	for plane: PlaneActor in manager.get_planes():
		plane.part_state_changed.connect(_on_part_state_changed)
	if has_player:
		player.damaged.connect(_on_player_damaged)
		player.touched_down.connect(_on_player_touched_down)
		player.serviced.connect(_on_player_serviced)
		_gadget_button.caption = player.stats.gadget_name.to_upper() if player.has_gadget() else "NO GADGET"
	var level: int = Profile.commander_level()
	_level_label.text = str(level)
	_title_label.text = "COMMANDER LEVEL"
	_xp_bar.value = CommanderProgression.level_progress(Profile.commander_xp) * 100.0


func _process(delta: float) -> void:
	if match_manager == null:
		return
	_update_clock()
	_update_flight_panel()
	_update_buttons()
	_alert_time = maxf(_alert_time - delta, 0.0)
	_repair_hint_time = maxf(_repair_hint_time - delta, 0.0)
	_update_messages()
	_age_kill_feed(delta)


# ---------------------------------------------------------------------------
# Per-frame updates
# ---------------------------------------------------------------------------

func _update_clock() -> void:
	var seconds: int = ceili(match_manager.time_left)
	var minutes: int = floori(float(seconds) / 60.0)
	_timer_label.text = "%02d:%02d" % [minutes, seconds % 60]
	# Last 30 seconds: the clock turns red.
	var urgent: bool = seconds <= 30 and match_manager.phase == MatchManager5v5.Phase.ACTIVE
	_timer_label.add_theme_color_override(&"font_color", Color(1.0, 0.45, 0.4) if urgent else UiStyle.WHITE)


func _update_flight_panel() -> void:
	var shown: PlaneActor = player if player != null else camera.target
	if shown == null or not is_instance_valid(shown):
		return
	var readout: String = "SPD %3d km/h   ALT %4d m" % [roundi(shown.speed_kmh()), roundi(maxf(shown.altitude(), 0.0))]
	if shown.broken_gear_mask() != 0:
		readout += "   GEAR BROKEN"
	elif shown.gear_deploy > 0.02:
		readout += "   GEAR %s" % ("DOWN" if shown.gear_deploy >= 0.98 else "...")
	if shown.is_propeller_broken():
		readout += "   NO PROP"
	# Fuel only matters once the tank is holed, so it only shows then.
	if shown.fuel < 0.995:
		readout += "   FUEL %d%%" % roundi(shown.fuel * 100.0)
	_flight_label.text = readout


func _update_buttons() -> void:
	if player == null or not is_instance_valid(player):
		return
	var dead: bool = not player.alive
	_fire_button.disabled = dead or player.weapons_locked
	_roll_button.disabled = dead
	_roll_button.cooldown_ratio = 0.0 if dead else player.evade_cooldown_ratio()
	_roll_button.cooldown_seconds = 0.0
	_gadget_button.disabled = dead or not player.has_gadget()
	var gadget_ratio: float = 0.0 if dead else player.gadget_cooldown_ratio()
	_gadget_button.cooldown_ratio = gadget_ratio
	_gadget_button.cooldown_seconds = gadget_ratio * player.stats.gadget_cooldown
	var grounded: bool = player.is_on_ground()
	_fire_button.disabled = _fire_button.disabled or grounded
	_roll_button.disabled = _roll_button.disabled or grounded
	# ENGINE: lamp on while it runs; greyed out when there is nothing to start.
	var running: bool = player.is_engine_running()
	_engine_button.disabled = dead or (not running and player.engine_power() <= 0.0)
	_engine_button.lit = running
	_engine_button.caption_text = "STOP" if running else "START"
	# GEAR: lamp on while down; locked while the plane is standing on it.
	_gear_button.disabled = dead or grounded
	_gear_button.lit = player.is_gear_down()
	_gear_button.caption_text = "GEAR UP" if player.is_gear_down() else "GEAR DN"


func _update_messages() -> void:
	var headline: String = ""
	var detail: String = ""
	match match_manager.phase:
		MatchManager5v5.Phase.COUNTDOWN:
			headline = str(ceili(match_manager.countdown_left))
			detail = "First to %d takedowns" % match_manager.score_limit()
			if player != null and player.alive and player.is_on_ground():
				detail = "Start your engine and take off"
		MatchManager5v5.Phase.ACTIVE:
			var slot: PilotSlot = match_manager.local_slot()
			if slot != null and slot.respawn_timer > 0.0:
				headline = "SHOT DOWN"
				detail = "A new plane is being wheeled out: %d" % ceili(slot.respawn_timer)
			elif player != null and player.alive and player.is_out_of_bounds():
				headline = "RETURN TO BATTLE"
				detail = "Autopilot is turning you around"
			elif _alert_time > 0.0:
				detail = _alert_text
			elif player != null and player.alive:
				detail = _flight_guidance()
		MatchManager5v5.Phase.FINISHED:
			pass
	if _center_message.text != headline:
		_center_message.text = headline
	if _sub_message.text != detail:
		_sub_message.text = detail


## One line telling the pilot what to do next, or "" when they need no telling.
func _flight_guidance() -> String:
	var takeoff_kmh: int = roundi(player.takeoff_speed() * 3.6)
	if player.is_on_ground():
		if player.is_servicing():
			return "Repairing and refuelling... %d%%" % roundi(player.service_progress() * 100.0)
		var at_home: bool = _home != null and _home.contains(player.global_position)
		var wants_repair: bool = at_home and player.needs_service()
		if wants_repair and player.speed < PlaneActor.SERVICE_MAX_SPEED:
			return "Hold still - ground crew are on their way"
		if wants_repair and player.input.throttle <= PlaneActor.BRAKE_THROTTLE:
			return "Braking - stop to be repaired"
		if player.broken_gear_mask() != 0 or player.is_propeller_broken():
			return "Wrecked away from home - this one is not flying again" if not at_home else "Sliding to a stop..."
		if not player.is_engine_running():
			if player.engine_power() <= 0.0:
				return "Engine dead - stop on your own airfield to have it repaired"
			return "Press ENGINE to start up"
		if player.input.throttle < 0.5 and player.speed < player.takeoff_speed() * 0.5:
			return "Open the throttle to roll (closed throttle = brakes)"
		if player.speed < player.takeoff_speed():
			return "Take-off speed %d km/h" % takeoff_kmh
		return "Ease the stick back to lift off"
	if player.is_going_down():
		return "You are going down - fly it as far as you can"
	var home_distance: float = INF
	if _home != null:
		home_distance = Vector2(player.global_position.x - _home.global_position.x, player.global_position.z - _home.global_position.z).length()
	if player.is_gear_down():
		if home_distance < APPROACH_RANGE and player.height_above_ground() < 260.0:
			var sink: float = maxf(-player.velocity.y, 0.0)
			var arrival: float = player.predicted_touchdown_sink()
			var verdict: String = "good"
			if arrival > PlaneActor.GEAR_COLLAPSE_SINK:
				verdict = "too steep, the gear will not take it"
			elif arrival > PlaneActor.FIRM_LANDING_SINK:
				verdict = "firm"
			elif player.pitch < -PlaneActor.PROP_STRIKE_PITCH:
				verdict = "nose too low"
			return "Approach: %d km/h (stalls below %d)   descent %.0f m/s - %s" % [roundi(player.speed_kmh()), takeoff_kmh, sink, verdict]
		if player.speed > player.stats.top_speed * 0.6:
			return "Wheels are down - press GEAR to raise them"
	if _repair_hint_time > 0.0 and player.needs_service():
		return "Damaged - land at your airfield and stop to be repaired"
	if not player.is_engine_running() and player.engine_power() > 0.0:
		return "Engine off - press ENGINE to restart"
	return ""


func _age_kill_feed(delta: float) -> void:
	for index: int in range(_feed_ages.size() - 1, -1, -1):
		_feed_ages[index] += delta
		var line: Control = _kill_feed.get_child(index) as Control
		line.modulate.a = clampf(KILL_FEED_TIME - _feed_ages[index], 0.0, 1.0)
		if _feed_ages[index] >= KILL_FEED_TIME:
			_feed_ages.remove_at(index)
			_kill_feed.remove_child(line)
			line.queue_free()


# ---------------------------------------------------------------------------
# Match events
# ---------------------------------------------------------------------------

func _on_score_changed(blue_score: int, red_score: int) -> void:
	_blue_score.text = str(blue_score)
	_red_score.text = str(red_score)


func _on_takedown(victim: PilotSlot, killer: PilotSlot) -> void:
	var line: Label = Label.new()
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if killer != null:
		line.text = "%s  >>  %s" % [killer.display_name, victim.display_name]
		UiStyle.style_label(line, 26, Teams.color_of(killer.team).lightened(0.35), 7)
	else:
		line.text = "%s crashed" % victim.display_name
		UiStyle.style_label(line, 26, Color(0.85, 0.88, 0.93), 7)
	_kill_feed.add_child(line)
	_feed_ages.append(0.0)
	while _kill_feed.get_child_count() > KILL_FEED_LINES:
		var oldest: Node = _kill_feed.get_child(0)
		_kill_feed.remove_child(oldest)
		oldest.queue_free()
		_feed_ages.remove_at(0)


func _on_bullet_hit(_victim: PlaneActor, shooter: PlaneActor, _world_position: Vector3) -> void:
	if shooter == player and player != null:
		_overlay.show_hit_marker()


## Damage reports: the player's own parts, and enemy parts the player shot off.
func _on_part_state_changed(plane: PlaneActor, part: PlaneActor.Part, state: PlaneActor.PartState) -> void:
	if player == null:
		return
	var part_name: String = PlaneActor.PART_NAMES[part]
	if plane == player:
		_alert_text = _describe_own_damage(part, state)
		_alert_time = ALERT_TIME
		if state != PlaneActor.PartState.OK:
			_repair_hint_time = ALERT_TIME + REPAIR_HINT_TIME
	elif state == PlaneActor.PartState.DESTROYED and plane.recent_attacker() == player:
		_alert_text = "%s: %s shot off!" % [plane.pilot_name, part_name.to_lower()]
		if not PlaneActor.PART_DETACHES[part]:
			_alert_text = "%s: %s knocked out!" % [plane.pilot_name, part_name.to_lower()]
		_alert_time = ALERT_TIME


func _describe_own_damage(part: PlaneActor.Part, state: PlaneActor.PartState) -> String:
	var part_name: String = PlaneActor.PART_NAMES[part].to_upper()
	if state == PlaneActor.PartState.DESTROYED:
		match part:
			PlaneActor.Part.ENGINE:
				return "ENGINE DEAD - you are gliding"
			PlaneActor.Part.FUSELAGE:
				return "FUEL TANK RUPTURED - engine will stop"
	if state == PlaneActor.PartState.OK:
		return "%s %s" % [part_name, STATE_WORDS[state]]
	return "%s %s - %s" % [part_name, STATE_WORDS[state], PART_EFFECTS[part]]


func _on_player_damaged(_victim: PlaneActor, _amount: float, _attacker: PlaneActor) -> void:
	_overlay.show_damage_flash()


func _on_player_touched_down(_plane: PlaneActor, sink_speed: float, on_wheels: bool) -> void:
	var broken: PackedStringArray = PackedStringArray()
	var legs: int = player.broken_gear_mask()
	if legs == (PlaneActor.GEAR_LEFT | PlaneActor.GEAR_RIGHT):
		broken.append("undercarriage collapsed")
	elif legs != 0:
		broken.append("%s leg collapsed" % ("left" if legs == PlaneActor.GEAR_LEFT else "right"))
	if player.is_propeller_broken():
		broken.append("propeller smashed")
	if not broken.is_empty():
		var headline: String = "ROUGH LANDING" if player.is_gear_down() else "BELLY LANDING"
		_alert_text = "%s - %s" % [headline, ", ".join(broken)]
	elif not on_wheels:
		_alert_text = "BELLY LANDING"
	elif sink_speed > PlaneActor.FIRM_LANDING_SINK:
		_alert_text = "FIRM LANDING - the wings felt that"
	else:
		_alert_text = "Down safely - close the throttle to brake"
	_alert_time = ALERT_TIME * 1.5


func _on_player_serviced(_plane: PlaneActor) -> void:
	_alert_text = "Repaired and refuelled - cleared for take-off"
	_alert_time = ALERT_TIME
	_repair_hint_time = 0.0


func _on_match_ended(winning_team: int) -> void:
	var view_team: Teams.Id = player.team if player != null else Teams.Id.TEAM_BLUE
	if winning_team == MatchManager5v5.DRAW:
		_result_title.text = "DRAW"
		_result_title.add_theme_color_override(&"font_color", UiStyle.WHITE)
	elif winning_team == int(view_team):
		_result_title.text = "VICTORY"
		_result_title.add_theme_color_override(&"font_color", UiStyle.GOLD)
	else:
		_result_title.text = "DEFEAT"
		_result_title.add_theme_color_override(&"font_color", Color(1.0, 0.5, 0.45))
	_result_score.text = "BLUE %d  -  %d RED" % [
			match_manager.team_score(Teams.Id.TEAM_BLUE), match_manager.team_score(Teams.Id.TEAM_RED)]
	_reward_label.text = _describe_rewards()
	_results.visible = true
	_joystick.visible = false
	_fire_button.visible = false
	_roll_button.visible = false
	_gadget_button.visible = false
	_engine_button.visible = false
	_gear_button.visible = false
	_throttle_lever.visible = false


func _describe_rewards() -> String:
	var rewards: MatchRewards = match_manager.last_rewards
	var slot: PilotSlot = match_manager.local_slot()
	if rewards == null or slot == null:
		return ""
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Takedowns %d    Losses %d" % [slot.kills, slot.deaths])
	lines.append("+%d coins" % rewards.coins)
	for index: int in range(rewards.card_ids.size()):
		var card: ComponentCard = GameCatalog.find_card(rewards.card_ids[index])
		if card != null:
			lines.append("%s x%d  (%s)" % [card.display_name, rewards.card_counts[index], card.rarity_name()])
	return "\n".join(lines)


func _on_hangar_pressed() -> void:
	GameSession.goto_hangar()


# ---------------------------------------------------------------------------
# Styling
# ---------------------------------------------------------------------------

func _apply_style() -> void:
	(%TopLeft as PanelContainer).add_theme_stylebox_override(&"panel", UiStyle.panel(Color(UiStyle.NAVY, 0.82), 22))
	(%LevelBadge as PanelContainer).add_theme_stylebox_override(&"panel", UiStyle.panel(Teams.COLOR_BLUE, 20, UiStyle.WHITE, 4, 6))
	UiStyle.style_label(_level_label, 54)
	UiStyle.style_label(_title_label, 24)
	UiStyle.style_label(_flight_label, 22, Color(0.82, 0.93, 1.0), 6)
	UiStyle.style_bar(_xp_bar, UiStyle.XP_CYAN, 18.0)

	(%BluePanel as PanelContainer).add_theme_stylebox_override(&"panel", UiStyle.panel(Teams.COLOR_BLUE, 18))
	(%RedPanel as PanelContainer).add_theme_stylebox_override(&"panel", UiStyle.panel(Teams.COLOR_RED, 18))
	(%CenterPanel as PanelContainer).add_theme_stylebox_override(&"panel", UiStyle.panel(Color(UiStyle.NAVY, 0.92), 18))
	UiStyle.style_label(_blue_score, 52)
	UiStyle.style_label(_red_score, 52)
	UiStyle.style_label(_mode_label, 30)
	UiStyle.style_label(_timer_label, 26)

	UiStyle.style_label(_center_message, 96, UiStyle.GOLD, 16)
	UiStyle.style_label(_sub_message, 34, UiStyle.WHITE, 9)

	_results.add_theme_stylebox_override(&"panel", UiStyle.panel(Color(UiStyle.NAVY, 0.95), 30, UiStyle.OUTLINE, 6, 30))
	UiStyle.style_label(_result_title, 96, UiStyle.GOLD, 16)
	UiStyle.style_label(_result_score, 40)
	UiStyle.style_label(_reward_label, 28, Color(0.86, 0.94, 1.0), 6)
	UiStyle.style_button(_hangar_button, UiStyle.GREEN, 40)
