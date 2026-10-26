// Fatebound (Unity port): GDScript's Vector3 (on top of GMath.cs's Vec3, whose existing members the match simulation
// uses and are left exactly as they are), Vector3i, Vector4 and Vector4i. core/math/vector3*.{h,cpp}, vector4*.{h,cpp}
// with real_t = float: float arithmetic in Godot's order, GDScript float arguments narrowed to float first.
// Godot's default Vector3() is (0, 0, 0) like C#'s default, so `new Vec3()` is safe here.
using System;

namespace Fatebound.Sim
{
    public partial struct Vec3
    {
        public static readonly Vec3 ZERO = new Vec3(0f, 0f, 0f);
        public static readonly Vec3 ONE = new Vec3(1f, 1f, 1f);
        public static readonly Vec3 INF = new Vec3(float.PositiveInfinity, float.PositiveInfinity, float.PositiveInfinity);
        public static readonly Vec3 LEFT = new Vec3(-1f, 0f, 0f);
        public static readonly Vec3 RIGHT = new Vec3(1f, 0f, 0f);
        public static readonly Vec3 UP = new Vec3(0f, 1f, 0f);
        public static readonly Vec3 DOWN = new Vec3(0f, -1f, 0f);
        public static readonly Vec3 FORWARD = new Vec3(0f, 0f, -1f);
        public static readonly Vec3 BACK = new Vec3(0f, 0f, 1f);
        public static readonly Vec3 MODEL_LEFT = new Vec3(1f, 0f, 0f);
        public static readonly Vec3 MODEL_RIGHT = new Vec3(-1f, 0f, 0f);
        public static readonly Vec3 MODEL_TOP = new Vec3(0f, 1f, 0f);
        public static readonly Vec3 MODEL_BOTTOM = new Vec3(0f, -1f, 0f);
        public static readonly Vec3 MODEL_FRONT = new Vec3(0f, 0f, 1f);
        public static readonly Vec3 MODEL_REAR = new Vec3(0f, 0f, -1f);
        public const int AXIS_X = 0, AXIS_Y = 1, AXIS_Z = 2;

        public float this[int axis]
        {
            get
            {
                switch (axis) { case 0: return x; case 1: return y; case 2: return z; }
                throw new IndexOutOfRangeException("Vector3 index " + axis);
            }
            set
            {
                switch (axis) { case 0: x = value; return; case 1: y = value; return; case 2: z = value; return; }
                throw new IndexOutOfRangeException("Vector3 index " + axis);
            }
        }

        public static Vec3 operator -(Vec3 a) => new Vec3(-a.x, -a.y, -a.z);
        public static Vec3 operator +(Vec3 a) => a;
        public static Vec3 operator *(Vec3 a, Vec3 b) => new Vec3(a.x * b.x, a.y * b.y, a.z * b.z);
        public static Vec3 operator /(Vec3 a, Vec3 b) => new Vec3(a.x / b.x, a.y / b.y, a.z / b.z);
        public static Vec3 operator *(double s, Vec3 a) { float f = (float)s; return new Vec3(a.x * f, a.y * f, a.z * f); }
        public static Vec3 operator /(Vec3 a, double s) { float f = (float)s; return new Vec3(a.x / f, a.y / f, a.z / f); }
        public static bool operator <(Vec3 a, Vec3 b)
        {
            if (a.x == b.x) return a.y == b.y ? a.z < b.z : a.y < b.y;
            return a.x < b.x;
        }
        public static bool operator >(Vec3 a, Vec3 b)
        {
            if (a.x == b.x) return a.y == b.y ? a.z > b.z : a.y > b.y;
            return a.x > b.x;
        }
        public static bool operator <=(Vec3 a, Vec3 b)
        {
            if (a.x == b.x) return a.y == b.y ? a.z <= b.z : a.y < b.y;
            return a.x < b.x;
        }
        public static bool operator >=(Vec3 a, Vec3 b)
        {
            if (a.x == b.x) return a.y == b.y ? a.z >= b.z : a.y > b.y;
            return a.x > b.x;
        }
        public static explicit operator Vec3i(Vec3 v) => new Vec3i((int)v.x, (int)v.y, (int)v.z);
        public static explicit operator Vec3(Vec3i v) => new Vec3((float)v.x, (float)v.y, (float)v.z);

        public override string ToString() => "(" + GFormat.NumRealF(x) + ", " + GFormat.NumRealF(y) + ", " + GFormat.NumRealF(z) + ")";

        public int MinAxisIndex() => x < y ? (x < z ? AXIS_X : AXIS_Z) : (y < z ? AXIS_Y : AXIS_Z);
        public int MaxAxisIndex() => x < y ? (y < z ? AXIS_Z : AXIS_Y) : (x < z ? AXIS_Z : AXIS_X);
        public Vec3 Min(Vec3 o) => new Vec3(GD.MinF(x, o.x), GD.MinF(y, o.y), GD.MinF(z, o.z));
        public Vec3 Max(Vec3 o) => new Vec3(GD.MaxF(x, o.x), GD.MaxF(y, o.y), GD.MaxF(z, o.z));
        public Vec3 Minf(double s) { float f = (float)s; return new Vec3(GD.MinF(x, f), GD.MinF(y, f), GD.MinF(z, f)); }
        public Vec3 Maxf(double s) { float f = (float)s; return new Vec3(GD.MaxF(x, f), GD.MaxF(y, f), GD.MaxF(z, f)); }
        public Vec3 Clamp(Vec3 min, Vec3 max) => new Vec3(GD.ClampF(x, min.x, max.x), GD.ClampF(y, min.y, max.y), GD.ClampF(z, min.z, max.z));
        public Vec3 Clampf(double min, double max)
        {
            float lo = (float)min, hi = (float)max;
            return new Vec3(GD.ClampF(x, lo, hi), GD.ClampF(y, lo, hi), GD.ClampF(z, lo, hi));
        }

        public float LengthSquared()
        {
            float x2 = x * x, y2 = y * y, z2 = z * z;
            return x2 + y2 + z2;
        }

