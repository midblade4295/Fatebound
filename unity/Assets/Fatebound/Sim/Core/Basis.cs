// Fatebound (Unity port): Godot's Basis and Quaternion (core/math/basis.{h,cpp}, quaternion.{h,cpp}), real_t = float.
// Basis stores ROWS like Godot (row0..row2); GDScript's basis.x / .y / .z and basis[i] are COLUMNS (properties x, y, z
// and the indexer here). C# can't give a struct a parameterless constructor, so `new Basis()` / `default` is the ZERO
// matrix and `new Quat()` is (0, 0, 0, 0) -- GDScript's Basis() / Quaternion() are Basis.IDENTITY / Quat.IDENTITY.
using System;

namespace Fatebound.Sim
{
    public struct Basis : IEquatable<Basis>, IGodotValue
    {
        public Vec3 row0, row1, row2;

        public static readonly Basis IDENTITY = FromRows(1, 0, 0, 0, 1, 0, 0, 0, 1);
        public static readonly Basis FLIP_X = FromRows(-1, 0, 0, 0, 1, 0, 0, 0, 1);
        public static readonly Basis FLIP_Y = FromRows(1, 0, 0, 0, -1, 0, 0, 0, 1);
        public static readonly Basis FLIP_Z = FromRows(1, 0, 0, 0, 1, 0, 0, 0, -1);

        /// <summary>Basis(x_axis, y_axis, z_axis): the three columns.</summary>
        public Basis(Vec3 xAxis, Vec3 yAxis, Vec3 zAxis)
        {
            row0 = new Vec3(xAxis.x, yAxis.x, zAxis.x);
            row1 = new Vec3(xAxis.y, yAxis.y, zAxis.y);
            row2 = new Vec3(xAxis.z, yAxis.z, zAxis.z);
        }

        /// <summary>Basis(quaternion).</summary>
        public Basis(Quat q)
        {
            row0 = row1 = row2 = default;
            SetQuaternion(q);
        }

        /// <summary>Basis(axis, angle): the axis must be normalized (else, with MathChecks, an error and IDENTITY).</summary>
        public Basis(Vec3 axis, double angle)
        {
            row0 = new Vec3(1f, 0f, 0f);
            row1 = new Vec3(0f, 1f, 0f);
            row2 = new Vec3(0f, 0f, 1f);
            SetAxisAngle(axis, (float)angle);
        }

        /// <summary>C++ Basis(quaternion, scale).</summary>
        public Basis(Quat q, Vec3 scale)
        {
            this = FromScale(scale);
            this = new Basis(q) * this;
        }

        /// <summary>C++ Basis(axis, angle, scale).</summary>
        public Basis(Vec3 axis, double angle, Vec3 scale)
        {
            this = FromScale(scale);
            this = new Basis(axis, angle) * this;
        }

        /// <summary>The C++ nine-value constructor (row-major: xx, xy, xz are row 0).</summary>
        public static Basis FromRows(float xx, float xy, float xz, float yx, float yy, float yz, float zx, float zy, float zz)
        {
            Basis b;
            b.row0 = new Vec3(xx, xy, xz);
            b.row1 = new Vec3(yx, yy, yz);
            b.row2 = new Vec3(zx, zy, zz);
            return b;
        }

        // ------------------------------------------------------------------ element / column access
        /// <summary>basis.x: column 0.</summary>
        public Vec3 x { get => GetColumn(0); set => SetColumn(0, value); }
        public Vec3 y { get => GetColumn(1); set => SetColumn(1, value); }
        public Vec3 z { get => GetColumn(2); set => SetColumn(2, value); }

        /// <summary>basis[i] in GDScript: column i.</summary>
        public Vec3 this[int column]
        {
            get
            {
                if ((uint)column > 2) throw new IndexOutOfRangeException("Basis index " + column);
                return GetColumn(column);
            }
            set
            {
                if ((uint)column > 2) throw new IndexOutOfRangeException("Basis index " + column);
                SetColumn(column, value);
            }
        }

        public Vec3 GetColumn(int i) => new Vec3(row0[i], row1[i], row2[i]);
        public void SetColumn(int i, Vec3 v) { row0[i] = v.x; row1[i] = v.y; row2[i] = v.z; }
        public Vec3 GetRow(int r) => r == 0 ? row0 : (r == 1 ? row1 : row2);
        public void SetRow(int r, Vec3 v) { if (r == 0) row0 = v; else if (r == 1) row1 = v; else row2 = v; }
        public Vec3 GetMainDiagonal() => new Vec3(row0.x, row1.y, row2.z);
        /// <summary>C++ rows[r][c].</summary>
        public float Get(int r, int c) => GetRow(r)[c];
        public void Set(int r, int c, float v)
        {
            switch (r) { case 0: row0[c] = v; break; case 1: row1[c] = v; break; default: row2[c] = v; break; }
        }

        // ------------------------------------------------------------------ products
        public float Tdotx(Vec3 v) => row0.x * v.x + row1.x * v.y + row2.x * v.z;
        public float Tdoty(Vec3 v) => row0.y * v.x + row1.y * v.y + row2.y * v.z;
        public float Tdotz(Vec3 v) => row0.z * v.x + row1.z * v.y + row2.z * v.z;

        public Vec3 Xform(Vec3 v) => new Vec3(row0.Dot(v), row1.Dot(v), row2.Dot(v));

        public Vec3 XformInv(Vec3 v) => new Vec3(
            (row0.x * v.x) + (row1.x * v.y) + (row2.x * v.z),
            (row0.y * v.x) + (row1.y * v.y) + (row2.y * v.z),
            (row0.z * v.x) + (row1.z * v.y) + (row2.z * v.z));

        public static Basis operator *(Basis a, Basis m) => FromRows(
            m.Tdotx(a.row0), m.Tdoty(a.row0), m.Tdotz(a.row0),
            m.Tdotx(a.row1), m.Tdoty(a.row1), m.Tdotz(a.row1),
            m.Tdotx(a.row2), m.Tdoty(a.row2), m.Tdotz(a.row2));

