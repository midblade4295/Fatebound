// Ported from godot/scripts/app/herald_intro.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector4 = Fatebound.Sim.Vec4;
using Color = Fatebound.GUI.Col;
using Tut = Fatebound.Game.Tutorial;
using VisualTheme = Fatebound.Game.VisualTheme;
using UI = Fatebound.Game.Ui;
using UI2 = Fatebound.Game.Ui2;
using Profile = Fatebound.Game.Profile;

namespace Fatebound.Game
{
    // 0.31.198 THE HERALD'S WELCOME (Kevin, with the server wiped so everyone starts fresh: "Have the game ask their name and
    // after they do that it'll briefly say what game is and then ask if they would like to play tutorial. Make the tutorial
    // guy pop up while doing this and voice it. Do the same type of messages and model like he is in tutorial. Make it very
    // funny"; and "Also have him briefly take player through menus").
    // On Home, for a player with no name yet (the profile's "Player": a new install, or anyone after the wipe), the Royal
    // Herald pops up with his proclamation scroll exactly as in the tutorial (scripts/siege/tutorial.gd: his eight poses,
    // each line typed out on the parchment as he says it, TAP TO CONTINUE): he asks the player's name (a field over the
    // scroll; a few names get a word from him, unvoiced), announces it, says what Fatebound is, walks them round Home
    // (PLAY, the chests, SHOP, PASS, ARMORY (0.31.204: was LOCKER), ALLIANCE, the menu: the shade lifts off each in turn, ringed and labelled, the
    // scroll at the top of the screen while what he shows is below), then offers the tutorial -- SHOW ME HOW
    // (siege_app.start_tutorial) or I'LL WING IT (Home). VOICE: assets/vo/tutorial/intro_*.ogg and tour_*.ogg, his voice
    // (ElevenLabs; art_sources/tutorial/intro_script.json, tools/build_tutorial_assets.py). The captions are that script's
    // lines without their spoken [directions] (tests/herald_intro_test.gd checks).
    public class HeraldIntro : Control
    {
        public const string VO_DIR = "res://assets/vo/tutorial/";
        public const int NAME_MAX = 16;
        public const string DEFAULT_NAME = "Player";                // (Profile.defaults: no name chosen yet)
        public static readonly Color GOLD = Color.FromCode("#ffd257");                // (frames and rings only: no yellow text -- 0.31.195)
        public static readonly Color INK = Color.FromCode("#2a1604");

