// Ported from godot/scripts/siege/siege_hud.gd (Fatebound 0.31.222).
// The .gd in three partial files, each in the .gd's order: SiegeHud.cs (the fields, quick chat, panels, the results, the
// scoreboard and MVP, toasts and the match's events, input), SiegeHud.Draw.cs (drawing: the top layer, the buttons, the
// score bar, the kill feed, the 5v5's status, bars, names over heads, numbers, the button states), SiegeHud.Shop.cs (gold,
// the shop, the live scoreboard, the quick-buy, the jungle's timers).
using System;
using System.Collections;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector3 = Fatebound.Sim.Vec3;
using Color = Fatebound.GUI.Col;

namespace Fatebound.Game
{
    using Sim_Eco = Fatebound.Game.Economy;
    using UI = Fatebound.Game.Ui;
    using UI2 = Fatebound.Game.Ui2;
    using Sim = Fatebound.Sim.SiegeSim;
    using NetT = Fatebound.Game.SiegeNet;
    using CrestT = Fatebound.Game.Crest;     // 0.31.196: clan crests by the names
    using Moba = Fatebound.Sim.Moba;
    using Kits = Fatebound.Sim.MobaKits;       // 0.31.176: the live scoreboard's roles
    using View = Fatebound.Game.SiegeView;

    // The match HUD. The stick and the combat buttons are drawn and hit-tested by hand from raw
    // InputEventScreenTouch events, because Godot's Buttons only follow the first finger and on a
    // phone you hold the stick while tapping ATTACK. Modal panels (pause, result, shop) use Buttons.
    public partial class SiegeHud : Control
    {
        // The old brass kinds map onto the app's tactile styles so battle panels match the menus.
        public static readonly GDict BUTTON_STYLE = GDict.Of("primary", "orange", "secondary", "blue", "gold", "gold", "roll", "gold", "active", "green", "danger", "red");   // 0.31.79: the menu skins

        public event Action LeaveRequested;
        public event Action ReplayRequested;
        public event Action<string> ActionPressed;
        public event Action<int> QuickChat;              // 0.31.111: a line from the quick chat wheel (NetT.QUICK_CHAT index)

        public static readonly Color[] TEAM_COLORS = { new Color("#5fd2f0"), new Color("#ff7b52"), new Color("#e2c85c") };      // (0.31.157: the jungle's monsters)

        public SiegeSim sim;
        public SiegeDiag diag;
        public StyleBox _bar_style;
        public string player_id = "you";
        public string player_name = "Player";         // (0.31.87: the results panel shows an earned title on it)

        public int Vt(int t)
        {
            // 0.31.85: your side drawn blue, the other red, whichever team you're on (as siege_view.vt)
            if (t < 0 || t > 1 || sim == null)
                return t;
            return (sim.by_id.TryGetValue(player_id, out var me) ? me.team : 0) == 0 ? t : 1 - t;
        }
        public Func<Vector3, Vector2> project;          // world Vector3 -> HUD Vector2
        public Func<Vector3, bool> on_screen;           // world Vector3 -> bool
        public Func<GArray> numbers_source;             // -> Array of {pos, text, mine, at} from the 3D view
        public Func<GArray> bars_source;                // -> Array of {pos, fill, color} for 2D health bars
        public Func<double> numbers_clock;              // -> float, the view clock those "at" values use

        public bool _touchscreen = false;
        public GDict _touches = new GDict();             // index -> role
        public Vector2 _stick_origin = Vector2.ZERO;
        public Vector2 _stick_pos = Vector2.ZERO;
        public bool _stick_active = false;
        public bool _attack_held = false;
        public bool _ability_held = false;
        public bool _block_held = false;            // 0.31.61: the Crusader's shield button
        public GDict _pressed_at = new GDict();
        public string _toast = "";
        public Control minimap = null;              // 0.31.216 (minimap.gd)
        // 0.31.216 (Kevin: "The game needs to change from vertical to horizontal", Honor of Kings' HUD): the landscape layout --
        // the map top-left with your level, gold-and-shop and items under it; the score bar small in the top middle; pause and
        // quick chat top-right with the kill feed under them; the stick anywhere on the left half; ATTACK bottom-right with Q,
        // W, E and R in an arc round it and DODGE, WARD and HOME in a row to their left.
        public static readonly Rect2 MAP_RECT = new Rect2(8, 8, 132, 132);
        public const double BAR_W = 470.0;
        public const double BAR_H = 46.0;
        public KillBanner kill_banner = null;         // 0.31.180: the kill banners (kill_banner.gd; until then a DOUBLE KILL label of yours)
        public bool tut_modal = false;                   // 0.31.181: the tutorial's Herald is talking -- the match's buttons and stick wait
        public double _toast_at = -10.0;
        public GDict net_names = new GDict();             // 0.31.119: online, unit id -> player name (the server's "pn"), for the scoreboard
        public PanelContainer score_panel = null;
        public double rejoin_until = -1.0;            // 0.31.120: reconnecting after a dropped connection, until (ticks clock)
        public double idle_kick_at = -1.0;            // 0.31.119: online, a bot plays for me (I was idle); when I'll be removed (s, ticks clock)
        public Color _toast_color = Color.WHITE;
        public double _time = 0.0;
        public Font _font;
        public Font _bold;
        public Font _title;

        public Func<GArray> gate_bars_source;   // -> Array of {pos, fill, color, broken}
        public PanelContainer pause_panel;
        public PanelContainer result_panel;
        public Button pause_btn;
        // 0.31.111 (Kevin: "add the quick chat pings"): the horn beside the pause button opens the quick chat; a line said shows
        // as a bubble over the speaker (pinned to the screen edge, with an arrow, when they're off it) and in a short feed.
        public Button qc_btn;
        public PanelContainer qc_panel;
        public Func<string, Vector3> unit_world;              // unit id -> its world position (Vector3.INF when unknown)
        public GArray _pings = new GArray();                // {"u", "i", "at"}
        public GArray _feed = new GArray();                 // {"n", "i", "at", "col"}
        public const double PING_LIFE = 4.0;
        public const double FEED_LIFE = 6.0;

        public static GDict ready_times = new GDict();

        public SiegeHud()
        {
            _ci = this;
        }

        protected override void _Ready()
        {
            var t0 = Time.GetTicksMsec();
            SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            MouseFilter = Control.MOUSE_FILTER_IGNORE;
            _touchscreen = DisplayServer.IsTouchscreenAvailable();
            _font = VisualTheme.BODY_FONT;
            _bold = VisualTheme.BOLD_FONT;
            _title = VisualTheme.TITLE_FONT;
            pause_btn = UI2.Button(this, "II", "blue", () =>
            {
                if (pause_panel == null)
                    _BuildPausePanel();
                pause_panel.Visible = true;
                _Center(pause_panel, true);
            }, "", 16, 40.0, 12.0);
            pause_btn.CustomMinimumSize = new Vector2(44, 40);
            pause_btn.Size = new Vector2(44, 40);
            qc_btn = UI2.Button(this, "", "purple", () => _ToggleQc(), "quick_chat", 14, 46.0, 14.0, UI2.IconPath("horn"));
            qc_btn.CustomMinimumSize = new Vector2(46, 46);
            qc_btn.Size = new Vector2(46, 46);
            qc_btn.AddThemeConstantOverride("icon_max_width", 34);
            // 0.31.160: the scoreboard and the status lines under it on a layer of their own (_draw_top), drawn again only when
            // what they show changes (_top_parts) -- they were a third of the HUD's 7 ms a frame on Kevin's phone. Behind the
            // HUD's own drawing, as they were drawn first.
            _top_layer = new Control();
            _top_layer.Name = "TopLayer";
            _top_layer.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            _top_layer.ShowBehindParent = true;
            _top_layer.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            _top_layer.Draw += _DrawTopLayer;
            AddChild(_top_layer);
            MoveChild(_top_layer, 0);
            // 0.31.219 (Kevin's 0.31.218 log: the HUD 5-7 ms a frame on his phone, the stick and the buttons nearly half of it):
            // the stick, the skill buttons and their + marks on a layer of their own, over the HUD's own drawing (as they were
            // drawn last). 0.31.220: each on a canvas item of its own, drawn again only when what it shows changes (_btn_tick).
            btn_layer = new Control();
            btn_layer.Name = "BtnLayer";
            btn_layer.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            btn_layer.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            AddChild(btn_layer);
            MoveChild(btn_layer, 1);
            var mm = new Minimap();                        // 0.31.216: the landscape HUD's map, top-left
            mm.Name = "Minimap";
            mm.hud = this;
            minimap = mm;
            AddChild(minimap);
            MoveChild(minimap, 2);
            kill_banner = new KillBanner();                 // 0.31.180: over the match and the buttons, under the panels
            kill_banner.Name = "KillBanner";
            kill_banner.hud = this;
            AddChild(kill_banner);
            // 0.31.8: the pause panel is built the first time it opens.
            Resized += _Layout;
            _Layout();
            ready_times["hud _ready total"] = Time.GetTicksMsec() - t0;
        }

