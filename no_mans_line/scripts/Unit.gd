class_name Unit
extends CharacterBody2D
## Unit.gd -- one soldier (Rifleman or Trench Raider).
##
## State machine:
##   MARCHING  -> walking to a reserved trench slot (or the rally point)
##   IN_COVER  -> stationed in a trench slot, taking reduced damage, firing
##   CHARGING  -> over the top after a Whistle Charge, sprinting at an objective
##   ATTACKING -> stopped (rifle) or chasing (melee) to fight a specific target
##   DEAD      -> playing the death tween, about to be freed
##
## Every state has a matching animation on the AnimatedSprite2D (see
## _refresh_animation): "walk", "cover", "aim", plus "attack" for the shot or
## swing itself. The art faces right, so Red is mirrored with flip_h.
##
## Call setup() BEFORE add_child() so _ready() knows the team and type.

signal died(unit: Unit)

enum State { MARCHING, IN_COVER, CHARGING, ATTACKING, DEAD }
enum Type { RIFLEMAN, RAIDER }
enum DamageKind { BULLET, MELEE, EXPLOSION, GAS }

## Per-type balance values.
##   cover_range  : how far the unit looks for targets while IN_COVER
##   aggro_range  : how far it notices targets while out in the open
##   attack_reach : how close it must be to actually hit
##   open_ground_damage_mult : incoming damage multiplier outside trench/crater
##   trench_fight_bonus      : melee damage multiplier when fighting in a trench
const STATS := {
	Type.RIFLEMAN: {
		"max_health": 60.0,
		"march_speed": 95.0,
		"charge_speed": 165.0,
		"damage": 8.0,
		"attack_interval": 1.25,
		"cover_range": 980.0,
		"aggro_range": 300.0,
		"attack_reach": 320.0,
		"bunker_reach": 260.0,
		"melee": false,
		"open_ground_damage_mult": 1.0,
		"trench_fight_bonus": 1.0,
		"bunker_damage_mult": 1.0,
	},
	Type.RAIDER: {
		"max_health": 90.0,
		"march_speed": 150.0,
		"charge_speed": 235.0,
		"damage": 22.0,
		"attack_interval": 0.55,
		"cover_range": 175.0,
		"aggro_range": 230.0,
		"attack_reach": 44.0,
		"bunker_reach": 120.0,
		"melee": true,
		"open_ground_damage_mult": 1.5,
		"trench_fight_bonus": 1.6,
		"bunker_damage_mult": 0.5,
	},
}

const CRATER_COVER_MULTIPLIER := 0.65
const ARRIVE_DISTANCE := 6.0
const THINK_INTERVAL := 0.2

const ANIM_WALK := &"walk"
const ANIM_COVER := &"cover"
const ANIM_AIM := &"aim"
const ANIM_ATTACK := &"attack"

const RECOLOR_SHADER := preload("res://shaders/team_recolor.gdshader")

## Art per team and unit type.
##   frames  : SpriteFrames with the animations walk / cover / aim / attack
##   scale   : sheet pixels -> world pixels
##   muzzle  : rifle tip in sheet pixels, measured from the feet, facing right
##   recolor : animations that reuse Blue frames and need the Red repaint
const LOOKS := {
	GameManager.TEAM_BLUE: {
		Type.RIFLEMAN: {
			"frames": preload("res://assets/sprites/blue_rifleman.tres"),
			"scale": 0.5,
			"muzzle": Vector2(117, -151),
			"recolor": [],
		},
		Type.RAIDER: {
			"frames": preload("res://assets/sprites/blue_raider.tres"),
			"scale": 0.52,
			"muzzle": Vector2(100, -118),
			"recolor": [],
		},
	},
	GameManager.TEAM_RED: {
		Type.RIFLEMAN: {
			"frames": preload("res://assets/sprites/red_rifleman.tres"),
			"scale": 0.5,
			"muzzle": Vector2(126, -154),
			# The sheet has no Red walk cycle: red_rifleman.tres reuses Blue's.
			"recolor": [ANIM_WALK],
		},
		Type.RAIDER: {
			# The sheet has no Red raiders at all: reuse Blue's, repainted.
			"frames": preload("res://assets/sprites/blue_raider.tres"),
			"scale": 0.52,
			"muzzle": Vector2(100, -118),
			"recolor": [ANIM_WALK, ANIM_COVER, ANIM_AIM, ANIM_ATTACK],
		},
	},
}

