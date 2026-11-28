extends Node
## Headless test that each aeroplane is the size and shape of the real one,
## and stands and turns on its wheels like it.
##
##   godot --headless --fixed-fps 60 --path . res://tests/TestAirframes.tscn
##
## Each plane is built from its own model as the game builds it, and what the
## game measured from the model (span, wheel track, how high the centre of
## gravity is above the wheels, propeller, the angle it sits at) is compared
## with the published figures. Then it is driven about on its wheels, with the
## pilot's hands and feet the game gives every plane: swerved with the stick
## hard over at speeds from a taxi to the take-off run, and braked hard from
## a landing run. No wingtip or propeller may touch the ground.
## Prints AIRFRAMES_OK on success.

const DT: float = 1.0 / 60.0
## Published figures, metres: span, undercarriage track, propeller diameter.
const REAL: Dictionary[StringName, Vector3] = {
	&"hurricane": Vector3(12.19, 2.36, 3.43),
	&"spitfire": Vector3(11.23, 1.73, 3.27),
	&"mustang": Vector3(11.28, 3.61, 3.40),
}
const SWERVE_SPEEDS: Array[float] = [6.0, 10.0, 15.0, 22.0, 30.0]

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0
var _started: bool = false


func _ready() -> void:
	Profile.persistence_enabled = false
	Profile.reset_to_new_profile(false)


func _process(_delta: float) -> void:
	if _started:
		return
	_started = true
	for id: StringName in REAL:
		_test_plane(id)
	if _failures.is_empty():
		print("AIRFRAMES_OK (%d checks)" % _checks)
	else:
		for failure: String in _failures:
			print("FAIL: ", failure)
		print("AIRFRAMES_FAILED")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _test_plane(id: StringName) -> void:
	var data: PlaneData = GameCatalog.find_plane(id)
	var plane: PlaneActor = (load("res://scenes/actors/PlaneActor.tscn") as PackedScene).instantiate() as PlaneActor
	plane.setup(data, data.build_stock_stats(), Teams.Id.TEAM_BLUE, "Test")
	add_child(plane)
	plane.set_physics_process(false)
	var flight: FlightDynamics = plane.flight
	var real: Vector3 = REAL[id]

	# --- The size of it ---
	_check(data.model != null, "%s has a model of its own" % id)
	_check(is_equal_approx(plane.visual.model_scale(), 1.0), "%s is shown at its real size" % id)
	_check(is_equal_approx(data.base_span, real.x), "%s flies on its real span (%.2f m)" % [id, data.base_span])
	var span: float = absf(plane.visual.wingtip_contact().x) * 2.0
	_check(absf(span - real.x) < 0.04, "%s's model spans %.2f m (really %.2f)" % [id, span, real.x])
	var wheel: Vector3 = flight.contact_points[FlightDynamics.Contact.LEFT_WHEEL] + Vector3(0.0, FlightDynamics.MAIN_LEG_SAG, 0.0)
	var track: float = absf(wheel.x) * 2.0
	_check(absf(track - real.y) < 0.04, "%s's wheels are %.2f m apart (really %.2f)" % [id, track, real.y])
	var propeller: float = plane.visual.prop_radius() * 2.0
	_check(absf(propeller - real.z) < 0.04, "%s's propeller is %.2f m across (really %.2f)" % [id, propeller, real.z])
	_check(plane.visual.propeller_piece_name() == (&"PropellerMesh4" if id == &"mustang" else &"PropellerMesh"),
			"%s leaves the factory with %d blades" % [id, data.prop_blades])
	# --- How it stands ---
	var height: float = -wheel.y
	_check(height > 1.6 and height < 2.0, "%s's centre of gravity is %.2f m above its wheels" % [id, height])
	_check(-wheel.z > 0.5 and -wheel.z < 0.9, "%s's wheels are %.2f m ahead of its centre of gravity" % [id, -wheel.z])
	var sits: float = rad_to_deg(flight.standing_attitude().x)
	_check(sits > 10.5 and sits < 13.5, "%s sits %.1f degrees nose-up on its tail wheel" % [id, sits])
	var prop_tip: Vector3 = flight.contact_points[FlightDynamics.Contact.NOSE]
	var clearance: float = prop_tip.y - wheel.y
	_check(clearance > 0.15 and clearance < 0.45, "%s's propeller clears the ground by %.2f m with the tail up" % [id, clearance])
	var tip: Vector3 = flight.contact_points[FlightDynamics.Contact.LEFT_TIP]
	var tip_bank: float = rad_to_deg(atan2(tip.y - wheel.y, absf(tip.x) - absf(wheel.x)))
	_check(tip_bank > 17.0 and tip_bank < 26.0, "%s has to lean %.1f degrees to put a wingtip on the ground" % [id, tip_bank])
	var tips_at: float = absf(wheel.x) / height
	_check(tips_at > 0.45, "%s's inside wheel lifts at %.2f g sideways, not before" % [id, tips_at])
	# --- Which way the wheels fold ---
	plane.visual.set_gear(0.5)
	var left_leg: Node3D = plane.visual.find_child("GearL", true, false) as Node3D
	var swung: float = (left_leg.basis * Vector3.DOWN).x if left_leg != null else 0.0
	_check(left_leg != null and (swung > 0.2 if data.gear_folds_inward else swung < -0.2),
			"%s's wheels fold %s" % [id, "inward" if data.gear_folds_inward else "outward"])
	_check(data.gear_folds_inward == (id != &"spitfire"), "only the Spitfire's fold outward")
	plane.visual.set_gear(1.0)

	# --- Standing still ---
	_stand(flight, 0.0, true)
	flight.brake = 1.0
	flight.throttle = 1.0
	flight.elevator = 1.0
	var run_up: Vector2 = _drive(flight, 0.0, 5.0)
	_check(run_up.x < 4.0 and run_up.y < 0.5, "%s holds a full-power run-up on its brakes (leans %.1f degrees)" % [id, run_up.x])
	# --- Swerving ---
	for speed: float in SWERVE_SPEEDS:
		for stick: float in [-1.0, 1.0]:
			_stand(flight, speed, true)
			flight.throttle = 0.3
			var swerve: Vector2 = _drive(flight, stick, 6.0)
			_check(swerve.y < 0.5, "%s keeps its wingtips and propeller off the ground swerved hard %s at %.0f mph" % [id, "right" if stick > 0.0 else "left", speed * PlaneActor.MPH])
			_check(swerve.x < 8.0, "leaning no more than a few degrees (%.1f)" % swerve.x)
			_check(absf(_heading(flight)) > 10.0, "and it does turn (%.0f degrees in six seconds)" % absf(_heading(flight)))
	# --- Braking ---
	_stand(flight, 35.0, false)
	flight.brake = 1.0
	var stop: Vector2 = _drive(flight, 0.0, 30.0, true)
	_check(stop.y < 0.5, "%s can be braked hard from a landing run, tail up, without going on its nose" % id)
	_check(flight.velocity.length() < 0.5, "and stops")
	plane.queue_free()


