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
##   bottom-right FIRE and the two rudder pedals, with the throttle lever beside them
##                and ENGINE / GEAR above
##   centre       countdown / respawn / out-of-bounds messages, results panel
##   world layer  target diamonds, threat arrows, gun pipper, and a marker
##                on the player's own airfield (HudWorldOverlay)
##   anywhere else  drag to look around (LookArea turns the chase camera)
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
## The flight read-out warns of buffet past this share of the stalling angle.
const BUFFET_WARNING: float = 0.88
## On the take-off run the tail counts as still down with the nose above this.
const TAIL_DOWN_PITCH: float = deg_to_rad(7.0)
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
## The flight read-out adds the true airspeed once it is this many mph more
## than the indicated.
const TRUE_SPEED_SHOWN: float = 8.0
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
## The landing menu: repair, refuel, both, or cash out. Built in code.
var _service_panel: PanelContainer
var _service_title: Label
var _repair_button: Button
var _refuel_button: Button
var _both_button: Button
var _cash_button: Button
var _sky_clear: bool = false

@onready var _overlay: HudWorldOverlay = %WorldOverlay
@onready var _radar: Radar = %Radar
@onready var _damage_diagram: DamageDiagram = %DamageDiagram
@onready var _title_label: Label = %TitleLabel
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
@onready var _rudder_left: ActionButton = %RudderLeftButton
@onready var _rudder_right: ActionButton = %RudderRightButton
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
	_build_service_panel()


## Connects the HUD to a running match. [param local_plane] may be null when
## spectating a bots-only match; the flight controls are hidden in that case.
func bind(manager: MatchManager5v5, chase_camera: ChaseCamera, local_plane: PlaneActor) -> void:
	match_manager = manager
	camera = chase_camera
	player = local_plane
	var view_team: Teams.Id = player.team if player != null else Teams.Id.TEAM_BLUE
	(%LookArea as LookArea).camera = chase_camera
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
	manager.sky_cleared.connect(_on_sky_cleared)
	manager.bullet_system.bullet_hit.connect(_on_bullet_hit)
	_on_score_changed(manager.pilots_left(Teams.Id.TEAM_BLUE), manager.pilots_left(Teams.Id.TEAM_RED))
	_mode_label.text = "%dv%d" % [manager.team_size(), manager.team_size()]

	var has_player: bool = player != null
	_joystick.visible = has_player
	_fire_button.visible = has_player
	_rudder_left.visible = has_player
	_rudder_right.visible = has_player
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
	# The corner panel shows what the sortie is worth so far.
	_title_label.visible = has_player


func _process(delta: float) -> void:
	if match_manager == null:
		return
	_update_clock()
	_update_flight_panel()
	_update_buttons()
	_update_sortie()
	_alert_time = maxf(_alert_time - delta, 0.0)
	_repair_hint_time = maxf(_repair_hint_time - delta, 0.0)
	_update_messages()
	_age_kill_feed(delta)


# ---------------------------------------------------------------------------
# Per-frame updates
# ---------------------------------------------------------------------------

func _update_clock() -> void:
	# A sortie has no clock to beat: this is how long it has been going.
	var seconds: int = floori(match_manager.elapsed)
	_timer_label.text = "%02d:%02d" % [floori(float(seconds) / 60.0), seconds % 60]


## The bounty read-out and the landing menu.
func _update_sortie() -> void:
	if player == null:
		_service_panel.visible = false
		return
	var manager: MatchManager5v5 = match_manager
	_title_label.text = "BOUNTY %d    next kill +%d" % [manager.bounty, manager.next_kill_value()]
	_title_label.add_theme_color_override(&"font_color", UiStyle.GOLD if manager.bounty > 0 else UiStyle.WHITE)
	var open: bool = manager.can_service()
	_service_panel.visible = open
	if not open:
		return
	var ordered: int = player.service_orders
	var repair: int = manager.service_cost(true, false) if ordered & PlaneActor.SERVICE_REPAIR == 0 else 0
	var refuel: int = manager.service_cost(false, true) if ordered & PlaneActor.SERVICE_REFUEL == 0 else 0
	var funds: int = manager.funds()
	_service_title.text = "HOME    carrying %d gold    you have %d" % [manager.bounty, Profile.gold]
	_repair_button.text = _service_caption("REPAIR", repair, player.needs_repair(), ordered & PlaneActor.SERVICE_REPAIR != 0)
	_repair_button.disabled = repair <= 0 or repair > funds
	_refuel_button.text = _service_caption("REFUEL", refuel, player.needs_fuel(), ordered & PlaneActor.SERVICE_REFUEL != 0)
	_refuel_button.disabled = refuel <= 0 or refuel > funds
	_both_button.text = "BOTH\n%d gold" % (repair + refuel) if repair > 0 and refuel > 0 else "BOTH\n-"
	_both_button.disabled = repair <= 0 or refuel <= 0 or repair + refuel > funds
	_cash_button.text = "CASH OUT\nbank %d gold" % manager.bounty


