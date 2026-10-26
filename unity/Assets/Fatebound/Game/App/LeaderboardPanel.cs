// Ported from godot/scripts/app/leaderboard_panel.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Color = Fatebound.GUI.Col;
using UI = Fatebound.Game.Ui;
using UI2 = Fatebound.Game.Ui2;
using SocialUI = Fatebound.Game.SocialUi;
using LbFetch = Fatebound.Game.LbFetch;
using NetT = Fatebound.Game.SiegeNet;
using Eco = Fatebound.Game.Economy;

namespace Fatebound.Game
{
    // 0.31.119 (Kevin: "Do all" -- 4. leaderboards): the LEADERBOARD window from Home's RANKS medallion. The server keeps the
    // week's points from online matches (server/leaderboard.gd); this asks for them (lb_fetch.gd) and shows WEEKLY (the
    // top 50, your row pinned under them when you're further down) or FRIENDS (you and your friends), when the week ends,
    // last week's champions and how points are earned.
    public class LeaderboardPanel : Control
    {
        public static readonly GArray MEDAL = GArray.Of(new Color("#ffc23d"), new Color("#d8e2ea"), new Color("#e09056"));       // gold, silver, bronze
        public static readonly GDict TITLE_COL = GDict.Of("common", new Color("#cfd8e0"), "rare", new Color("#6cc4ff"), "epic", new Color("#d6a2ff"), "legendary", new Color("#ffc23d"));

        public SiegeApp app;
        public string tab = "week";                   // "week" / "friends"
        public GDict data = new GDict();              // the server's answer ({} until it comes; {"_fail": true} when it didn't)
        public VBoxContainer _list;
        public ScrollContainer _scroll;
        public HBoxContainer _tab_row;

        public void Open(SiegeApp a)
        {
            app = a;
            var w = SocialUI.Window(this, "LEADERBOARD", "trophy", () =>
            {
                app.Sfx("menuClose");
                app.CloseModal();
            }, 56.0 + (double)app.safe_top, 24.0);
            _tab_row = UI.Row(w["body"].As<Node>(), 8);
            _scroll = new ScrollContainer();
            _scroll.SizeFlagsVertical = Control.SIZE_EXPAND_FILL;
            _scroll.HorizontalScrollMode = ScrollContainer.SCROLL_MODE_DISABLED;
            _scroll.ScrollDeadzone = 1000000;                 // (drag-scrolled by the app, like the menus)
            w["body"].As<VBoxContainer>().AddChild(_scroll);
            SetMeta("drag_scroll", _scroll);
            _list = new VBoxContainer();
            _list.AddThemeConstantOverride("separation", 6);
            _list.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            _scroll.AddChild(_list);
            _Render();
            var acct = GD.Str(app.profile.d["account"].Get("id", ""));
            var key = GD.Str(app.profile.d["account"].Get("key", ""));
            if (acct == "" || key == "")
            {
                data = GDict.Of("_fail", true, "_why", "account");
                _Render();
                return;
            }
            LbFetch.Start(this, GD.Str(app.eco_url), acct, key, (GDict r) =>
            {
                data = !r.IsEmpty() ? r : GDict.Of("_fail", true);
                if (IsInsideTree())
                    _Render();
            });
        }

