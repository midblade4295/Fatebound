// Ported from godot/scripts/app/social_ui.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Color = Fatebound.GUI.Col;
using UI = Fatebound.Game.Ui;
using UI2 = Fatebound.Game.Ui2;
using Net = Fatebound.Game.SiegeNet;
using Eco = Fatebound.Game.Economy;
using CREST = Fatebound.Game.Crest;

namespace Fatebound.Game
{
    // 0.31.111 (Kevin: "Build a global chat and players can click a name and have option to add friend to a friends list.
    // They can then group up and form a party"): the pieces the chat and friends screens share -- the window frame, a
    // player's status dot and line, and the card that opens when a name is tapped (add friend / invite / remove / block /
    // report). The connection and the state are in scripts/meta/social.gd.
    public static class SocialUi
    {
        public static readonly GDict ST_COL = GDict.Of("online", new Color("#5fdc86"), "match", new Color("#ffb13d"), "offline", new Color("#6b778a"));
        public static readonly GDict RARITY_COL = GDict.Of("common", new Color("#cfd8e0"), "rare", new Color("#6cc4ff"), "epic", new Color("#d6a2ff"), "legendary", new Color("#ffc23d"));
        public static readonly Color NAME_ME = new Color("#8cf0a8");              // 0.31.196: green, as everywhere your name is (0.31.195: no yellow text)
        public static readonly Color NAME_OTHER = new Color("#9fd8ff");
        public static readonly GArray REPORTS = GArray.Of(GArray.Of("language", "Offensive language"), GArray.Of("spam", "Spam"), GArray.Of("cheating", "Cheating"), GArray.Of("name", "Offensive name"), GArray.Of("other", "Something else"));
        // 0.31.134: the three houses a clan belongs to
        public static readonly GArray HOUSES = GArray.Of("lions", "stags", "ravens");
        public static readonly GDict HOUSE_NAME = GDict.Of("lions", "Lions", "stags", "Stags", "ravens", "Ravens");
        public static readonly GDict HOUSE_COL = GDict.Of("lions", new Color("#ffc23d"), "stags", new Color("#6be07c"), "ravens", new Color("#c99bff"));
        public static readonly GDict HOUSE_RIM = GDict.Of("lions", "orange", "stags", "green", "ravens", "purple");
        public static readonly GDict HOUSE_BTN = GDict.Of("lions", "gold", "stags", "green", "ravens", "purple");

        public static string HouseName(string h)
        {
            return GD.Str(HOUSE_NAME.Get(h, "?"));
        }

        public static Color HouseColor(string h)
        {
            return (Color)HOUSE_COL.Get(h, UI2.MUTED);
        }

        public static string HouseRim(string h)
        {
            return GD.Str(HOUSE_RIM.Get(h, "gold"));
        }

        public static string HouseButton(string h)
        {
            return GD.Str(HOUSE_BTN.Get(h, "grey"));
        }

        public static Panel HouseChip(Node parent, string h, double px = 14.0)
        {
            // a small round chip in the house's colour
            var d = new Panel();
            var sb = new StyleBoxFlat();
            sb.BgColor = HouseColor(h);
            sb.BorderColor = HouseColor(h).Darkened(0.55);
            sb.SetBorderWidthAll(2);
            sb.SetCornerRadiusAll((int)px);
            d.AddThemeStyleboxOverride("panel", sb);
            d.CustomMinimumSize = new Vector2(px, px);
            d.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            d.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            parent.AddChild(d);
            return d;
        }

        public static CREST Crest(Node parent, string code, double h = 20.0, string frame = "")
        {
            // 0.31.196: a clan's crest ("e.f.c"), h px tall (scripts/app/crest.gd); an empty one for no crest
            var c = new CREST();
            c.SetCrest(code, frame);
            c.CustomMinimumSize = code != "" ? new Vector2(Math.Round(h / CREST.ASPECT, MidpointRounding.AwayFromZero), h) : Vector2.ZERO;
            c.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            c.Visible = code != "";
            parent.AddChild(c);
            return c;
        }

