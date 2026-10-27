// Ported from godot/scripts/siege/siege_hud.gd (Fatebound 0.31.222) -- the drawing (see SiegeHud.cs).
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
    using UI = Fatebound.Game.Ui;
    using UI2 = Fatebound.Game.Ui2;
    using Sim = Fatebound.Sim.SiegeSim;
    using NetT = Fatebound.Game.SiegeNet;
    using CrestT = Fatebound.Game.Crest;
    using Moba = Fatebound.Sim.Moba;
    using Kits = Fatebound.Sim.MobaKits;

    public partial class SiegeHud
    {
        // ---------- drawing ----------
        protected override void _Process(double delta)
        {
            _time += delta;
            if (sim == null)
                return;
            Unit me = sim.by_id.TryGetValue(player_id, out var mu) ? mu : null;
            if (me != null && ShopOpen())
                _RefreshShop(me);
            if (BoardOpen())
            {
                _board_tick -= delta;
                if (_board_tick <= 0.0)
                {
                    _board_tick = 0.25;                      // (live: four times a second)
                    _RefreshBoard();
                }
            }
            if (_top_layer != null)
            {
                var tk = _TopKey(me);
                if (!Var.Equal(tk, _top_parts))
                {
                    _top_parts = tk;
                    _top_layer.QueueRedraw();
                }
            }
            if (btn_layer != null)
                _BtnTick(me);
            QueueRedraw();
        }

        public void _Text(Vector2 pos, string text, int size_px, Color color, Font font = null, HorizontalAlignment align = HorizontalAlignment.Center, double width = -1.0)
        {
            var f = font != null ? font : _bold;
            if (align == HorizontalAlignment.Center && width < 0)
            {
                width = 400.0;
                pos.x -= (float)(width * 0.5);
            }
            _ci.DrawStringOutline(f, pos, text, align, width, size_px, 5, new Color(0, 0, 0, 0.6));
            _ci.DrawString(f, pos, text, align, width, size_px, UI.Ink(color));   // (0.31.195: no yellow text)
        }

        // ---------- the top layer (0.31.160) ----------
        public Control _top_layer = null;
        public Control btn_layer = null;
        public GDict _btn_nodes = new GDict();                          // "attack", "ability", ..., "recall" (HOME), "stick", "learn", "recall_bar" -> Control
        public GDict _btn_st = new GDict();                             // the same -> what it shows (drawn from this)
        public int btn_draws = 0;                            // (tests: canvas items drawn again)
        public CanvasItem _ci;                    // what _text and the top's drawing draw on: the HUD, or the top layer (self: set in the constructor)
        public GArray _top_parts = new GArray();

        public GArray _TopKey(Unit me)
        {
            // everything _draw_top shows, as it shows it (whole numbers, ring and bar sizes in steps): when it changes, it's redrawn
            if (me == null)
                return new GArray();
            int t = me.team;
            var lv = me.level;
            var k = GArray.Of(Size.x, Size.y, t, GD.Int(GD.Maxf(0.0, sim.match_time - sim.time)),
                GD.Int(GD.Ceil(sim.moba.KingFrac(t) * 100.0)), GD.Int(GD.Ceil(sim.moba.KingFrac(1 - t) * 100.0)),
                sim.moba.KingOpen(t), sim.moba.KingOpen(1 - t), sim.kills[t], sim.kills[1 - t],
                TowersStanding(t), TowersStanding(1 - t), lv, GD.Int(XpFrac(me) * 120.0),
                GD.Int(me.gold), NetT._V(me.items ?? new List<string>()));
            var b = me.buffs;
            foreach (var bk in new[] { "arcane", "ember", "lord" })
                k.Append(GD.Int(GD.Maxf(0.0, (b != null ? b.Get(bk, -1.0) : -1.0) - sim.time)));
            k.Append(sim.moba.wyrm_stacks[GD.Clampi(t, 0, 1)]);
            return k;
        }

        public void _DrawTopLayer()
        {
            if (sim == null)
                return;
            Unit me = sim.by_id.TryGetValue(player_id, out var mu) ? mu : null;
            if (me == null)
                return;
            var t0 = Time.GetTicksUsec();
            _ci = _top_layer;
            _DrawTop(me);
            _ci = this;
            if (diag != null)
                diag.AddTime("hud", Time.GetTicksUsec() - t0);
        }

        protected override void _Draw()
        {
            var t0 = Time.GetTicksUsec();
            if (diag != null)
                diag.Mark("hud draw");
            _DrawHud();
            if (diag != null)
            {
                diag.AddTime("hud", Time.GetTicksUsec() - t0);
                diag.Mark("hud drawn, rendering");
            }
        }

        public bool prof_on = false;                      // (tests/moba_bench.gd: microseconds per part of the draw in prof)
        public GDict prof = new GDict();

        public long _Ph(string key, long t0)
        {
            var now = Time.GetTicksUsec();
            prof[key] = (long)prof.Get(key, 0) + (now - t0);
            return now;
        }

        public void _DrawHud()
        {
            if (sim == null)
                return;
            Unit me = sim.by_id.TryGetValue(player_id, out var mu) ? mu : null;
            if (me == null)
                return;
            var tq = prof_on ? Time.GetTicksUsec() : 0;
            var w = Size.x;
            if (_top_layer == null)
                _DrawTop(me);                           // (no layer: drawn with the rest)
            _DrawShopPulse(me);
            _DrawCampTimers();
            if (prof_on) tq = _Ph("top", tq);
            // Toast.
            var age = _time - _toast_at;
            if (age < 2.6 && _toast != "")
            {
                var c = _toast_color;
                c.a = (float)GD.Clampf(2.6 - age, 0.0, 1.0);
                _Text(new Vector2(w * 0.5, Size.y * 0.34), _toast, 18, c, _bold);     // (0.31.216: a third down the screen; 284 in portrait)
            }
            _DrawKillFeed();
            _DrawIdle(me);
            _DrawRejoin();
            if (prof_on) tq = _Ph("feed", tq);
            _DrawBars();
            if (prof_on) tq = _Ph("bars", tq);
            _DrawPings();
            _DrawGateBars();
            _DrawKingMarker(me);
            _DrawNumbers();
            if (prof_on) tq = _Ph("pings..numbers", tq);
            // (0.31.163, Kevin: "Remove both": the fps / memory readout isn't shown -- it's in the diag log's STAT lines)
            if (!_ModalOpen())
                _DrawPicks(me);                           // (before the respawn line: the hand plays while you're down too)
            if (prof_on) tq = _Ph("cards+picks", tq);
            if (me.state == "dead")
            {
                _Text(new Vector2(w * 0.5, Size.y * 0.45), GD.Fmt("RESPAWNING IN %d", GD.Int(GD.Ceil(me.respawn_at - sim.time))), 22, VisualTheme.GOLD, _title);
                return;
            }
            // (the stick and the buttons: their own layer -- _btn_tick)
        }

        public Control _BtnNode(string id)
        {
            Control n = _btn_nodes.Get(id).As<Control>();
            if (n == null)
            {
                n = new Control();
                n.Name = "Btn_" + id;
                n.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                n.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
                var bid = id;
                n.Draw += () => _DrawBtnItem(bid);
                btn_layer.AddChild(n);
                _btn_nodes[id] = n;
            }
            return n;
        }

        public void _BtnItem(string id, GDict st, Var key)
        {
            // shown, and drawn again if what it shows changed
            var n = _BtnNode(id);
            if (!n.Visible)
                n.Visible = true;
            if (!n.HasMeta("key") || (Var)n.GetMeta("key") != key)
            {
                n.SetMeta("key", key);
                _btn_st[id] = st;
                n.QueueRedraw();
            }
        }

        public void _BtnTick(Unit me)
        {
            var t0 = Time.GetTicksUsec();
            var show = me != null && GD.Str(me.state) != "dead" && !_ModalOpen();
            if (btn_layer.Visible != show)
                btn_layer.Visible = show;
            if (!show)
                return;
            var seen = new GDict();
            // Stick.
            var stick = GDict.Of("active", _stick_active, "o", _stick_origin.Round(), "knob", (_stick_origin + (_stick_pos - _stick_origin).LimitLength(60.0)).Round(),
                "touch", _touchscreen, "h", Size.y);
            _BtnItem("stick", stick, stick.Values());
            seen["stick"] = true;
            // Combat buttons.
            foreach (var b in _Buttons())
            {
                var st = _ButtonState(b.D, me);
                _BtnItem(GD.Str(b["id"]), st, _ButtonKey(st));
                seen[GD.Str(b["id"])] = true;
            }
            // 0.31.217: the + over a skill a point can go on (pulsing, at 15 steps a second)
            var spots = LearnSpots(me);
            var lk = GArray.Of(!spots.IsEmpty() ? Math.Floor(_time * 15.0) : -1.0);
            foreach (var sp in spots)
                lk.Append(sp["c"]);
            _BtnItem("learn", GDict.Of("spots", spots), lk);
            seen["learn"] = true;
            // 0.31.181: RECALLING and its bar while you channel home
            var rc = new GDict();
            if (sim.moba != null && sim.Recalling(me))
            {
                var left = GD.Maxf(0.0, me.recall_until - sim.time);
                rc = GDict.Of("left", GD.Snappedf(left, 0.1), "w", Size);
            }
            _BtnItem("recall_bar", rc, rc.Values());
            seen["recall_bar"] = true;
            foreach (var id in _btn_nodes)
            {
                if (!seen.Has(id) && _btn_nodes[id].As<Control>().Visible)
                    _btn_nodes[id].As<Control>().Visible = false;
            }
            var dt = Time.GetTicksUsec() - t0;
            if (prof_on)
                prof["buttons.state"] = (long)prof.Get("buttons.state", 0) + dt;
            if (diag != null)
                diag.AddTime("hud", dt);
        }

        public void _DrawBtnItem(string id)
        {
            GDict st = _btn_st.Get(id, new GDict()).D;
            Control n = _btn_nodes.Get(id).As<Control>();
            if (n == null)
                return;
            var t0 = Time.GetTicksUsec();
            btn_draws += 1;
            _ci = n;
            switch (id)
            {
                case "stick":
                    if ((bool)st.Get("active", false))
                    {
                        _ci.DrawCircle(st["o"].V2, 62, new Color(1, 1, 1, 0.08));
                        _ci.DrawArc(st["o"].V2, 62, 0, GD.TAU, 40, new Color(1, 1, 1, 0.3), 2.0, true);
                        _ci.DrawCircle(st["knob"].V2, 26, new Color(1, 1, 1, 0.35));
                    }
                    else if ((bool)st.Get("touch", false))
                    {
                        var home = new Vector2(120, Size.y - 110);
                        _ci.DrawArc(home, 62, 0, GD.TAU, 40, new Color(1, 1, 1, 0.14), 2.0, true);
                        _Text(home + new Vector2(0, 6), "MOVE", 12, new Color(1, 1, 1, 0.35), _bold);
                    }
                    break;
                case "learn":
                    _DrawLearn(st.Get("spots", new GArray()).A);
                    break;
                case "recall_bar":
                    _DrawRecall(st);
                    break;
                default:
                    if (!st.IsEmpty())
                        _DrawButton(st);
                    break;
            }
            _ci = this;
            var dt = Time.GetTicksUsec() - t0;
            if (prof_on)
                prof["buttons.draw"] = (long)prof.Get("buttons.draw", 0) + dt;
            if (diag != null)
                diag.AddTime("hud", dt);
        }

        public void _DrawTop(Unit me)
        {
            // the scoreboard and, under it, your level, gold and items -- on the top layer (0.31.160). 0.31.178 (Kevin: "Clean up
            // and make this UI much better looking. Player health bar doesn't need to be there since they already have one above
            // head. The objective doesn't need to be there ect. Make the other stuff prettier"): no health bar, class line or
            // objective line any more (your King under attack shows on the bar itself, _draw_king_alert)
            _DrawScoreBar(me);
            _DrawMobaStatus(me);
        }

        public Rect2 ScoreBarRect()
        {
            // 0.31.216: small, in the top middle (the whole width until then)
            var w = GD.Minf(BAR_W, Size.x - 2.0 * (MAP_RECT.End.x + 8.0) - 110.0);
            return new Rect2(Size.x * 0.5 - w * 0.5, 6, w, BAR_H);
        }

        public Rect2 ClockRect()
        {
            // the clock's plate in the middle of the bar, standing a little proud of it
            return new Rect2(Size.x * 0.5 - 46.0, 3.0, 92.0, BAR_H + 6.0);
        }

        public int TowersStanding(int t)
        {
            var n = 0;
            foreach (var tw in sim.moba.towers)
            {
                if (tw.team == t && !tw.dead)
                    n += 1;
            }
            return n;
        }

        public static Texture2D HudIcon(string name)
        {
            // the menus' glossy icons (assets/ui/v2/icons), for the bar
            if (!_hud_icons.Has(name))
            {
                var p = GD.Fmt("res://assets/ui/v2/icons/%s.png", name);
                _hud_icons[name] = ResourceLoader.Exists(p) ? Var.Of(ResourceLoader.Load(p)) : Var.Nil;
            }
            return _hud_icons[name].As<Texture2D>();
        }

        public static GDict _hud_icons = new GDict();
        public GArray _wash_styles = new GArray();
        public StyleBox _clock_style = null;

        public void _IconAt(string name, Rect2 r, Color? mod = null)
        {
            var tx = HudIcon(name);
            if (tx != null)
                _ci.DrawTextureRect(tx, r, false, mod ?? Color.WHITE);
        }

        public void _DrawScoreBar(Unit me)
        {
            // 0.31.178: your side on the left in blue, theirs on the right in red (no labels): each King's crown and health,
            // then the towers still standing and the knockouts; the clock on its own plate in the middle. Tapping it opens the
            // live board (0.31.176).
            var bar = ScoreBarRect();
            if (_bar_style == null)
            {
                _bar_style = VisualTheme.Panel(new Color(0.035, 0.07, 0.1, 0.94), VisualTheme.GOLD_DARK, 12, 8);
                for (int s = 0; s < 2; s++)
                {
                    var ws = new StyleBoxFlat();
                    Color c = TEAM_COLORS[s];
                    ws.BgColor = new Color(c.Darkened(0.42), 0.62);
                    ws.BorderColor = new Color(c, 0.45);
                    ws.SetBorderWidthAll(0);
                    ws.BorderWidthBottom = 2;
                    ws.SetCornerRadiusAll(8);
                    ws.AntiAliasing = true;
                    _wash_styles.Append(Var.Of(ws));
                }
                _clock_style = VisualTheme.Panel(new Color(0.02, 0.04, 0.06, 0.98), VisualTheme.GOLD, 12, 6);
            }
            _ci.DrawStyleBox(_bar_style, bar);
            int t = me.team;
            var cr = ClockRect();
            var inner = bar.Grow(-6.0);
            _ci.DrawStyleBox(_wash_styles[0].As<StyleBox>(), new Rect2(inner.position, new Vector2(cr.position.x - inner.position.x + 4.0, inner.size.y)));
            _ci.DrawStyleBox(_wash_styles[1].As<StyleBox>(), new Rect2(new Vector2(cr.End.x - 4.0, inner.position.y), new Vector2(inner.End.x - cr.End.x + 4.0, inner.size.y)));
            for (int side = 0; side < 2; side++)
            {
                // 0.31.216: one row a side -- the King's crown and health, then the towers he still has and the side's knockouts
                var team = side == 0 ? t : 1 - t;
                var right = side == 1;
                var x0 = !right ? inner.position.x + 6.0 : inner.End.x - 6.0;
                var sgn = !right ? 1.0 : -1.0;
                var cy = inner.GetCenter().y;
                var crown = new Rect2(new Vector2(!right ? x0 : x0 - 26.0, cy - 13.0), new Vector2(26, 26));
                if (right && sim.moba.KingOpen(team))
                    _ci.DrawCircle(crown.GetCenter(), 15.0, new Color(1.0, 0.82, 0.3, 0.35));
                _IconAt("crown", crown);
                var pct = GD.Fmt("%d%%", GD.Int(GD.Ceil(sim.moba.KingFrac(team) * 100.0)));
                var col = VisualTheme.GOLD;
                if (sim.moba.KingFrac(team) < 0.995)
                    col = !right ? new Color("#ffe9a8") : new Color("#ffd0b8");
                _Text(new Vector2(x0 + sgn * 29.0 - (right ? 56.0 : 0.0), cy + 7.0), pct, 18, col, _title,
                    right ? HorizontalAlignment.Right : HorizontalAlignment.Left, 56.0);
                var parts = GArray.Of(GArray.Of("castle", GD.Str(TowersStanding(team))), GArray.Of("swords", GD.Str(sim.kills[team])));
                var x = x0 + sgn * 92.0;
                for (int pi = 0; pi < parts.Size(); pi++)
                {
                    GArray part = parts[pi].A;
                    var txt = GD.Str(part[1]);
                    var tw = _bold.GetStringSize(txt, HorizontalAlignment.Left, -1, 15).x;
                    if (right)
                    {
                        _IconAt(GD.Str(part[0]), new Rect2(new Vector2(x - 17.0, cy - 9.0), new Vector2(17, 17)));
                        _Text(new Vector2(x - 21.0 - tw, cy + 6.0), txt, 15, new Color("#eef3f6"), _bold, HorizontalAlignment.Left, tw + 4.0);
                        x -= 21.0 + tw + 10.0;
                    }
                    else
                    {
                        _IconAt(GD.Str(part[0]), new Rect2(new Vector2(x, cy - 9.0), new Vector2(17, 17)));
                        _Text(new Vector2(x + 21.0, cy + 6.0), txt, 15, new Color("#eef3f6"), _bold, HorizontalAlignment.Left, tw + 4.0);
                        x += 21.0 + tw + 10.0;
                    }
                }
            }
            // the clock
            _ci.DrawStyleBox(_clock_style, cr);
            var left = GD.Maxf(0.0, sim.match_time - sim.time);
            _Text(new Vector2(cr.GetCenter().x, cr.position.y + 36.0), GD.Fmt("%d:%02d", GD.Int(left) / 60, GD.Int(left) % 60), 24,
                left > 60 ? new Color("#eef3f6") : VisualTheme.RED, _title);
        }

        public bool KingAlert(Unit me)
        {
            // your King open and an enemy at him
            return sim.moba != null && sim.moba.KingThreat(me.team) != null && sim.moba.KingOpen(me.team);
        }

        public void _DrawKingAlert(Unit me)
        {
            // 0.31.178: your King under attack -- your half of the bar beats red, and a line under the clock says it
            if (!KingAlert(me))
                return;
            var pulse = 0.5 + 0.5 * Math.Sin(_time * 7.0);
            var bar = ScoreBarRect().Grow(-6.0);
            var half = new Rect2(bar.position, new Vector2(ClockRect().position.x - bar.position.x + 4.0, bar.size.y));
            if (_alert_style == null)
            {
                _alert_style = new StyleBoxFlat();
                _alert_style.DrawCenter = false;
                _alert_style.SetBorderWidthAll(2);
                _alert_style.SetCornerRadiusAll(8);
                _alert_style.AntiAliasing = true;
            }
            _alert_style.BorderColor = new Color(1.0, 0.25, 0.2, 0.45 + 0.5 * pulse);
            DrawStyleBox(_alert_style, half);
            DrawRect(half.Grow(-2.0), new Color(1.0, 0.15, 0.1, 0.12 * pulse));
            _Text(new Vector2(Size.x * 0.5, ScoreBarRect().End.y + 18.0), "KING UNDER ATTACK!", 13, new Color(1.0, 0.45, 0.38, 0.65 + 0.35 * pulse), _bold);
        }

        public StyleBoxFlat _alert_style = null;

        public void _DrawRecall(GDict rc)
        {
            // 0.31.181: "RECALLING" and its bar under you while you channel home
            if (rc.IsEmpty())
                return;
            double left = (double)rc["left"];
            var f = GD.Clampf(1.0 - left / Sim.RECALL_TIME, 0.0, 1.0);
            var w = GD.Minf(200.0, Size.x * 0.5);
            var r = new Rect2(new Vector2(Size.x * 0.5 - w * 0.5, Size.y * 0.6), new Vector2(w, 10.0));
            _ci.DrawRect(r.Grow(2.0), new Color(0.04, 0.03, 0.1, 0.8));
            _ci.DrawRect(new Rect2(r.position, new Vector2(w * f, r.size.y)), new Color("#b9a8ff"));
            _ci.DrawRect(r.Grow(2.0), new Color("#6d5ed0"), false, 1.5);
            _Text(new Vector2(Size.x * 0.5, r.position.y - 6.0), GD.Fmt("RECALLING  %.1f", left), 13, new Color("#e6deff"), _bold);
        }
        public void _DrawIdle(Unit me)
        {
            // 0.31.119: "A BOT IS PLAYING FOR YOU" while the server's bot holds my unit (I gave no input for a while)
            if (idle_kick_at < 0.0 || !me.bot)
                return;
            var w = Size.x;
            var left = GD.Maxf(0.0, idle_kick_at - Time.GetTicksMsec() / 1000.0);
            var r = new Rect2(w * 0.5 - GD.Minf(180.0, w * 0.45), Size.y * 0.3, GD.Minf(360.0, w * 0.9), 74);
            if (_idle_style == null)
                _idle_style = VisualTheme.Panel(new Color(0.06, 0.04, 0.02, 0.9), VisualTheme.GOLD, 12, 8);
            DrawStyleBox(_idle_style, r);
            var pulse = 0.75 + 0.25 * Math.Sin(_time * 4.0);
            _Text(new Vector2(w * 0.5, r.position.y + 30), "A BOT IS PLAYING FOR YOU", 20, new Color(VisualTheme.GOLD, pulse), _title);
            _Text(new Vector2(w * 0.5, r.position.y + 56), GD.Fmt("Move or attack to take over · removed in %d:%02d", GD.Int(left) / 60, GD.Int(left) % 60), 13, VisualTheme.TEXT, _bold);
        }

        public StyleBox _idle_style = null;

        // ---------------- kill feed (0.31.120, Kevin: "kill feed") ----------------
        // On the right under the toast line: who knocked out whom, towers and gates broken, epic monsters slain --
        // newest on top, KF_MAX lines, each KF_LIFE seconds then fading. Players by name (you: "You", on a gold plate),
        // bots by class (0.31.177: a 5v5 bot's hero by its name, "Bot Alfred"), in their side's colour; a knockout with no one behind it (a fall, the moat) shows a skull.
        public const int KF_MAX = 4;
        public const double KF_LIFE = 6.0;
        public const int KF_PX = 12;
        public const double KF_TOP = 74.0;                  // (0.31.216: under pause and quick chat on the right; 202 in portrait)
        public const double KF_STEP = 19.0;
        public GArray kill_feed = new GArray();                  // newest first: {"parts": [[text, colour], ...], "at": _time, "me": I'm in it}
        public bool kill_feed_on = true;                   // (a match can turn it off)

        public GArray KfName(string id)
        {
            // [text, colour] for a unit in the feed
            Unit u = sim.by_id.TryGetValue(id, out var uu) ? uu : null;
            if (u == null)
                return GArray.Of("?", VisualTheme.TEXT);
            Color col = TEAM_COLORS[Vt(u.team)].Lightened(0.15);
            if (id == player_id)
                return GArray.Of("You", VisualTheme.GOLD);
            if (net_names.Has(id))
                return GArray.Of(GD.Str(net_names[id]).Left(16), col);
            if (u.hero && sim.moba != null)
                return GArray.Of(Moba.BotLabel(u), col);       // 0.31.177: a bot's hero by its name, as over its head
            return GArray.Of(sim.ClassLabel(u), col);
        }

        public void _KfAdd(GArray parts, bool mine)
        {
            kill_feed.PushFront(GDict.Of("parts", parts, "at", _time, "me", mine));
            if (kill_feed.Size() > KF_MAX)
                kill_feed.Resize(KF_MAX);
            QueueRedraw();
        }

        public void _KfEvent(Ev e, Unit me)
        {
            if (!kill_feed_on)
                return;
            var grey = new Color("#c9d1dc");
            switch (e.K)
            {
                case "lord_down":
                    {
                        var ours_l = e.I("team", -1) == me.team;
                        var lb = e.S("by", "");
                        if (lb != "" && sim.by_id.ContainsKey(lb))
                            _KfAdd(GArray.Of(KfName(lb), GArray.Of(" slew the Bone Lord", ours_l ? VisualTheme.GOLD : VisualTheme.RED)), lb == player_id);
                        break;
                    }
                case "wyrm_down":
                    {
                        var ours_k = e.I("team", -1) == me.team;
                        var wb = e.S("by", "");
                        if (wb != "" && sim.by_id.ContainsKey(wb))
                            _KfAdd(GArray.Of(KfName(wb), GArray.Of(" slew the Grave Wyrm", ours_k ? VisualTheme.GOLD : VisualTheme.RED)), wb == player_id);
                        break;
                    }
                case "buff":
                    if (e.S("id", "") != GD.Str(player_id) && sim.by_id.ContainsKey(e.S("id", "")))
                        _KfAdd(GArray.Of(KfName(e.S("id")), GArray.Of(GD.Fmt(" took %s", Moba.BUFF_NAMES.TryGetValue(e.S("buff"), out var bn) ? bn : ""), e.S("buff") == "arcane" ? new Color("#7fb8ff") : new Color("#ff9a5a"))), false);
                    break;
                case "tower_down":
                    {
                        var ours_t = e.I("team", -1) == me.team;
                        _KfAdd(GArray.Of(GArray.Of(GD.Fmt("%s %s %s tower fell", ours_t ? "Our" : "Their", GD.Str(Moba.LANE_NAMES[e.I("lane")]),
                            GArray.Of("outer", "inner", "high ground")[GD.Clampi(e.I("tier") - 1, 0, 2)]), ours_t ? VisualTheme.RED : VisualTheme.GOLD)), false);
                        if (e.I("tier", 0) == 3)                 // 0.31.217: a lane broken -- that side's King can be hit now
                            Toast(!ours_t ? "THEIR KING IS OPEN -- break him to win!" : "OUR KING IS EXPOSED -- defend him!",
                                !ours_t ? VisualTheme.GOLD : VisualTheme.RED);
                        break;
                    }
                case "death":
                    {
                        if (e.B("minion", false) || e.B("mon", false))
                            return;                                     // (0.31.155: minions fall all the time; 0.31.157: so do monsters)
                        var victim = e.S("id", "");
                        var by = e.S("by", "");
                        if (!sim.by_id.ContainsKey(victim))
                            return;
                        if (by == "" || by == victim || !sim.by_id.ContainsKey(by))
                            _KfAdd(GArray.Of(GArray.Of("☠", grey), GArray.Of(" ", grey), KfName(victim)), victim == player_id);
                        else
                            _KfAdd(GArray.Of(KfName(by), GArray.Of("  ⚔  ", new Color(1, 1, 1, 0.85)), KfName(victim)), victim == player_id || by == player_id);
                        break;
                    }
                case "gate_broken":
                    {
                        var gi = e.I("gate", -1);
                        if (gi < 0 || gi >= sim.gates.Count)
                            return;
                        Gate g = sim.gates[gi];
                        var ours3 = g.team == me.team;
                        var what = GD.Fmt("the %s gate", GD.Str(g.side ?? "").ToLowerInvariant());
                        var by2 = e.S("by", "");
                        var tail = GArray.Of(GD.Fmt(" broke %s %s", ours3 ? "our" : "their", what.TrimPrefix("the ")), ours3 ? VisualTheme.RED : VisualTheme.GOLD);
                        if (by2 != "" && sim.by_id.ContainsKey(by2))
                            _KfAdd(GArray.Of(KfName(by2), tail), by2 == player_id);
                        else
                            _KfAdd(GArray.Of(GArray.Of(GD.Fmt("%s %s fell", ours3 ? "Our" : "Their", what.TrimPrefix("the ")), ours3 ? VisualTheme.RED : VisualTheme.GOLD)), false);
                        break;
                    }
            }
        }

        public void _DrawKillFeed()
        {
            if (kill_feed.IsEmpty())
                return;
            var right = Size.x - 10.0;
            var y = KF_TOP;
            var keep = new GArray();
            foreach (var it in kill_feed)
            {
                double age = _time - (double)it["at"];
                if (age > KF_LIFE)
                    continue;
                keep.Append(it);
                var a = GD.Clampf((KF_LIFE - age) / 0.6, 0.0, 1.0) * GD.Clampf(age / 0.15, 0.0, 1.0);
                var w = 0.0;
                foreach (var part in it["parts"])
                    w += _bold.GetStringSize(GD.Str(part[0]), HorizontalAlignment.Left, -1, KF_PX).x;
                w = GD.Minf(w, Size.x * 0.56);
                var plate = new Rect2(right - w - 12.0, y - 14.0, w + 12.0, 18.0);
                DrawRect(plate, new Color(0.03, 0.05, 0.1, 0.55 * a));
                if ((bool)it["me"])
                    DrawRect(plate, new Color(VisualTheme.GOLD, 0.8 * a), false, 1.0);
                var x = plate.position.x + 6.0;
                foreach (var part in it["parts"])
                {
                    var t = GD.Str(part[0]);
                    Color c = part[1].As<Color>();
                    c.a *= (float)a;
                    var tw = _bold.GetStringSize(t, HorizontalAlignment.Left, -1, KF_PX).x;
                    DrawStringOutline(_bold, new Vector2(x, y), t, HorizontalAlignment.Left, -1, KF_PX, 4, new Color(0, 0, 0, 0.55 * a));
                    DrawString(_bold, new Vector2(x, y), t, HorizontalAlignment.Left, -1, KF_PX, c);
                    x += tw;
                }
                y += KF_STEP;
            }
            if (keep.Size() != kill_feed.Size())
                kill_feed = keep;
        }

        // ---------- 5V5 (0.31.155) ----------
        // Under the bar on the left (0.31.178): your level on a medallion ringed by your XP, the gold-and-shop button beside it,
        // your six item slots under them, then the buffs you carry. A level-up: three upgrade chips in the middle of the screen
        // until you tap one (siege_mode -> sim "pick").
        public double XpFrac(Unit me)
        {
            var lv = me.level;
            if (lv >= Moba.LEVEL_MAX)
                return 1.0;
            return GD.Clampf(me.xp / sim.moba.Need(lv), 0.0, 1.0);
        }

        public Vector2 LevelCenter()
        {
            return new Vector2(MAP_RECT.position.x + 24.0, MAP_RECT.End.y + 30.0);       // (0.31.216: under the map; 36, 108 until then)
        }

        public void _DrawMobaStatus(Unit me)
        {
            var c = LevelCenter();
            var lv = me.level;
            _ci.DrawCircle(c + new Vector2(0, 2), 27.0, new Color(0, 0, 0, 0.35));                   // (its shadow)
            _ci.DrawCircle(c, 26.0, new Color(0.03, 0.06, 0.08, 0.95));
            _ci.DrawArc(c, 22.5, 0.0, GD.TAU, 48, new Color(0.0, 0.0, 0.0, 0.55), 5.0, true);          // the XP track
            var f = XpFrac(me);
            if (f > 0.0)
                _ci.DrawArc(c, 22.5, -GD.PI * 0.5, -GD.PI * 0.5 + GD.TAU * f, GD.Maxi(4, GD.Int(48.0 * f)), new Color("#ffd65a"), 5.0, true);
            _ci.DrawArc(c, 26.0, 0.0, GD.TAU, 48, VisualTheme.GOLD_DARK, 1.5, true);
            _ci.DrawArc(c, 19.5, 0.0, GD.TAU, 40, new Color(VisualTheme.GOLD_DARK, 0.7), 1.0, true);
            _Text(c + new Vector2(0, -6.0), "LV", 9, VisualTheme.GOLD, _bold);
            _Text(c + new Vector2(0, 13.0), GD.Str(lv), lv < 10 ? 20 : 18, new Color("#fff4d6"), _title);
            _DrawGoldAndItems(me);                      // 0.31.157 (0.31.160: the camp timers and the shop's pulse per frame, in _draw_hud)
        }

        public bool _PicksOpen()
        {
            Unit me = sim.by_id.TryGetValue(player_id, out var mu) ? mu : null;
            return me != null && me.picks != null && me.picks.Count != 0;
        }

        public Rect2 PickRect(int i)
        {
            var w = GD.Minf(124.0, (Size.x - 40.0) / 3.0);
            var x0 = (Size.x - (w * 3.0 + 16.0)) * 0.5;
            return new Rect2(x0 + (w + 8.0) * (double)i, ScoreBarRect().End.y + 30.0, w, 48.0);     // (0.31.216: 312 in portrait)
        }

        public StyleBox _pick_style = null;

        public void _DrawPicks(Unit me)
        {
            var picks = me.picks;
            if (picks == null || picks.Count == 0)
                return;
            List<string> offer = picks[0];
            if (_pick_style == null)
                _pick_style = VisualTheme.Panel(new Color(0.08, 0.05, 0.16, 0.92), VisualTheme.GOLD, 10, 6);
            var pulse = 0.75 + 0.25 * Math.Sin(_time * 5.0);
            _Text(new Vector2(Size.x * 0.5, ScoreBarRect().End.y + 22.0), GD.Fmt("LEVEL %d · CHOOSE ONE%s", me.level - picks.Count + 1, picks.Count > 1 ? GD.Fmt("  (+%d more)", picks.Count - 1) : ""),
                13, new Color(1.0, 0.85, 0.4, pulse), _bold);
            for (int i = 0; i < offer.Count; i++)
            {
                var r = PickRect(i);
                DrawStyleBox(_pick_style, r);
                var nm = _UpgradeName(GD.Str(offer[i]));
                var have = me.ups != null ? me.ups.Get(GD.Str(offer[i]), 0) : 0;
                _Text(new Vector2(r.GetCenter().x, r.position.y + 25.0), nm, nm.Length <= 12 ? 12 : 10, Color.WHITE, _bold);
                if (have > 0)
                    _Text(new Vector2(r.GetCenter().x, r.position.y + 42.0), GD.Fmt("have %d", have), 10, new Color(1, 1, 1, 0.6), _font);
            }
        }

        // (sim.moba.UPGRADES.get(key, {}).get("name", key): the C# sim keeps UPGRADES as (key, name) pairs)
        static string _UpgradeName(string key)
        {
            foreach (var up in Moba.UPGRADES)
                if (up.key == key) return up.name;
            return key;
        }

        public void _DrawRejoin()
        {
            // 0.31.120: "RECONNECTING..." while the game gets back onto my seat
            if (rejoin_until < 0.0)
                return;
            var w = Size.x;
            var left = GD.Maxf(0.0, rejoin_until - Time.GetTicksMsec() / 1000.0);
            var r = new Rect2(w * 0.5 - GD.Minf(170.0, w * 0.42), Size.y * 0.42, GD.Minf(340.0, w * 0.84), 70);
            if (_rejoin_style == null)
                _rejoin_style = VisualTheme.Panel(new Color(0.02, 0.05, 0.12, 0.92), new Color("#5fb6ff"), 12, 8);
            DrawStyleBox(_rejoin_style, r);
            var dots = ".".Repeat(1 + GD.Int(_time * 2.0) % 3);
            _Text(new Vector2(w * 0.5, r.position.y + 30), "RECONNECTING" + dots, 20, new Color("#bfe3ff"), _title);
            _Text(new Vector2(w * 0.5, r.position.y + 54), GD.Fmt("Your seat is held for you · %d s", GD.Int(GD.Ceil(left))), 13, VisualTheme.TEXT, _bold);
        }

        public StyleBox _rejoin_style = null;

        public void _DrawBars()
        {
            if (bars_source == null || project == null)
                return;
            var tags = new GArray();
            foreach (var b in bars_source())
            {
                if (on_screen != null && !on_screen(b["pos"].V3))
                    continue;
                Vector2 p = project(b["pos"].V3);
                if (p.y < 150.0)
                    continue;
                var r = new Rect2(p - new Vector2(17, 3), new Vector2(34, 5));
                if ((bool)b.D.Get("wide", false))
                    r = new Rect2(p - new Vector2(34, 4), new Vector2(68, 8));         // (0.31.155: a 5v5 tower)
                DrawRect(r.Grow(1.0), new Color(0, 0, 0, 0.7));
                DrawRect(new Rect2(r.position, new Vector2(r.size.x * (double)b["fill"], r.size.y)), b["color"].As<Color>());
                if (b.D.Has("name"))                                 // 0.31.86: a live player's name over the bar
                    tags.Append(GArray.Of(p, b));
            }
            _DrawNameTags(tags);
        }

        // ---------------- names and titles over heads (0.31.86, 0.31.87) ----------------
        // Each live player's name on a dark plate over their bar, in their side's colour; a title joins it with its
        // punctuation (Net.title_parts), in its rarity's colour, and the plate shows the rarity: common plain, rare a blue rim,
        // epic a purple rim and a slow glow, legendary a gold rim, a glow, a light band sweeping the letters and two sparkles.
        public const int TAG_PX = 12;
        public static readonly GDict TAG_COL = GDict.Of("common", new Color("#cfd8e0"), "rare", new Color("#6cc4ff"), "epic", new Color("#d6a2ff"), "legendary", new Color("#ffc23d"));
        public static readonly GDict TAG_RIM = GDict.Of("rare", GArray.Of(new Color("#5fb6ff"), 1), "epic", GArray.Of(new Color("#b86bff"), 2), "legendary", GArray.Of(new Color("#ffc23d"), 2));
        public static readonly GDict TAG_GLOW = GDict.Of("epic", new Color(0.62, 0.25, 1.0, 0.55), "legendary", new Color(1.0, 0.55, 0.1, 0.6));
        public GDict _tag_styles = new GDict();

        public StyleBoxFlat _TagStyle(string key)
        {
            if (!_tag_styles.Has(key))
            {
                var sb = new StyleBoxFlat();
                sb.AntiAliasing = true;
                if (key.BeginsWith("glow"))
                    sb.SetCornerRadiusAll(9 + 2 * (int)key.Substr(4).ToInt());
                else
                {
                    sb.BgColor = new Color(0.03, 0.04, 0.09, 0.62);
                    sb.SetCornerRadiusAll(8);
                    if (TAG_RIM.Has(key))
                    {
                        sb.BorderColor = TAG_RIM[key][0].As<Color>();
                        sb.SetBorderWidthAll(GD.Int(TAG_RIM[key][1]));
                    }
                }
                _tag_styles[key] = Var.Of(sb);
            }
            return _tag_styles[key].As<StyleBoxFlat>();
        }

        public void _DrawNameTags(GArray tags)
        {
            // The nearest (lowest on screen) keep their place; a plate that would cover one already placed steps up.
            tags.SortCustom((a, b) => a[0].V2.y > b[0].V2.y);
            var placed = new List<Rect2>();
            var t = Time.GetTicksMsec() / 1000.0;
            foreach (var tg in tags)
            {
                Vector2 p = tg[0].V2;
                GDict b = tg[1].D;
                var parts = NetT.TitleParts(GD.Str(b["name"]), GD.Str(b.Get("title", "")));
                var w = 0.0;
                foreach (var part in parts)
                    w += _bold.GetStringSize(GD.Str(part[0]), HorizontalAlignment.Left, -1, TAG_PX).x;
                var plate = new Rect2(p.x - w * 0.5 - 6.0, p.y - 7.0 - 13.0, w + 12.0, 17.0);
                for (int _i = 0; _i < 4; _i++)
                {
                    var hit = false;
                    foreach (var r in placed)
                    {
                        if (r.Intersects(plate))
                        {
                            hit = true;
                            break;
                        }
                    }
                    if (!hit)
                        break;
                    plate.position.y -= 18.0f;
                }
                var cc = GD.Str(b.Get("crest", ""));
                if (cc != "")
                {
                    // 0.31.196: the clan's crest left of the plate (the plate moves over to keep the pair centred)
                    plate.position.x += 8.0f;
                    var cr = new Rect2(plate.position.x - 17.0, plate.position.y - 1.5, 15.0, 15.0 * CrestT.ASPECT);
                    placed.Add(plate.Merge(cr));
                    _DrawTag(plate, parts, NetT.TitleRarity(GD.Str(b.Get("title", ""))), b.Has("name_color") ? b["name_color"].As<Color>() : Color.WHITE, t);
                    CrestT.DrawOn(this, cc, cr);
                    continue;
                }
                placed.Add(plate);
                _DrawTag(plate, parts, NetT.TitleRarity(GD.Str(b.Get("title", ""))), b.Has("name_color") ? b["name_color"].As<Color>() : Color.WHITE, t);
            }
        }

        public void _DrawTag(Rect2 plate, GArray parts, string rarity, Color side_col, double t)
        {
            if (TAG_GLOW.Has(rarity))
            {
                Color glow = TAG_GLOW[rarity].As<Color>();
                var pulse = 0.6 + 0.4 * Math.Sin(t * 3.0);
                for (int g = 0; g < 3; g++)
                {
                    var gs = _TagStyle(GD.Fmt("glow%d", g));
                    gs.BgColor = new Color(glow, glow.a * pulse * (0.28 - 0.08 * g));
                    DrawStyleBox(gs, plate.Grow(2.0 + 2.0 * g));
                }
            }
            DrawStyleBox(_TagStyle(TAG_RIM.Has(rarity) ? rarity : "plain"), plate);
            if (rarity == "legendary")
            {
                foreach (var sx in new double[] { plate.position.x, plate.End.x })
                    _Sparkle(new Vector2(sx, plate.position.y + 1.0), 5.0, new Color(1.0, 0.95, 0.6, 0.65 + 0.35 * Math.Sin(t * 5.0 + sx)));
            }
            var x = plate.position.x + 6.0;
            var y = plate.position.y + 13.0;
            Color col = TAG_COL.Get(rarity, Color.WHITE).As<Color>();
            foreach (var part in parts)
            {
                string s = part[0].AsString();
                bool is_title = (bool)part[1];
                var sw = _bold.GetStringSize(s, HorizontalAlignment.Left, -1, TAG_PX).x;
                if (is_title && rarity == "legendary")
                {
                    // letter by letter, so a light band can sweep across the gold
                    var cx = x;
                    for (int i = 0; i < s.Length; i++)
                    {
                        var ch = s.Substr(i, 1);
                        DrawCharOutline(_bold, new Vector2(cx, y), ch, TAG_PX, 4, new Color(0, 0, 0, 0.75));
                        cx += _bold.GetCharSize(ch.UnicodeAt(0), TAG_PX).x;
                    }
                    cx = x;
                    for (int i = 0; i < s.Length; i++)
                    {
                        var ch = s.Substr(i, 1);
                        var band = GD.Fposmod((cx - x) / GD.Maxf(1.0, sw) - t * 0.6, 1.6);
                        var k = GD.Clampf(1.0 - Math.Abs(band - 0.3) / 0.2, 0.0, 1.0);
                        DrawChar(_bold, new Vector2(cx, y), ch, TAG_PX, col.Lerp(new Color("#fff8dc"), k));
                        cx += _bold.GetCharSize(ch.UnicodeAt(0), TAG_PX).x;
                    }
                }
                else
                {
                    DrawStringOutline(_bold, new Vector2(x, y), s, HorizontalAlignment.Left, -1, TAG_PX, 4, new Color(0, 0, 0, 0.75));
                    DrawString(_bold, new Vector2(x, y), s, HorizontalAlignment.Left, -1, TAG_PX, is_title ? col : side_col);
                }
                x += sw;
            }
        }

        public void _Sparkle(Vector2 c, double s, Color col)
        {
            DrawColoredPolygon(new List<Vector2> { c + new Vector2(0, -s), c + new Vector2(s * 0.3, -s * 0.3), c + new Vector2(s, 0), c + new Vector2(s * 0.3, s * 0.3),
                c + new Vector2(0, s), c + new Vector2(-s * 0.3, s * 0.3), c + new Vector2(-s, 0), c + new Vector2(-s * 0.3, -s * 0.3) }, col);
        }

        public void _DrawNumbers()
        {
            // Damage numbers: projected from 3D and drawn on the HUD canvas (no Label3D mesh rebuilds).
            if (numbers_source == null || project == null)
                return;
            double now = numbers_clock();
            foreach (var n in numbers_source())
            {
                var u = GD.Clampf((now - (double)n["at"]) / 0.8, 0.0, 1.0);
                if (on_screen != null && !on_screen(n["pos"].V3))
                    continue;
                Vector2 p = project(n["pos"].V3);
                if (p.y < 150.0)
                    continue;   // keep clear of the scoreboard and status lines
                var c = (bool)n["mine"] ? new Color("#ff6b5a") : new Color("#fff1c2");
                if ((bool)n.D.Get("gold", false))
                    c = new Color("#ffd65a");                       // 0.31.157 5V5: gold you earned (_text draws it white: 0.31.195)
                c.a = (float)(1.0 - u * u);
                _Text(p + new Vector2(0, -34.0 * u), GD.Str(n["text"]), 18, c, _bold);
            }
        }

        public void _DrawGateBars()
        {
            if (gate_bars_source == null || project == null)
                return;
            foreach (var b in gate_bars_source())
            {
                if (on_screen != null && !on_screen(b["pos"].V3))
                    continue;
                Vector2 p = project(b["pos"].V3);
                if (p.y < 170.0)
                    continue;
                var r = new Rect2(p - new Vector2(30, 4), new Vector2(60, 7));
                DrawRect(r.Grow(1.5), new Color(0, 0, 0, 0.7));
                DrawRect(new Rect2(r.position, new Vector2(r.size.x * (double)b["fill"], r.size.y)), b["color"].As<Color>());
            }
        }

        public string _KingStatus(Unit me)
        {
            // 0.31.156 5V5: the Kings are the hearts
            if (sim.moba.KingThreat(me.team) != null && sim.moba.KingOpen(me.team))
                return "OUR KING IS UNDER ATTACK!";
            if (sim.moba.KingOpen(1 - me.team))
                return "Their King is open -- defeat him!";
            return "Defeat their King -- he's guarded until a lane's three towers fall";
        }

        public void _DrawKingMarker(Unit me)
        {
            // 0.31.156: point to the King to defeat, theirs, when he is off-screen
            if (project == null || on_screen == null)
                return;
            Vector2 goal = sim.moba.KingPos(1 - me.team);
            var world = new Vector3(goal.x, 1.0, goal.y);
            if (on_screen(world))
                return;
            Vector2 p = project(world);
            var center = Size * 0.5;
            var dir = (p - center).Normalized();
            var edge = center + dir * GD.Minf(Size.x * 0.42, Size.y * 0.36);
            Color col = VisualTheme.GOLD;
            var tip = edge + dir * 16;
            var side = new Vector2(-dir.y, dir.x) * 11;
            DrawColoredPolygon(new List<Vector2> { tip, edge - dir * 6 + side, edge - dir * 6 - side }, col);
            _Text(edge - dir * 22 + new Vector2(0, 5), "KING", 11, col, _bold);
        }

        // 0.31.220 (Kevin's 0.31.219 log: the stick and the buttons 3.8-5 ms a frame on his phone, drawn again every frame at
        // his 15-30 fps): what a button shows is worked out each frame (_button_state) and drawn again only when that changes
        // (_button_key: its label, state, the recharge's sweep in 60 steps, the countdown's text, the ult's pulse at 15 a
        // second...) -- each button on its own canvas item under btn_layer, so a recharging Q redraws alone.
        public GDict _ButtonState(GDict b, Unit me)
        {
            Vector2 c = b["c"].V2;
            double r = (double)b["r"];
            var label = "";
            var col = new Color("#2c3136");
            var rim = new Color("#b8904e");
            var cd = 0.0;
            var cd_max = 1.0;
            var ready = true;
            var badge = "";                                  // (a small mark drawn over the button: the ult's rank, ward charges)
            Texture2D icon = null;                       // 0.31.171: Q, W, E and R show their painted icon (assets/ui/abilities)
            var locked = false;
            var pulse = -1.0;                                // (the ult's glow when it's ready)
            var recall = -1.0;                               // (HOME's ring while it channels: the share done)
            switch (GD.Str(b["id"]))
            {
                case "attack":
                    label = "ATTACK";
                    col = new Color("#9a6414");
                    rim = new Color("#fff1bf");
                    break;
                case "block":
                    label = "BLOCK";
                    col = new Color("#2c4a6e");
                    rim = new Color("#bcd8ff");
                    icon = AbilityIcon(GD.Str(me.hid ?? ""), "w");    // (the Crusader's W: his shield)
                    break;
                case "w":
                case "e":
                    {
                        // 0.31.167 5V5: W and E -- locked until their level (LV 2 / LV 3), then their name and recharge
                        var bid = GD.Str(b["id"]);
                        KitSpec k = Kits.Kit(GD.Str(me.hid ?? ""), bid);
                        bool unl = sim.moba.kits.Unlocked(me, bid);
                        label = unl ? (k != null ? GD.Str(k.shortName ?? k.name ?? "—") : "—") : _LockLabel(me, bid);
                        col = bid == "w" ? new Color("#1f4a33") : new Color("#4a2a1a");
                        rim = bid == "w" ? new Color("#9ff0b8") : new Color("#ffc08a");
                        cd = V.ToDouble(me.Get("cd_" + bid));
                        cd_max = GD.Maxf(0.1, (k != null ? k.N("cd", 1.0) : 1.0) * sim.moba.RankCd(me, bid));
                        ready = unl && cd <= 0.0 && sim.Alive(me);
                        badge = bid.ToUpperInvariant();
                        icon = AbilityIcon(GD.Str(me.hid ?? ""), bid);
                        locked = !unl;
                        break;
                    }
                case "ability":
                    {
                        var ab = GD.Str(sim.AbilityOf(me));
                        label = ab != "" ? ab.ToUpperInvariant() : "—";
                        badge = "Q";
                        col = new Color("#35226a");
                        rim = new Color("#d6b8ff");
                        cd = me.cd_ability;
                        cd_max = GD.Maxf(0.1, (double)GDict.Of("hammer", Sim.HAMMER_CD, "resurrect", Sim.RESURRECT_CD, "vanish", Sim.VANISH_CD, "pierce", Sim.PIERCE_CD,
                            "meteor", Sim.METEOR_CD).Get(ab, Sim.CLASSES[me.cls].ab_cd));
                        if (me.kq != null)
                        {
                            // 0.31.168: a new hero's Q is a kit spell -- its own name and recharge
                            KitSpec kq = Kits.Kit(GD.Str(me.hid ?? ""), "q");
                            label = kq != null ? GD.Str(kq.shortName ?? kq.name ?? label) : label;
                            cd_max = GD.Maxf(0.1, kq != null ? kq.N("cd", cd_max) : cd_max);
                        }
                        cd_max *= sim.moba.RankCd(me, "q");
                        ready = ab != "" && cd <= 0.0 && sim.moba.Rank(me, "q") > 0;
                        icon = AbilityIcon(GD.Str(me.hid ?? ""), "q");
                        locked = sim.moba.Rank(me, "q") <= 0;               // 0.31.217: not learnt yet
                        if (locked)
                            label = _LockLabel(me, "q");
                        break;
                    }
                case "ult":
                    {
                        // 0.31.157 5V5: the ultimate -- locked until level 6 (LV 6), its name once it's yours, a glow when it's ready
                        UltDef info = sim.moba.UltInfo(me);
                        bool unlocked = sim.moba.UltRank(me) > 0;
                        label = unlocked ? (info != null ? GD.Str(info.shortName ?? info.name ?? "ULT") : "ULT") : _LockLabel(me, "r");
                        col = new Color("#7a3208");
                        rim = new Color("#ffd65a");
                        cd = me.ult_cd;
                        cd_max = GD.Maxf(1.0, sim.moba.UltMaxCd(me));
                        ready = unlocked && cd <= 0.0;
                        if (ready)
                            pulse = 0.5 + 0.5 * Math.Sin(Math.Floor(_time * 15.0) / 15.0 * 5.0);
                        badge = unlocked && sim.moba.UltRank(me) >= 2 ? "R II" : "R";
                        icon = AbilityIcon(GD.Str(me.hid ?? ""), "r");
                        locked = !unlocked;
                        break;
                    }
                case "ward":
                    {
                        // 0.31.158 5V5: a ward at your feet -- its charges in the corner, the next one filling in round the rim
                        var ch = me.ward_ch;
                        label = "WARD";
                        col = new Color("#16485a");
                        rim = new Color("#8fe3ff");
                        ready = ch >= 1.0 && sim.Alive(me);
                        if (ch < (double)MobaVision.WARD_CHARGES)
                        {
                            cd = 1.0 - (ch - Math.Floor(ch));
                            cd_max = 1.0;
                        }
                        badge = GD.Str(GD.Int(ch));
                        break;
                    }
                case "dodge":
                    label = "DODGE";
                    cd = me.cd_dodge;
                    cd_max = 2.2;
                    ready = cd <= 0.0;
                    break;
                case "recall":
                    // 0.31.181: home to the fountain -- the castle on it; while it channels, its ring fills
                    label = "HOME";
                    col = new Color("#2a2456");
                    rim = new Color("#b9a8ff");
                    icon = HudIcon("castle");
                    ready = sim.Alive(me) && !sim.Recalling(me);
                    if (sim.Recalling(me))
                    {
                        var left = GD.Maxf(0.0, me.recall_until - sim.time);
                        recall = GD.Clampf(1.0 - left / Sim.RECALL_TIME, 0.0, 1.0);
                    }
                    break;
            }
            bool pressed = _time - (double)_pressed_at.Get(b["id"], -10.0) < 0.12 || (b["id"] == "attack" && _attack_held);
            var frac = cd > 0.0 ? GD.Clampf(cd / cd_max, 0.0, 1.0) : 0.0;
            frac = Math.Ceiling(frac * 60.0) / 60.0;                     // (the sweep in 60 steps)
            var cd_text = "";
            if (icon != null && !locked && cd > 0.0 && GD.Str(b["id"]) != "ward")
                cd_text = cd >= 1.0 ? GD.Str(GD.Ceili(cd)) : GD.Fmt("%.1f", cd);
            var st = GDict.Of("id", GD.Str(b["id"]), "c", c, "r", r, "label", label, "col", col, "rim", rim, "cd", cd, "frac", frac, "cd_text", cd_text,
                "ready", ready, "badge", badge, "icon", Var.Of(icon), "locked", locked, "pressed", pressed, "pulse", pulse,
                "recall", recall >= 0.0 ? Math.Floor(recall * 60.0) / 60.0 : -1.0, "slot", "", "mx", 0, "rk", 0, "tag", "");
            var slot = GD.Str(SLOT_OF.Get(GD.Str(b["id"]), ""));
            if (slot != "" && sim.moba != null)
            {
                st["slot"] = slot;
                st["mx"] = Moba.SKILL_MAX.TryGetValue(slot, out var mx) ? mx : 0;
                st["rk"] = sim.moba.Rank(me, slot);
                st["tag"] = Kits.Tag(GD.Str(me.hid ?? ""), slot, slot == "q" ? GD.Str(sim.AbilityOf(me)) : "");
            }
            return st;
        }

        public GArray _ButtonKey(GDict st)
        {
            // (the icon by its instance id in the .gd: the facade's resources have none -- the texture itself, compared by
            // identity, is the same test)
            return GArray.Of(st["c"], st["r"], st["label"], st["col"], st["rim"], st["frac"], (double)st["cd"] > 0.0, st["cd_text"], st["ready"], st["badge"],
                st["icon"], st["locked"], st["pressed"], st["pulse"], st["recall"], st["mx"], st["rk"], st["tag"]);
        }

        public void _DrawButton(GDict st)
        {
            string id = st["id"].AsString();
            Vector2 c = st["c"].V2;
            double r = (double)st["r"];
            string label = st["label"].AsString();
            Color col = st["col"].As<Color>();
            Color rim = st["rim"].As<Color>();
            double cd = (double)st["cd"];
            double frac = (double)st["frac"];
            bool ready = (bool)st["ready"];
            string badge = st["badge"].AsString();
            Texture2D icon = st["icon"].As<Texture2D>();
            bool locked = (bool)st["locked"];
            bool pressed = (bool)st["pressed"];
            if ((double)st["pulse"] >= 0.0)
            {
                double pulse = (double)st["pulse"];
                _ci.DrawArc(c, r + 5.0 + 3.0 * pulse, 0, GD.TAU, 48, new Color(1.0, 0.84, 0.35, 0.35 + 0.4 * pulse), 4.0, true);
            }
            if ((double)st["recall"] >= 0.0)
                _ci.DrawArc(c, r + 4.0, -GD.PI * 0.5, -GD.PI * 0.5 + GD.TAU * (double)st["recall"], 40, new Color("#d8ccff"), 4.0, true);
            var body = pressed ? col.Lightened(0.15) : col;
            if (!ready)
                body = body.Darkened(0.45);
            _ci.DrawCircle(c + new Vector2(0, 4), r, new Color(0, 0, 0, 0.45));
            _ci.DrawCircle(c, r, body);
            if (icon != null)
            {
                // 0.31.171: the icon in the circle -- dimmed while it recharges or is locked, the time left over it
                var lit = ready ? new Color(1, 1, 1) : (locked ? new Color(0.3, 0.3, 0.34) : new Color(0.5, 0.5, 0.54));
                _IconCircle(c, r - 1.5, icon, lit);
                if (pressed)
                    _ci.DrawCircle(c, r - 1.5, new Color(1, 1, 1, 0.18));
                if (cd > 0.0 && !locked && frac > 0.01)
                    _Pie(c, r - 1.5, frac, new Color(0, 0, 0, 0.45));
            }
            _ci.DrawArc(c, r, 0, GD.TAU, 48, ready ? rim : rim.Darkened(0.5), 3.0, true);
            if (cd > 0.0)
                _ci.DrawArc(c, r - 6, -GD.PI * 0.5, -GD.PI * 0.5 + GD.TAU * frac, 40, new Color(1, 1, 1, 0.55), 5.0, true);
            if (icon == null)
                _Text(c + new Vector2(0, 6), label, r > 40 ? 15 : (r > 30 ? 12 : 11), ready ? new Color("#fffaf0") : new Color("#8a939a"), _bold);
            else if (locked)
                _Text(c + new Vector2(0, 6), label, r > 30 ? 12 : 11, new Color("#c9d0d6"), _bold);          // LV 2 / LV 3 / LV 6
            else if (GD.Str(st["cd_text"]) != "")
                _Text(c + new Vector2(0, 7), GD.Str(st["cd_text"]), r > 33 ? 18 : 16, new Color("#fffaf0"), _bold);
            if (badge != "")
            {
                if (id == "ward")
                {
                    var bc = c + new Vector2(r * 0.72, -r * 0.72);
                    _ci.DrawCircle(bc, 9.0, new Color("#0d2a33"));
                    _ci.DrawArc(bc, 9.0, 0, GD.TAU, 24, rim, 1.5, true);
                    _Text(bc + new Vector2(0, 4), badge, 11, new Color("#dff7ff"), _bold);
                }
                else if (id == "ability" || id == "w" || id == "e")
                    _Text(c + new Vector2(0, -r + 13), badge, 10, ready ? new Color(1, 1, 1, 0.75) : new Color(1, 1, 1, 0.35), _bold);
                else
                    _Text(c + new Vector2(0, -r + 12), badge, 11, new Color("#ffe9a6"), _bold);
            }
            if (GD.Str(st["slot"]) != "")
            {
                // 0.31.217 (Honor of Kings): the skill's ranks as pips along its foot, and what it's for under it
                int mx = (int)st["mx"];
                int rk = (int)st["rk"];
                for (int i = 0; i < mx; i++)
                {
                    var pc = c + new Vector2(((double)i - (double)(mx - 1) * 0.5) * 9.0, r - 5.0);
                    _ci.DrawCircle(pc, 3.4, new Color(0, 0, 0, 0.6));
                    _ci.DrawCircle(pc, 2.6, i < rk ? new Color("#ffd65a") : new Color(1, 1, 1, 0.18));
                }
                _Text(c + new Vector2(0, r + 13.0), GD.Str(st["tag"]), 9, rk > 0 ? new Color(1, 1, 1, 0.82) : new Color(1, 1, 1, 0.45), _bold);
            }
        }


        public string _LockLabel(Unit me, string slot)
        {
            // 0.31.217: a skill not learnt -- "LEARN" when a point can go on it now; the level it needs ("LV 4") until you're
            // there; there but no point left: "NEXT LV" (the next level's point)
            if (sim.moba.CanLearn(me, slot))
                return "LEARN";
            var need = sim.moba.RankNeed(slot, 1);
            return me.level < need ? GD.Fmt("LV %d", need) : "NEXT LV";
        }

        // 0.31.171: the ability icons (tools/build_ability_icons.py): <hero>_<q|w|e|r>.png, loaded once (a missing one: the
        // button's name, as before)
        public const string ICON_DIR = "res://assets/ui/abilities/";
        public static GDict _icons = new GDict();

        public static Texture2D AbilityIcon(string hid, string slot)
        {
            var key = GD.Fmt("%s_%s", hid, slot);
            if (!_icons.Has(key))
            {
                var p = ICON_DIR + key + ".png";
                _icons[key] = hid != "" && ResourceLoader.Exists(p) ? Var.Of(ResourceLoader.Load(p)) : Var.Nil;
            }
            return _icons[key].As<Texture2D>();
        }

        // 0.31.219: the unit circle's points made once (they were 40 sines and cosines a button a frame, the largest part of a
        // button's drawing): an icon or a recharge's pie is drawn from them, placed and sized by the canvas transform
        public static List<Vector2> _unit_ring = new List<Vector2>();
        public static List<Vector2> _unit_uvs = new List<Vector2>();
        public static List<Vector2> _pie_ring = new List<Vector2>();       // (41 points clockwise from the top: the pie's rim)

        public static void _RingsMade()
        {
            if (_unit_ring.Count != 0)
                return;
            for (int i = 0; i < 40; i++)
            {
                var d = Vector2.FromAngle(GD.TAU * (double)i / 40.0);
                _unit_ring.Add(d);
                _unit_uvs.Add(new Vector2(0.5, 0.5) + d * 0.5);
            }
            for (int i = 0; i < 41; i++)
                _pie_ring.Add(Vector2.FromAngle(-GD.PI * 0.5 + GD.TAU * (double)i / 40.0));
        }

        public void _IconCircle(Vector2 c, double r, Texture2D tex, Color tint)
        {
            _RingsMade();
            _ci.DrawSetTransform(c, 0.0, new Vector2(r, r));
            _ci.DrawPolygon(_unit_ring, new[] { tint }, _unit_uvs, tex);
            _ci.DrawSetTransform(Vector2.ZERO, 0.0, Vector2.ONE);
        }

        public void _Pie(Vector2 c, double r, double frac, Color color)
        {
            // the part still recharging, clockwise from the top: the rim's whole steps, then the exact end
            _RingsMade();
            var f = GD.Clampf(frac, 0.0, 1.0);
            var k = GD.Int(40.0 * f);
            var pts = new List<Vector2> { Vector2.ZERO };
            pts.AddRange(_pie_ring.GetRange(0, Math.Min(k + 1, _pie_ring.Count)));
            if ((double)k < 40.0 * f)
                pts.Add(Vector2.FromAngle(-GD.PI * 0.5 + GD.TAU * f));
            if (pts.Count < 3)
                return;
            _ci.DrawSetTransform(c, 0.0, new Vector2(r, r));
            _ci.DrawColoredPolygon(pts, color);
            _ci.DrawSetTransform(Vector2.ZERO, 0.0, Vector2.ONE);
        }
    }
}
