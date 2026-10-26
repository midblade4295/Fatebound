// Fatebound GUI (Unity port): what a canvas item draws -- Godot's RenderingServer canvas commands, tessellated the way
// RendererCanvasCull does it (polyline miters and AA feathers of FEATHER_SIZE 1.25, 64-segment ellipses, ear-clipped
// polygons), recorded in the item's local space. The viewport walks the items and hands the host the triangles.
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public partial struct GVertex
    {
        public float x, y, u, v;
        public Col c;

        public GVertex(Vec2 p, Col c) { x = p.x; y = p.y; u = 0f; v = 0f; this.c = c; }
        public GVertex(Vec2 p, Vec2 uv, Col c) { x = p.x; y = p.y; u = uv.x; v = uv.y; this.c = c; }
    }

    /// <summary>How a run of triangles is shaded: plain (vertex colour times texture), SDF text (the texture's alpha is
    /// a distance field; aux = outline width in px), or hairlines (Godot's width &lt; 0 lines: one device pixel).</summary>
    public enum DrawMode : byte { Normal = 0, SdfText = 1, Hairline = 2 }

    public partial struct DrawSegment
    {
        public Texture2D tex;
        public DrawMode mode;
        public float aux;
        public int vStart, vCount, iStart, iCount;
        public Xform2 xform;
        public bool hasXform;
    }

    public sealed partial class DrawList
    {
        public const float FEATHER_SIZE = 1.25f;
        const float CMP_EPSILON = 0.00001f;

        public readonly List<GVertex> verts = new List<GVertex>();
        public readonly List<int> idx = new List<int>();
        public readonly List<DrawSegment> segments = new List<DrawSegment>();
        Xform2 _xf = Xform2.IDENTITY;
        bool _hasXf;
        /// <summary>Owner, for redraw bookkeeping (null for free-standing lists).</summary>
        public CanvasItem owner;
        public int version;

        public bool IsEmpty => segments.Count == 0;

        public void Clear()
        {
            verts.Clear();
            idx.Clear();
            segments.Clear();
            _xf = Xform2.IDENTITY;
            _hasXf = false;
            version++;
        }

        /// <summary>draw_set_transform / draw_set_transform_matrix: applies to what is drawn after it.</summary>
        public void SetTransform(Xform2 xf)
        {
            _xf = xf;
            _hasXf = xf != Xform2.IDENTITY;
        }

        public Xform2 CurrentTransform => _xf;

        Vec2 P(Vec2 p) => _hasXf ? _xf.Xform(p) : p;

        int Begin(Texture2D tex, DrawMode mode, float aux)
        {
            int n = segments.Count;
            if (n > 0)
            {
                var s = segments[n - 1];
                if (s.tex == tex && s.mode == mode && s.aux == aux) return verts.Count;
            }
            segments.Add(new DrawSegment { tex = tex, mode = mode, aux = aux, vStart = verts.Count, iStart = idx.Count });
            return verts.Count;
        }

        void End()
        {
            int n = segments.Count - 1;
            var s = segments[n];
            s.vCount = verts.Count - s.vStart;
            s.iCount = idx.Count - s.iStart;
            segments[n] = s;
        }

        void V(Vec2 p, Col c) => verts.Add(new GVertex(P(p), c));
        void V(Vec2 p, Vec2 uv, Col c) => verts.Add(new GVertex(P(p), uv, c));

        // ---------- primitive emitters ----------
        /// <summary>Triangle list from points/colours/uvs; colours may be one entry for all.</summary>
        public void AddTriangles(IList<int> indices, IList<Vec2> points, IList<Col> colors, IList<Vec2> uvs = null, Texture2D tex = null, DrawMode mode = DrawMode.Normal, float aux = 0f)
        {
            if (points.Count == 0 || indices.Count < 3) return;
            int b = Begin(tex, mode, aux);
            Col c0 = colors == null || colors.Count == 0 ? Col.WHITE : colors[0];
            for (int i = 0; i < points.Count; i++)
            {
                Col c = colors != null && colors.Count == points.Count ? colors[i] : c0;
                if (uvs != null && uvs.Count == points.Count) V(points[i], uvs[i], c);
                else V(points[i], c);
            }
            int ni = indices.Count - indices.Count % 3;
            for (int i = 0; i < ni; i++) idx.Add(b + indices[i]);
            End();
        }

        /// <summary>A triangle strip (Godot's PRIMITIVE_TRIANGLE_STRIP polygons).</summary>
        public void AddStrip(IList<Vec2> points, IList<Col> colors, Texture2D tex = null)
        {
            int n = points.Count;
            if (n < 3) return;
            int b = Begin(tex, DrawMode.Normal, 0f);
            Col c0 = colors == null || colors.Count == 0 ? Col.WHITE : colors[0];
            for (int i = 0; i < n; i++) V(points[i], colors != null && colors.Count == n ? colors[i] : c0);
            for (int i = 0; i < n - 2; i++)
            {
                if ((i & 1) == 0) { idx.Add(b + i); idx.Add(b + i + 1); idx.Add(b + i + 2); }
                else { idx.Add(b + i + 1); idx.Add(b + i); idx.Add(b + i + 2); }
            }
            End();
        }

        /// <summary>CommandPrimitive: up to 4 points as a fan (a quad is two triangles).</summary>
        public void AddPrimitive(Vec2[] pts, Col[] cols, Vec2[] uvs = null, Texture2D tex = null)
        {
            int n = pts.Length;
            if (n < 2) return;
            if (n == 2)
            {
                AddHairline(pts[0], pts[1], cols.Length > 0 ? cols[0] : Col.WHITE);
                return;
            }
            int b = Begin(tex, DrawMode.Normal, 0f);
            for (int i = 0; i < n; i++)
            {
                Col c = i < cols.Length ? cols[i] : (cols.Length > 0 ? cols[0] : Col.WHITE);
                if (uvs != null && i < uvs.Length) V(pts[i], uvs[i], c);
                else V(pts[i], c);
            }
            for (int i = 1; i < n - 1; i++) { idx.Add(b); idx.Add(b + i); idx.Add(b + i + 1); }
            End();
        }

        void Quad(Vec2 a, Vec2 b2, Vec2 c, Vec2 d, Col ca, Col cb, Col cc, Col cd)
        {
            int b = Begin(null, DrawMode.Normal, 0f);
            V(a, ca); V(b2, cb); V(c, cc); V(d, cd);
            idx.Add(b); idx.Add(b + 1); idx.Add(b + 2);
            idx.Add(b); idx.Add(b + 2); idx.Add(b + 3);
            End();
        }

        /// <summary>A one-device-pixel line (width &lt; 0): expanded by the viewport, which knows the pixel size.</summary>
        public void AddHairline(Vec2 a, Vec2 b, Col ca, Col? cb = null)
        {
            int s = Begin(null, DrawMode.Hairline, 0f);
            V(a, ca);
            V(b, cb ?? ca);
            idx.Add(s); idx.Add(s + 1); idx.Add(s + 1);
            End();
        }

        // ---------- canvas_item_add_* ----------
        public static float CompensatedAAWidth(float w)
        {
            if (w > 0f)
            {
                if (w <= FEATHER_SIZE * 2f + CMP_EPSILON) return w * 0.5f;
                if (w <= FEATHER_SIZE * 4f + CMP_EPSILON)
                {
                    float a = FEATHER_SIZE * 2f, b = FEATHER_SIZE * 4f;
                    float t = (w - a) / (b - a);
                    return w * 0.5f + (w - FEATHER_SIZE * 0.5f - w * 0.5f) * t;
                }
                return w - FEATHER_SIZE * 0.5f;
            }
            return w;
        }

        public void AddLine(Vec2 from, Vec2 to, Col color, float width, bool aa)
        {
            Vec2 diff = from - to;
            Vec2 dir = diff.Orthogonal().Normalized();
            if (aa) width = CompensatedAAWidth(width);
            Vec2 t = dir * (width * 0.5f);
            Vec2 bl, br, el, er;
            if (width >= 0f)
            {
                bl = from + t; br = from - t; el = to + t; er = to - t;
                Quad(bl, br, er, el, color, color, color, color);
            }
            else
            {
                bl = br = from; el = er = to;
                AddHairline(from, to, color);
            }
            if (!aa) return;
            float border = FEATHER_SIZE;
            if (0f <= width && width < 1f) border *= width;
            Vec2 dir2 = diff.Normalized();
            Vec2 bd = dir * border, bd2 = dir2 * border;
            Col tr = new Col(color, 0.0);
            Quad(bl, bl + bd, el + bd, el, color, tr, tr, color);
            Quad(br, br - bd, er - bd, er, color, tr, tr, color);
            Quad(bl, bl + bd2, br + bd2, br, color, tr, tr, color);
            Quad(el, el - bd2, er - bd2, er, color, tr, tr, color);
            Quad(bl, bl + bd2, bl + bd + bd2, bl + bd, color, tr, tr, tr);
            Quad(br, br + bd2, br - bd + bd2, br - bd, color, tr, tr, tr);
            Quad(el, el - bd2, el + bd - bd2, el + bd, color, tr, tr, tr);
            Quad(er, er - bd2, er - bd - bd2, er - bd, color, tr, tr, tr);
        }

        static bool IsZeroApprox(Vec2 v) => Math.Abs(v.x) < CMP_EPSILON && Math.Abs(v.y) < CMP_EPSILON;
        static bool IsEqualApprox(Vec2 a, Vec2 b) => ApproxF(a.x, b.x) && ApproxF(a.y, b.y);

        static bool ApproxF(float a, float b)
        {
            if (a == b) return true;
            float tol = CMP_EPSILON * Math.Abs(a);
            if (tol < CMP_EPSILON) tol = CMP_EPSILON;
            return Math.Abs(a - b) < tol;
        }

        static Vec2 SegmentDir(IList<Vec2> pts, int i, Vec2 prev)
        {
            if (i == pts.Count - 1) return prev;
            Vec2 d = (pts[i + 1] - pts[i]).Normalized();
            return IsZeroApprox(d) ? prev : d;
        }

        static Vec2 EdgeOffsetClamped(Vec2 seg, Vec2 prev)
        {
            float length = 1f;
            Vec2 bis = (prev * seg.Length() - seg * prev.Length()).Normalized();
            float angle = MathF.Atan2(bis.Cross(prev), bis.Dot(prev));
            float s = MathF.Sin(angle);
            if (!(Math.Abs(s) < CMP_EPSILON) && !IsEqualApprox(seg, prev))
            {
                length = 1f / s;
                length = Math.Max(-3f, Math.Min(3f, length));
            }
            else bis = seg.Orthogonal();
            if (IsZeroApprox(bis)) bis = seg.Orthogonal();
            return bis * length;
        }

        public void AddPolyline(IList<Vec2> pts, IList<Col> colors, float width, bool aa)
        {
            int n = pts.Count;
            if (n < 2) return;
            Col color = Col.WHITE;
            if (aa) width = CompensatedAAWidth(width);
            if (width < 0f)
            {
                for (int i = 0; i < n - 1; i++)
                {
                    Col a = colors == null || colors.Count == 0 ? color : colors[Math.Min(i, colors.Count - 1)];
                    Col b = colors == null || colors.Count == 0 ? color : colors[Math.Min(i + 1, colors.Count - 1)];
                    if (colors != null && colors.Count == 1) a = b = colors[0];
                    AddHairline(pts[i], pts[i + 1], a, b);
                }
                return;
            }
            int ppc = n * 2;
            bool loop = IsEqualApprox(pts[0], pts[n - 1]);
            Vec2 first = Vec2.Zero, last = Vec2.Zero;
            for (int i = 1; i < n; i++)
            {
                first = (pts[i] - pts[i - 1]).Normalized();
                if (!IsZeroApprox(first)) break;
            }
            for (int i = n - 1; i >= 1; i--)
            {
                last = (pts[i] - pts[i - 1]).Normalized();
                if (!IsZeroApprox(last)) break;
            }
            int mainCount = ppc + ((aa && !loop) ? 4 : 0);
            var points = new Vec2[mainCount];
            var cols = new Col[mainCount];
            if (aa)
            {
                float border = FEATHER_SIZE;
                if (width < 1f) border *= width;
                Col color2 = new Col(1f, 1f, 1f, 0f);
                int sideCount = ppc + (loop ? 0 : 5);
                var pl = new Vec2[sideCount];
                var cl = new Col[sideCount];
                var pr = new Vec2[sideCount];
                var cr = new Col[sideCount];
                Vec2 prev = Vec2.Zero;
                for (int i = 0; i < n; i++)
                {
                    bool isFirst = i == 0, isLast = i == n - 1;
                    Vec2 seg = SegmentDir(pts, i, prev);
                    if (isFirst && loop) prev = last;
                    else if (isLast && loop) prev = first;
                    Vec2 baseOff;
                    if (isFirst && !loop) baseOff = first.Orthogonal();
                    else if (isLast && !loop) baseOff = last.Orthogonal();
                    else baseOff = EdgeOffsetClamped(seg, prev);
                    Vec2 eo = baseOff * (width * 0.5f);
                    Vec2 bd = baseOff * border;
                    Vec2 pos = pts[i];
                    int j = i * 2 + (loop ? 0 : 2);
                    points[j] = pos + eo;
                    points[j + 1] = pos - eo;
                    pl[j] = pos + eo;
                    pl[j + 1] = pos + eo + bd;
                    pr[j] = pos - eo;
                    pr[j + 1] = pos - eo - bd;
                    if (colors != null && i < colors.Count)
                    {
                        color = colors[i];
                        color2 = new Col(color.r, color.g, color.b, 0f);
                    }
                    cols[j] = cols[j + 1] = color;
                    cl[j] = color; cl[j + 1] = color2;
                    cr[j] = color; cr[j + 1] = color2;
                    if (isFirst && !loop)
                    {
                        Vec2 bb = -seg * border;
                        points[0] = pos + eo + bb;
                        points[1] = pos - eo + bb;
                        cols[0] = cols[1] = color2;
                        pl[0] = pos + eo + bb;
                        pl[1] = pos + eo + bb + bd;
                        cl[0] = cl[1] = color2;
                        pr[0] = pos - eo + bb;
                        pr[1] = pos - eo + bb - bd;
                        cr[0] = cr[1] = color2;
                    }
                    if (isLast && !loop)
                    {
                        Vec2 eb = prev * border;
                        int e = ppc + 2;
                        points[e] = pos + eo + eb;
                        points[e + 1] = pos - eo + eb;
                        cols[e] = cols[e + 1] = color2;
                        pl[e] = pos + eo;
                        pl[e + 1] = pos + eo + eb + bd;
                        pl[e + 2] = pos + eo + eb;
                        cl[e] = color; cl[e + 1] = color2; cl[e + 2] = color2;
                        pr[e] = pos - eo;
                        pr[e + 1] = pos - eo + eb - bd;
                        pr[e + 2] = pos - eo + eb;
                        cr[e] = color; cr[e + 1] = color2; cr[e + 2] = color2;
                    }
                    prev = seg;
                }
                AddStrip(pl, cl);
                AddStrip(pr, cr);
            }
            else
            {
                Vec2 prev = Vec2.Zero;
                for (int i = 0; i < n; i++)
                {
                    bool isFirst = i == 0, isLast = i == n - 1;
                    Vec2 seg = SegmentDir(pts, i, prev);
                    if (isFirst && loop) prev = last;
                    else if (isLast && loop) prev = first;
                    Vec2 baseOff;
                    if (isFirst && !loop) baseOff = first.Orthogonal();
                    else if (isLast && !loop) baseOff = last.Orthogonal();
                    else baseOff = EdgeOffsetClamped(seg, prev);
                    Vec2 eo = baseOff * (width * 0.5f);
                    Vec2 pos = pts[i];
                    points[i * 2] = pos + eo;
                    points[i * 2 + 1] = pos - eo;
                    if (colors != null && i < colors.Count) color = colors[i];
                    cols[i * 2] = cols[i * 2 + 1] = color;
                    prev = seg;
                }
            }
            AddStrip(points, cols);
        }

        public void AddMultiline(IList<Vec2> pts, IList<Col> colors, float width, bool aa)
        {
            for (int i = 0; i + 1 < pts.Count; i += 2)
            {
                Col c = colors.Count == 1 ? colors[0] : colors[i / 2];
                if (width < 0f) AddHairline(pts[i], pts[i + 1], c);
                else AddLine(pts[i], pts[i + 1], c, width, aa);
            }
        }

        public void AddRect(Rect2 r, Col color, bool aa)
        {
            Rect2 ra = aa ? r.Grow(-FEATHER_SIZE * 0.25f) : r;
            Vec2 p = ra.position, s = ra.size;
            Quad(p, new Vec2(p.x + s.x, p.y), p + s, new Vec2(p.x, p.y + s.y), color, color, color, color);
            if (!aa) return;
            float border = FEATHER_SIZE;
            float size = Math.Min(s.x, s.y);
            if (0f <= size && size < 1f) border *= size;
            Vec2 down = new Vec2(0f, s.y), right = new Vec2(s.x, 0f);
            Vec2 bl = p, br = p + down, el = p + right, er = p + s;
            Vec2 bd = new Vec2(0f, -1f) * border, bd2 = new Vec2(-1f, 0f) * border;
            Col tr = new Col(color, 0.0);
            Quad(bl, bl + bd, el + bd, el, color, tr, tr, color);
            Quad(br, br - bd, er - bd, er, color, tr, tr, color);
            Quad(bl, bl + bd2, br + bd2, br, color, tr, tr, color);
            Quad(el, el - bd2, er - bd2, er, color, tr, tr, color);
            Quad(bl, bl + bd2, bl + bd + bd2, bl + bd, color, tr, tr, tr);
            Quad(br, br + bd2, br - bd + bd2, br - bd, color, tr, tr, tr);
            Quad(el, el - bd2, el + bd - bd2, el + bd, color, tr, tr, tr);
            Quad(er, er - bd2, er - bd - bd2, er - bd, color, tr, tr, tr);
        }

        const int ELLIPSE_SEGMENTS = 64;

        public void AddEllipse(Vec2 pos, float major, float minor, Col color, bool aa)
        {
            if (aa)
            {
                major = Math.Max(0f, major - FEATHER_SIZE * 0.25f);
                minor = Math.Max(0f, minor - FEATHER_SIZE * 0.25f);
            }
            float step = (float)(Math.PI * 2.0) / ELLIPSE_SEGMENTS;
            int b = Begin(null, DrawMode.Normal, 0f);
            for (int i = 0; i < ELLIPSE_SEGMENTS + 1; i++)
            {
                float a = i * step;
                V(new Vec2(MathF.Cos(a) * major + pos.x, MathF.Sin(a) * minor + pos.y), color);
            }
            V(pos, color);
            for (int i = 0; i < ELLIPSE_SEGMENTS; i++) { idx.Add(b + ELLIPSE_SEGMENTS + 1); idx.Add(b + i); idx.Add(b + i + 1); }
            End();
            if (!aa) return;
            float border = FEATHER_SIZE;
            float maxAxis = Math.Max(major, minor) * 2f;
            if (0f <= maxAxis && maxAxis < 1f) border *= maxAxis * 0.5f;
            Col tr = new Col(color, 0.0);
            var pts = new Vec2[2 * ELLIPSE_SEGMENTS + 2];
            var cols = new Col[pts.Length];
            for (int i = 0; i < ELLIPSE_SEGMENTS + 1; i++)
            {
                float a = i * step;
                float c = MathF.Cos(a), s = MathF.Sin(a);
                pts[i * 2] = new Vec2(c * major + pos.x, s * minor + pos.y);
                pts[i * 2 + 1] = new Vec2(c * (major + border) + pos.x, s * (minor + border) + pos.y);
                cols[i * 2] = color;
                cols[i * 2 + 1] = tr;
            }
            AddStrip(pts, cols);
        }

        public void AddPolygon(IList<Vec2> pts, IList<Col> colors, IList<Vec2> uvs = null, Texture2D tex = null)
        {
            if (pts.Count < 3) return;
            var tri = Triangulate(pts);
            if (tri == null) return;
            if (tex != null && uvs != null && uvs.Count == pts.Count)
            {
                var mapped = new Vec2[uvs.Count];
                for (int i = 0; i < uvs.Count; i++) mapped[i] = tex.MapUV(uvs[i]);
                AddTriangles(tri, pts, colors, mapped, tex.BoundTexture());
            }
            else AddTriangles(tri, pts, colors, uvs, tex?.BoundTexture());
        }

        public void AddTextureRect(Rect2 rect, Texture2D tex, bool tile, Col modulate, bool transpose = false)
        {
            if (tex == null) return;
            Vec2 sz = tex.GetSize();
            Rect2 src = new Rect2(Vec2.Zero, tile ? rect.size.Abs() : sz);
            if (!tile)
            {
                AddTextureRectRegion(rect, tex, src, modulate, transpose);
                return;
            }
            // Tiling: uvs past 1; the backend samples the texture with repeat for these (Godot: texture_repeat on).
            Vec2 uv0 = Vec2.Zero, uv1 = new Vec2(rect.size.x / Math.Max(1e-6f, sz.x), rect.size.y / Math.Max(1e-6f, sz.y));
            Quad4(rect, uv0, uv1, tex.BoundTexture(), modulate, transpose, true);
        }

        public void AddTextureRectRegion(Rect2 rect, Texture2D tex, Rect2 src, Col modulate, bool transpose = false, bool clipUV = true)
        {
            if (tex == null) return;
            // AtlasTexture: the region lives inside its atlas; trim the destination where the region was cut.
            if (tex is AtlasTexture at && at.atlas != null)
            {
                Rect2 reg = at.region;
                Rect2 srcIn = new Rect2(src.position + reg.position - at.margin.position, src.size);
                Rect2 clipped = srcIn.Intersection(reg);
                if (clipped.size.x <= 0 || clipped.size.y <= 0) return;
                Vec2 scale = new Vec2(rect.size.x / src.size.x, rect.size.y / src.size.y);
                Rect2 dst = new Rect2(rect.position + (clipped.position - srcIn.position) * scale, clipped.size * scale);
                AddTextureRectRegion(dst, at.atlas, clipped, modulate, transpose, clipUV);
                return;
            }
            Vec2 sz = tex.GetSize();
            if (sz.x <= 0 || sz.y <= 0) return;
            Vec2 uv0 = new Vec2(src.position.x / sz.x, src.position.y / sz.y);
            Vec2 uv1 = new Vec2((src.position.x + src.size.x) / sz.x, (src.position.y + src.size.y) / sz.y);
            Quad4(rect, uv0, uv1, tex.BoundTexture(), modulate, transpose, false);
        }

        void Quad4(Rect2 rect, Vec2 uv0, Vec2 uv1, Texture2D tex, Col modulate, bool transpose, bool tile)
        {
            int b = Begin(tex, DrawMode.Normal, tile ? 1f : 0f);
            Vec2 p0 = rect.position, p2 = rect.position + rect.size;
            Vec2 p1 = new Vec2(p2.x, p0.y), p3 = new Vec2(p0.x, p2.y);
            Vec2 t0 = uv0, t1 = new Vec2(uv1.x, uv0.y), t2 = uv1, t3 = new Vec2(uv0.x, uv1.y);
            if (transpose) { var tmp = t1; t1 = t3; t3 = tmp; }
            V(p0, t0, modulate); V(p1, t1, modulate); V(p2, t2, modulate); V(p3, t3, modulate);
            idx.Add(b); idx.Add(b + 1); idx.Add(b + 2);
            idx.Add(b); idx.Add(b + 2); idx.Add(b + 3);
            End();
        }

        public enum NinePatchAxis { Stretch = 0, Tile = 1, TileFit = 2 }

        /// <summary>canvas_item_add_nine_patch: margins in source pixels; draw_center fills the middle.</summary>
        public void AddNinePatch(Rect2 rect, Rect2 source, Texture2D tex, Vec2 topLeft, Vec2 bottomRight, NinePatchAxis ax, NinePatchAxis ay, bool drawCenter, Col modulate)
        {
            if (tex == null) return;
            if (source.size.x == 0 && source.size.y == 0) source = new Rect2(Vec2.Zero, tex.GetSize());
            float[] dx = { rect.position.x, rect.position.x + topLeft.x, rect.position.x + rect.size.x - bottomRight.x, rect.position.x + rect.size.x };
            float[] dy = { rect.position.y, rect.position.y + topLeft.y, rect.position.y + rect.size.y - bottomRight.y, rect.position.y + rect.size.y };
            float[] sx = { source.position.x, source.position.x + topLeft.x, source.position.x + source.size.x - bottomRight.x, source.position.x + source.size.x };
            float[] sy = { source.position.y, source.position.y + topLeft.y, source.position.y + source.size.y - bottomRight.y, source.position.y + source.size.y };
            // Margins larger than the rect collapse proportionally (as RendererCanvasRender's nine-patch).
            if (dx[1] > dx[2]) { float m = (dx[1] + dx[2]) * 0.5f; dx[1] = dx[2] = m; }
            if (dy[1] > dy[2]) { float m = (dy[1] + dy[2]) * 0.5f; dy[1] = dy[2] = m; }
            for (int j = 0; j < 3; j++)
                for (int i = 0; i < 3; i++)
                {
                    if (i == 1 && j == 1 && !drawCenter) continue;
                    var d = new Rect2(dx[i], dy[j], dx[i + 1] - dx[i], dy[j + 1] - dy[j]);
                    if (d.size.x <= 0 || d.size.y <= 0) continue;
                    var s = new Rect2(sx[i], sy[j], sx[i + 1] - sx[i], sy[j + 1] - sy[j]);
                    if (s.size.x <= 0 || s.size.y <= 0) continue;
                    bool tileX = i == 1 && ax != NinePatchAxis.Stretch, tileY = j == 1 && ay != NinePatchAxis.Stretch;
                    if (!tileX && !tileY) { AddTextureRectRegion(d, tex, s, modulate); continue; }
                    float stepX = tileX ? (ax == NinePatchAxis.TileFit ? d.size.x / Math.Max(1f, MathF.Round(d.size.x / s.size.x)) : s.size.x) : d.size.x;
                    float stepY = tileY ? (ay == NinePatchAxis.TileFit ? d.size.y / Math.Max(1f, MathF.Round(d.size.y / s.size.y)) : s.size.y) : d.size.y;
                    for (float yy = 0; yy < d.size.y - 0.01f; yy += stepY)
                        for (float xx = 0; xx < d.size.x - 0.01f; xx += stepX)
                        {
                            float w = Math.Min(stepX, d.size.x - xx), h = Math.Min(stepY, d.size.y - yy);
                            var sub = new Rect2(s.position, new Vec2(tileX && ax == NinePatchAxis.Tile ? w : s.size.x * (w / stepX), tileY && ay == NinePatchAxis.Tile ? h : s.size.y * (h / stepY)));
                            AddTextureRectRegion(new Rect2(d.position.x + xx, d.position.y + yy, w, h), tex, sub, modulate);
                        }
                }
        }

        /// <summary>One glyph quad from an SDF atlas page.</summary>
        public void AddGlyph(Rect2 dst, Texture2D atlas, Vec2 uv0, Vec2 uv1, Col color, float outline)
        {
            int b = Begin(atlas, DrawMode.SdfText, outline);
            Vec2 p0 = dst.position, p2 = dst.position + dst.size;
            V(p0, uv0, color);
            V(new Vec2(p2.x, p0.y), new Vec2(uv1.x, uv0.y), color);
            V(p2, uv1, color);
            V(new Vec2(p0.x, p2.y), new Vec2(uv0.x, uv1.y), color);
            idx.Add(b); idx.Add(b + 1); idx.Add(b + 2);
            idx.Add(b); idx.Add(b + 2); idx.Add(b + 3);
            End();
        }

        /// <summary>Appends another list (a StyleBox drawn into a scratch list, a cached text run).</summary>
        public void Append(DrawList o, Vec2 offset, Col modulate)
        {
            foreach (var s in o.segments)
            {
                int b = Begin(s.tex, s.mode, s.aux);
                for (int i = 0; i < s.vCount; i++)
                {
                    var v = o.verts[s.vStart + i];
                    var p = P(new Vec2(v.x + offset.x, v.y + offset.y));
                    verts.Add(new GVertex { x = p.x, y = p.y, u = v.u, v = v.v, c = v.c * modulate });
                }
                for (int i = 0; i < s.iCount; i++) idx.Add(b + o.idx[s.iStart + i] - s.vStart);
                End();
            }
        }

        // ---------- Geometry2D::triangulate_polygon (Triangulate::triangulate, ear clipping) ----------
        static float Area(IList<Vec2> c)
        {
            int n = c.Count;
            float A = 0f;
            for (int p = n - 1, q = 0; q < n; p = q++) A += c[p].Cross(c[q]);
            return A * 0.5f;
        }

        static bool InsideTri(float Ax, float Ay, float Bx, float By, float Cx, float Cy, float Px, float Py, bool includeEdges)
        {
            float ax = Cx - Bx, ay = Cy - By, bx = Ax - Cx, by = Ay - Cy, cx = Bx - Ax, cy = By - Ay;
            float apx = Px - Ax, apy = Py - Ay, bpx = Px - Bx, bpy = Py - By, cpx = Px - Cx, cpy = Py - Cy;
            float aCb = ax * bpy - ay * bpx, cCa = cx * apy - cy * apx, bCc = bx * cpy - by * cpx;
            if (includeEdges) return aCb > 0f && bCc > 0f && cCa > 0f;
            return aCb >= 0f && bCc >= 0f && cCa >= 0f;
        }

        static bool Snip(IList<Vec2> c, int u, int v, int w, int n, int[] V, bool relaxed)
        {
            float Ax = c[V[u]].x, Ay = c[V[u]].y, Bx = c[V[v]].x, By = c[V[v]].y, Cx = c[V[w]].x, Cy = c[V[w]].y;
            float threshold = relaxed ? -CMP_EPSILON : CMP_EPSILON;
            if (threshold > ((Bx - Ax) * (Cy - Ay)) - ((By - Ay) * (Cx - Ax))) return false;
            for (int p = 0; p < n; p++)
            {
                if (p == u || p == v || p == w) continue;
                if (InsideTri(Ax, Ay, Bx, By, Cx, Cy, c[V[p]].x, c[V[p]].y, relaxed)) return false;
            }
            return true;
        }

        public static List<int> Triangulate(IList<Vec2> contour)
        {
            int n = contour.Count;
            if (n < 3) return null;
            var result = new List<int>((n - 2) * 3);
            var V = new int[n];
            if (0f < Area(contour)) for (int v = 0; v < n; v++) V[v] = v;
            else for (int v = 0; v < n; v++) V[v] = (n - 1) - v;
            bool relaxed = false;
            int nv = n;
            int count = 2 * nv;
            for (int v = nv - 1; nv > 2;)
            {
                if (0 >= (count--))
                {
                    if (relaxed) return null;
                    count = 2 * nv;
                    relaxed = true;
                }
                int u = v;
                if (nv <= u) u = 0;
                v = u + 1;
                if (nv <= v) v = 0;
                int w = v + 1;
                if (nv <= w) w = 0;
                if (Snip(contour, u, v, w, nv, V, relaxed))
                {
                    result.Add(V[u]); result.Add(V[v]); result.Add(V[w]);
                    for (int s = v, t = v + 1; t < nv; s++, t++) V[s] = V[t];
                    nv--;
                    count = 2 * nv;
                }
            }
            return result;
        }
    }
}
