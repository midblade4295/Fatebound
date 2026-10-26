#if FB3D
// Godot's SurfaceTool (scene/resources/surface_tool.cpp) with its tangent generator, Morten Mikkelsen's mikktspace
// (thirdparty/misc/mikktspace.c, transcribed function by function: same welding, grouping, sorting seeds and float
// steps), and GpuPacking: the RenderingServer's GPU packing of normals/tangents (octahedral 16-bit), colours (8-bit)
// and weights (16-bit), which Godot applies to every mesh it stores. Godot's surface_get_arrays() returns the packed
// values decoded, so SurfaceTool.create_from/append_from read a C# mesh through GpuPacking.AsStored to see what Godot
// sees; a renderer uploading MeshSurface data packs the same way.
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    /// <summary>The RenderingServer's vertex packing (rendering_server.cpp) and Vector3's octahedral helpers.</summary>
    public static class GpuPacking
    {
        public static Vec2 OctahedronEncode(Vec3 v)
        {
            Vec3 n = v;
            float s = MathF.Abs(n.x) + MathF.Abs(n.y) + MathF.Abs(n.z);
            n = new Vec3(n.x / s, n.y / s, n.z / s);
            float ox, oy;
            if (n.z >= 0.0f) { ox = n.x; oy = n.y; }
            else
            {
                ox = (1.0f - MathF.Abs(n.y)) * (n.x >= 0.0f ? 1.0f : -1.0f);
                oy = (1.0f - MathF.Abs(n.x)) * (n.y >= 0.0f ? 1.0f : -1.0f);
            }
            return new Vec2(ox * 0.5f + 0.5f, oy * 0.5f + 0.5f);
        }

        public static Vec3 OctahedronDecode(Vec2 oct)
        {
            float fx = oct.x * 2.0f - 1.0f, fy = oct.y * 2.0f - 1.0f;
            Vec3 n = new Vec3(fx, fy, 1.0f - MathF.Abs(fx) - MathF.Abs(fy));
            float t = -n.z < 0.0f ? 0.0f : (-n.z > 1.0f ? 1.0f : -n.z);
            n.x += n.x >= 0 ? -t : t;
            n.y += n.y >= 0 ? -t : t;
            return n.NormalizedChecked();
        }

        public static Vec2 OctahedronTangentEncode(Vec3 t, float sign)
        {
            float bias = 1.0f / 32767.0f;
            Vec2 res = OctahedronEncode(t);
            res.y = res.y > bias ? res.y : bias;
            res.y = res.y * 0.5f + 0.5f;
            res.y = sign >= 0.0f ? res.y : 1 - res.y;
            return res;
        }

        public static Vec3 OctahedronTangentDecode(Vec2 oct, out float sign)
        {
            Vec2 c = oct;
            c.y = c.y * 2 - 1;
            sign = c.y >= 0.0f ? 1.0f : -1.0f;
            c.y = MathF.Abs(c.y);
            return OctahedronDecode(c);
        }

        static ushort U16(float v) => (ushort)(v < 0 ? 0f : (v > 65535 ? 65535f : v));

        /// <summary>A normal as stored on the GPU (two unorm16 of its octahedral encoding).</summary>
        public static uint PackNormal(Vec3 n)
        {
            Vec2 r = OctahedronEncode(n);
            return (uint)U16(r.x * 65535) | ((uint)U16(r.y * 65535) << 16);
        }

        public static Vec3 UnpackNormal(uint v) => OctahedronDecode(new Vec2((float)((v & 0xFFFF) / 65535.0), (float)(((v >> 16) & 0xFFFF) / 65535.0)));

        /// <summary>A tangent + binormal sign as stored on the GPU.</summary>
        public static uint PackTangent(Vec3 t, float sign)
        {
            Vec2 r = OctahedronTangentEncode(t, sign);
            ushort a = U16(r.x * 65535), b = U16(r.y * 65535);
            if (a == 0 && b == 65535) a = 65535;
            return (uint)a | ((uint)b << 16);
        }

        public static Vec3 UnpackTangent(uint v, out float sign) =>
            OctahedronTangentDecode(new Vec2((float)((v & 0xFFFF) / 65535.0), (float)(((v >> 16) & 0xFFFF) / 65535.0)), out sign);

        /// <summary>The tangent the server makes up for a surface with normals but no tangents.</summary>
        public static Vec3 ArbitraryTangent(Vec3 n) => new Vec3(n.z, -n.x, n.y).Cross(n.NormalizedChecked()).NormalizedChecked();

        public static byte ColorByte(float c) { double v = c * 255.0; return (byte)(v < 0.0 ? 0.0 : (v > 255.0 ? 255.0 : v)); }
        public static float ColorRoundTrip(float c) => (float)(ColorByte(c) / 255.0);
        public static float WeightRoundTrip(float w) { float v = w * 65535; ushort u = (ushort)(v < 0 ? 0f : (v > 65535 ? 65535f : v)); return (float)(u / 65535.0); }

        /// <summary>A surface's arrays as Godot's surface_get_arrays() returns them after packing: normals and tangents
        /// through the octahedral encoding (tangents made up when only normals were given), colours through 8 bits,
        /// weights through 16 bits. Positions, UVs, custom floats, bones and indices are unchanged.</summary>
        public static MeshSurface AsStored(MeshSurface s)
        {
            var o = s.Clone();
            if (s.Normals != null)
            {
                o.Normals = new Vec3[s.Normals.Length];
                for (int i = 0; i < s.Normals.Length; i++) o.Normals[i] = UnpackNormal(PackNormal(s.Normals[i]));
                o.Tangents = new float[s.Normals.Length * 4];
                for (int i = 0; i < s.Normals.Length; i++)
                {
                    uint p = s.Tangents != null && s.Tangents.Length >= i * 4 + 4
                        ? PackTangent(new Vec3(s.Tangents[i * 4], s.Tangents[i * 4 + 1], s.Tangents[i * 4 + 2]), s.Tangents[i * 4 + 3])
                        : PackTangent(ArbitraryTangent(s.Normals[i]), 1.0f);
                    Vec3 t = UnpackTangent(p, out float sign);
                    o.Tangents[i * 4] = t.x; o.Tangents[i * 4 + 1] = t.y; o.Tangents[i * 4 + 2] = t.z; o.Tangents[i * 4 + 3] = sign;
                }
            }
            else if (s.Tangents != null)
            {
                o.Tangents = new float[s.Tangents.Length];
                for (int i = 0; i + 3 < s.Tangents.Length; i += 4)
                {
                    Vec3 t = UnpackTangent(PackTangent(new Vec3(s.Tangents[i], s.Tangents[i + 1], s.Tangents[i + 2]), s.Tangents[i + 3]), out float sign);
                    o.Tangents[i] = t.x; o.Tangents[i + 1] = t.y; o.Tangents[i + 2] = t.z; o.Tangents[i + 3] = sign;
                }
            }
            if (s.Colors != null)
            {
                o.Colors = new Col[s.Colors.Length];
                for (int i = 0; i < s.Colors.Length; i++)
                {
                    Col c = s.Colors[i];
                    o.Colors[i] = new Col(ColorRoundTrip(c.r), ColorRoundTrip(c.g), ColorRoundTrip(c.b), ColorRoundTrip(c.a));
                }
            }
            if (s.Weights != null)
            {
                o.Weights = new float[s.Weights.Length];
                for (int i = 0; i < s.Weights.Length; i++) o.Weights[i] = WeightRoundTrip(s.Weights[i]);
            }
            return o;
        }

        /// <summary>Math::make_half_float.</summary>
        public static ushort MakeHalfFloat(float value)
        {
            uint x = (uint)BitConverter.SingleToInt32Bits(value);
            uint sign = (ushort)(x >> 31);
            uint mantissa = x & ((1u << 23) - 1);
            uint exponent = x & (0xFFu << 23);
            ushort hf;
            if (exponent >= 0x47800000)
            {
                if (mantissa != 0 && (exponent == (0xFFu << 23))) mantissa = (1u << 23) - 1;
                else mantissa = 0;
                hf = (ushort)((((ushort)sign) << 15) | (ushort)(0x1F << 10) | (ushort)(mantissa >> 13));
            }
            else if (exponent <= 0x38000000) hf = 0;
            else hf = (ushort)((((ushort)sign) << 15) | (ushort)((exponent - 0x38000000) >> 13) | (ushort)(mantissa >> 13));
            return hf;
        }
    }

    /// <summary>Godot's SurfaceTool: builds one surface vertex by vertex (the last set attributes apply to each
    /// add_vertex), indexes/deindexes it, generates normals (with smooth groups) and mikktspace tangents, and commits
    /// it to an ArrayMesh.</summary>
    public sealed class SurfaceTool
    {
        public const int CUSTOM_RGBA8_UNORM = 0, CUSTOM_RGBA8_SNORM = 1, CUSTOM_RG_HALF = 2, CUSTOM_RGBA_HALF = 3,
            CUSTOM_R_FLOAT = 4, CUSTOM_RG_FLOAT = 5, CUSTOM_RGB_FLOAT = 6, CUSTOM_RGBA_FLOAT = 7, CUSTOM_MAX = 8;
        public const int SKIN_4_WEIGHTS = 0, SKIN_8_WEIGHTS = 1;
        const ulong ARRAY_FORMAT_CUSTOM0 = 1 << 6;
        const int ARRAY_COMPRESS_FLAGS_BASE = 25;
        static readonly ulong[] CustomMask = { 1 << 6, 1 << 7, 1 << 8, 1 << 9 };
        static readonly int[] CustomShift = { 13, 16, 19, 22 };

        public struct Vertex
        {
            public uint SmoothGroup;
            public Col Color;
            public Vec3 Normal, Binormal, Tangent;
            public Vec2 Uv, Uv2;
            public Col Custom0, Custom1, Custom2, Custom3;
            public Vec3 Pos;
            public int[] Bones;
            public float[] Weights;

            public Col GetCustom(int i) => i == 0 ? Custom0 : i == 1 ? Custom1 : i == 2 ? Custom2 : Custom3;
            public void SetCustom(int i, Col c) { if (i == 0) Custom0 = c; else if (i == 1) Custom1 = c; else if (i == 2) Custom2 = c; else Custom3 = c; }
        }

        bool _begun, _first;
        PrimitiveType _primitive = PrimitiveType.Lines;
        ulong _format;
        GMaterial _material;
        readonly List<Vertex> _vertices = new List<Vertex>();
        readonly List<int> _indices = new List<int>();

        Col _lastColor = new Col(0f, 0f, 0f, 1f);
        Vec3 _lastNormal;
        Vec2 _lastUv, _lastUv2;
        int[] _lastBones = Array.Empty<int>();
        float[] _lastWeights = Array.Empty<float>();
        Plane _lastTangent;
        uint _lastSmoothGroup;
        int _skinWeights = SKIN_4_WEIGHTS;
        readonly Col[] _lastCustom = new Col[4] { new Col(0f, 0f, 0f, 1f), new Col(0f, 0f, 0f, 1f), new Col(0f, 0f, 0f, 1f), new Col(0f, 0f, 0f, 1f) };
        readonly int[] _lastCustomFormat = { CUSTOM_MAX, CUSTOM_MAX, CUSTOM_MAX, CUSTOM_MAX };

        static void Err(string m) => GD.PushError(m);

        /// <summary>The vertices as built so far (read-only view; tests and tools).</summary>
        public IReadOnlyList<Vertex> Vertices => _vertices;
        public IReadOnlyList<int> Indices => _indices;
        public ulong Format => _format;

        // ------------------------------------------------------------------ building
        public void Begin(PrimitiveType primitive)
        {
            Clear();
            _primitive = primitive;
            _begun = true;
            _first = true;
        }

        public void Begin(int primitive) => Begin((PrimitiveType)primitive);

        public void AddVertex(Vec3 vertex)
        {
            if (!_begun) { Err("Condition \"!begun\" is true."); return; }
            var vtx = new Vertex
            {
                Pos = vertex,
                Color = _lastColor,
                Normal = _lastNormal,
                Uv = _lastUv,
                Uv2 = _lastUv2,
                Weights = _lastWeights,
                Bones = _lastBones,
                Tangent = _lastTangent.normal,
                SmoothGroup = _lastSmoothGroup,
            };
            Vec3 bn = _lastNormal.Cross(_lastTangent.normal).NormalizedChecked();
            float td = _lastTangent.d;
            vtx.Binormal = new Vec3(bn.x * td, bn.y * td, bn.z * td);
            for (int i = 0; i < 4; i++) vtx.SetCustom(i, _lastCustom[i]);

            int expected = _skinWeights == SKIN_8_WEIGHTS ? 8 : 4;
            if (((_format & Mesh.ARRAY_FORMAT_WEIGHTS) != 0 || (_format & Mesh.ARRAY_FORMAT_BONES) != 0)
                && (vtx.Weights.Length != expected || vtx.Bones.Length != expected))
            {
                if (vtx.Weights.Length != vtx.Bones.Length) { Err("Condition \"vtx.weights.size() != vtx.bones.size()\" is true."); return; }
                if (vtx.Weights.Length < expected)
                {
                    var w = new float[expected];
                    var b = new int[expected];
                    Array.Copy(vtx.Weights, w, vtx.Weights.Length);
                    Array.Copy(vtx.Bones, b, vtx.Bones.Length);
                    vtx.Weights = w;
                    vtx.Bones = b;
                }
                else if (vtx.Weights.Length > expected)
                {
                    // sort (ascending weight, Godot's WeightSort::operator<; insertion sort keeps ties in order), cap, renormalize
                    int n = vtx.Weights.Length;
                    var idx = new int[n];
                    var wt = new float[n];
                    for (int i = 0; i < n; i++) { idx[i] = vtx.Bones[i]; wt[i] = vtx.Weights[i]; }
                    for (int i = 1; i < n; i++)
                    {
                        int ki = idx[i]; float kw = wt[i];
                        int j = i - 1;
                        while (j >= 0 && kw < wt[j]) { idx[j + 1] = idx[j]; wt[j + 1] = wt[j]; j--; }
                        idx[j + 1] = ki; wt[j + 1] = kw;
                    }
                    float total = 0.0f;
                    for (int i = 0; i < expected; i++) total += wt[i];
                    var w = new float[expected];
                    var b = new int[expected];
                    for (int i = 0; i < expected; i++)
                    {
                        w[i] = total > 0 ? wt[i] / total : 0;
                        b[i] = idx[i];
                    }
                    vtx.Weights = w;
                    vtx.Bones = b;
                }
            }

            _vertices.Add(vtx);
            _first = false;
            _format |= Mesh.ARRAY_FORMAT_VERTEX;
        }

        bool Settable(ulong bit)
        {
            if (!_begun) { Err("Condition \"!begun\" is true."); return false; }
            if (!_first && (_format & bit) == 0) { Err("Condition \"!first && !(format & bit)\" is true."); return false; }
            return true;
        }

        public void SetColor(Col c) { if (!Settable(Mesh.ARRAY_FORMAT_COLOR)) return; _format |= Mesh.ARRAY_FORMAT_COLOR; _lastColor = c; }
        public void SetNormal(Vec3 n) { if (!Settable(Mesh.ARRAY_FORMAT_NORMAL)) return; _format |= Mesh.ARRAY_FORMAT_NORMAL; _lastNormal = n; }
        public void SetTangent(Plane t) { if (!Settable(Mesh.ARRAY_FORMAT_TANGENT)) return; _format |= Mesh.ARRAY_FORMAT_TANGENT; _lastTangent = t; }
        public void SetUv(Vec2 uv) { if (!Settable(Mesh.ARRAY_FORMAT_TEX_UV)) return; _format |= Mesh.ARRAY_FORMAT_TEX_UV; _lastUv = uv; }
        public void SetUv2(Vec2 uv) { if (!Settable(Mesh.ARRAY_FORMAT_TEX_UV2)) return; _format |= Mesh.ARRAY_FORMAT_TEX_UV2; _lastUv2 = uv; }

        public void SetCustom(int channel, Col c)
        {
            if (channel < 0 || channel >= 4) { Err("Index p_channel_index out of bounds."); return; }
            if (!_begun) { Err("Condition \"!begun\" is true."); return; }
            if (_lastCustomFormat[channel] == CUSTOM_MAX) { Err("Condition \"last_custom_format[p_channel_index] == CUSTOM_MAX\" is true."); return; }
            if (!_first && (_format & CustomMask[channel]) == 0) { Err("Condition \"!first && !(format & mask[p_channel_index])\" is true."); return; }
            if (_first) _format |= CustomMask[channel];
            _lastCustom[channel] = c;
        }

        public void SetBones(int[] bones)
        {
            if (!Settable(Mesh.ARRAY_FORMAT_BONES)) return;
            _format |= Mesh.ARRAY_FORMAT_BONES;
            if (_skinWeights == SKIN_8_WEIGHTS) _format |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS;
            _lastBones = bones == null ? Array.Empty<int>() : (int[])bones.Clone();
        }

        public void SetBones(Var bones) => SetBones(Mesh.ToIntArray(bones));

        public void SetWeights(float[] weights)
        {
            if (!Settable(Mesh.ARRAY_FORMAT_WEIGHTS)) return;
            _format |= Mesh.ARRAY_FORMAT_WEIGHTS;
            if (_skinWeights == SKIN_8_WEIGHTS) _format |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS;
            _lastWeights = weights == null ? Array.Empty<float>() : (float[])weights.Clone();
        }

        public void SetWeights(Var weights) => SetWeights(Mesh.ToFloatArray(weights));

        /// <summary>set_smooth_group: -1 (UINT32_MAX) makes the vertex flat-shaded by generate_normals().</summary>
        public void SetSmoothGroup(long group) => _lastSmoothGroup = unchecked((uint)group);

        public void AddTriangleFan(IList<Vec3> vertices, IList<Vec2> uvs = null, IList<Col> colors = null, IList<Vec2> uv2s = null,
            IList<Vec3> normals = null, IList<Plane> tangents = null)
        {
            if (!_begun) { Err("Condition \"!begun\" is true."); return; }
            if (_primitive != PrimitiveType.Triangles) { Err("Condition \"primitive != Mesh::PRIMITIVE_TRIANGLES\" is true."); return; }
            if (vertices == null || vertices.Count < 3) { Err("Condition \"p_vertices.size() < 3\" is true."); return; }
            void Point(int n)
            {
                if (colors != null && colors.Count > n) SetColor(colors[n]);
                if (uvs != null && uvs.Count > n) SetUv(uvs[n]);
                if (uv2s != null && uv2s.Count > n) SetUv2(uv2s[n]);
                if (normals != null && normals.Count > n) SetNormal(normals[n]);
                if (tangents != null && tangents.Count > n) SetTangent(tangents[n]);
                AddVertex(vertices[n]);
            }
            for (int i = 0; i < vertices.Count - 2; i++)
            {
                Point(0);
                Point(i + 1);
                Point(i + 2);
            }
        }

        public void AddIndex(int index)
        {
            if (!_begun) { Err("Condition \"!begun\" is true."); return; }
            if (index < 0) { Err("Condition \"p_index < 0\" is true."); return; }
            _format |= Mesh.ARRAY_FORMAT_INDEX;
            _indices.Add(index);
        }

        // ------------------------------------------------------------------ output
        /// <summary>commit_to_arrays(): Godot's ARRAY_MAX array (packed arrays as C# arrays inside Vars; custom byte
        /// formats as byte[]).</summary>
        public GArray CommitToArrays()
        {
            int n = _vertices.Count;
            var a = new GArray();
            a.Resize(Mesh.ARRAY_MAX);
            for (int i = 0; i < Mesh.ARRAY_MAX; i++)
            {
                if ((_format & (1UL << i)) == 0) continue;
                switch (i)
                {
                    case Mesh.ARRAY_VERTEX:
                    {
                        var arr = new Vec3[n];
                        for (int k = 0; k < n; k++) arr[k] = _vertices[k].Pos;
                        a[i] = Var.Of(arr);
                        break;
                    }
                    case Mesh.ARRAY_NORMAL:
                    {
                        var arr = new Vec3[n];
                        for (int k = 0; k < n; k++) arr[k] = _vertices[k].Normal;
                        a[i] = Var.Of(arr);
                        break;
                    }
                    case Mesh.ARRAY_TEX_UV:
                    case Mesh.ARRAY_TEX_UV2:
                    {
                        var arr = new Vec2[n];
                        for (int k = 0; k < n; k++) arr[k] = i == Mesh.ARRAY_TEX_UV ? _vertices[k].Uv : _vertices[k].Uv2;
                        a[i] = Var.Of(arr);
                        break;
                    }
                    case Mesh.ARRAY_TANGENT:
                    {
                        var arr = new float[n * 4];
                        for (int k = 0; k < n; k++)
                        {
                            var v = _vertices[k];
                            arr[k * 4] = v.Tangent.x;
                            arr[k * 4 + 1] = v.Tangent.y;
                            arr[k * 4 + 2] = v.Tangent.z;
                            float d = v.Binormal.Dot(v.Normal.Cross(v.Tangent));
                            arr[k * 4 + 3] = d < 0 ? -1 : 1;
                        }
                        a[i] = Var.Of(arr);
                        break;
                    }
                    case Mesh.ARRAY_COLOR:
                    {
                        var arr = new Col[n];
                        for (int k = 0; k < n; k++) arr[k] = _vertices[k].Color;
                        a[i] = Var.Of(arr);
                        break;
                    }
                    case Mesh.ARRAY_CUSTOM0:
                    case Mesh.ARRAY_CUSTOM1:
                    case Mesh.ARRAY_CUSTOM2:
                    case Mesh.ARRAY_CUSTOM3:
                        a[i] = CustomArray(i - Mesh.ARRAY_CUSTOM0);
                        break;
                    case Mesh.ARRAY_BONES:
                    {
                        int count = _skinWeights == SKIN_8_WEIGHTS ? 8 : 4;
                        var arr = new int[n * count];
                        for (int k = 0; k < n; k++)
                        {
                            var v = _vertices[k];
                            if (v.Bones.Length != count) { Err("Invalid bones size " + v.Bones.Length + " vs count " + count); continue; }
                            for (int j = 0; j < count; j++) arr[k * count + j] = v.Bones[j];
                        }
                        a[i] = Var.Of(arr);
                        break;
                    }
                    case Mesh.ARRAY_WEIGHTS:
                    {
                        int count = _skinWeights == SKIN_8_WEIGHTS ? 8 : 4;
                        var arr = new float[n * count];
                        for (int k = 0; k < n; k++)
                        {
                            var v = _vertices[k];
                            if (v.Weights.Length != count) { Err("Invalid weight size " + v.Weights.Length + " vs count " + count); continue; }
                            for (int j = 0; j < count; j++) arr[k * count + j] = v.Weights[j];
                        }
                        a[i] = Var.Of(arr);
                        break;
                    }
                    case Mesh.ARRAY_INDEX:
                        if (_indices.Count == 0) { Err("Condition \"index_array.is_empty()\" is true. Continuing."); continue; }
                        a[i] = Var.Of(_indices.ToArray());
                        break;
                }
            }
            return a;
        }

        Var CustomArray(int fmt)
        {
            int n = _vertices.Count;
            static int Clampi(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
            switch (_lastCustomFormat[fmt])
            {
                case CUSTOM_RGBA8_UNORM:
                {
                    var arr = new byte[n * 4];
                    for (int k = 0; k < n; k++)
                    {
                        Col c = _vertices[k].GetCustom(fmt);
                        arr[k * 4] = (byte)Clampi((int)(c.r * 255.0), 0, 255);
                        arr[k * 4 + 1] = (byte)Clampi((int)(c.g * 255.0), 0, 255);
                        arr[k * 4 + 2] = (byte)Clampi((int)(c.b * 255.0), 0, 255);
                        arr[k * 4 + 3] = (byte)Clampi((int)(c.a * 255.0), 0, 255);
                    }
                    return Var.Of(arr);
                }
                case CUSTOM_RGBA8_SNORM:
                {
                    var arr = new byte[n * 4];
                    for (int k = 0; k < n; k++)
                    {
                        Col c = _vertices[k].GetCustom(fmt);
                        arr[k * 4] = unchecked((byte)(sbyte)Clampi((int)(c.r * 127.0), -128, 127));
                        arr[k * 4 + 1] = unchecked((byte)(sbyte)Clampi((int)(c.g * 127.0), -128, 127));
                        arr[k * 4 + 2] = unchecked((byte)(sbyte)Clampi((int)(c.b * 127.0), -128, 127));
                        arr[k * 4 + 3] = unchecked((byte)(sbyte)Clampi((int)(c.a * 127.0), -128, 127));
                    }
                    return Var.Of(arr);
                }
                case CUSTOM_RG_HALF:
                case CUSTOM_RGBA_HALF:
                {
                    int ch = _lastCustomFormat[fmt] == CUSTOM_RG_HALF ? 2 : 4;
                    var arr = new byte[n * ch * 2];
                    for (int k = 0; k < n; k++)
                    {
                        Col c = _vertices[k].GetCustom(fmt);
                        float[] cc = { c.r, c.g, c.b, c.a };
                        for (int j = 0; j < ch; j++)
                        {
                            ushort h = GpuPacking.MakeHalfFloat(cc[j]);
                            arr[(k * ch + j) * 2] = (byte)(h & 0xFF);
                            arr[(k * ch + j) * 2 + 1] = (byte)(h >> 8);
                        }
                    }
                    return Var.Of(arr);
                }
                case CUSTOM_R_FLOAT:
                case CUSTOM_RG_FLOAT:
                case CUSTOM_RGB_FLOAT:
                case CUSTOM_RGBA_FLOAT:
                {
                    int ch = _lastCustomFormat[fmt] - CUSTOM_R_FLOAT + 1;
                    var arr = new float[n * ch];
                    for (int k = 0; k < n; k++)
                    {
                        Col c = _vertices[k].GetCustom(fmt);
                        float[] cc = { c.r, c.g, c.b, c.a };
                        for (int j = 0; j < ch; j++) arr[k * ch + j] = cc[j];
                    }
                    return Var.Of(arr);
                }
            }
            return Var.Nil;
        }

        /// <summary>commit(existing = null, flags = 0): appends the surface to `existing` (or a new ArrayMesh).</summary>
        public ArrayMesh Commit(ArrayMesh existing = null, ulong compressFlags = 0)
        {
            ArrayMesh mesh = existing ?? new ArrayMesh();
            if (_vertices.Count == 0) return mesh;
            int surface = mesh.GetSurfaceCount();
            GArray a = CommitToArrays();
            ulong flags = (compressFlags >> ARRAY_COMPRESS_FLAGS_BASE) << ARRAY_COMPRESS_FLAGS_BASE;
            for (int i = 0; i < 4; i++)
                if (_lastCustomFormat[i] != CUSTOM_MAX) flags |= (ulong)_lastCustomFormat[i] << CustomShift[i];
            var s = Mesh.SurfaceFromArrays(_primitive, a, (uint)flags);
            uint fmt = (uint)flags;
            for (int i = 0; i < Mesh.ARRAY_MAX; i++) if (i < a.Size() && !a[i].IsNil) fmt |= 1u << i;
            if (s.Normals != null && s.Tangents == null) fmt |= Mesh.ARRAY_FORMAT_TANGENT;
            s.Format = fmt;
            mesh.AddSurface(s);
            if (_material != null) mesh.SurfaceSetMaterial(surface, _material);
            return mesh;
        }

        // ------------------------------------------------------------------ indexing
        sealed class VertexComparer : IEqualityComparer<Vertex>
        {
            public static readonly VertexComparer Instance = new VertexComparer();
            static bool Eq(Col a, Col b) => a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a;

            public bool Equals(Vertex a, Vertex b)
            {
                if (a.Pos != b.Pos || a.Uv != b.Uv || a.Uv2 != b.Uv2 || a.Normal != b.Normal || a.Binormal != b.Binormal || a.Tangent != b.Tangent) return false;
                if (!Eq(a.Color, b.Color)) return false;
                if (a.Bones.Length != b.Bones.Length) return false;
                for (int i = 0; i < a.Bones.Length; i++) if (a.Bones[i] != b.Bones[i]) return false;
                for (int i = 0; i < a.Weights.Length && i < b.Weights.Length; i++) if (a.Weights[i] != b.Weights[i]) return false;
                if (!Eq(a.Custom0, b.Custom0) || !Eq(a.Custom1, b.Custom1) || !Eq(a.Custom2, b.Custom2) || !Eq(a.Custom3, b.Custom3)) return false;
                return a.SmoothGroup == b.SmoothGroup;
            }

            // (raw bits, as Godot hashes the bytes: +0 and -0 hash apart)
            static int H(int h, float f) => unchecked(h * 31 + BitConverter.SingleToInt32Bits(f));
            public int GetHashCode(Vertex v)
            {
                int h = (int)v.SmoothGroup;
                h = H(H(H(h, v.Pos.x), v.Pos.y), v.Pos.z);
                h = H(H(h, v.Uv.x), v.Uv.y);
                h = H(H(H(h, v.Normal.x), v.Normal.y), v.Normal.z);
                h = H(H(H(H(h, v.Color.r), v.Color.g), v.Color.b), v.Color.a);
                foreach (int b in v.Bones) h = unchecked(h * 31 + b);
                foreach (float w in v.Weights) h = H(h, w);
                return h;
            }
        }

        /// <summary>index(): merges identical vertices (first appearance order) and builds the index array.</summary>
        public void Index()
        {
            if (_indices.Count > 0) return;
            var map = new Dictionary<Vertex, int>(_vertices.Count, VertexComparer.Instance);
            int newSize = 0;
            for (int k = 0; k < _vertices.Count; k++)
            {
                Vertex v = _vertices[k];
                if (!map.TryGetValue(v, out int idx))
                {
                    idx = map.Count;
                    _vertices[newSize] = v;
                    map.Add(v, idx);
                    newSize++;
                }
                _indices.Add(idx);
            }
            _vertices.RemoveRange(newSize, _vertices.Count - newSize);
            _format |= Mesh.ARRAY_FORMAT_INDEX;
        }

        public void Deindex()
        {
            if (_indices.Count == 0) return;
            var old = _vertices.ToArray();
            _vertices.Clear();
            foreach (int index in _indices)
            {
                if ((uint)index >= (uint)old.Length) { Err("Condition \"uint32_t(index) >= old_vertex_array.size()\" is true."); return; }
                _vertices.Add(old[index]);
            }
            _format &= ~(ulong)Mesh.ARRAY_FORMAT_INDEX;
            _indices.Clear();
        }

        // ------------------------------------------------------------------ reading meshes
        sealed class SourceArrays
        {
            public Vec3[] V, N;
            public float[] T;
            public Col[] C;
            public Vec2[] Uv, Uv2;
            public int[] Bones;
            public float[] Weights;
            public float[][] Custom = new float[4][];
            public int[] Index;
        }

        static SourceArrays FromGArray(GArray arrays)
        {
            Var At(int i) => i < arrays.Size() ? arrays[i] : Var.Nil;
            var s = new SourceArrays
            {
                V = Mesh.ToVec3Array(At(Mesh.ARRAY_VERTEX)),
                N = Mesh.ToVec3Array(At(Mesh.ARRAY_NORMAL)),
                T = Mesh.ToFloatArray(At(Mesh.ARRAY_TANGENT)),
                C = Mesh.ToColArray(At(Mesh.ARRAY_COLOR)),
                Uv = Mesh.ToVec2Array(At(Mesh.ARRAY_TEX_UV)),
                Uv2 = Mesh.ToVec2Array(At(Mesh.ARRAY_TEX_UV2)),
                Bones = Mesh.ToIntArray(At(Mesh.ARRAY_BONES)),
                Weights = Mesh.ToFloatArray(At(Mesh.ARRAY_WEIGHTS)),
                Index = Mesh.ToIntArray(At(Mesh.ARRAY_INDEX)),
            };
            for (int c = 0; c < 4; c++)
            {
                Var cv = At(Mesh.ARRAY_CUSTOM0 + c);
                if (cv.Obj is byte[]) Err("Extracting Byte/Half formats is not supported");
                else if (cv.Obj is float[] || cv.Obj is List<float>) s.Custom[c] = Mesh.ToFloatArray(cv);
            }
            return s;
        }

        /// <summary>A mesh surface the way Godot's surface_get_arrays() returns it (GPU packing applied).</summary>
        static SourceArrays FromMesh(Mesh m, int surface, out PrimitiveType prim, out GMaterial mat)
        {
            var ss = m.GetSurfaces();
            var st = GpuPacking.AsStored(ss[surface]);
            prim = st.Primitive;
            mat = m.SurfaceGetMaterial(surface);
            var s = new SourceArrays { V = st.Vertices, N = st.Normals, T = st.Tangents, C = st.Colors, Uv = st.Uv, Uv2 = st.Uv2, Bones = st.Bones, Weights = st.Weights, Index = st.Indices };
            for (int c = 0; c < 4; c++)
            {
                if (st.Custom[c] == null) continue;
                if (st.CustomFormat[c] < CUSTOM_R_FLOAT) Err("Extracting Byte/Half formats is not supported");
                else s.Custom[c] = st.Custom[c];
            }
            return s;
        }

        static ulong CreateVertexArray(SourceArrays a, List<Vertex> ret)
        {
            ret.Clear();
            int vc = a.V?.Length ?? 0;
            if (vc == 0) return 0;
            ulong lformat = Mesh.ARRAY_FORMAT_VERTEX;
            if (a.N != null && a.N.Length > 0) lformat |= Mesh.ARRAY_FORMAT_NORMAL;
            if (a.T != null && a.T.Length > 0) lformat |= Mesh.ARRAY_FORMAT_TANGENT;
            if (a.C != null && a.C.Length > 0) lformat |= Mesh.ARRAY_FORMAT_COLOR;
            if (a.Uv != null && a.Uv.Length > 0) lformat |= Mesh.ARRAY_FORMAT_TEX_UV;
            if (a.Uv2 != null && a.Uv2.Length > 0) lformat |= Mesh.ARRAY_FORMAT_TEX_UV2;
            int wcount = 0;
            if (a.Bones != null && a.Bones.Length > 0 && a.Weights != null && a.Weights.Length > 0)
            {
                lformat |= Mesh.ARRAY_FORMAT_BONES | Mesh.ARRAY_FORMAT_WEIGHTS;
                wcount = a.Bones.Length / vc;
                if (wcount == 8) lformat |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS;
            }
            if (a.Weights != null && a.Weights.Length > 0) lformat |= Mesh.ARRAY_FORMAT_WEIGHTS;
            var cc = new int[4];
            for (int i = 0; i < 4; i++)
            {
                if (a.Custom[i] == null) continue;
                lformat |= CustomMask[i];
                int f = a.Custom[i].Length / vc;
                cc[i] = f;
                if (f == 1) lformat |= (ulong)CUSTOM_R_FLOAT << CustomShift[i];
                else if (f == 2) lformat |= (ulong)CUSTOM_RG_FLOAT << CustomShift[i];
                else if (f == 3) lformat |= (ulong)CUSTOM_RGB_FLOAT << CustomShift[i];
                else if (f == 4) lformat |= (ulong)CUSTOM_RGBA_FLOAT << CustomShift[i];
            }

            for (int i = 0; i < vc; i++)
            {
                var v = new Vertex
                {
                    Color = new Col(0f, 0f, 0f, 1f),
                    Custom0 = new Col(0f, 0f, 0f, 1f), Custom1 = new Col(0f, 0f, 0f, 1f), Custom2 = new Col(0f, 0f, 0f, 1f), Custom3 = new Col(0f, 0f, 0f, 1f),
                    Bones = Array.Empty<int>(),
                    Weights = Array.Empty<float>(),
                };
                v.Pos = a.V[i];
                if ((lformat & Mesh.ARRAY_FORMAT_NORMAL) != 0) v.Normal = a.N[i];
                if ((lformat & Mesh.ARRAY_FORMAT_TANGENT) != 0)
                {
                    v.Tangent = new Vec3(a.T[i * 4], a.T[i * 4 + 1], a.T[i * 4 + 2]);
                    float d = a.T[i * 4 + 3];
                    Vec3 b = v.Normal.Cross(v.Tangent).NormalizedChecked();
                    v.Binormal = new Vec3(b.x * d, b.y * d, b.z * d);
                }
                if ((lformat & Mesh.ARRAY_FORMAT_COLOR) != 0) v.Color = a.C[i];
                if ((lformat & Mesh.ARRAY_FORMAT_TEX_UV) != 0) v.Uv = a.Uv[i];
                if ((lformat & Mesh.ARRAY_FORMAT_TEX_UV2) != 0) v.Uv2 = a.Uv2[i];
                if ((lformat & Mesh.ARRAY_FORMAT_BONES) != 0)
                {
                    var b = new int[wcount];
                    for (int j = 0; j < wcount; j++) b[j] = a.Bones[i * wcount + j];
                    v.Bones = b;
                }
                if ((lformat & Mesh.ARRAY_FORMAT_WEIGHTS) != 0)
                {
                    var w = new float[wcount];
                    for (int j = 0; j < wcount; j++) w[j] = a.Weights[i * wcount + j];
                    v.Weights = w;
                }
                for (int j = 0; j < 4; j++)
                {
                    if ((lformat & CustomMask[j]) == 0) continue;
                    Col c = v.GetCustom(j);
                    float[] comp = { c.r, c.g, c.b, c.a };
                    for (int k = 0; k < cc[j]; k++) comp[k] = a.Custom[j][i * cc[j] + k];
                    v.SetCustom(j, new Col(comp[0], comp[1], comp[2], comp[3]));
                }
                ret.Add(v);
            }
            return lformat;
        }

        static ulong CreateList(SourceArrays a, List<Vertex> verts, List<int> idx)
        {
            ulong lformat = CreateVertexArray(a, verts);
            if (verts.Count == 0) { Err("Condition \"r_vertex->size() == 0\" is true."); return lformat; }
            idx.Clear();
            if (a.Index != null && a.Index.Length > 0)
            {
                lformat |= Mesh.ARRAY_FORMAT_INDEX;
                idx.AddRange(a.Index);
            }
            return lformat;
        }

        void CustomFormatsFromFormat()
        {
            for (int j = 0; j < 4; j++)
                if ((_format & CustomMask[j]) != 0) _lastCustomFormat[j] = (int)((_format >> CustomShift[j]) & 7);
        }

        public void CreateFromArrays(GArray arrays, PrimitiveType primitive = PrimitiveType.Triangles)
        {
            Clear();
            _primitive = primitive;
            _format = CreateList(FromGArray(arrays), _vertices, _indices);
            CustomFormatsFromFormat();
        }

        public void CreateFromTriangleArrays(GArray arrays) => CreateFromArrays(arrays, PrimitiveType.Triangles);

        public void CreateFrom(Mesh existing, int surface)
        {
            if (existing == null) { Err("First argument in SurfaceTool::create_from() must be a valid object of type Mesh"); return; }
            Clear();
            var src = FromMesh(existing, surface, out _primitive, out _material);
            _format = CreateList(src, _vertices, _indices);
            CustomFormatsFromFormat();
        }

        /// <summary>create_from_blend_shape: the C# Mesh keeps no blend shape names, so this is not available.</summary>
        public void CreateFromBlendShape(Mesh existing, int surface, string blendShape)
        {
            Err("SurfaceTool.create_from_blend_shape() is not supported by the port (meshes carry no blend shape names).");
        }

        public void AppendFrom(Mesh existing, int surface, Xform3 xform)
        {
            if (existing == null) { Err("First argument in SurfaceTool::append_from() must be a valid object of type Mesh"); return; }
            var src = FromMesh(existing, surface, out var prim, out _);
            if (_vertices.Count == 0)
            {
                _primitive = prim;
                _format = 0;
            }
            var nverts = new List<Vertex>();
            var nidx = new List<int>();
            ulong nformat = CreateList(src, nverts, nidx);
            _format |= nformat;
            CustomFormatsFromFormat();
            int vfrom = _vertices.Count;
            for (int k = 0; k < nverts.Count; k++)
            {
                Vertex v = nverts[k];
                v.Pos = xform.Xform(v.Pos);
                if ((nformat & Mesh.ARRAY_FORMAT_NORMAL) != 0) v.Normal = xform.basis.Xform(v.Normal);
                if ((nformat & Mesh.ARRAY_FORMAT_TANGENT) != 0)
                {
                    v.Tangent = xform.basis.Xform(v.Tangent);
                    v.Binormal = xform.basis.Xform(v.Binormal);
                }
                _vertices.Add(v);
            }
            foreach (int index in nidx) _indices.Add(index + vfrom);
            if (_indices.Count % 3 != 0) GD.PushWarning("SurfaceTool: Index array not a multiple of 3.");
        }

        // ------------------------------------------------------------------ generation
        /// <summary>generate_normals(flip): face normals (Plane of each triangle), summed per position within a smooth
        /// group and normalized; vertices in group UINT32_MAX (-1) keep their face's normal.</summary>
        public void GenerateNormals(bool flip = false)
        {
            if (_primitive != PrimitiveType.Triangles) { Err("Condition \"primitive != Mesh::PRIMITIVE_TRIANGLES\" is true."); return; }
            bool wasIndexed = _indices.Count > 0;
            Deindex();
            if (_vertices.Count % 3 != 0) { Err("Condition \"(vertex_array.size() % 3) != 0\" is true."); return; }

            var smooth = new Dictionary<SmoothKey, Vec3>(_vertices.Count);
            for (int vi = 0; vi < _vertices.Count; vi += 3)
            {
                Vec3 normal = !flip
                    ? new Plane(_vertices[vi].Pos, _vertices[vi + 1].Pos, _vertices[vi + 2].Pos).normal
                    : new Plane(_vertices[vi + 2].Pos, _vertices[vi + 1].Pos, _vertices[vi].Pos).normal;
                for (int i = 0; i < 3; i++)
                {
                    Vertex v = _vertices[vi + i];
                    if (v.SmoothGroup != uint.MaxValue)
                    {
                        var key = new SmoothKey(v.Pos, v.SmoothGroup);
                        if (!smooth.TryGetValue(key, out Vec3 lv)) smooth.Add(key, normal);
                        else smooth[key] = lv + normal;
                    }
                    else
                    {
                        v.Normal = normal;
                        _vertices[vi + i] = v;
                    }
                }
            }
            for (int k = 0; k < _vertices.Count; k++)
            {
                Vertex v = _vertices[k];
                if (v.SmoothGroup == uint.MaxValue) continue;
                v.Normal = smooth.TryGetValue(new SmoothKey(v.Pos, v.SmoothGroup), out Vec3 lv) ? lv.NormalizedChecked() : new Vec3(0f, 0f, 0f);
                _vertices[k] = v;
            }
            _format |= Mesh.ARRAY_FORMAT_NORMAL;
            if (wasIndexed) Index();
        }

        readonly struct SmoothKey : IEquatable<SmoothKey>
        {
            readonly Vec3 _p;
            readonly uint _g;
            public SmoothKey(Vec3 p, uint g) { _p = p; _g = g; }
            public bool Equals(SmoothKey o) => _p == o._p && _g == o._g;
            public override bool Equals(object o) => o is SmoothKey k && Equals(k);
            // (Godot's Vector3 hasher folds -0 into +0, so positions equal by == always share a bucket)
            static int B(float f) => f == 0f ? 0 : BitConverter.SingleToInt32Bits(f);
            public override int GetHashCode() => unchecked(((B(_p.x) * 31 + B(_p.y)) * 31 + B(_p.z)) * 31 + (int)_g);
        }

        /// <summary>generate_tangents(): mikktspace over the current triangles (UVs and normals required).</summary>
        public void GenerateTangents()
        {
            if ((_format & Mesh.ARRAY_FORMAT_TEX_UV) == 0) { Err("UVs are required to generate tangents."); return; }
            if ((_format & Mesh.ARRAY_FORMAT_NORMAL) == 0) { Err("Condition \"!(format & Mesh::ARRAY_FORMAT_NORMAL)\" is true."); return; }
            for (int k = 0; k < _vertices.Count; k++)
            {
                Vertex v = _vertices[k];
                v.Binormal = new Vec3(0f, 0f, 0f);
                v.Tangent = new Vec3(0f, 0f, 0f);
                _vertices[k] = v;
            }
            bool res = Mikktspace.GenTangSpaceDefault(new MikkSurface(_vertices, _indices));
            if (!res) { Err("Condition \"!res\" is true."); return; }
            _format |= Mesh.ARRAY_FORMAT_TANGENT;
        }

        sealed class MikkSurface : Mikktspace.IContext
        {
            readonly List<Vertex> _v;
            readonly List<int> _i;
            public MikkSurface(List<Vertex> v, List<int> i) { _v = v; _i = i; }

            public int GetNumFaces() => _i.Count > 0 ? _i.Count / 3 : _v.Count / 3;
            public int GetNumVerticesOfFace(int face) => 3;

            int Slot(int face, int vert)
            {
                if (_i.Count > 0)
                {
                    uint index = (uint)_i[face * 3 + vert];
                    return index < (uint)_v.Count ? (int)index : -1;
                }
                return face * 3 + vert;
            }

            public void GetPosition(float[] o, int face, int vert)
            {
                int s = Slot(face, vert);
                Vec3 p = s >= 0 ? _v[s].Pos : new Vec3(0f, 0f, 0f);
                o[0] = p.x; o[1] = p.y; o[2] = p.z;
            }

            public void GetNormal(float[] o, int face, int vert)
            {
                int s = Slot(face, vert);
                Vec3 p = s >= 0 ? _v[s].Normal : new Vec3(0f, 0f, 0f);
                o[0] = p.x; o[1] = p.y; o[2] = p.z;
            }

            public void GetTexCoord(float[] o, int face, int vert)
            {
                int s = Slot(face, vert);
                Vec2 p = s >= 0 ? _v[s].Uv : new Vec2(0f, 0f);
                o[0] = p.x; o[1] = p.y;
            }

            public void SetTSpace(float[] tangent, float[] bitangent, float magS, float magT, bool orientationPreserving, int face, int vert)
            {
                int s = Slot(face, vert);
                if (s < 0) return;
                Vertex v = _v[s];
                v.Tangent = new Vec3(tangent[0], tangent[1], tangent[2]);
                v.Binormal = new Vec3(-bitangent[0], -bitangent[1], -bitangent[2]);
                _v[s] = v;
            }
        }

        /// <summary>optimize_indices_for_cache(): needs meshoptimizer, which the port does not carry.</summary>
        public void OptimizeIndicesForCache() => Err("SurfaceTool.optimize_indices_for_cache() is not supported by the port (no meshoptimizer).");

        // ------------------------------------------------------------------ state
        public void SetMaterial(GMaterial m) => _material = m;
        public GMaterial GetMaterial() => _material;

        public void Clear()
        {
            _begun = false;
            _primitive = PrimitiveType.Lines;
            _format = 0;
            _lastBones = Array.Empty<int>();
            _lastWeights = Array.Empty<float>();
            _indices.Clear();
            _vertices.Clear();
            _material = null;
            _lastSmoothGroup = 0;
            for (int i = 0; i < 4; i++) _lastCustomFormat[i] = CUSTOM_MAX;
            _skinWeights = SKIN_4_WEIGHTS;
        }

        public void SetSkinWeightCount(int count)
        {
            if (_begun) { Err("Condition \"begun\" is true."); return; }
            _skinWeights = count;
        }

        public int GetSkinWeightCount() => _skinWeights;

        public void SetCustomFormat(int channel, int format)
        {
            if (channel < 0 || channel >= 4) { Err("Index p_channel_index out of bounds."); return; }
            if (!_begun) { Err("Condition \"!begun\" is true."); return; }
            if (format < 0 || format > CUSTOM_MAX) { Err("Index p_format out of bounds."); return; }
            _lastCustomFormat[channel] = format;
        }

        public int GetCustomFormat(int channel) => channel >= 0 && channel < 4 ? _lastCustomFormat[channel] : CUSTOM_MAX;
        public PrimitiveType GetPrimitiveType() => _primitive;

        public Aabb GetAabb()
        {
            if (_vertices.Count == 0) { Err("Condition \"vertex_array.is_empty()\" is true."); return new Aabb(); }
            Aabb aabb = new Aabb();
            for (int i = 0; i < _vertices.Count; i++)
            {
                if (i == 0) aabb.position = _vertices[i].Pos;
                else aabb = aabb.ExpandTo(_vertices[i].Pos);
            }
            return aabb;
        }
    }

    /// <summary>Morten S. Mikkelsen's mikktspace (thirdparty/misc/mikktspace.c), transcribed.</summary>
    public static class Mikktspace
    {
        public interface IContext
        {
            int GetNumFaces();
            int GetNumVerticesOfFace(int face);
            void GetPosition(float[] posOut, int face, int vert);
            void GetNormal(float[] normOut, int face, int vert);
            void GetTexCoord(float[] texcOut, int face, int vert);
            void SetTSpace(float[] tangent, float[] bitangent, float magS, float magT, bool orientationPreserving, int face, int vert);
        }

        const int INTERNAL_RND_SORT_SEED = 39871946;
        const int MARK_DEGENERATE = 1, QUAD_ONE_DEGEN_TRI = 2, GROUP_WITH_ANY = 4, ORIENT_PRESERVING = 8;
        const float FLT_MIN = 1.17549435e-38f;
        const int g_iCells = 2048;

        struct SVec3
        {
            public float x, y, z;
            public SVec3(float x, float y, float z) { this.x = x; this.y = y; this.z = z; }
        }

        static bool veq(SVec3 a, SVec3 b) => (a.x == b.x) && (a.y == b.y) && (a.z == b.z);
        static SVec3 vadd(SVec3 a, SVec3 b) => new SVec3(a.x + b.x, a.y + b.y, a.z + b.z);
        static SVec3 vsub(SVec3 a, SVec3 b) => new SVec3(a.x - b.x, a.y - b.y, a.z - b.z);
        static SVec3 vscale(float s, SVec3 v) => new SVec3(s * v.x, s * v.y, s * v.z);
        static float LengthSquared(SVec3 v) => v.x * v.x + v.y * v.y + v.z * v.z;
        static float Length(SVec3 v) => MathF.Sqrt(LengthSquared(v));
        static SVec3 Normalize(SVec3 v) => vscale(1 / Length(v), v);
        static float vdot(SVec3 a, SVec3 b) => a.x * b.x + a.y * b.y + a.z * b.z;
        static bool NotZero(float x) => MathF.Abs(x) > FLT_MIN;
        static bool VNotZero(SVec3 v) => NotZero(v.x) || NotZero(v.y) || NotZero(v.z);

        sealed class SGroup
        {
            public int iNrFaces;
            public int pFaceIndices; // offset into the group triangle buffer
            public int iVertexRepresentitive;
            public bool bOrientPreservering;
        }

        sealed class STriInfo
        {
            public readonly int[] FaceNeighbors = new int[3];
            public readonly int[] AssignedGroup = new int[3]; // group index, -1 = none
            public SVec3 vOs, vOt;
            public float fMagS, fMagT;
            public int iOrgFaceNumber;
            public int iFlag, iTSpacesOffs;
            public readonly byte[] vert_num = new byte[4];
        }

        struct STSpace
        {
            public SVec3 vOs;
            public float fMagS;
            public SVec3 vOt;
            public float fMagT;
            public int iCounter;
            public bool bOrient;
        }

        static int MakeIndex(int iFace, int iVert) => (iFace << 2) | (iVert & 0x3);
        static void IndexToData(out int piFace, out int piVert, int iIndexIn) { piVert = iIndexIn & 0x3; piFace = iIndexIn >> 2; }

        static STSpace AvgTSpace(ref STSpace pTS0, ref STSpace pTS1)
        {
            STSpace ts_res = default;
            if (pTS0.fMagS == pTS1.fMagS && pTS0.fMagT == pTS1.fMagT && veq(pTS0.vOs, pTS1.vOs) && veq(pTS0.vOt, pTS1.vOt))
            {
                ts_res.fMagS = pTS0.fMagS;
                ts_res.fMagT = pTS0.fMagT;
                ts_res.vOs = pTS0.vOs;
                ts_res.vOt = pTS0.vOt;
            }
            else
            {
                ts_res.fMagS = 0.5f * (pTS0.fMagS + pTS1.fMagS);
                ts_res.fMagT = 0.5f * (pTS0.fMagT + pTS1.fMagT);
                ts_res.vOs = vadd(pTS0.vOs, pTS1.vOs);
                ts_res.vOt = vadd(pTS0.vOt, pTS1.vOt);
                if (VNotZero(ts_res.vOs)) ts_res.vOs = Normalize(ts_res.vOs);
                if (VNotZero(ts_res.vOt)) ts_res.vOt = Normalize(ts_res.vOt);
            }
            return ts_res;
        }

        static SVec3 GetPosition(IContext c, int index)
        {
            IndexToData(out int iF, out int iI, index);
            var p = new float[3];
            c.GetPosition(p, iF, iI);
            return new SVec3(p[0], p[1], p[2]);
        }

        static SVec3 GetNormal(IContext c, int index)
        {
            IndexToData(out int iF, out int iI, index);
            var p = new float[3];
            c.GetNormal(p, iF, iI);
            return new SVec3(p[0], p[1], p[2]);
        }

        static SVec3 GetTexCoord(IContext c, int index)
        {
            IndexToData(out int iF, out int iI, index);
            var p = new float[2];
            c.GetTexCoord(p, iF, iI);
            return new SVec3(p[0], p[1], 1.0f);
        }

        public static bool GenTangSpaceDefault(IContext c) => GenTangSpace(c, 180.0f);

        public static bool GenTangSpace(IContext pContext, float fAngularThreshold)
        {
            int iNrTrianglesIn = 0, f, t, i;
            int iNrTSPaces, iTotTris, iDegenTriangles, iNrMaxGroups;
            int iNrActiveGroups, index;
            int iNrFaces = pContext.GetNumFaces();
            bool bRes;
            float fThresCos = (float)Math.Cos((fAngularThreshold * (float)Math.PI) / 180.0f);

            for (f = 0; f < iNrFaces; f++)
            {
                int verts = pContext.GetNumVerticesOfFace(f);
                if (verts == 3) ++iNrTrianglesIn;
                else if (verts == 4) iNrTrianglesIn += 2;
            }
            if (iNrTrianglesIn <= 0) return false;

            var piTriListIn = new int[3 * iNrTrianglesIn];
            var pTriInfos = new STriInfo[iNrTrianglesIn];
            for (t = 0; t < iNrTrianglesIn; t++) pTriInfos[t] = new STriInfo();

            iNrTSPaces = GenerateInitialVerticesIndexList(pTriInfos, piTriListIn, pContext, iNrTrianglesIn);
            GenerateSharedVerticesIndexList(piTriListIn, pContext, iNrTrianglesIn);

            iTotTris = iNrTrianglesIn;
            iDegenTriangles = 0;
            for (t = 0; t < iTotTris; t++)
            {
                int i0 = piTriListIn[t * 3 + 0], i1 = piTriListIn[t * 3 + 1], i2 = piTriListIn[t * 3 + 2];
                SVec3 p0 = GetPosition(pContext, i0), p1 = GetPosition(pContext, i1), p2 = GetPosition(pContext, i2);
                if (veq(p0, p1) || veq(p0, p2) || veq(p1, p2))
                {
                    pTriInfos[t].iFlag |= MARK_DEGENERATE;
                    ++iDegenTriangles;
                }
            }
            iNrTrianglesIn = iTotTris - iDegenTriangles;

            DegenPrologue(pTriInfos, piTriListIn, iNrTrianglesIn, iTotTris);
            InitTriInfo(pTriInfos, piTriListIn, pContext, iNrTrianglesIn);

            iNrMaxGroups = iNrTrianglesIn * 3;
            var pGroups = new SGroup[iNrMaxGroups];
            for (i = 0; i < iNrMaxGroups; i++) pGroups[i] = new SGroup();
            var piGroupTrianglesBuffer = new int[iNrTrianglesIn * 3];
            iNrActiveGroups = Build4RuleGroups(pTriInfos, pGroups, piGroupTrianglesBuffer, piTriListIn, iNrTrianglesIn);

            var psTspace = new STSpace[iNrTSPaces];
            for (t = 0; t < iNrTSPaces; t++)
            {
                psTspace[t].vOs = new SVec3(1.0f, 0.0f, 0.0f); psTspace[t].fMagS = 1.0f;
                psTspace[t].vOt = new SVec3(0.0f, 1.0f, 0.0f); psTspace[t].fMagT = 1.0f;
            }

            bRes = GenerateTSpaces(psTspace, pTriInfos, pGroups, piGroupTrianglesBuffer, iNrActiveGroups, piTriListIn, fThresCos, pContext);
            if (!bRes) return false;

            DegenEpilogue(psTspace, pTriInfos, piTriListIn, pContext, iNrTrianglesIn, iTotTris);

            index = 0;
            var tang = new float[3];
            var bitang = new float[3];
            for (f = 0; f < iNrFaces; f++)
            {
                int verts = pContext.GetNumVerticesOfFace(f);
                if (verts != 3 && verts != 4) continue;
                for (i = 0; i < verts; i++)
                {
                    STSpace pTSpace = psTspace[index];
                    tang[0] = pTSpace.vOs.x; tang[1] = pTSpace.vOs.y; tang[2] = pTSpace.vOs.z;
                    bitang[0] = pTSpace.vOt.x; bitang[1] = pTSpace.vOt.y; bitang[2] = pTSpace.vOt.z;
                    pContext.SetTSpace(tang, bitang, pTSpace.fMagS, pTSpace.fMagT, pTSpace.bOrient, f, i);
                    ++index;
                }
            }
            return true;
        }

        struct STmpVert
        {
            public float v0, v1, v2;
            public int index;
            public float this[int c] => c == 0 ? v0 : (c == 1 ? v1 : v2);
        }

        static int FindGridCell(float fMin, float fMax, float fVal)
        {
            float fIndex = g_iCells * ((fVal - fMin) / (fMax - fMin));
            int iIndex = float.IsNaN(fIndex) ? int.MinValue : (fIndex >= 2147483648f ? int.MinValue : (fIndex <= -2147483648f ? int.MinValue : (int)fIndex));
            return iIndex < g_iCells ? (iIndex >= 0 ? iIndex : 0) : (g_iCells - 1);
        }

        static void GenerateSharedVerticesIndexList(int[] piTriList_in_and_out, IContext pContext, int iNrTrianglesIn)
        {
            int i, iChannel, k, e;
            int iMaxCount;
            SVec3 vMin = GetPosition(pContext, 0), vMax = vMin, vDim;
            float fMin, fMax;
            for (i = 1; i < (iNrTrianglesIn * 3); i++)
            {
                int index = piTriList_in_and_out[i];
                SVec3 vP = GetPosition(pContext, index);
                if (vMin.x > vP.x) vMin.x = vP.x;
                else if (vMax.x < vP.x) vMax.x = vP.x;
                if (vMin.y > vP.y) vMin.y = vP.y;
                else if (vMax.y < vP.y) vMax.y = vP.y;
                if (vMin.z > vP.z) vMin.z = vP.z;
                else if (vMax.z < vP.z) vMax.z = vP.z;
            }

            vDim = vsub(vMax, vMin);
            iChannel = 0;
            fMin = vMin.x; fMax = vMax.x;
            if (vDim.y > vDim.x && vDim.y > vDim.z) { iChannel = 1; fMin = vMin.y; fMax = vMax.y; }
            else if (vDim.z > vDim.x) { iChannel = 2; fMin = vMin.z; fMax = vMax.z; }

            var piHashTable = new int[iNrTrianglesIn * 3];
            var piHashCount = new int[g_iCells];
            var piHashOffsets = new int[g_iCells];
            var piHashCount2 = new int[g_iCells];

            for (i = 0; i < (iNrTrianglesIn * 3); i++)
            {
                int index = piTriList_in_and_out[i];
                SVec3 vP = GetPosition(pContext, index);
                float fVal = iChannel == 0 ? vP.x : (iChannel == 1 ? vP.y : vP.z);
                int iCell = FindGridCell(fMin, fMax, fVal);
                ++piHashCount[iCell];
            }

            piHashOffsets[0] = 0;
            for (k = 1; k < g_iCells; k++) piHashOffsets[k] = piHashOffsets[k - 1] + piHashCount[k - 1];

            for (i = 0; i < (iNrTrianglesIn * 3); i++)
            {
                int index = piTriList_in_and_out[i];
                SVec3 vP = GetPosition(pContext, index);
                float fVal = iChannel == 0 ? vP.x : (iChannel == 1 ? vP.y : vP.z);
                int iCell = FindGridCell(fMin, fMax, fVal);
                piHashTable[piHashOffsets[iCell] + piHashCount2[iCell]] = i;
                ++piHashCount2[iCell];
            }

            iMaxCount = piHashCount[0];
            for (k = 1; k < g_iCells; k++) if (iMaxCount < piHashCount[k]) iMaxCount = piHashCount[k];
            var pTmpVert = new STmpVert[Math.Max(iMaxCount, 1)];

            for (k = 0; k < g_iCells; k++)
            {
                int tableOfs = piHashOffsets[k];
                int iEntries = piHashCount[k];
                if (iEntries < 2) continue;
                for (e = 0; e < iEntries; e++)
                {
                    int ii = piHashTable[tableOfs + e];
                    SVec3 vP = GetPosition(pContext, piTriList_in_and_out[ii]);
                    pTmpVert[e].v0 = vP.x; pTmpVert[e].v1 = vP.y; pTmpVert[e].v2 = vP.z; pTmpVert[e].index = ii;
                }
                MergeVertsFast(piTriList_in_and_out, pTmpVert, pContext, 0, iEntries - 1);
            }
        }

        static void MergeVertsFast(int[] piTriList_in_and_out, STmpVert[] pTmpVert, IContext pContext, int iL_in, int iR_in)
        {
            int c, l, channel;
            var fvMin = new float[3];
            var fvMax = new float[3];
            float dx, dy, dz, fSep;
            for (c = 0; c < 3; c++) { fvMin[c] = pTmpVert[iL_in][c]; fvMax[c] = fvMin[c]; }
            for (l = (iL_in + 1); l <= iR_in; l++)
                for (c = 0; c < 3; c++)
                    if (fvMin[c] > pTmpVert[l][c]) fvMin[c] = pTmpVert[l][c];
                    else if (fvMax[c] < pTmpVert[l][c]) fvMax[c] = pTmpVert[l][c];

            dx = fvMax[0] - fvMin[0];
            dy = fvMax[1] - fvMin[1];
            dz = fvMax[2] - fvMin[2];

            channel = 0;
            if (dy > dx && dy > dz) channel = 1;
            else if (dz > dx) channel = 2;

            fSep = 0.5f * (fvMax[channel] + fvMin[channel]);

            if (fSep >= fvMax[channel] || fSep <= fvMin[channel])
            {
                for (l = iL_in; l <= iR_in; l++)
                {
                    int i = pTmpVert[l].index;
                    int index = piTriList_in_and_out[i];
                    SVec3 vP = GetPosition(pContext, index);
                    SVec3 vN = GetNormal(pContext, index);
                    SVec3 vT = GetTexCoord(pContext, index);

                    bool bNotFound = true;
                    int l2 = iL_in, i2rec = -1;
                    while (l2 < l && bNotFound)
                    {
                        int i2 = pTmpVert[l2].index;
                        int index2 = piTriList_in_and_out[i2];
                        SVec3 vP2 = GetPosition(pContext, index2);
                        SVec3 vN2 = GetNormal(pContext, index2);
                        SVec3 vT2 = GetTexCoord(pContext, index2);
                        i2rec = i2;
                        if (vP.x == vP2.x && vP.y == vP2.y && vP.z == vP2.z &&
                            vN.x == vN2.x && vN.y == vN2.y && vN.z == vN2.z &&
                            vT.x == vT2.x && vT.y == vT2.y && vT.z == vT2.z)
                            bNotFound = false;
                        else
                            ++l2;
                    }
                    if (!bNotFound) piTriList_in_and_out[i] = piTriList_in_and_out[i2rec];
                }
            }
            else
            {
                int iL = iL_in, iR = iR_in;
                while (iL < iR)
                {
                    bool bReadyLeftSwap = false, bReadyRightSwap = false;
                    while ((!bReadyLeftSwap) && iL < iR)
                    {
                        bReadyLeftSwap = !(pTmpVert[iL][channel] < fSep);
                        if (!bReadyLeftSwap) ++iL;
                    }
                    while ((!bReadyRightSwap) && iL < iR)
                    {
                        bReadyRightSwap = pTmpVert[iR][channel] < fSep;
                        if (!bReadyRightSwap) --iR;
                    }
                    if (bReadyLeftSwap && bReadyRightSwap)
                    {
                        STmpVert sTmp = pTmpVert[iL];
                        pTmpVert[iL] = pTmpVert[iR];
                        pTmpVert[iR] = sTmp;
                        ++iL; --iR;
                    }
                }
                if (iL == iR)
                {
                    bool bReadyRightSwap = pTmpVert[iR][channel] < fSep;
                    if (bReadyRightSwap) ++iL;
                    else --iR;
                }
                if (iL_in < iR) MergeVertsFast(piTriList_in_and_out, pTmpVert, pContext, iL_in, iR);
                if (iL < iR_in) MergeVertsFast(piTriList_in_and_out, pTmpVert, pContext, iL, iR_in);
            }
        }

        static int GenerateInitialVerticesIndexList(STriInfo[] pTriInfos, int[] piTriList_out, IContext pContext, int iNrTrianglesIn)
        {
            int iTSpacesOffs = 0, f, t;
            int iDstTriIndex = 0;
            for (f = 0; f < pContext.GetNumFaces(); f++)
            {
                int verts = pContext.GetNumVerticesOfFace(f);
                if (verts != 3 && verts != 4) continue;

                pTriInfos[iDstTriIndex].iOrgFaceNumber = f;
                pTriInfos[iDstTriIndex].iTSpacesOffs = iTSpacesOffs;

                if (verts == 3)
                {
                    byte[] pVerts = pTriInfos[iDstTriIndex].vert_num;
                    pVerts[0] = 0; pVerts[1] = 1; pVerts[2] = 2;
                    piTriList_out[iDstTriIndex * 3 + 0] = MakeIndex(f, 0);
                    piTriList_out[iDstTriIndex * 3 + 1] = MakeIndex(f, 1);
                    piTriList_out[iDstTriIndex * 3 + 2] = MakeIndex(f, 2);
                    ++iDstTriIndex;
                }
                else
                {
                    pTriInfos[iDstTriIndex + 1].iOrgFaceNumber = f;
                    pTriInfos[iDstTriIndex + 1].iTSpacesOffs = iTSpacesOffs;
                    int i0 = MakeIndex(f, 0), i1 = MakeIndex(f, 1), i2 = MakeIndex(f, 2), i3 = MakeIndex(f, 3);
                    SVec3 T0 = GetTexCoord(pContext, i0), T1 = GetTexCoord(pContext, i1), T2 = GetTexCoord(pContext, i2), T3 = GetTexCoord(pContext, i3);
                    float distSQ_02 = LengthSquared(vsub(T2, T0));
                    float distSQ_13 = LengthSquared(vsub(T3, T1));
                    bool bQuadDiagIs_02;
                    if (distSQ_02 < distSQ_13) bQuadDiagIs_02 = true;
                    else if (distSQ_13 < distSQ_02) bQuadDiagIs_02 = false;
                    else
                    {
                        SVec3 P0 = GetPosition(pContext, i0), P1 = GetPosition(pContext, i1), P2 = GetPosition(pContext, i2), P3 = GetPosition(pContext, i3);
                        float d02 = LengthSquared(vsub(P2, P0));
                        float d13 = LengthSquared(vsub(P3, P1));
                        bQuadDiagIs_02 = d13 < d02 ? false : true;
                    }

                    if (bQuadDiagIs_02)
                    {
                        byte[] pA = pTriInfos[iDstTriIndex].vert_num;
                        pA[0] = 0; pA[1] = 1; pA[2] = 2;
                        piTriList_out[iDstTriIndex * 3 + 0] = i0;
                        piTriList_out[iDstTriIndex * 3 + 1] = i1;
                        piTriList_out[iDstTriIndex * 3 + 2] = i2;
                        ++iDstTriIndex;
                        byte[] pB = pTriInfos[iDstTriIndex].vert_num;
                        pB[0] = 0; pB[1] = 2; pB[2] = 3;
                        piTriList_out[iDstTriIndex * 3 + 0] = i0;
                        piTriList_out[iDstTriIndex * 3 + 1] = i2;
                        piTriList_out[iDstTriIndex * 3 + 2] = i3;
                        ++iDstTriIndex;
                    }
                    else
                    {
                        byte[] pA = pTriInfos[iDstTriIndex].vert_num;
                        pA[0] = 0; pA[1] = 1; pA[2] = 3;
                        piTriList_out[iDstTriIndex * 3 + 0] = i0;
                        piTriList_out[iDstTriIndex * 3 + 1] = i1;
                        piTriList_out[iDstTriIndex * 3 + 2] = i3;
                        ++iDstTriIndex;
                        byte[] pB = pTriInfos[iDstTriIndex].vert_num;
                        pB[0] = 1; pB[1] = 2; pB[2] = 3;
                        piTriList_out[iDstTriIndex * 3 + 0] = i1;
                        piTriList_out[iDstTriIndex * 3 + 1] = i2;
                        piTriList_out[iDstTriIndex * 3 + 2] = i3;
                        ++iDstTriIndex;
                    }
                }
                iTSpacesOffs += verts;
            }
            for (t = 0; t < iNrTrianglesIn; t++) pTriInfos[t].iFlag = 0;
            return iTSpacesOffs;
        }

        static float CalcTexArea(IContext pContext, int[] indices, int ofs)
        {
            SVec3 t1 = GetTexCoord(pContext, indices[ofs]);
            SVec3 t2 = GetTexCoord(pContext, indices[ofs + 1]);
            SVec3 t3 = GetTexCoord(pContext, indices[ofs + 2]);
            float t21x = t2.x - t1.x, t21y = t2.y - t1.y, t31x = t3.x - t1.x, t31y = t3.y - t1.y;
            float fSignedAreaSTx2 = t21x * t31y - t21y * t31x;
            return fSignedAreaSTx2 < 0 ? (-fSignedAreaSTx2) : fSignedAreaSTx2;
        }

        static void InitTriInfo(STriInfo[] pTriInfos, int[] piTriListIn, IContext pContext, int iNrTrianglesIn)
        {
            int f, i, t = 0;
            for (f = 0; f < iNrTrianglesIn; f++)
                for (i = 0; i < 3; i++)
                {
                    pTriInfos[f].FaceNeighbors[i] = -1;
                    pTriInfos[f].AssignedGroup[i] = -1;
                    pTriInfos[f].vOs = new SVec3(0f, 0f, 0f);
                    pTriInfos[f].vOt = new SVec3(0f, 0f, 0f);
                    pTriInfos[f].fMagS = 0;
                    pTriInfos[f].fMagT = 0;
                    pTriInfos[f].iFlag |= GROUP_WITH_ANY;
                }

            for (f = 0; f < iNrTrianglesIn; f++)
            {
                SVec3 v1 = GetPosition(pContext, piTriListIn[f * 3 + 0]);
                SVec3 v2 = GetPosition(pContext, piTriListIn[f * 3 + 1]);
                SVec3 v3 = GetPosition(pContext, piTriListIn[f * 3 + 2]);
                SVec3 t1 = GetTexCoord(pContext, piTriListIn[f * 3 + 0]);
                SVec3 t2 = GetTexCoord(pContext, piTriListIn[f * 3 + 1]);
                SVec3 t3 = GetTexCoord(pContext, piTriListIn[f * 3 + 2]);

                float t21x = t2.x - t1.x, t21y = t2.y - t1.y, t31x = t3.x - t1.x, t31y = t3.y - t1.y;
                SVec3 d1 = vsub(v2, v1);
                SVec3 d2 = vsub(v3, v1);

                float fSignedAreaSTx2 = t21x * t31y - t21y * t31x;
                SVec3 vOs = vsub(vscale(t31y, d1), vscale(t21y, d2));
                SVec3 vOt = vadd(vscale(-t31x, d1), vscale(t21x, d2));

                pTriInfos[f].iFlag |= (fSignedAreaSTx2 > 0 ? ORIENT_PRESERVING : 0);

                if (NotZero(fSignedAreaSTx2))
                {
                    float fAbsArea = MathF.Abs(fSignedAreaSTx2);
                    float fLenOs = Length(vOs);
                    float fLenOt = Length(vOt);
                    float fS = (pTriInfos[f].iFlag & ORIENT_PRESERVING) == 0 ? (-1.0f) : 1.0f;
                    if (NotZero(fLenOs)) pTriInfos[f].vOs = vscale(fS / fLenOs, vOs);
                    if (NotZero(fLenOt)) pTriInfos[f].vOt = vscale(fS / fLenOt, vOt);
                    pTriInfos[f].fMagS = fLenOs / fAbsArea;
                    pTriInfos[f].fMagT = fLenOt / fAbsArea;
                    if (NotZero(pTriInfos[f].fMagS) && NotZero(pTriInfos[f].fMagT)) pTriInfos[f].iFlag &= (~GROUP_WITH_ANY);
                }
            }

            while (t < (iNrTrianglesIn - 1))
            {
                int iFO_a = pTriInfos[t].iOrgFaceNumber;
                int iFO_b = pTriInfos[t + 1].iOrgFaceNumber;
                if (iFO_a == iFO_b)
                {
                    bool bIsDeg_a = (pTriInfos[t].iFlag & MARK_DEGENERATE) != 0;
                    bool bIsDeg_b = (pTriInfos[t + 1].iFlag & MARK_DEGENERATE) != 0;
                    if (!(bIsDeg_a || bIsDeg_b))
                    {
                        bool bOrientA = (pTriInfos[t].iFlag & ORIENT_PRESERVING) != 0;
                        bool bOrientB = (pTriInfos[t + 1].iFlag & ORIENT_PRESERVING) != 0;
                        if (bOrientA != bOrientB)
                        {
                            bool bChooseOrientFirstTri = false;
                            if ((pTriInfos[t + 1].iFlag & GROUP_WITH_ANY) != 0) bChooseOrientFirstTri = true;
                            else if (CalcTexArea(pContext, piTriListIn, t * 3) >= CalcTexArea(pContext, piTriListIn, (t + 1) * 3)) bChooseOrientFirstTri = true;
                            int t0 = bChooseOrientFirstTri ? t : (t + 1);
                            int t1 = bChooseOrientFirstTri ? (t + 1) : t;
                            pTriInfos[t1].iFlag &= (~ORIENT_PRESERVING);
                            pTriInfos[t1].iFlag |= (pTriInfos[t0].iFlag & ORIENT_PRESERVING);
                        }
                    }
                    t += 2;
                }
                else ++t;
            }

            var pEdges = new SEdge[iNrTrianglesIn * 3];
            BuildNeighborsFast(pTriInfos, pEdges, piTriListIn, iNrTrianglesIn);
        }

        static int Build4RuleGroups(STriInfo[] pTriInfos, SGroup[] pGroups, int[] piGroupTrianglesBuffer, int[] piTriListIn, int iNrTrianglesIn)
        {
            int iNrActiveGroups = 0;
            int iOffset = 0, f, i;
            for (f = 0; f < iNrTrianglesIn; f++)
            {
                for (i = 0; i < 3; i++)
                {
                    if ((pTriInfos[f].iFlag & GROUP_WITH_ANY) == 0 && pTriInfos[f].AssignedGroup[i] == -1)
                    {
                        int vert_index = piTriListIn[f * 3 + i];
                        int g = iNrActiveGroups;
                        pTriInfos[f].AssignedGroup[i] = g;
                        SGroup grp = pGroups[g];
                        grp.iVertexRepresentitive = vert_index;
                        grp.bOrientPreservering = (pTriInfos[f].iFlag & ORIENT_PRESERVING) != 0;
                        grp.iNrFaces = 0;
                        grp.pFaceIndices = iOffset;
                        ++iNrActiveGroups;

                        AddTriToGroup(piGroupTrianglesBuffer, grp, f);
                        int neigh_indexL = pTriInfos[f].FaceNeighbors[i];
                        int neigh_indexR = pTriInfos[f].FaceNeighbors[i > 0 ? (i - 1) : 2];
                        if (neigh_indexL >= 0) AssignRecur(piTriListIn, pTriInfos, neigh_indexL, pGroups, g, piGroupTrianglesBuffer);
                        if (neigh_indexR >= 0) AssignRecur(piTriListIn, pTriInfos, neigh_indexR, pGroups, g, piGroupTrianglesBuffer);
                        iOffset += grp.iNrFaces;
                    }
                }
            }
            return iNrActiveGroups;
        }

        static void AddTriToGroup(int[] buffer, SGroup pGroup, int iTriIndex)
        {
            buffer[pGroup.pFaceIndices + pGroup.iNrFaces] = iTriIndex;
            ++pGroup.iNrFaces;
        }

        static bool AssignRecur(int[] piTriListIn, STriInfo[] psTriInfos, int iMyTriIndex, SGroup[] groups, int g, int[] buffer)
        {
            STriInfo pMyTriInfo = psTriInfos[iMyTriIndex];
            SGroup pGroup = groups[g];
            int iVertRep = pGroup.iVertexRepresentitive;
            int pv = 3 * iMyTriIndex;
            int i = -1;
            if (piTriListIn[pv] == iVertRep) i = 0;
            else if (piTriListIn[pv + 1] == iVertRep) i = 1;
            else if (piTriListIn[pv + 2] == iVertRep) i = 2;

            if (pMyTriInfo.AssignedGroup[i] == g) return true;
            else if (pMyTriInfo.AssignedGroup[i] != -1) return false;
            if ((pMyTriInfo.iFlag & GROUP_WITH_ANY) != 0)
            {
                if (pMyTriInfo.AssignedGroup[0] == -1 && pMyTriInfo.AssignedGroup[1] == -1 && pMyTriInfo.AssignedGroup[2] == -1)
                {
                    pMyTriInfo.iFlag &= (~ORIENT_PRESERVING);
                    pMyTriInfo.iFlag |= (pGroup.bOrientPreservering ? ORIENT_PRESERVING : 0);
                }
            }
            {
                bool bOrient = (pMyTriInfo.iFlag & ORIENT_PRESERVING) != 0;
                if (bOrient != pGroup.bOrientPreservering) return false;
            }

            AddTriToGroup(buffer, pGroup, iMyTriIndex);
            pMyTriInfo.AssignedGroup[i] = g;
            {
                int neigh_indexL = pMyTriInfo.FaceNeighbors[i];
                int neigh_indexR = pMyTriInfo.FaceNeighbors[i > 0 ? (i - 1) : 2];
                if (neigh_indexL >= 0) AssignRecur(piTriListIn, psTriInfos, neigh_indexL, groups, g, buffer);
                if (neigh_indexR >= 0) AssignRecur(piTriListIn, psTriInfos, neigh_indexR, groups, g, buffer);
            }
            return true;
        }

        static bool GenerateTSpaces(STSpace[] psTspace, STriInfo[] pTriInfos, SGroup[] pGroups, int[] groupBuffer, int iNrActiveGroups,
            int[] piTriListIn, float fThresCos, IContext pContext)
        {
            int iMaxNrFaces = 0, g, i;
            for (g = 0; g < iNrActiveGroups; g++)
                if (iMaxNrFaces < pGroups[g].iNrFaces) iMaxNrFaces = pGroups[g].iNrFaces;
            if (iMaxNrFaces == 0) return true;

            var pSubGroupTspace = new STSpace[iMaxNrFaces];
            var pUniSubGroups = new int[iMaxNrFaces][];
            var pTmpMembers = new int[iMaxNrFaces];

            for (g = 0; g < iNrActiveGroups; g++)
            {
                SGroup pGroup = pGroups[g];
                int iUniqueSubGroups = 0;

                for (i = 0; i < pGroup.iNrFaces; i++)
                {
                    int f = groupBuffer[pGroup.pFaceIndices + i];
                    int index = -1, iVertIndex, iOF_1, iMembers, j, l;
                    bool bFound;
                    SVec3 n, vOs, vOt;
                    if (pTriInfos[f].AssignedGroup[0] == g) index = 0;
                    else if (pTriInfos[f].AssignedGroup[1] == g) index = 1;
                    else if (pTriInfos[f].AssignedGroup[2] == g) index = 2;

                    iVertIndex = piTriListIn[f * 3 + index];
                    n = GetNormal(pContext, iVertIndex);

                    vOs = vsub(pTriInfos[f].vOs, vscale(vdot(n, pTriInfos[f].vOs), n));
                    vOt = vsub(pTriInfos[f].vOt, vscale(vdot(n, pTriInfos[f].vOt), n));
                    if (VNotZero(vOs)) vOs = Normalize(vOs);
                    if (VNotZero(vOt)) vOt = Normalize(vOt);

                    iOF_1 = pTriInfos[f].iOrgFaceNumber;
                    iMembers = 0;
                    for (j = 0; j < pGroup.iNrFaces; j++)
                    {
                        int t = groupBuffer[pGroup.pFaceIndices + j];
                        int iOF_2 = pTriInfos[t].iOrgFaceNumber;
                        SVec3 vOs2 = vsub(pTriInfos[t].vOs, vscale(vdot(n, pTriInfos[t].vOs), n));
                        SVec3 vOt2 = vsub(pTriInfos[t].vOt, vscale(vdot(n, pTriInfos[t].vOt), n));
                        if (VNotZero(vOs2)) vOs2 = Normalize(vOs2);
                        if (VNotZero(vOt2)) vOt2 = Normalize(vOt2);
                        {
                            bool bAny = ((pTriInfos[f].iFlag | pTriInfos[t].iFlag) & GROUP_WITH_ANY) != 0;
                            bool bSameOrgFace = iOF_1 == iOF_2;
                            float fCosS = vdot(vOs, vOs2);
                            float fCosT = vdot(vOt, vOt2);
                            if (bAny || bSameOrgFace || (fCosS > fThresCos && fCosT > fThresCos)) pTmpMembers[iMembers++] = t;
                        }
                    }

                    if (iMembers > 1)
                    {
                        uint uSeed = INTERNAL_RND_SORT_SEED;
                        QuickSort(pTmpMembers, 0, iMembers - 1, uSeed);
                    }

                    bFound = false;
                    l = 0;
                    while (l < iUniqueSubGroups && !bFound)
                    {
                        bFound = CompareSubGroups(pTmpMembers, iMembers, pUniSubGroups[l]);
                        if (!bFound) ++l;
                    }

                    if (!bFound)
                    {
                        var pIndices = new int[iMembers];
                        Array.Copy(pTmpMembers, pIndices, iMembers);
                        pUniSubGroups[iUniqueSubGroups] = pIndices;
                        pSubGroupTspace[iUniqueSubGroups] = EvalTspace(pIndices, iMembers, piTriListIn, pTriInfos, pContext, pGroup.iVertexRepresentitive);
                        ++iUniqueSubGroups;
                    }

                    {
                        int iOffs = pTriInfos[f].iTSpacesOffs;
                        int iVert = pTriInfos[f].vert_num[index];
                        ref STSpace pTS_out = ref psTspace[iOffs + iVert];
                        if (pTS_out.iCounter == 1)
                        {
                            pTS_out = AvgTSpace(ref pTS_out, ref pSubGroupTspace[l]);
                            pTS_out.iCounter = 2;
                            pTS_out.bOrient = pGroup.bOrientPreservering;
                        }
                        else
                        {
                            pTS_out = pSubGroupTspace[l];
                            pTS_out.iCounter = 1;
                            pTS_out.bOrient = pGroup.bOrientPreservering;
                        }
                    }
                }
            }
            return true;
        }

        static STSpace EvalTspace(int[] face_indices, int iFaces, int[] piTriListIn, STriInfo[] pTriInfos, IContext pContext, int iVertexRepresentitive)
        {
            STSpace res = default;
            float fAngleSum = 0;
            int face;
            res.vOs = new SVec3(0f, 0f, 0f);
            res.vOt = new SVec3(0f, 0f, 0f);
            res.fMagS = 0; res.fMagT = 0;

            for (face = 0; face < iFaces; face++)
            {
                int f = face_indices[face];
                if ((pTriInfos[f].iFlag & GROUP_WITH_ANY) == 0)
                {
                    SVec3 n, vOs, vOt, p0, p1, p2, v1, v2;
                    float fCos, fAngle, fMagS, fMagT;
                    int i = -1, index, i0, i1, i2;
                    if (piTriListIn[3 * f + 0] == iVertexRepresentitive) i = 0;
                    else if (piTriListIn[3 * f + 1] == iVertexRepresentitive) i = 1;
                    else if (piTriListIn[3 * f + 2] == iVertexRepresentitive) i = 2;

                    index = piTriListIn[3 * f + i];
                    n = GetNormal(pContext, index);
                    vOs = vsub(pTriInfos[f].vOs, vscale(vdot(n, pTriInfos[f].vOs), n));
                    vOt = vsub(pTriInfos[f].vOt, vscale(vdot(n, pTriInfos[f].vOt), n));
                    if (VNotZero(vOs)) vOs = Normalize(vOs);
                    if (VNotZero(vOt)) vOt = Normalize(vOt);

                    i2 = piTriListIn[3 * f + (i < 2 ? (i + 1) : 0)];
                    i1 = piTriListIn[3 * f + i];
                    i0 = piTriListIn[3 * f + (i > 0 ? (i - 1) : 2)];

                    p0 = GetPosition(pContext, i0);
                    p1 = GetPosition(pContext, i1);
                    p2 = GetPosition(pContext, i2);
                    v1 = vsub(p0, p1);
                    v2 = vsub(p2, p1);

                    v1 = vsub(v1, vscale(vdot(n, v1), n)); if (VNotZero(v1)) v1 = Normalize(v1);
                    v2 = vsub(v2, vscale(vdot(n, v2), n)); if (VNotZero(v2)) v2 = Normalize(v2);

                    fCos = vdot(v1, v2); fCos = fCos > 1 ? 1 : (fCos < (-1) ? (-1) : fCos);
                    fAngle = (float)Math.Acos(fCos);
                    fMagS = pTriInfos[f].fMagS;
                    fMagT = pTriInfos[f].fMagT;

                    res.vOs = vadd(res.vOs, vscale(fAngle, vOs));
                    res.vOt = vadd(res.vOt, vscale(fAngle, vOt));
                    res.fMagS += (fAngle * fMagS);
                    res.fMagT += (fAngle * fMagT);
                    fAngleSum += fAngle;
                }
            }

            if (VNotZero(res.vOs)) res.vOs = Normalize(res.vOs);
            if (VNotZero(res.vOt)) res.vOt = Normalize(res.vOt);
            if (fAngleSum > 0)
            {
                res.fMagS /= fAngleSum;
                res.fMagT /= fAngleSum;
            }
            return res;
        }

        static bool CompareSubGroups(int[] members1, int n1, int[] members2)
        {
            bool bStillSame = true;
            int i = 0;
            if (n1 != members2.Length) return false;
            while (i < n1 && bStillSame)
            {
                bStillSame = members1[i] == members2[i];
                if (bStillSame) ++i;
            }
            return bStillSame;
        }

        static void QuickSort(int[] pSortBuffer, int iLeft, int iRight, uint uSeed)
        {
            int iL, iR, n, index, iMid, iTmp;
            uint t = uSeed & 31;
            t = (uSeed << (int)t) | (uSeed >> (int)(32 - t));
            uSeed = uSeed + t + 3;

            iL = iLeft; iR = iRight;
            n = (iR - iL) + 1;
            index = (int)(uSeed % (uint)n);
            iMid = pSortBuffer[index + iL];

            do
            {
                while (pSortBuffer[iL] < iMid) ++iL;
                while (pSortBuffer[iR] > iMid) --iR;
                if (iL <= iR)
                {
                    iTmp = pSortBuffer[iL];
                    pSortBuffer[iL] = pSortBuffer[iR];
                    pSortBuffer[iR] = iTmp;
                    ++iL; --iR;
                }
            }
            while (iL <= iR);

            if (iLeft < iR) QuickSort(pSortBuffer, iLeft, iR, uSeed);
            if (iL < iRight) QuickSort(pSortBuffer, iL, iRight, uSeed);
        }

        struct SEdge
        {
            public int i0, i1, f;
            public int this[int c] => c == 0 ? i0 : (c == 1 ? i1 : f);
        }

        static void BuildNeighborsFast(STriInfo[] pTriInfos, SEdge[] pEdges, int[] piTriListIn, int iNrTrianglesIn)
        {
            uint uSeed = INTERNAL_RND_SORT_SEED;
            int iEntries, iCurStartIndex, f, i;
            for (f = 0; f < iNrTrianglesIn; f++)
                for (i = 0; i < 3; i++)
                {
                    int i0 = piTriListIn[f * 3 + i];
                    int i1 = piTriListIn[f * 3 + (i < 2 ? (i + 1) : 0)];
                    pEdges[f * 3 + i].i0 = i0 < i1 ? i0 : i1;
                    pEdges[f * 3 + i].i1 = !(i0 < i1) ? i0 : i1;
                    pEdges[f * 3 + i].f = f;
                }

            QuickSortEdges(pEdges, 0, iNrTrianglesIn * 3 - 1, 0, uSeed);

            iEntries = iNrTrianglesIn * 3;
            iCurStartIndex = 0;
            for (i = 1; i < iEntries; i++)
            {
                if (pEdges[iCurStartIndex].i0 != pEdges[i].i0)
                {
                    int iL = iCurStartIndex;
                    int iR = i - 1;
                    iCurStartIndex = i;
                    QuickSortEdges(pEdges, iL, iR, 1, uSeed);
                }
            }

            iCurStartIndex = 0;
            for (i = 1; i < iEntries; i++)
            {
                if (pEdges[iCurStartIndex].i0 != pEdges[i].i0 || pEdges[iCurStartIndex].i1 != pEdges[i].i1)
                {
                    int iL = iCurStartIndex;
                    int iR = i - 1;
                    iCurStartIndex = i;
                    QuickSortEdges(pEdges, iL, iR, 2, uSeed);
                }
            }

            for (i = 0; i < iEntries; i++)
            {
                int i0 = pEdges[i].i0;
                int i1 = pEdges[i].i1;
                int f2 = pEdges[i].f;
                bool bUnassigned_A;
                int i0_A, i1_A;
                int edgenum_A, edgenum_B = 0;
                GetEdge(out i0_A, out i1_A, out edgenum_A, piTriListIn, f2 * 3, i0, i1);
                bUnassigned_A = pTriInfos[f2].FaceNeighbors[edgenum_A] == -1;

                if (bUnassigned_A)
                {
                    int j = i + 1, t;
                    bool bNotFound = true;
                    while (j < iEntries && i0 == pEdges[j].i0 && i1 == pEdges[j].i1 && bNotFound)
                    {
                        bool bUnassigned_B;
                        int i0_B, i1_B;
                        t = pEdges[j].f;
                        GetEdge(out i1_B, out i0_B, out edgenum_B, piTriListIn, t * 3, pEdges[j].i0, pEdges[j].i1);
                        bUnassigned_B = pTriInfos[t].FaceNeighbors[edgenum_B] == -1;
                        if (i0_A == i0_B && i1_A == i1_B && bUnassigned_B) bNotFound = false;
                        else ++j;
                    }

                    if (!bNotFound)
                    {
                        int t2 = pEdges[j].f;
                        pTriInfos[f2].FaceNeighbors[edgenum_A] = t2;
                        pTriInfos[t2].FaceNeighbors[edgenum_B] = f2;
                    }
                }
            }
        }

        static void QuickSortEdges(SEdge[] pSortBuffer, int iLeft, int iRight, int channel, uint uSeed)
        {
            uint t;
            int iL, iR, n, index, iMid;
            SEdge sTmp;
            int iElems = iRight - iLeft + 1;
            if (iElems < 2) return;
            else if (iElems == 2)
            {
                if (pSortBuffer[iLeft][channel] > pSortBuffer[iRight][channel])
                {
                    sTmp = pSortBuffer[iLeft];
                    pSortBuffer[iLeft] = pSortBuffer[iRight];
                    pSortBuffer[iRight] = sTmp;
                }
                return;
            }

            t = uSeed & 31;
            t = (uSeed << (int)t) | (uSeed >> (int)(32 - t));
            uSeed = uSeed + t + 3;

            iL = iLeft; iR = iRight;
            n = (iR - iL) + 1;
            index = (int)(uSeed % (uint)n);
            iMid = pSortBuffer[index + iL][channel];

            do
            {
                while (pSortBuffer[iL][channel] < iMid) ++iL;
                while (pSortBuffer[iR][channel] > iMid) --iR;
                if (iL <= iR)
                {
                    sTmp = pSortBuffer[iL];
                    pSortBuffer[iL] = pSortBuffer[iR];
                    pSortBuffer[iR] = sTmp;
                    ++iL; --iR;
                }
            }
            while (iL <= iR);

            if (iLeft < iR) QuickSortEdges(pSortBuffer, iLeft, iR, channel, uSeed);
            if (iL < iRight) QuickSortEdges(pSortBuffer, iL, iRight, channel, uSeed);
        }

        static void GetEdge(out int i0_out, out int i1_out, out int edgenum_out, int[] indices, int ofs, int i0_in, int i1_in)
        {
            if (indices[ofs] == i0_in || indices[ofs] == i1_in)
            {
                if (indices[ofs + 1] == i0_in || indices[ofs + 1] == i1_in)
                {
                    edgenum_out = 0;
                    i0_out = indices[ofs];
                    i1_out = indices[ofs + 1];
                }
                else
                {
                    edgenum_out = 2;
                    i0_out = indices[ofs + 2];
                    i1_out = indices[ofs];
                }
            }
            else
            {
                edgenum_out = 1;
                i0_out = indices[ofs + 1];
                i1_out = indices[ofs + 2];
            }
        }

        static void DegenPrologue(STriInfo[] pTriInfos, int[] piTriList_out, int iNrTrianglesIn, int iTotTris)
        {
            int iNextGoodTriangleSearchIndex;
            bool bStillFindingGoodOnes;
            int t = 0;
            while (t < (iTotTris - 1))
            {
                int iFO_a = pTriInfos[t].iOrgFaceNumber;
                int iFO_b = pTriInfos[t + 1].iOrgFaceNumber;
                if (iFO_a == iFO_b)
                {
                    bool bIsDeg_a = (pTriInfos[t].iFlag & MARK_DEGENERATE) != 0;
                    bool bIsDeg_b = (pTriInfos[t + 1].iFlag & MARK_DEGENERATE) != 0;
                    if (bIsDeg_a ^ bIsDeg_b)
                    {
                        pTriInfos[t].iFlag |= QUAD_ONE_DEGEN_TRI;
                        pTriInfos[t + 1].iFlag |= QUAD_ONE_DEGEN_TRI;
                    }
                    t += 2;
                }
                else ++t;
            }

            iNextGoodTriangleSearchIndex = 1;
            t = 0;
            bStillFindingGoodOnes = true;
            while (t < iNrTrianglesIn && bStillFindingGoodOnes)
            {
                bool bIsGood = (pTriInfos[t].iFlag & MARK_DEGENERATE) == 0;
                if (bIsGood)
                {
                    if (iNextGoodTriangleSearchIndex < (t + 2)) iNextGoodTriangleSearchIndex = t + 2;
                }
                else
                {
                    int t0, t1;
                    bool bJustADegenerate = true;
                    while (bJustADegenerate && iNextGoodTriangleSearchIndex < iTotTris)
                    {
                        bool bGood = (pTriInfos[iNextGoodTriangleSearchIndex].iFlag & MARK_DEGENERATE) == 0;
                        if (bGood) bJustADegenerate = false;
                        else ++iNextGoodTriangleSearchIndex;
                    }
                    t0 = t;
                    t1 = iNextGoodTriangleSearchIndex;
                    ++iNextGoodTriangleSearchIndex;
                    if (!bJustADegenerate)
                    {
                        for (int i = 0; i < 3; i++)
                        {
                            int index = piTriList_out[t0 * 3 + i];
                            piTriList_out[t0 * 3 + i] = piTriList_out[t1 * 3 + i];
                            piTriList_out[t1 * 3 + i] = index;
                        }
                        STriInfo tri_info = pTriInfos[t0];
                        pTriInfos[t0] = pTriInfos[t1];
                        pTriInfos[t1] = tri_info;
                    }
                    else bStillFindingGoodOnes = false;
                }
                if (bStillFindingGoodOnes) ++t;
            }
        }

        static void DegenEpilogue(STSpace[] psTspace, STriInfo[] pTriInfos, int[] piTriListIn, IContext pContext, int iNrTrianglesIn, int iTotTris)
        {
            int t, i;
            for (t = iNrTrianglesIn; t < iTotTris; t++)
            {
                bool bSkip = (pTriInfos[t].iFlag & QUAD_ONE_DEGEN_TRI) != 0;
                if (!bSkip)
                {
                    for (i = 0; i < 3; i++)
                    {
                        int index1 = piTriListIn[t * 3 + i];
                        bool bNotFound = true;
                        int j = 0;
                        while (bNotFound && j < (3 * iNrTrianglesIn))
                        {
                            int index2 = piTriListIn[j];
                            if (index1 == index2) bNotFound = false;
                            else ++j;
                        }
                        if (!bNotFound)
                        {
                            int iTri = j / 3;
                            int iVert = j % 3;
                            int iSrcVert = pTriInfos[iTri].vert_num[iVert];
                            int iSrcOffs = pTriInfos[iTri].iTSpacesOffs;
                            int iDstVert = pTriInfos[t].vert_num[i];
                            int iDstOffs = pTriInfos[t].iTSpacesOffs;
                            psTspace[iDstOffs + iDstVert] = psTspace[iSrcOffs + iSrcVert];
                        }
                    }
                }
            }

            for (t = 0; t < iNrTrianglesIn; t++)
            {
                if ((pTriInfos[t].iFlag & QUAD_ONE_DEGEN_TRI) != 0)
                {
                    SVec3 vDstP;
                    int iOrgF, ii;
                    bool bNotFound;
                    byte[] pV = pTriInfos[t].vert_num;
                    int iFlag = (1 << pV[0]) | (1 << pV[1]) | (1 << pV[2]);
                    int iMissingIndex = 0;
                    if ((iFlag & 2) == 0) iMissingIndex = 1;
                    else if ((iFlag & 4) == 0) iMissingIndex = 2;
                    else if ((iFlag & 8) == 0) iMissingIndex = 3;

                    iOrgF = pTriInfos[t].iOrgFaceNumber;
                    vDstP = GetPosition(pContext, MakeIndex(iOrgF, iMissingIndex));
                    bNotFound = true;
                    ii = 0;
                    while (bNotFound && ii < 3)
                    {
                        int iVert = pV[ii];
                        SVec3 vSrcP = GetPosition(pContext, MakeIndex(iOrgF, iVert));
                        if (veq(vSrcP, vDstP))
                        {
                            int iOffs = pTriInfos[t].iTSpacesOffs;
                            psTspace[iOffs + iMissingIndex] = psTspace[iOffs + iVert];
                            bNotFound = false;
                        }
                        else ++ii;
                    }
                }
            }
        }
    }
}

#endif