        public void _Layout()
        {
            pause_btn.Position = new Vector2(Size.x - 52, 8);
            qc_btn.Position = new Vector2(Size.x - 104, 5);             // (left of the pause button)
            if (qc_panel != null)
                qc_panel.Position = new Vector2(Size.x - qc_panel.Size.x - 10, 58);
            if (minimap != null)
            {
                minimap.Position = MAP_RECT.position;
                minimap.Size = MAP_RECT.size;
            }
        }

        // ---------------- quick chat (0.31.111) ----------------
        public void _ToggleQc()
        {
            if (qc_panel == null)
            {
                qc_panel = new PanelContainer();
                var sb = new StyleBoxFlat();
                sb.BgColor = new Color(0.03, 0.05, 0.14, 0.92);
                sb.BorderColor = new Color("#c47bff");
                sb.SetBorderWidthAll(2);
                sb.SetCornerRadiusAll(16);
                sb.ContentMarginLeft = 8;
                sb.ContentMarginRight = 8;
                sb.ContentMarginTop = 8;
                sb.ContentMarginBottom = 8;
                qc_panel.AddThemeStyleboxOverride("panel", sb);
                AddChild(qc_panel);
                var g = new GridContainer();
                g.Columns = 2;
                g.AddThemeConstantOverride("h_separation", 6);
                g.AddThemeConstantOverride("v_separation", 6);
                qc_panel.AddChild(g);
                for (int i = 0; i < NetT.QUICK_CHAT.Size(); i++)
                {
                    GDict q = NetT.QUICK_CHAT[i].D;
                    var ii = i;
                    var b = UI2.Button(g, GD.Str(q["x"]).ToUpperInvariant(), GD.Str(q["x"]) == "Need help!" ? "red" : ((bool)q.Get("all", false) ? "purple" : "blue"), () =>
                    {
                        qc_panel.Visible = false;
                        QuickChat?.Invoke(ii);
                    }, GD.Fmt("qc_%d", i), 13, 40.0, 12.0);
                    var bm = b.CustomMinimumSize;
                    bm.x = 132;
                    b.CustomMinimumSize = bm;
                }
                qc_panel.Visible = false;
            }
            qc_panel.Visible = !qc_panel.Visible;
            qc_panel.ResetSize();
            _Layout();
        }

        public void AddPing(string unit, int i, string name)
        {
            // a quick chat line from `unit` (name "" for an unnamed bot -- only players speak, so it's always someone)
            if (i < 0 || i >= NetT.QUICK_CHAT.Size())
                return;
            _pings = _pings.Filter(p => GD.Str(p["u"]) != unit);
            _pings.Append(GDict.Of("u", unit, "i", i, "at", _time));
            Unit u = sim != null && sim.by_id.TryGetValue(unit, out var uu) ? uu : null;
            Unit me = sim != null && sim.by_id.TryGetValue(player_id, out var mu) ? mu : null;
            Color col = unit == player_id ? new Color("#8cf0a8") : (u != null ? TEAM_COLORS[Vt(u.team)] : Color.WHITE);
            _feed.Append(GDict.Of("n", name != "" ? name : "Ally", "i", i, "at", _time, "col", col, "enemy", u != null && me != null && u.team != me.team));
            while (_feed.Size() > 3)
                _feed.PopFront();
        }

        public void _DrawPings()
        {
            _pings = _pings.Filter(p => _time - (double)p["at"] < PING_LIFE);
            _feed = _feed.Filter(f => _time - (double)f["at"] < FEED_LIFE);
            var vp = new Rect2(new Vector2(MAP_RECT.End.x + 10.0, 70), Size - new Vector2(MAP_RECT.End.x + 160.0, 170));     // (0.31.216: landscape)
            foreach (var p in _pings)
            {
                if (unit_world == null || project == null)
                    break;
                Vector3 w3 = unit_world(GD.Str(p["u"]));
                if (w3 == Vector3.INF)
                    continue;
                GDict q = NetT.QUICK_CHAT[GD.Int(p["i"])].D;
                var age = _time - (double)p["at"];
                var a = GD.Clampf(GD.Minf(age * 6.0, (PING_LIFE - age) * 2.0), 0.0, 1.0);
                Vector3 anchor = w3 + new Vector3(0, 2.7, 0);
                bool inside = on_screen != null && on_screen(anchor);
                Vector2 sp = inside ? project(anchor) : Vector2.ZERO;
                var txt = GD.Str(q["x"]);
                var tw = _bold.GetStringSize(txt, HorizontalAlignment.Left, -1, 15).x;
                var box = new Vector2(tw + 22.0, 28.0);
                var col = Color.FromCode(GD.Str(q["c"]));
                Vector2 pos;
                var arrow = Vector2.ZERO;
                if (inside)
                {
                    pos = sp + new Vector2(-box.x * 0.5, -box.y - 46.0 - (1.0 - GD.Minf(age * 5.0, 1.0)) * 10.0);
                    pos.x = (float)GD.Clampf(pos.x, 6.0, Size.x - box.x - 6.0);          // (someone at the edge: the bubble stays on the screen)
                }
                else
                {
                    // off the screen: on its edge, toward them, with an arrow
                    Vector3 me3 = unit_world(player_id);
                    var dir = me3 != Vector3.INF ? new Vector2(w3.x - me3.x, w3.z - me3.z) : new Vector2(0, -1);
                    var up = View.ScreenUp(sim.by_id.TryGetValue(player_id, out var pu) ? pu.team : 0);     // (0.31.216: the yawed camera)
                    dir = new Vector2(dir.Dot(new Vector2(-up.y, up.x)), -dir.Dot(up));
                    dir = dir.Length() > 0.01 ? dir.Normalized() : new Vector2(0, -1);
                    var c = vp.GetCenter();
                    var k = GD.Minf(Math.Abs(vp.size.x * 0.5 / GD.Maxf(Math.Abs(dir.x), 0.001)), Math.Abs(vp.size.y * 0.5 / GD.Maxf(Math.Abs(dir.y), 0.001)));
                    var edge = c + dir * k;
                    pos = new Vector2(GD.Clampf(edge.x - box.x * 0.5, vp.position.x, vp.End.x - box.x), GD.Clampf(edge.y - box.y * 0.5, vp.position.y, vp.End.y - box.y));
                    arrow = dir;
                }
                var r = new Rect2(pos, box);
                var bg = new StyleBoxFlat();
                bg.BgColor = new Color(0.03, 0.04, 0.1, 0.88 * a);
                bg.BorderColor = new Color(col, a);
                bg.SetBorderWidthAll(2);
                bg.SetCornerRadiusAll(12);
                DrawStyleBox(bg, r);
                if (inside)
                {
                    var tip = new Vector2(GD.Clampf(sp.x, r.position.x + 12.0, r.End.x - 12.0), r.End.y);
                    DrawColoredPolygon(new List<Vector2> { tip + new Vector2(-7, -1), tip + new Vector2(7, -1), tip + new Vector2(0, 9) }, new Color(col, a));
                }
                else
                {
                    var tip2 = r.GetCenter() + arrow * (GD.Maxf(box.x, box.y) * 0.5 + 10.0);
                    var side = new Vector2(-arrow.y, arrow.x) * 7.0;
                    DrawColoredPolygon(new List<Vector2> { tip2, tip2 - arrow * 11.0 + side, tip2 - arrow * 11.0 - side }, new Color(col, a));
                }
                DrawStringOutline(_bold, r.position + new Vector2(11, 20), txt, HorizontalAlignment.Left, -1, 15, 4, new Color(0, 0, 0, 0.7 * a));
                DrawString(_bold, r.position + new Vector2(11, 20), txt, HorizontalAlignment.Left, -1, 15, new Color(col.Lightened(0.25), a));
            }
            var y = MAP_RECT.End.y + 128.0;                         // (0.31.216: under the map's column on the left; 210 in portrait)
            foreach (var f in _feed)
            {
                var a2 = GD.Clampf((FEED_LIFE - (_time - (double)f["at"])) * 1.5, 0.0, 1.0);
                GDict q2 = NetT.QUICK_CHAT[GD.Int(f["i"])].D;
                var nm = GD.Str(f["n"]) + ": ";
                var nw = _bold.GetStringSize(nm, HorizontalAlignment.Left, -1, 13).x;
                DrawStringOutline(_bold, new Vector2(14, y), nm, HorizontalAlignment.Left, -1, 13, 4, new Color(0, 0, 0, 0.7 * a2));
                DrawString(_bold, new Vector2(14, y), nm, HorizontalAlignment.Left, -1, 13, new Color(f["col"].As<Color>(), a2));
                DrawStringOutline(_bold, new Vector2(14 + nw, y), GD.Str(q2["x"]), HorizontalAlignment.Left, -1, 13, 4, new Color(0, 0, 0, 0.7 * a2));
                DrawString(_bold, new Vector2(14 + nw, y), GD.Str(q2["x"]), HorizontalAlignment.Left, -1, 13, new Color(Color.FromCode(GD.Str(q2["c"])).Lightened(0.3), a2));
                y += 18.0;
            }
        }

