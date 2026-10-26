// Ported from godot/scripts/app/camp_scene.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector3 = Fatebound.Sim.Vec3;
using Vector4 = Fatebound.Sim.Vec4;
using Color = Fatebound.GUI.Col;
using UI2 = Fatebound.Game.Ui2;

namespace Fatebound.Game
{
    // 0.31.194 (Kevin: "Now let's design a new home screen" -- he picked B2, the champions' camp): Home's backdrop -- six
    // champions round a campfire in the castle's courtyard at dusk, the castle behind them, its windows lit -- the painting
    // (tools/home_camp.py: art_sources/home_camp/camp.png, 1024 x 2048) brought to life:
    //   - the campfire burns: tongues of flame over the painted ones, swaying and flickering, a hot heart, its glow breathing,
    //     embers spiralling up and a thin smoke over it, and its light flickering over the champions and the stones round it
    //     (camp.gdshader, with the flames);
    //   - the lanterns, the gate's torches and the candle on the Necromancer's crate flicker, each throwing a little light;
    //   - the Necromancer's eyes and the skull in his hand glow green and breathe, wisps curling off them; the Mage's spell
    //     orb pulses blue over his book, sparkles rising off the page;
    //   - the castle's windows glow, now and then one dimming as someone passes; stars twinkle; now and then a star falls;
    //   - fireflies wander the camp; the two big banners ripple; the towers' pennants flutter (camp.gdshader).
    // Everything is laid out in the painting's px, scaled by `place` to the screen's width (a little wider if the screen is
    // tall enough to need it), standing so the champions' feet are just over the PLAY plaque. Reduce Motion (`calm`): the
    // glows hold still, no particles, nothing moves. A safe start (`lite`): the painting and its still glows only.
    // (0.31.138-0.31.193: the war room -- home_scene.gd, war_room.gd: a painted tower room and the live war table in 3D.)
    // 0.31.215 (Kevin: "I want the home screen as good of quality as the clan screen. The home screen looks very AI
    // generated." -> "Real 3D heroes in camp"): the picture is now a 3D render of the game's own models
    // (tools/render_home_camp.gd) -- the Royal kit's castle at dusk, the War kit's tents and braziers, the HD Knight, Mage,
    // King, Barbarian and Stormcaller round a campfire, a sky with stars and the moon -- in place of the painting (0.31.194-
    // 0.31.214, tools/home_camp.py). Over it, as before: the fire's flames, halo, embers and smoke and its light flickering
    // on the picture, stars twinkling and falling, fireflies, the banners rippling; the magic is the Mage's blue gem and the
    // Stormcaller's crystal, glowing and sparkling (the painting's Necromancer, his eyes and skull, and its lit windows are
    // gone with it).
    public class CampScene : Control
    {
        public static readonly Shader CampShader = ResourceLoader.Load<Shader>("res://scripts/app/camp.gdshader");
        public const string ART = "res://assets/ui/v2/bg_camp.webp";
        public static readonly Vector2 PAINT = new Vector2(2048.0, 1024.0);   // (0.31.216: landscape; 1024 x 2048 until then)
        public const double FEET_Y = 614.6;                 // the nearest heroes' boots (the Knight's, the Stormcaller's), down the picture
        public const double FEET_OVER = 6.0;                 // ... this far (screen px) under PLAY's top at most: the plaque hides no more of them
        public const double COVER_TO = 100.0;                // the painting reaches at least this far (screen px) from the screen's bottom
        public static readonly Vector2 FIRE = new Vector2(1024.0, 419.9);   // the campfire's flames (their middle)
        public static readonly Vector2 FIRE_BASE = new Vector2(1024.0, 567.7);
        // the flames' tongues over the painted fire: [x off the base, width, height, phase]
        public static readonly GArray TONGUES = GArray.Of(GArray.Of(-36.0, 44.0, 96.0, 0.0), GArray.Of(-15.0, 56.0, 150.0, 1.9), GArray.Of(8.0, 62.0, 172.0, 3.7), GArray.Of(30.0, 50.0, 118.0, 5.1),
            GArray.Of(46.0, 34.0, 74.0, 2.6), GArray.Of(-50.0, 30.0, 64.0, 4.4));
        // the braziers and torches you can see: [where, size, light's reach (0: none)]
        public static readonly GArray LAMPS = GArray.Of(GArray.Of(new Vector2(843, 200), 0.75, 90.0));   // (the left brazier; the others stand behind the heroes' heads)
        // the magic glowing on the heroes: [where, colour, size] -- the Mage's blue gem, the Stormcaller's crystal
        public static readonly GArray MAGIC = GArray.Of(GArray.Of(new Vector2(664, 310), new Color(0.45, 0.8, 1.0), 1.6), GArray.Of(new Vector2(1447, 268), new Color(0.55, 0.95, 1.0), 1.7));
        public static readonly GArray WINDOWS = new GArray();                    // (the castle's windows are dark at dusk in the render)
        public static readonly Rect2 SKY = new Rect2(0.0, 0.0, 2048.0, 190.0);     // where the stars twinkle (and the falling ones go): above the walls
        public static readonly Rect2 CAMP = new Rect2(120.0, 263.8, 1808.0, 350.7);  // where the fireflies wander
        public static readonly GArray BANNERS = GArray.Of(new Vector4(677, -74, 803, 219), new Vector4(1251, -74, 1362, 219));
        public static readonly GArray PENNANTS = new GArray();
        public static readonly Color FLAME = new Color(1.0, 0.62, 0.26);
        public const double FIRE_K = 1.35;                   // 0.31.216: the fire's size against the portrait picture's (its flames, glows, embers)

