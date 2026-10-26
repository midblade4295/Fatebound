// `guitest math`: Godot's math value types as ported (Sim/Core: Vec2/Vec2i/Vec3/Vec3i/Vec4/Vec4i, Basis, Quat, Xform3,
// Aabb, Plane, Projection; GUI/Core: Rect2, Col, Xform2) printing the same cases as tools/parity/godot_math.gd, line for
// line -- tools/parity/math.sh diffs the two. Written the way ported GDScript calls the API (where an older member of the
// GUI types differs from Godot, the *Exact / From* member that matches GDScript is the one called; see Math2DGodot.cs).
using System;
using System.Collections.Generic;
using Fatebound.GUI;
using Fatebound.Sim;

namespace GuiTest
{
    public static class MathTest
    {
        static void p(string k, Var v) => Console.WriteLine(k + "|" + GD.Str(v));
        static string F(string fmt, params Var[] a) => GD.Fmt(fmt, a);
        static GArray A(params Var[] items) => GArray.Of(items);
        const double PI = GD.PI;

        static readonly Vec2[] V2 = { new Vec2(0, 0), new Vec2(1, 0), new Vec2(3, -4), new Vec2(0.1, 0.2), new Vec2(-2.5, 7.25), new Vec2(1e-6, -1e-6), new Vec2(0.6, 0.8), new Vec2(-1, -1) };
        static readonly Vec3[] V3 = { new Vec3(0, 0, 0), new Vec3(1, 0, 0), new Vec3(0, 1, 0), new Vec3(1, 2, 3), new Vec3(-0.5, 0.25, 2), new Vec3(0.1, 0.2, 0.3),
            new Vec3(1e-6, 0, -1e-6), new Vec3(0.6, 0, 0.8), new Vec3(-3, 4, -12), new Vec3(0, 0, -1) };
        static readonly Vec3[] EUL = { new Vec3(0, 0, 0), new Vec3(0.1, 0.2, 0.3), new Vec3(1.0, -2.0, 3.0), new Vec3(PI / 2, 0.3, 0.2), new Vec3(-PI / 2, 0.1, 0),
            new Vec3(0.3, PI / 2, 0.2), new Vec3(0.2, 0.1, -PI / 2), new Vec3(0.5, 0, 0), new Vec3(0, 0.7, 0), new Vec3(0, PI, 0), new Vec3(PI, 0, 0), new Vec3(-1.2, 0.4, 2.9) };

        public static void Run()
        {
            Vec2Cases();
            Vec2iCases();
            Vec3Cases();
            Vec34iCases();
            BasisCases();
            QuatCases();
            Xform3Cases();
            AabbCases();
            PlaneCases();
            ProjectionCases();
            Xform2Cases();
            Rect2Cases();
            ColorCases();
            VariantCases();
            EdgeCases();
        }

        static void Vec2Cases()
        {
            for (int i = 0; i < V2.Length; i++)
            {
                Vec2 a = V2[i];
                string k = F("v2.%d.", i);
                p(k + "len", a.Length()); p(k + "lsq", a.LengthSquared()); p(k + "ang", a.Angle()); p(k + "asp", a.Aspect());
                p(k + "norm", a.Normalized()); p(k + "isn", a.IsNormalized()); p(k + "zap", a.IsZeroApprox()); p(k + "fin", a.IsFinite());
                p(k + "abs", a.Abs()); p(k + "ceil", a.Ceil()); p(k + "floor", a.Floor()); p(k + "round", a.Round()); p(k + "sign", a.Sign());
                p(k + "orth", a.Orthogonal()); p(k + "rot", a.Rotated(0.3)); p(k + "rot2", a.Rotated(-2.0)); p(k + "lim", a.LimitLength(1.5)); p(k + "lim1", a.LimitLength());
                p(k + "clampf", a.Clampf(-1, 1)); p(k + "clamp", a.Clamp(new Vec2(-0.5, -0.5), new Vec2(0.5, 2))); p(k + "snap", a.Snapped(new Vec2(0.25, 0.1)));
                p(k + "snapf", a.Snappedf(0.3)); p(k + "posmod", a.Posmod(0.7)); p(k + "posmodv", a.Posmodv(new Vec2(0.3, -0.4)));
                p(k + "maxi", a.MaxAxisIndex()); p(k + "mini", a.MinAxisIndex()); p(k + "minf", a.Minf(0.5)); p(k + "maxf", a.Maxf(0.5));
                p(k + "neg", -a); p(k + "pos", +a); p(k + "m2", a * 2); p(k + "m25", a * 2.5); p(k + "lm25", 2.5 * a); p(k + "d3", a / 3.0); p(k + "di3", a / 3);
                p(k + "hash", GD.Hash(a)); p(k + "fromang", Vec2.FromAngle(a.x));
                for (int j = 0; j < V2.Length; j++)
                {
                    Vec2 b = V2[j];
                    Vec2 n = b.Normalized();
                    string kk = k + F("%d.", j);
                    p(kk + "dot", a.Dot(b)); p(kk + "cross", a.Cross(b)); p(kk + "dist", a.DistanceTo(b)); p(kk + "dsq", a.DistanceSquaredTo(b));
                    p(kk + "angto", a.AngleTo(b)); p(kk + "angpt", a.AngleToPoint(b)); p(kk + "dir", a.DirectionTo(b)); p(kk + "lerp", a.Lerp(b, 0.3));
                    p(kk + "slerp", a.Slerp(b, 0.3)); p(kk + "slerp3", a.Slerp(b, 1.0 / 3.0)); p(kk + "mt", a.MoveToward(b, 0.5)); p(kk + "proj", a.Project(b));
                    p(kk + "min", a.Min(b)); p(kk + "max", a.Max(b)); p(kk + "mul", a * b); p(kk + "div", a / b); p(kk + "add", a + b); p(kk + "sub", a - b);
                    p(kk + "iea", a.IsEqualApprox(b)); p(kk + "lt", a < b); p(kk + "le", a <= b); p(kk + "eq", a == b);
                    p(kk + "cub", a.CubicInterpolate(b, V2[(j + 1) % V2.Length], V2[(j + 2) % V2.Length], 0.4));
                    p(kk + "cubt", a.CubicInterpolateInTime(b, V2[(j + 1) % V2.Length], V2[(j + 2) % V2.Length], 0.4, 1.0, -0.5, 2.0));
                    p(kk + "bez", a.BezierInterpolate(V2[(j + 3) % V2.Length], V2[(j + 5) % V2.Length], b, 0.3));
                    p(kk + "bezd", a.BezierDerivative(V2[(j + 3) % V2.Length], V2[(j + 5) % V2.Length], b, 0.3));
                    p(kk + "slide", a.Slide(n)); p(kk + "refl", a.Reflect(n)); p(kk + "bnc", a.Bounce(n));
                }
            }
        }

