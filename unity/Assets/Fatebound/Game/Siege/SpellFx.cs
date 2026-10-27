// Ported from godot/scripts/siege/spell_fx.gd (Fatebound 0.31.222).
using System;
using System.Collections;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector3 = Fatebound.Sim.Vec3;
using Color = Fatebound.GUI.Col;
using Transform3D = Fatebound.Sim.Xform3;
using AABB = Fatebound.Sim.Aabb;
using Material = Fatebound.GUI.GMaterial;

namespace Fatebound.Game
{
    using Sim = Fatebound.Sim.SiegeSim;
    using _Kits = Fatebound.Sim.MobaKits;

    // The abilities' effects (0.31.201, Kevin: "I want every ability to have much better special effects in the game. Every
    // one of them should have its own unique look and I want them especially the ultimates to look exciting"). A child of
    // siege_view.gd, which hands it every cast (cast / ult / q / event) and what lasts on heroes and on the ground (sync, each
    // frame); it builds each one from a few kinds of thing:
    //   - bursts and streams of sprites (GPU particles: the painted and the procedural sprites of assets/vfx, drawn by
    //     fx_sprite.gdshader in the spell's colour), rocks (mesh particles) and knives (boxes along their flight);
    //   - flashes (a sprite facing the camera, popping and going);
    //   - ground discs fitted to the terrain (fx_ground.gdshader: a soft disc, a turning sprite -- runes, cracks, rays, a
    //     swirl -- fire, lightning, dappled light), waves (the rim alone, running out), fans (a cone on the ground);
    //   - pillars, cones and sheets of light (fx_beam.gdshader: noise scrolling along them), beams between two points;
    //   - lightning (a jagged core with a glow, a branch or two);
    //   - shells round a hero (fx_shell.gdshader: a shield's bubble, a stone or bark skin, a fury's halo, a dome);
    //   - trails behind a dash, a thrown thing, a meteor.
    // Each hero's four abilities are their own recipe (cast, ult, q); what lasts -- shields, slows, marks, skins, parries,
    // poison, dashes, the ultimates' auras, the zones -- is held by key (_hold) and let go when the sim says it's over.
    // Everything is timed by the view's clock and stepped in step(); low_fx thins the particles and skips the extras.
    // (Port: the sim's events reach here as Ev (Fatebound.Sim's event records), its units as Unit, its zones as Zone and its
    // projectiles as Proj; the view's actors are its dictionaries (GDict). A _live entry's fn is an Action(node, u, age), a
    // hold's alive a Func<bool>, both kept in the entry's dictionary as GDScript keeps its Callables.)
    public class SpellFx : Node3D
    {
        public static readonly Shader SPRITE = ResourceLoader.Load<Shader>("res://scripts/siege/fx_sprite.gdshader");
        public static readonly Shader GROUND = ResourceLoader.Load<Shader>("res://scripts/siege/fx_ground.gdshader");
        public static readonly Shader BEAM = ResourceLoader.Load<Shader>("res://scripts/siege/fx_beam.gdshader");
        public static readonly Shader SHELL = ResourceLoader.Load<Shader>("res://scripts/siege/fx_shell.gdshader");
        public static readonly Shader SCORCH = ResourceLoader.Load<Shader>("res://scripts/siege/fx_scorch.gdshader");
        public static readonly GArray TEX_DIRS = GArray.Of("res://assets/vfx/spell/%s.png", "res://assets/vfx/weapon/%s.png", "res://assets/vfx/smoke/smoke_puff.png");

        public SiegeView view;                                 // siege_view.gd
        public double _time = 0.0;
        public GArray _live = new GArray();                    // [{node, t0, life, fn}] fn(node, u 0..1, age) each frame, freed at life
        public GDict _holds = new GDict();                     // key -> {nodes: [], alive: Callable, fade: [], until}

        public static GDict _tex = new GDict();
        public static GDict _mats = new GDict();               // shared sprite materials by key
        public static GDict _pms = new GDict();                // shared particle process materials by key
        public static GDict _meshes = new GDict();             // shared meshes by key
        public static StandardMaterial3D _rock_mat = null;

        // ---------- colours ----------
        public static readonly GDict HERO_COL = GDict.Of(
            "knight", GArray.Of("#ffd65a", "#bcd8ff"), "crusader", GArray.Of("#ffe9a6", "#fff6d8"), "barbarian", GArray.Of("#ff6a2a", "#ffb04a"),
            "berserker", GArray.Of("#ff2a2a", "#7a0c0c"), "rogue", GArray.Of("#a070ff", "#d8c8ff"), "assassin", GArray.Of("#8a5bff", "#2a1a4a"),
            "ranger", GArray.Of("#8fe36a", "#e8ffd0"), "sniper", GArray.Of("#bfefff", "#ffffff"), "mage", GArray.Of("#ff8a3a", "#ffd24a"),
            "archmage", GArray.Of("#c070ff", "#ff6ad0"), "priest", GArray.Of("#fff1a8", "#ffffff"), "necromancer", GArray.Of("#7dff8a", "#d8e8c0"),
            "golem", GArray.Of("#c8b48a", "#ffb04a"), "dragoon", GArray.Of("#ff7a3a", "#ffd890"), "duelist", GArray.Of("#ffe27a", "#ffffff"),
            "stormcaller", GArray.Of("#7fb8ff", "#e8f4ff"), "musketeer", GArray.Of("#ffd890", "#ff8a3a"), "druid", GArray.Of("#6aff7a", "#d8ffb0"));

        protected override void _Ready()
        {
            Name = "SpellFx";
        }

        // (the sim's event fields: e.get(key, default) on an Ev)
        static Var _Ev(Ev e, string key, Var dflt = default) => e.TryGetValue(key, out var v) ? Var.Of(v) : dflt;
        static GArray _EvArr(Ev e, string key) => e.TryGetValue(key, out var v) && v is IEnumerable en && !(v is string) ? GArray.From(en) : new GArray();

        // ======================================================================================================================
        // the pieces
        // ======================================================================================================================
        public static Texture2D Tex(string nm)
        {
            if (!_tex.Has(nm))
            {
                Texture2D t = null;
                foreach (var dv in TEX_DIRS)
                {
                    string d = dv.AsString();
                    string p = d.Contains("%s") ? GD.Fmt(d, nm) : d;
                    if ((nm == "smoke" && !d.Contains("%s")) || (d.Contains("%s") && ResourceLoader.Exists(p)))
                    {
                        t = ResourceLoader.Load<Texture2D>(p);
                        break;
                    }
                }
                _tex[nm] = Var.Of(t != null ? t : ResourceLoader.Load<Texture2D>("res://assets/vfx/weapon/dot.png"));
            }
            return _tex[nm].As<Texture2D>();
        }

        public static ShaderMaterial SpriteMat(string nm, double core = 0.6, Color? tint = null, double grid = 1.0, bool flat = false, double spin = 0.0)
        {
            Color tint_ = tint ?? Color.WHITE;
            var k = GD.Fmt("%s|%.2f|%s|%.0f|%s|%.2f", nm, core, tint_.ToHtmlExact(), grid, GD.Str(flat), spin);
            if (!_mats.Has(k))
            {
                var m = new ShaderMaterial();
                m.Shader = SPRITE;
                m.SetShaderParameter("tex", Tex(nm));
                m.SetShaderParameter("core", core);
                m.SetShaderParameter("tint", tint_);
                m.SetShaderParameter("grid", grid);
                m.SetShaderParameter("lie_flat", flat);
                m.SetShaderParameter("spin", spin);
                _mats[k] = Var.Of(m);
            }
            return _mats[k].As<ShaderMaterial>();
        }

        public static GradientTexture1D _Ramp(Color col, string fade, double alpha)
        {
            var g = new Gradient();
            var hot = col.Lerp(Color.WHITE, 0.65);
            switch (fade)
            {
                case "hot":
                    g.SetOffsets(new double[] { 0.0, 0.25, 1.0 });
                    g.SetColors(new Color[] { new Color(hot, alpha), new Color(col, alpha), new Color(col.Darkened(0.4), 0.0) });
                    break;
                case "flicker":
                    g.SetOffsets(new double[] { 0.0, 0.3, 0.5, 0.75, 1.0 });
                    g.SetColors(new Color[] { new Color(col, alpha), new Color(col, alpha * 0.2), new Color(hot, alpha), new Color(col, alpha * 0.3), new Color(col, 0.0) });
                    break;
                case "slow":
                    g.SetOffsets(new double[] { 0.0, 0.3, 0.7, 1.0 });
                    g.SetColors(new Color[] { new Color(col, 0.0), new Color(col, alpha), new Color(col, alpha), new Color(col, 0.0) });
                    break;
                case "late":
                    g.SetOffsets(new double[] { 0.0, 0.7, 1.0 });
                    g.SetColors(new Color[] { new Color(col, alpha), new Color(col, alpha), new Color(col, 0.0) });
                    break;
                case "dark":
                    g.SetOffsets(new double[] { 0.0, 0.4, 1.0 });
                    g.SetColors(new Color[] { new Color(col, alpha), new Color(col.Darkened(0.5), alpha * 0.7), new Color(Color.BLACK, 0.0) });
                    break;
                default:
                    g.SetOffsets(new double[] { 0.0, 0.1, 0.6, 1.0 });
                    g.SetColors(new Color[] { new Color(hot, 0.0), new Color(col, alpha), new Color(col, alpha), new Color(col, 0.0) });
                    break;
            }
            var t = new GradientTexture1D();
            t.Gradient = g;
            return t;
        }

        public static CurveTexture _Curve(GArray points)
        {
            var c = new Curve();
            c.MaxValue = 2.0;
            foreach (var p in points)
                c.AddPoint(p.V2);
            var t = new CurveTexture();
            t.Curve = c;
            return t;
        }

        public static ParticleProcessMaterial _Pm(Color col, GDict o)
        {
            // a burst's or stream's process material (shared by its settings)
            var k = col.ToHtmlExact() + "|" + JSON.Stringify(o);
            if (_pms.Has(k))
                return _pms[k].As<ParticleProcessMaterial>();
            var pm = new ParticleProcessMaterial();
            var shape = GD.Str(o.Get("shape", "sphere"));
            switch (shape)
            {
                case "ring":
                    pm.EmissionShape = ParticleProcessMaterial.EMISSION_SHAPE_RING;
                    pm.EmissionRingRadius = (double)o.Get("r", 1.0);
                    pm.EmissionRingInnerRadius = (double)o.Get("r", 1.0) * (double)o.Get("inner", 0.85);
                    pm.EmissionRingHeight = (double)o.Get("h", 0.1);
                    pm.EmissionRingAxis = Vector3.UP;
                    break;
                case "box":
                    pm.EmissionShape = ParticleProcessMaterial.EMISSION_SHAPE_BOX;
                    pm.EmissionBoxExtents = o.Get("ext", new Vector3(0.5, 0.5, 0.5)).V3;
                    break;
                case "point":
                    pm.EmissionShape = ParticleProcessMaterial.EMISSION_SHAPE_POINT;
                    break;
                default:
                    pm.EmissionShape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE;
                    pm.EmissionSphereRadius = (double)o.Get("r", 0.4);
                    break;
            }
            pm.Direction = o.Get("dir", Vector3.UP).V3;
            pm.Spread = (double)o.Get("spread", 180.0);
            GArray vel = o.Get("vel", GArray.Of(1.0, 3.0)).A;
            pm.InitialVelocityMin = (double)vel[0];
            pm.InitialVelocityMax = (double)vel[1];
            pm.Gravity = o.Get("grav", Vector3.ZERO).V3;
            pm.DampingMin = (double)o.Get("damp", 0.0);
            pm.DampingMax = (double)o.Get("damp", 0.0) * 1.4;
            if (o.Has("radial"))
            {
                pm.RadialVelocityMin = (double)o["radial"] * 0.7;
                pm.RadialVelocityMax = (double)o["radial"];
            }
            if (o.Has("orbit"))
            {
                pm.OrbitVelocityMin = (double)o["orbit"] * 0.7;
                pm.OrbitVelocityMax = (double)o["orbit"];
            }
            var ang = (double)o.Get("angle", 180.0);
            pm.AngleMin = -ang;
            pm.AngleMax = ang;
            var spin = (double)o.Get("spin", 0.0);
            pm.AngularVelocityMin = -spin;
            pm.AngularVelocityMax = spin;
            var sz = (double)o.Get("sizes", 0.35);
            pm.ScaleMin = 1.0 - sz;
            pm.ScaleMax = 1.0 + sz;
            switch (GD.Str(o.Get("shape_life", "")))
            {
                case "pop": pm.ScaleCurve = _Curve(GArray.Of(new Vector2(0, 0.1), new Vector2(0.2, 1.0), new Vector2(1, 0.0))); break;
                case "shrink": pm.ScaleCurve = _Curve(GArray.Of(new Vector2(0, 1.0), new Vector2(1, 0.15))); break;
                case "grow": pm.ScaleCurve = _Curve(GArray.Of(new Vector2(0, 0.4), new Vector2(1, 1.4))); break;
                case "swell": pm.ScaleCurve = _Curve(GArray.Of(new Vector2(0, 0.3), new Vector2(0.4, 1.0), new Vector2(1, 1.8))); break;
            }
            if ((double)o.Get("grid", 1.0) > 1.0)
                pm.AnimOffsetMax = 1.0;
            if ((double)o.Get("turb", 0.0) > 0.0)
            {
                pm.TurbulenceEnabled = true;
                pm.TurbulenceNoiseScale = 1.8;
                pm.TurbulenceNoiseStrength = 1.2;
                pm.TurbulenceInfluenceMin = 0.04 * (double)o["turb"];
                pm.TurbulenceInfluenceMax = 0.14 * (double)o["turb"];
            }
            if ((bool)o.Get("align", false))
                pm.ParticleFlagAlignY = true;
            pm.LifetimeRandomness = (double)o.Get("rand", 0.3);
            pm.ColorRamp = _Ramp(col, GD.Str(o.Get("fade", "")), (double)o.Get("alpha", 1.0));
            _pms[k] = Var.Of(pm);
            return pm;
        }

        public double _Thin()
        {
            return view.low_fx ? 0.45 : 1.0;
        }

        public GPUParticles3D Burst(Vector3 at, Color col, GDict o)
        {
            // a one-shot puff of sprites at `at`. o: n, life, size, tex, core, and the process material's settings (_pm): shape
            // (sphere r / ring r inner h / box ext / point), dir, spread, vel [min, max], grav, damp, radial, orbit, angle, spin,
            // sizes, shape_life (pop / shrink / grow / swell), fade (hot / flicker / slow / late / dark), alpha, turb, align,
            // grid; explode (0..1, 1 = all at once); dur (a stream for dur seconds instead of a burst); parent (ride a node);
            // mesh ("rock": lit stone chips, "knife": a thin box along its flight; else a sprite quad)
            var p = new GPUParticles3D();
            p.Amount = GD.Maxi(1, (int)Math.Ceiling((double)o.Get("n", 12) * _Thin()));
            p.Lifetime = (double)o.Get("life", 0.7);
            p.OneShot = !o.Has("dur");
            p.Explosiveness = p.OneShot ? (double)o.Get("explode", 1.0) : (double)o.Get("explode", 0.0);
            p.Randomness = 0.3;
            p.FixedFps = 30;
            p.Interpolate = true;
            p.LocalCoords = (bool)o.Get("local", false);
            p.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            var reach = (double)o.Get("reach", 8.0);
            p.VisibilityAabb = new AABB(new Vector3(-reach, -reach * 0.5, -reach), new Vector3(reach * 2.0, reach * 2.0, reach * 2.0));
            var po = o.Duplicate();
            foreach (var k in new[] { "n", "life", "size", "tex", "core", "explode", "dur", "parent", "mesh", "reach", "local", "tilt", "blend" })
                po.Erase(k);
            p.ProcessMaterial = _Pm(col, po);
            var size = (double)o.Get("size", 0.4);
            switch (GD.Str(o.Get("mesh", "")))
            {
                case "rock":
                {
                    var bm = new BoxMesh();
                    bm.Size = new Vector3(size, size * 0.7, size * 0.85);
                    if (_rock_mat == null)
                    {
                        _rock_mat = new StandardMaterial3D();
                        _rock_mat.AlbedoColor = new Color(0.5, 0.45, 0.38);
                        _rock_mat.VertexColorUseAsAlbedo = true;
                        _rock_mat.Roughness = 0.95;
                    }
                    bm.Material = _rock_mat;
                    p.DrawPass1 = bm;
                    break;
                }
                case "knife":
                {
                    var km = new BoxMesh();
                    km.Size = new Vector3(size * 0.12, size, size * 0.04);
                    var m = new StandardMaterial3D();
                    m.ShadingMode = BaseMaterial3D.SHADING_MODE_UNSHADED;
                    m.VertexColorUseAsAlbedo = true;
                    m.Transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
                    m.BlendMode = BaseMaterial3D.BLEND_MODE_ADD;
                    km.Material = m;
                    p.DrawPass1 = km;
                    break;
                }
                default:
                {
                    var q = new QuadMesh();
                    q.Size = Vector2.ONE * size;
                    if (GD.Str(o.Get("blend", "")) == "mix")
                    {
                        q.Material = SiegeView._SmokeDrawMat();          // (smoke mixed over the scene, not added: dust, shadow, gun smoke)
                        p.DrawOrder = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH;
                    }
                    else
                        q.Material = SpriteMat(GD.Str(o.Get("tex", "dot")), (double)o.Get("core", 0.7), Color.WHITE, (double)o.Get("grid", 1.0));
                    p.DrawPass1 = q;
                    break;
                }
            }
            Node3D parent = o.Has("parent") ? o["parent"].As<Node3D>() : this;
            if (parent != this)
            {
                p.Position = at;
                parent.AddChild(p);
            }
            else
            {
                p.Position = at;
                AddChild(p);
            }
            if (o.Has("tilt"))
                p.Basis = (Basis)o["tilt"];
            p.Restart();
            if (o.Has("dur"))
            {
                var dur = (double)o["dur"];
                _live.Append(GDict.Of("node", p, "t0", _time, "life", dur + p.Lifetime + 0.3, "fn", (Action<Node, double, double>)((n, u, age) =>
                {
                    if (age >= dur && (n as GPUParticles3D).Emitting)
                        (n as GPUParticles3D).Emitting = false;
                })));
            }
            else
                _live.Append(GDict.Of("node", p, "t0", _time, "life", p.Lifetime * (1.0 + (double)o.Get("rand", 0.3)) + 0.3, "fn", Var.Nil));
            return p;
        }

        public MeshInstance3D Flash(Vector3 at, Color col, double size, double life = 0.35, string nm = "dot", double core = 0.8, bool flat = false, double spin = 0.0)
        {
            // one sprite facing the camera (flat: lying on the ground), popping up and fading
            var mi = new MeshInstance3D();
            var q = new QuadMesh();
            q.Size = Vector2.ONE;
            mi.Mesh = q;
            var m = SpriteMat(nm, core, Color.WHITE, 1.0, flat, spin).Duplicate() as ShaderMaterial;
            m.SetShaderParameter("tint", col);
            mi.MaterialOverride = m;
            mi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            mi.Position = at;
            if (flat)
            {
                var rot = mi.Rotation;
                rot.x = (float)(-GD.PI * 0.5);
                mi.Rotation = rot;
            }
            AddChild(mi);
            _live.Append(GDict.Of("node", mi, "t0", _time, "life", life, "fn", (Action<Node, double, double>)((n, u, _age) =>
            {
                double s = size * (0.35 + 0.65 * Math.Sqrt(GD.Minf(1.0, u * 4.0))) * (1.0 + 0.25 * u);
                (n as Node3D).Scale = Vector3.ONE * s;
                var c = col;
                c.a = (float)(col.a * (1.0 - u * u));
                ((n as MeshInstance3D).MaterialOverride as ShaderMaterial).SetShaderParameter("tint", c);
            })));
            return mi;
        }

        // ----- ground -----
        public ArrayMesh _GroundMesh(Vector2 c, double r, int segs = 10)
        {
            // a disc of 2r across, its vertices on the terrain (UV 0..1 over it)
            var st = new SurfaceTool();
            st.Begin(Mesh.PRIMITIVE_TRIANGLES);
            var n = segs;
            for (int j = 0; j < n + 1; j++)
            {
                for (int i = 0; i < n + 1; i++)
                {
                    var u = (double)i / (double)n;
                    var v = (double)j / (double)n;
                    var p2 = c + new Vector2((u - 0.5) * 2.0 * r, (v - 0.5) * 2.0 * r);
                    st.SetUv(new Vector2(u, v));
                    st.AddVertex(new Vector3(p2.x - c.x, Sim.HeightAt(p2) - Sim.HeightAt(c), p2.y - c.y));
                }
            }
            for (int j = 0; j < n; j++)
            {
                for (int i = 0; i < n; i++)
                {
                    var a = j * (n + 1) + i;
                    st.AddIndex(a);
                    st.AddIndex(a + n + 1);
                    st.AddIndex(a + 1);
                    st.AddIndex(a + 1);
                    st.AddIndex(a + n + 1);
                    st.AddIndex(a + n + 2);
                }
            }
            return st.Commit();
        }

