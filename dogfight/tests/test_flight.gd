extends Node
## Headless test of how the planes fly: lift, stalling and recovery, gliding,
## and turning.
##
##   godot --headless --fixed-fps 60 --path . res://tests/TestFlight.tscn
##
## Prints FLIGHT_OK on success. Ten planes are each put in open sky and flown
## through one situation by a scripted hand on the stick.

const ARENA_SCENE: String = "res://scenes/arena/DogfightArena5v5.tscn"
const START_HEIGHT: float = 620.0
const RUN_TIME: float = 26.0

var _manager: MatchManager5v5
var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0
var _clock: float = -1.0
var _cases: Dictionary[String, FlightCase] = {}
var _finished: bool = false


## One plane flying one situation, and what it was seen to do.
class FlightCase:
	extends RefCounted
	var plane: PlaneActor
	## Called every tick with (case, seconds since the start) to work the controls.
	var fly: Callable
	var start_height: float = 0.0
	var start_position: Vector3 = Vector3.ZERO
	var lowest: float = INF
	## Largest change in rate of descent from one tick to the next (m/s).
	var worst_drop_step: float = 0.0
	var last_vertical: float = 0.0
	var height_at: Dictionary[int, float] = {}
	var speed_at: Dictionary[int, float] = {}
	var yaw_at: Dictionary[int, float] = {}
	var bank_at: Dictionary[int, float] = {}
	var position_at: Dictionary[int, Vector3] = {}
	var most_g: float = 0.0
	var flying_again_at: float = -1.0
	var stalled_seen: bool = false
	var total_turn: float = 0.0
	var last_yaw: float = 0.0
	var notes: Dictionary[String, float] = {}


