extends Node
## Headless smoke + rules test: plays a full bots-only 5v5 match as fast as the
## CPU allows and checks the match rules actually held.
##
##   godot --headless --fixed-fps 60 --path . res://tests/TestMatchSim.tscn
##
## Prints MATCH_SIM_OK on success. Optional user args: `-- seed=7 duration=180`.

const ARENA_SCENE: String = "res://scenes/arena/DogfightArena5v5.tscn"
const MAX_SIM_SECONDS: float = 400.0

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
var _parts_destroyed: Array[int] = [0, 0, 0, 0, 0]
var _parts_damaged: int = 0


func _ready() -> void:
	var seed_value: int = 7
	var duration: float = 180.0
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


func _on_part_state_changed(_plane: PlaneActor, part: PlaneActor.Part, state: PlaneActor.PartState) -> void:
	if state == PlaneActor.PartState.DESTROYED:
		_parts_destroyed[part] += 1
	elif state == PlaneActor.PartState.DAMAGED:
		_parts_damaged += 1


func _on_died(victim: PlaneActor, killer: PlaneActor) -> void:
	_death_times[victim.get_instance_id()] = _sim_time
	if _manager.phase != MatchManager5v5.Phase.ACTIVE:
		return
	if killer != null:
		_shot_kills += 1
	else:
		_crashes += 1


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
	print("parts damaged=%d destroyed engine=%d left_wing=%d right_wing=%d tail=%d" % [_parts_damaged,
			_parts_destroyed[PlaneActor.Part.ENGINE], _parts_destroyed[PlaneActor.Part.LEFT_WING],
			_parts_destroyed[PlaneActor.Part.RIGHT_WING], _parts_destroyed[PlaneActor.Part.TAIL]])
	for slot: PilotSlot in _manager.get_roster():
		print("  %-5s %-14s lvl%-2d skill %.2f  K %d  D %d  %s" % [Teams.name_of(slot.team), slot.display_name,
				slot.commander_level, slot.bot_skill, slot.kills, slot.deaths, slot.plane.plane_data.display_name])

	_check(_manager.phase == MatchManager5v5.Phase.FINISHED, "match is not in the FINISHED phase")
	_check(blue + red == total_deaths, "score %d does not equal total deaths %d" % [blue + red, total_deaths])
	_check(total_kills == _shot_kills, "credited kills %d != shot kills %d" % [total_kills, _shot_kills])
	_check(blue + red >= 8, "too little combat: only %d takedowns" % (blue + red))
	_check(_friendly_hits == 0, "%d friendly-fire hits got through" % _friendly_hits)
	_check(_crashes <= maxi(floori(float(blue + red) / 3.0), 2), "bots crash too often: %d of %d losses" % [_crashes, blue + red])
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
