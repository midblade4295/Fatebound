extends SceneTree
## Bench test of FlightDynamics on its own (no scene). Prints what the model
## does in a handful of set-piece manoeuvres. Run:
##   godot --headless --path . -s res://tools/flight_lab.gd [-- trim|loop|roll|spin|torque|turn|glide]

const DT: float = 1.0 / 60.0

var _height: float = 1000.0


func _make(kind: String) -> FlightDynamics:
	var f: FlightDynamics = FlightDynamics.new()
	match kind:
		"hurricane":
			f.configure(3300.0, 23.9, 12.19, 954000.0, 0.025, 1.45)
		"spitfire":
			f.configure(3000.0, 22.48, 11.23, 1096000.0, 0.021, 1.5)
		_:
			f.configure(4175.0, 21.83, 11.28, 1280000.0, 0.0176, 1.4)
	return f


func _pitch(f: FlightDynamics) -> float:
	return rad_to_deg(asin(clampf(-f.basis.z.y, -1.0, 1.0)))


## + = right wing down.
func _bank(f: FlightDynamics) -> float:
	return rad_to_deg(atan2(-f.basis.x.y, f.basis.y.y))


func _heading(f: FlightDynamics) -> float:
	var forward: Vector3 = -f.basis.z
	return rad_to_deg(atan2(forward.x, -forward.z))


func _line(t: float, f: FlightDynamics) -> String:
	return "t=%5.1f v=%6.1f alt=%7.1f vy=%6.1f pitch=%6.1f bank=%7.1f hdg=%7.1f a=%5.1f b=%5.1f g=%5.2f stall=%.2f w=(%.2f,%.2f,%.2f)" % [
		t, f.airspeed, _height, f.velocity.y, _pitch(f), _bank(f), _heading(f), rad_to_deg(f.alpha), rad_to_deg(f.beta), f.load_factor, f.stall,
		f.angular_velocity.x, f.angular_velocity.y, f.angular_velocity.z]


func _tick(f: FlightDynamics, trimming: bool = true) -> void:
	if trimming:
		f.update_trim(DT)
	f.step(DT)
	_height += f.velocity.y * DT


func _start(kind: String, speed: float, height: float = 1000.0) -> FlightDynamics:
	var f: FlightDynamics = _make(kind)
	f.reset(Basis.IDENTITY, Vector3(0.0, 0.0, -speed))
	_height = height
	return f


func _init() -> void:
	for kind: String in ["hurricane", "spitfire", "mustang"]:
		var f: FlightDynamics = _make(kind)
		print("== %s: top %.1f m/s, stall %.1f (flaps %.1f), climb %.1f m/s at %.0f, static thrust %.0f N, stall alpha %.1f" % [
			kind, f.level_top_speed(), f.stall_speed(), f.stall_speed(1.0), f.best_climb_rate(), f.best_climb_speed(), f._static_thrust,
			rad_to_deg(f.stall_alpha())])
	var probe: FlightDynamics = _make("spitfire")
	for speed: float in [50.0, 70.0, 90.0, 110.0, 135.0]:
		for setting: float in [0.3, 1.0]:
			probe.throttle = setting
			probe.reset(Basis.IDENTITY, Vector3(0.0, 0.0, -speed))
			print("   trim at %3.0f m/s, throttle %.1f: %.3v  (alpha %.1f deg, %.1f g per unit of elevator)" % [speed, setting, probe.trim, rad_to_deg(probe._trim_alpha), probe._load_per_elevator])
	var which: String = "all"
	for argument: String in OS.get_cmdline_user_args():
		which = argument
	if which == "all" or which == "trim":
		_trim_test()
	if which == "all" or which == "loop":
		_loop_test()
	if which == "all" or which == "roll":
		_roll_test()
	if which == "all" or which == "spin":
		_spin_test(0.1)
		_spin_test(1.0)
	if which == "all" or which == "torque":
		_torque_test()
	if which == "all" or which == "turn":
		_turn_test()
	if which == "all" or which == "glide":
		_glide_test()
	if which == "all" or which == "air":
		_air_test()
	if which == "all" or which == "ground":
		_stand_test()
		_takeoff_test(0.6)
		_brake_test()
		_swerve_test()
		_landing_test(2.5)
		_landing_test(2.5, true)
		_landing_test(5.0, true)
	quit()


