// Fatebound (Unity port): draws the engine-free 3D scene (GUI/Scene3D) with Unity -- the RenderSync renderer.
//  * Every World3D gets a root GameObject and a Unity layer of its own (a camera sees only its world: cullingMask;
//    lights are culled by their GameObject's layer too, so worlds don't light each other).
//  * Every drawn node gets a GameObject directly under its world's root, placed by its Godot global transform
//    (Conv.Apply): flat, as Godot's RenderingServer instances are. MeshInstance3D: MeshFilter + MeshRenderer, or a
//    SkinnedMeshRenderer whose bones are child transforms set from the facade skeleton's skin transforms each frame
//    its pose changed. MultiMeshInstance3D: Graphics.RenderMeshInstanced every frame. Lights: a Light on a child turned
//    180 degrees. GPUParticles3D: a ParticleSystem (ParticlesBridge). Sprite3D: a quad.
//  * Every Viewport that shows 3D gets a Camera on its own GameObject, configured each frame from the viewport's
//    current Camera3D (transform, Godot's projection matrix), rendering into an HDR render texture; the viewport's
//    Environment then goes through Godot's post (PostChain: glow, tonemap, adjustments) into the texture the GUI
//    draws (ViewportTexture.Resolve). The root viewport's 3D (if any) is drawn the same way, under the GUI.
//  * Per camera, the world's Environment sets the Fatebound shaders' globals (ambient, fog) and the clear/sky.
using System;
using System.Collections.Generic;
using Fatebound.GUI;
using Fatebound.Sim;
using UnityEngine;
using UnityEngine.Rendering;
using Camera = UnityEngine.Camera;
using Environment = Fatebound.GUI.Environment;
using GMesh = Fatebound.GUI.Mesh;
using Light = UnityEngine.Light;
using Material = UnityEngine.Material;
using Object = UnityEngine.Object;
using Shader = UnityEngine.Shader;
using UMesh = UnityEngine.Mesh;
using Time = UnityEngine.Time;

namespace Fatebound.Client
{
    public sealed class UnityRenderer3D : IRenderer3D
    {
        public static UnityRenderer3D Instance { get; private set; }

        readonly GameObject _root;
        public readonly MeshCache Meshes = new MeshCache();
        public readonly MaterialCache Materials = new MaterialCache();
        readonly Dictionary<World3D, WorldData> _worlds = new Dictionary<World3D, WorldData>();
        readonly Dictionary<Camera, VpData> _byCamera = new Dictionary<Camera, VpData>();
        readonly List<VpData> _viewports = new List<VpData>();
        readonly HashSet<MeshData> _skinned = new HashSet<MeshData>();
        readonly HashSet<MultiMeshData> _multimeshes = new HashSet<MultiMeshData>();
        readonly HashSet<DecalData> _decals = new HashSet<DecalData>();
        readonly Stack<int> _freeLayers = new Stack<int>();
        int _sharedLayer = 31;

        public sealed class WorldData
        {
            public World3D World;
            public GameObject Root;
            public int Layer;
        }

        public class NodeData
        {
            public GameObject Go;
            public WorldData World;
        }

        public sealed class MeshData : NodeData
        {
            public MeshInstance3D Node;
            public MeshFilter Filter;
            public MeshRenderer Renderer;
            public SkinnedMeshRenderer Skinned;
            public Transform[] Bones;
            public Xform3[] SkinXf;
            public int PoseVersion = -1;
            public UMesh Mesh;
            public int[] SubmeshOf;
            public MaterialPropertyBlock Props;
            public Renderer Active => Skinned != null ? (Renderer)Skinned : Renderer;
        }

        public sealed class MultiMeshData : NodeData
        {
            public MultiMeshInstance3D Node;
            public Matrix4x4[] Matrices = Array.Empty<Matrix4x4>();
            public Vector4[] Colors = Array.Empty<Vector4>(), Custom = Array.Empty<Vector4>();
            public int Version = -1;
            public Xform3 BuiltWith;
            public bool Visible = true;
            public MaterialPropertyBlock Props;
        }

        public sealed class LightData : NodeData
        {
            public Light Light;
        }

        public sealed class DecalData : NodeData
        {
            public Decal Node;
            public bool Visible;
        }

        public sealed class SpriteData : NodeData
        {
            public MeshFilter Filter;
            public MeshRenderer Renderer;
            public UMesh Quad;
        }

        public sealed class VpData
        {
            public Viewport Vp;
            public GameObject Go;
            public Camera Camera;
            public RenderTexture Hdr, Ldr;
            public WorldData World;
            public int OnceSeen = -1;
            public Environment Env;
            /// <summary>This frame: the camera renders the 3D picture / the canvas is drawn into the texture.</summary>
            public bool Rendered3D, Draw2D;
        }

