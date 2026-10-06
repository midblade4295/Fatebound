extends Node3D
const Eco = preload("res://scripts/meta/economy.gd")
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
	# 0.31.32: the last three upgrades get their own looks
	"assassin": {"model":"meshy:assassin","r":"dagger","l":"dagger","idle":"g/Idle_B","attack":"m/Melee_Dualwield_Attack_Stab","ability":"m/Melee_1H_Attack_Jump_Chop","tint":"#5b4f73"},
	"sniper": {"model":"Ranger","r":"crossbow_2handed","l":"","idle":"r/Ranged_Bow_Idle","attack":"r/Ranged_Bow_Release","ability":"r/Ranged_Bow_Draw","tint":"#4f6b4a"},
	"archmage": {"model":"meshy:archmage","r":"staff","l":"spellbook_open","idle":"g/Idle_B","attack":"r/Ranged_Magic_Shoot","ability":"r/Ranged_Magic_Summon","tint":"#a33d3d"},
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
const WATER_ROWS := 10                      # 0.31.21: vertices across the river, so waves can lift the surface
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
uniform float wave_height = 1.5;          // 0.31.21: the surface rises and falls with the simulated waves
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 ruv = vec2((wpos.x + rip_half) / (2.0 * rip_half), UV.y);
	float inside = step(0.0, ruv.x) * step(ruv.x, 1.0);
	float h = textureLod(rip_tex, ruv, 0.0).r * inside;
	h = (isnan(h) || isinf(h)) ? 0.0 : h;
	float edge = smoothstep(0.0, 0.1, UV2.y) * smoothstep(1.0, 0.9, UV2.y);     // held at the banks
	VERTEX.y += h * wave_height * edge;
	wpos.y += h * wave_height * edge;
}
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

var _rip_kicks: Array = []

func water_blast(at: Vector2, power: float) -> void:
	# 0.31.21 (Kevin: "the water to react to the bomb explosion and make huge waves"): a blast in or beside the river
	# pushes the water down hard where it hits for a few frames; the wave equation throws the rings out across it.
	# Also a column of spray.
	var c := Land.river_c(at.x)
	var hw := Land.river_hw(at.x)
	var off := at.y - c
	var reach := absf(off) - hw                   # how far from the water's edge (negative: in the water)
	if reach > 5.0 or absf(at.x) > RIP_HALF - 1.0:
		return
	var p := Vector2(at.x, c + clampf(off, -hw + 0.6, hw - 0.6))
	var k := power * clampf(1.0 - maxf(reach, 0.0) / 5.0, 0.25, 1.0)
	_rip_kicks.append({"p":p, "frames":4, "r":2.4 * sqrt(power), "s":-0.5 * k})
	var sp := Vector3(p.x, Land.WATER_Y + 0.1, p.y)
	for i in int(30 * k):
		spark(sp + Vector3(randf_range(-1.2, 1.2), randf_range(0.0, 3.5 * k), randf_range(-1.2, 1.2)), Color(0.88, 0.95, 1.0))
	ring_at(sp, Color(0.85, 0.95, 1.0), 4.0 * k + 1.0, 0.9)

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
	for i in range(_rip_kicks.size() - 1, -1, -1):
		var kk: Dictionary = _rip_kicks[i]
		var kp: Vector2 = kk.p
		var kv := (kp.y - (Land.river_c(kp.x) - RIP_ACROSS * 0.5)) / RIP_ACROSS
		drops.push_front(Vector4((kp.x + RIP_HALF) / (2.0 * RIP_HALF), kv, float(kk.r), float(kk.s)))
		kk.frames = int(kk.frames) - 1
		if int(kk.frames) <= 0:
			_rip_kicks.remove_at(i)
	if drops.size() > 16:
		drops.resize(16)
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
	var rows := WATER_ROWS
	for k in n + 1:
		var x := minf(xa + k, xb)
		var c := Land.river_c(x)
		var hw := Land.river_hw(x) + 0.35
		for r in rows + 1:
			var f := float(r) / float(rows)
			verts.append(Vector3(x, y, c - hw + 2.0 * hw * f))
			uvs.append(Vector2((x - xa) / span, 0.5 + (2.0 * f - 1.0) * hw / RIP_ACROSS))
			uv2s.append(Vector2(0.0, f))
		if k < n:
			for r in rows:
				var a := k * (rows + 1) + r
				var b := a + rows + 1
				idx.append_array([a, b, a + 1, a + 1, b, b + 1])
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
			if slot[2] == "drain" or plasma_nodes.has(slot[1]):
				_sync_plasma(slot[1], u, to if slot[2] == "drain" and sim.alive(u) else {})
				if slot[2] == "drain":
					continue
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

# ---------- the Necromancer's plasma siphon (0.31.50) ----------
# Kevin: "a plasma beam" for the drain. Our own shader (plasma_beam.gdshader): a twisting plasma sheath round a hot core,
# pulses running from the victim into the Necromancer, a soft glow at each end -- the victim's a darker, purple-green
# wound, the Necromancer's a bright green bloom.
var plasma_nodes: Dictionary = {}
static var _plasma_mats := {}
const PLASMA_SHADER := preload("res://scripts/siege/plasma_beam.gdshader")

static func _plasma_mat(kind: String) -> Material:
	if not _plasma_mats.has(kind):
		if kind == "glow_src" or kind == "glow_dst":
			var gt := GradientTexture2D.new()
			gt.fill = GradientTexture2D.FILL_RADIAL
			gt.fill_from = Vector2(0.5, 0.5)
			gt.fill_to = Vector2(1.0, 0.5)
			var gr := Gradient.new()
			gr.set_color(0, Color(1, 1, 1, 1))
			gr.set_color(1, Color(1, 1, 1, 0))
			gr.add_point(0.35, Color(1, 1, 1, 0.55))
			gt.gradient = gr
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			m.no_depth_test = false
			m.albedo_texture = gt
			m.albedo_color = Color(0.3, 0.75, 0.35, 0.8) if kind == "glow_dst" else Color(0.45, 0.2, 0.75, 0.8)
			_plasma_mats[kind] = m
		else:
			var sm := ShaderMaterial.new()
			sm.shader = PLASMA_SHADER
			sm.set_shader_parameter("core", 1.0 if kind == "core" else 0.0)
			sm.set_shader_parameter("intensity", 1.35 if kind == "core" else 1.1)
			sm.set_shader_parameter("twist", 3.0)
			sm.set_shader_parameter("flow_dir", -1.0)     # 0.31.51 (Kevin): flowing back INTO the Necromancer (it ran out)
			_plasma_mats[kind] = sm
	return _plasma_mats[kind]

func _make_plasma() -> Node3D:
	var root := Node3D.new()
	for part in [["sheath", 0.3, 18], ["core", 0.07, 8]]:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = float(part[1])
		cm.bottom_radius = float(part[1])
		cm.height = 1.0
		cm.radial_segments = int(part[2])
		cm.rings = 1
		mi.mesh = cm
		mi.material_override = _plasma_mat(str(part[0]))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = str(part[0])
		root.add_child(mi)
	for g in [["glow_src", 0.9], ["glow_dst", 1.1]]:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2.ONE * float(g[1])
		q.mesh = qm
		q.material_override = _plasma_mat(str(g[0]))
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.name = str(g[0])
		root.add_child(q)
	return root

func _sync_plasma(key: String, u: Dictionary, to: Dictionary) -> void:
	var pb: Node3D = plasma_nodes.get(key)
	var a: Dictionary = actors.get(u.id, {})
	var b: Dictionary = actors.get(to.get("id", ""), {}) if not to.is_empty() else {}
	if to.is_empty() or a.is_empty() or b.is_empty():
		if pb != null:
			pb.visible = false
		return
	if pb == null:
		pb = _make_plasma()
		add_child(pb)
		plasma_nodes[key] = pb
	var p0: Vector3 = (a.root as Node3D).position + Vector3(0, 1.35, 0) + Vector3(sin(float(u.face)), 0, cos(float(u.face))) * 0.35
	var p1: Vector3 = (b.root as Node3D).position + Vector3(0, 1.1, 0)
	var len := p0.distance_to(p1)
	if len < 0.05:
		pb.visible = false
		return
	pb.visible = true
	var up := (p1 - p0) / len
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	var fwd := side.cross(up)
	var mid := (p0 + p1) * 0.5
	var h := float(hash(key) % 100)
	var wob := 1.0 + 0.14 * sin(_time * 13.0 + h) + 0.06 * sin(_time * 31.0 + h * 0.7)
	var sheath := pb.get_node("sheath") as MeshInstance3D
	var core := pb.get_node("core") as MeshInstance3D
	sheath.transform = Transform3D(Basis(side * wob, up * len, fwd * wob), mid)
	core.transform = Transform3D(Basis(side, up * len, fwd), mid)
	sheath.set_instance_shader_parameter("beam_len", len)
	core.set_instance_shader_parameter("beam_len", len)
	var g_src := pb.get_node("glow_src") as Node3D        # on the victim: the wound the plasma is pulled from
	var g_dst := pb.get_node("glow_dst") as Node3D        # at the Necromancer's hands
	g_src.position = p1
	g_dst.position = p0
	g_src.scale = Vector3.ONE * (0.9 + 0.2 * sin(_time * 9.0 + h))
	g_dst.scale = Vector3.ONE * (0.85 + 0.3 * pow(0.5 + 0.5 * sin(_time * 9.0 + h + 1.3), 3.0))

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
		var newp := Vector3(h.pos.x, gy, h.pos.y)
		var mv: Vector3 = newp - n.position
		n.position = newp
		var hat := n.get_child(0) as Node3D
		var moving: bool = Vector2(mv.x, mv.z).length() > 0.004 and bool(n.get_meta("placed", false))
		n.set_meta("placed", true)
		if moving:                                    # 0.31.20: tumbling along the ground with its slide
			var ax := Vector3(mv.z, 0.0, -mv.x).normalized()
			hat.rotate(ax, Vector2(mv.x, mv.z).length() / 0.22)
			hat.position.y = lerpf(hat.position.y, 0.18, 0.3)
			n.set_meta("still_since", _time)
		elif _time - float(n.get_meta("still_since", -10.0)) < 0.6:
			hat.rotation = hat.rotation.lerp(Vector3(0.0, hat.rotation.y, 0.0), 0.15)   # settles upright
		else:
			hat.rotation.x = 0.0
			hat.rotation.z = 0.0
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
			if turret != null:                                  # 0.31.22: at rest it faces the field, not the castle
				var fl := cat.to_local(Vector3(0.0, 0.0, 0.0))
				turret.rotation.y = atan2(fl.x, fl.z)
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
	if u.up and u.cls in ["rogue", "ranger", "mage"]:
		return {"rogue":"assassin", "ranger":"sniper", "mage":"archmage"}[u.cls]
	return u.cls

