extends Node
## Development tool: loads a scene, lets it run, saves PNG screenshots.
##
##   godot --path . --fixed-fps 60 res://tools/ShotCapture.tscn -- \
##       scene=res://scenes/arena/DogfightArena5v5.tscn out=/tmp/shot frames=240,600 [fire=1] [seed=7]
##
## Needs a real renderer (not --headless). On a machine with no GPU:
##   xvfb-run -a godot --rendering-method mobile ...   with a software Vulkan driver.

var _frames: PackedInt32Array = PackedInt32Array()
var _out: String = "user://shot"
var _frame: int = 0
var _fire: bool = false
## Hold the stick over (steer=left|right|up) for the last second before each shot.
var _steer_action: StringName = &""
## Frames at the start that run at `_warp_scale` x speed to reach the action.
var _warp_frames: int = 0
var _warp_scale: float = 6.0


func _ready() -> void:
	var scene_path: String = GameSession.SCENE_HANGAR
	Profile.persistence_enabled = false
	Profile.reset_to_new_profile(false)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("scene="):
			scene_path = argument.trim_prefix("scene=")
		elif argument.begins_with("out="):
			_out = argument.trim_prefix("out=")
		elif argument.begins_with("frames="):
			for part: String in argument.trim_prefix("frames=").split(","):
				_frames.append(int(part))
		elif argument.begins_with("fire="):
			_fire = argument.trim_prefix("fire=") == "1"
		elif argument.begins_with("seed="):
			GameSession.match_seed = int(argument.trim_prefix("seed="))
		elif argument.begins_with("crates="):
			for _crate: int in range(int(argument.trim_prefix("crates="))):
				Profile.grant_match_rewards(true, 5)
		elif argument.begins_with("steer="):
			_steer_action = {"left": GameSession.ACTION_STEER_LEFT, "right": GameSession.ACTION_STEER_RIGHT,
					"up": GameSession.ACTION_PITCH_UP}.get(argument.trim_prefix("steer="), &"")
		elif argument.begins_with("warp="):
			_warp_frames = int(argument.trim_prefix("warp="))
		elif argument.begins_with("spectate="):
			GameSession.local_player_enabled = argument.trim_prefix("spectate=") != "1"
	if _frames.is_empty():
		_frames.append(120)
	add_child((load(scene_path) as PackedScene).instantiate())


func _process(_delta: float) -> void:
	_frame += 1
	Engine.time_scale = _warp_scale if _frame <= _warp_frames else 1.0
	if _fire:
		Input.action_press(GameSession.ACTION_FIRE)
	if _steer_action != &"" and _frame > _warp_frames:
		Input.action_press(_steer_action)
	var index: int = _frames.find(_frame)
	if index == -1:
		return
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = "%s_%d.png" % [_out, _frame]
	image.save_png(path)
	print("saved ", path, " ", image.get_size())
	if index == _frames.size() - 1:
		get_tree().quit()
