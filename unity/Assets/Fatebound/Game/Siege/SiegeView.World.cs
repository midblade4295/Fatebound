// Ported from godot/scripts/siege/siege_view.gd (Fatebound 0.31.222): blood, the world (lighting, terrain, outer land,
// water), foliage, whirls, shields, beams.
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector2i = Fatebound.Sim.Vec2i;
using Vector3 = Fatebound.Sim.Vec3;
using Vector4 = Fatebound.Sim.Vec4;
using Color = Fatebound.GUI.Col;
using Transform3D = Fatebound.Sim.Xform3;
using Quaternion = Fatebound.Sim.Quat;
using AABB = Fatebound.Sim.Aabb;
using Material = Fatebound.GUI.GMaterial;
using Environment = Fatebound.GUI.Environment;

namespace Fatebound.Game
{
    using Stage = Fatebound.Game.AssetCache;
    using Land = Fatebound.Sim.Land;
    using Keep = Fatebound.Sim.Keep;
    using Sim = Fatebound.Sim.SiegeSim;
    using Foliage = Fatebound.Game.Foliage;
    using GroundCards = Fatebound.Game.GroundCards;

    public partial class SiegeView
    {
        // ---------- Blood (Round 37, Kevin: "blood will splatter on the ground when hit, and when a player dies there will be
        // a pool of blood") ----------
        // Flat, lit, glossy marks on the ground (procedural splatter textures), droplets flung away from the attacker that
        // land as small spots, and a pool that spreads under a body. Recycled pools of nodes with hard caps; each mark fades
        // after a while. Not on the river.
        public static readonly Color BLOOD_COL = new Color(0.56, 0.03, 0.04);      // a red that reads as blood from the game camera (darker went black)
        public const int SPLAT_MAX = 90;
        public const int POOL_MAX = 24;
        public const int DROP_MAX = 60;
        public const double SPLAT_LIFE = 18.0;
        public const double POOL_LIFE = 25.0;
        public const double BLOOD_FADE = 3.0;
        public static GArray _blood_tex = new GArray();          // [splat variants..., pool]
        public GArray _splats = new GArray();                    // {mi, born, life, r0, r1, grow}
        public int _splat_i = 0;
        public GArray _pools = new GArray();
        public int _pool_i = 0;
        public GArray _drops = new GArray();                     // {mi, p: Vector3, v: Vector3, size}
        public int _drop_i = 0;
        public int _blood_layer = 0;

        public static ImageTexture _BloodTexture(int seed_v, bool pool)
        {
            return ImageTexture.CreateFromImage(_BloodImage(seed_v, pool));
        }

        public static Image _BloodImage(int seed_v, bool pool)
        {
            var n = 128;
            var img = Image.Create(n, n, false, ImageFormat.RGBA8);
            var rng = new Rng();
            rng.Seed = (ulong)seed_v;
            var c = new Vector2(n, n) * 0.5;
            var phases = new List<double[]>();
            for (int k = 0; k < 6; k++)
                phases.Add(new double[] { rng.Randf() * GD.TAU, rng.RandfRange(0.04, 0.12) * (pool ? 0.4 : 1.0), 2 + k * (pool ? 1 : 2) });
            var base_r = n * (pool ? 0.36 : 0.26);
            var drops = new List<(Vector2, double)>();
            if (!pool)
            {
                int nd = rng.RandiRange(5, 9);
                for (int k = 0; k < nd; k++)
                {
                    var ang = rng.Randf() * GD.TAU;
                    var dist = base_r * rng.RandfRange(1.15, 1.7);
                    drops.Add((c + new Vector2(Math.Cos(ang), Math.Sin(ang)) * dist, rng.RandfRange(1.6, 4.5)));
                }
            }
            for (int y = 0; y < n; y++)
            {
                for (int x = 0; x < n; x++)
                {
                    var p = new Vector2(x + 0.5, y + 0.5);
                    var d = p - c;
                    var ang = Math.Atan2(d.y, d.x);
                    var r = base_r;
                    foreach (var ph in phases)
                        r *= 1.0 + ph[1] * Math.Sin(ang * ph[2] + ph[0]);
                    var a = GD.Clampf((r - d.Length()) / 1.6, 0.0, 1.0);
                    foreach (var dr in drops)
                        a = GD.Maxf(a, GD.Clampf((dr.Item2 - p.DistanceTo(dr.Item1)) / 1.2, 0.0, 1.0));
                    // a little darker toward the middle, where it's thicker
                    var shade = 1.0 - 0.25 * GD.Clampf(1.0 - d.Length() / GD.Maxf(r, 1.0), 0.0, 1.0);
                    img.SetPixel(x, y, new Color(shade, shade, shade, a));
                }
            }
            return img;
        }

        public StandardMaterial3D _BloodMat(Texture2D tex)
        {
            var m = new StandardMaterial3D();
            m.AlbedoTexture = tex;
            m.AlbedoColor = BLOOD_COL;
            m.Transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
            m.Roughness = 0.22;                     // wet
            m.MetallicSpecular = 0.6;
            m.CullMode = BaseMaterial3D.CULL_BACK;
            return m;
        }

        public void _BuildBlood()
        {
            if (_blood_tex.IsEmpty())
            {
                for (int k = 0; k < 4; k++)
                    _blood_tex.Append(Var.Of(_BloodTexture(71 + k * 13, false)));
                _blood_tex.Append(Var.Of(_BloodTexture(503, true)));
            }
            var quad = new PlaneMesh();
            quad.Size = new Vector2(1.0, 1.0);
            for (int k = 0; k < SPLAT_MAX; k++)
            {
                var mi = new MeshInstance3D();
                mi.Mesh = quad;
                mi.MaterialOverride = _BloodMat(_blood_tex[k % 4].As<Texture2D>());
                mi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
                mi.Visible = false;
                AddChild(mi);
                _splats.Append(GDict.Of("mi", mi, "born", -999.0, "life", SPLAT_LIFE, "r0", 1.0, "r1", 1.0, "grow", 0.0));
            }
            for (int k = 0; k < POOL_MAX; k++)
            {
                var mi = new MeshInstance3D();
                mi.Mesh = quad;
                mi.MaterialOverride = _BloodMat(_blood_tex[4].As<Texture2D>());
                mi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
                mi.Visible = false;
                AddChild(mi);
                _pools.Append(GDict.Of("mi", mi, "born", -999.0, "life", POOL_LIFE, "r0", 0.2, "r1", 1.0, "grow", 3.0));
            }
            var dm = new SphereMesh();
            dm.Radius = 0.045;
            dm.Height = 0.09;
            dm.RadialSegments = 6;
            dm.Rings = 3;
            var dmat = new StandardMaterial3D();
            dmat.AlbedoColor = BLOOD_COL;
            dmat.Roughness = 0.25;
            dm.Material = dmat;
            for (int k = 0; k < DROP_MAX; k++)
            {
                var mi = new MeshInstance3D();
                mi.Mesh = dm;
                mi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
                mi.Visible = false;
                AddChild(mi);
                _drops.Append(GDict.Of("mi", mi, "p", Vector3.ZERO, "v", Vector3.ZERO, "size", 0.2, "on", false));
            }
        }

        public void _BloodMark(GArray list, int idx, Vector2 p, double radius, double grow, double life)
        {
            // Lay one mark flat on the ground at p (not on the river).
            if (Sim.WaterDepth(p) > 0.05)
                return;
            GDict m = list[idx].D;
            MeshInstance3D mi = m["mi"].As<MeshInstance3D>();
            _blood_layer = (_blood_layer + 1) % 40;
            mi.Position = new Vector3(p.x, Sim.HeightAt(p) + 0.02 + _blood_layer * 0.0006, p.y);
            mi.Rotation = new Vector3(0.0, GD.Randf() * GD.TAU, 0.0);
            m["born"] = _time;
            m["life"] = life;
            m["r1"] = radius;
            m["r0"] = radius * (grow > 0.0 ? 0.2 : 1.0);
            m["grow"] = grow;
            mi.Scale = Vector3.ONE * ((double)m["r0"] * 2.0);
            (mi.MaterialOverride as StandardMaterial3D).AlbedoColor = BLOOD_COL;
            if (!mi.Visible || !_marks_live.Has(m))
                _marks_live.Append(m);                     // 0.31.219: _sync_blood steps only the marks on the ground
            mi.Visible = true;
        }

