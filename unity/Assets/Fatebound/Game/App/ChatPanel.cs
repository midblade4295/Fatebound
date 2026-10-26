// Ported from godot/scripts/app/chat_panel.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Color = Fatebound.GUI.Col;
using UI = Fatebound.Game.Ui;
using UI2 = Fatebound.Game.Ui2;
using SocialUI = Fatebound.Game.SocialUi;
using Eco = Fatebound.Game.Economy;

namespace Fatebound.Game
{
    // 0.31.111 (Kevin: "Build a global chat and players can click a name and have option to add friend"): the chat window.
    // GLOBAL (everyone online) and PARTY tabs, the lines (tap a name for its card: add friend, invite, block, report),
    // and a text field with SEND. The sheet rises above the phone's keyboard while it's open. Lines arrive live from
    // scripts/meta/social.gd; the tab on screen counts as read.
    // 0.31.196: the crest before a clan member's name; in CLAN, a shard request's line has GIVE (if you hold that hero's
    // shard; TAKE BACK on your own) and an LFG call's line JOIN (CANCEL on your own) while they're open.
    public class ChatPanel : Control
    {
        public SiegeApp app;
        public Social social;
        public string ch = "global";
        public MarginContainer _margin;
        public VBoxContainer _list;
        public ScrollContainer _scroll;
        public LineEdit _input;
        public GDict _tabs = new GDict();
        public Label _status;
        public int _shown = 0;                       // lines of `ch` on screen
        public GDict _shown_first = new GDict();     // the first line on screen (history replaced -> redraw)
        public GDict _shown_last = new GDict();      // 0.31.140: the last line on screen (lines merged in before it -> redraw)
        public string _shown_ch = "";                // the channel on screen
        public double _bottom = 24.0;
        public bool _stick = true;                   // follow new lines (the list is at its bottom)
        public GArray _live = new GArray();          // 0.31.196: [button, line] -- a request's GIVE, a call's JOIN (kept up to date)
        public string back = "";                     // 0.31.197: "clan" -- opened from the clan camp: closing goes back to it

        public void Open(SiegeApp a, string start_ch = "global")
        {
            app = a;
            social = a.social;
            ch = (start_ch == "party" && social.InParty()) || (start_ch == "clan" && social.InClan()) ? start_ch : (social.show_global ? "global" : "party");
            _Build();
            social.Changed += _OnChanged;
            social.viewing = ch;
            social.MarkRead(ch);
            _Render();
        }

        protected override void _ExitTree()
        {
            if (social != null && social.viewing == ch)
                social.viewing = "";
        }

        public void _Build()
        {
            var w = SocialUI.Window(this, "CHAT", "chat", () =>
            {
                app.Sfx("menuClose");
                if (back == "clan" && app.social != null && app.social.InClan())
                    app.OpenClan();
                else
                    app.CloseModal();
            }, 56.0 + (double)app.safe_top, _bottom);
            _margin = w["margin"].As<MarginContainer>();
            VBoxContainer body = w["body"].As<VBoxContainer>();
            var tr = UI.Row(body, 8);
            foreach (var t in GArray.Of(GArray.Of("global", "GLOBAL"), GArray.Of("party", "PARTY"), GArray.Of("clan", "CLAN")))       // (0.31.134: CLAN)
            {
                string id = GD.Str(t[0]);
                var b = UI2.Button(tr, GD.Str(t[1]), "gold", () => _Switch(id), "chat_tab_" + id, 15, 38.0, 12.0);
                UI.Grow(b);
                _tabs[id] = b;
            }
            _status = UI2.Body(body, "", 12, UI2.MUTED);
            _status.HorizontalAlignment = HorizontalAlignment.Center;
            _scroll = new ScrollContainer();
            _scroll.SizeFlagsVertical = Control.SIZE_EXPAND_FILL;
            _scroll.HorizontalScrollMode = ScrollContainer.SCROLL_MODE_DISABLED;
            _scroll.ScrollDeadzone = 1000000;                 // (drag-scrolled by the app's _input, like the menus)
            body.AddChild(_scroll);
            SetMeta("drag_scroll", _scroll);
            _scroll.GetVScrollBar().ValueChanged += (double _v) =>
            {
                var bar = _scroll.GetVScrollBar();
                _stick = bar.Value >= bar.MaxValue - bar.Page - 24.0;
            };
            _list = new VBoxContainer();
            _list.AddThemeConstantOverride("separation", 6);
            _list.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            _scroll.AddChild(_list);
            var ir = UI.Row(body, 8);
            _input = SocialUI.Field(ir, "Say something...", 120);
            _input.TextSubmitted += (string _t) => _Send();
            var sb = UI2.Button(ir, "SEND", "orange", () => _Send(), "chat_send", 16, 46.0, 14.0);
            var sm = sb.CustomMinimumSize;
            sm.x = 86;
            sb.CustomMinimumSize = sm;
        }

