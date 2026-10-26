// Ported from godot/scripts/siege/siege_diag.gd (Fatebound 0.31.222).
using System;
using System.Collections;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Platform = Fatebound.Game.Platform;

namespace Fatebound.Game
{
    // Siege field diagnostics (alpha builds). Writes user://siege_diag.log, flushed every line so it
    // survives a freeze or force-close:
    //  - one stats line per second (fps, worst frame, memory, video memory, draw calls, objects, match state)
    //  - every engine/script error and warning, via an OS logger
    //  - a watchdog thread: if frames stop for >2 s it logs which phase the main thread was last in,
    //    which separates "stuck in game code" from "stuck in the renderer/driver".
    public class SiegeDiag : Node
    {
        public const string PATH = "user://siege_diag.log";
        public const string PREV_PATH = "user://siege_diag_prev.log";
        // 0.31.70: the app start has its own log (testers' phones stuck on a black screen right after the Godot splash),
        // so a match's diagnostics never push a stuck start out of the files.
        public const string BOOT_PATH = "user://boot_diag.log";
        public const string BOOT_PREV_PATH = "user://boot_diag_prev.log";
        // 0.31.91: the start that froze on Vulkan, kept when BootGuard switches to OpenGL (the two restarts after it used to
        // rotate it out of boot_diag_prev.log before anyone could copy it).
        public const string BOOT_STUCK_PATH = "user://boot_diag_stuck.log";
        public const string BUILD = "0.31.222-fatebound";

        public class ErrorCapture : Logger
        {
            public Action<string> sink;
            public override void _LogError(string function, string file, int line, string code, string rationale, bool _editor_notify, int error_type, GArray _bt)
            {
                sink(GD.Fmt("%s %s:%d %s %s %s", GArray.Of("ERROR", "WARNING", "SCRIPT", "SHADER")[GD.Clampi(error_type, 0, 3)], file.GetFile(), line, function, code, rationale));
            }

            public override void _LogMessage(string message, bool error)
            {
                if (error)
                    sink("STDERR " + message.StripEdges());
            }
        }

        public SiegeMode mode;  // siege_mode, for match state
        public string log_path = PATH;          // set before add_child (the app start uses BOOT_PATH / BOOT_PREV_PATH)
        public string prev_path = PREV_PATH;
        public FileAccess _file;
        public Mutex _mutex = new Mutex();
        public ErrorCapture _logger;
        public Thread _watchdog;
        public bool _quit = false;
        public string _phase = "start";
        public long _beat_ms = 0;
        public bool _stalled = false;
        public long _stall_at = 0;
        public double _second = 0.0;
        public double _worst_ms = 0.0;
        public long _last_frame_us = 0;
        public int _events = 0;
        public int _error_lines = 0;
        public string fps_text = "";            // (not shown since 0.31.163; the STAT lines carry it)
        public GDict _times = new GDict();   // label -> [total_us, max_us, count]

        public void AddTime(string label, long us)
        {
            GArray t = _times.Get(label, GArray.Of(0, 0, 0)).A;
            t[0] = t[0] + us;
            t[1] = GD.Maxi((long)t[1], us);
            t[2] = t[2] + 1;
            _times[label] = t;
        }

        public string _TimesText()
        {
            var parts = new List<string>();
            foreach (var k in _times)
            {
                GArray t = _times[k].A;
                parts.Add(GD.Fmt("%s=%.1f/%.1fms", k, (double)t[0] / 1000.0 / GD.Maxf(1, (double)t[2]), (double)t[1] / 1000.0));
            }
            _times.Clear();
            return string.Join(" ", parts);
        }

        // 0.31.161 (Kevin: "Add to log"): what the graphics chip spends -- its time on the 3D view (gpu3d) and on the screen
        // itself (gpuhud: the HUD and the 3D picture stretched onto it), and the CPU's time preparing the 3D view's draw
        // (rcpu3d: culling, building the draw lists) -- every frame, as mean/max on each STAT line beside sim/view/hud. The
        // engine's own per-pass timings (shadows, opaque, glow...) are only for its editor profiler, not a phone build.
        public RID _measured_vp = new RID();