        public void BloodHit(Vector2 target, Vector2 from, double dmg)
        {
            if (_splats.IsEmpty())
                return;
            var away = target.DistanceTo(from) > 0.05 ? (target - from).Normalized() : Vector2.FromAngle(GD.Randf() * GD.TAU);
            var amt = GD.Clampf(dmg / 40.0, 0.35, 1.6);
            var sp = target + away * GD.RandfRange(0.35, 0.8) + new Vector2(GD.RandfRange(-0.2, 0.2), GD.RandfRange(-0.2, 0.2));
            _BloodMark(_splats, _splat_i, sp, GD.RandfRange(0.45, 0.68) * (0.7 + amt * 0.5), 0.0, SPLAT_LIFE);
            _splat_i = (_splat_i + 1) % SPLAT_MAX;
            var y0 = Sim.HeightAt(target) + 1.0;
            for (int k = 0; k < (int)(3 + amt * 3); k++)
            {
                GDict d = _drops[_drop_i].D;
                _drop_i = (_drop_i + 1) % DROP_MAX;
                var dir2 = away.Rotated(GD.RandfRange(-0.7, 0.7));
                d["p"] = new Vector3(target.x, y0 + GD.RandfRange(-0.2, 0.3), target.y);
                d["v"] = new Vector3(dir2.x, 0.0, dir2.y) * GD.RandfRange(1.5, 3.8) + new Vector3(0.0, GD.RandfRange(1.0, 2.8), 0.0);
                d["size"] = GD.RandfRange(0.13, 0.24);
                d["g"] = y0 - 1.0;                           // 0.31.160: the ground under the hit, looked up once (they land within ~2 m)
                d["on"] = true;
                _drops_any = true;
                d["mi"].As<MeshInstance3D>().Position = d["p"].AsVec3();
                d["mi"].As<MeshInstance3D>().Visible = true;
            }
        }

        public void BloodPool(Vector2 p)
        {
            if (_pools.IsEmpty())
                return;
            _BloodMark(_pools, _pool_i, p, GD.RandfRange(1.45, 1.8), 3.0, POOL_LIFE);
            _pool_i = (_pool_i + 1) % POOL_MAX;
        }

        // 0.31.219 (Kevin's 0.31.218 log: the view ~8 ms a frame on his phone): only the drops in the air and the marks on the
        // ground are stepped -- all 60 drops and 114 marks were gone through every frame, most of them unused
        public bool _drops_any = false;
        public GArray _marks_live = new GArray();

        public void _SyncBlood(double dt)
        {
            if (_drops_any)
            {
                var flying = 0;
                foreach (var dv in _drops)
                {
                    GDict d = dv.D;
                    if (!(bool)d["on"])
                        continue;
                    d["v"] = d["v"].AsVec3() + new Vector3(0.0, -9.8, 0.0) * dt;
                    d["p"] = d["p"].AsVec3() + d["v"].AsVec3() * dt;
                    if (d["p"].AsVec3().y <= (double)d.Get("g", 0.0) + 0.03)
                    {
                        d["on"] = false;
                        d["mi"].As<MeshInstance3D>().Visible = false;
                        _BloodMark(_splats, _splat_i, new Vector2(d["p"].AsVec3().x, d["p"].AsVec3().z), (double)d["size"], 0.0, SPLAT_LIFE * 0.8);
                        _splat_i = (_splat_i + 1) % SPLAT_MAX;
                    }
                    else
                    {
                        flying += 1;
                        d["mi"].As<MeshInstance3D>().Position = d["p"].AsVec3();
                    }
                }
                _drops_any = flying > 0;
            }
            for (int i = _marks_live.Size() - 1; i > -1; i--)
            {
                GDict m = _marks_live[i].D;
                MeshInstance3D mi = m["mi"].As<MeshInstance3D>();
                if (!GD.IsInstanceValid(mi) || !mi.Visible)
                {
                    _marks_live.RemoveAt(i);
                    continue;
                }
                double age = _time - (double)m["born"];
                if (age > (double)m["life"] + BLOOD_FADE)
                {
                    mi.Visible = false;
                    _marks_live.RemoveAt(i);
                    continue;
                }
                if ((double)m["grow"] > 0.0 && age < (double)m["grow"])
                {
                    var k = 1.0 - Math.Pow(1.0 - age / (double)m["grow"], 3.0);          // spreads fast, then slows
                    mi.Scale = Vector3.ONE * GD.Lerpf((double)m["r0"], (double)m["r1"], k) * 2.0;
                }
                if (age > (double)m["life"])
                {
                    var c = BLOOD_COL;
                    c.a = (float)(1.0 - (age - (double)m["life"]) / BLOOD_FADE);
                    (mi.MaterialOverride as StandardMaterial3D).AlbedoColor = c;
                }
            }
        }

        // ---------- world ----------
        public int _hq_cached = -1;
        public static bool _cast_static = false;     // for the static make_body: set from _hq() before any unit is built

        public bool _Hq()
        {
            // High-quality graphics, except under the software renderer this project is built and tested with (it hung
            // on shadow-casting Kings in the full scene): there only when FB_FORCE_HQ is set, to check the look. Cached.
            if (_hq_cached < 0)
            {
                var soft = RenderingServer.GetVideoAdapterName().ToLowerInvariant().Contains("llvmpipe");
                _hq_cached = hq_gfx && (!soft || OS.HasEnvironment("FB_FORCE_HQ")) ? 1 : 0;
            }
            return _hq_cached == 1;
        }

        public ShadowCastingSetting _Cast()
        {
            // Solid things (castles, buildings, blocks, iron bars, units) cast shadows in high quality; ground, water,
            // grass, decals and effects never do (they only receive).
            return _Hq() ? GeometryInstance3D.SHADOW_CASTING_SETTING_ON : GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
        }

        public const int SHADOW_QUALITY = RenderingServer.SHADOW_QUALITY_HARD;

        public void _ApplyHq(Environment env, DirectionalLight3D sun)
        {
            // Round 30 (Kevin: "increase the graphical fidelity -- lighting, shadows"). The Mobile renderer has no SSAO,
            // SSR or GI, so: real sun shadows (castles, buildings, trees, units, Kings; grass and flowers stay out),
            // a warm sun against cool sky-blue shade instead of flat grey, a subtle glow on the brightest highlights
            // (low glow levels only: the cheap passes), and 2x MSAA (cheap on tile-based phone GPUs).
            sun.ShadowEnabled = true;
            // One shadow pass reaching the top of the screen (Round 36, Kevin: "I don't see shadows from trees"). The camera
            // is 38 m up: the visible ground is 28 m deep at the bottom of the screen and ~70 m at the top, so 0.27.2's 45 m
            // left the upper half (field, trees, rocks, bridges) unshadowed. tests/battle_bench.gd with MSAA 2x: one pass to
            // 75 m costs +4 % over 45 m (two splits to 80 m +7 %) -- the 21 fps was MSAA 4x, not shadow reach.
            sun.DirectionalShadowMode = DirectionalLight3D.SHADOW_ORTHOGONAL;
            // 0.31.218 (Kevin: "Honor of kings gives me 120fps solid"): 50 m -- the landscape camera (0.31.216) is nearer: the
            // ground at the screen's far corners is ~34 m from it, so 75 m drew the shadows of everything up to 40 m past the
            // screen (half the shadow pass's triangles at the middle lane; and the map's 2048 px spread over it)
            sun.DirectionalShadowMaxDistance = 50.0;
            sun.ShadowBias = 0.03;
            sun.ShadowNormalBias = 1.1;
            sun.ShadowBlur = 1.3;
            sun.ShadowOpacity = 1.0;
            // Rebalanced so shadows read: the ambient fill was tuned for a shadowless world (about as strong as the sun,
            // so a shadow only removed half the light and the tonemap flattened it). Less fill, more sun: sunlit ground
            // about as bright as before, shade ~40 % of it, tinted cool blue.
            sun.LightEnergy = 1.45;
            RenderingServer.DirectionalShadowAtlasSetSize(2048, true);
            // 0.31.222 (Kevin's phone, gpu_probe.gd: the soft filter cost ~6 fps in a lane fight -- every lit pixel sampling the
            // shadow map several times; Kevin: "Hard-edged shadows"): one sample, the hardware's 2x2 blend at the edge
            RenderingServer.DirectionalSoftShadowFilterSetQuality(SHADOW_QUALITY);
            env.AmbientLightColor = new Color("#a9bcd8");
            env.AmbientLightEnergy *= 0.75;
            env.GlowEnabled = true;
            for (int i = 0; i < 7; i++)
                env.SetGlowLevel(i, i == 1 || i == 2);
            env.GlowIntensity = 0.6;
            env.GlowStrength = 0.95;
            env.GlowBloom = 0.04;
            env.GlowHdrThreshold = 0.95;
            env.GlowBlendMode = Environment.GLOW_BLEND_MODE_SOFTLIGHT;
            env.AdjustmentSaturation = 1.12 * VULKAN_SATURATION;
            env.AdjustmentContrast = 1.08 * VULKAN_CONTRAST;
            env.TonemapExposure *= 1.05;                // the shade costs ~6 % mean brightness: give it back
        }

