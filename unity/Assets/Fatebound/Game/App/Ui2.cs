// Ported from godot/scripts/app/ui2.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector2i = Fatebound.Sim.Vec2i;
using Color = Fatebound.GUI.Col;
using UI = Fatebound.Game.Ui;
using SkinNode = Fatebound.Game.Skin;

namespace Fatebound.Game
{
    // 0.31.79 menu look (Kevin: "really spruce up the menus ... very good looking and have animated parts"): framed panels
    // on damask / parchment / wood / stone, glossy lipped buttons, chunky outlined titles (0.31.195: Lilita One, white --
    // Luckiest Guy and gold until then), ribbons,
    // dividers and the 3D-style icons. Every box is one SDF skin (skin.gd + ui_skin.gdshader), crisp at any density.
    public static class Ui2
    {
        public static readonly Font LG = ResourceLoader.Load<Font>("res://assets/fonts/LilitaOne-Regular.ttf");      // 0.31.195 (Kevin picked "A"; Luckiest Guy before)

        public const string V2 = "res://assets/ui/v2/";
        public static readonly Color INK = new Color("#2a1604");
        public static readonly Color NAVY = new Color("#0b1230");
        public static readonly Color GOLD = new Color("#ffd65a");
        public static readonly Color CREAM = new Color("#fff4d6");
        public static readonly Color SOFT = new Color("#c9d4f0");
        public static readonly Color MUTED = new Color("#9fb0d6");
        public static readonly Color GREEN = new Color("#7ee08f");
        public static readonly Color CYAN = new Color("#7fe3ff");
        public static readonly Color PURPLE = new Color("#d9a8ff");
        public static readonly Color RED = new Color("#ff6b5e");

        public static GDict _tex = new GDict();

        public static Texture2D Tex(string path)
        {
            if (!_tex.Has(path))
                _tex[path] = ResourceLoader.Exists(path) ? Var.Of(ResourceLoader.Load(path)) : Var.Nil;
            return _tex[path].As<Texture2D>();
        }

        public static string IconPath(string name)
        {
            return V2 + GD.Fmt("icons/%s.png", name);
        }

        // ---------------- skins ----------------
        public static readonly GArray RIM_GOLD = GArray.Of(new Color("#fff4c8"), new Color("#f7cd55"), new Color("#b9761b"));
        public static readonly GArray RIM_BROWN = GArray.Of(new Color("#c8925a"), new Color("#7a4c26"), new Color("#3b2412"));
        public static readonly GArray RIM_SILVER = GArray.Of(new Color("#ffffff"), new Color("#c9d3dc"), new Color("#6f7d8e"));
        public static readonly GArray RIM_GREEN = GArray.Of(new Color("#d6ffb8"), new Color("#6be07c"), new Color("#1f8a43"));
        public static readonly GArray RIM_PURPLE = GArray.Of(new Color("#f3dcff"), new Color("#c47bff"), new Color("#6a2bb8"));
        public static readonly GArray RIM_BLUE = GArray.Of(new Color("#d8ecff"), new Color("#5fb6ff"), new Color("#1e5aa8"));
        public static readonly GArray RIM_ORANGE = GArray.Of(new Color("#fff0b0"), new Color("#ffb13d"), new Color("#b9590c"));

        public static GArray RimOf(string name)
        {
            return GDict.Of("gold", RIM_GOLD, "brown", RIM_BROWN, "silver", RIM_SILVER, "green", RIM_GREEN, "purple", RIM_PURPLE,
                "blue", RIM_BLUE, "orange", RIM_ORANGE).Get(name, RIM_GOLD).A;
        }