## Hands off: does it settle into level flight, and stay there?
func _trim_test() -> void:
	print("--- TRIM: hands off at 75% throttle, then full")
	var f: FlightDynamics = _start("spitfire", 90.0)
	f.throttle = 0.75
	for i: int in range(60 * 40):
		_tick(f)
		if i % 300 == 0:
			print(_line(float(i) * DT, f), " trim=%.3v" % f.trim)
	print("  full throttle now")
	f.throttle = 1.0
	for i: int in range(60 * 60):
		_tick(f)
		if i % 600 == 0:
			print(_line(float(i) * DT, f), " trim=%.3v" % f.trim)


func _loop_test() -> void:
	print("--- LOOP: from 125 m/s, pull back, ease off if the wing complains")
	var f: FlightDynamics = _start("spitfire", 125.0)
	var turned: float = 0.0
	for i: int in range(60 * 30):
		f.elevator = 0.5 if f.stall < 0.08 else 0.2
		_tick(f)
		turned += f.angular_velocity.x * DT
		if i % 60 == 0:
			print(_line(float(i) * DT, f), " turned=%.0f" % rad_to_deg(turned))
		if turned > TAU:
			print("  LOOP COMPLETE at t=%.1f alt=%.0f v=%.0f" % [float(i) * DT, _height, f.airspeed])
			break


func _roll_test() -> void:
	for speed: float in [60.0, 100.0, 140.0]:
		var f: FlightDynamics = _start("spitfire", speed)
		var rolled: float = 0.0
		var took: float = 0.0
		for i: int in range(60 * 12):
			f.aileron = 1.0
			_tick(f)
			rolled += -f.angular_velocity.z * DT
			if rolled > TAU:
				took = float(i) * DT
				break
		print("--- ROLL at %.0f m/s: 360 degrees in %.1f s (%.0f deg/s), lost %.0f m" % [speed, took, 360.0 / maxf(took, 0.01), 1000.0 - _height])


func _spin_test(power_setting: float) -> void:
	print("--- SPIN at throttle %.1f: slow down, stick right back, full left rudder; recover from t=20" % power_setting)
	var f: FlightDynamics = _start("spitfire", 60.0, 2500.0)
	f.throttle = power_setting
	var yawed: float = 0.0
	var recovered_at: float = -1.0
	for i: int in range(60 * 40):
		var t: float = float(i) * DT
		var trimming: bool = false
		if t < 4.0:
			f.elevator = 0.3
		elif t < 20.0:
			f.elevator = 1.0
			f.rudder = -1.0
		elif recovered_at < 0.0:
			# Throttle closed, stick forward, rudder against the spin.
			f.throttle = 0.0
			f.elevator = -0.5
			f.rudder = clampf(f.angular_velocity.y * 3.0, -1.0, 1.0)
			if f.stall < 0.15 and absf(f.angular_velocity.y) < 0.3:
				recovered_at = t
				print("  UNSTALLED at t=%.1f (%.1f s after starting recovery), alt %.0f" % [t, t - 20.0, _height])
		else:
			# Roll level, then ease out of the dive.
			trimming = true
			f.throttle = 1.0
			f.rudder = 0.0
			f.aileron = clampf(-_bank(f) * 0.03 + f.angular_velocity.z * 0.3, -1.0, 1.0)
			f.elevator = 0.3 if absf(_bank(f)) < 40.0 and _pitch(f) < 0.0 and f.stall < 0.08 else 0.0
		_tick(f, trimming)
		yawed += f.angular_velocity.y * DT
		if i % 60 == 0:
			print(_line(t, f), " turns=%.2f" % (yawed / TAU))


