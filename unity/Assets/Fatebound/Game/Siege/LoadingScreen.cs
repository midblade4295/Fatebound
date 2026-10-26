// Ported from godot/scripts/siege/loading_screen.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector2i = Fatebound.Sim.Vec2i;
using Vector3 = Fatebound.Sim.Vec3;
using Color = Fatebound.GUI.Col;
using Transform3D = Fatebound.Sim.Xform3;
using Environment = Fatebound.GUI.Environment;

namespace Fatebound.Game
{
    using UI = Fatebound.Game.Ui;
    using UI2 = Fatebound.Game.Ui2;
    using Net = Fatebound.Game.SiegeNet;
    using View = Fatebound.Game.SiegeView;
    using Eco = Fatebound.Game.Economy;
    using Moba = Fatebound.Sim.Moba;
    using TitleLogo = Fatebound.Game.TitleLogo;

    // 0.31.208 (Kevin: "Make a all new loading screen graphic and as players join it'll show their character along with
    // cosmetics they are wearing in the loading screen"): the match's loading screen -- one screen from PLAY until the battle
    // shows. A painted courtyard at dusk (assets/ui/v2/bg_loading.webp; art_sources/loading), the title over its sky, and on
    // its plaza, in 3D, the players coming to the battle: each one's hero in the outfit they wear on him, dropping in as they
    // join (a burst of gold where they land), their name and the outfit's under them; you in the middle, ringed in gold.
    //   connecting  you on the plaza, the ring spinning
    //   lobby       the server's "lobby" messages (every half second): the countdown to the battle, who's joining -- their
    //               heroes and outfits from its "hr"/"sk" (a server before 0.31.208 sends only names: a shadow for each of
    //               the others), how many players are on, whether a battle is already running
    //   loading     the battle's being built behind it (siege_mode's loading card; offline it's the only state): PREPARING
    //               THE BATTLEFIELD, no LEAVE; it lifts with the match's warm-up
    //   failed      CAN'T JOIN and why
    // (0.31.82-0.31.207: lobby_panel.gd -- a countdown and a list of names; and the FATEBOUND card on the castle wall.)
    public class LoadingScreen : Control
    {
        public event Action Leave;

        public const string BG = "res://assets/ui/v2/bg_loading.webp";
        public const int MAX_FIGS = 10;
        public static readonly Color GOLD = new Color("#ffd65a");
        public static readonly Color HOT = new Color("#ff8a3d");
        public const double SPACING = 1.45;                 // metres between heroes in a row
        public const int ROW_MAX = 5;
        public const double BACK_Z = -1.7;                  // the second row: behind, between, on the step
        public const double BACK_Y = 0.8;
        public const double STAGE_TOP = 0.03;               // the 3D stage's band of the screen (of its height; 0.22-0.74 in portrait)
        public const double STAGE_BOTTOM = 0.84;
        public const double CAM_MIN = 10.0;                 // the camera at least this far back (7.2 in portrait: the band was narrower)
        public const double SIDE_W = 200.0;                 // 0.31.216 (landscape): the countdown's column on the left, the words and LEAVE's on the right
        public const double VFOV = 30.0;
        public const double DROP_H = 4.0;                   // a joining hero drops from this high...
        public const double DROP_T = 0.37;                  // ...in this long: the second half of his own leap in (the rig's Spawn_Air, from
        public const double LEAP_FROM = 0.37;               // its top at 0.37 s to its landing at 0.74 s), on top of it
        public const double RES_SCALE = 0.75;               // the stage drawn at 3/4 of the screen's pixels

        public Node audio = null;
        public string my_hero = "";                     // (siege_mode: the hero I play and the outfit I wear on him -- shown at once)
        public string my_skin = "";
        public string my_name = "";
        public string state = "connecting";
        public double left = -1.0;
        public double wait = 20.0;
        public string note_text = "";
        public int _last_sec = -1;
        public double _spin = 0.0;
        public bool _first = true;

        // the stage
        public SubViewport viewport;
        public TextureRect stage_tex;
        public Node3D world;
        public Camera3D cam;
        public double _cam_d = 8.0;                     // the camera's distance now (eases to _cam_want as heroes come and go)
        public double _cam_want = 8.0;
        public double _cam_z = 0.0;
        public double _cam_z_want = 0.0;
        public double _vis_w = 4.0;
        public double _cam_lift = 0.0;                  // (two rows: the camera higher, to see the second over the first)
        public double _cam_lift_want = 0.0;
        public GDict figs = new GDict();                // key ("name#n") -> {key, name, hero, skin, me, unknown, holder, body, player, shadow, plate, at, t0, drop, gone}
        public GArray _order = new GArray();            // keys in join order
        public Control plates_layer;

        // the UI
        public Label title;
        public Control ring;
        public Label number;
        public Label mode_lbl;
        public Control count_row;
        public Label count_lbl;
        public Label sub_lbl;
        public Button leave_btn;
        public VBoxContainer status_box;
        public int joined_n = 0;                        // (tests: heroes that dropped in)

        public bool _built = false;                     // the stage and the words (built the frame after the painting: PLAY stays quick)
        public GDict _pending = new GDict();            // a lobby message before then
        public string _fail_why = "";

        public LoadingScreen()
        {
            SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            MouseFilter = Control.MOUSE_FILTER_STOP;
            ZIndex = 50;                                   // over the HUD (100 as the loading card: loading())
            _BuildBg();
            _BuildTop();
        }

