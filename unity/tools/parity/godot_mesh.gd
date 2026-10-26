# Mesh building and material resources in Godot, printed line by line for tools/parity/mesh.sh, which diffs them with
# `guitest mesh` (tools/guitest/MeshTest.cs, the C# port in GUI/Scene3D printing the same lines).
#   prim|<case>|...      every PrimitiveMesh (default and changed settings): get_mesh_arrays() per array (count + md5 of
#                        the bytes), AABB, lightmap size hint
#   st|<case>|...        SurfaceTool: commit_to_arrays() after index / deindex / generate_normals / generate_tangents /
#                        create_from / append_from / triangle fans / custom channels and skin; commit() read back
#   im|<case>|...        ImmediateMesh surfaces read back
#   prop|<class>|<name>|<value>   every stored property's default (StandardMaterial3D, ORMMaterial3D,
#                        ParticleProcessMaterial, NoiseTexture2D, FastNoiseLite, CurveTexture, CurveXYZTexture,
#                        PhysicsMaterial, the primitive meshes) -- the C# side reads these names from this output
#   noise|<case>|...     FastNoiseLite samples (2D / 3D / 1D grids, md5 of the float32 values) for every noise type,
#                        fractal, cellular distance / return type and domain warp setting
#   img|<case>|...       Noise.get_image / get_seamless_image and NoiseTexture2D images (format, size, md5 of the
#                        pixels without mipmaps)
#   curve|<case>|...     CurveTexture / CurveXYZTexture texels (sample_baked at i / width, as _update writes them)
# FB_MESH_FULL=1 also prints every element (as hex bytes) after each array line, to find the first difference.
extends SceneTree

const ARRAY_NAMES = ["vertex", "normal", "tangent", "color", "uv", "uv2", "custom0", "custom1", "custom2", "custom3", "bones", "weights", "index"]
var full := false
var frames := 0
var textures := []


func f6(x: float) -> String:
	var s := "%.6f" % x
	if s == "-0.000000":
		s = "0.000000"
	return s


func fmt(v) -> String:
	match typeof(v):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_INT:
			return str(v)
		TYPE_FLOAT:
			return f6(v)
		TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(v)
		TYPE_VECTOR2:
			return "(%s, %s)" % [f6(v.x), f6(v.y)]
		TYPE_VECTOR2I:
			return "(%d, %d)" % [v.x, v.y]
		TYPE_VECTOR3:
			return "(%s, %s, %s)" % [f6(v.x), f6(v.y), f6(v.z)]
		TYPE_VECTOR3I:
			return "(%d, %d, %d)" % [v.x, v.y, v.z]
		TYPE_COLOR:
			return "(%s, %s, %s, %s)" % [f6(v.r), f6(v.g), f6(v.b), f6(v.a)]
		TYPE_AABB:
			return "[%s, %s]" % [fmt(v.position), fmt(v.size)]
		TYPE_OBJECT:
			return "null" if v == null else v.get_class()
	return str(v)


func elem_size(a) -> int:
	match typeof(a):
		TYPE_PACKED_VECTOR3_ARRAY:
			return 12
		TYPE_PACKED_VECTOR2_ARRAY:
			return 8
		TYPE_PACKED_COLOR_ARRAY:
			return 16
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT32_ARRAY:
			return 4
		TYPE_PACKED_BYTE_ARRAY:
			return 1
	return 0


func arr(prefix: String, key: String, a) -> void:
	if a == null:
		print(prefix, "|", key, "|none")
		return
	var b: PackedByteArray = a if typeof(a) == TYPE_PACKED_BYTE_ARRAY else a.to_byte_array()
	print(prefix, "|", key, "|", type_string(typeof(a)), "|", a.size(), "|", b.hex_encode().md5_text())
	if full:
		var es := elem_size(a)
		for i in a.size():
			print(prefix, "|", key, "|", i, "|", b.slice(i * es, i * es + es).hex_encode())