const BAR_COLORS: Array[Color] = [Color(0.45, 0.72, 0.95), Color(0.95, 0.36, 0.26)]

# ----------------------------------------------------------------------------
# Public state
# ----------------------------------------------------------------------------
var game: GameManager
var team := GameManager.TEAM_BLUE
var unit_type: Type = Type.RIFLEMAN
## Assigning a new state immediately switches to its animation.
var state: State = State.MARCHING:
	set(value):
		state = value
		if is_node_ready():
			_refresh_animation()
var health := 1.0

## Trench where this unit holds (or has reserved) a slot.
var trench: Trench = null
var slot_index := -1
## Trench Area2D the unit is physically standing in (set by Trench.gd).
var zone_trench: Trench = null
## Number of crater cover zones the unit is standing in (set by Crater.gd).
var crater_count := 0
## Charge objective: a Trench or a Bunker.
var objective: Node2D = null
## Current attack target: a Unit or a Bunker.
var target: Node2D = null

# Stats copied from STATS in _ready().
var max_health := 1.0
var march_speed := 0.0
var charge_speed := 0.0
var attack_damage := 0.0
var attack_interval := 1.0
var cover_range := 0.0
var aggro_range := 0.0
var attack_reach := 0.0
var bunker_reach := 0.0
var is_melee := false
var open_ground_damage_mult := 1.0
var trench_fight_bonus := 1.0
var bunker_damage_mult := 1.0

var _resume_state: State = State.MARCHING
var _attack_cooldown := 0.0
var _think_cooldown := 0.0
var _moving := false
var _facing := 1.0
var _lane_offset := 0.0
var _spread_x := 0.0
## Rifle tip in world pixels for a unit facing right.
var _muzzle_offset := Vector2.ZERO
## Animations that need the Red repaint (see LOOKS).
var _recolored: Array = []
var _recolor_material: ShaderMaterial = null

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var muzzle: Marker2D = $Muzzle
@onready var muzzle_flash: Sprite2D = $Muzzle/MuzzleFlash
@onready var muzzle_sparks: GPUParticles2D = $Muzzle/MuzzleSparks
@onready var vision_area: Area2D = $VisionArea
@onready var vision_shape: CollisionShape2D = $VisionArea/CollisionShape2D
@onready var health_bar: Node2D = $HealthBar
@onready var health_fill: ColorRect = $HealthBar/Fill


# ----------------------------------------------------------------------------
# Setup
# ----------------------------------------------------------------------------
func setup(p_game: GameManager, p_team: int, p_type: Type) -> void:
	game = p_game
	team = p_team
	unit_type = p_type


func _ready() -> void:
	var stats: Dictionary = STATS[unit_type]
	max_health = stats["max_health"]
	march_speed = stats["march_speed"]
	charge_speed = stats["charge_speed"]
	attack_damage = stats["damage"]
	attack_interval = stats["attack_interval"]
	cover_range = stats["cover_range"]
	aggro_range = stats["aggro_range"]
	attack_reach = stats["attack_reach"]
	bunker_reach = stats["bunker_reach"]
	is_melee = stats["melee"]
	open_ground_damage_mult = stats["open_ground_damage_mult"]
	trench_fight_bonus = stats["trench_fight_bonus"]
	bunker_damage_mult = stats["bunker_damage_mult"]
	health = max_health

	# Collision layers: bit 1 = blue_units, bit 2 = red_units.
	# Units never block each other (mask 0); the layer only lets Area2Ds
	# (vision, trenches, gas, craters) detect them.
	collision_layer = 1 << team
	collision_mask = 0
	vision_area.collision_layer = 0
	vision_area.collision_mask = 1 << GameManager.enemy_of(team)
	# Each unit needs its own shape: the radius depends on the unit type.
	var circle := CircleShape2D.new()
	circle.radius = maxf(cover_range, aggro_range) + 20.0
	vision_shape.shape = circle

	add_to_group("units")
	add_to_group("team_%d" % team)

	_facing = GameManager.advance_dir(team)
	_lane_offset = randf_range(-10.0, 14.0)
	_spread_x = randf_range(-80.0, 80.0)
	_attack_cooldown = randf_range(0.2, attack_interval)
	_think_cooldown = randf_range(0.0, THINK_INTERVAL)
	_apply_team_look()
	_update_health_bar()
	_refresh_animation()

	game.whistle_charge.connect(_on_whistle_charge)


