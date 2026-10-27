// Ported from godot/scripts/siege/siege_mode.gd (Fatebound 0.31.222).
// The .gd in two partial files, each in the .gd's order: SiegeMode.cs (the match: fields, the async sim, start-up,
// vibration, titles and quests, online play, input and actions, the warm-up, the frame, the tutorial, leaving) and
// SiegeMode.Sound.cs (the match's sound, the Herald, the announcements, quick chat).
//
// Events: the sim drains Fatebound.Sim.Ev records and the online snapshots carry Dictionaries. The HUD, the kill banners,
// the diag, the sounds and the training read Ev; the view's on_event (SiegeView.OnEvent) takes the Dictionary -- each event
// is handed to each in the form it reads (SiegeNet.ToEv / SiegeNet.WireEvent).
using System;
using System.Collections;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector2i = Fatebound.Sim.Vec2i;
using Vector3 = Fatebound.Sim.Vec3;
using Color = Fatebound.GUI.Col;

namespace Fatebound.Game
{
    using Sim = Fatebound.Sim.SiegeSim;
    using Land = Fatebound.Sim.Land;
    using Keep = Fatebound.Sim.Keep;
    using View = Fatebound.Game.SiegeView;
    using Hud = Fatebound.Game.SiegeHud;
    using Diag = Fatebound.Game.SiegeDiag;
    using Net = Fatebound.Game.SiegeNet;
    using Eco = Fatebound.Game.Economy;
    using Loading = Fatebound.Game.LoadingScreen;   // 0.31.208: the lobby and the loading card, one screen
    using Moba = Fatebound.Sim.Moba;

    // Offline Siege match: you plus bots. Owns the simulation, steps it at a fixed rate, and feeds the
    // 3D view and HUD. Emits `exited` when the player leaves.
    public partial class SiegeMode : Control
    {
        public event Action Exited;
        // 0.31.73: the server refused our protocol. verdict "update" (server newer: this build is too old -> the app shows
        // the blocking Update screen) or "server_old" (server older: "Servers are updating"). See Net.version_verdict.
        public event Action<int, string> VersionMismatch;

        public int team_size = 16;
        public string moba_hero = "";            // 0.31.155 5V5 (the test): your hero; a 5v5 against bots, offline (scripts/siege/moba.gd)
        public long match_seed = -1;           // (benchmarks: a fixed match; -1 the clock's)
        public Analytics analytics = null;          // 0.31.118: usage statistics (scripts/meta/analytics.gd): VS BOTS matches and the tutorial
        public string _an_match = "";           //   (the server counts online matches itself)
        public string _an_class0 = "";
        public const int TUTORIAL_GOLD = 250;
        // 3D resolution as a fraction of the PHYSICAL screen (window pixels, not logical UI units).
        // 0.31.163 (Kevin: "lock it to 30fps and 50% resolution. Remove settings so players don't see"): locked at 50 % -- on his
        // S21 Ultra the graphics chip took ~22 ms a frame there against ~36 at 75 % and ~46 at 100 %, and only 50 % held 30 fps.
        // No RESOLUTION button any more, no heat guard stepping it (set_render_scale stays for the benches).
        public const double RENDER_SCALE = 0.5;
        public double render_scale = RENDER_SCALE;
        public const int FPS_CAP = 60;         // 0.31.218 (Kevin, after the triangles were cut: "Honor of kings gives me 120fps solid"): 60 (30
                                               // since Round 32, 60 for one test build in 0.31.162) -- the sim still ticks at 30 Hz; the
                                               // view eases each body between its ticks
        public int _prev_max_fps = 0;
        public int _prev_physics_tps = 60;
        public int fps_cap = FPS_CAP;
        public bool low_fx = false;
        public bool hq_gfx = true;          // High-quality graphics (Settings): shadows, glow, smoother edges
        public string replay_hero = "";       // 0.31.164: PLAY AGAIN after a 5v5 -- siege_app starts the next one (with its own ticket)
        public bool tutorial = false;       // 0.31.181: the tutorial (0.31.217: the training, scripts/siege/training.gd -- Kael the
        public Training tutorial_ui = null;      //   Dragoon at your side; the app's start_training); no ticket, no match rewards -- its own gold once
        public int training = 1;           // 0.31.217: which -- 1 the basics (a quiet Rift), 2 the 5v5 battle (a real match, Kael beside you)
        public bool _tut_done = false;
        public long _tut_t0 = 0;
        public NativeAudio audio = null;
        public Profile profile = null;       // scripts/meta/profile.gd — rewards, challenges and cosmetics
        public GDict rewards = new GDict();
        public GDict match_result = new GDict();
        // 0.31.87 (titles): what the match counts toward them, gathered here so offline and online count the same way
        public GDict _cls_time = new GDict();      // class -> seconds played as it (alive; the upgrade counts as its class)
        public GDict _kills_cls = new GDict();     // class -> knockouts made as it
        public int _kills_seen = 0;
        public int _best_multi = 0;     // most knockouts in one burst ("multikill" events)
        // 0.31.97 (class quests): the same, per class as worn -- a Crusader apart from a Knight (Eco.cosmetic_class)
        public static readonly GDict Q_UNIT = GDict.Of("kills", "kills", "gate_dmg", "gate_dmg", "healed", "healed",
            "towers", "towers", "camps", "camps", "lh", "lh", "epics", "epics");       // (0.31.164: the 5v5's, moba.gd counts them on the hero)
        public GDict _q = new GDict();             // worn class -> {"t": seconds, "kills", "gate_dmg", "healed", "best_multi", "towers", "camps", "lh", "epics"}
        public GDict _q_seen = new GDict();        // my unit's running totals already credited
        public string _q_cls = "";         // the class I wear right now ("" = none)

        // Online play (set before adding to the tree). The server runs the match; this client mirrors it.
        public bool online = false;
        // SIEGE_URL overrides the server for desktop testing (e.g. ws://127.0.0.1:8082/fatebound/siege/ws).
        public string net_url = OS.HasEnvironment("SIEGE_URL") ? OS.GetEnvironment("SIEGE_URL") : Net.DEFAULT_URL;
        public string player_name = "Player";
        public WebSocketPeer ws = null;
        public string net_state = "";                  // "connecting", "waiting", "playing", "closed"
        public int net_match = -1;
        public string net_verdict = "";               // 0.31.73: "update" / "server_old" after a version refusal
        public int net_server_version = -1;        // the server's protocol from that refusal
        public GDict _net_bye = new GDict();
        public double _net_closing_since = -1.0;
        public bool _me_bot = false;                // 0.31.119: the server says a bot plays my unit (I was idle): no prediction
        // 0.31.120 (Kevin: rejoin after a dropped connection): the server's token for my seat ("rj" in the welcome). When the
        // connection drops mid-match the game keeps the match on screen and reconnects quietly every REJOIN_EVERY s for up to
        // REJOIN_FOR s with a hello carrying the token; the server puts me straight back on my unit (welcome "rejoin").
        public const double REJOIN_FOR = 55.0;
        public const double REJOIN_EVERY = 2.0;
        public double rejoin_for = REJOIN_FOR;        // (tests shorten it)
        public string _rj = "";
        public double _rejoin_until = -1.0;
        public double _rejoin_at = 0.0;
        public bool _rejoin_sent = false;
        public int rejoins = 0;                    // (tests, diag)
        public int again_sent = 0;                 // 0.31.122: PLAY AGAIN presses sent to the server (tests)
        public string party_join = "";                // 0.31.120: a friend's public id: their match is the one to join (Friends > JOIN)
        public string exit_note = "";                 // 0.31.119: why the match ended for me, for Home to say (removed for being idle)
        public const string MSG_UPDATE = "A new version of Fatebound is available. Update to keep playing.";
        public const string MSG_SERVER_OLD = "Servers are updating, try again in a few minutes";
        public double _net_started = 0.0;
        public double _snap_t = 0.0;
        public double _net_rt = -1.0;                 // 0.31.23: the render clock (server seconds) remote units are drawn at
        public double _net_latest = 0.0;              // the newest snapshot's server time
        public double _net_delay = Net.INTERP_DELAY;  // 0.31.24: the draw delay in use (grows with jitter, up to 250 ms)
        public double _net_jitter = 0.0;              // smoothed |arrival gap - snapshot interval|
        public double _net_rx_last = 0.0;
        public GDict _pred_fx = new GDict();                  // ability effects shown ahead of the server, by kind: time
        public double _snap_dt = 1.0 / Net.SNAP_HZ;
        public double _send_clock = 0.0;
        public Vector2 _sent_move = new Vector2(GD.INF, GD.INF);
        public bool _sent_hold = false;
        public bool _sent_bhold = false;
        public LoadingScreen lobby = null;           // 0.31.82: the join countdown, from PLAY until the welcome
        public int lobby_msgs = 0;                 // "lobby" messages received (tests)
        public GDict net_names = new GDict();                 // unit id -> name of each live player in the match (0.31.86, the server's "pn")
        public GDict net_titles = new GDict();                // unit id -> their title id (0.31.87, the "pn" message's "tt")
        public GDict net_looks = new GDict();                 // unit id -> their looks ({"_sk": the outfits}): what they wear (0.31.101, "pn" "lk")
        public GDict net_tags = new GDict();                  // unit id -> clan tag (0.31.134, "pn" "ct")
        public string clan_tag = "";                  // 0.31.134: the player's own clan tag (set by the app; shown on your plate)
        public string clan_crest = "";                // 0.31.196: ... and crest
        public GDict net_crests = new GDict();                // 0.31.196: unit id -> clan crest code ("pn" "cc")

        public SiegeSim sim;
        public SiegeView view;
        public SiegeHud hud;
        public SubViewport viewport;
        public SiegeDiag diag;
        public double _accum = 0.0;
        public bool _result_shown = false;