func dump_arrays(prefix: String, arrays: Array) -> void:
	for k in Mesh.ARRAY_MAX:
		arr(prefix, ARRAY_NAMES[k], arrays[k])


func dump_mesh(prefix: String, m: Mesh) -> void:
	print(prefix, "|surfaces|", m.get_surface_count())
	for s in m.get_surface_count():
		dump_arrays(prefix + "|s" + str(s), m.surface_get_arrays(s))
		print(prefix, "|s", s, "|format|", int(RenderingServer.mesh_get_surface(m.get_rid(), s)["format"]) & 8191)
		print(prefix, "|s", s, "|primitive|", int(RenderingServer.mesh_get_surface(m.get_rid(), s)["primitive"]))
	print(prefix, "|aabb|", fmt(m.get_aabb()))


# ---------------------------------------------------------------------------------------------- primitive meshes
func prim(name: String, m: PrimitiveMesh) -> void:
	var p := "prim|" + name
	dump_arrays(p, m.get_mesh_arrays())
	print(p, "|aabb|", fmt(m.get_aabb()))
	print(p, "|lightmap|", fmt(m.lightmap_size_hint))


func primitives() -> void:
	prim("box_default", BoxMesh.new())
	var box := BoxMesh.new()
	box.size = Vector3(2, 1, 3)
	box.subdivide_width = 2
	box.subdivide_height = 3
	box.subdivide_depth = 1
	prim("box_custom", box)
	box = BoxMesh.new()
	box.flip_faces = true
	prim("box_flip", box)
	box = BoxMesh.new()
	box.add_uv2 = true
	box.uv2_padding = 4.0
	prim("box_uv2", box)

	prim("capsule_default", CapsuleMesh.new())
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 1.5
	cap.radial_segments = 12
	cap.rings = 3
	prim("capsule_custom", cap)
	cap = CapsuleMesh.new()
	cap.add_uv2 = true
	prim("capsule_uv2", cap)

	prim("cylinder_default", CylinderMesh.new())
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.2
	cyl.bottom_radius = 0.6
	cyl.height = 1.2
	cyl.radial_segments = 10
	cyl.rings = 2
	cyl.cap_top = false
	prim("cylinder_custom", cyl)
	cyl = CylinderMesh.new()
	cyl.top_radius = 0.0
	cyl.cap_bottom = false
	cyl.flip_faces = true
	prim("cylinder_cone", cyl)
	cyl = CylinderMesh.new()
	cyl.add_uv2 = true
	prim("cylinder_uv2", cyl)

	prim("plane_default", PlaneMesh.new())
	var pl := PlaneMesh.new()
	pl.size = Vector2(3, 2)
	pl.subdivide_width = 2
	pl.subdivide_depth = 3
	pl.center_offset = Vector3(0.1, 0.2, 0.3)
	pl.orientation = PlaneMesh.FACE_X
	prim("plane_custom", pl)
	pl = PlaneMesh.new()
	pl.orientation = PlaneMesh.FACE_Z
	pl.add_uv2 = true
	prim("plane_z_uv2", pl)

	prim("quad_default", QuadMesh.new())
	var q := QuadMesh.new()
	q.size = Vector2(2, 1)
	q.orientation = PlaneMesh.FACE_Y
	q.center_offset = Vector3(0, 0.5, 0)
	prim("quad_custom", q)

	prim("prism_default", PrismMesh.new())
	var pr := PrismMesh.new()
	pr.left_to_right = 0.2
	pr.size = Vector3(1, 2, 3)
	pr.subdivide_width = 1
	pr.subdivide_height = 2
	pr.subdivide_depth = 3
	prim("prism_custom", pr)
	pr = PrismMesh.new()
	pr.add_uv2 = true
	prim("prism_uv2", pr)

	prim("sphere_default", SphereMesh.new())
	var sp := SphereMesh.new()
	sp.radius = 0.7
	sp.height = 1.0
	sp.radial_segments = 16
	sp.rings = 8
	sp.is_hemisphere = true
	prim("sphere_custom", sp)
	sp = SphereMesh.new()
	sp.radial_segments = 12
	sp.rings = 6
	sp.add_uv2 = true
	prim("sphere_uv2", sp)

	prim("torus_default", TorusMesh.new())
	var t := TorusMesh.new()
	t.inner_radius = 0.3
	t.outer_radius = 0.8
	t.rings = 12
	t.ring_segments = 6
	prim("torus_custom", t)
	t = TorusMesh.new()
	t.rings = 10
	t.ring_segments = 5
	t.add_uv2 = true
	prim("torus_uv2", t)

	prim("point_default", PointMesh.new())