        public bool calm = false;
        public bool lite = false;
        public double k = 1.0;                            // painting px -> screen px
        public Vector2 origin = Vector2.ZERO;              // the painting's top left on the screen
        public Control paint_layer;                // the painting and everything on it, in painting px (scaled)
        public TextureRect art;
        public object room = null;                         // (the war room's 3D; the camp has none -- siege_app reads it)
        public CPUParticles2D embers;
        public CPUParticles2D smoke;
        public GArray wisps = new GArray();                   // the magic's sparkles (one stream each)
        public Node2D flies;
        public TextureRect _fire_halo;
        public TextureRect _fire_heart;
        public GArray _tongues = new GArray();                // [TextureRect, phase, height]
        public GArray _lamps = new GArray();                  // {core, halo, phase, a}
        public GArray _pulses = new GArray();                 // [TextureRect, base alpha, rate, phase, depth] (the magic's glows)
        public GArray _windows = new GArray();                // [TextureRect, base alpha, next dim, dim until]
        public GArray _stars = new GArray();                  // [TextureRect, rate, phase]
        public Node2D _shooting;
        public double _clock = 0.0;
        public double flick = 0.0;                        // the fire's flicker now (-1..1)
        public static Texture2D _glow_t = null;    // one soft round glow for every light here
        public static Texture2D _dot_t = null;     // ... and one dot for the particles

        public static Texture2D GlowTexture()
        {
            if (_glow_t == null)
                _glow_t = UI2.GlowTex();
            return _glow_t;
        }

        public class Fireflies : Node2D
        {
            // little lights wandering the camp, each blinking on and off in its own time
            public Rect2 area = new Rect2();
            public Texture2D tex;                  // (camp_scene's one glow texture: a fresh one each frame drew a square)
            public GArray flies = new GArray();               // {p, v, phase, rate, size}

            public void Setup(int n)
            {
                for (int i = 0; i < n; i++)
                {
                    flies.Append(new GDict { { "p", new Vector2(GD.RandfRange(area.position.x, area.End.x), GD.RandfRange(area.position.y, area.End.y)) },
                        { "v", new Vector2(GD.RandfRange(-14.0, 14.0), GD.RandfRange(-10.0, 10.0)) }, { "phase", GD.Randf() * GD.TAU },
                        { "rate", GD.RandfRange(0.5, 1.2) }, { "size", GD.RandfRange(9.0, 15.0) }, { "turn", GD.Randf() * GD.TAU } });
                }
            }

