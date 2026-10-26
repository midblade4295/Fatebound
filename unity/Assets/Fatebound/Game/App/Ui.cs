// Ported from godot/scripts/app/ui.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Color = Fatebound.GUI.Col;

namespace Fatebound.Game
{
    // Fatebound Siege UI toolkit: palette, fonts and styled building blocks for the app shell.
    // Static helpers only; screens call these so the whole app shares one look.
    public static class Ui
    {
        // 0.31.195 (Kevin: "Change text style of UI" -> Lilita One, "A"): the titles and buttons in Lilita One (Brawl Stars'
        // face), the small text still Nunito; Cinzel only for the champions' lore lines (their epithet and their saying)
        public static readonly Font TITLE_FONT = ResourceLoader.Load<Font>("res://assets/fonts/LilitaOne-Regular.ttf");
        public static readonly Font LORE_FONT = ResourceLoader.Load<Font>("res://assets/fonts/Cinzel-Black.woff2");
        public static readonly Font HEAVY_FONT = ResourceLoader.Load<Font>("res://assets/fonts/Nunito-ExtraBold.woff2");
        public static readonly Font BODY_FONT = ResourceLoader.Load<Font>("res://assets/fonts/Nunito-Bold.woff2");

        public static readonly Color BG_TOP = new Color("#13203a");
        public static readonly Color BG_BOTTOM = new Color("#070b15");
        public static readonly Color CARD = new Color(0.086, 0.137, 0.235, 0.94);
        public static readonly Color CARD_HI = new Color("#2d4a78");
        public static readonly Color GOLD = new Color("#ffc94d");
        public static readonly Color CYAN = new Color("#5fd2f0");
        public static readonly Color GREEN = new Color("#5fdc86");
        public static readonly Color RED = new Color("#ff5f57");
        public static readonly Color PURPLE = new Color("#b77cff");
        public static readonly Color TEXT = new Color("#f2f5fa");
        public static readonly Color MUTED = new Color("#93a4bd");

        // style: [fill, lip (darker bottom edge), text colour]
        public static readonly GDict BUTTONS = new GDict
        {
            { "primary", GArray.Of(new Color("#ff9a2e"), new Color("#b04f10"), new Color("#2a1300")) },
            { "gold", GArray.Of(new Color("#ffc94d"), new Color("#a3680f"), new Color("#2e1d00")) },
            { "secondary", GArray.Of(new Color("#26406b"), new Color("#101d34"), new Color("#eef3fa")) },
            { "premium", GArray.Of(new Color("#9b5cff"), new Color("#4e2698"), new Color("#ffffff")) },
            { "claim", GArray.Of(new Color("#43c86f"), new Color("#1d7a3f"), new Color("#062b14")) },
            { "danger", GArray.Of(new Color("#ff5f57"), new Color("#9c2621"), new Color("#ffffff")) },
            { "ghost", GArray.Of(new Color(1, 1, 1, 0.06), new Color(1, 1, 1, 0.02), new Color("#dfe7f2")) },
        };

        public static StyleBoxFlat CardStyle(Color? fill = null, int radius = 18, Color? border = null, bool shadow = true)
        {
            fill ??= CARD;
            border ??= CARD_HI;
            var sb = new StyleBoxFlat();
            sb.BgColor = fill.Value;
            sb.SetCornerRadiusAll(radius);
            sb.BorderColor = border.Value;
            sb.SetBorderWidthAll(1);
            sb.BorderWidthTop = 2;                 // a lighter top edge reads as a bevel
            sb.ContentMarginLeft = 14;
            sb.ContentMarginRight = 14;
            sb.ContentMarginTop = 12;
            sb.ContentMarginBottom = 12;
            if (shadow)
            {
                sb.ShadowColor = new Color(0, 0, 0, 0.45);
                sb.ShadowSize = 10;
                sb.ShadowOffset = new Vector2(0, 5);
            }
            sb.AntiAliasing = true;
            return sb;
        }