        // 0.31.219: where each frame's time goes on the main thread -- ph_proc: every script's _process and _draw and the
        // engine's own per-node work (the animation players, the skeletons); ph_draw: the engine drawing the frame on the main
        // thread (culling, the draw lists, handing them to the graphics driver, waiting for it); ph_other: the rest till the
        // next frame (input, physics, the wait for the sim's ticks -- simwait -- and the 60 fps cap's sleep). The old proc= was
        // Performance's TIME_PROCESS: the WORST frame's process time in each second (not its mean) -- procmax= now.
        public long _ph_start = 0;
        public long _ph_pre = 0;
        public long _ph_post = 0;
        public GArray last_ph = GArray.Of(0, 0, 0);                  // 0.31.220: the last frame's ph_proc, ph_draw, ph_other in us (gpu_probe.gd)

        public void _OnProcessFrame()
        {
            var now = Time.GetTicksUsec();
            if (_ph_post > 0)
            {
                AddTime("ph_other", now - _ph_post);
                last_ph[2] = now - _ph_post;
            }
            _ph_start = now;
            _ph_pre = 0;
        }

        public void _OnPreDraw()
        {
            var now = Time.GetTicksUsec();
            if (_ph_start > 0)
            {
                AddTime("ph_proc", now - _ph_start);
                last_ph[0] = now - _ph_start;
            }
            _ph_pre = now;
        }

        public void _SampleRender()
        {
            if (mode == null || mode.viewport == null || !GD.IsInstanceValid(mode.viewport))
                return;
            RID v3 = mode.viewport.GetViewportRid();
            RID root = GetViewport().GetViewportRid();
            if (v3 != _measured_vp)
            {
                _measured_vp = v3;
                RenderingServer.ViewportSetMeasureRenderTime(v3, true);
                RenderingServer.ViewportSetMeasureRenderTime(root, true);
                return;
            }
            AddTime("gpu3d", GD.Int(RenderingServer.ViewportGetMeasuredRenderTimeGpu(v3) * 1000.0));
            AddTime("gpuhud", GD.Int(RenderingServer.ViewportGetMeasuredRenderTimeGpu(root) * 1000.0));
            AddTime("rcpu3d", GD.Int(RenderingServer.ViewportGetMeasuredRenderTimeCpu(v3) * 1000.0));
        }

        // 0.31.222 (Kevin's 0.31.221 log: a 2.3 s freeze in the training's last fight -- the 3D view's CPU time 2,256 ms, a
        // shader pipeline compiled on first use): the pipelines compiled in each second, by kind (canvas/mesh/surface/draw/
        // specialization), on every STAT line that had any -- which moment brought a new look the warm-up hadn't shown
        public static readonly GArray PSO_KINDS = GArray.Of(GArray.Of("c", RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS), GArray.Of("m", RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH),
            GArray.Of("s", RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE), GArray.Of("d", RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW),
            GArray.Of("sp", RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION));
        public GDict _pso_last = new GDict();

        public string _PsoText()
        {
            var parts = new List<string>();
            foreach (var k in PSO_KINDS)
            {
                var n = RenderingServer.GetRenderingInfo((int)k[1]);
                var d = n - (long)_pso_last.Get(k[0], n);
                _pso_last[k[0]] = n;
                if (d > 0)
                    parts.Add(GD.Fmt("%s%d", k[0], d));
            }
            return parts.Count != 0 ? "pso=" + string.Join("/", parts) : "";
        }