        public static GDict PanelParams(string kind, string rim = "gold")
        {
            var dam = Var.Of(Tex(V2 + "tex_damask.webp"));      // (0.31.83, Kevin: no "wallpaper" pattern -- pattern_mix 0: plain gradients)
            var p = new GDict();
            switch (kind)
            {
                case "royal":
                    p = GDict.Of("fill_top", new Color("#4f7ff0"), "fill_bottom", new Color("#0e1a52"), "pattern", dam, "pattern_mix", 0.0, "pattern_gain", 8.3, "pattern_luma", 1.0);
                    break;
                case "night":
                    p = GDict.Of("fill_top", new Color(0.16, 0.24, 0.6, 0.95), "fill_bottom", new Color(0.05, 0.07, 0.2, 0.97), "pattern", dam, "pattern_mix", 0.0, "pattern_gain", 8.3, "pattern_luma", 1.0);
                    break;
                case "purple":
                    p = GDict.Of("fill_top", new Color("#a463f2"), "fill_bottom", new Color("#25094d"), "pattern", dam, "pattern_mix", 0.0, "pattern_gain", 8.3, "pattern_luma", 1.0);
                    break;
                case "ember":
                    p = GDict.Of("fill_top", new Color("#ff9a45"), "fill_bottom", new Color("#3a1003"), "pattern", dam, "pattern_mix", 0.0, "pattern_gain", 8.3, "pattern_luma", 1.0);
                    break;
                case "green":
                    p = GDict.Of("fill_top", new Color("#4fd27a"), "fill_bottom", new Color("#0b3d22"), "pattern", dam, "pattern_mix", 0.0, "pattern_gain", 8.3, "pattern_luma", 1.0);
                    break;
                case "parch":
                    p = GDict.Of("fill_top", new Color("#fffaf0"), "fill_bottom", new Color("#e9d2a2"), "pattern", Var.Of(Tex(V2 + "tex_parchment.webp")), "pattern_mix", 1.0, "pattern_gain", 1.12, "pattern_px", 320.0);
                    break;
                case "wood":
                    p = GDict.Of("fill_top", new Color("#ffe2c0"), "fill_bottom", new Color("#9a7a62"), "pattern", Var.Of(Tex(V2 + "tex_wood.webp")), "pattern_mix", 1.0, "pattern_gain", 1.35, "pattern_px", 240.0);
                    break;
                case "stone":
                    p = GDict.Of("fill_top", new Color("#9db0d8"), "fill_bottom", new Color("#3a4568"), "pattern", Var.Of(Tex(V2 + "tex_stone.webp")), "pattern_mix", 1.0, "pattern_gain", 2.4, "pattern_luma", 1.0, "pattern_px", 220.0);
                    break;
                case "glass":
                    p = GDict.Of("fill_top", new Color(0.03, 0.05, 0.16, 0.78), "fill_bottom", new Color(0.02, 0.03, 0.1, 0.86), "rim", 0.0, "outline", 1.5,
                        "outline_color", new Color(1.0, 0.84, 0.35, 0.45), "shadow_alpha", 0.0, "bevel", 0.06);
                    break;
            }
            GArray r = RimOf(rim);
            var @base = GDict.Of("radius", 18.0, "outline", 2.0, "outline_color", INK, "rim", 3.0, "rim_a", r[0], "rim_b", r[1], "rim_c", r[2],
                "shadow_y", 6.0, "shadow_alpha", 0.55, "shadow_soft", 6.0, "bevel", 0.16);
            @base.Merge(p, true);
            return @base;
        }

        // fill top, fill bottom, lip, ink (outline + text outline)
        public static readonly GDict BTN = new GDict
        {
            { "gold", GArray.Of(new Color("#fff3ad"), new Color("#f0a024"), new Color("#b8650f"), new Color("#3a1c02")) },
            { "green", GArray.Of(new Color("#b4f7a4"), new Color("#25a248"), new Color("#16702f"), new Color("#0b3416")) },
            { "orange", GArray.Of(new Color("#ffe590"), new Color("#f0621a"), new Color("#a33c0b"), new Color("#3d1602")) },
            { "purple", GArray.Of(new Color("#e8ccff"), new Color("#7236d6"), new Color("#45198f"), new Color("#1e0a45")) },
            { "blue", GArray.Of(new Color("#a9c6ff"), new Color("#2a4cae"), new Color("#182c74"), new Color("#0a1238")) },
            { "red", GArray.Of(new Color("#ffb6a6"), new Color("#d6372b"), new Color("#8c1d15"), new Color("#3a0805")) },
            { "grey", GArray.Of(new Color("#d9dfe8"), new Color("#6b778a"), new Color("#4a5466"), new Color("#1c2230")) },
            { "discord", GArray.Of(new Color("#c3c8ff"), new Color("#5865f2"), new Color("#3a43b5"), new Color("#141852")) },      // 0.31.124: Discord's blue
            { "ghost", GArray.Of(new Color(1, 1, 1, 0.12), new Color(1, 1, 1, 0.05), new Color(0, 0, 0, 0.25), new Color(0, 0, 0, 0.6)) },
        };

        public static GDict ButtonParams(string color, double radius = 14.0, double lip = 6.0)
        {
            GArray c = BTN.Get(color, BTN["blue"]).A;
            return GDict.Of("radius", radius, "outline", 2.5, "outline_color", c[3], "rim", 0.0, "fill_top", c[0], "fill_bottom", c[1],
                "lip", lip, "lip_color", c[2], "gloss", 1.0, "bevel", 0.12, "shadow_y", 4.0, "shadow_alpha", 0.5, "shadow_soft", 4.0);
        }

        public static SkinNode Skin(Control parent, GDict @params)
        {
            SkinNode s = new SkinNode(@params);
            parent.AddChild(s);
            parent.MoveChild(s, 0);
            return s;
        }

        public static VBoxContainer Frame(Node parent, string kind = "royal", int pad = 12, double radius = 18.0, string rim = "gold", GDict extra = null)
        {
            extra ??= new GDict();
            // A framed panel; returns its content box (like UI.card).
            var pc = new PanelContainer();
            var sb = new StyleBoxEmpty();
            var p = PanelParams(kind, rim);
            p["radius"] = radius;
            p.Merge(extra, true);
            var edge = (double)p["outline"] + (double)p["rim"];
            foreach (var side in new[] { "left", "right", "top", "bottom" })
                PropertyPath.Set(sb, "content_margin_" + side, edge + pad);
            pc.AddThemeStyleboxOverride("panel", sb);
            parent.AddChild(pc);
            Skin(pc, p);
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", 8);
            pc.AddChild(v);
            return v;
        }

        public static SkinNode Plate(Control parent, string kind = "royal", double radius = 18.0, string rim = "gold", GDict extra = null)
        {
            extra ??= new GDict();
            // Just the skin behind an existing control (for absolutely placed boxes).
            var p = PanelParams(kind, rim);
            p["radius"] = radius;
            p.Merge(extra, true);
            return Skin(parent, p);
        }