        /// <summary>basis * vector: xform.</summary>
        public static Vec3 operator *(Basis b, Vec3 v) => b.Xform(v);
        /// <summary>vector * basis: xform_inv (the transposed product).</summary>
        public static Vec3 operator *(Vec3 v, Basis b) => b.XformInv(v);
        public static Basis operator *(Basis b, double s) { float f = (float)s; return FromRows(b.row0.x * f, b.row0.y * f, b.row0.z * f, b.row1.x * f, b.row1.y * f, b.row1.z * f, b.row2.x * f, b.row2.y * f, b.row2.z * f); }
        public static Basis operator /(Basis b, double s) { float f = (float)s; return FromRows(b.row0.x / f, b.row0.y / f, b.row0.z / f, b.row1.x / f, b.row1.y / f, b.row1.z / f, b.row2.x / f, b.row2.y / f, b.row2.z / f); }
        public static Basis operator +(Basis a, Basis b) { Basis r; r.row0 = a.row0 + b.row0; r.row1 = a.row1 + b.row1; r.row2 = a.row2 + b.row2; return r; }
        public static Basis operator -(Basis a, Basis b) { Basis r; r.row0 = a.row0 - b.row0; r.row1 = a.row1 - b.row1; r.row2 = a.row2 - b.row2; return r; }
        public static bool operator ==(Basis a, Basis b) => a.row0 == b.row0 && a.row1 == b.row1 && a.row2 == b.row2;
        public static bool operator !=(Basis a, Basis b) => !(a == b);
        public bool Equals(Basis o) => this == o;
        public override bool Equals(object o) => o is Basis b && this == b;
        public override int GetHashCode() => unchecked((int)GodotHash());
        public override string ToString() => "[X: " + GetColumn(0) + ", Y: " + GetColumn(1) + ", Z: " + GetColumn(2) + "]";

        // ------------------------------------------------------------------ inverse / transpose / determinant
        float Cofac(int r1, int c1, int r2, int c2) => Get(r1, c1) * Get(r2, c2) - Get(r1, c2) * Get(r2, c1);

        public Basis Inverse()
        {
            float co0 = Cofac(1, 1, 2, 2), co1 = Cofac(1, 2, 2, 0), co2 = Cofac(1, 0, 2, 1);
            float det = row0.x * co0 + row0.y * co1 + row0.z * co2;
            if (GD.MathChecks && det == 0)
            {
                GD.MathError("Condition \"det == 0\" is true.");
                return this;
            }
            float s = 1.0f / det;
            return FromRows(co0 * s, Cofac(0, 2, 2, 1) * s, Cofac(0, 1, 1, 2) * s,
                co1 * s, Cofac(0, 0, 2, 2) * s, Cofac(0, 2, 1, 0) * s,
                co2 * s, Cofac(0, 1, 2, 0) * s, Cofac(0, 0, 1, 1) * s);
        }

        public Basis Transposed() => FromRows(row0.x, row1.x, row2.x, row0.y, row1.y, row2.y, row0.z, row1.z, row2.z);

        public float Determinant() =>
            row0.x * (row1.y * row2.z - row2.y * row1.z) -
            row1.x * (row0.y * row2.z - row2.y * row0.z) +
            row2.x * (row0.y * row1.z - row1.y * row0.z);

        /// <summary>C++ transpose_xform(m): transposed() * m.</summary>
        public Basis TransposeXform(Basis m) => FromRows(
            row0.x * m.row0.x + row1.x * m.row1.x + row2.x * m.row2.x,
            row0.x * m.row0.y + row1.x * m.row1.y + row2.x * m.row2.y,
            row0.x * m.row0.z + row1.x * m.row1.z + row2.x * m.row2.z,
            row0.y * m.row0.x + row1.y * m.row1.x + row2.y * m.row2.x,
            row0.y * m.row0.y + row1.y * m.row1.y + row2.y * m.row2.y,
            row0.y * m.row0.z + row1.y * m.row1.z + row2.y * m.row2.z,
            row0.z * m.row0.x + row1.z * m.row1.x + row2.z * m.row2.x,
            row0.z * m.row0.y + row1.z * m.row1.y + row2.z * m.row2.y,
            row0.z * m.row0.z + row1.z * m.row1.z + row2.z * m.row2.z);

        // ------------------------------------------------------------------ orthonormalize / tests
        public Basis Orthonormalized()
        {
            Vec3 cx = GetColumn(0), cy = GetColumn(1), cz = GetColumn(2);
            cx = cx.NormalizedChecked();
            float d = cx.Dot(cy);
            cy = (cy - new Vec3(cx.x * d, cx.y * d, cx.z * d)).NormalizedChecked();
            float dz1 = cx.Dot(cz), dz2 = cy.Dot(cz);
            cz = (cz - new Vec3(cx.x * dz1, cx.y * dz1, cx.z * dz1) - new Vec3(cy.x * dz2, cy.y * dz2, cy.z * dz2)).NormalizedChecked();
            Basis b = this;
            b.SetColumn(0, cx);
            b.SetColumn(1, cy);
            b.SetColumn(2, cz);
            return b;
        }

        public Basis Orthogonalized()
        {
            Vec3 scl = GetScale();
            return Orthonormalized().ScaledLocal(scl);
        }

        public bool IsOrthogonal()
        {
            Vec3 cx = GetColumn(0), cy = GetColumn(1), cz = GetColumn(2);
            return GD.IsZeroApproxF(cx.Dot(cy)) && GD.IsZeroApproxF(cx.Dot(cz)) && GD.IsZeroApproxF(cy.Dot(cz));
        }

        public bool IsOrthonormal()
        {
            Vec3 cx = GetColumn(0), cy = GetColumn(1), cz = GetColumn(2);
            return GD.IsEqualApproxF(cx.LengthSquared(), 1f) && GD.IsEqualApproxF(cy.LengthSquared(), 1f) && GD.IsEqualApproxF(cz.LengthSquared(), 1f)
                && GD.IsZeroApproxF(cx.Dot(cy)) && GD.IsZeroApproxF(cx.Dot(cz)) && GD.IsZeroApproxF(cy.Dot(cz));
        }

        public bool IsConformal()
        {
            Vec3 cx = GetColumn(0), cy = GetColumn(1), cz = GetColumn(2);
            float xLenSq = cx.LengthSquared();
            return GD.IsEqualApproxF(xLenSq, cy.LengthSquared()) && GD.IsEqualApproxF(xLenSq, cz.LengthSquared())
                && GD.IsZeroApproxF(cx.Dot(cy)) && GD.IsZeroApproxF(cx.Dot(cz)) && GD.IsZeroApproxF(cy.Dot(cz));
        }

        public bool IsDiagonal() =>
            GD.IsZeroApproxF(row0.y) && GD.IsZeroApproxF(row0.z) && GD.IsZeroApproxF(row1.x) && GD.IsZeroApproxF(row1.z)
            && GD.IsZeroApproxF(row2.x) && GD.IsZeroApproxF(row2.y);

