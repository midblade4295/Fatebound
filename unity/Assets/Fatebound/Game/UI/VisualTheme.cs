// Ported from godot/scripts/ui/visual_theme.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Color = Fatebound.GUI.Col;
using Tactile = Fatebound.Game.TactileStyle;
using Brass = Fatebound.Game.BrassStyle;

namespace Fatebound.Game
{
    // One visual language for the native menus and the match HUD.
    public static class VisualTheme
    {
        public static readonly Font BODY_FONT = ResourceLoader.Load<Font>("res://assets/fonts/DejaVuSans.ttf");
        public static readonly Font BOLD_FONT = ResourceLoader.Load<Font>("res://assets/fonts/Nunito-ExtraBold.woff2");
        public static readonly Font TITLE_FONT = ResourceLoader.Load<Font>("res://assets/fonts/LilitaOne-Regular.ttf");  // big titles (0.31.195: Lilita One, as the menus; Cinzel before)
        public static readonly Color INK = Color.FromCode("#06131b");
        public static readonly Color SURFACE = Color.FromCode("#091d27");
        public static readonly Color RAISED = Color.FromCode("#102c37");
        public static readonly Color GOLD = Color.FromCode("#f2d18d");
        public static readonly Color GOLD_DARK = Color.FromCode("#ad8651");
        public static readonly Color CYAN = Color.FromCode("#70d8e2");
        public static readonly Color RED = Color.FromCode("#ed8c68");
        public static readonly Color TEXT = Color.FromCode("#f3efe1");
        public static readonly Color BRASS_LIGHT = Color.FromCode("#f0cf82");
        public static readonly Color BRASS_DARK = Color.FromCode("#6f4f1e");

        public static StyleBox Panel(Color? bg_ = null, Color? stroke_ = null, int radius = 12, int padding = 12)
        {
            Color bg = bg_ ?? SURFACE;
            Color stroke = stroke_ ?? GOLD_DARK;
            // Framed panels get the beveled brass rim; borderless fills (bars, tracks) stay flat.
            if (padding > 0 && stroke.a > 0.05)
            {
                var brass = new Brass();
                brass.top = new Color(bg.Lightened(0.06), bg.a);
                brass.bottom = new Color(bg.Darkened(0.35), bg.a);
                var saturated = stroke.S > 0.35 && (stroke.H < 0.06 || stroke.H > 0.18);
                brass.rim_light = saturated ? stroke.Lightened(0.25) : BRASS_LIGHT;
                brass.rim_dark = saturated ? stroke.Darkened(0.45) : BRASS_DARK;
                brass.rim_light.a = (float)GD.Maxf(0.6, stroke.a);
                brass.rim_dark.a = (float)GD.Maxf(0.6, stroke.a);
                brass.radius = radius;
                brass.SetContentMarginAll(padding + 2);
                return brass;
            }
            var style = new StyleBoxFlat();
            style.BgColor = bg;
            style.BorderColor = stroke;
            style.SetBorderWidthAll(1);
            style.BorderWidthTop = 2;
            style.SetCornerRadiusAll(radius);
            style.SetContentMarginAll(padding);
            style.ShadowColor = new Color(0, 0, 0, 0.50);
            style.ShadowSize = 7;
            style.AntiAliasing = true;
            return style;
        }

        public static StyleBox Button(Color? bg = null, Color? stroke = null, int radius = 11)
        {
            // Kept for existing call sites: any "button" is now a dimensional tactile face in these colours.
            return TactileFrom(bg ?? RAISED, stroke ?? GOLD_DARK, radius);
        }

        public static StyleBox TactileFrom(Color bg, Color stroke, int radius = 11, string state = "normal")
        {
            var style = new Tactile();
            style.top = bg.Lightened(0.16);
            style.bottom = bg.Darkened(0.22);
            style.lip = bg.Darkened(0.62);
            style.rim = stroke;
            style.radius = radius;
            style.depth = 4.0;
            style.pressed = state == "pressed";
            style.ContentMarginLeft = 10;
            style.ContentMarginRight = 10;
            style.ContentMarginTop = 5 + (state == "pressed" ? 3 : 0);
            style.ContentMarginBottom = 9 - (state == "pressed" ? 3 : 0);
            if (state == "hover")
            {
                style.top = style.top.Lightened(0.08);
                style.gloss = 0.28;
            }
            if (state == "disabled")
                style.gloss = 0.08;
            return style;
        }

