extends SceneTree
# Fatebound trailer 4 (Kevin: "a new cinematic trailer -- show off the graphics and scenery; lead it to a climax with the
# title moving into the shot, the sun's light reflecting off it; same rules as trailer 2"). One shot per run:
#   godot --rendering-method mobile --resolution 1920x1080 --fixed-fps 30 --write-movie /tmp/trailer4/<shot>.avi \
#         --path . -s res://tools/trailer4_shots.gd        (SHOT=<shot>)
# Cameras are keyframed paths [t, eye, look] eased between keys. "golden" writes the sun's screen position per frame to
# /tmp/trailer4/golden_sun.json for the title pass (tools/trailer4_title_fx.py). HUD hidden, High-quality graphics on.
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Land = preload("res://scripts/siege/siege_land.gd")
const LENGTH := {"probe": 0.2, "sky": 5.5, "falls": 5.5, "river": 6.0, "island": 5.5, "hills": 5.0, "castle": 6.0, "deck": 5.0,
	"logs": 4.5, "clash": 5.0, "golden": 10.0}
# The finale's title: a 3D gold FATEBOUND (Luckiest Guy, extruded) flies in and turns to face the camera; a glint of the
# low sun sweeps across the letters as it settles (TITLE_IN..TITLE_SET, then GLINT_* for the sweep).
const TITLE_FONT := preload("res://assets/fonts/LuckiestGuy-Regular.ttf")
const TITLE_IN := 3.6
const TITLE_SET := 6.4
const GLINT_A := 5.6
const GLINT_B := 8.4
const TITLE_SHADER := """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
uniform vec3 gold : source_color = vec3(1.0, 0.70, 0.20);
uniform vec3 sky_top : source_color = vec3(0.30, 0.42, 0.66);
uniform vec3 sky_low : source_color = vec3(1.0, 0.70, 0.40);
uniform vec3 glint_dir = vec3(-1.0, 0.3, 0.6);     // world-space direction the glint's light comes from
uniform float glint = 0.0;                          // 0..1 strength of the sweep
uniform float face_tint = 1.0;
void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 r = reflect(-v, n);
	// fake environment: warm horizon below, cool sky above -- what polished gold would mirror at golden hour
	vec3 env = mix(sky_low, sky_top, smoothstep(-0.15, 0.55, r.y));
	float spec = pow(max(dot(r, normalize(glint_dir)), 0.0), 90.0) * 14.0 * glint;
	float sheen = pow(max(dot(r, normalize(glint_dir)), 0.0), 8.0) * 1.2 * glint;
	// side faces (normal across the view) darker: the extrusion reads as depth
	float facing = clamp(dot(n, v), 0.0, 1.0);
	ALBEDO = gold * mix(0.35, 0.8, facing);
	METALLIC = 0.75;
	ROUGHNESS = 0.32;
	EMISSION = gold * env * mix(0.06, 0.32, facing) * face_tint + vec3(1.0, 0.93, 0.78) * (spec + sheen);
}
"""
const SUN_DIR := Vector3(0.0, 0.16, -1.0)
var mode
var shot := "river"
var frames := 0
var t := 0.0
var path := []          # [[t, eye, look], ...]
var orbit := {}
var fov := 55.0
var sun_track := []
var walkers := {}
var beats := []
var title: MeshInstance3D = null
var title_mat: ShaderMaterial = null

func _init() -> void:
	shot = OS.get_environment("SHOT") if OS.has_environment("SHOT") else "river"
	mode = Mode.new()
	mode.hq_gfx = true
	root.add_child(mode)

func _golden_hour() -> void:
	var d := SUN_DIR.normalized()
	for l in mode.view.find_children("*", "DirectionalLight3D", true, false):
		var sun: DirectionalLight3D = l
		sun.global_transform.basis = Basis.looking_at(-d)
		sun.light_color = Color("#ffc98a")
		sun.light_energy = 1.25
		sun.light_angular_distance = 2.5
	for w in mode.view.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (w as WorldEnvironment).environment
		var sm := env.sky.sky_material as ProceduralSkyMaterial
		if sm != null:
			sm.sky_top_color = Color("#4d6fa8")
			sm.sky_horizon_color = Color("#ffb877")
			sm.ground_horizon_color = Color("#f6bf8c")
			sm.ground_bottom_color = Color("#f6bf8c")
			sm.sun_angle_max = 40.0
			sm.sun_curve = 0.08
		env.fog_light_color = Color("#f2c192")