func _service_caption(job: String, cost: int, needed: bool, ordered: bool) -> String:
	if ordered:
		return "%s\nin hand" % job
	if not needed:
		return "%s\nnot needed" % job
	return "%s\n%d gold" % [job, cost]


func _update_flight_panel() -> void:
	var shown: PlaneActor = player if player != null else camera.target
	if shown == null or not is_instance_valid(shown):
		return
	# SPD is what the airspeed indicator reads: it is what the wings feel, so
	# the stall and the approach are at the same figure at any height. Up
	# high the plane is covering the ground faster than that.
	var readout: String = "SPD %3d mph   ALT %4d m" % [roundi(shown.speed_mph()), roundi(maxf(shown.altitude(), 0.0))]
	# Once the two have drifted apart, the true speed as well: that is the
	# figure the record books quote.
	if shown.true_speed_mph() - shown.speed_mph() >= TRUE_SPEED_SHOWN:
		readout = "SPD %3d mph (true %d)   ALT %4d m" % [roundi(shown.speed_mph()), roundi(shown.true_speed_mph()), roundi(maxf(shown.altitude(), 0.0))]
	# How hard the wings are pulling, once it is more than a gentle turn.
	if not shown.is_on_ground():
		readout += "   %+d m/s" % roundi(shown.climb_speed())
		if absf(shown.load_factor()) >= 1.5 or shown.load_factor() < 0.4:
			readout += "   %.1f G" % shown.load_factor()
		if shown.is_spinning():
			readout += "   SPIN"
		elif shown.is_stalling():
			readout += "   STALL"
		elif shown.attack_ratio() > BUFFET_WARNING:
			readout += "   BUFFET"
	if shown.broken_gear_mask() != 0:
		readout += "   GEAR BROKEN"
	elif shown.gear_deploy > 0.02:
		readout += "   GEAR %s" % ("DOWN" if shown.gear_deploy >= 0.98 else "...")
	if shown.is_propeller_broken():
		readout += "   NO PROP"
	# The player's engine burns fuel; anyone's leaks once the tank is holed.
	if shown.burns_fuel or shown.fuel < 0.995:
		readout += "   FUEL %d%%" % roundi(shown.fuel * 100.0)
	_flight_label.text = readout


