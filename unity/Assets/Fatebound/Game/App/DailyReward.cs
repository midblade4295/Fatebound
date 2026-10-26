// Ported from godot/scripts/app/daily_reward.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Color = Fatebound.GUI.Col;
using UI = Fatebound.Game.Ui;
using UI2 = Fatebound.Game.Ui2;
using Eco = Fatebound.Game.Economy;

namespace Fatebound.Game
{
    // 0.31.119 (Kevin: "Do all" -- 6. a daily login reward): the DAILY REWARD card. Seven days (Eco.LOGIN_REWARDS), one claim
    // each UTC day, round and round -- a missed day doesn't reset it. It opens by itself on Home the first time each day a
    // claim is waiting (siege_app.offer_daily), and from ORDERS. CLAIM is the profile's claim_login op: the phone shows it at
    // once and the server replays it with its own clock (eco_sync), so a changed phone clock can't claim twice.
    public class DailyReward : Control
    {
        public SiegeApp app;
        public VBoxContainer _card;

        public void Open(SiegeApp a)
        {
            app = a;
            SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            var dim = new ColorRect();
            dim.Color = new Color(0.01, 0.02, 0.06, 0.78);
            dim.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            AddChild(dim);
            var center = new CenterContainer();
            center.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            AddChild(center);
            var holder = new MarginContainer();
            holder.CustomMinimumSize = new Vector2(GD.Minf(392.0, app.Size.x - 20.0), 0);
            center.AddChild(holder);
            _card = UI2.Frame(holder, "royal", 14, 22.0, "gold");
            _card.AddThemeConstantOverride("separation", 10);
            _Render();
        }

        public void Refresh()
        {
            _Render();
        }

        public static GArray RewardText(GDict rw)
        {
            // -> [[icon path, "+150"], ...] for a day's tile
            var @out = new GArray();
            if (rw.Has("gold"))
                @out.Append(GArray.Of("res://assets/ui/currency/coin.png", GD.Fmt("%d", (int)rw["gold"])));
            if (rw.Has("chest"))
                @out.Append(GArray.Of(UI2.V2 + GD.Fmt("chests/%s_icon.png", GD.Str(GDict.Of("wooden", "wood").Get(GD.Str(rw["chest"]), GD.Str(rw["chest"])))), GD.Str(Eco.CHESTS[GD.Str(rw["chest"])]["name"])));
            if (rw.Has("gems"))
                @out.Append(GArray.Of("res://assets/ui/currency/gems.png", GD.Fmt("%d", (int)rw["gems"])));
            return @out;
        }

        public void _Render()
        {
            foreach (var c in _card.GetChildren())
            {
                _card.RemoveChild(c);
                c.QueueFree();
            }
            var p = app.profile;
            bool ready = p.LoginReady();
            int nxt = p.LoginNext();                       // the day the next claim gives (0-6)
            var today = ready ? nxt : (int)GD.Posmod(nxt - 1, 7);   // the day that's today's (claimed or not)
            var head = UI.Row(_card, 8);
            UI2.Img(head, UI2.V2 + "chests/gold_icon.png", 44.0).SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            var tl = UI2.Text(head, "DAILY REWARD", 26, UI2.GOLD);
            tl.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            tl.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            var x = UI2.Button(head, "✕", "ghost", () =>
            {
                app.Sfx("menuClose");
                app.CloseModal();
            }, "daily_close", 18, 40.0, 12.0);
            var xm = x.CustomMinimumSize;
            xm.x = 44;
            x.CustomMinimumSize = xm;
            UI2.Center(UI2.Body(_card, "A reward every day you play -- the best on day 7.", 12, UI2.SOFT));
            // the seven days: four on top, three under (day 7 wide)
            foreach (var row_days in new[] { new[] { 0, 1, 2, 3 }, new[] { 4, 5, 6 } })
            {
                var r = new HBoxContainer();
                r.AddThemeConstantOverride("separation", 6);
                r.Alignment = BoxContainer.ALIGNMENT_CENTER;
                _card.AddChild(r);
                foreach (var i in row_days)
                    _Tile(r, i, i < today || (i == today && !ready), i == today && ready, i == 6);
            }
            if (ready)
            {
                var b = UI2.Button(_card, GD.Fmt("CLAIM DAY %d", nxt + 1), "green", () => _Claim(), "daily_claim", 20, 54.0, 16.0);
                b.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
                UI2.Sweep(b);
            }
            else
            {
                var left = 86400 - (int)GD.Posmod((int)p.Now(), 86400);
                UI2.Center(UI2.Text(_card, "CLAIMED TODAY", 18, UI2.GREEN));
                UI2.Center(UI2.Body(_card, GD.Fmt("Day %d in %s", nxt + 1, _Left(left)), 13, UI2.SOFT, false));
                var ok = UI2.Button(_card, "OK", "blue", () =>
                {
                    app.Sfx("menuClose");
                    app.CloseModal();
                }, "daily_ok", 18, 46.0, 14.0);
                ok.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            }
            UI2.Center(UI2.Body(_card, "Missed a day? No problem -- you pick up where you left off.", 11, UI2.MUTED));
        }

