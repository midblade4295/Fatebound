# Godot's GPU particles (real renderer: run under Xvfb with Vulkan, see particles.sh) for the setups in
# particles_cases.txt, printing every frame's capture_aabb() -- the RenderingServer reading the particle buffer back
# (positions of every particle with non-zero flags, node-local) -- as `pt|case|frame|px py pz sx sy sz`.
# tools/parity/particles.sh compares the de-duplicated sequences with `guitest particles-parity` (ParticlesSim).
extends SceneTree

const FRAMES := 150
var systems := {}
var order := []
var frame := 0


func vec3(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())


func curve(s: String) -> Curve:
	var c := Curve.new()
	for pt in s.split(","):
		var xy := pt.split(":")
		c.add_point(Vector2(xy[0].to_float(), xy[1].to_float()))
	return c


func value(t: String, s: String):
	match t:
		"i":
			return s.to_int()
		"f":
			return s.to_float()
		"b":
			return s == "true"
		"v3":
			return vec3(s)
		"xf":
			var p := s.split(",")
			return Transform3D(Basis(Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float()).normalized(), p[3].to_float()),
					Vector3(p[4].to_float(), p[5].to_float(), p[6].to_float()))
		"curve":
			var ct := CurveTexture.new()
			ct.curve = curve(s)
			return ct
		"curvexyz":
			var cs := s.split(";")
			var cx := CurveXYZTexture.new()
			cx.curve_x = curve(cs[0])
			cx.curve_y = curve(cs[1])
			cx.curve_z = curve(cs[2])
			return cx
	return null


func _initialize() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 30)
	root.add_child(cam)
	var f := FileAccess.open("res://particles_cases.txt", FileAccess.READ)
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var p := line.split("|")
		var name: String = p[0]
		if not systems.has(name):
			var n := GPUParticles3D.new()
			n.use_fixed_seed = true
			n.visibility_aabb = AABB(Vector3(-1000, -1000, -1000), Vector3(2000, 2000, 2000))
			n.draw_pass_1 = PointMesh.new()
			n.process_material = ParticleProcessMaterial.new()
			systems[name] = n
			order.append(name)
		var target: Object = systems[name] if p[1] == "node" else systems[name].process_material
		target.set(p[2], value(p[3], p[4]))
	for name in order:
		root.add_child(systems[name])


func _process(_delta: float) -> bool:
	frame += 1
	for name in order:
		var a: AABB = systems[name].capture_aabb()
		print("pt|%s|%d|%.6f %.6f %.6f %.6f %.6f %.6f" % [name, frame, a.position.x, a.position.y, a.position.z, a.size.x, a.size.y, a.size.z])
	return frame >= FRAMES
