#if FB3D
// Godot's 3D collision shapes (scene/resources/3d/*_shape_3d.cpp) for the ported code: the resources a CollisionShape3D
// hands its body. Same defaults, clamps and error rules as Godot 4.7; every change emits `changed` (the bodies using the
// shape re-send it to the physics backend, which reads the values directly -- see Physics3D.cs).
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public abstract partial class Shape3D : Resource
    {
        float _margin = 0.04f, _bias;
        public Col DebugColor = new Col(0f, 0f, 0f, 0f);
        public bool DebugFill = true;

        /// <summary>margin (Godot Physics only: Jolt ignores it, so does the port's backend).</summary>
        public double Margin { get => _margin; set => _margin = (float)value; }
        public double CustomSolverBias { get => _bias; set => _bias = (float)value; }
        public abstract double GetEnclosingRadius();
    }

    public partial class BoxShape3D : Shape3D
    {
        Vec3 _size = new Vec3(1f, 1f, 1f);
        public Vec3 Size
        {
            get => _size;
            set
            {
                if (value.x < 0 || value.y < 0 || value.z < 0) { GD.PushError("BoxShape3D size cannot be negative."); return; }
                _size = value;
                EmitChanged();
            }
        }
        public override double GetEnclosingRadius() => _size.Length() / 2;
    }

    public partial class SphereShape3D : Shape3D
    {
        float _radius = 0.5f;
        public double Radius
        {
            get => _radius;
            set
            {
                if (value < 0) { GD.PushError("SphereShape3D radius cannot be negative."); return; }
                _radius = (float)value;
                EmitChanged();
            }
        }
        public override double GetEnclosingRadius() => _radius;
    }

    /// <summary>Along local Y; height is the whole length, caps included (Godot 4), radius clamped to half of it.</summary>
    public partial class CapsuleShape3D : Shape3D
    {
        float _radius = 0.5f, _height = 2.0f;
        public double Radius
        {
            get => _radius;
            set
            {
                if (value < 0) { GD.PushError("CapsuleShape3D radius cannot be negative."); return; }
                _radius = (float)value;
                if (_height < _radius * 2.0f) _height = _radius * 2.0f;
                EmitChanged();
            }
        }
        public double Height
        {
            get => _height;
            set
            {
                if (value < 0) { GD.PushError("CapsuleShape3D height cannot be negative."); return; }
                _height = (float)value;
                if (_radius > _height * 0.5f) _radius = _height * 0.5f;
                EmitChanged();
            }
        }
        /// <summary>The straight part between the caps.</summary>
        public double MidHeight
        {
            get => _height - _radius * 2.0f;
            set
            {
                if (value < 0) { GD.PushError("CapsuleShape3D mid-height cannot be negative."); return; }
                _height = (float)value + _radius * 2.0f;
                EmitChanged();
            }
        }
        public override double GetEnclosingRadius() => _height * 0.5f;
    }

    /// <summary>Along local Y.</summary>
    public partial class CylinderShape3D : Shape3D
    {
        float _radius = 0.5f, _height = 2.0f;
        public double Radius
        {
            get => _radius;
            set
            {
                if (value < 0) { GD.PushError("CylinderShape3D radius cannot be negative."); return; }
                _radius = (float)value;
                EmitChanged();
            }
        }
        public double Height
        {
            get => _height;
            set
            {
                if (value < 0) { GD.PushError("CylinderShape3D height cannot be negative."); return; }
                _height = (float)value;
                EmitChanged();
            }
        }
        public override double GetEnclosingRadius() => new Vec2(_radius, _height * 0.5f).Length();
    }

    /// <summary>A height field centred on its origin: map_width samples along X and map_depth along Z, one unit apart
    /// (sample (x, z) at (x - (w-1)/2, h, z - (d-1)/2)), map_data row-major by depth (data[z * w + x]). Each quad is
    /// split along its (x+1, z)-(x, z+1) diagonal and the surface is double-sided (Jolt's build, JoltHeightMapShape3D).</summary>
    public partial class HeightMapShape3D : Shape3D
    {
        int _w = 2, _d = 2;
        float[] _data = new float[4];
        float _minH, _maxH;

        public int MapWidth
        {
            get => _w;
            set
            {
                if (value < 1 || value == _w) return;
                _w = value;
                Array.Resize(ref _data, _w * _d);       // (Godot resizes keeping the first values; new ones are 0)
                EmitChanged();
            }
        }

        public int MapDepth
        {
            get => _d;
            set
            {
                if (value < 1 || value == _d) return;
                _d = value;
                Array.Resize(ref _data, _w * _d);
                EmitChanged();
            }
        }

        /// <summary>map_data (a copy in, a copy out, as Godot's PackedFloat32Array). A size other than width * depth is
        /// ignored, as Godot does.</summary>
        public float[] MapData
        {
            get => (float[])_data.Clone();
            set => SetMapData(value);
        }

        public void SetMapData(IReadOnlyList<float> data)
        {
            int size = _w * _d;
            if (data == null || data.Count != size) return;
            for (int i = 0; i < size; i++)
            {
                float v = data[i];
                _data[i] = v;
                if (i == 0) { _minH = v; _maxH = v; }
                else
                {
                    if (_minH > v) _minH = v;
                    if (_maxH < v) _maxH = v;
                }
            }
            EmitChanged();
        }

        /// <summary>The heights without a copy (the physics backend reads them; don't write).</summary>
        public float[] MapDataRaw => _data;
        public double GetMinHeight() => _minH;
        public double GetMaxHeight() => _maxH;
        public override double GetEnclosingRadius() => new Vec3(_w, _maxH - _minH, _d).Length();
    }
}

#endif
