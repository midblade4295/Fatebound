extends Node
## Headless test of the human path: 1 player + 9 bots, driven only through the
## same Input actions the touch HUD presses.
##
##   godot --headless --fixed-fps 60 --path . res://tests/TestPlayerFlow.tscn
##
## Script: fly level and fire -> evade roll -> nitro gadget -> dive into the sea.
## Checks bullets spawn, the roll and gadget go on cooldown, the crash gives RED
## a ticket and the player is back in the air 5 seconds later.
## Prints PLAYER_FLOW_OK on success.

enum Step { WAIT_START, FIRE, ROLL, GADGET, DIVE, WAIT_RESPAWN, DONE }

var _manager: MatchManager5v5
var _player: PlaneActor
var _hud: Hud
var _camera: ChaseCamera
var _step: Step = Step.WAIT_START
var _step_time: float = 0.0
var _failures: PackedStringArray = PackedStringArray()
var _shots: int = 0
var _death_time: float = -1.0
var _clock: float = 0.0
var _red_before_crash: int = 0
var _speed_before_nitro: float = 0.0
var _max_fov: float = 0.0
var _evades: int = 0
var _gadgets: int = 0


func _ready() -> void:
	Profile.persistence_enabled = false
	Profile.reset_to_new_profile(false)
	GameSession.local_player_enabled = true
	GameSession.match_seed = 11
	GameSession.match_duration = 180.0
	GameSession.bot_skill = 0.0  # Gentle bots: this test is about the player.
	var arena: Node = (load(GameSession.SCENE_ARENA) as PackedScene).instantiate()
	add_child(arena)
	_manager = arena.get_node("MatchManager") as MatchManager5v5
	_hud = arena.get_node("HUD") as Hud
	_camera = arena.get_node("ChaseCamera") as ChaseCamera
	var slot: PilotSlot = _manager.local_slot()
	_check(slot != null and slot.is_human and slot.controller is PlayerController, "seat 0 on BLUE is the local player")
	_check(_manager.get_planes().size() == 10, "ten planes spawned")
	var bots: int = 0
	for other: PilotSlot in _manager.get_roster():
		if other.controller is SquadAIController:
			bots += 1
	_check(bots == 9, "nine seats are filled by bots (got %d)" % bots)
	if slot == null:
		_finish()
		return
	_player = slot.plane
	_check(_player.team == Teams.Id.TEAM_BLUE and _player.is_human, "player plane is a human BLUE plane")
	_check(_camera.target == _player, "chase camera follows the player")
	_check(_hud.player == _player, "HUD is bound to the player")
	_player.shot_fired.connect(func(_plane: PlaneActor) -> void: _shots += 1)
	_player.evade_started.connect(func(_plane: PlaneActor) -> void: _evades += 1)
	_player.gadget_used.connect(func(_plane: PlaneActor, _type: int) -> void: _gadgets += 1)
	_player.died.connect(func(_victim: PlaneActor, _killer: PlaneActor) -> void: _death_time = _clock)


func _physics_process(delta: float) -> void:
	if _step == Step.DONE:
		return
	_clock += delta
	_step_time += delta
	_max_fov = maxf(_max_fov, _camera.camera.fov)
	match _step:
		Step.WAIT_START:
			# Weapons are locked during the countdown.
			Input.action_press(GameSession.ACTION_FIRE)
			if _manager.phase == MatchManager5v5.Phase.ACTIVE:
				_check(_shots == 0, "no shots during the countdown (got %d)" % _shots)
				_next(Step.FIRE)
		Step.FIRE:
			Input.action_press(GameSession.ACTION_FIRE)
			Input.action_press(GameSession.ACTION_STEER_RIGHT, 0.6)
			if _step_time >= 1.0:
				Input.action_release(GameSession.ACTION_FIRE)
				Input.action_release(GameSession.ACTION_STEER_RIGHT)
				# ~10.6 rounds/s for one second.
				_check(_shots >= 8 and _shots <= 13, "about ten shots in one second of fire (got %d)" % _shots)
				_check(_player.yaw < -0.2, "steering right turned the plane right (yaw %.2f)" % _player.yaw)
				_check(_player.bank < -0.2, "the plane banks into the turn (bank %.2f)" % _player.bank)
				Input.action_press(GameSession.ACTION_EVADE)
				_next(Step.ROLL)
		Step.ROLL:
			if _step_time >= 0.3:
				Input.action_release(GameSession.ACTION_EVADE)
				_check(_evades == 1, "evade roll started")
				_check(_player.is_evading(), "plane reports it is evading")
				_check(_player.evade_cooldown_ratio() > 0.5, "evade roll is on cooldown")
				_speed_before_nitro = _player.speed
				Input.action_press(GameSession.ACTION_GADGET)
				_next(Step.GADGET)
		Step.GADGET:
			if _step_time >= 1.5:
				Input.action_release(GameSession.ACTION_GADGET)
				_check(_gadgets == 1, "gadget activated once")
				_check(_player.speed > _speed_before_nitro * 1.1, "nitro raised speed (%.0f -> %.0f)" % [_speed_before_nitro, _player.speed])
				_check(_player.gadget_cooldown_ratio() > 0.5, "gadget is on cooldown")
				_red_before_crash = _manager.team_score(Teams.Id.TEAM_RED)
				_next(Step.DIVE)
		Step.DIVE:
			Input.action_press(GameSession.ACTION_PITCH_DOWN)
			if not _player.alive:
				Input.action_release(GameSession.ACTION_PITCH_DOWN)
				_check(_manager.team_score(Teams.Id.TEAM_RED) >= _red_before_crash + 1, "crashing gives RED a ticket")
				_check(_manager.local_slot().deaths == 1, "the crash counts as a loss for the player")
				_check(_max_fov > _camera.base_fov + 6.0, "camera FOV widened with nitro/dive (max %.1f)" % _max_fov)
				_next(Step.WAIT_RESPAWN)
			elif _step_time > 20.0:
				_check(false, "plane never hit the sea")
				_finish()
		Step.WAIT_RESPAWN:
			if _player.alive:
				var waited: float = _clock - _death_time
				_check(absf(waited - GameSession.respawn_delay) < 0.1, "respawned after %.2fs (expected %.1f)" % [waited, GameSession.respawn_delay])
				_check(is_equal_approx(_player.hp, _player.stats.max_hp), "respawned at full health")
				_check(_player.global_position.z > 1000.0, "respawned over the BLUE carrier")
				_check(_player.has_flag(PlaneActor.FLAG_SHIELDED), "spawn protection is active")
				_finish()
			elif _step_time > 8.0:
				_check(false, "player never respawned")
				_finish()


func _next(step: Step) -> void:
	_step = step
	_step_time = 0.0


func _finish() -> void:
	_step = Step.DONE
	for action: StringName in [GameSession.ACTION_FIRE, GameSession.ACTION_EVADE, GameSession.ACTION_GADGET,
			GameSession.ACTION_PITCH_DOWN, GameSession.ACTION_STEER_RIGHT]:
		Input.action_release(action)
	if _failures.is_empty():
		print("PLAYER_FLOW_OK")
	else:
		for failure: String in _failures:
			print("FAIL: " + failure)
		print("PLAYER_FLOW_FAILED")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