        // ---------- panels ----------
        public PanelContainer _Panel(double min_w, string kind = "night")
        {
            // 0.31.79: a gold-framed damask (or parchment) panel, like the menus
            var p = new PanelContainer();
            var ps = new StyleBoxEmpty();
            ps.ContentMarginLeft = 20;
            ps.ContentMarginRight = 20;
            ps.ContentMarginTop = 18;
            ps.ContentMarginBottom = 18;
            p.AddThemeStyleboxOverride("panel", ps);
            p.CustomMinimumSize = new Vector2(min_w, 0);
            p.Visible = false;
            AddChild(p);
            UI2.Plate(p, kind, 22.0, kind == "parch" ? "brown" : "gold", GDict.Of("rim", 4.0, "shadow_y", 10.0, "shadow_alpha", 0.7, "shadow_soft", 12.0));
            return p;
        }

        public void _Unroll(Control p)
        {
            // the panel drops open from the top
            var fit = Convert.ToDouble(p.GetMeta("fit", 1.0));
            p.PivotOffset = new Vector2(p.Size.x * 0.5, 0);
            p.Scale = new Vector2(fit, fit * 0.15);
            var m = p.Modulate;
            m.a = 0.0f;
            p.Modulate = m;
            var tw = p.CreateTween().SetParallel();
            tw.TweenProperty(p, "scale", Vector2.ONE * fit, 0.32).SetTrans(Tween.TRANS_BACK).SetEase(Tween.EASE_OUT);
            tw.TweenProperty(p, "modulate:a", 1.0, 0.15);
        }

        public Label _Label(Node parent, string text, int size_px, Color color, Font font = null)
        {
            var l = new Label();
            l.Text = text;
            l.HorizontalAlignment = HorizontalAlignment.Center;
            l.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
            l.CustomMinimumSize = new Vector2(290, 0);
            l.AddThemeFontSizeOverride("font_size", size_px);
            l.AddThemeColorOverride("font_color", UI.Ink(color));       // (0.31.195: no yellow text)
            if (font != null)
                l.AddThemeFontOverride("font", font);
            parent.AddChild(l);
            return l;
        }

        public Button _Button(Node parent, string text, string kind, Action cb)
        {
            var b = UI2.Button(parent, text, GD.Str(BUTTON_STYLE.Get(kind, "blue")), cb, "", 17, 50.0, 14.0);
            b.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            b.ClipText = true;
            return b;
        }

        public void _Center(Control p, bool unroll = false)
        {
            // wrapping labels report no width until laid out, so give them one (else a panel measures them a letter wide)
            foreach (var n in p.FindChildren("*", "Label", true, false))
            {
                var l = (Label)n;
                if (l.AutowrapMode != TextServer.AUTOWRAP_OFF && l.CustomMinimumSize.x < 1.0)
                {
                    var cm = l.CustomMinimumSize;
                    cm.x = 200.0f;
                    l.CustomMinimumSize = cm;
                }
            }
            // re-placed whenever its measured size settles (the labels learn their heights a frame or two later)
            if (!p.HasMeta("placed"))
            {
                p.SetMeta("placed", true);
                p.MinimumSizeChanged += () =>
                {
                    if (GD.IsInstanceValid(p) && p.Visible)
                        CallDeferred(() => _Place(p));
                };
            }
            _Place(p);
            if (unroll)
            {
                var m = p.Modulate;
                m.a = 0.0f;
                p.Modulate = m;
                if (IsInsideTree())
                {
                    var t = GetTree().CreateTimer(0.05);
                    var pref = new WeakRef(p);       // (0.31.144: held weakly -- a freed panel in a lambda logs an error)
                    t.Timeout += () =>
                    {
                        var pp = pref.GetRef() as Control;
                        if (pp != null)
                        {
                            _Place(pp);
                            _Unroll(pp);
                        }
                    };
                }
            }
        }

        public void _Place(Control p)
        {
            p.Size = new Vector2(GD.Minf(p.CustomMinimumSize.x, Size.x - 20), 0);
            p.ResetSize();
            // 0.31.79: a panel taller than the screen (a long results list) is shrunk to fit rather than cut off
            var fit = GD.Minf(1.0, (Size.y - 24.0) / GD.Maxf(1.0, p.Size.y));
            p.SetMeta("fit", fit);
            p.PivotOffset = new Vector2(p.Size.x * 0.5, 0);
            p.Scale = Vector2.ONE * fit;
            p.Position = new Vector2((Size.x - p.Size.x) * 0.5, GD.Maxf(12.0, (Size.y - p.Size.y * fit) * 0.5));
        }

        public bool Paused()
        {
            return pause_panel != null && pause_panel.Visible;
        }

        public void ShowPause()
        {
            CloseBoard();
            if (pause_panel == null)
                _BuildPausePanel();
            pause_panel.Visible = true;
            _Center(pause_panel, true);
        }

        public void _BuildPausePanel()
        {
            // 0.31.79: a parchment sheet -- how to win in three steps with the 3D icons, the tricks, then RESUME.
            pause_panel = _Panel(330, "parch");
            var ink = new Color("#3b2412");
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", 8);
            pause_panel.AddChild(v);
            UI2.Center(UI2.Text(v, "PAUSED", 38, UI2.GOLD, ink, 9));
            var hw = UI.Label(v, "HOW TO WIN", 11, new Color("#8a6a44"), UI.HEAVY_FONT);
            hw.HorizontalAlignment = HorizontalAlignment.Center;
            foreach (var st in GArray.Of(GArray.Of("castle", "1 · PUSH A LANE", "Bring down its towers, then a gate of their keep"), GArray.Of("swords", "2 · THE KING'S TOWERS", "Inside, the two towers guarding their King"),
                    GArray.Of("crown", "3 · DEFEAT THEIR KING", "wins the match")))
            {
                var r = new HBoxContainer();
                r.AddThemeConstantOverride("separation", 10);
                v.AddChild(r);
                var disc = new Control();
                disc.CustomMinimumSize = new Vector2(50, 50);
                r.AddChild(disc);
                UI2.Plate(disc, "parch", 25.0, "gold", GDict.Of("rim", 3.0, "shadow_y", 3.0, "pattern_mix", 0.0, "fill_top", new Color("#fff8e0"), "fill_bottom", new Color("#e9cf94")));
                var ic = UI2.Icon(disc, GD.Str(st[0]), 40.0);
                ic.Position = new Vector2(5, 3);
                var tv = new VBoxContainer();
                tv.AddThemeConstantOverride("separation", 0);
                tv.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
                r.AddChild(tv);
                UI2.Text(tv, GD.Str(st[1]), 15, ink, ink, 0, false);
                var sl = UI.Label(tv, GD.Str(st[2]), 12, new Color("#5d3a1c"), UI.HEAVY_FONT);
                sl.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
            }
            var tricks = UI.Label(v, "Walk in behind your minions: a tower shoots the nearest of them first. Last hits, jungle camps and towers pay gold -- shop in your keep or while you're down. The Bone Lord and the Grave Wyrm make your whole side stronger. Your fountain heals you.", 11, new Color("#5d3a1c"), UI.HEAVY_FONT);
            tricks.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
            tricks.CustomMinimumSize = new Vector2(290, 0);
            var rb = _Button(v, "RESUME", "active", () => pause_panel.Visible = false);
            var rbm = rb.CustomMinimumSize;
            rbm.y = 58;
            rb.CustomMinimumSize = rbm;
            rb.AddThemeFontSizeOverride("font_size", 26);
            var row = new HBoxContainer();
            row.AddThemeConstantOverride("separation", 8);
            v.AddChild(row);
            // (0.31.163: no RESOLUTION button -- the 3D is locked at 50 %, siege_mode.RENDER_SCALE)
            var lv = _Button(row, "LEAVE MATCH", "danger", () => LeaveRequested?.Invoke());
            lv.AddThemeFontSizeOverride("font_size", 13);
        }