# ---------- Meshy characters (0.31.52, Kevin: a new Assassin model from Meshy) ----------
# A Meshy-generated, Meshy-rigged character stands in for a KayKit one. Its bones are renamed to the KayKit names (and
# hand slots added) so weapons, hats and the rest of the view find what they expect; its animations are the game's
# KayKit animations baked onto its own skeleton by tools/retarget_meshy.gd (anims_<library>.res, same names), and
# rig.json carries the fit scale and the hand-slot rests the tool worked out.
const MESHY := {"assassin": "res://assets/meshy/assassin/", "archmage": "res://assets/meshy/archmage/"}
const MESHY_RENAME := {"Hips":"hips", "Spine02":"spine", "Spine":"chest", "Head":"head",
	"LeftArm":"upperarm.l", "LeftForeArm":"lowerarm.l", "LeftHand":"wrist.l",
	"RightArm":"upperarm.r", "RightForeArm":"lowerarm.r", "RightHand":"wrist.r",
	"LeftUpLeg":"upperleg.l", "LeftLeg":"lowerleg.l", "LeftFoot":"foot.l", "LeftToeBase":"toes.l",
	"RightUpLeg":"upperleg.r", "RightLeg":"lowerleg.r", "RightFoot":"foot.r", "RightToeBase":"toes.r"}
static var _meshy_libs := {}
static var _meshy_rig := {}

static func meshy_rig(name: String) -> Dictionary:
	if not _meshy_rig.has(name):
		var f := FileAccess.open(str(MESHY[name]) + "rig.json", FileAccess.READ)
		_meshy_rig[name] = JSON.parse_string(f.get_as_text()) if f != null else {}
	return _meshy_rig[name]

static func _xf(a: Array) -> Transform3D:
	return Transform3D(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8]), Vector3(a[9], a[10], a[11]))

static func meshy_body(name: String) -> Dictionary:
	var packed := Stage.scene(str(MESHY[name]) + "rigged.glb")
	if packed == null:
		return {}
	var body: Node3D = packed.instantiate()
	for ap in body.find_children("*", "AnimationPlayer", true, false):
		ap.free()                                   # Meshy's own sample player
	var sk: Skeleton3D = body.find_child("Skeleton3D", true, false)
	for i in sk.get_bone_count():
		if MESHY_RENAME.has(sk.get_bone_name(i)):
			sk.set_bone_name(i, MESHY_RENAME[sk.get_bone_name(i)])
	var skins: Array = []
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var skin: Skin = (mi as MeshInstance3D).skin
		if skin != null:
			skin = skin.duplicate()                               # per body: we rename and rescale it
			(mi as MeshInstance3D).skin = skin
			skins.append(skin)
			for b in skin.get_bind_count():                       # the skin binds bones by name: rename them too
				if MESHY_RENAME.has(str(skin.get_bind_name(b))):
					skin.set_bind_name(b, MESHY_RENAME[str(skin.get_bind_name(b))])
	var rig: Dictionary = meshy_rig(name)
	for hand in ["r", "l"]:
		if rig.has("slot_" + hand) and sk.find_bone("handslot." + hand) < 0:
			var bi := sk.get_bone_count()
			sk.add_bone("handslot." + hand)
			sk.set_bone_parent(bi, sk.find_bone("wrist." + hand))
			sk.set_bone_rest(bi, _xf(rig["slot_" + hand]))
	sk.reset_bone_poses()
	# 0.31.53: put the rig in metres at scale 1 (Meshy rigs are centimetres under a 0.01 Armature; with the fit to the
	# KayKit height on top) -- the ragdoll's physics bodies can't live under a scaled skeleton. Every bone rest's offset
	# and every skin bind is scaled by the same factor, then the nodes' scales are reset: the mesh draws exactly as before.
	var a := float(rig.get("fit", 1.0))
	var n: Node = sk
	while n != null and n != body:
		if n is Node3D:
			a *= (n as Node3D).scale.x
			(n as Node3D).scale = Vector3.ONE
		n = n.get_parent()
	for i in sk.get_bone_count():
		var r := sk.get_bone_rest(i)
		sk.set_bone_rest(i, Transform3D(r.basis, r.origin * a))
	var S := Transform3D(Basis.from_scale(Vector3.ONE * a), Vector3.ZERO)
	for skin in skins:
		for b in (skin as Skin).get_bind_count():
			(skin as Skin).set_bind_pose(b, S * (skin as Skin).get_bind_pose(b))
	sk.reset_bone_poses()
	body.set_meta("meshy", name)
	return {"body":body, "skeleton":sk, "chain":1.0}

static func meshy_libraries(name: String) -> Dictionary:
	if not _meshy_libs.has(name):
		var libs := {}
		for key in ["g", "m", "r", "mb", "ma", "t"]:
			var path := str(MESHY[name]) + "anims_%s.res" % key
			if ResourceLoader.exists(path):
				libs[key] = load(path)
		_meshy_libs[name] = libs
	return _meshy_libs[name]

static func make_body(cls: String, cosmetic: Dictionary = {}) -> Dictionary:
	var look: Dictionary = (LOOKS.get(cls, LOOKS.villager) as Dictionary).duplicate()
	for hand in ["r", "l"]:
		if cosmetic.has(hand):
			look[hand] = cosmetic[hand]
	if str(look.model) == "Knight" and str(look.l) == "":
		look.l = "bits/shield_B"            # 0.31.41 (Kevin): a Knight (and a Crusader) always carries a shield
	var meshy := str(look.model).begins_with("meshy:")
	var body: Node3D
	var skeleton: Skeleton3D
	var chain := 1.0
	if meshy:
		var mb := meshy_body(str(look.model).substr(6))
		if mb.is_empty():
			return {}
		body = mb.body
		skeleton = mb.skeleton
		chain = float(mb.chain)
	else:
		var packed := Stage.scene("res://assets/kaykit/heroes/%s.glb" % look.model)
		if packed == null:
			return {}
		body = packed.instantiate()
		skeleton = body.find_child("Skeleton3D", true, false)
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
				_fit_weapon(model, file, str(look.model), hand)
				if meshy:
					var holder := Node3D.new()         # undo the rig's centimetre scale: weapons keep their size
					holder.scale = Vector3.ONE / chain
					holder.add_child(model)
					slot.add_child(holder)
				else:
					slot.add_child(model)
	var player := AnimationPlayer.new()
	body.add_child(player)
	player.root_node = NodePath("..")
	var libs: Dictionary = meshy_libraries(str(look.model).substr(6)) if meshy else libraries()
	for key in libs:
		player.add_animation_library(key, libs[key])
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _cast_static else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	if not cosmetic.has("tint") and look.has("tint"):
		cosmetic = cosmetic.duplicate()
		cosmetic["tint"] = look.tint
	if cosmetic.has("tint") and not meshy:                   # (a Meshy model is painted already)
		_apply_tint(body, str(look.model), Color(str(cosmetic.tint)))
	return {"body":body, "player":player}

# 0.31.43 (Kevin: weapons upside down / wrongly sized -- "staffs shouldn't be super short"). Measured: the Bits pack uses
# the SAME convention and scale as the Adventurers weapons (grip at the origin, business end along +Y: sword_A 1.77 m
# vs sword_1handed 1.78, staff_A 2.15 vs staff 2.15), so the old flat 0.55 on every Bits model made them all small --
# a staff came out 1.2 m. Bits models now keep their size, with a few of the giants brought down to the Adventurers'
# two-handers (sword_E 3.25 -> 2.4; spears, the big bows, staff_D, the halberd), and shields a little larger than life
# so a Knight's is obvious. Bows: the Adventurers bow lies along Z and wants a half turn; the Bits bows lie along X and
# want a quarter turn the same way round.
const WEAPON_SCALE := {"bits/sword_E":0.75, "bits/spear_A":0.8, "bits/spear_B":0.8, "bits/bow_C_withString":0.75, "bits/staff_D":0.85,
	"bits/halberd":0.85, "bits/shield_D":0.78, "bits/shield_C":0.85, "bits/shield_B":0.9, "bits/shield_A":1.0, "bits/sword_F":0.9, "bits/hammer_D":0.9}

# 0.31.44 (Kevin's screenshots): crossbows stood up like bows -- they lie forward (a quarter turn about X); shields sat
# on the hand so the fist poked through the face -- they move out along the slot's Z so the hand is behind the board;
# the clawed knuckles faced backwards (half turn); the single-bladed cleaver's edge pointed up in the two-handed grip
# (half turn); the Twin Axes were two axes in a two-handed grip (now one double-bitted axe, in economy.gd).
const WEAPON_ROT := {"bits/fistweapon_C_left":Vector3(0, 180, 0), "bits/fistweapon_C_right":Vector3(0, 180, 0)}
# 0.31.46 (side-view renders): in the Knight's one-handed idle the hand holds the weapon's long axis horizontal, so a
# halberd lay flat; a quarter turn about Z stands it upright, head up. The Rogue's idle does the same to the scythe
# (blade up, grim-reaper style). Crossbows lie forward with a quarter turn about X -- opposite signs for the two hands
# (0.31.45's right-hand crossbows pointed backwards).
# 0.31.47 (Kevin: back the 90 degrees, and the blade turned 180): the hold he called "right way but backwards" in
# 0.31.45 -- lying along the arm, axe blade / scythe blade hanging down -- but with the head forward: a half roll about
# the weapon's own long axis instead of the half turn about Z (which also swung the head behind him).
const WEAPON_ROT_FOR := {"Knight":{"bits/halberd":Vector3(0, 180, 0)}, "Rogue_Hooded":{"bits/scythe":Vector3(0, 180, 0)}, "Rogue":{"bits/scythe":Vector3(0, 180, 0)}}

# 0.31.48 (Kevin: turn these blades 180): the one-handed axe (Worker, Axe & Ale, Axe & Buckler -- its edge faced back
# in the chop), the Great Cleaver and the Oathkeeper: a half roll about the weapon's own long axis.
const WEAPON_ROLL := {"axe_1handed":180.0, "bits/axe_D":180.0, "bits/sword_G":180.0}