        // ---------------- text ----------------
        public static Label Text(Node parent, string s, int size = 20, Color? color = null, Color? ink = null, int outline = -1, bool shadow = true)
        {
            color ??= Color.WHITE;
            ink ??= INK;
            var l = new Label();
            l.Text = s;
            l.AddThemeFontOverride("font", LG);
            l.AddThemeFontSizeOverride("font_size", size);
            l.AddThemeColorOverride("font_color", UI.Ink(color.Value));     // (0.31.195: no yellow text)
            var o = outline >= 0 ? outline : GD.Maxi(4, (int)GD.Round(size / 3.2));
            if (o > 0)
            {
                l.AddThemeColorOverride("font_outline_color", ink.Value);
                l.AddThemeConstantOverride("outline_size", o);
            }
            if (shadow)
            {
                l.AddThemeColorOverride("font_shadow_color", ink.Value);
                l.AddThemeConstantOverride("shadow_offset_x", 0);
                l.AddThemeConstantOverride("shadow_offset_y", GD.Maxi(2, (int)GD.Round(size / 11.0)));
                l.AddThemeConstantOverride("shadow_outline_size", o);
            }
            l.AutowrapMode = TextServer.AUTOWRAP_OFF;
            l.VerticalAlignment = VerticalAlignment.Center;
            l.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            parent.AddChild(l);
            return l;
        }

        public static Label Body(Node parent, string s, int size = 13, Color? color = null, bool wrap = true)
        {
            color ??= SOFT;
            var l = UI.Label(parent, s, size, color, UI.HEAVY_FONT);
            l.AddThemeColorOverride("font_shadow_color", new Color(0, 0, 0, 0.55));
            l.AddThemeConstantOverride("shadow_offset_y", 1);
            l.AutowrapMode = wrap ? TextServer.AUTOWRAP_WORD_SMART : TextServer.AUTOWRAP_OFF;
            l.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            return l;
        }

        public static Label Center(Label l)
        {
            l.HorizontalAlignment = HorizontalAlignment.Center;
            return l;
        }

        // ---------------- buttons ----------------
        public static Button Button(Node parent, string label, string color, Action on_press, string key = "", int size = 18, double h = 48.0, double radius = 14.0, string icon = "")
        {
            var b = new Button();
            b.Text = label;
            b.FocusMode = Control.FOCUS_NONE;
            b.CustomMinimumSize = new Vector2(0, h);
            GArray c = BTN.Get(color, BTN["blue"]).A;
            var lip = GD.Clampf(h * 0.12, 4.0, 9.0);
            foreach (var st_name in new[] { "normal", "hover", "pressed", "disabled", "focus", "hover_pressed" })
            {
                var sb = new StyleBoxEmpty();
                sb.ContentMarginLeft = 12;
                sb.ContentMarginRight = 12;
                sb.ContentMarginTop = 4.0 + (st_name == "pressed" || st_name == "hover_pressed" ? 2.0 : 0.0);
                sb.ContentMarginBottom = lip;
                b.AddThemeStyleboxOverride(st_name, sb);
            }
            b.AddThemeFontOverride("font", LG);
            b.AddThemeFontSizeOverride("font_size", size);
            Color ink = color != "ghost" ? (Color)c[3] : new Color(0, 0, 0, 0.7);
            foreach (var k in new[] { "font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color" })
                b.AddThemeColorOverride(k, Color.WHITE);
            b.AddThemeColorOverride("font_disabled_color", new Color(1, 1, 1, 0.55));
            b.AddThemeColorOverride("font_outline_color", ink);
            b.AddThemeConstantOverride("outline_size", GD.Maxi(4, (int)GD.Round(size / 3.4)));
            if (icon != "")
            {
                b.Icon = Tex(icon);
                b.ExpandIcon = false;
                b.AddThemeConstantOverride("icon_max_width", (int)(h * 0.62));
                b.AddThemeConstantOverride("h_separation", 6);
            }
            if (key != "")
                b.SetMeta("action_key", key);
            b.Pressed += on_press;
            parent.AddChild(b);
            Skin(b, ButtonParams(color, radius, lip));
            return b;
        }

        public static void WhenReady(Node c, Action f)
        {
            // Tweens need the node in the tree: run now if it is, else once it enters.
            if (c.IsInsideTree())
                f();
            else
            {
                Action once = null;
                once = () => { c.Ready -= once; f(); };      // (CONNECT_ONE_SHOT)
                c.Ready += once;
            }
        }

