// Fatebound (Unity port): the Godot math the Siege simulation was written against, reproduced so the C# sim plays the
// same match as the GDScript one from the same seed (simtest/ compares them tick by tick).
//  - Vec2: Godot's Vector2 with real_t = float (32-bit components); every operation in float, as Godot does. A double
//    (GDScript's float) meeting a Vec2 is narrowed to float first, as the engine's Variant operators do.
//  - Scalars: GDScript's float is a double; the helpers below are Godot's Math:: functions on doubles.
//  - Rng: Godot's RandomNumberGenerator (PCG32, its seeding, randf/randf_range/randi_range).
//  - GHash: String::hash (djb2, additive), what GDScript's hash() gives for a String.
// No UnityEngine here: the sim is plain C# shared by the client, the server and the tests.
using System;

namespace Fatebound.Sim
{
    public partial struct Vec2 : IEquatable<Vec2>
    {
        public float x, y;
        public Vec2(float x, float y) { this.x = x; this.y = y; }
        public Vec2(double x, double y) { this.x = (float)x; this.y = (float)y; }

        public static readonly Vec2 Zero = new Vec2(0f, 0f);
        public static readonly Vec2 Inf = new Vec2(float.PositiveInfinity, float.PositiveInfinity);
        public static readonly Vec2 Up = new Vec2(0f, -1f);
        public static readonly Vec2 Down = new Vec2(0f, 1f);
        public static readonly Vec2 Left = new Vec2(-1f, 0f);
        public static readonly Vec2 Right = new Vec2(1f, 0f);
        public static readonly Vec2 One = new Vec2(1f, 1f);

        public static Vec2 operator +(Vec2 a, Vec2 b) => new Vec2(a.x + b.x, a.y + b.y);
        public static Vec2 operator -(Vec2 a, Vec2 b) => new Vec2(a.x - b.x, a.y - b.y);
        public static Vec2 operator -(Vec2 a) => new Vec2(-a.x, -a.y);
        public static Vec2 operator *(Vec2 a, Vec2 b) => new Vec2(a.x * b.x, a.y * b.y);
        public static Vec2 operator /(Vec2 a, Vec2 b) => new Vec2(a.x / b.x, a.y / b.y);
        // (GDScript: Vector2 * float -> the float narrowed to real_t, then each component)
        public static Vec2 operator *(Vec2 a, double s) { float f = (float)s; return new Vec2(a.x * f, a.y * f); }
        public static Vec2 operator *(double s, Vec2 a) { float f = (float)s; return new Vec2(a.x * f, a.y * f); }
        public static Vec2 operator /(Vec2 a, double s) { float f = (float)s; return new Vec2(a.x / f, a.y / f); }
        public static bool operator ==(Vec2 a, Vec2 b) => a.x == b.x && a.y == b.y;
        public static bool operator !=(Vec2 a, Vec2 b) => !(a == b);
        public bool Equals(Vec2 o) => this == o;
        public override bool Equals(object o) => o is Vec2 v && this == v;
        public override int GetHashCode() => x.GetHashCode() * 31 + y.GetHashCode();
        public override string ToString() => "(" + GFormat.NumRealF(x) + ", " + GFormat.NumRealF(y) + ")";

        public float Length() => MathF.Sqrt(x * x + y * y);
        public float LengthSquared() => x * x + y * y;
        public float Dot(Vec2 o) => x * o.x + y * o.y;
        public float Cross(Vec2 o) => x * o.y - y * o.x;
        public float DistanceTo(Vec2 o) => MathF.Sqrt((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y));
        public float DistanceSquaredTo(Vec2 o) => (x - o.x) * (x - o.x) + (y - o.y) * (y - o.y);
        public float Angle() => MathF.Atan2(y, x);
        public float AngleTo(Vec2 o) => MathF.Atan2(Cross(o), Dot(o));
        public float AngleToPoint(Vec2 o) => (o - this).Angle();
        public bool IsFinite() => float.IsFinite(x) && float.IsFinite(y);

        public Vec2 Normalized()
        {
            if (!IsFinite()) return Zero;
            float l = x * x + y * y;
            if (l == 0f) return Zero;
            l = MathF.Sqrt(l);
            return new Vec2(x / l, y / l);
        }

