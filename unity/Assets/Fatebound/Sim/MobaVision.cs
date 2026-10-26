// 5V5 fog of war (moba_vision.gd, 0.31.158/220): each side sees what's within the sight radius of its heroes, minions,
// towers, wards and its own King; brush hides a unit from the other side unless one of theirs is inside the same patch;
// attacking reveals the attacker for 2 s; wards from a trinket's charges.
using System;
using System.Collections.Generic;

namespace Fatebound.Sim
{
    public sealed class Brush
    {
        public int id;
        public Vec2 p;
        public double r;
    }

    public sealed class Ward
    {
        public int id, team, brush;
        public string owner;
        public Vec2 p;
        public double until;
    }

    public sealed class MobaVision
    {
        public const double SIGHT_HERO = 15.0;
        public const double SIGHT_MINION = 13.5;
        public const double SIGHT_BIG = 15.0;
        public const double SIGHT_TOWER = 15.0;
        public const double SIGHT_WARD = 10.0;
        public const double SIGHT_CASTLE = 18.0;
        public const double REVEAL = 2.0;
        public const double WARD_LIFE = 90.0;
        public const double WARD_RECHARGE = 45.0;
        public const int WARD_CHARGES = 2;
        public const int WARD_MAX = 3;
        public const double EVERY = 0.2;
        static Vec2 V(double x, double y) => new Vec2(x, y);
        public static readonly (Vec2 p, double r)[] BRUSH_BLUE =
        {
            (V(-59.04, 44.9), 2.8), (V(-74.6, 29.34), 2.6), (V(-69.3, 12.73), 2.6), (V(-19.8, 22.63), 2.4),
            (V(-7.07, 12.73), 2.6), (V(-46.67, 18.38), 2.4), (V(-25.46, 7.07), 2.6), (V(-21.21, 63.64), 2.4),
            (V(59.04, 44.9), 2.8), (V(74.6, 29.34), 2.6), (V(69.3, 12.73), 2.6), (V(19.8, 22.63), 2.4),
            (V(7.07, 12.73), 2.6), (V(46.67, 18.38), 2.4), (V(25.46, 7.07), 2.6), (V(21.21, 63.64), 2.4),
        };

        public Moba m;
        public SiegeSim s;
        public List<Brush> brushes = new List<Brush>();
        public List<Ward> wards = new List<Ward>();
        public HashSet<string>[] seen = { new HashSet<string>(), new HashSet<string>() };
        double _clock = 0.0;
        int _wid = 0;
        double _bot_clock = 0.0;

        public void Setup(Moba moba)
        {
            m = moba;
            s = moba.s;
            for (int t = 0; t < 2; t++)
                foreach (var b in BRUSH_BLUE)
                    brushes.Add(new Brush { id = brushes.Count, p = t == 0 ? b.p : -b.p, r = b.r });
            foreach (var u in s.units)
                if (u.hero) u.ward_ch = WARD_CHARGES;
            Update();
        }

        public const double BCELL = 6.0;
        public const double VCELL = 18.0;
        Dictionary<Vec2i, List<Brush>> _bgrid = new Dictionary<Vec2i, List<Brush>>();
        public int epoch = 0;

        void BrushGrid()
        {
            _bgrid = new Dictionary<Vec2i, List<Brush>>();
            foreach (var b in brushes)
            {
                Vec2 p = b.p;
                double r = b.r;
                for (int cx = (int)Math.Floor((p.x - r) / BCELL); cx < (int)Math.Floor((p.x + r) / BCELL) + 1; cx++)
                    for (int cy = (int)Math.Floor((p.y - r) / BCELL); cy < (int)Math.Floor((p.y + r) / BCELL) + 1; cy++)
                    {
                        var k = new Vec2i(cx, cy);
                        if (!_bgrid.TryGetValue(k, out var l)) _bgrid[k] = l = new List<Brush>();
                        l.Add(b);
                    }
            }
        }

        public int BrushAt(Vec2 p)
        {
            if (_bgrid.Count == 0) BrushGrid();
            if (!_bgrid.TryGetValue(new Vec2i((int)Math.Floor(p.x / BCELL), (int)Math.Floor(p.y / BCELL)), out var lst)) return -1;
            int best = -1;
            foreach (var b in lst)
                if (p.DistanceSquaredTo(b.p) <= b.r * b.r && (best < 0 || b.id < best)) best = b.id;
            return best;
        }

        struct Src
        {
            public Vec2 p;
            public double r;
            public int brush;
        }

        List<Src> Sources(int team, Dictionary<string, int> ub)
        {
            var o = new List<Src>();
            foreach (var u in s.units)
            {
                if (u.team != team || !s.Alive(u)) continue;
                double r = SIGHT_MINION;
                if (u.hero || u.super || u.lordling || u.summon) r = u.hero ? SIGHT_HERO : SIGHT_BIG;
                else if (!u.minion) continue;
                o.Add(new Src { p = u.pos, r = r, brush = ub != null && ub.TryGetValue(u.id, out var bb) ? bb : BrushAt(u.pos) });
            }
            foreach (var tw in m.towers)
                if (tw.team == team && !tw.dead) o.Add(new Src { p = tw.p, r = SIGHT_TOWER, brush = -1 });
            foreach (var w in wards)
                if (w.team == team) o.Add(new Src { p = w.p, r = SIGHT_WARD, brush = w.brush });
            o.Add(new Src { p = m.KingPos(team), r = SIGHT_CASTLE, brush = -1 });
            return o;
        }