        public static void Sweep(Control c, double period = 3.2, double width = 70.0, double alpha = 0.55, bool masked = false)
        {
            // A light band that sweeps across the control every few seconds (clipped to it). 0.31.213 masked: only where c itself
            // draws (c a picture with see-through edges, e.g. Home's PLAY plaque: the band showed as a pale box past its ends)
            if (masked)
                c.ClipChildren = CanvasItem.CLIP_CHILDREN_AND_DRAW;
            var clip = new Control();
            clip.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            clip.OffsetLeft = 4;
            clip.OffsetRight = -4;
            clip.OffsetTop = 4;
            clip.OffsetBottom = -6;
            clip.ClipContents = true;
            clip.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            c.AddChild(clip);
            var g = new Gradient();
            g.SetColor(0, new Color(1, 1, 1, 0));
            g.SetColor(1, new Color(1, 1, 1, 0));
            g.AddPoint(0.5, new Color(1, 1, 1, alpha));
            var gt = new GradientTexture2D();
            gt.Gradient = g;
            gt.FillFrom = new Vector2(0, 0.5);
            gt.FillTo = new Vector2(1, 0.5);
            gt.Width = 64;
            gt.Height = 4;
            var band = new TextureRect();
            band.Texture = gt;
            band.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            band.Size = new Vector2(width, 400);
            band.Position = new Vector2(-width - 40, -150);
            band.Rotation = GD.DegToRad(18);
            band.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            clip.AddChild(band);
            WhenReady(c, () =>
            {
                var tw = c.CreateTween().SetLoops();
                tw.TweenInterval(GD.RandfRange(0.2, 1.6));
                tw.TweenMethod<double>(v => { var bp = band.Position; bp.x = (float)GD.Lerpf(-width - 60.0, clip.Size.x + 40.0, v); band.Position = bp; }, 0.0, 1.0, 0.9).SetTrans(Tween.TRANS_SINE);
                tw.TweenInterval(period);
            });
        }

        public static void Pulse(Control c, double amount = 0.03, double secs = 1.1)
        {
            c.Resized += () => c.PivotOffset = c.Size * 0.5;
            Action go = () =>
            {
                var tw = c.CreateTween().SetLoops();
                tw.TweenProperty(c, "scale", Vector2.ONE * (1.0 + amount), secs).SetTrans(Tween.TRANS_SINE).SetEase(Tween.EASE_IN_OUT);
                tw.TweenProperty(c, "scale", Vector2.ONE, secs).SetTrans(Tween.TRANS_SINE).SetEase(Tween.EASE_IN_OUT);
            };
            WhenReady(c, go);
        }

        public static void Bob(Control c, double px = 5.0, double secs = 1.3, double delay = 0.0)
        {
            // 0.31.116 (Kevin: "The icons in the menus that float up and down are not smooth"): a container lays its children out
            // again whenever anything in it changes, which put a floating icon back to rest for a frame; so an icon in a container
            // floats inside a holder of its own size, and the container lays out the holder. (The other half of the fix is
            // project.godot's gui/common/snap_controls_to_pixels=false: controls were rounded to whole canvas pixels, so on a phone
            // a 3-5 px float moved in 3-4 screen-pixel steps.)
            var p = c.GetParent();
            if (p is Container)
            {
                var holder = new Control();
                holder.Name = "BobHolder";
                holder.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                holder.CustomMinimumSize = c.GetCombinedMinimumSize();
                holder.SizeFlagsHorizontal = c.SizeFlagsHorizontal;
                holder.SizeFlagsVertical = c.SizeFlagsVertical;
                holder.SizeFlagsStretchRatio = c.SizeFlagsStretchRatio;
                var at = c.GetIndex();
                p.RemoveChild(c);
                p.AddChild(holder);
                p.MoveChild(holder, at);
                holder.AddChild(c);
                c.Position = Vector2.ZERO;
                c.Size = holder.CustomMinimumSize;
            }
            // 0.31.144: the icon held weakly -- a menu redrawn before the next frame frees it, and a lambda still holding a freed
            // node logs "Lambda capture at index 0 was freed" (in every start-up log on Kevin's phone, and in matches)
            WeakRef cref = new WeakRef(c);
            if (p is Container)
            {
                Control hold = c.GetParent() as Control;
                hold.Resized += () =>
                {
                    var cc = cref.GetRef() as Control;
                    if (cc != null)
                    {
                        var cp = cc.Position;
                        cp.x = 0.0f;
                        cc.Position = cp;
                        cc.Size = hold.Size;
                    }
                };
            }
            Action go = () =>
            {
                var cc = cref.GetRef() as Control;
                if (cc == null)
                    return;                               // (redrawn before the next frame: the node is gone)
                var y0 = cc.Position.y;
                var tw = cc.CreateTween().SetLoops();
                tw.TweenInterval(delay);
                tw.TweenProperty(cc, "position:y", y0 - px, secs).SetTrans(Tween.TRANS_SINE).SetEase(Tween.EASE_IN_OUT);
                tw.TweenProperty(cc, "position:y", (double)y0, secs).SetTrans(Tween.TRANS_SINE).SetEase(Tween.EASE_IN_OUT);
            };
            WhenReady(c, () =>
            {
                var tree = c.GetTree();
                Action once = null;
                once = () => { tree.ProcessFrame -= once; go(); };      // (CONNECT_ONE_SHOT)
                tree.ProcessFrame += once;
            });
        }

        public static void Spin(Control c, double secs = 12.0)
        {
            // 0.31.122 (Kevin: "The gear cog next to settings needs its animation to just rotate in place"): the pivot is set now
            // and whenever the size changes -- before, it was set only on "resized", which never came for an icon already at its
            // size (img() sizes it), so it turned about its top-left corner and swung around the sign
            c.PivotOffset = c.Size * 0.5;
            c.Resized += () => c.PivotOffset = c.Size * 0.5;
            Action go = () =>
            {
                c.PivotOffset = c.Size * 0.5;
                var tw = c.CreateTween().SetLoops();
                tw.TweenProperty(c, "rotation", GD.TAU, secs).From(0.0);
            };
            WhenReady(c, go);
        }

