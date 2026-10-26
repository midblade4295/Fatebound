// Ported from godot/scripts/siege/siege_net.gd (Fatebound 0.31.222).
//
// Port note: the GDScript sim keeps its units, towers, Kings, gates, camps, zones, traps, wards and projectiles as
// Dictionaries, and this protocol reads and writes them by key. The C# sim (Fatebound.Sim) keeps them as typed records
// whose fields are the dictionaries' keys. So the code below is the .gd's, line for line, with each dictionary access on
// a sim record going through the adapters at the end of this file ("the wire's dictionaries <-> the sim's records"):
// a record read as the dictionary GDScript would hold (its keys and values as Godot types -- what var_to_bytes encodes),
// a wire dictionary's key written into a record (converted to the field's type), a key erased (the field back to its
// default: absent). Keys a typed record has no field for (the mirror's own "net_*" history, "srv_pos", "task") live in
// the Unit's `extra` (Unit.Set/Get/Erase) and, for projectiles, in a table beside them (_PX). The bytes on the wire are
// unchanged: var_to_bytes of the same Dictionaries with the same keys, types and order (GMarshal), "R"/"Z" tags, zstd.
// The server side (snapshot/keyframe) is translated too; as the typed records can't tell an absent key from its default,
// a C# server's unit diffs would list every field the record has (the Godot server lists only the keys a unit holds).
using System;
using System.Collections;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector2i = Fatebound.Sim.Vec2i;
using Vector3 = Fatebound.Sim.Vec3;

namespace Fatebound.Game
{
    using Sim = Fatebound.Sim.SiegeSim;

    // Fatebound's online protocol, shared by the headless server (server/siege_server.gd) and the phone (siege_mode.gd).
    // The server runs the real sim; clients keep a mirror sim (the same map and heroes from setup() + setup_moba()) brought to
    // each snapshot, so the view and HUD draw an online match as they draw one against bots. (0.31.170: the online 5v5 --
    // its minions, monsters and summons come and go, its heroes level, shop and cast; snapshot() below. The protocol number
    // stays 35: the economy, the leaderboard and the version check send it too and a bump would force every app to update;
    // a 5v5 app says so in its hello ("five":1) and a 5v5 server in its answers, and the server refuses a match to an app
    // without it as too old -- the Update screen.)
    //
    // Transport: WebSocket binary frames, each one var_to_bytes(Dictionary). Never bytes_to_var with
    // objects: decode() uses the default allow_objects=false.
    public static class SiegeNet
    {
        public const int VERSION = 37;              // 37 = Honor of Kings rules (0.31.217: open gates, no King towers -- a lane, then the King; skill points); 36 = the Honor of Kings map (0.31.216: the square, corner keeps, gates at -135/-90/-45 degrees); 35 = the "block" action (the Crusader's shield, 0.31.61); 34 = the Sniper's piercing shot (PROJ_KINDS); 33 = the player launcher (state "fly", "la"); 32 = one snapshot for all + "m" task messages, timed interpolation; 31 = the bomb (bm); 30 = smaller snapshots: packed projectiles/items/Kings, slow state only when it changes (0.31.8); 29 = no class caps; per-class stand stock/restock, no heal stacking, armory +8 %, worker 80 hp; 28 = class caps; 27 = the Necromancer (drain + heal beams, unit field 32); 26 = Resurrection, bigger nova/sanctuary; 25 = logs/rocks (it); 24 = the Crusader and its thrown hammer; 23 = tower shot heights, run off a deck; 22 = wide roofless towers; 21 = natural hills, every class climbs; 20 = bigger towers; 19 = the bigger natural map; 18 = no "water" in the dungeons (wading only in the river); 17 = rampart shots
        public const string DEFAULT_URL = "wss://136-113-125-3.sslip.io/fatebound/siege/ws";
        // Refusals: the server sends {"t":"bye", "why":..., "need":VERSION} and then closes with one of these codes.
        // Since 0.31.73 the version refusal's close reason is "version:<server protocol>" (older servers: just "version").
        public const int CLOSE_NO_HELLO = 4000;
        public const int CLOSE_VERSION = 4001;
        public const int CLOSE_FULL = 4002;
        public const int DEFAULT_PORT = 8082;
        public const double SNAP_HZ = 20.0;            // 15 -> 20 (0.31.23); 10 -> 15 (0.18.4)
        public const int PROJ_HIST = 6;                // 0.31.207: a projectile's positions kept (300 ms at 20 Hz: past the render delay)
        public const double INTERP_DELAY = 1.5 / SNAP_HZ;   // 0.31.23: remote units are drawn this far behind the newest snapshot (75 ms)
        public const int HIST = 4;
        // 0.31.170: the 5v5's shots too (a kind + 16 = a big one, the Ranger's DEADEYE)
        public static readonly GArray PROJ_KINDS = GArray.Of("arrow", "fire", "hammer", "pierce", "bolt", "ball", "thorn", "boulder");
        public const double PREDICT_SNAP = 2.5;        // m: a predicting phone snaps to the server beyond this
        public const double PREDICT_SOFT = 0.7;        // m: beyond this it is eased back toward the server's position (0.31.24)
        public const int MAX_PACKET = 64 * 1024;            // client -> server; anything larger is dropped
        public const int TEAM_SIZE = 5;               // (0.31.169: the 5v5's; 16 a side in Siege)
        // 0.31.111 (Kevin: "add the quick chat pings"): the in-match quick chat. {"t":"qc", "i": index} from a player; the
        // server sends {"t":"qc", "u": unit, "i"} to their side ("all": to both sides). Additive: an older server ignores it,
        // an older app never sends it.
        public static readonly GArray QUICK_CHAT = GArray.Of(
            GDict.Of("x", "Attack!", "c", "#ff8a5c"),
            GDict.Of("x", "Defend the gate!", "c", "#7ec8ff"),
            GDict.Of("x", "Get our King!", "c", "#ffd65a"),
            GDict.Of("x", "Take the tower!", "c", "#ff6a6a"),          // (0.31.170: "Stop the carrier!" went with Siege)
            GDict.Of("x", "Need help!", "c", "#ff6a6a"),
            GDict.Of("x", "Follow me!", "c", "#9dff8a"),
            GDict.Of("x", "Thanks!", "c", "#e6e6e6"),
            GDict.Of("x", "Good game!", "c", "#e6c2ff", "all", true)
        );
        public const double QC_GAP = 2.0;              // s between one player's quick chats

        public static readonly GArray STATES = GArray.Of("idle", "move", "wind", "recover", "dodge", "dead", "dash");
        // Actions a client may ask for (anything else is ignored by the server), and what each takes (clean_arg). 0.31.170: the
        // 5v5's -- a level-up pick, the ultimate, W and E, a ward, the shop.
        public static readonly GArray ACTIONS = GArray.Of("attack", "ability", "block", "dodge", "pick", "ult", "spell", "ward", "shop_buy", "shop_sell", "recall", "learn");   // (0.31.217: learn, a skill point)
        public const int FIVE = 1;                  // 0.31.170: the online 5v5 (the hello's "five", the server's answers' "five")

        public static GArray CleanArg(string action, Var arg)
        {
            // -> [ok, the argument as the sim takes it] for an action from a phone
            switch (action)
            {
                case "pick":
                    return (arg.IsInt || arg.IsFloat) && GD.Int(arg) >= 0 && GD.Int(arg) <= 2 ? GArray.Of(true, GD.Int(arg)) : GArray.Of(false, Var.Nil);
                case "spell":
                    return arg.IsString && (GD.Str(arg) == "w" || GD.Str(arg) == "e") ? GArray.Of(true, GD.Str(arg)) : GArray.Of(false, Var.Nil);
                case "learn":
                    return arg.IsString && GArray.Of("q", "w", "e", "r").Has(GD.Str(arg)) ? GArray.Of(true, GD.Str(arg)) : GArray.Of(false, Var.Nil);
                case "shop_buy":
                    return arg.IsString && GD.Str(arg).Length <= 24 && _Word(GD.Str(arg), true) ? GArray.Of(true, GD.Str(arg)) : GArray.Of(false, Var.Nil);
                case "shop_sell":
                    return (arg.IsInt || arg.IsFloat) && GD.Int(arg) >= 0 && GD.Int(arg) < 8 ? GArray.Of(true, GD.Int(arg)) : GArray.Of(false, Var.Nil);
            }
            return GArray.Of(ACTIONS.Has(action), Var.Nil);
        }

        // ---------------- version mismatch (0.31.73: the "Update required" screen) ----------------
        // What the client should do about the server's protocol `server_v`, compared with ours (VERSION):
        //   "update"     the server is newer: this build is too old -> the blocking Update screen
        //   "server_old" the server is older: a new build went out before the server was redeployed -> "Servers are updating"
        //   "ok"         same protocol
        //   "unknown"    no answer (offline, or a server too old to answer the version check)
        // Nothing here hard-codes a protocol number, so every future bump of VERSION works the same way.
        // ---------------- titles (0.31.87) ----------------
        // Kevin: "make it so their titles show (use correct punctuation when putting the titles on the name)" and "players have
        // to earn the titles". Every title the game has: id -> [text, form, rarity]. The form says how it joins a name:
        //   "the"    an epithet, no comma           Midblade the Gatebreaker   (as "Alexander the Great")
        //   "of"     an "of" phrase, no comma       Midblade of Many Hats
        //   "prefix" a rank in front, no comma      Squire Midblade            (as "Sir Lancelot")
        //   "office" an office after it, a comma    Midblade, Siege Lord       (as "Arthur, King of the Britons")
        // Here (not in the economy) because the server builds the over-head text from it too: a hello names a title id, never
        // free text. How each is earned: scripts/meta/economy.gd TITLE_GOALS.
        // 0.31.90 in-app purchases (Kevin: "I want to incorporate IAP"). Google Play only, in the Play app; the server checks
        // each purchase with Google before the phone grants it (server/iap_verify.gd). The IDs are permanent in Play Console
        // (godot/PLAY_IAP_HANDOFF.md): never rename one. "once": acknowledged, never consumed, so Google sells it once.
        public const string IAP_PACKAGE = "com.fatebound.game";
        public static readonly GDict IAP = new GDict {
            { "gems_80",      GDict.Of("gems", 80,   "usd", "0.99") },
            { "gems_500",     GDict.Of("gems", 500,  "usd", "4.99") },
            { "gems_1100",    GDict.Of("gems", 1100, "usd", "9.99", "tag", "A SIEGE PASS") },
            { "gems_2400",    GDict.Of("gems", 2400, "usd", "19.99") },
            { "gems_6500",    GDict.Of("gems", 6500, "usd", "49.99", "tag", "BEST VALUE") },
            // 0.31.108 (the economy review): a $99.99 pack. "play_only": shown only once Google Play returns its price (the
            // product has to be created in Play Console first, PLAY_IAP_HANDOFF.md); it then takes BEST VALUE from gems_6500.
            { "gems_14000",   GDict.Of("gems", 14000, "usd", "99.99", "tag", "BEST VALUE", "play_only", true) },
            // 0.31.108: 300 gems + 150 Embers + a rare -> 500 + 300 + an epic (about 2.6x its price; was 1.5x). 0.31.184 (no more
            // Embers): 500 gems + 3,000 gold + an epic -- the 300 Embers at economy.gd EMBER_GOLD. 0.31.188 (no more weapons): a
            // Hero Token for the epic -- any locked hero (the product ID, type and price stay; its store text is Kevin's to change)
            { "starter_pack", GDict.Of("gems", 500,  "gold", 3000, "token", 1, "once", true, "usd", "2.99") },
        };

