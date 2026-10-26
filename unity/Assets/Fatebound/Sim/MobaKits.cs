// KITS AND ROLES (moba_kits.gd, 0.31.167/168/217): League's six roles; every hero's W and E (and the six new heroes'
// Q and R); the effects they're built from and what they leave on units -- shields, slows and hastes, quicker swings,
// damage taken up, lifesteal, empowered or poisoned basic attacks, damage over time, a parry -- zones, traps, dashes.
using System;
using System.Collections.Generic;

namespace Fatebound.Sim
{
    /// <summary>A W/E (or a new hero's Q/R): id (the effect), name, short (the button), text, hold, and its numbers.</summary>
    public sealed class KitSpec
    {
        public string id, name, shortName, text;
        public bool hold;
        public Dictionary<string, double> n = new Dictionary<string, double>();
        public bool HasId => id != null;
        public string Short => shortName ?? name;
        public double this[string key] => n[key];
        public double N(string key, double dflt) => n.TryGetValue(key, out var v) ? v : dflt;
        public bool Has(string key) => n.ContainsKey(key);
    }

    public sealed class Zone
    {
        public int zid, team;
        public string spell, owner;
        public Vec2 at;
        public double r, until, next;
        public double dmg, slow, heal, stun;
        public bool hasPush;
        public double push;
        public bool hasDelay;
        public double delay_at;
        public bool hasStrike;
        public double strikeDmg, strikeStun, every, next_at;
    }

    public sealed class Trap
    {
        public int id, team;
        public string owner;
        public Vec2 at;
        public double armed_at, until, r, dmg, stun;
    }

    public sealed class MobaKits
    {
        public static readonly string[] ROLE_ORDER = { "tank", "fighter", "assassin", "mage", "marksman", "support" };
        public static readonly Dictionary<string, string> ROLE_NAMES = new Dictionary<string, string>
        {
            { "tank", "TANK" }, { "fighter", "FIGHTER" }, { "assassin", "ASSASSIN" }, { "mage", "MAGE" }, { "marksman", "MARKSMAN" },
            { "support", "SUPPORT" },
        };
        public static readonly Dictionary<string, string> ROLE_TEXT = new Dictionary<string, string>
        {
            { "tank", "Takes the hits and holds the line." }, { "fighter", "Fights up close and keeps going." },
            { "assassin", "Gets in, takes out a hero, gets out." }, { "mage", "Spells from range: big damage, control." },
            { "marksman", "Steady damage from range; carries late." }, { "support", "Heals, shields and sets up the team." },
        };
        public static readonly Dictionary<string, string> ROLE_OF = new Dictionary<string, string>
        {
            { "knight", "tank" }, { "crusader", "tank" }, { "barbarian", "fighter" }, { "berserker", "fighter" }, { "rogue", "assassin" },
            { "assassin", "assassin" }, { "ranger", "marksman" }, { "sniper", "marksman" }, { "mage", "mage" }, { "archmage", "mage" },
            { "priest", "support" }, { "necromancer", "support" },
            { "golem", "tank" }, { "dragoon", "fighter" }, { "duelist", "assassin" }, { "stormcaller", "mage" }, { "musketeer", "marksman" },
            { "druid", "support" },
        };
        public static readonly Dictionary<string, int> UNLOCK = new Dictionary<string, int> { { "q", 1 }, { "w", 2 }, { "e", 3 } };
        public static readonly Dictionary<string, string> TAG_OF = new Dictionary<string, string>
        {
            { "block", "DEFENSE" }, { "spin", "DAMAGE" }, { "lunge", "MOBILITY" }, { "volley", "DAMAGE" }, { "nova", "DAMAGE" }, { "sanctuary", "HEAL" },
            { "hammer", "DAMAGE" }, { "whirlwind", "DAMAGE" }, { "vanish", "STEALTH" }, { "pierce", "DAMAGE" }, { "meteor", "DAMAGE" },
            { "resurrect", "REVIVE" }, { "barkskin", "DEFENSE" }, { "bash", "CONTROL" }, { "blink", "MOBILITY" }, { "bloodlust", "ENHANCE" },
            { "boneshield", "DEFENSE" }, { "boulder", "CONTROL" }, { "buckshot", "DAMAGE" }, { "caltrops", "CONTROL" }, { "chain", "CONTROL" },
            { "challenge", "CONTROL" }, { "charge", "MOBILITY" }, { "consecrate", "DAMAGE" }, { "curse", "DEBUFF" }, { "dazzle", "CONTROL" },
            { "dragondive", "MOBILITY" }, { "entangle", "CONTROL" }, { "feint", "MOBILITY" }, { "frenzy", "ENHANCE" }, { "gust", "CONTROL" },
            { "holylight", "HEAL" }, { "impale", "DAMAGE" }, { "keg", "DAMAGE" }, { "knives", "DAMAGE" }, { "landslide", "CONTROL" }, { "leap", "MOBILITY" },
            { "manashield", "DEFENSE" }, { "mark", "DEBUFF" }, { "missiles", "DAMAGE" }, { "pillar", "CONTROL" }, { "poison", "ENHANCE" },
            { "quake", "CONTROL" }, { "quickdraw", "ENHANCE" }, { "rally", "DEFENSE" }, { "rejuv", "HEAL" }, { "riposte", "DEFENSE" },
            { "shadowstep", "MOBILITY" }, { "smokeroll", "MOBILITY" }, { "snare", "CONTROL" }, { "static", "DAMAGE" }, { "stoneskin", "DEFENSE" },
            { "sweep", "DAMAGE" }, { "thrust", "DAMAGE" }, { "thunderstorm", "DAMAGE" }, { "trap", "CONTROL" }, { "tumble", "MOBILITY" },
            { "vault", "MOBILITY" }, { "wildgrowth", "HEAL" },
        };

        public static string Tag(string hid, string slot, string class_ability = "")
        {
            if (slot == "r") return "ULTIMATE";
            KitSpec k = Kit(hid, slot);
            string id = k != null && k.id != null ? k.id : (slot == "q" ? class_ability : "");
            return TAG_OF.TryGetValue(id ?? "", out var t) ? t : "SKILL";
        }

        static KitSpec K(string id, string name, string text, string shortName = null, bool hold = false, params (string, double)[] nums)
        {
            var k = new KitSpec { id = id, name = name, text = text, shortName = shortName, hold = hold };
            foreach (var (key, v) in nums) k.n[key] = v;
            return k;
        }
        static KitSpec Q(string name, string text) => new KitSpec { name = name, text = text };
        static KitSpec R(string id, params (string, double)[] nums) => K(id, null, null, null, false, nums);

