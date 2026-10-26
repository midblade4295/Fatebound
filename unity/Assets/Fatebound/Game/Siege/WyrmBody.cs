// Ported from godot/scripts/siege/wyrm_body.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector3 = Fatebound.Sim.Vec3;
using Color = Fatebound.GUI.Col;
using Transform3D = Fatebound.Sim.Xform3;
using Material = Fatebound.GUI.GMaterial;

namespace Fatebound.Game
{
    // The Grave Wyrm's body (0.31.166; Kevin picked concept "A" -- a skeletal dragon with soul-fire in its ribs -- made by
    // Meshy). One mesh with no rig: tools/wyrm_prep.py cut it off its rock base and painted its limbs into the vertex colours
    // (R the wings, G the neck, B the tail, A the legs -- the front-left and back-right above 128/255, the other pair below),
    // each weight rising from 0 where the limb leaves the torso. SHADER bends the limbs about the joints below: the wings
    // about a hinge along the body, the neck and head about its base, the tail in a travelling wave, the legs stepping in
    // diagonal pairs. Its idle (breathing, the wings and tail stirring, the head turning) runs on TIME in the shader; what
    // it does -- bite, wing buffet, soul-fire, flinch, fall -- the clips below drive through the shader's uniforms and a
    // pivot under the body (an AnimationPlayer as every other body has, so the view plays it the same way).
    // Model space: metres, feet on y 0, its front +Z (the view turns bodies so +Z faces where they face).
    public class WyrmBody
    {
        public const string MODEL = "res://assets/meshy/wyrm/wyrm.glb";
        // where each limb leaves the torso (tools/wyrm_prep.py prints them)
        public static readonly Vector3 WING_L = new Vector3(-0.82, 2.48, -0.09);
        public static readonly Vector3 WING_R = new Vector3(1.49, 2.40, -0.38);
        public static readonly Vector3 NECK = new Vector3(0.29, 2.11, 1.45);
        public static readonly Vector3 TAIL = new Vector3(0.55, 1.37, -1.46);
        public const double MID_X = 0.33;                       // the torso's middle (the wings either side of it)
        public static readonly Vector3 MOUTH = new Vector3(1.17, 2.8, 2.96);   // the tip of its jaws, at rest
        public const double REST_YAW = -0.42;                   // the head looks off to its left as modelled: turned back to the front

        public const string SHADER = @"
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
";


