class_name HudWorldOverlay
extends Control
## Everything on the HUD that is pinned to a point in the 3D world:
##  - red diamonds on enemies, small blue chevrons on wingmen
##  - arrows on the screen edge for nearby enemies that are off-screen,
##    pulsing gold when that enemy is hunting you
##  - the gun pipper: a fixed gunsight showing where your bullets are going.
##    There is no lead-prediction reticle; deflection is judged by eye.
##  - hit marker and damage flash
##  - a marker on the player's own airfield, with the distance to it
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
const HIT_MARKER_TIME: float = 0.14
const DAMAGE_FLASH_TIME: float = 0.35
## Short labels for damaged parts under the current target, indexed by PlaneActor.Part.
const PART_TAGS: Array[String] = [
	"FUEL", "ENGINE", "L WING", "R WING", "L TIP", "R TIP", "TAIL", "FIN", "RUDDER",
	"L FLAP", "R FLAP", "L AIL", "R AIL", "L ELEV", "R ELEV",
]
const MAX_TARGET_TAGS: int = 4

var camera: Camera3D
var match_manager: MatchManager5v5
var player: PlaneActor
var view_team: Teams.Id = Teams.Id.TEAM_BLUE
## The player's own airfield, or null.
var home: Airfield

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

	if player_alive and home != null and is_instance_valid(home) and not player.is_on_ground():
		_draw_home_marker(eye, safe_rect)
	if player_alive and not player.is_on_ground():
		_draw_gunsight()
	if _damage_flash > 0.0:
		var alpha: float = _damage_flash / DAMAGE_FLASH_TIME
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.1, 0.05, 0.22 * alpha), false, 90.0)


## A small runway sign on the player's own airfield. Off-screen it becomes an
## arrow on the edge, but only when the pilot has a reason to go home (damage,
## or the wheels are down), so it does not clutter a dogfight.
func _draw_home_marker(eye: Vector3, safe_rect: Rect2) -> void:
	var world_position: Vector3 = home.runway_center()
	var distance: float = eye.distance_to(world_position)
	var label: String = "BASE %.1f km" % (distance / 1000.0) if distance >= 1000.0 else "BASE %d m" % roundi(distance)
	var color: Color = Teams.color_of(home.team).lightened(0.35)
	var wanted: bool = player.needs_service() or player.is_gear_down()
	var in_front: bool = not camera.is_position_behind(world_position)
	var at: Vector2 = camera.unproject_position(world_position) if in_front else Vector2.ZERO
	if in_front and safe_rect.has_point(at):
		var half: Vector2 = Vector2(9.0, 20.0) * (1.25 if wanted else 1.0)
		var plate: Rect2 = Rect2(at - half, half * 2.0)
		draw_rect(plate.grow(3.0), UiStyle.OUTLINE)
		draw_rect(plate, color)
		draw_line(at + Vector2(0.0, -half.y + 5.0), at + Vector2(0.0, half.y - 5.0), UiStyle.OUTLINE, 2.0)
		UiStyle.draw_outlined_text(self, label, at + Vector2(-110.0, -half.y - 10.0), 18, color, 220.0, 5)
		return
	if not wanted:
		return
	var center: Vector2 = size * 0.5
	var direction: Vector2 = Vector2.UP
	var relative: Vector3 = camera.global_transform.basis.inverse() * (world_position - camera.global_position)
	if Vector2(relative.x, -relative.y).length_squared() > 0.0001:
		direction = Vector2(relative.x, -relative.y).normalized()
	var reach: float = minf((size.x * 0.5 - EDGE_MARGIN) / maxf(absf(direction.x), 0.0001), (size.y * 0.5 - EDGE_MARGIN) / maxf(absf(direction.y), 0.0001))
	var tip: Vector2 = center + direction * reach
	var side: Vector2 = direction.orthogonal() * 13.0
	var arrow: PackedVector2Array = PackedVector2Array([tip, tip - direction * 26.0 + side, tip - direction * 26.0 - side])
	draw_colored_polygon(arrow, color)
	draw_polyline(PackedVector2Array([arrow[0], arrow[1], arrow[2], arrow[0]]), UiStyle.OUTLINE, 3.0, true)
	UiStyle.draw_outlined_text(self, label, tip - direction * 52.0 + Vector2(-110.0, 6.0), 18, color, 220.0, 5)


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
	# The current target also gets its name and range, and a list of what is
	# already wrong with it. There is no health bar because there is no health.
	UiStyle.draw_outlined_text(self, "%s  %dm" % [plane.pilot_name, roundi(distance)],
			at + Vector2(-150.0, -half - 14.0), 20, UiStyle.WHITE, 300.0, 5)
	var hurt: PackedStringArray = PackedStringArray()
	if plane.is_going_down():
		hurt.append("GOING DOWN")
	for index: int in range(PlaneActor.PART_COUNT):
		if hurt.size() >= MAX_TARGET_TAGS:
			break
		var part: PlaneActor.Part = index as PlaneActor.Part
		# A part that left with its parent is not listed again.
		var parent: int = PlaneActor.PART_PARENT[index]
		if parent >= 0 and plane.is_part_gone(parent as PlaneActor.Part):
			continue
		if plane.part_state(part) != PlaneActor.PartState.OK:
			hurt.append(PART_TAGS[index] + (" OFF" if plane.is_part_gone(part) else ""))
	if not hurt.is_empty():
		UiStyle.draw_outlined_text(self, "  ".join(hurt), at + Vector2(-200.0, half + 26.0), 18, LEAD_COLOR, 400.0, 5)


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


## The gun pipper: where your bullets will be at convergence range.
func _draw_gunsight() -> void:
	var plane_transform: Transform3D = player.get_global_transform_interpolated()
	var origin: Vector3 = plane_transform.origin
	var nose: Vector3 = -plane_transform.basis.z
	# The pipper marks where bullets are at convergence range, including how
	# far they have dropped by then, so it sits a little below the nose line.
	var pipper_world: Vector3 = origin + nose * PlaneActor.GUN_CONVERGENCE
	var flight_time: float = Ballistics.time_to_travel(PlaneActor.GUN_CONVERGENCE, player.stats.bullet_speed)
	if flight_time > 0.0:
		pipper_world += Vector3.DOWN * Ballistics.drop_after(flight_time)
	if camera.is_position_behind(pipper_world):
		return
	var pipper: Vector2 = camera.unproject_position(pipper_world)

	# Plain fixed gunsight. There is deliberately no lead-prediction reticle:
	# judging how far ahead of (and above) the target to shoot is the pilot's job.
	for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(pipper + direction * 9.0, pipper + direction * 26.0, UiStyle.OUTLINE, 7.0)
		draw_line(pipper + direction * 10.0, pipper + direction * 25.0, UiStyle.WHITE, 3.5)
	draw_circle(pipper, 5.0, UiStyle.OUTLINE)
	draw_circle(pipper, 3.0, UiStyle.WHITE)

	if _hit_marker > 0.0:
		var marker_alpha: float = _hit_marker / HIT_MARKER_TIME
		for diagonal: Vector2 in [Vector2(1.0, 1.0), Vector2(1.0, -1.0), Vector2(-1.0, 1.0), Vector2(-1.0, -1.0)]:
			var unit: Vector2 = diagonal.normalized()
			draw_line(pipper + unit * 30.0, pipper + unit * 46.0, Color(1.0, 0.95, 0.5, marker_alpha), 5.0, true)
