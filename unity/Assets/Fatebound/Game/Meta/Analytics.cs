// Ported from godot/scripts/meta/analytics.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Net = Fatebound.Game.SiegeNet;
using Diag = Fatebound.Game.SiegeDiag;
using Events = Fatebound.Game.AnalyticsEvents;

namespace Fatebound.Game
{
    // 0.31.118 (Kevin's spec, ANALYTICS_SPEC_FOR_CLAUDE.md: self-hosted analytics on the Siege server -- what Firebase
    // Analytics would do, with no SDK and no third party): the phone's side.
    //
    // log(ev, props) puts an event in a queue kept on disk (<profile>.analytics_q.jsonl, one JSON line each):
    //   {"id": 16 random hex (the server's dedupe key), "ev", "ts": unix s, "sid": the session (8 hex), "b": Diag.BUILD,
    //    "p": props -- only the ones scripts/meta/analytics_events.gd allows that event, numbers or short words}
    // At most MAX_EVENTS (500) / MAX_BYTES (256 KB): when full the oldest go and are counted; the count goes up as a
    // q_dropped event with the next batch. Once the server has said "an":1 (the version check or the status) and the
    // phone has an account, batches of up to 100 go up on their own socket ({"t":"an", ..., "acct", "key", "ev":[...]},
    // compressed like "eco"); the answer {"t":"an", "ok":[ids]} lets those go. No answer (an older server, no
    // connection): the queue stays and it tries again later (eco_sync's RETRY). Sending a batch twice is safe.
    // Sessions: one per time in the foreground -- session_start when the app starts or comes back, session_end when it goes
    // to the background or quits (a session that never ended is closed at the next start, "lost"); clean_session at the
    // next start when the last one ended properly and this start isn't a safe start (crash-free = clean / ended).
    // Script errors are counted (watch_errors) and go up as one error event a session (kind script_error, n): no text.
    // Settings > "Share anonymous usage stats" (settings.analytics, on by default): off clears the queue, sends one
    // opt_out event (nothing else) and logs nothing more; the match and social hellos then carry "an_off" so the server
    // writes nothing for this account either. No device id, ad id, IP, name, chat text or Play Games id is ever logged.
    // 0.31.212 (Kevin: "Set up HeyCatch analytics"): each event logged also goes to HeyCatch (hc: scripts/meta/heycatch.gd),
    // under the same toggle -- off, nothing more goes there either.
    public class Analytics : Node
    {
        public const int BATCH = 100;
        public const double TIMEOUT = 15.0;
        public static readonly GArray RETRY = GArray.Of(3.0, 6.0, 15.0, 30.0, 60.0);
        public const double BEAT = 30.0;                        // s between notes of "still here" (a session that dies still has a length)
        public const double NET_WAIT = 10.0;                    // s session_start waits to learn whether the server answered

        public Profile profile;
        public string url = OS.HasEnvironment("SIEGE_URL") ? OS.GetEnvironment("SIEGE_URL") : Net.DEFAULT_URL;
        public bool auto_start = true;                    // tests turn this off (nothing goes up until start())
        public bool server_ok = false;                    // the server said "an":1
        public int max_events = 500;
        public int max_bytes = 256 * 1024;
        public double timeout = TIMEOUT;
        public GArray queue = new GArray();
        public int bytes = 0;
        public int dropped = 0;
        public string sid = "";
        public bool started = false;
        public string q_path = "";
        public string meta_path = "";
        public GDict meta = new GDict();                            // {"sid", "start", "last", "ended", "dropped", "lvl", "net"}
        public int now_override = -1;
        public GDict _req = new GDict();
        public double _send_at = 0.0;
        public int _fails = 0;
        public double _clock = 0.0;
        public double _beat = 0.0;
        public GDict _pending_start = new GDict();                  // session_start waiting for the network's answer
        public double _pending_at = 0.0;
        public ErrCount _errs = null;
        public HeyCatch hc = null;                       // 0.31.212: HeyCatch (scripts/meta/heycatch.gd) -- each event logged goes there too

        public class ErrCount : Logger
        {
            // script errors this session (the app's watch_errors): only how many, never the text or a path
            public int n = 0;

