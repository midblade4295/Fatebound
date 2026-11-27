extends Node
## Headless test of the damage model: parts, not health.
##
##   godot --headless --fixed-fps 60 --path . res://tests/TestDamageModel.tscn
##
## Ten bot planes with their brains switched off are the test subjects.
## Four layers:
##   1. the hit boxes come from the model, one per piece, and a bullet's path
##      through them decides what it hits;
##   2. real bullets flown by BulletSystem (drop, drag, pass-through);
##   3. damage only ever changes parts: there is no health to run out, shot-off
##      parts leave the model, and what is attached goes with them;
##   4. each kind of damage changes how the plane flies against an undamaged
##      reference, the pilot keeps control, and a plane is only lost when it
##      hits the sea, credited to whoever crippled it.
## Prints DAMAGE_MODEL_OK on success.

const P := PlaneActor.Part

var _manager: MatchManager5v5
var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0
var _clock: float = -1.0
var _stage: int = 0
var _events: Array[String] = []

# Blue subjects.
var _reference: PlaneActor
var _tip_lost: PlaneActor
var _wing_lost: PlaneActor
var _tail_lost: PlaneActor
var _engine_hit: PlaneActor
# Red subjects.
var _attacker: PlaneActor       # Loses its rudder, later a flap; credited with blue losses.
var _engine_lost: PlaneActor
var _fuel_hit: PlaneActor
var _speed_reference: PlaneActor
var _bullet_target: PlaneActor

var _yaw_start: Dictionary[int, float] = {}
var _pitch_start: Dictionary[int, float] = {}
var _height_start: Dictionary[int, float] = {}
var _died_at: Dictionary[int, float] = {}
var _died_height: Dictionary[int, float] = {}
## Radians each plane has rolled to its left since the last _mark(), and the
## most it has sideslipped.
var _rolled: Dictionary[int, float] = {}
var _most_slip: Dictionary[int, float] = {}
## Planes being flown straight and level by the test's own hands.
var _levelled: Array[PlaneActor] = []
## A plane being rolled level and pulled gently.
var _gentle: PlaneActor
## Planes that touched another aircraft at any point (none should).
var _collided: Array[PlaneActor] = []
var _live_stage: int = 0
var _live_before: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	Profile.persistence_enabled = false
	Profile.reset_to_new_profile(false)
	GameSession.local_player_enabled = false
	GameSession.match_seed = 5
	GameSession.ground_start = false  # This test is about flying: start in the air.
	GameSession.match_duration = 180.0
	var arena: Node = (load(GameSession.SCENE_ARENA) as PackedScene).instantiate()
	add_child(arena)
	_manager = arena.get_node("MatchManager") as MatchManager5v5
	_manager.midair_collisions.planes_collided.connect(_on_planes_collided)
	var blue: Array[PlaneActor] = []
	var red: Array[PlaneActor] = []
	for slot: PilotSlot in _manager.get_roster():
		# Brains off: this test flies every plane by writing to PlaneInput itself.
		slot.controller.set_physics_process(false)
		(blue if slot.team == Teams.Id.TEAM_BLUE else red).append(slot.plane)
		slot.plane.part_state_changed.connect(_on_part_state_changed)
		slot.plane.died.connect(_on_died)
	_reference = blue[0]
	_tip_lost = blue[1]
	_wing_lost = blue[2]
	_tail_lost = blue[3]
	_engine_hit = blue[4]
	_attacker = red[0]
	_engine_lost = red[1]
	_fuel_hit = red[2]
	_speed_reference = red[3]
	_bullet_target = red[4]
	_test_hit_boxes()


