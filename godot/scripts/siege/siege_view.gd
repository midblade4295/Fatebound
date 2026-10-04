extends Node3D
# Presentation only: mirrors siege_sim state every frame and never changes it.
const Stage = preload("res://scripts/siege/asset_cache.gd")
const Land = preload("res://scripts/siege/siege_land.gd")
const Castle = preload("res://scripts/siege/siege_castle.gd")
const CastleMesh = preload("res://scripts/siege/castle_mesh.gd")
const PATH_TEX := preload("res://assets/terrain/path.png")
const Sim = preload("res://scripts/siege/siege_sim.gd")

const HEX := "res://assets/kaykit/hex/"
const FOREST := "res://assets/kaykit/forest/"
const TEAM_COLORS := [Color("#5fd2f0"), Color("#ff7b52")]
const GOLD := Color("#ffd46a")
static var VULKAN_EXPOSURE := 1.55
static var VULKAN_AMBIENT := 2.25

# Model, weapons (right/left hand) and clips per class. Clip keys: g general, m melee, r ranged,
# mb movement basic, ma movement advanced, t tools.
const LOOKS := {
	"villager": {"model":"Rogue","r":"","l":"","idle":"g/Idle_A","attack":"m/Melee_Unarmed_Attack_Punch_A","ability":"m/Melee_Unarmed_Attack_Kick"},
	"worker": {"model":"Rogue","r":"axe_1handed","l":"","idle":"g/Idle_A","attack":"m/Melee_1H_Attack_Chop","ability":"m/Melee_1H_Attack_Chop"},
	"knight": {"model":"Knight","r":"sword_1handed","l":"bits/shield_B","idle":"g/Idle_A","attack":"m/Melee_1H_Attack_Slice_Diagonal","ability":"m/Melee_Blocking"},
	# Upgraded barbarian (Round 11): two-handed greatsword, whirlwind.
	"berserker": {"model":"Barbarian","r":"bits/sword_E","l":"","idle":"m/Melee_2H_Idle","attack":"m/Melee_2H_Attack_Chop","ability":"m/Melee_2H_Attack_Spinning"},
	"barbarian": {"model":"Barbarian","r":"axe_2handed","l":"","idle":"m/Melee_2H_Idle","attack":"m/Melee_2H_Attack_Slice","ability":"m/Melee_2H_Attack_Spin"},
	"rogue": {"model":"Rogue_Hooded","r":"dagger","l":"dagger","idle":"g/Idle_B","attack":"m/Melee_Dualwield_Attack_Stab","ability":"m/Melee_1H_Attack_Jump_Chop"},
	"ranger": {"model":"Ranger","r":"","l":"bow_withString","idle":"r/Ranged_Bow_Idle","attack":"r/Ranged_Bow_Release","ability":"r/Ranged_Bow_Release_Up"},
	"mage": {"model":"Mage","r":"staff","l":"","idle":"g/Idle_B","attack":"r/Ranged_Magic_Shoot","ability":"r/Ranged_Magic_Spellcasting"},
	# Healer: the Mage model in white-gold robes with a wand (tint set once, cached like skins).
	"priest": {"model":"Mage","r":"wand","l":"","tint":"#fff1c8","idle":"g/Idle_B","attack":"r/Ranged_Magic_Spellcasting_Long","ability":"r/Ranged_Magic_Raise"},
	# Upgraded priest (0.31.2, Kevin): the Necromancer from KayKit Skeletons (CC0, same Rig_Medium) with the skull staff.
	"necromancer": {"model":"Necromancer","r":"Skeleton_Staff","l":"","idle":"g/Idle_B","attack":"r/Ranged_Magic_Spellcasting_Long","ability":"r/Ranged_Magic_Raise"},
}
const LOOP_HINTS := ["Idle","Running","Walking","Hammering","Holding","Aiming","_Pose","Blocking","Chopping","Pickaxing"]

static var _libs: Dictionary = {}
# Shared GPU resources: one mesh/shader per effect type instead of one per hit, so fights don't
# churn buffers or trigger new shader compiles mid-match.
static var _spark_mesh: SphereMesh
static var _rings: Dictionary = {}

var sim
var player_id := "you"
var camera: Camera3D
var actors: Dictionary = {}
var oracle_nodes: Array = []
var gate_nodes: Dictionary = {}
var node_nodes: Dictionary = {}
var stock_piles: Array = []
var catapult_nodes: Array = []
var ladder_nodes: Dictionary = {}
var proj_nodes: Dictionary = {}
var proj_lead := 0.0          # offline: seconds since the last sim tick (projectiles drawn ahead by vel * this)
var _fx: Array = []
var _time := 0.0
var _cam_target := Vector3.ZERO
var low_fx := false
var hq_gfx := true          # High-quality graphics (Round 30): set by SiegeMode from Settings before _ready

static func libraries() -> Dictionary:
	if _libs.is_empty():
		var files := {"g":"General","m":"CombatMelee","r":"CombatRanged","mb":"MovementBasic","ma":"MovementAdvanced","t":"Tools"}
		for key in files:
			var packed := Stage.scene("res://assets/kaykit/anim/Rig_Medium_%s.glb" % files[key])
			if packed == null:
				continue
			var holder := packed.instantiate()
			var player: AnimationPlayer = holder.find_child("AnimationPlayer", true, false)
			if player != null:
				var lib: AnimationLibrary = player.get_animation_library("")
				for n in lib.get_animation_list():
					for hint in LOOP_HINTS:
						if n.contains(hint):
							lib.get_animation(n).loop_mode = Animation.LOOP_LINEAR
							break
				_libs[key] = lib
			holder.free()
	return _libs

static var build_times := {}      # last setup's ms per step (siege_diag / tools read it)
const CACHE_RES := "res://assets/terrain/cache.res"
static var _cache_tried := false

static func _load_cache() -> void:
	# The baked start-up cache (0.31.8): terrain and outer meshes, the foliage plan and blood textures, generated once by
	# tools/bake_land.gd. Used only when its key matches the land; otherwise the view generates (slower first start).
	if _cache_tried:
		return
	_cache_tried = true
	if not ResourceLoader.exists(CACHE_RES):
		return
	var c = load(CACHE_RES)
	if c == null or str(c.get("key")) != Land.bake_key():
		push_warning("siege: terrain cache is stale (run tools/bake_land.gd); generating at start instead")
		return
	_terrain_meshes = c.terrain.duplicate()
	_outer_meshes = c.outer.duplicate()
	_foliage = c.foliage.duplicate()
	_blood_tex = []
	for img in c.blood:
		_blood_tex.append(ImageTexture.create_from_image(img))

func setup(s) -> void:
	sim = s
	build_times = {}
	var t := Time.get_ticks_msec()
	_load_cache()
	build_times["cache"] = Time.get_ticks_msec() - t
	t = Time.get_ticks_msec()
	for step in ["_build_lighting", "_build_ambience", "_build_blood", "_build_terrain", "_build_props"]:
		call(step)
		var now := Time.get_ticks_msec()
		build_times[step] = now - t
		t = now
	for tm in 2:
		oracle_nodes.append(_make_oracle(tm))
	_warm_up()
	build_times["oracles+warm"] = Time.get_ticks_msec() - t

func _warm_up() -> void:
	# Draw one of every effect/projectile type in view during the first frames, so their shader
	# variants compile while the match is loading instead of freezing the first fight.
	var at := Vector3(Sim.spawn(0).x, 0.5, Sim.spawn(0).y)
	ring_at(at, GOLD, 1.0, 0.2)
	spark(at, GOLD)
	number(at, "0", false)
	for kind in ["arrow", "fire"]:
		var n := _make_projectile(kind)
		n.position = at
		get_tree().create_timer(0.3).timeout.connect(n.queue_free)

# ---------- High-quality ambience (Round 32: "add even more effects to make the game look more beautiful") ----------
const CLOUD_STRENGTH := 0.2
static var _cloud_tex: NoiseTexture2D = null
var _motes: GPUParticles3D = null
var _torches: Array = []          # [light, flame, base energy, phase]

static func _clouds() -> NoiseTexture2D:
	if _cloud_tex == null:
		_cloud_tex = NoiseTexture2D.new()
		_cloud_tex.width = 256
		_cloud_tex.height = 256
		_cloud_tex.seamless = true
		var fn := FastNoiseLite.new()
		fn.frequency = 0.02
		fn.fractal_octaves = 4
		_cloud_tex.noise = fn
	return _cloud_tex

static func _cloud_floor_material(tex: Texture2D, tint_col: Color) -> ShaderMaterial:
	# The castle floor with the terrain's drifting cloud shadows, so they don't stop at the castle walls.
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode specular_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 tint_col : source_color;
uniform float cloud_strength = 0.2;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float cl = smoothstep(0.46, 0.74, texture(cloud_tex, wpos.xz / 95.0 + vec2(TIME * 0.006, TIME * 0.0035)).r);
	ALBEDO = texture(tex, UV).rgb * tint_col.rgb * (1.0 - cloud_strength * cl);
	ROUGHNESS = 0.95;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("tint_col", tint_col)
	m.set_shader_parameter("cloud_tex", _clouds())
	m.set_shader_parameter("cloud_strength", CLOUD_STRENGTH)
	return m

static func _bright(c: Color) -> Color:
	# Effects bright enough for the glow to bloom (High-quality graphics); rings and decals don't use this.
	if not _cast_static:
		return c
	return Color(c.r * 1.8, c.g * 1.8, c.b * 1.8, c.a)

static func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t

func _build_ambience() -> void:
	if not _hq():
		return
	# Warm motes of pollen drifting in the sunlight around where the camera looks.
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(20.0, 2.5, 20.0)
	pm.gravity = Vector3(0.0, 0.06, 0.0)
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.25
	pm.direction = Vector3(0.3, 0.4, 0.2)
	pm.spread = 180.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.add_point(0.2, Color(1, 1, 1, 1))
	ramp.add_point(0.8, Color(1, 1, 1, 1))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mm.vertex_color_use_as_albedo = true
	mm.albedo_texture = _soft_dot()
	mm.albedo_color = Color(2.2, 2.0, 1.4, 0.75)
	quad.material = mm
	_motes = GPUParticles3D.new()
	_motes.amount = 90
	_motes.lifetime = 9.0
	_motes.preprocess = 9.0
	_motes.local_coords = false
	_motes.process_material = pm
	_motes.draw_pass_1 = quad
	_motes.visibility_aabb = AABB(Vector3(-24, -4, -24), Vector3(48, 10, 48))
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_motes)
	# Wall torches in each dungeon: a warm, flickering light (the KayKit RPG Tools torch).
	var torch_scene := Stage.scene("res://assets/kaykit/tools/torch.gltf")
	for t in 2:
		for spot in [[Vector2(-24.5, 23.0), Vector2(0.0, -1.0)], [Vector2(-32.0, 16.0), Vector2(1.0, 0.0)]]:
			var p: Vector2 = Sim._c(t, spot[0])
			var into: Vector2 = Sim._c(t, spot[0] + spot[1]) - p
			var fy := Sim.height_at(p + into * 0.6) + 1.9
			if torch_scene != null:
				var tm: Node3D = torch_scene.instantiate()
				tm.scale = Vector3.ONE * 2.2
				add_child(tm)
				tm.global_position = Vector3(p.x, fy - 1.3, p.y) + Vector3(into.x, 0.0, into.y) * 0.35
				tm.rotation = Vector3(0.0, Sim.angle_of(into), 0.0)
				tm.rotate_object_local(Vector3.RIGHT, 0.35)
			var light := OmniLight3D.new()
			light.light_color = Color("#ffb05a")
			light.light_energy = 1.6
			light.omni_range = 6.0
			light.omni_attenuation = 1.3
			light.shadow_enabled = false
			add_child(light)
			light.global_position = Vector3(p.x, fy, p.y) + Vector3(into.x, 0.0, into.y) * 0.6
			var flame := MeshInstance3D.new()
			var fq := QuadMesh.new()
			fq.size = Vector2(0.6, 0.9)
			var fmat := StandardMaterial3D.new()
			fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			fmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			fmat.albedo_texture = _soft_dot()
			fmat.albedo_color = Color(2.4, 1.3, 0.45, 0.9)
			fq.material = fmat
			flame.mesh = fq
			flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(flame)
			flame.global_position = light.global_position + Vector3(0.0, -0.15, 0.0)
			_torches.append([light, flame, 1.6, randf() * 10.0])

func _sync_ambience(_dt: float) -> void:
	if _motes != null and is_instance_valid(camera) and camera.is_inside_tree():
		var cp := camera.global_position
		var fwd := -camera.global_transform.basis.z
		if fwd.y < -0.05:
			var hit := cp + fwd * (-cp.y / fwd.y)
			_motes.global_position = hit + Vector3(0.0, 2.2, 0.0)
	for tr in _torches:
		var ph: float = float(tr[3])
		var k := 0.82 + 0.1 * sin(_time * 9.0 + ph) + 0.08 * sin(_time * 23.0 + ph * 1.7)
		(tr[0] as OmniLight3D).light_energy = float(tr[2]) * k
		(tr[1] as Node3D).scale = Vector3.ONE * (0.9 + 0.12 * k)

# ---------- Water you can wade through, with simulated waves (Round 33) ----------
# Kevin: "make the water look much more realistic, like actually simulated water ... realistic physics that create
# wakes". A height field over the river (RIP_W x RIP_H, ~13 cm cells) is stepped every frame on the GPU with the
# wave equation (two SubViewports ping-pong: R = height now, G = height a step ago). Each wading unit pushes on it in
# proportion to its speed, so wakes, rings and bank reflections come out of the physics. The water shader lights the
# resulting slopes (plus flowing detail), reflects the sky at grazing angles, is see-through over the bed, and foams
# on the banks and the wave crests. High-quality graphics only; without it the old water stays.
# 0.30.0: the field is wider and the river opens into a lake round the island, so the simulated patch spans the
# whole field and the lake's full width (still ~13 cm cells). UV.y on the water mesh is this patch's across
# coordinate (centred on the river line); UV2.y runs 0..1 bank to bank for the shallows.
const RIP_W := 680
const RIP_H := 198
const RIP_HALF := Land.HALF_W                  # the simulated stretch: x in [-44, 44]
const RIP_ACROSS := (Land.RIVER_HW + Land.LAKE_EXTRA + 0.35) * 2.0     # the lake at its widest
var _rip_vp: Array = []
var _rip_mat: Array = []
var _rip_i := 0
var _rip_prev: Dictionary = {}                 # unit id -> [last pos, was wet]