        public static ArrayMesh _FlatMesh(double r)
        {
            // a flat disc of 2r across (for one that rides a hero)
            var k = GD.Fmt("flat|%.2f", r);
            if (_meshes.Has(k))
                return _meshes[k].As<ArrayMesh>();
            var st = new SurfaceTool();
            st.Begin(Mesh.PRIMITIVE_TRIANGLES);
            for (int j = 0; j < 2; j++)
            {
                for (int i = 0; i < 2; i++)
                {
                    st.SetUv(new Vector2((double)i, (double)j));
                    st.AddVertex(new Vector3(((double)i - 0.5) * 2.0 * r, 0.0, ((double)j - 0.5) * 2.0 * r));
                }
            }
            st.AddIndex(0); st.AddIndex(2); st.AddIndex(1);
            st.AddIndex(1); st.AddIndex(2); st.AddIndex(3);
            _meshes[k] = Var.Of(st.Commit());
            return _meshes[k].As<ArrayMesh>();
        }

        public ShaderMaterial _GroundMat(Color col, int style, GDict o)
        {
            var m = new ShaderMaterial();
            m.Shader = GROUND;
            m.SetShaderParameter("color", col);
            m.SetShaderParameter("style", style);
            if (o.Has("tex"))
                m.SetShaderParameter("tex", Tex(GD.Str(o["tex"])));
            m.SetShaderParameter("spin", (double)o.Get("spin", 0.0));
            m.SetShaderParameter("rim", (double)o.Get("rim", 0.8));
            m.SetShaderParameter("energy", (double)o.Get("energy", 1.0));
            m.SetShaderParameter("seed", GD.Randf() * 100.0);
            m.SetShaderParameter("fade", 0.0);
            m.SetShaderParameter("grow", 1.0);
            return m;
        }

        public MeshInstance3D Disc(Vector2 c2, Color col, double r, double life, int style = 0, GDict o = null)
        {
            // a ground disc for `life` seconds (life < 0: held by a _hold key, o.key, until let go): fades in over o.in (0.15),
            // out over o.out (0.3); o.grow: the lit radius runs out over that many seconds; o.up: above the ground (0.1)
            o ??= new GDict();
            var mi = new MeshInstance3D();
            mi.Mesh = (bool)o.Get("flat", false) ? _FlatMesh(r) : _GroundMesh(c2, r, r > 3.0 ? 10 : 6);
            mi.MaterialOverride = _GroundMat(col, style, o);
            mi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            mi.Position = new Vector3(c2.x, Sim.HeightAt(c2) + (double)o.Get("up", 0.1), c2.y);
            AddChild(mi);
            var t_in = (double)o.Get("in", 0.15);
            var t_out = (double)o.Get("out", 0.3);
            var t_grow = (double)o.Get("grow", 0.0);
            var mat = mi.MaterialOverride as ShaderMaterial;
            var nodes = GArray.Of(mi);
            var mats = GArray.Of(Var.Of(mat));
            if ((double)o.Get("scorch", 0.0) > 0.0 && !view.low_fx)
            {
                // the dark under it (mixed over the ground, just below the light)
                var dk = new MeshInstance3D();
                dk.Mesh = mi.Mesh;
                var dm = new ShaderMaterial();
                dm.Shader = SCORCH;
                dm.SetShaderParameter("color", o.Get("scorch_col", new Color(0.06, 0.03, 0.01)));
                dm.SetShaderParameter("strength", (double)o["scorch"]);
                dm.SetShaderParameter("seed", GD.Randf() * 100.0);
                dm.SetShaderParameter("fade", 0.0);
                dk.MaterialOverride = dm;
                dk.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
                dk.Position = mi.Position - new Vector3(0, 0.03, 0);
                AddChild(dk);
                nodes.Append(dk);
                mats.Append(Var.Of(dm));
            }
            if (life < 0.0)
                _Hold(GD.Str(o.Get("key", GD.Fmt("disc%d", (long)mi.GetInstanceId()))), nodes, o.Get("alive", Var.Nil).As<Func<bool>>(), t_out, t_in, t_grow);
            else
            {
                var scorch_out = (double)o.Get("scorch_out", t_out);
                var dk_life = GD.Maxf(life, life - t_out + scorch_out);
                _live.Append(GDict.Of("node", mi, "t0", _time, "life", life, "fn", (Action<Node, double, double>)((_n, _u, age) =>
                {
                    double f = GD.Minf(1.0, age / t_in) * GD.Minf(1.0, (life - age) / t_out);
                    mat.SetShaderParameter("fade", GD.Clampf(f, 0.0, 1.0));
                    if (t_grow > 0.0)
                        mat.SetShaderParameter("grow", GD.Clampf(age / t_grow, 0.0, 1.0) * 1.08);
                })));
                if (nodes.Size() > 1)
                {
                    ShaderMaterial dm2 = mats[1].As<ShaderMaterial>();
                    _live.Append(GDict.Of("node", nodes[1], "t0", _time, "life", dk_life, "fn", (Action<Node, double, double>)((_n, _u, age) =>
                    {
                        double f = GD.Minf(1.0, age / t_in) * GD.Minf(1.0, (dk_life - age) / scorch_out);
                        dm2.SetShaderParameter("fade", GD.Clampf(f, 0.0, 1.0));
                        if (t_grow > 0.0)
                            dm2.SetShaderParameter("grow", GD.Clampf(age / t_grow, 0.0, 1.0) * 1.08);
                    })));
                }
            }
            return mi;
        }

        public MeshInstance3D Wave(Vector2 c2, Color col, double r0, double r1, double life, double rim = 1.2, double up = 0.12)
        {
            // a ring running out from r0 to r1 and fading (the rim style of the ground disc, scaled)
            var mi = new MeshInstance3D();
            mi.Mesh = _GroundMesh(c2, r1, 6);
            var mat = _GroundMat(col, 5, GDict.Of("rim", rim));
            mat.SetShaderParameter("fade", 1.0);
            mi.MaterialOverride = mat;
            mi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            mi.Position = new Vector3(c2.x, Sim.HeightAt(c2) + up, c2.y);
            mi.Scale = new Vector3(GD.Maxf(0.01, r0 / r1), 1.0, GD.Maxf(0.01, r0 / r1));
            AddChild(mi);
            _live.Append(GDict.Of("node", mi, "t0", _time, "life", life, "fn", (Action<Node, double, double>)((n, u, _age) =>
            {
                double k = 1.0 - (1.0 - u) * (1.0 - u);
                double s = GD.Maxf(0.01, GD.Lerpf(r0, r1, k) / r1);
                (n as Node3D).Scale = new Vector3(s, 1.0, s);
                mat.SetShaderParameter("fade", 1.0 - u * u);
            })));
            return mi;
        }

        public static ArrayMesh _FanMesh(double arc, int segs = 12)
        {
            // a sector of a unit disc, +Z ahead, arc radians either side: UV.y 0 at the apex, 1 at the rim; UV.x across
            var k = GD.Fmt("fan|%.2f|%d", arc, segs);
            if (_meshes.Has(k))
                return _meshes[k].As<ArrayMesh>();
            var st = new SurfaceTool();
            st.Begin(Mesh.PRIMITIVE_TRIANGLES);
            var rings = 4;
            for (int j = 0; j < rings + 1; j++)
            {
                var rr = (double)j / (double)rings;
                for (int i = 0; i < segs + 1; i++)
                {
                    var t = (double)i / (double)segs;
                    var a = -arc + 2.0 * arc * t;
                    st.SetUv(new Vector2(t, rr));
                    st.AddVertex(new Vector3(Math.Sin(a) * rr, 0.0, Math.Cos(a) * rr));
                }
            }
            for (int j = 0; j < rings; j++)
            {
                for (int i = 0; i < segs; i++)
                {
                    var a = j * (segs + 1) + i;
                    st.AddIndex(a);
                    st.AddIndex(a + 1);
                    st.AddIndex(a + segs + 1);
                    st.AddIndex(a + 1);
                    st.AddIndex(a + segs + 2);
                    st.AddIndex(a + segs + 1);
                }
            }
            _meshes[k] = Var.Of(st.Commit());
            return _meshes[k].As<ArrayMesh>();
        }

        public static ArrayMesh _TubeMesh(double r0, double r1, int segs = 14)
        {
            // a tube of unit height from r0 at the foot (UV.y 0) to r1 at the top (UV.y 1); UV.x round it
            var k = GD.Fmt("tube|%.2f|%.2f|%d", r0, r1, segs);
            if (_meshes.Has(k))
                return _meshes[k].As<ArrayMesh>();
            var st = new SurfaceTool();
            st.Begin(Mesh.PRIMITIVE_TRIANGLES);
            var rows = 3;
            for (int j = 0; j < rows + 1; j++)
            {
                var y = (double)j / (double)rows;
                var rr = GD.Lerpf(r0, r1, y);
                for (int i = 0; i < segs + 1; i++)
                {
                    var a = GD.TAU * (double)i / (double)segs;
                    st.SetUv(new Vector2((double)i / (double)segs, y));
                    st.AddVertex(new Vector3(Math.Cos(a) * rr, y, Math.Sin(a) * rr));
                }
            }
            for (int j = 0; j < rows; j++)
            {
                for (int i = 0; i < segs; i++)
                {
                    var a = j * (segs + 1) + i;
                    st.AddIndex(a);
                    st.AddIndex(a + segs + 1);
                    st.AddIndex(a + 1);
                    st.AddIndex(a + 1);
                    st.AddIndex(a + segs + 1);
                    st.AddIndex(a + segs + 2);
                }
            }
            _meshes[k] = Var.Of(st.Commit());
            return _meshes[k].As<ArrayMesh>();
        }

        public static ArrayMesh _SheetMesh()
        {
            // two crossed unit quads along +Z (UV.y along, UV.x across): a beam seen from any side
            var k = "sheet";
            if (_meshes.Has(k))
                return _meshes[k].As<ArrayMesh>();
            var st = new SurfaceTool();
            st.Begin(Mesh.PRIMITIVE_TRIANGLES);
            var n = 0;
            for (int plane = 0; plane < 2; plane++)
            {
                var side = plane == 0 ? new Vector3(1, 0, 0) : new Vector3(0, 1, 0);
                for (int j = 0; j < 2; j++)
                {
                    for (int i = 0; i < 2; i++)
                    {
                        st.SetUv(new Vector2((double)i, (double)j));
                        st.AddVertex(side * ((double)i - 0.5) + new Vector3(0, 0, (double)j));
                    }
                }
                st.AddIndex(n); st.AddIndex(n + 2); st.AddIndex(n + 1);
                st.AddIndex(n + 1); st.AddIndex(n + 2); st.AddIndex(n + 3);
                n += 4;
            }
            _meshes[k] = Var.Of(st.Commit());
            return _meshes[k].As<ArrayMesh>();
        }

        public ShaderMaterial _BeamMat(Color col, GDict o)
        {
            var m = new ShaderMaterial();
            m.Shader = BEAM;
            m.SetShaderParameter("color", col);
            m.SetShaderParameter("energy", (double)o.Get("energy", 1.0));
            m.SetShaderParameter("speed", (double)o.Get("speed", 2.0));
            m.SetShaderParameter("scale", (double)o.Get("scale", 3.0));
            m.SetShaderParameter("fade_root", (double)o.Get("fade_root", 0.15));
            m.SetShaderParameter("fade_end", (double)o.Get("fade_end", 0.4));
            m.SetShaderParameter("side_fade", (bool)o.Get("side_fade", true));
            m.SetShaderParameter("core", (double)o.Get("core", 0.4));
            m.SetShaderParameter("seed", GD.Randf() * 100.0);
            m.SetShaderParameter("fade", 0.0);
            m.SetShaderParameter("grow", 1.0);
            return m;
        }

        public void _Timed(MeshInstance3D mi, ShaderMaterial mat, double life, GDict o)
        {
            var t_in = (double)o.Get("in", 0.08);
            var t_out = (double)o.Get("out", 0.35);
            var t_grow = (double)o.Get("grow", 0.0);
            if (life < 0.0)
            {
                _Hold(GD.Str(o.Get("key", GD.Fmt("m%d", (long)mi.GetInstanceId()))), GArray.Of(mi), o.Get("alive", Var.Nil).As<Func<bool>>(), t_out, t_in, t_grow);
                return;
            }
            _live.Append(GDict.Of("node", mi, "t0", _time, "life", life, "fn", (Action<Node, double, double>)((_n, _u, age) =>
            {
                mat.SetShaderParameter("fade", GD.Clampf(GD.Minf(1.0, age / t_in) * GD.Minf(1.0, (life - age) / t_out), 0.0, 1.0));
                if (t_grow > 0.0)
                    mat.SetShaderParameter("grow", GD.Clampf(age / t_grow, 0.0, 1.0) * 1.08);
            })));
        }

        public MeshInstance3D Pillar(Vector3 at, Color col, double r, double h, double life, GDict o = null)
        {
            // a column of light standing on `at`: r at the foot, o.top (r) at the top
            o ??= new GDict();
            var mi = new MeshInstance3D();
            mi.Mesh = _TubeMesh(1.0, (double)o.Get("top", r) / r);
            var oo = o.Duplicate();
            oo["side_fade"] = false;
            oo["fade_end"] = (double)o.Get("fade_end", 0.5);
            var mat = _BeamMat(col, oo);
            mi.MaterialOverride = mat;
            mi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            mi.Position = at;
            mi.Scale = new Vector3(r, h, r);
            AddChild(mi);
            _Timed(mi, mat, life, o);
            return mi;
        }

        public MeshInstance3D Fan(Vector2 c2, Vector2 dir, Color col, double r, double arc, double life, GDict o = null)
        {
            // a cone of light on the ground ahead of c2 along dir, r long, arc radians either side
            o ??= new GDict();
            var mi = new MeshInstance3D();
            mi.Mesh = _FanMesh(arc);
            var oo = o.Duplicate();
            oo["fade_root"] = (double)o.Get("fade_root", 0.1);
            var mat = _BeamMat(col, oo);
            mi.MaterialOverride = mat;
            mi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            mi.Position = new Vector3(c2.x, Sim.HeightAt(c2) + (double)o.Get("up", 0.15), c2.y);
            var rot = mi.Rotation;
            rot.y = (float)Sim.AngleOf(dir);
            mi.Rotation = rot;
            mi.Scale = new Vector3(r, 1.0, r);
            AddChild(mi);
            _Timed(mi, mat, life, o);
            return mi;
        }

        public MeshInstance3D Beam(Vector3 from, Vector3 to, Color col, double w, double life, GDict o = null)
        {
            // a sheet of light between two points
            o ??= new GDict();
            var mi = new MeshInstance3D();
            mi.Mesh = _SheetMesh();
            var mat = _BeamMat(col, o);
            mi.MaterialOverride = mat;
            mi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            var len = GD.Maxf(0.05, from.DistanceTo(to));
            mi.Position = from;
            if (len > 0.06)
            {
                mi.LookAtFromPosition(from, to, Math.Abs((to - from).NormalizedChecked().y) < 0.95 ? Vector3.UP : Vector3.RIGHT);
                mi.RotateObjectLocal(Vector3.UP, GD.PI);            // (look_at points -Z at the target; the sheet runs along +Z)
            }
            mi.Scale = new Vector3(w, w, len);
            AddChild(mi);
            _Timed(mi, mat, life, o);
            return mi;
        }

        public MeshInstance3D Shell(Node3D parent, Color col, double r, double h, int style, double life, GDict o = null)
        {
            // a bubble round a hero (parent: his root; o.y its centre, 1.0)
            o ??= new GDict();
            if (parent == null)
                return null;
            var mi = new MeshInstance3D();
            var sm = new SphereMesh();
            sm.Radius = r;
            sm.Height = h;
            sm.RadialSegments = 20;
            sm.Rings = 10;
            mi.Mesh = sm;
            var mat = new ShaderMaterial();
            mat.Shader = SHELL;
            mat.SetShaderParameter("color", col);
            mat.SetShaderParameter("style", style);
            mat.SetShaderParameter("energy", (double)o.Get("energy", 1.0));
            mat.SetShaderParameter("speed", (double)o.Get("speed", 1.0));
            mat.SetShaderParameter("seed", GD.Randf() * 100.0);
            mat.SetShaderParameter("fade", 0.0);
            mi.MaterialOverride = mat;
            mi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            mi.Position = new Vector3(0, (double)o.Get("y", 1.0), 0);
            parent.AddChild(mi);
            _Timed(mi, mat, life, o);
            return mi;
        }

        public void Bolt(Vector3 from, Vector3 to, Color col, double life, double jag, double w = 0.14, int branches = 1)
        {
            // lightning: a white core and a glow round it, kinked every metre or so, a branch or two off it; thinning out
            var n = GD.Maxi(2, (int)(from.DistanceTo(to) / 1.1));
            var prev = from;
            var pts = GArray.Of(from);
            for (int i = 0; i < n; i++)
            {
                var t = (double)(i + 1) / (double)n;
                var nxt = from.Lerp(to, t);
                if (i < n - 1)
                    nxt += new Vector3(GD.RandfRange(-jag, jag), GD.RandfRange(-jag, jag) * 0.6, GD.RandfRange(-jag, jag)) * 0.5;
                pts.Append(nxt);
                prev = nxt;
            }
            _BoltPath(pts, col, life, w);
            if (!view.low_fx)
            {
                for (int b = 0; b < branches; b++)
                {
                    var i0 = GD.RandiRange(1, GD.Maxi(1, pts.Size() - 2));
                    Vector3 p0 = pts[i0].V3;
                    Vector3 d = (to - from).NormalizedChecked().Rotated(Vector3.UP, GD.RandfRange(-1.2, 1.2)) * GD.RandfRange(0.8, 1.8);
                    d.y = (float)(d.y + GD.RandfRange(-0.6, 0.2));
                    _BoltPath(GArray.Of(p0, p0 + d * 0.5 + new Vector3(GD.RandfRange(-jag, jag), 0, GD.RandfRange(-jag, jag)) * 0.3, p0 + d), col, life * 0.8, w * 0.6);
                }
            }
        }

        public static BoxMesh _BoxMesh()
        {
            if (!_meshes.Has("box"))
            {
                var bm = new BoxMesh();
                bm.Size = new Vector3(1.0, 1.0, 1.0);
                _meshes["box"] = Var.Of(bm);
            }
            return _meshes["box"].As<BoxMesh>();
        }

        public static StandardMaterial3D _FlatMat(Color col)
        {
            var k = "flat|" + col.ToHtmlExact();
            if (!_mats.Has(k))
            {
                var m = new StandardMaterial3D();
                m.ShadingMode = BaseMaterial3D.SHADING_MODE_UNSHADED;
                m.Transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
                m.BlendMode = BaseMaterial3D.BLEND_MODE_ADD;
                m.AlbedoColor = col;
                m.CullMode = BaseMaterial3D.CULL_DISABLED;
                _mats[k] = Var.Of(m);
            }
            return _mats[k].As<StandardMaterial3D>();
        }

        public void _BoltPath(GArray pts, Color col, double life, double w)
        {
            for (int i = 0; i < pts.Size() - 1; i++)
            {
                Vector3 a = pts[i].V3;
                Vector3 b = pts[i + 1].V3;
                var len = GD.Maxf(0.05, a.DistanceTo(b));
                var mid = (a + b) * 0.5;
                for (int layer = 0; layer < 2; layer++)
                {
                    var seg = new MeshInstance3D();
                    seg.Mesh = _BoxMesh();
                    seg.MaterialOverride = _FlatMat(layer == 0 ? new Color(1, 1, 1, 0.95) : new Color(col, 0.55));
                    seg.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
                    AddChild(seg);
                    seg.Position = mid;
                    if (len > 0.06)
                        seg.LookAtFromPosition(mid, b, Math.Abs((b - a).NormalizedChecked().y) < 0.95 ? Vector3.UP : Vector3.RIGHT);
                    var ww = w * (layer == 0 ? 0.45 : 1.6);
                    seg.Scale = new Vector3(ww, ww, len);
                    _live.Append(GDict.Of("node", seg, "t0", _time, "life", life, "fn", (Action<Node, double, double>)((n, u, _age) =>
                    {
                        double k = GD.Maxf(0.05, 1.0 - u * u);
                        (n as Node3D).Scale = new Vector3(ww * k, ww * k, len);
                    })));
                }
            }
        }

        public GPUParticles3D Trail(Node3D parent, Color col, double dur, string nm = "streak", GDict o = null)
        {
            // sprites left behind a moving thing (parent) for dur seconds
            o ??= new GDict();
            var oo = GDict.Of("n", (int)o.Get("n", 40), "life", (double)o.Get("life", 0.45), "size", (double)o.Get("size", 0.5), "tex", nm, "core", 0.7,
                "shape", "sphere", "r", (double)o.Get("r", 0.3), "vel", GArray.Of(0.2, 0.8), "spread", 180.0, "fade", GD.Str(o.Get("fade", "")),
                "shape_life", GD.Str(o.Get("shape_life", "shrink")), "dur", dur, "parent", parent, "angle", 180.0, "spin", 40.0,
                "grav", o.Get("grav", new Vector3(0, 0.6, 0)), "explode", 0.0, "rand", 0.2);
            if (o.Has("alpha"))
                oo["alpha"] = o["alpha"];
            if (o.Has("blend"))
                oo["blend"] = o["blend"];
            return Burst(new Vector3(0, (double)o.Get("y", 0.9), 0), col, oo);
        }

