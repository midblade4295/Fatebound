extends SceneTree
# The app icon as a 3D render of the game's own models (Kevin: "I want a new game icon that is a 3d design that doesn't
# look like 'ai slop' that I got feedback with" -- the 0.31.200 icon was a gpt-image-2 painting). Every concept is the
# real thing: the heroes as the game builds them (siege_view.gd make_body, his outfit, a frame of his KayKit animation),
# the King's own model, lit like a studio portrait (a warm key with soft shadows, a fill, a rim light in the background's
# colour so the silhouette separates) and rendered with the desktop renderer's ambient occlusion, on a clear background:
# tools/build_app_icon.py puts the background behind it and makes the launcher, Play and App Store icons.
#   Xvfb :98 -screen 0 1080x1920x24 &
#   DISPLAY=:98 godot --rendering-method forward_plus --path godot -s res://tools/render_app_icon.gd
#   OUT_DIR=<dir> (default /tmp/fb_icon)  ONLY=id1,id2  SIZE=2048
#   (one shot's framing, to try it: ONLY=<id> CAM=x,y,z AIM=x,y,z FOV=deg TURN=deg AT=0..1)
const View = preload("res://scripts/siege/siege_view.gd")
const Stage = preload("res://scripts/siege/asset_cache.gd")

# id -> what's in it: "hero" (a hero id, or "king"), "skin" (an outfit, "" his own), "anim"/"at" (a frame of an
# animation, 0..1 of its length), "turn" (degrees about his up axis), the camera ("cam", "aim", "fov") and the rim
# light's colour ("rim": the background's hue, lighter). "with": more bodies in the shot, each {hero, anim, at, turn, pos}.
const SHOTS := {
	"king": {"hero":"king", "turn":-12.0, "cam":Vector3(0.45, 1.8, 4.4), "aim":Vector3(0.02, 2.1, 0.0), "fov":21.0,
		"rim":"#9fd0ff"},
	"knight": {"hero":"knight", "anim":"m/Melee_1H_Attack_Chop", "at":0.38, "turn":-40.0,
		"cam":Vector3(0.4, 1.2, 3.8), "aim":Vector3(-0.05, 1.45, 0.0), "fov":28.0, "rim":"#9fd0ff"},
}
# the launchers' adaptive icons show the middle 72 dp of a 108 dp layer and move it about: each shot is rendered that
# much wider (<id>_wide.png, MARGIN x the size, the same picture in its middle) for the foreground layer, and its middle
# is <id>.png -- the square icon (Play, App Store, the legacy launcher icon)
const MARGIN := 1.5

var out_dir := "/tmp/fb_icon"
var only: Array = []
var size := 2048
var vp: SubViewport
var cam: Camera3D
var holder: Node3D
var rim: OmniLight3D
var rim2: DirectionalLight3D

func _initialize() -> void:
	out_dir = OS.get_environment("OUT_DIR") if OS.has_environment("OUT_DIR") else out_dir
	if OS.has_environment("ONLY"):
		only = OS.get_environment("ONLY").split(",")
	if OS.has_environment("SIZE"):
		size = clampi(int(OS.get_environment("SIZE")), 128, 4096)
	DirAccess.make_dir_recursive_absolute(out_dir)
	RenderingServer.directional_shadow_atlas_set_size(8192, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_ULTRA)
	vp = SubViewport.new()
	vp.size = Vector2i(int(size * MARGIN), int(size * MARGIN))
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_8X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#c9d2e8")
	env.ambient_light_energy = _num("AMBIENT", 0.42) * View.VULKAN_AMBIENT
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = _num("EXPOSURE", 0.66) * View.VULKAN_EXPOSURE
	env.tonemap_white = 3.0
	env.ssao_enabled = true                          # (the creases: the beard under the crown, the armour's plates)
	env.ssao_radius = 0.35
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.15
	var sky := Sky.new()                             # (only for what shines: the gold reflects a studio's soft light)
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("#f4f0ea")
	sm.sky_horizon_color = Color("#b9c6dc")
	sm.ground_horizon_color = Color("#6d7890")
	sm.ground_bottom_color = Color("#2a3142")
	sm.sun_angle_max = 0.0
	sky.sky_material = sm
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()              # warm key, high and to the camera's left
	key.light_color = Color("#fff1dc")
	key.light_energy = _num("KEY", 1.35)
	key.rotation_degrees = Vector3(-38, -42, 0)
	key.shadow_enabled = true
	key.shadow_blur = 1.6
	key.shadow_bias = 0.02
	key.shadow_normal_bias = 1.2
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 12.0
	vp.add_child(key)
	var fill := DirectionalLight3D.new()             # cool, soft, from the right
	fill.light_color = Color("#cfe0ff")
	fill.light_energy = 0.32
	fill.rotation_degrees = Vector3(-8, 62, 0)
	vp.add_child(fill)
	rim = OmniLight3D.new()                          # behind him, up and to the right: the edge against the background
	rim.light_energy = _num("RIM", 10.0)
	rim.omni_range = 9.0
	rim.omni_attenuation = 0.6
	vp.add_child(rim)
	rim2 = DirectionalLight3D.new()                  # a second edge from behind-left
	rim2.light_energy = _num("RIM2", 3.0)
	rim2.rotation_degrees = Vector3(-20, 160, 0)
	vp.add_child(rim2)
	cam = Camera3D.new()
	vp.add_child(cam)
	holder = Node3D.new()
	vp.add_child(holder)
	_run()