func _water_hq_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_opaque;
uniform sampler2D ripples : filter_linear_mipmap, repeat_enable;
uniform sampler2D rip_tex : filter_linear, repeat_disable;
uniform float rip_half = 34.0;
uniform vec2 rip_texel = vec2(0.001953, 0.019231);
uniform float rip_strength = 28.0;
uniform float wake_tint = 4.5;            // crests lighter, troughs darker: how the wakes show without foam
uniform vec3 deep_col : source_color = vec3(0.05, 0.27, 0.42);
uniform vec3 shallow_col : source_color = vec3(0.24, 0.62, 0.66);
uniform vec3 sky_col : source_color = vec3(0.62, 0.80, 0.95);
uniform float glint = 0.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float detail(vec2 p) {
	return texture(ripples, p * 0.11 + vec2(-TIME * 0.035, 0.0)).r * 0.6
		+ texture(ripples, p * 0.23 + vec2(-TIME * 0.05, TIME * 0.02)).r * 0.4;
}
void fragment() {
	// Flowing detail (the river runs toward -x) from finite differences of two scrolling layers.
	float e = 0.2;
	float d0 = detail(wpos.xz);
	vec2 slope = vec2(detail(wpos.xz + vec2(e, 0.0)) - d0, detail(wpos.xz + vec2(0.0, e)) - d0) / e * 0.22;
	// The simulated waves.
	vec2 ruv = vec2((wpos.x + rip_half) / (2.0 * rip_half), UV.y);
	float inside = step(0.0, ruv.x) * step(ruv.x, 1.0);
	float h = texture(rip_tex, ruv).r * inside;
	float hx = (texture(rip_tex, ruv + vec2(rip_texel.x, 0.0)).r - texture(rip_tex, ruv - vec2(rip_texel.x, 0.0)).r) * inside;
	float hz = (texture(rip_tex, ruv + vec2(0.0, rip_texel.y)).r - texture(rip_tex, ruv - vec2(0.0, rip_texel.y)).r) * inside;
	if (isnan(h + hx + hz) || isinf(h + hx + hz)) { h = 0.0; hx = 0.0; hz = 0.0; }
	slope += clamp(vec2(hx, hz) * rip_strength, vec2(-1.5), vec2(1.5));
	vec3 wn = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	float edge = min(UV2.y, 1.0 - UV2.y);
	float depth = smoothstep(0.02, 0.4, edge);
	vec3 col = mix(shallow_col, deep_col, depth);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	col = mix(col, sky_col, clamp(fres * 0.5, 0.0, 0.5));      // was up to 0.75: a lake-wide sheet read as white
	// No foam (Round 34, Kevin). The wakes read as light crests and dark troughs instead.
	col *= 1.0 + clamp(h, -0.12, 0.12) * wake_tint;
	ALBEDO = col;
	ALPHA = mix(0.58, 0.86, depth);
	ROUGHNESS = 0.16;                 // 0.30.11: was 0.05 / 0.75 -- the sun's glare spread white over the wide lake
	SPECULAR = 0.35;
	float sg = texture(ripples, wpos.xz * 0.19 + vec2(-TIME * 0.09, TIME * 0.05)).r * texture(ripples, wpos.xz * 0.13 + vec2(TIME * 0.07, -TIME * 0.04)).r;
	EMISSION = vec3(1.0, 0.97, 0.88) * smoothstep(0.58, 0.64, sg) * glint;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.04
	nt.noise = fn
	m.set_shader_parameter("ripples", nt)
	m.set_shader_parameter("glint", 1.3)
	m.set_shader_parameter("rip_half", RIP_HALF)
	m.set_shader_parameter("rip_texel", Vector2(1.0 / RIP_W, 1.0 / RIP_H))
	return m

func _build_ripples() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
render_mode blend_disabled;
uniform sampler2D prev : filter_nearest, repeat_disable;
uniform vec2 texel;
uniform vec2 cell_m;
uniform vec4 drops[16];
uniform int drop_count = 0;
uniform float damping = 0.989;            // wakes trail longer (Round 34)
void fragment() {
	vec4 p = texture(prev, UV);
	float n = texture(prev, UV + vec2(texel.x, 0.0)).r + texture(prev, UV - vec2(texel.x, 0.0)).r
		+ texture(prev, UV + vec2(0.0, texel.y)).r + texture(prev, UV - vec2(0.0, texel.y)).r;
	float h = (n * 0.5 - p.g) * damping;
	for (int i = 0; i < 16; i++) {
		if (i >= drop_count) { break; }
		vec2 d = (UV - drops[i].xy) / texel * cell_m;
		float r = drops[i].z;
		h += drops[i].w * exp(-dot(d, d) / (r * r));
	}
	h *= smoothstep(0.0, 0.03, UV.y) * smoothstep(1.0, 0.97, UV.y);
	// 0.30.11: the lake made the simulated patch 5x bigger. A bad cell (NaN/inf) would spread and the water would
	// render white (Kevin's screenshot): clamp and scrub every step.
	h = (isnan(h) || isinf(h)) ? 0.0 : clamp(h, -0.6, 0.6);
	float pr = (isnan(p.r) || isinf(p.r)) ? 0.0 : clamp(p.r, -0.6, 0.6);
	COLOR = vec4(h, pr, 0.0, 1.0);
}
"""
	for k in 2:
		var vp := SubViewport.new()
		vp.size = Vector2i(RIP_W, RIP_H)
		vp.use_hdr_2d = true
		vp.disable_3d = true
		vp.transparent_bg = false
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var cr := ColorRect.new()
		cr.size = Vector2(RIP_W, RIP_H)
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("texel", Vector2(1.0 / RIP_W, 1.0 / RIP_H))
		m.set_shader_parameter("cell_m", Vector2(2.0 * RIP_HALF / RIP_W, RIP_ACROSS / RIP_H))
		cr.material = m
		vp.add_child(cr)
		add_child(vp)
		_rip_vp.append(vp)
		_rip_mat.append(m)

func _sync_ripples(dt: float) -> void:
	if _rip_vp.is_empty() or _water_mat == null:
		return
	var drops := []
	for u in sim.units:
		if not sim.alive(u):
			_rip_prev.erase(u.id)
			continue
		var p: Vector2 = u.pos
		var wet := Sim.water_depth(p) > 0.12 and absf(p.x) < RIP_HALF - 0.5
		var last: Array = _rip_prev.get(u.id, [p, false])
		var spd: float = (p - (last[0] as Vector2)).length() / maxf(dt, 0.001)
		if wet and drops.size() < 16:
			var v := (p.y - (Land.river_c(p.x) - RIP_ACROSS * 0.5)) / RIP_ACROSS
			var strength := 0.005 + minf(spd, 6.0) * 0.0085          # (Round 34: twice as strong, no foam to hide it)
			var radius := 0.42
			if not bool(last[1]):
				strength = 0.06                              # stepping in: a splash
				radius = 0.7
				var sp := Vector3(p.x, Land.WATER_Y + 0.05, p.y)
				for k in 8:
					spark(sp + Vector3(randf_range(-0.4, 0.4), randf_range(0.0, 0.6), randf_range(-0.4, 0.4)), Color(0.9, 0.96, 1.0))
			drops.append(Vector4((p.x + RIP_HALF) / (2.0 * RIP_HALF), v, radius, strength))
		_rip_prev[u.id] = [p, wet]
	var cur := _rip_i % 2
	var other := 1 - cur
	var m: ShaderMaterial = _rip_mat[cur]
	m.set_shader_parameter("prev", (_rip_vp[other] as SubViewport).get_texture())
	var arr := PackedVector4Array()
	arr.resize(16)
	for i in drops.size():
		arr[i] = drops[i]
	m.set_shader_parameter("drops", arr)
	m.set_shader_parameter("drop_count", drops.size())
	(_rip_vp[cur] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
	_water_mat.set_shader_parameter("rip_tex", (_rip_vp[other] as SubViewport).get_texture())
	_rip_i += 1

# ---------- Blood (Round 37, Kevin: "blood will splatter on the ground when hit, and when a player dies there will be
# a pool of blood") ----------
# Flat, lit, glossy marks on the ground (procedural splatter textures), droplets flung away from the attacker that
# land as small spots, and a pool that spreads under a body. Recycled pools of nodes with hard caps; each mark fades
# after a while. Not on the river.
const BLOOD_COL := Color(0.56, 0.03, 0.04)      # a red that reads as blood from the game camera (darker went black)
const SPLAT_MAX := 90
const POOL_MAX := 24
const DROP_MAX := 60
const SPLAT_LIFE := 18.0
const POOL_LIFE := 25.0
const BLOOD_FADE := 3.0
static var _blood_tex: Array = []          # [splat variants..., pool]
var _splats: Array = []                    # {mi, born, life, r0, r1, grow}
var _splat_i := 0
var _pools: Array = []
var _pool_i := 0
var _drops: Array = []                     # {mi, p: Vector3, v: Vector3, size}
var _drop_i := 0
var _blood_layer := 0

static func _blood_texture(seed_v: int, pool: bool) -> ImageTexture:
	return ImageTexture.create_from_image(_blood_image(seed_v, pool))

static func _blood_image(seed_v: int, pool: bool) -> Image:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var c := Vector2(n, n) * 0.5
	var phases := []
	for k in 6:
		phases.append([rng.randf() * TAU, rng.randf_range(0.04, 0.12) * (0.4 if pool else 1.0), 2 + k * (1 if pool else 2)])
	var base_r := n * (0.36 if pool else 0.26)
	var drops := []
	if not pool:
		for k in rng.randi_range(5, 9):
			var ang := rng.randf() * TAU
			var dist := base_r * rng.randf_range(1.15, 1.7)
			drops.append([c + Vector2(cos(ang), sin(ang)) * dist, rng.randf_range(1.6, 4.5)])
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := p - c
			var ang := atan2(d.y, d.x)
			var r := base_r
			for ph in phases:
				r *= 1.0 + float(ph[1]) * sin(ang * float(ph[2]) + float(ph[0]))
			var a := clampf((r - d.length()) / 1.6, 0.0, 1.0)
			for dr in drops:
				a = maxf(a, clampf((float(dr[1]) - p.distance_to(dr[0])) / 1.2, 0.0, 1.0))
			# a little darker toward the middle, where it's thicker
			var shade := 1.0 - 0.25 * clampf(1.0 - d.length() / maxf(r, 1.0), 0.0, 1.0)
			img.set_pixel(x, y, Color(shade, shade, shade, a))
	return img

func _blood_mat(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = BLOOD_COL
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.22                     # wet
	m.metallic_specular = 0.6
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m

func _build_blood() -> void:
	if _blood_tex.is_empty():
		for k in 4:
			_blood_tex.append(_blood_texture(71 + k * 13, false))
		_blood_tex.append(_blood_texture(503, true))
	var quad := PlaneMesh.new()
	quad.size = Vector2(1.0, 1.0)
	for k in SPLAT_MAX:
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = _blood_mat(_blood_tex[k % 4])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_splats.append({"mi": mi, "born": -999.0, "life": SPLAT_LIFE, "r0": 1.0, "r1": 1.0, "grow": 0.0})
	for k in POOL_MAX:
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = _blood_mat(_blood_tex[4])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_pools.append({"mi": mi, "born": -999.0, "life": POOL_LIFE, "r0": 0.2, "r1": 1.0, "grow": 3.0})
	var dm := SphereMesh.new()
	dm.radius = 0.045
	dm.height = 0.09
	dm.radial_segments = 6
	dm.rings = 3
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = BLOOD_COL
	dmat.roughness = 0.25
	dm.material = dmat
	for k in DROP_MAX:
		var mi := MeshInstance3D.new()
		mi.mesh = dm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_drops.append({"mi": mi, "p": Vector3.ZERO, "v": Vector3.ZERO, "size": 0.2, "on": false})

func _blood_mark(list: Array, idx: int, p: Vector2, radius: float, grow: float, life: float) -> void:
	# Lay one mark flat on the ground at p (not on the river).
	if Sim.water_depth(p) > 0.05:
		return
	var m: Dictionary = list[idx]
	var mi: MeshInstance3D = m.mi
	_blood_layer = (_blood_layer + 1) % 40
	mi.position = Vector3(p.x, Sim.height_at(p) + 0.02 + _blood_layer * 0.0006, p.y)
	mi.rotation = Vector3(0.0, randf() * TAU, 0.0)
	m.born = _time
	m.life = life
	m.r1 = radius
	m.r0 = radius * (0.2 if grow > 0.0 else 1.0)
	m.grow = grow
	mi.scale = Vector3.ONE * (m.r0 * 2.0)
	(mi.material_override as StandardMaterial3D).albedo_color = BLOOD_COL
	mi.visible = true

func blood_hit(target: Vector2, from: Vector2, dmg: float) -> void:
	if _splats.is_empty():
		return
	var away := (target - from).normalized() if target.distance_to(from) > 0.05 else Vector2.from_angle(randf() * TAU)
	var amt := clampf(dmg / 40.0, 0.35, 1.6)
	var sp := target + away * randf_range(0.35, 0.8) + Vector2(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2))
	_blood_mark(_splats, _splat_i, sp, randf_range(0.45, 0.68) * (0.7 + amt * 0.5), 0.0, SPLAT_LIFE)
	_splat_i = (_splat_i + 1) % SPLAT_MAX
	var y0 := Sim.height_at(target) + 1.0
	for k in int(3 + amt * 3):
		var d: Dictionary = _drops[_drop_i]
		_drop_i = (_drop_i + 1) % DROP_MAX
		var dir2 := away.rotated(randf_range(-0.7, 0.7))
		d.p = Vector3(target.x, y0 + randf_range(-0.2, 0.3), target.y)
		d.v = Vector3(dir2.x, 0.0, dir2.y) * randf_range(1.5, 3.8) + Vector3(0.0, randf_range(1.0, 2.8), 0.0)
		d.size = randf_range(0.13, 0.24)
		d.on = true
		(d.mi as MeshInstance3D).position = d.p
		(d.mi as MeshInstance3D).visible = true

func blood_pool(p: Vector2) -> void:
	if _pools.is_empty():
		return
	_blood_mark(_pools, _pool_i, p, randf_range(1.45, 1.8), 3.0, POOL_LIFE)
	_pool_i = (_pool_i + 1) % POOL_MAX

func _sync_blood(dt: float) -> void:
	for d in _drops:
		if not bool(d.on):
			continue
		d.v += Vector3(0.0, -9.8, 0.0) * dt
		d.p += d.v * dt
		var g := Sim.height_at(Vector2(d.p.x, d.p.z))
		if d.p.y <= g + 0.03:
			d.on = false
			(d.mi as MeshInstance3D).visible = false
			_blood_mark(_splats, _splat_i, Vector2(d.p.x, d.p.z), float(d.size), 0.0, SPLAT_LIFE * 0.8)
			_splat_i = (_splat_i + 1) % SPLAT_MAX
		else:
			(d.mi as MeshInstance3D).position = d.p
	for list in [_splats, _pools]:
		for m in list:
			var mi: MeshInstance3D = m.mi
			if not mi.visible:
				continue
			var age: float = _time - float(m.born)
			if age > float(m.life) + BLOOD_FADE:
				mi.visible = false
				continue
			if float(m.grow) > 0.0 and age < float(m.grow):
				var k := 1.0 - pow(1.0 - age / float(m.grow), 3.0)          # spreads fast, then slows
				mi.scale = Vector3.ONE * lerpf(float(m.r0), float(m.r1), k) * 2.0
			if age > float(m.life):
				var c := BLOOD_COL
				c.a = 1.0 - (age - float(m.life)) / BLOOD_FADE
				(mi.material_override as StandardMaterial3D).albedo_color = c

# ---------- world ----------
var _hq_cached := -1
static var _cast_static := false     # for the static make_body: set from _hq() before any unit is built

func _hq() -> bool:
	# High-quality graphics, except under the software renderer this project is built and tested with (it hung
	# on shadow-casting Kings in the full scene): there only when FB_FORCE_HQ is set, to check the look. Cached.
	if _hq_cached < 0:
		var soft := RenderingServer.get_video_adapter_name().to_lower().contains("llvmpipe")
		_hq_cached = 1 if hq_gfx and (not soft or OS.has_environment("FB_FORCE_HQ")) else 0
	return _hq_cached == 1

func _cast() -> GeometryInstance3D.ShadowCastingSetting:
	# Solid things (castles, buildings, blocks, iron bars, units) cast shadows in high quality; ground, water,
	# grass, decals and effects never do (they only receive).
	return GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _hq() else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _apply_hq(env: Environment, sun: DirectionalLight3D) -> void:
	# Round 30 (Kevin: "increase the graphical fidelity -- lighting, shadows"). The Mobile renderer has no SSAO,
	# SSR or GI, so: real sun shadows (castles, buildings, trees, units, Kings; grass and flowers stay out),
	# a warm sun against cool sky-blue shade instead of flat grey, a subtle glow on the brightest highlights
	# (low glow levels only: the cheap passes), and 2x MSAA (cheap on tile-based phone GPUs).
	sun.shadow_enabled = true
	# One shadow pass reaching the top of the screen (Round 36, Kevin: "I don't see shadows from trees"). The camera
	# is 38 m up: the visible ground is 28 m deep at the bottom of the screen and ~70 m at the top, so 0.27.2's 45 m
	# left the upper half (field, trees, rocks, bridges) unshadowed. tests/battle_bench.gd with MSAA 2x: one pass to
	# 75 m costs +4 % over 45 m (two splits to 80 m +7 %) -- the 21 fps was MSAA 4x, not shadow reach.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 75.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.1
	sun.shadow_blur = 1.3
	sun.shadow_opacity = 1.0
	# Rebalanced so shadows read: the ambient fill was tuned for a shadowless world (about as strong as the sun,
	# so a shadow only removed half the light and the tonemap flattened it). Less fill, more sun: sunlit ground
	# about as bright as before, shade ~40 % of it, tinted cool blue.
	sun.light_energy = 1.45
	RenderingServer.directional_shadow_atlas_set_size(2048, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	env.ambient_light_color = Color("#a9bcd8")
	env.ambient_light_energy *= 0.75
	env.glow_enabled = true
	for i in 7:
		env.set_glow_level(i, i == 1 or i == 2)
	env.glow_intensity = 0.6
	env.glow_strength = 0.95
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.08
	env.tonemap_exposure *= 1.05                # the shade costs ~6 % mean brightness: give it back

func _build_lighting() -> void:
	_cast_static = _hq()
	var env := Environment.new()
	# A real sky (0.19.4, Kevin: "there needs to be a sky, mainly for the trailer"). Background only:
	# ambient stays a flat colour and reflections are off, so lighting on the field is unchanged and
	# no radiance map is computed.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#3a79c8")
	sky_mat.sky_horizon_color = Color("#bcd8ea")
	sky_mat.sky_curve = 0.12
	# Below the horizon = the fog colour: wherever no land is drawn it reads as distant haze, never
	# as a grey patch.
	sky_mat.ground_horizon_color = Color("#b3cfe1")
	sky_mat.ground_bottom_color = Color("#b3cfe1")
	sky_mat.sun_angle_max = 24.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#c3c9c4")
	env.ambient_light_energy = 0.5 * (VULKAN_AMBIENT if RenderingServer.get_current_rendering_method() != "gl_compatibility" else 1.0)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Vulkan/Mobile lights in linear space and reads darker than Compatibility with the same
	# settings. Multiplier tuned so Siege's mean brightness matches Compatibility (see commit).
	var vk := RenderingServer.get_current_rendering_method() != "gl_compatibility"
	env.tonemap_exposure = 0.84 * (VULKAN_EXPOSURE if vk else 1.0)
	env.tonemap_white = 3.0
	# More colourful, like the Fat Princess references (Kevin, Round 7b).
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.04
	env.fog_enabled = true
	env.fog_light_color = Color("#b3cfe1")      # the sky's horizon: distant hills fade into it
	env.fog_mode = Environment.FOG_MODE_DEPTH
	# 0.31.14 atmosphere (Kevin: "more atmosphere ... better lighting"): the haze starts nearer (aerial depth over the far
	# side of the field), scatters warm towards the sun, and settles a little in the low ground (river, gorges).
	env.fog_depth_begin = 48.0
	env.fog_depth_end = 270.0                  # the land ends at ~300 m: fully fogged there, so no rim shows
	env.fog_density = 0.9
	env.fog_sun_scatter = 0.22
	env.fog_height = -0.2
	env.fog_height_density = 0.05
	env.fog_sky_affect = 0.0                   # the sky itself stays clear
	# No glow in battle (0.14.3): it is full-screen blur passes at native resolution (~7 % of the
	# frame in tests/perf_bench.gd, and bandwidth-heavy on phones) for a bloom too faint to see.
	env.glow_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#ffdfb4")         # warmer (0.31.14), against the cool sky ambient
	sun.light_energy = 1.08
	sun.rotation_degrees = Vector3(-47, -33, 0)  # a little lower: longer, softer shadows give the ground depth
	# No real-time shadows: at this zoom they doubled every triangle for little visual gain.
	# Units are marked by team rings; HP bars are drawn on the 2D HUD.
	sun.shadow_enabled = false
	if _hq():
		_apply_hq(env, sun)
	add_child(sun)
	# Single directional light: the Compatibility renderer can add a per-object pass for each extra
	# directional light, so the old cool fill light is folded into ambient instead.
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.near = 0.3
	camera.far = 190.0
	add_child(camera)

func _mesh_of(path: String) -> Dictionary:
	var packed := Stage.scene(path)
	if packed == null:
		return {}
	var holder := packed.instantiate()
	var found := holder.find_children("*", "MeshInstance3D", true, false)
	var out := {}
	if not found.is_empty():
		var mi: MeshInstance3D = found[0]
		out = {"mesh":mi.mesh, "material":mi.get_active_material(0)}
	holder.free()
	return out

static var _terrain_meshes: Array = []
static var _terrain_mat: ShaderMaterial = null
static var _water_mat: ShaderMaterial = null

static func _terrain_material() -> ShaderMaterial:
	if _terrain_mat == null:
		var m := ShaderMaterial.new()
		m.shader = load("res://scripts/siege/terrain.gdshader")
		m.set_shader_parameter("grass_tex", load("res://assets/terrain/grass.png"))
		m.set_shader_parameter("path_tex", PATH_TEX)
		m.set_shader_parameter("rock_tex", load("res://assets/terrain/rock.png"))
		m.set_shader_parameter("path_mask", ImageTexture.create_from_image(load(Land.MASK_RES)))
		var r := Land.bake_rect()
		m.set_shader_parameter("mask_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
		# The battle view's Vulkan compensation (exposure x1.55) brightens everything; a neutral
		# (not yellowish) darkening keeps the grass a true green.
		# Measured against Kevin's references (grass hue ~111 deg, sat ~138, value ~190 of 255):
		# slightly darker and bluer than neutral.
		# Re-measured for the painted grass (0.14.4) against Kevin's references.
		m.set_shader_parameter("tint", Vector3(0.64, 0.73, 0.80))
		m.set_shader_parameter("grass_sat", 0.95)
		m.set_shader_parameter("band_strength", 1.6)     # between the 1x (faint) and 3x (bold) tests
		var mt := NoiseTexture2D.new()
		mt.width = 256
		mt.height = 256
		mt.seamless = true
		var fn := FastNoiseLite.new()
		fn.frequency = 0.012
		fn.fractal_octaves = 3
		mt.noise = fn
		m.set_shader_parameter("macro_tex", mt)
		m.set_shader_parameter("cloud_tex", _clouds())
		m.set_shader_parameter("cloud_strength", CLOUD_STRENGTH if _cast_static else 0.0)
		_terrain_mat = m
	return _terrain_mat

# ---------- the land beyond the playfield (0.19.4) ----------
static var _outer_meshes: Array = []
static var _outer_mat: ShaderMaterial = null
const OUTER_RINGS := [-1.0, 0.0, 2.0, 5.0, 9.0, 14.0, 21.0, 30.0, 42.0, 58.0, 80.0, 110.0, 150.0, 200.0, 260.0]
const OUTER_TREES := ["Tree_1_A_Color1", "Tree_2_A_Color1", "Tree_4_A_Color1"]

static func _outer_side_points(side: int) -> Array:
	# Points along one side of the baked rect, with their outward directions; each side also owns
	# the fan of directions around its first corner, so the four sides tile the ring.
	var r := Land.bake_rect()
	var c := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var nrm := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
	var a: Vector2 = c[side]
	var b: Vector2 = c[(side + 1) % 4]
	var n: Vector2 = nrm[side]
	var prev: Vector2 = nrm[(side + 3) % 4]
	var pts := []
	for k in 6:                                   # corner fan from the previous side's normal to ours
		pts.append([a, prev.slerp(n, k / 6.0).normalized()])
	var len := a.distance_to(b)
	var steps := int(ceil(len / 2.0))
	for k in steps + 1:
		pts.append([a.lerp(b, float(k) / steps), n])
	return pts

static func _make_outer_meshes() -> Array:
	var out := []
	for side in 4:
		var pts := _outer_side_points(side)
		var np := pts.size()
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var idx := PackedInt32Array()
		for ring in OUTER_RINGS.size():
			var d: float = OUTER_RINGS[ring]
			for pt in pts:
				var p: Vector2 = (pt[0] as Vector2) + (pt[1] as Vector2) * d
				# The first ring tucks 1 m under the terrain's edge so no crack can show.
				var y: float = Land.terrain_height(pt[0]) - 0.06 if d <= 0.0 else Land.outer_height(p)
				verts.append(Vector3(p.x, y, p.y))
				var e := 1.0
				var hx := Land.outer_height(p + Vector2(e, 0)) - Land.outer_height(p - Vector2(e, 0))
				var hz := Land.outer_height(p + Vector2(0, e)) - Land.outer_height(p - Vector2(0, e))
				norms.append(Vector3(-hx, 2.0 * e, -hz).normalized())
		for ring in OUTER_RINGS.size() - 1:
			for k in np - 1:
				var a := ring * np + k
				var b := a + np
				# Every side runs the same way round the map with rings going outward, so one winding
				# faces up on all four. (0.19.4 special-cased sides 1 and 2 the wrong way round: they
				# were culled and the sky's grey underside showed through -- Kevin's screenshots.)
				idx.append_array([a, b, a + 1, a + 1, b, b + 1])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_INDEX] = idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.append(am)
	return out

func _build_outer_land() -> void:
	if _outer_meshes.is_empty():
		_outer_meshes = _make_outer_meshes()
	if _outer_mat == null:
		var tm: ShaderMaterial = _terrain_material()
		_outer_mat = ShaderMaterial.new()
		_outer_mat.shader = load("res://scripts/siege/outer_land.gdshader")
		for k in ["grass_tex", "rock_tex", "path_mask", "mask_rect", "grass_scale", "rock_scale", "tint", "grass_sat", "band_strength",
				"cloud_tex", "cloud_strength", "macro_tex", "rock_col"]:
			_outer_mat.set_shader_parameter(k, tm.get_shader_parameter(k))
	for m in _outer_meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = _outer_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta("perf", "outer_land")
		add_child(mi)
	_build_outer_trees()

func _build_outer_trees() -> void:
	# Groves in the meadows and on the lower hills: batched per side and tree type (MultiMesh), so
	# a side off-screen costs nothing. Not in the river, not on steep or high ground.
	var r := Land.bake_rect()
	var rng := RandomNumberGenerator.new()
	rng.seed = 911
	var per := {}                                     # "side:type" -> Array[Transform3D]
	var placed := 0
	var tries := 0
	while placed < 420 and tries < 9000:             # 260 until 0.31.12: the valley's hills get their woods too
		tries += 1
		var d := 2.0 + pow(rng.randf(), 1.7) * 150.0           # denser near the playfield
		var side := rng.randi() % 4
		if side == 1 and rng.randf() < 0.5:
			d = 30.0 + rng.randf() * 190.0                      # the valley beyond the cliff side: woods all the way up
		var along := rng.randf()
		var q: Vector2
		var n: Vector2
		match side:
			0: q = Vector2(lerpf(r.position.x, r.end.x, along), r.position.y); n = Vector2(0, -1)
			1: q = Vector2(r.end.x, lerpf(r.position.y, r.end.y, along)); n = Vector2(1, 0)
			2: q = Vector2(lerpf(r.end.x, r.position.x, along), r.end.y); n = Vector2(0, 1)
			_: q = Vector2(r.position.x, lerpf(r.end.y, r.position.y, along)); n = Vector2(-1, 0)
		var p := q + n * d + Vector2(n.y, -n.x) * rng.randf_range(-6.0, 6.0)
		# Groves, not an even carpet.
		if sin(p.x * 0.09 + 1.1) * sin(p.y * 0.08 + 0.3) + rng.randf() * 0.6 < 0.25:
			continue
		if absf(p.y - Land.river_c(p.x)) < Land.RIVER_HW + 4.0:
			continue
		var h := Land.outer_height(p)
		var slope := absf(Land.outer_height(p + Vector2(1, 0)) - Land.outer_height(p - Vector2(1, 0))) \
			+ absf(Land.outer_height(p + Vector2(0, 1)) - Land.outer_height(p - Vector2(0, 1)))
		if h > 22.0 or slope > 1.4 or p.distance_to(q) < 1.5:
			continue
		var t := rng.randi() % OUTER_TREES.size()
		var sc := rng.randf_range(0.6, 1.0)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(p.x, h - 0.1, p.y))
		var key := "%d:%d" % [side, t]
		if not per.has(key):
			per[key] = []
		(per[key] as Array).append(xf)
		placed += 1
	for key in per:
		var t := int(str(key).split(":")[1])
		var packed := Stage.scene(FOREST + OUTER_TREES[t] + ".gltf")
		if packed == null:
			continue
		var node: Node3D = packed.instantiate()
		var src: MeshInstance3D = node.find_children("*", "MeshInstance3D", true, false)[0]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = src.mesh
		var list: Array = per[key]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, (list[i] as Transform3D) * src.transform)
		node.free()
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.set_meta("perf", "outer_trees")
		add_child(mmi)

static func _make_terrain_meshes() -> Array:
	# One mesh per 32 m band (tight AABBs -> off-screen bands are culled), vertices every
	# BAKE_STEP metres straight from the baked height map, normals by central differences.
	var img: Image = load(Land.HEIGHT_RES)
	var nx := img.get_width()
	var nz := img.get_height()
	var h := img.get_data().to_float32_array()
	var r := Land.bake_rect()
	var st := Land.BAKE_STEP
	var out := []
	var band := int(32.0 / st)
	var j0 := 0
	while j0 < nz - 1:
		var j1 := mini(nz - 1, j0 + band)
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var idx := PackedInt32Array()
		for j in range(j0, j1 + 1):
			for i in nx:
				var y := h[j * nx + i]
				verts.append(Vector3(r.position.x + i * st, y, r.position.y + j * st))
				var hl := h[j * nx + maxi(i - 1, 0)]
				var hr := h[j * nx + mini(i + 1, nx - 1)]
				var hd := h[maxi(j - 1, 0) * nx + i]
				var hu := h[mini(j + 1, nz - 1) * nx + i]
				norms.append(Vector3(hl - hr, 2.0 * st, hd - hu).normalized())
		var rows := j1 - j0 + 1
		for jj in rows - 1:
			for i in nx - 1:
				var a := jj * nx + i
				idx.append_array([a, a + 1, a + nx, a + 1, a + nx + 1, a + nx])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_INDEX] = idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.append(am)
		j0 = j1
	return out

func _build_terrain() -> void:
	# Round 7: a single height-mapped ground (grass, herringbone paths, rock ledges) built from the
	# baked landscape; cached for the session so rematches don't rebuild it.
	if _terrain_meshes.is_empty():
		_terrain_meshes = _make_terrain_meshes()
	for m in _terrain_meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = _terrain_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta("perf", "terrain")
		add_child(mi)
	_build_water()
	_build_outer_land()
	_build_bridges()
	_build_foliage()

func _build_water() -> void:
	_water_mat = null                 # rebuilt per match: the High-quality setting may have changed
	if _hq():
		_water_mat = _water_hq_material()
		_build_ripples()
	if _water_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D ripples : filter_linear_mipmap, repeat_enable;
uniform float glint = 0.0;
void fragment() {
	vec2 w = UV * vec2(18.0, 1.0);
	float a = texture(ripples, w * 0.35 + vec2(TIME * 0.05, TIME * 0.02)).r;
	float b = texture(ripples, w * 0.21 - vec2(TIME * 0.03, 0.0)).r;
	float n = a * 0.6 + b * 0.4;
	float shore = 1.0 - smoothstep(0.0, 0.16, min(UV2.y, 1.0 - UV2.y));
	vec3 deep = vec3(0.10, 0.42, 0.72);
	vec3 shallow = vec3(0.22, 0.66, 0.86);
	vec3 col = mix(deep, shallow, smoothstep(0.35, 0.75, n));
	col *= 1.0 - shore * 0.18;                     // no foam (Round 34): the banks just shade a little
	ALBEDO = col;
	ROUGHNESS = 0.18;
	SPECULAR = 0.35;                  // 0.30.11: was 0.6 (see the high-quality water)
	// Sun glints (High-quality graphics): sparse sparkles where two scrolling layers line up; bright enough to glow.
	float sg = texture(ripples, w * 1.3 + vec2(-TIME * 0.09, TIME * 0.05)).r * texture(ripples, w * 0.9 + vec2(TIME * 0.07, -TIME * 0.04)).r;
	EMISSION = vec3(1.0, 0.97, 0.88) * smoothstep(0.58, 0.64, sg) * glint;      // sparse: only the brightest crossings
}
"""
		var m := ShaderMaterial.new()
		m.shader = sh
		var nt := NoiseTexture2D.new()
		nt.width = 256
		nt.height = 256
		nt.seamless = true
		var fn := FastNoiseLite.new()
		fn.frequency = 0.04
		nt.noise = fn
		m.set_shader_parameter("ripples", nt)
		m.set_shader_parameter("glint", 1.3 if _cast_static else 0.0)
		_water_mat = m
	# The river runs on out of the map both ways (0.19.4; 0.31.13: no more waterfall -- the east is a valley like the west).
	var x0 := -Sim.HALF_W - Land.BAKE_MARGIN - Land.OUTER_REACH
	var x1 := Sim.HALF_W + Land.BAKE_MARGIN + Land.OUTER_REACH
	var span := 2.0 * (Sim.HALF_W + Land.BAKE_MARGIN)
	_water_strip(x0, x1, Land.WATER_Y, span, "water")

func _water_strip(xa: float, xb: float, y: float, span: float, tag: String) -> void:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()
	var n := int(ceil(xb - xa))
	for k in n + 1:
		var x := minf(xa + k, xb)
		var c := Land.river_c(x)
		var hw := Land.river_hw(x) + 0.35
		verts.append(Vector3(x, y, c - hw))
		verts.append(Vector3(x, y, c + hw))
		uvs.append(Vector2((x - xa) / span, 0.5 - hw / RIP_ACROSS))
		uvs.append(Vector2((x - xa) / span, 0.5 + hw / RIP_ACROSS))
		uv2s.append(Vector2(0.0, 0.0))
		uv2s.append(Vector2(0.0, 1.0))
		if k < n:
			var a := k * 2
			idx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = _water_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("perf", tag)
	add_child(mi)

static var _fall_mat: ShaderMaterial = null

func _build_bridges() -> void:
	for b in Land.bridges():
		var n := _place("res://assets/terrain/bridge.glb", Vector3(b.c.x, 0.0, b.c.y), 0.0, 1.0)
		if n != null:
			n.scale = Vector3(float(b.sx), 1.0, float(b.sz))

# ---------- foliage: grass tufts + flowers (Round 7b) ----------
# 44-triangle tufts only (Grass_1_B is 132 triangles; dropped in 0.14.2 for frame rate).
const TUFTS := ["Grass_1_A_Color1", "Grass_2_A_Color1"]
const FLOWERS := ["red", "blue", "yellow", "white"]
static var _foliage: Dictionary = {}          # kind -> Array[Transform3D], built once per session

static func _foliage_ok(p: Vector2, mask: Image, obstacles: Array, allow_slope := false) -> bool:
	if absf(p.x) > Sim.HALF_W - 0.6 or absf(p.y) > Sim.HALF_L - 0.6:
		return false
	if Land.shore(p) < 0.9 or Land.edge_dist(p) > -0.9 or Land.on_bridge(p, 0.6):
		return false
	if absf(p.x) <= Sim.CASTLE_HX + 1.5 and absf(p.y) >= Sim.CASTLE_SHIFT + Sim.FRONT_Z - 1.5:
		return false
	if Land.in_dungeon_pit(p, 1.5):
		return false                          # the dungeon wing's floor and walls (Kevin: grass on the floor)
	var r := Land.bake_rect()
	var px := Vector2i(clampi(int((p.x - r.position.x) * Land.MASK_PPM), 0, mask.get_width() - 1),
		clampi(int((p.y - r.position.y) * Land.MASK_PPM), 0, mask.get_height() - 1))
	var mk := mask.get_pixelv(px)
	if mk.r > 0.12:
		return false                          # on a brick path
	if not allow_slope and mk.g > 0.3:
		return false                          # on a ledge rim / cliff band
	for ob in obstacles:
		if p.distance_to(ob.p) < float(ob.r) + 0.5:
			return false
	return true

static func _foliage_xf(p: Vector2, rng: RandomNumberGenerator, s0: float, s1: float) -> Transform3D:
	var y := Land.ground_height(p, false)
	var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(s0, s1))
	return Transform3D(b, Vector3(p.x, y - 0.03, p.y))