        // 0.31.219 (Kevin's 0.31.218 log: 23 fps in a 5v5; the phone's CPU the limit -- the sim's ticks ~11 ms a frame, the
        // view's ~8, the HUD's ~6, and the engine's own drawing on top): the sim's ticks run on a worker thread while the
        // engine draws the frame -- launched when the drawing starts (RenderingServer.frame_pre_draw: every script's _process
        // and _draw is done by then) and waited for when it ends (frame_post_draw: before the next frame's input, physics or
        // scripts can touch the sim). Nothing else runs in that window but the engine's own C++ (culling, the draw lists, the
        // graphics driver), and the sim touches nothing of the engine's, so the two never meet. The view shows the ticks a
        // frame later (they are eased between anyway); the events come the frame after too. Headless no frame is drawn: the
        // ticks run in _process as before (and with FB_SIM_SYNC set).
        public bool async_sim = DisplayServer.GetName() != "headless" && !OS.HasEnvironment("FB_SIM_SYNC");
        public int _sim_due = 0;                     // ticks to run while this frame is drawn
        public long _sim_task = -1;                   // the WorkerThreadPool task running them
        public long _sim_task_us = 0;                 // its own time (the diag's "sim"; "simwait": the main thread's wait for it)
        public bool sim_hooked = false;
        public GpuProbe probe = null;
        public Control vignette = null;
        public int sim_tasks = 0;                    // (tests: tasks launched, and the thread the last one ran on)
        public long sim_task_thread = 0;

        public void _SimHook(bool on)
        {
            if (on == sim_hooked)
                return;
            sim_hooked = on;
            if (on)
            {
                RenderingServer.FramePreDraw += _SimLaunch;
                RenderingServer.FramePostDraw += SimJoin;
            }
            else
            {
                // (is_connected / disconnect: removing a handler that isn't connected does nothing)
                RenderingServer.FramePreDraw -= _SimLaunch;
                RenderingServer.FramePostDraw -= SimJoin;
            }
        }

        public void _SimLaunch()
        {
            if (_sim_due <= 0 || sim == null || _sim_task >= 0 || !IsInsideTree())
                return;
            var n = _sim_due;
            _sim_due = 0;
            var s = sim;
            _sim_task = WorkerThreadPool.AddTask(() => _SimRun(s, n), true, "sim ticks");
            sim_tasks += 1;
        }

        public void _SimRun(SiegeSim s, int n)
        {
            var t0 = Time.GetTicksUsec();
            sim_task_thread = OS.GetThreadCallerId();
            for (int i = 0; i < n; i++)
                s.Step(Sim.TICK);
            _sim_task_us = Time.GetTicksUsec() - t0;
        }

        public void SimJoin()
        {
            // the ticks launched for this frame done (and any a frame without drawing left due: run here)
            if (_sim_task >= 0)
            {
                var tw = Time.GetTicksUsec();
                WorkerThreadPool.WaitForTaskCompletion(_sim_task);
                _sim_task = -1;
                if (diag != null)
                {
                    diag.AddTime("sim", _sim_task_us);
                    diag.AddTime("simwait", Time.GetTicksUsec() - tw);
                }
            }
            if (_sim_due > 0 && sim != null)
            {
                var n = _sim_due;
                _sim_due = 0;
                var t0 = Time.GetTicksUsec();
                for (int i = 0; i < n; i++)
                    sim.Step(Sim.TICK);
                if (diag != null)
                    diag.AddTime("sim", Time.GetTicksUsec() - t0);
            }
        }

        public static GDict ready_times = new GDict();      // ms per start-up step of the last match (diag / tools)

        protected override void _Ready()
        {
            ready_times = new GDict();
            var t_ready = Time.GetTicksMsec();
            SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            MouseFilter = Control.MOUSE_FILTER_STOP;
            ClipContents = true;
            diag = new Diag();
            diag.mode = this;
            AddChild(diag);
            ready_times["diag"] = Time.GetTicksMsec() - t_ready;
            // Cap Siege's frame rate: uncapped on a 120 Hz phone it ran flat out and thermal-throttled
            // within ~70 s (field log, S21 Ultra). Restored when leaving.
            _prev_max_fps = Engine.MaxFps;
            SetFpsCap(FPS_CAP);
            // 0.31.160 (Kevin's phone log, 5v5 at 14-20 fps): the physics -- only the ragdolls and the loose weapons -- at the
            // frame cap's rate: steps beyond one a drawn frame buy nothing to see (at the 30 cap and 15 fps it had been four at
            // the engine's 60; tests/moba_bench.gd: ~1.3 ms a step here with a 5v5's eight ragdolls and twenty loose weapons).
            // 0.31.162: the cap is 60, so 60 Hz. Restored on leaving.
            _prev_physics_tps = Engine.PhysicsTicksPerSecond;
            Engine.PhysicsTicksPerSecond = FPS_CAP;
            viewport = new SubViewport();
            viewport.OwnWorld3D = true;
            // 2x (Round 35): 4x with High-quality graphics was the largest single cost in a big fight (tests/battle_bench.gd:
            // 4x -> 2x more than halved the frame).
            viewport.Msaa3D = Viewport.MSAA_2X;
            // Same 3D viewport settings as the (removed) dice battle, which ran full matches on the
            // phone that crashes in Siege: default mesh LOD threshold, update when visible.
            viewport.RenderTargetUpdateMode = SubViewport.UPDATE_WHEN_VISIBLE;
            viewport.HandleInputLocally = false;
            viewport.GuiDisableInput = true;
            viewport.Size = new Vector2i(64, 64);
            AddChild(viewport);
            var tex = new TextureRect();
            tex.Texture = viewport.GetTexture();
            tex.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            tex.StretchMode = TextureRect.STRETCH_SCALE;
            tex.TextureFilter = TextureFilterMode.Linear;     // (CanvasItem.TEXTURE_FILTER_LINEAR)
            tex.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            tex.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            AddChild(tex);
            // 0.31.14 atmosphere: a soft vignette over the 3D view (under the HUD) draws the eye in and deepens the corners.
            // 0.31.219: drawn inside the 3D view (its 2D layer, over the finished 3D picture) -- at its 50 % resolution, a quarter
            // of the pixels it blended over the whole 1440x3200 screen (the same look: the picture is stretched with it)
            var vig = new TextureRect();
            var gt = new GradientTexture2D();
            gt.Fill = GradientTexture2D.FillEnum.Radial;           // (GradientTexture2D.FILL_RADIAL)
            gt.FillFrom = new Vector2(0.5, 0.5);
            gt.FillTo = new Vector2(1.08, 1.08);
            var gr = new Gradient();
            gr.SetColor(0, new Color(0.05, 0.03, 0.02, 0.0));
            gr.SetColor(1, new Color(0.05, 0.03, 0.02, 0.32));
            gr.AddPoint(0.55, new Color(0.05, 0.03, 0.02, 0.0));
            gt.Gradient = gr;
            gt.Width = 256;
            gt.Height = 256;
            vig.Texture = gt;
            vig.StretchMode = TextureRect.STRETCH_SCALE;
            vig.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            vig.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            viewport.AddChild(vig);
            vignette = vig;
            var t_hud = Time.GetTicksMsec();
            hud = new Hud();
            hud.diag = diag;
            hud.player_name = player_name;          // 0.31.209 (Kevin: "make sure players name goes on match scoreboard correctly"):
            AddChild(hud);                          // my row on the live scoreboard said "Player" until the match ended
            ready_times["hud"] = Time.GetTicksMsec() - t_hud;
            hud.LeaveRequested += () => Exited?.Invoke();
            hud.ReplayRequested += () =>
            {
                if (online)
                {
                    // 0.31.122 (Kevin: "make it so the game doesn't automatically put player back in a new game because they could be
                    // looking at score card"): the server puts us in the next match only now -- when it starts, or at once if it
                    // already has (an older server still starts it for everyone on its own). Clear the results screen meanwhile.
                    _NetSend(GDict.Of("t", "again"));
                    again_sent += 1;
                    if (hud.result_panel != null)
                    {
                        hud.result_panel.QueueFree();
                        hud.result_panel = null;
                        if (hud.score_panel != null && GD.IsInstanceValid(hud.score_panel))   // 0.31.119
                            hud.score_panel.QueueFree();
                        hud.score_panel = null;
                    }
                    hud.Toast("Next match starts shortly...", new Color("#f2d18d"));
                }
                else if (profile != null)
                {
                    // 0.31.164: a 5v5 is paid against a ticket of its own -- back through the app (siege_app.start_moba)
                    replay_hero = _Hero();
                    Exited?.Invoke();
                }
                else
                    _Restart();
            };
            hud.ActionPressed += _OnAction;
            hud.QuickChat += _OnQuickChat;                 // 0.31.111
            hud.unit_world = (string id) => view != null ? view.UnitWorld(id) : Vector3.INF;
            hud.qc_btn.Visible = !tutorial;
            hud.project = (Vector3 world) => _ToHud(view.ScreenPoint(world));
            hud.on_screen = (Vector3 world) => view.IsOnScreen(world);
            hud.numbers_source = () => view != null ? view.numbers : new GArray();
            hud.bars_source = () => view != null ? view.Bars() : new GArray();
            hud.gate_bars_source = () => view != null ? view.GateBars() : new GArray();
            hud.numbers_clock = () => view != null ? view._time : 0.0;
            Resized += _ResizeViewport;
            ready_times["viewport+hud"] = Time.GetTicksMsec() - t_ready - GD.Int(ready_times["diag"]);
            var t_start = Time.GetTicksMsec();
            if (online)
                _StartOnline();
            else if (_Staged())
                _StartStaged();
            else
                _Start();
            ready_times["start"] = Time.GetTicksMsec() - t_start;
            _ResizeViewport();
            ready_times["_ready total"] = Time.GetTicksMsec() - t_ready;
        }

        public bool _Staged()
        {
            // The world built over frames behind the loading card (the app); all at once under a scripted main loop (tests and
            // tools expect `sim` right after add_child) unless FB_STAGED_START asks for it.
            return GetTree().GetScript() == null || OS.HasEnvironment("FB_STAGED_START");
        }

        public void _Start()
        {
            foreach (var step in _StartSteps())
                step.As<Action>()();
        }

        public void _StartStaged()
        {
            // 0.31.78 (Kevin: "slow loading into battles"): the loading card goes up on the first frame after PLAY and the match
            // is built behind it, one step per frame (the sim, then the view's parts), so the menu never freezes and the card's
            // dots keep moving. The warm-up camera tour follows as before, and the match clock starts when the card lifts.
            _CoverShow();
            _build_queue = _StartSteps();
        }

