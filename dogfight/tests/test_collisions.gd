extends Node
## Headless test of aircraft hitting each other.
##
##   godot --headless --fixed-fps 60 --path . res://tests/TestCollisions.tscn
##
## Bot planes with their brains switched off are placed into four situations:
## two enemies whose wingtips just overlap, two enemies head-on, two that pass
## close without touching, and two team-mates bumping tails.
## Prints COLLISIONS_OK on success.

var _manager: MatchManager5v5
var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0
var _clock: float = -1.0
var _stage: int = 0
## "nameA|nameB" -> [first part, second part, closing speed]
var _contacts: Dictionary[String, Array] = {}

var _clip_blue: PlaneActor
var _clip_red: PlaneActor
var _ram_blue: PlaneActor
var _ram_red: PlaneActor
var _pass_blue: PlaneActor
var _pass_red: PlaneActor
var _mate_lead: PlaneActor
var _mate_wing: PlaneActor
var _clip_gap_start: float = 0.0
var _clip_gap_after: float = -1.0


func _ready() -> void:
	Profile.persistence_enabled = false
	Profile.reset_to_new_profile(false)
	GameSession.local_player_enabled = false
	GameSession.match_seed = 5
	GameSession.match_duration = 180.0
	_test_box_overlap()
	var arena: Node = (load(GameSession.SCENE_ARENA) as PackedScene).instantiate()
	add_child(arena)
	_manager = arena.get_node("MatchManager") as MatchManager5v5
	_manager.midair_collisions.planes_collided.connect(_on_planes_collided)
	var blue: Array[PlaneActor] = []
	var red: Array[PlaneActor] = []
	for slot: PilotSlot in _manager.get_roster():
		slot.controller.set_physics_process(false)  # Brains off: they fly straight.
		(blue if slot.team == Teams.Id.TEAM_BLUE else red).append(slot.plane)
	_clip_blue = blue[0]
	_clip_red = red[0]
	_ram_blue = blue[1]
	_ram_red = red[1]
	_pass_blue = blue[2]
	_pass_red = red[2]
	_mate_lead = blue[3]
	_mate_wing = blue[4]


func _physics_process(delta: float) -> void:
	if _stage < 0 or _manager.phase != MatchManager5v5.Phase.ACTIVE:
		return
	if _clock < 0.0:
		_clock = 0.0
	_clock += delta
	match _stage:
		0:
			_arrange()
			_stage = 1
		1:
			# Sideways gap a quarter of a second after contact, before the
			# damaged wingtips start dragging the two planes back together.
			if _clip_gap_after < 0.0 and _clock >= 0.25:
				_clip_gap_after = absf(_clip_blue.global_position.x - _clip_red.global_position.x)
			if _clock >= 1.6:
				_check_results()
				_finish()


## The separating-axis test on its own, with boxes whose answer is obvious.
func _test_box_overlap() -> void:
	var unit: Vector3 = Vector3(1.0, 1.0, 1.0)
	var level: Basis = Basis.IDENTITY
	_check(MidairCollisions.boxes_overlap(Vector3.ZERO, level, unit, Vector3(1.5, 0.0, 0.0), level, unit), "boxes that share space overlap")
	_check(not MidairCollisions.boxes_overlap(Vector3.ZERO, level, unit, Vector3(2.5, 0.0, 0.0), level, unit), "boxes with a gap do not")
	# Two unit cubes 2.6 apart: clear when square on, touching when one is turned corner-first.
	var turned: Basis = Basis(Vector3.UP, PI * 0.25)
	_check(MidairCollisions.boxes_overlap(Vector3.ZERO, level, unit, Vector3(2.3, 0.0, 0.0), turned, unit), "a box turned corner-first reaches further")
	# Long thin "wings" crossing like a plus sign at different heights.
	var wing: Vector3 = Vector3(5.0, 0.2, 1.0)
	var crossed: Basis = Basis(Vector3.UP, PI * 0.5)
	_check(MidairCollisions.boxes_overlap(Vector3.ZERO, level, wing, Vector3(0.0, 0.3, 0.0), crossed, wing), "crossed wings at the same height touch")
	_check(not MidairCollisions.boxes_overlap(Vector3.ZERO, level, wing, Vector3(0.0, 0.5, 0.0), crossed, wing), "crossed wings half a metre apart do not")
	# Edge-to-edge case that only the cross-product axes can separate.
	var tilt_a: Basis = Basis(Vector3.RIGHT, PI * 0.25)
	var tilt_b: Basis = Basis(Vector3.BACK, PI * 0.25)
	_check(not MidairCollisions.boxes_overlap(Vector3.ZERO, tilt_a, Vector3(4.0, 0.1, 0.1), Vector3(0.0, 1.0, 1.0), tilt_b, Vector3(0.1, 0.1, 4.0)),
			"two thin rods passing each other at an angle do not touch")