func _num(k: String, dflt: float) -> float:
	return float(OS.get_environment(k)) if OS.has_environment(k) else dflt

func _v3(s: String, dflt: Vector3) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2])) if p.size() == 3 else dflt

func _clear() -> void:
	for c in holder.get_children():
		holder.remove_child(c)
		c.queue_free()

func _add(hero: String, anim: String, at: float, turn: float, pos: Vector3) -> bool:
	var body: Node3D
	if hero == "king":
		var packed := Stage.scene("res://assets/kings/king_blue_fat.glb")
		if packed == null:
			return false
		body = packed.instantiate()
		body.scale = Vector3.ONE * (View.KING_HEIGHT / 1.9)    # (as siege_view.gd places him)
		holder.add_child(body)
		if OS.get_environment("CLEAN") != "0":
			_clean_king(body)
	else:
		var made: Dictionary = View.make_body(hero, {})
		if made.is_empty():
			return false
		body = made.body
		holder.add_child(body)
		var pl: AnimationPlayer = made.player
		var an := anim if anim != "" else str(View.LOOKS.get(hero, View.LOOKS.knight).idle)
		if pl.has_animation(an):
			pl.play(an)
			pl.speed_scale = 0.0
			pl.seek(pl.get_animation(an).length * at, true)
		else:
			print("ICON_NO_ANIM ", hero, " ", an)
	body.position = pos
	body.rotation.y = deg_to_rad(turn)
	if OS.get_environment("SMOOTH") != "0":
		_smooth(body)
	if OS.get_environment("NORMALMAP") == "0":
		_no_normal_map(body)
	return true

func _png(path: String, mipmaps := true) -> ImageTexture:
	# straight from the PNG (the imported copies are VRAM-compressed for the phones)
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null:
		return null
	if mipmaps:
		img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _clean_king(body: Node3D) -> void:
	# tools/clean_king_texture.py's clean paint (art_sources/app_icon/king_clean): flat colours, gold that is metal
	var alb := _png("res://../art_sources/app_icon/king_clean/albedo.png")
	var orm := _png("res://../art_sources/app_icon/king_clean/orm.png")
	if alb == null or orm == null:
		print("ICON_NO_CLEAN_KING (run tools/clean_king_texture.py)")
		return
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		for s in m.mesh.get_surface_count():
			var mat := (m.get_active_material(s) as StandardMaterial3D).duplicate() as StandardMaterial3D
			mat.albedo_texture = alb
			mat.roughness = 1.0
			mat.roughness_texture = orm
			mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
			mat.metallic = 1.0
			mat.metallic_specular = 0.5
			mat.metallic_texture = orm
			mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
			mat.normal_enabled = false                # (its bumps are the facets of the Meshy sculpt: smooth instead)
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			m.set_surface_override_material(s, mat)