func _update_buttons() -> void:
	if player == null or not is_instance_valid(player):
		return
	var dead: bool = not player.alive
	_fire_button.disabled = dead or player.weapons_locked
	# The pedals work on the ground too: that is how the nose is held straight.
	_rudder_left.disabled = dead
	_rudder_right.disabled = dead
	var grounded: bool = player.is_on_ground()
	_fire_button.disabled = _fire_button.disabled or grounded
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
			detail = "One life. Land to keep what you earn."
			if player != null and player.alive and player.is_on_ground():
				detail = "Start your engine and take off"
		MatchManager5v5.Phase.ACTIVE:
			if player != null and player.alive and player.is_out_of_bounds():
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
	var takeoff_mph: int = roundi(player.takeoff_speed() * PlaneActor.MPH)
	if player.is_on_ground():
		if player.is_servicing():
			return "Ground crew at work... %d%%" % roundi(player.service_progress() * 100.0)
		var at_home: bool = _home != null and _home.contains(player.global_position)
		var wants_repair: bool = at_home and player.needs_service()
		if match_manager.can_service():
			if player.service_orders != 0:
				return "Hold still - ground crew are on their way"
			return "Repair, refuel, or cash out and keep the bounty"
		if wants_repair and player.input.throttle <= PlaneActor.BRAKE_THROTTLE:
			return "Braking - stop to repair, refuel or cash out"
		if player.broken_gear_mask() != 0 or player.is_propeller_broken():
			return "Wrecked away from home - this one is not flying again" if not at_home else "Sliding to a stop..."
		if not player.is_engine_running():
			if player.engine_power() <= 0.0:
				return "Engine dead - stop on your own airfield to have it repaired"
			return "Press ENGINE to start up"
		var indicated: float = player.indicated_speed()
		if player.input.throttle < 0.5 and indicated < player.takeoff_speed() * 0.5:
			return "Open the throttle to roll (closed throttle = brakes)"
		if indicated < player.takeoff_speed() * 0.3:
			return "Hold it straight with the stick or pedals - the engine pulls left"
		if indicated < player.takeoff_speed():
			if player.pitch > TAIL_DOWN_PITCH:
				return "Stick forward to lift the tail   (fly it off at %d mph)" % takeoff_mph
			return "Tail up - hold it level and straight until %d mph" % takeoff_mph
		return "Ease the stick back and let it fly off"
	if player.is_going_down():
		return "You are going down - fly it as far as you can"
	if player.is_spinning():
		return "SPIN - close the throttle, stick forward, rudder against the turn"
	if player.is_stalling():
		return "STALL - ease the stick forward and let the speed come back"
	var home_distance: float = INF
	if _home != null:
		home_distance = Vector2(player.global_position.x - _home.global_position.x, player.global_position.z - _home.global_position.z).length()
	if player.is_gear_down():
		# Going up under power with the wheels still down is a take-off (or a
		# go-around), not an approach.
		if player.velocity.y > 1.0 and player.input.throttle > 0.8:
			return "Climbing away - press GEAR to raise the wheels"
		if home_distance < APPROACH_RANGE and player.height_above_ground() < 260.0:
			var sink: float = maxf(-player.velocity.y, 0.0)
			var arrival: float = player.predicted_touchdown_sink()
			var verdict: String = "good: hold the nose up and let it settle"
			if arrival > PlaneActor.GEAR_COLLAPSE_SINK:
				verdict = "too steep, the gear will not take it: flare!"
			elif arrival > PlaneActor.FIRM_LANDING_SINK:
				verdict = "firm: ease the stick back"
			elif player.pitch < -PlaneActor.PROP_STRIKE_PITCH:
				verdict = "nose too low"
			elif player.indicated_speed() > player.stats.landing_stall_speed * 1.45:
				verdict = "fast: it will float and bounce"
			return "Approach: %d mph (stalls at %d)   descent %.0f m/s - %s" % [roundi(player.speed_mph()), roundi(player.stats.landing_stall_speed * PlaneActor.MPH), sink, verdict]
		if player.indicated_speed() > player.stats.top_speed * 0.6:
			return "Wheels are down - press GEAR to raise them"
	if _repair_hint_time > 0.0 and player.needs_repair():
		return "Damaged - land at your airfield and stop: repairs cost gold"
	if _sky_clear and match_manager.bounty > 0:
		return "The sky is clear - land at your airfield to claim %d gold" % match_manager.bounty
	if player.fuel < 0.25 and player.fuel > 0.0:
		return "Fuel is low - get home while the engine still runs"
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
	_alert_text = "Ground crew are done - cleared for take-off"
	_alert_time = ALERT_TIME
	_repair_hint_time = 0.0


func _on_sky_cleared(winning_team: int) -> void:
	if player == null or winning_team != int(player.team):
		return
	_sky_clear = true
	_alert_text = "The sky is clear - now get it home to claim the bounty"
	_alert_time = ALERT_TIME * 2.0


func _on_match_ended(winning_team: int) -> void:
	var manager: MatchManager5v5 = match_manager
	match manager.outcome:
		MatchManager5v5.Outcome.HOME:
			_result_title.text = "HOME SAFE"
			_result_title.add_theme_color_override(&"font_color", UiStyle.GOLD)
		MatchManager5v5.Outcome.LOST:
			_result_title.text = "KILLED"
			_result_title.add_theme_color_override(&"font_color", Color(1.0, 0.5, 0.45))
		_:
			# Nobody was flying: a battle between bots.
			_result_title.text = "DRAW" if winning_team == MatchManager5v5.DRAW else "%s WINS" % Teams.name_of(winning_team as Teams.Id).to_upper()
			_result_title.add_theme_color_override(&"font_color", UiStyle.WHITE)
	_result_score.text = "Pilots left:  BLUE %d  -  %d RED" % [
			manager.pilots_left(Teams.Id.TEAM_BLUE), manager.pilots_left(Teams.Id.TEAM_RED)]
	_reward_label.text = _describe_rewards()
	_results.visible = true
	_service_panel.visible = false
	_joystick.visible = false
	_fire_button.visible = false
	_rudder_left.visible = false
	_rudder_right.visible = false
	_engine_button.visible = false
	_gear_button.visible = false
	_throttle_lever.visible = false