        // the clips: name -> [length, loops, {track: [[time, value], ...]}]; a track left out stays at its rest (REST) all through.
        // Tracks: the shader's uniforms, and "pos" / "rot" of the pivot (the body's turn about its feet: x leans it forward).
        public static readonly GDict REST = GDict.Of("flap", 0.0, "sweep", 0.0, "pitch", 0.0, "yaw", 0.0, "reach", 0.0, "stride", 0.0, "alive", 1.0, "glow", 1.0,
            "pos", Vector3.ZERO, "rot", Vector3.ZERO);
        public static readonly GDict CLIPS = new GDict
        {
            { "w/Idle", GArray.Of(4.0, true, new GDict()) },
            { "w/Move", GArray.Of(1.0, true, GDict.Of("stride", GArray.Of(GArray.Of(0.0, 1.0)), "flap", GArray.Of(GArray.Of(0.0, 0.1)), "pitch", GArray.Of(GArray.Of(0.0, 0.12)),
                "pos", GArray.Of(GArray.Of(0.0, new Vector3(0, 0, 0)), GArray.Of(0.23, new Vector3(0, 0.08, 0)), GArray.Of(0.45, new Vector3(0, 0, 0)), GArray.Of(0.68, new Vector3(0, 0.08, 0)), GArray.Of(0.9, new Vector3(0, 0, 0))),
                "rot", GArray.Of(GArray.Of(0.0, new Vector3(0.03, 0, -0.025)), GArray.Of(0.45, new Vector3(0.03, 0, 0.025)), GArray.Of(0.9, new Vector3(0.03, 0, -0.025))))) },
            // a snap of the jaws: rear the head back, strike down and forward
            { "w/Bite", GArray.Of(0.8, false, GDict.Of("pitch", GArray.Of(GArray.Of(0.0, 0.0), GArray.Of(0.22, -0.4), GArray.Of(0.36, 0.32), GArray.Of(0.55, 0.22), GArray.Of(0.8, 0.0)),
                "reach", GArray.Of(GArray.Of(0.0, 0.0), GArray.Of(0.22, -0.25), GArray.Of(0.36, 0.45), GArray.Of(0.55, 0.3), GArray.Of(0.8, 0.0)),
                "rot", GArray.Of(GArray.Of(0.0, Vector3.ZERO), GArray.Of(0.22, new Vector3(-0.05, 0, 0)), GArray.Of(0.36, new Vector3(0.07, 0, 0)), GArray.Of(0.8, Vector3.ZERO)),
                "pos", GArray.Of(GArray.Of(0.0, Vector3.ZERO), GArray.Of(0.22, new Vector3(0, 0.06, -0.1)), GArray.Of(0.36, new Vector3(0, 0, 0.25)), GArray.Of(0.8, Vector3.ZERO)))) },
            // a buffet of the wings: up, then a beat down that lifts it off its feet
            { "w/Swipe", GArray.Of(0.9, false, GDict.Of("flap", GArray.Of(GArray.Of(0.0, 0.0), GArray.Of(0.3, 0.6), GArray.Of(0.48, -0.3), GArray.Of(0.9, 0.0)),
                "sweep", GArray.Of(GArray.Of(0.0, 0.0), GArray.Of(0.3, -0.2), GArray.Of(0.48, 0.3), GArray.Of(0.9, 0.0)),
                "pitch", GArray.Of(GArray.Of(0.0, 0.0), GArray.Of(0.3, -0.25), GArray.Of(0.5, 0.2), GArray.Of(0.9, 0.0)),
                "pos", GArray.Of(GArray.Of(0.0, Vector3.ZERO), GArray.Of(0.3, new Vector3(0, 0.05, 0)), GArray.Of(0.48, new Vector3(0, 0.4, 0.15)), GArray.Of(0.7, new Vector3(0, 0.05, 0.1)), GArray.Of(0.9, Vector3.ZERO)),
                "rot", GArray.Of(GArray.Of(0.0, Vector3.ZERO), GArray.Of(0.3, new Vector3(-0.08, 0, 0)), GArray.Of(0.48, new Vector3(0.05, 0, 0)), GArray.Of(0.9, Vector3.ZERO)))) },
            // soul-fire: rear up with the wings raised, then lunge and pour it out (the view's flames start at BREATH_AT)
            { "w/Breath", GArray.Of(1.5, false, GDict.Of("pitch", GArray.Of(GArray.Of(0.0, 0.0), GArray.Of(0.22, -0.6), GArray.Of(0.34, 0.25), GArray.Of(1.1, 0.3), GArray.Of(1.5, 0.0)),
                "reach", GArray.Of(GArray.Of(0.0, 0.0), GArray.Of(0.22, -0.3), GArray.Of(0.34, 0.45), GArray.Of(1.1, 0.4), GArray.Of(1.5, 0.0)),
                "flap", GArray.Of(GArray.Of(0.0, 0.0), GArray.Of(0.22, 0.5), GArray.Of(0.4, -0.15), GArray.Of(1.1, 0.05), GArray.Of(1.5, 0.0)),
                "sweep", GArray.Of(GArray.Of(0.0, 0.0), GArray.Of(0.22, -0.25), GArray.Of(0.4, 0.15), GArray.Of(1.5, 0.0)),
                "glow", GArray.Of(GArray.Of(0.0, 1.0), GArray.Of(0.22, 2.4), GArray.Of(1.1, 1.8), GArray.Of(1.5, 1.0)),
                "yaw", GArray.Of(GArray.Of(0.0, 0.0), GArray.Of(0.34, 0.0), GArray.Of(0.7, 0.12), GArray.Of(1.05, -0.12), GArray.Of(1.5, 0.0)),
                "rot", GArray.Of(GArray.Of(0.0, Vector3.ZERO), GArray.Of(0.22, new Vector3(-0.1, 0, 0)), GArray.Of(0.34, new Vector3(0.06, 0, 0)), GArray.Of(1.1, new Vector3(0.05, 0, 0)), GArray.Of(1.5, Vector3.ZERO)),
                "pos", GArray.Of(GArray.Of(0.0, Vector3.ZERO), GArray.Of(0.22, new Vector3(0, 0.22, -0.15)), GArray.Of(0.34, new Vector3(0, 0, 0.2)), GArray.Of(1.5, Vector3.ZERO)))) },
            // out of the ground when it rises in its pit
            { "w/Rise", GArray.Of(1.8, false, GDict.Of("pos", GArray.Of(GArray.Of(0.0, new Vector3(0, -3.6, 0)), GArray.Of(1.1, new Vector3(0, 0.15, 0)), GArray.Of(1.4, Vector3.ZERO)),
                "rot", GArray.Of(GArray.Of(0.0, new Vector3(-0.35, 0, 0)), GArray.Of(1.1, new Vector3(-0.1, 0, 0)), GArray.Of(1.4, Vector3.ZERO)),
                "flap", GArray.Of(GArray.Of(0.0, -0.5), GArray.Of(1.0, -0.2), GArray.Of(1.3, 0.7), GArray.Of(1.6, 0.1), GArray.Of(1.8, 0.0)),
                "pitch", GArray.Of(GArray.Of(0.0, 0.5), GArray.Of(1.1, -0.6), GArray.Of(1.6, -0.3), GArray.Of(1.8, 0.0)),
                "glow", GArray.Of(GArray.Of(0.0, 0.2), GArray.Of(1.2, 2.6), GArray.Of(1.8, 1.0)))) },
            // a flinch
            { "g/Hit_A", GArray.Of(0.35, false, GDict.Of("rot", GArray.Of(GArray.Of(0.0, Vector3.ZERO), GArray.Of(0.08, new Vector3(-0.05, 0, 0)), GArray.Of(0.35, Vector3.ZERO)),
                "flap", GArray.Of(GArray.Of(0.0, 0.0), GArray.Of(0.08, 0.12), GArray.Of(0.35, 0.0)), "pitch", GArray.Of(GArray.Of(0.0, 0.0), GArray.Of(0.08, -0.15), GArray.Of(0.35, 0.0)))) },
            { "g/Hit_B", GArray.Of(0.35, false, GDict.Of("rot", GArray.Of(GArray.Of(0.0, Vector3.ZERO), GArray.Of(0.08, new Vector3(0, 0.05, 0.05)), GArray.Of(0.35, Vector3.ZERO)),
                "yaw", GArray.Of(GArray.Of(0.0, 0.0), GArray.Of(0.08, -0.2), GArray.Of(0.35, 0.0)), "pitch", GArray.Of(GArray.Of(0.0, 0.0), GArray.Of(0.08, -0.1), GArray.Of(0.35, 0.0)))) },
            // it falls: a last rear with the soul-fire flaring, then down on its side with the wings folding over and the fire out
            { "g/Death_A", GArray.Of(2.2, false, GDict.Of("alive", GArray.Of(GArray.Of(0.0, 1.0), GArray.Of(0.6, 0.0)),
                "glow", GArray.Of(GArray.Of(0.0, 1.0), GArray.Of(0.3, 3.0), GArray.Of(1.4, 0.6), GArray.Of(2.2, 0.0)),
                "pitch", GArray.Of(GArray.Of(0.0, 0.0), GArray.Of(0.3, -0.6), GArray.Of(1.3, 0.85), GArray.Of(1.5, 0.75), GArray.Of(2.2, 0.8)),
                "yaw", GArray.Of(GArray.Of(0.0, 0.0), GArray.Of(1.3, 0.3)),
                "flap", GArray.Of(GArray.Of(0.0, 0.0), GArray.Of(0.3, 0.55), GArray.Of(1.2, -0.55), GArray.Of(1.4, -0.45), GArray.Of(2.2, -0.5)),
                "sweep", GArray.Of(GArray.Of(0.0, 0.0), GArray.Of(1.2, -0.35)),
                "rot", GArray.Of(GArray.Of(0.0, Vector3.ZERO), GArray.Of(0.3, new Vector3(-0.15, 0, 0)), GArray.Of(1.2, new Vector3(0.06, 0, 0.3)), GArray.Of(1.4, new Vector3(0.05, 0, 0.27)), GArray.Of(2.2, new Vector3(0.05, 0, 0.28))),
                "pos", GArray.Of(GArray.Of(0.0, Vector3.ZERO), GArray.Of(0.3, new Vector3(0, 0.3, 0)), GArray.Of(1.2, new Vector3(0, -0.35, 0)), GArray.Of(1.4, new Vector3(0, -0.28, 0)), GArray.Of(2.2, new Vector3(0, -0.3, 0))))) },
        };
        public static readonly GDict ALIASES = GDict.Of("g/Idle_A", "w/Idle", "mb/Running_A", "w/Move");
        public const double EASE = -1.8;                        // each key's ease into the next (in and out)
        public const double BREATH_AT = 0.3;                    // (s into w/Breath) the lunge: the flames pour from here

