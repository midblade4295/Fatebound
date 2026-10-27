// Records a canvas's render batches (Fatebound.GUI.Viewport.Render()) into a command buffer drawing into a raw RGBA8
// target, in Godot's 2D colour space (FateboundCanvas.hlsl): one mesh per batch (vertices in target pixels, y up),
// the batch's texture and its sRGB/alpha-only flags in a property block. Each target has its own drawer, because the
// meshes are only drawn when the command buffer runs later in the frame.
using System;
using System.Collections.Generic;
using Fatebound.GUI;
using UnityEngine;
using UnityEngine.Rendering;
using Material = UnityEngine.Material;
using Mesh = UnityEngine.Mesh;
using Texture = UnityEngine.Texture;
using Shader = UnityEngine.Shader;

namespace Fatebound.Client
{
    public sealed class CanvasDrawer
    {
        readonly List<Mesh> _meshes = new List<Mesh>();
        readonly List<MaterialPropertyBlock> _props = new List<MaterialPropertyBlock>();
        readonly List<ulong> _hashes = new List<ulong>();
        int _lastH = -1;

        /// <summary>FNV-1a over a batch's vertices and indices (and the target height they were flipped with): an
        /// unchanged batch keeps its uploaded mesh (most of a menu doesn't change from frame to frame).</summary>
        static ulong Mix(ulong x, float v) => (x ^ (uint)BitConverter.SingleToInt32Bits(v)) * 1099511628211UL;
        static ulong Mix(ulong x, int v) => (x ^ (uint)v) * 1099511628211UL;

        static ulong Hash(RenderBatch b, int h)
        {
            ulong x = 14695981039346656037UL;
            x = Mix(x, h);
            x = Mix(x, (int)b.mode);
            x = Mix(x, b.aux);
            var verts = b.verts;
            for (int i = 0; i < verts.Count; i++)
            {
                var v = verts[i];
                x = Mix(Mix(Mix(Mix(x, v.x), v.y), v.u), v.v);
                x = Mix(Mix(Mix(Mix(x, v.c.r), v.c.g), v.c.b), v.c.a);
                x = Mix(Mix(Mix(Mix(x, v.cx0), v.cy0), v.cx1), v.cy1);
            }
            var idx = b.indices;
            for (int i = 0; i < idx.Count; i++) x = Mix(x, idx[i]);
            return x;
        }

        static readonly List<Vector3> _pos = new List<Vector3>();
        static readonly List<Color32> _col = new List<Color32>();
        static readonly List<Vector4> _uv0 = new List<Vector4>();
        static readonly List<Vector4> _uv1 = new List<Vector4>();
        static readonly List<int> _idx = new List<int>();
        static readonly int ID_MainTex = Shader.PropertyToID("_MainTex"), ID_SrgbTex = Shader.PropertyToID("_SrgbTex"),
            ID_AlphaTex = Shader.PropertyToID("_AlphaTex"), ID_CanvasSize = Shader.PropertyToID("_FB_CanvasSize");

        /// <summary>Draws the batches into target (w x h pixels); clear: the colour to clear to first (sRGB values), or
        /// none to draw over what's there.</summary>
        public void Record(CommandBuffer cmd, RenderTargetIdentifier target, int w, int h, List<RenderBatch> batches, Color? clear,
            Func<RenderBatch, Material> materialFor, Texture white)
        {
            cmd.SetRenderTarget(target, clear.HasValue ? RenderBufferLoadAction.DontCare : RenderBufferLoadAction.Load, RenderBufferStoreAction.Store);
            if (clear.HasValue) cmd.ClearRenderTarget(false, true, clear.Value);
            cmd.SetViewProjectionMatrices(Matrix4x4.identity, GL.GetGPUProjectionMatrix(Matrix4x4.Ortho(0, w, 0, h, -1, 1), true));
            cmd.SetGlobalVector(ID_CanvasSize, new Vector4(w, h, 1f / w, 1f / h));
            while (_meshes.Count < batches.Count)
            {
                var m = new Mesh { hideFlags = HideFlags.DontSave };
                m.MarkDynamic();
                _meshes.Add(m);
                _props.Add(new MaterialPropertyBlock());
                _hashes.Add(0);
            }
            float fh = h;
            for (int i = 0; i < batches.Count; i++)
            {
                var b = batches[i];
                if (b.verts.Count == 0 || b.indices.Count == 0) continue;
                var mesh = _meshes[i];
                ulong hash = Hash(b, h);
                if (hash != _hashes[i] || h != _lastH)
                {
                    _hashes[i] = hash;
                    Upload(mesh, b, fh);
                }
                Texture tex = b.texture?.GetHandle() as Texture;
                // (a viewport that hasn't rendered yet shows nothing, not a white quad)
                if (tex == null) tex = b.texture is ViewportTexture ? (Texture)UnityEngine.Texture2D.blackTexture : white;
                if (b.repeat && tex.wrapMode != TextureWrapMode.Repeat) tex.wrapMode = TextureWrapMode.Repeat;
                var mpb = _props[i];
                mpb.Clear();
                mpb.SetTexture(ID_MainTex, tex);
                mpb.SetFloat(ID_SrgbTex, tex.isDataSRGB ? 1f : 0f);
                mpb.SetFloat(ID_AlphaTex, tex is UnityEngine.Texture2D t2 && t2.format == TextureFormat.Alpha8 ? 1f : 0f);
                cmd.DrawMesh(mesh, Matrix4x4.identity, materialFor(b), 0, 0, mpb);
                UnityRenderStats.CanvasDraws++;
                UnityRenderStats.CanvasPrimitives += b.indices.Count / 3;
            }
            _lastH = h;
        }

        static void Upload(Mesh mesh, RenderBatch b, float fh)
        {
            _pos.Clear(); _col.Clear(); _uv0.Clear(); _uv1.Clear(); _idx.Clear();
            float mode = b.mode == DrawMode.SdfText ? 1f : 0f;
            foreach (var v in b.verts)
            {
                _pos.Add(new Vector3(v.x, fh - v.y, 0));
                var c = v.c;
                _col.Add(new Color32((byte)(Mathf.Clamp01(c.r) * 255f + 0.5f), (byte)(Mathf.Clamp01(c.g) * 255f + 0.5f), (byte)(Mathf.Clamp01(c.b) * 255f + 0.5f), (byte)(Mathf.Clamp01(c.a) * 255f + 0.5f)));
                _uv0.Add(new Vector4(v.u, 1f - v.v, mode, b.aux));
                _uv1.Add(new Vector4(v.cx0, fh - v.cy1, v.cx1, fh - v.cy0));
            }
            _idx.AddRange(b.indices);
            mesh.Clear();
            mesh.indexFormat = _pos.Count > 65000 ? IndexFormat.UInt32 : IndexFormat.UInt16;
            mesh.SetVertices(_pos);
            mesh.SetColors(_col);
            mesh.SetUVs(0, _uv0);
            mesh.SetUVs(1, _uv1);
            mesh.SetTriangles(_idx, 0, false);
        }

        public void Release()
        {
            foreach (var m in _meshes) if (m != null) UnityEngine.Object.Destroy(m);
            _meshes.Clear();
            _props.Clear();
            _hashes.Clear();
        }
    }
}