        public void _Switch(string id)
        {
            if (id == ch)
                return;
            if (id == "party" && !social.InParty())
            {
                app.Sfx("error");
                app.Toast("Invite a friend to a party first -- tap their name, or open Friends", UI.MUTED);
                return;
            }
            if (id == "clan" && !social.InClan())
            {
                app.Sfx("error");
                app.Toast("Join a clan first -- FRIENDS on Home, then CLAN", UI.MUTED);
                return;
            }
            if (id == "global" && !social.show_global)
            {
                app.Sfx("error");
                app.Toast("Global chat is off -- turn it on in Settings", UI.MUTED);
                return;
            }
            app.Sfx("tab");
            ch = id;
            social.viewing = ch;
            social.MarkRead(ch);
            _shown = 0;
            _Render();
        }

        public void _Send()
        {
            var t = _input.Text.StripEdges();
            if (t == "")
                return;
            if (social.Say(ch, t))
            {
                app.Sfx("tap");
                _input.Text = "";
                _stick = true;
            }
            else
            {
                app.Sfx("error");
                app.Toast("Not connected to chat right now", UI.RED);
            }
        }

        public void _OnChanged(string what)
        {
            if ((what == "party" && ch == "party" && !social.InParty()) || (what == "clan" && ch == "clan" && !social.InClan()))
            {
                ch = "global";
                social.viewing = ch;
                _shown = 0;
            }
            if (GArray.Of("chat", "party", "state", "me", "clan").Has(what))
            {
                if (social.viewing == ch)
                    social.unread[ch] = 0;
                _Render();
                _LiveUpdate();
            }
        }

        public void _Render()
        {
            // tabs: the one open is gold; PARTY greys out without a party; unread counts on the other
            foreach (var idv in _tabs)
            {
                var id = GD.Str(idv);
                Button b = _tabs[idv].As<Button>();
                bool on = id == ch;
                var n = (int)social.unread.Get(id, 0);
                string label = GD.Str(GDict.Of("global", "GLOBAL", "party", "PARTY", "clan", "CLAN")[id]);
                if (id == "party" && social.InParty())
                    label = GD.Fmt("PARTY %d/%d", social.PartySize(), (int)social.party.Get("max", 4));
                b.Text = label + (n > 0 && !on ? GD.Fmt("  (%d)", n) : "");
                b.Modulate = on ? Color.WHITE : new Color(0.72, 0.76, 0.86, 0.9);
                if (id == "clan")
                {
                    var m = b.Modulate;
                    m.a = social.InClan() ? 1.0f : 0.45f;
                    b.Modulate = m;
                }
                if (id == "party")
                {
                    b.Visible = true;
                    var m = b.Modulate;
                    m.a = social.InParty() ? 1.0f : 0.45f;
                    b.Modulate = m;
                }
                if (id == "global")
                {
                    var m = b.Modulate;
                    m.a = social.show_global ? 1.0f : 0.45f;
                    b.Modulate = m;
                }
            }
            switch (GD.Str(social.state))
            {
                case "online": _status.Text = ""; break;
                case "connecting": _status.Text = "Connecting to chat..."; break;
                case "old": _status.Text = "Chat arrives with the next server update."; break;
                default: _status.Text = !social.HasAccount() ? "Chat connects once you're online with the game's server." : "Not connected -- trying again shortly..."; break;
            }
            _status.Visible = _status.Text != "";
            GArray lines = social.lines.Get(ch, new GArray()).A;
            GDict first = !lines.IsEmpty() ? lines[0].D : new GDict();
            GDict at_end = _shown > 0 && _shown <= lines.Size() ? lines[_shown - 1].D : new GDict();
            if (ch != _shown_ch || _shown > lines.Size() || (Var)first != (Var)_shown_first || (Var)at_end != (Var)_shown_last)
            {
                foreach (var c in _list.GetChildren())
                    c.QueueFree();
                _live = new GArray();
                _shown = 0;
                _shown_first = first;
                _shown_ch = ch;
            }
            if (lines.IsEmpty() && _list.GetChildCount() == 0)
            {
                var e = UI2.Body(_list, GD.Str(GDict.Of("global", "Nobody's said anything yet -- say hi!", "party", "Talk to your party here.", "clan", "Talk to your clan here.")[ch]), 13, UI2.MUTED);
                e.HorizontalAlignment = HorizontalAlignment.Center;
                e.SetMeta("empty", true);
            }
            for (int i = _shown; i < lines.Size(); i++)
            {
                foreach (var c in _list.GetChildren())
                {
                    if (c.HasMeta("empty"))
                        c.QueueFree();
                }
                _Row(lines[i].D);
            }
            _shown = lines.Size();
            _shown_last = _shown > 0 ? lines[_shown - 1].D : new GDict();
            if (_stick)
                CallDeferred(_ToBottom);
        }

