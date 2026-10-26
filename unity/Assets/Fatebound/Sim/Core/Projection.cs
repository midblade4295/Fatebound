// Fatebound (Unity port): Godot's Projection (core/math/projection.{h,cpp}), real_t = float: a column-major 4x4 matrix
// (columns x, y, z, w). What Camera3D needs: create_perspective / create_orthogonal(_aspect) / create_frustum(_aspect)
// with flip_fov (Camera3D passes keep_aspect == KEEP_WIDTH), xform of Vector4 / Vector3, inverse, the frustum planes,
// near/far/fov/aspect queries. GDScript's Projection() is Projection.IDENTITY (C#'s default is the zero matrix).
using System;

namespace Fatebound.Sim
{
    public struct Projection : IEquatable<Projection>, IGodotValue
    {
        public Vec4 x, y, z, w;

        public const int PLANE_NEAR = 0, PLANE_FAR = 1, PLANE_LEFT = 2, PLANE_TOP = 3, PLANE_RIGHT = 4, PLANE_BOTTOM = 5;

        public static readonly Projection IDENTITY = new Projection(new Vec4(1f, 0f, 0f, 0f), new Vec4(0f, 1f, 0f, 0f), new Vec4(0f, 0f, 1f, 0f), new Vec4(0f, 0f, 0f, 1f));
        public static readonly Projection ZERO = default;

        public Projection(Vec4 xAxis, Vec4 yAxis, Vec4 zAxis, Vec4 wAxis) { x = xAxis; y = yAxis; z = zAxis; w = wAxis; }

        /// <summary>Projection(transform).</summary>
        public Projection(Xform3 t)
        {
            Basis b = t.basis;
            x = new Vec4(b.row0.x, b.row1.x, b.row2.x, 0f);
            y = new Vec4(b.row0.y, b.row1.y, b.row2.y, 0f);
            z = new Vec4(b.row0.z, b.row1.z, b.row2.z, 0f);
            w = new Vec4(t.origin.x, t.origin.y, t.origin.z, 1f);
        }

        /// <summary>projection[i]: column i.</summary>
        public Vec4 this[int column]
        {
            get
            {
                switch (column) { case 0: return x; case 1: return y; case 2: return z; case 3: return w; }
                throw new IndexOutOfRangeException("Projection index " + column);
            }
            set
            {
                switch (column) { case 0: x = value; return; case 1: y = value; return; case 2: z = value; return; case 3: w = value; return; }
                throw new IndexOutOfRangeException("Projection index " + column);
            }
        }

        /// <summary>C++ columns[c][r].</summary>
        public float this[int c, int r]
        {
            get => this[c][r];
            set
            {
                switch (c)
                {
                    case 0: x[r] = value; return;
                    case 1: y[r] = value; return;
                    case 2: z[r] = value; return;
                    case 3: w[r] = value; return;
                }
                throw new IndexOutOfRangeException("Projection index " + c);
            }
        }

        /// <summary>The flat column-major element m[i] (C++ `(real_t *)columns`).</summary>
        float M(int i) => this[i >> 2][i & 3];

        public float Determinant()
        {
            Vec4 c0 = x, c1 = y, c2 = z, c3 = w;
            return c0.w * c1.z * c2.y * c3.x - c0.z * c1.w * c2.y * c3.x -
                c0.w * c1.y * c2.z * c3.x + c0.y * c1.w * c2.z * c3.x +
                c0.z * c1.y * c2.w * c3.x - c0.y * c1.z * c2.w * c3.x -
                c0.w * c1.z * c2.x * c3.y + c0.z * c1.w * c2.x * c3.y +
                c0.w * c1.x * c2.z * c3.y - c0.x * c1.w * c2.z * c3.y -
                c0.z * c1.x * c2.w * c3.y + c0.x * c1.z * c2.w * c3.y +
                c0.w * c1.y * c2.x * c3.z - c0.y * c1.w * c2.x * c3.z -
                c0.w * c1.x * c2.y * c3.z + c0.x * c1.w * c2.y * c3.z +
                c0.y * c1.x * c2.w * c3.z - c0.x * c1.y * c2.w * c3.z -
                c0.z * c1.y * c2.x * c3.w + c0.y * c1.z * c2.x * c3.w +
                c0.z * c1.x * c2.y * c3.w - c0.x * c1.z * c2.y * c3.w -
                c0.y * c1.x * c2.z * c3.w + c0.x * c1.y * c2.z * c3.w;
        }