        public GArray _StartSteps()
        {
            // The match's start as steps (each one timed into ready_times / View.build_times).
            var steps = new GArray();
            // (0.31.216: the field, the 5v5 and the view in three steps -- the Honor of Kings map's nav grid is bigger, and the
            // three in one frame went past 400 ms on a slow phone)
            long seed_value = match_seed < 0 ? ((long)Time.GetUnixTimeFromSystem() & 0x7fffffff) : match_seed;
            steps.Append((Action)(() =>
            {
                var t_sim = Time.GetTicksMsec();
                _sim_due = 0;                       // (0.31.219: the last match's ticks still due, if any, aren't this one's)
                sim = new SiegeSim();
                team_size = 5;
                sim.Setup(team_size, seed_value);
                ready_times["sim.setup"] = Time.GetTicksMsec() - t_sim;
            }));
            steps.Append((Action)(() =>
            {
                var t_moba = Time.GetTicksMsec();
                sim.SetupMoba(_Hero(), seed_value);
                ready_times["sim.setup_moba"] = Time.GetTicksMsec() - t_moba;
            }));
            steps.Append((Action)(() =>
            {
                view = new View();
                view.low_fx = low_fx;
                view.hq_gfx = hq_gfx;
                view.player_skins = _Skins();                   // 0.31.186 (0.31.188: the outfits are all there is)
                view.my_name = player_name;
                view.my_title = MyTitle();
                view.my_tag = clan_tag;
                view.my_crest = clan_crest;
                view.TowerBroke += _OnTowerBroke;
                viewport.AddChild(view);
                _view_steps = view.SetupSteps(sim);
            }));
            // (the view's own steps run from _view_steps between these two: the array is filled by the first step)
            steps.Append((Action)_RunViewSteps);
            steps.Append((Action)(() =>
            {
                hud.sim = sim;
                hud.kill_feed_on = true;
                hud.kill_feed = new GArray();
                _accum = 0.0;
                _result_shown = false;
                if (analytics != null && !online && !tutorial)
                {
                    _an_match = Analytics.Hex(4);
                    _an_class0 = ClassOf(sim.by_id.TryGetValue(hud.player_id, out var u0) ? u0 : null);
                    analytics.LogEv("match_start", GDict.Of("match", _an_match, "mode", "5v5", "class", _an_class0));
                }
                _TitleReset();
                if (tutorial)
                    _TutorialBegin();
                _ProbeBegin();
            }));
            return steps;
        }

        public void _ProbeBegin()
        {
            // 0.31.219: the graphics chip's (0.31.220: and the processor's) cost of each part, measured on the phone
            if (GD.IsInstanceValid(probe))
                probe.QueueFree();
            probe = null;
            if (GpuProbe.Wanted(this))
            {
                probe = new GpuProbe();
                probe.Name = "GpuProbe";
                probe.mode = this;
                AddChild(probe);
            }
            else if (diag != null && !GArray.Of("headless", "not asked for").Has(GpuProbe.OffReason(this)))
                diag.Write("PROBE off: " + GpuProbe.OffReason(this));
        }

        public string _Hero()
        {
            // the hero of an offline match (a 5v5 against bots): the one picked, else the Knight
            return moba_hero != "" ? moba_hero : "knight";
        }

        public GArray _build_queue = new GArray();           // steps still to run, one per frame (staged start)
        public GArray _view_steps = new GArray();

        public void _RunViewSteps()
        {
            // All of them at once (synchronous start); staged, _process takes them one per frame instead.
            foreach (var step in _view_steps)
                step.As<Action>()();
            _view_steps = new GArray();
        }

        public const int BUILD_BUDGET_MS = 20;       // steps of the staged start run until a frame has spent this long on them

        public void _BuildStep()
        {
            // Steps of the staged start, as many as fit the frame's budget (the view's steps have their own queue, run before
            // the step after them): never a frozen frame, and no frame spent on a step that took a millisecond.
            var t0 = Time.GetTicksMsec();
            while (!_build_queue.IsEmpty() && Time.GetTicksMsec() - t0 < BUILD_BUDGET_MS)
            {
                if (_build_queue[0] == Var.Of((Action)_RunViewSteps) && !_view_steps.IsEmpty())
                {
                    _view_steps.PopFront().As<Action>()();
                    if (!_view_steps.IsEmpty())
                        continue;
                }
                _build_queue.PopFront().As<Action>()();
            }
        }

        public GDict _Skins()
        {
            // 0.31.186: hero -> the skin I wear on him
            return profile != null ? profile.d.Get("skin_on", new GDict()).D.Duplicate() : new GDict();
        }

        // ---------- vibration (0.31.120, Kevin: "phone vibration") ----------
        // 0.31.128 (Kevin: "I only want phone to vibrate when player makes a kill"): one buzz for each enemy I knock out --
        // nothing for being hit, falling, the King, rescues or gates (0.31.120 buzzed for all of those). Settings > VIBRATION.
        public bool vibrate = false;        // (the app sets it from Settings; off in tests and tools)
        public int buzzes = 0;             // (tests: how many so far, and the last [ms, strength])
        public GArray last_buzz = new GArray();
        public static readonly GDict BUZZ = GDict.Of("ko", GArray.Of(70, 0.75));

        public void _Haptic(Ev e)
        {
            if (!vibrate || sim == null)
                return;
            var me = GD.Str(hud.player_id);
            if (e.S("k", "") == "death" && e.S("by", "") == me && e.S("id", "") != me)
                Buzz(GD.Int(BUZZ["ko"][0]), (double)BUZZ["ko"][1]);
        }

        public void Buzz(int ms, double strength)
        {
            buzzes += 1;
            last_buzz = GArray.Of(ms, strength);
            Input.VibrateHandheld(ms, strength);
        }

        public void _Count(Ev e)
        {
            _Haptic(e);
            if (e.S("id", "") == hud.player_id && e.S("k", "") == "multikill")
            {
                _best_multi = GD.Maxi(_best_multi, e.I("n", 0));
                if (_q_cls != "")
                {
                    GDict qe = _QEntry(_q_cls);
                    qe["best_multi"] = GD.Maxi(GD.Int(qe.Get("best_multi", 0)), e.I("n", 0));
                }
            }
        }

        public string MyTitle()
        {
            // The title to wear online: the profile's, if it is one the game knows and the player owns.
            if (profile == null)
                return "";
            var t = GD.Str(profile.d.Get("title", ""));
            return Net.TITLES.Has(t) && profile.Owns(t) ? t : "";
        }

        public void _TitleReset()
        {
            _cls_time = new GDict();
            _kills_cls = new GDict();
            _kills_seen = 0;
            _best_multi = 0;
            _q = new GDict();
            _q_seen = new GDict();
            _q_cls = "";
        }

        public void _TitleTrack(double delta)
        {
            // Each frame of a match: time as the class you are, and any new knockouts credited to it.
            Unit me = sim != null && sim.by_id.TryGetValue(hud.player_id, out var mu) ? mu : null;
            if (me == null || sim.ended)
                return;
            var cls = GD.Str(me.cls);
            if (me.state != "dead")
                _cls_time[cls] = (double)_cls_time.Get(cls, 0.0) + delta;
            var k = me.kills;
            if (k > _kills_seen)
            {
                _kills_cls[cls] = GD.Int(_kills_cls.Get(cls, 0)) + (k - _kills_seen);
                _kills_seen = k;
            }
            // 0.31.97: quests -- time as the class worn, and whatever my unit's totals grew by, credited to it
            _q_cls = Eco.CosmeticClass(cls, me.up);
            if (_q_cls != "" && me.state != "dead")
            {
                GDict qe = _QEntry(_q_cls);
                qe["t"] = (double)qe.Get("t", 0.0) + delta;
            }
            foreach (var f in Q_UNIT)
            {
                var v = V.ToDouble(me.Get(f.AsString()));
                var dv = v - (double)_q_seen.Get(f, 0.0);
                if (dv > 0.0)
                    _QAdd(GD.Str(Q_UNIT[f]), dv);
                _q_seen[f] = v;
            }
        }

        public GDict TitleSummary()
        {
            // The match's main class: the one played longest (at least a minute of it), else none.
            var main = "";
            var best = 60.0;
            foreach (var c in _cls_time)
            {
                if ((double)_cls_time[c] >= best)
                {
                    best = (double)_cls_time[c];
                    main = GD.Str(c);
                }
            }
            var q = new GDict();
            foreach (var c in _q)
            {
                GDict e = _q[c].D;
                q[c] = GDict.Of("t", (double)e.Get("t", 0.0), "kills", GD.Int(e.Get("kills", 0.0)),
                    "gates", GD.Int((double)e.Get("gate_dmg", 0.0) / 100.0), "healed", GD.Int(e.Get("healed", 0.0)),
                    "best_multi", GD.Int(e.Get("best_multi", 0)), "towers", GD.Int(e.Get("towers", 0.0)), "camps", GD.Int(e.Get("camps", 0.0)),
                    "lh", GD.Int(e.Get("lh", 0.0)), "epics", GD.Int(e.Get("epics", 0.0)));
            }
            return GDict.Of("cls_main", main, "kills_cls", _kills_cls.Duplicate(), "best_multi", _best_multi, "q", q);
        }

        public GDict _QEntry(string c)
        {
            if (!_q.Has(c))
                _q[c] = new GDict();
            return _q[c].D;
        }

        public void _QAdd(string stat, double n)
        {
            // credit n of a stat to the class I'm wearing
            if (_q_cls == "")
                return;
            var qe = _QEntry(_q_cls);
            qe[stat] = (double)qe.Get(stat, 0.0) + n;
        }

        public void _StartOnline()
        {
            ws = new WebSocketPeer();
            ws.InboundBufferSize = 1 << 20;
            ws.OutboundBufferSize = 1 << 16;
            var err = ws.ConnectToUrl(net_url);
            net_state = "connecting";
            _net_started = Time.GetTicksMsec() / 1000.0;
            diag.Write(GD.Fmt("NET connect %s err=%d", net_url, err));
            hud.Toast("Connecting to the server...", new Color("#f2d18d"));
            lobby = _LoadingScreen();
            lobby.Leave += () => Exited?.Invoke();
            AddChild(lobby);
            if (err != GD.OK)
                _NetFail("Could not reach the server");
        }

        public void _NetFail(string why)
        {
            if (net_state == "closed")
                return;
            net_state = "closed";
            diag.Write("NET closed: " + why);
            hud.Toast(why, VisualTheme.RED);
            if (GD.IsInstanceValid(lobby))
                lobby.Fail(why);
            if (sim == null || (again_sent > 0 && sim.ended))   // (0.31.209: or after PLAY AGAIN -- nothing left to show)
            {
                // Nothing to show: go back home after the message is readable. (A method, not a lambda: the app may free
                // this node first, e.g. for the Update screen, and a freed method target is simply not called.)
                GetTree().CreateTimer(2.5).Timeout += _NetExitIfAlive;
            }
        }

