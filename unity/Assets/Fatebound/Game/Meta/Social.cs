// Ported from godot/scripts/meta/social.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Net = Fatebound.Game.SiegeNet;

namespace Fatebound.Game
{
    // 0.31.111 (Kevin: "Build a global chat and players can click a name and have option to add friend to a friends list.
    // They can then group up and form a party"): the phone's social side -- one WebSocket to the Siege server while the
    // app is up (server/social.gd is the other end and has the rules). It needs the account (eco_sync.gd): without one, or
    // against a server older than 0.31.111 (it never answers "hi"), it stays off and the screens say so.
    // The app sets `want` (in front, account ready); this keeps the connection, retrying with a growing wait, and holds
    // what the screens show: the chat lines, friends, requests, the party and invites. Every change emits `changed`.
    // 0.31.134: clans (server/clans.gd) -- the player's clan, invites, search results, a clan's card, and the "clan" chat
    // channel; cards and lines carry "ct", a player's clan tag. "me" says "clans":1 when the server has them. (0.31.169:
    // Crown War's war map -- its battles were Siege matches -- went with Siege.)
    // 0.31.196 (Kevin: "Do clan chest, clan camp, crest, shard requests, 5 - stack, lfg button, league"): a clan's crest ("cc"
    // on cards and lines, "cr" on the clan), its level, the week's points and Clan Chest, last week, the shard requests
    // ("asks") and LFG calls ("lfg") in the clan's state ("cv": 2 -- an older server has none of it); the League table
    // (clan_league); a party of 5. {"k":"eco"}: the server changed this account (a Clan Chest, a shard) -- `pull` it.
    public class Social : Node
    {
        public event Action<string> Changed;            // "state", "me", "chat", "friends", "party", "prof" (0.31.120), "clan", "clans", "clan_info" (0.31.134)
        public event Action<string, bool, bool> Note;
        public event Action<GDict> Request;             // someone wants to be friends
        public event Action<string, GDict> Invited;
        public event Action<string, string> Go;         // the party leader started a match
        public event Action<GDict, GDict> ClanInvited;  // 0.31.134: an officer of a clan invited this player
        public event Action<bool, string> ClanMade;     // 0.31.134: the answer to clan_new (ok: the gold was taken)
        public event Action Pull;                       // 0.31.196: the server changed this account: fetch it (eco_sync)

        public static readonly GArray RETRY = GArray.Of(2.0, 5.0, 10.0, 20.0, 40.0, 60.0);
        public const double OLD_SERVER_RETRY = 600.0;         // s before asking a server that never answered "hi" again
        public const double HI_TIMEOUT = 8.0;
        public const int KEEP = 50;                           // lines kept a channel (0.31.140: as the server keeps; was 100)
        public const double INVITE_LIFE = 60.0;

        public string url = OS.HasEnvironment("SIEGE_URL") ? OS.GetEnvironment("SIEGE_URL") : Net.DEFAULT_URL;
        public Profile profile;
        public bool want = false;
        public string state = "off";                          // off / connecting / online / old (no social side on the server)
        public GDict me = new GDict();                        // {"pid", "n", "tt", "max"}
        public GDict lines = new GDict { { "global", new GArray() }, { "party", new GArray() }, { "clan", new GArray() } };
        public GDict unread = new GDict { { "global", 0 }, { "party", 0 }, { "clan", 0 } };
        public string viewing = "";                           // the chat tab on screen ("" = closed): its lines count as read
        public bool show_global = true;                       // the player's setting (Settings): global chat off keeps friends and parties
        public GArray friends = new GArray();                 // cards {"pid", "n", "tt", "st", "seen"}
        public GArray rin = new GArray();                     // requests to me
        public GArray rout = new GArray();                    // my requests
        public GArray blocked = new GArray();
        public GDict party = new GDict();                     // {} or {"id", "leader", "members", "pending", "max"}
        public GDict invites = new GDict();                   // party id -> {"from": card, "at": clock}
        public string party_play = "";                        // the party a "go" was for (siege_app passes it into the match)
        public GDict profiles = new GDict();                  // 0.31.120: pid -> its profile card's numbers ({"t":"so", "k":"prof", ...}, "_at": clock)
        // 0.31.134: clans
        public bool has_clans = false;                        // the server has clans ("me" said so)
        public GDict clan = new GDict();                      // {} or {"id", "name", "tag", "house", "join", "min_lv", "n", "max", "lead", "role", "members", "req"?}
        public GArray clan_inv = new GArray();                // invites: clan summaries with "by" (who invited)
        public GArray clan_asked = new GArray();              // clan ids this player asked to join
        public int clan_cool = 0;                             // unix: no joining a clan before then (0: free)
        public int clan_cost = 5000;                          // (the server says: 0.31.148, 5,000; was 10,000)
        public GArray house_clans = new GArray();             // 0.31.148: the three house clans (free, open to all): summaries with "hc"
        public int clan_max = 30;
        public GArray clan_list = new GArray();               // the last search's clans
        public string clan_query = "";
        public GDict clan_infos = new GDict();                // clan id -> its card (clan_info), "_at": clock
        public GDict league = new GDict();                    // 0.31.196: the last clan_league answer ({"week", "ends", "list", "me", "last"}, "_at")
        public bool has_lfg = false;                          // 0.31.196: the server has LFG and parties of 5 ("me" said so)
        public bool has_jn = false;                           // 0.31.209: a friend's card says whether their match can be joined ("jn")
        public WebSocketPeer _ws = null;
        public double _clock = 0.0;
        public double _next_try = 0.0;
        public int _fails = 0;
        public double _t0 = 0.0;
        public bool _hi_sent = false;