        public UnityRenderer3D()
        {
            Instance = this;
            _root = new GameObject("3D");
            Object.DontDestroyOnLoad(_root);
            for (int l = 30; l >= 8; l--) _freeLayers.Push(l);
            RenderSync.Renderer = this;
            ViewportTexture.Resolve = t => t.viewport != null && t.viewport.BackendData is VpData d ? d.Ldr : null;
            RenderPipelineManager.beginCameraRendering += OnBeginCamera;
            RenderPipelineManager.endCameraRendering += OnEndCamera;
        }

        bool _reported;

        /// <summary>Which of the port's shaders this GPU can't run (a shader that failed to compile for it): into the boot
        /// log, so a phone's log says what a build log would.</summary>
        static void ReportShaders()
        {
            try
            {
                // by the list of the port's shader files the build writes (BuildScript: Resources/fb_shaders.txt), so even a
                // shader that came out nameless is named by its file
                var list = Resources.Load<TextAsset>("fb_shaders");
                var paths = list != null ? list.text.Split(new[] { '\n' }, StringSplitOptions.RemoveEmptyEntries) : Array.Empty<string>();
                var all = Resources.LoadAll<UnityEngine.Shader>("Shaders");
                int bad = 0;
                if (paths.Length > 0)
                {
                    foreach (var raw in paths)
                    {
                        string path = raw.Trim();
                        var sh = Resources.Load<UnityEngine.Shader>(path);
                        if (sh != null && sh.isSupported) continue;
                        bad++;
                        Debug.LogError("Fatebound shader not supported on this GPU: " + path + (sh == null ? " (didn't load)" : " (\"" + sh.name + "\")"));
                    }
                }
                else
                    foreach (var sh in all)
                    {
                        if (sh.isSupported) continue;
                        bad++;
                        Debug.LogError("Fatebound shader not supported on this GPU: " + sh.name + " (" + sh.passCount + " passes)");
                    }
                var post = UnityEngine.Shader.Find("Hidden/Fatebound/Post");
                int total = paths.Length > 0 ? paths.Length : all.Length;
                Debug.LogWarning("Fatebound shaders: " + (total - bad) + " of " + total + " supported (" + SystemInfo.graphicsDeviceType
                    + "); the post shader " + (post == null ? "missing" : post.passCount + " passes"));
            }
            catch (Exception e) { Debug.LogException(e); }
        }

        // ------------------------------------------------------------------ worlds
        WorldData World(World3D w)
        {
            if (w == null) return null;
            if (_worlds.TryGetValue(w, out var d)) return d;
            d = new WorldData { World = w, Layer = _freeLayers.Count > 0 ? _freeLayers.Pop() : _sharedLayer };
            d.Root = new GameObject("World#" + w.Id);
            d.Root.layer = d.Layer;
            d.Root.transform.SetParent(_root.transform, false);
            _worlds[w] = d;
            w.BackendData = d;
            return d;
        }

        public void SyncWorld(World3D world)
        {
            World(world);         // (the environment is read per camera)
        }

        // ------------------------------------------------------------------ nodes
        public void Sync(Node3D node, RenderDirty bits)
        {
            var wd = World(node.RenderWorld);
            if (wd == null) return;
            // a node that moved to another world is made again
            if (node.BackendData is NodeData nd && nd.World != wd)
            {
                Remove(node, nd);
                node.BackendData = null;
                bits = RenderDirty.All;
            }
            switch (node)
            {
                case MeshInstance3D mi: SyncMesh(mi, wd, bits); break;
                case MultiMeshInstance3D mm: SyncMultiMesh(mm, wd, bits); break;
                case GPUParticles3D p: ParticlesBridge.Sync(this, p, wd, bits); break;
                case Sprite3D s: SyncSprite(s, wd, bits); break;
                case Decal dc: SyncDecal(dc, wd, bits); break;
                case Light3D l: SyncLight(l, wd, bits); break;
                case Camera3D _: break;           // read each frame through its viewport
                default:
                    if ((bits & RenderDirty.Created) != 0) Unsupported(node);
                    break;
            }
        }

        static readonly HashSet<Type> _warned = new HashSet<Type>();

        static void Unsupported(Node3D n)
        {
            if (_warned.Add(n.GetType())) Debug.LogWarning("Fatebound 3D: " + n.GetType().Name + " is not drawn yet (" + n.Name + ")");
        }

        GameObject MakeGo(string name, WorldData wd)
        {
            var go = new GameObject(name);
            go.layer = wd.Layer;
            go.transform.SetParent(wd.Root.transform, false);
            return go;
        }

        public void Remove(Node3D node, object data)
        {
            switch (data)
            {
                case MeshData md: _skinned.Remove(md); break;
                case MultiMeshData mm: _multimeshes.Remove(mm); break;
                case DecalData dd: _decals.Remove(dd); break;
                case SpriteData sd: if (sd.Quad != null) Object.Destroy(sd.Quad); break;
            }
            if (data is NodeData d && d.Go != null) Object.Destroy(d.Go);
            ParticlesBridge.Removed(data);
        }