        public static void SocialTabs(Node parent, SiegeApp app, string on)
        {
            // FRIENDS | CLAN at the top of both windows (a badge count on the other one)
            var tr = UI.Row(parent, 8);
            var social = app.social;
            foreach (var t in GArray.Of(GArray.Of("friends", "FRIENDS"), GArray.Of("clan", "CLAN")))
            {
                string id = GD.Str(t[0]);
                var n = 0;
                if (social != null && social.Online())
                    n = id == "friends" ? (social.rin.Size() + social.invites.Size()) : (social.clan_inv.Size() + (social.IsClanOfficer() ? social.ClanRequests() : 0));
                var b = UI2.Button(tr, GD.Str(t[1]) + (n > 0 && id != on ? GD.Fmt("  (%d)", n) : ""), id == on ? "gold" : "blue", () =>
                {
                    if (id != on)
                    {
                        app.Sfx("tab");
                        app.OpenSocial(id);
                    }
                }, "social_tab_" + id, 15, 38.0, 12.0);
                UI.Grow(b);
            }
        }

        public static string Ago(int secs)
        {
            if (secs < 90)
                return "just now";
            if (secs < 3600)
                return GD.Fmt("%dm ago", secs / 60);
            if (secs < 86400)
                return GD.Fmt("%dh ago", secs / 3600);
            return GD.Fmt("%dd ago", secs / 86400);
        }

        public static string StatusText(GDict c)
        {
            switch (GD.Str(c.Get("st", "offline")))
            {
                case "online": return "Online";
                case "match": return (int)c.Get("jn", 0) == 1 ? "In the lobby" : "In a match";   // 0.31.209: (a lobby can be joined)
            }
            var seen = (int)c.Get("seen", 0);
            return seen > 0 ? "Last seen " + Ago((int)Time.GetUnixTimeFromSystem() - seen) : "Offline";
        }

        public static Panel Dot(Node parent, string st, double px = 10.0)
        {
            var d = new Panel();
            var s = new StyleBoxFlat();
            s.BgColor = (Color)ST_COL.Get(st, ST_COL["offline"]);
            s.SetCornerRadiusAll((int)px);
            if (st != "offline")
            {
                s.ShadowColor = new Color(s.BgColor, 0.6);
                s.ShadowSize = 3;
            }
            d.AddThemeStyleboxOverride("panel", s);
            d.CustomMinimumSize = new Vector2(px, px);
            d.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            d.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            parent.AddChild(d);
            return d;
        }

        public static Label TitleLabel(Node parent, string tt, int size = 11)
        {
            GArray t = Net.TITLES.Get(tt, new GArray()).A;
            if (t.IsEmpty())
                return null;
            var l = UI.Label(parent, GD.Str(t[0]), size, (Color)RARITY_COL.Get(GD.Str(t[2]), RARITY_COL["common"]), UI.HEAVY_FONT);
            l.AutowrapMode = TextServer.AUTOWRAP_OFF;
            l.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            return l;
        }

        public static LineEdit Field(Node parent, string placeholder, int max_len)
        {
            // a text field in the game's look: dark, gold-edged, round
            var e = new LineEdit();
            e.PlaceholderText = placeholder;
            e.MaxLength = max_len;
            e.CustomMinimumSize = new Vector2(0, 46);
            e.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            e.AddThemeFontOverride("font", UI.HEAVY_FONT);
            e.AddThemeFontSizeOverride("font_size", 16);
            e.AddThemeColorOverride("font_color", Color.WHITE);
            e.AddThemeColorOverride("font_placeholder_color", new Color(0.75, 0.8, 0.92, 0.55));
            e.AddThemeColorOverride("caret_color", UI2.GOLD);
            e.AddThemeColorOverride("selection_color", new Color(1.0, 0.84, 0.35, 0.35));
            foreach (var st_name in new[] { "normal", "focus", "read_only" })
            {
                var s = new StyleBoxFlat();
                s.BgColor = new Color(0.02, 0.04, 0.1, 0.92);
                s.BorderColor = st_name == "focus" ? new Color("#f7cd55") : new Color("#8a6a2a");
                s.SetBorderWidthAll(2);
                s.SetCornerRadiusAll(14);
                s.ContentMarginLeft = 14;
                s.ContentMarginRight = 14;
                s.ContentMarginTop = 6;
                s.ContentMarginBottom = 6;
                e.AddThemeStyleboxOverride(st_name, s);
            }
            parent.AddChild(e);
            return e;
        }

