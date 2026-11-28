extends Node
## Headless test of how the planes fly. The flight model is a rigid body in
## real gravity (see FlightDynamics), so this checks the things a real
## aeroplane does: trimmed cruise, loops, rolls, stalls, spins and recovering
## from them, what the propeller's torque does, banked turns and gliding.
##
##   godot --headless --fixed-fps 60 --path . res://tests/TestFlight.tscn [-- verbose=1]
##
## Prints FLIGHT_OK on success. Ten planes are each put in open sky and flown
## through one situation by a scripted hand on the stick.

const ARENA_SCENE: String = "res://scenes/arena/DogfightArena5v5.tscn"
const START_HEIGHT: float = 2200.0
const RUN_TIME: float = 30.0

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
	var highest: float = -INF
	var height_at: Dictionary[int, float] = {}
	var speed_at: Dictionary[int, float] = {}
	var bank_at: Dictionary[int, float] = {}
	var load_at: Dictionary[int, float] = {}
	var most_g: float = -INF
	var least_g: float = INF
	## Radians turned about each of the plane's own axes since the start:
	## x = pitched up, y = yawed left, z = rolled left.
	var turned: Vector3 = Vector3.ZERO
	## Heading change (radians, positive to the left), unwrapped.
	var heading_change: float = 0.0
	var last_yaw: float = 0.0
	var stalled_seen: bool = false
	var spin_seen: bool = false
	var stalled_time: float = 0.0
	## Free for each case to use.
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
	# Every plane the same: a stock Spitfire, far from the others, with no
	# edge of the arena or ceiling to steer it.
	var data: PlaneData = GameCatalog.find_plane(&"spitfire")
	for index: int in range(planes.size()):
		var plane: PlaneActor = planes[index]
		plane.stats = data.build_stock_stats()
		plane.arena_radius = 1.0e7
		plane.arena_ceiling = 1.0e7
		plane.weapons_locked = true
	var stall: float = planes[0].stats.stall_speed
	var top: float = planes[0].stats.top_speed

	_start("cruise", planes[0], 0, top * 0.8, 0.75, func(case: FlightCase, _time: float) -> void:
		case.plane.input.steer = Vector2.ZERO)

	_start("flat out", planes[1], 1, top, 1.0, func(case: FlightCase, _time: float) -> void:
		case.plane.input.steer = Vector2(_level_wings(case.plane), _hold_height(case)))

	_start("loop", planes[2], 2, top * 0.95, 1.0, func(case: FlightCase, _time: float) -> void:
		# Stick back and held there, eased a little if the wing complains,
		# until the horizon has gone right round. Then let go.
		if case.turned.x < TAU:
			case.plane.input.steer = Vector2(0.0, 0.55 if case.plane.stall_amount() < 0.08 else 0.25)
			case.notes["loop_time"] = _clock
		else:
			case.plane.input.steer = Vector2.ZERO)

	_start("roll", planes[3], 3, top * 0.75, 1.0, func(case: FlightCase, _time: float) -> void:
		# Stick hard over until the plane has gone right round, then level.
		if -case.turned.z < TAU and not case.notes.has("rolled"):
			case.plane.input.steer = Vector2(1.0, 0.0)
			case.notes["roll_time"] = _clock
		else:
			case.notes["rolled"] = 1.0
			case.plane.input.steer = Vector2(_level_wings(case.plane), 0.0))

	_start("stall", planes[4], 4, stall * 1.5, 0.0, func(case: FlightCase, time: float) -> void:
		# Throttle closed, the stick eased right back and held there, ailerons
		# left alone. Then power on and fly away.
		var plane: PlaneActor = case.plane
		if time < 14.0:
			plane.input.throttle = 0.0
			plane.input.steer = Vector2(0.0, minf(0.15 + time * 0.12, 1.0))
			case.notes["slowest"] = minf(_note(case, "slowest", 999.0), plane.indicated_speed())
			case.notes["most_attack"] = maxf(_note(case, "most_attack", 0.0), plane.flight.alpha)
			if time > 7.2:
				# By now the stick is right back and staying there.
				case.notes["lowest_nose"] = minf(_note(case, "lowest_nose", 9.0), plane.pitch)
				case.notes["most_bank"] = maxf(_note(case, "most_bank", 0.0), absf(plane.bank))
			case.notes["recovering"] = _clock
			case.notes["stall_height"] = plane.global_position.y
			return
		plane.input.throttle = 1.0
		if plane.indicated_speed() >= plane.stats.stall_speed * 1.25 and not case.notes.has("flying_again"):
			case.notes["flying_again"] = _clock
		plane.input.steer = Vector2(_level_wings(plane), _hold_pitch(plane, 0.0, 0.5)))

	_start("spin", planes[5], 5, stall * 1.4, 0.1, func(case: FlightCase, time: float) -> void:
		# Slow, then stick right back with full left rudder, and hold it in.
		var plane: PlaneActor = case.plane
		if time < 3.0:
			plane.input.steer = Vector2(0.0, 0.35)
			return
		if time < 16.0:
			plane.input.steer = Vector2(0.0, 1.0)
			plane.input.rudder = -1.0
			case.notes["turns_in_spin"] = absf(case.turned.y) / TAU
			case.notes["spin_bottom"] = plane.global_position.y
			return
		# Recovery: throttle closed, stick forward, rudder against the turn.
		if not case.notes.has("out_of_spin"):
			plane.input.throttle = 0.0
			var against: Vector3 = FlightPilot.recover_spin(plane)
			plane.input.steer = Vector2(against.x, against.y)
			plane.input.rudder = against.z
			if not plane.is_stalling() and absf(plane.flight.angular_velocity.y) < 0.3:
				case.notes["out_of_spin"] = _clock
			return
		plane.input.throttle = 1.0
		plane.input.rudder = 0.0
		plane.input.steer = Vector2(_level_wings(plane), _hold_pitch(plane, 0.0, 0.5)))

	_start("torque", planes[6], 6, stall * 1.3, 0.3, func(case: FlightCase, time: float) -> void:
		# Trimmed and slow on a little power, then the throttle is slammed open
		# and nobody touches the stick.
		var plane: PlaneActor = case.plane
		plane.input.steer = Vector2.ZERO
		if time < 4.0:
			case.notes["bank_before"] = plane.bank
			case.notes["yaw_before"] = case.heading_change
		else:
			plane.input.throttle = 1.0
			if time < 7.0:
				case.notes["bank_after"] = plane.bank
				case.notes["yaw_after"] = case.heading_change)

	_start("turn", planes[7], 7, top * 0.75, 1.0, func(case: FlightCase, time: float) -> void:
		# Roll to sixty degrees of bank and pull enough to hold height: 2 g.
		var plane: PlaneActor = case.plane
		var bank_error: float = deg_to_rad(-60.0) - plane.bank
		var roll_stick: float = clampf(-bank_error * 2.5 + plane.flight.angular_velocity.z * 0.4, -1.0, 1.0)
		var pull: float = clampf(plane.flight.elevator_for_load(2.0) - plane.climb_speed() * 0.03, -0.3, 1.0)
		plane.input.steer = Vector2(roll_stick, pull if time > 1.0 else 0.0)
		if time > 8.0 and not case.notes.has("turn_from"):
			case.notes["turn_from"] = case.heading_change
			case.notes["turn_from_time"] = _clock
			case.notes["turn_height"] = plane.global_position.y
		case.notes["turn_to"] = case.heading_change
		case.notes["turn_to_time"] = _clock)

	_start("glide", planes[8], 8, stall * 1.6, -1.0, func(case: FlightCase, _time: float) -> void:
		# Engine stopped: hold a good gliding speed with the nose.
		var plane: PlaneActor = case.plane
		var target: float = plane.stats.stall_speed * 1.5
		plane.input.steer = Vector2(_level_wings(plane), clampf((plane.speed - target) * 0.04 - plane.flight.angular_velocity.x * 0.5, -0.5, 0.5)))

	_start("free fall", planes[9], 9, top * 0.7, -1.0, func(case: FlightCase, time: float) -> void:
		# Engine stopped; from two seconds in, push the stick to hold no g at
		# all for two seconds. With no lift the plane is a thrown stone.
		var plane: PlaneActor = case.plane
		if time < 2.0 or time > 4.0:
			plane.input.steer = Vector2(_level_wings(plane), _hold_pitch(plane, deg_to_rad(-8.0), 0.5) if time > 4.0 else 0.0)
			if time < 2.0:
				case.notes["fall_start"] = plane.velocity.y
			return
		plane.input.steer = Vector2(0.0, clampf(plane.flight.elevator_for_load(0.0) - plane.load_factor() * 0.2, -1.0, 1.0))
		if time > 2.5:
			case.notes["weightless_g"] = maxf(_note(case, "weightless_g", 0.0), absf(plane.load_factor()))
		case.notes["fall_end"] = plane.velocity.y
		case.notes["fall_time"] = time - 2.0)