func _physics_process(delta: float) -> void:
	if _stage < 0:
		return
	if _manager.phase != MatchManager5v5.Phase.ACTIVE:
		return  # Wait out the countdown (and with it the spawn shield).
	if _clock < 0.0:
		_clock = 0.0
		# The two formations spawn nose to nose in the same lanes, and damaged
		# planes wander. Give every subject its own wide lane, high up, so the
		# only things any of them can hit are the sea and the islands.
		for slot: PilotSlot in _manager.get_roster():
			var seat_x: float = float(slot.seat) * 700.0 - 1400.0 + (350.0 if slot.team == Teams.Id.TEAM_RED else 0.0)
			var start: Transform3D = slot.plane.global_transform
			start.origin = Vector3(seat_x, 900.0 + float(slot.seat) * 30.0, start.origin.z * 0.4)
			# The two that will have to glide all the way down start lower.
			if slot.plane == _engine_lost or slot.plane == _fuel_hit:
				start.origin.y = 420.0
			# The two whose engines are compared start flat out; the rest cruise.
			if slot.plane == _speed_reference or slot.plane == _engine_hit:
				slot.plane.speed = slot.plane.stats.top_speed
			slot.plane.arena_radius = 1.0e7
			slot.plane.teleport(start)
	_clock += delta
	_run_live_fire()
	for plane: PlaneActor in _manager.get_planes():
		var key: int = plane.get_instance_id()
		if plane.alive:
			_rolled[key] = _roll_of(plane) + plane.flight.angular_velocity.z * delta
			_most_slip[key] = maxf(_slip_of(plane), absf(plane.sideslip()))
	for plane: PlaneActor in _levelled:
		if plane.alive:
			plane.input.steer = _level_stick(plane)
	if _gentle != null and _gentle.alive:
		_gentle.input.steer = Vector2(_level_stick(_gentle).x, 0.15)
	# With one aileron gone the stick alone is not always enough: the pilot
	# helps the low wing up with rudder as well (a skid toward the high side
	# lifts it), for as long as he is flying it level.
	if _tip_lost.alive and (_gentle == _tip_lost or _levelled.has(_tip_lost)):
		_tip_lost.input.rudder = clampf(_tip_lost.bank * 1.5, -1.0, 1.0)
	match _stage:
		0:
			_test_no_health()
			_apply_all_damage()
			_stage = 1
		1:
			# 2.5 s hands-off: uneven damage should pull the plane on its own.
			if _clock >= 2.5:
				_check_hands_off()
				_mark()
				# Stick hard right; the reference pilot also treads on the right pedal.
				_set_stick(Vector2(1.0, 0.0))
				_reference.input.rudder = 1.0
				_stage = 2
		2:
			if _clock >= 3.2:
				_check_roll_in()
				_reference.input.rudder = 0.0
				_mark()
				_set_stick(Vector2(0.0, 0.6))
				_stage = 3
				# The tip-less plane's pilot has his hands full already: he
				# rolls back level and pulls gently.
				_gentle = _tip_lost
		3:
			# Banked over, 1.8 s of pull.
			if _clock >= 5.0:
				_check_turn()
				_gentle = null
				_set_stick(Vector2.ZERO)
				# From here the survivors are flown level, the tip-less one too:
				# it takes stick held against the missing tip.
				_levelled = [_reference, _tip_lost, _attacker]
				_mark()
				_stage = 4
		4:
			if _clock >= 9.5:
				_check_engines()
				_test_repair_and_flap()
				_stage = 5
		5:
			if _clock >= 12.5:
				_check_flaps()
				_stage = 6
		6:
			# Long enough for the two with dead engines to glide all the way down.
			if _clock >= 110.0 or _all_lost():
				_final_checks()
				_finish()


## Stick that flies a plane straight and level: wings level, no climb or sink.
func _level_stick(plane: PlaneActor) -> Vector2:
	var roll: float = clampf(plane.bank * 2.0 + plane.flight.angular_velocity.z * 0.4, -1.0, 1.0)
	# No pulling until the wings are somewhere near level.
	var upright: float = clampf(cos(plane.bank) * 2.0 - 1.0, 0.0, 1.0)
	var pull: float = clampf(-plane.climb_speed() * 0.03 - plane.flight.angular_velocity.x * 0.4, -0.5, 0.5) * upright
	return Vector2(roll, pull)


# ---------------------------------------------------------------------------
# 1. Hit boxes and bullet paths
# ---------------------------------------------------------------------------

