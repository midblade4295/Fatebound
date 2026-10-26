// Ported from godot/scripts/app/title_screen.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Color = Fatebound.GUI.Col;
using UI = Fatebound.Game.Ui;
using UI2 = Fatebound.Game.Ui2;
using Diag = Fatebound.Game.SiegeDiag;

namespace Fatebound.Game
{
    // 0.31.139 (Kevin: "remove the fatebound title and instead put that in a startup screen and any loading screens. Give
    // the starting title screen a little jingle tune and have title animate in there like slamming onto the wall or
    // something"): the screen the app opens on. A castle wall at dusk (bg_title_wall.webp; tools/build_title_art.py), its
    // two torches flickering and throwing up embers; the title (title_logo.gd) flies in from the viewer and slams onto the
    // wall: a thud (titleSlam), a flash, the screen shakes, dust bursts out from behind it and rubble drops, cracks run out
    // into the stones, the title squashes and settles -- its flags whip about and its rift flares (0.31.193; until then
    // the King swung from his rope). Then TAP TO START: a tap
    // anywhere lifts the screen off Home (a tap during the flight lands it first). Reduce motion: the title fades in and
    // holds still, no shake.
    //
    // 0.31.141 (Kevin: "Make the intro splash screen more exciting and also load faster"):
    //  - FASTER: the start-up screen (content_loader.gd) puts this up as soon as the content packs are mounted and loads
    //    the game (Main.tscn) on a thread behind it, instead of after it -- so the title is on screen ~2 s sooner and the
    //    show plays while the game loads. The game is put in behind it once the slam has settled (can_swap), and says
    //    when Home is built and drawn (home_ready): TAP TO START shows then (LOADING... until; a tap meanwhile is kept and
    //    lifts the screen the moment Home is ready). A long frame slows the show down rather than skipping it.
    //  - MORE EXCITING: the wall comes up from the boot splash as the edges darken; the torches flare alight one after the
    //    other (whoosh of fire); the title launches with a whoosh, trailing afterimages; it hits on the jingle's first
    //    note: a shockwave ring, gold sparks, a punch-in zoom, the torches flaring, the title's flags whipping (0.31.193); then
    //    light rays turn slowly behind the title, a gold glint sweeps across the letters every few seconds, and embers
    //    drift up the screen. The game's own sounds (tm_fireball1, tm_sword_swing2, tm_crumble1), no new files.
    //    Reduce motion: no flight, shake, zoom, rays turning, glint or drifting embers.
    // 0.31.142 (Kevin: "Getting freezes during it now"; his log: the game going in behind the title stopped the screen
    // for 6.4 s mid-show -- Home's build 1.9 s, then its first frame 4.5 s): the show now waits for the game. The wall and
    // its torches open (the PRE-ROLL) while the game loads on its thread; once loaded, the screen settles to a still
    // LOADING... (the drifting embers fade, the torches hold steady: hold_for_game, SETTLE) and the game goes in behind it
    // (can_swap), so the pause in drawing is a still loading screen, not a show stopping mid-swing; when Home is built and
    // drawn (home_ready) the embers come back and the SHOW plays -- the flight, the slam, TAP TO START just after. A tap
    // while loading is kept: in the moment Home is ready, straight in (no show). (And Home's first frame is shorter:
    // war_room.gd / chest_row.gd no longer use MSAA.)
    public class TitleScreen : Control
    {
        public static readonly Shader RaysShader = ResourceLoader.Load<Shader>("res://scripts/app/title_rays.gdshader");
        public static readonly Shader GlintShader = ResourceLoader.Load<Shader>("res://scripts/app/title_glint.gdshader");

        public const string GROUP = "title_screen";
        public const string ART = "res://assets/ui/v2/bg_title_wall.webp";
        public const string SPLASH = "res://assets/branding/splash.png";        // (the base build's copy of the wall, without the ui pack)
        public const string JINGLE = "res://assets/music/title_jingle.ogg";
        public static readonly GDict SOUNDS = new GDict                          // name -> [file, loudness as the game's ui cues (x 0.2)]
        {
            { "ignite", GArray.Of("res://assets/sounds/tm_fireball1.wav", 0.6) },
            { "whoosh", GArray.Of("res://assets/sounds/tm_sword_swing2.wav", 1.3) },
            { "slam", GArray.Of("res://assets/sounds/titleSlam.wav", 1.7) },
            { "crumble", GArray.Of("res://assets/sounds/tm_crumble1.wav", 0.5) },
        };
        public static readonly Vector2 PAINT = new Vector2(1152.0, 2560.0);
        public static readonly GArray TORCHES = GArray.Of(new Vector2(121, 832), new Vector2(1028, 830));   // the painted torches' flames
        public const double LOGO_AT = 0.3;                   // the title's middle, this far down the screen (0.22 in portrait, over the torches)
        public const double TORCH_Y = 980.0;                 // 0.31.216: the torches' row down the painting -- at the middle of the landscape screen
        public const double LOGO_W = 400.0;                  // at most this wide (screen px; 330 in portrait)
        public static readonly GArray IGNITE = GArray.Of(0.05, 0.16);           // the torches flare alight
        public const double START = 0.22;                    // the title sets off no sooner than this (and not before the game is ready)...
        public const double FLIGHT = 0.36;                   // ...and hits the wall this long after
        public const double JINGLE_LEAD = 0.13;              // the jingle's first note comes this long into it: started so it lands on the hit
        public const double SETTLE = 0.25;                   // the screen settles this long before the game goes in behind it
        public const double LOADING_AT = 0.9;                // LOADING... in the pre-roll, if the game still isn't ready
        public const double TAP_AFTER = 0.6;                 // TAP TO START, this long after the hit
        public const double GLINT_AT = 0.8;                  // the first glint, after the hit...
        public const double GLINT_EVERY = 4.5;               // ...then every this often
        public const double GLINT_TIME = 0.75;
        public const int GHOSTS = 2;                      // afterimages trailing the flight
        public const double KICK_DEG = 32.0;                 // the hit's kick to the title (title_logo.kick: its flags whip, its rift flares)
        public const double MAX_STEP = 1.0 / 20.0;           // a longer frame slows the show instead of skipping it

