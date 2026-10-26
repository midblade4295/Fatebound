// Ported from godot/scripts/siege/weapon_fx_root.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector3 = Fatebound.Sim.Vec3;
using Color = Fatebound.GUI.Col;
using Transform3D = Fatebound.Sim.Xform3;
using AABB = Fatebound.Sim.Aabb;

namespace Fatebound.Game
{
    // A weapon's particles, pinned sprites and swing ribbon (0.31.100, weapon_fx.gd sets box / specs / trail). Built on the
    // first frame in the tree: Godot draws a particle at its own size whatever the emitter's scale, so the piece's length
    // in the world is measured first and this node undoes the piece's scale -- below it everything is in world units.
    public class WeaponFxRoot : Node3D
    {
        public static readonly Shader SPRITE = ResourceLoader.Load<Shader>("res://scripts/siege/fx_sprite.gdshader");
        public static readonly Shader TRAIL = ResourceLoader.Load<Shader>("res://scripts/siege/fx_trail.gdshader");
        public const string TEX = "res://assets/vfx/weapon/%s.png";
        public const double TRAIL_LIFE = 0.16;             // s of ribbon
        public const int TRAIL_SUB = 3;                    // points between two frames' samples (a smooth curve)

        public AABB box = new AABB();                      // the piece, in its own space
        public GArray specs = new GArray();
        public Color trail = new Color(0, 0, 0, 0);
        public GArray spins = new GArray();                // 0.31.103: [{node, speed, wobble, wobble_speed}] -- the model's own moving parts

        public static GDict _mats = new GDict();
        public bool _built = false;
        public double _ps = 1.0;
        public double _len = 1.0;                          // the piece's length in the world
        public int _axis = 1;
        public GArray _spinners = new GArray();            // [node, axis, rad/s]
        public GArray _parts = new GArray();               // [node, its rest basis, spin spec]
        public double _t = 0.0;
        public MeshInstance3D _ribbon = null;
        public ImmediateMesh _im = null;
        public GArray _samples = new GArray();             // [base, tip, time], newest first
        public double _clock = 0.0;
        public Vector3 _base_l = Vector3.ZERO;
        public Vector3 _tip_l = Vector3.ZERO;

        protected override void _Process(double delta)
        {
            if (!_built)
            {
                _built = true;
                _Build();
            }
            foreach (var s in _spinners)
            {
                if (GD.IsInstanceValid(s[0]))
                    s[0].As<Node3D>().RotateObjectLocal(s[1].V3, (double)s[2] * delta);
            }
            _t += delta;
            foreach (var p in _parts)
            {
                // from the rest pose each frame (no drift): rocked about X, turned about Y
                if (GD.IsInstanceValid(p[0]))
                {
                    GDict sp = p[2].D;
                    var wob = GD.DegToRad((double)sp.Get("wobble", 0.0)) * Math.Sin(_t * (double)sp.Get("wobble_speed", 0.6));
                    p[0].As<Node3D>().Basis = (Basis)p[1] * new Basis(Vector3.RIGHT, wob) * new Basis(Vector3.UP, _t * (double)sp.Get("speed", 0.5));
                }
            }
            if (_ribbon != null)
                _UpdateRibbon(delta);
        }

        public Vector3 AtPoint(double f)
        {
            // a point on the piece's axis (its longest side; 0 = its low end, 1 = its high end), in its own space
            var p = box.GetCenter();
            p[_axis] = (float)(box.position[_axis] + box.size[_axis] * f);
            return p;
        }

        public void _Build()
        {
            var model = GetParent() as Node3D;
            if (model == null)
                return;
            _ps = GD.Maxf(model.GlobalBasis.GetScale().x, 0.0001);
            Scale = Vector3.ONE / _ps;
            _axis = 1;
            if (box.size.x > box.size[_axis] * 1.15)
                _axis = 0;
            if (box.size.z > box.size[_axis] * 1.15)
                _axis = 2;
            _len = GD.Maxf(box.size[_axis], 0.05) * _ps;
            foreach (var sp in spins)
            {
                var n = model.FindChild(GD.Str(sp.Get("node", "")), true, false) as Node3D;
                if (n != null)
                    _parts.Append(GArray.Of(n, n.Basis, sp));
            }
            foreach (var s in specs)
            {
                switch (GD.Str(s.Get("kind", "p")))
                {
                    case "p":
                        _Particles(s.D);
                        break;
                    case "bill":
                    case "flat":
                        _Pinned(s.D);
                        break;
                    case "orbit":
                        _Orbit(s.D);
                        break;
                }
            }
            if (trail.a > 0.0)
            {
                _base_l = AtPoint(0.45);
                _tip_l = AtPoint(1.0);
                _im = new ImmediateMesh();
                _ribbon = new MeshInstance3D();
                _ribbon.Name = "Ribbon";
                _ribbon.TopLevel = true;
                _ribbon.Mesh = _im;
                _ribbon.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
                var m = new ShaderMaterial();
                m.Shader = TRAIL;
                m.SetShaderParameter("tint", new Color(trail, 1.0));
                m.SetShaderParameter("energy", trail.a);
                _ribbon.MaterialOverride = m;
                AddChild(_ribbon);
                _ribbon.GlobalTransform = Transform3D.IDENTITY;
            }
        }