        /// <summary>What gives side `team` sight: (position, radius, brush) each -- the view's fog draws these.</summary>
        public List<(Vec2 p, double r, int brush)> SourcesFor(int team)
        {
            var o = new List<(Vec2, double, int)>();
            foreach (var sr in Sources(team, null)) o.Add((sr.p, sr.r, sr.brush));
            return o;
        }

        public void Step(double dt)
        {
            for (int i = wards.Count - 1; i > -1; i--)
            {
                if (s.time >= wards[i].until)
                {
                    s.Emit("ward_gone", "ward", wards[i].id, "team", wards[i].team);
                    wards.RemoveAt(i);
                }
            }
            for (int t = 0; t < 2; t++)
                foreach (var hid in m.heroes[t])
                    if (s.by_id.TryGetValue(hid, out var h)) h.ward_ch = GD.Min((double)WARD_CHARGES, h.ward_ch + dt / WARD_RECHARGE);
            _bot_clock += dt;
            if (_bot_clock >= 1.0)
            {
                _bot_clock = 0.0;
                BotWards();
            }
            _clock += dt;
            if (_clock >= EVERY)
            {
                _clock = 0.0;
                Update();
            }
        }

        public void Update()
        {
            var ub = new Dictionary<string, int>();
            foreach (var u in s.units)
                if (s.Alive(u)) ub[u.id] = BrushAt(u.pos);
            for (int t = 0; t < 2; t++)
            {
                var src = Sources(t, ub);
                var grid = new Dictionary<Vec2i, List<Src>>();
                foreach (var sr in src)
                {
                    var k = new Vec2i((int)Math.Floor(sr.p.x / VCELL), (int)Math.Floor(sr.p.y / VCELL));
                    if (!grid.TryGetValue(k, out var l)) grid[k] = l = new List<Src>();
                    l.Add(sr);
                }
                var vis = new HashSet<string>();
                foreach (var u in s.units)
                {
                    if (u.team == t || !s.Alive(u)) continue;
                    if (s.time < u.rev_until)
                    {
                        vis.Add(u.id);
                        continue;
                    }
                    int b = ub[u.id];
                    Vec2 p = u.pos;
                    int cx = (int)Math.Floor(p.x / VCELL);
                    int cy = (int)Math.Floor(p.y / VCELL);
                    bool hit = false;
                    for (int dx = 0; dx < 3 && !hit; dx++)
                        for (int dy = 0; dy < 3 && !hit; dy++)
                        {
                            if (!grid.TryGetValue(new Vec2i(cx + dx - 1, cy + dy - 1), out var lst)) continue;
                            foreach (var sr in lst)
                            {
                                double r = sr.r;
                                if (p.DistanceSquaredTo(sr.p) <= r * r && (b < 0 || sr.brush == b))
                                {
                                    hit = true;
                                    break;
                                }
                            }
                        }
                    if (hit) vis.Add(u.id);
                }
                seen[t] = vis;
            }
            epoch += 1;
        }

        public bool CanSee(int team, Unit u)
        {
            if (team < 0 || team > 1 || u.team == team) return true;
            return seen[team].Contains(u.id ?? "") || s.time < u.rev_until;
        }

        public void Reveal(Unit u)
        {
            if (u.team == 0 || u.team == 1) u.rev_until = s.time + REVEAL;
        }

        public bool WardReady(Unit u) => u.ward_ch >= 1.0 && s.Alive(u);

        public bool PlaceWard(Unit u)
        {
            if (!u.hero || !WardReady(u)) return false;
            var mine = wards.FindAll(w => w.owner == u.id);
            if (mine.Count >= WARD_MAX)
            {
                wards.Remove(mine[0]);
                s.Emit("ward_gone", "ward", mine[0].id, "team", mine[0].team);
            }
            _wid += 1;
            var wd = new Ward { id = _wid, team = u.team, owner = u.id, p = u.pos, until = s.time + WARD_LIFE, brush = BrushAt(u.pos) };
            wards.Add(wd);
            u.ward_ch = u.ward_ch - 1.0;
            s.Emit("ward", "ward", _wid, "team", u.team, "id", u.id, "pos", u.pos);
            Update();
            return true;
        }

        void BotWards()
        {
            for (int t = 0; t < 2; t++)
            {
                foreach (var hid in m.heroes[t])
                {
                    if (!s.by_id.TryGetValue(hid, out var h) || !h.bot || !WardReady(h)) continue;
                    int b = BrushAt(h.pos);
                    if (b < 0) continue;
                    bool have = false;
                    foreach (var w in wards)
                        if (w.team == t && w.brush == b)
                        {
                            have = true;
                            break;
                        }
                    if (!have) PlaceWard(h);
                }
            }
        }
    }
}