            protected override void _Process(double delta)
            {
                foreach (var f in flies)
                {
                    f.D["turn"] = f["turn"] + GD.RandfRange(-1.6, 1.6) * delta;
                    f.D["v"] = f["v"].V2.Lerp(new Vector2(GD.Cos((double)f["turn"]), GD.Sin((double)f["turn"]) * 0.7) * 16.0, GD.Minf(1.0, delta * 0.8));
                    f.D["p"] = f["p"].V2 + f["v"].V2 * delta;
                    if (!area.HasPoint(f["p"].V2))              // (turned back in at the edges)
                        f.D["turn"] = (area.GetCenter() - f["p"].V2).Angle();
                    f.D["phase"] = f["phase"] + delta * f["rate"];
                }
                QueueRedraw();
            }

            protected override void _Draw()
            {
                foreach (var f in flies)
                {
                    var a = GD.Pow(GD.Maxf(0.0, GD.Sin((double)f["phase"] * GD.TAU * 0.5)), 2.0);
                    if (a < 0.02)
                        continue;
                    double s = (double)f["size"] * (0.7 + 0.3 * a);
                    DrawTextureRect(tex, new Rect2(f["p"].V2 - new Vector2(s, s) * 1.6, new Vector2(s, s) * 3.2), false, new Color(0.75, 1.0, 0.35, 0.35 * a));
                    DrawTextureRect(tex, new Rect2(f["p"].V2 - new Vector2(s, s) * 0.35, new Vector2(s, s) * 0.7), false, new Color(1.0, 1.0, 0.7, 0.95 * a));
                }
            }
        }

        public class FallingStar : Node2D
        {
            // now and then a star falls across the sky
            public Rect2 area = new Rect2();
            public Texture2D tex;
            public double t = -1.0;
            public double wait = 6.0;
            public Vector2 from = Vector2.ZERO;
            public Vector2 dir = Vector2.ZERO;
            public int made = 0;

            protected override void _Process(double delta)
            {
                if (t < 0.0)
                {
                    wait -= delta;
                    if (wait <= 0.0)
                    {
                        t = 0.0;
                        made += 1;
                        from = new Vector2(GD.RandfRange(area.position.x + 100.0, area.End.x - 100.0), GD.RandfRange(area.position.y + 10.0, area.End.y * 0.6));
                        dir = new Vector2(GD.Randf() < 0.5 ? -1.0 : 1.0, GD.RandfRange(0.3, 0.55)).Normalized();
                    }
                }
                else
                {
                    t += delta;
                    if (t > 0.9)
                    {
                        t = -1.0;
                        wait = GD.RandfRange(9.0, 20.0);
                    }
                }
                QueueRedraw();
            }

            protected override void _Draw()
            {
                if (t < 0.0)
                    return;
                var head = from + dir * 420.0 * t;
                var a = GD.Sin(GD.Clampf(t / 0.9, 0.0, 1.0) * GD.PI);
                for (int i = 0; i < 10; i++)
                {
                    var f = (double)i / 10.0;
                    DrawLine(head - dir * 90.0 * f, head - dir * 90.0 * (f + 0.1), new Color(1.0, 0.97, 0.85, a * (1.0 - f) * 0.9), 3.0 * (1.0 - f) + 0.6, true);
                }
                DrawTextureRect(tex, new Rect2(head - new Vector2(10, 10), new Vector2(20, 20)), false, new Color(1, 1, 0.9, a));
            }
        }

        public CampScene(bool reduce_motion = false, bool safe = false)
        {
            calm = reduce_motion;
            lite = safe;
        }

