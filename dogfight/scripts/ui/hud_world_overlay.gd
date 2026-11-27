class_name HudWorldOverlay
extends Control
## Everything on the HUD that is pinned to a point in the 3D world:
##  - red diamonds on enemies, small blue chevrons on wingmen
##  - arrows on the screen edge for nearby enemies that are off-screen,
##    pulsing gold when that enemy is hunting you
##  - the gun pipper (where your bullets are going) and the lead reticle
##    (where to put the pipper to hit your current target)
##  - hit marker and damage flash
##
## All positions come from the chase camera's unproject_position() of
## *interpolated* transforms, so markers stay glued to the planes even though
## the camera lags behind the player and the planes move at the physics rate.

## Markers closer than this to the screen edge become edge arrows instead.
const EDGE_MARGIN: float = 70.0
## Off-screen enemies inside this range always get an arrow.
const THREAT_RANGE: float = 700.0
const ENEMY_COLOR: Color = Color(1.0, 0.27, 0.22)
const ALLY_COLOR: Color = Color(0.35, 0.72, 1.0)
const LEAD_COLOR: Color = Color(1.0, 0.84, 0.25)
const LOCK_COLOR: Color = Color(0.5, 1.0, 0.45)
const HIT_MARKER_TIME: float = 0.14
const DAMAGE_FLASH_TIME: float = 0.35
## Short labels for damaged parts under the current target, indexed by PlaneActor.Part.
const PART_TAGS: Array[String] = ["", "ENGINE", "L WING", "R WING", "TAIL"]

var camera: Camera3D
var match_manager: MatchManager5v5
var player: PlaneActor
var view_team: Teams.Id = Teams.Id.TEAM_BLUE

var _hit_marker: float = 0.0
var _damage_flash: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_time += delta
	_hit_marker = maxf(_hit_marker - delta, 0.0)
	_damage_flash = maxf(_damage_flash - delta, 0.0)
	queue_redraw()


## The player's bullets just connected.
func show_hit_marker() -> void:
	_hit_marker = HIT_MARKER_TIME


## The player just took damage.
func show_damage_flash() -> void:
	_damage_flash = DAMAGE_FLASH_TIME


func _draw() -> void:
	if camera == null or match_manager == null:
		return
	var has_player: bool = player != null and is_instance_valid(player)
	var player_alive: bool = has_player and player.alive
	var eye: Vector3 = player.global_position if has_player else camera.global_position
	var safe_rect: Rect2 = Rect2(Vector2.ZERO, size).grow(-EDGE_MARGIN)

	for plane: PlaneActor in match_manager.get_planes():
		if plane == player or not plane.alive:
			continue
		var hostile: bool = Teams.are_hostile(plane.team, view_team)
		if hostile and plane.is_concealed():
			continue
		var world_position: Vector3 = plane.get_global_transform_interpolated().origin
		var distance: float = eye.distance_to(world_position)
		var in_front: bool = not camera.is_position_behind(world_position)
		var screen_position: Vector2 = camera.unproject_position(world_position) if in_front else Vector2.ZERO
		if in_front and safe_rect.has_point(screen_position):
			if hostile:
				_draw_enemy_marker(plane, screen_position, distance, player_alive and plane == player.current_target)
			else:
				_draw_ally_marker(screen_position, distance)
		elif hostile and player_alive:
			var hunting: bool = plane.current_target == player
			if hunting or distance < THREAT_RANGE:
				_draw_edge_arrow(world_position, distance, hunting)

	if player_alive:
		_draw_gunsight()
	if _damage_flash > 0.0:
		var alpha: float = _damage_flash / DAMAGE_FLASH_TIME
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.1, 0.05, 0.22 * alpha), false, 90.0)


func _draw_enemy_marker(plane: PlaneActor, at: Vector2, distance: float, is_target: bool) -> void:
	var half: float = clampf(2600.0 / maxf(distance, 60.0), 13.0, 34.0)
	if is_target:
		half *= 1.25
	var diamond: PackedVector2Array = PackedVector2Array([
		at + Vector2(0.0, -half), at + Vector2(half, 0.0), at + Vector2(0.0, half), at + Vector2(-half, 0.0), at + Vector2(0.0, -half)])
	draw_polyline(diamond, UiStyle.OUTLINE, 7.0 if is_target else 6.0, true)
	draw_polyline(diamond, ENEMY_COLOR, 4.0 if is_target else 3.0, true)
	if not is_target:
		return
	# The current target also gets a health bar, name and range.
	var bar_width: float = 76.0
	var bar_origin: Vector2 = at + Vector2(-bar_width * 0.5, -half - 20.0)
	draw_rect(Rect2(bar_origin - Vector2(3.0, 3.0), Vector2(bar_width + 6.0, 14.0)), UiStyle.OUTLINE)
	draw_rect(Rect2(bar_origin, Vector2(bar_width * plane.hp_ratio(), 8.0)), ENEMY_COLOR)
	UiStyle.draw_outlined_text(self, "%s  %dm" % [plane.pilot_name, roundi(distance)],
			at + Vector2(-150.0, -half - 30.0), 20, UiStyle.WHITE, 300.0, 5)
	# Which of the target's parts are already hurt (shoot there to finish it).
	var hurt: PackedStringArray = PackedStringArray()
	for part: PlaneActor.Part in [PlaneActor.Part.ENGINE, PlaneActor.Part.LEFT_WING, PlaneActor.Part.RIGHT_WING, PlaneActor.Part.TAIL]:
		if plane.part_state(part) != PlaneActor.PartState.OK:
			hurt.append(PART_TAGS[part])
	if not hurt.is_empty():
		UiStyle.draw_outlined_text(self, "  ".join(hurt), at + Vector2(-150.0, half + 26.0), 18, LEAD_COLOR, 300.0, 5)


