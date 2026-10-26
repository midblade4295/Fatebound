// Ported from godot/scripts/app/reward_fly.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Color = Fatebound.GUI.Col;

namespace Fatebound.Game
{
    // Currency gains fly into their counters (0.31.105, Kevin: "when a player obtains them it'll play a animation where they
    // fly to the players total amount at top of screen"). A burst of the new Meshy coins / diamonds / embers (pre-rendered
    // turning, assets/ui/currency/*_spin.png from tools/render_currency_icons.gd) pops out of where the reward came from,
    // then each piece curves up into its counter in the top bar; the counter counts up as they land. Lives on a CanvasLayer
    // above everything (modals too). siege_app.gd decides when (a rise in the profile's gold / gems / embers).
    public class RewardFly : Node2D
    {
        public const int FRAMES = 16;
        public const double SIZE = 58.0;                     // a piece's height in flight (px)
        public static readonly GDict KINDS = new GDict
        {
            { "coin", GDict.Of("spin", "res://assets/ui/currency/coin_spin.png", "fps", 20.0, "spark", new Color(1.0, 0.86, 0.38),
                "glow", new Color(1.0, 0.78, 0.3, 0.5), "rise", 0.0) },
            { "gem", GDict.Of("spin", "res://assets/ui/currency/gem_spin.png", "fps", 10.0, "spark", new Color(0.7, 0.95, 1.0),
                "glow", new Color(0.35, 0.8, 1.0, 0.55), "rise", 0.0) },
            { "ember", GDict.Of("spin", "res://assets/ui/currency/ember_spin.png", "fps", 14.0, "spark", new Color(1.0, 0.55, 0.15),
                "glow", new Color(1.0, 0.42, 0.08, 0.75), "rise", -90.0) },
        };
        public int flying = 0;                        // pieces in the air (tests)
        public int bursts = 0;                        // bursts started (tests)
        public Texture2D _dot;
        public Texture2D _sparkle;
        public Texture2D _flame;
        public CanvasItemMaterial _add_mat;
        public GDict _sheets = new GDict();
        public double _t = 0.0;

        protected override void _Ready()
        {
            var g = new Gradient();
            g.SetColor(0, new Color(1, 1, 1, 1));
            g.SetColor(1, new Color(1, 1, 1, 0));
            var gt = new GradientTexture2D();
            gt.Gradient = g;
            gt.Fill = GradientTexture2D.FillEnum.Radial;
            gt.FillFrom = new Vector2(0.5, 0.5);
            gt.FillTo = new Vector2(1.0, 0.5);
            gt.Width = 64;
            gt.Height = 64;
            _dot = gt;
            _sparkle = ResourceLoader.Exists("res://assets/vfx/weapon/sparkle.png") ? ResourceLoader.Load<Texture2D>("res://assets/vfx/weapon/sparkle.png") : _dot;
            _flame = ResourceLoader.Exists("res://assets/vfx/weapon/flame.png") ? ResourceLoader.Load<Texture2D>("res://assets/vfx/weapon/flame.png") : null;
            _add_mat = new CanvasItemMaterial();
            _add_mat.BlendMode = CanvasBlendMode.Add;
        }

        public static int PiecesFor(int amount)
        {
            // a few for a little, a dozen for a lot
            return GD.Clampi((int)GD.Round(2.0 + Math.Log((double)GD.Maxi(amount, 1) + 1.0) / Math.Log(2.0) * 1.1), 3, 12);
        }

        public void Burst(string kind, int amount, Vector2 from, Control target, Action<int> land, Action done)
        {
            // land(share) as each piece reaches the counter (the shares add up to amount); done() after the last
            var n = PiecesFor(amount);
            var shares = new List<int>();
            for (int i = 0; i < n; i++)
                shares.Add(amount / n + (i < amount % n ? 1 : 0));
            bursts += 1;
            var left = new[] { n };
            for (int i = 0; i < n; i++)
            {
                var ii = i;
                _Piece(kind, from, target, i, () =>
                {
                    land(shares[ii]);
                    left[0] -= 1;
                    if (left[0] == 0)
                        done();
                });
            }
        }

