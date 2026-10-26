#if FB3D
// Godot's drawable 3D nodes: VisualInstance3D / GeometryInstance3D / MeshInstance3D / MultiMeshInstance3D, the
// lights, Camera3D (projection maths as camera_3d.cpp: unproject_position, project_ray_*...), WorldEnvironment,
// Sprite3D, Label3D, Decal, GPUParticles3D (emission timing and `finished` as Godot keeps them). Each marks itself in
// RenderSync when something drawn changes; the renderer reads the properties.
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public partial class Node3D
    {
        /// <summary>The renderer's own object for this node (Unity: its GameObject and components).</summary>
        public object BackendData;
        /// <summary>The world this node was registered in (set while it is in a world and drawn).</summary>
        public World3D RenderWorld { get; internal set; }

        protected void MarkRender(RenderDirty bits) { if (RenderWorld != null) RenderSync.Mark(this, bits); }

        /// <summary>Registers a drawn node in its world (VisualInstance3D, Camera3D, lights...).</summary>
        protected void RenderEnter()
        {
            RenderWorld = GetWorld3D();
            SetNotifyTransform(true);
            RenderSync.Mark(this, RenderDirty.All);
        }

        protected void RenderExit()
        {
            RenderSync.Removed(this);
            RenderWorld = null;
        }
    }

    public class VisualInstance3D : Node3D
    {
        uint _layers = 1;
        public double SortingOffset;
        public bool SortingUseAabbCenter = true;

        public uint Layers { get => _layers; set { _layers = value; MarkRender(RenderDirty.Params); } }
        public void SetLayerMaskValue(int layer, bool on)
        {
            if (on) Layers = _layers | (1u << (layer - 1));
            else Layers = _layers & ~(1u << (layer - 1));
        }
        public bool GetLayerMaskValue(int layer) => (_layers & (1u << (layer - 1))) != 0;

        protected override void OnEnterWorld() { base.OnEnterWorld(); RenderEnter(); }
        protected override void OnExitWorld() { RenderExit(); base.OnExitWorld(); }
        protected override void OnTransformChanged() { base.OnTransformChanged(); MarkRender(RenderDirty.Transform); }
        protected override void OnVisibilityChanged3D() { base.OnVisibilityChanged3D(); MarkRender(RenderDirty.Visibility); }

        public virtual Aabb GetAabb() => new Aabb();
    }

    public enum ShadowCastingSetting { Off = 0, On = 1, DoubleSided = 2, ShadowsOnly = 3 }

    public class GeometryInstance3D : VisualInstance3D
    {
        public const ShadowCastingSetting SHADOW_CASTING_SETTING_OFF = ShadowCastingSetting.Off, SHADOW_CASTING_SETTING_ON = ShadowCastingSetting.On,
            SHADOW_CASTING_SETTING_DOUBLE_SIDED = ShadowCastingSetting.DoubleSided, SHADOW_CASTING_SETTING_SHADOWS_ONLY = ShadowCastingSetting.ShadowsOnly;
        public const int GI_MODE_DISABLED = 0, GI_MODE_STATIC = 1, GI_MODE_DYNAMIC = 2;

        GMaterial _override, _overlay;
        ShadowCastingSetting _cast = ShadowCastingSetting.On;
        float _transparency;
        float _extraCull;
        Aabb _customAabb;
        readonly Dictionary<string, object> _instParams = new Dictionary<string, object>();

        public GMaterial MaterialOverride { get => _override; set { _override = value; MarkRender(RenderDirty.Material); } }
        public GMaterial MaterialOverlay { get => _overlay; set { _overlay = value; MarkRender(RenderDirty.Material); } }
        public ShadowCastingSetting CastShadow { get => _cast; set { _cast = value; MarkRender(RenderDirty.Params); } }
        public double Transparency { get => _transparency; set { _transparency = (float)GD.Clamp(value, 0, 1); MarkRender(RenderDirty.Params); } }
        public double ExtraCullMargin { get => _extraCull; set { _extraCull = (float)value; MarkRender(RenderDirty.Params); } }
        public Aabb CustomAabb { get => _customAabb; set { _customAabb = value; MarkRender(RenderDirty.Params); } }
        public double LodBias = 1.0;
        public bool IgnoreOcclusionCulling;
        public int GiMode = GI_MODE_STATIC;
        public double VisibilityRangeBegin, VisibilityRangeEnd, VisibilityRangeBeginMargin, VisibilityRangeEndMargin;

        public IReadOnlyDictionary<string, object> InstanceShaderParameters => _instParams;

        public void SetInstanceShaderParameter(string name, object value)
        {
            if (value is Var v) value = v.Obj;
            if (value == null) _instParams.Remove(name);
            else _instParams[name] = value;
            MarkRender(RenderDirty.Params);
        }

        public object GetInstanceShaderParameter(string name) => _instParams.TryGetValue(name, out var v) ? v : null;
    }

    public class MeshInstance3D : GeometryInstance3D
    {
        Mesh _mesh;
        Skin _skin;
        string _skeletonPath = "..";
        readonly List<GMaterial> _surfaceOverride = new List<GMaterial>();
        internal Skeleton3D skeletonNode;
        bool _listening;

        public Mesh Mesh
        {
            get => _mesh;
            set
            {
                if (_mesh == value) return;
                Listen(false);
                _mesh = value;
                Listen(IsInsideWorld());
                ResizeOverrides();
                UpdateSkeleton();
                MarkRender(RenderDirty.Base | RenderDirty.Material);
            }
        }

        // (the mesh's `changed` is followed only while in a world: a shared mesh doesn't keep freed instances alive)
        void Listen(bool on)
        {
            if (on == _listening || _mesh == null) { if (_mesh == null) _listening = false; return; }
            if (on) _mesh.Changed += OnMeshChanged;
            else _mesh.Changed -= OnMeshChanged;
            _listening = on;
        }

        void OnMeshChanged()
        {
            ResizeOverrides();
            MarkRender(RenderDirty.Base | RenderDirty.Material);
        }

        void ResizeOverrides()
        {
            int n = _mesh?.GetSurfaceCount() ?? 0;
            while (_surfaceOverride.Count < n) _surfaceOverride.Add(null);
            if (_surfaceOverride.Count > n) _surfaceOverride.RemoveRange(n, _surfaceOverride.Count - n);
        }

        public Skin Skin { get => _skin; set { _skin = value; UpdateSkeleton(); MarkRender(RenderDirty.Base); } }
        public string Skeleton { get => _skeletonPath; set { _skeletonPath = value; UpdateSkeleton(); MarkRender(RenderDirty.Base); } }

        /// <summary>The Skeleton3D this mesh is skinned by (null when not skinned).</summary>
        public Skeleton3D GetSkeleton() => skeletonNode;

        void UpdateSkeleton()
        {
            var old = skeletonNode;
            skeletonNode = null;
            if (IsInsideTree() && (_skin != null || (_mesh != null && _mesh.HasBones())))
                skeletonNode = GetNodeOrNull(_skeletonPath) as Skeleton3D;
            if (old != skeletonNode)
            {
                old?.UnregisterSkinned(this);
                skeletonNode?.RegisterSkinned(this);
            }
        }

        protected override void OnEnterWorld()
        {
            base.OnEnterWorld();
            Listen(true);
            UpdateSkeleton();
        }

        protected override void OnExitWorld()
        {
            Listen(false);
            skeletonNode?.UnregisterSkinned(this);
            skeletonNode = null;
            base.OnExitWorld();
        }

        internal void SkeletonPoseChanged() => MarkRender(RenderDirty.Pose);

        public int GetSurfaceOverrideMaterialCount() => _surfaceOverride.Count;

        public void SetSurfaceOverrideMaterial(int surface, GMaterial m)
        {
            ResizeOverrides();
            if (surface < 0 || surface >= _surfaceOverride.Count) { GD.PushError("Index p_surface = " + surface + " is out of bounds."); return; }
            _surfaceOverride[surface] = m;
            MarkRender(RenderDirty.Material);
        }

        public GMaterial GetSurfaceOverrideMaterial(int surface) =>
            surface >= 0 && surface < _surfaceOverride.Count ? _surfaceOverride[surface] : null;

        // ---- blend shape weights (Godot's blend_shape_properties; kept for the game code -- the renderer doesn't morph)
        readonly Dictionary<string, float> _blendShapeValues = new Dictionary<string, float>();

        public int FindBlendShapeByName(string name) => _mesh is ArrayMesh am ? am.BlendShapeNames.IndexOf(name) : -1;

        public double GetBlendShapeValue(int i)
        {
            string n = _mesh is ArrayMesh am && (uint)i < (uint)am.BlendShapeNames.Count ? am.BlendShapeNames[i] : null;
            return n != null && _blendShapeValues.TryGetValue(n, out var v) ? v : 0.0;
        }

        public void SetBlendShapeValue(int i, double value)
        {
            if (!(_mesh is ArrayMesh am) || (uint)i >= (uint)am.BlendShapeNames.Count) { GD.PushError("Index p_blend_shape = " + i + " is out of bounds."); return; }
            _blendShapeValues[am.BlendShapeNames[i]] = (float)value;
            MarkRender(RenderDirty.Base);
        }

        /// <summary>Godot's stored properties (MeshInstance3D::_set) for the baked-asset loader:
        /// "surface_material_override/N" and "blend_shapes/name".</summary>
        public override bool SetStoredProperty(string name, Var value)
        {
            if (name.StartsWith("surface_material_override/"))
            {
                int i = (int)GStr.ToInt(name.Substring(26));
                ResizeOverrides();
                if ((uint)i < (uint)_surfaceOverride.Count) SetSurfaceOverrideMaterial(i, value.Obj as GMaterial);
                else if (value.Obj != null) GD.PushError("Index p_surface = " + i + " is out of bounds.");
                return true;
            }
            if (name.StartsWith("blend_shapes/"))
            {
                _blendShapeValues[name.Substring(13)] = (float)value.AsFloat();
                return true;
            }
            return base.SetStoredProperty(name, value);
        }

        /// <summary>get_active_material(surface): the override, else the surface override, else the mesh's own.</summary>
        public GMaterial GetActiveMaterial(int surface)
        {
            if (MaterialOverride != null) return MaterialOverride;
            var s = GetSurfaceOverrideMaterial(surface);
            if (s != null) return s;
            return _mesh != null && surface >= 0 && surface < _mesh.GetSurfaceCount() ? _mesh.SurfaceGetMaterial(surface) : null;
        }

        public override Aabb GetAabb() => _mesh?.GetAabb() ?? new Aabb();
    }

    public class MultiMeshInstance3D : GeometryInstance3D
    {
        MultiMesh _mm;
        bool _listening;
        public MultiMesh Multimesh
        {
            get => _mm;
            set
            {
                Listen(false);
                _mm = value;
                Listen(IsInsideWorld());
                MarkRender(RenderDirty.Base | RenderDirty.Pose);
            }
        }

        void Listen(bool on)
        {
            if (_mm == null) { _listening = false; return; }
            if (on == _listening) return;
            if (on) _mm.Changed += OnChanged; else _mm.Changed -= OnChanged;
            _listening = on;
        }

        protected override void OnEnterWorld() { base.OnEnterWorld(); Listen(true); }
        protected override void OnExitWorld() { Listen(false); base.OnExitWorld(); }
        void OnChanged() => MarkRender(RenderDirty.Pose);
        public override Aabb GetAabb() => _mm?.GetAabb() ?? new Aabb();
    }

    // ------------------------------------------------------------------ sprites and labels
    public enum BillboardMode { Disabled = 0, Enabled = 1, FixedY = 2, Particles = 3 }

    public class SpriteBase3D : GeometryInstance3D
    {
        public const BillboardMode BILLBOARD_DISABLED = BillboardMode.Disabled, BILLBOARD_ENABLED = BillboardMode.Enabled, BILLBOARD_FIXED_Y = BillboardMode.FixedY;
        public const int ALPHA_CUT_DISABLED = 0, ALPHA_CUT_DISCARD = 1, ALPHA_CUT_OPAQUE_PREPASS = 2, ALPHA_CUT_HASH = 3;
        Col _modulate = Col.WHITE;
        double _pixelSize = 0.01;
        BillboardMode _billboard;
        bool _centered = true, _flipH, _flipV, _shaded, _doubleSided = true, _transparent = true, _noDepthTest, _fixedSize;
        Vec2 _offset;
        int _alphaCut;
        int _textureFilter = 3;
        public int RenderPriority;

        void M() => MarkRender(RenderDirty.Base);
        public Col Modulate { get => _modulate; set { _modulate = value; M(); } }
        public double PixelSize { get => _pixelSize; set { _pixelSize = value; M(); } }
        public BillboardMode Billboard { get => _billboard; set { _billboard = value; M(); } }
        public bool Centered { get => _centered; set { _centered = value; M(); } }
        public Vec2 Offset { get => _offset; set { _offset = value; M(); } }
        public bool FlipH { get => _flipH; set { _flipH = value; M(); } }
        public bool FlipV { get => _flipV; set { _flipV = value; M(); } }
        public bool Shaded { get => _shaded; set { _shaded = value; M(); } }
        public bool DoubleSided { get => _doubleSided; set { _doubleSided = value; M(); } }
        public bool Transparent { get => _transparent; set { _transparent = value; M(); } }
        public bool NoDepthTest { get => _noDepthTest; set { _noDepthTest = value; M(); } }
        public bool FixedSize { get => _fixedSize; set { _fixedSize = value; M(); } }
        public int AlphaCut { get => _alphaCut; set { _alphaCut = value; M(); } }
        public int TextureFilter { get => _textureFilter; set { _textureFilter = value; M(); } }
    }

    public class Sprite3D : SpriteBase3D
    {
        Texture2D _tex;
        int _hframes = 1, _vframes = 1, _frame;
        bool _regionEnabled;
        Rect2 _region;
        public Texture2D Texture { get => _tex; set { _tex = value; MarkRender(RenderDirty.Base); } }
        public int Hframes { get => _hframes; set { _hframes = Math.Max(1, value); MarkRender(RenderDirty.Base); } }
        public int Vframes { get => _vframes; set { _vframes = Math.Max(1, value); MarkRender(RenderDirty.Base); } }
        public int Frame { get => _frame; set { _frame = value; MarkRender(RenderDirty.Base); } }
        public bool RegionEnabled { get => _regionEnabled; set { _regionEnabled = value; MarkRender(RenderDirty.Base); } }
        public Rect2 RegionRect { get => _region; set { _region = value; MarkRender(RenderDirty.Base); } }
    }

    public class Label3D : GeometryInstance3D
    {
        string _text = "";
        int _fontSize = 32, _outlineSize = 12;
        Col _modulate = Col.WHITE, _outlineModulate = Col.BLACK;
        double _pixelSize = 0.005;
        BillboardMode _billboard;
        bool _noDepthTest, _fixedSize, _shaded, _doubleSided = true;
        Font _font;
        HorizontalAlignment _halign = HorizontalAlignment.Center;
        VerticalAlignment _valign = VerticalAlignment.Center;
        Vec2 _offset;
        public double Width = 500.0, LineSpacing;
        public int RenderPriority, OutlineRenderPriority = -1;
        public bool Uppercase;

        void M() => MarkRender(RenderDirty.Base);
        public string Text { get => _text; set { _text = value ?? ""; M(); } }
        public int FontSize { get => _fontSize; set { _fontSize = value; M(); } }
        public int OutlineSize { get => _outlineSize; set { _outlineSize = value; M(); } }
        public Col Modulate { get => _modulate; set { _modulate = value; M(); } }
        public Col OutlineModulate { get => _outlineModulate; set { _outlineModulate = value; M(); } }
        public double PixelSize { get => _pixelSize; set { _pixelSize = value; M(); } }
        public BillboardMode Billboard { get => _billboard; set { _billboard = value; M(); } }
        public bool NoDepthTest { get => _noDepthTest; set { _noDepthTest = value; M(); } }
        public bool FixedSize { get => _fixedSize; set { _fixedSize = value; M(); } }
        public bool Shaded { get => _shaded; set { _shaded = value; M(); } }
        public bool DoubleSided { get => _doubleSided; set { _doubleSided = value; M(); } }
        public Font Font { get => _font; set { _font = value; M(); } }
        public HorizontalAlignment HorizontalAlignment { get => _halign; set { _halign = value; M(); } }
        public VerticalAlignment VerticalAlignment { get => _valign; set { _valign = value; M(); } }
        public Vec2 Offset { get => _offset; set { _offset = value; M(); } }
    }

    public class Decal : VisualInstance3D
    {
        Vec3 _size = new Vec3(2f, 2f, 2f);
        Texture2D _albedo, _normal, _orm, _emission;
        Col _modulate = Col.WHITE;
        double _albedoMix = 1.0, _upperFade = 0.3, _lowerFade = 0.3, _emissionEnergy = 1.0, _normalFade;
        uint _cullMask = 0xFFFFF;
        void M() => MarkRender(RenderDirty.Base);
        public Vec3 Size { get => _size; set { _size = value; M(); } }
        public Texture2D TextureAlbedo { get => _albedo; set { _albedo = value; M(); } }
        public Texture2D TextureNormal { get => _normal; set { _normal = value; M(); } }
        public Texture2D TextureOrm { get => _orm; set { _orm = value; M(); } }
        public Texture2D TextureEmission { get => _emission; set { _emission = value; M(); } }
        public Col Modulate { get => _modulate; set { _modulate = value; M(); } }
        public double AlbedoMix { get => _albedoMix; set { _albedoMix = value; M(); } }
        public double UpperFade { get => _upperFade; set { _upperFade = value; M(); } }
        public double LowerFade { get => _lowerFade; set { _lowerFade = value; M(); } }
        public double NormalFade { get => _normalFade; set { _normalFade = value; M(); } }
        public double EmissionEnergy { get => _emissionEnergy; set { _emissionEnergy = value; M(); } }
        public uint CullMask { get => _cullMask; set { _cullMask = value; M(); } }
    }

    // ------------------------------------------------------------------ lights
    public class Light3D : VisualInstance3D
    {
        public const int BAKE_DISABLED = 0, BAKE_STATIC = 1, BAKE_DYNAMIC = 2;
        Col _color = Col.WHITE;
        double _energy = 1.0, _indirect = 1.0, _specular = 0.5, _shadowBias = 0.1, _shadowNormalBias = 1.0,
            _shadowOpacity = 1.0, _shadowBlur = 1.0, _angularDistance;
        bool _shadow, _negative;
        uint _cullMask = 0xFFFFFFFF;
        void M() => MarkRender(RenderDirty.Base);
        public Col LightColor { get => _color; set { _color = value; M(); } }
        public double LightEnergy { get => _energy; set { _energy = value; M(); } }
        public double LightIndirectEnergy { get => _indirect; set { _indirect = value; M(); } }
        public double LightSpecular { get => _specular; set { _specular = value; M(); } }
        public bool LightNegative { get => _negative; set { _negative = value; M(); } }
        public uint LightCullMask { get => _cullMask; set { _cullMask = value; M(); } }
        public bool ShadowEnabled { get => _shadow; set { _shadow = value; M(); } }
        public double ShadowBias { get => _shadowBias; set { _shadowBias = value; M(); } }
        public double ShadowNormalBias { get => _shadowNormalBias; set { _shadowNormalBias = value; M(); } }
        public double ShadowOpacity { get => _shadowOpacity; set { _shadowOpacity = value; M(); } }
        public double ShadowBlur { get => _shadowBlur; set { _shadowBlur = value; M(); } }
        public double LightAngularDistance { get => _angularDistance; set { _angularDistance = value; M(); } }
        public int LightBakeMode = BAKE_DYNAMIC;
        public bool DistanceFadeEnabled;
        public double DistanceFadeBegin = 40, DistanceFadeShadow = 50, DistanceFadeLength = 10;
    }

    public class DirectionalLight3D : Light3D
    {
        public const int SHADOW_ORTHOGONAL = 0, SHADOW_PARALLEL_2_SPLITS = 1, SHADOW_PARALLEL_4_SPLITS = 2;
        public const int SKY_MODE_LIGHT_AND_SKY = 0, SKY_MODE_LIGHT_ONLY = 1, SKY_MODE_SKY_ONLY = 2;
        int _mode = SHADOW_PARALLEL_4_SPLITS, _skyMode;
        double _maxDistance = 100.0, _split1 = 0.1, _split2 = 0.2, _split3 = 0.5, _fadeStart = 0.8;
        bool _blendSplits;
        public DirectionalLight3D() { ShadowNormalBias = 2.0; }
        void M() => MarkRender(RenderDirty.Base);
        public int DirectionalShadowMode { get => _mode; set { _mode = value; M(); } }
        public double DirectionalShadowMaxDistance { get => _maxDistance; set { _maxDistance = value; M(); } }
        public double DirectionalShadowSplit1 { get => _split1; set { _split1 = value; M(); } }
        public double DirectionalShadowSplit2 { get => _split2; set { _split2 = value; M(); } }
        public double DirectionalShadowSplit3 { get => _split3; set { _split3 = value; M(); } }
        public double DirectionalShadowFadeStart { get => _fadeStart; set { _fadeStart = value; M(); } }
        public bool DirectionalShadowBlendSplits { get => _blendSplits; set { _blendSplits = value; M(); } }
        public int SkyMode { get => _skyMode; set { _skyMode = value; M(); } }
    }

    public class OmniLight3D : Light3D
    {
        public const int SHADOW_DUAL_PARABOLOID = 0, SHADOW_CUBE = 1;
        double _range = 5.0, _attenuation = 1.0;
        int _shadowMode = SHADOW_CUBE;
        void M() => MarkRender(RenderDirty.Base);
        public double OmniRange { get => _range; set { _range = value; M(); } }
        public double OmniAttenuation { get => _attenuation; set { _attenuation = value; M(); } }
        public int OmniShadowMode { get => _shadowMode; set { _shadowMode = value; M(); } }
    }

    public class SpotLight3D : Light3D
    {
        double _range = 5.0, _attenuation = 1.0, _angle = 45.0, _angleAttenuation = 1.0;
        void M() => MarkRender(RenderDirty.Base);
        public double SpotRange { get => _range; set { _range = value; M(); } }
        public double SpotAttenuation { get => _attenuation; set { _attenuation = value; M(); } }
        public double SpotAngle { get => _angle; set { _angle = value; M(); } }
        public double SpotAngleAttenuation { get => _angleAttenuation; set { _angleAttenuation = value; M(); } }
    }

    // ------------------------------------------------------------------ camera
    public class Camera3D : Node3D
    {
        public enum ProjectionType { Perspective = 0, Orthogonal = 1, Frustum = 2 }
        public enum KeepAspectEnum { KeepWidth = 0, KeepHeight = 1 }
        public const ProjectionType PROJECTION_PERSPECTIVE = ProjectionType.Perspective, PROJECTION_ORTHOGONAL = ProjectionType.Orthogonal,
            PROJECTION_FRUSTUM = ProjectionType.Frustum;
        public const KeepAspectEnum KEEP_WIDTH = KeepAspectEnum.KeepWidth, KEEP_HEIGHT = KeepAspectEnum.KeepHeight;

        ProjectionType _mode = ProjectionType.Perspective;
        KeepAspectEnum _keep = KeepAspectEnum.KeepHeight;
        float _fov = 75f, _size = 1f, _near = 0.05f, _far = 4000f, _hOffset, _vOffset;
        Vec2 _frustumOffset;
        uint _cullMask = 0xFFFFF;
        bool _current;
        Environment _env;
        Viewport _vp;
        public double DopplerTracking;

        void M() => MarkRender(RenderDirty.Base);
        public ProjectionType Projection { get => _mode; set { _mode = value; M(); } }
        public KeepAspectEnum KeepAspect { get => _keep; set { _keep = value; M(); } }
        public double Fov { get => _fov; set { _fov = (float)value; M(); } }
        public double Size { get => _size; set { _size = (float)value; M(); } }
        public double Near { get => _near; set { _near = (float)value; M(); } }
        public double Far { get => _far; set { _far = (float)value; M(); } }
        public double HOffset { get => _hOffset; set { _hOffset = (float)value; M(); } }
        public double VOffset { get => _vOffset; set { _vOffset = (float)value; M(); } }
        public Vec2 FrustumOffset { get => _frustumOffset; set { _frustumOffset = value; M(); } }
        public uint CullMask { get => _cullMask; set { _cullMask = value; M(); } }
        public Environment Environment { get => _env; set { _env = value; M(); } }

        public void SetPerspective(double fovy, double near, double far) { _fov = (float)fovy; _near = (float)near; _far = (float)far; _mode = ProjectionType.Perspective; M(); }
        public void SetOrthogonal(double size, double near, double far) { _size = (float)size; _near = (float)near; _far = (float)far; _mode = ProjectionType.Orthogonal; M(); }
        public void SetFrustum(double size, Vec2 offset, double near, double far) { _size = (float)size; _frustumOffset = offset; _near = (float)near; _far = (float)far; _mode = ProjectionType.Frustum; M(); }

        protected override void OnEnterWorld()
        {
            base.OnEnterWorld();
            _vp = GetViewport();
            RenderEnter();
            if (_vp != null)
            {
                bool first = _vp.Camera3DAdd(this);
                if (_current || first) _vp.Camera3DSet(this);
            }
        }

        protected override void OnExitWorld()
        {
            if (IsCurrent())
            {
                ClearCurrent();
                _current = true;
            }
            else _current = false;
            _vp?.Camera3DRemove(this);
            _vp = null;
            RenderExit();
            base.OnExitWorld();
        }

        protected override void OnTransformChanged() { base.OnTransformChanged(); MarkRender(RenderDirty.Transform); }

        public bool Current
        {
            get => IsCurrent();
            set { if (value) MakeCurrent(); else ClearCurrent(); }
        }

        public void MakeCurrent()
        {
            _current = true;
            if (!IsInsideTree()) return;
            GetViewport()?.Camera3DSet(this);
        }

        public void ClearCurrent(bool enableNext = true)
        {
            _current = false;
            if (!IsInsideTree()) return;
            var vp = GetViewport();
            if (vp != null && vp.GetCamera3D() == this)
            {
                vp.Camera3DSet(null);
                if (enableNext) vp.Camera3DMakeNextCurrent(this);
            }
        }

        public bool IsCurrent() => IsInsideTree() ? GetViewport()?.GetCamera3D() == this : _current;

        internal void BecameCurrent(bool on) => MarkRender(RenderDirty.Base);

        Xform3 AdjustedCameraTransform(Xform3 x)
        {
            Xform3 tr = x.Orthonormalized();
            tr.origin = tr.origin + tr.basis.GetColumn(1) * _vOffset;
            tr.origin = tr.origin + tr.basis.GetColumn(0) * _hOffset;
            return tr;
        }

        public Xform3 GetCameraTransform() => AdjustedCameraTransform(GlobalTransform);

        Vec2 ViewportSize() => GetViewport()?.Get3DSize() ?? new Vec2(1f, 1f);

        Fatebound.Sim.Projection CameraProjection(float near)
        {
            Vec2 vs = ViewportSize();
            float aspect = vs.y != 0 ? vs.x / vs.y : 1f;
            var cm = new Fatebound.Sim.Projection();
            switch (_mode)
            {
                case ProjectionType.Perspective: cm.SetPerspective(_fov, aspect, near, _far, _keep == KeepAspectEnum.KeepWidth); break;
                case ProjectionType.Orthogonal: cm.SetOrthogonalAspect(_size, aspect, near, _far, _keep == KeepAspectEnum.KeepWidth); break;
                case ProjectionType.Frustum: cm.SetFrustumAspect(_size, aspect, _frustumOffset, near, _far); break;
            }
            return cm;
        }

        public Fatebound.Sim.Projection GetCameraProjection() => CameraProjection(_near);

        public Vec3 ProjectRayNormal(Vec2 pos) => GetCameraTransform().basis.Xform(ProjectLocalRayNormal(pos)).Normalized();

        public Vec3 ProjectLocalRayNormal(Vec2 pos)
        {
            Vec2 vs = ViewportSize();
            Vec2 cpos = GetViewport()?.GetCameraCoords(pos) ?? pos;
            if (_mode == ProjectionType.Orthogonal) return new Vec3(0f, 0f, -1f);
            Fatebound.Sim.Projection cm = CameraProjection(_near);
            Vec2 he = cm.GetViewportHalfExtents();
            return new Vec3(((cpos.x / vs.x) * 2.0f - 1.0f) * he.x, ((1.0f - (cpos.y / vs.y)) * 2.0f - 1.0f) * he.y, -_near).Normalized();
        }

        public Vec3 ProjectRayOrigin(Vec2 pos)
        {
            Vec2 vs = ViewportSize();
            Vec2 cpos = GetViewport()?.GetCameraCoords(pos) ?? pos;
            if (vs.y == 0) return Vec3.Zero;
            if (_mode == ProjectionType.Orthogonal)
            {
                Vec2 p = cpos / vs;
                float aspect = vs.x / vs.y;
                float vsize, hsize;
                if (_keep == KeepAspectEnum.KeepWidth) { vsize = _size / aspect; hsize = _size; }
                else { hsize = _size * aspect; vsize = _size; }
                var ray = new Vec3(p.x * hsize - hsize / 2, (1.0f - p.y) * vsize - vsize / 2, -_near);
                return GetCameraTransform().Xform(ray);
            }
            return GetCameraTransform().origin;
        }

        public bool IsPositionBehind(Vec3 pos)
        {
            Xform3 t = GlobalTransform;
            Vec3 eyedir = -t.basis.GetColumn(2).Normalized();
            return eyedir.Dot(pos - t.origin) < _near;
        }

        public Vec2 UnprojectPosition(Vec3 pos)
        {
            Vec2 vs = ViewportSize();
            Fatebound.Sim.Projection cm = CameraProjection(_near);
            var p = new Plane(GetCameraTransform().XformInv(pos), 1.0f);
            p = cm.Xform4(p);
            if (p.d == 0) { GD.PushError("unproject_position: divide by zero"); return Vec2.Zero; }
            Vec3 n = p.normal / p.d;
            return new Vec2((n.x * 0.5f + 0.5f) * vs.x, (-n.y * 0.5f + 0.5f) * vs.y);
        }

        public Vec3 ProjectPosition(Vec2 point, double zDepth)
        {
            if (zDepth == 0 && _mode != ProjectionType.Orthogonal) return GlobalTransform.origin;
            Vec2 vs = ViewportSize();
            Fatebound.Sim.Projection cm = CameraProjection(_near);
            var zSlice = new Plane(new Vec3(0f, 0f, 1f), (float)-zDepth);
            zSlice.Intersect3(cm.GetProjectionPlane(Fatebound.Sim.Projection.PLANE_RIGHT), cm.GetProjectionPlane(Fatebound.Sim.Projection.PLANE_TOP), out Vec3 res);
            var he = new Vec2(res.x, res.y);
            var pt = new Vec2((point.x / vs.x) * 2.0f - 1.0f, (1.0f - (point.y / vs.y)) * 2.0f - 1.0f) * he;
            return GetCameraTransform().Xform(new Vec3(pt.x, pt.y, (float)-zDepth));
        }

        public Plane[] GetFrustum() => CameraProjection(_near).GetProjectionPlanes(GetCameraTransform());

        public bool IsPositionInFrustum(Vec3 pos)
        {
            foreach (var p in GetFrustum()) if (p.IsPointOver(pos)) return false;
            return true;
        }
    }

    public class WorldEnvironment : Node
    {
        Environment _env;
        World3D _world;
        public Environment Environment
        {
            get => _env;
            set
            {
                _env = value;
                if (_world != null) _world.Environment = value;
            }
        }
        public Resource CameraAttributes;

        protected override void OnEnterTree()
        {
            base.OnEnterTree();
            _world = GetViewport()?.FindWorld3D();
            if (_world != null)
            {
                _world.worldEnvironments.Add(this);
                if (_env != null) _world.Environment = _env;
            }
        }

        protected override void OnExitTree()
        {
            if (_world != null)
            {
                _world.worldEnvironments.Remove(this);
                if (_world.Environment == _env) _world.Environment = null;
            }
            _world = null;
            base.OnExitTree();
        }
    }

    // ------------------------------------------------------------------ particles
    public class GPUParticles3D : GeometryInstance3D
    {
        public const int DRAW_ORDER_INDEX = 0, DRAW_ORDER_LIFETIME = 1, DRAW_ORDER_REVERSE_LIFETIME = 2, DRAW_ORDER_VIEW_DEPTH = 3;
        public const int TRANSFORM_ALIGN_DISABLED = 0, TRANSFORM_ALIGN_Z_BILLBOARD = 1, TRANSFORM_ALIGN_Y_TO_VELOCITY = 2, TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY = 3;

        bool _emitting = true, _oneShot, _localCoords, _interpolate = true, _fractDelta = true;
        int _amount = 8, _fixedFps = 30, _drawOrder;
        double _lifetime = 1.0, _preprocess, _speedScale = 1.0, _explosiveness, _randomness, _amountRatio = 1.0;
        Aabb _visibilityAabb = new Aabb(new Vec3(-4f, -4f, -4f), new Vec3(8f, 8f, 8f));
        GMaterial _process;
        readonly Mesh[] _passes = new Mesh[4];
        int _passCount = 1;
        bool _active, _signalCanceled;
        double _time, _emissionTime, _activeTime;
        public int Seed;
        public bool UseFixedSeed;
        /// <summary>Bumped on restart(): the renderer restarts the system when it sees a new value.</summary>
        public int RestartCounter { get; private set; }
        public int TransformAlign;
        public bool TrailEnabled;
        public double TrailLifetime = 0.3;
        public string SubEmitter = "";
        public double CollisionBaseSize = 0.01;
        /// <summary>transform_align_axis (Godot's default 1 = Y; used by TRANSFORM_ALIGN_Y_TO_VELOCITY).</summary>
        public int TransformAlignAxis = 1;
        /// <summary>The last emitting value handed to the rendering side (Godot's particles_set_emitting: every
        /// set_emitting and restart) and a count of those calls -- ParticlesSim follows them, not the node's own
        /// one-shot bookkeeping in `Emitting`.</summary>
        public bool EmittingRequest { get; private set; } = true;
        public int EmittingRequestCounter { get; private set; }
        double _interpToEnd;
        /// <summary>interp_to_end (0..1): pushes every particle towards the end of its life.</summary>
        public double InterpToEnd { get => _interpToEnd; set { _interpToEnd = value < 0 ? 0 : (value > 1 ? 1 : value); M(); } }

        public event Action Finished;

        void M() => MarkRender(RenderDirty.Base);

        public bool Emitting
        {
            get => _emitting;
            set
            {
                if (value && value != _emitting && !UseFixedSeed && _oneShot) Seed = (int)GD.GlobalRng.Next();
                if (value && _oneShot)
                {
                    if (!_active && !_emitting)
                    {
                        _active = true;
                        _time = 0;
                        _signalCanceled = false;
                        _emissionTime = _lifetime;
                        _activeTime = _lifetime * (2 - _explosiveness);
                    }
                    else _signalCanceled = true;
                    SetProcessInternal(true);
                }
                else if (!value) SetProcessInternal(_oneShot);
                else SetProcessInternal(true);
                _emitting = value;
                EmittingRequest = value;
                EmittingRequestCounter++;
                M();
            }
        }

        public int Amount { get => _amount; set { _amount = Math.Max(1, value); M(); } }
        public double Lifetime { get => _lifetime; set { if (value > 0) _lifetime = value; M(); } }
        public bool OneShot
        {
            get => _oneShot;
            set
            {
                _oneShot = value;
                if (_emitting && !_oneShot) RestartCounter++;
                M();
            }
        }
        public double Preprocess { get => _preprocess; set { _preprocess = value; M(); } }
        public double SpeedScale { get => _speedScale; set { _speedScale = value; M(); } }
        public double Explosiveness { get => _explosiveness; set { _explosiveness = value; M(); } }
        public double Randomness { get => _randomness; set { _randomness = value; M(); } }
        public double AmountRatio { get => _amountRatio; set { _amountRatio = value; M(); } }
        public int FixedFps { get => _fixedFps; set { _fixedFps = value; M(); } }
        public bool Interpolate { get => _interpolate; set { _interpolate = value; M(); } }
        public bool FractDelta { get => _fractDelta; set { _fractDelta = value; M(); } }
        public bool LocalCoords { get => _localCoords; set { _localCoords = value; M(); } }
        public int DrawOrder { get => _drawOrder; set { _drawOrder = value; M(); } }
        public Aabb VisibilityAabb { get => _visibilityAabb; set { _visibilityAabb = value; M(); } }
        public GMaterial ProcessMaterial { get => _process; set { _process = value; M(); } }
        public int DrawPasses { get => _passCount; set { _passCount = Math.Max(1, Math.Min(4, value)); M(); } }
        public Mesh DrawPass1 { get => _passes[0]; set { _passes[0] = value; M(); } }
        public Mesh DrawPass2 { get => _passes[1]; set { _passes[1] = value; M(); } }
        public Mesh DrawPass3 { get => _passes[2]; set { _passes[2] = value; M(); } }
        public Mesh DrawPass4 { get => _passes[3]; set { _passes[3] = value; M(); } }
        public Mesh GetDrawPassMesh(int i) => _passes[i];
        public void SetDrawPassMesh(int i, Mesh m) { _passes[i] = m; M(); }

        public void Restart(bool keepSeed = false)
        {
            if (!keepSeed && !UseFixedSeed) Seed = (int)GD.GlobalRng.Next();
            RestartCounter++;
            _emitting = true;
            EmittingRequest = true;
            EmittingRequestCounter++;
            _active = true;
            _signalCanceled = false;
            _time = 0;
            _emissionTime = _lifetime * (1 - _explosiveness);
            _activeTime = _lifetime * (2 - _explosiveness);
            SetProcessInternal(true);
            MarkRender(RenderDirty.Base | RenderDirty.Pose);
        }

        protected override void InternalProcess(double delta)
        {
            if (!_oneShot) return;
            _time += delta;
            if (_time > _emissionTime)
            {
                if (_emitting) { _emitting = false; M(); }
                if (!_active) SetProcessInternal(false);
            }
            if (_time > _activeTime)
            {
                if (_active && !_signalCanceled) Finished?.Invoke();
                _active = false;
                if (!_emitting) SetProcessInternal(false);
            }
        }

        protected override void OnEnterWorld()
        {
            base.OnEnterWorld();
            if (_oneShot && _emitting && !_active)
            {
                _active = true;
                _time = 0;
                _emissionTime = _lifetime;
                _activeTime = _lifetime * (2 - _explosiveness);
            }
            SetProcessInternal(_emitting || _active);
        }

        public override Aabb GetAabb() => _visibilityAabb;
        public Aabb CaptureAabb() => _visibilityAabb;
    }
}

#endif
