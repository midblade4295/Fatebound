// Software rasteriser for the GUI's render batches: triangles with per-vertex colour, bilinear texture sampling
// (clamp or repeat), SDF text (smoothstep around the threshold, width from the screen-space uv derivative), per-vertex
// clip rectangles, straight-alpha "mix" blending (and add/mul for CanvasItemMaterial). Mirrors what the Unity shader does.
using System;
using System.Collections.Generic;
using Fatebound.GUI;

namespace GuiTest
{
    public sealed class SoftRaster
    {
        public readonly int W, H;
        readonly float[] _buf;

        public SoftRaster(int w, int h, Col clear)
        {
            W = w; H = h;
            _buf = new float[w * h * 4];
            for (int i = 0; i < w * h; i++) { _buf[i * 4] = clear.r; _buf[i * 4 + 1] = clear.g; _buf[i * 4 + 2] = clear.b; _buf[i * 4 + 3] = clear.a; }
        }

        static float Clamp01(float v) => v < 0 ? 0 : v > 1 ? 1 : v;

        static void Sample(RgbaImage img, float u, float v, bool repeat, out float r, out float g, out float b, out float a)
        {
            if (img == null) { r = g = b = a = 1; return; }
            float x = u * img.W - 0.5f, y = v * img.H - 0.5f;
            int x0 = (int)MathF.Floor(x), y0 = (int)MathF.Floor(y);
            float fx = x - x0, fy = y - y0;
            r = g = b = a = 0;
            for (int k = 0; k < 4; k++)
            {
                int xi = x0 + (k & 1), yi = y0 + (k >> 1);
                if (repeat) { xi = ((xi % img.W) + img.W) % img.W; yi = ((yi % img.H) + img.H) % img.H; }
                else { xi = Math.Clamp(xi, 0, img.W - 1); yi = Math.Clamp(yi, 0, img.H - 1); }
                float wgt = ((k & 1) != 0 ? fx : 1 - fx) * ((k >> 1) != 0 ? fy : 1 - fy);
                int q = (yi * img.W + xi) * 4;
                float pa = img.Px[q + 3] / 255f;
                // premultiplied filtering (avoids dark fringes), unpremultiplied after
                r += img.Px[q] / 255f * pa * wgt; g += img.Px[q + 1] / 255f * pa * wgt; b += img.Px[q + 2] / 255f * pa * wgt; a += pa * wgt;
            }
            if (a > 1e-6f) { r /= a; g /= a; b /= a; }
        }

        public void Draw(List<RenderBatch> batches)
        {
            foreach (var bt in batches)
            {
                var img = bt.texture?.GetHandle() as RgbaImage;
                for (int i = 0; i + 2 < bt.indices.Count; i += 3)
                    Tri(bt, img, bt.verts[bt.indices[i]], bt.verts[bt.indices[i + 1]], bt.verts[bt.indices[i + 2]]);
            }
        }