        public static ShaderMaterial SpriteMat(string tex, double grid, double core, Color? tint = null, double spin = 0.0, double pulse = 0.0, bool flat = false)
        {
            Color tint_ = tint ?? Color.WHITE;
            var k = GD.Fmt("%s|%.0f|%.2f|%s|%.2f|%.2f|%s", tex, grid, core, tint_.ToHtmlExact(), spin, pulse, GD.Str(flat));
            if (!_mats.Has(k))
            {
                var m = new ShaderMaterial();
                m.Shader = SPRITE;
                m.SetShaderParameter("tex", ResourceLoader.Load(GD.Fmt(TEX, tex)));
                m.SetShaderParameter("grid", grid);
                m.SetShaderParameter("core", core);
                m.SetShaderParameter("tint", tint_);
                m.SetShaderParameter("spin", spin);
                m.SetShaderParameter("pulse", pulse);
                m.SetShaderParameter("lie_flat", flat);
                _mats[k] = Var.Of(m);
            }
            return _mats[k].As<ShaderMaterial>();
        }

        public GradientTexture1D _Ramp(Color col, string fade, double alpha)
        {
            var g = new Gradient();
            var a = alpha;
            switch (fade)
            {
                case "hot":
                    g.SetColor(0, new Color(col.Lerp(Color.WHITE, 0.7), a));
                    g.AddPoint(0.3, new Color(col, a));
                    g.SetColor(g.GetPointCount() - 1, new Color(col.Darkened(0.5), 0.0));
                    break;
                case "flicker":
                    g.SetColor(0, new Color(col, a));
                    g.AddPoint(0.25, new Color(col, a * 0.25));
                    g.AddPoint(0.5, new Color(col, a));
                    g.AddPoint(0.75, new Color(col, a * 0.35));
                    g.SetColor(g.GetPointCount() - 1, new Color(col, 0.0));
                    break;
                case "slow":
                    g.SetColor(0, new Color(col, 0.0));
                    g.AddPoint(0.3, new Color(col, a));
                    g.AddPoint(0.7, new Color(col, a));
                    g.SetColor(g.GetPointCount() - 1, new Color(col, 0.0));
                    break;
                default:
                    g.SetColor(0, new Color(col, 0.0));
                    g.AddPoint(0.12, new Color(col, a));
                    g.AddPoint(0.65, new Color(col, a));
                    g.SetColor(g.GetPointCount() - 1, new Color(col, 0.0));
                    break;
            }
            var t = new GradientTexture1D();
            t.Gradient = g;
            return t;
        }

        public CurveTexture _Curve(GArray points)
        {
            var c = new Curve();
            c.MaxValue = 2.0;
            foreach (var p in points)
                c.AddPoint(p.V2);
            var t = new CurveTexture();
            t.Curve = c;
            return t;
        }

