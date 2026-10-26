// Fatebound GUI (Unity port): a small TrueType reader -- metrics (head/hhea/OS2/hmtx), the character map, glyph
// outlines (glyf/loca, composite glyphs), pair kerning (GPOS 'kern' lookups and the legacy kern table) -- and a signed
// distance field rasteriser for the glyph atlas. Pure C#, the same code in the tests and in the game. (The .woff2 fonts
// are converted to .ttf when the assets are synced.)
using System;
using System.Collections.Generic;

namespace Fatebound.GUI
{
    public sealed class TrueTypeFace
    {
        readonly byte[] d;
        readonly Dictionary<string, (int off, int len)> _tables = new Dictionary<string, (int, int)>();
        public readonly int UnitsPerEm;
        public readonly int Ascender, Descender, LineGap;
        public readonly int NumGlyphs;
        readonly int _numHMetrics, _hmtx, _loca, _glyf, _locaFormat;
        readonly int _cmap;
        int _cmapFormat;
        readonly Dictionary<int, int> _cmapCache = new Dictionary<int, int>();
        readonly Dictionary<long, short> _kernCache = new Dictionary<long, short>();
        readonly List<int> _gposPairTables = new List<int>();
        readonly Dictionary<int, short> _legacyKern;
        public readonly string Name;

        public TrueTypeFace(byte[] data, string name = "")
        {
            d = data;
            Name = name;
            uint tag = U32(0);
            if (tag == 0x4F54544F) throw new NotSupportedException("CFF (OTTO) fonts are not supported: " + name);
            int n = U16(4);
            for (int i = 0; i < n; i++)
            {
                int r = 12 + i * 16;
                string t = "" + (char)d[r] + (char)d[r + 1] + (char)d[r + 2] + (char)d[r + 3];
                _tables[t] = ((int)U32(r + 8), (int)U32(r + 12));
            }
            int head = T("head");
            UnitsPerEm = U16(head + 18);
            _locaFormat = S16(head + 50);
            int hhea = T("hhea");
            Ascender = S16(hhea + 4);
            Descender = S16(hhea + 6);
            LineGap = S16(hhea + 8);
            _numHMetrics = U16(hhea + 34);
            if (Ascender == 0 && Descender == 0 && _tables.ContainsKey("OS/2"))
            {
                int os2 = T("OS/2");
                Ascender = S16(os2 + 68);
                Descender = S16(os2 + 70);
                LineGap = S16(os2 + 72);
                if (Ascender == 0 && Descender == 0)
                {
                    Ascender = U16(os2 + 74);
                    Descender = -U16(os2 + 76);
                }
            }
            NumGlyphs = U16(T("maxp") + 4);
            _hmtx = T("hmtx");
            _loca = _tables.ContainsKey("loca") ? T("loca") : -1;
            _glyf = _tables.ContainsKey("glyf") ? T("glyf") : -1;
            _cmap = PickCmap();
            if (_tables.ContainsKey("GPOS")) ReadGpos();
            if (_tables.ContainsKey("kern")) _legacyKern = ReadKern();
        }

        int T(string t) => _tables.TryGetValue(t, out var v) ? v.off : throw new FormatException("font table " + t + " missing: " + Name);
        int U8(int o) => d[o];
        int U16(int o) => (d[o] << 8) | d[o + 1];
        short S16(int o) => (short)((d[o] << 8) | d[o + 1]);
        uint U32(int o) => ((uint)d[o] << 24) | ((uint)d[o + 1] << 16) | ((uint)d[o + 2] << 8) | d[o + 3];

        // ---------- cmap ----------
        int PickCmap()
        {
            int cm = T("cmap");
            int n = U16(cm + 2);
            int best = -1, bestScore = -1;
            for (int i = 0; i < n; i++)
            {
                int pid = U16(cm + 4 + i * 8), eid = U16(cm + 6 + i * 8);
                int off = cm + (int)U32(cm + 8 + i * 8);
                int fmt = U16(off);
                int score = -1;
                if (fmt == 12 && (pid == 3 && eid == 10 || pid == 0)) score = 3;
                else if (fmt == 4 && pid == 3 && (eid == 1 || eid == 0)) score = 2;
                else if (fmt == 4 && pid == 0) score = 2;
                else if (fmt == 6 || fmt == 0) score = 0;
                if (score > bestScore) { bestScore = score; best = off; }
            }
            if (best >= 0) _cmapFormat = U16(best);
            return best;
        }