        public static VBoxContainer Card(Node parent, Color? fill = null, Color? border = null)
        {
            fill ??= CARD;
            border ??= CARD_HI;
            var p = new PanelContainer();
            p.AddThemeStyleboxOverride("panel", CardStyle(fill, 18, border));
            parent.AddChild(p);
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", 8);
            p.AddChild(v);
            return v;
        }

        // 0.31.195 (Kevin: "Also I don't like the yellow"): no yellow text anywhere -- a gold or yellow colour asked of a label
        // is drawn white (the gold stays on frames, rims, glows and buttons); a highlight that was gold is green for you
        // (your name in the boards and the kill banners) and cyan for what's picked (the open class, today, the current step)
        public static Color Ink(Color c)
        {
            if (c.H > 0.105 && c.H < 0.19 && c.S > 0.38 && c.V > 0.8)
                return new Color(1.0, 1.0, 1.0, c.a);
            return c;
        }

        public static Label Label(Node parent, string text, int size = 14, Color? color = null, Font font = null, bool outline = false)
        {
            color ??= TEXT;
            var l = new Label();
            l.Text = text;
            l.AddThemeFontOverride("font", font != null ? font : HEAVY_FONT);
            l.AddThemeFontSizeOverride("font_size", size);
            l.AddThemeColorOverride("font_color", Ink(color.Value));
            if (outline)
            {
                l.AddThemeColorOverride("font_outline_color", new Color(0, 0, 0, 0.85));
                l.AddThemeConstantOverride("outline_size", GD.Maxi(3, size / 5));
            }
            l.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
            l.VerticalAlignment = VerticalAlignment.Center;
            parent.AddChild(l);
            return l;
        }

        public static Label Title(Node parent, string text, int size = 22, Color? color = null)
        {
            color ??= GOLD;
            var l = Label(parent, text, size, color, TITLE_FONT, true);
            l.HorizontalAlignment = HorizontalAlignment.Center;
            return l;
        }

        public static StyleBoxFlat _ButtonBox(Color fill, Color lip, bool pressed, int radius)
        {
            var sb = new StyleBoxFlat();
            sb.BgColor = fill;
            sb.SetCornerRadiusAll(radius);
            sb.BorderColor = lip;
            sb.BorderWidthBottom = pressed ? 2 : 6;
            sb.BorderWidthLeft = 1;
            sb.BorderWidthRight = 1;
            sb.BorderWidthTop = 1;
            sb.ContentMarginLeft = 16;
            sb.ContentMarginRight = 16;
            sb.ContentMarginTop = 10 + (pressed ? 4 : 0);
            sb.ContentMarginBottom = 10;
            sb.ShadowColor = new Color(0, 0, 0, 0.35);
            sb.ShadowSize = pressed ? 1 : 6;
            sb.ShadowOffset = new Vector2(0, pressed ? 1 : 4);
            sb.AntiAliasing = true;
            return sb;
        }

        public static Button Button(Node parent, string text, string style, Action on_press, string key = "", int size = 16, int radius = 16)
        {
            var b = new Button();
            b.Text = text;
            StyleButton(b, style, size, radius);
            if (key != "")
                b.SetMeta("action_key", key);
            b.Pressed += on_press;
            parent.AddChild(b);
            return b;
        }