func _ready() -> void:
	Profile.persistence_enabled = false
	Profile.reset_to_new_profile(false)
	GameSession.local_player_enabled = false
	GameSession.ground_start = false
	GameSession.match_seed = 9
	GameSession.match_duration = 400.0
	var arena: Node = (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	_manager = arena.get_node("MatchManager") as MatchManager5v5
	for slot: PilotSlot in _manager.get_roster():
		slot.controller.set_physics_process(false)


func _physics_process(delta: float) -> void:
	if _finished or _manager.phase != MatchManager5v5.Phase.ACTIVE:
		return
	if _clock < 0.0:
		_clock = 0.0
		_set_up()
		return
	_clock += delta
	for label: String in _cases:
		var case: FlightCase = _cases[label]
		if not case.plane.alive:
			continue
		case.fly.call(case, _clock)
		_watch(case, delta)
	if _clock >= RUN_TIME:
		_finished = true
		_judge()
		_report()


# ---------------------------------------------------------------------------
# Setting up
# ---------------------------------------------------------------------------

func _set_up() -> void:
	var planes: Array[PlaneActor] = _manager.get_planes()
	# Every plane the same: a stock Hurricane, far from the others, with no
	# edge of the arena or ceiling to steer it.
	var data: PlaneData = GameCatalog.find_plane(&"hurricane")
	for index: int in range(planes.size()):
		var plane: PlaneActor = planes[index]
		plane.stats = data.build_stock_stats(1)
		plane.arena_radius = 1.0e7
		plane.arena_ceiling = 1.0e7
		plane.weapons_locked = true
	var stall: float = planes[0].stats.stall_speed
	var top: float = planes[0].stats.top_speed
	# Three planes caught too slow to fly with their noses in the air,
	# engines at full power.
	_start("slow, hands off", planes[0], 0, stall * 0.7, true, func(case: FlightCase, _time: float) -> void:
		case.plane.input.steer = Vector2.ZERO)
	_start("slow, nose down", planes[1], 1, stall * 0.7, true, func(case: FlightCase, _time: float) -> void:
		# Push the nose down until it is flying again, then ease out level.
		var flying: bool = case.plane.speed > case.plane.stats.stall_speed * 1.15
		case.plane.input.steer = Vector2(0.0, _hold_pitch(case.plane, 0.0) if flying else -1.0))
	_start("slow, stick held back", planes[2], 2, stall * 0.7, true, func(case: FlightCase, _time: float) -> void:
		case.plane.input.steer = Vector2(0.0, 1.0))
	_start("glide", planes[3], 3, stall * 1.3, false, func(case: FlightCase, _time: float) -> void:
		# Engine off: hold the best gliding speed with the nose.
		var target: float = case.plane.stats.stall_speed * PlaneActor.BEST_GLIDE_SPEED_RATIO
		case.plane.input.steer = Vector2(0.0, clampf((case.plane.speed - target) * 0.08, -0.6, 0.6)))
	_start("engine cut at speed", planes[4], 4, top, false, func(case: FlightCase, _time: float) -> void:
		case.plane.input.steer = Vector2(0.0, _hold_pitch(case.plane, 0.0)))
	_start("cruise", planes[5], 5, top * 0.9, true, func(case: FlightCase, _time: float) -> void:
		case.plane.input.steer = Vector2.ZERO)
	_start("turn at speed", planes[6], 6, top, true, func(case: FlightCase, _time: float) -> void:
		case.plane.input.steer = Vector2(1.0, 0.0))
	_start("turn slow", planes[7], 7, stall * 1.12, true, func(case: FlightCase, time: float) -> void:
		# Throttled back so it stays slow.
		case.plane.input.throttle = 0.6
		case.plane.input.steer = Vector2(1.0 if time > 1.0 else 0.0, 0.0))
	_start("turn below flying speed", planes[8], 8, stall * 0.9, false, func(case: FlightCase, time: float) -> void:
		case.plane.input.steer = Vector2(1.0 if time < 1.5 else 0.0, 0.0))
	_start("zoom climb", planes[9], 9, top, true, func(case: FlightCase, time: float) -> void:
		# Haul the nose up and hold it there until the speed is gone, then let go.
		case.plane.input.steer = Vector2(0.0, 1.0 if time < 9.0 else 0.0))


func _start(label: String, plane: PlaneActor, lane: int, speed: float, engine_on: bool, fly: Callable) -> void:
	# The three "slow" planes start nose-high, as after pulling up too far.
	var nose_up: float = deg_to_rad(25.0) if label.begins_with("slow") else 0.0
	var case: FlightCase = FlightCase.new()
	case.plane = plane
	case.fly = fly
	plane.speed = speed
	plane.set_engine_running(engine_on)
	plane.input.throttle = 1.0 if engine_on else 0.0
	plane.throttle = plane.input.throttle
	plane.input.steer = Vector2.ZERO
	# Lanes 320 m apart, all heading north.
	plane.teleport(Transform3D(Basis(Vector3.RIGHT, nose_up), Vector3((float(lane) - 4.5) * 320.0, START_HEIGHT, 1200.0)))
	case.start_height = plane.global_position.y
	case.start_position = plane.global_position
	case.last_yaw = plane.yaw
	_cases[label] = case


## Stick position that eases the flight path toward [param target] radians.
func _hold_pitch(plane: PlaneActor, target: float) -> float:
	return clampf((target - plane.pitch) * 6.0, -1.0, 1.0)


func _watch(case: FlightCase, delta: float) -> void:
	var plane: PlaneActor = case.plane
	var second: int = floori(_clock)
	if not case.height_at.has(second):
		case.height_at[second] = plane.global_position.y
		case.speed_at[second] = plane.speed
		case.yaw_at[second] = case.total_turn
		case.bank_at[second] = plane.bank
		case.position_at[second] = plane.global_position
	case.lowest = minf(case.lowest, plane.global_position.y)
	case.worst_drop_step = maxf(case.worst_drop_step, case.last_vertical - plane.velocity.y)
	case.last_vertical = plane.velocity.y
	case.most_g = maxf(case.most_g, plane.load_factor())
	var lift_possible: float = pow(plane.speed / plane.stats.stall_speed, 2.0) * (1.0 + PlaneActor.FLAP_LIFT_BONUS)
	case.notes["g_over_lift"] = maxf(_note(case, "g_over_lift", -INF), plane.load_factor() - lift_possible)
	if _clock > 3.0:
		case.notes["slowest"] = minf(_note(case, "slowest", INF), plane.speed)
	case.total_turn += wrapf(plane.yaw - case.last_yaw, -PI, PI)
	case.last_yaw = plane.yaw
	if plane.is_stalling():
		case.stalled_seen = true
	elif case.stalled_seen and case.flying_again_at < 0.0 and plane.speed >= plane.stats.stall_speed:
		case.flying_again_at = _clock
	if delta <= 0.0:
		return


# ---------------------------------------------------------------------------
# Judging
# ---------------------------------------------------------------------------

func _judge() -> void:
	var stall: float = _cases["cruise"].plane.stats.stall_speed
	var top: float = _cases["cruise"].plane.stats.top_speed
	var gravity_step: float = PlaneActor.FLIGHT_GRAVITY / 60.0

	# --- Too slow to fly: it sinks, it does not drop -------------------------
	var hands_off: FlightCase = _cases["slow, hands off"]
	_check(hands_off.stalled_seen, "at 70% of stalling speed the wings cannot hold the plane")
	_check(hands_off.worst_drop_step <= gravity_step * 1.2, "but its descent builds no faster than a fall would (largest change %.2f m/s in a tick, gravity is %.2f)" % [hands_off.worst_drop_step, gravity_step])
	var early_loss: float = hands_off.start_height - _height(hands_off, 1)
	_check(early_loss < 8.0, "after a second it has lost only %.1f m, not dropped out of the sky" % early_loss)
	_check(hands_off.plane.alive and hands_off.flying_again_at > 0.0, "left alone, it picks up speed on the way down and flies again (after %.1f s)" % hands_off.flying_again_at)
	var hands_off_loss: float = hands_off.start_height - hands_off.lowest
	_check(hands_off_loss < 120.0, "having lost %.0f m doing it" % hands_off_loss)
	_check(absf(_height(hands_off, 20) - _height(hands_off, 24)) < 12.0, "after which it holds its height (%.0f m in 4 s)" % (_height(hands_off, 24) - _height(hands_off, 20)))
	_check(_speed(hands_off, 20) >= stall, "and it is still flying 20 s later (%.0f m/s, stalls at %.0f)" % [_speed(hands_off, 20), stall])

	# --- Nose down gets the speed back sooner --------------------------------
	var nose_down: FlightCase = _cases["slow, nose down"]
	_check(nose_down.flying_again_at > 0.0 and nose_down.flying_again_at < hands_off.flying_again_at - 0.2,
			"putting the nose down gets flying speed back sooner (%.1f s against %.1f s hands off)" % [nose_down.flying_again_at, hands_off.flying_again_at])
	_check(nose_down.start_height - nose_down.lowest < 150.0, "for %.0f m of height" % (nose_down.start_height - nose_down.lowest))
	_check(nose_down.plane.alive and absf(nose_down.plane.pitch) < deg_to_rad(6.0) and not nose_down.plane.is_stalling(), "and the pilot then levels out, in control (nose %.1f degrees)" % rad_to_deg(nose_down.plane.pitch))
	_check(_speed(nose_down, 20) > stall * 1.05, "flying at %.0f m/s" % _speed(nose_down, 20))

	# --- Holding the stick back when slow does not help ----------------------
	var held_back: FlightCase = _cases["slow, stick held back"]
	var over: float = _note(held_back, "g_over_lift", 0.0)
	_check(over <= 0.01, "hauling back cannot make the wings pull harder than the airspeed allows (never more than %.2f g over what the airspeed gives)" % over)
	_check(_note(held_back, "slowest", INF) < stall, "holding the stick back keeps stalling it again (down to %.0f m/s)" % _note(held_back, "slowest", INF))
	_check(held_back.plane.alive, "though it still does not fall out of the sky")

	# --- Gliding ---------------------------------------------------------------
	var glide: FlightCase = _cases["glide"]
	var glide_run: float = Vector2(glide.position_at[22].x - glide.position_at[6].x, glide.position_at[22].z - glide.position_at[6].z).length()
	var glide_fall: float = _height(glide, 6) - _height(glide, 22)
	var glide_ratio: float = glide_run / maxf(glide_fall, 0.1)
	_check(glide_ratio > 4.0 and glide_ratio < 9.0, "engine off, it glides about 1 in %.1f" % glide_ratio)
	_check(not glide.plane.is_stalling() and absf(_speed(glide, 22) - stall * PlaneActor.BEST_GLIDE_SPEED_RATIO) < 6.0, "holding its speed with the nose down a little (%.0f m/s, nose %.1f degrees)" % [_speed(glide, 22), rad_to_deg(glide.plane.pitch)])
	var cut: FlightCase = _cases["engine cut at speed"]
	_check(_height(cut, 6) > cut.start_height - 3.0, "an engine cut at speed leaves the plane flying level on its momentum (%.1f m lost in 6 s)" % (cut.start_height - _height(cut, 6)))
	_check(_speed(cut, 6) < top * 0.9 and _speed(cut, 6) > stall, "slowing as drag takes the speed off (%.0f -> %.0f m/s in 6 s)" % [top, _speed(cut, 6)])
	var sink_rate: float = (_height(cut, 18) - _height(cut, 24)) / 6.0
	_check(cut.plane.alive and sink_rate > 3.0 and sink_rate < 14.0, "and when it can no longer fly level it descends at %.0f m/s: a glide, not a plummet" % sink_rate)

	# --- Cruise ----------------------------------------------------------------
	var cruise: FlightCase = _cases["cruise"]
	_check(absf(_speed(cruise, 20) - top) < top * 0.03, "at full throttle it settles at top speed (%.0f of %.0f m/s)" % [_speed(cruise, 20), top])
	_check(absf(_height(cruise, 20) - cruise.start_height) < 5.0, "holding its height hands off (%.1f m)" % (_height(cruise, 20) - cruise.start_height))
	_check(absf(cruise.plane.load_factor() - 1.0) < 0.05, "at 1 g (%.2f)" % cruise.plane.load_factor())

	# --- Turning ---------------------------------------------------------------
	var fast_turn: FlightCase = _cases["turn at speed"]
	var slow_turn: FlightCase = _cases["turn slow"]
	var fast_bank: float = absf(fast_turn.bank_at[3])
	var slow_bank: float = absf(slow_turn.bank_at[6])
	_check(fast_bank > deg_to_rad(45.0), "a turn is a bank: full stick at speed rolls it over %.0f degrees" % rad_to_deg(fast_bank))
	var fast_rate: float = absf(fast_turn.yaw_at[4] - fast_turn.yaw_at[2]) / 2.0
	var fast_speed: float = (_speed(fast_turn, 2) + _speed(fast_turn, 4)) * 0.5
	# g x tan(bank) / speed, plus the little the rudder skids it round.
	var expected: float = PlaneActor.FLIGHT_GRAVITY * tan(fast_bank) / fast_speed + PlaneActor.RUDDER_YAW_RATE
	_check(absf(fast_rate - expected) < expected * 0.2, "and it turns at the rate that bank gives at that speed (%.0f degrees/s, physics says %.0f)" % [rad_to_deg(fast_rate), rad_to_deg(expected)])
	_check(fast_turn.most_g > 1.8 and fast_turn.most_g <= PlaneActor.G_LIMIT + 0.01, "pulling %.1f g" % fast_turn.most_g)
	_check(absf(_height(fast_turn, 8) - fast_turn.start_height) < 25.0, "without losing or gaining height (%.0f m in 8 s)" % (_height(fast_turn, 8) - fast_turn.start_height))
	_check(_speed(fast_turn, 10) < top * 0.97, "a hard turn costs speed (%.0f -> %.0f m/s)" % [top, _speed(fast_turn, 10)])
	var later_rate: float = absf(fast_turn.yaw_at[20] - fast_turn.yaw_at[16]) / 4.0
	_check(later_rate < fast_rate * 0.97, "so held, it settles into a slower turn (%.0f then %.0f degrees/s)" % [rad_to_deg(fast_rate), rad_to_deg(later_rate)])
	var slow_rate: float = absf(slow_turn.yaw_at[10] - slow_turn.yaw_at[6]) / 4.0
	_check(slow_bank < fast_bank - deg_to_rad(8.0), "just above stalling speed it cannot bank as far without losing height (%.0f against %.0f degrees)" % [rad_to_deg(slow_bank), rad_to_deg(fast_bank)])
	_check(slow_rate < fast_rate * 0.8, "so it turns more slowly (%.0f against %.0f degrees/s)" % [rad_to_deg(slow_rate), rad_to_deg(fast_rate)])
	_check(slow_turn.start_height - slow_turn.lowest < 30.0, "but it does not fall out of the turn (%.0f m lost)" % (slow_turn.start_height - slow_turn.lowest))
	var too_slow: FlightCase = _cases["turn below flying speed"]
	_check(absf(too_slow.bank_at[1]) < deg_to_rad(12.0), "below flying speed there is no lift to spare for a turn: it stays nearly wings-level (%.0f degrees)" % rad_to_deg(absf(too_slow.bank_at[1])))
	_check(too_slow.plane.alive, "and survives the attempt")

	# --- Zoom climb --------------------------------------------------------------
	var zoom: FlightCase = _cases["zoom climb"]
	var gained: float = 0.0
	for second: int in zoom.height_at:
		gained = maxf(gained, zoom.height_at[second] - zoom.start_height)
	_check(gained > 80.0, "hauling the nose up trades speed for height (%.0f m gained)" % gained)
	_check(zoom.most_g > 2.0, "pulling %.1f g into the climb" % zoom.most_g)
	_check(zoom.plane.alive and _speed(zoom, 24) > stall, "and once the speed has gone the nose comes down and it flies on (%.0f m/s at the end)" % _speed(zoom, 24))
	_check(zoom.worst_drop_step <= gravity_step * 1.2, "with no sudden drop at the top (largest change %.2f m/s in a tick)" % zoom.worst_drop_step)

	if OS.get_cmdline_user_args().has("verbose=1"):
		for label: String in _cases:
			var case: FlightCase = _cases[label]
			var line: String = "%-26s" % label
			for second: int in [0, 2, 4, 6, 10, 15, 20, 25]:
				if case.height_at.has(second):
					line += "  %2ds h%+5.0f v%3.0f b%+4.0f" % [second, case.height_at[second] - case.start_height, case.speed_at[second], rad_to_deg(case.bank_at[second])]
			print(line, "  maxg %.2f  alive %s" % [case.most_g, case.plane.alive])


func _height(case: FlightCase, second: int) -> float:
	if case.height_at.has(second):
		return case.height_at[second]
	return case.plane.global_position.y


func _speed(case: FlightCase, second: int) -> float:
	if case.speed_at.has(second):
		return case.speed_at[second]
	return case.plane.speed


func _note(case: FlightCase, key: String, fallback: float) -> float:
	if case.notes.has(key):
		return case.notes[key]
	return fallback


func _report() -> void:
	if _failures.is_empty():
		print("%d checks passed" % _checks)
		print("FLIGHT_OK")
	else:
		for failure: String in _failures:
			print("FAIL: " + failure)
		print("FLIGHT_FAILED")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
