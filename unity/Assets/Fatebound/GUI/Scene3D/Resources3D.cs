#if FB3D
// Small 3D resources: Skin (bind poses by bone index or name), MultiMesh (instanced transforms/colours/custom data),
// and the Environment class's seam (its properties: Environment3D.cs).
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public sealed class Skin : Resource
    {
        public struct Bind { public int Bone; public string Name; public Xform3 Pose; }
        readonly List<Bind> _binds = new List<Bind>();
        public IReadOnlyList<Bind> Binds => _binds;

        public int GetBindCount() => _binds.Count;
        public void SetBindCount(int n)
        {
            while (_binds.Count < n) _binds.Add(new Bind { Bone = -1, Name = "", Pose = Xform3.IDENTITY });
            if (_binds.Count > n) _binds.RemoveRange(n, _binds.Count - n);
            EmitChanged();
        }
        public void AddBind(int bone, Xform3 pose) { _binds.Add(new Bind { Bone = bone, Name = "", Pose = pose }); EmitChanged(); }
        public void AddNamedBind(string name, Xform3 pose) { _binds.Add(new Bind { Bone = -1, Name = name ?? "", Pose = pose }); EmitChanged(); }
        public void ClearBinds() { _binds.Clear(); EmitChanged(); }
        public string GetBindName(int i) => _binds[i].Name;
        public void SetBindName(int i, string n) { var b = _binds[i]; b.Name = n ?? ""; _binds[i] = b; EmitChanged(); }
        public int GetBindBone(int i) => _binds[i].Bone;
        public void SetBindBone(int i, int bone) { var b = _binds[i]; b.Bone = bone; _binds[i] = b; EmitChanged(); }
        public Xform3 GetBindPose(int i) => _binds[i].Pose;
        public void SetBindPose(int i, Xform3 p) { var b = _binds[i]; b.Pose = p; _binds[i] = b; EmitChanged(); }

        public override Resource Duplicate(bool deep = false)
        {
            var s = new Skin { ResourceName = ResourceName };
            s._binds.AddRange(_binds);
            return s;
        }
    }

    public sealed class MultiMesh : Resource
    {
        public enum TransformFormatEnum { Transform2D = 0, Transform3D = 1 }
        public const TransformFormatEnum TRANSFORM_2D = TransformFormatEnum.Transform2D, TRANSFORM_3D = TransformFormatEnum.Transform3D;
        public const int PHYSICS_INTERPOLATION_QUALITY_FAST = 0, PHYSICS_INTERPOLATION_QUALITY_HIGH = 1;

        TransformFormatEnum _format = TransformFormatEnum.Transform2D;
        bool _useColors, _useCustom;
        int _count, _visible = -1;
        Mesh _mesh;
        Xform3[] _xf = Array.Empty<Xform3>();
        Col[] _colors = Array.Empty<Col>();
        Col[] _custom = Array.Empty<Col>();
        Aabb _customAabb;
        /// <summary>Bumped whenever an instance changes (the renderer re-uploads).</summary>
        public int InstancesVersion { get; private set; }

        public TransformFormatEnum TransformFormat { get => _format; set { _format = value; EmitChanged(); } }
        public bool UseColors { get => _useColors; set { _useColors = value; EmitChanged(); } }
        public bool UseCustomData { get => _useCustom; set { _useCustom = value; EmitChanged(); } }
        public Mesh Mesh { get => _mesh; set { _mesh = value; EmitChanged(); } }
        public Aabb CustomAabb { get => _customAabb; set { _customAabb = value; EmitChanged(); } }

        /// <summary>instance_count: setting it clears every instance (as Godot does).</summary>
        public int InstanceCount
        {
            get => _count;
            set
            {
                _count = Math.Max(0, value);
                _xf = new Xform3[_count];
                for (int i = 0; i < _count; i++) _xf[i] = Xform3.IDENTITY;
                _colors = new Col[_count];
                for (int i = 0; i < _count; i++) _colors[i] = Col.WHITE;
                _custom = new Col[_count];
                InstancesVersion++;
                EmitChanged();
            }
        }

        public int VisibleInstanceCount { get => _visible; set { _visible = Math.Min(value, _count); InstancesVersion++; EmitChanged(); } }

        public void SetInstanceTransform(int i, Xform3 t)
        {
            if ((uint)i >= (uint)_count) { GD.PushError("MultiMesh: instance index out of range."); return; }
            _xf[i] = t;
            InstancesVersion++;
            EmitChanged();
        }

        public void SetInstanceTransform2D(int i, Xform2 t)
        {
            if ((uint)i >= (uint)_count) return;
            var b = Basis.IDENTITY;
            b.SetColumn(0, new Vec3(t.x.x, t.x.y, 0f));
            b.SetColumn(1, new Vec3(t.y.x, t.y.y, 0f));
            _xf[i] = new Xform3(b, new Vec3(t.origin.x, t.origin.y, 0f));
            InstancesVersion++;
            EmitChanged();
        }

        public Xform3 GetInstanceTransform(int i) => (uint)i < (uint)_count ? _xf[i] : Xform3.IDENTITY;

        public void SetInstanceColor(int i, Col c)
        {
            if ((uint)i >= (uint)_count) return;
            _colors[i] = c;
            InstancesVersion++;
            EmitChanged();
        }

        public Col GetInstanceColor(int i) => (uint)i < (uint)_count ? _colors[i] : Col.WHITE;

        public void SetInstanceCustomData(int i, Col c)
        {
            if ((uint)i >= (uint)_count) return;
            _custom[i] = c;
            InstancesVersion++;
            EmitChanged();
        }

        public Col GetInstanceCustomData(int i) => (uint)i < (uint)_count ? _custom[i] : new Col(0, 0, 0, 0);

        public IReadOnlyList<Xform3> Transforms => _xf;
        public IReadOnlyList<Col> Colors => _colors;
        public IReadOnlyList<Col> CustomData => _custom;
        public int DrawnCount => _visible < 0 ? _count : Math.Min(_visible, _count);

        public Aabb GetAabb()
        {
            if (_customAabb.size != Vec3.Zero) return _customAabb;
            if (_mesh == null || _count == 0) return new Aabb();
            Aabb ma = _mesh.GetAabb();
            Aabb a = _xf[0] * ma;
            for (int i = 1; i < DrawnCount; i++) a = a.Merge(_xf[i] * ma);
            return a;
        }
    }
}

#endif