        public bool IsFinite() => GD.IsFiniteF(x) && GD.IsFiniteF(y) && GD.IsFiniteF(z);
        public bool IsNormalized() => GD.IsEqualApproxF(LengthSquared(), 1f, GD.UNIT_EPS_F);
        public bool IsEqualApprox(Vec3 o) => GD.IsEqualApproxF(x, o.x) && GD.IsEqualApproxF(y, o.y) && GD.IsEqualApproxF(z, o.z);
        public bool IsZeroApprox() => GD.IsZeroApproxF(x) && GD.IsZeroApproxF(y) && GD.IsZeroApproxF(z);
        public bool IsSame(Vec3 o) => GD.IsSameF(x, o.x) && GD.IsSameF(y, o.y) && GD.IsSameF(z, o.z);
        public Vec3 Inverse() => new Vec3(1.0f / x, 1.0f / y, 1.0f / z);

        /// <summary>Vector3::normalize exactly (a non-finite vector gives zero). Normalized() (GMath.cs) skips the
        /// finite check, so it differs only for inf/nan components; the ported types use this one.</summary>
        public Vec3 NormalizedChecked()
        {
            if (!IsFinite())
            {
                if (GD.MathChecks) GD.PushWarning("Vector3 cannot be normalized, the elements must be finite. Making (0, 0, 0) as a fallback.");
                return new Vec3(0f, 0f, 0f);
            }
            float l = LengthSquared();
            if (l == 0) return new Vec3(0f, 0f, 0f);
            l = MathF.Sqrt(l);
            return new Vec3(x / l, y / l, z / l);
        }

        public Vec3 LimitLength(double length = 1.0)
        {
            float p = (float)length;
            float l = Length();
            Vec3 v = this;
            if (l > 0 && p < l)
            {
                v = new Vec3(v.x / l, v.y / l, v.z / l);
                v = new Vec3(v.x * p, v.y * p, v.z * p);
            }
            return v;
        }

        public Vec3 Snapped(Vec3 step) => new Vec3(GD.SnappedF(x, step.x), GD.SnappedF(y, step.y), GD.SnappedF(z, step.z));
        public Vec3 Snappedf(double step) { float s = (float)step; return new Vec3(GD.SnappedF(x, s), GD.SnappedF(y, s), GD.SnappedF(z, s)); }

        /// <summary>rotated(axis, angle): Basis(axis, angle).xform(v) (the axis must be normalized).</summary>
        public Vec3 Rotated(Vec3 axis, double angle) => new Basis(axis, angle).Xform(this);

        public Vec3 Lerp(Vec3 to, double weight)
        {
            float w = (float)weight;
            return new Vec3(GD.LerpF(x, to.x, w), GD.LerpF(y, to.y, w), GD.LerpF(z, to.z, w));
        }

        public Vec3 Slerp(Vec3 to, double weight)
        {
            float w = (float)weight;
            float startLengthSq = LengthSquared();
            float endLengthSq = to.LengthSquared();
            if (startLengthSq == 0.0f || endLengthSq == 0.0f) return Lerp(to, w);
            Vec3 axis = Cross(to);
            float axisLengthSq = axis.LengthSquared();
            if (axisLengthSq == 0.0f) return Lerp(to, w);
            float al = MathF.Sqrt(axisLengthSq);
            axis = new Vec3(axis.x / al, axis.y / al, axis.z / al);
            float startLength = MathF.Sqrt(startLengthSq);
            float resultLength = GD.LerpF(startLength, MathF.Sqrt(endLengthSq), w);
            float angle = AngleTo(to);
            Vec3 r = Rotated(axis, angle * w);
            float k = resultLength / startLength;
            return new Vec3(r.x * k, r.y * k, r.z * k);
        }

        public Vec3 CubicInterpolate(Vec3 b, Vec3 preA, Vec3 postB, double weight)
        {
            float w = (float)weight;
            return new Vec3(GD.CubicInterpolateF(x, b.x, preA.x, postB.x, w), GD.CubicInterpolateF(y, b.y, preA.y, postB.y, w),
                GD.CubicInterpolateF(z, b.z, preA.z, postB.z, w));
        }

        public Vec3 CubicInterpolateInTime(Vec3 b, Vec3 preA, Vec3 postB, double weight, double bT, double preAT, double postBT)
        {
            float w = (float)weight, tb = (float)bT, tpre = (float)preAT, tpost = (float)postBT;
            return new Vec3(GD.CubicInterpolateInTimeF(x, b.x, preA.x, postB.x, w, tb, tpre, tpost),
                GD.CubicInterpolateInTimeF(y, b.y, preA.y, postB.y, w, tb, tpre, tpost),
                GD.CubicInterpolateInTimeF(z, b.z, preA.z, postB.z, w, tb, tpre, tpost));
        }

        public Vec3 BezierInterpolate(Vec3 c1, Vec3 c2, Vec3 end, double t)
        {
            float f = (float)t;
            return new Vec3(GD.BezierInterpolateF(x, c1.x, c2.x, end.x, f), GD.BezierInterpolateF(y, c1.y, c2.y, end.y, f),
                GD.BezierInterpolateF(z, c1.z, c2.z, end.z, f));
        }

        public Vec3 BezierDerivative(Vec3 c1, Vec3 c2, Vec3 end, double t)
        {
            float f = (float)t;
            return new Vec3(GD.BezierDerivativeF(x, c1.x, c2.x, end.x, f), GD.BezierDerivativeF(y, c1.y, c2.y, end.y, f),
                GD.BezierDerivativeF(z, c1.z, c2.z, end.z, f));
        }

        public Vec3 MoveToward(Vec3 to, double delta)
        {
            float d = (float)delta;
            Vec3 vd = to - this;
            float len = vd.Length();
            if (len <= d || len < GD.EPS_F) return to;
            Vec3 s = new Vec3(vd.x / len, vd.y / len, vd.z / len);
            return this + new Vec3(s.x * d, s.y * d, s.z * d);
        }

        public Vec2 OctahedronEncode()
        {
            Vec3 n = this;
            float s = MathF.Abs(n.x) + MathF.Abs(n.y) + MathF.Abs(n.z);
            n = new Vec3(n.x / s, n.y / s, n.z / s);
            float ox, oy;
            if (n.z >= 0.0f)
            {
                ox = n.x;
                oy = n.y;
            }
            else
            {
                ox = (1.0f - MathF.Abs(n.y)) * (n.x >= 0.0f ? 1.0f : -1.0f);
                oy = (1.0f - MathF.Abs(n.x)) * (n.y >= 0.0f ? 1.0f : -1.0f);
            }
            ox = ox * 0.5f + 0.5f;
            oy = oy * 0.5f + 0.5f;
            return new Vec2(ox, oy);
        }