        public static GDict Window(Control panel, string title, string icon, Action on_close, double top = 56.0, double bottom = 24.0)
        {
            // the frame both screens open in: a dimmed backdrop and a gold-rimmed sheet with a title row and a close button.
            // -> {"margin", "body" (the sheet's VBox), "head" (the title row)}
            panel.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            var dim = new ColorRect();
            dim.Color = new Color(0.01, 0.02, 0.06, 0.78);
            dim.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            panel.AddChild(dim);
            var margin = new MarginContainer();
            margin.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            foreach (var side in new[] { "left", "right" })
                margin.AddThemeConstantOverride("margin_" + side, 10);
            margin.AddThemeConstantOverride("margin_top", (int)top);
            margin.AddThemeConstantOverride("margin_bottom", (int)bottom);
            panel.AddChild(margin);
            var body = UI2.Frame(margin, "night", 12, 20.0, "gold");
            body.AddThemeConstantOverride("separation", 8);
            var head = UI.Row(body, 8);
            var ic = UI2.Icon(head, icon, 38.0);
            ic.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            var tl = UI2.Text(head, title, 26, UI2.GOLD);
            tl.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            var sp = new Control();
            sp.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            head.AddChild(sp);
            var x = UI2.Button(head, "✕", "ghost", on_close, "social_close", 18, 40.0, 12.0);
            var xm = x.CustomMinimumSize;
            xm.x = 44;
            x.CustomMinimumSize = xm;
            x.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            return GDict.Of("margin", margin, "body", body, "head", head);
        }

        // ---------------- the card behind a name ----------------
        public static void NameCard(SiegeApp app, Control host, GDict c)
        {
            var social = app.social;
            var pid = GD.Str(c.Get("pid", ""));
            if (social == null || pid == "" || social.Relation(pid) == "me")
                return;
            app.Sfx("menuOpen");
            foreach (var o in host.GetChildren())
            {
                if (o.HasMeta("name_card"))
                    o.QueueFree();
            }
            var ov = new Control();
            ov.SetMeta("name_card", true);
            ov.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            host.AddChild(ov);
            var dim = new ColorRect();
            dim.Color = new Color(0, 0, 0, 0.55);
            dim.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            dim.GuiInput += (InputEvent ev) =>
            {
                if ((ev is InputEventMouseButton || ev is InputEventScreenTouch) && !ev.IsPressed())
                {
                    app.Sfx("menuClose");
                    ov.QueueFree();
                }
            };
            ov.AddChild(dim);
            var cc = new CenterContainer();
            cc.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            cc.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            ov.AddChild(cc);
            var v = UI2.Frame(cc, "royal", 14, 20.0, "gold");
            (v.GetParent() as Control).CustomMinimumSize = new Vector2(GD.Minf(330.0, host.Size.x - 40.0), 0);
            v.AddThemeConstantOverride("separation", 8);
            _FillCard(app, ov, v, c);
            // 0.31.120 (Kevin: player profile card): its numbers come from the server; the card fills in when they arrive
            social.AskProfile(pid);
            Action<string> on_ch = (string what) =>
            {
                if (what == "prof" && GD.IsInstanceValid(ov) && GD.IsInstanceValid(v) && !v.HasMeta("reporting") && ov.IsInsideTree())
                    _FillCard(app, ov, v, c);
            };
            social.Changed += on_ch;
            ov.TreeExiting += () =>
            {
                // (if social.changed.is_connected(on_ch): disconnect -- removing a handler that isn't there does nothing)
                social.Changed -= on_ch;
            };
        }

        public static void _Close(SiegeApp app, Control ov)
        {
            if (GD.IsInstanceValid(ov))
                ov.QueueFree();
        }

