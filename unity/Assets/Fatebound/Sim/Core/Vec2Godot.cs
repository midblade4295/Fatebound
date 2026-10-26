// Fatebound (Unity port): the rest of GDScript's Vector2 / Vector2i API on top of GMath.cs's Vec2 / Vec2i (whose
// members the match simulation uses and are left exactly as they are). core/math/vector2.{h,cpp} and vector2i.{h,cpp}
// with real_t = float: float arithmetic in Godot's order, scalars arriving as GDScript floats (double) narrowed to
// float first, as the engine's method binds do.
using System;

namespace Fatebound.Sim
{
    public partial struct Vec2
    {
        public static readonly Vec2 ZERO = new Vec2(0f, 0f);
        public static readonly Vec2 ONE = new Vec2(1f, 1f);
        public static readonly Vec2 INF = new Vec2(float.PositiveInfinity, float.PositiveInfinity);
        public static readonly Vec2 LEFT = new Vec2(-1f, 0f);
        public static readonly Vec2 RIGHT = new Vec2(1f, 0f);
        public static readonly Vec2 UP = new Vec2(0f, -1f);
        public static readonly Vec2 DOWN = new Vec2(0f, 1f);
        public const int AXIS_X = 0, AXIS_Y = 1;

        /// <summary>v[0] / v[1].</summary>
        public float this[int axis]
        {
            get
            {
                switch (axis) { case 0: return x; case 1: return y; }
                throw new IndexOutOfRangeException("Vector2 index " + axis);
            }
            set
            {
                switch (axis) { case 0: x = value; return; case 1: y = value; return; }
                throw new IndexOutOfRangeException("Vector2 index " + axis);
            }
        }

        public static Vec2 operator +(Vec2 a) => a;
        public static bool operator <(Vec2 a, Vec2 b) => a.x == b.x ? (a.y < b.y) : (a.x < b.x);
        public static bool operator >(Vec2 a, Vec2 b) => a.x == b.x ? (a.y > b.y) : (a.x > b.x);
        public static bool operator <=(Vec2 a, Vec2 b) => a.x == b.x ? (a.y <= b.y) : (a.x < b.x);
        public static bool operator >=(Vec2 a, Vec2 b) => a.x == b.x ? (a.y >= b.y) : (a.x > b.x);
        public static explicit operator Vec2i(Vec2 v) => new Vec2i((int)v.x, (int)v.y);
        public static explicit operator Vec2(Vec2i v) => new Vec2((float)v.x, (float)v.y);

        public float Aspect() => x / y;
        public int MaxAxisIndex() => x < y ? AXIS_Y : AXIS_X;
        public int MinAxisIndex() => x < y ? AXIS_X : AXIS_Y;

        public Vec2 Ceil() => new Vec2(MathF.Ceiling(x), MathF.Ceiling(y));
        public Vec2 Sign() => new Vec2(GD.SignF(x), GD.SignF(y));
        public Vec2 Min(Vec2 o) => new Vec2(GD.MinF(x, o.x), GD.MinF(y, o.y));
        public Vec2 Max(Vec2 o) => new Vec2(GD.MaxF(x, o.x), GD.MaxF(y, o.y));
        public Vec2 Minf(double s) { float f = (float)s; return new Vec2(GD.MinF(x, f), GD.MinF(y, f)); }
        public Vec2 Maxf(double s) { float f = (float)s; return new Vec2(GD.MaxF(x, f), GD.MaxF(y, f)); }
        public Vec2 Clamp(Vec2 min, Vec2 max) => new Vec2(GD.ClampF(x, min.x, max.x), GD.ClampF(y, min.y, max.y));
        public Vec2 Clampf(double min, double max)
        {
            float lo = (float)min, hi = (float)max;
            return new Vec2(GD.ClampF(x, lo, hi), GD.ClampF(y, lo, hi));
        }
        public Vec2 Snapped(Vec2 step) => new Vec2(GD.SnappedF(x, step.x), GD.SnappedF(y, step.y));
        public Vec2 Snappedf(double step) { float s = (float)step; return new Vec2(GD.SnappedF(x, s), GD.SnappedF(y, s)); }
        public Vec2 Posmod(double mod) { float m = (float)mod; return new Vec2(GD.FposmodF(x, m), GD.FposmodF(y, m)); }
        public Vec2 Posmodv(Vec2 modv) => new Vec2(GD.FposmodF(x, modv.x), GD.FposmodF(y, modv.y));
        public Vec2 Project(Vec2 to) => to * (Dot(to) / to.LengthSquared());
        public Vec2 PlaneProject(double d, Vec2 vec) => vec - this * (Dot(vec) - (float)d);

