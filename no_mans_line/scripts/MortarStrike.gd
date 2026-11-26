class_name MortarStrike
extends Node2D
## MortarStrike.gd -- a delayed mortar shell.
## Shows a flare on the target, drops the shell after `delay`, deals area damage
## through GameManager.apply_explosion() and leaves a crater behind.

@export var delay := 1.6
@export var radius := 150.0
@export var max_damage := 70.0
@export var min_damage := 25.0

var game: GameManager
var source_team := GameManager.TEAM_BLUE

@onready var target_marker: Node2D = $TargetMarker
@onready var ring: Line2D = $TargetMarker/Ring
@onready var shell: Sprite2D = $Shell
@onready var blast: Polygon2D = $Blast
@onready var debris: GPUParticles2D = $Debris
@onready var smoke: GPUParticles2D = $Smoke
@onready var fuse_timer: Timer = $FuseTimer


func setup(p_game: GameManager, p_team: int) -> void:
	game = p_game
	source_team = p_team


func _ready() -> void:
	# Flattened ring on the ground showing the blast radius.
	var points := PackedVector2Array()
	for i in 33:
		var angle := TAU * i / 32.0
		points.append(Vector2(cos(angle) * radius, sin(angle) * radius * 0.22))
	ring.points = points
	var pulse := target_marker.create_tween().set_loops()
	pulse.tween_property(target_marker, "modulate:a", 0.45, 0.2)
	pulse.tween_property(target_marker, "modulate:a", 1.0, 0.2)

	# The shell arcs in from the firing side's rear.
	var dir := GameManager.advance_dir(source_team)
	shell.position = Vector2(-dir * 320.0, -1100.0)
	# The shell art points up; turn its nose along the line of fall.
	shell.rotation = Vector2(dir * 320.0, 1100.0).angle() + PI / 2.0
	var fall := create_tween()
	fall.tween_property(shell, "position", Vector2.ZERO, delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	blast.visible = false
	fuse_timer.start(delay)


func _on_fuse_timer_timeout() -> void:
	target_marker.visible = false
	shell.visible = false

	game.apply_explosion(global_position, radius, max_damage, min_damage)
	game.add_crater(global_position)
	game.shake_camera(10.0)

	debris.emitting = true
	smoke.emitting = true
	blast.visible = true
	blast.scale = Vector2(0.3, 0.3)
	var tween := create_tween()
	tween.tween_property(blast, "scale", Vector2(1.5, 1.5), 0.18)
	tween.parallel().tween_property(blast, "modulate:a", 0.0, 0.3)
	tween.tween_interval(2.2)
	tween.tween_callback(queue_free)
