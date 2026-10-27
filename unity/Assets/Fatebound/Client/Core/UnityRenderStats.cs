// What Godot's RenderingServer reports about its frames (siege_diag.gd's STAT and SESSION lines, the match log Kevin
// sends back), answered from Unity:
//  - the adapter: SystemInfo's graphics device vendor / name / version
//  - viewport_get_measured_render_time_gpu / _cpu: Unity's FrameTimingManager (PlayerSettings.enableFrameTimingStats,
//    set by the build script). Unity times whole frames, not viewports: the 3D viewports get the frame's GPU time
//    and render-thread CPU time, the root (the GUI) 0 -- so "gpu3d" is the whole frame's graphics-chip time.
//  - draw calls and primitives: ProfilerRecorder's "Draw Calls Count" / "Triangles Count" for the frame (0 where a
//    player build doesn't record them), the root's canvas draws counted by CanvasDrawer; texture and video memory
//    from Texture.currentTextureMemory and "Gfx Used Memory". Pipeline compilations: Unity doesn't count them (0).
//  - (the port's own, RenderingServer.HostFrameTimes / HostStatText, after Kevin's first match log: ph_draw ~20 ms a
//    frame and never over 30 fps) the draw step's parts each frame -- d_sync (the worlds' changes to their Unity
//    objects), d_mat (changed materials), d_skin (skinned bodies' bones), d_mm (multimeshes), d_cam (the viewports'
//    cameras), d_part (particles), d_sweep, d_gui (the GUI's draw lists), d_rec (recording them) -- and Unity's own
//    main-thread times (u_main: the main thread's frame, u_wait: its wait for the present / render thread, the frame
//    cap's included; u_urp: URP rendering the cameras, after LateUpdate); on each STAT line the display's rate (hz, modes, target) and the garbage collector's
//    collections that second (gc) and allocations a frame (alloc, where the player counts them).
using System;
using System.Diagnostics;
using Debug = UnityEngine.Debug;
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

        // the draw step's parts (Lap: the time since `from` into a part)
        public const int SYNC = 0, MAT = 1, SKIN = 2, MM = 3, CAM = 4, PART = 5, SWEEP = 6, GUI = 7, REC = 8, URP = 9;
        static readonly string[] PARTS = { "d_sync", "d_mat", "d_skin", "d_mm", "d_cam", "d_part", "d_sweep", "d_gui", "d_rec", "u_urp" };
        static readonly long[] _part = new long[PARTS.Length], _partLast = new long[PARTS.Length];
        static readonly Stopwatch _clock = Stopwatch.StartNew();
        static readonly double _usPerTick = 1e6 / Stopwatch.Frequency;
        static double _mainMs, _waitMs;
        static ProfilerRecorder _alloc;
        static long _allocSum;
        static int _allocFrames, _gcLast = -1;
        static long _urpFrom;

        public static long Now => _clock.ElapsedTicks;

        public static long Lap(int part, long from)
        {
            long now = _clock.ElapsedTicks;
            _part[part] += now - from;
            return now;
        }

        public static void Install(SceneTree tree)
        {
            _tree = tree;
            try { _alloc = ProfilerRecorder.StartNew(ProfilerCategory.Memory, "GC Allocated In Frame"); }
            catch (Exception e) { Debug.LogWarning("Fatebound render stats (allocations): " + e.Message); }
            // URP's own rendering on the main thread (culling, its passes' setup and recording: after LateUpdate, so
            // after siege_diag's ph_draw, in its ph_other)
            RenderPipelineManager.beginContextRendering += (ctx, cams) => _urpFrom = Now;
            RenderPipelineManager.endContextRendering += (ctx, cams) => { if (_urpFrom != 0) Lap(URP, _urpFrom); _urpFrom = 0; };
            RenderingServer.HostFrameTimesHook = add =>
            {
                for (int i = 0; i < PARTS.Length; i++) add(PARTS[i], (long)(_partLast[i] * _usPerTick));
                add("u_main", (long)(_mainMs * 1000.0));
                add("u_wait", (long)(_waitMs * 1000.0));
            };
            RenderingServer.HostStatTextHook = () =>
            {
                int gc = GC.CollectionCount(0);
                string text = UnityPlatform.DisplayText() + " gc=" + (_gcLast < 0 ? 0 : gc - _gcLast);
                _gcLast = gc;
                if (_alloc.Valid && _allocFrames > 0) text += " alloc=" + (_allocSum / _allocFrames / 1024) + "KB";
                _allocSum = 0;
                _allocFrames = 0;
                return text;
            };
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
            for (int i = 0; i < _part.Length; i++) { _partLast[i] = _part[i]; _part[i] = 0; }
            if (_alloc.Valid) { _allocSum += _alloc.LastValue; _allocFrames++; }
            FrameTimingManager.CaptureFrameTimings();
            if (FrameTimingManager.GetLatestTimings(1, _timings) > 0)
            {
                _gpuMs = _timings[0].gpuFrameTime;
                _cpuRenderMs = _timings[0].cpuRenderThreadFrameTime;
                _mainMs = _timings[0].cpuMainThreadFrameTime;
                _waitMs = _timings[0].cpuMainThreadPresentWaitTime;
            }
        }
    }
}