        public void _BuildLighting()
        {
            _cast_static = _Hq();
            var env = new Environment();
            // A real sky (0.19.4, Kevin: "there needs to be a sky, mainly for the trailer"). Background only:
            // ambient stays a flat colour and reflections are off, so lighting on the field is unchanged and
            // no radiance map is computed.
            var sky_mat = new ProceduralSkyMaterial();
            sky_mat.SkyTopColor = new Color("#3a79c8");
            sky_mat.SkyHorizonColor = new Color("#bcd8ea");
            sky_mat.SkyCurve = 0.12;
            // Below the horizon = the fog colour: wherever no land is drawn it reads as distant haze, never
            // as a grey patch.
            sky_mat.GroundHorizonColor = new Color("#b3cfe1");
            sky_mat.GroundBottomColor = new Color("#b3cfe1");
            sky_mat.SunAngleMax = 24.0;
            var sky = new Sky();
            sky.SkyMaterial = sky_mat;
            sky.RadianceSize = Sky.RADIANCE_SIZE_32;
            env.BackgroundMode = Environment.BG_SKY;
            env.Sky = sky;
            env.ReflectedLightSource = Environment.REFLECTION_SOURCE_DISABLED;
            env.AmbientLightSource = Environment.AMBIENT_SOURCE_COLOR;
            env.AmbientLightColor = new Color("#c3c9c4");
            env.AmbientLightEnergy = 0.5 * VULKAN_AMBIENT;
            env.TonemapMode = Environment.TONE_MAPPER_FILMIC;
            // Vulkan/Mobile lights in linear space and read darker than the old OpenGL render with the same settings; the
            // multipliers keep the look Kevin picked (0.31.71).
            env.TonemapExposure = 0.84 * VULKAN_EXPOSURE;
            env.TonemapWhite = 3.0;
            // More colourful, like the Fat Princess references (Kevin, Round 7b).
            env.AdjustmentEnabled = true;
            env.AdjustmentSaturation = 1.08 * VULKAN_SATURATION;
            env.AdjustmentContrast = 1.04 * VULKAN_CONTRAST;
            env.FogEnabled = true;
            env.FogLightColor = new Color("#b3cfe1");      // the sky's horizon: distant hills fade into it
            env.FogMode = Environment.FOG_MODE_DEPTH;
            // 0.31.14 atmosphere (Kevin: "more atmosphere ... better lighting"): the haze starts nearer (aerial depth over the far
            // side of the field), scatters warm towards the sun, and settles a little in the low ground (river, gorges).
            env.FogDepthBegin = 48.0;
            env.FogDepthEnd = 270.0;                  // the land ends at ~300 m: fully fogged there, so no rim shows
            env.FogDensity = 0.9;
            env.FogSunScatter = 0.22;
            env.FogHeight = -0.2;
            env.FogHeightDensity = 0.05;
            env.FogSkyAffect = 0.0;                   // the sky itself stays clear
            // No glow in battle (0.14.3): it is full-screen blur passes at native resolution (~7 % of the
            // frame in tests/perf_bench.gd, and bandwidth-heavy on phones) for a bloom too faint to see.
            env.GlowEnabled = false;
            var we = new WorldEnvironment();
            we.Environment = env;
            AddChild(we);
            var sun = new DirectionalLight3D();
            sun.LightColor = new Color("#ffdfb4");         // warmer (0.31.14), against the cool sky ambient
            sun.LightEnergy = 1.08;
            sun.RotationDegrees = new Vector3(-47, -33, 0);  // a little lower: longer, softer shadows give the ground depth
            // No real-time shadows: at this zoom they doubled every triangle for little visual gain.
            // Units are marked by team rings; HP bars are drawn on the 2D HUD.
            sun.ShadowEnabled = false;
            if (_Hq())
                _ApplyHq(env, sun);
            AddChild(sun);
            // Single directional light: the Compatibility renderer can add a per-object pass for each extra
            // directional light, so the old cool fill light is folded into ambient instead.
            camera = new Camera3D();
            camera.Fov = CAM_FOV;
            camera.Near = 0.3;
            camera.Far = 190.0;
            AddChild(camera);
        }

        public GDict _MeshOf(string path)
        {
            var packed = Stage.Scene(path);
            if (packed == null)
                return new GDict();
            var holder = packed.Instantiate();
            var found = holder.FindChildren("*", "MeshInstance3D", true, false);
            var output = new GDict();
            if (found.Count != 0)
            {
                MeshInstance3D mi = found[0] as MeshInstance3D;
                output = GDict.Of("mesh", Var.Of(mi.Mesh), "material", Var.Of(mi.GetActiveMaterial(0)));
            }
            holder.Free();
            return output;
        }

        public static GArray _terrain_meshes = new GArray();
        public static ShaderMaterial _terrain_mat = null;
        public const string PAINT = "res://assets/terrain/paint/";            // 0.31.216: the painted ground, plants and decals (tools/ground_paint.py)
        public static readonly Vector3 PAINT_TINT = new Vector3(0.66, 0.68, 0.70);
        public static ShaderMaterial _water_mat = null;

        public static ShaderMaterial _TerrainMaterial()
        {
            if (_terrain_mat == null)
            {
                var m = new ShaderMaterial();
                m.Shader = ResourceLoader.Load<Shader>("res://scripts/siege/terrain.gdshader");
                // 0.31.216 (Kevin: "use eleven to draw detailed paint on ground"): the ground ElevenLabs painted
                // (tools/ground_paint.py) -- two lawns, the lanes' flagstones, the jungle's earth, the cliff rock, the river bed
                m.SetShaderParameter("grass_tex", Stage.Texture(PAINT + "grass.webp"));
                m.SetShaderParameter("grass2_tex", Stage.Texture(PAINT + "grass2.webp"));
                m.SetShaderParameter("lane_tex", Stage.Texture(PAINT + "lane.webp"));
                m.SetShaderParameter("path_tex", Stage.Texture(PAINT + "dirt.webp"));
                m.SetShaderParameter("rock_tex", Stage.Texture(PAINT + "rock.webp"));
                m.SetShaderParameter("bed_tex", Stage.Texture(PAINT + "riverbed.webp"));
                m.SetShaderParameter("path_mask", ImageTexture.CreateFromImage(ResourceLoader.Load<Image>(Land.MASK_RES)));
                var br = Land.BakeRect();                          // (the C# sim's bake_rect(): (x, y, w, h))
                var r = new Rect2(br.x, br.y, br.w, br.h);
                m.SetShaderParameter("mask_rect", new Vector4(r.position.x, r.position.y, r.size.x, r.size.y));
                // The battle view's Vulkan compensation (exposure x1.55) brightens everything; a neutral darkening keeps the
                // painting's own colours (0.31.216: re-set for the painted ground; the Fat Princess grass took 0.64/0.73/0.80).
                m.SetShaderParameter("tint", PAINT_TINT);
                m.SetShaderParameter("grass_sat", 1.0);
                var mt = new NoiseTexture2D();
                mt.Width = 256;
                mt.Height = 256;
                mt.Seamless = true;
                var fn = new FastNoiseLite();
                fn.Frequency = 0.012;
                fn.FractalOctaves = 3;
                mt.Noise = fn;
                m.SetShaderParameter("macro_tex", mt);
                m.SetShaderParameter("cloud_tex", _Clouds());
                m.SetShaderParameter("cloud_strength", _cast_static ? CLOUD_STRENGTH : 0.0);
                _terrain_mat = m;
            }
            return _terrain_mat;
        }

