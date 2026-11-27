extends Node
## Headless smoke + rules test: plays a full bots-only 5v5 match as fast as the
## CPU allows and checks the match rules actually held.
##
##   godot --headless --fixed-fps 60 --path . res://tests/TestMatchSim.tscn
##
## Prints MATCH_SIM_OK on success. Optional user args: `-- seed=7 duration=300 verbose=1`.

const ARENA_SCENE: String = "res://scenes/arena/DogfightArena5v5.tscn"
const MAX_SIM_SECONDS: float = 520.0

var _manager: MatchManager5v5
var _failures: PackedStringArray = PackedStringArray()
var _sim_time: float = 0.0
var _death_times: Dictionary[int, float] = {}
var _shot_kills: int = 0
var _crashes: int = 0
var _respawns: int = 0
var _friendly_hits: int = 0
var _damage_events: int = 0
var _min_respawn_gap: float = INF
var _clump_samples: int = 0
var _clump_hits: int = 0
var _sample_timer: float = 0.0
var _finished: bool = false
var _max_bullets: int = 0
var _shots: int = 0
var _bullet_hits: int = 0
var _parts_destroyed: Array[int] = []
var _collisions: int = 0
var _collision_speeds: Array[float] = []
var _fall_times: Array[float] = []
var _first_loss_time: Dictionary[int, float] = {}
var _parts_damaged: int = 0
## With verbose=1: what each plane was doing over its last few seconds.
var _history: Dictionary[int, Array] = {}
var _history_timer: float = 0.0
var _state_samples: Array[int] = [0, 0, 0, 0, 0, 0]
var _engage_distance: float = 0.0
var _in_range: int = 0
var _in_range_20: int = 0
var _in_range_8: int = 0
var _in_range_firing: int = 0


