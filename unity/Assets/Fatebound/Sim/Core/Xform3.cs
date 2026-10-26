// Fatebound (Unity port): Godot's Transform3D, AABB and Plane (core/math/transform_3d.*, aabb.*, plane.*), real_t =
// float. GDScript's Transform3D() is Xform3.IDENTITY (C#'s default has a zero basis); AABB() and Plane() are all zero
// in Godot too, so `default` is right for those.
using System;

namespace Fatebound.Sim
{
    public struct Xform3 : IEquatable<Xform3>, IGodotValue
    {
        public Basis basis;
        public Vec3 origin;

        public static readonly Xform3 IDENTITY = new Xform3(Basis.IDENTITY, new Vec3(0f, 0f, 0f));
        public static readonly Xform3 FLIP_X = new Xform3(Basis.FLIP_X, new Vec3(0f, 0f, 0f));
        public static readonly Xform3 FLIP_Y = new Xform3(Basis.FLIP_Y, new Vec3(0f, 0f, 0f));
        public static readonly Xform3 FLIP_Z = new Xform3(Basis.FLIP_Z, new Vec3(0f, 0f, 0f));

        public Xform3(Basis basis, Vec3 origin) { this.basis = basis; this.origin = origin; }
        /// <summary>Transform3D(x_axis, y_axis, z_axis, origin).</summary>
        public Xform3(Vec3 xAxis, Vec3 yAxis, Vec3 zAxis, Vec3 origin) { basis = new Basis(xAxis, yAxis, zAxis); this.origin = origin; }
        /// <summary>Transform3D(projection): the upper 3x4 of the matrix.</summary>
        public Xform3(Projection p)
        {
            basis = Basis.FromRows(p.x.x, p.y.x, p.z.x, p.x.y, p.y.y, p.z.y, p.x.z, p.y.z, p.z.z);
            origin = new Vec3(p.w.x, p.w.y, p.w.z);
        }

        public Basis GetBasis() => basis;
        public Vec3 GetOrigin() => origin;

        /// <summary>transform[i]: basis columns 0..2, origin 3.</summary>
        public Vec3 this[int i]
        {
            get
            {
                if (i == 3) return origin;
                if ((uint)i > 2) throw new IndexOutOfRangeException("Transform3D index " + i);
                return basis.GetColumn(i);
            }
            set
            {
                if (i == 3) { origin = value; return; }
                if ((uint)i > 2) throw new IndexOutOfRangeException("Transform3D index " + i);
                basis.SetColumn(i, value);
            }
        }

        public Vec3 Xform(Vec3 v) => new Vec3(basis.row0.Dot(v) + origin.x, basis.row1.Dot(v) + origin.y, basis.row2.Dot(v) + origin.z);

        public Vec3 XformInv(Vec3 p)
        {
            Vec3 v = p - origin;
            return new Vec3(
                (basis.row0.x * v.x) + (basis.row1.x * v.y) + (basis.row2.x * v.z),
                (basis.row0.y * v.x) + (basis.row1.y * v.y) + (basis.row2.y * v.z),
                (basis.row0.z * v.x) + (basis.row1.z * v.y) + (basis.row2.z * v.z));
        }

        public Aabb Xform(Aabb aabb)
        {
            Vec3 min = aabb.position;
            Vec3 max = aabb.position + aabb.size;
            Vec3 tmin = default, tmax = default;
            for (int i = 0; i < 3; i++)
            {
                tmin[i] = tmax[i] = origin[i];
                Vec3 row = basis.GetRow(i);
                for (int j = 0; j < 3; j++)
                {
                    float e = row[j] * min[j];
                    float f = row[j] * max[j];
                    if (e < f)
                    {
                        tmin[i] += e;
                        tmax[i] += f;
                    }
                    else
                    {
                        tmin[i] += f;
                        tmax[i] += e;
                    }
                }
            }
            return new Aabb(tmin, tmax - tmin);
        }