        public int GlyphIndex(int cp)
        {
            if (_cmapCache.TryGetValue(cp, out int g)) return g;
            g = LookupCmap(cp);
            _cmapCache[cp] = g;
            return g;
        }

        int LookupCmap(int cp)
        {
            int o = _cmap;
            if (o < 0) return 0;
            switch (_cmapFormat)
            {
                case 0: return cp < 256 ? d[o + 6 + cp] : 0;
                case 4:
                {
                    if (cp > 0xFFFF) return 0;
                    int segX2 = U16(o + 6);
                    int ends = o + 14, starts = ends + segX2 + 2, deltas = starts + segX2, ranges = deltas + segX2;
                    int lo = 0, hi = segX2 / 2 - 1;
                    while (lo <= hi)
                    {
                        int mid = (lo + hi) >> 1;
                        int end = U16(ends + mid * 2);
                        if (end < cp) { lo = mid + 1; continue; }
                        int start = U16(starts + mid * 2);
                        if (start > cp) { hi = mid - 1; continue; }
                        int delta = S16(deltas + mid * 2);
                        int ro = U16(ranges + mid * 2);
                        if (ro == 0) return (cp + delta) & 0xFFFF;
                        int gi = U16(ranges + mid * 2 + ro + (cp - start) * 2);
                        return gi == 0 ? 0 : (gi + delta) & 0xFFFF;
                    }
                    return 0;
                }
                case 6:
                {
                    int first = U16(o + 6), count = U16(o + 8);
                    return cp >= first && cp < first + count ? U16(o + 10 + (cp - first) * 2) : 0;
                }
                case 12:
                {
                    int ng = (int)U32(o + 12);
                    int lo = 0, hi = ng - 1;
                    while (lo <= hi)
                    {
                        int mid = (lo + hi) >> 1;
                        int g = o + 16 + mid * 12;
                        uint s = U32(g), e = U32(g + 4);
                        if (cp < s) hi = mid - 1;
                        else if (cp > e) lo = mid + 1;
                        else return (int)(U32(g + 8) + (cp - s));
                    }
                    return 0;
                }
            }
            return 0;
        }

        public bool HasChar(int cp) => GlyphIndex(cp) != 0;

        // ---------- metrics ----------
        public int AdvanceWidth(int glyph)
        {
            if (glyph < _numHMetrics) return U16(_hmtx + glyph * 4);
            return U16(_hmtx + (_numHMetrics - 1) * 4);
        }

        public int LeftSideBearing(int glyph)
        {
            if (glyph < _numHMetrics) return S16(_hmtx + glyph * 4 + 2);
            return S16(_hmtx + _numHMetrics * 4 + (glyph - _numHMetrics) * 2);
        }

        /// <summary>Pair kerning in font units (GPOS pair adjustment of the 'kern' feature, else the kern table).</summary>
        public int Kerning(int g1, int g2)
        {
            long key = ((long)g1 << 32) | (uint)g2;
            if (_kernCache.TryGetValue(key, out short k)) return k;
            int v = 0;
            if (_gposPairTables.Count > 0)
            {
                foreach (int st in _gposPairTables)
                {
                    if (PairAdjust(st, g1, g2, out int adj)) { v = adj; break; }
                }
            }
            else if (_legacyKern != null && _legacyKern.TryGetValue((g1 << 16) | g2, out short lk)) v = lk;
            _kernCache[key] = (short)v;
            return v;
        }

        Dictionary<int, short> ReadKern()
        {
            var o = new Dictionary<int, short>();
            int kt = T("kern");
            int ver = U16(kt);
            if (ver != 0) return o;
            int n = U16(kt + 2);
            int p = kt + 4;
            for (int t = 0; t < n; t++)
            {
                int len = U16(p + 2), cov = U16(p + 4);
                if ((cov >> 8) == 0 && (cov & 1) == 1)
                {
                    int np = U16(p + 6);
                    for (int i = 0; i < np; i++)
                    {
                        int r = p + 14 + i * 6;
                        int key = (U16(r) << 16) | U16(r + 2);
                        if (!o.ContainsKey(key)) o[key] = S16(r + 4);
                    }
                }
                p += len;
            }
            return o;
        }