        public bool IsRotation() => IsConformal() && GD.IsEqualApproxF(Determinant(), 1f, GD.UNIT_EPS_F);
        public bool IsEqualApprox(Basis b) => row0.IsEqualApprox(b.row0) && row1.IsEqualApprox(b.row1) && row2.IsEqualApprox(b.row2);
        public bool IsSame(Basis b) => row0.IsSame(b.row0) && row1.IsSame(b.row1) && row2.IsSame(b.row2);
        public bool IsFinite() => row0.IsFinite() && row1.IsFinite() && row2.IsFinite();

        // ------------------------------------------------------------------ scale
        public static Basis FromScale(Vec3 s) => FromRows(s.x, 0, 0, 0, s.y, 0, 0, 0, s.z);

        /// <summary>scaled(scale): rows scaled (S * M).</summary>
        public Basis Scaled(Vec3 s)
        {
            Basis m = this;
            m.row0 = new Vec3(row0.x * s.x, row0.y * s.x, row0.z * s.x);
            m.row1 = new Vec3(row1.x * s.y, row1.y * s.y, row1.z * s.y);
            m.row2 = new Vec3(row2.x * s.z, row2.y * s.z, row2.z * s.z);
            return m;
        }

        /// <summary>scaled_local(scale): columns scaled (M * S).</summary>
        public Basis ScaledLocal(Vec3 s)
        {
            Basis m = this;
            m.row0 = row0 * s;
            m.row1 = row1 * s;
            m.row2 = row2 * s;
            return m;
        }

        public Vec3 GetScaleAbs() => new Vec3(GetColumn(0).Length(), GetColumn(1).Length(), GetColumn(2).Length());

        public Vec3 GetScaleGlobal()
        {
            float detSign = GD.SignF(Determinant());
            Vec3 v = new Vec3(row0.Length(), row1.Length(), row2.Length());
            return new Vec3(v.x * detSign, v.y * detSign, v.z * detSign);
        }

        public Vec3 GetScale()
        {
            float detSign = GD.SignF(Determinant());
            Vec3 v = GetScaleAbs();
            return new Vec3(v.x * detSign, v.y * detSign, v.z * detSign);
        }

        public float GetUniformScale() => (row0.Length() + row1.Length() + row2.Length()) / 3.0f;

        // ------------------------------------------------------------------ rotation
        /// <summary>rotated(axis, angle): Basis(axis, angle) * this (a global rotation).</summary>
        public Basis Rotated(Vec3 axis, double angle) => new Basis(axis, angle) * this;
        /// <summary>C++ rotated_local(axis, angle): this * Basis(axis, angle).</summary>
        public Basis RotatedLocal(Vec3 axis, double angle) => this * new Basis(axis, angle);
        /// <summary>C++ rotated(euler, order).</summary>
        public Basis Rotated(Vec3 euler, EulerOrder order) => FromEuler(euler, order) * this;
        /// <summary>C++ rotated(quaternion).</summary>
        public Basis Rotated(Quat q) => new Basis(q) * this;

        void SetAxisAngle(Vec3 axis, float angle)
        {
            if (GD.MathChecks && !axis.IsNormalized())
            {
                GD.MathError("The axis Vector3 " + axis + " must be normalized.");
                return;
            }
            Vec3 axisSq = new Vec3(axis.x * axis.x, axis.y * axis.y, axis.z * axis.z);
            float cosine = MathF.Cos(angle);
            row0.x = axisSq.x + cosine * (1.0f - axisSq.x);
            row1.y = axisSq.y + cosine * (1.0f - axisSq.y);
            row2.z = axisSq.z + cosine * (1.0f - axisSq.z);
            float sine = MathF.Sin(angle);
            float t = 1 - cosine;
            float xyzt = axis.x * axis.y * t;
            float zyxs = axis.z * sine;
            row0.y = xyzt - zyxs;
            row1.x = xyzt + zyxs;
            xyzt = axis.x * axis.z * t;
            zyxs = axis.y * sine;
            row0.z = xyzt + zyxs;
            row2.x = xyzt - zyxs;
            xyzt = axis.y * axis.z * t;
            zyxs = axis.x * sine;
            row1.z = xyzt - zyxs;
            row2.y = xyzt + zyxs;
        }

        void SetQuaternion(Quat q)
        {
            float d = q.LengthSquared();
            float s = 2.0f / d;
            float xs = q.x * s, ys = q.y * s, zs = q.z * s;
            float wx = q.w * xs, wy = q.w * ys, wz = q.w * zs;
            float xx = q.x * xs, xy = q.x * ys, xz = q.x * zs;
            float yy = q.y * ys, yz = q.y * zs, zz = q.z * zs;
            row0 = new Vec3(1.0f - (yy + zz), xy - wz, xz + wy);
            row1 = new Vec3(xy + wz, 1.0f - (xx + zz), yz - wx);
            row2 = new Vec3(xz - wy, yz + wx, 1.0f - (xx + yy));
        }

        /// <summary>from_euler(euler, order = YXZ).</summary>
        public static Basis FromEuler(Vec3 euler, EulerOrder order = EulerOrder.YXZ)
        {
            float c = MathF.Cos(euler.x), s = MathF.Sin(euler.x);
            Basis xmat = FromRows(1, 0, 0, 0, c, -s, 0, s, c);
            c = MathF.Cos(euler.y);
            s = MathF.Sin(euler.y);
            Basis ymat = FromRows(c, 0, s, 0, 1, 0, -s, 0, c);
            c = MathF.Cos(euler.z);
            s = MathF.Sin(euler.z);
            Basis zmat = FromRows(c, -s, 0, s, c, 0, 0, 0, 1);
            switch (order)
            {
                case EulerOrder.XYZ: return xmat * (ymat * zmat);
                case EulerOrder.XZY: return xmat * zmat * ymat;
                case EulerOrder.YXZ: return ymat * xmat * zmat;
                case EulerOrder.YZX: return ymat * zmat * xmat;
                case EulerOrder.ZXY: return zmat * xmat * ymat;
                case EulerOrder.ZYX: return zmat * ymat * xmat;
            }
            GD.MathError("Invalid Euler order parameter.");
            return IDENTITY;
        }