        static ShadowCastingMode Shadows(ShadowCastingSetting s)
        {
            switch (s)
            {
                case ShadowCastingSetting.Off: return ShadowCastingMode.Off;
                case ShadowCastingSetting.DoubleSided: return ShadowCastingMode.TwoSided;
                case ShadowCastingSetting.ShadowsOnly: return ShadowCastingMode.ShadowsOnly;
                default: return ShadowCastingMode.On;
            }
        }

        void SyncMesh(MeshInstance3D mi, WorldData wd, RenderDirty bits)
        {
            var d = mi.BackendData as MeshData;
            if (d == null)
            {
                d = new MeshData { Node = mi, World = wd, Go = MakeGo(mi.Name, wd) };
                mi.BackendData = d;
                bits = RenderDirty.All;
            }
            var skel = mi.GetSkeleton();
            bool skinned = skel != null && mi.Mesh != null && mi.Mesh.HasBones();
            if ((bits & (RenderDirty.Base | RenderDirty.Material)) != 0 || (skinned != (d.Skinned != null)))
            {
                d.Mesh = Meshes.Get(mi.Mesh, out d.SubmeshOf);
                if (skinned)
                {
                    if (d.Renderer != null) { Object.Destroy(d.Renderer); Object.Destroy(d.Filter); d.Renderer = null; d.Filter = null; }
                    if (d.Skinned == null) d.Skinned = d.Go.AddComponent<SkinnedMeshRenderer>();
                    SetupBones(d, mi);
                    d.Skinned.sharedMesh = d.Mesh;
                    d.Skinned.updateWhenOffscreen = false;
                    _skinned.Add(d);
                    d.PoseVersion = -1;
                }
                else
                {
                    if (d.Skinned != null) { Object.Destroy(d.Skinned); d.Skinned = null; _skinned.Remove(d); }
                    if (d.Filter == null) d.Filter = d.Go.AddComponent<MeshFilter>();
                    if (d.Renderer == null) d.Renderer = d.Go.AddComponent<MeshRenderer>();
                    d.Filter.sharedMesh = d.Mesh;
                }
                d.Active.sharedMaterials = Materials.ForMesh(mi, d.SubmeshOf, d.Mesh != null ? d.Mesh.subMeshCount : 0);
                bits |= RenderDirty.Params | RenderDirty.Visibility | RenderDirty.Transform;
            }
            var r = d.Active;
            if (r == null) return;
            if ((bits & RenderDirty.Transform) != 0) Conv.Apply(d.Go.transform, mi.GlobalTransform);
            if ((bits & RenderDirty.Visibility) != 0) r.enabled = mi.IsVisibleInTree() && d.Mesh != null;
            if ((bits & RenderDirty.Params) != 0)
            {
                r.shadowCastingMode = Shadows(mi.CastShadow);
                r.receiveShadows = true;
                Materials.ApplyInstanceParams(r, ref d.Props, mi);
            }
            if ((bits & RenderDirty.Pose) != 0 && d.Skinned != null) d.PoseVersion = -1;
        }

        void SetupBones(MeshData d, MeshInstance3D mi)
        {
            var skin = mi.Skin;
            int n = skin != null ? skin.GetBindCount() : mi.GetSkeleton().GetBoneCount();
            if (d.Bones == null || d.Bones.Length != n)
            {
                if (d.Bones != null) foreach (var b in d.Bones) if (b != null) Object.Destroy(b.gameObject);
                d.Bones = new Transform[n];
                for (int i = 0; i < n; i++)
                {
                    var b = new GameObject("b" + i).transform;
                    b.SetParent(d.Go.transform, false);
                    d.Bones[i] = b;
                }
                d.SkinXf = new Xform3[n];
            }
            d.Skinned.bones = d.Bones;
            d.Skinned.rootBone = d.Go.transform;
            if (d.Mesh != null && (d.Mesh.bindposes == null || d.Mesh.bindposes.Length != n))
            {
                var bp = new Matrix4x4[n];
                for (int i = 0; i < n; i++) bp[i] = Matrix4x4.identity;
                d.Mesh.bindposes = bp;
            }
            if (d.Mesh != null)
            {
                // (the pose can reach far from the rest mesh: generous bounds, so it isn't culled mid-swing)
                var b = d.Mesh.bounds;
                b.Expand(b.size.magnitude + 2f);
                d.Skinned.localBounds = b;
            }
        }

        void UpdateSkin(MeshData d)
        {
            var mi = d.Node;
            var skel = mi.GetSkeleton();
            if (skel == null || d.Skinned == null || !d.Skinned.enabled) return;
            if (d.PoseVersion == skel.PoseVersion) return;
            d.PoseVersion = skel.PoseVersion;
            // (a null skin: the skeleton's rest skin, as Godot creates one for a MeshInstance3D without a skin)
            skel.GetSkinTransforms(mi.Skin, d.SkinXf);
            // bone transforms are children of the mesh's GameObject: relative to the mesh instance (Godot's skinning
            // applies the instance transform after the skin transforms)
            for (int i = 0; i < d.Bones.Length; i++) Conv.Apply(d.Bones[i], d.SkinXf[i]);
        }