# ---------------------------------------------------------------------------------------------- SurfaceTool
func quad_verts(st: SurfaceTool, with_normals: bool) -> void:
	var pts := [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0.2), Vector3(0, 0, 0), Vector3(1, 1, 0.2), Vector3(0, 1, 0),
			Vector3(1, 0, 0), Vector3(2, 0, -0.3), Vector3(2, 1, 0), Vector3(1, 0, 0), Vector3(2, 1, 0), Vector3(1, 1, 0.2)]
	for i in pts.size():
		var v: Vector3 = pts[i]
		st.set_color(Color(v.x * 0.4, v.y * 0.7, 0.25 + v.z, 1.0 - 0.05 * i))
		st.set_uv(Vector2(v.x * 0.5, 1.0 - v.y))
		if with_normals:
			st.set_normal(Vector3(0.1 * i, 0.3, 1.0).normalized())
		st.add_vertex(v)


func grid_verts(st: SurfaceTool, n: int) -> void:
	for y in n:
		for x in n:
			var c := [Vector2(x, y), Vector2(x + 1, y), Vector2(x + 1, y + 1), Vector2(x, y), Vector2(x + 1, y + 1), Vector2(x, y + 1)]
			for p in c:
				var h: float = sin(p.x * 1.3) * 0.4 + cos(p.y * 0.7) * 0.3
				st.set_uv(Vector2(p.x / n, p.y / n))
				st.set_smooth_group(0 if p.x < 2 else 1)
				st.add_vertex(Vector3(p.x, h, p.y))


