#if FB3D
// Godot's ImmediateMesh (scene/resources/immediate_mesh.cpp): surfaces built vertex by vertex at runtime
// (surface_begin .. surface_add_vertex .. surface_end), typically cleared and rebuilt every frame. Each finished surface
// is a new MeshSurface (new Version) and the mesh emits "changed", so the renderer re-uploads. Like Godot, a surface
// with normals but no tangents gets the server's made-up tangent (GpuPacking.ArbitraryTangent), and an attribute first
// set part-way through a surface back-fills the vertices before it with that first value.
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public class ImmediateMesh : Mesh
    {
        static readonly Vec3 SMALL_VEC3 = new Vec3((float)GD.CMP_EPSILON, (float)GD.CMP_EPSILON, (float)GD.CMP_EPSILON);

        readonly List<MeshSurface> _surfaces = new List<MeshSurface>();
        bool _active, _vertex2d;
        PrimitiveType _prim;
        GMaterial _mat;

        readonly List<Vec3> _vertices = new List<Vec3>();
        readonly List<Col> _colors = new List<Col>();
        readonly List<Vec3> _normals = new List<Vec3>();
        readonly List<Plane> _tangents = new List<Plane>();
        readonly List<Vec2> _uvs = new List<Vec2>();
        readonly List<Vec2> _uv2s = new List<Vec2>();
        bool _usesColors, _usesNormals, _usesTangents, _usesUvs, _usesUv2s;
        Col _curColor = new Col(0f, 0f, 0f, 1f);
        Vec3 _curNormal;
        Plane _curTangent;
        Vec2 _curUv, _curUv2;

        public override IReadOnlyList<MeshSurface> GetSurfaces() => _surfaces;

        static void Err(string m) => GD.PushError(m);

        public void SurfaceBegin(PrimitiveType primitive, GMaterial material = null)
        {
            if (_active) { Err("Already creating a new surface."); return; }
            _prim = primitive;
            _mat = material;
            _active = true;
        }

        public void SurfaceBegin(int primitive, GMaterial material = null) => SurfaceBegin((PrimitiveType)primitive, material);

        bool Active()
        {
            if (!_active) { Err("Not creating any surface. Use surface_begin() to do it."); return false; }
            return true;
        }

        static void Fill<T>(List<T> list, int n, T v) { list.Clear(); for (int i = 0; i < n; i++) list.Add(v); }

        public void SurfaceSetColor(Col c)
        {
            if (!Active()) return;
            if (!_usesColors) { Fill(_colors, _vertices.Count, c); _usesColors = true; }
            _curColor = c;
        }

        public void SurfaceSetNormal(Vec3 n)
        {
            if (!Active()) return;
            if (!_usesNormals) { Fill(_normals, _vertices.Count, n); _usesNormals = true; }
            _curNormal = n;
        }

        public void SurfaceSetTangent(Plane t)
        {
            if (!Active()) return;
            if (!_usesTangents) { Fill(_tangents, _vertices.Count, t); _usesTangents = true; }
            _curTangent = t;
        }

        public void SurfaceSetUv(Vec2 uv)
        {
            if (!Active()) return;
            if (!_usesUvs) { Fill(_uvs, _vertices.Count, uv); _usesUvs = true; }
            _curUv = uv;
        }

        public void SurfaceSetUv2(Vec2 uv)
        {
            if (!Active()) return;
            if (!_usesUv2s) { Fill(_uv2s, _vertices.Count, uv); _usesUv2s = true; }
            _curUv2 = uv;
        }

        void PushAttributes()
        {
            if (_usesColors) _colors.Add(_curColor);
            if (_usesNormals) _normals.Add(_curNormal);
            if (_usesTangents) _tangents.Add(_curTangent);
            if (_usesUvs) _uvs.Add(_curUv);
            if (_usesUv2s) _uv2s.Add(_curUv2);
        }

        public void SurfaceAddVertex(Vec3 v)
        {
            if (!Active()) return;
            if (_vertices.Count > 0 && _vertex2d) { Err("Can't mix 2D and 3D vertices in a surface."); return; }
            PushAttributes();
            _vertices.Add(v);
        }

        public void SurfaceAddVertex2D(Vec2 v)
        {
            if (!Active()) return;
            if (_vertices.Count > 0 && !_vertex2d) { Err("Can't mix 2D and 3D vertices in a surface."); return; }
            PushAttributes();
            _vertices.Add(new Vec3(v.x, v.y, 0f));
            _vertex2d = true;
        }

        public void SurfaceEnd()
        {
            if (!Active()) return;
            if (_vertices.Count == 0) { Err("No vertices were added, surface can't be created."); return; }

            uint format = ARRAY_FORMAT_VERTEX;
            if (_vertex2d) format |= 1u << 25; // ARRAY_FLAG_USE_2D_VERTICES
            var s = new MeshSurface { Primitive = _prim, Material = _mat, Vertices = _vertices.ToArray() };

            Aabb aabb = new Aabb();
            for (int i = 0; i < _vertices.Count; i++)
            {
                if (i == 0) aabb = new Aabb(_vertices[i], SMALL_VEC3);
                else aabb = aabb.ExpandTo(_vertices[i]);
            }
            s.Aabb = aabb;

            if (_usesNormals)
            {
                format |= ARRAY_FORMAT_NORMAL;
                s.Normals = _normals.ToArray();
            }
            if (_usesTangents || _usesNormals)
            {
                format |= ARRAY_FORMAT_TANGENT;
                var t = new float[_vertices.Count * 4];
                for (int i = 0; i < _vertices.Count; i++)
                {
                    Vec3 tv;
                    float d;
                    if (_usesTangents) { tv = _tangents[i].normal; d = _tangents[i].d; }
                    else { tv = GpuPacking.ArbitraryTangent(_normals[i]); d = 1.0f; }
                    t[i * 4] = tv.x; t[i * 4 + 1] = tv.y; t[i * 4 + 2] = tv.z; t[i * 4 + 3] = d;
                }
                s.Tangents = t;
            }
            if (_usesColors) { format |= ARRAY_FORMAT_COLOR; s.Colors = _colors.ToArray(); }
            if (_usesUvs) { format |= ARRAY_FORMAT_TEX_UV; s.Uv = _uvs.ToArray(); }
            if (_usesUv2s) { format |= ARRAY_FORMAT_TEX_UV2; s.Uv2 = _uv2s.ToArray(); }
            s.Format = format;
            s.Touch();
            _surfaces.Add(s);

            ResetBuilder();
            _vertex2d = false;
            _active = false;
            EmitChanged();
        }

        void ResetBuilder()
        {
            _colors.Clear(); _normals.Clear(); _tangents.Clear(); _uvs.Clear(); _uv2s.Clear(); _vertices.Clear();
            _usesColors = _usesNormals = _usesTangents = _usesUvs = _usesUv2s = false;
        }

        public void ClearSurfaces()
        {
            _surfaces.Clear();
            _active = false;
            ResetBuilder();
            EmitChanged();
        }

        public int SurfaceGetArrayLen(int i) => i >= 0 && i < _surfaces.Count ? _surfaces[i].VertexCount : -1;
        public int SurfaceGetArrayIndexLen(int i) => 0;
        public uint SurfaceGetFormat(int i) => i >= 0 && i < _surfaces.Count ? _surfaces[i].Format : 0;

        public override void SurfaceSetMaterial(int i, GMaterial m)
        {
            if (i < 0 || i >= _surfaces.Count) { Err("Index p_idx out of bounds."); return; }
            _surfaces[i].Material = m;
            _surfaces[i].Touch();
            EmitChanged();
        }

        public override Aabb GetAabb()
        {
            Aabb aabb = new Aabb();
            for (int i = 0; i < _surfaces.Count; i++)
                aabb = i == 0 ? _surfaces[i].Aabb : aabb.Merge(_surfaces[i].Aabb);
            return aabb;
        }
    }
}

#endif