            public override void _LogError(string _function, string _file, int _line, string _code, string _rationale, bool _editor_notify, int error_type, GArray _bt)
            {
                if (error_type == ERROR_TYPE_SCRIPT)
                    n += 1;
            }
        }

        // ---------------- setup ----------------
        public void Setup(Profile p)
        {
            profile = p;
            var base_ = GD.Str(p.path).GetBasename();
            q_path = base_ + ".analytics_q.jsonl";
            meta_path = base_ + ".analytics.json";
            _Load();
        }

        protected override void _Ready()
        {
            if (auto_start)
                Start();
        }

        public void Start()
        {
            started = true;
        }

        public void WatchErrors()
        {
            // the app: count script errors; each session's count goes up with its session_end (error script_error n)
            if (_errs == null)
            {
                _errs = new ErrCount();
                OS.AddLogger(_errs);
            }
        }

        protected override void _ExitTree()
        {
            if (_errs != null)
            {
                OS.RemoveLogger(_errs);
                _errs = null;
            }
        }

        public bool Enabled()
        {
            return profile == null || (bool)profile.d["settings"].Get("analytics", true);
        }

        public bool HasAccount()
        {
            return profile != null && GD.Str(profile.d["account"].Get("id", "")) != "" && GD.Str(profile.d["account"].Get("key", "")) != "";
        }

        public int Now()
        {
            return now_override >= 0 ? now_override : GD.Int(Time.GetUnixTimeFromSystem());
        }

        public static string Hex(int n)
        {
            return new Crypto().GenerateRandomBytes(n).HexEncode();
        }

        public static GDict HelloFlags(Profile p)
        {
            // what a hello (match or social) adds: "an_off" when this phone opted out
            if (p != null && !(bool)p.d["settings"].Get("analytics", true))
                return new GDict { { "an_off", 1 } };
            return new GDict();
        }

        // ---------------- sessions ----------------
        public void BeginSession(bool cold, bool safe_boot = false, string net = "")
        {
            var prev = meta.Duplicate();
            if (prev.Has("sid") && GD.Str(prev["sid"]) != "")
            {
                if ((bool)prev.Get("ended", false))
                {
                    if (cold && !safe_boot)
                        LogEv("clean_session", new GDict { { "prev_sid", GD.Str(prev["sid"]) } });
                }
                else
                {
                    // the last session never said it ended (killed, crashed, or the phone switched off): its length to its last note
                    LogEv("session_end", new GDict { { "dur_s", GD.Maxi(0, (int)prev.Get("last", 0) - (int)prev.Get("start", 0)) }, { "lost", true } },
                        GD.Str(prev["sid"]), (int)prev.Get("last", Now()));
                }
            }
            sid = Hex(4);
            var lvl = profile != null ? (int)profile.d.Get("level", 1) : 1;
            meta = new GDict { { "sid", sid }, { "start", Now() }, { "last", Now() }, { "ended", false }, { "dropped", dropped }, { "lvl", (int)meta.Get("lvl", lvl) } };
            _SaveMeta();
            _pending_start = new GDict { { "cold", cold }, { "safe_boot", safe_boot } };
            _pending_at = _clock;
            if (net != "")
                SetNet(net == "online");
            if (safe_boot)
                LogEv("error", new GDict { { "kind", "boot_stuck" } });
        }

        public void SetNet(bool online)
        {
            // the version check answered (or didn't): session_start goes in with what it found
            meta["net"] = online ? "online" : "offline";
            if (!_pending_start.IsEmpty())
            {
                var ps = _pending_start;
                _pending_start = new GDict();
                LogEv("session_start", new GDict { { "cold", (bool)ps["cold"] }, { "safe_boot", (bool)ps["safe_boot"] }, { "net", meta["net"] }, { "plat", Platform.Plat() } });
            }
        }

        public void EndSession()
        {
            if (!_pending_start.IsEmpty())
                SetNet(GD.Str(meta.Get("net", "")) == "online");
            if (sid == "" || (bool)meta.Get("ended", false))
                return;
            if (_errs != null && _errs.n > 0)
            {
                LogEv("error", new GDict { { "kind", "script_error" }, { "n", _errs.n } });
                _errs.n = 0;
            }
            LogEv("session_end", new GDict { { "dur_s", GD.Maxi(0, Now() - (int)meta.Get("start", Now())) } });
            meta["ended"] = true;
            meta["last"] = Now();
            _SaveMeta();
        }

