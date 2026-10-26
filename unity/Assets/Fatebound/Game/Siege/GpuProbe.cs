// Ported from godot/scripts/siege/gpu_probe.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector3 = Fatebound.Sim.Vec3;
using Color = Fatebound.GUI.Col;
using Environment = Fatebound.GUI.Environment;

namespace Fatebound.Game
{
    using View = Fatebound.Game.SiegeView;

    // 0.31.219 (Kevin: "Honor of kings gives me 120fps solid. This game I can hardly hit 30"): what each part of the picture
    // costs the phone's graphics chip, measured on the phone. The engine's own per-pass timings are only for its editor
    // profiler, so a test build switches one thing off for OFF_T seconds, measures the graphics chip's time on the 3D view
    // (gpu3d) and on the screen (gpuhud), switches it back and measures again right after: the difference is that thing's
    // cost, in the same fight. Two rounds of every test from START seconds into a 5v5 against bots, each written to the
    // match log as a PROBE line and summed up at the end (PROBE SUMMARY). The ones that would hide what you're playing
    // with (the HUD) wait until you're down. Off (never made) in the first training, headless, or with FB_NO_PROBE (0.31.220;
    // online and in the training's 5v5 too until then).
    public class GpuProbe : Node
    {
        public const double START = 40.0;          // match seconds before the first test (the first waves are fighting by then)
        public const double OFF_T = 2.0;
        public const double ON_T = 2.0;
        public const double SETTLE = 0.6;          // (the first part of each half not measured: the change shows a frame or two late)
        public const int ROUNDS = 2;
        public static readonly GArray TESTS = GArray.Of("none", "shadows", "hard_shadows", "glow", "msaa", "fog", "scale40", "terrain_plain", "plants", "outer", "vignette",
            "anim", "particles", "minimap", "hud");
        public static readonly GArray DEAD_ONLY = GArray.Of("hud");
        public static readonly GArray PLANT_KINDS = GArray.Of("ridges", "edge_trees", "brush", "foliage", "fords");
        public static readonly GArray OUTER_KINDS = GArray.Of("outer_land", "outer_trees");

        public SiegeMode mode;
        public GArray _queue = new GArray();
        public string _cur = "";
        public string _half = "";              // "off" | "on"
        public double _t = 0.0;
        public GArray _acc = GArray.Of(0.0, 0.0, 0, 0.0, 0.0, 0.0, 0.0);   // gpu3d, gpuhud, frames, seconds; ph_proc, ph_draw, ph_other (ms sums)
        public GArray _off = new GArray();
        public GDict _results = new GDict();   // test -> [[saves3d, saveshud], ...]
        public Action _restore;
        public Shader _plain = null;
        public bool _done = false;

        // 0.31.220: in every match but the first training (its lessons) -- Kevin's 0.31.219 and 0.31.220 logs had no PROBE
        // line at all (a training's 5v5, or an online one, had it off); whether it runs, and why not, is written as it starts
        // 0.31.222: its rounds done on Kevin's phone (0.31.221's log), off unless asked for (FB_PROBE, or ON) -- it switches
        // things off mid-match
        public const bool ON = false;

        public static string OffReason(SiegeMode m)
        {
            if (!ON && !OS.HasEnvironment("FB_PROBE"))
                return "not asked for";
            if (DisplayServer.GetName() == "headless")
                return "headless";
            if (OS.HasEnvironment("FB_NO_PROBE"))
                return "FB_NO_PROBE";
            if (RenderingServer.GetRenderingDevice() == null)
                return GD.Fmt("no RenderingDevice (%s)", RenderingServer.GetCurrentRenderingMethod());
            if (m.tutorial && (int)m.training == 1)
                return "the first training";
            return "";
        }

        public static bool Wanted(SiegeMode m)
        {
            return OffReason(m) == "";
        }

        public double _start = START;

