// Ported from godot/scripts/meta/war_map.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;

namespace Fatebound.Game
{
    // 0.31.135 (Kevin, Crown War step 2 -- the "Crown War" design doc): the war map both sides share. Three houses, each
    // with a home (0.31.151: stormed only on King's Day, every Sunday -- below), and fifteen territories between them,
    // joined by links: a house attacks only along a link from land it holds (its home counts). The server (server/world.gd)
    // keeps who holds what; the phone (scripts/app/war_table.gd) draws it as a 3D war table from these positions.
    // Positions are map units (x right, y down); the table lays a hex tile at each, 2.4 units apart.
    public static class WarMap
    {
        public static readonly GArray HOUSES = GArray.Of("lions", "stags", "ravens");
        public static readonly GDict HOMES = new GDict { { "lions", "home_lions" }, { "stags", "home_stags" }, { "ravens", "home_ravens" } };
        public static readonly GDict HOUSE_NAMES = new GDict { { "lions", "Lions" }, { "stags", "Stags" }, { "ravens", "Ravens" } };

        // id -> {"name", "p": map position, "home": house ("" for a territory), "look": what stands on its tile}
        public static readonly GDict T = new GDict {
            { "home_lions",  GDict.Of("name", "Lions' Keep",  "p", new Vector2(0.9f, 1.1f), "home", "lions",  "look", "castle") },
            { "home_stags",  GDict.Of("name", "Stags' Keep",  "p", new Vector2(6.7f, 1.1f), "home", "stags",  "look", "castle") },
            { "home_ravens", GDict.Of("name", "Ravens' Keep", "p", new Vector2(3.8f, 4.2f), "home", "ravens", "look", "castle") },
            { "mill",   GDict.Of("name", "The Mill",     "p", new Vector2(2.1f, 1.1f),  "home", "", "look", "mill") },
            { "tower",  GDict.Of("name", "Old Tower",    "p", new Vector2(3.3f, 1.1f),  "home", "", "look", "tower") },
            { "abbey",  GDict.Of("name", "The Abbey",    "p", new Vector2(4.5f, 1.1f),  "home", "", "look", "abbey") },
            { "pass",   GDict.Of("name", "High Pass",    "p", new Vector2(5.7f, 1.1f),  "home", "", "look", "pass") },
            { "quarry", GDict.Of("name", "The Quarry",   "p", new Vector2(1.5f, 2.15f), "home", "", "look", "quarry") },
            { "ford",   GDict.Of("name", "The Ford",     "p", new Vector2(2.7f, 2.15f), "home", "", "look", "ford") },
            { "lake",   GDict.Of("name", "Silver Lake",  "p", new Vector2(3.85f, 2.15f), "home", "", "look", "lake") },
            { "bridge", GDict.Of("name", "King's Bridge", "p", new Vector2(4.95f, 2.15f), "home", "", "look", "bridge") },
            { "mine",   GDict.Of("name", "Deep Mine",    "p", new Vector2(6.1f, 2.15f), "home", "", "look", "mine") },
            { "marsh",  GDict.Of("name", "The Marsh",    "p", new Vector2(2.0f, 3.2f),  "home", "", "look", "marsh") },
            { "woods",  GDict.Of("name", "Kingswood",    "p", new Vector2(3.2f, 3.2f),  "home", "", "look", "woods") },
            { "forge",  GDict.Of("name", "The Forge",    "p", new Vector2(4.4f, 3.2f),  "home", "", "look", "forge") },
            { "cliffs", GDict.Of("name", "Grey Cliffs",  "p", new Vector2(5.6f, 3.2f),  "home", "", "look", "cliffs") },
            { "fen",    GDict.Of("name", "Raven Fen",    "p", new Vector2(2.6f, 4.2f),  "home", "", "look", "fen") },
            { "port",   GDict.Of("name", "Saltport",     "p", new Vector2(5.0f, 4.2f),  "home", "", "look", "port") },
        };
        public static readonly GArray LINKS = GArray.Of(
            GArray.Of("home_lions", "mill"), GArray.Of("home_lions", "quarry"), GArray.Of("mill", "tower"), GArray.Of("mill", "ford"), GArray.Of("quarry", "ford"),
            GArray.Of("quarry", "marsh"), GArray.Of("tower", "abbey"), GArray.Of("tower", "lake"), GArray.Of("ford", "lake"), GArray.Of("ford", "woods"), GArray.Of("abbey", "pass"),
            GArray.Of("abbey", "bridge"), GArray.Of("pass", "home_stags"), GArray.Of("pass", "mine"), GArray.Of("home_stags", "mine"), GArray.Of("lake", "bridge"),
            GArray.Of("lake", "woods"), GArray.Of("lake", "forge"), GArray.Of("bridge", "mine"), GArray.Of("bridge", "forge"), GArray.Of("mine", "cliffs"), GArray.Of("marsh", "woods"),
            GArray.Of("woods", "forge"), GArray.Of("forge", "cliffs"), GArray.Of("marsh", "fen"), GArray.Of("woods", "fen"), GArray.Of("fen", "home_ravens"),
            GArray.Of("home_ravens", "port"), GArray.Of("forge", "port"), GArray.Of("cliffs", "port")
        );