        public void _Particles(GDict s)
        {
            var L = _len;
            GArray at = s.Get("at", GArray.Of(0.5, 1.0)).A;
            var p = new GPUParticles3D();
            p.Name = "Fx_" + GD.Str(s["tex"]);
            p.Amount = (int)s.Get("n", 8);
            p.Lifetime = (double)s.Get("life", 1.0);
            p.Preprocess = p.Lifetime;
            p.Randomness = 0.35;
            p.LocalCoords = !(bool)s.Get("world", false);
            p.Position = AtPoint(((double)at[0] + (double)at[1]) * 0.5) * _ps;
            var pm = new ParticleProcessMaterial();
            pm.EmissionShape = ParticleProcessMaterial.EMISSION_SHAPE_BOX;
            var ext = box.size * 0.5 * (double)s.Get("w", 0.6);
            ext[_axis] = (float)(box.size[_axis] * Math.Abs((double)at[1] - (double)at[0]) * 0.5);
            pm.EmissionBoxExtents = ext * _ps;
            var dir = Vector3.ZERO;
            dir[_axis] = 1.0f;
            pm.Direction = dir;
            pm.Spread = (double)s.Get("spread", 0.0);
            GArray vel = s.Get("vel", GArray.Of(0.0, 0.0)).A;
            pm.InitialVelocityMin = (double)vel[0] * L;
            pm.InitialVelocityMax = (double)vel[1] * L;
            pm.Gravity = s.Get("grav", Vector3.ZERO).V3 * L;
            var ang = (double)s.Get("angle", 0.0);
            pm.AngleMin = -ang;
            pm.AngleMax = ang;
            var spin = (double)s.Get("spin", 0.0);
            pm.AngularVelocityMin = -spin;
            pm.AngularVelocityMax = spin;
            pm.ScaleMin = 0.7;
            pm.ScaleMax = 1.2;
            if ((bool)s.Get("pop", false))
                pm.ScaleCurve = _Curve(GArray.Of(new Vector2(0, 0), new Vector2(0.18, 1.0), new Vector2(1, 0)));
            else if ((bool)s.Get("shrink", false))
                pm.ScaleCurve = _Curve(GArray.Of(new Vector2(0, 1.0), new Vector2(1, 0.25)));
            else if ((bool)s.Get("grow", false))
                pm.ScaleCurve = _Curve(GArray.Of(new Vector2(0, 0.45), new Vector2(1, 1.2)));
            var grid = (double)s.Get("grid", 1.0);
            if (grid > 1.0)
                pm.AnimOffsetMax = 1.0;
            if ((double)s.Get("turb", 0.0) > 0.0)
            {
                pm.TurbulenceEnabled = true;
                pm.TurbulenceNoiseScale = 1.5;
                pm.TurbulenceNoiseStrength = 1.0;
                pm.TurbulenceInfluenceMin = 0.03 * (double)s["turb"];
                pm.TurbulenceInfluenceMax = 0.12 * (double)s["turb"];
            }
            pm.ColorRamp = _Ramp(s["col"].As<Color>(), GD.Str(s.Get("fade", "")), (double)s.Get("alpha", 1.0));
            p.ProcessMaterial = pm;
            var q = new QuadMesh();
            q.Size = Vector2.ONE * (double)s.Get("size", 0.1) * L;
            q.Material = SpriteMat(GD.Str(s["tex"]), grid, (double)s.Get("core", 0.6));
            p.DrawPass1 = q;
            p.VisibilityAabb = new AABB(-Vector3.ONE * L * 2.0, Vector3.ONE * L * 4.0);
            p.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            AddChild(p);
        }

        public MeshInstance3D _Quad(string tex, double size, Color col, GDict s, bool flat = false)
        {
            var mi = new MeshInstance3D();
            var q = new QuadMesh();
            q.Size = Vector2.ONE * size;
            mi.Mesh = q;
            mi.MaterialOverride = SpriteMat(tex, 1.0, (double)s.Get("core", 0.5), new Color(col, (double)s.Get("alpha", 1.0)),
                (double)s.Get("spin", 0.0), (double)s.Get("pulse", 0.0), flat);
            mi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            return mi;
        }

        public void _Pinned(GDict s)
        {
            var flat = GD.Str(s.Get("kind", "")) == "flat";
            var mi = _Quad(GD.Str(s["tex"]), (double)s.Get("size", 0.5) * _len, s["col"].As<Color>(), s, flat);
            mi.Name = "Fx_" + GD.Str(s["tex"]);
            mi.Position = AtPoint((double)s.Get("at", 0.9)) * _ps;
            if (flat)
            {
                // the quad faces +Z: turn it to face along the piece (a halo lies across a staff)
                var ax = Vector3.ZERO;
                ax[_axis] = 1.0f;
                if (_axis != 2)
                    mi.Basis = Basis.LookingAt(-ax, _axis == 1 ? Vector3.BACK : Vector3.UP);
            }
            AddChild(mi);
        }

