// Ported from godot/scripts/meta/eco_sync.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Net = Fatebound.Game.SiegeNet;
using Diag = Fatebound.Game.SiegeDiag;

namespace Fatebound.Game
{
    // 0.31.108 (Kevin: "make sure everything is verified by server so players can't edit gems ect"): the phone's side of
    // the accounts the Siege server keeps (server/eco_accounts.gd).
    //
    // The first time it reaches a server that keeps accounts, the phone asks for one ("new"), handing over its progress so
    // far once (the server takes it in held to what that many matches could earn, purchases counted only if Google
    // confirmed them). From then on the phone's profile is a prediction:
    //   - every change made in the app is an op (Profile._rec -> _on_op) that goes into the outbox (kept on disk) and up
    //     to the server in batches; the server replays it with the same Profile code and its own clock;
    //   - each answer carries the account as the server has it: it replaces the phone's copy, the ops not answered yet are
    //     applied again on top (Profile.apply_op), and the screens redraw if anything differs;
    //   - a VS BOTS match needs a ticket from the server (request_ticket) before it starts -- Kevin: "Always online" -- and
    //     its result goes up as an op carrying that ticket; an online match is paid by the server from its own match;
    //   - a purchase is granted by the server to the account (billing.gd sends the account with the purchase).
    // Ops are numbered; the server skips any number it has done, so sending a batch again after a lost answer is safe.
    // Nothing here can add gems or gold the server doesn't agree with: an edited save is replaced by the next answer.
    public class EcoSync : Node
    {
        public event Action<bool> Synced;           // the profile is the server's again (differs: what it shows changed)
        public event Action<string, string> Rejected;
        public event Action StateChanged;

        public const double DEBOUNCE = 0.35;                 // s after an op before the batch goes up
        public const double TIMEOUT = 15.0;
        public const int MAX_BATCH = 64;
        public static readonly GArray RETRY = GArray.Of(3.0, 6.0, 15.0, 30.0, 60.0);

        public Profile profile;
        public string url = OS.HasEnvironment("SIEGE_URL") ? OS.GetEnvironment("SIEGE_URL") : Net.DEFAULT_URL;
        public bool auto_start = true;                 // tests turn this off and call start() / pull() themselves
        public string outbox_path = "";
        public GArray outbox = new GArray();           // [{"s", "op", "a", "tk"?}]
        public int next_seq = 1;
        public bool enabled = false;                   // this phone has an account on the server
        public bool online = false;                    // the last exchange worked
        public bool started = false;
        public string ticket = "";                     // the VS BOTS ticket of the match being played
        public GDict _req = new GDict();               // the exchange in flight: {ws, sent, msg, t0, ops}
        public bool _want = false;                     // an exchange is wanted even with nothing to send (a pull, a ticket)
        public bool _want_ticket = false;
        public List<Action<string>> _ticket_cbs = new List<Action<string>>();
        public double _send_at = 0.0;
        public int _fails = 0;
        public double _clock = 0.0;

        public void Setup(Profile p)
        {
            profile = p;
            outbox_path = GD.Str(p.path).GetBasename() + ".outbox.json";
            _LoadOutbox();
            profile.on_op = _OnOp;
            _AccountChanged();
        }

        public void _AccountChanged()
        {
            enabled = GD.Str(profile.d["account"].Get("id", "")) != "" && GD.Str(profile.d["account"].Get("key", "")) != "";
            profile.server_mode = enabled;
            next_seq = GD.Maxi(next_seq, (int)profile.d["account"].Get("seq", 0) + 1);
            StateChanged?.Invoke();
        }

        protected override void _Ready()
        {
            if (auto_start)
                Start();
        }

        public void Start()
        {
            // reach the server: an account if there is none yet, else the account as it stands (and whatever is waiting)
            started = true;
            Pull();
        }

        public void Pull()
        {
            _want = true;
            _send_at = GD.Minf(_send_at, _clock);
        }

        public void AccountSwitched()
        {
            // Google Play's saved progress replaced this phone's, and with it the account: what was waiting belonged to the
            // other one
            outbox.Clear();
            next_seq = 1;
            _SaveOutbox();
            _AccountChanged();
            Pull();
        }

        public void RequestTicket(Action<string> cb)
        {
            // a VS BOTS match may start: cb(ticket) -- "" when the server can't be reached (no match without it); "local"
            // with no account (an older server: the phone's own economy)
            if (!enabled)
            {
                cb("local");
                return;
            }
            _ticket_cbs.Add(cb);
            _want_ticket = true;
            Pull();
        }

        public int Pending()
        {
            return outbox.Size();
        }

        public List<Action> _flush_cbs = new List<Action>();