func _test_hit_boxes() -> void:
	var boxes: PlaneHitboxes = _reference.hitboxes
	for index: int in range(PlaneActor.PART_COUNT):
		_check(boxes.parts.has(index), "the model provides a hit box for the %s" % PlaneActor.PART_NAMES[index].to_lower())
	_check(boxes.bounding_radius > 6.5 and boxes.bounding_radius < 9.5, "the bounding radius covers the wingtips (%.1f m)" % boxes.bounding_radius)
	_check(boxes.solid_boxes.size() == boxes.boxes.size(), "every bullet box has a true-size collision box")
	var rudder: Vector3 = _box_centre(boxes, P.RUDDER)
	var fin: Vector3 = _box_centre(boxes, P.FIN)
	var right_tip: Vector3 = _box_centre(boxes, P.RIGHT_WINGTIP)
	var left_wing: AABB = _box(boxes, P.LEFT_WING)
	var fin_top: float = _box(boxes, P.FIN).end.y

	_expect_path(boxes, Vector3(0.0, 0.0, 30.0), Vector3.FORWARD, 0, [P.TAIL, P.FUSELAGE, P.ENGINE], true,
			"from dead astern, straight up the fuselage")
	_expect_path(boxes, Vector3(0.0, 0.0, -30.0), Vector3.BACK, 0, [P.ENGINE, P.FUSELAGE, P.TAIL], true,
			"head-on into the nose")
	_expect_path(boxes, rudder + Vector3(0.0, 0.0, 30.0), Vector3.FORWARD, 0, [P.RUDDER, P.FIN], false,
			"from astern at fin height: rudder first, then the fin")
	_expect_path(boxes, right_tip + Vector3(0.0, 0.0, 30.0), Vector3.FORWARD, 0, [P.RIGHT_AILERON, P.RIGHT_WINGTIP], false,
			"from astern into the right wingtip: aileron first, then the tip")
	# Well out along the panel (clear of the engine's exhausts) and behind the
	# cannon, which sticks out ahead of the leading edge.
	_expect_path(boxes, Vector3(left_wing.position.x + left_wing.size.x * 0.25, 30.0, left_wing.end.z - left_wing.size.z * 0.3), Vector3.DOWN, 0, [P.LEFT_WING], true,
			"from above onto the left wing")
	# From the front, diving steeply over the nose and canopy into the fin.
	var over_the_nose: Vector3 = Vector3(0.0, -0.9, 1.0).normalized()
	_expect_path(boxes, fin - over_the_nose * 30.0, over_the_nose, 0, [P.FIN], false,
			"from the front, over the nose and canopy, into the fin")
	_expect_path(boxes, Vector3(0.0, fin_top + 1.2, 30.0), Vector3.FORWARD, 0, [], true,
			"from astern, just over the top of the fin")
	# Once the wingtip has been shot off, the same shot goes through empty air.
	var tip_gone: int = (1 << P.RIGHT_WINGTIP) | (1 << P.RIGHT_AILERON)
	_expect_path(boxes, right_tip + Vector3(0.0, 0.0, 30.0), Vector3.FORWARD, tip_gone, [], true,
			"from astern where the right wingtip used to be")


func _expect_path(boxes: PlaneHitboxes, start: Vector3, direction: Vector3, gone_mask: int, expected: Array, exact: bool, description: String) -> void:
	var found_parts: PackedInt32Array = PackedInt32Array()
	var found_distances: PackedFloat32Array = PackedFloat32Array()
	boxes.trace(start, direction.normalized(), 80.0, gone_mask, found_parts, found_distances)
	var found: Array = Array(found_parts)
	var matches: bool = found == expected if exact else found.slice(0, expected.size()) == expected
	_check(matches, "path %s strikes %s (got %s)" % [description, _part_list(expected), _part_list(found)])


## The whole extent of a part: a part can be made of several boxes.
func _box(boxes: PlaneHitboxes, part: PlaneActor.Part) -> AABB:
	var result: AABB = AABB()
	var found: bool = false
	for index: int in range(boxes.parts.size()):
		if boxes.parts[index] != part:
			continue
		result = boxes.solid_boxes[index] if not found else result.merge(boxes.solid_boxes[index])
		found = true
	return result


func _box_centre(boxes: PlaneHitboxes, part: PlaneActor.Part) -> Vector3:
	return _box(boxes, part).get_center()


# ---------------------------------------------------------------------------
# 2. Live bullets
# ---------------------------------------------------------------------------

