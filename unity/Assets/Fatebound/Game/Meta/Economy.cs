// Ported from godot/scripts/meta/economy.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;

namespace Fatebound.Game
{
    // Fatebound Siege economy: currencies, levels, Siege Pass, challenges, shop rotation, cosmetics and
    // match rewards. Pure data + pure functions (no I/O) so it is easy to test and tune; the player's
    // state lives in scripts/meta/profile.gd.
    //
    // Everything sold is cosmetic -- but the 5v5's six sold heroes (0.31.168 for gold; 0.31.185, League's way, for gems too:
    // HERO_GEMS), each also earned with gold from playing, and twelve heroes everyone's. The store listing's "Everything you
    // unlock is cosmetic" line needs Kevin's rewording (store-listing/listing/STORE_LISTING.md).
    // 0.31.188 (Kevin: "Remove the forge and the individual weapon skins. I only want the cosmetics to be an entire outfit.
    // Each outfit has its own specific looking weapon"): the 75 weapons (CATALOG), the Arsenal packs, the shop's daily and
    // featured weapons, the Forge (stars, elements, Embers' heir) are gone. The only cosmetics are outfits (SKINS): a hero's
    // whole look -- his body repainted and a weapon of its own -- bought for gems. Titles (earned name tags) stay. What gave
    // weapons gives gold, gems, hero shards and chests: chests, the pass's item tiers, a quest's last step, the starter pack
    // (a Hero Token). Owned weapons and Forge stars simply drop from a save (Kevin: "Remove, no refund").
    // 0.31.189 (Kevin: "Now check the gold and gem economy and make sure it's balanced"; tools/economy_sim.gd plays it out):
    // gold had almost nothing left to buy -- a light player owned all six sold heroes in 5 days and sat on 190,000 gold by
    // week 16 -- and free gems ran at about twice 0.31.108's targets (the premium pass paid back ~880 of its 950). Kevin's
    // calls: a hero takes a casual player (3 matches a day) about 10 days of gold (HERO_PRICES 25,000, launch 50,000), and
    // once the heroes are his, gold buys the Frostbound outfits (SKIN_GOLD; the heroes' own sets stay gems-only). Free gems
    // back near the review's targets (light ~300 a season, casual ~550, regular ~600, grinder ~650: chests, weekly orders,
    // the quests' last step), the premium track paying back about half its price, fewer hero shards.
    public static class Economy
    {
        // 0.31.168 (Kevin: "Unlock with gold"): the 5v5 heroes you buy with gold (moba.gd HEROES; Profile.buy_hero). The twelve
        // from the old classes are everyone's.
        // 0.31.189: 25,000 each (was 2,000 -- bought in the first days; Kevin: "About 10 days" for a casual player)
        public static readonly GDict HERO_PRICES = new GDict { { "golem", 25000 }, { "dragoon", 25000 }, { "duelist", 25000 }, { "stormcaller", 25000 }, { "musketeer", 25000 }, { "druid", 25000 } };
        // 0.31.185 (Kevin: "I want the same IAP system as league of legends"): heroes the way League sells champions --
        //  - gold (League's Blue Essence, earned only: the gem -> gold packs are gone) OR gems (its RP): HERO_GEMS;
        //  - a new hero launches dearer (HERO_LAUNCH: when it came out) for LAUNCH_DAYS, then drops to its price -- and only
        //    then joins the free rotation (League: a new champion joins it in its third week);
        //  - a free rotation: FREE_HEROES of them free to play each week (Monday 00:00 UTC), in turn so each comes round;
        //  - hero shards (League's champion shards): from chests (CHESTS "shard") and the pass's free track -- unlock that hero
        //    for SHARD_UNLOCK of its gold price, or melt one for SHARD_MELT of it;
        //  - a Hero Token on the premium pass (tier 1): any locked hero, yours.
        public const int HERO_GEMS = 450;
        // hero id -> unix it came out. A static var, not a const, so a test can put a hero in (or out of) its launch; a new
        // hero's line goes here when he ships. 0.31.187 (Kevin: "Make the champions the higher price since they are new"): the
        // six launch together on 2026-10-19 00:00 UTC -- LAUNCH_GOLD / LAUNCH_GEMS until 2026-11-02, then 2,000 / 450.
        public const int SIX_LAUNCH = 1792368000;
        public static GDict HERO_LAUNCH = new GDict { { "golem", SIX_LAUNCH }, { "dragoon", SIX_LAUNCH }, { "duelist", SIX_LAUNCH }, { "stormcaller", SIX_LAUNCH },
            { "musketeer", SIX_LAUNCH }, { "druid", SIX_LAUNCH } };
        public const int LAUNCH_DAYS = 14;
        public const int LAUNCH_GOLD = 50000;   // (0.31.189: 4,000 until then -- twice the price, as before)
        public const int LAUNCH_GEMS = 600;
        public const int FREE_HEROES = 2;
        public const double SHARD_UNLOCK = 0.6;
        public const double SHARD_MELT = 0.1;   // (0.31.189: 0.2 -- with the heroes at 25,000 a melted shard was 5,000)

        // 0.31.186 (League's way, the fourth part): hero skins -- the hero's own model repainted (Meshy's retexture with his
        // UVs kept, tools/meshy_retexture.py; the textures tools/build_skins.py, assets/skins/<id>.jpg): same mesh, rig and
        // silhouette, so every hero still reads as himself, with the team ring under him. Bought for gems (SKIN_GEMS by rarity);
        // like League, a skin of a hero you haven't unlocked comes with him. Worn per hero (Profile.wear_skin), seen by everyone
        // online ("_sk" in the looks, siege_net.clean_looks).
        // 0.31.188 (Kevin: "I only want the cosmetics to be an entire outfit. Each outfit has its own specific looking weapon" /
        // "Make all new sets for every hero and make each one unique to their class and lore along with the weapons"): a skin is
        // a whole outfit -- the body and a weapon of its own:
        //  - OUTFITS: one set made for each hero (his class and his story, champions.gd), its weapon a model of its own
        //    ("weapon": {"r", "l"}, assets/meshy/weapons/<model>.glb, held like the hero's own -- siege_view MESHY_WEAPON_LIKE),
        //    epic;
        //  - Frostbound (SKIN_LINES, every hero): his own weapon repainted in frost ("weapon_tex": assets/skins/weapons/
        //    <model>_frost.jpg -- skin_weapon_texture), rare.
        public static readonly GDict SKIN_GEMS = new GDict { { "rare", 390 }, { "epic", 750 }, { "legendary", 1350 } };
        // 0.31.189 (Kevin: "Frostbound for gold"): a rare outfit (the Frostbound line) is also sold for gold -- what gold buys once
        // the heroes are yours (about two weeks of a casual player's gold). The heroes' own sets (epic) are gems only.
        public static readonly GDict SKIN_GOLD = new GDict { { "rare", 40000 } };
        public static readonly GDict SKIN_LINES = new GDict { { "frost", "Frostbound" } };
        public static readonly GDict SKIN_HEROES = new GDict { { "knight", "Knight" }, { "barbarian", "Barbarian" }, { "rogue", "Rogue" }, { "ranger", "Archer" }, { "mage", "Mage" },
            { "priest", "Priest" }, { "crusader", "Crusader" }, { "berserker", "Berserker" }, { "assassin", "Assassin" }, { "sniper", "Ranger" },
            { "archmage", "Archmage" }, { "necromancer", "Necromancer" }, { "golem", "Golem" }, { "dragoon", "Dragoon" }, { "duelist", "Duelist" },
            { "stormcaller", "Stormcaller" }, { "musketeer", "Musketeer" }, { "druid", "Druid" } };
        // id ("<hero>_<set key>") -> {set (its name), weapon {"r", "l"}} -- each hero's own set
        public static readonly GDict OUTFITS = new GDict {
            { "knight_lion", new GDict { { "set", "Lionguard" }, { "weapon", new GDict { { "r", "mw/lion_sword" }, { "l", "mw/lion_shield" } } } } },
            { "barbarian_mammoth", new GDict { { "set", "Mammoth Hunter" }, { "weapon", new GDict { { "r", "mw/mammoth_axe" } } } } },
            { "rogue_velvet", new GDict { { "set", "Velvet Thief" }, { "weapon", new GDict { { "r", "mw/coin_dagger" }, { "l", "mw/coin_dagger" } } } } },
            { "ranger_orchard", new GDict { { "set", "Orchard Warden" }, { "weapon", new GDict { { "l", "mw/orchard_bow" } } } } },
            { "mage_phoenix", new GDict { { "set", "Phoenix" }, { "weapon", new GDict { { "r", "mw/phoenix_staff" } } } } },
            { "priest_bell", new GDict { { "set", "Bellringer" }, { "weapon", new GDict { { "r", "mw/bell_scepter" } } } } },
            { "crusader_ashen", new GDict { { "set", "Ashen Templar" }, { "weapon", new GDict { { "r", "mw/ember_hammer" }, { "l", "mw/ashen_shield" } } } } },
            { "berserker_bloodmoon", new GDict { { "set", "Blood Moon" }, { "weapon", new GDict { { "r", "mw/bloodmoon_greatsword" } } } } },
            { "assassin_ribbon", new GDict { { "set", "Red Ribbon" }, { "weapon", new GDict { { "r", "mw/ribbon_dagger" }, { "l", "mw/ribbon_dagger" } } } } },
            { "sniper_wolf", new GDict { { "set", "Wolfstalker" }, { "weapon", new GDict { { "r", "mw/wolf_crossbow" } } } } },
            { "archmage_stargazer", new GDict { { "set", "Stargazer" }, { "weapon", new GDict { { "r", "mw/orrery_staff" }, { "l", "mw/starchart_tome" } } } } },
            { "necromancer_gravekeeper", new GDict { { "set", "Gravekeeper" }, { "weapon", new GDict { { "r", "mw/lantern_shovel" } } } } },
            { "golem_geode", new GDict { { "set", "Geode" }, { "weapon", new GDict { { "r", "mw/geode_hammer" }, { "l", "mw/geode_shield" } } } } },
            { "dragoon_dragonscale", new GDict { { "set", "Dragonscale" }, { "weapon", new GDict { { "r", "mw/dragon_halberd" } } } } },
            { "duelist_rose", new GDict { { "set", "Golden Rose" }, { "weapon", new GDict { { "r", "mw/rose_rapier" }, { "l", "mw/thorn_stiletto" } } } } },
            { "stormcaller_stormforged", new GDict { { "set", "Stormforged" }, { "weapon", new GDict { { "r", "mw/lightning_rod_staff" } } } } },
            { "musketeer_privateer", new GDict { { "set", "Privateer" }, { "weapon", new GDict { { "r", "mw/brass_blunderbuss" } } } } },
            { "druid_blossom", new GDict { { "set", "Cherry Blossom" }, { "weapon", new GDict { { "r", "mw/blossom_staff" } } } } },
        };
        public static GDict SKINS = _MakeSkins();