        public static void _FillCard(SiegeApp app, Control ov, VBoxContainer v, GDict c0)
        {
            foreach (var ch in v.GetChildren())
                ch.QueueFree();
            var social = app.social;
            var pid = GD.Str(c0.Get("pid", ""));
            GDict c = social.CardOf(pid);
            if (c.IsEmpty())
                c = c0;
            string rel = social.Relation(pid);
            GDict pr0 = social.ProfileOf(pid);
            var ct = GD.Str(c.Get("ct", pr0.Get("ct", "")));      // 0.31.134: their clan's tag
            var nl = UI2.Text(v, GD.Str(c.Get("n", "Player")), 24, Color.WHITE);
            nl.HorizontalAlignment = HorizontalAlignment.Center;
            if (ct != "")
            {
                var crow = new HBoxContainer();                  // 0.31.196: the crest beside the tag
                crow.Alignment = BoxContainer.ALIGNMENT_CENTER;
                crow.AddThemeConstantOverride("separation", 6);
                v.AddChild(crow);
                Crest(crow, GD.Str(c.Get("cc", pr0.Get("cc", ""))), 22.0);
                UI2.Text(crow, GD.Fmt("[%s]", ct), 15, UI2.GOLD);
            }
            var tr = new HBoxContainer();
            tr.Alignment = BoxContainer.ALIGNMENT_CENTER;
            tr.AddThemeConstantOverride("separation", 8);
            v.AddChild(tr);
            TitleLabel(tr, GD.Str(c.Get("tt", "")), 13);
            var code = UI.Label(tr, "#" + pid.ToUpperInvariant(), 12, UI2.MUTED, UI.HEAVY_FONT);
            code.AutowrapMode = TextServer.AUTOWRAP_OFF;
            if (c.Has("st") && rel == "friend")
            {
                var sr = new HBoxContainer();
                sr.Alignment = BoxContainer.ALIGNMENT_CENTER;
                sr.AddThemeConstantOverride("separation", 6);
                v.AddChild(sr);
                Dot(sr, GD.Str(c["st"]));
                UI.Label(sr, StatusText(c), 12, UI2.SOFT, UI.HEAVY_FONT).AutowrapMode = TextServer.AUTOWRAP_OFF;
            }
            _StatsBlock(v, social.ProfileOf(pid), social.Online());
            Action<bool> act = (bool ok) =>
            {
                if (!ok)
                {
                    app.Sfx("error");
                    app.Toast("Not connected to the server right now", UI.RED);
                }
                else
                    _Close(app, ov);
            };
            switch (rel)
            {
                case "none":
                    UI2.Button(v, "ADD FRIEND", "green", () =>
                    {
                        app.Sfx("confirm");
                        act(social.Add(pid));
                    }, "card_add", 17, 46.0);
                    break;
                case "sent":
                {
                    var sb = UI2.Button(v, "FRIEND REQUEST SENT", "grey", () => { }, "card_sent", 15, 42.0);
                    UI2.DimButton(sb, true);
                    UI2.Button(v, "TAKE IT BACK", "ghost", () =>
                    {
                        app.Sfx("tap");
                        act(social.Unfriend(pid));
                    }, "card_unsend", 14, 38.0);
                    break;
                }
                case "asked":
                {
                    var r = UI.Row(v, 8);
                    UI.Grow(UI2.Button(r, "ACCEPT", "green", () =>
                    {
                        app.Sfx("confirm");
                        act(social.Add(pid));
                    }, "card_accept", 17, 46.0));
                    UI.Grow(UI2.Button(r, "DECLINE", "ghost", () =>
                    {
                        app.Sfx("tap");
                        act(social.Decline(pid));
                    }, "card_decline", 15, 46.0));
                    break;
                }
                case "friend":
                {
                    var st = GD.Str(c.Get("st", "offline"));
                    bool full = social.InParty() && social.PartySize() + social.party.Get("pending", new GArray()).Size() >= social.ClanPartyMax();
                    bool can = st == "online" && !social.InMyParty(pid) && !full;
                    var why = "INVITE TO PARTY";
                    if (social.InMyParty(pid))
                        why = "IN YOUR PARTY";
                    else if (st == "match")
                        why = "IN A MATCH";
                    else if (st == "offline")
                        why = "OFFLINE";
                    else if (full)
                        why = "PARTY FULL";
                    if (social.CanJoin(c) && !social.InMyParty(pid) && true /* app.has_method("join_friend") */)   // 0.31.209: its countdown only
                    {
                        // 0.31.120 (Kevin: "make so it's a join match option")
                        UI2.Button(v, "JOIN THEIR MATCH", "green", () =>
                        {
                            _Close(app, ov);
                            app.JoinFriend(pid);
                        }, "card_join", 17, 46.0);
                    }
                    else
                    {
                        var ib = UI2.Button(v, why, can ? "orange" : "grey", () =>
                        {
                            if (can)
                            {
                                app.Sfx("confirm");
                                act(social.Invite(pid));
                            }
                        }, "card_invite", 17, 46.0);
                        UI2.DimButton(ib, !can);
                    }
                    Button rb = null;
                    rb = UI2.Button(v, "REMOVE FRIEND", "ghost", () => { }, "card_remove", 14, 38.0);
                    rb.Pressed += () =>
                    {
                        if (rb.HasMeta("armed"))
                        {
                            app.Sfx("menuClose");
                            act(social.Unfriend(pid));
                        }
                        else
                        {
                            rb.SetMeta("armed", true);
                            rb.Text = "TAP AGAIN TO REMOVE";
                            app.Sfx("tap");
                        }
                    };
                    break;
                }
                case "blocked":
                    UI2.Button(v, "UNBLOCK", "blue", () =>
                    {
                        app.Sfx("tap");
                        act(social.Unblock(pid));
                    }, "card_unblock", 16, 44.0);
                    break;
            }
            if (GArray.Of("none", "sent", "asked").Has(rel) && social.has_lfg && social.InMyClan(pid))
            {
                // 0.31.196: a clanmate who isn't a friend can be invited to the party too
                var cst = GD.Str(c.Get("st", "offline"));
                bool cfull = social.InParty() && social.PartySize() + social.party.Get("pending", new GArray()).Size() >= social.ClanPartyMax();
                bool ccan = cst == "online" && !social.InMyParty(pid) && !cfull;
                var cwhy = "INVITE TO PARTY";
                if (social.InMyParty(pid))
                    cwhy = "IN YOUR PARTY";
                else if (cst == "match")
                    cwhy = "IN A MATCH";
                else if (cst == "offline")
                    cwhy = "OFFLINE";
                else if (cfull)
                    cwhy = "PARTY FULL";
                var cib = UI2.Button(v, cwhy, ccan ? "orange" : "grey", () =>
                {
                    if (ccan)
                    {
                        app.Sfx("confirm");
                        act(social.Invite(pid));
                    }
                }, "card_invite", 17, 46.0);
                UI2.DimButton(cib, !ccan);
            }
            if (rel != "blocked" && social.has_clans && social.IsClanOfficer() && ct == "" && !social.InMyClan(pid))
            {
                // 0.31.134: officers invite players who aren't in a clan
                UI2.Button(v, "INVITE TO CLAN", "purple", () =>
                {
                    app.Sfx("confirm");
                    act(social.ClanInvite(pid));
                }, "card_clan_invite", 15, 42.0);
            }
            var r2 = UI.Row(v, 8);
            if (rel != "blocked")
            {
                Button bb = null;
                bb = UI2.Button(r2, "BLOCK", "red", () => { }, "card_block", 14, 40.0);
                UI.Grow(bb);
                bb.Pressed += () =>
                {
                    if (bb.HasMeta("armed"))
                    {
                        app.Sfx("menuClose");
                        act(social.Block(pid));
                    }
                    else
                    {
                        bb.SetMeta("armed", true);
                        bb.Text = "SURE? TAP AGAIN";
                        app.Sfx("tap");
                    }
                };
            }
            UI.Grow(UI2.Button(r2, "REPORT", "grey", () =>
            {
                app.Sfx("tap");
                _ReportMenu(app, ov, v, c);
            }, "card_report", 14, 40.0));
            UI2.Button(v, "CLOSE", "ghost", () =>
            {
                app.Sfx("menuClose");
                _Close(app, ov);
            }, "card_close", 14, 36.0);
        }