        public static Shader _shader = null;
        public static GDict _libs = new GDict();

        public static GDict Make(PackedScene packed, bool shadows)
        {
            // {"body", "player"} as SiegeView.make_body gives, or {} without its model (a content pack not on the phone yet)
            if (packed == null)
                return new GDict();
            Node3D model = packed.Instantiate() as Node3D;
            var found = model.FindChildren("*", "MeshInstance3D", true, false);
            if (found.Count == 0)
            {
                model.Free();
                return new GDict();
            }
            MeshInstance3D mi = (MeshInstance3D)found[0];
            var xf = mi.Transform;
            Material src = mi.GetActiveMaterial(0);
            mi.GetParent().RemoveChild(mi);
            model.Free();
            var body = new Node3D();
            body.Name = "Wyrm";
            var pivot = new Node3D();
            pivot.Name = "Pivot";
            body.AddChild(pivot);
            mi.Name = "Mesh";
            mi.Owner = null;
            mi.Transform = xf;
            pivot.AddChild(mi);
            if (_shader == null)
            {
                _shader = new Shader();
                _shader.Code = SHADER;
            }
            var sm = new ShaderMaterial();
            sm.Shader = _shader;
            if (src is BaseMaterial3D)
                sm.SetShaderParameter("albedo_tex", (src as BaseMaterial3D).AlbedoTexture);
            sm.SetShaderParameter("wing_l", WING_L);
            sm.SetShaderParameter("wing_r", WING_R);
            sm.SetShaderParameter("neck_root", NECK);
            sm.SetShaderParameter("tail_root", TAIL);
            sm.SetShaderParameter("mid_x", MID_X);
            sm.SetShaderParameter("rest_yaw", REST_YAW);
            mi.MaterialOverride = sm;
            mi.ExtraCullMargin = 2.5;               // (the wings reach past the mesh's own box when raised)
            mi.CastShadow = shadows ? GeometryInstance3D.SHADOW_CASTING_SETTING_ON : GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            var player = new AnimationPlayer();
            body.AddChild(player);
            player.RootNode = new NodePath("..");
            var libs = Libraries();
            foreach (var key in libs)
                player.AddAnimationLibrary(key.AsString(), libs[key].As<AnimationLibrary>());
            return GDict.Of("body", body, "player", player);
        }