        public static readonly Dictionary<string, Dictionary<string, KitSpec>> KITS = new Dictionary<string, Dictionary<string, KitSpec>>
        {
            { "knight", new Dictionary<string, KitSpec> {
                { "q", Q("SHIELD", "Hold: your shield blocks everything from the front.") },
                { "w", K("bash", "SHIELD BASH", "Charge 5 m behind your shield; the first enemy you hit is stunned for 1 s.", "BASH", false, ("cd", 10.0), ("dist", 5.0), ("dmg", 1.0), ("stun", 1.0)) },
                { "e", K("rally", "RALLY", "You and every ally hero near: a shield worth 15 % of your health for 4 s.", null, false, ("cd", 16.0), ("r", 7.0), ("shield", 0.15), ("dur", 4.0)) } } },
            { "crusader", new Dictionary<string, KitSpec> {
                { "q", Q("HAMMER", "Throws his hammer through a line; it comes back.") },
                { "w", K("block", "SHIELD", "Hold: your shield blocks everything from the front.", "BLOCK", true, ("cd", 0.0)) },
                { "e", K("consecrate", "CONSECRATE", "Holy ground round you for 4 s: enemies on it slowed and burnt, allies healed.", "HOLY", false, ("cd", 14.0), ("r", 4.0), ("dur", 4.0), ("dmg", 0.25), ("slow", 0.3), ("heal", 0.015)) } } },
            { "barbarian", new Dictionary<string, KitSpec> {
                { "q", Q("SPIN", "A spinning swing that hits everyone round you.") },
                { "w", K("leap", "LEAP", "Leap onto an enemy hero up to 8 m away (or ahead) and slam: damage and a slow round you.", null, false, ("cd", 11.0), ("range", 8.0), ("r", 2.5), ("dmg", 1.2), ("slow", 0.3), ("dur", 1.5)) },
                { "e", K("bloodlust", "BLOODLUST", "5 s: your hits heal you for 30 % of their damage, and you're 15 % quicker.", "RAGE", false, ("cd", 15.0), ("ls", 0.3), ("haste", 0.15), ("dur", 5.0)) } } },
            { "berserker", new Dictionary<string, KitSpec> {
                { "q", Q("WHIRLWIND", "A whirlwind that keeps moving.") },
                { "w", K("charge", "RECKLESS CHARGE", "Charge 7 m through them, hitting everyone you pass.", "CHARGE", false, ("cd", 10.0), ("dist", 7.0), ("dmg", 0.8)) },
                { "e", K("frenzy", "FRENZY", "Heal 12 % of your health and swing 35 % quicker for 4 s.", null, false, ("cd", 16.0), ("heal", 0.12), ("as", 0.35), ("dur", 4.0)) } } },
            { "rogue", new Dictionary<string, KitSpec> {
                { "q", Q("LUNGE", "Lunges in, quick and sharp.") },
                { "w", K("caltrops", "CALTROPS", "Scatter caltrops round an enemy hero up to 8 m away: slowed and cut while on them, 4 s.", null, false, ("cd", 12.0), ("range", 8.0), ("r", 3.0), ("dur", 4.0), ("dmg", 0.2), ("slow", 0.4)) },
                { "e", K("poison", "POISON BLADES", "Your next 3 hits poison: a quarter of your damage a second for 4 s.", "POISON", false, ("cd", 10.0), ("n", 3), ("dps", 0.25), ("dur", 4.0)) } } },
            { "assassin", new Dictionary<string, KitSpec> {
                { "q", Q("VANISH", "Vanishes, then strikes twice as hard.") },
                { "w", K("shadowstep", "SHADOW STEP", "Step out of the shadows behind an enemy hero up to 8 m away and strike.", "STEP", false, ("cd", 10.0), ("range", 8.0), ("dmg", 1.5)) },
                { "e", K("knives", "FAN OF KNIVES", "Knives in a fan ahead of you: damage, and a slow for 2 s.", "KNIVES", false, ("cd", 8.0), ("r", 5.5), ("arc", 0.7), ("dmg", 1.0), ("slow", 0.25), ("dur", 2.0)) } } },
            { "ranger", new Dictionary<string, KitSpec> {
                { "q", Q("VOLLEY", "Five arrows in a fan.") },
                { "w", K("tumble", "TUMBLE", "Roll 4.5 m; your next shot within 3 s hits 60 % harder.", null, false, ("cd", 8.0), ("dist", 4.5), ("emp", 0.6), ("dur", 3.0)) },
                { "e", K("snare", "SNARE ARROW", "An arrow that roots the first enemy it hits for 1.2 s.", "SNARE", false, ("cd", 12.0), ("range", 12.0), ("dmg", 0.8), ("stun", 1.2)) } } },
            { "sniper", new Dictionary<string, KitSpec> {
                { "q", Q("PIERCE", "A piercing shot through everyone in a line.") },
                { "w", K("trap", "BEAR TRAP", "Set a trap at your feet (two at most): the first enemy on it is caught for 1.5 s and seen.", "TRAP", false, ("cd", 14.0), ("n", 2), ("life", 40.0), ("arm", 0.8), ("r", 1.0), ("dmg", 0.8), ("stun", 1.5)) },
                { "e", K("mark", "HUNTER'S MARK", "Mark an enemy hero up to 13 m away: seen, and takes 20 % more damage for 5 s.", "MARK", false, ("cd", 14.0), ("range", 13.0), ("amp", 0.2), ("dur", 5.0)) } } },
            { "mage", new Dictionary<string, KitSpec> {
                { "q", Q("NOVA", "A blast of fire all round her.") },
                { "w", K("pillar", "FIRE PILLAR", "Fire erupts under an enemy up to 10 m away after a moment: heavy damage and a 1 s stun.", "PILLAR", false, ("cd", 10.0), ("range", 10.0), ("r", 2.5), ("delay", 0.7), ("dmg", 1.6), ("stun", 1.0)) },
                { "e", K("blink", "BLINK", "Vanish and appear 6 m away, the way you're going.", null, false, ("cd", 14.0), ("dist", 6.0)) } } },
            { "archmage", new Dictionary<string, KitSpec> {
                { "q", Q("METEOR", "Calls down a meteor.") },
                { "w", K("missiles", "ARCANE MISSILES", "Three bolts at up to three enemies near (heroes first).", "MISSILE", false, ("cd", 8.0), ("range", 10.0), ("n", 3), ("dmg", 0.9)) },
                { "e", K("manashield", "MANA SHIELD", "A shield worth 25 % of your health for 4 s.", "SHIELD", false, ("cd", 16.0), ("shield", 0.25), ("dur", 4.0)) } } },
            { "priest", new Dictionary<string, KitSpec> {
                { "q", Q("SANCTUARY", "Heals every ally near.") },
                { "w", K("holylight", "HOLY LIGHT", "Heal the most hurt ally hero near you (or you) by 22 % of their health, and free them of slows.", "LIGHT", false, ("cd", 10.0), ("range", 10.0), ("heal", 0.22)) },
                { "e", K("dazzle", "DAZZLE", "A flash of light: every enemy round you stunned for 0.9 s.", null, false, ("cd", 14.0), ("r", 4.5), ("stun", 0.9)) } } },
            { "necromancer", new Dictionary<string, KitSpec> {
                { "q", Q("RESURRECT", "Brings a fallen ally back where he fell.") },
                { "w", K("boneshield", "BONE SHIELD", "Bones wrap the most hurt ally hero near you (or you): a shield of 20 % of their health, 4 s.", "BONES", false, ("cd", 12.0), ("range", 10.0), ("shield", 0.2), ("dur", 4.0)) },
                { "e", K("curse", "CURSE", "Curse an enemy hero up to 10 m away: slowed 35 % and takes 15 % more damage for 4 s.", null, false, ("cd", 13.0), ("range", 10.0), ("slow", 0.35), ("amp", 0.15), ("dur", 4.0)) } } },
            { "golem", new Dictionary<string, KitSpec> {
                { "q", K("boulder", "BOULDER", "Hurl a boulder: the first enemy it hits takes heavy damage and is stunned for 1 s.", null, false, ("cd", 9.0), ("range", 11.0), ("dmg", 1.2), ("stun", 1.0)) },
                { "w", K("stoneskin", "STONESKIN", "Your skin turns to stone for 4 s: you take 40 % less damage, and slows fall off you.", "STONE", false, ("cd", 15.0), ("dr", 0.4), ("dur", 4.0)) },
                { "e", K("quake", "QUAKE", "Stamp the ground: everyone round you hurt and slowed 40 % for 2 s.", null, false, ("cd", 11.0), ("r", 4.0), ("dmg", 0.9), ("slow", 0.4), ("dur", 2.0)) },
                { "r", R("landslide", ("dist", 9.0), ("dmg", 1.2), ("r", 4.0), ("land", 1.6), ("stun", 1.5)) } } },
            { "dragoon", new Dictionary<string, KitSpec> {
                { "q", K("sweep", "SWEEP", "A wide sweep of the halberd ahead: damage, and you heal 5 % of your health for each hero hit.", null, false, ("cd", 7.0), ("r", 3.8), ("arc", 1.05), ("dmg", 1.3), ("heal", 0.05)) },
                { "w", K("impale", "IMPALE", "Thrust 6 m ahead: everyone in the line hurt, dragged 3 m toward you and slowed.", null, false, ("cd", 11.0), ("len", 6.0), ("w", 1.0), ("dmg", 1.0), ("pull", 3.0), ("slow", 0.3), ("dur", 1.5)) },
                { "e", K("vault", "VAULT", "Pole-vault 6 m; your next strike within 3 s hits 60 % harder.", null, false, ("cd", 12.0), ("dist", 6.0), ("emp", 0.6), ("dur", 3.0)) },
                { "r", R("dragondive", ("range", 11.0), ("r", 3.5), ("dmg", 2.2), ("stun", 1.0)) } } },
            { "duelist", new Dictionary<string, KitSpec> {
                { "q", K("thrust", "LUNGE", "Lunge 5 m: the first enemy you meet takes a hard thrust -- a hero, and it's back twice as soon.", null, false, ("cd", 5.0), ("dist", 5.0), ("dmg", 1.4), ("refund", 0.5)) },
                { "w", K("riposte", "RIPOSTE", "Parry for 1 s: nothing hurts you. If anything struck, you answer the nearest enemy: a heavy thrust and a 0.8 s stun.", null, false, ("cd", 12.0), ("dur", 1.0), ("r", 3.5), ("dmg", 1.8), ("stun", 0.8)) },
                { "e", K("feint", "FEINT", "Spring back 3.5 m and vanish for 1.5 s: your first strike out of it hits twice as hard.", null, false, ("cd", 11.0), ("dist", 3.5), ("hide", 1.5)) },
                { "r", R("challenge", ("range", 8.0), ("n", 5), ("dmg", 0.8), ("missing", 0.06)) } } },
            { "stormcaller", new Dictionary<string, KitSpec> {
                { "q", K("chain", "CHAIN LIGHTNING", "Lightning strikes the nearest enemy and leaps to three more near him, each a little weaker.", "CHAIN", false, ("cd", 7.0), ("range", 10.0), ("jump", 4.5), ("n", 4), ("dmg", 1.3), ("fall", 0.75)) },
                { "w", K("static", "STATIC FIELD", "A crackling field up to 9 m away for 3 s: enemies in it shocked and slowed 30 %.", "STATIC", false, ("cd", 12.0), ("range", 9.0), ("r", 3.0), ("dur", 3.0), ("dmg", 0.35), ("slow", 0.3)) },
                { "e", K("gust", "GUST", "A blast of wind ahead: enemies blown back 4 m and slowed.", null, false, ("cd", 12.0), ("r", 5.0), ("arc", 0.8), ("push", 4.0), ("dmg", 0.5), ("slow", 0.3), ("dur", 1.5)) },
                { "r", R("thunderstorm", ("range", 13.0), ("r", 5.0), ("n", 8), ("every", 0.45), ("dmg", 1.1), ("stun", 0.35)) } } },
            { "musketeer", new Dictionary<string, KitSpec> {
                { "q", K("buckshot", "BUCKSHOT", "A spread of shot ahead: damage and a shove -- close up it hits much harder.", "BUCK", false, ("cd", 7.0), ("r", 7.0), ("arc", 0.45), ("dmg", 1.3), ("close", 1.6), ("push", 1.5)) },
                { "w", K("keg", "POWDER KEG", "Lob a lit keg up to 9 m: a moment later it bursts, hurting and throwing back everyone round it.", "KEG", false, ("cd", 11.0), ("range", 9.0), ("r", 3.0), ("delay", 0.8), ("dmg", 1.5), ("push", 2.5)) },
                { "e", K("smokeroll", "SMOKE ROLL", "Roll 4.5 m out of a cloud of smoke that slows enemies in it; your next shot within 3 s hits 60 % harder.", "ROLL", false, ("cd", 10.0), ("dist", 4.5), ("r", 3.0), ("zdur", 3.0), ("slow", 0.3), ("emp", 0.6), ("dur", 3.0)) },
                { "r", R("quickdraw", ("range", 15.0), ("n", 5), ("dmg", 2.0), ("missing", 0.12)) } } },
            { "druid", new Dictionary<string, KitSpec> {
                { "q", K("rejuv", "REJUVENATE", "The most hurt ally hero near you (or you) heals 6 % of their health a second for 5 s.", "REJUV", false, ("cd", 8.0), ("range", 10.0), ("hps", 0.06), ("dur", 5.0)) },
                { "w", K("entangle", "ENTANGLE", "Roots burst up under an enemy up to 10 m away: hurt and held fast for 1.5 s.", "ROOTS", false, ("cd", 12.0), ("range", 10.0), ("r", 1.8), ("delay", 0.5), ("dmg", 0.8), ("stun", 1.5)) },
                { "e", K("barkskin", "BARKSKIN", "Bark covers the most hurt ally hero near you (or you): 30 % less damage for 4 s.", "BARK", false, ("cd", 14.0), ("range", 10.0), ("dr", 0.3), ("dur", 4.0)) },
                { "r", R("wildgrowth", ("r", 7.0), ("dur", 5.0), ("heal", 0.025), ("slow", 0.3), ("dmg", 0.15)) } } },
        };

