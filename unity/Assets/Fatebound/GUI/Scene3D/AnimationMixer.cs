#if FB3D
// Godot's AnimationMixer (scene/animation/animation_mixer.cpp, 4.7): animation libraries ("lib/anim" names, the ""
// library without prefix), the track caches (one per track path and cache type, built from every animation the mixer
// has: a 3D transform cache per bone/node with its rest as the initial value, value caches, method caches), and the
// blending pipeline run each process step: _blend_init -> _blend_pre_process (the player makes its animation instances)
// -> _blend_calc_total_weight -> _blend_process (each instance's tracks interpolated and accumulated: positions/scales
// as weighted offsets from the rest, rotations with interpolate_via_rest; non-deterministic blending normalizes by each
// track's total weight, so a track only one of the blended animations has shows that animation fully, and a track no
// playing animation has keeps its last pose) -> _blend_apply (bone poses set on the Skeleton3D, Node3D transforms,
// value-track properties) -> _blend_post_process.
//
// Processing: IDLE advances in the node's internal process (so a mixer whose process mode is DISABLED, or paused out,
// doesn't advance -- the game pauses off-screen bodies that way), PHYSICS at each physics tick (SceneTree.PhysicsFrame,
// before the physics nodes rather than in tree order), MANUAL only in Advance(). Track caches are bound to bone indices
// once (until the caches are cleared, as Godot: stop/pause, active=false, library or animation changes, entering or
// leaving the tree); a frame's processing allocates nothing for 3D transform tracks, and each track remembers its last
// key index so the key search starts there (same result as Godot's binary search).
//
// Not ported (the game doesn't use them): root motion, capture (UPDATE_CAPTURE value tracks / play_with_capture blend
// in nothing), audio and animation-playback tracks (kept as data, skipped), blend shape tracks (no blend shapes on the
// facade's MeshInstance3D), the _post_process_key_value script hook, the RESET-on-save editor features. Method tracks
// call the method through MethodCallHook or by reflection (PascalCase of the name). Value tracks set the property
// through fast paths for Node3D transforms, visibility and ShaderMaterial parameters, else by reflection (PropertyPath).
using System;
using System.Collections.Generic;
using System.Reflection;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    /// <summary>A hash map that iterates in insertion order and erases by moving the last entry into the hole (Godot's
    /// AHashMap: the mixer's caches and animation set iterate in that order).</summary>
    internal sealed class OrderedMap<K, V>
    {
        readonly List<K> _keys = new List<K>();
        readonly List<V> _values = new List<V>();
        readonly Dictionary<K, int> _index;

        public OrderedMap(IEqualityComparer<K> cmp = null) { _index = new Dictionary<K, int>(cmp ?? EqualityComparer<K>.Default); }

        public int Count => _keys.Count;
        public K KeyAt(int i) => _keys[i];
        public V ValueAt(int i) => _values[i];
        public bool ContainsKey(K k) => _index.ContainsKey(k);

        public bool TryGetValue(K k, out V v)
        {
            if (_index.TryGetValue(k, out int i)) { v = _values[i]; return true; }
            v = default;
            return false;
        }

        public void Set(K k, V v)
        {
            if (_index.TryGetValue(k, out int i)) { _values[i] = v; return; }
            _index[k] = _keys.Count;
            _keys.Add(k);
            _values.Add(v);
        }

        public bool Remove(K k)
        {
            if (!_index.TryGetValue(k, out int i)) return false;
            _index.Remove(k);
            int last = _keys.Count - 1;
            if (i < last)
            {
                _keys[i] = _keys[last];
                _values[i] = _values[last];
                _index[_keys[i]] = i;
            }
            _keys.RemoveAt(last);
            _values.RemoveAt(last);
            return true;
        }

        public void Clear()
        {
            _keys.Clear();
            _values.Clear();
            _index.Clear();
        }
    }

    public class AnimationMixer : Node
    {
        public enum AnimationCallbackModeProcess { Physics = 0, Idle = 1, Manual = 2 }
        public enum AnimationCallbackModeMethod { Deferred = 0, Immediate = 1 }
        public enum AnimationCallbackModeDiscrete { Dominant = 0, Recessive = 1, ForceContinuous = 2 }
        public const AnimationCallbackModeProcess ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS = AnimationCallbackModeProcess.Physics,
            ANIMATION_CALLBACK_MODE_PROCESS_IDLE = AnimationCallbackModeProcess.Idle, ANIMATION_CALLBACK_MODE_PROCESS_MANUAL = AnimationCallbackModeProcess.Manual;
        public const AnimationCallbackModeMethod ANIMATION_CALLBACK_MODE_METHOD_DEFERRED = AnimationCallbackModeMethod.Deferred,
            ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE = AnimationCallbackModeMethod.Immediate;
        public const AnimationCallbackModeDiscrete ANIMATION_CALLBACK_MODE_DISCRETE_DOMINANT = AnimationCallbackModeDiscrete.Dominant,
            ANIMATION_CALLBACK_MODE_DISCRETE_RECESSIVE = AnimationCallbackModeDiscrete.Recessive,
            ANIMATION_CALLBACK_MODE_DISCRETE_FORCE_CONTINUOUS = AnimationCallbackModeDiscrete.ForceContinuous;

        /// <summary>Method-track calls: (target, method, args) -> handled. Unset (or false): reflection on the target
        /// (the PascalCase method, else the exact name, with as many parameters as args).</summary>
        public static Func<object, string, Var[], bool> MethodCallHook;

        // ------------------------------------------------------------------ data lists
        internal sealed class LibraryData
        {
            public string name;
            public AnimationLibrary library;
            public Action<string> added, removed, changed;
            public Action<string, string> renamed;
        }

        internal sealed class AnimationData
        {
            public Animation animation;
            public string library;
            public ulong lastUpdate;
        }

        internal readonly List<LibraryData> animationLibraries = new List<LibraryData>();
        internal readonly OrderedMap<string, AnimationData> animationSet = new OrderedMap<string, AnimationData>(StringComparer.Ordinal);
        ulong _animationSetUpdatePass = 1;

        public event Action AnimationListChanged, AnimationLibrariesUpdated, CachesCleared, MixerApplied, MixerUpdated;
        public event Action<string> AnimationStarted, AnimationFinished;
        protected void EmitAnimationStarted(string n) => AnimationStarted?.Invoke(n);
        protected void EmitAnimationFinished(string n) => AnimationFinished?.Invoke(n);

        // ------------------------------------------------------------------ settings
        protected AnimationCallbackModeProcess callbackModeProcess = AnimationCallbackModeProcess.Idle;
        protected AnimationCallbackModeMethod callbackModeMethod = AnimationCallbackModeMethod.Deferred;
        protected AnimationCallbackModeDiscrete callbackModeDiscrete = AnimationCallbackModeDiscrete.Recessive;
        NodePath _rootNode = new NodePath("..");
        protected bool processing;
        protected bool active = true;
        bool _deterministic;
        readonly InternalPhysicsProcess _physics;
        bool _warnedRoot;

        // ------------------------------------------------------------------ caches
        protected bool cacheValid;
        ulong _setupPass = 1;

        internal struct CacheKey : IEquatable<CacheKey>
        {
            public readonly string path;
            public readonly Animation.TrackType type;
            public CacheKey(string p, Animation.TrackType t) { path = p; type = t; }
            public bool Equals(CacheKey o) => type == o.type && string.Equals(path, o.path, StringComparison.Ordinal);
            public override bool Equals(object o) => o is CacheKey k && Equals(k);
            public override int GetHashCode() => (path?.GetHashCode() ?? 0) * 31 + (int)type;
        }

        internal class TrackCache
        {
            public ulong setupPass;
            public Animation.TrackType type;
            public NodePath path;
            public int blendIdx = -1;
            public object obj;
            public float totalWeight;
            public ulong weightAppliedAt;
            public bool ObjectGone => obj == null || (obj is Node n && n.IsFreed);
        }

        internal sealed class TrackCacheTransform : TrackCache
        {
            public Skeleton3D skeleton;
            public int boneIdx = -1;
            public bool locUsed, rotUsed, scaleUsed;
            public Vec3 initLoc, loc;
            public Quat initRot = Quat.IDENTITY, rot = Quat.IDENTITY;
            public Vec3 initScale = new Vec3(1f, 1f, 1f), scale = new Vec3(1f, 1f, 1f);
            public TrackCacheTransform() { type = Animation.TrackType.Position3D; }
        }

        internal sealed class TrackCacheValue : TrackCache
        {
            public Var initValue, value, elementSize;
            public string[] subpath = Array.Empty<string>();
            public bool isInit, useContinuous, useDiscrete, isUsingAngle, isVariantInterpolatable = true;
            public ValueSetter setter;
            public TrackCacheValue() { type = Animation.TrackType.Value; }
        }

        internal sealed class TrackCacheMethod : TrackCache
        {
            public TrackCacheMethod() { type = Animation.TrackType.Method; }
        }

        readonly OrderedMap<CacheKey, TrackCache> _trackCache = new OrderedMap<CacheKey, TrackCache>();

        sealed class AnimBinding
        {
            public TrackCache[] caches = Array.Empty<TrackCache>();
            public int[] hints = Array.Empty<int>();
            public ulong pass;
        }

        readonly Dictionary<Animation, AnimBinding> _bindings = new Dictionary<Animation, AnimBinding>();
        ulong _bindingPass = 1;
        readonly Dictionary<string, int> _trackMap = new Dictionary<string, int>(StringComparer.Ordinal);
        int _trackCount;

        // ------------------------------------------------------------------ blending processor
        public struct PlaybackInfo
        {
            public double time, delta, start, end;
            public bool seeked, isExternalSeeking;
            public Animation.LoopedFlag loopedFlag;
            public float weight;
        }

        protected struct AnimationInstance
        {
            public Animation animation;
            public PlaybackInfo info;
        }

        readonly List<AnimationInstance> _instances = new List<AnimationInstance>();
        ulong _weightPassCounter;
        readonly List<int> _indices = new List<int>();

        public AnimationMixer()
        {
            _physics = new InternalPhysicsProcess(this, d =>
            {
                if (active && callbackModeProcess == AnimationCallbackModeProcess.Physics) ProcessAnimation(d);
            });
        }

        // ================================================================== libraries
        void AnimationSetCacheUpdate()
        {
            _animationSetUpdatePass++;
            bool clearNeeded = false;
            foreach (var lib in animationLibraries)
            {
                foreach (var kv in lib.library.Animations)
                {
                    string key = lib.name.Length == 0 ? kv.Key : lib.name + "/" + kv.Key;
                    if (!animationSet.TryGetValue(key, out var ad))
                    {
                        ad = new AnimationData { animation = kv.Value, library = lib.name, lastUpdate = _animationSetUpdatePass };
                        animationSet.Set(key, ad);
                        cacheValid = false;
                    }
                    else if (ad.lastUpdate != _animationSetUpdatePass)
                    {
                        if (ad.animation != kv.Value || ad.library != lib.name)
                        {
                            clearNeeded = true;
                            ad.animation = kv.Value;
                            ad.library = lib.name;
                        }
                        ad.lastUpdate = _animationSetUpdatePass;
                    }
                }
            }
            List<string> toErase = null;
            for (int i = 0; i < animationSet.Count; i++)
                if (animationSet.ValueAt(i).lastUpdate != _animationSetUpdatePass) (toErase ??= new List<string>()).Add(animationSet.KeyAt(i));
            if (toErase != null)
            {
                foreach (var k in toErase) animationSet.Remove(k);
                clearNeeded = true;
            }
            if (clearNeeded) ClearCachesInternal();
            AnimationListChanged?.Invoke();
        }

        protected virtual void OnAnimationAdded(string name, string library) => AnimationSetCacheUpdate();

        protected virtual void OnAnimationRemoved(string name, string library)
        {
            string full = library.Length == 0 ? name : library + "/" + name;
            if (!animationSet.ContainsKey(full)) return;
            AnimationSetCacheUpdate();
            OnRemoveAnimation(full);
        }

        protected virtual void OnAnimationRenamed(string name, string toName, string library)
        {
            string from = library.Length == 0 ? name : library + "/" + name;
            string to = library.Length == 0 ? toName : library + "/" + toName;
            if (!animationSet.ContainsKey(from)) return;
            AnimationSetCacheUpdate();
            OnRenameAnimation(from, to);
        }

        protected virtual void OnAnimationChanged(string name) => ClearCachesInternal();
        protected virtual void OnSetActive(bool active) { }
        protected virtual void OnRemoveAnimation(string name) { }
        protected virtual void OnRenameAnimation(string from, string to) { }

        void ConnectLibrary(LibraryData ld)
        {
            string ln = ld.name;
            ld.added = n => OnAnimationAdded(n, ln);
            ld.removed = n => OnAnimationRemoved(n, ln);
            ld.renamed = (a, b) => OnAnimationRenamed(a, b, ln);
            ld.changed = OnAnimationChanged;
            ld.library.AnimationAdded += ld.added;
            ld.library.AnimationRemoved += ld.removed;
            ld.library.AnimationRenamed += ld.renamed;
            ld.library.AnimationChanged += ld.changed;
        }

        static void DisconnectLibrary(LibraryData ld)
        {
            ld.library.AnimationAdded -= ld.added;
            ld.library.AnimationRemoved -= ld.removed;
            ld.library.AnimationRenamed -= ld.renamed;
            ld.library.AnimationChanged -= ld.changed;
        }

        public string[] GetAnimationLibraryList()
        {
            var r = new string[animationLibraries.Count];
            for (int i = 0; i < r.Length; i++) r[i] = animationLibraries[i].name;
            return r;
        }

        public AnimationLibrary GetAnimationLibrary(string name)
        {
            name ??= "";
            foreach (var l in animationLibraries) if (l.name == name) return l.library;
            GD.PushError("Method/function failed. Returning: Ref<AnimationLibrary>()");
            return null;
        }

        public bool HasAnimationLibrary(string name)
        {
            name ??= "";
            foreach (var l in animationLibraries) if (l.name == name) return true;
            return false;
        }

        public string FindAnimationLibrary(Animation animation)
        {
            for (int i = 0; i < animationSet.Count; i++)
                if (animationSet.ValueAt(i).animation == animation) return animationSet.ValueAt(i).library;
            return "";
        }

        public int AddAnimationLibrary(string name, AnimationLibrary library)
        {
            name ??= "";
            if (library == null) { GD.PushError("Condition \"p_animation_library.is_null()\" is true. Returning: ERR_INVALID_PARAMETER"); return GD.ERR_INVALID_PARAMETER; }
            if (name.IndexOf('/') >= 0 || name.IndexOf(':') >= 0 || name.IndexOf(',') >= 0 || name.IndexOf('[') >= 0)
            {
                GD.PushError("Invalid animation name: " + name + ".");
                return GD.ERR_INVALID_PARAMETER;
            }
            int insertPos = 0;
            foreach (var lib in animationLibraries)
            {
                if (lib.name == name) { GD.PushError("Can't add animation library twice with name: " + name); return GD.ERR_ALREADY_EXISTS; }
                if (lib.library == library) { GD.PushError("Can't add animation library twice (adding as '" + name + "', exists as '" + lib.name + "'."); return GD.ERR_ALREADY_EXISTS; }
                if (string.CompareOrdinal(lib.name, name) >= 0) break;
                insertPos++;
            }
            var ld = new LibraryData { name = name, library = library };
            animationLibraries.Insert(insertPos, ld);
            ConnectLibrary(ld);
            AnimationSetCacheUpdate();
            return GD.OK;
        }

        public void RemoveAnimationLibrary(string name)
        {
            name ??= "";
            int at = -1;
            for (int i = 0; i < animationLibraries.Count; i++) if (animationLibraries[i].name == name) { at = i; break; }
            if (at == -1) { GD.PushError("Condition \"at_pos == -1\" is true."); return; }
            DisconnectLibrary(animationLibraries[at]);
            animationLibraries.RemoveAt(at);
            AnimationSetCacheUpdate();
        }

        public void RenameAnimationLibrary(string name, string newName)
        {
            name ??= "";
            newName ??= "";
            if (name == newName) return;
            bool found = false;
            foreach (var lib in animationLibraries)
            {
                if (lib.name == newName) { GD.PushError("Can't rename animation library to another existing name: " + newName + "."); return; }
                if (lib.name == name)
                {
                    found = true;
                    DisconnectLibrary(lib);
                    lib.name = newName;
                    ConnectLibrary(lib);
                    foreach (var kv in lib.library.Animations)
                        OnRenameAnimation(name.Length == 0 ? kv.Key : name + "/" + kv.Key, newName.Length == 0 ? kv.Key : newName + "/" + kv.Key);
                }
            }
            if (!found) { GD.PushError("Condition \"!found\" is true."); return; }
            animationLibraries.Sort((a, b) => string.CompareOrdinal(a.name, b.name));
            AnimationSetCacheUpdate();
        }

        /// <summary>get_animation_list(): every "lib/anim" name, sorted.</summary>
        public string[] GetAnimationList()
        {
            var r = new string[animationSet.Count];
            for (int i = 0; i < r.Length; i++) r[i] = animationSet.KeyAt(i);
            Array.Sort(r, StringComparer.Ordinal);
            return r;
        }

        public Animation GetAnimation(string name)
        {
            var a = GetAnimationOrNull(name);
            if (a == null) GD.PushError("Animation not found: \"" + name + "\".");
            return a;
        }

        public Animation GetAnimationOrNull(string name) => name != null && animationSet.TryGetValue(name, out var ad) ? ad.animation : null;
        public bool HasAnimation(string name) => name != null && animationSet.ContainsKey(name);

        public string FindAnimation(Animation animation)
        {
            for (int i = 0; i < animationSet.Count; i++)
                if (animationSet.ValueAt(i).animation == animation) return animationSet.KeyAt(i);
            return "";
        }

        // ================================================================== settings
        protected void SetMixerProcess(bool process, bool force = false)
        {
            if (processing == process && !force) return;
            switch (callbackModeProcess)
            {
                case AnimationCallbackModeProcess.Physics: _physics.Set(process && active); break;
                case AnimationCallbackModeProcess.Idle: SetProcessInternal(process && active); break;
            }
            processing = process;
        }

        public bool Active
        {
            get => active;
            set
            {
                if (active == value) return;
                active = value;
                OnSetActive(active);
                SetMixerProcess(processing, true);
                if (!active && IsInsideTree()) ClearCachesInternal();
            }
        }
        public void SetActive(bool on) => Active = on;
        public bool IsActive() => active;

        public bool Deterministic
        {
            get => _deterministic;
            set { _deterministic = value; ClearCachesInternal(); }
        }

        public NodePath RootNode
        {
            get => _rootNode;
            set { _rootNode = value; ClearCachesInternal(); }
        }
        public void SetRootNode(NodePath p) => RootNode = p;
        public NodePath GetRootNode() => _rootNode;

        public AnimationCallbackModeProcess CallbackModeProcess
        {
            get => callbackModeProcess;
            set
            {
                if (callbackModeProcess == value) return;
                bool wasActive = Active;
                if (wasActive) Active = false;
                callbackModeProcess = value;
                if (wasActive) Active = true;
            }
        }

        public AnimationCallbackModeMethod CallbackModeMethod
        {
            get => callbackModeMethod;
            set { callbackModeMethod = value; MixerUpdated?.Invoke(); }
        }

        public AnimationCallbackModeDiscrete CallbackModeDiscrete
        {
            get => callbackModeDiscrete;
            set { callbackModeDiscrete = value; ClearCachesInternal(); MixerUpdated?.Invoke(); }
        }

        public int AudioMaxPolyphony = 32;
        /// <summary>root_motion_track: kept, not applied (root motion isn't ported).</summary>
        public NodePath RootMotionTrack;
        public bool RootMotionLocal;
        public bool ResetOnSaveEnabled = true;

        // ================================================================== caches
        void ClearCachesInternal()
        {
            _trackCache.Clear();
            _bindingPass++;
            cacheValid = false;
            CachesCleared?.Invoke();
        }

        /// <summary>clear_caches(): must be called by hand if an animation was modified after being added.</summary>
        public void ClearCaches() => ClearCachesInternal();

        bool UpdateCaches()
        {
            _setupPass++;
            if (_setupPass == 0) _setupPass = 1;
            Node parent = ResolveRoot();
            if (parent == null)
            {
                if (!_warnedRoot) { _warnedRoot = true; GD.PushWarning("'" + _rootNode + "' is an invalid root_node path, caches will not be built, please check the root_node assignment on: " + Name); }
                cacheValid = false;
                return false;
            }
            Animation resetAnim = HasAnimation("RESET") ? GetAnimation("RESET") : null;
            int nAnims = animationSet.Count;
            for (int ai = 0; ai < nAnims; ai++)
            {
                var anim = animationSet.ValueAt(ai).animation;
                var tracks = anim.Tracks;
                for (int i = 0; i < tracks.Count; i++)
                {
                    var tr = tracks[i];
                    if (!tr.enabled) continue;
                    var srcType = tr.type;
                    var cacheType = Animation.GetCacheType(srcType);
                    var key = new CacheKey(tr.concatenatedPath, cacheType);
                    _trackCache.TryGetValue(key, out var track);
                    if (track != null && (track.type != cacheType || track.ObjectGone))
                    {
                        _trackCache.Remove(key);
                        track = null;
                    }
                    if (track == null)
                    {
                        Node child = AnimTargets.Resolve(parent, tr.path, out object resource, out string[] leftover);
                        if (child == null) continue;
                        switch (srcType)
                        {
                            case Animation.TrackType.Bezier:
                            case Animation.TrackType.Value:
                            {
                                if (anim.TrackGetKeyCount(i) == 0) continue;
                                var tv = new TrackCacheValue();
                                tv.obj = resource ?? child;
                                tv.isUsingAngle = tr.interpolation == Animation.InterpolationType.LinearAngle || tr.interpolation == Animation.InterpolationType.CubicAngle;
                                tv.subpath = leftover;
                                bool isValue = srcType == Animation.TrackType.Value;
                                tv.initValue = AnimVar.Zero(isValue ? anim.TrackGetKeyValue(i, 0) : anim.TrackGetKeyValue(i, 0).AsArr()[0]);
                                tv.isInit = false;
                                tv.isVariantInterpolatable = AnimVar.IsVariantInterpolatable(tv.initValue);
                                if (resetAnim != null)
                                {
                                    int rt = resetAnim.FindTrack(tr.path, srcType);
                                    if (rt >= 0 && resetAnim.TrackIsEnabled(rt) && resetAnim.TrackGetKeyCount(rt) > 0)
                                        tv.initValue = isValue ? resetAnim.TrackGetKeyValue(rt, 0) : resetAnim.TrackGetKeyValue(rt, 0).AsArr()[0];
                                }
                                tv.setter = new ValueSetter(tv.obj, leftover);
                                track = tv;
                                break;
                            }
                            case Animation.TrackType.Position3D:
                            case Animation.TrackType.Rotation3D:
                            case Animation.TrackType.Scale3D:
                            {
                                if (!(child is Node3D node3d))
                                {
                                    GD.PushError("AnimationMixer: '" + animationSet.KeyAt(ai) + "', transform track does not point to Node3D:  '" + tr.path + "'.");
                                    continue;
                                }
                                var tx = new TrackCacheTransform();
                                bool hasRest = false;
                                if (node3d is Skeleton3D sk && tr.path.GetSubnameCount() == 1)
                                {
                                    tx.skeleton = sk;
                                    int bi = sk.FindBone(tr.path.GetSubname(0));
                                    if (bi != -1)
                                    {
                                        hasRest = true;
                                        tx.boneIdx = bi;
                                        var rest = sk.GetBoneRest(bi);
                                        tx.initLoc = rest.origin;
                                        tx.initRot = rest.basis.GetRotationQuaternion();
                                        tx.initScale = rest.basis.GetScale();
                                    }
                                }
                                tx.obj = node3d;
                                if (srcType == Animation.TrackType.Position3D) tx.locUsed = true;
                                else if (srcType == Animation.TrackType.Rotation3D) tx.rotUsed = true;
                                else tx.scaleUsed = true;
                                if (resetAnim != null && !hasRest)
                                {
                                    int rt = resetAnim.FindTrack(tr.path, srcType);
                                    if (rt >= 0 && resetAnim.TrackIsEnabled(rt) && resetAnim.TrackGetKeyCount(rt) > 0)
                                    {
                                        var v = resetAnim.TrackGetKeyValue(rt, 0);
                                        if (srcType == Animation.TrackType.Position3D) tx.initLoc = AnimVar.ToVec3(v);
                                        else if (srcType == Animation.TrackType.Rotation3D) tx.initRot = AnimVar.ToQuat(v);
                                        else tx.initScale = AnimVar.ToVec3(v);
                                    }
                                }
                                track = tx;
                                break;
                            }
                            case Animation.TrackType.Method:
                                track = new TrackCacheMethod { obj = resource ?? child };
                                break;
                            default:
                                continue;       // (blend shape, audio, animation tracks: not ported)
                        }
                        track.path = tr.path;
                        _trackCache.Set(key, track);
                    }
                    else if (cacheType == Animation.TrackType.Position3D)
                    {
                        var tx = (TrackCacheTransform)track;
                        if (track.setupPass != _setupPass) { tx.locUsed = false; tx.rotUsed = false; tx.scaleUsed = false; }
                        if (srcType == Animation.TrackType.Position3D) tx.locUsed = true;
                        else if (srcType == Animation.TrackType.Rotation3D) tx.rotUsed = true;
                        else if (srcType == Animation.TrackType.Scale3D) tx.scaleUsed = true;
                    }
                    else if (cacheType == Animation.TrackType.Value)
                    {
                        var tv = (TrackCacheValue)track;
                        if (srcType == Animation.TrackType.Value)
                            tv.isUsingAngle = tv.isUsingAngle || tr.interpolation == Animation.InterpolationType.LinearAngle || tr.interpolation == Animation.InterpolationType.CubicAngle;
                    }
                    track.setupPass = _setupPass;
                }
            }
            List<CacheKey> toDelete = null;
            for (int i = 0; i < _trackCache.Count; i++)
                if (_trackCache.ValueAt(i).setupPass != _setupPass) (toDelete ??= new List<CacheKey>()).Add(_trackCache.KeyAt(i));
            if (toDelete != null) foreach (var k in toDelete) _trackCache.Remove(k);

            _trackMap.Clear();
            int idx = 0;
            for (int i = 0; i < _trackCache.Count; i++) _trackMap[_trackCache.ValueAt(i).path.ToString()] = idx++;
            for (int i = 0; i < _trackCache.Count; i++) _trackCache.ValueAt(i).blendIdx = _trackMap[_trackCache.ValueAt(i).path.ToString()];

            // track number -> cache, per animation (reusing the arrays of earlier builds)
            _bindingPass++;
            for (int ai = 0; ai < nAnims; ai++)
            {
                var anim = animationSet.ValueAt(ai).animation;
                if (!_bindings.TryGetValue(anim, out var b)) { b = new AnimBinding(); _bindings[anim] = b; }
                if (b.pass == _bindingPass) continue;
                var tracks = anim.Tracks;
                if (b.caches.Length != tracks.Count)
                {
                    b.caches = new TrackCache[tracks.Count];
                    b.hints = new int[tracks.Count];
                }
                for (int i = 0; i < tracks.Count; i++)
                {
                    _trackCache.TryGetValue(new CacheKey(tracks[i].concatenatedPath, Animation.GetCacheType(tracks[i].type)), out var tc);
                    b.caches[i] = tc;
                    b.hints[i] = -1;
                }
                b.pass = _bindingPass;
            }
            if (_bindings.Count > nAnims)
            {
                var stale = new List<Animation>();
                foreach (var kv in _bindings) if (kv.Value.pass != _bindingPass) stale.Add(kv.Key);
                foreach (var a in stale) _bindings.Remove(a);
            }
            _trackCount = idx;
            cacheValid = true;
            return true;
        }

        Node ResolveRoot()
        {
            if (_rootNode.IsEmpty()) return null;
            if (_rootNode.GetNameCount() == 0 && !_rootNode.IsAbsolute()) return this;
            return GetNodeOrNull(_rootNode.NodePart);
        }

        // ================================================================== process
        protected virtual void ProcessAnimation(double delta, bool updateOnly = false)
        {
            BlendInit();
            if (cacheValid && BlendPreProcess(delta, _trackCount))
            {
                BlendCapture(delta);
                BlendCalcTotalWeight();
                BlendProcess(delta, updateOnly);
                _instances.Clear();
                BlendApply();
                BlendPostProcess();
                MixerApplied?.Invoke();
            }
            else _instances.Clear();
        }

        void BlendInit()
        {
            if (!cacheValid && !UpdateCaches()) return;
            for (int i = 0; i < _trackCache.Count; i++)
            {
                var track = _trackCache.ValueAt(i);
                track.totalWeight = 0f;
                switch (track)
                {
                    case TrackCacheTransform t:
                        t.loc = t.initLoc;
                        t.rot = t.initRot;
                        t.scale = t.initScale;
                        break;
                    case TrackCacheValue v:
                        v.value = AnimVar.CastToBlendwise(v.initValue);
                        v.elementSize = v.initValue.IsString ? (double)(float)v.initValue.AsString().Length : 0.0;
                        v.useContinuous = false;
                        v.useDiscrete = false;
                        break;
                }
            }
        }

        protected virtual bool BlendPreProcess(double delta, int trackCount) => true;
        protected virtual void BlendPostProcess() { }
        protected virtual void BlendCapture(double delta) { }

        /// <summary>make_animation_instance(name, playback_info).</summary>
        public void MakeAnimationInstance(string name, PlaybackInfo info)
        {
            var a = GetAnimationOrNull(name);
            if (a == null) { GD.PushError("Condition \"animation.is_null()\" is true."); return; }
            _instances.Add(new AnimationInstance { animation = a, info = info });
        }

        public void ClearAnimationInstances() => _instances.Clear();

        void BlendCalcTotalWeight()
        {
            for (int n = 0; n < _instances.Count; n++)
            {
                var ai = _instances[n];
                float weight = ai.info.weight;
                if (GD.IsZeroApproxF(weight)) continue;
                if (!_bindings.TryGetValue(ai.animation, out var b) || b.pass != _bindingPass) { GD.PushError("No animation in cache."); continue; }
                ulong passId = ++_weightPassCounter;
                var tracks = ai.animation.Tracks;
                int count = Math.Min(tracks.Count, b.caches.Length);
                for (int i = 0; i < count; i++)
                {
                    if (!tracks[i].enabled) continue;
                    var track = b.caches[i];
                    if (track == null) continue;
                    if (track.weightAppliedAt == passId) continue;
                    if (track.blendIdx < 0 || track.blendIdx >= _trackCount) continue;
                    track.totalWeight += weight;
                    track.weightAppliedAt = passId;
                }
            }
        }

        void BlendProcess(double pDelta, bool updateOnly)
        {
            for (int n = 0; n < _instances.Count; n++)
            {
                var ai = _instances[n];
                var a = ai.animation;
                ref readonly PlaybackInfo pi = ref ai.info;
                double time = pi.time, delta = pi.delta, start = pi.start, end = pi.end;
                bool seeked = pi.seeked, isExternalSeeking = pi.isExternalSeeking;
                var loopedFlag = pi.loopedFlag;
                float weight = pi.weight;
                bool backward = Animation.IsNegative(delta);
                bool seekedBackward = Animation.IsNegative(pDelta);
                if (!_bindings.TryGetValue(a, out var b) || b.pass != _bindingPass) { GD.PushError("No animation in cache."); continue; }
                var tracks = a.Tracks;
                int count = Math.Min(tracks.Count, b.caches.Length);
                for (int i = 0; i < count; i++)
                {
                    var at = tracks[i];
                    if (!at.enabled) continue;
                    var track = b.caches[i];
                    if (track == null) continue;
                    if (track.blendIdx < 0 || track.blendIdx >= _trackCount) continue;
                    float blend = weight;
                    if (!_deterministic)
                    {
                        if (GD.IsZeroApproxF(track.totalWeight)) continue;
                        blend = blend / track.totalWeight;
                    }
                    switch (at.type)
                    {
                        case Animation.TrackType.Position3D:
                        {
                            if (GD.IsZeroApproxF(blend)) continue;
                            var t = (TrackCacheTransform)track;
                            if (!a.InterpolateVec3((Animation.Track<Vec3>)at, time, false, ref b.hints[i], out var loc)) continue;
                            if (t.boneIdx >= 0 && t.obj is Skeleton3D skel) loc = loc * (double)skel.GetMotionScale();
                            t.loc = t.loc + (loc - t.initLoc) * (double)blend;
                            break;
                        }
                        case Animation.TrackType.Rotation3D:
                        {
                            if (GD.IsZeroApproxF(blend)) continue;
                            var t = (TrackCacheTransform)track;
                            if (!a.InterpolateQuat((Animation.Track<Quat>)at, time, false, ref b.hints[i], out var rot)) continue;
                            t.rot = Animation.InterpolateViaRest(t.rot, rot, blend, t.initRot);
                            break;
                        }
                        case Animation.TrackType.Scale3D:
                        {
                            if (GD.IsZeroApproxF(blend)) continue;
                            var t = (TrackCacheTransform)track;
                            if (!a.InterpolateVec3((Animation.Track<Vec3>)at, time, false, ref b.hints[i], out var sc)) continue;
                            t.scale = t.scale + (sc - t.initScale) * (double)blend;
                            break;
                        }
                        case Animation.TrackType.Bezier:
                        case Animation.TrackType.Value:
                        {
                            if (GD.IsZeroApproxF(blend)) continue;
                            var t = (TrackCacheValue)track;
                            bool isValue = at.type == Animation.TrackType.Value;
                            var vt = at as Animation.ValueTrack;
                            bool isDiscrete = isValue && vt.updateMode == Animation.UpdateMode.Discrete;
                            bool forceContinuous = callbackModeDiscrete == AnimationCallbackModeDiscrete.ForceContinuous;
                            if (!isDiscrete || forceContinuous)
                            {
                                t.useContinuous = true;
                                Var value;
                                if (t.isVariantInterpolatable)
                                {
                                    if (isValue)
                                    {
                                        var interp = vt.updateMode == Animation.UpdateMode.Discrete ? Animation.InterpolationType.Nearest : vt.interpolation;
                                        bool bw = isDiscrete && forceContinuous ? backward : false;
                                        if (!a.InterpolateValue(vt, time, interp, bw, ref b.hints[i], out value)) continue;
                                    }
                                    else value = a.BezierTrackInterpolate(i, time);
                                    if (value.IsNil) continue;
                                }
                                else
                                {
                                    int idx = a.TrackFindKey(i, time, Animation.FindMode.Nearest, false, backward);
                                    if (idx < 0) continue;
                                    value = a.TrackGetKeyValue(i, idx);
                                    if (value.IsNil) continue;
                                    t.value = value;
                                    continue;
                                }
                                if (t.isUsingAngle)
                                {
                                    t.value = Animation.InterpolateViaRest(t.value.AsFloat(), value.AsFloat(), blend, t.initValue.AsFloat());
                                }
                                else
                                {
                                    value = AnimVar.CastToBlendwise(value);
                                    if (t.initValue.IsArr) t.elementSize = Math.Max(t.elementSize.AsInt(), value.AsArr()?.Size() ?? 0);
                                    else if (t.initValue.IsString)
                                    {
                                        float length = (float)AnimVar.Subtract((double)(float)(value.AsArr()?.Size() ?? 0), (double)(float)t.initValue.AsString().Length).AsFloat();
                                        t.elementSize = AnimVar.Blend(t.elementSize, (double)length, blend);
                                    }
                                    value = AnimVar.Subtract(value, AnimVar.CastToBlendwise(t.initValue));
                                    t.value = AnimVar.Blend(t.value, value, blend);
                                }
                            }
                            else
                            {
                                if (seeked)
                                {
                                    int idx = a.TrackFindKey(i, time, isExternalSeeking ? Animation.FindMode.Nearest : Animation.FindMode.Exact, false, seekedBackward);
                                    if (idx < 0) continue;
                                    t.useDiscrete = true;
                                    if (!t.ObjectGone) t.setter.Set(a.TrackGetKeyValue(i, idx));
                                }
                                else
                                {
                                    _indices.Clear();
                                    a.TrackGetKeyIndicesInRange(i, time, delta, start, end, _indices, loopedFlag);
                                    for (int k = 0; k < _indices.Count; k++)
                                    {
                                        t.useDiscrete = true;
                                        if (!t.ObjectGone) t.setter.Set(a.TrackGetKeyValue(i, _indices[k]));
                                    }
                                }
                            }
                            break;
                        }
                        case Animation.TrackType.Method:
                        {
                            if (updateOnly || GD.IsZeroApproxF(blend)) continue;
                            var t = (TrackCacheMethod)track;
                            bool deferred = callbackModeMethod == AnimationCallbackModeMethod.Deferred;
                            if (seeked)
                            {
                                int idx = a.TrackFindKey(i, time, isExternalSeeking ? Animation.FindMode.Nearest : Animation.FindMode.Exact, true);
                                if (idx < 0) continue;
                                CallObject(t, a.MethodTrackGetName(i, idx), a.MethodTrackGetParams(i, idx), deferred);
                            }
                            else
                            {
                                _indices.Clear();
                                a.TrackGetKeyIndicesInRange(i, time, delta, start, end, _indices, loopedFlag);
                                for (int k = 0; k < _indices.Count; k++)
                                    CallObject(t, a.MethodTrackGetName(i, _indices[k]), a.MethodTrackGetParams(i, _indices[k]), deferred);
                            }
                            break;
                        }
                    }
                }
            }
        }

        void BlendApply()
        {
            for (int i = 0; i < _trackCache.Count; i++)
            {
                var track = _trackCache.ValueAt(i);
                bool isZeroAmount = GD.IsZeroApproxF(track.totalWeight);
                if (!_deterministic && isZeroAmount) continue;
                switch (track)
                {
                    case TrackCacheTransform t:
                    {
                        if (t.skeleton != null && t.boneIdx >= 0)
                        {
                            if (t.skeleton.IsFreed) return;
                            if (t.locUsed) t.skeleton.SetBonePosePosition(t.boneIdx, t.loc);
                            if (t.rotUsed) t.skeleton.SetBonePoseRotation(t.boneIdx, t.rot);
                            if (t.scaleUsed) t.skeleton.SetBonePoseScale(t.boneIdx, t.scale);
                        }
                        else if (t.skeleton == null)
                        {
                            var n3 = t.obj as Node3D;
                            if (n3 == null || n3.IsFreed) return;
                            if (t.locUsed && t.rotUsed && t.scaleUsed) n3.Transform = new Xform3(new Basis(t.rot).Scaled(t.scale), t.loc);
                            else
                            {
                                if (t.locUsed) n3.Position = t.loc;
                                if (t.rotUsed) n3.Rotation = t.rot.GetEuler();
                                if (t.scaleUsed) n3.Scale = t.scale;
                            }
                        }
                        break;
                    }
                    case TrackCacheValue t:
                    {
                        if (callbackModeDiscrete == AnimationCallbackModeDiscrete.ForceContinuous) t.isInit = false;
                        else if (!t.useContinuous && (t.useDiscrete || !_deterministic)) t.isInit = true;
                        if ((t.isInit && (isZeroAmount || !t.useContinuous)) ||
                            (callbackModeDiscrete != AnimationCallbackModeDiscrete.ForceContinuous && !isZeroAmount &&
                             callbackModeDiscrete == AnimationCallbackModeDiscrete.Dominant && t.useDiscrete))
                            break;
                        if (callbackModeDiscrete != AnimationCallbackModeDiscrete.ForceContinuous) t.isInit = !t.useContinuous;
                        if (t.value.IsArr)
                        {
                            var arr = t.value.AsArr();
                            int actual = (int)MathF.Round(MathF.Abs((float)t.elementSize.AsFloat()), MidpointRounding.AwayFromZero);
                            if (actual < arr.Size())
                            {
                                float absWeight = MathF.Abs(track.totalWeight);
                                if (absWeight >= 1.0f) arr.Resize(actual);
                                else if (t.initValue.IsString)
                                    arr.Resize(AnimVar.Interpolate((long)t.initValue.AsString().Length, (long)actual, absWeight).AsInt());
                            }
                        }
                        if (!t.ObjectGone) t.setter.Set(AnimVar.CastFromBlendwise(t.value, t.initValue.GodotType));
                        break;
                    }
                }
            }
        }

        void CallObject(TrackCacheMethod t, string method, Var[] args, bool deferred)
        {
            object target = t.obj;
            if (t.ObjectGone) return;
            if (deferred)
            {
                var tree = GetTree() ?? SceneTree.Current;
                if (tree != null) { tree.Defer(() => { if (!t.ObjectGone) MethodCaller.Call(target, method, args); }); return; }
            }
            MethodCaller.Call(target, method, args);
        }

        /// <summary>advance(delta): processes the animation by delta seconds (MANUAL callback mode, or any mode).</summary>
        public virtual void Advance(double delta) => ProcessAnimation(delta);

        /// <summary>capture(): not ported (logs an error).</summary>
        public void Capture(string name, double duration, int transType = 0, int easeType = 0) =>
            GD.PushError("AnimationMixer.capture() is not supported by the port.");

        // ================================================================== tree
        protected override void OnEnterTree()
        {
            base.OnEnterTree();
            if (!processing)
            {
                _physics.Set(false);
                SetProcessInternal(false);
            }
            ClearCachesInternal();
            _physics.EnterTree();
        }

        protected override void OnExitTree()
        {
            ClearCachesInternal();
            _physics.ExitTree();
            base.OnExitTree();
        }

        protected override void InternalProcess(double delta)
        {
            if (active && callbackModeProcess == AnimationCallbackModeProcess.Idle) ProcessAnimation(delta);
        }

        protected override void OnFreed()
        {
            foreach (var l in animationLibraries) DisconnectLibrary(l);
            _physics.ExitTree();
            base.OnFreed();
        }

        /// <summary>Stored properties of a baked scene: "libraries" (Dictionary name -> AnimationLibrary), "libraries/name".</summary>
        public override bool SetStoredProperty(string name, Var value)
        {
            if (name == "libraries")
            {
                while (animationLibraries.Count > 0) RemoveAnimationLibrary(animationLibraries[0].name);
                var d = value.AsDict();
                if (d != null) foreach (var k in d.Keys()) if (d[k].Obj is AnimationLibrary lib) AddAnimationLibrary(k.AsString(), lib);
                AnimationLibrariesUpdated?.Invoke();
                return true;
            }
            if (name.StartsWith("libraries/"))
            {
                string which = name.Substring(10);
                if (HasAnimationLibrary(which)) RemoveAnimationLibrary(which);
                if (value.Obj is AnimationLibrary lib) AddAnimationLibrary(which, lib);
                AnimationLibrariesUpdated?.Invoke();
                return true;
            }
            return base.SetStoredProperty(name, value);
        }
    }

    // ====================================================================== value / method targets
    internal static class AnimTargets
    {
        /// <summary>Node::get_node_and_resource(path): the node, the resource the subnames lead to (all but the last one
        /// tried), and the leftover property path. Null when the node or a resource step doesn't exist.</summary>
        public static Node Resolve(Node root, NodePath path, out object resource, out string[] leftover)
        {
            resource = null;
            leftover = Array.Empty<string>();
            Node node;
            if (path.IsEmpty()) return null;
            if (path.GetNameCount() == 0 && !path.IsAbsolute()) node = root;
            else node = root.GetNodeOrNull(path.NodePart);
            if (node == null) return null;
            int n = path.GetSubnameCount();
            if (n > 0)
            {
                int j = 0;
                object cur = node;
                for (; j < n - 1; j++)
                {
                    if (!TryGet(cur, path.GetSubname(j), out object v)) return null;
                    if (!(v is Resource r)) break;
                    resource = r;
                    cur = r;
                }
                leftover = new string[n - j];
                for (int k = j; k < n; k++) leftover[k - j] = path.GetSubname(k);
            }
            return node;
        }

        static bool TryGet(object o, string name, out object v)
        {
            v = null;
            try
            {
                if (o is GeometryInstance3D g && name == "material_override") { v = g.MaterialOverride; return true; }
                if (o is MeshInstance3D mi && name == "mesh") { v = mi.Mesh; return true; }
                v = PropertyPath.Get(o, name);
                return true;
            }
            catch (Exception) { return false; }
        }
    }

    /// <summary>set_indexed(subpath, value) for a value track's target, with fast paths for what animations set often.</summary>
    internal sealed class ValueSetter
    {
        enum Kind { Generic, Position, Rotation, RotationDegrees, Scale, Quaternion, Transform, Basis, Visible, ShaderParam }
        readonly object _target;
        readonly Kind _kind;
        readonly string _path, _param;
        bool _warned;

        public ValueSetter(object target, string[] subpath)
        {
            _target = target;
            _path = string.Join(":", subpath);
            _kind = Kind.Generic;
            if (subpath.Length == 1)
            {
                string p = subpath[0];
                if (target is Node3D)
                {
                    switch (p)
                    {
                        case "position": _kind = Kind.Position; break;
                        case "rotation": _kind = Kind.Rotation; break;
                        case "rotation_degrees": _kind = Kind.RotationDegrees; break;
                        case "scale": _kind = Kind.Scale; break;
                        case "quaternion": _kind = Kind.Quaternion; break;
                        case "transform": _kind = Kind.Transform; break;
                        case "basis": _kind = Kind.Basis; break;
                        case "visible": _kind = Kind.Visible; break;
                    }
                }
                else if (target is ShaderMaterial && p.StartsWith("shader_parameter/"))
                {
                    _kind = Kind.ShaderParam;
                    _param = p.Substring(17);
                }
            }
        }

        public void Set(Var v)
        {
            try
            {
                switch (_kind)
                {
                    case Kind.Position: ((Node3D)_target).Position = v.AsVec3(); return;
                    case Kind.Rotation: ((Node3D)_target).Rotation = v.AsVec3(); return;
                    case Kind.RotationDegrees: ((Node3D)_target).RotationDegrees = v.AsVec3(); return;
                    case Kind.Scale: ((Node3D)_target).Scale = v.AsVec3(); return;
                    case Kind.Quaternion: ((Node3D)_target).Quaternion = AnimVar.ToQuat(v); return;
                    case Kind.Transform: ((Node3D)_target).Transform = AnimVar.ToXform3(v); return;
                    case Kind.Basis: if (v.Obj is Basis b) ((Node3D)_target).Basis = b; return;
                    case Kind.Visible: ((Node3D)_target).Visible = v.Truthy; return;
                    case Kind.ShaderParam: ((ShaderMaterial)_target).SetShaderParameter(_param, v); return;
                }
                if (_path.Length == 0) return;
                PropertyPath.Set(_target, _path, v.Obj);
            }
            catch (Exception e)
            {
                if (!_warned) { _warned = true; GD.PushError("AnimationMixer: can't set '" + _path + "' on " + _target + ": " + e.Message); }
            }
        }
    }

    internal static class MethodCaller
    {
        static readonly Dictionary<(Type, string, int), MethodInfo> _cache = new Dictionary<(Type, string, int), MethodInfo>();

        public static void Call(object target, string method, Var[] args)
        {
            try
            {
                var hook = AnimationMixer.MethodCallHook;
                if (hook != null && hook(target, method, args)) return;
                var mi = Find(target.GetType(), method, args.Length);
                if (mi == null) { GD.PushError("AnimationMixer: method '" + method + "' not found on " + target + "."); return; }
                var ps = mi.GetParameters();
                var a = new object[ps.Length];
                for (int i = 0; i < ps.Length; i++)
                    a[i] = i < args.Length ? Convert(args[i], ps[i].ParameterType) : ps[i].DefaultValue;
                mi.Invoke(target, a);
            }
            catch (TargetInvocationException e) { GD.PushError("AnimationMixer: method '" + method + "': " + e.InnerException); }
            catch (Exception e) { GD.PushError("AnimationMixer: method '" + method + "': " + e.Message); }
        }

        static object Convert(Var v, Type t)
        {
            if (t == typeof(Var)) return v;
            return Tween.Convert(v.Obj, t);
        }

        static MethodInfo Find(Type t, string name, int argc)
        {
            lock (_cache)
            {
                if (_cache.TryGetValue((t, name, argc), out var m)) return m;
                const BindingFlags F = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.FlattenHierarchy;
                string pascal = PropertyPath.Pascal(name);
                foreach (var cand in new[] { pascal, name })
                {
                    foreach (var mi in t.GetMethods(F))
                    {
                        if (mi.Name != cand) continue;
                        var ps = mi.GetParameters();
                        int required = 0;
                        foreach (var p in ps) if (!p.IsOptional) required++;
                        if (argc >= required && argc <= ps.Length) { m = mi; break; }
                    }
                    if (m != null) break;
                }
                _cache[(t, name, argc)] = m;
                return m;
            }
        }
    }
}

#endif