        /// <summary>get_euler(order = YXZ).</summary>
        public Vec3 GetEuler(EulerOrder order = EulerOrder.YXZ)
        {
            const float epsilon = 0.00000025f;
            Vec3 euler = default;
            switch (order)
            {
                case EulerOrder.XYZ:
                    {
                        float sy = row0.z;
                        if (sy < (1.0f - epsilon))
                        {
                            if (sy > -(1.0f - epsilon))
                            {
                                if (row1.x == 0 && row0.y == 0 && row1.z == 0 && row2.y == 0 && row1.y == 1)
                                {
                                    euler.x = 0;
                                    euler.y = MathF.Atan2(row0.z, row0.x);
                                    euler.z = 0;
                                }
                                else
                                {
                                    euler.x = MathF.Atan2(-row1.z, row2.z);
                                    euler.y = GD.AsinF(sy);
                                    euler.z = MathF.Atan2(-row0.y, row0.x);
                                }
                            }
                            else
                            {
                                euler.x = MathF.Atan2(row2.y, row1.y);
                                euler.y = (float)(-GD.PI / 2.0f);
                                euler.z = 0.0f;
                            }
                        }
                        else
                        {
                            euler.x = MathF.Atan2(row2.y, row1.y);
                            euler.y = (float)(GD.PI / 2.0f);
                            euler.z = 0.0f;
                        }
                        return euler;
                    }
                case EulerOrder.XZY:
                    {
                        float sz = row0.y;
                        if (sz < (1.0f - epsilon))
                        {
                            if (sz > -(1.0f - epsilon))
                            {
                                euler.x = MathF.Atan2(row2.y, row1.y);
                                euler.y = MathF.Atan2(row0.z, row0.x);
                                euler.z = GD.AsinF(-sz);
                            }
                            else
                            {
                                euler.x = -MathF.Atan2(row1.z, row2.z);
                                euler.y = 0.0f;
                                euler.z = (float)(GD.PI / 2.0f);
                            }
                        }
                        else
                        {
                            euler.x = -MathF.Atan2(row1.z, row2.z);
                            euler.y = 0.0f;
                            euler.z = (float)(-GD.PI / 2.0f);
                        }
                        return euler;
                    }
                case EulerOrder.YXZ:
                    {
                        float m12 = row1.z;
                        if (m12 < (1 - epsilon))
                        {
                            if (m12 > -(1 - epsilon))
                            {
                                if (row1.x == 0 && row0.y == 0 && row0.z == 0 && row2.x == 0 && row0.x == 1)
                                {
                                    euler.x = MathF.Atan2(-m12, row1.y);
                                    euler.y = 0;
                                    euler.z = 0;
                                }
                                else
                                {
                                    euler.x = MathF.Asin(-m12);
                                    euler.y = MathF.Atan2(row0.z, row2.z);
                                    euler.z = MathF.Atan2(row1.x, row1.y);
                                }
                            }
                            else
                            {
                                euler.x = (float)(GD.PI * 0.5f);
                                euler.y = MathF.Atan2(row0.y, row0.x);
                                euler.z = 0;
                            }
                        }
                        else
                        {
                            euler.x = (float)(-GD.PI * 0.5f);
                            euler.y = -MathF.Atan2(row0.y, row0.x);
                            euler.z = 0;
                        }
                        return euler;
                    }
                case EulerOrder.YZX:
                    {
                        float sz = row1.x;
                        if (sz < (1.0f - epsilon))
                        {
                            if (sz > -(1.0f - epsilon))
                            {
                                euler.x = MathF.Atan2(-row1.z, row1.y);
                                euler.y = MathF.Atan2(-row2.x, row0.x);
                                euler.z = GD.AsinF(sz);
                            }
                            else
                            {
                                euler.x = MathF.Atan2(row2.y, row2.z);
                                euler.y = 0.0f;
                                euler.z = (float)(-GD.PI / 2.0f);
                            }
                        }
                        else
                        {
                            euler.x = MathF.Atan2(row2.y, row2.z);
                            euler.y = 0.0f;
                            euler.z = (float)(GD.PI / 2.0f);
                        }
                        return euler;
                    }
                case EulerOrder.ZXY:
                    {
                        float sx = row2.y;
                        if (sx < (1.0f - epsilon))
                        {
                            if (sx > -(1.0f - epsilon))
                            {
                                euler.x = GD.AsinF(sx);
                                euler.y = MathF.Atan2(-row2.x, row2.z);
                                euler.z = MathF.Atan2(-row0.y, row1.y);
                            }
                            else
                            {
                                euler.x = (float)(-GD.PI / 2.0f);
                                euler.y = MathF.Atan2(row0.z, row0.x);
                                euler.z = 0;
                            }
                        }
                        else
                        {
                            euler.x = (float)(GD.PI / 2.0f);
                            euler.y = MathF.Atan2(row0.z, row0.x);
                            euler.z = 0;
                        }
                        return euler;
                    }
                case EulerOrder.ZYX:
                    {
                        float sy = row2.x;
                        if (sy < (1.0f - epsilon))
                        {
                            if (sy > -(1.0f - epsilon))
                            {
                                euler.x = MathF.Atan2(row2.y, row2.z);
                                euler.y = GD.AsinF(-sy);
                                euler.z = MathF.Atan2(row1.x, row0.x);
                            }
                            else
                            {
                                euler.x = 0;
                                euler.y = (float)(GD.PI / 2.0f);
                                euler.z = -MathF.Atan2(row0.y, row1.y);
                            }
                        }
                        else
                        {
                            euler.x = 0;
                            euler.y = (float)(-GD.PI / 2.0f);
                            euler.z = -MathF.Atan2(row0.y, row1.y);
                        }
                        return euler;
                    }
            }
            GD.MathError("Invalid parameter for get_euler(order)");
            return default;
        }

        /// <summary>C++ get_euler_normalized(order): the Euler angles of the rotation part (sign-corrected).</summary>
        public Vec3 GetEulerNormalized(EulerOrder order = EulerOrder.YXZ) => RotationPart().GetEuler(order);

        Basis RotationPart()
        {
            Basis m = Orthonormalized();
            if (m.Determinant() < 0) m = m.Scaled(new Vec3(-1f, -1f, -1f));
            return m;
        }