func _torque_test() -> void:
	print("--- TORQUE: cruising at 50 m/s on 40% power, slam the throttle open, hands off")
	var f: FlightDynamics = _start("spitfire", 50.0)
	f.throttle = 0.4
	f.settle_trim()
	for i: int in range(60 * 3):
		_tick(f)
	print(_line(0.0, f), " trim=%.3v" % f.trim)
	f.throttle = 1.0
	for i: int in range(60 * 10):
		_tick(f)
		if i % 60 == 0:
			print(_line(float(i) * DT, f), " trim=%.3v" % f.trim)


func _turn_test() -> void:
	print("--- TURN: roll to 60 degrees, pull to hold height, from 100 m/s")
	var f: FlightDynamics = _start("spitfire", 100.0)
	for i: int in range(60 * 30):
		f.aileron = clampf((60.0 - _bank(f)) * 0.04 + f.angular_velocity.z * 0.4, -1.0, 1.0)
		f.elevator = clampf((2.0 - f.load_factor) * 0.3 - f.velocity.y * 0.02, -1.0, 1.0)
		_tick(f)
		if i % 180 == 0:
			print(_line(float(i) * DT, f))


func _glide_test() -> void:
	print("--- GLIDE: engine dead at 90 m/s, hands off")
	var f: FlightDynamics = _start("spitfire", 90.0)
	f.engine_turning = false
	f.engine_output = 0.0
	for i: int in range(60 * 60):
		_tick(f)
		if i % 600 == 0:
			print(_line(float(i) * DT, f), "  glide ratio %.1f" % (f.airspeed / maxf(-f.velocity.y, 0.1)))


# ---------------------------------------------------------------------------
# The air at height
# ---------------------------------------------------------------------------

func _air_test() -> void:
	print("--- AIR: what height does")
	var f: FlightDynamics = _make("spitfire")
	for height: float in [0.0, 1500.0, 3000.0, 4500.0, 6000.0]:
		print("   %5.0f m: density %.3f (%.0f%%), sound %.0f m/s, power %.0f%%, top speed %.0f m/s true = %.0f indicated" % [height, FlightDynamics.density_at(height),
				FlightDynamics.density_at(height) / FlightDynamics.AIR_DENSITY * 100.0, FlightDynamics.sound_speed_at(height), f.power_share_at(height) * 100.0,
				f.top_speed_at(height), f.top_speed_at(height) * sqrt(FlightDynamics.density_at(height) / FlightDynamics.AIR_DENSITY)])
	print("--- DIVE: straight down from 6000 m at full power")
	f = _start("spitfire", 120.0, 6000.0)
	f.reset(Basis(Vector3.RIGHT, deg_to_rad(-80.0)), Basis(Vector3.RIGHT, deg_to_rad(-80.0)) * Vector3(0.0, 0.0, -120.0))
	for i: int in range(60 * 14):
		f.altitude = _height
		f.elevator = clampf((deg_to_rad(-80.0) - asin(clampf(-f.basis.z.y, -1.0, 1.0))) * 2.0 - f.angular_velocity.x, -1.0, 1.0)
		_tick(f)
		if i % 120 == 0:
			print(_line(float(i) * DT, f), " mach %.2f ias %.0f" % [f.mach, f.indicated_airspeed])


# ---------------------------------------------------------------------------
# On the ground
# ---------------------------------------------------------------------------

var _place: Vector3 = Vector3.ZERO


func _ground_start(kind: String, speed: float) -> FlightDynamics:
	var f: FlightDynamics = _make(kind)
	var stand: Vector2 = f.standing_attitude()
	f.reset(Basis(Vector3.RIGHT, stand.x), Vector3(0.0, 0.0, -speed))
	f.ground_gap = stand.y
	f.gear = 1.0
	f.flaps = 1.0
	_place = Vector3.ZERO
	return f