## Picks the SpriteFrames for this team / type and sizes everything around it.
func _apply_team_look() -> void:
	var look: Dictionary = LOOKS[team][unit_type]
	var look_scale: float = look["scale"]
	sprite.sprite_frames = look["frames"]
	sprite.scale = Vector2(look_scale, look_scale)
	# Every frame of a SpriteFrames shares one cell size with the feet on the
	# bottom edge, so lifting the sprite by half a cell puts the feet on the
	# node's origin.
	var cell := sprite.sprite_frames.get_frame_texture(ANIM_AIM, 0).get_size()
	sprite.offset = Vector2(0.0, -cell.y * 0.5)
	_muzzle_offset = Vector2(look["muzzle"]) * look_scale
	muzzle.visible = not is_melee

	_recolored = look["recolor"]
	if not _recolored.is_empty():
		# One material per unit: each soldier toggles the repaint on its own.
		_recolor_material = ShaderMaterial.new()
		_recolor_material.shader = RECOLOR_SHADER
		sprite.material = _recolor_material

	health_fill.color = BAR_COLORS[team]


func is_alive() -> bool:
	return state != State.DEAD


# ----------------------------------------------------------------------------
# State machine
# ----------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if game.match_over:
		_moving = false
		_animate(delta)
		return

	_attack_cooldown -= delta
	match state:
		State.MARCHING:
			_state_marching()
		State.IN_COVER:
			_state_in_cover()
		State.CHARGING:
			_state_charging()
		State.ATTACKING:
			_state_attacking()
	_think_cooldown -= delta
	_animate(delta)


## True once every THINK_INTERVAL: throttles the expensive target searches.
func _should_think() -> bool:
	if _think_cooldown > 0.0:
		return false
	_think_cooldown = THINK_INTERVAL
	return true


## MARCHING: walk to a trench slot, fighting anything that gets close.
func _state_marching() -> void:
	if _should_think():
		if trench != null and not trench.can_hold(self):
			_release_slot()  # Our trench was overrun while we were walking.
		if trench == null:
			_seek_cover()
			if state != State.MARCHING:
				return
		var enemy := _find_target(aggro_range)
		if enemy != null:
			_enter_attacking(enemy, State.MARCHING)
			return

	if trench != null:
		if _move_toward(trench.get_slot_position(slot_index), march_speed):
			_enter_cover()
	else:
		# Every trench is full: wait at the rally point outside the bunker.
		var rally := game.get_rally_point(team) + Vector2(_spread_x * 0.6, _lane_offset)
		_move_toward(rally, march_speed)


## IN_COVER: stay in the slot and shoot across No Man's Land.
func _state_in_cover() -> void:
	_moving = false
	velocity = Vector2.ZERO
	if _attack_cooldown > 0.0:
		return
	var enemy := _find_target(cover_range)
	if enemy == null:
		_attack_cooldown = THINK_INTERVAL
		return
	if is_melee:
		# Raiders leave their slot to club anyone who drops into the trench.
		_enter_attacking(enemy, State.IN_COVER)
	else:
		_perform_attack(enemy)