        public static Vec3 OctahedronDecode(Vec2 oct)
        {
            float fx = oct.x * 2.0f - 1.0f, fy = oct.y * 2.0f - 1.0f;
            Vec3 n = new Vec3(fx, fy, 1.0f - MathF.Abs(fx) - MathF.Abs(fy));
            float t = GD.ClampF(-n.z, 0.0f, 1.0f);
            n.x += n.x >= 0 ? -t : t;
            n.y += n.y >= 0 ? -t : t;
            return n.NormalizedChecked();
        }

        public Vec3 Cross(Vec3 w) => new Vec3((y * w.z) - (z * w.y), (z * w.x) - (x * w.z), (x * w.y) - (y * w.x));
        public float Dot(Vec3 w) => x * w.x + y * w.y + z * w.z;

        public Basis Outer(Vec3 w) => Basis.FromRows(x * w.x, x * w.y, x * w.z, y * w.x, y * w.y, y * w.z, z * w.x, z * w.y, z * w.z);

        /// <summary>Vector3::get_any_perpendicular (C++ only; used by Basis.looking_at and the shortest-arc Quaternion).</summary>
        public Vec3 GetAnyPerpendicular()
        {
            if (IsZeroApprox())
            {
                GD.MathError("The Vector3 must not be zero.");
                return new Vec3(0f, 0f, 0f);
            }
            return Cross((MathF.Abs(x) <= MathF.Abs(y) && MathF.Abs(x) <= MathF.Abs(z)) ? RIGHT : UP).NormalizedChecked();
        }

        public Vec3 Abs() => new Vec3(MathF.Abs(x), MathF.Abs(y), MathF.Abs(z));
        public Vec3 Floor() => new Vec3(MathF.Floor(x), MathF.Floor(y), MathF.Floor(z));
        public Vec3 Ceil() => new Vec3(MathF.Ceiling(x), MathF.Ceiling(y), MathF.Ceiling(z));
        public Vec3 Round() => new Vec3(MathF.Round(x, MidpointRounding.AwayFromZero), MathF.Round(y, MidpointRounding.AwayFromZero), MathF.Round(z, MidpointRounding.AwayFromZero));
        public Vec3 Sign() => new Vec3(GD.SignF(x), GD.SignF(y), GD.SignF(z));
        public float DistanceTo(Vec3 to) => (to - this).Length();
        public float DistanceSquaredTo(Vec3 to) => (to - this).LengthSquared();
        public Vec3 Posmod(double mod) { float m = (float)mod; return new Vec3(GD.FposmodF(x, m), GD.FposmodF(y, m), GD.FposmodF(z, m)); }
        public Vec3 Posmodv(Vec3 m) => new Vec3(GD.FposmodF(x, m.x), GD.FposmodF(y, m.y), GD.FposmodF(z, m.z));

        public Vec3 Project(Vec3 to)
        {
            float k = Dot(to) / to.LengthSquared();
            return new Vec3(to.x * k, to.y * k, to.z * k);
        }

        public float AngleTo(Vec3 to) => MathF.Atan2(Cross(to).Length(), Dot(to));

        public float SignedAngleTo(Vec3 to, Vec3 axis)
        {
            Vec3 crossTo = Cross(to);
            float unsignedAngle = MathF.Atan2(crossTo.Length(), Dot(to));
            float sign = crossTo.Dot(axis);
            return (sign < 0) ? -unsignedAngle : unsignedAngle;
        }

        public Vec3 DirectionTo(Vec3 to) => new Vec3(to.x - x, to.y - y, to.z - z).NormalizedChecked();

        public Vec3 Slide(Vec3 n)
        {
            if (GD.MathChecks && !n.IsNormalized())
            {
                GD.MathError("The normal Vector3 " + n + " must be normalized.");
                return new Vec3(0f, 0f, 0f);
            }
            float d = Dot(n);
            return this - new Vec3(n.x * d, n.y * d, n.z * d);
        }

        public Vec3 Bounce(Vec3 n) => -Reflect(n);

        public Vec3 Reflect(Vec3 n)
        {
            if (GD.MathChecks && !n.IsNormalized())
            {
                GD.MathError("The normal Vector3 " + n + " must be normalized.");
                return new Vec3(0f, 0f, 0f);
            }
            float d = Dot(n);
            Vec3 n2 = new Vec3(n.x * 2.0f, n.y * 2.0f, n.z * 2.0f);
            return new Vec3(n2.x * d, n2.y * d, n2.z * d) - this;
        }

        public uint GodotHash()
        {
            uint h = GHashing.Murmur3OneFloat(x);
            h = GHashing.Murmur3OneFloat(y, h);
            h = GHashing.Murmur3OneFloat(z, h);
            return GHashing.Fmix32(h);
        }
    }

    /// <summary>Godot's Vector3i.</summary>
    public struct Vec3i : IEquatable<Vec3i>, IComparable<Vec3i>, IGodotValue
    {
        public int x, y, z;
        public Vec3i(int x, int y, int z) { this.x = x; this.y = y; this.z = z; }
        public Vec3i(long x, long y, long z) { this.x = unchecked((int)x); this.y = unchecked((int)y); this.z = unchecked((int)z); }

        public static readonly Vec3i ZERO = new Vec3i(0, 0, 0);
        public static readonly Vec3i ONE = new Vec3i(1, 1, 1);
        public static readonly Vec3i MIN = new Vec3i(int.MinValue, int.MinValue, int.MinValue);
        public static readonly Vec3i MAX = new Vec3i(int.MaxValue, int.MaxValue, int.MaxValue);
        public static readonly Vec3i LEFT = new Vec3i(-1, 0, 0);
        public static readonly Vec3i RIGHT = new Vec3i(1, 0, 0);
        public static readonly Vec3i UP = new Vec3i(0, 1, 0);
        public static readonly Vec3i DOWN = new Vec3i(0, -1, 0);
        public static readonly Vec3i FORWARD = new Vec3i(0, 0, -1);
        public static readonly Vec3i BACK = new Vec3i(0, 0, 1);
        public const int AXIS_X = 0, AXIS_Y = 1, AXIS_Z = 2;

        public int this[int axis]
        {
            get
            {
                switch (axis) { case 0: return x; case 1: return y; case 2: return z; }
                throw new IndexOutOfRangeException("Vector3i index " + axis);
            }
            set
            {
                switch (axis) { case 0: x = value; return; case 1: y = value; return; case 2: z = value; return; }
                throw new IndexOutOfRangeException("Vector3i index " + axis);
            }
        }

