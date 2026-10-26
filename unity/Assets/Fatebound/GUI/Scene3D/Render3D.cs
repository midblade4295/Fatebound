#if FB3D
// The seam between the engine-free 3D scene (Node3D and friends) and whatever draws it. Godot's nodes push their
// state to the RenderingServer; here the renderer pulls: a node that changed what's drawn marks itself in RenderSync
// (with bits saying what changed), and once a frame the host's renderer (the Unity client's) takes the marked set and
// reads the nodes and resources directly. Headless (tests, the .NET server) there is no renderer and nothing is kept.
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    /// <summary>A 3D world (Godot's World3D): the scene a viewport's camera sees. Viewports share their parent's unless
    /// own_world_3d is set.</summary>
    public sealed class World3D : Resource
    {
        static int _next;
        public readonly int Id = ++_next;
        Environment _env, _fallback;
        public Environment Environment { get => _env; set { _env = value; RenderSync.MarkWorld(this); } }
        public Environment FallbackEnvironment { get => _fallback; set { _fallback = value; RenderSync.MarkWorld(this); } }
        /// <summary>The renderer's own data for this world (its scene root, lighting state...).</summary>
        public object BackendData;
        internal readonly List<WorldEnvironment> worldEnvironments = new List<WorldEnvironment>();
        internal readonly List<Light3D> directionalLights = new List<Light3D>();
        public override string ToString() => "World3D#" + Id;
    }

    /// <summary>What changed on a render node since the renderer last looked.</summary>
    [Flags]
    public enum RenderDirty
    {
        None = 0,
        Created = 1,          // entered a world (or moved to another one)
        Transform = 2,        // global transform
        Visibility = 4,       // visible in tree
        Base = 8,             // what it draws: mesh, multimesh, light type, camera projection, particles setup...
        Material = 16,        // material override / overlay / surface overrides
        Params = 32,          // instance shader parameters, cast shadow, transparency, layers and other flags
        Pose = 64,            // a skeleton's bone pose (skinned meshes), a particle restart, a multimesh's instances
        All = 0x7fffffff,
    }

    /// <summary>The renderer the host plugs in (the Unity client's). Called on the main thread.</summary>
    public interface IRenderer3D
    {
        /// <summary>A node entered a world or changed: read it. `bits` says what changed (All for a new one).</summary>
        void Sync(Node3D node, RenderDirty bits);
        /// <summary>A node left its world (or was freed): drop what was made for it (its BackendData).</summary>
        void Remove(Node3D node, object backendData);
        /// <summary>A world's environment or settings changed.</summary>
        void SyncWorld(World3D world);
        /// <summary>A viewport's 3D settings changed (size, world, camera, msaa, update mode...).</summary>
        void SyncViewport(Viewport vp);
        void RemoveViewport(Viewport vp, object backendData);
    }

    public static class RenderSync
    {
        /// <summary>Null when nothing draws (headless): then nothing is recorded.</summary>
        public static IRenderer3D Renderer;

        static readonly Dictionary<Node3D, RenderDirty> _dirty = new Dictionary<Node3D, RenderDirty>();
        static readonly List<(Node3D node, object data)> _removed = new List<(Node3D, object)>();
        static readonly HashSet<World3D> _worlds = new HashSet<World3D>();
        static readonly HashSet<Viewport> _viewports = new HashSet<Viewport>();
        static readonly List<(Viewport vp, object data)> _removedVps = new List<(Viewport, object)>();

        public static bool Active => Renderer != null;

        public static void Mark(Node3D n, RenderDirty bits)
        {
            if (Renderer == null) return;
            _dirty.TryGetValue(n, out var b);
            _dirty[n] = b | bits;
        }

        internal static void Removed(Node3D n)
        {
            if (Renderer == null) return;
            _dirty.Remove(n);
            if (n.BackendData != null)
            {
                _removed.Add((n, n.BackendData));
                n.BackendData = null;
            }
        }

        public static void MarkWorld(World3D w) { if (Renderer != null) _worlds.Add(w); }
        public static void MarkViewport(Viewport vp) { if (Renderer != null) _viewports.Add(vp); }

        internal static void RemovedViewport(Viewport vp)
        {
            if (Renderer == null) return;
            _viewports.Remove(vp);
            if (vp.BackendData != null)
            {
                _removedVps.Add((vp, vp.BackendData));
                vp.BackendData = null;
            }
        }

        static readonly List<KeyValuePair<Node3D, RenderDirty>> _batch = new List<KeyValuePair<Node3D, RenderDirty>>();

        /// <summary>The renderer's once-a-frame pass (after the SceneTree's iteration): removals first, then worlds,
        /// viewports and every marked node.</summary>
        public static void Flush()
        {
            var r = Renderer;
            if (r == null) return;
            foreach (var (node, data) in _removed) r.Remove(node, data);
            _removed.Clear();
            foreach (var (vp, data) in _removedVps) r.RemoveViewport(vp, data);
            _removedVps.Clear();
            if (_worlds.Count > 0)
            {
                var ws = new List<World3D>(_worlds);
                _worlds.Clear();
                foreach (var w in ws) r.SyncWorld(w);
            }
            if (_viewports.Count > 0)
            {
                var vps = new List<Viewport>(_viewports);
                _viewports.Clear();
                foreach (var vp in vps) r.SyncViewport(vp);
            }
            if (_dirty.Count > 0)
            {
                _batch.Clear();
                _batch.AddRange(_dirty);
                _dirty.Clear();
                foreach (var kv in _batch)
                    if (kv.Key.IsInsideTree() && !kv.Key.IsFreed) r.Sync(kv.Key, kv.Value);
                _batch.Clear();
            }
        }
    }
}

#endif
