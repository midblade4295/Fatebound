// Fatebound GUI (Unity port): Godot's 2D value types for the UI layer -- Rect2, Col (Color), Xform2 (Transform2D).
// float components and Godot's formulas, so ported layout and drawing code computes the same numbers.
using System;
using System.Globalization;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public partial struct Rect2 : IEquatable<Rect2>
    {
        public Vec2 position, size;

        public Rect2(Vec2 position, Vec2 size) { this.position = position; this.size = size; }
        public Rect2(double x, double y, double w, double h) { position = new Vec2(x, y); size = new Vec2(w, h); }

        public Vec2 End { get => position + size; set => size = value - position; }
        public float X => position.x;
        public float Y => position.y;
        public float Width => size.x;
        public float Height => size.y;
        public Vec2 GetCenter() => position + size * 0.5;
        public float GetArea() => size.x * size.y;

        public bool HasPoint(Vec2 p) =>
            p.x >= position.x && p.y >= position.y && p.x < position.x + size.x && p.y < position.y + size.y;

        public Rect2 Abs() => new Rect2(new Vec2(position.x + Math.Min(size.x, 0f), position.y + Math.Min(size.y, 0f)), size.Abs());

        public Rect2 Grow(double by)
        {
            float b = (float)by;
            return new Rect2(new Vec2(position.x - b, position.y - b), new Vec2(size.x + b * 2, size.y + b * 2));
        }

        public Rect2 GrowIndividual(double left, double top, double right, double bottom)
        {
            var g = this;
            g.position = new Vec2(g.position.x - (float)left, g.position.y - (float)top);
            g.size = new Vec2(g.size.x + (float)left + (float)right, g.size.y + (float)top + (float)bottom);
            return g;
        }

        public Rect2 GrowSide(int side, double amount)
        {
            float a = (float)amount;
            return GrowIndividual(side == 0 ? a : 0, side == 1 ? a : 0, side == 2 ? a : 0, side == 3 ? a : 0);
        }

        public Rect2 Merge(Rect2 r)
        {
            var n = new Rect2();
            n.position = new Vec2(Math.Min(r.position.x, position.x), Math.Min(r.position.y, position.y));
            Vec2 e = new Vec2(Math.Max(r.position.x + r.size.x, position.x + size.x), Math.Max(r.position.y + r.size.y, position.y + size.y));
            n.size = e - n.position;
            return n;
        }

        public bool Intersects(Rect2 r, bool includeBorders = false)
        {
            if (includeBorders)
                return !(position.x > r.position.x + r.size.x || position.x + size.x < r.position.x
                    || position.y > r.position.y + r.size.y || position.y + size.y < r.position.y);
            return !(position.x >= r.position.x + r.size.x || position.x + size.x <= r.position.x
                || position.y >= r.position.y + r.size.y || position.y + size.y <= r.position.y);
        }

        public Rect2 Intersection(Rect2 r)
        {
            if (!Intersects(r)) return new Rect2();
            Vec2 p = new Vec2(Math.Max(r.position.x, position.x), Math.Max(r.position.y, position.y));
            Vec2 e = new Vec2(Math.Min(r.position.x + r.size.x, position.x + size.x), Math.Min(r.position.y + r.size.y, position.y + size.y));
            return new Rect2(p, e - p);
        }

        public bool Encloses(Rect2 r) =>
            r.position.x >= position.x && r.position.y >= position.y
            && r.position.x + r.size.x <= position.x + size.x && r.position.y + r.size.y <= position.y + size.y;

        public Rect2 Expand(Vec2 to)
        {
            Vec2 b = position, e = position + size;
            b = new Vec2(Math.Min(b.x, to.x), Math.Min(b.y, to.y));
            e = new Vec2(Math.Max(e.x, to.x), Math.Max(e.y, to.y));
            return new Rect2(b, e - b);
        }

        public static bool operator ==(Rect2 a, Rect2 b) => a.position == b.position && a.size == b.size;
        public static bool operator !=(Rect2 a, Rect2 b) => !(a == b);
        public bool Equals(Rect2 o) => this == o;
        public override bool Equals(object o) => o is Rect2 r && this == r;
        public override int GetHashCode() => position.GetHashCode() * 31 + size.GetHashCode();
        public override string ToString() => "[P: " + position + ", S: " + size + "]";
    }

    /// <summary>Godot's Color (float RGBA). Named Col so it never clashes with UnityEngine.Color.</summary>
    public partial struct Col : IEquatable<Col>
    {
        public float r, g, b, a;

        public Col(float r, float g, float b, float a = 1f) { this.r = r; this.g = g; this.b = b; this.a = a; }
        public Col(double r, double g, double b, double a = 1.0) { this.r = (float)r; this.g = (float)g; this.b = (float)b; this.a = (float)a; }
        /// <summary>Color(c, alpha).</summary>
        public Col(Col c, double alpha) { r = c.r; g = c.g; b = c.b; a = (float)alpha; }
        /// <summary>Color("#rrggbb") / Color("#rrggbbaa") / "#rgb" / named.</summary>
        public Col(string html) { this = Html(html); }
        public Col(string html, double alpha) { this = Html(html); a = (float)alpha; }

        public static readonly Col WHITE = new Col(1f, 1f, 1f, 1f);
        public static readonly Col BLACK = new Col(0f, 0f, 0f, 1f);
        public static readonly Col TRANSPARENT = new Col(1f, 1f, 1f, 0f);
        public static readonly Col RED = new Col(1f, 0f, 0f, 1f);
        public static readonly Col GREEN = new Col(0f, 1f, 0f, 1f);
        public static readonly Col BLUE = new Col(0f, 0f, 1f, 1f);
        public static readonly Col YELLOW = new Col(1f, 1f, 0f, 1f);
        public static readonly Col ORANGE = new Col(1f, 0.647059f, 0f, 1f);
        public static readonly Col GOLD = new Col(1f, 0.843137f, 0f, 1f);
        public static readonly Col GRAY = new Col(0.745098f, 0.745098f, 0.745098f, 1f);
        public static readonly Col DIM_GRAY = new Col(0.411765f, 0.411765f, 0.411765f, 1f);
        public static readonly Col CYAN = new Col(0f, 1f, 1f, 1f);
        public static readonly Col MAGENTA = new Col(1f, 0f, 1f, 1f);
        public static readonly Col PURPLE = new Col(0.627451f, 0.12549f, 0.941176f, 1f);
        public static readonly Col LIME_GREEN = new Col(0.196078f, 0.803922f, 0.196078f, 1f);
        public static readonly Col SKY_BLUE = new Col(0.529412f, 0.807843f, 0.921569f, 1f);
        public static readonly Col ORANGE_RED = new Col(1f, 0.270588f, 0f, 1f);
        public static readonly Col CRIMSON = new Col(0.862745f, 0.0784314f, 0.235294f, 1f);
        public static readonly Col DARK_RED = new Col(0.545098f, 0f, 0f, 1f);
        public static readonly Col SILVER = new Col(0.752941f, 0.752941f, 0.752941f, 1f);
        public static readonly Col LIGHT_GRAY = new Col(0.827451f, 0.827451f, 0.827451f, 1f);
        public static readonly Col WHEAT = new Col(0.960784f, 0.870588f, 0.701961f, 1f);
        public static readonly Col INDIAN_RED = new Col(0.803922f, 0.360784f, 0.360784f, 1f);
        public static readonly Col TOMATO = new Col(1f, 0.388235f, 0.278431f, 1f);
        public static readonly Col DEEP_SKY_BLUE = new Col(0f, 0.74902f, 1f, 1f);
        public static readonly Col SPRING_GREEN = new Col(0f, 1f, 0.498039f, 1f);
        public static readonly Col GOLDENROD = new Col(0.854902f, 0.647059f, 0.12549f, 1f);
        public static readonly Col SADDLE_BROWN = new Col(0.545098f, 0.270588f, 0.0745098f, 1f);
        public static readonly Col CORAL = new Col(1f, 0.498039f, 0.313726f, 1f);
        public static readonly Col PINK = new Col(1f, 0.752941f, 0.796078f, 1f);
        public static readonly Col VIOLET = new Col(0.933333f, 0.509804f, 0.933333f, 1f);
        public static readonly Col AQUA = new Col(0f, 1f, 1f, 1f);
        public static readonly Col NAVY_BLUE = new Col(0f, 0f, 0.501961f, 1f);
        public static readonly Col FOREST_GREEN = new Col(0.133333f, 0.545098f, 0.133333f, 1f);
        public static readonly Col LIGHT_GREEN = new Col(0.564706f, 0.933333f, 0.564706f, 1f);
        public static readonly Col LIGHT_BLUE = new Col(0.678431f, 0.847059f, 0.901961f, 1f);
        public static readonly Col LIGHT_CORAL = new Col(0.941176f, 0.501961f, 0.501961f, 1f);
        public static readonly Col LIGHT_YELLOW = new Col(1f, 1f, 0.878431f, 1f);
        public static readonly Col LIGHT_SKY_BLUE = new Col(0.529412f, 0.807843f, 0.980392f, 1f);
        public static readonly Col LIGHT_SALMON = new Col(1f, 0.627451f, 0.478431f, 1f);
        public static readonly Col STEEL_BLUE = new Col(0.27451f, 0.509804f, 0.705882f, 1f);
        public static readonly Col DARK_GRAY = new Col(0.662745f, 0.662745f, 0.662745f, 1f);
        public static readonly Col DARK_ORANGE = new Col(1f, 0.54902f, 0f, 1f);
        public static readonly Col DARK_GREEN = new Col(0f, 0.392157f, 0f, 1f);
        public static readonly Col DARK_SLATE_GRAY = new Col(0.184314f, 0.309804f, 0.309804f, 1f);
        public static readonly Col MIDNIGHT_BLUE = new Col(0.0980392f, 0.0980392f, 0.439216f, 1f);
        public static readonly Col WEB_GRAY = new Col(0.501961f, 0.501961f, 0.501961f, 1f);
        public static readonly Col BROWN = new Col(0.647059f, 0.164706f, 0.164706f, 1f);
        public static readonly Col SALMON = new Col(0.980392f, 0.501961f, 0.447059f, 1f);
        public static readonly Col TURQUOISE = new Col(0.25098f, 0.878431f, 0.815686f, 1f);
        public static readonly Col KHAKI = new Col(0.941176f, 0.901961f, 0.54902f, 1f);
        public static readonly Col LAVENDER = new Col(0.901961f, 0.901961f, 0.980392f, 1f);
        public static readonly Col BEIGE = new Col(0.960784f, 0.960784f, 0.862745f, 1f);
        public static readonly Col IVORY = new Col(1f, 1f, 0.941176f, 1f);
        public static readonly Col SNOW = new Col(1f, 0.980392f, 0.980392f, 1f);
        public static readonly Col FIREBRICK = new Col(0.698039f, 0.133333f, 0.133333f, 1f);
        public static readonly Col CHARTREUSE = new Col(0.498039f, 1f, 0f, 1f);
        public static readonly Col HOT_PINK = new Col(1f, 0.411765f, 0.705882f, 1f);
        public static readonly Col ROYAL_BLUE = new Col(0.254902f, 0.411765f, 0.882353f, 1f);
        public static readonly Col DODGER_BLUE = new Col(0.117647f, 0.564706f, 1f, 1f);
        public static readonly Col SEA_GREEN = new Col(0.180392f, 0.545098f, 0.341176f, 1f);
        public static readonly Col TEAL = new Col(0f, 0.501961f, 0.501961f, 1f);
        public static readonly Col OLIVE = new Col(0.501961f, 0.501961f, 0f, 1f);
        public static readonly Col MAROON = new Col(0.690196f, 0.188235f, 0.376471f, 1f);
        public static readonly Col TAN = new Col(0.823529f, 0.705882f, 0.54902f, 1f);
        public static readonly Col PALE_GREEN = new Col(0.596078f, 0.984314f, 0.596078f, 1f);
        public static readonly Col PALE_TURQUOISE = new Col(0.686275f, 0.933333f, 0.933333f, 1f);
        public static readonly Col MEDIUM_PURPLE = new Col(0.576471f, 0.439216f, 0.858824f, 1f);
        public static readonly Col LAWN_GREEN = new Col(0.486275f, 0.988235f, 0f, 1f);
        public static readonly Col YELLOW_GREEN = new Col(0.603922f, 0.803922f, 0.196078f, 1f);

        static int Hex(char c)
        {
            if (c >= '0' && c <= '9') return c - '0';
            if (c >= 'a' && c <= 'f') return c - 'a' + 10;
            if (c >= 'A' && c <= 'F') return c - 'A' + 10;
            return -1;
        }

        static float H2(string s, int i) => (Hex(s[i]) * 16 + Hex(s[i + 1])) / 255f;
        static float H1(string s, int i) => (Hex(s[i]) * 17) / 255f;

        public static Col Html(string s)
        {
            if (string.IsNullOrEmpty(s)) return BLACK;
            string c = s.StartsWith("#") ? s.Substring(1) : s;
            if (c.Length == 6 && AllHex(c)) return new Col(H2(c, 0), H2(c, 2), H2(c, 4), 1f);
            if (c.Length == 8 && AllHex(c)) return new Col(H2(c, 0), H2(c, 2), H2(c, 4), H2(c, 6));
            if (c.Length == 3 && AllHex(c)) return new Col(H1(c, 0), H1(c, 1), H1(c, 2), 1f);
            if (c.Length == 4 && AllHex(c)) return new Col(H1(c, 0), H1(c, 1), H1(c, 2), H1(c, 3));
            return Named(s);
        }

        static bool AllHex(string c)
        {
            foreach (var ch in c) if (Hex(ch) < 0) return false;
            return true;
        }

        public static Col Named(string name)
        {
            string n = name.Trim().ToUpperInvariant().Replace(" ", "_");
            var f = typeof(Col).GetField(n, System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static);
            if (f != null && f.FieldType == typeof(Col)) return (Col)f.GetValue(null);
            return BLACK;
        }

        public static bool HtmlIsValid(string s)
        {
            if (string.IsNullOrEmpty(s)) return false;
            string c = s.StartsWith("#") ? s.Substring(1) : s;
            return (c.Length == 3 || c.Length == 4 || c.Length == 6 || c.Length == 8) && AllHex(c);
        }

        public string ToHtml(bool withAlpha = true)
        {
            string h(float v) => ((int)Math.Round(Math.Max(0, Math.Min(1, v)) * 255)).ToString("x2");
            return h(r) + h(g) + h(b) + (withAlpha ? h(a) : "");
        }

        public float H
        {
            get
            {
                float min = Math.Min(Math.Min(r, g), b), max = Math.Max(Math.Max(r, g), b);
                float delta = max - min;
                if (delta == 0) return 0;
                float h;
                if (r == max) h = (g - b) / delta;
                else if (g == max) h = 2 + (b - r) / delta;
                else h = 4 + (r - g) / delta;
                h /= 6.0f;
                if (h < 0) h += 1.0f;
                return h;
            }
        }

        public float S
        {
            get
            {
                float min = Math.Min(Math.Min(r, g), b), max = Math.Max(Math.Max(r, g), b);
                float delta = max - min;
                return max != 0 ? delta / max : 0;
            }
        }

        public float V => Math.Max(Math.Max(r, g), b);
        public float Luminance => 0.2126f * r + 0.7152f * g + 0.0722f * b;

        public static Col FromHsv(double h, double s, double v, double alpha = 1.0)
        {
            int i;
            float f, p, q, t;
            float hh = (float)h, ss = (float)s, vv = (float)v;
            if (ss == 0.0f) return new Col(vv, vv, vv, (float)alpha);
            hh *= 6.0f;
            hh = (float)(hh - Math.Floor(hh / 6.0f) * 6.0f);
            i = (int)Math.Floor(hh);
            f = hh - i;
            p = vv * (1.0f - ss);
            q = vv * (1.0f - ss * f);
            t = vv * (1.0f - ss * (1.0f - f));
            switch (i)
            {
                case 0: return new Col(vv, t, p, (float)alpha);
                case 1: return new Col(q, vv, p, (float)alpha);
                case 2: return new Col(p, vv, t, (float)alpha);
                case 3: return new Col(p, q, vv, (float)alpha);
                case 4: return new Col(t, p, vv, (float)alpha);
                default: return new Col(vv, p, q, (float)alpha);
            }
        }

        public Col Lightened(double amount)
        {
            float k = (float)amount;
            return new Col(r + (1.0f - r) * k, g + (1.0f - g) * k, b + (1.0f - b) * k, a);
        }

        public Col Darkened(double amount)
        {
            float k = (float)amount;
            return new Col(r * (1.0f - k), g * (1.0f - k), b * (1.0f - k), a);
        }

        public Col Inverted() => new Col(1f - r, 1f - g, 1f - b, a);

        public Col Lerp(Col to, double weight)
        {
            float w = (float)weight;
            return new Col(r + w * (to.r - r), g + w * (to.g - g), b + w * (to.b - b), a + w * (to.a - a));
        }

        /// <summary>Color.blend(over): alpha-composites `over` on top of this.</summary>
        public Col Blend(Col over)
        {
            float sa = 1.0f - over.a;
            float na = a * sa + over.a;
            if (na == 0) return new Col(0, 0, 0, 0);
            return new Col((r * a * sa + over.r * over.a) / na, (g * a * sa + over.g * over.a) / na, (b * a * sa + over.b * over.a) / na, na);
        }

        public Col Clamp() => new Col(Clamp01(r), Clamp01(g), Clamp01(b), Clamp01(a));
        static float Clamp01(float v) => v < 0 ? 0 : (v > 1 ? 1 : v);

        public Col WithAlpha(double alpha) => new Col(r, g, b, (float)alpha);
        public bool IsEqualApprox(Col o) => Math.Abs(r - o.r) < 1e-5f && Math.Abs(g - o.g) < 1e-5f && Math.Abs(b - o.b) < 1e-5f && Math.Abs(a - o.a) < 1e-5f;

        public uint ToRgba32()
        {
            uint c(float v) => (uint)Math.Round(Clamp01(v) * 255f);
            return (c(r) << 24) | (c(g) << 16) | (c(b) << 8) | c(a);
        }

        public static Col operator *(Col x, Col y) => new Col(x.r * y.r, x.g * y.g, x.b * y.b, x.a * y.a);
        public static Col operator *(Col x, double s) { float f = (float)s; return new Col(x.r * f, x.g * f, x.b * f, x.a * f); }
        public static Col operator /(Col x, double s) { float f = (float)s; return new Col(x.r / f, x.g / f, x.b / f, x.a / f); }
        public static Col operator +(Col x, Col y) => new Col(x.r + y.r, x.g + y.g, x.b + y.b, x.a + y.a);
        public static Col operator -(Col x, Col y) => new Col(x.r - y.r, x.g - y.g, x.b - y.b, x.a - y.a);
        public static bool operator ==(Col x, Col y) => x.r == y.r && x.g == y.g && x.b == y.b && x.a == y.a;
        public static bool operator !=(Col x, Col y) => !(x == y);
        public bool Equals(Col o) => this == o;
        public override bool Equals(object o) => o is Col c && this == c;
        public override int GetHashCode() => (r, g, b, a).GetHashCode();
        public override string ToString() => string.Format(CultureInfo.InvariantCulture, "({0}, {1}, {2}, {3})", r, g, b, a);
    }

    /// <summary>Godot's Transform2D: columns x, y (the basis) and origin.</summary>
    public partial struct Xform2 : IEquatable<Xform2>
    {
        public Vec2 x, y, origin;

        public static readonly Xform2 IDENTITY = new Xform2(new Vec2(1f, 0f), new Vec2(0f, 1f), Vec2.Zero);

        public Xform2(Vec2 x, Vec2 y, Vec2 origin) { this.x = x; this.y = y; this.origin = origin; }

        public Xform2(double rot, Vec2 pos)
        {
            float cr = (float)Math.Cos(rot), sr = (float)Math.Sin(rot);
            x = new Vec2(cr, sr);
            y = new Vec2(-sr, cr);
            origin = pos;
        }

        /// <summary>Transform2D(rotation, scale, skew, position).</summary>
        public Xform2(double rot, Vec2 scale, double skew, Vec2 pos)
        {
            float r = (float)rot, k = (float)skew;
            x = new Vec2((float)Math.Cos(r) * scale.x, (float)Math.Sin(r) * scale.x);
            y = new Vec2(-(float)Math.Sin(r + k) * scale.y, (float)Math.Cos(r + k) * scale.y);
            origin = pos;
        }

        public Vec2 Xform(Vec2 v) => new Vec2(x.x * v.x + y.x * v.y + origin.x, x.y * v.x + y.y * v.y + origin.y);
        public Vec2 BasisXform(Vec2 v) => new Vec2(x.x * v.x + y.x * v.y, x.y * v.x + y.y * v.y);
        public float BasisDeterminant() => x.x * y.y - x.y * y.x;

        public Xform2 AffineInverse()
        {
            float det = BasisDeterminant();
            if (det == 0) return IDENTITY;
            float idet = 1.0f / det;
            var inv = new Xform2(new Vec2(y.y * idet, -x.y * idet), new Vec2(-y.x * idet, x.x * idet), Vec2.Zero);
            inv.origin = inv.BasisXform(-origin);
            return inv;
        }

        public Vec2 XformInv(Vec2 v) => AffineInverse().Xform(v);

        public static Xform2 operator *(Xform2 a, Xform2 b)
        {
            return new Xform2(a.BasisXform(b.x), a.BasisXform(b.y), a.Xform(b.origin));
        }

        public Vec2 GetScale()
        {
            float detSign = Math.Sign(BasisDeterminant());
            return new Vec2(x.Length(), detSign * y.Length());
        }

        public float GetRotation() => (float)Math.Atan2(x.y, x.x);
        public Vec2 GetOrigin() => origin;

        public Xform2 Translated(Vec2 offset) { var t = this; t.origin = t.origin + offset; return t; }
        public Xform2 TranslatedLocal(Vec2 offset) { var t = this; t.origin = t.origin + BasisXform(offset); return t; }
        public Xform2 Scaled(Vec2 s) => new Xform2(new Vec2(x.x * s.x, x.y * s.y), new Vec2(y.x * s.x, y.y * s.y), new Vec2(origin.x * s.x, origin.y * s.y));
        public Xform2 ScaledLocal(Vec2 s) => new Xform2(x * s.x, y * s.y, origin);
        public Xform2 Rotated(double ang) => new Xform2(ang, Vec2.Zero) * this;
        public Xform2 RotatedLocal(double ang) => this * new Xform2(ang, Vec2.Zero);

        /// <summary>Axis-aligned (no rotation/skew): clip rects can be transformed exactly.</summary>
        public bool IsAxisAligned => Math.Abs(x.y) < 1e-6f && Math.Abs(y.x) < 1e-6f;

        public Rect2 XformRect(Rect2 r)
        {
            Vec2 p0 = Xform(r.position);
            Vec2 p1 = Xform(new Vec2(r.position.x + r.size.x, r.position.y));
            Vec2 p2 = Xform(new Vec2(r.position.x, r.position.y + r.size.y));
            Vec2 p3 = Xform(r.position + r.size);
            var o = new Rect2(p0, Vec2.Zero);
            o = o.Expand(p1); o = o.Expand(p2); o = o.Expand(p3);
            return o;
        }

        public static bool operator ==(Xform2 a, Xform2 b) => a.x == b.x && a.y == b.y && a.origin == b.origin;
        public static bool operator !=(Xform2 a, Xform2 b) => !(a == b);
        public bool Equals(Xform2 o) => this == o;
        public override bool Equals(object o) => o is Xform2 t && this == t;
        public override int GetHashCode() => (x, y, origin).GetHashCode();
    }

    public enum Side { Left = 0, Top = 1, Right = 2, Bottom = 3 }
    public enum Corner { TopLeft = 0, TopRight = 1, BottomRight = 2, BottomLeft = 3 }
    public enum HorizontalAlignment { Left = 0, Center = 1, Right = 2, Fill = 3 }
    public enum VerticalAlignment { Top = 0, Center = 1, Bottom = 2, Fill = 3 }
}