        void Tri(RenderBatch bt, RgbaImage img, RVert a, RVert b, RVert c)
        {
            float area = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
            if (Math.Abs(area) < 1e-8f) return;
            float minx = MathF.Max(MathF.Min(a.x, MathF.Min(b.x, c.x)), MathF.Max(0, a.cx0));
            float maxx = MathF.Min(MathF.Max(a.x, MathF.Max(b.x, c.x)), MathF.Min(W, a.cx1));
            float miny = MathF.Max(MathF.Min(a.y, MathF.Min(b.y, c.y)), MathF.Max(0, a.cy0));
            float maxy = MathF.Min(MathF.Max(a.y, MathF.Max(b.y, c.y)), MathF.Min(H, a.cy1));
            int x0 = (int)MathF.Floor(minx), x1 = (int)MathF.Ceiling(maxx), y0 = (int)MathF.Floor(miny), y1 = (int)MathF.Ceiling(maxy);
            // uv derivatives for SDF smoothing
            float dudx = ((b.u - a.u) * (c.y - a.y) - (c.u - a.u) * (b.y - a.y)) / area;
            float dudy = ((c.u - a.u) * (b.x - a.x) - (b.u - a.u) * (c.x - a.x)) / area;
            float dvdx = ((b.v - a.v) * (c.y - a.y) - (c.v - a.v) * (b.y - a.y)) / area;
            float dvdy = ((c.v - a.v) * (b.x - a.x) - (b.v - a.v) * (c.x - a.x)) / area;
            float inv = 1f / area;
            for (int y = y0; y < y1; y++)
            {
                if (y < 0 || y >= H) continue;
                float py = y + 0.5f;
                if (py < a.cy0 || py >= a.cy1) continue;
                for (int x = x0; x < x1; x++)
                {
                    if (x < 0 || x >= W) continue;
                    float px = x + 0.5f;
                    if (px < a.cx0 || px >= a.cx1) continue;
                    float w0 = ((b.x - px) * (c.y - py) - (b.y - py) * (c.x - px)) * inv;
                    float w1 = ((c.x - px) * (a.y - py) - (c.y - py) * (a.x - px)) * inv;
                    float w2 = 1 - w0 - w1;
                    const float E = -1e-5f;
                    if (w0 < E || w1 < E || w2 < E) continue;
                    // top-left-ish rule: skip shared right/bottom edges exactly at 0
                    float cr = a.c.r * w0 + b.c.r * w1 + c.c.r * w2;
                    float cg = a.c.g * w0 + b.c.g * w1 + c.c.g * w2;
                    float cb = a.c.b * w0 + b.c.b * w1 + c.c.b * w2;
                    float ca = a.c.a * w0 + b.c.a * w1 + c.c.a * w2;
                    if (bt.texture != null)
                    {
                        float u = a.u * w0 + b.u * w1 + c.u * w2, v = a.v * w0 + b.v * w1 + c.v * w2;
                        if (bt.mode == DrawMode.SdfText)
                        {
                            Sample(img, u, v, false, out _, out _, out _, out float dist);
                            float fw = (MathF.Abs(dudx) + MathF.Abs(dudy) + MathF.Abs(dvdx) + MathF.Abs(dvdy)) * 0.5f * (img?.W ?? 1) / (2f * GlyphAtlas.SPREAD);
                            float edge = 0.5f - bt.aux;
                            float wdt = MathF.Max(fw * 0.75f, 1e-4f);
                            float t = Clamp01((dist - (edge - wdt)) / (2 * wdt));
                            ca *= t * t * (3 - 2 * t);
                        }
                        else
                        {
                            Sample(img, u, v, bt.repeat, out float tr, out float tg, out float tb, out float ta);
                            cr *= tr; cg *= tg; cb *= tb; ca *= ta;
                        }
                    }
                    ca = Clamp01(ca);
                    if (ca <= 0) continue;
                    int q = (y * W + x) * 4;
                    switch (bt.blend)
                    {
                        case CanvasBlendMode.Add:
                            _buf[q] += cr * ca; _buf[q + 1] += cg * ca; _buf[q + 2] += cb * ca; break;
                        case CanvasBlendMode.Mul:
                            _buf[q] *= cr; _buf[q + 1] *= cg; _buf[q + 2] *= cb; break;
                        default:
                            _buf[q] = cr * ca + _buf[q] * (1 - ca);
                            _buf[q + 1] = cg * ca + _buf[q + 1] * (1 - ca);
                            _buf[q + 2] = cb * ca + _buf[q + 2] * (1 - ca);
                            _buf[q + 3] = ca + _buf[q + 3] * (1 - ca);
                            break;
                    }
                }
            }
        }

        public RgbaImage ToImage()
        {
            var o = new RgbaImage(W, H);
            for (int i = 0; i < W * H * 4; i++) o.Px[i] = (byte)Math.Round(Clamp01(_buf[i]) * 255f);
            for (int i = 0; i < W * H; i++) o.Px[i * 4 + 3] = 255;
            return o;
        }
    }
}
