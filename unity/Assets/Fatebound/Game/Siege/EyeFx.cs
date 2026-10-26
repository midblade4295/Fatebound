// Ported from godot/scripts/siege/eye_fx.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector3 = Fatebound.Sim.Vec3;
using Color = Fatebound.GUI.Col;
using Quaternion = Fatebound.Sim.Quat;
using AABB = Fatebound.Sim.Aabb;

namespace Fatebound.Game
{
    using Root = Fatebound.Game.WeaponFxRoot;

    // Glowing, smoking eyes (0.31.192, Kevin: "add glow/smoky effects to the necromancers eyes"). siege_view.make_body puts
    // one under a BoneAttachment3D on the head (EYE_FX: each eye's place on the mesh, through the head's skin bind) and
    // sets pts / col / lite. Built on its first frame in the tree, like weapon_fx_root.gd: Godot draws a particle at its own
    // size whatever the emitter's scale, so this node undoes the world scale and everything below is in world units, sized
    // from the distance between the eyes (the same look on every body size).
    //  - each eye: a white-hot core and a wider soft glow in the eye's colour (billboards, pulsing out of step);
    //  - each eye: wisps and a thin smoke in its colour streaming off it -- out to its side across the temple, and up --
    //    left behind in the world as he moves (not with "lite": another player's body with fewer effects on keeps the
    //    glow only).
    public class EyeFx : Node3D
    {
        public GArray pts = new GArray();          // the eyes, in the head attachment's space
        public Vector3 up = Vector3.UP;            // the face's up and forward, in that space
        public Vector3 fwd = Vector3.BACK;
        public Color col = Color.FromCode("#9dff5a");
        public bool lite = false;
        public bool _built = false;

        protected override void _Process(double _d)
        {
            if (!_built)
            {
                _built = true;
                _Build();
            }
            SetProcess(false);
        }

        public void _Build()
        {
            if (pts.Size() < 1)
                return;
            var ps = GD.Maxf(GlobalBasis.GetScale().x, 0.0001);
            Scale = Vector3.ONE / ps;
            var gap = 0.1;
            var mid = Vector3.ZERO;
            foreach (var q in pts)
                mid += q.V3 / (double)pts.Size();
            if (pts.Size() >= 2)
                gap = GD.Maxf((pts[0].V3 - pts[1].V3).Length() * ps, 0.02);
            for (int i = 0; i < pts.Size(); i++)
            {
                var eye = new Node3D();
                eye.Name = GD.Fmt("Eye%d", i);
                eye.Position = pts[i].V3 * ps;
                AddChild(eye);
                // the glow: a soft halo, then the core (white at its heart); the two eyes pulse a little out of step
                eye.AddChild(_Glow("Glow", gap * 1.25, new Color(col, 0.55), 0.0, 0.3 + 0.08 * i));
                eye.AddChild(_Glow("Core", gap * 0.5, new Color(col.Lightened(0.25), 1.0), 0.95, 0.2 + 0.05 * i));
                if (lite)
                    continue;
                var @out = (pts[i].V3 - mid).NormalizedChecked();
                var dir = (@out * 0.85 + fwd.NormalizedChecked() * 0.2 + up.NormalizedChecked() * 0.5).NormalizedChecked();
                foreach (var pr in new Node3D[] { _Smoke("Wisps", "wisp", 9, 1.0, gap * 0.85, gap, 0.6, 1.0, 1.3), _Smoke("Smoke", "smoke", 5, 1.5, gap * 1.0, gap, 0.0, 0.35, 0.8) })
                {
                    pr.Basis = new Basis(new Quaternion(Vector3.UP, dir));       // streaming out along dir
                    eye.AddChild(pr);
                }
            }
        }

        public MeshInstance3D _Glow(string nm, double size, Color c, double core, double pulse)
        {
            var mi = new MeshInstance3D();
            mi.Name = nm;
            var q = new QuadMesh();
            q.Size = Vector2.ONE * size;
            mi.Mesh = q;
            mi.MaterialOverride = Root.SpriteMat("dot", 1.0, core, c, 0.0, pulse);
            mi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            return mi;
        }

        public GPUParticles3D _Smoke(string nm, string tex, int n, double life, double size, double gap, double core, double alpha, double speed)
        {
            // off the eye along the emitter's +Y, rising, left behind in the world, growing and fading
            var p = new GPUParticles3D();
            p.Name = nm;
            p.Amount = n;
            p.Lifetime = life;
            p.Preprocess = life;
            p.Randomness = 0.4;
            p.LocalCoords = false;
            var pm = new ParticleProcessMaterial();
            pm.EmissionShape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE;
            pm.EmissionSphereRadius = gap * 0.12;
            pm.Direction = Vector3.UP;
            pm.Spread = 22.0;
            pm.InitialVelocityMin = gap * 1.2 * speed;
            pm.InitialVelocityMax = gap * 2.2 * speed;
            pm.Gravity = new Vector3(0, gap * 1.4, 0);
            pm.DampingMin = gap * 0.5;
            pm.DampingMax = gap * 1.0;
            pm.AngleMin = -180.0;
            pm.AngleMax = 180.0;
            pm.AngularVelocityMin = -60.0;
            pm.AngularVelocityMax = 60.0;
            pm.ScaleMin = 0.7;
            pm.ScaleMax = 1.2;
            var sc = new Curve();
            sc.MaxValue = 2.0;
            sc.AddPoint(new Vector2(0.0, 0.35));
            sc.AddPoint(new Vector2(1.0, 1.4));
            var st = new CurveTexture();
            st.Curve = sc;
            pm.ScaleCurve = st;
            pm.TurbulenceEnabled = true;
            pm.TurbulenceNoiseScale = 1.2;
            pm.TurbulenceNoiseStrength = 1.0;
            pm.TurbulenceInfluenceMin = 0.04;
            pm.TurbulenceInfluenceMax = 0.12;
            var g = new Gradient();
            g.SetColor(0, new Color(col.Lightened(0.2), 0.0));
            g.AddPoint(0.12, new Color(col.Lightened(0.1), alpha));
            g.AddPoint(0.55, new Color(col, alpha * 0.7));
            g.SetColor(g.GetPointCount() - 1, new Color(col.Darkened(0.3), 0.0));
            var gt = new GradientTexture1D();
            gt.Gradient = g;
            pm.ColorRamp = gt;
            p.ProcessMaterial = pm;
            var q = new QuadMesh();
            q.Size = Vector2.ONE * size;
            q.Material = Root.SpriteMat(tex, 1.0, core);
            p.DrawPass1 = q;
            p.VisibilityAabb = new AABB(new Vector3(-gap * 4.0, -gap * 2.0, -gap * 4.0), new Vector3(gap * 8.0, gap * 10.0, gap * 8.0));
            p.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            return p;
        }
    }
}