        public static GDict _MakeSkins()
        {
            // id -> {hero, line (the set's key), set (its name), name, rarity, gems, gold (0.31.189: rare ones -- or gold),
            // weapon {"r","l"} | weapon_tex (a key)}
            var out_ = new GDict();
            foreach (var id in OUTFITS)
            {
                GDict o = OUTFITS[id].D;
                var h = GD.Str(id).Substr(0, GD.Str(id).Find("_"));
                out_[id] = new GDict { { "hero", h }, { "line", GD.Str(id).Substr(h.Length + 1) }, { "set", GD.Str(o["set"]) },
                    { "name", GD.Fmt("%s %s", GD.Str(o["set"]), SKIN_HEROES[h]) }, { "rarity", "epic" }, { "gems", (int)SKIN_GEMS["epic"] },
                    { "weapon", o["weapon"].D.Duplicate() } };
            }
            foreach (var line in SKIN_LINES)
            {
                foreach (var h in SKIN_HEROES)
                {
                    out_[GD.Fmt("%s_%s", h, line)] = new GDict { { "hero", h }, { "line", line }, { "set", GD.Str(SKIN_LINES[line]) },
                        { "name", GD.Fmt("%s %s", SKIN_LINES[line], SKIN_HEROES[h]) }, { "rarity", "rare" }, { "gems", (int)SKIN_GEMS["rare"] },
                        { "gold", (int)SKIN_GOLD["rare"] }, { "weapon_tex", line } };
                }
            }
            return out_;
        }

        public static string SkinTexture(string id)
        {
            return GD.Fmt("res://assets/skins/%s.jpg", id);
        }

        public static string SkinWeaponTexture(string file, string key)
        {
            // an outfit's repainting of a weapon piece ("mw/squire_sword", "frost" -> assets/skins/weapons/squire_sword_frost.jpg)
            return GD.Fmt("res://assets/skins/weapons/%s_%s.jpg", file.GetFile(), key);
        }

        public static GArray SkinsOf(string hid)
        {
            var out_ = new GArray();
            foreach (var id in SKINS)
            {
                if (GD.Str(SKINS[id]["hero"]) == hid)
                    out_.Append(id);
            }
            return out_;
        }

        public static bool Launching(string hid, int unix)
        {
            return HERO_LAUNCH.Has(hid) && unix < (int)HERO_LAUNCH[hid] + LAUNCH_DAYS * 86400;
        }

        public static GDict HeroPrice(string hid, int unix)
        {
            // {"gold", "gems"} to unlock hid at this time; {} when it isn't sold (everyone's)
            if (!HERO_PRICES.Has(hid))
                return new GDict();
            if (Launching(hid, unix))
                return new GDict { { "gold", LAUNCH_GOLD }, { "gems", LAUNCH_GEMS } };
            return new GDict { { "gold", (int)HERO_PRICES[hid] }, { "gems", HERO_GEMS } };
        }

        public static int ShardUnlockGold(string hid, int unix)
        {
            return GD.Int(GD.Round((double)HeroPrice(hid, unix).Get("gold", 0) * SHARD_UNLOCK / 10.0)) * 10;
        }

        public static int ShardMeltGold(string hid, int unix)
        {
            return GD.Int(GD.Round((double)HeroPrice(hid, unix).Get("gold", 0) * SHARD_MELT / 10.0)) * 10;
        }

        public static int WeekIndex(int unix)
        {
            // weeks since the Monday before 1970-01-01 (weeks start Monday 00:00 UTC, as week_key)
            var days = GD.Int(GD.Floor(unix / 86400.0));
            return GD.Int(GD.Floor((double)(days + 3) / 7.0));
        }

        public static GArray FreeHeroes(int unix)
        {
            // this week's free rotation: FREE_HEROES of the sold heroes, in a fixed shuffled order so each comes round in turn
            // (a launching one waits until its launch price ends -- 0.31.187: unless too few are left to fill it, as while all six
            // launch together: then the rotation goes on with every one of them, the same weeks the server keeps)
            GArray pool = HERO_PRICES.Keys().Filter(h => !Launching(GD.Str(h), unix));
            if (pool.Size() < FREE_HEROES)
                pool = HERO_PRICES.Keys();
            pool.Sort();
            if (pool.IsEmpty())
                return new GArray();
            var rng = new Rng();
            rng.Seed = (ulong)GD.Hash("free-heroes");
            var order = new GArray();
            while (!pool.IsEmpty())
                order.Append(pool.PopAt((int)(rng.Randi() % pool.Size())));
            var out_ = new GArray();
            var w = WeekIndex(unix);
            int n_ = GD.Mini(FREE_HEROES, order.Size());
            for (int i = 0; i < n_; i++)
                out_.Append(order[(w * FREE_HEROES + i) % order.Size()]);
            return out_;
        }

        public static string PickShard(string seedText, GArray heroesOwned)
        {
            // a pass shard: one of the heroes not owned yet (any, once all are), the same on the phone and the server
            GArray pool = HERO_PRICES.Keys().Filter(h => !heroesOwned.Has(h));
            if (pool.IsEmpty())
                pool = HERO_PRICES.Keys();
            pool.Sort();
            return GD.Str(pool[(int)(GD.AbsL(GD.Hash(seedText)) % pool.Size())]);
        }

        public static readonly GArray CLASSES = GArray.Of("knight", "barbarian", "rogue", "ranger", "mage", "priest", "worker");
        // 0.31.164 (Kevin: "Remove them now: 5v5 only"): the classes a 5v5 hero can be -- the Worker was Siege's (his quest and
        // titles are kept for the record but not shown, see RETIRED)
        public static readonly GArray HERO_CLASSES = GArray.Of("knight", "barbarian", "rogue", "ranger", "mage", "priest");
        // 0.31.38: the upgraded classes have their own cosmetics (and equip slots): what they upgrade from, and which body
        // the game builds for them (the Crusader is a Knight body)
        public static readonly GArray UP_CLASSES = GArray.Of("crusader", "berserker", "necromancer", "assassin", "sniper", "archmage");
        public static readonly GDict UP_BASE = new GDict { { "crusader", "knight" }, { "berserker", "barbarian" }, { "necromancer", "priest" }, { "assassin", "rogue" }, { "sniper", "ranger" }, { "archmage", "mage" } };
        public static readonly GDict UP_LOOK = new GDict { { "crusader", "crusader" }, { "berserker", "berserker" }, { "necromancer", "necromancer" }, { "assassin", "assassin" }, { "sniper", "sniper" }, { "archmage", "archmage" } };
        public static readonly GDict CLASS_NAMES = new GDict { { "knight", "Knight" }, { "barbarian", "Barbarian" }, { "rogue", "Rogue" }, { "ranger", "Archer" }, { "mage", "Mage" }, { "priest", "Priest" }, { "worker", "Worker" },
            { "crusader", "Crusader" }, { "berserker", "Berserker" }, { "necromancer", "Necromancer" }, { "assassin", "Assassin" }, { "sniper", "Ranger" }, { "archmage", "Archmage" } };   // 0.31.61: Ranger -> Archer, Sniper -> Ranger

        public static string CosmeticClass(string cls, bool up)
        {
            // which equip slot dresses a unit: the upgraded one once he wears the upgraded hat
            if (up)
            {
                foreach (var k in UP_BASE)
                {
                    if (UP_BASE[k] == cls)
                        return k.AsString();
                }
            }
            return cls;
        }
        public static readonly GDict RARITY_COLOR = new GDict { { "common", "#b8c4c9" }, { "rare", "#5fb6ff" }, { "epic", "#c47bff" }, { "legendary", "#ffb13d" } };

        // ---------------- account level ----------------
        public static int LevelXp(int level)
        {
            return 500 + 150 * (level - 1);
        }

        public static GDict LevelReward(int level)
        {
            // Reward for reaching `level`.
            var r = new GDict { { "gold", 100 + 10 * level } };
            if (level % 10 == 0)
                r["chest"] = "royal";                 // 0.31.37: chests (was 25 gems every 5 levels)
            else if (level % 5 == 0)
                r["chest"] = "gold";
            return r;
        }

        // ---------------- Siege Pass ----------------
        public const int SEASON_EPOCH = 1790812800;   // 2026-10-01 00:00 UTC; seasons before that are season 1
        public const int SEASON_DAYS = 28;   // 4 weeks (Kevin, 0.31.36; was 42)
        public const int PASS_TIERS = 30;
        // 0.31.36: measured -- a match gives ~420 pass XP, the three dailies ~1,300, the weeklies ~5,700 a week; at 1,000 a tier
        // the 30 tiers filled in 8-9 days. At 2,500 (75,000 in all): ~20 days at 3 matches a day with the challenges done,
        // ~23 at 2 a day, ~16 at 5 a day -- inside the 28 days for a regular player, a goal for a casual one.
        public const int TIER_XP = 2500;
        public const int PREMIUM_COST = 950;   // gems
        // 0.31.107 (Kevin: "put tier skips for the battlepass. Players can buy 10 tiers for gems"): 10 tiers at a time, 100 gems
        // a tier (fewer near the end: only what's left). Any 10 tiers give back at most ~270 gems over both tracks, so a skip is
        // never a way to make gems.
        public const int TIER_SKIP = 10;
        public const int TIER_SKIP_GEMS = 100;   // per tier
        public static readonly GArray SEASON_NAMES = GArray.Of("The King's Keep", "Ashen Ramparts", "Frost Siege", "The Fish Wars", "Iron Tide", "Summer of Stones");

        public static int SeasonId(int unix)
        {
            return 1 + GD.Maxi(0, GD.Int(GD.Floor((double)(unix - SEASON_EPOCH) / (SEASON_DAYS * 86400.0))));
        }

        public static string SeasonName(int sid)
        {
            return SEASON_NAMES[(sid - 1) % SEASON_NAMES.Size()].AsString();
        }

        public static int SeasonEnds(int sid)
        {
            return SEASON_EPOCH + sid * SEASON_DAYS * 86400;
        }

        public static GDict PassReward(int sid, int tier, bool premium)
        {
            // tier is 1..PASS_TIERS. 0.31.188: no cosmetics on the pass (outfits are bought) -- the tiers that held a weapon give
            // chests, gems and hero shards (PASS_FREE_EXTRA / PASS_PREMIUM_EXTRA); the rest as before.
            if (!premium)
            {
                if (PASS_SHARD_TIERS.Has(tier))
                    return new GDict { { "shard", "" } };                       // 0.31.185: a hero shard (which one: Profile.pass_reward_for)
                if (PASS_FREE_EXTRA.Has(tier))
                    return PASS_FREE_EXTRA[tier].D.Duplicate();
                if (tier == 12 || tier == 24)
                    return new GDict { { "chest", "silver" } };
                if (tier % 4 == 0)
                    return new GDict { { "gems", 30 } };
                if (tier % 4 == 2)
                    return new GDict { { "gold", PASS_GOLD_FREE } };            // (0.31.93-0.31.183: 20 Embers)
                return new GDict { { "gold", 150 + 5 * tier } };
            }
            if (tier == PASS_TOKEN_TIER)
                return new GDict { { "token", 1 } };                            // 0.31.185: the Hero Token -- any locked hero
            if (PASS_PREMIUM_EXTRA.Has(tier))
                return PASS_PREMIUM_EXTRA[tier].D.Duplicate();
            if (tier == 8 || tier == 16)
                return new GDict { { "chest", "gold" } };
            if (tier == 22)
                return new GDict { { "chest", "royal" } };
            if (tier % 4 == 0)
                return sid >= 2 ? new GDict { { "gold", PASS_GOLD_GEM_TIER } } : new GDict { { "gems", 60 } };     // 0.31.108: not gems from season 2 (until 0.31.184 60 Embers)
            if (tier % 4 == 2)
                return new GDict { { "gold", PASS_GOLD_PREMIUM } };         // (0.31.93-0.31.183: 40 Embers)
            return new GDict { { "gold", 300 + 10 * tier } };
        }

