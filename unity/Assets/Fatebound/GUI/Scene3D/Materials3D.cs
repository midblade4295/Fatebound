#if FB3D
// Godot's BaseMaterial3D / StandardMaterial3D / ORMMaterial3D (scene/resources/material.cpp) as a property bag the
// renderer reads: every property Godot has, its default (the constructor's set_* calls), its storage type (float
// fields stay 32-bit as in Godot), the flag/feature/texture arrays behind set_flag/set_feature/set_texture, the
// constants (BaseMaterial3D.TRANSPARENCY_ALPHA...), the stencil Outline/X-Ray next pass Godot builds, and the 3.x
// property remaps StandardMaterial3D accepts when loading. Every change calls EmitChanged() (bumps `version`).
// Properties use Godot's property names PascalCased (albedo_color -> AlbedoColor, grow_amount -> GrowAmount).
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public class BaseMaterial3D : GMaterial
    {
        // ---------------------------------------------------------------- constants
        public const int TEXTURE_ALBEDO = 0, TEXTURE_METALLIC = 1, TEXTURE_ROUGHNESS = 2, TEXTURE_EMISSION = 3, TEXTURE_NORMAL = 4,
            TEXTURE_RIM = 5, TEXTURE_CLEARCOAT = 6, TEXTURE_FLOWMAP = 7, TEXTURE_AMBIENT_OCCLUSION = 8, TEXTURE_HEIGHTMAP = 9,
            TEXTURE_SUBSURFACE_SCATTERING = 10, TEXTURE_SUBSURFACE_TRANSMITTANCE = 11, TEXTURE_BACKLIGHT = 12, TEXTURE_REFRACTION = 13,
            TEXTURE_DETAIL_MASK = 14, TEXTURE_DETAIL_ALBEDO = 15, TEXTURE_DETAIL_NORMAL = 16, TEXTURE_ORM = 17, TEXTURE_BENT_NORMAL = 18,
            TEXTURE_MAX = 19;
        public const int TEXTURE_FILTER_NEAREST = 0, TEXTURE_FILTER_LINEAR = 1, TEXTURE_FILTER_NEAREST_WITH_MIPMAPS = 2,
            TEXTURE_FILTER_LINEAR_WITH_MIPMAPS = 3, TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC = 4,
            TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC = 5, TEXTURE_FILTER_MAX = 6;
        public const int DETAIL_UV_1 = 0, DETAIL_UV_2 = 1;
        public const int TRANSPARENCY_DISABLED = 0, TRANSPARENCY_ALPHA = 1, TRANSPARENCY_ALPHA_SCISSOR = 2, TRANSPARENCY_ALPHA_HASH = 3,
            TRANSPARENCY_ALPHA_DEPTH_PRE_PASS = 4, TRANSPARENCY_MAX = 5;
        public const int ALPHA_ANTIALIASING_OFF = 0, ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE = 1, ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE_AND_TO_ONE = 2;
        public const int SHADING_MODE_UNSHADED = 0, SHADING_MODE_PER_PIXEL = 1, SHADING_MODE_PER_VERTEX = 2, SHADING_MODE_MAX = 3;
        public const int FEATURE_EMISSION = 0, FEATURE_NORMAL_MAPPING = 1, FEATURE_RIM = 2, FEATURE_CLEARCOAT = 3, FEATURE_ANISOTROPY = 4,
            FEATURE_AMBIENT_OCCLUSION = 5, FEATURE_HEIGHT_MAPPING = 6, FEATURE_SUBSURFACE_SCATTERING = 7, FEATURE_SUBSURFACE_TRANSMITTANCE = 8,
            FEATURE_BACKLIGHT = 9, FEATURE_REFRACTION = 10, FEATURE_DETAIL = 11, FEATURE_BENT_NORMAL_MAPPING = 12, FEATURE_MAX = 13;
        public const int BLEND_MODE_MIX = 0, BLEND_MODE_ADD = 1, BLEND_MODE_SUB = 2, BLEND_MODE_MUL = 3, BLEND_MODE_PREMULT_ALPHA = 4;
        public const int DEPTH_DRAW_OPAQUE_ONLY = 0, DEPTH_DRAW_ALWAYS = 1, DEPTH_DRAW_DISABLED = 2;
        public const int DEPTH_TEST_DEFAULT = 0, DEPTH_TEST_INVERTED = 1;
        public const int CULL_BACK = 0, CULL_FRONT = 1, CULL_DISABLED = 2;
        public const int FLAG_DISABLE_DEPTH_TEST = 0, FLAG_ALBEDO_FROM_VERTEX_COLOR = 1, FLAG_SRGB_VERTEX_COLOR = 2, FLAG_USE_POINT_SIZE = 3,
            FLAG_FIXED_SIZE = 4, FLAG_BILLBOARD_KEEP_SCALE = 5, FLAG_UV1_USE_TRIPLANAR = 6, FLAG_UV2_USE_TRIPLANAR = 7,
            FLAG_UV1_USE_WORLD_TRIPLANAR = 8, FLAG_UV2_USE_WORLD_TRIPLANAR = 9, FLAG_AO_ON_UV2 = 10, FLAG_EMISSION_ON_UV2 = 11,
            FLAG_ALBEDO_TEXTURE_FORCE_SRGB = 12, FLAG_DONT_RECEIVE_SHADOWS = 13, FLAG_DISABLE_AMBIENT_LIGHT = 14,
            FLAG_USE_SHADOW_TO_OPACITY = 15, FLAG_USE_TEXTURE_REPEAT = 16, FLAG_INVERT_HEIGHTMAP = 17, FLAG_SUBSURFACE_MODE_SKIN = 18,
            FLAG_PARTICLE_TRAILS_MODE = 19, FLAG_ALBEDO_TEXTURE_MSDF = 20, FLAG_DISABLE_FOG = 21, FLAG_DISABLE_SPECULAR_OCCLUSION = 22,
            FLAG_USE_Z_CLIP_SCALE = 23, FLAG_USE_FOV_OVERRIDE = 24, FLAG_MAX = 25;
        public const int DIFFUSE_BURLEY = 0, DIFFUSE_LAMBERT = 1, DIFFUSE_LAMBERT_WRAP = 2, DIFFUSE_TOON = 3;
        public const int SPECULAR_SCHLICK_GGX = 0, SPECULAR_TOON = 1, SPECULAR_DISABLED = 2;
        public const int BILLBOARD_DISABLED = 0, BILLBOARD_ENABLED = 1, BILLBOARD_FIXED_Y = 2, BILLBOARD_PARTICLES = 3;
        public const int TEXTURE_CHANNEL_RED = 0, TEXTURE_CHANNEL_GREEN = 1, TEXTURE_CHANNEL_BLUE = 2, TEXTURE_CHANNEL_ALPHA = 3, TEXTURE_CHANNEL_GRAYSCALE = 4;
        public const int EMISSION_OP_ADD = 0, EMISSION_OP_MULTIPLY = 1;
        public const int DISTANCE_FADE_DISABLED = 0, DISTANCE_FADE_PIXEL_ALPHA = 1, DISTANCE_FADE_PIXEL_DITHER = 2, DISTANCE_FADE_OBJECT_DITHER = 3;
        public const int STENCIL_MODE_DISABLED = 0, STENCIL_MODE_OUTLINE = 1, STENCIL_MODE_XRAY = 2, STENCIL_MODE_CUSTOM = 3;
        public const int STENCIL_FLAG_READ = 1, STENCIL_FLAG_WRITE = 2, STENCIL_FLAG_WRITE_DEPTH_FAIL = 4;
        public const int STENCIL_COMPARE_ALWAYS = 0, STENCIL_COMPARE_LESS = 1, STENCIL_COMPARE_EQUAL = 2, STENCIL_COMPARE_LESS_OR_EQUAL = 3,
            STENCIL_COMPARE_GREATER = 4, STENCIL_COMPARE_NOT_EQUAL = 5, STENCIL_COMPARE_GREATER_OR_EQUAL = 6;

        /// <summary>Project setting rendering/lights_and_shadows/use_physical_light_units (Godot's default false).</summary>
        public static bool UsePhysicalLightUnits = false;

        // ---------------------------------------------------------------- state (one object, so duplicate() is a copy)
        sealed class State
        {
            public bool orm;
            public Col albedo, emission, transmittanceColor, backlight, stencilEffectColor = new Col(0f, 0f, 0f, 1f);
            public float specular, metallic, roughness, emissionEnergyMultiplier = 1.0f, emissionIntensity = 1000.0f, normalScale, rim, rimTint,
                clearcoat, clearcoatRoughness, anisotropy, heightmapScale, subsurfaceScatteringStrength, transmittanceDepth, transmittanceBoost,
                refraction, pointSize, alphaScissorThreshold, alphaHashScale, alphaAntialiasingEdge, aoLightAffect, grow,
                uv1TriplanarSharpness, uv2TriplanarSharpness, proximityFadeDistance, msdfPixelRange = 4f, msdfOutlineSize,
                distanceFadeMaxDistance, distanceFadeMinDistance, zClipScale = 1.0f, fovOverride = 75.0f, stencilEffectOutlineThickness = 0.01f;
            public bool growEnabled, particlesAnimLoop, deepParallax, heightmapFlipTangent, heightmapFlipBinormal, proximityFadeEnabled;
            public int particlesAnimHFrames, particlesAnimVFrames, deepParallaxMinLayers, deepParallaxMaxLayers;
            public int transparency = TRANSPARENCY_DISABLED, shadingMode = SHADING_MODE_PER_PIXEL, textureFilter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,
                detailUv = DETAIL_UV_1, distanceFade = DISTANCE_FADE_DISABLED, blendMode = BLEND_MODE_MIX, detailBlendMode = BLEND_MODE_MIX,
                depthDrawMode = DEPTH_DRAW_OPAQUE_ONLY, depthTest = DEPTH_TEST_DEFAULT, cullMode = CULL_BACK, specularMode = SPECULAR_SCHLICK_GGX,
                diffuseMode = DIFFUSE_BURLEY, billboardMode, emissionOp = EMISSION_OP_ADD, metallicTextureChannel, roughnessTextureChannel,
                aoTextureChannel, refractionTextureChannel, alphaAntialiasingMode = ALPHA_ANTIALIASING_OFF,
                stencilMode = STENCIL_MODE_DISABLED, stencilFlags, stencilCompare = STENCIL_COMPARE_ALWAYS, stencilReference = 1;
            public Vec3 uv1Scale, uv1Offset, uv2Scale, uv2Offset;
            public bool[] flags = new bool[FLAG_MAX];
            public bool[] features = new bool[FEATURE_MAX];
            public Texture2D[] textures = new Texture2D[TEXTURE_MAX];

            public State Clone()
            {
                var s = (State)MemberwiseClone();
                s.flags = (bool[])flags.Clone();
                s.features = (bool[])features.Clone();
                s.textures = (Texture2D[])textures.Clone();
                return s;
            }
        }

        State _s = new State();
        /// <summary>Set on a next pass this material made for its stencil Outline/X-Ray mode (Godot's "_stencil_owned" meta).</summary>
        public bool StencilOwned;

        void C() => EmitChanged();
        static void Err(string m) => GD.PushError(m);

        public BaseMaterial3D() : this(false) { }

        protected BaseMaterial3D(bool orm)
        {
            _s.orm = orm;
            _s.albedo = new Col(1f, 1f, 1f, 1f);
            _s.specular = 0.5f;
            _s.roughness = 1.0f;
            _s.metallic = 0.0f;
            _s.emission = new Col(0f, 0f, 0f, 1f);
            _s.emissionEnergyMultiplier = 1.0f;
            _s.normalScale = 1f;
            _s.rim = 1.0f;
            _s.rimTint = 0.5f;
            _s.clearcoat = 1f;
            _s.clearcoatRoughness = 0.5f;
            _s.anisotropy = 0f;
            _s.heightmapScale = 5.0f;
            _s.subsurfaceScatteringStrength = 0f;
            _s.backlight = new Col(0f, 0f, 0f, 1f);
            _s.transmittanceColor = new Col(1f, 1f, 1f, 1f);
            _s.transmittanceDepth = 0.1f;
            _s.transmittanceBoost = 0.0f;
            _s.refraction = 0.05f;
            _s.pointSize = 1f;
            _s.uv1Offset = new Vec3(0f, 0f, 0f);
            _s.uv1Scale = new Vec3(1f, 1f, 1f);
            _s.uv1TriplanarSharpness = 1f;
            _s.uv2Offset = new Vec3(0f, 0f, 0f);
            _s.uv2Scale = new Vec3(1f, 1f, 1f);
            _s.uv2TriplanarSharpness = 1f;
            _s.billboardMode = BILLBOARD_DISABLED;
            _s.particlesAnimHFrames = 1;
            _s.particlesAnimVFrames = 1;
            _s.particlesAnimLoop = false;
            _s.alphaScissorThreshold = 0.5f;
            _s.alphaHashScale = 1.0f;
            _s.alphaAntialiasingEdge = 0.3f;
            _s.proximityFadeDistance = 1f;
            _s.distanceFadeMinDistance = 0f;
            _s.distanceFadeMaxDistance = 10f;
            _s.aoLightAffect = 0.0f;
            _s.grow = 0.0f;
            _s.msdfPixelRange = 4.0f;
            _s.msdfOutlineSize = 0.0f;
            _s.deepParallaxMinLayers = 8;
            _s.deepParallaxMaxLayers = 32;
            _s.zClipScale = 1.0f;
            _s.fovOverride = 75.0f;
            _s.flags[FLAG_ALBEDO_TEXTURE_MSDF] = false;
            _s.flags[FLAG_USE_TEXTURE_REPEAT] = true;
        }

        public bool IsOrm => _s.orm;

        // ---------------------------------------------------------------- flags / features / textures
        public void SetFlag(int flag, bool enabled)
        {
            if (flag < 0 || flag >= FLAG_MAX) { Err("Index p_flag = " + flag + " is out of bounds (FLAG_MAX = " + FLAG_MAX + ")."); return; }
            if (_s.flags[flag] == enabled) return;
            _s.flags[flag] = enabled;
            C();
        }

        public bool GetFlag(int flag) => flag >= 0 && flag < FLAG_MAX && _s.flags[flag];

        public void SetFeature(int feature, bool enabled)
        {
            if (feature < 0 || feature >= FEATURE_MAX) { Err("Index p_feature = " + feature + " is out of bounds (FEATURE_MAX = " + FEATURE_MAX + ")."); return; }
            if (_s.features[feature] == enabled) return;
            _s.features[feature] = enabled;
            C();
        }

        public bool GetFeature(int feature) => feature >= 0 && feature < FEATURE_MAX && _s.features[feature];

        public void SetTexture(int param, Texture2D texture)
        {
            if (param < 0 || param >= TEXTURE_MAX) { Err("Index p_param = " + param + " is out of bounds (TEXTURE_MAX = " + TEXTURE_MAX + ")."); return; }
            _s.textures[param] = texture;
            C();
        }

        public Texture2D GetTexture(int param) => param >= 0 && param < TEXTURE_MAX ? _s.textures[param] : null;

        /// <summary>The flag/feature/texture arrays (renderer access).</summary>
        public IReadOnlyList<bool> Flags => _s.flags;
        public IReadOnlyList<bool> Features => _s.features;
        public IReadOnlyList<Texture2D> Textures => _s.textures;

        // ---------------------------------------------------------------- transparency
        public int Transparency { get => _s.transparency; set { if (_s.transparency == value) return; _s.transparency = value; C(); } }
        public double AlphaScissorThreshold { get => _s.alphaScissorThreshold; set { _s.alphaScissorThreshold = (float)value; C(); } }
        public double AlphaHashScale { get => _s.alphaHashScale; set { _s.alphaHashScale = (float)value; C(); } }
        public int AlphaAntialiasingMode { get => _s.alphaAntialiasingMode; set { if (_s.alphaAntialiasingMode == value) return; _s.alphaAntialiasingMode = value; C(); } }
        public double AlphaAntialiasingEdge { get => _s.alphaAntialiasingEdge; set { _s.alphaAntialiasingEdge = (float)value; C(); } }
        public int BlendMode { get => _s.blendMode; set { if (_s.blendMode == value) return; _s.blendMode = value; C(); } }
        public int CullMode { get => _s.cullMode; set { if (_s.cullMode == value) return; _s.cullMode = value; C(); } }
        public int DepthDrawMode { get => _s.depthDrawMode; set { if (_s.depthDrawMode == value) return; _s.depthDrawMode = value; C(); } }
        public bool NoDepthTest { get => GetFlag(FLAG_DISABLE_DEPTH_TEST); set => SetFlag(FLAG_DISABLE_DEPTH_TEST, value); }
        public int DepthTest { get => _s.depthTest; set { if (_s.depthTest == value) return; _s.depthTest = value; C(); } }

        // ---------------------------------------------------------------- shading
        public int ShadingMode { get => _s.shadingMode; set { if (_s.shadingMode == value) return; _s.shadingMode = value; C(); } }
        public int DiffuseMode { get => _s.diffuseMode; set { if (_s.diffuseMode == value) return; _s.diffuseMode = value; C(); } }
        public int SpecularMode { get => _s.specularMode; set { if (_s.specularMode == value) return; _s.specularMode = value; C(); } }
        public bool DisableAmbientLight { get => GetFlag(FLAG_DISABLE_AMBIENT_LIGHT); set => SetFlag(FLAG_DISABLE_AMBIENT_LIGHT, value); }
        public bool DisableFog { get => GetFlag(FLAG_DISABLE_FOG); set => SetFlag(FLAG_DISABLE_FOG, value); }
        public bool DisableSpecularOcclusion { get => GetFlag(FLAG_DISABLE_SPECULAR_OCCLUSION); set => SetFlag(FLAG_DISABLE_SPECULAR_OCCLUSION, value); }

        // ---------------------------------------------------------------- vertex color / albedo / orm
        public bool VertexColorUseAsAlbedo { get => GetFlag(FLAG_ALBEDO_FROM_VERTEX_COLOR); set => SetFlag(FLAG_ALBEDO_FROM_VERTEX_COLOR, value); }
        public bool VertexColorIsSrgb { get => GetFlag(FLAG_SRGB_VERTEX_COLOR); set => SetFlag(FLAG_SRGB_VERTEX_COLOR, value); }
        public Col AlbedoColor { get => _s.albedo; set { _s.albedo = value; C(); } }
        public Texture2D AlbedoTexture { get => GetTexture(TEXTURE_ALBEDO); set => SetTexture(TEXTURE_ALBEDO, value); }
        public bool AlbedoTextureForceSrgb { get => GetFlag(FLAG_ALBEDO_TEXTURE_FORCE_SRGB); set => SetFlag(FLAG_ALBEDO_TEXTURE_FORCE_SRGB, value); }
        public bool AlbedoTextureMsdf { get => GetFlag(FLAG_ALBEDO_TEXTURE_MSDF); set => SetFlag(FLAG_ALBEDO_TEXTURE_MSDF, value); }
        public Texture2D OrmTexture { get => GetTexture(TEXTURE_ORM); set => SetTexture(TEXTURE_ORM, value); }

        // ---------------------------------------------------------------- metallic / roughness
        public double Metallic { get => _s.metallic; set { _s.metallic = (float)value; C(); } }
        public double MetallicSpecular { get => _s.specular; set { _s.specular = (float)value; C(); } }
        public Texture2D MetallicTexture { get => GetTexture(TEXTURE_METALLIC); set => SetTexture(TEXTURE_METALLIC, value); }
        public int MetallicTextureChannel { get => _s.metallicTextureChannel; set { if ((uint)value >= 5) { Err("Index p_channel out of bounds."); return; } _s.metallicTextureChannel = value; C(); } }
        public double Roughness { get => _s.roughness; set { _s.roughness = (float)value; C(); } }
        public Texture2D RoughnessTexture { get => GetTexture(TEXTURE_ROUGHNESS); set => SetTexture(TEXTURE_ROUGHNESS, value); }
        public int RoughnessTextureChannel { get => _s.roughnessTextureChannel; set { if ((uint)value >= 5) { Err("Index p_channel out of bounds."); return; } _s.roughnessTextureChannel = value; C(); } }

        // ---------------------------------------------------------------- emission
        public bool EmissionEnabled { get => GetFeature(FEATURE_EMISSION); set => SetFeature(FEATURE_EMISSION, value); }
        public Col Emission { get => _s.emission; set { _s.emission = value; C(); } }
        public double EmissionEnergyMultiplier { get => _s.emissionEnergyMultiplier; set { _s.emissionEnergyMultiplier = (float)value; C(); } }
        public double EmissionIntensity
        {
            get => _s.emissionIntensity;
            set
            {
                if (!UsePhysicalLightUnits) { Err("Cannot set material emission intensity when Physical Light Units disabled."); return; }
                _s.emissionIntensity = (float)value;
                C();
            }
        }
        public int EmissionOperator { get => _s.emissionOp; set { if (_s.emissionOp == value) return; _s.emissionOp = value; C(); } }
        public bool EmissionOnUv2 { get => GetFlag(FLAG_EMISSION_ON_UV2); set => SetFlag(FLAG_EMISSION_ON_UV2, value); }
        public Texture2D EmissionTexture { get => GetTexture(TEXTURE_EMISSION); set => SetTexture(TEXTURE_EMISSION, value); }
        /// <summary>The energy the shader gets (emission_energy_multiplier, times emission_intensity with physical light units).</summary>
        public double EmissionEnergy => UsePhysicalLightUnits ? _s.emissionEnergyMultiplier * _s.emissionIntensity : _s.emissionEnergyMultiplier;

        // ---------------------------------------------------------------- normal / bent normal / rim / clearcoat / anisotropy
        public bool NormalEnabled { get => GetFeature(FEATURE_NORMAL_MAPPING); set => SetFeature(FEATURE_NORMAL_MAPPING, value); }
        public double NormalScale { get => _s.normalScale; set { _s.normalScale = (float)value; C(); } }
        public Texture2D NormalTexture { get => GetTexture(TEXTURE_NORMAL); set => SetTexture(TEXTURE_NORMAL, value); }
        public bool BentNormalEnabled { get => GetFeature(FEATURE_BENT_NORMAL_MAPPING); set => SetFeature(FEATURE_BENT_NORMAL_MAPPING, value); }
        public Texture2D BentNormalTexture { get => GetTexture(TEXTURE_BENT_NORMAL); set => SetTexture(TEXTURE_BENT_NORMAL, value); }
        public bool RimEnabled { get => GetFeature(FEATURE_RIM); set => SetFeature(FEATURE_RIM, value); }
        public double Rim { get => _s.rim; set { _s.rim = (float)value; C(); } }
        public double RimTint { get => _s.rimTint; set { _s.rimTint = (float)value; C(); } }
        public Texture2D RimTexture { get => GetTexture(TEXTURE_RIM); set => SetTexture(TEXTURE_RIM, value); }
        public bool ClearcoatEnabled { get => GetFeature(FEATURE_CLEARCOAT); set => SetFeature(FEATURE_CLEARCOAT, value); }
        public double Clearcoat { get => _s.clearcoat; set { _s.clearcoat = (float)value; C(); } }
        public double ClearcoatRoughness { get => _s.clearcoatRoughness; set { _s.clearcoatRoughness = (float)value; C(); } }
        public Texture2D ClearcoatTexture { get => GetTexture(TEXTURE_CLEARCOAT); set => SetTexture(TEXTURE_CLEARCOAT, value); }
        public bool AnisotropyEnabled { get => GetFeature(FEATURE_ANISOTROPY); set => SetFeature(FEATURE_ANISOTROPY, value); }
        public double Anisotropy { get => _s.anisotropy; set { _s.anisotropy = (float)value; C(); } }
        public Texture2D AnisotropyFlowmap { get => GetTexture(TEXTURE_FLOWMAP); set => SetTexture(TEXTURE_FLOWMAP, value); }

        // ---------------------------------------------------------------- ambient occlusion / height
        public bool AoEnabled { get => GetFeature(FEATURE_AMBIENT_OCCLUSION); set => SetFeature(FEATURE_AMBIENT_OCCLUSION, value); }
        public double AoLightAffect { get => _s.aoLightAffect; set { _s.aoLightAffect = (float)value; C(); } }
        public Texture2D AoTexture { get => GetTexture(TEXTURE_AMBIENT_OCCLUSION); set => SetTexture(TEXTURE_AMBIENT_OCCLUSION, value); }
        public bool AoOnUv2 { get => GetFlag(FLAG_AO_ON_UV2); set => SetFlag(FLAG_AO_ON_UV2, value); }
        public int AoTextureChannel { get => _s.aoTextureChannel; set { if ((uint)value >= 5) { Err("Index p_channel out of bounds."); return; } _s.aoTextureChannel = value; C(); } }
        public bool HeightmapEnabled { get => GetFeature(FEATURE_HEIGHT_MAPPING); set => SetFeature(FEATURE_HEIGHT_MAPPING, value); }
        public double HeightmapScale { get => _s.heightmapScale; set { _s.heightmapScale = (float)value; C(); } }
        public bool HeightmapDeepParallax { get => _s.deepParallax; set { _s.deepParallax = value; C(); } }
        public int HeightmapMinLayers { get => _s.deepParallaxMinLayers; set { _s.deepParallaxMinLayers = value; C(); } }
        public int HeightmapMaxLayers { get => _s.deepParallaxMaxLayers; set { _s.deepParallaxMaxLayers = value; C(); } }
        public bool HeightmapFlipTangent { get => _s.heightmapFlipTangent; set { _s.heightmapFlipTangent = value; C(); } }
        public bool HeightmapFlipBinormal { get => _s.heightmapFlipBinormal; set { _s.heightmapFlipBinormal = value; C(); } }
        public Texture2D HeightmapTexture { get => GetTexture(TEXTURE_HEIGHTMAP); set => SetTexture(TEXTURE_HEIGHTMAP, value); }
        public bool HeightmapFlipTexture { get => GetFlag(FLAG_INVERT_HEIGHTMAP); set => SetFlag(FLAG_INVERT_HEIGHTMAP, value); }

        // ---------------------------------------------------------------- subsurface scattering / backlight / refraction
        public bool SubsurfScatterEnabled { get => GetFeature(FEATURE_SUBSURFACE_SCATTERING); set => SetFeature(FEATURE_SUBSURFACE_SCATTERING, value); }
        public double SubsurfScatterStrength { get => _s.subsurfaceScatteringStrength; set { _s.subsurfaceScatteringStrength = (float)value; C(); } }
        public bool SubsurfScatterSkinMode { get => GetFlag(FLAG_SUBSURFACE_MODE_SKIN); set => SetFlag(FLAG_SUBSURFACE_MODE_SKIN, value); }
        public Texture2D SubsurfScatterTexture { get => GetTexture(TEXTURE_SUBSURFACE_SCATTERING); set => SetTexture(TEXTURE_SUBSURFACE_SCATTERING, value); }
        public bool SubsurfScatterTransmittanceEnabled { get => GetFeature(FEATURE_SUBSURFACE_TRANSMITTANCE); set => SetFeature(FEATURE_SUBSURFACE_TRANSMITTANCE, value); }
        public Col SubsurfScatterTransmittanceColor { get => _s.transmittanceColor; set { _s.transmittanceColor = value; C(); } }
        public Texture2D SubsurfScatterTransmittanceTexture { get => GetTexture(TEXTURE_SUBSURFACE_TRANSMITTANCE); set => SetTexture(TEXTURE_SUBSURFACE_TRANSMITTANCE, value); }
        public double SubsurfScatterTransmittanceDepth { get => _s.transmittanceDepth; set { _s.transmittanceDepth = (float)value; C(); } }
        public double SubsurfScatterTransmittanceBoost { get => _s.transmittanceBoost; set { _s.transmittanceBoost = (float)value; C(); } }
        public bool BacklightEnabled { get => GetFeature(FEATURE_BACKLIGHT); set => SetFeature(FEATURE_BACKLIGHT, value); }
        public Col Backlight { get => _s.backlight; set { _s.backlight = value; C(); } }
        public Texture2D BacklightTexture { get => GetTexture(TEXTURE_BACKLIGHT); set => SetTexture(TEXTURE_BACKLIGHT, value); }
        public bool RefractionEnabled { get => GetFeature(FEATURE_REFRACTION); set => SetFeature(FEATURE_REFRACTION, value); }
        public double RefractionScale { get => _s.refraction; set { _s.refraction = (float)value; C(); } }
        public Texture2D RefractionTexture { get => GetTexture(TEXTURE_REFRACTION); set => SetTexture(TEXTURE_REFRACTION, value); }
        public int RefractionTextureChannel { get => _s.refractionTextureChannel; set { if ((uint)value >= 5) { Err("Index p_channel out of bounds."); return; } _s.refractionTextureChannel = value; C(); } }

        // ---------------------------------------------------------------- detail
        public bool DetailEnabled { get => GetFeature(FEATURE_DETAIL); set => SetFeature(FEATURE_DETAIL, value); }
        public Texture2D DetailMask { get => GetTexture(TEXTURE_DETAIL_MASK); set => SetTexture(TEXTURE_DETAIL_MASK, value); }
        public int DetailBlendMode { get => _s.detailBlendMode; set { _s.detailBlendMode = value; C(); } }
        public int DetailUvLayer { get => _s.detailUv; set { if (_s.detailUv == value) return; _s.detailUv = value; C(); } }
        public Texture2D DetailAlbedo { get => GetTexture(TEXTURE_DETAIL_ALBEDO); set => SetTexture(TEXTURE_DETAIL_ALBEDO, value); }
        public Texture2D DetailNormal { get => GetTexture(TEXTURE_DETAIL_NORMAL); set => SetTexture(TEXTURE_DETAIL_NORMAL, value); }

        // ---------------------------------------------------------------- uv1 / uv2
        public Vec3 Uv1Scale { get => _s.uv1Scale; set { _s.uv1Scale = value; C(); } }
        public Vec3 Uv1Offset { get => _s.uv1Offset; set { _s.uv1Offset = value; C(); } }
        public bool Uv1Triplanar { get => GetFlag(FLAG_UV1_USE_TRIPLANAR); set => SetFlag(FLAG_UV1_USE_TRIPLANAR, value); }
        /// <summary>uv1_triplanar_sharpness, clamped to 0..150 (Godot: larger values give NaNs).</summary>
        public double Uv1TriplanarSharpness { get => _s.uv1TriplanarSharpness; set { _s.uv1TriplanarSharpness = (float)GD.Clamp((float)value, 0.0, 150.0); C(); } }
        public bool Uv1WorldTriplanar { get => GetFlag(FLAG_UV1_USE_WORLD_TRIPLANAR); set => SetFlag(FLAG_UV1_USE_WORLD_TRIPLANAR, value); }
        public Vec3 Uv2Scale { get => _s.uv2Scale; set { _s.uv2Scale = value; C(); } }
        public Vec3 Uv2Offset { get => _s.uv2Offset; set { _s.uv2Offset = value; C(); } }
        public bool Uv2Triplanar { get => GetFlag(FLAG_UV2_USE_TRIPLANAR); set => SetFlag(FLAG_UV2_USE_TRIPLANAR, value); }
        public double Uv2TriplanarSharpness { get => _s.uv2TriplanarSharpness; set { _s.uv2TriplanarSharpness = (float)GD.Clamp((float)value, 0.0, 150.0); C(); } }
        public bool Uv2WorldTriplanar { get => GetFlag(FLAG_UV2_USE_WORLD_TRIPLANAR); set => SetFlag(FLAG_UV2_USE_WORLD_TRIPLANAR, value); }

        // ---------------------------------------------------------------- sampling / shadows / billboard / particles anim
        public int TextureFilter { get => _s.textureFilter; set { _s.textureFilter = value; C(); } }
        public bool TextureRepeat { get => GetFlag(FLAG_USE_TEXTURE_REPEAT); set => SetFlag(FLAG_USE_TEXTURE_REPEAT, value); }
        public bool DisableReceiveShadows { get => GetFlag(FLAG_DONT_RECEIVE_SHADOWS); set => SetFlag(FLAG_DONT_RECEIVE_SHADOWS, value); }
        public bool ShadowToOpacity { get => GetFlag(FLAG_USE_SHADOW_TO_OPACITY); set => SetFlag(FLAG_USE_SHADOW_TO_OPACITY, value); }
        public int BillboardMode { get => _s.billboardMode; set { _s.billboardMode = value; C(); } }
        public bool BillboardKeepScale { get => GetFlag(FLAG_BILLBOARD_KEEP_SCALE); set => SetFlag(FLAG_BILLBOARD_KEEP_SCALE, value); }
        public int ParticlesAnimHFrames { get => _s.particlesAnimHFrames; set { _s.particlesAnimHFrames = value; C(); } }
        public int ParticlesAnimVFrames { get => _s.particlesAnimVFrames; set { _s.particlesAnimVFrames = value; C(); } }
        public bool ParticlesAnimLoop { get => _s.particlesAnimLoop; set { _s.particlesAnimLoop = value; C(); } }

        // ---------------------------------------------------------------- grow / transform
        /// <summary>grow (bool; Godot's set_grow_enabled).</summary>
        public bool Grow { get => _s.growEnabled; set { _s.growEnabled = value; C(); } }
        /// <summary>grow_amount (Godot's set_grow).</summary>
        public double GrowAmount { get => _s.grow; set { _s.grow = (float)value; C(); } }
        public bool FixedSize { get => GetFlag(FLAG_FIXED_SIZE); set => SetFlag(FLAG_FIXED_SIZE, value); }
        public bool UsePointSize { get => GetFlag(FLAG_USE_POINT_SIZE); set => SetFlag(FLAG_USE_POINT_SIZE, value); }
        public double PointSize { get => _s.pointSize; set { _s.pointSize = (float)value; C(); } }
        public bool UseParticleTrails { get => GetFlag(FLAG_PARTICLE_TRAILS_MODE); set => SetFlag(FLAG_PARTICLE_TRAILS_MODE, value); }
        public bool UseZClipScale { get => GetFlag(FLAG_USE_Z_CLIP_SCALE); set => SetFlag(FLAG_USE_Z_CLIP_SCALE, value); }
        public double ZClipScale { get => _s.zClipScale; set { _s.zClipScale = (float)value; C(); } }
        public bool UseFovOverride { get => GetFlag(FLAG_USE_FOV_OVERRIDE); set => SetFlag(FLAG_USE_FOV_OVERRIDE, value); }
        public double FovOverride { get => _s.fovOverride; set { _s.fovOverride = (float)value; C(); } }

        // ---------------------------------------------------------------- proximity / msdf / distance fade
        public bool ProximityFadeEnabled { get => _s.proximityFadeEnabled; set { _s.proximityFadeEnabled = value; C(); } }
        /// <summary>proximity_fade_distance (at least 0.01).</summary>
        public double ProximityFadeDistance { get => _s.proximityFadeDistance; set { _s.proximityFadeDistance = (float)Math.Max((float)value, 0.01); C(); } }
        public double MsdfPixelRange { get => _s.msdfPixelRange; set { _s.msdfPixelRange = (float)value; C(); } }
        public double MsdfOutlineSize { get => _s.msdfOutlineSize; set { _s.msdfOutlineSize = (float)value; C(); } }
        public int DistanceFadeMode { get => _s.distanceFade; set { _s.distanceFade = value; C(); } }
        public double DistanceFadeMinDistance { get => _s.distanceFadeMinDistance; set { _s.distanceFadeMinDistance = (float)value; C(); } }
        public double DistanceFadeMaxDistance { get => _s.distanceFadeMaxDistance; set { _s.distanceFadeMaxDistance = (float)value; C(); } }

        // ---------------------------------------------------------------- stencil
        public int StencilMode
        {
            get => _s.stencilMode;
            set
            {
                if (_s.stencilMode == value) return;
                if ((value == STENCIL_MODE_OUTLINE || value == STENCIL_MODE_XRAY) && RenderPriority >= RENDER_PRIORITY_MAX)
                {
                    Err("Cannot use stencil mode Outline or Xray, when render priority is RENDER_PRIORITY_MAX(" + RENDER_PRIORITY_MAX + ").");
                    return;
                }
                _s.stencilMode = value;
                PrepareStencilEffect();
                C();
            }
        }

        public int StencilFlags
        {
            get => _s.stencilFlags;
            set
            {
                int f = value;
                if (_s.stencilFlags == f) return;
                if ((f & STENCIL_FLAG_READ) != 0 && (_s.stencilFlags & (STENCIL_FLAG_WRITE | STENCIL_FLAG_WRITE_DEPTH_FAIL)) != 0) f &= STENCIL_FLAG_READ;
                if ((f & (STENCIL_FLAG_WRITE | STENCIL_FLAG_WRITE_DEPTH_FAIL)) != 0 && (_s.stencilFlags & STENCIL_FLAG_READ) != 0) f &= (STENCIL_FLAG_WRITE | STENCIL_FLAG_WRITE_DEPTH_FAIL);
                if ((f & STENCIL_FLAG_READ) != 0 && (f & (STENCIL_FLAG_WRITE | STENCIL_FLAG_WRITE_DEPTH_FAIL)) != 0) f &= STENCIL_FLAG_READ;
                _s.stencilFlags = f;
                C();
            }
        }

        public int StencilCompare { get => _s.stencilCompare; set { if (_s.stencilCompare == value) return; _s.stencilCompare = value; C(); } }

        public int StencilReference
        {
            get => _s.stencilReference;
            set
            {
                if (_s.stencilReference == value) return;
                _s.stencilReference = value;
                C();
                StencilNextPass()?.SetStencilReferenceFromOwner(value);
            }
        }

        void SetStencilReferenceFromOwner(int v) => StencilReference = v;

        public Col StencilColor
        {
            get => _s.stencilEffectColor;
            set
            {
                if (_s.stencilEffectColor == value) return;
                _s.stencilEffectColor = value;
                C();
                var np = StencilNextPass();
                if (np != null) np.AlbedoColor = value;
            }
        }

        public double StencilOutlineThickness
        {
            get => _s.stencilEffectOutlineThickness;
            set
            {
                float t = (float)value;
                if (_s.stencilEffectOutlineThickness == t) return;
                _s.stencilEffectOutlineThickness = t;
                C();
                var np = StencilNextPass();
                if (np != null) np.GrowAmount = t;
            }
        }

        BaseMaterial3D StencilNextPass() => NextPass is BaseMaterial3D b && b.StencilOwned ? b : null;

        void PrepareStencilEffect()
        {
            GMaterial current = NextPass;
            if (_s.stencilMode == STENCIL_MODE_DISABLED || _s.stencilMode == STENCIL_MODE_CUSTOM)
            {
                if (current is BaseMaterial3D owned && owned.StencilOwned) NextPass = owned.NextPass;
                return;
            }
            BaseMaterial3D np;
            if (!(current is BaseMaterial3D cb) || !cb.StencilOwned)
            {
                np = new StandardMaterial3D { StencilOwned = true };
                np.NextPass = current;
                NextPass = np;
            }
            else np = cb;

            StencilFlags = STENCIL_FLAG_WRITE;
            StencilCompare = STENCIL_COMPARE_ALWAYS;
            np.RenderPriority = RenderPriority + 1;
            np.ShadingMode = SHADING_MODE_UNSHADED;
            np.Transparency = TRANSPARENCY_ALPHA;
            if (_s.stencilMode == STENCIL_MODE_OUTLINE)
            {
                np.SetFlag(FLAG_DISABLE_DEPTH_TEST, false);
                np.Grow = true;
                np.GrowAmount = _s.stencilEffectOutlineThickness;
            }
            else
            {
                np.SetFlag(FLAG_DISABLE_DEPTH_TEST, true);
                np.Grow = false;
                np.GrowAmount = 0;
            }
            np.AlbedoColor = _s.stencilEffectColor;
            np.StencilMode = STENCIL_MODE_CUSTOM;
            np.StencilFlags = STENCIL_FLAG_READ;
            np.StencilCompare = STENCIL_COMPARE_NOT_EQUAL;
            np.StencilReference = _s.stencilReference;
        }

        /// <summary>set_on_top_of_alpha().</summary>
        public void SetOnTopOfAlpha()
        {
            Transparency = TRANSPARENCY_DISABLED;
            RenderPriority = RENDER_PRIORITY_MAX;
            SetFlag(FLAG_DISABLE_DEPTH_TEST, true);
        }

        // ---------------------------------------------------------------- duplicate
        public override Resource Duplicate(bool deep = false)
        {
            var m = (BaseMaterial3D)Activator.CreateInstance(GetType(), true);
            m._s = _s.Clone();
            m.StencilOwned = StencilOwned;
            m.ResourceName = ResourceName;
            m.RenderPriority = RenderPriority;
            GMaterial np = NextPass;
            if (deep)
            {
                for (int i = 0; i < TEXTURE_MAX; i++)
                    if (m._s.textures[i] != null && string.IsNullOrEmpty(m._s.textures[i].ResourcePath)) m._s.textures[i] = (Texture2D)m._s.textures[i].Duplicate(true);
                if (np != null && string.IsNullOrEmpty(np.ResourcePath)) np = (GMaterial)np.Duplicate(true);
            }
            m.NextPass = np;
            return m;
        }
    }

    public class StandardMaterial3D : BaseMaterial3D
    {
        public StandardMaterial3D() : base(false) { }

        static readonly Dictionary<string, string> Remaps = new Dictionary<string, string>
        {
            { "flags_use_shadow_to_opacity", "shadow_to_opacity" },
            { "flags_no_depth_test", "no_depth_test" },
            { "flags_use_point_size", "use_point_size" },
            { "flags_fixed_size", "fixed_size" },
            { "flags_albedo_tex_force_srgb", "albedo_texture_force_srgb" },
            { "flags_do_not_receive_shadows", "disable_receive_shadows" },
            { "flags_disable_ambient_light", "disable_ambient_light" },
            { "params_diffuse_mode", "diffuse_mode" },
            { "params_specular_mode", "specular_mode" },
            { "params_blend_mode", "blend_mode" },
            { "params_cull_mode", "cull_mode" },
            { "params_point_size", "point_size" },
            { "params_billboard_mode", "billboard_mode" },
            { "params_billboard_keep_scale", "billboard_keep_scale" },
            { "params_grow", "grow" },
            { "params_grow_amount", "grow_amount" },
            { "params_alpha_scissor_threshold", "alpha_scissor_threshold" },
            { "params_alpha_hash_scale", "alpha_hash_scale" },
            { "params_alpha_antialiasing_edge", "alpha_antialiasing_edge" },
            { "depth_scale", "heightmap_scale" },
            { "depth_deep_parallax", "heightmap_deep_parallax" },
            { "depth_min_layers", "heightmap_min_layers" },
            { "depth_max_layers", "heightmap_max_layers" },
            { "depth_flip_tangent", "heightmap_flip_tangent" },
            { "depth_flip_binormal", "heightmap_flip_binormal" },
            { "depth_texture", "heightmap_texture" },
            { "emission_energy", "emission_energy_multiplier" },
        };

        /// <summary>StandardMaterial3D::_set: Godot 3.x SpatialMaterial names found in old resources.</summary>
        public override bool SetStoredProperty(string name, Var value)
        {
            switch (name)
            {
                case "flags_transparent": if (value.Truthy) Transparency = TRANSPARENCY_ALPHA; return true;
                case "flags_unshaded": if (value.Truthy) ShadingMode = SHADING_MODE_UNSHADED; return true;
                case "flags_vertex_lighting": if (value.Truthy && ShadingMode != SHADING_MODE_UNSHADED) ShadingMode = SHADING_MODE_PER_VERTEX; return true;
                case "params_use_alpha_scissor": if (value.Truthy) Transparency = TRANSPARENCY_ALPHA_SCISSOR; return true;
                case "params_use_alpha_hash": if (value.Truthy) Transparency = TRANSPARENCY_ALPHA_HASH; return true;
                case "params_depth_draw_mode": if (value.AsInt() == 3) Transparency = TRANSPARENCY_ALPHA_DEPTH_PRE_PASS; return true;
                case "depth_enabled": if (value.Truthy) { SetFeature(FEATURE_HEIGHT_MAPPING, true); SetFlag(FLAG_INVERT_HEIGHTMAP, true); } return true;
            }
            if (name.StartsWith("flags_") || name.StartsWith("params_") || name.StartsWith("depth_") || name == "emission_energy")
            {
                if (Remaps.TryGetValue(name, out string to)) { PropertyPath.Set(this, to, value.Obj); return true; }
                GD.PushWarning("Godot 3.x SpatialMaterial remapped parameter not found: " + name);
                return true;
            }
            return false;
        }
    }

    public class ORMMaterial3D : BaseMaterial3D
    {
        public ORMMaterial3D() : base(true) { }
    }
}

#endif