        // Named palettes for the whole game. "primary" is the molten-orange ROLL, "gold" the home CTA,
        // "secondary" the navy/gold standard control, "active" a lit cyan toggle, "arcane" spells/ultimate.
        public static readonly GDict PALETTES = new GDict {
            { "primary", new GDict { { "top", "#ffb24a" }, { "bottom", "#e2571a" }, { "lip", "#7c2a07" }, { "rim", "#ffe6a6" }, { "glow", "#ff9a3a" }, { "text", "#fffaf0" } } },
            { "roll", new GDict { { "top", "#f4cf6c" }, { "bottom", "#9a6414" }, { "lip", "#452a05" }, { "rim", "#fff1bf" }, { "glow", "#ffcf5a" }, { "text", "#fffaf0" } } },
            { "gold", new GDict { { "top", "#ffd875" }, { "bottom", "#c98612" }, { "lip", "#6b4105" }, { "rim", "#fff0b8" }, { "glow", "#ffcc55" }, { "text", "#2a1604" } } },
            { "secondary", new GDict { { "top", "#2c3136" }, { "bottom", "#121518" }, { "lip", "#040506" }, { "rim", "#b8904e" }, { "glow", "" }, { "text", "#f2d18d" } } },
            { "active", new GDict { { "top", "#2f8f94" }, { "bottom", "#155258" }, { "lip", "#062326" }, { "rim", "#9ff6ef" }, { "glow", "#5ce8e0" }, { "text", "#effffd" } } },
            { "arcane", new GDict { { "top", "#6a4bb0" }, { "bottom", "#35226a" }, { "lip", "#140a2c" }, { "rim", "#d6b8ff" }, { "glow", "#a77bff" }, { "text", "#f6efff" } } },
            { "nav_active", new GDict { { "top", "#35404a" }, { "bottom", "#141a1f" }, { "lip", "#050608" }, { "rim", "#ffe09a" }, { "glow", "#ffcc55" }, { "text", "#ffffff" } } },
            { "disabled", new GDict { { "top", "#1a2a33" }, { "bottom", "#121e25" }, { "lip", "#070d11" }, { "rim", "#3d4d56" }, { "glow", "" }, { "text", "#7f9097" } } },
        };

        public static StyleBox Tactile(string kind, string state = "normal", int radius = 12)
        {
            GDict pal = PALETTES.Get(state == "disabled" ? "disabled" : kind, PALETTES["secondary"]).D;
            if (state == "disabled" && kind == "arcane")
                pal = new GDict { { "top", "#3b2f58" }, { "bottom", "#221a36" }, { "lip", "#0c0816" }, { "rim", "#6d5a92" }, { "glow", "" }, { "text", "#a595c4" } };
            var style = new Tactile();
            style.top = Color.FromCode(GD.Str(pal["top"]));
            style.bottom = Color.FromCode(GD.Str(pal["bottom"]));
            style.lip = Color.FromCode(GD.Str(pal["lip"]));
            style.rim = Color.FromCode(GD.Str(pal["rim"]));
            style.radius = radius;
            style.depth = GArray.Of("primary", "gold", "roll").Has(kind) ? 5.0 : 4.0;
            style.pressed = state == "pressed";
            if (!GD.Str(pal["glow"]).IsEmpty() && state != "disabled")
            {
                style.glow = Color.FromCode(GD.Str(pal["glow"]));
                style.glow.a = state == "hover" ? 0.55f : 0.38f;
            }
            if (state == "hover")
            {
                style.top = style.top.Lightened(0.10);
                style.bottom = style.bottom.Lightened(0.05);
                style.gloss = 0.3;
            }
            else if (state == "pressed")
            {
                style.top = style.top.Darkened(0.06);
                style.gloss = 0.14;
            }
            else if (state == "disabled")
                style.gloss = 0.06;
            double d = style.depth;
            style.ContentMarginLeft = 10;
            style.ContentMarginRight = 10;
            style.ContentMarginTop = 4 + (state == "pressed" ? d - 1 : 0.0);
            style.ContentMarginBottom = d + 4 - (state == "pressed" ? d - 1 : 0.0);
            return style;
        }
    }
}