        // 0.31.188: the tiers that held the pass's weapons (free 10/20/30, premium 2 ... 30)
        public static readonly GDict PASS_FREE_EXTRA = new GDict { { 10, new GDict { { "chest", "gold" } } }, { 20, new GDict { { "chest", "gold" } } }, { 30, new GDict { { "chest", "royal" } } } };
        // 0.31.189 (the balance check): the track paid back ~880 of its 950 gems (500 on its tiers, ~380 in its chests); now about
        // half -- 260 on its tiers (7, 15, 24, 30) and ~190 in its chests; tiers 2 and 28 a Silver and a Gold chest
        public static readonly GDict PASS_PREMIUM_EXTRA = new GDict { { 2, new GDict { { "chest", "silver" } } }, { 3, new GDict { { "chest", "gold" } } }, { 5, new GDict { { "chest", "silver" } } }, { 7, new GDict { { "gems", 50 } } },
            { 9, new GDict { { "chest", "gold" } } }, { 12, new GDict { { "shard", "" } } }, { 15, new GDict { { "gems", 50 } } }, { 18, new GDict { { "chest", "royal" } } }, { 21, new GDict { { "shard", "" } } },
            { 24, new GDict { { "gems", 60 } } }, { 26, new GDict { { "chest", "royal" } } }, { 28, new GDict { { "chest", "gold" } } }, { 30, new GDict { { "chest", "royal" }, { "gems", 100 } } } };
        // 0.31.185 (League's pass: Blue Essence and champion capsules on the free track): free tiers 5, 15 and 25 give a hero
        // shard (they gave gold); the premium track opens with a Hero Token
        public static readonly GArray PASS_SHARD_TIERS = GArray.Of(15);   // (0.31.189: 5 and 25 too until then -- they give gold again)
        public const int PASS_TOKEN_TIER = 1;
        // 0.31.184 (Kevin: "Maybe let's have the two currency so it's more simple"): the Embers the pass gave are gold, ten for
        // one (EMBER_GOLD)
        public const int PASS_GOLD_FREE = 200;
        public const int PASS_GOLD_PREMIUM = 400;
        public const int PASS_GOLD_GEM_TIER = 600;

        // ---------------- cosmetics ----------------
        // 0.31.188: the titles (kind "title": text shown with the name, all earned -- TITLE_GOALS, the leaderboard's prizes).
        // The weapons that were here (0.31.39-0.31.187) are gone; each hero's own weapon is siege_view.gd LOOKS, and an outfit's
        // its own (SKINS).
        // Each class's own weapon has a name (0.31.93 Armory Reforged, Kevin's roster).
        public static readonly GDict STARTER_NAMES = new GDict { { "knight", "Squire's Blade" }, { "barbarian", "Woodsplitter" }, { "rogue", "Cutpurse Daggers" },
            { "ranger", "Ashwood Bow" }, { "mage", "Apprentice Staff" }, { "priest", "Acolyte's Wand" }, { "worker", "Work Hatchet" },
            { "crusader", "Templar's Sword" }, { "berserker", "Ironhewer" }, { "necromancer", "Bonecaller" }, { "assassin", "Shade Daggers" },
            { "sniper", "Marksman's Crossbow" }, { "archmage", "Magister's Staff" } };

        public static readonly GDict CATALOG = new GDict {
            // --- Titles (0.31.87, Kevin: "players have to earn the titles instead by doing tasks in the game"): source "earn" --
            // not sold, not in the pass or chests; how each is earned is TITLE_GOALS, its text/form/rarity siege_net.TITLES
            // (the same name and rarity here). Owned ones from before (shop, pass, the Knight Arsenal) stay owned.
            { "title_squire", new GDict { { "kind", "title" }, { "class", "" }, { "name", "Squire" }, { "rarity", "common" }, { "source", "earn" } } },
            { "title_victor", new GDict { { "kind", "title" }, { "class", "" }, { "name", "the Victor" }, { "rarity", "common" }, { "source", "earn" } } },
            { "title_brawler", new GDict { { "kind", "title" }, { "class", "" }, { "name", "the Brawler" }, { "rarity", "common" }, { "source", "earn" } } },
            { "title_woodcutter", new GDict { { "kind", "title" }, { "class", "" }, { "name", "the Woodcutter" }, { "rarity", "common" }, { "source", "earn" } } },
            { "title_fishmonger", new GDict { { "kind", "title" }, { "class", "" }, { "name", "the Fishmonger" }, { "rarity", "common" }, { "source", "earn" } } },
            { "title_gatebreaker", new GDict { { "kind", "title" }, { "class", "" }, { "name", "the Gatebreaker" }, { "rarity", "rare" }, { "source", "earn" } } },
            { "title_kingbearer", new GDict { { "kind", "title" }, { "class", "" }, { "name", "Kingbearer" }, { "rarity", "rare" }, { "source", "earn" } } },
            { "title_many_hats", new GDict { { "kind", "title" }, { "class", "" }, { "name", "of Many Hats" }, { "rarity", "rare" }, { "source", "earn" } } },
            { "title_tempest", new GDict { { "kind", "title" }, { "class", "" }, { "name", "the Tempest" }, { "rarity", "epic" }, { "source", "earn" } } },
            { "title_relentless", new GDict { { "kind", "title" }, { "class", "" }, { "name", "the Relentless" }, { "rarity", "epic" }, { "source", "earn" } } },
            { "title_cake_baron", new GDict { { "kind", "title" }, { "class", "" }, { "name", "Fish Baron" }, { "rarity", "epic" }, { "source", "earn" } } },
            { "title_siege_lord", new GDict { { "kind", "title" }, { "class", "" }, { "name", "Siege Lord" }, { "rarity", "epic" }, { "source", "earn" } } },
            { "title_oracle_sworn", new GDict { { "kind", "title" }, { "class", "" }, { "name", "the Kingsworn" }, { "rarity", "legendary" }, { "source", "earn" } } },
            { "title_unstoppable", new GDict { { "kind", "title" }, { "class", "" }, { "name", "the Unstoppable" }, { "rarity", "legendary" }, { "source", "earn" } } },
            { "title_undefeated", new GDict { { "kind", "title" }, { "class", "" }, { "name", "the Undefeated" }, { "rarity", "legendary" }, { "source", "earn" } } },
            { "title_legend", new GDict { { "kind", "title" }, { "class", "" }, { "name", "the Legend" }, { "rarity", "legendary" }, { "source", "earn" } } },
            { "title_sir", new GDict { { "kind", "title" }, { "class", "" }, { "name", "Sir" }, { "rarity", "rare" }, { "source", "earn" } } },
            { "title_shieldwall", new GDict { { "kind", "title" }, { "class", "" }, { "name", "the Shieldwall" }, { "rarity", "epic" }, { "source", "earn" } } },
            { "title_hammer_realm", new GDict { { "kind", "title" }, { "class", "" }, { "name", "Hammer of the Realm" }, { "rarity", "legendary" }, { "source", "earn" } } },
            { "title_wild", new GDict { { "kind", "title" }, { "class", "" }, { "name", "the Wild" }, { "rarity", "rare" }, { "source", "earn" } } },
            { "title_whirlwind", new GDict { { "kind", "title" }, { "class", "" }, { "name", "the Whirlwind" }, { "rarity", "epic" }, { "source", "earn" } } },
            { "title_unchained", new GDict { { "kind", "title" }, { "class", "" }, { "name", "the Unchained" }, { "rarity", "legendary" }, { "source", "earn" } } },
            { "title_sly", new GDict { { "kind", "title" }, { "class", "" }, { "name", "the Sly" }, { "rarity", "rare" }, { "source", "earn" } } },
            { "title_shadows", new GDict { { "kind", "title" }, { "class", "" }, { "name", "of the Shadows" }, { "rarity", "epic" }, { "source", "earn" } } },
            { "title_knives", new GDict { { "kind", "title" }, { "class", "" }, { "name", "Master of Knives" }, { "rarity", "legendary" }, { "source", "earn" } } },
            { "title_keen_eyed", new GDict { { "kind", "title" }, { "class", "" }, { "name", "the Keen-Eyed" }, { "rarity", "rare" }, { "source", "earn" } } },
            { "title_deadeye", new GDict { { "kind", "title" }, { "class", "" }, { "name", "the Deadeye" }, { "rarity", "epic" }, { "source", "earn" } } },
            { "title_warden", new GDict { { "kind", "title" }, { "class", "" }, { "name", "Warden of the Wilds" }, { "rarity", "legendary" }, { "source", "earn" } } },
            { "title_apprentice", new GDict { { "kind", "title" }, { "class", "" }, { "name", "Apprentice" }, { "rarity", "rare" }, { "source", "earn" } } },
            { "title_stormcaller", new GDict { { "kind", "title" }, { "class", "" }, { "name", "the Stormcaller" }, { "rarity", "epic" }, { "source", "earn" } } },
            { "title_starborn", new GDict { { "kind", "title" }, { "class", "" }, { "name", "the Starborn" }, { "rarity", "legendary" }, { "source", "earn" } } },
            { "title_acolyte", new GDict { { "kind", "title" }, { "class", "" }, { "name", "Acolyte" }, { "rarity", "rare" }, { "source", "earn" } } },
            { "title_merciful", new GDict { { "kind", "title" }, { "class", "" }, { "name", "the Merciful" }, { "rarity", "epic" }, { "source", "earn" } } },
            { "title_lightbringer", new GDict { { "kind", "title" }, { "class", "" }, { "name", "the Lightbringer" }, { "rarity", "legendary" }, { "source", "earn" } } },
            { "title_foreman", new GDict { { "kind", "title" }, { "class", "" }, { "name", "Foreman" }, { "rarity", "rare" }, { "source", "earn" } } },
            { "title_mason", new GDict { { "kind", "title" }, { "class", "" }, { "name", "the Mason" }, { "rarity", "epic" }, { "source", "earn" } } },
            { "title_master_builder", new GDict { { "kind", "title" }, { "class", "" }, { "name", "Master Builder" }, { "rarity", "legendary" }, { "source", "earn" } } },
            // --- 0.31.120: only from the weekly leaderboard (LB_PRIZES)
            { "title_champion", new GDict { { "kind", "title" }, { "class", "" }, { "name", "Champion" }, { "rarity", "legendary" }, { "source", "prize" } } },
            { "title_contender", new GDict { { "kind", "title" }, { "class", "" }, { "name", "the Contender" }, { "rarity", "epic" }, { "source", "prize" } } },
            { "title_top_ten", new GDict { { "kind", "title" }, { "class", "" }, { "name", "of the Ten" }, { "rarity", "rare" }, { "source", "prize" } } },
        };

