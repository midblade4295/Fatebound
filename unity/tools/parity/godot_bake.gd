extends SceneTree
# Godot's side of the baked-asset parity test (tools/parity/bake.sh; the C# side: tools/guitest/BakeTest.cs, `guitest
# bake`). For each path given after "--": load() it and print what the port's loader must rebuild -- a scene's
# instantiated tree (classes, names, owners, transforms, metadata), meshes (surfaces, vertex/index counts, an md5 of each
# surface_get_arrays() array), materials (their main properties), skins (binds), skeletons (bones), animation players and
# libraries (track paths/types/key counts, first and last keys), particles (process material, curves, gradients), images
# (size, format, md5 of the data) and a script resource's properties. Each line: "<key>|<value>".

const MAT_PROPS := ["albedo_color", "albedo_texture", "transparency", "cull_mode", "shading_mode", "diffuse_mode",
	"specular_mode", "metallic", "metallic_specular", "roughness", "vertex_color_use_as_albedo", "vertex_color_is_srgb",
	"emission_enabled", "emission", "emission_energy_multiplier", "emission_operator", "emission_texture", "normal_enabled",
	"normal_scale", "normal_texture", "billboard_mode", "billboard_keep_scale", "particles_anim_h_frames",
	"particles_anim_v_frames", "particles_anim_loop", "texture_filter", "texture_repeat", "depth_draw_mode", "no_depth_test",
	"alpha_scissor_threshold", "uv1_scale", "uv1_offset", "render_priority", "grow", "grow_amount"]
const PPM_PROPS := ["direction", "spread", "flatness", "gravity", "initial_velocity_min", "initial_velocity_max",
	"angular_velocity_min", "angular_velocity_max", "angle_min", "angle_max", "scale_min", "scale_max", "scale_curve", "color",
	"color_ramp", "alpha_curve", "emission_curve", "emission_shape", "emission_sphere_radius", "lifetime_randomness",
	"particle_flag_align_y", "velocity_pivot", "collision_mode", "collision_friction", "collision_bounce", "sub_emitter_mode",
	"sub_emitter_frequency", "damping_min", "damping_max"]
const GP_PROPS := ["amount", "lifetime", "one_shot", "emitting", "explosiveness", "randomness", "fixed_fps", "sub_emitter",
	"sorting_offset", "trail_lifetime", "local_coords", "draw_passes"]

var ids := {}
var dumped := {}

func p(k: String, v) -> void:
	print(k + "|" + str(v))

func md5(b: PackedByteArray) -> String:
	var c := HashingContext.new()
	c.start(HashingContext.HASH_MD5)
	c.update(b)
	return c.finish().hex_encode().substr(0, 16)

func rel(root: Node, n: Node) -> String:
	if n == root:
		return "."
	var parts := []
	while n != null and n != root:
		parts.push_front(String(n.name))
		n = n.get_parent()
	return "/".join(parts)

func rid(r) -> String:
	if r == null:
		return "-"
	var path: String = r.resource_path
	if path != "" and not path.contains("::"):
		return "file:" + path
	if not ids.has(r):
		ids[r] = ids.size()
	return "#" + str(ids[r])

func fv(v) -> String:
	if typeof(v) == TYPE_OBJECT:
		return rid(v)
	return str(v)

func props(key: String, o: Object, names: Array) -> void:
	for n in names:
		var v = o.get(n)
		p(key + "|" + n, fv(v))
		if v is Resource:
			dres(v)

func _init() -> void:
	for path in OS.get_cmdline_user_args():
		ids = {}
		dumped = {}
		var r = load(path)
		if r == null:
			p("file", path + "|null")
			continue
		p("file", path + "|" + ("PackedScene" if r is PackedScene else r.get_class()))
		if r is PackedScene:
			var inst: Node = r.instantiate()
			walk(inst, inst)
			inst.free()
		else:
			dres(r)
	quit()