        public static void Wiggle(Control c, double every = 2.8)
        {
            c.PivotOffset = c.Size * 0.5;                  // (0.31.122: as spin -- set now too, not only on "resized")
            c.Resized += () => c.PivotOffset = c.Size * 0.5;
            Action go = () =>
            {
                c.PivotOffset = c.Size * 0.5;
                var tw = c.CreateTween().SetLoops();
                tw.TweenInterval(every);
                foreach (var a in new[] { -10.0, 9.0, -6.0, 3.0, 0.0 })
                    tw.TweenProperty(c, "rotation", GD.DegToRad(a), 0.08);
            };
            WhenReady(c, go);
        }

        // ---------------- pieces ----------------
        public static TextureRect Img(Node parent, string path, double px = 40.0)
        {
            var t = new TextureRect();
            t.Texture = Tex(path);
            t.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            t.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
            t.CustomMinimumSize = new Vector2(px, px);
            t.Size = new Vector2(px, px);
            t.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            parent.AddChild(t);
            return t;
        }

        public static TextureRect Icon(Node parent, string name, double px = 40.0)
        {
            return Img(parent, IconPath(name), px);
        }

        public static PanelContainer Badge(Control parent, string n, Vector2? at = null)
        {
            var at_ = at ?? new Vector2(6, -6);
            // A red count bubble pinned to the parent's top-right corner, with a bounce every few seconds.
            var pc = new PanelContainer();
            var sb = new StyleBoxFlat();
            sb.BgColor = new Color("#e8443a");
            sb.BorderColor = new Color("#3a0805");
            sb.SetBorderWidthAll(2);
            sb.SetCornerRadiusAll(11);
            sb.ContentMarginLeft = 6;
            sb.ContentMarginRight = 6;
            sb.ShadowColor = new Color(0, 0, 0, 0.4);
            sb.ShadowSize = 2;
            sb.ShadowOffset = new Vector2(0, 2);
            pc.AddThemeStyleboxOverride("panel", sb);
            pc.CustomMinimumSize = new Vector2(22, 22);
            pc.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            parent.AddChild(pc);
            var l = UI.Label(pc, n, 12, Color.WHITE, UI.HEAVY_FONT);
            l.AutowrapMode = TextServer.AUTOWRAP_OFF;
            l.HorizontalAlignment = HorizontalAlignment.Center;
            pc.AnchorLeft = 1.0;
            pc.AnchorRight = 1.0;
            pc.GrowHorizontal = Control.GROW_DIRECTION_BEGIN;
            pc.OffsetRight = at_.x;
            pc.OffsetLeft = at_.x - 22;
            pc.OffsetTop = at_.y;
            pc.OffsetBottom = at_.y + 22;
            pc.Resized += () => pc.PivotOffset = pc.Size * 0.5;
            WhenReady(pc, () =>
            {
                var tw = pc.CreateTween().SetLoops();
                tw.TweenInterval(2.0);
                tw.TweenProperty(pc, "scale", Vector2.ONE * 1.3, 0.12);
                tw.TweenProperty(pc, "scale", Vector2.ONE * 0.92, 0.1);
                tw.TweenProperty(pc, "scale", Vector2.ONE, 0.1);
            });
            return pc;
        }

        public static PanelContainer Chip(Node parent, string s, Color fill, Color ink, Color? border = null)
        {
            var border_ = border ?? new Color(0, 0, 0, 0);
            var pc = new PanelContainer();
            var sb = new StyleBoxFlat();
            sb.BgColor = fill;
            sb.SetCornerRadiusAll(9);
            sb.ContentMarginLeft = 8;
            sb.ContentMarginRight = 8;
            sb.ContentMarginTop = 2;
            sb.ContentMarginBottom = 2;
            if (border_.a > 0.0)
            {
                sb.BorderColor = border_;
                sb.SetBorderWidthAll(1);
            }
            pc.AddThemeStyleboxOverride("panel", sb);
            pc.SizeFlagsHorizontal = Control.SIZE_SHRINK_BEGIN;
            pc.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            parent.AddChild(pc);
            var l = UI.Label(pc, s, 10, ink, UI.HEAVY_FONT);
            l.AutowrapMode = TextServer.AUTOWRAP_OFF;
            l.HorizontalAlignment = HorizontalAlignment.Center;
            return pc;
        }

        public static PanelContainer IconChip(Node parent, string icon_file, string s, Color fill, Color ink, Color? border = null)
        {
            var border_ = border ?? new Color(0, 0, 0, 0);
            var pc = Chip(parent, "", fill, ink, border_);
            Label l = pc.GetChild(0) as Label;
            pc.RemoveChild(l);
            l.QueueFree();
            var r = new HBoxContainer();
            r.AddThemeConstantOverride("separation", 4);
            r.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            pc.AddChild(r);
            Img(r, icon_file, 16.0);
            var t = UI.Label(r, s, 10, ink, UI.HEAVY_FONT);
            t.AutowrapMode = TextServer.AUTOWRAP_OFF;
            return pc;
        }