        public void ShowResult(GDict result = null)
        {
            result ??= new GDict();
            CloseBoard();                                  // (0.31.176: the live scoreboard gives way to the results)
            // 0.31.79: a ribbon banner (VICTORY / DEFEAT / DRAW) with a crown and a sunburst behind a win, the score in team
            // colours, your match, the spoils as a table, chests with their pictures, then PLAY AGAIN / HOME.
            if (result_panel != null)
                return;
            Unit me = sim.by_id.TryGetValue(player_id, out var mu) ? mu : null;
            result_panel = _Panel(340);
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", 8);
            result_panel.AddChild(v);
            bool won = sim.winner == me.team;
            bool draw = sim.winner == -1;
            var head = new Control();
            head.CustomMinimumSize = new Vector2(300, 92);
            v.AddChild(head);
            if (won)
            {
                var ry = UI2.Rays(head, 420.0, new Color(1.0, 0.86, 0.45), 30.0, 0.45);
                head.Resized += () => ry.Position = new Vector2(head.Size.x * 0.5 - 210.0, -160.0);
                var crn = UI2.Icon(head, "crown", 54.0);
                head.Resized += () => crn.Position = new Vector2(head.Size.x * 0.5 - 27.0, -26.0);
                UI2.Bob(crn, 4.0, 1.0);
            }
            var title = draw ? "DRAW" : (won ? "VICTORY!" : "DEFEAT");
            GArray cols = won ? GArray.Of(new Color("#ff8a6a"), new Color("#a8221a")) : (draw ? GArray.Of(new Color("#5d89f0"), new Color("#1b2d78")) : GArray.Of(new Color("#6b7486"), new Color("#2a2f3c")));
            var rib = UI2.Ribbon(head, title, "", 300.0, 58.0, cols);
            head.Resized += () => rib.Position = new Vector2((head.Size.x - 300.0) * 0.5, 30.0);
            // score
            var sc = new HBoxContainer();
            sc.AddThemeConstantOverride("separation", 0);
            sc.CustomMinimumSize = new Vector2(0, 62);
            v.AddChild(sc);
            for (int side = 0; side < 3; side++)
            {
                var cell = new VBoxContainer();
                cell.Alignment = BoxContainer.ALIGNMENT_CENTER;
                cell.AddThemeConstantOverride("separation", 0);
                cell.SizeFlagsHorizontal = side != 1 ? Control.SIZE_EXPAND_FILL : Control.SIZE_FILL;
                cell.CustomMinimumSize = new Vector2(side == 1 ? 92 : 0, 0);
                sc.AddChild(cell);
                if (side == 1)
                {
                    UI2.Center(UI2.Body(cell, "KINGS", 11, UI2.GOLD, false));
                    UI2.Center(UI2.Body(cell, GD.Fmt("KOs %d–%d", sim.kills[me.team], sim.kills[1 - me.team]), 10, UI2.MUTED, false));
                    continue;
                }
                var mine = side == 0;
                int t = mine ? me.team : 1 - me.team;
                UI2.Plate(cell, "royal", 14.0, "gold", GDict.Of("rim", 0.0, "outline", 2.0, "pattern_mix", 0.0,
                    "fill_top", TEAM_COLORS[Vt(t)].Lightened(0.15), "fill_bottom", TEAM_COLORS[Vt(t)].Darkened(0.45), "shadow_y", 3.0));
                UI2.Center(UI2.Body(cell, mine ? "YOU" : "ENEMY", 10, Color.WHITE, false));
                UI2.Center(UI2.Text(cell, GD.Str(sim.score[t]), 30, Color.WHITE, new Color("#0a1238"), 7));
            }
            // you
            var you = new HBoxContainer();
            you.Alignment = BoxContainer.ALIGNMENT_CENTER;
            you.AddThemeConstantOverride("separation", 6);
            v.AddChild(you);
            var third = GArray.Of("castle", GD.Fmt("%d tower%s", me.towers, me.towers == 1 ? "" : "s"));     // (0.31.164)
            foreach (var ch in GArray.Of(GArray.Of("skull", GD.Fmt("%d KOs", me.kills)), GArray.Of("helmet", GD.Fmt("%d downs", me.deaths)), third))
            {
                var c = UI2.Chip(you, "", new Color(0.01, 0.02, 0.08, 0.8), Color.WHITE, new Color(UI2.GOLD, 0.4));
                var cl = (Label)c.GetChild(0);
                c.RemoveChild(cl);
                cl.QueueFree();
                var r = new HBoxContainer();
                r.AddThemeConstantOverride("separation", 3);
                c.AddChild(r);
                UI2.Icon(r, GD.Str(ch[0]), 20.0);
                UI2.Body(r, GD.Str(ch[1]), 11, Color.WHITE, false);
            }
            UI2.Center(UI2.Body(v, GD.Fmt("Last hits %d · camps %d · tower and gate damage %d", me.lh, me.camps,
                GD.Int(me.gate_dmg)), 12, new Color("#cfe8b8"), false));
            // 0.31.155 5V5: the towers each side brought down, your level (0.31.164: paid like any match now)
            UI2.Center(UI2.Body(v, GD.Fmt("Towers down: theirs %d · yours %d  ·  you reached level %d", sim.moba.TowersDown(1 - me.team),
                sim.moba.TowersDown(me.team), me.level), 12, new Color("#ffcf7a"), false));
            var n_items = me.items != null ? me.items.Count : 0;
            UI2.Center(UI2.Body(v, GD.Fmt("Gold earned %d · %d item%s", GD.Int(me.gold_total), n_items,
                n_items == 1 ? "" : "s"), 12, new Color("#ffe39a"), false));
            _MvpStrip(v);
            GDict rw = result.Get("rewards", new GDict()).D;
            if (!rw.IsEmpty())
            {
                var tab = new PanelContainer();
                var ts = new StyleBoxEmpty();
                foreach (var side in new[] { "left", "right", "top", "bottom" })
                    GObject.Set(ts, "content_margin_" + side, 12.0);
                tab.AddThemeStyleboxOverride("panel", ts);
                v.AddChild(tab);
                UI2.Plate(tab, "parch", 14.0, "brown", GDict.Of("rim", 3.0));
                var box = new VBoxContainer();
                box.AddThemeConstantOverride("separation", 1);
                tab.AddChild(box);
                var ink = new Color("#3b2412");
                var hdr = new HBoxContainer();
                box.AddChild(hdr);
                var ht = UI2.Text(hdr, "SPOILS OF WAR", 15, ink, ink, 0, false);
                ht.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
                foreach (var hh in new[] { "GOLD", "PASS" })
                {
                    var hl = UI.Label(hdr, hh, 9, new Color("#7a5530"), UI.HEAVY_FONT);
                    hl.CustomMinimumSize = new Vector2(52, 0);
                    hl.HorizontalAlignment = HorizontalAlignment.Right;
                }
                foreach (var ln in rw["lines"])
                {
                    var row = new HBoxContainer();
                    box.AddChild(row);
                    var name_l = UI.Label(row, GD.Str(ln["label"]), 12, ink, UI.HEAVY_FONT);
                    name_l.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
                    foreach (var val in GArray.Of(GArray.Of(GD.Fmt("+%d", GD.Int(ln["gold"])), new Color("#8a5a0a")), GArray.Of(GD.Fmt("+%d", GD.Int(ln["pass"])), new Color("#6a2bb8"))))
                    {
                        var vl = UI.Label(row, GD.Str(val[0]), 12, val[1].As<Color>(), UI.HEAVY_FONT);
                        vl.CustomMinimumSize = new Vector2(52, 0);
                        vl.HorizontalAlignment = HorizontalAlignment.Right;
                    }
                }
                var tot = new HBoxContainer();
                tot.Alignment = BoxContainer.ALIGNMENT_CENTER;
                tot.AddThemeConstantOverride("separation", 10);
                v.AddChild(tot);
                var totals = GArray.Of(GArray.Of("res://assets/ui/currency/coin.png", GD.Fmt("+%d", GD.Int(rw["gold"])), UI2.GOLD), GArray.Of("", GD.Fmt("+%d XP", GD.Int(rw["xp"])), UI2.CYAN), GArray.Of("", GD.Fmt("+%d PASS", GD.Int(rw["pass"])), UI2.PURPLE));
                if (totals.Size() > 3)
                    tot.AddThemeConstantOverride("separation", 6);       // (four totals fit a narrow phone)
                foreach (var tv in totals)
                {
                    var tr = new HBoxContainer();
                    tr.AddThemeConstantOverride("separation", 3);
                    tot.AddChild(tr);
                    if (GD.Str(tv[0]) != "")
                        UI2.Img(tr, GD.Str(tv[0]), totals.Size() > 3 ? 24.0 : 26.0);
                    UI2.Text(tr, GD.Str(tv[1]), totals.Size() > 3 ? 16 : 18, tv[2].As<Color>(), UI2.INK, 5);
                }
                foreach (var lv in result.Get("levels", new GArray()))
                {
                    UI2.Center(UI2.Text(v, GD.Fmt("LEVEL UP!  LEVEL %d", GD.Int(lv["level"])), 18, UI2.CYAN, new Color("#06283a"), 5));
                    UI2.Center(UI2.Body(v, GD.Fmt("+%d gold%s", GD.Int(lv["reward"].D.Get("gold", 0)), lv["reward"].D.Has("gems") ? GD.Fmt("  ·  +%d gems", GD.Int(lv["reward"]["gems"])) : ""), 12, Color.WHITE, false));
                }
                foreach (var ch in result.Get("chests", new GArray()))                     // 0.31.37
                {
                    var kind = GD.Str(ch["kind"]);
                    var cn = GD.Str(Sim_Eco.CHESTS[kind]["name"]);
                    var cr = new HBoxContainer();
                    cr.AddThemeConstantOverride("separation", 8);
                    v.AddChild(cr);
                    var ci = UI2.Img(cr, UI2.V2 + GD.Fmt("chests/%s_icon.png", GD.Str(GDict.Of("wooden", "wood").Get(kind, kind))), 52.0);
                    if (!(bool)ch.D.Get("full", false))
                        UI2.Bob(ci, 3.0, 1.0);
                    var cv = new VBoxContainer();
                    cv.AddThemeConstantOverride("separation", 0);
                    cv.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
                    cr.AddChild(cv);
                    if ((bool)ch.D.Get("full", false))
                    {
                        UI2.Text(cv, cn.ToUpperInvariant(), 14, Color.WHITE);
                        UI2.Body(cv, GD.Fmt("Chest slots full -- turned into %d gold", GD.Int(ch["gold"])), 11, UI2.SOFT);
                    }
                    else
                    {
                        UI2.Text(cv, GD.Fmt("%s EARNED!", cn.ToUpperInvariant()), 15, Color.FromCode(GD.Str(Sim_Eco.CHESTS[kind]["color"])));
                        UI2.Body(cv, "Unlock it from Home", 11, UI2.SOFT);
                    }
                }
                foreach (var tid in result.Get("titles", new GArray()))                    // 0.31.87: a title earned this match
                {
                    var trar = NetT.TitleRarity(GD.Str(tid));
                    var tbox = UI2.Frame(v, GD.Str(GDict.Of("common", "night", "rare", "royal", "epic", "purple", "legendary", "ember").Get(trar, "night")), 8, 14.0,
                        GD.Str(GDict.Of("common", "silver", "rare", "blue", "epic", "purple", "legendary", "orange").Get(trar, "gold")), GDict.Of("pattern_mix", 0.0));
                    if (trar == "legendary")
                        UI2.Sweep(tbox.GetParent() as Control, 2.2, 60.0, 0.35);
                    UI2.Center(UI2.Text(tbox, "TITLE EARNED!", 15, UI2.GOLD));
                    var tl = new HBoxContainer();
                    tl.Alignment = BoxContainer.ALIGNMENT_CENTER;
                    tl.AddThemeConstantOverride("separation", 0);
                    tbox.AddChild(tl);
                    foreach (var part in NetT.TitleParts(GD.Str(player_name), GD.Str(tid)))
                        UI2.Text(tl, GD.Str(part[0]), 17, (bool)part[1] ? TAG_COL.Get(trar, Color.WHITE).As<Color>() : Color.WHITE, new Color("#120a02"), 5);
                    UI2.Center(UI2.Body(tbox, GD.Fmt("%s · wear it from the Armory", trar.Capitalize()), 11, new Color(1, 1, 1, 0.8), false));
                }
                GArray tiers = result.Get("tiers", new GArray()).A;
                if (!tiers.IsEmpty())
                    UI2.Center(UI2.Body(v, GD.Fmt("Siege Pass tier %s reached — claim it on the Pass screen", tiers.Size() == 1 ? GD.Str(tiers[-1]) : GD.Fmt("%d–%d", tiers[0], tiers[-1])), 12, new Color("#ffcf7a")));
                foreach (var c in result.Get("challenges", new GArray()).A.Slice(0, 4))
                    UI2.Center(UI2.Body(v, GD.Fmt("%s  %s  %d/%d", (bool)c["done"] ? "✔" : "•", GD.Str(c["text"]), GD.Mini(GD.Int(c["progress"]), GD.Int(c["goal"])), GD.Int(c["goal"])), 11, (bool)c["done"] ? UI2.GREEN : UI2.MUTED, false));
                // 0.31.97: class quests -- the steps this match moved, and a banner when one is ready to claim
                GArray qlines = result.Get("quests", new GArray()).A;
                var qready = qlines.Filter(x => (bool)x["done"]);
                if (!qready.IsEmpty())
                {
                    var qb = UI2.Frame(v, "ember", 8, 14.0, "orange", GDict.Of("pattern_mix", 0.0));
                    UI2.Sweep(qb.GetParent() as Control, 2.2, 60.0, 0.35);
                    UI2.Center(UI2.Text(qb, "QUEST STEP DONE!", 15, new Color("#ffd27a")));
                    foreach (var ql in qready.Slice(0, 2))
                        UI2.Center(UI2.Body(qb, GD.Fmt("%s: %s", GD.Str(Sim_Eco.CLASS_NAMES.Get(GD.Str(ql["cls"]), "")), GD.Str(ql["text"])), 11, Color.WHITE, false));
                    UI2.Center(UI2.Body(qb, "Claim it in Quests from Home", 10, new Color(1, 1, 1, 0.75), false));
                }
                foreach (var ql in qlines.Filter(x => !(bool)x["done"]).Slice(0, 2))
                    UI2.Center(UI2.Body(v, GD.Fmt("⚔  %s quest  %s  %d/%d", GD.Str(Sim_Eco.CLASS_NAMES.Get(GD.Str(ql["cls"]), "")), GD.Str(ql["text"]), GD.Int(ql["progress"]), GD.Int(ql["goal"])), 11, new Color("#ffcf7a"), false));
            }
            var br = new HBoxContainer();
            br.AddThemeConstantOverride("separation", 10);
            v.AddChild(br);
            _Button(br, "HOME", "secondary", () => LeaveRequested?.Invoke());
            var sb = _Button(br, "SCORES", "gold", () => ShowScoreboard());         // 0.31.119
            sb.SetMeta("key", "scoreboard");
            var pa = _Button(br, "PLAY AGAIN", "primary", () => ReplayRequested?.Invoke());
            pa.SizeFlagsStretchRatio = 1.5;
            UI2.Sweep(pa);
            result_panel.Visible = true;
            _Center(result_panel, true);
            if (pause_panel != null)
                pause_panel.Visible = false;
        }

