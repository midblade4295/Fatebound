// Ported from godot/scripts/app/chest_open.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector2i = Fatebound.Sim.Vec2i;
using Vector3 = Fatebound.Sim.Vec3;
using Color = Fatebound.GUI.Col;
using UI = Fatebound.Game.Ui;
using UI2 = Fatebound.Game.Ui2;
using Eco = Fatebound.Game.Economy;
using Chest3D = Fatebound.Game.Chest3d;

namespace Fatebound.Game
{
    // 0.31.79 (Kevin: "chests in 3d and animated"): opening a chest. The Meshy chest teases in the middle of a sunburst;
    // TAP TO OPEN (or OPEN) rolls the contents (Profile.open_chest), the chest shakes, the lid flies open with a flash and a
    // spray of coins, the chest sinks and the rewards rise into view one by one: a hero shard (or the gold), then the gold and
    // gems, then COLLECT. (0.31.79-0.31.187 a weapon came first, with EQUIP NOW -- 0.31.188 chests hold gold, gems and shards.)
    public class ChestOpen : Control
    {
        public SiegeApp app;
        public int index = 0;
        public string kind = "wooden";
        public GDict result = new GDict();

        public Control _stage;
        public SubViewport _vp;
        public Node3D _chest;
        public double _t = 0.0;
        public double _open_t = -1.0;
        public Label _title;                    // 0.31.216: the chest's name and odds (they fade as the reward shows)
        public Label _odds;
        public TextureRect _rays;
        public TextureRect _rays2;
        public Control _prompt;
        public Control _reveal;
        public ColorRect _flash;

        public static readonly GDict COLORS = new GDict
        {
            { "wooden", GArray.Of(Color.FromCode("#6a4220"), Color.FromCode("#2a160a"), Color.FromCode("#f0bf86"), new Color(1.0, 0.77, 0.51)) },
            { "silver", GArray.Of(Color.FromCode("#3d5878"), Color.FromCode("#121e33"), Color.FromCode("#eef4fa"), new Color(0.84, 0.91, 1.0)) },
            { "gold", GArray.Of(Color.FromCode("#6b4a12"), Color.FromCode("#24150a"), Color.FromCode("#ffd65a"), new Color(1.0, 0.84, 0.43)) },
            { "royal", GArray.Of(Color.FromCode("#4a1f86"), Color.FromCode("#140829"), Color.FromCode("#e0b5ff"), new Color(0.8, 0.59, 1.0)) },
        };

