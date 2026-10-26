// Fatebound GUI (Unity port): the rest of GDScript's Rect2 / Color / Transform2D API on top of Math2D.cs (whose members
// the UI framework uses and are left exactly as they are), plus Variant support (str(), hash(), truthiness and the
// engine's operators through Var). core/math/rect2.h, color.{h,cpp} (+ thirdparty ok_color.h for OKHSL),
// transform_2d.{h,cpp}; real_t = float.
//
// Where a member that already existed differs from Godot (kept for the UI's verified output), the Godot-exact form is
// here under another name: Xform2.FromRotation / FromRotationScaleSkew / RotatedExact / RotatedLocalExact /
// GetRotationExact, the `transform * rect` and `vector * transform` operators, Col.FromString / NamedExact /
// IsEqualApproxExact / ToRgba32Exact, Rect2.GrowIndividualExact / GrowSideExact. GodotStr() (what GD.Str prints) is
// always Godot's text.
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public partial struct Rect2 : IGodotValue
    {
        public Vec2 GetEnd() => position + size;
        public bool HasArea() => size.x > 0.0f && size.y > 0.0f;
        public bool IsEqualApprox(Rect2 r) => position.IsEqualApprox(r.position) && size.IsEqualApprox(r.size);
        public bool IsFinite() => position.IsFinite() && size.IsFinite();

        public Vec2 GetSupport(Vec2 direction)
        {
            Vec2 support = position;
            if (direction.x > 0.0f) support.x += size.x;
            if (direction.y > 0.0f) support.y += size.y;
            return support;
        }

        /// <summary>grow_individual exactly as Godot (size += left + right; the existing GrowIndividual adds them one
        /// at a time, which can differ in the last bit).</summary>
        public Rect2 GrowIndividualExact(double left, double top, double right, double bottom)
        {
            float l = (float)left, t = (float)top, r = (float)right, b = (float)bottom;
            var g = this;
            g.position = new Vec2(g.position.x - l, g.position.y - t);
            g.size = new Vec2(g.size.x + (l + r), g.size.y + (t + b));
            return g;
        }

        public Rect2 GrowSideExact(long side, double amount)
        {
            float a = (float)amount;
            return GrowIndividualExact(side == (int)Side.Left ? a : 0, side == (int)Side.Top ? a : 0, side == (int)Side.Right ? a : 0, side == (int)Side.Bottom ? a : 0);
        }

        /// <summary>C++ Rect2::expand_to (Godot's comparisons, used by Transform2D * Rect2).</summary>
        internal Rect2 ExpandToExact(Vec2 v)
        {
            Vec2 begin = position, end = position + size;
            if (v.x < begin.x) begin.x = v.x;
            if (v.y < begin.y) begin.y = v.y;
            if (v.x > end.x) end.x = v.x;
            if (v.y > end.y) end.y = v.y;
            return new Rect2(begin, end - begin);
        }

        public float DistanceTo(Vec2 p)
        {
            float dist = 0.0f;
            bool inside = true;
            if (p.x < position.x) { dist = position.x - p.x; inside = false; }
            if (p.y < position.y) { float d = position.y - p.y; dist = inside ? d : GD.MinF(dist, d); inside = false; }
            if (p.x >= (position.x + size.x)) { float d = p.x - (position.x + size.x); dist = inside ? d : GD.MinF(dist, d); inside = false; }
            if (p.y >= (position.y + size.y)) { float d = p.y - (position.y + size.y); dist = inside ? d : GD.MinF(dist, d); inside = false; }
            return inside ? 0 : dist;
        }

        // ------------------------------------------------------------------ Variant
        public static implicit operator Var(Rect2 r) => Var.Of(r);
        public static explicit operator Rect2(Var v) => v.Obj is Rect2 r ? r : default;
        public int GodotType => GD.TYPE_RECT2;
        public string GodotStr() => "[P: " + position + ", S: " + size + "]";
        public bool GodotIsZero => this == default(Rect2);
        public uint GodotHash()
        {
            uint h = GHashing.Murmur3OneFloat(position.x);
            h = GHashing.Murmur3OneFloat(position.y, h);
            h = GHashing.Murmur3OneFloat(size.x, h);
            h = GHashing.Murmur3OneFloat(size.y, h);
            return GHashing.Fmix32(h);
        }
        public bool GodotOp(char op, Var other, bool selfLeft, out Var result)
        {
            result = Var.Nil;
            if (op == '*' && selfLeft && other.Obj is Xform2 t) { result = t.XformInvRect(this); return true; }
            return false;
        }
    }

    public partial struct Col : IGodotValue
    {
        // (the named colors Math2D.cs didn't have, with Godot's exact values: Color::hex of color_names.inc)
        public static readonly Col ALICE_BLUE = Hex(0xF0F8FFFFu);
        public static readonly Col ANTIQUE_WHITE = Hex(0xFAEBD7FFu);
        public static readonly Col AQUAMARINE = Hex(0x7FFFD4FFu);
        public static readonly Col AZURE = Hex(0xF0FFFFFFu);
        public static readonly Col BISQUE = Hex(0xFFE4C4FFu);
        public static readonly Col BLANCHED_ALMOND = Hex(0xFFEBCDFFu);
        public static readonly Col BLUE_VIOLET = Hex(0x8A2BE2FFu);
        public static readonly Col BURLYWOOD = Hex(0xDEB887FFu);
        public static readonly Col CADET_BLUE = Hex(0x5F9EA0FFu);
        public static readonly Col CHOCOLATE = Hex(0xD2691EFFu);
        public static readonly Col CORNFLOWER_BLUE = Hex(0x6495EDFFu);
        public static readonly Col CORNSILK = Hex(0xFFF8DCFFu);
        public static readonly Col DARK_BLUE = Hex(0x00008BFFu);
        public static readonly Col DARK_CYAN = Hex(0x008B8BFFu);
        public static readonly Col DARK_GOLDENROD = Hex(0xB8860BFFu);
        public static readonly Col DARK_KHAKI = Hex(0xBDB76BFFu);
        public static readonly Col DARK_MAGENTA = Hex(0x8B008BFFu);
        public static readonly Col DARK_OLIVE_GREEN = Hex(0x556B2FFFu);
        public static readonly Col DARK_ORCHID = Hex(0x9932CCFFu);
        public static readonly Col DARK_SALMON = Hex(0xE9967AFFu);
        public static readonly Col DARK_SEA_GREEN = Hex(0x8FBC8FFFu);
        public static readonly Col DARK_SLATE_BLUE = Hex(0x483D8BFFu);
        public static readonly Col DARK_TURQUOISE = Hex(0x00CED1FFu);
        public static readonly Col DARK_VIOLET = Hex(0x9400D3FFu);
        public static readonly Col DEEP_PINK = Hex(0xFF1493FFu);
        public static readonly Col FLORAL_WHITE = Hex(0xFFFAF0FFu);
        public static readonly Col FUCHSIA = Hex(0xFF00FFFFu);
        public static readonly Col GAINSBORO = Hex(0xDCDCDCFFu);
        public static readonly Col GHOST_WHITE = Hex(0xF8F8FFFFu);
        public static readonly Col GREEN_YELLOW = Hex(0xADFF2FFFu);
        public static readonly Col HONEYDEW = Hex(0xF0FFF0FFu);
        public static readonly Col INDIGO = Hex(0x4B0082FFu);
        public static readonly Col LAVENDER_BLUSH = Hex(0xFFF0F5FFu);
        public static readonly Col LEMON_CHIFFON = Hex(0xFFFACDFFu);
        public static readonly Col LIGHT_CYAN = Hex(0xE0FFFFFFu);
        public static readonly Col LIGHT_GOLDENROD = Hex(0xFAFAD2FFu);
        public static readonly Col LIGHT_PINK = Hex(0xFFB6C1FFu);
        public static readonly Col LIGHT_SEA_GREEN = Hex(0x20B2AAFFu);
        public static readonly Col LIGHT_SLATE_GRAY = Hex(0x778899FFu);
        public static readonly Col LIGHT_STEEL_BLUE = Hex(0xB0C4DEFFu);
        public static readonly Col LIME = Hex(0x00FF00FFu);
        public static readonly Col LINEN = Hex(0xFAF0E6FFu);
        public static readonly Col MEDIUM_AQUAMARINE = Hex(0x66CDAAFFu);
        public static readonly Col MEDIUM_BLUE = Hex(0x0000CDFFu);
        public static readonly Col MEDIUM_ORCHID = Hex(0xBA55D3FFu);
        public static readonly Col MEDIUM_SEA_GREEN = Hex(0x3CB371FFu);
        public static readonly Col MEDIUM_SLATE_BLUE = Hex(0x7B68EEFFu);
        public static readonly Col MEDIUM_SPRING_GREEN = Hex(0x00FA9AFFu);
        public static readonly Col MEDIUM_TURQUOISE = Hex(0x48D1CCFFu);
        public static readonly Col MEDIUM_VIOLET_RED = Hex(0xC71585FFu);
        public static readonly Col MINT_CREAM = Hex(0xF5FFFAFFu);
        public static readonly Col MISTY_ROSE = Hex(0xFFE4E1FFu);
        public static readonly Col MOCCASIN = Hex(0xFFE4B5FFu);
        public static readonly Col NAVAJO_WHITE = Hex(0xFFDEADFFu);
        public static readonly Col OLD_LACE = Hex(0xFDF5E6FFu);
        public static readonly Col OLIVE_DRAB = Hex(0x6B8E23FFu);
        public static readonly Col ORCHID = Hex(0xDA70D6FFu);
        public static readonly Col PALE_GOLDENROD = Hex(0xEEE8AAFFu);
        public static readonly Col PALE_VIOLET_RED = Hex(0xDB7093FFu);
        public static readonly Col PAPAYA_WHIP = Hex(0xFFEFD5FFu);
        public static readonly Col PEACH_PUFF = Hex(0xFFDAB9FFu);
        public static readonly Col PERU = Hex(0xCD853FFFu);
        public static readonly Col PLUM = Hex(0xDDA0DDFFu);
        public static readonly Col POWDER_BLUE = Hex(0xB0E0E6FFu);
        public static readonly Col REBECCA_PURPLE = Hex(0x663399FFu);
        public static readonly Col ROSY_BROWN = Hex(0xBC8F8FFFu);
        public static readonly Col SANDY_BROWN = Hex(0xF4A460FFu);
        public static readonly Col SEASHELL = Hex(0xFFF5EEFFu);
        public static readonly Col SIENNA = Hex(0xA0522DFFu);
        public static readonly Col SLATE_BLUE = Hex(0x6A5ACDFFu);
        public static readonly Col SLATE_GRAY = Hex(0x708090FFu);
        public static readonly Col THISTLE = Hex(0xD8BFD8FFu);
        public static readonly Col WEB_GREEN = Hex(0x008000FFu);
        public static readonly Col WEB_MAROON = Hex(0x800000FFu);
        public static readonly Col WEB_PURPLE = Hex(0x800080FFu);
        public static readonly Col WHITE_SMOKE = Hex(0xF5F5F5FFu);

        static readonly (string name, uint hex)[] NamedTable = {
            ("ALICE_BLUE", 0xF0F8FFFFu),
            ("ANTIQUE_WHITE", 0xFAEBD7FFu),
            ("AQUA", 0x00FFFFFFu),
            ("AQUAMARINE", 0x7FFFD4FFu),
            ("AZURE", 0xF0FFFFFFu),
            ("BEIGE", 0xF5F5DCFFu),
            ("BISQUE", 0xFFE4C4FFu),
            ("BLACK", 0x000000FFu),
            ("BLANCHED_ALMOND", 0xFFEBCDFFu),
            ("BLUE", 0x0000FFFFu),
            ("BLUE_VIOLET", 0x8A2BE2FFu),
            ("BROWN", 0xA52A2AFFu),
            ("BURLYWOOD", 0xDEB887FFu),
            ("CADET_BLUE", 0x5F9EA0FFu),
            ("CHARTREUSE", 0x7FFF00FFu),
            ("CHOCOLATE", 0xD2691EFFu),
            ("CORAL", 0xFF7F50FFu),
            ("CORNFLOWER_BLUE", 0x6495EDFFu),
            ("CORNSILK", 0xFFF8DCFFu),
            ("CRIMSON", 0xDC143CFFu),
            ("CYAN", 0x00FFFFFFu),
            ("DARK_BLUE", 0x00008BFFu),
            ("DARK_CYAN", 0x008B8BFFu),
            ("DARK_GOLDENROD", 0xB8860BFFu),
            ("DARK_GRAY", 0xA9A9A9FFu),
            ("DARK_GREEN", 0x006400FFu),
            ("DARK_KHAKI", 0xBDB76BFFu),
            ("DARK_MAGENTA", 0x8B008BFFu),
            ("DARK_OLIVE_GREEN", 0x556B2FFFu),
            ("DARK_ORANGE", 0xFF8C00FFu),
            ("DARK_ORCHID", 0x9932CCFFu),
            ("DARK_RED", 0x8B0000FFu),
            ("DARK_SALMON", 0xE9967AFFu),
            ("DARK_SEA_GREEN", 0x8FBC8FFFu),
            ("DARK_SLATE_BLUE", 0x483D8BFFu),
            ("DARK_SLATE_GRAY", 0x2F4F4FFFu),
            ("DARK_TURQUOISE", 0x00CED1FFu),
            ("DARK_VIOLET", 0x9400D3FFu),
            ("DEEP_PINK", 0xFF1493FFu),
            ("DEEP_SKY_BLUE", 0x00BFFFFFu),
            ("DIM_GRAY", 0x696969FFu),
            ("DODGER_BLUE", 0x1E90FFFFu),
            ("FIREBRICK", 0xB22222FFu),
            ("FLORAL_WHITE", 0xFFFAF0FFu),
            ("FOREST_GREEN", 0x228B22FFu),
            ("FUCHSIA", 0xFF00FFFFu),
            ("GAINSBORO", 0xDCDCDCFFu),
            ("GHOST_WHITE", 0xF8F8FFFFu),
            ("GOLD", 0xFFD700FFu),
            ("GOLDENROD", 0xDAA520FFu),
            ("GRAY", 0xBEBEBEFFu),
            ("GREEN", 0x00FF00FFu),
            ("GREEN_YELLOW", 0xADFF2FFFu),
            ("HONEYDEW", 0xF0FFF0FFu),
            ("HOT_PINK", 0xFF69B4FFu),
            ("INDIAN_RED", 0xCD5C5CFFu),
            ("INDIGO", 0x4B0082FFu),
            ("IVORY", 0xFFFFF0FFu),
            ("KHAKI", 0xF0E68CFFu),
            ("LAVENDER", 0xE6E6FAFFu),
            ("LAVENDER_BLUSH", 0xFFF0F5FFu),
            ("LAWN_GREEN", 0x7CFC00FFu),
            ("LEMON_CHIFFON", 0xFFFACDFFu),
            ("LIGHT_BLUE", 0xADD8E6FFu),
            ("LIGHT_CORAL", 0xF08080FFu),
            ("LIGHT_CYAN", 0xE0FFFFFFu),
            ("LIGHT_GOLDENROD", 0xFAFAD2FFu),
            ("LIGHT_GRAY", 0xD3D3D3FFu),
            ("LIGHT_GREEN", 0x90EE90FFu),
            ("LIGHT_PINK", 0xFFB6C1FFu),
            ("LIGHT_SALMON", 0xFFA07AFFu),
            ("LIGHT_SEA_GREEN", 0x20B2AAFFu),
            ("LIGHT_SKY_BLUE", 0x87CEFAFFu),
            ("LIGHT_SLATE_GRAY", 0x778899FFu),
            ("LIGHT_STEEL_BLUE", 0xB0C4DEFFu),
            ("LIGHT_YELLOW", 0xFFFFE0FFu),
            ("LIME", 0x00FF00FFu),
            ("LIME_GREEN", 0x32CD32FFu),
            ("LINEN", 0xFAF0E6FFu),
            ("MAGENTA", 0xFF00FFFFu),
            ("MAROON", 0xB03060FFu),
            ("MEDIUM_AQUAMARINE", 0x66CDAAFFu),
            ("MEDIUM_BLUE", 0x0000CDFFu),
            ("MEDIUM_ORCHID", 0xBA55D3FFu),
            ("MEDIUM_PURPLE", 0x9370DBFFu),
            ("MEDIUM_SEA_GREEN", 0x3CB371FFu),
            ("MEDIUM_SLATE_BLUE", 0x7B68EEFFu),
            ("MEDIUM_SPRING_GREEN", 0x00FA9AFFu),
            ("MEDIUM_TURQUOISE", 0x48D1CCFFu),
            ("MEDIUM_VIOLET_RED", 0xC71585FFu),
            ("MIDNIGHT_BLUE", 0x191970FFu),
            ("MINT_CREAM", 0xF5FFFAFFu),
            ("MISTY_ROSE", 0xFFE4E1FFu),
            ("MOCCASIN", 0xFFE4B5FFu),
            ("NAVAJO_WHITE", 0xFFDEADFFu),
            ("NAVY_BLUE", 0x000080FFu),
            ("OLD_LACE", 0xFDF5E6FFu),
            ("OLIVE", 0x808000FFu),
            ("OLIVE_DRAB", 0x6B8E23FFu),
            ("ORANGE", 0xFFA500FFu),
            ("ORANGE_RED", 0xFF4500FFu),
            ("ORCHID", 0xDA70D6FFu),
            ("PALE_GOLDENROD", 0xEEE8AAFFu),
            ("PALE_GREEN", 0x98FB98FFu),
            ("PALE_TURQUOISE", 0xAFEEEEFFu),
            ("PALE_VIOLET_RED", 0xDB7093FFu),
            ("PAPAYA_WHIP", 0xFFEFD5FFu),
            ("PEACH_PUFF", 0xFFDAB9FFu),
            ("PERU", 0xCD853FFFu),
            ("PINK", 0xFFC0CBFFu),
            ("PLUM", 0xDDA0DDFFu),
            ("POWDER_BLUE", 0xB0E0E6FFu),
            ("PURPLE", 0xA020F0FFu),
            ("REBECCA_PURPLE", 0x663399FFu),
            ("RED", 0xFF0000FFu),
            ("ROSY_BROWN", 0xBC8F8FFFu),
            ("ROYAL_BLUE", 0x4169E1FFu),
            ("SADDLE_BROWN", 0x8B4513FFu),
            ("SALMON", 0xFA8072FFu),
            ("SANDY_BROWN", 0xF4A460FFu),
            ("SEA_GREEN", 0x2E8B57FFu),
            ("SEASHELL", 0xFFF5EEFFu),
            ("SIENNA", 0xA0522DFFu),
            ("SILVER", 0xC0C0C0FFu),
            ("SKY_BLUE", 0x87CEEBFFu),
            ("SLATE_BLUE", 0x6A5ACDFFu),
            ("SLATE_GRAY", 0x708090FFu),
            ("SNOW", 0xFFFAFAFFu),
            ("SPRING_GREEN", 0x00FF7FFFu),
            ("STEEL_BLUE", 0x4682B4FFu),
            ("TAN", 0xD2B48CFFu),
            ("TEAL", 0x008080FFu),
            ("THISTLE", 0xD8BFD8FFu),
            ("TOMATO", 0xFF6347FFu),
            ("TRANSPARENT", 0xFFFFFF00u),
            ("TURQUOISE", 0x40E0D0FFu),
            ("VIOLET", 0xEE82EEFFu),
            ("WEB_GRAY", 0x808080FFu),
            ("WEB_GREEN", 0x008000FFu),
            ("WEB_MAROON", 0x800000FFu),
            ("WEB_PURPLE", 0x800080FFu),
            ("WHEAT", 0xF5DEB3FFu),
            ("WHITE", 0xFFFFFFFFu),
            ("WHITE_SMOKE", 0xF5F5F5FFu),
            ("YELLOW", 0xFFFF00FFu),
            ("YELLOW_GREEN", 0x9ACD32FFu)
        };

        static Dictionary<string, int> _namedIndex;

        /// <summary>Color.hex(0xRRGGBBAA).</summary>
        public static Col Hex(uint hex)
        {
            float a = (hex & 0xFF) / 255.0f;
            hex >>= 8;
            float b = (hex & 0xFF) / 255.0f;
            hex >>= 8;
            float g = (hex & 0xFF) / 255.0f;
            hex >>= 8;
            float r = (hex & 0xFF) / 255.0f;
            return new Col(r, g, b, a);
        }

        public static Col Hex(long hex) => Hex(unchecked((uint)hex));

        /// <summary>Color.hex64(0xRRRRGGGGBBBBAAAA).</summary>
        public static Col Hex64(long hex)
        {
            ulong p = unchecked((ulong)hex);
            float a = (p & 0xFFFF) / 65535.0f;
            p >>= 16;
            float b = (p & 0xFFFF) / 65535.0f;
            p >>= 16;
            float g = (p & 0xFFFF) / 65535.0f;
            p >>= 16;
            float r = (p & 0xFFFF) / 65535.0f;
            return new Col(r, g, b, a);
        }

        public static Col FromRgba8(long r8, long g8, long b8, long a8 = 255) => new Col(r8 / 255.0f, g8 / 255.0f, b8 / 255.0f, a8 / 255.0f);

        public static Col FromRgbe9995(long rgbe)
        {
            uint p = unchecked((uint)rgbe);
            float r = p & 0x1ff;
            float g = (p >> 9) & 0x1ff;
            float b = (p >> 18) & 0x1ff;
            float e = p >> 27;
            float m = MathF.Pow(2.0f, e - 15.0f - 9.0f);
            return new Col(r * m, g * m, b * m, 1.0f);
        }

        public uint ToRgbe9995()
        {
            const float kMaxVal = (float)(0x1FF << 7);
            const float kMinVal = 1.0f / (1 << 16);
            float _r = GD.ClampF(r, 0.0f, kMaxVal);
            float _g = GD.ClampF(g, 0.0f, kMaxVal);
            float _b = GD.ClampF(b, 0.0f, kMaxVal);
            float maxChannel = GD.MaxF(GD.MaxF(_r, _g), GD.MaxF(_b, kMinVal));
            uint ei = unchecked((uint)BitConverter.SingleToInt32Bits(maxChannel));
            ei += 0x07804000;
            ei &= 0x7F800000;
            float ef = BitConverter.Int32BitsToSingle(unchecked((int)ei));
            uint ri = unchecked((uint)BitConverter.SingleToInt32Bits(_r + ef));
            uint gi = unchecked((uint)BitConverter.SingleToInt32Bits(_g + ef));
            uint bi = unchecked((uint)BitConverter.SingleToInt32Bits(_b + ef));
            ei <<= 4;
            ei += 0x10000000;
            return ei | (bi << 18) | (gi << 9) | (ri & 511U);
        }

        /// <summary>Color.html(code) as Godot parses it ("#rgb", "#rgba", "#rrggbb", "#rrggbbaa"; else an error and
        /// Color()). The existing Html() falls back to a color name instead.</summary>
        public static Col HtmlExact(string rgba)
        {
            if (string.IsNullOrEmpty(rgba)) return new Col(0f, 0f, 0f, 1f);
            int cur = rgba[0] == '#' ? 1 : 0;
            int digits = rgba.Length - cur;
            float r, g, b, a = 1.0f;
            if (digits == 3)
            {
                r = Col4(rgba, cur) / 15.0f; g = Col4(rgba, cur + 1) / 15.0f; b = Col4(rgba, cur + 2) / 15.0f;
            }
            else if (digits == 4)
            {
                r = Col4(rgba, cur) / 15.0f; g = Col4(rgba, cur + 1) / 15.0f; b = Col4(rgba, cur + 2) / 15.0f; a = Col4(rgba, cur + 3) / 15.0f;
            }
            else if (digits == 6)
            {
                r = Col8(rgba, cur) / 255.0f; g = Col8(rgba, cur + 2) / 255.0f; b = Col8(rgba, cur + 4) / 255.0f;
            }
            else if (digits == 8)
            {
                r = Col8(rgba, cur) / 255.0f; g = Col8(rgba, cur + 2) / 255.0f; b = Col8(rgba, cur + 4) / 255.0f; a = Col8(rgba, cur + 6) / 255.0f;
            }
            else
            {
                GD.PushError("Invalid color code: " + rgba + ".");
                return new Col(0f, 0f, 0f, 1f);
            }
            if (r < 0.0f || g < 0.0f || b < 0.0f || a < 0.0f)
            {
                GD.PushError("Invalid color code: " + rgba + ".");
                return new Col(0f, 0f, 0f, 1f);
            }
            return new Col(r, g, b, a);
        }

        static int Col4(string s, int ofs)
        {
            char c = s[ofs];
            if (c >= '0' && c <= '9') return c - '0';
            if (c >= 'a' && c <= 'f') return c + (10 - 'a');
            if (c >= 'A' && c <= 'F') return c + (10 - 'A');
            return -1;
        }

        static int Col8(string s, int ofs) => Col4(s, ofs) * 16 + Col4(s, ofs + 1);

        static int FindNamed(string name)
        {
            if (_namedIndex == null)
            {
                var d = new Dictionary<string, int>();
                for (int i = 0; i < NamedTable.Length; i++) d[NamedTable[i].name.Replace("_", "")] = i;
                _namedIndex = d;
            }
            var sb = new System.Text.StringBuilder(name.Length);
            foreach (char c in name)
            {
                if (c == ' ' || c == '-' || c == '_' || c == '\'' || c == '.') continue;
                sb.Append(c);
            }
            return _namedIndex.TryGetValue(sb.ToString().ToUpperInvariant(), out int idx) ? idx : -1;
        }

        /// <summary>Color.named-style lookup with Godot's exact values and name normalization (spaces, '-', '_', '\'',
        /// '.' ignored, any case); an unknown name is an error and Color().</summary>
        public static Col NamedExact(string name)
        {
            int idx = FindNamed(name);
            if (idx < 0)
            {
                GD.PushError("Invalid color name: " + name + ".");
                return new Col(0f, 0f, 0f, 1f);
            }
            return Hex(NamedTable[idx].hex);
        }

        /// <summary>Color.from_string(str, default): an HTML code or a color name, else `default`.</summary>
        public static Col FromString(string str, Col dflt)
        {
            if (HtmlIsValid(str)) return HtmlExact(str);
            int idx = FindNamed(str);
            return idx < 0 ? dflt : Hex(NamedTable[idx].hex);
        }

        /// <summary>GDScript's Color(code): html if valid, else a color name (error and Color() if neither).</summary>
        public static Col FromCode(string code) => HtmlIsValid(code) ? HtmlExact(code) : NamedExact(code);

        public static int GetNamedColorCount() => NamedTable.Length;
        public static string GetNamedColorName(int i) => NamedTable[i].name;
        public static Col GetNamedColor(int i) => Hex(NamedTable[i].hex);

        // ------------------------------------------------------------------ packing
        static uint R8u(float v) => unchecked((uint)(byte)(int)MathF.Round(v * 255.0f, MidpointRounding.AwayFromZero));
        static ulong R16u(float v) => unchecked((ulong)(ushort)(int)MathF.Round(v * 65535.0f, MidpointRounding.AwayFromZero));

        /// <summary>to_rgba32 exactly as Godot ((uint8_t)round(c * 255): no clamp, .5 rounds away from zero).</summary>
        public uint ToRgba32Exact() => (R8u(r) << 24) | (R8u(g) << 16) | (R8u(b) << 8) | R8u(a);
        public uint ToArgb32() => (R8u(a) << 24) | (R8u(r) << 16) | (R8u(g) << 8) | R8u(b);
        public uint ToAbgr32() => (R8u(a) << 24) | (R8u(b) << 16) | (R8u(g) << 8) | R8u(r);
        public ulong ToRgba64() => (R16u(r) << 48) | (R16u(g) << 32) | (R16u(b) << 16) | R16u(a);
        public ulong ToArgb64() => (R16u(a) << 48) | (R16u(r) << 32) | (R16u(g) << 16) | R16u(b);
        public ulong ToAbgr64() => (R16u(a) << 48) | (R16u(b) << 32) | (R16u(g) << 16) | R16u(r);

        /// <summary>to_html exactly as Godot (round half away from zero in float, then clamp).</summary>
        public string ToHtmlExact(bool withAlpha = true)
        {
            string h(float v)
            {
                int i = (int)MathF.Round(v * 255.0f, MidpointRounding.AwayFromZero);
                i = GD.ClampInt(i, 0, 255);
                return i.ToString("x2");
            }
            return h(r) + h(g) + h(b) + (withAlpha ? h(a) : "");
        }

        static int Byte8(float v) => (int)GD.ClampF(MathF.Round(v * 255.0f, MidpointRounding.AwayFromZero), 0.0f, 255.0f);
        public int R8 { get => Byte8(r); set => r = GD.ClampInt(value, 0, 255) / 255.0f; }
        public int G8 { get => Byte8(g); set => g = GD.ClampInt(value, 0, 255) / 255.0f; }
        public int B8 { get => Byte8(b); set => b = GD.ClampInt(value, 0, 255) / 255.0f; }
        public int A8 { get => Byte8(a); set => a = GD.ClampInt(value, 0, 255) / 255.0f; }

        // ------------------------------------------------------------------ HSV / OKHSL
        /// <summary>Color::set_hsv exactly (fmod on the hue: a negative hue lands in the last sextant, as in Godot).</summary>
        public static Col FromHsvExact(double h, double s, double v, double alpha = 1.0)
        {
            float ph = (float)h, ps = (float)s, pv = (float)v, pa = (float)alpha;
            if (ps == 0.0f) return new Col(pv, pv, pv, pa);
            ph *= 6.0f;
            ph = ph % 6.0f;
            int i = (int)MathF.Floor(ph);
            float f = ph - i;
            float p = pv * (1.0f - ps);
            float q = pv * (1.0f - ps * f);
            float t = pv * (1.0f - ps * (1.0f - f));
            switch (i)
            {
                case 0: return new Col(pv, t, p, pa);
                case 1: return new Col(q, pv, p, pa);
                case 2: return new Col(p, pv, t, pa);
                case 3: return new Col(p, q, pv, pa);
                case 4: return new Col(t, p, pv, pa);
                default: return new Col(pv, p, q, pa);
            }
        }

        public Col WithHsv(double h, double s, double v) => FromHsvExact(h, s, v, a);

        public static Col FromOkHsl(double h, double s, double l, double alpha = 1.0)
        {
            OkColor.OkhslToSrgb((float)h, (float)s, (float)l, out float rr, out float gg, out float bb);
            return new Col(rr, gg, bb, (float)alpha).Clamp();
        }

        public float OkHslH { get { OkColor.SrgbToOkhsl(r, g, b, out float h, out _, out _); return float.IsNaN(h) ? 0.0f : GD.ClampF(h, 0.0f, 1.0f); } }
        public float OkHslS { get { OkColor.SrgbToOkhsl(r, g, b, out _, out float s, out _); return float.IsNaN(s) ? 0.0f : GD.ClampF(s, 0.0f, 1.0f); } }
        public float OkHslL { get { OkColor.SrgbToOkhsl(r, g, b, out _, out _, out float l); return float.IsNaN(l) ? 0.0f : GD.ClampF(l, 0.0f, 1.0f); } }

        // ------------------------------------------------------------------ math
        public float GetLuminance() => 0.2126f * r + 0.7152f * g + 0.0722f * b;

        public Col Clamp(Col min, Col max) =>
            new Col(GD.ClampF(r, min.r, max.r), GD.ClampF(g, min.g, max.g), GD.ClampF(b, min.b, max.b), GD.ClampF(a, min.a, max.a));

        /// <summary>is_equal_approx exactly as Godot (relative tolerance; the existing IsEqualApprox is absolute).</summary>
        public bool IsEqualApproxExact(Col c) => GD.IsEqualApproxF(r, c.r) && GD.IsEqualApproxF(g, c.g) && GD.IsEqualApproxF(b, c.b) && GD.IsEqualApproxF(a, c.a);

        public Col SrgbToLinear() => new Col(
            r < 0.04045f ? r * (1.0f / 12.92f) : MathF.Pow((float)((r + 0.055) * (1.0 / (1.0 + 0.055))), 2.4f),
            g < 0.04045f ? g * (1.0f / 12.92f) : MathF.Pow((float)((g + 0.055) * (1.0 / (1.0 + 0.055))), 2.4f),
            b < 0.04045f ? b * (1.0f / 12.92f) : MathF.Pow((float)((b + 0.055) * (1.0 / (1.0 + 0.055))), 2.4f),
            a);

        public Col LinearToSrgb() => new Col(
            r < 0.0031308f ? 12.92f * r : (float)((1.0 + 0.055) * MathF.Pow(r, 1.0f / 2.4f) - 0.055),
            g < 0.0031308f ? 12.92f * g : (float)((1.0 + 0.055) * MathF.Pow(g, 1.0f / 2.4f) - 0.055),
            b < 0.0031308f ? 12.92f * b : (float)((1.0 + 0.055) * MathF.Pow(b, 1.0f / 2.4f) - 0.055),
            a);

        public float this[int i]
        {
            get
            {
                switch (i) { case 0: return r; case 1: return g; case 2: return b; case 3: return a; }
                throw new IndexOutOfRangeException("Color index " + i);
            }
            set
            {
                switch (i) { case 0: r = value; return; case 1: g = value; return; case 2: b = value; return; case 3: a = value; return; }
                throw new IndexOutOfRangeException("Color index " + i);
            }
        }

        /// <summary>-color: (1 - r, 1 - g, 1 - b, 1 - a) (alpha too, unlike inverted()).</summary>
        public static Col operator -(Col c) => new Col(1.0f - c.r, 1.0f - c.g, 1.0f - c.b, 1.0f - c.a);
        public static Col operator +(Col c) => c;
        public static Col operator /(Col x, Col y) => new Col(x.r / y.r, x.g / y.g, x.b / y.b, x.a / y.a);
        public static Col operator *(double s, Col c) => c * s;
        public static bool operator <(Col x, Col y)
        {
            if (x.r == y.r)
            {
                if (x.g == y.g) return x.b == y.b ? x.a < y.a : x.b < y.b;
                return x.g < y.g;
            }
            return x.r < y.r;
        }
        public static bool operator >(Col x, Col y) => y < x;

        // ------------------------------------------------------------------ Variant
        public static implicit operator Var(Col c) => Var.Of(c);
        public static explicit operator Col(Var v) => v.Obj is Col c ? c : new Col(0f, 0f, 0f, 1f);
        public int GodotType => GD.TYPE_COLOR;
        public string GodotStr() => "(" + GFormat.Num(r, 4) + ", " + GFormat.Num(g, 4) + ", " + GFormat.Num(b, 4) + ", " + GFormat.Num(a, 4) + ")";
        public bool GodotIsZero => r == 0f && g == 0f && b == 0f && a == 1f;
        public uint GodotHash()
        {
            uint h = GHashing.MURMUR3_SEED;
            h = GHashing.Murmur3OneFloat(r, h);
            h = GHashing.Murmur3OneFloat(g, h);
            h = GHashing.Murmur3OneFloat(b, h);
            h = GHashing.Murmur3OneFloat(a, h);
            return GHashing.Fmix32(h);
        }
        public bool GodotOp(char op, Var other, bool selfLeft, out Var result)
        {
            result = Var.Nil;
            if (op == 'n') { result = -this; return true; }
            object o = other.Obj;
            if (o is Col c)
            {
                Col l = selfLeft ? this : c, rr = selfLeft ? c : this;
                switch (op)
                {
                    case '+': result = l + rr; return true;
                    case '-': result = l - rr; return true;
                    case '*': result = l * rr; return true;
                    case '/': result = l / rr; return true;
                }
                return false;
            }
            if (other.IsNum)
            {
                double s = other.IsInt ? (double)(float)other.AsLong() : other.AsFloat();
                if (op == '*') { result = this * s; return true; }
                if (op == '/' && selfLeft) { result = this / s; return true; }
            }
            return false;
        }
    }

    public partial struct Xform2 : IGodotValue
    {
        public static readonly Xform2 FLIP_X = new Xform2(new Vec2(-1f, 0f), new Vec2(0f, 1f), new Vec2(0f, 0f));
        public static readonly Xform2 FLIP_Y = new Xform2(new Vec2(1f, 0f), new Vec2(0f, -1f), new Vec2(0f, 0f));

        /// <summary>Transform2D(rotation, position) exactly as Godot (the angle narrowed to float, cosf/sinf).</summary>
        public static Xform2 FromRotation(double rotation, Vec2 position)
        {
            float rot = (float)rotation;
            float cr = MathF.Cos(rot), sr = MathF.Sin(rot);
            return new Xform2(new Vec2(cr, sr), new Vec2(-sr, cr), position);
        }

        /// <summary>Transform2D(rotation, scale, skew, position) exactly as Godot.</summary>
        public static Xform2 FromRotationScaleSkew(double rotation, Vec2 scale, double skew, Vec2 position)
        {
            float rot = (float)rotation, sk = (float)skew;
            Xform2 t;
            t.x = new Vec2(MathF.Cos(rot) * scale.x, MathF.Sin(rot) * scale.x);
            t.y = new Vec2(-MathF.Sin(rot + sk) * scale.y, MathF.Cos(rot + sk) * scale.y);
            t.origin = position;
            return t;
        }

        /// <summary>transform[i]: x, y, origin.</summary>
        public Vec2 this[int i]
        {
            get
            {
                switch (i) { case 0: return x; case 1: return y; case 2: return origin; }
                throw new IndexOutOfRangeException("Transform2D index " + i);
            }
            set
            {
                switch (i) { case 0: x = value; return; case 1: y = value; return; case 2: origin = value; return; }
                throw new IndexOutOfRangeException("Transform2D index " + i);
            }
        }

        public float Tdotx(Vec2 v) => x.x * v.x + y.x * v.y;
        public float Tdoty(Vec2 v) => x.y * v.x + y.y * v.y;
        public float Determinant() => x.x * y.y - x.y * y.x;
        public Vec2 BasisXformInv(Vec2 v) => new Vec2(x.Dot(v), y.Dot(v));

        /// <summary>Godot's xform_inv (`vector * transform`): the transposed basis applied to (v - origin) -- exact for
        /// orthonormal transforms. (The existing XformInv uses the affine inverse.)</summary>
        public Vec2 XformInvExact(Vec2 v)
        {
            Vec2 d = v - origin;
            return new Vec2(x.Dot(d), y.Dot(d));
        }

        /// <summary>transform * rect (Godot: the box around the transformed corners, built with expand_to).</summary>
        public Rect2 XformRectExact(Rect2 r)
        {
            Vec2 xa = x * r.size.x;
            Vec2 ya = y * r.size.y;
            Vec2 pos = Xform(r.position);
            Rect2 nr = new Rect2(pos, new Vec2(0f, 0f));
            nr = nr.ExpandToExact(pos + xa);
            nr = nr.ExpandToExact(pos + ya);
            nr = nr.ExpandToExact(pos + xa + ya);
            return nr;
        }

        /// <summary>rect * transform.</summary>
        public Rect2 XformInvRect(Rect2 r)
        {
            Vec2 e0 = XformInvExact(r.position);
            Vec2 e1 = XformInvExact(new Vec2(r.position.x, r.position.y + r.size.y));
            Vec2 e2 = XformInvExact(new Vec2(r.position.x + r.size.x, r.position.y + r.size.y));
            Vec2 e3 = XformInvExact(new Vec2(r.position.x + r.size.x, r.position.y));
            Rect2 nr = new Rect2(e0, new Vec2(0f, 0f));
            nr = nr.ExpandToExact(e1);
            nr = nr.ExpandToExact(e2);
            nr = nr.ExpandToExact(e3);
            return nr;
        }

        /// <summary>inverse(): assumes a rotation-only basis (transposes it).</summary>
        public Xform2 Inverse()
        {
            Xform2 t = this;
            float tmp = t.x.y;
            t.x.y = t.y.x;
            t.y.x = tmp;
            t.origin = t.BasisXform(-t.origin);
            return t;
        }

        /// <summary>affine_inverse exactly as Godot (a singular basis: with MathChecks an error and the transform
        /// unchanged, else infinities). The existing AffineInverse returns IDENTITY for a singular basis.</summary>
        public Xform2 AffineInverseExact()
        {
            float det = Determinant();
            if (GD.MathChecks && det == 0)
            {
                GD.PushError("Condition \"det == 0\" is true.");
                return this;
            }
            float idet = 1.0f / det;
            Xform2 t = this;
            float tmp = t.x.x;
            t.x.x = t.y.y;
            t.y.y = tmp;
            t.x = t.x * new Vec2(idet, -idet);
            t.y = t.y * new Vec2(-idet, idet);
            t.origin = t.BasisXform(-t.origin);
            return t;
        }

        /// <summary>get_rotation exactly as Godot (atan2f; the existing GetRotation uses the double atan2).</summary>
        public float GetRotationExact() => MathF.Atan2(x.y, x.x);

        Vec2 ScaleExact()
        {
            float detSign = GD.SignF(Determinant());
            return new Vec2(x.Length(), detSign * y.Length());
        }

        public float GetSkew()
        {
            float det = Determinant();
            return GD.AcosF(x.Normalized().Dot(y.Normalized() * GD.SignF(det))) - (float)GD.PI * 0.5f;
        }

        public Xform2 Orthonormalized()
        {
            Vec2 nx = x.Normalized();
            Vec2 ny = (y - nx * nx.Dot(y)).Normalized();
            return new Xform2(nx, ny, origin);
        }

        public Xform2 Untranslated() => new Xform2(x, y, new Vec2(0f, 0f));

        /// <summary>rotated(angle) exactly as Godot: Transform2D(angle, Vector2()) * this.</summary>
        public Xform2 RotatedExact(double angle) => FromRotation(angle, new Vec2(0f, 0f)) * this;
        /// <summary>rotated_local(angle) exactly as Godot: this * Transform2D(angle, Vector2()).</summary>
        public Xform2 RotatedLocalExact(double angle) => this * FromRotation(angle, new Vec2(0f, 0f));

        public bool IsConformal()
        {
            if (GD.IsEqualApproxF(x.x, y.y) && GD.IsEqualApproxF(x.y, -y.x)) return true;
            if (GD.IsEqualApproxF(x.x, -y.y) && GD.IsEqualApproxF(x.y, y.x)) return true;
            return false;
        }

        public bool IsEqualApprox(Xform2 t) => x.IsEqualApprox(t.x) && y.IsEqualApprox(t.y) && origin.IsEqualApprox(t.origin);
        public bool IsFinite() => x.IsFinite() && y.IsFinite() && origin.IsFinite();

        /// <summary>C++ set_rotation (keeps the scale).</summary>
        Xform2 WithRotation(float rot)
        {
            Vec2 scale = ScaleExact();
            float cr = MathF.Cos(rot), sr = MathF.Sin(rot);
            Xform2 t = this;
            t.x = new Vec2(cr, sr);
            t.y = new Vec2(-sr, cr);
            t.x = t.x.Normalized() * scale.x;
            t.y = t.y.Normalized() * scale.y;
            return t;
        }

        /// <summary>looking_at(target = Vector2()): rotated about the origin so +X points at target (scale kept, skew dropped).</summary>
        public Xform2 LookingAt(Vec2 target = default)
        {
            Xform2 ret = FromRotation(GetRotationExact(), origin);
            Vec2 targetPosition = AffineInverseExact().Xform(target);
            return ret.WithRotation(ret.GetRotationExact() + (targetPosition * ScaleExact()).Angle());
        }

        public Xform2 InterpolateWith(Xform2 xform, double weight)
        {
            float w = (float)weight;
            return FromRotationScaleSkew(
                GD.LerpAngleF(GetRotationExact(), xform.GetRotationExact(), w),
                ScaleExact().Lerp(xform.ScaleExact(), w),
                GD.LerpAngleF(GetSkew(), xform.GetSkew(), w),
                origin.Lerp(xform.origin, w));
        }

        public static Vec2 operator *(Xform2 t, Vec2 v) => t.Xform(v);
        public static Vec2 operator *(Vec2 v, Xform2 t) => t.XformInvExact(v);
        public static Rect2 operator *(Xform2 t, Rect2 r) => t.XformRectExact(r);
        public static Rect2 operator *(Rect2 r, Xform2 t) => t.XformInvRect(r);
        public static Xform2 operator *(Xform2 t, double s) { float f = (float)s; return new Xform2(t.x * f, t.y * f, t.origin * f); }
        public static Xform2 operator /(Xform2 t, double s) { float f = (float)s; return new Xform2(t.x / f, t.y / f, t.origin / f); }

        public override string ToString() => "[X: " + x + ", Y: " + y + ", O: " + origin + "]";

        // ------------------------------------------------------------------ Variant
        public static implicit operator Var(Xform2 t) => Var.Of(t);
        public static explicit operator Xform2(Var v) => v.Obj is Xform2 t ? t : IDENTITY;
        public int GodotType => GD.TYPE_TRANSFORM2D;
        public string GodotStr() => ToString();
        public bool GodotIsZero => this == IDENTITY;
        public uint GodotHash()
        {
            uint h = GHashing.MURMUR3_SEED;
            h = GHashing.Murmur3OneFloat(x.x, h);
            h = GHashing.Murmur3OneFloat(x.y, h);
            h = GHashing.Murmur3OneFloat(y.x, h);
            h = GHashing.Murmur3OneFloat(y.y, h);
            h = GHashing.Murmur3OneFloat(origin.x, h);
            h = GHashing.Murmur3OneFloat(origin.y, h);
            return GHashing.Fmix32(h);
        }
        public bool GodotOp(char op, Var other, bool selfLeft, out Var result)
        {
            result = Var.Nil;
            object o = other.Obj;
            if (op == '*')
            {
                if (o is Xform2 t) { result = selfLeft ? this * t : t * this; return true; }
                if (other.IsVec2) { result = selfLeft ? Xform(other.AsVec2()) : XformInvExact(other.AsVec2()); return true; }
                if (o is Rect2 r) { result = selfLeft ? XformRectExact(r) : XformInvRect(r); return true; }
                if (selfLeft && other.IsInt) { result = this * (double)(float)other.AsLong(); return true; }
                if (selfLeft && other.IsFloat) { result = this * other.AsFloat(); return true; }
            }
            else if (op == '/' && selfLeft)
            {
                if (other.IsInt) { result = this / (double)(float)other.AsLong(); return true; }
                if (other.IsFloat) { result = this / other.AsFloat(); return true; }
            }
            return false;
        }
    }

    /// <summary>Björn Ottosson's OKHSL conversions as Godot ships them (thirdparty/misc/ok_color.h), in float.</summary>
    static class OkColor
    {
        const float pi = 3.1415926535897932384626433832795028841971693993751058209749445923078164062f;

        // cbrtf: Godot's binary links a correctly rounded cbrtf (glibc 2.39's, which MathF.Cbrt calls, is 1 ulp off
        // for some inputs), so the cube root is taken in double and rounded once, as a correctly rounded cbrtf does.
        static float Cbrt(float x) => (float)Math.Cbrt(x);

        static float FMax(float a, float b) => float.IsNaN(a) ? b : (float.IsNaN(b) ? a : (a > b ? a : b));
        static float FMin(float a, float b) => float.IsNaN(a) ? b : (float.IsNaN(b) ? a : (a < b ? a : b));

        static float SrgbTransfer(float a) => .0031308f >= a ? 12.92f * a : 1.055f * MathF.Pow(a, .4166666666666667f) - .055f;
        static float SrgbTransferInv(float a) => .04045f < a ? MathF.Pow((a + .055f) / 1.055f, 2.4f) : a / 12.92f;

        static void LinearSrgbToOklab(float r, float g, float b, out float L, out float A, out float B)
        {
            float l = 0.4122214708f * r + 0.5363325363f * g + 0.0514459929f * b;
            float m = 0.2119034982f * r + 0.6806995451f * g + 0.1073969566f * b;
            float s = 0.0883024619f * r + 0.2817188376f * g + 0.6299787005f * b;
            float l_ = Cbrt(l), m_ = Cbrt(m), s_ = Cbrt(s);
            L = 0.2104542553f * l_ + 0.7936177850f * m_ - 0.0040720468f * s_;
            A = 1.9779984951f * l_ - 2.4285922050f * m_ + 0.4505937099f * s_;
            B = 0.0259040371f * l_ + 0.7827717662f * m_ - 0.8086757660f * s_;
        }

        static void OklabToLinearSrgb(float L, float A, float B, out float r, out float g, out float b)
        {
            float l_ = L + 0.3963377774f * A + 0.2158037573f * B;
            float m_ = L - 0.1055613458f * A - 0.0638541728f * B;
            float s_ = L - 0.0894841775f * A - 1.2914855480f * B;
            float l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_;
            r = +4.0767416621f * l - 3.3077115913f * m + 0.2309699292f * s;
            g = -1.2684380046f * l + 2.6097574011f * m - 0.3413193965f * s;
            b = -0.0041960863f * l - 0.7034186147f * m + 1.7076147010f * s;
        }

        static float ComputeMaxSaturation(float a, float b)
        {
            float k0, k1, k2, k3, k4, wl, wm, ws;
            if (-1.88170328f * a - 0.80936493f * b > 1)
            {
                k0 = +1.19086277f; k1 = +1.76576728f; k2 = +0.59662641f; k3 = +0.75515197f; k4 = +0.56771245f;
                wl = +4.0767416621f; wm = -3.3077115913f; ws = +0.2309699292f;
            }
            else if (1.81444104f * a - 1.19445276f * b > 1)
            {
                k0 = +0.73956515f; k1 = -0.45954404f; k2 = +0.08285427f; k3 = +0.12541070f; k4 = +0.14503204f;
                wl = -1.2684380046f; wm = +2.6097574011f; ws = -0.3413193965f;
            }
            else
            {
                k0 = +1.35733652f; k1 = -0.00915799f; k2 = -1.15130210f; k3 = -0.50559606f; k4 = +0.00692167f;
                wl = -0.0041960863f; wm = -0.7034186147f; ws = +1.7076147010f;
            }
            float S = k0 + k1 * a + k2 * b + k3 * a * a + k4 * a * b;
            float k_l = +0.3963377774f * a + 0.2158037573f * b;
            float k_m = -0.1055613458f * a - 0.0638541728f * b;
            float k_s = -0.0894841775f * a - 1.2914855480f * b;
            {
                float l_ = 1.0f + S * k_l, m_ = 1.0f + S * k_m, s_ = 1.0f + S * k_s;
                float l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_;
                float l_dS = 3.0f * k_l * l_ * l_, m_dS = 3.0f * k_m * m_ * m_, s_dS = 3.0f * k_s * s_ * s_;
                float l_dS2 = 6.0f * k_l * k_l * l_, m_dS2 = 6.0f * k_m * k_m * m_, s_dS2 = 6.0f * k_s * k_s * s_;
                float f = wl * l + wm * m + ws * s;
                float f1 = wl * l_dS + wm * m_dS + ws * s_dS;
                float f2 = wl * l_dS2 + wm * m_dS2 + ws * s_dS2;
                S = S - f * f1 / (f1 * f1 - 0.5f * f * f2);
            }
            return S;
        }

        static void FindCusp(float a, float b, out float cuspL, out float cuspC)
        {
            float sCusp = ComputeMaxSaturation(a, b);
            OklabToLinearSrgb(1, sCusp * a, sCusp * b, out float r, out float g, out float bb);
            cuspL = Cbrt(1.0f / FMax(FMax(r, g), bb));
            cuspC = cuspL * sCusp;
        }

        static float FindGamutIntersection(float a, float b, float L1, float C1, float L0, float cuspL, float cuspC)
        {
            float t;
            if (((L1 - L0) * cuspC - (cuspL - L0) * C1) <= 0.0f)
            {
                t = cuspC * L0 / (C1 * cuspL + cuspC * (L0 - L1));
            }
            else
            {
                t = cuspC * (L0 - 1.0f) / (C1 * (cuspL - 1.0f) + cuspC * (L0 - L1));
                {
                    float dL = L1 - L0;
                    float dC = C1;
                    float k_l = +0.3963377774f * a + 0.2158037573f * b;
                    float k_m = -0.1055613458f * a - 0.0638541728f * b;
                    float k_s = -0.0894841775f * a - 1.2914855480f * b;
                    float l_dt = dL + dC * k_l, m_dt = dL + dC * k_m, s_dt = dL + dC * k_s;
                    {
                        float L = L0 * (1.0f - t) + t * L1;
                        float C = t * C1;
                        float l_ = L + C * k_l, m_ = L + C * k_m, s_ = L + C * k_s;
                        float l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_;
                        float ldt = 3 * l_dt * l_ * l_, mdt = 3 * m_dt * m_ * m_, sdt = 3 * s_dt * s_ * s_;
                        float ldt2 = 6 * l_dt * l_dt * l_, mdt2 = 6 * m_dt * m_dt * m_, sdt2 = 6 * s_dt * s_dt * s_;
                        float r = 4.0767416621f * l - 3.3077115913f * m + 0.2309699292f * s - 1;
                        float r1 = 4.0767416621f * ldt - 3.3077115913f * mdt + 0.2309699292f * sdt;
                        float r2 = 4.0767416621f * ldt2 - 3.3077115913f * mdt2 + 0.2309699292f * sdt2;
                        float u_r = r1 / (r1 * r1 - 0.5f * r * r2);
                        float t_r = -r * u_r;
                        float g = -1.2684380046f * l + 2.6097574011f * m - 0.3413193965f * s - 1;
                        float g1 = -1.2684380046f * ldt + 2.6097574011f * mdt - 0.3413193965f * sdt;
                        float g2 = -1.2684380046f * ldt2 + 2.6097574011f * mdt2 - 0.3413193965f * sdt2;
                        float u_g = g1 / (g1 * g1 - 0.5f * g * g2);
                        float t_g = -g * u_g;
                        float bq = -0.0041960863f * l - 0.7034186147f * m + 1.7076147010f * s - 1;
                        float b1 = -0.0041960863f * ldt - 0.7034186147f * mdt + 1.7076147010f * sdt;
                        float b2 = -0.0041960863f * ldt2 - 0.7034186147f * mdt2 + 1.7076147010f * sdt2;
                        float u_b = b1 / (b1 * b1 - 0.5f * bq * b2);
                        float t_b = -bq * u_b;
                        t_r = u_r >= 0.0f ? t_r : float.MaxValue;
                        t_g = u_g >= 0.0f ? t_g : float.MaxValue;
                        t_b = u_b >= 0.0f ? t_b : float.MaxValue;
                        t += FMin(t_r, FMin(t_g, t_b));
                    }
                }
            }
            return t;
        }

        static float Toe(float x)
        {
            const float k_1 = 0.206f, k_2 = 0.03f;
            const float k_3 = (1.0f + k_1) / (1.0f + k_2);
            return 0.5f * (k_3 * x - k_1 + MathF.Sqrt((k_3 * x - k_1) * (k_3 * x - k_1) + 4 * k_2 * k_3 * x));
        }

        static float ToeInv(float x)
        {
            const float k_1 = 0.206f, k_2 = 0.03f;
            const float k_3 = (1.0f + k_1) / (1.0f + k_2);
            return (x * x + k_1 * x) / (k_3 * (x + k_2));
        }

        static void GetStMid(float a_, float b_, out float S, out float T)
        {
            S = 0.11516993f + 1.0f / (
                +7.44778970f + 4.15901240f * b_
                + a_ * (-2.19557347f + 1.75198401f * b_
                    + a_ * (-2.13704948f - 10.02301043f * b_
                        + a_ * (-4.24894561f + 5.38770819f * b_ + 4.69891013f * a_))));
            T = 0.11239642f + 1.0f / (
                +1.61320320f - 0.68124379f * b_
                + a_ * (+0.40370612f + 0.90148123f * b_
                    + a_ * (-0.27087943f + 0.61223990f * b_
                        + a_ * (+0.00299215f - 0.45399568f * b_ - 0.14661872f * a_))));
        }

        static void GetCs(float L, float a_, float b_, out float C_0, out float C_mid, out float C_max)
        {
            FindCusp(a_, b_, out float cuspL, out float cuspC);
            C_max = FindGamutIntersection(a_, b_, L, 1, L, cuspL, cuspC);
            float stS = cuspC / cuspL, stT = cuspC / (1 - cuspL);
            float k = C_max / FMin((L * stS), (1 - L) * stT);
            {
                GetStMid(a_, b_, out float midS, out float midT);
                float C_a = L * midS;
                float C_b = (1.0f - L) * midT;
                C_mid = 0.9f * k * MathF.Sqrt(MathF.Sqrt(1.0f / (1.0f / (C_a * C_a * C_a * C_a) + 1.0f / (C_b * C_b * C_b * C_b))));
            }
            {
                float C_a = L * 0.4f;
                float C_b = (1.0f - L) * 0.8f;
                C_0 = MathF.Sqrt(1.0f / (1.0f / (C_a * C_a) + 1.0f / (C_b * C_b)));
            }
        }

        public static void OkhslToSrgb(float h, float s, float l, out float r, out float g, out float b)
        {
            if (l == 1.0f) { r = g = b = 1.0f; return; }
            if (l == 0.0f) { r = g = b = 0.0f; return; }
            float a_ = MathF.Cos(2.0f * pi * h);
            float b_ = MathF.Sin(2.0f * pi * h);
            float L = ToeInv(l);
            GetCs(L, a_, b_, out float C_0, out float C_mid, out float C_max);
            const float mid = 0.8f, mid_inv = 1.25f;
            float C, t, k_0, k_1, k_2;
            if (s < mid)
            {
                t = mid_inv * s;
                k_1 = mid * C_0;
                k_2 = (1.0f - k_1 / C_mid);
                C = t * k_1 / (1.0f - k_2 * t);
            }
            else
            {
                t = (s - mid) / (1 - mid);
                k_0 = C_mid;
                k_1 = (1.0f - mid) * C_mid * C_mid * mid_inv * mid_inv / C_0;
                k_2 = (1.0f - (k_1) / (C_max - C_mid));
                C = k_0 + t * k_1 / (1.0f - k_2 * t);
            }
            OklabToLinearSrgb(L, C * a_, C * b_, out float lr, out float lg, out float lb);
            r = SrgbTransfer(lr);
            g = SrgbTransfer(lg);
            b = SrgbTransfer(lb);
        }

        public static void SrgbToOkhsl(float r, float g, float b, out float h, out float s, out float l)
        {
            if (r == 0.0f && g == 0.0f && b == 0.0f) { h = s = l = 0.0f; return; }
            LinearSrgbToOklab(SrgbTransferInv(r), SrgbTransferInv(g), SrgbTransferInv(b), out float labL, out float labA, out float labB);
            float C = MathF.Sqrt(labA * labA + labB * labB);
            float a_ = labA / C;
            float b_ = labB / C;
            float L = labL;
            h = 0.5f + 0.5f * MathF.Atan2(-labB, -labA) / pi;
            GetCs(L, a_, b_, out float C_0, out float C_mid, out float C_max);
            const float mid = 0.8f, mid_inv = 1.25f;
            if (C < C_mid)
            {
                float k_1 = mid * C_0;
                float k_2 = (1.0f - k_1 / C_mid);
                float t = C / (k_1 + k_2 * C);
                s = t * mid;
            }
            else
            {
                float k_0 = C_mid;
                float k_1 = (1.0f - mid) * C_mid * C_mid * mid_inv * mid_inv / C_0;
                float k_2 = (1.0f - (k_1) / (C_max - C_mid));
                float t = (C - k_0) / (k_1 + k_2 * (C - k_0));
                s = mid + (1.0f - mid) * t;
            }
            l = Toe(L);
        }
    }
}