        public string _ViewportText()
        {
            // Draw calls/triangles split by the 3D SubViewport vs the HUD canvas.
            if (mode == null || mode.viewport == null)
                return "";
            RID v3 = mode.viewport.GetViewportRid();
            RID root = GetViewport().GetViewportRid();
            var I = RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE;
            var C = RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS;
            var D = RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME;
            var P = RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME;
            return GD.Fmt("3d_px=%dx%d 3d_draws=%d 3d_prims=%d 3d_shadow_prims=%d hud_draws=%d", mode.viewport.Size.x, mode.viewport.Size.y,
                RenderingServer.ViewportGetRenderInfo(v3, I, D), RenderingServer.ViewportGetRenderInfo(v3, I, P),
                RenderingServer.ViewportGetRenderInfo(v3, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, P),
                RenderingServer.ViewportGetRenderInfo(root, C, D));
        }

        public bool _started = false;

        protected override void _Ready()
        {
            StartEarly();
        }

        public void StartEarly()
        {
            // Normally from _ready; BootGuard calls it from its _init, before the main scene loads (0.31.72).
            if (_started)
                return;
            _started = true;
            // Keep the previous session's log (the one that froze) before starting a new one.
            if (FileAccess.FileExists(log_path))
            {
                DirAccess.RemoveAbsolute(ProjectSettings.GlobalizePath(prev_path));
                DirAccess.RenameAbsolute(ProjectSettings.GlobalizePath(log_path), ProjectSettings.GlobalizePath(prev_path));
            }
            _file = FileAccess.Open(log_path, FileAccess.WRITE);
            Write(GD.Fmt("SESSION %s | %s %s | %s | %s | GPU %s %s | renderer %s (%s)", Time.GetDatetimeStringFromSystem(), OS.GetName(), OS.GetVersion(),
                OS.GetModelName(), BUILD, RenderingServer.GetVideoAdapterVendor(), RenderingServer.GetVideoAdapterName(),
                RenderingServer.GetCurrentRenderingMethod(), RenderingServer.GetVideoAdapterApiVersion()));
            _logger = new ErrorCapture();
            _logger.sink = (string line) =>
            {
                _error_lines += 1;
                if (_error_lines <= 400)
                    Write(line);
            };
            OS.AddLogger(_logger);
            _beat_ms = Time.GetTicksMsec();
            RenderingServer.FramePostDraw += _OnFrameDrawn;
            if (mode != null)
            {
                RenderingServer.FramePreDraw += _OnPreDraw;
                var tree = Engine.GetMainLoop() as SceneTree;
                if (tree != null)
                    tree.ProcessFrame += _OnProcessFrame;
            }
            _watchdog = new Thread();
            _watchdog.Start(_Watch);
        }

        protected override void _ExitTree()
        {
            _mutex.Lock();
            _quit = true;
            _mutex.Unlock();
            if (_watchdog != null && _watchdog.IsStarted())
                _watchdog.WaitToFinish();
            // (is_connected / disconnect: removing a handler that isn't connected does nothing)
            RenderingServer.FramePostDraw -= _OnFrameDrawn;
            RenderingServer.FramePreDraw -= _OnPreDraw;
            var tree = Engine.GetMainLoop() as SceneTree;
            if (tree != null)
                tree.ProcessFrame -= _OnProcessFrame;
            if (_measured_vp.IsValid() && IsInsideTree())
                RenderingServer.ViewportSetMeasureRenderTime(GetViewport().GetViewportRid(), false);
            if (_logger != null)
                OS.RemoveLogger(_logger);
            Write("SESSION END");
        }

        public bool _writing = false;

        public void Write(string line)
        {
            _mutex.Lock();
            if (_file != null && !_writing)
            {
                _writing = true;
                _file.StoreLine(GD.Fmt("%8.2f %s", Time.GetTicksMsec() / 1000.0, line));
                _file.Flush();
                _writing = false;
            }
            _mutex.Unlock();
        }

        public void Mark(string phase)
        {
            // Breadcrumb for the watchdog: the last phase the main thread entered.
            _mutex.Lock();
            _phase = phase;
            _mutex.Unlock();
        }

        public GDict _ev_kinds = new GDict();                       // 0.31.222: this second's event kinds (written with a pipeline compile)

