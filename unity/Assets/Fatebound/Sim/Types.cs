// The sim's records (siege_sim.gd / moba.gd / moba_kits.gd dictionaries as classes). Field names follow the GDScript
// keys -- the online protocol's names -- so the port reads line for line against the original.
using System;
using System.Collections.Generic;

namespace Fatebound.Sim
{
    public sealed partial class Unit
    {
        /// <summary>False for a stand-in source ({"id":"tower3", "team":1, "pos":..} -- a tower's shot, the King's slam,
        /// a gone owner's {"team":t, "id":""}): it has no health, kills, gate damage.</summary>
        public bool real = true;
        /// <summary>A stand-in made without a position ({"team":t}): src.has("pos") is false.</summary>
        public bool hasPos = true;

        public static Unit Pseudo(string id, int team, Vec2? pos = null, string state = "idle")
        {
            return new Unit
            {
                real = false, id = id ?? "", team = team, bot = true, cls = "", state = state,
                hasPos = pos.HasValue, pos = pos ?? Vec2.Zero,
            };
        }

        public bool HasMon => mon >= 0;
        public bool IsDead => state == "dead";
        public override string ToString() => "Unit(" + id + ")";
    }

    public sealed class Dance
    {
        public List<string> ids = new List<string>();
        public int i;
        public double next, dmg, missing;
    }

    public sealed class Riposte
    {
        public double until, r, dmg, stun;
        public bool hit;
    }

    public sealed class Dot
    {
        public string by = "";
        public int team = -1;
        public double dps, until, next;
        public bool heal;
    }

    public sealed class LandFx
    {
        public double r, dmg, slow, dur = 1.0, stun;
    }

    public sealed class Dash
    {
        public Vec2 dir;
        public double left, total, speed;
        public List<string> hits = new List<string>();
        public double dmg, stun, refund;
        public bool first, through, leap;
        public LandFx land;
    }

    public sealed class Proj
    {
        public int id, team;
        public string owner = "";
        public Vec2 pos, vel, from;
        public bool hasFrom;
        public double dmg, aoe, life, gate_mult;
        public string kind = "arrow";
        public bool basic, high;
        public List<string> hit;
        public bool @out;
        public double trav;
        public double stun;
        public bool big;
        public string spell;               // (null: not a W/E's shot)
        public double slow;
        public double slow_dur = 1.5;
    }

    public sealed class Gate
    {
        public int id, team, lane;
        public Vec2 a, b, c, @in;
        public bool hasIn = true;
        public double hp, max_hp, r = SiegeSim.WALL_R;
        public bool broken, open;
        public string side = "";
        public double hit_at = double.NegativeInfinity, broken_at = double.NegativeInfinity;
    }

    public sealed class Wall
    {
        public Vec2 a, b;
        public double r;
        public int team = -1;
        public string kind = "wall";
    }

    public sealed class Obstacle
    {
        public Vec2 p;
        public double r;
        public string kind = "";
        public int team = -1, tw = -1, kg = -1;
    }

    public sealed class Meteor
    {
        public int team;
        public string owner = "";
        public Vec2 at;
        public double t_hit, dmg, burn_until = -1.0, kburn;
    }

    public sealed class Oracle
    {
        public int team;
        public string state = "home";
        public Vec2 pos;
    }

    /// <summary>A sim event: {"k": kind, "at": time, ...} as GDScript built it (the view, HUD, sound and the network read
    /// them by key). Values: int, double, bool, string, Vec2, Vec3, List of those.</summary>
    public sealed class Ev : Dictionary<string, object>
    {
        public Ev() { }
        public string K => TryGetValue("k", out var v) ? v as string ?? "" : "";
        public double At => TryGetValue("at", out var v) ? V.ToDouble(v) : 0.0;
        public string S(string key, string dflt = "") => TryGetValue(key, out var v) && v != null ? v.ToString() : dflt;
        public double F(string key, double dflt = 0.0) => TryGetValue(key, out var v) && v != null ? V.ToDouble(v) : dflt;
        public int I(string key, int dflt = 0) => TryGetValue(key, out var v) && v != null ? V.ToInt(v) : dflt;
        public bool B(string key, bool dflt = false) => TryGetValue(key, out var v) && v != null ? V.ToBool(v) : dflt;
        public Vec2 P(string key) => TryGetValue(key, out var v) && v != null ? V.ToVec2(v) : Vec2.Zero;
        public bool Has(string key) => ContainsKey(key);
    }

    /// <summary>Variant-style conversions (what float(x), int(x), bool(x) do in GDScript).</summary>
    public static class V
    {
        public static double ToDouble(object v)
        {
            switch (v)
            {
                case null: return 0.0;
                case double d: return d;
                case float f: return f;
                case int i: return i;
                case long l: return l;
                case bool b: return b ? 1.0 : 0.0;
                case string s: return double.TryParse(s, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var r) ? r : 0.0;
                default: return 0.0;
            }
        }

        public static int ToInt(object v)
        {
            switch (v)
            {
                case null: return 0;
                case int i: return i;
                case long l: return (int)l;
                case double d: return (int)d;
                case float f: return (int)f;
                case bool b: return b ? 1 : 0;
                case string s: return int.TryParse(s, out var r) ? r : 0;
                default: return 0;
            }
        }

        public static long ToLong(object v)
        {
            switch (v)
            {
                case null: return 0;
                case int i: return i;
                case long l: return l;
                case double d: return (long)d;
                case float f: return (long)f;
                case bool b: return b ? 1 : 0;
                default: return 0;
            }
        }

        public static bool ToBool(object v)
        {
            switch (v)
            {
                case null: return false;
                case bool b: return b;
                case int i: return i != 0;
                case long l: return l != 0;
                case double d: return d != 0.0;
                case string s: return s.Length > 0;
                default: return true;
            }
        }

        public static Vec2 ToVec2(object v)
        {
            switch (v)
            {
                case Vec2 p: return p;
                case Vec2i q: return new Vec2((float)q.x, (float)q.y);
                default: return Vec2.Zero;
            }
        }

        public static Vec3 ToVec3(object v) => v is Vec3 p ? p : Vec3.Zero;

        public static T Convert<T>(object v) where T : class => v as T;

        public static string Str(object v) => v == null ? "" : (v is double d ? GD.FloatStr(d) : v is bool b ? (b ? "true" : "false") : v.ToString());
    }
}
