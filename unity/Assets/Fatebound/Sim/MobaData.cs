// moba.gd's tables (0.31.155-0.31.217): heroes, towers, waves, ultimates, items, the jungle. The rules are in Moba.cs.
using System;
using System.Collections.Generic;

namespace Fatebound.Sim
{
    public sealed class HeroDef
    {
        public string name, cls;
        public bool up;
    }

    public sealed class UltDef
    {
        public string name, shortName, text;
        public double cd;
        public string Short => shortName ?? name;
    }

    public sealed class ItemDef
    {
        public string id, name, icon;
        public int cost;
        public string[] from = new string[0];
        public bool boots;
        public double dmg, hp, @as, spd, cdr, ls, regen, armor, heal;
        public bool Has(string k) => Stat(k) != 0.0;
        public double Stat(string k)
        {
            switch (k)
            {
                case "dmg": return dmg;
                case "hp": return hp;
                case "as": return @as;
                case "spd": return spd;
                case "cdr": return cdr;
                case "ls": return ls;
                case "regen": return regen;
                case "armor": return armor;
                case "heal": return heal;
            }
            return 0.0;
        }
    }

    public sealed class CampKind
    {
        public string name, buff;
        public (string mk, Vec2 off)[] mobs;
        public double respawn;
    }

    public sealed class MonsterDef
    {
        public string name, look, cls;
        public double hp, dmg, spd, gold, xp, scale = 1.0;
    }

    public sealed partial class Moba
    {
        static HeroDef H(string name, string cls, bool up) => new HeroDef { name = name, cls = cls, up = up };

        public static readonly Dictionary<string, HeroDef> HEROES = new Dictionary<string, HeroDef>
        {
            { "knight", H("Knight", "knight", false) }, { "barbarian", H("Barbarian", "barbarian", false) },
            { "rogue", H("Rogue", "rogue", false) }, { "ranger", H("Archer", "ranger", false) },
            { "mage", H("Mage", "mage", false) }, { "priest", H("Priest", "priest", false) },
            { "crusader", H("Crusader", "knight", true) }, { "berserker", H("Berserker", "barbarian", true) },
            { "assassin", H("Assassin", "rogue", true) }, { "sniper", H("Ranger", "ranger", true) },
            { "archmage", H("Archmage", "mage", true) }, { "necromancer", H("Necromancer", "priest", true) },
            { "golem", H("Golem", "barbarian", false) }, { "dragoon", H("Dragoon", "knight", false) },
            { "duelist", H("Duelist", "rogue", false) }, { "stormcaller", H("Stormcaller", "mage", false) },
            { "musketeer", H("Musketeer", "ranger", false) }, { "druid", H("Druid", "mage", false) },
        };
        public static readonly string[] HERO_ORDER = { "knight", "barbarian", "rogue", "ranger", "mage", "priest", "crusader", "berserker",
            "assassin", "sniper", "archmage", "necromancer", "golem", "dragoon", "duelist", "stormcaller", "musketeer", "druid" };

        // 0.31.168: the new heroes' own numbers over their class's (by SK; null: the class's)
        static double?[] HB(double? hp = null, double? dmg = null, double? speed = null, double? range = null, double? arc = null,
            double? windup = null, double? recover = null, double? aoe = null, double? proj_speed = null)
        {
            var a = new double?[9];
            a[(int)SK.hp] = hp; a[(int)SK.dmg] = dmg; a[(int)SK.speed] = speed; a[(int)SK.range] = range; a[(int)SK.arc] = arc;
            a[(int)SK.windup] = windup; a[(int)SK.recover] = recover; a[(int)SK.aoe] = aoe; a[(int)SK.proj_speed] = proj_speed;
            return a;
        }