        protected override void _Ready()
        {
            SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            MouseFilter = Control.MOUSE_FILTER_STOP;
            GArray cs = COLORS.Get(kind, COLORS["wooden"]).A;
            var g = new Gradient();
            g.SetColor(0, (Color)cs[0]);
            g.SetColor(1, Color.FromCode("#06040f"));
            g.AddPoint(0.45, (Color)cs[1]);
            var gt = new GradientTexture2D();
            gt.Gradient = g;
            gt.Fill = GradientTexture2D.FillEnum.Radial;
            gt.FillFrom = new Vector2(0.5, 0.45);
            gt.FillTo = new Vector2(1.15, 0.45);
            gt.Width = 128;
            gt.Height = 256;
            var bg = new TextureRect();
            bg.Texture = gt;
            bg.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            bg.StretchMode = TextureRect.STRETCH_SCALE;
            bg.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            bg.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(bg);
            { var mc = Modulate; mc.a = 0.0f; Modulate = mc; }
            CreateTween().TweenProperty(this, "modulate:a", 1.0, 0.2);
            _rays = UI2.Rays(this, 900.0, (Color)cs[3], 46.0, 0.34);
            for (int i = 0; i < 8; i++)
            {
                var vs = GetViewportRect().size;
                _Twinkle(new Vector2(GD.RandfRange(0.05, 0.95) * vs.x, GD.RandfRange(0.12, 0.9) * vs.y), GD.RandfRange(8, 14), GD.RandfRange(0.0, 2.0));
            }
            GDict def = Eco.CHESTS[kind].D;
            var title = UI2.Text(this, GD.Str(def["name"]).ToUpperInvariant(), 36, (Color)cs[2], UI2.INK, 9);
            title.HorizontalAlignment = HorizontalAlignment.Center;
            title.AnchorLeft = 0.58;
            title.AnchorRight = 1.0;
            title.AnchorTop = 0.5;
            title.AnchorBottom = 0.5;
            title.OffsetRight = -16;
            title.OffsetTop = -150;
            title.OffsetBottom = -104;
            _title = title;
            var odds = UI2.Body(this, Eco.ChestOdds(kind), 11, Color.FromCode("#e8dcff"));
            odds.HorizontalAlignment = HorizontalAlignment.Center;
            odds.AnchorLeft = 0.58;
            odds.AnchorRight = 1.0;
            odds.AnchorTop = 0.5;
            odds.AnchorBottom = 0.5;
            odds.OffsetRight = -16;
            odds.OffsetTop = -102;
            odds.OffsetBottom = -50;
            _odds = odds;
            // the chest
            _stage = new Control();
            _stage.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            _stage.Size = new Vector2(340, 340);
            AddChild(_stage);
            _vp = new SubViewport();
            _vp.OwnWorld3D = true;
            _vp.TransparentBg = true;
            _vp.Msaa3D = Viewport.MSAA_DISABLED;       // 0.31.144: drawn at the screen's own pixel density; MSAA's pipelines weren't pre-compiled (a hitch the first time it opened)
            _vp.RenderTargetUpdateMode = SubViewport.UPDATE_ALWAYS;
            _stage.AddChild(_vp);
            var vt = new TextureRect();
            vt.Texture = _vp.GetTexture();
            vt.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            vt.StretchMode = TextureRect.STRETCH_SCALE;
            vt.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            vt.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            _stage.AddChild(vt);
            var world = new Node3D();
            _vp.AddChild(world);
            Chest3D.Stage(world);
            var cam = new Camera3D();
            cam.Fov = 28.0;
            world.AddChild(cam);
            var yaw = GD.DegToRad(28.0);
            cam.LookAtFromPosition(new Vector3(GD.Sin(yaw) * 7.1, 2.75, GD.Cos(yaw) * 7.1), new Vector3(0.0, 0.8, 0.0), Vector3.UP);
            _chest = Chest3D.Make(kind);
            world.AddChild(_chest);
            var tap = new Button();
            tap.Flat = true;
            foreach (var st_name in new[] { "normal", "hover", "pressed", "focus" })
                tap.AddThemeStyleboxOverride(st_name, new StyleBoxEmpty());
            tap.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            tap.SetMeta("action_key", "chest_tap");
            tap.Pressed += Open;
            _stage.AddChild(tap);
            // before: TAP TO OPEN and a big OPEN
            _prompt = new Control();
            _prompt.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            _prompt.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(_prompt);
            var tt = UI2.Text(_prompt, "TAP TO OPEN", 26, Color.WHITE, UI2.INK, 7);
            tt.HorizontalAlignment = HorizontalAlignment.Center;
            tt.AnchorLeft = 0.58;
            tt.AnchorTop = 0.5;
            tt.AnchorBottom = 0.5;
            tt.AnchorRight = 1.0;
            tt.OffsetRight = -16;
            tt.OffsetTop = -30;
            tt.OffsetBottom = 4;
            UI2.Pulse(tt, 0.06, 0.7);
            var ob = UI2.Button(_prompt, "OPEN", "gold", Open, "chest_modal_open", 32, 66.0, 20.0);
            ob.AnchorLeft = 0.79;
            ob.AnchorRight = 0.79;
            ob.AnchorTop = 0.5;
            ob.AnchorBottom = 0.5;
            ob.OffsetLeft = -115;
            ob.OffsetRight = 115;
            ob.OffsetTop = 22;
            ob.OffsetBottom = 88;
            UI2.Sweep(ob);
            var close = UI2.Button(_prompt, "✕", "ghost", () =>
            {
                app.Sfx("menuClose");
                app.CloseModal();
            }, "chest_modal_close", 20, 40.0, 12.0);
            close.CustomMinimumSize = new Vector2(44, 44);
            close.Position = new Vector2(12, 14 + _Safe());
            Resized += _Layout;
            _Layout();
        }

        public double _Safe()
        {
            return app != null ? (double)app.safe_top : 0.0;
        }

        // 0.31.216 (landscape): the chest on the left, the words and OPEN on the right; opened, it moves aside (left) and its
        // reward stands in the middle, the amounts and COLLECT on the right (one column down the screen in portrait)
        public Vector2 _ChestAt()
        {
            return new Vector2(Size.x * 0.34, Size.y * 0.54);
        }

        public Vector2 _CardAt()
        {
            return new Vector2(Size.x * 0.5, Size.y * 0.5 + 8.0);
        }

        public void _Layout()
        {
            var r = Chest3D.ViewportRatio(this);
            _vp.Size = new Vector2i(GD.Int(340 * r), GD.Int(340 * r));
            var c = _ChestAt();
            if (_open_t < 0.0)
            {
                _stage.Position = c - new Vector2(170, 170);
                _rays.Position = c - _rays.Size * 0.5;
            }
        }