        void SyncMultiMesh(MultiMeshInstance3D mm, WorldData wd, RenderDirty bits)
        {
            var d = mm.BackendData as MultiMeshData;
            if (d == null)
            {
                d = new MultiMeshData { Node = mm, World = wd, Go = null };
                mm.BackendData = d;
                _multimeshes.Add(d);
            }
            if ((bits & RenderDirty.Visibility) != 0) d.Visible = mm.IsVisibleInTree();
            if ((bits & (RenderDirty.Transform | RenderDirty.Pose | RenderDirty.Base)) != 0) d.Version = -1;
            if ((bits & RenderDirty.Params) != 0) Materials.ApplyInstanceParams(null, ref d.Props, mm);
        }

        void DrawMultiMesh(MultiMeshData d)
        {
            var mm = d.Node.Multimesh;
            if (!d.Visible || mm == null || mm.Mesh == null) return;
            int n = mm.DrawnCount;
            if (n <= 0) return;
            var mesh = Meshes.Get(mm.Mesh, out var submeshOf);
            if (mesh == null) return;
            if (d.Version != mm.InstancesVersion || d.Matrices.Length < n)
            {
                if (d.Matrices.Length < n)
                {
                    d.Matrices = new Matrix4x4[n];
                    d.Colors = new Vector4[n];
                    d.Custom = new Vector4[n];
                }
                var g = d.Node.GlobalTransform;
                var xf = mm.Transforms;
                var cols = mm.Colors;
                var cus = mm.CustomData;
                for (int i = 0; i < n; i++)
                {
                    d.Matrices[i] = Conv.Matrix(g * xf[i]);
                    var c = cols[i];
                    d.Colors[i] = new Vector4(c.r, c.g, c.b, c.a);
                    var u = cus[i];
                    d.Custom[i] = new Vector4(u.r, u.g, u.b, u.a);
                }
                d.Version = mm.InstancesVersion;
            }
            if (d.Props == null) d.Props = new MaterialPropertyBlock();
            var mats = Materials.ForMultiMesh(d.Node, submeshOf);
            var rp = new RenderParams
            {
                layer = d.World.Layer,
                shadowCastingMode = Shadows(d.Node.CastShadow),
                receiveShadows = true,
                matProps = d.Props,
                worldBounds = new Bounds(Vector3.zero, Vector3.one * 100000f),
            };
            const int MAX = 1023;
            for (int s = 0; s < submeshOf.Length; s++)
            {
                int sub = submeshOf[s];
                if (sub < 0 || mats[s] == null) continue;
                rp.material = mats[s];
                for (int start = 0; start < n; start += MAX)
                {
                    int count = Math.Min(MAX, n - start);
                    if (mm.UseColors) d.Props.SetVectorArray("_InstColor", Slice(d.Colors, start, count));
                    if (mm.UseCustomData) d.Props.SetVectorArray("_InstCustom", Slice(d.Custom, start, count));
                    Graphics.RenderMeshInstanced(rp, mesh, sub, d.Matrices, count, start);
                }
            }
        }

        static Vector4[] _slice = new Vector4[1023];
        /// <summary>The batch's per-instance values in a 1023-long array: Unity fixes a property block array's length the
        /// first time it is set, so every set is the full length (a shorter first set capped the bigger batches).</summary>
        static Vector4[] Slice(Vector4[] a, int start, int count)
        {
            if (start == 0 && count == _slice.Length && a.Length == _slice.Length) return a;
            Array.Copy(a, start, _slice, 0, count);
            return _slice;
        }

        void SyncLight(Light3D l, WorldData wd, RenderDirty bits)
        {
            var d = l.BackendData as LightData;
            if (d == null)
            {
                d = new LightData { World = wd, Go = MakeGo(l.Name, wd) };
                var child = new GameObject("light");
                child.layer = wd.Layer;
                child.transform.SetParent(d.Go.transform, false);
                child.transform.localRotation = Conv.Yaw180;
                d.Light = child.AddComponent<Light>();
                l.BackendData = d;
                bits = RenderDirty.All;
            }
            var light = d.Light;
            if ((bits & RenderDirty.Transform) != 0) Conv.Apply(d.Go.transform, l.GlobalTransform.Orthonormalized());
            if ((bits & RenderDirty.Visibility) != 0) light.enabled = l.IsVisibleInTree();
            if ((bits & RenderDirty.Base) != 0)
            {
                switch (l)
                {
                    case DirectionalLight3D _: light.type = LightType.Directional; break;
                    case OmniLight3D o: light.type = LightType.Point; light.range = (float)o.OmniRange; break;
                    case SpotLight3D sp:
                        light.type = LightType.Spot;
                        light.range = (float)sp.SpotRange;
                        light.spotAngle = (float)sp.SpotAngle * 2f;
                        break;
                }
                // (URP takes the colour as sRGB and linearises it, times the intensity: Godot's srgb_to_linear * energy)
                var c = l.LightColor;
                float sign = l.LightNegative ? -1f : 1f;
                light.color = new Color(c.r, c.g, c.b, 1f);
                light.intensity = (float)l.LightEnergy * sign;
                light.shadows = l.ShadowEnabled ? LightShadows.Hard : LightShadows.None;
                light.shadowStrength = (float)l.ShadowOpacity;
                light.shadowBias = (float)l.ShadowBias * 0.5f;
                light.shadowNormalBias = (float)l.ShadowNormalBias * 0.5f;
                light.cullingMask = 1 << wd.Layer;
            }
        }