        public event Action Done;
        public event Action Shown;                           // the show is over (TAP TO START is up): the game may get on with its loading
        public event Action Lifting;                         // the screen starts to fade off what's behind it

        public SiegeApp app = null;
        public bool calm = false;
        public bool home_is_ready = false;             // the game's Home is built and drawn behind: TAP TO START
        public bool want_leave = false;                // tapped while Home was still loading: lift as soon as it's ready
        public bool holding = false;                   // settled, still, for the game going in behind (hold_for_game)
        public double _hold_t = 0.0;
        public double _launch = -1.0;                    // when the flight set off (-1: not yet)
        public bool _shown = false;
        public CPUParticles2D _drift;
        public ProgressBar bar;                   // 0.31.142: the LOADING bar (set_progress)
        public double _progress_to = 0.0;
        public double k = 1.0;
        public Vector2 origin = Vector2.ZERO;
        public Control paint;                     // the wall and its torches, in the painting's pixels
        public TextureRect wall;
        public Control stage;                     // what shakes and punches in (the wall, the title, the dust)
        public TextureRect vignette;
        public TextureRect rays;
        public ShaderMaterial rays_mat;
        public ShaderMaterial glint_mat;
        public TitleLogo logo;
        public GArray ghosts = new GArray();
        public Cracks cracks;
        public Ring ring;
        public TextureRect flash;
        public Label tap;
        public AudioStreamPlayer jingle;
        public double t = 0.0;
        public bool landed = false;
        public bool leaving = false;
        public double shake = 0.0;
        public double punch = 0.0;
        public double _land_t = 0.0;
        public GArray _flames = new GArray();
        public GArray _bursts = new GArray();                // CPUParticles2D fired at the hit: dust, rubble, sparks
        public GDict _players = new GDict();
        public GDict _levels = new GDict();
        public GArray _lit = GArray.Of(false, false);
        public bool _whooshed = false;
        public bool _crumbled = false;
        public bool _first = true;

        public class Cracks : Node2D
        {
            // cracks running out into the stones from behind the title, drawn as they grow
            public List<List<Vector2>> lines = new List<List<Vector2>>();              // PackedVector2Array each
            public double grow = 0.0;

            public void Make(Rect2 rect, int seed)
            {
                var rng = new Rng();
                rng.Seed = unchecked((ulong)seed);
                lines.Clear();
                for (int i = 0; i < 9; i++)
                {
                    var side = i % 4;
                    var p = Vector2.ZERO;
                    var dir = Vector2.ZERO;
                    switch (side)
                    {
                        case 0:
                            p = new Vector2(rng.RandfRange(rect.position.x + 20.0, rect.End.x - 20.0), rect.position.y + 12.0);
                            dir = new Vector2(rng.RandfRange(-0.6, 0.6), -1.0);
                            break;
                        case 1:
                            p = new Vector2(rect.End.x - 14.0, rng.RandfRange(rect.position.y + 20.0, rect.End.y - 20.0));
                            dir = new Vector2(1.0, rng.RandfRange(-0.7, 0.7));
                            break;
                        case 2:
                            p = new Vector2(rng.RandfRange(rect.position.x + 20.0, rect.End.x - 20.0), rect.End.y - 14.0);
                            dir = new Vector2(rng.RandfRange(-0.6, 0.6), 1.0);
                            break;
                        default:
                            p = new Vector2(rect.position.x + 14.0, rng.RandfRange(rect.position.y + 20.0, rect.End.y - 20.0));
                            dir = new Vector2(-1.0, rng.RandfRange(-0.7, 0.7));
                            break;
                    }
                    var pts = new List<Vector2> { p };
                    double len = rng.RandfRange(70.0, 170.0);
                    var step = len / 6.0;
                    for (int s = 0; s < 6; s++)
                    {
                        dir = dir.Normalized().Rotated(rng.RandfRange(-0.55, 0.55));
                        p += dir * step;
                        pts.Add(p);
                    }
                    lines.Add(pts);
                }
            }

            protected override void _Draw()
            {
                foreach (var pts in lines)
                {
                    var n = GD.Int(Math.Ceiling((double)(pts.Count - 1) * grow)) + 1;
                    if (n < 2)
                        continue;
                    List<Vector2> part = pts.GetRange(0, Math.Min(n, pts.Count));
                    DrawPolyline(part, new Color(0.95, 0.78, 0.55, 0.3), 12.0, true);     // (the lit lip of the crack)
                    DrawPolyline(part, new Color(0.07, 0.04, 0.03, 0.9), 6.5, true);
                }
            }
        }

        public class Ring : Node2D
        {
            // 0.31.141: the shockwave of the hit, a bright ring racing out from the title and fading
            public double p = -1.0;                      // 0..1 while it spreads
            public double r0 = 120.0;
            public double r1 = 900.0;

            protected override void _Draw()
            {
                if (p < 0.0 || p >= 1.0)
                    return;
                var e = 1.0 - GD.Pow(1.0 - p, 3.0);
                var r = GD.Lerpf(r0, r1, e);
                var a = (1.0 - p) * 0.8;
                DrawArc(Vector2.ZERO, r, 0.0, GD.TAU, 96, new Color(1.0, 0.88, 0.6, a), GD.Lerpf(70.0, 8.0, p), true);
                DrawArc(Vector2.ZERO, r * 0.86, 0.0, GD.TAU, 96, new Color(1.0, 0.62, 0.3, a * 0.5), GD.Lerpf(40.0, 4.0, p), true);
            }
        }

