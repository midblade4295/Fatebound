extends SceneTree
# 0.31.173 (Kevin: "I want better trees and bush models" -- all sixteen Summer and Enchanted concepts, "Use meshy for
# the models"): foliage.gd's plants and the Rift's trees and brush.
#  - every plant loads from its Meshy model, drawn with foliage.gdshader (its texture, its height for the sway, the
#    glowing ones their glow mask); every tree has its shadow copy (fewer triangles, inside the tree) and the woods'
#    kinds their light *_far copies; the place tables name only plants;
#  - in a match: no KayKit tree or bush left; the brush patches filled with their sets' plants (on the ground, no
#    shadow), the ridges' trees and bushes, the edge's trees and the outer woods' far trees all drawn as small
#    MultiMesh cells; a tree casts its shadow only from its shadow copy (a shadow-only MultiMesh beside it).
#   godot --headless --path godot -s res://tests/foliage_test.gd
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Foliage = preload("res://scripts/siege/foliage.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
var mode
var frames := 0
var fails := []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

static func _tris(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var a: Array = m.surface_get_arrays(s)
		n += (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if a[Mesh.ARRAY_INDEX] != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n

func _init() -> void:
	check(Foliage.PLANTS.size() == 16, "sixteen plants (%d)" % Foliage.PLANTS.size())
	for kind in Foliage.PLANTS:
		var m := Foliage.mesh(kind)
		var mat := Foliage.material(kind) as ShaderMaterial
		var ok := m != null and mat != null and mat.shader == Foliage.SHADER and mat.get_shader_parameter("albedo_tex") is Texture2D
		var tris := _tris(m) if m != null else 0
		ok = ok and tris >= 1400 and absf(float(mat.get_shader_parameter("height")) - m.get_aabb().size.y) < 0.01
		ok = ok and float(mat.get_shader_parameter("sway")) > 0.0
		if Foliage.PLANTS[kind].has("glow"):
			ok = ok and mat.get_shader_parameter("glow_tex") is Texture2D and float(mat.get_shader_parameter("glow_energy")) > 0.0
		var size := m.get_aabb().size if m != null else Vector3.ZERO
		var want := "tree" if str(kind).begins_with("tree") else "bush"
		ok = ok and ((want == "tree" and size.y >= 4.0) or (want == "bush" and size.y <= 1.2 and size.y >= 0.3))
		check(ok, "%s: its Meshy model (%d triangles, %.1f m tall), foliage.gdshader%s" % [kind, tris, size.y,
			", glowing" if Foliage.PLANTS[kind].has("glow") else ""])
		if str(kind).begins_with("tree"):
			var sk := Foliage.shadow_of(kind)
			var sm := Foliage.mesh(sk)
			var inside := sm != null and m.get_aabb().grow(0.1).encloses(sm.get_aabb())
			check(inside and _tris(sm) < tris * 0.6, "%s: its shadow copy, %d triangles, inside the tree" % [kind, _tris(sm) if sm != null else 0])
		else:
			check(Foliage.shadow_of(kind) == "", "%s casts no shadow" % kind)
	for kind in Foliage.OUTER_TREES:
		var fm := Foliage.mesh(str(kind) + "_far")
		check(fm != null and _tris(fm) < _tris(Foliage.mesh(kind)) and Foliage.material(str(kind) + "_far") is ShaderMaterial,
			"%s_far: the woods' light copy" % kind)
	var named := true
	for table in [Foliage.RIDGE_TREES, Foliage.RIDGE_BUSHES, Foliage.OUTER_TREES] + Foliage.BRUSH_SETS:
		for k in table:
			named = named and Foliage.PLANTS.has(k)
	for bset in Foliage.BRUSH_SETS:
		for k in bset:
			named = named and not str(k).begins_with("tree")
	check(named, "the place tables name only plants (the brush no trees)")
	mode = Mode.new()
	mode.moba_hero = "knight"
	mode.match_seed = 4403
	root.add_child(mode)

func _process(_d: float) -> bool:
	frames += 1
	if mode.sim == null or not mode._build_queue.is_empty() or frames < 30:
		return false
	var v = mode.view
	var by_perf := {}                    # perf -> [instances, nodes]
	var kayk := 0
	var wide := 0
	var shadows := {}                    # perf -> instances in shadow copies
	var bad_shadow := 0
	var brush_kinds := {}
	var brush_pts := []
	for c in v.get_children():
		var n := str(c.name)
		if not (c is MultiMeshInstance3D) and (n.begins_with("Tree_") or n.begins_with("Bush_")):
			kayk += 1
		if not (c is MultiMeshInstance3D) or not (n.begins_with("Plants_") or n.begins_with("Brush_") or n.begins_with("Shadows_")):
			continue
		var mmi := c as MultiMeshInstance3D
		var perf := str(mmi.get_meta("perf", ""))
		var kind := str(mmi.get_meta("perf_kind", ""))
		var cnt := mmi.multimesh.instance_count
		var places: Array = mmi.get_meta("places", []) if not n.begins_with("Shadows_") else []
		if not n.begins_with("Shadows_"):
			var lo := Vector2(INF, INF)
			var hi := -lo
			for xf in places:
				var o: Vector3 = (xf as Transform3D).origin
				lo = Vector2(minf(lo.x, o.x), minf(lo.y, o.z))
				hi = Vector2(maxf(hi.x, o.x), maxf(hi.y, o.z))
			var cell := 24.0 if perf == "outer_trees" else float(v.PLANT_CELL)
			if places.size() != cnt or hi.x - lo.x > cell or hi.y - lo.y > cell:
				wide += 1
		if n.begins_with("Shadows_"):
			shadows[perf] = int(shadows.get(perf, 0)) + cnt
			if mmi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY or not kind.ends_with("_shadow"):
				bad_shadow += 1
			continue
		if not by_perf.has(perf):
			by_perf[perf] = [0, 0]
		by_perf[perf][0] += cnt
		by_perf[perf][1] += 1
		if mmi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF or not Foliage.is_plant(kind) or not (mmi.material_override is ShaderMaterial):
			bad_shadow += 1
		if perf == "brush":
			brush_kinds[kind] = true
			for xf in places:
				brush_pts.append((xf as Transform3D).origin)
	check(kayk == 0, "no KayKit tree or bush left in the scene (%d)" % kayk)
	var bp: Array = by_perf.get("brush", [0, 0])
	var rp: Array = by_perf.get("ridges", [0, 0])
	var ep: Array = by_perf.get("edge_trees", [0, 0])
	var op: Array = by_perf.get("outer_trees", [0, 0])
	check(int(bp[0]) >= 60 and int(rp[0]) >= 100 and int(ep[0]) >= 60 and int(op[0]) >= 300,
		"plants drawn: brush %d, ridges %d, edge trees %d, the woods %d" % [bp[0], rp[0], ep[0], op[0]])
	var all_kinds := {}
	for bset in Foliage.BRUSH_SETS:
		for k in bset:
			all_kinds[k] = true
	check(brush_kinds.size() == all_kinds.size(), "every brush plant used (%s)" % str(brush_kinds.keys()))
	check(wide == 0, "every plant batch one small cell, its places kept (%d not)" % wide)
	check(bad_shadow == 0 and int(shadows.get("ridges_shadow", 0)) > 0 and int(shadows.get("edge_trees_shadow", 0)) == int(ep[0])
		and not shadows.has("brush_shadow") and not shadows.has("outer_trees_shadow"),
		"the trees' shadows from their shadow copies (ridges %d, edge %d); the plants themselves and the brush cast none" % [
			shadows.get("ridges_shadow", 0), shadows.get("edge_trees_shadow", 0)])
	var thin := 0
	var aground := 0
	for b in mode.sim.moba.vision.brushes:
		var inside := 0
		for p in brush_pts:
			var q := Vector2((p as Vector3).x, (p as Vector3).z)
			if q.distance_to(b.p) <= float(b.r):
				inside += 1
				if absf((p as Vector3).y - (Sim.height_at(q) - 0.05)) < 0.02:
					aground += 1
		if inside < 4:
			thin += 1
	check(thin == 0, "every brush patch filled (%d patches, %d with under 4 plants)" % [mode.sim.moba.vision.brushes.size(), thin])
	check(aground == brush_pts.size(), "the brush on the ground (%d of %d)" % [aground, brush_pts.size()])
	print("FOLIAGE_%s" % ("PASS" if fails.is_empty() else "FAIL %s" % str(fails)))
	quit(0 if fails.is_empty() else 1)
	return true