        void SyncSprite(Sprite3D s, WorldData wd, RenderDirty bits)
        {
            var d = s.BackendData as SpriteData;
            if (d == null)
            {
                d = new SpriteData { World = wd, Go = MakeGo(s.Name, wd) };
                d.Filter = d.Go.AddComponent<MeshFilter>();
                d.Renderer = d.Go.AddComponent<MeshRenderer>();
                s.BackendData = d;
                bits = RenderDirty.All;
            }
            if ((bits & RenderDirty.Transform) != 0) Conv.Apply(d.Go.transform, s.GlobalTransform);
            if ((bits & RenderDirty.Visibility) != 0) d.Renderer.enabled = s.IsVisibleInTree() && s.Texture != null;
            if ((bits & (RenderDirty.Base | RenderDirty.Material)) != 0)
            {
                if (d.Quad == null) d.Quad = new UMesh { name = "sprite", hideFlags = HideFlags.DontSave };
                SpriteQuad(s, d.Quad);
                d.Filter.sharedMesh = d.Quad;
                d.Renderer.sharedMaterial = Materials.ForSprite(s);
                d.Renderer.enabled = s.IsVisibleInTree() && s.Texture != null;
            }
            if ((bits & RenderDirty.Params) != 0) d.Renderer.shadowCastingMode = Shadows(s.CastShadow);
        }

        static void SpriteQuad(Sprite3D s, UMesh q)
        {
            // Godot's SpriteBase3D: a quad of the texture's (or region's / frame's) size * pixel_size, centred, offset
            var tex = s.Texture;
            float tw = tex != null ? tex.GetWidth() : 1, th = tex != null ? tex.GetHeight() : 1;
            Rect2 src = new Rect2(0, 0, tw, th);
            if (s.RegionEnabled) src = s.RegionRect;
            else if (s.Hframes > 1 || s.Vframes > 1)
            {
                float fw = tw / s.Hframes, fh = th / s.Vframes;
                int f = s.Frame;
                src = new Rect2((f % s.Hframes) * fw, (f / s.Hframes) * fh, fw, fh);
            }
            float px = (float)s.PixelSize;
            var size = new Vec2(src.size.x, src.size.y);
            var ofs = s.Offset;
            if (s.Centered) ofs = ofs - size * 0.5;
            float x0 = ofs.x * px, x1 = (ofs.x + size.x) * px, y0 = ofs.y * px, y1 = (ofs.y + size.y) * px;
            float u0 = src.position.x / tw, u1 = (src.position.x + src.size.x) / tw, v0 = src.position.y / th, v1 = (src.position.y + src.size.y) / th;
            if (s.FlipH) { var t = u0; u0 = u1; u1 = t; }
            if (s.FlipV) { var t = v0; v0 = v1; v1 = t; }
            // Godot's quad in its own space (y up, facing +Z), mirrored into Unity's; UVs are Godot's (v down)
            q.Clear();
            q.vertices = new[] { new Vector3(-x0, y1, 0), new Vector3(-x1, y1, 0), new Vector3(-x1, y0, 0), new Vector3(-x0, y0, 0) };
            q.normals = new[] { Vector3.forward, Vector3.forward, Vector3.forward, Vector3.forward };
            q.uv = new[] { new Vector2(u0, v0), new Vector2(u1, v0), new Vector2(u1, v1), new Vector2(u0, v1) };
            var c = s.Modulate;
            var col = new Color(c.r, c.g, c.b, c.a);
            q.colors = new[] { col, col, col, col };
            q.triangles = new[] { 0, 1, 2, 0, 2, 3 };
            q.RecalculateBounds();
        }

        // ------------------------------------------------------------------ decals
        void SyncDecal(Decal dc, WorldData wd, RenderDirty bits)
        {
            var d = dc.BackendData as DecalData;
            if (d == null)
            {
                d = new DecalData { Node = dc, World = wd };
                dc.BackendData = d;
                _decals.Add(d);
            }
            d.Visible = dc.IsVisibleInTree();
        }

