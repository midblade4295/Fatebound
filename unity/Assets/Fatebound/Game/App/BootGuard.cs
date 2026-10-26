// Ported from godot/scripts/app/boot_guard.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Diag = Fatebound.Game.SiegeDiag;
using Platform = Fatebound.Game.Platform;

namespace Fatebound.Game
{
    // BootGuard (autoload, 0.31.72; Vulkan only since 0.31.92). Watches the app start on the phone.
    //
    // 0.31.92 (Kevin: "Vulkan now works. I'd like to remove the OpenGL version"): the OpenGL (Compatibility) renderer is
    // gone. Godot's own fallback is off (rendering_device/fallback_to_opengl3=false, so the Android manifest requires
    // Vulkan 1.1 and Play doesn't offer the game to phones without it), project.godot no longer reads user://renderer.cfg,
    // and this guard no longer switches renderers. The freezes the switch was for were the 0.31.91 preload deadlock.
    //
    // What it still does: each start is marked pending until the menu has drawn OK_FRAMES frames. If the last start never
    // got there, this start is a SAFE START (no background model loading, no live 3D heroes; SiegeApp reads safe_boot)
    // and the frozen start's log is kept as user://boot_diag_stuck.log for COPY DIAGNOSTICS. It is an autoload so its
    // _init runs before the main scene loads: the start-up log (user://boot_diag.log, Diag) covers the main scene's
    // loading too. Only tracks on Android (or with the FB_BOOT_GUARD env var, for testing on desktop).
    public class BootGuard : Node
    {
        public const string STATE = "user://boot_state.json";
        public const string OLD_RENDERER_CFG = "user://renderer.cfg";   // 0.31.72-0.31.91's OpenGL switch; deleted, no longer read
        public const int OK_FRAMES = 30;

        public bool tracking = false;
        public bool safe_boot = false;
        public Diag diag = null;
        public long _t0 = 0;
        public int _frames = 0;
        public bool _done = false;
        public bool _held = false;

        public static GDict Decide(GDict prev, string build)
        {
            // What this start does, from the last start's record. Pure (tests/boot_guard_test.gd).
            var stuck = (bool)prev.Get("pending", false);
            return new GDict { { "stuck", stuck }, { "safe", stuck || GD.Str(prev.Get("safe_build", "")) == build } };
        }

        public BootGuard()
        {
            Name = "BootGuard";
            _t0 = Time.GetTicksMsec();
            tracking = Platform.TracksBoot() || OS.HasEnvironment("FB_BOOT_GUARD");     // (0.31.130: iOS too)
            diag = new Diag();
            diag.log_path = Diag.BOOT_PATH;
            diag.prev_path = Diag.BOOT_PREV_PATH;
            diag.StartEarly();
            AddChild(diag);
            diag.Write(GD.Fmt("BOOT guard up: renderer %s", RenderingServer.GetCurrentRenderingMethod()));
            diag.Write(GD.Fmt("BOOT %s", PipelineCacheNote()));
            if (!tracking)
                return;
            if (FileAccess.FileExists(OLD_RENDERER_CFG))
            {
                DirAccess.RemoveAbsolute(ProjectSettings.GlobalizePath(OLD_RENDERER_CFG));
                diag.Write("BOOT removed the old OpenGL switch file");
            }
            var prev = _ReadState();
            var d = Decide(prev, Diag.BUILD);
            if ((bool)d["stuck"])
                _KeepStuckLog();
            safe_boot = (bool)d["safe"];
            _WriteState(new GDict { { "pending", true }, { "build", Diag.BUILD }, { "safe_build", safe_boot ? Diag.BUILD : "" } });
            diag.Write(GD.Fmt("BOOT %s (last start %s)", safe_boot ? "SAFE START" : "normal",
                (bool)d["stuck"] ? "never reached the menu" : "ok"));
        }