        public void _Twinkle(Vector2 at, double px, double delay)
        {
            var t = new TextureRect();
            t.Texture = UI2.GlowTex();
            t.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            t.StretchMode = TextureRect.STRETCH_SCALE;
            t.Size = new Vector2(px, px);
            t.Position = at;
            t.PivotOffset = new Vector2(px, px) * 0.5;
            t.Modulate = new Color(1, 0.95, 0.8, 0.0);
            t.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(t);
            UI2.WhenReady(t, () =>
            {
                var tw = t.CreateTween().SetLoops();
                tw.TweenInterval(delay);
                tw.TweenProperty(t, "modulate:a", 1.0, 0.8).SetTrans(Tween.TRANS_SINE);
                tw.TweenProperty(t, "modulate:a", 0.1, 0.8).SetTrans(Tween.TRANS_SINE);
            });
        }

        public void Open()
        {
            if (_open_t >= 0.0)
                return;
            result = app.profile.OpenChest(index);
            if (!(bool)result.Get("ok", false))
            {
                app.CloseModal();
                return;
            }
            if (app.analytics != null)          // 0.31.118: what came out, and which chest (0.31.188: "shard" or "none")
                app.analytics.LogEv("chest_open", new GDict { { "rarity", GD.Str(result.Get("shard", "")) != "" ? "shard" : "none" }, { "src", kind } });
            app.Sfx("chestOpen");                   // 0.31.109: the lid, the magic swelling into the burst at 0.45 s, the sparkle
            _open_t = 0.0;
            var tw = CreateTween();
            tw.TweenProperty(_prompt, "modulate:a", 0.0, 0.2);
            tw.TweenCallback(() => _prompt.Visible = false);
        }

        protected override void _Process(double delta)
        {
            _t += delta;
            if (_open_t < 0.0)
            {
                Chest3D.Pose(_chest, "tease", _t);
                return;
            }
            var was = _open_t;
            _open_t += delta;
            Chest3D.Pose(_chest, _open_t < 1.6 ? "open" : "opened", _open_t);
            if (was < 0.45 && _open_t >= 0.45)
                _Burst();
            if (was < 1.3 && _open_t >= 1.3)
            {
                var c = new Vector2(Size.x * 0.17, Size.y * 0.6);            // (aside: the reward takes the middle)
                var tw = CreateTween().SetParallel();
                tw.TweenProperty(_stage, "position", c - new Vector2(170, 170), 0.55).SetTrans(Tween.TRANS_CUBIC).SetEase(Tween.EASE_IN_OUT);
                _stage.PivotOffset = new Vector2(170, 170);
                tw.TweenProperty(_stage, "scale", Vector2.ONE * 0.62, 0.55).SetTrans(Tween.TRANS_CUBIC).SetEase(Tween.EASE_IN_OUT);
                tw.TweenProperty(_rays, "position", _CardAt() - _rays.Size * 0.5, 0.55);
                foreach (var l in new Label[] { _title, _odds })
                {
                    if (l != null)
                        tw.TweenProperty(l, "modulate:a", 0.0, 0.3);
                }
            }
            if (was < 1.45 && _open_t >= 1.45)
                _ShowRewards();
        }