        public Texture2D _Sheet(string kind)
        {
            if (!_sheets.Has(kind))
            {
                string p = GD.Str(KINDS[kind]["spin"]);
                _sheets[kind] = ResourceLoader.Exists(p) ? Var.Of(ResourceLoader.Load(p)) : Var.Nil;
            }
            return _sheets[kind].As<Texture2D>();
        }

        public Vector2 _TargetPoint(Control target, Vector2 fallback)
        {
            return GD.IsInstanceValid(target) && target.IsVisibleInTree() ? target.GetGlobalRect().GetCenter() : fallback;
        }

        public void _Piece(string kind, Vector2 from, Control target, int i, Action arrived)
        {
            GDict spec = KINDS[kind].D;
            var s = new Sprite2D();
            var sheet = _Sheet(kind);
            if (sheet != null)
            {
                s.Texture = sheet;
                s.Hframes = FRAMES;
                s.Frame = (int)(GD.Randi() % FRAMES);
            }
            else
                s.Texture = ResourceLoader.Load<Texture2D>(GD.Fmt("res://assets/ui/currency/%s.png", kind == "coin" ? "coin" : kind));
            var @base = SIZE / (double)s.Texture.GetHeight();
            s.Scale = Vector2.ONE * @base * 0.2;
            s.Position = from;
            s.Visible = false;
            s.SetMeta("fps", (double)spec["fps"] * GD.RandfRange(0.8, 1.25));
            s.SetMeta("f0", GD.Randf() * FRAMES);
            AddChild(s);
            flying += 1;
            var halo = new Sprite2D();                  // a soft glow round the piece
            halo.Texture = _dot;
            halo.Material = _add_mat;
            halo.Modulate = (Color)spec["glow"];
            halo.Scale = Vector2.ONE * (SIZE * 1.5 / 64.0) / @base;
            halo.ShowBehindParent = true;
            s.AddChild(halo);
            if (kind == "ember" && _flame != null)        // the ember's flame (the concept's; not in the model)
            {
                var fl = new Sprite2D();
                fl.Texture = _flame;
                fl.Material = _add_mat;
                fl.Modulate = new Color(1.0, 0.55, 0.15, 0.95);
                fl.Offset = new Vector2(0, -_flame.GetHeight() * 0.42);
                fl.Position = new Vector2(0, -s.Texture.GetHeight() * 0.18);
                fl.Scale = Vector2.ONE * (SIZE * 0.9 / (double)_flame.GetHeight()) / @base;
                fl.SetMeta("flame", fl.Scale);
                s.AddChild(fl);
            }
            var sp = new CPUParticles2D();              // a short trail of sparks
            sp.Texture = kind == "ember" ? _dot : _sparkle;
            sp.Material = _add_mat;
            sp.LocalCoords = false;
            sp.Amount = 14;
            sp.Lifetime = 0.42;
            sp.Emitting = false;
            sp.Direction = new Vector2(0, 1);
            sp.Spread = 180.0;
            sp.InitialVelocityMin = 10.0;
            sp.InitialVelocityMax = 40.0;
            sp.Gravity = new Vector2(0, (double)spec["rise"]);
            var ts = 64.0 / (double)sp.Texture.GetWidth();   // (sizes for the 64 px dot)
            sp.ScaleAmountMin = 0.06 * ts * (kind != "ember" ? 1.6 : 1.0);
            sp.ScaleAmountMax = 0.16 * ts * (kind != "ember" ? 1.6 : 1.0);
            var ramp = new Gradient();
            ramp.SetColor(0, new Color((Color)spec["spark"], 1.0));
            ramp.SetColor(1, new Color((Color)spec["spark"], 0.0));
            sp.ColorRamp = ramp;
            AddChild(sp);
            // out of the reward in a burst, then up into the counter on a curve
            var out_dir = Vector2.FromAngle(GD.RandfRange(-GD.PI * 0.92, -GD.PI * 0.08));
            var p1 = from + out_dir * GD.RandfRange(55.0, 125.0);
            var bend = GD.RandfRange(-1.0, 1.0) * 110.0;
            var t_out = GD.RandfRange(0.22, 0.3);
            var t_home = GD.RandfRange(0.48, 0.62);
            var tw = CreateTween();
            tw.TweenInterval(i * 0.055);
            tw.TweenCallback(() =>
            {
                s.Visible = true;
                sp.Position = s.Position;
                sp.Emitting = true;
            });
            tw.TweenMethod<double>((double t) =>
            {
                var e = 1.0 - Math.Pow(1.0 - t, 3.0);
                s.Position = from.Lerp(p1, e);
                s.Scale = Vector2.ONE * @base * GD.Lerpf(0.25, 1.0, e);
                sp.Position = s.Position;
            }, 0.0, 1.0, t_out);
            tw.TweenMethod<double>((double t) =>
            {
                var p3 = _TargetPoint(target, new Vector2(GetViewportRect().size.x * 0.75, 30.0));
                var mid = (p1 + p3) * 0.5;
                var perp = (p3 - p1).Orthogonal().Normalized();
                var c = mid + perp * bend + new Vector2(0, -50);
                var e = t * t;
                s.Position = p1.Lerp(c, e).Lerp(c.Lerp(p3, e), e);
                s.Scale = Vector2.ONE * @base * GD.Lerpf(1.0, 0.55, e);
                sp.Position = s.Position;
            }, 0.0, 1.0, t_home);
            tw.TweenCallback(() =>
            {
                flying -= 1;
                sp.Emitting = false;
                _Flash(s.Position, (Color)spec["glow"]);
                s.QueueFree();
                var kill = sp.CreateTween();             // let the last sparks fade, then go
                kill.TweenInterval(sp.Lifetime + 0.05);
                kill.TweenCallback(sp.QueueFree);
                arrived();
            });
        }