        // [voice id, caption, pose]; the flow: hello -> (the name) -> named -> what -> the tour -> ask -> (the choice) -> yes / no
        public static readonly GDict LINES = new GDict
        {
            { "hello", GArray.Of("intro_hello", "Oh! Hello. Didn't see you there. I'm the Royal Herald. I announce people. Which is awkward, because I have no idea who you are. What's your name? And do pick something I can say out loud. In public. Near children.", "peeking") },
            { "named", GArray.Of("intro_named", "Hear ye, hear ye! Presenting... that. Lovely. I've written it on the royal scroll. In permanent ink. I've regretted that before.", "hold") },
            { "what", GArray.Of("intro_what", "Right. This is Fatebound. Five heroes versus five. Three lanes. Two castles. Each with a King sitting on a very comfortable chair. Knock their King off his chair, keep ours on his, and try not to die in ways I'll have to announce.", "lying") },
            { "tour_play", GArray.Of("tour_play", "First, the big button. PLAY. It throws you straight into a battle. It is the most important button in the kingdom. Please don't sit on it.", "pointing") },
            { "tour_chests", GArray.Of("tour_chests", "Win, and you'll earn chests. They wait down here, unlocking slower than a royal tax refund. Then, gold, gems, and the odd hero shard.", "leaning") },
            { "tour_shop", GArray.Of("tour_shop", "The Shop. Heroes, outfits, gems. Everything a growing hero needs, and several things he doesn't.", "hold") },
            { "tour_pass", GArray.Of("tour_pass", "The Pass. Play matches, climb its tiers, collect prizes. It's a ladder. Made of presents.", "sitting") },
            { "tour_locker", GArray.Of("tour_locker", "Your Armory. Your heroes, their outfits, your titles. Dress to impress. Or at least to intimidate.", "peeking") },
            { "tour_alliance", GArray.Of("tour_alliance", "Alliance. Friends, parties, and your clan. Five of you on one side. The enemy hates it. I adore it.", "hanging") },
            { "tour_menu", GArray.Of("tour_menu", "And up here, the menu. Daily orders, quests, the rankings, and my lessons. Do read the orders. They pay. I don't.", "lying") },
            { "ask", GArray.Of("intro_ask", "Now. I could teach you the basics. It's quick, it's mostly painless, and there's gold at the end. Or you can skip it and learn by losing. Loudly. In front of everyone. Your call.", "pointing") },
            { "yes", GArray.Of("intro_yes", "Excellent. A recruit with sense. That's a first. Follow me, and mind the King's chair. He's very particular about it.", "hold") },
            { "no", GArray.Of("intro_no", "Bold. Foolish, but bold. If you change your mind, the lessons are in the menu. I'll be right here. Napping. Heroically.", "napping") },
        };
        public static readonly GDict NEXT = new GDict { { "named", "what" }, { "what", "tour_play" }, { "tour_play", "tour_chests" }, { "tour_chests", "tour_shop" },
            { "tour_shop", "tour_pass" }, { "tour_pass", "tour_locker" }, { "tour_locker", "tour_alliance" }, { "tour_alliance", "tour_menu" },
            { "tour_menu", "ask" } };
        // the tour: what each line shows (a button's action_key, or "@<meta>" for every node carrying that meta), its label, and
        // (if not the side away from the screen's edge) where the arrow and label go
        public static readonly GDict TOUR = new GDict
        {
            { "tour_play", GArray.Of("play", "PLAY") },
            { "tour_chests", GArray.Of("@chest_plate", "CHESTS", "below") },          // (above them is PLAY)
            { "tour_shop", GArray.Of("tab_shop", "SHOP") },
            { "tour_pass", GArray.Of("tab_pass", "PASS") },
            { "tour_locker", GArray.Of("tab_locker", "ARMORY") },         // (0.31.204: the Locker renamed, his line voiced again)
            { "tour_alliance", GArray.Of("tab_alliance", "ALLIANCE") },
            { "tour_menu", GArray.Of("home_menu", "MENU") },
        };
        // a word from him for some names (written, not voiced: the name field stays up)
        public static readonly GDict NAME_QUIPS = new GDict
        {
            { "", "The quill refuses to write nothing. It has tried before. Nobody noticed." },
            { "player", "'Player'? That's what I call people I've forgotten. Try again." },
            { "herald", "There's room for one Herald in this kingdom. It's me. Pick another." },
            { "royal herald", "Flattering. Still me, though. Pick another." },
            { "king", "The King is busy sitting on his chair. You can be someone else." },
            { "admin", "Nice try. The royal records have seen that trick. Twice today." },
        };
        // the shade, with a hole where the tour is looking (soft-edged, rounded)
        public const string SHADE_CODE = "\n" +
            "shader_type canvas_item;\n" +
            "uniform vec2 size = vec2(1.0, 1.0);\n" +
            "uniform vec4 hole = vec4(0.0);                 // x, y, w, h in px (w 0: none)\n" +
            "uniform float radius = 18.0;\n" +
            "uniform float soft = 8.0;\n" +
            "uniform vec4 shade : source_color = vec4(0.0, 0.01, 0.04, 0.6);\n" +
            "void fragment() {\n" +
            "\tvec2 p = UV * size;\n" +
            "\tfloat a = shade.a;\n" +
            "\tif (hole.z > 0.5) {\n" +
            "\t\tvec2 h = hole.zw * 0.5;\n" +
            "\t\tfloat r = min(radius, min(h.x, h.y));\n" +
            "\t\tvec2 q = abs(p - (hole.xy + h)) - (h - vec2(r));\n" +
            "\t\tfloat d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;\n" +
            "\t\ta *= smoothstep(-1.0, soft, d);\n" +
            "\t}\n" +
            "\tCOLOR = vec4(shade.rgb, a);\n" +
            "}\n";

