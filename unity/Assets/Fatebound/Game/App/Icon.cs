// Ported from godot/scripts/app/icon.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Color = Fatebound.GUI.Col;

namespace Fatebound.Game
{
    // Crisp procedural icons (no image assets): currencies, tabs, classes and item types.
    // Drawn in a 32x32 design space scaled to the control.
    public class Icon : Control
    {
        public string kind = "coin";
        public Color tint = Color.WHITE;

        protected override void _Ready()
        {
            Resized += QueueRedraw;
        }

        protected override void _Draw()
        {
            var s = GD.Minf(Size.x, Size.y) / 32.0;
            DrawSetTransform(Size * 0.5, 0.0, new Vector2(s, s));
            var w = tint;
            switch (kind)
            {
                case "coin":
                {
                    // 0.31.49: the gold coin is the rendered MegaKit coin (assets/ui/currency/coin.png), like everywhere else
                    Texture2D ct = ResourceLoader.Load<Texture2D>("res://assets/ui/currency/coin.png");
                    if (ct != null)
                    {
                        DrawTextureRect(ct, new Rect2(-16, -16, 32, 32), false);
                        return;
                    }
                    DrawCircle(Vector2.ZERO, 14, new Color("#8a5a0c"));
                    DrawCircle(new Vector2(0, -1), 13, new Color("#ffcf4a"));
                    DrawArc(new Vector2(0, -1), 9.5, 0, GD.TAU, 32, new Color("#e0a226"), 2.5, true);
                    DrawRect(new Rect2(-2, -7, 4, 12), new Color("#e0a226"));
                    DrawArc(new Vector2(-4, -6), 5, GD.PI * 1.1, GD.PI * 1.6, 8, new Color(1, 1, 1, 0.8), 2, true);
                    break;
                }
                case "gem":
                {
                    var top = new[] { new Vector2(-13, -4), new Vector2(-7, -12), new Vector2(7, -12), new Vector2(13, -4) };
                    var body = new[] { new Vector2(-13, -4), new Vector2(13, -4), new Vector2(0, 14) };
                    DrawColoredPolygon(top, new Color("#b9f3ff"));
                    DrawColoredPolygon(body, new Color("#3fb8e8"));
                    DrawColoredPolygon(new[] { new Vector2(-5, -4), new Vector2(5, -4), new Vector2(0, 14) }, new Color("#7fdcff"));
                    DrawPolyline(new[] { new Vector2(-13, -4), new Vector2(-7, -12), new Vector2(7, -12), new Vector2(13, -4), new Vector2(0, 14), new Vector2(-13, -4) }, new Color("#0f4a73"), 1.5, true);
                    break;
                }
                case "xp":
                case "star":
                {
                    var pts = new List<Vector2>();
                    for (int i = 0; i < 10; i++)
                    {
                        var r = i % 2 == 0 ? 14.0 : 6.0;
                        var a = -GD.PI / 2 + i * GD.PI / 5;
                        pts.Add(new Vector2(Math.Cos(a), Math.Sin(a)) * r);
                    }
                    DrawColoredPolygon(pts, kind == "star" ? w : new Color("#7fe0ff"));
                    break;
                }
                case "home":
                    DrawRect(new Rect2(-12, -2, 24, 14), w);
                    foreach (var x in new[] { -12, -4, 4 })
                        DrawRect(new Rect2(x, -6, 5, 4), w);
                    DrawRect(new Rect2(-4, -13, 8, 11), w);
                    DrawRect(new Rect2(-2.5, 4, 5, 8), new Color(0, 0, 0, 0.55));
                    break;
                case "pass":
                {
                    DrawColoredPolygon(new[] { new Vector2(-10, -13), new Vector2(10, -13), new Vector2(10, 13), new Vector2(0, 7), new Vector2(-10, 13) }, w);
                    var sp = new List<Vector2>();
                    for (int i = 0; i < 10; i++)
                    {
                        var r = i % 2 == 0 ? 6.0 : 2.6;
                        var a = -GD.PI / 2 + i * GD.PI / 5;
                        sp.Add(new Vector2(Math.Cos(a), Math.Sin(a)) * r + new Vector2(0, -3));
                    }
                    DrawColoredPolygon(sp, new Color(0, 0, 0, 0.55));
                    break;
                }
                case "shop":
                    DrawArc(new Vector2(0, -6), 6, GD.PI, GD.TAU, 16, w, 2.5, true);
                    DrawColoredPolygon(new[] { new Vector2(-12, -5), new Vector2(12, -5), new Vector2(10, 13), new Vector2(-10, 13) }, w);
                    DrawCircle(new Vector2(0, 3), 2.2, new Color(0, 0, 0, 0.55));
                    break;
                case "locker":
                    // knight helm
                    DrawColoredPolygon(new[] { new Vector2(-11, 12), new Vector2(-11, -3), new Vector2(-7, -11), new Vector2(7, -11), new Vector2(11, -3), new Vector2(11, 12) }, w);
                    DrawRect(new Rect2(-9, -2, 18, 3), new Color(0, 0, 0, 0.6));
                    DrawRect(new Rect2(-1.2, 1, 2.4, 10), new Color(0, 0, 0, 0.45));
                    break;
                case "gear":
                    for (int i = 0; i < 8; i++)
                    {
                        var a = i * GD.TAU / 8;
                        DrawSetTransform(Size * 0.5, a, new Vector2(s, s));
                        DrawRect(new Rect2(-3, -15, 6, 6), w);
                    }
                    DrawSetTransform(Size * 0.5, 0.0, new Vector2(s, s));
                    DrawCircle(Vector2.ZERO, 10, w);
                    DrawCircle(Vector2.ZERO, 4.5, new Color(0, 0, 0, 0.6));
                    break;
                case "play":
                    DrawColoredPolygon(new[] { new Vector2(-8, -12), new Vector2(12, 0), new Vector2(-8, 12) }, w);
                    break;
                case "lock":
                    DrawArc(new Vector2(0, -3), 7, GD.PI, GD.TAU, 16, w, 3, true);
                    DrawLine(new Vector2(-7, -3), new Vector2(-7, 1), w, 3);
                    DrawLine(new Vector2(7, -3), new Vector2(7, 1), w, 3);
                    DrawRect(new Rect2(-10, 0, 20, 13), w);
                    DrawCircle(new Vector2(0, 6), 2.2, new Color(0, 0, 0, 0.6));
                    break;
                case "check":
                    DrawPolyline(new[] { new Vector2(-11, 1), new Vector2(-3, 9), new Vector2(12, -8) }, w, 4.5, true);
                    break;
                case "crown":
                    DrawColoredPolygon(new[] { new Vector2(-13, 10), new Vector2(-13, -8), new Vector2(-6, 0), new Vector2(0, -11), new Vector2(6, 0), new Vector2(13, -8), new Vector2(13, 10) }, w);
                    break;
                case "clock":
                    DrawArc(Vector2.ZERO, 12, 0, GD.TAU, 28, w, 3, true);
                    DrawLine(Vector2.ZERO, new Vector2(0, -7), w, 2.5);
                    DrawLine(Vector2.ZERO, new Vector2(5, 3), w, 2.5);
                    break;
                case "skin":
                    DrawColoredPolygon(new[] { new Vector2(-6, -12), new Vector2(6, -12), new Vector2(13, -6), new Vector2(9, -1), new Vector2(7, -3), new Vector2(7, 13), new Vector2(-7, 13), new Vector2(-7, -3), new Vector2(-9, -1), new Vector2(-13, -6) }, w);
                    break;
                case "weapon":
                case "knight":
                    DrawSetTransform(Size * 0.5, GD.PI / 4, new Vector2(s, s));
                    DrawRect(new Rect2(-2, -14, 4, 20), w);
                    DrawRect(new Rect2(-7, 5, 14, 3), w);
                    DrawRect(new Rect2(-1.5, 8, 3, 6), w.Darkened(0.3));
                    DrawSetTransform(Size * 0.5, 0.0, new Vector2(s, s));
                    break;
                case "barbarian":
                    DrawLine(new Vector2(-8, 13), new Vector2(6, -9), w.Darkened(0.3), 3);
                    DrawColoredPolygon(new[] { new Vector2(1, -13), new Vector2(13, -8), new Vector2(9, 3), new Vector2(3, -3) }, w);
                    break;
                case "rogue":
                    DrawColoredPolygon(new[] { new Vector2(0, -14), new Vector2(4, 2), new Vector2(-4, 2) }, w);
                    DrawRect(new Rect2(-7, 2, 14, 3), w);
                    DrawRect(new Rect2(-1.5, 5, 3, 8), w.Darkened(0.3));
                    break;
                case "ranger":
                    DrawArc(new Vector2(-4, 0), 13, -GD.PI / 2.6, GD.PI / 2.6, 16, w, 3, true);
                    DrawLine(new Vector2(0.5, -12), new Vector2(0.5, 12), w.Darkened(0.2), 1.2);
                    DrawLine(new Vector2(-10, 0), new Vector2(12, 0), w, 2);
                    DrawColoredPolygon(new[] { new Vector2(14, 0), new Vector2(9, -3), new Vector2(9, 3) }, w);
                    break;
                case "mage":
                    DrawLine(new Vector2(-6, 13), new Vector2(4, -6), w.Darkened(0.25), 3);
                    DrawCircle(new Vector2(6, -9), 5, w);
                    DrawCircle(new Vector2(6, -9), 2.2, new Color(1, 1, 1, 0.8));
                    break;
                case "worker":
                    DrawLine(new Vector2(-9, 12), new Vector2(6, -3), w.Darkened(0.3), 3);
                    DrawColoredPolygon(new[] { new Vector2(0, -8), new Vector2(10, -13), new Vector2(13, -4), new Vector2(6, -1) }, w);
                    break;
                case "title":
                    DrawRect(new Rect2(-10, -9, 20, 18), w);
                    DrawCircle(new Vector2(-10, -9), 3, w.Darkened(0.2));
                    DrawCircle(new Vector2(10, 9), 3, w.Darkened(0.2));
                    foreach (var y in new[] { -4, 0, 4 })
                        DrawLine(new Vector2(-6, y), new Vector2(6, y), new Color(0, 0, 0, 0.5), 1.5);
                    break;
                case "plus":
                    DrawRect(new Rect2(-2, -9, 4, 18), w);
                    DrawRect(new Rect2(-9, -2, 18, 4), w);
                    break;
                case "chest":                                         // 0.31.37: a chest -- lid, body, band and lock, in the tint
                {
                    var body = tint != Color.WHITE ? tint : new Color("#c48a4a");
                    DrawRect(new Rect2(-13, -2, 26, 13), body.Darkened(0.15));
                    DrawColoredPolygon(new[] { new Vector2(-13, -2), new Vector2(-13, -7), new Vector2(-9, -12), new Vector2(9, -12), new Vector2(13, -7), new Vector2(13, -2) }, body);
                    DrawRect(new Rect2(-13, -3, 26, 2), new Color(0.15, 0.1, 0.06));
                    DrawRect(new Rect2(-9, -12, 3, 23), new Color(0.2, 0.14, 0.08, 0.6));
                    DrawRect(new Rect2(6, -12, 3, 23), new Color(0.2, 0.14, 0.08, 0.6));
                    DrawRect(new Rect2(-3, -5, 6, 7), new Color("#ffd75e"));
                    DrawRect(new Rect2(-1, -2, 2, 3), new Color(0.15, 0.1, 0.06));
                    break;
                }
                case "trophy":
                    DrawColoredPolygon(new[] { new Vector2(-9, -12), new Vector2(9, -12), new Vector2(7, -2), new Vector2(0, 3), new Vector2(-7, -2) }, w);
                    DrawRect(new Rect2(-2, 3, 4, 5), w);
                    DrawRect(new Rect2(-7, 8, 14, 4), w);
                    break;
                default:
                    DrawCircle(Vector2.ZERO, 10, w);
                    break;
            }
        }
    }
}