        // (a timer's call into a freed node is dropped in Godot; a C# delegate would still run it -- so it checks first)
        void _NetExitIfAlive()
        {
            if (!IsFreed)
                _NetExit();
        }

        public void _NetExit()
        {
            if (IsInsideTree())
                Exited?.Invoke();
        }

        public void _NetNoFive()
        {
            // 0.31.170: the server answered from before the online 5v5 (not redeployed yet): leave quietly, and Home starts this
            // hero's match against bots instead (siege_app._end_match, exit_note "no_five")
            if (net_state == "closed")
                return;
            net_state = "closed";
            diag.Write("NET the server has no online 5v5: a match against bots instead");
            _NetSend(GDict.Of("t", "leave"));
            if (ws != null)
                ws.Close(1000, "leave");
            exit_note = "no_five";
            replay_hero = _Hero();
            _NetExit();
        }

        public bool _NetVersionRefused(int code, string reason)
        {
            // A version refusal, from the bye ("need") or the close (code 4001, reason "version:<n>"). Works for every
            // future protocol bump: only Net.VERSION is compared.
            int sv = Net.RefusedVersion(_net_bye, code, reason);
            if (sv < 0)
                return false;
            string verdict = Net.VersionVerdict(sv);
            if (verdict == "ok")
                verdict = "server_old";         // refused although the numbers match: treat it as a server mid-update
            net_verdict = verdict;
            net_server_version = sv;
            diag.Write(GD.Fmt("NET version refused: server %d, client %d -> %s (code %d %s)", sv, Net.VERSION, verdict, code, reason));
            VersionMismatch?.Invoke(sv, verdict);
            _NetFail(verdict == "update" ? MSG_UPDATE : MSG_SERVER_OLD);
            return true;
        }

        public GArray _NetReadPackets()
        {
            var o = new GArray();
            while (ws != null && ws.GetAvailablePacketCount() > 0)
                o.Append(Net.Decode(ws.GetPacket()));
            return o;
        }

        public void _NetSend(GDict msg)
        {
            if (ws != null && ws.GetReadyState() == WebSocketPeer.STATE_OPEN)
                ws.PutPacket(Net.Encode(msg));
        }

        public GDict _Hello()
        {
            var hi = GDict.Of("t", "hello", "v", Net.VERSION, "name", player_name, "build", Diag.BUILD, "pred", true, "title", MyTitle(),
                "lk", profile != null ? profile.WireLooks() : new GDict());          // 0.31.101: what I wear, for the others
            if (profile != null && (bool)profile.server_mode)
            {
                hi["acct"] = GD.Str(profile.d["account"]["id"]);       // 0.31.108: the server pays this match to the account
                hi["key"] = GD.Str(profile.d["account"]["key"]);
            }
            hi.Merge(Analytics.HelloFlags(profile));         // 0.31.118: "an_off" when usage statistics are off
            if (party_join != "")
                hi["join"] = party_join;                      // 0.31.120: into this friend's match (Friends > JOIN)
            hi["ask_next"] = true;                            // 0.31.122: the next match only after PLAY AGAIN (older servers ignore it)
            hi["five"] = Net.FIVE;                            // 0.31.170: the online 5v5 -- as my hero (the server checks I own it)
            hi["hero"] = _Hero();
            return hi;
        }

        public void _BeginRejoin()
        {
            // 0.31.120: the connection dropped mid-match -- keep the match on screen and try to get back onto my seat
            net_state = "rejoining";
            _rejoin_until = Time.GetTicksMsec() / 1000.0 + rejoin_for;
            _rejoin_at = Time.GetTicksMsec() / 1000.0 + 0.5;
            _rejoin_sent = false;
            _net_bye = new GDict();
            hud.rejoin_until = _rejoin_until;
            diag.Write(GD.Fmt("NET dropped mid-match: reconnecting (token %s...)", _rj.Left(4)));
        }

        public bool _RejoinTick()
        {
            // -> true while a new connection is being made (nothing else to read yet)
            var now = Time.GetTicksMsec() / 1000.0;
            if (now > _rejoin_until)
            {
                hud.rejoin_until = -1.0;
                _NetFail("Disconnected from the server");
                return true;
            }
            var st = ws != null ? ws.GetReadyState() : WebSocketPeer.STATE_CLOSED;
            if (st == WebSocketPeer.STATE_CLOSED && now >= _rejoin_at)
            {
                _rejoin_at = now + REJOIN_EVERY;
                _rejoin_sent = false;
                ws = new WebSocketPeer();
                ws.InboundBufferSize = 1 << 20;
                ws.OutboundBufferSize = 1 << 16;
                ws.ConnectToUrl(net_url);
                _net_started = now;
                return true;
            }
            if (st == WebSocketPeer.STATE_CONNECTING && now - _net_started > 6.0)
            {
                ws.Close();
                return true;
            }
            return st != WebSocketPeer.STATE_OPEN;
        }

        public void _BuildOnlineMatch(GDict msg)
        {
            // A new match (or the first one): rebuild the mirror sim and the 3D view.
            if (GD.IsInstanceValid(view))
                view.QueueFree();
            if (hud.result_panel != null)
            {
                hud.result_panel.QueueFree();
                hud.result_panel = null;
                if (hud.score_panel != null && GD.IsInstanceValid(hud.score_panel))   // 0.31.119
                    hud.score_panel.QueueFree();
                hud.score_panel = null;
            }
            sim = new SiegeSim();
            sim.Setup(GD.Int(msg.Get("team_size", Net.TEAM_SIZE)), GD.Int(msg.Get("seed", 1)), -1);
            sim.SetupMoba("", GD.Int(msg.Get("seed", 1)));      // (0.31.169: the server's 5v5, its heroes drafted from the same seed)
            var me_id = GD.Str(msg.Get("you", ""));
            hud.player_id = me_id;
            view = new View();
            view.low_fx = low_fx;
            view.hq_gfx = hq_gfx;
            view.player_id = me_id;
            view.player_skins = _Skins();                       // 0.31.186
            view.player_names = net_names;
            view.player_titles = net_titles;
            view.player_tags = net_tags;
            view.player_crests = net_crests;
            view.SetUnitLooks(net_looks);
            view.my_name = player_name;
            view.my_title = MyTitle();
            view.my_tag = clan_tag;
            view.my_crest = clan_crest;
            view.TowerBroke += _OnTowerBroke;
            viewport.AddChild(view);
            view.Setup(sim);
            hud.sim = sim;
            hud.kill_feed = new GArray();
            net_match = GD.Int(msg.Get("match", 0));
            hud.rejoin_until = -1.0;
            _result_shown = false;
            _TitleReset();
            _ProbeBegin();                                       // 0.31.220: online too
            net_state = "playing";
            diag.Write(GD.Fmt("NET welcome match=%d you=%s players=%d", net_match, me_id, GD.Int(msg.Get("players", 1))));
            hud.Toast(GD.Fmt("Online: %d player%s", GD.Int(msg.Get("players", 1)), GD.Int(msg.Get("players", 1)) == 1 ? "" : "s"), VisualTheme.GOLD);
            hud.player_name = player_name;                      // 0.31.209: my row on the scoreboard (not "Player")
            if (GD.IsInstanceValid(lobby))
            {
                if (_warm_done)
                {
                    lobby.QueueFree();                         // 0.31.209: a PLAY AGAIN lobby: the match is built -- straight in
                    lobby = null;
                }
                else
                    _LobbyToCard();
            }
        }

        public void _LobbyToCard()
        {
            // 0.31.208: at the welcome the lobby stays up as the loading card -- the same heroes on the plaza, PREPARING THE
            // BATTLEFIELD (the warm-up keeps it up; tests drop it)
            if (_cover != null && _cover != lobby)
                _cover.QueueFree();
            lobby.Loading();
            _cover = lobby;
            lobby = null;
        }