        public TitleScreen(SiegeApp a = null, bool reduce_motion = false)
        {
            app = a;
            calm = reduce_motion;
        }

        public static GDict SavedSettings()
        {
            // the player's settings before the game has read its profile (the boot screen puts this up first): the volumes and
            // Reduce Motion, straight from the saved profile
            var path = "user://siege_profile.json";
            if (FileAccess.FileExists(path))
            {
                Var v = JSON.ParseString(FileAccess.GetFileAsString(path));
                if (v.IsDict && v.D.Get("settings").IsDict)
                    return v["settings"].D;
            }
            return new GDict();
        }

        protected override void _Ready()
        {
            AddToGroup(GROUP);
            SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            MouseFilter = Control.MOUSE_FILTER_STOP;
            _levels = _ReadLevels();
            var under = new ColorRect();
            under.Color = Color.FromCode("#120b10");
            under.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            under.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(under);
            stage = new Control();
            stage.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(stage);
            paint = new Control();
            paint.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            paint.Size = PAINT;
            stage.AddChild(paint);
            wall = new TextureRect();
            Texture2D wt = UI2.Tex(ART);
            wall.Texture = wt != null ? wt : ResourceLoader.Load<Texture2D>(SPLASH);
            wall.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            wall.StretchMode = TextureRect.STRETCH_SCALE;
            wall.Size = PAINT;
            wall.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            paint.AddChild(wall);
            foreach (var at in TORCHES)
                _Torch(at.V2);
            vignette = _Vignette();
            paint.AddChild(vignette);
            rays = new TextureRect();
            rays.Texture = _White();
            rays.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            rays.StretchMode = TextureRect.STRETCH_SCALE;
            rays.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            rays_mat = new ShaderMaterial();
            rays_mat.Shader = RaysShader;
            rays_mat.SetShaderParameter("power", 0.0);          // (drawn from the first frame, so it's compiled before the show)
            rays.Material = rays_mat;
            paint.AddChild(rays);
            cracks = new Cracks();
            paint.AddChild(cracks);
            flash = _Glow(paint, Vector2.ZERO, new Vector2(900, 600), new Color(1.0, 0.93, 0.75, 0.0));
            _bursts = GArray.Of(_Dust(), _Rubble(), _Sparks());
            paint.AddChild(_bursts[0].As<Node>());                  // (the dust puffs out from behind the title...)
            if (!calm)
            {
                for (int i = 0; i < GHOSTS; i++)
                {
                    var g = new TitleLogo(true);
                    { var mc = g.Modulate; mc.a = 0.0f; g.Modulate = mc; }
                    paint.AddChild(g);
                    ghosts.Append(g);
                }
            }
            logo = new TitleLogo(calm);
            { var mc = logo.Modulate; mc.a = 0.01f; logo.Modulate = mc; }                       // (drawn, so its glint is compiled before the show; too faint to see)
            paint.AddChild(logo);
            glint_mat = new ShaderMaterial();
            glint_mat.Shader = GlintShader;
            glint_mat.SetShaderParameter("sweep", -1.0);
            logo.SetShine(glint_mat);
            paint.AddChild(_bursts[1].As<Node>());                  // (...the rubble drops in front of it...)
            paint.AddChild(_bursts[2].As<Node>());                  // (...and the sparks fly)
            ring = new Ring();
            var add = new CanvasItemMaterial();
            add.BlendMode = CanvasBlendMode.Add;
            ring.Material = add;
            paint.AddChild(ring);
            if (!calm)
            {
                _drift = _DriftEmbers();
                paint.AddChild(_drift);
            }
            tap = UI2.Text(this, "TAP TO START", 30, UI2.GOLD, Color.FromCode("#2a1205"), 9);
            tap.HorizontalAlignment = HorizontalAlignment.Center;
            { var mc = tap.Modulate; mc.a = 0.0f; tap.Modulate = mc; }
            tap.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            bar = _LoadingBar();
            AddChild(bar);
            var ver = UI.Label(this, "v" + Diag.BUILD.Replace("-fatebound", ""), 11, new Color(1, 1, 1, 0.45), UI.HEAVY_FONT);
            ver.Name = "Version";
            ver.HorizontalAlignment = HorizontalAlignment.Center;
            ver.SetAnchorsAndOffsetsPreset(Control.PRESET_BOTTOM_WIDE);
            ver.OffsetTop = -30;
            ver.OffsetBottom = -10;
            ver.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            Resized += _Lay;
            _Lay();
            _PrepareSounds();
        }