        protected override void _Ready()
        {
            CallDeferred(_BuildRest);
        }

        public void _BuildRest()
        {
            // the plaza's stage and the countdown, then whatever came before them; my hero drops in
            if (_built || !IsInsideTree())
                return;
            _BuildStage();
            _BuildStatus();
            _built = true;
            Resized += _Resize;
            _Resize();
            if (state == "loading")
                _ApplyLoading();
            else if (state == "failed")
                _ApplyFail();
            if (!_pending.IsEmpty())
            {
                var m = _pending;
                _pending = new GDict();
                Update(m);
            }
            if (note_text != "")
                sub_lbl.Text = note_text;
            if (my_hero != "" && figs.IsEmpty())
                _SetLineup(GArray.Of(GDict.Of("key", "me", "name", my_name != "" ? my_name : "You", "hero", my_hero, "skin", my_skin, "me", true)));
        }

        // ---------------- the painting ----------------
        public void _BuildBg()
        {
            var tex = UI2.Tex(BG);
            if (tex != null)
            {
                var bg = new TextureRect();
                bg.Texture = tex;
                bg.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
                bg.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_COVERED;
                bg.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
                bg.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                bg.Name = "Background";
                AddChild(bg);
            }
            else
            {
                // (no ui pack yet: dusk in a gradient)
                var g = new TextureRect();
                var gt = new GradientTexture2D();
                var gr = new Gradient();
                gr.SetColor(0, new Color("#5a2a4a"));
                gr.SetColor(1, new Color("#0c0a14"));
                gt.Gradient = gr;
                gt.FillFrom = new Vector2(0.5, 0.0);
                gt.FillTo = new Vector2(0.5, 1.0);
                gt.Width = 8;
                gt.Height = 128;
                g.Texture = gt;
                g.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
                g.StretchMode = TextureRect.STRETCH_SCALE;
                g.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
                g.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                AddChild(g);
            }
            // the bottom darkened a little more under the words and the button
            var shade = new TextureRect();
            var st = new GradientTexture2D();
            var sg = new Gradient();
            sg.SetOffsets(new double[] { 0.0, 0.62, 1.0 });
            sg.SetColors(new Color[] { new Color(0, 0, 0, 0), new Color(0.03, 0.02, 0.05, 0.0), new Color(0.03, 0.02, 0.05, 0.78) });
            st.Gradient = sg;
            st.FillFrom = new Vector2(0.5, 0.0);
            st.FillTo = new Vector2(0.5, 1.0);
            st.Width = 4;
            st.Height = 256;
            shade.Texture = st;
            shade.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            shade.StretchMode = TextureRect.STRETCH_SCALE;
            shade.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            shade.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(shade);
        }

        // ---------------- the stage (3D) ----------------
        public void _BuildStage()
        {
            viewport = new SubViewport();
            viewport.OwnWorld3D = true;
            viewport.TransparentBg = true;
            viewport.Msaa3D = Viewport.MSAA_DISABLED;        // (as the menus' hero: MSAA's pipelines aren't pre-compiled)
            viewport.RenderTargetUpdateMode = SubViewport.UPDATE_WHEN_VISIBLE;
            AddChild(viewport);
            stage_tex = new TextureRect();
            stage_tex.Texture = viewport.GetTexture();
            stage_tex.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            stage_tex.StretchMode = TextureRect.STRETCH_SCALE;
            stage_tex.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            stage_tex.Name = "Stage";
            AddChild(stage_tex);
            plates_layer = new Control();
            plates_layer.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            plates_layer.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(plates_layer);
            world = new Node3D();
            viewport.AddChild(world);
            var env = new Environment();
            env.BackgroundMode = Environment.BG_CLEAR_COLOR;
            env.AmbientLightSource = Environment.AMBIENT_SOURCE_COLOR;
            env.AmbientLightColor = new Color("#e6cfd6");
            env.AmbientLightEnergy = 0.6 * View.VULKAN_AMBIENT;
            env.TonemapMode = Environment.TONE_MAPPER_FILMIC;
            env.TonemapExposure = 0.9 * View.VULKAN_EXPOSURE;
            env.TonemapWhite = 3.0;
            var we = new WorldEnvironment();
            we.Environment = env;
            world.AddChild(we);
            // the painting's light: the sunset low behind (a warm rim), the braziers either side, a soft key from the front
            var key = new DirectionalLight3D();
            key.LightColor = new Color("#ffe6c8");
            key.LightEnergy = 1.1;
            key.RotationDegrees = new Vector3(-24, 18, 0);
            world.AddChild(key);
            var rim = new DirectionalLight3D();
            rim.LightColor = new Color("#ff9a5a");
            rim.LightEnergy = 1.4;
            rim.RotationDegrees = new Vector3(-14, 180, 0);
            world.AddChild(rim);
            foreach (var sx in new[] { -1.0, 1.0 })
            {
                var fire = new OmniLight3D();
                fire.LightColor = new Color("#ff8a3a");
                fire.LightEnergy = 2.4;
                fire.OmniRange = 9.0;
                fire.Position = new Vector3(sx * 5.5, 2.2, -2.5);
                world.AddChild(fire);
            }
            cam = new Camera3D();
            cam.Fov = VFOV;
            cam.Current = true;
            world.AddChild(cam);
            _PlaceCam();
        }

