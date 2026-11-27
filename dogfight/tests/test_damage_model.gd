extends Node
## Headless test of the per-part damage model.
##
##   godot --headless --fixed-fps 60 --path . res://tests/TestDamageModel.tscn
##
## Three layers: bullet paths traced through the hit boxes; real bullets flown
## by BulletSystem (drop, drag, pass-through) at a cruising plane; and how each
## kind of damage changes the way a plane flies.
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
var _bullet_target: PlaneActor
var _live_stage: int = 0
var _live_hp: float = 0.0
var _live_tail: float = 0.0
var _live_engine: float = 0.0

var _yaw_start: Dictionary[int, float] = {}
var _pitch_start: Dictionary[int, float] = {}
var _wing_lost_died_at: float = -1.0
var _rudder_wander: float = 0.0
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
	_bullet_target = red[4]
	_wing_lost.died.connect(func(_victim: PlaneActor, _killer: PlaneActor) -> void: _wing_lost_died_at = _clock)
	_engine_lost.died.connect(func(_victim: PlaneActor, _killer: PlaneActor) -> void: _engine_lost_died_at = _clock)
	_tail_lost.died.connect(_on_tail_lost_died)
	_test_bullet_paths()


func _physics_process(delta: float) -> void:
	if _stage < 0:
		return
	if _manager.phase != MatchManager5v5.Phase.ACTIVE:
		return  # Wait out the countdown (and with it the spawn shield).
	if _clock < 0.0:
		_clock = 0.0
	_clock += delta
	_run_live_fire()
	match _stage:
		0:
			_test_pass_through()
			_apply_all_damage()
			_stage = 1
		1:
			# 1.5 s hands-off: asymmetric damage should pull the plane on its own.
			_rudder_wander = maxf(_rudder_wander, absf(_yaw_drift(_attacker)))
			if _clock >= 1.6:
				_check(_rudder_wander > 0.012, "with no rudder the nose wanders from side to side (%.3f rad)" % _rudder_wander)
				_check(absf(_attacker.bank) < 0.05, "but the wings stay level (bank %.3f rad)" % _attacker.bank)
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
				var rudderless_turn: float = absf(_yaw_drift(_attacker))
				_check(rudderless_turn < clean_turn * 0.75 and rudderless_turn > clean_turn * 0.4,
						"without a rudder the plane still turns, but weakly (%.2f vs %.2f rad)" % [rudderless_turn, clean_turn])
				_check(_reference.flap_deploy() > 0.9, "pulling hard drops the combat flaps (%.2f)" % _reference.flap_deploy())
				_check(_reference.control_state.x > 0.9, "and the model is told the stick is hard right")
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
				_check(_reference.flap_deploy() < 0.05, "flaps come back up when the stick is released (%.2f)" % _reference.flap_deploy())
				# Flaps: shoot one off and compare a hard left turn against the clean plane.
				_hurt(_engine_hit, PlaneActor.Part.RIGHT_FLAP, 1.05, _attacker)
				_check(_engine_hit.part_state(PlaneActor.Part.RIGHT_FLAP) == PlaneActor.PartState.DESTROYED, "a flap can be shot off")
				_check(_engine_hit.alive and not _engine_hit.is_spinning_out(), "losing a flap does not bring the plane down")
				_mark_yaw()
				_reference.input.steer = Vector2(-1.0, 0.0)
				_engine_hit.input.steer = Vector2(-1.0, 0.0)
				_stage = 5
		5:
			if _clock >= 8.5:
				var clean_left: float = absf(_yaw_drift(_reference))
				var one_flap_left: float = absf(_yaw_drift(_engine_hit))
				_check(one_flap_left < clean_left * 0.92, "with the right flap gone, a hard left turn is slower (%.2f vs %.2f rad)" % [one_flap_left, clean_left])
				var flap_node: Node3D = _engine_hit.visual.get_node("FlapRight") as Node3D
				var rudder_node: Node3D = _attacker.visual.get_node("Rudder") as Node3D
				_check(flap_node != null and not flap_node.visible, "the shot-off flap is gone from the model")
				_check(rudder_node != null and not rudder_node.visible, "the shot-off rudder is gone from the model")
				var clean_flap: Node3D = _reference.visual.get_node("FlapLeft") as Node3D
				_check(clean_flap.visible and clean_flap.rotation.x > 0.3, "the clean plane's flaps are visibly down in the turn (%.2f rad)" % clean_flap.rotation.x)
				var clean_rudder: Node3D = _reference.visual.get_node("Rudder") as Node3D
				_check(clean_rudder.rotation.y < -0.3, "and its rudder is over to the left (%.2f rad)" % clean_rudder.rotation.y)
				_reference.input.steer = Vector2.ZERO
				_engine_hit.input.steer = Vector2.ZERO
				_stage = 6
		6:
			if _clock >= 13.0:
				_final_checks()
				_finish()