static func _fit_weapon(model: Node3D, file: String, body_model := "", hand := "r") -> void:
	model.scale = Vector3.ONE * float(WEAPON_SCALE.get(file, 1.0))
	if file.contains("crossbow"):
		model.rotation.x = deg_to_rad(-90.0 if hand == "r" else 90.0)
	elif file.contains("bow"):
		model.rotation.y = PI * 0.5 if file.begins_with("bits/") else PI
	if WEAPON_ROT.has(file):
		var r: Vector3 = WEAPON_ROT[file]
		model.rotation = Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z))
	var per: Dictionary = WEAPON_ROT_FOR.get(body_model, {})
	if per.has(file):
		var pr: Vector3 = per[file]
		model.rotation = Vector3(deg_to_rad(pr.x), deg_to_rad(pr.y), deg_to_rad(pr.z))
	if WEAPON_ROLL.has(file):
		model.rotate_object_local(Vector3.UP, deg_to_rad(float(WEAPON_ROLL[file])))
	if file.contains("shield"):
		model.position = Vector3(0.0, 0.0, 0.14 if file.begins_with("bits/") else 0.15)

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
	# 0.31.38: an upgraded class wears its own cosmetics (the Crusader's, the Berserker's...), not the base class's
	var cosmetic: Dictionary = player_looks.get(Eco.cosmetic_class(str(u.cls), bool(u.up)), {}) if u.id == player_id else {}
	var look_key := "%s:%s:%s" % [u.cls, u.up, str(cosmetic)]
	if not a.is_empty() and a.look == look_key:
		return a
	if not a.is_empty() and u.state == "dead" and a.get("body") != null:
		return a                                    # 0.31.20: the body stays as it fell until he respawns
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
	_sync_bombs(dt)
	_sync_meteor_fx(dt)
	_sync_chips(dt)
	_sync_shocks()
	_kick_debris()
	_sync_launchers(dt)
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
		if u.state == "fly":
			target.y += sim.flight_height(u)             # 0.31.28: off the launcher, high over the field
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
		_sync_vanish(a, u)
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
			if a.get("rag") == null:
				_play(a, "g/Death_A", 1.0, 99.0)       # far off (no ragdoll): the old fall
		return
	if a.dead:
		a.dead = false
		_ragdoll_end(a)
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
			if not a.is_empty():
				var pa: Array = e.get("push", [0.0, 1.6, 0.0])
				var push := Vector3(float(pa[0]), float(pa[1]), float(pa[2])) if pa.size() >= 3 else Vector3(0.0, 1.6, 0.0)
				_drop_weapons(a, push)
				_ragdoll(a, push)
		"spawn":
			if not a.is_empty():
				a.root.position = Vector3(sim.by_id[e.id].pos.x, 0, sim.by_id[e.id].pos.y)
				ring_at(a.root.position, TEAM_COLORS[sim.by_id[e.id].team], 1.6, 0.6)
		"class":
			if not a.is_empty():
				ring_at(a.root.position, GOLD, 3.0 if e.up else 2.0, 0.8)
				for i in (10 if e.up else 5):
					spark(a.root.position + Vector3(randf_range(-0.6, 0.6), 0.4 + randf()*1.4, randf_range(-0.6, 0.6)), GOLD)
		"hat_equip_up":
			if not a.is_empty():
				ring_at(a.root.position, GOLD, 3.0, 0.8)
				for i in 10:
					spark(a.root.position + Vector3(randf_range(-0.6, 0.6), 0.4 + randf() * 1.4, randf_range(-0.6, 0.6)), GOLD)
		"launch":
			for f in e.get("flown", []):
				if sim.by_id.has(str(f.id)):
					sim.by_id[str(f.id)]["fly"] = {"from":f.from, "to":f.to, "t0":float(e.t0), "dur":float(f.dur)}
			var lp := Vector3(e.pos.x, Sim.height_at(e.pos) + 0.2, e.pos.y)
			ring_at(lp, Color(1.0, 0.85, 0.4), Sim.LAUNCH_PAD_R * 2.2, 0.6)
			for i in 18:
				spark(lp + Vector3(randf_range(-1.5, 1.5), randf() * 1.5, randf_range(-1.5, 1.5)), Color(0.85, 0.75, 0.55))
			shake(0.35)
		"land":
			var ld := Vector3(e.pos.x, Sim.height_at(e.pos) + 0.1, e.pos.y)
			ring_at(ld, Color(0.85, 0.78, 0.62), 2.2, 0.5)
			for i in 8:
				spark(ld + Vector3(randf_range(-0.6, 0.6), randf() * 0.5, randf_range(-0.6, 0.6)), Color(0.8, 0.72, 0.58))
		"vanish":
			if sim.by_id.has(str(e.id)):
				sim.by_id[str(e.id)]["vanish_until"] = float(e.until)
			if not a.is_empty():
				for i in 10:
					spark((a.root as Node3D).position + Vector3(randf_range(-0.5, 0.5), 0.3 + randf() * 1.4, randf_range(-0.5, 0.5)), Color(0.35, 0.3, 0.45))
		"unvanish":
			if sim.by_id.has(str(e.id)):
				sim.by_id[str(e.id)]["vanish_until"] = sim.time
		"meteor_warn":
			_meteor_warn(e.pos, float(e.delay), int(e.team))
		"meteor_hit":
			_recent_blasts.append([e.pos, _time])
			_launch_items(e.pos, Sim.METEOR_R + 1.5, 0.85)
			_meteor_hit(e.pos, float(e.burn))
		"pierce_hit":
			var ph := Vector3(e.pos.x, Sim.height_at(e.pos) + 1.1, e.pos.y)
			for i in 6:
				spark(ph, Color(0.85, 0.95, 1.0))
		"node_fell":                                         # 0.31.33: a burst of chips (away from a blast if one did it)
			var nfp := Vector3(e.pos.x, Sim.height_at(e.pos), e.pos.y)
			var bl := float(e.get("blast", 0.0))
			var away := Vector2.ZERO
			if bl > 0.0:
				away = ((e.pos as Vector2) - (e.get("from", e.pos) as Vector2)).normalized()
			_chip_burst(nfp, str(e.kind) == "wood", 26 if bl > 0.0 else 18, 1.3 if bl > 0.0 else 1.0, away)
		"gather":
			var gn: int = int(e.get("node", -1))
			if gn >= 0 and gn < sim.nodes.size():
				var gp: Vector2 = sim.nodes[gn].p
				_chip_burst(Vector3(gp.x, Sim.height_at(gp), gp.y), str(e.get("kind", "wood")) == "wood", 4, 0.6)
		"bomb_boom":
			_recent_blasts.append([e.pos, _time])
			_launch_items(e.pos, Sim.BOMB_R + 2.0, 1.0)
			bomb_blast(e.pos)
			water_blast(e.pos, 1.0)
			_blast_bodies(e.pos, Sim.BOMB_R + 2.5, 7.0)
		"bomb_spawn":
			var bs := Vector3(e.pos.x, Sim.height_at(e.pos) + 0.1, e.pos.y)
			ring_at(bs, GOLD, 1.4, 0.7)
			for i in 6:
				spark(bs + Vector3(randf_range(-0.4, 0.4), 0.3 + randf() * 0.8, randf_range(-0.4, 0.4)), GOLD)
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
					(best.turret as Node3D).rotation.y = atan2(local.x, local.z)      # 0.31.22: the model throws along +z
			var stone := _place(HEX + "projectile_catapult.gltf", Vector3(e.from.x, 4.2, e.from.y), 0.0, 3.2)
			if stone != null:
				_fx.append({"node":stone, "at":_time, "life":float(e.flight), "kind":"shell",
					"p0":Vector3(e.from.x, 4.2, e.from.y), "p1":Vector3(e.to.x, Sim.height_at(e.to) + 0.3, e.to.y)})
		"catapult_hit":
			_pack_explosion("light", Vector3(e.pos.x, Sim.height_at(e.pos) + 0.15, e.pos.y), 2.0)      # 0.31.57
			_recent_blasts.append([e.pos, _time])                    # 0.31.34: the logs and rocks it breaks fly high
			_launch_items(e.pos, Sim.CATAPULT_AOE + 1.5, 0.7)        # ...and those already lying round it go up again
			water_blast(e.pos, 0.6)                                  # 0.31.21: a stone in the river makes waves too
			_blast_bodies(e.pos, Sim.CATAPULT_AOE + 1.5, 4.5)       # ...and throws the dead and loose weapons
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
	if kind == "pierce":
		# the Sniper's shot (0.31.32): a long arrow with a pale glowing streak behind it
		var pr := Node3D.new()
		var pk := Stage.scene("res://assets/kaykit/weapons/arrow_bow.gltf")
		if pk != null:
			var ar: Node3D = pk.instantiate()
			ar.scale = Vector3(1.6, 1.6, 2.0)
			pr.add_child(ar)
		var streak := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.06
		cm.bottom_radius = 0.0
		cm.height = 3.2
		streak.mesh = cm
		streak.material_override = _fx_mat(Color(0.85, 0.95, 1.0))
		streak.rotation.x = PI * 0.5
		streak.position.z = -1.7
		pr.add_child(streak)
		add_child(pr)
		return pr
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
	if not me.is_empty() and me.state == "dead" and not a.is_empty():
		# 0.31.22 (Kevin): the camera stays with your body through the countdown (it cut to your spawn) -- with the
		# ragdoll's hips if it has one, so it follows where you were thrown
		var rg = a.get("rag")
		focus = a.root.position
		if rg != null and is_instance_valid(rg.sim):
			for pb in (rg.sim as Node).get_children():
				if pb is PhysicalBone3D and str((pb as PhysicalBone3D).bone_name) == "hips":
					focus = (pb as Node3D).global_position
					focus.y = 0.0
					break
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
			# 0.31.33 (Kevin): a new log or rock pops up into the air and tumbles down, like confetti -- higher if a
			# blast threw it
			var blasted := false
			for b in _recent_blasts:
				if _time - float(b[1]) < 0.6 and (b[0] as Vector2).distance_to(p) < 12.0:
					blasted = true
			# (0.31.35: a piece the sim has in the air follows the sim's flight below; this pop is for a chopped tree or
			# a mined boulder, or an online client that doesn't know the flight)
			nd.set_meta("pop_vz", Sim.BLAST_VZ if blasted else randf_range(4.5, 6.5))
			nd.set_meta("pop_h", 0.05)
			nd.set_meta("pop_ax", Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)).normalized())
			nd.set_meta("pop_spin", randf_range(7.0, 13.0) * (1.6 if blasted else 1.0))
			nd.set_meta("pop_rot", 0.0)
		var air_end := float(it.get("air_end", -1.0))
		if air_end > sim.time:
			# 0.31.35: flying away from a blast -- the same arc the sim gives it (straight out, up and down once)
			var avz := float(it.get("air_vz", Sim.BLAST_VZ))
			var tt: float = sim.time - (air_end - 2.0 * avz / Sim.ITEM_G)
			target.y += maxf(0.0, avz * tt - 0.5 * Sim.ITEM_G * tt * tt)
			if nd.has_meta("pop_vz"):
				nd.remove_meta("pop_vz")
			if not nd.has_meta("air_ax"):
				nd.set_meta("air_ax", Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)).normalized())
				nd.set_meta("air_rot", 0.0)
			nd.set_meta("air_rot", float(nd.get_meta("air_rot")) + 14.0 * dt)
			nd.position = target                          # no easing in flight: it would lag the arc
		elif nd.has_meta("pop_vz"):
			var vz: float = nd.get_meta("pop_vz")
			var ph: float = nd.get_meta("pop_h")
			vz -= ITEM_POP_G * dt
			ph += vz * dt
			nd.set_meta("pop_rot", float(nd.get_meta("pop_rot")) + float(nd.get_meta("pop_spin")) * dt)
			if ph <= 0.0:
				if vz < -3.0:
					vz = -vz * 0.28                          # one small bounce
					ph = 0.0
				else:
					nd.remove_meta("pop_vz")
					ph = 0.0
			if nd.has_meta("pop_vz"):
				nd.set_meta("pop_vz", vz)
				nd.set_meta("pop_h", ph)
			target.y += ph
			nd.position = Vector3(nd.position.x, target.y, nd.position.z).lerp(target, minf(1.0, dt * 16.0))
		else:
			nd.position = nd.position.lerp(target, minf(1.0, dt * 16.0))
		if is_log:
			var ang := float(it.ang)
			var ax := Vector3(cos(ang), 0.0, sin(ang))
			nd.basis = Basis(ax, float(it.roll)) * Basis(Vector3.UP, -ang) * Basis(Vector3(0, 0, 1), PI * 0.5)
		else:
			var rax := float(it.rax)
			nd.basis = Basis(Vector3(sin(rax), 0.0, -cos(rax)), float(it.roll))
		if nd.has_meta("pop_vz"):
			nd.basis = Basis(nd.get_meta("pop_ax"), float(nd.get_meta("pop_rot"))) * nd.basis      # tumbling in the air
		elif air_end > sim.time and nd.has_meta("air_ax"):
			nd.basis = Basis(nd.get_meta("air_ax"), float(nd.get_meta("air_rot"))) * nd.basis
		elif nd.has_meta("air_ax"):
			nd.remove_meta("air_ax")
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