        public static readonly Dictionary<string, double?[]> HERO_BASE = new Dictionary<string, double?[]>
        {
            { "golem", HB(hp: 172.0, dmg: 19.0, speed: 4.5, range: 2.1, arc: 0.35, windup: 0.36, recover: 0.48) },
            { "dragoon", HB(hp: 142.0, dmg: 23.0, speed: 4.8, range: 2.7, arc: 0.3, windup: 0.3, recover: 0.45) },
            { "duelist", HB(hp: 94.0, dmg: 15.0, speed: 6.3, range: 1.6, arc: 0.5, windup: 0.12, recover: 0.2) },
            { "stormcaller", HB(hp: 76.0, dmg: 21.0, speed: 5.0, range: 9.5, proj_speed: 34.0, aoe: 0.0, windup: 0.35, recover: 0.5) },
            { "musketeer", HB(hp: 80.0, dmg: 25.0, speed: 5.2, range: 12.5, proj_speed: 46.0, windup: 0.42, recover: 0.85) },
            { "druid", HB(hp: 88.0, dmg: 14.0, speed: 5.1, range: 9.0, proj_speed: 26.0, aoe: 0.0, windup: 0.35, recover: 0.45) },
        };
        public static readonly Dictionary<string, string> HERO_SHOT = new Dictionary<string, string>
            { { "stormcaller", "bolt" }, { "musketeer", "ball" }, { "druid", "thorn" } };
        public static readonly Dictionary<string, double> HERO_SCALE = new Dictionary<string, double> { { "golem", 1.12 } };
        public static readonly Dictionary<string, string> HERO_LINE = new Dictionary<string, string>
        {
            { "knight", "Shield up: blocks everything from the front." }, { "barbarian", "Spins through a crowd." },
            { "rogue", "Lunges in, quick and sharp." }, { "ranger", "Arrows from range, a volley of five." },
            { "mage", "Fireballs, and a nova all round." },
            { "priest", "Heals with a beam; Sanctuary heals everyone near." }, { "crusader", "Throws his hammer through a line, and blocks." },
            { "berserker", "A whirlwind that keeps moving." }, { "assassin", "Vanishes, then strikes twice as hard." },
            { "sniper", "A piercing shot through everyone in a line." }, { "archmage", "Calls down a meteor." },
            { "necromancer", "Drains enemies to heal friends; raises the fallen." },
            { "golem", "A wall of living stone: boulders, quakes, an avalanche." }, { "dragoon", "A halberd that sweeps, drags and dives from the sky." },
            { "duelist", "Lunges, parries and answers -- a blade for one foe at a time." },
            { "stormcaller", "Lightning that leaps from foe to foe, wind and a storm." },
            { "musketeer", "Long, heavy shots; buckshot and powder kegs up close." },
            { "druid", "Heals that grow over time, roots and bark, a grove of life." },
        };

        public static Vec2[][] LANES => Land.LANES;
        public static readonly string[] LANE_NAMES = { "west", "middle", "east" };
        static Vec2 V(double x, double y) => new Vec2(x, y);
        public static readonly (int lane, int tier, Vec2 p)[] TOWERS_BLUE =
        {
            (0, 1, V(-73.04, 16.48)), (0, 2, V(-44.76, 44.76)), (0, 3, V(-17.89, 71.63)),
            (1, 1, V(4.0, 30.0)), (1, 2, V(4.0, 54.0)), (1, 3, V(4.0, 74.5)),
            (2, 1, V(73.04, 16.48)), (2, 2, V(44.76, 44.76)), (2, 3, V(17.89, 71.63)),
        };