func surface_tool() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	quad_verts(st, true)
	dump_arrays("st|basic", st.commit_to_arrays())
	print("st|basic|aabb|", fmt(st.get_aabb()))
	st.index()
	dump_arrays("st|basic_indexed", st.commit_to_arrays())
	st.deindex()
	dump_arrays("st|basic_deindexed", st.commit_to_arrays())
	st.index()
	var m := st.commit()
	dump_mesh("st|basic_commit", m)

	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	quad_verts(st, false)
	st.generate_normals()
	dump_arrays("st|quad_normals", st.commit_to_arrays())
	dump_mesh("st|quad_normals_commit", st.commit())

	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	grid_verts(st, 4)
	st.generate_normals()
	dump_arrays("st|grid_normals", st.commit_to_arrays())
	st.generate_tangents()
	dump_arrays("st|grid_tangents", st.commit_to_arrays())
	st.index()
	dump_arrays("st|grid_indexed", st.commit_to_arrays())
	dump_mesh("st|grid_commit", st.commit())

	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	grid_verts(st, 3)
	st.index()
	st.generate_normals(true)
	st.generate_tangents()
	dump_arrays("st|grid_flat_flip", st.commit_to_arrays())

	var box := BoxMesh.new()
	box.subdivide_width = 1
	st = SurfaceTool.new()
	st.create_from(box, 0)
	dump_arrays("st|from_box", st.commit_to_arrays())
	st.generate_normals()
	st.generate_tangents()
	dump_arrays("st|from_box_regen", st.commit_to_arrays())
	dump_mesh("st|from_box_commit", st.commit())

	var sph := SphereMesh.new()
	sph.radial_segments = 8
	sph.rings = 4
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(sph, 0, Transform3D(Basis(Vector3(0.3, 1, 0.2).normalized(), 0.7).scaled(Vector3(1, 2, 0.5)), Vector3(1, -2, 3)))
	st.append_from(box, 0, Transform3D(Basis(), Vector3(0, 0, 0)))
	dump_arrays("st|append", st.commit_to_arrays())
	st.deindex()
	st.generate_normals()
	st.index()
	dump_arrays("st|append_renormal", st.commit_to_arrays())

	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.add_triangle_fan(PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0), Vector3(-0.5, 0.5, 0)]),
			PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(-0.5, 0.5)]),
			PackedColorArray([Color.RED, Color.GREEN, Color.BLUE, Color.WHITE, Color(0.2, 0.3, 0.4, 0.5)]))
	dump_arrays("st|fan", st.commit_to_arrays())

	st = SurfaceTool.new()
	st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA8_UNORM)
	st.set_custom_format(1, SurfaceTool.CUSTOM_RGBA_FLOAT)
	st.set_custom_format(2, SurfaceTool.CUSTOM_RG_HALF)
	st.set_custom_format(3, SurfaceTool.CUSTOM_RGBA8_SNORM)
	for i in 6:
		st.set_custom(0, Color(0.1 * i, 0.5, 1.2, -0.1))
		st.set_custom(1, Color(i, -i * 0.5, 0.25, 7.0))
		st.set_custom(2, Color(0.333 * i, -1.5, 0, 0))
		st.set_custom(3, Color(-0.7, 0.3 * i, 1.0, -1.0))
		st.set_bones(PackedInt32Array([i, i + 1, 0, 3]))
		st.set_weights(PackedFloat32Array([0.5, 0.3, 0.2 - 0.01 * i, 0.01 * i]))
		st.add_vertex(Vector3(i, i % 2, -i * 0.5))
	dump_arrays("st|custom_skin", st.commit_to_arrays())

	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for i in 8:
		st.set_color(Color(0.1 * i, 0.2, 0.3))
		st.add_vertex(Vector3(i % 3, i % 2, 0.5 * (i % 4)))
	st.index()
	dump_arrays("st|lines", st.commit_to_arrays())
	dump_mesh("st|lines_commit", st.commit())


# ---------------------------------------------------------------------------------------------- ImmediateMesh
func immediate() -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 9:
		var a := i * 0.7
		im.surface_set_normal(Vector3(cos(a), 0.4, sin(a)).normalized())
		im.surface_set_color(Color(0.1 * i, 1.0 - 0.1 * i, 0.5, 1.0))
		im.surface_set_uv(Vector2(0.1 * i, 0.2))
		im.surface_add_vertex(Vector3(cos(a) * 2.0, i * 0.25, sin(a)))
	im.surface_end()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(Vector3(0, 0, 0))
	im.surface_add_vertex(Vector3(1, 2, 3))
	im.surface_set_color(Color(1, 0.5, 0.25))
	im.surface_set_tangent(Plane(Vector3(1, 0, 0), -1))
	im.surface_add_vertex(Vector3(-1, 0.5, 2))
	im.surface_set_uv2(Vector2(0.3, 0.6))
	im.surface_add_vertex(Vector3(4, -1, 0))
	im.surface_end()
	dump_mesh("im|two", im)
	im.clear_surfaces()
	print("im|cleared|", im.get_surface_count())