        // ------------------------------------------------------------------ products
        public static Projection operator *(Projection a, Projection m)
        {
            Projection r = default;
            for (int j = 0; j < 4; j++)
            {
                Vec4 mj = m[j];
                for (int i = 0; i < 4; i++)
                {
                    float ab = 0;
                    for (int k = 0; k < 4; k++) ab += a[k][i] * mj[k];
                    r[j, i] = ab;
                }
            }
            return r;
        }

        public Vec4 Xform(Vec4 v) => new Vec4(
            x.x * v.x + y.x * v.y + z.x * v.z + w.x * v.w,
            x.y * v.x + y.y * v.y + z.y * v.z + w.y * v.w,
            x.z * v.x + y.z * v.y + z.z * v.z + w.z * v.w,
            x.w * v.x + y.w * v.y + z.w * v.z + w.w * v.w);

        public Vec4 XformInv(Vec4 v) => new Vec4(
            x.x * v.x + x.y * v.y + x.z * v.z + x.w * v.w,
            y.x * v.x + y.y * v.y + y.z * v.z + y.w * v.w,
            z.x * v.x + z.y * v.y + z.z * v.z + z.w * v.w,
            w.x * v.x + w.y * v.y + w.z * v.z + w.w * v.w);

        /// <summary>C++ xform(Vector3): the point projected, divided by w.</summary>
        public Vec3 Xform(Vec3 v)
        {
            float rx = x.x * v.x + y.x * v.y + z.x * v.z + w.x;
            float ry = x.y * v.x + y.y * v.y + z.y * v.z + w.y;
            float rz = x.z * v.x + y.z * v.y + z.z * v.z + w.z;
            float rw = x.w * v.x + y.w * v.y + z.w * v.z + w.w;
            return new Vec3(rx / rw, ry / rw, rz / rw);
        }

        /// <summary>C++ xform4(Plane): the plane as a 4-vector (normal, d).</summary>
        public Plane Xform4(Plane p) => new Plane(
            x.x * p.normal.x + y.x * p.normal.y + z.x * p.normal.z + w.x * p.d,
            x.y * p.normal.x + y.y * p.normal.y + z.y * p.normal.z + w.y * p.d,
            x.z * p.normal.x + y.z * p.normal.y + z.z * p.normal.z + w.z * p.d,
            x.w * p.normal.x + y.w * p.normal.y + z.w * p.normal.z + w.w * p.d);

        public static Vec4 operator *(Projection p, Vec4 v) => p.Xform(v);
        public static Vec4 operator *(Vec4 v, Projection p) => p.XformInv(v);
        public static bool operator ==(Projection a, Projection b) => a.x == b.x && a.y == b.y && a.z == b.z && a.w == b.w;
        public static bool operator !=(Projection a, Projection b) => !(a == b);
        public bool Equals(Projection o) => this == o;
        public override bool Equals(object o) => o is Projection p && this == p;
        public override int GetHashCode() => unchecked((int)GodotHash());
        public override string ToString() => "[X: " + x + ", Y: " + y + ", Z: " + z + ", W: " + w + "]";
        public bool IsSame(Projection p) => x.IsSame(p.x) && y.IsSame(p.y) && z.IsSame(p.z) && w.IsSame(p.w);

        // ------------------------------------------------------------------ setters (C++), static creators (GDScript)
        public void SetIdentity() => this = IDENTITY;
        public void SetZero() => this = default;

        /// <summary>set_perspective(fovy_degrees, aspect, z_near, z_far, flip_fov): flip_fov makes the fov horizontal
        /// (Camera3D's KEEP_WIDTH). A zero depth range, angle or aspect leaves the matrix unchanged.</summary>
        public void SetPerspective(double fovyDegrees, double aspect, double zNear, double zFar, bool flipFov = false)
        {
            float fovy = (float)fovyDegrees, asp = (float)aspect, near = (float)zNear, far = (float)zFar;
            if (flipFov) fovy = GetFovyF(fovy, (float)(1.0 / asp));
            float radians = (float)(fovy / 2.0 * (GD.PI / 180.0));
            float deltaZ = far - near;
            float sine = MathF.Sin(radians);
            if ((deltaZ == 0) || (sine == 0) || (asp == 0)) return;
            float cotangent = MathF.Cos(radians) / sine;
            SetIdentity();
            x.x = cotangent / asp;
            y.y = cotangent;
            z.z = -(far + near) / deltaZ;
            z.w = -1;
            w.z = -2 * near * far / deltaZ;
            w.w = 0;
        }

