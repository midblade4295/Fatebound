// Facade meshes (Godot's surface arrays) -> Unity meshes, one submesh per surface, rebuilt when a surface changes.
// Godot -> Unity: positions/normals mirrored in X, tangents mirrored with the binormal sign flipped, winding kept,
// UVs kept as Godot's (shaders flip v when sampling), ARRAY_CUSTOM0..3 -> TEXCOORD2..5, bones/weights as BoneWeight1
// (indices = the skin's binds), triangle strips unrolled. Unity meshes whose facade mesh is gone are destroyed.
using System;
using System.Collections.Generic;
using Fatebound.GUI;
using Fatebound.Sim;
using Unity.Collections;
using UnityEngine;
using UnityEngine.Rendering;
using GMesh = Fatebound.GUI.Mesh;
using UMesh = UnityEngine.Mesh;
using PrimitiveType = Fatebound.GUI.PrimitiveType;

namespace Fatebound.Client
{
    public sealed class MeshCache
    {
        sealed class Entry
        {
            public WeakReference<GMesh> Source;
            public UMesh Mesh;
            public int[] Versions = Array.Empty<int>();
            public int[] SubmeshOf = Array.Empty<int>();     // surface index -> submesh (-1: empty surface)
            public bool Skinned;
        }

        // (weak keys: a facade mesh nobody uses any more can be collected; Sweep then destroys its Unity mesh)
        readonly System.Runtime.CompilerServices.ConditionalWeakTable<GMesh, Entry> _byMesh = new System.Runtime.CompilerServices.ConditionalWeakTable<GMesh, Entry>();
        readonly List<Entry> _all = new List<Entry>();
        int _sweep;

        /// <summary>The Unity mesh for a facade mesh (null if it has nothing to draw). submeshOf maps surfaces to submeshes.</summary>
        public UMesh Get(GMesh m, out int[] submeshOf)
        {
            submeshOf = null;
            if (m == null) return null;
            var surfaces = m.GetSurfaces();
            if (!_byMesh.TryGetValue(m, out var e))
            {
                e = new Entry { Source = new WeakReference<GMesh>(m) };
                _byMesh.Add(m, e);
                _all.Add(e);
            }
            if (!UpToDate(e, surfaces)) Build(e, surfaces);
            submeshOf = e.SubmeshOf;
            return e.Mesh;
        }

        static bool UpToDate(Entry e, IReadOnlyList<MeshSurface> s)
        {
            if (e.Mesh == null || e.Versions.Length != s.Count) return false;
            for (int i = 0; i < s.Count; i++) if (e.Versions[i] != s[i].Version) return false;
            return true;
        }

        static readonly List<Vector3> _v = new List<Vector3>(), _n = new List<Vector3>();
        static readonly List<Vector4> _t = new List<Vector4>(), _c0 = new List<Vector4>();
        static readonly List<Color> _col = new List<Color>();
        static readonly List<Vector2> _uv = new List<Vector2>(), _uv2 = new List<Vector2>();
        static readonly List<int> _idx = new List<int>();