# ---------------------------------------------------------------------------------------------- property defaults
func props() -> void:
	for cls in ["StandardMaterial3D", "ORMMaterial3D", "ParticleProcessMaterial", "NoiseTexture2D", "FastNoiseLite", "CurveTexture",
			"CurveXYZTexture", "PhysicsMaterial", "BoxMesh", "PlaneMesh", "QuadMesh", "CapsuleMesh", "CylinderMesh", "SphereMesh",
			"TorusMesh", "PrismMesh", "PointMesh"]:
		var o = ClassDB.instantiate(cls)
		for p in o.get_property_list():
			if not (p.usage & PROPERTY_USAGE_STORAGE or p.usage & PROPERTY_USAGE_EDITOR):
				continue
			if p.usage & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP):
				continue
			if p.name.begins_with("resource_") or p.name == "script" or p.name.begins_with("metadata/"):
				continue
			print("prop|", cls, "|", p.name, "|", fmt(o.get(p.name)))


# ---------------------------------------------------------------------------------------------- FastNoiseLite
func noise_case(name: String, n: FastNoiseLite) -> void:
	var a := PackedFloat32Array()
	for y in 12:
		for x in 12:
			a.append(n.get_noise_2d(x * 7.3 - 40.0, y * 5.1 - 30.0))
	arr("noise|" + name, "2d", a)
	print("noise|", name, "|2d0|", f6(a[0]), "|", f6(a[77]))
	a = PackedFloat32Array()
	for z in 4:
		for y in 6:
			for x in 6:
				a.append(n.get_noise_3d(x * 9.1 - 20.0, y * 4.7 + 3.0, z * 11.3 - 7.0))
	arr("noise|" + name, "3d", a)
	a = PackedFloat32Array()
	for x in 20:
		a.append(n.get_noise_1d(x * 3.7 - 12.0))
	arr("noise|" + name, "1d", a)


func noises() -> void:
	noise_case("default", FastNoiseLite.new())
	for t in 6:
		for f in 4:
			var n := FastNoiseLite.new()
			n.noise_type = t
			n.fractal_type = f
			n.seed = 1234 + t
			n.fractal_octaves = 3
			n.fractal_weighted_strength = 0.4 if f == 3 else 0.0
			n.frequency = 0.03
			noise_case("type%d_fractal%d" % [t, f], n)
	for d in 4:
		for r in 7:
			var n := FastNoiseLite.new()
			n.noise_type = FastNoiseLite.TYPE_CELLULAR
			n.cellular_distance_function = d
			n.cellular_return_type = r
			n.cellular_jitter = 0.8
			n.fractal_type = FastNoiseLite.FRACTAL_NONE
			n.frequency = 0.05
			noise_case("cell_d%d_r%d" % [d, r], n)
	for w in 3:
		for wf in 3:
			var n := FastNoiseLite.new()
			n.domain_warp_enabled = true
			n.domain_warp_type = w
			n.domain_warp_fractal_type = wf
			n.domain_warp_amplitude = 20.0
			n.domain_warp_frequency = 0.02
			n.domain_warp_fractal_octaves = 3
			n.seed = -77
			noise_case("warp%d_f%d" % [w, wf], n)
	var n2 := FastNoiseLite.new()
	n2.offset = Vector3(10.5, -3.25, 7)
	n2.fractal_lacunarity = 2.5
	n2.fractal_gain = 0.6
	n2.fractal_ping_pong_strength = 3.0
	n2.fractal_type = FastNoiseLite.FRACTAL_PING_PONG
	noise_case("offset_pingpong", n2)


# ---------------------------------------------------------------------------------------------- images
func img(name: String, im: Image) -> void:
	if im == null:
		print("img|", name, "|null")
		return
	var c := im.duplicate()
	if c.has_mipmaps():
		c.clear_mipmaps()
	print("img|", name, "|", c.get_format(), "|", c.get_width(), "x", c.get_height(), "|", c.get_data().hex_encode().md5_text(), "|", c.get_data().slice(0, 8).hex_encode())
	if full:
		var d: PackedByteArray = c.get_data()
		var row: int = d.size() / c.get_height()
		for y in c.get_height():
			print("img|", name, "|row", y, "|", d.slice(y * row, y * row + row).hex_encode())