        public void Event(Ev e = null)
        {
            _events += 1;
            if (e != null && e.Count != 0 && _ev_kinds.Size() < 24)
            {
                var k = e.TryGetValue("k", out var kv) ? V.Str(kv) : "?";
                foreach (var f in new[] { "spell", "ult", "kind" })
                {
                    if (e.Has(f))
                    {
                        k += "/" + V.Str(e[f]);
                        break;
                    }
                }
                _ev_kinds[k] = true;
            }
        }

        public void _CaptureLogcat(string label)
        {
            Write(GD.Fmt("LOGCAT BEGIN (%s)", label));
            var t0 = Time.GetTicksMsec();
            var text = LogcatTail(60);
            foreach (var line in text.Split("\n", false))
                Write("LOGCAT " + line);
            Write(GD.Fmt("LOGCAT END (%d ms)", Time.GetTicksMsec() - t0));
        }

        public void _OnFrameDrawn()
        {
            // If a stall's last phase is "frame drawn" or "hud draw", the main thread finished our code and
            // hung inside rendering/the GPU driver rather than in game logic.
            Mark("frame drawn");
            var now = Time.GetTicksUsec();
            if (_ph_pre > 0 && mode != null)
            {
                AddTime("ph_draw", now - _ph_pre);
                last_ph[1] = now - _ph_pre;
            }
            _ph_post = mode != null ? now : 0;
        }

        public void _Watch()
        {
            while (true)
            {
                OS.DelayMsec(250);
                _mutex.Lock();
                var quit = _quit;
                var since = Time.GetTicksMsec() - _beat_ms;
                var phase = _phase;
                _mutex.Unlock();
                if (quit)
                    return;
                if (since > 2000 && !_stalled)
                {
                    _stalled = true;
                    _stall_at = Time.GetTicksMsec();
                    Write(GD.Fmt("STALL no frame for %d ms; main thread last in: %s", since, phase));
                    _CaptureLogcat("at stall");
                }
                else if (since > 2000 && Time.GetTicksMsec() - _stall_at > 5000)
                {
                    _stall_at = Time.GetTicksMsec();
                    Write(GD.Fmt("STILL STALLED %d ms; last phase: %s", since, phase));
                    if (since > 6000 && since < 12000)
                        _CaptureLogcat("6 s into stall");
                }
                else if (since <= 2000 && _stalled)
                {
                    _stalled = false;
                    Write("RECOVERED");
                }
            }
        }

        // (mode.view's _fx / _ragdolls / _debris: their size, whichever list type the view keeps them in)
        static int _Count(object o) => o is GArray ga ? ga.Size() : (o is ICollection c ? c.Count : 0);

        protected override void _Process(double delta)
        {
            _mutex.Lock();
            _beat_ms = Time.GetTicksMsec();
            _mutex.Unlock();
            _SampleRender();
            var now = Time.GetTicksUsec();
            if (_last_frame_us > 0)
                _worst_ms = GD.Maxf(_worst_ms, (now - _last_frame_us) / 1000.0);
            _last_frame_us = now;
            _second += delta;
            if (_second < 1.0)
                return;
            _second = 0.0;
            var vmem = Performance.GetMonitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0;
            var smem = Performance.GetMonitor(Performance.MEMORY_STATIC) / 1048576.0;
            var fps = Engine.GetFramesPerSecond();
            fps_text = GD.Fmt("%d fps · %d MB · %d vMB", fps, GD.Int(smem), GD.Int(vmem));
            var state = "";
            if (mode != null && mode.sim != null)
            {
                var s = mode.sim;
                Unit me = s.by_id.TryGetValue("you", out var mu) ? mu : null;
                state = GD.Fmt("t=%.0f score=%s kills=%s me=%s/%s hp=%.0f carry=%s fx=%d proj=%d rag=%d loose=%d units=%d", s.time, GD.Str(GArray.From(s.score)), GD.Str(GArray.From(s.kills)),
                    me != null ? me.cls : "?", me != null ? me.state : "?", me != null ? me.hp : 0.0, me != null ? Var.Of(me.Get("carrying") ?? false) : false,
                    mode.view != null ? _Count(mode.view._fx) : -1, s.projectiles.Count,
                    mode.view != null ? _Count(mode.view._ragdolls) : -1, mode.view != null ? _Count(mode.view._debris) : -1, s.units.Count);
            }
            var pso = _PsoText();
            if (pso != "")
                state = pso + " ev=" + GStr.Join(",", _ev_kinds.Keys()) + " " + state;
            _ev_kinds.Clear();
            Write(GD.Fmt("STAT fps=%d worst=%.0fms %s %s procmax=%.1fms physmax=%.1fms mem=%.1fMB vmem=%.1fMB tex=%.1fMB draws=%d prims=%d objs=%d nodes=%d ev=%d %s", fps, _worst_ms, _TimesText(), _ViewportText(),
                Performance.GetMonitor(Performance.TIME_PROCESS) * 1000.0, Performance.GetMonitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, smem, vmem,
                Performance.GetMonitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
                Performance.GetMonitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.GetMonitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
                Performance.GetMonitor(Performance.OBJECT_COUNT), Performance.GetMonitor(Performance.OBJECT_NODE_COUNT), _events, state));
            _worst_ms = 0.0;
            _events = 0;
            _PartsSecond();
        }