        public static readonly GDict TITLES = new GDict {
            // --- for everyone
            { "title_squire",         GArray.Of("Squire", "prefix", "common") },
            { "title_victor",         GArray.Of("the Victor", "the", "common") },
            { "title_brawler",        GArray.Of("the Brawler", "the", "common") },
            { "title_woodcutter",     GArray.Of("the Woodcutter", "the", "common") },
            { "title_fishmonger",     GArray.Of("the Fishmonger", "the", "common") },
            { "title_gatebreaker",    GArray.Of("the Gatebreaker", "the", "rare") },
            { "title_kingbearer",     GArray.Of("Kingbearer", "office", "rare") },
            { "title_many_hats",      GArray.Of("of Many Hats", "of", "rare") },
            { "title_tempest",        GArray.Of("the Tempest", "the", "epic") },
            { "title_relentless",     GArray.Of("the Relentless", "the", "epic") },
            { "title_cake_baron",     GArray.Of("Fish Baron", "office", "epic") },
            { "title_siege_lord",     GArray.Of("Siege Lord", "office", "epic") },
            { "title_oracle_sworn",   GArray.Of("the Kingsworn", "the", "legendary") },
            { "title_unstoppable",    GArray.Of("the Unstoppable", "the", "legendary") },
            { "title_undefeated",     GArray.Of("the Undefeated", "the", "legendary") },
            { "title_legend",         GArray.Of("the Legend", "the", "legendary") },
            // --- per class (each upgrade counts as its class)
            { "title_sir",            GArray.Of("Sir", "prefix", "rare") },
            { "title_shieldwall",     GArray.Of("the Shieldwall", "the", "epic") },
            { "title_hammer_realm",   GArray.Of("Hammer of the Realm", "office", "legendary") },
            { "title_wild",           GArray.Of("the Wild", "the", "rare") },
            { "title_whirlwind",      GArray.Of("the Whirlwind", "the", "epic") },
            { "title_unchained",      GArray.Of("the Unchained", "the", "legendary") },
            { "title_sly",            GArray.Of("the Sly", "the", "rare") },
            { "title_shadows",        GArray.Of("of the Shadows", "of", "epic") },
            { "title_knives",         GArray.Of("Master of Knives", "office", "legendary") },
            { "title_keen_eyed",      GArray.Of("the Keen-Eyed", "the", "rare") },
            { "title_deadeye",        GArray.Of("the Deadeye", "the", "epic") },
            { "title_warden",         GArray.Of("Warden of the Wilds", "office", "legendary") },
            { "title_apprentice",     GArray.Of("Apprentice", "prefix", "rare") },
            { "title_stormcaller",    GArray.Of("the Stormcaller", "the", "epic") },
            { "title_starborn",       GArray.Of("the Starborn", "the", "legendary") },
            { "title_acolyte",        GArray.Of("Acolyte", "prefix", "rare") },
            { "title_merciful",       GArray.Of("the Merciful", "the", "epic") },
            { "title_lightbringer",   GArray.Of("the Lightbringer", "the", "legendary") },
            { "title_foreman",        GArray.Of("Foreman", "prefix", "rare") },
            { "title_mason",          GArray.Of("the Mason", "the", "epic") },
            { "title_master_builder", GArray.Of("Master Builder", "office", "legendary") },
            // --- 0.31.120: the weekly leaderboard's
            { "title_champion",       GArray.Of("Champion", "prefix", "legendary") },
            { "title_contender",      GArray.Of("the Contender", "the", "epic") },
            { "title_top_ten",        GArray.Of("of the Ten", "of", "rare") },
        };

        public static GArray TitleParts(string name, string title_id)
        {
            // The name with its title, in reading order: [[text, is_title], ...] (the punctuation is part of the name's side).
            GArray t = TITLES.Get(title_id, new GArray()).A;
            if (t.IsEmpty())
                return GArray.Of(GArray.Of(name, false));
            switch (GD.Str(t[1]))
            {
                case "prefix": return GArray.Of(GArray.Of(GD.Str(t[0]), true), GArray.Of(" " + name, false));
                case "office": return GArray.Of(GArray.Of(name + ",", false), GArray.Of(" " + GD.Str(t[0]), true));     // (spaces lead a part: measured widths keep them)
                default: return GArray.Of(GArray.Of(name, false), GArray.Of(" " + GD.Str(t[0]), true));
            }
        }

        public static string TitleText(string name, string title_id)
        {
            var s = "";
            foreach (var p in TitleParts(name, title_id))
                s += GD.Str(p[0]);
            return s;
        }

        public static string TitleRarity(string title_id)
        {
            GArray t = TITLES.Get(title_id, new GArray()).A;
            return !t.IsEmpty() ? GD.Str(t[2]) : "";
        }

        // ---------------- what the players wear (0.31.101) ----------------
        // Kevin: "I want players to see everything the other players are wearing". A hello may carry "lk": what the player wears
        // (Profile.wire_looks); the server keeps only well-formed entries (clean_looks) and sends them in "pn" as "lk": {unit id:
        // looks}, as it does names and titles. 0.31.188 (Kevin: "I only want the cosmetics to be an entire outfit"): the outfits
        // worn, "_sk", are all there is -- the weapons' "<class>": "weapon id|stars|element" entries (0.31.101-0.31.187) are
        // dropped (an older app still sending them: left out). Additive: an older server ignores "lk", an older app ignores "_sk".
        public static GDict CleanLooks(Var v)
        {
            var o = new GDict();
            if (!v.IsDict)
                return o;
            if (v.D.Get("_sk").IsString)
            {
                var sk = CleanSkins(v.D["_sk"].AsString());
                if (sk != "")
                    o["_sk"] = sk;
            }
            return o;
        }

        // 0.31.186: the hero skins worn, "_sk": "knight_frost,golem_frost" -- ids of a-z 0-9 _, at most SKINS_MAX (each app
        // shows the one for the hero being played, from its own catalog; an id it doesn't know: the hero's own look)
        public const int SKINS_MAX = 24;

        public static string CleanSkins(string s)
        {
            if (s.Length > 600)
                return "";
            var keep = new GArray();
            foreach (var id in s.Split(","))
            {
                if (id != "" && id.Length <= 40 && _Word(id, true) && !keep.Has(id) && keep.Size() < SKINS_MAX)
                    keep.Append(id);
            }
            return GStr.Join(",", keep);
        }

        public static bool _Word(string s, bool digits)
        {
            for (int i = 0; i < s.Length; i++)
            {
                var c = s.UnicodeAt(i);
                if (!((c >= 97 && c <= 122) || c == 95 || (digits && c >= 48 && c <= 57)))
                    return false;
            }
            return true;
        }

        // App builds ("0.31.209-fatebound"; server 0.31.84-minbuild's minimum app build). 0.31.209: here rather than in the
        // server, so the app checks the server's minimum ("ver" says "min_build") at launch, before any match.
        public static GArray ParseBuild(string b)
        {
            var head = b.StripEdges() != "" ? b.StripEdges().Split("-", true, 1)[0] : "";
            if (head == "")
                return new GArray();
            var o = new GArray();
            foreach (var part in head.Split("."))
            {
                if (!part.IsValidInt())
                    return new GArray();
                o.Append(part.ToInt());
            }
            return o;
        }

        // -1 a < b, 0 equal, 1 a > b (missing parts count as 0: 0.31 == 0.31.0).
        public static int CompareBuilds(GArray a, GArray b)
        {
            for (int i = 0; i < GD.Maxi(a.Size(), b.Size()); i++)
            {
                long x = i < a.Size() ? (long)a[i] : 0;
                long y = i < b.Size() ? (long)b[i] : 0;
                if (x != y)
                    return x < y ? -1 : 1;
            }
            return 0;
        }

        // True only when both are readable and `build` is older than `minimum`. Unknown builds and "no minimum" pass.
        public static bool BuildTooOld(string build, string minimum)
        {
            var m = ParseBuild(minimum);
            var b = ParseBuild(build);
            if (m.IsEmpty() || b.IsEmpty())
                return false;
            return CompareBuilds(b, m) < 0;
        }

        public static string VersionVerdict(int server_v, int client_v = VERSION)
        {
            if (server_v < 0)
                return "unknown";
            if (server_v > client_v)
                return "update";
            if (server_v < client_v)
                return "server_old";
            return "ok";
        }

        // The server's protocol from a refusal: the bye's "need" if it arrived, else the close reason "version:<n>".
        // -1 = not a version refusal. A version refusal (code 4001 / bye "version") without any number comes from a server
        // that predates 0.31.73 -- i.e. older than any build carrying this code -- so it maps to "server older" (0).
        public static int RefusedVersion(GDict bye, int close_code, string close_reason)
        {
            if (GD.Str(bye.Get("why", "")) == "version" && bye.Has("need"))
                return GD.Maxi(0, GD.Int(bye.Get("need", 0)));
            if (close_reason.BeginsWith("version:") && close_reason.Substr(8).IsValidInt())
                return GD.Maxi(0, close_reason.Substr(8).ToInt());
            if (close_code == CLOSE_VERSION || GD.Str(bye.Get("why", "")) == "version" || close_reason == "version")
                return 0;
            return -1;
        }

