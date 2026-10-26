// Ported from godot/scripts/app/friends_panel.gd (Fatebound 0.31.222).
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
    // 0.31.111 (Kevin: "players can ... add friend to a friends list. They can then group up and form a party"): the
    // Friends window. Your friend code (and adding someone by theirs), your party (leader's crown, KICK, LEAVE, PLAY
    // TOGETHER), party invites and friend requests waiting, your friends -- online first, each with INVITE -- the requests
    // you've sent and the players you've blocked. Redrawn whenever scripts/meta/social.gd changes.
    public class FriendsPanel : Control
    {
        public SiegeApp app;
        public Social social;
        public VBoxContainer _list;
        public ScrollContainer _scroll;
        public LineEdit _code;
        public LineEdit _ref;                 // 0.31.120: the code of the friend who invited you
        public bool _ref_busy = false;
        public bool _dirty = false;

        public void Open(SiegeApp a)
        {
            app = a;
            social = a.social;
            var w = SocialUI.Window(this, "FRIENDS", "friends", () =>
            {
                app.Sfx("menuClose");
                app.CloseModal();
            }, 56.0 + (double)app.safe_top, 24.0);
            VBoxContainer body = w["body"].As<VBoxContainer>();
            SocialUI.SocialTabs(body, app, "friends");              // 0.31.134: FRIENDS | CLAN
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
            social.Changed += _OnChanged;
            _Render();
        }

        public void RefChanged()
        {
            // (siege_app.redeem_code: the server answered)
            _ref_busy = false;
            _dirty = true;
        }

        public void _OnChanged(string what)
        {
            if (GArray.Of("friends", "party", "state", "me", "clan").Has(what))
                _dirty = true;
        }

        protected override void _Process(double _delta)
        {
            if (_dirty)
            {
                _dirty = false;
                var keep = _scroll.ScrollVertical;
                var typed = GD.IsInstanceValid(_code) ? _code.Text : "";
                var typed_ref = GD.IsInstanceValid(_ref) ? _ref.Text : "";
                _Render();
                if (GD.IsInstanceValid(_code))
                    _code.Text = typed;
                if (GD.IsInstanceValid(_ref))
                    _ref.Text = typed_ref;
                _scroll.CallDeferred(() => _scroll.ScrollVertical = keep);
            }
        }

        public VBoxContainer _Section(string title, string sub = "")
        {
            var f = UI2.Frame(_list, "glass", 10, 16.0);
            f.AddThemeConstantOverride("separation", 6);
            var h = UI.Row(f, 8);
            UI.Grow(UI2.Text(h, title, 17, UI2.GOLD));
            if (sub != "")
            {
                var s = UI.Label(h, sub, 12, UI2.MUTED, UI.HEAVY_FONT);
                s.AutowrapMode = TextServer.AUTOWRAP_OFF;
                s.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            }
            return f;
        }

        public HBoxContainer _Person(Node parent, GDict c, bool crown = false)
        {
            // a row: status dot, the name (tap: its card), title, status line; buttons go on the end
            var r = UI.Row(parent, 8);
            SocialUI.Dot(r, GD.Str(c.Get("st", "offline")));
            var nb = new Button();
            nb.Flat = true;
            nb.FocusMode = Control.FOCUS_NONE;
            nb.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            nb.Alignment = HorizontalAlignment.Left;
            nb.ClipText = true;
            nb.ClipContents = true;                  // (0.31.213: a long name, tag and title are cut at the row's end, not drawn over its buttons)
            nb.CustomMinimumSize = new Vector2(0, 44);
            foreach (var st_name in new[] { "normal", "hover", "pressed", "focus", "hover_pressed" })
                nb.AddThemeStyleboxOverride(st_name, new StyleBoxEmpty());
            nb.SetMeta("action_key", "friend_" + GD.Str(c.Get("pid", "")));
            var card = c.Duplicate();
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
            if (crown)
                UI2.Icon(top, "crown", 18.0).SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            UI2.Text(top, GD.Str(c.Get("n", "Player")), 15, Color.WHITE);
            if (GD.Str(c.Get("ct", "")) != "")
            {
                SocialUI.Crest(top, GD.Str(c.Get("cc", "")), 18.0);            // 0.31.196: their clan's crest
                // 0.31.134; 0.31.213 (Kevin's screenshot: "[LION]" down the row a letter a line, pushing the name out of the box):
                // one line -- a wrapping label in a row is squeezed to nothing and wraps at every letter
                var ctl = UI.Label(top, GD.Fmt("[%s]", GD.Str(c["ct"])), 12, UI2.SOFT, UI.HEAVY_FONT);
                ctl.AutowrapMode = TextServer.AUTOWRAP_OFF;
                ctl.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            }
            SocialUI.TitleLabel(top, GD.Str(c.Get("tt", "")), 11);
            var sl = UI.Label(v, SocialUI.StatusText(c), 11, ((Color)SocialUI.ST_COL.Get(GD.Str(c.Get("st", "offline")), UI2.MUTED)).Lightened(0.25), UI.HEAVY_FONT);
            sl.AutowrapMode = TextServer.AUTOWRAP_OFF;
            sl.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            return r;
        }

        public Button _Small(Node parent, string text, string color, string key, Action cb, double w = 78.0)
        {
            var b = UI2.Button(parent, text, color, cb, key, 13, 36.0, 11.0);
            var bm = b.CustomMinimumSize;
            bm.x = (float)w;
            b.CustomMinimumSize = bm;
            b.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            return b;
        }

        public Label _Tag(Node parent, string text, Color col)
        {
            var l = UI.Label(parent, text, 12, col, UI.HEAVY_FONT);
            l.AutowrapMode = TextServer.AUTOWRAP_OFF;
            l.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            return l;
        }

        public void _Fail()
        {
            app.Sfx("error");
            app.Toast("Not connected to the server right now", UI.RED);
        }

        public void _Render()
        {
            foreach (var c in _list.GetChildren())
            {
                _list.RemoveChild(c);
                c.QueueFree();
            }
            // ---- not connected
            if (!social.Online())
            {
                var f = _Section("NOT CONNECTED");
                var why = "Friends and parties need the game's server. Trying again shortly...";
                if (!social.HasAccount())
                    why = "Friends and parties start once you've been online with the game's server.";
                else if (GD.Str(social.state) == "old")
                    why = "Friends and parties arrive with the next server update.";
                else if (GD.Str(social.state) == "connecting")
                    why = "Connecting...";
                UI2.Body(f, why, 13, UI2.SOFT);
                return;
            }
            // ---- your code / add by code
            var cf = _Section("YOUR FRIEND CODE");
            var cr = UI.Row(cf, 8);
            var code = UI2.Text(cr, Social.CodeOf(GD.Str(social.me.Get("pid", ""))), 22, Color.WHITE);
            code.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            _Small(cr, "COPY", "blue", "friend_code_copy", () =>
            {
                DisplayServer.ClipboardSet(Social.CodeOf(GD.Str(social.me["pid"])));
                app.Sfx("confirm");
                app.Toast("Friend code copied -- send it to a friend", UI.CYAN);
            });
            var ar = UI.Row(cf, 8);
            _code = SocialUI.Field(ar, "A friend's code", 12);
            _code.TextSubmitted += (string _t) => _AddCode();
            _Small(ar, "ADD", "green", "friend_code_add", () => _AddCode());
            _InviteSection();
            // ---- the party
            if (social.InParty())
            {
                GDict p = social.party;
                var pf = _Section("YOUR PARTY", GD.Fmt("%d / %d", social.PartySize(), (int)p.Get("max", 4)));
                foreach (var m in p.Get("members", new GArray()))
                {
                    bool me = GD.Str(m["pid"]) == GD.Str(social.me["pid"]);
                    var r = _Person(pf, m.D, GD.Str(m["pid"]) == GD.Str(p["leader"]));
                    if (me)
                        _Tag(r, "YOU", UI2.GOLD);
                    else if (social.IsLeader())
                    {
                        var mp = GD.Str(m["pid"]);
                        _Small(r, "KICK", "red", "party_kick_" + mp, () =>
                        {
                            app.Sfx("menuClose");
                            if (!social.Kick(mp))
                                _Fail();
                        }, 66.0);
                    }
                }
                foreach (var m in p.Get("pending", new GArray()))
                {
                    var r2 = _Person(pf, m.D);
                    _Tag(r2, "INVITED", UI2.MUTED);
                }
                UI2.Body(pf, "Your party plays the same match, on one side -- five of you are the whole team. With clanmates, double clan points.", 12, UI2.MUTED);
                var br = UI.Row(pf, 8);
                if (social.IsLeader())
                {
                    // the leader's PLAY (the party follows once matches are online again)
                    UI.Grow(UI2.Button(br, "PLAY TOGETHER", "orange", () =>
                    {
                        app.CloseModal();
                        app.Play();
                    }, "party_play", 17, 46.0));
                }
                else
                {
                    var wait = UI2.Button(br, "LEADER STARTS", "grey", () => { }, "party_wait", 15, 46.0);
                    UI.Grow(wait);
                    UI2.DimButton(wait, true);
                }
                var lb = UI2.Button(br, "LEAVE", "red", () =>
                {
                    app.Sfx("menuClose");
                    if (!social.Leave())
                        _Fail();
                }, "party_leave", 15, 46.0);
                var lm = lb.CustomMinimumSize;
                lm.x = 96;
                lb.CustomMinimumSize = lm;
            }
            // ---- invites and requests waiting
            if (!social.invites.IsEmpty())
            {
                var inf = _Section("PARTY INVITES");
                foreach (var pa in social.invites)
                {
                    GDict from = social.invites[pa]["from"].D;
                    var r = _Person(inf, from);
                    string pid_pa = GD.Str(pa);
                    _Small(r, "JOIN", "green", "invite_join", () =>
                    {
                        app.Sfx("confirm");
                        if (!social.Join(pid_pa))
                            _Fail();
                    }, 70.0);
                    _Small(r, "✕", "ghost", "invite_no", () =>
                    {
                        app.Sfx("tap");
                        social.NoJoin(pid_pa);
                    }, 44.0);
                }
            }
            if (!social.rin.IsEmpty())
            {
                var rf = _Section("FRIEND REQUESTS", GD.Str(social.rin.Size()));
                foreach (var c in social.rin)
                {
                    var r = _Person(rf, c.D);
                    var cp = GD.Str(c["pid"]);
                    _Small(r, "ACCEPT", "green", "req_accept_" + cp, () =>
                    {
                        app.Sfx("confirm");
                        if (!social.Add(cp))
                            _Fail();
                    }, 84.0);
                    _Small(r, "✕", "ghost", "req_decline_" + cp, () =>
                    {
                        app.Sfx("tap");
                        social.Decline(cp);
                    }, 44.0);
                }
            }
            // ---- friends, online first
            var ff = _Section("FRIENDS", GD.Fmt("%d", social.friends.Size()));
            if (social.friends.IsEmpty())
                UI2.Body(ff, "No friends yet. Tap a name in the chat to add them, or trade friend codes.", 13, UI2.SOFT);
            var order = GDict.Of("online", 0, "match", 1, "offline", 2);
            GArray fl = social.friends.Duplicate();
            fl.SortCustom((a, b) =>
            {
                var oa = (int)order.Get(GD.Str(a["st"]), 3);
                var ob = (int)order.Get(GD.Str(b["st"]), 3);
                return oa != ob ? oa < ob : GD.Str(a["n"]).NocasecmpTo(GD.Str(b["n"])) < 0;
            });
            bool full = social.InParty() && social.PartySize() + social.party.Get("pending", new GArray()).Size() >= (int)social.party.Get("max", 4);
            foreach (var c in fl)
            {
                var r = _Person(ff, c.D);
                var cp = GD.Str(c["pid"]);
                if (social.InMyParty(cp))
                    _Tag(r, "IN PARTY", UI2.GOLD);
                else if (GD.Str(c["st"]) == "online" && !full)
                {
                    _Small(r, "INVITE", "orange", "friend_invite_" + cp, () =>
                    {
                        app.Sfx("confirm");
                        if (!social.Invite(cp))
                            _Fail();
                    }, 80.0);
                }
                else if (social.CanJoin(c.D))
                {
                    _Small(r, "JOIN", "green", "friend_join_" + cp, () =>      // 0.31.120: into their match
                    {
                        app.Sfx("confirm");
                        app.JoinFriend(cp);
                    }, 80.0);
                }
                else if (GD.Str(c["st"]) == "match")
                    _Tag(r, "PLAYING", UI2.MUTED);                 // 0.31.209: their match has started -- no joining it midway
            }
            // ---- 0.31.196: clanmates online who aren't friends -- they can be invited too (a party of 5)
            if (social.has_lfg && social.InClan())
            {
                var mates = new GArray();
                foreach (var m in social.clan.Get("members", new GArray()))
                {
                    string rel = social.Relation(GD.Str(m.Get("pid", "")));
                    if (GD.Str(m.Get("st", "")) == "online" && rel != "me" && rel != "friend" && rel != "blocked")
                        mates.Append(m);
                }
                if (!mates.IsEmpty())
                {
                    var mf = _Section("CLANMATES ONLINE", GD.Fmt("%d", mates.Size()));
                    foreach (var c in mates.Slice(0, 12))
                    {
                        var r = _Person(mf, c.D);
                        var cp = GD.Str(c["pid"]);
                        if (social.InMyParty(cp))
                            _Tag(r, "IN PARTY", UI2.GREEN);
                        else if (!full)
                        {
                            _Small(r, "INVITE", "orange", "clanmate_invite_" + cp, () =>
                            {
                                app.Sfx("confirm");
                                if (!social.Invite(cp))
                                    _Fail();
                            }, 80.0);
                        }
                    }
                }
            }
            // ---- sent, blocked
            if (!social.rout.IsEmpty())
            {
                var sf = _Section("REQUESTS SENT", GD.Str(social.rout.Size()));
                foreach (var c in social.rout)
                {
                    var r = _Person(sf, c.D);
                    var cp = GD.Str(c["pid"]);
                    _Small(r, "CANCEL", "ghost", "req_cancel_" + cp, () =>
                    {
                        app.Sfx("tap");
                        social.Unfriend(cp);
                    }, 80.0);
                }
            }
            if (!social.blocked.IsEmpty())
            {
                var bf = _Section("BLOCKED", GD.Str(social.blocked.Size()));
                foreach (var c in social.blocked)
                {
                    var r = UI.Row(bf, 8);
                    var n = UI2.Text(r, GD.Str(c["n"]), 14, UI2.SOFT);
                    n.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
                    var cp = GD.Str(c["pid"]);
                    _Small(r, "UNBLOCK", "blue", "unblock_" + cp, () =>
                    {
                        app.Sfx("tap");
                        social.Unblock(cp);
                    }, 90.0);
                }
            }
        }

        public void _AddCode()
        {
            var t = _code.Text.StripEdges().Replace("#", "").Replace(" ", "").ToLowerInvariant();
            if (t.Length != 10 || !t.IsValidHexNumber())
            {
                app.Sfx("error");
                app.Toast("A friend code is 10 letters and numbers (like 3FA21C9B0D)", UI.RED);
                return;
            }
            if (t == GD.Str(social.me.Get("pid", "")))
            {
                app.Sfx("error");
                app.Toast("That's your own code", UI.MUTED);
                return;
            }
            if (social.Add(t))
            {
                app.Sfx("confirm");
                _code.Text = "";
            }
            else
                _Fail();
        }

        // ---------------- invite friends (0.31.120, Kevin: referral codes) ----------------
        public void _InviteSection()
        {
            GDict p = app.profile.d;
            GDict @ref = p.Get("referral", new GDict()).D;
            var f = _Section("INVITE FRIENDS");
            UI2.Body(f, GD.Fmt("A new player who enters your friend code gets a Gold Chest at level %d -- and so do you.", Eco.REF_LEVEL), 13, UI2.SOFT);
            var mine = @ref.Get("notes", new GArray()).A.Filter(n => GD.Str(n.Get("kind", "")) == "friend").Size();
            if (mine > 0)
            {
                var l = UI.Label(f, GD.Fmt("Friends who reached level %d with your code: %d", Eco.REF_LEVEL, mine), 12, UI2.GOLD, UI.HEAVY_FONT);
                l.AutowrapMode = TextServer.AUTOWRAP_OFF;
            }
            var by = GD.Str(@ref.Get("by", ""));
            if (by != "")
            {
                var got = @ref.Get("notes", new GArray()).A.Any(n => GD.Str(n.Get("kind", "")) == "joined");
                UI2.Body(f, GD.Fmt("You joined with %s's code.", by) + (got ? "" : GD.Fmt(" Reach level %d for your Gold Chest!", Eco.REF_LEVEL)), 13, UI2.GOLD);
            }
            else if ((int)p.Get("level", 1) < Eco.REF_LEVEL && !(bool)p.Get("settings", new GDict()).Get("ref_late", false))
            {
                var rr = UI.Row(f, 8);
                _ref = SocialUI.Field(rr, "Invited? Their code", 12);
                _ref.TextSubmitted += (string _t) => _Redeem();
                var b = _Small(rr, "REDEEM", "orange", "ref_redeem", () => _Redeem(), 96.0);
                if (_ref_busy)
                    UI2.DimButton(b, true);
            }
        }

        public void _Redeem()
        {
            if (_ref_busy || !GD.IsInstanceValid(_ref))
                return;
            var t = _ref.Text.StripEdges().Replace("#", "").Replace(" ", "").ToLowerInvariant();
            if (t.Length != 10 || !t.IsValidHexNumber())
            {
                app.Sfx("error");
                app.Toast("A friend code is 10 letters and numbers (like 3FA21C9B0D)", UI.RED);
                return;
            }
            if (t == GD.Str(social.me.Get("pid", "")))
            {
                app.Sfx("error");
                app.Toast("That's your own code", UI.MUTED);
                return;
            }
            _ref_busy = true;
            app.Sfx("tap");
            app.RedeemCode(t);
            _dirty = true;
        }
    }
}
