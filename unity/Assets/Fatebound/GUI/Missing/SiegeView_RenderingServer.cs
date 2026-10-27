// Facade additions for the siege view's port (siege_view.gd _apply_hq; gpu_probe.gd uses the same calls):
// RenderingServer.directional_shadow_atlas_set_size(size, 16_bits) and directional_soft_shadow_filter_set_quality(quality),
// with Godot's ShadowQuality values (servers/rendering/rendering_server_enums.h). Godot hands both straight to the
// renderer's light storage / scene render; here they are stored for the renderer (the Unity client) to read and apply.
// Their starting values are the project settings' .mobile defaults (rendering_server.cpp: directional_shadow/size.mobile
// 2048, soft_shadow_filter_quality.mobile 0 = hard) -- the game ships to Android, and project.godot sets neither.
using System;

namespace Fatebound.GUI
{
    public static partial class RenderingServer
    {
        public const int SHADOW_QUALITY_HARD = 0, SHADOW_QUALITY_SOFT_VERY_LOW = 1, SHADOW_QUALITY_SOFT_LOW = 2,
            SHADOW_QUALITY_SOFT_MEDIUM = 3, SHADOW_QUALITY_SOFT_HIGH = 4, SHADOW_QUALITY_SOFT_ULTRA = 5, SHADOW_QUALITY_MAX = 6;

        /// <summary>The directional shadow atlas the renderer should use (directional_shadow_atlas_set_size).</summary>
        public static int DirectionalShadowAtlasSize = 2048;
        public static bool DirectionalShadowAtlas16Bits = true;
        /// <summary>The directional lights' soft shadow filter (a SHADOW_QUALITY_* value).</summary>
        public static int DirectionalSoftShadowFilterQuality = SHADOW_QUALITY_HARD;
        /// <summary>Raised when either changes (the renderer re-applies them).</summary>
        public static event Action DirectionalShadowSettingsChanged;

        public static void DirectionalShadowAtlasSetSize(int size, bool is16Bits = true)
        {
            DirectionalShadowAtlasSize = size;
            DirectionalShadowAtlas16Bits = is16Bits;
            DirectionalShadowSettingsChanged?.Invoke();
        }

        public static void DirectionalSoftShadowFilterSetQuality(int quality)
        {
            if (quality < 0 || quality >= SHADOW_QUALITY_MAX)
            {
                Fatebound.Sim.GD.PushError("Index p_quality = " + quality + " is out of bounds (RSE::SHADOW_QUALITY_MAX = " + SHADOW_QUALITY_MAX + ").");
                return;
            }
            DirectionalSoftShadowFilterQuality = quality;
            DirectionalShadowSettingsChanged?.Invoke();
        }
    }
}