        public const double DASH_SPEED = 17.0;
        public const double SHIELD_CAP = 0.6;
        public const double ZONE_EVERY = 0.5;

        public Moba m;
        public SiegeSim s;
        public List<Zone> zones = new List<Zone>();
        public List<Trap> traps = new List<Trap>();
        int _trap_id = 0;
        int _zone_id = 0;
        readonly ODict<string, bool> _afflicted = new ODict<string, bool>();
        readonly ODict<string, bool> _riposting = new ODict<string, bool>();

        public void Setup(Moba moba)
        {
            m = moba;
            s = moba.s;
        }

        // ---------- what the rest reads ----------
        public static string RoleOf(string hid) => ROLE_OF.TryGetValue(hid ?? "", out var r) ? r : "";

        public static KitSpec Kit(string hid, string slot)
        {
            if (hid != null && KITS.TryGetValue(hid, out var k) && k.TryGetValue(slot, out var spec)) return spec;
            return null;
        }

        public static string KitQ(string hid)
        {
            var k = Kit(hid, "q");
            return k != null && k.id != null ? k.id : "";
        }

        public static string CdKey(string slot) => slot == "q" ? "cd_ability" : "cd_" + slot;

        public static double Cd(Unit u, string slot) => slot == "q" ? u.cd_ability : (slot == "w" ? u.cd_w : (slot == "e" ? u.cd_e : 0.0));

        static void SetCd(Unit u, string slot, double v)
        {
            if (slot == "q") u.cd_ability = v;
            else if (slot == "w") u.cd_w = v;
            else if (slot == "e") u.cd_e = v;
        }

        public bool Unlocked(Unit u, string slot) => m != null ? m.Rank(u, slot) > 0 : u.level >= (UNLOCK.TryGetValue(slot, out var l) ? l : 1);

        public bool CanCast(Unit u, string slot)
        {
            var k = Kit(u.hid, slot);
            return k != null && u.hero && s.Alive(u) && Unlocked(u, slot) && Cd(u, slot) <= 0.0;
        }

        public double SpeedMult(Unit u)
        {
            double t = s.time;
            double k = 1.0;
            if (t < u.slow_until) k *= 1.0 - u.slow_k;
            if (t < u.haste_until) k *= 1.0 + u.haste_k;
            return k;
        }

        public double SwingMult(Unit u) => s.time < u.as_until ? 1.0 / (1.0 + u.as_k) : 1.0;

        public double LifestealAdd(Unit u) => s.time < u.ls_until ? u.ls_k : 0.0;

        public double Taken(Unit src, Unit dst, double a)
        {
            double t = s.time;
            if (t < dst.parry_until)
            {
                if (dst.riposte != null && a > 0.0 && (src != null ? src.team : -1) != dst.team) dst.riposte.hit = true;
                return 0.0;
            }
            if (t < dst.amp_until) a *= 1.0 + dst.amp_k;
            if (a > 0.0 && dst.shield > 0.0)
            {
                if (t >= dst.shield_until) dst.shield = 0.0;
                else
                {
                    double took = GD.Min(dst.shield, a);
                    dst.shield = dst.shield - took;
                    a -= took;
                }
            }
            return a;
        }

        public void Clear(Unit u)
        {
            u.Erase("shield"); u.Erase("shield_until"); u.Erase("slow_until"); u.Erase("haste_until"); u.Erase("amp_until");
            u.Erase("as_until"); u.Erase("ls_until"); u.Erase("emp_n"); u.Erase("poison_n"); u.Erase("parry_until");
            u.dots = null; u.dash = null; u.riposte = null; u.Erase("unstop_until");
            _afflicted.Erase(u.id ?? "");
            _riposting.Erase(u.id ?? "");
        }

        // ---------- casting ----------
        public bool Spell(Unit u, string slot)
        {
            var k = Kit(u.hid, slot);
            if (k == null || k.id == null || k.hold || slot == "r") return false;
            if (!CanCast(u, slot) || !s.CanAct(u) || u.dance != null) return false;
            var ev = new Ev { ["id"] = u.id, ["team"] = u.team, ["hid"] = u.hid, ["slot"] = slot, ["spell"] = k.id, ["pos"] = u.pos };
            SetCd(u, slot, k["cd"] * m.RankCd(u, slot));
            _pk = m.RankPower(u, slot);
            if (!Cast(u, k, ev))
            {
                SetCd(u, slot, 0.0);
                return false;
            }
            s.Emit("spell", ev);
            return true;
        }

        double _pk = 1.0;

