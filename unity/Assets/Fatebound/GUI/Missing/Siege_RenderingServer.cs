// Facade additions for the siege/ port (siege_diag.gd's STAT / SESSION lines, siege_mode.gd's warm-up): what Godot's
// RenderingServer reports about the frames it draws.
//  - RID (Godot's resource id) and Viewport.get_viewport_rid(): a viewport's id here is its instance id.
//  - get_rendering_info(info), viewport_get_render_info(viewport, type, info), viewport_set_measure_render_time /
//    viewport_get_measured_render_time_cpu / _gpu, get_video_adapter_vendor / _name / _api_version, with Godot's enum
//    values (servers/rendering/rendering_server_enums.h RenderingInfo, ViewportRenderInfo, ViewportRenderInfoType).
//    The numbers come from the hooks below, which the renderer (the Unity client) can fill; unfilled, the answers are
//    those of Godot's dummy renderer (servers/rendering/dummy: every count 0, the adapter's strings empty, no times).
using System;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    /// <summary>Godot's RID: an opaque id (0: invalid, as RID()).</summary>
    public readonly struct RID : IEquatable<RID>
    {
        public readonly ulong Id;
        public RID(ulong id) { Id = id; }
        public bool IsValid() => Id != 0;
        public ulong GetId() => Id;
        public bool Equals(RID o) => o.Id == Id;
        public override bool Equals(object o) => o is RID r && r.Id == Id;
        public override int GetHashCode() => Id.GetHashCode();
        public static bool operator ==(RID a, RID b) => a.Id == b.Id;
        public static bool operator !=(RID a, RID b) => a.Id != b.Id;
        public override string ToString() => "RID(" + Id + ")";
    }

    public partial class Viewport
    {
        /// <summary>get_viewport_rid(): this viewport's id (its instance id).</summary>
        public RID GetViewportRid() => new RID(GetInstanceId());
    }

    public static partial class RenderingServer
    {
        public const int RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME = 0, RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME = 1,
            RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME = 2, RENDERING_INFO_TEXTURE_MEM_USED = 3, RENDERING_INFO_BUFFER_MEM_USED = 4,
            RENDERING_INFO_VIDEO_MEM_USED = 5, RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS = 6, RENDERING_INFO_PIPELINE_COMPILATIONS_MESH = 7,
            RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE = 8, RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW = 9,
            RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION = 10;
        public const int VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME = 0, VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME = 1,
            VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME = 2;
        public const int VIEWPORT_RENDER_INFO_TYPE_VISIBLE = 0, VIEWPORT_RENDER_INFO_TYPE_SHADOW = 1, VIEWPORT_RENDER_INFO_TYPE_CANVAS = 2;

        /// <summary>The renderer's answers (null: the dummy renderer's).</summary>
        public static Func<int, long> RenderingInfoHook;
        /// <summary>(viewport, type, info) -> count.</summary>
        public static Func<RID, int, int, int> ViewportRenderInfoHook;
        /// <summary>(viewport, gpu) -> the last frame's time in ms; called only while measuring is on for it.</summary>
        public static Func<RID, bool, double> MeasuredRenderTimeHook;
        public static Action<RID, bool> MeasureRenderTimeHook;
        public static string VideoAdapterVendor = "", VideoAdapterName = "", VideoAdapterApiVersion = "";

        static readonly System.Collections.Generic.HashSet<RID> _measured = new System.Collections.Generic.HashSet<RID>();

        public static long GetRenderingInfo(int info) => RenderingInfoHook?.Invoke(info) ?? 0;
        public static int ViewportGetRenderInfo(RID viewport, int type, int info) => ViewportRenderInfoHook?.Invoke(viewport, type, info) ?? 0;

        public static void ViewportSetMeasureRenderTime(RID viewport, bool enable)
        {
            lock (_measured)
            {
                if (enable) _measured.Add(viewport);
                else _measured.Remove(viewport);
            }
            MeasureRenderTimeHook?.Invoke(viewport, enable);
        }

        static double Measured(RID viewport, bool gpu)
        {
            lock (_measured)
                if (!_measured.Contains(viewport)) return 0.0;
            return MeasuredRenderTimeHook?.Invoke(viewport, gpu) ?? 0.0;
        }

        public static double ViewportGetMeasuredRenderTimeCpu(RID viewport) => Measured(viewport, false);
        public static double ViewportGetMeasuredRenderTimeGpu(RID viewport) => Measured(viewport, true);
        public static string GetVideoAdapterVendor() => VideoAdapterVendor ?? "";
        public static string GetVideoAdapterName() => VideoAdapterName ?? "";
        public static string GetVideoAdapterApiVersion() => VideoAdapterApiVersion ?? "";
    }
}