        public void Setup(Profile p)
        {
            profile = p;
        }

        public bool HasAccount()
        {
            return profile != null && GD.Str(profile.d["account"].Get("id", "")) != "" && GD.Str(profile.d["account"].Get("key", "")) != "";
        }

        public void SetActive(bool on)
        {
            want = on;
            if (!on)
                _Close();
            else if (_ws == null && state != "old")
                _next_try = GD.Minf(_next_try, _clock);
        }

        public bool Online()
        {
            return state == "online";
        }

        protected override void _Process(double delta)
        {
            _clock += delta;
            foreach (var pa in invites.Keys())
            {
                if (_clock - (double)invites[pa]["at"] > INVITE_LIFE)
                {
                    invites.Erase(pa);
                    Changed?.Invoke("party");
                }
            }
            if (_ws == null)
            {
                if (want && HasAccount() && _clock >= _next_try)
                    _Open();
                return;
            }
            _ws.Poll();
            var st = _ws.GetReadyState();
            if (st == WebSocketPeer.STATE_OPEN && !_hi_sent)
            {
                _hi_sent = true;
                _t0 = _clock;
                var hi = new GDict { { "t", "so" }, { "k", "hi" }, { "v", Net.VERSION }, { "acct", GD.Str(profile.d["account"]["id"]) }, { "key", GD.Str(profile.d["account"]["key"]) } };
                if (!(bool)profile.d["settings"].Get("analytics", true))
                    hi["an_off"] = 1;                         // 0.31.118: usage statistics off -- the server writes nothing for us
                _ws.PutPacket(Net.Encode(hi));
            }
            while (_ws != null && _ws.GetAvailablePacketCount() > 0)
                _On(Net.Decode(_ws.GetPacket()));
            if (_ws == null)
                return;
            if (st == WebSocketPeer.STATE_CLOSED)
                _Lost();
            else if (state == "connecting" && _clock - _t0 > HI_TIMEOUT)
            {
                // the server never answered: one without a social side (older than 0.31.111) -- ask again much later
                _Close();
                state = "old";
                _next_try = _clock + OLD_SERVER_RETRY;
                Changed?.Invoke("state");
            }
        }

        public void _Open()
        {
            _ws = new WebSocketPeer();
            _ws.InboundBufferSize = 1 << 20;
            _ws.OutboundBufferSize = 1 << 16;
            _hi_sent = false;
            _t0 = _clock;
            state = "connecting";
            if (_ws.ConnectToUrl(url) != GD.OK)
            {
                _ws = null;
                _Lost();
                return;
            }
            Changed?.Invoke("state");
        }

        public void _Lost()
        {
            _ws = null;
            if (state != "old")
                state = "off";
            _fails += 1;
            _next_try = _clock + (double)RETRY[GD.Mini(_fails - 1, RETRY.Size() - 1)];
            Changed?.Invoke("state");
        }