        public static readonly string[] WAVE = { "knight", "ranger", "ranger", "priest" };
        public const double WAVE_FIRST = 15.0;
        public const double WAVE_EVERY = 30.0;
        public const double WAVE_EVERY_MID = 25.0;
        public const double WAVE_EVERY_LATE = 20.0;
        public const double MID_AT = 420.0;
        public const double LATE_AT = 750.0;
        public static readonly Dictionary<string, string> MINION_CLS = new Dictionary<string, string>
            { { "melee", "knight" }, { "caster", "ranger" }, { "siege", "mage" }, { "super", "barbarian" } };
        public static readonly Dictionary<string, double> MINION_KIND_HP = new Dictionary<string, double>
            { { "melee", 0.5 }, { "caster", 0.58 }, { "siege", 1.9 }, { "super", 2.2 } };
        public static readonly Dictionary<string, double> MINION_KIND_DMG = new Dictionary<string, double>
            { { "melee", 0.45 }, { "caster", 0.8 }, { "siege", 1.0 }, { "super", 1.6 } };
        public static readonly Dictionary<string, double> MINION_KIND_SCALE = new Dictionary<string, double> { { "siege", 1.1 } };
        public const double MINION_UP = 0.05;
        public const double MINION_UP_EVERY = 90.0;
        public const double MINION_VS_HERO = 0.6;
        public const double ACQ_R = 8.0;
        public const double HELP_R = 15.0;
        public const int MINION_CAP = 48;
        public const double MINION_HP = 0.5;
        public const double MINION_DMG = 0.45;
        public const double MINION_SPD = 0.88;
        public const double MINION_GONE = 3.0;
        public const double HERO_HP = 1.8;
        public const int LEVEL_MAX = 10;
        public const double LEVEL_GROW = 0.08;
        public const double XP_BASE = 60.0;
        public const double XP_STEP = 30.0;
        public const double MINION_XP = 15.0;
        public static readonly Dictionary<string, double> MINION_XP_BY = new Dictionary<string, double>
            { { "melee", 16.0 }, { "caster", 8.0 }, { "siege", 25.0 }, { "super", 25.0 } };
        public const double XP_R = 12.0;
        public const double HERO_XP = 40.0;
        public const double HERO_XP_LVL = 12.0;
        public const double TOWER_XP = 50.0;
        public const double RESPAWN_BASE = 4.0;
        public const double RESPAWN_LVL = 2.6;
        public const double FOUNTAIN = 0.06;
        public const double TOWER_R = 1.5;
        public const double TOWER_RANGE = 11.5;
        public static readonly double[] TOWER_HP = { 0.0, 900.0, 1150.0, 1300.0, 1200.0 };
        public static readonly Dictionary<string, double> MINION_TOWER = new Dictionary<string, double>
            { { "melee", 0.4 }, { "caster", 0.4 }, { "siege", 1.6 }, { "super", 1.6 } };
        public const double TOWER_EVERY = 1.2;
        public const double TOWER_FLIGHT = 0.3;
        public const double TOWER_HERO_DMG = 50.0;
        public const double TOWER_RAMP = 0.5;
        public const int TOWER_RAMP_MAX = 3;
        public const double TOWER_RAMP_COOL = 5.0;
        public const double TOWER_GROW = 0.04;
        public static readonly Dictionary<string, double> TOWER_PCT = new Dictionary<string, double>
            { { "melee", 0.45 }, { "caster", 0.7 }, { "siege", 0.14 }, { "super", 0.05 }, { "pet", 0.45 }, { "lord", 0.05 } };
        public const double TOWER_PCT_ELSE = 0.7;
        public const double TOWER_HELP_R = 21.5;
        public const double BACKDOOR = 0.2;
        public const double MELEE_VS_TOWER = 1.2;
        public const int PLATES = 5;
        public const double PLATES_UNTIL = 420.0;
        public const int GOLD_PLATE = 60;
        public const int GOLD_TOWER_LOCAL = 200;
        public static readonly int[] GOLD_TOWER_GLOBAL = { 0, 50, 25, 25, 25 };
        public const int GOLD_FIRST_TOWER = 150;
        public const double TOWER_LOCAL_R = 18.0;
        public const double HELP_FOR = 2.0;
        public static readonly (string key, string name)[] UPGRADES =
        {
            ("dmg", "+15% DAMAGE"), ("hp", "+15% HEALTH"), ("spd", "+8% SPEED"), ("as", "+12% ATTACK SPEED"),
            ("cdr", "ABILITY +25% FASTER"), ("ls", "8% LIFESTEAL"), ("regen", "REGEN 1%/s"),
        };
        public const int UP_MAX = 3;
        public const double KING_HP = 3000.0;
        public const double KING_R = 1.0;
        public const double KING_REACH = 4.5;
        public const double KING_SLAM = 50.0;
        public const double KING_SLAM_MINION = 0.35;
        public const double KING_EVERY = 1.6;
        public const double KING_REGEN = 0.002;
        public const double KING_QUIET = 10.0;
        public const double GATE_HP_5V5 = 800.0;
        public const double MATCH_5V5 = 1200.0;
        public const double KING_GUARD = 14.0;