        public void _Resize()
        {
            var top = Size.y * STAGE_TOP;
            var h = Size.y * (STAGE_BOTTOM - STAGE_TOP);
            stage_tex.Position = new Vector2(0.0, top);
            stage_tex.Size = new Vector2(Size.x, h);
            var logical = IsInsideTree() ? GetViewport().GetVisibleRect().size : Size;
            var window = (Vector2)DisplayServer.WindowGetSize();
            var ratio = 1.0;
            if (logical.x > 0.0 && window.x > 0.0)
                ratio = GD.Clampf(window.x / logical.x, 1.0, 4.0);
            ratio *= RES_SCALE;
            viewport.Size = new Vector2i(GD.Maxi(64, GD.Int(Size.x * ratio)), GD.Maxi(64, GD.Int(h * ratio)));
            _Fit();
            _SizePlates();
        }

        public void _Fit()
        {
            // the camera far enough back that the widest row fits (closer for one or two: they stand tall)
            var n = 0;
            foreach (var k in _order)
            {
                if (!(bool)figs[k]["gone"])
                    n += 1;
            }
            var per_row = GD.Mini(GD.Maxi(n, 1), ROW_MAX);
            var width = (double)(per_row - 1) * SPACING + (per_row == 1 ? 1.9 : 3.1) + (n > ROW_MAX ? SPACING * 0.5 : 0.0);
            var aspect = (double)viewport.Size.x / GD.Maxf(1.0, (double)viewport.Size.y);
            var half_h = Math.Tan(GD.DegToRad(VFOV) * 0.5) * aspect;
            _cam_want = GD.Clampf(width / (2.0 * half_h), CAM_MIN, 16.0);
            _vis_w = 2.0 * _cam_want * half_h;                // (the plaza's width across the screen at the heroes)
            _cam_z_want = n > ROW_MAX ? BACK_Z * 0.35 : 0.0;
            _cam_lift_want = n > ROW_MAX ? 1.1 : 0.0;
        }

        public void _PlaceCam()
        {
            // a little above the heroes' heads, looking down at their waists (more from farther back)
            var eye = new Vector3(0.0, 1.55 + 0.1 * _cam_d + _cam_lift, _cam_z + _cam_d);
            cam.Transform = new Transform3D(Basis.LookingAt(new Vector3(0.0, 0.95, _cam_z) - eye, Vector3.UP), eye);
        }

        public GArray _Slots(int n)
        {
            // n places: the front row first, the middle first then out to either side; past five, a second row behind,
            // between them and a step up
            var o = new GArray();
            var front = GD.Mini(n, ROW_MAX);
            var back = n - front;
            foreach (var row in GArray.Of(GArray.Of(front, 0.0, 0.0, 0.0), GArray.Of(back, BACK_Z, BACK_Y, SPACING * 0.5)))
            {
                var cnt = GD.Int(row[0]);
                var order = new GArray();
                for (int i = 0; i < cnt; i++)
                    order.Append(i == 0 ? 0 : ((int)((i + 1) / 2) * (i % 2 == 1 ? 1 : -1)));
                // centred: a row of an even count shifts half a place
                var shift = cnt % 2 == 1 ? 0.0 : -0.5;
                foreach (var ov in order)
                {
                    var oi = (int)ov;
                    var x = ((double)oi + shift) * SPACING + (cnt % 2 == 1 ? (double)row[3] : 0.0);
                    o.Append(new Vector3(x, (double)row[2], (double)row[1] - Math.Abs((double)oi) * 0.18));
                }
            }
            return o;
        }

        // ---------------- the heroes ----------------
        public static string LookOf(string hero)
        {
            return View.LOOKS.Has(GD.Str(Eco.UP_LOOK.Get(hero, hero))) ? GD.Str(Eco.UP_LOOK.Get(hero, hero)) : "knight";
        }

        public void _SetLineup(GArray list)
        {
            // list: [{key, name, hero, skin, me, unknown}] in the server's order (who came first first)
            var keys = new GDict();
            foreach (var e in list.Slice(0, MAX_FIGS))
                keys[GD.Str(e["key"])] = true;
            foreach (var k in _order.Duplicate())
            {
                if (!keys.Has(k) && !(bool)figs[k]["gone"])
                    _RemoveFig(k.AsString());
            }
            var joined = false;
            var delay = 0.0;
            foreach (var ev in list.Slice(0, MAX_FIGS))
            {
                GDict e = ev.D;
                var k = GD.Str(e["key"]);
                GDict f = figs.Get(k, new GDict()).D;
                if (!f.IsEmpty() && !(bool)f["gone"] && (GD.Str(f["hero"]) != GD.Str(e["hero"]) || GD.Str(f["skin"]) != GD.Str(e.Get("skin", "")) || (bool)f["unknown"] != (bool)e.Get("unknown", false)))
                {
                    _RemoveFig(k, true);                      // (a different hero or outfit: built again)
                    f = new GDict();
                }
                if (f.IsEmpty() || (bool)f["gone"])
                {
                    _AddFig(e, delay);
                    delay += 0.12;
                    if (!_first && !(bool)e.Get("me", false))
                        joined = true;
                }
                else
                {
                    f["name"] = GD.Str(e["name"]);
                    f["plate_name"].As<Label>().Text = GD.Str(e["name"]);        // (now with their title and clan tag)
                }
            }
            // me in the middle: my key first, then the others in the order they came
            var mine = _order.Filter(k => (bool)figs[k]["me"] && !(bool)figs[k]["gone"]);
            var rest = _order.Filter(k => !(bool)figs[k]["me"] && !(bool)figs[k]["gone"]);
            GArray live = mine.Duplicate();
            live.AppendArray(rest);
            var slots = _Slots(live.Size());
            for (int i = 0; i < live.Size(); i++)
                figs[live[i]].D["at"] = slots[i];
            _Fit();
            _SizePlates();
            if (joined)
                _Sfx("flip");
        }