func walk(n: Node, root: Node) -> void:
	var path := rel(root, n)
	p("node|" + path, n.get_class() + "|owner=" + (rel(root, n.owner) if n.owner != null else "-") + "|children=" + str(n.get_child_count()))
	var metas: Array = []
	for k in n.get_meta_list():
		metas.append(String(k))
	metas.sort()
	for k in metas:
		p("meta|" + path + "|" + k, n.get_meta(k))
	if n is Node3D:
		p("xf|" + path, n.transform)
		if not n.visible:
			p("hidden|" + path, "")
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		p("mi|" + path, "skeleton=" + str(mi.skeleton) + "|mesh=" + rid(mi.mesh) + "|skin=" + rid(mi.skin) + "|override=" + rid(mi.material_override) + "|cast=" + str(int(mi.cast_shadow)))
		for i in mi.get_surface_override_material_count():
			if mi.get_surface_override_material(i) != null:
				p("mi_so|" + path + "|" + str(i), rid(mi.get_surface_override_material(i)))
		if mi.mesh is ArrayMesh:
			for i in (mi.mesh as ArrayMesh).get_blend_shape_count():
				p("mi_bs|" + path + "|" + str(i), mi.get_blend_shape_value(i))
		dres(mi.mesh)
		dres(mi.skin)
		dres(mi.material_override)
	if n is Skeleton3D:
		var sk := n as Skeleton3D
		p("skel|" + path, sk.get_bone_count())
		for i in sk.get_bone_count():
			p("bone|" + path + "|" + str(i), "%s|%d|%s|%s|%s|%s|%s" % [sk.get_bone_name(i), sk.get_bone_parent(i), sk.get_bone_rest(i),
				sk.get_bone_pose_position(i), sk.get_bone_pose_rotation(i), sk.get_bone_pose_scale(i), sk.is_bone_enabled(i)])
	if n is AnimationPlayer:
		var ap := n as AnimationPlayer
		var libs: Array = []
		for l in ap.get_animation_library_list():
			libs.append(String(l))
		libs.sort()
		p("ap|" + path, "root=" + str(ap.root_node) + "|libs=" + ",".join(libs))
		for l in libs:
			p("ap_lib|" + path + "|" + l, rid(ap.get_animation_library(l)))
			dres(ap.get_animation_library(l))
	if n is BoneAttachment3D:
		p("ba|" + path, str(n.bone_name) + "|" + str(n.bone_idx))
	if n is GPUParticles3D:
		props("gp|" + path, n, GP_PROPS)
		p("gp|" + path + "|process_material", rid(n.process_material))
		p("gp|" + path + "|draw_pass_1", rid(n.draw_pass_1))
		dres(n.process_material)
		dres(n.draw_pass_1)
	for c in n.get_children():
		walk(c, root)

