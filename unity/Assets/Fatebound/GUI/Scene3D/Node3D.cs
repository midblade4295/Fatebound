#if FB3D
// Godot's Node3D (scene/3d/node_3d.cpp) for the ported 3D code: local transform with Godot's euler/scale caching
// (rotation edit modes, rotation order), the global transform computed lazily down the Node3D parent chain, top level,
// visibility, notifications (ENTER/EXIT_WORLD, TRANSFORM_CHANGED flushed by the SceneTree like Godot's
// xform_change_list), and the helpers (look_at, rotate_*, translate, to_local/to_global...).
// Engine-free: what's drawn is read by the host's renderer through RenderSync (Render3D.cs).
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public partial class Node3D : Node
    {
        public const int NOTIFICATION_TRANSFORM_CHANGED = 2000, NOTIFICATION_ENTER_WORLD = 41, NOTIFICATION_EXIT_WORLD = 42,
            NOTIFICATION_VISIBILITY_CHANGED_3D = 43, NOTIFICATION_LOCAL_TRANSFORM_CHANGED = 44;

        public enum RotationEditModeEnum { Euler = 0, Quaternion = 1, Basis = 2 }
        public const RotationEditModeEnum ROTATION_EDIT_MODE_EULER = RotationEditModeEnum.Euler,
            ROTATION_EDIT_MODE_QUATERNION = RotationEditModeEnum.Quaternion, ROTATION_EDIT_MODE_BASIS = RotationEditModeEnum.Basis;

        const int DIRTY_NONE = 0, DIRTY_EULER_ROTATION_AND_SCALE = 1, DIRTY_LOCAL_TRANSFORM = 2, DIRTY_GLOBAL_TRANSFORM = 4;

        Xform3 _local = Xform3.IDENTITY;
        Xform3 _global = Xform3.IDENTITY;
        Vec3 _euler;
        Vec3 _scale = new Vec3(1f, 1f, 1f);
        EulerOrder _order = EulerOrder.YXZ;
        RotationEditModeEnum _editMode = RotationEditModeEnum.Euler;
        int _dirty;
        Node3D _parent3d;
        internal readonly List<Node3D> children3d = new List<Node3D>();
        bool _topLevel, _visible = true, _notifyTransform, _notifyLocal, _disableScale, _insideWorld;
        internal bool inXformChangeList;
        Viewport _viewport;

        public event Action VisibilityChanged;

        // ------------------------------------------------------------------ dirty bits
        bool TestDirty(int b) => (_dirty & b) != 0;

        void UpdateLocalTransform()
        {
            _local.basis = Basis.FromEuler(_euler, _order) * Basis.FromScale(_scale);     // (set_euler_scale)
            _dirty &= ~DIRTY_LOCAL_TRANSFORM;
        }

        void UpdateRotationAndScale()
        {
            _scale = _local.basis.GetScale();
            _euler = _local.basis.GetEulerNormalized(_order);
            _dirty &= ~DIRTY_EULER_ROTATION_AND_SCALE;
        }

        void NotifyDirty()
        {
            if (_notifyTransform && !inXformChangeList && IsInsideTree())
            {
                inXformChangeList = true;
                GetTree().xformChangeList.Add(this);
            }
        }

        void PropagateTransformChanged()
        {
            if (!IsInsideTree()) return;
            for (int i = 0; i < children3d.Count; i++)
            {
                var c = children3d[i];
                if (!c._topLevel) c.PropagateTransformChanged();
            }
            if (_notifyTransform && !inXformChangeList)
            {
                inXformChangeList = true;
                GetTree().xformChangeList.Add(this);
            }
            _dirty |= DIRTY_GLOBAL_TRANSFORM;
        }

        void LocalChanged()
        {
            PropagateTransformChanged();
            if (_notifyLocal) _Notification(NOTIFICATION_LOCAL_TRANSFORM_CHANGED);
        }

        // ------------------------------------------------------------------ tree / world
        protected override void OnEnterTree()
        {
            base.OnEnterTree();
            _parent3d = Parent as Node3D;
            _parent3d?.children3d.Add(this);
            if (_topLevel && _parent3d != null)
            {
                _local = GetTransformInternal();
                _dirty = DIRTY_EULER_ROTATION_AND_SCALE;
            }
            _dirty |= DIRTY_GLOBAL_TRANSFORM;
            NotifyDirty();
            _insideWorld = true;
            _viewport = null;
            for (var p = Parent; p != null && _viewport == null; p = p.Parent) _viewport = p as Viewport;
            OnEnterWorld();
            _Notification(NOTIFICATION_ENTER_WORLD);
        }

        protected override void OnExitTree()
        {
            _Notification(NOTIFICATION_EXIT_WORLD);
            OnExitWorld();
            if (inXformChangeList)
            {
                GetTree()?.xformChangeList.Remove(this);
                inXformChangeList = false;
            }
            _parent3d?.children3d.Remove(this);
            _parent3d = null;
            _viewport = null;
            _insideWorld = false;
            base.OnExitTree();
        }

        /// <summary>Entering the 3D world (subclasses create their render instance here).</summary>
        protected virtual void OnEnterWorld() { }
        protected virtual void OnExitWorld() { }
        /// <summary>NOTIFICATION_TRANSFORM_CHANGED for subclasses (only when set_notify_transform is on).</summary>
        protected virtual void OnTransformChanged() { }
        protected virtual void OnVisibilityChanged3D() { }

        internal void DeliverTransformChanged()
        {
            inXformChangeList = false;
            OnTransformChanged();
            _Notification(NOTIFICATION_TRANSFORM_CHANGED);
        }

        public bool IsInsideWorld() => _insideWorld;
        public Viewport GetViewport3D() => _viewport;
        public override Viewport GetViewport() => _viewport ?? base.GetViewport();
        public World3D GetWorld3D() => _viewport?.FindWorld3D();
        public Node3D GetParentNode3D() => _topLevel ? null : Parent as Node3D;

        // ------------------------------------------------------------------ transform
        Xform3 GetTransformInternal()
        {
            if (TestDirty(DIRTY_LOCAL_TRANSFORM)) UpdateLocalTransform();
            return _local;
        }

        public Xform3 Transform
        {
            get => GetTransformInternal();
            set
            {
                _local = value;
                _dirty = DIRTY_EULER_ROTATION_AND_SCALE | (_dirty & DIRTY_GLOBAL_TRANSFORM);
                LocalChanged();
            }
        }

        public Xform3 GetTransform() => Transform;
        public void SetTransform(Xform3 t) => Transform = t;

        public Xform3 GlobalTransform
        {
            get
            {
                if (TestDirty(DIRTY_GLOBAL_TRANSFORM))
                {
                    if (TestDirty(DIRTY_LOCAL_TRANSFORM)) UpdateLocalTransform();
                    Xform3 g = _parent3d != null && !_topLevel ? _parent3d.GlobalTransform * _local : _local;
                    if (_disableScale) g.basis = g.basis.Orthonormalized();
                    _global = g;
                    _dirty &= ~DIRTY_GLOBAL_TRANSFORM;
                }
                return _global;
            }
            set
            {
                Transform = _parent3d != null && !_topLevel ? _parent3d.GlobalTransform.AffineInverse() * value : value;
            }
        }

        public Xform3 GetGlobalTransform() => GlobalTransform;
        public void SetGlobalTransform(Xform3 t) => GlobalTransform = t;

        public Vec3 Position
        {
            get => _local.origin;
            set
            {
                _local.origin = value;
                LocalChanged();
            }
        }

        public Vec3 Rotation
        {
            get
            {
                if (TestDirty(DIRTY_EULER_ROTATION_AND_SCALE)) UpdateRotationAndScale();
                return _euler;
            }
            set
            {
                if (TestDirty(DIRTY_EULER_ROTATION_AND_SCALE))
                {
                    _scale = _local.basis.GetScale();
                    _dirty &= ~DIRTY_EULER_ROTATION_AND_SCALE;
                }
                _euler = value;
                _dirty = DIRTY_LOCAL_TRANSFORM | (_dirty & DIRTY_GLOBAL_TRANSFORM);
                LocalChanged();
            }
        }

        public Vec3 RotationDegrees
        {
            get { var r = Rotation; return new Vec3(GD.RadToDeg(r.x), GD.RadToDeg(r.y), GD.RadToDeg(r.z)); }
            set => Rotation = new Vec3(GD.DegToRad(value.x), GD.DegToRad(value.y), GD.DegToRad(value.z));
        }

        public Vec3 Scale
        {
            get
            {
                if (TestDirty(DIRTY_EULER_ROTATION_AND_SCALE)) UpdateRotationAndScale();
                return _scale;
            }
            set
            {
                if (TestDirty(DIRTY_EULER_ROTATION_AND_SCALE))
                {
                    _euler = _local.basis.GetEulerNormalized(_order);
                    _dirty &= ~DIRTY_EULER_ROTATION_AND_SCALE;
                }
                _scale = value;
                _dirty = DIRTY_LOCAL_TRANSFORM | (_dirty & DIRTY_GLOBAL_TRANSFORM);
                LocalChanged();
            }
        }

        public Basis Basis
        {
            get => GetTransformInternal().basis;
            set => Transform = new Xform3(value, _local.origin);
        }

        public Quat Quaternion
        {
            get => GetTransformInternal().basis.GetRotationQuaternion();
            set
            {
                if (TestDirty(DIRTY_EULER_ROTATION_AND_SCALE))
                {
                    _scale = _local.basis.GetScale();
                    _dirty &= ~DIRTY_EULER_ROTATION_AND_SCALE;
                }
                _local.basis = new Basis(value, _scale);
                _euler = _local.basis.GetEulerNormalized(_order);
                _dirty &= DIRTY_GLOBAL_TRANSFORM;
                LocalChanged();
            }
        }

        public EulerOrder RotationOrder
        {
            get => _order;
            set
            {
                if (_order == value) return;
                bool changed = false;
                if (TestDirty(DIRTY_EULER_ROTATION_AND_SCALE)) UpdateRotationAndScale();
                else if (TestDirty(DIRTY_LOCAL_TRANSFORM))
                {
                    _euler = Basis.FromEuler(_euler, _order).GetEulerNormalized(value);
                    changed = true;
                }
                else
                {
                    _dirty |= DIRTY_LOCAL_TRANSFORM;
                    changed = true;
                }
                _order = value;
                if (changed) LocalChanged();
            }
        }

        public RotationEditModeEnum RotationEditMode
        {
            get => _editMode;
            set
            {
                if (_editMode == value) return;
                bool changed = false;
                if (_editMode == RotationEditModeEnum.Basis && !TestDirty(DIRTY_LOCAL_TRANSFORM))
                {
                    _local = _local.Orthogonalized();
                    changed = true;
                }
                _editMode = value;
                if (value == RotationEditModeEnum.Euler && TestDirty(DIRTY_EULER_ROTATION_AND_SCALE)) UpdateRotationAndScale();
                if (changed) LocalChanged();
            }
        }

        public Vec3 GlobalPosition
        {
            get => GlobalTransform.origin;
            set { var t = GlobalTransform; t.origin = value; GlobalTransform = t; }
        }

        public Basis GlobalBasis
        {
            get => GlobalTransform.basis;
            set { var t = GlobalTransform; t.basis = value; GlobalTransform = t; }
        }

        public Vec3 GlobalRotation
        {
            get => GlobalTransform.basis.GetEulerNormalized(EulerOrder.YXZ);
            set
            {
                var t = GlobalTransform;
                t.basis = Basis.FromEuler(value, EulerOrder.YXZ) * Basis.FromScale(t.basis.GetScale());
                GlobalTransform = t;
            }
        }

        public Vec3 GlobalRotationDegrees
        {
            get { var r = GlobalRotation; return new Vec3(GD.RadToDeg(r.x), GD.RadToDeg(r.y), GD.RadToDeg(r.z)); }
            set => GlobalRotation = new Vec3(GD.DegToRad(value.x), GD.DegToRad(value.y), GD.DegToRad(value.z));
        }

        public bool TopLevel
        {
            get => _topLevel;
            set
            {
                if (_topLevel == value) return;
                if (IsInsideTree())
                {
                    if (value) Transform = GlobalTransform;
                    else if (_parent3d != null) Transform = _parent3d.GlobalTransform.AffineInverse() * GlobalTransform;
                }
                _topLevel = value;
            }
        }

        public void SetAsTopLevel(bool on) => TopLevel = on;
        public bool IsSetAsTopLevel() => _topLevel;

        public bool DisableScale { get => _disableScale; set => _disableScale = value; }

        public Xform3 GetRelativeTransform(Node parent)
        {
            if (parent == this) return Xform3.IDENTITY;
            if (_parent3d == null) return Xform3.IDENTITY;
            if (parent == _parent3d) return Transform;
            return _parent3d.GetRelativeTransform(parent) * Transform;
        }

        public void SetNotifyTransform(bool on) => _notifyTransform = on;
        public bool IsTransformNotificationEnabled() => _notifyTransform;
        public void SetNotifyLocalTransform(bool on) => _notifyLocal = on;
        public bool IsLocalTransformNotificationEnabled() => _notifyLocal;

        public void ForceUpdateTransform()
        {
            if (!IsInsideTree() || !inXformChangeList) return;
            GetTree().xformChangeList.Remove(this);
            DeliverTransformChanged();
        }

        // ------------------------------------------------------------------ visibility
        public bool Visible
        {
            get => _visible;
            set
            {
                if (_visible == value) return;
                _visible = value;
                if (!IsInsideTree()) return;
                PropagateVisibilityChanged();
            }
        }

        public void Show() => Visible = true;
        public void Hide() => Visible = false;
        public bool IsVisible() => _visible;

        public bool IsVisibleInTree()
        {
            for (var s = this; s != null; s = s._parent3d)
                if (!s._visible) return false;
            return true;
        }

        void PropagateVisibilityChanged()
        {
            OnVisibilityChanged3D();
            _Notification(NOTIFICATION_VISIBILITY_CHANGED_3D);
            VisibilityChanged?.Invoke();
            for (int i = 0; i < children3d.Count; i++)
                if (children3d[i]._visible) children3d[i].PropagateVisibilityChanged();
        }

        // ------------------------------------------------------------------ helpers
        public void RotateObjectLocal(Vec3 axis, double angle)
        {
            var t = Transform;
            t.basis = t.basis.RotatedLocal(axis, (float)angle);
            Transform = t;
        }

        public void Rotate(Vec3 axis, double angle)
        {
            var t = Transform;
            t.basis = t.basis.Rotated(axis, (float)angle);
            Transform = t;
        }

        public void RotateX(double angle) => Rotate(new Vec3(1f, 0f, 0f), angle);
        public void RotateY(double angle) => Rotate(new Vec3(0f, 1f, 0f), angle);
        public void RotateZ(double angle) => Rotate(new Vec3(0f, 0f, 1f), angle);

        public void Translate(Vec3 offset)
        {
            var t = Transform;
            Transform = t.TranslatedLocal(offset);
        }

        public void TranslateObjectLocal(Vec3 offset)
        {
            var t = Transform;
            Transform = t * new Xform3(Basis.IDENTITY, offset);
        }

        public void ScaleBy(Vec3 ratio)
        {
            var t = Transform;
            t.basis = t.basis.Scaled(ratio);
            Transform = t;
        }

        public void ScaleObjectLocal(Vec3 s)
        {
            var t = Transform;
            t.basis = t.basis.ScaledLocal(s);
            Transform = t;
        }

        public void GlobalRotate(Vec3 axis, double angle)
        {
            var t = GlobalTransform;
            t.basis = t.basis.Rotated(axis, (float)angle);
            GlobalTransform = t;
        }

        public void GlobalScale(Vec3 s)
        {
            var t = GlobalTransform;
            t.basis = t.basis.Scaled(s);
            GlobalTransform = t;
        }

        public void GlobalTranslate(Vec3 offset)
        {
            var t = GlobalTransform;
            t.origin = t.origin + offset;
            GlobalTransform = t;
        }

        public void Orthonormalize() => Transform = Transform.Orthonormalized();
        public void SetIdentity() => Transform = Xform3.IDENTITY;

        public void LookAt(Vec3 target, Vec3? up = null, bool useModelFront = false)
        {
            if (!IsInsideTree()) { GD.PushError("Node not inside tree. Use look_at_from_position() instead."); return; }
            LookAtFromPosition(GlobalTransform.origin, target, up, useModelFront);
        }

        public void LookAtFromPosition(Vec3 pos, Vec3 target, Vec3? up = null, bool useModelFront = false)
        {
            Vec3 u = up ?? new Vec3(0f, 1f, 0f);
            if (pos.IsEqualApprox(target)) { GD.PushError("Node origin and target are in the same position, look_at() failed."); return; }
            if (u.IsZeroApprox()) { GD.PushError("The up vector can't be zero, look_at() failed."); return; }
            Vec3 forward = target - pos;
            Basis lookat = Basis.LookingAt(forward, u, useModelFront);
            Vec3 originalScale = Scale;
            GlobalTransform = new Xform3(lookat, pos);
            Scale = originalScale;
        }

        public Vec3 ToLocal(Vec3 global) => GlobalTransform.AffineInverse().Xform(global);
        public Vec3 ToGlobal(Vec3 local) => GlobalTransform.Xform(local);

        /// <summary>reparent(new_parent, keep_global_transform).</summary>
        public void Reparent3D(Node newParent, bool keepGlobal = true)
        {
            if (keepGlobal && IsInsideTree())
            {
                var g = GlobalTransform;
                Reparent(newParent, false);
                GlobalTransform = g;
            }
            else Reparent(newParent, false);
        }
    }

    /// <summary>Marker3D: a Node3D that marks a place.</summary>
    public class Marker3D : Node3D
    {
        public double GizmoExtents = 0.25;
    }
}

#endif