        // Wire format: 1 byte tag + payload. "R" = var_to_bytes, "Z" = zstd(var_to_bytes) with the raw
        // size in 4 bytes. Snapshots are compressed; small client messages go raw.
        public static byte[] Encode(GDict msg, bool compress = false)
        {
            var raw = GMarshal.VarToBytes(msg);
            byte[] o;
            if (compress)
            {
                var z = raw.Compress(FileAccess.COMPRESSION_ZSTD);
                o = new byte[5];
                o[0] = 0x5A;
                o.EncodeU32(1, raw.Length);
                return _Cat(o, z);
            }
            o = new byte[] { 0x52 };
            return _Cat(o, raw);
        }

        // (PackedByteArray.append_array)
        static byte[] _Cat(byte[] a, byte[] b)
        {
            var r = new byte[a.Length + b.Length];
            Buffer.BlockCopy(a, 0, r, 0, a.Length);
            Buffer.BlockCopy(b, 0, r, a.Length, b.Length);
            return r;
        }

        public static GDict Decode(byte[] bytes)
        {
            if (bytes.Length < 2 || bytes.Length > MAX_PACKET * 16)
                return new GDict();
            var raw = new byte[0];
            if (bytes[0] == 0x5A && bytes.Length > 5)
            {
                var n = bytes.DecodeU32(1);
                if (n <= 0 || n > MAX_PACKET * 64)
                    return new GDict();
                raw = bytes.Slice(5).Decompress(n, FileAccess.COMPRESSION_ZSTD);
            }
            else if (bytes[0] == 0x52)
                raw = bytes.Slice(1);
            else
                return new GDict();
            Var v = GMarshal.BytesToVar(raw);
            return v.IsDict ? v.D : new GDict();
        }

        public static void _S16(byte[] arr, int i, double v)
        {
            arr.EncodeS16(i * 2, _I16(v));
        }

        public static int _I16(double v)
        {
            return GD.Clampi(GD.Int(GD.Round(v)), -32768, 32767);
        }

        public static int _Wrap16(long v)
        {
            // a 16-bit difference (the phone adds it back the same way: exact whatever the values)
            return (int)(((v + 32768) & 0xFFFF) - 32768);
        }

        // ---------------- server side ----------------
        // 0.31.170 (the online 5v5): one snapshot for every player, 20 a second. What changes all the time goes in full each
        // time, packed; everything else only when it changed since the last snapshot (each player's socket delivers every one,
        // in order, so a change sent once is never lost; a player seated, back from a drop, or whose socket couldn't take a
        // snapshot gets a KEYFRAME -- the lot -- first):
        //   "ids"  the units' ids, in the order of "u" (only when a unit came or went; the 5v5's minions, monsters and summons
        //          come and go all match long)
        //   "u"    per unit, FAST 16-bit values: health, x, z (1 cm), facing (0.001 rad), state, stun and ability recharge
        //          (0.01 s)
        //   "ho"/"h"  the heroes' ids (once) and per hero HERO_FAST: gold and the W, E, ultimate and ward recharges
        //   "ud"   {unit id: {key: value}}: every other key of a unit that changed (its hero, level, items, buffs, the shield
        //          and the times its effects end -- absolute match times, so the phone needs no clock of its own) but NO_SYNC
        //   "ux"   {unit id: [keys]}: keys a unit lost (an effect that ended)
        //   "o"    {"tw:3": {key: value}}: the towers', Kings', gates' and camps' changes (OBJ_SKIP: what never changes)
        //   "zn" "tr" "wd" "ws" "ek"  the spells' zones and traps, the wards, the Wyrm's stacks, each side's epic monsters
        //          slain (0.31.176): in full when they changed
        //   "p"    the projectiles, 6 x 16 bits each (id, x, z, vx, vz, kind + 16 if big)
        //   "e"    the match's events since the last snapshot (the view's and the HUD's effects, sounds, toasts)
        public const int FAST = 7;
        public static readonly GArray HERO_FAST = GArray.Of("gold", "cd_w", "cd_e", "ult_cd", "ward_ch");
        public static readonly GArray HERO_FAST_SCALE = GArray.Of(1.0, 100.0, 100.0, 100.0, 100.0);
        // Never sent: the server's own bookkeeping (paths, the bots' thinking and targets, who hit whom for assists, the
        // multi-kill window, the camps' monsters' homes) and clocks that tick all the time and the phone never reads.
        public static readonly GDict NO_SYNC = GDict.Of("t", true, "move", true, "path", true, "path_i", true, "path_goal", true, "path_at", true, "path_ver", true,
            "think_at", true, "unstick", true, "unstick_dir", true, "stuck_t", true, "last_pos", true, "aim_d", true, "drain_acc", true,
            "hit_log", true, "hh_at", true, "hh_by", true, "hurt_at", true, "hurt_by", true, "mt", true, "mt_pri", true, "mt_tw", true,
            "wp", true, "home", true, "home_face", true, "healed", true, "mk_n", true, "mk_t", true, "beam_heal_t", true,
            "combo_t", true, "dodge_dir", true, "lunge_hit", true, "whirl_t", true, "net_driven", true, "id", true,
            "cc_log", true, "heal_log", true);
        public static readonly GDict FAST_KEYS = GDict.Of("hp", true, "pos", true, "face", true, "state", true, "stun", true, "cd_ability", true,
            "gold", true, "cd_w", true, "cd_e", true, "ult_cd", true, "ward_ch", true);
        public static readonly GDict OBJ_SKIP = new GDict {
            { "tw", GDict.Of("id", true, "team", true, "lane", true, "tier", true, "p", true) },
            { "kg", GDict.Of("quiet", true) },
            { "gt", GDict.Of("id", true, "team", true, "a", true, "b", true, "c", true, "side", true, "lane", true, "in", true, "r", true) },
            { "cp", GDict.Of("id", true, "kind", true, "side", true, "p", true, "patience", true, "hits", true) },
        };

        public static GArray _Objs(Sim sim)
        {
            // [prefix, the list] for the "o" channel
            var o = GArray.Of(GArray.Of("gt", Var.Of(sim.gates)));
            if (sim.moba != null)
                o.AppendArray(GArray.Of(GArray.Of("tw", Var.Of(sim.moba.towers)), GArray.Of("kg", Var.Of(sim.moba.kings)), GArray.Of("cp", Var.Of(sim.moba.camps))));
            return o;
        }

        public static GDict _Blobs(Sim sim)
        {
            // the slow lists, as sent
            if (sim.moba == null)
                return new GDict();
            var zn = new GArray();
            foreach (var z in sim.moba.kits.zones)
            {
                GDict c = _ZoneDict(z);
                c.Erase("next");                                 // (its next tick: the server's)
                zn.Append(c);
            }
            return GDict.Of("zn", zn, "tr", _V(sim.moba.kits.traps), "wd", _V(sim.moba.vision.wards), "ws", _V(_IntsArr(sim.moba.wyrm_stacks)), "ek", _EpicDict(sim.moba.epic_kills));
        }

        public static void _Diff(GDict sync, string key, GDict d, GDict skip, GDict changed, GDict erased)
        {
            // d's keys (but skip) that differ from what was last sent for `key` -> changed[key]; keys it lost -> erased[key]
            GDict cache = sync["c"].D;
            GDict c = cache.Get(key, new GDict()).D;
            if (!cache.Has(key))
                cache[key] = c;
            // Its keys are listed again when it gained or lost one: its size changed, or a listed key went. (A skipped or NO_SYNC
            // key never comes and goes on a unit -- else one leaving as another arrives would hide the new one.)
            GArray kl = sync["kl"].D.Get(key, new GArray()).A;
            bool rebuild = d.Size() != GD.Int(sync["ksz"].D.Get(key, -1));
            if (!rebuild)
            {
                foreach (var k in kl)
                {
                    if (!d.Has(k))
                    {
                        rebuild = true;
                        break;
                    }
                }
            }
            if (rebuild)
            {
                kl = new GArray();
                foreach (var k in d)
                {
                    if (!skip.Has(k) && !NO_SYNC.Has(k))
                        kl.Append(k);
                }
                sync["kl"].D[key] = kl;
                sync["ksz"].D[key] = d.Size();
                var gone = new GArray();
                foreach (var k in c.Keys())
                {
                    if (!d.Has(k))
                    {
                        c.Erase(k);
                        gone.Append(k);
                    }
                }
                if (!gone.IsEmpty())
                    erased[key] = gone;
            }
            var ch = new GDict();
            foreach (var k in kl)
            {
                Var v = d[k];
                Var cv = c.Get(k);                       // (null: never sent -- no key of a unit is ever null)
                if (cv.IsNull || cv.GodotType != v.GodotType || cv != v)
                {
                    Var sv = (v.IsArr || v.IsDict) ? v.Duplicate(true) : v;
                    c[k] = sv;
                    ch[k] = sv;
                }
            }
            if (!ch.IsEmpty())
                changed[key] = ch;
        }

        public static GDict _SyncOf(Sim sim)
        {
            GDict sync = _NetSync(sim);
            if (!sync.Has("c"))
                sync.Merge(GDict.Of("c", new GDict(), "kl", new GDict(), "ksz", new GDict(), "ids", Var.Of(new string[0]), "ho", Var.Of(new string[0]), "blob", new GDict(), "last", new GDict()));
            return sync;
        }