        public void _NetProcess(double delta)
        {
            if (ws == null)
                return;
            ws.Poll();
            var st = ws.GetReadyState();
            if (net_state == "rejoining")
            {
                if (_RejoinTick())
                    return;
                st = ws.GetReadyState();
            }
            if (st == WebSocketPeer.STATE_CONNECTING)
            {
                if (Time.GetTicksMsec() / 1000.0 - _net_started > 10.0)
                {
                    ws.Close();
                    _NetFail("Server did not answer");
                }
                return;
            }
            if (st == WebSocketPeer.STATE_CLOSED || st == WebSocketPeer.STATE_CLOSING)
            {
                // A refusal's bye can arrive together with the close: read what is left before deciding (before 0.31.73
                // the state was checked first, so a version refusal only ever said "Could not connect to the server").
                foreach (var left in _NetReadPackets())
                {
                    if (GD.Str(left.D.Get("t", "")) == "bye")
                        _net_bye = left.D;
                }
                if (net_state == "closed")
                    return;
                if (st == WebSocketPeer.STATE_CLOSING)
                {
                    var now_c = Time.GetTicksMsec() / 1000.0;
                    if (_net_closing_since < 0.0)
                        _net_closing_since = now_c;
                    if (now_c - _net_closing_since < 2.0)
                        return;                         // wait for the close code
                }
                if (_NetVersionRefused(ws.GetCloseCode(), ws.GetCloseReason()))
                    return;
                if (GD.Str(_net_bye.Get("why", "")) == "full" || ws.GetCloseCode() == Net.CLOSE_FULL)
                {
                    _NetFail("Server is full");
                    return;
                }
                if (GD.Str(_net_bye.Get("why", "")) == "done")
                {
                    _NetExit();                                  // 0.31.122: (the bye and the close arrived together)
                    return;
                }
                if (sim != null && !sim.ended && _rj != "" && net_state == "playing" && _net_bye.IsEmpty() && ws.GetCloseCode() != 4006)
                {
                    _BeginRejoin();                              // 0.31.120: the connection dropped -- try to get back in
                    return;
                }
                _NetFail(sim != null ? "Disconnected from the server" : "Could not connect to the server");
                return;
            }
            if (net_state == "connecting")
            {
                net_state = "waiting";
                _NetSend(_Hello());
            }
            if (net_state == "rejoining" && !_rejoin_sent)
            {
                _rejoin_sent = true;
                var hr = _Hello();
                hr["rj"] = _rj;                                   // 0.31.120: back onto my seat
                _NetSend(hr);
            }
            while (ws.GetAvailablePacketCount() > 0)
            {
                var msg = Net.Decode(ws.GetPacket());
                switch (GD.Str(msg.Get("t", "")))
                {
                    case "welcome":
                        if (GD.Int(msg.Get("five", 0)) < Net.FIVE)
                        {
                            _NetNoFive();                              // 0.31.170: a server from before the online 5v5
                            return;
                        }
                        _rj = GD.Str(msg.Get("rj", _rj));                   // 0.31.120: my seat's token, for a rejoin
                        if ((bool)msg.Get("rejoin", false) && GD.Int(msg.Get("match", -1)) == net_match && sim != null)
                        {
                            net_state = "playing";
                            rejoins += 1;
                            hud.rejoin_until = -1.0;
                            _net_rt = -1.0;                              // (the render clock starts again from the next snapshot)
                            _net_rx_last = 0.0;
                            hud.Toast("Back in the match!", new Color("#8fe3a2"));
                            diag.Write(GD.Fmt("NET rejoined match %d as %s", net_match, GD.Str(msg.Get("you", ""))));
                        }
                        else if (GD.Int(msg.Get("match", -1)) != net_match)
                        {
                            _BuildOnlineMatch(msg);
                            var got = GD.Str(msg.Get("hero", ""));
                            if (got != "" && got != _Hero() && Moba.HEROES.ContainsKey(got))
                            {
                                // 0.31.170: someone on my side plays my pick, or the server doesn't know I bought it yet
                                hud.Toast(GD.Fmt("%s was taken -- you're the %s", Moba.HEROES.TryGetValue(_Hero(), out var mh) ? GD.Str(mh.name) : _Hero(),
                                    GD.Str(Moba.HEROES[got].name)), new Color("#f2d18d"));
                            }
                        }
                        break;
                    case "s":
                        {
                            if (sim == null)
                                continue;
                            Net.Apply(sim, msg, hud.player_id, !_me_bot);
                            var was_bot = _me_bot;
                            _me_bot = sim.by_id.TryGetValue(hud.player_id, out var mb) && mb.bot;
                            if (was_bot && !_me_bot)
                                hud.idle_kick_at = -1.0;                // (mine again)
                            _snap_dt = _snap_t > 0.0 ? GD.Lerpf(_snap_dt, GD.Maxf(0.03, _snap_t), 0.2) : _snap_dt;
                            _snap_t = 0.0;
                            _net_latest = (double)msg.Get("tm", _net_latest);
                            // 0.31.24: the draw delay adapts to the connection -- the gap between arrivals vs the snapshot interval
                            var now_rx = Time.GetTicksMsec() / 1000.0;
                            if (_net_rx_last > 0.0)
                            {
                                var gap = now_rx - _net_rx_last;
                                _net_jitter = GD.Lerpf(_net_jitter, Math.Abs(gap - 1.0 / Net.SNAP_HZ), 0.1);
                            }
                            _net_rx_last = now_rx;
                            _net_delay = GD.Clampf(Net.INTERP_DELAY + 1.5 * _net_jitter, Net.INTERP_DELAY, 0.25);
                            if (_net_rt < 0.0)
                                _net_rt = _net_latest - _net_delay;
                            foreach (var we in msg.Get("e", new GArray()))
                            {
                                var e = Net.ToEv(we);
                                diag.Event(e);
                                _Count(e);
                                // an effect of my own that I already showed when I pressed the button: don't show it twice
                                if (e.S("id", "") == hud.player_id && _pred_fx.Has(e.K) && Time.GetTicksMsec() / 1000.0 - (double)_pred_fx[e.K] < 0.6)
                                {
                                    _pred_fx.Erase(e.K);
                                    hud.OnEvent(e);
                                    continue;
                                }
                                view.OnEvent(we.D);
                                _EventSound(e);
                                hud.OnEvent(e);
                            }
                            break;
                        }
                    case "lobby":                                          // 0.31.82: waiting for the wave's countdown
                        if (GD.Int(msg.Get("five", 0)) < Net.FIVE)
                        {
                            _NetNoFive();                              // 0.31.170: a server from before the online 5v5
                            return;
                        }
                        lobby_msgs += 1;
                        if (lobby_msgs == 1)
                            diag.Write(GD.Fmt("NET lobby left=%.1f names=%d online=%d running=%s", (double)msg.Get("left", 0), msg.Get("names", new GArray()).A.Size(), GD.Int(msg.Get("online", 0)), GD.Str(msg.Get("running", false))));
                        if (sim == null && GD.IsInstanceValid(lobby))
                            lobby.Update(msg);
                        else if (sim != null && sim.ended)
                        {
                            // 0.31.209 (Kevin: "players cannot join a match in progress"): PLAY AGAIN once the next match had
                            // started puts us in a lobby's countdown instead -- its screen, over the old match, until the welcome
                            if (!GD.IsInstanceValid(lobby))
                            {
                                lobby = _LoadingScreen();
                                lobby.Leave += () => Exited?.Invoke();
                                AddChild(lobby);
                                diag.Write(GD.Fmt("NET lobby after PLAY AGAIN left=%.1f", (double)msg.Get("left", 0)));
                            }
                            lobby.Update(msg);
                        }
                        break;
                    case "pn":                                             // 0.31.86: the live players' names, by unit
                        {
                            Var pn = msg.Get("n", new GDict());
                            net_names = pn.IsDict ? pn.D : new GDict();
                            Var tt = msg.Get("tt", new GDict());
                            net_titles = tt.IsDict ? tt.D : new GDict();
                            Var lk = msg.Get("lk", new GDict());           // 0.31.101: what each of them wears
                            net_looks = lk.IsDict ? lk.D : new GDict();
                            Var ct = msg.Get("ct", new GDict());           // 0.31.134: their clan tags
                            net_tags = ct.IsDict ? ct.D : new GDict();
                            Var cc = msg.Get("cc", new GDict());           // 0.31.196: and crests
                            net_crests = cc.IsDict ? cc.D : new GDict();
                            hud.net_names = net_names;                     // 0.31.119: the scoreboard names the players
                            if (GD.IsInstanceValid(view))
                            {
                                view.player_names = net_names;
                                view.player_titles = net_titles;
                                view.player_tags = net_tags;
                                view.player_crests = net_crests;
                                view.SetUnitLooks(net_looks);
                            }
                            break;
                        }
                    case "qc":                                             // 0.31.111: a quick chat line from a player of my side (or anyone's gg)
                        {
                            var qu = GD.Str(msg.Get("u", ""));
                            if (qu != hud.player_id && sim != null)      // (mine showed when I said it)
                            {
                                hud.AddPing(qu, GD.Int(msg.Get("i", -1)), GD.Str(net_names.Get(qu, "")));
                                _PingSound();
                            }
                            break;
                        }
                    case "st":                                             // 0.31.87: the health I've healed (the Merciful title)
                        if (sim != null && sim.by_id.ContainsKey(hud.player_id))
                            sim.by_id[hud.player_id].healed = (double)msg.Get("heal", 0);
                        break;
                    case "m":                                              // 0.31.23: my task, sent on its own when it changes
                        if (sim != null && sim.by_id.ContainsKey(hud.player_id))
                            sim.by_id[hud.player_id].Set("task", msg.Get("task", new GDict()));
                        break;
                    case "joinr":                                          // 0.31.120: the friend's match couldn't take me
                        {
                            var jw = GD.Str(msg.Get("why", ""));
                            // 0.31.209: "playing" -- it had started (no joining a match in progress)
                            string jt = GD.Str(GDict.Of("full", "Their match is full", "playing", "Their match has already started").Get(jw, "They've left that match"));
                            hud.Toast(jt + " -- you're in another one", new Color("#f2d18d"));
                            if (GD.IsInstanceValid(lobby))
                                lobby.Note(jt);
                            break;
                        }
                    case "idle":                                           // 0.31.119: a bot plays for me until I move (or I'm removed)
                        if ((bool)msg.Get("on", false))
                            hud.idle_kick_at = Time.GetTicksMsec() / 1000.0 + (double)msg.Get("kick_in", 120.0);
                        else
                            hud.idle_kick_at = -1.0;
                        break;
                    case "bye":
                        {
                            _net_bye = msg;
                            if (_NetVersionRefused(-1, ""))
                                return;
                            var why = GD.Str(msg.Get("why", ""));
                            if (why == "done")
                            {
                                _NetExit();                             // 0.31.122: left on the results a long while -- back to Home
                                return;
                            }
                            if (why == "idle")
                            {
                                exit_note = "idle";
                                _NetFail("Removed for being idle");
                                GetTree().CreateTimer(2.5).Timeout += _NetExitIfAlive;     // (back to Home, which says why)
                                return;
                            }
                            _NetFail(GD.Str(GDict.Of("full", "Every match is full -- try again in a minute").Get(why, "Server closed the connection")));
                            return;
                        }
                }
            }
            if (sim == null)
                return;
            _snap_t += delta;
            // 0.31.23: a render clock in server time, INTERP_DELAY behind the newest snapshot, eased so jitter doesn't show
            if (_net_rt >= 0.0)
            {
                _net_rt += delta;
                var want = _net_latest - _net_delay;
                var err = want - _net_rt;
                if (Math.Abs(err) > 0.3)
                    _net_rt = want;
                else
                    _net_rt += err * GD.Minf(1.0, delta * 3.0);
                Net.InterpolateAt(sim, _net_rt, _me_bot ? "" : hud.player_id);     // (a bot playing me: drawn like the others)
            }
            // Inputs: movement and held attack at 20 Hz (or when they change); actions go immediately.
            _send_clock += delta;
            Vector2 mv = !hud.Paused() ? _MoveInput() : Vector2.ZERO;
            bool hold = hud.AttackHeld() && !hud.Paused();
            bool bhold = hud.AbilityHeld() && !hud.Paused();
            // Client-side prediction: move our own unit now (same movement code as the server); the server
            // validates the position we send. Snapshots only correct us when we've drifted > 2.5 m.
            Unit me_p = sim.by_id.TryGetValue(hud.player_id, out var mpu) ? mpu : null;
            if (me_p != null && !_me_bot && sim.ClientDrivable(me_p))
            {
                sim.PredictStep(me_p, mv, delta);
                // Held ATTACK: the server swings every time it can; start the same swings locally.
                if (hold && me_p.cls != "priest" && sim.CanAct(me_p))
                    sim.StartAttack(me_p, "attack");
                sim.DrainEvents();                         // (prediction events are shown in _act; nothing else should pile up)
            }
            if (_send_clock >= 0.05 || (mv - _sent_move).Length() > 0.25 || hold != _sent_hold || bhold != _sent_bhold)
            {
                _send_clock = 0.0;
                _sent_move = mv;
                _sent_hold = hold;
                _sent_bhold = bhold;
                var msg_in = GDict.Of("t", "in", "m", mv, "h", hold, "b", bhold);
                if (me_p != null && !_me_bot)
                {
                    msg_in["p"] = me_p.pos;
                    msg_in["f"] = me_p.face;
                }
                _NetSend(msg_in);
            }
        }