        public void Mover(Node3D node, Vector3 from, Vector3 to, double dur, double arc, double spin = 0.0, Action done = null)
        {
            // carries a node from one point to another on an arc (arc: its height at the top), spinning; done() at the end
            AddChild(node);
            node.Position = from;
            _live.Append(GDict.Of("node", node, "t0", _time, "life", dur, "fn", (Action<Node, double, double>)((n, u, _age) =>
            {
                var n3 = n as Node3D;
                n3.Position = from.Lerp(to, u) + new Vector3(0, arc * 4.0 * u * (1.0 - u), 0);
                if (spin != 0.0)
                {
                    var rot = n3.Rotation;
                    rot.x = (float)(rot.x + spin);
                    n3.Rotation = rot;
                }
                if (u >= 0.999 && done != null)
                    done();
            })));
        }

        public void Shake(double k, Vector2? near = null, double r = 12.0)
        {
            Vector2 near_ = near ?? Vector2.INF;
            if (near_ == Vector2.INF)
                view.Shake(k);
            else
                view._ShakeNear(near_, r, k);
        }

        // ----- what lasts -----
        public void _Hold(string key, GArray nodes, Func<bool> alive, double t_out = 0.3, double t_in = 0.1, double t_grow = 0.0)
        {
            // nodes kept until alive() is false (or until release(key)); their shader "fade" eased in and out
            Release(key, true);
            _holds[key] = GDict.Of("nodes", nodes, "alive", alive, "t0", _time, "out", t_out, "in", t_in, "grow", t_grow, "gone", -1.0);
        }

        public bool Holding(string key)
        {
            return _holds.Has(key) && (double)_holds[key]["gone"] < 0.0;
        }

        public void Release(string key, bool now = false)
        {
            if (!_holds.Has(key))
                return;
            GDict h = _holds[key].D;
            if (now)
            {
                foreach (var n in h["nodes"])
                {
                    if (GD.IsInstanceValid(n))
                        n.As<Node>().QueueFree();
                }
                _holds.Erase(key);
            }
            else if ((double)h["gone"] < 0.0)
            {
                h["gone"] = _time;
                foreach (var n in h["nodes"])
                {
                    if (GD.IsInstanceValid(n) && n.Is<GPUParticles3D>())
                        n.As<GPUParticles3D>().Emitting = false;
                }
            }
        }

        public void _StepHolds()
        {
            foreach (var key in _holds.Keys())
            {
                GDict h = _holds[key].D;
                if ((double)h["gone"] < 0.0 && h["alive"].Is<Func<bool>>() && h["alive"].As<Func<bool>>() != null && !h["alive"].As<Func<bool>>()())
                    Release(key.AsString());
                var f = 1.0;
                var age = _time - (double)h["t0"];
                if ((double)h["gone"] >= 0.0)
                {
                    f = 1.0 - GD.Clampf((_time - (double)h["gone"]) / GD.Maxf(0.01, (double)h["out"]), 0.0, 1.0);
                    if (f <= 0.0)
                    {
                        foreach (var n in h["nodes"])
                        {
                            if (GD.IsInstanceValid(n))
                                n.As<Node>().QueueFree();
                        }
                        _holds.Erase(key);
                        continue;
                    }
                }
                f *= GD.Clampf(age / GD.Maxf(0.01, (double)h["in"]), 0.0, 1.0);
                foreach (var n in h["nodes"])
                {
                    if (GD.IsInstanceValid(n) && n.Is<MeshInstance3D>() && n.As<MeshInstance3D>().MaterialOverride is ShaderMaterial)
                    {
                        var m = n.As<MeshInstance3D>().MaterialOverride as ShaderMaterial;
                        m.SetShaderParameter("fade", f);
                        if ((double)h["grow"] > 0.0)
                            m.SetShaderParameter("grow", GD.Clampf(age / (double)h["grow"], 0.0, 1.0) * 1.08);
                    }
                }
            }
        }

        public void Step(double dt)
        {
            _time += dt;
            for (int i = _live.Size() - 1; i > -1; i--)
            {
                GDict e = _live[i].D;
                var n = e["node"];
                if (!GD.IsInstanceValid(n))
                {
                    _live.RemoveAt(i);
                    continue;
                }
                var age = _time - (double)e["t0"];
                if (age > (double)e["life"])
                {
                    n.As<Node>().QueueFree();
                    _live.RemoveAt(i);
                    continue;
                }
                if (e["fn"].Is<Action<Node, double, double>>() && e["fn"].As<Action<Node, double, double>>() != null)
                    e["fn"].As<Action<Node, double, double>>()(n.As<Node>(), age / GD.Maxf(0.001, (double)e["life"]), age);
            }
            _StepHolds();
        }

        // ---------- the match's loading card (0.31.207) ----------
        // Kevin: "The match keeps getting stutters". Each look here is built the first time it's needed -- its particles' process
        // shader, its sprite material, the pipelines to draw them -- and on the phone the first of each in a match was a long
        // frame (tools/hitch_bench.gd: the long frames came with new particle materials and pipeline compiles). So behind the
        // match's loading card, in front of its camera, every look this match's heroes have is shown once on your own hero (a
        // job a frame): each hero's casts, Q and ultimate, the one-off events, the lasting states, the zones, a trap and each
        // projectile's trail -- then all of it cleared (clear_all) before the card lifts.
        public static readonly GArray WARM_EVENTS = GArray.Of("block_up", "pillar", "slam", "burst", "zap", "riposte", "flurry_hit", "trap_snap", "nova", "sanctuary",
            "proj", "resurrect", "pierce_hit", "boom", "dodge", "meteor_warn", "meteor_hit");
        public static readonly GArray WARM_ZONES = GArray.Of("consecrate", "caltrops", "static", "smoke", "wildgrowth", "thunderstorm", "pillar", "entangle");
        public static readonly GArray WARM_TRAILS = GArray.Of(GArray.Of("hammer", ""), GArray.Of("pierce", ""), GArray.Of("boulder", ""), GArray.Of("bolt", ""), GArray.Of("ball", ""), GArray.Of("thorn", ""), GArray.Of("fire", ""),
            GArray.Of("fire", "missiles"), GArray.Of("arrow", ""), GArray.Of("arrow", "snare"));
        public int warm_shown = 0;                     // (tests: the looks the warm-up showed)

        public GArray WarmJobs(string me_id)
        {
            // -> [Callable, ...], one a frame (siege_mode's warm-up)
            var sim = view.sim;
            if (sim == null || sim.moba == null || !sim.by_id.ContainsKey(me_id))
                return new GArray();
            var jobs = new GArray();
            var hids = new GDict();
            foreach (var u in sim.units)
            {
                var hid = GD.Str(u.hid);
                if ((bool)u.hero && hid != "" && !hids.Has(hid))
                {
                    hids[hid] = true;
                    Unit hu = u;
                    jobs.Append((Action)(() => _WarmHero(me_id, hu)));
                }
            }
            jobs.Append((Action)(() => _WarmEvents(me_id, hids.Keys())));
            jobs.Append((Action)(() => _WarmStates(me_id)));
            jobs.Append((Action)(() => _WarmZones(me_id)));
            jobs.Append((Action)(() => _WarmTrails(me_id)));
            return jobs;
        }

        public Ev _WarmEv(string me_id)
        {
            // a cast's event, every field a look reads, all on (or just ahead of) you
            Unit me = view.sim.by_id.TryGetValue(me_id, out var mu) ? mu : null;
            var root = _Root(me_id);
            Vector2 p2 = root != null ? new Vector2(root.Position.x, root.Position.z) : (me != null ? me.pos : Vector2.ZERO);
            var face = me != null ? (double)me.face : 0.0;
            var f = new Vector2(Math.Sin(face), Math.Cos(face));
            var ahead = p2 + f * 4.0;
            return new Ev { { "id", me_id }, { "team", me != null ? (int)me.team : 0 }, { "pos", p2 }, { "dir", f }, { "to", ahead }, { "c", ahead }, { "from", p2 }, { "r", 3.0 }, { "dur", 1.0 },
                { "delay", 0.6 }, { "burn", 1.0 }, { "target", me_id }, { "ids", new List<object> { me_id } }, { "pts", new List<object> { ahead, ahead + f * 2.0 } }, { "arc", 0.6 }, { "len", 4.0 } };
        }

        public void _WarmHero(string me_id, Unit h)
        {
            GDict a = view.actors.Get(me_id, new GDict()).D;
            Unit me = view.sim.by_id.TryGetValue(me_id, out var mu) ? mu : null;
            if (a.IsEmpty() || me == null || !GD.IsInstanceValid(a["root"]))
                return;
            Vector3 at = a["root"].As<Node3D>().Position;
            var hid = GD.Str(h.hid);
            foreach (var slot in new[] { "q", "w", "e" })
            {
                var ks = _Kits.Kit(hid, slot);
                var sp = GD.Str(ks != null && ks.id != null ? ks.id : "");
                if (sp != "")
                {
                    var e = _WarmEv(me_id);
                    // (e.merge({...}, true))
                    e["k"] = "spell"; e["hid"] = hid; e["slot"] = slot; e["spell"] = sp;
                    Cast(sp, e, a, at, hid);
                    warm_shown += 1;
                }
            }
            if (_Kits.KitQ(hid) == "")
            {
                var ab = GD.Str(view.sim.AbilityOf(h));
                if (ab != "")
                {
                    Q(ab, a, me);                               // (an old class's Q)
                    warm_shown += 1;
                }
            }
            var eu = _WarmEv(me_id);
            var kr = _Kits.Kit(hid, "r");
            // (eu.merge({...}, true))
            eu["k"] = "ult"; eu["ult"] = hid; eu["hid"] = hid; eu["spell"] = GD.Str(kr != null && kr.id != null ? kr.id : "");
            Ult(hid, eu, a, at);
            warm_shown += 1;
        }

        public void _WarmEvents(string me_id, GArray hids)
        {
            foreach (var k in WARM_EVENTS)
            {
                foreach (var spell in (k == "burst" ? GArray.Of("keg", "roots") : GArray.Of("")))
                {
                    var e = _WarmEv(me_id);
                    // (e.merge({...}, true))
                    e["k"] = GD.Str(k); e["spell"] = GD.Str(spell); e["kind"] = "pierce"; e["pos"] = e["c"];
                    Event(e);
                    warm_shown += 1;
                }
            }
            // a landing and a strike look like whose they are: the Barbarian's, the Dragoon's, the Golem's; the Duelist's
            Unit me = view.sim.by_id.TryGetValue(me_id, out var mu) ? mu : null;
            var hid0 = me != null ? GD.Str(me.hid) : "";
            foreach (var hid in hids)
            {
                if (GArray.Of("barbarian", "dragoon", "golem", "duelist").Has(hid))
                {
                    me.hid = GD.Str(hid);
                    var e = _WarmEv(me_id);
                    // (e.merge({...}, true))
                    e["k"] = "slam"; e["pos"] = e["c"];
                    Event(e);
                    e["k"] = "flurry_hit";
                    Event(e);
                    warm_shown += 2;
                }
            }
            me.hid = hid0;
        }

        public void _WarmStates(string me_id)
        {
            GDict a = view.actors.Get(me_id, new GDict()).D;
            Unit me = view.sim.by_id.TryGetValue(me_id, out var mu) ? mu : null;
            if (a.IsEmpty() || me == null || !GD.IsInstanceValid(a["root"]))
                return;
            double t = view.sim.time;
            Unit fake = me.Duplicate();
            foreach (var k in new[] { "shield_until", "slow_until", "amp_until", "skin_until", "dr_until", "bl_until", "ud_until" })
                fake.Set(k, t + 5.0);
            fake.shield = 1.0;
            fake.riposte = new Riposte();
            fake.dots = new List<Dot> { new Dot() };
            fake.state = "dash";
            fake.buffs = new ODict<string, double>();
            fake.buffs["arcane"] = t + 5.0;
            fake.buffs["ember"] = t + 5.0;
            fake.buffs["lord"] = t + 5.0;
            SyncUnit(me_id, fake, a, true);               // (the real one, the next frame, lets them all go)
            warm_shown += 1;
        }

        public void _WarmZones(string me_id)
        {
            var e = _WarmEv(me_id);
            var i = 0;
            foreach (var sp in WARM_ZONES)
            {
                i += 1;
                Zone(new Zone { zid = -1000 - i, spell = GD.Str(sp), team = e.I("team"), owner = me_id, at = e.P("c"), r = 2.5, until = view.sim.time + 1.0 });
                warm_shown += 1;
            }
            var tn = TrapNode(_G(e.P("c"), 0.05), Color.WHITE);
            _live.Append(GDict.Of("node", tn, "t0", _time, "life", 0.5, "fn", Var.Nil));
            warm_shown += 1;
        }

        public void _WarmTrails(string me_id)
        {
            var root = _Root(me_id);
            if (root == null)
                return;
            foreach (var tk in WARM_TRAILS)
            {
                Node3D n = view._MakeProjectile(GD.Str(tk[0]));
                n.Position = root.Position + new Vector3(0.0, 1.2, 0.0);
                ProjTrail(n, new Proj { kind = GD.Str(tk[0]), spell = GD.Str(tk[1]), vel = new Vector2(0.0, 10.0) });
                _live.Append(GDict.Of("node", n, "t0", _time, "life", 0.5, "fn", Var.Nil));
                warm_shown += 1;
            }
        }

        public void ClearAll()
        {
            // everything shown or held, gone at once (the end of the loading card's warm-up, before the match is seen)
            foreach (var e in _live)
            {
                if (GD.IsInstanceValid(e["node"]))
                    e["node"].As<Node>().QueueFree();
            }
            _live.Clear();
            foreach (var key in _holds.Keys())
                Release(key.AsString(), true);
            _holds.Clear();
            foreach (var d in new[] { _shield_style, _amp_style, _skin_style, _dash_style })
                d.Clear();
        }

        // ---------- handy ----------
        public Vector3 _G(Vector2 p2, double up = 0.1)
        {
            return new Vector3(p2.x, Sim.HeightAt(p2) + up, p2.y);
        }

        public Vector2 _UnitPos(string id)
        {
            Unit u = view.sim.by_id.TryGetValue(id, out var uu) ? uu : null;
            return u != null ? u.pos : Vector2.INF;
        }

        public Node3D _Root(string id)
        {
            GDict a = view.actors.Get(id, new GDict()).D;
            return !a.IsEmpty() && GD.IsInstanceValid(a["root"]) ? a["root"].As<Node3D>() : null;
        }

        public Func<bool> _AliveUntil(string id, string key)
        {
            // true while the sim says the unit's `key` time is ahead
            var sim = view.sim;
            return () =>
            {
                Unit u = sim.by_id.TryGetValue(id, out var uu) ? uu : null;
                return u != null && sim.Alive(u) && (double)sim.time < (u.Get(key) != null ? V.ToDouble(u.Get(key)) : -1.0);
            };
        }

        public Func<bool> _AliveWhile(string id, Func<Unit, bool> test)
        {
            var sim = view.sim;
            return () =>
            {
                Unit u = sim.by_id.TryGetValue(id, out var uu) ? uu : null;
                return u != null && sim.Alive(u) && test(u);
            };
        }

        public void _Sparkles(Vector3 at, Color col, int n, double r, double h, double life = 0.9, string nm = "sparkle")
        {
            Burst(at, col, GDict.Of("n", n, "life", life, "size", 0.35, "tex", nm, "core", 0.9, "shape", "sphere", "r", r, "vel", GArray.Of(0.3, 1.2),
                "grav", new Vector3(0, h, 0), "shape_life", "pop", "fade", "slow", "angle", 180.0, "spin", 60.0));
        }

        public void _Dust(Vector3 at, Color col, int n, double r, double size = 1.4, double life = 1.1, double vel = 2.5)
        {
            Burst(at, col, GDict.Of("n", n, "life", life, "size", size * 0.8, "tex", "smoke", "core", 0.0, "blend", "mix", "shape", "ring", "r", r, "inner", 0.3, "h", 0.2,
                "dir", Vector3.UP, "spread", 60.0, "vel", GArray.Of(vel * 0.4, vel), "damp", 2.0, "grav", new Vector3(0, 0.3, 0), "shape_life", "swell",
                "fade", "late", "alpha", 0.55, "angle", 180.0, "spin", 30.0, "rand", 0.4));
        }

        public void _Embers(Vector3 at, Color col, int n, double r, double up = 2.5, double life = 1.3)
        {
            Burst(at, col, GDict.Of("n", n, "life", life, "size", 0.14, "tex", "dot", "core", 1.0, "shape", "sphere", "r", r, "vel", GArray.Of(0.5, 2.0),
                "grav", new Vector3(0, up, 0), "turb", 1.2, "fade", "hot", "shape_life", "shrink", "damp", 0.5));
        }

        public GPUParticles3D _Flames(Vector3 at, Color col, int n, double r, double life = 0.7, double size = 0.9, double dur = -1.0, double up = 3.0)
        {
            var o = GDict.Of("n", n, "life", life, "size", size, "tex", "flame", "core", 0.7, "shape", "ring", "r", r, "inner", 0.2, "h", 0.3,
                "dir", Vector3.UP, "spread", 25.0, "vel", GArray.Of(1.0, 2.5), "grav", new Vector3(0, up, 0), "shape_life", "shrink", "fade", "hot",
                "angle", 12.0, "spin", 20.0, "damp", 1.0);
            if (dur > 0.0)
                o["dur"] = dur;
            return Burst(at, col, o);
        }

        public void _Rocks(Vector3 at, int n, double r, double size = 0.3, double vel = 6.0, double life = 1.2)
        {
            Burst(at, new Color(0.55, 0.5, 0.42), GDict.Of("n", n, "life", life, "size", size, "mesh", "rock", "shape", "sphere", "r", r,
                "dir", Vector3.UP, "spread", 55.0, "vel", GArray.Of(vel * 0.4, vel), "grav", new Vector3(0, -14.0, 0), "angle", 180.0, "spin", 400.0,
                "fade", "late", "sizes", 0.5, "rand", 0.3));
        }

        public void _Shards(Vector3 at, Color col, Vector2 dir, int n, double arc, double speed, double reach)
        {
            // knives (thin glints along their flight) thrown in a fan
            var d3 = new Vector3(dir.x, 0.0, dir.y);
            Burst(at, col, GDict.Of("n", n, "life", reach / speed, "size", 0.7, "mesh", "knife", "shape", "point", "dir", d3,
                "spread", GD.RadToDeg(arc), "vel", GArray.Of(speed * 0.8, speed), "align", true, "fade", "late", "rand", 0.1, "sizes", 0.2));
        }

        public Color _Col(string hid, int i = 0)
        {
            GArray c = HERO_COL.Get(hid, GArray.Of("#ffffff", "#ffffff")).A;
            return Color.FromCode(GD.Str(c[i]));
        }

        static Color C(string code) => Color.FromCode(code);       // (GDScript's Color("#rrggbb"))

        // ======================================================================================================================
        // the casts
        // ======================================================================================================================
        /// <summary>(the view's on_event hands its events as Dictionaries)</summary>
        public void Cast(string sp, GDict e, GDict a, Vector3 at, string hid) => Cast(sp, SiegeNet.ToEv(Var.Of(e)), a, at, hid);