func _morning() -> void:
	# A low warm sun from the east, long shadows across the hills (the scenery shots).
	var d := Vector3(1.0, 0.42, 0.35).normalized()
	for l in mode.view.find_children("*", "DirectionalLight3D", true, false):
		var sun: DirectionalLight3D = l
		sun.global_transform.basis = Basis.looking_at(-d)
		sun.light_color = Color("#ffe2bf")
		sun.light_energy = 1.15

func _stage() -> void:
	var s = mode.sim
	mode.hud.visible = false
	mode.hud.diag = null
	for u in s.units:
		u.bot = true
	# a living battlefield: let the bots play a while first
	var warm := 25.0 if shot in ["clash", "deck", "castle"] else 12.0
	for i in int(warm / Sim.TICK):
		s.step(Sim.TICK)
		s.drain_events()
	var fx := Land.FALL_X
	match shot:
		"sky":
			_morning()
			path = [[0.0, Vector3(70, 34, 52), Vector3(10, 70, -60)], [0.55, Vector3(68, 28, 44), Vector3(14, 26, -30)],
				[1.0, Vector3(66, 22, 36), Vector3(10, -2, 0)]]
		"falls":
			_morning()
			# along the river to the edge, then out over it: the water pouring down into the valley below
			var rc := Land.river_c(fx)
			path = [[0.0, Vector3(fx - 16, 5.0, rc + 7.0), Vector3(fx + 4.0, -6.0, rc)], [1.0, Vector3(fx - 3, 9.0, rc + 9.0), Vector3(fx + 14.0, -22.0, rc)]]
		"river":
			_morning()
			# a little higher than first cut (0.31.11 review: the island's bushes filled the lower frame mid-shot)
			path = [[0.0, Vector3(40, 5.6, 3.5), Vector3(-4, 0.4, 0)], [1.0, Vector3(13, 5.2, 2.5), Vector3(-18, 0.6, -1)]]
		"island":
			_morning()
			orbit = {"c": Vector3(0, 3.0, 0), "r": 17.0, "h": 8.5, "a0": 0.55, "a1": 1.75}
		"hills":
			_morning()
			path = [[0.0, Vector3(-14, 9.0, 47), Vector3(-30, 2.5, 26)], [1.0, Vector3(-24, 7.0, 40), Vector3(-36, 3.0, 22)]]
		"castle":
			_morning()
			path = [[0.0, Vector3(34, 24, 98), Vector3(0, 2, 64)], [1.0, Vector3(-26, 21, 100), Vector3(0, 3, 64)]]
		"deck":
			_morning()
			var op: Dictionary = s.outposts[0]
			op.owner = 0
			op.prog = 1.0
			var tp: Vector2 = op.p
			var archers: Array = s.units.filter(func(u): return u.team == 0).slice(1, 4)
			for k in archers.size():
				var a: Dictionary = archers[k]
				s._set_class(a, ["ranger", "mage", "ranger"][k], false)
				a.pos = tp + Vector2(Land.OUTPOST_TOWER_R + 0.8, 0).rotated(k * 0.6)
				s.act(a.id, "interact")
				a.face = Sim.angle_of(Vector2(8, -6))
			var foes: Array = s.units.filter(func(u): return u.team == 1).slice(0, 5)
			for k in foes.size():
				foes[k].pos = tp + Vector2(7.0 + k * 1.3, -6.0 - (k % 2) * 1.5)
			var g := Sim.height_at(tp)
			path = [[0.0, Vector3(tp.x - 5, g + 7.0, tp.y + 6.5), Vector3(tp.x + 6, g + 3.0, tp.y - 7)],
				[1.0, Vector3(tp.x - 7.5, g + 10.5, tp.y + 9), Vector3(tp.x + 7, g + 2.0, tp.y - 8)]]
		"logs":
			_morning()
			var best := {}
			var bs := -1.0
			for n in s.nodes:
				if n.kind == "wood":
					var gr: float = s._ground_grad(n.p).length()
					if gr > bs:
						bs = gr
						best = n
			var w: Dictionary = s.units.filter(func(u): return u.team == 0)[2]
			s._set_class(w, "worker", false)
			w.bot = false
			w.pos = (best.p as Vector2) + Vector2(best.r + 0.7, 0)
			set_meta("tree", best.id)
			set_meta("chopper", w.id)
			var c: Vector2 = best.p
			var gy := Sim.height_at(c)
			path = [[0.0, Vector3(c.x + 7, gy + 3.5, c.y + 6), Vector3(c.x - 1, gy + 0.8, c.y - 1)],
				[1.0, Vector3(c.x + 5, gy + 4.5, c.y + 8.5), Vector3(c.x - 3, gy + 0.2, c.y - 3)]]
		"clash":
			_morning()
			var bx := Land.SIDE_BRIDGE_X
			var blue: Array = s.units.filter(func(u): return u.team == 0)
			var red: Array = s.units.filter(func(u): return u.team == 1)
			for k in 8:
				blue[k].pos = Vector2(bx + (k % 3 - 1) * 1.2, 7.0 + k * 0.8)
				red[k].pos = Vector2(bx + (k % 3 - 1) * 1.2, -7.0 - k * 0.8)
				walkers[blue[k].id] = Vector2(0, -1)
				walkers[red[k].id] = Vector2(0, 1)
				blue[k].bot = false
				red[k].bot = false
			beats.append([1.6, "melee"])
			path = [[0.0, Vector3(bx + 9, 3.2, 6), Vector3(bx, 1.2, 0)], [1.0, Vector3(bx + 7, 4.5, -3), Vector3(bx - 1, 1.0, 0.5)]]
		"golden":
			for i in int(25.0 / Sim.TICK):
				s.step(Sim.TICK)
				s.drain_events()
			_golden_hour()
			path = [[0.0, Vector3(0.0, 22.0, 84.0), Vector3(0.0, 8.0, -40.0)], [1.0, Vector3(0.0, 32.0, 102.0), Vector3(0.0, 12.0, -40.0)]]
			_make_title()
	mode.view.camera.fov = fov
	_apply_cam(0.0)
	mode.view.snap_camera()