        public void _Lay()
        {
            double w = Size.x;
            double h = Size.y;
            if (w <= 0.0 || h <= 0.0)
                return;
            stage.Size = Size;
            stage.PivotOffset = new Vector2(w * 0.5, h * LOGO_AT);    // (the punch-in zooms on the title)
            k = GD.Maxf(w / PAINT.x, h / PAINT.y);
            // 0.31.216 (landscape): the band of the wall with the torches and the banners' tails across the screen's middle (the
            // whole tall wall, centred, in portrait)
            origin = new Vector2((w - PAINT.x * k) * 0.5, GD.Clampf(h * 0.5 - TORCH_Y * k, h - PAINT.y * k, 0.0));
            paint.Position = origin;
            paint.Scale = new Vector2(k, k);
            var lw = GD.Minf(w - 36.0, LOGO_W) / k;
            var centre = new Vector2(PAINT.x * 0.5, (h * LOGO_AT - origin.y) / k);
            var all = GArray.Of(logo);
            all.AppendArray(ghosts);
            foreach (var l in all)
            {
                var c = l.As<Control>();
                c.Size = new Vector2(lw, lw * TitleLogo.Aspect());
                c.Position = centre - c.Size * 0.5;
                c.PivotOffset = c.Size * 0.5;
            }
            var r = new Rect2(logo.Position, logo.Size);
            cracks.Make(r.Grow(-lw * 0.04), 1139);
            cracks.QueueRedraw();
            flash.Size = logo.Size * new Vector2(1.5, 2.0);
            flash.PivotOffset = flash.Size * 0.5;
            flash.Position = centre - flash.Size * 0.5;
            rays.Size = new Vector2(lw * 2.1, lw * 2.1);
            rays.Position = centre - rays.Size * 0.5;
            ring.Position = centre;
            ring.r0 = lw * 0.35;
            ring.r1 = lw * 1.25;
            // the vignette covers what the screen shows of the painting
            vignette.Position = -origin / k;
            vignette.Size = Size / k;
            foreach (var b in _bursts)
            {
                var p = b.As<CPUParticles2D>();
                switch (GD.Str(p.Name))
                {
                    case "Dust":
                        p.Position = centre + new Vector2(0.0, logo.Size.y * 0.1);
                        p.EmissionRectExtents = new Vector2(logo.Size.x * 0.46, logo.Size.y * 0.36);
                        break;
                    case "Rubble":
                        p.Position = centre + new Vector2(0.0, logo.Size.y * 0.38);
                        p.EmissionRectExtents = new Vector2(logo.Size.x * 0.4, logo.Size.y * 0.08);
                        break;
                    default:
                        p.Position = centre;
                        p.EmissionRectExtents = new Vector2(logo.Size.x * 0.42, logo.Size.y * 0.3);
                        break;
                }
            }
            tap.Size = new Vector2(w, 44);
            tap.Position = new Vector2(0, h * 0.8);
            tap.PivotOffset = tap.Size * 0.5;
            bar.Size = new Vector2(GD.Minf(w * 0.56, 240.0), 12.0);
            bar.Position = new Vector2((w - bar.Size.x) * 0.5, h * 0.8 + 50.0);
        }

        // ---------------- the parts ----------------
        public ProgressBar _LoadingBar()
        {
            // 0.31.142: a gold bar under LOADING..., as the first-start download screen has (content_loader.gd)
            var b = new ProgressBar();
            b.ShowPercentage = false;
            b.MinValue = 0.0;
            b.MaxValue = 1.0;
            b.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            var back = new StyleBoxFlat();
            back.BgColor = new Color(0.03, 0.02, 0.05, 0.75);
            back.SetCornerRadiusAll(6);
            back.BorderColor = new Color(1.0, 0.85, 0.5, 0.35);
            back.SetBorderWidthAll(1);
            var fill = new StyleBoxFlat();
            fill.BgColor = UI2.GOLD;
            fill.SetCornerRadiusAll(6);
            b.AddThemeStyleboxOverride("background", back);
            b.AddThemeStyleboxOverride("fill", fill);
            { var mc = b.Modulate; mc.a = 0.0f; b.Modulate = mc; }
            return b;
        }

        public void SetProgress(double f)
        {
            // how far the game behind has got (the boot screen and the game say, 0..1); the bar never goes back
            _progress_to = GD.Maxf(_progress_to, GD.Clampf(f, 0.0, 1.0));
        }

        public static Texture2D _White()
        {
            var img = Image.Create(4, 4, false, ImageFormat.RGBA8);
            img.Fill(Color.WHITE);
            return ImageTexture.CreateFromImage(img);
        }

        public TextureRect _Vignette()
        {
            // the screen's edges darkening as the show starts (it opens as the boot splash left it)
            var g = new Gradient();
            g.SetOffsets(new double[] { 0.0, 0.5, 1.0 });
            g.SetColors(new Color[] { new Color(0, 0, 0, 0), new Color(0, 0, 0, 0.05), new Color(0.02, 0.0, 0.02, 0.8) });
            var gt = new GradientTexture2D();
            gt.Gradient = g;
            gt.Fill = GradientTexture2D.FillEnum.Radial;
            gt.FillFrom = new Vector2(0.5, 0.42);
            gt.FillTo = new Vector2(1.08, 1.0);
            gt.Width = 128;
            gt.Height = 256;
            var v = new TextureRect();
            v.Texture = gt;
            v.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            v.StretchMode = TextureRect.STRETCH_SCALE;
            v.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            { var mc = v.Modulate; mc.a = calm ? 1.0f : 0.0f; v.Modulate = mc; }
            return v;
        }

        public TextureRect _Glow(Control parent, Vector2 centre, Vector2 sz, Color col, bool add = true)
        {
            var g = new TextureRect();
            g.Texture = UI2.GlowTex();
            g.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            g.StretchMode = TextureRect.STRETCH_SCALE;
            g.Size = sz;
            g.PivotOffset = sz * 0.5;
            g.Position = centre - sz * 0.5;
            g.Modulate = col;
            g.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            if (add)
            {
                var m = new CanvasItemMaterial();
                m.BlendMode = CanvasBlendMode.Add;
                g.Material = m;
            }
            parent.AddChild(g);
            return g;
        }

        public CPUParticles2D _Additive(CPUParticles2D p)
        {
            var m = new CanvasItemMaterial();
            m.BlendMode = CanvasBlendMode.Add;
            p.Material = m;
            return p;
        }