        public async void _ToBottom()
        {
            try
            {
                await Await.ProcessFrame();
                if (GD.IsInstanceValid(_scroll))
                    _scroll.ScrollVertical = (int)_scroll.GetVScrollBar().MaxValue;
            }
            catch (Exception e) { GD.PushError(e.ToString()); }
        }

        public void _Row(GDict l)
        {
            if ((bool)l.Get("sys", false))
            {
                var s = UI2.Body(_list, GD.Fmt("— %s —", GD.Str(l.Get("x", ""))), 12, new Color("#c8b88a"));
                s.HorizontalAlignment = HorizontalAlignment.Center;
                return;
            }
            bool mine = GD.Str(l.Get("pid", "")) == GD.Str(social.me.Get("pid", ""));
            var pc = new PanelContainer();
            var st = new StyleBoxFlat();
            st.BgColor = mine ? new Color(0.36, 0.22, 0.04, 0.5) : new Color(0.0, 0.02, 0.08, 0.42);
            st.BorderColor = mine ? new Color(0.97, 0.8, 0.33, 0.35) : new Color(0.5, 0.65, 0.95, 0.18);
            st.SetBorderWidthAll(1);
            st.SetCornerRadiusAll(12);
            st.ContentMarginLeft = 10;
            st.ContentMarginRight = 10;
            st.ContentMarginTop = 4;
            st.ContentMarginBottom = 6;
            pc.AddThemeStyleboxOverride("panel", st);
            _list.AddChild(pc);
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", 0);
            pc.AddChild(v);
            var head = UI.Row(v, 6);
            var nb = new Button();
            nb.Flat = true;
            nb.FocusMode = Control.FOCUS_NONE;
            nb.Text = GD.Str(l.Get("n", "Player"));
            if (GD.Str(l.Get("ct", "")) != "")
                nb.Text = GD.Fmt("[%s] %s", GD.Str(l["ct"]), nb.Text);          // 0.31.134: their clan's tag
            nb.AddThemeFontOverride("font", UI.HEAVY_FONT);
            nb.AddThemeFontSizeOverride("font_size", 14);
            Color col = mine ? SocialUI.NAME_ME : SocialUI.NAME_OTHER;
            foreach (var k in new[] { "font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color" })
                nb.AddThemeColorOverride(k, col);
            nb.AddThemeColorOverride("font_outline_color", new Color(0, 0, 0, 0.7));
            nb.AddThemeConstantOverride("outline_size", 3);
            foreach (var st_name in new[] { "normal", "hover", "pressed", "focus", "hover_pressed" })
            {
                var e = new StyleBoxEmpty();
                e.ContentMarginLeft = 0;
                e.ContentMarginRight = 4;
                nb.AddThemeStyleboxOverride(st_name, e);
            }
            nb.SetMeta("action_key", "chat_name");
            var card = GDict.Of("pid", GD.Str(l.Get("pid", "")), "n", GD.Str(l.Get("n", "")), "tt", GD.Str(l.Get("tt", "")), "ct", GD.Str(l.Get("ct", "")));
            nb.Pressed += () => SocialUI.NameCard(app, this, card);
            if (GD.Str(l.Get("cc", "")) != "")
                SocialUI.Crest(head, GD.Str(l["cc"]), 20.0);          // 0.31.196: their clan's crest
            head.AddChild(nb);
            SocialUI.TitleLabel(head, GD.Str(l.Get("tt", "")), 11);
            var sp = new Control();
            sp.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            sp.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            head.AddChild(sp);
            var tl = UI.Label(head, SocialUI.Ago((int)Time.GetUnixTimeFromSystem() - (int)l.Get("at", 0)), 10, UI2.MUTED, UI.HEAVY_FONT);
            tl.AutowrapMode = TextServer.AUTOWRAP_OFF;
            tl.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            var x = UI.Label(v, GD.Str(l.Get("x", "")), 15, Color.WHITE, UI.BODY_FONT);
            x.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
            x.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            if (ch == "clan" && (l.Has("ask") || l.Has("lfg")))
            {
                // 0.31.196: a shard request (GIVE) or an LFG call (JOIN), live while it's open
                var b = UI2.Button(v, "", "green", () => _Act(l), l.Has("ask") ? "chat_give" : "chat_lfg_join", 13, 34.0, 10.0);
                b.SizeFlagsHorizontal = Control.SIZE_SHRINK_END;
                var bm = b.CustomMinimumSize;
                bm.x = 150;
                b.CustomMinimumSize = bm;
                _live.Append(GArray.Of(b, l));
                _LiveOne(b, l);
            }
        }