func _smooth(body: Node3D) -> void:
	# smooth shading: each vertex's normal the area-weighted mean of every face at its position (the models' vertices
	# are split along the texture's seams, so a plain per-index average would keep those seams as hard edges)
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var src: Mesh = (mi as MeshInstance3D).mesh
		if src == null or not (src is ArrayMesh):
			continue
		var out := ArrayMesh.new()
		for s in src.get_surface_count():
			var a: Array = src.surface_get_arrays(s)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if idx.is_empty():
				for i in v.size():
					idx.append(i)
			var key := PackedInt32Array()
			key.resize(v.size())
			var slot := {}
			var acc: Array[Vector3] = []
			for i in v.size():
				var k := Vector3i((v[i] * 4000.0).round())
				if not slot.has(k):
					slot[k] = acc.size()
					acc.append(Vector3.ZERO)
				key[i] = int(slot[k])
			for t in range(0, idx.size(), 3):
				var p0 := v[idx[t]]
				var n := (v[idx[t + 1]] - p0).cross(v[idx[t + 2]] - p0)     # (Godot's front faces are clockwise)
				for j in 3:
					acc[key[idx[t + j]]] -= n
			var nn := PackedVector3Array()
			nn.resize(v.size())
			var agree := 0.0
			var old: PackedVector3Array = a[Mesh.ARRAY_NORMAL] if a[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			for i in v.size():
				nn[i] = acc[key[i]].normalized()
				if i < old.size():
					agree += nn[i].dot(old[i])
			if agree < 0.0:                                                    # (the winding the other way after all)
				for i in v.size():
					nn[i] = -nn[i]
			a[Mesh.ARRAY_NORMAL] = nn
			a[Mesh.ARRAY_TANGENT] = null
			var fmt: int = (src as ArrayMesh).surface_get_format(s)
			out.add_surface_from_arrays(src.surface_get_primitive_type(s), a, [], {}, fmt & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
			out.surface_set_material(s, src.surface_get_material(s))
		(mi as MeshInstance3D).mesh = out

func _no_normal_map(body: Node3D) -> void:
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var mat = m.get_active_material(s)
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).normal_enabled:
				var c: BaseMaterial3D = mat.duplicate()
				c.normal_enabled = false
				m.set_surface_override_material(s, c)

func _run() -> void:
	for id in SHOTS:
		if not only.is_empty() and not only.has(id):
			continue
		var s: Dictionary = SHOTS[id]
		# (trying poses: ANIM=<animation> ATS=0.1,0.2,... renders <id>_<at>.png for each)
		var ats: Array = [float(OS.get_environment("AT")) if OS.has_environment("AT") else float(s.get("at", 0.3))]
		if OS.has_environment("ATS"):
			ats = Array(OS.get_environment("ATS").split(",")).map(func(x): return float(x))
		var anim := OS.get_environment("ANIM") if OS.has_environment("ANIM") else str(s.get("anim", ""))
		for at in ats:
			_clear()
			var turn := float(OS.get_environment("TURN")) if OS.has_environment("TURN") else float(s.get("turn", 0.0))
			if not _add(str(s.hero), anim, float(at), turn, Vector3.ZERO):
				print("ICON_FAIL ", id)
				break
			for w in s.get("with", []):
				_add(str(w.hero), str(w.get("anim", "")), float(w.get("at", 0.3)), float(w.get("turn", 0.0)), w.get("pos", Vector3.ZERO))
			var pos := _v3(OS.get_environment("CAM"), s.cam) if OS.has_environment("CAM") else s.cam as Vector3
			var aim := _v3(OS.get_environment("AIM"), s.aim) if OS.has_environment("AIM") else s.aim as Vector3
			var fov := float(OS.get_environment("FOV")) if OS.has_environment("FOV") else float(s.fov)
			cam.fov = rad_to_deg(2.0 * atan(MARGIN * tan(deg_to_rad(fov) * 0.5)))
			cam.transform = Transform3D(Basis.looking_at(aim - pos, Vector3.UP), pos)
			var rc := Color(str(s.get("rim", "#ffffff")))
			rim.light_color = rc
			rim2.light_color = rc
			rim.position = aim + Vector3(1.6, 1.4, -2.2)
			for i in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			var name: String = id if ats.size() == 1 else "%s_%.2f" % [id, float(at)]
			var img := vp.get_texture().get_image()
			img.save_png(out_dir.path_join("%s_wide.png" % name))
			var o := (img.get_width() - size) / 2
			img.get_region(Rect2i(o, o, size, size)).save_png(out_dir.path_join("%s.png" % name))
			print("ICON_DONE ", name)
	print("ICON_ALL_DONE")
	quit(0)