        public void _Torch(Vector2 at)
        {
            var pool = _Glow(paint, at + new Vector2(0, 40), new Vector2(560, 640), new Color(1.0, 0.5, 0.18, 0.16));
            var halo = _Glow(paint, at, new Vector2(190, 210), new Color(1.0, 0.6, 0.25, 0.45));
            var core = _Glow(paint, at + new Vector2(0, -6), new Vector2(46, 92), new Color(1.0, 0.82, 0.45, 0.85));
            core.PivotOffset = new Vector2(23, 80);
            var f = new GDict { { "pool", pool }, { "halo", halo }, { "core", core }, { "phase", GD.Randf() * GD.TAU }, { "boost", 0.0 }, { "burst", Var.Nil }, { "embers", Var.Nil } };
            _flames.Append(f);
            if (calm)
                return;
            var embers = new CPUParticles2D();
            embers.Texture = UI2.GlowTex();
            embers.Amount = 10;
            embers.Lifetime = 2.6;
            embers.Preprocess = 2.6;
            embers.Position = at + new Vector2(0, -30);
            embers.EmissionShape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE;
            embers.EmissionRectExtents = new Vector2(14, 6);
            embers.Direction = new Vector2(0, -1);
            embers.Spread = 22.0;
            embers.Gravity = new Vector2(0, -12);
            embers.InitialVelocityMin = 40.0;
            embers.InitialVelocityMax = 90.0;
            embers.ScaleAmountMin = 0.08;
            embers.ScaleAmountMax = 0.16;
            embers.ColorRamp = _FireRamp();
            paint.AddChild(_Additive(embers));
            f["embers"] = embers;
            // 0.31.141: the flare as it catches -- a burst of sparks up out of the torch
            var burst = new CPUParticles2D();
            burst.Texture = UI2.GlowTex();
            burst.OneShot = true;
            burst.Emitting = false;
            burst.Explosiveness = 0.9;
            burst.Amount = 16;
            burst.Lifetime = 0.9;
            burst.Position = at + new Vector2(0, -20);
            burst.EmissionShape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE;
            burst.EmissionRectExtents = new Vector2(18, 10);
            burst.Direction = new Vector2(0, -1);
            burst.Spread = 45.0;
            burst.Gravity = new Vector2(0, 220);
            burst.InitialVelocityMin = 160.0;
            burst.InitialVelocityMax = 420.0;
            burst.ScaleAmountMin = 0.1;
            burst.ScaleAmountMax = 0.24;
            burst.ColorRamp = _FireRamp();
            paint.AddChild(_Additive(burst));
            f["burst"] = burst;
        }

        public static Gradient _FireRamp()
        {
            var ramp = new Gradient();
            ramp.SetColor(0, new Color(1.0, 0.8, 0.4, 1.0));
            ramp.SetColor(1, new Color(1.0, 0.35, 0.1, 0.0));
            return ramp;
        }

        public CPUParticles2D _Dust()
        {
            // the dust knocked out of the wall: puffs bursting out round the title's edges, spreading and fading
            var d = new CPUParticles2D();
            d.Name = "Dust";
            d.Texture = UI2.GlowTex();
            d.OneShot = true;
            d.Emitting = false;
            d.Explosiveness = 0.92;
            d.Amount = 40;
            d.Lifetime = 1.3;
            d.EmissionShape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE;
            d.Direction = new Vector2(0, 0);
            d.Spread = 180.0;
            d.Gravity = new Vector2(0, 60);
            d.InitialVelocityMin = 120.0;
            d.InitialVelocityMax = 380.0;
            d.DampingMin = 220.0;
            d.DampingMax = 320.0;
            d.ScaleAmountMin = 1.2;
            d.ScaleAmountMax = 2.6;
            var curve = new Curve();
            curve.AddPoint(new Vector2(0.0, 0.5));
            curve.AddPoint(new Vector2(1.0, 1.6));
            d.ScaleAmountCurve = curve;
            var ramp = new Gradient();
            ramp.SetColor(0, new Color(0.86, 0.78, 0.66, 0.5));
            ramp.SetColor(1, new Color(0.6, 0.52, 0.45, 0.0));
            d.ColorRamp = ramp;
            return d;
        }

        public CPUParticles2D _Rubble()
        {
            // chips of stone dropping from under the title
            var r = new CPUParticles2D();
            r.Name = "Rubble";
            var img = Image.Create(6, 6, false, ImageFormat.RGBA8);
            img.Fill(new Color(0.33, 0.27, 0.24));
            r.Texture = ImageTexture.CreateFromImage(img);
            r.OneShot = true;
            r.Emitting = false;
            r.Explosiveness = 0.85;
            r.Amount = 18;
            r.Lifetime = 1.4;
            r.EmissionShape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE;
            r.Direction = new Vector2(0, 1);
            r.Spread = 70.0;
            r.Gravity = new Vector2(0, 1500);
            r.InitialVelocityMin = 60.0;
            r.InitialVelocityMax = 260.0;
            r.AngularVelocityMin = -400.0;
            r.AngularVelocityMax = 400.0;
            r.ScaleAmountMin = 0.8;
            r.ScaleAmountMax = 2.2;
            return r;
        }

        public CPUParticles2D _Sparks()
        {
            // 0.31.141: gold sparks flying out from the hit and falling
            var s = new CPUParticles2D();
            s.Name = "Sparks";
            s.Texture = UI2.GlowTex();
            s.OneShot = true;
            s.Emitting = false;
            s.Explosiveness = 0.95;
            s.Amount = 44;
            s.Lifetime = 1.1;
            s.EmissionShape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE;
            s.Direction = new Vector2(0, -0.3);
            s.Spread = 180.0;
            s.Gravity = new Vector2(0, 1100);
            s.InitialVelocityMin = 450.0;
            s.InitialVelocityMax = 1250.0;
            s.DampingMin = 300.0;
            s.DampingMax = 500.0;
            s.ScaleAmountMin = 0.12;
            s.ScaleAmountMax = 0.3;
            var ramp = new Gradient();
            ramp.SetOffsets(new double[] { 0.0, 0.5, 1.0 });
            ramp.SetColors(new Color[] { new Color(1.0, 0.97, 0.8, 1.0), new Color(1.0, 0.75, 0.3, 0.9), new Color(1.0, 0.4, 0.1, 0.0) });
            s.ColorRamp = ramp;
            return _Additive(s);
        }