        public static void _Diamond(Node parent)
        {
            var holder = new Control();
            holder.CustomMinimumSize = new Vector2(14, 14);
            holder.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            holder.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            parent.AddChild(holder);
            var dia = new Panel();
            var ds = new StyleBoxFlat();
            ds.BgColor = GOLD;
            ds.BorderColor = INK;
            ds.SetBorderWidthAll(2);
            dia.AddThemeStyleboxOverride("panel", ds);
            dia.Size = new Vector2(10, 10);
            dia.Position = new Vector2(2, 2);
            dia.PivotOffset = new Vector2(5, 5);
            dia.Rotation = GD.PI / 4.0;
            dia.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            holder.AddChild(dia);
        }

        public static void _Rule(Node parent, bool fade_left)
        {
            var line = new TextureRect();
            var g = new Gradient();
            g.SetColor(0, fade_left ? new Color(GOLD, 0.0) : GOLD);
            g.SetColor(1, fade_left ? GOLD : new Color(GOLD, 0.0));
            var gt = new GradientTexture2D();
            gt.Gradient = g;
            gt.Width = 64;
            gt.Height = 2;
            line.Texture = gt;
            line.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            line.StretchMode = TextureRect.STRETCH_SCALE;
            line.CustomMinimumSize = new Vector2(0, 3);
            line.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            line.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            line.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            parent.AddChild(line);
        }

        public static VBoxContainer Divider(Node parent, string s, int size = 22, string sub = "")
        {
            // ◆──── TITLE ────◆  with an optional muted line under it
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", 2);
            parent.AddChild(v);
            var r = new HBoxContainer();
            r.AddThemeConstantOverride("separation", 8);
            v.AddChild(r);
            _Rule(r, true);
            _Diamond(r);
            Text(r, s, size, GOLD);
            _Diamond(r);
            _Rule(r, false);
            if (sub != "")
                Center(Body(v, sub, 11, MUTED));
            return v;
        }

        public static Control Ribbon(Control parent, string title, string sub, double width, double height = 52.0, GArray colors = null)
        {
            colors ??= GArray.Of(new Color("#5d89f0"), new Color("#1b2d78"));
            // A banner ribbon with notched ends: a gold outer shape, a coloured inner one, the title and a line under it.
            var c = new Control();
            c.CustomMinimumSize = new Vector2(width, height);
            c.Size = new Vector2(width, height);
            c.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            parent.AddChild(c);
            var n = 16.0;
            Func<double, Vector2[]> shape = (double inset) =>
            {
                var w = width - inset * 2.0;
                var h = height - inset * 2.0;
                var o = new Vector2(inset, inset);
                var k = n - inset * 0.6;
                return new[] { o, o + new Vector2(w, 0), o + new Vector2(w - k, h * 0.5), o + new Vector2(w, h), o + new Vector2(0, h), o + new Vector2(k, h * 0.5) };
            };
            var shadow = new Polygon2D();
            shadow.Polygon = shape(0.0);
            shadow.Color = new Color(0, 0, 0, 0.5);
            shadow.Position = new Vector2(0, 4);
            c.AddChild(shadow);
            var outer = new Polygon2D();
            outer.Polygon = shape(0.0);
            outer.Color = new Color("#e8b546");
            c.AddChild(outer);
            var inner = new Polygon2D();
            inner.Polygon = shape(3.0);
            Vector2[] pts = inner.Polygon;
            var cols = new List<Color>();
            foreach (var pt in pts)
                cols.Add(((Color)colors[0]).Lerp((Color)colors[1], GD.Clampf(pt.y / height, 0.0, 1.0)));
            inner.VertexColors = cols.ToArray();
            c.AddChild(inner);
            var tl = Text(c, title, sub != "" ? (int)(height * 0.44) : (int)(height * 0.5), Color.WHITE, new Color("#0e1433"));
            tl.HorizontalAlignment = HorizontalAlignment.Center;
            tl.Position = new Vector2(0, sub != "" ? 4 : 0);
            tl.Size = new Vector2(width, height * (sub != "" ? 0.56 : 1.0));
            if (sub != "")
            {
                var sl = UI.Label(c, sub, 11, new Color("#ffe39a"), UI.HEAVY_FONT);
                sl.AutowrapMode = TextServer.AUTOWRAP_OFF;
                sl.HorizontalAlignment = HorizontalAlignment.Center;
                sl.AddThemeColorOverride("font_outline_color", new Color("#0e1433"));
                sl.AddThemeConstantOverride("outline_size", 3);
                sl.Position = new Vector2(0, height * 0.58);
                sl.Size = new Vector2(width, height * 0.34);
                sl.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            }
            return c;
        }