        // 0.31.219: one second in every ten, the sim's, the view's and the HUD's own parts timed (their prof dictionaries:
        // tests/moba_bench.gd's breakdown) and written as a PARTS line in ms a frame -- which part to cut, measured on the phone.
        // (Off the other nine: the view's are per body, a few hundred clock reads a frame.)
        public int _parts_n = 0;
        public long _parts_from = 0;
        public bool _parts_mine = false;
        // (the C# sim (Fatebound.Sim.SiegeSim) has no `profile` / `prof`: its phases aren't timed, so the PARTS line's
        // "sim:" part stays empty -- this stands in for mode.sim.prof)
        public GDict _sim_prof = new GDict();

        public void _PartsSecond()
        {
            if (mode == null || mode.sim == null || !GD.IsInstanceValid(mode.view) || !GD.IsInstanceValid(mode.hud))
                return;
            _parts_n += 1;
            if (_parts_n % 10 == 9 && !mode.view.prof_on)      // (not while a bench has them on)
            {
                _parts_mine = true;
                // (mode.sim.profile = true: see _sim_prof)
                _sim_prof = new GDict();
                mode.view.prof_on = true;
                mode.view.prof = new GDict();
                mode.hud.prof_on = true;
                mode.hud.prof = new GDict();
                _parts_from = Engine.GetProcessFrames();
            }
            else if (_parts_mine)
            {
                _parts_mine = false;
                var frames = GD.Maxi(1, Engine.GetProcessFrames() - _parts_from);
                var o = new List<string>();
                foreach (var pr in GArray.Of(GArray.Of("sim", _sim_prof), GArray.Of("view", mode.view.prof), GArray.Of("hud", mode.hud.prof)))
                {
                    GDict pd = pr[1].D;
                    GArray keys = pd.Keys();
                    keys.SortCustom((x, y) => (int)pd[x] > (int)pd[y]);
                    var t = new List<string>();
                    foreach (var k in keys)
                        t.Add(GD.Fmt("%s=%.2f", k, (double)pd[k] / 1000.0 / frames));
                    o.Add(GD.Fmt("%s: %s", pr[0], string.Join(" ", t)));
                }
                Write(GD.Fmt("PARTS (ms a frame, %d frames) %s", frames, string.Join(" | ", o)));
                // (mode.sim.profile = false)
                mode.view.prof_on = false;
                mode.hud.prof_on = false;
            }
        }

        // Android log capture. Only warnings and above (*:W) from the main, system and crash buffers, so
        // window/touch chatter (VRI, InsetsController, ... all Info/Debug) can't crowd out a crash report.
        // Native crash reports are F/DEBUG + F/libc; GPU driver errors are E/Adreno*, E/kgsl.
        public static readonly string[] LOGCAT_NOISE = { "InsetsController", "VRI[", "BLASTBuffer", "SurfaceView", "GestureDetector", "RegularContextFactory" };