        public void _Render()
        {
            // the tabs: the open one gold, the other blue
            foreach (var c in _tab_row.GetChildren())
            {
                _tab_row.RemoveChild(c);
                c.QueueFree();
            }
            foreach (var t in GArray.Of(GArray.Of("week", "THIS WEEK"), GArray.Of("friends", "FRIENDS")))
            {
                var b = UI2.Button(_tab_row, GD.Str(t[1]), tab == GD.Str(t[0]) ? "gold" : "blue", () =>
                {
                    if (tab == GD.Str(t[0]))
                        return;
                    app.Sfx("tab");
                    tab = GD.Str(t[0]);
                    _Render();
                }, "lb_tab_" + GD.Str(t[0]), 15, 40.0, 12.0);
                b.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            }
            foreach (var c in _list.GetChildren())
            {
                _list.RemoveChild(c);
                c.QueueFree();
            }
            if (data.IsEmpty())
            {
                UI2.Center(UI2.Body(_list, "Loading the week's best...", 14, UI2.SOFT));
                return;
            }
            if ((bool)data.Get("_fail", false))
            {
                var why = GD.Str(data.Get("_why", "")) == "account" ? "Play an online match first -- your account is made then."
                    : "Couldn't reach the server. Try again in a moment.";
                UI2.Center(UI2.Body(_list, why, 14, UI2.SOFT));
                return;
            }
            // when the week ends
            var left = GD.Maxi(0, (int)data.Get("ends", 0) - (int)Time.GetUnixTimeFromSystem());
            var head = UI.Row(_list, 6);
            var hl = UI2.Text(head, GD.Fmt("WEEK OF %s", _Date(GD.Str(data.Get("week", "")))), 14, UI2.GOLD);
            hl.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            UI2.Body(head, GD.Fmt("ends in %s", _Left(left)), 12, UI2.SOFT, false);
            GArray rows = tab == "week" ? data.Get("top", new GArray()).A : data.Get("friends", new GArray()).A;
            if (rows.IsEmpty())
            {
                if (tab == "week")
                    UI2.Center(UI2.Body(_list, "Nobody's on the board yet this week -- win an online match and be first.", 13, UI2.SOFT));
                else
                    UI2.Center(UI2.Body(_list, "Play an online match to get on the board, and add friends to see how you compare.", 13, UI2.SOFT));
            }
            else
            {
                _Header(_list);
                foreach (var r in rows)
                    _Row(_list, r.D);
            }
            GDict me = data.Get("me", new GDict()).D;
            if (tab == "week" && !me.IsEmpty() && (int)me.Get("rank", 0) > rows.Size())
            {
                UI2.Center(UI2.Body(_list, "· · ·", 12, UI2.MUTED, false));
                _Row(_list, me);
            }
            else if (me.IsEmpty() && tab == "week" && !rows.IsEmpty())
                UI2.Center(UI2.Body(_list, "You're not on the board yet -- play an online match.", 12, UI2.SOFT));
            if (tab == "friends")
            {
                var fb = UI2.Button(_list, "FRIENDS", "blue", () =>
                {
                    app.Sfx("menuOpen");
                    app.OpenFriends();
                }, "lb_friends", 15, 42.0, 12.0);
                fb.SizeFlagsHorizontal = Control.SIZE_SHRINK_CENTER;
                var fm = fb.CustomMinimumSize;
                fm.x = 160;
                fb.CustomMinimumSize = fm;
            }
            if (tab == "week")
                _Prizes(_list);
            // last week's champions
            GArray last = data.Get("last", new GArray()).A;
            if (!last.IsEmpty())
            {
                var f = UI2.Frame(_list, "royal", 10, 14.0, "gold", GDict.Of("pattern_mix", 0.0));
                UI2.Center(UI2.Text(f, "LAST WEEK'S CHAMPIONS", 14, UI2.GOLD));
                for (int i = 0; i < last.Size(); i++)
                {
                    GDict c = last[i].D;
                    var lr = UI.Row(f, 6);
                    var ml = UI.Label(lr, GD.Fmt("%d", i + 1), 14, (Color)MEDAL[i], UI.HEAVY_FONT);
                    ml.AutowrapMode = TextServer.AUTOWRAP_OFF;
                    var mm = ml.CustomMinimumSize;
                    mm.x = 18;
                    ml.CustomMinimumSize = mm;
                    var nl = UI.Label(lr, NetT.TitleText(GD.Str(c.Get("name", "")), GD.Str(c.Get("title", ""))), 13, Color.WHITE, UI.HEAVY_FONT);
                    nl.AutowrapMode = TextServer.AUTOWRAP_OFF;
                    nl.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
                    nl.ClipText = true;
                    var pl = UI.Label(lr, GD.Fmt("%d pts", (int)c.Get("pts", 0)), 12, UI2.SOFT, UI.HEAVY_FONT);
                    pl.AutowrapMode = TextServer.AUTOWRAP_OFF;
                }
            }
            UI2.Center(UI2.Body(_list, "Points come from online matches: KO 20 · tower, gate and King damage ÷10 · a win +100. A new week starts every Monday (UTC).", 11, UI2.MUTED));
            UI2.Center(UI2.Body(_list, GD.Fmt("%d player%s on the board", (int)data.Get("players", 0), (int)data.Get("players", 0) == 1 ? "" : "s"), 11, UI2.MUTED, false));
        }

