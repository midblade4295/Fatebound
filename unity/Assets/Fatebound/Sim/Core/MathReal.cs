// Fatebound (Unity port): the real_t (float) side of Godot's Math:: (core/math/math_funcs.h), shared by the vector,
// Basis, Quaternion, Transform, AABB, Plane and Projection ports (Vec2Godot.cs, Vec3Godot.cs, Basis.cs, Xform3.cs,
// Projection.cs). Each helper is the float overload Godot's C++ calls when real_t is float -- float arithmetic, the C
// library's float functions (MathF -> sinf/cosf/atan2f...), and Godot's MIN/MAX/CLAMP/SIGN templates (NaN falls
// through to the second operand / 0, unlike Math.Min).
using System;

namespace Fatebound.Sim
{
    /// <summary>Godot's EulerOrder (GDScript's EULER_ORDER_XYZ ... EULER_ORDER_ZYX).</summary>
    public enum EulerOrder { XYZ = 0, XZY = 1, YXZ = 2, YZX = 3, ZXY = 4, ZYX = 5 }

    public static partial class GD
    {
        /// <summary>Godot's MATH_CHECKS (on in debug and editor builds, where GDScript runs during development): the
        /// argument checks in normalize-requiring methods (slide/reflect with a non-normalized normal, Basis(axis, angle)
        /// with a non-normalized axis, Quaternion.slerp of non-unit quaternions...) report an error and return Godot's
        /// fallback value. False gives a release export's behaviour (no check, the raw formula).</summary>
        public static bool MathChecks = true;

        public const int EULER_ORDER_XYZ = 0, EULER_ORDER_XZY = 1, EULER_ORDER_YXZ = 2, EULER_ORDER_YZX = 3,
            EULER_ORDER_ZXY = 4, EULER_ORDER_ZYX = 5;
        public const double SQRT12 = 0.7071067811865475244008443621048490;
        public const double UNIT_EPSILON = 0.001;
        public const double CMP_EPSILON2 = CMP_EPSILON * CMP_EPSILON;

        internal const float EPS_F = (float)CMP_EPSILON;
        internal const float UNIT_EPS_F = (float)UNIT_EPSILON;

        public static bool IsEqualApproxF(float a, float b)
        {
            if (a == b) return true;
            float tolerance = EPS_F * MathF.Abs(a);
            if (tolerance < EPS_F) tolerance = EPS_F;
            return MathF.Abs(a - b) < tolerance;
        }

        public static bool IsEqualApproxF(float a, float b, float tolerance)
        {
            if (a == b) return true;
            return MathF.Abs(a - b) < tolerance;
        }

        public static bool IsZeroApproxF(float v) => MathF.Abs(v) < EPS_F;
        public static bool IsFiniteF(float v) => !float.IsNaN(v) && !float.IsInfinity(v);
        public static bool IsSameF(float a, float b) => a == b || (float.IsNaN(a) && float.IsNaN(b));

        /// <summary>Godot's SIGN template (NaN gives 0).</summary>
        public static float SignF(float v) => v > 0 ? 1f : (v < 0 ? -1f : 0f);
        public static int SignI(int v) => v > 0 ? 1 : (v < 0 ? -1 : 0);
        /// <summary>Godot's MIN / MAX / CLAMP templates (a &lt; b ? a : b ...).</summary>
        public static float MinF(float a, float b) => a < b ? a : b;
        public static float MaxF(float a, float b) => a > b ? a : b;
        public static float ClampF(float v, float lo, float hi) => v < lo ? lo : (v > hi ? hi : v);
        public static int ClampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
        /// <summary>std::abs on int32 (abs(INT32_MIN) stays INT32_MIN instead of throwing).</summary>
        public static int AbsInt(int v) => v < 0 ? unchecked(-v) : v;

        public static float FposmodF(float x, float y)
        {
            float value = x % y;      // (C#'s float % is C's fmodf)
            if ((value < 0 && y > 0) || (value > 0 && y < 0)) value += y;
            value += 0.0f;
            return value;
        }

        public static float FposmodpF(float x, float y)
        {
            float value = x % y;
            if (value < 0) value += y;
            value += 0.0f;
            return value;
        }

        public static float LerpF(float from, float to, float w) => from + (to - from) * w;

        public static float BezierInterpolateF(float start, float c1, float c2, float end, float t)
        {
            float omt = 1.0f - t;
            float omt2 = omt * omt;
            float omt3 = omt2 * omt;
            float t2 = t * t;
            float t3 = t2 * t;
            return start * omt3 + c1 * omt2 * t * 3.0f + c2 * omt * t2 * 3.0f + end * t3;
        }

        public static float BezierDerivativeF(float start, float c1, float c2, float end, float t)
        {
            float omt = 1.0f - t;
            float omt2 = omt * omt;
            float t2 = t * t;
            return (c1 - start) * 3.0f * omt2 + (c2 - c1) * 6.0f * omt * t + (end - c2) * 3.0f * t2;
        }

        public static float CubicInterpolateInTimeF(float from, float to, float pre, float post, float weight, float toT, float preT, float postT)
        {
            float t = LerpF(0.0f, toT, weight);
            float a1 = LerpF(pre, from, preT == 0 ? 0.0f : (t - preT) / -preT);
            float a2 = LerpF(from, to, toT == 0 ? 0.5f : t / toT);
            float a3 = LerpF(to, post, postT - toT == 0 ? 1.0f : (t - toT) / (postT - toT));
            float b1 = LerpF(a1, a2, toT - preT == 0 ? 0.0f : (t - preT) / (toT - preT));
            float b2 = LerpF(a2, a3, postT == 0 ? 1.0f : t / postT);
            return LerpF(b1, b2, toT == 0 ? 0.5f : t / toT);
        }

        /// <summary>Math::acos / asin on float: clamped to [-1, 1] first.</summary>
        public static float AcosF(float x) => x < -1 ? (float)PI : (x > 1 ? 0f : MathF.Acos(x));
        public static float AsinF(float x) => x < -1 ? (-(float)PI / 2) : (x > 1 ? ((float)PI / 2) : MathF.Asin(x));

        public static float RadToDegF(float r) => r * (180.0f / (float)PI);
        public static float DegToRadF(float d) => d * ((float)PI / 180.0f);

        /// <summary>Math::lerp_angle on float (Transform2D.interpolate_with).</summary>
        public static float LerpAngleF(float from, float to, float w)
        {
            float difference = (to - from) % (float)TAU;
            float diff = (2.0f * difference) % (float)TAU - difference;
            return from + diff * w;
        }

        /// <summary>Math::snapped (double only in Godot: real_t arguments widen, the result narrows back).</summary>
        internal static float SnappedF(float v, float step) => (float)Snapped(v, step);

        /// <summary>A MATH_CHECKS / ERR_FAIL message, Godot-style.</summary>
        internal static void MathError(string msg) => PushError(msg);
    }
}