        public void AccountSwitched()
        {
            // 0.31.132: this phone plays as another account now (a transfer code, Game Center, or a deleted account): the
            // connection starts again with it
            clan = new GDict();
            clan_inv = new GArray();
            clan_asked = new GArray();
            clan_cool = 0;
            lines["clan"] = new GArray();
            unread["clan"] = 0;
            _Close();
            _fails = 0;
            _next_try = _clock;
        }

        public void _Close()
        {
            if (_ws != null)
                _ws.Close();
            _ws = null;
            if (state != "old")
                state = "off";
            Changed?.Invoke("state");
        }

        public bool _Send(GDict msg)
        {
            if (state != "online" || _ws == null || _ws.GetReadyState() != WebSocketPeer.STATE_OPEN)
                return false;
            msg["t"] = "so";
            _ws.PutPacket(Net.Encode(msg));
            return true;
        }

        // ---------------- what the server says ----------------
        public void _On(GDict m)
        {
            if (GD.Str(m.Get("t", "")) != "so")
                return;
            switch (GD.Str(m.Get("k", "")))
            {
                case "me":
                    {
                        me = new GDict { { "pid", GD.Str(m.Get("pid", "")) }, { "n", GD.Str(m.Get("n", "")) }, { "tt", GD.Str(m.Get("tt", "")) }, { "max", (int)m.Get("max", 120) }, { "ct", GD.Str(m.Get("ct", "")) } };
                        has_clans = (int)m.Get("clans", 0) == 1;
                        has_lfg = (int)m.Get("lfg", 0) == 1;
                        has_jn = (int)m.Get("jn", 0) == 1;
                        me["cc"] = GD.Str(m.Get("cc", ""));
                        var was = state;
                        state = "online";
                        _fails = 0;
                        Changed?.Invoke("me");
                        if (was != "online")
                            Changed?.Invoke("state");
                        break;
                    }
                case "bye":
                    // "auth": the account isn't known here (eco_sync makes a new one); "replaced": this account opened another
                    // social socket (a second copy of the app) -- either way, try again later rather than fight over it
                    _Close();
                    _next_try = _clock + (GD.Str(m.Get("why", "")) == "replaced" ? 60.0 : 20.0);
                    break;
                case "hist":
                    {
                        var ch = GD.Str(m.Get("ch", "global"));
                        if (ch == "global" && !show_global)
                            return;
                        GArray l = m.Get("list", new GArray()).A;
                        // 0.31.140 (Kevin: "make it so the chat messages don't get deleted, only delete after 50 messages"): the
                        // server's global lines join the ones already here (a server that restarted, or an older one that kept
                        // none, no longer wipes them); a party's and a clan's chat are theirs alone (a new clan, or none: replaced)
                        lines[ch] = ch == "global" ? MergeLines(lines.Get(ch, new GArray()).A, l) : l.Slice(GD.Maxi(0, l.Size() - KEEP));
                        Changed?.Invoke("chat");
                        break;
                    }
                case "chat":
                    {
                        GDict line = m.Get("m", new GDict()).D;
                        var ch = GD.Str(line.Get("ch", "global"));
                        if (!lines.Has(ch) || (ch == "global" && !show_global))
                            return;
                        GArray l = lines[ch].A;
                        l.Append(line);
                        while (l.Size() > KEEP)
                            l.PopFront();
                        if (viewing != ch && GD.Str(line.Get("pid", "")) != GD.Str(me.Get("pid", "")))
                            unread[ch] = (int)unread[ch] + 1;
                        Changed?.Invoke("chat");
                        break;
                    }
                case "friends":
                    friends = m.Get("friends", new GArray()).A;
                    rin = m.Get("rin", new GArray()).A;
                    rout = m.Get("rout", new GArray()).A;
                    blocked = m.Get("blocked", new GArray()).A;
                    Changed?.Invoke("friends");
                    break;
                case "pres":
                    {
                        GDict c = m.Get("c", new GDict()).D;
                        foreach (var l in new[] { friends, rin, rout })
                        {
                            for (int i = 0; i < l.Size(); i++)
                            {
                                if (GD.Str(l[i]["pid"]) == GD.Str(c.Get("pid", "")))
                                    l[i] = c;
                            }
                        }
                        Changed?.Invoke("friends");
                        break;
                    }
                case "req":
                    Request?.Invoke(m.Get("from", new GDict()).D);
                    break;
                case "party":
                    {
                        Var p = m.Get("party", new GDict());
                        party = p.IsDict ? p.D : new GDict();
                        if (party.IsEmpty())
                        {
                            lines["party"] = new GArray();
                            unread["party"] = 0;
                        }
                        Changed?.Invoke("party");
                        break;
                    }
                case "inv":
                    {
                        var pa = GD.Str(m.Get("party", ""));
                        invites[pa] = new GDict { { "from", m.Get("from", new GDict()) }, { "at", _clock } };
                        Invited?.Invoke(pa, m.Get("from", new GDict()).D);
                        Changed?.Invoke("party");
                        break;
                    }
                case "go":
                    party_play = GD.Str(m.Get("party", ""));
                    Go?.Invoke(party_play, GD.Str(m.Get("by", "")));
                    break;
                case "note":
                    Note?.Invoke(GD.Str(m.Get("x", "")), (bool)m.Get("bad", false), (bool)m.Get("pop", false));
                    break;
                case "clan":                                       // 0.31.134: my clan (or none), my invites
                    {
                        Var c = m.Get("clan", new GDict());
                        var was = GD.Str(clan.Get("id", ""));
                        clan = c.IsDict ? c.D : new GDict();
                        clan_inv = m.Get("inv", new GArray()).IsArr ? m.Get("inv", new GArray()).A : new GArray();
                        clan_asked = m.Get("asked", new GArray()).IsArr ? m.Get("asked", new GArray()).A : new GArray();
                        clan_cool = (int)m.Get("cool", 0);
                        clan_cost = (int)m.Get("cost", clan_cost);
                        if (m.Get("hcs", Var.Nil).IsArr)
                            house_clans = m["hcs"].A;
                        clan_max = (int)m.Get("max", clan_max);
                        me["ct"] = GD.Str(clan.Get("tag", ""));
                        me["cc"] = GD.Str(clan.Get("cc", ""));
                        if (GD.Str(clan.Get("id", "")) != was)
                        {
                            lines["clan"] = new GArray();
                            unread["clan"] = 0;
                        }
                        Changed?.Invoke("clan");
                        break;
                    }
                case "clans":
                    clan_list = m.Get("list", new GArray()).IsArr ? m.Get("list", new GArray()).A : new GArray();
                    clan_query = GD.Str(m.Get("q", ""));
                    Changed?.Invoke("clans");
                    break;
                case "clan_info":
                    {
                        Var ci = m.Get("c", new GDict());
                        GDict info = ci.IsDict ? ci.D.Duplicate() : new GDict();
                        info["_at"] = _clock;
                        clan_infos[GD.Str(m.Get("id", ""))] = info;
                        Changed?.Invoke("clan_info");
                        break;
                    }
                case "clan_inv":
                    ClanInvited?.Invoke(m.Get("c", new GDict()).D, m.Get("by", new GDict()).D);
                    break;
                case "clan_made":
                    ClanMade?.Invoke((bool)m.Get("ok", false), GD.Str(m.Get("why", "")));
                    break;
                case "clan_league":                                // 0.31.196
                    league = m.Duplicate();
                    league["_at"] = _clock;
                    Changed?.Invoke("league");
                    break;
                case "eco":                                        // 0.31.196: a Clan Chest, a shard given or received
                    Pull?.Invoke();
                    break;
                case "prof":
                    {
                        var pp = GD.Str(m.Get("pid", ""));
                        if (pp != "")
                        {
                            var pr = m.Duplicate();
                            pr["_at"] = _clock;
                            profiles[pp] = pr;
                            Changed?.Invoke("prof");
                        }
                        break;
                    }
            }
        }

