extends RefCounted
# The Rift's painted plants and ground marks (0.31.216, Kevin: "use eleven to draw detailed paint on ground. Also need
# new models for grass"): ElevenLabs painted the sheets (tools/ground_paint.py), this file cuts them into cards and the
# view (siege_view.gd: _plan_foliage, _build_foliage, _build_brush, _build_ground_marks) places them.
#   BLADES   grass clumps (4 x 2 on the sheet): two crossed cards, swaying -- the fields and the lanes' edges
#   BRUSH    the tall lavender-tipped grass you hide in (2 on the sheet): three crossed cards, swaying more
#   FLOWERS  patches of buttercups, daisies and blossoms (3 x 3): one card lying on the grass
#   decals   the carved stone circles on the lanes and the pits' floors, the ring of carved stone round every tower's
#            foot: a grid laid over the baked terrain (decal_mesh), drawn just above it
const Stage = preload("res://scripts/siege/asset_cache.gd")
const Land = preload("res://scripts/siege/siege_land.gd")
const SHADER := preload("res://scripts/siege/ground_cards.gdshader")
const DIR := "res://assets/terrain/paint/"

# sheet, its grid, sway (card heights), cut, the mesh's cards
const KINDS := {
	"blades": {"sheet": "blades.png", "cells": Vector2(4, 2), "sway": 0.09, "cards": 2, "aspect": 1.0, "hue": Vector3(1.0, 1.0, 1.0)},
	"brush": {"sheet": "brush.png", "cells": Vector2(2, 1), "sway": 0.06, "cards": 3, "aspect": 0.5, "hue": Vector3(1.0, 1.12, 0.84)},
	"flowers": {"sheet": "flowers.png", "cells": Vector2(3, 3), "sway": 0.0, "cards": 0, "aspect": 1.0, "hue": Vector3(1.0, 1.0, 1.0)},
}

static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}

static func material(kind: String, tint: Vector3) -> ShaderMaterial:
	if not _mats.has(kind):
		var k: Dictionary = KINDS[kind]
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("sheet", Stage.texture(DIR + str(k.sheet)))
		m.set_shader_parameter("cells", k.cells)
		m.set_shader_parameter("sway", float(k.sway))
		m.set_shader_parameter("tint", tint * (k.hue as Vector3))     # (the brush's painted teal pulled toward green)
		_mats[kind] = m
	return _mats[kind]

static func mesh(kind: String) -> ArrayMesh:
	# A card is 1 tall (its width by the sheet's cell), its foot at y 0; UV v 0 at its top. "flowers": one card flat on
	# the ground, 1 x 1, centred.
	if _meshes.has(kind):
		return _meshes[kind]
	var k: Dictionary = KINDS[kind]
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var n := int(k.cards)
	if n == 0:
		for c in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
			verts.append(Vector3(c.x, 0.02, c.y))
			uvs.append(Vector2(c.x + 0.5, c.y + 0.5))
			norms.append(Vector3.UP)
		idx.append_array([0, 1, 2, 0, 2, 3])
	else:
		var w := float(k.aspect) * 0.5
		for i in n:
			var a := PI * float(i) / float(n)
			var d := Vector3(cos(a), 0.0, sin(a)) * w
			var b := verts.size()
			verts.append_array([-d, d, d + Vector3.UP, -d + Vector3.UP])
			uvs.append_array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
			for _j in 4:
				norms.append(Vector3.UP)
			idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_meshes[kind] = am
	return am

static func custom(cell: int, rng: RandomNumberGenerator) -> Color:
	# INSTANCE_CUSTOM: the sheet's cell, a shade, a beat in the breeze
	return Color(float(cell), rng.randf(), rng.randf(), 0.0)

# ---------- decals ----------
static var _decal_mats: Dictionary = {}
const DECAL_SHADER := """
shader_type spatial;
// (ground_cards.gd) a painted mark laid over the ground: the picture's own alpha, lit as the ground is
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint = vec3(1.0);
uniform float spin = 0.0;
void fragment() {
	vec2 q = UV - 0.5;
	q = mat2(vec2(cos(spin), sin(spin)), vec2(-sin(spin), cos(spin))) * q + 0.5;
	vec4 c = texture(tex, q);
	ALBEDO = c.rgb * tint;
	ALPHA = c.a * step(0.0, q.x) * step(q.x, 1.0) * step(0.0, q.y) * step(q.y, 1.0);
	ROUGHNESS = 0.95;
}
"""
static var _decal_shader: Shader = null

static func decal_material(pic: String, tint: Vector3) -> ShaderMaterial:
	if not _decal_mats.has(pic):
		if _decal_shader == null:
			_decal_shader = Shader.new()
			_decal_shader.code = DECAL_SHADER
		var m := ShaderMaterial.new()
		m.shader = _decal_shader
		m.set_shader_parameter("tex", Stage.texture(DIR + pic))
		m.set_shader_parameter("tint", tint)
		m.render_priority = 1
		_decal_mats[pic] = m
	return _decal_mats[pic]

static func decal_mesh(c: Vector2, size: float, height: Callable, lift := 0.05) -> ArrayMesh:
	# A size x size grid centred on c, every 0.75 m or less, each point just above the ground (height: Vector2 -> float).
	var n := maxi(4, int(ceil(size / 0.75)))
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in n + 1:
		for i in n + 1:
			var u := float(i) / n
			var v := float(j) / n
			var p := c + Vector2(u - 0.5, v - 0.5) * size
			verts.append(Vector3(p.x, float(height.call(p)) + lift, p.y))
			uvs.append(Vector2(u, v))
			norms.append(Vector3.UP)
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			idx.append_array([a, a + 1, a + n + 1, a + 1, a + n + 2, a + n + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am