        // ---------- scoreboard and MVP (0.31.119, Kevin: "Do all" -- a proper end-of-match screen) ----------
        // Every hero's knockouts, downs, towers and tower/gate damage come with the snapshots (and are the sim's own offline), so
        // the board is the match as the server counted it. Points: a knockout 20, tower, gate and King damage 1 per 10. Bots are
        // on the board too (as "Bot · <hero>"; 0.31.177: a 5v5 bot by its name, "Bot Alfred"): most matches are mostly bots, and an honest board says when one outplayed
        // everybody.
        public const int MVP_KO = 20;
        public const double MVP_GATE = 0.1;

        public static int Points(Unit u)
        {
            return u.kills * MVP_KO + GD.Int(u.gate_dmg * MVP_GATE);
        }

        public string DisplayName(Unit u)
        {
            if (GD.Str(u.id) == player_id)
                return player_name;
            if (net_names.Has(GD.Str(u.id)))
                return GD.Str(net_names[GD.Str(u.id)]);
            if (u.hero && sim.moba != null)
                return Moba.BotLabel(u);               // 0.31.177: "Bot Alfred", as over its head
            return GD.Fmt("Bot · %s", sim.ClassLabel(u));
        }

        public bool IsPlayer(Unit u)
        {
            return GD.Str(u.id) == player_id || net_names.Has(GD.Str(u.id));
        }

