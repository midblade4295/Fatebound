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
## damage=1 shoots the right wingtip and the rudder off the player's plane
## once the fast-forward ends, to show break-up and debris.
var _damage_demo: bool = false
## takeoff=1 flies the player's plane off the runway: starter, full throttle,
## stick back at flying speed, wheels up once clear of the ground.
var _takeoff_demo: bool = false
## roughlanding=<m/s> drops the player's plane onto its own runway at that
## rate of descent on frame 30, to show what a rough landing breaks.
var _rough_landing: float = 0.0
## look=<x>,<y>,<zoom> drags the camera by that many pixels on frame 20: in
## the hangar it also zooms by that factor (below 1 = closer); in a match it
## holds the chase camera turned that far.
var _look: Vector3 = Vector3.ZERO
var _scene: Node
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
		elif argument.begins_with("fit="):
			_fit(argument.trim_prefix("fit=").split("+"))
		elif argument.begins_with("crates="):
			for _crate: int in range(int(argument.trim_prefix("crates="))):
				Profile.grant_match_rewards(true, 5)
		elif argument.begins_with("steer="):
			_steer_action = {"left": GameSession.ACTION_STEER_LEFT, "right": GameSession.ACTION_STEER_RIGHT,
					"up": GameSession.ACTION_PITCH_UP}.get(argument.trim_prefix("steer="), &"")
		elif argument.begins_with("look="):
			var parts: PackedStringArray = argument.trim_prefix("look=").split(",")
			if parts.size() == 3:
				_look = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
		elif argument.begins_with("roughlanding="):
			_rough_landing = float(argument.trim_prefix("roughlanding="))
		elif argument.begins_with("takeoff="):
			_takeoff_demo = argument.trim_prefix("takeoff=") == "1"
		elif argument.begins_with("damage="):
			_damage_demo = argument.trim_prefix("damage=") == "1"
		elif argument.begins_with("warp="):
			_warp_frames = int(argument.trim_prefix("warp="))
		elif argument.begins_with("spectate="):
			GameSession.local_player_enabled = argument.trim_prefix("spectate=") != "1"
	if _frames.is_empty():
		_frames.append(120)
	_scene = (load(scene_path) as PackedScene).instantiate()
	add_child(_scene)


func _apply_demo_damage() -> void:
	var manager: MatchManager5v5 = _scene.get_node_or_null("MatchManager") as MatchManager5v5
	if manager == null or manager.local_slot() == null:
		return
	var plane: PlaneActor = manager.local_slot().plane
	for part: PlaneActor.Part in [PlaneActor.Part.RIGHT_WINGTIP, PlaneActor.Part.RUDDER]:
		plane.apply_damage(100000.0, null, part)
	plane.apply_damage(plane.stats.max_hp * PlaneActor.PART_STRENGTH[PlaneActor.Part.ENGINE] * 0.5, null, PlaneActor.Part.ENGINE)


## fit=<item id>+<item id>+... gives the player every item (at Commander
## Level 8, so every mount is open) and fits the listed ones, in order, each
## to the next free mount of its kind. A gun id listed twice fits two guns.
func _fit(item_ids: PackedStringArray) -> void:
	Profile.commander_xp = CommanderProgression.total_xp_for_level(8)
	for card: ComponentCard in GameCatalog.CARDS:
		Profile.add_card_units(card.id, card.max_units())
	for station: int in range(CommanderProgression.GUN_STATION_COUNT):
		Profile.unequip_mount(station)
	for item_id: String in item_ids:
		var card: ComponentCard = GameCatalog.find_card(StringName(item_id))
		if card != null:
			Profile.equip_card(Profile.find_mount_for(card), card.id)


func _drop_player() -> void:
	var manager: MatchManager5v5 = _scene.get_node_or_null("MatchManager") as MatchManager5v5
	if manager == null or manager.local_slot() == null:
		return
	var plane: PlaneActor = manager.local_slot().plane
	var field: Airfield = plane.home_airfield()
	if field == null:
		return
	var direction: Vector3 = field.takeoff_direction()
	plane.set_engine_running(true)
	plane.speed = plane.stats.top_speed * 0.6
	plane.teleport(Transform3D(Basis.looking_at(direction, Vector3.UP), field.runway_start() + direction * 300.0 + Vector3.UP * 20.0))
	plane._touch_down(field, _rough_landing)


func _fly_takeoff() -> void:
	var manager: MatchManager5v5 = _scene.get_node_or_null("MatchManager") as MatchManager5v5
	if manager == null or manager.local_slot() == null:
		return
	var plane: PlaneActor = manager.local_slot().plane
	if not plane.alive:
		return
	if not plane.has_flag(PlaneActor.FLAG_ENGINE_ON) and _frame % 60 == 20:
		plane.input.press_engine()
	plane.input.throttle = 1.0
	if plane.is_on_ground():
		if plane.speed >= plane.takeoff_speed() * 1.03:
			Input.action_press(GameSession.ACTION_PITCH_UP, 0.6)
	else:
		# Hold a gentle climb and tidy the wheels away.
		Input.action_press(GameSession.ACTION_PITCH_UP, clampf((deg_to_rad(10.0) - plane.pitch) * 4.0, 0.01, 1.0))
		if plane.is_gear_down() and plane.height_above_ground() > 25.0 and _frame % 60 == 0:
			plane.input.press_gear()


func _process(_delta: float) -> void:
	_frame += 1
	Engine.time_scale = _warp_scale if _frame <= _warp_frames else 1.0
	if _damage_demo and _frame == _warp_frames + 2:
		_apply_demo_damage()
	if _fire:
		Input.action_press(GameSession.ACTION_FIRE)
	if _takeoff_demo:
		_fly_takeoff()
	if _look.z > 0.0 and _frame == 20 and _scene.has_method(&"orbit_view"):
		_scene.call(&"orbit_view", Vector2(_look.x, _look.y))
		_scene.call(&"zoom_view", _look.z)
	var chase: ChaseCamera = _scene.get_node_or_null("ChaseCamera") as ChaseCamera
	if _look.z > 0.0 and _frame == 20 and chase != null:
		# In a match: hold the view round by that many pixels of drag.
		chase.begin_look()
		chase.look_by(Vector2(_look.x, _look.y))
	if _rough_landing > 0.0 and _frame == 30:
		_drop_player()
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
