class_name Bunker
extends Area2D
## Bunker.gd -- a Command Bunker. Spawns the team's troops, defends itself with
## a machine gun and ends the match when it is destroyed.
##
## Collision setup: layer 4 (sectors), mask 0. The GunRange child Area2D gets
## its mask (the enemy unit layer) from code because it depends on `team`.

signal health_changed(team: int, health: float, max_health: float)
signal destroyed(team: int)

@export_enum("Blue:0", "Red:1") var team: int = 0
@export var max_health := 1000.0
@export_group("Art")
@export var intact_texture: Texture2D
@export var damaged_texture: Texture2D
## The bunker switches to damaged_texture at or below this health fraction.
@export_range(0.0, 1.0, 0.05) var damaged_below := 0.4
@export_group("Machine Gun")
@export var gun_damage := 7.0
@export var gun_interval := 0.3
@export var gun_range := 340.0
@export_range(0.0, 1.0, 0.05) var gun_accuracy := 0.85
## Half of the bunker's footprint, used for melee reach and blast checks.
@export var half_width := 95.0

var game: GameManager
var health := 0.0
## Seconds the machine gun stays silent after a shell lands on the bunker.
var _suppressed_time := 0.0

@onready var visual: Node2D = $Visual
@onready var sprite: Sprite2D = $Visual/Sprite
@onready var mortar_prop: Sprite2D = $Visual/MortarProp
@onready var flag_cloth: Polygon2D = $Visual/Flag/Cloth
@onready var muzzle: Marker2D = $Visual/Muzzle
@onready var muzzle_flash: Sprite2D = $Visual/Muzzle/MuzzleFlash
@onready var spawn_point: Marker2D = $Visual/SpawnPoint
@onready var gun_area: Area2D = $GunRange
@onready var gun_shape: CollisionShape2D = $GunRange/CollisionShape2D
@onready var gun_timer: Timer = $GunTimer
@onready var health_fill: ColorRect = $HealthBar/Fill
@onready var wreck_smoke: GPUParticles2D = $WreckSmoke


func _ready() -> void:
	health = max_health
	sprite.texture = intact_texture
	# The art is drawn facing right; Red's bunker is mirrored. Mirroring the
	# parent also mirrors the Muzzle and SpawnPoint markers.
	visual.scale.x = GameManager.advance_dir(team)
	var blue := team == GameManager.TEAM_BLUE
	flag_cloth.color = Color(0.3, 0.55, 0.85) if blue else Color(0.82, 0.25, 0.2)
	health_fill.color = Color(0.45, 0.72, 0.95) if blue else Color(0.95, 0.36, 0.26)

	var circle := CircleShape2D.new()
	circle.radius = gun_range
	gun_shape.shape = circle
	gun_area.collision_layer = 0
	gun_area.collision_mask = 1 << GameManager.enemy_of(team)
	gun_timer.wait_time = gun_interval


## Called by GameManager._ready().
func setup(p_game: GameManager) -> void:
	game = p_game
	health_changed.emit(team, health, max_health)


func is_alive() -> bool:
	return health > 0.0


func get_health_fraction() -> float:
	return clampf(health / max_health, 0.0, 1.0)


func get_spawn_position() -> Vector2:
	return spawn_point.global_position


## Same signature as Unit.take_damage so attackers can treat both alike.
func take_damage(amount: float, kind: Unit.DamageKind, _attacker: Unit) -> void:
	if not is_alive() or kind == Unit.DamageKind.GAS:
		return  # Concrete does not breathe.
	health = maxf(0.0, health - amount)
	health_fill.size.x = 150.0 * get_health_fraction()
	health_changed.emit(team, health, max_health)

	if get_health_fraction() <= damaged_below and sprite.texture != damaged_texture:
		sprite.texture = damaged_texture
		wreck_smoke.emitting = true

	visual.modulate = Color(1.5, 1.3, 1.2)
	var tween := create_tween()
	tween.tween_property(visual, "modulate", Color.WHITE, 0.12)

	if health <= 0.0:
		_destroy()


func _destroy() -> void:
	gun_timer.stop()
	muzzle_flash.visible = false
	sprite.texture = damaged_texture
	wreck_smoke.emitting = true
	var tween := create_tween()
	tween.tween_property(visual, "modulate", Color(0.45, 0.4, 0.37), 0.6)
	destroyed.emit(team)


## A mortar hit keeps the gun crew's heads down for `seconds`.
func suppress(seconds: float) -> void:
	_suppressed_time = maxf(_suppressed_time, seconds)


func is_suppressed() -> bool:
	return _suppressed_time > 0.0


## Machine gun: one burst at the nearest enemy inside GunRange.
func _on_gun_timer_timeout() -> void:
	if game == null or game.match_over or not is_alive():
		return
	if _suppressed_time > 0.0:
		_suppressed_time -= gun_timer.wait_time
		return
	var victim: Unit = null
	var best_distance := INF
	for body in gun_area.get_overlapping_bodies():
		var unit := body as Unit
		if unit == null or not unit.is_alive():
			continue
		var distance := absf(unit.global_position.x - global_position.x)
		if distance < best_distance:
			victim = unit
			best_distance = distance
	if victim == null:
		return

	var aim := victim.global_position + Vector2(0.0, -45.0)
	var hit := randf() <= gun_accuracy
	if not hit:
		aim += Vector2(randf_range(-50.0, 50.0), randf_range(-60.0, 10.0))
	game.spawn_tracer(muzzle.global_position, aim)
	muzzle_flash.visible = true
	muzzle_flash.rotation = randf_range(-0.15, 0.15)
	var tween := create_tween()
	tween.tween_interval(0.06)
	tween.tween_callback(muzzle_flash.hide)
	if hit:
		victim.take_damage(gun_damage, Unit.DamageKind.BULLET, null)


## Small kick on the mortar beside the bunker when this team fires a shell.
func play_mortar_recoil() -> void:
	var rest := Vector2(0.6, 0.6)
	mortar_prop.scale = rest * Vector2(1.0, 0.82)
	var tween := create_tween()
	tween.tween_property(mortar_prop, "scale", rest, 0.25)
