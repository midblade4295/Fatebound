// Ported from godot/scripts/meta/account_link.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Net = Fatebound.Game.SiegeNet;

namespace Fatebound.Game
{
    // 0.31.132 (the iOS port, IOS_PORT_SPEC_FOR_CLAUDE.md §4, §6): the Fatebound account between phones -- the same on
    // Android and iPhone. The account (id + key, profile.d.account) is the progress; the server keeps it
    // (server/eco_accounts.gd). Each request is one "eco" message with an "op" on its own socket:
    //   MOVE TO ANOTHER PHONE  new_code()      a one-time 8-character code, 10 minutes (Android <-> iPhone, both ways)
    //   ENTER A CODE           use_code(code)  this phone plays as that account from then on (with a key of its own)
    //   Game Center            game_center()   the Game Center player is linked to the account; a reinstall gets it back
    //                                          (a fresh install simply takes it; a phone with progress asks: ask_gc)
    //   DELETE ACCOUNT         delete_account() the account is deleted on the server; this phone starts again
    // A switch replaces this phone's account and progress with the server's (switched -> the app pulls and redraws).
    public class AccountLink : Node
    {
        public const double TIMEOUT = 20.0;

        public event Action Switched;                    // this phone now plays as another account (or a new one after a deletion)
        public event Action<string, bool> Note;
        public event Action<GDict> AskGc;                // Game Center has another account and this phone has progress: the app asks

        public Profile profile;
        public string url = OS.HasEnvironment("SIEGE_URL") ? OS.GetEnvironment("SIEGE_URL") : Net.DEFAULT_URL;
        public string busy = "";                         // the request in flight ("" none)
        public string gc_done = "";                      // the Game Center player linked this run (asked once)
        public GDict _gc_other = new GDict();            // {acct, key, seq, sum} while the player chooses
        public GDict _gc_proof = new GDict();
        public GArray _reqs = new GArray();              // [{ws, sent, msg, cb, t0}]

        public void Setup(Profile p)
        {
            profile = p;
        }

        public bool HasAccount()
        {
            return profile != null && GD.Str(profile.d["account"].Get("id", "")) != "" && GD.Str(profile.d["account"].Get("key", "")) != "";
        }

        public GDict _Auth()
        {
            return new GDict { { "acct", GD.Str(profile.d["account"].Get("id", "")) }, { "key", GD.Str(profile.d["account"].Get("key", "")) } };
        }

        // ---------------- MOVE TO ANOTHER PHONE / ENTER A CODE ----------------
        public void NewCode(Action<GDict> cb)
        {
            // cb({ok, code, ttl} | {ok:false, why: "auth" | "busy" | "old" | "unreachable"})
            if (!HasAccount())
            {
                cb(new GDict { { "ok", false }, { "why", "auth" } });
                return;
            }
            var m = new GDict { { "t", "eco" }, { "v", Net.VERSION }, { "op", "link_new" } };
            m.Merge(_Auth());
            _Ask("code", m, (GDict a) =>
            {
                if ((bool)a.Get("ok", false) && !a.Has("code"))
                    a = new GDict { { "ok", false }, { "why", "old" } };            // (a server from before 0.31.132 answered with the account)
                cb(a);
            });
        }

        public void UseCode(string code, Action<GDict> cb)
        {
            // cb({ok} | {ok:false, why: "code" | "busy" | "old" | "unreachable"}); on ok this phone has switched
            var c = code.StripEdges().ToUpperInvariant().Replace(" ", "").Replace("-", "");
            if (GStr.Length(c) != 8)
            {
                cb(new GDict { { "ok", false }, { "why", "code" } });
                return;
            }
            _Ask("use", new GDict { { "t", "eco" }, { "v", Net.VERSION }, { "op", "link_use" }, { "code", c } }, (GDict a) =>
            {
                if ((bool)a.Get("ok", false) && GD.Str(a.Get("acct", "")) != "" && GStr.Length(GD.Str(a.Get("key", ""))) == 64)
                {
                    SwitchTo(GD.Str(a["acct"]), GD.Str(a["key"]), (int)a.Get("seq", 0));
                    cb(new GDict { { "ok", true } });
                    return;
                }
                if ((bool)a.Get("ok", false))
                    a = new GDict { { "ok", false }, { "why", "old" } };
                cb(a);
            });
        }

