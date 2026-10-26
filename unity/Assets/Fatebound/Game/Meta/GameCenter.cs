// Ported from godot/scripts/meta/game_center.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using GcIds = Fatebound.Game.GcAchievementIds;

namespace Fatebound.Game
{
    // 0.31.130 (the iOS port, IOS_PORT_SPEC_FOR_CLAUDE.md §4): Game Center sign-in and achievements, with the same face as
    // play_games.gd (Google Play Games) so the app and Settings talk to either (scripts/meta/game_services.gd picks one).
    // The native side is GodotApplePlugins' GameCenterManager (addons/GodotApplePluginsGameCenter, a GDExtension in the iOS
    // build only), wrapped by Native below; tests hand setup() a double with Native's calls and signals.
    //
    // Signing in: Apple signs the player in by itself at start (its own banner, or its sheet the first time). There is no
    // in-app sign-in once a player has declined -- Apple's rule -- so Settings says where: iOS Settings > Game Center.
    // Achievements: the 18 of achievements.gd with Apple's ids (gc_achievement_ids.gd), as percentages (Apple has no
    // incremental kind), checked every ACH_EVERY s while signed in; only what changed is reported (GameKit itself keeps a
    // report made offline and sends it later).
    // The progress: iOS v1 keeps no cloud copy (no GameKit saved games): the server account holds it, moved with a transfer
    // code, and Game Center's teamPlayerID links the account so a reinstall gets it back (signed -> the app). So `ask` and
    // `restored` exist only for the same face and are never emitted.
    public class GameCenter : Node, IGameServices
    {
        public const double ACH_EVERY = 5.0;                 // s between looks at the achievements (only what changed is sent)

        public event Action Changed;                        // state / name changed: Settings redraws
        public event Action<string, bool> Note;
        public event Action<GDict, GDict> Ask;              // (never: no cloud copy on iOS v1)
        public event Action Restored;                       // (never)
        public event Action<string> Signed;                 // signed in to Game Center: the app links the server account to this player

        public Profile profile;
        public Native plugin = null;                        // Native, or a test double with the same calls and signals
        public string state = "off";                        // off | out | signing | synced  (play_games.gd's names; "synced" = signed in)
        public string player = "";                          // the Game Center alias
        public string team_id = "";                         // teamPlayerID (stays on the phone; the server keeps only a hash of it)
        public string why = "";                             // the last error (diagnostics; Settings shows where to sign in instead)
        public Achievements achievements = new Achievements();
        public int reported = 0;                            // achievements reported this run (diagnostics, tests)
        public double _ach_clock = 0.0;
        public bool _manual = false;

        // GodotApplePlugins' Game Center classes, reached through ClassDB (the names don't exist outside the iOS build)
        public class Native
        {
            public event Action<bool> Authenticated;
            public event Action<string> Failed;
            public object gc = null;

            public Native()
            {
                gc = ClassDB.Instantiate("GameCenterManager");
                GObject.Connect(gc, "authentication_result", (Action<Var>)(ok => Authenticated?.Invoke((bool)ok)));
                GObject.Connect(gc, "authentication_error", (Action<Var>)(m => Failed?.Invoke(GD.Str(m))));
            }

            public void Authenticate()
            {
                GObject.Call(gc, "authenticate");
            }

            public object _Local()
            {
                return gc != null ? GObject.Get(gc, "local_player").Obj : null;
            }

            public string PlayerAlias()
            {
                var lp = _Local();
                return lp != null ? GD.Str(GObject.Get(lp, "alias")) : "";
            }

            public string TeamPlayerId()
            {
                var lp = _Local();
                return lp != null ? GD.Str(GObject.Get(lp, "team_player_id")) : "";
            }

            public void Report(GArray list, Action<Var> cb)
            {
                // list: [[id, percent], ...] -> one GKAchievement.report_achievement; cb(error or null)
                var arr = new GArray();
                foreach (var it in list)
                {
                    Var a = ClassDB.ClassCallStatic("GKAchievement", "make", GD.Str(it[0]));
                    if (a.IsNull)
                        continue;
                    GObject.Set(a, "percent_complete", (double)it[1]);
                    GObject.Set(a, "shows_completion_banner", true);
                    arr.Append(a);
                }
                if (!arr.IsEmpty())
                    ClassDB.ClassCallStatic("GKAchievement", "report_achievement", arr, cb);
            }