        public void Flush(Action cb)
        {
            // 0.31.170: cb() once the changes waiting here have reached the server (or it couldn't be reached) -- before an
            // online match, so the server knows a hero bought a moment ago
            if (!enabled || outbox.IsEmpty())
            {
                cb();
                return;
            }
            _flush_cbs.Add(cb);
            _want = true;
            _send_at = GD.Minf(_send_at, _clock);
        }

        public void _FlushDone(bool all)
        {
            if (_flush_cbs.Count == 0 || (!all && !outbox.IsEmpty()))
                return;
            var cbs = new List<Action>(_flush_cbs);
            _flush_cbs.Clear();
            foreach (var cb in cbs)
                cb();
        }

        // ---------------- the outbox ----------------
        public void _OnOp(string op, GArray args)
        {
            if (!enabled)
                return;
            var o = new GDict { { "s", next_seq }, { "op", op }, { "a", args } };
            if (op == "match")
            {
                o["tk"] = ticket;
                ticket = "";
            }
            next_seq += 1;
            outbox.Append(o);
            _SaveOutbox();
            if (_send_at <= _clock)
                _send_at = _clock + DEBOUNCE;               // (a retry already waiting keeps its time)
            StateChanged?.Invoke();
        }

        public void _LoadOutbox()
        {
            outbox = new GArray();
            if (outbox_path == "" || !FileAccess.FileExists(outbox_path))
                return;
            Var v = JSON.ParseString(FileAccess.GetFileAsString(outbox_path));
            if (v.IsDict && v.Get("ops", Var.Nil).IsArr)
            {
                outbox = v["ops"].A;
                next_seq = GD.Maxi(next_seq, (int)v.Get("next", 1));
            }
        }

        public void _SaveOutbox()
        {
            if (outbox_path == "")
                return;
            var f = FileAccess.Open(outbox_path + ".tmp", FileAccess.WRITE);
            if (f == null)
                return;
            f.StoreString(JSON.Stringify(new GDict { { "next", next_seq }, { "ops", outbox } }));
            f.Close();
            DirAccess.RenameAbsolute(ProjectSettings.GlobalizePath(outbox_path + ".tmp"), ProjectSettings.GlobalizePath(outbox_path));
        }

        // ---------------- talking to the server ----------------
        protected override void _Process(double delta)
        {
            _clock += delta;
            if (!_req.IsEmpty())
            {
                _Poll();
                return;
            }
            if (!started || _clock < _send_at)
                return;
            if (_want || (enabled && !outbox.IsEmpty()))
                _Send();
        }

        public GDict _Message()
        {
            if (!enabled)
            {
                // a new account, with this phone's progress so far (taken in once, within limits)
                GDict imp = profile.d.Duplicate(true);
                foreach (var k in GArray.Of("settings", "cloud", "account", "history"))
                    imp.Erase(k);
                return new GDict { { "t", "eco" }, { "v", Net.VERSION }, { "build", Diag.BUILD }, { "new", true }, { "import", imp } };
            }
            return new GDict { { "t", "eco" }, { "v", Net.VERSION }, { "build", Diag.BUILD }, { "acct", GD.Str(profile.d["account"]["id"]) }, { "key", GD.Str(profile.d["account"]["key"]) },
                { "ops", outbox.Slice(0, MAX_BATCH) }, { "ticket", _want_ticket } };
        }

        public void _Send()
        {
            var ws = new WebSocketPeer();
            ws.InboundBufferSize = 1 << 21;
            ws.OutboundBufferSize = 1 << 17;
            var msg = _Message();
            _want = false;
            if (ws.ConnectToUrl(url) != GD.OK)
            {
                _Failed();
                return;
            }
            _req = new GDict { { "ws", Var.Of(ws) }, { "sent", false }, { "msg", msg }, { "t0", _clock }, { "ticket", (bool)msg.Get("ticket", false) } };
        }

        public void _Poll()
        {
            WebSocketPeer ws = _req["ws"].As<WebSocketPeer>();
            ws.Poll();
            var st = ws.GetReadyState();
            if (st == WebSocketPeer.STATE_OPEN && !(bool)_req["sent"])
            {
                ws.PutPacket(Net.Encode(_req["msg"].D, true));
                _req["sent"] = true;
            }
            var answer = new GDict();
            while (ws.GetAvailablePacketCount() > 0)
            {
                var m = Net.Decode(ws.GetPacket());
                if (GD.Str(m.Get("t", "")) == "eco")
                    answer = m;
            }
            if (!answer.IsEmpty())
            {
                GDict sent = _req["msg"].D;
                var had_ticket = (bool)_req["ticket"];
                _req = new GDict();
                if (st == WebSocketPeer.STATE_OPEN)
                    ws.Close();
                ApplyAnswer(answer, sent, had_ticket);
                return;
            }
            if (st == WebSocketPeer.STATE_CLOSED || _clock - (double)_req["t0"] > TIMEOUT)
            {
                _req = new GDict();
                if (st != WebSocketPeer.STATE_CLOSED)
                    ws.Close();
                _Failed();
            }
        }