        public void _AddFig(GDict e, double delay)
        {
            var k = GD.Str(e["key"]);
            if (figs.Has(k))
                _FreeFig(k);
            var hero = GD.Str(e.Get("hero", ""));
            var unknown = (bool)e.Get("unknown", false) || hero == "";
            var skin = GD.Str(e.Get("skin", ""));
            if (skin != "" && !(Eco.SKINS.Has(skin) && GD.Str(Eco.SKINS[skin]["hero"]) == hero))
                skin = "";
            var holder = new Node3D();
            world.AddChild(holder);
            var shadow = new MeshInstance3D();
            var sm = new CylinderMesh();
            sm.TopRadius = 0.62;
            sm.BottomRadius = 0.62;
            sm.Height = 0.01;
            sm.RadialSegments = 32;
            shadow.Mesh = sm;
            var shm = new StandardMaterial3D();
            shm.Transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
            shm.ShadingMode = BaseMaterial3D.SHADING_MODE_UNSHADED;
            shm.AlbedoColor = (bool)e.Get("me", false) ? new Color(1.0, 0.82, 0.3, 0.55) : new Color(0.0, 0.0, 0.0, 0.45);
            shadow.MaterialOverride = shm;
            shadow.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            world.AddChild(shadow);
            Node3D body = null;
            AnimationPlayer player = null;
            var look = LookOf(!unknown ? hero : "knight");
            GDict made = View.MakeBody(look, skin != "" ? GDict.Of("skin", skin) : new GDict());
            if (!made.IsEmpty())
            {
                body = made["body"].As<Node3D>();
                player = made["player"].As<AnimationPlayer>();
                holder.AddChild(body);
                body.Scale = Vector3.ONE * View.BODY_SCALE * (Moba.HERO_SCALE.TryGetValue(hero, out var hs) ? hs : 1.0);
                if (unknown)
                    _ShadowBody(body);                        // (an older server: who they'll be isn't known -- a shadow)
            }

            var f = GDict.Of("key", k, "name", GD.Str(e["name"]), "hero", hero, "skin", skin, "me", (bool)e.Get("me", false), "unknown", unknown,
                "holder", holder, "body", body, "player", player, "shadow", shadow, "look", look, "at", Vector3.ZERO,
                "t0", _spin + delay, "landed", false, "gone", false);
            holder.Visible = false;
            shadow.Visible = false;
            _MakePlate(f);
            figs[k] = f;
            _order.Append(k);
        }

        public void _ShadowBody(Node3D body)
        {
            var m = new StandardMaterial3D();
            m.AlbedoColor = new Color(0.07, 0.05, 0.12);
            m.Roughness = 1.0;
            m.EmissionEnabled = true;
            m.Emission = new Color(0.25, 0.18, 0.45);
            m.EmissionEnergyMultiplier = 0.25;
            foreach (var mi in body.FindChildren("*", "MeshInstance3D", true, false))
                ((MeshInstance3D)mi).MaterialOverride = m;
        }

        public void _MakePlate(GDict f)
        {
            var me = (bool)f["me"];
            var pc = new PanelContainer();
            var sb = new StyleBoxFlat();
            sb.BgColor = me ? new Color(0.16, 0.1, 0.03, 0.82) : new Color(0.05, 0.04, 0.09, 0.78);
            sb.BorderColor = me ? new Color(GOLD, 0.95) : new Color(1, 1, 1, 0.22);
            sb.SetBorderWidthAll(me ? 2 : 1);
            sb.SetCornerRadiusAll(9);
            sb.ContentMarginLeft = 7;
            sb.ContentMarginRight = 7;
            sb.ContentMarginTop = 2;
            sb.ContentMarginBottom = 3;
            pc.AddThemeStyleboxOverride("panel", sb);
            pc.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", -2);
            v.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            pc.AddChild(v);
            var nm = UI2.Body(v, GD.Str(f["name"]), 13, me ? new Color("#fff4d6") : new Color("#e8ecfb"), false);
            nm.HorizontalAlignment = HorizontalAlignment.Center;
            nm.ClipText = true;
            nm.TextOverrunBehavior = TextServer.OVERRUN_TRIM_ELLIPSIS;
            var sub = "";
            var sub_col = new Color("#b9c2dd");
            if ((bool)f["unknown"])
                sub = "joining...";
            else if (GD.Str(f["skin"]) != "")
            {
                sub = GD.Str(Eco.SKINS[GD.Str(f["skin"])]["name"]);         // the outfit ("Frost Knight")
                sub_col = new Color("#ffcf6a");
            }
            else
                sub = Moba.HEROES.TryGetValue(GD.Str(f["hero"]), out var hd) ? GD.Str(hd.name) : GD.Str(f["hero"]).Capitalize();
            var sl = UI2.Body(v, sub, 10, sub_col, false);
            sl.HorizontalAlignment = HorizontalAlignment.Center;
            sl.ClipText = true;
            sl.TextOverrunBehavior = TextServer.OVERRUN_TRIM_ELLIPSIS;
            if (me)
            {
                var you = UI2.Chip(v, "YOU", GOLD, new Color("#3a1c02"));
                you.SizeFlagsHorizontal = Control.SIZE_SHRINK_CENTER;
            }
            var pm = pc.Modulate;
            pm.a = 0.0f;
            pc.Modulate = pm;
            plates_layer.AddChild(pc);
            f["plate"] = pc;
            f["plate_name"] = nm;
            f["plate_sub"] = sl;
        }