        public static GArray _LogcatRun(GArray buffers)
        {
            var args = new List<string> { "-d", "-v", "time" };
            foreach (var b in buffers)
                args.AddRange(new[] { "-b", b.AsString() });
            args.Add("*:W");
            var o = new GArray();
            var err = OS.Execute("/system/bin/logcat", args.ToArray(), o, true);
            return GArray.Of(err, !o.IsEmpty() ? GD.Str(o[0]) : "");
        }

        public static string LogcatTail(int keep_other = 120)
        {
            if (!Platform.IsAndroid())
                return "";
            var r = _LogcatRun(GArray.Of("main", "system", "crash"));
            if ((int)r[0] != GD.OK || GD.Str(r[1]).StripEdges() == "" || GD.Str(r[1]).Contains("Unable to open"))
                r = _LogcatRun(GArray.Of("main", "system"));
            if ((int)r[0] != GD.OK)
                return GD.Fmt("logcat unavailable (error %d)", (int)r[0]);
            return FilterLogcat(GD.Str(r[1]), keep_other);
        }

        public static string FilterLogcat(string raw, int keep_other = 120)
        {
            var fatal = new List<string>();
            var other = new List<string>();
            foreach (var line in raw.Split("\n", false))
            {
                var l = line.StripEdges();
                if (l == "" || l.BeginsWith("---------"))
                    continue;
                var noisy = false;
                foreach (var n in LOGCAT_NOISE)
                {
                    if (l.Contains(n))
                    {
                        noisy = true;
                        break;
                    }
                }
                if (noisy)
                    continue;
                // Every fatal line (crash header, signal, abort message, full backtrace) is kept.
                if (l.Contains(" F/") || l.Contains("F/DEBUG") || l.Contains("F/libc") || l.Contains("Fatal signal") || l.Contains("Abort message"))
                    fatal.Add(l);
                else
                    other.Add(l);
            }
            if (fatal.Count > 400)
                fatal = fatal.GetRange(fatal.Count - 400, 400);
            if (other.Count > keep_other)
                other = other.GetRange(other.Count - keep_other, keep_other);
            return GD.Fmt("-- fatal (%d) --\n%s\n-- errors/warnings (last %d) --\n%s", fatal.Count, string.Join("\n", fatal), other.Count, string.Join("\n", other));
        }

        public static bool HasLogs()
        {
            foreach (var p in new[] { PATH, PREV_PATH, BOOT_PATH, BOOT_PREV_PATH, BOOT_STUCK_PATH })
            {
                if (FileAccess.FileExists(p))
                    return true;
            }
            return false;
        }

        public static string ReadLogs(int tail = 120)
        {
            // Both sessions (older first), each trimmed to its session header, every STALL/ERROR line and
            // the last `tail` lines, so it pastes into a chat in one piece.
            var o = "";
            foreach (var p in new[] { BOOT_STUCK_PATH, BOOT_PREV_PATH, BOOT_PATH, PREV_PATH, PATH })
            {
                if (!FileAccess.FileExists(p))
                    continue;
                var lines = FileAccess.GetFileAsString(p).Split("\n", false);
                var keep = new List<string>();
                for (int i = 0; i < lines.Length; i++)
                {
                    string l = lines[i];
                    // (0.31.220: and every PROBE line -- the graphics test runs early in a match, before the tail)
                    if (i == 0 || i >= lines.Length - tail || l.Contains("STALL") || l.Contains("ERROR") || l.Contains("RECOVERED") || l.Contains("SESSION") || l.Contains("BOOT")
                            || l.Contains("PROBE"))
                        keep.Add(l);
                }
                o += GD.Fmt("==== %s (%d lines) ====\n%s\n", p.GetFile(), lines.Length, string.Join("\n", keep));
            }
            var lc = LogcatTail(120);
            if (lc != "")
                o += GD.Fmt("==== logcat (this app, warnings+, crash buffer) ====\n%s\n", lc);
            return o;
        }
    }
}