        public void _Flash(Vector2 at, Color col)
        {
            var f = new Sprite2D();
            f.Texture = _dot;
            f.Material = _add_mat;
            f.Modulate = new Color(col, 0.9);
            f.Position = at;
            f.Scale = Vector2.ONE * 0.5;
            AddChild(f);
            var tw = f.CreateTween().SetParallel();
            tw.TweenProperty(f, "scale", Vector2.ONE * 1.4, 0.25).SetEase(Tween.EASE_OUT);
            tw.TweenProperty(f, "modulate:a", 0.0, 0.25);
            tw.Chain().TweenCallback(f.QueueFree);
        }

        protected override void _Process(double delta)
        {
            _t += delta;
            foreach (var c in GetChildren())
            {
                if (!(c is Sprite2D && c.HasMeta("fps")))
                    continue;
                if ((c as Sprite2D).Hframes == FRAMES)
                    (c as Sprite2D).Frame = (int)(GD.Float(Var.Of(c.GetMeta("f0"))) + _t * GD.Float(Var.Of(c.GetMeta("fps")))) % FRAMES;
                foreach (var f in c.GetChildren())
                {
                    if (f.HasMeta("flame"))                   // the flame flickers and stays upright while the ember tumbles
                    {
                        var k = GD.Float(Var.Of(c.GetMeta("f0")));
                        Vector2 b = f.GetMeta<Vector2>("flame");
                        (f as Sprite2D).Scale = b * new Vector2(1.0 + 0.12 * Math.Sin(_t * 23.0 + k), 1.0 + 0.2 * Math.Sin(_t * 17.0 + k * 2.0));
                    }
                }
            }
        }
    }
}