        public void _Burst()
        {
            // (its sound is the end of chestOpen's swell)
            GArray cs = COLORS.Get(kind, COLORS["wooden"]).A;
            _flash = new ColorRect();
            _flash.Color = new Color(1, 0.98, 0.9, 0.0);
            _flash.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            _flash.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(_flash);
            var ft = CreateTween();
            ft.TweenProperty(_flash, "color:a", 0.9, 0.08);
            ft.TweenProperty(_flash, "color:a", 0.0, 0.7);
            ft.TweenCallback(_flash.QueueFree);
            _rays2 = UI2.Rays(this, 760.0, (Color)cs[3], 18.0, 0.0);
            var c = _ChestAt();
            _rays2.Position = _CardAt() - _rays2.Size * 0.5;
            MoveChild(_rays2, 2);
            CreateTween().TweenProperty(_rays2, "modulate:a", 0.7, 0.4);
            // coins and gems spray out of the chest
            var origin = c + new Vector2(0, -10);
            for (int i = 0; i < 16; i++)
            {
                var gem = i % 4 == 1;
                var px = (i % 3) != 0 ? 34.0 : 42.0;
                var t = new TextureRect();
                t.Texture = UI2.Tex(GD.Fmt("res://assets/ui/currency/%s.png", gem ? "gem" : "coin"));
                t.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
                t.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
                t.Size = new Vector2(px, px);
                t.PivotOffset = t.Size * 0.5;
                t.Position = origin - t.Size * 0.5;
                t.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                AddChild(t);
                var ang = GD.DegToRad(-165.0 + i * (150.0 / 15.0) + GD.RandfRange(-6, 6));
                var dist = GD.RandfRange(150, 230);
                var dest = origin + new Vector2(GD.Cos(ang), GD.Sin(ang)) * dist + new Vector2(0, 70);
                var peak = origin + new Vector2(GD.Cos(ang), GD.Sin(ang)) * dist * 0.6 + new Vector2(0, -60);
                var dur = GD.RandfRange(0.9, 1.3);
                var spin = GD.RandfRange(-6.0, 6.0);
                var tw = t.CreateTween();
                tw.TweenMethod<double>((double v) =>
                {
                    var a = origin.Lerp(peak, v);
                    var b = peak.Lerp(dest, v);
                    t.Position = a.Lerp(b, v) - t.Size * 0.5;
                    t.Rotation = v * spin;
                    { var mc = t.Modulate; mc.a = (float)(1.0 - GD.Maxf(0.0, (v - 0.7) / 0.3)); t.Modulate = mc; }
                }, 0.0, 1.0, dur);
                tw.TweenCallback(t.QueueFree);
            }
        }