func _arrange() -> void:
	var north: Basis = Basis.looking_at(Vector3.FORWARD, Vector3.UP)
	var south: Basis = Basis.looking_at(Vector3.BACK, Vector3.UP)

	# 1. Wingtip clip: an enemy flying alongside, slightly slower, with its
	# left wingtip overlapping our right wingtip by about 0.6 m.
	var span: float = _wingspan(_clip_blue)
	_clip_blue.teleport(Transform3D(north, Vector3(-600.0, 520.0, 0.0)))
	_clip_red.teleport(Transform3D(north, Vector3(-600.0 + span - 0.6, 520.0, 0.0)))
	_clip_red.speed = _clip_blue.speed - 9.0
	_clip_gap_start = absf(_clip_blue.global_position.x - _clip_red.global_position.x)

	# 2. Head-on: nose to nose, 70 m apart, same line.
	_ram_blue.teleport(Transform3D(north, Vector3(0.0, 520.0, 35.0)))
	_ram_red.teleport(Transform3D(south, Vector3(0.0, 520.0, -35.0)))

	# 3. Near miss: head-on again, but one wingspan plus three metres to the side.
	_pass_blue.teleport(Transform3D(north, Vector3(600.0, 520.0, 35.0)))
	_pass_red.teleport(Transform3D(south, Vector3(600.0 + span + 3.0, 520.0, -35.0)))

	# 4. Team-mates: a wingman running into the back of his leader.
	var length: float = _mate_lead.hitboxes.bounding_radius
	_mate_lead.teleport(Transform3D(north, Vector3(0.0, 520.0, 700.0)))
	_mate_wing.teleport(Transform3D(north, Vector3(0.0, 520.0, 700.0 + length * 0.9)))
	_mate_wing.speed = _mate_lead.speed + 12.0


func _check_results() -> void:
	# 1. Wingtip clip.
	var clip: Array = _contact(_clip_blue, _clip_red)
	_check(not clip.is_empty(), "overlapping wingtips collide")
	_check(_clip_blue.alive and _clip_red.alive, "a wingtip clip is survivable")
	var tip_parts: Array[PlaneActor.Part] = [PlaneActor.Part.RIGHT_WINGTIP, PlaneActor.Part.RIGHT_AILERON]
	_check(_damage_on(_clip_blue, tip_parts) > 0.1, "our right wingtip took the damage (%.2f)" % _damage_on(_clip_blue, tip_parts))
	_check(_damage_on(_clip_red, [PlaneActor.Part.LEFT_WINGTIP, PlaneActor.Part.LEFT_AILERON]) > 0.1, "and so did their left wingtip")
	_check(_damage_everywhere_else(_clip_blue, tip_parts) < 0.001, "nothing else on our plane was touched")
	_check(_clip_gap_after > _clip_gap_start + 0.5, "the contact pushed the two planes apart (%.2f m -> %.2f m)" % [_clip_gap_start, _clip_gap_after])
	if not clip.is_empty():
		var clip_speed: float = clip[2]
		_check(clip_speed < 20.0, "the clip was a slow one (%.1f m/s)" % clip_speed)

	# 2. Head-on.
	_check(not _contact(_ram_blue, _ram_red).is_empty(), "planes flying nose to nose collide")
	_check(not _ram_blue.alive and not _ram_red.alive, "a head-on collision destroys both")
	_check(_manager.slot_for_plane(_ram_blue).kills == 1 and _manager.slot_for_plane(_ram_red).kills == 1, "each is credited with the other")

	# 3. Near miss.
	_check(_contact(_pass_blue, _pass_red).is_empty(), "planes that pass three metres apart do not collide")
	_check(_pass_blue.alive and _pass_red.alive and _total_damage(_pass_blue) < 0.001, "and are unharmed")

	# 4. Team-mates.
	var bump: Array = _contact(_mate_lead, _mate_wing)
	_check(not bump.is_empty(), "team-mates can collide too")
	_check(_total_damage(_mate_lead) > 0.05 and _total_damage(_mate_wing) > 0.05, "and both are damaged by it")
	_check(_manager.slot_for_plane(_mate_lead).kills == 0 and _manager.slot_for_plane(_mate_wing).kills == 0, "but nobody is credited")

	_check(_manager.team_score(Teams.Id.TEAM_BLUE) == 1 and _manager.team_score(Teams.Id.TEAM_RED) == 1,
			"only the head-on cost anyone a plane (BLUE %d, RED %d)" % [_manager.team_score(Teams.Id.TEAM_BLUE), _manager.team_score(Teams.Id.TEAM_RED)])


func _wingspan(plane: PlaneActor) -> float:
	return plane.plane_data.wing_span * PlaneVisual.VISUAL_SCALE


func _damage_on(plane: PlaneActor, part_list: Array[PlaneActor.Part]) -> float:
	var total: float = 0.0
	for part: PlaneActor.Part in part_list:
		total += plane.part_damage_of(part)
	return total


func _damage_everywhere_else(plane: PlaneActor, part_list: Array[PlaneActor.Part]) -> float:
	return _total_damage(plane) - _damage_on(plane, part_list)


func _total_damage(plane: PlaneActor) -> float:
	var total: float = 0.0
	for index: int in range(PlaneActor.PART_COUNT):
		total += plane.part_damage_of(index as PlaneActor.Part)
	return total


func _contact(first: PlaneActor, second: PlaneActor) -> Array:
	var forward_key: String = "%s|%s" % [first.name, second.name]
	var reverse_key: String = "%s|%s" % [second.name, first.name]
	if _contacts.has(forward_key):
		return _contacts[forward_key]
	return _contacts.get(reverse_key, [])


func _on_planes_collided(first: PlaneActor, second: PlaneActor, first_part: int, second_part: int, closing_speed: float) -> void:
	var key: String = "%s|%s" % [first.name, second.name]
	if not _contacts.has(key):
		_contacts[key] = [first_part, second_part, closing_speed]


func _finish() -> void:
	_stage = -1
	if _failures.is_empty():
		print("%d checks passed" % _checks)
		print("COLLISIONS_OK")
	else:
		for failure: String in _failures:
			print("FAIL: " + failure)
		print("COLLISIONS_FAILED")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