        public Vec2 LimitLength(double len = 1.0)
        {
            float p = (float)len;
            float l = Length();
            Vec2 v = this;
            if (l > 0f && p < l)
            {
                v = new Vec2(v.x / l, v.y / l);
                v = new Vec2(v.x * p, v.y * p);
            }
            return v;
        }

        public Vec2 Lerp(Vec2 to, double weight)
        {
            float w = (float)weight;
            return new Vec2(x + (to.x - x) * w, y + (to.y - y) * w);
        }

        public Vec2 CubicInterpolate(Vec2 b, Vec2 preA, Vec2 postB, double weight)
        {
            float w = (float)weight;
            return new Vec2(GD.CubicInterpolateF(x, b.x, preA.x, postB.x, w), GD.CubicInterpolateF(y, b.y, preA.y, postB.y, w));
        }

        public Vec2 DirectionTo(Vec2 to) => (to - this).Normalized();
        public Vec2 Abs() => new Vec2(MathF.Abs(x), MathF.Abs(y));
        public Vec2 Floor() => new Vec2(MathF.Floor(x), MathF.Floor(y));
        public Vec2 Round() => new Vec2(MathF.Round(x, MidpointRounding.AwayFromZero), MathF.Round(y, MidpointRounding.AwayFromZero));
        public Vec2 Orthogonal() => new Vec2(y, -x);
        public Vec2 Rotated(double by)
        {
            float b = (float)by;
            float s = MathF.Sin(b), c = MathF.Cos(b);
            return new Vec2(x * c - y * s, x * s + y * c);
        }
        public Vec2 MoveToward(Vec2 to, double delta)
        {
            float d = (float)delta;
            Vec2 vd = to - this;
            float len = vd.Length();
            return len <= d || len < GD.CMP_EPSILON_F ? to : this + vd / len * d;
        }

        public static Vec2 FromAngle(double angle)
        {
            float a = (float)angle;
            return new Vec2(MathF.Cos(a), MathF.Sin(a));
        }
    }

    public partial struct Vec2i : IEquatable<Vec2i>
    {
        public int x, y;
        public Vec2i(int x, int y) { this.x = x; this.y = y; }
        public static bool operator ==(Vec2i a, Vec2i b) => a.x == b.x && a.y == b.y;
        public static bool operator !=(Vec2i a, Vec2i b) => !(a == b);
        public static Vec2i operator +(Vec2i a, Vec2i b) => new Vec2i(a.x + b.x, a.y + b.y);
        public bool Equals(Vec2i o) => this == o;
        public override bool Equals(object o) => o is Vec2i v && this == v;
        public override int GetHashCode() => x * 73856093 ^ y * 19349663;
        public override string ToString() => "(" + x + ", " + y + ")";
    }

    public partial struct Vec3 : IEquatable<Vec3>
    {
        public float x, y, z;
        public Vec3(float x, float y, float z) { this.x = x; this.y = y; this.z = z; }
        public Vec3(double x, double y, double z) { this.x = (float)x; this.y = (float)y; this.z = (float)z; }
        public static readonly Vec3 Zero = new Vec3(0f, 0f, 0f);
        public static Vec3 operator +(Vec3 a, Vec3 b) => new Vec3(a.x + b.x, a.y + b.y, a.z + b.z);
        public static Vec3 operator -(Vec3 a, Vec3 b) => new Vec3(a.x - b.x, a.y - b.y, a.z - b.z);
        public static Vec3 operator *(Vec3 a, double s) { float f = (float)s; return new Vec3(a.x * f, a.y * f, a.z * f); }
        public static bool operator ==(Vec3 a, Vec3 b) => a.x == b.x && a.y == b.y && a.z == b.z;
        public static bool operator !=(Vec3 a, Vec3 b) => !(a == b);
        public bool Equals(Vec3 o) => this == o;
        public override bool Equals(object o) => o is Vec3 v && this == v;
        public override int GetHashCode() => x.GetHashCode() ^ y.GetHashCode() * 7 ^ z.GetHashCode() * 13;
        public float Length() => MathF.Sqrt(x * x + y * y + z * z);
        public Vec3 Normalized()
        {
            float l = x * x + y * y + z * z;
            if (l == 0f) return Zero;
            l = MathF.Sqrt(l);
            return new Vec3(x / l, y / l, z / l);
        }
    }

