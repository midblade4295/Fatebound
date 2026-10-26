#if FB3D
// Godot's primitive meshes (scene/resources/3d/primitive_meshes.cpp): PrimitiveMesh and Box/Sphere/Cylinder/Capsule/
// Plane/Quad/Prism/Torus/Point meshes. Each _create_mesh_array is transcribed expression by expression (float vs
// double steps included), so the arrays are Godot's to the bit: same vertex order, normals, tangents (4 floats per
// vertex), UVs/UV2s and indices. The surface is regenerated lazily (on GetSurfaces/GetAabb) after a property change.
// The arrays are what _create_mesh_array produces; Godot's get_mesh_arrays() returns them after the RenderingServer's
// GPU packing (normals/tangents octahedral-encoded to 16 bits) -- the renderer does that packing itself.
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    /// <summary>What a _create_mesh_array fills (Godot's ARRAY_* slots a primitive uses).</summary>
    public sealed class PrimitiveArrays
    {
        public readonly List<Vec3> Vertex = new List<Vec3>();
        public readonly List<Vec3> Normal = new List<Vec3>();
        public readonly List<float> Tangent = new List<float>();
        public readonly List<Vec2> Uv = new List<Vec2>();
        public List<Vec2> Uv2;
        public readonly List<int> Index = new List<int>();

        public void AddTangent(float x, float y, float z, float d) { Tangent.Add(x); Tangent.Add(y); Tangent.Add(z); Tangent.Add(d); }
    }

    public abstract class PrimitiveMesh : Mesh
    {
        const double PADDING_REF_SIZE = 1024.0;
        /// <summary>Project setting rendering/lightmapping/primitive_meshes/texel_size (Godot's default 0.2).</summary>
        public static float TexelSizeSetting = 0.2f;

        GMaterial _material;
        Aabb _customAabb;
        bool _flipFaces, _addUv2;
        float _uv2Padding = 2.0f;
        protected PrimitiveType primitiveType = PrimitiveType.Triangles;
        protected float texelSize;
        Vec2i _lightmapSizeHint;

        bool _pending = true;
        MeshSurface _surface;
        MeshSurface[] _list = Array.Empty<MeshSurface>();
        Aabb _aabb;

        protected PrimitiveMesh()
        {
            texelSize = TexelSizeSetting <= 0f ? 0.2f : TexelSizeSetting;
        }

        /// <summary>_create_mesh_array: fills the arrays from the current settings.</summary>
        protected abstract void CreateMeshArray(PrimitiveArrays a);
        /// <summary>_update_lightmap_size (only meaningful with add_uv2).</summary>
        protected virtual void UpdateLightmapSize() { }

        /// <summary>request_update: the surface is rebuilt on the next read; listeners hear "changed" now.</summary>
        public void RequestUpdate()
        {
            _pending = true;
            EmitChanged();
        }

        void Update()
        {
            var arr = new PrimitiveArrays();
            CreateMeshArray(arr);
            _pending = false;
            if (arr.Vertex.Count == 0) { GD.PushError("_create_mesh_array must return at least a vertex array."); _list = Array.Empty<MeshSurface>(); _surface = null; return; }

            Aabb aabb = new Aabb();
            for (int i = 0; i < arr.Vertex.Count; i++)
            {
                if (i == 0) aabb.position = arr.Vertex[i];
                else aabb = aabb.ExpandTo(arr.Vertex[i]);
            }
            _aabb = aabb;

            Vec3[] normals = arr.Normal.Count > 0 ? arr.Normal.ToArray() : null;
            int[] indices = arr.Index.Count > 0 ? arr.Index.ToArray() : null;
            if (_flipFaces && normals != null && indices != null)
            {
                for (int i = 0; i < normals.Length; i++) normals[i] = -normals[i];
                for (int i = 0; i < indices.Length; i += 3) { int t = indices[i]; indices[i] = indices[i + 1]; indices[i + 1] = t; }
            }

            Vec2[] uv = arr.Uv.Count > 0 ? arr.Uv.ToArray() : null;
            Vec2[] uv2 = arr.Uv2 != null && arr.Uv2.Count > 0 ? arr.Uv2.ToArray() : null;
            if (_addUv2 && uv != null && uv2 == null)
            {
                // The fallback when _create_mesh_array gives no UV2: UV scaled to leave the right/bottom padding.
                Vec2 s = GetUv2Scale(new Vec2(1f, 1f));
                uv2 = new Vec2[uv.Length];
                for (int i = 0; i < uv.Length; i++) uv2[i] = new Vec2(uv[i].x * s.x, uv[i].y * s.y);
            }

            var surf = new MeshSurface
            {
                Primitive = primitiveType,
                Vertices = arr.Vertex.ToArray(),
                Normals = normals,
                Tangents = arr.Tangent.Count > 0 ? arr.Tangent.ToArray() : null,
                Uv = uv,
                Uv2 = uv2,
                Indices = indices,
                Material = _material,
                Aabb = aabb,
            };
            uint fmt = ARRAY_FORMAT_VERTEX;
            if (surf.Normals != null) fmt |= ARRAY_FORMAT_NORMAL;
            if (surf.Tangents != null) fmt |= ARRAY_FORMAT_TANGENT;
            if (surf.Uv != null) fmt |= ARRAY_FORMAT_TEX_UV;
            if (surf.Uv2 != null) fmt |= ARRAY_FORMAT_TEX_UV2;
            if (surf.Indices != null) fmt |= ARRAY_FORMAT_INDEX;
            surf.Format = fmt;
            surf.Touch();
            _surface = surf;
            _list = new[] { surf };
        }

        public override IReadOnlyList<MeshSurface> GetSurfaces()
        {
            if (_pending) Update();
            return _list;
        }

        public override Aabb GetAabb()
        {
            if (_pending) Update();
            return _aabb;
        }

        public override GMaterial SurfaceGetMaterial(int i) => i == 0 ? _material : null;
        public override void SurfaceSetMaterial(int i, GMaterial m) { if (i == 0) Material = m; }

        /// <summary>get_mesh_arrays(): the surface's ARRAY_MAX arrays.</summary>
        public GArray GetMeshArrays() => SurfaceGetArrays(0);

        public GMaterial Material
        {
            get => _material;
            set
            {
                if (ReferenceEquals(value, _material)) return;
                _material = value;
                if (!_pending && _surface != null) { _surface.Material = value; _surface.Touch(); }
                EmitChanged();
            }
        }

        public Aabb CustomAabb
        {
            get => _customAabb;
            set { if (value.IsEqualApprox(_customAabb)) return; _customAabb = value; EmitChanged(); }
        }

        public bool FlipFaces { get => _flipFaces; set { if (value == _flipFaces) return; _flipFaces = value; RequestUpdate(); } }

        public bool AddUv2
        {
            get => _addUv2;
            set { if (value == _addUv2) return; _addUv2 = value; UpdateLightmapSize(); RequestUpdate(); }
        }

        public double Uv2Padding
        {
            get => _uv2Padding;
            set { float p = (float)value; if (GD.IsEqualApproxF(p, _uv2Padding)) return; _uv2Padding = p; UpdateLightmapSize(); RequestUpdate(); }
        }

        /// <summary>Mesh.lightmap_size_hint.</summary>
        public Vec2i LightmapSizeHint { get => _lightmapSizeHint; set => _lightmapSizeHint = value; }

        public int GetSurfaceCountPrimitive() => 1;
        public PrimitiveType PrimitiveKind => primitiveType;

        /// <summary>The lightmap texel size this mesh uses (the project setting when it was made).</summary>
        public float GetLightmapTexelSize() => texelSize;

        protected Vec2 GetUv2Scale(Vec2 marginScale)
        {
            Vec2 ls = new Vec2(_lightmapSizeHint.x, _lightmapSizeHint.y);
            float sx = (float)(marginScale.x * _uv2Padding / (ls.x == 0.0 ? PADDING_REF_SIZE : (double)_lightmapSizeHint.x));
            float sy = (float)(marginScale.y * _uv2Padding / (ls.y == 0.0 ? PADDING_REF_SIZE : (double)_lightmapSizeHint.y));
            return new Vec2(1f - sx, 1f - sy);
        }

        // (C++'s implicit double -> int truncation of a Size2i assignment)
        protected static int ToInt(double v) => (int)v;
        protected static double Max(double a, double b) => a > b ? a : b;
        protected static float MaxF(float a, float b) => a > b ? a : b;

        public override Resource Duplicate(bool deep = false)
        {
            var m = (PrimitiveMesh)base.Duplicate(deep);
            m._pending = true;
            m._surface = null;
            m._list = Array.Empty<MeshSurface>();
            return m;
        }
    }

    // ------------------------------------------------------------------ CapsuleMesh
    public class CapsuleMesh : PrimitiveMesh
    {
        float _radius = 0.5f, _height = 2.0f;
        int _radialSegments = 64, _rings = 8;

        public double Radius
        {
            get => _radius;
            set
            {
                float r = (float)value;
                if (GD.IsEqualApproxF(_radius, r)) return;
                _radius = r;
                if (_radius > _height * 0.5) _height = (float)(_radius * 2.0);
                UpdateLightmapSize();
                RequestUpdate();
            }
        }

        public double Height
        {
            get => _height;
            set
            {
                float h = (float)value;
                if (GD.IsEqualApproxF(_height, h)) return;
                _height = h;
                if (_radius > _height * 0.5) _radius = (float)(_height * 0.5);
                UpdateLightmapSize();
                RequestUpdate();
            }
        }

        public int RadialSegments { get => _radialSegments; set { if (_radialSegments == value) return; _radialSegments = value > 4 ? value : 4; RequestUpdate(); } }
        public int Rings { get => _rings; set { if (_rings == value) return; if (value < 0) { GD.PushError("Condition \"p_rings < 0\" is true."); return; } _rings = value; RequestUpdate(); } }

        protected override void UpdateLightmapSize()
        {
            if (!AddUv2) return;
            float padding = (float)Uv2Padding;
            float radialLength = (float)(_radius * Math.PI * 0.5);
            float verticalLength = (float)(radialLength * 2 + (_height - 2.0 * _radius));
            LightmapSizeHint = new Vec2i(ToInt(Max(1.0, 4.0 * radialLength / texelSize) + padding), ToInt(Max(1.0, verticalLength / texelSize) + padding));
        }

        protected override void CreateMeshArray(PrimitiveArrays a)
        {
            CreateMeshArray(a, _radius, _height, _radialSegments, _rings, AddUv2, (float)Uv2Padding * texelSize);
        }

        public static void CreateMeshArray(PrimitiveArrays arr, float radius, float height, int radialSegments, int rings, bool addUv2, float uv2Padding)
        {
            int i, j, prevrow, thisrow, point;
            float x, y, z, u, v, w;
            float onethird = (float)(1.0 / 3.0);
            float twothirds = (float)(2.0 / 3.0);

            float radialWidth = (float)(2.0 * radius * Math.PI);
            float radialH = radialWidth / (radialWidth + uv2Padding);
            float radialLength = (float)(radius * Math.PI * 0.5);
            float verticalLength = (float)(radialLength * 2 + (height - 2.0 * radius) + uv2Padding);
            float radialV = radialLength / verticalLength;
            float heightV = (float)((height - 2.0 * radius) / verticalLength);
            if (addUv2) arr.Uv2 = new List<Vec2>();
            point = 0;

            // top hemisphere
            thisrow = 0;
            prevrow = 0;
            for (j = 0; j <= (rings + 1); j++)
            {
                v = j;
                v /= (rings + 1);
                if (j == (rings + 1)) { w = 1.0f; y = 0.0f; }
                else { w = (float)Math.Sin(0.5 * Math.PI * v); y = (float)Math.Cos(0.5 * Math.PI * v); }

                for (i = 0; i <= radialSegments; i++)
                {
                    u = i;
                    u /= radialSegments;
                    if (i == radialSegments) { x = 0.0f; z = 1.0f; }
                    else { x = (float)-Math.Sin(u * GD.TAU); z = (float)Math.Cos(u * GD.TAU); }

                    Vec3 p = new Vec3(x * w, y, -z * w);
                    arr.Vertex.Add(p * radius + new Vec3(0.0f, (float)(0.5 * height - radius), 0.0f));
                    arr.Normal.Add(p);
                    arr.AddTangent(-z, 0.0f, -x, 1.0f);
                    arr.Uv.Add(new Vec2(u, v * onethird));
                    if (addUv2) arr.Uv2.Add(new Vec2(u * radialH, v * radialV));
                    point++;

                    if (i > 0 && j > 0)
                    {
                        arr.Index.Add(prevrow + i - 1); arr.Index.Add(prevrow + i); arr.Index.Add(thisrow + i - 1);
                        arr.Index.Add(prevrow + i); arr.Index.Add(thisrow + i); arr.Index.Add(thisrow + i - 1);
                    }
                }
                prevrow = thisrow;
                thisrow = point;
            }

            // cylinder
            thisrow = point;
            prevrow = 0;
            for (j = 0; j <= (rings + 1); j++)
            {
                v = j;
                v /= (rings + 1);
                y = (float)((height - 2.0 * radius) * v);
                y = (float)((0.5 * height - radius) - y);

                for (i = 0; i <= radialSegments; i++)
                {
                    u = i;
                    u /= radialSegments;
                    if (i == radialSegments) { x = 0.0f; z = 1.0f; }
                    else { x = (float)-Math.Sin(u * GD.TAU); z = (float)Math.Cos(u * GD.TAU); }

                    Vec3 p = new Vec3(x * radius, y, -z * radius);
                    arr.Vertex.Add(p);
                    arr.Normal.Add(new Vec3(x, 0.0f, -z));
                    arr.AddTangent(-z, 0.0f, -x, 1.0f);
                    arr.Uv.Add(new Vec2(u, onethird + (v * onethird)));
                    if (addUv2) arr.Uv2.Add(new Vec2(u * radialH, radialV + (v * heightV)));
                    point++;

                    if (i > 0 && j > 0)
                    {
                        arr.Index.Add(prevrow + i - 1); arr.Index.Add(prevrow + i); arr.Index.Add(thisrow + i - 1);
                        arr.Index.Add(prevrow + i); arr.Index.Add(thisrow + i); arr.Index.Add(thisrow + i - 1);
                    }
                }
                prevrow = thisrow;
                thisrow = point;
            }

            // bottom hemisphere
            thisrow = point;
            prevrow = 0;
            for (j = 0; j <= (rings + 1); j++)
            {
                v = j;
                v /= (rings + 1);
                if (j == (rings + 1)) { w = 0.0f; y = -1.0f; }
                else { w = (float)Math.Cos(0.5 * Math.PI * v); y = (float)-Math.Sin(0.5 * Math.PI * v); }

                for (i = 0; i <= radialSegments; i++)
                {
                    u = i;
                    u /= radialSegments;
                    if (i == radialSegments) { x = 0.0f; z = 1.0f; }
                    else { x = (float)-Math.Sin(u * GD.TAU); z = (float)Math.Cos(u * GD.TAU); }

                    Vec3 p = new Vec3(x * w, y, -z * w);
                    arr.Vertex.Add(p * radius + new Vec3(0.0f, (float)(-0.5 * height + radius), 0.0f));
                    arr.Normal.Add(p);
                    arr.AddTangent(-z, 0.0f, -x, 1.0f);
                    arr.Uv.Add(new Vec2(u, twothirds + v * onethird));
                    if (addUv2) arr.Uv2.Add(new Vec2(u * radialH, radialV + heightV + v * radialV));
                    point++;

                    if (i > 0 && j > 0)
                    {
                        arr.Index.Add(prevrow + i - 1); arr.Index.Add(prevrow + i); arr.Index.Add(thisrow + i - 1);
                        arr.Index.Add(prevrow + i); arr.Index.Add(thisrow + i); arr.Index.Add(thisrow + i - 1);
                    }
                }
                prevrow = thisrow;
                thisrow = point;
            }
        }
    }

    // ------------------------------------------------------------------ BoxMesh
    public class BoxMesh : PrimitiveMesh
    {
        Vec3 _size = new Vec3(1f, 1f, 1f);
        int _subW, _subH, _subD;

        public Vec3 Size { get => _size; set { if (value.IsEqualApprox(_size)) return; _size = value; UpdateLightmapSize(); RequestUpdate(); } }
        public int SubdivideWidth { get => _subW; set { if (value == _subW) return; _subW = value > 0 ? value : 0; RequestUpdate(); } }
        public int SubdivideHeight { get => _subH; set { if (value == _subH) return; _subH = value > 0 ? value : 0; RequestUpdate(); } }
        public int SubdivideDepth { get => _subD; set { if (value == _subD) return; _subD = value > 0 ? value : 0; RequestUpdate(); } }

        protected override void UpdateLightmapSize()
        {
            if (!AddUv2) return;
            float padding = (float)Uv2Padding;
            float width = (_size.x + _size.z) / texelSize;
            float length = (_size.y + _size.y + MaxF(_size.x, _size.z)) / texelSize;
            LightmapSizeHint = new Vec2i(ToInt(Max(1.0, width) + 2.0 * padding), ToInt(Max(1.0, length) + 3.0 * padding));
        }

        protected override void CreateMeshArray(PrimitiveArrays a) => CreateMeshArray(a, _size, _subW, _subH, _subD, AddUv2, (float)Uv2Padding * texelSize);

        public static void CreateMeshArray(PrimitiveArrays arr, Vec3 size, int subdivideW, int subdivideH, int subdivideD, bool addUv2, float uv2Padding)
        {
            int i, j, prevrow, thisrow, point;
            float x, y, z;
            float onethird = (float)(1.0 / 3.0);
            float twothirds = (float)(2.0 / 3.0);

            float totalH = (float)(size.x + size.z + (2.0 * uv2Padding));
            float paddingH = uv2Padding / totalH;
            float widthH = size.x / totalH;
            float depthH = size.z / totalH;
            float totalV = (float)(size.y + size.y + MaxF(size.x, size.z) + (3.0 * uv2Padding));
            float paddingV = uv2Padding / totalV;
            float widthV = size.x / totalV;
            float heightV = size.y / totalV;
            float depthV = size.z / totalV;

            Vec3 startPos = new Vec3(size.x * -0.5f, size.y * -0.5f, size.z * -0.5f);
            if (addUv2) arr.Uv2 = new List<Vec2>();
            point = 0;

            // front + back
            y = startPos.y;
            thisrow = point;
            prevrow = 0;
            for (j = 0; j <= subdivideH + 1; j++)
            {
                float v = j;
                float v2 = (float)(v / (subdivideW + 1.0));
                v = (float)(v / (2.0 * (subdivideH + 1.0)));

                x = startPos.x;
                for (i = 0; i <= subdivideW + 1; i++)
                {
                    float u = i;
                    float u2 = (float)(u / (subdivideW + 1.0));
                    u = (float)(u / (3.0 * (subdivideW + 1.0)));

                    // front
                    arr.Vertex.Add(new Vec3(x, -y, -startPos.z));
                    arr.Normal.Add(new Vec3(0f, 0f, 1f));
                    arr.AddTangent(1f, 0f, 0f, 1f);
                    arr.Uv.Add(new Vec2(u, v));
                    if (addUv2) arr.Uv2.Add(new Vec2(u2 * widthH, v2 * heightV));
                    point++;

                    // back
                    arr.Vertex.Add(new Vec3(-x, -y, startPos.z));
                    arr.Normal.Add(new Vec3(0f, 0f, -1f));
                    arr.AddTangent(-1f, 0f, 0f, 1f);
                    arr.Uv.Add(new Vec2(twothirds + u, v));
                    if (addUv2) arr.Uv2.Add(new Vec2(u2 * widthH, heightV + paddingV + (v2 * heightV)));
                    point++;

                    if (i > 0 && j > 0)
                    {
                        int i2 = i * 2;
                        arr.Index.Add(prevrow + i2 - 2); arr.Index.Add(prevrow + i2); arr.Index.Add(thisrow + i2 - 2);
                        arr.Index.Add(prevrow + i2); arr.Index.Add(thisrow + i2); arr.Index.Add(thisrow + i2 - 2);
                        arr.Index.Add(prevrow + i2 - 1); arr.Index.Add(prevrow + i2 + 1); arr.Index.Add(thisrow + i2 - 1);
                        arr.Index.Add(prevrow + i2 + 1); arr.Index.Add(thisrow + i2 + 1); arr.Index.Add(thisrow + i2 - 1);
                    }
                    x = (float)(x + size.x / (subdivideW + 1.0));
                }
                y = (float)(y + size.y / (subdivideH + 1.0));
                prevrow = thisrow;
                thisrow = point;
            }

            // left + right
            y = startPos.y;
            thisrow = point;
            prevrow = 0;
            for (j = 0; j <= (subdivideH + 1); j++)
            {
                float v = j;
                float v2 = (float)(v / (subdivideH + 1.0));
                v = (float)(v / (2.0 * (subdivideH + 1.0)));

                z = startPos.z;
                for (i = 0; i <= (subdivideD + 1); i++)
                {
                    float u = i;
                    float u2 = (float)(u / (subdivideD + 1.0));
                    u = (float)(u / (3.0 * (subdivideD + 1.0)));

                    // right
                    arr.Vertex.Add(new Vec3(-startPos.x, -y, -z));
                    arr.Normal.Add(new Vec3(1f, 0f, 0f));
                    arr.AddTangent(0f, 0f, -1f, 1f);
                    arr.Uv.Add(new Vec2(onethird + u, v));
                    if (addUv2) arr.Uv2.Add(new Vec2(widthH + paddingH + (u2 * depthH), v2 * heightV));
                    point++;

                    // left
                    arr.Vertex.Add(new Vec3(startPos.x, -y, z));
                    arr.Normal.Add(new Vec3(-1f, 0f, 0f));
                    arr.AddTangent(0f, 0f, 1f, 1f);
                    arr.Uv.Add(new Vec2(u, (float)(0.5 + v)));
                    if (addUv2) arr.Uv2.Add(new Vec2(widthH + paddingH + (u2 * depthH), heightV + paddingV + (v2 * heightV)));
                    point++;

                    if (i > 0 && j > 0)
                    {
                        int i2 = i * 2;
                        arr.Index.Add(prevrow + i2 - 2); arr.Index.Add(prevrow + i2); arr.Index.Add(thisrow + i2 - 2);
                        arr.Index.Add(prevrow + i2); arr.Index.Add(thisrow + i2); arr.Index.Add(thisrow + i2 - 2);
                        arr.Index.Add(prevrow + i2 - 1); arr.Index.Add(prevrow + i2 + 1); arr.Index.Add(thisrow + i2 - 1);
                        arr.Index.Add(prevrow + i2 + 1); arr.Index.Add(thisrow + i2 + 1); arr.Index.Add(thisrow + i2 - 1);
                    }
                    z = (float)(z + size.z / (subdivideD + 1.0));
                }
                y = (float)(y + size.y / (subdivideH + 1.0));
                prevrow = thisrow;
                thisrow = point;
            }

            // top + bottom
            z = startPos.z;
            thisrow = point;
            prevrow = 0;
            for (j = 0; j <= (subdivideD + 1); j++)
            {
                float v = j;
                float v2 = (float)(v / (subdivideD + 1.0));
                v = (float)(v / (2.0 * (subdivideD + 1.0)));

                x = startPos.x;
                for (i = 0; i <= (subdivideW + 1); i++)
                {
                    float u = i;
                    float u2 = (float)(u / (subdivideW + 1.0));
                    u = (float)(u / (3.0 * (subdivideW + 1.0)));

                    // top
                    arr.Vertex.Add(new Vec3(-x, -startPos.y, -z));
                    arr.Normal.Add(new Vec3(0f, 1f, 0f));
                    arr.AddTangent(-1f, 0f, 0f, 1f);
                    arr.Uv.Add(new Vec2(onethird + u, (float)(0.5 + v)));
                    if (addUv2) arr.Uv2.Add(new Vec2(u2 * widthH, (float)(((heightV + paddingV) * 2.0) + (v2 * depthV))));
                    point++;

                    // bottom
                    arr.Vertex.Add(new Vec3(x, startPos.y, -z));
                    arr.Normal.Add(new Vec3(0f, -1f, 0f));
                    arr.AddTangent(1f, 0f, 0f, 1f);
                    arr.Uv.Add(new Vec2(twothirds + u, (float)(0.5 + v)));
                    if (addUv2) arr.Uv2.Add(new Vec2(widthH + paddingH + (u2 * depthH), (float)(((heightV + paddingV) * 2.0) + (v2 * widthV))));
                    point++;

                    if (i > 0 && j > 0)
                    {
                        int i2 = i * 2;
                        arr.Index.Add(prevrow + i2 - 2); arr.Index.Add(prevrow + i2); arr.Index.Add(thisrow + i2 - 2);
                        arr.Index.Add(prevrow + i2); arr.Index.Add(thisrow + i2); arr.Index.Add(thisrow + i2 - 2);
                        arr.Index.Add(prevrow + i2 - 1); arr.Index.Add(prevrow + i2 + 1); arr.Index.Add(thisrow + i2 - 1);
                        arr.Index.Add(prevrow + i2 + 1); arr.Index.Add(thisrow + i2 + 1); arr.Index.Add(thisrow + i2 - 1);
                    }
                    x = (float)(x + size.x / (subdivideW + 1.0));
                }
                z = (float)(z + size.z / (subdivideD + 1.0));
                prevrow = thisrow;
                thisrow = point;
            }
        }
    }

    // ------------------------------------------------------------------ CylinderMesh
    public class CylinderMesh : PrimitiveMesh
    {
        float _topRadius = 0.5f, _bottomRadius = 0.5f, _height = 2.0f;
        int _radialSegments = 64, _rings = 4;
        bool _capTop = true, _capBottom = true;

        public double TopRadius { get => _topRadius; set { float r = (float)value; if (GD.IsEqualApproxF(r, _topRadius)) return; _topRadius = r; UpdateLightmapSize(); RequestUpdate(); } }
        public double BottomRadius { get => _bottomRadius; set { float r = (float)value; if (GD.IsEqualApproxF(r, _bottomRadius)) return; _bottomRadius = r; UpdateLightmapSize(); RequestUpdate(); } }
        public double Height { get => _height; set { float h = (float)value; if (GD.IsEqualApproxF(h, _height)) return; _height = h; UpdateLightmapSize(); RequestUpdate(); } }
        public int RadialSegments { get => _radialSegments; set { if (value == _radialSegments) return; _radialSegments = value > 4 ? value : 4; RequestUpdate(); } }
        public int Rings { get => _rings; set { if (value == _rings) return; if (value < 0) { GD.PushError("Condition \"p_rings < 0\" is true."); return; } _rings = value; RequestUpdate(); } }
        public bool CapTop { get => _capTop; set { if (value == _capTop) return; _capTop = value; RequestUpdate(); } }
        public bool CapBottom { get => _capBottom; set { if (value == _capBottom) return; _capBottom = value; RequestUpdate(); } }

        protected override void UpdateLightmapSize()
        {
            if (!AddUv2) return;
            float padding = (float)Uv2Padding;
            float topCircumference = (float)(_topRadius * Math.PI * 2.0);
            float bottomCircumference = (float)(_bottomRadius * Math.PI * 2.0);
            float width = MaxF(topCircumference, bottomCircumference) / texelSize + padding;
            width = (float)Max(width, (((_topRadius + _bottomRadius) / texelSize) + padding) * 2.0);
            int lx = ToInt(Max(1.0, width));
            float height = (float)(((_height + (MaxF(_topRadius, _bottomRadius) * 2.0)) / texelSize) + (2.0 * padding));
            LightmapSizeHint = new Vec2i(lx, ToInt(Max(1.0, height)));
        }

        protected override void CreateMeshArray(PrimitiveArrays a) =>
            CreateMeshArray(a, _topRadius, _bottomRadius, _height, _radialSegments, _rings, _capTop, _capBottom, AddUv2, (float)Uv2Padding * texelSize);

        public static void CreateMeshArray(PrimitiveArrays arr, float topRadius, float bottomRadius, float height, int radialSegments, int rings,
            bool capTop, bool capBottom, bool addUv2, float uv2Padding)
        {
            int i, j, prevrow, thisrow, point;
            float x, y, z, u, v, radius, radiusH;

            float topCircumference = (float)(topRadius * Math.PI * 2.0);
            float bottomCircumference = (float)(bottomRadius * Math.PI * 2.0);
            float verticalLength = (float)(height + Max(2.0 * topRadius, 2.0 * bottomRadius) + (2.0 * uv2Padding));
            float heightV = height / verticalLength;
            float paddingV = uv2Padding / verticalLength;
            float horizontalLength = (float)Max(Max(2.0 * (topRadius + bottomRadius + uv2Padding), topCircumference + uv2Padding), bottomCircumference + uv2Padding);
            float centerH = (float)(0.5 * (horizontalLength - uv2Padding) / horizontalLength);
            float topH = topCircumference / horizontalLength;
            float bottomH = bottomCircumference / horizontalLength;
            float paddingH = uv2Padding / horizontalLength;
            if (addUv2) arr.Uv2 = new List<Vec2>();
            point = 0;

            thisrow = 0;
            prevrow = 0;
            float sideNormalY = (bottomRadius - topRadius) / height;
            for (j = 0; j <= (rings + 1); j++)
            {
                v = j;
                v /= (rings + 1);

                radius = topRadius + ((bottomRadius - topRadius) * v);
                radiusH = topH + ((bottomH - topH) * v);

                y = height * v;
                y = (float)((height * 0.5) - y);

                for (i = 0; i <= radialSegments; i++)
                {
                    u = i;
                    u /= radialSegments;
                    if (i == radialSegments) { x = 0.0f; z = 1.0f; }
                    else { x = (float)Math.Sin(u * GD.TAU); z = (float)Math.Cos(u * GD.TAU); }

                    arr.Vertex.Add(new Vec3(x * radius, y, z * radius));
                    arr.Normal.Add(new Vec3(x, sideNormalY, z).NormalizedChecked());
                    arr.AddTangent(z, 0.0f, -x, 1.0f);
                    arr.Uv.Add(new Vec2(u, (float)(v * 0.5)));
                    if (addUv2) arr.Uv2.Add(new Vec2((float)(centerH + (u - 0.5) * radiusH), v * heightV));
                    point++;

                    if (i > 0 && j > 0)
                    {
                        arr.Index.Add(prevrow + i - 1); arr.Index.Add(prevrow + i); arr.Index.Add(thisrow + i - 1);
                        arr.Index.Add(prevrow + i); arr.Index.Add(thisrow + i); arr.Index.Add(thisrow + i - 1);
                    }
                }
                prevrow = thisrow;
                thisrow = point;
            }

            topH = topRadius / horizontalLength;
            float topV = topRadius / verticalLength;
            bottomH = bottomRadius / horizontalLength;
            float bottomV = bottomRadius / verticalLength;

            if (capTop && topRadius > 0.0)
            {
                y = (float)(height * 0.5);
                thisrow = point;
                arr.Vertex.Add(new Vec3(0f, y, 0f));
                arr.Normal.Add(new Vec3(0f, 1f, 0f));
                arr.AddTangent(1f, 0f, 0f, 1f);
                arr.Uv.Add(new Vec2(0.25f, 0.75f));
                if (addUv2) arr.Uv2.Add(new Vec2(topH, heightV + paddingV + MaxF(topV, bottomV)));
                point++;

                for (i = 0; i <= radialSegments; i++)
                {
                    float r = i;
                    r /= radialSegments;
                    if (i == radialSegments) { x = 0.0f; z = 1.0f; }
                    else { x = (float)Math.Sin(r * GD.TAU); z = (float)Math.Cos(r * GD.TAU); }

                    u = (float)((x + 1.0) * 0.25);
                    v = (float)(0.5 + ((z + 1.0) * 0.25));

                    arr.Vertex.Add(new Vec3(x * topRadius, y, z * topRadius));
                    arr.Normal.Add(new Vec3(0f, 1f, 0f));
                    arr.AddTangent(1f, 0f, 0f, 1f);
                    arr.Uv.Add(new Vec2(u, v));
                    if (addUv2) arr.Uv2.Add(new Vec2(topH + (x * topH), heightV + paddingV + MaxF(topV, bottomV) + (z * topV)));
                    point++;

                    if (i > 0)
                    {
                        arr.Index.Add(thisrow); arr.Index.Add(point - 1); arr.Index.Add(point - 2);
                    }
                }
            }

            if (capBottom && bottomRadius > 0.0)
            {
                y = (float)(height * -0.5);
                thisrow = point;
                arr.Vertex.Add(new Vec3(0f, y, 0f));
                arr.Normal.Add(new Vec3(0f, -1f, 0f));
                arr.AddTangent(1f, 0f, 0f, 1f);
                arr.Uv.Add(new Vec2(0.75f, 0.75f));
                if (addUv2) arr.Uv2.Add(new Vec2(topH + topH + paddingH + bottomH, heightV + paddingV + MaxF(topV, bottomV)));
                point++;

                for (i = 0; i <= radialSegments; i++)
                {
                    float r = i;
                    r /= radialSegments;
                    if (i == radialSegments) { x = 0.0f; z = 1.0f; }
                    else { x = (float)Math.Sin(r * GD.TAU); z = (float)Math.Cos(r * GD.TAU); }

                    u = (float)(0.5 + ((x + 1.0) * 0.25));
                    v = (float)(1.0 - ((z + 1.0) * 0.25));

                    arr.Vertex.Add(new Vec3(x * bottomRadius, y, z * bottomRadius));
                    arr.Normal.Add(new Vec3(0f, -1f, 0f));
                    arr.AddTangent(1f, 0f, 0f, 1f);
                    arr.Uv.Add(new Vec2(u, v));
                    if (addUv2) arr.Uv2.Add(new Vec2(topH + topH + paddingH + bottomH + (x * bottomH), heightV + paddingV + MaxF(topV, bottomV) - (z * bottomV)));
                    point++;

                    if (i > 0)
                    {
                        arr.Index.Add(thisrow); arr.Index.Add(point - 2); arr.Index.Add(point - 1);
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ PlaneMesh / QuadMesh
    public class PlaneMesh : PrimitiveMesh
    {
        public const int FACE_X = 0, FACE_Y = 1, FACE_Z = 2;

        Vec2 _size = new Vec2(2f, 2f);
        int _subW, _subD;
        Vec3 _centerOffset;
        int _orientation = FACE_Y;

        public Vec2 Size { get => _size; set { if (value == _size) return; _size = value; UpdateLightmapSize(); RequestUpdate(); } }
        public int SubdivideWidth { get => _subW; set { if (value == _subW || (_subW == 0 && value < 0)) return; _subW = value > 0 ? value : 0; RequestUpdate(); } }
        public int SubdivideDepth { get => _subD; set { if (value == _subD || (_subD == 0 && value < 0)) return; _subD = value > 0 ? value : 0; RequestUpdate(); } }
        public Vec3 CenterOffset { get => _centerOffset; set { if (value.IsEqualApprox(_centerOffset)) return; _centerOffset = value; RequestUpdate(); } }
        public int Orientation { get => _orientation; set { if (value == _orientation) return; _orientation = value; RequestUpdate(); } }

        protected override void UpdateLightmapSize()
        {
            if (!AddUv2) return;
            float padding = (float)Uv2Padding;
            LightmapSizeHint = new Vec2i(ToInt(Max(1.0, (_size.x / texelSize) + padding)), ToInt(Max(1.0, (_size.y / texelSize) + padding)));
        }

        protected override void CreateMeshArray(PrimitiveArrays arr)
        {
            int i, j, prevrow, thisrow, point;
            float x, z;
            // (uses PrimitiveMesh's default UV2)
            Vec2 startPos = new Vec2(_size.x * -0.5f, _size.y * -0.5f);

            Vec3 normal = new Vec3(0f, 1f, 0f);
            if (_orientation == FACE_X) normal = new Vec3(1f, 0f, 0f);
            else if (_orientation == FACE_Z) normal = new Vec3(0f, 0f, 1f);
            point = 0;

            z = startPos.y;
            thisrow = point;
            prevrow = 0;
            for (j = 0; j <= (_subD + 1); j++)
            {
                x = startPos.x;
                for (i = 0; i <= (_subW + 1); i++)
                {
                    float u = i;
                    float v = j;
                    u = (float)(u / (_subW + 1.0));
                    v = (float)(v / (_subD + 1.0));

                    if (_orientation == FACE_X) arr.Vertex.Add(new Vec3(0f, z, x) + _centerOffset);
                    else if (_orientation == FACE_Y) arr.Vertex.Add(new Vec3(-x, 0f, -z) + _centerOffset);
                    else if (_orientation == FACE_Z) arr.Vertex.Add(new Vec3(-x, z, 0f) + _centerOffset);
                    arr.Normal.Add(normal);
                    if (_orientation == FACE_X) arr.AddTangent(0f, 0f, -1f, 1f);
                    else arr.AddTangent(1f, 0f, 0f, 1f);
                    arr.Uv.Add(new Vec2((float)(1.0 - u), (float)(1.0 - v)));
                    point++;

                    if (i > 0 && j > 0)
                    {
                        arr.Index.Add(prevrow + i - 1); arr.Index.Add(prevrow + i); arr.Index.Add(thisrow + i - 1);
                        arr.Index.Add(prevrow + i); arr.Index.Add(thisrow + i); arr.Index.Add(thisrow + i - 1);
                    }
                    x = (float)(x + _size.x / (_subW + 1.0));
                }
                z = (float)(z + _size.y / (_subD + 1.0));
                prevrow = thisrow;
                thisrow = point;
            }
        }
    }

    /// <summary>A PlaneMesh facing +Z, 1x1 (Godot's QuadMesh).</summary>
    public class QuadMesh : PlaneMesh
    {
        public QuadMesh()
        {
            Orientation = FACE_Z;
            Size = new Vec2(1f, 1f);
        }
    }

    // ------------------------------------------------------------------ PrismMesh
    public class PrismMesh : PrimitiveMesh
    {
        float _leftToRight = 0.5f;
        Vec3 _size = new Vec3(1f, 1f, 1f);
        int _subW, _subH, _subD;

        public double LeftToRight { get => _leftToRight; set { float l = (float)value; if (GD.IsEqualApproxF(l, _leftToRight)) return; _leftToRight = l; RequestUpdate(); } }
        public Vec3 Size { get => _size; set { if (value.IsEqualApprox(_size)) return; _size = value; UpdateLightmapSize(); RequestUpdate(); } }
        public int SubdivideWidth { get => _subW; set { if (value == _subW || (value < 0 && _subW == 0)) return; _subW = value > 0 ? value : 0; RequestUpdate(); } }
        public int SubdivideHeight { get => _subH; set { if (value == _subH || (value < 0 && _subH == 0)) return; _subH = value > 0 ? value : 0; RequestUpdate(); } }
        public int SubdivideDepth { get => _subD; set { if (value == _subD || (value < 0 && _subD == 0)) return; _subD = value > 0 ? value : 0; RequestUpdate(); } }

        protected override void UpdateLightmapSize()
        {
            if (!AddUv2) return;
            float padding = (float)Uv2Padding;
            float width = (_size.x + _size.z) / texelSize;
            float length = (_size.y + _size.y + _size.z) / texelSize;
            LightmapSizeHint = new Vec2i(ToInt(Max(1.0, width) + 2.0 * padding), ToInt(Max(1.0, length) + 3.0 * padding));
        }

        protected override void CreateMeshArray(PrimitiveArrays arr)
        {
            int i, j, prevrow, thisrow, point;
            float x, y, z;
            float onethird = (float)(1.0 / 3.0);
            float twothirds = (float)(2.0 / 3.0);
            Vec3 size = _size;
            float leftToRight = _leftToRight;

            bool addUv2 = AddUv2;
            float uv2Padding = (float)Uv2Padding * texelSize;

            float horizontalTotal = (float)(size.x + size.z + 2.0 * uv2Padding);
            float widthH = size.x / horizontalTotal;
            float depthH = size.z / horizontalTotal;
            float paddingH = uv2Padding / horizontalTotal;

            float verticalTotal = (float)((size.y + size.y + size.z) + (3.0 * uv2Padding));
            float heightV = size.y / verticalTotal;
            float depthV = size.z / verticalTotal;
            float paddingV = uv2Padding / verticalTotal;

            Vec3 startPos = new Vec3(size.x * -0.5f, size.y * -0.5f, size.z * -0.5f);
            if (addUv2) arr.Uv2 = new List<Vec2>();
            point = 0;

            // front + back
            y = startPos.y;
            thisrow = point;
            prevrow = 0;
            for (j = 0; j <= (_subH + 1); j++)
            {
                float scale = (float)(j / (_subH + 1.0));
                float scaledSizeX = size.x * scale;
                float startX = (float)(startPos.x + (1.0 - scale) * size.x * leftToRight);
                float offsetFront = (float)((1.0 - scale) * onethird * leftToRight);
                float offsetBack = (float)((1.0 - scale) * onethird * (1.0 - leftToRight));

                float v = j;
                float v2 = scale;
                v = (float)(v / (2.0 * (_subH + 1.0)));

                x = 0.0f;
                for (i = 0; i <= (_subW + 1); i++)
                {
                    float u = i;
                    float u2 = (float)(i / (_subW + 1.0));
                    u = (float)(u / (3.0 * (_subW + 1.0)));
                    u *= scale;

                    // front
                    arr.Vertex.Add(new Vec3(startX + x, -y, -startPos.z));
                    arr.Normal.Add(new Vec3(0f, 0f, 1f));
                    arr.AddTangent(1f, 0f, 0f, 1f);
                    arr.Uv.Add(new Vec2(offsetFront + u, v));
                    if (addUv2) arr.Uv2.Add(new Vec2(u2 * scale * widthH, v2 * heightV));
                    point++;

                    // back
                    arr.Vertex.Add(new Vec3(startX + scaledSizeX - x, -y, startPos.z));
                    arr.Normal.Add(new Vec3(0f, 0f, -1f));
                    arr.AddTangent(-1f, 0f, 0f, 1f);
                    arr.Uv.Add(new Vec2(twothirds + offsetBack + u, v));
                    if (addUv2) arr.Uv2.Add(new Vec2(u2 * scale * widthH, heightV + paddingV + v2 * heightV));
                    point++;

                    if (i > 0 && j == 1)
                    {
                        int i2 = i * 2;
                        arr.Index.Add(prevrow + i2); arr.Index.Add(thisrow + i2); arr.Index.Add(thisrow + i2 - 2);
                        arr.Index.Add(prevrow + i2 + 1); arr.Index.Add(thisrow + i2 + 1); arr.Index.Add(thisrow + i2 - 1);
                    }
                    else if (i > 0 && j > 0)
                    {
                        int i2 = i * 2;
                        arr.Index.Add(prevrow + i2 - 2); arr.Index.Add(prevrow + i2); arr.Index.Add(thisrow + i2 - 2);
                        arr.Index.Add(prevrow + i2); arr.Index.Add(thisrow + i2); arr.Index.Add(thisrow + i2 - 2);
                        arr.Index.Add(prevrow + i2 - 1); arr.Index.Add(prevrow + i2 + 1); arr.Index.Add(thisrow + i2 - 1);
                        arr.Index.Add(prevrow + i2 + 1); arr.Index.Add(thisrow + i2 + 1); arr.Index.Add(thisrow + i2 - 1);
                    }
                    x = (float)(x + scale * size.x / (_subW + 1.0));
                }
                y = (float)(y + size.y / (_subH + 1.0));
                prevrow = thisrow;
                thisrow = point;
            }

            // left + right
            Vec3 normalLeft = new Vec3(-size.y, size.x * leftToRight, 0.0f).NormalizedChecked();
            Vec3 normalRight = new Vec3(size.y, (float)(size.x * (1.0 - leftToRight)), 0.0f).NormalizedChecked();

            y = startPos.y;
            thisrow = point;
            prevrow = 0;
            for (j = 0; j <= (_subH + 1); j++)
            {
                float left, right;
                float scale = (float)(j / (_subH + 1.0));
                left = (float)(startPos.x + (size.x * (1.0 - scale) * leftToRight));
                right = left + (size.x * scale);

                float v = j;
                float v2 = scale;
                v = (float)(v / (2.0 * (_subH + 1.0)));

                z = startPos.z;
                for (i = 0; i <= (_subD + 1); i++)
                {
                    float u = i;
                    float u2 = (float)(u / (_subD + 1.0));
                    u = (float)(u / (3.0 * (_subD + 1.0)));

                    // right
                    arr.Vertex.Add(new Vec3(right, -y, -z));
                    arr.Normal.Add(normalRight);
                    arr.AddTangent(0f, 0f, -1f, 1f);
                    arr.Uv.Add(new Vec2(onethird + u, v));
                    if (addUv2) arr.Uv2.Add(new Vec2(widthH + paddingH + u2 * depthH, v2 * heightV));
                    point++;

                    // left
                    arr.Vertex.Add(new Vec3(left, -y, z));
                    arr.Normal.Add(normalLeft);
                    arr.AddTangent(0f, 0f, 1f, 1f);
                    arr.Uv.Add(new Vec2(u, (float)(0.5 + v)));
                    if (addUv2) arr.Uv2.Add(new Vec2(widthH + paddingH + u2 * depthH, heightV + paddingV + v2 * heightV));
                    point++;

                    if (i > 0 && j > 0)
                    {
                        int i2 = i * 2;
                        arr.Index.Add(prevrow + i2 - 2); arr.Index.Add(prevrow + i2); arr.Index.Add(thisrow + i2 - 2);
                        arr.Index.Add(prevrow + i2); arr.Index.Add(thisrow + i2); arr.Index.Add(thisrow + i2 - 2);
                        arr.Index.Add(prevrow + i2 - 1); arr.Index.Add(prevrow + i2 + 1); arr.Index.Add(thisrow + i2 - 1);
                        arr.Index.Add(prevrow + i2 + 1); arr.Index.Add(thisrow + i2 + 1); arr.Index.Add(thisrow + i2 - 1);
                    }
                    z = (float)(z + size.z / (_subD + 1.0));
                }
                y = (float)(y + size.y / (_subH + 1.0));
                prevrow = thisrow;
                thisrow = point;
            }

            // bottom
            z = startPos.z;
            thisrow = point;
            prevrow = 0;
            for (j = 0; j <= (_subD + 1); j++)
            {
                float v = j;
                float v2 = (float)(v / (_subD + 1.0));
                v = (float)(v / (2.0 * (_subD + 1.0)));

                x = startPos.x;
                for (i = 0; i <= (_subW + 1); i++)
                {
                    float u = i;
                    float u2 = (float)(u / (_subW + 1.0));
                    u = (float)(u / (3.0 * (_subW + 1.0)));

                    arr.Vertex.Add(new Vec3(x, startPos.y, -z));
                    arr.Normal.Add(new Vec3(0f, -1f, 0f));
                    arr.AddTangent(1f, 0f, 0f, 1f);
                    arr.Uv.Add(new Vec2(twothirds + u, (float)(0.5 + v)));
                    if (addUv2) arr.Uv2.Add(new Vec2(u2 * widthH, (float)(2.0 * (heightV + paddingV) + v2 * depthV)));
                    point++;

                    if (i > 0 && j > 0)
                    {
                        arr.Index.Add(prevrow + i - 1); arr.Index.Add(prevrow + i); arr.Index.Add(thisrow + i - 1);
                        arr.Index.Add(prevrow + i); arr.Index.Add(thisrow + i); arr.Index.Add(thisrow + i - 1);
                    }
                    x = (float)(x + size.x / (_subW + 1.0));
                }
                z = (float)(z + size.z / (_subD + 1.0));
                prevrow = thisrow;
                thisrow = point;
            }
        }
    }

    // ------------------------------------------------------------------ SphereMesh
    public class SphereMesh : PrimitiveMesh
    {
        float _radius = 0.5f, _height = 1.0f;
        int _radialSegments = 64, _rings = 32;
        bool _isHemisphere;

        public double Radius { get => _radius; set { float r = (float)value; if (GD.IsEqualApproxF(r, _radius)) return; _radius = r; UpdateLightmapSize(); RequestUpdate(); } }
        public double Height { get => _height; set { float h = (float)value; if (GD.IsEqualApproxF(_height, h)) return; _height = h; UpdateLightmapSize(); RequestUpdate(); } }
        public int RadialSegments
        {
            get => _radialSegments;
            set { if (value == _radialSegments || (_radialSegments == 4 && value < 4)) return; _radialSegments = value > 4 ? value : 4; RequestUpdate(); }
        }
        public int Rings { get => _rings; set { if (value == _rings) return; if (value < 1) { GD.PushError("Condition \"p_rings < 1\" is true."); return; } _rings = value; RequestUpdate(); } }
        public bool IsHemisphere { get => _isHemisphere; set { if (value == _isHemisphere) return; _isHemisphere = value; UpdateLightmapSize(); RequestUpdate(); } }

        protected override void UpdateLightmapSize()
        {
            if (!AddUv2) return;
            float padding = (float)Uv2Padding;
            float width = (float)(_radius * GD.TAU);
            int lx = ToInt(Max(1.0, (width / texelSize) + padding));
            float height = (float)((_isHemisphere ? 1.0 : 0.5) * _height * Math.PI);
            LightmapSizeHint = new Vec2i(lx, ToInt(Max(1.0, (height / texelSize) + padding)));
        }

        protected override void CreateMeshArray(PrimitiveArrays a) =>
            CreateMeshArray(a, _radius, _height, _radialSegments, _rings, _isHemisphere, AddUv2, (float)Uv2Padding * texelSize);

        public static void CreateMeshArray(PrimitiveArrays arr, float radius, float height, int radialSegments, int rings, bool isHemisphere, bool addUv2, float uv2Padding)
        {
            int i, j, prevrow, thisrow, point;
            float x, y, z;

            float scale = (float)(height / radius * (isHemisphere ? 1.0 : 0.5));

            float circumference = (float)(radius * GD.TAU);
            float horizontalLength = circumference + uv2Padding;
            float centerH = (float)(0.5 * circumference / horizontalLength);
            float heightV = (float)(scale * Math.PI / ((scale * Math.PI) + uv2Padding / radius));
            if (addUv2) arr.Uv2 = new List<Vec2>();
            point = 0;

            thisrow = 0;
            prevrow = 0;
            for (j = 0; j <= (rings + 1); j++)
            {
                float v = j;
                float w;
                v /= (rings + 1);
                if (j == (rings + 1)) { w = 0.0f; y = -1.0f; }
                else { w = (float)Math.Sin(Math.PI * v); y = (float)Math.Cos(Math.PI * v); }

                for (i = 0; i <= radialSegments; i++)
                {
                    float u = i;
                    u /= radialSegments;
                    if (i == radialSegments) { x = 0.0f; z = 1.0f; }
                    else { x = (float)Math.Sin(u * GD.TAU); z = (float)Math.Cos(u * GD.TAU); }

                    if (isHemisphere && y < 0.0)
                    {
                        arr.Vertex.Add(new Vec3(x * radius * w, 0.0f, z * radius * w));
                        arr.Normal.Add(new Vec3(0f, -1f, 0f));
                    }
                    else
                    {
                        Vec3 p = new Vec3(x * w, y * scale, z * w);
                        arr.Vertex.Add(p * radius);
                        Vec3 normal = new Vec3(x * w * scale, y, z * w * scale);
                        arr.Normal.Add(normal.NormalizedChecked());
                    }
                    arr.AddTangent(z, 0.0f, -x, 1.0f);
                    arr.Uv.Add(new Vec2(u, v));
                    if (addUv2)
                    {
                        float wH = (float)(w * 2.0 * centerH);
                        arr.Uv2.Add(new Vec2((float)(centerH + ((u - 0.5) * wH)), v * heightV));
                    }
                    point++;

                    if (i > 0 && j > 0)
                    {
                        arr.Index.Add(prevrow + i - 1); arr.Index.Add(prevrow + i); arr.Index.Add(thisrow + i - 1);
                        arr.Index.Add(prevrow + i); arr.Index.Add(thisrow + i); arr.Index.Add(thisrow + i - 1);
                    }
                }
                prevrow = thisrow;
                thisrow = point;
            }
        }
    }

    // ------------------------------------------------------------------ TorusMesh
    public class TorusMesh : PrimitiveMesh
    {
        float _innerRadius = 0.5f, _outerRadius = 1.0f;
        int _rings = 64, _ringSegments = 32;

        public double InnerRadius { get => _innerRadius; set { float r = (float)value; if (GD.IsEqualApproxF(r, _innerRadius)) return; _innerRadius = r; RequestUpdate(); } }
        public double OuterRadius { get => _outerRadius; set { float r = (float)value; if (GD.IsEqualApproxF(r, _outerRadius)) return; _outerRadius = r; RequestUpdate(); } }
        public int Rings { get => _rings; set { if (value == _rings) return; if (value < 3) { GD.PushError("Condition \"p_rings < 3\" is true."); return; } _rings = value; RequestUpdate(); } }
        public int RingSegments { get => _ringSegments; set { if (value == _ringSegments) return; if (value < 3) { GD.PushError("Condition \"p_ring_segments < 3\" is true."); return; } _ringSegments = value; RequestUpdate(); } }

        protected override void UpdateLightmapSize()
        {
            if (!AddUv2) return;
            float padding = (float)Uv2Padding;
            float minRadius = _innerRadius, maxRadius = _outerRadius;
            if (minRadius > maxRadius) { float t = minRadius; minRadius = maxRadius; maxRadius = t; }
            float radius = (float)((maxRadius - minRadius) * 0.5);
            float width = (float)(maxRadius * GD.TAU);
            int lx = ToInt(Max(1.0, (width / texelSize) + padding));
            float height = (float)(radius * GD.TAU);
            LightmapSizeHint = new Vec2i(lx, ToInt(Max(1.0, (height / texelSize) + padding)));
        }

        protected override void CreateMeshArray(PrimitiveArrays arr)
        {
            bool addUv2 = AddUv2;
            if (_innerRadius == _outerRadius) { GD.PushError("Inner radius and outer radius cannot be the same."); return; }
            if (addUv2) arr.Uv2 = new List<Vec2>();

            float minRadius = _innerRadius;
            float maxRadius = _outerRadius;
            if (minRadius > maxRadius) { float t = minRadius; minRadius = maxRadius; maxRadius = t; }
            float radius = (float)((maxRadius - minRadius) * 0.5);

            float uv2Padding = (float)Uv2Padding * texelSize;
            float horizontalTotal = (float)(maxRadius * GD.TAU + uv2Padding);
            float maxH = (float)(maxRadius * GD.TAU / horizontalTotal);
            float deltaH = (float)((maxRadius - minRadius) * GD.TAU / horizontalTotal);
            float heightV = (float)(radius * GD.TAU / (radius * GD.TAU + uv2Padding));

            for (int i = 0; i <= _rings; i++)
            {
                int prevrow = (i - 1) * (_ringSegments + 1);
                int thisrow = i * (_ringSegments + 1);
                float inci = (float)i / _rings;
                float angi = (float)(inci * GD.TAU);

                Vec2 normali = (i == _rings) ? new Vec2(0f, -1f) : new Vec2(-MathF.Sin(angi), -MathF.Cos(angi));

                for (int j = 0; j <= _ringSegments; j++)
                {
                    float incj = (float)j / _ringSegments;
                    float angj = (float)(incj * GD.TAU);

                    Vec2 normalj = (j == _ringSegments) ? new Vec2(-1f, 0f) : new Vec2(-MathF.Cos(angj), MathF.Sin(angj));
                    Vec2 normalk = new Vec2(normalj.x * radius, normalj.y * radius) + new Vec2(minRadius + radius, 0f);

                    float offsetH = (float)(0.5 * (1.0 - normalj.x) * deltaH);
                    float adjH = maxH - offsetH;
                    offsetH = (float)(offsetH * 0.5);

                    arr.Vertex.Add(new Vec3(normali.x * normalk.x, normalk.y, normali.y * normalk.x));
                    arr.Normal.Add(new Vec3(normali.x * normalj.x, normalj.y, normali.y * normalj.x));
                    arr.AddTangent(normali.y, 0.0f, -normali.x, 1.0f);
                    arr.Uv.Add(new Vec2(inci, incj));
                    if (addUv2) arr.Uv2.Add(new Vec2(offsetH + inci * adjH, incj * heightV));

                    if (i > 0 && j > 0)
                    {
                        arr.Index.Add(thisrow + j - 1); arr.Index.Add(prevrow + j); arr.Index.Add(prevrow + j - 1);
                        arr.Index.Add(thisrow + j - 1); arr.Index.Add(thisrow + j); arr.Index.Add(prevrow + j);
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ PointMesh
    /// <summary>A single point at the origin, drawn as a PRIMITIVE_POINTS surface (its size from the material).</summary>
    public class PointMesh : PrimitiveMesh
    {
        public PointMesh() { primitiveType = PrimitiveType.Points; }
        protected override void CreateMeshArray(PrimitiveArrays arr) => arr.Vertex.Add(new Vec3(0f, 0f, 0f));
    }
}

#endif