        public void _Header(Node parent)
        {
            var h = UI.Row(parent, 4);
            var a = UI.Label(h, "PLAYER", 10, UI2.MUTED, UI.HEAVY_FONT);
            a.AutowrapMode = TextServer.AUTOWRAP_OFF;
            a.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            foreach (var hh in GArray.Of(GArray.Of("WINS", 40), GArray.Of("TW", 28), GArray.Of("PTS", 56)))          // (0.31.170: towers; Siege's ♛ rescues until then)
            {
                var l = UI.Label(h, GD.Str(hh[0]), 10, UI2.MUTED, UI.HEAVY_FONT);
                l.AutowrapMode = TextServer.AUTOWRAP_OFF;
                var lm = l.CustomMinimumSize;
                lm.x = (float)(double)hh[1];
                l.CustomMinimumSize = lm;
                l.HorizontalAlignment = HorizontalAlignment.Right;
            }
        }

        public void _Row(Node parent, GDict r)
        {
            var mine = (bool)r.Get("you", false);
            var rank = (int)r.Get("rank", 0);
            var box = new PanelContainer();
            box.Name = "LbRow";
            box.SetMeta("rank", rank);
            box.SetMeta("you", mine);
            var st = new StyleBoxFlat();
            st.BgColor = mine ? new Color(UI2.GOLD, 0.2) : new Color(1, 1, 1, 0.05);
            st.SetCornerRadiusAll(10);
            st.ContentMarginLeft = 8;
            st.ContentMarginRight = 8;
            st.ContentMarginTop = 4;
            st.ContentMarginBottom = 4;
            if (mine)
            {
                st.BorderColor = UI2.GOLD;
                st.SetBorderWidthAll(1);
            }
            else if (rank >= 1 && rank <= 3)
            {
                st.BorderColor = new Color((Color)MEDAL[rank - 1], 0.6);
                st.SetBorderWidthAll(1);
            }
            box.AddThemeStyleboxOverride("panel", st);
            parent.AddChild(box);
            var h = new HBoxContainer();
            h.AddThemeConstantOverride("separation", 4);
            box.AddChild(h);
            var rk = UI.Label(h, GD.Str(rank), rank <= 3 ? 15 : 13, rank >= 1 && rank <= 3 ? (Color)MEDAL[rank - 1] : UI2.MUTED, UI.HEAVY_FONT);
            rk.AutowrapMode = TextServer.AUTOWRAP_OFF;
            var rm = rk.CustomMinimumSize;
            rm.x = 30;
            rk.CustomMinimumSize = rm;
            if (GD.Str(r.Get("cc", "")) != "")
                SocialUI.Crest(h, GD.Str(r["cc"]), 26.0);                 // 0.31.196: their clan's crest
            var col = new VBoxContainer();
            col.AddThemeConstantOverride("separation", -2);
            col.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            h.AddChild(col);
            var nm = GD.Str(r.Get("name", "Player"));
            if (GD.Str(r.Get("ct", "")) != "")
                nm = GD.Fmt("[%s] %s", GD.Str(r["ct"]), nm);                // 0.31.134: their clan's tag
            var nl = UI.Label(col, nm + (mine ? "  (you)" : ""), 14, mine ? UI2.GREEN : Color.WHITE, UI.HEAVY_FONT);
            nl.AutowrapMode = TextServer.AUTOWRAP_OFF;
            nl.ClipText = true;
            nl.TextOverrunBehavior = TextServer.OVERRUN_TRIM_ELLIPSIS;
            var tid = GD.Str(r.Get("title", ""));
            if (tid != "" && NetT.TITLES.Has(tid))
            {
                var tl = UI.Label(col, GD.Str(NetT.TITLES[tid][0]), 10, (Color)TITLE_COL.Get(NetT.TitleRarity(tid), Color.WHITE), UI.HEAVY_FONT);
                tl.AutowrapMode = TextServer.AUTOWRAP_OFF;
            }
            if (r.Has("q") && !(bool)r["q"])
            {
                // 0.31.120: not in the running for a prize yet
                var ql = UI.Label(col, GD.Fmt("%d more match%s for a prize", Eco.LB_MIN_MATCHES - (int)r.Get("m", 0), Eco.LB_MIN_MATCHES - (int)r.Get("m", 0) == 1 ? "" : "es"), 10, UI2.MUTED, UI.HEAVY_FONT);
                ql.AutowrapMode = TextServer.AUTOWRAP_OFF;
            }
            foreach (var v in GArray.Of(GArray.Of(GD.Str((int)r.Get("w", 0)), 40), GArray.Of(GD.Str((int)r.Get("tw", 0)), 28), GArray.Of(GD.Str((int)r.Get("pts", 0)), 56)))
            {
                var l = UI.Label(h, GD.Str(v[0]), 14, Color.WHITE, UI.HEAVY_FONT);
                l.AutowrapMode = TextServer.AUTOWRAP_OFF;
                var lm = l.CustomMinimumSize;
                lm.x = (float)(double)v[1];
                l.CustomMinimumSize = lm;
                l.HorizontalAlignment = HorizontalAlignment.Right;
            }
            // 0.31.120 (Kevin: player profile card): tap a player's row for their card (add them as a friend from it)
            var pid = GD.Str(r.Get("pid", ""));
            if (pid != "" && !mine && app.social != null && app.social.Online())
            {
                var tap = new Button();
                tap.Flat = true;
                tap.FocusMode = Control.FOCUS_NONE;
                foreach (var st_name in new[] { "normal", "hover", "pressed", "focus", "hover_pressed" })
                    tap.AddThemeStyleboxOverride(st_name, new StyleBoxEmpty());
                tap.SetMeta("action_key", GD.Fmt("lb_card_%d", rank));
                var card = GDict.Of("pid", pid, "n", GD.Str(r.Get("name", "Player")), "tt", GD.Str(r.Get("title", "")), "ct", GD.Str(r.Get("ct", "")), "cc", GD.Str(r.Get("cc", "")));
                tap.Pressed += () => SocialUI.NameCard(app, this, card);
                box.AddChild(tap);
            }
        }