func dres(r) -> void:
	if r == null or rid(r).begins_with("file:") or dumped.has(r):
		return
	dumped[r] = true
	var id := rid(r)
	if r is ArrayMesh:
		var m := r as ArrayMesh
		var names := []
		for i in m.get_blend_shape_count():
			names.append(String(m.get_blend_shape_name(i)))
		p("mesh" + id, "surfaces=%d|name=%s|blend=%s|aabb=%s" % [m.get_surface_count(), m.resource_name, ",".join(names), m.get_aabb()])
		for i in m.get_surface_count():
			p("surf" + id + "|" + str(i), "prim=%d|verts=%d|idx=%d|fmt=%d|mat=%s|name=%s" % [m.surface_get_primitive_type(i),
				m.surface_get_array_len(i), m.surface_get_array_index_len(i), m.surface_get_format(i) & 0xFFFFFFFF,
				rid(m.surface_get_material(i)), m.surface_get_name(i)])
			var arrays := m.surface_get_arrays(i)
			for a in arrays.size():
				if arrays[a] != null:
					p("arr" + id + "|" + str(i) + "|" + str(a), md5(var_to_bytes(arrays[a])))
			var bs := m.surface_get_blend_shape_arrays(i)
			for b in bs.size():
				p("bsarr" + id + "|" + str(i) + "|" + str(b), md5(var_to_bytes(bs[b][Mesh.ARRAY_VERTEX])))
			dres(m.surface_get_material(i))
	elif r is Skin:
		p("skin" + id, r.get_bind_count())
		for i in r.get_bind_count():
			p("bind" + id + "|" + str(i), "%s|%d|%s" % [r.get_bind_name(i), r.get_bind_bone(i), r.get_bind_pose(i)])
	elif r is AnimationLibrary:
		var names: Array = []
		for a in r.get_animation_list():
			names.append(String(a))
		names.sort()
		p("lib" + id, names.size())
		for a in names:
			p("lib" + id + "|" + a, rid(r.get_animation(a)))
			dres(r.get_animation(a))
	elif r is Animation:
		var an := r as Animation
		p("anim" + id, "%s|%d|%d" % [an.length, an.loop_mode, an.get_track_count()])
		for t in an.get_track_count():
			var nk := an.track_get_key_count(t)
			p("track" + id + "|" + str(t), "%d|%s|%d|%s|%s|%d" % [an.track_get_type(t), an.track_get_path(t), an.track_get_interpolation_type(t),
				an.track_get_interpolation_loop_wrap(t), an.track_is_enabled(t), nk])
			if nk > 0 and an.track_get_type(t) <= Animation.TYPE_BLEND_SHAPE:
				p("key" + id + "|" + str(t) + "|first", str(an.track_get_key_time(t, 0)) + "|" + fv(an.track_get_key_value(t, 0)))
				p("key" + id + "|" + str(t) + "|last", str(an.track_get_key_time(t, nk - 1)) + "|" + fv(an.track_get_key_value(t, nk - 1)))
	elif r is BaseMaterial3D:
		p("mat" + id, r.get_class())
		props("matp" + id, r, MAT_PROPS)
	elif r is ParticleProcessMaterial:
		p("mat" + id, r.get_class())
		props("ppm" + id, r, PPM_PROPS)
	elif r is CurveTexture:
		p("curvetex" + id, "%d|%d|%s" % [r.width, r.texture_mode, rid(r.curve)])
		dres(r.curve)
	elif r is Curve:
		p("curve" + id, "%d|%s|%s" % [r.point_count, r.min_value, r.max_value])
		for i in r.point_count:
			p("cpt" + id + "|" + str(i), "%s|%s|%s" % [r.get_point_position(i), r.get_point_left_tangent(i), r.get_point_right_tangent(i)])
	elif r is GradientTexture1D:
		p("gradtex" + id, "%d|%s|%s" % [r.width, r.use_hdr, rid(r.gradient)])
		dres(r.gradient)
	elif r is Gradient:
		p("grad" + id, "%d|%d" % [r.get_point_count(), r.interpolation_mode])
		for i in r.get_point_count():
			p("gpt" + id + "|" + str(i), "%s|%s" % [r.get_offset(i), r.get_color(i)])
	elif r is Image:
		p("img" + id, "%d|%d|%d|%s" % [r.get_width(), r.get_height(), r.get_format(), md5(r.get_data())])
	elif r.get_script() != null:
		p("script" + id, (r.get_script() as Script).resource_path)
		var names := []
		for pr in r.get_property_list():
			if pr.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				names.append(pr.name)
		names.sort()
		for n in names:
			dv("sp" + id + "|" + n, r.get(n))
	else:
		p("res" + id, r.get_class())

func dv(key: String, v) -> void:
	if v is Resource:
		p(key, rid(v))
		dres(v)
	elif v is Array:
		p(key, "array|" + str(v.size()))
		for i in v.size():
			var e = v[i]
			if e is Resource or e is Array or e is Dictionary:
				dv(key + "/" + str(i), e)
			elif i == 0 or i == v.size() - 1:
				p(key + "/" + str(i), e)
	elif v is Dictionary:
		p(key, "dict|" + str(v.size()))
		for k in v:
			dv(key + "/" + str(k), v[k])
	else:
		p(key, v)