        public void _ShowRewards()
        {
            _reveal = new Control();
            _reveal.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            _reveal.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            AddChild(_reveal);
            var shard = GD.Str(result.Get("shard", ""));
            var top = _CardAt().y - 119.0;
            var card = new Control();
            card.Size = new Vector2(210, 238);
            card.Position = new Vector2(_CardAt().x - 105.0, top);
            card.PivotOffset = card.Size * 0.5;
            _reveal.AddChild(card);
            var rar = "common";
            var title = "";
            var tag = "";
            var icon = "";
            if (shard != "")
            {
                rar = "epic";                                     // 0.31.185: a hero shard -- the chest's best
                title = GD.Fmt("%s SHARD", GD.Str(Eco.SKIN_HEROES.Get(shard, shard.Capitalize())).ToUpperInvariant());
                tag = "UNLOCK HIM FOR LESS  ·  OR MELT IT";
                icon = GD.Fmt("res://assets/ui/skins/default_%s.png", shard);
            }
            else
            {
                title = GD.Fmt("+%s GOLD", UI.Grouped((int)result.Get("gold", 0)));
                tag = GD.Str(Eco.CHESTS.Get(kind, new GDict()).Get("name", "CHEST")).ToUpperInvariant();
                icon = "res://assets/ui/currency/coins_l.png";
            }
            string panel = GD.Str(new GDict { { "common", "night" }, { "rare", "royal" }, { "epic", "purple" }, { "legendary", "ember" } }.Get(rar, "night"));
            string rim = GD.Str(new GDict { { "common", "silver" }, { "rare", "blue" }, { "epic", "purple" }, { "legendary", "orange" } }.Get(rar, "gold"));
            Color tint = (Color)new GDict { { "common", new Color(1, 0.9, 0.6) }, { "rare", new Color(0.5, 0.75, 1.0) }, { "epic", new Color(0.8, 0.55, 1.0) }, { "legendary", new Color(1.0, 0.75, 0.3) } }.Get(rar, new Color(1, 0.9, 0.6));
            var plate = new Control();
            plate.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            plate.ClipContents = true;
            plate.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            card.AddChild(plate);
            UI2.Plate(plate, panel, 22.0, rim, new GDict { { "rim", 4.0 } });
            var halo = UI2.Rays(plate, 300.0, tint, 16.0, 0.5);
            halo.Position = new Vector2(-45, -60);
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", 2);
            v.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            v.OffsetLeft = 8;
            v.OffsetRight = -8;
            v.OffsetTop = 12;
            v.OffsetBottom = -10;
            v.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            card.AddChild(v);
            var ic = UI2.Img(v, icon, 136.0);
            ic.SizeFlagsHorizontal = Control.SIZE_SHRINK_CENTER;
            var nl = UI2.Text(v, title, 17, Color.WHITE, UI2.INK, 5);
            nl.HorizontalAlignment = HorizontalAlignment.Center;
            nl.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
            nl.SizeFlagsVertical = Control.SIZE_EXPAND_FILL;
            var tl = UI2.Body(v, tag, 10, tint.Lightened(0.2), false);
            tl.HorizontalAlignment = HorizontalAlignment.Center;
            tl.ClipText = true;
            if (shard != "")
            {
                var nb = new PanelContainer();
                var sb = new StyleBoxFlat();
                sb.BgColor = Color.FromCode("#e8443a");
                sb.BorderColor = Color.FromCode("#3a0805");
                sb.SetBorderWidthAll(3);
                sb.SetCornerRadiusAll(10);
                sb.ContentMarginLeft = 9;
                sb.ContentMarginRight = 9;
                sb.ContentMarginTop = 3;
                sb.ContentMarginBottom = 1;
                nb.AddThemeStyleboxOverride("panel", sb);
                nb.Position = new Vector2(150, -14);
                nb.Rotation = GD.DegToRad(12);
                card.AddChild(nb);
                UI2.Text(nb, "NEW!", 16, Color.WHITE, Color.FromCode("#3a0805"), 4);
            }
            card.Scale = Vector2.ONE * 0.6;
            { var mc = card.Modulate; mc.a = 0.0f; card.Modulate = mc; }
            var tw = CreateTween().SetParallel();
            tw.TweenProperty(card, "scale", Vector2.ONE, 0.5).SetTrans(Tween.TRANS_BACK).SetEase(Tween.EASE_OUT);
            tw.TweenProperty(card, "modulate:a", 1.0, 0.25);
            // 0.31.110: the card's sound by what it holds -- a shard an epic's swell, gold the coin
            app.Sfx(shard != "" ? "revealEpic" : "coin");
            // gold and gems
            var right_x = _CardAt().x + 125.0;                  // (0.31.216: the column right of the card)
            var chips = new HBoxContainer();
            chips.AddThemeConstantOverride("separation", 8);
            chips.Alignment = BoxContainer.ALIGNMENT_CENTER;
            chips.Position = new Vector2(right_x, _CardAt().y - 74.0);
            chips.Size = new Vector2(Size.x - 16.0 - right_x, 60);
            _reveal.AddChild(chips);
            var amounts = new GArray();
            if (shard != "")
                amounts.Append(GArray.Of("coins_m", GD.Fmt("+%s", UI.Compact((int)result.Get("gold", 0))), UI2.GOLD, UI2.INK));
            if ((int)result.Get("gems", 0) > 0)
                amounts.Append(GArray.Of("gems", GD.Fmt("+%d", (int)result["gems"]), UI2.CYAN, Color.FromCode("#06283a")));
            var k = 0;
            var narrow = amounts.Size() >= 3;
            foreach (var a in amounts)
            {
                var f = UI2.Frame(chips, "night", 6, 16.0, "gold");
                var pc = f.GetParent() as Control;
                pc.CustomMinimumSize = new Vector2(narrow ? 98 : 150, 58);
                var r = new HBoxContainer();
                r.AddThemeConstantOverride("separation", 6);
                r.Alignment = BoxContainer.ALIGNMENT_CENTER;
                f.AddChild(r);
                UI2.Img(r, GD.Str(a[0]).BeginsWith("res://") ? GD.Str(a[0]) : GD.Fmt("res://assets/ui/currency/%s.png", a[0]), narrow ? 40.0 : 46.0);
                UI2.Text(r, a[1].AsString(), narrow ? 18 : 24, (Color)a[2], (Color)a[3], 6);
                { var mc = pc.Modulate; mc.a = 0.0f; pc.Modulate = mc; }
                var ct = CreateTween();
                ct.TweenInterval(0.35 + k * 0.2);
                ct.TweenProperty(pc, "modulate:a", 1.0, 0.25);
                k += 1;
            }
            // actions
            var row = new HBoxContainer();
            row.AddThemeConstantOverride("separation", 10);
            row.Position = new Vector2(right_x + 10.0, _CardAt().y + 4.0);
            row.Size = new Vector2(Size.x - 26.0 - right_x - 10.0, 62);
            _reveal.AddChild(row);
            var cb = UI2.Button(row, "COLLECT", "green", _Close, "chest_collect", 26, 62.0, 18.0);
            cb.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            cb.SizeFlagsStretchRatio = 1.3;
            UI2.Sweep(cb);
            { var mc = row.Modulate; mc.a = 0.0f; row.Modulate = mc; }
            var rt = CreateTween();
            rt.TweenInterval(0.8);
            rt.TweenProperty(row, "modulate:a", 1.0, 0.3);
        }

        public void _Close()
        {
            app.Sfx("coin");
            app.CloseModal();
            app.Rebuild();
        }
    }
}