        public static GDict Snapshot(Sim sim, string _for_unit, GArray events)
        {
            // The next snapshot for everyone in the match (_for_unit: kept for the callers; nothing in it is private).
            var sync = _SyncOf(sim);
            var msg = GDict.Of("t", "s", "tm", sim.time, "sc", _IntsArr(sim.score), "k", _IntsArr(sim.kills),
                "end", GArray.Of(sim.ended, sim.winner, sim.end_reason), "e", events);
            var ids = new List<string>();
            int n = sim.units.Count;
            var abs_i = new int[n * FAST];                    // the values themselves (a keyframe's)
            var fast = new byte[n * FAST * 2];                // what's sent: each value less the last snapshot's (mostly 0)
            string[] prev_ids = _Strs(sync["ids"]);
            int[] prev_i = sync.Get("abs_i").As<int[]>() ?? new int[0];
            var prev_at = new GDict();
            var ud = new GDict();
            var ux = new GDict();
            var i = 0;
            foreach (var u in sim.units)
            {
                var id = GD.Str(u.id);
                ids.Add(id);
                var b = i * FAST;
                var hp = u.hp;
                Vector2 p = u.pos;
                abs_i[b] = hp > 0.0 ? GD.Clampi(GD.Int(GD.Ceilf(hp)), 0, 32767) : 0;
                abs_i[b + 1] = GD.Clampi(GD.Int(GD.Round(p.x * 100.0)), -32768, 32767);
                abs_i[b + 2] = GD.Clampi(GD.Int(GD.Round(p.y * 100.0)), -32768, 32767);
                abs_i[b + 3] = GD.Clampi(GD.Int(GD.Round(GD.Wrapf(u.face, -GD.PI, GD.PI) * 1000.0)), -32768, 32767);
                abs_i[b + 4] = GD.Maxi(0, STATES.Find(GD.Str(u.state)));
                abs_i[b + 5] = GD.Clampi(GD.Int(GD.Round(u.stun * 100.0)), -32768, 32767);
                abs_i[b + 6] = GD.Clampi(GD.Int(GD.Round(u.cd_ability * 100.0)), -32768, 32767);
                var j = i < prev_ids.Length && prev_ids[i] == id ? i : -1;
                if (j < 0 && prev_ids.Length != 0)
                {
                    if (prev_at.IsEmpty())
                    {
                        for (int pi = 0; pi < prev_ids.Length; pi++)
                            prev_at[prev_ids[pi]] = pi;
                    }
                    j = GD.Int(prev_at.Get(id, -1));
                }
                if (j >= 0)
                {
                    var pb = j * FAST;
                    for (int k = 0; k < FAST; k++)
                        fast.EncodeS16((b + k) * 2, ((abs_i[b + k] - prev_i[pb + k] + 32768) & 0xFFFF) - 32768);
                }
                else
                {
                    for (int k = 0; k < FAST; k++)
                        fast.EncodeS16((b + k) * 2, abs_i[b + k]);
                }
                _Diff(sync, id, _UnitDict(u), FAST_KEYS, ud, ux);
                i += 1;
            }
            var ids_a = ids.ToArray();
            if (!_SameStrs(ids_a, _Strs(sync["ids"])))
            {
                // units came or went: their cached keys go with them
                var live = new GDict();
                foreach (var id in ids_a)
                    live[id] = true;
                foreach (var id in _Strs(sync["ids"]))
                {
                    if (!live.Has(id))
                    {
                        sync["c"].D.Erase(id);
                        sync["kl"].D.Erase(id);
                        sync["ksz"].D.Erase(id);
                    }
                }
                sync["ids"] = Var.Of(ids_a);
                msg["ids"] = Var.Of(ids_a);
            }
            sync["abs_i"] = Var.Of(abs_i);
            msg["u"] = Var.Of(fast);
            // the heroes' gold and recharges (each less the last snapshot's too)
            var ho = new List<string>();
            var abs_h = new int[0];
            var hf = new byte[0];
            if (sim.moba != null)
            {
                for (int t = 0; t < 2; t++)
                    foreach (var hid in sim.moba.heroes[t])
                        ho.Add(GD.Str(hid));
                var hn = HERO_FAST.Size();
                abs_h = new int[ho.Count * hn];
                hf = new byte[abs_h.Length * 2];
                int[] prev_h = _SameStrs(ho.ToArray(), _Strs(sync["ho"])) ? (sync.Get("abs_h").As<int[]>() ?? new int[0]) : new int[0];
                var hi = 0;
                foreach (var hid in ho)
                {
                    Unit h = sim.by_id.TryGetValue(hid, out var hu) ? hu : null;
                    for (int k = 0; k < hn; k++)
                    {
                        var at = hi * hn + k;
                        var v = GD.Clampi(GD.Int(GD.Round((h != null ? V.ToDouble(h.Get(HERO_FAST[k].AsString())) : 0.0) * (double)HERO_FAST_SCALE[k])), -32768, 32767);
                        abs_h[at] = v;
                        hf.EncodeS16(at * 2, _Wrap16(v - (at < prev_h.Length ? prev_h[at] : 0)));
                    }
                    hi += 1;
                }
            }
            var ho_a = ho.ToArray();
            if (!_SameStrs(ho_a, _Strs(sync["ho"])))
            {
                sync["ho"] = Var.Of(ho_a);
                msg["ho"] = Var.Of(ho_a);
            }
            sync["abs_h"] = Var.Of(abs_h);
            msg["h"] = Var.Of(hf);
            if (!ud.IsEmpty())
                msg["ud"] = ud;
            if (!ux.IsEmpty())
                msg["ux"] = ux;
            // towers, Kings, gates, camps
            var od = new GDict();
            var ox = new GDict();
            foreach (var pair in _Objs(sim))
            {
                string pre = pair[0].AsString();
                IList list = (IList)pair[1].Obj;
                for (int j = 0; j < list.Count; j++)
                    _Diff(sync, pre + ":" + GD.Str(j), _ObjDict(list[j]), OBJ_SKIP[pre].D, od, ox);
            }
            if (!od.IsEmpty())
                msg["o"] = od;
            if (!ox.IsEmpty())
                msg["ox"] = ox;
            // zones, traps, wards, the Wyrm's stacks
            var blobs = _Blobs(sim);
            foreach (var k in blobs)
            {
                Var v = blobs[k];
                if (!sync["blob"].D.Has(k) || sync["blob"].D[k] != v)
                {
                    Var sv = v.Duplicate(true);
                    sync["blob"].D[k] = sv;
                    msg[k] = sv;
                }
            }
            msg["p"] = Var.Of(_PackProj(sim));
            sync["last"] = GDict.Of("tm", msg["tm"], "sc", msg["sc"], "k", msg["k"], "end", msg["end"], "p", msg["p"]);
            return msg;
        }

        public static GDict Keyframe(Sim sim)
        {
            // Everything a phone needs to draw the match as of the last snapshot sent (the next one builds on it): for a player
            // just seated, back from a drop, or whose socket dropped a snapshot. Nothing sent yet: the first snapshot is one.
            var sync = _SyncOf(sim);
            if (sync["last"].D.IsEmpty())
            {
                var first = Snapshot(sim, "", new GArray());
                first["kf"] = true;
                return first;
            }
            var msg = GDict.Of("t", "s", "kf", true, "e", new GArray(), "ids", sync["ids"], "ho", sync["ho"], "u", Var.Of(_Bytes16(sync["abs_i"].As<int[]>() ?? new int[0])), "h", Var.Of(_Bytes16(sync["abs_h"].As<int[]>() ?? new int[0])));
            msg.Merge(sync["last"].D);
            var ud = new GDict();
            foreach (var id in _Strs(sync["ids"]))
                ud[id] = sync["c"].D.Get(id, new GDict());
            msg["ud"] = ud;
            var od = new GDict();
            foreach (var k in sync["c"].D)
            {
                if (GD.Str(k).Contains(":"))
                    od[k] = sync["c"].D[k];
            }
            msg["o"] = od;
            msg.Merge(sync["blob"].D);
            return msg;
        }

        public static byte[] _Bytes16(int[] v)
        {
            var o = new byte[v.Length * 2];
            for (int i = 0; i < v.Length; i++)
                o.EncodeS16(i * 2, v[i]);
            return o;
        }

        public static byte[] _PackProj(Sim sim)
        {
            // 6 x 16 bits each: id, x, z (1 cm), vx, vz (1 cm/s), kind (+16: a big one, the Ranger's DEADEYE)
            var proj = new byte[sim.projectiles.Count * 12];
            var pi = 0;
            foreach (var p in sim.projectiles)
            {
                var vals_p = new double[] { p.id % 65536 - 32768, p.pos.x * 100.0, p.pos.y * 100.0, p.vel.x * 100.0,
                    p.vel.y * 100.0, GD.Maxi(0, PROJ_KINDS.Find(GD.Str(p.kind))) + (p.big ? 16 : 0) };
                for (int k = 0; k < 6; k++)
                    _S16(proj, pi * 6 + k, vals_p[k]);
                pi += 1;
            }
            return proj;
        }