        public static Vec3i operator +(Vec3i a, Vec3i b) => new Vec3i(unchecked(a.x + b.x), unchecked(a.y + b.y), unchecked(a.z + b.z));
        public static Vec3i operator -(Vec3i a, Vec3i b) => new Vec3i(unchecked(a.x - b.x), unchecked(a.y - b.y), unchecked(a.z - b.z));
        public static Vec3i operator *(Vec3i a, Vec3i b) => new Vec3i(unchecked(a.x * b.x), unchecked(a.y * b.y), unchecked(a.z * b.z));
        public static Vec3i operator /(Vec3i a, Vec3i b) => new Vec3i(a.x / b.x, a.y / b.y, a.z / b.z);
        public static Vec3i operator %(Vec3i a, Vec3i b) => new Vec3i(a.x % b.x, a.y % b.y, a.z % b.z);
        public static Vec3i operator *(Vec3i a, long s) { int i = unchecked((int)s); return new Vec3i(unchecked(a.x * i), unchecked(a.y * i), unchecked(a.z * i)); }
        public static Vec3i operator *(long s, Vec3i a) => a * s;
        public static Vec3i operator /(Vec3i a, long s) { int i = unchecked((int)s); return new Vec3i(a.x / i, a.y / i, a.z / i); }
        public static Vec3i operator %(Vec3i a, long s) { int i = unchecked((int)s); return new Vec3i(a.x % i, a.y % i, a.z % i); }
        /// <summary>Vector3i * float -> Vector3.</summary>
        public static Vec3 operator *(Vec3i a, double s) => new Vec3((float)a.x, (float)a.y, (float)a.z) * s;
        public static Vec3 operator *(double s, Vec3i a) => new Vec3((float)a.x, (float)a.y, (float)a.z) * s;
        public static Vec3 operator /(Vec3i a, double s) => new Vec3((float)a.x, (float)a.y, (float)a.z) / s;
        public static Vec3i operator -(Vec3i a) => new Vec3i(unchecked(-a.x), unchecked(-a.y), unchecked(-a.z));
        public static Vec3i operator +(Vec3i a) => a;
        public static bool operator ==(Vec3i a, Vec3i b) => a.x == b.x && a.y == b.y && a.z == b.z;
        public static bool operator !=(Vec3i a, Vec3i b) => !(a == b);
        public static bool operator <(Vec3i a, Vec3i b)
        {
            if (a.x == b.x) return a.y == b.y ? a.z < b.z : a.y < b.y;
            return a.x < b.x;
        }
        public static bool operator >(Vec3i a, Vec3i b)
        {
            if (a.x == b.x) return a.y == b.y ? a.z > b.z : a.y > b.y;
            return a.x > b.x;
        }
        public static bool operator <=(Vec3i a, Vec3i b)
        {
            if (a.x == b.x) return a.y == b.y ? a.z <= b.z : a.y < b.y;
            return a.x < b.x;
        }
        public static bool operator >=(Vec3i a, Vec3i b)
        {
            if (a.x == b.x) return a.y == b.y ? a.z >= b.z : a.y > b.y;
            return a.x > b.x;
        }
        public int CompareTo(Vec3i o) => this < o ? -1 : (o < this ? 1 : 0);
        public bool Equals(Vec3i o) => this == o;
        public override bool Equals(object o) => o is Vec3i v && this == v;
        public override int GetHashCode() => unchecked((int)GodotHash());
        public override string ToString() => "(" + GFormat.Itos(x) + ", " + GFormat.Itos(y) + ", " + GFormat.Itos(z) + ")";

        public int MinAxisIndex() => x < y ? (x < z ? AXIS_X : AXIS_Z) : (y < z ? AXIS_Y : AXIS_Z);
        public int MaxAxisIndex() => x < y ? (y < z ? AXIS_Z : AXIS_Y) : (x < z ? AXIS_Z : AXIS_X);
        public long LengthSquared() => x * (long)x + y * (long)y + z * (long)z;
        public double Length() => Math.Sqrt((double)LengthSquared());
        public double DistanceTo(Vec3i to) => (to - this).Length();
        public long DistanceSquaredTo(Vec3i to) => (to - this).LengthSquared();
        public Vec3i Abs() => new Vec3i(GD.AbsInt(x), GD.AbsInt(y), GD.AbsInt(z));
        public Vec3i Sign() => new Vec3i(GD.SignI(x), GD.SignI(y), GD.SignI(z));
        public Vec3i Clamp(Vec3i min, Vec3i max) => new Vec3i(GD.ClampInt(x, min.x, max.x), GD.ClampInt(y, min.y, max.y), GD.ClampInt(z, min.z, max.z));
        public Vec3i Clampi(long min, long max)
        {
            int lo = unchecked((int)min), hi = unchecked((int)max);
            return new Vec3i(GD.ClampInt(x, lo, hi), GD.ClampInt(y, lo, hi), GD.ClampInt(z, lo, hi));
        }
        public Vec3i Snapped(Vec3i step) => new Vec3i((int)GD.Snapped(x, step.x), (int)GD.Snapped(y, step.y), (int)GD.Snapped(z, step.z));
        public Vec3i Snappedi(long step)
        {
            int s = unchecked((int)step);
            return new Vec3i((int)GD.Snapped(x, s), (int)GD.Snapped(y, s), (int)GD.Snapped(z, s));
        }
        public Vec3i Min(Vec3i o) => new Vec3i(x < o.x ? x : o.x, y < o.y ? y : o.y, z < o.z ? z : o.z);
        public Vec3i Max(Vec3i o) => new Vec3i(x > o.x ? x : o.x, y > o.y ? y : o.y, z > o.z ? z : o.z);
        public Vec3i Mini(long s) { int i = unchecked((int)s); return new Vec3i(x < i ? x : i, y < i ? y : i, z < i ? z : i); }
        public Vec3i Maxi(long s) { int i = unchecked((int)s); return new Vec3i(x > i ? x : i, y > i ? y : i, z > i ? z : i); }