        public Vector2 _MoveInput()
        {
            // The stick in world terms. 0.31.85 (Kevin: "When on the other team ... controls are inverted"): the camera looks up
            // the field from your own castle, so on the red team (online) it is turned half way round from blue's -- the
            // stick's screen directions are the opposite world directions there.
            // 0.31.216: the landscape camera is turned (siege_view.gd CAM_YAW): the stick's screen directions are the world's
            // turned with it.
            Vector2 v = hud.MoveVector();
            var team = sim != null ? (sim.by_id.TryGetValue(hud.player_id, out var u) ? u.team : 0) : 0;
            return View.ScreenToWorld(v, team);
        }

        public void _Restart()
        {
            if (GD.IsInstanceValid(view))
                view.QueueFree();
            if (hud.result_panel != null)
            {
                hud.result_panel.QueueFree();
                hud.result_panel = null;
                if (hud.score_panel != null && GD.IsInstanceValid(hud.score_panel))   // 0.31.119
                    hud.score_panel.QueueFree();
                hud.score_panel = null;
            }
            if (_Staged())
            {
                _warm_done = false;                 // the card again (briefly: the pipelines are compiled by now)
                _StartStaged();
            }
            else
                _Start();
        }

        public void _ResizeViewport()
        {
            // The canvas transform is 1.0 under canvas_items stretching, so it can't tell logical from
            // physical pixels (that bug rendered 3D at 336x746 on a 1440x3200 screen). Use the real
            // window size over the logical viewport size instead.
            var logical = GetViewport().GetVisibleRect().size;
            var window = (Vector2)DisplayServer.WindowGetSize();
            var phys = logical.x > 0.0 && window.x > 0.0 ? window / logical : Vector2.ONE;
            var scale = phys * render_scale;
            viewport.Size = new Vector2i(GD.Maxi(64, GD.Int(Size.x * scale.x)), GD.Maxi(64, GD.Int(Size.y * scale.y)));
            // At native density MSAA costs bandwidth for no visible gain; keep it for reduced scales.
            viewport.Msaa3D = render_scale >= 0.99 ? Viewport.MSAA_DISABLED : Viewport.MSAA_2X;
            if (diag != null)
                diag.Write(GD.Fmt("3D RES %dx%d = %d%% of window %dx%d (logical %dx%d, refresh %.0f Hz, fps cap %d)", viewport.Size.x, viewport.Size.y,
                    GD.Int(render_scale * 100.0), GD.Int(window.x), GD.Int(window.y), GD.Int(Size.x), GD.Int(Size.y), DisplayServer.ScreenGetRefreshRate(), fps_cap));
        }

        public void SetRenderScale(double v)
        {
            render_scale = GD.Clampf(v, 0.25, 1.0);
            _ResizeViewport();
        }

        public Vector2 _ToHud(Vector2 p)
        {
            var vs = (Vector2)viewport.Size;
            return vs.x > 0 ? p * (Size / vs) : p;
        }

        public void _Act(string action, Var arg = default)
        {
            if (online)
            {
                Unit me_a = sim.by_id.TryGetValue(hud.player_id, out var mau) ? mau : null;
                if ((action == "dodge" || action == "attack") && me_a != null && sim.ClientDrivable(me_a))
                {
                    // Predict dodges and swings locally: the animation starts now, the server resolves the hit.
                    if (action == "dodge")
                        sim.Dodge(me_a);
                    else if (me_a.cls != "priest")
                        sim.StartAttack(me_a, "attack");
                }
                else if (action == "ability" && me_a != null && sim.ClientDrivable(me_a) && me_a.kq == null)
                {
                    // (0.31.170: not a new hero's Q -- a kit spell only the server casts)
                    // 0.31.23 (Kevin: "abilities lag"): the ability's start shows now -- the swing, the spin, the ring; the
                    // server resolves what it does (the predicted start happens in _process right after this frame's input)
                    if (sim.PredictAbility(me_a))
                    {
                        foreach (var e in sim.DrainEvents())
                        {
                            _pred_fx[e.K] = Time.GetTicksMsec() / 1000.0;
                            view.OnEvent(Net.WireEvent(e));
                            _EventSound(e);
                        }
                    }
                }
                var msg_a = GDict.Of("t", "in", "m", _MoveInput(), "h", hud.AttackHeld(), "b", hud.AbilityHeld(), "k", hud.BlockHeld(), "a", action, "arg", arg);
                if (me_a != null)
                {
                    msg_a["p"] = me_a.pos;
                    msg_a["f"] = me_a.face;
                }
                _NetSend(msg_a);
                return;
            }
            sim.Act(hud.player_id, action, arg.Obj);
        }

        public string _LearnHint(Unit me, string slot)
        {
            // 0.31.217: why a skill can't be used yet -- not learnt: tap its +, or the level it needs
            var name = slot == "r" ? "Your ultimate" : slot.ToUpperInvariant();
            if (sim.moba.CanLearn(me, slot))
                return GD.Fmt("%s isn't learnt yet -- tap the + over it", name);
            return GD.Fmt("%s can be learnt at level %d", name, sim.moba.RankNeed(slot, 1));
        }

        // (audio.play(cue) when the app gave one: `audio != null and audio.has_method("play")` -- the app's NativeAudio has it)
        void _Play(string cue)
        {
            if (audio != null)
                audio.Play(cue);
        }

        public void _OnAction(string kind)
        {
            SimJoin();                             // (0.31.219: a no-op -- the ticks end with each frame's drawing; for safety)
            if (online && !(kind == "attack" || kind == "ability" || kind == "dodge"))
            {
                _OnActionOnline(kind);
                return;
            }
            switch (kind)
            {
                case "attack": _Act("attack"); break;
                case "ability":
                    {
                        Unit me_q = sim != null && sim.by_id.TryGetValue(hud.player_id, out var mq) ? mq : null;
                        if (sim != null && sim.moba != null && me_q != null && me_q.rk != null && sim.moba.Rank(me_q, "q") <= 0)
                        {
                            hud.Toast(_LearnHint(me_q, "q"), new Color("#ffcf7a"));      // 0.31.217: not learnt yet
                            return;
                        }
                        if (sim != null && me_q != null && me_q.kq != null && !online)
                        {
                            // 0.31.168: a new hero's Q is a kit spell -- say why when it can't go (CHAIN, ROOTS need someone near)
                            if (!sim.Act(hud.player_id, "ability") && me_q.cd_ability <= 0.0 && sim.CanAct(me_q))
                                hud.Toast("No enemy in reach", new Color("#ffcf7a"));
                        }
                        else
                            _Act("ability");
                        break;
                    }
                case "dodge": _Act("dodge"); break;
                case "pick0":
                case "pick1":
                case "pick2":                       // 0.31.155 5V5: a level-up choice
                    if (sim != null && sim.Act(hud.player_id, "pick", GD.Int(kind.Right(1))))
                        _Play("equip");
                    break;
                case "learn_q":
                case "learn_w":
                case "learn_e":
                case "learn_r":      // 0.31.217: a skill point (the + over a skill)
                    if (sim != null && sim.Act(hud.player_id, "learn", kind.Right(1)))
                        _Play("equip");
                    break;
                case "ult":                                           // 0.31.157 5V5: the ultimate
                    if (sim != null && !sim.Act(hud.player_id, "ult"))
                    {
                        Unit me_u = sim.by_id.TryGetValue(hud.player_id, out var mu) ? mu : null;
                        if (me_u != null && sim.moba.UltRank(me_u) == 0)
                            hud.Toast(_LearnHint(me_u, "r"), new Color("#ffcf7a"));
                        else if (me_u != null && me_u.ult_cd <= 0.0 && sim.CanAct(me_u))
                            hud.Toast("No enemy in reach", new Color("#ffcf7a"));         // (EXECUTE, FLURRY: they need someone near)
                    }
                    break;
                case "w":
                case "e":                                        // 0.31.167 5V5: W and E
                    if (sim != null && !sim.Act(hud.player_id, "spell", kind))
                    {
                        Unit me_s = sim.by_id.TryGetValue(hud.player_id, out var ms) ? ms : null;
                        if (me_s != null && !sim.moba.kits.Unlocked(me_s, kind))
                            hud.Toast(_LearnHint(me_s, kind), new Color("#ffcf7a"));
                        else if (me_s != null && V.ToDouble(me_s.Get("cd_" + kind)) <= 0.0 && sim.CanAct(me_s))
                            hud.Toast("No enemy hero in reach", new Color("#ffcf7a"));       // (SHADOW STEP, MARK, CURSE need one)
                    }
                    break;
                case "recall":                                        // 0.31.181: home to the fountain
                    if (sim != null)
                    {
                        Unit me_r = sim.by_id.TryGetValue(hud.player_id, out var mr) ? mr : null;
                        if (sim.Act(hud.player_id, "recall"))
                        {
                            // (its sound comes with its event)
                        }
                        else if (me_r != null && sim.Alive(me_r) && !sim.Recalling(me_r))
                            hud.Toast(me_r.pos.DistanceTo(Sim.Spawn(me_r.team)) < 8.0 ? "You're home already" : "Can't recall right now", new Color("#ffcf7a"));
                    }
                    break;
                case "ward":                                          // 0.31.158 5V5: a ward at your feet
                    if (sim != null)
                    {
                        if (sim.Act(hud.player_id, "ward"))
                            _Play("equip");
                        else
                            hud.Toast("No ward charge yet", new Color("#ffcf7a"));
                    }
                    break;
                default:
                    if (kind.BeginsWith("shop_buy:") || kind.BeginsWith("shop_sell:"))     // 0.31.157 5V5: the shop
                    {
                        bool ok = sim != null && sim.Act(hud.player_id, kind.BeginsWith("shop_buy:") ? "shop_buy" : "shop_sell",
                            kind.BeginsWith("shop_buy:") ? (object)kind.GetSlice(":", 1) : GD.Int(kind.GetSlice(":", 1)));
                        if (audio != null)
                            audio.Play(ok && kind.BeginsWith("shop_buy:") ? "purchase" : (ok ? "coin" : "error"));
                    }
                    break;
            }
        }