        // ---------- the land beyond the playfield (0.19.4) ----------
        public static GArray _outer_meshes = new GArray();
        public static ShaderMaterial _outer_mat = null;
        public static readonly double[] OUTER_RINGS = { -1.0, 0.0, 2.0, 5.0, 9.0, 14.0, 21.0, 30.0, 42.0, 58.0, 80.0, 110.0, 150.0, 200.0, 260.0 };
        // (0.31.173: the outer woods are Foliage.OUTER_TREES -- the light *_far copies of the Meshy trees; were KayKit's
        // Tree_1_A / 2_A / 4_A)

        public static List<(Vector2, Vector2)> _OuterSidePoints(int side)
        {
            // Points along one side of the baked rect, with their outward directions; each side also owns
            // the fan of directions around its first corner, so the four sides tile the ring.
            var br = Land.BakeRect();
            var r = new Rect2(br.x, br.y, br.w, br.h);
            var c = new[] { r.position, new Vector2(r.End.x, r.position.y), r.End, new Vector2(r.position.x, r.End.y) };
            var nrm = new[] { new Vector2(0, -1), new Vector2(1, 0), new Vector2(0, 1), new Vector2(-1, 0) };
            Vector2 a = c[side];
            Vector2 b = c[(side + 1) % 4];
            Vector2 n = nrm[side];
            Vector2 prev = nrm[(side + 3) % 4];
            var pts = new List<(Vector2, Vector2)>();
            for (int k = 0; k < 6; k++)                                   // corner fan from the previous side's normal to ours
                pts.Add((a, prev.Slerp(n, k / 6.0).Normalized()));
            var len = a.DistanceTo(b);
            var steps = (int)Math.Ceiling(len / 2.0);
            for (int k = 0; k < steps + 1; k++)
                pts.Add((a.Lerp(b, (double)k / steps), n));
            return pts;
        }

        public static GArray _MakeOuterMeshes()
        {
            var output = new GArray();
            for (int side = 0; side < 4; side++)
            {
                var pts = _OuterSidePoints(side);
                var np = pts.Count;
                var verts = new List<Vector3>();
                var norms = new List<Vector3>();
                var idx = new List<int>();
                for (int ring = 0; ring < OUTER_RINGS.Length; ring++)
                {
                    double d = OUTER_RINGS[ring];
                    foreach (var pt in pts)
                    {
                        Vector2 p = pt.Item1 + pt.Item2 * d;
                        // The first ring tucks 1 m under the terrain's edge so no crack can show.
                        double y = d <= 0.0 ? Land.TerrainHeight(pt.Item1) - 0.06 : Land.OuterHeight(p);
                        verts.Add(new Vector3(p.x, y, p.y));
                        var e = 1.0;
                        var hx = Land.OuterHeight(p + new Vector2(e, 0)) - Land.OuterHeight(p - new Vector2(e, 0));
                        var hz = Land.OuterHeight(p + new Vector2(0, e)) - Land.OuterHeight(p - new Vector2(0, e));
                        norms.Add(new Vector3(-hx, 2.0 * e, -hz).NormalizedChecked());
                    }
                }
                for (int ring = 0; ring < OUTER_RINGS.Length - 1; ring++)
                {
                    for (int k = 0; k < np - 1; k++)
                    {
                        var a = ring * np + k;
                        var b = a + np;
                        // Every side runs the same way round the map with rings going outward, so one winding
                        // faces up on all four. (0.19.4 special-cased sides 1 and 2 the wrong way round: they
                        // were culled and the sky's grey underside showed through -- Kevin's screenshots.)
                        idx.AddRange(new[] { a, b, a + 1, a + 1, b, b + 1 });
                    }
                }
                var arr = new GArray();
                arr.Resize(Mesh.ARRAY_MAX);
                arr[Mesh.ARRAY_VERTEX] = Var.Of(verts);
                arr[Mesh.ARRAY_NORMAL] = Var.Of(norms);
                arr[Mesh.ARRAY_INDEX] = Var.Of(idx);
                var am = new ArrayMesh();
                am.AddSurfaceFromArrays(Mesh.PRIMITIVE_TRIANGLES, arr);
                output.Append(Var.Of(am));
            }
            return output;
        }

        public void _BuildOuterLand()
        {
            if (_outer_meshes.IsEmpty())
                _outer_meshes = _MakeOuterMeshes();
            if (_outer_mat == null)
            {
                ShaderMaterial tm = _TerrainMaterial();
                _outer_mat = new ShaderMaterial();
                _outer_mat.Shader = ResourceLoader.Load<Shader>("res://scripts/siege/outer_land.gdshader");
                foreach (var k in new[] { "grass_tex", "rock_tex", "path_mask", "mask_rect", "grass_scale", "rock_scale", "tint", "grass_sat",
                        "cloud_tex", "cloud_strength", "macro_tex", "rock_col" })
                    _outer_mat.SetShaderParameter(k, tm.GetShaderParameter(k));
            }
            foreach (var m in _outer_meshes)
            {
                var mi = new MeshInstance3D();
                mi.Mesh = m.As<Mesh>();
                mi.MaterialOverride = _outer_mat;
                mi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
                mi.SetMeta("perf", "outer_land");
                AddChild(mi);
            }
            _BuildOuterTrees();
        }

        public static GDict _outer_trees = new GDict();      // "side:type" -> Array[Transform3D]: planned once (or from the baked cache)