    /// <summary>Godot's Math:: and GDScript's global functions, on doubles unless named F.</summary>
    public static partial class GD
    {
        public const double PI = Math.PI;
        public const double TAU = Math.PI * 2.0;
        public const double CMP_EPSILON = 0.00001;
        public const float CMP_EPSILON_F = 0.00001f;
        public const double INF = double.PositiveInfinity;

        public static double Clamp(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);
        public static int ClampI(long v, long lo, long hi) => (int)(v < lo ? lo : (v > hi ? hi : v));
        public static double Lerp(double from, double to, double w) => from + (to - from) * w;
        public static double Max(double a, double b) => a > b ? a : b;     // (Godot's MAX: a > b ? a : b)
        public static double Min(double a, double b) => a < b ? a : b;
        public static int MaxI(int a, int b) => a > b ? a : b;
        public static int MinI(int a, int b) => a < b ? a : b;
        public static double Abs(double v) => Math.Abs(v);
        public static int AbsI(int v) => v < 0 ? -v : v;
        public static long AbsL(long v) => v < 0 ? -v : v;
        public static double Sign(double v) => v > 0 ? 1.0 : (v < 0 ? -1.0 : 0.0);
        public static double Floor(double v) => Math.Floor(v);
        public static double Ceil(double v) => Math.Ceiling(v);
        public static int FloorI(double v) => (int)Math.Floor(v);
        public static int CeilI(double v) => (int)Math.Ceiling(v);
        // (Godot's round: halfway away from zero)
        public static double Round(double v) => Math.Round(v, MidpointRounding.AwayFromZero);
        public static int RoundI(double v) => (int)Math.Round(v, MidpointRounding.AwayFromZero);
        public static double Sqrt(double v) => Math.Sqrt(v);
        public static double Pow(double b, double e) => Math.Pow(b, e);
        public static double Exp(double v) => Math.Exp(v);
        public static double Sin(double v) => Math.Sin(v);
        public static double Cos(double v) => Math.Cos(v);
        public static double Asin(double v) => Math.Asin(v);
        public static double Acos(double v) => Math.Acos(v);
        public static double Atan2(double y, double x) => Math.Atan2(y, x);
        public static double DegToRad(double d) => d * (PI / 180.0);

        public static double Fmod(double a, double b) => a % b;              // (C's fmod: C#'s % on doubles truncates the same way)
        public static double Fposmod(double x, double y)
        {
            double value = x % y;
            if ((value < 0 && y > 0) || (value > 0 && y < 0)) value += y;
            value += 0.0;
            return value;
        }
        public static long Posmod(long x, long y)
        {
            long value = x % y;
            if ((value < 0 && y > 0) || (value > 0 && y < 0)) value += y;
            return value;
        }

        public static double AngleDifference(double from, double to)
        {
            double difference = (to - from) % TAU;
            return (2.0 * difference) % TAU - difference;
        }
        public static double LerpAngle(double from, double to, double w) => from + AngleDifference(from, to) * w;
        public static double MoveToward(double from, double to, double delta) =>
            Math.Abs(to - from) <= delta ? to : from + Sign(to - from) * delta;

        public static bool IsEqualApprox(double a, double b)
        {
            if (a == b) return true;
            double tolerance = CMP_EPSILON * Math.Abs(a);
            if (tolerance < CMP_EPSILON) tolerance = CMP_EPSILON;
            return Math.Abs(a - b) < tolerance;
        }

        public static double Smoothstep(double from, double to, double s)
        {
            if (IsEqualApprox(from, to))
            {
                if (from <= to) return s <= from ? 0.0 : 1.0;
                return s <= to ? 1.0 : 0.0;
            }
            double t = Clamp((s - from) / (to - from), 0.0, 1.0);
            return t * t * (3.0 - 2.0 * t);
        }

        public static double Snapped(double value, double step)
        {
            if (step != 0) value = Math.Floor(value / step + 0.5) * step;
            return value;
        }

