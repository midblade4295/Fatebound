#if FB3D
// Fatebound GUI (Unity port): the baked Godot scenes and resources -- load("res://assets/kaykit/heroes/Knight.glb")
// gives a PackedScene whose instantiate() builds the node tree Godot builds (names, Node3D/Skeleton3D/MeshInstance3D/
// AnimationPlayer layout, transforms, skins, materials, animation libraries), load("...anims_g.res") the AnimationLibrary.
// Engine-free: the bytes come from the host (ReadFile), everything else is plain C#.
//
// The files: unity/tools/bake/bake_resources.gd runs Godot headless on the game's project, loads every .glb .gltf .scn
// .tscn .res .tres under res://assets (with Godot's import cache: the values are the imported ones) and writes
// Assets/Resources/res/<path>.bytes = var_to_bytes(D) (decoded here with GMarshal), D a Dictionary without Objects:
//   "bake": 1, "path", "type": "PackedScene" or the main resource's class,
//   "resources": [{"class", "name"?, "script"?, "props": {stored property: value}, "surfaces"? (ArrayMesh)}...]
//                dependencies first; props are the stored properties that differ from Godot's class defaults,
//   "main": index (resource files), "nodes": [{"class", "name", "parent", "owner", "props", "groups"?, "script"?}...]
//                (scenes: the tree Godot's instantiate() gives, pre-order).
//   Objects inside values: {"@res": i} (resources[i]), {"@ext": "res://path", "@type"} (a resource with its own file:
//   load()ed -- textures, other baked files), {"@node": "path from the scene root"}.
//   ArrayMesh "surfaces": [{"primitive", "format", "aabb", "arrays" (surface_get_arrays), "blend_shapes"?, "material"?, "name"?}].
//   _baked/manifest.json lists every baked path (ResourceLoader.exists answers from it).
//
// Building: every resource of the file is created (by Godot class name: the facade's classes carry Godot's names; a
// script resource by its script's ported class, see RegisterScript) and then filled in table order; each property goes
// to SetStoredProperty(name, value) first (Godot's _set: "bones/3/rest", "tracks/0/keys", "bind/2/pose", "_data"...),
// otherwise to the C# member named like it (snake_case -> PascalCase, then the exact name; cached per type), the value
// converted to the member's type (bool/int/float/enum from numbers, NodePath from strings, Transform3D/Basis/Quaternion/
// AABB/Plane/Vector4/Vector3i decoded as the port's structs, arrays, resources). "metadata/x" -> set_meta on nodes
// (dropped on resources: the facade's Resource has no metadata). Whatever the port can't take is reported once
// (GD.PushWarning) and listed in BakedLoader.Unmapped.
// PackedScene.Instantiate(): fresh nodes each call (the resources are the file's, shared, as in Godot), in Godot's order
// (SceneState::instantiate: create, set properties, groups, add to the parent, set the owner; node references last).
// Threads: Load runs on a worker for ResourceLoader.load_threaded_request (no node is created there -- a scene's nodes are
// made by instantiate(), on the caller's thread); textures it references are created unresolved and load from the host
// on first use (LoadedTexture), the file bytes come through the main thread (ResourceLoader.ReadHostFile).
using System;
using System.Collections;
using System.Collections.Generic;
using System.Reflection;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    /// <summary>Godot's PackedScene: a baked scene (its nodes as data, its resources built) -- instantiate() makes the tree.</summary>
    public partial class PackedScene : Resource
    {
        public const int GEN_EDIT_STATE_DISABLED = 0, GEN_EDIT_STATE_INSTANCE = 1, GEN_EDIT_STATE_MAIN = 2, GEN_EDIT_STATE_MAIN_INHERITED = 3;
        internal BakedLoader.NodeEntry[] nodes = Array.Empty<BakedLoader.NodeEntry>();

        public bool CanInstantiate() => nodes.Length > 0;
        public Node Instantiate(int editState = GEN_EDIT_STATE_DISABLED) => BakedLoader.Instantiate(this);
        public T Instantiate<T>(int editState = GEN_EDIT_STATE_DISABLED) where T : Node => Instantiate(editState) as T;
        /// <summary>Nodes the scene creates (SceneState.get_node_count()).</summary>
        public int GetNodeCount() => nodes.Length;
    }

    /// <summary>A baked resource whose script has no ported class (yet): the script's stored properties by name
    /// (res://assets/terrain/cache.res, a SiegeTerrainCache: key, terrain, outer, foliage, outer_trees, blood).</summary>
    public sealed class BakedScriptResource : Resource
    {
        public string Script = "";
        public readonly GDict Properties = new GDict();
        /// <summary>get(name) (Nil when the file didn't store it: it had the script's default).</summary>
        public Var Get(string name) => Properties.Has(name) ? Properties[name] : Var.Nil;
        public void Set(string name, Var value) => Properties[name] = value;
    }

    public static class BakedLoader
    {
        public const int BAKE_VERSION = 1;
        public const string MANIFEST = "res://_baked/manifest.json";
        static readonly HashSet<string> Exts = new HashSet<string> { ".glb", ".gltf", ".scn", ".tscn", ".res", ".tres" };

        /// <summary>Whether the path is a baked format (by extension).</summary>
        public static bool Handles(string path)
        {
            int dot = path.LastIndexOf('.');
            return dot >= 0 && Exts.Contains(path.Substring(dot).ToLowerInvariant());
        }

        // ------------------------------------------------------------------ manifest (exists())
        static HashSet<string> _manifest;
        static bool _manifestTried;
        static readonly object _manifestLock = new object();

        /// <summary>Whether the bake has the path (null: no manifest -- ask the host).</summary>
        public static bool? InManifest(string path)
        {
            lock (_manifestLock)
            {
                if (!_manifestTried)
                {
                    _manifestTried = true;
                    var bytes = ResourceLoader.ReadHostFile(MANIFEST);
                    if (bytes != null)
                    {
                        var d = JSON.ParseString(System.Text.Encoding.UTF8.GetString(bytes)).AsDict();
                        var files = d != null && d.Has("files") ? d["files"].AsArr() : null;
                        if (files != null)
                        {
                            _manifest = new HashSet<string>();
                            foreach (var f in files) _manifest.Add(f.AsString());
                        }
                    }
                }
                return _manifest == null ? (bool?)null : _manifest.Contains(path);
            }
        }

        /// <summary>Forget the manifest (tests that bake while running).</summary>
        public static void ResetManifest() { lock (_manifestLock) { _manifest = null; _manifestTried = false; } }

        // ------------------------------------------------------------------ script classes
        static readonly Dictionary<string, Func<object>> _scripts = new Dictionary<string, Func<object>>();
        static readonly Dictionary<string, Type> _scriptTypes = new Dictionary<string, Type>();

        /// <summary>The ported class of a script ("res://scripts/siege/terrain_cache.gd" -> new TerrainCache()) for baked
        /// objects that have it attached. Without a registration the porting guide's name is tried (Fatebound.Game.
        /// &lt;PascalCased file name&gt;, in any loaded assembly); without either a resource becomes a BakedScriptResource.</summary>
        public static void RegisterScript(string scriptPath, Func<object> factory)
        {
            lock (_scripts) _scripts[scriptPath] = factory;
        }

        static object NewScriptObject(string script)
        {
            Func<object> f;
            lock (_scripts) _scripts.TryGetValue(script, out f);
            if (f != null) return f();
            Type t;
            lock (_scriptTypes)
            {
                if (!_scriptTypes.TryGetValue(script, out t))
                {
                    string stem = script.Substring(script.LastIndexOf('/') + 1);
                    int dot = stem.LastIndexOf('.');
                    if (dot > 0) stem = stem.Substring(0, dot);
                    string full = "Fatebound.Game." + PropertyPath.Pascal(stem);
                    foreach (var asm in AppDomain.CurrentDomain.GetAssemblies())
                    {
                        try { t = asm.GetType(full, false); }
                        catch (Exception) { t = null; }
                        if (t != null) break;
                    }
                    _scriptTypes[script] = t;
                }
            }
            return t != null ? Activator.CreateInstance(t) : null;
        }

        // ------------------------------------------------------------------ engine classes
        static Dictionary<string, Type> _types;
        // Godot class -> the facade class, where the names differ
        static readonly Dictionary<string, string> Aliases = new Dictionary<string, string> { { "Material", "GMaterial" } };

        static Type EngineType(string cls)
        {
            lock (Exts)
            {
                if (_types == null)
                {
                    _types = new Dictionary<string, Type>();
                    foreach (var t in typeof(Node).Assembly.GetTypes())
                        if (t.IsPublic && !t.IsAbstract && t.Namespace == typeof(Node).Namespace && t.GetConstructor(Type.EmptyTypes) != null &&
                            (typeof(Node).IsAssignableFrom(t) || typeof(Resource).IsAssignableFrom(t)))
                            _types[t.Name] = t;
                }
                if (Aliases.TryGetValue(cls, out var a)) cls = a;
                return _types.TryGetValue(cls, out var r) ? r : null;
            }
        }

        // ------------------------------------------------------------------ what the port can't map (reported once)
        static readonly HashSet<string> _unmapped = new HashSet<string>();

        /// <summary>"Class.property" / "class Class" the loader met and couldn't map, so far.</summary>
        public static List<string> Unmapped { get { lock (_unmapped) { var l = new List<string>(_unmapped); l.Sort(StringComparer.Ordinal); return l; } } }

        static void Report(string what, string detail)
        {
            lock (_unmapped)
            {
                if (!_unmapped.Add(what)) return;
            }
            GD.PushWarning("baked asset: " + what + " " + detail);
        }

        // ------------------------------------------------------------------ loading
        sealed class FileCtx
        {
            public string path;
            public Resource[] res;
        }

        /// <summary>A node reference inside a scene's property ({"@node": path}), resolved when instantiated.</summary>
        internal sealed class NodeRef { public string path; }

        internal sealed class NodeEntry
        {
            public string cls, name, script;
            public Type type;
            public int parent, owner;
            public string[] keys;
            public Var[] values;
            public string[] groups;
        }

        static int _decoded, _decodedOffMain;
        /// <summary>Files decoded so far, and how many of them on a worker thread (tests).</summary>
        public static int FilesDecoded => _decoded;
        public static int FilesDecodedOffMain => _decodedOffMain;

        /// <summary>Loads a baked file (ResourceLoader.LoadUncached: any thread). Null (and an error) when it's missing.</summary>
        public static Resource Load(string path)
        {
            System.Threading.Interlocked.Increment(ref _decoded);
            if (!PlatformHost.IsMainThread) System.Threading.Interlocked.Increment(ref _decodedOffMain);
            byte[] bytes = ResourceLoader.ReadHostFile(path);
            if (bytes == null)
            {
                GD_Log.Error("load: " + path + " was not baked (run unity/tools/bake/bake.sh)");
                return null;
            }
            var root = GMarshal.BytesToVar(bytes).AsDict();
            if (root == null || root.Get("bake", 0).AsInt() != BAKE_VERSION)
            {
                GD_Log.Error("load: " + path + ": not a bake " + BAKE_VERSION + " file (re-run unity/tools/bake/bake.sh)");
                return null;
            }
            var ctx = new FileCtx { path = path };
            var entries = root["resources"].AsArr() ?? new GArray();
            ctx.res = new Resource[entries.Size()];
            for (int i = 0; i < ctx.res.Length; i++) ctx.res[i] = Create(entries[i].AsDict());
            for (int i = 0; i < ctx.res.Length; i++) Fill(ctx, ctx.res[i], entries[i].AsDict());
            if (root["type"].AsString() == "PackedScene")
            {
                var ps = new PackedScene();
                var ns = root["nodes"].AsArr() ?? new GArray();
                ps.nodes = new NodeEntry[ns.Size()];
                for (int i = 0; i < ps.nodes.Length; i++) ps.nodes[i] = ReadNode(ctx, ns[i].AsDict());
                return ps;
            }
            int main = root.Get("main", -1).AsInt();
            return main >= 0 && main < ctx.res.Length ? ctx.res[main] : null;
        }

        static Resource Create(GDict e)
        {
            string cls = e["class"].AsString();
            string script = e.Get("script", "").AsString();
            if (script != "")
            {
                var so = NewScriptObject(script);
                if (so is Resource sr) return sr;
                if (so != null) Report("script " + script, "has a class that is not a Resource: ignored");
                if (cls == "Resource") return new BakedScriptResource { Script = script };
                Report("script " + script, "(on a " + cls + ") has no ported class: the " + cls + " is loaded without it");
            }
            var t = EngineType(cls);
            if (t == null || !typeof(Resource).IsAssignableFrom(t))
            {
                Report("class " + cls, "is not in the port: loaded as null");
                return null;
            }
            return (Resource)Activator.CreateInstance(t);
        }

        static void Fill(FileCtx ctx, Resource r, GDict e)
        {
            if (r == null) return;
            string cls = e["class"].AsString();
            if (e.Has("name")) r.ResourceName = e["name"].AsString();
            var props = e["props"].AsDict();
            if (props != null)
                foreach (var k in props.Keys())
                    SetProperty(r, cls, k.AsString(), Resolve(ctx, props[k]));
            if (e.Has("surfaces"))
            {
                if (r is ArrayMesh am) AddSurfaces(ctx, am, e["surfaces"].AsArr());
                else Report(cls + ".surfaces", "on a class that isn't an ArrayMesh in the port");
            }
        }

        static void AddSurfaces(FileCtx ctx, ArrayMesh m, GArray surfaces)
        {
            if (surfaces == null) return;
            foreach (var sv in surfaces)
            {
                var s = sv.AsDict();
                var prim = (PrimitiveType)s["primitive"].AsInt();
                uint fmt = unchecked((uint)s["format"].AsLong());
                var arrays = s["arrays"].AsArr();
                if (arrays == null) continue;
                var surf = Mesh.SurfaceFromArrays(prim, arrays, fmt);
                if (surf.Vertices == null) { GD.PushError("baked mesh in " + ctx.path + ": a surface without vertices"); continue; }
                if (s.Has("blend_shapes"))
                {
                    surf.BlendShapes = new List<MeshSurface>();
                    foreach (var b in s["blend_shapes"].AsArr() ?? new GArray())
                        if (b.AsArr() is GArray ba) surf.BlendShapes.Add(Mesh.SurfaceFromArrays(prim, ba, fmt));
                }
                if (s.Has("aabb") && Resolve(ctx, s["aabb"]).Obj is Aabb box) surf.Aabb = box;     // (Godot's: blend shapes included)
                if (s.Has("material")) surf.Material = Resolve(ctx, s["material"]).Obj as GMaterial;
                if (s.Has("name")) surf.Name = s["name"].AsString();
                m.AddSurface(surf);
            }
        }

        static NodeEntry ReadNode(FileCtx ctx, GDict e)
        {
            var n = new NodeEntry
            {
                cls = e["class"].AsString(),
                name = e["name"].AsString(),
                script = e.Get("script", "").AsString(),
                parent = e.Get("parent", -1).AsInt(),
                owner = e.Get("owner", -1).AsInt(),
            };
            n.type = EngineType(n.cls);
            if (n.type == null || !typeof(Node).IsAssignableFrom(n.type))
            {
                Report("class " + n.cls, "is not in the port: instantiated as a " + (n.cls.EndsWith("3D") ? "Node3D" : "Node"));
                n.type = n.cls.EndsWith("3D") ? typeof(Node3D) : typeof(Node);
            }
            var props = e["props"].AsDict() ?? new GDict();
            n.keys = new string[props.Size()];
            n.values = new Var[props.Size()];
            int i = 0;
            foreach (var k in props.Keys())
            {
                n.keys[i] = k.AsString();
                n.values[i] = Resolve(ctx, props[k]);
                i++;
            }
            if (e.Has("groups"))
            {
                var g = e["groups"].AsArr();
                n.groups = new string[g.Size()];
                for (int j = 0; j < g.Size(); j++) n.groups[j] = g[j].AsString();
            }
            return n;
        }

        internal static Node Instantiate(PackedScene ps)
        {
            var en = ps.nodes;
            if (en.Length == 0) { GD.PushError("Can't instantiate a PackedScene without nodes."); return null; }
            var nodes = new Node[en.Length];
            List<(Node, string, string, NodePath)> refs = null;
            for (int i = 0; i < en.Length; i++)
            {
                var e = en[i];
                Node node = null;
                if (e.script != "")
                {
                    var so = NewScriptObject(e.script);
                    node = so as Node;
                    if (node == null) Report("script " + e.script, "(on a " + e.cls + " node) has no ported Node class: the node is made without it");
                }
                if (node == null) node = (Node)Activator.CreateInstance(e.type);
                node.Name = e.name;
                for (int k = 0; k < e.keys.Length; k++)
                {
                    if (e.values[k].Obj is NodeRef nr)
                    {
                        (refs ?? (refs = new List<(Node, string, string, NodePath)>())).Add((node, e.cls, e.keys[k], new NodePath(nr.path)));
                        continue;
                    }
                    SetProperty(node, e.cls, e.keys[k], e.values[k]);
                }
                if (e.groups != null) foreach (var g in e.groups) node.AddToGroup(g);
                if (i > 0)
                {
                    if (e.parent >= 0 && e.parent < i) nodes[e.parent].AddChild(node);
                    else GD.PushError("baked scene " + ps.ResourcePath + ": node " + e.name + " has no parent");
                }
                if (e.owner >= 0 && e.owner < i) node.Owner = nodes[e.owner];
                nodes[i] = node;
            }
            if (refs != null)
                foreach (var (node, cls, prop, path) in refs)
                    SetProperty(node, cls, prop, Var.Of(nodes[0].GetNodeOrNull(path.ToString())));
            return nodes[0];
        }

        // ------------------------------------------------------------------ values
        /// <summary>A decoded value with the bake's object markers replaced (resources, external files, node refs) and
        /// Godot's math types as the port's structs.</summary>
        static Var Resolve(FileCtx ctx, Var v)
        {
            switch (v.Type)
            {
                case VT.Dict:
                {
                    var d = v.AsDict();
                    if (d.Size() == 1 && d.Has("@res"))
                    {
                        int i = d["@res"].AsInt();
                        return i >= 0 && i < ctx.res.Length ? Var.Of(ctx.res[i]) : Var.Nil;
                    }
                    if (d.Has("@ext") && d.Size() <= 2) return Var.Of(LoadExternal(d["@ext"].AsString()));
                    if (d.Size() == 1 && d.Has("@node")) return Var.Of(new NodeRef { path = d["@node"].AsString() });
                    var o = new GDict();
                    foreach (var k in d.Keys()) o[Resolve(ctx, k)] = Resolve(ctx, d[k]);
                    return o;
                }
                case VT.Arr:
                {
                    var a = v.AsArr();
                    var o = new GArray();
                    foreach (var x in a) o.Append(Resolve(ctx, x));
                    return o;
                }
                case VT.Obj:
                    if (v.Obj is GValue g) return Normalize(g);
                    return v;
            }
            return v;
        }

        static Resource LoadExternal(string path)
        {
            if (path.EndsWith(".gd") || path.EndsWith(".cs")) return null;      // (scripts are classes in the port)
            var r = ResourceLoader.Load(path);
            if (r == null) Report("file " + path, "(referenced by a baked file) could not be loaded");
            return r;
        }

        static Var Normalize(GValue g)
        {
            var c = g.C;
            float F(int i) => (float)c[i];
            switch (g.Type)
            {
                case GD.TYPE_QUATERNION: return Var.Of(new Quat(c[0], c[1], c[2], c[3]));
                case GD.TYPE_BASIS: return Var.Of(Basis.FromRows(F(0), F(1), F(2), F(3), F(4), F(5), F(6), F(7), F(8)));
                case GD.TYPE_TRANSFORM3D: return Var.Of(new Xform3(Basis.FromRows(F(0), F(1), F(2), F(3), F(4), F(5), F(6), F(7), F(8)), new Vec3(F(9), F(10), F(11))));
                case GD.TYPE_AABB: return Var.Of(new Aabb(new Vec3(F(0), F(1), F(2)), new Vec3(F(3), F(4), F(5))));
                case GD.TYPE_PLANE: return Var.Of(new Plane(c[0], c[1], c[2], c[3]));
                case GD.TYPE_VECTOR3I: return Var.Of(new Vec3i((int)c[0], (int)c[1], (int)c[2]));
                case GD.TYPE_VECTOR4: return Var.Of(new Vec4(c[0], c[1], c[2], c[3]));
                case GD.TYPE_VECTOR4I: return Var.Of(new Vec4i((int)c[0], (int)c[1], (int)c[2], (int)c[3]));
                case GD.TYPE_PROJECTION:
                    return Var.Of(new Projection(new Vec4(c[0], c[1], c[2], c[3]), new Vec4(c[4], c[5], c[6], c[7]), new Vec4(c[8], c[9], c[10], c[11]), new Vec4(c[12], c[13], c[14], c[15])));
            }
            return Var.Of(g);
        }

        // ------------------------------------------------------------------ properties
        sealed class Member
        {
            public Type type;
            public Action<object, object> set;
        }

        static readonly Dictionary<(Type, string), Member> _members = new Dictionary<(Type, string), Member>();

        static Member FindMember(Type t, string name)
        {
            lock (_members)
            {
                if (_members.TryGetValue((t, name), out var m)) return m;
                const BindingFlags F = BindingFlags.Instance | BindingFlags.Public | BindingFlags.FlattenHierarchy;
                foreach (var n in new[] { PropertyPath.Pascal(name), name })
                {
                    var pi = t.GetProperty(n, F);
                    if (pi != null && pi.CanWrite && pi.GetSetMethod() != null && pi.GetIndexParameters().Length == 0)
                    {
                        m = new Member { type = pi.PropertyType, set = (o, v) => pi.SetValue(o, v) };
                        break;
                    }
                    var fi = t.GetField(n, F);
                    if (fi != null && !fi.IsInitOnly && !fi.IsLiteral)
                    {
                        m = new Member { type = fi.FieldType, set = (o, v) => fi.SetValue(o, v) };
                        break;
                    }
                }
                _members[(t, name)] = m;
                return m;
            }
        }

        /// <summary>Sets one stored property: SetStoredProperty, else the member by name (snake_case -> PascalCase).</summary>
        public static void SetProperty(object target, string cls, string name, Var value)
        {
            if (target is Resource r && r.SetStoredProperty(name, value)) return;
            if (target is Node n && n.SetStoredProperty(name, value)) return;
            if (name.StartsWith("metadata/"))
            {
                if (target is Node mn) mn.SetMeta(name.Substring(9), value.Obj);
                else Report(cls + ".metadata/*", "(resource metadata) is not kept: the port's Resource has no metadata");
                return;
            }
            if (target is BakedScriptResource bs) { bs.Properties[name] = value; return; }
            var m = FindMember(target.GetType(), name);
            if (m == null) { Report(cls + "." + name, "is not in the port (ignored)"); return; }
            if (!TryConvert(value, m.type, out object cv))
            {
                Report(cls + "." + name, "has a value the port's " + m.type.Name + " can't take (" + (value.Obj?.GetType().Name ?? "null") + "): ignored");
                return;
            }
            try { m.set(target, cv); }
            catch (TargetInvocationException e) { GD.PushError("baked " + cls + "." + name + ": " + e.InnerException?.Message); }
        }

        /// <summary>A Var as a C# member type (Godot's implicit conversions the stored values need).</summary>
        public static bool TryConvert(Var v, Type t, out object r)
        {
            r = null;
            if (t == typeof(Var)) { r = v; return true; }
            object o = v.Obj;
            var nt = Nullable.GetUnderlyingType(t);
            if (o == null) return !t.IsValueType || nt != null;
            if (nt != null) t = nt;
            if (t.IsInstanceOfType(o)) { r = o; return true; }
            bool num = v.IsNum || v.IsBool;
            if (t.IsEnum) { if (!num) return false; r = Enum.ToObject(t, v.AsLong()); return true; }
            switch (Type.GetTypeCode(t))
            {
                case TypeCode.Boolean: if (!num) return false; r = v.Truthy; return true;
                case TypeCode.Int32: if (!num) return false; r = unchecked((int)v.AsLong()); return true;
                case TypeCode.Int64: if (!num) return false; r = v.AsLong(); return true;
                case TypeCode.UInt32: if (!num) return false; r = unchecked((uint)v.AsLong()); return true;
                case TypeCode.UInt64: if (!num) return false; r = unchecked((ulong)v.AsLong()); return true;
                case TypeCode.Int16: if (!num) return false; r = unchecked((short)v.AsLong()); return true;
                case TypeCode.Byte: if (!num) return false; r = unchecked((byte)v.AsLong()); return true;
                case TypeCode.Single: if (!num) return false; r = (float)v.AsFloat(); return true;
                case TypeCode.Double: if (!num) return false; r = v.AsFloat(); return true;
                case TypeCode.String: if (!v.IsString) return false; r = v.AsString(); return true;
            }
            if (t == typeof(NodePath)) { if (!v.IsString) return false; r = new NodePath(v.AsString()); return true; }
            if (t == typeof(Vec3) && o is Vec3i i3) { r = new Vec3((float)i3.x, (float)i3.y, (float)i3.z); return true; }
            if (t == typeof(Vec2) && o is Vec2i i2) { r = new Vec2(i2.x, i2.y); return true; }
            if (t == typeof(Quat) && o is Basis qb) { r = qb.GetQuaternion(); return true; }
            if (t == typeof(GArray))
            {
                if (!(o is IEnumerable en) || o is string || o is GDict) return false;
                var ga = new GArray();
                foreach (var x in en) ga.Append(Var.Of(x));
                r = ga;
                return true;
            }
            if (t.IsArray || (t.IsGenericType && t.GetGenericTypeDefinition() == typeof(List<>)))
            {
                var et = t.IsArray ? t.GetElementType() : t.GetGenericArguments()[0];
                if (!(o is IEnumerable src) || o is string || o is GDict) return false;
                var list = (IList)Activator.CreateInstance(typeof(List<>).MakeGenericType(et));
                foreach (var x in src)
                {
                    if (!TryConvert(x is Var xv ? xv : Var.Of(x), et, out object ce)) return false;
                    list.Add(ce);
                }
                if (!t.IsArray) { r = list; return true; }
                var arr = Array.CreateInstance(et, list.Count);
                list.CopyTo(arr, 0);
                r = arr;
                return true;
            }
            return false;
        }
    }
}

#endif
