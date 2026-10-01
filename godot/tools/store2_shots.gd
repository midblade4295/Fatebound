extends "res://tools/trailer2_shots.gd"
# Cinematic Play Store screenshots (Round 26): the trailer's staged shots, frozen at their best moment and
# rendered portrait (1080x1920 via override.cfg), HUD hidden. SHOT=<trailer shot> STILL_AT=<s> OUT=<png>.
# Optional PORTRAIT_CAM per shot replaces the trailer's widescreen camera for the portrait frame.
var _still_frame := -1
var _pcam := []

func _portrait_cam() -> Array:
	# Portrait-specific cameras where the trailer's widescreen framing doesn't fit a tall frame.
	var s = mode.sim
	match shot:
		"clash":
			# Behind our line, looking down the charge: their army runs at the viewer.
			return [Vector3(-1.2, 2.6, 22.5), Vector3(0.6, 1.3, 13.0)]
		"captive":
			var cell: Vector2 = Sim.cell(0)
			var jail: Dictionary = s.gates.filter(func(g): return g.team == 1 and str(g.get("kind", "")) == "jail")[0]
			var out: Vector2 = ((jail.c as Vector2) - cell).normalized()
			var cy := Sim.height_at(cell)
			# High enough that the line of sight clears the guards at the bars.
			return [_v(cell + out * 5.0, cy + 4.3), _v(cell, cy + 1.0)]
		"build":
			# Along the wall, so the ladder and the knight going over it both show.
			return [Vector3(-9.3, 3.6, -34.6), Vector3(-14.2, 2.3, -38.2)]
		"rampart":
			# Low, outside the wall, looking up at the rangers on the parapet against the sky.
			return [_v(Sim._c(0, Vector2(1.6, -5.0)), 1.4), _v(Sim._c(0, Vector2(0.4, 4.4)), 3.1)]
	return []

func _process(delta: float) -> bool:
	var at := float(OS.get_environment("STILL_AT")) if OS.has_environment("STILL_AT") else 2.0
	if _still_frame < 0:
		_still_frame = int(at * 30.0) + 2
	if frames == _still_frame:
		var out := OS.get_environment("OUT") if OS.has_environment("OUT") else "/tmp/store2/%s.png" % shot
		RenderingServer.frame_post_draw.connect(func():
			root.get_texture().get_image().save_png(out)
			quit(0), CONNECT_ONE_SHOT)
	var r := super._process(delta)
	if frames == 3:
		_pcam = _portrait_cam()
	if not _pcam.is_empty() and frames > 3:
		mode.view.cam_override = _pcam
	return r