## The path a bullet takes through the airframe decides what it hits. These
## are straight lines in the plane's own space (-Z nose, +X right, +Y up),
## traced through the hit boxes with no bullets fired.
func _test_bullet_paths() -> void:
	var boxes: PlaneHitboxes = _reference.hitboxes
	var none: Array[int] = []
	var cases: Array[Array] = [
		# [start, direction, parts in the order they are struck, description]
		[Vector3(5.2, -0.5, 10.0), Vector3.FORWARD, [PlaneActor.Part.RIGHT_WING], "from astern, out along the right wing"],
		[Vector3(-5.2, -0.5, 10.0), Vector3.FORWARD, [PlaneActor.Part.LEFT_WING], "from astern, out along the left wing"],
		[Vector3(2.5, -0.5, 10.0), Vector3.FORWARD, [PlaneActor.Part.RIGHT_FLAP, PlaneActor.Part.RIGHT_WING], "from astern into the inner right wing: flap first, then the wing"],
		[Vector3(-2.5, -0.5, 10.0), Vector3.FORWARD, [PlaneActor.Part.LEFT_FLAP, PlaneActor.Part.LEFT_WING], "from astern into the inner left wing"],
		[Vector3(0.0, 0.0, 10.0), Vector3.FORWARD, [PlaneActor.Part.RUDDER, PlaneActor.Part.TAIL, PlaneActor.Part.HULL, PlaneActor.Part.ENGINE], "from dead astern, straight up the fuselage"],
		[Vector3(0.0, 0.0, -10.0), Vector3.BACK, [PlaneActor.Part.ENGINE, PlaneActor.Part.HULL, PlaneActor.Part.TAIL, PlaneActor.Part.RUDDER], "head-on into the nose"],
		[Vector3(0.0, 6.39, -10.0), Vector3(0.0, -0.328, 1.0), [PlaneActor.Part.TAIL, PlaneActor.Part.RUDDER], "from the front, diving over the nose and canopy into the fin and on into the rudder"],
		[Vector3(10.0, 2.0, 6.2), Vector3.LEFT, [PlaneActor.Part.RUDDER], "from the side through the rudder alone"],
		[Vector3(10.0, 0.3, -0.5), Vector3.LEFT, [PlaneActor.Part.HULL], "from the right side into the cockpit"],
		[Vector3(-4.0, 10.0, -0.9), Vector3.DOWN, [PlaneActor.Part.LEFT_WING], "from above onto the left wing"],
		[Vector3(0.0, 3.2, 10.0), Vector3.FORWARD, none, "from astern, just over the top of the fin"],
		[Vector3(2.2, 1.5, 10.0), Vector3.FORWARD, none, "from astern, between the fuselage and the wing"],
	]
	var found_parts: PackedInt32Array = PackedInt32Array()
	var found_distances: PackedFloat32Array = PackedFloat32Array()
	for case: Array in cases:
		var start: Vector3 = case[0]
		var direction: Vector3 = case[1]
		var expected: Array = case[2]
		boxes.trace(start, direction.normalized(), 40.0, found_parts, found_distances)
		_check(Array(found_parts) == expected, "path %s strikes %s (got %s)" % [case[3], _part_list(expected), _part_list(Array(found_parts))])
	_check(boxes.bounding_radius > 6.5 and boxes.bounding_radius < 9.0, "the bounding radius covers the wingtips (%.1f m)" % boxes.bounding_radius)



## Energy carried through each part: what lies behind takes less. Run once the
## match is live, because planes shrug off everything while spawn-shielded.
func _test_pass_through() -> void:
	var victim: PlaneActor = _bullet_target
	var hp_before: float = victim.hp
	victim.take_bullet(PackedInt32Array([PlaneActor.Part.TAIL, PlaneActor.Part.HULL, PlaneActor.Part.ENGINE]), 100.0, _reference)
	var tail_pool: float = victim.stats.max_hp * 0.45
	var engine_pool: float = victim.stats.max_hp * 0.5
	_near(victim.part_damage_of(PlaneActor.Part.TAIL), 100.0 / tail_pool, "a through-and-through shot hits the tail at full energy")
	_near(victim.part_damage_of(PlaneActor.Part.ENGINE), 15.0 / engine_pool, "and reaches the engine with 15% left (tail 50% x hull 30%)")
	_near(hp_before - victim.hp, 90.0 + 60.0 + 15.0, "hull loss is the sum along the path")
	hp_before = victim.hp
	victim.take_bullet(PackedInt32Array([PlaneActor.Part.ENGINE, PlaneActor.Part.HULL, PlaneActor.Part.TAIL]), 100.0, _reference)
	_near(hp_before - victim.hp, 100.0, "nothing comes out the back of the engine")
	victim.respawn(victim.global_transform)  # Clean slate (and spawn shield) before the live-fire test.