        public void SetOrthogonal(double left, double right, double bottom, double top, double zNear, double zFar)
        {
            float l = (float)left, r = (float)right, b = (float)bottom, t = (float)top, n = (float)zNear, f = (float)zFar;
            SetIdentity();
            x.x = (float)(2.0 / (r - l));
            w.x = -((r + l) / (r - l));
            y.y = (float)(2.0 / (t - b));
            w.y = -((t + b) / (t - b));
            z.z = (float)(-2.0 / (f - n));
            w.z = -((f + n) / (f - n));
            w.w = 1.0f;
        }

        /// <summary>set_orthogonal(size, aspect, z_near, z_far, flip_fov): size is the height (the width with flip_fov).</summary>
        public void SetOrthogonalAspect(double size, double aspect, double zNear, double zFar, bool flipFov = false)
        {
            float s = (float)size, a = (float)aspect;
            if (!flipFov) s *= a;
            SetOrthogonal(-s / 2, +s / 2, -s / a / 2, +s / a / 2, (float)zNear, (float)zFar);
        }

        public void SetFrustum(double left, double right, double bottom, double top, double zNear, double zFar)
        {
            float l = (float)left, r = (float)right, b = (float)bottom, t = (float)top, n = (float)zNear, f = (float)zFar;
            if (r <= l) { GD.MathError("Condition \"p_right <= p_left\" is true."); return; }
            if (t <= b) { GD.MathError("Condition \"p_top <= p_bottom\" is true."); return; }
            if (f <= n) { GD.MathError("Condition \"p_far <= p_near\" is true."); return; }
            float xx = 2 * n / (r - l);
            float yy = 2 * n / (t - b);
            float a = (r + l) / (r - l);
            float bb = (t + b) / (t - b);
            float c = -(f + n) / (f - n);
            float d = -2 * f * n / (f - n);
            x = new Vec4(xx, 0f, 0f, 0f);
            y = new Vec4(0f, yy, 0f, 0f);
            z = new Vec4(a, bb, c, -1f);
            w = new Vec4(0f, 0f, d, 0f);
        }

        public void SetFrustumAspect(double size, double aspect, Vec2 offset, double zNear, double zFar, bool flipFov = false)
        {
            float s = (float)size, a = (float)aspect;
            if (!flipFov) s *= a;
            SetFrustum(-s / 2 + offset.x, +s / 2 + offset.x, -s / a / 2 + offset.y, +s / a / 2 + offset.y, (float)zNear, (float)zFar);
        }

        public static Projection CreatePerspective(double fovy, double aspect, double zNear, double zFar, bool flipFov = false)
        {
            Projection p = IDENTITY;
            p.SetPerspective(fovy, aspect, zNear, zFar, flipFov);
            return p;
        }

        public static Projection CreateOrthogonal(double left, double right, double bottom, double top, double zNear, double zFar)
        {
            Projection p = IDENTITY;
            p.SetOrthogonal(left, right, bottom, top, zNear, zFar);
            return p;
        }

        public static Projection CreateOrthogonalAspect(double size, double aspect, double zNear, double zFar, bool flipFov = false)
        {
            Projection p = IDENTITY;
            p.SetOrthogonalAspect(size, aspect, zNear, zFar, flipFov);
            return p;
        }

        public static Projection CreateFrustum(double left, double right, double bottom, double top, double zNear, double zFar)
        {
            Projection p = IDENTITY;
            p.SetFrustum(left, right, bottom, top, zNear, zFar);
            return p;
        }

        public static Projection CreateFrustumAspect(double size, double aspect, Vec2 offset, double zNear, double zFar, bool flipFov = false)
        {
            Projection p = IDENTITY;
            p.SetFrustumAspect(size, aspect, offset, zNear, zFar, flipFov);
            return p;
        }

        public static Projection CreateDepthCorrection(bool flipY)
        {
            Projection p;
            p.x = new Vec4(1f, 0f, 0f, 0f);
            p.y = new Vec4(0f, flipY ? -1f : 1f, 0f, 0f);
            p.z = new Vec4(0f, 0f, -0.5f, 0f);      // (remap_z and reverse_z on, as the GDScript binding calls it)
            p.w = new Vec4(0f, 0f, 0.5f, 1f);
            return p;
        }