        // 0.31.39 (Kevin: "only the weapons are cosmetics -- so it's easy to tell who's playing what class"): the skins (tints)
        // are gone. Anyone who bought one gets its price back once (Profile._normalized).
        public static readonly GDict REMOVED_SKIN_REFUND = new GDict {
            { "knight_skin_royal", new GDict { { "gold", 1200 } } },
            { "knight_skin_gilded", new GDict { { "gems", 400 } } },
            { "barb_skin_ember", new GDict { { "gold", 1200 } } },
            { "rogue_skin_night", new GDict { { "gold", 1200 } } },
            { "ranger_skin_forest", new GDict { { "gold", 1200 } } },
            { "ranger_skin_dusk", new GDict { { "gems", 400 } } },
            { "mage_skin_arcane", new GDict { { "gold", 1200 } } },
            { "mage_skin_solar", new GDict { { "gems", 400 } } },
            { "worker_skin_miner", new GDict { { "gold", 600 } } },
            { "priest_skin_dawn", new GDict { { "gold", 1200 } } },
            { "crus_skin_holy", new GDict { { "gold", 1500 } } },
            { "crus_skin_templar", new GDict { { "gold", 2800 } } },
            { "crus_skin_sunforged", new GDict { { "gems", 400 } } },
            { "bers_skin_bloodrage", new GDict { { "gold", 1500 } } },
            { "bers_skin_glacier", new GDict { { "gold", 2800 } } },
            { "bers_skin_volcanic", new GDict { { "gems", 400 } } },
            { "necro_skin_plague", new GDict { { "gold", 1500 } } },
            { "necro_skin_frost", new GDict { { "gold", 2800 } } },
            { "necro_skin_boneking", new GDict { { "gems", 400 } } },
            { "assn_skin_crimson", new GDict { { "gold", 1500 } } },
            { "assn_skin_midnight", new GDict { { "gold", 2800 } } },
            { "assn_skin_phantom", new GDict { { "gems", 400 } } },
            { "snip_skin_desert", new GDict { { "gold", 1500 } } },
            { "snip_skin_winter", new GDict { { "gold", 2800 } } },
            { "snip_skin_golden", new GDict { { "gems", 400 } } },
            { "arch_skin_frost", new GDict { { "gold", 1500 } } },
            { "arch_skin_void", new GDict { { "gold", 2800 } } },
            { "arch_skin_starborn", new GDict { { "gems", 400 } } } };

        public static GDict Item(string id)
        {
            return CATALOG.Get(id, new GDict()).D;
        }

        // ---------------- the shop's days and weeks ----------------
        // (0.31.36-0.31.187: the daily gold weapons and the weekly gem weapons rotated here -- 0.31.188 the shop sells outfits,
        // heroes, the pass and gem packs. 0.31.106-0.31.184 EXCHANGE: gold for gems. 0.31.185, League's way: gold is earned only)

        public const int FEATURED_OUTFITS = 3;

        // 0.31.203 (Kevin: "For featured outfits, let's make them discounted. A new set of on sale skins will rotate once per
        // week"): the week's featured outfits are the WEEKLY SALE -- each at its own discount (SALE_OFF, in the order of the
        // week's picks), in gems and, for the rare line, in gold too. Bought with the "buy_sale" op (Profile.buy_sale), which
        // names the week whose sale the buyer saw: this week's, or last week's for SALE_GRACE after it ended (a buy still on its
        // way to the server, or made offline just before midnight on Sunday).
        public static readonly GArray SALE_OFF = GArray.Of(50, 35, 25);
        public const int SALE_GRACE = 86400;
        public const int SALE_GEM_STEP = 5;   // sale prices round to these
        public const int SALE_GOLD_STEP = 500;

        public static int WeekStart(int unix)
        {
            // the Monday 00:00 UTC that began this week
            return (WeekIndex(unix) * 7 - 3) * 86400;
        }

        public static int SaleOffWeek(string id, int week)
        {
            // an outfit's discount (percent) in that week's sale; 0 when it isn't in it
            var i = FeaturedOutfitsWeek(week).Find(id);
            return i >= 0 && i < SALE_OFF.Size() ? (int)SALE_OFF[i] : 0;
        }

        public static int SaleOff(string id, int unix)
        {
            return SaleOffWeek(id, WeekIndex(unix));
        }

        public static int SalePrice(int full, int off, int step)
        {
            if (off <= 0 || full <= 0)
                return full;
            return GD.Maxi(step, GD.Int(GD.Round(full * (100 - off) / 100.0 / step)) * step);
        }

        public static GDict SkinOffer(string id, int unix)
        {
            // what an outfit costs now: gems, gold (0: not for gold), off (%, 0: full price), was_gems / was_gold (the full
            // prices), week (the sale's, for the op)
            GDict sk = SKINS.Get(id, new GDict()).D;
            var w = WeekIndex(unix);
            var off = SaleOffWeek(id, w);
            var full_gems = (int)sk.Get("gems", 0);
            var full_gold = (int)sk.Get("gold", 0);
            return new GDict { { "gems", SalePrice(full_gems, off, SALE_GEM_STEP) }, { "gold", SalePrice(full_gold, off, SALE_GOLD_STEP) },
                { "off", off }, { "was_gems", full_gems }, { "was_gold", full_gold }, { "week", w } };
        }

        public static GArray FeaturedOutfits(int unix)
        {
            return FeaturedOutfitsWeek(WeekIndex(unix));
        }

        public static GArray FeaturedOutfitsWeek(int w)
        {
            // 0.31.188: the shop's featured outfits this week (Monday 00:00 UTC) -- a fixed shuffle of every outfit, three a week
            // in turn so each comes round; a hero's own set first in the shuffle's draw (they're the new ones). 0.31.203: the
            // week's sale, by week number (Profile.buy_sale checks last week's too)
            GArray pool = SKINS.Keys();
            pool.Sort();
            if (pool.IsEmpty())
                return new GArray();
            var rng = new Rng();
            rng.Seed = (ulong)GD.Hash("featured-outfits");
            var order = new GArray();
            while (!pool.IsEmpty())
                order.Append(pool.PopAt((int)(rng.Randi() % pool.Size())));
            order.SortCustom((a, b) => SKINS[a].Has("weapon") && !SKINS[b].Has("weapon"));
            var out_ = new GArray();
            var n = GD.Mini(FEATURED_OUTFITS, order.Size());
            for (int i = 0; i < n; i++)
                out_.Append(order[(w * n + i) % order.Size()]);
            return out_;
        }

        public static string DayKey(int unix)
        {
            var d = Time.GetDateDictFromUnixTime(unix);
            return GD.Fmt("%04d-%02d-%02d", d["year"], d["month"], d["day"]);
        }

        public static string WeekKey(int unix)
        {
            // Weeks start Monday 00:00 UTC.
            var days = GD.Int(GD.Floor(unix / 86400.0));
            var monday = days - ((days + 3) % 7);            // 1970-01-01 was a Thursday
            return DayKey(monday * 86400);
        }

        // ---------------- challenges ----------------
        // stat keys come from match_stats(): wins, matches, rescues, kills, gates (gate damage / 100),
        // gathered, fed, lifts (Oracle lifts joined), class_<name> (matches finished as that class).
        // 0.31.164 (Kevin: "5v5 only"): the 5v5's challenges -- Siege's (King rescues, fish, gathering, King lifts) are gone; a
        // saved one of those is swapped for a new one when the profile refreshes (Profile._retire_challenges). "gates" is now
        // the damage dealt to towers, gates and the King (per 100).
        public static readonly GDict CHALLENGES = new GDict {
            { "win1", new GDict { { "text", "Win a match" }, { "stat", "wins" }, { "goal", 1 }, { "pass", 500 }, { "gold", 100 }, { "span", "daily" } } },
            { "play3", new GDict { { "text", "Play 3 matches" }, { "stat", "matches" }, { "goal", 3 }, { "pass", 400 }, { "gold", 80 }, { "span", "daily" } } },
            { "kos5", new GDict { { "text", "Knock out 5 enemy heroes" }, { "stat", "kills" }, { "goal", 5 }, { "pass", 400 }, { "gold", 80 }, { "span", "daily" } } },
            { "gate5", new GDict { { "text", "Deal 500 damage to towers and gates" }, { "stat", "gates" }, { "goal", 5 }, { "pass", 450 }, { "gold", 90 }, { "span", "daily" } } },
            { "tower2", new GDict { { "text", "Destroy 2 towers" }, { "stat", "towers" }, { "goal", 2 }, { "pass", 500 }, { "gold", 100 }, { "span", "daily" } } },
            { "camps4", new GDict { { "text", "Clear 4 jungle camps" }, { "stat", "camps" }, { "goal", 4 }, { "pass", 450 }, { "gold", 90 }, { "span", "daily" } } },
            { "lh60", new GDict { { "text", "Last-hit 60 minions" }, { "stat", "lh" }, { "goal", 60 }, { "pass", 400 }, { "gold", 80 }, { "span", "daily" } } },
            { "epic1", new GDict { { "text", "Defeat an epic monster" }, { "stat", "epics" }, { "goal", 1 }, { "pass", 600 }, { "gold", 120 }, { "span", "daily" } } },
            { "w_win5", new GDict { { "text", "Win 5 matches" }, { "stat", "wins" }, { "goal", 5 }, { "pass", 2000 }, { "gems", 15 }, { "span", "weekly" } } },
            { "w_kos30", new GDict { { "text", "Knock out 30 enemy heroes" }, { "stat", "kills" }, { "goal", 30 }, { "pass", 1800 }, { "gems", 12 }, { "span", "weekly" } } },
            { "w_gate30", new GDict { { "text", "Deal 3,000 damage to towers and gates" }, { "stat", "gates" }, { "goal", 30 }, { "pass", 1800 }, { "gems", 12 }, { "span", "weekly" } } },
            { "w_tower12", new GDict { { "text", "Destroy 12 towers" }, { "stat", "towers" }, { "goal", 12 }, { "pass", 2000 }, { "gems", 15 }, { "span", "weekly" } } },
            { "w_camps20", new GDict { { "text", "Clear 20 jungle camps" }, { "stat", "camps" }, { "goal", 20 }, { "pass", 1800 }, { "gems", 12 }, { "span", "weekly" } } },
            { "w_play12", new GDict { { "text", "Play 12 matches" }, { "stat", "matches" }, { "goal", 12 }, { "pass", 1600 }, { "gems", 10 }, { "span", "weekly" } } },
        };
        // (0.31.189: the weeklies' gems 25-40 -> 10-15: they were a third of all free gems, ~400 a season)
        public const int DAILY_COUNT = 3;
        public const int WEEKLY_COUNT = 3;