        static void Vec2iCases()
        {
            Vec2i[] VI = { new Vec2i(0, 0), new Vec2i(3, -4), new Vec2i(-7, 2), new Vec2i(5, 5), new Vec2i(1, 0), new Vec2i(-2147483648, 7) };
            for (int i = 0; i < VI.Length; i++)
            {
                Vec2i a = VI[i];
                string k = F("v2i.%d.", i);
                p(k + "len", a.Length()); p(k + "lsq", a.LengthSquared()); p(k + "asp", a.Aspect()); p(k + "abs", a.Abs()); p(k + "sign", a.Sign());
                p(k + "clamp", a.Clamp(new Vec2i(-3, -3), new Vec2i(4, 1))); p(k + "clampi", a.Clampi(-2, 3)); p(k + "snap", a.Snapped(new Vec2i(3, 2))); p(k + "snapi", a.Snappedi(4));
                p(k + "mini", a.Mini(1)); p(k + "maxi", a.Maxi(1)); p(k + "maxax", a.MaxAxisIndex()); p(k + "minax", a.MinAxisIndex());
                p(k + "neg", -a); p(k + "m3", a * 3); p(k + "m25", a * 2.5); p(k + "lm3", 3 * a); p(k + "d2", a / 2); p(k + "mod3", a % 3); p(k + "df", a / 2.0);
                p(k + "hash", GD.Hash(a)); p(k + "tov2", (Vec2)a); p(k + "fromv2", (Vec2i)((Vec2)a * 0.7));
                for (int j = 0; j < VI.Length; j++)
                {
                    Vec2i b = VI[j];
                    string kk = k + F("%d.", j);
                    p(kk + "add", a + b); p(kk + "sub", a - b); p(kk + "mul", a * b); p(kk + "min", a.Min(b)); p(kk + "max", a.Max(b));
                    p(kk + "dist", a.DistanceTo(b)); p(kk + "dsq", a.DistanceSquaredTo(b)); p(kk + "lt", a < b);
                    if (b.x != 0 && b.y != 0) { p(kk + "div", a / b); p(kk + "mod", a % b); }
                }
            }
        }

        static void Vec3Cases()
        {
            for (int i = 0; i < V3.Length; i++)
            {
                Vec3 a = V3[i];
                string k = F("v3.%d.", i);
                p(k + "str", a); p(k + "len", a.Length()); p(k + "lsq", a.LengthSquared()); p(k + "norm", a.NormalizedChecked()); p(k + "isn", a.IsNormalized());
                p(k + "zap", a.IsZeroApprox()); p(k + "fin", a.IsFinite()); p(k + "inv", a.Inverse()); p(k + "abs", a.Abs()); p(k + "ceil", a.Ceil());
                p(k + "floor", a.Floor()); p(k + "round", a.Round()); p(k + "sign", a.Sign()); p(k + "lim", a.LimitLength(1.5)); p(k + "lim1", a.LimitLength());
                p(k + "clampf", a.Clampf(-1, 1)); p(k + "clamp", a.Clamp(new Vec3(-0.5, -0.5, 0), new Vec3(0.5, 2, 1))); p(k + "snap", a.Snapped(new Vec3(0.25, 0.1, 2)));
                p(k + "snapf", a.Snappedf(0.3)); p(k + "posmod", a.Posmod(0.7)); p(k + "posmodv", a.Posmodv(new Vec3(0.3, -0.4, 5)));
                p(k + "maxi", a.MaxAxisIndex()); p(k + "mini", a.MinAxisIndex()); p(k + "minf", a.Minf(0.5)); p(k + "maxf", a.Maxf(0.5));
                p(k + "neg", -a); p(k + "pos", +a); p(k + "m2", a * 2); p(k + "m25", a * 2.5); p(k + "lm25", 2.5 * a); p(k + "d3", a / 3.0); p(k + "di3", a / 3);
                p(k + "hash", GD.Hash(a)); p(k + "oct", a.OctahedronEncode()); p(k + "octd", Vec3.OctahedronDecode(a.OctahedronEncode()));
                p(k + "octd2", Vec3.OctahedronDecode(new Vec2(a.x, a.y)));
                foreach (var ax in new[] { new Vec3(0, 1, 0), new Vec3(1, 2, 3).NormalizedChecked(), new Vec3(1, 1, 0) })
                    p(k + "rotax", a.Rotated(ax, 0.7));
                for (int j = 0; j < V3.Length; j++)
                {
                    Vec3 b = V3[j];
                    Vec3 n = b.NormalizedChecked();
                    string kk = k + F("%d.", j);
                    p(kk + "dot", a.Dot(b)); p(kk + "cross", a.Cross(b)); p(kk + "dist", a.DistanceTo(b)); p(kk + "dsq", a.DistanceSquaredTo(b));
                    p(kk + "angto", a.AngleTo(b)); p(kk + "sang", a.SignedAngleTo(b, new Vec3(0, 1, 0))); p(kk + "dir", a.DirectionTo(b));
                    p(kk + "lerp", a.Lerp(b, 0.3)); p(kk + "slerp", a.Slerp(b, 0.3)); p(kk + "slerp3", a.Slerp(b, 1.0 / 3.0)); p(kk + "mt", a.MoveToward(b, 0.5));
                    p(kk + "proj", a.Project(b)); p(kk + "min", a.Min(b)); p(kk + "max", a.Max(b)); p(kk + "mul", a * b); p(kk + "div", a / b);
                    p(kk + "add", a + b); p(kk + "sub", a - b); p(kk + "iea", a.IsEqualApprox(b)); p(kk + "lt", a < b); p(kk + "le", a <= b); p(kk + "eq", a == b);
                    p(kk + "outer", a.Outer(b));
                    p(kk + "cub", a.CubicInterpolate(b, V3[(j + 1) % V3.Length], V3[(j + 2) % V3.Length], 0.4));
                    p(kk + "cubt", a.CubicInterpolateInTime(b, V3[(j + 1) % V3.Length], V3[(j + 2) % V3.Length], 0.4, 1.0, -0.5, 2.0));
                    p(kk + "bez", a.BezierInterpolate(V3[(j + 3) % V3.Length], V3[(j + 5) % V3.Length], b, 0.3));
                    p(kk + "bezd", a.BezierDerivative(V3[(j + 3) % V3.Length], V3[(j + 5) % V3.Length], b, 0.3));
                    p(kk + "slide", a.Slide(n)); p(kk + "refl", a.Reflect(n)); p(kk + "bnc", a.Bounce(n));
                }
            }
        }