        // ---- Variant
        public static implicit operator Var(Vec3i v) => Var.Of(v);
        public static explicit operator Vec3i(Var v)
        {
            object o = v.Obj;
            if (o is Vec3i a) return a;
            if (o is Vec3 b) return (Vec3i)b;
            return default;
        }
        public int GodotType => GD.TYPE_VECTOR3I;
        public string GodotStr() => ToString();
        public bool GodotIsZero => x == 0 && y == 0 && z == 0;
        public uint GodotHash()
        {
            uint h = GHashing.Murmur3One32(unchecked((uint)x));
            h = GHashing.Murmur3One32(unchecked((uint)y), h);
            h = GHashing.Murmur3One32(unchecked((uint)z), h);
            return GHashing.Fmix32(h);
        }

        public bool GodotOp(char op, Var other, bool selfLeft, out Var result)
        {
            result = Var.Nil;
            if (op == 'n') { result = -this; return true; }
            object o = other.Obj;
            if (o is Vec3i b)
            {
                Vec3i l = selfLeft ? this : b, r = selfLeft ? b : this;
                switch (op)
                {
                    case '+': result = l + r; return true;
                    case '-': result = l - r; return true;
                    case '*': result = l * r; return true;
                    case '/':
                    case '%':
                        if (r.x == 0 || r.y == 0 || r.z == 0) { GD.PushError("Division by zero error in operator '" + op + "'."); result = default(Vec3i); return true; }
                        result = op == '/' ? l / r : l % r;
                        return true;
                }
                return false;
            }
            if (other.IsInt)
            {
                long s = other.AsLong();
                if (op == '*') { result = this * s; return true; }
                if (!selfLeft) return false;
                if (op == '/' || op == '%')
                {
                    if (s == 0) { GD.PushError("Division by zero error in operator '" + op + "'."); result = default(Vec3i); return true; }
                    result = op == '/' ? this / s : this % s;
                    return true;
                }
                return false;
            }
            if (other.IsFloat)
            {
                double s = other.AsFloat();
                if (op == '*') { result = this * s; return true; }
                if (op == '/' && selfLeft)
                {
                    if (s == 0) { GD.PushError("Division by zero error in operator '/'."); result = new Vec3(); return true; }
                    result = this / s;
                    return true;
                }
            }
            return false;
        }
    }

    /// <summary>Godot's Vector4 (real_t = float).</summary>
    public struct Vec4 : IEquatable<Vec4>, IComparable<Vec4>, IGodotValue
    {
        public float x, y, z, w;
        public Vec4(float x, float y, float z, float w) { this.x = x; this.y = y; this.z = z; this.w = w; }
        public Vec4(double x, double y, double z, double w) { this.x = (float)x; this.y = (float)y; this.z = (float)z; this.w = (float)w; }

        public static readonly Vec4 ZERO = new Vec4(0f, 0f, 0f, 0f);
        public static readonly Vec4 ONE = new Vec4(1f, 1f, 1f, 1f);
        public static readonly Vec4 INF = new Vec4(float.PositiveInfinity, float.PositiveInfinity, float.PositiveInfinity, float.PositiveInfinity);
        public const int AXIS_X = 0, AXIS_Y = 1, AXIS_Z = 2, AXIS_W = 3;

        public float this[int axis]
        {
            get
            {
                switch (axis) { case 0: return x; case 1: return y; case 2: return z; case 3: return w; }
                throw new IndexOutOfRangeException("Vector4 index " + axis);
            }
            set
            {
                switch (axis) { case 0: x = value; return; case 1: y = value; return; case 2: z = value; return; case 3: w = value; return; }
                throw new IndexOutOfRangeException("Vector4 index " + axis);
            }
        }

        public static Vec4 operator +(Vec4 a, Vec4 b) => new Vec4(a.x + b.x, a.y + b.y, a.z + b.z, a.w + b.w);
        public static Vec4 operator -(Vec4 a, Vec4 b) => new Vec4(a.x - b.x, a.y - b.y, a.z - b.z, a.w - b.w);
        public static Vec4 operator *(Vec4 a, Vec4 b) => new Vec4(a.x * b.x, a.y * b.y, a.z * b.z, a.w * b.w);
        public static Vec4 operator /(Vec4 a, Vec4 b) => new Vec4(a.x / b.x, a.y / b.y, a.z / b.z, a.w / b.w);
        public static Vec4 operator *(Vec4 a, double s) { float f = (float)s; return new Vec4(a.x * f, a.y * f, a.z * f, a.w * f); }
        public static Vec4 operator *(double s, Vec4 a) => a * s;
        public static Vec4 operator /(Vec4 a, double s) { float f = (float)s; return new Vec4(a.x / f, a.y / f, a.z / f, a.w / f); }
        public static Vec4 operator -(Vec4 a) => new Vec4(-a.x, -a.y, -a.z, -a.w);
        public static Vec4 operator +(Vec4 a) => a;
        public static bool operator ==(Vec4 a, Vec4 b) => a.x == b.x && a.y == b.y && a.z == b.z && a.w == b.w;
        public static bool operator !=(Vec4 a, Vec4 b) => a.x != b.x || a.y != b.y || a.z != b.z || a.w != b.w;
        public static bool operator <(Vec4 a, Vec4 b)
        {
            if (a.x == b.x)
            {
                if (a.y == b.y) return a.z == b.z ? a.w < b.w : a.z < b.z;
                return a.y < b.y;
            }
            return a.x < b.x;
        }
        public static bool operator >(Vec4 a, Vec4 b)
        {
            if (a.x == b.x)
            {
                if (a.y == b.y) return a.z == b.z ? a.w > b.w : a.z > b.z;
                return a.y > b.y;
            }
            return a.x > b.x;
        }
        public static bool operator <=(Vec4 a, Vec4 b)
        {
            if (a.x == b.x)
            {
                if (a.y == b.y) return a.z == b.z ? a.w <= b.w : a.z < b.z;
                return a.y < b.y;
            }
            return a.x < b.x;
        }
        public static bool operator >=(Vec4 a, Vec4 b)
        {
            if (a.x == b.x)
            {
                if (a.y == b.y) return a.z == b.z ? a.w >= b.w : a.z > b.z;
                return a.y > b.y;
            }
            return a.x > b.x;
        }
        public static explicit operator Vec4i(Vec4 v) => new Vec4i((int)v.x, (int)v.y, (int)v.z, (int)v.w);
        public static explicit operator Vec4(Vec4i v) => new Vec4((float)v.x, (float)v.y, (float)v.z, (float)v.w);
        public int CompareTo(Vec4 o) => this < o ? -1 : (o < this ? 1 : 0);
        public bool Equals(Vec4 o) => this == o;
        public override bool Equals(object o) => o is Vec4 v && this == v;
        public override int GetHashCode() => unchecked((int)GodotHash());
        public override string ToString() => "(" + GFormat.NumRealF(x) + ", " + GFormat.NumRealF(y) + ", " + GFormat.NumRealF(z) + ", " + GFormat.NumRealF(w) + ")";