        // ---------------- DELETE ACCOUNT ----------------
        public void DeleteAccount(Action<GDict> cb)
        {
            // cb({ok} | {ok:false, why}); on ok the phone's progress is gone too and a new account comes with the next sync
            if (!HasAccount())
            {
                cb(new GDict { { "ok", false }, { "why", "auth" } });
                return;
            }
            var m = new GDict { { "t", "eco" }, { "v", Net.VERSION }, { "op", "delete" } };
            m.Merge(_Auth());
            _Ask("delete", m, (GDict a) =>
            {
                if ((bool)a.Get("ok", false) && GD.Str(a.Get("op", "")) == "delete")
                {
                    Wipe();
                    cb(new GDict { { "ok", true } });
                    return;
                }
                if ((bool)a.Get("ok", false))
                    a = new GDict { { "ok", false }, { "why", "old" } };
                cb(a);
            });
        }

        public void Wipe()
        {
            // this phone starts again: a fresh profile (its sound and graphics settings kept); the Google Play copy, if any,
            // is overwritten by the fresh one at its next upload (marked changed), never read back
            GDict keep = profile.d["settings"].D.Duplicate(true);
            GDict cloud = profile.d["cloud"].D.Duplicate(true);
            profile.d = Profile.Defaults();
            profile.d["settings"] = keep;
            profile.d["cloud"] = new GDict { { "stamp", GD.Str(cloud.Get("stamp", "")) }, { "dirty", true }, { "at", (int)cloud.Get("at", 0) } };
            profile.Save(false);
            Switched?.Invoke();
        }

        // ---------------- Game Center ----------------
        public void GameCenter(string team_id, GDict proof)
        {
            // the Game Center player and Apple's identity signature ({url, data, salt, timestamp} from GKLocalPlayer)
            if (team_id == "" || gc_done == team_id || busy != "")
                return;
            Var sig = proof.Get("data", Var.Of(new byte[0]));
            Var salt = proof.Get("salt", Var.Of(new byte[0]));
            if (!sig.Is<byte[]>() || !salt.Is<byte[]>() || sig.As<byte[]>().Length == 0)
                return;
            _gc_proof = new GDict { { "id", team_id }, { "url", GD.Str(proof.Get("url", "")) }, { "sig", Marshalls.RawToBase64(sig.As<byte[]>()) },
                { "salt", Marshalls.RawToBase64(salt.As<byte[]>()) }, { "ts", (int)proof.Get("timestamp", 0) } };
            var m = new GDict { { "t", "eco" }, { "v", Net.VERSION }, { "op", "gc" }, { "gc", _gc_proof } };
            if (HasAccount())
                m.Merge(_Auth());
            _Ask("gc", m, (GDict a) => _OnGc(team_id, a));
        }

        public void _OnGc(string team_id, GDict a)
        {
            if (!(bool)a.Get("ok", false))
                return;                                       // (offline, an older server, a refused signature: next start)
            switch (GD.Str(a.Get("gc", "")))
            {
                case "linked":
                case "same":
                    gc_done = team_id;
                    break;
                case "none":
                    break;                                     // (no account here yet: linked once eco_sync has made one)
                case "other":
                    {
                        gc_done = team_id;
                        var other = new GDict { { "acct", GD.Str(a.Get("acct", "")) }, { "key", GD.Str(a.Get("key", "")) }, { "seq", (int)a.Get("seq", 0) },
                            { "sum", a.Get("sum", new GDict()).IsDict ? a.Get("sum", new GDict()) : new GDict() } };
                        if (GD.Str(other["acct"]) == "" || GStr.Length(GD.Str(other["key"])) != 64)
                            return;
                        if (!HasAccount() || profile.IsFresh())
                        {
                            SwitchTo(GD.Str(other["acct"]), GD.Str(other["key"]), (int)other["seq"]);
                            Note?.Invoke("Progress restored from Game Center", true);
                        }
                        else
                        {
                            _gc_other = other;
                            AskGc?.Invoke(other);
                        }
                        break;
                    }
            }
        }

