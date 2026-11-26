extends SceneTree
## Plays a bot-versus-bot match on the real battle screen and saves screenshots.
## Needs a display (not --headless), for example:
##   xvfb-run -a $GODOT --rendering-method mobile --fixed-fps 30 --resolution 540x960 \
##       --path drums_of_war -s tools/capture.gd
## Environment: CAPTURE_DIR (default res://captures), CAPTURE_SEED (default 7),
## CAPTURE_TIMES (match seconds, default "14,32,55"), CAPTURE_LOOK ("field_x,field_y,distance"
## for a close-up instead of the game camera).

const Sim = preload("res://scripts/sim/battle_sim.gd")

var screen: Node
var out_dir: String = "res://captures"
var times: Array = [14.0, 32.0, 55.0]
var next_shot: int = 0
var select_card: bool = true


func _initialize() -> void:
	if OS.has_environment("CAPTURE_DIR"):
		out_dir = OS.get_environment("CAPTURE_DIR")
	if OS.has_environment("CAPTURE_TIMES"):
		times.clear()
		for part: String in OS.get_environment("CAPTURE_TIMES").split(","):
			times.append(float(part))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	screen = load("res://scripts/view/battle_screen.gd").new()       # the battle alone, without the menu
	screen.autoplay = true
	if OS.has_environment("CAPTURE_DECK"):
		screen.deck = Array(OS.get_environment("CAPTURE_DECK").split(","))
	screen.match_seed = int(OS.get_environment("CAPTURE_SEED")) if OS.has_environment("CAPTURE_SEED") else 7
	root.add_child(screen)


func _process(_delta: float) -> bool:
	var sim: Sim = screen.sim
	if OS.has_environment("CAPTURE_LOOK"):
		# Close-up for checking models: "field_x,field_y,distance".
		var parts := OS.get_environment("CAPTURE_LOOK").split(",")
		var target: Vector3 = screen.world.to_world(Vector2(float(parts[0]), float(parts[1])), 0.6)
		var d := float(parts[2])
		screen.world.camera.look_at_from_position(target + Vector3(d * 0.25, d * 0.55, d), target, Vector3.UP)
	if next_shot >= times.size() or sim.phase == Sim.PHASE_OVER:
		_save("end")
		quit(0)
		return true
	# Fast-forward the rules between shots, then let a few real frames draw the effects.
	var target: float = times[next_shot]
	if sim.time < target - 1.0:
		for i in 10:
			screen.bot.tick(sim)
			screen.auto_bot.tick(sim)
			sim.tick()
			screen._take_events()
	elif sim.time >= target:
		_save("t%03d" % int(target))
		next_shot += 1
	return false


func _save(tag: String) -> void:
	var img := root.get_texture().get_image()
	var path := "%s/drums_%s.png" % [out_dir, tag]
	img.save_png(path)
	print("saved ", path, " ", img.get_size())