        public CPUParticles2D _DriftEmbers()
        {
            // 0.31.141: embers drifting up the screen the whole time
            var e = new CPUParticles2D();
            e.Texture = UI2.GlowTex();
            e.Amount = 26;
            e.Lifetime = 9.0;
            e.Preprocess = 9.0;
            e.Position = new Vector2(PAINT.x * 0.5, PAINT.y * 0.98);
            e.EmissionShape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE;
            e.EmissionRectExtents = new Vector2(PAINT.x * 0.55, 60);
            e.Direction = new Vector2(0.15, -1);
            e.Spread = 18.0;
            e.Gravity = new Vector2(14, -10);
            e.InitialVelocityMin = 160.0;
            e.InitialVelocityMax = 300.0;
            e.ScaleAmountMin = 0.07;
            e.ScaleAmountMax = 0.17;
            e.HueVariationMin = -0.03;
            e.HueVariationMax = 0.03;
            var ramp = new Gradient();
            ramp.SetOffsets(new double[] { 0.0, 0.15, 0.8, 1.0 });
            ramp.SetColors(new Color[] { new Color(1.0, 0.7, 0.3, 0.0), new Color(1.0, 0.75, 0.35, 0.9), new Color(1.0, 0.45, 0.15, 0.6), new Color(1.0, 0.3, 0.1, 0.0) });
            e.ColorRamp = ramp;
            return _Additive(e);
        }

        // ---------------- sound ----------------
        public GDict _ReadLevels()
        {
            // the volumes: the game's when it's up, else the saved settings (the boot screen puts this up before the game)
            if (app != null && app.audio != null)
            {
                var au = app.audio;
                GDict lv = au.levels != null ? au.levels : new GDict();
                return new GDict { { "master", (double)lv.Get("master", 1.0) }, { "music", (double)lv.Get("music", 1.0) }, { "ui", (double)lv.Get("ui", 1.0) },
                    { "muted", au.muted } };
            }
            var st = SavedSettings();
            var cfg = new ConfigFile();
            var muted = cfg.Load("user://native_audio.cfg") == GD.OK && (bool)cfg.GetValue("audio", "muted", false);
            return new GDict { { "master", GD.Clampf((double)st.Get("master", 1.0), 0.0, 1.0) }, { "music", GD.Clampf((double)st.Get("music", 1.0), 0.0, 1.0) },
                { "ui", GD.Clampf((double)st.Get("sfx", 1.0), 0.0, 1.0) }, { "muted", muted } };
        }

        public void _PrepareSounds()
        {
            if ((bool)_levels.Get("muted", false))
                return;
            var music = 0.7 * (double)_levels["master"] * (double)_levels["music"];
            if (music > 0.001 && ResourceLoader.Exists(JINGLE))
            {
                jingle = new AudioStreamPlayer();
                jingle.Stream = ResourceLoader.Load<AudioStream>(JINGLE);
                jingle.VolumeDb = GD.LinearToDb(music);
                AddChild(jingle);
            }
            foreach (var n in SOUNDS)
            {
                var gain = GD.Minf(1.0, 0.2 * (double)_levels["master"] * (double)_levels["ui"] * (double)SOUNDS[n][1]);
                if (gain <= 0.001 || !ResourceLoader.Exists(GD.Str(SOUNDS[n][0])))
                    continue;
                var p = new AudioStreamPlayer();
                p.Stream = ResourceLoader.Load<AudioStream>(GD.Str(SOUNDS[n][0]));
                p.VolumeDb = GD.LinearToDb(gain);
                AddChild(p);
                _players[n] = p;
            }
        }

        public void _Sound(string n)
        {
            AudioStreamPlayer p = _players.Get(n).As<AudioStreamPlayer>();
            if (p != null)
                p.Play();
        }

        public void _Mark(string s)
        {
            if (!IsInsideTree())
                return;
            var g = GetNodeOrNull("/root/BootGuard");
            if (g != null && g is BootGuard)
                ((BootGuard)g).Mark(s);
        }

        // ---------------- the show ----------------
        public void Land()
        {
            // the hit: the thud, a flash, the shockwave, sparks, dust and rubble, the cracks, the shake, the title's flags whipping
            if (landed)
                return;
            landed = true;
            _land_t = t;
            _Mark("title: slam");
            { var mc = logo.Modulate; mc.a = 1.0f; logo.Modulate = mc; }
            logo.Scale = Vector2.ONE;
            logo.Rotation = 0.0;
            foreach (var g in ghosts)
            {
                var gc = g.As<Control>();
                var mc = gc.Modulate; mc.a = 0.0f; gc.Modulate = mc;
            }
            if (jingle != null && !jingle.Playing)
                jingle.Play(GD.Maxf(0.0, JINGLE_LEAD - 0.02));       // (a tap that lands it early: the first note now)
            _Sound("slam");
            if (calm)
            {
                cracks.grow = 1.0;
                cracks.QueueRedraw();
                return;
            }
            shake = 1.0;
            punch = 1.0;
            { var mc = flash.Modulate; mc.a = 0.9f; flash.Modulate = mc; }
            ring.p = 0.0;
            logo.Kick(KICK_DEG);
            foreach (var f in _flames)
                f.D["boost"] = GD.Maxf((double)f["boost"], 0.7);                  // (the torches gust up with the blow)
            foreach (var b in _bursts)
            {
                b.As<CPUParticles2D>().Restart();
                b.As<CPUParticles2D>().Emitting = true;
            }
        }

        public void HomeReady()
        {
            // the game behind is built and drawn: the show (or, tapped already, straight in)
            if (home_is_ready)
                return;
            home_is_ready = true;
            holding = false;
            SetProgress(1.0);
            _Mark("title: the game is ready behind it");
            if (want_leave)
                Leave();
        }