        public List<Unit> Ranking(int team = -1)
        {
            // units by points (then knockouts, then fewer downs); team -1 = everyone
            List<Unit> o = sim.units.FindAll(u => (team < 0 || u.team == team) && u.hero);
            GSort.Sort(o, (a, b) =>
            {
                var pa = Points(a);
                var pb = Points(b);
                if (pa != pb)
                    return pa > pb;
                if (a.kills != b.kills)
                    return a.kills > b.kills;
                if (a.deaths != b.deaths)
                    return a.deaths < b.deaths;
                return IsPlayer(a) && !IsPlayer(b);
            });
            return o;
        }

        public Unit Mvp()
        {
            var r = Ranking();
            return r.Count != 0 && Points(r[0]) > 0 ? r[0] : null;
        }

        public void _MvpStrip(VBoxContainer v)
        {
            var m = Mvp();
            if (m == null)
                return;
            var mine = GD.Str(m.id) == player_id;
            var box = UI2.Frame(v, mine ? "ember" : "royal", 6, 14.0, mine ? "orange" : "gold", GDict.Of("pattern_mix", 0.0));
            box.Name = "MvpStrip";
            if (mine)
                UI2.Sweep(box.GetParent() as Control, 2.2, 60.0, 0.4);
            var row = new HBoxContainer();
            row.Alignment = BoxContainer.ALIGNMENT_CENTER;
            row.AddThemeConstantOverride("separation", 8);
            box.AddChild(row);
            UI2.Icon(row, "crown", 30.0);
            var col = new VBoxContainer();
            col.AddThemeConstantOverride("separation", 0);
            row.AddChild(col);
            var head = UI2.Text(col, mine ? "YOU ARE THE MVP!" : GD.Fmt("MVP  ·  %s", DisplayName(m)), mine ? 16 : 15,
                mine ? UI2.GOLD : Color.WHITE, new Color("#1a0c02"), 5);
            head.Name = "MvpName";
            var bits = new GArray();
            if (m.towers > 0)
                bits.Append(GD.Fmt("%d tower%s", m.towers, m.towers == 1 ? "" : "s"));
            bits.Append(GD.Fmt("%d KOs", m.kills));
            bits.Append(GD.Fmt("%d pts", Points(m)));
            UI2.Body(col, GStr.Join(" · ", bits), 11, new Color(1, 1, 1, 0.85), false);
        }

        public void ShowScoreboard()
        {
            // both sides, best first: the top 6 of each (and you, wherever you placed)
            if (score_panel != null)
                score_panel.QueueFree();
            score_panel = _Panel(360);
            score_panel.Name = "Scoreboard";
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", 6);
            score_panel.AddChild(v);
            UI2.Center(UI2.Text(v, "SCOREBOARD", 24, UI2.GOLD, new Color("#1a0c02"), 6));
            Unit me = sim.by_id.TryGetValue(player_id, out var mu) ? mu : null;
            var my_team = me != null ? me.team : 0;
            foreach (var side in new[] { my_team, 1 - my_team })
            {
                var hdr = new HBoxContainer();
                hdr.AddThemeConstantOverride("separation", 4);
                v.AddChild(hdr);
                var hl = UI2.Text(hdr, side == my_team ? "YOUR SIDE" : "ENEMY", 14, TEAM_COLORS[Vt(side)], new Color("#0a1238"), 4);
                hl.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
                foreach (var hh in GArray.Of(GArray.Of("KO", 34), GArray.Of("TW", 26), GArray.Of("PTS", 46)))
                {
                    var hc = UI.Label(hdr, GD.Str(hh[0]), 10, UI2.MUTED, UI.HEAVY_FONT);
                    hc.AutowrapMode = TextServer.AUTOWRAP_OFF;
                    hc.CustomMinimumSize = new Vector2((double)hh[1], 0);
                    hc.HorizontalAlignment = HorizontalAlignment.Right;
                }
                var rows = Ranking(side);
                var shown = rows.GetRange(0, Math.Min(6, rows.Count));
                var my_rank = rows.IndexOf(me);
                if (side == my_team && my_rank >= 6)
                    shown.Add(me);
                foreach (var u in shown)
                    _ScoreRow(v, u, rows.IndexOf(u) + 1, GD.Str(u.id) == player_id, side);
            }
            UI2.Center(UI2.Body(v, GD.Fmt("Points: KO %d · tower, gate and King damage ÷%d  ·  TW: towers", MVP_KO, GD.Int(1.0 / MVP_GATE)), 10, UI2.MUTED, true));
            var back = _Button(v, "BACK", "secondary", () =>
            {
                score_panel.Visible = false;                  // (hidden, not freed: its opening animation may still be running)
                if (result_panel != null)
                {
                    result_panel.Visible = true;
                    _Center(result_panel);
                }
            });
            back.SetMeta("key", "scoreboard_back");
            if (result_panel != null)
                result_panel.Visible = false;
            score_panel.Visible = true;
            _Center(score_panel, true);
        }

        public void _ScoreRow(VBoxContainer v, Unit u, int rank, bool mine, int side)
        {
            var row = new PanelContainer();
            var st = new StyleBoxFlat();
            st.BgColor = mine ? new Color(UI2.GOLD, 0.22) : new Color(TEAM_COLORS[Vt(side)], 0.08);
            st.SetCornerRadiusAll(8);
            st.ContentMarginLeft = 6;
            st.ContentMarginRight = 6;
            st.ContentMarginTop = 3;
            st.ContentMarginBottom = 3;
            if (mine)
            {
                st.BorderColor = UI2.GOLD;
                st.SetBorderWidthAll(1);
            }
            row.AddThemeStyleboxOverride("panel", st);
            v.AddChild(row);
            var h = new HBoxContainer();
            h.AddThemeConstantOverride("separation", 4);
            row.AddChild(h);
            var rl = UI.Label(h, GD.Fmt("%d", rank), 12, rank == 1 ? UI2.GOLD : UI2.MUTED, UI.HEAVY_FONT);
            rl.AutowrapMode = TextServer.AUTOWRAP_OFF;
            rl.CustomMinimumSize = new Vector2(18, 0);
            var name_col = IsPlayer(u) ? Color.WHITE : new Color(1, 1, 1, 0.62);
            var nl = UI.Label(h, DisplayName(u), 13, mine ? UI2.GREEN : name_col, UI.HEAVY_FONT);    // (0.31.195: green, not gold)
            nl.AutowrapMode = TextServer.AUTOWRAP_OFF;
            nl.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            nl.ClipText = true;
            nl.TextOverrunBehavior = TextServer.OVERRUN_TRIM_ELLIPSIS;
            foreach (var val in GArray.Of(GArray.Of(GD.Str(u.kills), 34), GArray.Of(GD.Str(u.towers), 26), GArray.Of(GD.Str(Points(u)), 46)))
            {
                var vl = UI.Label(h, GD.Str(val[0]), 13, Color.WHITE, UI.HEAVY_FONT);
                vl.AutowrapMode = TextServer.AUTOWRAP_OFF;
                vl.CustomMinimumSize = new Vector2((double)val[1], 0);
                vl.HorizontalAlignment = HorizontalAlignment.Right;
            }
        }

        public void Toast(string text, Color? color = null)
        {
            var c = color ?? Color.WHITE;
            _toast = text;
            _toast_at = _time;
            _toast_color = UI.Ink(c);
        }

        // (e.get(key, []) as Array: an event's list, as the sim or the wire put it)
        static IList _EvList(Ev e, string key) => e.TryGetValue(key, out var v) && v is IList l ? l : new List<object>();