        public void ChooseGc(bool use_other)
        {
            // the answer to ask_gc: USE THAT ACCOUNT (this phone switches) or KEEP THIS PHONE'S (Game Center follows this one)
            if (_gc_other.IsEmpty())
                return;
            var o = _gc_other;
            _gc_other = new GDict();
            if (use_other)
            {
                SwitchTo(GD.Str(o["acct"]), GD.Str(o["key"]), (int)o["seq"]);
                Note?.Invoke("Progress restored from Game Center", true);
                return;
            }
            // a fresh signature is needed (each is used once): Game Center gives one at the next sign-in or start
            gc_done = "";
            _pending_relink = true;
        }

        public bool _pending_relink = false;

        public bool RelinkPending()
        {
            return _pending_relink;
        }

        public void GameCenterRelink(string team_id, GDict proof)
        {
            // KEEP THIS PHONE'S, with a fresh identity signature
            if (!_pending_relink || !HasAccount())
                return;
            _pending_relink = false;
            Var sig = proof.Get("data", Var.Of(new byte[0]));
            Var salt = proof.Get("salt", Var.Of(new byte[0]));
            if (!sig.Is<byte[]>() || !salt.Is<byte[]>())
                return;
            var g = new GDict { { "id", team_id }, { "url", GD.Str(proof.Get("url", "")) }, { "sig", Marshalls.RawToBase64(sig.As<byte[]>()) },
                { "salt", Marshalls.RawToBase64(salt.As<byte[]>()) }, { "ts", (int)proof.Get("timestamp", 0) } };
            var m = new GDict { { "t", "eco" }, { "v", Net.VERSION }, { "op", "gc" }, { "gc", g }, { "relink", true } };
            m.Merge(_Auth());
            _Ask("gc", m, (GDict a) =>
            {
                if ((bool)a.Get("ok", false))
                {
                    gc_done = team_id;
                    Note?.Invoke("Game Center now goes with this phone's progress", true);
                }
            });
        }

        public GDict PendingGc()
        {
            return _gc_other;
        }

        // ---------------- the switch ----------------
        public void SwitchTo(string acct, string key, int seq)
        {
            // this phone plays as that account from now on: the server's copy replaces the phone's at the next sync (the app
            // pulls at once); ops numbered after the account's own (seq), so none is mistaken for one already done
            profile.d["account"] = new GDict { { "id", acct }, { "key", key }, { "seq", seq } };
            profile.d["cloud"].D["dirty"] = true;                  // (Google Play's copy follows the account)
            profile.Save(false);
            Switched?.Invoke();
        }

        // ---------------- the socket ----------------
        public void _Ask(string what, GDict msg, Action<GDict> cb)
        {
            var ws = new WebSocketPeer();
            ws.InboundBufferSize = 1 << 21;
            if (ws.ConnectToUrl(url) != GD.OK)
            {
                cb(new GDict { { "ok", false }, { "why", "unreachable" } });
                return;
            }
            busy = what;
            _reqs.Append(new GDict { { "ws", Var.Of(ws) }, { "sent", false }, { "msg", msg }, { "cb", cb }, { "t0", Time.GetTicksMsec() / 1000.0 } });
        }

        protected override void _Process(double _dt)
        {
            foreach (var r in _reqs.Duplicate())
            {
                WebSocketPeer ws = r["ws"].As<WebSocketPeer>();
                ws.Poll();
                var st = ws.GetReadyState();
                if (st == WebSocketPeer.STATE_OPEN && !(bool)r["sent"])
                {
                    ws.PutPacket(Net.Encode(r["msg"].D, true));
                    r.D["sent"] = true;
                }
                var answer = new GDict();
                while (ws.GetAvailablePacketCount() > 0)
                {
                    var m = Net.Decode(ws.GetPacket());
                    if (GD.Str(m.Get("t", "")) == "eco")
                        answer = m;
                }
                bool late = Time.GetTicksMsec() / 1000.0 - (double)r["t0"] > TIMEOUT;
                if (!answer.IsEmpty() || st == WebSocketPeer.STATE_CLOSED || late)
                {
                    _reqs.Erase(r);
                    if (st != WebSocketPeer.STATE_CLOSED)
                        ws.Close();
                    if (_reqs.IsEmpty())
                        busy = "";
                    r["cb"].As<Action<GDict>>()(!answer.IsEmpty() ? answer : new GDict { { "ok", false }, { "why", "unreachable" } });
                }
            }
        }
    }
}