        void ReadGpos()
        {
            int g = T("GPOS");
            int featureList = g + U16(g + 6), lookupList = g + U16(g + 8);
            var lookups = new SortedSet<int>();
            int fc = U16(featureList);
            for (int i = 0; i < fc; i++)
            {
                int r = featureList + 2 + i * 6;
                string tag = "" + (char)d[r] + (char)d[r + 1] + (char)d[r + 2] + (char)d[r + 3];
                if (tag != "kern") continue;
                int f = featureList + U16(r + 4);
                int lc = U16(f + 2);
                for (int j = 0; j < lc; j++) lookups.Add(U16(f + 4 + j * 2));
            }
            int nl = U16(lookupList);
            foreach (int li in lookups)
            {
                if (li >= nl) continue;
                int l = lookupList + U16(lookupList + 2 + li * 2);
                int type = U16(l), subs = U16(l + 4);
                for (int s = 0; s < subs; s++)
                {
                    int st = l + U16(l + 6 + s * 2);
                    int t = type;
                    if (t == 9)
                    {
                        t = U16(st + 2);
                        st = st + (int)U32(st + 4);
                    }
                    if (t == 2) _gposPairTables.Add(st);
                }
            }
        }

        int CoverageIndex(int cov, int glyph)
        {
            int fmt = U16(cov);
            if (fmt == 1)
            {
                int n = U16(cov + 2);
                int lo = 0, hi = n - 1;
                while (lo <= hi)
                {
                    int mid = (lo + hi) >> 1;
                    int gv = U16(cov + 4 + mid * 2);
                    if (gv < glyph) lo = mid + 1;
                    else if (gv > glyph) hi = mid - 1;
                    else return mid;
                }
                return -1;
            }
            if (fmt == 2)
            {
                int n = U16(cov + 2);
                int lo = 0, hi = n - 1;
                while (lo <= hi)
                {
                    int mid = (lo + hi) >> 1;
                    int r = cov + 4 + mid * 6;
                    int s = U16(r), e = U16(r + 2);
                    if (glyph < s) hi = mid - 1;
                    else if (glyph > e) lo = mid + 1;
                    else return U16(r + 4) + glyph - s;
                }
            }
            return -1;
        }

        int ClassOf(int cd, int glyph)
        {
            int fmt = U16(cd);
            if (fmt == 1)
            {
                int start = U16(cd + 2), n = U16(cd + 4);
                return glyph >= start && glyph < start + n ? U16(cd + 6 + (glyph - start) * 2) : 0;
            }
            if (fmt == 2)
            {
                int n = U16(cd + 2);
                int lo = 0, hi = n - 1;
                while (lo <= hi)
                {
                    int mid = (lo + hi) >> 1;
                    int r = cd + 4 + mid * 6;
                    int s = U16(r), e = U16(r + 2);
                    if (glyph < s) hi = mid - 1;
                    else if (glyph > e) lo = mid + 1;
                    else return U16(r + 4);
                }
            }
            return 0;
        }

        static int ValueSize(int fmt)
        {
            int n = 0;
            for (int b = 0; b < 8; b++) if ((fmt & (1 << b)) != 0) n += 2;
            return n;
        }

        int XAdvanceOf(int rec, int fmt)
        {
            int o = rec;
            if ((fmt & 1) != 0) o += 2;
            if ((fmt & 2) != 0) o += 2;
            return (fmt & 4) != 0 ? S16(o) : 0;
        }