func _make_title() -> void:
	var tm := TextMesh.new()
	tm.text = "FATEBOUND"
	tm.font = TITLE_FONT
	tm.font_size = 64
	tm.pixel_size = 0.042
	tm.depth = 0.5
	tm.curve_step = 0.6
	title = MeshInstance3D.new()
	title.mesh = tm
	title_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = TITLE_SHADER
	title_mat.shader = sh
	title.material_override = title_mat
	title.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	title.visible = false
	mode.view.add_child(title)

func _place_title(tt: float) -> void:
	# In camera space: flies in from high and far off to the right, turning from edge-on to face the camera, and settles
	# a little above centre; a slow drift after. The glint sweeps across the letters as it settles.
	if title == null:
		return
	var cam: Camera3D = mode.view.camera
	var k := clampf((tt - TITLE_IN) / (TITLE_SET - TITLE_IN), 0.0, 1.0)
	title.visible = tt >= TITLE_IN
	var e := 1.0 - pow(1.0 - k, 3.0)                       # ease out: fast in, gentle landing
	var settle := Vector3(0.0, 1.25, -15.0)                # camera space: above centre, 15 m ahead
	var start := Vector3(9.0, 5.0, -38.0)
	var drift := Vector3(0.0, 0.08 * maxf(tt - TITLE_SET, 0.0), 0.35 * maxf(tt - TITLE_SET, 0.0))
	var local := start.lerp(settle, e) + drift
	var yaw := lerpf(-1.25, 0.0, e) + 0.03 * sin(tt * 0.9)
	var pitch := lerpf(0.35, -0.06, e)
	var b := cam.global_transform.basis * Basis.from_euler(Vector3(pitch, yaw, 0.0))
	title.global_transform = Transform3D(b, cam.global_transform * local)
	var g := clampf((tt - GLINT_A) / (GLINT_B - GLINT_A), 0.0, 1.0)
	var sweep := lerpf(-1.4, 1.4, g)                        # the glint light swings across: left -> right
	var gd := cam.global_transform.basis * Vector3(sin(sweep) * 0.9, 0.35, cos(sweep) * 0.9)
	title_mat.set_shader_parameter("glint_dir", gd)
	title_mat.set_shader_parameter("glint", sin(g * PI) * 1.0 + (0.25 if tt >= GLINT_B else 0.0))