        public static void _ReportMenu(SiegeApp app, Control ov, VBoxContainer v, GDict c)
        {
            foreach (var ch in v.GetChildren())
                ch.QueueFree();
            v.SetMeta("reporting", true);
            var pid = GD.Str(c.Get("pid", ""));
            UI2.Center(UI2.Text(v, GD.Fmt("REPORT %s", GD.Str(c.Get("n", "Player")).ToUpperInvariant()), 20, Color.WHITE));
            UI2.Center(UI2.Body(v, "What's wrong? The report goes to the developer with their last messages.", 12, UI2.SOFT));
            foreach (var r in REPORTS)
            {
                string key = GD.Str(r[0]);
                UI2.Button(v, GD.Str(r[1]).ToUpperInvariant(), "blue", () =>
                {
                    if (app.social.Report(pid, key))
                    {
                        app.Sfx("confirm");
                        _Close(app, ov);
                    }
                    else
                    {
                        app.Sfx("error");
                        app.Toast("Not connected to the server right now", UI.RED);
                    }
                }, "report_" + key, 15, 40.0);
            }
            UI2.Button(v, "BACK", "ghost", () =>
            {
                app.Sfx("menuClose");
                _FillCard(app, ov, v, c);
            }, "report_back", 14, 36.0);
        }

