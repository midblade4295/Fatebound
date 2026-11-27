class_name PlaneStats
extends RefCounted
## The final, fully-resolved numbers a PlaneActor flies with.
## Built by PlaneData.build_stats() from: plane base stats x Commander Level
## bonuses x equipped ComponentCard bonuses. PlaneActor never reads cards directly.

# --- Airframe ---
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

# --- Guns ---
## Rounds per second, all guns combined.
var fire_rate: float = 10.0
var bullet_damage: float = 150.0
var bullet_speed: float = 420.0
var gun_range: float = 480.0
var gun_spread_deg: float = 0.6
## Incendiary: damage per second applied after a hit, and for how long.
var burn_dps: float = 0.0
var burn_duration: float = 0.0

# --- Tactical gadget (ComponentCard.GadgetType as int; 0 = none) ---
var gadget_type: int = 0
var gadget_cooldown: float = 0.0
var gadget_duration: float = 0.0
## Meaning depends on the gadget: nitro = +speed fraction, repair = heal fraction.
var gadget_power: float = 0.0
var gadget_name: String = ""


func duplicate_stats() -> PlaneStats:
	var copy: PlaneStats = PlaneStats.new()
	copy.max_hp = max_hp
	copy.top_speed = top_speed
	copy.acceleration = acceleration
	copy.climb_rate = climb_rate
	copy.turn_rate = turn_rate
	copy.pitch_rate = pitch_rate
	copy.roll_rate = roll_rate
	copy.fire_rate = fire_rate
	copy.bullet_damage = bullet_damage
	copy.bullet_speed = bullet_speed
	copy.gun_range = gun_range
	copy.gun_spread_deg = gun_spread_deg
	copy.burn_dps = burn_dps
	copy.burn_duration = burn_duration
	copy.gadget_type = gadget_type
	copy.gadget_cooldown = gadget_cooldown
	copy.gadget_duration = gadget_duration
	copy.gadget_power = gadget_power
	copy.gadget_name = gadget_name
	return copy