        public Aabb XformInv(Aabb a)
        {
            Vec3 p = a.position, s = a.size;
            Aabb ret = new Aabb(XformInv(new Vec3(p.x + s.x, p.y + s.y, p.z + s.z)), new Vec3(0f, 0f, 0f));
            ret = ret.ExpandTo(XformInv(new Vec3(p.x + s.x, p.y + s.y, p.z)));
            ret = ret.ExpandTo(XformInv(new Vec3(p.x + s.x, p.y, p.z + s.z)));
            ret = ret.ExpandTo(XformInv(new Vec3(p.x + s.x, p.y, p.z)));
            ret = ret.ExpandTo(XformInv(new Vec3(p.x, p.y + s.y, p.z + s.z)));
            ret = ret.ExpandTo(XformInv(new Vec3(p.x, p.y + s.y, p.z)));
            ret = ret.ExpandTo(XformInv(new Vec3(p.x, p.y, p.z + s.z)));
            ret = ret.ExpandTo(XformInv(new Vec3(p.x, p.y, p.z)));
            return ret;
        }

        public Plane Xform(Plane plane)
        {
            Basis b = basis.Inverse().Transposed();
            return XformFast(plane, b);
        }

        public Plane XformInv(Plane plane)
        {
            Xform3 inv = AffineInverse();
            Basis basisTranspose = basis.Transposed();
            return XformInvFast(plane, inv, basisTranspose);
        }

        public Plane XformFast(Plane plane, Basis basisInverseTranspose)
        {
            Vec3 point = new Vec3(plane.normal.x * plane.d, plane.normal.y * plane.d, plane.normal.z * plane.d);
            point = Xform(point);
            Vec3 normal = basisInverseTranspose.Xform(plane.normal).NormalizedChecked();
            float d = normal.Dot(point);
            return new Plane(normal, d);
        }

        public static Plane XformInvFast(Plane plane, Xform3 inverse, Basis basisTranspose)
        {
            Vec3 point = new Vec3(plane.normal.x * plane.d, plane.normal.y * plane.d, plane.normal.z * plane.d);
            point = inverse.Xform(point);
            Vec3 normal = basisTranspose.Xform(plane.normal).NormalizedChecked();
            float d = normal.Dot(point);
            return new Plane(normal, d);
        }

        /// <summary>inverse(): assumes an orthonormal basis (transposes it).</summary>
        public Xform3 Inverse()
        {
            Basis b = basis.Transposed();
            return new Xform3(b, b.Xform(-origin));
        }

        /// <summary>affine_inverse(): any invertible basis.</summary>
        public Xform3 AffineInverse()
        {
            Basis b = basis.Inverse();
            return new Xform3(b, b.Xform(-origin));
        }

        public Xform3 Rotated(Vec3 axis, double angle)
        {
            Basis b = new Basis(axis, angle);
            return new Xform3(b * basis, b.Xform(origin));
        }

        public Xform3 RotatedLocal(Vec3 axis, double angle) => new Xform3(basis * new Basis(axis, angle), origin);
        public Xform3 Scaled(Vec3 s) => new Xform3(basis.Scaled(s), origin * s);
        public Xform3 ScaledLocal(Vec3 s) => new Xform3(basis.ScaledLocal(s), origin);
        public Xform3 Translated(Vec3 offset) => new Xform3(basis, origin + offset);
        public Xform3 TranslatedLocal(Vec3 offset) => new Xform3(basis, origin + basis.Xform(offset));
        public Xform3 Orthonormalized() => new Xform3(basis.Orthonormalized(), origin);
        public Xform3 Orthogonalized() => new Xform3(basis.Orthogonalized(), origin);

        public Xform3 LookingAt(Vec3 target) => LookingAt(target, Vec3.UP, false);

        /// <summary>looking_at(target, up = Vector3.UP, use_model_front = false).</summary>
        public Xform3 LookingAt(Vec3 target, Vec3 up, bool useModelFront = false)
        {
            if (GD.MathChecks && origin.IsEqualApprox(target))
            {
                GD.MathError("The transform's origin and target can't be equal.");
                return IDENTITY;
            }
            Xform3 t = this;
            t.basis = Basis.LookingAt(target - origin, up, useModelFront);
            return t;
        }

        public Xform3 InterpolateWith(Xform3 xform, double weight)
        {
            float c = (float)weight;
            Vec3 srcScale = basis.GetScale();
            Quat srcRot = basis.GetRotationQuaternion();
            Vec3 srcLoc = origin;
            Vec3 dstScale = xform.basis.GetScale();
            Quat dstRot = xform.basis.GetRotationQuaternion();
            Vec3 dstLoc = xform.origin;
            Xform3 interp;
            interp.basis = new Basis(srcRot.Slerp(dstRot, c).Normalized(), srcScale.Lerp(dstScale, c));
            interp.origin = srcLoc.Lerp(dstLoc, c);
            return interp;
        }