        // ---------------- the profile card's numbers (0.31.120) ----------------
        public static string SinceText(int t)
        {
            if (t <= 0)
                return "";
            var dt = Time.GetDatetimeDictFromUnixTime((long)t);
            var months = new[] { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
            return GD.Fmt("%s %d", months[GD.Clampi((int)dt["month"] - 1, 0, 11)], (int)dt["year"]);
        }

        public static void _Tile(GridContainer g, string n, string cap, Color? col = null)
        {
            col ??= Color.WHITE;
            var t = new VBoxContainer();
            t.AddThemeConstantOverride("separation", -3);
            t.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            t.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            g.AddChild(t);
            var nl = UI2.Text(t, n, 19, col);
            nl.HorizontalAlignment = HorizontalAlignment.Center;
            var cl = new Label();
            cl.Text = cap;
            cl.HorizontalAlignment = HorizontalAlignment.Center;
            cl.AddThemeFontOverride("font", UI.HEAVY_FONT);
            cl.AddThemeFontSizeOverride("font_size", 10);
            cl.AddThemeColorOverride("font_color", UI2.MUTED);
            cl.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            t.AddChild(cl);
        }

        public static void _StatsBlock(VBoxContainer v, GDict pr, bool online)
        {
            var f = UI2.Frame(v, "glass", 10, 14.0);
            f.AddThemeConstantOverride("separation", 8);
            f.SetMeta("action_key", "card_stats");
            if (pr.IsEmpty() || !(bool)pr.Get("ok", false))
            {
                var why = online && pr.IsEmpty() ? "Loading..." : "No profile to show";
                if (GD.Str(pr.Get("why", "")) == "busy")
                    why = "Too many at once -- try again in a moment";
                var l = UI2.Body(f, why, 12, UI2.MUTED);
                l.HorizontalAlignment = HorizontalAlignment.Center;
                var lm = l.CustomMinimumSize;
                lm.y = 120;
                l.CustomMinimumSize = lm;
                l.VerticalAlignment = VerticalAlignment.Center;
                return;
            }
            // the class they play most, and the outfit they wear on him (0.31.188: it was the weapon they won most with)
            var cls = GD.Str(pr.Get("cls", ""));
            var outfit = GD.Str(pr.Get("sk", ""));
            var top = new HBoxContainer();
            top.AddThemeConstantOverride("separation", 10);
            f.AddChild(top);
            var portrait = outfit != "" && Eco.SKINS.Has(outfit) ? GD.Fmt("res://assets/ui/skins/%s.png", outfit) : GD.Fmt("res://assets/ui/skins/default_%s.png", cls);
            Texture2D tex = cls != "" && ResourceLoader.Exists(portrait) ? UI2.Tex(portrait) : null;
            if (tex != null)
            {
                var disc = new PanelContainer();
                var sb = new StyleBoxFlat();
                sb.BgColor = new Color("#20314a");
                sb.SetCornerRadiusAll(30);
                sb.SetBorderWidthAll(2);
                sb.BorderColor = UI2.GOLD;
                disc.AddThemeStyleboxOverride("panel", sb);
                disc.CustomMinimumSize = new Vector2(60, 60);
                disc.ClipChildren = CanvasItem.CLIP_CHILDREN_AND_DRAW;
                disc.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                top.AddChild(disc);
                var t = new TextureRect();
                t.Texture = tex;
                t.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
                t.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_COVERED;
                t.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                disc.AddChild(t);
            }
            var tv = new VBoxContainer();
            tv.AddThemeConstantOverride("separation", 0);
            tv.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            tv.Alignment = BoxContainer.ALIGNMENT_CENTER;
            top.AddChild(tv);
            if (cls != "")
            {
                UI2.Text(tv, GD.Str(Eco.CLASS_NAMES.Get(cls, cls.Capitalize())), 18, UI2.GOLD);
                var cm = (int)pr.Get("cm", 0);
                var sub = UI.Label(tv, GD.Fmt("Plays most  ·  %d match%s, %d won", cm, cm == 1 ? "" : "es", (int)pr.Get("cw", 0)), 11, UI2.SOFT, UI.HEAVY_FONT);
                sub.AutowrapMode = TextServer.AUTOWRAP_OFF;
            }
            else
                UI2.Text(tv, "New recruit", 18, UI2.GOLD);
            if (outfit != "" && Eco.SKINS.Has(outfit))
            {
                var wl = UI.Label(tv, "Wears " + GD.Str(Eco.SKINS[outfit]["name"]), 12, Color.FromCode(GD.Str(Eco.RARITY_COLOR.Get(GD.Str(Eco.SKINS[outfit]["rarity"]), "#ffffff"))), UI.HEAVY_FONT);
                wl.AutowrapMode = TextServer.AUTOWRAP_OFF;
                wl.ClipText = true;
            }
            // the numbers
            var g = new GridContainer();
            g.Columns = 3;
            g.AddThemeConstantOverride("h_separation", 4);
            g.AddThemeConstantOverride("v_separation", 6);
            f.AddChild(g);
            var m = (int)pr.Get("m", 0);
            _Tile(g, GD.Str((int)pr.Get("lv", 1)), "LEVEL", UI2.GOLD);
            _Tile(g, GD.Str((int)pr.Get("w", 0)), "WINS");
            _Tile(g, m > 0 ? GD.Fmt("%d%%", GD.Roundi(100.0 * (int)pr.Get("w", 0) / m)) : "-", "WIN RATE");
            _Tile(g, GD.Str((int)pr.Get("tw", 0)), "TOWERS");                 // (0.31.169: was Siege's RESCUES)
            _Tile(g, GD.Str((int)pr.Get("ko", 0)), "KNOCKOUTS");
            _Tile(g, GD.Str((int)pr.Get("bs", 0)), "BEST STREAK");
            var bits = new GArray();
            if ((int)pr.Get("rank", 0) > 0)
                bits.Append(GD.Fmt("#%d this week", (int)pr["rank"]));
            bits.Append(GD.Fmt("%d matches", m));
            if (SinceText((int)pr.Get("since", 0)) != "")
                bits.Append("since " + SinceText((int)pr["since"]));
            var foot = UI.Label(f, GStr.Join("  ·  ", bits), 11, UI2.MUTED, UI.HEAVY_FONT);
            foot.AutowrapMode = TextServer.AUTOWRAP_OFF;
            foot.HorizontalAlignment = HorizontalAlignment.Center;
        }

        // ---------------- a clan's card (0.31.134) ----------------
        public static void ClanCard(SiegeApp app, Control host, GDict c0)
        {
            var social = app.social;
            var id = GD.Str(c0.Get("id", ""));
            if (social == null || id == "")
                return;
            app.Sfx("menuOpen");
            foreach (var o in host.GetChildren())
            {
                if (o.HasMeta("clan_card"))
                    o.QueueFree();
            }
            var ov = new Control();
            ov.SetMeta("clan_card", true);
            ov.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            host.AddChild(ov);
            var dim = new ColorRect();
            dim.Color = new Color(0, 0, 0, 0.55);
            dim.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            dim.GuiInput += (InputEvent ev) =>
            {
                if ((ev is InputEventMouseButton || ev is InputEventScreenTouch) && !ev.IsPressed())
                {
                    app.Sfx("menuClose");
                    ov.QueueFree();
                }
            };
            ov.AddChild(dim);
            var cc = new CenterContainer();
            cc.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            cc.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            ov.AddChild(cc);
            var v = UI2.Frame(cc, "night", 14, 20.0, "gold");
            (v.GetParent() as Control).CustomMinimumSize = new Vector2(GD.Minf(340.0, host.Size.x - 32.0), 0);
            v.AddThemeConstantOverride("separation", 8);
            _FillClanCard(app, ov, v, c0);
            social.ClanInfo(id);
            Action<string> on_ch = (string what) =>
            {
                if (GArray.Of("clan_info", "clan").Has(what) && GD.IsInstanceValid(ov) && GD.IsInstanceValid(v) && ov.IsInsideTree())
                    _FillClanCard(app, ov, v, c0);
            };
            social.Changed += on_ch;
            ov.TreeExiting += () =>
            {
                // (if social.changed.is_connected(on_ch): disconnect -- removing a handler that isn't there does nothing)
                social.Changed -= on_ch;
            };
        }

        public static void _FillClanCard(SiegeApp app, Control ov, VBoxContainer v, GDict c0)
        {
            foreach (var ch in v.GetChildren())
                ch.QueueFree();
            var social = app.social;
            var id = GD.Str(c0.Get("id", ""));
            GDict info = social.clan_infos.Get(id, new GDict()).D;
            GDict c = c0.Duplicate();
            c.Merge(info, true);
            var house = GD.Str(c.Get("house", ""));
            if (GD.Str(c.Get("cc", "")) != "")
            {
                // 0.31.196: its crest (in its League frame), [TAG] and level
                var cw = new CenterContainer();
                v.AddChild(cw);
                Crest(cw, GD.Str(c["cc"]), 64.0, GD.Str(c.Get("fr", "")));
            }
            var nl = UI2.Text(v, GD.Str(c.Get("name", "")), 22, Color.WHITE);
            nl.HorizontalAlignment = HorizontalAlignment.Center;
            var sub_line = GD.Fmt("[%s]  ·  HOUSE %s", GD.Str(c.Get("tag", "")), HouseName(house).ToUpperInvariant());
            if ((int)c.Get("cv", 0) >= 2)
                sub_line = GD.Fmt("[%s]  ·  %s", GD.Str(c.Get("tag", "")), (bool)c.Get("hc", false) ? "STARTER CLAN" : GD.Fmt("LEVEL %d", (int)c.Get("lv", 1)));
            var hl = UI2.Text(v, sub_line, 14, (int)c.Get("cv", 0) >= 2 ? UI2.SOFT : HouseColor(house));
            hl.HorizontalAlignment = HorizontalAlignment.Center;
            var bits = GArray.Of(GD.Fmt("%d / %d members", (int)c.Get("n", 0), (int)c.Get("max", 30)),
                GDict.Of("open", "Open to all", "request", "Join by request", "invite", "Invite only").Get(GD.Str(c.Get("join", "")), ""));
            if ((int)c.Get("min_lv", 1) > 1)
                bits.Append(GD.Fmt("Lv %d+", (int)c["min_lv"]));
            var bl = UI.Label(v, GStr.Join("  ·  ", bits), 12, UI2.SOFT, UI.HEAVY_FONT);
            bl.HorizontalAlignment = HorizontalAlignment.Center;
            bl.AutowrapMode = TextServer.AUTOWRAP_OFF;
            var f = UI2.Frame(v, "glass", 10, 14.0);
            f.AddThemeConstantOverride("separation", 4);
            GArray members = info.Get("members", new GArray()).A;
            if (info.IsEmpty())
                UI2.Body(f, social.Online() ? "Loading..." : "Not connected", 12, UI2.MUTED);
            else if (members.IsEmpty())
                UI2.Body(f, "That clan is gone", 12, UI2.MUTED);
            foreach (var m in members.Slice(0, 12))
            {
                var r = UI.Row(f, 6);
                if (GD.Str(m.Get("role", "")) == "leader")
                    UI2.Icon(r, "crown", 16.0).SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
                var ml = UI2.Text(r, GD.Str(m.Get("n", "Player")), 14, Color.WHITE);
                ml.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
                ml.ClipText = true;
                if (GD.Str(m.Get("role", "")) == "officer")
                {
                    var ol = UI.Label(r, "OFFICER", 10, UI2.CYAN, UI.HEAVY_FONT);
                    ol.AutowrapMode = TextServer.AUTOWRAP_OFF;
                    ol.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
                }
            }
            if (members.Size() > 12)
                UI2.Body(f, GD.Fmt("and %d more", members.Size() - 12), 12, UI2.MUTED);
            Action<bool> done = (bool ok) =>
            {
                if (!ok)
                {
                    app.Sfx("error");
                    app.Toast("Not connected to the server right now", UI.RED);
                }
                else if (GD.IsInstanceValid(ov))
                    ov.QueueFree();
            };
            if (!social.InClan())
            {
                bool invited = social.clan_inv.Any(x => GD.Str(x.Get("id", "")) == id) || (bool)c.Get("invited", false);
                bool asked = social.clan_asked.Has(id) || (bool)c.Get("asked", false);
                var full = (int)c.Get("n", 0) >= (int)c.Get("max", 30);
                bool cool = social.ClanCoolLeft() > 0;
                if (asked)
                {
                    UI2.Button(v, "TAKE BACK MY REQUEST", "ghost", () =>
                    {
                        app.Sfx("tap");
                        done(social.ClanUnreq(id));
                    }, "clan_card_unreq", 14, 40.0);
                }
                else if (full && !invited)
                    UI2.DimButton(UI2.Button(v, "FULL", "grey", () => { }, "clan_card_full", 15, 44.0), true);
                else if (invited || GD.Str(c.Get("join", "")) == "open")
                {
                    var jb = UI2.Button(v, "JOIN", "green", () =>
                    {
                        app.Sfx("confirm");
                        done(social.ClanJoin(id));
                    }, "clan_card_join", 17, 46.0);
                    UI2.DimButton(jb, cool);
                }
                else if (GD.Str(c.Get("join", "")) == "request")
                {
                    var ab = UI2.Button(v, "ASK TO JOIN", "orange", () =>
                    {
                        app.Sfx("confirm");
                        done(social.ClanJoin(id));
                    }, "clan_card_ask", 17, 46.0);
                    UI2.DimButton(ab, cool);
                }
                else
                    UI2.DimButton(UI2.Button(v, "INVITE ONLY", "grey", () => { }, "clan_card_inviteonly", 15, 44.0), true);
            }
            UI2.Button(v, "CLOSE", "ghost", () =>
            {
                app.Sfx("menuClose");
                if (GD.IsInstanceValid(ov))
                    ov.QueueFree();
            }, "clan_card_close", 14, 36.0);
        }
    }
}