        public void Cast(string sp, Ev e, GDict a, Vector3 at, string hid)
        {
            // a W or an E (moba_kits.gd "spell"; the new heroes' Q too), at: the caster's place now
            var p2 = new Vector2(at.x, at.z);
            var root = _Root(e.S("id", ""));
            var id = e.S("id", "");
            var c1 = _Col(hid, 0);
            var c2 = _Col(hid, 1);
            Vector2 dir = _Ev(e, "dir", new Vector2(0, 1)).V2.Normalized();
            switch (sp)
            {
                // ---- knight ----
                case "bash":
                    _DashFx(id, C("#bcd8ff"), "streak");
                    Fan(p2, dir, C("#dce8ff"), 3.0, 0.5, 0.3, GDict.Of("speed", 8.0, "core", 0.6));
                    Flash(at + new Vector3(0, 1.1, 0) + new Vector3(dir.x, 0, dir.y) * 0.8, C("#ffffff"), 1.6, 0.25, "ring");
                    _Dust(at, C("#d8cfb8"), 8, 0.6);
                    break;
                case "rally":
                {
                    var r = (double)_Ev(e, "r", 7.0);
                    Disc(p2, C("#ffd65a"), r, 1.2, 1, GDict.Of("tex", "rays", "spin", 1.2, "grow", 0.5, "out", 0.5));
                    Wave(p2, C("#ffe9a6"), 0.5, r, 0.6);
                    Pillar(at, C("#ffd65a"), 0.35, 4.0, 0.7, GDict.Of("top", 0.6, "speed", 3.0, "out", 0.4, "core", 0.15, "energy", 0.7));
                    foreach (var o in view.sim.units)
                    {
                        if ((int)o.team == e.I("team", -1) && (bool)o.hero && view.sim.Alive(o)
                                && o.pos.DistanceTo(p2) <= r)
                        {
                            var ro = _Root(GD.Str(o.id));
                            if (ro != null)
                            {
                                _Sparkles(ro.Position + new Vector3(0, 0.5, 0), C("#ffe9a6"), 10, 0.5, 2.0, 1.0, "star");
                                _shield_style[GD.Str(o.id)] = GDict.Of("col", C("#ffd65a"), "style", 0);
                            }
                        }
                    }
                    Shake(0.1, p2);
                    break;
                }
                // ---- crusader ----
                case "block":
                    _BlockUp(id, C("#ffe9a6"));
                    break;
                case "consecrate":
                {
                    var r = (double)_Ev(e, "r", 4.0);
                    Pillar(at, C("#ffe9a6"), 0.25, 5.0, 0.8, GDict.Of("top", 0.5, "speed", 4.0, "out", 0.5, "core", 0.15, "energy", 0.6));
                    Wave(p2, C("#ffe9a6"), 0.3, r, 0.6);
                    Flash(at + new Vector3(0, 2.4, 0), C("#fff1a8"), 1.8, 0.4, "star");
                    _Sparkles(at + new Vector3(0, 0.3, 0), C("#fff6d8"), 16, r * 0.6, 1.5, 1.2, "sparkle");
                    break;
                }
                // ---- barbarian ----
                case "leap":
                    _Dust(at, C("#d8c8a8"), 10, 0.7, 1.2, 0.9, 3.0);
                    _DashFx(id, C("#ffb04a"), "streak", 0.6);
                    break;
                case "bloodlust":
                    Shell(root, C("#ff3a2a"), 1.1, 2.4, 2, 0.5, GDict.Of("energy", 1.3, "speed", 3.0));
                    _Embers(at + new Vector3(0, 0.8, 0), C("#ff6a2a"), 24, 0.8, 3.5);
                    Disc(p2, C("#ff3a2a"), 1.6, 0.6, 2, GDict.Of("out", 0.3));
                    Shake(0.1, p2);
                    break;
                // ---- berserker ----
                case "charge":
                    _DashFx(id, C("#ff4a2a"), "flame", 0.7);
                    Fan(p2, dir, C("#ff6a3a"), 3.5, 0.35, 0.3, GDict.Of("speed", 10.0, "core", 0.7));
                    _Dust(at, C("#c8b098"), 10, 0.6, 1.3, 0.9, 3.5);
                    Shake(0.1, p2);
                    break;
                case "frenzy":
                    Wave(p2, C("#ff2a2a"), 0.3, 2.6, 0.45, 1.5);
                    Shell(root, C("#ff2a2a"), 1.0, 2.3, 2, 0.6, GDict.Of("energy", 1.4, "speed", 4.0));
                    Burst(at + new Vector3(0, 1.0, 0), C("#ff3a3a"), GDict.Of("n", 18, "life", 0.6, "size", 0.5, "tex", "crescent", "core", 0.6,
                        "shape", "sphere", "r", 0.3, "vel", GArray.Of(3.0, 6.0), "damp", 4.0, "angle", 180.0, "spin", 500.0, "fade", "hot", "shape_life", "shrink"));
                    _Sparkles(at + new Vector3(0, 0.6, 0), C("#7dff6a"), 8, 0.5, 2.0, 0.9);      // (the heal)
                    break;
                // ---- rogue ----
                case "caltrops":
                {
                    Vector2 c3 = _Ev(e, "c", p2).V2;
                    var r = (double)_Ev(e, "r", 3.0);
                    Burst(at + new Vector3(0, 1.2, 0), C("#d8d8d8"), GDict.Of("n", 22, "life", 0.8, "size", 0.26, "tex", "shard", "core", 0.3,
                        "shape", "point", "dir", (new Vector3(c3.x, 0, c3.y) - at + new Vector3(0, 4.0, 0)).NormalizedChecked(), "spread", 18.0,
                        "vel", GArray.Of(7.0, 10.0), "grav", new Vector3(0, -12.0, 0), "angle", 180.0, "spin", 600.0, "fade", "late", "rand", 0.2));
                    Flash(at + new Vector3(0, 1.3, 0), C("#ffffff"), 0.8, 0.2, "sparkle");
                    break;
                }
                case "poison":
                    Burst(at + new Vector3(0, 1.1, 0), C("#7dff6a"), GDict.Of("n", 22, "life", 0.8, "size", 0.2, "tex", "dot", "core", 0.8, "shape", "sphere",
                        "r", 0.5, "vel", GArray.Of(0.3, 1.5), "grav", new Vector3(0, -5.0, 0), "fade", "slow", "shape_life", "shrink"));
                    Shell(root, C("#5dff4a"), 0.9, 2.2, 0, 0.5, GDict.Of("energy", 1.2));
                    if (root != null)
                    {
                        _Hold("poison:" + id, GArray.Of(Burst(new Vector3(0, 1.0, 0), C("#7dff6a"), GDict.Of("n", 24, "life", 0.7, "size", 0.22, "tex", "dot", "core", 0.8,
                            "shape", "sphere", "r", 0.45, "vel", GArray.Of(0.1, 0.6), "grav", new Vector3(0, -2.5, 0), "fade", "slow", "dur", 30.0, "parent", root,
                            "explode", 0.0))), _AliveWhile(id, uu => (int)uu.poison_n > 0));
                    }
                    break;
                // ---- assassin ----
                case "shadowstep":
                {
                    Vector2 from = _Ev(e, "from", p2).V2;
                    Vector2 to = _Ev(e, "to", p2).V2;
                    Burst(_G(from, 0.9), C("#2a1a4a"), GDict.Of("n", 12, "life", 0.8, "size", 1.3, "tex", "smoke", "core", 0.0, "blend", "mix", "shape", "sphere", "r", 0.4,
                        "vel", GArray.Of(0.5, 1.5), "shape_life", "swell", "fade", "late", "alpha", 0.7, "angle", 180.0, "spin", 40.0));
                    _Sparkles(_G(from, 0.6), C("#8a5bff"), 8, 0.4, 1.5, 0.7);
                    var fv = _G(from, 1.0);
                    var tv = _G(to, 1.0);
                    Beam(fv, tv, C("#8a5bff"), 0.5, 0.25, GDict.Of("speed", 12.0, "core", 0.5, "out", 0.2));
                    Flash(tv + new Vector3(0, 0.3, 0), C("#d8c8ff"), 2.2, 0.3, "crescent");
                    Burst(tv, C("#2a1a4a"), GDict.Of("n", 10, "life", 0.7, "size", 1.2, "tex", "smoke", "core", 0.0, "blend", "mix", "shape", "sphere", "r", 0.4,
                        "vel", GArray.Of(0.5, 1.5), "shape_life", "swell", "fade", "late", "alpha", 0.6, "angle", 180.0, "spin", 40.0));
                    break;
                }
                case "knives":
                {
                    var r = (double)_Ev(e, "r", 5.5);
                    var arc = (double)_Ev(e, "arc", 0.7);
                    Fan(p2, dir, C("#8a5bff"), r, arc, 0.35, GDict.Of("speed", 9.0, "core", 0.3, "fade_end", 0.6));
                    _Shards(at + new Vector3(0, 1.1, 0), C("#e8e0ff"), dir, 12, arc, 16.0, r);
                    Flash(at + new Vector3(0, 1.1, 0), C("#d8c8ff"), 1.2, 0.2, "sparkle");
                    break;
                }
                case "feint":
                    _DashFx(id, C("#c9b8ff"), "streak", 0.3);
                    Burst(at + new Vector3(0, 1.0, 0), C("#8a5bff"), GDict.Of("n", 14, "life", 0.6, "size", 0.3, "tex", "sparkle", "core", 0.9, "shape", "sphere",
                        "r", 1.2, "radial", -4.0, "vel", GArray.Of(0.0, 0.3), "fade", "slow", "shape_life", "shrink"));
                    Burst(at + new Vector3(0, 0.8, 0), C("#3a2a5a"), GDict.Of("n", 8, "life", 0.7, "size", 1.2, "tex", "smoke", "core", 0.0, "blend", "mix", "shape", "sphere", "r", 0.4,
                        "vel", GArray.Of(0.3, 1.0), "shape_life", "swell", "fade", "late", "alpha", 0.6, "angle", 180.0, "spin", 40.0));
                    break;
                // ---- ranger ----
                case "tumble":
                    _DashFx(id, C("#d8c8a8"), "smoke", 0.4);
                    Burst(at + new Vector3(0, 0.6, 0), C("#8fe36a"), GDict.Of("n", 8, "life", 1.2, "size", 0.3, "tex", "leaf", "core", 0.3, "shape", "sphere", "r", 0.5,
                        "vel", GArray.Of(1.0, 2.5), "grav", new Vector3(0, -1.0, 0), "turb", 1.0, "angle", 180.0, "spin", 200.0, "fade", "slow"));
                    break;
                case "snare":
                {
                    var tip = at + new Vector3(dir.x, 0.0, dir.y) * 0.8 + new Vector3(0, 1.2, 0);
                    Flash(tip, C("#e8ffd0"), 1.1, 0.2, "sparkle");
                    Beam(tip, tip + new Vector3(dir.x, 0.0, dir.y) * 4.0, C("#8fe36a"), 0.35, 0.3, GDict.Of("speed", 14.0, "core", 0.5, "fade_end", 0.7));
                    Burst(tip, C("#6fbf3a"), GDict.Of("n", 10, "life", 0.6, "size", 0.26, "tex", "leaf", "core", 0.3, "shape", "point", "dir", new Vector3(dir.x, 0.2, dir.y),
                        "spread", 25.0, "vel", GArray.Of(4.0, 8.0), "damp", 3.0, "angle", 180.0, "spin", 300.0, "fade", "slow"));
                    break;
                }
                // ---- sniper ----
                case "trap":
                    Flash(at + new Vector3(0, 0.3, 0), C("#ffffff"), 0.9, 0.25, "sparkle");
                    Burst(at + new Vector3(0, 0.2, 0), C("#d8d0c0"), GDict.Of("n", 8, "life", 0.5, "size", 0.14, "tex", "dot", "core", 1.0, "shape", "sphere", "r", 0.3,
                        "vel", GArray.Of(1.0, 3.0), "grav", new Vector3(0, -8.0, 0), "fade", "hot"));
                    break;
                case "mark":
                {
                    var tid = e.S("target", "");
                    var tr = _Root(tid);
                    if (tr != null)
                    {
                        Vector3 tp = tr.Position;
                        Beam(at + new Vector3(0, 1.4, 0), tp + new Vector3(0, 1.3, 0), C("#ff4a4a"), 0.25, 0.3, GDict.Of("speed", 16.0, "core", 0.6, "fade_end", 0.2));
                        Flash(tp + new Vector3(0, 2.6, 0), C("#ff4a4a"), 1.4, 0.5, "ring");
                        Flash(tp + new Vector3(0, 2.6, 0), C("#ffffff"), 0.6, 0.4, "sparkle");
                        _amp_style[tid] = GDict.Of("col", C("#ff4a4a"), "tex", "rays", "spin", 2.5);
                    }
                    break;
                }
                // ---- mage ----
                case "pillar":
                {
                    Vector2 c3 = _Ev(e, "c", p2).V2;
                    _Sparkles(at + new Vector3(0, 1.2, 0), C("#ffd24a"), 8, 0.4, 1.0, 0.5);
                    Beam(at + new Vector3(0, 1.3, 0), _G(c3, 0.3), C("#ff8a3a"), 0.3, 0.35, GDict.Of("speed", 10.0, "core", 0.4));
                    break;
                }
                case "blink":
                {
                    Vector2 from = _Ev(e, "from", p2).V2;
                    Vector2 to = _Ev(e, "to", p2).V2;
                    var fv = _G(from, 1.0);
                    var tv = _G(to, 1.0);
                    Burst(fv, C("#8fc8ff"), GDict.Of("n", 16, "life", 0.5, "size", 0.3, "tex", "sparkle", "core", 0.9, "shape", "sphere", "r", 1.3,
                        "radial", -6.0, "vel", GArray.Of(0.0, 0.2), "fade", "slow", "shape_life", "shrink"));
                    Flash(fv, C("#ffffff"), 1.6, 0.25, "ring");
                    Beam(fv, tv, C("#8fc8ff"), 0.6, 0.3, GDict.Of("speed", 14.0, "core", 0.6, "out", 0.25));
                    Flash(tv, C("#dff0ff"), 2.0, 0.3, "star");
                    _Sparkles(tv - new Vector3(0, 0.5, 0), C("#8fc8ff"), 14, 0.4, 2.0, 0.8);
                    Wave(to, C("#8fc8ff"), 0.2, 2.2, 0.4);
                    break;
                }
                // ---- archmage ----
                case "missiles":
                    Flash(at + new Vector3(0, 1.3, 0), C("#c070ff"), 1.4, 0.3, "runes", 0.6, false, 3.0);
                    _Sparkles(at + new Vector3(0, 1.2, 0), C("#ff6ad0"), 10, 0.4, 1.0, 0.6);
                    break;
                case "manashield":
                    Burst(at + new Vector3(0, 1.0, 0), C("#7fb8ff"), GDict.Of("n", 18, "life", 0.6, "size", 0.3, "tex", "runes", "grid", 2.0, "core", 0.6,
                        "shape", "sphere", "r", 1.6, "radial", -4.0, "vel", GArray.Of(0.0, 0.3), "fade", "slow", "shape_life", "shrink", "angle", 30.0));
                    Flash(at + new Vector3(0, 1.0, 0), C("#dff0ff"), 2.4, 0.3, "ring");
                    _shield_style[id] = GDict.Of("col", C("#7fb8ff"), "style", 0);
                    break;
                // ---- priest ----
                case "holylight":
                {
                    var tid = e.S("target", "");
                    var tr = _Root(tid);
                    if (tr != null)
                    {
                        Vector3 tp = tr.Position;
                        Pillar(tp, C("#ffe9a6"), 0.4, 6.0, 0.9, GDict.Of("top", 0.6, "speed", 4.0, "out", 0.5, "core", 0.2, "energy", 0.75));
                        Disc(new Vector2(tp.x, tp.z), C("#fff1a8"), 1.8, 0.9, 1, GDict.Of("tex", "rays", "spin", 1.5, "out", 0.4, "energy", 0.8));
                        Burst(tp + new Vector3(0, 3.0, 0), C("#fff6d8"), GDict.Of("n", 20, "life", 1.0, "size", 0.3, "tex", "sparkle", "core", 0.9,
                            "shape", "box", "ext", new Vector3(0.8, 0.1, 0.8), "dir", Vector3.DOWN, "spread", 10.0, "vel", GArray.Of(2.0, 4.0), "fade", "slow",
                            "shape_life", "pop", "angle", 180.0));
                        Flash(tp + new Vector3(0, 1.3, 0), C("#fff6d8"), 1.6, 0.35, "star");
                    }
                    break;
                }
                case "dazzle":
                {
                    var r = (double)_Ev(e, "r", 4.5);
                    Flash(at + new Vector3(0, 1.4, 0), C("#ffffff"), 4.5, 0.3, "star", 1.0);
                    Flash(at + new Vector3(0, 1.4, 0), C("#fff1a8"), 3.0, 0.5, "rays", 0.9);
                    Wave(p2, C("#ffffff"), 0.3, r, 0.4, 1.5);
                    Burst(at + new Vector3(0, 1.3, 0), C("#ffffff"), GDict.Of("n", 24, "life", 0.6, "size", 0.4, "tex", "sparkle", "core", 1.0, "shape", "point",
                        "vel", GArray.Of(6.0, 11.0), "damp", 6.0, "fade", "hot", "shape_life", "shrink", "angle", 180.0, "spin", 200.0));
                    break;
                }
                // ---- necromancer ----
                case "boneshield":
                {
                    var tid = e.S("target", "");
                    var tr = _Root(tid);
                    if (tr != null)
                    {
                        Burst(tr.Position + new Vector3(0, 1.0, 0), C("#e8e0c8"), GDict.Of("n", 14, "life", 0.7, "size", 0.3, "tex", "shard", "core", 0.2,
                            "shape", "sphere", "r", 1.4, "radial", -3.0, "orbit", 1.0, "vel", GArray.Of(0.0, 0.3), "fade", "slow", "angle", 180.0, "spin", 200.0));
                        _Sparkles(tr.Position + new Vector3(0, 0.6, 0), C("#7dff8a"), 8, 0.5, 1.5, 0.7);
                        _shield_style[tid] = GDict.Of("col", C("#d8d0b8"), "style", 1);
                    }
                    break;
                }
                case "curse":
                {
                    var tid = e.S("target", "");
                    var tr = _Root(tid);
                    if (tr != null)
                    {
                        Vector3 tp = tr.Position;
                        Beam(at + new Vector3(0, 1.4, 0), tp + new Vector3(0, 1.2, 0), C("#b04aff"), 0.45, 0.35, GDict.Of("speed", 8.0, "core", 0.3));
                        Burst(tp + new Vector3(0, 0.9, 0), C("#4a1a6a"), GDict.Of("n", 12, "life", 1.0, "size", 1.2, "tex", "smoke", "core", 0.0, "blend", "mix", "shape", "sphere",
                            "r", 0.5, "vel", GArray.Of(0.3, 1.0), "shape_life", "swell", "fade", "late", "alpha", 0.7, "angle", 180.0, "spin", 40.0));
                        Burst(tp + new Vector3(0, 2.2, 0), C("#7dff8a"), GDict.Of("n", 10, "life", 1.0, "size", 0.3, "tex", "runes", "grid", 2.0, "core", 0.5,
                            "shape", "sphere", "r", 0.5, "vel", GArray.Of(0.1, 0.4), "grav", new Vector3(0, -2.0, 0), "fade", "slow", "angle", 30.0));
                        _amp_style[tid] = GDict.Of("col", C("#b04aff"), "tex", "runes", "spin", -1.2);
                    }
                    break;
                }
                // ---- golem ----
                case "boulder":
                    _Dust(at + new Vector3(dir.x, 0, dir.y) * 0.5, C("#c8b89a"), 8, 0.5, 1.0, 0.8, 2.0);
                    _Rocks(at + new Vector3(0, 1.4, 0), 6, 0.3, 0.16, 4.0, 0.9);
                    break;
                case "stoneskin":
                    _Rocks(at + new Vector3(0, 0.9, 0), 10, 0.6, 0.18, 3.0, 1.0);
                    _Dust(at, C("#c8b8a0"), 8, 0.6, 1.2, 0.9, 2.0);
                    Disc(p2, C("#c8b48a"), 1.8, 0.8, 1, GDict.Of("tex", "cracks", "out", 0.4));
                    _skin_style[id] = GDict.Of("col", C("#b8b2a4"));
                    break;
                case "quake":
                {
                    var r = (double)_Ev(e, "r", 4.0);
                    Disc(p2, C("#ffb04a"), r, 1.2, 1, GDict.Of("tex", "cracks", "grow", 0.25, "out", 0.6, "energy", 1.2, "scorch", 0.35, "scorch_out", 2.5, "scorch_col", new Color(0.12, 0.09, 0.05)));
                    Wave(p2, C("#c8b48a"), 0.4, r + 0.5, 0.5);
                    _Rocks(at + new Vector3(0, 0.3, 0), 18, r * 0.5, 0.26, 7.0);
                    _Dust(at, C("#c8b89a"), 16, r * 0.6, 1.8, 1.3, 3.0);
                    view.Shockwave(at, r);
                    Shake(0.3, p2, 10.0);
                    break;
                }
                // ---- dragoon ----
                case "sweep":
                {
                    var r = (double)_Ev(e, "r", 3.8);
                    var arc = (double)_Ev(e, "arc", 1.05);
                    Fan(p2, dir, C("#ff7a3a"), r, arc, 0.3, GDict.Of("speed", 12.0, "core", 0.6, "fade_end", 0.3, "up", 0.9));
                    Flash(at + new Vector3(dir.x, 0, dir.y) * r * 0.5 + new Vector3(0, 1.0, 0), C("#ffd890"), r * 1.3, 0.25, "crescent", 0.7, true, 6.0);
                    _Sparkles(at + new Vector3(dir.x, 0, dir.y) * r * 0.5 + new Vector3(0, 0.9, 0), C("#ffd890"), 10, r * 0.4, 1.0, 0.5);
                    break;
                }
                case "impale":
                {
                    var len = (double)_Ev(e, "len", 6.0);
                    var tip = at + new Vector3(0, 1.0, 0);
                    var far = tip + new Vector3(dir.x, 0, dir.y) * len;
                    Beam(tip, far, C("#ff7a3a"), 0.5, 0.35, GDict.Of("speed", 16.0, "core", 0.7, "fade_end", 0.15, "in", 0.03));
                    Flash(far, C("#ffd890"), 1.4, 0.3, "sparkle");
                    Burst(far, C("#ffd890"), GDict.Of("n", 16, "life", 0.5, "size", 0.3, "tex", "streak", "core", 0.7, "shape", "point", "dir", -new Vector3(dir.x, 0, dir.y),
                        "spread", 8.0, "vel", GArray.Of(len * 1.8, len * 2.2), "fade", "slow", "align", false, "angle", 0.0));    // (the pull, back to him)
                    break;
                }
                case "vault":
                    _Dust(at, C("#d8c8a8"), 8, 0.6, 1.2, 0.9, 3.0);
                    _DashFx(id, C("#ffcf8a"), "streak", 0.5);
                    break;
                // ---- duelist ----
                case "thrust":
                {
                    var far = at + new Vector3(dir.x, 0, dir.y) * 5.0 + new Vector3(0, 1.0, 0);
                    Beam(at + new Vector3(0, 1.0, 0), far, C("#ffffff"), 0.25, 0.3, GDict.Of("speed", 20.0, "core", 0.8, "fade_end", 0.1, "in", 0.02));
                    _DashFx(id, C("#ffe27a"), "streak", 0.35);
                    Flash(at + new Vector3(dir.x, 0, dir.y) * 1.2 + new Vector3(0, 1.1, 0), C("#ffffff"), 1.0, 0.2, "sparkle");
                    break;
                }
                case "riposte":
                    Shell(root, C("#ffe27a"), 1.0, 2.3, 0, 0.4, GDict.Of("energy", 1.3));
                    Flash(at + new Vector3(0, 1.2, 0), C("#fff4c0"), 1.6, 0.3, "ring");
                    break;
                case "feint_":
                    break;
                // ---- stormcaller ----
                case "chain":
                {
                    GArray pts = _EvArr(e, "pts");
                    var prev = at + new Vector3(0, 1.4, 0);
                    Flash(prev, C("#e8f4ff"), 1.4, 0.25, "sparkle");
                    for (int i = 0; i < pts.Size(); i++)
                    {
                        var pb = _G(pts[i].V2, 1.1);
                        if (i > 0)
                            prev = _G(pts[i - 1].V2, 1.1);
                        Bolt(prev, pb, C("#7fb8ff"), 0.4, 0.6, 0.16, 1);
                        _ZapHit(pb, C("#7fb8ff"), 0.8);
                    }
                    break;
                }
                case "static":
                {
                    Vector2 c3 = _Ev(e, "c", p2).V2;
                    Bolt(_G(c3, 9.0) + new Vector3(GD.RandfRange(-1, 1), 0, GD.RandfRange(-1, 1)), _G(c3, 0.3), C("#6fb4ff"), 0.3, 1.4, 0.2, 2);
                    _ZapHit(_G(c3, 0.4), C("#9fd4ff"), 1.2);
                    break;
                }
                case "gust":
                {
                    var r = (double)_Ev(e, "r", 5.0);
                    var arc = (double)_Ev(e, "arc", 0.8);
                    Fan(p2, dir, C("#d8f4ff"), r, arc, 0.45, GDict.Of("speed", 18.0, "scale", 4.0, "core", 0.2, "fade_end", 0.5, "up", 0.4, "energy", 0.8));
                    Burst(at + new Vector3(0, 0.8, 0), C("#e8f8ff"), GDict.Of("n", 26, "life", 0.6, "size", 0.9, "tex", "streak", "core", 0.4, "shape", "point",
                        "dir", new Vector3(dir.x, 0.1, dir.y), "spread", GD.RadToDeg(arc), "vel", GArray.Of(r * 1.6, r * 2.2), "fade", "slow", "angle", 0.0, "shape_life", "grow"));
                    Burst(at + new Vector3(0, 0.3, 0), C("#b8d8a0"), GDict.Of("n", 12, "life", 1.0, "size", 0.24, "tex", "leaf", "core", 0.2, "shape", "point",
                        "dir", new Vector3(dir.x, 0.4, dir.y), "spread", GD.RadToDeg(arc), "vel", GArray.Of(r, r * 1.6), "damp", 2.0, "turb", 1.5, "angle", 180.0,
                        "spin", 400.0, "fade", "slow"));
                    break;
                }
                // ---- musketeer ----
                case "buckshot":
                {
                    var r = (double)_Ev(e, "r", 7.0);
                    var arc = (double)_Ev(e, "arc", 0.45);
                    var mz = at + new Vector3(dir.x, 0, dir.y) * 1.1 + new Vector3(0, 1.25, 0);
                    Flash(mz, C("#ffe8b0"), 2.2, 0.18, "star", 1.0);
                    Flash(mz, C("#ff8a3a"), 1.2, 0.25, "dot", 0.6);
                    Fan(p2, dir, C("#ffd890"), r * 0.7, arc, 0.25, GDict.Of("speed", 20.0, "core", 0.4, "fade_end", 0.6, "up", 1.0, "in", 0.02));
                    _Shards(mz, C("#fff0c8"), dir, 14, arc, 30.0, r);
                    Burst(mz, C("#c8c8c8"), GDict.Of("n", 8, "life", 1.4, "size", 1.0, "tex", "smoke", "core", 0.0, "blend", "mix", "shape", "point", "dir", new Vector3(dir.x, 0.3, dir.y),
                        "spread", 30.0, "vel", GArray.Of(2.0, 4.0), "damp", 3.0, "shape_life", "swell", "fade", "late", "alpha", 0.5, "angle", 180.0, "spin", 40.0));
                    Shake(0.12, p2, 8.0);
                    break;
                }
                case "keg":
                {
                    Vector2 c3 = _Ev(e, "c", p2).V2;
                    Flash(at + new Vector3(0, 1.4, 0), C("#ff8a3a"), 0.8, 0.2, "sparkle");
                    view._Lob(at + new Vector3(0, 1.4, 0), _G(c3, 0.3), (double)_Ev(e, "delay", 0.8), C("#6a4a2a"));
                    Burst(at + new Vector3(0, 1.4, 0), C("#ffb04a"), GDict.Of("n", 10, "life", 0.5, "size", 0.14, "tex", "dot", "core", 1.0, "shape", "point",
                        "vel", GArray.Of(1.0, 3.0), "grav", new Vector3(0, -6.0, 0), "fade", "hot"));
                    break;
                }
                case "smokeroll":
                    _DashFx(id, C("#c8c8c8"), "smoke", 0.4);
                    Burst(at + new Vector3(0, 0.8, 0), C("#b8b8b8"), GDict.Of("n", 12, "life", 1.5, "size", 1.6, "tex", "smoke", "core", 0.0, "blend", "mix", "shape", "sphere", "r", 0.6,
                        "vel", GArray.Of(1.0, 2.5), "damp", 2.0, "shape_life", "swell", "fade", "late", "alpha", 0.55, "angle", 180.0, "spin", 40.0));
                    break;
                // ---- druid ----
                case "rejuv":
                {
                    var tid = e.S("target", "");
                    var tr = _Root(tid);
                    if (tr != null)
                    {
                        _Sparkles(tr.Position + new Vector3(0, 0.4, 0), C("#8dff6a"), 12, 0.5, 2.5, 1.0);
                        _Hold("rejuv:" + tid, GArray.Of(Burst(new Vector3(0, 0.3, 0), C("#8dff6a"), GDict.Of("n", 30, "life", 1.4, "size", 0.4, "tex", "leaf", "core", 0.3,
                            "shape", "ring", "r", 0.7, "inner", 0.6, "h", 0.2, "dir", Vector3.UP, "spread", 20.0, "vel", GArray.Of(0.8, 1.4), "orbit", 0.6,
                            "angle", 180.0, "spin", 120.0, "fade", "slow", "dur", (double)_Ev(e, "dur", 5.0), "parent", tr, "explode", 0.0, "local", true))),
                            _AliveWhile(tid, u => u.dots != null));
                    }
                    break;
                }
                case "entangle":
                {
                    Vector2 c3 = _Ev(e, "c", p2).V2;
                    Disc(c3, C("#6fbf3a"), (double)_Ev(e, "r", 1.8) + 0.4, (double)_Ev(e, "delay", 0.5) + 0.2, 4, GDict.Of("in", 0.1, "out", 0.15, "energy", 1.3));
                    _Sparkles(at + new Vector3(0, 1.0, 0), C("#8dff6a"), 8, 0.4, 1.5, 0.6, "leaf");
                    break;
                }
                case "barkskin":
                {
                    var tid = e.S("target", "");
                    var tr = _Root(tid);
                    if (tr != null)
                    {
                        Burst(tr.Position + new Vector3(0, 0.8, 0), C("#a07a4a"), GDict.Of("n", 14, "life", 1.0, "size", 0.3, "tex", "leaf", "core", 0.2,
                            "shape", "sphere", "r", 1.2, "radial", -2.5, "orbit", 1.2, "vel", GArray.Of(0.0, 0.3), "fade", "slow", "angle", 180.0, "spin", 200.0));
                        _Sparkles(tr.Position + new Vector3(0, 0.5, 0), C("#8dff6a"), 8, 0.5, 1.5, 0.8);
                        _skin_style[tid] = GDict.Of("col", C("#a07a4a"));
                    }
                    break;
                }
                default:
                    view.RingAt(at, c1, 2.2, 0.45);
                    _Sparkles(at + new Vector3(0, 0.6, 0), c2, 8, 0.5, 1.5);
                    break;
            }
        }