        public bool IsEqualApprox(Xform3 t) => basis.IsEqualApprox(t.basis) && origin.IsEqualApprox(t.origin);
        public bool IsSame(Xform3 t) => basis.IsSame(t.basis) && origin.IsSame(t.origin);
        public bool IsFinite() => basis.IsFinite() && origin.IsFinite();

        public static Xform3 operator *(Xform3 a, Xform3 b) => new Xform3(a.basis * b.basis, a.Xform(b.origin));
        public static Vec3 operator *(Xform3 t, Vec3 v) => t.Xform(v);
        public static Vec3 operator *(Vec3 v, Xform3 t) => t.XformInv(v);
        public static Aabb operator *(Xform3 t, Aabb a) => t.Xform(a);
        public static Aabb operator *(Aabb a, Xform3 t) => t.XformInv(a);
        public static Plane operator *(Xform3 t, Plane p) => t.Xform(p);
        public static Plane operator *(Plane p, Xform3 t) => t.XformInv(p);
        public static Xform3 operator *(Xform3 t, double s) { float f = (float)s; return new Xform3(t.basis * f, new Vec3(t.origin.x * f, t.origin.y * f, t.origin.z * f)); }
        public static Xform3 operator /(Xform3 t, double s) { float f = (float)s; return new Xform3(t.basis / f, new Vec3(t.origin.x / f, t.origin.y / f, t.origin.z / f)); }
        public static bool operator ==(Xform3 a, Xform3 b) => a.basis == b.basis && a.origin == b.origin;
        public static bool operator !=(Xform3 a, Xform3 b) => !(a == b);
        public bool Equals(Xform3 o) => this == o;
        public override bool Equals(object o) => o is Xform3 t && this == t;
        public override int GetHashCode() => unchecked((int)GodotHash());
        public override string ToString() => "[X: " + basis.GetColumn(0) + ", Y: " + basis.GetColumn(1) + ", Z: " + basis.GetColumn(2) + ", O: " + origin + "]";

        // ------------------------------------------------------------------ Variant
        public static implicit operator Var(Xform3 t) => Var.Of(t);
        public static explicit operator Xform3(Var v)
        {
            object o = v.Obj;
            if (o is Xform3 t) return t;
            if (o is Basis b) return new Xform3(b, new Vec3(0f, 0f, 0f));
            if (o is Quat q) return new Xform3(new Basis(q), new Vec3(0f, 0f, 0f));
            if (o is Projection p) return new Xform3(p);
            return IDENTITY;
        }
        public int GodotType => GD.TYPE_TRANSFORM3D;
        public string GodotStr() => ToString();
        public bool GodotIsZero => this == IDENTITY;
        public uint GodotHash()
        {
            uint h = GHashing.MURMUR3_SEED;
            h = GHashing.Murmur3OneFloat(basis.row0.x, h);
            h = GHashing.Murmur3OneFloat(basis.row0.y, h);
            h = GHashing.Murmur3OneFloat(basis.row0.z, h);
            h = GHashing.Murmur3OneFloat(basis.row1.x, h);
            h = GHashing.Murmur3OneFloat(basis.row1.y, h);
            h = GHashing.Murmur3OneFloat(basis.row1.z, h);
            h = GHashing.Murmur3OneFloat(basis.row2.x, h);
            h = GHashing.Murmur3OneFloat(basis.row2.y, h);
            h = GHashing.Murmur3OneFloat(basis.row2.z, h);
            h = GHashing.Murmur3OneFloat(origin.x, h);
            h = GHashing.Murmur3OneFloat(origin.y, h);
            h = GHashing.Murmur3OneFloat(origin.z, h);
            return GHashing.Fmix32(h);
        }

