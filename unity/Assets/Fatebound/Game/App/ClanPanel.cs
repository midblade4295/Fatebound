// Ported from godot/scripts/app/clan_panel.gd (Fatebound 0.31.222).
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
    // 0.31.134 (Kevin): the CLAN window, beside FRIENDS (the tabs at the top switch between them).
    // Not in a clan: invites waiting, FIND A CLAN (a search, JOIN / ASK on each), START A CLAN (name, tag, who may join, the
    // lowest level; 5,000 gold, taken by the server). In a clan: CLAN CHAT, requests waiting (officers), INVITE A PLAYER by
    // friend code (officers), the members (the leader's crown, OFFICER, each one's MANAGE for those you may manage), the
    // settings (officers) and LEAVE / DISBAND. Everything goes through scripts/meta/social.gd; the server (server/clans.gd)
    // decides.
    // 0.31.148 (Kevin: "make a default clan for each faction that the new players can choose"): the three house clans (free,
    // open to all; nobody runs them) first when not in a clan, JOIN on each; in one, the players' clans to move to or START A
    // CLAN (moving needs no leaving).
    // 0.31.196 (Kevin: "Now let's redo the clan system for new game" -> "Do clan chest, clan camp, crest, shard requests,
    // 5 - stack, lfg button, league"): no houses -- a clan has a CREST (picked when it's made; the leader and officers change
    // it: CHANGE CREST), the house clans are the STARTER CLANS. In a clan the window opens on its CAMP (scripts/app/
    // clan_camp.gd: the camp at its level's stage, its banners in the crest's colours) with the clan's crest, name, level and
    // XP over it, and three tabs:
    //   CAMP     CLAN CHAT; the CLAN CHEST (the week's points against its four tiers, mine, last week's result); PLAY
    //            TOGETHER (LOOKING FOR GROUP: a call in clan chat clanmates JOIN; the calls open; a party of 5); SHARD
    //            REQUESTS (ASK FOR A SHARD of a hero you don't own; GIVE a clanmate one you hold, for its melt gold); then
    //            requests, invite, crest and settings (officers), and LEAVE / DISBAND
    //   MEMBERS  each member's points this week
    //   LEAGUE   this week's clans by points (clan_league), the prizes, last week's podium
    // Against a server older than 0.31.196 (no "cv"): the clan as before, with a line that the rest comes with its update.
    // 0.31.197 (Kevin: "make the camp screen fill the entire screen instead of being a small box and incorporate the clan
    // buttons into the screen"): in a clan the window IS the camp -- the painting fills the screen (clan_camp.gd) and the
    // clan's buttons stand in it: at the top FRIENDS and close, the crest with the clan's name, level and XP in the sky, any
    // clanmate's LFG call (JOIN) under them; on the ground by the fire the CLAN CHEST (its tier, the week's points) and the
    // SHARD REQUESTS board; then CHAT, MEMBERS, LEAGUE and CLAN (crest, settings, leave); and LOOKING FOR GROUP at the
    // bottom. Each but CHAT and LFG opens its sheet over the camp (the CHEST, SHARDS, MEMBERS, LEAGUE, CLAN parts of 0.31.196).
    public class ClanPanel : Control
    {
        public static readonly GDict JOIN_TEXT = new GDict { { "open", "Open to all" }, { "request", "Join by request" }, { "invite", "Invite only" } };
        public static readonly GDict TIER_COL = new GDict { { "wooden", Color.FromCode("#c08a55") }, { "silver", Color.FromCode("#c9d3dc") }, { "gold", Color.FromCode("#ffcf4a") }, { "royal", Color.FromCode("#c47bff") } };
        public static readonly GDict FRAME_COL = new GDict { { "gold", Color.FromCode("#ffcf4a") }, { "silver", Color.FromCode("#d6e0ea") }, { "bronze", Color.FromCode("#e0955a") } };
        public const double LEAGUE_STALE = 20.0;             // s before LEAGUE asks the server again

        public SiegeApp app;
        public Social social;
        public VBoxContainer _list;
        public ScrollContainer _scroll;
        public bool _dirty = false;
        public bool _making = false;                  // START CLAN sent, waiting for the server's answer
        public GDict _crest = new GDict();                      // the crest for a new clan {"e", "f", "c"}
        public string _join = "open";
        public int _min_lv = 1;
        public string _set_join = "";                   // the settings being edited (officers)
        public int _set_lv = 0;
        public GDict _fields = new GDict();                     // name -> LineEdit (what's typed survives a redraw)
        public GDict _typed = new GDict();
        public string focus = "";                       // 0.31.147: "join" -- opened to join one
        public Control _start_box = null;        // START A CLAN's section (START MY OWN CLAN scrolls to it)
        public string _shown_clan = "";                 // the clan the window was drawn for (a change: back to the top)
        public bool _asked_list = false;              // (0.31.148: in a house clan, the players' clans asked for once)
        public string mode = "";                        // 0.31.197: "window" (not in a clan, an older server) or "full" (the camp)
        public ClanCamp camp = null;              // the camp painting on screen (clan_camp.gd)
        public string _camp_key = "";                   // (redrawn only when its stage, crest or frame changes)
        public string sheet = "";                       // 0.31.197: the sheet open over the camp ("chest", "shards", "members", "league", "clan")
        public Control _camp_layer = null;
        public Control _ui_layer = null;
        public Control _sheet_layer = null;
        public Control _overlay = null;          // the crest editor or the hero picker, over the window
        public double _league_asked = -999.0;

        public void Open(SiegeApp a, string f = "")
        {
            app = a;
            social = a.social;
            focus = f;
            _crest = RandomCrest();
            SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            social.Changed += _OnChanged;
            social.ClanMade += _OnMade;
            if (social.Online() && !social.InClan())
                social.ClanFind("", "");
            _shown_clan = GD.Str(social.clan.Get("id", ""));
            _Render();
        }

        public string _WantMode()
        {
            return social.Online() && social.has_clans && social.InClan() && social.ClanV2() ? "full" : "window";
        }

        public void _Build(string m)
        {
            // the window (a framed list) or the camp (full screen, its layers) -- everything that was here goes
            mode = m;
            foreach (var c in GetChildren())
            {
                if (c != _overlay)
                {
                    RemoveChild(c);
                    c.QueueFree();
                }
            }
            camp = null;
            _camp_key = "";
            sheet = "";
            _list = null;
            _scroll = null;
            if (m == "window")
            {
                var w = SocialUI.Window(this, "CLAN", "castle", () =>
                {
                    app.Sfx("menuClose");
                    app.CloseModal();
                }, 56.0 + (double)app.safe_top, 24.0);
                VBoxContainer body = w["body"].As<VBoxContainer>();
                SocialUI.SocialTabs(body, app, "clan");
                _scroll = new ScrollContainer();
                _scroll.SizeFlagsVertical = Control.SIZE_EXPAND_FILL;
                _scroll.HorizontalScrollMode = ScrollContainer.SCROLL_MODE_DISABLED;
                _scroll.ScrollDeadzone = 1000000;
                body.AddChild(_scroll);
                SetMeta("drag_scroll", _scroll);
                _list = new VBoxContainer();
                _list.AddThemeConstantOverride("separation", 10);
                _list.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
                _scroll.AddChild(_list);
            }
            else
            {
                var bg = new ColorRect();
                bg.Color = new Color(0.02, 0.02, 0.06);
                bg.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
                AddChild(bg);
                foreach (var n in new[] { "CampLayer", "UiLayer", "SheetLayer" })
                {
                    var l = new Control();
                    l.Name = n;
                    l.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
                    l.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                    AddChild(l);
                }
                _camp_layer = GetNode("CampLayer") as Control;
                _ui_layer = GetNode("UiLayer") as Control;
                _sheet_layer = GetNode("SheetLayer") as Control;
                if (HasMeta("drag_scroll"))
                    RemoveMeta("drag_scroll");
            }
            if (GD.IsInstanceValid(_overlay))
                MoveChild(_overlay, GetChildCount() - 1);
        }

        protected override void _ExitTree()
        {
            if (social != null)
            {
                // (is_connected / disconnect: removing a handler that isn't there does nothing)
                social.Changed -= _OnChanged;
                social.ClanMade -= _OnMade;
            }
        }

        public void _OnChanged(string what)
        {
            if (GArray.Of("clan", "clans", "state", "me", "friends", "league", "party").Has(what))
                _dirty = true;
        }

        public void _OnMade(bool ok, string _why)
        {
            _making = false;
            if (ok)
            {
                app.Sfx("confirm");
                foreach (var k in new[] { "new_name", "new_tag" })
                    _typed.Erase(k);
                app.ClanFounded();
            }
            _dirty = true;
        }

        protected override void _Process(double _delta)
        {
            if (_dirty)
            {
                _dirty = false;
                var keep = GD.IsInstanceValid(_scroll) ? _scroll.ScrollVertical : 0;
                var now_in = GD.Str(social.clan.Get("id", ""));
                if (now_in != _shown_clan)
                {
                    keep = 0;                               // (joined, left or moved clans: the window from its top)
                    _shown_clan = now_in;
                    sheet = "";
                }
                foreach (var k in _fields)
                {
                    if (GD.IsInstanceValid(_fields[k]))
                        _typed[k] = _fields[k].As<LineEdit>().Text;
                }
                _Render();
                if (GD.IsInstanceValid(_scroll))
                {
                    var sc = _scroll;
                    CallDeferred(() => sc.ScrollVertical = keep);
                }
            }
        }

        public static GDict RandomCrest()
        {
            var e = (int)(GD.Randi() % Eco.CLAN_EMBLEMS.Size());
            var f = (int)(GD.Randi() % 6);                         // (the strong colours first: blue, red, green, purple, orange, night)
            var c = f != 9 ? 0 : 2;
            if (GD.Randf() < 0.35)
                c = 1;                                    // gold
            return new GDict { { "e", e }, { "f", f }, { "c", c } };
        }

        // ---------------- pieces ----------------
        public VBoxContainer _Section(string title, string sub = "", string rim = "")
        {
            var f = rim == "" ? UI2.Frame(_list, "glass", 10, 16.0) : UI2.Frame(_list, "night", 12, 18.0, rim);
            f.AddThemeConstantOverride("separation", 6);
            if (title != "")
            {
                var h = UI.Row(f, 8);
                UI.Grow(UI2.Text(h, title, 17, UI2.GOLD));
                if (sub != "")
                {
                    var s = UI.Label(h, sub, 12, UI2.MUTED, UI.HEAVY_FONT);
                    s.AutowrapMode = TextServer.AUTOWRAP_OFF;
                    s.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
                }
            }
            return f;
        }

        public Button _Small(Node parent, string text, string color, string key, Action cb, double w = 78.0)
        {
            var b = UI2.Button(parent, text, color, cb, key, 13, 36.0, 11.0);
            { var cm = b.CustomMinimumSize; cm.x = (float)w; b.CustomMinimumSize = cm; }
            b.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            return b;
        }

        public LineEdit _Field(Node parent, string key, string placeholder, int max_len)
        {
            var e = SocialUI.Field(parent, placeholder, max_len);
            e.Text = GD.Str(_typed.Get(key, ""));
            _fields[key] = e;
            return e;
        }

        public void _Fail()
        {
            app.Sfx("error");
            app.Toast("Not connected to the server right now", UI.RED);
        }

        public void _Armed(Button b, string again, Action cb)
        {
            // a button that needs a second tap (leave, disband, remove, hand over)
            b.Pressed += () =>
            {
                if (b.HasMeta("armed"))
                    cb();
                else
                {
                    b.SetMeta("armed", true);
                    b.Text = again;
                    app.Sfx("tap");
                }
            };
        }

        public Label _NoteLabel(Node parent, string s, int size = 12, Color? col = null)
        {
            Color cl = col ?? UI2.MUTED;
            var l = UI.Label(parent, s, size, cl, UI.HEAVY_FONT);
            l.AutowrapMode = TextServer.AUTOWRAP_OFF;
            l.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            l.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            return l;
        }

        public HBoxContainer _ClanLine(Node parent, GDict c)
        {
            // a clan in a list: its crest (0.31.196; a house chip from an older server), [TAG] name, and level · members · who
            // may join
            var r = UI.Row(parent, 8);
            if (GD.Str(c.Get("cc", "")) != "")
                SocialUI.Crest(r, GD.Str(c["cc"]), 34.0, GD.Str(c.Get("fr", "")));
            else
                SocialUI.HouseChip(r, GD.Str(c.Get("house", "")));
            var nb = new Button();
            nb.Flat = true;
            nb.FocusMode = Control.FOCUS_NONE;
            nb.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            nb.ClipText = true;
            nb.CustomMinimumSize = new Vector2(0, 46);
            foreach (var st_name in new[] { "normal", "hover", "pressed", "focus", "hover_pressed" })
                nb.AddThemeStyleboxOverride(st_name, new StyleBoxEmpty());
            nb.SetMeta("action_key", "clan_card_" + GD.Str(c.Get("id", "")));
            var cc = c.Duplicate();
            nb.Pressed += () => SocialUI.ClanCard(app, this, cc);
            r.AddChild(nb);
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", -2);
            v.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            v.Alignment = BoxContainer.ALIGNMENT_CENTER;
            v.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            nb.AddChild(v);
            var top = UI.Row(v, 6);
            top.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            var v2 = (int)c.Get("cv", 0) >= 2;
            var tl = UI2.Text(top, GD.Fmt("[%s]", GD.Str(c.Get("tag", ""))), 15, v2 ? UI2.SOFT : SocialUI.HouseColor(GD.Str(c.Get("house", ""))));
            tl.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            var nl = UI2.Text(top, GD.Str(c.Get("name", "")), 15, Color.WHITE);
            nl.ClipText = true;
            nl.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            nl.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            var bits = GArray.Of(v2 ? GD.Fmt("Lv %d", (int)c.Get("lv", 1)) : SocialUI.HouseName(GD.Str(c.Get("house", ""))), GD.Fmt("%d/%d", (int)c.Get("n", 0), (int)c.Get("max", 30)),
                GD.Str(JOIN_TEXT.Get(GD.Str(c.Get("join", "")), "")));
            if ((bool)c.Get("hc", false))
                bits = GArray.Of("Starter clan", GD.Fmt("%d member%s", (int)c.Get("n", 0), (int)c.Get("n", 0) == 1 ? "" : "s"), "free, open to all");
            else if (v2 && (int)c.Get("pts", 0) > 0)
                bits.Insert(1, GD.Fmt("%s pts this week", _Thousands((int)c["pts"])));
            if ((int)c.Get("min_lv", 1) > 1)
                bits.Append(GD.Fmt("Lv %d+ to join", (int)c["min_lv"]));
            var sl = UI.Label(v, GStr.Join("  ·  ", bits), 11, UI2.MUTED, UI.HEAVY_FONT);
            sl.AutowrapMode = TextServer.AUTOWRAP_OFF;
            sl.ClipText = true;
            sl.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            return r;
        }

        // ---------------- the window ----------------
        public void _Render()
        {
            _fields = new GDict();
            var want = _WantMode();
            if (want != mode)
                _Build(want);
            if (mode == "full")
            {
                _RenderFull();
                return;
            }
            foreach (var c in _list.GetChildren())
            {
                _list.RemoveChild(c);
                c.QueueFree();
            }
            if (!social.Online())
            {
                var f = _Section("NOT CONNECTED");
                var why = "Clans need the game's server. Trying again shortly...";
                if (!social.HasAccount())
                    why = "Clans start once you've been online with the game's server.";
                else if (GD.Str(social.state) == "connecting")
                    why = "Connecting...";
                UI2.Body(f, why, 13, UI2.SOFT);
                return;
            }
            if (!social.has_clans)
            {
                UI2.Body(_Section("CLANS"), "Clans arrive with the next server update.", 13, UI2.SOFT);
                return;
            }
            if (social.InClan())
                _RenderMineOld();
            else
                _RenderFree();
        }

        // ---------------- not in a clan ----------------
        public void _RenderFree()
        {
            int cool = social.ClanCoolLeft();
            var intro = _Section(focus == "join" ? "JOIN A CLAN" : "YOUR CLAN");
            if (cool > 0)
                UI2.Body(intro, GD.Fmt("You left a clan recently. You can join a players' clan or start one again in %s -- the starter clans are open to you now.", _Hours(cool)), 13, UI2.CYAN);
            else if (focus == "join")
                UI2.Body(intro, "Pick a starter clan -- free, open to all -- or a players' clan. Or start your own with its own crest.", 13, UI2.SOFT);
            else
                UI2.Body(intro, "You're not in a clan yet. Clans fill a Clan Chest every week, climb the Clan League, party up 5 at a time and share hero shards. Join one below or start your own.", 13, UI2.SOFT);
            // 0.31.147 (Kevin: "When they click join clan it put the list of available clans or they have option to start clan"):
            // the list is right under this; START MY OWN CLAN goes down to the form
            UI2.Button(intro, "START MY OWN CLAN", "gold", () =>
            {
                app.Sfx("tab");
                _ToStart();
            }, "clan_to_start", 14, 38.0);
            // ---- invites
            if (!social.clan_inv.IsEmpty())
            {
                var inf = _Section("CLAN INVITES", GD.Str(social.clan_inv.Size()));
                foreach (var cv in social.clan_inv)
                {
                    GDict c = cv.D;
                    _ClanLine(inf, c);
                    var by = UI.Label(inf, GD.Fmt("Invited by %s", GD.Str(c.Get("by", ""))), 11, UI2.SOFT, UI.HEAVY_FONT);
                    by.AutowrapMode = TextServer.AUTOWRAP_OFF;
                    var br = UI.Row(inf, 8);
                    var cid = GD.Str(c.Get("id", ""));
                    var jb = UI2.Button(br, "JOIN", "green", () =>
                    {
                        app.Sfx("confirm");
                        if (!social.ClanJoin(cid))
                            _Fail();
                    }, "clan_inv_join_" + cid, 15, 40.0);
                    UI.Grow(jb);
                    UI2.DimButton(jb, cool > 0);
                    var nb = _Small(br, "NO THANKS", "ghost", "clan_inv_no_" + cid, () =>
                    {
                        app.Sfx("tap");
                        social.ClanNoinv(cid);
                    }, 120.0);
                    { var cm = nb.CustomMinimumSize; cm.y = 40; nb.CustomMinimumSize = cm; }
                }
            }
            // ---- 0.31.148: the house clans (0.31.196: the starter clans)
            _HouseSection();
            _FindSection(cool);
            // ---- start one
            _RenderNew(cool);
        }

        public void _HouseSection()
        {
            // 0.31.148: the three house clans, each with JOIN (free, open to all; the 24-hour wait doesn't apply)
            if (social.house_clans.IsEmpty())
                return;
            var hf = _Section("STARTER CLANS", "FREE");
            UI2.Body(hf, "Open to all, no wait to leave. Players' clans fill a Clan Chest and play in the League.", 12, UI2.MUTED);
            foreach (var cv in social.house_clans)
            {
                GDict c = cv.D;
                var r = _ClanLine(hf, c);
                var cid = GD.Str(c.Get("id", ""));
                if (GD.Str(social.clan.Get("id", "")) == cid)
                {
                    _NoteLabel(r, "YOURS", 12, UI2.GREEN);
                    continue;
                }
                _Small(r, "JOIN", "green", "clan_house_join_" + GD.Str(c.Get("house", "")), () =>
                {
                    app.Sfx("confirm");
                    if (!social.ClanJoin(cid))
                        _Fail();
                }, 76.0);
            }
        }

        public void _FindSection(int cool)
        {
            var ff = _Section(!social.InHouseClan() ? "FIND A CLAN" : "MOVE TO A PLAYERS' CLAN");
            var sr = UI.Row(ff, 8);
            var q = _Field(sr, "find", "Clan name or tag", 20);
            q.TextSubmitted += (_t) => _Search();
            _Small(sr, "FIND", "blue", "clan_find", () => _Search(), 80.0);
            GArray list = social.clan_list.Filter(c => !(bool)c.Get("hc", false));   // (the starter clans: above)
            if (list.IsEmpty())
                UI2.Body(ff, social.clan_query == "" ? "No players' clans yet -- be the first to start one!" : "No clans match that.", 13, UI2.MUTED);
            foreach (var cv in list)
            {
                GDict c = cv.D;
                var r = _ClanLine(ff, c);
                var cid = GD.Str(c.Get("id", ""));
                bool full = (int)c.Get("n", 0) >= (int)c.Get("max", 30);
                bool invited = social.clan_inv.Any(x => GD.Str(x.Get("id", "")) == cid);
                bool asked = social.clan_asked.Has(cid) || (bool)c.Get("asked", false);
                if (full && !invited)
                    UI2.DimButton(_Small(r, "FULL", "grey", "clan_full_" + cid, () => { }, 76.0), true);
                else if (asked)
                {
                    _Small(r, "ASKED", "ghost", "clan_asked_" + cid, () =>
                    {
                        app.Sfx("tap");
                        social.ClanUnreq(cid);
                        app.Toast("Request taken back", UI.MUTED);
                    }, 76.0);
                }
                else if (invited || GD.Str(c.Get("join", "")) == "open")
                {
                    var b = _Small(r, "JOIN", "green", "clan_join_" + cid, () =>
                    {
                        app.Sfx("confirm");
                        if (!social.ClanJoin(cid))
                            _Fail();
                    }, 76.0);
                    UI2.DimButton(b, cool > 0);
                }
                else if (GD.Str(c.Get("join", "")) == "request")
                {
                    var b2 = _Small(r, "ASK", "orange", "clan_ask_" + cid, () =>
                    {
                        app.Sfx("confirm");
                        if (!social.ClanJoin(cid))
                            _Fail();
                    }, 76.0);
                    UI2.DimButton(b2, cool > 0);
                }
                else
                {
                    UI2.DimButton(_Small(r, "INVITE", "grey", "clan_inviteonly_" + cid, () =>
                        app.Toast("This clan is invite only", UI.MUTED), 76.0), true);
                }
            }
        }

        public void _Search()
        {
            var t = "";
            if (_fields.Has("find") && GD.IsInstanceValid(_fields["find"]))
                t = _fields["find"].As<LineEdit>().Text;
            if (!social.ClanFind(t, ""))
                _Fail();
        }

        public void _ToStart()
        {
            // scroll the window down to START A CLAN
            if (GD.IsInstanceValid(_start_box))
            {
                var pc = _start_box.GetParent() as Control;
                _scroll.ScrollVertical = pc != null ? GD.Int(pc.Position.y) : GD.Int(_start_box.Position.y);
            }
        }

        public void _RenderNew(int cool)
        {
            var nf = _Section("START A CLAN");
            _start_box = nf;
            var gold = (int)app.profile.d.Get("gold", 0);
            int cost = social.clan_cost;
            UI2.Body(nf, GD.Fmt("Costs %s gold (you have %s).", _Thousands(cost), _Thousands(gold)), 13,
                gold >= cost ? UI2.SOFT : Color.FromCode("#ffb0a0"));
            var nr = UI.Row(nf, 8);
            var ne = _Field(nr, "new_name", "Clan name", 20);
            ne.SizeFlagsStretchRatio = 3.0;
            var te = _Field(nr, "new_tag", "TAG", 4);
            te.SizeFlagsStretchRatio = 1.2;
            te.TextChanged += (string tx) =>           // (a tag is capitals: shown so as it's typed)
            {
                if (tx != tx.ToUpperInvariant())
                {
                    var at = te.CaretColumn;
                    te.Text = tx.ToUpperInvariant();
                    te.CaretColumn = at;
                }
            };
            UI2.Body(nf, "CREST", 12, UI2.MUTED);
            CrestEditor(nf, _crest, "crest", (GDict k) =>
            {
                _crest = k;
                _dirty = true;
            });
            if (!social.has_lfg)
                UI2.Body(nf, "(Your crest shows once the game's server updates.)", 11, UI2.MUTED);
            UI2.Body(nf, "WHO MAY JOIN", 12, UI2.MUTED);
            var jr = UI.Row(nf, 6);
            foreach (var j in new[] { "open", "request", "invite" })
            {
                string jid = j;
                var jb = UI2.Button(jr, GD.Str(new GDict { { "open", "OPEN" }, { "request", "REQUEST" }, { "invite", "INVITE" } }[jid]), _join == jid ? "gold" : "grey", () =>
                {
                    app.Sfx("tab");
                    _join = jid;
                    _dirty = true;
                }, "clan_join_mode_" + jid, 13, 36.0, 10.0);
                UI.Grow(jb);
            }
            _LevelRow(nf, "LOWEST LEVEL", _min_lv, (int v) =>
            {
                _min_lv = v;
                _dirty = true;
            }, "clan_new_lv");
            var go = UI2.Button(nf, _making ? "WAITING..." : GD.Fmt("START CLAN  ·  %s GOLD", _Thousands(cost)), "gold", () => _Start(), "clan_start", 17, 48.0);
            UI2.DimButton(go, _making || cool > 0 || gold < cost);
        }

        public void _LevelRow(Node parent, string title, int value, Action<int> set_cb, string key)
        {
            var r = UI.Row(parent, 8);
            _NoteLabel(r, title);
            var sp = new Control();
            sp.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            r.AddChild(sp);
            _Small(r, "−", "blue", key + "_down", () =>
            {
                app.Sfx("tap");
                set_cb(GD.Maxi(1, value - (value > 10 ? 5 : 1)));
            }, 44.0);
            var v = UI2.Text(r, GD.Fmt("Lv %d", value), 16, Color.WHITE);
            { var cm = v.CustomMinimumSize; cm.x = 64; v.CustomMinimumSize = cm; }
            v.HorizontalAlignment = HorizontalAlignment.Center;
            v.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            _Small(r, "+", "blue", key + "_up", () =>
            {
                app.Sfx("tap");
                set_cb(GD.Mini(100, value + (value >= 10 ? 5 : 1)));
            }, 44.0);
        }

        public void _Start()
        {
            if (_making)
                return;
            var name = "";
            var tag = "";
            if (GD.IsInstanceValid(_fields.Get("new_name")))
                name = _fields["new_name"].As<LineEdit>().Text.StripEdges();
            if (GD.IsInstanceValid(_fields.Get("new_tag")))
                tag = _fields["new_tag"].As<LineEdit>().Text.StripEdges().ToUpperInvariant();
            var why = "";
            if (name.Length < 3)
                why = "Give your clan a name (3-20 letters)";
            else if (tag.Length < 3 || !_Alnum(tag))
                why = "A tag is 3-4 letters or numbers (like WOLF)";
            else if (Eco.CleanCrest(_crest).IsEmpty())
                why = "Pick your clan's crest";
            else if (social.ClanCoolLeft() > 0)
                why = GD.Fmt("You can start a clan again in %s", _Hours(social.ClanCoolLeft()));
            else if ((int)app.profile.d.Get("gold", 0) < (int)social.clan_cost)
                why = GD.Fmt("Starting a clan costs %s gold", _Thousands((int)social.clan_cost));
            if (why != "")
            {
                app.Sfx("error");
                app.Toast(why, UI.RED);
                return;
            }
            if (!social.ClanNew(name, tag, Eco.CleanCrest(_crest), _join, _min_lv))
            {
                _Fail();
                return;
            }
            app.Sfx("tap");
            _making = true;
            _dirty = true;
        }

        public static bool _Alnum(string t)
        {
            foreach (var ch in (Var)t)
            {
                if (!((ch >= "A" && ch <= "Z") || (ch >= "0" && ch <= "9")))
                    return false;
            }
            return true;
        }

        // ---------------- the crest editor (0.31.196) ----------------
        public void CrestEditor(Node parent, GDict k, string key, Action<GDict> changed)
        {
            // the crest as it stands (big) with SHUFFLE; the sixteen emblems (each in the crest's colours), the shield's colours,
            // the emblem's colours. Every tap calls changed with the new {"e", "f", "c"}.
            var cur = Eco.CleanCrest(k);
            if (cur.IsEmpty())
                cur = new GDict { { "e", 0 }, { "f", 0 }, { "c", 0 } };
            var top = UI.Row(parent, 12);
            var pv = SocialUI.Crest(top, Eco.CrestCode(cur), 92.0);
            pv.SetMeta("crest_preview", Eco.CrestCode(cur));
            var tv = new VBoxContainer();
            tv.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            tv.Alignment = BoxContainer.ALIGNMENT_CENTER;
            top.AddChild(tv);
            UI2.Body(tv, "Your clan's banner: on its camp, beside every member's name and on the League.", 12, UI2.SOFT);
            UI2.Button(tv, "SHUFFLE", "blue", () =>
            {
                app.Sfx("tap");
                changed(RandomCrest());
            }, key + "_random", 13, 34.0, 10.0);
            _NoteLabel(parent, "EMBLEM", 11);
            var g = new GridContainer();
            g.Columns = 8;
            g.AddThemeConstantOverride("h_separation", 4);
            g.AddThemeConstantOverride("v_separation", 4);
            parent.AddChild(g);
            for (int i = 0; i < Eco.CLAN_EMBLEMS.Size(); i++)
            {
                int ei = i;
                var b = _Swatch(g, Color.FromCode(GD.Str(Eco.CLAN_FIELDS[(int)cur["f"]])), (int)cur["e"] == ei, key + GD.Fmt("_e_%d", ei), () =>
                {
                    app.Sfx("tab");
                    changed(new GDict { { "e", ei }, { "f", (int)cur["f"] }, { "c", (int)cur["c"] } });
                });
                var t = new TextureRect();
                t.Texture = Crest.Tex("emblem_" + GD.Str(Eco.CLAN_EMBLEMS[ei]));
                t.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
                t.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
                t.TextureFilter = TextureFilterMode.LinearWithMipmaps;
                t.Modulate = Color.FromCode(GD.Str(Eco.CLAN_CHARGES[(int)cur["c"]]));
                t.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                t.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
                t.OffsetLeft = 5;
                t.OffsetTop = 5;
                t.OffsetRight = -5;
                t.OffsetBottom = -5;
                b.AddChild(t);
            }
            _NoteLabel(parent, "SHIELD", 11);
            var fr = new GridContainer();
            fr.Columns = 10;
            fr.AddThemeConstantOverride("h_separation", 4);
            parent.AddChild(fr);
            for (int i = 0; i < Eco.CLAN_FIELDS.Size(); i++)
            {
                int fi = i;
                _Swatch(fr, Color.FromCode(GD.Str(Eco.CLAN_FIELDS[fi])), (int)cur["f"] == fi, key + GD.Fmt("_f_%d", fi), () =>
                {
                    app.Sfx("tab");
                    changed(new GDict { { "e", (int)cur["e"] }, { "f", fi }, { "c", (int)cur["c"] } });
                }, 28.0);
            }
            _NoteLabel(parent, "EMBLEM COLOUR", 11);
            var cr = new GridContainer();
            cr.Columns = 8;
            cr.AddThemeConstantOverride("h_separation", 4);
            parent.AddChild(cr);
            for (int i = 0; i < Eco.CLAN_CHARGES.Size(); i++)
            {
                int ci = i;
                _Swatch(cr, Color.FromCode(GD.Str(Eco.CLAN_CHARGES[ci])), (int)cur["c"] == ci, key + GD.Fmt("_c_%d", ci), () =>
                {
                    app.Sfx("tab");
                    changed(new GDict { { "e", (int)cur["e"] }, { "f", (int)cur["f"] }, { "c", ci } });
                }, 30.0);
            }
        }

        public Button _Swatch(Node parent, Color fill, bool on, string key, Action cb, double h = 36.0)
        {
            var b = new Button();
            b.FocusMode = Control.FOCUS_NONE;
            b.CustomMinimumSize = new Vector2(0, h);
            b.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            foreach (var st_name in new[] { "normal", "hover", "pressed", "focus", "hover_pressed" })
            {
                var sb = new StyleBoxFlat();
                sb.BgColor = fill;
                sb.SetCornerRadiusAll(8);
                sb.BorderColor = on ? Color.FromCode("#ffe08a") : new Color(0, 0, 0, 0.55);
                sb.SetBorderWidthAll(on ? 3 : 1);
                b.AddThemeStyleboxOverride(st_name, sb);
            }
            b.SetMeta("action_key", key);
            b.Pressed += cb;
            parent.AddChild(b);
            return b;
        }

        public VBoxContainer _OpenOverlay(string title, double w = 340.0, bool quiet = false)
        {
            _CloseOverlay();
            if (!quiet)
                app.Sfx("menuOpen");
            var ov = new Control();
            ov.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            AddChild(ov);
            _overlay = ov;
            var dim = new ColorRect();
            dim.Color = new Color(0, 0, 0, 0.6);
            dim.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            dim.GuiInput += (InputEvent ev) =>
            {
                if ((ev is InputEventMouseButton || ev is InputEventScreenTouch) && !ev.IsPressed())
                {
                    app.Sfx("menuClose");
                    _CloseOverlay();
                }
            };
            ov.AddChild(dim);
            var cc = new CenterContainer();
            cc.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            cc.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            ov.AddChild(cc);
            var v = UI2.Frame(cc, "royal", 14, 20.0, "gold");
            (v.GetParent() as Control).CustomMinimumSize = new Vector2(GD.Minf(w, Size.x - 28.0), 0);
            UI2.Center(UI2.Text(v, title, 20, Color.WHITE));
            return v;
        }

        public void _CloseOverlay()
        {
            if (GD.IsInstanceValid(_overlay))
                _overlay.QueueFree();
            _overlay = null;
        }

        public void _EditCrest(GDict k, bool again = false)
        {
            // CHANGE CREST (the leader and officers)
            var v = _OpenOverlay("CHANGE CREST", 360.0, again);
            CrestEditor(v, k, "crest_edit", (GDict nk) => _EditCrest(nk, true));
            var r = UI.Row(v, 8);
            UI.Grow(UI2.Button(r, "CANCEL", "ghost", () =>
            {
                app.Sfx("menuClose");
                _CloseOverlay();
            }, "clan_crest_cancel", 14, 42.0));
            bool same = Eco.CrestCode(k) == social.MyCrest();
            var sb = UI2.Button(r, "SAVE CREST", "green", () =>
            {
                if (social.ClanCrest(Eco.CleanCrest(k)))
                {
                    app.Sfx("confirm");
                    _CloseOverlay();
                }
                else
                    _Fail();
            }, "clan_crest_save", 15, 42.0);
            UI.Grow(sb);
            UI2.DimButton(sb, same);
        }

        // ---------------- in a clan: the camp, full screen (0.31.196; 0.31.197) ----------------
        public void _RenderFull()
        {
            GDict c = social.clan;
            var hc = (bool)c.Get("hc", false);
            var lv = (int)c.Get("lv", 1);
            var key = GD.Fmt("%d|%s|%s", Eco.ClanCampStage(lv), GD.Str(c.Get("cc", "")), GD.Str(c.Get("fr", "")));
            if (key != _camp_key || !GD.IsInstanceValid(camp))
            {
                _camp_key = key;
                foreach (var ch in _camp_layer.GetChildren())
                    ch.QueueFree();
                camp = new ClanCamp();
                camp.Setup(Eco.ClanCampStage(lv), GD.Str(c.Get("cc", "")), GD.Str(c.Get("fr", "")), (bool)app.profile.d["settings"].Get("reduce_motion", false));
                camp.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
                _camp_layer.AddChild(camp);
            }
            foreach (var ch in _ui_layer.GetChildren())
            {
                _ui_layer.RemoveChild(ch);
                ch.QueueFree();
            }
            var mc = new MarginContainer();
            mc.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            mc.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            mc.AddThemeConstantOverride("margin_left", 12);
            mc.AddThemeConstantOverride("margin_right", 12);
            mc.AddThemeConstantOverride("margin_top", GD.Int(8.0 + (double)app.safe_top));
            mc.AddThemeConstantOverride("margin_bottom", 16);
            _ui_layer.AddChild(mc);
            var col = new VBoxContainer();
            col.AddThemeConstantOverride("separation", 8);
            col.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            mc.AddChild(col);
            // ---- the top: FRIENDS, close
            var top = UI.Row(col, 8);
            top.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            int fr_n = social.rin.Size() + social.invites.Size();
            var fb = UI2.Button(top, "FRIENDS" + (fr_n > 0 ? GD.Fmt("  (%d)", fr_n) : ""), "blue", () =>
            {
                app.Sfx("tab");
                app.OpenSocial("friends");
            }, "social_tab_friends", 14, 38.0, 12.0, UI2.IconPath("friends"));
            { var cm = fb.CustomMinimumSize; cm.x = 126; fb.CustomMinimumSize = cm; }
            var sp = new Control();
            sp.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            sp.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            top.AddChild(sp);
            var xb = UI2.Button(top, "✕", "ghost", () =>
            {
                app.Sfx("menuClose");
                app.CloseModal();
            }, "clan_close", 18, 38.0, 12.0);
            { var cm = xb.CustomMinimumSize; cm.x = 46; xb.CustomMinimumSize = cm; }
            // ---- the sky: the crest, the clan's name, level and XP
            var head = new VBoxContainer();
            head.AddThemeConstantOverride("separation", 0);
            head.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            col.AddChild(head);
            var cw = new CenterContainer();
            cw.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            head.AddChild(cw);
            var big = SocialUI.Crest(cw, GD.Str(c.Get("cc", "")), 60.0, GD.Str(c.Get("fr", "")));       // (84 in portrait)
            big.SetMeta("clan_crest_big", true);
            var nl = UI2.Text(head, GD.Str(c.Get("name", "")), 24, Color.WHITE);
            nl.HorizontalAlignment = HorizontalAlignment.Center;
            nl.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            var sub = GD.Fmt("[%s]  ·  %s", GD.Str(c.Get("tag", "")), hc ? "STARTER CLAN" : GD.Fmt("LEVEL %d", lv));
            if (GD.Str(c.Get("fr", "")) != "")
                sub += GD.Fmt("  ·  LEAGUE #%d", new GDict { { "gold", 1 }, { "silver", 2 }, { "bronze", 3 } }.Get(GD.Str(c["fr"]), 0));
            var sl = UI2.Text(head, sub, 14, (Color)FRAME_COL.Get(GD.Str(c.Get("fr", "")), UI2.CREAM));
            sl.HorizontalAlignment = HorizontalAlignment.Center;
            sl.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            if (!hc)
            {
                var xp = (int)c.Get("xp", 0);
                var at = Eco.ClanLevelXp(lv);
                var nxt = Eco.ClanLevelXp(lv + 1);
                var xc = new CenterContainer();
                xc.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                head.AddChild(xc);
                var xr = UI.Row(xc, 6);
                xr.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                { var cm = xr.CustomMinimumSize; cm.x = 250; xr.CustomMinimumSize = cm; }
                if (nxt > 0)
                {
                    var b = UI2.Bar(xr, (double)(xp - at), (double)(nxt - at), Color.FromCode("#d9f99a"), Color.FromCode("#5bbf3a"), 10.0);
                    b.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
                    _NoteLabel(xr, GD.Fmt("%s / %s XP", _Thousands(xp - at), _Thousands(nxt - at)), 11, UI2.CREAM);
                }
                else
                    _NoteLabel(xr, GD.Fmt("MAX LEVEL  ·  %s XP", _Thousands(xp)), 11, UI2.GREEN);
            }
            // ---- clanmates calling for players (JOIN)
            var me_pid = GD.Str(social.me.Get("pid", ""));
            foreach (var call in c.Get("lfg", new GArray()))
            {
                var pid = GD.Str(call.Get("pid", ""));
                if (pid == me_pid || social.InMyParty(pid))
                    continue;
                var bc = new CenterContainer();
                bc.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                col.AddChild(bc);
                var pill = UI2.Frame(bc, "night", 6, 16.0, "green");
                var pr = UI.Row(pill, 8);
                UI2.Icon(pr, "horn", 26.0).SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
                _NoteLabel(pr, GD.Fmt("%s wants players  %d/%d", GD.Str(call.Get("n", "Player")), (int)call.Get("size", 1), (int)call.Get("max", 5)), 13, Color.WHITE);
                _Small(pr, "JOIN", "green", "clan_lfg_join_" + pid, () =>
                {
                    app.Sfx("confirm");
                    if (!social.LfgJoin(pid))
                        _Fail();
                }, 70.0);
            }
            var spacer = new Control();
            spacer.SizeFlagsVertical = Control.SIZE_EXPAND_FILL;
            spacer.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            col.AddChild(spacer);
            // ---- on the ground by the fire: the CLAN CHEST, the SHARD REQUESTS board
            var ground = UI.Row(col, 8);
            ground.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            if (hc)
                _Spot(ground, UI2.IconPath("castle"), "STARTER CLAN", "Players' clans fill a chest", -1.0, 0, "clan_open_starter", () => _OpenSheet("clan"));
            else
            {
                var pts = (int)c.Get("pts", 0);
                var tier = Eco.ClanTier(pts);
                var nxt_i = GD.Mini(tier, Eco.CLAN_CHEST_TIERS.Size() - 1);
                var need = (int)Eco.CLAN_CHEST_TIERS[nxt_i][0];
                var shown = Eco.ClanChestOf(GD.Maxi(1, tier));
                var line = tier < Eco.CLAN_CHEST_TIERS.Size() ? GD.Fmt("%s / %s pts", _Thousands(pts), _Thousands(need)) : GD.Fmt("%s pts  ·  ROYAL!", _Thousands(pts));
                var chest = _Spot(ground, Screens.ChestIcon(shown), "CLAN CHEST", line, (double)pts / (double)need, 0, "clan_open_chest", () => _OpenSheet("chest"));
                chest.SetMeta("clan_chest_tier", tier);
                if (tier == 0)
                    (chest.GetMeta("icon") as Control).Modulate = new Color(0.62, 0.62, 0.7, 0.9);
            }
            // ---- CHAT, MEMBERS, LEAGUE, CLAN between them (0.31.216, landscape: one row; a row of their own under it in
            // portrait)
            var med = UI.Row(ground, 6);
            med.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            med.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            med.SizeFlagsStretchRatio = 4.0;
            var others = c.Get("asks", new GArray()).A.Filter(a => GD.Str(a.Get("pid", "")) != me_pid);
            var can_give = others.Filter(a => app.profile.GiftableShards(GD.Str(a.Get("h", ""))) > 0).Size();
            GDict mine_ask = social.MyAsk();
            var sline = !mine_ask.IsEmpty() ? GD.Fmt("You asked: %s", _Hero(GD.Str(mine_ask["h"]))) : (!others.IsEmpty() ? GD.Fmt("%d open", others.Size()) : "Ask your clan");
            _Spot(ground, UI2.IconPath("scroll"), "SHARDS", sline, -1.0, can_give > 0 ? can_give : 0, "clan_open_shards", () => _OpenSheet("shards"));
            var unread = (int)social.unread.Get("clan", 0);
            _Medallion(med, "chat", "CHAT", unread, "clan_chat", () =>
            {
                app.Sfx("menuOpen");
                app.OpenChat("clan", "clan");
            });
            int req_n = social.IsClanOfficer() ? social.ClanRequests() : 0;
            _Medallion(med, "friends", "MEMBERS", req_n, "clan_open_members", () => _OpenSheet("members"),
                !hc ? GD.Fmt("%d/%d", (int)c.Get("n", 0), (int)c.Get("max", 30)) : GD.Fmt("%d", (int)c.Get("n", 0)));
            var rank = 0;
            GDict lg = social.league;
            if (!lg.IsEmpty() && !lg.Get("me", new GDict()).D.IsEmpty())
                rank = (int)lg["me"].Get("rank", 0);
            _Medallion(med, "trophy", "LEAGUE", 0, "clan_open_league", () => _OpenSheet("league"), rank > 0 ? GD.Fmt("#%d this week", rank) : "");
            _Medallion(med, "gear", "CLAN", 0, "clan_open_clan", () => _OpenSheet("clan"));
            // ---- LOOKING FOR GROUP
            _LfgPlaque(col);
            if (sheet != "")
                _OpenSheet(sheet, true);
        }

        public Button _Spot(Node parent, string icon_path, string title, string line, double frac, int badge, string key, Action cb)
        {
            // a place on the camp's ground that opens something: its picture, a soft glow under it, its name and a line (and a
            // bar when frac >= 0)
            var b = new Button();
            b.Flat = true;
            b.FocusMode = Control.FOCUS_NONE;
            foreach (var st_name in new[] { "normal", "hover", "focus", "hover_pressed" })
                b.AddThemeStyleboxOverride(st_name, new StyleBoxEmpty());
            var pressed = new StyleBoxFlat();
            pressed.BgColor = new Color(1, 1, 1, 0.08);
            pressed.SetCornerRadiusAll(14);
            b.AddThemeStyleboxOverride("pressed", pressed);
            b.CustomMinimumSize = new Vector2(150, 128);
            b.SetMeta("action_key", key);
            b.Pressed += () =>
            {
                app.Sfx("menuOpen");
                cb();
            };
            parent.AddChild(b);
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", 0);
            v.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            v.Alignment = BoxContainer.ALIGNMENT_END;
            v.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            b.AddChild(v);
            var ic_box = new Control();
            ic_box.CustomMinimumSize = new Vector2(0, 64);
            ic_box.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            v.AddChild(ic_box);
            UI2.Glow(ic_box, new Rect2(30, 6, 90, 70), new Color(1.0, 0.8, 0.45, 0.45));
            var ic = UI2.Img(ic_box, icon_path, 64.0);
            ic.Position = new Vector2(43, 0);
            b.SetMeta("icon", ic);
            if (badge > 0)
                UI2.Badge(ic, GD.Str(badge), new Vector2(8, -4));
            var t = UI2.Text(v, title, 15, Color.WHITE);
            t.HorizontalAlignment = HorizontalAlignment.Center;
            t.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            if (frac >= 0.0)
            {
                var bc = new MarginContainer();
                bc.AddThemeConstantOverride("margin_left", 22);
                bc.AddThemeConstantOverride("margin_right", 22);
                bc.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                v.AddChild(bc);
                UI2.Bar(bc, GD.Clampf(frac, 0.0, 1.0), 1.0, Color.FromCode("#ffe9a6"), Color.FromCode("#e09a2a"), 9.0);
            }
            var l = UI.Label(v, line, 11, UI2.CREAM, UI.HEAVY_FONT, true);
            l.HorizontalAlignment = HorizontalAlignment.Center;
            l.AutowrapMode = TextServer.AUTOWRAP_OFF;
            l.ClipText = true;
            l.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            return b;
        }

        public Button _Medallion(Node parent, string icon, string title, int badge, string key, Action cb, string sub = "")
        {
            // a round medallion standing in the camp: its icon on a plate (a badge for what waits), its name under it
            var b = new Button();
            b.Flat = true;
            b.FocusMode = Control.FOCUS_NONE;
            foreach (var st_name in new[] { "normal", "hover", "focus", "hover_pressed" })
                b.AddThemeStyleboxOverride(st_name, new StyleBoxEmpty());
            var pressed = new StyleBoxFlat();
            pressed.BgColor = new Color(1, 1, 1, 0.08);
            pressed.SetCornerRadiusAll(14);
            b.AddThemeStyleboxOverride("pressed", pressed);
            b.CustomMinimumSize = new Vector2(0, 92);
            b.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            b.SetMeta("action_key", key);
            b.Pressed += cb;
            parent.AddChild(b);
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", 2);
            v.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            v.Alignment = BoxContainer.ALIGNMENT_CENTER;
            v.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            b.AddChild(v);
            var cc = new CenterContainer();
            cc.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            v.AddChild(cc);
            var disc = new Control();
            disc.CustomMinimumSize = new Vector2(56, 56);
            disc.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            cc.AddChild(disc);
            UI2.Plate(disc, "royal", 28.0, "gold", new GDict { { "rim", 3.0 }, { "shadow_y", 4.0 } });
            var ic = UI2.Icon(disc, icon, 46.0);
            ic.Position = new Vector2(5, 4);
            if (badge > 0)
                UI2.Badge(disc, GD.Str(badge), new Vector2(6, -6));
            var t = UI2.Text(v, title, 13, Color.WHITE);
            t.HorizontalAlignment = HorizontalAlignment.Center;
            t.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            if (sub != "")
            {
                var sl = UI.Label(v, sub, 10, UI2.CREAM, UI.HEAVY_FONT, true);
                sl.HorizontalAlignment = HorizontalAlignment.Center;
                sl.AutowrapMode = TextServer.AUTOWRAP_OFF;
                sl.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            }
            return b;
        }

        public void _LfgPlaque(Node parent)
        {
            // LOOKING FOR GROUP: a call in clan chat clanmates JOIN (CANCEL while it's up); a party's member waits for its leader
            GDict mine = social.LfgCall(GD.Str(social.me.Get("pid", "")));
            if (!social.has_lfg)
            {
                var ob = UI2.Button(parent, "LFG COMES WITH THE SERVER UPDATE", "grey", () => { }, "clan_lfg", 15, 52.0);
                UI2.DimButton(ob, true);
                return;
            }
            if (!mine.IsEmpty())
            {
                var r = UI.Row(parent, 8);
                r.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                var cb = UI2.Button(r, GD.Fmt("CALLING YOUR CLAN  ·  %d/%d", (int)mine.Get("size", 1), (int)mine.Get("max", 5)), "green", () => { }, "clan_lfg_up", 17, 54.0, 16.0, UI2.IconPath("horn"));
                UI.Grow(cb);
                UI2.Pulse(cb, 0.02, 1.2);
                var xb = UI2.Button(r, "CANCEL", "ghost", () =>
                {
                    app.Sfx("tap");
                    if (!social.Lfg(false))
                        _Fail();
                }, "clan_lfg_cancel", 14, 54.0, 16.0);
                { var cm = xb.CustomMinimumSize; cm.x = 100; xb.CustomMinimumSize = cm; }
                return;
            }
            bool can = !social.InParty() || social.IsLeader();
            var lb = UI2.Button(parent, can ? "LOOKING FOR GROUP" : "YOUR PARTY'S LEADER CALLS", "green", () =>
            {
                if (!can)
                {
                    app.Sfx("error");
                    app.Toast("Only your party's leader can call for players", UI.MUTED);
                    return;
                }
                app.Sfx("confirm");
                if (!social.Lfg(true))
                    _Fail();
            }, "clan_lfg", 19, 56.0, 16.0, UI2.IconPath("horn"));
            UI2.DimButton(lb, !can);
        }

        public void _OpenSheet(string id, bool again = false)
        {
            // a sheet over the camp, from just under the clan's name to the bottom: its title, ✕, and what it holds
            if (!again)
                app.Sfx("menuOpen");
            sheet = id;
            var keep = 0;
            if (GD.IsInstanceValid(_scroll) && again)
                keep = _scroll.ScrollVertical;
            foreach (var ch in _sheet_layer.GetChildren())
            {
                _sheet_layer.RemoveChild(ch);
                ch.QueueFree();
            }
            var dim = new ColorRect();
            dim.Color = new Color(0, 0, 0, 0.45);
            dim.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            dim.GuiInput += (InputEvent ev) =>
            {
                if ((ev is InputEventMouseButton || ev is InputEventScreenTouch) && !ev.IsPressed())
                    _CloseSheet();
            };
            _sheet_layer.AddChild(dim);
            var mc = new MarginContainer();
            mc.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            mc.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            mc.AddThemeConstantOverride("margin_left", 8);
            mc.AddThemeConstantOverride("margin_right", 8);
            mc.AddThemeConstantOverride("margin_top", GD.Int(54.0 + (double)app.safe_top));     // (0.31.216: under the top row; under the name in portrait)
            mc.AddThemeConstantOverride("margin_bottom", 10);
            _sheet_layer.AddChild(mc);
            var body = UI2.Frame(mc, "night", 12, 20.0, "gold");
            body.AddThemeConstantOverride("separation", 8);
            var hr = UI.Row(body, 8);
            string title = GD.Str(new GDict { { "chest", "CLAN CHEST" }, { "shards", "SHARD REQUESTS" }, { "members", "MEMBERS" }, { "league", "CLAN LEAGUE" }, { "clan", "CLAN" } }.Get(id, "CLAN"));
            UI.Grow(UI2.Text(hr, title, 22, Color.WHITE));
            var xb = UI2.Button(hr, "✕", "ghost", () => _CloseSheet(), "clan_sheet_close", 18, 38.0, 12.0);
            { var cm = xb.CustomMinimumSize; cm.x = 46; xb.CustomMinimumSize = cm; }
            _scroll = new ScrollContainer();
            _scroll.SizeFlagsVertical = Control.SIZE_EXPAND_FILL;
            _scroll.HorizontalScrollMode = ScrollContainer.SCROLL_MODE_DISABLED;
            _scroll.ScrollDeadzone = 1000000;
            body.AddChild(_scroll);
            SetMeta("drag_scroll", _scroll);
            _list = new VBoxContainer();
            _list.AddThemeConstantOverride("separation", 10);
            _list.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            _scroll.AddChild(_list);
            GDict c = social.clan;
            var hc = (bool)c.Get("hc", false);
            string role = social.ClanRoleOfMe();
            switch (id)
            {
                case "chest":
                    _ChestSection(c);
                    break;
                case "shards":
                    _ShardSection(c);
                    break;
                case "members":
                    _MembersSheet(c, hc);
                    break;
                case "league":
                    _RenderLeague(c);
                    break;
                default:
                    _ClanSheet(c, hc, role);
                    break;
            }
            if (again)
            {
                var sc = _scroll;
                CallDeferred(() => sc.ScrollVertical = keep);
            }
        }

        public void _CloseSheet()
        {
            app.Sfx("menuClose");
            sheet = "";
            foreach (var ch in _sheet_layer.GetChildren())
            {
                _sheet_layer.RemoveChild(ch);
                ch.QueueFree();
            }
            _scroll = null;
            _list = null;
            if (HasMeta("drag_scroll"))
                RemoveMeta("drag_scroll");
        }

        public void _MembersSheet(GDict c, bool hc)
        {
            bool officer = social.IsClanOfficer();
            GArray req = c.Get("req", new GArray()).A;
            if (officer && !req.IsEmpty())
            {
                var rf = _Section("REQUESTS", GD.Str(req.Size()));
                foreach (var pv in req)
                {
                    GDict p = pv.D;
                    var r = _MemberRow(rf, p, "");
                    _NoteLabel(r, GD.Fmt("Lv %d", (int)p.Get("lv", 1)), 12, UI2.CYAN);
                    var pp = GD.Str(p["pid"]);
                    _Small(r, "ACCEPT", "green", "clan_accept_" + pp, () =>
                    {
                        app.Sfx("confirm");
                        if (!social.ClanAccept(pp))
                            _Fail();
                    }, 84.0);
                    _Small(r, "✕", "ghost", "clan_reject_" + pp, () =>
                    {
                        app.Sfx("tap");
                        social.ClanReject(pp);
                    }, 44.0);
                }
            }
            _RenderMembers(c, hc);
            if (officer)
            {
                var vf = _Section("INVITE A PLAYER");
                var vr = UI.Row(vf, 8);
                var ve = _Field(vr, "invite", "Their friend code", 12);
                ve.TextSubmitted += (_t) => _InviteCode();
                _Small(vr, "INVITE", "green", "clan_invite_code", () => _InviteCode(), 90.0);
                UI2.Body(vf, "Or tap a player's name anywhere (chat, friends, ranks) and choose INVITE TO CLAN.", 12, UI2.MUTED);
            }
        }

        public void _ClanSheet(GDict c, bool hc, string role)
        {
            // CLAN: who you are in it; the crest and settings (the leader and officers); a starter clan's way to a players'
            // clan; LEAVE / DISBAND
            bool officer = social.IsClanOfficer();
            var f = _Section("");
            var r = UI.Row(f, 10);
            SocialUI.Crest(r, GD.Str(c.Get("cc", "")), 54.0, GD.Str(c.Get("fr", "")));
            var tv = new VBoxContainer();
            tv.AddThemeConstantOverride("separation", 0);
            tv.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            r.AddChild(tv);
            var nl = UI2.Text(tv, GD.Fmt("[%s] %s", GD.Str(c.Get("tag", "")), GD.Str(c.Get("name", ""))), 17, Color.WHITE);
            nl.ClipText = true;
            var bits = GArray.Of(new GDict { { "leader", "You lead it" }, { "officer", "You're an officer" }, { "member", "You're a member" } }.Get(role, ""),
                GD.Fmt("%d / %d members", (int)c.Get("n", 0), (int)c.Get("max", 30)), GD.Str(JOIN_TEXT.Get(GD.Str(c.Get("join", "")), "")));
            if (hc)
                bits = GArray.Of("A starter clan", GD.Fmt("%d member%s", (int)c.Get("n", 0), (int)c.Get("n", 0) == 1 ? "" : "s"), "free, open to all");
            UI2.Body(tv, GStr.Join("  ·  ", bits), 12, UI2.SOFT);
            if (officer && !hc)
            {
                var sf = _Section("CREST & SETTINGS");
                var crr = UI.Row(sf, 10);
                SocialUI.Crest(crr, GD.Str(c.Get("cc", "")), 46.0, GD.Str(c.Get("fr", "")));
                UI.Grow(UI2.Button(crr, "CHANGE CREST", "purple", () => _EditCrest(Eco.CrestOfCode(GD.Str(c.Get("cc", "")))), "clan_crest_edit", 15, 42.0));
                _SettingsRows(sf, c);
            }
            if (hc)
            {
                var stf = _Section("STARTER CLAN");
                UI2.Body(stf, "Starter clans don't fill a Clan Chest or play in the League. Join a players' clan or start your own for a chest every week and League gems -- your shard requests and LFG work here too.", 12, UI2.SOFT);
                var nf = _Section("A CLAN OF YOUR OWN?");
                UI2.Body(nf, GD.Fmt("Join a players' clan or start your own any time: you move over from %s by itself.", GD.Str(c.Get("name", ""))), 12, UI2.MUTED);
                UI2.Button(nf, "START MY OWN CLAN", "gold", () =>
                {
                    app.Sfx("tab");
                    _ToStart();
                }, "clan_to_start", 14, 38.0);
                if (!_asked_list)
                {
                    _asked_list = true;
                    social.ClanFind("", "");
                }
                _FindSection(social.ClanCoolLeft());
                _RenderNew(social.ClanCoolLeft());
            }
            _LeaveSection(c, hc, role);
        }

        public void _ChestSection(GDict c)
        {
            // the CLAN CHEST: the week's points against its four tiers, mine, when the week ends; last week's result
            var pts = (int)c.Get("pts", 0);
            var tier = Eco.ClanTier(pts);
            var left = (long)c.Get("ends", 0) - GD.Long(Time.GetUnixTimeFromSystem());
            var f = _Section("CLAN CHEST", left > 0 ? (GD.Fmt("ENDS IN %s", UI.Duration((int)left))).ToUpperInvariant() : "");
            var top = UI.Row(f, 10);
            var shown = Eco.ClanChestOf(GD.Maxi(1, tier));
            var ci = UI2.Img(top, Screens.ChestIcon(shown), 64.0);
            ci.Modulate = tier > 0 ? Color.WHITE : new Color(0.55, 0.55, 0.62, 0.85);
            ci.SetMeta("clan_chest_icon", shown);
            var tv = new VBoxContainer();
            tv.AddThemeConstantOverride("separation", 2);
            tv.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            top.AddChild(tv);
            var head = tier > 0 ? GD.Fmt("%s REACHED", GD.Str(Eco.CHESTS[shown]["name"]).ToUpperInvariant()) : "NO CHEST YET";
            UI2.Text(tv, head, 16, tier > 0 ? (Color)TIER_COL.Get(shown, Color.WHITE) : UI2.SOFT);
            var nxt = tier + 1;
            if (nxt <= Eco.CLAN_CHEST_TIERS.Size())
            {
                var need = (int)Eco.CLAN_CHEST_TIERS[nxt - 1][0];
                UI2.Body(tv, GD.Fmt("%s / %s points to the %s", _Thousands(pts), _Thousands(need), GD.Str(Eco.CHESTS[GD.Str(Eco.CLAN_CHEST_TIERS[nxt - 1][1])]["name"])), 12, UI2.SOFT);
            }
            else
                UI2.Body(tv, GD.Fmt("%s points -- the best chest there is!", _Thousands(pts)), 12, UI2.GREEN);
            var top_pts = (double)Eco.CLAN_CHEST_TIERS[Eco.CLAN_CHEST_TIERS.Size() - 1][0];
            var bar = UI2.Bar(f, GD.Minf((double)pts, top_pts), top_pts, Color.FromCode("#ffe9a6"), Color.FromCode("#e09a2a"), 14.0);
            bar.SetMeta("clan_chest_bar", pts);
            // the tiers under the bar, each at its points
            var marks = new Control();
            marks.CustomMinimumSize = new Vector2(0, 30);
            marks.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            marks.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            f.AddChild(marks);
            for (int i = 0; i < Eco.CLAN_CHEST_TIERS.Size(); i++)
            {
                GArray t = Eco.CLAN_CHEST_TIERS[i].A;
                var lab = UI.Label(marks, GD.Fmt("%s\n%d", GD.Str(t[1]).ToUpperInvariant(), (int)t[0]), 9, tier > i ? (Color)TIER_COL.Get(GD.Str(t[1]), Color.WHITE) : UI2.MUTED, UI.HEAVY_FONT);
                lab.HorizontalAlignment = HorizontalAlignment.Center;
                lab.AutowrapMode = TextServer.AUTOWRAP_OFF;
                lab.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                var frac = (double)t[0] / top_pts;
                Action place = () =>
                {
                    lab.Size = lab.GetCombinedMinimumSize();
                    lab.Position = new Vector2(GD.Clampf(marks.Size.x * frac - lab.Size.x * 0.5, 0.0, marks.Size.x - lab.Size.x), 0.0);
                };
                marks.Resized += place;
                CallDeferred(place);
            }
            var mine = (int)c.Get("mine_pts", 0);
            var ok = mine >= Eco.CLAN_CHEST_MIN;
            {
                // (the .gd's first text has one %d for the two values: Godot's typed String % Array then prints a formatting
                // error and gives the text unformatted -- kept as it does)
                var fmt = ok ? "Your points this week: %d -- the chest is yours on Monday." : "Your points this week: %d -- earn %d to get the chest on Monday.";
                var txt = GFormat.Sprintf(fmt, new List<Var> { mine, Eco.CLAN_CHEST_MIN }, out bool bad);
                if (bad)
                {
                    GD.PushError("String formatting error: " + txt + ".");
                    txt = fmt;
                }
                UI2.Body(f, txt, 12, ok ? UI2.GREEN : UI2.SOFT);
            }
            UI2.Body(f, "Every online match earns points: a win 10, a draw 6, a loss 4, +2 a tower, +1 a KO. Doubled with a clanmate in your party!", 11, UI2.MUTED);
            GDict last = c.Get("last", new GDict()).D;
            if ((int)last.Get("pts", 0) > 0)
            {
                var bits = GArray.Of(GD.Fmt("%s points", _Thousands((int)last["pts"])));
                if (GD.Str(last.Get("chest", "")) != "")
                    bits.Append(GD.Str(Eco.CHESTS.Get(GD.Str(last["chest"]), new GDict()).Get("name", "")));
                bits.Append(GD.Fmt("League #%d%s", (int)last.Get("rank", 0), (int)last.Get("gems", 0) > 0 ? (GD.Fmt(" (+%d gems)", (int)last["gems"])) : ""));
                UI2.Body(f, "Last week: " + GStr.Join(",  ", bits), 12, UI2.CYAN);
            }
        }

        public void _ShardSection(GDict c)
        {
            var f = _Section("SHARD REQUESTS");
            var p = app.profile;
            var me_pid = GD.Str(social.me.Get("pid", ""));
            GDict mine = social.MyAsk();
            if (!mine.IsEmpty())
            {
                var r = UI.Row(f, 8);
                UI2.Img(r, GD.Fmt("res://assets/ui/skins/default_%s.png", GD.Str(mine["h"])), 40.0);
                UI.Grow(UI2.Body(r, GD.Fmt("You asked for a %s shard. A clanmate who has one can give it.", _Hero(GD.Str(mine["h"]))), 12, UI2.SOFT));
                _Small(r, "TAKE BACK", "ghost", "clan_shard_back", () =>
                {
                    app.Sfx("tap");
                    if (!social.ClanUnask())
                        _Fail();
                }, 96.0);
            }
            else
            {
                var wait = (long)c.Get("ask_next", 0) - GD.Long(Time.GetUnixTimeFromSystem());
                var ab = UI2.Button(f, wait <= 0 ? "ASK FOR A SHARD" : GD.Fmt("NEXT ASK IN %s", UI.Duration((int)wait).ToUpperInvariant()), "purple", () =>
                {
                    if (wait > 0)
                    {
                        app.Sfx("error");
                        app.Toast(GD.Fmt("You can ask again in %s", UI.Duration((int)wait)), UI.MUTED);
                        return;
                    }
                    _PickHero();
                }, "clan_shard_ask", 15, 42.0);
                UI2.DimButton(ab, wait > 0);
            }
            var others = c.Get("asks", new GArray()).A.Filter(a => GD.Str(a.Get("pid", "")) != me_pid);
            if (others.IsEmpty())
                UI2.Body(f, "Ask your clan for a shard of a hero you don't have yet; give clanmates the ones you hold and get their melt gold.", 11, UI2.MUTED);
            foreach (var a in others)
            {
                var h = GD.Str(a.Get("h", ""));
                var pid = GD.Str(a.Get("pid", ""));
                var r = UI.Row(f, 8);
                UI2.Img(r, GD.Fmt("res://assets/ui/skins/default_%s.png", h), 40.0);
                var tv = new VBoxContainer();
                tv.AddThemeConstantOverride("separation", -2);
                tv.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
                r.AddChild(tv);
                var nl = UI2.Text(tv, GD.Str(a.Get("n", "Player")), 14, Color.WHITE);
                nl.ClipText = true;
                UI2.Body(tv, GD.Fmt("needs a %s shard", _Hero(h)), 11, UI2.SOFT);
                bool have = p.GiftableShards(h) > 0;
                var gb = _Small(r, have ? (GD.Fmt("GIVE +%d", Eco.ShardMeltGold(h, p.Now()))) : "NO SHARD", have ? "green" : "grey", "clan_shard_give_" + pid, () =>
                {
                    if (!have)
                    {
                        app.Sfx("error");
                        app.Toast(GD.Fmt(p.ShardsOf(h) > 0 ? "Your %s shard was a clanmate's gift -- it can't be given on" : "You don't have a %s shard", _Hero(h)), UI.MUTED);
                        return;
                    }
                    app.Sfx("confirm");
                    if (!social.ClanGive(pid))
                        _Fail();
                }, 108.0);
                UI2.DimButton(gb, !have);
            }
        }

        public void _PickHero()
        {
            // ASK FOR A SHARD: the heroes this player doesn't own
            var v = _OpenOverlay("ASK FOR A SHARD");
            UI2.Center(UI2.Body(v, "Which hero? Your clan sees the request for 24 hours.", 12, UI2.SOFT));
            var g = new GridContainer();
            g.Columns = 3;
            g.AddThemeConstantOverride("h_separation", 8);
            g.AddThemeConstantOverride("v_separation", 8);
            v.AddChild(g);
            var n = 0;
            foreach (var h in Eco.HERO_PRICES)
            {
                var hid = GD.Str(h);
                if (app.profile.OwnsHero(hid))
                    continue;
                n += 1;
                var cell = new VBoxContainer();
                cell.AddThemeConstantOverride("separation", 2);
                cell.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
                g.AddChild(cell);
                var im = UI2.Img(cell, GD.Fmt("res://assets/ui/skins/default_%s.png", hid), 72.0);
                im.SizeFlagsHorizontal = Control.SIZE_SHRINK_CENTER;
                UI2.Button(cell, _Hero(hid).ToUpperInvariant(), "purple", () =>
                {
                    if (social.ClanAsk(hid))
                    {
                        app.Sfx("confirm");
                        _CloseOverlay();
                    }
                    else
                        _Fail();
                }, "clan_shard_" + hid, 11, 32.0, 9.0);
            }
            if (n == 0)
                UI2.Center(UI2.Body(v, "You have every hero already!", 13, UI2.GREEN));
            UI2.Button(v, "CLOSE", "ghost", () =>
            {
                app.Sfx("menuClose");
                _CloseOverlay();
            }, "clan_shard_close", 14, 36.0);
        }

        public static string _Hero(string hid)
        {
            return GD.Str(Screens.HERO_NAMES.Get(hid, hid.Capitalize()));
        }

        public void _SettingsRows(VBoxContainer sf, GDict c)
        {
            if (_set_join == "")
            {
                _set_join = GD.Str(c.Get("join", "open"));
                _set_lv = (int)c.Get("min_lv", 1);
            }
            UI2.Body(sf, "WHO MAY JOIN", 12, UI2.MUTED);
            var jr = UI.Row(sf, 6);
            foreach (var j in new[] { "open", "request", "invite" })
            {
                string jid = j;
                UI.Grow(UI2.Button(jr, GD.Str(new GDict { { "open", "OPEN" }, { "request", "REQUEST" }, { "invite", "INVITE" } }[jid]), _set_join == jid ? "gold" : "grey", () =>
                {
                    app.Sfx("tab");
                    _set_join = jid;
                    _dirty = true;
                }, "clan_set_join_" + jid, 13, 36.0, 10.0));
            }
            _LevelRow(sf, "LOWEST LEVEL", _set_lv, (int v) =>
            {
                _set_lv = v;
                _dirty = true;
            }, "clan_set_lv");
            bool changed = _set_join != GD.Str(c.Get("join", "")) || _set_lv != (int)c.Get("min_lv", 1);
            var sb = UI2.Button(sf, "SAVE SETTINGS", "green", () =>
            {
                if (social.ClanSet(_set_join, _set_lv))
                {
                    app.Sfx("confirm");
                    _set_join = "";
                }
                else
                    _Fail();
            }, "clan_set_save", 15, 42.0);
            UI2.DimButton(sb, !changed);
        }

        public void _LeaveSection(GDict c, bool hc, string role)
        {
            var lf = _Section("");
            var lr = UI.Row(lf, 8);
            var lb = UI2.Button(lr, "LEAVE CLAN", "red", () => { }, "clan_leave", 15, 42.0);
            UI.Grow(lb);
            _Armed(lb, "TAP AGAIN TO LEAVE", () =>
            {
                app.Sfx("menuClose");
                if (!social.ClanLeave())
                    _Fail();
            });
            if (role == "leader")
            {
                var db = UI2.Button(lr, "DISBAND", "grey", () => { }, "clan_disband", 15, 42.0);
                UI.Grow(db);
                _Armed(db, "SURE? ENDS IT FOR ALL", () =>
                {
                    app.Sfx("menuClose");
                    if (!social.ClanDisband())
                        _Fail();
                });
            }
            var note = "Leaving means waiting 24 hours before joining another clan.";
            if (hc)
                note = "Leaving a starter clan has no wait.";
            if (role == "leader")
                note += " If you leave, an officer takes over.";
            UI2.Body(lf, note, 12, UI2.MUTED);
        }

        public void _RenderMembers(GDict c, bool hc)
        {
            string role = social.ClanRoleOfMe();
            int shown = c.Get("members", new GArray()).Size();
            var mf = _Section("MEMBERS", !hc ? (GD.Fmt("%d / %d", (int)c.Get("n", 0), (int)c.Get("max", 30)))
                : (shown >= (int)c.Get("n", 0) ? GD.Fmt("%d", (int)c.Get("n", 0)) : GD.Fmt("%d SHOWN OF %d", shown, (int)c.Get("n", 0))));
            if (!hc)
                UI2.Body(mf, GD.Fmt("Points this week beside each name -- %d+ gets the Clan Chest.", Eco.CLAN_CHEST_MIN), 11, UI2.MUTED);
            foreach (var mv in c.Get("members", new GArray()))
            {
                GDict m = mv.D;
                var mrole = GD.Str(m.Get("role", "member"));
                var r = _MemberRow(mf, m, mrole);
                var mp = GD.Str(m["pid"]);
                if (!hc)
                {
                    var wp = (int)m.Get("wp", 0);
                    var pl = _NoteLabel(r, GD.Fmt("%d pts", wp), 12, wp >= Eco.CLAN_CHEST_MIN ? UI2.GREEN : UI2.MUTED);
                    { var cm = pl.CustomMinimumSize; cm.x = 52; pl.CustomMinimumSize = cm; }
                    pl.HorizontalAlignment = HorizontalAlignment.Right;
                }
                if (mp == GD.Str(social.me.Get("pid", "")))
                    _NoteLabel(r, "YOU", 12, UI2.GREEN);
                else if (role == "leader" || (role == "officer" && mrole == "member"))
                {
                    GDict mc = m.Duplicate();
                    _Small(r, "MANAGE", "blue", "clan_manage_" + mp, () => _Manage(mc), 92.0);
                }
            }
        }

        public void _RenderLeague(GDict c)
        {
            GDict lg = social.league;
            var now = Time.GetTicksMsec() / 1000.0;
            if ((lg.IsEmpty() || (double)social._clock - (double)lg.Get("_at", -999.0) > LEAGUE_STALE) && now - _league_asked > LEAGUE_STALE)
            {
                _league_asked = now;                      // (asked once in a while: the answer redraws the window)
                social.ClanLeague();
            }
            var left = (long)lg.Get("ends", c.Get("ends", 0)) - GD.Long(Time.GetUnixTimeFromSystem());
            var f = _Section("CLAN LEAGUE", left > 0 ? (GD.Fmt("ENDS IN %s", UI.Duration((int)left))).ToUpperInvariant() : "");
            UI2.Body(f, GD.Fmt("Clans ranked by this week's points. On Monday every member with %d+ points gets the prize:", Eco.CLAN_CHEST_MIN), 12, UI2.SOFT);
            var pr = UI.Row(f, 6);
            foreach (var p in Eco.CLAN_LEAGUE_PRIZES)
            {
                var rank = (int)p["from"] == (int)p["to"] ? GD.Fmt("#%d", (int)p["from"]) : GD.Fmt("#%d-%d", (int)p["from"], (int)p["to"]);
                Color col = (Color)FRAME_COL.Get(GD.Str(p["frame"]), UI2.SOFT);
                var chip = UI2.Chip(pr, GD.Fmt("%s  %d GEMS", rank, (int)p["gems"]), new Color(0.05, 0.07, 0.16, 0.9), col, col.Darkened(0.4));
                chip.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            }
            UI2.Body(f, "The top three wear a gold, silver or bronze frame round their crest all next week.", 11, UI2.MUTED);
            var tf = _Section("THIS WEEK", !lg.IsEmpty() ? GD.Fmt("%d CLANS", (int)lg.Get("clans", 0)) : "");
            GArray rows = lg.Get("list", new GArray()).A;
            if (lg.IsEmpty())
                UI2.Body(tf, "Loading...", 13, UI2.MUTED);
            else if (rows.IsEmpty())
                UI2.Body(tf, "No clan has points yet this week -- play an online match to put yours on top!", 13, UI2.MUTED);
            foreach (var row in rows)
                _LeagueRow(tf, row.D);
            GDict me_row = lg.Get("me", new GDict()).D;
            if (!lg.IsEmpty() && !(bool)c.Get("hc", false))
            {
                if (me_row.IsEmpty())
                    UI2.Body(tf, "Your clan: no points yet this week.", 12, UI2.SOFT);
                else if ((int)me_row.Get("rank", 0) > rows.Size())
                    _LeagueRow(tf, me_row);
            }
            GArray last = lg.Get("last", new GArray()).A;
            if (!last.IsEmpty())
            {
                var lf = _Section("LAST WEEK'S PODIUM");
                for (int i = 0; i < last.Size(); i++)
                {
                    GDict x = last[i].D;
                    var r = UI.Row(lf, 8);
                    _NoteLabel(r, GD.Fmt("#%d", i + 1), 15, (Color)FRAME_COL.Get(GD.Str(x.Get("fr", "")), Color.WHITE));
                    SocialUI.Crest(r, GD.Str(x.Get("cc", "")), 30.0, GD.Str(x.Get("fr", "")));
                    var nl = UI2.Text(r, GD.Fmt("[%s] %s", GD.Str(x.Get("tag", "")), GD.Str(x.Get("name", ""))), 14, Color.WHITE);
                    nl.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
                    nl.ClipText = true;
                    _NoteLabel(r, GD.Fmt("%s pts", _Thousands((int)x.Get("pts", 0))), 12, UI2.SOFT);
                }
            }
        }

        public void _LeagueRow(Node parent, GDict row)
        {
            var you = (bool)row.Get("you", false);
            var pc = new PanelContainer();
            var st = new StyleBoxFlat();
            st.BgColor = you ? new Color(0.1, 0.3, 0.12, 0.55) : new Color(0.0, 0.02, 0.08, 0.35);
            st.BorderColor = you ? new Color(0.55, 0.94, 0.66, 0.6) : new Color(0.5, 0.65, 0.95, 0.15);
            st.SetBorderWidthAll(1);
            st.SetCornerRadiusAll(10);
            st.ContentMarginLeft = 8;
            st.ContentMarginRight = 8;
            st.ContentMarginTop = 3;
            st.ContentMarginBottom = 3;
            pc.AddThemeStyleboxOverride("panel", st);
            pc.SetMeta("league_row", (int)row.Get("rank", 0));
            parent.AddChild(pc);
            var r = UI.Row(pc, 8);
            var rk = _NoteLabel(r, GD.Fmt("#%d", (int)row.Get("rank", 0)), 15, (int)row.Get("rank", 0) > 3 ? (Color)FRAME_COL.Get(GD.Str(row.Get("fr", "")), Color.WHITE) :
                (Color)FRAME_COL[GArray.Of("gold", "silver", "bronze")[(int)row.Get("rank", 1) - 1]]);
            { var cm = rk.CustomMinimumSize; cm.x = 34; rk.CustomMinimumSize = cm; }
            SocialUI.Crest(r, GD.Str(row.Get("cc", "")), 30.0, GD.Str(row.Get("fr", "")));
            var tv = new VBoxContainer();
            tv.AddThemeConstantOverride("separation", -3);
            tv.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            r.AddChild(tv);
            var nl = UI2.Text(tv, GD.Fmt("[%s] %s", GD.Str(row.Get("tag", "")), GD.Str(row.Get("name", ""))), 14, you ? SocialUI.NAME_ME : Color.WHITE);
            nl.ClipText = true;
            var sl = UI.Label(tv, GD.Fmt("Level %d  ·  %d members", (int)row.Get("lv", 1), (int)row.Get("n", 0)), 10, UI2.MUTED, UI.HEAVY_FONT);
            sl.AutowrapMode = TextServer.AUTOWRAP_OFF;
            _NoteLabel(r, GD.Fmt("%s pts", _Thousands((int)row.Get("pts", 0))), 13, UI2.CREAM);
        }

        // ---------------- in a clan, an older server (0.31.134-0.31.195) ----------------
        public void _RenderMineOld()
        {
            GDict c = social.clan;
            var house = GD.Str(c.Get("house", ""));
            string role = social.ClanRoleOfMe();
            bool officer = social.IsClanOfficer();
            var hc = (bool)c.Get("hc", false);
            var bf = _Section("", "", SocialUI.HouseRim(house));
            var tr = UI.Row(bf, 10);
            var ic = UI2.Icon(tr, "banner", 54.0);
            ic.Modulate = SocialUI.HouseColor(house).Lightened(0.15);
            ic.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            var tv = new VBoxContainer();
            tv.AddThemeConstantOverride("separation", -2);
            tv.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            tr.AddChild(tv);
            var nl = UI2.Text(tv, GD.Str(c.Get("name", "")), 22, Color.WHITE);
            nl.ClipText = true;
            var hl = UI2.Text(tv, GD.Fmt("[%s]  ·  HOUSE %s", GD.Str(c.Get("tag", "")), SocialUI.HouseName(house).ToUpperInvariant()), 14, SocialUI.HouseColor(house));
            hl.ClipText = true;
            UI2.Body(bf, "The clan camp, crest, Clan Chest, League, shard requests and LFG arrive with the next server update.", 12, UI2.MUTED);
            var cr = UI.Row(bf, 8);
            var n = (int)social.unread.Get("clan", 0);
            UI.Grow(UI2.Button(cr, "CLAN CHAT" + (n > 0 ? GD.Fmt("  (%d)", n) : ""), "orange", () =>
            {
                app.Sfx("menuOpen");
                app.OpenChat("clan");
            }, "clan_chat", 16, 44.0));
            GArray req = c.Get("req", new GArray()).A;
            if (officer && !req.IsEmpty())
            {
                var rf = _Section("REQUESTS", GD.Str(req.Size()));
                foreach (var pv in req)
                {
                    GDict p = pv.D;
                    var r = _MemberRow(rf, p, "");
                    var pp = GD.Str(p["pid"]);
                    _Small(r, "ACCEPT", "green", "clan_accept_" + pp, () =>
                    {
                        app.Sfx("confirm");
                        if (!social.ClanAccept(pp))
                            _Fail();
                    }, 84.0);
                    _Small(r, "✕", "ghost", "clan_reject_" + pp, () =>
                    {
                        app.Sfx("tap");
                        social.ClanReject(pp);
                    }, 44.0);
                }
            }
            if (officer)
            {
                var vf = _Section("INVITE A PLAYER");
                var vr = UI.Row(vf, 8);
                var ve = _Field(vr, "invite", "Their friend code", 12);
                ve.TextSubmitted += (_t) => _InviteCode();
                _Small(vr, "INVITE", "green", "clan_invite_code", () => _InviteCode(), 90.0);
            }
            _RenderMembers(c, hc);
            if (officer)
                _SettingsRows(_Section("SETTINGS"), c);
            _LeaveSection(c, hc, role);
        }

        // ---------------- members ----------------
        public HBoxContainer _MemberRow(Node parent, GDict m, string role)
        {
            var r = UI.Row(parent, 8);
            SocialUI.Dot(r, GD.Str(m.Get("st", "offline")));
            var nb = new Button();
            nb.Flat = true;
            nb.FocusMode = Control.FOCUS_NONE;
            nb.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            nb.ClipText = true;
            nb.CustomMinimumSize = new Vector2(0, 44);
            foreach (var st_name in new[] { "normal", "hover", "pressed", "focus", "hover_pressed" })
                nb.AddThemeStyleboxOverride(st_name, new StyleBoxEmpty());
            nb.SetMeta("action_key", "clan_member_" + GD.Str(m.Get("pid", "")));
            var card = m.Duplicate();
            nb.Pressed += () => SocialUI.NameCard(app, this, card);
            r.AddChild(nb);
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", -2);
            v.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            v.Alignment = BoxContainer.ALIGNMENT_CENTER;
            v.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            nb.AddChild(v);
            var top = UI.Row(v, 6);
            top.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            if (role == "leader")
                UI2.Icon(top, "crown", 18.0).SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            UI2.Text(top, GD.Str(m.Get("n", "Player")), 15, Color.WHITE);
            if (role == "officer")
                _NoteLabel(top, "OFFICER", 11, UI2.CYAN);
            else
                SocialUI.TitleLabel(top, GD.Str(m.Get("tt", "")), 11);
            if (m.Has("st"))
            {
                var sl = UI.Label(v, SocialUI.StatusText(m), 11, ((Color)SocialUI.ST_COL.Get(GD.Str(m.Get("st", "offline")), UI2.MUTED)).Lightened(0.25), UI.HEAVY_FONT);
                sl.AutowrapMode = TextServer.AUTOWRAP_OFF;
                sl.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            }
            return r;
        }

        public void _InviteCode()
        {
            if (!GD.IsInstanceValid(_fields.Get("invite")))
                return;
            var t = _fields["invite"].As<LineEdit>().Text.StripEdges().Replace("#", "").Replace(" ", "").ToLowerInvariant();
            if (t.Length != 10 || !t.IsValidHexNumber())
            {
                app.Sfx("error");
                app.Toast("A friend code is 10 letters and numbers (like 3FA21C9B0D)", UI.RED);
                return;
            }
            if (social.ClanInvite(t))
            {
                app.Sfx("confirm");
                _typed.Erase("invite");
                _fields["invite"].As<LineEdit>().Text = "";
            }
            else
                _Fail();
        }

        public void _Manage(GDict m)
        {
            // what the leader (or an officer, for members) can do with one member
            var v = _OpenOverlay(GD.Str(m.Get("n", "Player")), 320.0);
            var pid = GD.Str(m.Get("pid", ""));
            var role = GD.Str(m.Get("role", "member"));
            string mine = social.ClanRoleOfMe();
            UI2.Center(UI2.Body(v, GD.Str(new GDict { { "officer", "Officer" }, { "member", "Member" } }.Get(role, "")), 13, UI2.MUTED));
            Action<bool> done = (bool ok) =>
            {
                if (!ok)
                    _Fail();
                _CloseOverlay();
            };
            if (mine == "leader")
            {
                if (role == "member")
                {
                    UI2.Button(v, "MAKE OFFICER", "blue", () =>
                    {
                        app.Sfx("confirm");
                        done(social.ClanRole(pid, "officer"));
                    }, "clan_m_officer", 15, 42.0);
                }
                else
                {
                    UI2.Button(v, "MAKE MEMBER", "blue", () =>
                    {
                        app.Sfx("tap");
                        done(social.ClanRole(pid, "member"));
                    }, "clan_m_member", 15, 42.0);
                }
                var lb = UI2.Button(v, "MAKE LEADER", "gold", () => { }, "clan_m_lead", 15, 42.0);
                _Armed(lb, "SURE? THEY LEAD", () =>
                {
                    app.Sfx("confirm");
                    done(social.ClanLead(pid));
                });
            }
            var kb = UI2.Button(v, "REMOVE FROM CLAN", "red", () => { }, "clan_m_kick", 15, 42.0);
            _Armed(kb, "TAP AGAIN TO REMOVE", () =>
            {
                app.Sfx("menuClose");
                done(social.ClanKick(pid));
            });
            UI2.Button(v, "CLOSE", "ghost", () =>
            {
                app.Sfx("menuClose");
                _CloseOverlay();
            }, "clan_m_close", 14, 36.0);
        }

        // ---------------- text ----------------
        public static string _Hours(int secs)
        {
            var h = GD.Int(Math.Ceiling(secs / 3600.0));
            return GD.Fmt("%d hour%s", h, h == 1 ? "" : "s");
        }

        public static string _Thousands(int n)
        {
            var s = GD.Str(GD.Absi(n));
            var @out = "";
            while (s.Length > 3)
            {
                @out = "," + s.Right(3) + @out;
                s = s.Left(s.Length - 3);
            }
            return (n < 0 ? "-" : "") + s + @out;
        }
    }
}