        public SiegeApp app;
        public string step = "";
        public double shown = 0.0;
        public string pose = "";
        public GArray lines_said = new GArray();                  // (tests) every line id shown, in order
        public string quip = "";                              // a written word about the name (no voice), shown instead of the line
        public double _time = 0.0;
        public GDict _pose_tex = new GDict();
        public AudioStreamPlayer voice;
        public ColorRect dim;
        public Control marker;
        public TextureRect scroll;
        public Label text_label;
        public Label hint_label;
        public Control name_box;
        public LineEdit name_edit;
        public Control choice_box;
        public Label banner;
        public double _kb = 0.0;
        public Rect2 hole_want = new Rect2();                    // where the tour is looking (this control's px; empty: nowhere)
        public Rect2 hole_now = new Rect2();                     // ...and the shade's hole on its way there
        public bool at_top = false;                         // the scroll at the top of the screen (what he shows is below)
        public double _y_off = 0.0;                           // the scroll's way to its place, eased off
        public double _y_last = double.NaN;

        public void Open(SiegeApp a)
        {
            app = a;
            SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            voice = new AudioStreamPlayer();
            voice.Bus = "Master";
            AddChild(voice);
            dim = new ColorRect();
            var sh = new Shader();
            sh.Code = SHADE_CODE;
            var sm = new ShaderMaterial();
            sm.Shader = sh;
            dim.Material = sm;
            dim.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            dim.MouseFilter = Control.MOUSE_FILTER_STOP;
            dim.GuiInput += (InputEvent e) =>
            {
                if ((e is InputEventScreenTouch && e.IsPressed()) || (e is InputEventMouseButton mb && mb.Pressed && mb.ButtonIndex == MouseButton.Left))
                {
                    AcceptEvent();
                    Next();
                }
            };
            AddChild(dim);
            var mk = new Marker();
            marker = mk;
            mk.intro = this;
            marker.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            marker.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(marker);
            scroll = new TextureRect();
            scroll.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            scroll.StretchMode = TextureRect.STRETCH_SCALE;
            scroll.TextureFilter = TextureFilterMode.LinearWithMipmaps;
            scroll.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(scroll);
            text_label = new Label();
            text_label.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
            text_label.AddThemeFontOverride("font", VisualTheme.BOLD_FONT);
            text_label.AddThemeFontSizeOverride("font_size", 16);
            text_label.AddThemeColorOverride("font_color", Tut.INK_TEXT);
            text_label.AddThemeConstantOverride("line_spacing", Tut.LINE_GAP);
            text_label.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(text_label);
            hint_label = new Label();
            hint_label.Text = "TAP TO CONTINUE  >";
            hint_label.AddThemeFontOverride("font", VisualTheme.BOLD_FONT);
            hint_label.AddThemeFontSizeOverride("font_size", 12);
            hint_label.AddThemeColorOverride("font_color", Color.WHITE);
            hint_label.AddThemeColorOverride("font_outline_color", new Color(0, 0, 0, 0.8));
            hint_label.AddThemeConstantOverride("outline_size", 4);
            hint_label.HorizontalAlignment = HorizontalAlignment.Right;
            hint_label.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(hint_label);
            // the name, announced: big over the scroll
            banner = new Label();
            banner.AddThemeFontOverride("font", UI2.LG);
            banner.AddThemeFontSizeOverride("font_size", 34);
            banner.AddThemeColorOverride("font_color", Color.WHITE);
            banner.AddThemeColorOverride("font_outline_color", Color.FromCode("#5a3208"));
            banner.AddThemeConstantOverride("outline_size", 12);
            banner.HorizontalAlignment = HorizontalAlignment.Center;
            banner.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            banner.Visible = false;
            AddChild(banner);
            _BuildNameBox();
            _BuildChoiceBox();
            // he pops up: the scroll rises into place
            { var mc = scroll.Modulate; mc.a = 0.0f; scroll.Modulate = mc; }
            { var mc = text_label.Modulate; mc.a = 0.0f; text_label.Modulate = mc; }
            _Say("hello");
            _y_off = 300.0;
            var tw = CreateTween().SetParallel(true);
            tw.TweenProperty(scroll, "modulate:a", 1.0, 0.25);
            tw.TweenProperty(text_label, "modulate:a", 1.0, 0.25);
            if (app != null)
                app.Sfx("menuOpen");
        }