        public void _OnActionOnline(string kind)
        {
            // 0.31.170: the 5v5's buttons online -- the server does it (the next snapshots show it); here only what my copy of the
            // match can already tell: the same toasts and sounds as against bots when it can't be done, and the sound when it can
            Unit me = sim != null && sim.by_id.TryGetValue(hud.player_id, out var mu) ? mu : null;
            if (me == null || sim.ended)
                return;
            Action<string> play = (string cue) =>
            {
                if (audio != null)
                    audio.Play(cue);
            };
            switch (kind)
            {
                case "pick0":
                case "pick1":
                case "pick2":
                    {
                        var picks = me.picks;
                        if (picks == null || picks.Count == 0 || !sim.Alive(me))
                            return;                                   // (down: the server wouldn't take it, as against bots)
                        picks.RemoveAt(0);                            // (shown at once; the server's count follows)
                        _Act("pick", GD.Int(kind.Right(1)));
                        play("equip");
                        break;
                    }
                case "learn_q":
                case "learn_w":
                case "learn_e":
                case "learn_r":      // 0.31.217
                    if (sim.moba.CanLearn(me, kind.Right(1)))
                    {
                        _Act("learn", kind.Right(1));
                        play("equip");
                    }
                    break;
                case "ult":
                    if (sim.moba.UltRank(me) == 0)
                        hud.Toast(_LearnHint(me, "r"), new Color("#ffcf7a"));
                    else if (me.ult_cd <= 0.0 && sim.CanAct(me))
                        _Act("ult");
                    break;
                case "w":
                case "e":
                    if (!sim.moba.kits.Unlocked(me, kind))
                        hud.Toast(_LearnHint(me, kind), new Color("#ffcf7a"));
                    else if (V.ToDouble(me.Get("cd_" + kind)) <= 0.0 && sim.CanAct(me))
                        _Act("spell", kind);
                    break;
                case "recall":                                        // 0.31.181
                    if (sim.Alive(me) && !sim.Recalling(me) && sim.CanAct(me))
                        _Act("recall");
                    break;
                case "ward":
                    if (sim.moba.vision.WardReady(me))
                    {
                        _Act("ward");
                        play("equip");
                    }
                    else
                        hud.Toast("No ward charge yet", new Color("#ffcf7a"));
                    break;
                default:
                    if (kind.BeginsWith("shop_buy:"))
                    {
                        var id = kind.GetSlice(":", 1);
                        bool ok = sim.moba.BuyWhy(me, id) == "";
                        if (ok)
                            _Act("shop_buy", id);
                        play(ok ? "purchase" : "error");
                    }
                    else if (kind.BeginsWith("shop_sell:"))
                    {
                        var slot = GD.Int(kind.GetSlice(":", 1));
                        bool ok2 = sim.moba.CanShop(me) && slot >= 0 && slot < (me.items != null ? me.items.Count : 0);
                        if (ok2)
                            _Act("shop_sell", slot);
                        play(ok2 ? "coin" : "error");
                    }
                    break;
            }
        }

        // ---- Warm-up cover (Round 16, Kevin: the 3D world showed black for a few seconds at match start: the
        // phone compiling the scene's shader pipelines). A loading card covers the first moments while the
        // camera visits the key places so their materials compile behind it; it lifts once the engine's
        // pipeline-compilation counters have been still for WARM_STILL (never before WARM_MIN, at most
        // WARM_MAX). Offline the match clock waits. Skipped under scripted main loops (tests, render tools).
        // 0.31.208: the card is the loading screen (loading_screen.gd: the heroes on the plaza), not the castle wall's.
        public const double WARM_MIN = 0.6;
        public const double WARM_MAX = 10.0;
        public const double WARM_STILL = 0.5;
        public GDict _warm = new GDict();
        public bool _warm_done = false;
        public double warm_max = WARM_MAX;                   // (tools/hitch_bench.gd: longer, for a desktop's software renderer)
        public Control _cover = null;             // 0.31.208: the loading screen (loading_screen.gd), as the card
        public double _cover_t = 0.0;

        public LoadingScreen _LoadingScreen()
        {
            // 0.31.208: the loading screen, with my hero on its plaza in the outfit I wear on him
            LoadingScreen ls = new Loading();
            ls.audio = audio;
            ls.my_hero = _Hero();
            ls.my_skin = GD.Str(_Skins().Get(_Hero(), ""));
            ls.my_name = (clan_tag != "" ? GD.Fmt("[%s] ", clan_tag) : "") + Net.TitleText(player_name, MyTitle());
            return ls;
        }

        public void _CoverShow()
        {
            // The loading card over everything (the staged start builds the world behind it; the warm-up keeps it up).
            // 0.31.208: the loading screen (loading_screen.gd) in its loading state; the card on the castle wall until then.
            if (_cover != null)
                return;
            var t_card = Time.GetTicksMsec();
            var ls = _LoadingScreen();
            ls.Loading();
            AddChild(ls);
            _cover = ls;
            ready_times["card"] = Time.GetTicksMsec() - t_card;
        }

        public void _CoverTick(double delta)
        {
            _cover_t += delta;                  // (the loading screen moves its own dots)
        }

        public void _WarmBegin()
        {
            _warm_done = true;
            if (GetTree().GetScript() != null && !OS.HasEnvironment("FB_FORCE_WARMUP"))
            {
                if (_cover != null)
                {
                    _cover.QueueFree();
                    _cover = null;
                }
                return;
            }
            _CoverShow();
            var spots = new GArray();
            for (int t = 0; t < 2; t++)
            {
                foreach (var q in new[] { Keep.C, Keep.FOUNTAIN, Keep.GateC(1) + new Vector2(0.0, -6.0) })      // (0.31.165: the keeps)
                    spots.Append(Sim.M(t, q));
            }
            spots.Append(Vector2.ZERO);
            _warm = GDict.Of("cover", _cover, "t", 0.0, "last", -1, "still", 0.0, "spots", spots, "i", 0, "fade", -1.0, "fx", new GArray(), "pool", new GArray(), "fight", new GArray(), "shown", new GArray());
        }

        public bool _WarmStep(double delta)
        {
            // True while the match should wait behind the cover.
            var w = _warm;
            w["t"] = (double)w["t"] + delta;
            GArray spots = w["spots"].A;
            var i = GD.Int(w["i"]);
            if (i < spots.Size() * 2)
            {
                Vector2 p = spots[i / 2].V2;
                var y = Sim.HeightAt(p);
                view.cam_override = GArray.Of(new Vector3(p.x + 6.0, y + 16.0, p.y + 10.0), new Vector3(p.x, y, p.y));
                w["i"] = i + 1;
            }
            else if (i == spots.Size() * 2)
            {
                view.cam_override = new GArray();
                view.SnapCamera();
                w["i"] = i + 1;
                // 0.31.207 (Kevin: "The match keeps getting stutters"): with the camera on you, every look of this match's heroes
                // once (spell_fx.warm_jobs), then a wave's minion bodies into the view's pool (prefill_minions)
                if (view.fxs != null)
                    w["fx"] = view.fxs.WarmJobs(hud.player_id);
                if (sim.moba != null)
                {
                    w["fx"].A.AppendArray(view.WarmBodies(hud.player_id));
                    w["pool"] = view.PrefillMinions(GDict.Of("melee", 6, "caster", 6, "siege", 1));     // (two waves' worth: they overlap)
                    w["fight"] = view.WarmFight();                                       // (after: a pooled body falls)
                }
            }
            else
            {
                // a look a frame and the pool's bodies four a frame, then the fight (on a pooled body); what the view itself
                // makes for a look (smoke, blasts, roots, numbers) is noted, to hide when the card lifts
                GArray pool = w["pool"].A;
                for (int k = 0; k < 4; k++)
                {
                    if (!pool.IsEmpty())
                        pool.PopFront().As<Action>()();
                }
                GArray list = !w["fx"].A.IsEmpty() ? w["fx"].A : (pool.IsEmpty() ? w["fight"].A : new GArray());
                if (!list.IsEmpty())
                {
                    GArray shown = w["shown"].A;
                    Action<Node> grab = (Node n) => shown.Append(n);
                    view.ChildEnteredTree += grab;
                    list.PopFront().As<Action>()();
                    view.ChildEnteredTree -= grab;
                }
            }
            long c = 0;
            foreach (var k in new[] { RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
                    RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
                    RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION })
                c += RenderingServer.GetRenderingInfo(k);
            if (c != (long)w["last"])
            {
                w["last"] = c;
                w["still"] = 0.0;
            }
            else
                w["still"] = (double)w["still"] + delta;
            _CoverTick(delta);
            Control cover = w["cover"].As<Control>();
            if ((double)w["fade"] < 0.0)
            {
                bool jobs_done = w["fx"].A.IsEmpty() && w["pool"].A.IsEmpty() && w["fight"].A.IsEmpty();
                if ((GD.Int(w["i"]) > spots.Size() * 2 && jobs_done && (double)w["t"] >= WARM_MIN && (double)w["still"] >= WARM_STILL) || (double)w["t"] >= warm_max)
                {
                    w["fade"] = 0.0;
                    diag.Mark(GD.Fmt("warm-up %.1f s, %d pipeline compiles, %d looks shown, %d bodies pooled%s", (double)w["t"], c,
                        view.fxs != null ? GD.Int(view.fxs.warm_shown) : 0, view.PoolSize(), jobs_done ? "" : " (cut short)"));
                    _WarmClear();
                }
                return true;
            }
            w["fade"] = (double)w["fade"] + delta;
            var cm = cover.Modulate;
            cm.a = (float)GD.Clampf(1.0 - (double)w["fade"] / 0.3, 0.0, 1.0);
            cover.Modulate = cm;
            if ((double)w["fade"] >= 0.3)
            {
                cover.QueueFree();
                _cover = null;
                _warm = new GDict();
                return false;
            }
            return (double)w["fade"] < 0.15;
        }

        public void _WarmClear()
        {
            // the warm-up's looks gone before the match is seen (the view's own go on their timers, hidden till then)
            if (GD.IsInstanceValid(view) && view.fxs != null)
                view.fxs.ClearAll();
            if (GD.IsInstanceValid(view))
                view.WarmEnd();
            foreach (var n in _warm.Get("shown", new GArray()))
            {
                if (GD.IsInstanceValid(n) && n.Obj is Node3D n3 && !view.proj_nodes.Values().Has(n))
                    n3.Visible = false;
            }
            _warm["fx"] = new GArray();
            _warm["pool"] = new GArray();
            _warm["fight"] = new GArray();
        }