        public static Projection CreateFitAabb(Aabb aabb)
        {
            Vec3 min = aabb.position, max = aabb.position + aabb.size;
            Projection p;
            p.x = new Vec4(2 / (max.x - min.x), 0f, 0f, 0f);
            p.y = new Vec4(0f, 2 / (max.y - min.y), 0f, 0f);
            p.z = new Vec4(0f, 0f, 2 / (max.z - min.z), 0f);
            p.w = new Vec4(-(max.x + min.x) / (max.x - min.x), -(max.y + min.y) / (max.y - min.y), -(max.z + min.z) / (max.z - min.z), 1f);
            return p;
        }

        /// <summary>get_fovy(fovx, aspect) (static): the vertical fov for a horizontal one.</summary>
        public static float GetFovy(double fovx, double aspect) => GetFovyF((float)fovx, (float)aspect);

        static float GetFovyF(float fovx, float aspect) =>
            (float)((Math.Atan(aspect * Math.Tan(GD.DegToRadF(fovx) * 0.5)) * 2.0) * (180.0 / GD.PI));

        public Projection PerspectiveZnearAdjusted(double newZnear)
        {
            Projection p = this;
            float zfar = GetZFar();
            float znear = (float)newZnear;
            float deltaZ = zfar - znear;
            p.z.z = -(zfar + znear) / deltaZ;
            p.w.z = -2 * znear * zfar / deltaZ;
            return p;
        }

        public Projection FlippedY()
        {
            Projection p = this;
            p.y = -p.y;
            return p;
        }

        public Projection JitterOffseted(Vec2 offset)
        {
            Projection p = this;
            p.w.x += offset.x;
            p.w.y += offset.y;
            return p;
        }

        // ------------------------------------------------------------------ queries
        public float GetZFar() => (w.w - w.z) / (z.w - z.z);
        public float GetZNear() => (w.w + w.z) / (z.w + z.z);
        public float GetAspect() => y.y / x.x;
        public bool IsOrthogonal() => z.w == 0.0f;
        public float GetLodMultiplier() => 2 / x.x;

        public float GetFov()
        {
            if (z.x == 0) return GD.RadToDegF(2 * MathF.Atan2(1, x.x));
            float right = MathF.Atan2(z.x + 1, x.x);
            float left = MathF.Atan2(z.x - 1, x.x);
            return GD.RadToDegF(right - left);
        }

        public int GetPixelsPerMeter(long forPixelWidth)
        {
            float width = 2 * (-GetZNear() * z.w + w.w) / x.x;
            return (int)(forPixelWidth / width);
        }

        public Vec2 GetViewportHalfExtents()
        {
            float ww = -GetZNear() * z.w + w.w;
            return new Vec2(ww / x.x, ww / y.y);
        }

        public Vec2 GetFarPlaneHalfExtents()
        {
            float ww = -GetZFar() * z.w + w.w;
            return new Vec2(ww / x.x, ww / y.y);
        }

        /// <summary>get_projection_plane(plane): PLANE_NEAR ... PLANE_BOTTOM, normals pointing out of the frustum.</summary>
        public Plane GetProjectionPlane(int plane)
        {
            float a, b, c, d;
            switch (plane)
            {
                case PLANE_NEAR: a = M(3) + M(2); b = M(7) + M(6); c = M(11) + M(10); d = M(15) + M(14); break;
                case PLANE_FAR: a = M(3) - M(2); b = M(7) - M(6); c = M(11) - M(10); d = M(15) - M(14); break;
                case PLANE_LEFT: a = M(3) + M(0); b = M(7) + M(4); c = M(11) + M(8); d = M(15) + M(12); break;
                case PLANE_TOP: a = M(3) - M(1); b = M(7) - M(5); c = M(11) - M(9); d = M(15) - M(13); break;
                case PLANE_RIGHT: a = M(3) - M(0); b = M(7) - M(4); c = M(11) - M(8); d = M(15) - M(12); break;
                case PLANE_BOTTOM: a = M(3) + M(1); b = M(7) + M(5); c = M(11) + M(9); d = M(15) + M(13); break;
                default: return default;
            }
            Plane p = new Plane(a, b, c, d);
            p.normal = -p.normal;
            return p.Normalized();
        }

