// Ported from godot/scripts/app/title_rift_fx.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Color = Fatebound.GUI.Col;

namespace Fatebound.Game
{
    // 0.31.193 (Kevin: "the lighting effect in middle show effects"): the title's rift alive (title_logo.gd puts it over
    // the word, the same size). Along the rift's line (title_logo.gd RIFT, in the base's px; sc turns them into this
    // control's px):
    //  - its white-hot core glows and flickers (title_rift_glow.webp, added on);
    //  - lightning crackles along it: jagged bolts, each a few hundredths of a second, over part of the rift, now and then
    //    forking out into the letters;
    //  - sparks spit off it and fall;
    //  - every couple of seconds a flare: bolts the whole length, the glow up, a burst of sparks (and on the title's slam).
    // With calm (Reduce Motion, and the title screen's afterimages): only the glow, steady.
    public class TitleRiftFx : Control
    {
        public const double GLOW_A = 0.32;

        public List<Vector2> line = new List<Vector2>();
        public double sc = 1.0;
        public bool calm = false;
        public double flare = 0.0;                 // 0..1: the glow's and the bolts' extra, dying away
        public GArray bolts = new GArray();        // {p: PackedVector2Array (base px), w, life, t}
        public int made = 0;                       // bolts made so far (tests)
        public TextureRect glow;
        public CPUParticles2D sparks;
        public CPUParticles2D burst_sparks;
        public Rng rng = new Rng();
        public double _next = 0.2;
        public double _flare_in = 1.4;
        public double _flick = 0.0;

        public TitleRiftFx(Texture2D glow_tex, bool still = false)
        {
            calm = still;
            MouseFilter = Control.MOUSE_FILTER_IGNORE;
            var add = new CanvasItemMaterial();
            add.BlendMode = CanvasBlendMode.Add;
            Material = add;
            glow = new TextureRect();
            glow.Texture = glow_tex;
            glow.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            glow.StretchMode = TextureRect.STRETCH_SCALE;
            glow.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            glow.Material = add;
            var gm = glow.Modulate;
            gm.a = (float)GLOW_A;
            glow.Modulate = gm;
            AddChild(glow);
            sparks = _Emitter(26, 0.75, false);
            burst_sparks = _Emitter(46, 0.9, true);
            sparks.Emitting = !calm;
        }

        public CPUParticles2D _Emitter(int n, double life, bool one_shot)
        {
            var p = new CPUParticles2D();
            p.Amount = n;
            p.Lifetime = life;
            p.OneShot = one_shot;
            p.Explosiveness = one_shot ? 1.0 : 0.0;
            p.Randomness = 0.5;
            p.Emitting = false;
            p.EmissionShape = CPUParticles2D.EMISSION_SHAPE_POINTS;
            p.Direction = new Vector2(0, -1);
            p.Spread = 180.0;
            p.Gravity = new Vector2(0, 300);
            p.Texture = _Dot();
            p.ScaleAmountMin = 0.25;
            p.ScaleAmountMax = 0.6;
            var g = new Gradient();
            g.SetColor(0, new Color(1.0, 1.0, 0.92, 1.0));
            g.AddPoint(0.35, new Color(1.0, 0.86, 0.42, 1.0));
            g.SetColor(g.GetPointCount() - 1, new Color(1.0, 0.45, 0.1, 0.0));
            p.ColorRamp = g;
            var add = new CanvasItemMaterial();
            add.BlendMode = CanvasBlendMode.Add;
            p.Material = add;
            AddChild(p);
            return p;
        }

        public static Texture2D _dot_tex = null;

        public static Texture2D _Dot()
        {
            if (_dot_tex == null)
            {
                var t = new GradientTexture2D();
                t.Width = 24;
                t.Height = 24;
                t.Fill = GradientTexture2D.FillEnum.Radial;
                t.FillFrom = new Vector2(0.5, 0.5);
                t.FillTo = new Vector2(1.0, 0.5);
                var g = new Gradient();
                g.SetColor(0, new Color(1, 1, 1, 1));
                g.AddPoint(0.35, new Color(1, 1, 1, 0.8));
                g.SetColor(g.GetPointCount() - 1, new Color(1, 1, 1, 0));
                t.Gradient = g;
                _dot_tex = t;
            }
            return _dot_tex;
        }

        public void Lay(double s, Rect2 glow_rect)
        {
            sc = s;
            glow.Position = glow_rect.position * s;
            glow.Size = glow_rect.size * s;
            var pts = new List<Vector2>();
            foreach (var q in line)
                pts.Add(q * s);
            foreach (var p in new[] { sparks, burst_sparks })
            {
                p.EmissionPoints = pts.ToArray();
                p.InitialVelocityMin = 40.0 * s;
                p.InitialVelocityMax = 150.0 * s;
                p.Gravity = new Vector2(0, 340.0 * s);
                p.ScaleAmountMin = 0.22 * s / 0.7;
                p.ScaleAmountMax = 0.55 * s / 0.7;
            }
        }