        public void _BuildNameBox()
        {
            name_box = new PanelContainer();
            var sb = new StyleBoxFlat();
            sb.BgColor = Color.FromCode("#fff4dc");
            sb.BorderColor = Color.FromCode("#6b4420");
            sb.SetBorderWidthAll(3);
            sb.SetCornerRadiusAll(16);
            sb.ContentMarginLeft = 14;
            sb.ContentMarginRight = 14;
            sb.ContentMarginTop = 10;
            sb.ContentMarginBottom = 12;
            sb.ShadowColor = new Color(0, 0, 0, 0.5);
            sb.ShadowSize = 10;
            name_box.AddThemeStyleboxOverride("panel", sb);
            name_box.Visible = false;
            AddChild(name_box);
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", 8);
            name_box.AddChild(v);
            var t = new Label();
            t.Text = "WHAT SHALL THE HERALD CALL YOU?";
            t.AddThemeFontOverride("font", UI2.LG);
            t.AddThemeFontSizeOverride("font_size", 15);
            t.AddThemeColorOverride("font_color", Color.FromCode("#7a3c14"));
            t.HorizontalAlignment = HorizontalAlignment.Center;
            v.AddChild(t);
            var r = new HBoxContainer();
            r.AddThemeConstantOverride("separation", 8);
            v.AddChild(r);
            name_edit = new LineEdit();
            name_edit.MaxLength = NAME_MAX;
            name_edit.PlaceholderText = "Your name";
            name_edit.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            name_edit.CustomMinimumSize = new Vector2(0, 46);
            name_edit.AddThemeFontOverride("font", UI.HEAVY_FONT);
            name_edit.AddThemeFontSizeOverride("font_size", 18);
            name_edit.AddThemeColorOverride("font_color", Color.FromCode("#3e2610"));
            name_edit.AddThemeColorOverride("font_placeholder_color", new Color(0.24, 0.15, 0.06, 0.45));
            name_edit.AddThemeColorOverride("caret_color", Color.FromCode("#3e2610"));
            var es = new StyleBoxFlat();
            es.BgColor = Color.FromCode("#ffffff");
            es.BorderColor = Color.FromCode("#a8763c");
            es.SetBorderWidthAll(2);
            es.SetCornerRadiusAll(10);
            es.ContentMarginLeft = 12;
            es.ContentMarginRight = 12;
            name_edit.AddThemeStyleboxOverride("normal", es);
            name_edit.AddThemeStyleboxOverride("focus", es);
            name_edit.TextSubmitted += (_t) => SubmitName(name_edit.Text);
            r.AddChild(name_edit);
            var ok = UI2.Button(r, "THAT'S ME", "green", () => SubmitName(name_edit.Text), "intro_name_ok", 15, 46.0, 12.0);
            { var cm = ok.CustomMinimumSize; cm.x = 112; ok.CustomMinimumSize = cm; }
        }

        public void _BuildChoiceBox()
        {
            choice_box = new VBoxContainer();
            (choice_box as VBoxContainer).AddThemeConstantOverride("separation", 10);
            choice_box.Visible = false;
            AddChild(choice_box);
            UI2.Button(choice_box, "SHOW ME HOW", "green", () => Choose(true), "intro_tutorial_yes", 20, 58.0, 16.0);
            UI2.Button(choice_box, "I'LL WING IT", "blue", () => Choose(false), "intro_tutorial_no", 16, 46.0, 14.0);
        }

        // ---------------- the lines ----------------
        public static GArray LineOf(string id)
        {
            return LINES.Get(id, GArray.Of("", "", "hold")).A;
        }