        protected override void _Ready()
        {
            if (OS.HasEnvironment("FB_PROBE_START"))
                _start = GD.Float(OS.GetEnvironment("FB_PROBE_START"));       // (tools)
            for (int r = 0; r < ROUNDS; r++)
                _queue.AppendArray(TESTS);
            _Write(GD.Fmt("PROBE ready: %d tests from %.0f s into the match (%s)", _queue.Size(), _start,
                mode.online ? "online" : (mode.tutorial ? GD.Fmt("training %d", (int)mode.training) : "against bots")));
        }

        public bool _SimOk()
        {
            return mode != null && mode.sim != null && GD.IsInstanceValid(mode.view) && !mode.sim.ended;
        }

        protected override void _Process(double delta)
        {
            if (_done || !_SimOk())
                return;
            if (_cur == "")
            {
                if ((double)mode.sim.time < _start || !mode.Warmed())
                    return;
                _Next();
                return;
            }
            _t += delta;
            var settle = SETTLE + (_cur == "terrain_plain" ? 0.6 : 0.0);   // (its stand-in shader compiles first)
            if (_t >= settle)
            {
                RID v3 = mode.viewport.GetViewportRid();
                RID root = GetViewport().GetViewportRid();
                _acc[0] += RenderingServer.ViewportGetMeasuredRenderTimeGpu(v3);
                _acc[1] += RenderingServer.ViewportGetMeasuredRenderTimeGpu(root);
                _acc[2] += 1;
                _acc[3] += delta;
                GArray ph = mode.diag != null ? mode.diag.last_ph : GArray.Of(0, 0, 0);
                _acc[4] += (double)ph[0] / 1000.0;
                _acc[5] += (double)ph[1] / 1000.0;
                _acc[6] += (double)ph[2] / 1000.0;
            }
            if (_half == "off" && _t >= OFF_T)
            {
                _off = _acc.Duplicate();
                _Undo();
                _half = "on";
                _t = 0.0;
                _acc = GArray.Of(0.0, 0.0, 0, 0.0, 0.0, 0.0, 0.0);
            }
            else if (_half == "on" && _t >= ON_T)
            {
                _Report(_cur, _off, _acc);
                _cur = "";
                _Next();
            }
        }

        public void _Next()
        {
            // the next test that can run now (the HUD's waits until you're down)
            Unit me = mode.sim.by_id.TryGetValue(mode.hud.player_id, out var mu) ? mu : null;
            bool dead = me != null && GD.Str(me.state) == "dead" && (double)me.respawn_at - (double)mode.sim.time > OFF_T + ON_T;
            for (int i = 0; i < _queue.Size(); i++)
            {
                string name = _queue[i].AsString();
                if (DEAD_ONLY.Has(name) && !dead)
                    continue;
                _queue.RemoveAt(i);
                if (!_Apply(name))
                {
                    _Write(GD.Fmt("PROBE %s: skipped (already off here)", name));
                    return;
                }
                _cur = name;
                _half = "off";
                _t = 0.0;
                _acc = GArray.Of(0.0, 0.0, 0, 0.0, 0.0, 0.0, 0.0);
                return;
            }
            if (_queue.IsEmpty() || _queue.All(n => DEAD_ONLY.Has(n)) && (double)mode.sim.time > _start + 600.0)
                _Finish();
        }

