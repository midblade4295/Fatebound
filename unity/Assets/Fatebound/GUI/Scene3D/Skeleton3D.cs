#if FB3D
// Godot's Skeleton3D (scene/3d/skeleton_3d.cpp, 4.7) for the ported 3D code: bones (name, parent, rest, enabled, pose
// position/rotation/scale), the lazily computed global poses with Godot's nested-set dirty flags, the deferred
// NOTIFICATION_UPDATE_SKELETON (one per frame at most, run with the frame's deferred calls -- Godot's MessageQueue) that
// processes the SkeletonModifier3D children, emits skeleton_updated (BoneAttachment3D follows it) and "updates the skins".
//
// Skinning (the renderer's side): Godot pushes global_pose[bind bone] * bind_pose to the RenderingServer during the
// update. Here the renderer pulls: during each update that changed the pose the skeleton snapshots the global poses the
// skins must show (after the modifiers ran -- Godot restores the unmodified poses right after), bumps PoseVersion and
// calls NotifySkinnedPoseChanged() (each skinned MeshInstance3D is marked RenderDirty.Pose); the renderer then calls
// GetSkinTransforms(skin, dst) for each skinned mesh. Binds by name are resolved through find_bone, cached per skin and
// invalidated when the skeleton's version changes (add_bone, set_bone_name, clear_bones) or the skin changes.
//
// The modifier hook (ragdolls, IK): SkeletonModifier3D, below, exactly Godot's design -- a child node of the skeleton whose
// _ProcessModificationWithDelta(delta) overrides bone poses (SetBonePose*/SetBoneGlobalPose) once per frame, after the
// animation was applied. What it sets is what the skins and the bone attachments show that frame; the skeleton then puts
// the animated poses back, so the animation keeps blending from its own result (a PhysicalBoneSimulator3D port subclasses
// it and writes the simulated bodies' transforms with SetBoneGlobalPose).
//
// Differences from Godot: no editor gizmos, no bone meta property list; the deprecated compat PhysicalBoneSimulator3D that
// Godot adds to every skeleton (inactive, no visible effect) is not created; PHYSICS modifier callback mode runs at each
// physics tick's start (SceneTree.PhysicsFrame), not in tree order.
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public partial class Skeleton3D : Node3D
    {
        public const int NOTIFICATION_UPDATE_SKELETON = 50;

        public enum ModifierCallbackModeProcessEnum { Physics = 0, Idle = 1, Manual = 2 }
        public const ModifierCallbackModeProcessEnum MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS = ModifierCallbackModeProcessEnum.Physics,
            MODIFIER_CALLBACK_MODE_PROCESS_IDLE = ModifierCallbackModeProcessEnum.Idle,
            MODIFIER_CALLBACK_MODE_PROCESS_MANUAL = ModifierCallbackModeProcessEnum.Manual;

        const byte UPDATE_FLAG_NONE = 1, UPDATE_FLAG_MODIFIER = 2, UPDATE_FLAG_POSE = 4;
        static readonly Vec3 ONE = new Vec3(1f, 1f, 1f);

        sealed class Bone
        {
            public string name = "";
            public int parent = -1;
            public readonly List<int> childBones = new List<int>();
            public Xform3 rest = Xform3.IDENTITY, globalRest = Xform3.IDENTITY;
            public bool enabled = true, poseCacheDirty = true;
            public Xform3 poseCache = Xform3.IDENTITY;
            public Vec3 posePosition;
            public Quat poseRotation = Quat.IDENTITY;
            public Vec3 poseScale = ONE;
            public Xform3 globalPose = Xform3.IDENTITY;
            public int nestedSetOffset, nestedSetSpan;
            public bool modifierApplied;
            public Xform3 modifierPoseCache = Xform3.IDENTITY;
            public Dictionary<string, Var> metadata;
            // (DISABLE_DEPRECATED is off in Godot's builds: the global pose override is still applied)
            public Xform3 poseGlobalNoOverride = Xform3.IDENTITY;
            public float globalPoseOverrideAmount;
            public bool globalPoseOverrideReset;
            public Xform3 globalPoseOverride = Xform3.IDENTITY;

            public void MakeBoneModified()
            {
                modifierApplied = true;
                modifierPoseCache = poseCache;
            }

            public void UpdatePoseCache()
            {
                if (poseCacheDirty)
                {
                    poseCache.basis = new Basis(poseRotation, poseScale);       // (set_quaternion_scale)
                    poseCache.origin = posePosition;
                    poseCacheDirty = false;
                }
            }
        }

        struct BonePoseBackup
        {
            public Xform3 poseCache, globalPose;
            public Vec3 posePosition, poseScale;
            public Quat poseRotation;
            public void Save(Bone b) { poseCache = b.poseCache; posePosition = b.posePosition; poseRotation = b.poseRotation; poseScale = b.poseScale; globalPose = b.globalPose; }
            public void Restore(Bone b) { b.poseCache = poseCache; b.posePosition = posePosition; b.poseRotation = poseRotation; b.poseScale = poseScale; b.globalPose = globalPose; }
        }

        readonly List<Bone> _bones = new List<Bone>();
        bool _processOrderDirty;
        readonly List<int> _parentlessBones = new List<int>();
        readonly Dictionary<string, int> _nameToBoneIndex = new Dictionary<string, int>();
        bool _dirty, _restDirty, _showRestOnly;
        float _motionScale = 1f;
        ulong _version = 1;
        byte _updateFlags = UPDATE_FLAG_NONE;
        bool _updating;
        double _updateDelta;
        int[] _nestedSetOffsetToBoneIndex = Array.Empty<int>();
        bool[] _boneGlobalPoseDirty = Array.Empty<bool>();
        readonly List<int> _boneListScratch = new List<int>();
        BonePoseBackup[] _backup = Array.Empty<BonePoseBackup>();
        bool[] _dirtyBackup = Array.Empty<bool>();

        ModifierCallbackModeProcessEnum _modifierMode = ModifierCallbackModeProcessEnum.Idle;
        readonly List<SkeletonModifier3D> _modifiers = new List<SkeletonModifier3D>();
        bool _modifiersDirty, _modifierUpdating;
        readonly InternalPhysicsProcess _physics;
        readonly Action _deferredUpdate;

        // skinning snapshot (see the header)
        Xform3[] _skinPose = Array.Empty<Xform3>();
        int _skinPoseCount = -1;
        sealed class SkinBinding { public int[] bones = Array.Empty<int>(); public ulong skeletonVersion; public int skinVersion = -1; }
        readonly Dictionary<Skin, SkinBinding> _skinBindings = new Dictionary<Skin, SkinBinding>();
        Skin _restSkin;
        ulong _restSkinVersion;

        /// <summary>Bumped each time the pose the skins must show changed (the renderer re-reads GetSkinTransforms).</summary>
        public int PoseVersion { get; private set; }

        public event Action PoseUpdated, SkeletonUpdated, RestUpdated, BoneListChanged, ShowRestOnlyChanged;
        public event Action<int> BoneEnabledChanged;

        public Skeleton3D()
        {
            _physics = new InternalPhysicsProcess(this, d => Advance(d));
            _deferredUpdate = () => { if (!IsFreed) UpdateSkeletonNotification(); };
        }

        // ------------------------------------------------------------------ stored properties ("bones/N/...")
        public override bool SetStoredProperty(string path, Var value)
        {
            if (!path.StartsWith("bones/")) return false;
            int s1 = path.IndexOf('/', 6);
            if (s1 < 0) return false;
            int which = (int)GStr.ToInt(path.Substring(6, s1 - 6));
            int s2 = path.IndexOf('/', s1 + 1);
            string what = s2 < 0 ? path.Substring(s1 + 1) : path.Substring(s1 + 1, s2 - s1 - 1);
            if (which == _bones.Count && what == "name") { AddBone(value.AsString()); return true; }
            if ((uint)which >= (uint)_bones.Count) { GD.PushError("Index p_index = " + which + " is out of bounds (bones.size() = " + _bones.Count + ")."); return false; }
            switch (what)
            {
                case "parent": SetBoneParent(which, value.AsInt()); break;
                case "rest": SetBoneRest(which, AnimVar.ToXform3(value)); break;
                case "enabled": SetBoneEnabled(which, value.Truthy); break;
                case "position": SetBonePosePosition(which, value.AsVec3()); break;
                case "rotation": SetBonePoseRotation(which, AnimVar.ToQuat(value)); break;
                case "scale": SetBonePoseScale(which, value.AsVec3()); break;
                case "bone_meta": SetBoneMeta(which, s2 < 0 ? "" : path.Substring(s2 + 1), value); break;
                default: return false;
            }
            return true;
        }

        // ------------------------------------------------------------------ process order / nested set
        void UpdateProcessOrder()
        {
            if (!_processOrderDirty) return;
            int len = _bones.Count;
            _parentlessBones.Clear();
            for (int i = 0; i < len; i++) _bones[i].childBones.Clear();
            for (int i = 0; i < len; i++)
            {
                var b = _bones[i];
                if (b.parent >= len)
                {
                    GD.PushError("Bone " + i + " has invalid parent: " + b.parent);
                    b.parent = -1;
                }
                if (b.parent != -1)
                {
                    var pc = _bones[b.parent].childBones;
                    if (!pc.Contains(i)) pc.Add(i);
                    else GD.PushError("Skeleton3D parenthood graph is cyclic");
                }
                else _parentlessBones.Add(i);
            }
            UpdateBonesNestedSet();
            _processOrderDirty = false;
            BoneListChanged?.Invoke();
        }

        void UpdateBonesNestedSet()
        {
            int n = _bones.Count;
            if (_nestedSetOffsetToBoneIndex.Length != n) _nestedSetOffsetToBoneIndex = new int[n];
            if (_boneGlobalPoseDirty.Length != n) _boneGlobalPoseDirty = new bool[n];
            MakeBoneGlobalPosesDirty();
            int offset = 0;
            for (int i = 0; i < _parentlessBones.Count; i++) offset += UpdateBoneNestedSet(_parentlessBones[i], offset);
        }

        int UpdateBoneNestedSet(int bone, int pOffset)
        {
            var b = _bones[bone];
            int offset = pOffset + 1, span = 1;
            for (int i = 0; i < b.childBones.Count; i++)
            {
                int sub = UpdateBoneNestedSet(b.childBones[i], offset);
                offset += sub;
                span += sub;
            }
            _nestedSetOffsetToBoneIndex[pOffset] = bone;
            b.nestedSetOffset = pOffset;
            b.nestedSetSpan = span;
            return span;
        }

        void MakeBoneGlobalPosesDirty()
        {
            for (int i = 0; i < _boneGlobalPoseDirty.Length; i++) _boneGlobalPoseDirty[i] = true;
        }

        void MakeBoneGlobalPoseSubtreeDirty(int bone)
        {
            if (_processOrderDirty) return;
            var b = _bones[bone];
            int spanOffset = b.nestedSetOffset;
            if (_boneGlobalPoseDirty[spanOffset]) return;
            int spanEnd = spanOffset + b.nestedSetSpan;
            for (int i = spanOffset; i < spanEnd; i++) _boneGlobalPoseDirty[i] = true;
        }

        void UpdateBoneGlobalPose(int bone)
        {
            UpdateProcessOrder();
            if (!_boneGlobalPoseDirty[_bones[bone].nestedSetOffset]) return;
            var list = _boneListScratch;
            list.Clear();
            Xform3 globalPose = Xform3.IDENTITY;
            for (int bi = bone; bi >= 0; bi = _bones[bi].parent)
            {
                var b = _bones[bi];
                if (!_boneGlobalPoseDirty[b.nestedSetOffset])
                {
                    globalPose = b.globalPose;
                    break;
                }
                list.Add(bi);
            }
            for (int i = list.Count - 1; i >= 0; i--)
            {
                int idx = list[i];
                var b = _bones[idx];
                bool enabled = b.enabled && !_showRestOnly;
                Xform3 bonePose;
                if (enabled) { b.UpdatePoseCache(); bonePose = b.poseCache; }
                else bonePose = b.rest;
                globalPose = globalPose * bonePose;
                if (b.globalPoseOverrideAmount >= (float)GD.CMP_EPSILON)
                    globalPose = globalPose.InterpolateWith(b.globalPoseOverride, b.globalPoseOverrideAmount);
                b.globalPose = globalPose;
                _boneGlobalPoseDirty[b.nestedSetOffset] = false;
            }
        }

        bool BoneOk(int bone, string what = "p_bone")
        {
            if ((uint)bone < (uint)_bones.Count) return true;
            GD.PushError("Index " + what + " = " + bone + " is out of bounds (bone_size = " + _bones.Count + ").");
            return false;
        }

        // ------------------------------------------------------------------ global poses
        public Xform3 GetBoneGlobalPose(int bone)
        {
            if (!BoneOk(bone)) return Xform3.IDENTITY;
            UpdateBoneGlobalPose(bone);
            return _bones[bone].globalPose;
        }

        public void SetBoneGlobalPose(int bone, Xform3 pose)
        {
            if (!BoneOk(bone)) return;
            Xform3 pt = Xform3.IDENTITY;
            if (_bones[bone].parent >= 0) pt = GetBoneGlobalPose(_bones[bone].parent);
            SetBonePose(bone, pt.AffineInverse() * pose);
        }

        public float MotionScale
        {
            get => _motionScale <= 0 ? 1f : _motionScale;
            set
            {
                if (value <= 0) { _motionScale = 1; GD.PushError("Motion scale must be larger than 0."); return; }
                _motionScale = value;
            }
        }
        public void SetMotionScale(double s) => MotionScale = (float)s;
        public float GetMotionScale() => MotionScale;

        // ------------------------------------------------------------------ bones
        public ulong GetVersion() => _version;

        public int AddBone(string name)
        {
            if (string.IsNullOrEmpty(name) || name.IndexOf(':') >= 0 || name.IndexOf('/') >= 0)
            {
                GD.PushError("Bone name cannot be empty or contain ':' or '/'.");
                return -1;
            }
            if (_nameToBoneIndex.ContainsKey(name))
            {
                GD.PushError("Skeleton3D \"" + Name + "\" already has a bone with name \"" + name + "\".");
                return -1;
            }
            _bones.Add(new Bone { name = name });
            int idx = _bones.Count - 1;
            _nameToBoneIndex[name] = idx;
            _processOrderDirty = true;
            _version++;
            _restDirty = true;
            MakeDirty();
            return idx;
        }

        /// <summary>find_bone(name): a dictionary lookup (-1 when there's none).</summary>
        public int FindBone(string name) => name != null && _nameToBoneIndex.TryGetValue(name, out int i) ? i : -1;

        public string GetBoneName(int bone) => BoneOk(bone) ? _bones[bone].name : "";

        public void SetBoneName(int bone, string name)
        {
            if (!BoneOk(bone)) return;
            if (_nameToBoneIndex.TryGetValue(name ?? "", out int existing))
            {
                if (existing != bone) GD.PushError("Skeleton3D: '" + Name + "', bone name:  '" + name + "' already exists.");
                return;
            }
            _nameToBoneIndex.Remove(_bones[bone].name);
            _bones[bone].name = name;
            _nameToBoneIndex[name] = bone;
            _version++;
        }

        public string GetConcatenatedBoneNames()
        {
            var sb = new System.Text.StringBuilder();
            for (int i = 0; i < _bones.Count; i++) { if (i > 0) sb.Append(','); sb.Append(_bones[i].name); }
            return sb.ToString();
        }

        public bool IsBoneParentOf(int bone, int parentBone)
        {
            int p = GetBoneParent(bone);
            if (p == -1) return false;
            if (p == parentBone) return true;
            return IsBoneParentOf(p, parentBone);
        }

        public int GetBoneCount() => _bones.Count;

        public void SetBoneParent(int bone, int parent)
        {
            if (!BoneOk(bone)) return;
            if (parent != -1 && parent < 0) { GD.PushError("Condition \"p_parent != -1 && (p_parent < 0)\" is true."); return; }
            if (bone == parent) { GD.PushError("Condition \"p_bone == p_parent\" is true."); return; }
            _bones[bone].parent = parent;
            _processOrderDirty = true;
            _restDirty = true;
            MakeDirty();
        }

        public void UnparentBoneAndRest(int bone)
        {
            if (!BoneOk(bone)) return;
            UpdateProcessOrder();
            int parent = _bones[bone].parent;
            while (parent >= 0)
            {
                _bones[bone].rest = _bones[parent].rest * _bones[bone].rest;
                parent = _bones[parent].parent;
            }
            _bones[bone].parent = -1;
            _processOrderDirty = true;
            _restDirty = true;
            MakeDirty();
        }

        public int GetBoneParent(int bone)
        {
            if (!BoneOk(bone)) return -1;
            if (_processOrderDirty) UpdateProcessOrder();
            return _bones[bone].parent;
        }

        public int[] GetBoneChildren(int bone)
        {
            if (!BoneOk(bone)) return Array.Empty<int>();
            if (_processOrderDirty) UpdateProcessOrder();
            return _bones[bone].childBones.ToArray();
        }

        public int[] GetParentlessBones()
        {
            if (_processOrderDirty) UpdateProcessOrder();
            return _parentlessBones.ToArray();
        }

        public void SetBoneRest(int bone, Xform3 rest)
        {
            if (!BoneOk(bone)) return;
            _bones[bone].rest = rest;
            _restDirty = true;
            MakeDirty();
            MakeBoneGlobalPoseSubtreeDirty(bone);
        }

        public Xform3 GetBoneRest(int bone) => BoneOk(bone) ? _bones[bone].rest : Xform3.IDENTITY;

        public Xform3 GetBoneGlobalRest(int bone)
        {
            if (!BoneOk(bone)) return Xform3.IDENTITY;
            if (_restDirty) ForceUpdateAllBoneTransformsInternal();
            return _bones[bone].globalRest;
        }

        public void SetBoneEnabled(int bone, bool enabled = true)
        {
            if (!BoneOk(bone)) return;
            _bones[bone].enabled = enabled;
            BoneEnabledChanged?.Invoke(bone);
            MakeDirty();
            MakeBoneGlobalPoseSubtreeDirty(bone);
        }

        public bool IsBoneEnabled(int bone) => BoneOk(bone) && _bones[bone].enabled;

        public bool ShowRestOnly
        {
            get => _showRestOnly;
            set
            {
                _showRestOnly = value;
                ShowRestOnlyChanged?.Invoke();
                MakeDirty();
                MakeBoneGlobalPosesDirty();
            }
        }
        public void SetShowRestOnly(bool on) => ShowRestOnly = on;
        public bool IsShowRestOnly() => _showRestOnly;

        public void ClearBones()
        {
            _bones.Clear();
            _nameToBoneIndex.Clear();
            _skinBindings.Clear();
            _boneGlobalPoseDirty = Array.Empty<bool>();
            _parentlessBones.Clear();
            _nestedSetOffsetToBoneIndex = Array.Empty<int>();
            _processOrderDirty = true;
            _version++;
            MakeDirty();
        }

        // bone metadata
        public Var GetBoneMeta(int bone, string key)
        {
            if (!BoneOk(bone)) return Var.Nil;
            var m = _bones[bone].metadata;
            return m != null && m.TryGetValue(key, out var v) ? v : Var.Nil;
        }

        public string[] GetBoneMetaList(int bone)
        {
            if (!BoneOk(bone) || _bones[bone].metadata == null) return Array.Empty<string>();
            return new List<string>(_bones[bone].metadata.Keys).ToArray();
        }

        public bool HasBoneMeta(int bone, string key) => BoneOk(bone) && _bones[bone].metadata != null && _bones[bone].metadata.ContainsKey(key);

        public void SetBoneMeta(int bone, string key, Var value)
        {
            if (!BoneOk(bone)) return;
            var b = _bones[bone];
            if (value.IsNil) { b.metadata?.Remove(key); return; }
            (b.metadata ??= new Dictionary<string, Var>())[key] = value;
        }

        // ------------------------------------------------------------------ poses
        public void SetBonePose(int bone, Xform3 pose)
        {
            if (!BoneOk(bone)) return;
            var b = _bones[bone];
            if (_modifierUpdating) b.MakeBoneModified();
            b.posePosition = pose.origin;
            b.poseRotation = pose.basis.GetRotationQuaternion();
            b.poseScale = pose.basis.GetScale();
            b.poseCacheDirty = true;
            if (IsInsideTree())
            {
                MakeDirty();
                MakeBoneGlobalPoseSubtreeDirty(bone);
            }
        }

        public void SetBonePosePosition(int bone, Vec3 position)
        {
            if (!BoneOk(bone)) return;
            var b = _bones[bone];
            if (_modifierUpdating) b.MakeBoneModified();
            b.posePosition = position;
            b.poseCacheDirty = true;
            if (IsInsideTree())
            {
                MakeDirty();
                MakeBoneGlobalPoseSubtreeDirty(bone);
            }
        }

        public void SetBonePoseRotation(int bone, Quat rotation)
        {
            if (!BoneOk(bone)) return;
            var b = _bones[bone];
            if (_modifierUpdating) b.MakeBoneModified();
            b.poseRotation = rotation;
            b.poseCacheDirty = true;
            if (IsInsideTree())
            {
                MakeDirty();
                MakeBoneGlobalPoseSubtreeDirty(bone);
            }
        }

        public void SetBonePoseScale(int bone, Vec3 scale)
        {
            if (!BoneOk(bone)) return;
            var b = _bones[bone];
            if (_modifierUpdating) b.MakeBoneModified();
            b.poseScale = scale;
            b.poseCacheDirty = true;
            if (IsInsideTree())
            {
                MakeDirty();
                MakeBoneGlobalPoseSubtreeDirty(bone);
            }
        }

        public Vec3 GetBonePosePosition(int bone) => BoneOk(bone) ? _bones[bone].posePosition : Vec3.Zero;
        public Quat GetBonePoseRotation(int bone) => BoneOk(bone) ? _bones[bone].poseRotation : Quat.IDENTITY;
        public Vec3 GetBonePoseScale(int bone) => BoneOk(bone) ? _bones[bone].poseScale : Vec3.Zero;

        public void ResetBonePose(int bone)
        {
            if (!BoneOk(bone)) return;
            var r = _bones[bone].rest;
            SetBonePosePosition(bone, r.origin);
            SetBonePoseRotation(bone, r.basis.GetRotationQuaternion());
            SetBonePoseScale(bone, r.basis.GetScale());
        }

        public void ResetBonePoses()
        {
            for (int i = 0; i < _bones.Count; i++) ResetBonePose(i);
        }

        public Xform3 GetBonePose(int bone)
        {
            if (!BoneOk(bone)) return Xform3.IDENTITY;
            _bones[bone].UpdatePoseCache();
            return _bones[bone].poseCache;
        }

        public void LocalizeRests()
        {
            var toProcess = new List<int>(GetParentlessBones());
            while (toProcess.Count > 0)
            {
                int cur = toProcess[0];
                toProcess.Remove(cur);
                var b = _bones[cur];
                if (b.parent >= 0) SetBoneRest(cur, _bones[b.parent].rest.AffineInverse() * b.rest);
                for (int i = 0; i < b.childBones.Count; i++) toProcess.Add(b.childBones[i]);
            }
        }

        /// <summary>create_skin_from_rest_transforms(): binds every bone by index to the inverse of its global rest.</summary>
        public Skin CreateSkinFromRestTransforms()
        {
            var skin = new Skin();
            int len = _bones.Count;
            skin.SetBindCount(len);
            var toProcess = new List<int>(GetParentlessBones());
            while (toProcess.Count > 0)
            {
                int cur = toProcess[0];
                var b = _bones[cur];
                toProcess.Remove(cur);
                var children = GetBoneChildren(cur);
                if (b.parent < 0) skin.SetBindPose(cur, b.rest);
                for (int i = 0; i < children.Length; i++)
                {
                    skin.SetBindPose(children[i], skin.GetBindPose(cur) * _bones[children[i]].rest);
                    toProcess.Add(children[i]);
                }
            }
            for (int i = 0; i < len; i++)
            {
                skin.SetBindBone(i, i);
                skin.SetBindPose(i, skin.GetBindPose(i).AffineInverse());
            }
            return skin;
        }

        public void ForceUpdateDeferred() => MakeDirty();
        public void ForceUpdateAllDirtyBones() { if (_dirty) ForceUpdateAllBoneTransformsInternal(); }
        public void ForceUpdateAllBoneTransforms() => ForceUpdateAllBoneTransformsInternal();
        public void ForceUpdateBoneChildTransform(int bone) => ForceUpdateBoneChildrenTransforms(bone);

        void ForceUpdateAllBoneTransformsInternal()
        {
            UpdateProcessOrder();
            for (int i = 0; i < _parentlessBones.Count; i++) ForceUpdateBoneChildrenTransforms(_parentlessBones[i]);
            if (_restDirty)
            {
                _restDirty = false;
                RestUpdated?.Invoke();
            }
            else _restDirty = false;
            _dirty = false;
            if (_updating) return;
            PoseUpdated?.Invoke();
        }

        void ForceUpdateBoneChildrenTransforms(int boneIdx)
        {
            int size = _bones.Count;
            if (!BoneOk(boneIdx, "p_bone_idx")) return;
            UpdateProcessOrder();
            for (int offset = 0; offset < size; offset++)
            {
                if (_restDirty)
                {
                    var rb = _bones[_nestedSetOffsetToBoneIndex[offset]];
                    rb.globalRest = rb.parent >= 0 ? _bones[rb.parent].globalRest * rb.rest : rb.rest;
                }
                if (!_boneGlobalPoseDirty[offset]) continue;
                var b = _bones[_nestedSetOffsetToBoneIndex[offset]];
                bool enabled = b.enabled && !_showRestOnly;
                if (enabled)
                {
                    b.UpdatePoseCache();
                    b.globalPose = b.parent >= 0 ? _bones[b.parent].globalPose * b.poseCache : b.poseCache;
                    b.poseGlobalNoOverride = b.parent >= 0 ? _bones[b.parent].poseGlobalNoOverride * b.poseCache : b.poseCache;
                }
                else
                {
                    b.globalPose = b.parent >= 0 ? _bones[b.parent].globalPose * b.rest : b.rest;
                    b.poseGlobalNoOverride = b.parent >= 0 ? _bones[b.parent].poseGlobalNoOverride * b.rest : b.rest;
                }
                if (b.globalPoseOverrideAmount >= (float)GD.CMP_EPSILON)
                    b.globalPose = b.globalPose.InterpolateWith(b.globalPoseOverride, b.globalPoseOverrideAmount);
                if (b.globalPoseOverrideReset) b.globalPoseOverrideAmount = 0f;
                _boneGlobalPoseDirty[offset] = false;
            }
        }

        // (deprecated in Godot 4.3 but still there: blends a bone's global pose toward an override)
        public void ClearBonesGlobalPoseOverride()
        {
            for (int i = 0; i < _bones.Count; i++) { _bones[i].globalPoseOverrideAmount = 0; _bones[i].globalPoseOverrideReset = true; }
            MakeDirty();
            MakeBoneGlobalPosesDirty();
        }

        public void SetBoneGlobalPoseOverride(int bone, Xform3 pose, double amount, bool persistent = false)
        {
            if (!BoneOk(bone)) return;
            var b = _bones[bone];
            b.globalPoseOverrideAmount = (float)amount;
            b.globalPoseOverride = pose;
            b.globalPoseOverrideReset = !persistent;
            MakeDirty();
            MakeBoneGlobalPoseSubtreeDirty(bone);
        }

        public Xform3 GetBoneGlobalPoseOverride(int bone) => BoneOk(bone) ? _bones[bone].globalPoseOverride : Xform3.IDENTITY;

        public Xform3 GetBoneGlobalPoseNoOverride(int bone)
        {
            if (!BoneOk(bone)) return Xform3.IDENTITY;
            ForceUpdateAllDirtyBones();
            return _bones[bone].poseGlobalNoOverride;
        }

        // ------------------------------------------------------------------ deferred update (NOTIFICATION_UPDATE_SKELETON)
        void MakeDirty()
        {
            if (_dirty) return;
            _dirty = true;
            UpdateDeferred(_modifiers.Count == 0 ? UPDATE_FLAG_POSE : (byte)(UPDATE_FLAG_POSE | UPDATE_FLAG_MODIFIER));
        }

        void UpdateDeferred(byte flag)
        {
            if (!IsInsideTree()) return;
            if (_updateFlags == UPDATE_FLAG_NONE && !_updating)
                (GetTree() ?? SceneTree.Current)?.Defer(_deferredUpdate);       // (never more than once a frame)
            _updateFlags |= flag;
        }

        public override void _Notification(int what)
        {
            base._Notification(what);
            if (what == NOTIFICATION_UPDATE_SKELETON) UpdateSkeletonNotification();
        }

        void UpdateSkeletonNotification()
        {
            ForceUpdateAllDirtyBones();
            _updating = true;
            int len = _bones.Count;
            FindModifiers();
            bool hasMods = _modifiers.Count > 0;
            if (hasMods)
            {
                if (_backup.Length < len) _backup = new BonePoseBackup[len];
                for (int i = 0; i < len; i++) _backup[i].Save(_bones[i]);
                if (_dirtyBackup.Length != _boneGlobalPoseDirty.Length) _dirtyBackup = new bool[_boneGlobalPoseDirty.Length];
                Array.Copy(_boneGlobalPoseDirty, _dirtyBackup, _boneGlobalPoseDirty.Length);
                if ((_updateFlags & UPDATE_FLAG_MODIFIER) != 0) ProcessModifiers();
            }
            if ((_updateFlags & UPDATE_FLAG_POSE) == 0)
            {
                _updating = false;
                _updateFlags = UPDATE_FLAG_NONE;
                return;
            }
            SkeletonUpdated?.Invoke();
            // "update skins": the snapshot the renderer skins with (see GetSkinTransforms)
            if (_skinPose.Length < len) _skinPose = new Xform3[len];
            for (int i = 0; i < len; i++) _skinPose[i] = _bones[i].globalPose;
            _skinPoseCount = len;
            PoseVersion++;
            NotifySkinnedPoseChanged();
            if (hasMods)
            {
                for (int i = 0; i < len && i < _bones.Count; i++) _backup[i].Restore(_bones[i]);
                if (_dirtyBackup.Length == _boneGlobalPoseDirty.Length) Array.Copy(_dirtyBackup, _boneGlobalPoseDirty, _dirtyBackup.Length);
            }
            _updating = false;
            _updateFlags = UPDATE_FLAG_NONE;
        }

        // ------------------------------------------------------------------ tree
        protected override void OnEnterTree()
        {
            base.OnEnterTree();
            ProcessChanged();
            _physics.EnterTree();
        }

        protected override void OnExitTree()
        {
            _physics.ExitTree();
            base.OnExitTree();
        }

        protected override void OnPostEnterTree()
        {
            base.OnPostEnterTree();
            MakeDirty();
            MakeModifiersDirty();
            ForceUpdateAllDirtyBones();
            _updateFlags |= UPDATE_FLAG_POSE;
            UpdateSkeletonNotification();
        }

        protected override void InternalProcess(double delta) => Advance(delta);

        // ------------------------------------------------------------------ modifiers
        /// <summary>advance(delta): the modifiers' step (MANUAL modifier callback mode calls it by hand).</summary>
        public void Advance(double delta)
        {
            FindModifiers();
            if (_modifiers.Count > 0)
            {
                _updateDelta += delta;
                UpdateDeferred(UPDATE_FLAG_MODIFIER);
            }
        }

        public ModifierCallbackModeProcessEnum ModifierCallbackModeProcess
        {
            get => _modifierMode;
            set
            {
                if (_modifierMode == value) return;
                _modifierMode = value;
                ProcessChanged();
            }
        }

        void ProcessChanged()
        {
            SetProcessInternal(_modifierMode == ModifierCallbackModeProcessEnum.Idle);
            _physics.Set(_modifierMode == ModifierCallbackModeProcessEnum.Physics);
        }

        void MakeModifiersDirty()
        {
            _modifiersDirty = true;
            UpdateDeferred(UPDATE_FLAG_MODIFIER);
        }

        void FindModifiers()
        {
            if (!_modifiersDirty) return;
            _modifiers.Clear();
            var ch = AllChildren;
            for (int i = 0; i < ch.Count; i++)
                if (ch[i] is SkeletonModifier3D m) _modifiers.Add(m);
            _modifiersDirty = false;
        }

        void ProcessModifiers()
        {
            for (int mi = 0; mi < _modifiers.Count; mi++)
            {
                var mod = _modifiers[mi];
                if (mod == null || mod.IsFreed) continue;
                float influence = (float)mod.Influence;
                if (influence < 1.0f)
                {
                    _modifierUpdating = true;
                    mod.ProcessModification(_updateDelta);
                    _modifierUpdating = false;
                    for (int i = 0; i < _bones.Count; i++)
                    {
                        var b = _bones[i];
                        if (!b.modifierApplied) continue;
                        b.UpdatePoseCache();
                        if (b.poseCache == b.modifierPoseCache) continue;
                        SetBonePose(i, b.modifierPoseCache.InterpolateWith(b.poseCache, influence));
                        b.modifierApplied = false;
                    }
                }
                else mod.ProcessModification(_updateDelta);
                ForceUpdateAllDirtyBones();
            }
            _updateDelta = 0;
        }

        protected override void AddChildNotify(Node child)
        {
            base.AddChildNotify(child);
            if (child is SkeletonModifier3D) MakeModifiersDirty();
        }

        protected override void MoveChildNotify(Node child)
        {
            base.MoveChildNotify(child);
            if (child is SkeletonModifier3D) MakeModifiersDirty();
        }

        protected override void RemoveChildNotify(Node child)
        {
            base.RemoveChildNotify(child);
            if (child is SkeletonModifier3D) MakeModifiersDirty();
        }

        // ------------------------------------------------------------------ skinning (the renderer's side)
        /// <summary>The skin transforms to draw a mesh skinned by `skin` with: dst[i] = global_pose[bind i's bone] *
        /// bind_pose[i], from the pose of the last skeleton update (what Godot sends the RenderingServer). A null skin uses
        /// the skeleton's own rest skin (create_skin_from_rest_transforms, as a MeshInstance3D without a skin). dst must
        /// hold the skin's bind count. No allocation once the binding is cached.</summary>
        public void GetSkinTransforms(Skin skin, Xform3[] dst)
        {
            if (skin == null)
            {
                if (_restSkin == null || _restSkinVersion != _version) { _restSkin = CreateSkinFromRestTransforms(); _restSkinVersion = _version; }
                skin = _restSkin;
            }
            int len = _bones.Count;
            if (_skinPoseCount != len)
            {
                // (no update yet since the bones changed: the current global poses)
                if (_skinPose.Length < len) _skinPose = new Xform3[len];
                for (int i = 0; i < len; i++) _skinPose[i] = GetBoneGlobalPose(i);
                _skinPoseCount = len;
            }
            var binding = Bind(skin);
            var binds = skin.Binds;
            int n = Math.Min(binds.Count, dst.Length);
            for (int i = 0; i < n; i++)
            {
                int bi = binding.bones[i];
                dst[i] = (uint)bi < (uint)len ? _skinPose[bi] * binds[i].Pose : binds[i].Pose;
            }
        }

        /// <summary>The bone each bind of `skin` follows (resolved as Godot does: by name when the bind has one, else by
        /// index; 0 with an error when neither works). Cached until the skin or the skeleton's bones change.</summary>
        public int GetSkinBindBone(Skin skin, int bind)
        {
            var b = Bind(skin);
            return (uint)bind < (uint)b.bones.Length ? b.bones[bind] : -1;
        }

        SkinBinding Bind(Skin skin)
        {
            if (!_skinBindings.TryGetValue(skin, out var sb)) { sb = new SkinBinding(); _skinBindings[skin] = sb; }
            var binds = skin.Binds;
            if (sb.skeletonVersion == _version && sb.skinVersion == skin.version && sb.bones.Length == binds.Count) return sb;
            int len = _bones.Count;
            if (sb.bones.Length != binds.Count) sb.bones = new int[binds.Count];
            for (int i = 0; i < binds.Count; i++)
            {
                string bn = binds[i].Name;
                if (!string.IsNullOrEmpty(bn))
                {
                    int f = FindBone(bn);
                    if (f < 0) { GD.PushError("Skin bind #" + i + " contains named bind '" + bn + "' but Skeleton3D has no bone by that name."); f = 0; }
                    sb.bones[i] = f;
                }
                else if (binds[i].Bone >= 0)
                {
                    int bi = binds[i].Bone;
                    if (bi >= len) { GD.PushError("Skin bind #" + i + " contains bone index bind: " + bi + " , which is greater than the skeleton bone count: " + len + "."); bi = 0; }
                    sb.bones[i] = bi;
                }
                else
                {
                    GD.PushError("Skin bind #" + i + " does not contain a name nor a bone index.");
                    sb.bones[i] = 0;
                }
            }
            sb.skeletonVersion = _version;
            sb.skinVersion = skin.version;
            return sb;
        }
    }

    /// <summary>Godot's SkeletonModifier3D (scene/3d/skeleton_modifier_3d.cpp): a child of a Skeleton3D that changes its
    /// bone poses once per frame after the animation (IK, look-at, ragdolls: PhysicalBoneSimulator3D). Override
    /// _ProcessModificationWithDelta and set poses on GetSkeleton() (SetBonePose*, SetBoneGlobalPose); with Influence &lt; 1
    /// the skeleton blends each changed bone between the animated pose and yours. Runs during the skeleton's deferred update
    /// (when the skeleton's process mode lets it advance); the skins and BoneAttachment3Ds show the result, then the
    /// skeleton restores the animated poses.</summary>
    public class SkeletonModifier3D : Node3D
    {
        bool _active = true;
        Skeleton3D _skeleton;
        public double Influence = 1.0;
        public event Action ModificationProcessed;

        public Skeleton3D GetSkeleton() => _skeleton != null && !_skeleton.IsFreed ? _skeleton : null;

        public bool Active
        {
            get => _active;
            set
            {
                if (_active == value) return;
                _active = value;
                _SetActive(value);
                ForceUpdateSkeletonSkin();
            }
        }
        public void SetActive(bool on) => Active = on;
        public bool IsActive() => _active;
        public void SetInfluence(double v) => Influence = v;
        public double GetInfluence() => Influence;

        protected virtual void _SetActive(bool active) { }
        /// <summary>The modification itself (Godot's _process_modification_with_delta).</summary>
        protected virtual void _ProcessModificationWithDelta(double delta) { }
        protected virtual void _SkeletonChanged(Skeleton3D oldSkeleton, Skeleton3D newSkeleton) { }
        protected virtual void _ValidateBoneNames() { }

        internal void ProcessModification(double delta)
        {
            if (!IsInsideTree() || !_active) return;
            _ProcessModificationWithDelta(delta);
            ModificationProcessed?.Invoke();
        }

        void UpdateSkeleton()
        {
            if (!IsInsideTree()) return;
            var old = GetSkeleton();
            _skeleton = Parent as Skeleton3D;
            var nw = GetSkeleton();
            if (old != nw) _SkeletonChanged(old, nw);
            if (nw != null) _ValidateBoneNames();
        }

        void ForceUpdateSkeletonSkin()
        {
            if (!IsInsideTree()) return;
            GetSkeleton()?.ForceUpdateDeferred();
        }

        protected override void OnEnterTree() { base.OnEnterTree(); UpdateSkeleton(); }
        protected override void OnParented() { base.OnParented(); UpdateSkeleton(); }
        protected override void OnExitTree() { ForceUpdateSkeletonSkin(); base.OnExitTree(); }
        protected override void OnUnparented() { ForceUpdateSkeletonSkin(); base.OnUnparented(); }
    }

    /// <summary>set_physics_process_internal for the engine-free nodes: the callback runs at the start of each physics
    /// tick (SceneTree.PhysicsFrame) with the physics step, while the node is in the tree, enabled and can process.</summary>
    internal sealed class InternalPhysicsProcess
    {
        readonly Node _node;
        readonly Action<double> _cb;
        readonly Action _tick;
        SceneTree _tree;
        bool _on;

        public InternalPhysicsProcess(Node node, Action<double> cb)
        {
            _node = node;
            _cb = cb;
            _tick = Tick;
        }

        public bool On => _on;

        public void Set(bool on)
        {
            if (_on == on) return;
            _on = on;
            if (on && _node.IsInsideTree()) Hook();
            else if (!on) Unhook();
        }

        public void EnterTree() { if (_on) Hook(); }
        public void ExitTree() => Unhook();

        void Hook()
        {
            if (_tree != null) return;
            _tree = _node.GetTree();
            if (_tree != null) _tree.PhysicsFrame += _tick;
        }

        void Unhook()
        {
            if (_tree == null) return;
            _tree.PhysicsFrame -= _tick;
            _tree = null;
        }

        void Tick()
        {
            var t = _tree;
            if (t == null || !_node.IsInsideTree() || _node.IsFreed || !_node.CanProcess()) return;
            _cb(1.0 / t.PhysicsTicksPerSecond * t.TimeScale);
        }
    }
}

#endif
