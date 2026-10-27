// What Godot's RenderingServer reports about its frames (siege_diag.gd's STAT and SESSION lines, the match log Kevin
// sends back), answered from Unity:
//  - the adapter: SystemInfo's graphics device vendor / name / version
//  - viewport_get_measured_render_time_gpu / _cpu: Unity's FrameTimingManager (PlayerSettings.enableFrameTimingStats,
//    set by the build script). Unity times whole frames, not viewports: the 3D viewports get the frame's GPU time
//    and render-thread CPU time, the root (the GUI) 0 -- so "gpu3d" is the whole frame's graphics-chip time.
//  - draw calls and primitives: ProfilerRecorder's "Draw Calls Count" / "Triangles Count" for the frame (0 where a
//    player build doesn't record them), the root's canvas draws counted by CanvasDrawer; texture and video memory
//    from Texture.currentTextureMemory and "Gfx Used Memory". Pipeline compilations: Unity doesn't count them (0).
using System;
using Fatebound.GUI;
using Unity.Profiling;
using UnityEngine;
using UnityEngine.Rendering;
using RID = Fatebound.GUI.RID;

namespace Fatebound.Client
{
    public static class UnityRenderStats
    {
        static readonly FrameTiming[] _timings = new FrameTiming[1];
        static double _gpuMs, _cpuRenderMs;
        static ProfilerRecorder _draws, _tris, _gfxMem;
        static SceneTree _tree;
        /// <summary>Canvas draw calls this frame (CanvasDrawer counts them).</summary>
        public static int CanvasDraws, CanvasPrimitives;
        static int _canvasDrawsLast, _canvasPrimsLast;

        public static void Install(SceneTree tree)
        {
            _tree = tree;
            RenderingServer.VideoAdapterVendor = SystemInfo.graphicsDeviceVendor ?? "";
            RenderingServer.VideoAdapterName = SystemInfo.graphicsDeviceName ?? "";
            RenderingServer.VideoAdapterApiVersion = SystemInfo.graphicsDeviceVersion ?? "";
            try
            {
                _draws = ProfilerRecorder.StartNew(ProfilerCategory.Render, "Draw Calls Count");
                _tris = ProfilerRecorder.StartNew(ProfilerCategory.Render, "Triangles Count");
                _gfxMem = ProfilerRecorder.StartNew(ProfilerCategory.Memory, "Gfx Used Memory");
            }
            catch (Exception e) { Debug.LogWarning("Fatebound render stats: " + e.Message); }
            RenderingServer.MeasuredRenderTimeHook = (vp, gpu) => IsRoot(vp) ? 0.0 : (gpu ? _gpuMs : _cpuRenderMs);
            RenderingServer.RenderingInfoHook = info =>
            {
                switch (info)
                {
                    case RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME: return Last(_draws);
                    case RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME: return Last(_tris);
                    case RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED: return (long)Texture.currentTextureMemory;
                    case RenderingServer.RENDERING_INFO_VIDEO_MEM_USED: return Last(_gfxMem);
                }
                return 0;
            };
            RenderingServer.ViewportRenderInfoHook = (vp, type, info) =>
            {
                bool root = IsRoot(vp);
                if (type == RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS)
                    return !root ? 0 : info == RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME ? _canvasDrawsLast
                        : info == RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME ? _canvasPrimsLast : 0;
                if (type != RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE || root) return 0;
                // (the frame's, less the GUI's)
                switch (info)
                {
                    case RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME: return (int)Math.Max(0, Last(_draws) - _canvasDrawsLast);
                    case RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME: return (int)Math.Max(0, Last(_tris) - _canvasPrimsLast);
                }
                return 0;
            };
        }

        static bool IsRoot(RID vp) => _tree != null && vp.Id == _tree.Root.GetInstanceId();
        static long Last(ProfilerRecorder r) => r.Valid ? r.LastValue : 0;

        /// <summary>Once a frame, before the game's frame: the previous frames' timings.</summary>
        public static void Frame()
        {
            _canvasDrawsLast = CanvasDraws;
            _canvasPrimsLast = CanvasPrimitives;
            CanvasDraws = CanvasPrimitives = 0;
            FrameTimingManager.CaptureFrameTimings();
            if (FrameTimingManager.GetLatestTimings(1, _timings) > 0)
            {
                _gpuMs = _timings[0].gpuFrameTime;
                _cpuRenderMs = _timings[0].cpuRenderThreadFrameTime;
            }
        }
    }
}