        protected override void _Ready()
        {
            MouseFilter = Control.MOUSE_FILTER_IGNORE;
            ClipContents = true;
            paint_layer = new Control();
            paint_layer.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            paint_layer.Size = PAINT;
            AddChild(paint_layer);
            art = new TextureRect();
            art.Texture = UI2.Tex(ART);
            art.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            art.StretchMode = TextureRect.STRETCH_SCALE;
            art.Size = PAINT;
            art.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            art.SetMeta("home_art", true);
            var m = new ShaderMaterial();
            m.Shader = CampShader;
            m.SetShaderParameter("paint_size", PAINT);
            m.SetShaderParameter("motion", calm ? 0.0 : 1.0);
            m.SetShaderParameter("fire", new Vector3(FIRE.x, FIRE.y + 20.0, 360.0));
            var lamps = new GArray();
            for (int i = 0; i < LAMPS.Size(); i++)
            {
                if ((double)LAMPS[i][2] > 0.0)
                    lamps.Append(new Vector4(LAMPS[i][0].V2.x, LAMPS[i][0].V2.y, (double)LAMPS[i][2], 1.7 * i));
            }
            if (!lamps.IsEmpty())                       // (0.31.215: the render may have none in view)
                m.SetShaderParameter("lamps", lamps);
            m.SetShaderParameter("lamp_n", lamps.Size());
            if (!BANNERS.IsEmpty())
                m.SetShaderParameter("cloth", BANNERS);
            m.SetShaderParameter("cloth_n", BANNERS.Size());
            if (!PENNANTS.IsEmpty())
                m.SetShaderParameter("pennants", PENNANTS);
            m.SetShaderParameter("pennant_n", PENNANTS.Size());
            art.Material = m;
            paint_layer.AddChild(art);
            _BuildSky();
            _BuildWindows();
            _BuildFire();
            for (int i = 0; i < LAMPS.Size(); i++)
                _Lamp(LAMPS[i][0].V2, (double)LAMPS[i][1], i);
            _BuildMagic();
            if (!calm && !lite)
            {
                var ff = new Fireflies();
                flies = ff;
                ff.tex = GlowTexture();
                ff.area = CAMP;
                ff.Setup(14);
                paint_layer.AddChild(flies);
            }
        }

        public TextureRect _Glow(Control parent, Vector2 centre, Vector2 sz, Color col, bool add = true)
        {
            var t = new TextureRect();
            t.Texture = GlowTexture();
            t.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            t.StretchMode = TextureRect.STRETCH_SCALE;
            t.Size = sz;
            t.PivotOffset = sz * 0.5;
            t.Position = centre - sz * 0.5;
            t.Modulate = col;
            t.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            if (add)
            {
                var mat = new CanvasItemMaterial();
                mat.BlendMode = CanvasBlendMode.Add;
                t.Material = mat;
            }
            parent.AddChild(t);
            return t;
        }

        public static Texture2D _DotTex()
        {
            if (_dot_t != null)
                return _dot_t;
            var t = new GradientTexture2D();
            t.Width = 24;
            t.Height = 24;
            t.Fill = GradientTexture2D.FillEnum.Radial;
            t.FillFrom = new Vector2(0.5, 0.5);
            t.FillTo = new Vector2(1.0, 0.5);
            var g = new Gradient();
            g.SetColor(0, new Color(1, 1, 1, 1));
            g.AddPoint(0.35, new Color(1, 1, 1, 0.75));
            g.SetColor(g.GetPointCount() - 1, new Color(1, 1, 1, 0));
            t.Gradient = g;
            _dot_t = t;
            return t;
        }

        public CPUParticles2D _Particles(Vector2 at, int n, double life, GArray ramp, bool add = true)
        {
            var p = new CPUParticles2D();
            p.Position = at;
            p.Amount = n;
            p.Lifetime = life;
            p.Preprocess = life;
            p.Texture = _DotTex();
            p.LocalCoords = false;
            var g = new Gradient();
            g.SetColor(0, (Color)ramp[0]);
            for (int i = 1; i < ramp.Size() - 1; i++)
                g.AddPoint((double)i / (double)(ramp.Size() - 1), (Color)ramp[i]);
            g.SetColor(g.GetPointCount() - 1, (Color)ramp[ramp.Size() - 1]);
            p.ColorRamp = g;
            if (add)
            {
                var mat = new CanvasItemMaterial();
                mat.BlendMode = CanvasBlendMode.Add;
                p.Material = mat;
            }
            p.Emitting = !calm && !lite;
            paint_layer.AddChild(p);
            return p;
        }

        // ---------------- the sky and the castle ----------------
        public void _BuildSky()
        {
            var rng = new Rng();
            rng.Seed = 194;
            for (int i = 0; i < 18; i++)
            {
                var at = new Vector2(rng.RandfRange(SKY.position.x + 20.0, SKY.End.x - 20.0), rng.RandfRange(SKY.position.y + 10.0, SKY.End.y));
                var st = _Glow(paint_layer, at, Vector2.ONE * rng.RandfRange(9.0, 16.0), new Color(0.95, 0.93, 1.0, !calm ? 0.0 : 0.35));
                _stars.Append(GArray.Of(st, rng.RandfRange(0.4, 1.2), rng.Randf() * GD.TAU));
            }
            var fs = new FallingStar();
            _shooting = fs;
            fs.tex = GlowTexture();
            fs.area = SKY;
            fs.wait = 4.0;
            paint_layer.AddChild(_shooting);
            if (calm || lite)
                _shooting.ProcessMode = ProcessModeEnum.Disabled;
        }