        void Build(Entry e, IReadOnlyList<MeshSurface> surfaces)
        {
            if (e.Mesh == null)
            {
                e.Mesh = new UMesh { name = "fb", hideFlags = HideFlags.DontSave };
                e.Mesh.MarkDynamic();
            }
            var mesh = e.Mesh;
            mesh.Clear();
            e.Versions = new int[surfaces.Count];
            e.SubmeshOf = new int[surfaces.Count];
            int total = 0;
            bool hasN = false, hasT = false, hasC = false, hasUv = false, hasUv2 = false, hasBones = false;
            var hasCustom = new bool[4];
            for (int i = 0; i < surfaces.Count; i++)
            {
                var s = surfaces[i];
                e.Versions[i] = s.Version;
                int vc = s.VertexCount;
                total += vc;
                hasN |= s.Normals != null;
                hasT |= s.Tangents != null;
                hasC |= s.Colors != null;
                hasUv |= s.Uv != null;
                hasUv2 |= s.Uv2 != null;
                hasBones |= s.Bones != null && s.Weights != null;
                for (int c = 0; c < 4; c++) hasCustom[c] |= s.Custom[c] != null;
            }
            mesh.indexFormat = total > 65535 ? IndexFormat.UInt32 : IndexFormat.UInt16;
            _v.Clear(); _n.Clear(); _t.Clear(); _col.Clear(); _uv.Clear(); _uv2.Clear();
            var custom = new List<Vector4>[4];
            for (int c = 0; c < 4; c++) if (hasCustom[c]) custom[c] = new List<Vector4>(total);
            var bonesPer = hasBones ? new NativeArray<byte>(total, Allocator.Temp) : default;
            var weights = hasBones ? new List<BoneWeight1>(total * 4) : null;
            var subIndices = new List<(MeshTopology topo, int[] idx)>();
            int baseV = 0;
            for (int si = 0; si < surfaces.Count; si++)
            {
                var s = surfaces[si];
                int vc = s.VertexCount;
                if (vc == 0) { e.SubmeshOf[si] = -1; continue; }
                for (int i = 0; i < vc; i++) _v.Add(Conv.Pos(s.Vertices[i]));
                if (hasN) for (int i = 0; i < vc; i++) _n.Add(s.Normals != null && i < s.Normals.Length ? Conv.Dir(s.Normals[i]) : Vector3.up);
                if (hasT)
                    for (int i = 0; i < vc; i++)
                    {
                        if (s.Tangents != null && i * 4 + 3 < s.Tangents.Length)
                            _t.Add(new Vector4(-s.Tangents[i * 4], s.Tangents[i * 4 + 1], s.Tangents[i * 4 + 2], -s.Tangents[i * 4 + 3]));
                        else _t.Add(new Vector4(-1f, 0f, 0f, -1f));
                    }
                if (hasC) for (int i = 0; i < vc; i++) _col.Add(s.Colors != null && i < s.Colors.Length ? Conv.Color(s.Colors[i]) : Color.white);
                if (hasUv) for (int i = 0; i < vc; i++) { var u = s.Uv != null && i < s.Uv.Length ? s.Uv[i] : Vec2.Zero; _uv.Add(new Vector2(u.x, u.y)); }
                if (hasUv2) for (int i = 0; i < vc; i++) { var u = s.Uv2 != null && i < s.Uv2.Length ? s.Uv2[i] : Vec2.Zero; _uv2.Add(new Vector2(u.x, u.y)); }
                for (int c = 0; c < 4; c++)
                {
                    if (custom[c] == null) continue;
                    var src = s.Custom[c];
                    int comps = CustomComponents(s.CustomFormat[c]);
                    for (int i = 0; i < vc; i++)
                    {
                        var v4 = Vector4.zero;
                        if (src != null)
                            for (int k = 0; k < comps && i * comps + k < src.Length; k++) v4[k] = src[i * comps + k];
                        custom[c].Add(v4);
                    }
                }
                if (hasBones)
                {
                    int bpv = s.BonesPerVertex;
                    var tmp = new List<BoneWeight1>(8);
                    for (int i = 0; i < vc; i++)
                    {
                        tmp.Clear();
                        if (s.Bones != null && s.Weights != null)
                            for (int k = 0; k < bpv; k++)
                            {
                                int at = i * bpv + k;
                                if (at >= s.Weights.Length || at >= s.Bones.Length) break;
                                float w = s.Weights[at];
                                if (w <= 0f) continue;
                                tmp.Add(new BoneWeight1 { boneIndex = s.Bones[at], weight = w });
                            }
                        if (tmp.Count == 0) tmp.Add(new BoneWeight1 { boneIndex = 0, weight = 1f });
                        tmp.Sort((a, b) => b.weight.CompareTo(a.weight));
                        bonesPer[baseV + i] = (byte)tmp.Count;
                        weights.AddRange(tmp);
                    }
                }
                subIndices.Add(Indices(s, baseV));
                e.SubmeshOf[si] = subIndices.Count - 1;
                baseV += vc;
            }
            mesh.SetVertices(_v);
            if (hasN) mesh.SetNormals(_n);
            if (hasT) mesh.SetTangents(_t);
            if (hasC) mesh.SetColors(_col);
            if (hasUv) mesh.SetUVs(0, _uv);
            if (hasUv2) mesh.SetUVs(1, _uv2);
            for (int c = 0; c < 4; c++) if (custom[c] != null) mesh.SetUVs(2 + c, custom[c]);
            if (hasBones)
            {
                var w = new NativeArray<BoneWeight1>(weights.ToArray(), Allocator.Temp);
                mesh.SetBoneWeights(bonesPer, w);
                w.Dispose();
                bonesPer.Dispose();
            }
            e.Skinned = hasBones;
            mesh.subMeshCount = subIndices.Count;
            for (int i = 0; i < subIndices.Count; i++)
                mesh.SetIndices(subIndices[i].idx, subIndices[i].topo, i, false, 0);
            mesh.RecalculateBounds();
        }