func _describe_rewards() -> String:
	var manager: MatchManager5v5 = match_manager
	var slot: PilotSlot = manager.local_slot()
	if slot == null:
		return ""
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Kills %d" % slot.kills)
	if manager.service_spent > 0:
		lines.append("Repairs and fuel: %d gold" % manager.service_spent)
	if manager.outcome == MatchManager5v5.Outcome.HOME:
		lines.append("Bounty banked: +%d gold" % manager.final_bounty)
	else:
		lines.append("Bounty lost: %d gold" % manager.final_bounty)
		var plane: PlaneData = slot.plane_data
		if manager.plane_lost:
			lines.append("%s lost - a new one is %d gold" % [plane.display_name, plane.price])
		elif manager.insured:
			lines.append("%s lost - the insurance has replaced it" % plane.display_name)
		else:
			lines.append("%s lost - another has been issued to you" % plane.display_name)
		lines.append("Everything fitted to it is still yours")
	lines.append("You have %d gold" % Profile.gold)
	return "\n".join(lines)


func _on_repair_pressed() -> void:
	match_manager.buy_service(true, false)


func _on_refuel_pressed() -> void:
	match_manager.buy_service(false, true)


func _on_both_pressed() -> void:
	match_manager.buy_service(true, true)


func _on_cash_out_pressed() -> void:
	match_manager.cash_out()


## The menu a pilot gets when they have stopped on their own airfield: four
## big buttons along the bottom of the screen, between the stick and the
## flight controls.
func _build_service_panel() -> void:
	_service_panel = PanelContainer.new()
	_service_panel.name = "ServicePanel"
	_service_panel.add_theme_stylebox_override(&"panel", UiStyle.panel(Color(UiStyle.NAVY, 0.94), 26, UiStyle.OUTLINE, 5, 18))
	_service_panel.anchor_left = 0.5
	_service_panel.anchor_right = 0.5
	_service_panel.anchor_top = 0.5
	_service_panel.anchor_bottom = 0.5
	_service_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_service_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_service_panel.offset_top = 40.0
	_service_panel.offset_bottom = 40.0
	_service_panel.visible = false
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 14)
	_service_panel.add_child(column)
	_service_title = Label.new()
	_service_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiStyle.style_label(_service_title, 30, UiStyle.GOLD, 7)
	column.add_child(_service_title)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	column.add_child(row)
	_repair_button = _service_button(row, "RepairButton", Teams.COLOR_BLUE, _on_repair_pressed)
	_refuel_button = _service_button(row, "RefuelButton", Teams.COLOR_BLUE, _on_refuel_pressed)
	_both_button = _service_button(row, "BothButton", Teams.COLOR_BLUE, _on_both_pressed)
	_cash_button = _service_button(row, "CashOutButton", UiStyle.GOLD, _on_cash_out_pressed)
	(get_node("Root") as Control).add_child(_service_panel)


func _service_button(row: HBoxContainer, button_name: String, color: Color, action: Callable) -> Button:
	var button: Button = Button.new()
	button.name = button_name
	button.custom_minimum_size = Vector2(250.0, 130.0)
	UiStyle.style_button(button, color, 30)
	button.pressed.connect(action)
	row.add_child(button)
	return button


func _on_hangar_pressed() -> void:
	GameSession.goto_hangar()


# ---------------------------------------------------------------------------
# Styling
# ---------------------------------------------------------------------------

func _apply_style() -> void:
	(%TopLeft as PanelContainer).add_theme_stylebox_override(&"panel", UiStyle.panel(Color(UiStyle.NAVY, 0.82), 22))
	UiStyle.style_label(_title_label, 24)
	UiStyle.style_label(_flight_label, 22, Color(0.82, 0.93, 1.0), 6)

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
