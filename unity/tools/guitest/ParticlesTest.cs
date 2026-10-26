// `guitest particles`: a smoke run of ParticlesSim (GUI/Scene3D, the CPU port of Godot's GPU particles) -- sphere and box
// emitters, one-shot, fixed_fps 30 and free-running, colour ramp, scale curve, turbulence, align-to-velocity -- for two
// seconds at 60 fps, printing instance counts, live particles, the first transforms, colours and INSTANCE_CUSTOM.
using System;
using System.Globalization;
using Fatebound.GUI;
using Fatebound.Sim;

namespace GuiTest
{
    public static class ParticlesTest
    {
        static string F(double v) => v.ToString("0.0000", CultureInfo.InvariantCulture);
        static string V(Vec3 v) => "(" + F(v.x) + ", " + F(v.y) + ", " + F(v.z) + ")";
        static string C(Col c) => "(" + F(c.r) + ", " + F(c.g) + ", " + F(c.b) + ", " + F(c.a) + ")";

        static GradientTexture1D Ramp()
        {
            var g = new Gradient();
            g.Colors[0] = new Col(1f, 0.8f, 0.2f, 1f);
            g.Colors[1] = new Col(0.6f, 0.1f, 0.05f, 0f);
            g.AddPoint(0.3, new Col(1f, 0.4f, 0.1f, 0.9f));
            return new GradientTexture1D { Gradient = g, Width = 64 };
        }

        static CurveTexture ScaleCurve()
        {
            var c = new Curve();
            c.AddPoint(new Vec2(0f, 0.2f), 0, 3);
            c.AddPoint(new Vec2(0.4f, 1f));
            c.AddPoint(new Vec2(1f, 0f), -1, 0);
            return new CurveTexture { Curve = c };
        }

        static void Run(string name, GPUParticles3D p, double seconds, Action<GPUParticles3D, double> during = null)
        {
            var tree = new SceneTree(new Vec2(64, 64));
            tree.Root.AddChild(p);
            var sim = new ParticlesSim(p);
            const double dt = 1.0 / 60.0;
            int frames = (int)Math.Round(seconds / dt);
            for (int f = 1; f <= frames; f++)
            {
                during?.Invoke(p, f * dt);
                tree.Iterate(dt);           // (node side first: one-shot bookkeeping, then the rendering side)
                sim.Update(dt);
                if (f % 30 != 0) continue;
                int alive = 0;
                for (int i = 0; i < sim.Count; i++)
                    if (sim.Transforms[i].basis.GetColumn(0) != new Vec3(0, 0, 0) || sim.Transforms[i].basis.GetColumn(1) != new Vec3(0, 0, 0)) alive++;
                Console.WriteLine("particles|" + name + "|t=" + F(f * dt) + "|active=" + sim.Active + "|count=" + sim.Count + "|alive=" + alive + "|local=" + sim.LocalCoords
                    + "|emitting=" + p.Emitting + "|node " + V(p.GlobalTransform.origin));
                for (int i = 0; i < Math.Min(2, sim.Count); i++)
                {
                    var x = sim.Transforms[i];
                    Console.WriteLine("  [" + i + "] origin " + V(x.origin) + " x " + V(x.basis.GetColumn(0)) + " y " + V(x.basis.GetColumn(1))
                        + " color " + C(sim.Colors[i]) + " custom (" + F(sim.Custom[i * 4]) + ", " + F(sim.Custom[i * 4 + 1]) + ", "
                        + F(sim.Custom[i * 4 + 2]) + ", " + F(sim.Custom[i * 4 + 3]) + ")");
                }
            }
        }

        // ------------------------------------------------------------------ parity with Godot (tools/parity/particles.sh)
        static Curve ParseCurve(string s)
        {
            var c = new Curve();
            foreach (var pt in s.Split(','))
            {
                var xy = pt.Split(':');
                c.AddPoint(new Vec2((float)double.Parse(xy[0], CultureInfo.InvariantCulture), (float)double.Parse(xy[1], CultureInfo.InvariantCulture)));
            }
            return c;
        }

