// Ported from godot/scripts/app/training_pick.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Color = Fatebound.GUI.Col;
using UI = Fatebound.Game.Ui;
using UI2 = Fatebound.Game.Ui2;
using SocialUI = Fatebound.Game.SocialUi;
using Kits = Fatebound.Sim.MobaKits;
using Moba = Fatebound.Sim.Moba;
using Eco = Fatebound.Game.Economy;

namespace Fatebound.Game
{
    // 0.31.217 TRAINING (Kevin, with a recording of Honor of Kings' first launch: "Here is how I want the training to go in
    // fatebound"): which training -- 1 THE BASICS or 2 5V5 BATTLE -- and a hero of three (Honor of Kings' pick of three), Kael
    // the Dragoon beside them; BATTLE -> siege_app.start_training. The menu's TUTORIAL, the Herald's first-run intro and
    // Settings' HOW TO PLAY open it (siege_app.start_tutorial). The match itself: scripts/siege/training.gd.
    public class TrainingPick : Control
    {
        public const string KAEL = "res://assets/ui/skins/default_dragoon.png";
        // the three to pick from: a tank for the top lane, a mage for the middle, a marksman for the bottom
        public static readonly GArray HEROES = GArray.Of(GArray.Of("knight", "TANK", "Top lane"), GArray.Of("mage", "MAGE", "Middle lane"), GArray.Of("ranger", "MARKSMAN", "Bottom lane"));
        public static readonly GArray TRAININGS = GArray.Of(
            GArray.Of("1", "THE BASICS", "Move, fight, learn your skills, buy from the quick-buy, break the towers and the King."),
            GArray.Of("2", "5V5 BATTLE", "The Rift's lanes and who goes where, how towers fight -- then a real match, Kael beside you."));

        public SiegeApp app;
        public int which = 1;
        public string hero = "knight";
        public GArray _cards = new GArray();           // the two trainings' buttons
        public GArray _heroes = new GArray();          // the three heroes' buttons
        public Label _say;

