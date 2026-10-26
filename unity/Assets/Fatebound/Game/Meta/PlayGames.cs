// Ported from godot/scripts/meta/play_games.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;

namespace Fatebound.Game
{
    // 0.31.102: Google Play Games sign-in and the progress kept in the player's Google account (Kevin: "Google play account
    // linking to the game"). Only the Play app has the plugin (addons/GodotPlayGameServices, packed by the Gradle preset
    // once the Play Games project's Game ID is set); everywhere else `active()` is false and Settings says so.
    //
    // Signing in: Play Games v2 signs the player in by itself at start when they have Play Games (isAuthenticated); SIGN
    // IN in Settings asks Google to (signIn). There is no sign-out in Play Games v2 (the Play Games app owns that).
    //
    // The copy (one Saved Game, SLOT): the profile as JSON, gzipped and base64'd (ASCII, so the plugin's JSON hands the
    // bytes back intact), with a stamp, the time, the phone and a summary. The profile remembers the stamp of the copy it
    // is in step with and whether it changed since (Profile.save marks it). Signed in, the game reads the copy first and
    // never writes before it has:
    //   - no copy yet                          -> this phone's progress goes up (the first link)
    //   - the copy is the one we're in step with -> ours goes up when it has changed
    //   - another phone wrote since, and this one hasn't changed (or is a new install, never linked) -> Google Play's
    //     replaces ours
    //   - both changed (or a second phone with its own progress links the account) -> the player chooses (ask):
    //     USE GOOGLE PLAY'S or KEEP THIS PHONE'S (which then goes up). Nothing is ever replaced without that choice.
    // Then ours goes up at most every UPLOAD_EVERY s while it changes, when the app goes to the background, and on BACK UP
    // NOW. A copy written by a newer version of the game (v > CLOUD_VERSION) is never overwritten or read.
    public class PlayGames : Node, IGameServices
    {
        public const string PLUGIN = "GodotPlayGameServices";
        public const string SLOT = "fatebound-profile";
        public const string MAGIC = "FB1:";
        public const double WAIT = 30.0;                    // s for Google to answer before we call it unreachable
        public const double UPLOAD_EVERY = 120.0;           // s between uploads while the progress keeps changing

        public event Action Changed;                        // state / name / last backup changed: Settings redraws
        public event Action<string, bool> Note;
        public event Action<GDict, GDict> Ask;              // both sides have progress: the app asks which to keep
        public event Action Restored;                       // Google Play's copy replaced this phone's: the app rebuilds its screens

        public Profile profile;
        public object plugin = null;                        // the Android singleton, or a test double with the same calls and signals
        public string device = "";                          // this phone's model, written into the copy
        public string state = "off";                        // off | out | signing | checking | synced | ask | error
        public string player = "";                          // the Play Games name
        public string why = "";                             // the last error, for Settings
        public GDict _cloud = new GDict();                  // Google Play's copy while the player chooses
        public string _wait = "";                           // what Google owes us: "sign" | "load" | "save"
        public double _wait_t = 0.0;
        public double _since = 0.0;                         // s since the last upload started
        public string _up_stamp = "";                       // the stamp of the upload in flight
        public int _up_saves = 0;                           // profile.saves when it started
        public bool _manual = false;                        // the player pressed SIGN IN / BACK UP NOW (say how it went)
        public Achievements achievements = new Achievements();  // 0.31.119: Play Games achievements, sent while signed in
        public double _ach_clock = 0.0;
        public const double ACH_EVERY = 5.0;                // s between looks at the achievements (only what changed is sent)

        public static bool Supported()
        {
            return Engine.HasSingleton(PLUGIN);
        }

        public void Setup(Profile p, object plug = null)
        {
            profile = p;
            plugin = plug;
            if (plugin == null && Supported())
            {
                plugin = Engine.GetSingleton(PLUGIN);
                GObject.Call(plugin, "initialize");
            }
            if (plugin == null)
                return;
            device = OS.GetModelName();
            GObject.Connect(plugin, "userAuthenticated", (Action<bool>)_OnAuth);
            GObject.Connect(plugin, "currentPlayerLoaded", (Action<string>)_OnPlayer);
            GObject.Connect(plugin, "gameLoaded", (Action<string>)_OnLoaded);
            GObject.Connect(plugin, "gameSaved", (Action<bool, string, string>)_OnSaved);
            GObject.Connect(plugin, "conflictEmitted", (Action<string>)_OnConflict);
            _State("signing");
            _AskGoogle("sign");
            GObject.Call(plugin, "isAuthenticated");
        }

