extends RefCounted
# The Rift's trees and bushes (0.31.173, Kevin: "I want better trees and bush models" -- all sixteen of the Summer and
# Enchanted concepts). Meshy models (assets/meshy/foliage/, tools/foliage_prep.py), drawn by the view as MultiMeshes
# with foliage.gdshader (the canopies sway; the glowing fruits and flowers shine). This file says which plant goes
# where; the view (siege_view.gd: _plan_ridges, _build_brush, _build_outer_trees, _build_edge_scenery) places them.
const Stage = preload("res://scripts/siege/asset_cache.gd")
const SHADER := preload("res://scripts/siege/foliage.gdshader")
const DIR := "res://assets/meshy/foliage/"

# every plant: its sway (model units at the top), the still share of its height, glow strength
const PLANTS := {
	"tree_oak": {"sway": 0.10, "from": 0.40}, "tree_fir": {"sway": 0.08, "from": 0.30}, "tree_birch": {"sway": 0.13, "from": 0.35},
	"tree_gnarled": {"sway": 0.08, "from": 0.45}, "tree_mossy": {"sway": 0.10, "from": 0.40}, "tree_blossom": {"sway": 0.10, "from": 0.40},
	"tree_glow": {"sway": 0.09, "from": 0.40, "glow": 2.2}, "tree_autumn": {"sway": 0.10, "from": 0.40},
	"bush_round": {"sway": 0.03, "from": 0.2}, "bush_flower": {"sway": 0.03, "from": 0.2}, "bush_fern": {"sway": 0.05, "from": 0.15},
	"grass_reeds": {"sway": 0.09, "from": 0.1}, "bush_berry": {"sway": 0.03, "from": 0.2}, "bush_broadleaf": {"sway": 0.05, "from": 0.15},
	"grass_glow": {"sway": 0.07, "from": 0.1, "glow": 2.0}, "grass_tall": {"sway": 0.09, "from": 0.1},
}
# the trees along the jungle's walls: mostly greens, a blossom, an autumn tree or a glowing one here and there
const RIDGE_TREES := {"tree_oak": 3, "tree_mossy": 3, "tree_fir": 2, "tree_birch": 2, "tree_gnarled": 2, "tree_blossom": 1,
	"tree_autumn": 1, "tree_glow": 1}
# under them
const RIDGE_BUSHES := {"bush_round": 2, "bush_fern": 2, "bush_broadleaf": 2, "bush_berry": 1, "bush_flower": 1}
# the woods beyond the field (the light copies, *_far: Meshy's first, lighter takes, 1.3-1.9k triangles)
const OUTER_TREES := {"tree_oak": 3, "tree_mossy": 3, "tree_fir": 3, "tree_birch": 2, "tree_autumn": 1}
# a brush patch is one of these sets: tall grass (League's brush), a leafy thicket, an enchanted thicket
const BRUSH_SETS := [{"grass_reeds": 3, "grass_tall": 3, "bush_fern": 1},
	{"bush_round": 3, "bush_flower": 2, "bush_fern": 2},
	{"bush_berry": 2, "bush_broadleaf": 2, "grass_glow": 2}]

# a brush plant's size (its instance scale; the models: the bushes 1 m across, the grasses 1 m tall): a hero's height
# or more, overlapping -- a thicket you can see you'd hide in (the KayKit bushes' brush stood about as tall)
static func brush_scale(rng: RandomNumberGenerator, kind: String) -> float:
	return rng.randf_range(1.45, 1.8) if kind.begins_with("grass") else rng.randf_range(1.9, 2.4)

static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}

static func pick(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0
	for k in weights:
		total += int(weights[k])
	var x := rng.randi() % maxi(total, 1)
	for k in weights:
		x -= int(weights[k])
		if x < 0:
			return str(k)
	return str(weights.keys()[0])

static func path(kind: String) -> String:
	return DIR + kind + ".glb"

# a plant's own name without its copy's suffix: *_far (the woods beyond the field: an earlier, lighter Meshy take),
# *_shadow (the same model remeshed by Meshy to ~1000 triangles, its canopy pulled in a little: what a tree's shadow
# is drawn from -- siege_view._plant_batch)
static func base(kind: String) -> String:
	return kind.trim_suffix("_far").trim_suffix("_shadow")

static func is_plant(kind: String) -> bool:
	return PLANTS.has(base(kind))

# the light copy a tree's shadow is drawn from ("" for a plant without one: the bushes cast none)
static func shadow_of(kind: String) -> String:
	return base(kind) + "_shadow" if base(kind).begins_with("tree") else ""

static func mesh(kind: String) -> Mesh:
	if not _meshes.has(kind):
		var m: Mesh = null
		var packed: PackedScene = Stage.scene(path(kind))
		if packed != null:
			var holder := packed.instantiate()
			for c in holder.find_children("*", "MeshInstance3D", true, false):
				m = (c as MeshInstance3D).mesh
				if not _mats.has(kind):
					_material_from(kind, c as MeshInstance3D, m)
				break
			holder.free()
		_meshes[kind] = m
	return _meshes[kind]

static func material(kind: String) -> Material:
	if not _mats.has(kind):
		mesh(kind)
	return _mats.get(kind, null)

static func _material_from(kind: String, mi: MeshInstance3D, m: Mesh) -> void:
	var spec: Dictionary = PLANTS.get(base(kind), {})
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	var src := mi.get_active_material(0) as BaseMaterial3D
	mat.set_shader_parameter("albedo_tex", src.albedo_texture if src != null else null)
	mat.set_shader_parameter("height", maxf(m.get_aabb().size.y, 0.1) if m != null else 1.0)
	mat.set_shader_parameter("sway", float(spec.get("sway", 0.08)))
	mat.set_shader_parameter("sway_from", float(spec.get("from", 0.3)))
	if spec.has("glow"):
		mat.set_shader_parameter("glow_tex", Stage.texture(DIR + base(kind) + "_glow.png"))
		mat.set_shader_parameter("glow_energy", float(spec.glow))
	_mats[kind] = mat
