extends Node
## Headless test of the per-part damage model.
##
##   godot --headless --fixed-fps 60 --path . res://tests/TestDamageModel.tscn
##
## Ten bot planes with their brains switched off are used as test subjects:
## each gets one kind of damage and the same stick inputs as an undamaged
## reference, and the test checks the damaged plane really flies differently.
## Prints DAMAGE_MODEL_OK on success.

var _manager: MatchManager5v5
var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0
var _clock: float = -1.0
var _stage: int = 0
var _events: Array[String] = []

# Blue subjects.
var _reference: PlaneActor
var _left_wing_hit: PlaneActor
var _tail_hit: PlaneActor
var _engine_hit: PlaneActor
var _wing_lost: PlaneActor
# Red subjects.
var _attacker: PlaneActor
var _engine_lost: PlaneActor
var _tail_lost: PlaneActor
var _speed_reference: PlaneActor

var _yaw_start: Dictionary[int, float] = {}
var _pitch_start: Dictionary[int, float] = {}
var _wing_lost_died_at: float = -1.0
var _engine_lost_died_at: float = -1.0
var _tail_lost_died_at: float = -1.0
var _tail_lost_hp_at_death: float = -1.0


func _ready() -> void:
	Profile.persistence_enabled = false
	Profile.reset_to_new_profile(false)
	GameSession.local_player_enabled = false
	GameSession.match_seed = 5
	GameSession.match_duration = 180.0
	var arena: Node = (load(GameSession.SCENE_ARENA) as PackedScene).instantiate()
	add_child(arena)
	_manager = arena.get_node("MatchManager") as MatchManager5v5
	var blue: Array[PlaneActor] = []
	var red: Array[PlaneActor] = []
	for slot: PilotSlot in _manager.get_roster():
		# Brains off: this test flies every plane by writing to PlaneInput itself.
		slot.controller.set_physics_process(false)
		if slot.team == Teams.Id.TEAM_BLUE:
			blue.append(slot.plane)
		else:
			red.append(slot.plane)
		slot.plane.part_state_changed.connect(_on_part_state_changed)
	_reference = blue[0]
	_left_wing_hit = blue[1]
	_tail_hit = blue[2]
	_engine_hit = blue[3]
	_wing_lost = blue[4]
	_attacker = red[0]
	_engine_lost = red[1]
	_tail_lost = red[2]
	_speed_reference = red[3]
	_wing_lost.died.connect(func(_victim: PlaneActor, _killer: PlaneActor) -> void: _wing_lost_died_at = _clock)
	_engine_lost.died.connect(func(_victim: PlaneActor, _killer: PlaneActor) -> void: _engine_lost_died_at = _clock)
	_tail_lost.died.connect(_on_tail_lost_died)
	_test_hit_location()


func _physics_process(delta: float) -> void:
	if _stage < 0:
		return
	if _manager.phase != MatchManager5v5.Phase.ACTIVE:
		return  # Wait out the countdown (and with it the spawn shield).
	if _clock < 0.0:
		_clock = 0.0
	_clock += delta
	match _stage:
		0:
			_apply_all_damage()
			_stage = 1
		1:
			# 1.5 s hands-off: asymmetric damage should pull the plane on its own.
			if _clock >= 1.6:
				_check(_wing_lost.is_spinning_out() or not _wing_lost.alive, "a plane that lost a wing spins out")
				_check(_yaw_drift(_left_wing_hit) > 0.08, "damaged left wing drags the nose left (yaw drift %.3f rad)" % _yaw_drift(_left_wing_hit))
				_check(absf(_yaw_drift(_reference)) < 0.02, "undamaged plane flies straight (yaw drift %.3f rad)" % _yaw_drift(_reference))
				_check(_left_wing_hit.bank > 0.12, "damaged left wing hangs low (bank %.2f rad)" % _left_wing_hit.bank)
				_check(_tail_hit.pitch < -0.03, "damaged tail lets the nose drop (pitch %.3f rad)" % _tail_hit.pitch)
				_check(_engine_lost.has_flag(PlaneActor.FLAG_BURNING), "a destroyed engine is on fire")
				_mark_yaw()
				_set_stick(Vector2(1.0, 0.0))
				_stage = 2
		2:
			# 1.5 s of full right stick: the damaged plane turns away from its bad wing poorly.
			if _clock >= 3.1:
				var clean_turn: float = absf(_yaw_drift(_reference))
				var hurt_turn: float = absf(_yaw_drift(_left_wing_hit))
				_check(clean_turn > 1.0, "reference plane turns normally (%.2f rad in 1.5 s)" % clean_turn)
				_check(hurt_turn < clean_turn * 0.75, "turning away from a damaged wing is much slower (%.2f vs %.2f rad)" % [hurt_turn, clean_turn])
				_mark_pitch()
				_set_stick(Vector2(0.0, 1.0))
				_stage = 3
		3:
			# 1 s of full back stick: a shot-up elevator pulls far less.
			if _clock >= 4.1:
				var clean_pull: float = _reference.pitch - _pitch_start[_reference.get_instance_id()]
				var hurt_pull: float = _tail_hit.pitch - _pitch_start[_tail_hit.get_instance_id()]
				_check(clean_pull > 0.5, "reference plane pitches up normally (%.2f rad in 1 s)" % clean_pull)
				_check(hurt_pull < clean_pull * 0.6, "a damaged tail pitches up far less (%.2f vs %.2f rad)" % [hurt_pull, clean_pull])
				_set_stick(Vector2.ZERO)
				# A nose-heavy plane needs the pilot to hold some back stick.
				_tail_hit.input.steer = Vector2(0.0, 0.4)
				_stage = 4
		4:
			if _clock >= 7.0:
				var slow: float = _engine_hit.speed / _engine_hit.stats.top_speed
				var fast: float = _speed_reference.speed / _speed_reference.stats.top_speed
				_check(fast > 0.93, "healthy engine reaches top speed (%.0f%%)" % (fast * 100.0))
				_check(slow < 0.8, "damaged engine cannot (%.0f%% of top speed)" % (slow * 100.0))
				_check(_tail_hit.alive and _tail_hit.pitch > -0.15, "back stick holds a nose-heavy plane up (pitch %.2f rad)" % _tail_hit.pitch)
				# Field repair brings a damaged part back, with a report.
				_events.clear()
				_left_wing_hit.repair_parts(0.3)
				_check(_left_wing_hit.part_state(PlaneActor.Part.LEFT_WING) == PlaneActor.PartState.OK, "repair patches a damaged wing")
				_check(_events.has("Left wing:OK"), "repair reports the part as OK again")
				_stage = 5
		5:
			if _clock >= 13.0:
				_final_checks()
				_finish()


