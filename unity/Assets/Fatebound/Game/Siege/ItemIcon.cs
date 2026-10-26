// Ported from godot/scripts/siege/item_icon.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Color = Fatebound.GUI.Col;
using Transform2D = Fatebound.GUI.Xform2;
using Moba = Fatebound.Sim.Moba;

namespace Fatebound.Game
{
    // 0.31.157 5V5: an item's glyph (scripts/siege/moba.gd ITEMS), drawn, not an image -- the shop's cells and slots use this
    // Control; the HUD's item slots call draw_item() on its own canvas. 0.31.175 (Kevin: "make these menus better looking
    // and more high quality"): each item its own painted icon (assets/ui/items/<id>.png, tools/build_menu_icons.py); the
    // drawn glyph only if one is missing.
    public class ItemIcon : Control
    {
        public const string DIR = "res://assets/ui/items/";
        public static GDict _tex = new GDict();

        public static Texture2D Texture(string id)
        {
            if (!_tex.Has(id))
            {
                var p = DIR + id + ".png";
                _tex[id] = ResourceLoader.Exists(p) ? Var.Of(ResourceLoader.Load(p)) : Var.Nil;
            }
            return _tex[id].As<Texture2D>();
        }

        public static readonly GDict ITEM_TINT = new GDict { { "sword", "#d8dee6" }, { "ruby", "#e8304a" }, { "dagger", "#cfd6de" }, { "boots", "#9a6a3a" }, { "tome", "#3a6bd0" }, { "fang", "#f2ead8" },
            { "bead", "#4ad07a" }, { "cloth", "#9aa6b2" }, { "greaves", "#e0b040" }, { "bloodthirster", "#e04040" }, { "titan", "#ff8a3a" }, { "phantom", "#9a6bff" },
            { "archon", "#a050ff" }, { "thorn", "#5aa860" }, { "relic", "#ffd65a" } };
        public string item = "";
        public bool dim = false;

        protected override void _Draw()
        {
            if (item != "")
                DrawItem(this, item, Size * 0.5, GD.Minf(Size.x, Size.y), dim);
        }

        // (PackedVector2Array + PackedVector2Array([p]): the polygon closed for its outline)
        static List<Vector2> _Closed(IList<Vector2> pts)
        {
            var o = new List<Vector2>(pts);
            o.Add(pts[0]);
            return o;
        }

        // (Transform2D * PackedVector2Array)
        static List<Vector2> _Xf(Transform2D tf, IList<Vector2> pts)
        {
            var o = new List<Vector2>(pts.Count);
            foreach (var p in pts)
                o.Add(tf.Xform(p));
            return o;
        }