## Real bullets from a fixed gun, flown by BulletSystem with drop and drag at
## a plane cruising past. Called every tick; fires and checks on a timetable.
func _run_live_fire() -> void:
	var victim: PlaneActor = _bullet_target
	var ahead: Vector3 = victim.forward()
	match _live_stage:
		0:
			if _clock >= 0.2:
				# From ahead and well above, aimed at the fin: it has to clear the nose and canopy.
				_live_before = victim.part_damage.duplicate()
				var fin_offset: Vector3 = victim.global_transform.basis * _box_centre(victim.hitboxes, P.FIN)
				_fire_at(victim, victim.global_position + ahead * 110.0 + Vector3.UP * 100.0, fin_offset)
				_live_stage = 1
		1:
			if _clock >= 1.0:
				_check(_gain(victim, P.FIN) > 0.0, "a bullet from the front, over the nose, damages the fin")
				_check(is_zero_approx(_gain(victim, P.ENGINE)) and is_zero_approx(_gain(victim, P.FUSELAGE)), "and does not touch the engine or fuselage it flew over")
				_live_before = victim.part_damage.duplicate()
				_fire_at(victim, victim.global_position + ahead * 150.0, Vector3.ZERO)  # Level, from dead ahead.
				_live_stage = 2
		2:
			if _clock >= 1.8:
				_check(_gain(victim, P.ENGINE) > 0.0, "a head-on bullet hits the engine")
				_check(is_zero_approx(_gain(victim, P.TAIL)) and is_zero_approx(_gain(victim, P.FUSELAGE)), "and stops there: nothing behind it is touched")
				var head_on_engine: float = _gain(victim, P.ENGINE)
				_live_before = victim.part_damage.duplicate()
				_fire_at(victim, victim.global_position - ahead * 150.0, Vector3.ZERO)  # Level, from dead astern.
				_live_stage = 3
				set_meta(&"head_on_engine", head_on_engine)
		3:
			if _clock >= 2.9:
				var tail_gain: float = _gain(victim, P.TAIL)
				var engine_gain: float = _gain(victim, P.ENGINE)
				_check(tail_gain > 0.0, "a bullet from astern hits the tail first")
				_check(_gain(victim, P.FUSELAGE) > 0.0, "carries on through the fuselage")
				_check(engine_gain > 0.0 and engine_gain < tail_gain * 0.4, "and reaches the engine with much less energy (tail +%.3f, engine +%.3f)" % [tail_gain, engine_gain])
				# Same bullet, same engine: the tail-chase one arrived after two
				# other parts and at a lower closing speed.
				var head_on_engine: float = get_meta(&"head_on_engine")
				_check(engine_gain < head_on_engine * 0.3, "a head-on hit lands far harder than one that came the long way round")
				_live_before = victim.part_damage.duplicate()
				var over: float = _box(victim.hitboxes, P.FIN).end.y + 1.5
				_fire_at(victim, victim.global_position - ahead * 150.0, Vector3.UP * over)
				_live_stage = 4
		4:
			if _clock >= 4.0:
				var touched: float = 0.0
				for index: int in range(PlaneActor.PART_COUNT):
					touched += victim.part_damage[index] - _live_before[index]
				_check(is_zero_approx(touched), "a bullet that passes over the plane does no damage")
				_live_stage = 5


func _gain(plane: PlaneActor, part: PlaneActor.Part) -> float:
	return plane.part_damage[part] - _live_before[part]


## Fires one bullet from a stationary gun at [param gun_position] so that it
## meets [param offset] (world axes) from the victim's centre, allowing for
## the victim's motion and for bullet drop.
func _fire_at(victim: PlaneActor, gun_position: Vector3, offset: Vector3) -> void:
	var muzzle_speed: float = 420.0
	var aim: Vector3 = Ballistics.lead_point(gun_position, Vector3.ZERO, victim.global_position + offset, victim.velocity, muzzle_speed)
	_manager.bullet_system.spawn(gun_position, (aim - gun_position).normalized() * muzzle_speed, _reference, 2.0, 60.0, muzzle_speed)


# ---------------------------------------------------------------------------
# 3. Parts, not health
# ---------------------------------------------------------------------------

func _test_no_health() -> void:
	var victim: PlaneActor = _speed_reference
	_check(victim.get(&"hp") == null, "a plane has no health value at all")
	var toughness: float = victim.stats.max_hp
	# Energy carried through each part: what lies behind takes less.
	victim.take_bullet(PackedInt32Array([P.TAIL, P.FUSELAGE, P.ENGINE]), 30.0, _reference)
	_near(victim.part_damage_of(P.TAIL), 30.0 / (toughness * PlaneActor.PART_STRENGTH[P.TAIL]), "a through-and-through shot hits the tail at full energy")
	_near(victim.part_damage_of(P.FUSELAGE), 30.0 * 0.45 / (toughness * PlaneActor.PART_STRENGTH[P.FUSELAGE]), "the fuselage gets what the tail let through (45%)")
	_near(victim.part_damage_of(P.ENGINE), 30.0 * 0.45 * 0.3 / (toughness * PlaneActor.PART_STRENGTH[P.ENGINE]), "and the engine what the fuselage let through (30% of that)")
	_near(victim.part_damage_of(P.LEFT_WING) + victim.part_damage_of(P.RIGHT_WING), 0.0, "parts off the bullet's path are untouched")
	var before: float = _reference.part_damage_of(P.ENGINE)
	_reference.apply_damage(100.0, _tip_lost, P.ENGINE)
	_near(_reference.part_damage_of(P.ENGINE), before, "team-mates' guns cannot damage each other")
	_check(victim.part_state(P.TAIL) == PlaneActor.PartState.OK, "one light hit does not cripple a part")
	victim.repair_parts(1.0)  # Leave the speed reference clean for later.