        protected override void _Process(double delta)
        {
            SimJoin();                             // 0.31.219 (done already at the end of the last frame's drawing, unless none was)
            _SimHook(async_sim && sim != null && !online);
            if (!_build_queue.IsEmpty())
            {
                _CoverTick(delta);
                _BuildStep();                      // the staged start: one step per frame behind the card
                if (!_build_queue.IsEmpty())
                    return;
                diag.Mark("built");
                diag.Write(GD.Fmt("MATCH BUILT ready=%s build=%s", GD.Str(ready_times), GD.Str(View.build_times)));
            }
            _ann_clock += delta;
            _AnnounceTick();
            if (online)
                _NetProcess(delta);
            if (sim == null)
                return;
            if (!_warm_done)
                _WarmBegin();
            if (!_warm.IsEmpty() && _WarmStep(delta))
            {
                view.proj_lead = 0.0;
                view.Sync(delta);
                return;
            }
            diag.Mark("input");
            _Footsteps(delta);
            _TitleTrack(delta);
            _Ambience(delta);
            var t_start = Time.GetTicksUsec();
            if (online)
            {
                // the server steps the match; _net_process applied the latest snapshot
            }
            else if ((!hud.Paused() && (tutorial_ui == null || !tutorial_ui.Holds())) || sim.ended)
            {
                sim.SetMove(hud.player_id, _MoveInput());
                Unit me_b = sim.by_id.TryGetValue(hud.player_id, out var mb) ? mb : null;
                if (hud.AbilityHeld() && me_b != null && sim.AbilityOf(me_b) == "block")
                    sim.Act(hud.player_id, "ability");
                if (hud.BlockHeld() && me_b != null)
                    sim.Act(hud.player_id, "block");
                if (hud.AttackHeld())
                {
                    Unit me = sim.by_id[hud.player_id];
                    if (sim.CanAct(me))
                        sim.Act(hud.player_id, "attack");
                }
                _accum += GD.Minf(delta, 0.1);
                diag.Mark("sim.step");
                var t_sim = Time.GetTicksUsec();
                while (_accum >= Sim.TICK)
                {
                    _accum -= Sim.TICK;
                    if (async_sim)
                        _sim_due += 1;                    // (run while this frame is drawn: _sim_launch)
                    else
                        sim.Step(Sim.TICK);
                }
                if (!async_sim)
                    diag.AddTime("sim", Time.GetTicksUsec() - t_sim);
                foreach (var e in sim.DrainEvents())
                {
                    diag.Mark("event " + e.K);
                    diag.Event(e);
                    _Count(e);
                    view.OnEvent(Net.WireEvent(e));
                    hud.OnEvent(e);
                    _EventSound(e);
                    if (tutorial_ui != null)
                        tutorial_ui.OnEvent(e);
                }
            }
            diag.Mark("view.sync");
            view.proj_lead = online ? 0.0 : _accum + _sim_due * Sim.TICK;   // online, projectiles interpolate (Net); (0.31.219:
                                                                           // and the ticks still to run, while it's drawn)
            var t_view = Time.GetTicksUsec();
            view.Sync(delta);
            diag.AddTime("view", Time.GetTicksUsec() - t_view);
            diag.Mark("process done");
            diag.AddTime("game", Time.GetTicksUsec() - t_start);
            if (sim.ended && !_result_shown)
            {
                _result_shown = true;
                diag.Write(GD.Fmt("MATCH END winner=%d reason=%s score=%s", sim.winner, sim.end_reason, GD.Str(GArray.From(sim.score))));
                GDict me = Net._UnitDict(sim.by_id[hud.player_id]);         // ((sim.by_id[...] as Dictionary).duplicate())
                me.Merge(TitleSummary(), true);
                bool won = sim.winner == GD.Int(me["team"]);
                bool draw = sim.winner == -1;
                if (tutorial && tutorial_ui != null)
                {
                    tutorial_ui.MatchOver(won);              // 0.31.217: the training's own end -- no match rewards
                    _ResultSounds(won, draw);
                    return;
                }
                match_result = new GDict();
                if (profile != null)
                {
                    match_result = profile.ApplyMatch(me, won, draw, online);
                    rewards = match_result["rewards"].D;
                }
                diag.Write(GD.Fmt("REWARDS %s", GD.Str(match_result.Get("rewards", new GDict()).D.Get("gold", 0))));
                hud.player_name = player_name;
                hud.ShowResult(match_result);
                _ResultSounds(won, draw);
                if (analytics != null && !online && _an_match != "")
                    analytics.LogEv("match_finish", GDict.Of("match", _an_match, "mode", "5v5", "dur_s", GD.Int(sim.time),
                        "result", won ? "win" : (draw ? "draw" : "loss"), "team_n", 1, "class", ClassOf(me), "class0", _an_class0));
            }
        }

        public void _ResultSounds(bool won, bool draw)
        {
            // 0.31.110 (Kevin: "more menu sound effects"): the results' stinger -- brass and drums for a win, low strings and a
            // horn for a loss (softly for a draw) -- then, once it's played out, a level up's arpeggio or a pass tier's chime
            if (audio == null)
                return;
            audio.Play(won ? "resultWin" : "resultLose", draw && !won);
            var next = "";
            if (!match_result.Get("levels", new GArray()).A.IsEmpty())
                next = "levelUp";
            else if (!match_result.Get("tiers", new GArray()).A.IsEmpty())
                next = "tierUp";
            if (next != "")
                GetTree().CreateTimer(1.6).Timeout += () =>
                {
                    if (!IsFreed)
                        _LateCue(next);
                };
        }

        public void _LateCue(string cue)
        {
            if (audio != null)
                audio.Play(cue);
        }

        // ---------- the tutorial (0.31.181) ----------
        public bool Warmed()
        {
            // the match is built and its warm-up cover is gone (the Herald waits for it)
            return _warm_done && _warm.IsEmpty() && _build_queue.IsEmpty();
        }

        public bool TutorialPays()
        {
            // its gold is still to come (Profile.finish_tutorial pays it once: Siege's tutorial before 0.31.164 counted)
            return profile != null && !(bool)profile.d.Get("tutorial_done", false);
        }

        public void _TutorialBegin()
        {
            tutorial_ui = new Training();
            tutorial_ui.Name = "Training";
            tutorial_ui.which = training;
            hud.AddChild(tutorial_ui);
            // over the HUD's drawing and its buttons' layer (0.31.219), under its pause button, panels and banners
            hud.MoveChild(tutorial_ui, hud.btn_layer != null ? hud.btn_layer.GetIndex() + 1 : 1);
            tutorial_ui.Begin(this);
            _tut_t0 = Time.GetTicksMsec();
            if (analytics != null)
                analytics.LogEv("tutorial_start", new GDict());
        }

        public void FinishTutorial()
        {
            // the Herald's last line tapped: the recruit's pay (once ever), and home
            if (_tut_done)
                return;
            _tut_done = true;
            var paid = false;
            if (profile != null)
                paid = (bool)profile.FinishTutorial().Get("ok", false);
            exit_note = paid ? "tutorial_paid" : "tutorial";
            if (analytics != null)
                analytics.LogEv("tutorial_complete", GDict.Of("dur_s", (Time.GetTicksMsec() - _tut_t0) / 1000));
            Exited?.Invoke();
        }

        public static string ClassOf(Unit u)
        {
            // 0.31.118: the class a unit plays, its upgrade marked ("knight", "knight+") -- as the server writes it
            return u == null ? "" : GD.Str(u.cls) + (u.up ? "+" : "");
        }

        // (class_of(me) of the results' unit Dictionary)
        public static string ClassOf(GDict u)
        {
            return GD.Str(u.Get("cls", "")) + ((bool)u.Get("up", false) ? "+" : "");
        }

        public void NoteLeaving()
        {
            // 0.31.118: the app is taking us down -- a VS BOTS match left before its end
            if (analytics == null)
                return;
            if (tutorial && !_tut_done && tutorial_ui != null)
                analytics.LogEv("tutorial_skip", GDict.Of("dur_s", (Time.GetTicksMsec() - _tut_t0) / 1000, "step", GD.Int(tutorial_ui.step),
                    "id", GD.Str(tutorial_ui.StepId())));
            if (!online && _an_match != "" && sim != null && !sim.ended)
                analytics.LogEv("match_quit", GDict.Of("match", _an_match, "mode", "bots", "quit_at_s", GD.Int(sim.time),
                    "class", ClassOf(sim.by_id.TryGetValue(hud.player_id, out var u) ? u : null), "class0", _an_class0));
        }

        public void SetFpsCap(int v)
        {
            fps_cap = v;
            Engine.MaxFps = v;
            if (diag != null)
                diag.Write(GD.Fmt("FPS CAP %d", v));
        }

        protected override void _ExitTree()
        {
            _sim_due = 0;                           // (leaving: nothing more to run -- only what's running waited for)
            SimJoin();
            _SimHook(false);
            Engine.MaxFps = _prev_max_fps;
            Engine.PhysicsTicksPerSecond = _prev_physics_tps;
            if (ws != null)
            {
                _NetSend(GDict.Of("t", "leave"));            // 0.31.120: quitting on purpose -- the server doesn't hold the seat
                ws.Close(1000, "leave");
                var closer = new SocketCloser();   // (polled until the close is out: this node is about to go)
                closer.ws = ws;
                if (IsInsideTree())
                {
                    var root = GetTree().Root;
                    CallDeferred(() => root.AddChild(closer));
                }
            }
        }

        public class SocketCloser : Node
        {
            // 0.31.120: keeps polling a closing socket for a moment so its "leave" and close frame reach the server
            public WebSocketPeer ws;
            public double t = 0.0;
            protected override void _Process(double delta)
            {
                t += delta;
                ws.Poll();
                if (ws.GetReadyState() == WebSocketPeer.STATE_CLOSED || t > 3.0)
                    QueueFree();
            }
        }

        public void RequestLeave()
        {
            // Android back button: open the pause panel rather than quitting a match outright.
            if (sim == null || GD.IsInstanceValid(lobby))
                Exited?.Invoke();                      // (0.31.82: still in the lobby -- nothing to pause; 0.31.209: or a PLAY AGAIN lobby)
            else if (hud.result_panel != null)
                Exited?.Invoke();
            else
            {
                hud.ShowPause();
                hud._Center(hud.pause_panel);
            }
        }
    }
}
