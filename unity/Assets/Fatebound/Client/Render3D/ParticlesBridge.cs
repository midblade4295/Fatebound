// GPUParticles3D: Godot's particle simulation runs on the CPU (Fatebound.GUI.ParticlesSim, a port of particles.glsl and
// the ParticleProcessMaterial shader) and every draw pass is drawn instanced like a MultiMesh, the particle's colour
// and INSTANCE_CUSTOM per instance (Fatebound/Standard3D's _InstColor / _InstCustom: billboard particles turn by
// custom.x and pick their flipbook frame from custom.z). Global-coordinate particles are drawn in world space; local
// ones with the node's transform.
using System;
using System.Collections.Generic;
using Fatebound.GUI;
using Fatebound.Sim;
using UnityEngine;
using UnityEngine.Rendering;
using Material = UnityEngine.Material;

namespace Fatebound.Client
{
    public static class ParticlesBridge
    {
        sealed class PData : UnityRenderer3D.NodeData
        {
            public GPUParticles3D Node;
            public ParticlesSim Sim;
            public int RestartSeen = -1;
            public bool Visible = true;
            public Matrix4x4[] Matrices = Array.Empty<Matrix4x4>();
            public Vector4[] Colors = Array.Empty<Vector4>(), Custom = Array.Empty<Vector4>();
            public MaterialPropertyBlock Props;
        }

        static readonly HashSet<PData> _all = new HashSet<PData>();

        public static void Sync(UnityRenderer3D r, GPUParticles3D p, UnityRenderer3D.WorldData wd, RenderDirty bits)
        {
            var d = p.BackendData as PData;
            if (d == null)
            {
                d = new PData { Node = p, World = wd, Sim = new ParticlesSim(p) };
                p.BackendData = d;
                _all.Add(d);
                bits = RenderDirty.All;
            }
            if ((bits & RenderDirty.Visibility) != 0) d.Visible = p.IsVisibleInTree();
            if ((bits & RenderDirty.Params) != 0) r.Materials.ApplyInstanceParams(null, ref d.Props, p);
        }

        public static void Removed(object data)
        {
            if (data is PData d) _all.Remove(d);
        }

        public static void Frame(UnityRenderer3D r, double delta)
        {
            foreach (var d in _all) Draw(r, d, delta);
        }

        static void Draw(UnityRenderer3D r, PData d, double delta)
        {
            var p = d.Node;
            // (Godot simulates particles whether or not they are visible, once the node is in a world)
            d.Sim.Update(delta);
            if (!d.Visible || !d.Sim.Active) return;
            int n = d.Sim.Count;
            if (n <= 0) return;
            if (d.Matrices.Length < n)
            {
                d.Matrices = new Matrix4x4[n];
                d.Colors = new Vector4[n];
                d.Custom = new Vector4[n];
            }
            var xf = d.Sim.Transforms;
            var cols = d.Sim.Colors;
            var cus = d.Sim.Custom;
            bool local = d.Sim.LocalCoords;
            var g = local ? p.GlobalTransform : Xform3.IDENTITY;
            int drawn = 0;
            for (int i = 0; i < n; i++)
            {
                // an inactive slot has a zero basis (Godot also moves it to -INF so even a billboard vanishes): skip it
                var b = xf[i].basis;
                if (b.x == Vec3.Zero && b.y == Vec3.Zero && b.z == Vec3.Zero) continue;
                d.Matrices[drawn] = Conv.Matrix(local ? g * xf[i] : xf[i]);
                var c = cols[i];
                d.Colors[drawn] = new Vector4(c.r, c.g, c.b, c.a);
                d.Custom[drawn] = new Vector4(cus[i * 4], cus[i * 4 + 1], cus[i * 4 + 2], cus[i * 4 + 3]);
                drawn++;
            }
            n = drawn;
            if (n == 0) return;
            if (d.Props == null) d.Props = new MaterialPropertyBlock();
            var rp = new RenderParams
            {
                layer = d.World.Layer,
                shadowCastingMode = p.CastShadow == ShadowCastingSetting.Off ? ShadowCastingMode.Off : ShadowCastingMode.On,
                receiveShadows = true,
                matProps = d.Props,
                worldBounds = new Bounds(Vector3.zero, Vector3.one * 100000f),
            };
            const int MAX = 1023;
            for (int pass = 0; pass < p.DrawPasses; pass++)
            {
                var gm = p.GetDrawPassMesh(pass);
                if (gm == null) continue;
                var mesh = r.Meshes.Get(gm, out var submeshOf);
                if (mesh == null) continue;
                for (int s = 0; s < submeshOf.Length; s++)
                {
                    int sub = submeshOf[s];
                    if (sub < 0) continue;
                    // a draw pass uses the node's material_override, else the mesh's surface material
                    Material mat = r.Materials.Get(p.MaterialOverride ?? gm.SurfaceGetMaterial(s), 1);
                    rp.material = mat;
                    for (int start = 0; start < n; start += MAX)
                    {
                        int count = Math.Min(MAX, n - start);
                        d.Props.SetVectorArray("_InstColor", Slice(d.Colors, start, count));
                        d.Props.SetVectorArray("_InstCustom", Slice(d.Custom, start, count, true));
                        Graphics.RenderMeshInstanced(rp, mesh, sub, d.Matrices, count, start);
                    }
                }
            }
        }

        static readonly Vector4[] _slice = new Vector4[1023], _slice2 = new Vector4[1023];

        static Vector4[] Slice(Vector4[] a, int start, int count, bool second = false)
        {
            if (start == 0 && count == a.Length) return a;
            var dst = second ? _slice2 : _slice;
            Array.Copy(a, start, dst, 0, count);
            return dst;
        }
    }
}