        // ---------------- what the player does ----------------
        public bool Say(string ch, string text)
        {
            var t = text.StripEdges();
            if (t == "")
                return false;
            return _Send(new GDict { { "k", "chat" }, { "ch", ch }, { "x", t.Left((int)me.Get("max", 120)) } });
        }

        public bool Add(string pid)
        {
            return _Send(new GDict { { "k", "add" }, { "pid", pid.StripEdges().ToLowerInvariant() } });
        }

        public bool Decline(string pid)
        {
            return _Send(new GDict { { "k", "decline" }, { "pid", pid } });
        }

        public bool Unfriend(string pid)
        {
            return _Send(new GDict { { "k", "unfriend" }, { "pid", pid } });
        }

        public bool Block(string pid)
        {
            return _Send(new GDict { { "k", "block" }, { "pid", pid } });
        }

        public bool Unblock(string pid)
        {
            return _Send(new GDict { { "k", "unblock" }, { "pid", pid } });
        }

        public bool Report(string pid, string why)
        {
            return _Send(new GDict { { "k", "report" }, { "pid", pid }, { "why", why } });
        }

        public bool Invite(string pid)
        {
            return _Send(new GDict { { "k", "invite" }, { "pid", pid } });
        }

        public bool Join(string pa)
        {
            invites.Erase(pa);
            Changed?.Invoke("party");
            return _Send(new GDict { { "k", "join" }, { "party", pa } });
        }