func _ready() -> void:
	var seed_value: int = 7
	var duration: float = 300.0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("seed="):
			seed_value = int(argument.trim_prefix("seed="))
		elif argument.begins_with("duration="):
			duration = float(argument.trim_prefix("duration="))
	Profile.persistence_enabled = false
	Profile.reset_to_new_profile(false)
	GameSession.local_player_enabled = false
	GameSession.match_seed = seed_value
	GameSession.match_duration = duration
	seed(seed_value)

	var arena: Node = (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	_manager = arena.get_node("MatchManager") as MatchManager5v5
	_manager.match_ended.connect(_on_match_ended)
	_parts_destroyed.resize(PlaneActor.PART_COUNT)
	_parts_destroyed.fill(0)
	_manager.midair_collisions.planes_collided.connect(_on_planes_collided)
	_manager.bullet_system.bullet_hit.connect(func(_victim: PlaneActor, _shooter: PlaneActor, _at: Vector3) -> void: _bullet_hits += 1)
	for plane: PlaneActor in _manager.get_planes():
		plane.damaged.connect(_on_damaged)
		plane.died.connect(_on_died)
		plane.respawned.connect(_on_respawned)
		plane.shot_fired.connect(func(_shooter: PlaneActor) -> void: _shots += 1)
		plane.part_state_changed.connect(_on_part_state_changed)
	_check(_manager.get_planes().size() == 10, "expected 10 planes, got %d" % _manager.get_planes().size())
	var blue: int = 0
	for slot: PilotSlot in _manager.get_roster():
		if slot.team == Teams.Id.TEAM_BLUE:
			blue += 1
		_check(slot.controller is SquadAIController, "seat %d has no bot controller" % slot.index)
	_check(blue == 5, "expected 5 blue seats, got %d" % blue)


func _physics_process(delta: float) -> void:
	if _finished:
		return
	_sim_time += delta
	_max_bullets = maxi(_max_bullets, _manager.bullet_system.active_bullet_count())
	if OS.get_cmdline_user_args().has("verbose=1"):
		_record_history(delta)
	_sample_timer -= delta
	if _sample_timer <= 0.0:
		_sample_timer = 0.5
		_sample_clumping()
	if _sim_time > MAX_SIM_SECONDS:
		_check(false, "match did not end within %d simulated seconds" % int(MAX_SIM_SECONDS))
		_report()


func _on_damaged(victim: PlaneActor, _amount: float, attacker: PlaneActor) -> void:
	_damage_events += 1
	if attacker != null and attacker != victim and attacker.team == victim.team:
		_friendly_hits += 1


func _on_planes_collided(_first: PlaneActor, _second: PlaneActor, _first_part: int, _second_part: int, closing_speed: float) -> void:
	_collisions += 1
	_collision_speeds.append(closing_speed)


func _on_part_state_changed(plane: PlaneActor, part: PlaneActor.Part, state: PlaneActor.PartState) -> void:
	if state == PlaneActor.PartState.DESTROYED:
		_parts_destroyed[part] += 1
		# Remember when each plane first lost a part, to time how long it then flew.
		if not _first_loss_time.has(plane.get_instance_id()):
			_first_loss_time[plane.get_instance_id()] = _sim_time
	elif state == PlaneActor.PartState.DAMAGED:
		_parts_damaged += 1


func _on_died(victim: PlaneActor, killer: PlaneActor) -> void:
	_death_times[victim.get_instance_id()] = _sim_time
	if _first_loss_time.has(victim.get_instance_id()):
		_fall_times.append(_sim_time - _first_loss_time[victim.get_instance_id()])
		_first_loss_time.erase(victim.get_instance_id())
	if _manager.phase != MatchManager5v5.Phase.ACTIVE:
		return
	if killer != null:
		_shot_kills += 1
	else:
		_crashes += 1
		if OS.get_cmdline_user_args().has("verbose=1"):
			var worst: float = 0.0
			for damage: float in victim.part_damage:
				worst = maxf(worst, damage)
			var bot: SquadAIController = _manager.slot_for_plane(victim).controller as SquadAIController
			for line: String in _history.get(victim.get_instance_id(), []):
				print("      ", line)
			print("  uncaused loss t=%.0f %s at %s speed %.0f pitch %.0f bank %.0f lift %.2f worst damage %.2f ground %s state %d over field %s" % [
					_sim_time, victim.name, str(victim.global_position.round()), victim.speed, rad_to_deg(victim.pitch), rad_to_deg(victim.bank),
					victim.lift_ratio(), worst, victim.is_on_ground(), bot.state if bot != null else -1, victim.airfield_at(victim.global_position) != null])


## Notes what every bot is doing a few times a second (verbose runs only).
func _record_history(delta: float) -> void:
	_history_timer -= delta
	if _history_timer > 0.0:
		return
	_history_timer = 0.5
	for slot: PilotSlot in _manager.get_roster():
		var plane: PlaneActor = slot.plane
		var bot: SquadAIController = slot.controller as SquadAIController
		if bot == null or not plane.alive:
			continue
		_state_samples[bot.state] += 1
		if bot.state == SquadAIController.State.ENGAGE and bot.target != null and is_instance_valid(bot.target):
			var distance: float = plane.global_position.distance_to(bot.target.global_position)
			var off: float = rad_to_deg(Ballistics.angle_off_nose(plane.global_position, plane.forward(), bot.target.global_position))
			_engage_distance += distance
			if distance < plane.stats.gun_range:
				_in_range += 1
				if off < 20.0:
					_in_range_20 += 1
				if off < 8.0:
					_in_range_8 += 1
				if plane.input.firing:
					_in_range_firing += 1
		var lines: Array = _history.get_or_add(plane.get_instance_id(), [])
		lines.append("t=%.1f state %d y %.0f vy %.0f v %.0f pitch %.0f bank %.0f g %.1f alpha %.1f stall %.2f stick %.2v thr %.1f" % [_sim_time, bot.state,
				plane.global_position.y, plane.velocity.y, plane.speed, rad_to_deg(plane.pitch), rad_to_deg(plane.bank), plane.load_factor(),
				rad_to_deg(plane.flight.alpha), plane.flight.stall, plane.input.steer, plane.throttle])
		if lines.size() > 14:
			lines.pop_front()


func _on_respawned(plane: PlaneActor) -> void:
	var key: int = plane.get_instance_id()
	if not _death_times.has(key):
		return  # Initial spawn.
	_respawns += 1
	_min_respawn_gap = minf(_min_respawn_gap, _sim_time - _death_times[key])
	_death_times.erase(key)


## Counts how often two living team-mates fly within 25 m of each other.
func _sample_clumping() -> void:
	var planes: Array[PlaneActor] = _manager.get_planes()
	for first: int in range(planes.size()):
		for second: int in range(first + 1, planes.size()):
			var a: PlaneActor = planes[first]
			var b: PlaneActor = planes[second]
			if not a.alive or not b.alive or a.team != b.team:
				continue
			_clump_samples += 1
			if a.global_position.distance_to(b.global_position) < 25.0:
				_clump_hits += 1


func _on_match_ended(_winning_team: int) -> void:
	_report()


func _report() -> void:
	_finished = true
	var blue: int = _manager.team_score(Teams.Id.TEAM_BLUE)
	var red: int = _manager.team_score(Teams.Id.TEAM_RED)
	var total_deaths: int = 0
	var total_kills: int = 0
	for slot: PilotSlot in _manager.get_roster():
		total_deaths += slot.deaths
		total_kills += slot.kills
	var clump_rate: float = float(_clump_hits) / float(maxi(_clump_samples, 1))
	print("sim_time=%.1fs  score blue=%d red=%d  winner=%d" % [_sim_time, blue, red, _manager.winning_team])
	print("shot_kills=%d crashes=%d respawns=%d damage_events=%d friendly_hits=%d" % [_shot_kills, _crashes, _respawns, _damage_events, _friendly_hits])
	print("min_respawn_gap=%.2fs clump_rate=%.3f max_bullets=%d" % [_min_respawn_gap, clump_rate, _max_bullets])
	# One bullet can damage several parts, so accuracy counts bullets, not damage events.
	var accuracy: float = float(_bullet_hits) / float(maxi(_shots, 1))
	print("shots=%d bullet_hits=%d accuracy=%.1f%% hits_per_takedown=%.1f" % [_shots, _bullet_hits, accuracy * 100.0, float(_bullet_hits) / float(maxi(blue + red, 1))])
	var lost: PackedStringArray = PackedStringArray()
	for index: int in range(PlaneActor.PART_COUNT):
		if _parts_destroyed[index] > 0:
			lost.append("%s %d" % [PlaneActor.PART_NAMES[index], _parts_destroyed[index]])
	print("parts damaged=%d destroyed: %s" % [_parts_damaged, ", ".join(lost)])
	var average_fall: float = 0.0
	for fall: float in _fall_times:
		average_fall += fall / float(_fall_times.size())
	var fastest_collision: float = 0.0
	for collision_speed: float in _collision_speeds:
		fastest_collision = maxf(fastest_collision, collision_speed)
	print("collisions=%d (fastest %.0f m/s)  crippled planes flew on for %.1fs on average before going in" % [_collisions, fastest_collision, average_fall])
	for slot: PilotSlot in _manager.get_roster():
		print("  %-5s %-14s lvl%-2d skill %.2f  K %d  D %d  %s" % [Teams.name_of(slot.team), slot.display_name,
				slot.commander_level, slot.bot_skill, slot.kills, slot.deaths, slot.plane.plane_data.display_name])

	if OS.get_cmdline_user_args().has("verbose=1"):
		print("bot half-seconds by state [patrol, engage, evade, recover, takeoff, upset]: %s" % str(_state_samples))
		print("engaging: mean distance %.0f m; in gun range %d half-seconds, of which nose within 20 deg %d, within 8 deg %d, firing %d" % [
				_engage_distance / float(maxi(_state_samples[1], 1)), _in_range, _in_range_20, _in_range_8, _in_range_firing])
	_check(_manager.phase == MatchManager5v5.Phase.FINISHED, "match is not in the FINISHED phase")
	_check(blue + red == total_deaths, "score %d does not equal total deaths %d" % [blue + red, total_deaths])
	_check(total_kills == _shot_kills, "credited kills %d != credited deaths %d" % [total_kills, _shot_kills])
	# Everyone has to take off and fly to the fight first, and turning fights
	# between real aeroplanes take a while: five losses in five minutes is a
	# slow match, fewer means the bots are not fighting.
	_check(blue + red >= 5, "too little combat: only %d takedowns" % (blue + red))
	_check(_friendly_hits == 0, "%d friendly-fire hits got through" % _friendly_hits)
	# Every loss is now a crash; "uncredited" ones are those nobody caused.
	_check(_crashes <= maxi(floori(float(blue + red) / 3.0), 2), "too many losses nobody caused: %d of %d" % [_crashes, blue + red])
	_check(_collisions <= maxi(blue + red, 6), "bots collide too often: %d collisions" % _collisions)
	_check(_respawns > 0, "nobody respawned")
	var delay: float = GameSession.respawn_delay
	_check(_min_respawn_gap >= delay - 0.05, "a respawn took %.2fs, less than the %.1fs delay" % [_min_respawn_gap, delay])
	_check(blue <= _manager.score_limit() and red <= _manager.score_limit(), "score went past the limit")
	_check(clump_rate < 0.05, "team-mates clump: %.1f%% of samples within 25 m" % (clump_rate * 100.0))
	_check(_max_bullets < BulletSystem.MAX_BULLETS, "bullet pool saturated")
	_check(accuracy > 0.02 and accuracy < 0.25, "bot accuracy %.1f%% is outside the human-like 2-25%% band" % (accuracy * 100.0))
	_check(_parts_damaged > 0, "no part was ever damaged")

	if _failures.is_empty():
		print("MATCH_SIM_OK")
	else:
		for failure: String in _failures:
			print("FAIL: " + failure)
		print("MATCH_SIM_FAILED")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
