extends RefCounted
# The 5v5's towers (0.31.172, Kevin: "new tower models" -- the Royal A concepts for the lane tower and the King tower,
# "I want them to visually break as their health gets lower").
#
# Two Meshy models (assets/meshy/towers/, made by tools/tower_prep.py): the lane tower for tiers 1-3 (a little bigger
# each tier) and the King tower for tier 4. Each is drawn with tower.gdshader in its side's colours. A model is cut into
# cells, each with the stage it breaks off at; as the tower's health falls past 75 / 50 / 25 % (stages 1 / 2 / 3) and
# when it falls (4), that stage's cells are hidden in the tower's mesh and the view (siege_view.gd) drops a copy of
# each (chunks()). Cracks spread with the damage taken. What's drawn follows the tower's health only -- the sim's
# towers are unchanged.
const Stage = preload("res://scripts/siege/asset_cache.gd")
const SHADER := preload("res://scripts/siege/tower.gdshader")
const DIR := "res://assets/meshy/towers/"
const CRACKS := DIR + "cracks.png"
# kind -> model; its height in metres at tier 1 (the King's own); the brazier (model units: the model is 1.0 tall, its
# foot at y 0, its front on +Z) where the shots start; the foot's radius (model units) -- all from tools/tower_prep.py
const MODELS := {
	"lane": {"m": "tower_lane", "h": 6.0, "brazier": Vector3(0.0, 0.638, -0.007), "foot": 0.193},
	"king": {"m": "tower_king", "h": 7.0, "brazier": Vector3(0.004, 0.641, 0.015), "foot": 0.285},
}
const TIER_SCALE := [1.0, 1.0, 1.07, 1.14, 1.0]      # by tier: the outer tower, the inner, the gate's, the King's
const STAGE_AT := [0.75, 0.5, 0.25]                  # health fractions at or under which stages 1, 2, 3 begin

static var _mats: Dictionary = {}       # "kind|team" -> ShaderMaterial
static var _chunks: Dictionary = {}     # kind -> [{mesh, center, stage}]

static func kind_of(tier: int) -> String:
	return "king" if tier >= 4 else "lane"

static func height(tier: int) -> float:
	return float(MODELS[kind_of(tier)].h) * float(TIER_SCALE[clampi(tier, 0, 4)])

static func stage_of(hp: float, max_hp: float, dead: bool) -> int:
	if dead:
		return 4
	var f := hp / maxf(max_hp, 1.0)
	var s := 0
	for k in STAGE_AT.size():
		if f <= float(STAGE_AT[k]):
			s = k + 1
	return s

static func brazier(tier: int) -> Vector3:
	# the brazier above the tower's foot, in metres (the tower turned to face +Z)
	return (MODELS[kind_of(tier)].brazier as Vector3) * height(tier)

static func material(kind: String, team: int, albedo: Texture2D) -> ShaderMaterial:
	var key := "%s|%d" % [kind, team]
	if _mats.has(key):
		return _mats[key]
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("team", team)
	mat.set_shader_parameter("albedo_tex", albedo)
	mat.set_shader_parameter("glow_tex", Stage.texture(DIR + str(MODELS[kind].m) + "_glow.png"))
	mat.set_shader_parameter("crack_tex", Stage.texture(CRACKS))
	_mats[key] = mat
	return mat

static func instance(tier: int, team: int) -> Node3D:
	# The tower for a tier, in a side's colours (team: the side as drawn, 0 blue / 1 red), its foot at the origin,
	# metres tall, front on +Z. Metas: "kind"; "mesh", its MeshInstance3D (the view sets broken / dmg / lit on it).
	var kind := kind_of(tier)
	var root := Node3D.new()
	root.name = "tower_" + kind
	root.set_meta("kind", kind)
	var packed: PackedScene = Stage.scene(DIR + str(MODELS[kind].m) + ".glb")
	if packed == null:
		return root
	var m: Node3D = packed.instantiate()
	root.add_child(m)
	m.scale = Vector3.ONE * height(tier)
	var mi: MeshInstance3D = null
	for c in m.find_children("*", "MeshInstance3D", true, false):
		mi = c
		break
	if mi != null:
		var src := mi.get_active_material(0) as BaseMaterial3D
		mi.material_override = material(kind, team, src.albedo_texture if src != null else null)
		root.set_meta("mesh", mi)
	return root

static func chunks(kind: String, mesh: Mesh) -> Array:
	# The model's cells as their own meshes (made once per model, the first time one breaks): each centred on its own
	# middle (model units) so it can tumble about it; its stage.
	if _chunks.has(kind):
		return _chunks[kind]
	var out := []
	if mesh == null or mesh.get_surface_count() == 0:
		_chunks[kind] = out
		return out
	var a: Array = mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var uv2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var tris := {}                     # cell -> [vertex indices, three a triangle] (an Array: a packed one is a copy)
	for t in range(0, idx.size(), 3):
		var c := int(round(uv2[idx[t]].y))
		if not tris.has(c):
			tris[c] = []
		var l: Array = tris[c]
		l.append(idx[t])
		l.append(idx[t + 1])
		l.append(idx[t + 2])
	var cells: Array = tris.keys()
	cells.sort()
	for c in cells:
		var ti: Array = tris[c]
		var remap := {}
		var v2 := PackedVector3Array()
		var n2 := PackedVector3Array()
		var u2 := PackedVector2Array()
		var w2 := PackedVector2Array()
		var i2 := PackedInt32Array()
		var mid := Vector3.ZERO
		for vi in ti:
			if not remap.has(vi):
				remap[vi] = v2.size()
				v2.append(vs[vi])
				n2.append(ns[vi])
				u2.append(uv[vi])
				w2.append(uv2[vi])
				mid += vs[vi]
			i2.append(remap[vi])
		mid /= float(maxi(v2.size(), 1))
		for k in v2.size():
			v2[k] -= mid
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v2
		arr[Mesh.ARRAY_NORMAL] = n2
		arr[Mesh.ARRAY_TEX_UV] = u2
		arr[Mesh.ARRAY_TEX_UV2] = w2
		arr[Mesh.ARRAY_INDEX] = i2
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.append({"mesh":am, "center":mid, "stage":int(round(uv2[ti[0]].x)), "tris":ti.size() / 3})
	_chunks[kind] = out
	return out