        public static Control Bar(Node parent, double value, double max_value, Color? top = null, Color? bottom = null, double h = 12.0)
        {
            top ??= new Color("#b6f3ff");
            bottom ??= new Color("#36b9ea");
            // A rounded progress bar with a gradient fill and a moving shine.
            var c = new Control();
            c.CustomMinimumSize = new Vector2(0, h);
            c.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            c.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            parent.AddChild(c);
            Skin(c, GDict.Of("radius", h * 0.5, "outline", 2.0, "outline_color", new Color("#050818"), "rim", 0.0, "fill_top", new Color(0.01, 0.02, 0.07, 0.95),
                "fill_bottom", new Color(0.03, 0.05, 0.14, 0.95), "shadow_alpha", 0.0, "bevel", -0.2));
            var f = new Control();
            f.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            c.AddChild(f);
            var frac = GD.Clampf(value / GD.Maxf(1.0, max_value), 0.0, 1.0);
            var fs = Skin(f, GDict.Of("radius", h * 0.5 - 2.0, "outline", 0.0, "rim", 0.0, "fill_top", top.Value, "fill_bottom", bottom.Value, "shadow_alpha", 0.0, "gloss", 0.8, "bevel", 0.1));
            Action lay = () =>
            {
                f.Position = new Vector2(2, 2);
                f.Size = new Vector2(GD.Maxf(0.0, (c.Size.x - 4.0) * frac), c.Size.y - 4.0);
                f.Visible = frac > 0.0;
            };
            c.Resized += lay;
            Sweep(f, 2.4, 40.0, 0.6);
            return c;
        }

        public static ImageTexture KnobTexture(int px = 26)
        {
            // a gold slider knob: dark outline, gold body, a highlight
            var n = px * 3;
            var im = Image.Create(n, n, false, ImageFormat.RGBA8);
            var c = new Vector2(n, n) * 0.5;
            for (int y = 0; y < n; y++)
            {
                for (int x = 0; x < n; x++)
                {
                    var d = (new Vector2(x + 0.5, y + 0.5) - c).Length() / (n * 0.5);
                    var col = new Color(0, 0, 0, 0);
                    if (d < 1.0)
                        col = new Color("#2a1604");
                    if (d < 0.84)
                    {
                        var t = (double)y / n;
                        col = new Color("#fff3b8").Lerp(new Color("#d98516"), t);
                        var hl = (new Vector2(x + 0.5, y + 0.5) - c - new Vector2(-n * 0.12, -n * 0.16)).Length() / (n * 0.22);
                        if (hl < 1.0)
                            col = col.Lerp(Color.WHITE, (1.0 - hl) * 0.6);
                    }
                    col.a *= (float)GD.Clampf((1.0 - d) * n * 0.5, 0.0, 1.0);
                    im.SetPixel(x, y, col);
                }
            }
            var tex = ImageTexture.CreateFromImage(im);
            tex.SetSizeOverride((Vector2)new Vector2i(px, px));      // (the facade's set_size_override takes a Vector2)
            return tex;
        }

        public static ImageTexture _knob;

        public static void StyleSlider(HSlider sl)
        {
            if (_knob == null)
                _knob = KnobTexture(26);
            var track = new StyleBoxFlat();
            track.BgColor = new Color(0.01, 0.02, 0.07, 0.95);
            track.BorderColor = new Color("#050818");
            track.SetBorderWidthAll(2);
            track.SetCornerRadiusAll(8);
            track.ContentMarginTop = 7;
            track.ContentMarginBottom = 7;
            var fill = new StyleBoxFlat();
            fill.BgColor = new Color("#ffc94d");
            fill.BorderColor = new Color("#fff3a8");
            fill.BorderWidthTop = 2;
            fill.SetCornerRadiusAll(8);
            fill.ContentMarginTop = 7;
            fill.ContentMarginBottom = 7;
            fill.ShadowColor = new Color(1.0, 0.8, 0.3, 0.45);
            fill.ShadowSize = 4;
            sl.AddThemeStyleboxOverride("slider", track);
            sl.AddThemeStyleboxOverride("grabber_area", fill);
            sl.AddThemeStyleboxOverride("grabber_area_highlight", fill);
            sl.AddThemeIconOverride("grabber", _knob);
            sl.AddThemeIconOverride("grabber_highlight", _knob);
            sl.CustomMinimumSize = new Vector2(0, 30);
        }