        bool PairAdjust(int st, int g1, int g2, out int adj)
        {
            adj = 0;
            int fmt = U16(st);
            int ci = CoverageIndex(st + U16(st + 2), g1);
            if (ci < 0) return false;
            int vf1 = U16(st + 4), vf2 = U16(st + 6);
            int s1 = ValueSize(vf1), s2 = ValueSize(vf2);
            if (fmt == 1)
            {
                int n = U16(st + 8);
                if (ci >= n) return false;
                int ps = st + U16(st + 10 + ci * 2);
                int pc = U16(ps);
                int rs = 2 + s1 + s2;
                int lo = 0, hi = pc - 1;
                while (lo <= hi)
                {
                    int mid = (lo + hi) >> 1;
                    int r = ps + 2 + mid * rs;
                    int sg = U16(r);
                    if (sg < g2) lo = mid + 1;
                    else if (sg > g2) hi = mid - 1;
                    else { adj = XAdvanceOf(r + 2, vf1); return true; }
                }
                return false;
            }
            if (fmt == 2)
            {
                int cd1 = st + U16(st + 8), cd2 = st + U16(st + 10);
                int c1n = U16(st + 12), c2n = U16(st + 14);
                int c1 = ClassOf(cd1, g1), c2 = ClassOf(cd2, g2);
                if (c1 >= c1n || c2 >= c2n) return false;
                int r = st + 16 + (c1 * c2n + c2) * (s1 + s2);
                adj = XAdvanceOf(r, vf1);
                return true;
            }
            return false;
        }

        // ---------- outlines ----------
        public struct Pt { public float x, y; public bool on; }

        /// <summary>The glyph's contours in font units (y up), composite glyphs flattened.</summary>
        public List<List<Pt>> Outline(int glyph)
        {
            var o = new List<List<Pt>>();
            AppendOutline(glyph, o, 1, 0, 0, 1, 0, 0, 0);
            return o;
        }

        int GlyphOffset(int glyph, out int len)
        {
            len = 0;
            if (_glyf < 0 || glyph >= NumGlyphs) return -1;
            int a, b;
            if (_locaFormat == 0) { a = U16(_loca + glyph * 2) * 2; b = U16(_loca + glyph * 2 + 2) * 2; }
            else { a = (int)U32(_loca + glyph * 4); b = (int)U32(_loca + glyph * 4 + 4); }
            len = b - a;
            return len <= 0 ? -1 : _glyf + a;
        }

        public bool Bounds(int glyph, out int x0, out int y0, out int x1, out int y1)
        {
            x0 = y0 = x1 = y1 = 0;
            int g = GlyphOffset(glyph, out _);
            if (g < 0) return false;
            x0 = S16(g + 2); y0 = S16(g + 4); x1 = S16(g + 6); y1 = S16(g + 8);
            return true;
        }

        void AppendOutline(int glyph, List<List<Pt>> outC, float a, float b, float c, float dd, float e, float f, int depth)
        {
            if (depth > 8) return;
            int g = GlyphOffset(glyph, out _);
            if (g < 0) return;
            int nc = S16(g);
            if (nc >= 0)
            {
                int endPts = g + 10;
                int np = nc == 0 ? 0 : U16(endPts + (nc - 1) * 2) + 1;
                int ilen = U16(endPts + nc * 2);
                int p = endPts + nc * 2 + 2 + ilen;
                var flags = new byte[np];
                for (int i = 0; i < np;)
                {
                    byte fl = d[p++];
                    flags[i++] = fl;
                    if ((fl & 8) != 0)
                    {
                        int rep = d[p++];
                        while (rep-- > 0 && i < np) flags[i++] = fl;
                    }
                }
                var xs = new int[np];
                var ys = new int[np];
                int v = 0;
                for (int i = 0; i < np; i++)
                {
                    byte fl = flags[i];
                    if ((fl & 2) != 0) { int dx = d[p++]; v += (fl & 16) != 0 ? dx : -dx; }
                    else if ((fl & 16) == 0) { v += S16(p); p += 2; }
                    xs[i] = v;
                }
                v = 0;
                for (int i = 0; i < np; i++)
                {
                    byte fl = flags[i];
                    if ((fl & 4) != 0) { int dy = d[p++]; v += (fl & 32) != 0 ? dy : -dy; }
                    else if ((fl & 32) == 0) { v += S16(p); p += 2; }
                    ys[i] = v;
                }
                int s = 0;
                for (int ci = 0; ci < nc; ci++)
                {
                    int end = U16(endPts + ci * 2);
                    var cont = new List<Pt>(end - s + 1);
                    for (int i = s; i <= end; i++)
                        cont.Add(new Pt { x = a * xs[i] + c * ys[i] + e, y = b * xs[i] + dd * ys[i] + f, on = (flags[i] & 1) != 0 });
                    if (cont.Count > 1) outC.Add(cont);
                    s = end + 1;
                }
                return;
            }
            // Composite.
            int q = g + 10;
            while (true)
            {
                int fl = U16(q), gi = U16(q + 2);
                q += 4;
                float dx, dy;
                if ((fl & 1) != 0) { dx = S16(q); dy = S16(q + 2); q += 4; }
                else { dx = (sbyte)d[q]; dy = (sbyte)d[q + 1]; q += 2; }
                float ma = 1, mb = 0, mc = 0, md = 1;
                if ((fl & 8) != 0) { ma = md = F2Dot14(q); q += 2; }
                else if ((fl & 0x40) != 0) { ma = F2Dot14(q); md = F2Dot14(q + 2); q += 4; }
                else if ((fl & 0x80) != 0) { ma = F2Dot14(q); mb = F2Dot14(q + 2); mc = F2Dot14(q + 4); md = F2Dot14(q + 6); q += 8; }
                if ((fl & 2) == 0) { dx = 0; dy = 0; }
                // child transform then parent transform
                float na = a * ma + c * mb, nb = b * ma + dd * mb, nc2 = a * mc + c * md, nd = b * mc + dd * md;
                float ne = a * dx + c * dy + e, nf = b * dx + dd * dy + f;
                AppendOutline(gi, outC, na, nb, nc2, nd, ne, nf, depth + 1);
                if ((fl & 0x20) == 0) break;
            }
        }