        static readonly Matrix4x4[] _decalXf = new Matrix4x4[4];
        static readonly Vector4[] _decalMod = new Vector4[4], _decalPrm = new Vector4[4], _decalUp = new Vector4[4];
        static readonly int[] _decalTexId = { Shader.PropertyToID("_FB_DecalTex0"), Shader.PropertyToID("_FB_DecalTex1"), Shader.PropertyToID("_FB_DecalTex2"), Shader.PropertyToID("_FB_DecalTex3") };
        readonly List<(float dist, DecalData d)> _decalPick = new List<(float, DecalData)>();
        static readonly Matrix4x4 MirrorX = Matrix4x4.Scale(new Vector3(-1f, 1f, 1f));

        /// <summary>Godot's decal buffer for one camera (texture_storage.cpp update_decal_buffer): its world's visible
        /// decals with an albedo texture, nearest first, up to FB_MAX_DECALS.</summary>
        void SetDecals(VpData vd, Xform3 camXf)
        {
            _decalPick.Clear();
            foreach (var d in _decals)
            {
                if (!d.Visible || d.World != vd.World || d.Node.TextureAlbedo == null) continue;
                if ((d.Node.CullMask & (vd.Vp.GetCamera3D()?.CullMask ?? 0xFFFFFu)) == 0) continue;
                float dist = (float)camXf.origin.DistanceTo(d.Node.GlobalTransform.origin);
                _decalPick.Add((dist, d));
            }
            _decalPick.Sort((a, b) => a.dist.CompareTo(b.dist));
            int n = Math.Min(4, _decalPick.Count);
            for (int i = 0; i < n; i++)
            {
                var dc = _decalPick[i].d.Node;
                // uv_local = inverse(xform * scale(extents) * uv_xform) * point, uv_xform = scale (2,1,2) + origin (-1,0,-1)
                var ext = dc.Size * 0.5f;
                var scale = new Xform3(Basis.FromScale(ext), Vec3.Zero);
                var uvx = new Xform3(Basis.FromScale(new Vec3(2f, 1f, 2f)), new Vec3(-1f, 0f, -1f));
                var toDecal = (dc.GlobalTransform * scale * uvx).AffineInverse();
                // (the shader's point is Unity's: mirror it back to Godot's first)
                _decalXf[i] = GodotMatrix(toDecal) * MirrorX;
                var m = new Color(dc.Modulate.r, dc.Modulate.g, dc.Modulate.b, 1f).linear;
                _decalMod[i] = new Vector4(m.r, m.g, m.b, dc.Modulate.a);
                _decalPrm[i] = new Vector4((float)dc.AlbedoMix, (float)dc.UpperFade, (float)dc.LowerFade, (float)dc.NormalFade);
                var up = dc.GlobalTransform.basis.GetColumn(1).Normalized();
                var uu = Conv.Dir(up);
                _decalUp[i] = new Vector4(uu.x, uu.y, uu.z, 0f);
                var tex = dc.TextureAlbedo.GetHandle() as Texture;
                if (tex != null) { tex.wrapMode = TextureWrapMode.Clamp; if (tex.filterMode == FilterMode.Point) tex.filterMode = FilterMode.Bilinear; }
                Shader.SetGlobalTexture(_decalTexId[i], tex != null ? tex : UnityEngine.Texture2D.blackTexture);
            }
            Shader.SetGlobalVector("_FB_DecalCount", new Vector4(n, 0, 0, 0));
            if (n > 0)
            {
                Shader.SetGlobalMatrixArray("_FB_DecalXf", _decalXf);
                Shader.SetGlobalVectorArray("_FB_DecalModulate", _decalMod);
                Shader.SetGlobalVectorArray("_FB_DecalParams", _decalPrm);
                Shader.SetGlobalVectorArray("_FB_DecalUp", _decalUp);
            }
        }

        /// <summary>A Godot transform as a 4x4 matrix in Godot's own space (no mirroring).</summary>
        static Matrix4x4 GodotMatrix(Xform3 t)
        {
            var m = Matrix4x4.identity;
            for (int c = 0; c < 3; c++)
            {
                var col = t.basis.GetColumn(c);
                m.SetColumn(c, new Vector4(col.x, col.y, col.z, 0f));
            }
            m.SetColumn(3, new Vector4(t.origin.x, t.origin.y, t.origin.z, 1f));
            return m;
        }

        // ------------------------------------------------------------------ viewports
        public void SyncViewport(Viewport vp)
        {
            var d = vp.BackendData as VpData;
            if (d == null)
            {
                d = new VpData { Vp = vp };
                d.Go = new GameObject("Viewport " + vp.Name);
                d.Go.transform.SetParent(_root.transform, false);
                var child = new GameObject("camera");
                child.transform.SetParent(d.Go.transform, false);
                child.transform.localRotation = Conv.Yaw180;
                d.Camera = child.AddComponent<Camera>();
                d.Camera.enabled = false;
                d.Camera.clearFlags = CameraClearFlags.SolidColor;
                d.Camera.allowHDR = true;
                d.Camera.allowMSAA = true;
                d.Camera.useOcclusionCulling = false;
                d.Camera.depth = -10;
                vp.BackendData = d;
                _viewports.Add(d);
                _byCamera[d.Camera] = d;
            }
            d.World = World(vp.FindWorld3D());
        }

