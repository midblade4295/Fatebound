// Ported from godot/scripts/meta/game_services.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;

namespace Fatebound.Game
{
    // 0.31.130 (the iOS port, IOS_PORT_SPEC_FOR_CLAUDE.md §1): which store's game services the app uses. Both have one face
    // (signals changed / note / ask / restored; state, player, why, achievements; setup, active, sign_in, back_up_now,
    // choose, pending_choice, on_pause, on_resume, signed_in, show_achievements, last_backup), so the app and Settings only
    // ever talk to what this hands back:
    //   Android (and the desktop, where nothing is active)  scripts/meta/play_games.gd    Google Play Games, unchanged
    //   iOS                                                 scripts/meta/game_center.gd   Game Center
    // Achievements are counted the same for both (achievements.gd, by key); each service maps a key to its own id.
    public static class GameServices
    {
        public static Type ScriptFor(string store = "")
        {
            return (store != "" ? store : Platform.Store()) == "appstore" ? typeof(GameCenter) : typeof(PlayGames);
        }

        public static Node Make(string store = "")
        {
            return ScriptFor(store) == typeof(GameCenter) ? (Node)new GameCenter() : new PlayGames();
        }

        public static bool IsGameCenter(object s)
        {
            return s != null && s is GameCenter;
        }
    }

    /// <summary>(The port: the "one face" above as a C# interface -- GDScript calls it duck-typed. PlayGames and GameCenter
    /// implement it; a caller holding the Node that Make() returns casts to it. Game Center's extras -- signed, identity,
    /// team_id -- are on GameCenter itself.)</summary>
    public interface IGameServices
    {
        event Action Changed;
        event Action<string, bool> Note;
        event Action<GDict, GDict> Ask;
        event Action Restored;
        string state { get; }
        string player { get; }
        string why { get; }
        Achievements achievements { get; }
        void Setup(Profile p);
        bool Active();
        void SignIn();
        void BackUpNow();
        void Choose(bool keep_cloud);
        GDict PendingChoice();
        void OnPause();
        void OnResume();
        bool SignedIn();
        void ShowAchievements();
        int LastBackup();
    }
}
