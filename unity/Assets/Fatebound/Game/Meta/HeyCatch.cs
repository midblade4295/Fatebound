// Ported from godot/scripts/meta/heycatch.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Diag = Fatebound.Game.SiegeDiag;

namespace Fatebound.Game
{
    // 0.31.212 (Kevin: "Set up HeyCatch analytics in this project following https://heycatch.ai/agents.md exactly"):
    // HeyCatch (heycatch.ai), by its native install guide (/agents-native.md, which agents.md sends a native app to). Its
    // ingest speaks PostHog's protocol: a Swift / Kotlin / Flutter app puts PostHog's own SDK on it. A Godot game has none
    // of those, so this is the guide's plain-HTTP route ("Send to HeyCatch directly"): POST <HOST>/batch/ in the standard
    // PostHog capture format, with HeyCatch's write-only ingest token, every event's properties carrying the project key
    // twice -- as heycatch_project_key and as the "project" group ($groups) -- or it belongs to no project.
    //
    // What goes: every event the app logs for our own server (scripts/meta/analytics.gd log_ev hands each one here, its
    // allowed props as they are: numbers and short words), screen views ($screen, $screen_name: the tab, "match",
    // "tutorial"), a purchase granted (purchase_completed, product), and one $identify when the phone first has an account.
    // distinct_id: never the account id (it is half of how the account signs in) -- "fb_" + 20 hex of a SHA-256 of it;
    // before the account exists, a random "anon_" id, merged into the account's by that $identify ($anon_distinct_id).
    // No name, chat text, email, device or ad id. Only while Settings > "Share anonymous usage stats" is on (off: what's
    // waiting goes, nothing more -- the server's own opt_out event isn't sent here). Only on a phone (Android, iOS): a
    // desktop run sends nothing unless HEYCATCH=1 (HEYCATCH=0: never), so tests and tools never reach HeyCatch.
    // Sent promptly (the guide: "events held in a long offline queue can be dropped"): in memory, every FLUSH_S or BATCH
    // events, and at once when the app goes to the background; older than MAX_AGE_S: dropped. 2xx = accepted; 4xx: that
    // batch dropped (it would never be); no answer / 5xx: tried again, RETRY.
    public class HeyCatch : Node
    {
        // HeyCatch's two values, the same for every app (the guide: "safe to ship inside an app binary - not secrets")
        public const string TOKEN = "phc_oiDt6uXiBiEA2aT43SMzMAFE9D4gMVkRP3BtvYRsmHqe";
        public const string HOST = "https://in.heycatch.ai";
        // this game's HeyCatch project (Kevin's dashboard, Install page)
        public const string PROJECT_KEY = "hck_pk_C3_tEJ-DQtuqB8czseyEd74j-gmKBQ4G";

        public const double FLUSH_S = 10.0;
        public const int BATCH = 50;
        public const int MAX_QUEUE = 300;
        public const int MAX_AGE_S = 3600;
        public static readonly GArray RETRY = GArray.Of(5.0, 15.0, 30.0, 60.0, 120.0);
        public const double TIMEOUT = 15.0;

        public Profile profile;
        public string url = HOST + "/batch/";
        public bool force = false;                    // tests: send even on a desktop (to their own url)
        public GArray retry = RETRY.Duplicate();
        public GArray queue = new GArray();
        public int sent_batches = 0;                 // (tests, the verification run)
        public int last_code = -1;
        public string last_screen = "";
        public HTTPRequest _req = null;
        public GArray _busy = new GArray();          // the batch on its way
        public double _clock = 0.0;
        public double _send_at = -1.0;
        public int _fails = 0;
        public bool _flush_next = false;
        public GDict _ids = new GDict();             // {"anon", "ided"} -- kept beside the profile
        public string _ids_path = "";
        public int now_override = -1;

        public void Setup(Profile p)
        {
            profile = p;
            if (p != null && GD.Str(p.path) != "")
            {
                _ids_path = GD.Str(p.path).GetBasename() + ".heycatch.json";
                var t = FileAccess.FileExists(_ids_path) ? FileAccess.GetFileAsString(_ids_path) : "";
                Var v = t != "" ? JSON.ParseString(t) : Var.Nil;
                if (v.IsDict)
                    _ids = v.D;
            }
        }

        protected override void _Ready()
        {
            _req = new HTTPRequest();
            _req.Timeout = TIMEOUT;
            _req.UseThreads = false;
            AddChild(_req);
            _req.RequestCompleted += _OnDone;
        }

        public static bool OnPhone()
        {
            return GArray.Of("Android", "iOS").Has(OS.GetName());          // (the real one: a test's Platform.forced sends nothing)
        }

        public bool Active()
        {
            if (OS.GetEnvironment("HEYCATCH") == "0")
                return false;
            if (!(force || OnPhone() || OS.GetEnvironment("HEYCATCH") == "1"))
                return false;
            return profile == null || (bool)profile.d["settings"].Get("analytics", true);
        }

        public int Now()
        {
            return now_override >= 0 ? now_override : GD.Int(Time.GetUnixTimeFromSystem());
        }

        // ---------------- who ----------------
        public string DistinctId()
        {
            var acct = _Acct();
            if (acct != "")
                return "fb_" + _Sha(acct).Left(20);
            if (GD.Str(_ids.Get("anon", "")) == "")
            {
                _ids["anon"] = "anon_" + new Crypto().GenerateRandomBytes(10).HexEncode();
                _SaveIds();
            }
            return GD.Str(_ids["anon"]);
        }

        public string _Acct()
        {
            if (profile == null)
                return "";
            return GD.Str(profile.d.Get("account", new GDict()).Get("id", ""));
        }