        public bool NoJoin(string pa)
        {
            invites.Erase(pa);
            Changed?.Invoke("party");
            return _Send(new GDict { { "k", "nojoin" }, { "party", pa } });
        }

        public bool Leave()
        {
            return _Send(new GDict { { "k", "leave" } });
        }

        public bool Kick(string pid)
        {
            return _Send(new GDict { { "k", "kick" }, { "pid", pid } });
        }

        public bool Play()
        {
            // the party leader starts: the members follow
            return _Send(new GDict { { "k", "play" } });
        }

        public bool Refresh()
        {
            return _Send(new GDict { { "k", "refresh" } });
        }

        public bool AskProfile(string pid)
        {
            // 0.31.120 (Kevin: player profile card): the numbers on a player's card; kept a minute
            GDict pr = profiles.Get(pid, new GDict()).D;
            if (!pr.IsEmpty() && GD.Str(pr.Get("why", "")) != "busy" && _clock - (double)pr.Get("_at", -999.0) < 60.0)
                return true;
            return _Send(new GDict { { "k", "prof" }, { "pid", pid } });
        }

        public GDict ProfileOf(string pid)
        {
            return profiles.Get(pid, new GDict()).D;
        }

        // ---------------- clans (0.31.134) ----------------
        public bool ClanNew(string name, string tag, GDict crest, string join, int min_lv)
        {
            // 0.31.196: the crest ("cr"); and a house for a server older than crests (one by the emblem: Eco.CLAN_HOUSE_CREST's
            // first three are the houses')
            return _Send(new GDict { { "k", "clan_new" }, { "name", name.StripEdges() }, { "tag", tag.StripEdges().ToUpperInvariant() }, { "cr", crest },
                { "house", HOUSES_OLD[(int)crest.Get("e", 0) % 3] }, { "join", join }, { "min_lv", min_lv } });
        }

        public static readonly GArray HOUSES_OLD = GArray.Of("lions", "stags", "ravens");

        // 0.31.196
        public bool ClanV2()
        {
            // the server's clans have the crest, points, Clan Chest, League, shard requests and LFG
            return (int)clan.Get("cv", 0) >= 2;
        }

        public bool ClanCrest(GDict cr)
        {
            return _Send(new GDict { { "k", "clan_crest" }, { "cr", cr } });
        }

        public bool ClanAsk(string hid)
        {
            return _Send(new GDict { { "k", "clan_ask" }, { "h", hid } });
        }

        public bool ClanUnask()
        {
            return _Send(new GDict { { "k", "clan_unask" } });
        }

        public bool ClanGive(string pid)
        {
            return _Send(new GDict { { "k", "clan_give" }, { "pid", pid } });
        }

        public bool ClanLeague()
        {
            return _Send(new GDict { { "k", "clan_league" } });
        }

        public bool Lfg(bool on)
        {
            return _Send(new GDict { { "k", "lfg" }, { "on", on } });
        }

        public bool LfgJoin(string pid)
        {
            return _Send(new GDict { { "k", "lfg_join" }, { "pid", pid } });
        }

        public string MyCrest()
        {
            return GD.Str(clan.Get("cc", ""));
        }