        public int MinAxisIndex()
        {
            int minIndex = 0;
            float minValue = x;
            for (int i = 1; i < 4; i++)
                if (this[i] <= minValue) { minIndex = i; minValue = this[i]; }
            return minIndex;
        }

        public int MaxAxisIndex()
        {
            int maxIndex = 0;
            float maxValue = x;
            for (int i = 1; i < 4; i++)
                if (this[i] > maxValue) { maxIndex = i; maxValue = this[i]; }
            return maxIndex;
        }

        public Vec4 Min(Vec4 o) => new Vec4(GD.MinF(x, o.x), GD.MinF(y, o.y), GD.MinF(z, o.z), GD.MinF(w, o.w));
        public Vec4 Max(Vec4 o) => new Vec4(GD.MaxF(x, o.x), GD.MaxF(y, o.y), GD.MaxF(z, o.z), GD.MaxF(w, o.w));
        public Vec4 Minf(double s) { float f = (float)s; return new Vec4(GD.MinF(x, f), GD.MinF(y, f), GD.MinF(z, f), GD.MinF(w, f)); }
        public Vec4 Maxf(double s) { float f = (float)s; return new Vec4(GD.MaxF(x, f), GD.MaxF(y, f), GD.MaxF(z, f), GD.MaxF(w, f)); }
        public float Dot(Vec4 o) => x * o.x + y * o.y + z * o.z + w * o.w;
        public float LengthSquared() => Dot(this);
        public float Length() => MathF.Sqrt(LengthSquared());
        public bool IsEqualApprox(Vec4 o) => GD.IsEqualApproxF(x, o.x) && GD.IsEqualApproxF(y, o.y) && GD.IsEqualApproxF(z, o.z) && GD.IsEqualApproxF(w, o.w);
        public bool IsZeroApprox() => GD.IsZeroApproxF(x) && GD.IsZeroApproxF(y) && GD.IsZeroApproxF(z) && GD.IsZeroApproxF(w);
        public bool IsSame(Vec4 o) => GD.IsSameF(x, o.x) && GD.IsSameF(y, o.y) && GD.IsSameF(z, o.z) && GD.IsSameF(w, o.w);
        public bool IsFinite() => GD.IsFiniteF(x) && GD.IsFiniteF(y) && GD.IsFiniteF(z) && GD.IsFiniteF(w);

        public Vec4 Normalized()
        {
            if (!IsFinite())
            {
                if (GD.MathChecks) GD.PushWarning("Vector4 cannot be normalized, the elements must be finite. Making (0, 0, 0, 0) as a fallback.");
                return new Vec4(0f, 0f, 0f, 0f);
            }
            float l = LengthSquared();
            if (l == 0) return new Vec4(0f, 0f, 0f, 0f);
            l = MathF.Sqrt(l);
            return new Vec4(x / l, y / l, z / l, w / l);
        }

        public bool IsNormalized() => GD.IsEqualApproxF(LengthSquared(), 1f, GD.UNIT_EPS_F);
        public float DistanceTo(Vec4 to) => (to - this).Length();
        public float DistanceSquaredTo(Vec4 to) => (to - this).LengthSquared();
        public Vec4 DirectionTo(Vec4 to) => new Vec4(to.x - x, to.y - y, to.z - z, to.w - w).Normalized();
        public Vec4 Abs() => new Vec4(MathF.Abs(x), MathF.Abs(y), MathF.Abs(z), MathF.Abs(w));
        public Vec4 Sign() => new Vec4(GD.SignF(x), GD.SignF(y), GD.SignF(z), GD.SignF(w));
        public Vec4 Floor() => new Vec4(MathF.Floor(x), MathF.Floor(y), MathF.Floor(z), MathF.Floor(w));
        public Vec4 Ceil() => new Vec4(MathF.Ceiling(x), MathF.Ceiling(y), MathF.Ceiling(z), MathF.Ceiling(w));
        public Vec4 Round() => new Vec4(MathF.Round(x, MidpointRounding.AwayFromZero), MathF.Round(y, MidpointRounding.AwayFromZero),
            MathF.Round(z, MidpointRounding.AwayFromZero), MathF.Round(w, MidpointRounding.AwayFromZero));

        public Vec4 Lerp(Vec4 to, double weight)
        {
            float t = (float)weight;
            return new Vec4(GD.LerpF(x, to.x, t), GD.LerpF(y, to.y, t), GD.LerpF(z, to.z, t), GD.LerpF(w, to.w, t));
        }

        public Vec4 CubicInterpolate(Vec4 b, Vec4 preA, Vec4 postB, double weight)
        {
            float t = (float)weight;
            return new Vec4(GD.CubicInterpolateF(x, b.x, preA.x, postB.x, t), GD.CubicInterpolateF(y, b.y, preA.y, postB.y, t),
                GD.CubicInterpolateF(z, b.z, preA.z, postB.z, t), GD.CubicInterpolateF(w, b.w, preA.w, postB.w, t));
        }

        public Vec4 CubicInterpolateInTime(Vec4 b, Vec4 preA, Vec4 postB, double weight, double bT, double preAT, double postBT)
        {
            float t = (float)weight, tb = (float)bT, tpre = (float)preAT, tpost = (float)postBT;
            return new Vec4(GD.CubicInterpolateInTimeF(x, b.x, preA.x, postB.x, t, tb, tpre, tpost),
                GD.CubicInterpolateInTimeF(y, b.y, preA.y, postB.y, t, tb, tpre, tpost),
                GD.CubicInterpolateInTimeF(z, b.z, preA.z, postB.z, t, tb, tpre, tpost),
                GD.CubicInterpolateInTimeF(w, b.w, preA.w, postB.w, t, tb, tpre, tpost));
        }

