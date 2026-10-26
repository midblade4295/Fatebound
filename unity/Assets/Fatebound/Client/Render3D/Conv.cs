// Godot's 3D space -> Unity's. Godot is right-handed (-Z forward), Unity left-handed (+Z forward). The port mirrors X
// (what glTFast does for glTF, Godot's own coordinate system): a point (x, y, z) is (-x, y, z); a rotation q is
// (q.x, -q.y, -q.z, q.w); scales are unchanged. Triangle winding stays as Godot's: the mirrored world seen by the
// mirrored camera is the same picture, clockwise front faces in both engines. Cameras and lights look down Godot's -Z,
// Unity's look down +Z: their components sit on a child turned 180 degrees about Y. Mesh UVs stay Godot's (v down);
// the 3D shaders flip v when they sample a texture (Unity textures are stored bottom-up).
using Fatebound.Sim;
using UnityEngine;
using Quaternion = UnityEngine.Quaternion;

namespace Fatebound.Client
{
    public static class Conv
    {
        public static Vector3 Pos(Vec3 v) => new Vector3(-v.x, v.y, v.z);
        public static Vector3 Dir(Vec3 v) => new Vector3(-v.x, v.y, v.z);
        public static Quaternion Rot(Quat q) => new Quaternion(q.x, -q.y, -q.z, q.w);
        public static readonly Quaternion Yaw180 = Quaternion.Euler(0f, 180f, 0f);

        /// <summary>A Godot transform on a Unity Transform (local values: the renderer keeps every object directly
        /// under its world's root, so local is global). Godot allows skew; Unity doesn't (rotation + scale kept).</summary>
        public static void Apply(Transform t, in Xform3 x)
        {
            Basis b = x.basis;
            Vec3 s = b.GetScale();
            if (s.x == 0f || s.y == 0f || s.z == 0f)
            {
                t.localPosition = Pos(x.origin);
                t.localScale = Vector3.zero;
                return;
            }
            Basis r = b * Basis.FromScale(new Vec3(1f / s.x, 1f / s.y, 1f / s.z));
            Quat q = r.Orthonormalized().GetQuaternion();
            t.localPosition = Pos(x.origin);
            t.localRotation = Rot(q);
            t.localScale = new Vector3(s.x, s.y, s.z);
        }

        /// <summary>The Unity matrix of a Godot transform (M * T * M, M = mirror X): for Graphics.Render* calls.</summary>
        public static Matrix4x4 Matrix(in Xform3 x)
        {
            Basis b = x.basis;
            var m = new Matrix4x4();
            // rows/cols of M B M: entries with exactly one x index flip sign
            m.m00 = b.row0.x;  m.m01 = -b.row0.y; m.m02 = -b.row0.z; m.m03 = -x.origin.x;
            m.m10 = -b.row1.x; m.m11 = b.row1.y;  m.m12 = b.row1.z;  m.m13 = x.origin.y;
            m.m20 = -b.row2.x; m.m21 = b.row2.y;  m.m22 = b.row2.z;  m.m23 = x.origin.z;
            m.m30 = 0f; m.m31 = 0f; m.m32 = 0f; m.m33 = 1f;
            return m;
        }

        /// <summary>Godot's projection matrix for Unity's Camera.projectionMatrix: both are OpenGL-style and, with the
        /// camera on its 180-degree child, Unity's view space (worldToCameraMatrix) is exactly Godot's.</summary>
        public static Matrix4x4 Projection(in Fatebound.Sim.Projection p)
        {
            var m = new Matrix4x4();
            m.SetColumn(0, new Vector4(p.x.x, p.x.y, p.x.z, p.x.w));
            m.SetColumn(1, new Vector4(p.y.x, p.y.y, p.y.z, p.y.w));
            m.SetColumn(2, new Vector4(p.z.x, p.z.y, p.z.z, p.z.w));
            m.SetColumn(3, new Vector4(p.w.x, p.w.y, p.w.z, p.w.w));
            return m;
        }

        public static Color Color(Fatebound.GUI.Col c) => new Color(c.r, c.g, c.b, c.a);

        /// <summary>A Godot (sRGB) colour as the linear value a shader wants in a linear-space project.</summary>
        public static Color Linear(Fatebound.GUI.Col c) => new Color(c.r, c.g, c.b, c.a).linear;
    }
}