        // ---- the numbers (the design doc's "Starting numbers"; Kevin approved them)
        public const int ATTEMPTS = 5;                 // (0.31.135-0.31.149: battles a clan member scored in a day. 0.31.150, Kevin: "Remove the
                                                       // 5 battle daily" -- no limit; the server still sends it as "att"/"max" for older phones)
        public const int PTS_CROWN = 50;               // each crown a battle earns: a gate broken, the King rescued, the match won
        public const int PTS_LOSS = 100;               // a lost battle takes this off
        public const int NEED_OWNED = 1000;            // points to take a territory another house holds
        public const int NEED_NEUTRAL = 500;           // ... one nobody holds (every Monday's land rush)
        // 0.31.151 -- King's Day (Kevin: "Do them all"; the design doc's later step): every Sunday (UTC, the week's last day)
        // the keeps can be stormed -- by a house holding land linked to one, or by its own house taking it back. A keep takes
        // NEED_HOME points; a fallen keep counts HOME_WORTH lands for its captor in the week's count (and no longer counts as
        // its own house's land to attack from) until Monday gives every keep back.
        public const int KINGS_DAY = 0;                // Time's weekday (0 = Sunday, UTC)
        public const int NEED_HOME = 2000;
        public const int HOME_WORTH = 3;

        public static bool IsKingsDay(int t)
        {
            return (int)Time.GetDatetimeDictFromUnixTime(t)["weekday"] == KINGS_DAY;
        }

        public static int KingsDayNext(int t)
        {
            // when the next King's Day starts (today's start when it's King's Day now)
            var day0 = t - (int)GD.Posmod(t, 86400);
            var wd = (int)Time.GetDatetimeDictFromUnixTime(t)["weekday"];
            return day0 + (int)GD.Posmod(KINGS_DAY - wd, 7) * 86400;
        }

        public static int Worth(string id)
        {
            // what holding it counts for in the week's count (a fallen keep: HOME_WORTH)
            return IsHome(id) ? HOME_WORTH : 1;
        }

        public static GArray Territories()
        {
            // the fifteen that can be taken (not the homes), in a fixed order
            var out_ = new GArray();
            foreach (var id in T)
            {
                if (GD.Str(T[id]["home"]) == "")
                    out_.Append(id);
            }
            return out_;
        }

        public static bool IsHome(string id)
        {
            return T.Has(id) && GD.Str(T[id]["home"]) != "";
        }

        public static GArray Neighbours(string id)
        {
            var out_ = new GArray();
            foreach (var l in LINKS)
            {
                if (l[0] == id)
                    out_.Append(l[1]);
                else if (l[1] == id)
                    out_.Append(l[0]);
            }
            return out_;
        }

        public static bool Linked(string a, string b)
        {
            foreach (var l in LINKS)
            {
                if ((l[0] == a && l[1] == b) || (l[0] == b && l[1] == a))
                    return true;
            }
            return false;
        }

        public static string NameOf(string id)
        {
            return GD.Str(T.Get(id, new GDict()).Get("name", id));
        }

        public static int Points(int crowns, bool won)
        {
            // what one clan member's battle adds to their clan's bar (a win is always worth something, a loss never helps)
            return crowns * PTS_CROWN - (won ? 0 : PTS_LOSS);
        }
    }
}