        public void _Failed()
        {
            online = false;
            _fails += 1;
            _send_at = _clock + (double)RETRY[GD.Mini(_fails - 1, RETRY.Size() - 1)];
            if (!enabled)
            {
                // no account yet: an older server that keeps none, or no connection -- a few tries, then the next start
                _want = _fails < 3;
            }
            _TicketDone("");
            _FlushDone(true);
            StateChanged?.Invoke();
        }

        public void _TicketDone(string tk)
        {
            _want_ticket = false;
            var cbs = new List<Action<string>>(_ticket_cbs);
            _ticket_cbs.Clear();
            foreach (var cb in cbs)
                cb(tk);
        }

        public void ApplyAnswer(GDict a, GDict sent = null, bool had_ticket = false)
        {
            sent ??= new GDict();
            online = true;
            _fails = 0;
            if (!(bool)a.Get("ok", false))
            {
                if (GD.Str(a.Get("why", "")) == "auth")
                {
                    // the server doesn't know this key (its accounts were reset): a new account from this phone's copy
                    profile.d["account"] = new GDict { { "id", "" }, { "key", "" }, { "seq", 0 } };
                    outbox.Clear();
                    next_seq = 1;
                    _SaveOutbox();
                    profile.Save(false);
                    _AccountChanged();
                    _want = true;
                }
                _TicketDone("");
                _FlushDone(true);
                StateChanged?.Invoke();
                return;
            }
            if (a.Has("key"))
            {
                profile.d["account"] = new GDict { { "id", GD.Str(a["acct"]) }, { "key", GD.Str(a["key"]) }, { "seq", 0 } };
                _AccountChanged();
            }
            var seq = (int)a.Get("seq", 0);
            var ops_by_s = new GDict();
            foreach (var o in sent.Get("ops", new GArray()))
                ops_by_s[(int)o["s"]] = GD.Str(o["op"]);
            foreach (var r in a.Get("results", new GArray()))
            {
                if (!(bool)r.Get("ok", false) && !(bool)r.Get("dup", false))
                    Rejected?.Invoke(GD.Str(ops_by_s.Get((int)r.Get("s", 0), "?")), GD.Str(r.Get("error", "")));
            }
            var left = new GArray();
            foreach (var o in outbox)
            {
                if ((int)o["s"] > seq)
                    left.Append(o);
            }
            outbox = left;
            next_seq = GD.Maxi(next_seq, seq + 1);
            _SaveOutbox();
            if (a.Has("now"))
                profile.clock_offset = (int)a["now"] - GD.Int(Time.GetUnixTimeFromSystem());
            Adopt(a.Get("profile", new GDict()), seq);
            if (had_ticket)
            {
                ticket = GD.Str(a.Get("ticket", ""));
                _TicketDone(ticket);
            }
            if (!outbox.IsEmpty())
                _send_at = _clock;                           // more waiting: straight on
            _FlushDone(false);
            StateChanged?.Invoke();
        }

        public void Adopt(Var sp, int seq)
        {
            // the server's copy replaces this phone's; what is the phone's alone stays; the unanswered ops again on top
            if (!sp.IsDict || !sp.D.Has("stats"))
                return;
            GDict d = profile.d;
            var before = _View(d);
            GDict nd = sp.D.Duplicate(true);
            nd["settings"] = d["settings"];
            nd["cloud"] = d["cloud"];
            nd["account"] = new GDict { { "id", GD.Str(d["account"]["id"]) }, { "key", GD.Str(d["account"]["key"]) }, { "seq", seq } };
            nd["iap"] = new GDict { { "done", d["iap"].Get("done", new GArray()) }, { "starter", (bool)sp.D.Get("iap", new GDict()).Get("starter", false) } };
            foreach (var k in GArray.Of("migration", "refund_note", "title_note"))
            {
                if (d.Has(k))
                    nd[k] = d[k];
            }
            profile.d = profile._Normalized(nd);
            bool was = profile.replaying;
            profile.replaying = true;
            foreach (var o in outbox)
            {
                if (GD.Str(o["op"]) == "match")
                {
                    GArray ar = o["a"].A;
                    if (ar.Size() == 3 && ar[0].IsDict)
                        profile.ApplyMatch(ar[0].D, (bool)ar[1], (bool)ar[2], false);
                }
                else
                    profile.ApplyOp(GD.Str(o["op"]), o["a"]);
            }
            profile.replaying = was;
            profile.Save();
            Synced?.Invoke(_View(profile.d) != before);
        }

        public static string _View(GDict d)
        {
            // what the screens show, to tell whether a redraw is needed
            var v = d.Duplicate(true);
            foreach (var k in GArray.Of("settings", "cloud", "account", "history", "iap"))
                v.Erase(k);
            return JSON.Stringify(v, "", true);
        }
    }
}