## CHARGING: sprint at the next enemy trench or the enemy Command Bunker.
func _state_charging() -> void:
	if _should_think():
		if not _is_objective_valid():
			objective = game.find_charge_objective(team, global_position.x)
		var enemy := _find_target(aggro_range)
		if enemy != null:
			_enter_attacking(enemy, State.CHARGING)
			return

	var lane_y := GameManager.GROUND_Y + _lane_offset
	if objective is Bunker:
		var bunker := objective as Bunker
		if absf(bunker.global_position.x - global_position.x) <= bunker_reach:
			_enter_attacking(bunker, State.CHARGING)
			return
		_move_toward(Vector2(bunker.global_position.x, lane_y), charge_speed)
	elif objective is Trench:
		var goal := objective as Trench
		var arrived := _move_toward(Vector2(goal.global_position.x + _spread_x, lane_y), charge_speed)
		if arrived:
			if goal.has_enemies_of(team):
				return  # Still contested: the think step picks targets.
			# Trench is clear: jump in and take it.
			var index := goal.reserve_slot(self)
			if index >= 0:
				trench = goal
				slot_index = index
				objective = null
				state = State.MARCHING
			else:
				objective = game.find_charge_objective(team, global_position.x, goal)


## ATTACKING: fight `target` until it dies or gets away, then resume.
func _state_attacking() -> void:
	if not _is_target_valid():
		_leave_attacking()
		return

	var target_pos := target.global_position
	var distance := absf(target_pos.x - global_position.x)
	var reach := bunker_reach if target is Bunker else attack_reach

	if distance > reach:
		if is_melee or target is Bunker:
			_move_toward(Vector2(target_pos.x, global_position.y), charge_speed)
		else:
			_leave_attacking()  # Riflemen do not chase; they go back to their orders.
		return

	_moving = false
	velocity = Vector2.ZERO
	_face_toward(target_pos.x)
	if _attack_cooldown <= 0.0:
		_perform_attack(target)


func _enter_attacking(new_target: Node2D, resume: State) -> void:
	target = new_target
	_resume_state = resume
	state = State.ATTACKING


func _leave_attacking() -> void:
	target = null
	# A unit that left its slot to fight walks back to it via MARCHING.
	state = State.MARCHING if _resume_state == State.IN_COVER else _resume_state


func _enter_cover() -> void:
	state = State.IN_COVER
	_moving = false
	velocity = Vector2.ZERO
	_facing = _direction_to_enemy()
	trench.occupy(self)


## Leave cover and go over the top.
func _begin_charge(new_objective: Node2D = null) -> void:
	var left_trench := trench
	_release_slot()
	target = null
	objective = new_objective
	if objective == null:
		objective = game.find_charge_objective(team, global_position.x, left_trench)
	state = State.CHARGING


func _on_whistle_charge(whistle_team: int) -> void:
	if whistle_team == team and state == State.IN_COVER:
		_begin_charge()


# ----------------------------------------------------------------------------
# Cover / objectives
# ----------------------------------------------------------------------------
func _seek_cover() -> void:
	var found := game.find_cover_trench(team, global_position)
	if found != null:
		var index := found.reserve_slot(self)
		if index >= 0:
			trench = found
			slot_index = index
			return
	# No reachable cover. If the enemy holds a trench on our side, retake it.
	var blocker := game.find_blocking_trench(team)
	if blocker != null:
		_begin_charge(blocker)


func _release_slot() -> void:
	if trench != null:
		trench.release_slot(self)
	trench = null
	slot_index = -1


func _is_objective_valid() -> bool:
	if objective == null or not is_instance_valid(objective):
		return false
	if objective is Bunker:
		return (objective as Bunker).is_alive()
	return true


## The side the enemy is on (used for facing while stationed).
func _direction_to_enemy() -> float:
	return GameManager.advance_dir(team)


# ----------------------------------------------------------------------------
# Targeting
# ----------------------------------------------------------------------------
## Nearest living enemy inside the VisionArea and within `max_range`.
func _find_target(max_range: float) -> Unit:
	var best: Unit = null
	var best_distance := max_range
	for body in vision_area.get_overlapping_bodies():
		var enemy := body as Unit
		if enemy == null or not enemy.is_alive() or not _can_engage(enemy):
			continue
		var distance := global_position.distance_to(enemy.global_position)
		if distance < best_distance:
			best = enemy
			best_distance = distance
	return best


## Riflemen on the move do not stop in the open to trade shots with soldiers
## who are in cover -- they keep running until they are inside that trench.
func _can_engage(enemy: Unit) -> bool:
	if is_melee or state == State.IN_COVER:
		return true
	if enemy.state == State.IN_COVER and enemy.trench != zone_trench:
		return false
	return true


