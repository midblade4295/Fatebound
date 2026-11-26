class_name Radar
extends Control
## Circular heading-up radar for the top-right corner. The player is the arrow
## in the middle and "up" is always the direction the nose points, so a blip
## above the centre is in front of you. Contacts beyond the range are pinned to
## the rim so you still know which way to turn.

## World metres from the centre to the rim.
@export var radar_range: float = 800.0
## Half-angle of the forward gun cone drawn on the dial, in degrees.
@export var cone_half_angle_deg: float = 28.0

var match_manager: MatchManager5v5
var player: PlaneActor
## Team drawn as "friendly" when there is no player plane (spectating).
var view_team: Teams.Id = Teams.Id.TEAM_BLUE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var dial_radius: float = minf(size.x, size.y) * 0.5 - 6.0
	draw_circle(center, dial_radius, Color(0.06, 0.13, 0.26, 0.72))
	for ring: float in [0.33, 0.66]:
		draw_arc(center, dial_radius * ring, 0.0, TAU, 48, Color(0.6, 0.85, 1.0, 0.22), 2.0, true)
	draw_line(center - Vector2(dial_radius, 0.0), center + Vector2(dial_radius, 0.0), Color(0.6, 0.85, 1.0, 0.16), 2.0)
	draw_line(center - Vector2(0.0, dial_radius), center + Vector2(0.0, dial_radius), Color(0.6, 0.85, 1.0, 0.16), 2.0)

	# Forward gun cone.
	var cone: PackedVector2Array = PackedVector2Array([center])
	var half_angle: float = deg_to_rad(cone_half_angle_deg)
	for step: int in range(9):
		var angle: float = -PI * 0.5 - half_angle + 2.0 * half_angle * float(step) / 8.0
		cone.append(center + Vector2.from_angle(angle) * dial_radius)
	draw_colored_polygon(cone, Color(1.0, 0.35, 0.3, 0.2))

	var has_player: bool = player != null and is_instance_valid(player)
	if match_manager != null and has_player:
		var origin: Vector3 = player.global_position
		# Player's forward and right on the ground plane.
		var forward: Vector2 = Vector2(-sin(player.yaw), -cos(player.yaw))
		var right: Vector2 = Vector2(cos(player.yaw), -sin(player.yaw))
		for plane: PlaneActor in match_manager.get_planes():
			if plane == player or not plane.alive:
				continue
			var hostile: bool = Teams.are_hostile(plane.team, view_team)
			if hostile and plane.is_concealed():
				continue  # Smoke screens hide a plane from radar too.
			var offset: Vector3 = plane.global_position - origin
			var flat: Vector2 = Vector2(offset.x, offset.z)
			var blip: Vector2 = Vector2(flat.dot(right), -flat.dot(forward)) / radar_range
			var pinned: bool = blip.length() > 1.0
			if pinned:
				blip = blip.normalized()
			var blip_position: Vector2 = center + blip * (dial_radius - 9.0)
			var blip_color: Color = Teams.color_of(plane.team).lightened(0.15)
			var blip_radius: float = 6.0 if pinned else 8.5
			draw_circle(blip_position, blip_radius + 2.5, UiStyle.OUTLINE)
			draw_circle(blip_position, blip_radius, blip_color)
			if hostile and plane.current_target == player:
				# This enemy is hunting you.
				draw_arc(blip_position, blip_radius + 6.0, 0.0, TAU, 16, Color(1.0, 0.9, 0.3, 0.9), 2.5, true)

	# Player arrow.
	var arrow: PackedVector2Array = PackedVector2Array([
		center + Vector2(0.0, -14.0), center + Vector2(11.0, 11.0), center + Vector2(0.0, 5.0), center + Vector2(-11.0, 11.0)])
	draw_colored_polygon(arrow, Color(0.45, 0.9, 1.0))
	var arrow_outline: PackedVector2Array = arrow.duplicate()
	arrow_outline.append(arrow[0])
	draw_polyline(arrow_outline, UiStyle.OUTLINE, 2.5, true)

	draw_arc(center, dial_radius, 0.0, TAU, 64, UiStyle.OUTLINE, 9.0, true)
	draw_arc(center, dial_radius, 0.0, TAU, 64, Color(0.75, 0.88, 1.0, 0.95), 4.0, true)
