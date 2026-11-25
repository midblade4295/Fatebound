extends SceneTree
## Plays a bot-versus-bot match on the real battle screen and saves screenshots.
## Needs a display (not --headless), for example:
##   xvfb-run -a $GODOT --rendering-method mobile --fixed-fps 30 --resolution 540x960 \
##       --path grapeshot -s tools/capture.gd
## Environment: CAPTURE_DIR (default res://captures), CAPTURE_SEED (default 7),
## CAPTURE_TIMES (match seconds, default "14,32,55").

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
	screen = load("res://scenes/Main.tscn").instantiate()
	screen.autoplay = true
	screen.match_seed = int(OS.get_environment("CAPTURE_SEED")) if OS.has_environment("CAPTURE_SEED") else 7
	root.add_child(screen)


func _process(_delta: float) -> bool:
	var sim: Sim = screen.sim
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
	var path := "%s/grapeshot_%s.png" % [out_dir, tag]
	img.save_png(path)
	print("saved ", path, " ", img.get_size())
