// Fatebound GUI (Unity port): fonts and text as Godot's TextServerAdvanced lays them out -- per-size metrics with
// FreeType's rounding, advances (1/64 px up to size 20, whole pixels with carried remainders above), GPOS kerning,
// fallback to DejaVu Sans for missing characters, Godot's line breaking (shaped_text_get_line_breaks) and ellipsis
// trimming, and glyphs drawn from a shared signed-distance-field atlas (outlines are a threshold shift).
using System;
using System.Collections.Generic;
using System.Text;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    [Flags]
    public enum GlyphFlags
    {
        None = 0,
        Space = 1,
        BreakSoft = 2,
        BreakHard = 4,
        Virtual = 8,
        Tab = 16,
        Punct = 32,
        SoftHyphen = 64,
    }

    [Flags]
    public enum LineBreakFlags
    {
        None = 0,
        Mandatory = 1,
        WordBound = 2,
        GraphemeBound = 4,
        Adaptive = 8,
        TrimStartEdgeSpaces = 16,
        TrimEndEdgeSpaces = 32,
        TrimIndent = 64,
    }

    public enum AutowrapMode { Off = 0, Arbitrary = 1, Word = 2, WordSmart = 3 }
    public enum OverrunBehavior { NoTrimming = 0, TrimChar = 1, TrimWord = 2, TrimEllipsis = 3, TrimWordEllipsis = 4, TrimEllipsisForce = 5, TrimWordEllipsisForce = 6 }

    [Flags]
    public enum OverrunFlags { NoTrim = 0, Trim = 1, TrimWordOnly = 2, AddEllipsis = 4, EnforceEllipsis = 8, JustificationAware = 16 }

    /// <summary>The TextServer namespace constants the UI code refers to (TextServer.AUTOWRAP_WORD_SMART ...).</summary>
    public static class TextServer
    {
        public const AutowrapMode AUTOWRAP_OFF = AutowrapMode.Off;
        public const AutowrapMode AUTOWRAP_ARBITRARY = AutowrapMode.Arbitrary;
        public const AutowrapMode AUTOWRAP_WORD = AutowrapMode.Word;
        public const AutowrapMode AUTOWRAP_WORD_SMART = AutowrapMode.WordSmart;
        public const OverrunBehavior OVERRUN_NO_TRIMMING = OverrunBehavior.NoTrimming;
        public const OverrunBehavior OVERRUN_TRIM_CHAR = OverrunBehavior.TrimChar;
        public const OverrunBehavior OVERRUN_TRIM_WORD = OverrunBehavior.TrimWord;
        public const OverrunBehavior OVERRUN_TRIM_ELLIPSIS = OverrunBehavior.TrimEllipsis;
        public const OverrunBehavior OVERRUN_TRIM_WORD_ELLIPSIS = OverrunBehavior.TrimWordEllipsis;

        public static OverrunFlags FlagsFromBehavior(OverrunBehavior b)
        {
            switch (b)
            {
                case OverrunBehavior.TrimChar: return OverrunFlags.Trim;
                case OverrunBehavior.TrimWord: return OverrunFlags.Trim | OverrunFlags.TrimWordOnly;
                case OverrunBehavior.TrimEllipsis: return OverrunFlags.Trim | OverrunFlags.AddEllipsis;
                case OverrunBehavior.TrimWordEllipsis: return OverrunFlags.Trim | OverrunFlags.TrimWordOnly | OverrunFlags.AddEllipsis;
                case OverrunBehavior.TrimEllipsisForce: return OverrunFlags.Trim | OverrunFlags.AddEllipsis | OverrunFlags.EnforceEllipsis;
                case OverrunBehavior.TrimWordEllipsisForce: return OverrunFlags.Trim | OverrunFlags.TrimWordOnly | OverrunFlags.AddEllipsis | OverrunFlags.EnforceEllipsis;
                default: return OverrunFlags.NoTrim;
            }
        }
    }

    // ---------- fonts ----------
    public abstract class Font : Resource
    {
        public const int SUBPIXEL_HALF_MAX_SIZE = 20;

        /// <summary>This font then its fallbacks, as Font::get_rids().</summary>
        public abstract IReadOnlyList<FontFile> GetRids();
        public virtual float SpacingTop => 0f;
        public virtual float SpacingBottom => 0f;
        public virtual float SpacingGlyph => 0f;
        public virtual float SpacingSpace => 0f;
        public virtual float Embolden => 0f;
        public List<Font> Fallbacks = new List<Font>();

        public double GetHeight(int size = 16)
        {
            float r = 0f;
            foreach (var f in GetRids()) r = Math.Max(r, f.Ascent(size) + f.Descent(size));
            return r + SpacingBottom + SpacingTop;
        }

        public double GetAscent(int size = 16)
        {
            float r = 0f;
            foreach (var f in GetRids()) r = Math.Max(r, f.Ascent(size));
            return r + SpacingTop;
        }

        public double GetDescent(int size = 16)
        {
            float r = 0f;
            foreach (var f in GetRids()) r = Math.Max(r, f.Descent(size));
            return r + SpacingBottom;
        }

        readonly Dictionary<(string, int), ShapedText> _cache = new Dictionary<(string, int), ShapedText>();

        internal ShapedText ShapeCached(string text, int size)
        {
            var key = (text ?? "", size);
            if (_cache.TryGetValue(key, out var st)) return st;
            if (_cache.Count > 512) _cache.Clear();
            st = ShapedText.Shape(text ?? "", this, size);
            _cache[key] = st;
            return st;
        }

        /// <summary>get_string_size: width of the shaped line (trimmed to `width` if given), height asc+desc.</summary>
        public Vec2 GetStringSize(string text, HorizontalAlignment alignment = HorizontalAlignment.Left, double width = -1, int fontSize = 16)
        {
            var st = ShapeCached(text, fontSize);
            if (width > 0 && st.width > width)
            {
                var t = st.Clone();
                t.OverrunTrim((float)width, OverrunFlags.Trim);
                return t.Size;
            }
            return st.Size;
        }

        public Vec2 GetMultilineStringSize(string text, HorizontalAlignment alignment = HorizontalAlignment.Left, double width = -1, int fontSize = 16, int maxLines = -1)
        {
            var lines = TextLayout.Paragraphs(text ?? "", this, fontSize, (float)width, width > 0 ? LineBreakFlags.Mandatory | LineBreakFlags.WordBound | LineBreakFlags.Adaptive | LineBreakFlags.TrimStartEdgeSpaces | LineBreakFlags.TrimEndEdgeSpaces : LineBreakFlags.Mandatory);
            float w = 0, h = 0;
            int n = 0;
            foreach (var l in lines)
            {
                if (maxLines >= 0 && n >= maxLines) break;
                w = Math.Max(w, l.width);
                h += l.ascent + l.descent;
                n++;
            }
            return new Vec2(w, h);
        }

        public Vec2 GetCharSize(int ch, int fontSize = 16)
        {
            foreach (var f in GetRids())
                if (f.Face.HasChar(ch)) return new Vec2(f.GlyphAdvance(f.Face.GlyphIndex(ch), fontSize), (float)GetHeight(fontSize));
            return Vec2.Zero;
        }

        public Vec2 GetCharSize(string ch, int fontSize = 16) => string.IsNullOrEmpty(ch) ? Vec2.Zero : GetCharSize(char.ConvertToUtf32(ch, 0), fontSize);

        Vec2 AlignedOrigin(ShapedText st, Vec2 pos, HorizontalAlignment alignment, float width)
        {
            Vec2 ofs = pos;
            float length = st.TrimmedWidth;
            if (width > 0)
            {
                if (alignment == HorizontalAlignment.Center && length <= width) ofs.x += MathF.Floor((width - length) / 2f);
                else if (alignment == HorizontalAlignment.Right) ofs.x += width - length;
            }
            return ofs;
        }

        ShapedText Prepared(string text, int size, float width)
        {
            var st = ShapeCached(text, size);
            if (width > 0 && st.width > width)
            {
                st = st.Clone();
                st.OverrunTrim(width, OverrunFlags.Trim);
            }
            return st;
        }

        /// <summary>draw_string: pos is the baseline's left end.</summary>
        public void DrawString(DrawList ci, Vec2 pos, string text, HorizontalAlignment alignment, float width, int fontSize, Col modulate)
        {
            var st = Prepared(text, fontSize, width);
            Vec2 o = AlignedOrigin(st, pos, alignment, width);
            st.Draw(ci, o, modulate, 0, width > 0 ? Math.Max(0, pos.x - o.x) : -1, width > 0 ? Math.Max(0, pos.x - o.x) + width : -1);
        }

        public void DrawStringOutline(DrawList ci, Vec2 pos, string text, HorizontalAlignment alignment, float width, int fontSize, int size, Col modulate)
        {
            var st = Prepared(text, fontSize, width);
            Vec2 o = AlignedOrigin(st, pos, alignment, width);
            st.Draw(ci, o, modulate, size, width > 0 ? Math.Max(0, pos.x - o.x) : -1, width > 0 ? Math.Max(0, pos.x - o.x) + width : -1);
        }

        public void DrawMultilineString(DrawList ci, Vec2 pos, string text, HorizontalAlignment alignment, float width, int fontSize, int maxLines, Col modulate)
        {
            var lines = TextLayout.Paragraphs(text ?? "", this, fontSize, width, width > 0 ? LineBreakFlags.Mandatory | LineBreakFlags.WordBound | LineBreakFlags.Adaptive | LineBreakFlags.TrimStartEdgeSpaces | LineBreakFlags.TrimEndEdgeSpaces : LineBreakFlags.Mandatory);
            Vec2 ofs = pos;
            int n = 0;
            foreach (var l in lines)
            {
                if (maxLines >= 0 && n >= maxLines) break;
                if (n > 0) ofs.y += l.ascent;
                Vec2 o = AlignedOrigin(l, ofs, alignment, width);
                l.Draw(ci, o, modulate, 0);
                ofs.y += l.descent;
                n++;
            }
        }

        public double DrawChar(DrawList ci, Vec2 pos, string ch, int fontSize, Col modulate)
        {
            if (string.IsNullOrEmpty(ch)) return 0;
            int cp = char.ConvertToUtf32(ch, 0);
            foreach (var f in GetRids())
                if (f.Face.HasChar(cp))
                {
                    int g = f.Face.GlyphIndex(cp);
                    f.DrawGlyph(ci, pos, g, fontSize, modulate, 0);
                    return f.GlyphAdvance(g, fontSize);
                }
            return 0;
        }

        public double DrawCharOutline(DrawList ci, Vec2 pos, string ch, int fontSize, int size, Col modulate)
        {
            if (string.IsNullOrEmpty(ch)) return 0;
            int cp = char.ConvertToUtf32(ch, 0);
            foreach (var f in GetRids())
                if (f.Face.HasChar(cp))
                {
                    int g = f.Face.GlyphIndex(cp);
                    f.DrawGlyph(ci, pos, g, fontSize, modulate, size);
                    return f.GlyphAdvance(g, fontSize);
                }
            return 0;
        }
    }

    public sealed class FontFile : Font
    {
        public TrueTypeFace Face;
        readonly List<FontFile> _rids = new List<FontFile>();
        readonly bool _roundMetrics;
        public bool AllowSystemFallback = true;

        public FontFile(TrueTypeFace face, bool roundMetrics)
        {
            Face = face;
            _roundMetrics = roundMetrics;
            _rids.Add(this);
        }

        public static FontFile FromBytes(byte[] data, string name = "")
        {
            var face = new TrueTypeFace(data, name);
            // head.flags bit 3: "ppem must be integer" -> FreeType rounds the size metrics; else ceil/floor.
            int head = FindHead(data);
            bool round = head >= 0 && ((data[head + 16] << 8 | data[head + 17]) & 8) != 0;
            return new FontFile(face, round) { ResourcePath = name };
        }

        static int FindHead(byte[] d)
        {
            int n = (d[4] << 8) | d[5];
            for (int i = 0; i < n; i++)
            {
                int r = 12 + i * 16;
                if (d[r] == 'h' && d[r + 1] == 'e' && d[r + 2] == 'a' && d[r + 3] == 'd')
                    return (d[r + 8] << 24) | (d[r + 9] << 16) | (d[r + 10] << 8) | d[r + 11];
            }
            return -1;
        }

        internal static FontFile LoadFromHost(string path)
        {
            byte[] data = ResourceLoader.Host?.ReadFile(path);
            if (data == null && path.EndsWith(".woff2")) data = ResourceLoader.Host?.ReadFile(path.Substring(0, path.Length - 6) + ".ttf");
            if (data == null) { GD_Log.Error("font missing: " + path); return null; }
            return FromBytes(data, path);
        }

        public override IReadOnlyList<FontFile> GetRids()
        {
            if (Fallbacks.Count == 0) return _rids;
            var o = new List<FontFile> { this };
            foreach (var f in Fallbacks)
                foreach (var r in f.GetRids())
                    if (!o.Contains(r)) o.Add(r);
            return o;
        }

        float Scale(int size) => size / (float)Face.UnitsPerEm;

        static float PixRound(float v) => MathF.Floor(v * 64f + 32f) / 64f;

        /// <summary>Fonts drawn as MSDF in Godot (the project's default font): metrics come from a 48 px face, scaled.</summary>
        public bool Msdf;
        public const int MSDF_SOURCE = 48;

        /// <summary>FreeType size metrics (ascender ceiled, descender floored to whole pixels at the nominal size).</summary>
        public float Ascent(int size)
        {
            if (Msdf) return MathF.Ceiling(Face.Ascender * Scale(MSDF_SOURCE)) * size / MSDF_SOURCE;
            return MathF.Ceiling(Face.Ascender * Scale(size));
        }

        public float Descent(int size)
        {
            if (Msdf) return -MathF.Floor(Face.Descender * Scale(MSDF_SOURCE)) * size / MSDF_SOURCE;
            return -MathF.Floor(Face.Descender * Scale(size));
        }

        /// <summary>Unhinted advance in 26.6 (HarfBuzz over FreeType without hinting).</summary>
        public float GlyphAdvance(int glyph, int size)
        {
            if (Msdf) return MathF.Round(Face.AdvanceWidth(glyph) * Scale(MSDF_SOURCE) * 64f) / 64f * size / MSDF_SOURCE;
            return MathF.Round(Face.AdvanceWidth(glyph) * Scale(size) * 64f) / 64f;
        }

        public float Kern(int g1, int g2, int size)
        {
            int k = Face.Kerning(g1, g2);
            if (k == 0) return 0f;
            if (Msdf) return MathF.Round(k * Scale(MSDF_SOURCE) * 64f) / 64f * size / MSDF_SOURCE;
            return MathF.Round(k * Scale(size) * 64f) / 64f;
        }

        /// <summary>Draws one glyph with its pen at `pos` (the baseline). outline &gt; 0: Godot's outline_size.</summary>
        public void DrawGlyph(DrawList ci, Vec2 pos, int glyph, int size, Col color, int outline)
        {
            var slot = GlyphAtlas.Shared.Get(this, glyph);
            if (slot == null) return;
            float s = size / GlyphAtlas.BASE;
            var dst = new Rect2(pos.x + slot.ox * s, pos.y + slot.oy * s, slot.w * s, slot.h * s);
            float aux = 0f;
            if (outline > 0)
            {
                float radiusPx = outline * GlyphAtlas.OUTLINE_RADIUS_PER_UNIT;
                float radiusBase = radiusPx / s;
                aux = Math.Min(0.49f, radiusBase / (2f * GlyphAtlas.SPREAD));
            }
            if (Embolden != 0f) aux += Embolden * 0.02f;
            ci.AddGlyph(dst, slot.page, slot.uv0, slot.uv1, color, aux);
        }
    }

    /// <summary>FontVariation: a base font with extra spacing / emboldening.</summary>
    public sealed class FontVariation : Font
    {
        public Font BaseFont;
        public float spacingTop, spacingBottom, spacingGlyph, spacingSpace, variationEmbolden;
        public override IReadOnlyList<FontFile> GetRids() => BaseFont?.GetRids() ?? ThemeDB.FallbackFont.GetRids();
        public override float SpacingTop => spacingTop;
        public override float SpacingBottom => spacingBottom;
        public override float SpacingGlyph => spacingGlyph;
        public override float SpacingSpace => spacingSpace;
        public override float Embolden => variationEmbolden;
    }

    // ---------- the SDF atlas ----------
    public sealed class GlyphSlot
    {
        public AtlasPage page;
        public Vec2 uv0, uv1;
        /// <summary>Quad offset from the pen (base px, y down) and size (base px).</summary>
        public float ox, oy, w, h;
    }

    public sealed class AtlasPage : CpuTexture
    {
        public readonly Image img;
        public AtlasPage(int size) { img = Image.CreateAlpha(size, size); linearFilter = true; }
        protected override Image BuildImage() => img;
        public override int GetWidth() => img.Width;
        public override int GetHeight() => img.Height;
        public void Touch() => MarkDirty();
        public override Image GetImage() => img;
    }

    public sealed class GlyphAtlas
    {
        public const float BASE = 48f;
        public const float SPREAD = 8f;
        /// <summary>Godot's FreeType stroker radius per unit of outline_size (FT_Stroker_Set(size.y * 16) in 26.6).</summary>
        public static float OUTLINE_RADIUS_PER_UNIT = 0.25f;
        public const int PAGE = 1024;
        public static GlyphAtlas Shared = new GlyphAtlas();

        readonly List<AtlasPage> _pages = new List<AtlasPage>();
        readonly Dictionary<(FontFile, int), GlyphSlot> _slots = new Dictionary<(FontFile, int), GlyphSlot>();
        int _x, _y, _rowH;
        readonly HashSet<AtlasPage> _dirty = new HashSet<AtlasPage>();
        public IReadOnlyList<AtlasPage> Pages => _pages;

        public GlyphSlot Get(FontFile f, int glyph)
        {
            if (_slots.TryGetValue((f, glyph), out var s)) return s;
            s = Make(f, glyph);
            _slots[(f, glyph)] = s;
            return s;
        }

        GlyphSlot Make(FontFile f, int glyph)
        {
            var face = f.Face;
            if (!face.Bounds(glyph, out int x0, out int y0, out int x1, out int y1)) return null;
            if (x1 <= x0 || y1 <= y0) return null;
            float sc = BASE / face.UnitsPerEm;
            int pad = (int)MathF.Ceiling(SPREAD) + 1;
            float fx0 = MathF.Floor(x0 * sc) - pad, fy1 = MathF.Ceiling(y1 * sc) + pad;
            int w = (int)(MathF.Ceiling(x1 * sc) + pad - fx0), h = (int)(fy1 - (MathF.Floor(y0 * sc) - pad));
            var field = SdfRaster.Render(face.Outline(glyph), sc, fx0, fy1, w, h, SPREAD);
            if (_pages.Count == 0 || _x + w > PAGE)
            {
                _x = 0;
                _y += _rowH + 1;
                _rowH = 0;
            }
            if (_pages.Count == 0 || _y + h > PAGE)
            {
                _pages.Add(new AtlasPage(PAGE));
                _x = 0; _y = 0; _rowH = 0;
            }
            var page = _pages[_pages.Count - 1];
            for (int yy = 0; yy < h; yy++) Array.Copy(field, yy * w, page.img.Data, (_y + yy) * PAGE + _x, w);
            var slot = new GlyphSlot
            {
                page = page,
                uv0 = new Vec2(_x / (float)PAGE, _y / (float)PAGE),
                uv1 = new Vec2((_x + w) / (float)PAGE, (_y + h) / (float)PAGE),
                ox = fx0, oy = -fy1, w = w, h = h,
            };
            _x += w + 1;
            _rowH = Math.Max(_rowH, h);
            page.Touch();
            return slot;
        }

        /// <summary>Renders the glyphs of `text` now (loading screens warm the common characters).</summary>
        public void Warm(Font font, string text)
        {
            foreach (var f in font.GetRids())
                foreach (char c in text)
                    if (f.Face.HasChar(c)) Get(f, f.Face.GlyphIndex(c));
        }
    }

    // ---------- shaped text ----------
    public struct ShapedGlyph
    {
        public int start, end, count, repeat;
        public float advance, xOff, yOff;
        public FontFile font;
        public int index, size;
        public GlyphFlags flags;
        public int cp;
    }

    public sealed class ShapedText
    {
        public List<ShapedGlyph> glyphs = new List<ShapedGlyph>();
        public int rangeStart, rangeEnd;
        public float width, ascent, descent;
        public Font font;
        public int size;
        public string text;
        /// <summary>After an overrun trim: glyphs drawn = [0, trimPos), then the ellipsis glyphs.</summary>
        public int trimPos = -1;
        public List<ShapedGlyph> ellipsis = new List<ShapedGlyph>();
        public float ellipsisWidth;

        public float TrimmedWidth
        {
            get
            {
                if (trimPos < 0) return width;
                float w = 0;
                for (int i = 0; i < trimPos; i++) w += glyphs[i].advance * glyphs[i].repeat;
                return w + ellipsisWidth;
            }
        }

        /// <summary>shaped_text_get_size: width and height rounded up to whole pixels.</summary>
        public Vec2 Size => new Vec2(MathF.Ceiling(TrimmedWidth), MathF.Ceiling(ascent + descent));

        public ShapedText Clone()
        {
            var o = (ShapedText)MemberwiseClone();
            o.glyphs = new List<ShapedGlyph>(glyphs);
            o.ellipsis = new List<ShapedGlyph>(ellipsis);
            return o;
        }

        static FontFile _sys;
        /// <summary>The system fallback for characters none of the font's faces have (DejaVu Sans).</summary>
        public static FontFile SystemFallback
        {
            get
            {
                if (_sys == null) _sys = ResourceLoader.Load<FontFile>("res://assets/fonts/DejaVuSans.ttf");
                return _sys;
            }
            set => _sys = value;
        }

        static bool IsWhitespace(int c) =>
            c == ' ' || c == 0x00a0 || c == 0x1680 || (c >= 0x2000 && c <= 0x200a) || c == 0x2028 || c == 0x2029 ||
            c == 0x202f || c == 0x205f || c == 0x3000 || (c >= 0x0009 && c <= 0x000d) || c == 0x0085;

        static bool IsLinebreak(int c) => (c >= 0x000a && c <= 0x000d) || c == 0x0085 || c == 0x2028 || c == 0x2029;

        static bool IsCjk(int c) => (c >= 0x2E80 && c <= 0x9FFF) || (c >= 0xAC00 && c <= 0xD7AF) || (c >= 0xF900 && c <= 0xFAFF) || (c >= 0xFF00 && c <= 0xFFEF) || (c >= 0x20000 && c <= 0x2FFFF);

        public static ShapedText Shape(string text, Font font, int size)
        {
            var st = new ShapedText { font = font, size = size, text = text, rangeStart = 0, rangeEnd = text.Length };
            var rids = font.GetRids();
            float sGlyph = font.SpacingGlyph, sSpace = font.SpacingSpace;
            bool subpos = size <= Font.SUBPIXEL_HALF_MAX_SIZE;
            float asc = 0, dsc = 0;
            if (rids.Count > 0) { asc = rids[0].Ascent(size); dsc = rids[0].Descent(size); }
            double rem = 0;
            FontFile prevFont = null;
            int prevGlyph = -1, prevIdx = -1;
            for (int i = 0; i < text.Length;)
            {
                int cp = char.ConvertToUtf32(text, i);
                int len = char.IsSurrogatePair(text, i) ? 2 : 1;
                FontFile f = null;
                int gi = 0;
                if (cp == 0x200B || cp == 0x200C || cp == 0x200D || cp == 0xFEFF || cp == '\n' || cp == '\r')
                {
                    f = rids.Count > 0 ? rids[0] : null;
                    gi = -1;
                }
                else
                {
                    foreach (var r in rids)
                        if (r.Face.HasChar(cp)) { f = r; gi = r.Face.GlyphIndex(cp); break; }
                    if (f == null && rids.Count > 0 && rids[0].AllowSystemFallback && SystemFallback != null && SystemFallback.Face.HasChar(cp))
                    {
                        f = SystemFallback;
                        gi = f.Face.GlyphIndex(cp);
                    }
                    if (f == null) { f = rids.Count > 0 ? rids[0] : null; gi = 0; }
                }
                var g = new ShapedGlyph { start = i, end = i + len, count = 1, repeat = 1, font = f, index = gi, size = size, cp = cp };
                if (IsWhitespace(cp)) g.flags |= GlyphFlags.Space;
                if (cp == '\t') g.flags |= GlyphFlags.Tab;
                if (IsLinebreak(cp)) g.flags |= GlyphFlags.BreakHard;
                else if (IsWhitespace(cp) || cp == '-' || cp == 0x2010 || cp == 0x2013 || cp == 0x2014 || cp == 0x200B || cp == '/' || IsCjk(cp)) g.flags |= GlyphFlags.BreakSoft;
                if (cp == 0x00AD) g.flags |= GlyphFlags.SoftHyphen | GlyphFlags.BreakSoft;
                if (char.IsPunctuation((char)Math.Min(cp, 0xFFFF))) g.flags |= GlyphFlags.Punct;
                double adv = 0;
                if (f != null && gi >= 0)
                {
                    adv = f.GlyphAdvance(gi, size);
                    asc = Math.Max(asc, f.Ascent(size));
                    dsc = Math.Max(dsc, f.Descent(size));
                }
                if (gi < 0) g.flags |= GlyphFlags.Virtual;
                // GPOS kerning moves the previous glyph's advance.
                if (prevIdx >= 0 && prevFont != null && prevFont == f && gi > 0 && prevGlyph > 0)
                {
                    float k = f.Kern(prevGlyph, gi, size);
                    if (k != 0)
                    {
                        var pg = st.glyphs[prevIdx];
                        pg.advance += k;
                        st.glyphs[prevIdx] = pg;
                    }
                }
                adv += (g.flags & GlyphFlags.Space) != 0 ? sSpace : 0;
                if (gi >= 0) adv += sGlyph;
                g.advance = (float)adv;
                st.glyphs.Add(g);
                prevFont = f;
                prevGlyph = gi;
                prevIdx = st.glyphs.Count - 1;
                i += len;
            }
            // Whole-pixel advances above size 20 (not for MSDF fonts, which scale), with the rounding remainder carried
            // (keep_rounding_remainders) and reset at blanks.
            if (!subpos)
            {
                rem = 0;
                for (int i = 0; i < st.glyphs.Count; i++)
                {
                    var g = st.glyphs[i];
                    if (g.cp == '\t' || g.cp == ' ' || g.cp == 0xA0 || (g.cp >= 0x2000 && g.cp <= 0x200A) || g.cp == 0x3000 || IsLinebreak(g.cp)) rem = 0;
                    if ((g.flags & GlyphFlags.Virtual) != 0 || g.font == null || (g.font.Msdf && size != FontFile.MSDF_SOURCE)) continue;
                    double full = rem + g.advance;
                    g.advance = (float)Math.Round(full, MidpointRounding.AwayFromZero);
                    rem = full - g.advance;
                    st.glyphs[i] = g;
                }
            }
            float w = 0;
            foreach (var g in st.glyphs) w += g.advance * g.repeat;
            st.width = w;
            st.ascent = asc;
            st.descent = dsc;
            return st;
        }

        /// <summary>shaped_text_substr: the glyphs in [start, start+length).</summary>
        public ShapedText Substr(int start, int length)
        {
            var o = new ShapedText { font = font, size = size, text = text, rangeStart = start, rangeEnd = start + length };
            var rids = font.GetRids();
            float asc = rids.Count > 0 ? rids[0].Ascent(size) : 0, dsc = rids.Count > 0 ? rids[0].Descent(size) : 0;
            float w = 0;
            foreach (var g in glyphs)
            {
                if (g.start >= start && g.end <= start + length)
                {
                    o.glyphs.Add(g);
                    w += g.advance * g.repeat;
                    if (g.font != null && g.index >= 0)
                    {
                        asc = Math.Max(asc, g.font.Ascent(size));
                        dsc = Math.Max(dsc, g.font.Descent(size));
                    }
                }
            }
            o.width = w;
            o.ascent = asc;
            o.descent = dsc;
            return o;
        }

        bool Has(int i, GlyphFlags f) => (glyphs[i].flags & f) == f;

        /// <summary>TextServer::shaped_text_get_line_breaks, ported.</summary>
        public List<int> GetLineBreaks(float pWidth, int pStart, LineBreakFlags flags)
        {
            var lines = new List<int>();
            float width = 0f;
            int lineStart = Math.Max(pStart, rangeStart);
            int lastEnd = lineStart;
            int prevSafeBreak = 0;
            int lastSafeBreak = -1;
            int wordCount = 0;
            bool trimNext = false;
            int lSize = glyphs.Count;
            var l = glyphs;
            int indentEnd = 0;
            double indent = 0;
            bool trimStart = (flags & LineBreakFlags.TrimStartEdgeSpaces) != 0, trimEnd = (flags & LineBreakFlags.TrimEndEdgeSpaces) != 0;
            bool IsEdge(int i, bool soft) =>
                (soft || (l[i].flags & GlyphFlags.SoftHyphen) == 0) &&
                ((l[i].flags & GlyphFlags.Space) != 0 || (l[i].flags & GlyphFlags.BreakHard) != 0 || (l[i].flags & GlyphFlags.BreakSoft) != 0);
            double lWidth = pWidth;
            for (int i = 0; i < lSize; i++)
            {
                if (l[i].start < pStart)
                {
                    prevSafeBreak = i + 1;
                    continue;
                }
                if (l[i].count > 0)
                {
                    float adv = 0f;
                    for (int j = i; j < lSize && l[i].end == l[j].end && l[i].start == l[j].start; j++) adv += l[j].advance * l[j].repeat;
                    if (lWidth > 0 && width + adv > lWidth && lastSafeBreak >= 0)
                    {
                        int curSafeBrk = lastSafeBreak;
                        if (trimStart || trimEnd)
                        {
                            int startPos = prevSafeBreak, endPos = lastSafeBreak;
                            while (trimStart && trimNext && startPos < endPos && IsEdge(startPos, false)) startPos += l[startPos].count;
                            while (trimEnd && startPos <= endPos && endPos > 0 && IsEdge(endPos, false)) endPos -= l[endPos].count;
                            if (lastEnd <= l[startPos].start && l[startPos].start != l[endPos].end)
                            {
                                lines.Add(l[startPos].start);
                                lines.Add(l[endPos].end);
                                curSafeBrk = lastSafeBreak;
                                lastEnd = l[endPos].end;
                            }
                            trimNext = true;
                        }
                        else if (lastEnd <= lineStart)
                        {
                            lines.Add(lineStart);
                            lines.Add(l[lastSafeBreak].end);
                            lastEnd = l[lastSafeBreak].end;
                        }
                        lineStart = l[curSafeBrk].end;
                        prevSafeBreak = curSafeBrk + 1;
                        while (prevSafeBreak < lSize && l[prevSafeBreak].end == lineStart) prevSafeBreak++;
                        i = curSafeBrk;
                        lastSafeBreak = -1;
                        width = 0;
                        wordCount = 0;
                        continue;
                    }
                    if ((flags & LineBreakFlags.Mandatory) != 0 && (l[i].flags & GlyphFlags.BreakHard) != 0)
                    {
                        int curSafeBrk = i;
                        if (trimStart || trimEnd)
                        {
                            int startPos = prevSafeBreak, endPos = i;
                            while (trimStart && trimNext && startPos < endPos && IsEdge(startPos, true)) startPos += l[startPos].count;
                            while (trimEnd && startPos <= endPos && endPos > 0 && IsEdge(endPos, true)) endPos -= l[endPos].count;
                            trimNext = true;
                            if (lastEnd <= l[startPos].start && l[startPos].start != l[endPos].end)
                            {
                                lines.Add(l[startPos].start);
                                lines.Add(l[endPos].end);
                                lastEnd = l[i].end;
                                curSafeBrk = i;
                            }
                        }
                        else if (lastEnd <= lineStart)
                        {
                            lines.Add(lineStart);
                            lines.Add(l[i].end);
                            lastEnd = l[i].end;
                        }
                        lineStart = l[curSafeBrk].end;
                        prevSafeBreak = curSafeBrk + 1;
                        while (prevSafeBreak < lSize && l[prevSafeBreak].end == lineStart) prevSafeBreak++;
                        lastSafeBreak = -1;
                        width = 0;
                        continue;
                    }
                    if ((flags & LineBreakFlags.WordBound) != 0)
                    {
                        if ((l[i].flags & GlyphFlags.BreakSoft) != 0)
                        {
                            if ((l[i].flags & GlyphFlags.SoftHyphen) != 0)
                            {
                                float hw = l[i].font != null ? l[i].font.GlyphAdvance(l[i].font.Face.GlyphIndex(0x2D), size) : 0f;
                                if (width + adv + hw <= pWidth || hw >= pWidth) { lastSafeBreak = i; wordCount++; }
                            }
                            else if (i >= indentEnd) { lastSafeBreak = i; wordCount++; }
                        }
                        if ((flags & LineBreakFlags.Adaptive) != 0 && wordCount == 0) lastSafeBreak = i;
                    }
                    if ((flags & LineBreakFlags.GraphemeBound) != 0) lastSafeBreak = i;
                }
                width += l[i].advance * l[i].repeat;
            }
            if (lSize > 0)
            {
                if (lines.Count == 0 || (lines[lines.Count - 1] < rangeEnd && prevSafeBreak < lSize))
                {
                    if (trimStart)
                    {
                        int startPos = prevSafeBreak < lSize ? prevSafeBreak : lSize - 1;
                        if (lastEnd <= l[startPos].start)
                        {
                            int endPos = lSize - 1;
                            while (trimNext && startPos < endPos && IsEdge(startPos, true)) startPos += l[startPos].count;
                            lines.Add(l[startPos].start);
                        }
                        else lines.Add(lastEnd);
                    }
                    else lines.Add(Math.Max(lastEnd, lineStart));
                    lines.Add(rangeEnd);
                }
            }
            else
            {
                lines.Add(0);
                lines.Add(0);
            }
            _ = indent;
            return lines;
        }

        /// <summary>shaped_text_overrun_trim_to_width (left-to-right): drop trailing glyphs to fit, with "…" if asked.</summary>
        public void OverrunTrim(float pWidth, OverrunFlags flags, int elChar = 0x2026)
        {
            trimPos = -1;
            ellipsis.Clear();
            ellipsisWidth = 0;
            bool addEl = (flags & OverrunFlags.AddEllipsis) != 0, perWord = (flags & OverrunFlags.TrimWordOnly) != 0, enforce = (flags & OverrunFlags.EnforceEllipsis) != 0;
            if ((flags & OverrunFlags.Trim) == 0 || glyphs.Count == 0 || pWidth <= 0 || !(width > pWidth || enforce)) return;
            var last = glyphs[glyphs.Count - 1];
            FontFile ef = last.font;
            bool foundEl = ef != null && ef.Face.HasChar(elChar);
            if (!foundEl)
                foreach (var r in font.GetRids())
                    if (r.Face.HasChar(elChar)) { ef = r; foundEl = true; break; }
            if (ef == null) return;
            int dot = ef.Face.GlyphIndex(foundEl ? elChar : '.');
            float dotAdv = ef.GlyphAdvance(dot, size);
            float spaceAdv = ef.GlyphAdvance(ef.Face.GlyphIndex(' '), size);
            float elW = addEl ? (foundEl ? 1 : 3) * dotAdv + font.SpacingGlyph + (perWord ? spaceAdv : 0) : 0;
            const int ELL_MIN_CHARACTERS = 6;
            float w = width;
            int trim = 0;
            int lastValidCut = -1;
            float widthNoEl = w;
            int lastValidNoEl = -1;
            if (enforce && w + elW <= pWidth) trim = glyphs.Count;
            else
            {
                for (int i = glyphs.Count - 1; i >= 0; i--)
                {
                    w -= glyphs[i].advance * glyphs[i].repeat;
                    if (glyphs[i].count <= 0) continue;
                    bool above = i >= ELL_MIN_CHARACTERS;
                    if (!above && lastValidNoEl != -1)
                    {
                        trim = lastValidNoEl;
                        addEl = false;
                        w = widthNoEl;
                        lastValidCut = trim;
                        break;
                    }
                    if (!enforce && w <= pWidth && lastValidNoEl == -1)
                    {
                        if (perWord && above)
                        {
                            if ((glyphs[i].flags & GlyphFlags.BreakSoft) != 0) { lastValidNoEl = i; widthNoEl = w; }
                        }
                        else if (!perWord) { lastValidNoEl = i; widthNoEl = w; }
                        if (!addEl) { trim = i; lastValidCut = i; break; }
                    }
                    if (w + elW <= pWidth)
                    {
                        if (perWord && above)
                        {
                            if ((glyphs[i].flags & GlyphFlags.BreakSoft) != 0) { lastValidCut = i; trim = i; break; }
                        }
                        else if (!perWord) { lastValidCut = i; trim = i; break; }
                    }
                }
                if (lastValidCut < 0) trim = 0;
            }
            trimPos = trim;
            if (addEl && (trim < glyphs.Count || enforce))
            {
                int n = foundEl ? 1 : 3;
                for (int k = 0; k < n; k++)
                    ellipsis.Add(new ShapedGlyph { font = ef, index = dot, advance = dotAdv, size = size, count = 1, repeat = 1, cp = foundEl ? elChar : '.' });
                ellipsisWidth = n * dotAdv;
            }
        }

        /// <summary>shaped_text_draw: pen starts at `pos` (baseline). Glyphs outside [clipL, clipR] are skipped.</summary>
        public void Draw(DrawList ci, Vec2 pos, Col color, int outline, float clipL = -1, float clipR = -1)
        {
            float x = 0;
            int n = trimPos >= 0 ? trimPos : glyphs.Count;
            for (int i = 0; i < n; i++)
            {
                var g = glyphs[i];
                float adv = g.advance * g.repeat;
                if (clipR > 0 && x + adv > clipR + 0.01f) break;
                if (!(clipL > 0 && x < clipL) && g.font != null && g.index > 0 && (g.flags & GlyphFlags.Space) == 0)
                    for (int r = 0; r < g.repeat; r++) g.font.DrawGlyph(ci, new Vec2(pos.x + x + g.xOff + r * g.advance, pos.y + g.yOff), g.index, g.size, color, outline);
                x += adv;
            }
            foreach (var g in ellipsis)
            {
                g.font?.DrawGlyph(ci, new Vec2(pos.x + x, pos.y), g.index, g.size, color, outline);
                x += g.advance;
            }
        }

        public bool HasVisibleChars()
        {
            foreach (var g in glyphs) if ((g.flags & (GlyphFlags.Space | GlyphFlags.Virtual)) == 0 && g.index >= 0) return true;
            return false;
        }

        public int GlyphCount => glyphs.Count;
    }

    /// <summary>Shared helpers for multi-line text (Font.draw_multiline_string, RichTextLabel).</summary>
    public static class TextLayout
    {
        public static List<ShapedText> Paragraphs(string text, Font font, int size, float width, LineBreakFlags flags)
        {
            var o = new List<ShapedText>();
            foreach (var para in text.Split('\n'))
            {
                var st = ShapedText.Shape(para + "​", font, size);
                var br = st.GetLineBreaks(width, 0, flags);
                for (int i = 0; i + 1 < br.Count; i += 2) o.Add(st.Substr(br[i], br[i + 1] - br[i]));
            }
            return o;
        }
    }

    /// <summary>ThemeDB: the project-wide fallback font and size.</summary>
    public static class ThemeDB
    {
        static Font _fallback;
        public static int FallbackFontSize = 16;
        public static double FallbackBaseScale = 1.0;

        /// <summary>Godot's default font (Open Sans SemiBold), synced to res://assets/fonts/OpenSans_SemiBold.ttf.</summary>
        public static Font FallbackFont
        {
            get
            {
                if (_fallback == null)
                {
                    var f = ResourceLoader.Load<FontFile>("res://assets/fonts/OpenSans_SemiBold.ttf");
                    if (f != null) f.Msdf = true;   // project setting gui/theme/default_font_multichannel_signed_distance_field
                    _fallback = f;
                }
                return _fallback;
            }
            set => _fallback = value;
        }
    }
}