        static object ParseValue(string t, string s)
        {
            double D(string x) => double.Parse(x, CultureInfo.InvariantCulture);
            switch (t)
            {
                case "i": return int.Parse(s, CultureInfo.InvariantCulture);
                case "f": return D(s);
                case "b": return s == "true";
                case "v3": { var p = s.Split(','); return new Vec3((float)D(p[0]), (float)D(p[1]), (float)D(p[2])); }
                case "xf":
                {
                    var p = s.Split(',');
                    var axis = new Vec3((float)D(p[0]), (float)D(p[1]), (float)D(p[2])).NormalizedChecked();
                    return new Xform3(new Basis(axis, (float)D(p[3])), new Vec3((float)D(p[4]), (float)D(p[5]), (float)D(p[6])));
                }
                case "curve": return new CurveTexture { Curve = ParseCurve(s) };
                case "curvexyz": { var cs = s.Split(';'); return new CurveXYZTexture { CurveX = ParseCurve(cs[0]), CurveY = ParseCurve(cs[1]), CurveZ = ParseCurve(cs[2]) }; }
            }
            throw new ArgumentException(t);
        }

        static string Pascal(string snake)
        {
            var sb = new System.Text.StringBuilder();
            bool up = true;
            foreach (char ch in snake) { if (ch == '_') { up = true; continue; } sb.Append(up ? char.ToUpperInvariant(ch) : ch); up = false; }
            return sb.ToString();
        }

        static void Set(object target, string prop, object v)
        {
            string n = Pascal(prop);
            var pi = target.GetType().GetProperty(n);
            if (pi != null) { pi.SetValue(target, pi.PropertyType == typeof(Texture2D) || pi.PropertyType.IsInstanceOfType(v) ? v : Convert.ChangeType(v, pi.PropertyType, CultureInfo.InvariantCulture)); return; }
            var fi = target.GetType().GetField(n);
            if (fi != null) { fi.SetValue(target, fi.FieldType.IsInstanceOfType(v) ? v : Convert.ChangeType(v, fi.FieldType, CultureInfo.InvariantCulture)); return; }
            throw new MissingMemberException(target.GetType().Name, n);
        }

        static string F6(float v) { string s = v.ToString("F6", CultureInfo.InvariantCulture); return s == "-0.000000" ? "0.000000" : s; }

        /// <summary>The setups of tools/parity/particles_cases.txt, printing CaptureAabb() each frame like godot_particles.gd.</summary>
        public static void Parity(string casesPath)
        {
            const int FRAMES = 150;
            var tree = new SceneTree(new Vec2(64, 64));
            var systems = new System.Collections.Generic.Dictionary<string, GPUParticles3D>();
            var order = new System.Collections.Generic.List<string>();
            foreach (var raw in System.IO.File.ReadAllLines(casesPath))
            {
                string line = raw.Trim();
                if (line.Length == 0 || line.StartsWith("#")) continue;
                var p = line.Split('|');
                if (!systems.TryGetValue(p[0], out var n))
                {
                    n = new GPUParticles3D { UseFixedSeed = true, VisibilityAabb = new Aabb(new Vec3(-1000, -1000, -1000), new Vec3(2000, 2000, 2000)),
                        DrawPass1 = new PointMesh(), ProcessMaterial = new ParticleProcessMaterial() };
                    systems[p[0]] = n;
                    order.Add(p[0]);
                }
                object target = p[1] == "node" ? n : (object)n.ProcessMaterial;
                Set(target, p[2], ParseValue(p[3], p[4]));
            }
            var sims = new System.Collections.Generic.List<ParticlesSim>();
            foreach (var name in order) { tree.Root.AddChild(systems[name]); sims.Add(new ParticlesSim(systems[name])); }
            const double dt = 1.0 / 60.0;
            for (int frame = 1; frame <= FRAMES; frame++)
            {
                for (int i = 0; i < order.Count; i++)
                {
                    Aabb a = sims[i].CaptureAabb();
                    Console.WriteLine("pt|" + order[i] + "|" + frame + "|" + F6(a.position.x) + " " + F6(a.position.y) + " " + F6(a.position.z) + " "
                        + F6(a.size.x) + " " + F6(a.size.y) + " " + F6(a.size.z));
                }
                tree.Iterate(dt);
                foreach (var s in sims) s.Update(dt);
            }
        }

