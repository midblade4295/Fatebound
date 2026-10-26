#if FB3D
// Godot's Mesh: a list of surfaces, each a primitive type, vertex arrays (Godot's ARRAY_* layout) and a material.
// The renderer builds its own mesh from MeshSurface's arrays (in Godot's coordinates and winding: clockwise front
// faces; the Unity renderer converts). Mesh.Changed fires when surfaces change; MeshSurface.Version too.
using System;
using System.Collections;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public enum PrimitiveType { Points = 0, Lines = 1, LineStrip = 2, Triangles = 3, TriangleStrip = 4 }

    /// <summary>One surface's data. Arrays are null when absent. Godot's layout: tangents 4 floats per vertex
    /// (xyz + binormal sign), bones/weights 4 per vertex (8 with ARRAY_FLAG_USE_8_BONE_WEIGHTS).</summary>
    public sealed class MeshSurface
    {
        public PrimitiveType Primitive = PrimitiveType.Triangles;
        public Vec3[] Vertices;
        public Vec3[] Normals;
        public float[] Tangents;
        public Col[] Colors;
        public Vec2[] Uv, Uv2;
        public float[][] Custom = new float[4][];
        public int[] CustomFormat = new int[4];
        public int[] Bones;
        public float[] Weights;
        public int BonesPerVertex = 4;
        public int[] Indices;
        public GMaterial Material;
        public string Name = "";
        public Aabb Aabb;
        public uint Format;
        /// <summary>Blend shapes (rare): each a full vertex array set.</summary>
        public List<MeshSurface> BlendShapes;
        public int Version;
        static int _versions;

        public void Touch() => Version = ++_versions;

        public int VertexCount => Vertices?.Length ?? 0;
        public int IndexCount => Indices?.Length ?? 0;

        public void ComputeAabb()
        {
            if (Vertices == null || Vertices.Length == 0) { Aabb = new Aabb(); return; }
            Vec3 mn = Vertices[0], mx = Vertices[0];
            for (int i = 1; i < Vertices.Length; i++)
            {
                var v = Vertices[i];
                if (v.x < mn.x) mn.x = v.x; if (v.y < mn.y) mn.y = v.y; if (v.z < mn.z) mn.z = v.z;
                if (v.x > mx.x) mx.x = v.x; if (v.y > mx.y) mx.y = v.y; if (v.z > mx.z) mx.z = v.z;
            }
            Aabb = new Aabb(mn, mx - mn);
        }

        public MeshSurface Clone()
        {
            var s = (MeshSurface)MemberwiseClone();
            s.Custom = (float[][])Custom.Clone();
            s.CustomFormat = (int[])CustomFormat.Clone();
            return s;
        }
    }

    public abstract partial class Mesh : Resource
    {
        public const int ARRAY_VERTEX = 0, ARRAY_NORMAL = 1, ARRAY_TANGENT = 2, ARRAY_COLOR = 3, ARRAY_TEX_UV = 4,
            ARRAY_TEX_UV2 = 5, ARRAY_CUSTOM0 = 6, ARRAY_CUSTOM1 = 7, ARRAY_CUSTOM2 = 8, ARRAY_CUSTOM3 = 9, ARRAY_BONES = 10,
            ARRAY_WEIGHTS = 11, ARRAY_INDEX = 12, ARRAY_MAX = 13;
        public const PrimitiveType PRIMITIVE_POINTS = PrimitiveType.Points, PRIMITIVE_LINES = PrimitiveType.Lines,
            PRIMITIVE_LINE_STRIP = PrimitiveType.LineStrip, PRIMITIVE_TRIANGLES = PrimitiveType.Triangles,
            PRIMITIVE_TRIANGLE_STRIP = PrimitiveType.TriangleStrip;
        public const int ARRAY_FORMAT_VERTEX = 1, ARRAY_FORMAT_NORMAL = 2, ARRAY_FORMAT_TANGENT = 4, ARRAY_FORMAT_COLOR = 8,
            ARRAY_FORMAT_TEX_UV = 16, ARRAY_FORMAT_TEX_UV2 = 32, ARRAY_FORMAT_BONES = 1 << 10, ARRAY_FORMAT_WEIGHTS = 1 << 11,
            ARRAY_FORMAT_INDEX = 1 << 12, ARRAY_FLAG_USE_8_BONE_WEIGHTS = 1 << 27;
        public const int ARRAY_CUSTOM_RGBA8_UNORM = 0, ARRAY_CUSTOM_RGBA8_SNORM = 1, ARRAY_CUSTOM_RG_HALF = 2,
            ARRAY_CUSTOM_RGBA_HALF = 3, ARRAY_CUSTOM_R_FLOAT = 4, ARRAY_CUSTOM_RG_FLOAT = 5, ARRAY_CUSTOM_RGB_FLOAT = 6,
            ARRAY_CUSTOM_RGBA_FLOAT = 7;

        /// <summary>The surfaces as they are now (a PrimitiveMesh regenerates them first when its settings changed).</summary>
        public abstract IReadOnlyList<MeshSurface> GetSurfaces();

        public int GetSurfaceCount() => GetSurfaces().Count;
        public virtual GMaterial SurfaceGetMaterial(int i) { var s = GetSurfaces(); return i >= 0 && i < s.Count ? s[i].Material : null; }
        public virtual void SurfaceSetMaterial(int i, GMaterial m)
        {
            var s = GetSurfaces();
            if (i < 0 || i >= s.Count) return;
            s[i].Material = m;
            s[i].Touch();
            EmitChanged();
        }

        public PrimitiveType SurfaceGetPrimitiveType(int i) => GetSurfaces()[i].Primitive;

        public bool HasBones()
        {
            foreach (var s in GetSurfaces()) if (s.Bones != null) return true;
            return false;
        }

        public virtual Aabb GetAabb()
        {
            var ss = GetSurfaces();
            if (ss.Count == 0) return new Aabb();
            Aabb a = ss[0].Aabb;
            for (int i = 1; i < ss.Count; i++) a = a.Merge(ss[i].Aabb);
            return a;
        }

        /// <summary>surface_get_arrays(i): Godot's ARRAY_MAX-long array (packed arrays as C# arrays inside Vars).</summary>
        public GArray SurfaceGetArrays(int i)
        {
            var s = GetSurfaces()[i];
            var a = new GArray();
            a.Resize(ARRAY_MAX);
            if (s.Vertices != null) a[ARRAY_VERTEX] = Var.Of((Vec3[])s.Vertices.Clone());
            if (s.Normals != null) a[ARRAY_NORMAL] = Var.Of((Vec3[])s.Normals.Clone());
            if (s.Tangents != null) a[ARRAY_TANGENT] = Var.Of((float[])s.Tangents.Clone());
            if (s.Colors != null) a[ARRAY_COLOR] = Var.Of((Col[])s.Colors.Clone());
            if (s.Uv != null) a[ARRAY_TEX_UV] = Var.Of((Vec2[])s.Uv.Clone());
            if (s.Uv2 != null) a[ARRAY_TEX_UV2] = Var.Of((Vec2[])s.Uv2.Clone());
            for (int c = 0; c < 4; c++) if (s.Custom[c] != null) a[ARRAY_CUSTOM0 + c] = Var.Of((float[])s.Custom[c].Clone());
            if (s.Bones != null) a[ARRAY_BONES] = Var.Of((int[])s.Bones.Clone());
            if (s.Weights != null) a[ARRAY_WEIGHTS] = Var.Of((float[])s.Weights.Clone());
            if (s.Indices != null) a[ARRAY_INDEX] = Var.Of((int[])s.Indices.Clone());
            return a;
        }

        // ---------- reading GDScript-built arrays (packed arrays arrive as C# arrays or lists inside Vars) ----------
        public static Vec3[] ToVec3Array(Var v)
        {
            switch (v.Obj)
            {
                case Vec3[] a: return (Vec3[])a.Clone();
                case List<Vec3> l: return l.ToArray();
                case GArray g: { var r = new Vec3[g.Size()]; for (int i = 0; i < r.Length; i++) r[i] = g[i].AsVec3(); return r; }
                case IEnumerable<Vec3> e: return new List<Vec3>(e).ToArray();
            }
            return null;
        }

        public static Vec2[] ToVec2Array(Var v)
        {
            switch (v.Obj)
            {
                case Vec2[] a: return (Vec2[])a.Clone();
                case List<Vec2> l: return l.ToArray();
                case GArray g: { var r = new Vec2[g.Size()]; for (int i = 0; i < r.Length; i++) r[i] = g[i].AsVec2(); return r; }
                case IEnumerable<Vec2> e: return new List<Vec2>(e).ToArray();
            }
            return null;
        }

        public static Col[] ToColArray(Var v)
        {
            switch (v.Obj)
            {
                case Col[] a: return (Col[])a.Clone();
                case List<Col> l: return l.ToArray();
                case GArray g: { var r = new Col[g.Size()]; for (int i = 0; i < r.Length; i++) r[i] = g[i].As<Col>(); return r; }
                case IEnumerable<Col> e: return new List<Col>(e).ToArray();
            }
            return null;
        }

        public static float[] ToFloatArray(Var v)
        {
            switch (v.Obj)
            {
                case float[] a: return (float[])a.Clone();
                case List<float> l: return l.ToArray();
                case double[] d: { var r = new float[d.Length]; for (int i = 0; i < r.Length; i++) r[i] = (float)d[i]; return r; }
                case List<double> ld: { var r = new float[ld.Count]; for (int i = 0; i < r.Length; i++) r[i] = (float)ld[i]; return r; }
                case GArray g: { var r = new float[g.Size()]; for (int i = 0; i < r.Length; i++) r[i] = (float)g[i].AsFloat(); return r; }
            }
            return null;
        }

        public static int[] ToIntArray(Var v)
        {
            switch (v.Obj)
            {
                case int[] a: return (int[])a.Clone();
                case List<int> l: return l.ToArray();
                case long[] la: { var r = new int[la.Length]; for (int i = 0; i < r.Length; i++) r[i] = (int)la[i]; return r; }
                case List<long> ll: { var r = new int[ll.Count]; for (int i = 0; i < r.Length; i++) r[i] = (int)ll[i]; return r; }
                case GArray g: { var r = new int[g.Size()]; for (int i = 0; i < r.Length; i++) r[i] = g[i].AsInt(); return r; }
            }
            return null;
        }

        /// <summary>A surface from Godot's arrays (add_surface_from_arrays' reading).</summary>
        public static MeshSurface SurfaceFromArrays(PrimitiveType prim, GArray arrays, uint flags = 0)
        {
            var s = new MeshSurface { Primitive = prim, Format = flags };
            Var At(int i) => i < arrays.Size() ? arrays[i] : Var.Nil;
            s.Vertices = ToVec3Array(At(ARRAY_VERTEX));
            s.Normals = ToVec3Array(At(ARRAY_NORMAL));
            s.Tangents = ToFloatArray(At(ARRAY_TANGENT));
            s.Colors = ToColArray(At(ARRAY_COLOR));
            s.Uv = ToVec2Array(At(ARRAY_TEX_UV));
            s.Uv2 = ToVec2Array(At(ARRAY_TEX_UV2));
            for (int c = 0; c < 4; c++)
            {
                var cv = At(ARRAY_CUSTOM0 + c);
                if (!cv.IsNil) s.Custom[c] = cv.Obj is byte[] b ? Array.ConvertAll(b, x => x / 255f) : ToFloatArray(cv);
                s.CustomFormat[c] = (int)((flags >> (13 + c * 3)) & 7);
            }
            s.Bones = ToIntArray(At(ARRAY_BONES));
            s.Weights = ToFloatArray(At(ARRAY_WEIGHTS));
            s.BonesPerVertex = (flags & ARRAY_FLAG_USE_8_BONE_WEIGHTS) != 0 ? 8 : 4;
            s.Indices = ToIntArray(At(ARRAY_INDEX));
            s.ComputeAabb();
            s.Touch();
            return s;
        }
    }

    /// <summary>A mesh built from arrays (ArrayMesh): add_surface_from_arrays, surface_* accessors, clear_surfaces.</summary>
    public partial class ArrayMesh : Mesh
    {
        protected readonly List<MeshSurface> surfaces = new List<MeshSurface>();
        public Aabb CustomAabb;
        public int BlendShapeMode;
        public override IReadOnlyList<MeshSurface> GetSurfaces() => surfaces;

        public void AddSurfaceFromArrays(PrimitiveType prim, GArray arrays, GArray blendShapes = null, GDict lods = null, uint flags = 0)
        {
            var s = SurfaceFromArrays(prim, arrays, flags);
            if (s.Vertices == null) { GD.PushError("add_surface_from_arrays: no vertex array."); return; }
            surfaces.Add(s);
            EmitChanged();
        }

        /// <summary>Adds an already made surface (SurfaceTool.commit, the baked-asset loader).</summary>
        public void AddSurface(MeshSurface s)
        {
            if (s.Aabb.size == Vec3.Zero) s.ComputeAabb();
            s.Touch();
            surfaces.Add(s);
            EmitChanged();
        }

        public void ClearSurfaces()
        {
            surfaces.Clear();
            EmitChanged();
        }

        public void SurfaceRemove(int i)
        {
            if (i < 0 || i >= surfaces.Count) return;
            surfaces.RemoveAt(i);
            EmitChanged();
        }

        public int SurfaceGetArrayLen(int i) => surfaces[i].VertexCount;
        public int SurfaceGetArrayIndexLen(int i) => surfaces[i].IndexCount;
        public string SurfaceGetName(int i) => surfaces[i].Name;
        public void SurfaceSetName(int i, string n) => surfaces[i].Name = n;
        public uint SurfaceGetFormat(int i) => surfaces[i].Format;

        public int SurfaceFindByName(string name)
        {
            for (int i = 0; i < surfaces.Count; i++) if (surfaces[i].Name == name) return i;
            return -1;
        }

        public override Aabb GetAabb() => CustomAabb.size != Vec3.Zero ? CustomAabb : base.GetAabb();
    }
}

#endif
