// Ported from godot/scripts/meta/achievements.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Eco = Fatebound.Game.Economy;
using Ids = Fatebound.Game.PlayAchievementIds;

namespace Fatebound.Game
{
    // 0.31.119 (Kevin: "Do all" -- 8. Play Games achievements): what the game reports to Google Play Games. Each achievement
    // reads the profile -- the account the server keeps (0.31.108), so they can't be faked by editing a save -- and is sent
    // through the Play Games plugin (scripts/meta/play_games.gd) while the player is signed in: an "incremental" one as its
    // steps (setAchievementSteps: never goes back, so sending the total again is harmless), a standard one unlocked once
    // its goal is met. Only what changed since the last send goes out. The ids are Play Console's
    // (scripts/meta/play_achievement_ids.gd, empty until they're made there -- see godot/PLAY_ACHIEVEMENTS_HANDOFF.md).
    // 0.31.130 (the iOS port): the same list goes to Game Center (scripts/meta/game_center.gd) with Apple's ids
    // (gc_achievement_ids.gd) as percentages -- sync_percent; what is counted and when it is sent is the same code.
    public class Achievements
    {
        // key, name, description (as Play Console shows them), what's counted, the goal, incremental (steps) or not, the icon
        public static readonly GArray LIST = GArray.Of(
            new GDict { { "key", "welcome" }, { "name", "Welcome to the Siege" }, { "desc", "Finish the tutorial." }, { "stat", "tutorial" }, { "n", 1 }, { "inc", false }, { "icon", "castle" }, { "xp", 5 } },
            new GDict { { "key", "first_blood" }, { "name", "First Blood" }, { "desc", "Knock out an enemy." }, { "stat", "kills" }, { "n", 1 }, { "inc", false }, { "icon", "skull" }, { "xp", 5 } },
            new GDict { { "key", "first_victory" }, { "name", "First Victory" }, { "desc", "Win a match." }, { "stat", "wins" }, { "n", 1 }, { "inc", false }, { "icon", "trophy" }, { "xp", 10 } },
            new GDict { { "key", "kings_rescue" }, { "name", "Long Live the King" }, { "desc", "Carry your King home from the enemy dungeon." }, { "stat", "rescues" }, { "n", 1 }, { "inc", false }, { "icon", "crown" }, { "xp", 10 } },
            new GDict { { "key", "many_hats" }, { "name", "Many Hats" }, { "desc", "Play a match as each of the 7 classes." }, { "stat", "classes" }, { "n", 7 }, { "inc", true }, { "icon", "helmet" }, { "xp", 20 } },
            new GDict { { "key", "fattening" }, { "name", "Fattening Season" }, { "desc", "Feed 25 fish to the enemy King." }, { "stat", "fed" }, { "n", 25 }, { "inc", true }, { "icon", "fish" }, { "xp", 15 } },
            new GDict { { "key", "lumberjack" }, { "name", "Lumberjack" }, { "desc", "Gather 500 wood or stone." }, { "stat", "gathered" }, { "n", 500 }, { "inc", true }, { "icon", "stall" }, { "xp", 15 } },
            new GDict { { "key", "gatecrasher" }, { "name", "Gatecrasher" }, { "desc", "Deal 10,000 damage to enemy gates." }, { "stat", "gates" }, { "n", 100 }, { "inc", true }, { "icon", "swords" }, { "xp", 20 } },
            new GDict { { "key", "heavy_lifting" }, { "name", "Heavy Lifting" }, { "desc", "Help lift your King 50 times." }, { "stat", "lifts" }, { "n", 50 }, { "inc", true }, { "icon", "crown" }, { "xp", 20 } },
            new GDict { { "key", "centurion" }, { "name", "Centurion" }, { "desc", "Knock out 100 enemies." }, { "stat", "kills" }, { "n", 100 }, { "inc", true }, { "icon", "skull" }, { "xp", 20 } },
            new GDict { { "key", "relentless" }, { "name", "Relentless" }, { "desc", "Win 5 matches in a row." }, { "stat", "best_streak" }, { "n", 5 }, { "inc", false }, { "icon", "banner" }, { "xp", 30 } },
            new GDict { { "key", "unstoppable" }, { "name", "Unstoppable" }, { "desc", "Knock out 5 enemies in one burst." }, { "stat", "best_multi" }, { "n", 5 }, { "inc", false }, { "icon", "swords" }, { "xp", 40 } },
            new GDict { { "key", "bodyguard" }, { "name", "Royal Bodyguard" }, { "desc", "Rescue your King 25 times." }, { "stat", "rescues" }, { "n", 25 }, { "inc", true }, { "icon", "crown" }, { "xp", 40 } },
            new GDict { { "key", "seasoned" }, { "name", "Seasoned" }, { "desc", "Reach level 20." }, { "stat", "level" }, { "n", 20 }, { "inc", true }, { "icon", "banner" }, { "xp", 40 } },
            new GDict { { "key", "siege_lord" }, { "name", "Siege Lord" }, { "desc", "Win 50 matches." }, { "stat", "wins" }, { "n", 50 }, { "inc", true }, { "icon", "castle" }, { "xp", 60 } },
            new GDict { { "key", "slayer" }, { "name", "Slayer of Thousands" }, { "desc", "Knock out 1,000 enemies." }, { "stat", "kills" }, { "n", 1000 }, { "inc", true }, { "icon", "skull" }, { "xp", 80 } },
            new GDict { { "key", "legend" }, { "name", "Legend of the Siege" }, { "desc", "Win 250 matches." }, { "stat", "wins" }, { "n", 250 }, { "inc", true }, { "icon", "trophy" }, { "xp", 100 } }
        );