        public void _Say(string id)
        {
            step = id;
            quip = "";
            shown = 0.0;
            var l = LineOf(id);
            lines_said.Append(GD.Str(l[0]));
            _SetPose(GD.Str(l[2]));
            text_label.Text = GD.Str(l[1]);
            _Play(GD.Str(l[0]));
            name_box.Visible = false;
            choice_box.Visible = false;
            banner.Visible = id == "named";
            if (id == "named")
            {
                banner.Text = GD.Fmt("★ %s ★", GD.Str(app != null ? app.profile.d["name"] : (Var)"").ToUpperInvariant());
                banner.PivotOffset = new Vector2(banner.Size.x * 0.5, 20.0);
                banner.Scale = new Vector2(0.4, 0.4);
                CreateTween().TweenProperty(banner, "scale", Vector2.ONE, 0.35).SetTrans(Tween.TRANS_BACK).SetEase(Tween.EASE_OUT);
                if (app != null)
                    app.Sfx("confirm");
            }
            else if (TOUR.Has(id) && app != null)
                app.Sfx("tap");
            _Aim();
            _Layout();
        }

        public void _Play(string id)
        {
            voice.Stop();
            if (app == null || app.audio == null)
                return;
            var master = (double)app.audio.levels.Get("master", 1.0);
            var muted = app.audio.muted;
            var p = VO_DIR + id + ".ogg";
            if (id != "" && !muted && master > 0.0 && ResourceLoader.Exists(p))
            {
                voice.Stream = ResourceLoader.Load<AudioStream>(p);
                voice.VolumeDb = GD.LinearToDb(master * Tut.VOICE_GAIN);
                voice.Play();
            }
        }

        public void _SetPose(string p)
        {
            if (p == pose)
                return;
            pose = p;
            if (!_pose_tex.Has(p))
            {
                var path = GD.Fmt(Tut.POSE_PATH, p);
                _pose_tex[p] = ResourceLoader.Exists(path) ? Var.Of(ResourceLoader.Load<Texture2D>(path)) : Var.Nil;
            }
            scroll.Texture = _pose_tex[p].As<Texture2D>();
            // he changes how he's holding it: the scroll pops a little
            GDict r = Tut.ScrollRects(p, Size);
            scroll.PivotOffset = new Vector2(((Rect2)r["art"]).size.x * 0.5, ((Rect2)r["art"]).size.y);
            scroll.Scale = new Vector2(0.94, 0.94);
            var tw = CreateTween();
            tw.TweenProperty(scroll, "scale", Vector2.ONE, 0.22).SetTrans(Tween.TRANS_BACK).SetEase(Tween.EASE_OUT);
        }

        public bool Typed()
        {
            return shown >= (double)text_label.Text.Length;
        }

        public void Next()
        {
            // a tap: the line typed out first; then on (the name and the choice wait for their own buttons)
            if (!Typed())
            {
                shown = 9999.0;
                return;
            }
            switch (step)
            {
                case "hello":
                    _AskName();
                    break;
                case "ask":
                    choice_box.Visible = true;
                    break;
                case "yes":
                case "no":
                    _Done();
                    break;
                default:
                    if (NEXT.Has(step))
                        _Say(GD.Str(NEXT[step]));
                    break;
            }
        }

        public void _AskName()
        {
            name_box.Visible = true;
            _Layout();
            name_edit.GrabFocus();
            if (DisplayServer.HasFeature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD))
                DisplayServer.VirtualKeyboardShow(name_edit.Text);
        }

        public static string NameQuip(string n)
        {
            // what he says to a name he won't write ("" for a name he will)
            var k = n.StripEdges().ToLowerInvariant();
            if (NAME_QUIPS.Has(k))
                return GD.Str(NAME_QUIPS[k]);
            return "";
        }