        static int CustomComponents(int format)
        {
            switch (format)
            {
                case GMesh.ARRAY_CUSTOM_R_FLOAT: return 1;
                case GMesh.ARRAY_CUSTOM_RG_FLOAT:
                case GMesh.ARRAY_CUSTOM_RG_HALF: return 2;
                case GMesh.ARRAY_CUSTOM_RGB_FLOAT: return 3;
                default: return 4;
            }
        }

        static (MeshTopology, int[]) Indices(MeshSurface s, int baseV)
        {
            int vc = s.VertexCount;
            int[] src = s.Indices;
            if (src == null)
            {
                src = new int[vc];
                for (int i = 0; i < vc; i++) src[i] = i;
            }
            switch (s.Primitive)
            {
                case PrimitiveType.Points: return (MeshTopology.Points, Offset(src, baseV));
                case PrimitiveType.Lines: return (MeshTopology.Lines, Offset(src, baseV));
                case PrimitiveType.LineStrip: return (MeshTopology.LineStrip, Offset(src, baseV));
                case PrimitiveType.TriangleStrip:
                    {
                        // Godot's strips alternate winding like every API's: unroll to triangles with the same facing
                        var tri = new List<int>(Math.Max(0, (src.Length - 2) * 3));
                        for (int i = 0; i + 2 < src.Length; i++)
                        {
                            if ((i & 1) == 0) { tri.Add(src[i]); tri.Add(src[i + 1]); tri.Add(src[i + 2]); }
                            else { tri.Add(src[i + 1]); tri.Add(src[i]); tri.Add(src[i + 2]); }
                        }
                        return (MeshTopology.Triangles, Offset(tri.ToArray(), baseV));
                    }
                default:
                    {
                        int n = src.Length - src.Length % 3;
                        var o = new int[n];
                        for (int i = 0; i < n; i++) o[i] = src[i] + baseV;
                        return (MeshTopology.Triangles, o);
                    }
            }
        }

        static int[] Offset(int[] a, int b)
        {
            var o = new int[a.Length];
            for (int i = 0; i < a.Length; i++) o[i] = a[i] + b;
            return o;
        }

        /// <summary>Every few hundred frames: destroy Unity meshes whose facade mesh was collected.</summary>
        public void Sweep()
        {
            if (++_sweep < 300) return;
            _sweep = 0;
            for (int i = _all.Count - 1; i >= 0; i--)
            {
                var e = _all[i];
                if (e.Source.TryGetTarget(out _)) continue;
                if (e.Mesh != null) UnityEngine.Object.Destroy(e.Mesh);
                _all.RemoveAt(i);
            }
        }
    }

    /// <summary>Reference identity for dictionary keys (Resources may override Equals in the future).</summary>
    public sealed class ReferenceEqualityComparer<T> : IEqualityComparer<T> where T : class
    {
        public static readonly ReferenceEqualityComparer<T> Instance = new ReferenceEqualityComparer<T>();
        public bool Equals(T a, T b) => ReferenceEquals(a, b);
        public int GetHashCode(T o) => System.Runtime.CompilerServices.RuntimeHelpers.GetHashCode(o);
    }
}