func _ground_tick(f: FlightDynamics) -> void:
	f.ground_effect = clampf(1.0 - f.clearance(f.ground_gap) / 10.0, 0.0, 1.0)
	f.step(DT)
	_place += f.displacement


func _ground_line(t: float, f: FlightDynamics) -> String:
	return "t=%5.1f v=%5.1f pitch=%5.1f bank=%5.1f hdg=%6.1f clear=%5.2f vy=%5.1f on_ground=%.2f loads=(%5.0f %5.0f %5.0f) x=%6.1f z=%7.1f touching=%s" % [
		t, f.velocity.length(), _pitch(f), _bank(f), _heading(f), f.clearance(f.ground_gap), f.velocity.y, f.weight_on_ground,
		f.contact_load[0], f.contact_load[1], f.contact_load[2], _place.x, -_place.z, _touching(f)]


func _touching(f: FlightDynamics) -> String:
	var names: PackedStringArray = PackedStringArray()
	for index: int in range(FlightDynamics.CONTACT_COUNT):
		if f.is_touching(index as FlightDynamics.Contact):
			names.append(FlightDynamics.Contact.keys()[index])
	return ",".join(names)


## Rudder that holds the plane heading north down the line x = 0. (Heading is
## in degrees, positive to the right; yaw rate is positive to the left.)
func _feet(f: FlightDynamics) -> float:
	return clampf(-_heading(f) * 0.06 + f.angular_velocity.y * 1.2 - _place.x * 0.01, -1.0, 1.0)


func _stand_test() -> void:
	print("--- STAND: engine off, brakes on")
	var f: FlightDynamics = _ground_start("spitfire", 0.0)
	f.engine_turning = false
	f.engine_output = 0.0
	f.brake = 1.0
	print("  standing attitude %.1f deg at %.2f m" % [rad_to_deg(f.standing_attitude().x), f.standing_attitude().y])
	for i: int in range(60 * 4):
		_ground_tick(f)
		if i % 60 == 0:
			print(_ground_line(float(i) * DT, f), " asleep=%s" % f.asleep)


func _takeoff_test(_pull: float) -> void:
	print("--- TAKE-OFF: full throttle, feet holding the heading, stick forward to lift the tail, eased back at flying speed")
	var f: FlightDynamics = _ground_start("spitfire", 0.0)
	f.brake = 0.0
	f.throttle = 1.0
	var unstick: float = f.stall_speed(1.0) * 1.12
	for i: int in range(60 * 40):
		f.rudder = _feet(f) if f.weight_on_ground > 0.05 else 0.0
		# Tail up to a level-ish attitude once there is air over the elevators,
		# held there until flying speed, then the nose is eased up.
		var wanted_pitch: float = deg_to_rad(13.0)
		if f.indicated_airspeed > unstick:
			wanted_pitch = deg_to_rad(9.0)
		elif f.indicated_airspeed > 12.0:
			wanted_pitch = deg_to_rad(4.0)
		f.elevator = clampf((wanted_pitch - deg_to_rad(_pitch(f))) * 3.0 - f.angular_velocity.x * 1.0, -1.0, 1.0)
		# One stick: on the wheels it is the rudder, off them the ailerons.
		var light: float = clampf(1.0 - f.weight_on_ground * 2.0, 0.0, 1.0)
		f.aileron = _level(f) * light
		f.update_trim(DT)
		_ground_tick(f)
		if i % 60 == 0:
			print(_ground_line(float(i) * DT, f), " rud=%.2f elev=%.2f ail=%.2f ias=%.0f" % [f.rudder, f.elevator, f.aileron, f.indicated_airspeed])
		if f.clearance(f.ground_gap) > 15.0:
			print("  AIRBORNE and climbing at t=%.1f after %.0f m" % [float(i) * DT, -_place.z])
			break