func _is_target_valid() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target is Bunker:
		return (target as Bunker).is_alive()
	var enemy := target as Unit
	if enemy == null or not enemy.is_alive():
		return false
	if not _can_engage(enemy):
		return false
	var distance := global_position.distance_to(enemy.global_position)
	if is_melee:
		# Raiders defending a trench do not chase far from their slot.
		var leash := cover_range * 1.4 if _resume_state == State.IN_COVER else aggro_range * 1.6
		return distance <= leash
	return distance <= attack_reach * 1.1


# ----------------------------------------------------------------------------
# Dealing damage
# ----------------------------------------------------------------------------
func _perform_attack(victim: Node2D) -> void:
	_attack_cooldown = attack_interval * randf_range(0.85, 1.15)
	_face_toward(victim.global_position.x)

	if is_melee:
		var damage := attack_damage
		var victim_unit := victim as Unit
		if victim_unit != null and (zone_trench != null or victim_unit.zone_trench != null):
			damage *= trench_fight_bonus  # Close-quarters trench fighting.
		if victim is Bunker:
			damage *= bunker_damage_mult
		_play_attack_animation()
		_deal_damage(victim, damage, DamageKind.MELEE)
		return

	_play_attack_animation()

	# Rifle shot: accuracy drops with distance, bunkers are too big to miss.
	var aim := victim.global_position + Vector2(0.0, -50.0)
	var distance := global_position.distance_to(victim.global_position)
	var hit_chance := lerpf(0.95, 0.5, clampf(distance / cover_range, 0.0, 1.0))
	var hit := victim is Bunker or randf() <= hit_chance
	if not hit:
		aim += Vector2(_facing * randf_range(40.0, 120.0), randf_range(-70.0, -20.0))
	_play_muzzle_flash()
	game.spawn_tracer(muzzle.global_position, aim)
	if hit:
		var damage := attack_damage
		if victim is Bunker:
			damage *= bunker_damage_mult
		_deal_damage(victim, damage, DamageKind.BULLET)


func _deal_damage(victim: Node2D, amount: float, kind: DamageKind) -> void:
	if victim is Unit:
		(victim as Unit).take_damage(amount, kind, self)
	elif victim is Bunker:
		(victim as Bunker).take_damage(amount, kind, self)


# ----------------------------------------------------------------------------
# Taking damage
# ----------------------------------------------------------------------------
func is_in_open_ground() -> bool:
	return zone_trench == null and crater_count <= 0


## `attacker` may be null (mortars, gas, bunker guns).
func take_damage(amount: float, kind: DamageKind, attacker: Unit) -> void:
	if state == State.DEAD:
		return

	var multiplier := 1.0
	match kind:
		DamageKind.BULLET:
			if state == State.IN_COVER and trench != null:
				# Cover does not help against someone standing in your trench.
				if attacker == null or attacker.zone_trench != trench:
					multiplier *= trench.cover_damage_multiplier
			elif crater_count > 0:
				multiplier *= CRATER_COVER_MULTIPLIER
			elif zone_trench == null:
				multiplier *= open_ground_damage_mult
		DamageKind.EXPLOSION:
			if state == State.IN_COVER and trench != null:
				multiplier *= trench.blast_damage_multiplier
			elif is_in_open_ground():
				multiplier *= open_ground_damage_mult
		DamageKind.MELEE, DamageKind.GAS:
			pass  # Bayonets and gas ignore cover.

	health -= amount * multiplier
	_update_health_bar()
	_flash_hit()
	if health <= 0.0:
		_die()


func _die() -> void:
	state = State.DEAD
	_release_slot()
	target = null
	objective = null
	velocity = Vector2.ZERO
	remove_from_group("units")
	remove_from_group("team_%d" % team)
	collision_layer = 0
	vision_area.set_deferred("monitoring", false)
	health_bar.visible = false
	muzzle_flash.visible = false
	died.emit(self)

	# Fall over backwards, darken, then fade away.
	sprite.pause()
	var tween := create_tween()
	tween.tween_property(sprite, "rotation", -_facing * PI / 2.0, 0.3)
	tween.parallel().tween_property(sprite, "modulate", Color(0.35, 0.3, 0.27, 1.0), 0.3)
	tween.tween_interval(2.5)
	tween.tween_property(self, "modulate:a", 0.0, 1.0)
	tween.tween_callback(queue_free)