        public static GDict Libraries()
        {
            if (!_libs.IsEmpty())
                return _libs;
            var anims = new GDict();
            foreach (var name in CLIPS)
                anims[name] = Var.Of(_Clip(CLIPS[name].A));
            foreach (var alias in ALIASES)
                anims[alias] = anims[ALIASES[alias]];
            foreach (var full in anims)
            {
                var parts = GD.Str(full).Split("/");
                if (!_libs.Has(parts[0]))
                    _libs[parts[0]] = Var.Of(new AnimationLibrary());
                _libs[parts[0]].As<AnimationLibrary>().AddAnimation(parts[1], anims[full].As<Animation>());
            }
            return _libs;
        }

        public static Animation _Clip(GArray spec)
        {
            // every track a value track, linear with an ease in and out on each stretch (Godot's cubic overshoots between
            // keys unevenly spaced: 0.65 where the keys say 0.12 and 0.16)
            var an = new Animation();
            an.Length = (double)spec[0];
            an.LoopMode = (bool)spec[1] ? Animation.LOOP_LINEAR : Animation.LOOP_NONE;
            GDict keys = spec[2].D;
            foreach (var track in REST)
            {
                GArray ks = keys.Get(track, GArray.Of(GArray.Of(0.0, REST[track]))).A;
                var t = an.AddTrack(Animation.TYPE_VALUE);
                switch (GD.Str(track))
                {
                    case "pos": an.TrackSetPath(t, new NodePath("Pivot:position")); break;
                    case "rot": an.TrackSetPath(t, new NodePath("Pivot:rotation")); break;
                    default: an.TrackSetPath(t, new NodePath("Pivot/Mesh:material_override:shader_parameter/" + GD.Str(track))); break;
                }
                an.TrackSetInterpolationType(t, Animation.INTERPOLATION_LINEAR);
                foreach (var k in ks)
                    an.TrackInsertKey(t, (double)k[0], GArray.Of("pos", "rot").Has(track) ? k[1] : (Var)(double)k[1], EASE);
            }
            return an;
        }

        public static Vector3 MouthLocal()
        {
            // where its jaws are at rest (the head turned by REST_YAW about the neck), in its own space
            return NECK + new Basis(Vector3.UP, REST_YAW) * (MOUTH - NECK);
        }
    }
}
