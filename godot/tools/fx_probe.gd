extends SceneTree
# A probe for spell_fx.gd's pieces on their own: a camera, a floor, the module, and a few bursts (parented to a moving
# node or not), shot after a second. DISPLAY=:97 godot --rendering-method mobile --fixed-fps 30 --resolution 800x800 --path godot -s res://tools/fx_probe.gd
const SpellFx = preload("res://scripts/siege/spell_fx.gd")
var frames := 0
var fxs
var mover: Node3D
var fake_view

class FakeView extends Node3D:
	var low_fx := false
	var sim = null
	var actors := {}
	func shake(_k: float) -> void: pass
	func _shake_near(_p, _r, _k) -> void: pass
	static func _smoke_draw_mat() -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = preload("res://assets/vfx/smoke/smoke_puff.png")
		return m

func _init() -> void:
	var w := Node3D.new()
	root.add_child(w)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 9, 8)
	cam.look_at_from_position(cam.position, Vector3(0, 0.5, 0), Vector3.UP)
	w.add_child(cam)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-1.0, 0.4, 0)
	w.add_child(light)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.6, 0.25)
	floor.material_override = fm
	w.add_child(floor)
	fake_view = FakeView.new()
	w.add_child(fake_view)
	fxs = SpellFx.new()
	fxs.view = fake_view
	fake_view.add_child(fxs)
	mover = Node3D.new()
	mover.position = Vector3(-3, 0, 0)
	w.add_child(mover)
	RenderingServer.frame_post_draw.connect(func():
		if frames == 40 or frames == 70:
			root.get_texture().get_image().save_png("/tmp/claude-0/-home-claude/e4fc224e-d3ca-520a-b893-0d1f5b60b186/scratchpad/fx/probe_%d.png" % frames)
			print("PROBE ", frames))

func _process(delta: float) -> bool:
	frames += 1
	if frames == 5:
		# the same flame stream three ways: free in the world, parented to a still node, parented to a moving node
		fxs.burst(Vector3(3, 0.2, 0), Color("#ff4a2a"), {"n":14, "life":0.6, "size":0.7, "tex":"flame", "core":0.7, "shape":"ring", "r":0.6,
			"inner":0.3, "h":0.3, "dir":Vector3.UP, "spread":20.0, "vel":[1.0, 2.0], "grav":Vector3(0, 2.0, 0), "shape_life":"shrink",
			"fade":"hot", "angle":12.0, "spin":20.0, "dur":30.0, "explode":0.0})
		fxs.burst(Vector3(0, 0.2, 0), Color("#ff4a2a"), {"n":14, "life":0.6, "size":0.7, "tex":"flame", "core":0.7, "shape":"ring", "r":0.6,
			"inner":0.3, "h":0.3, "dir":Vector3.UP, "spread":20.0, "vel":[1.0, 2.0], "grav":Vector3(0, 2.0, 0), "shape_life":"shrink",
			"fade":"hot", "angle":12.0, "spin":20.0, "dur":30.0, "explode":0.0, "parent":mover})
		fxs.shell(mover, Color("#7a0c0c"), 1.0, 2.3, 2, 1e9, {"energy":1.2, "speed":3.0, "in":0.3})
	if frames > 5:
		mover.position.x += delta * 0.5
	fxs.step(delta)
	if frames > 75:
		quit(0)
	return false