        public static string PipelineCacheNote()
        {
            // 0.31.142: the graphics driver's compiled pipelines, kept by Godot in user://vulkan. Godot wrote them only every
            // 3 MB of new pipelines or when the app quits -- and a phone's app is killed, not quit -- so every start compiled
            // Home's ~45 pipelines again (its first frame: 4.5-4.8 s on Kevin's S21). project.godot now saves every 0.1 MB.
            var d = DirAccess.Open("user://vulkan");
            if (d == null)
                return "pipeline cache: none yet";
            var parts = new GArray();
            foreach (var f in d.GetFiles())
            {
                var fa = FileAccess.Open("user://vulkan".PathJoin(f), FileAccess.READ);
                parts.Append(GD.Fmt("%s %.2f MB", f, (fa != null ? fa.GetLength() : 0) / 1048576.0));
            }
            return "pipeline cache: " + (!parts.IsEmpty() ? GStr.Join(", ", parts) : "none yet");
        }

        public void _KeepStuckLog()
        {
            // The frozen start's log is boot_diag_prev.log right now; the next start would push it out, so keep a copy for
            // COPY DIAGNOSTICS (Diag.BOOT_STUCK_PATH).
            if (FileAccess.FileExists(Diag.BOOT_PREV_PATH))
                DirAccess.CopyAbsolute(ProjectSettings.GlobalizePath(Diag.BOOT_PREV_PATH), ProjectSettings.GlobalizePath(Diag.BOOT_STUCK_PATH));
        }

        public void Mark(string phase)
        {
            if (diag != null && GD.IsInstanceValid(diag))
            {
                diag.Mark(phase);
                diag.Write(GD.Fmt("BOOT %s (%d ms)", phase, Time.GetTicksMsec() - _t0));
            }
        }

        public void Hold(bool on)
        {
            // 0.31.95: while the content loader downloads the game's packs nothing counts -- the start is not pending (closing
            // the app mid-download is not a frozen start), and the frame count starts again when the game loads.
            _held = on;
            _frames = 0;
            if (tracking && !_done)
                _WriteState(new GDict { { "pending", !on }, { "build", Diag.BUILD }, { "safe_build", safe_boot ? Diag.BUILD : "" } });
            Mark(GD.Fmt("content download %s", on ? "started" : "done"));
        }

        public void WaitForGame(bool on)
        {
            // 0.31.141: the title screen is up while the game loads on a thread behind it -- its frames are not the menu's, so
            // none count (the start stays pending) until the game is in.
            _held = on;
            _frames = 0;
            Mark(on ? "title up, the game loading behind it" : "the game in, behind the title");
        }

        protected override void _Process(double _delta)
        {
            // Frames drawn with the menu up; at OK_FRAMES the start counts as good.
            if (_done || _held)
                return;
            _frames += 1;
            if (_frames == 1)
                Mark("first frame");
            if (_frames >= OK_FRAMES)
            {
                _done = true;
                SetProcess(false);
                if (tracking)
                    _WriteState(new GDict { { "pending", false }, { "build", Diag.BUILD }, { "safe_build", safe_boot ? Diag.BUILD : "" } });
                Mark(GD.Fmt("OK -- menu up%s", safe_boot ? " (safe start)" : ""));
                if (OS.HasEnvironment("FB_QUIT_WHEN_UP"))          // (tools/content_e2e.sh: quit once the menu's models are in)
                    _QuitWhenLoaded();
                var d = diag;
                GetTree().CreateTimer(8.0).Timeout += () =>         // a few seconds of menu stats, then stop logging
                {
                    if (GD.IsInstanceValid(d))
                        d.QueueFree();
                };
            }
        }

        public GDict _ReadState()
        {
            if (FileAccess.FileExists(STATE))
            {
                Var parsed = JSON.ParseString(FileAccess.GetFileAsString(STATE));
                if (parsed.IsDict)
                    return parsed.D;
            }
            return new GDict();
        }

        public void _WriteState(GDict st)
        {
            var f = FileAccess.Open(STATE, FileAccess.WRITE);
            if (f != null)
            {
                f.StoreString(JSON.Stringify(st));
                f.Close();
            }
        }

        public async void _QuitWhenLoaded()
        {
            try
            {
                // (load("res://scripts/siege/asset_cache.gd"): the script's static functions -- AssetCache in C#)
                while (AssetCache.Pending() > 0)
                    await Await.Timer(0.5);
                Mark("all preloaded");
                GD.Print("BOOT all preloaded");
                GetTree().Quit();
            }
            catch (Exception e) { GD.PushError(e.ToString()); }
        }
    }
}