## locate_hit() is pure geometry, so it can be checked without firing a shot.
func _test_hit_location() -> void:
	var plane: PlaneActor = _reference
	var frame: Transform3D = plane.global_transform
	var ahead: Vector3 = -frame.basis.z
	var cases: Array[Array] = [
		# [entry point (local), bullet direction (local), expected part, description]
		[Vector3(3.0, 0.0, 3.3), Vector3.FORWARD, PlaneActor.Part.RIGHT_WING, "from astern, off to the right"],
		[Vector3(-3.0, 0.0, 3.3), Vector3.FORWARD, PlaneActor.Part.LEFT_WING, "from astern, off to the left"],
		[Vector3(0.3, 0.2, 4.4), Vector3.FORWARD, PlaneActor.Part.TAIL, "from dead astern"],
		[Vector3(0.0, 0.3, -4.4), Vector3.BACK, PlaneActor.Part.ENGINE, "head-on"],
		[Vector3(4.5, 0.0, 0.0), Vector3.LEFT, PlaneActor.Part.HULL, "beam shot at the cockpit"],
		[Vector3(-3.0, 3.3, 0.0), Vector3.DOWN, PlaneActor.Part.LEFT_WING, "from above onto the left wing"],
		[Vector3(0.0, 3.0, 3.3), Vector3.DOWN, PlaneActor.Part.TAIL, "from above onto the tail"],
	]
	for case: Array in cases:
		var entry: Vector3 = case[0]
		var direction: Vector3 = case[1]
		var expected: PlaneActor.Part = case[2]
		var found: PlaneActor.Part = plane.locate_hit(frame * entry, frame.basis * direction)
		_check(found == expected, "hit %s lands on %s (got %s)" % [case[3], PlaneActor.PART_NAMES[expected], PlaneActor.PART_NAMES[found]])
	_check(ahead.length() > 0.9, "sanity: plane has a forward axis")


func _apply_all_damage() -> void:
	# Hull bookkeeping first, on a plane that is not otherwise under test.
	var hull_before: float = _speed_reference.hp
	_speed_reference.apply_damage(100.0, _reference, 0.0, 0.0, PlaneActor.Part.HULL)
	_near(hull_before - _speed_reference.hp, 120.0, "a centre hit does 120% hull damage")
	hull_before = _speed_reference.hp
	_speed_reference.apply_damage(100.0, _reference, 0.0, 0.0, PlaneActor.Part.TAIL)
	_near(hull_before - _speed_reference.hp, 90.0, "a tail hit does 90% hull damage")
	_near(_speed_reference.part_damage_of(PlaneActor.Part.TAIL), 100.0 / (_speed_reference.stats.max_hp * 0.45), "and takes its share off the tail's own pool")
	_check(_speed_reference.part_state(PlaneActor.Part.TAIL) == PlaneActor.PartState.OK, "one bullet does not cripple a part")
	hull_before = _reference.hp
	_reference.apply_damage(100.0, _left_wing_hit, 0.0, 0.0, PlaneActor.Part.ENGINE)
	_near(_reference.hp, hull_before, "team-mates cannot damage each other")
	_near(_reference.part_damage_of(PlaneActor.Part.ENGINE), 0.0, "nor each other's parts")

	_events.clear()
	_hurt(_left_wing_hit, PlaneActor.Part.LEFT_WING, 0.6, _attacker)
	_check(_events.has("Left wing:DAMAGED"), "crossing 40% reports the part as damaged")
	_check(_left_wing_hit.alive and _left_wing_hit.hp_ratio() > 0.6, "60%% wing damage leaves the hull mostly intact (%.0f%%)" % (_left_wing_hit.hp_ratio() * 100.0))
	_hurt(_tail_hit, PlaneActor.Part.TAIL, 0.8, _attacker)
	_check(_tail_hit.part_state(PlaneActor.Part.TAIL) == PlaneActor.PartState.CRITICAL, "80% tail damage is critical")
	_hurt(_engine_hit, PlaneActor.Part.ENGINE, 0.8, _attacker)
	_hurt(_wing_lost, PlaneActor.Part.RIGHT_WING, 1.05, _attacker)
	_check(_events.has("Right wing:DESTROYED"), "a wing can be shot off")
	_check(_wing_lost.alive, "losing a wing does not kill outright")
	_hurt(_engine_lost, PlaneActor.Part.ENGINE, 1.05, _reference)
	_hurt(_tail_lost, PlaneActor.Part.TAIL, 1.05, _reference)
	_check(_engine_lost.alive and _tail_lost.alive, "losing the engine or tail does not kill outright")
	_mark_yaw()
	# The tail-less plane gets full back stick the whole time: it must go down anyway.
	_tail_lost.input.steer = Vector2(0.0, 1.0)