        public bool Active()
        {
            return plugin != null;
        }

        public int LastBackup()
        {
            return profile != null ? (int)profile.d["cloud"].Get("at", 0) : 0;
        }

        // ---------------- the player's buttons ----------------
        public void SignIn()
        {
            if (plugin == null || GArray.Of("signing", "checking").Has(state))
                return;
            _manual = true;
            _State("signing");
            _AskGoogle("sign");
            GObject.Call(plugin, "signIn");
        }

        public void BackUpNow()
        {
            if (plugin == null || _wait != "")
                return;
            _manual = true;
            if (state == "synced")
                _Upload();
            else if (state == "error")
                _Check();                           // read the copy again first: never write blind
            else if (state == "out")
                SignIn();
        }

        public void Choose(bool keep_cloud)
        {
            // the answer to `ask`
            if (state != "ask" || _cloud.IsEmpty())
                return;
            var c = _cloud;
            _cloud = new GDict();
            if (keep_cloud)
                _Restore(c);
            else
            {
                _State("checking");
                _Upload();
            }
        }

        public GDict PendingChoice()
        {
            // Settings' CHOOSE re-opens the question
            return state == "ask" ? new GDict { { "here", profile.Summary() }, { "cloud", _CloudSide(_cloud) } } : new GDict();
        }

        public void OnPause()
        {
            if (state == "synced" && (bool)profile.d["cloud"]["dirty"] && _wait == "")
                _Upload();
        }

        public void OnResume()
        {
            if (state == "error" && _wait == "")
                _Check();
        }

        public bool SignedIn()
        {
            return plugin != null && GArray.Of("checking", "synced", "ask").Has(state);
        }

        public void ShowAchievements()
        {
            // 0.31.119: Google's own achievements screen
            if (SignedIn())
                GObject.Call(plugin, "showAchievements");
        }

        protected override void _Process(double delta)
        {
            if (plugin == null)
                return;
            _ach_clock += delta;
            if (_ach_clock >= ACH_EVERY)
            {
                _ach_clock = 0.0;
                if (SignedIn())
                    achievements.Sync(profile, plugin);
            }
            _since += delta;
            if (_wait != "")
            {
                _wait_t += delta;
                if (_wait_t > WAIT)
                {
                    var what = _wait;
                    _wait = "";
                    if (what == "sign")
                        _Fail("out", "Google Play didn't answer");
                    else
                        _Fail("error", "Google Play saves didn't answer");
                }
                return;
            }
            if (state == "synced" && (bool)profile.d["cloud"]["dirty"] && _since > UPLOAD_EVERY)
                _Upload();
        }

        // ---------------- Google's answers ----------------
        public void _OnAuth(bool ok)
        {
            if (_wait == "sign")
                _wait = "";
            if (!ok)
            {
                _Fail("out", _manual ? "Not signed in to Google Play" : "");
                return;
            }
            GObject.Call(plugin, "loadCurrentPlayer", false);
            _Check();
        }

        public void _OnPlayer(string json)
        {
            Var v = JSON.ParseString(json);
            if (v.IsDict)
            {
                player = GD.Str(v.D.Get("displayName", ""));
                Changed?.Invoke();
            }
        }

        public void _Check()
        {
            _State("checking");
            _AskGoogle("load");
            GObject.Call(plugin, "loadGame", SLOT, false);
        }

        public void _OnLoaded(string json)
        {
            if (_wait != "load")
                return;
            _wait = "";
            Var v = JSON.ParseString(json);
            if (v.IsNull)
            {
                _Upload();                         // no copy yet: the first link
                return;
            }
            var c = Decode(v.IsDict ? v.Get("content", new GArray()) : (Var)new GArray());
            if (c.IsEmpty())
            {
                _Fail("error", "The Google Play save couldn't be read");
                return;
            }
            if ((int)c.Get("v", 0) > Profile.CLOUD_VERSION)
            {
                _Fail("error", "Your Google Play save is from a newer version: update the game");
                return;
            }
            _Decide(c);
        }

        public void _Decide(GDict c)
        {
            GDict here = profile.d["cloud"].D;
            if (GD.Str(c.Get("stamp", "")) == GD.Str(here["stamp"]))
            {
                _State("synced");
                if ((bool)here["dirty"])
                    _Upload();
                else
                    _DoneManual("Your progress is backed up to Google Play");
                return;
            }
            if ((GD.Str(here["stamp"]) != "" && !(bool)here["dirty"]) || (GD.Str(here["stamp"]) == "" && profile.IsFresh()))
            {
                _Restore(c);
                return;
            }
            _cloud = c;
            _State("ask");
            Ask?.Invoke(profile.Summary(), _CloudSide(c));
        }