        public GDict MyAsk()
        {
            // my open shard request ({} for none)
            foreach (var a in clan.Get("asks", new GArray()))
            {
                if (GD.Str(a.Get("pid", "")) == GD.Str(me.Get("pid", "")))
                    return a.D;
            }
            return new GDict();
        }

        public bool AskOpen(string pid, string hid)
        {
            foreach (var a in clan.Get("asks", new GArray()))
            {
                if (GD.Str(a.Get("pid", "")) == pid && GD.Str(a.Get("h", "")) == hid)
                    return true;
            }
            return false;
        }

        public GDict LfgCall(string pid)
        {
            // an open LFG call in my clan ({} for none)
            foreach (var c in clan.Get("lfg", new GArray()))
            {
                if (GD.Str(c.Get("pid", "")) == pid)
                    return c.D;
            }
            return new GDict();
        }

        public int ClanPartyMax()
        {
            return (int)party.Get("max", has_lfg ? 5 : 4);
        }

        public bool CanJoin(GDict c)
        {
            // 0.31.209 (Kevin: "players cannot join a match in progress"): a friend's match can be joined only in its countdown --
            // the card says so ("jn"); an older server doesn't, and JOIN shows for any match as before
            return GD.Str(c.Get("st", "")) == "match" && (!has_jn || (int)c.Get("jn", 0) == 1);
        }

        public bool ClanFind(string q, string house = "")
        {
            return _Send(new GDict { { "k", "clan_find" }, { "q", q.StripEdges() }, { "house", house } });
        }

        public bool ClanInfo(string id)
        {
            return _Send(new GDict { { "k", "clan_info" }, { "id", id } });
        }

        public bool ClanJoin(string id)
        {
            return _Send(new GDict { { "k", "clan_join" }, { "id", id } });
        }

        public bool ClanUnreq(string id)
        {
            return _Send(new GDict { { "k", "clan_unreq" }, { "id", id } });
        }

        public bool ClanNoinv(string id)
        {
            clan_inv = clan_inv.Filter(c => GD.Str(c.Get("id", "")) != id);
            Changed?.Invoke("clan");
            return _Send(new GDict { { "k", "clan_noinv" }, { "id", id } });
        }

        public bool ClanAccept(string pid)
        {
            return _Send(new GDict { { "k", "clan_accept" }, { "pid", pid } });
        }

        public bool ClanReject(string pid)
        {
            return _Send(new GDict { { "k", "clan_reject" }, { "pid", pid } });
        }

        public bool ClanInvite(string pid)
        {
            return _Send(new GDict { { "k", "clan_invite" }, { "pid", pid.StripEdges().ToLowerInvariant() } });
        }

        public bool ClanLeave()
        {
            return _Send(new GDict { { "k", "clan_leave" } });
        }

        public bool ClanKick(string pid)
        {
            return _Send(new GDict { { "k", "clan_kick" }, { "pid", pid } });
        }

        public bool ClanRole(string pid, string role)
        {
            return _Send(new GDict { { "k", "clan_role" }, { "pid", pid }, { "role", role } });
        }

        public bool ClanLead(string pid)
        {
            return _Send(new GDict { { "k", "clan_lead" }, { "pid", pid } });
        }

        public bool ClanSet(string join, int min_lv)
        {
            return _Send(new GDict { { "k", "clan_set" }, { "join", join }, { "min_lv", min_lv } });
        }

        public bool ClanDisband()
        {
            return _Send(new GDict { { "k", "clan_disband" } });
        }

        public bool InClan()
        {
            return !clan.IsEmpty();
        }

        public bool InHouseClan()
        {
            // 0.31.148: in one of the house clans (joining or starting a players' clan moves you out of it)
            return (bool)clan.Get("hc", false);
        }

        public string ClanRoleOfMe()
        {
            return GD.Str(clan.Get("role", ""));
        }

        public bool IsClanOfficer()
        {
            return GArray.Of("leader", "officer").Has(ClanRoleOfMe());
        }

        public string MyTag()
        {
            return GD.Str(clan.Get("tag", ""));
        }

        public int ClanRequests()
        {
            return clan.Get("req", new GArray()).A.Size();
        }

        public int ClanCoolLeft()
        {
            return GD.Maxi(0, clan_cool - GD.Int(Time.GetUnixTimeFromSystem()));
        }