        bool Cast(Unit u, KitSpec k, Ev ev)
        {
            double dmg = s.Stat(u, SK.dmg) * _pk;
            double mhp = u.max_hp * _pk;
            switch (k.id)
            {
                case "bash":
                    DoDash(u, MoveDir(u), k["dist"], new Dash { dmg = dmg * k["dmg"], stun = k["stun"], first = true });
                    break;
                case "rally":
                {
                    var ids = new List<object>();
                    foreach (var o in AlliesNear(u, k["r"], true))
                    {
                        Shield(o, mhp * k["shield"], k["dur"]);
                        ids.Add(o.id);
                    }
                    ev["ids"] = ids;
                    ev["r"] = k["r"];
                    break;
                }
                case "consecrate":
                    MakeZone(u, k.id, u.pos, k["r"], k["dur"], new Zone { dmg = dmg * k["dmg"], slow = k["slow"], heal = k["heal"] });
                    ev["r"] = k["r"];
                    break;
                case "leap":
                {
                    Vec2 to = Aim(u, k["range"], 6.0);
                    ev["to"] = to;
                    DoDash(u, to.DistanceTo(u.pos) > 0.3 ? (to - u.pos).Normalized() : SiegeSim.DirOf(u.face),
                        GD.Min(k["range"], to.DistanceTo(u.pos)), new Dash { land = new LandFx { r = k["r"], dmg = dmg * k["dmg"],
                            slow = k["slow"], dur = k["dur"] }, leap = true }, 15.0);
                    break;
                }
                case "bloodlust":
                    u.ls_k = k["ls"];
                    u.ls_until = s.time + k["dur"];
                    Haste(u, k["haste"], k["dur"]);
                    break;
                case "charge":
                    DoDash(u, MoveDir(u), k["dist"], new Dash { dmg = dmg * k["dmg"], through = true }, 19.0);
                    break;
                case "frenzy":
                    s.Heal(u, u, mhp * k["heal"]);
                    u.as_k = k["as"];
                    u.as_until = s.time + k["dur"];
                    break;
                case "caltrops":
                {
                    Vec2 at = Aim(u, k["range"], 4.0);
                    MakeZone(u, k.id, at, k["r"], k["dur"], new Zone { dmg = dmg * k["dmg"], slow = k["slow"] });
                    ev["c"] = at;
                    ev["r"] = k["r"];
                    break;
                }
                case "poison":
                    u.poison_n = (int)k["n"];
                    u.poison_k = k["dps"];
                    u.poison_dur = k["dur"];
                    break;
                case "shadowstep":
                {
                    Unit tgt = HeroNear(u, k["range"]);
                    if (tgt == null) return false;
                    Vec2 behind = tgt.pos - SiegeSim.DirOf(tgt.face) * 1.1;
                    ev["from"] = u.pos;
                    u.pos = s.ClampToField(s.PushOut(behind, SiegeSim.UNIT_R, u.team));
                    u.face = SiegeSim.AngleOf(tgt.pos - u.pos);
                    s._next_push = s.PushFrom(u.pos, tgt.pos, 4.0, 1.6);
                    s.Damage(u, tgt, dmg * k["dmg"]);
                    ev["to"] = u.pos;
                    ev["target"] = tgt.id;
                    break;
                }
                case "knives":
                {
                    Vec2 d = FaceFoe(u, k["r"]);
                    int n = 0;
                    foreach (var o in EnemiesNear(u, u.pos, k["r"]))
                    {
                        Vec2 off = o.pos - u.pos;
                        if (off.Length() < 0.8 || Math.Abs(d.AngleTo(off)) <= k["arc"])
                        {
                            s.Damage(u, o, dmg * k["dmg"]);
                            Slow(o, k["slow"], k["dur"], u);
                            n += 1;
                        }
                    }
                    n += m.AbilityKing(u, dmg * k["dmg"], u.pos, k["r"], d, Math.Cos(k["arc"]));
                    ev["dir"] = d;
                    ev["r"] = k["r"];
                    ev["n"] = n;
                    break;
                }
                case "tumble":
                    DoDash(u, MoveDir(u), k["dist"], new Dash(), 18.0);
                    u.emp_n = 1;
                    u.emp_k = k["emp"];
                    u.emp_until = s.time + k["dur"] + 0.4;
                    break;
                case "snare":
                {
                    Vec2 aim = Aim(u, k["range"], k["range"]);
                    u.face = SiegeSim.AngleOf(aim - u.pos);
                    Shot(u, "arrow", SiegeSim.DirOf(u.face), 26.0, k["range"], dmg * k["dmg"], new Proj { stun = k["stun"], spell = "snare" });
                    break;
                }
                case "trap":
                {
                    var mine = traps.FindAll(tr => tr.owner == u.id);
                    if (mine.Count >= (int)k["n"])
                    {
                        traps.Remove(mine[0]);
                        s.Emit("trap_gone", "trap", mine[0].id);
                    }
                    _trap_id += 1;
                    traps.Add(new Trap { id = _trap_id, team = u.team, owner = u.id, at = u.pos, armed_at = s.time + k["arm"],
                        until = s.time + k["life"], r = k["r"], dmg = dmg * k["dmg"], stun = k["stun"] });
                    ev["trap"] = _trap_id;
                    break;
                }
                case "mark":
                {
                    Unit tgt2 = HeroNear(u, k["range"]);
                    if (tgt2 == null) return false;
                    Amp(tgt2, k["amp"], k["dur"]);
                    for (int i = 0; i < 3; i++) m.vision.Reveal(tgt2);
                    tgt2.rev_until = GD.Max(tgt2.rev_until, s.time + k["dur"]);
                    ev["target"] = tgt2.id;
                    break;
                }
                case "pillar":
                {
                    Vec2 at2 = Aim(u, k["range"], 7.0);
                    MakeZone(u, k.id, at2, k["r"], 0.0, new Zone { dmg = dmg * k["dmg"], stun = k["stun"], hasDelay = true, delay_at = s.time + k["delay"] });
                    u.face = SiegeSim.AngleOf(at2 - u.pos);
                    ev["c"] = at2;
                    ev["r"] = k["r"];
                    ev["delay"] = k["delay"];
                    break;
                }
                case "blink":
                {
                    Vec2 to2 = u.pos + MoveDir(u) * k["dist"];
                    ev["from"] = u.pos;
                    u.pos = s.ClampToField(s.PushOut(to2, SiegeSim.UNIT_R, u.team));
                    ev["to"] = u.pos;
                    break;
                }
                case "missiles":
                {
                    var pool = EnemiesNear(u, u.pos, k["range"]);
                    Vec2 me_p = u.pos;
                    GSort.Sort(pool, (a, b) => FoeKey(a, me_p) < FoeKey(b, me_p));
                    int n2 = 0;
                    foreach (var o in pool)
                    {
                        if (n2 >= (int)k["n"]) break;
                        Vec2 dd = (o.pos - me_p).Normalized();
                        Shot(u, "fire", dd, 22.0, k["range"] + 2.0, dmg * k["dmg"], new Proj { spell = "missiles" });
                        n2 += 1;
                    }
                    if (n2 == 0) return false;
                    break;
                }
                case "manashield":
                    Shield(u, mhp * k["shield"], k["dur"]);
                    break;
                case "holylight":
                {
                    Unit who = MostHurt(u, k["range"]);
                    s.Heal(u, who, who.max_hp * k["heal"]);
                    who.Erase("slow_until");
                    ev["target"] = who.id;
                    break;
                }
                case "dazzle":
                {
                    int n3 = 0;
                    foreach (var o in EnemiesNear(u, u.pos, k["r"]))
                    {
                        o.stun = GD.Max(o.stun, k["stun"]);
                        m.NoteCc(u, o);
                        n3 += 1;
                    }
                    ev["r"] = k["r"];
                    ev["n"] = n3;
                    break;
                }
                case "boneshield":
                {
                    Unit who2 = MostHurt(u, k["range"]);
                    Shield(who2, who2.max_hp * k["shield"], k["dur"]);
                    ev["target"] = who2.id;
                    break;
                }
                case "curse":
                {
                    Unit tgt3 = HeroNear(u, k["range"]);
                    if (tgt3 == null) return false;
                    Slow(tgt3, k["slow"], k["dur"], u);
                    Amp(tgt3, k["amp"], k["dur"]);
                    ev["target"] = tgt3.id;
                    break;
                }
                // ---- 0.31.168: the six new heroes ----
                case "boulder":
                {
                    Vec2 aim3 = Aim(u, k["range"], k["range"]);
                    u.face = SiegeSim.AngleOf(aim3 - u.pos);
                    Shot(u, "boulder", SiegeSim.DirOf(u.face), 20.0, k["range"], dmg * k["dmg"], new Proj { stun = k["stun"], spell = "boulder" });
                    break;
                }
                case "stoneskin":
                    Dr(u, k["dr"], k["dur"]);
                    u.unstop_until = s.time + k["dur"];
                    u.Erase("slow_until");
                    break;
                case "quake":
                {
                    int n4 = 0;
                    foreach (var o in EnemiesNear(u, u.pos, k["r"]))
                    {
                        s._next_push = s.PushFrom(u.pos, o.pos, 3.0, 2.0);
                        s.Damage(u, o, dmg * k["dmg"]);
                        Slow(o, k["slow"], k["dur"], u);
                        n4 += 1;
                    }
                    n4 += m.AbilityKing(u, dmg * k["dmg"], u.pos, k["r"]);
                    ev["r"] = k["r"];
                    ev["n"] = n4;
                    break;
                }
                case "sweep":
                {
                    Vec2 d3 = FaceFoe(u, k["r"] + 1.0);
                    int heroes_hit = 0;
                    foreach (var o in EnemiesNear(u, u.pos, k["r"]))
                    {
                        Vec2 off3 = o.pos - u.pos;
                        if (off3.Length() < 0.8 || Math.Abs(d3.AngleTo(off3)) <= k["arc"])
                        {
                            s.Damage(u, o, dmg * k["dmg"]);
                            if (o.hero) heroes_hit += 1;
                        }
                    }
                    if (heroes_hit > 0) s.Heal(u, u, mhp * k["heal"] * (double)heroes_hit);
                    m.AbilityKing(u, dmg * k["dmg"], u.pos, k["r"], d3, Math.Cos(k["arc"]));
                    ev["dir"] = d3;
                    ev["r"] = k["r"];
                    break;
                }
                case "impale":
                {
                    Vec2 d4 = FaceFoe(u, k["len"]);
                    int hit_n = 0;
                    foreach (var o in EnemiesNear(u, u.pos, k["len"] + 0.5))
                    {
                        Vec2 off4 = o.pos - u.pos;
                        double along = off4.Dot(d4);
                        if (along < -0.3 || along > k["len"] || Math.Abs(off4.Cross(d4)) > k["w"] + SiegeSim.UNIT_R) continue;
                        s.Damage(u, o, dmg * k["dmg"]);
                        if (s.Alive(o) && o.mon < 0) s.Knockback(o, -d4 * GD.Min(k["pull"], GD.Max(0.0, along - 1.3)));
                        Slow(o, k["slow"], k["dur"], u);
                        hit_n += 1;
                    }
                    hit_n += m.AbilityKing(u, dmg * k["dmg"], u.pos, k["len"], d4, -2.0, k["w"]);
                    ev["dir"] = d4;
                    ev["len"] = k["len"];
                    ev["n"] = hit_n;
                    break;
                }
                case "vault":
                    DoDash(u, MoveDir(u), k["dist"], new Dash { leap = true }, 15.0);
                    u.emp_n = 1;
                    u.emp_k = k["emp"];
                    u.emp_until = s.time + k["dur"] + 0.4;
                    break;
                case "thrust":
                {
                    Vec2 d5 = FaceFoe(u, k["dist"] + 1.0);
                    DoDash(u, d5, k["dist"], new Dash { dmg = dmg * k["dmg"], first = true, refund = k["refund"] }, 20.0);
                    break;
                }
                case "riposte":
                    u.parry_until = s.time + k["dur"];
                    u.riposte = new Riposte { until = s.time + k["dur"], hit = false, r = k["r"], dmg = dmg * k["dmg"], stun = k["stun"] };
                    _riposting[u.id] = true;
                    break;
                case "feint":
                {
                    Vec2 back = -SiegeSim.DirOf(u.face);
                    if (u.move.Length() > 0.2) back = u.move.Normalized();
                    DoDash(u, back, k["dist"], new Dash(), 18.0);
                    u.face = SiegeSim.AngleOf(-back);
                    u.vanish_until = s.time + k["hide"];
                    s.Emit("vanish", "id", u.id, "team", u.team, "until", s.time + k["hide"]);
                    break;
                }
                case "chain":
                {
                    Unit first = HeroNear(u, k["range"]);
                    if (first == null) first = s.NearestEnemy(u, k["range"]);
                    if (first == null) return false;
                    u.face = SiegeSim.AngleOf(first.pos - u.pos);
                    var pts = new List<object> { u.pos };
                    var hit = new List<string> { first.id };
                    Unit cur = first;
                    double amt = dmg * k["dmg"];
                    for (int i = 0; i < (int)k["n"]; i++)
                    {
                        pts.Add(cur.pos);
                        s.Damage(u, cur, amt);
                        amt *= k["fall"];
                        Unit nxt = null;
                        double nd = k["jump"];
                        foreach (var o in EnemiesNear(u, cur.pos, k["jump"]))
                        {
                            if (hit.Contains(o.id)) continue;
                            double dd2 = o.pos.DistanceTo(cur.pos) - (o.hero ? 2.0 : 0.0);
                            if (dd2 < nd)
                            {
                                nd = dd2;
                                nxt = o;
                            }
                        }
                        if (nxt == null) break;
                        hit.Add(nxt.id);
                        cur = nxt;
                    }
                    ev["pts"] = pts;
                    break;
                }
                case "static":
                {
                    Vec2 at3 = Aim(u, k["range"], 6.0);
                    MakeZone(u, k.id, at3, k["r"], k["dur"], new Zone { dmg = dmg * k["dmg"], slow = k["slow"] });
                    u.face = SiegeSim.AngleOf(at3 - u.pos);
                    ev["c"] = at3;
                    ev["r"] = k["r"];
                    break;
                }
                case "gust":
                {
                    Vec2 d6 = FaceFoe(u, k["r"]);
                    foreach (var o in EnemiesNear(u, u.pos, k["r"]))
                    {
                        Vec2 off6 = o.pos - u.pos;
                        if (off6.Length() < 0.8 || Math.Abs(d6.AngleTo(off6)) <= k["arc"])
                        {
                            s.Damage(u, o, dmg * k["dmg"]);
                            if (s.Alive(o) && o.mon < 0) s.Knockback(o, (off6.Length() > 0.1 ? off6.Normalized() : d6) * k["push"]);
                            Slow(o, k["slow"], k["dur"], u);
                        }
                    }
                    m.AbilityKing(u, dmg * k["dmg"], u.pos, k["r"], d6, Math.Cos(k["arc"]));
                    ev["dir"] = d6;
                    ev["r"] = k["r"];
                    break;
                }
                case "buckshot":
                {
                    Vec2 d7 = FaceFoe(u, k["r"]);
                    foreach (var o in EnemiesNear(u, u.pos, k["r"]))
                    {
                        Vec2 off7 = o.pos - u.pos;
                        if (off7.Length() < 0.8 || Math.Abs(d7.AngleTo(off7)) <= k["arc"])
                        {
                            double close = GD.Clamp(1.0 - (off7.Length() - 1.5) / (k["r"] - 1.5), 0.0, 1.0);
                            s.Damage(u, o, dmg * k["dmg"] * GD.Lerp(1.0, k["close"], close));
                            if (s.Alive(o) && o.mon < 0) s.Knockback(o, (off7.Length() > 0.1 ? off7.Normalized() : d7) * k["push"]);
                        }
                    }
                    m.AbilityKing(u, dmg * k["dmg"], u.pos, k["r"], d7, Math.Cos(k["arc"]));
                    ev["dir"] = d7;
                    ev["r"] = k["r"];
                    break;
                }
                case "keg":
                {
                    Vec2 at4 = Aim(u, k["range"], 6.0);
                    MakeZone(u, k.id, at4, k["r"], 0.0, new Zone { dmg = dmg * k["dmg"], hasPush = true, push = k["push"], hasDelay = true,
                        delay_at = s.time + k["delay"] });
                    u.face = SiegeSim.AngleOf(at4 - u.pos);
                    ev["c"] = at4;
                    ev["r"] = k["r"];
                    ev["delay"] = k["delay"];
                    break;
                }
                case "smokeroll":
                    MakeZone(u, "smoke", u.pos, k["r"], k["zdur"], new Zone { slow = k["slow"] });
                    DoDash(u, AwayDir(u), k["dist"], new Dash(), 18.0);
                    u.emp_n = 1;
                    u.emp_k = k["emp"];
                    u.emp_until = s.time + k["dur"] + 0.4;
                    ev["r"] = k["r"];
                    break;
                case "rejuv":
                {
                    Unit who3 = MostHurt(u, k["range"]);
                    Dot(who3, u, who3.max_hp * k["hps"], k["dur"], true);
                    ev["target"] = who3.id;
                    break;
                }
                case "entangle":
                {
                    Unit tgt4 = HeroNear(u, k["range"]);
                    if (tgt4 == null) tgt4 = s.NearestEnemy(u, k["range"]);
                    if (tgt4 == null) return false;
                    MakeZone(u, k.id, tgt4.pos, k["r"], 0.0, new Zone { dmg = dmg * k["dmg"], stun = k["stun"], hasDelay = true,
                        delay_at = s.time + k["delay"], hasPush = true, push = 0.0 });
                    u.face = SiegeSim.AngleOf(tgt4.pos - u.pos);
                    ev["c"] = tgt4.pos;
                    ev["r"] = k["r"];
                    ev["delay"] = k["delay"];
                    break;
                }
                case "barkskin":
                {
                    Unit who4 = MostHurt(u, k["range"]);
                    Dr(who4, k["dr"], k["dur"]);
                    ev["target"] = who4.id;
                    break;
                }
                default:
                    return false;
            }
            return true;
        }

