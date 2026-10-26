// Godot's Geometry2D (core/math/geometry_2d.h), the parts the sim and the land use -- float (real_t) arithmetic.
using System.Collections.Generic;

namespace Fatebound.Sim
{
    public static class Geometry2D
    {
        const float EPS = 0.00001f;

        static bool IsEqualApproxF(float a, float b)
        {
            if (a == b) return true;
            float tol = EPS * System.Math.Abs(a);
            if (tol < EPS) tol = EPS;
            return System.Math.Abs(a - b) < tol;
        }

        public static bool SegmentIntersectsSegment(Vec2 fromA, Vec2 toA, Vec2 fromB, Vec2 toB, out Vec2 result)
        {
            result = Vec2.Zero;
            Vec2 B = toA - fromA;
            Vec2 C = fromB - fromA;
            Vec2 D = toB - fromA;
            float ABlen = B.Dot(B);
            if (ABlen <= 0) return false;
            Vec2 Bn = new Vec2(B.x / ABlen, B.y / ABlen);
            C = new Vec2(C.x * Bn.x + C.y * Bn.y, C.y * Bn.x - C.x * Bn.y);
            D = new Vec2(D.x * Bn.x + D.y * Bn.y, D.y * Bn.x - D.x * Bn.y);
            if ((C.y < -EPS && D.y < -EPS) || (C.y > EPS && D.y > EPS)) return false;
            if (IsEqualApproxF(C.y, D.y)) return false;
            float ABpos = D.x + (C.x - D.x) * D.y / (D.y - C.y);
            if (ABpos < 0 || ABpos > 1) return false;
            result = new Vec2(fromA.x + B.x * ABpos, fromA.y + B.y * ABpos);
            return true;
        }

        public static bool IsPointInPolygon(Vec2 point, IReadOnlyList<Vec2> poly)
        {
            int c = poly.Count;
            if (c < 3) return false;
            Vec2 far = new Vec2(-1e20f, -1e20f);
            Vec2 opp = new Vec2(1e20f, 1e20f);
            for (int i = 0; i < c; i++)
            {
                Vec2 q = poly[i];
                far = new Vec2(System.Math.Max(far.x, q.x), System.Math.Max(far.y, q.y));
                opp = new Vec2(System.Math.Min(opp.x, q.x), System.Math.Min(opp.y, q.y));
            }
            Vec2 span = far - opp;
            far = far + new Vec2(span.x * 1.221313f, span.y * 1.512312f);
            int inter = 0;
            for (int i = 0; i < c; i++)
            {
                if (SegmentIntersectsSegment(poly[i], poly[(i + 1) % c], point, far, out Vec2 res))
                {
                    inter++;
                    if (IsEqualApproxF(res.x, point.x) && IsEqualApproxF(res.y, point.y)) return true;
                }
            }
            return (inter & 1) == 1;
        }
    }
}
