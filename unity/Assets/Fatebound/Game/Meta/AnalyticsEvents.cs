// Ported from godot/scripts/meta/analytics_events.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;

namespace Fatebound.Game
{
    // 0.31.118 (Kevin's spec, ANALYTICS_SPEC_FOR_CLAUDE.md: "self-hosted analytics on the Siege server ... no SDK and no third
    // party"): the events and, for each, the only props it may carry. Shared by the phone (scripts/meta/analytics.gd: what
    // it logs) and the server (server/analytics.gd: what it keeps -- anything else is dropped). Props are numbers, true/false
    // or short words made by the game's own code: never a name, a chat line, a token or an order id.
    public static class AnalyticsEvents
    {
        public const int MAX_PROPS = 32;                // (0.31.212: 12 -> 32 for the server's match_quit -- still only the listed keys)
        public const int MAX_STR = 40;

        // sent by the phone ({"t":"an"} batches)
        public static readonly GDict CLIENT = new GDict {
            { "session_start", GArray.Of("cold", "safe_boot", "net", "plat") },     // 0.31.132: plat "android" | "ios" (| "desktop")
            { "session_end", GArray.Of("dur_s", "lost") },              // lost: the session never said it ended (sent at the next start)
            { "clean_session", GArray.Of("prev_sid") },                  // the last session ended without a crash or a stuck start
            { "tutorial_start", new GArray() },
            { "tutorial_step", GArray.Of("step", "id") },
            { "tutorial_complete", GArray.Of("dur_s") },
            { "tutorial_skip", GArray.Of("dur_s", "step", "id") },
            { "match_join", GArray.Of("mode", "party_n") },
            { "match_start", GArray.Of("match", "mode", "class") },      // (the phone's only for "bots": online matches are the server's)
            { "match_finish", GArray.Of("match", "mode", "dur_s", "result", "team_n", "class", "class0") },
            { "match_quit", GArray.Of("match", "mode", "quit_at_s", "class", "class0") },
            { "level_up", GArray.Of("lvl") },
            { "forge", GArray.Of("item", "stars") },
            { "chest_open", GArray.Of("rarity", "src") },
            { "shop_view", GArray.Of("tab") },
            { "daily_reward", GArray.Of("day") },                         // 0.31.119: the daily login reward claimed (day 1-7)
            { "update_screen", GArray.Of("from_build", "need") },
            { "error", GArray.Of("kind", "n") },
            { "opt_out", new GArray() },
            { "q_dropped", GArray.Of("n") },
        };

        // written by the server itself (it knows these first-hand; the phone never sends them)
        public static readonly GDict SERVER = new GDict {
            { "session_online", new GArray() },
            { "match_start", GArray.Of("match", "mode", "class") },
            // 0.31.212 (NEW_PLAYER_RETENTION_HANDOFF.md): the player's upgrades from the match's shop -- items bought, the gold
            // they cost, the gold left unspent
            { "match_finish", GArray.Of("match", "mode", "dur_s", "result", "team_n", "class", "class0", "items", "gold_spent", "gold_left") },
            // 0.31.212 (the same): the match as the player left it. why: the drop's reason ("left" = quit on purpose, "closed" /
            // "silent" = the connection went, "idle", ...); held: their seat waited for them and they never came back (let go
            // when the wait ran out or the match ended); rejoins: times they came back to this seat; match_s: the match's clock
            // at the leave; team 0 blue / 1 red, the rest from their side: score (Kings toppled), kills (the team's), k/d/a
            // (theirs), each King's HP in percent, and their shop totals
            { "match_quit", GArray.Of("match", "mode", "quit_at_s", "class", "class0", "why", "held", "rejoins", "match_s", "hero", "team", "lvl",
                "score_us", "score_them", "kills_us", "kills_them", "k", "d", "a", "king_us_pct", "king_them_pct",
                "items", "gold_spent", "gold_left") },
            // 0.31.212 (the same): an upgrade a player bought with the match's gold (a bot's buys are not counted)
            { "match_shop_buy", GArray.Of("match", "mode", "item", "cost", "match_s", "hero", "gold_left") },
            { "purchase_verified", GArray.Of("product", "test", "store") },     // 0.31.131: store "google" | "apple"
            { "chat_send", GArray.Of("kind") },
            { "friend_add", new GArray() },
            { "friend_accept", new GArray() },
            { "party_create", new GArray() },
            { "party_join", GArray.Of("n") },
            { "party_invite", new GArray() },
            { "quick_chat", GArray.Of("i") },
            { "update_screen", GArray.Of("from_build", "need") },
            { "clan_create", GArray.Of("house", "join") },               // 0.31.134: clans (server/clans.gd)
            { "clan_join", GArray.Of("n") },
            { "clan_request", new GArray() },
            { "clan_invite", new GArray() },
            { "clan_leave", new GArray() },
            // 0.31.208, server (Kevin: "Gold and gem spending ... tracking system for server"): gold or gems an account spent, as the
            // server replayed it (server/eco_accounts.gd spend_props): what on, what it cost, what was left
            { "spend", GArray.Of("cat", "item", "op", "gold", "gems", "gold_left", "gems_left", "lvl", "hero", "off", "n", "season") },
        };

        public static GDict CleanProps(GArray allowed, Var p)
        {
            // only the allowed keys; numbers and true/false as they are, anything else as a short string
            var out_ = new GDict();
            if (!p.IsDict)
                return out_;
            foreach (var k in allowed)
            {
                if (out_.Size() >= MAX_PROPS)
                    break;
                if (!p.D.Has(k))
                    continue;
                Var v = p[k];
                switch (GD.TypeOf(v))
                {
                    case GD.TYPE_BOOL:
                    case GD.TYPE_INT:
                        out_[k] = v;
                        break;
                    case GD.TYPE_FLOAT:
                        out_[k] = GD.IsFinite((double)v) && (double)GD.Long(v) == (double)v ? (Var)GD.Long(v) : (GD.IsFinite((double)v) ? (Var)GD.Snappedf((double)v, 0.01) : (Var)0);
                        break;
                    default:
                        out_[k] = GD.Str(v).Left(MAX_STR);
                        break;
                }
            }
            return out_;
        }
    }
}
