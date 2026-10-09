extends RefCounted
# 0.31.79: the Meshy chests in the menus (baked by tools/chest_bake.gd: 1.6 m wide, base at y 0, front +Z, the lid hung
# from a "Lid" pivot at its back edge). make() adds the treasure's light; pose() animates idle / tease / open.
const DIR := "res://assets/ui/v2/chests/"
const KIND := {"wooden": "wood", "wood": "wood", "silver": "silver", "gold": "gold", "royal": "royal"}
const GLOW := {"wood": Color("#ffcf6a"), "silver": Color("#bfe2ff"), "gold": Color("#ffd76a"), "royal": Color("#e2a8ff")}

static func make(kind: String) -> Node3D:
	var k: String = KIND.get(kind, "wood")
	var ps: PackedScene = load(DIR + "%s.scn" % k)
	var root := Node3D.new()
	var body: Node3D = ps.instantiate()
	body.name = "Body"
	root.add_child(body)
	var seam := float(body.get_meta("seam", 0.6))
	var depth := float(body.get_meta("depth", 1.0))
	var light := OmniLight3D.new()
	light.name = "Glow"
	light.light_color = GLOW[k]
	light.omni_range = 2.2
	light.light_energy = 0.0
	light.position = Vector3(0.0, seam + 0.15, 0.0)
	body.add_child(light)
	var card := MeshInstance3D.new()
	card.name = "Card"
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.45, depth * 0.9)
	card.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var gc: Color = GLOW[k]
	gm.albedo_color = Color(gc.r * 1.9, gc.g * 1.6, gc.b * 1.1)
	card.material_override = gm
	card.position = Vector3(0.0, seam - 0.06, 0.0)
	card.visible = false
	body.add_child(card)
	root.set_meta("seam", seam)
	return root

static func _ease_out_back(x: float) -> float:
	var c1 := 1.9
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)

static func pose(root: Node3D, mode: String, t: float, phase := 0.0) -> void:
	# mode: "idle" (a slow breath), "tease" (ready to open: a hop and a rattle every couple of seconds with light
	# leaking out of the lid), "open" (t seconds into the 1.6 s opening: shake, pop, the lid flies open, light spills out),
	# "opened" (held open).
	var body: Node3D = root.get_node("Body")
	var lid: Node3D = body.get_node("Lid")
	var light: OmniLight3D = body.get_node("Glow")
	var card: MeshInstance3D = body.get_node("Card")
	var lid_deg := 0.0
	var y := 0.0
	var sx := 1.0
	var sy := 1.0
	var rz := 0.0
	var glow := 0.0
	match mode:
		"idle":
			var p := (t + phase) / 2.4 * TAU
			y = 0.03 * (0.5 - 0.5 * cos(p))
			sy = 1.0 + 0.02 * sin(p)
			sx = 1.0 - 0.012 * sin(p)
		"tease":
			var cyc := fmod(t + phase, 2.2)
			var p := (t + phase) / 2.2 * TAU
			y = 0.03 * (0.5 - 0.5 * cos(p))
			if cyc > 1.55:
				var a := (cyc - 1.55) / 0.65
				rz = sin(a * PI * 6.0) * 5.0 * sin(a * PI)
				y += 0.14 * sin(a * PI)
				lid_deg = -14.0 * sin(a * PI)
				glow = sin(a * PI)
		"open":
			if t < 0.45:
				var a := t / 0.45
				rz = sin(t * 48.0) * 5.0 * a
				sy = 1.0 - 0.1 * a
				sx = 1.0 + 0.06 * a
			elif t < 0.62:
				var b := (t - 0.45) / 0.17
				sy = lerpf(0.9, 1.14, b)
				sx = lerpf(1.06, 0.94, b)
				y = 0.3 * sin(b * PI * 0.5)
				lid_deg = -112.0 * _ease_out_back(clampf(b, 0.0, 1.0)) * 0.55
				glow = b
			else:
				var c := clampf((t - 0.62) / 0.4, 0.0, 1.0)
				lid_deg = lerpf(-61.6, -108.0, _ease_out_back(c))
				y = 0.3 * (1.0 - c) * (1.0 - c)
				var land := clampf((t - 0.85) / 0.25, 0.0, 1.0)
				sy = 1.0 + 0.08 * sin(land * PI) * (1.0 - land) - 0.02 * sin(land * PI)
				sx = 1.0 - 0.04 * sin(land * PI) * (1.0 - land)
				glow = 1.0
		"opened":
			lid_deg = -108.0
			glow = 0.85 + 0.15 * sin(t * 3.0)
	body.position = Vector3(0.0, y, 0.0)
	body.scale = Vector3(sx, sy, sx)
	body.rotation = Vector3(0.0, 0.0, deg_to_rad(rz))
	lid.rotation = Vector3(deg_to_rad(lid_deg), 0.0, 0.0)
	light.light_energy = 1.6 * glow
	card.visible = glow > 0.05

static func stage(world: Node3D) -> void:
	# The lights and environment the chests are lit with (a warm key, a cool rim).
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.82, 0.95)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#ffe6c0")
	sun.light_energy = 1.35
	world.add_child(sun)
	sun.look_at_from_position(Vector3(2.0, 4.0, 3.5), Vector3.ZERO, Vector3.UP)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("#9cc0ff")
	rim.light_energy = 1.2
	world.add_child(rim)
	rim.look_at_from_position(Vector3(-3.0, 2.5, -3.0), Vector3.ZERO, Vector3.UP)

static func viewport_ratio(c: Control) -> float:
	var logical := c.get_viewport().get_visible_rect().size
	var window := Vector2(DisplayServer.window_get_size())
	if logical.x > 0 and window.x > 0:
		return clampf(window.x / logical.x, 1.0, 4.0)
	return 1.0