func _exit_tree() -> void:
	# Safety net: never leave a dangling slot reservation behind.
	if trench != null and is_instance_valid(trench):
		trench.release_slot(self)
		trench = null


# ----------------------------------------------------------------------------
# Movement + procedural animation
# ----------------------------------------------------------------------------
## Moves toward `destination`. Returns true once the unit has arrived.
func _move_toward(destination: Vector2, speed: float) -> bool:
	var offset := destination - global_position
	# Never overshoot: one physics step can cover more than ARRIVE_DISTANCE
	# for fast units or when Engine.time_scale is raised.
	var step := speed * get_physics_process_delta_time()
	if offset.length() <= maxf(ARRIVE_DISTANCE, step):
		velocity = Vector2.ZERO
		_moving = false
		return true
	velocity = offset.normalized() * speed
	if absf(velocity.x) > 1.0:
		_facing = signf(velocity.x)
	move_and_slide()
	_moving = true
	return false


func _face_toward(x: float) -> void:
	if absf(x - global_position.x) > 1.0:
		_facing = signf(x - global_position.x)


func _animate(_delta: float) -> void:
	# The art is drawn facing right: Blue (advancing right) is shown as-is and
	# Red (advancing left) is mirrored. Units also turn to face their target.
	sprite.flip_h = _facing < 0.0
	muzzle.position = Vector2(_muzzle_offset.x * _facing, _muzzle_offset.y)
	_refresh_animation()


## Plays the animation that matches the current state:
##   MARCHING / CHARGING -> "walk" (held on one frame while standing still)
##   IN_COVER            -> "cover"
##   ATTACKING           -> "aim" between attacks, "walk" while chasing a target
## The "attack" animation (the shot or swing itself) is started by
## _play_attack_animation() and is left to finish before this takes over again.
func _refresh_animation() -> void:
	if state == State.DEAD:
		return
	var wanted := ANIM_WALK
	if not _moving:
		match state:
			State.IN_COVER:
				wanted = ANIM_COVER
			State.ATTACKING:
				wanted = ANIM_AIM

	var mid_attack := sprite.animation == ANIM_ATTACK and sprite.is_playing()
	if mid_attack and not _moving:
		return
	if sprite.animation != wanted:
		_play(wanted)

	if wanted == ANIM_WALK:
		if _moving:
			# Step faster when sprinting so the feet keep up with the ground.
			sprite.speed_scale = clampf(velocity.length() / march_speed, 0.6, 2.0)
			if not sprite.is_playing():
				sprite.play(ANIM_WALK)
		elif sprite.is_playing():
			sprite.pause()


func _play(animation: StringName) -> void:
	if _recolor_material != null:
		var amount := 1.0 if _recolored.has(animation) else 0.0
		_recolor_material.set_shader_parameter("strength", amount)
	sprite.speed_scale = 1.0
	sprite.stop()  # Restart even if this animation is already the current one.
	sprite.play(animation)


## One shot (riflemen) or one swing (raiders).
func _play_attack_animation() -> void:
	_play(ANIM_ATTACK)


## Connected from Sprite.animation_finished in Unit.tscn.
func _on_sprite_animation_finished() -> void:
	_refresh_animation()


func _play_muzzle_flash() -> void:
	muzzle_flash.flip_h = _facing < 0.0
	muzzle_flash.position.x = _facing * 8.0
	muzzle_flash.visible = true
	muzzle_sparks.rotation = 0.0 if _facing > 0.0 else PI
	muzzle_sparks.restart()
	muzzle_sparks.emitting = true
	var tween := create_tween()
	tween.tween_interval(0.08)
	tween.tween_callback(muzzle_flash.hide)


func _flash_hit() -> void:
	if state == State.DEAD:
		return
	sprite.modulate = Color(1.7, 1.45, 1.3)
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.15)


func _update_health_bar() -> void:
	var fraction := clampf(health / max_health, 0.0, 1.0)
	health_fill.size.x = 34.0 * fraction
	health_bar.visible = fraction < 0.999 and state != State.DEAD