        public bool IsNormalized() => GD.IsEqualApproxF(LengthSquared(), 1f, GD.UNIT_EPS_F);
        public bool IsEqualApprox(Vec2 o) => GD.IsEqualApproxF(x, o.x) && GD.IsEqualApproxF(y, o.y);
        public bool IsZeroApprox() => GD.IsZeroApproxF(x) && GD.IsZeroApproxF(y);
        public bool IsSame(Vec2 o) => GD.IsSameF(x, o.x) && GD.IsSameF(y, o.y);

        public Vec2 Slerp(Vec2 to, double weight)
        {
            float w = (float)weight;
            float startLengthSq = LengthSquared();
            float endLengthSq = to.LengthSquared();
            if (startLengthSq == 0.0f || endLengthSq == 0.0f) return Lerp(to, w);
            float startLength = MathF.Sqrt(startLengthSq);
            float resultLength = GD.LerpF(startLength, MathF.Sqrt(endLengthSq), w);
            float angle = AngleTo(to);
            return Rotated(angle * w) * (resultLength / startLength);
        }

        public Vec2 CubicInterpolateInTime(Vec2 b, Vec2 preA, Vec2 postB, double weight, double bT, double preAT, double postBT)
        {
            float w = (float)weight, tb = (float)bT, tpre = (float)preAT, tpost = (float)postBT;
            return new Vec2(GD.CubicInterpolateInTimeF(x, b.x, preA.x, postB.x, w, tb, tpre, tpost),
                GD.CubicInterpolateInTimeF(y, b.y, preA.y, postB.y, w, tb, tpre, tpost));
        }

        public Vec2 BezierInterpolate(Vec2 c1, Vec2 c2, Vec2 end, double t)
        {
            float f = (float)t;
            return new Vec2(GD.BezierInterpolateF(x, c1.x, c2.x, end.x, f), GD.BezierInterpolateF(y, c1.y, c2.y, end.y, f));
        }

        public Vec2 BezierDerivative(Vec2 c1, Vec2 c2, Vec2 end, double t)
        {
            float f = (float)t;
            return new Vec2(GD.BezierDerivativeF(x, c1.x, c2.x, end.x, f), GD.BezierDerivativeF(y, c1.y, c2.y, end.y, f));
        }

        public Vec2 Slide(Vec2 n)
        {
            if (GD.MathChecks && !n.IsNormalized())
            {
                GD.MathError("The normal Vector2 " + n + "must be normalized.");
                return new Vec2(0f, 0f);
            }
            return this - n * Dot(n);
        }

        public Vec2 Bounce(Vec2 n) => -Reflect(n);

        public Vec2 Reflect(Vec2 n)
        {
            if (GD.MathChecks && !n.IsNormalized())
            {
                GD.MathError("The normal Vector2 " + n + "must be normalized.");
                return new Vec2(0f, 0f);
            }
            return n * 2.0 * Dot(n) - this;
        }

        public uint GodotHash()
        {
            uint h = GHashing.Murmur3OneFloat(x);
            h = GHashing.Murmur3OneFloat(y, h);
            return GHashing.Fmix32(h);
        }
    }

    public partial struct Vec2i : IComparable<Vec2i>
    {
        public static readonly Vec2i ZERO = new Vec2i(0, 0);
        public static readonly Vec2i ONE = new Vec2i(1, 1);
        public static readonly Vec2i MIN = new Vec2i(int.MinValue, int.MinValue);
        public static readonly Vec2i MAX = new Vec2i(int.MaxValue, int.MaxValue);
        public static readonly Vec2i LEFT = new Vec2i(-1, 0);
        public static readonly Vec2i RIGHT = new Vec2i(1, 0);
        public static readonly Vec2i UP = new Vec2i(0, -1);
        public static readonly Vec2i DOWN = new Vec2i(0, 1);
        public const int AXIS_X = 0, AXIS_Y = 1;

        public int this[int axis]
        {
            get
            {
                switch (axis) { case 0: return x; case 1: return y; }
                throw new IndexOutOfRangeException("Vector2i index " + axis);
            }
            set
            {
                switch (axis) { case 0: x = value; return; case 1: y = value; return; }
                throw new IndexOutOfRangeException("Vector2i index " + axis);
            }
        }