        // ---------------- client side ----------------
        public static void Apply(Sim sim, GDict msg, string me_id, bool predict = false)
        {
            // Brings the mirror sim to the snapshot. Unit positions go into each unit's history (net_hist: interpolate_at draws
            // remote units between them); everything else is set directly.
            // The phone predicts its own unit: keep its position/facing (and a dodge or swing it started) unless the server
            // disagrees by > PREDICT_SNAP or the unit is in a server-driven state (0.18.4).
            var mine_prev = new GDict();
            if (predict && sim.by_id.ContainsKey(me_id))
            {
                Unit mp = sim.by_id[me_id];
                mine_prev = GDict.Of("pos", mp.pos, "face", mp.face, "state", mp.state, "t", mp.t);
            }
            GDict sync = _NetSync(sim);
            var kf = (bool)msg.Get("kf", false);
            sim.time = (double)msg.Get("tm", sim.time);
            double snap_t = sim.time;
            sim.score = _ToInts(msg.Get("sc"), sim.score);
            sim.kills = _ToInts(msg.Get("k"), sim.kills);
            GArray end = msg.Get("end", GArray.Of(false, -1, "")).A;
            sim.ended = (bool)end[0];
            sim.winner = (int)end[1];
            sim.end_reason = GD.Str(end[2]);
            GDict ud = msg.Get("ud", new GDict()).D;
            // the units: new ones made, gone ones dropped, in the server's order
            if (msg.Has("ids"))
            {
                string[] ids = _Strs(msg["ids"]);
                var keep = new List<Unit>();
                foreach (var id in ids)
                {
                    Unit u = sim.by_id.TryGetValue(id, out var uu) ? uu : null;
                    if (u == null)
                    {
                        GDict d0 = ud.Get(id, new GDict()).D;
                        u = sim.NewUnit(id, GD.Int(d0.Get("team", 0)), (bool)d0.Get("bot", true));
                        u.Set("net_new", true);
                        sim.by_id[id] = u;
                    }
                    keep.Add(u);
                }
                var live = new GDict();
                foreach (var id in ids)
                    live[id] = true;
                foreach (var u in sim.units)
                {
                    if (!live.Has(GD.Str(u.id)))
                        sim.by_id.Remove(u.id);
                }
                sim.units.Clear();
                sim.units.AddRange(keep);
                sync["ids"] = Var.Of(ids);
            }
            string[] ids_now = _Strs(sync.Get("ids"));
            var hero_changed = false;
            foreach (var id in ud)
            {
                Unit u = sim.by_id.TryGetValue(id.AsString(), out var uu) ? uu : null;
                if (u == null)
                    continue;
                GDict d = ud[id].D;
                if (kf)
                {
                    foreach (var k in _UnitKeys(u))
                    {
                        if (!d.Has(k) && !_ClientKey(k))
                            u.Erase(k);                      // (a key the server's unit doesn't have: the mirror's own draft)
                    }
                }
                foreach (var k in d)
                    _UnitSet(u, k.AsString(), d[k]);
                if (d.Has("hid"))
                    hero_changed = true;
            }
            GDict ux = msg.Get("ux", new GDict()).D;
            foreach (var id in ux)
            {
                Unit u = sim.by_id.TryGetValue(id.AsString(), out var uu) ? uu : null;
                foreach (var k in ux[id])
                    u?.Erase(k.AsString());
            }
            if (hero_changed && sim.moba != null)
            {
                foreach (var u in sim.units)
                {
                    if (u.hid != "")                     // (u.has("hid"))
                        sim.moba.hero_of[GD.Str(u.id)] = GD.Str(u.hid);
                }
            }
            // the fast values: each the last snapshot's plus what this one says (a keyframe's are the values themselves)
            byte[] fast = msg.Get("u").As<byte[]>() ?? new byte[0];
            int n_units = GD.Mini(ids_now.Length, fast.Length / (FAST * 2));
            for (int i = 0; i < n_units; i++)
            {
                Unit u = sim.by_id.TryGetValue(ids_now[i], out var uu) ? uu : null;
                if (u == null)
                    continue;
                var b = i * FAST;
                int[] nf = u.Get("net_f") as int[] ?? new int[0];
                if (kf || nf.Length != FAST)
                {
                    nf = new int[FAST];
                }
                for (int k = 0; k < FAST; k++)
                    nf[k] = _Wrap16(nf[k] + fast.DecodeS16((b + k) * 2));
                u.Set("net_f", nf);
                bool was_dead = u.state == "dead";
                u.hp = (double)nf[0];
                var to = new Vector2((double)nf[1] / 100.0, (double)nf[2] / 100.0);
                var face = (double)nf[3] / 1000.0;
                string state = STATES[GD.Clampi(nf[4], 0, STATES.Size() - 1)].AsString();
                if (V.ToBool(u.Get("net_new")))
                {
                    u.Erase("net_new");
                    u.pos = to;                           // (a new unit: where it is, no sliding in from the field's middle)
                    u.face = face;
                }
                _PushHist(u, snap_t, to, face);
                u.Set("net_from", u.pos);
                u.Set("net_to", to);
                if (was_dead != (state == "dead") || u.pos.DistanceTo(to) > 6.0)
                {
                    u.pos = to;                           // respawn / teleport: no sliding across the map
                    u.Set("net_from", to);
                }
                u.face = face;
                u.state = state;
                u.stun = (double)nf[5] / 100.0;
                u.cd_ability = (double)nf[6] / 100.0;
            }
            if (msg.Has("ho"))
                sync["ho"] = Var.Of(_Strs(msg["ho"]));
            string[] ho = _Strs(sync.Get("ho"));
            byte[] hf = msg.Get("h").As<byte[]>() ?? new byte[0];
            var hn = HERO_FAST.Size();
            int[] hv = sync.Get("hv").As<int[]>() ?? new int[0];
            if (kf || msg.Has("ho") || hv.Length != ho.Length * hn)
            {
                hv = new int[ho.Length * hn];
            }
            for (int hi = 0; hi < GD.Mini(ho.Length, hf.Length / (hn * 2)); hi++)
            {
                Unit h = sim.by_id.TryGetValue(ho[hi], out var hu) ? hu : null;
                for (int k = 0; k < hn; k++)
                {
                    var at = hi * hn + k;
                    hv[at] = _Wrap16(hv[at] + hf.DecodeS16(at * 2));
                    if (h != null)
                        h.Set(HERO_FAST[k].AsString(), (double)hv[at] / (double)HERO_FAST_SCALE[k]);
                }
            }
            sync["hv"] = Var.Of(hv);
            // towers, Kings, gates, camps
            GDict od = msg.Get("o", new GDict()).D;
            GDict ox = msg.Get("ox", new GDict()).D;
            if (!od.IsEmpty() || !ox.IsEmpty())
            {
                var lists = new GDict();
                foreach (var pair in _Objs(sim))
                    lists[pair[0]] = pair[1];
                foreach (var key in od)
                {
                    object o = _Obj(lists, GD.Str(key));
                    if (o == null)
                        continue;
                    if (kf)
                    {
                        foreach (var k in _ObjDict(o).Keys())
                        {
                            if (!od[key].D.Has(k) && !OBJ_SKIP[GD.Str(key).GetSlice(":", 0)].D.Has(k))
                                _ObjErase(o, k.AsString());
                        }
                    }
                    foreach (var k in od[key].D)          // (o.merge(od[key], true))
                        _ObjSet(o, k.AsString(), od[key].D[k]);
                }
                foreach (var key in ox)
                {
                    object o2 = _Obj(lists, GD.Str(key));
                    foreach (var k in ox[key])
                    {
                        if (o2 != null)
                            _ObjErase(o2, k.AsString());
                    }
                }
            }
            if (sim.moba != null)
            {
                if (msg.Has("zn"))
                    sim.moba.kits.zones = _Zones(msg["zn"]);
                if (msg.Has("tr"))
                    sim.moba.kits.traps = _Traps(msg["tr"]);
                if (msg.Has("wd"))
                    sim.moba.vision.wards = _Wards(msg["wd"]);
                if (msg.Has("ws"))
                    sim.moba.wyrm_stacks = _ToInts(msg["ws"], sim.moba.wyrm_stacks);
                if (msg.Has("ek"))
                    sim.moba.epic_kills = _Epic(msg["ek"]);                // 0.31.176: the epic monsters each side slew (the scoreboard)
            }
            _ApplyProj(sim, msg, snap_t);
            if (!mine_prev.IsEmpty() && sim.by_id.ContainsKey(me_id))
            {
                Unit me2 = sim.by_id[me_id];
                Var nt = Var.Of(me2.Get("net_to"));
                Vector2 server_pos = nt.IsVec2 ? nt.V2 : me2.pos;
                me2.Erase("net_to");
                me2.Erase("net_from");
                me2.Set("srv_pos", server_pos);
                double drift = mine_prev["pos"].V2.DistanceTo(server_pos);
                if (sim.ClientDrivable(me2) && drift <= PREDICT_SNAP)
                {
                    // 0.31.24: past PREDICT_SOFT the server's position pulls ours back a little each snapshot, so a correction
                    // is a slide rather than a 2.5 m teleport (the server's position is a round trip old, so only a little)
                    me2.pos = drift <= PREDICT_SOFT ? mine_prev["pos"].V2 : mine_prev["pos"].V2.Lerp(server_pos, 0.12);
                    me2.face = (double)mine_prev["face"];
                    // A dodge or swing we started locally keeps playing until its timer runs out (the server's
                    // confirmation arrives a round trip later).
                    if (GArray.Of("dodge", "wind", "recover").Has(GD.Str(mine_prev["state"])) && (double)mine_prev["t"] > 0.0)
                    {
                        me2.state = mine_prev["state"].AsString();
                        me2.t = (double)mine_prev["t"];
                    }
                }
                else
                    me2.pos = server_pos;
            }
            // the fog of war: worked out here from what the snapshot brought, as often as the server does
            if (sim.moba != null && sim.moba.vision != null && (kf || snap_t - (double)sync.Get("vis_at", -99.0) >= MobaVision.EVERY))
            {
                sync["vis_at"] = snap_t;
                sim.moba.vision.Update();
            }
        }

        public static bool _ClientKey(string k)
        {
            // a key the phone keeps on a unit whatever a keyframe says: its own (the draw history, the prediction) and the
            // keys the snapshot carries some other way or never
            return NO_SYNC.Has(k) || FAST_KEYS.Has(k) || k.BeginsWith("net_") || k == "srv_pos";
        }

        public static object _Obj(GDict lists, string key)
        {
            IList list = lists.Get(key.GetSlice(":", 0)).Obj as IList;
            var j = (int)key.GetSlice(":", 1).ToInt();
            return list != null && j >= 0 && j < list.Count ? list[j] : null;
        }