        // ---------- the six new heroes' ultimates (moba.Ult -> here) ----------
        public bool Ult(Unit u, double pk, double dmg, Ev ev)
        {
            var k = Kit(u.hid, "r");
            if (k == null) return false;
            ev["spell"] = k.id;
            switch (k.id)
            {
                case "landslide":
                {
                    Vec2 to = Aim(u, k["dist"], k["dist"]);
                    Vec2 dir = to.DistanceTo(u.pos) > 0.5 ? (to - u.pos).Normalized() : MoveDir(u);
                    DoDash(u, dir, k["dist"], new Dash { dmg = dmg * k["dmg"] * pk, through = true, land = new LandFx { r = k["r"],
                        dmg = dmg * k["land"] * pk, stun = k["stun"] } }, 16.0);
                    ev["dir"] = dir;
                    break;
                }
                case "dragondive":
                {
                    Unit tgt = HeroNear(u, k["range"]);
                    Vec2 to2 = tgt != null ? tgt.pos : Aim(u, k["range"], 8.0);
                    Vec2 off = to2 - u.pos;
                    DoDash(u, off.Length() > 0.3 ? off.Normalized() : SiegeSim.DirOf(u.face), GD.Min(k["range"], off.Length()),
                        new Dash { leap = true, land = new LandFx { r = k["r"], dmg = dmg * k["dmg"] * pk, stun = k["stun"] } }, 14.0);
                    ev["to"] = to2;
                    break;
                }
                case "challenge":
                {
                    Unit tgt2 = HeroNear(u, k["range"]);
                    if (tgt2 == null) return false;
                    var ids = new List<string>();
                    int nn = (int)k["n"] + (pk > 1.0 ? 1 : 0);
                    for (int i = 0; i < nn; i++) ids.Add(tgt2.id);
                    u.dance = new Dance { ids = ids, i = 0, next = s.time, dmg = dmg * k["dmg"] * pk, missing = k["missing"] };
                    ev["target"] = tgt2.id;
                    break;
                }
                case "thunderstorm":
                {
                    Vec2 c = Aim(u, k["range"], 8.0);
                    int n = (int)k["n"] + (pk > 1.0 ? 2 : 0);
                    MakeZone(u, k.id, c, k["r"], k["every"] * (double)n + 0.3, new Zone { hasStrike = true, strikeDmg = dmg * k["dmg"],
                        strikeStun = k["stun"], every = k["every"], next_at = s.time + 0.3 });
                    u.face = SiegeSim.AngleOf(c - u.pos);
                    ev["c"] = c;
                    ev["r"] = k["r"];
                    break;
                }
                case "quickdraw":
                {
                    var pool = new List<Unit>();
                    foreach (var o in m.UnitsNear(u.pos, k["range"]))
                        if (o.team != u.team && o.team <= 1 && s.Alive(o) && o.hero && m.CanSee(u.team, o) && o.pos.DistanceTo(u.pos) <= k["range"])
                            pool.Add(o);
                    if (pool.Count == 0) return false;
                    Vec2 me_p = u.pos;
                    GSort.Sort(pool, (a, b) => a.pos.DistanceTo(me_p) < b.pos.DistanceTo(me_p));
                    var ids2 = new List<object>();
                    var pts = new List<object>();
                    int take = Math.Min(pool.Count, (int)k["n"]);
                    for (int i = 0; i < take; i++)
                    {
                        Unit o = pool[i];
                        s._next_push = s.PushFrom(u.pos, o.pos, 4.0, 1.6);
                        s.Damage(u, o, dmg * k["dmg"] * pk + k["missing"] * GD.Max(0.0, o.max_hp - o.hp));
                        ids2.Add(o.id);
                        pts.Add(o.pos);
                    }
                    u.face = SiegeSim.AngleOf((Vec2)pts[0] - u.pos);
                    ev["ids"] = ids2;
                    ev["pts"] = pts;
                    break;
                }
                case "wildgrowth":
                    MakeZone(u, k.id, u.pos, k["r"], k["dur"], new Zone { heal = k["heal"] * pk, slow = k["slow"], dmg = dmg * k["dmg"] });
                    ev["c"] = u.pos;
                    ev["r"] = k["r"];
                    break;
                default:
                    return false;
            }
            return true;
        }

