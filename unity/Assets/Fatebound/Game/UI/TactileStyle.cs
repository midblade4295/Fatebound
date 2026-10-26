// Ported from godot/scripts/ui/tactile_style.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Color = Fatebound.GUI.Col;

namespace Fatebound.Game
{
    // A dimensional button face: drop shadow, darker "lip" for physical depth, a vertical gradient body,
    // a glossy top highlight and a bright rim. The pressed state sinks the body into its lip.
    public class TactileStyle : StyleBox
    {
        public Color top = Color.FromCode("#244354");
        public Color bottom = Color.FromCode("#122836");
        public Color lip = Color.FromCode("#07131b");
        public Color rim = Color.FromCode("#b8904f");
        public Color glow = new Color(0, 0, 0, 0);
        public double radius = 12.0;
        public double depth = 4.0;
        public bool pressed = false;
        public double gloss = 0.22;

        public List<Vector2> _Rounded(Rect2 rect, double r)
        {
            var pts = new List<Vector2>();
            r = GD.Minf(r, GD.Minf(rect.size.x, rect.size.y) * 0.5);
            var corners = new[] {
                (rect.position + new Vector2(rect.size.x - r, r), -GD.PI * 0.5),
                (rect.position + new Vector2(rect.size.x - r, rect.size.y - r), 0.0),
                (rect.position + new Vector2(r, rect.size.y - r), GD.PI * 0.5),
                (rect.position + new Vector2(r, r), GD.PI),
            };
            foreach (var c in corners)
            {
                for (int k = 0; k < 7; k++)
                {
                    double a = c.Item2 + k * (GD.PI * 0.5) / 6.0;
                    pts.Add(c.Item1 + new Vector2(GD.Cos(a), GD.Sin(a)) * r);
                }
            }
            return pts;
        }

        public void _Fill(DrawList ci, Rect2 rect, double r, Color c_top, Color c_bottom)
        {
            if (rect.size.x < 2 || rect.size.y < 2)
                return;
            var pts = _Rounded(rect, r);
            var cols = new List<Color>();
            foreach (var p in pts)
            {
                var t = GD.Clampf(((double)p.y - rect.position.y) / rect.size.y, 0, 1);
                cols.Add(c_top.Lerp(c_bottom, t));
            }
            RenderingServer.CanvasItemAddPolygon(ci, pts, cols);
        }

        public void _Outline(DrawList ci, Rect2 rect, double r, Color color, double width)
        {
            var pts = _Rounded(rect, r);
            pts.Add(pts[0]);
            RenderingServer.CanvasItemAddPolyline(ci, pts, new List<Color> { color }, width, true);
        }

        // (GDScript's _draw(ci, rect): the facade's StyleBox draws through Draw)
        public override void Draw(DrawList ci, Rect2 rect)
        {
            var sink = pressed ? depth - 1.0 : 0.0;
            var body = new Rect2(rect.position + new Vector2(0, sink), new Vector2(rect.size.x, rect.size.y - depth));
            // Outer glow for primary/active controls.
            if (glow.a > 0.0)
            {
                for (int i = 0; i < 3; i++)
                {
                    var g = glow;
                    g.a = (float)(glow.a * (0.45 - i * 0.13));
                    _Outline(ci, rect.Grow(2.0 + i * 2.2), radius + 2.0 + i * 2.2, g, 2.2);
                }
            }
            // Contact shadow and the physical lip under the face.
            _Fill(ci, new Rect2(rect.position + new Vector2(1, 3), rect.size), radius, new Color(0, 0, 0, 0.0), new Color(0, 0, 0, 0.42));
            _Fill(ci, new Rect2(rect.position + new Vector2(0, depth), new Vector2(rect.size.x, rect.size.y - depth)), radius, lip.Lightened(0.08), lip);
            // Gradient face.
            _Fill(ci, body, radius, top, bottom);
            // Gloss: a soft band across the upper half.
            var shine = new Rect2(body.position + new Vector2(3, 2), new Vector2(body.size.x - 6, body.size.y * 0.46));
            _Fill(ci, shine, GD.Maxf(2.0, radius - 3.0), new Color(1, 1, 1, gloss), new Color(1, 1, 1, 0.0));
            // Crisp rim plus an inner bevel line.
            _Outline(ci, body, radius, rim, 1.6);
            var inner = body.Grow(-2.0);
            _Outline(ci, inner, GD.Maxf(2.0, radius - 2.0), new Color(1, 1, 1, !pressed ? 0.10 : 0.04), 1.0);
        }
    }
}