        public void _RemoveFig(string k, bool now = false)
        {
            GDict f = figs[k].D;
            f["gone"] = true;
            f["t_gone"] = _spin;
            if (now)
                _FreeFig(k);
        }

        public void _FreeFig(string k)
        {
            GDict f = figs.Get(k, new GDict()).D;
            if (f.IsEmpty())
                return;
            foreach (var n in GArray.Of(f["holder"], f["shadow"], f["plate"]))
            {
                if (GD.IsInstanceValid(n.As<Node>()))
                    n.As<Node>().QueueFree();
            }
            figs.Erase(k);
            _order.Erase(k);
        }

        public void _Land(GDict f)
        {
            // where a hero lands: a ring of gold racing out over the stones and a column of light fading up
            f["landed"] = true;
            joined_n += 1;
            Vector3 at = f["at"].V3;
            var ring_mi = new MeshInstance3D();
            var tm = new TorusMesh();
            tm.InnerRadius = 0.82;
            tm.OuterRadius = 1.0;
            tm.Rings = 40;
            tm.RingSegments = 4;
            ring_mi.Mesh = tm;
            var rm = new StandardMaterial3D();
            rm.ShadingMode = BaseMaterial3D.SHADING_MODE_UNSHADED;
            rm.Transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
            rm.BlendMode = BaseMaterial3D.BLEND_MODE_ADD;
            rm.AlbedoColor = new Color(1.0, 0.78, 0.3, 0.9);
            ring_mi.MaterialOverride = rm;
            ring_mi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            ring_mi.Position = at + new Vector3(0, 0.03, 0);
            ring_mi.Scale = new Vector3(0.3, 0.05, 0.3);
            world.AddChild(ring_mi);
            var beam = new MeshInstance3D();
            var cm = new CylinderMesh();
            cm.TopRadius = 0.04;
            cm.BottomRadius = 0.28;
            cm.Height = 7.0;
            cm.RadialSegments = 16;
            cm.CapTop = false;
            cm.CapBottom = false;
            beam.Mesh = cm;
            var bm = new StandardMaterial3D();
            bm.ShadingMode = BaseMaterial3D.SHADING_MODE_UNSHADED;
            bm.Transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
            bm.BlendMode = BaseMaterial3D.BLEND_MODE_ADD;
            bm.CullMode = BaseMaterial3D.CULL_DISABLED;
            bm.AlbedoColor = new Color(1.0, 0.85, 0.45, 0.32);
            beam.MaterialOverride = bm;
            beam.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            beam.Position = at + new Vector3(0, 3.5, -0.45);            // (behind him: a streak of light, not a wash over him)
            world.AddChild(beam);
            var tw = ring_mi.CreateTween().SetParallel();
            tw.TweenProperty(ring_mi, "scale", new Vector3(2.4, 0.05, 2.4), 0.55).SetTrans(Tween.TRANS_QUAD).SetEase(Tween.EASE_OUT);
            tw.TweenProperty(rm, "albedo_color:a", 0.0, 0.55);
            tw.Chain().TweenCallback(ring_mi.QueueFree);
            var tb = beam.CreateTween().SetParallel();
            tb.TweenProperty(bm, "albedo_color:a", 0.0, 0.45).SetTrans(Tween.TRANS_QUAD).SetEase(Tween.EASE_OUT);
            tb.TweenProperty(beam, "scale", new Vector3(0.2, 1.0, 0.2), 0.45);
            tb.Chain().TweenCallback(beam.QueueFree);
        }

        public void _Leap(GDict f)
        {
            // his leap in from its top, the landing crouch and up, then his idle
            AnimationPlayer p = f["player"].As<AnimationPlayer>();
            if (p == null || !GD.IsInstanceValid(p))
                return;
            var idle = GD.Str(View.LOOKS.Get(GD.Str(f["look"]), View.LOOKS["knight"]).D["idle"]);
            if (!p.HasAnimation(idle))
                idle = "g/Idle_A";
            if (p.HasAnimation("g/Spawn_Air"))
            {
                p.Play("g/Spawn_Air", 0.0);
                p.Seek(LEAP_FROM, true);
                p.Queue(idle);
            }
            else if (p.HasAnimation(idle))
                p.Play(idle);
        }