        public void Burst(double strength = 1.0)
        {
            // a flare: bolts the whole length, the glow up, a burst of sparks
            if (calm || line.Count < 2)
                return;
            flare = GD.Maxf(flare, strength);
            for (int i = 0; i < 2 + (int)(strength * 2.0); i++)
                _Bolt(true);
            burst_sparks.Restart();
            burst_sparks.Emitting = true;
        }

        protected override void _Process(double delta)
        {
            if (calm || line.Count < 2)
                return;
            _flare_in -= delta;
            if (_flare_in <= 0.0)
            {
                Burst(0.8);
                _flare_in = rng.RandfRange(1.6, 3.2);
            }
            flare = GD.Maxf(0.0, flare - delta * 1.8);
            _next -= delta;
            if (_next <= 0.0)
            {
                _Bolt(false);
                _next = rng.RandfRange(0.05, 0.18) * (flare > 0.3 ? 0.4 : 1.0);
            }
            var i = bolts.Size() - 1;
            while (i >= 0)
            {
                bolts[i].D["life"] -= delta;
                if ((double)bolts[i]["life"] <= 0.0)
                    bolts.RemoveAt(i);
                i -= 1;
            }
            _flick = GD.Lerpf(_flick, rng.RandfRange(-1.0, 1.0), GD.Minf(1.0, delta * 18.0));
            var gm = glow.Modulate;
            gm.a = (float)GD.Clampf(GLOW_A + 0.14 * _flick + 0.5 * flare + 0.08 * bolts.Size(), 0.12, 0.95);
            glow.Modulate = gm;
            QueueRedraw();
        }

        public void _Bolt(bool full)
        {
            var n = line.Count;
            var i0 = 0;
            var i1 = n - 1;
            if (!full)
            {
                var span = rng.RandiRange(4, GD.Mini(14, n - 1));
                i0 = rng.RandiRange(0, n - 1 - span);
                i1 = i0 + span;
            }
            var pts = new List<Vector2>();
            for (int i = i0; i < i1; i++)
            {
                Vector2 a = line[i];
                Vector2 b = line[i + 1];
                var steps = GD.Maxi(1, (int)(a.DistanceTo(b) / 5.0));
                var nrm = (b - a).Normalized().Orthogonal();
                for (int k = 0; k < steps; k++)
                {
                    var q = a.Lerp(b, (double)k / (double)steps);
                    var edge = GD.Minf((double)(i - i0) + (double)k / (double)steps, (double)(i1 - i)); // (pinned at its two ends)
                    pts.Add(q + nrm * (double)rng.RandfRange(-6.0, 6.0) * GD.Clampf(edge, 0.0, 1.0));
                }
            }
            pts.Add(line[i1]);
            double w = rng.RandfRange(2.2, 3.4) * (full ? 1.3 : 1.0);
            double life = rng.RandfRange(0.05, 0.12) * (full ? 1.6 : 1.0);
            bolts.Append(GDict.Of("p", Var.Of(pts.ToArray()), "w", w, "life", life, "t", life));
            made += 1;
            // a fork or two off it, out into the letters
            var forks = full ? rng.RandiRange(1, 3) : rng.RandiRange(0, 1);
            for (int f = 0; f < forks; f++)
            {
                var at = rng.RandiRange(1, GD.Maxi(1, pts.Count - 2));
                var dir = new Vector2(rng.Randf() < 0.5 ? 1.0 : -1.0, rng.RandfRange(-0.6, 0.9)).Normalized();
                var fp = new List<Vector2> { pts[at] };
                Vector2 q = pts[at];
                var steps = rng.RandiRange(3, 6);
                for (int k = 0; k < steps; k++)
                {
                    q += dir * (double)rng.RandfRange(5.0, 11.0) + new Vector2(rng.RandfRange(-4.0, 4.0), rng.RandfRange(-4.0, 4.0));
                    fp.Add(q);
                }
                bolts.Append(GDict.Of("p", Var.Of(fp.ToArray()), "w", w * 0.55, "life", life, "t", life));
            }
        }

        protected override void _Draw()
        {
            foreach (var b in bolts)
            {
                var a = GD.Clampf((double)b["life"] / (double)b["t"], 0.0, 1.0);
                var pts = new List<Vector2>();
                foreach (var q in b["p"].As<Vector2[]>())
                    pts.Add(q * sc);
                DrawPolyline(pts, new Color(1.0, 0.78, 0.38, 0.35 * a), (double)b["w"] * 3.4 * sc, true);
                DrawPolyline(pts, new Color(1.0, 0.98, 0.9, 0.95 * a), (double)b["w"] * sc, true);
            }
        }
    }
}