        public void OnEvent(Ev e)
        {
            Unit me = sim.by_id.TryGetValue(player_id, out var mu) ? mu : null;
            if (me == null)
                return;
            _KfEvent(e, me);
            bool mine = e.I("team", -1) == me.team;
            switch (e.K)
            {
                case "level":
                    if (e.S("id", "") == GD.Str(player_id))
                        Toast(GD.Fmt("LEVEL %d!  TAP + TO LEARN A SKILL", e.I("level")), VisualTheme.GOLD);     // (0.31.217: skill points; PICK AN UPGRADE until then)
                    break;
                case "tower_immune":
                    Toast("That tower is protected -- take the one in front of it first", new Color("#ffcf7a"));
                    break;
                case "tower_far":                                     // 0.31.179: hit from outside its range
                    if (e.S("by", "") == GD.Str(player_id))
                        Toast("Too far -- step into the tower's range to hurt it", new Color("#ffcf7a"));
                    break;
                case "king_immune":
                    Toast("Their King is protected until one of their lanes falls -- all three of its towers", new Color("#ffcf7a"));   // (0.31.217)
                    break;
                case "king_down":
                    Toast(e.I("team", -1) != me.team ? "THEIR KING IS DEFEATED!" : "OUR KING HAS FALLEN", e.I("team", -1) != me.team ? VisualTheme.GOLD : VisualTheme.RED);
                    break;
                case "ult_ready":                                     // 0.31.157 5V5
                    if (e.S("id", "") == GD.Str(player_id))
                    {
                        var info = sim.moba.UltInfo(me);
                        var un = info != null ? GD.Str(info.name ?? "ULTIMATE") : "ULTIMATE";
                        Toast(e.I("rank") < 2 ? GD.Fmt("ULTIMATE READY: %s!", un) : GD.Fmt("%s IS STRONGER NOW", un), new Color("#ffb04a"));
                    }
                    break;
                case "buff":
                    if (e.S("id", "") == GD.Str(player_id))
                        Toast(GD.Fmt("%s! %s", Moba.BUFF_NAMES.TryGetValue(e.S("buff"), out var bn) ? bn : "", e.S("buff") == "arcane" ? "Abilities recharge faster" : "You hit harder"), e.S("buff") == "arcane" ? new Color("#7fb8ff") : new Color("#ff9a5a"));
                    break;
                case "lord_down":
                    Toast(e.I("team", -1) == me.team ? "WE SLEW THE BONE LORD! Gold for all, and his blessing" : "THEY SLEW THE BONE LORD", e.I("team", -1) == me.team ? VisualTheme.GOLD : VisualTheme.RED);
                    break;
                case "camp_up":
                    if (e.S("kind", "") == "lord")
                        Toast("THE BONE LORD HAS RISEN IN THE WEST PIT", new Color("#d8c2ff"));
                    else if (e.S("kind", "") == "wyrm")
                        Toast("THE GRAVE WYRM STIRS IN THE EAST PIT", new Color("#7fffd4"));
                    break;
                case "wyrm_down":                                     // 0.31.166
                    {
                        var ours_w = e.I("team", -1) == me.team;
                        var pct = GD.Int(GD.Round(Moba.WYRM_HIDE * 100.0 * e.I("stacks", 0)));
                        Toast(GD.Fmt(ours_w ? "WE SLEW THE GRAVE WYRM! WYRM'S HIDE x%d: +%d%% HEALTH FOR ALL" : "THEY SLEW THE GRAVE WYRM -- THEIR HIDE x%d (+%d%%)", e.I("stacks", 0), pct),
                            ours_w ? VisualTheme.GOLD : VisualTheme.RED);
                        break;
                    }
                case "lord_march":                                    // 0.31.158 5V5: the slain Lord marches for the slayers
                    Toast(e.I("team", -1) == me.team ? "THE BONE LORD MARCHES WITH US DOWN THE MIDDLE!" : "THE BONE LORD MARCHES ON US -- MIDDLE LANE!",
                        e.I("team", -1) == me.team ? VisualTheme.GOLD : VisualTheme.RED);
                    break;
                case "gate_rebuilt":
                    Toast(e.I("team", -1) == me.team ? "Our gate is rebuilt" : "Their gate is rebuilt", new Color("#e8dcc0"));
                    break;
                case "plate":
                    if (_EvList(e, "ids").Contains(GD.Str(player_id)))
                        Toast(GD.Fmt("TOWER PLATE! +%d gold", e.I("gold", 0)), VisualTheme.GOLD);
                    break;
                case "ward":
                    if (e.S("id", "") == GD.Str(player_id))
                        Toast(GD.Fmt("Ward placed -- it watches %d s", GD.Int(MobaVision.WARD_LIFE)), new Color("#8fe3ff"));
                    break;
                case "buy":
                    if (e.S("id", "") == GD.Str(player_id))
                        Toast(GD.Fmt("Bought %s", GD.Str(Moba.ITEMS[e.S("item")].name)), VisualTheme.GOLD);
                    break;
                case "sell":
                    if (e.S("id", "") == GD.Str(player_id))
                        Toast(GD.Fmt("Sold %s · +%d gold", GD.Str(Moba.ITEMS[e.S("item")].name), e.I("gold")), new Color("#e8dcc0"));
                    break;
                case "kb":
                case "ace":
                    if (kill_banner != null)
                        kill_banner.Push(e);                      // 0.31.180: every hero kill, FIRST BLOOD, multi-kills, SHUTDOWN, ACE
                    break;
                case "death":
                    if (e.S("id") == player_id && !(sim.by_id.TryGetValue(e.S("by", ""), out var killer) && killer.hero))
                        Toast("You fell!", VisualTheme.RED);     // (a hero's kill has its banner)
                    break;
                case "gate_broken":
                    {
                        string side = GD.Str(sim.gates[e.I("gate")].side).ToUpperInvariant();
                        Toast(mine ? GD.Fmt("OUR %s GATE HAS FALLEN!", side) : GD.Fmt("ENEMY %s GATE BROKEN — CHARGE!", side), mine ? VisualTheme.RED : VisualTheme.GOLD);
                        break;
                    }
            }
        }

        // ---------- input ----------
        public GArray _Buttons()
        {
            Unit me = sim.by_id.TryGetValue(player_id, out var mu) ? mu : null;
            if (me == null || !me.hero)
                return new GArray();
            var br = new Vector2(Size.x, Size.y);
            // 0.31.167 5V5 (Kevin: "class roles like League of Legends"): Q, W, E and R in an arc round ATTACK (Wild Rift's
            // layout), DODGE and WARD above them (0.31.206: HOME over DODGE); on the narrowest screen (420 wide) Q and W reach as
            // far left as the old ABILITY did. The Crusader's W is his shield, held (it was its own BLOCK button).
            bool crus = me.cls == "knight" && me.up;
            // 0.31.216, landscape (Honor of Kings' layout): Q, W, E and R in an arc round ATTACK; DODGE, WARD and HOME in a row
            // along the bottom to their left. (Portrait until then: the arc reached 364 px up the screen.)
            var a = br + new Vector2(-80, -80);
            return GArray.Of(
                GDict.Of("id", "attack", "c", a, "r", 46.0),
                GDict.Of("id", "ability", "c", a + Vector2.FromAngle(GD.DegToRad(184.0)) * 108.0, "r", 31.0),
                GDict.Of("id", crus ? "block" : "w", "c", a + Vector2.FromAngle(GD.DegToRad(216.0)) * 108.0, "r", 31.0),
                GDict.Of("id", "e", "c", a + Vector2.FromAngle(GD.DegToRad(248.0)) * 108.0, "r", 31.0),
                GDict.Of("id", "ult", "c", a + Vector2.FromAngle(GD.DegToRad(282.0)) * 112.0, "r", 35.0),
                GDict.Of("id", "dodge", "c", br + new Vector2(-262, -34), "r", 25.0),
                GDict.Of("id", "ward", "c", br + new Vector2(-318, -34), "r", 23.0),
                // 0.31.181: home to the fountain (0.31.206: over DODGE; 0.31.216: at the row's left end, as Honor of Kings' Recall)
                GDict.Of("id", "recall", "c", br + new Vector2(-372, -34), "r", 23.0)
            );
        }

        // 0.31.217 (Kevin, Honor of Kings: "HoK + buttons"): a gold + over each skill a point can go on (Honor of Kings' learn /
        // upgrade), out from the arc's middle; tapped: "learn_<slot>"
        public static readonly GDict SLOT_OF = GDict.Of("ability", "q", "w", "w", "block", "w", "e", "e", "ult", "r");

        public GArray LearnSpots(Unit me)
        {
            var o = new GArray();
            if (me == null || sim == null || sim.moba == null || me.sp <= 0)
                return o;
            var a = new Vector2(Size.x, Size.y) + new Vector2(-80, -80);
            foreach (var b in _Buttons())
            {
                var slot = GD.Str(SLOT_OF.Get(GD.Str(b["id"]), ""));
                if (slot == "" || !sim.moba.CanLearn(me, slot))
                    continue;
                Vector2 c = b["c"].V2;
                var out_dir = (c - a).Normalized();
                o.Append(GDict.Of("slot", slot, "c", c + out_dir * ((double)b["r"] + 17.0), "r", 14.0));
            }
            return o;
        }