        public void RemoveViewport(Viewport vp, object data)
        {
            if (!(data is VpData d)) return;
            _viewports.Remove(d);
            _byCamera.Remove(d.Camera);
            Free(ref d.Hdr);
            Free(ref d.Ldr);
            if (d.Go != null) Object.Destroy(d.Go);
            if (vp.BackendData == d) vp.BackendData = null;
        }

        /// <summary>Every viewport in the tree (the GUI draws the SubViewports' canvases into their textures).</summary>
        public IReadOnlyList<VpData> Viewports => _viewports;

        public VpData RootData(Viewport root) => root?.BackendData as VpData;

        static void Free(ref RenderTexture rt)
        {
            if (rt == null) return;
            rt.Release();
            Object.Destroy(rt);
            rt = null;
        }

        /// <summary>The viewport's texture (what ViewportTexture shows and its canvas is drawn into): raw RGBA8 holding
        /// sRGB values, Godot's 2D colour space (the post chain encodes the 3D picture into it).</summary>
        static void EnsureLdr(VpData d, int w, int h)
        {
            // (use_hdr_2d: a half-float target, values kept as the canvas shader writes them)
            var fmt = d.Vp.UseHdr2D ? RenderTextureFormat.ARGBHalf : RenderTextureFormat.ARGB32;
            if (d.Ldr != null && d.Ldr.width == w && d.Ldr.height == h && d.Ldr.format == fmt) return;
            Free(ref d.Ldr);
            d.Ldr = new RenderTexture(w, h, 0, fmt, RenderTextureReadWrite.Linear) { name = "vp " + d.Vp.Name, filterMode = FilterMode.Bilinear };
            d.Ldr.Create();
        }

        /// <summary>The 3D scene buffer: 32-bit float RGB like Godot Mobile's 32-bit RGB10A2 (same bandwidth), half floats
        /// when the viewport is transparent (alpha) or the GPU can't.</summary>
        static void EnsureHdr(VpData d, int w, int h)
        {
            var vp = d.Vp;
            int msaa = vp.Msaa3D == Viewport.MSAA_2X ? 2 : vp.Msaa3D == Viewport.MSAA_4X ? 4 : vp.Msaa3D == Viewport.MSAA_8X ? 8 : 1;
            var fmt = vp.TransparentBg || !SystemInfo.SupportsRenderTextureFormat(RenderTextureFormat.RGB111110Float) ? RenderTextureFormat.ARGBHalf : RenderTextureFormat.RGB111110Float;
            // (as many samples as the GPU takes for that format: 1 when it takes none)
            if (msaa > 1) msaa = Math.Max(1, SystemInfo.GetRenderTextureSupportedMSAASampleCount(new RenderTextureDescriptor(w, h, fmt, 24) { msaaSamples = msaa }));
            if (d.Hdr != null && d.Hdr.width == w && d.Hdr.height == h && d.Hdr.antiAliasing == msaa && d.Hdr.format == fmt) return;
            Free(ref d.Hdr);
            d.Hdr = new RenderTexture(w, h, 24, fmt) { antiAliasing = msaa, name = "vp-hdr " + vp.Name };
            d.Hdr.Create();
        }

        void UpdateCamera(VpData d)
        {
            var vp = d.Vp;
            bool isRoot = vp.Parent == null;
            bool inTree = vp.IsInsideTree();
            // this frame's update (SubViewport.render_target_update_mode; the root always draws)
            bool should = inTree;
            if (should && vp is SubViewport sv)
            {
                should = sv.ShouldRender();
                if (sv.RenderTargetUpdateMode == SubViewport.UpdateMode.Once)
                {
                    should = d.OnceSeen != sv.UpdateOnceCounter;
                    d.OnceSeen = sv.UpdateOnceCounter;
                }
            }
            var cam3d = vp.GetCamera3D();
            d.World = World(vp.FindWorld3D());
            bool render = should && cam3d != null && !vp.Disable3D && d.World != null;
            var size = vp.Get3DSize();
            int w = Math.Max(1, (int)size.x), h = Math.Max(1, (int)size.y);
            d.Rendered3D = render;
            d.Draw2D = should && !isRoot;
            if (render || d.Draw2D) EnsureLdr(d, w, h);
            var cam = d.Camera;
            cam.enabled = render;
            if (!render) return;
            EnsureHdr(d, w, h);
            Conv.Apply(d.Go.transform, cam3d.GetCameraTransform());
            cam.projectionMatrix = Conv.Projection(cam3d.GetCameraProjection());
            cam.nearClipPlane = (float)cam3d.Near;
            cam.farClipPlane = (float)cam3d.Far;
            cam.cullingMask = 1 << d.World.Layer;
            cam.targetTexture = d.Hdr;
            cam.allowMSAA = d.Hdr.antiAliasing > 1;
            var env = cam3d.Environment ?? d.World.World.Environment ?? d.World.World.FallbackEnvironment;
            d.Env = env;
            bool transparent = vp.TransparentBg;
            if (transparent) { cam.clearFlags = CameraClearFlags.SolidColor; cam.backgroundColor = new Color(0, 0, 0, 0); }
            else if (env != null && env.BackgroundMode == Environment.BG_SKY && env.Sky != null)
            {
                cam.clearFlags = CameraClearFlags.Skybox;
            }
            else
            {
                cam.clearFlags = CameraClearFlags.SolidColor;
                Col bg = env != null && env.BackgroundMode == Environment.BG_COLOR ? env.BackgroundColor * (float)env.BackgroundEnergyMultiplier : DefaultClearColor;
                cam.backgroundColor = new Color(bg.r, bg.g, bg.b, 1f);
            }
        }