        public void _Tile(Node parent, int i, bool claimed, bool is_today, bool wide)
        {
            var t = new PanelContainer();
            t.Name = GD.Fmt("DayTile%d", i + 1);
            t.SetMeta("claimed", claimed);
            t.SetMeta("today", is_today);
            t.CustomMinimumSize = new Vector2(wide ? 176 : 84, 104);
            var st = new StyleBoxFlat();
            st.BgColor = is_today ? new Color("#2a6b3a") : (claimed ? new Color(0.02, 0.04, 0.1, 0.75) : new Color(0.08, 0.12, 0.28, 0.95));
            st.BorderColor = is_today ? UI2.GOLD : (claimed ? new Color(1, 1, 1, 0.15) : new Color("#4d6bd8"));
            st.SetBorderWidthAll(is_today ? 3 : 2);
            st.SetCornerRadiusAll(12);
            st.ContentMarginTop = 4;
            st.ContentMarginBottom = 4;
            t.AddThemeStyleboxOverride("panel", st);
            parent.AddChild(t);
            var v = new VBoxContainer();
            v.Alignment = BoxContainer.ALIGNMENT_CENTER;
            v.AddThemeConstantOverride("separation", 1);
            t.AddChild(v);
            UI2.Center(UI2.Text(v, GD.Fmt("DAY %d", i + 1), 12, is_today ? UI2.CYAN : Color.WHITE));
            var icons = new HBoxContainer();
            icons.Alignment = BoxContainer.ALIGNMENT_CENTER;
            icons.AddThemeConstantOverride("separation", 2);
            v.AddChild(icons);
            var amounts = new GArray();
            foreach (var it in RewardText(Eco.LOGIN_REWARDS[i].D))
            {
                var im = UI2.Img(icons, GD.Str(it[0]), wide ? 44.0 : 40.0);
                if (is_today)
                    UI2.Bob(im, 3.0, 0.9);
                amounts.Append(GD.Str(it[1]));
            }
            UI2.Center(UI2.Body(v, GStr.Join(" + ", amounts), 11, Color.WHITE, false));
            if (claimed)
            {
                t.Modulate = new Color(1, 1, 1, 0.55);
                var ck = new Label();
                ck.Text = "✔";
                ck.AddThemeFontSizeOverride("font_size", 30);
                ck.AddThemeColorOverride("font_color", UI2.GREEN);
                ck.AddThemeColorOverride("font_outline_color", new Color(0, 0, 0, 0.9));
                ck.AddThemeConstantOverride("outline_size", 6);
                ck.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                ck.SetAnchorsAndOffsetsPreset(Control.PRESET_CENTER);
                t.AddChild(ck);
            }
            if (is_today)
                UI2.Pulse(t, 0.03, 0.9);
        }

        public void _Claim()
        {
            GDict r = app.profile.ClaimLogin();
            if (!(bool)r.Get("ok", false))
            {
                app.Toast("Already claimed today", UI.MUTED);
                _Render();
                return;
            }
            app.Sfx("confirm");
            GArray chests = r.Get("chests", new GArray()).A;
            foreach (var ch in chests)
            {
                if ((bool)ch.Get("queued", false))
                    app.Toast(GD.Fmt("Your chest slots are full -- the %s waits for a free one", GD.Str(Eco.CHESTS[GD.Str(ch["kind"])]["name"])), UI.GOLD);
                else if ((bool)ch.Get("full", false))
                    app.Toast(GD.Fmt("Chest slots full -- turned into %d gold", (int)ch["gold"]), UI.GOLD);
            }
            if (app.analytics != null)        // (app.get("analytics") != null)
                app.analytics.LogEv("daily_reward", GDict.Of("day", (int)r["day"]));
            app.Rebuild();                                        // (the counters fly up; Home's chests show a new one)
            _Render();
        }

        public static string _Left(int s)
        {
            if (s >= 3600)
                return GD.Fmt("%dh %dm", s / 3600, (s % 3600) / 60);
            return GD.Fmt("%dm", GD.Maxi(1, s / 60));
        }
    }
}