        public static GDict _PlanOuterTrees()
        {
            // Groves in the meadows and on the lower hills, batched per side and tree type. Not in the river, not on steep or
            // high ground. Deterministic (seed 911), so tools/bake_land.gd bakes the plan into the start-up cache (0.31.78: the
            // 9,000 tries cost ~90 ms of every match start).
            var br = Land.BakeRect();
            var r = new Rect2(br.x, br.y, br.w, br.h);
            var rng = new Rng();
            rng.Seed = 911;
            var per = new GDict();
            var placed = 0;
            var tries = 0;
            while (placed < 420 && tries < 9000)             // 260 until 0.31.12: the valley's hills get their woods too
            {
                tries += 1;
                var d = 2.0 + Math.Pow(rng.Randf(), 1.7) * 150.0;           // denser near the playfield
                var side = (int)(rng.Randi() % 4);
                if (side == 1 && rng.Randf() < 0.5)
                    d = 30.0 + rng.Randf() * 190.0;                      // the valley beyond the cliff side: woods all the way up
                var along = rng.Randf();
                Vector2 q;
                Vector2 n;
                switch (side)
                {
                    case 0: q = new Vector2(GD.Lerpf(r.position.x, r.End.x, along), r.position.y); n = new Vector2(0, -1); break;
                    case 1: q = new Vector2(r.End.x, GD.Lerpf(r.position.y, r.End.y, along)); n = new Vector2(1, 0); break;
                    case 2: q = new Vector2(GD.Lerpf(r.End.x, r.position.x, along), r.End.y); n = new Vector2(0, 1); break;
                    default: q = new Vector2(r.position.x, GD.Lerpf(r.End.y, r.position.y, along)); n = new Vector2(-1, 0); break;
                }
                var p = q + n * d + new Vector2(n.y, -n.x) * rng.RandfRange(-6.0, 6.0);
                // Groves, not an even carpet.
                if (Math.Sin(p.x * 0.09 + 1.1) * Math.Sin(p.y * 0.08 + 0.3) + rng.Randf() * 0.6 < 0.25)
                    continue;
                if (Math.Abs(p.y - Land.RiverC(p.x)) < Land.RIVER_HW + 4.0)
                    continue;
                var h = Land.OuterHeight(p);
                var slope = Math.Abs(Land.OuterHeight(p + new Vector2(1, 0)) - Land.OuterHeight(p - new Vector2(1, 0)))
                    + Math.Abs(Land.OuterHeight(p + new Vector2(0, 1)) - Land.OuterHeight(p - new Vector2(0, 1)));
                if (h > 22.0 || slope > 1.4 || p.DistanceTo(q) < 1.5)
                    continue;
                var kind = Foliage.Pick(rng, Foliage.OUTER_TREES) + "_far";          // (0.31.173: was one of three KayKit trees)
                var sc = rng.RandfRange(0.6, 1.0);
                var xf = new Transform3D(new Basis(Vector3.UP, rng.Randf() * GD.TAU).Scaled(Vector3.ONE * sc), new Vector3(p.x, h - 0.1, p.y));
                var key = GD.Fmt("%d:%s", side, kind);
                if (!per.Has(key))
                    per[key] = new GArray();
                per[key].A.Append(xf);
                placed += 1;
            }
            return per;
        }

        public void _BuildOuterTrees()
        {
            // The woods beyond the field: the light *_far trees, one MultiMesh per kind and 24 m square (0.31.173: was one per
            // side and kind -- a whole side drawn when any of it was on screen).
            if (_outer_trees.IsEmpty())
                _outer_trees = _PlanOuterTrees();
            var per = new GDict();
            foreach (var key in _outer_trees)
            {
                var kind = GD.Str(key).Split(":")[1];
                if (!per.Has(kind))
                    per[kind] = new GArray();
                per[kind].A.AppendArray(_outer_trees[key].A);
            }
            foreach (var kind in per)
                _PlantBatch(kind.AsString(), per[kind].A, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "outer_trees", 24.0);
        }

        public static GArray _MakeTerrainMeshes()
        {
            // One mesh per 32 m square (tight AABBs -> off-screen squares are culled; 0.31.216: squares, the yawed landscape
            // camera sees a diagonal of the map -- 32 m bands across its whole width until then), vertices every BAKE_STEP
            // metres straight from the baked height map, normals by central differences.
            Image img = ResourceLoader.Load<Image>(Land.HEIGHT_RES);
            var nx = img.GetWidth();
            var nz = img.GetHeight();
            var h = img.GetData().ToFloat32Array();
            var br = Land.BakeRect();
            var r = new Rect2(br.x, br.y, br.w, br.h);
            var st = Land.BAKE_STEP;
            var output = new GArray();
            var band = (int)(32.0 / st);
            var j0 = 0;
            while (j0 < nz - 1)
            {
                var j1 = GD.Mini(nz - 1, j0 + band);
                var i0 = 0;
                while (i0 < nx - 1)
                {
                    var i1 = GD.Mini(nx - 1, i0 + band);
                    var cols = i1 - i0 + 1;
                    var verts = new List<Vector3>();
                    var norms = new List<Vector3>();
                    var idx = new List<int>();
                    for (int j = j0; j < j1 + 1; j++)
                    {
                        for (int i = i0; i < i1 + 1; i++)
                        {
                            double y = h[j * nx + i];
                            verts.Add(new Vector3(r.position.x + i * st, y, r.position.y + j * st));
                            double hl = h[j * nx + GD.Maxi(i - 1, 0)];
                            double hr = h[j * nx + GD.Mini(i + 1, nx - 1)];
                            double hd = h[GD.Maxi(j - 1, 0) * nx + i];
                            double hu = h[GD.Mini(j + 1, nz - 1) * nx + i];
                            norms.Add(new Vector3(hl - hr, 2.0 * st, hd - hu).NormalizedChecked());
                        }
                    }
                    for (int jj = 0; jj < j1 - j0; jj++)
                    {
                        for (int ii = 0; ii < cols - 1; ii++)
                        {
                            var a = jj * cols + ii;
                            idx.AddRange(new[] { a, a + 1, a + cols, a + 1, a + cols + 1, a + cols });
                        }
                    }
                    var arr = new GArray();
                    arr.Resize(Mesh.ARRAY_MAX);
                    arr[Mesh.ARRAY_VERTEX] = Var.Of(verts);
                    arr[Mesh.ARRAY_NORMAL] = Var.Of(norms);
                    arr[Mesh.ARRAY_INDEX] = Var.Of(idx);
                    var am = new ArrayMesh();
                    am.AddSurfaceFromArrays(Mesh.PRIMITIVE_TRIANGLES, arr);
                    output.Append(Var.Of(am));
                    i0 = i1;
                }
                j0 = j1;
            }
            return output;
        }

        public void _BuildTerrain()
        {
            // Round 7: a single height-mapped ground (grass, herringbone paths, rock ledges) built from the
            // baked landscape; cached for the session so rematches don't rebuild it.
            if (_terrain_meshes.IsEmpty())
                _terrain_meshes = _MakeTerrainMeshes();
            foreach (var m in _terrain_meshes)
            {
                var mi = new MeshInstance3D();
                mi.Mesh = m.As<Mesh>();
                mi.MaterialOverride = _TerrainMaterial();
                mi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
                mi.SetMeta("perf", "terrain");
                AddChild(mi);
            }
            _BuildWater();
        }

        public void _BuildWater()
        {
            _water_mat = null;                 // rebuilt per match: the High-quality setting may have changed
            if (_Hq())
            {
                _water_mat = _WaterHqMaterial();
                _BuildRipples();
            }
            if (_water_mat == null)
            {
                var sh = new Shader();
                sh.Code = GDSHADER_L1245;
                var m = new ShaderMaterial();
                m.Shader = sh;
                var nt = new NoiseTexture2D();
                nt.Width = 256;
                nt.Height = 256;
                nt.Seamless = true;
                var fn = new FastNoiseLite();
                fn.Frequency = 0.04;
                nt.Noise = fn;
                m.SetShaderParameter("ripples", nt);
                m.SetShaderParameter("glint", _cast_static ? 1.3 : 0.0);
                _water_mat = m;
            }
            // The river runs on out of the map both ways (0.19.4; 0.31.13: no more waterfall -- the east is a valley like the west).
            var x0 = -Sim.HALF_W - Land.BAKE_MARGIN - Land.OUTER_REACH;
            var x1 = Sim.HALF_W + Land.BAKE_MARGIN + Land.OUTER_REACH;
            var span = 2.0 * (Sim.HALF_W + Land.BAKE_MARGIN);
            _WaterStrip(x0, x1, Land.WATER_Y, span, "water");
        }