        static void Vec34iCases()
        {
            Vec3i[] VI = { new Vec3i(0, 0, 0), new Vec3i(3, -4, 5), new Vec3i(-7, 2, -1), new Vec3i(5, 5, 5), new Vec3i(1, 0, 2) };
            for (int i = 0; i < VI.Length; i++)
            {
                Vec3i a = VI[i];
                string k = F("v3i.%d.", i);
                p(k + "str", a); p(k + "len", a.Length()); p(k + "lsq", a.LengthSquared()); p(k + "abs", a.Abs()); p(k + "sign", a.Sign());
                p(k + "clamp", a.Clamp(new Vec3i(-3, -3, -3), new Vec3i(4, 1, 2))); p(k + "clampi", a.Clampi(-2, 3)); p(k + "snap", a.Snapped(new Vec3i(3, 2, 4))); p(k + "snapi", a.Snappedi(4));
                p(k + "mini", a.Mini(1)); p(k + "maxi", a.Maxi(1)); p(k + "maxax", a.MaxAxisIndex()); p(k + "minax", a.MinAxisIndex());
                p(k + "neg", -a); p(k + "m3", a * 3); p(k + "m25", a * 2.5); p(k + "lm3", 3 * a); p(k + "lm25", 2.5 * a); p(k + "d2", a / 2); p(k + "mod3", a % 3); p(k + "df", a / 2.0);
                p(k + "hash", GD.Hash(a)); p(k + "tov3", (Vec3)a); p(k + "fromv3", (Vec3i)((Vec3)a * 0.7)); p(k + "type", GD.TypeOf(a));
                for (int j = 0; j < VI.Length; j++)
                {
                    Vec3i b = VI[j];
                    string kk = k + F("%d.", j);
                    p(kk + "add", a + b); p(kk + "sub", a - b); p(kk + "mul", a * b); p(kk + "min", a.Min(b)); p(kk + "max", a.Max(b));
                    p(kk + "dist", a.DistanceTo(b)); p(kk + "dsq", a.DistanceSquaredTo(b)); p(kk + "lt", a < b); p(kk + "eq", a == b);
                    if (b.x != 0 && b.y != 0 && b.z != 0) { p(kk + "div", a / b); p(kk + "mod", a % b); }
                }
            }
            Vec4[] V4 = { new Vec4(0, 0, 0, 0), new Vec4(1, -2, 3.5, 0.25), new Vec4(0.1, 0.2, 0.3, 0.4), new Vec4(-1, -1, 2, 2), new Vec4(1e-6, 0, 0, -1e-6) };
            for (int i = 0; i < V4.Length; i++)
            {
                Vec4 a = V4[i];
                string k = F("v4.%d.", i);
                p(k + "str", a); p(k + "len", a.Length()); p(k + "lsq", a.LengthSquared()); p(k + "norm", a.Normalized()); p(k + "isn", a.IsNormalized());
                p(k + "abs", a.Abs()); p(k + "sign", a.Sign()); p(k + "floor", a.Floor()); p(k + "ceil", a.Ceil()); p(k + "round", a.Round()); p(k + "inv", a.Inverse());
                p(k + "maxax", a.MaxAxisIndex()); p(k + "minax", a.MinAxisIndex()); p(k + "snapf", a.Snappedf(0.3)); p(k + "posmod", a.Posmod(0.7));
                p(k + "clampf", a.Clampf(-1, 1)); p(k + "neg", -a); p(k + "m25", a * 2.5); p(k + "lm2", 2 * a); p(k + "d3", a / 3.0); p(k + "hash", GD.Hash(a)); p(k + "zap", a.IsZeroApprox());
                p(k + "minf", a.Minf(0.2)); p(k + "maxf", a.Maxf(0.2));
                for (int j = 0; j < V4.Length; j++)
                {
                    Vec4 b = V4[j];
                    string kk = k + F("%d.", j);
                    p(kk + "dot", a.Dot(b)); p(kk + "dist", a.DistanceTo(b)); p(kk + "dir", a.DirectionTo(b)); p(kk + "lerp", a.Lerp(b, 0.3));
                    p(kk + "cub", a.CubicInterpolate(b, V4[(j + 1) % V4.Length], V4[(j + 2) % V4.Length], 0.4));
                    p(kk + "cubt", a.CubicInterpolateInTime(b, V4[(j + 1) % V4.Length], V4[(j + 2) % V4.Length], 0.4, 1.0, -0.5, 2.0));
                    p(kk + "add", a + b); p(kk + "mul", a * b); p(kk + "div", a / b); p(kk + "lt", a < b); p(kk + "posmodv", a.Posmodv(b)); p(kk + "snap", a.Snapped(b));
                    p(kk + "clamp", a.Clamp(b, b + new Vec4(1, 1, 1, 1))); p(kk + "min", a.Min(b)); p(kk + "max", a.Max(b)); p(kk + "iea", a.IsEqualApprox(b));
                }
            }
            Vec4i[] V4I = { new Vec4i(0, 0, 0, 0), new Vec4i(1, -2, 3, 4), new Vec4i(-5, 6, -7, 8) };
            for (int i = 0; i < V4I.Length; i++)
            {
                Vec4i a = V4I[i];
                string k = F("v4i.%d.", i);
                p(k + "str", a); p(k + "len", a.Length()); p(k + "abs", a.Abs()); p(k + "sign", a.Sign()); p(k + "m25", a * 2.5); p(k + "m3", a * 3); p(k + "lm3", 3 * a);
                p(k + "hash", GD.Hash(a)); p(k + "maxax", a.MaxAxisIndex()); p(k + "minax", a.MinAxisIndex()); p(k + "snapi", a.Snappedi(3)); p(k + "clampi", a.Clampi(-3, 3));
                for (int j = 0; j < V4I.Length; j++)
                {
                    Vec4i b = V4I[j];
                    p(k + F("%d.add", j), a + b); p(k + F("%d.mul", j), a * b); p(k + F("%d.lt", j), a < b); p(k + F("%d.dsq", j), a.DistanceSquaredTo(b));
                }
            }
        }

        static List<Basis> MakeBases()
        {
            var B = new List<Basis> { Basis.IDENTITY, Basis.FLIP_X, Basis.FromScale(new Vec3(2, -1, 0.5)), new Basis(new Vec3(1, 2, 3), new Vec3(4, 5, 6), new Vec3(7, 8, 10)),
                new Basis(new Vec3(1, 2, 3), new Vec3(2, 4, 6), new Vec3(0, 0, 1)), new Basis(new Vec3(0, 1, 0), 0.7), new Basis(new Vec3(1, 2, 3).NormalizedChecked(), -2.1),
                new Basis(new Vec3(1, 1, 0), 0.5), new Basis(new Quat(0.1, 0.2, 0.3, 0.9)), Basis.FromScale(new Vec3(1.5, 1.5, 1.5)) * Basis.FromEuler(new Vec3(0.3, -0.2, 1.1)) };
            foreach (var e in EUL) B.Add(Basis.FromEuler(e));
            B.Add(Basis.FromEuler(new Vec3(0.4, 0.5, 0.6), EulerOrder.ZXY) * Basis.FromScale(new Vec3(-1, 2, 3)));
            return B;
        }