        /// <summary>C++ get_projection_planes(transform): the six planes (near, far, left, top, right, bottom) moved by
        /// the camera transform, written into `planes` (length 6).</summary>
        public void GetProjectionPlanes(Xform3 transform, Span<Plane> planes)
        {
            for (int i = 0; i < 6; i++) planes[i] = transform.Xform(GetProjectionPlane(i));
        }

        public Plane[] GetProjectionPlanes(Xform3 transform)
        {
            var planes = new Plane[6];
            GetProjectionPlanes(transform, planes);
            return planes;
        }

        /// <summary>C++ get_endpoints(transform, 8 points): the frustum corners (far then near).</summary>
        public bool GetEndpoints(Xform3 transform, Span<Vec3> points)
        {
            Span<Plane> planes = stackalloc Plane[6];
            GetProjectionPlanes(Xform3.IDENTITY, planes);
            ReadOnlySpan<int> inter = stackalloc int[] {
                PLANE_FAR, PLANE_LEFT, PLANE_TOP, PLANE_FAR, PLANE_LEFT, PLANE_BOTTOM, PLANE_FAR, PLANE_RIGHT, PLANE_TOP, PLANE_FAR, PLANE_RIGHT, PLANE_BOTTOM,
                PLANE_NEAR, PLANE_LEFT, PLANE_TOP, PLANE_NEAR, PLANE_LEFT, PLANE_BOTTOM, PLANE_NEAR, PLANE_RIGHT, PLANE_TOP, PLANE_NEAR, PLANE_RIGHT, PLANE_BOTTOM };
            for (int i = 0; i < 8; i++)
            {
                if (!planes[inter[i * 3]].Intersect3(planes[inter[i * 3 + 1]], planes[inter[i * 3 + 2]], out Vec3 point))
                {
                    GD.MathError("Condition \"!res\" is true. Returning: false");
                    return false;
                }
                points[i] = transform.Xform(point);
            }
            return true;
        }