        public static string _Sha(string s)
        {
            var h = new HashingContext();
            h.Start(HashingContext.HASH_SHA256);
            h.Update(("fatebound-heycatch:" + s).ToUtf8Buffer());
            return h.Finish().HexEncode();
        }

        public void _CheckIdentity()
        {
            // the phone has an account now (or a different one): one $identify -- the anonymous id's events join it
            var acct = _Acct();
            if (acct == "")
                return;
            var me = DistinctId();
            if (GD.Str(_ids.Get("ided", "")) == me)
                return;
            var p = new GDict { { "$set", new GDict { { "plat", Platform.Plat() }, { "build", Diag.BUILD.Left(40) } } } };
            if (GD.Str(_ids.Get("anon", "")) != "")
                p["$anon_distinct_id"] = GD.Str(_ids["anon"]);
            _ids["ided"] = me;
            _SaveIds();
            _Add("$identify", p, Now());
        }

        public void _SaveIds()
        {
            if (_ids_path == "")
                return;
            var f = FileAccess.Open(_ids_path, FileAccess.WRITE);
            if (f != null)
            {
                f.StoreString(JSON.Stringify(_ids));
                f.Close();                                  // (Godot closes it as `f` goes out of scope)
            }
        }

        // ---------------- events ----------------
        public void Capture(string ev, GDict props = null, int ts = -1)
        {
            // a business event (the same name and props the app logs for our own server)
            props ??= new GDict();
            if (!Active())
                return;
            _CheckIdentity();
            _Add(ev, props, ts >= 0 ? ts : Now());
        }

        public void Screen(string screen_name)
        {
            // a screen appeared (the same one again in a row: nothing)
            if (!Active() || screen_name == "" || screen_name == last_screen)
                return;
            last_screen = screen_name;
            _CheckIdentity();
            _Add("$screen", new GDict { { "$screen_name", screen_name } }, Now());
        }

        public void _Add(string ev, GDict props, int ts)
        {
            var p = props.Duplicate();
            p["heycatch_project_key"] = PROJECT_KEY;
            p["$groups"] = new GDict { { "project", PROJECT_KEY } };
            p["$lib"] = "fatebound-godot";
            p["$app_version"] = Diag.BUILD.Left(40);
            p["$os"] = Platform.OsName();
            queue.Append(new GDict { { "event", ev }, { "distinct_id", DistinctId() }, { "timestamp", _Iso(ts) }, { "t", ts }, { "properties", p } });
            while (queue.Size() > MAX_QUEUE)
                queue.PopFront();
            if (queue.Size() >= BATCH)
                _send_at = _clock;
            else if (_send_at < 0.0)
                _send_at = _clock + FLUSH_S;
        }

        public static string _Iso(int ts)
        {
            return Time.GetDatetimeStringFromUnixTime(ts) + "Z";         // (ISO 8601, UTC)
        }

        public void Flush()
        {
            // the app is going to the background: what's waiting goes now (this frame -- the next may be a while)
            if (queue.IsEmpty())
                return;
            if (_busy.IsEmpty())
                _Send();
            else
                _flush_next = true;                       // (straight after the batch on its way)
        }

        public void Clear()
        {
            // Settings: the statistics turned off -- nothing waiting goes
            queue.Clear();
            _send_at = -1.0;
        }

        // ---------------- sending ----------------
        protected override void _Process(double delta)
        {
            _clock += delta;
            if (_busy.IsEmpty() && _send_at >= 0.0 && _clock >= _send_at)
                _Send();
        }

        public void _Send()
        {
            _send_at = -1.0;
            var cut = Now() - MAX_AGE_S;
            queue = queue.Filter(e => (int)e["t"] >= cut);
            if (queue.IsEmpty() || _req == null || !Active())
                return;
            _busy = queue.Slice(0, BATCH);
            var batch = new GArray();
            foreach (var e in _busy)
                batch.Append(new GDict { { "event", e["event"] }, { "distinct_id", e["distinct_id"] }, { "timestamp", e["timestamp"] }, { "properties", e["properties"] } });
            var body = JSON.Stringify(new GDict { { "api_key", TOKEN }, { "batch", batch }, { "sent_at", _Iso(Now()) } });
            if (_req.Request(url, new[] { "Content-Type: application/json" }, HTTPClient.METHOD_POST, body) != GD.OK)
            {
                _busy = new GArray();
                _Retry();
            }
        }

        public void _OnDone(int result, int code, string[] _headers, byte[] _body)
        {
            last_code = code;
            Func<Var, bool> keep = e => !_busy.Any(b => ReferenceEquals(b.Obj, e.Obj));
            if (result == HTTPRequest.RESULT_SUCCESS && code >= 200 && code < 300)
            {
                queue = queue.Filter(keep);
                sent_batches += 1;
                _fails = 0;
            }
            else if (result == HTTPRequest.RESULT_SUCCESS && code >= 400 && code < 500 && code != 408 && code != 429)
            {
                queue = queue.Filter(keep);               // (refused as it is: it never would be accepted)
                GD.PushWarning(GD.Fmt("heycatch: batch refused (%d)", code));
            }
            else
            {
                _busy = new GArray();
                _Retry();
                return;
            }
            _busy = new GArray();
            if (!queue.IsEmpty())
                _send_at = _clock + (_flush_next ? 0.0 : (queue.Size() >= BATCH ? 0.5 : FLUSH_S));
            _flush_next = false;
        }

        public void _Retry()
        {
            _fails += 1;
            _send_at = _clock + (double)retry[GD.Mini(_fails - 1, retry.Size() - 1)];
        }
    }
}