        static void BasisCases()
        {
            for (int e = 0; e < EUL.Length; e++)
                for (int o = 0; o < 6; o++)
                {
                    Basis b = Basis.FromEuler(EUL[e], (EulerOrder)o);
                    string k = F("be.%d.%d.", e, o);
                    p(k + "b", b);
                    for (int o2 = 0; o2 < 6; o2++) p(k + F("ge%d", o2), b.GetEuler((EulerOrder)o2));
                }
            var B = MakeBases();
            for (int i = 0; i < B.Count; i++)
            {
                Basis b = B[i];
                string k = F("b.%d.", i);
                p(k + "str", b); p(k + "det", b.Determinant()); p(k + "inv", b.Inverse()); p(k + "tr", b.Transposed()); p(k + "orth", b.Orthonormalized());
                p(k + "scale", b.GetScale()); p(k + "rq", b.GetRotationQuaternion()); p(k + "ion", b.IsOrthonormal()); p(k + "icf", b.IsConformal());
                p(k + "fin", b.IsFinite()); p(k + "hash", GD.Hash(b)); p(k + "q", new Quat(b)); p(k + "x", b.x); p(k + "y", b.y); p(k + "z", b.z); p(k + "i2", b[2]);
                p(k + "m2", b * 2.0); p(k + "d2", b / 2.0); p(k + "mi3", b * 3);
                for (int o = 0; o < 6; o++) p(k + F("ge%d", o), b.GetEuler((EulerOrder)o));
                foreach (var v in new[] { new Vec3(1, 2, 3), new Vec3(-0.5, 0.25, 2) })
                {
                    p(k + "tdx", b.Tdotx(v)); p(k + "tdy", b.Tdoty(v)); p(k + "tdz", b.Tdotz(v)); p(k + "sc", b.Scaled(v)); p(k + "scl", b.ScaledLocal(v));
                    p(k + "xf", b * v); p(k + "xfi", v * b);
                }
                p(k + "rot", b.Rotated(new Vec3(1, 2, 3).NormalizedChecked(), 0.7)); p(k + "rotbad", b.Rotated(new Vec3(1, 2, 3), 0.7));
                for (int j = i % 3; j < B.Count; j += 3)
                {
                    Basis c = B[j];
                    p(k + F("%d.mul", j), b * c); p(k + F("%d.iea", j), b.IsEqualApprox(c)); p(k + F("%d.eq", j), b == c);
                    p(k + F("%d.slerp", j), b.Slerp(c, 0.3));
                }
            }
            foreach (var t in new[] { new Vec3(0, 0, -1), new Vec3(1, 2, 3), new Vec3(0, 5, 0), new Vec3(0, -2, 0), new Vec3(1e-7, 0, 0), new Vec3(-3, 0.5, 4) })
                foreach (var up in new[] { Vec3.UP, new Vec3(0, 0, 1), new Vec3(1, 1, 1) })
                {
                    p(F("blook.%s.%s", t, up), Basis.LookingAt(t, up)); p(F("blookm.%s.%s", t, up), Basis.LookingAt(t, up, true));
                }
            p("blook.def", Basis.LookingAt(new Vec3(3, -1, 2)));
            p("bconst", A(Basis.IDENTITY, Basis.FLIP_Y, Basis.FLIP_Z));
        }

        static List<Quat> MakeQuats()
        {
            var Q = new List<Quat> { Quat.IDENTITY, new Quat(new Vec3(0, 1, 0), 0.5), new Quat(new Vec3(1, 2, 3).NormalizedChecked(), 2.5), new Quat(0.1, 0.2, 0.3, 0.9),
                new Quat(0.1, 0.2, 0.3, 0.9).Normalized(), new Quat(new Vec3(0, 1, 0), PI), new Quat(new Vec3(0, 1, 0), 0.5 + 1e-6),
                -new Quat(new Vec3(0, 1, 0), 0.5), new Quat(new Vec3(1, 0, 0), -3.0), new Quat(0, 0, 0, 0) };
            foreach (var e in EUL) Q.Add(Quat.FromEuler(e));
            return Q;
        }

        static void QuatCases()
        {
            var Q = MakeQuats();
            for (int i = 0; i < Q.Count; i++)
            {
                Quat q = Q[i];
                string k = F("q.%d.", i);
                p(k + "str", q); p(k + "len", q.Length()); p(k + "lsq", q.LengthSquared()); p(k + "norm", q.Normalized()); p(k + "isn", q.IsNormalized());
                p(k + "inv", q.Inverse()); p(k + "log", q.Log()); p(k + "exp", q.Exp()); p(k + "axis", q.GetAxis()); p(k + "angle", q.GetAngle());
                p(k + "fin", q.IsFinite()); p(k + "hash", GD.Hash(q)); p(k + "b", new Basis(q)); p(k + "neg", -q); p(k + "m2", q * 2.0); p(k + "d2", q / 2.0);
                p(k + "lm2", 2.0 * q); p(k + "mi2", q * 2); p(k + "di2", q / 2);
                for (int o = 0; o < 6; o++) p(k + F("ge%d", o), q.GetEuler((EulerOrder)o));
                foreach (var v in new[] { new Vec3(1, 2, 3), new Vec3(-0.5, 0.25, 2) })
                {
                    p(k + "xf", q * v); p(k + "xfi", v * q);
                }
                for (int j = i % 2; j < Q.Count; j += 2)
                {
                    Quat r = Q[j];
                    string kk = k + F("%d.", j);
                    p(kk + "mul", q * r); p(kk + "add", q + r); p(kk + "sub", q - r); p(kk + "dot", q.Dot(r)); p(kk + "angto", q.AngleTo(r));
                    p(kk + "slerp", q.Slerp(r, 0.3)); p(kk + "slerpni", q.Slerpni(r, 0.3)); p(kk + "iea", q.IsEqualApprox(r)); p(kk + "eq", q == r);
                    p(kk + "sci", q.SphericalCubicInterpolate(r, Q[(j + 1) % Q.Count], Q[(j + 2) % Q.Count], 0.3));
                    p(kk + "scit", q.SphericalCubicInterpolateInTime(r, Q[(j + 1) % Q.Count], Q[(j + 2) % Q.Count], 0.3, 1.0, -0.5, 2.0));
                }
            }
            foreach (var a in new[] { new Vec3(1, 0, 0), new Vec3(0, 0, 1), new Vec3(1, 2, 3), new Vec3(-1, 0, 0), new Vec3(-1, 1e-8, 0), new Vec3(0.3, -0.2, 0.9), new Vec3(0, 0, 0) })
                foreach (var b in new[] { new Vec3(1, 0, 0), new Vec3(0, 1, 0), new Vec3(-2, -4, -6), new Vec3(0.1, 0.1, -0.9) })
                    p(F("qarc.%s.%s", a, b), new Quat(a, b));
            foreach (double ang in new[] { 0.0, 0.3, -1.7, PI, 2 * PI, 10.0 })
            {
                p(F("qaa.%s", ang), new Quat(new Vec3(0, 0, 1), ang)); p(F("qaa2.%s", ang), new Quat(new Vec3(1, -2, 2).NormalizedChecked(), ang));
            }
            p("qaabad", new Quat(new Vec3(1, 1, 0), 0.5));
            var q0 = new Quat(new Vec3(0, 1, 0), 0.1);
            foreach (double d in new[] { 0.0, 1e-7, 1e-5, 1e-3 })
            {
                p(F("qslerp0.%s", d), q0.Slerp(new Quat(new Vec3(0, 1, 0), 0.1 + d), 0.5)); p(F("qslerp180.%s", d), q0.Slerp(-new Quat(new Vec3(0, 1, 0), 0.1 + d), 0.5));
                p(F("qslerpPI.%s", d), q0.Slerp(new Quat(new Vec3(0, 1, 0), 0.1 + PI + d), 0.5)); p(F("qslerpni0.%s", d), q0.Slerpni(new Quat(new Vec3(0, 1, 0), 0.1 + d), 0.5));
            }
        }

        static List<Xform3> MakeXforms()
        {
            var B = MakeBases();
            return new List<Xform3> { Xform3.IDENTITY, Xform3.FLIP_X, new Xform3(Basis.IDENTITY, new Vec3(1, 2, 3)), new Xform3(B[6], new Vec3(-4, 0.5, 2)),
                new Xform3(B[2], new Vec3(0.1, 0.2, 0.3)), new Xform3(B[3], new Vec3(5, -5, 5)), new Xform3(new Vec3(1, 0, 0), new Vec3(0, 0, 1), new Vec3(0, -1, 0), new Vec3(7, 8, 9)),
                new Xform3(B[9], new Vec3(-1, -2, -3)), new Xform3(B[14], new Vec3(0, 10, -20)) };
        }

