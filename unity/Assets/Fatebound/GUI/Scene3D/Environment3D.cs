#if FB3D
// Godot's Environment (background, ambient light, tonemap, glow, fog, adjustments), Sky and the sky materials. Plain
// property bags with Godot's defaults; a change bumps the version (EmitChanged) and the renderer re-reads it.
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public sealed class Environment : Resource
    {
        public const int BG_CLEAR_COLOR = 0, BG_COLOR = 1, BG_SKY = 2, BG_CANVAS = 3, BG_KEEP = 4, BG_CAMERA_FEED = 5;
        public const int AMBIENT_SOURCE_BG = 0, AMBIENT_SOURCE_DISABLED = 1, AMBIENT_SOURCE_COLOR = 2, AMBIENT_SOURCE_SKY = 3;
        public const int REFLECTION_SOURCE_BG = 0, REFLECTION_SOURCE_DISABLED = 1, REFLECTION_SOURCE_SKY = 2;
        public const int TONE_MAPPER_LINEAR = 0, TONE_MAPPER_REINHARDT = 1, TONE_MAPPER_FILMIC = 2, TONE_MAPPER_ACES = 3, TONE_MAPPER_AGX = 4;
        public const int GLOW_BLEND_MODE_ADDITIVE = 0, GLOW_BLEND_MODE_SCREEN = 1, GLOW_BLEND_MODE_SOFTLIGHT = 2,
            GLOW_BLEND_MODE_REPLACE = 3, GLOW_BLEND_MODE_MIX = 4;
        public const int FOG_MODE_EXPONENTIAL = 0, FOG_MODE_DEPTH = 1;

        int _bgMode = BG_CLEAR_COLOR, _ambientSource = AMBIENT_SOURCE_BG, _reflSource = REFLECTION_SOURCE_BG,
            _tonemap = TONE_MAPPER_LINEAR, _glowBlend = GLOW_BLEND_MODE_SCREEN, _fogMode = FOG_MODE_EXPONENTIAL;
        Col _bgColor = new Col(0, 0, 0, 1), _ambientColor = new Col(0, 0, 0, 1), _fogColor = new Col(0.518f, 0.553f, 0.608f, 1);
        double _bgEnergy = 1.0, _ambientEnergy = 1.0, _ambientSkyContribution = 1.0, _exposure = 1.0, _white = 1.0,
            _glowIntensity = 0.8, _glowStrength = 1.0, _glowMix = 0.05, _glowBloom, _glowThreshold = 1.0,
            _glowHdrScale = 2.0, _glowHdrLuminanceCap = 12.0, _glowMapStrength = 0.8,
            _fogEnergy = 1.0, _fogSunScatter, _fogDensity = 0.01, _fogAerial, _fogSkyAffect = 1.0, _fogHeight,
            _fogHeightDensity, _fogDepthCurve = 1.0, _fogDepthBegin = 10.0, _fogDepthEnd = 100.0,
            _brightness = 1.0, _contrast = 1.0, _saturation = 1.0;
        bool _glow, _glowNormalized, _fog, _adjust, _ssao, _ssr, _sdfgi, _ssil, _volumetricFog;
        readonly float[] _glowLevels = { 0, 1, 0, 1, 0, 0, 0 };
        Sky _sky;
        Vec3 _skyRotation;
        double _skyCustomFov;
        Texture2D _adjustColorCorrection;

        void C() => EmitChanged();
        public int BackgroundMode { get => _bgMode; set { _bgMode = value; C(); } }
        public Col BackgroundColor { get => _bgColor; set { _bgColor = value; C(); } }
        public double BackgroundEnergyMultiplier { get => _bgEnergy; set { _bgEnergy = value; C(); } }
        public Sky Sky { get => _sky; set { _sky = value; C(); } }
        public Vec3 SkyRotation { get => _skyRotation; set { _skyRotation = value; C(); } }
        public double SkyCustomFov { get => _skyCustomFov; set { _skyCustomFov = value; C(); } }
        public int AmbientLightSource { get => _ambientSource; set { _ambientSource = value; C(); } }
        public Col AmbientLightColor { get => _ambientColor; set { _ambientColor = value; C(); } }
        public double AmbientLightEnergy { get => _ambientEnergy; set { _ambientEnergy = value; C(); } }
        public double AmbientLightSkyContribution { get => _ambientSkyContribution; set { _ambientSkyContribution = value; C(); } }
        public int ReflectedLightSource { get => _reflSource; set { _reflSource = value; C(); } }
        public int TonemapMode { get => _tonemap; set { _tonemap = value; C(); } }
        public double TonemapExposure { get => _exposure; set { _exposure = value; C(); } }
        public double TonemapWhite { get => _white; set { _white = value; C(); } }

        public bool GlowEnabled { get => _glow; set { _glow = value; C(); } }
        public bool GlowNormalized { get => _glowNormalized; set { _glowNormalized = value; C(); } }
        public double GlowIntensity { get => _glowIntensity; set { _glowIntensity = value; C(); } }
        public double GlowStrength { get => _glowStrength; set { _glowStrength = value; C(); } }
        public double GlowMix { get => _glowMix; set { _glowMix = value; C(); } }
        public double GlowBloom { get => _glowBloom; set { _glowBloom = value; C(); } }
        public int GlowBlendMode { get => _glowBlend; set { _glowBlend = value; C(); } }
        public double GlowHdrThreshold { get => _glowThreshold; set { _glowThreshold = value; C(); } }
        public double GlowHdrScale { get => _glowHdrScale; set { _glowHdrScale = value; C(); } }
        public double GlowHdrLuminanceCap { get => _glowHdrLuminanceCap; set { _glowHdrLuminanceCap = value; C(); } }
        public double GlowMapStrength { get => _glowMapStrength; set { _glowMapStrength = value; C(); } }
        public Texture2D GlowMap;
        public void SetGlowLevel(int i, double intensity) { if (i >= 0 && i < 7) { _glowLevels[i] = (float)intensity; C(); } }
        public void SetGlowLevel(int i, bool on) => SetGlowLevel(i, on ? 1.0 : 0.0);
        public double GetGlowLevel(int i) => i >= 0 && i < 7 ? _glowLevels[i] : 0.0;
        public IReadOnlyList<float> GlowLevels => _glowLevels;

        public bool FogEnabled { get => _fog; set { _fog = value; C(); } }
        public int FogMode { get => _fogMode; set { _fogMode = value; C(); } }
        public Col FogLightColor { get => _fogColor; set { _fogColor = value; C(); } }
        public double FogLightEnergy { get => _fogEnergy; set { _fogEnergy = value; C(); } }
        public double FogSunScatter { get => _fogSunScatter; set { _fogSunScatter = value; C(); } }
        public double FogDensity { get => _fogDensity; set { _fogDensity = value; C(); } }
        public double FogAerialPerspective { get => _fogAerial; set { _fogAerial = value; C(); } }
        public double FogSkyAffect { get => _fogSkyAffect; set { _fogSkyAffect = value; C(); } }
        public double FogHeight { get => _fogHeight; set { _fogHeight = value; C(); } }
        public double FogHeightDensity { get => _fogHeightDensity; set { _fogHeightDensity = value; C(); } }
        public double FogDepthCurve { get => _fogDepthCurve; set { _fogDepthCurve = value; C(); } }
        public double FogDepthBegin { get => _fogDepthBegin; set { _fogDepthBegin = value; C(); } }
        public double FogDepthEnd { get => _fogDepthEnd; set { _fogDepthEnd = value; C(); } }

        public bool AdjustmentEnabled { get => _adjust; set { _adjust = value; C(); } }
        public double AdjustmentBrightness { get => _brightness; set { _brightness = value; C(); } }
        public double AdjustmentContrast { get => _contrast; set { _contrast = value; C(); } }
        public double AdjustmentSaturation { get => _saturation; set { _saturation = value; C(); } }
        public Texture2D AdjustmentColorCorrection { get => _adjustColorCorrection; set { _adjustColorCorrection = value; C(); } }

        // (not drawn by the mobile renderer the game targets; kept so the code that switches them compiles and reads back)
        public bool SsaoEnabled { get => _ssao; set { _ssao = value; C(); } }
        public bool SsrEnabled { get => _ssr; set { _ssr = value; C(); } }
        public bool SdfgiEnabled { get => _sdfgi; set { _sdfgi = value; C(); } }
        public bool SsilEnabled { get => _ssil; set { _ssil = value; C(); } }
        public bool VolumetricFogEnabled { get => _volumetricFog; set { _volumetricFog = value; C(); } }
        public double SsaoIntensity = 2.0, SsaoRadius = 1.0;
    }

    public sealed class Sky : Resource
    {
        public const int RADIANCE_SIZE_32 = 0, RADIANCE_SIZE_64 = 1, RADIANCE_SIZE_128 = 2, RADIANCE_SIZE_256 = 3,
            RADIANCE_SIZE_512 = 4, RADIANCE_SIZE_1024 = 5, RADIANCE_SIZE_2048 = 6;
        public const int PROCESS_MODE_AUTOMATIC = 0, PROCESS_MODE_QUALITY = 1, PROCESS_MODE_INCREMENTAL = 2, PROCESS_MODE_REALTIME = 3;
        GMaterial _mat;
        public GMaterial SkyMaterial { get => _mat; set { _mat = value; EmitChanged(); } }
        public int RadianceSize = RADIANCE_SIZE_256;
        public int ProcessMode = PROCESS_MODE_AUTOMATIC;
    }

    /// <summary>ProceduralSkyMaterial: Godot's gradient sky (top/horizon/ground colours, curves, the sun disc).</summary>
    public sealed class ProceduralSkyMaterial : GMaterial
    {
        Col _top = new Col(0.385f, 0.454f, 0.55f, 1f), _horizon = new Col(0.6463f, 0.6558f, 0.6708f, 1f),
            _groundBottom = new Col(0.2f, 0.169f, 0.133f, 1f), _groundHorizon = new Col(0.6463f, 0.6558f, 0.6708f, 1f);
        double _skyCurve = 0.15, _skyEnergy = 1.0, _groundCurve = 0.02, _groundEnergy = 1.0, _sunAngleMax = 30.0,
            _sunCurve = 0.15, _coverStrength;
        Texture2D _cover;
        bool _debanding = true;
        void C() => EmitChanged();
        public Col SkyTopColor { get => _top; set { _top = value; C(); } }
        public Col SkyHorizonColor { get => _horizon; set { _horizon = value; C(); } }
        public double SkyCurve { get => _skyCurve; set { _skyCurve = value; C(); } }
        public double SkyEnergyMultiplier { get => _skyEnergy; set { _skyEnergy = value; C(); } }
        public Texture2D SkyCover { get => _cover; set { _cover = value; C(); } }
        public double SkyCoverStrength { get => _coverStrength; set { _coverStrength = value; C(); } }
        public Col GroundBottomColor { get => _groundBottom; set { _groundBottom = value; C(); } }
        public Col GroundHorizonColor { get => _groundHorizon; set { _groundHorizon = value; C(); } }
        public double GroundCurve { get => _groundCurve; set { _groundCurve = value; C(); } }
        public double GroundEnergyMultiplier { get => _groundEnergy; set { _groundEnergy = value; C(); } }
        public double SunAngleMax { get => _sunAngleMax; set { _sunAngleMax = value; C(); } }
        public double SunCurve { get => _sunCurve; set { _sunCurve = value; C(); } }
        public bool UseDebanding { get => _debanding; set { _debanding = value; C(); } }
    }

    public sealed class PanoramaSkyMaterial : GMaterial
    {
        Texture2D _pano;
        double _energy = 1.0;
        public Texture2D Panorama { get => _pano; set { _pano = value; EmitChanged(); } }
        public double EnergyMultiplier { get => _energy; set { _energy = value; EmitChanged(); } }
        public bool Filter = true;
    }
}
#endif