        public void _Prizes(Node parent)
        {
            // 0.31.120: what the week's best win (paid by the server when the week ends)
            var f = UI2.Frame(parent, "ember", 10, 14.0, "orange", GDict.Of("pattern_mix", 0.0));
            f.Name = "PrizeCard";
            UI2.Center(UI2.Text(f, "THIS WEEK'S PRIZES", 15, new Color("#ffd27a")));
            foreach (var t in Eco.LB_PRIZES)
            {
                var r = UI.Row(f, 6);
                var place = (int)t["from"] == (int)t["to"] ? GD.Fmt("#%d", (int)t["from"]) : GD.Fmt("#%d-%d", (int)t["from"], (int)t["to"]);
                var pl = UI.Label(r, place, 13, (int)t["from"] == 1 ? (Color)MEDAL[0] : Color.WHITE, UI.HEAVY_FONT);
                pl.AutowrapMode = TextServer.AUTOWRAP_OFF;
                var pm = pl.CustomMinimumSize;
                pm.x = 64;
                pl.CustomMinimumSize = pm;
                var bits = GArray.Of(GD.Fmt("%d gems", (int)t["gems"]));
                if (GD.Str(t.Get("chest", "")) != "")
                    bits.Append(GD.Str(Eco.CHESTS[GD.Str(t["chest"])]["name"]));
                if (GD.Str(t.Get("title", "")) != "")
                    bits.Append(GD.Fmt("title \"%s\"", GD.Str(NetT.TITLES[GD.Str(t["title"])][0])));
                var bl = UI.Label(r, GStr.Join(" + ", bits), 12, Color.WHITE, UI.HEAVY_FONT);
                bl.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            }
            UI2.Center(UI2.Body(f, GD.Fmt("Play %d or more online matches in the week to be in the running.", Eco.LB_MIN_MATCHES), 11, new Color(1, 1, 1, 0.8)));
        }

        public static string _Date(string iso)
        {
            // "2026-10-12" -> "OCT 12"
            var p = iso.Split("-");
            if (p.Length != 3)
                return iso;
            var months = new[] { "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" };
            return GD.Fmt("%s %d", months[GD.Clampi(GD.Int(p[1]) - 1, 0, 11)], GD.Int(p[2]));
        }

        public static string _Left(int s)
        {
            if (s >= 86400)
                return GD.Fmt("%dd %dh", s / 86400, (s % 86400) / 3600);
            if (s >= 3600)
                return GD.Fmt("%dh %dm", s / 3600, (s % 3600) / 60);
            return GD.Fmt("%dm", GD.Maxi(1, s / 60));
        }
    }
}