        public Vec4 Posmod(double mod) { float m = (float)mod; return new Vec4(GD.FposmodF(x, m), GD.FposmodF(y, m), GD.FposmodF(z, m), GD.FposmodF(w, m)); }
        public Vec4 Posmodv(Vec4 m) => new Vec4(GD.FposmodF(x, m.x), GD.FposmodF(y, m.y), GD.FposmodF(z, m.z), GD.FposmodF(w, m.w));
        public Vec4 Snapped(Vec4 s) => new Vec4(GD.SnappedF(x, s.x), GD.SnappedF(y, s.y), GD.SnappedF(z, s.z), GD.SnappedF(w, s.w));
        public Vec4 Snappedf(double step) { float s = (float)step; return new Vec4(GD.SnappedF(x, s), GD.SnappedF(y, s), GD.SnappedF(z, s), GD.SnappedF(w, s)); }
        public Vec4 Clamp(Vec4 min, Vec4 max) => new Vec4(GD.ClampF(x, min.x, max.x), GD.ClampF(y, min.y, max.y), GD.ClampF(z, min.z, max.z), GD.ClampF(w, min.w, max.w));
        public Vec4 Clampf(double min, double max)
        {
            float lo = (float)min, hi = (float)max;
            return new Vec4(GD.ClampF(x, lo, hi), GD.ClampF(y, lo, hi), GD.ClampF(z, lo, hi), GD.ClampF(w, lo, hi));
        }
        public Vec4 Inverse() => new Vec4(1.0f / x, 1.0f / y, 1.0f / z, 1.0f / w);

        // ---- Variant
        public static implicit operator Var(Vec4 v) => Var.Of(v);
        public static explicit operator Vec4(Var v)
        {
            object o = v.Obj;
            if (o is Vec4 a) return a;
            if (o is Vec4i b) return (Vec4)b;
            return default;
        }
        public int GodotType => GD.TYPE_VECTOR4;
        public string GodotStr() => ToString();
        public bool GodotIsZero => this == default(Vec4);
        public uint GodotHash()
        {
            uint h = GHashing.Murmur3OneFloat(x);
            h = GHashing.Murmur3OneFloat(y, h);
            h = GHashing.Murmur3OneFloat(z, h);
            h = GHashing.Murmur3OneFloat(w, h);
            return GHashing.Fmix32(h);
        }

        public bool GodotOp(char op, Var other, bool selfLeft, out Var result)
        {
            result = Var.Nil;
            if (op == 'n') { result = -this; return true; }
            object o = other.Obj;
            if (o is Vec4 b)
            {
                Vec4 l = selfLeft ? this : b, r = selfLeft ? b : this;
                switch (op)
                {
                    case '+': result = l + r; return true;
                    case '-': result = l - r; return true;
                    case '*': result = l * r; return true;
                    case '/': result = l / r; return true;
                }
                return false;
            }
            if (o is Projection p && selfLeft && op == '*') { result = p.XformInv(this); return true; }
            if (other.IsNum)
            {
                double s = other.IsInt ? (double)(float)other.AsLong() : other.AsFloat();
                if (op == '*') { result = this * s; return true; }
                if (op == '/' && selfLeft) { result = this / s; return true; }
            }
            return false;
        }
    }

    /// <summary>Godot's Vector4i.</summary>
    public struct Vec4i : IEquatable<Vec4i>, IComparable<Vec4i>, IGodotValue
    {
        public int x, y, z, w;
        public Vec4i(int x, int y, int z, int w) { this.x = x; this.y = y; this.z = z; this.w = w; }
        public Vec4i(long x, long y, long z, long w) { this.x = unchecked((int)x); this.y = unchecked((int)y); this.z = unchecked((int)z); this.w = unchecked((int)w); }

        public static readonly Vec4i ZERO = new Vec4i(0, 0, 0, 0);
        public static readonly Vec4i ONE = new Vec4i(1, 1, 1, 1);
        public static readonly Vec4i MIN = new Vec4i(int.MinValue, int.MinValue, int.MinValue, int.MinValue);
        public static readonly Vec4i MAX = new Vec4i(int.MaxValue, int.MaxValue, int.MaxValue, int.MaxValue);

        public int this[int axis]
        {
            get
            {
                switch (axis) { case 0: return x; case 1: return y; case 2: return z; case 3: return w; }
                throw new IndexOutOfRangeException("Vector4i index " + axis);
            }
            set
            {
                switch (axis) { case 0: x = value; return; case 1: y = value; return; case 2: z = value; return; case 3: w = value; return; }
                throw new IndexOutOfRangeException("Vector4i index " + axis);
            }
        }

        public static Vec4i operator +(Vec4i a, Vec4i b) => new Vec4i(unchecked(a.x + b.x), unchecked(a.y + b.y), unchecked(a.z + b.z), unchecked(a.w + b.w));
        public static Vec4i operator -(Vec4i a, Vec4i b) => new Vec4i(unchecked(a.x - b.x), unchecked(a.y - b.y), unchecked(a.z - b.z), unchecked(a.w - b.w));
        public static Vec4i operator *(Vec4i a, Vec4i b) => new Vec4i(unchecked(a.x * b.x), unchecked(a.y * b.y), unchecked(a.z * b.z), unchecked(a.w * b.w));
        public static Vec4i operator /(Vec4i a, Vec4i b) => new Vec4i(a.x / b.x, a.y / b.y, a.z / b.z, a.w / b.w);
        public static Vec4i operator %(Vec4i a, Vec4i b) => new Vec4i(a.x % b.x, a.y % b.y, a.z % b.z, a.w % b.w);
        public static Vec4i operator *(Vec4i a, long s) { int i = unchecked((int)s); return new Vec4i(unchecked(a.x * i), unchecked(a.y * i), unchecked(a.z * i), unchecked(a.w * i)); }
        public static Vec4i operator *(long s, Vec4i a) => a * s;
        public static Vec4i operator /(Vec4i a, long s) { int i = unchecked((int)s); return new Vec4i(a.x / i, a.y / i, a.z / i, a.w / i); }
        public static Vec4i operator %(Vec4i a, long s) { int i = unchecked((int)s); return new Vec4i(a.x % i, a.y % i, a.z % i, a.w % i); }
        public static Vec4 operator *(Vec4i a, double s) => (Vec4)a * s;
        public static Vec4 operator *(double s, Vec4i a) => (Vec4)a * s;
        public static Vec4 operator /(Vec4i a, double s) => (Vec4)a / s;
        public static Vec4i operator -(Vec4i a) => new Vec4i(unchecked(-a.x), unchecked(-a.y), unchecked(-a.z), unchecked(-a.w));
        public static Vec4i operator +(Vec4i a) => a;
        public static bool operator ==(Vec4i a, Vec4i b) => a.x == b.x && a.y == b.y && a.z == b.z && a.w == b.w;
        public static bool operator !=(Vec4i a, Vec4i b) => !(a == b);
        public static bool operator <(Vec4i a, Vec4i b)
        {
            if (a.x == b.x)
            {
                if (a.y == b.y) return a.z == b.z ? a.w < b.w : a.z < b.z;
                return a.y < b.y;
            }
            return a.x < b.x;
        }
        public static bool operator >(Vec4i a, Vec4i b) => b < a;
        public static bool operator <=(Vec4i a, Vec4i b) => !(b < a);
        public static bool operator >=(Vec4i a, Vec4i b) => !(a < b);
        public int CompareTo(Vec4i o) => this < o ? -1 : (o < this ? 1 : 0);
        public bool Equals(Vec4i o) => this == o;
        public override bool Equals(object o) => o is Vec4i v && this == v;
        public override int GetHashCode() => unchecked((int)GodotHash());
        public override string ToString() => "(" + GFormat.Itos(x) + ", " + GFormat.Itos(y) + ", " + GFormat.Itos(z) + ", " + GFormat.Itos(w) + ")";