func _apply_all_damage() -> void:
	_events.clear()
	# Blue losses are the attacker's doing; red losses are the reference's.
	_destroy(_tip_lost, P.RIGHT_WINGTIP, _attacker)
	_check(_events.has("Right wingtip:DESTROYED"), "a wingtip can be shot off")
	_check(_tip_lost.is_part_gone(P.RIGHT_AILERON), "and its aileron goes with it")
	_check(not _tip_lost.is_part_gone(P.RIGHT_WING) and not _tip_lost.is_part_gone(P.RIGHT_FLAP), "but the inner wing and its flap stay on")
	_destroy(_wing_lost, P.LEFT_WING, _attacker)
	_check(_wing_lost.is_part_gone(P.LEFT_WINGTIP) and _wing_lost.is_part_gone(P.LEFT_FLAP) and _wing_lost.is_part_gone(P.LEFT_AILERON),
			"a lost wing takes its tip, flap and aileron with it")
	_check(_wing_lost.has_guns(), "the plane keeps the gun in its other wing")
	_destroy(_tail_lost, P.TAIL, _attacker)
	_check(_tail_lost.is_part_gone(P.FIN) and _tail_lost.is_part_gone(P.RUDDER) and _tail_lost.is_part_gone(P.LEFT_ELEVATOR) and _tail_lost.is_part_gone(P.RIGHT_ELEVATOR),
			"a lost tail takes the fin, rudder and both elevators with it")
	_hurt(_engine_hit, P.ENGINE, 0.8, _attacker)
	_destroy(_attacker, P.RUDDER, _reference)
	_check(not _attacker.is_part_gone(P.FIN), "losing the rudder leaves the fin")
	_destroy(_engine_lost, P.ENGINE, _reference)
	_check(not _engine_lost.is_part_gone(P.ENGINE), "a dead engine stays on the plane")
	_near(_engine_lost.engine_power(), 0.0, "but gives no power")
	# Far more than the fuselage can take: still not a kill.
	_fuel_hit.apply_damage(1000000.0, _reference, P.FUSELAGE)
	_check(_fuel_hit.part_state(P.FUSELAGE) == PlaneActor.PartState.DESTROYED, "the fuselage can be wrecked")
	_check(_fuel_hit.engine_power() > 0.9, "the engine runs on until the fuel has gone")
	for plane: PlaneActor in [_tip_lost, _wing_lost, _tail_lost, _engine_lost, _fuel_hit, _attacker]:
		_check(plane.alive, "%s is still flying: no amount of damage destroys a plane by itself" % plane.name)
	_tail_lost.input.steer = Vector2(0.0, 1.0)  # Full back stick the whole way: it goes in anyway.
	_mark()


## Deals exactly [param fraction] of a part's strength to it.
func _hurt(plane: PlaneActor, part: PlaneActor.Part, fraction: float, attacker: PlaneActor) -> void:
	plane.apply_damage(fraction * plane.stats.max_hp * PlaneActor.PART_STRENGTH[part], attacker, part)


func _destroy(plane: PlaneActor, part: PlaneActor.Part, attacker: PlaneActor) -> void:
	_hurt(plane, part, 1.05, attacker)


# ---------------------------------------------------------------------------
# 4. Flying a damaged plane
# ---------------------------------------------------------------------------

