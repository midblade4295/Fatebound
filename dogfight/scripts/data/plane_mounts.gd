class_name PlaneMounts
extends RefCounted
## The places on an aeroplane where something can be fitted: four wing gun
## stations, propeller, engine, wingtips, armour and undercarriage. Pure
## static facts, no state. Every mount is open on every plane; what a pilot
## can fit is whatever they have bought.

## Number of wing gun stations. They are the first mounts, in this order:
## left inner, right inner, left outer, right outer.
const GUN_STATION_COUNT: int = 4
## Every place on the aeroplane something can be fitted.
const MOUNT_COUNT: int = 9
## What kind of item each mount takes.
const MOUNT_SLOTS: Array[ComponentCard.Slot] = [
	ComponentCard.Slot.GUN, ComponentCard.Slot.GUN, ComponentCard.Slot.GUN, ComponentCard.Slot.GUN,
	ComponentCard.Slot.PROPELLER, ComponentCard.Slot.ENGINE, ComponentCard.Slot.WINGTIPS,
	ComponentCard.Slot.ARMOUR, ComponentCard.Slot.UNDERCARRIAGE,
]
const MOUNT_NAMES: Array[String] = [
	"Left inner gun", "Right inner gun", "Left outer gun", "Right outer gun",
	"Propeller", "Engine", "Wingtips", "Armour", "Undercarriage",
]
## Short labels for the loadout tiles.
const MOUNT_LABELS: Array[String] = ["GUN L1", "GUN R1", "GUN L2", "GUN R2", "PROP", "ENGINE", "TIPS", "ARMOUR", "GEAR"]

## True when [param card] is the kind of item [param mount] takes.
static func mount_accepts(mount: int, card: ComponentCard) -> bool:
	return card != null and mount >= 0 and mount < MOUNT_COUNT and card.slot == MOUNT_SLOTS[mount]


static func is_gun_station(mount: int) -> bool:
	return mount >= 0 and mount < GUN_STATION_COUNT


## The first mount that takes items of [param slot] (the only one, except for guns).
static func mount_for_slot(slot: ComponentCard.Slot) -> int:
	return MOUNT_SLOTS.find(slot)


static func mount_name(mount: int) -> String:
	return MOUNT_NAMES[clampi(mount, 0, MOUNT_COUNT - 1)]


static func mount_label(mount: int) -> String:
	return MOUNT_LABELS[clampi(mount, 0, MOUNT_COUNT - 1)]
