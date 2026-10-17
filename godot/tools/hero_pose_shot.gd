extends SceneTree
# 0.31.168: review shots of heroes in their gear -- each look in LOOKS posed in each clip of CLIPS (at T seconds into
# it), seen from each angle of YAWS, one row per clip, saved to OUT/<look>.png.
#   DISPLAY=:98 godot --rendering-method mobile --path godot -s res://tools/hero_pose_shot.gd
#   LOOKS=golem,dragoon  CLIPS=idle,attack,ability (or library/clip names)  T=0.35  YAWS=-30,60,150  OUT=/tmp/poses
const View = preload("res://scripts/siege/siege_view.gd")
const SIZE := Vector2i(300, 380)

var vp: SubViewport
var cam: Camera3D
var holder: Node3D

func _initialize() -> void:
	vp = SubViewport.new()
	vp.size = SIZE
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#56606e")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#cfd6ea")
	env.ambient_light_energy = 0.55 * View.VULKAN_AMBIENT
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85 * View.VULKAN_EXPOSURE
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color("#fff0d6")
	key.light_energy = 1.25
	key.rotation_degrees = Vector3(-35, -30, 0)
	vp.add_child(key)
	cam = Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	holder = Node3D.new()
	vp.add_child(holder)
	_run()

func _env(k: String, d: String) -> String:
	return OS.get_environment(k) if OS.has_environment(k) else d

func _run() -> void:
	var looks := _env("LOOKS", "golem").split(",")
	var clips := _env("CLIPS", "idle,attack").split(",")
	var t := float(_env("T", "0.35"))
	var yaws := _env("YAWS", "-30,60,150").split(",")
	var out := _env("OUT", "/tmp/poses")
	DirAccess.make_dir_recursive_absolute(out)
	for look in looks:
		var lk: Dictionary = View.LOOKS.get(look, {})
		var sheet := Image.create(SIZE.x * yaws.size(), SIZE.y * clips.size(), false, Image.FORMAT_RGBA8)
		for ci in clips.size():
			var clip := str(clips[ci])
			if clip in ["idle", "attack", "ability"]:
				clip = str(lk.get(clip, "g/Idle_A"))
			for yi in yaws.size():
				for c in holder.get_children():
					c.free()
				var made: Dictionary = View.make_body(look)
				var body: Node3D = made.body
				holder.add_child(body)
				body.scale = Vector3.ONE * View.BODY_SCALE
				body.rotation.y = deg_to_rad(float(yaws[yi]))
				var pl: AnimationPlayer = made.player
				if pl != null and pl.has_animation(clip):
					pl.play(clip)
					pl.seek(t, true)
				var cpos := Vector3(0.0, 1.5, 7.4)
				cam.transform = Transform3D(Basis.looking_at(Vector3(0, 1.15, 0) - cpos, Vector3.UP), cpos)
				for i in 3:
					await process_frame
				await RenderingServer.frame_post_draw
				var img := vp.get_texture().get_image()
				img.convert(Image.FORMAT_RGBA8)
				sheet.blit_rect(img, Rect2i(Vector2i.ZERO, SIZE), Vector2i(SIZE.x * yi, SIZE.y * ci))
		sheet.save_png(out.path_join("%s.png" % look))
		print("POSE_DONE ", look)
	quit(0)