        // ---------- ultimates ----------
        public const int ULT_LEVEL = 4;
        public const int ULT_RANK2 = 8;
        public static readonly Dictionary<string, int> SKILL_MAX = new Dictionary<string, int> { { "q", 3 }, { "w", 3 }, { "e", 3 }, { "r", 2 } };
        public const double RANK_POWER = 0.2;
        public const double RANK_CD = 0.1;
        public const double RANK2_POWER = 1.35;
        public const double RANK2_CD = 0.75;
        static UltDef U(string name, double cd, string text, string shortName = null) => new UltDef { name = name, cd = cd, text = text, shortName = shortName };
        public static readonly Dictionary<string, UltDef> ULTS = new Dictionary<string, UltDef>
        {
            { "knight", U("BULWARK", 70.0, "You and every ally near take half damage for 5 s.") },
            { "barbarian", U("WAR CRY", 60.0, "6 s of fury: far quicker swings, harder hits, quicker feet.", "WARCRY") },
            { "rogue", U("EXECUTE", 50.0, "Blinks behind the weakest enemy hero near and strikes for triple -- more the more hurt he is.") },
            { "ranger", U("ARROW RAIN", 60.0, "Arrows pour down on a wide circle for 2.4 s.", "RAIN") },
            { "mage", U("INFERNO", 60.0, "A huge ring of fire round you: heavy damage, and everyone in it stunned.") },
            { "priest", U("GRACE", 80.0, "Heals every hero on your side, wherever they are, by a third.") },
            { "crusader", U("JUDGMENT", 65.0, "Smites the ground: enemies near hurt and stunned, allies near healed.") },
            { "berserker", U("UNDYING", 75.0, "For 5 s nothing can take you below 1 health, and you hit harder.") },
            { "assassin", U("FLURRY", 65.0, "Darts from enemy to enemy -- up to four near -- striking each for double.") },
            { "sniper", U("DEADEYE", 70.0, "A huge arrow across the whole field, through everyone in its way, stunning.") },
            { "archmage", U("METEORS", 75.0, "Six meteors rain down round your target.") },
            { "necromancer", U("LEGION", 80.0, "Raises four skeletons who fight for you for 20 s.") },
            { "golem", U("LANDSLIDE", 75.0, "Roll 9 m like an avalanche, flattening everyone in the way; where you stop the ground breaks -- enemies near stunned 1.5 s.", "SLIDE") },
            { "dragoon", U("DRAGON DIVE", 70.0, "Leap high onto an enemy hero up to 11 m away and crash down: heavy damage and a 1 s stun round you.", "DIVE") },
            { "duelist", U("GRAND CHALLENGE", 65.0, "Five lightning strikes at the nearest enemy hero up to 8 m, from every side -- harder the more hurt he is.", "DUEL") },
            { "stormcaller", U("THUNDERSTORM", 75.0, "A storm up to 13 m away: for 3.5 s bolts strike the enemies under it, each a short stun.", "STORM") },
            { "musketeer", U("QUICKDRAW", 70.0, "Shoots every enemy hero you can see within 15 m -- up to five -- for double, more the more hurt they are.", "DRAW") },
            { "druid", U("WILD GROWTH", 80.0, "A grove round you for 5 s: allies in it heal 5 % of their health a second; enemies in it slowed and stung.", "GROVE") },
        };
        public const double BULWARK_R = 7.0;
        public const double BULWARK_DR = 0.5;
        public const double BULWARK_TIME = 5.0;
        public const double WARCRY_TIME = 6.0;
        public const double WARCRY_AS = 0.67;
        public const double WARCRY_SPD = 1.15;
        public const double WARCRY_DMG = 1.25;
        public const double EXECUTE_R = 10.0;
        public const double EXECUTE_DMG = 3.0;
        public const double EXECUTE_MISSING = 0.2;
        public const double RAIN_RANGE = 15.0;
        public const double RAIN_R = 4.5;
        public const int RAIN_TICKS = 8;
        public const double RAIN_EVERY = 0.3;
        public const double RAIN_DMG = 0.55;
        public const double INFERNO_R = 7.0;
        public const double INFERNO_DMG = 2.4;
        public const double INFERNO_STUN = 1.2;
        public const double GRACE_HEAL = 0.35;
        public const double JUDGMENT_R = 5.5;
        public const double JUDGMENT_DMG = 2.0;
        public const double JUDGMENT_STUN = 1.5;
        public const double JUDGMENT_HEAL = 0.15;
        public const double UNDYING_TIME = 5.0;
        public const double UNDYING_DMG = 1.3;
        public const double FLURRY_R = 9.0;
        public const int FLURRY_N = 4;
        public const double FLURRY_DMG = 2.0;
        public const double FLURRY_EVERY = 0.22;
        public const double DEADEYE_RANGE = 75.0;
        public const double DEADEYE_SPEED = 55.0;
        public const double DEADEYE_DMG = 3.5;
        public const double DEADEYE_STUN = 1.2;
        public const double STORM_RANGE = 14.0;
        public const int STORM_N = 6;
        public const double STORM_SPREAD = 4.0;
        public const double STORM_DMG = 1.6;
        public const int LEGION_N = 4;
        public const double LEGION_TIME = 20.0;
        public const double LEGION_HP = 0.9;
        public const double LEGION_DMG = 0.6;

