#if FB3D
// Godot's BoneAttachment3D (scene/3d/bone_attachment_3d.cpp): a Node3D that follows a bone of its parent Skeleton3D (or
// of an external one): when it enters the tree it binds to the bone (bone_name -> find_bone, if bone_idx isn't set) and
// takes the bone's global pose as its transform; then on each skeleton_updated (the skeleton's deferred per-frame
// update, after the skeleton modifiers) it sets its transform again (its global transform with an external skeleton).
// With override_pose it drives the bone instead (set_bone_global_pose from its own transform when that changes).
using System;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public class BoneAttachment3D : Node3D
    {
        string _boneName = "";
        int _boneIdx = -1;
        bool _overridePose, _overriding, _overrideDirty, _bound, _updating, _useExternal;
        NodePath _externalPath;
        Skeleton3D _externalCache;
        Skeleton3D _boundTo;
        readonly Action _onSkeletonUpdate;

        public BoneAttachment3D() { _onSkeletonUpdate = OnSkeletonUpdate; }

        public string BoneName { get => _boneName; set => SetBoneName(value); }
        public int BoneIdx { get => _boneIdx; set => SetBoneIdx(value); }
        public bool OverridePose { get => _overridePose; set => SetOverridePose(value); }
        public bool UseExternalSkeleton { get => _useExternal; set => SetUseExternalSkeleton(value); }
        public NodePath ExternalSkeleton { get => _externalPath; set => SetExternalSkeleton(value); }

        void UpdateExternalSkeletonCache()
        {
            _externalCache = null;
            Node node = _externalPath.IsEmpty() ? null : GetNodeOrNull(_externalPath.NodePart);
            if (node != null)
            {
                if (!(node is Skeleton3D sk)) { GD.PushError("Cannot update external skeleton cache: Skeleton3D Nodepath does not point to a Skeleton3D node!"); return; }
                _externalCache = sk;
            }
            else if (_externalPath.IsEmpty() && Parent is BoneAttachment3D pa)
            {
                pa.UpdateExternalSkeletonCache();
                if (pa._externalCache != null) _externalCache = pa._externalCache;
            }
        }

        void CheckBind()
        {
            var sk = GetSkeleton();
            if (sk != null && !_bound)
            {
                if (_boneIdx <= -1) _boneIdx = sk.FindBone(_boneName);
                if (_boneIdx != -1)
                {
                    sk.SkeletonUpdated += _onSkeletonUpdate;
                    _boundTo = sk;
                    _bound = true;
                    OnSkeletonUpdate();
                }
            }
        }

        public Skeleton3D GetSkeleton()
        {
            if (_useExternal)
            {
                if (_externalCache != null && !_externalCache.IsFreed) return _externalCache;
                UpdateExternalSkeletonCache();
                return _externalCache != null && !_externalCache.IsFreed ? _externalCache : null;
            }
            return Parent as Skeleton3D;
        }

        void CheckUnbind()
        {
            if (_bound)
            {
                if (_boundTo != null) _boundTo.SkeletonUpdated -= _onSkeletonUpdate;
                _boundTo = null;
                _bound = false;
            }
        }

        void TransformChanged()
        {
            if (!IsInsideTree()) return;
            if (_overridePose && !_overriding)
            {
                var sk = GetSkeleton();
                if (sk == null) { GD.PushError("Cannot override pose: Skeleton not found!"); return; }
                if ((uint)_boneIdx >= (uint)sk.GetBoneCount()) { GD.PushError("Cannot override pose: Bone index is out of range!"); return; }
                Xform3 ours = Transform;
                if (_useExternal)
                {
                    if (!sk.IsInsideTree()) return;
                    ours = sk.GlobalTransform.AffineInverse() * GlobalTransform;
                }
                _overriding = true;
                sk.SetBoneGlobalPose(_boneIdx, ours);
                sk.ForceUpdateAllDirtyBones();
            }
            _overriding = false;
        }

        public void SetBoneName(string name)
        {
            _boneName = name ?? "";
            var sk = GetSkeleton();
            if (sk != null) SetBoneIdx(sk.FindBone(_boneName));
        }
        public string GetBoneName() => _boneName;

        public void SetBoneIdx(int idx)
        {
            if (IsInsideTree()) CheckUnbind();
            _boneIdx = idx;
            var sk = GetSkeleton();
            if (sk != null)
            {
                if (_boneIdx <= -1 || _boneIdx >= sk.GetBoneCount())
                {
                    GD.PushWarning("Bone index " + _boneIdx + " out of range! Cannot connect BoneAttachment to node!");
                    _boneIdx = -1;
                }
                else _boneName = sk.GetBoneName(_boneIdx);
            }
            if (IsInsideTree()) CheckBind();
            else OnSkeletonUpdate();
        }
        public int GetBoneIdx() => _boneIdx;

        public void SetOverridePose(bool on)
        {
            if (_overridePose == on) return;
            _overridePose = on;
            SetNotifyTransform(on);
            SetProcessInternal(on);
            if (!on && _boneIdx >= 0) GetSkeleton()?.ResetBonePose(_boneIdx);
        }
        public bool GetOverridePose() => _overridePose;

        public void SetUseExternalSkeleton(bool on)
        {
            _useExternal = on;
            if (on)
            {
                CheckUnbind();
                UpdateExternalSkeletonCache();
                CheckBind();
                TransformChanged();
            }
        }
        public bool GetUseExternalSkeleton() => _useExternal;

        public void SetExternalSkeleton(NodePath path)
        {
            _externalPath = path;
            UpdateExternalSkeletonCache();
        }
        public NodePath GetExternalSkeleton() => _externalPath;

        protected override void OnEnterTree()
        {
            base.OnEnterTree();
            if (_useExternal) UpdateExternalSkeletonCache();
            CheckBind();
        }

        protected override void OnExitTree()
        {
            CheckUnbind();
            base.OnExitTree();
        }

        protected override void OnTransformChanged()
        {
            base.OnTransformChanged();
            TransformChanged();
        }

        protected override void InternalProcess(double delta)
        {
            if (_overrideDirty) _overrideDirty = false;
        }

        /// <summary>on_skeleton_update(): takes the bone's pose (or, with override_pose, pushes its own).</summary>
        public void OnSkeletonUpdate()
        {
            if (_updating) return;
            _updating = true;
            if (_boneIdx >= 0)
            {
                var sk = GetSkeleton();
                if (sk != null)
                {
                    if (!_overridePose)
                    {
                        if (_useExternal)
                        {
                            if (sk.IsInsideTree()) GlobalTransform = sk.GlobalTransform * sk.GetBoneGlobalPose(_boneIdx);
                        }
                        else Transform = sk.GetBoneGlobalPose(_boneIdx);
                    }
                    else if (!_overrideDirty)
                    {
                        TransformChanged();
                        _overrideDirty = true;
                    }
                }
            }
            _updating = false;
        }

        public override bool SetStoredProperty(string name, Var value)
        {
            switch (name)
            {
                case "bone_name": SetBoneName(value.AsString()); return true;
                case "bone_idx": SetBoneIdx(value.AsInt()); return true;
                case "override_pose": SetOverridePose(value.Truthy); return true;
                case "use_external_skeleton": SetUseExternalSkeleton(value.Truthy); return true;
                case "external_skeleton": SetExternalSkeleton(new NodePath(value.AsString())); return true;
            }
            return base.SetStoredProperty(name, value);
        }
    }
}

#endif