        public void _BuildWindows()
        {
            for (int i = 0; i < WINDOWS.Size(); i++)
            {
                var a = 0.32;
                var g = _Glow(paint_layer, WINDOWS[i].V2, new Vector2(46, 46), new Color(1.0, 0.78, 0.4, a));
                _windows.Append(GArray.Of(g, a, GD.RandfRange(3.0, 14.0) + i * 1.3, 0.0));
            }
        }

        // ---------------- the campfire ----------------
        public void _BuildFire()
        {
            var fk = FIRE_K;                                 // (0.31.216: the fire's size in the picture against the portrait one's)
            _fire_halo = _Glow(paint_layer, FIRE + new Vector2(0, 30) * fk, new Vector2(520, 420) * fk, new Color(1.0, 0.5, 0.18, 0.32));
            smoke = _Particles(FIRE + new Vector2(0, -90) * fk, 14, 4.5, GArray.Of(new Color(0.35, 0.3, 0.32, 0.0), new Color(0.35, 0.3, 0.32, 0.16),
                new Color(0.3, 0.28, 0.32, 0.1), new Color(0.3, 0.28, 0.32, 0.0)), false);
            smoke.EmissionShape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE;
            smoke.EmissionRectExtents = new Vector2(18, 6);
            smoke.Direction = new Vector2(0.15, -1.0);
            smoke.Spread = 10.0;
            smoke.Gravity = new Vector2(6, -4);
            smoke.InitialVelocityMin = 20.0;
            smoke.InitialVelocityMax = 34.0;
            smoke.ScaleAmountMin = 2.2;
            smoke.ScaleAmountMax = 3.6;
            smoke.ScaleAmountCurve = _RisingCurve();
            foreach (var tg in TONGUES)
            {
                double w = (double)tg[1] * fk;
                double h = (double)tg[2] * fk;
                var t = _Glow(paint_layer, Vector2.ZERO, new Vector2(w, h), new Color(1.0, 0.55, 0.16, 0.85));
                t.PivotOffset = new Vector2(w * 0.5, h * 0.92);
                t.Position = FIRE_BASE + new Vector2((double)tg[0] * fk, 0.0) - t.PivotOffset;
                _tongues.Append(GArray.Of(t, (double)tg[3], h));
            }
            _fire_heart = _Glow(paint_layer, FIRE_BASE + new Vector2(0, -34) * fk, new Vector2(84, 74) * fk, new Color(1.0, 0.92, 0.62, 0.8));
            embers = _Particles(FIRE_BASE + new Vector2(0, -40) * fk, 26, 2.6, GArray.Of(new Color(1.0, 0.95, 0.7, 1.0), new Color(1.0, 0.7, 0.25, 1.0),
                new Color(1.0, 0.4, 0.1, 0.8), new Color(0.9, 0.2, 0.05, 0.0)));
            embers.EmissionShape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE;
            embers.EmissionRectExtents = new Vector2(36, 18) * fk;
            embers.Direction = new Vector2(0, -1);
            embers.Spread = 22.0;
            embers.Gravity = new Vector2(0, -30);
            embers.InitialVelocityMin = 50.0;
            embers.InitialVelocityMax = 120.0;
            embers.TangentialAccelMin = -30.0;
            embers.TangentialAccelMax = 30.0;
            embers.ScaleAmountMin = 0.18;
            embers.ScaleAmountMax = 0.42;
        }

        public static Curve _RisingCurve()
        {
            var c = new Curve();
            c.AddPoint(new Vector2(0.0, 0.4));
            c.AddPoint(new Vector2(1.0, 1.0));
            return c;
        }