        /// <summary>C++ get_quaternion (Quaternion(basis) in GDScript): the basis must be a rotation (with MathChecks,
        /// else an error and IDENTITY).</summary>
        public Quat GetQuaternion()
        {
            if (GD.MathChecks && !IsRotation())
            {
                GD.MathError("Basis " + this + " must be normalized in order to be casted to a Quaternion. Use get_rotation_quaternion() or call orthonormalized() if the Basis contains linearly independent vectors.");
                return Quat.IDENTITY;
            }
            float trace = row0.x + row1.y + row2.z;
            float t0, t1, t2, t3;
            if (trace > 0.0f)
            {
                float s = MathF.Sqrt(trace + 1.0f);
                t3 = s * 0.5f;
                s = 0.5f / s;
                t0 = (row2.y - row1.z) * s;
                t1 = (row0.z - row2.x) * s;
                t2 = (row1.x - row0.y) * s;
            }
            else
            {
                int i = row0.x < row1.y ? (row1.y < row2.z ? 2 : 1) : (row0.x < row2.z ? 2 : 0);
                int j = (i + 1) % 3;
                int k = (i + 2) % 3;
                float s = MathF.Sqrt(Get(i, i) - Get(j, j) - Get(k, k) + 1.0f);
                float ti = s * 0.5f;
                s = 0.5f / s;
                float tw = (Get(k, j) - Get(j, k)) * s;
                float tj = (Get(j, i) + Get(i, j)) * s;
                float tk = (Get(k, i) + Get(i, k)) * s;
                t0 = t1 = t2 = 0;
                SetTemp(ref t0, ref t1, ref t2, i, ti);
                SetTemp(ref t0, ref t1, ref t2, j, tj);
                SetTemp(ref t0, ref t1, ref t2, k, tk);
                t3 = tw;
            }
            return new Quat(t0, t1, t2, t3);
        }

        static void SetTemp(ref float t0, ref float t1, ref float t2, int idx, float v)
        {
            if (idx == 0) t0 = v; else if (idx == 1) t1 = v; else t2 = v;
        }

        /// <summary>get_rotation_quaternion(): the rotation part (orthonormalized, sign-corrected) as a quaternion.</summary>
        public Quat GetRotationQuaternion() => RotationPart().GetQuaternion();

        /// <summary>C++ get_axis_angle (no rotation check).</summary>
        public void GetAxisAngle(out Vec3 axis, out float angle)
        {
            float x, y, z;
            if (GD.IsZeroApproxF(row0.y - row1.x) && GD.IsZeroApproxF(row0.z - row2.x) && GD.IsZeroApproxF(row1.z - row2.y))
            {
                if (IsDiagonal() && (MathF.Abs(row0.x + row1.y + row2.z - 3) < 3 * GD.CMP_EPSILON))
                {
                    axis = new Vec3(0f, 1f, 0f);
                    angle = 0;
                    return;
                }
                float xx = (row0.x + 1) / 2;
                float yy = (row1.y + 1) / 2;
                float zz = (row2.z + 1) / 2;
                float xy = (row0.y + row1.x) / 4;
                float xz = (row0.z + row2.x) / 4;
                float yz = (row1.z + row2.y) / 4;
                if ((xx > yy) && (xx > zz))
                {
                    if (xx < GD.CMP_EPSILON) { x = 0; y = (float)GD.SQRT12; z = (float)GD.SQRT12; }
                    else { x = MathF.Sqrt(xx); y = xy / x; z = xz / x; }
                }
                else if (yy > zz)
                {
                    if (yy < GD.CMP_EPSILON) { x = (float)GD.SQRT12; y = 0; z = (float)GD.SQRT12; }
                    else { y = MathF.Sqrt(yy); x = xy / y; z = yz / y; }
                }
                else
                {
                    if (zz < GD.CMP_EPSILON) { x = (float)GD.SQRT12; y = (float)GD.SQRT12; z = 0; }
                    else { z = MathF.Sqrt(zz); x = xz / z; y = yz / z; }
                }
                axis = new Vec3(x, y, z);
                angle = (float)GD.PI;
                return;
            }
            double s = MathF.Sqrt((row2.y - row1.z) * (row2.y - row1.z) + (row0.z - row2.x) * (row0.z - row2.x) + (row1.x - row0.y) * (row1.x - row0.y));
            if (Math.Abs(s) < GD.CMP_EPSILON) s = 1;
            x = (float)((row2.y - row1.z) / s);
            y = (float)((row0.z - row2.x) / s);
            z = (float)((row1.x - row0.y) / s);
            axis = new Vec3(x, y, z);
            angle = GD.AcosF((row0.x + row1.y + row2.z - 1) / 2);
        }

        /// <summary>C++ get_rotation_axis_angle.</summary>
        public void GetRotationAxisAngle(out Vec3 axis, out float angle) => RotationPart().GetAxisAngle(out axis, out angle);

        // ------------------------------------------------------------------ interpolation / look-at
        public Basis Lerp(Basis to, double weight)
        {
            Basis b;
            b.row0 = row0.Lerp(to.row0, weight);
            b.row1 = row1.Lerp(to.row1, weight);
            b.row2 = row2.Lerp(to.row2, weight);
            return b;
        }

        /// <summary>slerp(to, weight): quaternion slerp of the rotations (both must be rotations), row lengths lerped.</summary>
        public Basis Slerp(Basis to, double weight)
        {
            float w = (float)weight;
            Quat from = GetQuaternion();
            Quat toQ = to.GetQuaternion();
            Basis b = new Basis(from.Slerp(toQ, w));
            float k0 = GD.LerpF(row0.Length(), to.row0.Length(), w);
            float k1 = GD.LerpF(row1.Length(), to.row1.Length(), w);
            float k2 = GD.LerpF(row2.Length(), to.row2.Length(), w);
            b.row0 = new Vec3(b.row0.x * k0, b.row0.y * k0, b.row0.z * k0);
            b.row1 = new Vec3(b.row1.x * k1, b.row1.y * k1, b.row1.z * k1);
            b.row2 = new Vec3(b.row2.x * k2, b.row2.y * k2, b.row2.z * k2);
            return b;
        }

        public static Basis LookingAt(Vec3 target) => LookingAt(target, Vec3.UP, false);

        /// <summary>looking_at(target, up = Vector3.UP, use_model_front = false).</summary>
        public static Basis LookingAt(Vec3 target, Vec3 up, bool useModelFront = false)
        {
            if (GD.MathChecks)
            {
                if (target.IsZeroApprox()) { GD.MathError("The target vector can't be zero."); return IDENTITY; }
                if (up.IsZeroApprox()) { GD.MathError("The up vector can't be zero."); return IDENTITY; }
            }
            Vec3 vZ = target.NormalizedChecked();
            if (!useModelFront) vZ = -vZ;
            Vec3 vX = up.Cross(vZ);
            if (vX.IsZeroApprox())
            {
                GD.PushWarning("Target and up vectors are colinear. This is not advised as it may cause unwanted rotation around local Z axis.");
                vX = up.GetAnyPerpendicular();
            }
            vX = vX.NormalizedChecked();
            Vec3 vY = vZ.Cross(vX);
            return new Basis(vX, vY, vZ);
        }