func _final_checks() -> void:
	_check(_wing_lost_died_at > 0.0 and _wing_lost_died_at <= PlaneActor.SPIN_OUT_TIME + 0.3,
			"the spinning plane was destroyed within %.1f s (died at %.2f s)" % [PlaneActor.SPIN_OUT_TIME, _wing_lost_died_at])
	_check(_engine_lost_died_at > 0.0, "the plane with a dead, burning engine went down (%.2f s)" % _engine_lost_died_at)
	_check(_tail_lost_died_at > 0.0, "the plane with no tail went down despite full back stick (%.2f s)" % _tail_lost_died_at)
	_check(_tail_lost_hp_at_death > 0.0, "the tail-less plane died by hitting the sea, not from hull damage")
	# Whoever shot the part off gets the takedown, however the plane finally dies.
	_check(_manager.slot_for_plane(_attacker).kills == 1, "the wing kill is credited to the attacker (kills %d)" % _manager.slot_for_plane(_attacker).kills)
	_check(_manager.slot_for_plane(_reference).kills == 2, "engine and tail kills are credited too (kills %d)" % _manager.slot_for_plane(_reference).kills)
	_check(_manager.team_score(Teams.Id.TEAM_RED) == 1 and _manager.team_score(Teams.Id.TEAM_BLUE) == 2,
			"score is BLUE 2 - 1 RED (got %d - %d)" % [_manager.team_score(Teams.Id.TEAM_BLUE), _manager.team_score(Teams.Id.TEAM_RED)])
	_check(_reference.alive and _left_wing_hit.alive and _tail_hit.alive and _engine_hit.alive, "damaged-but-not-destroyed planes are still flying")


## Deals exactly [param fraction] of a part's health pool to it.
func _hurt(plane: PlaneActor, part: PlaneActor.Part, fraction: float, attacker: PlaneActor) -> void:
	plane.apply_damage(fraction * plane.stats.max_hp * PlaneActor.PART_HEALTH_FRACTION[part], attacker, 0.0, 0.0, part)


func _set_stick(steer: Vector2) -> void:
	# The two engine-test planes are left alone so they fly level the whole time.
	for plane: PlaneActor in [_reference, _left_wing_hit, _tail_hit]:
		plane.input.steer = steer


func _mark_yaw() -> void:
	for plane: PlaneActor in _manager.get_planes():
		_yaw_start[plane.get_instance_id()] = plane.yaw


func _mark_pitch() -> void:
	for plane: PlaneActor in _manager.get_planes():
		_pitch_start[plane.get_instance_id()] = plane.pitch


## Signed yaw change since the last _mark_yaw(). Positive = turned left.
func _yaw_drift(plane: PlaneActor) -> float:
	return wrapf(plane.yaw - _yaw_start[plane.get_instance_id()], -PI, PI)


func _on_part_state_changed(_plane: PlaneActor, part: PlaneActor.Part, state: PlaneActor.PartState) -> void:
	var state_names: Array[String] = ["OK", "DAMAGED", "CRITICAL", "DESTROYED"]
	_events.append("%s:%s" % [PlaneActor.PART_NAMES[part], state_names[state]])


func _on_tail_lost_died(victim: PlaneActor, _killer: PlaneActor) -> void:
	_tail_lost_died_at = _clock
	# hp is zeroed by the time this fires, so judge by altitude: it hit the sea.
	_tail_lost_hp_at_death = 1.0 if victim.global_position.y < 12.0 else 0.0


func _finish() -> void:
	_stage = -1
	if _failures.is_empty():
		print("%d checks passed" % _checks)
		print("DAMAGE_MODEL_OK")
	else:
		for failure: String in _failures:
			print("FAIL: " + failure)
		print("DAMAGE_MODEL_FAILED")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _near(actual: float, expected: float, message: String) -> void:
	_check(absf(actual - expected) < 0.01, "%s (expected %.3f, got %.3f)" % [message, expected, actual])