        public void SubmitName(string raw)
        {
            if (step != "hello")
                return;
            var n = Profile.CleanName(raw).Left(NAME_MAX);
            var q = NameQuip(n);
            if (q != "")
            {
                quip = q;
                text_label.Text = q;
                shown = 0.0;
                _SetPose("leaning");
                voice.Stop();
                if (app != null)
                    app.Sfx("error");
                _Layout();
                return;
            }
            if (app != null)
            {
                app.profile.SetName(n);                     // (an op: the server has it too)
                app.RefreshTop();
            }
            if (DisplayServer.HasFeature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD))
                DisplayServer.VirtualKeyboardHide();
            name_edit.ReleaseFocus();
            _Say("named");
        }

        public void Choose(bool tutorial)
        {
            if (step != "ask")
                return;
            if (app != null)
                app.Sfx(tutorial ? "confirm" : "tap");
            _Say(tutorial ? "yes" : "no");
        }

        public void _Done()
        {
            voice.Stop();
            var tutorial = step == "yes";
            if (app == null)
            {
                QueueFree();
                return;
            }
            app.CloseModal();
            if (tutorial)
                app.StartTutorial();
            else
            {
                app.Toast("The tutorial waits in the menu at the top, whenever you want it", UI.CYAN);
                app.CallDeferred(app.OfferDaily);
            }
        }

        // ---------------- the tour ----------------
        public Rect2 TargetRect(string key)
        {
            // what the tour shows, in this control's px: the button with that action_key on the screen (or, "@meta", every node
            // carrying that meta, together); empty if it isn't there
            if (app == null)
                return new Rect2();
            var found = new GArray();
            _Find(app, key, found);
            var @out = new Rect2();
            foreach (var n in found)
            {
                Rect2 g = n.As<Control>().GetGlobalRect();
                @out = @out.HasArea() == false ? g : @out.Merge(g);
            }
            if (!@out.HasArea())
                return new Rect2();
            @out.position -= GetGlobalRect().position;
            return @out;
        }

        public void _Find(Node n, string key, GArray @out)
        {
            if (n == this)
                return;
            if (n is Control && (n as Control).IsVisibleInTree())
            {
                var hit = false;
                if (key.BeginsWith("@"))
                    hit = n.HasMeta(key.Substr(1));
                else
                    hit = GD.Str(Var.Of(n.GetMeta("action_key", ""))) == key;
                if (hit)
                {
                    @out.Append(n);
                    if (!key.BeginsWith("@"))
                        return;
                }
            }
            foreach (var c in n.GetChildren())
            {
                _Find(c, key, @out);
                if (!key.BeginsWith("@") && !@out.IsEmpty())
                    return;
            }
        }

        public string TourKey()
        {
            return TOUR.Has(step) ? GD.Str(TOUR[step][0]) : "";
        }

        public string TourLabel()
        {
            return TOUR.Has(step) ? GD.Str(TOUR[step][1]) : "";
        }

        public string TourSide()
        {
            return TOUR.Has(step) && TOUR[step].Size() > 2 ? GD.Str(TOUR[step][2]) : "";
        }

        public void _Aim()
        {
            // where the shade opens, and where the scroll goes (out of its way)
            var k = TourKey();
            var r = k != "" ? TargetRect(k) : new Rect2();
            if (r.HasArea())
            {
                r = r.Grow(8.0);
                if (!hole_now.HasArea())
                    hole_now = new Rect2(r.GetCenter(), Vector2.ZERO);   // (it opens out of the middle of the thing)
                at_top = r.GetCenter().y > Size.y * 0.42;
            }
            else
                at_top = false;
            hole_want = r;
        }

        // ---------------- every frame ----------------
        protected override void _Process(double delta)
        {
            _time += delta;
            var full = text_label.Text.Length;
            if (shown < 9000.0)
                shown = GD.Minf(shown + delta * Tut.TYPE_CPS, (double)full);
            text_label.VisibleCharacters = shown >= (double)full ? -1 : GD.Int(shown);
            var waiting = name_box.Visible || choice_box.Visible;
            hint_label.Visible = !waiting;
            { var mc = hint_label.Modulate; mc.a = (float)(Typed() && !voice.Playing ? (0.55 + 0.45 * GD.Sin(_time * 5.0)) : 0.35); hint_label.Modulate = mc; }
            if (step == "ask" && Typed() && !choice_box.Visible && !voice.Playing)
                choice_box.Visible = true;                   // (the choice comes up once he's asked)
            var kh = (double)DisplayServer.VirtualKeyboardGetHeight();
            var want = 0.0;
            if (kh > 0.0)
                want = kh * (GetViewportRect().size.y / GD.Maxf(1.0, (double)DisplayServer.WindowGetSize().y));
            if (GD.Absf(want - _kb) > 1.0)
                _kb = want;
            // the shade's hole: on its way to what's shown (the layout may move under it), or shut
            if (TOUR.Has(step))
                _Aim();
            var goal = hole_want;
            if (!goal.HasArea() && hole_now.HasArea())
                goal = new Rect2(hole_now.GetCenter(), Vector2.ZERO);
            var e = 1.0 - GD.Exp(-delta * 10.0);
            hole_now = new Rect2(hole_now.position.Lerp(goal.position, e), hole_now.size.Lerp(goal.size, e));
            if (!hole_want.HasArea() && hole_now.size.Length() < 3.0)
                hole_now = new Rect2();
            var m = dim.Material as ShaderMaterial;
            m.SetShaderParameter("size", Size);
            m.SetShaderParameter("hole", hole_now.HasArea() ? new Vector4(hole_now.position.x, hole_now.position.y, hole_now.size.x, hole_now.size.y) : Vector4.ZERO);
            _y_off = GD.MoveToward(_y_off, 0.0, GD.Maxf(700.0, GD.Absf(_y_off) * 9.0) * delta);
            marker.QueueRedraw();
            _Layout();
        }

        public void _Layout()
        {
            if (scroll == null || Size.x <= 0.0)
                return;
            GDict r = Tut.ScrollRects(pose != "" ? pose : "hold", Size);
            Rect2 art = (Rect2)r["art"];
            Rect2 tr = (Rect2)r["text"];
            var top_y = 10.0 + (app != null ? (double)app.safe_top : 0.0);
            var dy = at_top ? (top_y - art.position.y) : 0.0;
            var want_y = art.position.y + dy;
            if (!double.IsNaN(_y_last) && GD.Absf(want_y - _y_last) > 0.5)
                _y_off += _y_last - want_y;                  // (from where it was: it slides there)
            _y_last = want_y;
            scroll.Position = new Vector2(art.position.x, want_y + _y_off);
            scroll.Size = art.size;
            text_label.Position = tr.position + new Vector2(0, dy + _y_off);
            text_label.Size = tr.size;
            text_label.AddThemeFontSizeOverride("font_size", Tut.FitPx(text_label.Text, tr.size));
            var foot = Size.y - Tut.SCROLL_BOTTOM + 13.0;
            if (at_top)
                foot = GD.Minf(art.End.y + dy + 2.0, Size.y - 30.0);
            hint_label.Position = new Vector2(Size.x * 0.5, foot + _y_off);
            hint_label.Size = new Vector2(Size.x * 0.5 - Tut.SCROLL_SIDE, 18);
            var top = art.position.y + dy;
            var w = GD.Minf(Size.x - 32.0, 420.0);
            banner.Size = new Vector2(Size.x - 24.0, 46.0);
            banner.Position = new Vector2(12.0, top - 64.0 + _y_off);
            name_box.Size = new Vector2(w, 0);
            name_box.ResetSize();
            double nb_h = name_box.Size.y;
            var ny = top - nb_h - 18.0;
            if (_kb > 0.0)
                ny = GD.Minf(ny, Size.y - _kb - nb_h - 12.0);
            name_box.Position = new Vector2((Size.x - w) * 0.5, GD.Maxf(12.0 + (app != null ? (double)app.safe_top : 0.0), ny));
            choice_box.Size = new Vector2(w, 0);
            choice_box.ResetSize();
            choice_box.Position = new Vector2((Size.x - w) * 0.5, top - choice_box.Size.y - 18.0);
            // (Unity port, Kevin: "Training text gets cutoff" -- in landscape the Herald stands so tall that above him the
            // choice ran off the top of the screen, SHOW ME HOW half gone; the same in Godot 0.31.222. Then it goes
            // beside him instead: over the right of the parchment, clear of his figure on its left)
            double min_y = 12.0 + (app != null ? (double)app.safe_top : 0.0);
            if (choice_box.Position.y < min_y)
            {
                Rect2 parch = (Rect2)r["parch"];
                double cy = GD.Maxf(min_y, parch.position.y + dy - choice_box.Size.y - 18.0);
                choice_box.Position = new Vector2(parch.End.x - choice_box.Size.x - 24.0, cy + _y_off);
            }
        }

        // the ring round what the tour shows, an arrow at it and its name
        public class Marker : Control
        {
            public HeraldIntro intro;
            public StyleBoxFlat _ring;
            public StyleBoxFlat _ink;

            protected override void _Ready()
            {
                _ring = new StyleBoxFlat();
                _ring.DrawCenter = false;
                _ring.BorderColor = GOLD;
                _ring.SetBorderWidthAll(4);
                _ring.SetCornerRadiusAll(16);
                _ink = _ring.Duplicate() as StyleBoxFlat;
                _ink.BorderColor = INK;
                _ink.SetBorderWidthAll(9);
                _ink.SetCornerRadiusAll(19);
            }

            protected override void _Draw()
            {
                if (intro == null || !intro.hole_want.HasArea() || !intro.hole_now.HasArea())
                    return;
                var pulse = 0.5 + 0.5 * GD.Sin((double)intro._time * 5.0);
                Rect2 r = intro.hole_now.Grow(2.0 + 4.0 * pulse);
                _ink.Draw(GetCanvasItem(), r.Grow(2.5));
                _ring.Draw(GetCanvasItem(), r);
                if (intro.hole_now.size.DistanceTo(intro.hole_want.size) > 12.0)
                    return;                                  // (the arrow and name once it's there)
                bool down = r.GetCenter().y > Size.y * 0.5;     // (below the middle: the arrow comes from above)
                var side = GD.Str(intro.TourSide());
                if (side != "")
                    down = side == "above";
                var x = GD.Clampf(r.GetCenter().x, 40.0, Size.x - 40.0);
                var tip = down ? new Vector2(x, r.position.y - 6.0 - 10.0 * pulse) : new Vector2(x, r.End.y + 6.0 + 10.0 * pulse);
                _Arrow(tip, 1.0, !down);
                _Plate(tip + new Vector2(0, down ? -74.0 : 74.0), GD.Str(intro.TourLabel()));
            }

            public void _Arrow(Vector2 tip, double s, bool up = false)
            {
                // a fat outlined arrow pointing down at tip (or up) -- the tutorial's
                var k = up ? -1.0 : 1.0;
                var pts = new List<Vector2> { tip, tip + new Vector2(-22, -26 * k) * s, tip + new Vector2(-9, -26 * k) * s, tip + new Vector2(-9, -52 * k) * s,
                    tip + new Vector2(9, -52 * k) * s, tip + new Vector2(9, -26 * k) * s, tip + new Vector2(22, -26 * k) * s };
                var c = Vector2.ZERO;
                foreach (var q in pts)
                    c += q;
                c /= pts.Count;
                var @out = new List<Vector2>();
                foreach (var q in pts)
                    @out.Add(c + (q - c) * 1.18);
                DrawColoredPolygon(@out, INK);
                DrawColoredPolygon(pts, GOLD);
            }

            public void _Plate(Vector2 center, string text)
            {
                Font font = UI2.LG;
                var fs = 18;
                var w = font.GetStringSize(text, HorizontalAlignment.Left, -1, fs).x + 26.0;
                var r = new Rect2(GD.Clampf(center.x - w * 0.5, 6.0, Size.x - 6.0 - w), center.y - 16, w, 32);
                DrawRect(r.Grow(2), INK);
                DrawRect(r, new Color(0.12, 0.09, 0.03, 0.95));
                DrawRect(new Rect2(r.position, new Vector2(r.size.x, 3)), GOLD);
                DrawString(font, new Vector2(r.position.x + 13, r.position.y + 23), text, HorizontalAlignment.Left, -1, fs, Color.WHITE);
            }
        }
    }
}