        static void Xform3Cases()
        {
            var T = MakeXforms();
            Aabb[] AA = { new Aabb(new Vec3(0, 0, 0), new Vec3(1, 1, 1)), new Aabb(new Vec3(-1, 2, -3), new Vec3(2, 0.5, 4)) };
            Plane[] P = { new Plane(new Vec3(0, 1, 0), 2), new Plane(new Vec3(1, 2, 3).NormalizedChecked(), -1.5) };
            for (int i = 0; i < T.Count; i++)
            {
                Xform3 t = T[i];
                string k = F("t.%d.", i);
                p(k + "str", t); p(k + "inv", t.Inverse()); p(k + "ainv", t.AffineInverse()); p(k + "orth", t.Orthonormalized());
                p(k + "rot", t.Rotated(new Vec3(0, 1, 0), 0.9)); p(k + "rotl", t.RotatedLocal(new Vec3(1, 2, 3).NormalizedChecked(), -0.4)); p(k + "sc", t.Scaled(new Vec3(2, -1, 0.5)));
                p(k + "scl", t.ScaledLocal(new Vec3(2, -1, 0.5))); p(k + "tr", t.Translated(new Vec3(1, -2, 3))); p(k + "trl", t.TranslatedLocal(new Vec3(1, -2, 3)));
                p(k + "look", t.LookingAt(new Vec3(3, 4, -5))); p(k + "lookm", t.LookingAt(new Vec3(3, 4, -5), new Vec3(0, 0, 1), true)); p(k + "lookbad", t.LookingAt(t.origin));
                p(k + "hash", GD.Hash(t)); p(k + "fin", t.IsFinite()); p(k + "m2", t * 2.0); p(k + "d2", t / 2.0); p(k + "basis", t.basis); p(k + "origin", t.origin);
                foreach (var v in new[] { new Vec3(1, 2, 3), new Vec3(-0.5, 0.25, 2) })
                {
                    p(k + "xf", t * v); p(k + "xfi", v * t);
                }
                foreach (var a in AA) { p(k + "xa", t * a); p(k + "xai", a * t); }
                foreach (var pl in P) { p(k + "xp", t * pl); p(k + "xpi", pl * t); }
                for (int j = 0; j < T.Count; j++)
                {
                    Xform3 u = T[j];
                    p(k + F("%d.mul", j), t * u); p(k + F("%d.iea", j), t.IsEqualApprox(u)); p(k + F("%d.interp", j), t.InterpolateWith(u, 0.3));
                }
            }
        }

        static void AabbCases()
        {
            Aabb[] AA = { default, new Aabb(new Vec3(0, 0, 0), new Vec3(1, 1, 1)), new Aabb(new Vec3(-1, 2, -3), new Vec3(2, 0.5, 4)), new Aabb(new Vec3(0.5, 0.5, 0.5), new Vec3(2, 2, 2)),
                new Aabb(new Vec3(1, 1, 1), new Vec3(-2, 3, -0.5)), new Aabb(new Vec3(0, 0, 0), new Vec3(3, 0, 1)), new Aabb(new Vec3(0.1, 0.2, 0.3), new Vec3(0.4, 0.5, 0.6)) };
            Vec3[] PTS = { new Vec3(0, 0, 0), new Vec3(0.5, 0.5, 0.5), new Vec3(1, 1, 1), new Vec3(-2, 1, 0), new Vec3(0.2, 2.25, -1) };
            Vec3[][] RAYS = { new[] { new Vec3(-5, 0.5, 0.5), new Vec3(1, 0, 0) }, new[] { new Vec3(0.5, 0.5, 0.5), new Vec3(0, 1, 0) }, new[] { new Vec3(-5, -5, -5), new Vec3(1, 1, 1) },
                new[] { new Vec3(-5, 0.5, 0.5), new Vec3(0, 1, 0) }, new[] { new Vec3(3, 3, 3), new Vec3(-1, -1.2, -0.9) }, new[] { new Vec3(0.2, 2.1, -2), new Vec3(0.1, 0, 1) } };
            for (int i = 0; i < AA.Length; i++)
            {
                Aabb a = AA[i];
                string k = F("a.%d.", i);
                p(k + "str", a); p(k + "abs", a.Abs()); p(k + "ctr", a.GetCenter()); p(k + "vol", a.GetVolume()); p(k + "hv", a.HasVolume()); p(k + "hs", a.HasSurface());
                p(k + "grow", a.Grow(0.5)); p(k + "end", a.End); p(k + "hash", GD.Hash(a)); p(k + "fin", a.IsFinite());
                p(k + "la", a.GetLongestAxis()); p(k + "lai", a.GetLongestAxisIndex()); p(k + "las", a.GetLongestAxisSize());
                p(k + "sa", a.GetShortestAxis()); p(k + "sai", a.GetShortestAxisIndex()); p(k + "sas", a.GetShortestAxisSize());
                for (int e = 0; e < 8; e++) p(k + F("ep%d", e), a.GetEndpoint(e));
                foreach (var v in PTS)
                {
                    p(k + "hp", a.HasPoint(v)); p(k + "exp", a.Expand(v)); p(k + "sup", a.GetSupport(v - new Vec3(0.5, 0.5, 0.5)));
                }
                foreach (var r in RAYS)
                {
                    p(k + "ray", a.IntersectsRay(r[0], r[1])); p(k + "seg", a.IntersectsSegment(r[0], r[0] + r[1] * 10));
                }
                foreach (var pl in new[] { new Plane(new Vec3(0, 1, 0), 0.5), new Plane(new Vec3(1, 1, 1).NormalizedChecked(), 10), new Plane(new Vec3(1, 0, 0), -1) })
                    p(k + "ip", a.IntersectsPlane(pl));
                for (int j = 0; j < AA.Length; j++)
                {
                    Aabb b = AA[j];
                    string kk = k + F("%d.", j);
                    p(kk + "int", a.Intersects(b)); p(kk + "enc", a.Encloses(b)); p(kk + "isect", a.Intersection(b)); p(kk + "merge", a.Merge(b));
                    p(kk + "iea", a.IsEqualApprox(b)); p(kk + "eq", a == b);
                }
            }
        }