        public void NoteLevel(int lvl)
        {
            // a level up since the last look (the server's count arrives with the account, so it's checked whenever it does)
            if (lvl > (int)meta.Get("lvl", lvl))
                LogEv("level_up", new GDict { { "lvl", lvl } });
            if (lvl != (int)meta.Get("lvl", -1))
            {
                meta["lvl"] = lvl;
                _SaveMeta();
            }
        }

        // ---------------- the queue ----------------
        public void LogEv(string ev, GDict props = null, string sid_over = "", int ts_over = -1)
        {
            props ??= new GDict();
            if (!Enabled() && ev != "opt_out")
                return;
            if (!Events.CLIENT.Has(ev))
            {
                GD.PushWarning("analytics: unknown event " + ev);
                return;
            }
            var e = new GDict { { "id", Hex(8) }, { "ev", ev }, { "ts", ts_over >= 0 ? ts_over : Now() }, { "sid", sid_over != "" ? sid_over : sid },
                { "b", Diag.BUILD.Left(40) }, { "p", Events.CleanProps(Events.CLIENT[ev].A, props) } };
            if (hc != null && Enabled())
                hc.Capture(ev, e["p"].D, (int)e["ts"]);           // 0.31.212 (not opt_out: off means nothing more goes there)
            var line = JSON.Stringify(e);
            queue.Append(e);
            bytes += GStr.Length(line) + 1;
            if (queue.Size() > max_events || bytes > max_bytes)
            {
                while (queue.Size() > 1 && (queue.Size() > max_events || bytes > max_bytes))
                {
                    GDict old = queue.PopFront().D;
                    bytes -= GStr.Length(JSON.Stringify(old)) + 1;
                    dropped += 1;
                }
                meta["dropped"] = dropped;
                _SaveMeta();
                _Rewrite();
            }
            else
                _Append(line);
            if (_send_at <= _clock)
                _send_at = _clock + 2.0;                     // (a few together; a retry already waiting keeps its time)
        }

        public void SetEnabled(bool on)
        {
            // Settings: off -- everything waiting goes, one opt_out goes up, nothing more is logged
            if (on)
                return;
            if (hc != null)
                hc.Clear();                               // 0.31.212: HeyCatch's waiting events go too
            queue.Clear();
            bytes = 0;
            dropped = 0;
            meta["dropped"] = 0;
            _pending_start = new GDict();
            _SaveMeta();
            _Rewrite();
            LogEv("opt_out", new GDict());
            _send_at = _clock;
        }

        public void Ack(GArray ids, int dropped_sent = 0)
        {
            var gone = new GDict();
            foreach (var i in ids)
                gone[GD.Str(i)] = true;
            var left = new GArray();
            bytes = 0;
            foreach (var e in queue)
            {
                if (!gone.Has(GD.Str(e["id"])))
                {
                    left.Append(e);
                    bytes += GStr.Length(JSON.Stringify(e)) + 1;
                }
            }
            queue = left;
            dropped = GD.Maxi(0, dropped - dropped_sent);
            meta["dropped"] = dropped;
            _SaveMeta();
            _Rewrite();
        }

        public GDict Batch()
        {
            // the next batch: {"ev": [...], "dropped": the q_dropped count it carries, "qid": its id}
            var evs = new GArray();
            var out_ = new GDict { { "dropped", 0 }, { "qid", "" } };
            if (dropped > 0 && Enabled())
            {
                var q = new GDict { { "id", Hex(8) }, { "ev", "q_dropped" }, { "ts", Now() }, { "sid", sid }, { "b", Diag.BUILD.Left(40) }, { "p", new GDict { { "n", dropped } } } };
                evs.Append(q);
                out_["dropped"] = dropped;
                out_["qid"] = q["id"];
            }
            evs.AppendArray(queue.Slice(0, BATCH - evs.Size()));
            out_["ev"] = evs;
            return out_;
        }

        public void _Append(string line)
        {
            if (q_path == "")
                return;
            var f = FileAccess.Open(q_path, FileAccess.FileExists(q_path) ? FileAccess.READ_WRITE : FileAccess.WRITE);
            if (f == null)
                return;
            f.SeekEnd();
            f.StoreLine(line);
            f.Close();
        }