func _plan_foliage() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 707
	var mask: Image = load(Land.MASK_RES)
	var obs: Array = sim.obstacles
	var out := {}
	for k in TUFTS + FLOWERS:
		out[k] = []
	var tuft := func(p: Vector2, allow_slope := false):
		if _foliage_ok(p, mask, obs, allow_slope):
			out[TUFTS[rng.randi() % TUFTS.size()]].append(_foliage_xf(p, rng, 1.2, 1.7))
	# 1. Both edges of every brick path (the grassy borders of the references).
	for pl in Land.paths():
		for i in range(pl.size() - 1):
			var a: Vector2 = pl[i]
			var b: Vector2 = pl[i + 1]
			var d := (b - a).normalized()
			var n := Vector2(-d.y, d.x)
			var L := a.distance_to(b)
			var t := 0.0
			while t < L:
				for side in [-1.0, 1.0]:
					if rng.randf() < 0.6:
						tuft.call(a + d * (t + rng.randf_range(-0.3, 0.3)) + n * side * (Land.PATH_HALF_W + rng.randf_range(0.05, 0.45)))
				t += 0.9
	# 2. Along the top of every scarp (natural hills, 0.30.2).
	for half in [1.0, -1.0]:
		for sc in Land.SCARPS:
			var pts: Array = sc.pts
			var cen: Vector2 = (Land.HILLS[int(sc.hill)] as Dictionary).c
			for i in pts.size() - 1:
				var a: Vector2 = pts[i]
				var b: Vector2 = pts[i + 1]
				var L := a.distance_to(b)
				var t := 0.4
				while t < L - 0.4:
					var q := a.lerp(b, t / L)
					q += (cen - q).normalized() * rng.randf_range(0.3, 0.8)
					if rng.randf() < 0.65:
						tuft.call(q * half, true)
					t += 0.85
	# 2b. A ring of grass and a few flowers round each tower's foot (0.30.1, Kevin).
	for op in sim.outposts:
		var c: Vector2 = op.p
		for k in 54:
			var a := rng.randf() * TAU
			var q := c + Vector2(cos(a), sin(a)) * (Land.OUTPOST_TOWER_R + rng.randf_range(-0.05, 1.0))
			if Land.shore(q) > 0.9 and Land.edge_dist(q) < -0.9:
				out[TUFTS[rng.randi() % TUFTS.size()]].append(_foliage_xf(q, rng, 1.3, 1.9))
		for k in 10:
			var a := rng.randf() * TAU
			var q := c + Vector2(cos(a), sin(a)) * (Land.OUTPOST_TOWER_R + rng.randf_range(0.3, 1.3))
			if Land.shore(q) > 0.9 and Land.edge_dist(q) < -0.9:
				out[FLOWERS[rng.randi() % FLOWERS.size()]].append(_foliage_xf(q, rng, 2.0, 2.6))
	# 3. Clumps across the fields.
	for c in 520:
		var cp := Vector2(rng.randf_range(-Sim.HALF_W, Sim.HALF_W), rng.randf_range(-Sim.HALF_L, Sim.HALF_L))
		for k in rng.randi_range(2, 5):
			tuft.call(cp + Vector2(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.8, 0.8)))
	# 4. Flower clusters.
	for c in 230:
		var cp := Vector2(rng.randf_range(-Sim.HALF_W, Sim.HALF_W), rng.randf_range(-Sim.HALF_L, Sim.HALF_L))
		var col: String = FLOWERS[[0, 0, 0, 1, 1, 1, 2, 2, 3][rng.randi() % 9]]
		for k in rng.randi_range(2, 4):
			var fp := cp + Vector2(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.7, 0.7))
			if _foliage_ok(fp, mask, obs):
				out[col].append(_foliage_xf(fp, rng, 2.0, 2.6))
	return out