        static void PlaneCases()
        {
            Plane[] P = { default, new Plane(new Vec3(0, 1, 0), 2), new Plane(new Vec3(1, 2, 3).NormalizedChecked(), -1.5), new Plane(new Vec3(1, 2, 3), 4), new Plane(1, 0, 0, 0.25),
                new Plane(new Vec3(0, 0, 1), new Vec3(1, 2, 3)), new Plane(new Vec3(0, 0, 0), new Vec3(1, 0, 0), new Vec3(0, 1, 0)), new Plane(new Vec3(1, 2, 3), new Vec3(-1, 0.5, 2), new Vec3(4, -4, 0.1)),
                new Plane(new Vec3(0.6, 0.8, 0)), Plane.PLANE_XZ };
            Vec3[] PTS = { new Vec3(0, 0, 0), new Vec3(1, 2, 3), new Vec3(0, 2, 0), new Vec3(-4, 0.5, 9) };
            for (int i = 0; i < P.Length; i++)
            {
                Plane pl = P[i];
                string k = F("p.%d.", i);
                p(k + "str", pl); p(k + "norm", pl.Normalized()); p(k + "ctr", pl.GetCenter()); p(k + "neg", -pl); p(k + "hash", GD.Hash(pl));
                p(k + "xyzd", A(pl.x, pl.y, pl.z, pl.d)); p(k + "fin", pl.IsFinite());
                foreach (var v in PTS)
                {
                    p(k + "dist", pl.DistanceTo(v)); p(k + "over", pl.IsPointOver(v)); p(k + "has", pl.HasPoint(v)); p(k + "has2", pl.HasPoint(v, 0.5)); p(k + "proj", pl.Project(v));
                    p(k + "ray", pl.IntersectsRay(v, new Vec3(0, -1, 0))); p(k + "ray2", pl.IntersectsRay(v, new Vec3(0.3, 0.4, -0.5)));
                    p(k + "seg", pl.IntersectsSegment(v, v + new Vec3(0, -5, 1)));
                }
                for (int j = 0; j < P.Length; j++)
                {
                    p(k + F("%d.i3", j), pl.Intersect3(P[j], P[(j + 3) % P.Length])); p(k + F("%d.iea", j), pl.IsEqualApprox(P[j])); p(k + F("%d.eq", j), pl == P[j]);
                }
            }
        }

        static List<Projection> MakeProjections() => new List<Projection> {
            Projection.IDENTITY, Projection.CreatePerspective(70, 16.0 / 9.0, 0.05, 4000), Projection.CreatePerspective(70, 16.0 / 9.0, 0.05, 4000, true),
            Projection.CreatePerspective(45, 0.5, 0.1, 100), Projection.CreatePerspective(45, 0.5, 0.1, 100, true), Projection.CreatePerspective(90, 1, 1, 10),
            Projection.CreateOrthogonal(-1, 1, -0.5, 0.5, 0.1, 100), Projection.CreateOrthogonalAspect(10, 16.0 / 9.0, 0.1, 50),
            Projection.CreateOrthogonalAspect(10, 16.0 / 9.0, 0.1, 50, true), Projection.CreateFrustum(-0.3, 0.5, -0.2, 0.25, 0.1, 30),
            Projection.CreateFrustumAspect(1.5, 4.0 / 3.0, new Vec2(0.1, -0.2), 0.5, 80), Projection.CreateFrustumAspect(1.5, 4.0 / 3.0, new Vec2(0.1, -0.2), 0.5, 80, true),
            Projection.CreateFrustum(1, -1, 0, 1, 0.1, 10), Projection.CreateFitAabb(new Aabb(new Vec3(-1, -2, -3), new Vec3(2, 4, 6))),
            Projection.CreateDepthCorrection(true), Projection.CreatePerspective(60, 1.25, 0.1, 0.1),
            new Projection(new Vec4(1, 2, 3, 4), new Vec4(0, 1, 0.5, -1), new Vec4(2, 0, 1, 0), new Vec4(0.25, 0.5, 0, 1)),
            new Projection(new Xform3(Basis.FromEuler(new Vec3(0.1, 0.2, 0.3)), new Vec3(1, 2, 3))) };

        static void ProjectionCases()
        {
            var PR = MakeProjections();
            var cam = new Xform3(Basis.FromEuler(new Vec3(-0.4, 0.8, 0)), new Vec3(3, 10, 12));
            for (int i = 0; i < PR.Count; i++)
            {
                Projection pr = PR[i];
                string k = F("pr.%d.", i);
                p(k + "str", pr); p(k + "det", pr.Determinant()); p(k + "inv", pr.Inverse()); p(k + "zf", pr.GetZFar()); p(k + "zn", pr.GetZNear());
                p(k + "asp", pr.GetAspect()); p(k + "fov", pr.GetFov()); p(k + "orth", pr.IsOrthogonal()); p(k + "vhe", pr.GetViewportHalfExtents());
                p(k + "fhe", pr.GetFarPlaneHalfExtents()); p(k + "lod", pr.GetLodMultiplier()); p(k + "ppm", pr.GetPixelsPerMeter(1024)); p(k + "hash", GD.Hash(pr));
                p(k + "zadj", pr.PerspectiveZnearAdjusted(0.5)); p(k + "fy", pr.FlippedY()); p(k + "jit", pr.JitterOffseted(new Vec2(0.01, -0.02))); p(k + "xf3", new Xform3(pr));
                p(k + "cols", A(pr.x, pr.y, pr.z, pr.w, pr[3]));
                Plane[] planes = pr.GetProjectionPlanes(cam);
                for (int pi = 0; pi < 6; pi++)
                {
                    p(k + F("pl%d", pi), pr.GetProjectionPlane(pi)); p(k + F("cpl%d", pi), planes[pi]);
                }
                foreach (var v in new[] { new Vec4(1, 2, 3, 1), new Vec4(-0.5, 0.25, -10, 1), new Vec4(0, 0, 0, 0) })
                {
                    p(k + "xf", pr * v); p(k + "xfi", v * pr);
                }
                for (int j = i % 2; j < PR.Count; j += 2) p(k + F("%d.mul", j), pr * PR[j]);
            }
            foreach (var f in new[] { new[] { 70.0, 16.0 / 9.0 }, new[] { 45.0, 0.75 }, new[] { 90.0, 1.0 }, new[] { 110.0, 2.5 } })
                p(F("prfovy.%s", f[0]), Projection.GetFovy(f[0], f[1]));
        }

        static List<Xform2> MakeX2() => new List<Xform2> {
            Xform2.IDENTITY, Xform2.FLIP_X, Xform2.FromRotation(0.5, new Vec2(1, 2)), Xform2.FromRotation(0.1, new Vec2(-3, 4)),
            Xform2.FromRotationScaleSkew(-2.0, new Vec2(2, -1.5), 0.3, new Vec2(5, 6)), Xform2.FromRotationScaleSkew(PI / 6, new Vec2(1, 1), 0, new Vec2(0, 0)),
            new Xform2(new Vec2(1, 2), new Vec2(3, 4), new Vec2(5, 6)), new Xform2(new Vec2(1, 2), new Vec2(2, 4), new Vec2(1, 1)),
            Xform2.FromRotationScaleSkew(1.0, new Vec2(-1, 2), -0.2, new Vec2(0.5, 0.25)) };