        public void _WaterStrip(double xa, double xb, double y, double span, string tag)
        {
            var verts = new List<Vector3>();
            var uvs = new List<Vector2>();
            var uv2s = new List<Vector2>();
            var idx = new List<int>();
            var n = (int)Math.Ceiling(xb - xa);
            var rows = WATER_ROWS;
            for (int k = 0; k < n + 1; k++)
            {
                var x = GD.Minf(xa + k, xb);
                var c = Land.RiverC(x);
                var hw = Land.RiverHw(x) + 0.35;
                for (int r = 0; r < rows + 1; r++)
                {
                    var f = (double)r / (double)rows;
                    verts.Add(new Vector3(x, y, c - hw + 2.0 * hw * f));
                    uvs.Add(new Vector2((x - xa) / span, 0.5 + (2.0 * f - 1.0) * hw / RIP_ACROSS));
                    uv2s.Add(new Vector2(0.0, f));
                }
                if (k < n)
                {
                    for (int r = 0; r < rows; r++)
                    {
                        var a = k * (rows + 1) + r;
                        var b = a + rows + 1;
                        idx.AddRange(new[] { a, b, a + 1, a + 1, b, b + 1 });
                    }
                }
            }
            var arr = new GArray();
            arr.Resize(Mesh.ARRAY_MAX);
            arr[Mesh.ARRAY_VERTEX] = Var.Of(verts);
            arr[Mesh.ARRAY_TEX_UV] = Var.Of(uvs);
            arr[Mesh.ARRAY_TEX_UV2] = Var.Of(uv2s);
            arr[Mesh.ARRAY_INDEX] = Var.Of(idx);
            var am = new ArrayMesh();
            am.AddSurfaceFromArrays(Mesh.PRIMITIVE_TRIANGLES, arr);
            var mi = new MeshInstance3D();
            mi.Mesh = am;
            mi.MaterialOverride = _water_mat;
            mi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            mi.SetMeta("perf", tag);
            AddChild(mi);
        }

        // ---------- foliage: grass tufts + flowers (Round 7b) ----------
        // 44-triangle tufts only (Grass_1_B is 132 triangles; dropped in 0.14.2 for frame rate).
        public static readonly string[] TUFTS = { "Grass_1_A_Color1", "Grass_2_A_Color1" };
        public static readonly string[] FLOWERS = { "red", "blue", "yellow", "white" };
        public static GDict _foliage = new GDict();          // kind -> Array[Transform3D], built once per session

        public static bool _FoliageOk(Vector2 p, Image mask, List<Obstacle> obstacles, bool allow_slope = false)
        {
            if (Math.Abs(p.x) > Sim.HALF_W - 0.6 || Math.Abs(p.y) > Sim.HALF_L - 0.6)
                return false;
            if (Land.Shore(p) < 0.9 || Land.EdgeDist(p) > -0.9)
                return false;
            if (Land.KeepDist(p) < Keep.R + 1.5)
                return false;                          // (0.31.165: the keeps' floors)
            if (Land.InDungeonPit(p, 1.5))
                return false;                          // the dungeon wing's floor and walls (Kevin: grass on the floor)
            var br = Land.BakeRect();
            var r = new Rect2(br.x, br.y, br.w, br.h);
            var px = new Vector2i(GD.Clampi((int)((p.x - r.position.x) * Land.MASK_PPM), 0, mask.GetWidth() - 1),
                GD.Clampi((int)((p.y - r.position.y) * Land.MASK_PPM), 0, mask.GetHeight() - 1));
            var mk = mask.GetPixelv(px);
            if (mk.r > 0.46 || mk.a > 0.4)
                return false;                          // on a dirt path (0.31.126: R is 0.5 at the track's edge), on a lane's paving
            var rd = Land.RidgeDist(p);
            if (rd.x < rd.y + 1.1)
                return false;                          // (0.31.216) under a rock formation, which stands wider than its wall
            if (!allow_slope && mk.g > 0.3)
                return false;                          // on a ledge rim / cliff band
            foreach (var ob in obstacles)
            {
                if (p.DistanceTo(ob.p) < ob.r + 0.5)
                    return false;
            }
            return true;
        }

        public static Transform3D _FoliageXf(Vector2 p, Rng rng, double s0, double s1)
        {
            var y = Land.GroundHeight(p);                  // (ground_height(p, false): the C# sim's has no unused second argument)
            var b = new Basis(Vector3.UP, rng.Randf() * GD.TAU).Scaled(Vector3.ONE * rng.RandfRange(s0, s1));
            return new Transform3D(b, new Vector3(p.x, y - 0.03, p.y));
        }

        public GDict _PlanFoliage()
        {
            // 0.31.216 (Kevin: "need new models for grass"): the painted grass clumps and flower patches (ground_cards.gd) --
            // clumps lining both edges of every lane's paving, clusters across the fields and the jungle, flowers lying in the
            // grass. {kind: [Transform3D...], kind + "_c": [Color...] (INSTANCE_CUSTOM)}. Seeded: the same every match (and baked
            // into the start-up cache by tools/bake_land.gd). (KayKit's grass tufts and the Blender flowers until then.)
            var rng = new Rng();
            rng.Seed = 707;
            Image mask = ResourceLoader.Load<Image>(Land.MASK_RES);
            List<Obstacle> obs = sim.obstacles;
            List<Brush> brushes = new List<Brush>();
            if (sim.moba != null && sim.moba.vision != null)
                brushes = sim.moba.vision.brushes;
            var output = GDict.Of("blades", new GArray(), "blades_c", new GArray(), "flowers", new GArray(), "flowers_c", new GArray());
            Action<Vector2, double, double> clump = (p, s0, s1) =>
            {
                if (_FoliageOk(p, mask, obs) && !_InBrush(p, brushes, 0.3))
                {
                    output["blades"].Append(_FoliageXf(p, rng, s0, s1));
                    output["blades_c"].Append(GroundCards.Custom((int)(rng.Randi() % 8), rng));
                }
            };
            // 1. Both edges of every lane's paving: where the slabs stop (the mask's A just under 0.5) the grass grows long.
            foreach (var pl in Land.Paths())
            {
                for (int i = 0; i < pl.Count - 1; i++)
                {
                    Vector2 a = pl[i];
                    Vector2 b = pl[i + 1];
                    var d = (b - a).Normalized();
                    var n = new Vector2(-d.y, d.x);
                    foreach (var side in new[] { -1.0, 1.0 })
                    {
                        if (rng.Randf() < 0.7)
                        {
                            Vector2 q = a + d * rng.RandfRange(0.0, a.DistanceTo(b)) + n * side * (Land.LANE_PAVE_HALF + rng.RandfRange(0.1, 0.9));
                            clump(q, 0.75, 1.1);
                        }
                    }
                }
            }
            // 2. Clusters across the fields and the jungle.
            var area = Sim.HALF_W * Sim.HALF_L;
            for (int c = 0; c < (int)(area * 0.042); c++)
            {
                var cp = new Vector2(rng.RandfRange(-Sim.HALF_W, Sim.HALF_W), rng.RandfRange(-Sim.HALF_L, Sim.HALF_L));
                if (!Land.InsideField(cp))
                    continue;
                int nk = rng.RandiRange(3, 7);
                for (int k = 0; k < nk; k++)
                    clump(cp + new Vector2(rng.RandfRange(-1.1, 1.1), rng.RandfRange(-1.1, 1.1)), 0.6, 1.0);
            }
            // 3. Flower patches.
            for (int c = 0; c < (int)(area * 0.02); c++)
            {
                var fp = new Vector2(rng.RandfRange(-Sim.HALF_W, Sim.HALF_W), rng.RandfRange(-Sim.HALF_L, Sim.HALF_L));
                if (Land.InsideField(fp) && _FoliageOk(fp, mask, obs) && !_InBrush(fp, brushes, 0.6))
                {
                    var xf = _FoliageXf(fp, rng, 0.75, 1.15);
                    xf.origin.y = (float)(Land.TerrainHeight(fp) + 0.02);
                    output["flowers"].Append(xf);
                    output["flowers_c"].Append(GroundCards.Custom((int)(rng.Randi() % 9), rng));
                }
            }
            return output;
        }

        public static bool _InBrush(Vector2 p, List<Brush> brushes, double margin)
        {
            foreach (var b in brushes)
            {
                if (p.DistanceTo(b.p) < b.r + margin)
                    return true;
            }
            return false;
        }

        // (GroundCards = preload("res://scripts/siege/ground_cards.gd"))