        public static void StyleButton(Button b, string style, int size = 16, int radius = 16)
        {
            // The shared tactile look; also used by the in-match HUD so menus and battle match.
            GArray st = BUTTONS.Get(style, BUTTONS["secondary"]).A;
            Color fill = (Color)st[0];
            Color lip = (Color)st[1];
            b.AddThemeStyleboxOverride("normal", _ButtonBox(fill, lip, false, radius));
            b.AddThemeStyleboxOverride("hover", _ButtonBox(fill.Lightened(0.06), lip, false, radius));
            b.AddThemeStyleboxOverride("pressed", _ButtonBox(fill.Darkened(0.08), lip, true, radius));
            b.AddThemeStyleboxOverride("focus", new StyleBoxEmpty());
            var dis = _ButtonBox(new Color(fill.r, fill.g, fill.b, 0.35).Darkened(0.3), new Color(lip, 0.4), false, radius);
            b.AddThemeStyleboxOverride("disabled", dis);
            b.AddThemeFontOverride("font", HEAVY_FONT);
            b.AddThemeFontSizeOverride("font_size", size);
            foreach (var k in new[] { "font_color", "font_hover_color", "font_pressed_color", "font_focus_color" })
                b.AddThemeColorOverride(k, (Color)st[2]);
            b.AddThemeColorOverride("font_disabled_color", new Color((Color)st[2], 0.45));
            b.FocusMode = Control.FOCUS_NONE;
        }

        public static void Tighten(Button b, int side = 6)
        {
            // Narrow side padding for buttons in tight rows (in-match dice, two-up action rows); long
            // labels are clipped instead of pushing the row past its panel.
            foreach (var st_name in new[] { "normal", "hover", "pressed", "disabled" })
            {
                var sb = b.GetThemeStylebox(st_name) as StyleBoxFlat;
                if (sb != null)
                {
                    sb.ContentMarginLeft = side;
                    sb.ContentMarginRight = side;
                }
            }
            b.ClipText = true;
            var m = b.CustomMinimumSize;
            m.x = 0;
            b.CustomMinimumSize = m;
        }

        public static GDict _tex_cache = new GDict();

        public static Texture2D Tex(string path)
        {
            if (!_tex_cache.Has(path))
                _tex_cache[path] = ResourceLoader.Exists(path) ? Var.Of(ResourceLoader.Load(path)) : Var.Nil;
            return _tex_cache[path].As<Texture2D>();
        }

        public static TextureRect TexIcon(Node parent, string path, int px = 24)
        {
            // A pre-rendered image (Blender/Godot renders in assets/ui) at a fixed size.
            var t = new TextureRect();
            t.Texture = Tex(path);
            t.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            t.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
            t.CustomMinimumSize = new Vector2(px, px);
            t.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            parent.AddChild(t);
            return t;
        }

        public static Button PlayButton(Node parent, string text, Action on_press, string key = "")
        {
            // The big call to action: orange glow, a slow pulse and a light sweep every few seconds.
            var b = Button(parent, text, "primary", on_press, key, 34, 22);
            b.AddThemeFontOverride("font", TITLE_FONT);
            b.CustomMinimumSize = new Vector2(0, 82);
            foreach (var st_name in new[] { "normal", "hover", "pressed" })
            {
                var sb = b.GetThemeStylebox(st_name).Duplicate() as StyleBoxFlat;
                sb.ShadowColor = new Color(1.0, 0.5, 0.08, 0.5);
                sb.ShadowSize = 18;
                sb.ShadowOffset = new Vector2(0, 5);
                b.AddThemeStyleboxOverride(st_name, sb);
            }
            var clip = new Control();                     // clips the sweep to the button, not the glow
            clip.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            clip.ClipContents = true;
            clip.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            b.AddChild(clip);
            var g = new Gradient();
            g.SetColor(0, new Color(1, 1, 1, 0));
            g.SetColor(1, new Color(1, 1, 1, 0));
            g.AddPoint(0.5, new Color(1, 1, 1, 0.42));
            var gt = new GradientTexture2D();
            gt.Gradient = g;
            gt.FillFrom = new Vector2(0, 0.5);
            gt.FillTo = new Vector2(1, 0.5);
            gt.Width = 128;
            gt.Height = 8;
            var band = new TextureRect();
            band.Texture = gt;
            band.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            band.Size = new Vector2(110, 90);
            band.Position = new Vector2(-140, -4);
            band.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            clip.AddChild(band);
            b.Resized += () => b.PivotOffset = b.Size * 0.5;
            if (b.IsInsideTree())
            {
                var tw = b.CreateTween().SetLoops();
                tw.TweenMethod<double>(v => { var p = band.Position; p.x = (float)GD.Lerpf(-140.0, clip.Size.x + 30.0, v); band.Position = p; }, 0.0, 1.0, 0.85).SetTrans(Tween.TRANS_SINE);
                tw.TweenInterval(2.6);
                var pulse = b.CreateTween().SetLoops();
                pulse.TweenProperty(b, "scale", new Vector2(1.022, 1.022), 1.1).SetTrans(Tween.TRANS_SINE).SetEase(Tween.EASE_IN_OUT);
                pulse.TweenProperty(b, "scale", Vector2.ONE, 1.1).SetTrans(Tween.TRANS_SINE).SetEase(Tween.EASE_IN_OUT);
            }
            return b;
        }

