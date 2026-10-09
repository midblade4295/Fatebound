extends SceneTree
# Bakes the Meshy chests (assets/ui/v2/chests/src/<kind>.glb, not imported) into menu-ready scenes: 1.6 m wide, base
# at y 0, front facing +Z, the lid cut off where the dome starts (the highest height at which the chest is still ~its full
# depth) and hung from a "Lid" pivot at its back edge, so the menus can open it. Texture: <kind>.jpg next to them (1K).
#   godot --headless --path godot -s res://tools/chest_bake.gd
const KINDS := ["wood", "silver", "gold", "royal"]
const DIR := "res://assets/ui/v2/chests/"

func _init() -> void:
	for kind in KINDS:
		_bake(kind)
	quit(0)

func _bake(kind: String) -> void:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(DIR + "src/%s.glb" % kind), st)
	if err != OK:
		push_error("can't read %s.glb" % kind)
		return
	var scn: Node = doc.generate_scene(st)
	var mi: MeshInstance3D = scn.find_children("*", "MeshInstance3D", true, false)[0]
	var xf := Transform3D.IDENTITY
	var p: Node = mi
	while p != null and p is Node3D:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	var arr := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for vi in verts.size():
		verts[vi] = xf * verts[vi]
	var box := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		box = box.expand(v)
	var s := 1.6 / box.size.x
	var off := Vector3(-box.get_center().x, -box.position.y, -box.get_center().z)
	for vi in verts.size():
		verts[vi] = (verts[vi] + off) * s
	var h := box.size.y * s
	var dmax := box.size.z * s
	var bins := 80
	var zmin := PackedFloat32Array()
	var zmax := PackedFloat32Array()
	zmin.resize(bins)
	zmax.resize(bins)
	for b in bins:
		zmin[b] = 1e9
		zmax[b] = -1e9
	for v in verts:
		var b := clampi(int(v.y / h * bins), 0, bins - 1)
		zmin[b] = minf(zmin[b], v.z)
		zmax[b] = maxf(zmax[b], v.z)
	var seam := h * 0.55
	for b in range(int(bins * 0.3), bins):
		if zmax[b] - zmin[b] >= dmax * 0.955:
			seam = (b + 1) * h / bins
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var basis_n := xf.basis.inverse().transposed()
	var hinge := Vector3(0.0, seam, -dmax * 0.5)
	var parts := {"lid": SurfaceTool.new(), "base": SurfaceTool.new()}
	for su in parts.values():
		(su as SurfaceTool).begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in range(0, idx.size(), 3):
		var cy := (verts[idx[t]].y + verts[idx[t + 1]].y + verts[idx[t + 2]].y) / 3.0
		var key := "lid" if cy > seam else "base"
		var su: SurfaceTool = parts[key]
		for j in 3:
			var vi := idx[t + j]
			if normals.size() > 0:
				su.set_normal((basis_n * normals[vi]).normalized())
			if uvs.size() > 0:
				su.set_uv(uvs[vi])
			su.add_vertex(verts[vi] - (hinge if key == "lid" else Vector3.ZERO))
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(DIR + "%s.jpg" % kind)
	mat.roughness = 0.62
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED            # the cut-open insides show
	var root := Node3D.new()
	root.name = "Chest"
	root.set_meta("seam", seam)
	root.set_meta("depth", dmax)
	root.set_meta("height", h)
	var base := MeshInstance3D.new()
	base.name = "Base"
	(parts.base as SurfaceTool).index()
	base.mesh = (parts.base as SurfaceTool).commit()
	base.material_override = mat
	root.add_child(base)
	base.owner = root
	var pivot := Node3D.new()
	pivot.name = "Lid"
	pivot.position = hinge
	root.add_child(pivot)
	pivot.owner = root
	var lid := MeshInstance3D.new()
	lid.name = "LidMesh"
	(parts.lid as SurfaceTool).index()
	lid.mesh = (parts.lid as SurfaceTool).commit()
	lid.material_override = mat
	pivot.add_child(lid)
	lid.owner = root
	var ps := PackedScene.new()
	ps.pack(root)
	var path := DIR + "%s.scn" % kind
	print("CHEST ", kind, " seam ", snappedf(seam / h, 0.01), " verts ", base.mesh.surface_get_array_len(0) + lid.mesh.surface_get_array_len(0), " -> ", path, " ", ResourceSaver.save(ps, path, ResourceSaver.FLAG_COMPRESS))
	scn.free()
	root.free()