        public void _LiveUpdate()
        {
            foreach (var e in _live)
            {
                if (GD.IsInstanceValid(e[0]))
                    _LiveOne(e[0].As<Button>(), e[1].D);
            }
        }

        public void _LiveOne(Button b, GDict l)
        {
            var pid = GD.Str(l.Get("pid", ""));
            bool mine = pid == GD.Str(social.me.Get("pid", ""));
            var text = "";
            var on = false;
            var col = "green";
            if (l.Has("ask"))
            {
                var h = GD.Str(l["ask"]);
                if (social.AskOpen(pid, h))
                {
                    if (mine)
                    {
                        text = "TAKE BACK";
                        col = "ghost";
                        on = true;
                    }
                    else if (app.profile.GiftableShards(h) > 0)
                    {
                        text = GD.Fmt("GIVE  +%d GOLD", Eco.ShardMeltGold(h, app.profile.Now()));
                        on = true;
                    }
                    else
                    {
                        text = "NO SHARD TO GIVE";
                        col = "grey";
                    }
                }
            }
            else
            {
                GDict call = social.LfgCall(GD.Str(l["lfg"]));
                if (!call.IsEmpty() && GD.Absi((int)call.Get("at", 0) - (int)l.Get("at", 0)) < 5)
                {
                    if (mine)
                    {
                        text = "CANCEL CALL";
                        col = "ghost";
                        on = true;
                    }
                    else if (social.InMyParty(pid))
                    {
                        text = "IN YOUR PARTY";
                        col = "grey";
                    }
                    else
                    {
                        text = GD.Fmt("JOIN  %d/%d", (int)call.Get("size", 1), (int)call.Get("max", 5));
                        on = true;
                    }
                }
            }
            b.Visible = text != "";
            if (text != "" && (b.Text != text || GD.Str(Var.Of(b.GetMeta("col", ""))) != col))
            {
                b.Text = text;
                b.SetMeta("col", col);
                UI2.DimButton(b, !on);
            }
            b.SetMeta("on", on);
        }

        public void _Act(GDict l)
        {
            Button b = null;
            foreach (var e in _live)
            {
                if (e[1] == (Var)l && GD.IsInstanceValid(e[0]))
                    b = e[0].As<Button>();
            }
            if (b == null || !(bool)Var.Of(b.GetMeta("on", false)))
            {
                app.Sfx("error");
                return;
            }
            var pid = GD.Str(l.Get("pid", ""));
            bool mine = pid == GD.Str(social.me.Get("pid", ""));
            var ok = false;
            if (l.Has("ask"))
                ok = mine ? social.ClanUnask() : social.ClanGive(pid);
            else
                ok = mine ? social.Lfg(false) : social.LfgJoin(GD.Str(l["lfg"]));
            if (ok)
                app.Sfx("confirm");
            else
            {
                app.Sfx("error");
                app.Toast("Not connected to the server right now", UI.RED);
            }
        }

        protected override void _Process(double _delta)
        {
            // keep the field above the keyboard (its height is in window pixels: turned into this canvas's)
            var kh = (double)DisplayServer.VirtualKeyboardGetHeight();
            var want = 24.0;
            if (kh > 0.0)
            {
                var win = (double)DisplayServer.WindowGetSize().y;
                var scale = GetViewportRect().size.y / GD.Maxf(1.0, win);
                want = kh * scale + 8.0;
            }
            if (GD.Absf(want - _bottom) > 1.0)
            {
                _bottom = want;
                _margin.AddThemeConstantOverride("margin_bottom", (int)_bottom);
                if (_stick)
                    CallDeferred(_ToBottom);
            }
        }
    }
}