func _check_hands_off() -> void:
	# Bank is positive with the left wing low; rolling to the left is positive.
	_check(_tip_lost.bank < -0.1, "a missing right wingtip lifts less on that side, and the plane rolls toward it (bank %.2f rad)" % _tip_lost.bank)
	_check(not _tip_lost.is_stalling() and _height_lost(_tip_lost) < 40.0,
			"at speed, less wing is still enough wing: it does not fall (%.1f m lost)" % _height_lost(_tip_lost))
	_check(absf(_yaw_drift(_reference)) < 0.03 and absf(_height_lost(_reference)) < 6.0 and absf(_reference.bank) < 0.06,
			"the undamaged plane flies straight and level (%.3f rad, %.1f m, bank %.2f)" % [_yaw_drift(_reference), _height_lost(_reference), _reference.bank])
	_check(_wing_lost.alive and _wing_lost.is_going_down(), "a plane with one wing is going down, but is still flying")
	_check(_roll_of(_wing_lost) > 2.0, "with nothing to balance the wing that is left, it rolls over and over toward the missing one (%.1f rad in 2.5 s)" % _roll_of(_wing_lost))
	_check(_height_lost(_wing_lost) > 15.0, "and falls (%.0f m)" % _height_lost(_wing_lost))
	_check(_attacker.alive and absf(_attacker.bank) < 0.15 and not _attacker.is_going_down(), "losing the rudder does not bring a plane down (bank %.2f rad)" % _attacker.bank)
	_check(_engine_lost.has_flag(PlaneActor.FLAG_BURNING) and _engine_lost.is_going_down(), "a destroyed engine burns and the plane is going down")
	_check(_fuel_hit.fuel < 0.7 and _fuel_hit.fuel > 0.2, "a wrecked fuselage is pouring fuel (%.0f%% left)" % (_fuel_hit.fuel * 100.0))
	# The tail is what holds the nose into the airflow. Without it the plane
	# cannot be flown: it pitches over and tumbles, stick or no stick.
	_check(_tail_lost.alive and _tail_lost.is_going_down(), "a plane with no tail is going down")
	_check(absf(_tail_lost.pitch) > 0.5 or absf(_tail_lost.flight.angular_velocity.x) > 0.5 or _tail_lost.is_stalling(),
			"out of control: nothing holds its nose into the air any more (pitch %.2f rad, pitching at %.2f rad/s)" % [_tail_lost.pitch, _tail_lost.flight.angular_velocity.x])
	# What was shot off has left the model, and is falling as debris.
	_check(not _tip_lost.visual.has_piece(P.RIGHT_WINGTIP) and not _tip_lost.visual.has_piece(P.RIGHT_AILERON), "the wingtip and its aileron are gone from the model")
	_check(_tip_lost.visual.has_piece(P.RIGHT_WING) and _tip_lost.visual.has_piece(P.RIGHT_FLAP), "the rest of that wing is still on it")
	_check(not _tail_lost.visual.has_piece(P.TAIL) and not _tail_lost.visual.has_piece(P.RUDDER), "the tail-less plane has no tail on its model")
	_check(_engine_lost.visual.has_piece(P.ENGINE), "the dead engine is still on the model")
	var debris: int = 0
	for node: Node in _reference.get_parent().get_children():
		if node is Debris:
			debris += 1
	_check(debris >= 4, "shot-off pieces are falling as debris (%d)" % debris)


## After 0.7 s of full right stick (and, for the reference, right pedal).
func _check_roll_in() -> void:
	var clean_roll: float = -_roll_of(_reference)
	_check(clean_roll > 0.5 and _reference.bank < -0.5, "stick hard over rolls the reference plane to the right (%.2f rad in 0.7 s)" % clean_roll)
	# One aileron is gone, but the roll is toward the side the damage drops anyway.
	_check(-_roll_of(_tip_lost) > clean_roll * 0.5, "the tip-less plane answers the stick on one aileron (%.2f against %.2f rad)" % [-_roll_of(_tip_lost), clean_roll])
	_check(-_roll_of(_attacker) > 0.4, "ailerons do not need a rudder (%.2f rad)" % -_roll_of(_attacker))
	# Right stick against a missing left wing: one aileron against half the
	# aeroplane's lift is no contest.
	_check(_roll_of(_wing_lost) > 0.5, "full opposite stick cannot stop the one-winged plane rolling (%.1f rad more)" % _roll_of(_wing_lost))
	var aileron: Node3D = _reference.visual.get_node("Model").find_child("AileronL", true, false) as Node3D
	var rudder: Node3D = _reference.visual.get_node("Model").find_child("Rudder", true, false) as Node3D
	_check(aileron != null and rudder != null, "the model has separate aileron and rudder pieces")
	if aileron != null and rudder != null:
		# Deflection shows up as the piece's trailing edge (+Z) swinging.
		_check((aileron.basis * Vector3.BACK).y < -0.1, "rolling right, the left aileron's trailing edge is down")
		_check((rudder.basis * Vector3.BACK).x > 0.3, "and with the right pedal down the rudder's is over to the right")
	_check(_slip_of(_reference) > deg_to_rad(2.0), "the pedal skids the reference plane (%.1f degrees of slip)" % rad_to_deg(_slip_of(_reference)))