        public static void RunAll()
        {
            // sphere emitter, continuous, fixed_fps 30 (Godot's default), colour ramp and scale curve
            var m = new ParticleProcessMaterial
            {
                EmissionShape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
                EmissionSphereRadius = 0.5,
                Direction = new Vec3(0, 1, 0),
                Spread = 25,
                InitialVelocityMin = 1,
                InitialVelocityMax = 2,
                Gravity = new Vec3(0, -1, 0),
                ColorRamp = Ramp(),
                ScaleCurve = ScaleCurve(),
                AngleMin = -30,
                AngleMax = 45,
                AngularVelocityMin = 90,
                AngularVelocityMax = 90,
            };
            var p = new GPUParticles3D { Amount = 12, Lifetime = 1.0, ProcessMaterial = m, Seed = 7 };
            p.Position = new Vec3(0, 2, 0);
            Run("sphere", p, 2.0);

            // box emitter, one shot with explosiveness, damping and hue variation, world-space emission from a moved node
            var mb = new ParticleProcessMaterial
            {
                EmissionShape = ParticleProcessMaterial.EMISSION_SHAPE_BOX,
                EmissionBoxExtents = new Vec3(1, 0.5f, 2),
                Direction = new Vec3(1, 0, 0),
                Spread = 180,
                InitialVelocityMin = 3,
                InitialVelocityMax = 4,
                DampingMin = 2,
                DampingMax = 3,
                HueVariationMin = -0.2,
                HueVariationMax = 0.2,
                Color = new Col(0.2f, 0.6f, 1f, 1f),
            };
            var pb = new GPUParticles3D { Amount = 8, Lifetime = 0.8, OneShot = true, Explosiveness = 0.8, ProcessMaterial = mb, Seed = 99 };
            pb.Position = new Vec3(5, 0, -1);
            Run("box_one_shot", pb, 2.0);

            // ring, free-running (fixed_fps 0), local coordinates, turbulence and align Y to velocity, node moving
            var mr = new ParticleProcessMaterial
            {
                EmissionShape = ParticleProcessMaterial.EMISSION_SHAPE_RING,
                EmissionRingRadius = 1.0,
                EmissionRingInnerRadius = 0.5,
                EmissionRingHeight = 0.2,
                InitialVelocityMin = 0.5,
                InitialVelocityMax = 0.5,
                TurbulenceEnabled = true,
                ParticleFlagAlignY = true,
                LifetimeRandomness = 0.3,
                ScaleMin = 0.5,
                ScaleMax = 1.5,
            };
            var pr = new GPUParticles3D { Amount = 10, Lifetime = 1.5, FixedFps = 0, LocalCoords = true, ProcessMaterial = mr, Seed = 3, Randomness = 0.5 };
            Run("ring_turbulence", pr, 2.0, (n, t) => n.Position = new Vec3((float)t, 0, 0));

            // emitting switched off half way: particles finish their life, then the system goes inactive
            var po = new GPUParticles3D { Amount = 6, Lifetime = 0.5, ProcessMaterial = m, Seed = 5 };
            Run("stop_emitting", po, 2.0, (n, t) => { if (Math.Abs(t - 0.5) < 1e-9) n.Emitting = false; });
        }
    }
}