        // ---------- the effects ----------
        void Shield(Unit u, double amount, double dur)
        {
            double have = s.time < u.shield_until ? u.shield : 0.0;
            u.shield = GD.Min(have + amount, u.max_hp * SHIELD_CAP);
            u.shield_until = GD.Max(u.shield_until, s.time + dur);
        }

        public void Slow(Unit u, double k, double dur, Unit by = null)
        {
            if (k <= 0.0 || s.time < u.unstop_until) return;
            if (by != null) m.NoteCc(by, u);
            if (s.time < u.slow_until)
            {
                u.slow_k = GD.Max(u.slow_k, k);
                u.slow_until = GD.Max(u.slow_until, s.time + dur);
            }
            else
            {
                u.slow_k = k;
                u.slow_until = s.time + dur;
            }
        }

        void Haste(Unit u, double k, double dur)
        {
            u.haste_k = k;
            u.haste_until = s.time + dur;
        }

        void Amp(Unit u, double k, double dur)
        {
            u.amp_k = GD.Max(k, s.time < u.amp_until ? u.amp_k : 0.0);
            u.amp_until = GD.Max(u.amp_until, s.time + dur);
        }

        void Dot(Unit u, Unit by, double dps, double dur, bool heal = false)
        {
            var dots = u.dots ?? new List<Dot>();
            string byId = by != null ? by.id : "";
            foreach (var d in dots)
            {
                if (d.by == byId && d.heal == heal)
                {
                    d.dps = GD.Max(d.dps, dps);
                    d.until = s.time + dur;
                    return;
                }
            }
            dots.Add(new Dot { by = byId, team = by != null ? by.team : -1, dps = dps, until = s.time + dur, next = s.time + 1.0, heal = heal });
            u.dots = dots;
            _afflicted[u.id] = true;
        }

        void Dr(Unit u, double k, double dur)
        {
            if (s.time < u.dr_until) u.dr = GD.Max(u.dr, k);
            else u.dr = k;
            u.dr_until = GD.Max(u.dr_until, s.time + dur);
            u.skin_until = s.time + dur;
        }

        void MakeZone(Unit u, string kind, Vec2 at, double r, double dur, Zone fx)
        {
            _zone_id += 1;
            fx.zid = _zone_id;
            fx.spell = kind;
            fx.team = u.team;
            fx.owner = u.id;
            fx.at = at;
            fx.r = r;
            fx.until = s.time + dur;
            fx.next = s.time;
            zones.Add(fx);
        }

        void DoDash(Unit u, Vec2 dir, double dist, Dash fx, double speed = DASH_SPEED)
        {
            u.state = "dash";
            u.t = dist / speed + 0.05;
            u.face = SiegeSim.AngleOf(dir);
            u.move = Vec2.Zero;
            fx.dir = dir;
            fx.left = dist;
            fx.total = dist;
            fx.speed = speed;
            fx.hits = new List<string>();
            u.dash = fx;
        }

        void Shot(Unit u, string kind, Vec2 dir, double speed, double reach, double dmg, Proj fx)
        {
            fx.id = s._next_proj;
            fx.team = u.team;
            fx.owner = u.id;
            fx.pos = u.pos + dir * 0.6;
            fx.from = u.pos;
            fx.hasFrom = true;
            fx.vel = dir * speed;
            fx.dmg = dmg;
            fx.aoe = 0.0;
            fx.life = reach / speed;
            fx.kind = kind;
            fx.gate_mult = 0.0;
            fx.high = false;
            s.projectiles.Add(fx);
            s.Emit("proj", "pid", s._next_proj, "kind", kind);
            s._next_proj += 1;
        }

        public void ProjHit(Proj p, Unit hit)
        {
            if (p.slow > 0.0)
            {
                s.by_id.TryGetValue(p.owner ?? "", out Unit by);
                Slow(hit, p.slow, p.slow_dur, by);
            }
        }

        public double OnBasic(Unit u)
        {
            double k = 1.0;
            if (u.emp_n > 0)
            {
                if (s.time < u.emp_until) k += u.emp_k;
                u.emp_n = u.emp_n - 1;
            }
            return k;
        }

        public void PoisonHit(Unit src, Unit dst, double amount)
        {
            if (src.poison_n <= 0 || dst.team == src.team || amount <= 0.0) return;
            src.poison_n = src.poison_n - 1;
            Dot(dst, src, s.Stat(src, SK.dmg) * src.poison_k, src.poison_dur);
        }

