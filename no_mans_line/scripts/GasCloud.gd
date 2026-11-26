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

@onready var clouds: Node2D = $Clouds
@onready var puffs: GPUParticles2D = $Puffs
@onready var tick_timer: Timer = $TickTimer
@onready var life_timer: Timer = $LifeTimer


func _ready() -> void:
	add_to_group("gas_clouds")
	# Billow in: the three cloud sprites fade up and swell slightly.
	clouds.modulate.a = 0.0
	clouds.scale = Vector2(0.7, 0.7)
	var tween := create_tween()
	tween.tween_property(clouds, "modulate:a", 0.6, 0.8)
	tween.parallel().tween_property(clouds, "scale", Vector2.ONE, 1.2)
	tick_timer.start(tick_interval)
	life_timer.start(lifetime)


## False once the cloud has stopped hurting and is only fading out.
func is_active() -> bool:
	return not life_timer.is_stopped()


func _on_tick_timer_timeout() -> void:
	for body in get_overlapping_bodies():
		var unit := body as Unit
		if unit != null and unit.is_alive():
			# Choking soldiers cannot fight: they stay pinned until just after
			# they leave the cloud or it clears.
			unit.pin(tick_interval + 0.4)
			unit.take_damage(damage_per_tick, Unit.DamageKind.GAS, null)


func _on_life_timer_timeout() -> void:
	tick_timer.stop()
	set_deferred("monitoring", false)
	puffs.emitting = false
	var tween := create_tween()
	tween.tween_property(clouds, "modulate:a", 0.0, 1.5)
	tween.tween_interval(1.5)
	tween.tween_callback(queue_free)