        public static Icon Icon(Node parent, string kind, int px = 24, Color? tint = null)
        {
            tint ??= Color.WHITE;
            var i = new Icon();
            i.kind = kind;
            i.tint = tint.Value;
            i.CustomMinimumSize = new Vector2(px, px);
            i.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            parent.AddChild(i);
            return i;
        }

        public static ProgressBar Progress(Node parent, double value, double max_value, Color? fill = null, int height = 12)
        {
            fill ??= GOLD;
            var pb = new ProgressBar();
            pb.MaxValue = GD.Maxf(1.0, max_value);
            pb.Value = GD.Clampf(value, 0.0, pb.MaxValue);
            pb.ShowPercentage = false;
            pb.CustomMinimumSize = new Vector2(0, height);
            var bg = new StyleBoxFlat();
            bg.BgColor = new Color(0, 0, 0, 0.45);
            bg.SetCornerRadiusAll(height / 2);
            bg.BorderColor = new Color(1, 1, 1, 0.08);
            bg.SetBorderWidthAll(1);
            var fg = new StyleBoxFlat();
            fg.BgColor = fill.Value;
            fg.SetCornerRadiusAll(height / 2);
            fg.BorderColor = fill.Value.Lightened(0.35);
            fg.BorderWidthTop = 2;
            pb.AddThemeStyleboxOverride("background", bg);
            pb.AddThemeStyleboxOverride("fill", fg);
            parent.AddChild(pb);
            return pb;
        }

        public static HBoxContainer Row(Node parent, int sep = 8)
        {
            var h = new HBoxContainer();
            h.AddThemeConstantOverride("separation", sep);
            parent.AddChild(h);
            return h;
        }

        public static Control Spacer(Node parent, double h = 8.0)
        {
            var c = new Control();
            c.CustomMinimumSize = new Vector2(0, h);
            parent.AddChild(c);
            return c;
        }

        public static T Grow<T>(T c) where T : Control
        {
            c.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            return c;
        }

        public static string Compact(int n)
        {
            if (n >= 1000000)
                return GD.Fmt("%.1fM", n / 1000000.0);
            if (n >= 10000)
                return GD.Fmt("%.1fK", n / 1000.0);
            return GD.Str(n);
        }

        public static string Grouped(int n)
        {
            // 12000 -> "12,000" (0.31.106: the shop's gold offers)
            var s = GD.Str(GD.Absi(n));
            var @out = "";
            while (s.Length > 3)
            {
                @out = "," + s.Substr(s.Length - 3) + @out;
                s = s.Substr(0, s.Length - 3);
            }
            return (n < 0 ? "-" : "") + s + @out;
        }

        public static string Duration(int seconds)
        {
            var s = GD.Maxi(0, seconds);
            if (s >= 86400)
                return GD.Fmt("%dd %dh", s / 86400, (s % 86400) / 3600);
            if (s >= 3600)
                return GD.Fmt("%dh %dm", s / 3600, (s % 3600) / 60);
            return GD.Fmt("%dm", GD.Maxi(1, s / 60));
        }
    }
}