        public void _StepFigs(double delta)
        {
            foreach (var kv in _order.Duplicate())
            {
                var k = kv.AsString();
                GDict f = figs[k].D;
                Node3D holder = f["holder"].As<Node3D>();
                MeshInstance3D shadow = f["shadow"].As<MeshInstance3D>();
                Vector3 at = f["at"].V3;
                var age = _spin - (double)f["t0"];
                if ((bool)f["gone"])
                {
                    var gt = _spin - (double)f.Get("t_gone", _spin);
                    var s = GD.Clampf(1.0 - gt / 0.25, 0.0, 1.0);
                    holder.Scale = Vector3.ONE * GD.Maxf(s, 0.001);
                    shadow.Scale = Vector3.ONE * GD.Maxf(s, 0.001);
                    var pl = f["plate"].As<Control>();
                    var pm = pl.Modulate;
                    pm.a = (float)s;
                    pl.Modulate = pm;
                    if (s <= 0.0)
                        _FreeFig(k);
                    continue;
                }
                if (age < 0.0)
                    continue;
                if (!holder.Visible)
                {
                    holder.Visible = true;
                    shadow.Visible = true;
                    _Leap(f);
                }
                // down out of the sky onto its place; landed, it slides over when the line-up changes
                var fall = GD.Clampf(age / DROP_T, 0.0, 1.0);
                if (!(bool)f["landed"])
                {
                    holder.Position = at + new Vector3(0.0, DROP_H * (1.0 - fall * fall), 0.0);
                    if (fall >= 1.0)
                        _Land(f);
                }
                else
                    holder.Position = holder.Position.Lerp(at, 1.0 - Math.Exp(-delta * 8.0));
                shadow.Position = new Vector3(holder.Position.x, at.y + 0.02, holder.Position.z);
                var sc = GD.Clampf(0.35 + 0.65 * fall, 0.0, 1.0);
                shadow.Scale = new Vector3(sc, 1.0, sc);
                // a slow sway toward the camera
                var rot = holder.Rotation;
                rot.y = (float)(Math.Sin(_spin * 0.5 + (double)(GD.Hash(k) % 100) * 0.1) * 0.18);
                holder.Rotation = rot;
                var plate = f["plate"].As<Control>();
                var mod = plate.Modulate;
                mod.a = (float)GD.Clampf((age - DROP_T) / 0.25, 0.0, 1.0);
                plate.Modulate = mod;
            }
        }

        public void _SizePlates()
        {
            // each name plate as wide as its words, at most a row's share of the screen
            var n = 0;
            foreach (var k in _order)
                n += (bool)figs[k]["gone"] ? 0 : 1;
            var max_w = GD.Clampf(Size.x * SPACING / GD.Maxf(_vis_w, 0.1) - 6.0, 68.0, 170.0) - 14.0;   // (a hero's share of the width)
            foreach (var k in _order)
            {
                GDict f = figs[k].D;
                foreach (var key in new[] { "plate_name", "plate_sub" })
                {
                    Label l = f[key].As<Label>();
                    Font font = l.GetThemeFont("font");
                    var tw = font.GetStringSize(l.Text, HorizontalAlignment.Left, -1, l.GetThemeFontSize("font_size")).x + 2.0;
                    var cms = l.CustomMinimumSize;
                    cms.x = (float)GD.Minf(tw, max_w);
                    l.CustomMinimumSize = cms;
                }
                PanelContainer pc = f["plate"].As<PanelContainer>();
                pc.Size = pc.GetCombinedMinimumSize();
            }
        }

        public void _PlacePlates()
        {
            if (!GD.IsInstanceValid(cam) || !cam.IsInsideTree())
                return;
            var vs = (Vector2)viewport.Size;
            if (vs.x <= 0.0)
                return;
            var scale_v = stage_tex.Size / vs;
            foreach (var k in _order)
            {
                GDict f = figs[k].D;
                PanelContainer pc = f["plate"].As<PanelContainer>();
                var back = (double)f["at"].V3.z < BACK_Z * 0.5;
                // under the feet (the second row: over the head)
                Vector3 anchor_p = f["holder"].As<Node3D>().Position + (back ? new Vector3(0, 2.75, 0) : new Vector3(0, -0.05, 0));
                if ((bool)f["landed"])
                    anchor_p = f["at"].V3 + (back ? new Vector3(0, 2.75, 0) : new Vector3(0, -0.05, 0));
                if (cam.IsPositionBehind(anchor_p))
                    continue;
                var sp = cam.UnprojectPosition(anchor_p) * scale_v + stage_tex.Position;
                pc.Position = new Vector2(sp.x - pc.Size.x * 0.5, GD.Maxf(4.0, sp.y - (back ? pc.Size.y : -2.0))).Round();   // (on the screen)
            }
        }

        // ---------------- the words ----------------
        public void _BuildTop()
        {
            // the title over the sky (0.31.216, landscape: in the top-left corner; across the top in portrait)
            var top = new VBoxContainer();
            top.SetAnchorsAndOffsetsPreset(Control.PRESET_TOP_LEFT);
            top.OffsetTop = 6;
            top.OffsetLeft = 14;
            top.Alignment = BoxContainer.ALIGNMENT_BEGIN;
            top.AddThemeConstantOverride("separation", -4);
            top.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(top);
            var lw = SIDE_W;
            var logo = new TitleLogo();
            logo.CustomMinimumSize = new Vector2(lw, lw * TitleLogo.Aspect());
            logo.SizeFlagsHorizontal = Control.SIZE_SHRINK_CENTER;
            top.AddChild(logo);
            UI2.Center(UI2.Text(top, "5 VS 5", 15, new Color("#ffe9c4"), new Color("#2a1206"), 5));
        }