        // ---------- stepping ----------
        public void Step(double dt)
        {
            for (int i = zones.Count - 1; i > -1; i--)
            {
                Zone z = zones[i];
                if (!s.by_id.TryGetValue(z.owner, out Unit owner)) owner = Unit.Pseudo("", z.team, null);
                if (z.hasDelay)
                {
                    if (s.time < z.delay_at) continue;
                    foreach (var o in EnemiesNear(owner, z.at, z.r + SiegeSim.UNIT_R))
                    {
                        if ((z.hasPush ? z.push : -1.0) != 0.0) s._next_push = s.PushFrom(z.at, o.pos, 5.0, 3.0);
                        s.Damage(owner, o, z.dmg, z.stun);
                        if ((z.hasPush ? z.push : 0.0) > 0.0 && s.Alive(o) && o.mon < 0)
                        {
                            Vec2 away = o.pos - z.at;
                            Vec2 dir = away.Length() > 0.1 ? away.Normalized() : Vec2.FromAngle(s.rng.Randf() * GD.TAU);
                            s.Knockback(o, dir * z.push * (1.0 - 0.5 * GD.Clamp(away.Length() / z.r, 0.0, 1.0)));
                        }
                    }
                    if (z.dmg > 0.0) m.AbilityKing(owner, z.dmg, z.at, z.r);
                    if (z.spell == "pillar") s.Emit("pillar", "c", z.at, "r", z.r, "team", z.team);
                    else s.Emit("burst", "spell", z.spell, "c", z.at, "r", z.r, "team", z.team);
                    zones.RemoveAt(i);
                    continue;
                }
                if (s.time >= z.until)
                {
                    zones.RemoveAt(i);
                    continue;
                }
                if (z.hasStrike)
                {
                    if (s.time >= z.next_at)
                    {
                        z.next_at = z.next_at + z.every;
                        var pool = EnemiesNear(owner, z.at, z.r);
                        Unit pick = null;
                        foreach (var o in pool)
                        {
                            if (pick == null || (o.hero && !pick.hero) || (o.hero == pick.hero && s.rng.Randf() < 0.5)) pick = o;
                        }
                        int kt = (pick == null || !pick.hero) ? m.KingInReach(owner, z.at, z.r) : -1;
                        if (kt >= 0) pick = null;
                        Vec2 spot;
                        if (kt >= 0) spot = m.KingPos(kt);
                        else if (pick != null) spot = pick.pos;
                        else
                        {
                            Vec2 dd = Vec2.FromAngle(s.rng.Randf() * GD.TAU);
                            spot = z.at + dd * Math.Sqrt(s.rng.Randf()) * z.r;
                        }
                        if (kt >= 0) m.HitKing(owner, kt, z.strikeDmg);
                        else if (pick != null) s.Damage(owner, pick, z.strikeDmg, z.strikeStun);
                        s.Emit("zap", "c", spot, "team", z.team, "id", pick != null ? pick.id : "");
                    }
                    continue;
                }
                if (s.time < z.next) continue;
                z.next = z.next + ZONE_EVERY;
                foreach (var o in m.UnitsNear(z.at, z.r + 1.0))
                {
                    if (!s.Alive(o) || o.pos.DistanceTo(z.at) > z.r) continue;
                    if (o.team != z.team)
                    {
                        if (z.dmg > 0.0) s.Damage(owner, o, z.dmg);
                        if (z.slow > 0.0) Slow(o, z.slow, ZONE_EVERY + 0.15, owner);
                    }
                    else if (z.heal > 0.0 && (o.hero || o.minion)) s.Heal(owner, o, o.max_hp * z.heal);
                }
                if (z.dmg > 0.0) m.AbilityKing(owner, z.dmg, z.at, z.r);
            }
            for (int i = traps.Count - 1; i > -1; i--)
            {
                Trap tr = traps[i];
                if (s.time >= tr.until)
                {
                    traps.RemoveAt(i);
                    s.Emit("trap_gone", "trap", tr.id);
                    continue;
                }
                if (s.time < tr.armed_at) continue;
                foreach (var o in m.UnitsNear(tr.at, tr.r + 1.0))
                {
                    if (o.team == tr.team || o.team > 1 || !s.Alive(o) || o.pos.DistanceTo(tr.at) > tr.r) continue;
                    if (!s.by_id.TryGetValue(tr.owner, out Unit owner2)) owner2 = Unit.Pseudo("", tr.team, null);
                    s.Damage(owner2, o, tr.dmg, tr.stun);
                    m.vision.Reveal(o);
                    s.Emit("trap_snap", "trap", tr.id, "id", o.id, "pos", tr.at);
                    traps.RemoveAt(i);
                    break;
                }
            }
            if (!_afflicted.IsEmpty)
            {
                foreach (var id in _afflicted.Keys())
                {
                    s.by_id.TryGetValue(id, out Unit u);
                    if (u == null || !s.Alive(u) || u.dots == null)
                    {
                        _afflicted.Erase(id);
                        continue;
                    }
                    var dots = u.dots;
                    for (int j = dots.Count - 1; j > -1; j--)
                    {
                        Dot d = dots[j];
                        if (s.time >= d.next)
                        {
                            d.next = d.next + 1.0;
                            if (!s.by_id.TryGetValue(d.by, out Unit by)) by = Unit.Pseudo("", d.team, null);
                            if (d.heal) s.Heal(by, u, d.dps);
                            else s.Damage(by, u, d.dps);
                            if (!s.Alive(u)) break;
                        }
                        if (s.time >= d.until) dots.RemoveAt(j);
                    }
                    if (dots.Count == 0)
                    {
                        u.dots = null;
                        _afflicted.Erase(id);
                    }
                }
            }
            if (!_riposting.IsEmpty)
            {
                foreach (var id2 in _riposting.Keys())
                {
                    s.by_id.TryGetValue(id2, out Unit du);
                    if (du == null || !s.Alive(du) || du.riposte == null)
                    {
                        _riposting.Erase(id2);
                        continue;
                    }
                    Riposte rp = du.riposte;
                    if (s.time < rp.until) continue;
                    _riposting.Erase(id2);
                    du.riposte = null;
                    if (!rp.hit) continue;
                    Unit foe = null;
                    double fd = rp.r;
                    foreach (var o in EnemiesNear(du, du.pos, rp.r))
                    {
                        double dd = o.pos.DistanceTo(du.pos) - (o.hero ? 1.5 : 0.0);
                        if (dd < fd)
                        {
                            fd = dd;
                            foe = o;
                        }
                    }
                    if (foe == null) continue;
                    du.face = SiegeSim.AngleOf(foe.pos - du.pos);
                    s._next_push = s.PushFrom(du.pos, foe.pos, 4.0, 1.8);
                    s.Damage(du, foe, rp.dmg, rp.stun);
                    s.Emit("riposte", "id", du.id, "target", foe.id, "pos", foe.pos);
                    s.Emit("attack", "id", du.id, "kind", "attack", "ability", "", "combo", 2);
                }
            }
        }

        public void StepDash(Unit u, double dt)
        {
            Dash dd = u.dash;
            u.t -= dt;
            if (dd == null)
            {
                u.state = "idle";
                return;
            }
            double step_len = GD.Min(dd.left, dd.speed * dt);
            u.pos += dd.dir * step_len;
            dd.left = dd.left - step_len;
            if (dd.dmg > 0.0 && !(dd.first && dd.hits.Count > 0))
            {
                foreach (var o in m.UnitsNear(u.pos, 2.0))
                {
                    if (o.team == u.team || !s.Alive(o) || dd.hits.Contains(o.id)) continue;
                    if (o.pos.DistanceTo(u.pos) > SiegeSim.UNIT_R * 2.0 + 0.35) continue;
                    dd.hits.Add(o.id);
                    s._next_push = s.PushFrom(u.pos, o.pos, 4.0, 1.8);
                    s.Damage(u, o, dd.dmg, dd.stun);
                    if (dd.refund > 0.0 && o.hero) u.cd_ability = u.cd_ability * dd.refund;
                    if (dd.through && s.Alive(o))
                    {
                        Vec2 side = new Vec2(-dd.dir.y, dd.dir.x);
                        if (side.Dot(o.pos - u.pos) < 0.0) side = -side;
                        o.pos = s.ClampToField(s.PushOut(o.pos + side * 1.2, SiegeSim.UNIT_R, o.team));
                    }
                    if (dd.first)
                    {
                        dd.left = 0.0;
                        break;
                    }
                }
                if (!dd.hits.Contains("king") && dd.left > 0.0 && m.KingInReach(u, u.pos, SiegeSim.UNIT_R + 0.35) >= 0)
                {
                    dd.hits.Add("king");
                    m.AbilityKing(u, dd.dmg, u.pos, SiegeSim.UNIT_R + 0.35);
                    if (dd.first) dd.left = 0.0;
                }
            }
            if (dd.left <= 0.001 || u.t <= 0.0)
            {
                LandFx land = dd.land;
                if (land != null)
                {
                    foreach (var o in EnemiesNear(u, u.pos, land.r))
                    {
                        s._next_push = s.PushFrom(u.pos, o.pos, 5.0, 2.6);
                        s.Damage(u, o, land.dmg, land.stun);
                        Slow(o, land.slow, land.dur, u);
                    }
                    m.AbilityKing(u, land.dmg, u.pos, land.r);
                    s.Emit("slam", "id", u.id, "pos", u.pos, "r", land.r);
                }
                u.dash = null;
                u.state = "recover";
                u.t = 0.12;
            }
        }