        public static void _ApplyProj(Sim sim, GDict msg, double snap_t)
        {
            // Projectiles slide between snapshots like units (0.18.5, Kevin: "projectiles skip across the
            // screen online"): they used to be redrawn only at each snapshot's position, so an arrow at
            // 22 m/s sat still for 66 ms and then jumped 1.5 m. Now each keeps from/to: a new one starts at
            // its spawn point (on the same one-interval-behind timeline as the units it flies between), and
            // one that ended this snapshot gets one last slide to its impact point before it disappears.
            // 0.31.207 (Kevin: "the projectiles aren't smooth when traveling"): from/to slid against the render clock, which runs
            // INTERP_DELAY (75 ms+) behind the newest snapshot -- past each snapshot's interval -- so every 50 ms it jumped half a
            // step ahead and sat still for a moment, and it vanished a snapshot before it reached what it hit. Now a projectile
            // keeps a history of its positions with their server times, as the units do (net_hist), and is drawn on the same
            // render clock (interpolate_at): between the two samples round it, past the newest along its velocity; one that
            // ended keeps flying (a ghost) to its impact point, reached when it got there, then goes. net_to stays its newest
            // position (the tests compare it with the server's).
            var old = new ODict<int, Proj>();
            foreach (var p in sim.projectiles)
                old[p.id] = p;
            sim.projectiles.Clear();
            var seen = new GDict();
            byte[] pb = msg.Get("p").As<byte[]>() ?? new byte[0];
            for (int pi = 0; pi < pb.Length / 12; pi++)
            {
                var v = new GArray();
                for (int k = 0; k < 6; k++)
                    v.Append(pb.DecodeS16((pi * 6 + k) * 2));
                var pid = GD.Int(v[0]) + 32768;
                var to = new Vector2((double)v[1] / 100.0, (double)v[2] / 100.0);
                Proj prev = old.Get(pid, null);
                var kc = GD.Int(v[5]);
                GArray hist = (prev != null ? _PX(prev).Get("net_hist", new GArray()).A : new GArray()).Duplicate();
                if (hist.IsEmpty() || (double)hist[-1][0] < snap_t)
                    hist.Append(GArray.Of(snap_t, to));
                while (hist.Size() > PROJ_HIST)
                    hist.PopFront();
                var p = new Proj { id = pid, pos = prev != null ? prev.pos : to,
                    vel = new Vector2((double)v[3] / 100.0, (double)v[4] / 100.0),
                    kind = PROJ_KINDS[GD.Clampi(kc % 16, 0, PROJ_KINDS.Size() - 1)].AsString(), team = -1 };
                _PX(p).Merge(GDict.Of("net_to", to, "net_t", snap_t, "net_hist", hist));
                if (kc >= 16)
                    p.big = true;
                sim.projectiles.Add(p);
                seen[pid] = true;
            }
            var ends = new GDict();
            foreach (var e in msg.Get("e", new GArray()))
            {
                if (e.IsDict && GD.Str(e.D.Get("k", "")) == "proj_end" && e.D.Has("pos"))
                    ends[e.D.Get("pid")] = e.D["pos"];
            }
            foreach (var kv in old)
            {
                int id = kv.Key;
                Proj gone = kv.Value;
                GDict gx = _PX(gone);
                if (seen.Has(id))
                    continue;
                if ((bool)gx.Get("ghost", false))
                {
                    // still on its way to where it hit (the render clock is behind): kept until it gets there
                    if (snap_t - (double)gx.Get("end_t", snap_t) < 1.0)
                        sim.projectiles.Add(gone);
                }
                else if (ends.Has(id) && gx.Has("net_hist"))
                {
                    // it hit (or ended) since the last snapshot: one last leg from its newest sample to the impact, at its speed
                    GArray hist2 = gx["net_hist"].A.Duplicate();
                    GArray last = hist2[-1].A;
                    Vector2 endp = ends[id].V2;
                    var speed = GD.Maxf(gone.vel.Length(), 1.0);
                    var t_end = GD.Minf((double)last[0] + last[1].V2.DistanceTo(endp) / speed, snap_t);
                    t_end = GD.Maxf(t_end, (double)last[0] + 0.001);
                    hist2.Append(GArray.Of(t_end, endp));
                    var gp = new Proj { id = id, pos = gone.pos, vel = gone.vel, kind = gone.kind, team = -1 };
                    _PX(gp).Merge(GDict.Of("net_to", endp, "net_t", t_end, "net_hist", hist2, "ghost", true, "end_t", t_end));
                    if (gone.big)                          // (gone.has("big"))
                        gp.big = true;
                    sim.projectiles.Add(gp);
                }
            }
        }

        public static void Interpolate(Sim sim, double alpha)
        {
            // Called every frame between snapshots: slide unit positions from the previous snapshot to
            // the latest (alpha 0..1 across one snapshot interval).
            var a = GD.Clampf(alpha, 0.0, 1.0);
            foreach (var u in sim.units)
            {
                if (u.Get("net_to") != null)
                    u.pos = Var.Of(u.Get("net_from")).V2.Lerp(Var.Of(u.Get("net_to")).V2, a);
            }
            foreach (var p in sim.projectiles)
            {
                GDict px = _PX(p);
                if (px.Has("net_from"))
                    p.pos = px["net_from"].V2.Lerp(px["net_to"].V2, a);
            }
        }


        // ---------- timed interpolation (0.31.23) ----------
        // Every snapshot's positions are kept with their server time (HIST per unit). The client draws remote units at a render
        // time INTERP_DELAY behind the newest snapshot, between the two samples round that time, so a late or early packet
        // doesn't freeze or jump them (the old scheme slid from the last position to the newest over an estimated interval and
        // stuttered with any jitter). Past the newest sample it extrapolates a little, then holds.
        public static void _PushHist(Unit o, double t, Vector2 pos, double face)
        {
            GArray h = o.Get("net_hist") as GArray ?? new GArray();
            if (!h.IsEmpty() && (double)h[-1][0] >= t)
                return;
            h.Append(GArray.Of(t, pos, face));
            while (h.Size() > HIST)
                h.PopFront();
            o.Set("net_hist", h);
        }

        public static void InterpolateAt(Sim sim, double rt, string skip_id)
        {
            foreach (var u in sim.units)
            {
                if (u.id == skip_id || !(u.Get("net_hist") is GArray))
                    continue;
                GArray h = (GArray)u.Get("net_hist");
                if (h.Size() < 2)
                    continue;
                GArray newest = h[-1].A;
                if (rt >= (double)newest[0])
                {
                    // a little extrapolation, then hold (a late packet shouldn't drag him to a halt)
                    GArray prev = h[-2].A;
                    var span = GD.Maxf((double)newest[0] - (double)prev[0], 0.001);
                    var ahead = GD.Minf(rt - (double)newest[0], 0.12);
                    u.pos = newest[1].V2 + (newest[1].V2 - prev[1].V2) * (ahead / span);
                    u.face = (double)newest[2];
                    continue;
                }
                for (int k = h.Size() - 1; k > 0; k--)
                {
                    GArray b = h[k].A;
                    GArray a2 = h[k - 1].A;
                    if (rt >= (double)a2[0])
                    {
                        var f = GD.Clampf((rt - (double)a2[0]) / GD.Maxf((double)b[0] - (double)a2[0], 0.001), 0.0, 1.0);
                        if (a2[1].V2.DistanceTo(b[1].V2) > 6.0)
                            f = f > 0.5 ? 1.0 : 0.0;            // a respawn or teleport between samples: no sliding
                        u.pos = a2[1].V2.Lerp(b[1].V2, f);
                        u.face = GD.LerpAngle((double)a2[2], (double)b[2], f);
                        break;
                    }
                }
            }
            // 0.31.207: projectiles on the same render clock (see _apply_proj): before their first sample, back along their
            // velocity from it (they left the hand within the snapshot before; held there, at the hand, until then); between
            // samples, along the line; past the newest, on along their velocity (a little); a ghost gone once the clock passes
            // its impact
            var done = false;
            foreach (var p in sim.projectiles)
            {
                GDict px = _PX(p);
                if (!px.Has("net_hist"))
                    continue;
                GArray ph = px["net_hist"].A;
                if (rt <= (double)ph[0][0])
                {
                    p.pos = ph[0][1].V2 - p.vel * GD.Minf((double)ph[0][0] - rt, 1.0 / SNAP_HZ);
                    continue;
                }
                GArray pn = ph[-1].A;
                if (rt >= (double)pn[0])
                {
                    if ((bool)px.Get("ghost", false))
                    {
                        px["done"] = true;
                        done = true;
                        p.pos = pn[1].V2;
                        continue;
                    }
                    p.pos = pn[1].V2 + p.vel * GD.Minf(rt - (double)pn[0], 0.25);
                    continue;
                }
                for (int k = ph.Size() - 1; k > 0; k--)
                {
                    GArray pa = ph[k - 1].A;
                    if (rt >= (double)pa[0])
                    {
                        GArray pb2 = ph[k].A;
                        var f = GD.Clampf((rt - (double)pa[0]) / GD.Maxf((double)pb2[0] - (double)pa[0], 0.001), 0.0, 1.0);
                        p.pos = pa[1].V2.Lerp(pb2[1].V2, f);
                        break;
                    }
                }
            }
            if (done)
                sim.projectiles = sim.projectiles.FindAll(p => !(bool)_PX(p).Get("done", false));
        }

        // =====================================================================================================================
        // The wire's dictionaries <-> the sim's records (port only; see the note at the top of the file)
        // =====================================================================================================================

        /// <summary>The protocol's sync state (GDScript's sim.net_sync Dictionary), kept in the C# sim's net_sync.</summary>
        public static GDict _NetSync(Sim sim)
        {
            if (!(sim.net_sync.TryGetValue("net", out var o) && o is GDict d))
            {
                d = new GDict();
                sim.net_sync["net"] = d;
            }
            return d;
        }

        /// <summary>A projectile's keys the typed Proj has no field for (net_to, net_t, net_hist, ghost, end_t, done).</summary>
        static readonly ConditionalWeakTable<Proj, GDict> _proj_extra = new ConditionalWeakTable<Proj, GDict>();
        public static GDict _PX(Proj p) => _proj_extra.GetValue(p, _ => new GDict());

        /// <summary>A wire event (a Dictionary of a snapshot's "e") as the sim's Ev, for the view, the HUD, the sounds.</summary>
        public static Ev ToEv(Var e)
        {
            var o = new Ev();
            if (!e.IsDict)
                return o;
            foreach (var k in e.D)
                o[k.AsString()] = _Obj(e.D[k]);
            return o;
        }

        /// <summary>A sim event as the Dictionary a snapshot's "e" carries.</summary>
        public static GDict WireEvent(Ev e) => _V(e).D;

        /// <summary>A Var as the plain value the sim's records and events hold (int, double, bool, string, Vec2, Vec3,
        /// List of those, Ev for a dictionary; packed arrays as their arrays).</summary>
        static object _Obj(Var v)
        {
            switch (v.Type)
            {
                case VT.Nil: return null;
                case VT.Bool: return v.B;
                case VT.Int: { long l = v.L; return l >= int.MinValue && l <= int.MaxValue ? (object)(int)l : l; }
                case VT.Float: return v.F;
                case VT.String: return v.AsString();
                case VT.Vec2: return v.V2;
                case VT.Vec2i: return v.AsVec2i();
                case VT.Vec3: return v.V3;
                case VT.Arr:
                    {
                        var l = new List<object>();
                        foreach (var x in v.A) l.Add(_Obj(x));
                        return l;
                    }
                case VT.Dict:
                    {
                        var d = new Ev();
                        foreach (var k in v.D) d[k.AsString()] = _Obj(v.D[k]);
                        return d;
                    }
            }
            return v.Obj;
        }