        public void _BuildStatus()
        {
            // the countdown and who's coming: 0.31.216 (landscape) a column on the left beside the plaza's heroes -- the ring over
            // the words; what's going on and LEAVE in the bottom-right corner (under the plaza's ring, one column, in portrait)
            status_box = new VBoxContainer();
            status_box.AnchorTop = 0.5;
            status_box.AnchorBottom = 0.5;
            status_box.OffsetLeft = 14;
            status_box.OffsetRight = 14 + SIDE_W;
            status_box.OffsetTop = -44;
            status_box.OffsetBottom = 130;
            status_box.Alignment = BoxContainer.ALIGNMENT_BEGIN;
            status_box.AddThemeConstantOverride("separation", 6);
            status_box.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(status_box);
            var row = new VBoxContainer();
            row.Alignment = BoxContainer.ALIGNMENT_CENTER;
            row.AddThemeConstantOverride("separation", 4);
            row.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            status_box.AddChild(row);
            ring = new Control();
            ring.CustomMinimumSize = new Vector2(72, 72);
            ring.SizeFlagsHorizontal = Control.SIZE_SHRINK_CENTER;
            ring.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            row.AddChild(ring);
            ring.Draw += _DrawRing;
            number = UI2.Text(ring, "", 38, Color.WHITE, new Color("#2a1604"), 8);
            number.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            number.HorizontalAlignment = HorizontalAlignment.Center;
            number.Resized += () => number.PivotOffset = number.Size * 0.5;
            var words = new VBoxContainer();
            words.Alignment = BoxContainer.ALIGNMENT_CENTER;
            words.AddThemeConstantOverride("separation", 2);
            words.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            row.AddChild(words);
            title = UI2.Text(words, "FINDING A BATTLE", 20, Color.WHITE, new Color("#2a1206"));
            title.HorizontalAlignment = HorizontalAlignment.Center;
            title.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
            var tcm = title.CustomMinimumSize;
            tcm.x = (float)SIDE_W;
            title.CustomMinimumSize = tcm;
            var cr = new HBoxContainer();
            cr.Alignment = BoxContainer.ALIGNMENT_CENTER;
            cr.AddThemeConstantOverride("separation", 7);
            cr.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            words.AddChild(cr);
            count_row = cr;
            var dot = new Panel();
            var ds = new StyleBoxFlat();
            ds.BgColor = new Color("#5fdc86");
            ds.SetCornerRadiusAll(5);
            ds.ShadowColor = new Color(0.37, 0.86, 0.53, 0.7);
            ds.ShadowSize = 4;
            dot.AddThemeStyleboxOverride("panel", ds);
            dot.CustomMinimumSize = new Vector2(9, 9);
            dot.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            dot.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            cr.AddChild(dot);
            count_lbl = UI2.Text(cr, "5 vs 5", 17, new Color("#8cf0a8"), new Color("#0b2a14"));
            var foot = new VBoxContainer();
            foot.SetAnchorsAndOffsetsPreset(Control.PRESET_BOTTOM_RIGHT);
            foot.OffsetLeft = -14 - SIDE_W;
            foot.OffsetRight = -14;
            foot.OffsetTop = -150;
            foot.OffsetBottom = -10;
            foot.Alignment = BoxContainer.ALIGNMENT_END;
            foot.AddThemeConstantOverride("separation", 6);
            foot.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(foot);
            mode_lbl = UI2.Center(UI2.Body(foot, "Connecting to the server...", 13, new Color("#fff4d6")));
            sub_lbl = UI2.Center(UI2.Body(foot, "bots fill the empty slots", 11, new Color("#b9c2dd")));
            var lc = new CenterContainer();
            lc.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            foot.AddChild(lc);
            leave_btn = UI2.Button(lc, "LEAVE", "grey", () =>
            {
                _Sfx("menuClose");
                Leave?.Invoke();
            }, "lobby_leave", 17, 44.0);
            var lcm = leave_btn.CustomMinimumSize;
            lcm.x = 170;
            leave_btn.CustomMinimumSize = lcm;
        }

        public void _Sfx(string cue)
        {
            if (audio != null && GObject.HasMethod(audio, "play"))
                GObject.Call(audio, "play", cue);
        }

        // ---------------- server messages ----------------
        public void Update(GDict msg)
        {
            // A "lobby" message: {left, wait, names, me, online, in_match, slots, running, tt, ct, hr, sk}
            if (state == "loading" || state == "failed")
                return;
            if (!_built)
            {
                _pending = msg;
                return;
            }
            state = "lobby";
            wait = GD.Maxf(1.0, (double)msg.Get("wait", wait));
            var l = (double)msg.Get("left", 0.0);
            if (left < 0.0 || Math.Abs(l - left) > 0.35)        // (between messages the clock runs here; resync on drift)
                left = l;
            title.Text = "BATTLE STARTS IN";
            var slots = GD.Int(msg.Get("slots", 10));
            var online = GD.Int(msg.Get("online", 1));
            count_lbl.Text = GD.Fmt("%d / %d PLAYERS", GD.Mini(online, slots), slots);
            if ((bool)msg.Get("running", false))
            {
                var n = GD.Int(msg.Get("in_match", 0));
                mode_lbl.Text = GD.Fmt("A battle is on -- %d player%s fighting. You join it at zero.", n, n == 1 ? "" : "s");
            }
            else
                mode_lbl.Text = "A new 5 vs 5 battle starts at zero";
            sub_lbl.Text = note_text != "" ? note_text : "bots fill the empty slots";
            GArray names = msg.Get("names", new GArray()).A.Duplicate();
            GArray tt = msg.Get("tt", new GArray()).IsArr ? msg.Get("tt", new GArray()).A : new GArray();
            GArray ct = msg.Get("ct", new GArray()).IsArr ? msg.Get("ct", new GArray()).A : new GArray();
            GArray hr = msg.Get("hr", new GArray()).IsArr ? msg.Get("hr", new GArray()).A : new GArray();
            GArray sk = msg.Get("sk", new GArray()).IsArr ? msg.Get("sk", new GArray()).A : new GArray();
            var me = GD.Int(msg.Get("me", -1));
            var seen = new GDict();
            var list = new GArray();
            for (int i = 0; i < names.Size(); i++)
            {
                var raw = GD.Str(names[i]);
                seen[raw] = GD.Int(seen.Get(raw, 0)) + 1;
                var shown = raw;
                if (i < tt.Size() && GD.Str(tt[i]) != "")
                    shown = Net.TitleText(raw, GD.Str(tt[i]));          // (with their titles, punctuated)
                if (i < ct.Size() && GD.Str(ct[i]) != "")
                    shown = GD.Fmt("[%s] %s", GD.Str(ct[i]), shown);          // their clan's tag
                var is_me = i == me;
                var hero = i < hr.Size() ? GD.Str(hr[i]) : "";
                var skin = i < sk.Size() ? GD.Str(sk[i]) : "";
                if (is_me)
                {
                    hero = my_hero != "" ? my_hero : hero;        // (mine I know: the server may be older)
                    skin = my_hero != "" ? my_skin : skin;
                }
                else if (hero != "" && !Moba.HEROES.ContainsKey(hero))
                    hero = "";
                var key = is_me ? "me" : GD.Fmt("%s#%d", raw, seen[raw]);
                list.Append(GDict.Of("key", key, "name", shown, "hero", hero, "skin", skin, "me", is_me, "unknown", hero == ""));
            }
            if (me < 0 && my_hero != "")
                list.PushFront(GDict.Of("key", "me", "name", my_name != "" ? my_name : "You", "hero", my_hero, "skin", my_skin, "me", true));
            _SetLineup(list);
            _first = false;
        }