## Real bullets from a fixed gun, flown by BulletSystem with drop and drag at
## a plane cruising past. Called every tick; fires and checks on a timetable.
func _run_live_fire() -> void:
	var victim: PlaneActor = _bullet_target
	var ahead: Vector3 = victim.forward()
	match _live_stage:
		0:
			if _clock >= 2.7:  # The spawn shield from the respawn above has run out.
				# From ahead and above, aimed at the fin: must clear the nose and canopy.
				_live_hp = victim.hp
				_fire_at(victim, victim.global_position + ahead * 150.0 + Vector3.UP * 60.0, -ahead * 4.6 + Vector3.UP * 1.6)
				_live_stage = 1
		1:
			if _clock >= 3.5:
				_check(victim.part_damage_of(PlaneActor.Part.TAIL) > 0.0, "a bullet from the front, over the nose, damages the tail")
				_check(is_zero_approx(victim.part_damage_of(PlaneActor.Part.ENGINE)), "and does not touch the engine it flew over")
				_check(victim.hp < _live_hp, "and costs the plane hull health")
				_live_tail = victim.part_damage_of(PlaneActor.Part.TAIL)
				# Level, from dead ahead, at the centre of the plane.
				_fire_at(victim, victim.global_position + ahead * 150.0, Vector3.ZERO)
				_live_stage = 2
		2:
			if _clock >= 4.3:
				_check(victim.part_damage_of(PlaneActor.Part.ENGINE) > 0.0, "a head-on bullet hits the engine")
				_near(victim.part_damage_of(PlaneActor.Part.TAIL), _live_tail, "and stops there: the tail is untouched")
				_live_engine = victim.part_damage_of(PlaneActor.Part.ENGINE)
				_live_tail = victim.part_damage_of(PlaneActor.Part.TAIL)
				# Level, from dead astern.
				_fire_at(victim, victim.global_position - ahead * 150.0, Vector3.ZERO)
				_live_stage = 3
		3:
			if _clock >= 5.4:
				var tail_gain: float = victim.part_damage_of(PlaneActor.Part.TAIL) - _live_tail
				var engine_gain: float = victim.part_damage_of(PlaneActor.Part.ENGINE) - _live_engine
				_check(victim.part_damage_of(PlaneActor.Part.RUDDER) > 0.0, "a bullet from astern goes through the rudder first")
				_check(tail_gain > 0.0, "then into the tail")
				_check(engine_gain > 0.0 and engine_gain < tail_gain * 0.4, "and carries on to the engine with much less energy (tail +%.3f, engine +%.3f)" % [tail_gain, engine_gain])
				# A tail chase closes slowly, so each hit is softer than the head-on one.
				_check(tail_gain * 0.45 < _live_engine * 0.5 * 0.9, "a tail-chase hit lands softer than a head-on hit")
				_live_hp = victim.hp
				# Aimed 3.6 m above the plane: inside the old hit sphere, outside the airframe.
				_fire_at(victim, victim.global_position - ahead * 150.0, Vector3.UP * 3.6)
				_live_stage = 4
		4:
			if _clock >= 6.5:
				_near(victim.hp, _live_hp, "a bullet that passes over the plane does no damage")
				_live_stage = 5


## Fires one bullet from a stationary gun at [param gun_position] so that it
## meets [param offset] from the victim's centre, allowing for the victim's
## motion and for bullet drop.
func _fire_at(victim: PlaneActor, gun_position: Vector3, offset: Vector3) -> void:
	var muzzle_speed: float = 420.0
	var aim: Vector3 = Ballistics.lead_point(gun_position, Vector3.ZERO, victim.global_position + offset, victim.velocity, muzzle_speed)
	_manager.bullet_system.spawn(gun_position, (aim - gun_position).normalized() * muzzle_speed, _reference, 2.0, 100.0, muzzle_speed)


func _part_list(part_ids: Array) -> String:
	if part_ids.is_empty():
		return "nothing"
	var names: PackedStringArray = PackedStringArray()
	for part_id: int in part_ids:
		names.append(PlaneActor.PART_NAMES[part_id])
	return " -> ".join(names)


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
	# The attacker loses its rudder outright: awkward to fly, but it survives.
	_hurt(_attacker, PlaneActor.Part.RUDDER, 1.05, _reference)
	_check(_events.has("Rudder:DESTROYED"), "a rudder can be shot off")
	_check(not _attacker.is_spinning_out(), "losing the rudder does not bring the plane down")
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
	_check(_live_stage == 5, "the live-fire sequence ran to the end (stage %d)" % _live_stage)
	_check(_reference.alive and _left_wing_hit.alive and _tail_hit.alive and _engine_hit.alive, "damaged-but-not-destroyed planes are still flying")
	_check(_attacker.alive, "the plane with no rudder is still flying")


## Deals exactly [param fraction] of a part's health pool to it.
func _hurt(plane: PlaneActor, part: PlaneActor.Part, fraction: float, attacker: PlaneActor) -> void:
	plane.apply_damage(fraction * plane.stats.max_hp * PlaneActor.PART_HEALTH_FRACTION[part], attacker, 0.0, 0.0, part)


func _set_stick(steer: Vector2) -> void:
	# The two engine-test planes are left alone so they fly level the whole time.
	for plane: PlaneActor in [_reference, _left_wing_hit, _tail_hit, _attacker]:
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