        public GDict _shield_style = new GDict();          // unit id -> {col, style}: the last shield cast on him (what its bubble looks like)
        public GDict _amp_style = new GDict();             // unit id -> {col, tex, spin}: a mark or a curse
        public GDict _skin_style = new GDict();            // unit id -> {col}: stone or bark
        public GDict _dash_style = new GDict();            // unit id -> {col, tex, at, dur}: the dash just cast (its trail)

        public void _DashFx(string id, Color col, string nm, double dur = 0.5)
        {
            _dash_style[id] = GDict.Of("col", col, "tex", nm, "at", _time, "dur", dur);
        }

        public void _BlockUp(string id, Color col)
        {
            var root = _Root(id);
            if (root == null)
                return;
            Unit u = view.sim.by_id.TryGetValue(id, out var uu) ? uu : null;
            var face = u != null ? (double)u.face : 0.0;
            var f = new Vector2(Math.Sin(face), Math.Cos(face));
            Vector3 at = root.Position + new Vector3(f.x, 0, f.y) * 0.9 + new Vector3(0, 1.1, 0);
            Flash(at, col, 1.8, 0.3, "ring");
            _Sparkles(at, C("#ffffff"), 6, 0.4, 0.8, 0.5);
        }

        public void _ZapHit(Vector3 at, Color col, double size)
        {
            Flash(at, C("#ffffff"), 1.4 * size, 0.2, "sparkle", 1.0);
            Burst(at, col, GDict.Of("n", 10, "life", 0.4, "size", 0.5 * size, "tex", "lightning", "core", 0.9, "shape", "sphere", "r", 0.2 * size,
                "vel", GArray.Of(1.0, 3.0), "fade", "flicker", "angle", 180.0, "spin", 100.0, "shape_life", "shrink"));
            Wave(new Vector2(at.x, at.z), col, 0.2, 1.6 * size, 0.35);
        }

        // ======================================================================================================================
        // the ultimates
        // ======================================================================================================================
        public void Ult(string hid, GDict e, GDict a, Vector3 at) => Ult(hid, SiegeNet.ToEv(Var.Of(e)), a, at);

        public void Ult(string hid, Ev e, GDict a, Vector3 at)
        {
            var p2 = new Vector2(at.x, at.z);
            var id = e.S("id", "");
            var root = _Root(id);
            switch (hid)
            {
                case "knight":                                  // BULWARK: a golden dome over them all
                {
                    var r = (double)Moba.BULWARK_R;
                    Disc(p2, C("#ffd65a"), r * 0.85, 1.5, 1, GDict.Of("tex", "rays", "spin", 0.8, "grow", 0.5, "out", 0.8, "energy", 0.75));
                    Wave(p2, C("#ffe9a6"), 0.5, r, 0.7, 1.4);
                    Pillar(at, C("#ffd65a"), 0.45, 6.0, 0.8, GDict.Of("top", 0.7, "speed", 4.0, "out", 0.5, "core", 0.2, "energy", 0.7));
                    Flash(at + new Vector3(0, 1.4, 0), C("#fff1a8"), 2.4, 0.4, "star");
                    if (root != null)
                    {
                        var dome = Shell(root, new Color(C("#ffd65a"), 0.45), r, r * 2.0, 3, -1.0, GDict.Of("energy", 0.8, "speed", 0.6, "y", 0.2, "key", "bulwark:" + id,
                            "alive", _AliveUntil(id, "dr_until"), "in", 0.4, "out", 0.6));
                        dome.Scale = new Vector3(1.0, 0.55, 1.0);
                    }
                    foreach (var oid in _EvArr(e, "ids"))
                    {
                        var ro = _Root(GD.Str(oid));
                        if (ro != null)
                            _Sparkles(ro.Position + new Vector3(0, 0.5, 0), C("#ffe9a6"), 10, 0.5, 2.0, 1.0, "star");
                    }
                    Shake(0.2, p2);
                    break;
                }
                case "barbarian":                               // WAR CRY: a roar of fire
                    for (int i = 0; i < 3; i++)
                        Wave(p2, C("#ff6a2a"), 0.3, 5.0 + 2.5 * i, 0.5 + 0.2 * i, 1.4);
                    Disc(p2, C("#ff5a2a"), 4.0, 0.9, 2, GDict.Of("grow", 0.35, "out", 0.5, "energy", 1.2, "scorch", 0.4, "scorch_out", 2.0));
                    _Flames(at, C("#ff6a2a"), 30, 1.6, 0.7, 1.2);
                    _Embers(at + new Vector3(0, 0.8, 0), C("#ffb04a"), 30, 1.0, 4.0);
                    Flash(at + new Vector3(0, 1.4, 0), C("#ffb04a"), 4.0, 0.4, "rays", 0.9);
                    view.Shockwave(at + new Vector3(0, 0.3, 0), 5.0);
                    Shake(0.35, p2);
                    break;
                case "rogue":                                   // EXECUTE: out of the dark, the kill
                {
                    Vector2 from = _Ev(e, "from", p2).V2;
                    Vector2 to = _Ev(e, "to", p2).V2;
                    Burst(_G(from, 0.9), C("#3a2a5a"), GDict.Of("n", 12, "life", 0.8, "size", 1.4, "tex", "smoke", "core", 0.0, "blend", "mix", "shape", "sphere", "r", 0.4,
                        "vel", GArray.Of(0.5, 1.5), "shape_life", "swell", "fade", "late", "alpha", 0.7, "angle", 180.0, "spin", 40.0));
                    _Sparkles(_G(from, 0.6), C("#a070ff"), 10, 0.4, 1.5, 0.7);
                    var tr = _Root(e.S("target", ""));
                    Vector3 tp = tr != null ? tr.Position : _G(to);
                    Flash(tp + new Vector3(0, 1.3, 0), C("#d8c8ff"), 3.2, 0.35, "crescent", 0.8);
                    var f2 = Flash(tp + new Vector3(0, 1.3, 0), C("#d8c8ff"), 3.2, 0.35, "crescent", 0.8);
                    var rot2 = f2.Rotation;
                    rot2.z = (float)(GD.PI * 0.5);
                    f2.Rotation = rot2;
                    Flash(tp + new Vector3(0, 1.3, 0), C("#ff3a3a"), 1.8, 0.3, "star", 1.0);
                    Burst(tp + new Vector3(0, 1.1, 0), C("#a070ff"), GDict.Of("n", 20, "life", 0.5, "size", 0.5, "tex", "streak", "core", 0.8, "shape", "point",
                        "vel", GArray.Of(6.0, 12.0), "damp", 6.0, "fade", "hot", "shape_life", "shrink", "angle", 180.0));
                    Wave(to, C("#a070ff"), 0.3, 3.0, 0.4);
                    Shake(0.2, to);
                    break;
                }
                case "ranger":                                  // ARROW RAIN: the sky darkens with arrows
                {
                    Vector2 c3 = _Ev(e, "c", p2).V2;
                    var r = (double)_Ev(e, "r", 4.5);
                    var dur = (double)_Ev(e, "dur", 2.0);
                    Disc(c3, C("#8fe36a"), r, dur + 0.3, 1, GDict.Of("tex", "rays", "spin", -0.8, "grow", 0.3, "out", 0.5));
                    Wave(c3, C("#cfe8b8"), 0.3, r, 0.5);
                    Pillar(at, C("#cfe8b8"), 0.25, 7.0, 0.5, GDict.Of("top", 0.05, "speed", 12.0, "out", 0.3, "fade_end", 0.8, "core", 0.2, "energy", 0.8));
                    Burst(_G(c3, 9.0), C("#e8ffd0"), GDict.Of("n", 30, "life", 0.5, "size", 0.6, "tex", "streak", "core", 0.6, "shape", "box",
                        "ext", new Vector3(r * 0.7, 0.3, r * 0.7), "dir", Vector3.DOWN, "spread", 6.0, "vel", GArray.Of(14.0, 18.0), "align", true, "fade", "late",
                        "dur", dur, "angle", 0.0, "explode", 0.0, "rand", 0.1));
                    Burst(_G(c3, 0.3), C("#d8c8a8"), GDict.Of("n", 40, "life", 0.7, "size", 0.7, "tex", "smoke", "core", 0.0, "blend", "mix", "shape", "ring", "r", r * 0.8,
                        "inner", 0.0, "h", 0.1, "dir", Vector3.UP, "spread", 40.0, "vel", GArray.Of(0.8, 2.0), "damp", 2.0, "shape_life", "swell", "fade", "late",
                        "alpha", 0.4, "angle", 180.0, "spin", 30.0, "dur", dur, "explode", 0.0));
                    break;
                }
                case "mage":                                    // INFERNO: a wall of fire running out
                {
                    var r = (double)_Ev(e, "r", 7.0);
                    Disc(p2, C("#ff4a12"), r, 3.0, 2, GDict.Of("grow", 0.45, "out", 1.2, "energy", 1.1, "scorch", 0.55, "scorch_out", 4.0));
                    Wave(p2, C("#ffb04a"), 0.3, r, 0.55, 1.4);
                    Pillar(at, C("#ff8a2a"), 0.7, 6.0, 0.7, GDict.Of("top", 1.3, "speed", 5.0, "out", 0.45, "core", 0.25, "energy", 0.8));
                    Flash(at + new Vector3(0, 1.5, 0), C("#fff0c0"), 5.0, 0.4, "star", 1.0);
                    for (int i = 0; i < 3; i++)
                    {
                        var rr = r * (0.35 + 0.3 * i);
                        var ii = i;
                        GetTree().CreateTimer(0.12 * i).Timeout += () =>
                        {
                            _Flames(at, C("#ff6a1a"), 30, rr, 0.9, 2.2 + 0.3 * ii, -1.0, 4.0);
                            _Embers(at + new Vector3(0, 0.5, 0), C("#ffb04a"), 20, rr, 4.0);
                        };
                    }
                    Burst(at + new Vector3(0, 0.4, 0), C("#ff6a1a"), GDict.Of("n", 40, "life", 0.8, "size", 2.2, "tex", "flame", "core", 0.6, "shape", "ring", "r", r * 0.95,
                        "inner", 0.9, "h", 0.2, "dir", Vector3.UP, "spread", 15.0, "vel", GArray.Of(2.0, 4.0), "grav", new Vector3(0, 3.0, 0), "shape_life", "shrink",
                        "fade", "hot", "angle", 12.0, "spin", 20.0, "dur", 2.0, "explode", 0.0));
                    view.Shockwave(at + new Vector3(0, 0.3, 0), r);
                    Shake(0.5, p2, 20.0);
                    break;
                }
                case "priest":                                  // GRACE: light on every one of them
                    Disc(p2, C("#fff1a8"), 4.5, 1.4, 1, GDict.Of("tex", "rays", "spin", 1.0, "grow", 0.5, "out", 0.7, "energy", 0.8));
                    Flash(at + new Vector3(0, 1.4, 0), C("#fff1a8"), 3.0, 0.5, "star", 1.0);
                    foreach (var oid in _EvArr(e, "ids"))
                    {
                        var ro = _Root(GD.Str(oid));
                        if (ro != null && ro.Visible)
                        {
                            Vector3 tp = ro.Position;
                            Pillar(tp, C("#ffe9a6"), 0.4, 6.0, 1.2, GDict.Of("top", 0.6, "speed", 3.0, "out", 0.7, "core", 0.2, "energy", 0.75));
                            Disc(new Vector2(tp.x, tp.z), C("#fff1a8"), 1.8, 1.2, 1, GDict.Of("tex", "rays", "spin", 1.5, "out", 0.5, "energy", 0.8));
                            Burst(tp + new Vector3(0, 0.4, 0), C("#fff6d8"), GDict.Of("n", 18, "life", 1.2, "size", 0.3, "tex", "sparkle", "core", 0.9, "shape", "sphere",
                                "r", 0.6, "vel", GArray.Of(0.3, 1.0), "grav", new Vector3(0, 2.0, 0), "fade", "slow", "shape_life", "pop", "angle", 180.0, "spin", 60.0));
                        }
                    }
                    break;
                case "crusader":                                // JUDGMENT: a pillar from heaven
                {
                    var r = (double)_Ev(e, "r", 5.5);
                    Pillar(at, C("#ffe9a6"), 1.0, 11.0, 1.0, GDict.Of("top", 1.4, "speed", 5.0, "out", 0.55, "core", 0.2, "in", 0.05, "energy", 0.75));
                    Disc(p2, C("#ffd65a"), r, 1.6, 1, GDict.Of("tex", "rays", "spin", 2.0, "grow", 0.3, "out", 0.7, "energy", 0.9));
                    Wave(p2, C("#fff6d8"), 0.3, r + 0.5, 0.5, 1.6);
                    Flash(at + new Vector3(0, 2.0, 0), C("#fff6d8"), 4.0, 0.4, "star", 1.0);
                    Burst(at + new Vector3(0, 0.3, 0), C("#fff1a8"), GDict.Of("n", 30, "life", 1.0, "size", 0.4, "tex", "sparkle", "core", 0.9, "shape", "ring",
                        "r", r * 0.7, "inner", 0.1, "h", 0.2, "dir", Vector3.UP, "spread", 30.0, "vel", GArray.Of(2.0, 5.0), "grav", new Vector3(0, -3.0, 0),
                        "fade", "slow", "shape_life", "pop", "angle", 180.0, "spin", 60.0));
                    view.Shockwave(at + new Vector3(0, 0.3, 0), r);
                    Shake(0.45, p2, 20.0);
                    break;
                }
                case "berserker":                               // UNDYING: nothing takes him down
                    Wave(p2, C("#ff2a2a"), 0.3, 4.0, 0.5, 1.5);
                    Disc(p2, C("#7a0c0c"), 2.4, 1.0, 2, GDict.Of("out", 0.5, "energy", 1.5, "scorch", 0.5, "scorch_col", new Color(0.1, 0.0, 0.0)));
                    Burst(at + new Vector3(0, 1.0, 0), C("#ff2a2a"), GDict.Of("n", 24, "life", 0.7, "size", 0.5, "tex", "crescent", "core", 0.5, "shape", "sphere", "r", 0.4,
                        "vel", GArray.Of(4.0, 8.0), "damp", 5.0, "angle", 180.0, "spin", 500.0, "fade", "hot", "shape_life", "shrink"));
                    Burst(at + new Vector3(0, 1.2, 0), C("#2a0404"), GDict.Of("n", 10, "life", 1.0, "size", 1.6, "tex", "smoke", "core", 0.0, "blend", "mix", "shape", "sphere", "r", 0.5,
                        "vel", GArray.Of(0.5, 2.0), "shape_life", "swell", "fade", "late", "alpha", 0.7, "angle", 180.0, "spin", 40.0));
                    Flash(at + new Vector3(0, 1.3, 0), C("#ff4a2a"), 3.0, 0.4, "rays", 0.8);
                    Shake(0.3, p2);
                    break;
                case "assassin":                                // FLURRY: the first of the darts
                    Burst(at + new Vector3(0, 1.0, 0), C("#2a1a4a"), GDict.Of("n", 14, "life", 0.8, "size", 1.4, "tex", "smoke", "core", 0.0, "blend", "mix", "shape", "sphere", "r", 0.5,
                        "vel", GArray.Of(0.5, 2.0), "shape_life", "swell", "fade", "late", "alpha", 0.7, "angle", 180.0, "spin", 40.0));
                    Flash(at + new Vector3(0, 1.2, 0), C("#9a6bff"), 2.6, 0.3, "crescent", 0.8);
                    Wave(p2, C("#8a5bff"), 0.3, (double)Moba.FLURRY_R, 0.5);
                    break;
                case "sniper":                                  // DEADEYE: the shot across the field
                {
                    Unit u = view.sim.by_id.TryGetValue(id, out var uu) ? uu : null;
                    var face = u != null ? (double)u.face : 0.0;
                    var f = new Vector2(Math.Sin(face), Math.Cos(face));
                    var mz = at + new Vector3(f.x, 0, f.y) * 1.0 + new Vector3(0, 1.3, 0);
                    Flash(mz, C("#ffffff"), 3.4, 0.25, "star", 1.0);
                    Flash(mz, C("#bfefff"), 2.0, 0.4, "rays", 0.8);
                    Beam(mz, mz + new Vector3(f.x, 0, f.y) * (double)Moba.DEADEYE_RANGE, C("#bfefff"), 0.8, 0.9, GDict.Of("speed", 30.0, "core", 0.8,
                        "fade_end", 0.3, "in", 0.03, "out", 0.6, "grow", 0.25));
                    Burst(mz, C("#ffffff"), GDict.Of("n", 20, "life", 0.5, "size", 0.4, "tex", "sparkle", "core", 1.0, "shape", "point", "vel", GArray.Of(4.0, 9.0), "damp", 6.0,
                        "fade", "hot", "shape_life", "shrink", "angle", 180.0, "spin", 200.0));
                    Wave(p2, C("#bfefff"), 0.2, 3.0, 0.4);
                    Shake(0.3, p2);
                    break;
                }
                case "archmage":                                // METEORS: the sky called down
                {
                    Vector2 c3 = _Ev(e, "c", p2).V2;
                    Disc(c3, C("#c070ff"), (double)Moba.STORM_SPREAD + 2.0, 2.6, 1, GDict.Of("tex", "runes", "spin", 1.5, "grow", 0.4, "out", 0.8, "energy", 1.2));
                    Wave(c3, C("#ff6ad0"), 0.3, (double)Moba.STORM_SPREAD + 2.0, 0.6);
                    Flash(at + new Vector3(0, 1.4, 0), C("#c070ff"), 2.2, 0.4, "runes", 0.6, false, 4.0);
                    Pillar(at, C("#c070ff"), 0.3, 9.0, 0.6, GDict.Of("top", 0.05, "speed", 12.0, "out", 0.35, "fade_end", 0.7, "core", 0.2, "energy", 0.8));
                    break;
                }
                case "necromancer":                             // LEGION: the dead rise
                    Disc(p2, C("#7dff8a"), 4.0, 2.0, 1, GDict.Of("tex", "runes", "spin", -1.0, "grow", 0.5, "out", 0.8));
                    Burst(at + new Vector3(0, 0.3, 0), C("#1a3a1a"), GDict.Of("n", 16, "life", 1.6, "size", 1.8, "tex", "smoke", "core", 0.0, "blend", "mix", "shape", "ring", "r", 2.5,
                        "inner", 0.2, "h", 0.1, "dir", Vector3.UP, "spread", 40.0, "vel", GArray.Of(0.5, 1.5), "shape_life", "swell", "fade", "late", "alpha", 0.7,
                        "angle", 180.0, "spin", 30.0));
                    foreach (var oid in _EvArr(e, "ids"))
                    {
                        var zp = _UnitPos(GD.Str(oid));
                        if (zp != Vector2.INF)
                        {
                            Pillar(_G(zp, 0.0), C("#7dff8a"), 0.35, 4.0, 1.0, GDict.Of("top", 0.6, "speed", 3.0, "out", 0.6, "core", 0.2, "energy", 0.85));
                            Burst(_G(zp, 0.6), C("#e8e0c8"), GDict.Of("n", 10, "life", 0.9, "size", 0.26, "tex", "shard", "core", 0.2, "shape", "sphere", "r", 0.4,
                                "vel", GArray.Of(1.0, 3.0), "grav", new Vector3(0, -6.0, 0), "angle", 180.0, "spin", 300.0, "fade", "late"));
                        }
                    }
                    Flash(at + new Vector3(0, 1.4, 0), C("#7dff8a"), 2.6, 0.4, "runes", 0.6, false, -3.0);
                    break;
                case "golem":
                case "dragoon":
                case "duelist":
                case "stormcaller":
                case "musketeer":
                case "druid":
                    _NewUlt(e.S("spell", ""), e, a, at, id, root);
                    break;
                default:
                    view.RingAt(at, _Col(hid, 0), 2.6, 0.6);
                    break;
            }
        }