func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)

func _apply_cam(u: float) -> void:
	if not orbit.is_empty():
		var ang: float = lerpf(orbit.a0, orbit.a1, _ease(u))
		var c: Vector3 = orbit.c
		mode.view.cam_override = [c + Vector3(sin(ang) * orbit.r, orbit.h, cos(ang) * orbit.r), c]
		return
	if path.is_empty():
		return
	var k := 0
	while k < path.size() - 2 and u > float(path[k + 1][0]):
		k += 1
	var a: Array = path[k]
	var b: Array = path[mini(k + 1, path.size() - 1)]
	var span := maxf(float(b[0]) - float(a[0]), 0.001)
	var e := _ease(clampf((u - float(a[0])) / span, 0.0, 1.0))
	mode.view.cam_override = [(a[1] as Vector3).lerp(b[1], e), (a[2] as Vector3).lerp(b[2], e)]

func _process(delta: float) -> bool:
	frames += 1
	if OS.has_environment("FRAMELOG"):
		printerr("F %d %.2f" % [frames, Time.get_ticks_msec() / 1000.0])
	mode._guard_clock = -1.0e9
	if frames == 2:
		_stage()
	if frames < 2:
		return false
	t += delta
	if OS.has_environment("STILL_AT") and frames == 3:
		t = float(OS.get_environment("STILL_AT"))
	var s = mode.sim
	mode.view.camera.fov = fov
	_apply_cam(clampf(t / float(LENGTH[shot]), 0.0, 1.0))
	for id in walkers:
		s.by_id[id].move = walkers[id]
	for b in beats.duplicate():
		if t >= float(b[0]) and str(b[1]) == "melee":
			beats.erase(b)
			walkers.clear()
			for u in s.units:
				u.bot = true
	if shot == "logs" and t >= 0.6 and not has_meta("felled"):
		set_meta("felled", true)
		var n: Dictionary = s.nodes[int(get_meta("tree"))]
		var w: Dictionary = s.by_id[str(get_meta("chopper"))]
		n.amount = 0
		s._fell_node(n, w.pos)
		mode.view.on_event({"k":"node_fell", "node":n.id, "kind":"wood", "pos":n.p})
	if shot == "golden":
		_place_title(t)
		var cam: Camera3D = mode.view.camera
		var far := cam.global_position + SUN_DIR.normalized() * 3000.0
		var sp := cam.unproject_position(far)
		var vs := root.get_visible_rect().size
		sun_track.append([sp.x / vs.x, sp.y / vs.y, not cam.is_position_behind(far)])
	if OS.has_environment("STILL_AT") and frames == 6:
		root.get_texture().get_image().save_png("/tmp/trailer4/still_%s.png" % shot)
		printerr("SHOT_DONE %s still" % shot)
		quit(0)
		return false
	if t >= float(LENGTH[shot]):
		if shot == "golden":
			var f := FileAccess.open("/tmp/trailer4/golden_sun.json", FileAccess.WRITE)
			f.store_string(JSON.stringify(sun_track))
			f.close()
		printerr("SHOT_DONE %s %d frames" % [shot, frames])
		quit(0)
	return false