        static void Xform2Cases()
        {
            var X = MakeX2();
            Rect2[] R = { new Rect2(0, 0, 1, 1), new Rect2(-1, 2, 3, 0.5) };
            for (int i = 0; i < X.Count; i++)
            {
                Xform2 t = X[i];
                string k = F("x2.%d.", i);
                p(k + "str", t); p(k + "inv", t.Inverse()); p(k + "ainv", t.AffineInverseExact()); p(k + "rot", t.GetRotationExact()); p(k + "org", t.GetOrigin());
                p(k + "scale", t.GetScale()); p(k + "skew", t.GetSkew()); p(k + "orth", t.Orthonormalized()); p(k + "rotd", t.RotatedExact(0.7)); p(k + "rotl", t.RotatedLocalExact(-0.3));
                p(k + "sc", t.Scaled(new Vec2(2, -0.5))); p(k + "scl", t.ScaledLocal(new Vec2(2, -0.5))); p(k + "tr", t.Translated(new Vec2(1, -2))); p(k + "trl", t.TranslatedLocal(new Vec2(1, -2)));
                p(k + "det", t.Determinant()); p(k + "conf", t.IsConformal()); p(k + "fin", t.IsFinite()); p(k + "hash", GD.Hash(t)); p(k + "look", t.LookingAt(new Vec2(3, -4)));
                p(k + "look0", t.LookingAt()); p(k + "m2", t * 2.0); p(k + "d2", t / 2.0); p(k + "cols", A(t.x, t.y, t.origin, t[1]));
                foreach (var v in new[] { new Vec2(1, 2), new Vec2(-0.5, 0.25) })
                {
                    p(k + "bx", t.BasisXform(v)); p(k + "bxi", t.BasisXformInv(v)); p(k + "xf", t * v); p(k + "xfi", v * t);
                }
                foreach (var r in R) { p(k + "xr", t * r); p(k + "xri", r * t); }
                for (int j = 0; j < X.Count; j++)
                {
                    Xform2 u = X[j];
                    p(k + F("%d.mul", j), t * u); p(k + F("%d.iea", j), t.IsEqualApprox(u)); p(k + F("%d.interp", j), t.InterpolateWith(u, 0.3));
                }
            }
        }

        static void Rect2Cases()
        {
            Rect2[] R = { default, new Rect2(0, 0, 1, 1), new Rect2(-1, 2, 3, 0.5), new Rect2(0.5, 0.5, 2, 2), new Rect2(1, 1, -2, 3), new Rect2(0.1, 0.2, 0.3, 0.7), new Rect2(1, 0, 0, 5) };
            Vec2[] PTS = { new Vec2(0, 0), new Vec2(0.5, 0.5), new Vec2(1, 1), new Vec2(-2, 1), new Vec2(0.2, 2.25) };
            for (int i = 0; i < R.Length; i++)
            {
                Rect2 r = R[i];
                string k = F("r.%d.", i);
                p(k + "str", r); p(k + "abs", r.Abs()); p(k + "area", r.GetArea()); p(k + "ctr", r.GetCenter()); p(k + "ha", r.HasArea()); p(k + "end", r.End);
                p(k + "grow", r.Grow(0.5)); p(k + "gi", r.GrowIndividualExact(0.1, 0.2, 0.3, 0.4)); p(k + "hash", GD.Hash(r)); p(k + "fin", r.IsFinite());
                for (int s = 0; s < 4; s++) p(k + F("gs%d", s), r.GrowSideExact(s, 0.7));
                foreach (var v in PTS)
                {
                    p(k + "hp", r.HasPoint(v)); p(k + "exp", r.Expand(v)); p(k + "sup", r.GetSupport(v - new Vec2(0.5, 0.5)));
                }
                for (int j = 0; j < R.Length; j++)
                {
                    Rect2 o = R[j];
                    string kk = k + F("%d.", j);
                    p(kk + "int", r.Intersects(o)); p(kk + "intb", r.Intersects(o, true)); p(kk + "enc", r.Encloses(o)); p(kk + "isect", r.Intersection(o));
                    p(kk + "merge", r.Merge(o)); p(kk + "iea", r.IsEqualApprox(o)); p(kk + "eq", r == o);
                }
            }
        }

        static void ColorCases()
        {
            Col[] C = { new Col(0f, 0f, 0f, 1f), new Col(1, 0.5, 0.25), new Col(0.1, 0.2, 0.3, 0.4), new Col(2, -0.5, 0.5, 1.5), new Col(0.333333, 0.666667, 0.999), new Col(0, 0, 0, 0),
                new Col(1, 1, 1), new Col(0.5 / 255.0, 2.5 / 255.0, 127.5 / 255.0, 0.5), Col.ALICE_BLUE, Col.REBECCA_PURPLE, Col.Hex(0x7FFFD4FFu), new Col(0.02, 0.9, 0.6) };
            for (int i = 0; i < C.Length; i++)
            {
                Col c = C[i];
                string k = F("c.%d.", i);
                p(k + "str", c); p(k + "html", c.ToHtmlExact()); p(k + "html3", c.ToHtmlExact(false)); p(k + "rgba32", (long)c.ToRgba32Exact()); p(k + "argb32", (long)c.ToArgb32());
                p(k + "abgr32", (long)c.ToAbgr32()); p(k + "rgba64", unchecked((long)c.ToRgba64())); p(k + "argb64", unchecked((long)c.ToArgb64())); p(k + "abgr64", unchecked((long)c.ToAbgr64()));
                p(k + "hsv", A(c.H, c.S, c.V)); p(k + "c8", A(c.R8, c.G8, c.B8, c.A8)); p(k + "lum", c.GetLuminance()); p(k + "inv", c.Inverted());
                p(k + "light", c.Lightened(0.3)); p(k + "dark", c.Darkened(0.3)); p(k + "clamp", c.Clamp()); p(k + "clamp2", c.Clamp(new Col(0.2, 0.2, 0.2, 0.2), new Col(0.6, 0.7, 0.8, 0.9)));
                p(k + "s2l", c.SrgbToLinear()); p(k + "l2s", c.LinearToSrgb()); p(k + "ok", A(c.OkHslH, c.OkHslS, c.OkHslL)); p(k + "neg", -c);
                p(k + "m2", c * 2.0); p(k + "d2", c / 2.0); p(k + "lm2", 2.0 * c); p(k + "mi3", c * 3); p(k + "hash", GD.Hash(c));
                p(k + "fhsv", Col.FromHsvExact(c.r, c.g, c.b, c.a)); p(k + "fok", Col.FromOkHsl(c.r, c.g, c.b, c.a)); p(k + "hex", Col.Hex(c.ToRgba32Exact()));
                p(k + "hex64", Col.Hex64(unchecked((long)c.ToRgba64()))); p(k + "html_rt", Col.HtmlExact(c.ToHtmlExact()));
                for (int j = 0; j < C.Length; j++)
                {
                    Col d = C[j];
                    string kk = k + F("%d.", j);
                    p(kk + "lerp", c.Lerp(d, 0.3)); p(kk + "blend", c.Blend(d)); p(kk + "add", c + d); p(kk + "sub", c - d); p(kk + "mul", c * d); p(kk + "div", c / d);
                    p(kk + "iea", c.IsEqualApproxExact(d)); p(kk + "eq", c == d);
                }
            }
            foreach (var s in new[] { "#fff", "ffff", "#12345678", "abcdef", "#ABC", "zz", "#12345", "red", "Light Sky Blue", "rebecca-purple", "web_gray", "nope", "" })
            {
                p(F("cs.%s.valid", s), Col.HtmlIsValid(s)); p(F("cs.%s.from", s), Col.FromString(s, new Col(0.1, 0.2, 0.3)));
            }
            foreach (var s in new[] { "#fff", "ffff", "#12345678", "abcdef", "#ABC" })
            {
                p(F("cs.%s.html", s), Col.HtmlExact(s)); p(F("cs.%s.ctor", s), Col.FromCode(s)); p(F("cs.%s.ctora", s), new Col(Col.FromCode(s), 0.5));
            }
            foreach (double h in new[] { 0.0, 0.1, 0.5, 0.99, 1.0, 1.5, -0.25 })
            {
                p(F("chsv.%s", h), Col.FromHsvExact(h, 0.7, 0.9)); p(F("cokhsl.%s", h), Col.FromOkHsl(h, 0.7, 0.6)); p(F("cokhsl0.%s", h), Col.FromOkHsl(h, 0.3, 0.0));
            }
            p("crgba8", Col.FromRgba8(255, 128, 0)); p("crgba8b", Col.FromRgba8(12, 34, 56, 78)); p("crgbe", Col.FromRgbe9995(0x12345678));
            p("cnamed", A(Col.ALICE_BLUE, Col.WEB_PURPLE, Col.MEDIUM_SPRING_GREEN, Col.LIGHT_GOLDENROD, Col.LIME, Col.FUCHSIA));
        }