# ---------- cloth capes (0.31.17, Kevin: "realistic cloth physics for the capes"; 0.31.18: "floating capes ... very
# jittery") ----------
# The Knight, Mage, Ranger and both Rogues wear a cape (a skinned 56-vertex mesh in the KayKit models, rigid on the
# torso). Near the camera it hangs from a small spring grid -- CAPE_COLS x CAPE_ROWS points, the top row pinned across
# the shoulders to the chest bone, the rest falling under gravity with a little wind, held by stretch and bend links,
# kept behind the back, outside the torso and above the ground -- stepped at a fixed 30 Hz and eased onto the screen.
# The cape mesh itself is bent by the grid in its vertex shader, so there is no separate cloth object to be left
# behind (0.31.17's floating capes) and no mesh rebuilt each frame (its cost on phones).
const CAPE_COLS := 3
const CAPE_ROWS := 4
const CAPE_NEAR := 32.0          # ground distance from the camera
const CAPE_GRAVITY := 7.5
const CAPE_DAMP := 0.9
const CAPE_ITERS := 2
const CAPE_STEP := 1.0 / 30.0
const CAPE_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness = 0.5;
uniform vec3 offs[12];
void vertex() {
	// model-space position -> place on the 3 x 4 grid (shoulders at y 1.2, hem at 0.12, 0.94 m across)
	float u = clamp((VERTEX.x + 0.47) / 0.94, 0.0, 1.0) * 2.0;
	float v = clamp((1.2 - VERTEX.y) / 1.08, 0.0, 1.0) * 3.0;
	int c0 = int(min(floor(u), 1.0));
	int r0 = int(min(floor(v), 2.0));
	float fu = u - float(c0);
	float fv = v - float(r0);
	vec3 a = mix(offs[r0 * 3 + c0], offs[r0 * 3 + c0 + 1], fu);
	vec3 b = mix(offs[(r0 + 1) * 3 + c0], offs[(r0 + 1) * 3 + c0 + 1], fu);
	VERTEX += mix(a, b, fv);
}
void fragment() {
	vec4 t = texture(albedo_tex, UV) * albedo;
	ALBEDO = t.rgb;
	ROUGHNESS = roughness;
}
"""
static var _cape_shader: Shader = null
static var cape_usec := 0           # time spent in cloth this session (diag/tests)
static var cape_active := 0

func _cape_setup(a: Dictionary) -> void:
	a["cape"] = null
	var body: Node3D = a.body
	var orig: MeshInstance3D = null
	for c in body.find_children("*_Cape", "MeshInstance3D", true, false):
		orig = c
		break
	var skel: Skeleton3D = body.find_child("Skeleton3D", true, false)
	if orig == null or skel == null or skel.find_bone("chest") < 0:
		return
	if _cape_shader == null:
		_cape_shader = Shader.new()
		_cape_shader.code = CAPE_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = _cape_shader
	var src = orig.get_active_material(0)
	if src is BaseMaterial3D:
		sm.set_shader_parameter("albedo_tex", (src as BaseMaterial3D).albedo_texture)
		sm.set_shader_parameter("albedo", (src as BaseMaterial3D).albedo_color)
		sm.set_shader_parameter("roughness", (src as BaseMaterial3D).roughness)
	var zero := PackedVector3Array()
	zero.resize(CAPE_COLS * CAPE_ROWS)
	sm.set_shader_parameter("offs", zero)
	orig.material_override = sm
	var rest := PackedVector3Array()
	for r in CAPE_ROWS:
		var fv := float(r) / float(CAPE_ROWS - 1)
		for c2 in CAPE_COLS:
			var fu := float(c2) / float(CAPE_COLS - 1)
			var half := lerpf(0.40, 0.47, fv)
			rest.append(Vector3(lerpf(-half, half, fu), lerpf(1.2, 0.12, fv), lerpf(-0.08, -0.36, fv)))
	var chest := skel.find_bone("chest")
	a["cape"] = {"skel":skel, "chest":chest, "b0i":skel.get_bone_global_rest(chest).affine_inverse(), "rest":rest,
		"pos":PackedVector3Array(), "prev":PackedVector3Array(), "shown":zero.duplicate(), "mat":sm, "on":false, "acc":0.0}

func _cape_step(a: Dictionary, dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_cape_step_inner(a, dt)
	cape_usec += Time.get_ticks_usec() - t0

func _cape_step_inner(a: Dictionary, dt: float) -> void:
	var cp: Dictionary = a.cape
	var skel: Skeleton3D = cp.skel
	if not is_instance_valid(skel):
		a["cape"] = null
		return
	var ap: Vector3 = (a.root as Node3D).global_position
	var cpos: Vector3 = camera.global_position if is_instance_valid(camera) else ap
	var near := Vector2(ap.x - cpos.x, ap.z - cpos.z).length() < CAPE_NEAR and skel.is_visible_in_tree()
	var n := CAPE_COLS * CAPE_ROWS
	if not near:
		if bool(cp.on):                                  # back to the plain cape
			cp.on = false
			var z := PackedVector3Array()
			z.resize(n)
			cp.shown = z
			(cp.mat as ShaderMaterial).set_shader_parameter("offs", z)
		return
	var model: Transform3D = skel.global_transform
	var rig_m: Transform3D = skel.get_bone_global_pose(int(cp.chest)) * (cp.b0i as Transform3D)   # model space, rigid on the chest
	var rig: Transform3D = model * rig_m
	var rest: PackedVector3Array = cp.rest
	var pos: PackedVector3Array = cp.pos
	var prev: PackedVector3Array = cp.prev
	if not bool(cp.on) or pos.size() != n:
		pos.resize(n)
		prev.resize(n)
		for i in n:
			pos[i] = rig * rest[i]
			prev[i] = pos[i]
		cp.on = true
		cp.acc = 0.0
	# fixed 30 Hz steps (frame times vary on phones; a variable step made it shiver)
	cp.acc = minf(float(cp.acc) + dt, CAPE_STEP * 3.0)
	var h2 := CAPE_STEP * CAPE_STEP
	var inv := rig.affine_inverse()
	var ground := ap.y + 0.03
	var wind := Vector3(sin(_time * 1.3 + float(int(cp.chest) + rest.size())) * 0.8, 0.0, cos(_time * 0.9) * 0.5)
	while float(cp.acc) >= CAPE_STEP:
		cp.acc = float(cp.acc) - CAPE_STEP
		for i in n:
			if i < CAPE_COLS:
				prev[i] = pos[i]
				pos[i] = rig * rest[i]                         # pinned across the shoulders
				continue
			var p: Vector3 = pos[i]
			var v: Vector3 = (p - prev[i]) * CAPE_DAMP
			prev[i] = p
			pos[i] = p + v + (Vector3(0.0, -CAPE_GRAVITY, 0.0) + wind) * h2
		for it in CAPE_ITERS:
			for r in CAPE_ROWS:
				for c in CAPE_COLS:
					var i := r * CAPE_COLS + c
					if c + 1 < CAPE_COLS:
						_cape_link(pos, rest, i, i + 1, r == 0)
					if r + 1 < CAPE_ROWS:
						_cape_link(pos, rest, i, i + CAPE_COLS, r == 0)
					if r + 2 < CAPE_ROWS:
						_cape_link(pos, rest, i, i + 2 * CAPE_COLS, r == 0)
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
	# the bend each point makes, in the cape's model space, eased onto the screen
	var inv_model := model.affine_inverse()
	var shown: PackedVector3Array = cp.shown
	var k := 1.0 - exp(-dt * 30.0)
	for i in n:
		var off: Vector3 = inv_model * pos[i] - rig_m * rest[i]
		shown[i] = shown[i].lerp(off, k)
	cp.shown = shown
	(cp.mat as ShaderMaterial).set_shader_parameter("offs", shown)
	cape_active += 1

func _cape_link(pos: PackedVector3Array, rest: PackedVector3Array, i: int, j: int, pin_i: bool) -> void:
	var d: Vector3 = pos[j] - pos[i]
	var l := d.length()
	if l < 0.0001:
		return
	var want: float = rest[i].distance_to(rest[j])
	var corr := d * ((l - want) / l)
	if pin_i:
		pos[j] -= corr                                     # the shoulder end doesn't move
	else:
		pos[i] += corr * 0.5
		pos[j] -= corr * 0.5


# ---------- the bomb (0.31.19) ----------
# A round iron bomb with a band and a fuse, sitting by its workshop, held up over the carrier's head, spinning through
# the air when thrown; once lit the fuse spits sparks and the bomb throbs red as it runs down. The blast: a fireball
# flash, a ring out to the blast radius, sparks, smoke rising, a scorch on the ground, and the camera shakes.
var bomb_nodes: Array = [null, null]
var _booms: Array = []

func _make_bomb() -> Node3D:
	var n := Node3D.new()
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color("#2a2c31")
	iron.metallic = 0.55
	iron.roughness = 0.38
	iron.emission_enabled = true
	iron.emission = Color(1.0, 0.18, 0.08)
	iron.emission_energy_multiplier = 0.0
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.36
	sm.height = 0.72
	ball.mesh = sm
	ball.material_override = iron
	n.add_child(ball)
	var band := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.365
	bm.bottom_radius = 0.365
	bm.height = 0.08
	band.mesh = bm
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color("#b98a3e")
	brass.metallic = 0.7
	brass.roughness = 0.35
	band.material_override = brass
	n.add_child(band)
	var cap := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.1
	cm.bottom_radius = 0.12
	cm.height = 0.12
	cap.mesh = cm
	cap.material_override = brass
	cap.position = Vector3(0.0, 0.36, 0.0)
	n.add_child(cap)
	var fuse := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.022
	fm.bottom_radius = 0.026
	fm.height = 0.26
	fuse.mesh = fm
	var rope := StandardMaterial3D.new()
	rope.albedo_color = Color("#8a6a44")
	fuse.material_override = rope
	fuse.position = Vector3(0.05, 0.52, 0.0)
	fuse.rotation.z = -0.4
	n.add_child(fuse)
	var tip := MeshInstance3D.new()
	var tm := SphereMesh.new()
	tm.radius = 0.07
	tm.height = 0.14
	tip.mesh = tm
	tip.material_override = _fx_mat(Color(1.0, 0.75, 0.25))
	tip.position = Vector3(0.1, 0.64, 0.0)
	tip.visible = false
	n.add_child(tip)
	n.set_meta("iron", iron)
	n.set_meta("tip", tip)
	add_child(n)
	return n

func _sync_bombs(dt: float) -> void:
	for t in 2:
		var b: Dictionary = sim.bombs[t] if t < sim.bombs.size() else {}
		var n: Node3D = bomb_nodes[t]
		if b.is_empty():
			if n != null:
				n.visible = false
			continue
		if n == null:
			n = _make_bomb()
			bomb_nodes[t] = n
		n.visible = true
		var target: Vector3
		if str(b.state) == "carried" and actors.has(str(b.carrier)):
			var ca: Dictionary = actors[str(b.carrier)]
			target = (ca.root as Node3D).global_position + Vector3(0.0, 2.15, 0.0)      # held up over his head
		else:
			target = Vector3(b.p.x, Sim.height_at(b.p) + float(b.h) + 0.34, b.p.y)
		n.position = target if n.position.distance_to(target) > 4.0 else n.position.lerp(target, 1.0 - exp(-dt * 20.0))
		if str(b.state) == "flying":
			n.rotation.x += dt * 9.0
			n.rotation.z += dt * 6.0
		elif str(b.state) != "carried":
			n.rotation = n.rotation.lerp(Vector3.ZERO, 1.0 - exp(-dt * 6.0))
		var lit := float(b.lit_at) >= 0.0
		var tip: MeshInstance3D = n.get_meta("tip")
		tip.visible = lit
		var iron: StandardMaterial3D = n.get_meta("iron")
		if lit:
			var left := maxf(0.0, Sim.BOMB_FUSE - (sim.time - float(b.lit_at)))
			var rate := lerpf(16.0, 4.0, left / Sim.BOMB_FUSE)                # throbs faster as it runs down
			iron.emission_energy_multiplier = (0.5 + 0.5 * sin(_time * rate * 3.0)) * lerpf(2.2, 0.4, left / Sim.BOMB_FUSE)
			tip.scale = Vector3.ONE * (0.8 + 0.6 * randf())
			if randf() < dt * 30.0:
				spark(n.position + Vector3(0.1, 0.66, 0.0), Color(1.0, 0.7 + randf() * 0.3, 0.2))
		else:
			iron.emission_energy_multiplier = 0.0
	# the blasts going on
	for i in range(_booms.size() - 1, -1, -1):
		var bo: Dictionary = _booms[i]
		var k := (_time - float(bo.t0)) / float(bo.life)
		var node: Node3D = bo.node
		if k >= 1.0 or not is_instance_valid(node):
			if is_instance_valid(node):
				node.queue_free()
			_booms.remove_at(i)
			continue
		match str(bo.kind):
			"flash":
				node.scale = Vector3.ONE * lerpf(0.5, Sim.BOMB_R * 0.95, sqrt(k))
				((node as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a = 0.85 * (1.0 - k)
			"smoke":
				node.position += (bo.vel as Vector3) * dt
				node.scale = Vector3.ONE * lerpf(0.6, 2.2, k)
				((node as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a = 0.55 * (1.0 - k)
			"scorch":
				((node as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a = 0.55 * (1.0 - k * k)

func _blast_bodies(at2: Vector2, radius: float, speed: float) -> void:
	# 0.31.21: the dead and the loose weapons lying round a blast are thrown by it
	var at := Vector3(at2.x, Sim.height_at(at2), at2.y)
	for a in _ragdolls:
		var rg = a.get("rag")
		if rg == null or not is_instance_valid(rg.sim):
			continue
		for pb in (rg.sim as Node).get_children():
			if not (pb is PhysicalBone3D):
				continue
			var d: Vector3 = (pb as Node3D).global_position - at
			var dist := Vector2(d.x, d.z).length()
			if dist > radius:
				continue
			var dir := Vector3(d.x, 0.0, d.z).normalized() if dist > 0.05 else Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).normalized()
			var f := speed * (1.0 - 0.6 * dist / radius)
			(pb as PhysicalBone3D).linear_velocity += dir * f + Vector3(0.0, f * 0.7, 0.0)
			(pb as PhysicalBone3D).angular_velocity += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * f
	for db in _debris:
		var rb = db.node
		if not is_instance_valid(rb):
			continue
		var d2: Vector3 = (rb as Node3D).global_position - at
		var dist2 := Vector2(d2.x, d2.z).length()
		if dist2 > radius:
			continue
		var dir2 := Vector3(d2.x, 0.0, d2.z).normalized() if dist2 > 0.05 else Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).normalized()
		var f2 := speed * 1.2 * (1.0 - 0.6 * dist2 / radius)
		(rb as RigidBody3D).sleeping = false
		(rb as RigidBody3D).linear_velocity += dir2 * f2 + Vector3(0.0, f2 * 0.8, 0.0)
		(rb as RigidBody3D).angular_velocity += Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))

func _kick_debris() -> void:
	# loose weapons are kicked along by whoever walks into them
	if _debris.is_empty():
		return
	for db in _debris:
		var rb = db.node
		if not is_instance_valid(rb):
			continue
		var wp: Vector3 = (rb as Node3D).global_position
		for a in actors.values():
			if a.get("dead", false) or a.get("rag") != null:
				continue
			var ap: Vector3 = (a.root as Node3D).global_position
			var d := Vector2(wp.x - ap.x, wp.z - ap.z)
			if d.length() > 0.62 or absf(wp.y - ap.y) > 1.2:
				continue
			var lp: Vector3 = a.get("kick_last", ap)
			var mv := Vector2(ap.x - lp.x, ap.z - lp.z)
			if mv.length() < 0.004:
				continue
			var dir := (d.normalized() * 0.5 + mv.normalized() * 0.5).normalized()
			(rb as RigidBody3D).sleeping = false
			(rb as RigidBody3D).linear_velocity = Vector3(dir.x * 3.2, 1.0, dir.y * 3.2)
			(rb as RigidBody3D).angular_velocity += Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
	for a in actors.values():
		a["kick_last"] = (a.root as Node3D).global_position

# ---------- the EffectBlocks explosions (0.31.57, Kevin) ----------
# The pack's heavy explosion (fireball, sparks, rolling smoke, burning debris with smoke trails) on the bomb and the
# meteor, its light one (a small pop, sparks, puffs) on catapult stones. Copies in assets/vfx/effectblocks without the
# pack's demo script and sound. Every emitter is switched to local coordinates so the node's scale sizes the whole
# effect; half the particles on low effects; freed when the longest emitter is done.
static var _fire_cool: ParticleProcessMaterial = null
const PACK_EXPLOSIONS := {"heavy": preload("res://assets/vfx/effectblocks/explosion_heavy.tscn"),
	"light": preload("res://assets/vfx/effectblocks/explosion_light.tscn")}

func _pack_explosion(kind: String, at: Vector3, size: float, own_smoke := false) -> void:
	var n: Node3D = (PACK_EXPLOSIONS[kind] as PackedScene).instantiate()
	if own_smoke and n.has_node("Smoke"):
		n.get_node("Smoke").free()                    # 0.31.59: our physical smoke replaces the pack's smoke
	if own_smoke and n.has_node("Fire"):
		# the pack's fireball cools to an opaque near-black ball; ours cools to a thin grey and fades, handing over to
		# the smoke cloud
		var fire := n.get_node("Fire") as GPUParticles3D
		if _fire_cool == null:
			_fire_cool = (fire.process_material as ParticleProcessMaterial).duplicate()
			var g := Gradient.new()
			g.offsets = PackedFloat32Array([0.0, 0.16, 0.3, 0.55])
			g.colors = PackedColorArray([Color(0.95, 0.5, 0.0, 1.0), Color(0.85, 0.27, 0.04, 1.0), Color(0.3, 0.26, 0.23, 0.5), Color(0.34, 0.33, 0.32, 0.0)])
			var gt := GradientTexture1D.new()
			gt.gradient = g
			_fire_cool.color_ramp = gt
		fire.process_material = _fire_cool
	n.position = at
	n.scale = Vector3.ONE * size
	add_child(n)
	var life := 0.5
	for gp in n.find_children("*", "GPUParticles3D", true, false):
		var p3 := gp as GPUParticles3D
		p3.local_coords = true
		if low_fx:
			p3.amount_ratio = 0.5
		life = maxf(life, p3.lifetime * 1.6)
		p3.restart()
	get_tree().create_timer(life + 0.5).timeout.connect(n.queue_free)

# ---------- physical smoke (0.31.59, Kevin: realistic, physics-based smoke that lingers after explosions) ----------
# A one-shot GPU particle cloud per blast: puffs (a generated, lumpy smoke texture) are thrown out of a sphere at the
# blast, slowed hard by air drag (damping), lifted by buoyancy and pushed by a steady breeze (both as gravity), and
# stirred by a turbulence noise field so the cloud boils and curls instead of moving in straight lines. Each puff swells
# as it rises, turns slowly, starts dark and fire-warm, then thins to a pale grey and fades -- the cloud lingers for
# 8-10 s. Depth-sorted, soft where it meets the ground (proximity fade), no shadows; 40 % of the puffs on low effects.
const SMOKE_TEX := preload("res://assets/vfx/smoke/smoke_puff.png")
const SMOKE_WIND := Vector3(0.45, 0.0, 0.18)
static var _smoke_draw: StandardMaterial3D = null

static func _smoke_draw_mat() -> StandardMaterial3D:
	if _smoke_draw == null:
		var m := StandardMaterial3D.new()
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = SMOKE_TEX
		m.proximity_fade_enabled = true
		m.proximity_fade_distance = 1.4
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_smoke_draw = m
	return _smoke_draw

func smoke_cloud(at: Vector3, size: float, amount: int, life: float) -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.1 * size
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 80.0
	pm.initial_velocity_min = 2.6 * size
	pm.initial_velocity_max = 6.5 * size
	pm.damping_min = 2.4 * size                       # air drag: the blast's push dies within a second or so
	pm.damping_max = 3.6 * size
	pm.gravity = Vector3(0.0, 0.55, 0.0) + SMOKE_WIND  # buoyancy up, the breeze sideways
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.8
	pm.turbulence_noise_scale = 3.2 * size
	pm.turbulence_noise_speed = Vector3(0.15, 0.3, 0.1)
	pm.turbulence_noise_speed_random = 0.3
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.16
	pm.lifetime_randomness = 0.35
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -14.0
	pm.angular_velocity_max = 14.0
	pm.scale_min = 2.0 * size
	pm.scale_max = 3.4 * size
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.35))
	sc.add_point(Vector2(0.2, 0.85))
	sc.add_point(Vector2(1.0, 1.45))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.04, 0.12, 0.45, 1.0])
	g.colors = PackedColorArray([Color(0.55, 0.32, 0.16, 0.0), Color(0.42, 0.28, 0.2, 0.92), Color(0.24, 0.23, 0.22, 0.9),
		Color(0.42, 0.41, 0.4, 0.62), Color(0.62, 0.62, 0.62, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	var gi := Gradient.new()                          # each puff a little lighter or darker than the next
	gi.colors = PackedColorArray([Color(0.82, 0.82, 0.82), Color(1.12, 1.1, 1.08)])
	var git := GradientTexture1D.new()
	git.gradient = gi
	pm.color_initial_ramp = git
	var p := GPUParticles3D.new()
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = _smoke_draw_mat()
	p.draw_pass_1 = q
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.85
	p.randomness = 0.4
	p.fixed_fps = 30
	p.interpolate = true
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-22, -4, -22) * size, Vector3(44, 34, 44) * size)
	if low_fx:
		p.amount_ratio = 0.4
	p.position = at
	add_child(p)
	p.restart()
	get_tree().create_timer(life * 1.4 + 1.0).timeout.connect(p.queue_free)

# ---------- shockwave (0.31.56, Kevin: the EffectBlocks pack's shockwave on the bomb and meteor blasts) ----------
# The pack's effect (assets/other/shockwave.tscn): one torus, inner 0.8 / outer 1.0, triangular section, growing from
# nothing to its full size over 0.74 s on an ease-in curve, drawn with its screen-distortion shader (in
# assets/vfx/effectblocks/shockwave.gdshader, adapted to bend round the ring's own centre; distortion 0.1, noise 0.273
# as in its material). Here it's a plain
# MeshInstance3D animated in _sync_shocks (one particle never needed a particle system), sized to each blast, and
# skipped on low effects (the screen copy it reads costs a little on phones).
const SHOCK_SHADER := preload("res://assets/vfx/effectblocks/shockwave.gdshader")
const SHOCK_LIFE := 0.74
static var _shock_mat: ShaderMaterial = null
static var _shock_mesh: TorusMesh = null
var _shocks: Array = []

func shockwave(at: Vector3, radius: float, delay := 0.0) -> void:
	if low_fx:
		return
	if _shock_mat == null:
		_shock_mat = ShaderMaterial.new()
		_shock_mat.shader = SHOCK_SHADER
		_shock_mat.set_shader_parameter("distortion_intensity", 0.1)
		_shock_mat.set_shader_parameter("noise_influence", 0.273)
		_shock_mesh = TorusMesh.new()
		_shock_mesh.inner_radius = 0.8
		_shock_mesh.outer_radius = 1.0
		_shock_mesh.rings = 40
		_shock_mesh.ring_segments = 3
	var mi := MeshInstance3D.new()
	mi.mesh = _shock_mesh
	mi.material_override = _shock_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	mi.scale = Vector3.ONE * 0.001
	mi.visible = false
	add_child(mi)
	_shocks.append({"node":mi, "t0":_time + delay, "r":radius})

func _sync_shocks() -> void:
	for i in range(_shocks.size() - 1, -1, -1):
		var sh: Dictionary = _shocks[i]
		var mi: MeshInstance3D = sh.node
		var t: float = (_time - float(sh.t0)) / SHOCK_LIFE
		if t >= 1.0 or not is_instance_valid(mi):
			if is_instance_valid(mi):
				mi.queue_free()
			_shocks.remove_at(i)
			continue
		if t < 0.0:
			continue
		mi.visible = true
		# the pack's scale curve: (0,0) leaving at slope 0.227, (1,1) arriving at 1.392 -- a cubic Hermite
		var c := (2.0*t*t*t - 3.0*t*t + 1.0) * 0.0 + (t*t*t - 2.0*t*t + t) * 0.227 + (-2.0*t*t*t + 3.0*t*t) * 1.0 + (t*t*t - t*t) * 1.392
		mi.scale = Vector3.ONE * maxf(0.001, float(sh.r) * c)
		mi.set_instance_shader_parameter("fade", 1.0 - t * t)

func bomb_blast(at2: Vector2) -> void:
	var at := Vector3(at2.x, Sim.height_at(at2) + 0.6, at2.y)
	shockwave(Vector3(at.x, at.y - 0.2, at.z), Sim.BOMB_R + 3.0)           # 0.31.56 (0.31.58: wider, with the bigger blast)
	_pack_explosion("heavy", Vector3(at.x, at.y - 0.4, at.z), 6.0, true)      # 0.31.57: the EffectBlocks heavy explosion (0.31.58: much larger)
	smoke_cloud(Vector3(at.x, at.y - 0.2, at.z), 1.7, 64, 9.5)              # 0.31.59: the cloud that hangs over it
	ring_at(Vector3(at.x, at.y - 0.5, at.z), Color(1.0, 0.55, 0.2), Sim.BOMB_R, 0.7)
	ring_at(Vector3(at.x, at.y - 0.5, at.z), Color(1.0, 0.9, 0.6), Sim.BOMB_R * 0.6, 0.4)
	# (its fire, sparks, smoke and burning debris replace the old glow sphere, sparks and smoke puffs)
	var sc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = Sim.BOMB_R * 0.65
	cyl.bottom_radius = Sim.BOMB_R * 0.65
	cyl.height = 0.02
	cyl.radial_segments = 24
	sc.mesh = cyl
	var scm := StandardMaterial3D.new()
	scm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	scm.albedo_color = Color(0.08, 0.06, 0.05, 0.55)
	scm.roughness = 1.0
	sc.material_override = scm
	sc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sc.position = Vector3(at2.x, Sim.height_at(at2) + 0.04, at2.y)
	add_child(sc)
	_booms.append({"node":sc, "kind":"scorch", "t0":_time, "life":25.0})
	if is_instance_valid(camera):
		shake(clampf(1.0 - Vector2(camera.global_position.x - at.x, camera.global_position.z - at.z).length() / 45.0, 0.15, 1.0) * 0.9)


# ---------- ragdolls and dropped weapons (0.31.20, Kevin: "ragdoll physics so when they die they fall to the ground
# in a way that they were killed"; "when a player dies their weapons fall on the ground too") ----------
# A death near the camera turns the body into a ragdoll: 11 physics bodies on the KayKit skeleton (hips, chest, head,
# upper and lower arms and legs) joined by cones (hips, shoulders, neck) and hinges (elbows, knees), thrown with the
# killing blow's push from the sim (a sword: back from the killer; an arrow or hammer: the way it flew; a bomb or a
# catapult stone: up and away from the blast) and tumbling. The ground under it is a small height-field patch sampled
# from the land (castle floors included). The weapons in his hands come loose as rigid bodies thrown the same way.
# All of it is freed when he respawns; at most RAG_MAX at once (the oldest is let go).
const RAG_MAX := 8
const RAG_NEAR := 40.0
const RAG_SPEC := [
	# bone, child bone (for its length), radius, joint (0 none, 1 cone, 2 hinge), mass
	["hips", "spine", 0.24, 0, 3.0], ["chest", "head", 0.27, 1, 3.0], ["head", "", 0.4, 1, 2.0],
	["upperarm.l", "lowerarm.l", 0.08, 1, 0.6], ["lowerarm.l", "wrist.l", 0.07, 2, 0.5],
	["upperarm.r", "lowerarm.r", 0.08, 1, 0.6], ["lowerarm.r", "wrist.r", 0.07, 2, 0.5],
	["upperleg.l", "lowerleg.l", 0.1, 1, 0.9], ["lowerleg.l", "foot.l", 0.09, 2, 0.7],
	["upperleg.r", "lowerleg.r", 0.1, 1, 0.9], ["lowerleg.r", "foot.r", 0.09, 2, 0.7]]
var _ragdolls: Array = []
var _debris: Array = []

func _ground_patch(c: Vector3, half: int = 7) -> StaticBody3D:
	var hm := HeightMapShape3D.new()
	var w := half * 2 + 1
	hm.map_width = w
	hm.map_depth = w
	var data := PackedFloat32Array()
	data.resize(w * w)
	for zi in w:
		for xi in w:
			data[zi * w + xi] = Sim.height_at(Vector2(c.x + float(xi - half), c.z + float(zi - half)))
	hm.map_data = data
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = hm
	sb.add_child(cs)
	sb.position = Vector3(roundf(c.x), 0.0, roundf(c.z))
	sb.physics_material_override = PhysicsMaterial.new()
	sb.physics_material_override.friction = 0.9
	add_child(sb)
	return sb

func _ragdoll(a: Dictionary, push: Vector3) -> void:
	if a.get("rag") != null or a.get("body") == null:
		return
	var root: Node3D = a.root
	if is_instance_valid(camera) and Vector2(root.global_position.x - camera.global_position.x, root.global_position.z - camera.global_position.z).length() > RAG_NEAR:
		return
	var skel: Skeleton3D = (a.body as Node3D).find_child("Skeleton3D", true, false)
	if skel == null:
		return
	while _ragdolls.size() >= RAG_MAX:
		_ragdoll_end(_ragdolls[0])
	var sim3 := PhysicalBoneSimulator3D.new()
	skel.add_child(sim3)
	var bones: Array = []
	for sp in RAG_SPEC:
		var bi := skel.find_bone(str(sp[0]))
		if bi < 0:
			continue
		var length := 0.6
		var dir := Vector3.UP
		if str(sp[1]) != "":
			var ci := skel.find_bone(str(sp[1]))
			if ci >= 0:
				var co: Vector3 = skel.get_bone_rest(ci).origin
				length = maxf(co.length(), 0.05)
				dir = co / length
		var pb := PhysicalBone3D.new()
		pb.bone_name = str(sp[0])
		var r: float = sp[2]
		var basis := Basis(Quaternion(Vector3.UP, dir)) if dir.distance_to(Vector3.UP) > 0.001 else Basis()
		var reach := length * 0.5 if str(sp[0]) != "head" else 0.42
		pb.body_offset = Transform3D(basis, dir * reach)
		pb.joint_offset = Transform3D(Basis(), Vector3(0.0, -reach, 0.0))
		var cs := CollisionShape3D.new()
		if str(sp[0]) == "head":
			var sph := SphereShape3D.new()
			sph.radius = r
			cs.shape = sph
		else:
			var cap := CapsuleShape3D.new()
			cap.radius = r
			cap.height = maxf(length, r * 2.0 + 0.02)
			cs.shape = cap
		pb.add_child(cs)
		pb.mass = float(sp[4])
		pb.friction = 0.85
		pb.bounce = 0.05
		pb.linear_damp = 0.6
		pb.angular_damp = 1.6
		match int(sp[3]):
			1:
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			2:
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
			_:
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
		sim3.add_child(pb)
		if int(sp[3]) == 1:
			pb.set("joint_constraints/swing_span", 50.0)
			pb.set("joint_constraints/twist_span", 25.0)
		elif int(sp[3]) == 2:
			pb.set("joint_constraints/angular_limit_enabled", true)
			pb.set("joint_constraints/angular_limit_upper", 0.0)
			pb.set("joint_constraints/angular_limit_lower", -110.0)
		bones.append(pb)
	if bones.is_empty():
		sim3.queue_free()
		return
	var ground := _ground_patch(root.global_position, 10)       # room for the throw (a bomb carries them ~4 m)
	if a.get("player") != null:
		(a.player as AnimationPlayer).pause()
	sim3.physical_bones_start_simulation()
	var spin := push.length() * 0.9
	for pb in bones:
		(pb as PhysicalBone3D).linear_velocity = push + Vector3(randf_range(-0.4, 0.4), randf_range(0.0, 0.3), randf_range(-0.4, 0.4))
		(pb as PhysicalBone3D).angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spin
	(a.ring as MeshInstance3D).visible = false
	a["rag"] = {"sim":sim3, "ground":ground, "t0":_time}
	_ragdolls.append(a)

func _ragdoll_end(a: Dictionary) -> void:
	var rg = a.get("rag")
	if rg == null:
		return
	if is_instance_valid(rg.sim):
		(rg.sim as PhysicalBoneSimulator3D).physical_bones_stop_simulation()
		(rg.sim as Node).queue_free()
	if is_instance_valid(rg.ground):
		(rg.ground as Node).queue_free()
	a["rag"] = null
	if a.get("player") != null and is_instance_valid(a.player):
		(a.player as AnimationPlayer).play()
	_ragdolls.erase(a)

func _drop_weapons(a: Dictionary, push: Vector3) -> void:
	# whatever he held comes loose: each weapon or shield becomes a tumbling rigid body thrown with him
	if a.get("body") == null:
		return
	var root: Node3D = a.root
	if is_instance_valid(camera) and Vector2(root.global_position.x - camera.global_position.x, root.global_position.z - camera.global_position.z).length() > RAG_NEAR:
		return
	var ground: StaticBody3D = null
	for slot in (a.body as Node3D).find_children("*", "BoneAttachment3D", true, false):
		if not str((slot as BoneAttachment3D).bone_name).begins_with("handslot"):
			continue
		for w in (slot as Node3D).get_children():
			if not (w is Node3D) or not (w as Node3D).visible:
				continue
			var aabb := _node_aabb(w as Node3D)
			if aabb.size.length() < 0.05:
				continue
			if ground == null:
				ground = _ground_patch(root.global_position, 6)
			var rb := RigidBody3D.new()
			var gt: Transform3D = (w as Node3D).global_transform
			var copy := (w as Node3D).duplicate() as Node3D
			rb.add_child(copy)
			copy.transform = Transform3D(gt.basis, Vector3.ZERO)
			var cs := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			bx.size = Vector3(maxf(aabb.size.x, 0.08), maxf(aabb.size.y, 0.08), maxf(aabb.size.z, 0.08)) * gt.basis.get_scale()
			cs.shape = bx
			cs.transform = Transform3D(gt.basis.orthonormalized(), gt.basis * aabb.get_center())
			rb.add_child(cs)
			rb.mass = 0.8
			rb.physics_material_override = PhysicsMaterial.new()
			rb.physics_material_override.bounce = 0.2
			rb.physics_material_override.friction = 0.7
			add_child(rb)
			rb.global_position = gt.origin
			rb.linear_velocity = push * 1.1 + Vector3(randf_range(-0.8, 0.8), 1.2 + randf(), randf_range(-0.8, 0.8))
			rb.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
			(w as Node3D).visible = false
			_debris.append({"node":rb, "ground":ground, "t0":_time, "id":str(a.get("id", ""))})
	# loose weapons lie a while, then go (with their bit of ground)
	for i in range(_debris.size() - 1, -1, -1):
		if _time - float(_debris[i].t0) > 30.0 or _debris.size() > 24:
			var d: Dictionary = _debris[i]
			if is_instance_valid(d.node):
				(d.node as Node).queue_free()
			if is_instance_valid(d.ground) and _debris.filter(func(x): return x.ground == d.ground).size() <= 1:
				(d.ground as Node).queue_free()
			_debris.remove_at(i)

func _node_aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false) + ([n] if n is MeshInstance3D else []):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var b := n.global_transform.affine_inverse() * mi.global_transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


# ---------- the player launcher (0.31.28) ----------
# A round wooden pad on a stone base with a brass rim and a great spring under it, and a lever on a post beside it;
# only once the team has built it. Pulling the lever: the countdown (5..1) hangs over the pad and the rim glows,
# faster to the end; then everyone on it is thrown (the arc comes from Sim.flight_height).
var launcher_nodes: Array = [null, null]

func _make_launcher(t: int) -> Dictionary:
	var root := Node3D.new()
	var c: Vector2 = sim.launch_pad(t)
	root.position = Vector3(c.x, Sim.height_at(c), c.y)
	add_child(root)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("#8d8a84")
	stone.roughness = 0.9
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("#9c6a3c")
	wood.roughness = 0.8
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color("#c79a45")
	brass.metallic = 0.7
	brass.roughness = 0.35
	brass.emission_enabled = true
	brass.emission = Color(1.0, 0.7, 0.25)
	brass.emission_energy_multiplier = 0.0
	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = Sim.LAUNCH_PAD_R + 0.15
	bm.bottom_radius = Sim.LAUNCH_PAD_R + 0.35
	bm.height = 0.3
	base.mesh = bm
	base.material_override = stone
	base.position.y = 0.15
	root.add_child(base)
	var pad := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = Sim.LAUNCH_PAD_R
	pm.bottom_radius = Sim.LAUNCH_PAD_R
	pm.height = 0.12
	pad.mesh = pm
	pad.material_override = wood
	pad.position.y = 0.36
	root.add_child(pad)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = Sim.LAUNCH_PAD_R - 0.12
	tm.outer_radius = Sim.LAUNCH_PAD_R + 0.05
	rim.mesh = tm
	rim.material_override = brass
	rim.position.y = 0.42
	root.add_child(rim)
	for k in 4:                                       # the spring's coils showing under the pad
		var coil := MeshInstance3D.new()
		var cm := TorusMesh.new()
		cm.inner_radius = 0.55
		cm.outer_radius = 0.68
		coil.mesh = cm
		coil.material_override = brass
		coil.position = Vector3(0.0, 0.05 + k * 0.07, 0.0)
		root.add_child(coil)
	var lv: Vector2 = sim.launch_lever(t)
	var lever := Node3D.new()
	lever.position = Vector3(lv.x, Sim.height_at(lv), lv.y)
	add_child(lever)
	var post := MeshInstance3D.new()
	var pom := BoxMesh.new()
	pom.size = Vector3(0.35, 0.9, 0.35)
	post.mesh = pom
	post.material_override = wood
	post.position.y = 0.45
	lever.add_child(post)
	var arm := Node3D.new()
	arm.position.y = 0.85
	lever.add_child(arm)
	var stick := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.05
	sm.bottom_radius = 0.06
	sm.height = 1.0
	stick.mesh = sm
	stick.material_override = brass
	stick.position.y = 0.5
	arm.add_child(stick)
	var knob := MeshInstance3D.new()
	var km := SphereMesh.new()
	km.radius = 0.13
	km.height = 0.26
	knob.mesh = km
	var red := StandardMaterial3D.new()
	red.albedo_color = Color("#c0392b")
	knob.material_override = red
	knob.position.y = 1.0
	arm.add_child(knob)
	arm.rotation.x = -0.6
	var lbl := Label3D.new()
	lbl.font_size = 220
	lbl.outline_size = 36
	lbl.modulate = Color(1.0, 0.86, 0.4)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = Vector3(0.0, 3.2, 0.0)
	lbl.visible = false
	root.add_child(lbl)
	return {"root":root, "lever":lever, "arm":arm, "rim":brass, "label":lbl}

func _sync_launchers(dt: float) -> void:
	for t in 2:
		var built: bool = sim.launcher_built(t)
		var ln = launcher_nodes[t]
		if not built:
			if ln != null:
				(ln.root as Node3D).visible = false
				(ln.lever as Node3D).visible = false
			continue
		if ln == null:
			ln = _make_launcher(t)
			launcher_nodes[t] = ln
			ring_at((ln.root as Node3D).position + Vector3(0.0, 0.3, 0.0), GOLD, 3.5, 0.9)
		(ln.root as Node3D).visible = true
		(ln.lever as Node3D).visible = true
		var l: Dictionary = sim.launchers[t]
		var counting := float(l.count_at) >= 0.0
		var lbl: Label3D = ln.label
		lbl.visible = counting
		(ln.arm as Node3D).rotation.x = lerpf((ln.arm as Node3D).rotation.x, 0.6 if counting else -0.6, 1.0 - exp(-dt * 10.0))
		if counting:
			var left := maxf(0.0, Sim.LAUNCH_COUNT - (sim.time - float(l.count_at)))
			var n := int(ceil(left))
			if lbl.text != str(n):
				lbl.text = str(n)
				lbl.scale = Vector3.ONE * 1.4
			lbl.scale = lbl.scale.lerp(Vector3.ONE, 1.0 - exp(-dt * 8.0))
			(ln.rim as StandardMaterial3D).emission_energy_multiplier = 1.5 + 1.5 * sin(_time * lerpf(6.0, 22.0, 1.0 - left / Sim.LAUNCH_COUNT))
		else:
			var ready: bool = sim.time >= float(l.ready_at)
			(ln.rim as StandardMaterial3D).emission_energy_multiplier = (0.6 + 0.4 * sin(_time * 2.0)) if ready else 0.0


# ---------- the upgrades' new abilities in the view (0.31.32) ----------
func _sync_vanish(a: Dictionary, u: Dictionary) -> void:
	# an Assassin in Vanish: almost nothing for the enemy (8 % opaque), a ghost for his own side (45 %); ring hidden from
	# the enemy. Each mesh gets a see-through copy of its material while it lasts (GeometryInstance3D.transparency
	# didn't show on the phone renderer in the check render).
	var v: bool = sim.vanished(u)
	var want: float = 0.0
	if v:
		want = 0.55 if int(u.team) == int(sim.by_id.get(player_id, {}).get("team", 0)) else 0.92
	var on: bool = bool(a.get("vanish_on", false))
	if v and not on:
		a["vanish_on"] = true
		for mi in (a.body as Node3D).find_children("*", "MeshInstance3D", true, false):
			var m3 := mi as MeshInstance3D
			if m3.mesh == null:
				continue
			for si in m3.mesh.get_surface_count():
				var base: Material = m3.get_active_material(si)
				if base is BaseMaterial3D:
					var ghost := (base as BaseMaterial3D).duplicate() as BaseMaterial3D
					ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					ghost.albedo_color.a = 1.0 - want
					m3.set_meta("vanish_prev_%d" % si, m3.get_surface_override_material(si))
					m3.set_surface_override_material(si, ghost)
		if want > 0.9:
			(a.ring as MeshInstance3D).visible = false
	elif not v and on:
		a["vanish_on"] = false
		for mi in (a.body as Node3D).find_children("*", "MeshInstance3D", true, false):
			var m3 := mi as MeshInstance3D
			if m3.mesh == null:
				continue
			for si in m3.mesh.get_surface_count():
				if m3.has_meta("vanish_prev_%d" % si):
					m3.set_surface_override_material(si, m3.get_meta("vanish_prev_%d" % si))
					m3.remove_meta("vanish_prev_%d" % si)
	elif v and want > 0.9:
		(a.ring as MeshInstance3D).visible = false

var _meteors_fx: Array = []

func _meteor_warn(p2: Vector2, delay: float, team: int) -> void:
	var at := Vector3(p2.x, Sim.height_at(p2), p2.y)
	var ring := _decal(at + Vector3(0.0, 0.05, 0.0), Sim.METEOR_R, Color(1.0, 0.35, 0.15), 0.6)
	var rock := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.9
	sm.height = 1.8
	sm.radial_segments = 10
	sm.rings = 6
	rock.mesh = sm
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.35, 0.18, 0.1)
	mm.emission_enabled = true
	mm.emission = Color(1.0, 0.45, 0.12)
	mm.emission_energy_multiplier = 2.5
	rock.material_override = mm
	var from := at + Vector3(7.0, 28.0, 5.0)
	rock.position = from
	add_child(rock)
	_meteors_fx.append({"ring":ring, "rock":rock, "from":from, "to":at, "t0":_time, "dur":delay})

func _meteor_hit(p2: Vector2, burn: float) -> void:
	var at := Vector3(p2.x, Sim.height_at(p2) + 0.4, p2.y)
	shockwave(at, Sim.METEOR_R + 1.2)                                          # 0.31.56
	_pack_explosion("heavy", Vector3(at.x, at.y - 0.2, at.z), 3.4, true)      # 0.31.57 (0.31.58: a bit larger)
	smoke_cloud(at, 1.05, 34, 7.5)                                         # 0.31.59
	ring_at(at, Color(1.0, 0.5, 0.15), Sim.METEOR_R * 1.3, 0.6)
	shake(0.5)
	_blast_bodies(p2, Sim.METEOR_R + 1.5, 5.0)
	water_blast(p2, 0.7)
	_meteors_fx.append({"burn_at":at, "until":_time + burn})

func _sync_meteor_fx(dt: float) -> void:
	for i in range(_meteors_fx.size() - 1, -1, -1):
		var m: Dictionary = _meteors_fx[i]
		if m.has("rock"):
			var k := clampf((_time - float(m.t0)) / maxf(float(m.dur), 0.01), 0.0, 1.0)
			if is_instance_valid(m.rock):
				(m.rock as Node3D).position = (m.from as Vector3).lerp(m.to, k * k)
				if randf() < dt * 40.0:
					spark((m.rock as Node3D).position, Color(1.0, 0.6, 0.2))
			if is_instance_valid(m.ring):
				(m.ring as Node3D).scale = Vector3(1.0, 0.15, 1.0) * (0.8 + 0.2 * sin(_time * 18.0))
			if k >= 1.0:
				if is_instance_valid(m.rock):
					(m.rock as Node).queue_free()
				if is_instance_valid(m.ring):
					(m.ring as Node).queue_free()
				_meteors_fx.remove_at(i)
		else:
			if _time >= float(m.until):
				_meteors_fx.remove_at(i)
				continue
			if randf() < dt * 22.0:                       # the burning ground
				var off := Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).normalized() * randf() * Sim.METEOR_R * 0.8
				spark((m.burn_at as Vector3) + off, [Color(1.0, 0.5, 0.15), Color(1.0, 0.8, 0.25), Color(0.6, 0.2, 0.08)][randi() % 3])


# ---------- confetti from the woodpile and the quarry (0.31.33) ----------
# Every chop or pick throws a few chips; a tree coming down or a boulder breaking throws a burst (a blast, a bigger one,
# away from it). Small spinning bits -- bark and pale wood for trees, grey and dark stone for boulders -- that pop up,
# fall, bounce once and fade. Logs and rocks themselves pop and tumble in _sync_items.
const ITEM_POP_G := 16.0
const CHIP_G := 13.0
var _chips: Array = []
var _recent_blasts: Array = []        # [pos, time]: items appearing next to one pop higher
static var _chip_mesh: BoxMesh = null

func _chip_burst(at: Vector3, wood: bool, n: int, power: float, away := Vector2.ZERO) -> void:
	if low_fx:
		n = n / 3
	if _chip_mesh == null:
		_chip_mesh = BoxMesh.new()
		_chip_mesh.size = Vector3(0.16, 0.05, 0.11)
	var cols: Array = [Color("#7a5230"), Color("#c9a46b"), Color("#a57744"), Color("#5f9e3d")] if wood else [Color("#8b8a86"), Color("#a9a7a1"), Color("#6b6a66")]
	for i in n:
		var mi := MeshInstance3D.new()
		mi.mesh = _chip_mesh
		var m := StandardMaterial3D.new()
		m.albedo_color = cols[i % cols.size()]
		m.roughness = 0.9
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = at + Vector3(randf_range(-0.4, 0.4), randf_range(0.2, 1.4), randf_range(-0.4, 0.4))
		var sc := randf_range(0.7, 1.5)
		mi.scale = Vector3.ONE * sc
		add_child(mi)
		var out := Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(0.8, 3.0) * power
		if away != Vector2.ZERO:
			out = out * 0.5 + away.rotated(randf_range(-0.8, 0.8)) * randf_range(2.0, 6.0) * power
		_chips.append({"node":mi, "vel":Vector3(out.x, randf_range(4.0, 8.0) * power, out.y), "ax":Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized(),
			"spin":randf_range(8.0, 20.0), "t0":_time, "life":randf_range(1.6, 2.4), "bounced":false, "sc":sc})

func _sync_chips(dt: float) -> void:
	while not _recent_blasts.is_empty() and _time - float(_recent_blasts[0][1]) > 1.0:
		_recent_blasts.pop_front()
	for i in range(_chips.size() - 1, -1, -1):
		var c: Dictionary = _chips[i]
		var mi: MeshInstance3D = c.node
		var age := _time - float(c.t0)
		if age > float(c.life) or not is_instance_valid(mi):
			if is_instance_valid(mi):
				mi.queue_free()
			_chips.remove_at(i)
			continue
		var v: Vector3 = c.vel
		v.y -= CHIP_G * dt
		v.x *= 1.0 - 0.6 * dt                        # light bits: the air slows them (confetti, not stones)
		v.z *= 1.0 - 0.6 * dt
		var np: Vector3 = mi.position + v * dt
		var gy := Sim.height_at(Vector2(np.x, np.z)) + 0.03
		if np.y < gy:
			np.y = gy
			if not bool(c.bounced) and v.y < -2.0:
				v = Vector3(v.x * 0.5, -v.y * 0.3, v.z * 0.5)
				c.bounced = true
			else:
				v = Vector3(v.x * 0.2, 0.0, v.z * 0.2)
				c.spin = float(c.spin) * 0.8
		c.vel = v
		mi.position = np
		mi.rotate(c.ax, float(c.spin) * dt)
		var fade := clampf((float(c.life) - age) / 0.5, 0.0, 1.0)
		mi.scale = Vector3.ONE * float(c.sc) * fade


func _launch_items(at2: Vector2, radius: float, power: float) -> void:
	# 0.31.34 (Kevin: "make sure the materials get flung from explosion/catapult"): logs and rocks already lying in a
	# blast go up into the air again, tumbling. (0.31.35: when the sim has them in flight -- offline, or the host -- the
	# view follows that flight instead; this is the online client's stand-in.)
	for id in item_nodes.keys():
		var simit: Array = sim.items.filter(func(x): return int(x.id) == int(id))
		if not simit.is_empty() and float(simit[0].get("air_end", -1.0)) > sim.time:
			continue
		var nd: Node3D = item_nodes[id]
		var d := Vector2(nd.position.x - at2.x, nd.position.z - at2.y).length()
		if d > radius:
			continue
		nd.set_meta("pop_vz", lerpf(11.0, 6.0, d / radius) * power + randf_range(-1.0, 1.0))
		nd.set_meta("pop_h", maxf(float(nd.get_meta("pop_h", 0.0)), 0.05))
		nd.set_meta("pop_ax", Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)).normalized())
		nd.set_meta("pop_spin", randf_range(10.0, 20.0))
		if not nd.has_meta("pop_rot"):
			nd.set_meta("pop_rot", 0.0)