        public bool _Apply(string name)
        {
            // switch it off; _restore switches it back -> false when it's off already (nothing to measure)
            var view = mode.view;
            switch (name)
            {
                case "none":
                    _restore = () => { };            // (nothing switched: how much two halves differ by themselves -- the noise)
                    break;
                case "shadows":
                case "hard_shadows":
                {
                    var sun = _Sun();
                    if (sun == null || !sun.ShadowEnabled)
                        return false;
                    if (name == "shadows")
                    {
                        sun.ShadowEnabled = false;
                        _restore = () => { sun.ShadowEnabled = true; };
                    }
                    else
                    {
                        // (0.31.222: the match's own filter is hard now -- this measures the soft one it had, switched ON)
                        RenderingServer.DirectionalSoftShadowFilterSetQuality(RenderingServer.SHADOW_QUALITY_SOFT_LOW);
                        _restore = () => { RenderingServer.DirectionalSoftShadowFilterSetQuality(View.SHADOW_QUALITY); };
                    }
                    break;
                }
                case "glow":
                case "fog":
                {
                    var env = _Env();
                    if (env == null)
                        return false;
                    if (name == "glow")
                    {
                        if (!env.GlowEnabled)
                            return false;
                        env.GlowEnabled = false;
                        _restore = () => { env.GlowEnabled = true; };
                    }
                    else
                    {
                        if (!env.FogEnabled)
                            return false;
                        env.FogEnabled = false;
                        _restore = () => { env.FogEnabled = true; };
                    }
                    break;
                }
                case "msaa":
                {
                    int was = mode.viewport.Msaa3D;
                    if (was == Viewport.MSAA_DISABLED)
                        return false;
                    mode.viewport.Msaa3D = Viewport.MSAA_DISABLED;
                    _restore = () => { mode.viewport.Msaa3D = was; };
                    break;
                }
                case "scale40":
                {
                    double rs = mode.render_scale;
                    mode.SetRenderScale(rs * 0.8);                  // (50 % -> 40 %: the share of the cost that goes with pixels)
                    _restore = () => { mode.SetRenderScale(rs); };
                    break;
                }
                case "terrain_plain":
                {
                    ShaderMaterial tm = View._terrain_mat;
                    if (tm == null)
                        return false;
                    if (_plain == null)
                    {
                        _plain = new Shader();
                        _plain.Code = "shader_type spatial;\nrender_mode specular_disabled;\nvoid fragment() { ALBEDO = vec3(0.24, 0.36, 0.2); ROUGHNESS = 0.95; }\n";
                    }
                    Shader sh = tm.Shader;
                    tm.Shader = _plain;
                    _restore = () => { tm.Shader = sh; };
                    break;
                }
                case "plants":
                case "outer":
                {
                    GArray kinds = name == "plants" ? PLANT_KINDS : OUTER_KINDS;
                    var hid = new GArray();
                    foreach (var c in view.GetChildren())
                    {
                        if (c is Node3D && (c as Node3D).Visible && c.HasMeta("perf") && kinds.Has(GD.Str(Var.Of(c.GetMeta("perf"))).TrimSuffix("_shadow")))
                        {
                            (c as Node3D).Visible = false;
                            hid.Append(c);
                        }
                    }
                    if (hid.IsEmpty())
                        return false;
                    _restore = () =>
                    {
                        foreach (var c in hid)
                        {
                            if (GD.IsInstanceValid(c))
                                c.As<Node3D>().Visible = true;
                        }
                    };
                    break;
                }
                case "vignette":
                {
                    CanvasItem vg = mode.vignette;
                    if (vg == null || !vg.Visible)
                        return false;
                    vg.Visible = false;
                    _restore = () => { vg.Visible = true; };
                    break;
                }
                case "anim":
                    view.anim_freeze = true;                  // (every body's animation still for a moment: what animating costs)
                    _restore = () => { view.anim_freeze = false; };
                    break;
                case "particles":
                {
                    var stopped = new GArray();
                    foreach (var n in view.FindChildren("*", "GPUParticles3D", true, false))
                    {
                        var gp = n as GPUParticles3D;
                        if (gp.Emitting)
                        {
                            gp.Emitting = false;
                            gp.Restart();
                            gp.Emitting = false;
                            stopped.Append(gp);
                        }
                    }
                    if (stopped.IsEmpty())
                        return false;
                    _restore = () =>
                    {
                        foreach (var gp in stopped)
                        {
                            if (GD.IsInstanceValid(gp))
                                gp.As<GPUParticles3D>().Emitting = true;
                        }
                    };
                    break;
                }
                case "minimap":
                {
                    CanvasItem mm = mode.hud.minimap;
                    if (mm == null || !mm.Visible)
                        return false;
                    mm.Visible = false;
                    _restore = () => { mm.Visible = true; };
                    break;
                }
                case "hud":
                {
                    CanvasItem h = mode.hud;
                    if (!h.Visible)
                        return false;
                    h.Visible = false;
                    _restore = () => { h.Visible = true; };
                    break;
                }
                default:
                    return false;
            }
            return true;
        }