        // ------------------------------------------------------------------ inverse
        /// <summary>inverse(): Gauss-Jordan with partial pivoting (Mesa's util_invert_mat4x4, as Godot). A singular
        /// matrix reports an error and comes back unchanged.</summary>
        public Projection Inverse()
        {
            Span<float> wt = stackalloc float[32];
            for (int r = 0; r < 4; r++)
            {
                for (int c = 0; c < 4; c++) wt[r * 8 + c] = this[c][r];
                for (int c = 0; c < 4; c++) wt[r * 8 + 4 + c] = r == c ? 1.0f : 0.0f;
            }
            int r0 = 0, r1 = 8, r2 = 16, r3 = 24;
            float m0, m1, m2, m3, s;

            if (MathF.Abs(wt[r3 + 0]) > MathF.Abs(wt[r2 + 0])) Swap(ref r3, ref r2);
            if (MathF.Abs(wt[r2 + 0]) > MathF.Abs(wt[r1 + 0])) Swap(ref r2, ref r1);
            if (MathF.Abs(wt[r1 + 0]) > MathF.Abs(wt[r0 + 0])) Swap(ref r1, ref r0);
            if (0.0 == wt[r0 + 0]) return Singular();

            m1 = wt[r1 + 0] / wt[r0 + 0];
            m2 = wt[r2 + 0] / wt[r0 + 0];
            m3 = wt[r3 + 0] / wt[r0 + 0];
            for (int c = 1; c <= 3; c++)
            {
                s = wt[r0 + c];
                wt[r1 + c] -= m1 * s;
                wt[r2 + c] -= m2 * s;
                wt[r3 + c] -= m3 * s;
            }
            for (int c = 4; c <= 7; c++)
            {
                s = wt[r0 + c];
                if (s != 0.0)
                {
                    wt[r1 + c] -= m1 * s;
                    wt[r2 + c] -= m2 * s;
                    wt[r3 + c] -= m3 * s;
                }
            }

            if (MathF.Abs(wt[r3 + 1]) > MathF.Abs(wt[r2 + 1])) Swap(ref r3, ref r2);
            if (MathF.Abs(wt[r2 + 1]) > MathF.Abs(wt[r1 + 1])) Swap(ref r2, ref r1);
            if (0.0 == wt[r1 + 1]) return Singular();

            m2 = wt[r2 + 1] / wt[r1 + 1];
            m3 = wt[r3 + 1] / wt[r1 + 1];
            wt[r2 + 2] -= m2 * wt[r1 + 2];
            wt[r3 + 2] -= m3 * wt[r1 + 2];
            wt[r2 + 3] -= m2 * wt[r1 + 3];
            wt[r3 + 3] -= m3 * wt[r1 + 3];
            for (int c = 4; c <= 7; c++)
            {
                s = wt[r1 + c];
                if (0.0 != s)
                {
                    wt[r2 + c] -= m2 * s;
                    wt[r3 + c] -= m3 * s;
                }
            }

            if (MathF.Abs(wt[r3 + 2]) > MathF.Abs(wt[r2 + 2])) Swap(ref r3, ref r2);
            if (0.0 == wt[r2 + 2]) return Singular();

            m3 = wt[r3 + 2] / wt[r2 + 2];
            for (int c = 3; c <= 7; c++) wt[r3 + c] -= m3 * wt[r2 + c];

            if (0.0 == wt[r3 + 3]) return Singular();

            s = (float)(1.0 / wt[r3 + 3]);
            for (int c = 4; c <= 7; c++) wt[r3 + c] *= s;

            m2 = wt[r2 + 3];
            s = (float)(1.0 / wt[r2 + 2]);
            for (int c = 4; c <= 7; c++) wt[r2 + c] = s * (wt[r2 + c] - wt[r3 + c] * m2);
            m1 = wt[r1 + 3];
            for (int c = 4; c <= 7; c++) wt[r1 + c] -= wt[r3 + c] * m1;
            m0 = wt[r0 + 3];
            for (int c = 4; c <= 7; c++) wt[r0 + c] -= wt[r3 + c] * m0;

            m1 = wt[r1 + 2];
            s = (float)(1.0 / wt[r1 + 1]);
            for (int c = 4; c <= 7; c++) wt[r1 + c] = s * (wt[r1 + c] - wt[r2 + c] * m1);
            m0 = wt[r0 + 2];
            for (int c = 4; c <= 7; c++) wt[r0 + c] -= wt[r2 + c] * m0;

            m0 = wt[r0 + 1];
            s = (float)(1.0 / wt[r0 + 0]);
            for (int c = 4; c <= 7; c++) wt[r0 + c] = s * (wt[r0 + c] - wt[r1 + c] * m0);

            // MAT(out, r, c) = out[c * 4 + r]: column c of the result holds row r's entries
            Projection o;
            o.x = new Vec4(wt[r0 + 4], wt[r1 + 4], wt[r2 + 4], wt[r3 + 4]);
            o.y = new Vec4(wt[r0 + 5], wt[r1 + 5], wt[r2 + 5], wt[r3 + 5]);
            o.z = new Vec4(wt[r0 + 6], wt[r1 + 6], wt[r2 + 6], wt[r3 + 6]);
            o.w = new Vec4(wt[r0 + 7], wt[r1 + 7], wt[r2 + 7], wt[r3 + 7]);
            return o;
        }

        static void Swap(ref int a, ref int b) { int t = a; a = b; b = t; }

        Projection Singular()
        {
            GD.MathError("Condition \"0.0 == r0[0]\" is true.");
            return this;
        }

        // ------------------------------------------------------------------ Variant
        public static implicit operator Var(Projection p) => Var.Of(p);
        public static explicit operator Projection(Var v)
        {
            object o = v.Obj;
            if (o is Projection p) return p;
            if (o is Xform3 t) return new Projection(t);
            return IDENTITY;
        }
        public int GodotType => GD.TYPE_PROJECTION;
        public string GodotStr() => ToString();
        public bool GodotIsZero => this == IDENTITY;
        public uint GodotHash()
        {
            uint h = GHashing.MURMUR3_SEED;
            for (int c = 0; c < 4; c++)
            {
                Vec4 col = this[c];
                h = GHashing.Murmur3OneFloat(col.x, h);
                h = GHashing.Murmur3OneFloat(col.y, h);
                h = GHashing.Murmur3OneFloat(col.z, h);
                h = GHashing.Murmur3OneFloat(col.w, h);
            }
            return GHashing.Fmix32(h);
        }

        public bool GodotOp(char op, Var other, bool selfLeft, out Var result)
        {
            result = Var.Nil;
            if (op != '*') return false;
            object o = other.Obj;
            if (o is Projection p) { result = selfLeft ? this * p : p * this; return true; }
            if (o is Vec4 v) { result = selfLeft ? Xform(v) : XformInv(v); return true; }
            return false;
        }
    }
}