        public void Note(string t)
        {
            note_text = t;
            if (sub_lbl != null)
                sub_lbl.Text = t;
        }

        public void Fail(string why)
        {
            state = "failed";
            _fail_why = why;
            if (_built)
                _ApplyFail();
        }

        public void _ApplyFail()
        {
            title.Text = "CAN'T JOIN";
            title.AddThemeColorOverride("font_color", new Color("#ff6b5e"));
            number.Text = "";
            mode_lbl.Text = _fail_why;
            sub_lbl.Text = "Back to the menu...";
            ring.QueueRedraw();
        }

        public void Loading()
        {
            // the battle's being built behind this (siege_mode's loading card): no countdown, no LEAVE
            state = "loading";
            ZIndex = 100;
            if (_built)
                _ApplyLoading();
        }

        public void _ApplyLoading()
        {
            number.Text = "";                               // (the ring spins)
            count_row.Visible = false;
            leave_btn.Visible = false;
            leave_btn.Disabled = true;
            title.Text = "PREPARING THE BATTLEFIELD";
            title.AddThemeFontSizeOverride("font_size", 18);
            mode_lbl.Visible = false;
            sub_lbl.Visible = false;
        }

        // ---------------- clock ----------------
        protected override void _Process(double delta)
        {
            _spin += delta;
            if (!_built)
                return;
            if (state == "lobby")
            {
                left = GD.Maxf(0.0, left - delta);
                var sec = GD.Int(GD.Ceil(left));
                if (sec != _last_sec)
                {
                    number.Text = GD.Str(sec);
                    if (_last_sec >= 0 && sec < _last_sec)
                    {
                        // each second lands with a little punch; the last five tick (and go orange)
                        number.Scale = sec <= 5 ? new Vector2(1.22, 1.22) : new Vector2(1.1, 1.1);
                        number.CreateTween().TweenProperty(number, "scale", Vector2.ONE, 0.3).SetTrans(Tween.TRANS_BACK).SetEase(Tween.EASE_OUT);
                        if (sec <= 5 && sec >= 1)
                            _Sfx("countdown");
                    }
                    number.AddThemeColorOverride("font_color", sec <= 5 ? new Color("#ffd2a8") : Color.WHITE);
                    _last_sec = sec;
                }
                if (left <= 0.0)
                    title.Text = "STARTING";
            }
            _StepFigs(delta);
            _cam_d = GD.Lerpf(_cam_d, _cam_want, 1.0 - Math.Exp(-delta * 3.0));
            _cam_z = GD.Lerpf(_cam_z, _cam_z_want, 1.0 - Math.Exp(-delta * 3.0));
            _cam_lift = GD.Lerpf(_cam_lift, _cam_lift_want, 1.0 - Math.Exp(-delta * 3.0));
            _PlaceCam();
            _PlacePlates();
            if (ring.Visible)
                ring.QueueRedraw();
        }

        public void _DrawRing()
        {
            var c = ring.Size * 0.5;
            var r = GD.Minf(c.x, c.y) - 5.0;
            ring.DrawCircle(c, r + 4.0, new Color(0.03, 0.02, 0.06, 0.62));
            ring.DrawArc(c, r, 0.0, GD.TAU, 64, new Color(1, 1, 1, 0.14), 6.0, true);
            if (state == "connecting" || state == "loading")
            {
                var a = _spin * 4.0;
                ring.DrawArc(c, r, a, a + 1.6, 24, GOLD, 6.0, true);
            }
            else if (state == "lobby")
            {
                var f = GD.Clampf(left / wait, 0.0, 1.0);
                var col = left <= 5.0 ? HOT : GOLD;
                if (f > 0.0)
                    ring.DrawArc(c, r, -GD.PI * 0.5, -GD.PI * 0.5 + GD.TAU * f, GD.Maxi(8, GD.Int(64 * f)), col, 6.0, true);
            }
            else if (state == "failed")
                ring.DrawArc(c, r, 0.0, GD.TAU, 64, new Color("#ff6b5e"), 6.0, true);
        }
    }
}