        /// <summary>C++ rotate_to_align(start, end) (returns the rotated basis).</summary>
        public Basis RotateToAlign(Vec3 startDirection, Vec3 endDirection)
        {
            Vec3 axis = startDirection.Cross(endDirection).NormalizedChecked();
            if (axis.LengthSquared() != 0)
            {
                float dot = startDirection.Dot(endDirection);
                dot = GD.ClampF(dot, -1.0f, 1.0f);
                float angleRads = GD.AcosF(dot);
                return new Basis(axis, angleRads) * this;
            }
            return this;
        }

        // ------------------------------------------------------------------ Variant
        public static implicit operator Var(Basis b) => Var.Of(b);
        public static explicit operator Basis(Var v)
        {
            object o = v.Obj;
            if (o is Basis b) return b;
            if (o is Quat q) return new Basis(q);
            if (o is Xform3 t) return t.basis;
            return IDENTITY;
        }
        public int GodotType => GD.TYPE_BASIS;
        public string GodotStr() => ToString();
        public bool GodotIsZero => this == IDENTITY;
        public uint GodotHash()
        {
            uint h = GHashing.MURMUR3_SEED;
            h = GHashing.Murmur3OneFloat(row0.x, h);
            h = GHashing.Murmur3OneFloat(row0.y, h);
            h = GHashing.Murmur3OneFloat(row0.z, h);
            h = GHashing.Murmur3OneFloat(row1.x, h);
            h = GHashing.Murmur3OneFloat(row1.y, h);
            h = GHashing.Murmur3OneFloat(row1.z, h);
            h = GHashing.Murmur3OneFloat(row2.x, h);
            h = GHashing.Murmur3OneFloat(row2.y, h);
            h = GHashing.Murmur3OneFloat(row2.z, h);
            return GHashing.Fmix32(h);
        }