        public static GArray RollChallenges(string span, string key, int count, GArray exclude = null)
        {
            exclude ??= new GArray();
            var pool = new GArray();
            foreach (var id in CHALLENGES)
            {
                if (CHALLENGES[id]["span"] == span && !exclude.Has(id))
                    pool.Append(id);
            }
            pool.Sort();
            var rng = new Rng();
            rng.Seed = (ulong)GD.Hash(GD.Fmt("%s-%s-%d", span, key, exclude.Size()));
            var out_ = new GArray();
            while (out_.Size() < count && !pool.IsEmpty())
            {
                string id = pool.PopAt((int)(rng.Randi() % pool.Size())).AsString();
                out_.Append(new GDict { { "id", id }, { "progress", 0 }, { "claimed", false } });
            }
            return out_;
        }

        // ---------------- match rewards ----------------
        public static readonly GDict FIRST_WIN = new GDict { { "gold", 150 }, { "pass", 500 } };   // (0.31.189: 300 gold -- 8,400 a month of a casual player's gold)

        // 0.31.120 (Kevin: prizes for the weekly leaderboard): paid by the server to the accounts when a week ends
        // (server/leaderboard.gd), among players with at least LB_MIN_MATCHES online matches that week. The titles exist only
        // here. Chests are reward chests (they wait when the slots are full).
        public const int LB_MIN_MATCHES = 3;
        public static readonly GArray LB_PRIZES = GArray.Of(
            new GDict { { "from", 1 }, { "to", 1 }, { "gems", 300 }, { "chest", "royal" }, { "title", "title_champion" } },
            new GDict { { "from", 2 }, { "to", 3 }, { "gems", 200 }, { "chest", "gold" }, { "title", "title_contender" } },
            new GDict { { "from", 4 }, { "to", 10 }, { "gems", 100 }, { "chest", "gold" }, { "title", "title_top_ten" } },
            new GDict { { "from", 11 }, { "to", 100 }, { "gems", 30 }, { "chest", "silver" } }
        );

        public static readonly GDict PRIZE_TITLES = new GDict {
            { "title_champion", new GDict { { "task", "Finish #1 on a weekly leaderboard" }, { "n", 1 }, { "cls", "" } } },
            { "title_contender", new GDict { { "task", "Finish 2nd or 3rd on a weekly leaderboard" }, { "n", 1 }, { "cls", "" } } },
            { "title_top_ten", new GDict { { "task", "Finish in the top 10 of a weekly leaderboard" }, { "n", 1 }, { "cls", "" } } },
        };

        // 0.31.120 (Kevin: referral codes): a new player enters a friend's code within REF_DAYS of making their account and
        // before level REF_LEVEL; at level REF_LEVEL both get a REF_CHEST (server/referrals.gd), a friend for at most REF_MAX.
        public const int REF_DAYS = 7;
        public const int REF_LEVEL = 5;
        public const int REF_MAX = 20;
        public const string REF_CHEST = "gold";

        public static GDict LbPrize(int rank)
        {
            foreach (var t in LB_PRIZES)
            {
                if (rank >= (int)t["from"] && rank <= (int)t["to"])
                    return t.D;
            }
            return new GDict();
        }

        // 0.31.119 (Kevin: "Do all" -- a daily login reward): a 7-day calendar, one claim a day (UTC days, like the orders and
        // the first win), round and round; a missed day doesn't reset it. Gems only on day 7 (20 a week -- the economy review
        // found Silver chests were already half of all free gems). Chests are reward chests: with the slots full they wait.
        public static readonly GArray LOGIN_REWARDS = GArray.Of( // (0.31.189: gold 150 / 250 / 250 / 500 / 400 -> 100 / 150 / 150 / 300 / 250)
            new GDict { { "gold", 100 } },
            new GDict { { "gold", 150 } },
            new GDict { { "chest", "silver" } },
            new GDict { { "gold", 150 } },
            new GDict { { "gold", 300 } },
            new GDict { { "gold", 250 } },
            new GDict { { "chest", "gold" }, { "gems", 20 } }
        );

        public static GDict MatchStats(GDict me, bool won, bool _draw)
        {
            // Contribution numbers from the player's unit at the end of a match (offline or online).
            var s = new GDict { { "matches", 1 }, { "wins", won ? 1 : 0 }, { "rescues", (int)me.Get("rescues", 0) }, { "kills", (int)me.Get("kills", 0) },
                { "gates", GD.Int((double)me.Get("gate_dmg", 0.0) / 100.0) }, { "gathered", (int)me.Get("gathered", 0) }, { "fed", (int)me.Get("fed", 0) },
                { "lifts", (int)me.Get("lifts", 0) } };
            // 0.31.164 (5v5): towers destroyed (yours or near you), jungle camps cleared, minion last hits, epic monsters slain
            foreach (var k in FIVE_STATS)
                s[k] = (int)me.Get(k, 0);
            s["class_" + GD.Str(me.Get("cls", "villager"))] = 1;
            // 0.31.87 (titles): what siege_mode gathered over the match -- the class played most (cls_main), knockouts by the
            // class they were made as, gate health repaired, health healed, the biggest burst of knockouts
            s["repaired"] = (int)me.Get("repaired", 0.0);
            s["healed"] = (int)me.Get("healed", 0.0);
            s["best_multi"] = (int)me.Get("best_multi", 0);
            s["main"] = GD.Str(me.Get("cls_main", ""));
            GDict kc = me.Get("kills_cls", new GDict()).D;
            foreach (var c in kc)
                s["kills_" + GD.Str(c)] = (int)kc[c];
            // 0.31.97 (quests): per class as worn (Knight / Crusader apart): seconds played and what was done as it
            Var q = me.Get("q", new GDict());
            s["q"] = q.IsDict ? q.D.Duplicate(true) : new GDict();
            return s;
        }

        // ---------------- titles (0.31.87) ----------------
        // How each title is earned: a lifetime count (profile stats) reaching n. "cls": the class it belongs to ("" = anyone);
        // each upgrade counts as its class (the sim's unit class is the base class, up = upgraded). Stats: matches, wins,
        // kills, gathered, fed, gates (per 100 damage), rescues, lifts, repaired / healed (health), best_multi (most knockouts
        // in one burst), best_streak (wins in a row), classes (classes played as the main class of a match), win_<cls>
        // (wins with that as the main class), kills_<cls> (knockouts made as it).
        public static readonly GDict TITLE_GOALS = new GDict {
            { "title_squire", new GDict { { "stat", "matches" }, { "n", 5 }, { "task", "Play 5 matches" }, { "cls", "" } } },
            { "title_victor", new GDict { { "stat", "wins" }, { "n", 5 }, { "task", "Win 5 matches" }, { "cls", "" } } },
            { "title_brawler", new GDict { { "stat", "kills" }, { "n", 50 }, { "task", "Knock out 50 enemies" }, { "cls", "" } } },
            { "title_woodcutter", new GDict { { "stat", "gathered" }, { "n", 200 }, { "task", "Gather 200 wood or stone" }, { "cls", "" }, { "siege", true } } },
            { "title_fishmonger", new GDict { { "stat", "fed" }, { "n", 10 }, { "task", "Feed 10 fish to your King" }, { "cls", "" }, { "siege", true } } },
            { "title_gatebreaker", new GDict { { "stat", "gates" }, { "n", 100 }, { "task", "Deal 10,000 damage to towers and gates" }, { "cls", "" } } },
            { "title_kingbearer", new GDict { { "stat", "lifts" }, { "n", 25 }, { "task", "Help lift your King 25 times" }, { "cls", "" }, { "siege", true } } },
            { "title_many_hats", new GDict { { "stat", "classes" }, { "n", 7 }, { "task", "Play a match as each of the 7 classes" }, { "cls", "" }, { "siege", true } } },
            { "title_tempest", new GDict { { "stat", "best_multi" }, { "n", 3 }, { "task", "Knock out 3 enemies in one burst" }, { "cls", "" } } },
            { "title_relentless", new GDict { { "stat", "best_streak" }, { "n", 5 }, { "task", "Win 5 matches in a row" }, { "cls", "" } } },
            { "title_cake_baron", new GDict { { "stat", "fed" }, { "n", 100 }, { "task", "Feed 100 fish to your King" }, { "cls", "" }, { "siege", true } } },
            { "title_siege_lord", new GDict { { "stat", "wins" }, { "n", 50 }, { "task", "Win 50 matches" }, { "cls", "" } } },
            { "title_oracle_sworn", new GDict { { "stat", "rescues" }, { "n", 50 }, { "task", "Rescue your King 50 times" }, { "cls", "" }, { "siege", true } } },
            { "title_unstoppable", new GDict { { "stat", "best_multi" }, { "n", 5 }, { "task", "Knock out 5 enemies in one burst" }, { "cls", "" } } },
            { "title_undefeated", new GDict { { "stat", "best_streak" }, { "n", 10 }, { "task", "Win 10 matches in a row" }, { "cls", "" } } },
            { "title_legend", new GDict { { "stat", "wins" }, { "n", 250 }, { "task", "Win 250 matches" }, { "cls", "" } } },
            { "title_sir", new GDict { { "stat", "win_knight" }, { "n", 10 }, { "task", "Win 10 matches as Knight or Crusader" }, { "cls", "knight" } } },
            { "title_shieldwall", new GDict { { "stat", "kills_knight" }, { "n", 250 }, { "task", "Knock out 250 enemies as Knight or Crusader" }, { "cls", "knight" } } },
            { "title_hammer_realm", new GDict { { "stat", "win_knight" }, { "n", 100 }, { "task", "Win 100 matches as Knight or Crusader" }, { "cls", "knight" } } },
            { "title_wild", new GDict { { "stat", "win_barbarian" }, { "n", 10 }, { "task", "Win 10 matches as Barbarian or Berserker" }, { "cls", "barbarian" } } },
            { "title_whirlwind", new GDict { { "stat", "kills_barbarian" }, { "n", 250 }, { "task", "Knock out 250 enemies as Barbarian or Berserker" }, { "cls", "barbarian" } } },
            { "title_unchained", new GDict { { "stat", "win_barbarian" }, { "n", 100 }, { "task", "Win 100 matches as Barbarian or Berserker" }, { "cls", "barbarian" } } },
            { "title_sly", new GDict { { "stat", "win_rogue" }, { "n", 10 }, { "task", "Win 10 matches as Rogue or Assassin" }, { "cls", "rogue" } } },
            { "title_shadows", new GDict { { "stat", "kills_rogue" }, { "n", 250 }, { "task", "Knock out 250 enemies as Rogue or Assassin" }, { "cls", "rogue" } } },
            { "title_knives", new GDict { { "stat", "win_rogue" }, { "n", 100 }, { "task", "Win 100 matches as Rogue or Assassin" }, { "cls", "rogue" } } },
            { "title_keen_eyed", new GDict { { "stat", "win_ranger" }, { "n", 10 }, { "task", "Win 10 matches as Archer or Ranger" }, { "cls", "ranger" } } },
            { "title_deadeye", new GDict { { "stat", "kills_ranger" }, { "n", 250 }, { "task", "Knock out 250 enemies as Archer or Ranger" }, { "cls", "ranger" } } },
            { "title_warden", new GDict { { "stat", "win_ranger" }, { "n", 100 }, { "task", "Win 100 matches as Archer or Ranger" }, { "cls", "ranger" } } },
            { "title_apprentice", new GDict { { "stat", "win_mage" }, { "n", 10 }, { "task", "Win 10 matches as Mage or Archmage" }, { "cls", "mage" } } },
            { "title_stormcaller", new GDict { { "stat", "kills_mage" }, { "n", 250 }, { "task", "Knock out 250 enemies as Mage or Archmage" }, { "cls", "mage" } } },
            { "title_starborn", new GDict { { "stat", "win_mage" }, { "n", 100 }, { "task", "Win 100 matches as Mage or Archmage" }, { "cls", "mage" } } },
            { "title_acolyte", new GDict { { "stat", "win_priest" }, { "n", 10 }, { "task", "Win 10 matches as Priest or Necromancer" }, { "cls", "priest" } } },
            { "title_merciful", new GDict { { "stat", "healed" }, { "n", 25000 }, { "task", "Heal 25,000 health" }, { "cls", "priest" } } },
            { "title_lightbringer", new GDict { { "stat", "win_priest" }, { "n", 100 }, { "task", "Win 100 matches as Priest or Necromancer" }, { "cls", "priest" } } },
            { "title_foreman", new GDict { { "stat", "win_worker" }, { "n", 10 }, { "task", "Win 10 matches as Worker" }, { "cls", "worker" }, { "siege", true } } },
            { "title_mason", new GDict { { "stat", "repaired" }, { "n", 20000 }, { "task", "Repair 20,000 gate health" }, { "cls", "worker" }, { "siege", true } } },
            { "title_master_builder", new GDict { { "stat", "gathered" }, { "n", 5000 }, { "task", "Gather 5,000 wood or stone" }, { "cls", "worker" }, { "siege", true } } },
        };
        // 0.31.164: "siege": true -- earned in Siege (King rescues, fish, King lifts, gathering, repairs, the Worker, all 7 classes):
        // kept by whoever has it, not shown to earn any more (retired())
        public static readonly GArray TITLE_RARITY_ORDER = GArray.Of("common", "rare", "epic", "legendary");