## Puts the plane on its wheels rolling at [param speed], on all three or
## with the tail up, controls central.
func _stand(flight: FlightDynamics, speed: float, tail_down: bool) -> void:
	var stand: Vector2 = flight.standing_attitude()
	if tail_down:
		flight.reset(Basis(Vector3.RIGHT, stand.x), Vector3(0.0, 0.0, -speed))
		flight.ground_gap = stand.y
	else:
		flight.reset(Basis.IDENTITY, Vector3(0.0, 0.0, -speed))
		flight.ground_gap = -(flight.contact_points[FlightDynamics.Contact.LEFT_WHEEL].y + FlightDynamics.MAIN_LEG_SAG)
	flight.contact_enabled.fill(1)
	flight.gear = 1.0
	flight.flaps = 1.0
	flight.brake = 0.0
	flight.throttle = 0.0
	flight.aileron = 0.0
	flight.elevator = 0.0
	flight.rudder = 0.0


## Runs the plane on the ground for [param seconds] with the stick held
## [param stick] to one side (or, with [param hold_heading], the feet keeping
## it straight). Returns x = the most it leaned (degrees), y = 1 if a wingtip,
## the propeller or the belly touched.
func _drive(flight: FlightDynamics, stick: float, seconds: float, hold_heading: bool = false) -> Vector2:
	var leaned: float = 0.0
	var touched: float = 0.0
	for tick: int in range(int(seconds / DT)):
		var feet: float = stick
		if hold_heading:
			feet = clampf(-deg_to_rad(_heading(flight)) * 3.5 + flight.angular_velocity.y * 1.2, -1.0, 1.0)
		# What PlaneActor does with the stick while a wheel is on the ground.
		flight.rudder = move_toward(flight.rudder, FlightPilot.feet_within_the_wheels(flight, feet), PlaneActor.CONTROL_SLEW * DT)
		flight.aileron = move_toward(flight.aileron, FlightPilot.hold_wings_level(flight), PlaneActor.CONTROL_SLEW * DT)
		flight.ground_effect = clampf(1.0 - flight.clearance(flight.ground_gap) / 10.0, 0.0, 1.0)
		flight.step(DT)
		leaned = maxf(leaned, absf(rad_to_deg(atan2(-flight.basis.x.y, flight.basis.y.y))))
		for contact: FlightDynamics.Contact in [FlightDynamics.Contact.NOSE, FlightDynamics.Contact.LEFT_TIP, FlightDynamics.Contact.RIGHT_TIP, FlightDynamics.Contact.BELLY]:
			if flight.is_touching(contact):
				touched = 1.0
		if hold_heading and flight.velocity.length() < 0.2:
			break
	return Vector2(leaned, touched)


## Degrees the nose has swung to the right of where it started.
func _heading(flight: FlightDynamics) -> float:
	return rad_to_deg(atan2(-flight.basis.z.x, flight.basis.z.z))


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