        public bool GodotOp(char op, Var other, bool selfLeft, out Var result)
        {
            result = Var.Nil;
            object o = other.Obj;
            if (op == '*')
            {
                if (o is Basis b) { result = selfLeft ? this * b : b * this; return true; }
                if (other.IsVec3) { result = selfLeft ? Xform(other.AsVec3()) : XformInv(other.AsVec3()); return true; }
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

    /// <summary>Godot's Quaternion (real_t = float). GDScript's Quaternion() is Quat.IDENTITY (C#'s default is all zero).</summary>
    public struct Quat : IEquatable<Quat>, IGodotValue
    {
        public float x, y, z, w;

        public static readonly Quat IDENTITY = new Quat(0f, 0f, 0f, 1f);

        public Quat(float x, float y, float z, float w) { this.x = x; this.y = y; this.z = z; this.w = w; }
        public Quat(double x, double y, double z, double w) { this.x = (float)x; this.y = (float)y; this.z = (float)z; this.w = (float)w; }

        /// <summary>Quaternion(axis, angle): the axis must be normalized (with MathChecks, else an error and IDENTITY).</summary>
        public Quat(Vec3 axis, double angle)
        {
            x = 0; y = 0; z = 0; w = 1;
            if (GD.MathChecks && !axis.IsNormalized())
            {
                GD.MathError("The axis Vector3 " + axis + " must be normalized.");
                return;
            }
            float a = (float)angle;
            float d = axis.Length();
            if (d == 0)
            {
                w = 0;
            }
            else
            {
                float sinAngle = MathF.Sin(a * 0.5f);
                float cosAngle = MathF.Cos(a * 0.5f);
                float s = sinAngle / d;
                x = axis.x * s;
                y = axis.y * s;
                z = axis.z * s;
                w = cosAngle;
            }
        }

        /// <summary>Quaternion(arc_from, arc_to): the shortest arc between two directions.</summary>
        public Quat(Vec3 arcFrom, Vec3 arcTo)
        {
            x = 0; y = 0; z = 0; w = 1;
            if (GD.MathChecks && (arcFrom.IsZeroApprox() || arcTo.IsZeroApprox()))
            {
                GD.MathError("The vectors must not be zero.");
                return;
            }
            const float ALMOST_ONE = 0.99999975f;
            Vec3 n0 = arcFrom.NormalizedChecked();
            Vec3 n1 = arcTo.NormalizedChecked();
            float d = n0.Dot(n1);
            if (MathF.Abs(d) > ALMOST_ONE)
            {
                if (d >= 0) return;
                Vec3 axis = n0.GetAnyPerpendicular();
                x = axis.x;
                y = axis.y;
                z = axis.z;
                w = 0;
            }
            else
            {
                Vec3 c = n0.Cross(n1);
                float s = MathF.Sqrt((1.0f + d) * 2.0f);
                float rs = 1.0f / s;
                x = c.x * rs;
                y = c.y * rs;
                z = c.z * rs;
                w = s * 0.5f;
            }
            this = Normalized(true);
        }

        /// <summary>Quaternion(basis) (Basis.get_quaternion: the basis must be a rotation).</summary>
        public Quat(Basis b) { this = b.GetQuaternion(); }

        public float this[int i]
        {
            get
            {
                switch (i) { case 0: return x; case 1: return y; case 2: return z; case 3: return w; }
                throw new IndexOutOfRangeException("Quaternion index " + i);
            }
            set
            {
                switch (i) { case 0: x = value; return; case 1: y = value; return; case 2: z = value; return; case 3: w = value; return; }
                throw new IndexOutOfRangeException("Quaternion index " + i);
            }
        }

        public float Dot(Quat q) => x * q.x + y * q.y + z * q.z + w * q.w;
        public float LengthSquared() => Dot(this);
        public float Length() => MathF.Sqrt(LengthSquared());
        public bool IsNormalized() => GD.IsEqualApproxF(LengthSquared(), 1f, GD.UNIT_EPS_F);
        public bool IsEqualApprox(Quat q) => GD.IsEqualApproxF(x, q.x) && GD.IsEqualApproxF(y, q.y) && GD.IsEqualApproxF(z, q.z) && GD.IsEqualApproxF(w, q.w);
        public bool IsSame(Quat q) => GD.IsSameF(x, q.x) && GD.IsSameF(y, q.y) && GD.IsSameF(z, q.z) && GD.IsSameF(w, q.w);
        public bool IsFinite() => GD.IsFiniteF(x) && GD.IsFiniteF(y) && GD.IsFiniteF(z) && GD.IsFiniteF(w);

        public Quat Normalized() => this / (double)Length();

        Quat Normalized(bool warn)
        {
            if (warn && GD.MathChecks && !IsFinite()) GD.PushWarning("Quaternion cannot be normalized, the elements should be finite.");
            return this / (double)Length();
        }

        public Quat Inverse()
        {
            if (GD.MathChecks && !IsNormalized())
            {
                GD.MathError("The quaternion " + this + " must be normalized.");
                return IDENTITY;
            }
            return new Quat(-x, -y, -z, w);
        }

        public Quat Log()
        {
            Vec3 v = GetAxis();
            float a = GetAngle();
            return new Quat(v.x * a, v.y * a, v.z * a, 0f);
        }

        public Quat Exp()
        {
            Vec3 v = new Vec3(x, y, z);
            float theta = v.Length();
            v = v.NormalizedChecked();
            if (theta < GD.CMP_EPSILON || !v.IsNormalized()) return new Quat(0f, 0f, 0f, 1f);
            return new Quat(v, theta);
        }

        public float AngleTo(Quat to)
        {
            float d = Dot(to);
            return GD.AcosF(d * d * 2 - 1);
        }

        public Vec3 GetAxis()
        {
            if (MathF.Abs(w) > 1 - GD.CMP_EPSILON) return new Vec3(x, y, z);
            float r = 1f / MathF.Sqrt(1 - w * w);
            return new Vec3(x * r, y * r, z * r);
        }

        public float GetAngle() => 2 * GD.AcosF(w);

        /// <summary>get_euler(order = YXZ) (the quaternion must be normalized).</summary>
        public Vec3 GetEuler(EulerOrder order = EulerOrder.YXZ)
        {
            if (GD.MathChecks && !IsNormalized())
            {
                GD.MathError("The quaternion " + this + " must be normalized.");
                return new Vec3(0f, 0f, 0f);
            }
            return new Basis(this).GetEuler(order);
        }

        /// <summary>from_euler(euler): YXZ convention.</summary>
        public static Quat FromEuler(Vec3 euler)
        {
            float halfA1 = euler.y * 0.5f;
            float halfA2 = euler.x * 0.5f;
            float halfA3 = euler.z * 0.5f;
            float cosA1 = MathF.Cos(halfA1);
            float sinA1 = MathF.Sin(halfA1);
            float cosA2 = MathF.Cos(halfA2);
            float sinA2 = MathF.Sin(halfA2);
            float cosA3 = MathF.Cos(halfA3);
            float sinA3 = MathF.Sin(halfA3);
            return new Quat(
                sinA1 * cosA2 * sinA3 + cosA1 * sinA2 * cosA3,
                sinA1 * cosA2 * cosA3 - cosA1 * sinA2 * sinA3,
                -sinA1 * sinA2 * cosA3 + cosA1 * cosA2 * sinA3,
                sinA1 * sinA2 * sinA3 + cosA1 * cosA2 * cosA3);
        }

        public Quat Slerp(Quat to, double weight)
        {
            if (GD.MathChecks)
            {
                if (!IsNormalized()) { GD.MathError("The start quaternion " + this + " must be normalized."); return IDENTITY; }
                if (!to.IsNormalized()) { GD.MathError("The end quaternion " + to + " must be normalized."); return IDENTITY; }
            }
            float pw = (float)weight;
            Quat to1;
            float omega, cosom, sinom, scale0, scale1;
            cosom = Dot(to);
            if (cosom < 0.0f)
            {
                cosom = -cosom;
                to1 = -to;
            }
            else
            {
                to1 = to;
            }
            if ((1.0f - cosom) > GD.EPS_F)
            {
                omega = GD.AcosF(cosom);
                sinom = MathF.Sin(omega);
                scale0 = (float)(Math.Sin((1.0 - pw) * omega) / sinom);      // (1.0 is a double in Godot's source)
                scale1 = MathF.Sin(pw * omega) / sinom;
            }
            else
            {
                scale0 = 1.0f - pw;
                scale1 = pw;
            }
            return new Quat(scale0 * x + scale1 * to1.x, scale0 * y + scale1 * to1.y, scale0 * z + scale1 * to1.z, scale0 * w + scale1 * to1.w);
        }

        public Quat Slerpni(Quat to, double weight)
        {
            if (GD.MathChecks)
            {
                if (!IsNormalized()) { GD.MathError("The start quaternion " + this + " must be normalized."); return IDENTITY; }
                if (!to.IsNormalized()) { GD.MathError("The end quaternion " + to + " must be normalized."); return IDENTITY; }
            }
            float pw = (float)weight;
            float dot = Dot(to);
            if (MathF.Abs(dot) > 0.9999f) return this;
            float theta = GD.AcosF(dot);
            float sinT = 1.0f / MathF.Sin(theta);
            float newFactor = MathF.Sin(pw * theta) * sinT;
            float invFactor = MathF.Sin((1.0f - pw) * theta) * sinT;
            return new Quat(invFactor * x + newFactor * to.x, invFactor * y + newFactor * to.y, invFactor * z + newFactor * to.z, invFactor * w + newFactor * to.w);
        }

        static bool SignBit(float f) => BitConverter.SingleToInt32Bits(f) < 0;

        public Quat SphericalCubicInterpolate(Quat b, Quat preA, Quat postB, double weight) =>
            SphericalCubic(b, preA, postB, (float)weight, false, 0, 0, 0);

        public Quat SphericalCubicInterpolateInTime(Quat b, Quat preA, Quat postB, double weight, double bT, double preAT, double postBT) =>
            SphericalCubic(b, preA, postB, (float)weight, true, (float)bT, (float)preAT, (float)postBT);

        Quat SphericalCubic(Quat b, Quat preA, Quat postB, float pw, bool inTime, float bT, float preAT, float postBT)
        {
            if (GD.MathChecks)
            {
                if (!IsNormalized()) { GD.MathError("The start quaternion " + this + " must be normalized."); return IDENTITY; }
                if (!b.IsNormalized()) { GD.MathError("The end quaternion " + b + " must be normalized."); return IDENTITY; }
            }
            Quat fromQ = new Basis(this).GetRotationQuaternion();
            Quat preQ = new Basis(preA).GetRotationQuaternion();
            Quat toQ = new Basis(b).GetRotationQuaternion();
            Quat postQ = new Basis(postB).GetRotationQuaternion();

            bool flip1 = SignBit(fromQ.Dot(preQ));
            preQ = flip1 ? -preQ : preQ;
            bool flip2 = SignBit(fromQ.Dot(toQ));
            toQ = flip2 ? -toQ : toQ;
            bool flip3 = flip2 ? toQ.Dot(postQ) <= 0 : SignBit(toQ.Dot(postQ));
            postQ = flip3 ? -postQ : postQ;

            Quat lnFrom = new Quat(0f, 0f, 0f, 0f);
            Quat lnTo = (fromQ.Inverse() * toQ).Log();
            Quat lnPre = (fromQ.Inverse() * preQ).Log();
            Quat lnPost = (fromQ.Inverse() * postQ).Log();
            Quat ln = new Quat(0f, 0f, 0f, 0f);
            ln.x = Interp(lnFrom.x, lnTo.x, lnPre.x, lnPost.x, pw, inTime, bT, preAT, postBT);
            ln.y = Interp(lnFrom.y, lnTo.y, lnPre.y, lnPost.y, pw, inTime, bT, preAT, postBT);
            ln.z = Interp(lnFrom.z, lnTo.z, lnPre.z, lnPost.z, pw, inTime, bT, preAT, postBT);
            Quat q1 = fromQ * ln.Exp();

            lnFrom = (toQ.Inverse() * fromQ).Log();
            lnTo = new Quat(0f, 0f, 0f, 0f);
            lnPre = (toQ.Inverse() * preQ).Log();
            lnPost = (toQ.Inverse() * postQ).Log();
            ln = new Quat(0f, 0f, 0f, 0f);
            ln.x = Interp(lnFrom.x, lnTo.x, lnPre.x, lnPost.x, pw, inTime, bT, preAT, postBT);
            ln.y = Interp(lnFrom.y, lnTo.y, lnPre.y, lnPost.y, pw, inTime, bT, preAT, postBT);
            ln.z = Interp(lnFrom.z, lnTo.z, lnPre.z, lnPost.z, pw, inTime, bT, preAT, postBT);
            Quat q2 = toQ * ln.Exp();

            return q1.Slerp(q2, pw);
        }

        static float Interp(float from, float to, float pre, float post, float w, bool inTime, float bT, float preT, float postT) =>
            inTime ? GD.CubicInterpolateInTimeF(from, to, pre, post, w, bT, preT, postT) : GD.CubicInterpolateF(from, to, pre, post, w);

        /// <summary>quaternion * vector: rotates the vector (the quaternion must be normalized).</summary>
        public Vec3 Xform(Vec3 v)
        {
            if (GD.MathChecks && !IsNormalized())
            {
                GD.MathError("The quaternion " + this + " must be normalized.");
                return v;
            }
            Vec3 u = new Vec3(x, y, z);
            Vec3 uv = u.Cross(v);
            Vec3 uvw = new Vec3(uv.x * w, uv.y * w, uv.z * w);
            Vec3 t = uvw + u.Cross(uv);
            return v + new Vec3(t.x * 2f, t.y * 2f, t.z * 2f);
        }

        public Vec3 XformInv(Vec3 v) => Inverse().Xform(v);

        public static Quat operator *(Quat a, Quat q)
        {
            float xx = a.w * q.x + a.x * q.w + a.y * q.z - a.z * q.y;
            float yy = a.w * q.y + a.y * q.w + a.z * q.x - a.x * q.z;
            float zz = a.w * q.z + a.z * q.w + a.x * q.y - a.y * q.x;
            float ww = a.w * q.w - a.x * q.x - a.y * q.y - a.z * q.z;
            return new Quat(xx, yy, zz, ww);
        }

        public static Vec3 operator *(Quat q, Vec3 v) => q.Xform(v);
        public static Vec3 operator *(Vec3 v, Quat q) => q.XformInv(v);
        public static Quat operator *(Quat q, double s) { float f = (float)s; return new Quat(q.x * f, q.y * f, q.z * f, q.w * f); }
        public static Quat operator *(double s, Quat q) => q * s;
        /// <summary>q / s: Godot multiplies by (1 / s).</summary>
        public static Quat operator /(Quat q, double s) { float r = 1 / (float)s; return new Quat(q.x * r, q.y * r, q.z * r, q.w * r); }
        public static Quat operator +(Quat a, Quat b) => new Quat(a.x + b.x, a.y + b.y, a.z + b.z, a.w + b.w);
        public static Quat operator -(Quat a, Quat b) => new Quat(a.x - b.x, a.y - b.y, a.z - b.z, a.w - b.w);
        public static Quat operator -(Quat a) => new Quat(-a.x, -a.y, -a.z, -a.w);
        public static Quat operator +(Quat a) => a;
        public static bool operator ==(Quat a, Quat b) => a.x == b.x && a.y == b.y && a.z == b.z && a.w == b.w;
        public static bool operator !=(Quat a, Quat b) => a.x != b.x || a.y != b.y || a.z != b.z || a.w != b.w;
        public bool Equals(Quat o) => this == o;
        public override bool Equals(object o) => o is Quat q && this == q;
        public override int GetHashCode() => unchecked((int)GodotHash());
        public override string ToString() => "(" + GFormat.NumRealF(x, false) + ", " + GFormat.NumRealF(y, false) + ", " + GFormat.NumRealF(z, false) + ", " + GFormat.NumRealF(w, false) + ")";

        // ------------------------------------------------------------------ Variant
        public static implicit operator Var(Quat q) => Var.Of(q);
        public static explicit operator Quat(Var v)
        {
            object o = v.Obj;
            if (o is Quat q) return q;
            if (o is Basis b) return b.GetQuaternion();
            return IDENTITY;
        }
        public int GodotType => GD.TYPE_QUATERNION;
        public string GodotStr() => ToString();
        public bool GodotIsZero => this == IDENTITY;
        public uint GodotHash()
        {
            uint h = GHashing.MURMUR3_SEED;
            h = GHashing.Murmur3OneFloat(x, h);
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
            if (o is Quat q)
            {
                Quat l = selfLeft ? this : q, r = selfLeft ? q : this;
                switch (op)
                {
                    case '+': result = l + r; return true;
                    case '-': result = l - r; return true;
                    case '*': result = l * r; return true;
                }
                return false;
            }
            if (op == '*' && other.IsVec3) { result = selfLeft ? Xform(other.AsVec3()) : XformInv(other.AsVec3()); return true; }
            if (other.IsNum)
            {
                double s = other.IsInt ? (double)(float)other.AsLong() : other.AsFloat();
                if (op == '*') { result = this * s; return true; }
                if (op == '/' && selfLeft) { result = this / s; return true; }
            }
            return false;
        }
    }
}