## After 1.8 s of pulling in the bank.
func _check_turn() -> void:
	var clean_turn: float = -_yaw_drift(_reference)
	_check(clean_turn > 0.25 and absf(_reference.bank) > deg_to_rad(35.0), "banked and pulling, the reference plane turns (%.2f rad in 1.8 s, banked %.0f degrees)" % [clean_turn, rad_to_deg(absf(_reference.bank))])
	_check(_reference.load_factor() > 2.0, "pulling %.1f g" % _reference.load_factor())
	var rudderless: float = -_yaw_drift(_attacker)
	_check(rudderless > clean_turn * 0.6 and rudderless < clean_turn * 1.4, "without a rudder a plane still turns on its bank (%.2f against %.2f rad)" % [rudderless, clean_turn])
	# g for the airspeed and the angle of attack it has: less wing gives less of it.
	var tip_grip: float = _grip(_tip_lost)
	var clean_grip: float = _grip(_reference)
	_check(tip_grip < clean_grip * 0.93, "with a wingtip gone the wings pull less for the same speed and angle of attack (%.2f against %.2f)" % [tip_grip, clean_grip])
	_check(_wing_lost.alive or _died_at.has(_wing_lost.get_instance_id()), "the one-winged plane is past helping")


func _check_engines() -> void:
	var slow: float = _engine_hit.speed / _engine_hit.stats.top_speed
	var fast: float = _speed_reference.speed / _speed_reference.stats.top_speed
	_check(fast > 0.95, "a healthy engine holds top speed (%.0f%%)" % (fast * 100.0))
	_check(slow < fast - 0.04 and _engine_hit.alive, "a damaged engine cannot, but the plane flies on (%.0f%%)" % (slow * 100.0))
	_check(is_zero_approx(_fuel_hit.fuel) and is_zero_approx(_fuel_hit.engine_power()), "the leaking plane has run dry and its engine has stopped")
	_check(_tip_lost.alive and absf(_tip_lost.bank) < 0.25 and _height_lost(_tip_lost) < 120.0,
			"the tip-less plane is being held straight and level with stick and rudder (bank %.2f rad, %.0f m lost)" % [_tip_lost.bank, _height_lost(_tip_lost)])
	_check(absf(_tip_lost.input.steer.x) + absf(_tip_lost.input.rudder) > 0.03, "which takes stick and rudder held against the missing tip (stick %.2f, rudder %.2f)" % [_tip_lost.input.steer.x, _tip_lost.input.rudder])
	_levelled.append(_speed_reference)
	_levelled.append(_bullet_target)


func _test_repair_and_flap() -> void:
	_events.clear()
	_engine_hit.repair_parts(0.5)
	_check(_engine_hit.part_state(P.ENGINE) == PlaneActor.PartState.OK and _events.has("Engine:OK"), "a field repair patches a damaged engine")
	_tip_lost.repair_parts(1.0)
	_check(_tip_lost.is_part_gone(P.RIGHT_WINGTIP), "but cannot put back a part that has been shot off")
	# Flaps: shoot one off, then lower the wheels, which brings the flaps down
	# with them. Only one of them is there to come down.
	_destroy(_engine_hit, P.RIGHT_FLAP, _attacker)
	_check(_engine_hit.alive and not _engine_hit.is_going_down(), "losing a flap does not bring the plane down")
	_mark()
	_engine_hit.set_gear_down(true)
	_reference.set_gear_down(true)
	_levelled.erase(_reference)
	_reference.input.steer = Vector2.ZERO


func _check_flaps() -> void:
	_check(_reference.flap_deploy() > 0.9, "lowering the wheels brings the flaps down (%.2f)" % _reference.flap_deploy())
	var flap: Node3D = _reference.visual.get_node("Model").find_child("FlapL", true, false) as Node3D
	_check(flap != null and (flap.basis * Vector3.BACK).y < -0.3, "the flap's trailing edge is down")
	# The flap that is left lifts its own wing: the plane rolls away from it,
	# toward the side with none.
	var lopsided: float = -_roll_of(_engine_hit)
	var even: float = -_roll_of(_reference)
	_check(lopsided > even + 0.15, "with only the left flap down the plane rolls to the right (%.2f against %.2f rad)" % [lopsided, even])
	_engine_hit.set_gear_down(false)
	_reference.set_gear_down(false)
	_levelled.append(_reference)
	_levelled.append(_engine_hit)