            public void ShowAchievements()
            {
                ClassDB.ClassCallStatic("GKGameCenterViewController", "show_type", 2);   // State.ACHIEVEMENTS
            }

            public void Identity(Action<Var, Var> cb)
            {
                // Apple's identity signature (cb(data: Dictionary {url, data, salt, timestamp}, error)): the server checks it
                var lp = _Local();
                if (lp != null)
                {
                    // (GameKit may answer off the main thread: the game hears it on the main one)
                    GObject.Call(lp, "fetch_items_for_identity_verification_signature", (Action<Var, Var>)((d, e) => SceneTree.Current?.Defer(() => cb(d, e))));
                }
            }
        }

        public static bool Supported()
        {
            return Platform.HasClass(Platform.GAMECENTER_CLASS);
        }

        public void Setup(Profile p, Native plug = null)
        {
            profile = p;
            plugin = plug;
            if (plugin == null && Supported())
                plugin = new Native();
            if (plugin == null)
                return;
            achievements.ids = GcIds.IDS;
            plugin.Authenticated += _OnAuth;
            plugin.Failed += (string m) => why = m;
            _State("signing");
            plugin.Authenticate();
        }

        public bool Active()
        {
            return plugin != null;
        }

        public int LastBackup()
        {
            return 0;                                          // (no cloud copy on iOS v1)
        }

        // ---------------- the player's buttons (play_games.gd's face) ----------------
        public void SignIn()
        {
            // Apple shows its sheet again only while it still allows it; otherwise iOS Settings > Game Center
            if (plugin == null || state == "signing")
                return;
            _manual = true;
            _State("signing");
            plugin.Authenticate();
        }

        public void BackUpNow()
        {
            if (state == "out")
                SignIn();
        }

        public void Choose(bool _keep_cloud)
        {
        }

        public GDict PendingChoice()
        {
            return new GDict();
        }

        public void OnPause()
        {
        }

        public void OnResume()
        {
            // back from iOS Settings: signed in there? (GameKit tells the handler too; asking again is harmless)
            if (plugin != null && state == "out")
                plugin.Authenticate();
        }

        public bool SignedIn()
        {
            return plugin != null && state == "synced";
        }

        public void ShowAchievements()
        {
            // Apple's own achievements screen
            if (SignedIn())
                plugin.ShowAchievements();
        }

        public void Identity(Action<Var, Var> cb)
        {
            if (SignedIn())
                plugin.Identity(cb);
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
                    SyncAchievements();
            }
        }

        public int SyncAchievements()
        {
            var list = new GArray();
            achievements.SyncPercent(profile, (string id, double pct) => list.Append(GArray.Of(id, pct)));
            if (!list.IsEmpty())
            {
                reported += list.Size();
                plugin.Report(list, (Var err) =>
                {
                    if (!err.IsNull)
                        GD.Print(GD.Fmt("game_center: report: %s", GD.Str(err)));
                });
            }
            return list.Size();
        }

        // ---------------- Apple's answers ----------------
        public void _OnAuth(bool ok)
        {
            if (!ok)
            {
                state = "out";
                player = "";
                if (_manual)
                    Note?.Invoke("Sign in from iOS Settings > Game Center", false);
                _manual = false;
                Changed?.Invoke();
                return;
            }
            player = GD.Str(plugin.PlayerAlias());
            team_id = GD.Str(plugin.TeamPlayerId());
            why = "";
            var was = state;
            _State("synced");
            if (_manual)
                Note?.Invoke("Signed in to Game Center", true);
            _manual = false;
            if (was != "synced" && team_id != "")
                Signed?.Invoke(team_id);
        }

        public void _State(string s)
        {
            state = s;
            Changed?.Invoke();
        }

        // ---- IGameServices (the face game_services.gd describes)
        string IGameServices.state => state;
        string IGameServices.player => player;
        string IGameServices.why => why;
        Achievements IGameServices.achievements => achievements;
        void IGameServices.Setup(Profile p) => Setup(p);
    }
}