        public void _Undo()
        {
            if (_restore != null)
                _restore();
            _restore = null;
        }

        public DirectionalLight3D _Sun()
        {
            foreach (var n in mode.view.FindChildren("*", "DirectionalLight3D", true, false))
                return n as DirectionalLight3D;
            return null;
        }

        public Environment _Env()
        {
            foreach (var n in mode.view.FindChildren("*", "WorldEnvironment", true, false))
                return (n as WorldEnvironment).Environment;
            return null;
        }

        public void _Report(string name, GArray off, GArray on)
        {
            var fo = GD.Maxf(1.0, (double)off[2]);
            var fn = GD.Maxf(1.0, (double)on[2]);
            var o3 = (double)off[0] / fo;
            var oh = (double)off[1] / fo;
            var n3 = (double)on[0] / fn;
            var nh = (double)on[1] / fn;
            GArray r = _results.Get(name, new GArray()).A;
            r.Append(GArray.Of(n3 - o3, nh - oh));
            _results[name] = r;
            var op = GArray.Of((double)off[4] / fo, (double)off[5] / fo, (double)off[6] / fo);
            var np = GArray.Of((double)on[4] / fn, (double)on[5] / fn, (double)on[6] / fn);
            r[r.Size() - 1].A.AppendArray(GArray.Of(np[0] - op[0], np[1] - op[1], np[2] - op[2]));
            _Write(GD.Fmt("PROBE %s: off gpu3d %.1f gpuhud %.1f cpu %.1f/%.1f/%.1f ms %.0f fps | on gpu3d %.1f gpuhud %.1f cpu %.1f/%.1f/%.1f ms %.0f fps | gpu %.1f + %.1f, cpu proc %.1f draw %.1f other %.1f ms", name,
                o3, oh, op[0], op[1], op[2], (double)off[2] / GD.Maxf(0.01, (double)off[3]), n3, nh, np[0], np[1], np[2], (double)on[2] / GD.Maxf(0.01, (double)on[3]),
                n3 - o3, nh - oh, np[0] - op[0], np[1] - op[1], np[2] - op[2]));
        }

        public void _Finish()
        {
            _done = true;
            var parts = new List<string>();
            foreach (var name in TESTS)
            {
                GArray r = _results.Get(name, new GArray()).A;
                if (r.IsEmpty())
                    continue;
                var sums = GArray.Of(0.0, 0.0, 0.0, 0.0, 0.0);
                foreach (var x in r)
                {
                    for (int i = 0; i < GD.Mini(5, x.A.Size()); i++)
                        sums[i] += (double)x[i];
                }
                var k = (double)r.Size();
                parts.Add(GD.Fmt("%s gpu %.1f+%.1f cpu %.1f/%.1f/%.1f", name, sums[0] / k, sums[1] / k, sums[2] / k, sums[3] / k, sums[4] / k));
            }
            _Write(GD.Fmt("PROBE SUMMARY (ms a frame each costs, mean of the rounds run -- gpu: 3D + screen; cpu: process / drawing / other): %s", GStr.Join(", ", parts)));
        }

        public void _Write(string line)
        {
            if (mode != null && mode.diag != null)
                mode.diag.Write(line);
        }

        protected override void _ExitTree()
        {
            _Undo();                                // (a test running as the match ends: everything back as it was)
            if (!_results.IsEmpty())
                _Finish();                          // (0.31.220: again at the match's end -- the log sent is its last lines)
        }
    }
}