## [param throttle] below zero means the engine is stopped.
func _start(label: String, plane: PlaneActor, lane: int, speed: float, throttle: float, fly: Callable) -> void:
	var case: FlightCase = FlightCase.new()
	case.plane = plane
	case.fly = fly
	plane.speed = speed
	plane.set_engine_running(throttle >= 0.0)
	plane.input.throttle = maxf(throttle, 0.0)
	plane.throttle = plane.input.throttle
	plane.input.steer = Vector2.ZERO
	plane.input.rudder = 0.0
	# Lanes 600 m apart, all heading north.
	plane.teleport(Transform3D(Basis.IDENTITY, Vector3((float(lane) - 4.5) * 600.0, START_HEIGHT, 1200.0)))
	case.start_height = plane.global_position.y
	case.start_position = plane.global_position
	case.last_yaw = plane.yaw
	_cases[label] = case


## Stick that eases the nose toward [param target] radians above the horizon.
func _hold_pitch(plane: PlaneActor, target: float, most: float = 1.0) -> float:
	return clampf((target - plane.pitch) * 2.5 - plane.flight.angular_velocity.x * 0.8, -most, most)


## Stick that holds the height the case started at.
func _hold_height(case: FlightCase) -> float:
	var plane: PlaneActor = case.plane
	var climb_wanted: float = clampf((case.start_height - plane.global_position.y) * 0.3, -8.0, 8.0)
	return clampf((climb_wanted - plane.climb_speed()) * 0.03, -0.4, 0.4)