        public void Open(SiegeApp a)
        {
            app = a;
            var done = app.profile != null ? (bool)app.profile.d.Get("tutorial_done", false) : false;
            which = done ? 2 : 1;
            var saved = app.profile != null ? GD.Str(app.profile.d["settings"].Get("moba_hero", "")) : "";
            foreach (var h in HEROES)
            {
                if (GD.Str(h[0]) == saved)
                    hero = saved;
            }
            var w = SocialUI.Window(this, "TRAINING", "horn", () =>
            {
                app.Sfx("menuClose");
                app.CloseModal();
            }, 6.0 + (double)app.safe_top, 8.0);
            VBoxContainer sheet = w["body"].As<VBoxContainer>();
            var cols = new HBoxContainer();
            cols.AddThemeConstantOverride("separation", 14);
            cols.SizeFlagsVertical = Control.SIZE_EXPAND_FILL;
            sheet.AddChild(cols);
            // Kael, on the left
            var left = new VBoxContainer();
            left.AddThemeConstantOverride("separation", 4);
            left.CustomMinimumSize = new Vector2(150, 0);
            cols.AddChild(left);
            var face = new Panel();
            face.CustomMinimumSize = new Vector2(120, 120);
            face.SizeFlagsHorizontal = Control.SIZE_SHRINK_CENTER;
            var fs = new StyleBoxFlat();
            fs.BgColor = new Color(0.85, 0.72, 0.42);
            fs.SetCornerRadiusAll(60);
            fs.BorderColor = UI2.GOLD;
            fs.SetBorderWidthAll(3);
            fs.AntiAliasing = true;
            face.AddThemeStyleboxOverride("panel", fs);
            face.ClipChildren = CanvasItem.CLIP_CHILDREN_AND_DRAW;
            left.AddChild(face);
            var ft = new TextureRect();
            ft.Texture = ResourceLoader.Exists(KAEL) ? ResourceLoader.Load<Texture2D>(KAEL) : null;
            ft.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            ft.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_COVERED;
            ft.Position = new Vector2(-14, -4);
            ft.Size = new Vector2(148, 148);
            face.AddChild(ft);
            UI2.Center(UI2.Text(left, "KAEL", 18, UI2.GOLD));
            UI2.Center(UI2.Body(left, "The Dragoon · your trainer", 10, UI2.SOFT, false));
            _say = UI2.Body(left, "", 11, new Color("#fff4d6"));
            _say.HorizontalAlignment = HorizontalAlignment.Center;
            // the trainings and the heroes, on the right
            var body = new VBoxContainer();
            body.AddThemeConstantOverride("separation", 6);
            body.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            cols.AddChild(body);
            UI2.Text(body, "CHOOSE A TRAINING", 14, UI2.GOLD);
            var trow = new HBoxContainer();
            trow.AddThemeConstantOverride("separation", 8);
            body.AddChild(trow);
            _cards = new GArray();
            for (int i = 0; i < TRAININGS.Size(); i++)
            {
                GArray td = TRAININGS[i].A;
                var b = new Button();
                b.FocusMode = Control.FOCUS_NONE;
                b.CustomMinimumSize = new Vector2(0, 92);
                b.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
                b.SetMeta("action_key", GD.Fmt("training_%d", i + 1));
                trow.AddChild(b);
                var v = new VBoxContainer();
                v.AddThemeConstantOverride("separation", 1);
                v.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
                v.OffsetLeft = 10;
                v.OffsetRight = -10;
                v.OffsetTop = 6;
                v.OffsetBottom = -6;
                v.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                b.AddChild(v);
                var hrow = new HBoxContainer();
                hrow.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                v.AddChild(hrow);
                var n = UI2.Text(hrow, GD.Fmt("TRAINING %s", GD.Str(td[0])), 11, UI2.SOFT);
                n.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                if (i == 0 && !done)
                {
                    var sp = new Control();
                    sp.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
                    sp.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                    hrow.AddChild(sp);
                    var g = UI2.Text(hrow, GD.Fmt("+%d GOLD", Eco.TUTORIAL_GOLD), 11, new Color("#ffd65a"));
                    g.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                }
                var t = UI2.Text(v, GD.Str(td[1]), 17, Color.WHITE);
                t.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                var d = UI2.Body(v, GD.Str(td[2]), 10, UI2.SOFT);
                d.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                var ti = i + 1;
                b.Pressed += () =>
                {
                    app.Sfx("tab");
                    which = ti;
                    _Refresh();
                };
                _cards.Append(b);
            }
            UI2.Text(body, "PICK YOUR HERO", 14, UI2.GOLD);
            var hrow2 = new HBoxContainer();
            hrow2.AddThemeConstantOverride("separation", 8);
            body.AddChild(hrow2);
            _heroes = new GArray();
            foreach (var h in HEROES)
            {
                var hid = GD.Str(h[0]);
                var b2 = new Button();
                b2.FocusMode = Control.FOCUS_NONE;
                b2.CustomMinimumSize = new Vector2(0, 92);
                b2.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
                b2.SetMeta("action_key", "training_hero_" + hid);
                b2.SetMeta("hid", hid);
                hrow2.AddChild(b2);
                var hb = new HBoxContainer();
                hb.AddThemeConstantOverride("separation", 6);
                hb.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
                hb.OffsetLeft = 6;
                hb.OffsetRight = -6;
                hb.OffsetTop = 6;
                hb.OffsetBottom = -6;
                hb.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                b2.AddChild(hb);
                var pt = new TextureRect();
                pt.Texture = ResourceLoader.Exists(MobaPanel.Portrait(hid)) ? ResourceLoader.Load<Texture2D>(MobaPanel.Portrait(hid)) : null;
                pt.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
                pt.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
                pt.CustomMinimumSize = new Vector2(70, 70);
                pt.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                hb.AddChild(pt);
                var hv = new VBoxContainer();
                hv.AddThemeConstantOverride("separation", 0);
                hv.Alignment = BoxContainer.ALIGNMENT_CENTER;
                hv.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
                hv.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                hb.AddChild(hv);
                var nm = UI2.Text(hv, GD.Str(Moba.HEROES[hid].name).ToUpperInvariant(), 15, Color.WHITE);
                nm.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                var rl = UI2.Text(hv, GD.Str(h[1]), 11, Color.FromCode(GD.Str(MobaPanel.ROLE_COL.Get(Kits.RoleOf(hid), "#ffffff"))));
                rl.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                var ln = UI2.Body(hv, GD.Str(h[2]), 10, UI2.SOFT, false);
                ln.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                b2.Pressed += () =>
                {
                    app.Sfx("tab");
                    hero = hid;
                    _Refresh();
                };
                _heroes.Append(b2);
            }
            var gap = new Control();
            gap.SizeFlagsVertical = Control.SIZE_EXPAND_FILL;
            body.AddChild(gap);
            var brow = new HBoxContainer();
            brow.Alignment = BoxContainer.ALIGNMENT_END;
            body.AddChild(brow);
            var go = UI2.Button(brow, "BATTLE", "gold", () =>
            {
                app.Sfx("confirm");
                app.CloseModal();
                app.StartTraining(which, hero);
            }, "training_go", 20, 46.0);
            var gm = go.CustomMinimumSize;
            gm.x = 200;
            go.CustomMinimumSize = gm;
            _Refresh();
        }

        public void _Refresh()
        {
            for (int i = 0; i < _cards.Size(); i++)
                _Style(_cards[i].As<Button>(), i + 1 == which);
            foreach (var b in _heroes)
                _Style(b.As<Button>(), GD.Str(Var.Of(b.As<Button>().GetMeta("hid"))) == hero);
            var lane = "";
            foreach (var h in HEROES)
            {
                if (GD.Str(h[0]) == hero)
                    lane = GD.Str(h[2]).ToLowerInvariant();
            }
            _say.Text = which == 1 ? "\"Stay close, and I'll show you how we fight.\"" :
                GD.Fmt("\"Five against five. %s %s's place is the %s -- I'll take you there.\"", (GArray.Of("A", "E", "I", "O", "U").Has(GD.Str(Moba.HEROES[hero].name).Left(1)) ? "An" : "A"), GD.Str(Moba.HEROES[hero].name), lane);
        }

        public static void _Style(Button b, bool on)
        {
            var sb = new StyleBoxFlat();
            sb.BgColor = on ? new Color(0.22, 0.15, 0.05, 0.96) : new Color(0.05, 0.07, 0.14, 0.92);
            sb.BorderColor = on ? new Color("#ffd65a") : new Color("#3e4a66");
            sb.SetBorderWidthAll(on ? 3 : 2);
            sb.SetCornerRadiusAll(12);
            sb.AntiAliasing = true;
            if (on)
            {
                sb.ShadowColor = new Color(1.0, 0.82, 0.35, 0.45);
                sb.ShadowSize = 6;
            }
            foreach (var st in new[] { "normal", "hover", "pressed", "focus", "hover_pressed" })
                b.AddThemeStyleboxOverride(st, sb);
        }
    }
}