        static void VariantCases()
        {
            Var b = Basis.FromEuler(new Vec3(0.1, 0.2, 0.3));
            Var q = Quat.FromEuler(new Vec3(0.3, -0.2, 0.1));
            Var t = new Xform3(Basis.FromEuler(new Vec3(0.5, 0.1, -0.2)), new Vec3(1, 2, 3));
            Var v = new Vec3(1, -2, 0.5);
            Var a = new Aabb(new Vec3(-1, 0, 1), new Vec3(2, 3, 4));
            Var pl = new Plane(new Vec3(0, 1, 0), 2);
            Var x2 = Xform2.FromRotation(0.5, new Vec2(1, 2));
            Var v2 = new Vec2(3, -1);
            Var r2 = new Rect2(0, 1, 2, 3);
            Var pr = Projection.CreatePerspective(60, 1.5, 0.1, 100);
            Var v4 = new Vec4(1, 2, 3, 1);
            Var c = new Col(0.2, 0.4, 0.6, 0.8);
            Var v3i = new Vec3i(3, -4, 5);
            Var v4i = new Vec4i(3, -4, 5, 6);
            Var two = 2, twof = 2.0, three = 3, half = 0.5, twoHalf = 2.5;
            p("var.bv", b * v); p("var.vb", v * b); p("var.bb", b * b); p("var.b2", b * two); p("var.bd2", b / twof);
            p("var.qv", q * v); p("var.vq", v * q); p("var.qq", q * q); p("var.q2", two * q); p("var.qn", -q); p("var.qa", q + q);
            p("var.tv", t * v); p("var.vt", v * t); p("var.ta", t * a); p("var.at", a * t); p("var.tp", t * pl); p("var.pt", pl * t); p("var.tt", t * t);
            p("var.xv", x2 * v2); p("var.vx", v2 * x2); p("var.xr", x2 * r2); p("var.rx", r2 * x2); p("var.xx", x2 * x2); p("var.x2", x2 * twof);
            p("var.prv", pr * v4); p("var.vpr", v4 * pr); p("var.prpr", pr * pr);
            p("var.c2", c * two); p("var.2c", twof * c); p("var.cn", -c); p("var.cc", c * c); p("var.cdc", c / c); p("var.cp", c + c);
            p("var.pn", -pl); p("var.v3i25", v3i * twoHalf); p("var.v3id2", v3i / two); p("var.v3im3", v3i % three); p("var.v3iv", v3i + v3i); p("var.v3in", -v3i);
            p("var.v4m", v4 * two); p("var.2v4", twoHalf * v4); p("var.v4d", v4 / v4); p("var.v4i3", three * v4i); p("var.v4if", v4i * half);
            foreach (var x in new Var[] { b, q, t, a, pl, x2, r2, pr, v4, c, v3i, v4i, Basis.IDENTITY, Quat.IDENTITY, Xform3.IDENTITY, default(Aabb), default(Plane), Xform2.IDENTITY,
                default(Rect2), Projection.IDENTITY, default(Vec4), new Col(0f, 0f, 0f, 1f), default(Vec3i), default(Vec4i) })
                p("var.info", A(GD.TypeOf(x), GD.Hash(x), x.Truthy ? true : false, GD.Str(x)));
            p("var.eq", A(b == (Var)Basis.FromEuler(new Vec3(0.1, 0.2, 0.3)), q == q, t == (Var)Xform3.IDENTITY, c == (Var)new Col(0.2, 0.4, 0.6, 0.8), v3i == (Var)new Vec3i(3, -4, 5)));
        }
            static void EdgeCases()
        {
            float INF = float.PositiveInfinity, NAN = float.NaN;
            Vec2[] E2 = { new Vec2(INF, 1), new Vec2(NAN, 2), new Vec2(-0.0f, 0.0f), new Vec2(-INF, -INF) };
            for (int i = 0; i < E2.Length; i++)
            {
                Vec2 a = E2[i];
                string k = F("e2.%d.", i);
                p(k + "str", a); p(k + "norm", a.Normalized()); p(k + "fin", a.IsFinite()); p(k + "sign", a.Sign()); p(k + "clampf", a.Clampf(-1, 1));
                p(k + "minf", a.Minf(0.5)); p(k + "maxf", a.Maxf(0.5)); p(k + "snap0", a.Snappedf(0)); p(k + "posmod", a.Posmod(-0.7)); p(k + "hash", GD.Hash(a)); p(k + "lim", a.LimitLength(2));
            }
            Vec3[] E3 = { new Vec3(INF, 1, 0), new Vec3(NAN, 2, 3), new Vec3(-0.0f, 0.0f, -0.0f), new Vec3(1, -INF, 0) };
            for (int i = 0; i < E3.Length; i++)
            {
                Vec3 a = E3[i];
                string k = F("e3.%d.", i);
                p(k + "str", a); p(k + "norm", a.NormalizedChecked()); p(k + "fin", a.IsFinite()); p(k + "sign", a.Sign()); p(k + "clamp", a.Clamp(new Vec3(-1, -1, -1), new Vec3(1, 1, 1)));
                p(k + "min", a.Min(new Vec3(0.5, 0.5, 0.5))); p(k + "max", a.Max(new Vec3(0.5, 0.5, 0.5))); p(k + "snap0", a.Snapped(new Vec3(0, 0.5, 0))); p(k + "hash", GD.Hash(a));
                p(k + "dir", new Vec3(1, 1, 1).DirectionTo(a)); p(k + "octd", Vec3.OctahedronDecode(new Vec2(a.x, a.y))); p(k + "eul", Basis.FromEuler(a).GetEuler());
            }
            p("e.q", A(new Quat(NAN, 0, 0, 1).Normalized(), new Quat(0, 0, 0, 1).Slerp(new Quat(0, 0, 0, -1), 0.5), new Quat(0, 0, 0, 1).AngleTo(new Quat(0, 1, 0, 0))));
            p("e.c", A(new Col(NAN, 0.5f, 0.5f).GetLuminance(), new Col(-0.0f, 0f, 0f).H, new Col(1f, 1f, 1f).S, GD.Hash(new Col(-0.0f, 0f, 0f, 1f)), GD.Hash(new Col(0f, 0f, 0f, 1f))));
        }
    }
}