        public void _Rewrite()
        {
            if (q_path == "")
                return;
            var f = FileAccess.Open(q_path + ".tmp", FileAccess.WRITE);
            if (f == null)
                return;
            foreach (var e in queue)
                f.StoreLine(JSON.Stringify(e));
            f.Close();
            DirAccess.RenameAbsolute(ProjectSettings.GlobalizePath(q_path + ".tmp"), ProjectSettings.GlobalizePath(q_path));
        }

        public void _Load()
        {
            queue = new GArray();
            bytes = 0;
            if (q_path != "" && FileAccess.FileExists(q_path))
            {
                var f = FileAccess.Open(q_path, FileAccess.READ);
                while (f != null && !f.EofReached())
                {
                    var ln = f.GetLine();
                    if (ln == "")
                        continue;
                    Var v = JSON.ParseString(ln);
                    if (v.IsDict && GD.Str(v.Get("id", "")) != "")
                    {
                        queue.Append(v);
                        bytes += GStr.Length(ln) + 1;
                    }
                }
            }
            meta = new GDict();
            if (meta_path != "" && FileAccess.FileExists(meta_path))
            {
                Var m = JSON.ParseString(FileAccess.GetFileAsString(meta_path));
                if (m.IsDict)
                    meta = m.D;
            }
            dropped = (int)meta.Get("dropped", 0);
        }

        public void _SaveMeta()
        {
            if (meta_path == "")
                return;
            var f = FileAccess.Open(meta_path, FileAccess.WRITE);
            if (f != null)
            {
                f.StoreString(JSON.Stringify(meta));
                f.Close();
            }
        }

        // ---------------- sending ----------------
        protected override void _Process(double delta)
        {
            _clock += delta;
            if (!_pending_start.IsEmpty() && _clock - _pending_at > NET_WAIT)
                SetNet(false);                              // (no answer from the server: offline, as far as we know)
            _beat += delta;
            if (_beat >= BEAT && sid != "" && !(bool)meta.Get("ended", false))
            {
                _beat = 0.0;
                meta["last"] = Now();
                _SaveMeta();
            }
            if (!_req.IsEmpty())
            {
                _Poll();
                return;
            }
            if (started && server_ok && HasAccount() && !queue.IsEmpty() && _clock >= _send_at)
                _Send();
        }

        public void _Send()
        {
            var b = Batch();
            var msg = new GDict { { "t", "an" }, { "v", Net.VERSION }, { "build", Diag.BUILD }, { "acct", GD.Str(profile.d["account"]["id"]) }, { "key", GD.Str(profile.d["account"]["key"]) },
                { "ev", b["ev"] } };
            var ws = new WebSocketPeer();
            ws.InboundBufferSize = 1 << 16;
            ws.OutboundBufferSize = 1 << 18;
            if (ws.ConnectToUrl(url) != GD.OK)
            {
                _Failed();
                return;
            }
            _req = new GDict { { "ws", Var.Of(ws) }, { "sent", false }, { "msg", msg }, { "t0", _clock }, { "dropped", (int)b["dropped"] } };
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
            while (ws.GetAvailablePacketCount() > 0)
            {
                var m = Net.Decode(ws.GetPacket());
                if (GD.Str(m.Get("t", "")) == "an" && m.Get("ok", Var.Nil).IsArr)
                {
                    var dr = (int)_req["dropped"];
                    _req = new GDict();
                    if (st == WebSocketPeer.STATE_OPEN)
                        ws.Close();
                    _fails = 0;
                    Ack(m["ok"].A, dr);
                    if (!queue.IsEmpty())
                        _send_at = _clock;                    // more waiting: straight on
                    return;
                }
            }
            if (st == WebSocketPeer.STATE_CLOSED || _clock - (double)_req["t0"] > timeout)
            {
                _req = new GDict();
                if (st != WebSocketPeer.STATE_CLOSED)
                    ws.Close();
                _Failed();
            }
        }

        public void _Failed()
        {
            _fails += 1;
            _send_at = _clock + (double)RETRY[GD.Mini(_fails - 1, RETRY.Size() - 1)];
        }
    }
}