        // 0.31.188: gone from the game but published -- Play Console and Game Center keep them (Kevin can hide them there); this
        // app no longer reports them. "master_smith", Master Smith: forge a weapon to 3 stars (0.31.119-0.31.187, the Forge).
        public static readonly GArray RETIRED = GArray.Of("master_smith");

        public GDict sent = new GDict();                 // key -> the value last sent (this run)
        public GDict ids = Ids.IDS;                      // (tests put their own)

        public static int Value(Profile profile, string stat)
        {
            GDict d = profile.d;
            switch (stat)
            {
                case "tutorial":
                    return (bool)d.Get("tutorial_done", false) ? 1 : 0;
                case "classes":
                    {
                        var n = 0;
                        foreach (var c in Eco.CLASSES)
                        {
                            if ((int)d["stats"].Get("main_" + c, 0) > 0)
                                n += 1;
                        }
                        return n;
                    }
                case "level":
                    return (int)d.Get("level", 1);
            }
            return (int)d["stats"].Get(stat, 0);
        }

        public string IdOf(string key)
        {
            return GD.Str(ids.Get(key, ""));
        }

        public int Sync(Profile profile, object plugin)
        {
            // -> calls made. Google Play Games: standard ones unlocked once their goal is met, incremental ones as their steps
            // (capped at the goal) when they grew.
            if (profile == null || plugin == null)
                return 0;
            return _EachChange(profile, (string id, int v, int _n, bool inc) =>
            {
                if (inc)
                    GObject.Call(plugin, "setAchievementSteps", id, v);
                else
                    GObject.Call(plugin, "unlockAchievement", id);
            });
        }

        public int SyncPercent(Profile profile, Action<string, double> report)
        {
            // 0.31.130 (the iOS port): Game Center has no incremental kind -- each one is reported as its percent done
            // (100 * steps / goal, the same steps as Play), a standard one as 100 once met. report(id, percent).
            if (profile == null || report == null)
                return 0;
            return _EachChange(profile, (string id, int v, int n, bool inc) =>
            {
                report(id, inc ? 100.0 * v / n : 100.0);
            });
        }

        public int _EachChange(Profile profile, Action<string, int, int, bool> send)
        {
            // what changed since the last send (this run), the same for every service: send(id, steps, goal, incremental)
            var calls = 0;
            foreach (var a in LIST)
            {
                var id = IdOf(GD.Str(a["key"]));
                if (id == "")
                    continue;
                var n = (int)a["n"];
                var v = GD.Mini(Value(profile, GD.Str(a["stat"])), n);
                if (v <= (int)sent.Get(a["key"], 0))
                    continue;
                if (!(bool)a["inc"] && v < n)
                    continue;
                send(id, v, n, (bool)a["inc"]);
                calls += 1;
                sent[a["key"]] = v;
            }
            return calls;
        }

        public static int Configured()
        {
            // the achievements in the game with a Play Console id (0.31.188: not the retired ones)
            var n = 0;
            foreach (var a in LIST)
            {
                if (GD.Str(Ids.IDS.Get(GD.Str(a["key"]), "")) != "")
                    n += 1;
            }
            return n;
        }
    }
}