        public void _NewUlt(string sp, Ev e, GDict _a, Vector3 at, string id, Node3D root)
        {
            var p2 = new Vector2(at.x, at.z);
            switch (sp)
            {
                case "landslide":                               // the avalanche
                    _DashFx(id, C("#c8b89a"), "smoke", 0.7);
                    Wave(p2, C("#c8b48a"), 0.4, 4.0, 0.5);
                    _Rocks(at + new Vector3(0, 0.4, 0), 14, 1.0, 0.3, 6.0);
                    _Dust(at, C("#c8b89a"), 16, 1.0, 2.0, 1.3, 3.0);
                    if (root != null)
                    {
                        _Hold("slide:" + id, GArray.Of(Burst(new Vector3(0, 0.3, 0), C("#a89880"), GDict.Of("n", 18, "life", 0.8, "size", 0.3, "mesh", "rock", "shape", "sphere",
                            "r", 0.8, "dir", Vector3.UP, "spread", 70.0, "vel", GArray.Of(3.0, 6.0), "grav", new Vector3(0, -14.0, 0), "angle", 180.0, "spin", 500.0,
                            "fade", "late", "sizes", 0.5, "dur", 0.7, "parent", root, "explode", 0.0))), _AliveWhile(id, u => u.state == "dash"));
                    }
                    Shake(0.3, p2);
                    break;
                case "dragondive":                              // up in fire, down in fire
                {
                    Vector2 to = _Ev(e, "to", p2).V2;
                    _Flames(at, C("#ff7a3a"), 20, 0.8, 0.6, 1.2, -1.0, 6.0);
                    Pillar(at, C("#ff7a3a"), 0.4, 6.0, 0.5, GDict.Of("top", 0.1, "speed", 10.0, "out", 0.3, "fade_end", 0.7, "core", 0.2, "energy", 0.8));
                    _DashFx(id, C("#ff7a3a"), "flame", 1.0);
                    Disc(to, C("#ff3a2a"), (double)_Ev(e, "r", 3.5), 1.0, 1, GDict.Of("tex", "rays", "spin", 3.0, "energy", 1.3, "out", 0.2));
                    _Dust(at, C("#d8c8a8"), 10, 0.7, 1.4, 0.9, 3.5);
                    break;
                }
                case "challenge":                               // en garde
                {
                    var tr = _Root(e.S("target", ""));
                    Disc(p2, C("#ffe27a"), 3.0, 1.4, 1, GDict.Of("tex", "rays", "spin", 2.5, "out", 0.5));
                    Flash(at + new Vector3(0, 1.3, 0), C("#ffffff"), 2.4, 0.3, "star", 1.0);
                    if (tr != null)
                    {
                        Beam(at + new Vector3(0, 1.2, 0), tr.Position + new Vector3(0, 1.2, 0), C("#ffe27a"), 0.3, 0.3, GDict.Of("speed", 20.0, "core", 0.7));
                        Wave(new Vector2(tr.Position.x, tr.Position.z), C("#ffe27a"), 0.3, 3.0, 0.5);
                    }
                    break;
                }
                case "thunderstorm":                            // the storm gathers
                {
                    Vector2 c3 = _Ev(e, "c", p2).V2;
                    var r = (double)_Ev(e, "r", 5.0);
                    Pillar(at, C("#7fb8ff"), 0.25, 9.0, 0.5, GDict.Of("top", 0.05, "speed", 14.0, "out", 0.3, "fade_end", 0.7, "core", 0.2, "energy", 0.8));
                    Flash(at + new Vector3(0, 1.4, 0), C("#e8f4ff"), 2.0, 0.3, "sparkle", 1.0);
                    Bolt(at + new Vector3(0, 1.5, 0), _G(c3, 7.0), C("#7fb8ff"), 0.35, 1.0, 0.18, 2);
                    var dur = 4.5;
                    Burst(_G(c3, 7.5), C("#2a3a5a"), GDict.Of("n", 40, "life", 2.2, "size", 3.0, "tex", "smoke", "core", 0.0, "blend", "mix", "shape", "ring", "r", r * 0.9,
                        "inner", 0.0, "h", 0.6, "dir", Vector3.UP, "spread", 90.0, "vel", GArray.Of(0.2, 0.8), "damp", 0.5, "shape_life", "swell", "fade", "slow",
                        "alpha", 0.85, "angle", 180.0, "spin", 20.0, "dur", dur, "explode", 0.0, "rand", 0.4, "reach", 14.0));
                    Shake(0.25, p2, 20.0);
                    break;
                }
                case "quickdraw":                               // every shot at once
                {
                    Unit u = view.sim.by_id.TryGetValue(id, out var uu) ? uu : null;
                    var face = u != null ? (double)u.face : 0.0;
                    var f = new Vector2(Math.Sin(face), Math.Cos(face));
                    var mz = at + new Vector3(f.x, 0, f.y) * 1.0 + new Vector3(0, 1.3, 0);
                    Disc(p2, C("#ffd890"), 2.6, 0.9, 1, GDict.Of("tex", "rays", "spin", 4.0, "out", 0.4));
                    Flash(mz, C("#ffffff"), 2.6, 0.25, "star", 1.0);
                    Burst(mz, C("#c8c8c8"), GDict.Of("n", 12, "life", 1.6, "size", 1.2, "tex", "smoke", "core", 0.0, "blend", "mix", "shape", "sphere", "r", 0.3, "vel", GArray.Of(1.0, 2.5),
                        "damp", 2.0, "shape_life", "swell", "fade", "late", "alpha", 0.5, "angle", 180.0, "spin", 40.0));
                    var i = 0;
                    foreach (var pt in _EvArr(e, "pts"))
                    {
                        var tp = _G(pt.V2, 1.1);
                        GetTree().CreateTimer(0.06 * i).Timeout += () =>
                        {
                            Beam(mz, tp, C("#fff0c8"), 0.3, 0.22, GDict.Of("speed", 30.0, "core", 0.9, "fade_end", 0.1, "in", 0.02));
                            Flash(mz, C("#ffe8b0"), 1.6, 0.15, "star", 1.0);
                            Flash(tp, C("#ffd890"), 1.6, 0.3, "sparkle", 1.0);
                            Burst(tp, C("#ffd890"), GDict.Of("n", 10, "life", 0.4, "size", 0.3, "tex", "dot", "core", 1.0, "shape", "point", "vel", GArray.Of(3.0, 7.0),
                                "grav", new Vector3(0, -8.0, 0), "fade", "hot"));
                        };
                        i += 1;
                    }
                    Shake(0.25, p2);
                    break;
                }
                case "wildgrowth":                              // the grove
                {
                    var r = (double)_Ev(e, "r", 7.0);
                    Wave(p2, C("#6aff7a"), 0.3, r, 0.7, 1.4);
                    Pillar(at, C("#8dff6a"), 0.35, 5.0, 0.7, GDict.Of("top", 0.6, "speed", 3.0, "out", 0.5, "core", 0.15, "energy", 0.7));
                    Burst(at + new Vector3(0, 0.3, 0), C("#8dff6a"), GDict.Of("n", 30, "life", 1.6, "size", 0.3, "tex", "leaf", "core", 0.3, "shape", "ring", "r", r * 0.7,
                        "inner", 0.1, "h", 0.1, "dir", Vector3.UP, "spread", 30.0, "vel", GArray.Of(1.5, 3.0), "grav", new Vector3(0, -0.8, 0), "turb", 1.0, "angle", 180.0,
                        "spin", 200.0, "fade", "slow"));
                    view._Vines(at, r * 0.6);
                    _Sparkles(at + new Vector3(0, 0.3, 0), C("#d8ffb0"), 20, r * 0.6, 1.5, 1.2);
                    break;
                }
            }
        }

        // ======================================================================================================================
        // the old classes' Q (siege_sim.gd) and the one-off events
        // ======================================================================================================================
        public void Q(string ab, GDict a, Unit u)
        {
            var root = _Root(GD.Str(u.id));
            if (root == null)
                return;
            Vector3 at = root.Position;
            var p2 = new Vector2(at.x, at.z);
            var f = new Vector2(Math.Sin((double)u.face), Math.Cos((double)u.face));
            switch (ab)
            {
                case "spin":                                    // the Barbarian's
                    Flash(at + new Vector3(0, 1.0, 0), C("#ffb04a"), 5.0, 0.35, "crescent", 0.6, true, 14.0);
                    Wave(p2, C("#ff8a3a"), 0.3, 3.2, 0.4);
                    Burst(at + new Vector3(0, 1.0, 0), C("#ffcf7a"), GDict.Of("n", 16, "life", 0.45, "size", 0.4, "tex", "streak", "core", 0.7, "shape", "ring", "r", 1.6,
                        "inner", 0.8, "h", 0.2, "dir", Vector3.UP, "spread", 90.0, "vel", GArray.Of(0.5, 1.5), "orbit", 2.5, "fade", "hot", "angle", 180.0));
                    break;
                case "lunge":                                   // the Rogue's
                    _DashFx(GD.Str(u.id), C("#a070ff"), "streak", 0.35);
                    Flash(at + new Vector3(f.x, 0, f.y) * 1.0 + new Vector3(0, 1.1, 0), C("#d8c8ff"), 1.6, 0.25, "crescent", 0.7);
                    break;
                case "volley":                                  // the Ranger's
                    Flash(at + new Vector3(f.x, 0, f.y) * 0.8 + new Vector3(0, 1.2, 0), C("#e8ffd0"), 1.4, 0.2, "sparkle");
                    Fan(p2, f, C("#8fe36a"), 3.0, 0.6, 0.3, GDict.Of("speed", 14.0, "core", 0.3, "up", 1.0, "fade_end", 0.7));
                    Burst(at + new Vector3(0, 1.0, 0), C("#8fe36a"), GDict.Of("n", 8, "life", 0.9, "size", 0.24, "tex", "feather", "core", 0.3, "shape", "sphere", "r", 0.4,
                        "vel", GArray.Of(0.5, 1.5), "grav", new Vector3(0, -0.8, 0), "turb", 0.8, "angle", 180.0, "spin", 200.0, "fade", "slow"));
                    break;
                case "hammer":                                  // the Crusader's
                    Flash(at + new Vector3(f.x, 0, f.y) * 0.8 + new Vector3(0, 1.3, 0), C("#ffd65a"), 1.6, 0.25, "star");
                    _Sparkles(at + new Vector3(0, 1.2, 0), C("#ffe9a6"), 8, 0.4, 1.0, 0.6);
                    break;
                case "whirlwind":                               // the Berserker's (the ribbon is the view's; the dust it kicks)
                    if (!Holding("whirl:" + GD.Str(u.id)))
                    {
                        _Hold("whirl:" + GD.Str(u.id), GArray.Of(Burst(new Vector3(0, 0.2, 0), C("#d8c8a8"), GDict.Of("n", 24, "life", 0.8, "size", 1.4, "tex", "smoke", "core", 0.0, "blend", "mix",
                            "shape", "ring", "r", 1.2, "inner", 0.5, "h", 0.1, "dir", Vector3.UP, "spread", 50.0, "vel", GArray.Of(1.0, 2.5), "orbit", 2.0, "damp", 1.5,
                            "shape_life", "swell", "fade", "late", "alpha", 0.45, "angle", 180.0, "spin", 30.0, "dur", 30.0, "parent", root, "explode", 0.0)),
                            Burst(new Vector3(0, 1.0, 0), C("#ff2a2a"), GDict.Of("n", 24, "life", 0.4, "size", 0.8, "tex", "crescent", "core", 0.5, "shape", "ring", "r", 1.5,
                            "inner", 0.9, "h", 0.3, "dir", Vector3.UP, "spread", 90.0, "vel", GArray.Of(0.3, 1.0), "orbit", 3.0, "fade", "hot", "angle", 180.0, "dur", 30.0,
                            "parent", root, "explode", 0.0))), _AliveWhile(GD.Str(u.id), uu => view.sim.Whirling(uu)));
                    }
                    break;
                case "vanish":                                  // the Assassin's
                    Burst(at + new Vector3(0, 1.0, 0), C("#2a1a4a"), GDict.Of("n", 16, "life", 1.0, "size", 1.6, "tex", "smoke", "core", 0.0, "blend", "mix", "shape", "sphere", "r", 0.5,
                        "vel", GArray.Of(0.5, 1.5), "shape_life", "swell", "fade", "late", "alpha", 0.8, "angle", 180.0, "spin", 40.0));
                    Burst(at + new Vector3(0, 1.0, 0), C("#8a5bff"), GDict.Of("n", 16, "life", 0.5, "size", 0.3, "tex", "sparkle", "core", 0.9, "shape", "sphere", "r", 1.4,
                        "radial", -5.0, "vel", GArray.Of(0.0, 0.2), "fade", "slow", "shape_life", "shrink"));
                    break;
                case "pierce":                                  // the Sniper's: the draw (the shot: event "proj")
                    Flash(at + new Vector3(f.x, 0, f.y) * 0.8 + new Vector3(0, 1.3, 0), C("#bfefff"), 1.0, 0.3, "sparkle", 1.0);
                    break;
                case "meteor":                                  // the Archmage's (the rock itself: meteor_warn)
                    Flash(at + new Vector3(0, 1.4, 0), C("#ff6ad0"), 1.8, 0.35, "runes", 0.6, false, 4.0);
                    Pillar(at, C("#c070ff"), 0.25, 7.0, 0.5, GDict.Of("top", 0.05, "speed", 12.0, "out", 0.3, "fade_end", 0.7, "core", 0.2, "energy", 0.8));
                    break;
                case "nova":                                    // the Mage's: the gathering (the blast: event "nova")
                    Burst(at + new Vector3(0, 1.2, 0), C("#ffd24a"), GDict.Of("n", 12, "life", 0.4, "size", 0.3, "tex", "sparkle", "core", 0.9, "shape", "sphere", "r", 1.4,
                        "radial", -5.0, "vel", GArray.Of(0.0, 0.2), "fade", "slow", "shape_life", "shrink"));
                    break;
                case "nova_blast":
                {
                    var r = (double)Sim.NOVA_R;
                    Disc(p2, C("#ff5a1a"), r, 0.9, 2, GDict.Of("grow", 0.3, "out", 0.5, "energy", 1.1, "scorch", 0.4, "scorch_out", 2.0));
                    Wave(p2, C("#ffb04a"), 0.3, r, 0.45, 1.4);
                    _Flames(at, C("#ff6a1a"), 26, r * 0.6, 0.6, 1.8, -1.0, 3.5);
                    _Embers(at + new Vector3(0, 0.5, 0), C("#ffb04a"), 16, r * 0.5, 3.0);
                    Flash(at + new Vector3(0, 1.2, 0), C("#fff0c0"), 2.6, 0.3, "star", 1.0);
                    view.Shockwave(at + new Vector3(0, 0.3, 0), r);
                    Shake(0.2, p2);
                    break;
                }
                case "sanctuary":                               // the Priest's: the prayer (the light: event "sanctuary")
                    _Sparkles(at + new Vector3(0, 1.2, 0), C("#fff6d8"), 8, 0.4, 1.5, 0.6);
                    break;
                case "sanctuary_blast":
                {
                    var r = (double)Sim.SANCTUARY_R;
                    Disc(p2, C("#fff1a8"), r, 1.0, 1, GDict.Of("tex", "rays", "spin", 1.2, "grow", 0.4, "out", 0.5));
                    Wave(p2, C("#fff6d8"), 0.3, r, 0.6);
                    Pillar(at, C("#ffe9a6"), 0.3, 5.0, 0.7, GDict.Of("top", 0.5, "speed", 3.0, "out", 0.5, "core", 0.15, "energy", 0.7));
                    Burst(at + new Vector3(0, 0.3, 0), C("#fff6d8"), GDict.Of("n", 24, "life", 1.2, "size", 0.3, "tex", "sparkle", "core", 0.9, "shape", "ring", "r", r * 0.7,
                        "inner", 0.1, "h", 0.2, "dir", Vector3.UP, "spread", 20.0, "vel", GArray.Of(0.8, 2.0), "fade", "slow", "shape_life", "pop", "angle", 180.0, "spin", 60.0));
                    break;
                }
                case "resurrect":
                    break;                                      // (the "resurrect" event, where he rises)
                case "block":
                    break;                                      // (block_up)
                default:
                    break;
            }
        }