        // ---------- gold and the shop ----------
        public const int GOLD_START = 500;
        public const double GOLD_PASSIVE = 2.0;
        public static readonly Dictionary<string, int> GOLD_MINION = new Dictionary<string, int>
            { { "melee", 21 }, { "caster", 14 }, { "siege", 60 }, { "super", 60 } };
        public const int GOLD_HERO = 300;
        public const int GOLD_ASSIST = 150;
        public const double KILL_CREDIT = 15.0;
        public const double MULTI_GAP = 10.0;
        public const double PENTA_GAP = 30.0;
        public static readonly string[] MULTI_NAMES = { "", "", "DOUBLE KILL", "TRIPLE KILL", "QUADRA KILL", "PENTAKILL" };
        public const double BOUNTY_KILL = 0.25;
        public const double BOUNTY_CS = 0.05;
        public const double BOUNTY_MAX = 700.0;
        public const int BOUNTY_SHOW = 150;
        public const int BOUNTY_STEP = 50;
        public const double DEVALUE_FROM = 0.10;
        public const double DEVALUE_FULL = 0.40;
        public const double DEVALUE_MIN = 0.2;
        public const double DEVALUE_MAX = 0.8;
        public const double ASSIST_WINDOW = 10.0;
        public const double SELL_BACK = 0.7;
        public const int ITEM_SLOTS = 6;
        public const double ARMOR_MAX = 0.5;

        static ItemDef I(string id, string name, int cost, string icon, string[] from = null, bool boots = false, double dmg = 0, double hp = 0,
            double @as = 0, double spd = 0, double cdr = 0, double ls = 0, double regen = 0, double armor = 0, double heal = 0)
            => new ItemDef { id = id, name = name, cost = cost, icon = icon, from = from ?? new string[0], boots = boots, dmg = dmg, hp = hp,
                @as = @as, spd = spd, cdr = cdr, ls = ls, regen = regen, armor = armor, heal = heal };

