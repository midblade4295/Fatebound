extends Node
## Development trace: flies the player's plane off the runway with a simple
## scripted hand and prints what it does, and watches the bots do the same.
##   godot --headless --fixed-fps 60 --path . res://tools/TakeoffTrace.tscn [-- pull=0.6 rudder=1 plane=mustang]

var _manager: MatchManager5v5
var _player: PlaneActor
var _field: Airfield
var _clock: float = 0.0
var _next_print: float = 0.0
var _pull: float = 0.6
var _hold_straight: bool = true
var _run_time: float = 60.0
var _landing: bool = false
var _approach_pitch: float = 0.0
var _approach_throttle: float = 0.3
var _approach_speed: float = 1.35
var _placed: bool = false


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("pull="):
			_pull = argument.trim_prefix("pull=").to_float()
		elif argument.begins_with("rudder="):
			_hold_straight = argument.trim_prefix("rudder=") != "0"
		elif argument.begins_with("time="):
			_run_time = argument.trim_prefix("time=").to_float()
	Profile.persistence_enabled = false
	Profile.reset_to_new_profile(false)
	GameSession.local_player_enabled = true
	GameSession.ground_start = true
	GameSession.match_seed = 21
	GameSession.match_duration = 400.0
	var arena: Node = (load(GameSession.SCENE_ARENA) as PackedScene).instantiate()
	add_child(arena)
	_manager = arena.get_node("MatchManager") as MatchManager5v5
	_player = _manager.local_slot().plane
	_field = _player.home_airfield()
	_manager.local_slot().controller.set_physics_process(false)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("plane="):
			var data: PlaneData = GameCatalog.find_plane(StringName(argument.trim_prefix("plane=")))
			_player.stats = data.build_stock_stats(1)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("land="):
			_landing = true
			_approach_pitch = deg_to_rad(argument.trim_prefix("land=").to_float())
		elif argument.begins_with("throttle="):
			_approach_throttle = argument.trim_prefix("throttle=").to_float()
		elif argument.begins_with("speed="):
			_approach_speed = argument.trim_prefix("speed=").to_float()
	if _landing:
		for slot: PilotSlot in _manager.get_roster():
			slot.controller.set_physics_process(false)
		_player.touched_down.connect(func(_plane: PlaneActor, sink: float, wheels: bool) -> void:
			print("TOUCHDOWN sink %.1f m/s on wheels %s at %.0f m along, speed %.0f" % [sink, wheels, _field.runway_coordinates(_player.global_position).y, _player.speed]))
	print("player: top %.0f stall %.0f/%.0f takeoff %.0f m/s, mass %.0f" % [_player.stats.top_speed, _player.stats.stall_speed,
			_player.stats.landing_stall_speed, _player.takeoff_speed(), _player.stats.mass])


func _physics_process(delta: float) -> void:
	if _manager.phase != MatchManager5v5.Phase.ACTIVE:
		return
	_clock += delta
	var input: PlaneInput = _player.input
	if _landing:
		_fly_landing(input)
	elif _player.alive:
		if _player.is_on_ground():
			if not _player.is_engine_running() and _clock < 0.2:
				input.press_engine()
			input.throttle = 1.0
			var place: Vector2 = _field.runway_coordinates(_player.global_position)
			var direction: Vector3 = _field.takeoff_direction()
			var runway_yaw: float = atan2(-direction.x, -direction.z)
			var steer_x: float = 0.0
			if _hold_straight:
				steer_x = clampf(-wrapf(runway_yaw + atan(place.x / 70.0) - _player.yaw, -PI, PI) * 5.0, -1.0, 1.0)
			input.steer = Vector2(steer_x, _pull if _player.speed >= _player.takeoff_speed() else 0.0)
		else:
			if _player.is_gear_down() and _player.height_above_ground() > 12.0:
				input.press_gear()
			var target_pitch: float = deg_to_rad(8.0)
			var stick_y: float = clampf((target_pitch - _player.pitch) * 2.5 - _player.flight.angular_velocity.x * 0.8, -0.6, 0.6)
			var stick_x: float = clampf(_player.bank * 2.0 + _player.flight.angular_velocity.z * 0.4, -1.0, 1.0)
			input.steer = Vector2(stick_x, stick_y)
	if _landing and _player.alive and _player.is_on_ground() and _player.speed < 0.2 and _clock > 3.0 and _run_time > _clock + 1.0:
		print("STOPPED at %.0f m along" % _field.runway_coordinates(_player.global_position).y)
		_run_time = _clock + 0.5
	if _clock >= _next_print:
		_next_print += 0.5 if _clock < 30.0 else 2.0
		var place: Vector2 = _field.runway_coordinates(_player.global_position)
		print("t=%5.1f %s v=%5.1f h=%6.1f vy=%5.1f pitch=%5.1f bank=%5.1f along=%5.0f off=%5.1f a=%5.1f g=%4.2f stall=%.2f thr=%.2f steer=%.2v trim=%.2v yaw=%.1f beta=%.1f rud=%.2f w=%.3v" % [
			_clock, "GND" if _player.is_on_ground() else ("AIR" if _player.alive else "DEAD"), _player.speed, _player.height_above_ground(), _player.velocity.y,
			rad_to_deg(_player.pitch), rad_to_deg(_player.bank), place.y, place.x, rad_to_deg(_player.flight.alpha), _player.load_factor(),
			_player.flight.stall, _player.throttle, input.steer, _player.flight.trim, rad_to_deg(_player.yaw), rad_to_deg(_player.flight.beta), _player.flight.rudder, _player.flight.angular_velocity])
	if _clock >= _run_time:
		for slot: PilotSlot in _manager.get_roster():
			var plane: PlaneActor = slot.plane
			var bot: SquadAIController = slot.controller as SquadAIController
			print("  team%d %s alive=%s ground=%s h=%.0f v=%.0f state=%s deaths=%d" % [int(slot.team), plane.plane_id,
					plane.alive, plane.is_on_ground(), plane.global_position.y, plane.speed, str(bot.state) if bot != null else "-", slot.deaths])
		get_tree().quit()


func _fly_landing(input: PlaneInput) -> void:
	if not _placed:
		_placed = true
		var direction: Vector3 = _field.takeoff_direction()
		_player.set_engine_running(true)
		_player.set_gear_down(true)
		_player.input.throttle = _approach_throttle
		_player.throttle = _approach_throttle
		_player.speed = _player.stats.landing_stall_speed * _approach_speed
		_player.teleport(Transform3D(Basis.looking_at(direction, Vector3.UP), _field.runway_start() - direction * 250.0 + Vector3.UP * 45.0))
		return
	if not _player.alive:
		return
	if _player.is_on_ground():
		input.steer = Vector2.ZERO
		input.throttle = 0.0
		return
	input.throttle = _approach_throttle
	var stick_y: float = clampf((_approach_pitch - _player.pitch) * 2.5 - _player.flight.angular_velocity.x * 0.8, -0.6, 0.6)
	var stick_x: float = clampf(_player.bank * 2.0 + _player.flight.angular_velocity.z * 0.4, -1.0, 1.0)
	input.steer = Vector2(stick_x, stick_y)