        public void _Restore(GDict c)
        {
            if (profile.RestoreCloud(c.Get("profile"), GD.Str(c.Get("stamp", ""))))
            {
                _State("synced");
                Note?.Invoke("Progress restored from Google Play", true);
                Restored?.Invoke();
            }
            else
                _Fail("error", "The Google Play save couldn't be read");
        }

        public void _Upload()
        {
            _up_stamp = GD.Fmt("%d-%06d", profile.Now(), GD.Randi() % 1000000);
            _up_saves = profile.saves;
            _since = 0.0;
            GDict s = profile.Summary();
            var desc = GD.Fmt("Level %d · %d wins", (int)s["level"], (int)s["wins"]);
            _AskGoogle("save");
            GObject.Call(plugin, "saveGame", SLOT, desc, Var.Of(Encode(profile.CloudPayload(_up_stamp, device))), 0, profile.Now());
        }

        public void _OnSaved(bool ok, string _name, string _desc)
        {
            if (_wait != "save")
                return;
            _wait = "";
            if (!ok)
            {
                _Fail("error", "Google Play couldn't save");
                return;
            }
            profile.d["cloud"] = new GDict { { "stamp", _up_stamp }, { "dirty", profile.saves != _up_saves }, { "at", profile.Now() } };
            profile.Save(false);
            _State("synced");
            _DoneManual("Backed up to Google Play");
        }

        public void _OnConflict(string _json)
        {
            // two phones wrote at once: Google keeps the newest (the policy); read it again before writing anything
            if (GArray.Of("load", "save").Has(_wait))
            {
                _wait = "";
                _Check();
            }
        }

        // ---------------- helpers ----------------
        public void _AskGoogle(string what)
        {
            _wait = what;
            _wait_t = 0.0;
        }

        public void _State(string s)
        {
            state = s;
            if (s != "error" && s != "out")
                why = "";
            Changed?.Invoke();
        }

        public void _Fail(string s, string text)
        {
            state = s;
            why = text;
            if (text != "" && _manual)              // (on its own -- at start, offline -- it only shows in Settings)
                Note?.Invoke(text, false);
            _manual = false;
            Changed?.Invoke();
        }

        public void _DoneManual(string text)
        {
            if (_manual)
                Note?.Invoke(text, true);
            _manual = false;
        }

        public static GDict _CloudSide(GDict c)
        {
            GDict out_ = c.Get("sum", new GDict()).IsDict ? c.Get("sum", new GDict()).D.Duplicate() : new GDict();
            out_["device"] = GD.Str(c.Get("device", ""));
            out_["at"] = (int)c.Get("at", 0);
            return out_;
        }

        public static byte[] Encode(GDict payload)
        {
            var raw = JSON.Stringify(payload).ToUtf8Buffer().Compress(FileAccess.COMPRESSION_GZIP);
            return (MAGIC + Marshalls.RawToBase64(raw)).ToAsciiBuffer();
        }

        public static GDict Decode(Var content)
        {
            // the bytes as the plugin's JSON gives them (an array of numbers), or a PackedByteArray
            var bytes = new byte[0];
            if (content.Is<byte[]>())
                bytes = content.As<byte[]>();
            else if (content.IsArr)
            {
                var l = new List<byte>();
                foreach (var x in content)
                    l.Add((byte)(GD.Long(x) & 0xff));
                bytes = l.ToArray();
            }
            var txt = bytes.GetStringFromAscii();
            if (!txt.BeginsWith(MAGIC))
                return new GDict();
            var raw = Marshalls.Base64ToRaw(txt.Substr(MAGIC.Length));
            if (raw.Length == 0)
                return new GDict();
            var json = raw.DecompressDynamic(-1, FileAccess.COMPRESSION_GZIP).GetStringFromUtf8();
            Var v = JSON.ParseString(json);
            return v.IsDict && v.D.Has("profile") ? v.D : new GDict();
        }

        // ---- IGameServices (the face game_services.gd describes)
        string IGameServices.state => state;
        string IGameServices.player => player;
        string IGameServices.why => why;
        Achievements IGameServices.achievements => achievements;
        void IGameServices.Setup(Profile p) => Setup(p);
    }
}
