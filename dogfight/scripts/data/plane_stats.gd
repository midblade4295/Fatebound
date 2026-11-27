class_name PlaneStats
extends RefCounted
## The final, fully-resolved numbers a PlaneActor flies with, and the fittings
## they came from. Built by PlaneData.build_stats() from: the plane's base
## stats x Commander Level bonuses x what is fitted to each mount.
## PlaneActor reads the numbers; PlaneVisual reads the fittings to decide which
## pieces of the model to show.

# --- Airframe ---
## Toughness: how much punishment the parts take (see PlaneActor.PART_STRENGTH).
var max_hp: float = 1000.0
## Level-flight top speed in m/s.
var top_speed: float = 85.0
## How fast the engine pulls speed back toward top speed (1/s).
var acceleration: float = 0.6
## 1.0 = baseline. Higher keeps more speed in a climb.
var climb_rate: float = 1.0
## Yaw rate at full stick, radians per second.
var turn_rate: float = 1.0
## Pitch rate at full stick, radians per second.
var pitch_rate: float = 0.9
## 1.0 = baseline. Scales stick response and shortens the evade-roll cooldown.
var roll_rate: float = 1.0
## Speed (m/s) below which the clean wing no longer carries the plane. Heavier
## fittings raise it, more wing lowers it; a faster engine does not change it.
var stall_speed: float = 51.0
## Weight relative to the bare aeroplane (1.0 = nothing fitted).
var weight: float = 1.0
## Wing lift relative to the standard wing.
var lift: float = 1.0
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


## Ids of the fittings in mount order ("" for an empty mount): what a remote
## peer needs to rebuild this stat block and show the same aeroplane.
func fitting_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for card: ComponentCard in fittings:
		ids.append(String(card.id) if card != null else "")
	return ids