        public void HoldForGame()
        {
            // 0.31.142: the game has loaded and is about to go in behind (building Home and drawing it the first time stop the
            // drawing for a moment): settle to a still LOADING... first
            if (holding || home_is_ready)
                return;
            holding = true;
            _hold_t = t;
            SetProgress(0.6);
        }

        public bool CanSwap()
        {
            // the boot screen may now put the game in behind
            return holding && (t - _hold_t >= SETTLE || want_leave);
        }

        public void Leave()
        {
            if (leaving)
                return;
            leaving = true;
            MouseFilter = Control.MOUSE_FILTER_IGNORE;
            Lifting?.Invoke();
            if (app != null)
                app.Sfx("tap");
            var tw = CreateTween();
            tw.TweenProperty(this, "modulate:a", 0.0, 0.45).SetTrans(Tween.TRANS_SINE);
            if (jingle != null && jingle.Playing)
                tw.Parallel().TweenProperty(jingle, "volume_db", jingle.VolumeDb - 24.0, 0.45);
            tw.TweenCallback(() =>
            {
                Done?.Invoke();
                QueueFree();
            });
        }

        protected override void _GuiInput(InputEvent ev)
        {
            if (ev is InputEventMouse && (ev as InputEventMouse).Device == InputEvent.DEVICE_ID_EMULATION)
                return;                                   // (a phone's touch arrives as a touch; skip its mouse copy)
            var press = (ev is InputEventScreenTouch && (ev as InputEventScreenTouch).Pressed)
                || (ev is InputEventMouseButton && (ev as InputEventMouseButton).Pressed && (ev as InputEventMouseButton).ButtonIndex == MouseButton.Left);
            if (!press)
                return;
            AcceptEvent();
            if (!home_is_ready)
                want_leave = true;                        // (in the moment Home is ready: straight in)
            else if (!landed)
                Land();
            else if (t - _land_t > 0.35)
                Leave();
        }