        public void _BuildFoliage()
        {
            // One MultiMesh per kind and FOLIAGE_CELL square, so off-screen squares are culled (0.31.216: squares, not 32 m bands
            // across the whole map: the yawed camera sees a diagonal of the map).
            if (_foliage.IsEmpty() || !_foliage.Has("blades"))
                _foliage = _PlanFoliage();
            foreach (var kind in new[] { "blades", "flowers" })
            {
                GArray xfs = _foliage.Get(kind, new GArray()).A;
                GArray cs = _foliage.Get(kind + "_c", new GArray()).A;
                var cells = new GDict();
                for (int i = 0; i < xfs.Size(); i++)
                {
                    if (low_fx && i % 2 == 1)
                        continue;                                  // "Reduce effects": every other one
                    Vector3 o = ((Transform3D)xfs[i]).origin;
                    var key = new Vector2i((int)Math.Floor(o.x / FOLIAGE_CELL), (int)Math.Floor(o.z / FOLIAGE_CELL));
                    if (!cells.Has(key))
                        cells[key] = new GArray();
                    cells[key].Append(i);
                }
                foreach (var key in cells)
                {
                    GArray ids = cells[key].A;
                    var mm = new MultiMesh();
                    mm.TransformFormat = MultiMesh.TRANSFORM_3D;
                    mm.UseCustomData = true;
                    mm.Mesh = GroundCards.Mesh(kind);
                    mm.InstanceCount = ids.Size();
                    for (int j = 0; j < ids.Size(); j++)
                    {
                        mm.SetInstanceTransform(j, (Transform3D)xfs[(int)ids[j]]);
                        mm.SetInstanceCustomData(j, cs[(int)ids[j]].As<Color>());
                    }
                    var mmi = new MultiMeshInstance3D();
                    mmi.Multimesh = mm;
                    mmi.MaterialOverride = GroundCards.Material(kind, PAINT_TINT * CARD_LIGHT);
                    mmi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
                    mmi.SetMeta("perf", "foliage");
                    mmi.SetMeta("perf_kind", kind);
                    mmi.VisibilityRangeEnd = 70.0;
                    AddChild(mmi);
                }
            }
        }

        public const double FOLIAGE_CELL = 24.0;
        public const double CARD_LIGHT = 1.32;               // the painted cards stand in the light (the ground's tint is for a surface facing up)

        public static StandardMaterial3D _tuft_mat = null;
        public static ShaderMaterial _tuft_wind = null;
        public static Material _TuftMaterial(Material @base)
        {
            if (_cast_static)
            {
                // High-quality graphics: the tufts sway in rolling gusts (tips move, roots stay), lit per vertex like before.
                if (_tuft_wind == null)
                {
                    var sh = new Shader();
                    sh.Code = GDSHADER_L1459;
                    var m = new ShaderMaterial();
                    m.Shader = sh;
                    var sm = @base as StandardMaterial3D;
                    var col = new Color(1.0, 1.18, 0.82);
                    if (sm != null)
                    {
                        col = sm.AlbedoColor * new Color(1.0, 1.18, 0.82);
                        if (sm.AlbedoTexture != null)
                        {
                            m.SetShaderParameter("albedo_tex", sm.AlbedoTexture);
                            m.SetShaderParameter("use_tex", true);
                        }
                    }
                    m.SetShaderParameter("albedo_col", col);
                    _tuft_wind = m;
                }
                return _tuft_wind;
            }
            return _TuftMaterialPlain(@base);
        }

        public static StandardMaterial3D _TuftMaterialPlain(Material @base)
        {
            // Match the tufts to the terrain's green; per-vertex lighting (identical on tiny triangles,
            // cheaper per pixel on phones).
            if (_tuft_mat == null)
            {
                _tuft_mat = @base is StandardMaterial3D ? (StandardMaterial3D)(@base as StandardMaterial3D).Duplicate() : new StandardMaterial3D();
                _tuft_mat.AlbedoColor = new Color(1.0, 1.18, 0.82);
                _tuft_mat.ShadingMode = BaseMaterial3D.SHADING_MODE_PER_VERTEX;
                _tuft_mat.SpecularMode = BaseMaterial3D.SPECULAR_DISABLED;
            }
            return _tuft_mat;
        }

        public static GDict _flower_meshes = new GDict();
        public static Mesh _CheapFlowerMesh(Mesh mesh)
        {
            // The Blender flowers export double-sided; their petals are closed shapes, so back faces are
            // never seen: cull them, and light per vertex. A MultiMesh has no per-surface overrides, so
            // this is a cached copy of the mesh with the cheaper materials baked in.
            if (!_flower_meshes.Has(Var.Of(mesh)))
            {
                Mesh copy = mesh.Duplicate() as Mesh;
                for (int sidx = 0; sidx < copy.GetSurfaceCount(); sidx++)
                {
                    var @base = copy.SurfaceGetMaterial(sidx);
                    if (@base is StandardMaterial3D)
                    {
                        StandardMaterial3D m = (@base as StandardMaterial3D).Duplicate() as StandardMaterial3D;
                        m.CullMode = BaseMaterial3D.CULL_BACK;
                        m.ShadingMode = BaseMaterial3D.SHADING_MODE_PER_VERTEX;
                        m.SpecularMode = BaseMaterial3D.SPECULAR_DISABLED;
                        copy.SurfaceSetMaterial(sidx, m);
                    }
                }
                _flower_meshes[Var.Of(mesh)] = Var.Of(copy);
            }
            return _flower_meshes[Var.Of(mesh)].As<Mesh>();
        }

        // Whirlwind FX (Round 12, Kevin: "spin visuals like World of Warcraft"): two translucent blade-trail
        // ribbons (partial rings fading along their arc) circling the berserker at different heights and
        // tilts, spinning faster than the body; built once per unit, then only rotated (transform only).
        public GDict whirl_nodes = new GDict();
        public static ArrayMesh _whirl_mesh = null;
        public static StandardMaterial3D _whirl_mat = null;

        public static ArrayMesh _WhirlRibbon()
        {
            if (_whirl_mesh == null)
            {
                var st = new SurfaceTool();
                st.Begin(Mesh.PRIMITIVE_TRIANGLES);
                var seg = 28;
                var arc = GD.TAU * 0.72;
                for (int i = 0; i < seg; i++)
                {
                    var t0 = (double)i / seg;
                    var t1 = (double)(i + 1) / seg;
                    var pts = new List<(Vector3, Vector3, double)>();
                    foreach (var t in new[] { t0, t1 })
                    {
                        double ang = arc * t;
                        double fade = Math.Pow(t, 1.6);                  // bright at the leading edge
                        var inner = new Vector3(Math.Cos(ang), 0, Math.Sin(ang)) * 0.62;
                        var outer = new Vector3(Math.Cos(ang), 0, Math.Sin(ang)) * 1.0;
                        pts.Add((inner + new Vector3(0, -0.12, 0), outer + new Vector3(0, 0.12, 0), fade));
                    }
                    var a0 = pts[0];
                    var a1 = pts[1];
                    foreach (var v in new[] { (a0.Item1, a0.Item3), (a1.Item1, a1.Item3), (a1.Item2, a1.Item3), (a0.Item1, a0.Item3), (a1.Item2, a1.Item3), (a0.Item2, a0.Item3) })
                    {
                        st.SetColor(new Color(1, 1, 1, v.Item2));
                        st.AddVertex(v.Item1);
                    }
                }
                _whirl_mesh = st.Commit();
            }
            return _whirl_mesh;
        }