        public void _Lamp(Vector2 at, double s, int i)
        {
            // a lantern's (or torch's, or candle's) flame: its halo and a bright core that flickers and sways
            var halo = _Glow(paint_layer, at, new Vector2(120, 120) * s, new Color(FLAME, 0.36));
            var core = _Glow(paint_layer, at, new Vector2(16, 30) * s, new Color(1.0, 0.78, 0.4, 0.85));
            core.PivotOffset = new Vector2(core.Size.x * 0.5, core.Size.y * 0.85);
            core.Position = at - core.PivotOffset + new Vector2(0, core.Size.y * 0.35);
            _lamps.Append(new GDict { { "core", core }, { "halo", halo }, { "phase", GD.Randf() * GD.TAU + i * 1.37 }, { "a", halo.Modulate.a } });
        }

        // ---------------- the magic: the Mage's gem, the Stormcaller's crystal ----------------
        public void _BuildMagic()
        {
            for (int i = 0; i < MAGIC.Size(); i++)
            {
                Vector2 at = MAGIC[i][0].V2;
                Color col = (Color)MAGIC[i][1];
                double sz = (double)MAGIC[i][2];
                _pulses.Append(GArray.Of(_Glow(paint_layer, at, new Vector2(96, 96) * sz, new Color(col, 0.5)), 0.5, 1.5 + 0.3 * i, 0.7 * i, 0.4));
                _pulses.Append(GArray.Of(_Glow(paint_layer, at, new Vector2(24, 24) * sz, new Color(0.9, 0.97, 1.0, 0.75)), 0.75, 1.5 + 0.3 * i, 0.7 * i, 0.25));
                var sp = _Particles(at + new Vector2(0, -6), 9, 1.9, GArray.Of(new Color(col, 0.0), new Color(0.85, 0.97, 1.0, 0.9), new Color(col, 0.5),
                    new Color(col, 0.0)));
                sp.EmissionShape = CPUParticles2D.EMISSION_SHAPE_SPHERE;
                sp.EmissionSphereRadius = 14.0 * sz;
                sp.Direction = new Vector2(0, -1);
                sp.Spread = 30.0;
                sp.Gravity = new Vector2(0, -8);
                sp.InitialVelocityMin = 10.0;
                sp.InitialVelocityMax = 24.0;
                sp.ScaleAmountMin = 0.15;
                sp.ScaleAmountMax = 0.35;
                wisps.Append(sp);
            }
        }

        // ---------------- layout ----------------
        public double inset_left = 0.0;                    // 0.31.216: the app's tab rail (and the notch) on the left: the camp centres on the rest

        public void Place(double play_top)
        {
            // 0.31.216 (landscape): the picture covering the screen, centred on the screen area beside the tab rail, standing so
            // the heroes' feet are just over play_top (Home's chests) -- but never leaving a gap at an edge. (Portrait until then:
            // as wide as the screen, the feet just over PLAY.)
            double w = Size.x;
            double h = Size.y;
            if (w <= 0.0 || h <= 0.0)
                return;
            var cx = inset_left + (w - inset_left) * 0.5;
            k = GD.Maxf(w / PAINT.x, h / PAINT.y);
            k = GD.Maxf(k, GD.Minf(k * 1.05, 2.0 * cx / PAINT.x));   // (a wide phone: a touch bigger, so the fire can move over toward cx)
            origin = new Vector2(GD.Clampf(cx - PAINT.x * k * 0.5, w - PAINT.x * k, 0.0),
                GD.Clampf(play_top + FEET_OVER - FEET_Y * k, h - PAINT.y * k, 0.0));
            paint_layer.Position = origin;
            paint_layer.Scale = new Vector2(k, k);
        }

        public double PaintingBottom()
        {
            return origin.y + PAINT.y * k;
        }

        public Vector2 ToScreen(Vector2 p)
        {
            return origin + p * k;
        }

        // (the war room's: Home's heroes in their looks, the live war on the table -- the camp is painted)
        public void SetLooks(GDict _looks)
        {
        }

        public void PaintWar(GDict _war)
        {
        }