        protected override void _Process(double delta)
        {
            if (_first)
            {
                _first = false;
                _Mark("title: first frame");
            }
            delta = GD.Minf(delta, MAX_STEP);
            t += delta;
            // the opening: the edges darken, the torches flare alight one after the other
            if (!calm)
            {
                var mc = vignette.Modulate; mc.a = (float)GD.Smoothstep(0.0, 0.4, t); vignette.Modulate = mc;
            }
            for (int i = 0; i < _flames.Size(); i++)
            {
                if (!(bool)_lit[i] && t >= (double)IGNITE[i])
                {
                    _lit[i] = true;
                    if (!calm)
                    {
                        _flames[i].D["boost"] = 1.0;
                        if (!_flames[i]["burst"].IsNull)
                        {
                            _flames[i]["burst"].As<CPUParticles2D>().Restart();
                            _flames[i]["burst"].As<CPUParticles2D>().Emitting = true;
                        }
                    }
                    if (i == 0)
                        _Sound("ignite");
                }
            }
            // the show waits for the game behind (the pre-roll), then sets off
            if (_launch < 0.0 && home_is_ready && !leaving && t >= START)
            {
                _launch = t;
                _Mark("title: the show");
            }
            var since = _launch >= 0.0 ? t - _launch : -1.0;
            if (!_whooshed && since >= 0.0)
            {
                _whooshed = true;
                if (!calm)
                    _Sound("whoosh");
            }
            if (jingle != null && !jingle.Playing && !landed && since >= FLIGHT - JINGLE_LEAD)
                jingle.Play();
            // the pre-roll's embers fade while it holds still for the game, and come back for the show
            if (_drift != null)
            {
                var mc = _drift.Modulate;
                mc.a = (float)(holding ? GD.Clampf(1.0 - (t - _hold_t) / SETTLE, 0.0, 1.0) : GD.Minf(1.0, _drift.Modulate.a + delta * 2.5));
                _drift.Modulate = mc;
            }
            // the title's flight: from big and tilted at the viewer, faster and faster, onto the wall, afterimages trailing
            if (!landed)
            {
                if (since >= 0.0)
                {
                    var p = GD.Clampf(since / FLIGHT, 0.0, 1.0);
                    if (calm)
                    {
                        var mc = logo.Modulate; mc.a = (float)GD.Maxf(0.01, p); logo.Modulate = mc;
                    }
                    else
                    {
                        var e = p * p;
                        { var mc = logo.Modulate; mc.a = (float)GD.Clampf(p * 3.0, 0.01, 1.0); logo.Modulate = mc; }
                        logo.Scale = Vector2.ONE * GD.Lerpf(3.6, 1.0, e);
                        logo.Rotation = GD.Lerpf(-0.26, 0.0, e);
                        for (int i = 0; i < ghosts.Size(); i++)
                        {
                            var g = ghosts[i].As<Control>();
                            var pg = GD.Clampf(p - 0.09 * (i + 1), 0.0, 1.0);
                            g.Scale = Vector2.ONE * GD.Lerpf(3.6, 1.0, pg * pg);
                            g.Rotation = GD.Lerpf(-0.26, 0.0, pg * pg);
                            var mc = g.Modulate; mc.a = (float)((0.34 / (i + 1)) * GD.Clampf(p * 3.0, 0.0, 1.0) * GD.Clampf(since / 0.06, 0.0, 1.0)); g.Modulate = mc;
                        }
                    }
                    if (since >= FLIGHT)
                        Land();
                }
            }
            else
            {
                var s = t - _land_t;
                if (!calm)
                {
                    // squash on the hit, then settle
                    var bounce = GD.Exp(-s * 9.0) * GD.Cos(s * 34.0);
                    logo.Scale = new Vector2(1.0 + 0.07 * bounce, 1.0 - 0.07 * bounce);
                    cracks.grow = GD.Clampf(s / 0.18, 0.0, 1.0);
                    cracks.QueueRedraw();
                    { var mc = flash.Modulate; mc.a = (float)GD.Maxf(0.0, flash.Modulate.a - delta * 3.4); flash.Modulate = mc; }
                    shake = GD.Maxf(0.0, shake - delta * 2.4);
                    punch = GD.Maxf(0.0, punch - delta * 2.8);
                    var amp = 16.0 * shake * shake;
                    stage.Position = new Vector2(GD.RandfRange(-amp, amp), GD.RandfRange(-amp, amp));
                    stage.Scale = Vector2.ONE * (1.0 + 0.06 * punch * punch);
                    if (ring.p >= 0.0 && ring.p < 1.0)
                    {
                        ring.p = s / 0.45;
                        ring.QueueRedraw();
                    }
                    if (!_crumbled && s >= 0.14)
                    {
                        _crumbled = true;
                        _Sound("crumble");
                    }
                    // light rays turning behind the title; a gold glint sweeping across the letters every few seconds
                    rays_mat.SetShaderParameter("power", 0.45 * GD.Smoothstep(0.05, 0.7, s));
                    rays_mat.SetShaderParameter("spin", t * 0.22);
                    var g = s - GLINT_AT;
                    var sweep = -1.0;
                    if (g >= 0.0 && GD.Fmod(g, GLINT_EVERY) < GLINT_TIME)
                        sweep = GD.Lerpf(-0.15, 1.15, GD.Fmod(g, GLINT_EVERY) / GLINT_TIME);
                    glint_mat.SetShaderParameter("sweep", sweep);
                }
                else
                    rays_mat.SetShaderParameter("power", 0.4 * GD.Smoothstep(0.0, 0.5, s));
            }
            // LOADING... while the game gets ready behind (still while holding), TAP TO START just after the slam
            if (!leaving)
            {
                if (home_is_ready && landed && t - _land_t >= TAP_AFTER)
                {
                    var a = GD.Clampf((t - _land_t - TAP_AFTER) / 0.4, 0.0, 1.0);
                    if (tap.Text != "TAP TO START")
                    {
                        tap.Text = "TAP TO START";
                        _Mark("title: TAP TO START");
                    }
                    { var mc = tap.Modulate; mc.a = (float)(a * (0.75 + 0.25 * GD.Sin(t * 4.0))); tap.Modulate = mc; }
                    if (!calm)
                        tap.Scale = Vector2.ONE * (1.0 + 0.04 * GD.Sin(t * 4.0));
                    if (!_shown)
                    {
                        _shown = true;
                        Shown?.Invoke();
                    }
                }
                else if (!home_is_ready && (t >= LOADING_AT || want_leave || holding))
                {
                    tap.Text = "LOADING...";
                    tap.Scale = Vector2.ONE;
                    var mc = tap.Modulate; mc.a = (float)(holding || want_leave ? 0.6 : GD.Clampf((t - LOADING_AT) / 0.4, 0.0, 1.0) * (0.45 + 0.2 * GD.Sin(t * 5.0))); tap.Modulate = mc;
                }
                else
                {
                    var mc = tap.Modulate; mc.a = (float)GD.Maxf(0.0, tap.Modulate.a - delta * 4.0); tap.Modulate = mc;
                }
            }
            // the LOADING bar: creeping on by itself while the game loads on its thread, then a step for each piece of Home
            if (!home_is_ready && !holding)
                _progress_to = GD.Maxf(_progress_to, 0.55 * (1.0 - GD.Exp(-t / 2.2)));
            bar.Value = holding || home_is_ready ? _progress_to : GD.Lerpf(bar.Value, _progress_to, GD.Minf(1.0, delta * 6.0));
            var loading_shown = tap.Text == "LOADING..." && !leaving && !landed;
            {
                var mc = bar.Modulate;
                mc.a = (float)(loading_shown && (!home_is_ready) ? GD.Clampf(tap.Modulate.a / 0.6, 0.0, 1.0) : GD.Maxf(0.0, bar.Modulate.a - delta * 4.0));
                bar.Modulate = mc;
            }
            // the torches
            if (calm)
                return;
            foreach (var f in _flames)
            {
                double ph = (double)f["phase"];
                f.D["boost"] = GD.Maxf(0.0, (double)f["boost"] - delta * 1.8);
                double b = (double)f["boost"];
                var fl = 0.5 + 0.22 * GD.Sin(t * 9.3 + ph) + 0.16 * GD.Sin(t * 15.7 + ph * 1.7) + 0.12 * GD.Sin(t * 3.1 + ph * 0.6);
                if (holding)
                    fl = GD.Lerpf(fl, 0.5, GD.Clampf((t - _hold_t) / SETTLE, 0.0, 1.0));     // (steady while the game goes in)
                if (!f["embers"].IsNull)
                {
                    var em = f["embers"].As<CanvasItem>();
                    var mc = em.Modulate; mc.a = _drift != null ? _drift.Modulate.a : 1.0f; em.Modulate = mc;
                }
                var core = f["core"].As<Control>();
                core.Scale = new Vector2(0.9 + 0.12 * fl, 0.82 + 0.32 * fl) * (1.0 + 0.7 * b);
                core.Rotation = 0.08 * GD.Sin(t * 2.4 + ph);
                var halo = f["halo"].As<Control>();
                { var mc = halo.Modulate; mc.a = (float)(0.32 + 0.22 * fl + 0.55 * b); halo.Modulate = mc; }
                halo.Scale = Vector2.ONE * (1.0 + 0.5 * b);
                var pool = f["pool"].As<Control>();
                { var mc = pool.Modulate; mc.a = (float)(0.12 + 0.06 * fl + 0.22 * b); pool.Modulate = mc; }
            }
        }
    }
}