        public void _Orbit(GDict s)
        {
            var hub = new Node3D();
            hub.Name = "Fx_orbit";
            hub.Position = AtPoint((double)s.Get("at", 0.9)) * _ps;
            AddChild(hub);
            var ax = Vector3.ZERO;
            ax[_axis] = 1.0f;
            var side = _axis != 0 ? Vector3.RIGHT : Vector3.UP;
            var n = (int)s.Get("n", 3);
            for (int i = 0; i < n; i++)
            {
                var mi = _Quad(GD.Str(s["tex"]), (double)s.Get("size", 0.1) * _len, s["col"].As<Color>(), s);
                mi.Position = side.Rotated(ax, GD.TAU * (double)i / (double)n) * (double)s.Get("r", 0.17) * _len;
                hub.AddChild(mi);
            }
            _spinners.Append(GArray.Of(hub, ax, (double)s.Get("speed", 1.8)));
        }

        public void _UpdateRibbon(double delta)
        {
            _clock += delta;
            var model = GetParent() as Node3D;
            if (model == null)
                return;
            var xf = model.GlobalTransform;
            var tip = xf * _tip_l;
            if (!_samples.IsEmpty() && tip.DistanceTo(_samples[0][1].V3) > _len * 1.2)
                _samples.Clear();                              // a jump (a clip starting over, a respawn), not a swing
            _samples.PushFront(GArray.Of(xf * _base_l, tip, _clock));
            while (_samples.Size() > 2 && _clock - (double)_samples[-1][2] > TRAIL_LIFE)
                _samples.PopBack();
            _im.ClearSurfaces();
            var n = _samples.Size();
            if (n < 2)
                return;
            // how fast the tip moved at each sample (a still or idling weapon draws nothing)
            var speed = new GArray();
            var any = false;
            for (int i = 0; i < n; i++)
            {
                var j = i < n - 1 ? i + 1 : i - 1;
                var dt = GD.Maxf(Math.Abs((double)_samples[i][2] - (double)_samples[j][2]), 0.001);
                var v = (_samples[i][1].V3 - _samples[j][1].V3).Length() / dt;
                var a = GD.Clampf((v / GD.Maxf(_len, 0.01) - 1.0) / 2.5, 0.0, 1.0);
                speed.Append(a);
                any = any || a > 0.01;
            }
            if (!any)
                return;
            _im.SurfaceBegin(Fatebound.GUI.Mesh.PRIMITIVE_TRIANGLE_STRIP);
            for (int i = 0; i < n - 1; i++)
            {
                for (int sub = 0; sub < TRAIL_SUB; sub++)
                {
                    var t = (double)sub / (double)TRAIL_SUB;
                    var i0 = GD.Maxi(i - 1, 0);
                    var i3 = GD.Mini(i + 2, n - 1);
                    var b = _Cr(_samples[i0][0].V3, _samples[i][0].V3, _samples[i + 1][0].V3, _samples[i3][0].V3, t);
                    var tp = _Cr(_samples[i0][1].V3, _samples[i][1].V3, _samples[i + 1][1].V3, _samples[i3][1].V3, t);
                    var age = (_clock - GD.Lerpf((double)_samples[i][2], (double)_samples[i + 1][2], t)) / TRAIL_LIFE;
                    var a = GD.Lerpf((double)speed[i], (double)speed[i + 1], t);
                    _im.SurfaceSetColor(new Color(1, 1, 1, a));
                    _im.SurfaceSetUv(new Vector2(age, 0.0));
                    _im.SurfaceAddVertex(b);
                    _im.SurfaceSetColor(new Color(1, 1, 1, a));
                    _im.SurfaceSetUv(new Vector2(age, 1.0));
                    _im.SurfaceAddVertex(tp);
                }
            }
            GArray last = _samples[n - 1].A;
            _im.SurfaceSetColor(new Color(1, 1, 1, (double)speed[n - 1]));
            _im.SurfaceSetUv(new Vector2((_clock - (double)last[2]) / TRAIL_LIFE, 0.0));
            _im.SurfaceAddVertex(last[0].V3);
            _im.SurfaceSetColor(new Color(1, 1, 1, (double)speed[n - 1]));
            _im.SurfaceSetUv(new Vector2((_clock - (double)last[2]) / TRAIL_LIFE, 1.0));
            _im.SurfaceAddVertex(last[1].V3);
            _im.SurfaceEnd();
        }

        public static Vector3 _Cr(Vector3 p0, Vector3 p1, Vector3 p2, Vector3 p3, double t)
        {
            // Catmull-Rom between p1 and p2
            var t2 = t * t;
            var t3 = t2 * t;
            return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3);
        }
    }
}
