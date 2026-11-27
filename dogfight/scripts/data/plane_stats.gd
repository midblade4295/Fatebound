class_name PlaneStats
extends RefCounted
## The final, fully-resolved numbers a PlaneActor flies with, and the fittings
## they came from. Built by PlaneData.build_stats() from: the plane's base
## stats x Commander Level bonuses x what is fitted to each mount.
## PlaneActor reads the numbers; PlaneVisual reads the fittings to decide which
## pieces of the model to show.


# --- Airframe: the real figures the flight model is built from ---
## Toughness: how much punishment the parts take (see PlaneActor.PART_STRENGTH).
var max_hp: float = 1000.0
## All-up weight in kilograms, with everything that is fitted.
var mass: float = 3000.0
## Wing area (m^2) and span (m).
var wing_area: float = 22.5
var wing_span: float = 11.2
## Full engine power at the propeller shaft, watts.
var engine_power: float = 1000000.0
## Drag coefficient of the clean aeroplane at zero lift.
var drag: float = 0.021
## The most lift coefficient the wing makes before it stalls.
var max_lift: float = 1.5
## The propeller's bite at low speed, relative to the standard one.
var static_thrust: float = 1.0
## Aileron power relative to the standard wing: how fast it rolls.
var roll_power: float = 1.0
## Height (m) up to which the supercharger holds its boost, and the share of
## sea-level power the engine still gives there.
var critical_altitude: float = 3500.0
var altitude_power: float = 1.0

# --- What that adds up to: measured from the flight model by PlaneData ---
## Level-flight top speed at full power at sea level, m/s, and the true
## airspeed it reaches at its critical altitude, where it is fastest.
var top_speed: float = 130.0
var top_speed_high: float = 140.0
## Speed (m/s) below which the clean wing no longer carries the plane, and the
## same with the flaps down.
var stall_speed: float = 38.0
var landing_stall_speed: float = 36.0
## Best rate of climb (m/s) and the airspeed that gives it.
var climb_rate: float = 15.0
var climb_speed: float = 70.0

# --- Bookkeeping while the fittings are added up ---
## Weight relative to the bare aeroplane (1.0 = nothing fitted).
var weight: float = 1.0
## Multipliers the fittings ask for: top speed, engine power and wing span.
var speed_factor: float = 1.0
var power_factor: float = 1.0
var wing_factor: float = 1.0
## How fast a holed tank leaks, relative to an unprotected one.
var fuel_leak: float = 1.0
## How hard a landing the undercarriage stands, relative to the standard legs.
var gear_strength: float = 1.0

# --- Fittings ---
## What is fitted to each mount (CommanderProgression.MOUNT_*), null where a
## mount is empty, and the Mark of each.
var fittings: Array[ComponentCard] = []
var fitting_marks: Array[int] = []

# --- Guns: summaries of the fitted guns, for the HUD and the bots' aiming ---
## Rounds per second from all guns together.
var fire_rate: float = 0.0
## Damage of an average round.
var bullet_damage: float = 0.0
## Muzzle velocity of an average round, m/s.
var bullet_speed: float = 420.0
## Reach of the longest-ranged gun, metres.
var gun_range: float = 0.0


## The gun in a gun station (0 = left inner, 1 = right inner, 2 = left outer,
## 3 = right outer), or null if nothing is fitted there.
func gun_at(station: int) -> ComponentCard:
	if station < 0 or station >= CommanderProgression.GUN_STATION_COUNT or station >= fittings.size():
		return null
	return fittings[station]


func gun_mark(station: int) -> int:
	return fitting_marks[station] if station >= 0 and station < fitting_marks.size() else 1


func gun_count() -> int:
	var count: int = 0
	for station: int in range(CommanderProgression.GUN_STATION_COUNT):
		if gun_at(station) != null:
			count += 1
	return count


## The item fitted in the (single) mount for [param slot], or null.
func fitting_in(slot: ComponentCard.Slot) -> ComponentCard:
	var mount: int = CommanderProgression.mount_for_slot(slot)
	return fittings[mount] if mount >= 0 and mount < fittings.size() else null


## A flight model set up as this aeroplane.
func make_flight() -> FlightDynamics:
	var flight: FlightDynamics = FlightDynamics.new()
	flight.configure(mass, wing_area, wing_span, engine_power, drag, max_lift, static_thrust, roll_power, critical_altitude, altitude_power)
	return flight


## Indicated speed (m/s) at which to ease the stick back on the take-off
## run: a safe margin over the stalling speed with flaps and wheels down.
func takeoff_speed() -> float:
	return landing_stall_speed * 1.12


## Power for every kilogram, watts: the best single guide to climb and
## acceleration.
func power_loading() -> float:
	return engine_power / maxf(mass, 1.0)


## Weight on every square metre of wing, kg: the best single guide to turning.
func wing_loading() -> float:
	return mass / maxf(wing_area, 0.1)


## Ids of the fittings in mount order ("" for an empty mount): what a remote
## peer needs to rebuild this stat block and show the same aeroplane.
func fitting_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for card: ComponentCard in fittings:
		ids.append(String(card.id) if card != null else "")
	return ids