        public static bool Retired(GDict goal)
        {
            return (bool)goal.Get("siege", false);
        }

        // ---------------- class quests (0.31.97, Kevin: "Build the quest system and I want quests for each class") ----------------
        // Every class has one quest: three steps, claimed in order, each paying out (QUEST_REWARDS; the third gave the class's
        // legendary weapon until 0.31.188 -- now QUEST_FINAL: gems and a Royal chest). Progress is a lifetime count in the
        // profile's stats, "q_<class>_<stat>", kept from 0.31.97 on and credited to the class you were when you did it: a base
        // class counts its upgrade too (a Crusader's knockouts are a Knight's), an upgraded class only while in its hat. A match
        // counts as played (and won) as a class after QUEST_MIN_TIME seconds as it. Stats: matches, wins, kills, rescues, gates
        // (per 100 gate damage), gathered, fed, repaired / healed (health), lifts (King lifts joined), best_multi (the most
        // knockouts in one burst -- a best, not a sum).
        public const double QUEST_MIN_TIME = 60.0;
        public static readonly GArray QUEST_COUNTS = GArray.Of("kills", "rescues", "gates", "gathered", "fed", "repaired", "healed", "lifts", "towers", "camps", "lh", "epics");
        // 0.31.164 (5v5 only): the steps that asked for King rescues or King lifts ask for towers or jungle camps now ("gates" is
        // tower and gate damage); the Worker's quest is Siege's -- kept, not shown (HERO_CLASSES)
        public static readonly GArray QUEST_REWARDS = GArray.Of(new GDict { { "gold", 700 } }, new GDict { { "gems", 50 }, { "chest", "gold" } });   // steps 1 and 2 (0.31.184: 400 gold + 30 Embers -> 700 gold)
        public static readonly GDict QUEST_FINAL = new GDict { { "gems", 100 }, { "chest", "royal" } };   // step 3 (0.31.188: was the class's legendary weapon; 0.31.189: 150 -> 100 gems)
        public static readonly GDict QUESTS = new GDict {
            { "knight", new GDict { { "steps", GArray.Of(
                    new GDict { { "stat", "wins" }, { "n", 3 }, { "task", "Win 3 matches as a Knight" } },
                    new GDict { { "stat", "towers" }, { "n", 10 }, { "task", "Destroy 10 towers as a Knight" } },
                    new GDict { { "stat", "kills" }, { "n", 500 }, { "task", "Knock out 500 enemies as a Knight" } }) } } },
            { "barbarian", new GDict { { "steps", GArray.Of(
                    new GDict { { "stat", "kills" }, { "n", 40 }, { "task", "Knock out 40 enemies as a Barbarian" } },
                    new GDict { { "stat", "gates" }, { "n", 100 }, { "task", "Deal 10,000 damage to towers and gates as a Barbarian" } },
                    new GDict { { "stat", "wins" }, { "n", 60 }, { "task", "Win 60 matches as a Barbarian" } }) } } },
            { "rogue", new GDict { { "steps", GArray.Of(
                    new GDict { { "stat", "kills" }, { "n", 40 }, { "task", "Knock out 40 enemies as a Rogue" } },
                    new GDict { { "stat", "best_multi" }, { "n", 3 }, { "task", "Knock out 3 enemies in one burst as a Rogue" } },
                    new GDict { { "stat", "kills" }, { "n", 750 }, { "task", "Knock out 750 enemies as a Rogue" } }) } } },
            { "ranger", new GDict { { "steps", GArray.Of(
                    new GDict { { "stat", "kills" }, { "n", 40 }, { "task", "Knock out 40 enemies as an Archer" } },
                    new GDict { { "stat", "wins" }, { "n", 25 }, { "task", "Win 25 matches as an Archer" } },
                    new GDict { { "stat", "kills" }, { "n", 750 }, { "task", "Knock out 750 enemies as an Archer" } }) } } },
            { "mage", new GDict { { "steps", GArray.Of(
                    new GDict { { "stat", "kills" }, { "n", 40 }, { "task", "Knock out 40 enemies as a Mage" } },
                    new GDict { { "stat", "camps" }, { "n", 15 }, { "task", "Clear 15 jungle camps as a Mage" } },
                    new GDict { { "stat", "wins" }, { "n", 60 }, { "task", "Win 60 matches as a Mage" } }) } } },
            { "priest", new GDict { { "steps", GArray.Of(
                    new GDict { { "stat", "healed" }, { "n", 2000 }, { "task", "Heal 2,000 health as a Priest" } },
                    new GDict { { "stat", "towers" }, { "n", 10 }, { "task", "Destroy 10 towers as a Priest" } },
                    new GDict { { "stat", "wins" }, { "n", 60 }, { "task", "Win 60 matches as a Priest" } }) } } },
            { "worker", new GDict { { "steps", GArray.Of(
                    new GDict { { "stat", "gathered" }, { "n", 300 }, { "task", "Gather 300 wood or stone" } },
                    new GDict { { "stat", "repaired" }, { "n", 10000 }, { "task", "Repair 10,000 gate health" } },
                    new GDict { { "stat", "wins" }, { "n", 60 }, { "task", "Win 60 matches as a Worker" } }) } } },
            { "crusader", new GDict { { "steps", GArray.Of(
                    new GDict { { "stat", "kills" }, { "n", 25 }, { "task", "Knock out 25 enemies as a Crusader" } },
                    new GDict { { "stat", "towers" }, { "n", 8 }, { "task", "Destroy 8 towers as a Crusader" } },
                    new GDict { { "stat", "wins" }, { "n", 30 }, { "task", "Win 30 matches as a Crusader" } }) } } },
            { "berserker", new GDict { { "steps", GArray.Of(
                    new GDict { { "stat", "kills" }, { "n", 25 }, { "task", "Knock out 25 enemies as a Berserker" } },
                    new GDict { { "stat", "gates" }, { "n", 80 }, { "task", "Deal 8,000 damage to towers and gates as a Berserker" } },
                    new GDict { { "stat", "wins" }, { "n", 30 }, { "task", "Win 30 matches as a Berserker" } }) } } },
            { "necromancer", new GDict { { "steps", GArray.Of(
                    new GDict { { "stat", "kills" }, { "n", 25 }, { "task", "Knock out 25 enemies as a Necromancer" } },
                    new GDict { { "stat", "healed" }, { "n", 3000 }, { "task", "Heal 3,000 health as a Necromancer" } },
                    new GDict { { "stat", "wins" }, { "n", 30 }, { "task", "Win 30 matches as a Necromancer" } }) } } },
            { "assassin", new GDict { { "steps", GArray.Of(
                    new GDict { { "stat", "kills" }, { "n", 25 }, { "task", "Knock out 25 enemies as an Assassin" } },
                    new GDict { { "stat", "best_multi" }, { "n", 3 }, { "task", "Knock out 3 enemies in one burst as an Assassin" } },
                    new GDict { { "stat", "kills" }, { "n", 400 }, { "task", "Knock out 400 enemies as an Assassin" } }) } } },
            { "sniper", new GDict { { "steps", GArray.Of(
                    new GDict { { "stat", "kills" }, { "n", 25 }, { "task", "Knock out 25 enemies as a Ranger" } },
                    new GDict { { "stat", "wins" }, { "n", 20 }, { "task", "Win 20 matches as a Ranger" } },
                    new GDict { { "stat", "kills" }, { "n", 400 }, { "task", "Knock out 400 enemies as a Ranger" } }) } } },
            { "archmage", new GDict { { "steps", GArray.Of(
                    new GDict { { "stat", "kills" }, { "n", 25 }, { "task", "Knock out 25 enemies as an Archmage" } },
                    new GDict { { "stat", "camps" }, { "n", 10 }, { "task", "Clear 10 jungle camps as an Archmage" } },
                    new GDict { { "stat", "wins" }, { "n", 30 }, { "task", "Win 30 matches as an Archmage" } }) } } },
        };

        public static GArray QuestFamily(string cls)
        {
            // the classes whose play counts toward cls's quest: a base class and its upgrade, or an upgrade alone
            var out_ = GArray.Of(cls);
            foreach (var u in UP_BASE)
            {
                if (GD.Str(UP_BASE[u]) == cls)
                    out_.Append(u);
            }
            return out_;
        }

        public static string QuestKey(string cls, string stat)
        {
            return GD.Fmt("q_%s_%s", cls, stat);
        }

        public static int QuestProgress(GDict stats, string cls, int step)
        {
            GDict q = QUESTS.Get(cls, new GDict()).D;
            if (q.IsEmpty() || step < 0 || step >= q["steps"].Size())
                return 0;
            return (int)stats.Get(QuestKey(cls, GD.Str(q["steps"][step]["stat"])), 0);
        }