        // ---------------- alive ----------------
        protected override void _Process(double delta)
        {
            if (!IsVisibleInTree() || calm)
                return;
            _clock += delta;
            var t = _clock;
            // the fire: the tongues sway and leap; the heart and the halo breathe with them; its light on the painting too
            flick = 0.55 * GD.Sin(t * 7.3) + 0.3 * GD.Sin(t * 13.1 + 1.3) + 0.15 * GD.Sin(t * 2.1 + 0.4);
            foreach (var tg in _tongues)
            {
                TextureRect tr = tg[0].As<TextureRect>();
                double ph = (double)tg[1];
                var f = 0.5 + 0.25 * GD.Sin(t * 8.7 + ph) + 0.17 * GD.Sin(t * 14.9 + ph * 1.7) + 0.08 * GD.Sin(t * 3.1 + ph * 0.6);
                tr.Scale = new Vector2(0.85 + 0.2 * (1.0 - f), 0.72 + 0.5 * f);
                tr.Rotation = 0.12 * GD.Sin(t * 2.3 + ph) + 0.06 * GD.Sin(t * 6.7 + ph);
                { var mc = tr.Modulate; mc.a = (float)(0.6 + 0.3 * f); tr.Modulate = mc; }
            }
            { var mc = _fire_heart.Modulate; mc.a = (float)(0.62 + 0.18 * flick); _fire_heart.Modulate = mc; }
            _fire_heart.Scale = Vector2.ONE * (0.95 + 0.08 * flick);
            { var mc = _fire_halo.Modulate; mc.a = (float)(0.3 + 0.08 * flick); _fire_halo.Modulate = mc; }
            _fire_halo.Scale = Vector2.ONE * (0.97 + 0.05 * flick);
            var m = art.Material as ShaderMaterial;
            m.SetShaderParameter("clock", t);
            m.SetShaderParameter("fire_flick", flick);
            foreach (var l in _lamps)
            {
                double ph = (double)l["phase"];
                var fl = 0.5 + 0.22 * GD.Sin(t * 9.3 + ph) + 0.16 * GD.Sin(t * 15.1 + ph * 1.7) + 0.12 * GD.Sin(t * 3.7 + ph * 0.6);
                TextureRect core = l["core"].As<TextureRect>();
                TextureRect halo = l["halo"].As<TextureRect>();
                core.Scale = new Vector2(0.92 + 0.1 * fl, 0.84 + 0.3 * fl);
                core.Rotation = 0.09 * GD.Sin(t * 2.3 + ph) + 0.05 * GD.Sin(t * 6.1 + ph);
                { var mc = halo.Modulate; mc.a = (float)((double)l["a"] * (0.7 + 0.55 * fl)); halo.Modulate = mc; }
                halo.Scale = Vector2.ONE * (0.92 + 0.14 * fl);
            }
            foreach (var p in _pulses)
            {
                TextureRect g = p[0].As<TextureRect>();
                var v = 0.5 + 0.5 * GD.Sin(t * (double)p[2] * GD.TAU * 0.5 + (double)p[3]);
                { var mc = g.Modulate; mc.a = (float)((double)p[1] * (1.0 - (double)p[4] + (double)p[4] * v)); g.Modulate = mc; }
                g.Scale = Vector2.ONE * (0.94 + 0.12 * v);
            }
            foreach (var wd in _windows)
            {
                TextureRect g = wd[0].As<TextureRect>();
                wd.A[2] = (double)wd[2] - delta;
                if ((double)wd[2] <= 0.0)                  // someone passes the window: it dims a moment
                {
                    wd.A[3] = GD.RandfRange(0.6, 1.6);
                    wd.A[2] = GD.RandfRange(6.0, 18.0);
                }
                var dim = 0.0;
                if ((double)wd[3] > 0.0)
                {
                    wd.A[3] = (double)wd[3] - delta;
                    dim = 0.7;
                }
                { var mc = g.Modulate; mc.a = (float)GD.Lerpf(g.Modulate.a, (double)wd[1] * (1.0 - dim) * (0.9 + 0.1 * GD.Sin(t * 3.0 + g.Position.x)), GD.Minf(1.0, delta * 6.0)); g.Modulate = mc; }
            }
            foreach (var s in _stars)
            {
                TextureRect st = s[0].As<TextureRect>();
                { var mc = st.Modulate; mc.a = (float)(0.8 * GD.Pow(GD.Maxf(0.0, GD.Sin(t * (double)s[1] + (double)s[2])), 3.0)); st.Modulate = mc; }
            }
        }
    }
}