        float F2Dot14(int o) => S16(o) / 16384f;
    }

    /// <summary>Signed distance fields from TrueType outlines (quadratic splines flattened to segments).</summary>
    public static class SdfRaster
    {
        /// <summary>Renders glyph `contours` (font units, y up) scaled by `scale` px/unit into a w×h byte field whose
        /// origin pixel (0,0) is at font coordinates (ox, oy) (top-left, y down in the bitmap). 128 = the edge,
        /// +127 = `spread` px inside.</summary>
        public static byte[] Render(List<List<TrueTypeFace.Pt>> contours, float scale, float ox, float oy, int w, int h, float spread)
        {
            var segs = new List<float>(256);
            foreach (var c in contours) Flatten(c, scale, ox, oy, segs);
            var o = new byte[w * h];
            int ns = segs.Count / 4;
            if (ns == 0) return o;
            // Per row: winding by crossings; per pixel: distance to the nearest segment.
            var winding = new int[w];
            for (int y = 0; y < h; y++)
            {
                float py = y + 0.5f;
                Array.Clear(winding, 0, w);
                // crossings for nonzero winding
                var xs = new List<(float x, int dir)>();
                for (int i = 0; i < ns; i++)
                {
                    float x0 = segs[i * 4], y0 = segs[i * 4 + 1], x1 = segs[i * 4 + 2], y1 = segs[i * 4 + 3];
                    if (y0 == y1) continue;
                    bool up = y1 > y0;
                    float ya = up ? y0 : y1, yb = up ? y1 : y0;
                    if (py < ya || py >= yb) continue;
                    float t = (py - y0) / (y1 - y0);
                    xs.Add((x0 + (x1 - x0) * t, up ? 1 : -1));
                }
                xs.Sort((p1, p2) => p1.x.CompareTo(p2.x));
                for (int x = 0; x < w; x++)
                {
                    float px = x + 0.5f;
                    int wnd = 0;
                    foreach (var cr in xs)
                    {
                        if (cr.x > px) break;
                        wnd += cr.dir;
                    }
                    float best = (spread + 1f) * (spread + 1f);
                    for (int i = 0; i < ns; i++)
                    {
                        float x0 = segs[i * 4], y0 = segs[i * 4 + 1], x1 = segs[i * 4 + 2], y1 = segs[i * 4 + 3];
                        float bx = px < Math.Min(x0, x1) ? Math.Min(x0, x1) - px : (px > Math.Max(x0, x1) ? px - Math.Max(x0, x1) : 0f);
                        float by = py < Math.Min(y0, y1) ? Math.Min(y0, y1) - py : (py > Math.Max(y0, y1) ? py - Math.Max(y0, y1) : 0f);
                        if (bx * bx + by * by >= best) continue;
                        float dx = x1 - x0, dy = y1 - y0;
                        float l2 = dx * dx + dy * dy;
                        float t = l2 > 0 ? ((px - x0) * dx + (py - y0) * dy) / l2 : 0f;
                        if (t < 0) t = 0; else if (t > 1) t = 1;
                        float ex = x0 + dx * t - px, ey = y0 + dy * t - py;
                        float dd = ex * ex + ey * ey;
                        if (dd < best) best = dd;
                    }
                    float dist = MathF.Sqrt(best);
                    if (wnd == 0) dist = -dist;
                    float v = 0.5f + dist / (2f * spread);
                    o[y * w + x] = (byte)Math.Max(0, Math.Min(255, (int)MathF.Round(v * 255f)));
                }
            }
            return o;
        }

