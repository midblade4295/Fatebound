class_name GasCloud
extends Area2D
## GasCloud.gd -- lingering mustard gas. Every tick it hurts every soldier
## standing in the cloud (both teams: do not charge into your own gas).
## Gas ignores trench cover.
##
## Collision setup: layer 5 (hazards), mask 1 + 2 (blue_units, red_units).

@export var lifetime := 6.0
@export var tick_interval := 0.5
@export var damage_per_tick := 4.0

var source_team := GameManager.TEAM_BLUE

@onready var haze: Polygon2D = $Haze
@onready var puffs: GPUParticles2D = $Puffs
@onready var tick_timer: Timer = $TickTimer
@onready var life_timer: Timer = $LifeTimer


func _ready() -> void:
	add_to_group("gas_clouds")
	haze.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(haze, "modulate:a", 1.0, 0.8)
	tick_timer.start(tick_interval)
	life_timer.start(lifetime)


## False once the cloud has stopped hurting and is only fading out.
func is_active() -> bool:
	return not life_timer.is_stopped()


func _on_tick_timer_timeout() -> void:
	for body in get_overlapping_bodies():
		var unit := body as Unit
		if unit != null and unit.is_alive():
			unit.take_damage(damage_per_tick, Unit.DamageKind.GAS, null)


func _on_life_timer_timeout() -> void:
	tick_timer.stop()
	set_deferred("monitoring", false)
	puffs.emitting = false
	var tween := create_tween()
	tween.tween_property(haze, "modulate:a", 0.0, 1.5)
	tween.tween_interval(1.5)
	tween.tween_callback(queue_free)