        public int MinAxisIndex()
        {
            int minIndex = 0, minValue = x;
            for (int i = 1; i < 4; i++)
                if (this[i] <= minValue) { minIndex = i; minValue = this[i]; }
            return minIndex;
        }

        public int MaxAxisIndex()
        {
            int maxIndex = 0, maxValue = x;
            for (int i = 1; i < 4; i++)
                if (this[i] > maxValue) { maxIndex = i; maxValue = this[i]; }
            return maxIndex;
        }

        public long LengthSquared() => x * (long)x + y * (long)y + z * (long)z + w * (long)w;
        public double Length() => Math.Sqrt((double)LengthSquared());
        public double DistanceTo(Vec4i to) => (to - this).Length();
        public long DistanceSquaredTo(Vec4i to) => (to - this).LengthSquared();
        public Vec4i Abs() => new Vec4i(GD.AbsInt(x), GD.AbsInt(y), GD.AbsInt(z), GD.AbsInt(w));
        public Vec4i Sign() => new Vec4i(GD.SignI(x), GD.SignI(y), GD.SignI(z), GD.SignI(w));
        public Vec4i Clamp(Vec4i min, Vec4i max) => new Vec4i(GD.ClampInt(x, min.x, max.x), GD.ClampInt(y, min.y, max.y), GD.ClampInt(z, min.z, max.z), GD.ClampInt(w, min.w, max.w));
        public Vec4i Clampi(long min, long max)
        {
            int lo = unchecked((int)min), hi = unchecked((int)max);
            return new Vec4i(GD.ClampInt(x, lo, hi), GD.ClampInt(y, lo, hi), GD.ClampInt(z, lo, hi), GD.ClampInt(w, lo, hi));
        }
        public Vec4i Snapped(Vec4i s) => new Vec4i((int)GD.Snapped(x, s.x), (int)GD.Snapped(y, s.y), (int)GD.Snapped(z, s.z), (int)GD.Snapped(w, s.w));
        public Vec4i Snappedi(long step)
        {
            int s = unchecked((int)step);
            return new Vec4i((int)GD.Snapped(x, s), (int)GD.Snapped(y, s), (int)GD.Snapped(z, s), (int)GD.Snapped(w, s));
        }
        public Vec4i Min(Vec4i o) => new Vec4i(x < o.x ? x : o.x, y < o.y ? y : o.y, z < o.z ? z : o.z, w < o.w ? w : o.w);
        public Vec4i Max(Vec4i o) => new Vec4i(x > o.x ? x : o.x, y > o.y ? y : o.y, z > o.z ? z : o.z, w > o.w ? w : o.w);
        public Vec4i Mini(long s) { int i = unchecked((int)s); return new Vec4i(x < i ? x : i, y < i ? y : i, z < i ? z : i, w < i ? w : i); }
        public Vec4i Maxi(long s) { int i = unchecked((int)s); return new Vec4i(x > i ? x : i, y > i ? y : i, z > i ? z : i, w > i ? w : i); }

        // ---- Variant
        public static implicit operator Var(Vec4i v) => Var.Of(v);
        public static explicit operator Vec4i(Var v)
        {
            object o = v.Obj;
            if (o is Vec4i a) return a;
            if (o is Vec4 b) return (Vec4i)b;
            return default;
        }
        public int GodotType => GD.TYPE_VECTOR4I;
        public string GodotStr() => ToString();
        public bool GodotIsZero => x == 0 && y == 0 && z == 0 && w == 0;
        public uint GodotHash()
        {
            uint h = GHashing.Murmur3One32(unchecked((uint)x));
            h = GHashing.Murmur3One32(unchecked((uint)y), h);
            h = GHashing.Murmur3One32(unchecked((uint)z), h);
            h = GHashing.Murmur3One32(unchecked((uint)w), h);
            return GHashing.Fmix32(h);
        }

        public bool GodotOp(char op, Var other, bool selfLeft, out Var result)
        {
            result = Var.Nil;
            if (op == 'n') { result = -this; return true; }
            object o = other.Obj;
            if (o is Vec4i b)
            {
                Vec4i l = selfLeft ? this : b, r = selfLeft ? b : this;
                switch (op)
                {
                    case '+': result = l + r; return true;
                    case '-': result = l - r; return true;
                    case '*': result = l * r; return true;
                    case '/':
                    case '%':
                        if (r.x == 0 || r.y == 0 || r.z == 0 || r.w == 0) { GD.PushError("Division by zero error in operator '" + op + "'."); result = default(Vec4i); return true; }
                        result = op == '/' ? l / r : l % r;
                        return true;
                }
                return false;
            }
            if (other.IsInt)
            {
                long s = other.AsLong();
                if (op == '*') { result = this * s; return true; }
                if (!selfLeft) return false;
                if (op == '/' || op == '%')
                {
                    if (s == 0) { GD.PushError("Division by zero error in operator '" + op + "'."); result = default(Vec4i); return true; }
                    result = op == '/' ? this / s : this % s;
                    return true;
                }
                return false;
            }
            if (other.IsFloat)
            {
                double s = other.AsFloat();
                if (op == '*') { result = this * s; return true; }
                if (op == '/' && selfLeft)
                {
                    if (s == 0) { GD.PushError("Division by zero error in operator '/'."); result = new Vec4(); return true; }
                    result = this / s;
                    return true;
                }
            }
            return false;
        }
    }
}
