extends RefCounted
# The Grave Wyrm's body (0.31.166; Kevin picked concept "A" -- a skeletal dragon with soul-fire in its ribs -- made by
# Meshy). One mesh with no rig: tools/wyrm_prep.py cut it off its rock base and painted its limbs into the vertex colours
# (R the wings, G the neck, B the tail, A the legs -- the front-left and back-right above 128/255, the other pair below),
# each weight rising from 0 where the limb leaves the torso. SHADER bends the limbs about the joints below: the wings
# about a hinge along the body, the neck and head about its base, the tail in a travelling wave, the legs stepping in
# diagonal pairs. Its idle (breathing, the wings and tail stirring, the head turning) runs on TIME in the shader; what
# it does -- bite, wing buffet, soul-fire, flinch, fall -- the clips below drive through the shader's uniforms and a
# pivot under the body (an AnimationPlayer as every other body has, so the view plays it the same way).
# Model space: metres, feet on y 0, its front +Z (the view turns bodies so +Z faces where they face).

const MODEL := "res://assets/meshy/wyrm/wyrm.glb"
# where each limb leaves the torso (tools/wyrm_prep.py prints them)
const WING_L := Vector3(-0.82, 2.48, -0.09)
const WING_R := Vector3(1.49, 2.40, -0.38)
const NECK := Vector3(0.29, 2.11, 1.45)
const TAIL := Vector3(0.55, 1.37, -1.46)
const MID_X := 0.33                       # the torso's middle (the wings either side of it)
const MOUTH := Vector3(1.17, 2.8, 2.96)   # the tip of its jaws, at rest
const REST_YAW := -0.42                   # the head looks off to its left as modelled: turned back to the front

const SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec3 wing_l;
uniform vec3 wing_r;
uniform vec3 neck_root;
uniform vec3 tail_root;
uniform float mid_x;
uniform float rest_yaw;
uniform float flap = 0.0;      // the wings: + raised (radians)
uniform float sweep = 0.0;     // the wings: + swept forward
uniform float pitch = 0.0;     // the neck: + head down
uniform float yaw = 0.0;       // the neck: + toward +x
uniform float reach = 0.0;     // the head thrust forward (m)
uniform float stride = 0.0;    // the legs: 1 walking
uniform float alive = 1.0;     // the idle stirring (0 once it has fallen)
uniform float glow = 1.0;      // the soul-fire in its ribs
mat3 rx(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, c, s), vec3(0.0, -s, c)); }
mat3 ry(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, 0.0, -s), vec3(0.0, 1.0, 0.0), vec3(s, 0.0, c)); }
mat3 rz(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, s, 0.0), vec3(-s, c, 0.0), vec3(0.0, 0.0, 1.0)); }
void vertex() {
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	float t = TIME;
	float ww = COLOR.r;
	float nk = COLOR.g;
	float tl = COLOR.b;
	float lg = (COLOR.a * 255.0 - 128.0) / 127.0;
	// breathing: the ribs rise and swell
	float core = (1.0 - ww) * (1.0 - nk) * (1.0 - tl) * (1.0 - abs(lg));
	float br = (0.5 + 0.5 * sin(t * 1.25)) * alive * core * smoothstep(0.9, 1.8, v.y) * (1.0 - smoothstep(2.6, 3.2, v.y));
	v.x += (v.x - mid_x) * 0.035 * br;
	v.y += 0.05 * br;
	if (ww > 0.0) {
		float side = v.x > mid_x ? 1.0 : -1.0;
		vec3 root = side > 0.0 ? wing_r : wing_l;
		float a = (flap + alive * (0.05 + 0.06 * sin(t * 1.25 + 0.5))) * ww * side;
		mat3 r = rz(a) * ry(-sweep * ww * side);
		v = root + r * (v - root);
		n = r * n;
	}
	if (nk > 0.0) {
		float p = pitch + alive * 0.07 * sin(t * 0.8);
		float y = rest_yaw + yaw + alive * 0.12 * sin(t * 0.45 + 1.0);
		mat3 r = ry(y * nk) * rx(p * nk);
		v = neck_root + r * (v - neck_root) + vec3(0.0, -0.25 * reach, reach) * nk;
		n = r * n;
	}
	if (tl > 0.0) {
		float d = length((v - tail_root).xz);
		float a = (0.06 + 0.1 * alive) * sin(t * 1.5 - d * 1.2) * tl;
		mat3 r = ry(a);
		v = tail_root + r * (v - tail_root);
		n = r * n;
	}
	if (lg != 0.0 && stride > 0.0) {
		float s = sin(t * 7.0) * sign(lg);
		float k = stride * abs(lg);
		v.y += k * max(0.0, s) * 0.3;
		v.z += k * s * 0.22;
	}
	VERTEX = v;
	NORMAL = normalize(n);
}
void fragment() {
	vec4 c = texture(albedo_tex, UV);
	ALBEDO = c.rgb;
	ROUGHNESS = 0.8;
	// the cyan in its bones burns: soul-fire
	float soul = smoothstep(0.08, 0.22, min(c.g, c.b) - c.r);
	EMISSION = c.rgb * soul * glow * (2.0 + 0.8 * sin(TIME * 2.6));
}
"""

# the clips: name -> [length, loops, {track: [[time, value], ...]}]; a track left out stays at its rest (REST) all through.
# Tracks: the shader's uniforms, and "pos" / "rot" of the pivot (the body's turn about its feet: x leans it forward).
const REST := {"flap":0.0, "sweep":0.0, "pitch":0.0, "yaw":0.0, "reach":0.0, "stride":0.0, "alive":1.0, "glow":1.0,
	"pos":Vector3.ZERO, "rot":Vector3.ZERO}
const CLIPS := {
	"w/Idle": [4.0, true, {}],
	"w/Move": [1.0, true, {"stride":[[0.0, 1.0]], "flap":[[0.0, 0.1]], "pitch":[[0.0, 0.12]],
		"pos":[[0.0, Vector3(0, 0, 0)], [0.23, Vector3(0, 0.08, 0)], [0.45, Vector3(0, 0, 0)], [0.68, Vector3(0, 0.08, 0)], [0.9, Vector3(0, 0, 0)]],
		"rot":[[0.0, Vector3(0.03, 0, -0.025)], [0.45, Vector3(0.03, 0, 0.025)], [0.9, Vector3(0.03, 0, -0.025)]]}],
	# a snap of the jaws: rear the head back, strike down and forward
	"w/Bite": [0.8, false, {"pitch":[[0.0, 0.0], [0.22, -0.4], [0.36, 0.32], [0.55, 0.22], [0.8, 0.0]],
		"reach":[[0.0, 0.0], [0.22, -0.25], [0.36, 0.45], [0.55, 0.3], [0.8, 0.0]],
		"rot":[[0.0, Vector3.ZERO], [0.22, Vector3(-0.05, 0, 0)], [0.36, Vector3(0.07, 0, 0)], [0.8, Vector3.ZERO]],
		"pos":[[0.0, Vector3.ZERO], [0.22, Vector3(0, 0.06, -0.1)], [0.36, Vector3(0, 0, 0.25)], [0.8, Vector3.ZERO]]}],
	# a buffet of the wings: up, then a beat down that lifts it off its feet
	"w/Swipe": [0.9, false, {"flap":[[0.0, 0.0], [0.3, 0.6], [0.48, -0.3], [0.9, 0.0]],
		"sweep":[[0.0, 0.0], [0.3, -0.2], [0.48, 0.3], [0.9, 0.0]],
		"pitch":[[0.0, 0.0], [0.3, -0.25], [0.5, 0.2], [0.9, 0.0]],
		"pos":[[0.0, Vector3.ZERO], [0.3, Vector3(0, 0.05, 0)], [0.48, Vector3(0, 0.4, 0.15)], [0.7, Vector3(0, 0.05, 0.1)], [0.9, Vector3.ZERO]],
		"rot":[[0.0, Vector3.ZERO], [0.3, Vector3(-0.08, 0, 0)], [0.48, Vector3(0.05, 0, 0)], [0.9, Vector3.ZERO]]}],
	# soul-fire: rear up with the wings raised, then lunge and pour it out (the view's flames start at BREATH_AT)
	"w/Breath": [1.5, false, {"pitch":[[0.0, 0.0], [0.22, -0.6], [0.34, 0.25], [1.1, 0.3], [1.5, 0.0]],
		"reach":[[0.0, 0.0], [0.22, -0.3], [0.34, 0.45], [1.1, 0.4], [1.5, 0.0]],
		"flap":[[0.0, 0.0], [0.22, 0.5], [0.4, -0.15], [1.1, 0.05], [1.5, 0.0]],
		"sweep":[[0.0, 0.0], [0.22, -0.25], [0.4, 0.15], [1.5, 0.0]],
		"glow":[[0.0, 1.0], [0.22, 2.4], [1.1, 1.8], [1.5, 1.0]],
		"yaw":[[0.0, 0.0], [0.34, 0.0], [0.7, 0.12], [1.05, -0.12], [1.5, 0.0]],
		"rot":[[0.0, Vector3.ZERO], [0.22, Vector3(-0.1, 0, 0)], [0.34, Vector3(0.06, 0, 0)], [1.1, Vector3(0.05, 0, 0)], [1.5, Vector3.ZERO]],
		"pos":[[0.0, Vector3.ZERO], [0.22, Vector3(0, 0.22, -0.15)], [0.34, Vector3(0, 0, 0.2)], [1.5, Vector3.ZERO]]}],
	# out of the ground when it rises in its pit
	"w/Rise": [1.8, false, {"pos":[[0.0, Vector3(0, -3.6, 0)], [1.1, Vector3(0, 0.15, 0)], [1.4, Vector3.ZERO]],
		"rot":[[0.0, Vector3(-0.35, 0, 0)], [1.1, Vector3(-0.1, 0, 0)], [1.4, Vector3.ZERO]],
		"flap":[[0.0, -0.5], [1.0, -0.2], [1.3, 0.7], [1.6, 0.1], [1.8, 0.0]],
		"pitch":[[0.0, 0.5], [1.1, -0.6], [1.6, -0.3], [1.8, 0.0]],
		"glow":[[0.0, 0.2], [1.2, 2.6], [1.8, 1.0]]}],
	# a flinch
	"g/Hit_A": [0.35, false, {"rot":[[0.0, Vector3.ZERO], [0.08, Vector3(-0.05, 0, 0)], [0.35, Vector3.ZERO]],
		"flap":[[0.0, 0.0], [0.08, 0.12], [0.35, 0.0]], "pitch":[[0.0, 0.0], [0.08, -0.15], [0.35, 0.0]]}],
	"g/Hit_B": [0.35, false, {"rot":[[0.0, Vector3.ZERO], [0.08, Vector3(0, 0.05, 0.05)], [0.35, Vector3.ZERO]],
		"yaw":[[0.0, 0.0], [0.08, -0.2], [0.35, 0.0]], "pitch":[[0.0, 0.0], [0.08, -0.1], [0.35, 0.0]]}],
	# it falls: a last rear with the soul-fire flaring, then down on its side with the wings folding over and the fire out
	"g/Death_A": [2.2, false, {"alive":[[0.0, 1.0], [0.6, 0.0]],
		"glow":[[0.0, 1.0], [0.3, 3.0], [1.4, 0.6], [2.2, 0.0]],
		"pitch":[[0.0, 0.0], [0.3, -0.6], [1.3, 0.85], [1.5, 0.75], [2.2, 0.8]],
		"yaw":[[0.0, 0.0], [1.3, 0.3]],
		"flap":[[0.0, 0.0], [0.3, 0.55], [1.2, -0.55], [1.4, -0.45], [2.2, -0.5]],
		"sweep":[[0.0, 0.0], [1.2, -0.35]],
		"rot":[[0.0, Vector3.ZERO], [0.3, Vector3(-0.15, 0, 0)], [1.2, Vector3(0.06, 0, 0.3)], [1.4, Vector3(0.05, 0, 0.27)], [2.2, Vector3(0.05, 0, 0.28)]],
		"pos":[[0.0, Vector3.ZERO], [0.3, Vector3(0, 0.3, 0)], [1.2, Vector3(0, -0.35, 0)], [1.4, Vector3(0, -0.28, 0)], [2.2, Vector3(0, -0.3, 0)]]}],
}
const ALIASES := {"g/Idle_A": "w/Idle", "mb/Running_A": "w/Move"}
const EASE := -1.8                        # each key's ease into the next (in and out)
const BREATH_AT := 0.3                    # (s into w/Breath) the lunge: the flames pour from here

static var _shader: Shader = null
static var _libs: Dictionary = {}

static func make(packed: PackedScene, shadows: bool) -> Dictionary:
	# {"body", "player"} as SiegeView.make_body gives, or {} without its model (a content pack not on the phone yet)
	if packed == null:
		return {}
	var model: Node3D = packed.instantiate()
	var found := model.find_children("*", "MeshInstance3D", true, false)
	if found.is_empty():
		model.free()
		return {}
	var mi: MeshInstance3D = found[0]
	var xf := mi.transform
	var src: Material = mi.get_active_material(0)
	mi.get_parent().remove_child(mi)
	model.free()
	var body := Node3D.new()
	body.name = "Wyrm"
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	body.add_child(pivot)
	mi.name = "Mesh"
	mi.owner = null
	mi.transform = xf
	pivot.add_child(mi)
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var sm := ShaderMaterial.new()
	sm.shader = _shader
	if src is BaseMaterial3D:
		sm.set_shader_parameter("albedo_tex", (src as BaseMaterial3D).albedo_texture)
	sm.set_shader_parameter("wing_l", WING_L)
	sm.set_shader_parameter("wing_r", WING_R)
	sm.set_shader_parameter("neck_root", NECK)
	sm.set_shader_parameter("tail_root", TAIL)
	sm.set_shader_parameter("mid_x", MID_X)
	sm.set_shader_parameter("rest_yaw", REST_YAW)
	mi.material_override = sm
	mi.extra_cull_margin = 2.5               # (the wings reach past the mesh's own box when raised)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var player := AnimationPlayer.new()
	body.add_child(player)
	player.root_node = NodePath("..")
	var libs := libraries()
	for key in libs:
		player.add_animation_library(key, libs[key])
	return {"body":body, "player":player}

static func libraries() -> Dictionary:
	if not _libs.is_empty():
		return _libs
	var anims := {}
	for name in CLIPS:
		anims[name] = _clip(CLIPS[name])
	for alias in ALIASES:
		anims[alias] = anims[ALIASES[alias]]
	for full in anims:
		var parts := str(full).split("/")
		if not _libs.has(parts[0]):
			_libs[parts[0]] = AnimationLibrary.new()
		(_libs[parts[0]] as AnimationLibrary).add_animation(parts[1], anims[full])
	return _libs

static func _clip(spec: Array) -> Animation:
	# every track a value track, linear with an ease in and out on each stretch (Godot's cubic overshoots between
	# keys unevenly spaced: 0.65 where the keys say 0.12 and 0.16)
	var an := Animation.new()
	an.length = float(spec[0])
	an.loop_mode = Animation.LOOP_LINEAR if bool(spec[1]) else Animation.LOOP_NONE
	var keys: Dictionary = spec[2]
	for track in REST:
		var ks: Array = keys.get(track, [[0.0, REST[track]]])
		var t := an.add_track(Animation.TYPE_VALUE)
		match str(track):
			"pos": an.track_set_path(t, NodePath("Pivot:position"))
			"rot": an.track_set_path(t, NodePath("Pivot:rotation"))
			_: an.track_set_path(t, NodePath("Pivot/Mesh:material_override:shader_parameter/" + str(track)))
		an.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR)
		for k in ks:
			an.track_insert_key(t, float(k[0]), k[1] if track in ["pos", "rot"] else float(k[1]), EASE)
	return an

static func mouth_local() -> Vector3:
	# where its jaws are at rest (the head turned by REST_YAW about the neck), in its own space
	return NECK + Basis(Vector3.UP, REST_YAW) * (MOUTH - NECK)