func _final_checks() -> void:
	_check(_live_stage == 5, "the live-fire sequence ran to the end (stage %d)" % _live_stage)
	# Every plane that was lost was lost by hitting the sea.
	for plane: PlaneActor in [_wing_lost, _tail_lost, _engine_lost, _fuel_hit]:
		var key: int = plane.get_instance_id()
		_check(_died_at.has(key), "%s eventually went in" % plane.name)
		if _died_at.has(key):
			# Islands reach about 330 m, so anything lost below that hit the
			# sea or the ground, since no test plane touched another aircraft.
			_check(_died_height[key] < 340.0 and not _collided.has(plane), "%s was destroyed by flying into the surface (at %.0f m)" % [plane.name, _died_height[key]])
			_check(_died_at[key] > 2.0, "%s flew on for a while first (%.1f s)" % [plane.name, _died_at[key]])
	# Whoever crippled a plane gets the takedown when it finally crashes.
	_check(_manager.slot_for_plane(_attacker).kills == 2, "both blue losses are credited to the red plane that crippled them (kills %d)" % _manager.slot_for_plane(_attacker).kills)
	_check(_manager.slot_for_plane(_reference).kills == 2, "both red losses are credited to the blue plane that crippled them (kills %d)" % _manager.slot_for_plane(_reference).kills)
	_check(_manager.team_score(Teams.Id.TEAM_RED) == 2 and _manager.team_score(Teams.Id.TEAM_BLUE) == 2,
			"score is BLUE 2 - 2 RED (got %d - %d)" % [_manager.team_score(Teams.Id.TEAM_BLUE), _manager.team_score(Teams.Id.TEAM_RED)])
	_check(_reference.alive and _engine_hit.alive and _attacker.alive, "planes with lesser damage are still flying at the end")
	_check(_collided.is_empty(), "no test plane touched another aircraft")


## True once the four planes that cannot stay up have all gone in.
func _all_lost() -> bool:
	for plane: PlaneActor in [_wing_lost, _tail_lost, _engine_lost, _fuel_hit]:
		if not _died_at.has(plane.get_instance_id()):
			return false
	return _clock >= 30.0


func _set_stick(steer: Vector2) -> void:
	# The engine-test planes are left alone so they fly level the whole time,
	# and the tail-less plane keeps its full back stick.
	for plane: PlaneActor in [_reference, _tip_lost, _wing_lost, _attacker]:
		plane.input.steer = steer


## Lift for the speed and angle of attack the plane has right now: g per
## radian of wing angle of attack, at its stalling speed.
func _grip(plane: PlaneActor) -> float:
	var attack: float = plane.flight.alpha + FlightDynamics.WING_INCIDENCE
	return plane.load_factor() / pow(plane.speed / plane.stats.stall_speed, 2.0) / maxf(attack, 0.02)


## Radians rolled to the left since the last _mark().
func _roll_of(plane: PlaneActor) -> float:
	var key: int = plane.get_instance_id()
	if _rolled.has(key):
		return _rolled[key]
	return 0.0


## Largest sideslip since the last _mark(), radians.
func _slip_of(plane: PlaneActor) -> float:
	var key: int = plane.get_instance_id()
	if _most_slip.has(key):
		return _most_slip[key]
	return 0.0


func _mark() -> void:
	for plane: PlaneActor in _manager.get_planes():
		var key: int = plane.get_instance_id()
		_yaw_start[key] = plane.yaw
		_pitch_start[key] = plane.pitch
		_height_start[key] = plane.altitude()
		_rolled[key] = 0.0
		_most_slip[key] = 0.0


## Signed yaw change since the last _mark(). Positive = turned left.
func _yaw_drift(plane: PlaneActor) -> float:
	var start: float = _yaw_start.get(plane.get_instance_id(), plane.yaw)
	return wrapf(plane.yaw - start, -PI, PI)


func _height_lost(plane: PlaneActor) -> float:
	var start: float = _height_start.get(plane.get_instance_id(), plane.altitude())
	return start - plane.altitude()


func _part_list(part_ids: Array) -> String:
	if part_ids.is_empty():
		return "nothing"
	var names: PackedStringArray = PackedStringArray()
	for part_id: int in part_ids:
		names.append(PlaneActor.PART_NAMES[part_id])
	return " -> ".join(names)


func _on_part_state_changed(_plane: PlaneActor, part: PlaneActor.Part, state: PlaneActor.PartState) -> void:
	var state_names: Array[String] = ["OK", "DAMAGED", "CRITICAL", "DESTROYED"]
	_events.append("%s:%s" % [PlaneActor.PART_NAMES[part], state_names[state]])


func _on_planes_collided(first: PlaneActor, second: PlaneActor, _first_part: int, _second_part: int, _closing_speed: float) -> void:
	_collided.append(first)
	_collided.append(second)


func _on_died(victim: PlaneActor, _killer: PlaneActor) -> void:
	var key: int = victim.get_instance_id()
	if not _died_at.has(key):
		_died_at[key] = _clock
		_died_height[key] = victim.altitude()


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
	_check(absf(actual - expected) < 0.001, "%s (expected %.4f, got %.4f)" % [message, expected, actual])