        public static readonly Dictionary<string, ItemDef> ITEMS = new Dictionary<string, ItemDef>
        {
            { "sword", I("sword", "Long Sword", 350, "sword", dmg: 0.12) },
            { "ruby", I("ruby", "Ruby Crystal", 400, "ruby", hp: 0.15) },
            { "dagger", I("dagger", "Dagger", 300, "dagger", @as: 0.12) },
            { "boots", I("boots", "Boots", 300, "boots", boots: true, spd: 0.10) },
            { "tome", I("tome", "Spell Tome", 400, "tome", cdr: 0.20) },
            { "fang", I("fang", "Vampire Fang", 400, "fang", ls: 0.07) },
            { "bead", I("bead", "Healing Bead", 250, "bead", regen: 0.006) },
            { "cloth", I("cloth", "Cloth Armor", 300, "shield", armor: 0.10) },
            { "greaves", I("greaves", "Swift Greaves", 900, "boots", new[] { "boots" }, boots: true, spd: 0.20) },
            { "bloodthirster", I("bloodthirster", "Bloodthirster", 1900, "sword", new[] { "sword", "fang" }, dmg: 0.35, ls: 0.12) },
            { "titan", I("titan", "Titan's Belt", 1700, "ruby", new[] { "ruby", "bead" }, hp: 0.40, regen: 0.012) },
            { "phantom", I("phantom", "Phantom Blade", 1700, "dagger", new[] { "dagger", "dagger" }, @as: 0.35, spd: 0.06) },
            { "archon", I("archon", "Archon Staff", 1800, "tome", new[] { "tome", "sword" }, dmg: 0.30, cdr: 0.30) },
            { "thorn", I("thorn", "Thornplate", 1600, "shield", new[] { "cloth", "ruby" }, armor: 0.25, hp: 0.15) },
            { "relic", I("relic", "Holy Relic", 1500, "bead", new[] { "tome", "bead" }, heal: 0.40, hp: 0.15, cdr: 0.15) },
        };
        public static readonly string[] ITEM_ORDER = { "sword", "ruby", "dagger", "boots", "tome", "fang", "bead", "cloth",
            "bloodthirster", "titan", "phantom", "archon", "thorn", "greaves", "relic" };
        public static readonly (string tab, string[] ids)[] ITEM_TABS =
        {
            ("ATTACK", new[] { "sword", "dagger", "fang", "bloodthirster", "phantom" }),
            ("MAGIC", new[] { "tome", "archon", "relic" }),
            ("DEFENSE", new[] { "ruby", "cloth", "bead", "titan", "thorn" }),
            ("MOVEMENT", new[] { "boots", "greaves" }),
        };
        public static readonly Dictionary<string, string[]> BUILDS = new Dictionary<string, string[]>
        {
            { "knight", new[] { "boots", "ruby", "cloth", "thorn", "greaves", "sword", "fang", "bloodthirster", "bead", "titan" } },
            { "barbarian", new[] { "sword", "boots", "fang", "bloodthirster", "greaves", "ruby", "cloth", "thorn", "bead", "titan" } },
            { "rogue", new[] { "sword", "boots", "fang", "bloodthirster", "dagger", "dagger", "phantom", "greaves", "ruby", "cloth", "thorn" } },
            { "ranger", new[] { "dagger", "boots", "dagger", "phantom", "sword", "fang", "bloodthirster", "greaves", "ruby", "bead", "titan" } },
            { "mage", new[] { "tome", "boots", "sword", "archon", "greaves", "ruby", "bead", "titan", "cloth" } },
            { "priest", new[] { "tome", "boots", "bead", "relic", "greaves", "ruby", "cloth", "thorn" } },
            { "golem", new[] { "boots", "ruby", "cloth", "thorn", "greaves", "sword", "fang", "bloodthirster", "bead", "titan" } },
            { "druid", new[] { "tome", "boots", "bead", "relic", "greaves", "ruby", "cloth", "thorn" } },
        };