        static void Flatten(List<TrueTypeFace.Pt> c, float scale, float ox, float oy, List<float> segs)
        {
            int n = c.Count;
            if (n < 2) return;
            // Map to bitmap space: x' = x*scale - ox, y' = oy - y*scale.
            (float, float) M(float x, float y) => (x * scale - ox, oy - y * scale);
            // Find an on-curve start (or the midpoint of two off-curve points).
            int start = -1;
            for (int i = 0; i < n; i++) if (c[i].on) { start = i; break; }
            float sx, sy;
            if (start < 0)
            {
                sx = (c[0].x + c[1].x) * 0.5f;
                sy = (c[0].y + c[1].y) * 0.5f;
                start = 0;
            }
            else { sx = c[start].x; sy = c[start].y; }
            var (cx, cy) = M(sx, sy);
            float firstX = cx, firstY = cy;
            float ctrlX = 0, ctrlY = 0;
            bool haveCtrl = false;
            for (int k = 1; k <= n; k++)
            {
                var p = c[(start + k) % n];
                var (px, py) = M(p.x, p.y);
                if (k == n && !haveCtrl && p.on) { Seg(segs, cx, cy, firstX, firstY); cx = firstX; cy = firstY; break; }
                if (p.on)
                {
                    if (haveCtrl) { Quad(segs, cx, cy, ctrlX, ctrlY, px, py); haveCtrl = false; }
                    else Seg(segs, cx, cy, px, py);
                    cx = px; cy = py;
                }
                else
                {
                    if (haveCtrl)
                    {
                        float mx = (ctrlX + px) * 0.5f, my = (ctrlY + py) * 0.5f;
                        Quad(segs, cx, cy, ctrlX, ctrlY, mx, my);
                        cx = mx; cy = my;
                    }
                    ctrlX = px; ctrlY = py;
                    haveCtrl = true;
                }
            }
            if (haveCtrl) Quad(segs, cx, cy, ctrlX, ctrlY, firstX, firstY);
            else if (cx != firstX || cy != firstY) Seg(segs, cx, cy, firstX, firstY);
        }

        static void Seg(List<float> s, float x0, float y0, float x1, float y1)
        {
            if (x0 == x1 && y0 == y1) return;
            s.Add(x0); s.Add(y0); s.Add(x1); s.Add(y1);
        }

        static void Quad(List<float> s, float x0, float y0, float cx, float cy, float x1, float y1)
        {
            float dd = Math.Abs(x0 - 2 * cx + x1) + Math.Abs(y0 - 2 * cy + y1);
            int n = Math.Max(1, Math.Min(24, (int)MathF.Ceiling(MathF.Sqrt(dd * 2f))));
            float px = x0, py = y0;
            for (int i = 1; i <= n; i++)
            {
                float t = i / (float)n, mt = 1 - t;
                float x = mt * mt * x0 + 2 * mt * t * cx + t * t * x1;
                float y = mt * mt * y0 + 2 * mt * t * cy + t * t * y1;
                Seg(s, px, py, x, y);
                px = x; py = y;
            }
        }
    }
}