        public static Button Toggle(Node parent, string label, string sub, bool on, string key, Action<bool> changed)
        {
            // A label on the left and a pill switch on the right (green ON / dark OFF) that slides.
            var row = new HBoxContainer();
            row.AddThemeConstantOverride("separation", 10);
            parent.AddChild(row);
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", 0);
            v.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            row.AddChild(v);
            Text(v, label.ToUpperInvariant(), 14, Color.WHITE);
            Body(v, sub, 11, MUTED, true);        // (0.31.120: wraps -- a long one pushed Settings past a narrow screen)
            var b = new Button();
            b.ToggleMode = true;
            b.ButtonPressed = on;
            b.FocusMode = Control.FOCUS_NONE;
            foreach (var st_name in new[] { "normal", "hover", "pressed", "focus", "hover_pressed" })
                b.AddThemeStyleboxOverride(st_name, new StyleBoxEmpty());
            b.CustomMinimumSize = new Vector2(74, 36);
            b.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            b.SetMeta("action_key", key);
            row.AddChild(b);
            var sk = Skin(b, ButtonParams(on ? "green" : "grey", 18.0, 3.0));
            var knob = new Panel();
            var ks = new StyleBoxFlat();
            ks.BgColor = new Color("#f2f6ff");
            ks.BorderColor = new Color("#1c2230");
            ks.SetBorderWidthAll(2);
            ks.SetCornerRadiusAll(13);
            ks.ShadowColor = new Color(0, 0, 0, 0.35);
            ks.ShadowSize = 2;
            ks.ShadowOffset = new Vector2(0, 2);
            knob.AddThemeStyleboxOverride("panel", ks);
            knob.Size = new Vector2(26, 26);
            knob.Position = new Vector2(on ? 42 : 6, 4);
            knob.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            b.AddChild(knob);
            var tl = UI.Label(b, on ? "ON" : "OFF", 11, Color.WHITE, UI.HEAVY_FONT);
            tl.AutowrapMode = TextServer.AUTOWRAP_OFF;
            tl.AddThemeColorOverride("font_outline_color", new Color(0, 0, 0, 0.5));
            tl.AddThemeConstantOverride("outline_size", 3);
            tl.Size = new Vector2(30, 26);
            tl.Position = new Vector2(on ? 10 : 38, 3);
            tl.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            b.Toggled += (bool now_on) =>
            {
                GArray c = now_on ? BTN["green"].A : BTN["grey"].A;
                sk.SetParam("fill_top", c[0]);
                sk.SetParam("fill_bottom", c[1]);
                sk.SetParam("lip_color", c[2]);
                sk.SetParam("outline_color", c[3]);
                tl.Text = now_on ? "ON" : "OFF";
                var tp = tl.Position;
                tp.x = now_on ? 10 : 38;
                tl.Position = tp;
                b.CreateTween().TweenProperty(knob, "position:x", now_on ? 42.0 : 6.0, 0.15).SetTrans(Tween.TRANS_BACK);
                changed(now_on);
            };
            return b;
        }

        public static void DimButton(Button b, bool off)
        {
            b.Disabled = off;                       // (its skin greys itself: skin.gd)
        }

        public static ImageTexture RayTexture(Color? color = null, int rays = 14)
        {
            var color_ = color ?? new Color(1, 0.9, 0.6);
            // Soft sunburst: alternating rays fading out from the centre (for chest reveals, the prize and VICTORY).
            var n = 256;
            var im = Image.Create(n, n, false, ImageFormat.RGBA8);
            var c = new Vector2(n, n) * 0.5;
            for (int y = 0; y < n; y++)
            {
                for (int x = 0; x < n; x++)
                {
                    var d = new Vector2(x + 0.5, y + 0.5) - c;
                    var r = d.Length() / (n * 0.5);
                    if (r > 1.0)
                    {
                        im.SetPixel(x, y, new Color(0, 0, 0, 0));
                        continue;
                    }
                    var a = Math.Atan2(d.y, d.x);
                    var ray = Math.Pow(GD.Maxf(0.0, Math.Cos(a * rays)), 3.0);
                    var fade = (1.0 - r) * (1.0 - r);
                    im.SetPixel(x, y, new Color(color_, GD.Clampf(ray * fade * 1.2 + (1.0 - r) * 0.12, 0.0, 1.0)));
                }
            }
            return ImageTexture.CreateFromImage(im);
        }

        public static TextureRect Rays(Control parent, double size, Color? color = null, double secs = 30.0, double alpha = 0.5)
        {
            var color_ = color ?? new Color(1, 0.9, 0.6);
            var t = new TextureRect();
            t.Texture = _RaysCached(color_);
            t.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            t.Size = new Vector2(size, size);
            t.CustomMinimumSize = new Vector2(size, size);
            t.PivotOffset = new Vector2(size, size) * 0.5;
            t.Modulate = new Color(1, 1, 1, alpha);
            t.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            var mat = new CanvasItemMaterial();
            mat.BlendMode = CanvasBlendMode.Add;
            t.Material = mat;
            parent.AddChild(t);
            Action go = () =>
            {
                var tw = t.CreateTween().SetLoops();
                tw.TweenProperty(t, "rotation", GD.TAU, secs).From(0.0);
            };
            WhenReady(t, go);
            return t;
        }

        public static GDict _ray_cache = new GDict();

        public static ImageTexture _RaysCached(Color color)
        {
            var k = color.ToHtmlExact();
            if (!_ray_cache.Has(k))
                _ray_cache[k] = Var.Of(RayTexture(color));
            return _ray_cache[k].As<ImageTexture>();
        }

        public static GradientTexture2D GlowTex()
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
            return gt;
        }

        public static TextureRect Glow(Control parent, Rect2 rect, Color color, bool breathe = true)
        {
            var t = new TextureRect();
            t.Texture = GlowTex();
            t.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            t.StretchMode = TextureRect.STRETCH_SCALE;
            t.Position = rect.position;
            t.Size = rect.size;
            t.Modulate = color;
            t.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            parent.AddChild(t);
            if (breathe)
            {
                Action go = () =>
                {
                    var tw = t.CreateTween().SetLoops();
                    tw.TweenProperty(t, "modulate:a", color.a * 0.5, 1.4).SetTrans(Tween.TRANS_SINE);
                    tw.TweenProperty(t, "modulate:a", (double)color.a, 1.4).SetTrans(Tween.TRANS_SINE);
                };
                WhenReady(t, go);
            }
            return t;
        }
    }
}