        // ---------- the jungle ----------
        public const int JUNGLE = -2;
        public const double CAMP_FIRST = 30.0;
        public const double LORD_FIRST = 300.0;
        public static readonly (string kind, Vec2 p)[] CAMPS_BLUE =
        {
            ("pack", V(-58.69, 16.26)), ("archers", V(-19.8, 48.08)), ("arcane", V(-32.53, 24.04)),
            ("pack", V(58.69, 16.26)), ("archers", V(19.8, 48.08)), ("ember", V(32.53, 24.04)),
        };
        public static readonly Vec2 BOSS_P = new Vec2(-Land.POOL_X, 0.0);
        static CampKind CK(string name, double respawn, string buff, params (string, Vec2)[] mobs) =>
            new CampKind { name = name, respawn = respawn, buff = buff, mobs = mobs };
        public static readonly Dictionary<string, CampKind> CAMP_KINDS = new Dictionary<string, CampKind>
        {
            { "pack", CK("Bone Pack", 75.0, null, ("warrior", V(0, 0)), ("minion", V(-1.7, 1.2)), ("minion", V(1.7, 1.2))) },
            { "archers", CK("Grave Archers", 75.0, null, ("archer", V(-1.3, 0)), ("archer", V(1.3, 0)), ("minion", V(0, 1.5))) },
            { "arcane", CK("Arcane Wraith", 120.0, "arcane", ("wraith", V(0, 0)), ("minion", V(-1.8, 1.4)), ("minion", V(1.8, 1.4))) },
            { "ember", CK("Ember Brute", 120.0, "ember", ("brute", V(0, 0)), ("minion", V(-1.8, 1.4)), ("minion", V(1.8, 1.4))) },
            { "lord", CK("Bone Lord", 180.0, null, ("lord", V(0, 0))) },
            { "wyrm", CK("Grave Wyrm", 180.0, null, ("wyrm", V(0, 0))) },
        };
        static MonsterDef MD(string name, string look, string cls, double hp, double dmg, double spd, double gold, double xp, double scale = 1.0) =>
            new MonsterDef { name = name, look = look, cls = cls, hp = hp, dmg = dmg, spd = spd, gold = gold, xp = xp, scale = scale };
        public static readonly Dictionary<string, MonsterDef> MONSTERS = new Dictionary<string, MonsterDef>
        {
            { "minion", MD("Skeleton", "skel_minion", "rogue", 2.0, 0.6, 0.85, 20, 18) },
            { "warrior", MD("Skeleton Warrior", "skel_warrior", "barbarian", 3.6, 0.6, 0.8, 45, 40) },
            { "archer", MD("Skeleton Archer", "skel_rogue", "ranger", 2.4, 0.7, 0.8, 28, 25) },
            { "wraith", MD("Arcane Wraith", "skel_mage", "mage", 7.0, 0.8, 0.8, 90, 70, 1.3) },
            { "brute", MD("Ember Brute", "skel_brute", "barbarian", 6.5, 0.85, 0.8, 90, 70, 1.35) },
            { "lord", MD("Bone Lord", "skel_lord", "barbarian", 26.0, 1.9, 0.75, 300, 120, 1.9) },
            { "wyrm", MD("Grave Wyrm", "wyrm", "barbarian", 14.0, 0.8, 0.7, 150, 80, 1.8) },
        };
        public const double MON_GROW = 0.05;
        public const double LEASH = 9.0;
        public const double LORD_LEASH = 8.0;
        public const double RESET_HEAL = 0.3;
        public const double PATIENCE_DRAIN = 0.3;
        public const double PATIENCE_FAR = 0.08;
        public const double PATIENCE_BACK = 0.25;
        public const double SOFT_RESET = 6.0;
        public const double SOFT_HEAL = 0.06;
        public const double HARD_HEAL = 0.15;
        public const double LORD_SLAM_EVERY = 5.0;
        public const double LORD_SLAM_R = 4.5;
        public const double LORD_SLAM_DMG = 1.4;
        public const double BUFF_TIME = 90.0;
        public const double BUFF_PASS_MIN = 30.0;
        public const double ARCANE_CDR = 1.3;
        public const double EMBER_DMG = 1.2;
        public const double LORD_TIME = 120.0;
        public const double LORD_DMG = 1.15;
        public const double LORD_MINION = 1.4;
        public const double SUPER_MINION = 1.5;
        public const double LORD_SIEGE = 3.0;
        public const double LORDLING_HP = 12.0;
        public const double LORDLING_DMG = 1.4;
        public static readonly Dictionary<string, string> BUFF_NAMES = new Dictionary<string, string>
            { { "arcane", "ARCANE" }, { "ember", "EMBER" }, { "lord", "LORD'S BLESSING" } };
        public static readonly Vec2 WYRM_P = new Vec2(Land.POOL_X, 0.0);
        public const double WYRM_FIRST = 180.0;
        public const double WYRM_BACK = 180.0;
        public const double WYRM_HIDE = 0.06;
        public const int WYRM_STACKS = 4;
        public const double WYRM_BREATH_EVERY = 6.0;
        public const double WYRM_BREATH_R = 6.5;
        public const double WYRM_BREATH_ARC = 0.6;
        public const double WYRM_BREATH_DMG = 1.0;
        public const double WYRM_LEASH = 12.0;
        public const int WYRM_GATHER = 3;

