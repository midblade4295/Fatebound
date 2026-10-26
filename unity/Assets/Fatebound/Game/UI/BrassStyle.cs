// Ported from godot/scripts/ui/brass_style.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Color = Fatebound.GUI.Col;

namespace Fatebound.Game
{
    // Beveled brass-framed panel: soft drop shadow, a 2px brass rim lit from above, an inner dark bevel
    // line, a faint inner highlight and a dark navy/charcoal body with a gentle vertical gradient.
    public class BrassStyle : StyleBox
    {
        public Color top = Color.FromCode("#16222b");
        public Color bottom = Color.FromCode("#0b1116");
        public Color rim_light = Color.FromCode("#f0cf82");
        public Color rim_dark = Color.FromCode("#6f4f1e");
        public double radius = 12.0;
        public double rim = 2.0;
        public Color glow = new Color(0, 0, 0, 0);
        public double shadow = 0.5;
        public bool ornate = false;

        public List<Vector2> _Rounded(Rect2 rect, double r)
        {
            var pts = new List<Vector2>();
            r = GD.Maxf(0.0, GD.Minf(r, GD.Minf(rect.size.x, rect.size.y) * 0.5));
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

        public void _Fill(DrawList ci, Rect2 rect, double r, Color a, Color b)
        {
            if (rect.size.x < 2 || rect.size.y < 2)
                return;
            var pts = _Rounded(rect, r);
            var cols = new List<Color>();
            foreach (var p in pts)
                cols.Add(a.Lerp(b, GD.Clampf(((double)p.y - rect.position.y) / rect.size.y, 0, 1)));
            RenderingServer.CanvasItemAddPolygon(ci, pts, cols);
        }

        public void _Line(DrawList ci, Rect2 rect, double r, Color color, double width)
        {
            var pts = _Rounded(rect, r);
            pts.Add(pts[0]);
            RenderingServer.CanvasItemAddPolyline(ci, pts, new List<Color> { color }, width, true);
        }

        // (GDScript's _draw(ci, rect): the facade's StyleBox draws through Draw)
        public override void Draw(DrawList ci, Rect2 rect)
        {
            if (glow.a > 0.0)
            {
                for (int i = 0; i < 3; i++)
                {
                    var g = glow;
                    g.a = (float)(glow.a * (0.5 - i * 0.14));
                    _Line(ci, rect.Grow(2.0 + i * 2.4), radius + 2.0 + i * 2.4, g, 2.4);
                }
            }
            if (shadow > 0.0)
                _Fill(ci, new Rect2(rect.position + new Vector2(0, 3), rect.size).Grow(1.0), radius + 1.0, new Color(0, 0, 0, 0.0), new Color(0, 0, 0, shadow));
            // Brass rim: a filled plate lit from the top, then the body inset by the rim width.
            _Fill(ci, rect, radius, rim_light, rim_dark);
            var body = rect.Grow(-rim);
            _Fill(ci, body, radius - rim, top, bottom);
            // Inner dark bevel and a hairline highlight just inside it.
            _Line(ci, body.Grow(-0.75), radius - rim - 0.75, new Color(0, 0, 0, 0.55 * top.a), 1.5);
            _Line(ci, body.Grow(-2.2), radius - rim - 2.2, new Color(1, 1, 1, 0.05), 1.0);
            // Gloss across the top of the body.
            _Fill(ci, new Rect2(body.position + new Vector2(3, 2), new Vector2(body.size.x - 6, GD.Minf(22.0, body.size.y * 0.35))), GD.Maxf(2.0, radius - rim - 2.0), new Color(1, 1, 1, 0.06), new Color(1, 1, 1, 0.0));
            if (ornate)
            {
                // Small diamond studs at the four corners of a title plate.
                foreach (var c in new[] { rect.position + new Vector2(radius * 0.6, radius * 0.6), new Vector2(rect.End.x - radius * 0.6, rect.position.y + radius * 0.6),
                        new Vector2(rect.position.x + radius * 0.6, rect.End.y - radius * 0.6), rect.End - new Vector2(radius * 0.6, radius * 0.6) })
                {
                    var d = 4.0;
                    RenderingServer.CanvasItemAddPolygon(ci, new List<Vector2> { c + new Vector2(0, -d), c + new Vector2(d, 0), c + new Vector2(0, d), c + new Vector2(-d, 0) }, new List<Color> { rim_light });
                }
            }
        }
    }
}