func _brake_test() -> void:
	for push: float in [0.0, -1.0]:
		print("--- BRAKES: rolling at 30 m/s, throttle closed, full brake, stick %.0f" % push)
		var f: FlightDynamics = _ground_start("spitfire", 30.0)
		f.reset(Basis.IDENTITY, Vector3(0.0, 0.0, -30.0))
		f.ground_gap = -(f.contact_points[0].y + FlightDynamics.MAIN_LEG_SAG)
		f.throttle = 0.0
		f.brake = 1.0
		f.elevator = push
		for i: int in range(60 * 14):
			f.rudder = _feet(f)
			_ground_tick(f)
			if i % 60 == 0:
				print(_ground_line(float(i) * DT, f))
			if f.velocity.length() < 0.1 and i > 60:
				print("  STOPPED at t=%.1f after %.0f m" % [float(i) * DT, -_place.z])
				break


func _swerve_test() -> void:
	print("--- SWERVE: rolling tail-down at 22 m/s, full right rudder held")
	var f: FlightDynamics = _ground_start("spitfire", 22.0)
	f.reset(Basis(Vector3.RIGHT, f.standing_attitude().x), Vector3(0.0, 0.0, -22.0))
	f.ground_gap = f.standing_attitude().y
	f.throttle = 0.3
	f.rudder = 1.0
	for i: int in range(60 * 8):
		_ground_tick(f)
		if i % 30 == 0:
			print(_ground_line(float(i) * DT, f))


## Aileron that rolls the wings level. (Bank here is in degrees, positive with
## the right wing down; roll rate is positive rolling left.)
func _level(f: FlightDynamics) -> float:
	return clampf(-_bank(f) * 0.05 + f.angular_velocity.z * 0.3, -1.0, 1.0)


## [param sink] m/s on the approach. With [param hold_off] the pilot flares:
## throttle closed a couple of metres up and the nose held up into the
## three-point attitude until it settles. Without, it is flown straight on.
func _landing_test(sink: float, hold_off: bool = false) -> void:
	print("--- LANDING: wheels down, coming down at %.1f m/s, %s" % [sink, "flared and held off" if hold_off else "flown straight on to the wheels"])
	var f: FlightDynamics = _ground_start("spitfire", 0.0)
	var speed: float = f.stall_speed(1.0) * 1.25
	f.reset(Basis(Vector3.RIGHT, deg_to_rad(3.0)), Vector3(0.0, -sink, -speed))
	f.ground_gap = -(f.contact_points[0].y) + 6.0
	f.throttle = 0.25
	f.settle_trim()
	var touched: bool = false
	var first_impact: float = 0.0
	var highest_bounce: float = 0.0
	for i: int in range(60 * 30):
		if f.weight_on_ground > 0.0 and not touched:
			touched = true
			for index: int in range(FlightDynamics.CONTACT_COUNT):
				first_impact = maxf(first_impact, f.contact_impact[index])
		var room: float = f.clearance(f.ground_gap)
		if touched:
			highest_bounce = maxf(highest_bounce, room)
			f.throttle = 0.0
			f.brake = 1.0 if f.velocity.length() < 25.0 else 0.0
		if hold_off:
			if room < 2.5 or touched:
				f.throttle = 0.0
				f.elevator = clampf((deg_to_rad(11.5) - deg_to_rad(_pitch(f))) * 3.0 - f.angular_velocity.x * 1.0, -1.0, 1.0)
		elif touched:
			f.elevator = -0.15
		f.rudder = _feet(f) if f.weight_on_ground > 0.05 else 0.0
		f.aileron = _level(f)
		f.update_trim(DT)
		_ground_tick(f)
		if i % 30 == 0 and i < 60 * 7 or i % 120 == 0:
			print(_ground_line(float(i) * DT, f), " ias=%.0f" % f.indicated_airspeed)
		if touched and f.velocity.length() < 0.1:
			print("  STOPPED at t=%.1f after %.0f m; first touch at %.1f m/s, highest bounce %.2f m, impacts %s" % [float(i) * DT, -_place.z, first_impact, highest_bounce, str(f.contact_impact)])
			break
