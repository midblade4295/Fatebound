class_name ToonMaterials
extends RefCounted
## Material factory for the chunky toon look. Materials are cached by their
## parameters so ten planes built from ~30 primitives each still share a
## handful of materials (fewer state changes, which matters on mobile).

const TOON_SHADER: Shader = preload("res://shaders/toon_plane.gdshader")
const DAMAGE_SHADER: Shader = preload("res://shaders/toon_plane_damage.gdshader")
const TRAIL_SHADER: Shader = preload("res://shaders/bullet_trail.gdshader")
const HOLE_SHADER: Shader = preload("res://shaders/bullet_hole.gdshader")
const OCEAN_SHADER: Shader = preload("res://shaders/ocean.gdshader")
const CLOUD_SHADER: Shader = preload("res://shaders/cloud.gdshader")

static var _toon_cache: Dictionary[String, ShaderMaterial] = {}
static var _unlit_cache: Dictionary[String, StandardMaterial3D] = {}
static var _effect_cache: Dictionary[String, ShaderMaterial] = {}


## Cel-shaded material using shaders/toon_plane.gdshader. [param rim] scales
## the bright edge light: 1 for objects, 0 for flat ground, which is seen at
## such a shallow angle from a cockpit that the rim would bleach all of it.
static func toon(color: Color, emission_strength: float = 0.0, spec_strength: float = 0.45, rim: float = 1.0) -> ShaderMaterial:
	var key: String = "%s|%.2f|%.2f|%.2f" % [color.to_html(), emission_strength, spec_strength, rim]
	if _toon_cache.has(key):
		return _toon_cache[key]
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = TOON_SHADER
	material.set_shader_parameter(&"albedo", color)
	material.set_shader_parameter(&"emission_strength", emission_strength)
	material.set_shader_parameter(&"spec_strength", spec_strength)
	if rim < 1.0:
		material.set_shader_parameter(&"rim_strength", 0.7 * rim)
		material.set_shader_parameter(&"ambient_rim", 0.12 * rim)
	_toon_cache[key] = material
	return material


## The same toon surface for the pieces of an aeroplane, which also shows how
## badly each piece is damaged (shaders/toon_plane_damage.gdshader). The
## damage is set per piece with set_instance_shader_parameter(), so planes
## still share these materials.
static func toon_damageable(color: Color, spec_strength: float = 0.45) -> ShaderMaterial:
	var key: String = "damageable|%s|%.2f" % [color.to_html(), spec_strength]
	if _toon_cache.has(key):
		return _toon_cache[key]
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = DAMAGE_SHADER
	material.set_shader_parameter(&"albedo", color)
	material.set_shader_parameter(&"spec_strength", spec_strength)
	_toon_cache[key] = material
	return material


## Smoke ribbons behind bullets (shaders/bullet_trail.gdshader).
static func bullet_trail() -> ShaderMaterial:
	return _effect("trail", TRAIL_SHADER)


## Bullet holes and strike marks (shaders/bullet_hole.gdshader). Drawn just
## in front of the surface they lie on.
static func bullet_hole() -> ShaderMaterial:
	return _effect("hole", HOLE_SHADER)


static func _effect(key: String, shader: Shader) -> ShaderMaterial:
	if _effect_cache.has(key):
		return _effect_cache[key]
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	_effect_cache[key] = material
	return material


## Flat, unshaded colour: tracers, muzzle flashes, propeller blur, HUD-ish 3D.
static func unlit(color: Color, additive: bool = false) -> StandardMaterial3D:
	var key: String = "%s|%s" % [color.to_html(), additive]
	if _unlit_cache.has(key):
		return _unlit_cache[key]
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	if color.a < 0.999 or additive:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if additive:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_unlit_cache[key] = material
	return material


## Stylized-PBR alternative to the custom shader, using only StandardMaterial3D
## switches (toon diffuse + toon specular + built-in rim). Handy when a mesh
## needs textures, normal maps or vertex colours later on. Not cached: callers
## usually want to tweak it.
static func standard_toon(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material.specular_mode = BaseMaterial3D.SPECULAR_TOON
	material.roughness = 0.55
	material.metallic = 0.0
	material.metallic_specular = 0.6
	material.rim_enabled = true
	material.rim = 0.6
	material.rim_tint = 0.35
	return material


## Canopy glass: glossy, slightly see-through.
static func glass(color: Color = Color(0.55, 0.85, 1.0, 0.55)) -> StandardMaterial3D:
	var key: String = "glass|%s" % color.to_html()
	if _unlit_cache.has(key):
		return _unlit_cache[key]
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.08
	material.metallic_specular = 0.9
	material.rim_enabled = true
	material.rim = 0.8
	_unlit_cache[key] = material
	return material


## Faint spinning-propeller disc. Back-face culled so exactly one layer is
## drawn from either side (a double-sided disc would stack up and look solid).
static func prop_blur() -> StandardMaterial3D:
	var key: String = "prop_blur"
	if _unlit_cache.has(key):
		return _unlit_cache[key]
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.85, 0.92, 1.0, 0.07)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_unlit_cache[key] = material
	return material


static func ocean() -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = OCEAN_SHADER
	return material


static func cloud(sun_direction: Vector3) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = CLOUD_SHADER
	material.set_shader_parameter(&"sun_direction", sun_direction)
	return material