        /// <summary>A record's or event's value as the Godot value GDScript held (what var_to_bytes encodes).</summary>
        public static Var _V(object o)
        {
            switch (o)
            {
                case null: return Var.Nil;
                case Var v: return v;
                case GDict gd: return gd;
                case GArray ga: return ga;
                case byte[] _: case string[] _: case int[] _: case long[] _: case float[] _: case double[] _: case Vector2[] _: case Vector3[] _:
                    return Var.Of(o);                       // (packed arrays)
                case ODict<string, int> oi:
                    {
                        var d = new GDict();
                        foreach (var kv in oi) d[kv.Key] = kv.Value;
                        return d;
                    }
                case ODict<string, double> od:
                    {
                        var d = new GDict();
                        foreach (var kv in od) d[kv.Key] = kv.Value;
                        return d;
                    }
                case IDictionary<string, object> sd:
                    {
                        var d = new GDict();
                        foreach (var kv in sd) d[kv.Key] = _V(kv.Value);
                        return d;
                    }
                case Dance dn: return GDict.Of("ids", _V(dn.ids), "i", dn.i, "next", dn.next, "dmg", dn.dmg, "missing", dn.missing);
                case Riposte rp: return GDict.Of("until", rp.until, "hit", rp.hit, "r", rp.r, "dmg", rp.dmg, "stun", rp.stun);
                case Dot dt: return GDict.Of("by", dt.by, "team", dt.team, "dps", dt.dps, "until", dt.until, "next", dt.next, "heal", dt.heal);
                case LandFx lf: return GDict.Of("r", lf.r, "dmg", lf.dmg, "slow", lf.slow, "dur", lf.dur, "stun", lf.stun);
                case Dash ds:
                    {
                        var d = GDict.Of("dir", ds.dir, "left", ds.left, "total", ds.total, "speed", ds.speed, "hits", _V(ds.hits));
                        if (ds.dmg != 0.0) d["dmg"] = ds.dmg;
                        if (ds.stun != 0.0) d["stun"] = ds.stun;
                        if (ds.refund != 0.0) d["refund"] = ds.refund;
                        if (ds.first) d["first"] = true;
                        if (ds.through) d["through"] = true;
                        if (ds.leap) d["leap"] = true;
                        if (ds.land != null) d["land"] = _V(ds.land);
                        return d;
                    }
                case Trap tp: return GDict.Of("id", tp.id, "team", tp.team, "owner", tp.owner, "at", tp.at, "armed_at", tp.armed_at, "until", tp.until, "r", tp.r, "dmg", tp.dmg, "stun", tp.stun);
                case Ward wd: return GDict.Of("id", wd.id, "team", wd.team, "owner", wd.owner, "p", wd.p, "until", wd.until, "brush", wd.brush);
                case IList l:
                    {
                        var a = new GArray();
                        foreach (var x in l) a.Append(_V(x));
                        return a;
                    }
            }
            return Var.Of(o);
        }

        static GArray _IntsArr(int[] a)
        {
            var o = new GArray();
            foreach (var x in a) o.Append(x);
            return o;
        }

        static int[] _ToInts(Var v, int[] dflt)
        {
            if (v.IsArr)
            {
                var o = new int[v.A.Size()];
                for (int i = 0; i < o.Length; i++) o[i] = GD.Int(v.A[i]);
                return o;
            }
            if (v.Obj is int[] ia) return ia;
            return dflt;
        }

        static string[] _Strs(Var v)
        {
            if (v.Obj is string[] s) return s;
            if (v.IsArr)
            {
                var o = new string[v.A.Size()];
                for (int i = 0; i < o.Length; i++) o[i] = GD.Str(v.A[i]);
                return o;
            }
            return new string[0];
        }

        static bool _SameStrs(string[] a, string[] b)
        {
            if (a.Length != b.Length) return false;
            for (int i = 0; i < a.Length; i++) if (a[i] != b[i]) return false;
            return true;
        }

        static List<string> _StrList(Var v)
        {
            if (v.IsNil) return null;
            var o = new List<string>();
            foreach (var x in v) o.Add(GD.Str(x));
            return o;
        }

        // ---- units ----
        /// <summary>The unit's keys (u.keys()): every field with a value (an object field's null is an absent key), then the
        /// keys only the dictionary had (`extra`).</summary>
        public static List<string> _UnitKeys(Unit u)
        {
            var o = new List<string>();
            foreach (var k in Unit.FieldNames)
                if (u.Get(k) != null) o.Add(k);
            if (u.extra != null)
                o.AddRange(u.extra.Keys);
            return o;
        }

        /// <summary>The unit as GDScript's unit Dictionary (the server's diff reads it).</summary>
        public static GDict _UnitDict(Unit u)
        {
            var d = new GDict();
            foreach (var k in _UnitKeys(u))
                d[k] = _V(u.Get(k));
            return d;
        }

        /// <summary>u[k] = v from the wire: the value converted to the field's type (a key with no field: kept as is).</summary>
        public static void _UnitSet(Unit u, string k, Var v)
        {
            switch (k)
            {
                case "path":
                    {
                        List<Vector2> l = null;
                        if (!v.IsNil)
                        {
                            l = new List<Vector2>();
                            if (v.Obj is Vector2[] pa) l.AddRange(pa);
                            else foreach (var x in v) l.Add(x.V2);
                        }
                        u.path = l;
                        return;
                    }
                case "picks":
                    {
                        List<List<string>> l = null;
                        if (!v.IsNil)
                        {
                            l = new List<List<string>>();
                            foreach (var x in v) l.Add(_StrList(x) ?? new List<string>());
                        }
                        u.picks = l;
                        return;
                    }
                case "ups":
                case "rk":
                    {
                        ODict<string, int> m = null;
                        if (v.IsDict)
                        {
                            m = new ODict<string, int>();
                            foreach (var x in v.D) m[GD.Str(x)] = GD.Int(v.D[x]);
                        }
                        u.Set(k, m);
                        return;
                    }
                case "items":
                case "bought":
                    u.Set(k, _StrList(v));
                    return;
                case "buffs":
                case "hit_log":
                case "cc_log":
                case "heal_log":
                    {
                        ODict<string, double> m = null;
                        if (v.IsDict)
                        {
                            m = new ODict<string, double>();
                            foreach (var x in v.D) m[GD.Str(x)] = (double)v.D[x];
                        }
                        u.Set(k, m);
                        return;
                    }
                case "dance":
                    u.dance = !v.IsDict ? null : new Dance { ids = _StrList(v.D.Get("ids")) ?? new List<string>(), i = GD.Int(v.D.Get("i", 0)),
                        next = (double)v.D.Get("next", 0.0), dmg = (double)v.D.Get("dmg", 0.0), missing = (double)v.D.Get("missing", 0.0) };
                    return;
                case "riposte":
                    u.riposte = !v.IsDict ? null : new Riposte { until = (double)v.D.Get("until", 0.0), hit = (bool)v.D.Get("hit", false),
                        r = (double)v.D.Get("r", 0.0), dmg = (double)v.D.Get("dmg", 0.0), stun = (double)v.D.Get("stun", 0.0) };
                    return;
                case "dots":
                    {
                        List<Dot> l = null;
                        if (!v.IsNil)
                        {
                            l = new List<Dot>();
                            foreach (var x in v)
                                l.Add(new Dot { by = GD.Str(x.D.Get("by", "")), team = GD.Int(x.D.Get("team", -1)), dps = (double)x.D.Get("dps", 0.0),
                                    until = (double)x.D.Get("until", 0.0), next = (double)x.D.Get("next", 0.0), heal = (bool)x.D.Get("heal", false) });
                        }
                        u.dots = l;
                        return;
                    }
                case "dash":
                    {
                        if (!v.IsDict) { u.dash = null; return; }
                        var d = v.D;
                        var ds = new Dash { dir = d.Get("dir").V2, left = (double)d.Get("left", 0.0), total = (double)d.Get("total", 0.0),
                            speed = (double)d.Get("speed", 0.0), hits = _StrList(d.Get("hits")) ?? new List<string>(),
                            dmg = (double)d.Get("dmg", 0.0), stun = (double)d.Get("stun", 0.0), refund = (double)d.Get("refund", 0.0),
                            first = (bool)d.Get("first", false), through = (bool)d.Get("through", false), leap = (bool)d.Get("leap", false) };
                        if (d.Get("land").IsDict)
                        {
                            var ld = d["land"].D;
                            ds.land = new LandFx { r = (double)ld.Get("r", 0.0), dmg = (double)ld.Get("dmg", 0.0), slow = (double)ld.Get("slow", 0.0),
                                dur = (double)ld.Get("dur", 1.0), stun = (double)ld.Get("stun", 0.0) };
                        }
                        u.dash = ds;
                        return;
                    }
            }
            if (Array.IndexOf(Unit.FieldNames, k) >= 0)
                u.Set(k, v.Obj);
            else
                u.Set(k, v);                                  // (a key the typed unit has no field for: the Var itself)
        }