        public bool GodotOp(char op, Var other, bool selfLeft, out Var result)
        {
            result = Var.Nil;
            object o = other.Obj;
            if (op == '*')
            {
                if (o is Xform3 t) { result = selfLeft ? this * t : t * this; return true; }
                if (other.IsVec3) { result = selfLeft ? Xform(other.AsVec3()) : XformInv(other.AsVec3()); return true; }
                if (o is Aabb a) { result = selfLeft ? Xform(a) : XformInv(a); return true; }
                if (o is Plane p) { result = selfLeft ? Xform(p) : XformInv(p); return true; }
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

    /// <summary>Godot's AABB.</summary>
    public struct Aabb : IEquatable<Aabb>, IGodotValue
    {
        public Vec3 position, size;

        public Aabb(Vec3 position, Vec3 size) { this.position = position; this.size = size; }

        public Vec3 End { get => position + size; set => size = value - position; }
        public Vec3 GetEnd() => position + size;
        public Vec3 GetCenter() => position + new Vec3(size.x * 0.5f, size.y * 0.5f, size.z * 0.5f);
        public float GetVolume() => size.x * size.y * size.z;
        public bool HasVolume() => size.x > 0.0f && size.y > 0.0f && size.z > 0.0f;
        public bool HasSurface() => size.x > 0.0f || size.y > 0.0f || size.z > 0.0f;
        public Aabb Abs() => new Aabb(position + size.Minf(0), size.Abs());
        public bool IsEqualApprox(Aabb a) => position.IsEqualApprox(a.position) && size.IsEqualApprox(a.size);
        public bool IsSame(Aabb a) => position.IsSame(a.position) && size.IsSame(a.size);
        public bool IsFinite() => position.IsFinite() && size.IsFinite();

        bool Negative => size.x < 0 || size.y < 0 || size.z < 0;

        void CheckSize(Aabb other, bool both)
        {
            if (GD.MathChecks && (Negative || (both && other.Negative)))
                GD.MathError("AABB size is negative, this is not supported. Use AABB.abs() to get an AABB with a positive size.");
        }

        public bool HasPoint(Vec3 p)
        {
            CheckSize(this, false);
            if (p.x < position.x) return false;
            if (p.y < position.y) return false;
            if (p.z < position.z) return false;
            if (p.x > position.x + size.x) return false;
            if (p.y > position.y + size.y) return false;
            if (p.z > position.z + size.z) return false;
            return true;
        }

        public bool Intersects(Aabb a)
        {
            CheckSize(a, true);
            if (position.x >= (a.position.x + a.size.x)) return false;
            if ((position.x + size.x) <= a.position.x) return false;
            if (position.y >= (a.position.y + a.size.y)) return false;
            if ((position.y + size.y) <= a.position.y) return false;
            if (position.z >= (a.position.z + a.size.z)) return false;
            if ((position.z + size.z) <= a.position.z) return false;
            return true;
        }

        /// <summary>C++ intersects_inclusive (faces touching count).</summary>
        public bool IntersectsInclusive(Aabb a)
        {
            CheckSize(a, true);
            if (position.x > (a.position.x + a.size.x)) return false;
            if ((position.x + size.x) < a.position.x) return false;
            if (position.y > (a.position.y + a.size.y)) return false;
            if ((position.y + size.y) < a.position.y) return false;
            if (position.z > (a.position.z + a.size.z)) return false;
            if ((position.z + size.z) < a.position.z) return false;
            return true;
        }

        public bool Encloses(Aabb a)
        {
            CheckSize(a, true);
            Vec3 srcMin = position, srcMax = position + size, dstMin = a.position, dstMax = a.position + a.size;
            return srcMin.x <= dstMin.x && srcMax.x >= dstMax.x && srcMin.y <= dstMin.y && srcMax.y >= dstMax.y
                && srcMin.z <= dstMin.z && srcMax.z >= dstMax.z;
        }

        public Aabb Merge(Aabb a)
        {
            CheckSize(a, true);
            Vec3 beg1 = position, beg2 = a.position;
            Vec3 end1 = size + beg1, end2 = a.size + beg2;
            Vec3 min = new Vec3(beg1.x < beg2.x ? beg1.x : beg2.x, beg1.y < beg2.y ? beg1.y : beg2.y, beg1.z < beg2.z ? beg1.z : beg2.z);
            Vec3 max = new Vec3(end1.x > end2.x ? end1.x : end2.x, end1.y > end2.y ? end1.y : end2.y, end1.z > end2.z ? end1.z : end2.z);
            return new Aabb(min, max - min);
        }

        public Aabb Intersection(Aabb a)
        {
            CheckSize(a, true);
            Vec3 srcMin = position, srcMax = position + size, dstMin = a.position, dstMax = a.position + a.size;
            Vec3 min, max;
            if (srcMin.x > dstMax.x || srcMax.x < dstMin.x) return default;
            min.x = srcMin.x > dstMin.x ? srcMin.x : dstMin.x;
            max.x = srcMax.x < dstMax.x ? srcMax.x : dstMax.x;
            if (srcMin.y > dstMax.y || srcMax.y < dstMin.y) return default;
            min.y = srcMin.y > dstMin.y ? srcMin.y : dstMin.y;
            max.y = srcMax.y < dstMax.y ? srcMax.y : dstMax.y;
            if (srcMin.z > dstMax.z || srcMax.z < dstMin.z) return default;
            min.z = srcMin.z > dstMin.z ? srcMin.z : dstMin.z;
            max.z = srcMax.z < dstMax.z ? srcMax.z : dstMax.z;
            return new Aabb(min, max - min);
        }

        /// <summary>C++ expand_to (in place in Godot; returns the expanded box here).</summary>
        public Aabb ExpandTo(Vec3 v)
        {
            CheckSize(this, false);
            Vec3 begin = position, end = position + size;
            if (v.x < begin.x) begin.x = v.x;
            if (v.y < begin.y) begin.y = v.y;
            if (v.z < begin.z) begin.z = v.z;
            if (v.x > end.x) end.x = v.x;
            if (v.y > end.y) end.y = v.y;
            if (v.z > end.z) end.z = v.z;
            return new Aabb(begin, end - begin);
        }

        public Aabb Expand(Vec3 toPoint) => ExpandTo(toPoint);

        public Aabb Grow(double by)
        {
            float b = (float)by;
            Aabb a = this;
            a.position.x -= b;
            a.position.y -= b;
            a.position.z -= b;
            a.size.x += 2.0f * b;
            a.size.y += 2.0f * b;
            a.size.z += 2.0f * b;
            return a;
        }

        public Vec3 GetSupport(Vec3 dir)
        {
            Vec3 support = position;
            if (dir.x > 0.0f) support.x += size.x;
            if (dir.y > 0.0f) support.y += size.y;
            if (dir.z > 0.0f) support.z += size.z;
            return support;
        }

        public Vec3 GetEndpoint(int point)
        {
            switch (point)
            {
                case 0: return new Vec3(position.x, position.y, position.z);
                case 1: return new Vec3(position.x, position.y, position.z + size.z);
                case 2: return new Vec3(position.x, position.y + size.y, position.z);
                case 3: return new Vec3(position.x, position.y + size.y, position.z + size.z);
                case 4: return new Vec3(position.x + size.x, position.y, position.z);
                case 5: return new Vec3(position.x + size.x, position.y, position.z + size.z);
                case 6: return new Vec3(position.x + size.x, position.y + size.y, position.z);
                case 7: return new Vec3(position.x + size.x, position.y + size.y, position.z + size.z);
            }
            GD.MathError("Method/function failed. Returning: Vector3()");
            return default;
        }

        public Vec3 GetLongestAxis()
        {
            Vec3 axis = new Vec3(1f, 0f, 0f);
            float maxSize = size.x;
            if (size.y > maxSize) { axis = new Vec3(0f, 1f, 0f); maxSize = size.y; }
            if (size.z > maxSize) axis = new Vec3(0f, 0f, 1f);
            return axis;
        }

        public int GetLongestAxisIndex()
        {
            int axis = 0;
            float maxSize = size.x;
            if (size.y > maxSize) { axis = 1; maxSize = size.y; }
            if (size.z > maxSize) axis = 2;
            return axis;
        }

        public float GetLongestAxisSize()
        {
            float maxSize = size.x;
            if (size.y > maxSize) maxSize = size.y;
            if (size.z > maxSize) maxSize = size.z;
            return maxSize;
        }

        public Vec3 GetShortestAxis()
        {
            Vec3 axis = new Vec3(1f, 0f, 0f);
            float minSize = size.x;
            if (size.y < minSize) { axis = new Vec3(0f, 1f, 0f); minSize = size.y; }
            if (size.z < minSize) axis = new Vec3(0f, 0f, 1f);
            return axis;
        }

        public int GetShortestAxisIndex()
        {
            int axis = 0;
            float minSize = size.x;
            if (size.y < minSize) { axis = 1; minSize = size.y; }
            if (size.z < minSize) axis = 2;
            return axis;
        }

        public float GetShortestAxisSize()
        {
            float minSize = size.x;
            if (size.y < minSize) minSize = size.y;
            if (size.z < minSize) minSize = size.z;
            return minSize;
        }

        public bool IntersectsPlane(Plane plane)
        {
            bool over = false, under = false;
            for (int i = 0; i < 8; i++)
            {
                Vec3 p = GetEndpoint(i);
                if (plane.DistanceTo(p) > 0) over = true;
                else under = true;
            }
            return under && over;
        }

        /// <summary>C++ find_intersects_ray.</summary>
        public bool FindIntersectsRay(Vec3 from, Vec3 dir, out bool inside, out Vec3 point, out Vec3 normal)
        {
            CheckSize(this, false);
            inside = false;
            point = default;
            normal = default;
            Vec3 end = position + size;
            float tmin = (float)-1e20;
            float tmax = (float)1e20;
            int axis = 0;
            for (int i = 0; i < 3; i++)
            {
                if (dir[i] == 0)
                {
                    if ((from[i] < position[i]) || (from[i] > end[i])) return false;
                }
                else
                {
                    float t1 = (position[i] - from[i]) / dir[i];
                    float t2 = (end[i] - from[i]) / dir[i];
                    if (t1 > t2) { float tt = t1; t1 = t2; t2 = tt; }
                    if (t1 >= tmin) { tmin = t1; axis = i; }
                    if (t2 < tmax)
                    {
                        if (t2 < 0) return false;
                        tmax = t2;
                    }
                    if (tmin > tmax) return false;
                }
            }
            inside = tmin < 0;
            point = from + dir * tmin;
            point[axis] = (dir[axis] >= 0) ? position[axis] : end[axis];
            normal[axis] = (dir[axis] >= 0) ? -1 : 1;
            return true;
        }

        /// <summary>intersects_ray(from, dir): the entry point (the ray's origin when it starts inside), or null.</summary>
        public Var IntersectsRay(Vec3 from, Vec3 dir)
        {
            if (FindIntersectsRay(from, dir, out bool inside, out Vec3 p, out _)) return inside ? from : p;
            return Var.Nil;
        }

        /// <summary>C++ intersects_segment.</summary>
        public bool IntersectsSegment(Vec3 from, Vec3 to, out Vec3 point, out Vec3 normal)
        {
            CheckSize(this, false);
            point = default;
            normal = default;
            float min = 0, max = 1;
            int axis = 0;
            float sign = 0;
            for (int i = 0; i < 3; i++)
            {
                float segFrom = from[i];
                float segTo = to[i];
                float boxBegin = position[i];
                float boxEnd = boxBegin + size[i];
                float cmin, cmax, csign;
                if (segFrom < segTo)
                {
                    if (segFrom > boxEnd || segTo < boxBegin) return false;
                    float length = segTo - segFrom;
                    cmin = (segFrom < boxBegin) ? ((boxBegin - segFrom) / length) : 0;
                    cmax = (segTo > boxEnd) ? ((boxEnd - segFrom) / length) : 1;
                    csign = -1.0f;
                }
                else
                {
                    if (segTo > boxEnd || segFrom < boxBegin) return false;
                    float length = segTo - segFrom;
                    cmin = (segFrom > boxEnd) ? (boxEnd - segFrom) / length : 0;
                    cmax = (segTo < boxBegin) ? (boxBegin - segFrom) / length : 1;
                    csign = 1.0f;
                }
                if (cmin > min) { min = cmin; axis = i; sign = csign; }
                if (cmax < max) max = cmax;
                if (max < min) return false;
            }
            Vec3 rel = to - from;
            normal[axis] = sign;
            point = from + rel * min;
            return true;
        }

        /// <summary>intersects_segment(from, to): the entry point, or null.</summary>
        public Var IntersectsSegment(Vec3 from, Vec3 to)
        {
            if (IntersectsSegment(from, to, out Vec3 p, out _)) return p;
            return Var.Nil;
        }

        public static bool operator ==(Aabb a, Aabb b) => a.position == b.position && a.size == b.size;
        public static bool operator !=(Aabb a, Aabb b) => !(a == b);
        public bool Equals(Aabb o) => this == o;
        public override bool Equals(object o) => o is Aabb a && this == a;
        public override int GetHashCode() => unchecked((int)GodotHash());
        public override string ToString() => "[P: " + position + ", S: " + size + "]";

        // ------------------------------------------------------------------ Variant
        public static implicit operator Var(Aabb a) => Var.Of(a);
        public static explicit operator Aabb(Var v) => v.Obj is Aabb a ? a : default;
        public int GodotType => GD.TYPE_AABB;
        public string GodotStr() => ToString();
        public bool GodotIsZero => this == default(Aabb);
        public uint GodotHash()
        {
            uint h = GHashing.Murmur3OneFloat(position.x);
            h = GHashing.Murmur3OneFloat(position.y, h);
            h = GHashing.Murmur3OneFloat(position.z, h);
            h = GHashing.Murmur3OneFloat(size.x, h);
            h = GHashing.Murmur3OneFloat(size.y, h);
            h = GHashing.Murmur3OneFloat(size.z, h);
            return GHashing.Fmix32(h);
        }
        public bool GodotOp(char op, Var other, bool selfLeft, out Var result)
        {
            result = Var.Nil;
            if (op == '*' && selfLeft && other.Obj is Xform3 t) { result = t.XformInv(this); return true; }
            return false;
        }
    }

    /// <summary>Godot's Plane: normal and distance d (the plane is normal.dot(p) == d).</summary>
    public struct Plane : IEquatable<Plane>, IGodotValue
    {
        public Vec3 normal;
        public float d;

        public static readonly Plane PLANE_YZ = new Plane(1f, 0f, 0f, 0f);
        public static readonly Plane PLANE_XZ = new Plane(0f, 1f, 0f, 0f);
        public static readonly Plane PLANE_XY = new Plane(0f, 0f, 1f, 0f);

        public Plane(float a, float b, float c, float d) { normal = new Vec3(a, b, c); this.d = d; }
        public Plane(double a, double b, double c, double d) { normal = new Vec3(a, b, c); this.d = (float)d; }
        /// <summary>Plane(normal, d = 0).</summary>
        public Plane(Vec3 normal, double d = 0.0) { this.normal = normal; this.d = (float)d; }
        /// <summary>Plane(normal, point).</summary>
        public Plane(Vec3 normal, Vec3 point) { this.normal = normal; d = normal.Dot(point); }
        /// <summary>Plane(point1, point2, point3): clockwise winding.</summary>
        public Plane(Vec3 p1, Vec3 p2, Vec3 p3, bool clockwise = true)
        {
            if (clockwise) normal = (p1 - p3).Cross(p1 - p2);
            else normal = (p1 - p2).Cross(p1 - p3);
            normal = normal.NormalizedChecked();
            d = normal.Dot(p1);
        }

        public float x { get => normal.x; set => normal.x = value; }
        public float y { get => normal.y; set => normal.y = value; }
        public float z { get => normal.z; set => normal.z = value; }

        public Plane Normalized()
        {
            if (GD.MathChecks && !IsFinite()) GD.PushWarning("Plane cannot be normalized, the distance and the normal should be finite.");
            float l = normal.Length();
            if (l == 0) return default;
            return new Plane(new Vec3(normal.x / l, normal.y / l, normal.z / l), (double)(d / l));
        }

        public Vec3 GetCenter() => new Vec3(normal.x * d, normal.y * d, normal.z * d);
        public bool IsPointOver(Vec3 p) => normal.Dot(p) > d;
        public float DistanceTo(Vec3 p) => normal.Dot(p) - d;

        public bool HasPoint(Vec3 p, double tolerance = GD.CMP_EPSILON)
        {
            float dist = normal.Dot(p) - d;
            dist = MathF.Abs(dist);
            return dist <= (float)tolerance;
        }

        public Vec3 Project(Vec3 p)
        {
            float k = DistanceTo(p);
            return p - new Vec3(normal.x * k, normal.y * k, normal.z * k);
        }

        public bool IsEqualApprox(Plane p) => normal.IsEqualApprox(p.normal) && GD.IsEqualApproxF(d, p.d);
        public bool IsEqualApproxAnySide(Plane p) =>
            (normal.IsEqualApprox(p.normal) && GD.IsEqualApproxF(d, p.d)) || (normal.IsEqualApprox(-p.normal) && GD.IsEqualApproxF(d, -p.d));
        public bool IsSame(Plane p) => normal.IsSame(p.normal) && GD.IsSameF(d, p.d);
        public bool IsFinite() => normal.IsFinite() && GD.IsFiniteF(d);

        public Vec3 GetAnyPerpendicularNormal()
        {
            Vec3 p1 = new Vec3(1f, 0f, 0f), p2 = new Vec3(0f, 1f, 0f);
            Vec3 p = MathF.Abs(normal.Dot(p1)) > 0.99f ? p2 : p1;
            float k = normal.Dot(p);
            p -= new Vec3(normal.x * k, normal.y * k, normal.z * k);
            return p.NormalizedChecked();
        }

        /// <summary>C++ intersect_3.</summary>
        public bool Intersect3(Plane b, Plane c, out Vec3 result)
        {
            Vec3 n0 = normal, n1 = b.normal, n2 = c.normal;
            float denom = n0.Cross(n1).Dot(n2);
            result = default;
            if (GD.IsZeroApproxF(denom)) return false;
            Vec3 a1 = n1.Cross(n2), a2 = n2.Cross(n0), a3 = n0.Cross(n1);
            Vec3 sum = new Vec3(a1.x * d, a1.y * d, a1.z * d) + new Vec3(a2.x * b.d, a2.y * b.d, a2.z * b.d) + new Vec3(a3.x * c.d, a3.y * c.d, a3.z * c.d);
            result = new Vec3(sum.x / denom, sum.y / denom, sum.z / denom);
            return true;
        }

        /// <summary>intersect_3(b, c): the common point, or null.</summary>
        public Var Intersect3(Plane b, Plane c) => Intersect3(b, c, out Vec3 r) ? (Var)r : Var.Nil;

        /// <summary>C++ intersects_ray.</summary>
        public bool IntersectsRay(Vec3 from, Vec3 dir, out Vec3 intersection)
        {
            intersection = default;
            Vec3 segment = dir;
            float den = normal.Dot(segment);
            if (GD.IsZeroApproxF(den)) return false;
            float dist = (normal.Dot(from) - d) / den;
            if (dist > GD.EPS_F) return false;
            dist = -dist;
            intersection = from + new Vec3(segment.x * dist, segment.y * dist, segment.z * dist);
            return true;
        }

        public Var IntersectsRay(Vec3 from, Vec3 dir) => IntersectsRay(from, dir, out Vec3 r) ? (Var)r : Var.Nil;

        /// <summary>C++ intersects_segment.</summary>
        public bool IntersectsSegment(Vec3 begin, Vec3 end, out Vec3 intersection)
        {
            intersection = default;
            Vec3 segment = begin - end;
            float den = normal.Dot(segment);
            if (GD.IsZeroApproxF(den)) return false;
            float dist = (normal.Dot(begin) - d) / den;
            if (dist < -GD.EPS_F || dist > (1.0f + GD.EPS_F)) return false;
            dist = -dist;
            intersection = begin + new Vec3(segment.x * dist, segment.y * dist, segment.z * dist);
            return true;
        }

        public Var IntersectsSegment(Vec3 begin, Vec3 end) => IntersectsSegment(begin, end, out Vec3 r) ? (Var)r : Var.Nil;

        public static Plane operator -(Plane p) => new Plane(-p.normal, (double)-p.d);
        public static Plane operator +(Plane p) => p;
        public static bool operator ==(Plane a, Plane b) => a.normal == b.normal && a.d == b.d;
        public static bool operator !=(Plane a, Plane b) => a.normal != b.normal || a.d != b.d;
        public bool Equals(Plane o) => this == o;
        public override bool Equals(object o) => o is Plane p && this == p;
        public override int GetHashCode() => unchecked((int)GodotHash());
        public override string ToString() => "[N: " + normal + ", D: " + GFormat.NumRealF(d, false) + "]";

        // ------------------------------------------------------------------ Variant
        public static implicit operator Var(Plane p) => Var.Of(p);
        public static explicit operator Plane(Var v) => v.Obj is Plane p ? p : default;
        public int GodotType => GD.TYPE_PLANE;
        public string GodotStr() => ToString();
        public bool GodotIsZero => this == default(Plane);
        public uint GodotHash()
        {
            uint h = GHashing.MURMUR3_SEED;
            h = GHashing.Murmur3OneFloat(normal.x, h);
            h = GHashing.Murmur3OneFloat(normal.y, h);
            h = GHashing.Murmur3OneFloat(normal.z, h);
            h = GHashing.Murmur3OneFloat(d, h);
            return GHashing.Fmix32(h);
        }
        public bool GodotOp(char op, Var other, bool selfLeft, out Var result)
        {
            result = Var.Nil;
            if (op == 'n') { result = -this; return true; }
            if (op == '*' && selfLeft && other.Obj is Xform3 t) { result = t.XformInv(this); return true; }
            return false;
        }
    }
}