        public static GDict QuestReward(string cls, int step)
        {
            // what claiming step (0-based) gives: QUEST_REWARDS, QUEST_FINAL for the last
            if (step < QUEST_REWARDS.Size())
                return QUEST_REWARDS[step].D;
            return QUEST_FINAL.Duplicate();
        }

        public static string QuestNote(string cls)
        {
            // who counts: "Crusader play counts too" for a base class with an upgrade
            var fam = QuestFamily(cls);
            if (fam.Size() > 1)
                return GD.Fmt("%s play counts too", GD.Str(CLASS_NAMES[fam[1]]));
            if (UP_BASE.Has(cls))
                return GD.Fmt("Counts while you wear the %s hat", GD.Str(CLASS_NAMES[cls]));
            return "";
        }

        public static int TitleProgress(GDict stats, string id)
        {
            GDict g = TITLE_GOALS.Get(id, new GDict()).D;
            if (g.IsEmpty())
                return 0;
            if (GD.Str(g["stat"]) == "classes")
            {
                var n = 0;
                foreach (var c in CLASSES)
                {
                    if ((int)stats.Get("main_" + c, 0) > 0)
                        n += 1;
                }
                return n;
            }
            return (int)stats.Get(GD.Str(g["stat"]), 0);
        }

        public static readonly GArray FIVE_STATS = GArray.Of("towers", "camps", "lh", "epics");

        public static GDict MatchRewards(GDict stats, bool won, bool draw, bool online, bool first_win)
        {
            // Itemised so the results screen can show where every coin came from.
            var lines = new GArray();
            // (0.31.184: the Embers a match gave are in its gold, EMBER_GOLD each -- a win 5 -> 150 + 50, a draw or a loss 2 -> + 20)
            // (0.31.189, the balance check: a win 200 -> 150 gold, a draw 120 -> 100, a loss 95 -> 75 -- with the heroes at 25,000)
            GDict base_ = won ? new GDict { { "gold", 150 }, { "xp", 250 }, { "pass", 400 } } : (draw ? new GDict { { "gold", 100 }, { "xp", 175 }, { "pass", 300 } } : new GDict { { "gold", 75 }, { "xp", 125 }, { "pass", 250 } });
            lines.Append(new GDict { { "label", won ? "Victory" : (draw ? "Draw" : "Defeat") }, { "gold", base_["gold"] }, { "xp", base_["xp"] }, { "pass", base_["pass"] } });
            int r = (int)stats.Get("rescues", 0);
            if (r > 0)
                lines.Append(new GDict { { "label", GD.Fmt("King rescues x%d", r) }, { "gold", 50 * r }, { "xp", 40 * r }, { "pass", 60 * r } });
            int k = GD.Mini(30, (int)stats.Get("kills", 0));
            if (k > 0)
                lines.Append(new GDict { { "label", GD.Fmt("Knockouts x%d", k) }, { "gold", 3 * k }, { "xp", 4 * k }, { "pass", 5 * k } });
            int g = GD.Mini(100, (int)stats.Get("gathered", 0));
            if (g > 0)
                lines.Append(new GDict { { "label", GD.Fmt("Gathered x%d", g) }, { "gold", g }, { "xp", g }, { "pass", g } });
            int gd = GD.Mini(40, (int)stats.Get("gates", 0));
            if (gd > 0)
                lines.Append(new GDict { { "label", "Tower and gate damage" }, { "gold", 2 * gd }, { "xp", 3 * gd }, { "pass", 3 * gd } });
            int f = GD.Mini(10, (int)stats.Get("fed", 0));
            if (f > 0)
                lines.Append(new GDict { { "label", GD.Fmt("Fish fed x%d", f) }, { "gold", 10 * f }, { "xp", 10 * f }, { "pass", 15 * f } });
            // 0.31.164 (5v5)
            int tw = GD.Mini(12, (int)stats.Get("towers", 0));
            if (tw > 0)
                lines.Append(new GDict { { "label", GD.Fmt("Towers destroyed x%d", tw) }, { "gold", 25 * tw }, { "xp", 30 * tw }, { "pass", 40 * tw } });
            int cp = GD.Mini(30, (int)stats.Get("camps", 0));
            if (cp > 0)
                lines.Append(new GDict { { "label", GD.Fmt("Jungle camps x%d", cp) }, { "gold", 6 * cp }, { "xp", 8 * cp }, { "pass", 10 * cp } });
            int lh = GD.Mini(150, (int)stats.Get("lh", 0));
            if (lh > 0)
                lines.Append(new GDict { { "label", GD.Fmt("Minion last hits x%d", lh) }, { "gold", lh }, { "xp", lh }, { "pass", lh } });
            int ep = GD.Mini(6, (int)stats.Get("epics", 0));
            if (ep > 0)
                lines.Append(new GDict { { "label", GD.Fmt("Epic monsters x%d", ep) }, { "gold", 40 * ep }, { "xp", 40 * ep }, { "pass", 60 * ep } });
            if (online)
            {
                var sub = new GDict { { "gold", 0 }, { "xp", 0 }, { "pass", 0 } };
                foreach (var ln in lines)
                {
                    foreach (var key in sub)
                        sub[key] += (int)ln[key];
                }
                lines.Append(new GDict { { "label", "Online bonus +20%" }, { "gold", GD.Int((double)sub["gold"] * 0.2) }, { "xp", GD.Int((double)sub["xp"] * 0.2) }, { "pass", GD.Int((double)sub["pass"] * 0.2) } });
            }
            if (first_win)
                lines.Append(new GDict { { "label", "First win of the day" }, { "gold", FIRST_WIN["gold"] }, { "xp", 0 }, { "pass", FIRST_WIN["pass"] } });
            var total = new GDict { { "gold", 0 }, { "xp", 0 }, { "pass", 0 } };
            foreach (var ln in lines)
            {
                foreach (var key in total)
                    total[key] += (int)ln[key];
            }
            total["lines"] = lines;
            return total;
        }

        // ---------------- migration from the dice-era save ----------------
        public static GDict LegacyConversion(GDict old)
        {
            // Old gold 1:1; old tokens -> gems 1:1; old weapons beyond the starter -> 250 gold each;
            // unopened chests -> 150 gold each; old level kept (min 1). Old Fate energy is dropped.
            GArray owned = old.Get("owned", new GArray()).IsArr ? old.Get("owned", new GArray()).A : new GArray();
            GArray chests = old.Get("chests", new GArray()).IsArr ? old.Get("chests", new GArray()).A : new GArray();
            var gold = GD.Maxi(0, (int)old.Get("gold", 0)) + 250 * GD.Maxi(0, owned.Size() - 1) + 150 * chests.Size();
            return new GDict { { "gold", gold }, { "gems", GD.Maxi(0, (int)old.Get("tokens", 0)) }, { "level", GD.Maxi(1, (int)old.Get("level", 1)) },
                { "xp", GD.Maxi(0, (int)old.Get("xp", 0)) }, { "weapons", GD.Maxi(0, owned.Size() - 1) }, { "chests", chests.Size() } };
        }


        // ---------------- chests (0.31.37, Kevin: "a chest system"; "overtime") ----------------
        // Earned by playing, never sold (so they aren't paid loot boxes). CHEST_SLOTS hold chests; one unlocks at a time
        // over its timer; gems skip what's left (1 gem per 10 minutes). The contents are rolled when it's opened, from the
        // chest's id (so a reload can't re-roll), and the odds are shown in the game.
        public const int CHEST_SLOTS = 4;
        public const int TUTORIAL_GOLD = 250;   // the tutorial's pay, once (0.31.108: Profile.finish_tutorial; was siege_mode's)
        // 0.31.124 (Kevin: "Add the discord link to the game" / "Also give a reward for joining the discord"): Settings >
        // COMMUNITY opens the invite; the first time pays DISCORD_GEMS once per account (Profile.claim_discord, replayed by the
        // server). The game can't see whether the player then joins -- opening the invite is what's rewarded.
        public const string DISCORD_URL = "https://discord.gg/H8eKXH8TmM";
        public const int DISCORD_GEMS = 100;
        public static readonly GDict CHESTS = new GDict {
            // 0.31.188 (no weapons to drop): gold, gems and hero shards only. 0.31.189 (the balance check: with six heroes to buy
            // the shards came faster than they could be used, and gems at twice the targets): Wooden 50-100 gold, no gems or shard
            // (was 80-150, 15 % of 5 gems, 5 % a shard); Silver 120-200, 25 % of 5 gems, 2 % a shard (200-320, 40 % of 5-10, 15 %);
            // Gold 300-450, 10-15 gems, 10 % a shard (500-750, 20-30, 40 %); Royal 800, 30-40 gems, a shard half the time
            // (1,200, 60-80, always)
            { "wooden", new GDict { { "name", "Wooden Chest" }, { "unlock", 1800 }, { "gold", GArray.Of(50, 100) }, { "gems_chance", 0.0 }, { "gems", GArray.Of(5, 5) },
                { "color", "#a8794a" }, { "shard", 0.0 } } },
            // 0.31.108: Silver gems 5-10 every time -> a 30% chance of 5 (they were about half of all free gems)
            { "silver", new GDict { { "name", "Silver Chest" }, { "unlock", 3 * 3600 }, { "gold", GArray.Of(120, 200) }, { "gems_chance", 0.25 }, { "gems", GArray.Of(5, 5) },
                { "color", "#c9d3dc" }, { "shard", 0.02 } } },
            { "gold", new GDict { { "name", "Gold Chest" }, { "unlock", 8 * 3600 }, { "gold", GArray.Of(300, 450) }, { "gems_chance", 1.0 }, { "gems", GArray.Of(10, 15) },
                { "color", "#ffcf4a" }, { "shard", 0.1 } } },
            { "royal", new GDict { { "name", "Royal Chest" }, { "unlock", 12 * 3600 }, { "gold", GArray.Of(800, 800) }, { "gems_chance", 1.0 }, { "gems", GArray.Of(30, 40) },
                { "color", "#c47bff" }, { "shard", 0.5 } } },
        };
        // 0.31.185 (League's champion capsules): "shard" -- the chance of a hero shard (any of the sold heroes: unlock it for
        // Eco.SHARD_UNLOCK of its gold price, or melt it)
        public static readonly GDict CHEST_FULL_GOLD = new GDict { { "wooden", 50 }, { "silver", 120 }, { "gold", 300 }, { "royal", 700 } };   // slots full: the chest becomes gold
        public const int CHEST_QUEUE_MAX = 12;   // 0.31.108: reward chests waiting for a slot (beyond this they turn into gold)

        public static int SkipCost(int remaining_s)
        {
            return GD.Maxi(1, GD.Int(GD.Ceil((double)remaining_s / 600.0)));
        }