        public void Event(GDict e) => Event(SiegeNet.ToEv(Var.Of(e)));

        public void Event(Ev e)
        {
            // the one-off events (siege_view.on_event hands these over)
            GDict a = view.actors.Get(e.S("id", ""), new GDict()).D;
            Node3D root = !a.IsEmpty() && GD.IsInstanceValid(a["root"]) ? a["root"].As<Node3D>() : null;
            switch (e.K)
            {
                case "block_up":
                    if (root != null && root.Visible)
                    {
                        Unit u = view.sim.by_id.TryGetValue(e.S("id"), out var uu) ? uu : null;
                        _BlockUp(e.S("id"), (u != null ? GD.Str(u.hid) : "") == "crusader" ? C("#ffe9a6") : C("#bcd8ff"));
                    }
                    break;
                case "pillar":                                  // FIRE PILLAR erupts
                {
                    Vector2 c3 = e.P("c");
                    var r = e.F("r");
                    var at = _G(c3, 0.0);
                    Pillar(at, C("#ff7a2a"), r * 0.5, 5.0, 0.7, GDict.Of("top", r * 0.2, "speed", 6.0, "out", 0.4, "core", 0.25, "in", 0.04, "energy", 0.8));
                    Disc(c3, C("#ff6a2a"), r + 0.5, 1.2, 1, GDict.Of("tex", "cracks", "out", 0.6, "energy", 1.2, "scorch", 0.5, "scorch_out", 3.0));
                    _Flames(at, C("#ff6a1a"), 26, r * 0.7, 0.7, 1.9, -1.0, 5.0);
                    _Embers(at + new Vector3(0, 0.5, 0), C("#ffd24a"), 20, r * 0.5, 5.0);
                    Flash(at + new Vector3(0, 2.0, 0), C("#fff0c0"), 3.0, 0.3, "star", 1.0);
                    Wave(c3, C("#ffd24a"), 0.3, r + 1.0, 0.45, 1.5);
                    view.Shockwave(at + new Vector3(0, 0.3, 0), r);
                    Shake(0.25, c3);
                    break;
                }
                case "slam":                                    // a LEAP's or a dive's or the avalanche's landing
                {
                    Vector2 c3 = e.P("pos");
                    var r = (double)_Ev(e, "r", 2.5);
                    var at = _G(c3, 0.0);
                    Unit u = view.sim.by_id.TryGetValue(e.S("id", ""), out var uu) ? uu : null;
                    var hid = u != null ? GD.Str(u.hid) : "";
                    var col = hid == "barbarian" ? C("#ffb04a") : (hid == "dragoon" ? C("#ff7a3a") : C("#c8b48a"));
                    Disc(c3, col, r, 1.0, 1, GDict.Of("tex", "cracks", "out", 0.5, "energy", 1.2, "scorch", 0.4, "scorch_out", 2.5, "scorch_col", new Color(0.12, 0.09, 0.05)));
                    Wave(c3, col, 0.3, r + 0.8, 0.45, 1.5);
                    _Rocks(at + new Vector3(0, 0.3, 0), hid != "golem" ? 10 : 20, r * 0.4, 0.22, 6.0);
                    _Dust(at, C("#c8b89a"), 14, r * 0.5, 1.6, 1.1, 3.0);
                    if (hid == "dragoon")
                    {
                        _Flames(at, C("#ff7a3a"), 24, r * 0.7, 0.6, 1.3, -1.0, 4.0);
                        Flash(at + new Vector3(0, 1.2, 0), C("#ffd890"), 5.0, 0.3, "crescent", 0.7, true, 8.0);
                    }
                    view.Shockwave(at + new Vector3(0, 0.3, 0), r);
                    Shake(hid != "golem" ? 0.3 : 0.45, c3);
                    break;
                }
                case "burst":                                   // the keg goes off / the roots burst up
                {
                    Vector2 c3 = e.P("c");
                    var r = (double)_Ev(e, "r", 2.0);
                    var at = _G(c3, 0.0);
                    if (e.S("spell") == "keg")
                    {
                        view._PackExplosion("light", at + new Vector3(0, 0.5, 0), 1.2);
                        Flash(at + new Vector3(0, 0.8, 0), C("#ffe0a0"), 4.0, 0.3, "star", 1.0);
                        Disc(c3, C("#ff9a3a"), r, 0.8, 2, GDict.Of("out", 0.5));
                        Wave(c3, C("#ff9a3a"), 0.3, r + 1.0, 0.45, 1.5);
                        Burst(at + new Vector3(0, 0.5, 0), C("#6a4a2a"), GDict.Of("n", 14, "life", 1.0, "size", 0.22, "mesh", "rock", "shape", "sphere", "r", 0.3,
                            "dir", Vector3.UP, "spread", 60.0, "vel", GArray.Of(3.0, 8.0), "grav", new Vector3(0, -14.0, 0), "angle", 180.0, "spin", 500.0, "fade", "late"));
                        view.SmokeCloud(at + new Vector3(0, 0.6, 0), 0.5, 12, 4.0);
                        view.Shockwave(at + new Vector3(0, 0.3, 0), r);
                        Shake(0.25, c3);
                    }
                    else
                    {
                        Disc(c3, C("#6fbf3a"), r + 0.5, 1.6, 4, GDict.Of("out", 0.7, "energy", 1.3));
                        Wave(c3, C("#8dff6a"), 0.3, r + 1.0, 0.5);
                        view._Vines(at, r);
                        Burst(at + new Vector3(0, 0.3, 0), C("#8dff6a"), GDict.Of("n", 18, "life", 1.2, "size", 0.28, "tex", "leaf", "core", 0.3, "shape", "ring", "r", r * 0.6,
                            "inner", 0.2, "h", 0.1, "dir", Vector3.UP, "spread", 30.0, "vel", GArray.Of(2.0, 4.0), "grav", new Vector3(0, -1.5, 0), "turb", 1.0, "angle", 180.0,
                            "spin", 200.0, "fade", "slow"));
                        _Dust(at, C("#8a7a5a"), 8, r * 0.5, 1.0, 0.8, 2.0);
                    }
                    break;
                }
                case "zap":                                     // a THUNDERSTORM bolt
                {
                    var zp = _G(e.P("c"), 0.1);
                    Bolt(zp + new Vector3(GD.RandfRange(-1.5, 1.5), 8.0, GD.RandfRange(-1.5, 1.5)), zp + new Vector3(0, 0.3, 0), C("#7fb8ff"), 0.3, 1.6, 0.22, 2);
                    _ZapHit(zp + new Vector3(0, 0.5, 0), C("#9fd4ff"), 1.3);
                    Flash(zp + new Vector3(0, 6.0, 0), C("#dff0ff"), 6.0, 0.15, "dot", 0.3);
                    Shake(0.12, e.P("c"), 14.0);
                    break;
                }
                case "riposte":                                 // the Duelist answers
                {
                    var rp = _G(e.P("pos"), 1.0);
                    Flash(rp, C("#ffffff"), 2.2, 0.25, "star", 1.0);
                    var f2 = Flash(rp, C("#ffe27a"), 2.8, 0.3, "crescent", 0.8);
                    var rot2 = f2.Rotation;
                    rot2.z = (float)(GD.Randf() * GD.TAU);
                    f2.Rotation = rot2;
                    Burst(rp, C("#fff4c0"), GDict.Of("n", 14, "life", 0.45, "size", 0.4, "tex", "streak", "core", 0.8, "shape", "point", "vel", GArray.Of(4.0, 9.0), "damp", 6.0,
                        "fade", "hot", "shape_life", "shrink", "angle", 180.0));
                    Wave(e.P("pos"), C("#ffe27a"), 0.3, 2.4, 0.4);
                    break;
                }
                case "flurry_hit":                              // FLURRY's or GRAND CHALLENGE's strike
                {
                    Unit u = view.sim.by_id.TryGetValue(e.S("id", ""), out var uu) ? uu : null;
                    var gold = (u != null ? GD.Str(u.hid) : "") == "duelist";
                    var fp = _G(e.P("pos"), 1.1);
                    var col = gold ? C("#ffe27a") : C("#9a6bff");
                    var f1 = Flash(fp, col.Lerp(Color.WHITE, 0.5), 2.6, 0.28, "crescent", 0.8);
                    var rot1 = f1.Rotation;
                    rot1.z = (float)(GD.Randf() * GD.TAU);
                    f1.Rotation = rot1;
                    Burst(fp, col, GDict.Of("n", 12, "life", 0.4, "size", 0.5, "tex", "streak", "core", 0.8, "shape", "point", "vel", GArray.Of(5.0, 10.0), "damp", 6.0,
                        "fade", "hot", "shape_life", "shrink", "angle", 180.0));
                    if (!gold)
                    {
                        Burst(_G(_Ev(e, "from", e.P("pos")).V2, 0.9), C("#2a1a4a"), GDict.Of("n", 6, "life", 0.6, "size", 1.2, "tex", "smoke", "core", 0.0, "blend", "mix", "shape", "sphere",
                            "r", 0.3, "vel", GArray.Of(0.3, 1.0), "shape_life", "swell", "fade", "late", "alpha", 0.6, "angle", 180.0, "spin", 40.0));
                    }
                    else
                        Bolt(fp + new Vector3(GD.RandfRange(-2, 2), 5.0, GD.RandfRange(-2, 2)), fp, C("#ffe27a"), 0.25, 0.8, 0.14, 1);
                    break;
                }
                case "trap_snap":
                {
                    var tp = _G(e.P("pos"), 0.2);
                    Flash(tp + new Vector3(0, 0.4, 0), C("#ffffff"), 1.4, 0.2, "sparkle", 1.0);
                    Burst(tp, C("#ffd27a"), GDict.Of("n", 16, "life", 0.5, "size", 0.16, "tex", "dot", "core", 1.0, "shape", "sphere", "r", 0.3, "vel", GArray.Of(2.0, 6.0),
                        "grav", new Vector3(0, -10.0, 0), "fade", "hot"));
                    Wave(e.P("pos"), C("#ff4a4a"), 0.2, 1.8, 0.35);
                    break;
                }
                case "nova":
                {
                    Unit u = view.sim.by_id.TryGetValue(e.S("id"), out var uu) ? uu : null;
                    if (u != null)
                        Q("nova_blast", a, u);
                    break;
                }
                case "sanctuary":
                {
                    Unit u = view.sim.by_id.TryGetValue(e.S("id"), out var uu) ? uu : null;
                    if (u != null)
                        Q("sanctuary_blast", a, u);
                    break;
                }
                case "proj":                                    // a shot leaves: the Sniper's muzzle flash
                    if (e.S("kind", "") == "pierce" && root != null && root.Visible)
                    {
                        Unit u = view.sim.by_id.TryGetValue(e.S("id", ""), out var uu) ? uu : null;
                        if (u != null)
                        {
                            var f = new Vector2(Math.Sin((double)u.face), Math.Cos((double)u.face));
                            Vector3 mz = root.Position + new Vector3(f.x, 0, f.y) * 1.0 + new Vector3(0, 1.3, 0);
                            Flash(mz, C("#ffffff"), 1.8, 0.2, "star", 1.0);
                            Fan(new Vector2(root.Position.x, root.Position.z), f, C("#bfefff"), 2.5, 0.25, 0.25, GDict.Of("speed", 20.0, "core", 0.6, "up", 1.2, "in", 0.02));
                        }
                    }
                    break;
                case "resurrect":
                {
                    var rp = _G(e.P("pos"), 0.0);
                    Pillar(rp, C("#7dff8a"), 0.35, 5.0, 1.2, GDict.Of("top", 0.5, "speed", 3.0, "out", 0.7, "core", 0.2, "energy", 0.75));
                    Disc(e.P("pos"), C("#7dff8a"), 2.2, 1.4, 1, GDict.Of("tex", "runes", "spin", -1.5, "out", 0.6));
                    Burst(rp + new Vector3(0, 0.3, 0), C("#d8e8c0"), GDict.Of("n", 16, "life", 1.2, "size", 0.3, "tex", "sparkle", "core", 0.9, "shape", "sphere", "r", 0.5,
                        "vel", GArray.Of(0.3, 1.0), "grav", new Vector3(0, 2.0, 0), "fade", "slow", "shape_life", "pop", "angle", 180.0, "spin", 60.0));
                    Burst(rp + new Vector3(0, 0.6, 0), C("#e8e0c8"), GDict.Of("n", 10, "life", 0.9, "size", 0.26, "tex", "shard", "core", 0.2, "shape", "sphere", "r", 0.5,
                        "radial", -3.0, "vel", GArray.Of(0.0, 0.3), "fade", "slow", "angle", 180.0, "spin", 200.0));
                    break;
                }
                case "pierce_hit":
                {
                    var ph = _G(e.P("pos"), 1.1);
                    Flash(ph, C("#ffffff"), 1.4, 0.2, "sparkle", 1.0);
                    Burst(ph, C("#bfefff"), GDict.Of("n", 10, "life", 0.4, "size", 0.3, "tex", "streak", "core", 0.8, "shape", "point", "vel", GArray.Of(3.0, 7.0), "damp", 5.0,
                        "fade", "hot", "shape_life", "shrink", "angle", 180.0));
                    break;
                }
                case "boom":                                    // a fireball lands
                {
                    var bp = _G(e.P("pos"), 0.3);
                    Flash(bp + new Vector3(0, 0.4, 0), C("#ffb04a"), 2.0, 0.25, "star", 0.9);
                    _Flames(bp, C("#ff8a3a"), 8, 0.5, 0.5, 0.8, -1.0, 3.0);
                    Wave(e.P("pos"), C("#ff8a3a"), 0.2, 2.0, 0.35);
                    break;
                }
                case "vanish":
                    break;                                      // (q "vanish")
                case "dodge":
                    if (root != null && root.Visible)
                        _Dust(root.Position, C("#d8c8a8"), 5, 0.4, 0.9, 0.7, 2.0);
                    break;
                case "meteor_warn":
                {
                    Vector2 c3 = e.P("pos");
                    Disc(c3, C("#ff6a3a"), (double)Sim.METEOR_R, e.F("delay") + 0.1, 1, GDict.Of("tex", "runes", "spin", 4.0, "in", 0.1, "out", 0.1, "energy", 1.3));
                    break;
                }
                case "meteor_hit":
                {
                    Vector2 c3 = e.P("pos");
                    Disc(c3, C("#ff6a3a"), (double)Sim.METEOR_R + 1.0, e.F("burn") + 0.5, 2, GDict.Of("out", 1.0, "energy", 1.1, "in", 0.05, "scorch", 0.6, "scorch_out", 6.0));
                    Disc(c3, C("#ffb04a"), (double)Sim.METEOR_R * 1.4, 2.0, 1, GDict.Of("tex", "cracks", "out", 1.2, "energy", 1.2));
                    _Rocks(_G(c3, 0.3), 16, 1.0, 0.3, 8.0);
                    _Embers(_G(c3, 0.6), C("#ffb04a"), 24, 1.5, 5.0);
                    Flash(_G(c3, 1.0), C("#fff0c0"), 6.0, 0.3, "star", 1.0);
                    break;
                }
            }
        }

        public void MeteorTrail(Node3D rock)
        {
            // fire and smoke streaming off a falling meteor (siege_view._meteor_warn's rock)
            var rm = rock.GetNodeOrNull("rock_mesh");
            Burst(Vector3.ZERO, C("#ff8a3a"), GDict.Of("n", 30, "life", 0.5, "size", 1.3, "tex", "flame", "core", 0.7, "shape", "sphere", "r", 0.5, "vel", GArray.Of(0.5, 1.5),
                "grav", new Vector3(0, 2.0, 0), "shape_life", "grow", "fade", "hot", "angle", 180.0, "spin", 60.0, "dur", 6.0, "parent", rock, "explode", 0.0, "reach", 30.0));
            Burst(Vector3.ZERO, C("#3a2a20"), GDict.Of("n", 20, "life", 1.2, "size", 1.6, "tex", "smoke", "core", 0.0, "blend", "mix", "shape", "sphere", "r", 0.5, "vel", GArray.Of(0.2, 0.8),
                "grav", new Vector3(0, 0.8, 0), "shape_life", "swell", "fade", "late", "alpha", 0.6, "angle", 180.0, "spin", 30.0, "dur", 6.0, "parent", rock, "explode", 0.0, "reach", 30.0));
            if (rm == null)
            {
                var glow = new MeshInstance3D();
                var q = new QuadMesh();
                q.Size = Vector2.ONE * 3.2;
                glow.Mesh = q;
                glow.MaterialOverride = SpriteMat("dot", 0.9, C("#ffb04a"));
                glow.Name = "rock_mesh";
                glow.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
                rock.AddChild(glow);
            }
        }