## Aileron that rolls the wings level. (Positive bank is left wing down.)
func _level_wings(plane: PlaneActor) -> float:
	return clampf(plane.bank * 2.0 + plane.flight.angular_velocity.z * 0.4, -1.0, 1.0)


func _watch(case: FlightCase, delta: float) -> void:
	var plane: PlaneActor = case.plane
	var second: int = floori(_clock)
	if not case.height_at.has(second):
		case.height_at[second] = plane.global_position.y
		case.speed_at[second] = plane.speed
		case.bank_at[second] = plane.bank
		case.load_at[second] = plane.load_factor()
	case.lowest = minf(case.lowest, plane.global_position.y)
	case.highest = maxf(case.highest, plane.global_position.y)
	case.most_g = maxf(case.most_g, plane.load_factor())
	case.least_g = minf(case.least_g, plane.load_factor())
	case.turned += plane.flight.angular_velocity * delta
	case.heading_change += wrapf(plane.yaw - case.last_yaw, -PI, PI)
	case.last_yaw = plane.yaw
	if plane.is_stalling():
		case.stalled_seen = true
		case.stalled_time += delta
	if plane.is_spinning():
		case.spin_seen = true


# ---------------------------------------------------------------------------
# Judging
# ---------------------------------------------------------------------------

func _judge() -> void:
	var stats: PlaneStats = _cases["cruise"].plane.stats
	var stall: float = stats.stall_speed
	var top: float = stats.top_speed

	# --- The aeroplane's figures come out of the physics --------------------------
	# The real Spitfire V: about 332 mph at sea level on emergency boost, and
	# 370 mph at 20,000 ft, where its supercharger runs out.
	_check(top * PlaneActor.MPH > 322.0 and top * PlaneActor.MPH < 342.0, "a Spitfire's top speed at sea level is the real one (%.0f mph)" % (top * PlaneActor.MPH))
	_check(stats.top_speed_high * PlaneActor.MPH > 362.0 and stats.top_speed_high * PlaneActor.MPH < 380.0 and absf(stats.critical_altitude - 6100.0) < 1.0,
			"and so is its best: %.0f mph at %.0f m" % [stats.top_speed_high * PlaneActor.MPH, stats.critical_altitude])
	_check(stall * 3.6 > 115.0 and stall * 3.6 < 160.0, "and so is its stalling speed (%.0f km/h)" % (stall * 3.6))
	_check(stats.climb_rate > 11.0 and stats.climb_rate < 21.0, "and its rate of climb (%.1f m/s)" % stats.climb_rate)
	_check(stats.landing_stall_speed < stall, "flaps lower the stalling speed (%.0f against %.0f km/h)" % [stats.landing_stall_speed * 3.6, stall * 3.6])

	# --- Trimmed flight ------------------------------------------------------------
	var cruise: FlightCase = _cases["cruise"]
	_check(cruise.plane.alive and absf(_height(cruise, 28) - cruise.start_height) < 120.0, "hands off, a trimmed plane holds its height (%.0f m in 28 s)" % (_height(cruise, 28) - cruise.start_height))
	_check(absf(cruise.plane.load_factor() - 1.0) < 0.06, "at 1 g (%.2f)" % cruise.plane.load_factor())
	_check(absf(cruise.plane.bank) < deg_to_rad(25.0), "with its wings near enough level (%.0f degrees)" % rad_to_deg(cruise.plane.bank))
	var flat_out: FlightCase = _cases["flat out"]
	# Up here the air is thinner: less drag for the same power, so the true
	# top speed is higher than at sea level, while the airspeed indicator
	# (which shows what the wings feel) reads lower.
	var flight: FlightDynamics = flat_out.plane.flight
	var height: float = flat_out.plane.global_position.y
	var top_here: float = flight.top_speed_at(height)
	_check(absf(_speed(flat_out, 28) - top_here) < top_here * 0.04, "flat out and level it holds its top speed for that height (%.0f of %.0f m/s at %.0f m)" % [_speed(flat_out, 28), top_here, height])
	_check(top_here > top * 1.02, "which is faster than at sea level, in thinner air (%.0f against %.0f m/s)" % [top_here, top])
	_check(flat_out.plane.indicated_speed() < flat_out.plane.speed * 0.95, "though the airspeed indicator reads less than the true speed (%.0f against %.0f m/s)" % [flat_out.plane.indicated_speed(), flat_out.plane.speed])
	_check(absf(flight.density_ratio - FlightDynamics.density_at(height) / FlightDynamics.AIR_DENSITY) < 0.001 and flight.density_ratio < 0.85,
			"the plane is flying in the air of its own height (%.0f%% of sea level's at %.0f m)" % [flight.density_ratio * 100.0, height])

	# --- The air ----------------------------------------------------------------------
	_check(absf(FlightDynamics.density_at(0.0) - 1.225) < 0.001 and absf(FlightDynamics.density_at(5000.0) - 0.736) < 0.01, "the air thins with height as the standard atmosphere does (%.3f kg/m3 at 5000 m)" % FlightDynamics.density_at(5000.0))
	_check(absf(FlightDynamics.sound_speed_at(0.0) - 340.3) < 0.5 and FlightDynamics.sound_speed_at(5000.0) < 322.0, "and sound travels slower in the cold up there (%.0f m/s at 5000 m)" % FlightDynamics.sound_speed_at(5000.0))
	var above: float = flight.critical_altitude + 2500.0
	var at_critical: float = flight.power_share_at(flight.critical_altitude)
	_check(is_equal_approx(flight.power_share_at(0.0), 1.0) and is_equal_approx(at_critical, flight.altitude_power) and at_critical > 0.7 and at_critical < 1.0,
			"the supercharger holds the boost up to %.0f m, at a cost: the engine gives %.0f%% of its sea-level power there" % [flight.critical_altitude, at_critical * 100.0])
	var lost_below: float = (1.0 - at_critical) / flight.critical_altitude
	var lost_above: float = (at_critical - flight.power_share_at(above)) / 2500.0
	_check(lost_above > lost_below * 1.5, "above that it has nothing left to hold it with, and power falls away faster (%.0f%% at %.0f m)" % [flight.power_share_at(above) * 100.0, above])
	_check(flight.top_speed_at(above + 2000.0) < flight.top_speed_at(flight.critical_altitude), "so there is a height where it is fastest, and higher is slower again (%.0f then %.0f m/s)" % [flight.top_speed_at(flight.critical_altitude), flight.top_speed_at(above + 2000.0)])
	_check(absf(stats.stall_speed - flight.stall_speed()) < 0.01 and flight.true_speed(flight.stall_speed()) > stats.stall_speed * 1.08,
			"it stalls at the same indicated speed anywhere, which up here is a faster true speed (%.0f against %.0f m/s)" % [flight.true_speed(flight.stall_speed()), stats.stall_speed])

	# --- Aerobatics ------------------------------------------------------------------
	var loop: FlightCase = _cases["loop"]
	_check(loop.plane.alive and loop.turned.x >= TAU, "holding the stick back takes it right round a loop (%.0f degrees)" % rad_to_deg(loop.turned.x))
	_check(_note(loop, "loop_time", 99.0) < 26.0, "in %.0f seconds" % _note(loop, "loop_time", 99.0))
	_check(loop.highest - loop.start_height > 250.0, "going %.0f m up and over the top" % (loop.highest - loop.start_height))
	_check(loop.most_g > 3.0 and loop.most_g < 8.6, "pulling %.1f g on the way in" % loop.most_g)
	var roll: FlightCase = _cases["roll"]
	_check(roll.plane.alive and _note(roll, "rolled", 0.0) > 0.0, "stick hard over rolls it right round (%.0f degrees)" % rad_to_deg(-roll.turned.z))
	var roll_rate: float = 360.0 / maxf(_note(roll, "roll_time", 99.0), 0.1)
	_check(roll_rate > 60.0 and roll_rate < 170.0, "at a fighter's rate of roll (%.0f degrees a second)" % roll_rate)
	_check(roll.start_height - _height(roll, 4) > 20.0, "through upside down, where its lift points at the ground: it comes out %.0f m lower" % (roll.start_height - _height(roll, 4)))

	# --- Stall ----------------------------------------------------------------------
	var stalled: FlightCase = _cases["stall"]
	# Full back stick is a pull to the buffet, not through it: the pilot's hand
	# stops where the wing is giving all it has.
	var edge: float = stalled.plane.flight.best_alpha()
	_check(not stalled.stalled_seen and _note(stalled, "most_attack", 9.0) < stalled.plane.flight.stall_alpha(),
			"throttle closed and the stick held right back, the wing is held at the buffet and does not let go (%.1f degrees; most lift at %.1f, lets go at %.1f)" % [
			rad_to_deg(_note(stalled, "most_attack", 9.0)), rad_to_deg(edge), rad_to_deg(stalled.plane.flight.stall_alpha())])
	_check(_note(stalled, "most_attack", 0.0) > edge * 0.85, "but it is taken all the way there")
	_check(_note(stalled, "slowest", 999.0) < stall, "it runs out of speed (down to %.0f m/s; it needs %.0f to hold itself up)" % [_note(stalled, "slowest", 999.0), stall])
	_check(_note(stalled, "lowest_nose", 9.0) < deg_to_rad(-2.0), "and with the stick still back the nose comes down by itself (%.0f degrees)" % rad_to_deg(_note(stalled, "lowest_nose", 9.0)))
	_check(_note(stalled, "most_bank", 9.0) < deg_to_rad(25.0), "without dropping a wing (%.0f degrees of bank at most)" % rad_to_deg(_note(stalled, "most_bank", 9.0)))
	_check(stalled.plane.alive and _note(stalled, "flying_again", 99.0) - _note(stalled, "recovering", 0.0) < 8.0,
			"power on, it is flying again in %.1f s" % (_note(stalled, "flying_again", 99.0) - _note(stalled, "recovering", 0.0)))
	var height_lost: float = stalled.start_height - stalled.lowest
	_check(height_lost < 450.0, "having lost %.0f m" % height_lost)
	_check(not stalled.plane.is_stalling() and stalled.plane.speed > stall * 1.2, "and it flies on (%.0f m/s)" % stalled.plane.speed)

	# --- Spin -----------------------------------------------------------------------
	var spin: FlightCase = _cases["spin"]
	_check(spin.spin_seen, "stick back with full rudder held on is how a stall is asked for: it stalls and spins")
	_check(_note(spin, "turns_in_spin", 0.0) > 1.0, "going round %.1f times" % _note(spin, "turns_in_spin", 0.0))
	_check(spin.start_height - _note(spin, "spin_bottom", spin.start_height) > 250.0, "and coming down fast (%.0f m)" % (spin.start_height - _note(spin, "spin_bottom", spin.start_height)))
	_check(spin.turned.y > 0.0, "to the left, the way the rudder was put")
	_check(spin.plane.alive and _note(spin, "out_of_spin", 99.0) - 16.0 < 7.0, "stick forward and opposite rudder stops it in %.1f s" % (_note(spin, "out_of_spin", 99.0) - 16.0))
	_check(not spin.plane.is_stalling() and absf(spin.plane.pitch) < deg_to_rad(35.0), "and the pilot flies it out of the dive (nose %.0f degrees)" % rad_to_deg(spin.plane.pitch))

	# --- Propeller effects --------------------------------------------------------------
	var torque: FlightCase = _cases["torque"]
	var rolled_left: float = _note(torque, "bank_after", 0.0) - _note(torque, "bank_before", 0.0)
	_check(rolled_left > deg_to_rad(2.0), "slamming the throttle open at low speed rolls the plane to the left (%.1f degrees)" % rad_to_deg(rolled_left))
	var swung_left: float = _note(torque, "yaw_after", 0.0) - _note(torque, "yaw_before", 0.0)
	_check(swung_left > deg_to_rad(1.0), "and swings its nose left (%.1f degrees)" % rad_to_deg(swung_left))
	_check(torque.plane.alive and absf(torque.plane.bank) < deg_to_rad(40.0), "which the pilot's trimming then takes out (bank %.0f degrees at the end)" % rad_to_deg(torque.plane.bank))

	# --- Turning ---------------------------------------------------------------------
	var turn: FlightCase = _cases["turn"]
	var turn_time: float = _note(turn, "turn_to_time", 1.0) - _note(turn, "turn_from_time", 0.0)
	var turn_rate: float = -(_note(turn, "turn_to", 0.0) - _note(turn, "turn_from", 0.0)) / maxf(turn_time, 0.1)
	var expected_rate: float = FlightDynamics.GRAVITY * tan(deg_to_rad(60.0)) / maxf(turn.plane.speed, 1.0)
	_check(absf(turn.plane.bank + deg_to_rad(60.0)) < deg_to_rad(8.0), "it turns by banking (%.0f degrees)" % rad_to_deg(-turn.plane.bank))
	_check(absf(turn.plane.load_factor() - 2.0) < 0.35, "a sixty-degree bank held level is 2 g (%.2f)" % turn.plane.load_factor())
	_check(absf(turn_rate - expected_rate) < expected_rate * 0.25, "and turns as fast as that bank and speed say it must (%.1f against %.1f degrees a second)" % [rad_to_deg(turn_rate), rad_to_deg(expected_rate)])
	_check(absf(turn.plane.global_position.y - _note(turn, "turn_height", 0.0)) < 150.0, "holding its height (%.0f m)" % (turn.plane.global_position.y - _note(turn, "turn_height", 0.0)))
	_check(absf(turn.plane.sideslip()) < deg_to_rad(4.0), "without skidding (%.1f degrees of slip)" % rad_to_deg(turn.plane.sideslip()))

	# --- Gliding ---------------------------------------------------------------------
	var glide: FlightCase = _cases["glide"]
	var glide_time: float = 18.0
	var sink: float = (_height(glide, 10) - _height(glide, 28)) / glide_time
	var glide_ratio: float = _speed(glide, 20) / maxf(sink, 0.1)
	_check(glide.plane.alive and not glide.plane.is_stalling(), "with the engine stopped it glides")
	_check(glide_ratio > 6.0 and glide_ratio < 18.0, "about %.0f m forward for every metre down (%.1f m/s down at %.0f m/s)" % [glide_ratio, sink, _speed(glide, 20)])

	# --- Gravity ---------------------------------------------------------------------
	var fall: FlightCase = _cases["free fall"]
	var fall_rate: float = (_note(fall, "fall_start", 0.0) - _note(fall, "fall_end", 0.0)) / maxf(_note(fall, "fall_time", 1.0), 0.1)
	_check(_note(fall, "weightless_g", 9.0) < 0.35, "pushing the stick forward takes the weight off the wings (%.2f g)" % _note(fall, "weightless_g", 9.0))
	_check(absf(fall_rate - FlightDynamics.GRAVITY) < 2.5, "and then it falls as anything falls: %.1f m/s faster every second" % fall_rate)

	if OS.get_cmdline_user_args().has("verbose=1"):
		for label: String in _cases:
			var case: FlightCase = _cases[label]
			var line: String = "%-10s" % label
			for second: int in [0, 2, 4, 6, 8, 10, 14, 18, 22, 26, 29]:
				if case.height_at.has(second):
					line += " |%2d h%+5.0f v%3.0f b%+4.0f g%+4.1f" % [second, case.height_at[second] - case.start_height, case.speed_at[second], rad_to_deg(case.bank_at[second]), case.load_at[second]]
			print(line, "  g %.1f..%.1f alive %s notes %s" % [case.least_g, case.most_g, case.plane.alive, case.notes])


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