func make_noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = 42
	n.frequency = 0.04
	n.fractal_octaves = 4
	return n


func make_gradient() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(0.1, 0.0, 0.3))
	g.set_color(1, Color(1.0, 0.9, 0.2))
	g.add_point(0.4, Color(0.8, 0.2, 0.1, 0.7))
	return g


func images() -> void:
	var n := make_noise()
	img("get_image", n.get_image(40, 30))
	img("get_image_inv3d", n.get_image(33, 17, true, true, true))
	img("get_image_nonorm", n.get_image(24, 24, false, false, false))
	img("seamless", n.get_seamless_image(32, 32))
	img("seamless_skirt", n.get_seamless_image(40, 24, false, true, 0.3, true))
	img("seamless_nonorm", n.get_seamless_image(16, 20, true, false, 0.1, false))
	var specs := [
		["tex_default", {}],
		["tex_inv3d", {"invert": true, "in_3d_space": true, "normalize": false}],
		["tex_seamless", {"seamless": true, "seamless_blend_skirt": 0.2}],
		["tex_normal", {"as_normal_map": true, "bump_strength": 4.0}],
		["tex_ramp", {"color_ramp": make_gradient()}],
		["tex_seamless_ramp_normal", {"seamless": true, "color_ramp": make_gradient(), "as_normal_map": true}],
	]
	for s in specs:
		var t := NoiseTexture2D.new()
		t.width = 64
		t.height = 48
		for k in s[1]:
			t.set(k, s[1][k])
		t.noise = make_noise()
		textures.append([s[0], t])


func curves() -> void:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.2), 0.0, 1.5)
	c.add_point(Vector2(0.35, 0.9), -0.5, 2.0)
	c.add_point(Vector2(0.7, 0.4))
	c.add_point(Vector2(1.0, 1.0), 0.8, 0.0)
	var c2 := Curve.new()
	c2.add_point(Vector2(0.1, 0.5))
	c2.add_point(Vector2(0.6, 0.0), -1.0, 2.5)
	c2.add_point(Vector2(0.9, 0.75), 3.0, -1.0)
	for spec in [["c_256", c, 256], ["c_64", c, 64], ["c2_100", c2, 100], ["c2_32", c2, 32]]:
		var vals := PackedFloat32Array()
		var w: int = spec[2]
		for i in w:
			vals.append(spec[1].sample_baked(i / float(w)))
		arr("curve|" + spec[0], "texels", vals)
	var ct := CurveTexture.new()
	ct.curve = c
	var im := RenderingServer.texture_2d_get(ct.get_rid())
	print("curve|tex_image|", im.get_format(), "|", im.get_width(), "|", im.get_data().hex_encode().md5_text())
	var ct2 := CurveTexture.new()
	ct2.texture_mode = CurveTexture.TEXTURE_MODE_RED
	var im3 := RenderingServer.texture_2d_get(ct2.get_rid())
	print("curve|tex_red_empty|", im3.get_format(), "|", im3.get_data().hex_encode().md5_text())
	var xv := PackedFloat32Array()
	for i in 50:
		xv.append(c.sample_baked(i / 50.0))
		xv.append(c2.sample_baked(i / 50.0))
		xv.append(0.0)
	arr("curve|xyz_50", "texels", xv)
	# (the dummy renderer keeps a texture's first image, so only one curve is set before reading it back)
	var xyz := CurveXYZTexture.new()
	xyz.curve_x = c
	var im2 := RenderingServer.texture_2d_get(xyz.get_rid())
	print("curve|xyz_image|", im2.get_format(), "|", im2.get_width(), "|", im2.get_data().hex_encode().md5_text())


func _initialize() -> void:
	full = OS.get_environment("FB_MESH_FULL") == "1"
	primitives()
	surface_tool()
	immediate()
	props()
	noises()
	curves()
	images()


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 8:
		return false
	for e in textures:
		img(e[0], e[1].get_image())
	return true