        public void _SyncWhirls()
        {
            if (_whirl_mat == null)
            {
                _whirl_mat = new StandardMaterial3D();
                _whirl_mat.ShadingMode = BaseMaterial3D.SHADING_MODE_UNSHADED;
                _whirl_mat.VertexColorUseAsAlbedo = true;
                _whirl_mat.AlbedoColor = new Color(0.92, 0.95, 1.0, 0.75);
                _whirl_mat.Transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
                _whirl_mat.BlendMode = BaseMaterial3D.BLEND_MODE_ADD;
                _whirl_mat.CullMode = BaseMaterial3D.CULL_DISABLED;
            }
            foreach (var u in sim.units)
            {
                Node3D fx = whirl_nodes.Get(u.id).As<Node3D>();
                if (!sim.Whirling(u))
                {
                    if (fx != null)
                        fx.Visible = false;
                    continue;
                }
                if (fx == null)
                {
                    fx = new Node3D();
                    for (int k = 0; k < 2; k++)
                    {
                        var mi = new MeshInstance3D();
                        mi.Mesh = _WhirlRibbon();
                        mi.MaterialOverride = _whirl_mat;
                        mi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
                        fx.AddChild(mi);
                    }
                    AddChild(fx);
                    whirl_nodes[u.id] = fx;
                }
                GDict a = actors.Get(u.id, new GDict()).D;
                if (a.IsEmpty() || !a["root"].As<Node3D>().Visible)
                {
                    fx.Visible = false;
                    continue;
                }
                fx.Visible = true;
                fx.Position = a["root"].As<Node3D>().Position;
                var r0 = fx.GetChild(0) as Node3D;
                var r1 = fx.GetChild(1) as Node3D;
                // Faster than the body (4 turns/s): ~7 and ~5.5 turns/s, tilted opposite ways.
                r0.Transform = new Transform3D(new Basis(Vector3.UP, -_time * 44.0).Rotated(Vector3.RIGHT, 0.18).Scaled(new Vector3(2.3, 1.0, 2.3)), new Vector3(0, 1.05, 0));
                r1.Transform = new Transform3D(new Basis(Vector3.UP, -_time * 34.0 + 2.0).Rotated(Vector3.RIGHT, -0.22).Scaled(new Vector3(2.7, 1.0, 2.7)), new Vector3(0, 0.6, 0));
            }
        }

        public GDict shield_nodes = new GDict();        // knight id -> translucent shield-wall panel
        public static StandardMaterial3D _shield_mat = null;

        public void _SyncShields()
        {
            // A translucent panel where the sim's shield segment is, while a knight blocks (transform only).
            if (_shield_mat == null)
            {
                _shield_mat = new StandardMaterial3D();
                _shield_mat.ShadingMode = BaseMaterial3D.SHADING_MODE_UNSHADED;
                _shield_mat.AlbedoColor = new Color(0.55, 0.8, 1.0, 0.32);
                _shield_mat.Transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
                _shield_mat.CullMode = BaseMaterial3D.CULL_DISABLED;
            }
            foreach (var u in sim.units)
            {
                if (u.cls != "knight")
                    continue;
                MeshInstance3D n = shield_nodes.Get(u.id).As<MeshInstance3D>();
                if (!sim.Blocking(u) || _Fogged(u))
                {
                    if (n != null)
                        n.Visible = false;
                    continue;
                }
                if (n == null)
                {
                    n = new MeshInstance3D();
                    var q = new QuadMesh();
                    q.Size = new Vector2(1.0, 1.6);
                    n.Mesh = q;
                    n.MaterialOverride = _shield_mat;
                    n.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
                    AddChild(n);
                    shield_nodes[u.id] = n;
                }
                Vector2[] sg = sim.ShieldSeg(u);
                Vector2 a2 = sg[0];
                Vector2 b2 = sg[1];
                var mid = (a2 + b2) * 0.5;
                var y = Sim.HeightAt(mid) + 0.85;
                var along = new Vector3(b2.x - a2.x, 0, b2.y - a2.y);
                n.Visible = true;
                n.Transform = new Transform3D(new Basis(along, Vector3.UP, along.NormalizedChecked().Cross(Vector3.UP)), new Vector3(mid.x, y, mid.y));
            }
        }

        public GDict beam_nodes = new GDict();          // priest unit id -> MeshInstance3D (unit-length cylinder)

        public static GDict _beam_mats = new GDict();

        public StandardMaterial3D _BeamMaterial(string key)
        {
            if (!_beam_mats.Has(key))
            {
                var m = new StandardMaterial3D();
                m.ShadingMode = BaseMaterial3D.SHADING_MODE_UNSHADED;
                m.AlbedoColor = GDict.Of("heal", new Color(1.0, 0.95, 0.55, 0.75), "drain", new Color(0.35, 1.0, 0.4, 0.85), "white", new Color(1.0, 1.0, 1.0, 0.85))[key].As<Color>();
                m.Transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
                m.BlendMode = BaseMaterial3D.BLEND_MODE_ADD;
                m.CullMode = BaseMaterial3D.CULL_DISABLED;
                _beam_mats[key] = Var.Of(m);
            }
            return _beam_mats[key].As<StandardMaterial3D>();
        }

        public GDict _beam_ids = new GDict();                              // units that have had a beam (their nodes may need hiding)

        public void _SyncBeams()
        {
            // The Priest's gold healing beam; the Necromancer's green drain on an enemy plus a white heal to an ally (0.31.2).
            foreach (var u in sim.units)
            {
                // 0.31.160: a unit with no beam that never had one: nothing to show or hide (this ran its two slots -- arrays,
                // strings, lookups -- for every unit, every frame)
                if (u.beam == "" && u.beam2 == "" && !_beam_ids.Has(u.id))
                    continue;
                _beam_ids[u.id] = true;
                bool necro = u.cls == "priest" && u.up;
                foreach (var slot in new[] { new[] { "beam", u.id, necro ? "drain" : "heal" }, new[] { "beam2", u.id + "#2", "white" } })
                {
                    MeshInstance3D n = beam_nodes.Get(slot[1]).As<MeshInstance3D>();
                    Unit to = sim.by_id.TryGetValue(V.Str(u.Get(slot[0])), out var tu) ? tu : null;      // (null: {})
                    if (slot[2] == "drain" || plasma_nodes.Has(slot[1]))
                    {
                        _SyncPlasma(slot[1], u, slot[2] == "drain" && sim.Alive(u) && !_Fogged(u) ? to : null);
                        if (slot[2] == "drain")
                            continue;
                    }
                    if (to == null || !sim.Alive(u) || _Fogged(u))
                    {
                        if (n != null)
                            n.Visible = false;
                        continue;
                    }
                    if (n == null)
                    {
                        n = new MeshInstance3D();
                        var cm = new CylinderMesh();
                        cm.TopRadius = 0.07;
                        cm.BottomRadius = 0.07;
                        cm.Height = 1.0;
                        cm.RadialSegments = 6;
                        cm.Rings = 1;
                        n.Mesh = cm;
                        n.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
                        AddChild(n);
                        beam_nodes[slot[1]] = n;
                    }
                    n.MaterialOverride = _BeamMaterial(slot[2]);
                    GDict a = actors.Get(u.id, new GDict()).D;
                    GDict b = actors.Get(to.id, new GDict()).D;
                    if (a.IsEmpty() || b.IsEmpty())
                    {
                        n.Visible = false;
                        continue;
                    }
                    Vector3 p0 = a["root"].As<Node3D>().Position + new Vector3(0, 1.35, 0) + new Vector3(Math.Sin(u.face), 0, Math.Cos(u.face)) * 0.35;
                    Vector3 p1 = b["root"].As<Node3D>().Position + new Vector3(0, 1.1, 0);
                    var len = p0.DistanceTo(p1);
                    if (len < 0.05)
                    {
                        n.Visible = false;
                        continue;
                    }
                    n.Visible = true;
                    // A unit cylinder along Y, stretched to the beam's length and aimed at the target; it flickers a little in width.
                    var up = (p1 - p0) / len;
                    var side = up.Cross(Math.Abs(up.Dot(Vector3.FORWARD)) < 0.95 ? Vector3.FORWARD : Vector3.RIGHT).NormalizedChecked();
                    var fwd = side.Cross(up);
                    var w = (slot[2] == "drain" ? 1.25 : 1.0) + 0.25 * Math.Sin(_time * 25.0 + (double)(GD.Hash(slot[1]) % 100));
                    n.Transform = new Transform3D(new Basis(side * w, up * len, fwd * w), (p0 + p1) * 0.5);
                }
            }
        }
    }
}