        public static void DrawItem(CanvasItem ci, string id, Vector2 c, double sz, bool dim = false)
        {
            // an item's painted icon; or its glyph, drawn in a 32x32 space (crisp at any size), the big items on a gold disc
            var t = Texture(id);
            if (t != null)
            {
                ci.DrawTextureRect(t, new Rect2(c - new Vector2(sz, sz) * 0.5, new Vector2(sz, sz)), false,
                    dim ? new Color(0.58, 0.58, 0.64) : Color.WHITE);
                return;
            }
            ItemDef it = Moba.ITEMS.TryGetValue(id, out var itd) ? itd : null;
            var tint = Color.FromCode(GD.Str(ITEM_TINT.Get(id, "#ffffff")));
            if (dim)
                tint = tint.Darkened(0.45);
            var k = sz / 32.0;
            var ink = new Color(0.07, 0.05, 0.03);
            var gold = !dim ? new Color("#d9b04a") : new Color("#7a6230");
            bool has_from = it != null && it.from.Length > 0;       // (it.has("from"): a big item)
            if (has_from)
            {
                ci.DrawCircle(c, 15.5 * k, new Color(0.16, 0.1, 0.03, 0.9));
                ci.DrawArc(c, 15.0 * k, 0, GD.TAU, 32, gold, 1.6 * k, true);
            }
            var rot = 0.0;
            switch (it != null ? GD.Str(it.icon ?? "") : "")
            {
                case "sword": rot = -GD.PI * 0.25; break;
                case "dagger": rot = GD.PI * 0.2; break;
            }
            ci.DrawSetTransform(c, rot, new Vector2(k, k));
            switch (it != null ? GD.Str(it.icon ?? "") : "")
            {
                case "sword":
                    {
                        var blade = new List<Vector2> { new Vector2(0, -15), new Vector2(2.6, -11), new Vector2(2.6, 5), new Vector2(-2.6, 5), new Vector2(-2.6, -11) };
                        ci.DrawColoredPolygon(blade, tint);
                        ci.DrawPolyline(_Closed(blade), ink, 1.0, true);
                        ci.DrawLine(new Vector2(0, -11), new Vector2(0, 4), tint.Lightened(0.4), 1.0);
                        ci.DrawRect(new Rect2(-7, 5, 14, 3), gold);
                        ci.DrawRect(new Rect2(-1.4, 8, 2.8, 5), new Color("#6a4022"));
                        ci.DrawCircle(new Vector2(0, 14.5), 2.2, gold);
                        break;
                    }
                case "dagger":
                    foreach (var sx in new[] { -1.0, 1.0 })
                    {
                        var b = new List<Vector2> { new Vector2(0, -12), new Vector2(2.4, -8), new Vector2(2.4, 3), new Vector2(-2.4, 3), new Vector2(-2.4, -8) };
                        var tf = Transform2D.FromRotation(sx * 0.35, new Vector2(sx * 3.5, 0));
                        var bb = _Xf(tf, b);
                        ci.DrawColoredPolygon(bb, tint);
                        ci.DrawPolyline(_Closed(bb), ink, 1.0, true);
                        ci.DrawColoredPolygon(_Xf(tf, new List<Vector2> { new Vector2(-5.5, 3), new Vector2(5.5, 3), new Vector2(5.5, 5.4), new Vector2(-5.5, 5.4) }), gold);
                        ci.DrawColoredPolygon(_Xf(tf, new List<Vector2> { new Vector2(-1.2, 5.4), new Vector2(1.2, 5.4), new Vector2(1.2, 10.5), new Vector2(-1.2, 10.5) }), new Color("#6a4022"));
                    }
                    break;
                case "ruby":
                    {
                        var hexp = new List<Vector2>();
                        var inner = new List<Vector2>();
                        for (int i = 0; i < 6; i++)
                        {
                            var a = GD.PI / 6.0 + GD.TAU * (double)i / 6.0;
                            hexp.Add(new Vector2(Math.Cos(a), Math.Sin(a)) * 12.5);
                            inner.Add(new Vector2(Math.Cos(a), Math.Sin(a)) * 6.0);
                        }
                        ci.DrawColoredPolygon(hexp, tint);
                        ci.DrawColoredPolygon(inner, tint.Lightened(0.3));
                        ci.DrawPolyline(_Closed(hexp), ink, 1.0, true);
                        ci.DrawColoredPolygon(new List<Vector2> { new Vector2(-7, -6), new Vector2(-2, -9), new Vector2(-4, -3) }, new Color(1, 1, 1, 0.7));
                        break;
                    }
                case "boots":
                    {
                        var bt = new List<Vector2> { new Vector2(-7, -12), new Vector2(3, -12), new Vector2(3, 3), new Vector2(12, 6), new Vector2(12, 12), new Vector2(-7, 12) };
                        ci.DrawColoredPolygon(bt, tint);
                        ci.DrawPolyline(_Closed(bt), ink, 1.0, true);
                        ci.DrawRect(new Rect2(-7, 10, 19, 2.5), tint.Darkened(0.5));
                        ci.DrawRect(new Rect2(-8.5, -14, 13, 4), tint.Lightened(0.35));
                        if (has_from)
                            ci.DrawColoredPolygon(new List<Vector2> { new Vector2(-8, -6), new Vector2(-15, -11), new Vector2(-13, -4), new Vector2(-15, 0), new Vector2(-8, -1) }, new Color("#fff1c2"));
                        break;
                    }
                case "tome":
                    ci.DrawRect(new Rect2(-10, -13, 20, 26), tint);
                    ci.DrawRect(new Rect2(-10, -13, 3.5, 26), tint.Darkened(0.4));
                    ci.DrawRect(new Rect2(7, -11, 2.5, 22), new Color("#f2e6c8"));
                    ci.DrawRect(new Rect2(-10, -13, 20, 26), ink, false, 1.0);
                    ci.DrawCircle(new Vector2(1, 0), 4.2, gold);
                    ci.DrawCircle(new Vector2(1, 0), 2.0, tint.Lightened(0.5));
                    break;
                case "fang":
                    {
                        var fg = new List<Vector2> { new Vector2(-7, -13), new Vector2(7, -13), new Vector2(5, -4), new Vector2(1, 13), new Vector2(-2, -4) };
                        ci.DrawColoredPolygon(fg, tint);
                        ci.DrawPolyline(_Closed(fg), ink, 1.0, true);
                        ci.DrawColoredPolygon(new List<Vector2> { new Vector2(-0.5, 5), new Vector2(3, 5), new Vector2(1, 13) }, new Color("#d42a2a"));
                        break;
                    }
                case "bead":
                    ci.DrawArc(new Vector2(0, -12), 7.0, GD.PI * 1.15, GD.PI * 1.85, 10, new Color("#c8b07a"), 1.4, true);
                    ci.DrawCircle(new Vector2(0, 2), 10.0, tint);
                    ci.DrawArc(new Vector2(0, 2), 10.0, 0, GD.TAU, 24, ink, 1.0, true);
                    ci.DrawCircle(new Vector2(-3.5, -1.5), 3.0, new Color(1, 1, 1, 0.6));
                    break;
                case "shield":
                    {
                        var sh = new List<Vector2> { new Vector2(-11, -13), new Vector2(11, -13), new Vector2(11, 0), new Vector2(0, 14), new Vector2(-11, 0) };
                        ci.DrawColoredPolygon(sh, tint);
                        ci.DrawPolyline(_Closed(sh), ink, 1.0, true);
                        ci.DrawRect(new Rect2(-1.6, -11, 3.2, 21), gold);
                        ci.DrawRect(new Rect2(-9, -5.5, 18, 3.2), gold);
                        break;
                    }
            }
            ci.DrawSetTransform(Vector2.ZERO, 0.0, Vector2.ONE);
        }
    }
}