        public static readonly string[] BOT_NAMES = { "Alfred", "Bertram", "Cedric", "Dorian", "Edmund", "Felix", "Gideon", "Harold", "Ivo", "Jasper",
            "Kendrick", "Leopold", "Magnus", "Nigel", "Osric", "Percival", "Quentin", "Roland", "Sigmund", "Tobias", "Ulric",
            "Victor", "Wendell", "Yorick", "Ada", "Beatrix", "Clara", "Delia", "Edith", "Freya", "Greta", "Hilda", "Isolde",
            "Juno", "Lena", "Mira", "Nora", "Petra", "Rosa", "Sybil", "Tessa", "Vera", "Wren" };

        public const double BOT_RECALL_SAFE = 14.0;
        public const double GRID = 8.0;
        public const double GRID_PAD = 1.0;

        // 0.31.167: a side's five places
        public static readonly string[] POSTS = { "top", "jungle", "mid", "bot", "support" };
        public static readonly Dictionary<string, int> POST_LANE = new Dictionary<string, int>
            { { "top", 0 }, { "jungle", JUNGLE }, { "mid", 1 }, { "bot", 2 }, { "support", 2 } };
        public static readonly Dictionary<string, string[]> POST_ROLES = new Dictionary<string, string[]>
        {
            { "top", new[] { "fighter", "tank" } }, { "jungle", new[] { "assassin", "fighter" } }, { "mid", new[] { "mage", "assassin" } },
            { "bot", new[] { "marksman" } }, { "support", new[] { "support", "tank" } },
        };
        public static readonly Dictionary<string, string> ROLE_POST = new Dictionary<string, string>
        {
            { "tank", "top" }, { "fighter", "top" }, { "assassin", "jungle" }, { "mage", "mid" }, { "marksman", "bot" }, { "support", "support" },
        };
    }

    public sealed class Tower
    {
        public int id, team, lane, tier;
        public Vec2 p;
        public double hp, max_hp;
        public bool dead;
        public string target = "";
        public int ramp;
        public string ramp_id = "";
        public double next;
        public double ramp_at = -99.0;
        public int plates;
    }

    public sealed class KingSt
    {
        public double hp, max_hp, next, quiet;
        public bool dead;
    }

    public sealed class Camp
    {
        public int id, side;
        public string kind;
        public Vec2 p;
        public List<string> mobs = new List<string>();
        public bool alive;
        public double next;
        public string target = "";
        public ODict<string, double> hits = new ODict<string, double>();
        public double slam, patience = 1.0, reset_at;
        public string reset = "";
    }

    public sealed class Rain
    {
        public int team, left;
        public string owner;
        public Vec2 at;
        public double r, next, dmg;
    }

    public sealed class TowerShot
    {
        public int tw;
        public string target;
        public double t, dmg;
    }

    public sealed class AimSt
    {
        public Vec2 p;
        public double d, score;
    }
}