        public static string Tagged(string name, string ct)
        {
            // "[WOLF] Kevin" -- a player's name with their clan tag before it
            return ct != "" ? GD.Fmt("[%s] %s", ct, name) : name;
        }

        public GArray MergeLines(GArray have, GArray got)
        {
            // both lists as one, each line once (its id, time, sender and words), oldest first, the last KEEP; none from a
            // player blocked since
            var seen = new GDict();
            var out_ = new GArray();
            var gone = new GDict();
            foreach (var b in blocked)
                gone[b.IsDict ? GD.Str(b.D.Get("pid", "")) : GD.Str(b)] = true;
            var both = have.Duplicate();
            both.AppendArray(got);
            foreach (var line in both)
            {
                if (!line.IsDict)
                    continue;
                var key = GD.Fmt("%s|%s|%s|%s", GD.Str(GD.Long(line.Get("id", 0))), GD.Str(GD.Long(line.Get("at", 0))), GD.Str(line.Get("pid", "")), GD.Str(line.Get("x", "")));
                if (seen.Has(key) || gone.Has(GD.Str(line.Get("pid", ""))))
                    continue;
                seen[key] = true;
                out_.Append(line);
            }
            out_.SortCustom((a, b) => GD.Long(a.Get("at", 0)) < GD.Long(b.Get("at", 0)) || (GD.Long(a.Get("at", 0)) == GD.Long(b.Get("at", 0)) && GD.Long(a.Get("id", 0)) < GD.Long(b.Get("id", 0))));
            return out_.Slice(GD.Maxi(0, out_.Size() - KEEP));
        }

        public void MarkRead(string ch)
        {
            if ((int)unread.Get(ch, 0) != 0)
            {
                unread[ch] = 0;
                Changed?.Invoke("chat");
            }
        }

        public void SetShowGlobal(bool on)
        {
            show_global = on;
            if (!on)
            {
                lines["global"] = new GArray();
                unread["global"] = 0;
            }
            Changed?.Invoke("chat");
        }

        // ---------------- for the screens ----------------
        public bool InParty()
        {
            return !party.IsEmpty();
        }

        public bool IsLeader()
        {
            return InParty() && GD.Str(party.Get("leader", "")) == GD.Str(me.Get("pid", ""));
        }

        public int PartySize()
        {
            return party.Get("members", new GArray()).A.Size();
        }

        public bool InMyClan(string pid)
        {
            foreach (var c in clan.Get("members", new GArray()))
            {
                if (GD.Str(c["pid"]) == pid)
                    return true;
            }
            return false;
        }

        public bool InMyParty(string pid)
        {
            foreach (var c in party.Get("members", new GArray()))
            {
                if (GD.Str(c["pid"]) == pid)
                    return true;
            }
            return false;
        }

        public string Relation(string pid)
        {
            // "me", "friend", "sent" (I asked), "asked" (they asked me), "blocked" or "none"
            if (pid == GD.Str(me.Get("pid", "")))
                return "me";
            foreach (var pair in GArray.Of(GArray.Of(friends, "friend"), GArray.Of(rin, "asked"), GArray.Of(rout, "sent"), GArray.Of(blocked, "blocked")))
            {
                foreach (var c in pair[0])
                {
                    if (GD.Str(c["pid"]) == pid)
                        return GD.Str(pair[1]);
                }
            }
            return "none";
        }

        public GDict CardOf(string pid)
        {
            foreach (var l in GArray.Of(friends, rin, rout, blocked, party.Get("members", new GArray()), clan.Get("members", new GArray())))
            {
                foreach (var c in l)
                {
                    if (GD.Str(c["pid"]) == pid)
                        return c.D;
                }
            }
            return new GDict();
        }

        public int Attention()
        {
            // the Home badge: friend requests and party invites waiting (0.31.134: clan invites, and requests for officers)
            return rin.Size() + invites.Size() + clan_inv.Size() + (IsClanOfficer() ? ClanRequests() : 0);
        }

        public int UnreadTotal()
        {
            return (int)unread["global"] + (int)unread["party"] + (int)unread["clan"];
        }

        public static string CodeOf(string pid)
        {
            return pid.ToUpperInvariant();
        }
    }
}