        /// <summary>Godot's rendering/environment/defaults/default_clear_color (the project's).</summary>
        public static Col DefaultClearColor = new Col(0.3f, 0.3f, 0.3f, 1f);

        void OnBeginCamera(ScriptableRenderContext ctx, Camera cam)
        {
            if (!_byCamera.TryGetValue(cam, out var d)) return;
            var env = d.Env;
            // the world's Environment as the Fatebound shaders' globals
            Color amb = Color.black;
            if (env != null && env.AmbientLightSource != Environment.AMBIENT_SOURCE_DISABLED)
            {
                var a = env.AmbientLightColor;
                amb = new Color(a.r, a.g, a.b).linear * (float)env.AmbientLightEnergy;
            }
            Shader.SetGlobalVector("_FB_Ambient", amb);
            if (env != null && env.FogEnabled)
            {
                var f = env.FogLightColor;
                var fc = new Color(f.r, f.g, f.b).linear * (float)env.FogLightEnergy;
                Shader.SetGlobalVector("_FB_FogColor", new Vector4(fc.r, fc.g, fc.b, 1f));
                Shader.SetGlobalVector("_FB_FogParams", new Vector4((float)env.FogDensity, (float)env.FogSunScatter, (float)env.FogHeight, (float)env.FogHeightDensity));
                Shader.SetGlobalVector("_FB_FogDepth", new Vector4((float)env.FogDepthBegin, (float)env.FogDepthEnd, (float)env.FogDepthCurve, env.FogMode == Environment.FOG_MODE_DEPTH ? 1f : 0f));
            }
            else Shader.SetGlobalVector("_FB_FogColor", Vector4.zero);
            Shader.SetGlobalFloat("_FB_Time", (float)(Time.realtimeSinceStartupAsDouble % 3600.0));
            var c3 = d.Vp.GetCamera3D();
            SetDecals(d, c3 != null ? c3.GetCameraTransform() : Xform3.IDENTITY);
            if (cam.clearFlags == CameraClearFlags.Skybox)
            {
                // (an exception here would stop URP drawing the camera at all: the match came out grey)
                Material sky = null;
                try { sky = Materials.ForSky(env.Sky); }
                catch (Exception e) { Debug.LogException(e); }
                if (sky != null) RenderSettings.skybox = sky;
                else { cam.clearFlags = CameraClearFlags.SolidColor; cam.backgroundColor = new Color(DefaultClearColor.r, DefaultClearColor.g, DefaultClearColor.b, 1f); }
            }
        }

        void OnEndCamera(ScriptableRenderContext ctx, Camera cam)
        {
            if (!_byCamera.TryGetValue(cam, out var d)) return;
            PostChain.Render(ctx, d.Hdr, d.Ldr, d.Env, d.Vp.TransparentBg);
        }

        // ------------------------------------------------------------------ the frame
        /// <summary>Once a frame, after the SceneTree's iteration and before the GUI is drawn.</summary>
        public void Frame(double delta)
        {
            // (on the first frame: by then the game's loggers are listening)
            if (!_reported) { _reported = true; ReportShaders(); }
            // (each part timed for the match log: UnityRenderStats' d_*)
            long t = UnityRenderStats.Now;
            RenderSync.Flush();
            t = UnityRenderStats.Lap(UnityRenderStats.SYNC, t);
            Materials.Refresh();
            t = UnityRenderStats.Lap(UnityRenderStats.MAT, t);
            foreach (var d in _skinned) UpdateSkin(d);
            t = UnityRenderStats.Lap(UnityRenderStats.SKIN, t);
            foreach (var m in _multimeshes) DrawMultiMesh(m);
            t = UnityRenderStats.Lap(UnityRenderStats.MM, t);
            for (int i = 0; i < _viewports.Count; i++) UpdateCamera(_viewports[i]);
            t = UnityRenderStats.Lap(UnityRenderStats.CAM, t);
            ParticlesBridge.Frame(this, delta);
            t = UnityRenderStats.Lap(UnityRenderStats.PART, t);
            Meshes.Sweep();
            Materials.Sweep();
            UnityRenderStats.Lap(UnityRenderStats.SWEEP, t);
        }
    }
}