        public static GDict RollChest(string kind, long seed_value)
        {
            // -> {gold, gems, shard (a hero, "" if none)} -- the same on the phone and the server (the seed is the chest's)
            GDict c = CHESTS[kind].D;
            var rng = new Rng();
            rng.Seed = unchecked((ulong)seed_value);
            var out_ = new GDict { { "gold", rng.RandiRange((int)c["gold"][0], (int)c["gold"][1]) }, { "gems", 0 }, { "shard", "" } };
            if (rng.Randf() < (double)c["gems_chance"])
                out_["gems"] = rng.RandiRange((int)c["gems"][0], (int)c["gems"][1]);
            if ((double)c.Get("shard", 0.0) > 0.0 && rng.Randf() < (double)c["shard"])
            {
                GArray heroes = HERO_PRICES.Keys();
                heroes.Sort();
                out_["shard"] = GD.Str(heroes[rng.RandiRange(0, heroes.Size() - 1)]);
            }
            return out_;
        }

        public static string ChestOdds(string kind)
        {
            // for the info panel: what's in it, plainly
            GDict c = CHESTS[kind].D;
            var parts = GArray.Of((int)c["gold"][0] != (int)c["gold"][1] ? GD.Fmt("%d-%d gold", (int)c["gold"][0], (int)c["gold"][1]) : GD.Fmt("%d gold", (int)c["gold"][0]));
            var gems = (int)c["gems"][0] == (int)c["gems"][1] ? GD.Fmt("%d", (int)c["gems"][0]) : GD.Fmt("%d-%d", (int)c["gems"][0], (int)c["gems"][1]);
            if ((double)c["gems_chance"] >= 1.0)
                parts.Append(GD.Fmt("%s gems", gems));
            else if ((double)c["gems_chance"] > 0.0)                   // (0.31.189: a Wooden chest holds no gems)
                parts.Append(GD.Fmt("%d%% chance of %s gems", GD.Int(GD.Round((double)c["gems_chance"] * 100.0)), gems));
            if ((double)c.Get("shard", 0.0) > 0.0)
                parts.Append((double)c["shard"] >= 1.0 ? "a hero shard" : GD.Fmt("%d%% chance of a hero shard", GD.Int(GD.Round((double)c["shard"] * 100.0))));
            return GStr.Join(" · ", parts);
        }


        // ---------------- gold that was Embers (0.31.184) ----------------
        // (0.31.93-0.31.187: the Forge, Embers until 0.31.184.) Kevin: "Maybe let's have the two currency so it's more simple" --
        // what gave Embers gives gold at EMBER_GOLD a piece, and a save's Embers turn into gold once (Profile._normalized).
        public const int EMBER_GOLD = 10;
        public const int DAILY_GOLD = 0;   // each daily order claimed (0.31.93-0.31.183: 15 Embers; 0.31.184-0.31.188: 150 gold --
                                           // 0.31.189: gone, each order pays its own gold)


        // ---------------- clans (0.31.196) ----------------
        // Kevin: "Now let's redo the clan system for new game" -> "Do clan chest, clan camp, crest, shard requests, 5-stack, lfg
        // button, league". server/clans.gd keeps the books; the phone (scripts/app/clan_panel.gd) shows them with these numbers.
        // A players' clan (not one of the three starter clans, the house clans of 0.31.148) earns CLAN POINTS from its members'
        // online matches (the server's own count, siege_server _pay_match): CLAN_POINTS for the result, the towers and the KOs,
        // doubled (CLAN_PARTY_X) for a member who had a clanmate in his party. A week's points (Monday 00:00 UTC, as the
        // leaderboard) fill the CLAN CHEST -- CLAN_CHEST_TIERS, one chest for the highest tier reached, to every member who earned
        // CLAN_CHEST_MIN that week -- and rank the clans in the CLAN LEAGUE (CLAN_LEAGUE_PRIZES: gems to the same members, and a
        // frame round the crest for the next week). Every point is clan XP too (and every shard given, CLAN_GIVE_XP): CLAN_LEVELS
        // -> the clan's level, which grows its camp (CLAN_CAMP_STAGE: the camp painting's four stages).
        public static readonly GDict CLAN_POINTS = new GDict { { "win", 10 }, { "draw", 6 }, { "loss", 4 }, { "tower", 2 }, { "ko", 1 }, { "ko_max", 10 } };
        public const int CLAN_PARTY_X = 2;
        public static readonly GArray CLAN_CHEST_TIERS = GArray.Of(GArray.Of(60, "wooden"), GArray.Of(200, "silver"), GArray.Of(500, "gold"), GArray.Of(1000, "royal"));
        public const int CLAN_CHEST_MIN = 10;
        public static readonly GArray CLAN_LEAGUE_PRIZES = GArray.Of(
            new GDict { { "from", 1 }, { "to", 1 }, { "gems", 100 }, { "frame", "gold" } },
            new GDict { { "from", 2 }, { "to", 2 }, { "gems", 60 }, { "frame", "silver" } },
            new GDict { { "from", 3 }, { "to", 3 }, { "gems", 60 }, { "frame", "bronze" } },
            new GDict { { "from", 4 }, { "to", 10 }, { "gems", 30 }, { "frame", "" } }
        );
        public static readonly GArray CLAN_LEVELS = GArray.Of(0, 200, 600, 1200, 2000, 3200, 4800, 7000, 10000, 14000);   // the XP for levels 1-10
        public static readonly GArray CLAN_CAMP_STAGE = GArray.Of(1, 1, 2, 2, 3, 3, 3, 4, 4, 4);   // the camp's stage at levels 1-10
        public const int CLAN_GIVE_XP = 5;
        // shard requests: a member asks the clan for a shard of a hero he hasn't got (one ask open at a time, at most one every
        // CLAN_ASK_GAP, open CLAN_ASK_LIFE); a member holding a shard of that hero gives it -- the asker gets the shard, the giver
        // what melting it would have paid (Profile.melt_shard's gold) and the clan CLAN_GIVE_XP. A shard a clanmate gave can't be
        // given on (Profile "gift_shards"): passed back and forth it would pay its melt gold every time
        public const int CLAN_ASK_GAP = 7 * 3600;   // 0.31.197 (Kevin: "put a request donation limit to once per 7 hours"; was 8)
        public const int CLAN_ASK_LIFE = 24 * 3600;
        // LFG: a member says he's looking for a party (clan chat, CLAN_LFG_LIFE); clanmates JOIN straight into his party
        public const int CLAN_LFG_LIFE = 600;
        // the crest: an emblem in one colour on a shield of another (assets/ui/clans/, tools/build_clan_art.py)
        public static readonly GArray CLAN_EMBLEMS = GArray.Of("lion", "stag", "raven", "wolf", "dragon", "bear", "eagle", "boar", "skull", "crown", "swords", "tower",
            "tree", "flame", "moon", "bolt");
        public static readonly GArray CLAN_FIELDS = GArray.Of("#2b59c3", "#c0392b", "#1f8a4c", "#7d3cc8", "#d97a1e", "#1d2436", "#0f8f8f", "#a0284f", "#6b4a2b", "#e8e2d0");
        public static readonly GArray CLAN_CHARGES = GArray.Of("#ffffff", "#ffd65a", "#141414", "#ff6b5e", "#7fe3ff", "#8cf0a8", "#d9a8ff", "#c0c6cf");
        // the three house clans' crests (and a players' clan made with a house by an older app: 0.31.134-0.31.195)
        public static readonly GDict CLAN_HOUSE_CREST = new GDict { { "lions", new GDict { { "e", 0 }, { "f", 4 }, { "c", 0 } } }, { "stags", new GDict { { "e", 1 }, { "f", 2 }, { "c", 0 } } }, { "ravens", new GDict { { "e", 2 }, { "f", 3 }, { "c", 0 } } } };

        public static int ClanPoints(GDict me, bool won, bool draw)
        {
            // one online match's clan points (before CLAN_PARTY_X)
            var p = (int)(won ? CLAN_POINTS["win"] : (draw ? CLAN_POINTS["draw"] : CLAN_POINTS["loss"]));
            p += GD.Maxi(0, (int)me.Get("towers", 0)) * (int)CLAN_POINTS["tower"];
            p += GD.Mini(GD.Maxi(0, (int)me.Get("kills", 0)) * (int)CLAN_POINTS["ko"], (int)CLAN_POINTS["ko_max"]);
            return p;
        }

        public static int ClanLevel(int xp)
        {
            var lv = 1;
            for (int i = 0; i < CLAN_LEVELS.Size(); i++)
            {
                if (xp >= (int)CLAN_LEVELS[i])
                    lv = i + 1;
            }
            return lv;
        }

        public static int ClanLevelXp(int lv)
        {
            // the XP a level starts at (-1 past the last)
            return lv >= 1 && lv <= CLAN_LEVELS.Size() ? (int)CLAN_LEVELS[lv - 1] : -1;
        }

        public static int ClanCampStage(int lv)
        {
            return (int)CLAN_CAMP_STAGE[GD.Clampi(lv, 1, CLAN_CAMP_STAGE.Size()) - 1];
        }

        public static int ClanTier(int pts)
        {
            // the Clan Chest's tier the week's points reached (0: none yet)
            var t = 0;
            for (int i = 0; i < CLAN_CHEST_TIERS.Size(); i++)
            {
                if (pts >= (int)CLAN_CHEST_TIERS[i][0])
                    t = i + 1;
            }
            return t;
        }

        public static string ClanChestOf(int tier)
        {
            return tier >= 1 && tier <= CLAN_CHEST_TIERS.Size() ? GD.Str(CLAN_CHEST_TIERS[tier - 1][1]) : "";
        }

        public static GDict ClanLeaguePrize(int rank)
        {
            foreach (var t in CLAN_LEAGUE_PRIZES)
            {
                if (rank >= (int)t["from"] && rank <= (int)t["to"])
                    return t.D;
            }
            return new GDict();
        }

        public static GDict CleanCrest(Var c)
        {
            // {"e", "f", "c"} within the lists ({} when it isn't one)
            if (!c.IsDict)
                return new GDict();
            var e = (int)c.Get("e", -1);
            var f = (int)c.Get("f", -1);
            var ch = (int)c.Get("c", -1);
            if (e < 0 || e >= CLAN_EMBLEMS.Size() || f < 0 || f >= CLAN_FIELDS.Size() || ch < 0 || ch >= CLAN_CHARGES.Size())
                return new GDict();
            return new GDict { { "e", e }, { "f", f }, { "c", ch } };
        }

        public static string CrestCode(GDict c)
        {
            // "e.f.c" -- the crest on cards, chat lines, the match's names and the leaderboard ("" for none)
            var k = CleanCrest(c);
            return k.IsEmpty() ? "" : GD.Fmt("%d.%d.%d", (int)k["e"], (int)k["f"], (int)k["c"]);
        }

        public static GDict CrestOfCode(string s)
        {
            var p = s.Split(".");
            if (p.Length != 3 || !p[0].IsValidInt() || !p[1].IsValidInt() || !p[2].IsValidInt())
                return new GDict();
            return CleanCrest(new GDict { { "e", GD.Int(p[0]) }, { "f", GD.Int(p[1]) }, { "c", GD.Int(p[2]) } });
        }
    }
}