        // (C++ int32 arithmetic: wraps; division and modulo truncate toward zero)
        public static Vec2i operator -(Vec2i a, Vec2i b) => new Vec2i(unchecked(a.x - b.x), unchecked(a.y - b.y));
        public static Vec2i operator -(Vec2i a) => new Vec2i(unchecked(-a.x), unchecked(-a.y));
        public static Vec2i operator +(Vec2i a) => a;
        public static Vec2i operator *(Vec2i a, Vec2i b) => new Vec2i(unchecked(a.x * b.x), unchecked(a.y * b.y));
        public static Vec2i operator /(Vec2i a, Vec2i b) => new Vec2i(a.x / b.x, a.y / b.y);
        public static Vec2i operator %(Vec2i a, Vec2i b) => new Vec2i(a.x % b.x, a.y % b.y);
        public static Vec2i operator *(Vec2i a, long s) { int i = unchecked((int)s); return new Vec2i(unchecked(a.x * i), unchecked(a.y * i)); }
        public static Vec2i operator *(long s, Vec2i a) => a * s;
        public static Vec2i operator /(Vec2i a, long s) { int i = unchecked((int)s); return new Vec2i(a.x / i, a.y / i); }
        public static Vec2i operator %(Vec2i a, long s) { int i = unchecked((int)s); return new Vec2i(a.x % i, a.y % i); }
        /// <summary>Vector2i * float -> Vector2 (GDScript's operator).</summary>
        public static Vec2 operator *(Vec2i a, double s) => new Vec2((float)a.x, (float)a.y) * s;
        public static Vec2 operator *(double s, Vec2i a) => new Vec2((float)a.x, (float)a.y) * s;
        public static Vec2 operator /(Vec2i a, double s) => new Vec2((float)a.x, (float)a.y) / s;
        public static bool operator <(Vec2i a, Vec2i b) => a.x == b.x ? (a.y < b.y) : (a.x < b.x);
        public static bool operator >(Vec2i a, Vec2i b) => a.x == b.x ? (a.y > b.y) : (a.x > b.x);
        public static bool operator <=(Vec2i a, Vec2i b) => a.x == b.x ? (a.y <= b.y) : (a.x < b.x);
        public static bool operator >=(Vec2i a, Vec2i b) => a.x == b.x ? (a.y >= b.y) : (a.x > b.x);
        public int CompareTo(Vec2i o) => this < o ? -1 : (o < this ? 1 : 0);

        public float Aspect() => x / (float)y;
        public int MaxAxisIndex() => x < y ? AXIS_Y : AXIS_X;
        public int MinAxisIndex() => x < y ? AXIS_X : AXIS_Y;
        public long LengthSquared() => x * (long)x + y * (long)y;
        public double Length() => Math.Sqrt((double)LengthSquared());
        public double DistanceTo(Vec2i to) => (to - this).Length();
        public long DistanceSquaredTo(Vec2i to) => (to - this).LengthSquared();
        public Vec2i Sign() => new Vec2i(GD.SignI(x), GD.SignI(y));
        public Vec2i Abs() => new Vec2i(GD.AbsInt(x), GD.AbsInt(y));
        public Vec2i Clamp(Vec2i min, Vec2i max) => new Vec2i(GD.ClampInt(x, min.x, max.x), GD.ClampInt(y, min.y, max.y));
        public Vec2i Clampi(long min, long max)
        {
            int lo = unchecked((int)min), hi = unchecked((int)max);
            return new Vec2i(GD.ClampInt(x, lo, hi), GD.ClampInt(y, lo, hi));
        }
        public Vec2i Snapped(Vec2i step) => new Vec2i((int)GD.Snapped(x, step.x), (int)GD.Snapped(y, step.y));
        public Vec2i Snappedi(long step) { int s = unchecked((int)step); return new Vec2i((int)GD.Snapped(x, s), (int)GD.Snapped(y, s)); }
        public Vec2i Min(Vec2i o) => new Vec2i(x < o.x ? x : o.x, y < o.y ? y : o.y);
        public Vec2i Max(Vec2i o) => new Vec2i(x > o.x ? x : o.x, y > o.y ? y : o.y);
        public Vec2i Mini(long s) { int i = unchecked((int)s); return new Vec2i(x < i ? x : i, y < i ? y : i); }
        public Vec2i Maxi(long s) { int i = unchecked((int)s); return new Vec2i(x > i ? x : i, y > i ? y : i); }

        public uint GodotHash()
        {
            uint h = GHashing.Murmur3One32(unchecked((uint)x));
            h = GHashing.Murmur3One32(unchecked((uint)y), h);
            return GHashing.Fmix32(h);
        }
    }
}