        public void ProjTrail(Node3D node, Proj p)
        {
            // what a projectile leaves behind it, by what it is (siege_view._sync_projectiles, when its node is made)
            var kind = GD.Str(p.kind);
            var sp = GD.Str(p.spell != null ? p.spell : "");
            switch (kind)
            {
                case "hammer":
                    Trail(node, C("#ffd65a"), 30.0, "sparkle", GDict.Of("n", 20, "life", 0.4, "size", 0.35, "y", 0.0, "grav", Vector3.ZERO, "shape_life", "pop"));
                    break;
                case "pierce":
                    Trail(node, C("#bfefff"), 30.0, "streak", GDict.Of("n", 24, "life", 0.3, "size", 0.5, "y", 0.0, "grav", Vector3.ZERO));
                    break;
                case "boulder":
                    Trail(node, C("#c8b89a"), 30.0, "smoke", GDict.Of("n", 16, "life", 0.7, "size", 0.9, "y", -0.3, "grav", new Vector3(0, 0.3, 0), "shape_life", "grow", "alpha", 0.4, "fade", "late"));
                    break;
                case "bolt":
                    Trail(node, C("#9fd4ff"), 30.0, "lightning", GDict.Of("n", 16, "life", 0.25, "size", 0.6, "y", 0.0, "grav", Vector3.ZERO, "fade", "flicker"));
                    break;
                case "ball":
                    Trail(node, C("#ff8a3a"), 30.0, "flame", GDict.Of("n", 20, "life", 0.4, "size", 0.7, "y", 0.0, "grav", new Vector3(0, 1.5, 0), "fade", "hot"));
                    break;
                case "thorn":
                    Trail(node, C("#8dff6a"), 30.0, "leaf", GDict.Of("n", 12, "life", 0.5, "size", 0.3, "y", 0.0, "grav", new Vector3(0, -0.5, 0)));
                    break;
                case "fire":
                    if (sp == "missiles")
                    {
                        Trail(node, C("#c070ff"), 30.0, "runes", GDict.Of("n", 14, "life", 0.35, "size", 0.4, "y", 0.0, "grav", Vector3.ZERO, "shape_life", "shrink"));
                        Trail(node, C("#ff6ad0"), 30.0, "sparkle", GDict.Of("n", 14, "life", 0.3, "size", 0.3, "y", 0.0, "grav", Vector3.ZERO, "shape_life", "pop"));
                    }
                    else
                        Trail(node, C("#ff8a3a"), 30.0, "flame", GDict.Of("n", 16, "life", 0.35, "size", 0.6, "y", 0.0, "grav", new Vector3(0, 1.0, 0), "fade", "hot"));
                    break;
                case "arrow":
                    if (sp == "snare")
                    {
                        Trail(node, C("#8fe36a"), 30.0, "leaf", GDict.Of("n", 14, "life", 0.45, "size", 0.28, "y", 0.0, "grav", new Vector3(0, -0.8, 0)));
                        Trail(node, C("#e8ffd0"), 30.0, "streak", GDict.Of("n", 12, "life", 0.25, "size", 0.5, "y", 0.0, "grav", Vector3.ZERO));
                    }
                    else if ((bool)p.big)
                        Trail(node, C("#cfe8b8"), 30.0, "streak", GDict.Of("n", 20, "life", 0.3, "size", 0.7, "y", 0.0, "grav", Vector3.ZERO));
                    break;
            }
        }

        // ======================================================================================================================
        // what lasts (siege_view._sync_kits and _sync_auras hand over here, each frame)
        // ======================================================================================================================
        public void SyncUnit(string id, Unit u, GDict a, bool vis)
        {
            // a hero's lasting states: a shield's bubble, a slow's frost, a mark or curse, a stone or bark skin, a parry's
            // glints, poison, a dash's trail, the ultimates' auras and the jungle buffs
            var sim = view.sim;
            double t = sim.time;
            Node3D root = a["root"].As<Node3D>();
            var hid = GD.Str(u.hid);
            // shield
            bool want_shield = vis && (double)u.shield > 0.0 && t < (double)u.shield_until;
            if (want_shield && !Holding("shield:" + id))
            {
                GDict st = _shield_style.Get(id, GDict.Of("col", C("#7fb8ff"), "style", 0)).D;
                Shell(root, st["col"].As<Color>(), 0.95, 2.3, (int)st["style"], -1.0, GDict.Of("key", "shield:" + id, "alive", _AliveWhile(id, uu => (double)uu.shield > 0.0 && sim.time < (double)uu.shield_until), "energy", 0.9));
            }
            else if (!want_shield && Holding("shield:" + id))
                Release("shield:" + id);
            // slow: frost drifting round his feet
            bool want_slow = vis && t < (double)u.slow_until;
            if (want_slow && !Holding("slow:" + id))
            {
                var d = Disc(Vector2.ZERO, C("#9fd4ff"), 0.9, -1.0, 1, GDict.Of("tex", "swirl", "spin", -2.0, "key", "slow:" + id, "alive", _AliveUntil(id, "slow_until"), "rim", 0.4, "flat", true));
                d.Reparent(root, false);
                d.Position = new Vector3(0, 0.1, 0);
            }
            else if (!want_slow && Holding("slow:" + id))
                Release("slow:" + id);
            // a mark or a curse
            bool want_amp = vis && t < (double)u.amp_until;
            if (want_amp && !Holding("amp:" + id))
            {
                GDict st2 = _amp_style.Get(id, GDict.Of("col", C("#ff4a4a"), "tex", "rays", "spin", 2.5)).D;
                var d2 = Disc(Vector2.ZERO, st2["col"].As<Color>(), 1.1, -1.0, 1, GDict.Of("tex", GD.Str(st2["tex"]), "spin", (double)st2["spin"], "key", "amp:" + id, "alive", _AliveUntil(id, "amp_until"), "rim", 0.6, "flat", true));
                d2.Reparent(root, false);
                d2.Position = new Vector3(0, 0.12, 0);
            }
            else if (!want_amp && Holding("amp:" + id))
                Release("amp:" + id);
            // stone or bark
            bool want_skin = vis && t < (double)u.skin_until;
            if (want_skin && !Holding("skin:" + id))
            {
                GDict st3 = _skin_style.Get(id, GDict.Of("col", hid == "golem" ? C("#b8b2a4") : C("#a07a4a"))).D;
                Shell(root, st3["col"].As<Color>(), 0.9, 2.2, 1, -1.0, GDict.Of("key", "skin:" + id, "alive", _AliveUntil(id, "skin_until"), "energy", 0.7, "speed", 0.3));
            }
            else if (!want_skin && Holding("skin:" + id))
                Release("skin:" + id);
            // a parry
            bool want_parry = vis && u.riposte != null;
            if (want_parry && !Holding("parry:" + id))
            {
                _Hold("parry:" + id, GArray.Of(Burst(new Vector3(0, 1.1, 0), C("#ffe27a"), GDict.Of("n", 20, "life", 0.5, "size", 0.6, "tex", "crescent", "core", 0.7, "shape", "ring",
                    "r", 0.8, "inner", 0.9, "h", 0.1, "dir", Vector3.UP, "spread", 10.0, "vel", GArray.Of(0.0, 0.2), "orbit", 3.0, "fade", "slow", "angle", 180.0, "spin", 200.0,
                    "dur", 5.0, "parent", root, "explode", 0.0, "local", true))), _AliveWhile(id, uu => uu.riposte != null));
            }
            else if (!want_parry && Holding("parry:" + id))
                Release("parry:" + id);
            // poison ticking on him
            bool want_dots = vis && u.dots != null && !view.low_fx && hid != "" && !Holding("rejuv:" + id);
            if (want_dots && !Holding("dots:" + id))
            {
                _Hold("dots:" + id, GArray.Of(Burst(new Vector3(0, 1.0, 0), C("#7dff6a"), GDict.Of("n", 20, "life", 0.9, "size", 0.26, "tex", "dot", "core", 0.8, "shape", "sphere", "r", 0.4,
                    "vel", GArray.Of(0.2, 0.8), "grav", new Vector3(0, 1.5, 0), "fade", "slow", "dur", 30.0, "parent", root, "explode", 0.0, "shape_life", "shrink"))),
                    _AliveWhile(id, uu => uu.dots != null));
            }
            else if (!want_dots && Holding("dots:" + id))
                Release("dots:" + id);
            // the Berserker's whirlwind: the dust it kicks and the crescents round it (the ribbon is the view's)
            bool want_whirl = vis && view.sim.Whirling(u);
            if (want_whirl && !Holding("whirl:" + id))
                Q("whirlwind", a, u);
            else if (!want_whirl && Holding("whirl:" + id))
                Release("whirl:" + id);
            // a dash's trail
            bool want_dash = vis && u.state == "dash";
            if (want_dash && !Holding("dash:" + id))
            {
                GDict ds = _dash_style.Get(id, new GDict()).D;
                if (ds.IsEmpty() || _time - (double)ds["at"] > 1.5)
                    ds = GDict.Of("col", C("#e0d0b0"), "tex", "streak");
                var nm = GD.Str(ds["tex"]);
                var o = GDict.Of("n", 60, "life", 0.45, "size", nm != "smoke" ? 0.6 : 1.2, "y", nm != "smoke" ? 0.8 : 0.3, "alpha", 0.8);
                if (nm == "smoke")
                {
                    o["alpha"] = 0.5;
                    o["blend"] = "mix";
                    o["shape_life"] = "swell";
                    o["fade"] = "late";
                }
                else if (nm == "flame")
                {
                    o["grav"] = new Vector3(0, 2.0, 0);
                    o["fade"] = "hot";
                }
                _Hold("dash:" + id, GArray.Of(Trail(root, ds["col"].As<Color>(), 3.0, nm, o)), _AliveWhile(id, uu => uu.state == "dash"));
            }
            else if (!want_dash && Holding("dash:" + id))
                Release("dash:" + id);
            // the ultimates' auras
            _Aura(id, u, root, vis, "dr", t < (double)u.dr_until && !(t < (double)u.skin_until), C("#ffd65a"), "star");
            _Aura(id, u, root, vis, "bl", t < (double)u.bl_until || t < (double)u.ls_until, C("#ff5a3a"), "flame");
            _Aura(id, u, root, vis, "ud", t < (double)u.ud_until, C("#ff2a2a"), "crescent");
            var b = u.buffs;                                // (u.get("buffs", {}): none -> every buff's time -1)
            _Aura(id, u, root, vis, "arcane", t < (b != null ? b.Get("arcane", -1.0) : -1.0), C("#7fb8ff"), "runes");
            _Aura(id, u, root, vis, "ember", t < (b != null ? b.Get("ember", -1.0) : -1.0), C("#ff8a3a"), "dot");
            _Aura(id, u, root, vis, "lord", t < (b != null ? b.Get("lord", -1.0) : -1.0), C("#c9a6ff"), "sparkle");
        }

        public void _Aura(string id, Unit _u, Node3D root, bool vis, string kind, bool on, Color col, string nm)
        {
            var key = kind + ":" + id;
            bool want = vis && on && !view.low_fx;
            if (want && !Holding(key))
            {
                var nodes = new GArray();
                switch (kind)
                {
                    case "dr":
                        nodes.Append(Burst(new Vector3(0, 1.0, 0), col, GDict.Of("n", 24, "life", 1.2, "size", 0.5, "tex", nm, "core", 0.9, "shape", "ring", "r", 0.9, "inner", 0.9,
                            "h", 1.4, "dir", Vector3.UP, "spread", 10.0, "vel", GArray.Of(0.1, 0.4), "orbit", 1.5, "fade", "slow", "shape_life", "pop", "angle", 180.0,
                            "spin", 60.0, "dur", 30.0, "parent", root, "explode", 0.0, "local", true)));
                        break;
                    case "bl":
                        nodes.Append(Burst(new Vector3(0, 0.2, 0), col, GDict.Of("n", 36, "life", 0.7, "size", 1.3, "tex", nm, "core", 0.7, "shape", "ring", "r", 0.7, "inner", 0.3,
                            "h", 0.3, "dir", Vector3.UP, "spread", 20.0, "vel", GArray.Of(1.0, 2.2), "grav", new Vector3(0, 2.5, 0), "shape_life", "shrink", "fade", "hot",
                            "angle", 12.0, "spin", 20.0, "dur", 30.0, "parent", root, "explode", 0.0)));
                        break;
                    case "ud":
                        nodes.Append(Shell(root, C("#7a0c0c"), 1.0, 2.3, 2, 1e9, GDict.Of("energy", 1.2, "speed", 3.0, "in", 0.3)));
                        nodes.Append(Burst(new Vector3(0, 1.0, 0), col, GDict.Of("n", 24, "life", 0.7, "size", 0.8, "tex", nm, "core", 0.5, "shape", "ring", "r", 1.1, "inner", 0.8,
                            "h", 1.2, "dir", Vector3.UP, "spread", 20.0, "vel", GArray.Of(0.2, 0.6), "orbit", 2.5, "fade", "hot", "angle", 180.0, "spin", 400.0, "dur", 30.0,
                            "parent", root, "explode", 0.0, "local", true)));
                        break;
                    default:
                        nodes.Append(Burst(new Vector3(0, 0.6, 0), col, GDict.Of("n", 20, "life", 1.4, "size", 0.45, "tex", nm, "core", 0.7, "shape", "ring", "r", 0.7, "inner", 0.6,
                            "h", 0.8, "dir", Vector3.UP, "spread", 15.0, "vel", GArray.Of(0.3, 0.8), "orbit", 0.8, "fade", "slow", "shape_life", "pop", "angle", 180.0,
                            "spin", 40.0, "dur", 30.0, "parent", root, "explode", 0.0, "local", true, "grid", nm == "runes" ? 2.0 : 1.0)));
                        break;
                }
                foreach (var n in nodes)
                {
                    if (n.Is<MeshInstance3D>())
                    {
                        for (int i = _live.Size() - 1; i > -1; i--)
                        {
                            if (_live[i]["node"] == n)
                                _live.RemoveAt(i);                      // (held, not timed)
                        }
                    }
                }
                string until_key = GD.Str(GDict.Of("dr", "dr_until", "bl", "bl_until", "ud", "ud_until").Get(kind, ""));
                Func<bool> alive;
                if (until_key != "")
                    alive = _AliveWhile(id, uu => ((double)view.sim.time < V.ToDouble(uu.Get(until_key) ?? -1.0) && !(kind == "dr" && (double)view.sim.time < (double)uu.skin_until)) || (kind == "bl" && (double)view.sim.time < (double)uu.ls_until));
                else
                    alive = _AliveWhile(id, uu => (double)view.sim.time < (uu.buffs != null ? uu.buffs.Get(kind, -1.0) : -1.0));
                _Hold(key, nodes, alive, 0.5, 0.2);
            }
            else if (!want && Holding(key))
                Release(key);
        }

        public GArray Zone(Zone z)
        {
            // a zone's look while it lasts (siege_view._sync_kits): what's on the ground, by the spell; returns the nodes to free
            Vector2 c = z.at;
            var r = (double)z.r;
            var sp = GD.Str(z.spell);
            var nodes = new GArray();
            var key = GD.Fmt("zone:%d", (int)z.zid);
            var kits = view.sim.moba.kits;
            var zid = (int)z.zid;
            Func<bool> alive = () =>
            {
                foreach (var zz in kits.zones)
                {
                    if ((int)zz.zid == zid)
                        return true;
                }
                return false;
            };
            var at = _G(c, 0.0);
            switch (sp)
            {
                case "consecrate":
                    nodes.Append(Disc(c, C("#ffe9a6"), r, -1.0, 1, GDict.Of("tex", "rays", "spin", 0.9, "key", key, "alive", alive, "grow", 0.3, "out", 0.5)));
                    nodes.Append(Burst(at + new Vector3(0, 0.2, 0), C("#fff6d8"), GDict.Of("n", 30, "life", 1.4, "size", 0.4, "tex", "sparkle", "core", 0.9, "shape", "ring",
                        "r", r * 0.9, "inner", 0.0, "h", 0.1, "dir", Vector3.UP, "spread", 10.0, "vel", GArray.Of(0.4, 1.0), "fade", "slow", "shape_life", "pop", "angle", 180.0,
                        "spin", 60.0, "dur", 60.0, "explode", 0.0)));
                    break;
                case "caltrops":
                    nodes.Append(Disc(c, C("#b8b8b8"), r, -1.0, 0, GDict.Of("key", key, "alive", alive, "rim", 0.5, "energy", 0.7, "out", 0.4)));
                    nodes.Append(Burst(at + new Vector3(0, 0.15, 0), C("#e8e8e8"), GDict.Of("n", 24, "life", 1.0, "size", 0.3, "tex", "sparkle", "core", 1.0, "shape", "ring",
                        "r", r * 0.9, "inner", 0.0, "h", 0.05, "vel", GArray.Of(0.0, 0.05), "fade", "flicker", "shape_life", "pop", "angle", 180.0, "dur", 60.0, "explode", 0.0)));
                    break;
                case "static":
                    nodes.Append(Disc(c, C("#6fb4ff"), r, -1.0, 3, GDict.Of("key", key, "alive", alive, "energy", 1.2, "out", 0.3)));
                    nodes.Append(Burst(at + new Vector3(0, 0.3, 0), C("#9fd4ff"), GDict.Of("n", 30, "life", 0.35, "size", 0.8, "tex", "lightning", "core", 0.9, "shape", "ring",
                        "r", r * 0.9, "inner", 0.0, "h", 0.4, "vel", GArray.Of(0.2, 1.0), "fade", "flicker", "angle", 180.0, "spin", 100.0, "dur", 60.0, "explode", 0.0)));
                    break;
                case "smoke":
                    nodes.Append(Burst(at + new Vector3(0, 0.6, 0), C("#b8b8b8"), GDict.Of("n", 18, "life", 1.8, "size", 1.8, "tex", "smoke", "core", 0.0, "blend", "mix", "shape", "ring",
                        "r", r * 0.7, "inner", 0.0, "h", 0.4, "dir", Vector3.UP, "spread", 40.0, "vel", GArray.Of(0.2, 0.6), "damp", 1.0, "shape_life", "swell", "fade", "slow",
                        "alpha", 0.6, "angle", 180.0, "spin", 20.0, "dur", 60.0, "explode", 0.0, "rand", 0.4)));
                    _Hold(key, new GArray(), alive);
                    break;
                case "wildgrowth":
                    nodes.Append(Disc(c, C("#6aff7a"), r, -1.0, 4, GDict.Of("key", key, "alive", alive, "grow", 0.5, "out", 0.8, "energy", 1.1)));
                    nodes.Append(Burst(at + new Vector3(0, 0.2, 0), C("#8dff6a"), GDict.Of("n", 40, "life", 1.8, "size", 0.36, "tex", "leaf", "core", 0.3, "shape", "ring",
                        "r", r * 0.9, "inner", 0.0, "h", 0.1, "dir", Vector3.UP, "spread", 30.0, "vel", GArray.Of(0.6, 1.4), "grav", new Vector3(0, -0.3, 0), "turb", 1.0,
                        "angle", 180.0, "spin", 150.0, "fade", "slow", "dur", 60.0, "explode", 0.0)));
                    nodes.Append(Burst(at + new Vector3(0, 0.2, 0), C("#d8ffb0"), GDict.Of("n", 30, "life", 1.4, "size", 0.36, "tex", "sparkle", "core", 0.9, "shape", "ring",
                        "r", r * 0.9, "inner", 0.0, "h", 0.1, "dir", Vector3.UP, "spread", 10.0, "vel", GArray.Of(0.5, 1.2), "fade", "slow", "shape_life", "pop", "angle", 180.0,
                        "spin", 60.0, "dur", 60.0, "explode", 0.0)));
                    break;
                case "thunderstorm":
                    nodes.Append(Disc(c, C("#4a78c8"), r, -1.0, 3, GDict.Of("key", key, "alive", alive, "energy", 1.0, "out", 0.5, "rim", 0.9)));
                    break;
                case "pillar":
                    nodes.Append(Disc(c, C("#ff6a3a"), r, -1.0, 1, GDict.Of("tex", "runes", "spin", 5.0, "key", key, "alive", alive, "energy", 1.3, "in", 0.08, "out", 0.08)));
                    break;
                case "entangle":
                    nodes.Append(Disc(c, C("#6fbf3a"), r + 0.3, -1.0, 4, GDict.Of("key", key, "alive", alive, "energy", 1.3, "in", 0.08, "out", 0.1)));
                    break;
                default:
                    nodes.Append(Disc(c, C("#ffffff"), r, -1.0, 0, GDict.Of("key", key, "alive", alive)));
                    break;
            }
            if (_holds.Has(key))
            {
                foreach (var n in nodes)
                {
                    if (!_holds[key]["nodes"].A.Has(n))
                    {
                        _holds[key]["nodes"].A.Append(n);
                        for (int i = _live.Size() - 1; i > -1; i--)
                        {
                            if (_live[i]["node"] == n)
                                _live.RemoveAt(i);
                        }
                    }
                }
            }
            return nodes;
        }

        public Node3D TrapNode(Vector3 at, Color team_col)
        {
            // a bear trap of your side: two iron jaws open on the ground and a glint between them
            var root = new Node3D();
            root.Position = at;
            foreach (var s in new[] { -1.0, 1.0 })
            {
                var jaw = new MeshInstance3D();
                var tm = new TorusMesh();
                tm.InnerRadius = 0.34;
                tm.OuterRadius = 0.44;
                tm.Rings = 16;
                tm.RingSegments = 4;
                jaw.Mesh = tm;
                var m = new StandardMaterial3D();
                m.AlbedoColor = new Color(0.32, 0.3, 0.28);
                m.Metallic = 0.7;
                m.Roughness = 0.45;
                jaw.MaterialOverride = m;
                jaw.Scale = new Vector3(1.0, 0.5, 0.55);
                jaw.Position = new Vector3(0, 0.05, s * 0.2);
                var rot = jaw.Rotation;
                rot.x = (float)(s * 0.5);
                jaw.Rotation = rot;
                root.AddChild(jaw);
            }
            var glint = new MeshInstance3D();
            var q = new QuadMesh();
            q.Size = Vector2.ONE * 0.5;
            glint.Mesh = q;
            glint.MaterialOverride = SpriteMat("sparkle", 0.9, team_col, 1.0, false, 0.0);
            glint.Position = new Vector3(0, 0.15, 0);
            root.AddChild(glint);
            AddChild(root);
            return root;
        }
    }
}