func _draw_ally_marker(at: Vector2, distance: float) -> void:
	var half: float = clampf(1500.0 / maxf(distance, 60.0), 7.0, 14.0)
	var top: Vector2 = at + Vector2(0.0, -half * 3.2)
	var chevron: PackedVector2Array = PackedVector2Array([top + Vector2(-half, -half), top, top + Vector2(half, -half)])
	draw_polyline(chevron, UiStyle.OUTLINE, 6.0, true)
	draw_polyline(chevron, ALLY_COLOR, 3.0, true)


## Arrow on the screen edge pointing toward an enemy the camera cannot see.
func _draw_edge_arrow(world_position: Vector3, distance: float, hunting: bool) -> void:
	# Direction in camera space works even when the enemy is directly behind,
	# where unproject_position() would give a mirrored, useless result.
	var local: Vector3 = camera.global_transform.affine_inverse() * world_position
	var direction: Vector2 = Vector2(local.x, -local.y)
	if direction.length_squared() < 0.0001:
		direction = Vector2.DOWN
	direction = direction.normalized()
	var center: Vector2 = size * 0.5
	var half: Vector2 = size * 0.5 - Vector2(EDGE_MARGIN, EDGE_MARGIN)
	var reach: float = minf(half.x / maxf(absf(direction.x), 0.0001), half.y / maxf(absf(direction.y), 0.0001))
	var tip: Vector2 = center + direction * reach
	var pulse: float = 0.5 + 0.5 * sin(_time * 10.0)
	var arrow_size: float = 30.0 if hunting else 22.0
	var arrow_color: Color = ENEMY_COLOR.lerp(LEAD_COLOR, pulse) if hunting else ENEMY_COLOR
	var side: Vector2 = direction.orthogonal() * arrow_size * 0.7
	var base: Vector2 = tip - direction * arrow_size * 1.5
	var arrow: PackedVector2Array = PackedVector2Array([tip, base + side, base - side])
	draw_colored_polygon(arrow, arrow_color)
	draw_polyline(PackedVector2Array([arrow[0], arrow[1], arrow[2], arrow[0]]), UiStyle.OUTLINE, 4.0, true)
	UiStyle.draw_outlined_text(self, "%dm" % roundi(distance), base - direction * 24.0 + Vector2(-50.0, 8.0), 20, UiStyle.WHITE, 100.0, 5)


## Gun pipper plus, when a target is selected, the lead-prediction reticle.
func _draw_gunsight() -> void:
	var plane_transform: Transform3D = player.get_global_transform_interpolated()
	var origin: Vector3 = plane_transform.origin
	var nose: Vector3 = -plane_transform.basis.z
	var pipper_world: Vector3 = origin + nose * PlaneActor.GUN_CONVERGENCE
	if camera.is_position_behind(pipper_world):
		return
	var pipper: Vector2 = camera.unproject_position(pipper_world)

	var locked: bool = false
	var enemy: PlaneActor = player.current_target
	if enemy != null and is_instance_valid(enemy) and enemy.alive and not enemy.is_concealed():
		var enemy_position: Vector3 = enemy.get_global_transform_interpolated().origin
		var lead_world: Vector3 = Ballistics.lead_point(origin, player.velocity, enemy_position, enemy.velocity, player.stats.bullet_speed)
		if not camera.is_position_behind(lead_world) and not camera.is_position_behind(enemy_position):
			var lead: Vector2 = camera.unproject_position(lead_world)
			var enemy_screen: Vector2 = camera.unproject_position(enemy_position)
			var in_range: bool = origin.distance_to(enemy_position) <= player.stats.gun_range
			var lead_radius: float = 22.0
			locked = in_range and pipper.distance_to(lead) <= lead_radius * 1.5
			var lead_color: Color = LOCK_COLOR if locked else (LEAD_COLOR if in_range else Color(1.0, 1.0, 1.0, 0.55))
			# Dashed-looking tether from the enemy to where you should shoot.
			if enemy_screen.distance_to(lead) > lead_radius:
				draw_line(enemy_screen, lead - (lead - enemy_screen).normalized() * lead_radius, Color(lead_color, 0.55), 2.5, true)
			draw_arc(lead, lead_radius, 0.0, TAU, 28, UiStyle.OUTLINE, 7.0, true)
			draw_arc(lead, lead_radius, 0.0, TAU, 28, lead_color, 4.0, true)
			draw_circle(lead, 4.5, lead_color)

	var pipper_color: Color = LOCK_COLOR if locked else UiStyle.WHITE
	for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(pipper + direction * 9.0, pipper + direction * 26.0, UiStyle.OUTLINE, 7.0)
		draw_line(pipper + direction * 10.0, pipper + direction * 25.0, pipper_color, 3.5)
	draw_circle(pipper, 5.0, UiStyle.OUTLINE)
	draw_circle(pipper, 3.0, pipper_color)

	if _hit_marker > 0.0:
		var marker_alpha: float = _hit_marker / HIT_MARKER_TIME
		for diagonal: Vector2 in [Vector2(1.0, 1.0), Vector2(1.0, -1.0), Vector2(-1.0, 1.0), Vector2(-1.0, -1.0)]:
			var unit: Vector2 = diagonal.normalized()
			draw_line(pipper + unit * 30.0, pipper + unit * 46.0, Color(1.0, 0.95, 0.5, marker_alpha), 5.0, true)