func _build_foliage() -> void:
	if _foliage.is_empty():
		_foliage = _plan_foliage()
	for kind in _foliage:
		var xfs: Array = _foliage[kind]
		if low_fx:
			# "Reduce effects": every other instance.
			xfs = xfs.filter(func(_x): return true).slice(0, xfs.size(), 2)
		var src: Dictionary
		if kind in FLOWERS:
			src = _mesh_of("res://assets/terrain/flower_%s.glb" % kind)
		else:
			src = _mesh_of(FOREST + kind + ".gltf")
		if src.is_empty():
			continue
		# One MultiMesh per 32 m band so off-screen bands are culled.
		var bands := {}
		for xf in xfs:
			var bkey := int(floor((xf.origin.z + Sim.HALF_L) / 32.0))
			if not bands.has(bkey):
				bands[bkey] = []
			bands[bkey].append(xf)
		for bkey in bands:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = src.mesh
			mm.instance_count = bands[bkey].size()
			for i in mm.instance_count:
				mm.set_instance_transform(i, bands[bkey][i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.set_meta("perf", "foliage")
			mmi.set_meta("perf_kind", kind)
			mmi.visibility_range_end = 70.0          # bands far up-screen are tiny anyway
			if kind in TUFTS:
				mmi.material_override = _tuft_material(src.material)
			else:
				mm.mesh = _cheap_flower_mesh(src.mesh)
			add_child(mmi)

static var _tuft_mat: StandardMaterial3D = null
static var _tuft_wind: ShaderMaterial = null
static func _tuft_material(base: Material) -> Material:
	if _cast_static:
		# High-quality graphics: the tufts sway in rolling gusts (tips move, roots stay), lit per vertex like before.
		if _tuft_wind == null:
			var sh := Shader.new()
			sh.code = """
shader_type spatial;
render_mode cull_disabled, vertex_lighting, specular_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 albedo_col : source_color = vec4(1.0);
uniform bool use_tex = false;
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp(VERTEX.y / 0.5, 0.0, 1.0);
	float gust = sin(TIME * 1.3 + wp.x * 0.18 + wp.z * 0.11) * 0.5 + 0.5;
	float flutter = sin(TIME * 4.2 + wp.x * 1.3 + wp.z * 0.9);
	float sway = (gust * 0.10 + flutter * 0.025) * h;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.5;
}
void fragment() {
	vec3 c = albedo_col.rgb;
	if (use_tex) { c *= texture(albedo_tex, UV).rgb; }
	ALBEDO = c;
}
"""
			var m := ShaderMaterial.new()
			m.shader = sh
			var sm := base as StandardMaterial3D
			var col := Color(1.0, 1.18, 0.82)
			if sm != null:
				col = sm.albedo_color * Color(1.0, 1.18, 0.82)
				if sm.albedo_texture != null:
					m.set_shader_parameter("albedo_tex", sm.albedo_texture)
					m.set_shader_parameter("use_tex", true)
			m.set_shader_parameter("albedo_col", col)
			_tuft_wind = m
		return _tuft_wind
	return _tuft_material_plain(base)

static func _tuft_material_plain(base: Material) -> StandardMaterial3D:
	# Match the tufts to the terrain's green; per-vertex lighting (identical on tiny triangles,
	# cheaper per pixel on phones).
	if _tuft_mat == null:
		_tuft_mat = (base as StandardMaterial3D).duplicate() if base is StandardMaterial3D else StandardMaterial3D.new()
		_tuft_mat.albedo_color = Color(1.0, 1.18, 0.82)
		_tuft_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		_tuft_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return _tuft_mat

static var _flower_meshes: Dictionary = {}
static func _cheap_flower_mesh(mesh: Mesh) -> Mesh:
	# The Blender flowers export double-sided; their petals are closed shapes, so back faces are
	# never seen: cull them, and light per vertex. A MultiMesh has no per-surface overrides, so
	# this is a cached copy of the mesh with the cheaper materials baked in.
	if not _flower_meshes.has(mesh):
		var copy: Mesh = mesh.duplicate()
		for sidx in copy.get_surface_count():
			var base := copy.surface_get_material(sidx)
			if base is StandardMaterial3D:
				var m: StandardMaterial3D = (base as StandardMaterial3D).duplicate()
				m.cull_mode = BaseMaterial3D.CULL_BACK
				m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
				m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				copy.surface_set_material(sidx, m)
		_flower_meshes[mesh] = copy
	return _flower_meshes[mesh]

# ---------- hats (Round 8) ----------
const HAT_COLOR := {"knight":Color("#9fb6c8"), "barbarian":Color("#e0875a"), "rogue":Color("#6fd46a"),
	"ranger":Color("#e8c65a"), "mage":Color("#a879ff"), "worker":Color("#c8a27a"), "priest":Color("#fff4d0")}
static var _hat_mesh: ArrayMesh = null
static var _hat_mats: Dictionary = {}
var stand_nodes: Dictionary = {}       # stand id -> Array of 3 hat MeshInstance3D
var hat_nodes: Dictionary = {}         # dropped hat id -> Node3D

static func _hat_shape() -> ArrayMesh:
	# A pointed hat with a brim (cone + flat disc), built once.
	if _hat_mesh == null:
		var st := SurfaceTool.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.2
		cone.height = 0.34
		cone.radial_segments = 10
		cone.rings = 1
		var brim := CylinderMesh.new()
		brim.top_radius = 0.33
		brim.bottom_radius = 0.33
		brim.height = 0.04
		brim.radial_segments = 14
		brim.rings = 1
		st.append_from(cone, 0, Transform3D(Basis(), Vector3(0, 0.19, 0)))
		st.append_from(brim, 0, Transform3D(Basis(), Vector3(0, 0.02, 0)))
		_hat_mesh = st.commit()
	return _hat_mesh

static func _hat_mat(cls: String, up: bool) -> StandardMaterial3D:
	var key := "%s|%s" % [cls, up]
	if not _hat_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = HAT_COLOR.get(cls, Color.WHITE)
		m.roughness = 0.6
		if up:
			m.emission_enabled = true               # upgraded hats glow a little (static, set once)
			m.emission = Color("#ffd46a")
			m.emission_energy_multiplier = 0.35
		_hat_mats[key] = m
	return _hat_mats[key]

func _hat_instance(cls: String, up: bool, scale_k: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _hat_shape()
	mi.material_override = _hat_mat(cls, up)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * scale_k
	return mi

# Hat machines (Round 11, Kevin): one themed structure per class, with an upgraded look that
# appears once the team buys that class's hat upgrade. Pieces: [path, offset (x, y, z) in the
# machine's frame, yaw, scale]. "bits/" = KayKit Fantasy Weapons Bits, "%s" = team colour.
var machine_up: Dictionary = {}        # stand id -> {"up": Node3D, "glow": MeshInstance3D, "state": bool}

func _build_hat_stands() -> void:
	# Hat shops are buildings (Round 20): the class's building, team-coloured, its door facing the way
	# HAT_SHOPS says; the take ring at the door; a team flag on the roof once the class is upgraded.
	for st in sim.stands:
		var cls := str(st.cls)
		var t := int(st.team)
		var col: String = COLOR[t]
		var shop: Dictionary = Castle.HAT_SHOPS[Sim.HAT_CLASSES.find(cls)]
		var bp: Vector2 = st.b
		var face := 0.0 if t == 0 else PI
		var node := _place(HEX + (str(shop.model) % col) + ".gltf", Vector3(bp.x, float(shop.y), bp.y), face + deg_to_rad(float(shop.rot)), float(shop.scale))
		if node != null:
			node.set_meta("perf", "hat_shop")
		var gy := Sim.height_at(st.p)
		_decal(Vector3(st.p.x, gy + 0.06, st.p.y), Sim.HAT_TAKE_R, HAT_COLOR[cls], 0.5)
		var flag := _place(HEX + "flag_%s.gltf" % col, Vector3(bp.x, float(shop.y) + 3.4, bp.y), face, 2.2)
		if flag != null:
			flag.visible = false
		machine_up[st.id] = {"up": flag if flag != null else Node3D.new(), "glow": null, "state": false}
		stand_nodes[st.id] = []

# Whirlwind FX (Round 12, Kevin: "spin visuals like World of Warcraft"): two translucent blade-trail
# ribbons (partial rings fading along their arc) circling the berserker at different heights and
# tilts, spinning faster than the body; built once per unit, then only rotated (transform only).
var whirl_nodes: Dictionary = {}
static var _whirl_mesh: ArrayMesh = null
static var _whirl_mat: StandardMaterial3D = null

static func _whirl_ribbon() -> ArrayMesh:
	if _whirl_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var seg := 28
		var arc := TAU * 0.72
		for i in seg:
			var t0 := float(i) / seg
			var t1 := float(i + 1) / seg
			var pts := []
			for t in [t0, t1]:
				var ang: float = arc * t
				var fade: float = pow(t, 1.6)                  # bright at the leading edge
				var inner := Vector3(cos(ang), 0, sin(ang)) * 0.62
				var outer := Vector3(cos(ang), 0, sin(ang)) * 1.0
				pts.append([inner + Vector3(0, -0.12, 0), outer + Vector3(0, 0.12, 0), fade])
			var a0: Array = pts[0]
			var a1: Array = pts[1]
			for v in [[a0[0], a0[2]], [a1[0], a1[2]], [a1[1], a1[2]], [a0[0], a0[2]], [a1[1], a1[2]], [a0[1], a0[2]]]:
				st.set_color(Color(1, 1, 1, float(v[1])))
				st.add_vertex(v[0])
		_whirl_mesh = st.commit()
	return _whirl_mesh

func _sync_whirls() -> void:
	if _whirl_mat == null:
		_whirl_mat = StandardMaterial3D.new()
		_whirl_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_whirl_mat.vertex_color_use_as_albedo = true
		_whirl_mat.albedo_color = Color(0.92, 0.95, 1.0, 0.75)
		_whirl_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_whirl_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_whirl_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for u in sim.units:
		var fx: Node3D = whirl_nodes.get(u.id)
		if not sim.whirling(u):
			if fx != null:
				fx.visible = false
			continue
		if fx == null:
			fx = Node3D.new()
			for k in 2:
				var mi := MeshInstance3D.new()
				mi.mesh = _whirl_ribbon()
				mi.material_override = _whirl_mat
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				fx.add_child(mi)
			add_child(fx)
			whirl_nodes[u.id] = fx
		var a: Dictionary = actors.get(u.id, {})
		if a.is_empty():
			fx.visible = false
			continue
		fx.visible = true
		fx.position = (a.root as Node3D).position
		var r0 := fx.get_child(0) as Node3D
		var r1 := fx.get_child(1) as Node3D
		# Faster than the body (4 turns/s): ~7 and ~5.5 turns/s, tilted opposite ways.
		r0.transform = Transform3D(Basis(Vector3.UP, -_time * 44.0).rotated(Vector3.RIGHT, 0.18).scaled(Vector3(2.3, 1.0, 2.3)), Vector3(0, 1.05, 0))
		r1.transform = Transform3D(Basis(Vector3.UP, -_time * 34.0 + 2.0).rotated(Vector3.RIGHT, -0.22).scaled(Vector3(2.7, 1.0, 2.7)), Vector3(0, 0.6, 0))

var shield_nodes: Dictionary = {}        # knight id -> translucent shield-wall panel
static var _shield_mat: StandardMaterial3D = null

func _sync_shields() -> void:
	# A translucent panel where the sim's shield segment is, while a knight blocks (transform only).
	if _shield_mat == null:
		_shield_mat = StandardMaterial3D.new()
		_shield_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shield_mat.albedo_color = Color(0.55, 0.8, 1.0, 0.32)
		_shield_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shield_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for u in sim.units:
		if u.cls != "knight":
			continue
		var n: MeshInstance3D = shield_nodes.get(u.id)
		if not sim.blocking(u):
			if n != null:
				n.visible = false
			continue
		if n == null:
			n = MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(1.0, 1.6)
			n.mesh = q
			n.material_override = _shield_mat
			n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(n)
			shield_nodes[u.id] = n
		var sg: Array = sim.shield_seg(u)
		var a2: Vector2 = sg[0]
		var b2: Vector2 = sg[1]
		var mid := (a2 + b2) * 0.5
		var y := Sim.height_at(mid) + 0.85
		var along := Vector3(b2.x - a2.x, 0, b2.y - a2.y)
		n.visible = true
		n.transform = Transform3D(Basis(along, Vector3.UP, along.normalized().cross(Vector3.UP)), Vector3(mid.x, y, mid.y))

var beam_nodes: Dictionary = {}          # priest unit id -> MeshInstance3D (unit-length cylinder)

static var _beam_mats := {}

func _beam_material(key: String) -> StandardMaterial3D:
	if not _beam_mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = {"heal":Color(1.0, 0.95, 0.55, 0.75), "drain":Color(0.35, 1.0, 0.4, 0.85), "white":Color(1.0, 1.0, 1.0, 0.85)}[key]
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_beam_mats[key] = m
	return _beam_mats[key]

func _sync_beams() -> void:
	# The Priest's gold healing beam; the Necromancer's green drain on an enemy plus a white heal to an ally (0.31.2).
	for u in sim.units:
		var necro: bool = u.cls == "priest" and bool(u.get("up", false))
		for slot in [["beam", str(u.id), "drain" if necro else "heal"], ["beam2", str(u.id) + "#2", "white"]]:
			var n: MeshInstance3D = beam_nodes.get(slot[1])
			var to: Dictionary = sim.by_id.get(str(u.get(slot[0], "")), {})
			if to.is_empty() or not sim.alive(u):
				if n != null:
					n.visible = false
				continue
			if n == null:
				n = MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.07
				cm.bottom_radius = 0.07
				cm.height = 1.0
				cm.radial_segments = 6
				cm.rings = 1
				n.mesh = cm
				n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(n)
				beam_nodes[slot[1]] = n
			n.material_override = _beam_material(slot[2])
			var a: Dictionary = actors.get(u.id, {})
			var b: Dictionary = actors.get(to.id, {})
			if a.is_empty() or b.is_empty():
				n.visible = false
				continue
			var p0: Vector3 = (a.root as Node3D).position + Vector3(0, 1.35, 0) + Vector3(sin(float(u.face)), 0, cos(float(u.face))) * 0.35
			var p1: Vector3 = (b.root as Node3D).position + Vector3(0, 1.1, 0)
			var len := p0.distance_to(p1)
			if len < 0.05:
				n.visible = false
				continue
			n.visible = true
			# A unit cylinder along Y, stretched to the beam's length and aimed at the target; it flickers a little in width.
			var up := (p1 - p0) / len
			var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
			var fwd := side.cross(up)
			var w := (1.25 if slot[2] == "drain" else 1.0) + 0.25 * sin(_time * 25.0 + float(hash(slot[1]) % 100))
			n.transform = Transform3D(Basis(side * w, up * len, fwd * w), (p0 + p1) * 0.5)

func _sync_hats() -> void:
	for st in sim.stands:
		var stack: Array = stand_nodes.get(st.id, [])
		for k in stack.size():
			(stack[k] as Node3D).visible = k < int(st.stock)
		# Upgraded look once the team owns this class's hat upgrade.
		var mu: Dictionary = machine_up.get(st.id, {})
		if not mu.is_empty():
			var up: bool = int(sim.levels[int(st.team)].get("hat_" + str(st.cls), 0)) > 0
			if up != bool(mu.state):
				mu.state = up
				(mu.up as Node3D).visible = up
				if mu.glow != null:
					(mu.glow as Node3D).scale = Vector3.ONE * (1.8 if up else 1.0)
					(mu.glow as Node3D).position.y += 0.25 if up else -0.25
	# Dropped hats: add new ones, drop vanished ones, bob and spin (transforms only).
	var seen := {}
	for h in sim.hats:
		seen[h.id] = true
		var n: Node3D = hat_nodes.get(h.id)
		if n == null:
			n = Node3D.new()
			add_child(n)
			n.add_child(_hat_instance(str(h.cls), bool(h.up), 1.9))
			var ring := _decal(Vector3.ZERO, 0.75, HAT_COLOR.get(str(h.cls), Color.WHITE), 0.55)
			ring.reparent(n, false)
			hat_nodes[h.id] = n
		var gy := Sim.height_at(h.pos)
		n.position = Vector3(h.pos.x, gy, h.pos.y)
		var hat := n.get_child(0) as Node3D
		hat.position.y = 0.25 + 0.12 * sin(_time * 3.0 + float(h.id))
		hat.rotation.y = _time * 1.6 + float(h.id)
	for id in hat_nodes.keys():
		if not seen.has(id):
			(hat_nodes[id] as Node3D).queue_free()
			hat_nodes.erase(id)

var outpost_nodes: Dictionary = {}

func _build_outposts() -> void:
	for op in sim.outposts:
		# 0.30.3 (Kevin: "remove the roofs ... so you can see players on them and widen their size so players can
		# walk around on top"): the KayKit tower body only (its roof piece hidden), x6 wide and x4 tall, with a
		# plank deck inside its rim; the owner's flag flies from the rim. Sunk a little, bushes and grass round
		# the foot. The capture ring is painted on the ground by the terrain shader (_sync_outposts).
		var p := Vector3(op.p.x, Sim.height_at(op.p) - 0.14, op.p.y)
		var looks := {}
		looks[-1] = _tower_body(HEX + "building_tower_base_blue.gltf", p)
		looks[0] = _tower_body(HEX + "building_tower_A_blue.gltf", p)
		looks[1] = _tower_body(HEX + "building_tower_A_red.gltf", p)
		var deck := MeshInstance3D.new()
		var dm := CylinderMesh.new()
		dm.top_radius = 2.35
		dm.bottom_radius = 2.35
		dm.height = 0.12
		dm.radial_segments = 24
		deck.mesh = dm
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color("#9c7a52")
		wood.roughness = 0.9
		deck.material_override = wood
		deck.position = Vector3(p.x, Sim.height_at(op.p) + Land.TOWER_FLOOR - 0.06, p.z)
		add_child(deck)
		var flags := {}
		var top_y := Sim.height_at(op.p) + Land.TOWER_FLOOR
		for t in 2:
			flags[t] = _place(HEX + "flag_%s.gltf" % COLOR[t], Vector3(p.x + 1.75, top_y, p.z + 1.75), 0.0, 2.6)
		_dress_tower_base(op.p, int(op.id))
		outpost_nodes[op.id] = {"looks":looks, "flags":flags, "owner":-2}

func _tower_body(path: String, at: Vector3) -> Node3D:
	var n := _place(path, at, 0.3, 1.0)
	if n == null:
		return null
	n.scale = Land.TOWER_SCALE
	for c in n.find_children("*", "Node3D", true, false):
		if "_top_" in str(c.name):
			(c as Node3D).visible = false              # the roof and its band of windows
	return n

func _dress_tower_base(c: Vector2, seed_id: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4400 + seed_id
	var r: float = Land.OUTPOST_TOWER_R
	for k in 7:
		var a := TAU * k / 7.0 + rng.randf_range(-0.25, 0.25)
		if absf(wrapf(a - PI * 0.25, -PI, PI)) < 0.45:
			continue                                   # leave the flag's corner clear
		var q := c + Vector2(cos(a), sin(a)) * (r + rng.randf_range(0.0, 0.35))
		var y := Land.ground_height(q, false) - 0.05
		_place(FOREST + ["Bush_1_A_Color1", "Bush_2_A_Color1"][k % 2] + ".gltf", Vector3(q.x, y, q.y), rng.randf() * TAU,
			rng.randf_range(4.5, 6.0) if k % 2 == 0 else rng.randf_range(2.3, 3.0))

func _sync_outposts() -> void:
	var posts := []
	var rings := []
	var caps := []
	for op in sim.outposts:
		var on: Dictionary = outpost_nodes.get(op.id, {})
		if on.is_empty():
			continue
		var owner: int = op.owner
		if owner != int(on.owner):
			on.owner = owner
			for k in on.looks:
				if on.looks[k] != null:
					(on.looks[k] as Node3D).visible = int(k) == owner
			for t in on.flags:
				if on.flags[t] != null:
					(on.flags[t] as Node3D).visible = int(t) == owner
		# Painted on the ground (0.30.3, Kevin: "make sure the capture rings paint on the ground"): the ring in the
		# owner's colour (white when neutral), and while a capture is under way a fill growing from the middle in
		# the capturing team's colour. Hills can't hide it: the terrain itself draws it.
		var pr: float = op.prog
		var rc: Color = Color(1, 1, 1) if owner < 0 else TEAM_COLORS[owner]
		var pc: Color = TEAM_COLORS[0] if pr > 0.0 else TEAM_COLORS[1]
		var capturing := absf(pr) > 0.02 and absf(pr) < 0.999
		posts.append(Vector4(op.p.x, op.p.y, Land.OUTPOST_R, absf(pr)))
		rings.append(Vector4(rc.r, rc.g, rc.b, 0.9 if owner >= 0 else 0.75))
		caps.append(Vector4(pc.r, pc.g, pc.b, 0.42 if capturing else 0.0))
	while posts.size() < 6:
		posts.append(Vector4(0, 0, 0, 0))
		rings.append(Vector4(0, 0, 0, 0))
		caps.append(Vector4(0, 0, 0, 0))
	var tm: ShaderMaterial = _terrain_material()
	tm.set_shader_parameter("posts", posts)
	tm.set_shader_parameter("post_ring", rings)
	tm.set_shader_parameter("post_cap", caps)

func _place(path: String, pos: Vector3, rot := 0.0, s := 1.0) -> Node3D:
	var packed := Stage.scene(path)
	if packed == null:
		return null
	var node: Node3D = packed.instantiate()
	node.position = pos
	node.rotation.y = rot
	node.scale = Vector3.ONE * s
	add_child(node)
	return node

func _build_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var forest_trees := ["Tree_1_A_Color1","Tree_1_B_Color1","Tree_2_A_Color1","Tree_2_B_Color1","Tree_3_A_Color1"]
	var tt := Time.get_ticks_msec()
	for t in 2:
		_build_castle(t)
		_merge_kit()          # per castle, so the one off-screen is culled as a whole
	build_times["  castles"] = Time.get_ticks_msec() - tt
	tt = Time.get_ticks_msec()
	# Midfield ruin and circular props from the sim.
	for ob in sim.obstacles:
		var p := Vector3(ob.p.x, 0, ob.p.y)
		match str(ob.kind):
			"rock":
				# Cover rocks (resource-node rocks are drawn by _build_nodes).
				if not ob.has("node"):
					_place(HEX + ["rock_single_D.gltf", "rock_single_E.gltf"][int(absf(ob.p.x)) % 2], p, absf(ob.p.y) * 0.37, float(ob.r) * 3.4)
			"workshop_building":
				_place(HEX + "building_market_%s.gltf" % COLOR[ob.team], p, -PI * 0.5 if ob.team == 0 else PI * 0.5, 2.0)
	_build_nodes()
	_build_outposts()
	_build_hat_stands()
	build_times["  props+nodes+stands"] = Time.get_ticks_msec() - tt
	tt = Time.get_ticks_msec()
	# Scenery beyond the field's edge (0.26.0): trees along the tops of the rock walls, none over
	# the cliff side or in the river's gorge; a few wooded hills further out.
	var loop := Land.edge_loop()
	for i in loop.size():
		var a: Vector2 = loop[i]
		var b: Vector2 = loop[(i + 1) % loop.size()]
		var L := a.distance_to(b)
		var nrm := Vector2((b - a).y, -(b - a).x).normalized()
		if Land.inside_field((a + b) * 0.5 + nrm * 1.5):
			nrm = -nrm
		var t := rng.randf_range(0.0, 2.0)
		while t < L:
			var q := a.lerp(b, t / L) + nrm * rng.randf_range(3.5, 7.5)
			if absf(q.y - Land.river_c(q.x)) > Land.RIVER_HW + 3.5 and not Land.in_dungeon_pit(q, 2.0):
				_place(FOREST + forest_trees[rng.randi() % forest_trees.size()] + ".gltf", Vector3(q.x, Land.terrain_height(q), q.y), rng.randf()*TAU, 0.5 + rng.randf()*0.2)
			t += rng.randf_range(4.0, 6.5)
	for p in [Vector3(-Sim.HALF_W - 8, 0.5, -40), Vector3(-Sim.HALF_W - 8, 0.5, 14), Vector3(-Sim.HALF_W - 8, 0.5, -10),
			Vector3(Sim.HALF_W - 4, 0.5, 64), Vector3(Sim.HALF_W - 4, 0.5, -64), Vector3(0, 0.5, -Sim.HALF_L - 8), Vector3(0, 0.5, Sim.HALF_L + 8)]:
		_place(HEX + "mountain_A_grass_trees.gltf", Vector3(p.x, Land.terrain_height(Vector2(p.x, p.z)) - 0.3, p.z), rng.randf()*TAU, 1.6)
	build_times["  edge scenery"] = Time.get_ticks_msec() - tt

const COLOR := ["blue", "red"]
static var _floor_mats: Dictionary = {}

func _floor(team: int, x0: float, x1: float, z0: float, z1: float, color: Color, y := 0.03) -> void:
	# Flat floor over the hex terrain for a castle room (coordinates in blue space, mirrored).
	var key := color.to_html()
	if not _floor_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.95
		_floor_mats[key] = m
	var pm := PlaneMesh.new()
	pm.size = Vector2(absf(x1 - x0), absf(z1 - z0))
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = _floor_mats[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var c: Vector2 = Sim._c(team, Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5))
	mi.position = Vector3(c.x, y, c.y)
	add_child(mi)

static var _block_mats: Dictionary = {}
static var _box: BoxMesh

func _stone(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _block_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.92
		_block_mats[key] = m
	return _block_mats[key]

func _block(team: int, x0: float, x1: float, z0: float, z1: float, h: float, top: Color, castle := true) -> void:
	# A raised stone platform (blue-space coords, mirrored for red): stone sides, coloured top.
	if _box == null:
		_box = BoxMesh.new()
		_box.size = Vector3.ONE
	var mid := Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5)
	var c: Vector2 = Sim._c(team, mid) if castle else Sim._m(team, mid)
	var body := MeshInstance3D.new()
	body.mesh = _box
	body.material_override = _stone(Color("#a09580"))
	body.scale = Vector3(absf(x1 - x0), h, absf(z1 - z0))
	body.position = Vector3(c.x, h * 0.5, c.y)
	add_child(body)
	var pm := PlaneMesh.new()
	pm.size = Vector2(absf(x1 - x0), absf(z1 - z0))
	var lid := MeshInstance3D.new()
	lid.mesh = pm
	lid.material_override = _stone(top)
	lid.cast_shadow = _cast()
	lid.position = Vector3(c.x, h + 0.01, c.y)
	add_child(lid)

func _wall_run(a: Vector2, b: Vector2, path: String, y := 0.0, clip := true, inside := Vector2.INF) -> void:
	# inside (optional): a point inside what the wall encloses. The kit wall's stone face is its local +Z
	# (the other side has the walkway lip); pieces turn so the stone faces AWAY from it (Round 14,
	# Kevin: "the castle walls are backwards" -- the rotation came from the segment's direction, and
	# the red castle's mirrored walls run the other way; the model is centred, so turning doesn't shift it).
	# Lay 5.2 m wall models along a segment (clipped to the field unless told not to), stretched to fit.
	var aa := Vector2(clampf(a.x, -Sim.HALF_W, Sim.HALF_W), clampf(a.y, -Sim.HALF_L, Sim.HALF_L)) if clip else a
	var bb := Vector2(clampf(b.x, -Sim.HALF_W, Sim.HALF_W), clampf(b.y, -Sim.HALF_L, Sim.HALF_L)) if clip else b
	var length := aa.distance_to(bb)
	if length < 0.5:
		return
	var n := maxi(1, int(round(length / Sim.SEG)))
	var piece := length / float(n)
	var rot := -atan2(bb.y - aa.y, bb.x - aa.x)
	if inside != Vector2.INF:
		var d := (bb - aa).normalized()
		var stone := Vector2(-d.y, d.x)                  # where local +Z points with this rotation
		if stone.dot((aa + bb) * 0.5 - inside) < 0.0:
			rot += PI
	for i in n:
		var c := aa.lerp(bb, (float(i) + 0.5) / float(n))
		var node := _place(path, Vector3(c.x, y, c.y), rot, Sim.WALL_SCALE)
		if node != null:
			node.scale.x = Sim.WALL_SCALE * piece / Sim.SEG
			_kit_nodes.append(node)

static var _castle_meshes: Dictionary = {}
static var _castle_mats: Array = []

func _build_castle_mesh(t: int) -> void:
	# Generated parts (castle_mesh.gd): herringbone floors (the map's path texture) and grey stone
	# steps in the KayKit wall colour. Everything else is KayKit models (_build_castle_kit).
	if _castle_mats.is_empty():
		var floor_m: Material
		if _cast_static:
			floor_m = _cloud_floor_material(PATH_TEX, Color(0.86, 0.84, 0.8))
		else:
			var fm := StandardMaterial3D.new()
			fm.albedo_texture = PATH_TEX
			fm.albedo_color = Color(0.86, 0.84, 0.8)
			fm.roughness = 0.95
			fm.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			floor_m = fm
		var step_m := StandardMaterial3D.new()
		step_m.albedo_color = Color("#80858e")         # risers: darker, so each step reads
		step_m.roughness = 0.9
		step_m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		var tread_m := StandardMaterial3D.new()
		tread_m.vertex_color_use_as_albedo = true       # treads: striped bands (castle_mesh.gd)
		tread_m.vertex_color_is_srgb = true             # (read as linear, the dark bands came out pale grey)
		tread_m.roughness = 0.9
		tread_m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		_castle_mats = [floor_m, step_m, tread_m]
	if not _castle_meshes.has(t):
		_castle_meshes[t] = CastleMesh.build(sim, t)
	var parts: Dictionary = _castle_meshes[t]
	for k in ["floor", "steps", "treads"]:
		var mi := MeshInstance3D.new()
		mi.mesh = parts[k]
		mi.material_override = _castle_mats[{"floor":0, "steps":1, "treads":2}[k]]
		mi.cast_shadow = _cast()
		mi.set_meta("perf", "castle")
		add_child(mi)
	_build_castle_kit(t)

func _kit_run(a: Vector2, b: Vector2, y0: float, height: float, depth := 1.1) -> void:
	# KayKit wall_straight pieces along a terrace edge / stair side: stretched to fit the length,
	# scaled so the walkway sits at the terrace height (crenellations stand above as a parapet).
	var length := a.distance_to(b)
	if length < 0.3:
		return
	var seg := 2.0 * 1.9                      # target piece length (m)
	var n := maxi(1, int(round(length / seg)))
	var piece := length / float(n)
	var rot := -atan2(b.y - a.y, b.x - a.x)
	for i in n:
		var c := a.lerp(b, (float(i) + 0.5) / float(n))
		var node := _place(HEX + "wall_straight.gltf", Vector3(c.x, y0, c.y), rot, 1.0)
		if node != null:
			node.scale = Vector3(piece / 2.0, height / 0.85, depth / 0.8)
			_kit_nodes.append(node)

var _kit_nodes: Array = []

func _merge_kit() -> void:
	# All KayKit hex models share one atlas material: bake every static castle piece (walls,
	# terrace walls, towers, buildings, props, banners, trees) into ONE mesh per material instead
	# of ~70 separate draw calls per castle. Animated pieces (gates, catapults) and the hat stands
	# stay separate.
	var tools := {}
	for n in _kit_nodes:
		if n == null or not is_instance_valid(n):
			continue
		for mi in (n as Node).find_children("*", "MeshInstance3D", true, false):
			var m3 := mi as MeshInstance3D
			var xf: Transform3D = global_transform.affine_inverse() * m3.global_transform
			for si in m3.mesh.get_surface_count():
				var mat: Material = m3.get_active_material(si)
				if not tools.has(mat):
					var st := SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					tools[mat] = st
				(tools[mat] as SurfaceTool).append_from(m3.mesh, si, xf)
		(n as Node).queue_free()
	_kit_nodes.clear()
	for mat in tools:
		var mi := MeshInstance3D.new()
		mi.mesh = (tools[mat] as SurfaceTool).commit()
		mi.material_override = mat
		mi.cast_shadow = _cast()
		mi.set_meta("perf", "castle")
		add_child(mi)

func _build_castle_kit(t: int) -> void:
	var col: String = COLOR[t]
	var face := 0.0 if t == 0 else PI
	# Terrace faces and stair sides: KayKit wall pieces, walkway at the level above.
	for seg in Castle.ledges():
		var a: Vector2 = seg[0]
		var c: Vector2 = seg[1]
		var wa: Vector2 = Sim._c(t, a)
		var wc: Vector2 = Sim._c(t, c)
		if absf(a.y - c.y) < 0.01:
			var lo := 0.0 if absf(a.y - Castle.L1_Z) < 0.01 else Castle.L1_H
			var hi := Castle.L1_H if absf(a.y - Castle.L1_Z) < 0.01 else Castle.L2_H
			if absf(a.y - Castle.WALK_Z1) < 0.01:
				lo = 0.0                               # the rampart's front edge (Round 15)
				hi = Castle.WALK_H
			_kit_run(wa, wc, lo, hi - lo)
		else:
			# A stair side runs along z; it stands on the stair's lower level, as tall as the climb.
			var lo2 := 0.0 if a.y < Castle.L2_Z - 0.01 else Castle.L1_H
			var hi2 := Castle.L1_H if a.y < Castle.L2_Z - 0.01 else Castle.L2_H
			_kit_run(wa, wc, lo2, hi2 - lo2, 0.8)
	# The dungeon wing (Round 13): stone sides for the pit under the wing's walls and the castle's
	# west wall, and walls along both sides of the stairs down.
	var ax0: float = Castle.ANNEX_X0
	var az0: float = Castle.ANNEX_Z0
	var az1: float = Castle.ANNEX_Z1
	for seg in [[Vector2(ax0, az0), Vector2(ax0, az1)], [Vector2(ax0, az0), Vector2(-Castle.HX, az0)],
			[Vector2(ax0, az1), Vector2(-Castle.HX, az1)], [Vector2(-Castle.HX, az0), Vector2(-Castle.HX, az1)]]:
		_kit_run(Sim._c(t, seg[0]), Sim._c(t, seg[1]), Castle.DUNGEON_H, -Castle.DUNGEON_H + 0.05, 2.0)
	for seg in Castle.dungeon_ledges():
		_kit_run(Sim._c(t, seg[0]), Sim._c(t, seg[1]), Castle.DUNGEON_H, float(Castle.DSTAIR.h1) - Castle.DUNGEON_H, 0.8)
	# Towers: squat stone towers at the four corners, blue/red-roofed towers either side of the gates.
	for sx in [-Castle.HX, Castle.HX]:
		for sz in [Castle.FRONT_Z, Castle.BACK]:
			var tp: Vector2 = Sim._c(t, Vector2(sx, sz))
			_kit_nodes.append(_place(HEX + "building_tower_base_%s.gltf" % col, Vector3(tp.x, 0, tp.y), face, 3.2))
	for gx in Castle.GATE_X:
		for side in [-1.0, 1.0]:
			var gp: Vector2 = Sim._c(t, Vector2(float(gx) + side * Castle.GATE_PIECE, Castle.FRONT_Z))
			_kit_nodes.append(_place(HEX + "building_tower_A_%s.gltf" % col, Vector3(gp.x, 0, gp.y), face, 2.1))
	# Buildings (solid in the sim too) and props.
	for bd in Castle.BUILDINGS:
		var bp: Vector2 = Sim._c(t, bd.p)
		_kit_nodes.append(_place(HEX + (str(bd.model) % col) + ".gltf", Vector3(bp.x, float(bd.y), bp.y), face + deg_to_rad(float(bd.rot)), float(bd.scale)))
	# Banners on the corner towers, small trees in the courtyard's front corners (clear of the
	# hat stands, workshop and gates).
	for sx in [-Castle.HX, Castle.HX]:
		for sz in [Castle.FRONT_Z, Castle.BACK]:
			var fp: Vector2 = Sim._c(t, Vector2(sx - signf(sx) * 0.4, sz + (0.4 if sz < 10.0 else -0.4)))
			_kit_nodes.append(_place(HEX + "flag_%s.gltf" % col, Vector3(fp.x, 4.6, fp.y), face, 2.6))
	for tq in [Vector2(-10.2, 4.6), Vector2(10.4, 4.6), Vector2(-19.0, 13.0), Vector2(19.0, 13.2)]:
		var tpp: Vector2 = Sim._c(t, tq)
		_kit_nodes.append(_place(HEX + "tree_single_A.gltf", Vector3(tpp.x, 0, tpp.y), randf() * TAU, 2.2))
	for pr in Castle.PROPS:
		var pp: Vector2 = Sim._c(t, pr[1])
		var name: String = str(pr[0]) % col if str(pr[0]).contains("%s") else str(pr[0])
		_kit_nodes.append(_place(HEX + name + ".gltf", Vector3(pp.x, Sim.height_at(pp), pp.y), face + randf() * 0.6 - 0.3, float(pr[2])))

func _build_castle(t: int) -> void:
	var col: String = COLOR[t]
	var face := 0.0 if t == 0 else PI
	# Round 10 castle geometry (castle_mesh.gd): tall crenellated sandstone walls, round towers,
	# gatehouse lintels, terraces with brick faces + parapets, walled grand stairs, paved floors.
	_build_castle_mesh(t)
	# Royal carpet up to the throne.
	_floor(t, -1.3, 1.3, Castle.THRONE.y - 1.6, Castle.BACK - 0.2, Color("#2f5f8a") if t == 0 else Color("#8a3a2f"), Castle.L2_H + 0.02)
	# Walls from the sim (so collision and visuals always agree).
	for w in sim.walls:
		if w.team != t:
			continue
		match str(w.kind):
			"wall":
				# The dungeon wing's walls enclose the wing (and are drawn on their real line: clipped to
				# the field edge the outer one sat 1 m inside and the cage ran into it); the rest the castle.
				var mid: Vector2 = (w.a + w.b) * 0.5
				var ql: Vector2 = (mid if t == 0 else -mid) - Vector2(0.0, Sim.CASTLE_SHIFT)
				var wing: bool = ql.x < -Castle.HX - 0.5
				var inside: Vector2 = Sim._c(t, Vector2(-26.5, 16.0) if wing else Vector2(0.0, 16.0))
				_wall_run(w.a, w.b, HEX + "wall_straight.gltf", 0.0, not wing, inside)
			"backwall":
				_wall_run(w.a, w.b, HEX + "wall_straight.gltf", Castle.L2_H, false, Sim._c(t, Vector2(0.0, 16.0)))
			"bars":
				_bars(w.a, w.b)
			# "ledge" (terrace faces, stair sides) are KayKit wall runs in _build_castle_kit.
	# Gates on the front wall; open archways in the inner wall.
	for g in sim.gates:
		if g.team != t:
			continue
		if str(g.get("kind", "")) == "jail":
			# The jail door: an iron grille that slides up into the ceiling when the castle's own
			# players come near (g.open), gone when the enemy smashes it.
			var door := _iron_bars(g.a, g.b, 2.3)
			door.position = Vector3(g.c.x, Sim.height_at(g.c), g.c.y)
			add_child(door)
			gate_nodes[g.id] = {"jail": true, "door": door, "y0": door.position.y, "open": 0.0, "broken": false}
			continue
		# Stone face (local +Z) outwards, like the walls: face alone pointed it into the castle.
		var node := _place(HEX + "wall_straight_gate.gltf", Vector3(g.c.x, 0, g.c.y), face + PI, Sim.WALL_SCALE)
		var doors := []
		for mi in node.find_children("*door*", "MeshInstance3D", true, false):
			doors.append({"node":mi, "sign":1.0 if str(mi.name).contains("left") else -1.0})
		var rubble := Node3D.new()
		rubble.position = Vector3(g.c.x, 0, g.c.y)
		add_child(rubble)
		for i in 3:
			var r := _place(HEX + ["rock_single_D.gltf", "rock_single_E.gltf", "crate_open.gltf"][i],
				Vector3(g.c.x + (i - 1) * 0.9, 0, g.c.y + randf_range(-0.3, 0.3)), randf() * TAU, [3.0, 3.0, 1.6][i])
			if r != null:
				r.reparent(rubble, true)
		rubble.visible = false
		gate_nodes[g.id] = {"doors":doors, "rubble":rubble, "open":0.0, "broken":false}
	# Towers flank both gates; catapult towers on the front corners; the keep at the back.
	for cx in [-Sim.CATAPULT_X, Sim.CATAPULT_X]:
		var cp: Vector2 = Sim._c(t, Vector2(cx, Sim.FRONT_Z + 0.3))
		var cat := _place(HEX + "building_tower_catapult_%s.gltf" % col, Vector3(cp.x, 0, cp.y), face, 2.2)
		if cat != null:
			var turret: Node3D = cat.find_child("*turret*", true, false)
			var arm: Node3D = cat.find_child("*arm*", true, false)
			catapult_nodes.append({"team":t, "p":cp, "node":cat, "turret":turret, "arm":arm,
				"arm_rest":arm.rotation.x if arm != null else 0.0, "fired":-10.0})
	# The throne (Round 14, Kevin's ask; the keep that stood here blocked it): a Blender model against
	# the back wall, velvet in the castle's colour, facing the courtyard.
	var tp: Vector2 = Sim._c(t, Castle.THRONE_SEAT)
	var throne := _place("res://assets/props/throne.glb", Vector3(tp.x, Castle.L2_H, tp.y), PI if t == 0 else 0.0, 1.0)
	if throne != null:
		var velvet := StandardMaterial3D.new()
		velvet.albedo_color = Color("#2d58b8") if t == 0 else Color("#b3223a")
		velvet.roughness = 0.85
		for mi in throne.find_children("*", "MeshInstance3D", true, false):
			var m: MeshInstance3D = mi
			for si in m.mesh.get_surface_count():
				var sm := m.mesh.surface_get_material(si)
				if sm != null and str(sm.resource_name) == "Velvet":
					m.set_surface_override_material(si, velvet)
	# Throne room: banners either side of the throne, a weapon rack.
	var th: Vector2 = Sim.throne(t)
	for fx in [-1.6, 1.6]:
		var fp: Vector2 = th + Sim._c(t, Vector2(fx, 1.2))
		_place(HEX + "flag_%s.gltf" % col, Vector3(fp.x, Castle.L2_H, fp.y), face, 1.6)
	_decal(Vector3(th.x, Castle.L2_H + 0.06, th.y), Sim.THRONE_RADIUS, TEAM_COLORS[t], 0.6)
	var wr: Vector2 = Sim._c(t, Vector2(12.0, 26.0))
	_place(HEX + "weaponrack.gltf", Vector3(wr.x, Castle.L2_H, wr.y), face + PI * 0.5, 4.0)
	# Dungeon: the cell on the platform, a ladder against the back wall and barrels.
	var cc: Vector2 = Sim._c(t, Sim.CELL_C)
	# 0.31.11: on the cell's floor. (It was at the level-1 height from when the cell stood on the platform; since the cell
	# moved into the sunken dungeon that put it 3.5 m up, floating over the King's head.)
	_decal(Vector3(cc.x, Sim.height_at(cc) + 0.06, cc.y), 1.4, GOLD, 0.35)
	for bx in [Vector2(-19.0, 21.2), Vector2(-12.0, 21.2)]:
		var b2: Vector2 = Sim._c(t, bx)
		_place(HEX + "barrel.gltf", Vector3(b2.x, Castle.L1_H, b2.y), randf() * TAU, 2.2)
	# Courtyard: hat stands, workshop ring + stockpiles (piles scale with the team's stock).
	var ws: Vector2 = Sim.workshop(t)
	_decal(Vector3(ws.x, 0.06, ws.y), Sim.WORKSHOP_RADIUS, Color("#9fe07a"), 0.45)
	var piles := {}
	for kind in ["wood", "stone"]:
		var pp: Vector2 = Sim._c(t, Vector2(15.5, 12.4 if kind == "wood" else 5.6))
		var pile := Node3D.new()
		pile.position = Vector3(pp.x, 0, pp.y)
		add_child(pile)
		for i in 6:
			var at := Vector3(pp.x + (i % 3 - 1) * 0.75, 0.3 * float(i / 3), pp.y + randf_range(-0.2, 0.2))
			var piece: Node3D = _place(HEX + "resource_lumber.gltf", at, randf_range(-0.3, 0.3), 2.2) if kind == "wood" \
				else _mesh_node(boulder_mesh(60 + i, 0.34, 1), at + Vector3(0, 0.2, 0), randf() * TAU)
			if piece != null:
				piece.reparent(pile, true)
				piece.visible = false
		piles[kind] = pile
	var wb: Vector2 = Sim._c(t, Vector2(11.0, 12.6))
	_place(HEX + "wheelbarrow.gltf", Vector3(wb.x, 0, wb.y), face + 0.8, 3.0)
	stock_piles.append(piles)

func _bars(a: Vector2, b: Vector2) -> void:
	# Cell bars (Round 13, Kevin: "actual jail bars"): an iron grille on the dungeon floor.
	var n := _iron_bars(a, b, 2.3)
	var mid := (a + b) * 0.5
	n.position = Vector3(mid.x, Sim.height_at(mid), mid.y)
	add_child(n)

static var _iron_mat: StandardMaterial3D = null

func _iron_bars(a: Vector2, b: Vector2, height: float) -> Node3D:
	# Vertical iron bars every 0.2 m between a top and a bottom rail, centred on (a+b)/2.
	if _iron_mat == null:
		_iron_mat = StandardMaterial3D.new()
		_iron_mat.albedo_color = Color("#3b3f47")
		_iron_mat.metallic = 0.65
		_iron_mat.roughness = 0.42
	var length := a.distance_to(b)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := length * 0.5
	var n := maxi(2, int(length / 0.2))
	for i in n + 1:
		var x := -half + length * float(i) / n
		_bar_box(st, Vector3(x, height * 0.5, 0), Vector3(0.045, height * 0.5, 0.045))
	for y in [0.18, height - 0.12]:
		_bar_box(st, Vector3(0, y, 0), Vector3(half, 0.05, 0.06))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _iron_mat
	mi.cast_shadow = _cast()
	var root := Node3D.new()
	root.rotation.y = -atan2(b.y - a.y, b.x - a.x)
	root.add_child(mi)
	return root

static func _bar_box(st: SurfaceTool, c: Vector3, h: Vector3) -> void:
	var v := []
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			for sz in [-1, 1]:
				v.append(c + Vector3(h.x * sx, h.y * sy, h.z * sz))
	for f in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		for k in [0, 2, 1, 0, 3, 2]:
			st.add_vertex(v[f[k]])

func _build_nodes() -> void:
	# Trees and quarry stones the workers harvest; a depleted node shows a stump / bare rock.
	for n in sim.nodes:
		var p := Vector3(n.p.x, 0, n.p.y)
		var full: Node3D
		var empty: Node3D
		if n.kind == "wood":
			full = _place(HEX + ("tree_single_A.gltf" if n.id % 2 == 0 else "tree_single_B.gltf"), p, randf() * TAU, 3.2)
			empty = _place(HEX + ("tree_single_A_cut.gltf" if n.id % 2 == 0 else "tree_single_B_cut.gltf"), p, randf() * TAU, 3.2)
		else:
			# 0.31.0 (Kevin: "iron nodes ... shape of boulders"): a low-poly boulder; rubble once it's broken.
			full = _mesh_node(boulder_mesh(n.id, 1.25, 2), p + Vector3(0, -0.28, 0), randf() * TAU)
			empty = Node3D.new()
			empty.position = p
			add_child(empty)
			for k in 3:
				var bit := _mesh_node(boulder_mesh(n.id * 7 + k, 0.38, 1), Vector3(cos(k * 2.1) * 0.55, -0.08, sin(k * 2.1) * 0.55), randf() * TAU)
				bit.reparent(empty, false)
		if empty != null:
			empty.visible = false
		node_nodes[n.id] = {"full":full, "empty":empty, "state":true}

func _sync_castle(dt: float) -> void:
	_sync_outposts()
	_sync_hats()
	_sync_beams()
	_sync_shields()
	_sync_whirls()
	for g in sim.gates:
		var gn: Dictionary = gate_nodes.get(g.id, {})
		if gn.is_empty():
			continue
		var broken: bool = not sim.gate_blocks(g)
		if gn.has("jail"):
			gn.broken = broken
			(gn.door as Node3D).visible = not broken
			gn.open = move_toward(float(gn.open), 1.0 if (g.open and not broken) else 0.0, dt * 2.2)
			(gn.door as Node3D).position.y = float(gn.y0) - float(gn.open) * 2.35      # sinks into the floor (0.31.10, Kevin)
			continue
		if broken != bool(gn.broken):
			gn.broken = broken
			(gn.rubble as Node3D).visible = broken
			for d in gn.doors:
				(d.node as Node3D).visible = not broken
		var want := 1.0 if (g.open and not broken) else 0.0
		gn.open = move_toward(float(gn.open), want, dt * 2.5)
		for d in gn.doors:
			(d.node as Node3D).rotation.y = float(d.sign) * float(gn.open) * PI * 0.5
	for n in sim.nodes:
		var nn: Dictionary = node_nodes.get(n.id, {})
		if nn.is_empty():
			continue
		var has: bool = n.amount > 0
		if has != bool(nn.state):
			nn.state = has
			if nn.full != null:
				(nn.full as Node3D).visible = has
			if nn.empty != null:
				(nn.empty as Node3D).visible = not has
		if has and nn.full != null:
			var k := 0.75 + 0.25 * float(n.amount) / float(n.max)
			(nn.full as Node3D).scale = Vector3.ONE * (3.2 if n.kind == "wood" else 1.0) * k
	for cn in catapult_nodes:
		if cn.arm == null:
			continue
		var age: float = _time - float(cn.fired)
		# Throw: snap forward in 0.15 s, wind back over 0.9 s.
		var swing := 0.0
		if age < 0.15:
			swing = age / 0.15
		elif age < 1.05:
			swing = 1.0 - (age - 0.15) / 0.9
		(cn.arm as Node3D).rotation.x = float(cn.arm_rest) + swing * 1.4
	for t in 2:
		var o_node: Dictionary = oracle_nodes[t] if t < oracle_nodes.size() else {}
		if not o_node.is_empty() and o_node.body != null:
			var w := int(sim.oracles[t].get("weight", 0))
			var stage := clampi(w / 2, 0, KING_STAGES.size() - 1)
			if stage != int(o_node.stage):
				for k in (o_node.stages as Array).size():
					(o_node.stages[k] as Node3D).visible = k == stage
				o_node.puff = 1.0 if stage > int(o_node.stage) else 0.0    # he just got fatter
				o_node.stage = stage
			o_node.puff = maxf(0.0, float(o_node.puff) - dt * 2.5)
			var body: Node3D = o_node.body
			var bump := 1.0 + 0.05 * float(w % 2)                         # the odd weights show too
			var breathe := 1.0 + 0.018 * sin(_time * 2.4 + t)
			var puff := 1.0 + 0.18 * sin(float(o_node.puff) * PI)
			body.scale = Vector3(bump * puff * (2.0 - breathe), bump * breathe, bump * puff * (2.0 - breathe))
			if str(sim.oracles[t].state) == "carried":
				body.rotation = Vector3(0.12 * sin(_time * 5.2), 0.0, 0.16 * sin(_time * 4.1 + 0.7))
			else:
				body.rotation = Vector3(0.0, 0.08 * sin(_time * 0.9 + t * 2.0), 0.035 * sin(_time * 1.3 + t))
		for kind in ["wood", "stone"]:
			var pile: Node3D = stock_piles[t][kind]
			var shown := clampi(int(ceil(float(sim.stock[t][kind]) / 5.0)), 0, pile.get_child_count())
			for i in pile.get_child_count():
				(pile.get_child(i) as Node3D).visible = i < shown

func _unshaded(color: Color, additive := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	return m

func _ring_mesh(radius: float, width := 0.14) -> TorusMesh:
	var key := "%.2f:%.2f" % [radius, width]
	if _rings.has(key):
		return _rings[key]
	var tm := TorusMesh.new()
	tm.inner_radius = radius - width
	tm.outer_radius = radius
	tm.rings = 32
	tm.ring_segments = 4
	_rings[key] = tm
	return tm

func _decal(pos: Vector3, radius: float, color: Color, alpha: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh(radius, 0.18)
	mi.scale = Vector3(1, 0.15, 1)
	var c := color
	c.a = alpha
	mi.material_override = _unshaded(c)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	add_child(mi)
	return mi

# ---------- actors ----------
# Equipped cosmetics for the local player, per class: {"tint": "#rrggbb", "r": model, "l": model}.
# Set by the mode from the profile. Only the local player's unit uses them.
var player_looks: Dictionary = {}
static var _tint_mats: Dictionary = {}

static func look_key(u: Dictionary) -> String:
	if u.cls == "barbarian" and u.up:
		return "berserker"
	if u.cls == "priest" and u.up:
		return "necromancer"
	return u.cls

static func make_body(cls: String, cosmetic: Dictionary = {}) -> Dictionary:
	var look: Dictionary = (LOOKS.get(cls, LOOKS.villager) as Dictionary).duplicate()
	for hand in ["r", "l"]:
		if cosmetic.has(hand):
			look[hand] = cosmetic[hand]
	var packed := Stage.scene("res://assets/kaykit/heroes/%s.glb" % look.model)
	if packed == null:
		return {}
	var body: Node3D = packed.instantiate()
	var skeleton: Skeleton3D = body.find_child("Skeleton3D", true, false)
	if skeleton != null:
		for hand in ["r","l"]:
			var file := str(look.get(hand, ""))
			if file.is_empty():
				continue
			var slot := BoneAttachment3D.new()
			slot.bone_name = "handslot.%s" % hand
			skeleton.add_child(slot)
			# "bits/<name>" = KayKit Fantasy Weapons Bits (Round 11): larger models, scaled down.
			var bits := file.begins_with("bits/")
			var weapon := Stage.scene(("res://assets/kaykit/bits/%s.gltf" % file.substr(5)) if bits else ("res://assets/kaykit/weapons/%s.gltf" % file))
			if weapon != null:
				var model: Node3D = weapon.instantiate()
				if bits:
					# Shields bigger so it's obvious a knight carries one (Round 12, Kevin).
					model.scale = Vector3.ONE * (0.9 if file.contains("shield") else 0.55)
				if file.contains("bow"):
					model.rotation.y = PI
				slot.add_child(model)
	var player := AnimationPlayer.new()
	body.add_child(player)
	player.root_node = NodePath("..")
	for key in libraries():
		player.add_animation_library(key, _libs[key])
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _cast_static else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	if not cosmetic.has("tint") and look.has("tint"):
		cosmetic = cosmetic.duplicate()
		cosmetic["tint"] = look.tint
	if cosmetic.has("tint"):
		_apply_tint(body, str(look.model), Color(str(cosmetic.tint)))
	return {"body":body, "player":player}

static func _apply_tint(body: Node3D, model: String, tint: Color) -> void:
	# A skin = the model's own material with its albedo multiplied by the tint. Made once per
	# (model, surface, tint) and cached; set once when the body is built, never per frame.
	var skel: Skeleton3D = body.find_child("Skeleton3D", true, false)
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		if skel != null and not skel.is_ancestor_of(m3):
			continue
		var under_hand := false
		var n: Node = m3.get_parent()
		while n != null and n != body:
			if n is BoneAttachment3D:
				under_hand = true
				break
			n = n.get_parent()
		if under_hand:
			continue                       # weapons keep their own colours
		for surf in m3.mesh.get_surface_count():
			var base := m3.get_active_material(surf)
			if not (base is StandardMaterial3D):
				continue
			var key := "%s|%s|%d|%s" % [model, m3.name, surf, tint.to_html()]
			if not _tint_mats.has(key):
				var m2: StandardMaterial3D = (base as StandardMaterial3D).duplicate()
				m2.albedo_color = (base as StandardMaterial3D).albedo_color * tint
				_tint_mats[key] = m2
			m3.set_surface_override_material(surf, _tint_mats[key])

func _ensure_actor(u: Dictionary) -> Dictionary:
	var a: Dictionary = actors.get(u.id, {})
	var cosmetic: Dictionary = player_looks.get(u.cls, {}) if u.id == player_id else {}
	var look_key := "%s:%s:%s" % [u.cls, u.up, str(cosmetic)]
	if not a.is_empty() and a.look == look_key:
		return a
	var root: Node3D
	if a.is_empty():
		root = Node3D.new()
		add_child(root)
		root.position = Vector3(u.pos.x, 0, u.pos.y)
		var ring := MeshInstance3D.new()
		ring.mesh = _ring_mesh(0.62 if u.id == player_id else 0.5, 0.12)
		ring.scale = Vector3(1, 0.2, 1)
		var col: Color = GOLD if u.id == player_id else TEAM_COLORS[u.team]
		col.a = 0.9
		ring.material_override = _unshaded(col)
		ring.position.y = 0.05
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ring)
		# HP bars are drawn by the 2D HUD (as in the dice battle); no blob-shadow shader quads.
		a = {"root":root, "ring":ring, "body":null, "player":null, "clip":"", "busy_until":0.0, "dead":false, "last":root.position,
			"team":u.team}
		actors[u.id] = a
	else:
		root = a.root
		if is_instance_valid(a.body):
			a.body.queue_free()
	var made := make_body(look_key(u), cosmetic)
	if made.is_empty():
		return a
	root.add_child(made.body)
	made.body.scale = Vector3.ONE * (1.14 if u.up else 1.0)
	a.body = made.body
	a.player = made.player
	_cape_setup(a)
	a.look = look_key
	a.cls = u.cls
	a.clip = ""
	a.busy_until = 0.0
	_play(a, str(LOOKS.get(u.cls, LOOKS.villager).idle))
	# Upgraded: bigger body + gold ring (no material overrides on skinned meshes).
	var rc: Color = GOLD if (u.up or u.id == player_id) else TEAM_COLORS[u.team]
	rc.a = 0.9
	(a.ring as MeshInstance3D).material_override = _fx_mat(rc)
	(a.ring as MeshInstance3D).mesh = _ring_mesh(0.75 if u.up else (0.62 if u.id == player_id else 0.5), 0.14 if u.up else 0.12)
	return a

func _play(a: Dictionary, clip: String, speed := 1.0, busy := 0.0) -> void:
	var player: AnimationPlayer = a.player
	if not is_instance_valid(player):
		return
	if not player.has_animation(clip):
		clip = "g/Idle_A"
	if busy > 0.0:
		a.busy_until = _time + busy
	if a.clip == clip and player.is_playing() and busy <= 0.0:
		player.speed_scale = speed
		return
	a.clip = clip
	player.play(clip, 0.1)
	player.speed_scale = speed

# Animation culling (0.14.3): characters outside the camera view don't run their AnimationPlayer
# (so no skeleton update or skinning upload either); they resume the moment they come into view.
var anim_cull := true
var anim_active := 0

func _on_screen(p: Vector3, planes: Array) -> bool:
	# Bounding sphere (1.8 m) against the camera frustum planes.
	var c := p + Vector3(0, 1.0, 0)
	for pl in planes:
		if (pl as Plane).distance_to(c) > 1.8:
			return false
	return true

func sync(dt: float) -> void:
	_time += dt
	_sync_items(dt)
	_sync_raising()
	_sync_ambience(dt)
	_sync_ripples(dt)
	_sync_blood(dt)
	var seen := {}
	var planes: Array = camera.get_frustum() if anim_cull and is_instance_valid(camera) and camera.is_inside_tree() else []
	anim_active = 0
	for u in sim.units:
		seen[u.id] = true
		var a := _ensure_actor(u)
		if a.is_empty() or not is_instance_valid(a.root):
			continue
		var root: Node3D = a.root
		var tw := int(u.get("tower", -1))
		var gy := Sim.height_at(u.pos) if tw < 0 or tw >= sim.outposts.size() else Sim.height_at(sim.outposts[tw].p) + Land.TOWER_FLOOR
		# On a ladder: up the rungs, over the wall, down the far side (Round 25).
		var climb_d: float = sim.ladder_depth(u.pos, u.team) if not sim.ladders.is_empty() and u.state != "dead" else INF
		a.climb = climb_d != INF and Sim.ladder_lift(climb_d, gy) > gy + 0.15
		var target := Vector3(u.pos.x, Sim.ladder_lift(climb_d, gy) if climb_d != INF else gy, u.pos.y)
		var before := root.position
		# Smooth between 30 Hz sim ticks; snap on respawn teleports.
		if before.distance_to(target) > 6.0:
			root.position = target
		else:
			root.position = before.lerp(target, 1.0 - exp(-dt * 22.0))
		var vel := (root.position - before).length() / maxf(dt, 0.001)
		if sim.whirling(u) and u.state != "dead":
			# 0.31.16 (Kevin: "the barbarian model should spin with the vfx"): he turns with his whirlwind -- the same way
			# round as its ribbons and nearly as fast (they turn at 44 and 34 rad/s; he at 38).
			a["whirl_spin"] = float(a.get("whirl_spin", 0.0)) + dt * 38.0
			root.rotation.y = float(u.face) - float(a.whirl_spin)
		else:
			a["whirl_spin"] = 0.0
			root.rotation.y = lerp_angle(root.rotation.y, float(u.face), 1.0 - exp(-dt * 18.0))
		(a.ring as MeshInstance3D).visible = u.state != "dead"
		_sync_load(a, u)
		_sync_hand(a, u)
		_animate(a, u, vel)
		if a.get("cape") != null:
			_cape_step(a, dt)
		if is_instance_valid(a.player):
			var show := planes.is_empty() or _on_screen(root.position, planes)
			if (a.player as AnimationPlayer).active != show:
				(a.player as AnimationPlayer).active = show
			if show:
				anim_active += 1
	for id in actors.keys():
		if not seen.has(id):
			actors[id].root.queue_free()
			actors.erase(id)
	_sync_oracles(dt)
	_sync_castle(dt)
	_sync_projectiles()
	_step_fx()
	_update_camera(dt)

# ---------- hand tools (Round 19, KayKit RPG Tools Bits) ----------
const TOOLS := "res://assets/kaykit/tools/"
# Scaled to working size (measured: axe 1.05, pickaxe 1.45, hammer 0.82, rod 4.75 units; the old worker
# axe was 1.24): axe ~1.2 m, pickaxe ~1.3, hammer ~1.0, rod ~2.85.
const TOOL_SCALES := {"axe": 1.15, "pickaxe": 0.9, "hammer": 1.2, "fishing_rod": 0.6}
# The rod is the bare one (fishing_rod_base: fishing_rod has its own line and bobber dangling from the
# grip); our line runs from its tip -- measured: the highest vertex, the rod bends toward +Z.
const ROD_MODEL := "fishing_rod_base"
const ROD_TIP := Vector3(-0.0067, 2.3678, 0.9882)
static var _line_mat: StandardMaterial3D = null

func _gather_kind(u: Dictionary) -> String:
	if u.load.n > 0:
		return str(u.load.kind)
	var best := "wood"
	var bd := 3.2
	for n in sim.nodes:
		var d: float = u.pos.distance_to(n.p)
		if d < bd:
			bd = d
			best = str(n.kind)
	return best

func _sync_hand(a: Dictionary, u: Dictionary) -> void:
	# What's in the right hand: a fishing rod while fishing (anyone); for workers the tool for the job --
	# pickaxe on stone, axe on trees, hammer for repairs and ladders, the axe otherwise. Otherwise the
	# class weapon. Plus, while fishing, a float bobbing in the water and a line to it.
	var want := ""
	var fishing: bool = u.state == "fish"
	if fishing:
		want = "fishing_rod"
	elif u.cls == "worker" and u.state != "dead":
		match str(u.state):
			"gather":
				want = "pickaxe" if _gather_kind(u) == "stone" else "axe"
			"repair", "build_ladder":
				want = "hammer"
			_:
				want = "axe"
	if fishing and not a.has("fish_from"):
		a.fish_from = sim.time
	elif not fishing:
		a.erase("fish_from")
	_sync_fishing_gear(a, u, fishing)
	if want == str(a.get("hand_tool", "")):
		return
	a.hand_tool = want
	if not a.has("hand_slot") or not is_instance_valid(a.hand_slot):
		var sk: Skeleton3D = (a.body as Node3D).find_child("Skeleton3D", true, false) if a.get("body") != null else null
		if sk == null:
			return
		var slot: BoneAttachment3D = null
		for c in sk.get_children():
			if c is BoneAttachment3D and str((c as BoneAttachment3D).bone_name) == "handslot.r":
				slot = c
		if slot == null:
			slot = BoneAttachment3D.new()
			slot.bone_name = "handslot.r"
			sk.add_child(slot)
		a.hand_slot = slot
		a.hand_default = slot.get_children()
		a.tools = {}
	var slot2: BoneAttachment3D = a.hand_slot
	for c in a.hand_default:
		if is_instance_valid(c):
			(c as Node3D).visible = want == ""
	for k in a.tools:
		if is_instance_valid(a.tools[k]):
			(a.tools[k] as Node3D).visible = k == want
	if want != "" and not (a.tools as Dictionary).has(want):
		var packed := Stage.scene(TOOLS + (ROD_MODEL if want == "fishing_rod" else want) + ".gltf")
		if packed != null:
			var m: Node3D = packed.instantiate()
			m.scale = Vector3.ONE * float(TOOL_SCALES.get(want, 1.0))
			if want == "axe":
				m.rotation.y = PI          # edge down (Kevin: "the axe is held upside down" -- edge was up)
			elif want == "fishing_rod":
				m.rotation.x = PI          # the fishing animation's hand points it backward otherwise
			slot2.add_child(m)
			a.tools[want] = m

func _sync_fishing_gear(a: Dictionary, u: Dictionary, fishing: bool) -> void:
	if not fishing:
		for k in ["float_node", "line_node"]:
			if a.has(k) and is_instance_valid(a[k]):
				(a[k] as Node3D).visible = false
		return
	if not a.has("float_node") or not is_instance_valid(a.float_node):
		var fp := Stage.scene(TOOLS + "fishing_floater.gltf")
		a.float_node = fp.instantiate() if fp != null else Node3D.new()
		(a.float_node as Node3D).scale = Vector3.ONE * 1.4
		add_child(a.float_node)
		if _line_mat == null:
			_line_mat = StandardMaterial3D.new()
			_line_mat.albedo_color = Color(0.92, 0.92, 0.88, 0.85)
			_line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var cm := CylinderMesh.new()
		cm.top_radius = 0.012
		cm.bottom_radius = 0.012
		cm.height = 1.0
		cm.radial_segments = 4
		cm.rings = 1
		var line := MeshInstance3D.new()
		line.mesh = cm
		line.material_override = _line_mat
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(line)
		a.line_node = line
	var dir := Sim.dir_of(u.face)
	var reach: float = absf(u.pos.y - Land.river_c(u.pos.x)) - Land.river_hw(u.pos.x) + 1.1
	var wp: Vector2 = u.pos + dir * reach
	var bob := sin(float(sim.time) * 3.4 + float(u.pos.x)) * 0.04
	var fl: Node3D = a.float_node
	fl.visible = true
	fl.position = Vector3(wp.x, Land.WATER_Y + 0.06 + bob, wp.y)
	# The line starts at the rod's own tip, wherever the animation has it (Kevin: "the fishing pole
	# doesn't have string attached"); fall back to above the hands if the rod isn't there yet.
	var root_p: Vector3 = (a.root as Node3D).position
	var tip := root_p + Vector3(dir.x * 1.0, 2.5, dir.y * 1.0)
	# (Untyped first: the body -- and the cached rod -- can have been rebuilt and freed on a class change.)
	var rod_v = (a.get("tools", {}) as Dictionary).get("fishing_rod")
	if rod_v != null and is_instance_valid(rod_v) and (rod_v as Node3D).is_inside_tree():
		tip = (rod_v as Node3D).global_transform * ROD_TIP
	var line2: MeshInstance3D = a.line_node
	line2.visible = true
	var span := fl.position - tip
	line2.position = tip + span * 0.5
	line2.scale = Vector3(1.0, maxf(0.05, span.length()), 1.0)
	if span.length() > 0.01:
		line2.basis = Basis(Quaternion(Vector3.UP, span.normalized())) * Basis.from_scale(Vector3(1.0, span.length(), 1.0))

func _sync_load(a: Dictionary, u: Dictionary) -> void:
	var kind: String = u.load.kind if u.load.n > 0 and u.state != "dead" else ""
	if u.offering and u.state != "dead":
		kind = "offering"
	if kind == str(a.get("load_kind", "")):
		return
	a.load_kind = kind
	if a.has("load_node") and is_instance_valid(a.load_node):
		a.load_node.queue_free()
	if kind == "":
		return
	var n: Node3D
	if kind == "offering":
		# A fish held overhead (Round 19: the catch from the river; was a cake).
		var fp := Stage.scene("res://assets/props/fish.glb")
		n = fp.instantiate() if fp != null else Node3D.new()
		n.scale = Vector3.ONE * 0.85
		n.rotation = Vector3(0.0, PI * 0.5, 0.25)
		n.position = Vector3(0, 2.45, 0)
		(a.root as Node3D).add_child(n)
		a.load_node = n
		return
	if kind == "stone":
		n = Node3D.new()                                         # rocks carried overhead (0.31.0: boulders, not ingots)
		for k in 2:
			var bit := _mesh_node(boulder_mesh(40 + k, 0.3, 1), Vector3((k - 0.5) * 0.4, 0.0, 0.0), k * 1.7)
			bit.reparent(n, false)
		n.position = Vector3(0, 2.35, 0)
		(a.root as Node3D).add_child(n)
		a.load_node = n
		return
	var packed := Stage.scene(HEX + {"wood":"resource_lumber.gltf", "stone":"resource_stone.gltf"}[kind])
	if packed == null:
		return
	n = packed.instantiate()
	n.scale = Vector3.ONE * 2.2
	n.position = Vector3(0, 2.35, 0)
	(a.root as Node3D).add_child(n)
	a.load_node = n

func _animate(a: Dictionary, u: Dictionary, vel: float) -> void:
	var look: Dictionary = LOOKS.get(u.cls, LOOKS.villager)
	if u.state == "dead":
		if not a.dead:
			a.dead = true
			_play(a, "g/Death_A", 1.0, 99.0)
		return
	if a.dead:
		a.dead = false
		a.busy_until = 0.0
	if _time < float(a.busy_until):
		return
	if u.stun > 0.0:
		_play(a, "g/Hit_B", 0.6)
	elif bool(a.get("climb", false)):
		_play(a, "mb/Jump_Idle")                 # arms up on the rungs / over the top (Round 25)
	elif u.state == "dodge":
		_play(a, "ma/Dodge_Forward", 1.6, 0.3)
	elif sim.whirling(u):
		_play(a, "m/Melee_2H_Attack_Spinning", 1.8)
	elif sim.blocking(u):
		_play(a, "m/Melee_Blocking")
	elif str(u.get("beam", "")) != "":
		_play(a, "r/Ranged_Magic_Spellcasting_Long")
	elif u.state == "gather":
		var node: Dictionary = sim.nodes[int(u.task.get("node", 0))] if not u.task.is_empty() else {}
		_play(a, "t/Chopping" if node.get("kind", "wood") == "wood" else "t/Pickaxing")
	elif u.state == "repair":
		_play(a, "t/Hammering")
	elif u.state == "fish":
		# Cast, wait, reel in (Round 19; the KayKit tools rig has a fishing set).
		var ft := float(sim.time) - float(a.get("fish_from", sim.time))
		_play(a, "t/Fishing_Cast" if ft < 0.7 else ("t/Fishing_Reeling" if ft > Sim.FISH_TIME - 0.7 else "t/Fishing_Idle"))
	elif u.carrying:
		_play(a, "mb/Walking_A" if vel > 0.5 else "t/Holding_A", clampf(vel / 2.6, 0.7, 1.6))
	elif vel > 0.6:
		_play(a, "mb/Running_A", clampf(vel / 5.2, 0.7, 1.4))
	else:
		_play(a, str(look.idle))

func on_event(e: Dictionary) -> void:
	var a: Dictionary = actors.get(str(e.get("id", "")), {})
	match str(e.k):
		"attack":
			if a.is_empty():
				return
			var look: Dictionary = LOOKS.get(a.cls, LOOKS.villager)
			var clip := str(look.ability if e.kind == "ability" else look.attack)
			_play(a, clip, 1.7, 0.55)
			if e.ability == "spin":
				ring_at(a.root.position, Color("#ffcf7a"), 2.8, 0.45)
		"hit":
			if a.is_empty():
				return
			spark(a.root.position + Vector3(0, 1.3, 0), Color("#ffd27a"))
			var hu: Dictionary = sim.by_id.get(str(e.id), {})
			if not hu.is_empty():
				var src: Dictionary = sim.by_id.get(str(e.get("by", "")), {})
				blood_hit(hu.pos, src.pos if not src.is_empty() else (hu.pos as Vector2) - Vector2.from_angle(float(hu.face)), float(e.get("dmg", 20)))
			number(a.root.position + Vector3(0, 2.2, 0), str(e.dmg), e.id == player_id)
			if _time >= float(a.busy_until):
				_play(a, "g/Hit_A", 1.4, 0.3)
		"death":
			var du: Dictionary = sim.by_id.get(str(e.get("id", "")), {})
			if not du.is_empty():
				blood_pool(du.pos)
		"spawn":
			if not a.is_empty():
				a.root.position = Vector3(sim.by_id[e.id].pos.x, 0, sim.by_id[e.id].pos.y)
				ring_at(a.root.position, TEAM_COLORS[sim.by_id[e.id].team], 1.6, 0.6)
		"class":
			if not a.is_empty():
				ring_at(a.root.position, GOLD, 3.0 if e.up else 2.0, 0.8)
				for i in (10 if e.up else 5):
					spark(a.root.position + Vector3(randf_range(-0.6, 0.6), 0.4 + randf()*1.4, randf_range(-0.6, 0.6)), GOLD)
		"nova":
			if not a.is_empty():
				ring_at(a.root.position, Color("#ff8a3a"), Sim.NOVA_R, 0.55)
		"resurrect":                                          # 0.31.1: a High Priest brings someone back
			var rp := Vector3(e.pos.x, Sim.height_at(e.pos) + 0.1, e.pos.y)
			ring_at(rp, Color("#fff1a8"), 1.6, 0.9)
			for i in 14:
				spark(rp + Vector3(randf_range(-0.5, 0.5), randf() * 2.4, randf_range(-0.5, 0.5)), Color("#fff1a8"))
		"sanctuary":
			if not a.is_empty():
				ring_at(a.root.position, Color("#fff1a8"), Sim.SANCTUARY_R, 0.7)
		"boom":
			ring_at(Vector3(e.pos.x, Sim.height_at(Vector2(e.pos.x, e.pos.y)) + 0.2, e.pos.y), Color("#ff8a3a"), 1.6, 0.4)
			spark(Vector3(e.pos.x, 0.6, e.pos.y), Color("#ffb04a"))
		"rescue":
			var th: Vector2 = Sim.throne(int(e.team))
			for i in 3:
				ring_at(Vector3(th.x, Sim.height_at(Vector2(th.x, th.y)) + 0.1, th.y), GOLD, 2.0 + i * 1.5, 0.8 + i * 0.25)
		"gate_hit":
			var g: Dictionary = sim.gates[int(e.gate)]
			var gp: Vector2 = g.c + (Vector2(randf_range(-1.0, 1.0), 0.0))
			var gy := Sim.height_at(g.c)
			spark(Vector3(gp.x, gy + 1.4 + randf() * 1.2, gp.y), Color("#e8d6b0"))
			if randf() < 0.35:
				number(Vector3(g.c.x, gy + 3.2, g.c.y), str(e.dmg), false)
		"gate_broken":
			var g2: Dictionary = sim.gates[int(e.gate)]
			var gy2 := Sim.height_at(g2.c)
			for i in 3:
				ring_at(Vector3(g2.c.x, gy2 + 0.2, g2.c.y), Color("#e0c9a0"), 2.5 + i, 0.7 + i * 0.2)
			for i in 12:
				spark(Vector3(g2.c.x + randf_range(-2, 2), gy2 + 0.5 + randf() * 2.5, g2.c.y + randf_range(-1, 1)), Color("#c8b89a"))
		"gate_rebuilt":
			var g3: Dictionary = sim.gates[int(e.gate)]
			ring_at(Vector3(g3.c.x, Sim.height_at(Vector2(g3.c.x, g3.c.y)) + 0.2, g3.c.y), TEAM_COLORS[int(e.team)], 3.0, 0.8)
		"repair":
			var g4: Dictionary = sim.gates[int(e.gate)]
			if randf() < 0.5:
				spark(Vector3(g4.c.x + randf_range(-1, 1), 1.0 + randf(), g4.c.y), Color("#ffe29a"))
		"gather":
			if not a.is_empty() and randf() < 0.6:
				var nd: Dictionary = sim.nodes[int(e.node)]
				spark(Vector3(nd.p.x, 1.0, nd.p.y), Color("#c9a26b") if e.kind == "wood" else Color("#cfd3d6"))
		"deliver":
			var ws: Vector2 = Sim.workshop(int(e.team))
			ring_at(Vector3(ws.x, Sim.height_at(Vector2(ws.x, ws.y)) + 0.1, ws.y), Color("#9fe07a"), 1.4, 0.5)
		"fed":
			var fo: Dictionary = sim.oracles[int(e.team)]
			var fp := Vector3(fo.pos.x, Sim.height_at(fo.pos), fo.pos.y)
			ring_at(fp, Color("#e6b3ff"), 2.4, 0.8)
			for i in 8:
				spark(fp + Vector3(randf_range(-0.8, 0.8), 0.6 + randf() * 1.6, randf_range(-0.8, 0.8)), Color("#f0c8ff"))
		"fish_caught", "fish_lost":
			var fp2: Vector2 = e.pos
			var face_d := Sim.dir_of(float(sim.by_id.get(str(e.id), {}).get("face", 0.0)))
			var reach2: float = absf(fp2.y - Land.river_c(fp2.x)) - Land.river_hw(fp2.x) + 1.1
			var wp2: Vector2 = fp2 + face_d * reach2
			ring_at(Vector3(wp2.x, Land.WATER_Y + 0.08, wp2.y), Color("#dff4ff"), 1.2 if str(e.k) == "fish_caught" else 0.7, 0.5)
			if str(e.k) == "fish_caught":
				for k2 in 6:
					spark(Vector3(wp2.x + randf_range(-0.4, 0.4), Land.WATER_Y + 0.3 + randf() * 0.6, wp2.y + randf_range(-0.4, 0.4)), Color("#bfe6ff"))
		"tantrum":
			var tp := Vector3(e.pos.x, Sim.height_at(e.pos) + 0.2, e.pos.y)
			for i in 3:
				ring_at(tp, Color("#ff5a7a") if i == 0 else Color("#ffd0dc"), Sim.TANTRUM_R * (0.7 + 0.35 * i), 0.5 + 0.2 * i)
			for i in 14:
				spark(tp + Vector3(randf_range(-2.5, 2.5), 0.3 + randf() * 2.0, randf_range(-2.5, 2.5)), Color("#ffb3c6"))
			shake(0.5)
		"lift_join":
			var lo: Dictionary = sim.oracles[int(e.team)]
			ring_at(Vector3(lo.pos.x, Sim.height_at(lo.pos) + 0.1, lo.pos.y), GOLD, 1.6, 0.4)
		"upgrade":
			var ws2: Vector2 = Sim.workshop(int(e.team))
			for i in 2:
				ring_at(Vector3(ws2.x, Sim.height_at(Vector2(ws2.x, ws2.y)) + 0.1, ws2.y), GOLD, 2.5 + i * 1.5, 0.9)
		"catapult_fire":
			var best := {}
			var bd := INF
			for cn in catapult_nodes:
				var d: float = (cn.p as Vector2).distance_to(e.from)
				if int(cn.team) == int(e.team) and d < bd:
					bd = d
					best = cn
			if not best.is_empty():
				best.fired = _time
				if best.turret != null:
					var tgt: Vector2 = e.to
					var cat_node: Node3D = best.node
					var local := cat_node.to_local(Vector3(tgt.x, 0, tgt.y))
					(best.turret as Node3D).rotation.y = atan2(-local.x, -local.z)
			var stone := _place(HEX + "projectile_catapult.gltf", Vector3(e.from.x, 4.2, e.from.y), 0.0, 3.2)
			if stone != null:
				_fx.append({"node":stone, "at":_time, "life":float(e.flight), "kind":"shell",
					"p0":Vector3(e.from.x, 4.2, e.from.y), "p1":Vector3(e.to.x, Sim.height_at(e.to) + 0.3, e.to.y)})
		"catapult_hit":
			var hp := Vector3(e.pos.x, Sim.height_at(e.pos) + 0.15, e.pos.y)
			ring_at(hp, Color("#d9c4a0"), Sim.CATAPULT_AOE * 1.3, 0.55)
			for i in 6:
				spark(hp + Vector3(randf_range(-1, 1), 0.3 + randf(), randf_range(-1, 1)), Color("#bfb3a0"))
		"ladder_up":
			var lp: Vector2 = e.pos
			var own := int(e.team)
			# Leans against the outside face of the enemy wall (the side the builder came from).
			var outward := Vector2(0, 1) if own == 0 else Vector2(0, -1)
			var base: Vector2 = lp + outward * 1.35
			var ln := _place(HEX + "ladder.gltf", Vector3(base.x, Sim.height_at(base), base.y), 0.0 if own == 0 else PI, 4.6)
			if ln != null:
				# 0.31.15 (Kevin: "show the actual ladder being put up"): it swings up off the ground into its lean.
				var lean := -0.32 if own == 0 else 0.32
				ln.rotation.x = lean * 4.4
				_raising.append({"node":ln, "t0":_time, "to":lean, "from":lean * 4.4})
				ladder_nodes[int(e.ladder)] = ln
			ring_at(Vector3(base.x, Sim.height_at(Vector2(base.x, base.y)) + 0.1, base.y), TEAM_COLORS[own], 1.8, 0.6)
		"ladder_hit":
			var lh: Node3D = ladder_nodes.get(int(e.ladder))
			if lh != null:
				spark(lh.position + Vector3(0, 1.2 + randf(), 0), Color("#c9a26b"))
		"ladder_down":
			var ld: Node3D = ladder_nodes.get(int(e.ladder))
			if ld != null:
				for i in 6:
					spark(ld.position + Vector3(randf_range(-0.6, 0.6), 0.4 + randf() * 2.0, randf_range(-0.6, 0.6)), Color("#c9a26b"))
				ld.queue_free()
				ladder_nodes.erase(int(e.ladder))
		"pickup", "drop", "recaptured":
			var o: Dictionary = sim.oracles[int(e.team)]
			ring_at(Vector3(o.pos.x, Sim.height_at(Vector2(o.pos.x, o.pos.y)) + 0.1, o.pos.y), TEAM_COLORS[int(e.team)], 1.8, 0.6)

# ---------- Oracle ----------
# The captive is each castle's KING (0.20.0; models 0.20.2, Kevin): three hand-made models per team,
# fat / fatter / fattest, swapped by his weight (sim weight 0-5 -> stage weight/2), a little bigger on
# the odd weights so every feeding shows. The models aren't rigged, so he's animated by hand: breathing
# and a sway at rest, a wobble while carried, a puff when he fattens. Kevin named them kingT1 / kingT2;
# matched by robe colour: T2 (purple) leads blue, T1 (red) leads red. (Internal names -- sim.oracles,
# oracle_nodes -- stay: players never see them.)
const KING_STAGES := ["fat", "fatter", "fattest"]
const KING_HEIGHT := 2.6              # the Knight hero is 2.54; the king a touch taller (and much wider)

func _make_oracle(team: int) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var body := Node3D.new()                     # the part that breathes, wobbles and grows
	root.add_child(body)
	var stages := []
	for st in KING_STAGES:
		var packed := Stage.scene("res://assets/kings/king_%s_%s.glb" % ["blue" if team == 0 else "red", st])
		var m: Node3D = packed.instantiate() if packed != null else Node3D.new()
		m.scale = Vector3.ONE * (KING_HEIGHT / 1.9)          # the models are 1.9 tall, feet at 0
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _hq() else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = st == "fat"
		body.add_child(m)
		stages.append(m)
	var ground_ring := _decal(Vector3.ZERO, 1.0, TEAM_COLORS[team], 0.8)
	ground_ring.reparent(root, false)
	return {"root":root, "body":body, "player":null, "stages":stages, "stage":0, "puff":0.0,
		"ground":ground_ring, "state":""}

func _sync_oracles(dt: float) -> void:
	for t in 2:
		var n: Dictionary = oracle_nodes[t]
		var o: Dictionary = sim.oracles[t]
		var root: Node3D = n.root
		var target := Vector3(o.pos.x, Sim.height_at(o.pos), o.pos.y)
		if not n.has("aura"):
			n["aura"] = _decal(Vector3.ZERO, Sim.HEAL_R, Color("#7dffa8"), 0.35)
		var aura: Node3D = n.aura
		aura.visible = o.state == "cell"
		if aura.visible:
			aura.position = Vector3(o.pos.x, Sim.height_at(o.pos) + 0.07, o.pos.y)
			var ap := 0.92 + sin(_time * 2.2) * 0.08
			aura.scale = Vector3(ap, 0.15, ap)
		if o.state == "carried":
			var a: Dictionary = actors.get(o.carrier, {})
			if not a.is_empty():
				# Held up in the middle of all her lifters, higher the more there are.
				var sum := Vector3.ZERO
				var cnt := 0
				for id in o.lifters:
					var la: Dictionary = actors.get(id, {})
					if not la.is_empty():
						sum += (la.root as Node3D).position
						cnt += 1
				var centre: Vector3 = sum / float(maxi(1, cnt)) if cnt > 0 else a.root.position
				target = centre + Vector3(0, 1.75 + 0.12 * float(maxi(0, cnt - 1)), 0)
				root.rotation.y = a.root.rotation.y
			(n.ground as Node3D).visible = false
			if n.state != "carried" and n.player != null:
				(n.player as AnimationPlayer).play("t/Holding_B" if (n.player as AnimationPlayer).has_animation("t/Holding_B") else "g/Idle_B")
		else:
			(n.ground as Node3D).visible = true
			target.y = Sim.height_at(o.pos)
			# Facing (Kevin: "the king is facing the wall"): in his cell he looks out through the bars at
			# the cell door; on his throne, out over his castle; dropped, he keeps his last facing.
			if o.state == "cell":
				for g in sim.gates:
					if int(g.team) != t and str(g.get("kind", "")) == "jail":
						root.rotation.y = lerp_angle(root.rotation.y, Sim.angle_of((g.c as Vector2) - (o.pos as Vector2)), 1.0 - exp(-dt * 6.0))
			elif (o.pos as Vector2).distance_to(Sim.throne(t)) < 1.5:
				root.rotation.y = lerp_angle(root.rotation.y, Sim.angle_of(Sim._c(t, Vector2(0.0, 0.0)) - Sim.throne(t)), 1.0 - exp(-dt * 6.0))
			var pulse := 0.8 + sin(_time * 4.0) * 0.2
			(n.ground as Node3D).scale = Vector3(pulse, 0.15, pulse)
			if n.state == "carried" and n.player != null:
				(n.player as AnimationPlayer).play("g/Idle_B")
		n.state = o.state
		root.position = target if root.position.distance_to(target) > 5.0 else root.position.lerp(target, 1.0 - exp(-dt * 20.0))

# ---------- projectiles ----------
func _sync_projectiles() -> void:
	var live := {}
	for p in sim.projectiles:
		live[p.id] = true
		var node: Node3D = proj_nodes.get(p.id)
		if node == null:
			node = _make_projectile(str(p.kind))
			proj_nodes[p.id] = node
		# Offline the sim ticks at 30 Hz while frames run at 60: draw it where it is *now*.
		var at: Vector2 = p.pos + (p.vel as Vector2) * proj_lead
		var y := 1.2 + Sim.height_at(at)
		var pitch := 0.0
		if p.has("h0"):
			# From a tower's deck: starts up where the shooter stands and comes down onto the aimed spot.
			var o: Vector2 = p.o
			var top: float = Sim.height_at(o) + float(p.h0) + 1.2
			var k := clampf(at.distance_to(o) / maxf(float(p.dd), 0.5), 0.0, 1.0)
			y = lerpf(top, y, k)
			if k < 1.0:
				pitch = atan2(top - (1.2 + Sim.height_at(at)), maxf(float(p.dd), 0.5))
		node.position = Vector3(at.x, y, at.y)
		node.rotation = Vector3(pitch, Sim.angle_of(p.vel), 0.0)     # +X tips the +Z nose down
		if str(p.kind) == "hammer":
			var sp := node.get_node_or_null("spin") as Node3D
			if sp != null:
				sp.rotation.x = Time.get_ticks_msec() * 0.018          # end over end
	for id in proj_nodes.keys():
		if not live.has(id):
			proj_nodes[id].queue_free()
			proj_nodes.erase(id)

func _make_projectile(kind: String) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	if kind == "hammer":
		# The Crusader's hammer (0.30.5): a glowing gold head on a wooden handle, spinning end over end.
		var spin := Node3D.new()
		spin.name = "spin"
		root.add_child(spin)
		var handle := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.05
		hm.bottom_radius = 0.06
		hm.height = 0.8
		handle.mesh = hm
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color("#7a4e2a")
		handle.material_override = wood
		spin.add_child(handle)
		var head := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.46, 0.26, 0.26)
		head.mesh = bm
		head.position = Vector3(0.0, 0.4, 0.0)
		var gold := StandardMaterial3D.new()
		gold.albedo_color = Color("#f2c94c")
		gold.emission_enabled = true
		gold.emission = Color("#ffd766")
		gold.emission_energy_multiplier = 1.3
		gold.metallic = 0.6
		gold.roughness = 0.35
		head.material_override = gold
		spin.add_child(head)
		root.scale = Vector3.ONE * 1.25
		return root
	if kind == "arrow":
		var packed := Stage.scene("res://assets/kaykit/weapons/arrow_bow.gltf")
		if packed != null:
			var arrow: Node3D = packed.instantiate()
			# The model already lies along +Z, arrowhead forward (measured: z -0.64..0.62, the narrow end at
			# +Z), and the root turns +Z onto the flight path. The old 90 deg turn about X stood every arrow
			# on its tip (Kevin: "arrows flying sideways instead of straight").
			arrow.scale = Vector3.ONE * 1.3
			root.add_child(arrow)
			return root
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.28 if kind == "fire" else 0.12
	sm.height = sm.radius * 2.0
	ball.mesh = sm
	ball.material_override = _unshaded(_bright(Color(1.0, 0.55, 0.15, 0.95) if kind == "fire" else Color(1, 1, 0.8, 0.9)))
	root.add_child(ball)
	return root

# ---------- effects ----------
# No material or text writes per frame here. In Godot's GLES3 renderer every material parameter
# change re-uploads that material's buffer (glBufferData), and changing a Label3D's modulate
# rebuilds its mesh and materials. Field logs showed the Adreno driver hanging after ~5-6k frames
# of that churn, so effects share cached materials and fade by scale only, and damage numbers
# are drawn by the 2D HUD instead of Label3D.
static var _fx_mats: Dictionary = {}
var numbers: Array = []   # [{pos: Vector3, text, mine, at}] read by the HUD

func _fx_mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _fx_mats.has(key):
		_fx_mats[key] = _unshaded(_bright(color))
	return _fx_mats[key]

var _shake := 0.0

func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)

func ring_at(at: Vector3, color: Color, grow := 2.2, life := 0.6) -> void:
	if low_fx and life < 0.5:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh(0.5, 0.12)
	var c := color
	c.a = 0.85
	mi.material_override = _fx_mat(c)
	mi.position = at + Vector3(0, 0.08, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_fx.append({"node":mi, "at":_time, "life":life, "kind":"ring", "grow":grow})

func spark(at: Vector3, color: Color) -> void:
	if low_fx:
		return
	var mi := MeshInstance3D.new()
	if _spark_mesh == null:
		_spark_mesh = SphereMesh.new()
		_spark_mesh.radius = 0.12
		_spark_mesh.height = 0.24
		_spark_mesh.radial_segments = 6
		_spark_mesh.rings = 3
	mi.mesh = _spark_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _fx_mat(color)
	mi.position = at
	add_child(mi)
	var dir := Vector3(randf_range(-1, 1), randf_range(0.6, 1.6), randf_range(-1, 1))
	_fx.append({"node":mi, "at":_time, "life":0.45, "kind":"spark", "p0":at, "dir":dir})

func number(at: Vector3, text: String, mine: bool) -> void:
	numbers.append({"pos":at, "text":text, "mine":mine, "at":_time})
	if numbers.size() > 40:
		numbers.pop_front()

func _step_fx() -> void:
	for i in range(_fx.size()-1, -1, -1):
		var fx: Dictionary = _fx[i]
		var age := _time - float(fx.at)
		var node: Node3D = fx.node
		if age > float(fx.life) or not is_instance_valid(node):
			if is_instance_valid(node):
				node.queue_free()
			_fx.remove_at(i)
			continue
		var u := age / float(fx.life)
		match str(fx.kind):
			"ring":
				# Grow outward and disappear at the end of its life (no alpha fade).
				var s := 0.4 + u * float(fx.grow)
				node.scale = Vector3(s, 0.3, s)
			"shell":
				var p0: Vector3 = fx.p0
				var p1: Vector3 = fx.p1
				node.position = p0.lerp(p1, u) + Vector3(0, 7.0 * u * (1.0 - u), 0)
				node.rotation.x += 0.25
			"spark":
				node.position = fx.p0 + fx.dir * u * 1.2
				node.scale = Vector3.ONE * maxf(0.05, 1.0 - u)
	for i in range(numbers.size()-1, -1, -1):
		if _time - float(numbers[i].at) > 0.8:
			numbers.remove_at(i)

# ---------- camera ----------
var cam_override: Array = []   # [eye: Vector3, target: Vector3] for tests/screenshots only

func snap_camera() -> void:
	# Jump straight to the player next frame (after a teleport) instead of gliding across the map.
	_cam_target = Vector3.ZERO

func _update_camera(dt: float) -> void:
	if cam_override.size() == 2:
		camera.position = cam_override[0]
		camera.look_at(cam_override[1], Vector3.UP)
		return
	var me: Dictionary = sim.by_id.get(player_id, {})
	var focus := Vector3.ZERO
	var a: Dictionary = actors.get(player_id, {})
	if not a.is_empty():
		focus = a.root.position
	if not me.is_empty() and me.state == "dead":
		var sp: Vector2 = Sim.spawn(me.team)
		focus = Vector3(sp.x, 0, sp.y)
	# Look up-field (toward the enemy keep) so more of what's ahead is on screen.
	var ahead := -1.0 if me.get("team", 0) == 0 else 1.0
	var target := focus + Vector3(0, 0, ahead * 3.2)
	_cam_target = target if _cam_target == Vector3.ZERO else _cam_target.lerp(target, 1.0 - exp(-dt * 6.0))
	camera.position = _cam_target + Vector3(0, 38.0, -ahead * 30.0)
	camera.look_at(_cam_target, Vector3.UP)
	if _shake > 0.01:
		# Short camera shake for the tantrum shockwave.
		camera.position += Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * _shake * 0.5
		_shake = maxf(0.0, _shake - dt * 1.6)

func bars() -> Array:
	# [{pos, fill, color}] for the HUD to draw 2D health bars over living units.
	var out := []
	for u in sim.units:
		if u.state == "dead":
			continue
		var a: Dictionary = actors.get(u.id, {})
		if a.is_empty() or not is_instance_valid(a.root):
			continue
		var c: Color = Color("#7dff8a") if u.id == player_id else TEAM_COLORS[u.team]
		out.append({"pos": (a.root as Node3D).position + Vector3(0, 2.7, 0), "fill": clampf(u.hp / maxf(1.0, u.max_hp), 0.0, 1.0), "color": c})
	return out

func gate_bars() -> Array:
	# Damaged gates (either team) get a health bar over the arch.
	var out := []
	for g in sim.gates:
		if not sim.gate_blocks(g) or g.hp >= g.max_hp:
			continue
		out.append({"pos": Vector3(g.c.x, 4.2, g.c.y), "fill": g.hp / g.max_hp, "color": TEAM_COLORS[g.team]})
	return out

func screen_point(world: Vector3) -> Vector2:
	return camera.unproject_position(world)

func is_on_screen(world: Vector3) -> bool:
	return not camera.is_position_behind(world) and Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).has_point(camera.unproject_position(world))


# ---------- boulders, logs and rocks (0.31.0) ----------
static var _boulder_cache := {}
static var _boulder_mat: StandardMaterial3D = null
static var _bark_mat: StandardMaterial3D = null
var item_nodes := {}

static func boulder_mesh(seed_n: int, radius: float, detail := 1) -> ArrayMesh:
	# A low-poly boulder: an icosphere pushed in and out by smooth noise, squashed a little, flat-shaded faces in
	# slightly different greys. Cached per (seed, size, detail).
	var key := "%d_%d_%d" % [seed_n, int(radius * 100.0), detail]
	if _boulder_cache.has(key):
		return _boulder_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9100 + seed_n
	var t := (1.0 + sqrt(5.0)) / 2.0
	var vs: Array = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
		Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in vs.size():
		vs[i] = (vs[i] as Vector3).normalized()
	var fs: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for d in detail:
		var mids := {}
		var nf: Array = []
		for f in fs:
			var m := []
			for e in [[f[0], f[1]], [f[1], f[2]], [f[2], f[0]]]:
				var k2 := "%d_%d" % [mini(e[0], e[1]), maxi(e[0], e[1])]
				if not mids.has(k2):
					vs.append(((vs[e[0]] as Vector3) + (vs[e[1]] as Vector3)).normalized())
					mids[k2] = vs.size() - 1
				m.append(mids[k2])
			nf.append([f[0], m[0], m[2]])
			nf.append([f[1], m[1], m[0]])
			nf.append([f[2], m[2], m[1]])
			nf.append([m[0], m[1], m[2]])
		fs = nf
	var dirs := []
	for k in 4:
		dirs.append(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(1.6, 3.2))
	var sq := Vector3(rng.randf_range(0.95, 1.15), rng.randf_range(0.62, 0.78), rng.randf_range(0.85, 1.0)) * radius
	var pos := []
	for v in vs:
		var bump := 0.0
		for dv in dirs:
			bump += sin((v as Vector3).dot(dv) * 1.7 + float(dirs.find(dv))) * 0.07
		bump += rng.randf_range(-0.045, 0.045)
		pos.append((v as Vector3) * (1.0 + bump) * sq)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in fs:
		var a: Vector3 = pos[f[0]]
		var b: Vector3 = pos[f[1]]
		var c: Vector3 = pos[f[2]]
		var nrm := (b - a).cross(c - a).normalized()
		if nrm.dot((a + b + c) / 3.0) < 0.0:
			nrm = -nrm
			var tmp := b
			b = c
			c = tmp
		var g := rng.randf_range(0.28, 0.45)                    # darker, more contrast (the first try read washed-out)
		var col := Color(g * rng.randf_range(0.97, 1.04), g, g * rng.randf_range(0.96, 1.05))
		for vtx in [a, c, b]:
			st.set_color(col)
			st.set_normal(nrm)
			st.add_vertex(vtx)
	var mesh := st.commit()
	if _boulder_mat == null:
		_boulder_mat = StandardMaterial3D.new()
		_boulder_mat.vertex_color_use_as_albedo = true
		_boulder_mat.roughness = 0.92
	mesh.surface_set_material(0, _boulder_mat)
	_boulder_cache[key] = mesh
	return mesh

func _mesh_node(mesh: Mesh, at: Vector3, yaw: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	mi.rotation.y = yaw
	add_child(mi)
	return mi

func _log_node() -> Node3D:
	if _bark_mat == null:
		_bark_mat = StandardMaterial3D.new()
		_bark_mat.albedo_color = Color("#7a5230")
		_bark_mat.roughness = 0.95
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = Sim.LOG_R
	cm.bottom_radius = Sim.LOG_R * 1.06
	cm.height = Sim.LOG_HALF * 2.0
	cm.radial_segments = 10
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = _bark_mat
	root.add_child(mi)
	# pale cut ends
	for end in [-1.0, 1.0]:
		var cap := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = Sim.LOG_R * 0.86
		cyl.bottom_radius = Sim.LOG_R * 0.86
		cyl.height = 0.03
		cyl.radial_segments = 10
		cap.mesh = cyl
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color("#d9b27c")
		cap.material_override = wood
		cap.position = Vector3(0, Sim.LOG_HALF * end, 0)
		root.add_child(cap)
	add_child(root)
	return root

func _sync_items(dt: float) -> void:
	var seen := {}
	for it in sim.items:
		var id := int(it.id)
		seen[id] = true
		var nd: Node3D = item_nodes.get(id, null)
		var is_log: bool = it.kind == "log"
		var r: float = Sim.LOG_R if is_log else Sim.ROCK_R
		var p: Vector2 = it.pos
		var y := Sim.height_at(p) + r
		if is_log and Sim.water_depth(p) > 0.15:
			y = Land.WATER_Y + 0.06                           # floating
		var target := Vector3(p.x, y, p.y)
		if nd == null:
			nd = _log_node() if is_log else _mesh_node(boulder_mesh(id % 9, Sim.ROCK_R + 0.04, 1), target, 0.0)
			nd.position = target
			item_nodes[id] = nd
		nd.position = nd.position.lerp(target, minf(1.0, dt * 16.0))
		if is_log:
			var ang := float(it.ang)
			var ax := Vector3(cos(ang), 0.0, sin(ang))
			nd.basis = Basis(ax, float(it.roll)) * Basis(Vector3.UP, -ang) * Basis(Vector3(0, 0, 1), PI * 0.5)
		else:
			var rax := float(it.rax)
			nd.basis = Basis(Vector3(sin(rax), 0.0, -cos(rax)), float(it.roll))
	for id in item_nodes.keys():
		if not seen.has(id):
			(item_nodes[id] as Node3D).queue_free()
			item_nodes.erase(id)


# Ladders going up (0.31.15): from lying on the ground to their lean against the wall over LADDER_RAISE s, a little
# overshoot as they land on the wall.
const LADDER_RAISE := 0.9
var _raising: Array = []

func _sync_raising() -> void:
	for i in range(_raising.size() - 1, -1, -1):
		var r: Dictionary = _raising[i]
		var n: Node3D = r.node
		if not is_instance_valid(n):
			_raising.remove_at(i)
			continue
		var k := clampf((_time - float(r.t0)) / LADDER_RAISE, 0.0, 1.0)
		var e := 1.0 + 2.2 * pow(k - 1.0, 3.0) + 1.2 * pow(k - 1.0, 2.0)     # ease out with a small overshoot
		n.rotation.x = lerpf(float(r.from), float(r.to), e)
		if k >= 1.0:
			n.rotation.x = float(r.to)
			_raising.remove_at(i)


# ---------- cloth capes (0.31.17, Kevin: "realistic cloth physics for the capes") ----------
# The Knight, Mage, Ranger and both Rogues wear a cape (a rigid skinned mesh in the KayKit models). Near the camera it is
# swapped for a cloth: a CAPE_COLS x CAPE_ROWS Verlet sheet pinned across the shoulders to the chest bone, falling under
# gravity with a little wind, held in shape by stretch and bend links, kept off the body (behind the back, outside a
# capsule round the torso) and above the ground. It swings and trails when he runs, flies back when he's thrown, settles
# when he stops. Rendered as a double-sided strip in the cape's own atlas colour. Far away (or off screen) the original
# cape shows and nothing is simulated.
const CAPE_COLS := 5
const CAPE_ROWS := 6
const CAPE_NEAR := 34.0          # simulate within this of the camera's focus
const CAPE_GRAVITY := 7.5
const CAPE_DAMP := 0.93
const CAPE_ITERS := 2

func _cape_setup(a: Dictionary) -> void:
	a["cape"] = null
	var body: Node3D = a.body
	var orig: MeshInstance3D = null
	for c in body.find_children("*_Cape", "MeshInstance3D", true, false):
		orig = c
		break
	var skel: Skeleton3D = body.find_child("Skeleton3D", true, false)
	if orig == null or skel == null:
		return
	var chest := skel.find_bone("chest")
	if chest < 0:
		return
	# the cape's colour: its vertices all sample one patch of the atlas
	var uv := Vector2(0.5, 0.5)
	var arr := orig.mesh.surface_get_arrays(0)
	if arr[Mesh.ARRAY_TEX_UV] != null and (arr[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() > 0:
		uv = (arr[Mesh.ARRAY_TEX_UV] as PackedVector2Array)[0]
	var mat = orig.get_active_material(0)
	var cm: Material = mat.duplicate() if mat != null else StandardMaterial3D.new()
	if cm is BaseMaterial3D:
		(cm as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	var rest := PackedVector3Array()
	for r in CAPE_ROWS:
		var fv := float(r) / float(CAPE_ROWS - 1)
		for c2 in CAPE_COLS:
			var fu := float(c2) / float(CAPE_COLS - 1)
			# across the shoulders at the top, a little wider and flared back at the hem (the model's own shape)
			var half := lerpf(0.36, 0.47, fv)
			rest.append(Vector3(lerpf(-half, half, fu), lerpf(1.2, 0.12, fv), lerpf(-0.08, -0.36, fv)))
	var cloth := MeshInstance3D.new()
	cloth.top_level = true
	cloth.mesh = ArrayMesh.new()
	cloth.visible = false
	(a.root as Node3D).add_child(cloth)
	a["cape"] = {"orig":orig, "skel":skel, "chest":chest, "b0i":skel.get_bone_global_rest(chest).affine_inverse(),
		"rest":rest, "pos":PackedVector3Array(), "prev":PackedVector3Array(), "node":cloth, "mat":cm, "uv":uv, "on":false,
		"phase":randi() % 2}

func _cape_rigid(cp: Dictionary) -> Transform3D:
	# model space -> world, rigidly following the chest bone (the shoulders' frame)
	var skel: Skeleton3D = cp.skel
	return skel.global_transform * skel.get_bone_global_pose(int(cp.chest)) * (cp.b0i as Transform3D)

static var cape_usec := 0           # time spent in cloth this session (diag/tests)
static var cape_active := 0

func _cape_step(a: Dictionary, dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_cape_step_inner(a, dt)
	cape_usec += Time.get_ticks_usec() - t0

func _cape_step_inner(a: Dictionary, dt: float) -> void:
	var cp: Dictionary = a.cape
	var skel: Skeleton3D = cp.skel
	var ap: Vector3 = (a.root as Node3D).global_position
	var cpos: Vector3 = camera.global_position if is_instance_valid(camera) else ap
	var near := Vector2(ap.x - cpos.x, ap.z - cpos.z).length() < CAPE_NEAR and (a.root as Node3D).visible   # ground distance
	if not near:
		if bool(cp.on):
			cp.on = false
			(cp.node as MeshInstance3D).visible = false
			(cp.orig as MeshInstance3D).visible = true
		return
	# Further off, half rate: step every other frame with the time saved up.
	cp["acc"] = float(cp.get("acc", 0.0)) + dt
	if Vector2(ap.x - cpos.x, ap.z - cpos.z).length() > CAPE_NEAR * 0.7 and bool(cp.on) \
			and (Engine.get_process_frames() + int(cp.get("phase", 0))) % 2 == 1:
		return
	dt = float(cp.acc)
	cp.acc = 0.0
	var rig := _cape_rigid(cp)
	var rest: PackedVector3Array = cp.rest
	var pos: PackedVector3Array = cp.pos
	var prev: PackedVector3Array = cp.prev
	var n := CAPE_COLS * CAPE_ROWS
	if not bool(cp.on) or pos.size() != n:
		pos.resize(n)
		prev.resize(n)
		for i in n:
			pos[i] = rig * rest[i]
			prev[i] = pos[i]
		cp.on = true
		(cp.node as MeshInstance3D).visible = true
		(cp.orig as MeshInstance3D).visible = false
	var h := clampf(dt, 0.0, 0.05)
	var steps := 2 if h > 0.026 else 1
	h /= float(steps)
	var g := Vector3(0.0, -CAPE_GRAVITY, 0.0)
	var wind := Vector3(sin(_time * 1.3 + float(hash(a.root)) * 0.001) * 0.9, 0.0, cos(_time * 0.9) * 0.6)
	var inv := rig.affine_inverse()
	var ground := (a.root as Node3D).global_position.y + 0.03
	for st in steps:
		for i in n:
			if i < CAPE_COLS:
				prev[i] = pos[i]
				pos[i] = rig * rest[i]                     # pinned across the shoulders
				continue
			var p: Vector3 = pos[i]
			var v: Vector3 = (p - prev[i]) * CAPE_DAMP
			prev[i] = p
			pos[i] = p + v + (g + wind) * h * h
		for it in CAPE_ITERS:
			for r in CAPE_ROWS:
				for c in CAPE_COLS:
					var i := r * CAPE_COLS + c
					if c + 1 < CAPE_COLS:
						_cape_link(pos, rest, i, i + 1, r == 0)
					if r + 1 < CAPE_ROWS:
						_cape_link(pos, rest, i, i + CAPE_COLS, r == 0)
					if r + 2 < CAPE_ROWS:
						_cape_link(pos, rest, i, i + 2 * CAPE_COLS, r == 0)      # bend: keeps it from folding flat
			# keep it off the body (in the shoulders' frame) and above the ground
			for i in range(CAPE_COLS, n):
				var m: Vector3 = inv * pos[i]
				var moved := false
				if m.z > -0.07:
					m.z = -0.07
					moved = true
				var rxz := Vector2(m.x, m.z)
				if m.y > 0.05 and m.y < 1.3 and rxz.length() < 0.3:
					rxz = rxz.normalized() * 0.3 if rxz.length() > 0.001 else Vector2(0.0, -0.3)
					m.x = rxz.x
					m.z = rxz.y
					moved = true
				if moved:
					pos[i] = rig * m
				if pos[i].y < ground:
					pos[i].y = ground
	cp.pos = pos
	cp.prev = prev
	cape_active += 1
	_cape_draw(cp)

func _cape_link(pos: PackedVector3Array, rest: PackedVector3Array, i: int, j: int, pin_i: bool) -> void:
	var d: Vector3 = pos[j] - pos[i]
	var l := d.length()
	if l < 0.0001:
		return
	var want: float = rest[i].distance_to(rest[j])
	var corr := d * ((l - want) / l)
	if pin_i:
		pos[j] -= corr                                 # the shoulder end doesn't move
	else:
		pos[i] += corr * 0.5
		pos[j] -= corr * 0.5

static var _cape_idx := PackedInt32Array()

func _cape_draw(cp: Dictionary) -> void:
	var pos: PackedVector3Array = cp.pos
	if _cape_idx.is_empty():
		for r in CAPE_ROWS - 1:
			for c in CAPE_COLS - 1:
				var i := r * CAPE_COLS + c
				_cape_idx.append_array([i, i + CAPE_COLS, i + 1, i + 1, i + CAPE_COLS, i + CAPE_COLS + 1])
	var nrm := PackedVector3Array()
	nrm.resize(pos.size())
	for rr in CAPE_ROWS:
		for cc in CAPE_COLS:
			var tx: Vector3 = pos[rr * CAPE_COLS + mini(cc + 1, CAPE_COLS - 1)] - pos[rr * CAPE_COLS + maxi(cc - 1, 0)]
			var ty: Vector3 = pos[mini(rr + 1, CAPE_ROWS - 1) * CAPE_COLS + cc] - pos[maxi(rr - 1, 0) * CAPE_COLS + cc]
			nrm[rr * CAPE_COLS + cc] = ty.cross(tx).normalized()
	if not cp.has("uvs"):
		var uvs := PackedVector2Array()
		uvs.resize(pos.size())
		uvs.fill(cp.uv)
		cp["uvs"] = uvs
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_TEX_UV] = cp.uvs
	arrays[Mesh.ARRAY_INDEX] = _cape_idx
	var am: ArrayMesh = (cp.node as MeshInstance3D).mesh
	am.clear_surfaces()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(0, cp.mat)