        // ---------- aiming ----------
        Vec2 MoveDir(Unit u)
        {
            Vec2 mv = u.move;
            return mv.Length() > 0.2 ? mv.Normalized() : SiegeSim.DirOf(u.face);
        }

        Vec2 AwayDir(Unit u)
        {
            Vec2 mv = u.move;
            if (mv.Length() > 0.2) return mv.Normalized();
            Unit foe = s.NearestEnemy(u, 10.0);
            if (foe != null && foe.pos.DistanceTo(u.pos) > 0.1) return (u.pos - foe.pos).Normalized();
            return -SiegeSim.DirOf(u.face);
        }

        Unit HeroNear(Unit u, double r)
        {
            Unit best = null;
            double bd = r;
            foreach (var o in m.UnitsNear(u.pos, r))
            {
                if (o.team == u.team || o.team > 1 || !s.Alive(o) || !o.hero || !m.CanSee(u.team, o)) continue;
                double d = o.pos.DistanceTo(u.pos);
                if (d <= bd)
                {
                    bd = d;
                    best = o;
                }
            }
            return best;
        }

        Vec2 Aim(Unit u, double r, double ahead)
        {
            Unit h = HeroNear(u, r);
            if (h == null) h = s.NearestEnemy(u, r);
            if (h != null) return h.pos;
            return s.ClampToField(u.pos + MoveDir(u) * ahead);
        }

        Vec2 FaceFoe(Unit u, double r)
        {
            Unit h = HeroNear(u, r);
            if (h == null) h = s.NearestEnemy(u, r);
            if (h != null && h.pos.DistanceTo(u.pos) > 0.2) u.face = SiegeSim.AngleOf(h.pos - u.pos);
            return SiegeSim.DirOf(u.face);
        }

        List<Unit> EnemiesNear(Unit u, Vec2 at, double r)
        {
            var o = new List<Unit>();
            int ut = u != null ? u.team : -1;
            foreach (var x in m.UnitsNear(at, r))
            {
                if (x.team != ut && s.Alive(x) && x.pos.DistanceTo(at) <= r)
                {
                    if (x.mon >= 0 && m.camps[x.mon].target == "" && ut <= 1) continue;
                    o.Add(x);
                }
            }
            return o;
        }

        List<Unit> AlliesNear(Unit u, double r, bool heroes_only)
        {
            var o = new List<Unit>();
            foreach (var x in m.UnitsNear(u.pos, r))
                if (x.team == u.team && s.Alive(x) && x.pos.DistanceTo(u.pos) <= r && (!heroes_only || x.hero)) o.Add(x);
            return o;
        }

        Unit MostHurt(Unit u, double r)
        {
            Unit best = u;
            double bf = u.hp / GD.Max(1.0, u.max_hp);
            foreach (var o in AlliesNear(u, r, true))
            {
                double f = o.hp / GD.Max(1.0, o.max_hp);
                if (f < bf)
                {
                    bf = f;
                    best = o;
                }
            }
            return best;
        }

        double FoeKey(Unit o, Vec2 p) => (o.hero ? 0.0 : 100.0) + o.pos.DistanceTo(p);

        // ---------- bots ----------
        static readonly string[] QWE = { "q", "w", "e" };

        public bool BotSpells(Unit u)
        {
            if (!s.CanAct(u)) return false;
            string hid = u.hid;
            foreach (var slot in QWE)
            {
                var k = Kit(hid, slot);
                if (k == null || k.id == null || k.hold || !CanCast(u, slot)) continue;
                if (Worth(u, k) && Spell(u, slot)) return true;
            }
            return false;
        }

        bool Worth(Unit u, KitSpec k)
        {
            double hp = u.hp / GD.Max(1.0, u.max_hp);
            Unit foe = HeroNear(u, k.N("range", 7.0));
            int near_foes = EnemiesNear(u, u.pos, 5.0).Count;
            switch (k.id)
            {
                case "bash": case "leap": case "shadowstep": case "curse": case "mark": case "pillar": case "snare": case "missiles":
                    return foe != null || ((k.id == "missiles" || k.id == "pillar") && near_foes >= 3);
                case "charge": case "knives": case "dazzle":
                    return HeroNear(u, 5.0) != null || near_foes >= 3;
                case "caltrops":
                    return foe != null;
                case "rally": case "manashield":
                    return hp < 0.6 && (near_foes > 0 || HeroNear(u, 10.0) != null);
                case "consecrate": case "bloodlust": case "frenzy": case "poison":
                    return near_foes > 0 && (HeroNear(u, 6.0) != null || near_foes >= 2 || hp < 0.5);
                case "holylight": case "boneshield":
                {
                    Unit who = MostHurt(u, k["range"]);
                    return who.hp / GD.Max(1.0, who.max_hp) < 0.55;
                }
                case "tumble": case "blink":
                    return (hp < 0.35 && near_foes > 0) || (HeroNear(u, 3.0) != null && hp < 0.6);
                case "trap":
                    return near_foes == 0 && !SiegeSim.InCastle(u.pos, u.team) && traps.FindAll(tr => tr.owner == u.id).Count < (int)k["n"];
                case "boulder": case "entangle": case "static": case "keg":
                    return foe != null || ((k.id == "static" || k.id == "keg") && near_foes >= 3);
                case "chain":
                    return foe != null || EnemiesNear(u, u.pos, k["range"]).Count >= 3;
                case "thrust": case "impale":
                {
                    double r2 = k.N("dist", k.N("len", 5.0));
                    return HeroNear(u, r2) != null && (hp > 0.35 || k.id == "impale");
                }
                case "sweep": case "quake": case "buckshot": case "gust":
                {
                    double reach = k["r"] * ((k.id == "buckshot" || k.id == "gust") ? 0.6 : 0.9);
                    return HeroNear(u, reach) != null || EnemiesNear(u, u.pos, reach).Count >= 3 || (k.id == "gust" && hp < 0.5 && near_foes > 0);
                }
                case "stoneskin":
                    return near_foes > 0 && (hp < 0.6 || HeroNear(u, 4.0) != null);
                case "riposte":
                    return HeroNear(u, 2.6) != null && hp < 0.85;
                case "vault": case "smokeroll": case "feint":
                    return (hp < 0.35 && near_foes > 0) || (k.id == "vault" && hp > 0.6 && HeroNear(u, 7.0) != null && HeroNear(u, 3.0) == null);
                case "rejuv":
                {
                    Unit who3 = MostHurt(u, k["range"]);
                    return who3.hp / GD.Max(1.0, who3.max_hp) < 0.7 && who3.dots == null;
                }
                case "barkskin":
                {
                    Unit who4 = MostHurt(u, k["range"]);
                    return who4.hp / GD.Max(1.0, who4.max_hp) < 0.5 && EnemiesNear(u, who4.pos, 6.0).Count > 0;
                }
            }
            return false;
        }

        public bool BotUlt(Unit u, int near_h, int near_any, Unit closest, double cd_h, bool lord_fight)
        {
            var k = Kit(u.hid, "r");
            double hp = u.hp / GD.Max(1.0, u.max_hp);
            switch (k != null ? k.id : "")
            {
                case "landslide":
                    return (near_h >= 1 && (near_any >= 2 || hp < 0.5)) || lord_fight;
                case "dragondive":
                    return (closest != null && cd_h <= k["range"] && (closest.hp < closest.max_hp * 0.6 || near_any >= 2)) || lord_fight;
                case "challenge":
                    return closest != null && cd_h <= k["range"] && closest.hp < closest.max_hp * 0.65;
                case "thunderstorm":
                    if (closest == null || cd_h > k["range"]) return lord_fight;
                    return EnemiesNear(u, closest.pos, k["r"]).Count >= 3 || closest.hp < closest.max_hp * 0.4;
                case "quickdraw":
                {
                    int seen = 0;
                    bool low = false;
                    foreach (var o in m.UnitsNear(u.pos, k["range"]))
                    {
                        if (o.team != u.team && o.team <= 1 && s.Alive(o) && o.hero && m.CanSee(u.team, o))
                        {
                            seen += 1;
                            low = low || o.hp < o.max_hp * 0.35;
                        }
                    }
                    return seen >= 2 || low;
                }
                case "wildgrowth":
                {
                    int hurt = 0;
                    foreach (var o in AlliesNear(u, k["r"], true))
                        if (o.hp < o.max_hp * 0.6) hurt += 1;
                    return (hurt >= 2 && near_any > 0) || (hp < 0.3 && near_h > 0) || lord_fight;
                }
            }
            return false;
        }
    }
}