        public void _DrawLearn(GArray spots)
        {
            var pulse = 0.5 + 0.5 * Math.Sin(Math.Floor(_time * 15.0) / 15.0 * 6.0);
            foreach (var sp in spots)
            {
                Vector2 c = sp["c"].V2;
                _ci.DrawCircle(c, 14.0 + 4.0 * pulse, new Color(1.0, 0.82, 0.3, 0.22));
                _ci.DrawCircle(c + new Vector2(0, 2), 13.0, new Color(0, 0, 0, 0.45));
                _ci.DrawCircle(c, 13.0, new Color("#1a2a44"));
                _ci.DrawArc(c, 13.0, 0, GD.TAU, 32, new Color("#ffd65a"), 2.5, true);
                _ci.DrawLine(c - new Vector2(6, 0), c + new Vector2(6, 0), new Color("#ffe9a6"), 3.0);
                _ci.DrawLine(c - new Vector2(0, 6), c + new Vector2(0, 6), new Color("#ffe9a6"), 3.0);
            }
        }
        public bool _ModalOpen()
        {
            return Paused() || tut_modal || (result_panel != null && result_panel.Visible)
                || (score_panel != null && GD.IsInstanceValid(score_panel) && score_panel.Visible) || ShopOpen() || BoardOpen();
        }

        protected override void _Input(InputEvent @event)
        {
            if (sim == null)
                return;
            if (@event is InputEventScreenTouch st)
                _Touch(st.Index, ((InputEventScreenTouch)MakeInputLocal(@event)).Position, st.Pressed);
            else if (@event is InputEventScreenDrag sd)
                _Drag(sd.Index, ((InputEventScreenDrag)MakeInputLocal(@event)).Position);
            else if (!_touchscreen && @event is InputEventMouseButton mb && mb.ButtonIndex == MouseButton.Left)
                _Touch(-1, ((InputEventMouseButton)MakeInputLocal(@event)).Position, mb.Pressed);
            else if (!_touchscreen && @event is InputEventMouseMotion && _touches.Has(-1))
                _Drag(-1, ((InputEventMouseMotion)MakeInputLocal(@event)).Position);
            else if (@event is InputEventKey k && k.Pressed && !k.Echo && !_ModalOpen())
            {
                switch (k.PhysicalKeycode)
                {
                    case Key.J: case Key.Space: ActionPressed?.Invoke("attack"); break;
                    case Key.K: ActionPressed?.Invoke("ability"); break;
                    case Key.L: case Key.Shift: ActionPressed?.Invoke("dodge"); break;
                    case Key.R: ActionPressed?.Invoke("ult"); break;             // 0.31.157 5V5
                    case Key.U: ActionPressed?.Invoke("w"); break;               // 0.31.167 5V5: W and E
                    case Key.I: ActionPressed?.Invoke("e"); break;
                    case Key.T: ActionPressed?.Invoke("ward"); break;            // 0.31.158 5V5
                    case Key.B: ActionPressed?.Invoke("recall"); break;          // 0.31.181 (League's B)
                    case Key.P: OpenShop(); break;                            // (B until 0.31.181: League's P)
                }
            }
        }

        public void _Touch(int index, Vector2 pos, bool pressed)
        {
            if (pressed && BoardOpen())
            {
                // 0.31.176: the live scoreboard -- the score bar again or a tap outside it closes it (its X too)
                if (ScoreBarRect().HasPoint(pos) || !board_panel.GetGlobalRect().HasPoint(pos + GlobalPosition))
                {
                    CloseBoard();
                    GetViewport().SetInputAsHandled();
                }
                return;
            }
            if (pressed && sim != null && sim.moba != null && !_ModalOpen() && ScoreBarRect().HasPoint(pos))
            {
                OpenBoard();                               // 0.31.176: tap the score bar for the live scoreboard
                GetViewport().SetInputAsHandled();
                return;
            }
            if (pressed)
            {
                if (_ModalOpen() || pause_btn.GetGlobalRect().HasPoint(pos + GlobalPosition)
                        || (qc_btn.Visible && qc_btn.GetGlobalRect().HasPoint(pos + GlobalPosition)))
                    return;
                if (qc_panel != null && qc_panel.Visible)
                {
                    if (qc_panel.GetGlobalRect().HasPoint(pos + GlobalPosition))
                        return;                             // (the wheel's own buttons take it)
                    qc_panel.Visible = false;
                }
                for (int i = 0; i < 3; i++)
                {
                    if (PickRect(i).HasPoint(pos) && _PicksOpen())
                    {
                        ActionPressed?.Invoke(GD.Fmt("pick%d", i));
                        GetViewport().SetInputAsHandled();
                        return;
                    }
                }
                Unit me_l = sim.by_id.TryGetValue(player_id, out var ml) ? ml : null;
                foreach (var sp in LearnSpots(me_l))                // 0.31.217: a + over a skill
                {
                    if (pos.DistanceTo(sp["c"].V2) <= (double)sp["r"] + 8.0)
                    {
                        ActionPressed?.Invoke("learn_" + GD.Str(sp["slot"]));
                        GetViewport().SetInputAsHandled();
                        return;
                    }
                }
                foreach (var q in QuickRects(me_l))                // 0.31.217: the quick-buy
                {
                    if (q["r"].As<Rect2>().Grow(4.0).HasPoint(pos))
                    {
                        ActionPressed?.Invoke("shop_buy:" + GD.Str(q["id"]));
                        GetViewport().SetInputAsHandled();
                        return;
                    }
                }
                if (ShopRect().Grow(6.0).HasPoint(pos))
                {
                    OpenShop();                            // 0.31.157 5V5: the shop
                    GetViewport().SetInputAsHandled();
                    return;
                }
                foreach (var b in _Buttons())
                {
                    if (pos.DistanceTo(b["c"].V2) <= (double)b["r"] + 12.0)
                    {
                        _touches[index] = b["id"];
                        _pressed_at[b["id"]] = _time;
                        if (b["id"] == "attack")
                            _attack_held = true;
                        else if (b["id"] == "ability")
                            _ability_held = true;
                        else if (b["id"] == "block")
                            _block_held = true;
                        ActionPressed?.Invoke(GD.Str(b["id"]));
                        GetViewport().SetInputAsHandled();
                        return;
                    }
                }
                if (pos.x < Size.x * 0.5 && !MAP_RECT.Grow(6.0).HasPoint(pos) && pos.y > 60.0 && !_stick_active)
                {
                    _touches[index] = "stick";
                    _stick_active = true;
                    _stick_origin = pos;
                    _stick_pos = pos;
                    GetViewport().SetInputAsHandled();
                }
            }
            else
            {
                string role = GD.Str(_touches.Get(index, ""));
                _touches.Erase(index);
                if (role == "stick")
                    _stick_active = false;
                else if (role == "attack")
                    _attack_held = false;
                else if (role == "ability")
                    _ability_held = false;
                else if (role == "block")
                    _block_held = false;
                if (role != "")
                    GetViewport().SetInputAsHandled();
            }
        }

        public void _Drag(int index, Vector2 pos)
        {
            if (GD.Str(_touches.Get(index, "")) == "stick")
            {
                _stick_pos = pos;
                // Let the base follow a finger that drifts too far, so direction changes stay quick.
                var off = _stick_pos - _stick_origin;
                if (off.Length() > 70.0)
                    _stick_origin = _stick_pos - off.Normalized() * 70.0;
                GetViewport().SetInputAsHandled();
            }
        }

        public Vector2 MoveVector()
        {
            var v = Vector2.ZERO;
            if (_stick_active)
            {
                var off = (_stick_pos - _stick_origin) / 60.0;
                if (off.Length() > 0.15)
                    v = off.LimitLength(1.0);
            }
            else if (!_ModalOpen())
            {
                v = new Vector2(Input.GetAxis("ui_left", "ui_right"), Input.GetAxis("ui_up", "ui_down"));
                if (Input.IsPhysicalKeyPressed(Key.A)) v.x -= 1;
                if (Input.IsPhysicalKeyPressed(Key.D)) v.x += 1;
                if (Input.IsPhysicalKeyPressed(Key.W)) v.y -= 1;
                if (Input.IsPhysicalKeyPressed(Key.S)) v.y += 1;
                v = v.LimitLength(1.0);
            }
            return v;
        }

        public bool BlockHeld()
        {
            return _block_held || (!_ModalOpen() && Input.IsPhysicalKeyPressed(Key.L));
        }

        public bool AbilityHeld()
        {
            // Knights hold ABILITY to keep the shield up (K on a keyboard).
            return _ability_held || (!_ModalOpen() && Input.IsPhysicalKeyPressed(Key.K));
        }

        public bool AttackHeld()
        {
            return _attack_held || (!_ModalOpen() && (Input.IsPhysicalKeyPressed(Key.J) || Input.IsPhysicalKeyPressed(Key.Space)));
        }
    }
}