        public static double CubicInterpolate(double from, double to, double pre, double post, double w) =>
            0.5 * ((from * 2.0) + (-pre + to) * w + (2.0 * pre - 5.0 * from + 4.0 * to - post) * (w * w)
                + (-pre + 3.0 * from - 3.0 * to + post) * (w * w * w));
        public static float CubicInterpolateF(float from, float to, float pre, float post, float w) =>
            0.5f * ((from * 2.0f) + (-pre + to) * w + (2.0f * pre - 5.0f * from + 4.0f * to - post) * (w * w)
                + (-pre + 3.0f * from - 3.0f * to + post) * (w * w * w));

        /// <summary>GDScript's str() of a float: String::num_real ("1.0", "0.5", "0.33333333333333", "inf").</summary>
        public static string FloatStr(double v) => GFormat.NumReal(v, true);
    }

    /// <summary>Godot's String::hash (djb2, additive): GDScript's hash(some_string).</summary>
    public static class GHash
    {
        public static uint Str(string s)
        {
            uint h = 5381;
            // (char32 code points; the sim's strings are ASCII ids)
            for (int i = 0; i < s.Length; i++)
            {
                int c = char.ConvertToUtf32(s, i);
                if (char.IsHighSurrogate(s[i])) i++;
                h = ((h << 5) + h) + (uint)c;
            }
            return h;
        }
    }

    /// <summary>Godot's RandomNumberGenerator: PCG32 (pcg-c-basic), seeded the engine's way.</summary>
    public sealed class Rng
    {
        const ulong DEFAULT_INC = 1442695040888963407UL;
        ulong state, inc;
        ulong currentSeed;

        public Rng(ulong seed = 12047754176567800795UL) { Seed = seed; }

        public ulong Seed
        {
            get => currentSeed;
            set
            {
                currentSeed = value;
                state = 0UL;
                inc = (DEFAULT_INC << 1) | 1UL;
                Next();
                state += value;
                Next();
            }
        }

        public ulong State { get => state; set => state = value; }

        public uint Next()
        {
            ulong old = state;
            state = old * 6364136223846793005UL + (inc | 1UL);
            uint xorshifted = (uint)(((old >> 18) ^ old) >> 27);
            int rot = (int)(old >> 59);
            return (xorshifted >> rot) | (xorshifted << ((-rot) & 31));
        }

        public uint Bounded(uint bound)
        {
            uint threshold = (uint)(-bound) % bound;
            while (true)
            {
                uint r = Next();
                if (r >= threshold) return r % bound;
            }
        }

        static int Clz32(uint v)
        {
            // (no System.Numerics.BitOperations in .NET Standard 2.1, Unity's profile)
            if (v == 0) return 32;
            int n = 0;
            if ((v & 0xFFFF0000u) == 0) { n += 16; v <<= 16; }
            if ((v & 0xFF000000u) == 0) { n += 8; v <<= 8; }
            if ((v & 0xF0000000u) == 0) { n += 4; v <<= 4; }
            if ((v & 0xC0000000u) == 0) { n += 2; v <<= 2; }
            if ((v & 0x80000000u) == 0) { n += 1; }
            return n;
        }

        /// <summary>randf(): a float in [0, 1].</summary>
        public float Randf()
        {
            uint protoExpOffset = Next();
            if (protoExpOffset == 0) return 0f;
            return Ldexpf((float)(Next() | 0x80000001u), -32 - Clz32(protoExpOffset));
        }

        public double Randd()
        {
            uint protoExpOffset = Next();
            if (protoExpOffset == 0) return 0.0;
            ulong significand = (((ulong)Next()) << 32) | Next() | 0x8000000000000001UL;
            return Ldexp((double)significand, -64 - Clz32(protoExpOffset));
        }

        /// <summary>randf_range(from, to): in float, as RandomPCG::random(float, float).</summary>
        public float RandfRange(double from, double to)
        {
            float f = (float)from, t = (float)to;
            return Randf() * (t - f) + f;
        }

        /// <summary>randi_range(from, to): inclusive.</summary>
        public int RandiRange(int from, int to)
        {
            if (from == to) return from;
            long min = Math.Min(from, to), max = Math.Max(from, to);
            uint diff = (uint)(max - min);
            if (diff == uint.MaxValue) return (int)((long)Next() + min);
            return (int)((long)Bounded(diff + 1u) + min);
        }

        public uint Randi() => Next();

        static float Ldexpf(float x, int exp) => (float)Ldexp(x, exp);
        static double Ldexp(double x, int exp) => x * Math.Pow(2.0, exp);
    }
}