        // ---- towers, Kings, gates, camps ----
        /// <summary>A tower's / King's / gate's / camp's Dictionary (its keys as GDScript's record had them).</summary>
        public static GDict _ObjDict(object o)
        {
            switch (o)
            {
                case Tower tw:
                    {
                        var d = GDict.Of("id", tw.id, "team", tw.team, "lane", tw.lane, "tier", tw.tier, "p", tw.p, "hp", tw.hp, "max_hp", tw.max_hp,
                            "dead", tw.dead, "target", tw.target, "ramp", tw.ramp, "ramp_id", tw.ramp_id, "next", tw.next);
                        if (tw.ramp_at != -99.0) d["ramp_at"] = tw.ramp_at;
                        if (tw.plates != 0) d["plates"] = tw.plates;
                        return d;
                    }
                case KingSt kg:
                    return GDict.Of("hp", kg.hp, "max_hp", kg.max_hp, "dead", kg.dead, "next", kg.next, "quiet", kg.quiet);
                case Gate g:
                    {
                        var d = GDict.Of("id", g.id, "team", g.team, "a", g.a, "b", g.b, "c", g.c, "hp", g.hp, "max_hp", g.max_hp,
                            "broken", g.broken, "open", g.open, "side", g.side, "lane", g.lane);
                        if (g.hasIn) d["in"] = g.@in;
                        if (!double.IsNegativeInfinity(g.hit_at)) d["hit_at"] = g.hit_at;
                        if (!double.IsNegativeInfinity(g.broken_at)) d["broken_at"] = g.broken_at;
                        return d;
                    }
                case Camp cp:
                    return GDict.Of("id", cp.id, "kind", cp.kind, "side", cp.side, "p", cp.p, "mobs", _V(cp.mobs), "alive", cp.alive,
                        "next", cp.next, "target", cp.target, "hits", _V(cp.hits), "slam", cp.slam, "patience", cp.patience, "reset", cp.reset,
                        "reset_at", cp.reset_at);
            }
            return new GDict();
        }

        /// <summary>o[k] = v from the wire (o.merge(od[key], true)).</summary>
        public static void _ObjSet(object o, string k, Var v)
        {
            switch (o)
            {
                case Tower tw:
                    switch (k)
                    {
                        case "id": tw.id = GD.Int(v); return;
                        case "team": tw.team = GD.Int(v); return;
                        case "lane": tw.lane = GD.Int(v); return;
                        case "tier": tw.tier = GD.Int(v); return;
                        case "p": tw.p = v.V2; return;
                        case "hp": tw.hp = (double)v; return;
                        case "max_hp": tw.max_hp = (double)v; return;
                        case "dead": tw.dead = (bool)v; return;
                        case "target": tw.target = GD.Str(v); return;
                        case "ramp": tw.ramp = GD.Int(v); return;
                        case "ramp_id": tw.ramp_id = GD.Str(v); return;
                        case "next": tw.next = (double)v; return;
                        case "ramp_at": tw.ramp_at = (double)v; return;
                        case "plates": tw.plates = GD.Int(v); return;
                    }
                    return;
                case KingSt kg:
                    switch (k)
                    {
                        case "hp": kg.hp = (double)v; return;
                        case "max_hp": kg.max_hp = (double)v; return;
                        case "dead": kg.dead = (bool)v; return;
                        case "next": kg.next = (double)v; return;
                        case "quiet": kg.quiet = (double)v; return;
                    }
                    return;
                case Gate g:
                    switch (k)
                    {
                        case "id": g.id = GD.Int(v); return;
                        case "team": g.team = GD.Int(v); return;
                        case "lane": g.lane = GD.Int(v); return;
                        case "a": g.a = v.V2; return;
                        case "b": g.b = v.V2; return;
                        case "c": g.c = v.V2; return;
                        case "in": g.@in = v.V2; g.hasIn = true; return;
                        case "hp": g.hp = (double)v; return;
                        case "max_hp": g.max_hp = (double)v; return;
                        case "r": g.r = (double)v; return;
                        case "broken": g.broken = (bool)v; return;
                        case "open": g.open = (bool)v; return;
                        case "side": g.side = GD.Str(v); return;
                        case "hit_at": g.hit_at = (double)v; return;
                        case "broken_at": g.broken_at = (double)v; return;
                    }
                    return;
                case Camp cp:
                    switch (k)
                    {
                        case "id": cp.id = GD.Int(v); return;
                        case "side": cp.side = GD.Int(v); return;
                        case "kind": cp.kind = GD.Str(v); return;
                        case "p": cp.p = v.V2; return;
                        case "mobs": cp.mobs = _StrList(v) ?? new List<string>(); return;
                        case "alive": cp.alive = (bool)v; return;
                        case "next": cp.next = (double)v; return;
                        case "target": cp.target = GD.Str(v); return;
                        case "hits":
                            {
                                var m = new ODict<string, double>();
                                if (v.IsDict) foreach (var x in v.D) m[GD.Str(x)] = (double)v.D[x];
                                cp.hits = m;
                                return;
                            }
                        case "slam": cp.slam = (double)v; return;
                        case "patience": cp.patience = (double)v; return;
                        case "reset_at": cp.reset_at = (double)v; return;
                        case "reset": cp.reset = GD.Str(v); return;
                    }
                    return;
            }
        }

        /// <summary>o.erase(k): the field back to its default (an absent key).</summary>
        public static void _ObjErase(object o, string k)
        {
            switch (o)
            {
                case Tower tw:
                    if (k == "ramp_at") tw.ramp_at = -99.0;
                    else if (k == "plates") tw.plates = 0;
                    else if (k == "target") tw.target = "";
                    else if (k == "ramp_id") tw.ramp_id = "";
                    else if (k == "dead") tw.dead = false;
                    else if (k == "ramp") tw.ramp = 0;
                    else if (k == "next") tw.next = 0.0;
                    else if (k == "hp") tw.hp = 0.0;
                    else if (k == "max_hp") tw.max_hp = 0.0;
                    return;
                case KingSt kg:
                    if (k == "hp") kg.hp = 0.0;
                    else if (k == "max_hp") kg.max_hp = 0.0;
                    else if (k == "dead") kg.dead = false;
                    else if (k == "next") kg.next = 0.0;
                    else if (k == "quiet") kg.quiet = 0.0;
                    return;
                case Gate g:
                    if (k == "hit_at") g.hit_at = double.NegativeInfinity;
                    else if (k == "broken_at") g.broken_at = double.NegativeInfinity;
                    else if (k == "in") g.hasIn = false;
                    else if (k == "broken") g.broken = false;
                    else if (k == "open") g.open = false;
                    else if (k == "hp") g.hp = 0.0;
                    else if (k == "max_hp") g.max_hp = 0.0;
                    return;
                case Camp cp:
                    if (k == "alive") cp.alive = false;
                    else if (k == "next") cp.next = 0.0;
                    else if (k == "target") cp.target = "";
                    else if (k == "mobs") cp.mobs = new List<string>();
                    else if (k == "slam") cp.slam = 0.0;
                    else if (k == "reset") cp.reset = "";
                    else if (k == "reset_at") cp.reset_at = 0.0;
                    return;
            }
        }

        // ---- zones, traps, wards, the Wyrm's stacks, the epic monsters slain ----
        public static GDict _ZoneDict(Zone z)
        {
            var d = GDict.Of("zid", z.zid, "spell", z.spell, "team", z.team, "owner", z.owner, "at", z.at, "r", z.r, "until", z.until, "next", z.next);
            if (z.dmg != 0.0) d["dmg"] = z.dmg;
            if (z.slow != 0.0) d["slow"] = z.slow;
            if (z.heal != 0.0) d["heal"] = z.heal;
            if (z.stun != 0.0) d["stun"] = z.stun;
            if (z.hasPush) d["push"] = z.push;
            if (z.hasDelay) d["delay_at"] = z.delay_at;
            if (z.hasStrike)
            {
                d["strike"] = GDict.Of("dmg", z.strikeDmg, "stun", z.strikeStun);
                d["every"] = z.every;
                d["next_at"] = z.next_at;
            }
            return d;
        }

        static List<Zone> _Zones(Var v)
        {
            var o = new List<Zone>();
            foreach (var x in v)
            {
                var d = x.D;
                if (d == null) continue;
                var z = new Zone { zid = GD.Int(d.Get("zid", 0)), spell = GD.Str(d.Get("spell", "")), team = GD.Int(d.Get("team", 0)),
                    owner = GD.Str(d.Get("owner", "")), at = d.Get("at").V2, r = (double)d.Get("r", 0.0), until = (double)d.Get("until", 0.0),
                    next = (double)d.Get("next", 0.0), dmg = (double)d.Get("dmg", 0.0), slow = (double)d.Get("slow", 0.0),
                    heal = (double)d.Get("heal", 0.0), stun = (double)d.Get("stun", 0.0) };
                if (d.Has("push")) { z.hasPush = true; z.push = (double)d["push"]; }
                if (d.Has("delay_at")) { z.hasDelay = true; z.delay_at = (double)d["delay_at"]; }
                if (d.Has("strike"))
                {
                    z.hasStrike = true;
                    z.strikeDmg = (double)d["strike"].D.Get("dmg", 0.0);
                    z.strikeStun = (double)d["strike"].D.Get("stun", 0.0);
                    z.every = (double)d.Get("every", 0.0);
                    z.next_at = (double)d.Get("next_at", 0.0);
                }
                o.Add(z);
            }
            return o;
        }

        static List<Trap> _Traps(Var v)
        {
            var o = new List<Trap>();
            foreach (var x in v)
            {
                var d = x.D;
                if (d == null) continue;
                o.Add(new Trap { id = GD.Int(d.Get("id", 0)), team = GD.Int(d.Get("team", 0)), owner = GD.Str(d.Get("owner", "")), at = d.Get("at").V2,
                    armed_at = (double)d.Get("armed_at", 0.0), until = (double)d.Get("until", 0.0), r = (double)d.Get("r", 0.0),
                    dmg = (double)d.Get("dmg", 0.0), stun = (double)d.Get("stun", 0.0) });
            }
            return o;
        }

        static List<Ward> _Wards(Var v)
        {
            var o = new List<Ward>();
            foreach (var x in v)
            {
                var d = x.D;
                if (d == null) continue;
                o.Add(new Ward { id = GD.Int(d.Get("id", 0)), team = GD.Int(d.Get("team", 0)), owner = GD.Str(d.Get("owner", "")), p = d.Get("p").V2,
                    until = (double)d.Get("until", 0.0), brush = GD.Int(d.Get("brush", -1)) });
            }
            return o;
        }

        static GDict _EpicDict(Dictionary<string, int[]> ek)
        {
            var d = new GDict();
            foreach (var kv in ek) d[kv.Key] = _IntsArr(kv.Value);
            return d;
        }

        static Dictionary<string, int[]> _Epic(Var v)
        {
            var o = new Dictionary<string, int[]>();
            if (!v.IsDict) return o;
            foreach (var k in v.D) o[GD.Str(k)] = _ToInts(v.D[k], new[] { 0, 0 });
            return o;
        }
    }
}
