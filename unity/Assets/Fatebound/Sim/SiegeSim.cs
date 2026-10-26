// Fatebound's match simulation (siege_sim.gd, port of 0.31.222). Pure simulation with no engine types, stepped at a
// fixed rate; the same rules run on the server. Coordinates: Vec2(x, z) on the ground plane. Blue (team 0) holds the
// +y end, red (team 1) the -y end; red's keep is the point mirror of blue's. With a Moba (SetupMoba) the 5v5's rules
// take over through the hooks (stat, step, think, damage, kill, gates, melee and arrows on towers, act).
// Ported line for line: GDScript's float is double here, Vector2 is Vec2 (float components); simtest/ checks this
// against the GDScript sim tick by tick.
using System;
using System.Collections.Generic;

namespace Fatebound.Sim
{
    public enum SK { hp, dmg, speed, range, arc, windup, recover, aoe, proj_speed }

    public sealed class ClassDef
    {
        public string key, name, ability;
        public double hp, speed, dmg, range, arc, windup, recover, proj_speed, aoe, ab_cd, gate, heal;
        public bool ranged;

        public double Base(SK k)
        {
            switch (k)
            {
                case SK.hp: return hp;
                case SK.dmg: return dmg;
                case SK.speed: return speed;
                case SK.range: return range;
                case SK.arc: return arc;
                case SK.windup: return windup;
                case SK.recover: return recover;
                case SK.aoe: return aoe;
                default: return proj_speed;
            }
        }
    }

    public sealed partial class SiegeSim
    {
        public const double TICK = 1.0 / 30.0;
        public Moba moba;
        public const double HALF_W = Land.HALF_W;
        public const double HALF_L = Land.HALF_L;
        public const double UNIT_R = 0.45;
        public const double MATCH_TIME = 720.0;
        public double match_time = MATCH_TIME;
        public const double RESPAWN_TIME = 5.0;
        public const double WALL_SCALE = 2.6;
        public const double SEG = 5.2;
        public const double WALL_R = 1.0;
        public const double GATE_HP = 1100.0;
        public const double GATE_OPEN_RADIUS = 4.0;
        public const double WATER_MOVE = 0.45;
        public const double WATER_NAV_COST = 1.6;
        public const double WATER_NAV_DEPTH = 0.05;
        public const double SANCT_ONCE = 3.0;
        public const double BEAM_STACK = 0.5;
        public static readonly Dictionary<string, string> UPGRADE_NAME = new Dictionary<string, string>
        {
            { "knight", "Crusader" }, { "barbarian", "Berserker" }, { "rogue", "Assassin" }, { "ranger", "Ranger" },
            { "mage", "Archmage" }, { "priest", "Necromancer" },
        };
        public const double BEAM_HOLD = 0.22;
        public const double BLOCK_HOLD = 0.22;
        public const double BLOCK_MOVE = 0.4;
        public const double SHIELD_FWD = 0.7;
        public const double SHIELD_HALF = 1.3;
        public const double WHIRL_TIME = 3.0;
        public const double WHIRL_TICK = 0.3;
        public const double WHIRL_R = 2.4;
        public const double WHIRL_DMG = 0.55;
        public const double WHIRL_CD = 9.0;
        public const double BEAM_MOVE = 0.7;
        public const double SANCTUARY_R = 6.5;
        public const double NOVA_R = 4.8;
        public const double SANCTUARY_HEAL = 35.0;

        static ClassDef CD(string key, string name, double hp, double speed, double dmg, double range, double arc, double windup,
            double recover, bool ranged, string ability, double ab_cd, double gate, double proj_speed = 0.0, double aoe = 0.0, double heal = 0.0)
            => new ClassDef { key = key, name = name, hp = hp, speed = speed, dmg = dmg, range = range, arc = arc, windup = windup,
                recover = recover, ranged = ranged, ability = ability, ab_cd = ab_cd, gate = gate, proj_speed = proj_speed, aoe = aoe, heal = heal };

        public static readonly Dictionary<string, ClassDef> CLASSES = new Dictionary<string, ClassDef>
        {
            { "knight", CD("knight", "Knight", 150, 4.6, 21, 2.0, 0.4, 0.24, 0.4, false, "block", 0.0, 1.0) },
            { "barbarian", CD("barbarian", "Barbarian", 130, 4.8, 26, 2.0, 0.25, 0.36, 0.45, false, "spin", 7.0, 1.6) },
            { "rogue", CD("rogue", "Rogue", 85, 6.2, 14, 1.4, 0.5, 0.13, 0.22, false, "lunge", 5.0, 0.6) },
            { "ranger", CD("ranger", "Archer", 80, 5.4, 15, 11.0, 0.0, 0.3, 0.45, true, "volley", 7.0, 0.35, 33.0, 0.0) },
            { "mage", CD("mage", "Mage", 75, 5.0, 20, 9.0, 0.0, 0.4, 0.5, true, "nova", 8.0, 1.0, 24.0, 1.6) },
            { "priest", CD("priest", "Priest", 90, 5.2, 0, 9.0, 0.0, 0.3, 0.4, true, "sanctuary", 9.0, 0.3, 0.0, 0.0, 18.0) },
        };
        public static readonly string[] CLASS_ORDER = { "knight", "barbarian", "rogue", "ranger", "mage", "priest" };

        public double time = 0.0;
        public bool ended = false;
        public int winner = -1;
        public string end_reason = "";
        public List<Unit> units = new List<Unit>();
        public Dictionary<string, Unit> by_id = new Dictionary<string, Unit>();
        public List<Proj> projectiles = new List<Proj>();
        public List<Oracle> oracles = new List<Oracle>();
        public int[] score = { 0, 0 };
        public int[] kills = { 0, 0 };
        public List<Ev> events = new List<Ev>();
        public Dictionary<string, object> net_sync = new Dictionary<string, object>();
        public List<Obstacle> obstacles = new List<Obstacle>();
        public List<Wall> walls = new List<Wall>();
        public List<Gate> gates = new List<Gate>();
        public bool open_gates = false;
        public Vec3 _next_push = Vec3.Zero;
        public Rng rng = new Rng();
        public List<AStarGrid> nav = new List<AStarGrid>();
        public int nav_version = 0;
        public const double AI_EVERY = 0.15;
        public const double MINION_AI_EVERY = 0.3;
        public const int AI_SPREAD = 5;
        public int _next_proj = 1;
        public string _basic_by = "";

        // ---------- map ----------
        public static Vec2 M(int team, Vec2 p) => team == 0 ? p : -p;

        public static Vec2 Throne(int team) => M(team, Keep.KING);

        public static double HeightAt(Vec2 p) => Land.GroundHeight(p);

        public static Vec2 Spawn(int team) => M(team, Keep.FOUNTAIN);

        public static Vec2 GateFront(Gate g)
        {
            if (g.hasIn) return g.c - g.@in * 2.2;
            Vec2 outward = g.team == 0 ? new Vec2(0f, -1f) : new Vec2(0f, 1f);
            return g.c + outward * 2.2;
        }

        public static Vec2[] SegSegClosest(Vec2 a0, Vec2 a1, Vec2 b0, Vec2 b1)
        {
            double best = GD.INF;
            Vec2 pa = a0, pb = b0;
            for (int k = 0; k < 17; k++)
            {
                Vec2 q = a0.Lerp(a1, k / 16.0);
                Vec2 c = SegClosest(q, b0, b1);
                if (q.DistanceSquaredTo(c) < best)
                {
                    best = q.DistanceSquaredTo(c); pa = q; pb = c;
                }
                Vec2 q2 = b0.Lerp(b1, k / 16.0);
                Vec2 c2 = SegClosest(q2, a0, a1);
                if (q2.DistanceSquaredTo(c2) < best)
                {
                    best = q2.DistanceSquaredTo(c2); pa = c2; pb = q2;
                }
            }
            return new[] { pa, pb };
        }

        void FillSqueezeSlots()
        {
            double need = UNIT_R * 2.0 + 0.1;
            var fills = new List<Wall>();
            int n = walls.Count;
            for (int i = 0; i < n; i++)
            {
                Wall A = walls[i];
                for (int j = i + 1; j < n; j++)
                {
                    Wall B = walls[j];
                    double reach = A.r + B.r + need;
                    if (Math.Min(A.a.x, A.b.x) - reach > Math.Max(B.a.x, B.b.x) || Math.Min(B.a.x, B.b.x) - reach > Math.Max(A.a.x, A.b.x)
                        || Math.Min(A.a.y, A.b.y) - reach > Math.Max(B.a.y, B.b.y) || Math.Min(B.a.y, B.b.y) - reach > Math.Max(A.a.y, A.b.y))
                        continue;
                    Vec2[] cp = SegSegClosest(A.a, A.b, B.a, B.b);
                    double gap = cp[0].DistanceTo(cp[1]) - A.r - B.r;
                    if (gap <= 0.02 || gap >= need) continue;
                    Vec2 mid = (cp[0] + cp[1]) * 0.5;
                    bool covered = false;
                    for (int k = 0; k < n; k++)
                    {
                        if (k == i || k == j) continue;
                        Wall C = walls[k];
                        if (mid.DistanceTo(SegClosest(mid, C.a, C.b)) < C.r)
                        {
                            covered = true;
                            break;
                        }
                    }
                    if (covered) continue;
                    bool passable = Array.IndexOf(PROJ_PASS_KINDS, A.kind) >= 0 && Array.IndexOf(PROJ_PASS_KINDS, B.kind) >= 0;
                    fills.Add(new Wall { a = cp[0], b = cp[1], r = GD.Max(A.r, B.r), team = A.team == B.team ? A.team : -1,
                        kind = passable ? "ledge" : "fill" });
                }
            }
            walls.AddRange(fills);
            squeeze_fills = fills.Count;
        }

        void BuildMap()
        {
            walls.Clear();
            gates.Clear();
            obstacles.Clear();
            for (int t = 0; t < 2; t++) BuildKeep(t);
            walls.AddRange(Land.Walls());
            FillSqueezeSlots();
        }

        void BuildKeep(int t)
        {
            foreach (var seg in Keep.Ring())
                walls.Add(new Wall { a = M(t, seg[0]), b = M(t, seg[1]), r = WALL_R, team = t, kind = "wall" });
            for (int i = 0; i < Keep.GATE_ANG.Length; i++)
            {
                Vec2[] gd = Keep.GateEnds(i);
                Vec2 a = M(t, gd[0]);
                Vec2 b = M(t, gd[1]);
                Vec2 inw = (M(t, Keep.C) - (a + b) * 0.5).Normalized();
                gates.Add(new Gate { id = gates.Count, team = t, a = a, b = b, c = (a + b) * 0.5, hp = GATE_HP, max_hp = GATE_HP,
                    broken = false, open = false, side = Keep.GATE_SIDE[i], lane = i, @in = inw, hasIn = true });
            }
            obstacles.Add(new Obstacle { p = M(t, Keep.THRONE_SEAT), r = Keep.THRONE_R, kind = "castle_building", team = t });
        }

        // ---------- navigation ----------
        public static readonly int NAV_W = (int)(HALF_W * 2.0);
        public static readonly int NAV_H = (int)(HALF_L * 2.0);

        public static Vec2i NavCell(Vec2 p) =>
            new Vec2i(GD.ClampI((long)Math.Floor(p.x + HALF_W), 0, NAV_W - 1), GD.ClampI((long)Math.Floor(p.y + HALF_L), 0, NAV_H - 1));

        public static Vec2 NavPoint(Vec2i c) => new Vec2(c.x - HALF_W + 0.5, c.y - HALF_L + 0.5);

        public static Vec2 SegClosest(Vec2 p, Vec2 a, Vec2 b)
        {
            Vec2 ab = b - a;
            double t = GD.Clamp((p - a).Dot(ab) / GD.Max(ab.LengthSquared(), 0.0001), 0.0, 1.0);
            return a + ab * t;
        }

        List<Vec2i> CellsNearSegment(Vec2 a, Vec2 b, double reach)
        {
            var o = new List<Vec2i>();
            Vec2i lo = NavCell(new Vec2(Math.Min(a.x, b.x) - reach, Math.Min(a.y, b.y) - reach));
            Vec2i hi = NavCell(new Vec2(Math.Max(a.x, b.x) + reach, Math.Max(a.y, b.y) + reach));
            for (int x = lo.x; x < hi.x + 1; x++)
                for (int y = lo.y; y < hi.y + 1; y++)
                {
                    Vec2i c = new Vec2i(x, y);
                    Vec2 p = NavPoint(c);
                    if (p.DistanceTo(SegClosest(p, a, b)) < reach) o.Add(c);
                }
            return o;
        }

        List<Vec2i> CellsAcrossSegment(Vec2 a, Vec2 b, double reach)
        {
            var o = new List<Vec2i>();
            Vec2 ab = b - a;
            double len2 = GD.Max(ab.LengthSquared(), 0.0001);
            foreach (var c in CellsNearSegment(a, b, reach))
            {
                double t = (NavPoint(c) - a).Dot(ab) / len2;
                if (t >= 0.0 && t <= 1.0) o.Add(c);
            }
            return o;
        }

        // ---------- spatial buckets (collision culling) ----------
        public const double BUCKET = 6.0;
        public const double BUCKET_REACH = 1.6;
        int _bw, _bh;
        List<int>[] _bucket_walls = new List<int>[0];
        public List<Unit> _blockers = new List<Unit>();
        public int squeeze_fills = 0;
        List<int>[] _bucket_walls_proj = new List<int>[0];
        public static readonly string[] PROJ_PASS_KINDS = { "ledge", "bars", "river", "rail", "edge", "rock" };
        List<int>[] _bucket_obs = new List<int>[0];
        List<int>[] _bucket_obs_proj = new List<int>[0];

        public void BuildBuckets()
        {
            _bw = (int)Math.Ceiling(HALF_W * 2.0 / BUCKET) + 1;
            _bh = (int)Math.Ceiling(HALF_L * 2.0 / BUCKET) + 1;
            int nb = _bw * _bh;
            _bucket_walls = new List<int>[nb];
            _bucket_walls_proj = new List<int>[nb];
            _bucket_obs = new List<int>[nb];
            _bucket_obs_proj = new List<int>[nb];
            for (int i = 0; i < nb; i++)
            {
                _bucket_walls[i] = new List<int>();
                _bucket_walls_proj[i] = new List<int>();
                _bucket_obs[i] = new List<int>();
                _bucket_obs_proj[i] = new List<int>();
            }
            for (int wi = 0; wi < walls.Count; wi++)
            {
                Wall w = walls[wi];
                foreach (int bi in BucketsIn(Math.Min(w.a.x, w.b.x) - w.r - BUCKET_REACH, Math.Min(w.a.y, w.b.y) - w.r - BUCKET_REACH,
                             Math.Max(w.a.x, w.b.x) + w.r + BUCKET_REACH, Math.Max(w.a.y, w.b.y) + w.r + BUCKET_REACH))
                {
                    _bucket_walls[bi].Add(wi);
                    if (Array.IndexOf(PROJ_PASS_KINDS, w.kind) < 0) _bucket_walls_proj[bi].Add(wi);
                }
            }
            for (int oi = 0; oi < obstacles.Count; oi++)
            {
                Obstacle ob = obstacles[oi];
                foreach (int bi in BucketsIn(ob.p.x - ob.r - BUCKET_REACH, ob.p.y - ob.r - BUCKET_REACH, ob.p.x + ob.r + BUCKET_REACH, ob.p.y + ob.r + BUCKET_REACH))
                {
                    _bucket_obs[bi].Add(oi);
                    _bucket_obs_proj[bi].Add(oi);
                }
            }
        }

        List<int> BucketsIn(double x0, double y0, double x1, double y1)
        {
            var o = new List<int>();
            int bx0 = GD.ClampI((long)Math.Floor((x0 + HALF_W) / BUCKET), 0, _bw - 1);
            int by0 = GD.ClampI((long)Math.Floor((y0 + HALF_L) / BUCKET), 0, _bh - 1);
            int bx1 = GD.ClampI((long)Math.Floor((x1 + HALF_W) / BUCKET), 0, _bw - 1);
            int by1 = GD.ClampI((long)Math.Floor((y1 + HALF_L) / BUCKET), 0, _bh - 1);
            for (int bx = bx0; bx < bx1 + 1; bx++)
                for (int by = by0; by < by1 + 1; by++)
                    o.Add(by * _bw + bx);
            return o;
        }

        int Bucket(Vec2 p) =>
            GD.ClampI((long)Math.Floor((p.y + HALF_L) / BUCKET), 0, _bh - 1) * _bw + GD.ClampI((long)Math.Floor((p.x + HALF_W) / BUCKET), 0, _bw - 1);

        static List<Vec2i> _outside;

        static List<Vec2i> OutsideCells()
        {
            if (_outside == null)
            {
                var o = new List<Vec2i>();
                for (int x = 0; x < NAV_W; x++)
                    for (int y = 0; y < NAV_H; y++)
                    {
                        Vec2i c = new Vec2i(x, y);
                        if (!Land.InsideField(NavPoint(c))) o.Add(c);
                    }
                _outside = o;
            }
            return _outside;
        }

        public void BuildNav()
        {
            nav.Clear();
            for (int t = 0; t < 2; t++)
            {
                var g = new AStarGrid(0, 0, NAV_W, NAV_H)
                {
                    diagonal = AStarGrid.Diagonal.OnlyIfNoObstacles,
                    computeH = AStarGrid.Heuristic.Octile,
                    estimateH = AStarGrid.Heuristic.Octile,
                };
                nav.Add(g);
            }
            var solid = new List<Vec2i>();
            foreach (var w in walls) solid.AddRange(CellsNearSegment(w.a, w.b, w.r + UNIT_R * 0.9));
            foreach (var ob in obstacles) solid.AddRange(CellsNearSegment(ob.p, ob.p, ob.r + UNIT_R * 0.8));
            solid.AddRange(OutsideCells());
            foreach (var c in solid)
                for (int t = 0; t < 2; t++) nav[t].SetSolid(c, true);
            AStarGrid grid0 = nav[0];
            for (int ix = grid0.rx; ix < grid0.rx + grid0.rw; ix++)
                for (int iz = grid0.ry; iz < grid0.ry + grid0.rh; iz++)
                {
                    Vec2i cc = new Vec2i(ix, iz);
                    if (WaterDepth(NavPoint(cc)) > WATER_NAV_DEPTH)
                        for (int t = 0; t < 2; t++) nav[t].SetWeight(cc, WATER_NAV_COST);
                }
            _gate_cells.Clear();
            foreach (var g in gates) _gate_cells.Add(CellsAcrossSegment(g.a, g.b, g.r + UNIT_R * 0.9));
            UpdateGateNav();
        }

        List<List<Vec2i>> _gate_cells = new List<List<Vec2i>>();

        public void UpdateGateNav()
        {
            _po_epoch += 1;
            for (int gi = 0; gi < gates.Count; gi++)
            {
                Gate g = gates[gi];
                foreach (var c in _gate_cells[gi])
                    for (int t = 0; t < 2; t++)
                    {
                        AStarGrid grid = nav[t];
                        grid.SetSolid(c, false);
                        grid.SetWeight(c, (t == g.team || !GateBlocks(g)) ? 1.0 : 60.0);
                    }
            }
            nav_version += 1;
        }

        public List<Vec2> FindPath(int team, Vec2 from, Vec2 to)
        {
            AStarGrid grid = nav[team <= 1 ? team : 0];
            var opened = new List<int>();
            for (int gi = 0; gi < gates.Count; gi++)
            {
                Gate g = gates[gi];
                if (g.team != team && GateBlocks(g) && LetsOut(g, from))
                {
                    opened.Add(gi);
                    foreach (var c in _gate_cells[gi]) grid.SetWeight(c, 1.0);
                }
            }
            Vec2i a = FreeCell(grid, NavCell(from));
            Vec2i b = FreeCell(grid, NavCell(to));
            var ids = grid.GetIdPath(a, b, true);
            foreach (int gi in opened)
                foreach (var c in _gate_cells[gi]) grid.SetWeight(c, 60.0);
            var o = new List<Vec2>(Math.Max(0, ids.Count - 1));
            for (int i = 1; i < ids.Count; i++) o.Add(NavPoint(ids[i]));
            return o;
        }

        Vec2i FreeCell(AStarGrid grid, Vec2i c)
        {
            if (!grid.IsSolid(c)) return c;
            for (int r = 1; r < 5; r++)
                for (int dx = -r; dx < r + 1; dx++)
                    for (int dy = -r; dy < r + 1; dy++)
                    {
                        Vec2i n = new Vec2i(c.x + dx, c.y + dy);
                        if (grid.InBounds(n) && !grid.IsSolid(n)) return n;
                    }
            return c;
        }

        public bool GateBlocks(Gate g) => !open_gates && !g.broken && g.hp > 0.0;

        public static bool LetsOut(Gate g, Vec2 p) => g.hasIn && (p - g.c).Dot(g.@in) > 0.0;

        // ---------- setup ----------
        public void Setup(int team_size, long seed_value, int player_team = 0)
        {
            meteors = new List<Meteor>();
            rng.Seed = unchecked((ulong)seed_value);
            BuildMap();
            BuildBuckets();
            BuildNav();
            oracles = new List<Oracle> { NewKing(0), NewKing(1) };
            for (int t = 0; t < 2; t++)
                for (int i = 0; i < team_size; i++)
                {
                    bool human = t == player_team && i == 0;
                    string id = human ? "you" : (t == 0 ? "b" : "r") + i;
                    Unit u = NewUnit(id, t, !human);
                    u.think_at = (double)(units.Count % AI_SPREAD) * TICK;
                    units.Add(u);
                    by_id[id] = u;
                    Respawn(u, true);
                }
        }

        Oracle NewKing(int team) => new Oracle { team = team, state = "home", pos = Throne(team) };

        public Unit NewUnit(string id, int team, bool bot)
        {
            return new Unit { id = id, team = team, bot = bot, cls = "knight", up = false, hp = 60.0, max_hp = 60.0, pos = Vec2.Zero,
                face = 0.0, move = Vec2.Zero, state = "idle", t = 0.0, atk = "", path = new List<Vec2>(), path_i = 0,
                path_goal = Vec2.Inf, path_at = -10.0, path_ver = -1, think_at = 0.0 };
        }

        public double Stat(Unit u, SK key)
        {
            double b = CLASSES[u.cls].Base(key);
            if (moba != null) return moba.Stat(u, key, b);
            if (key == SK.hp || key == SK.dmg) return b * (u.up ? 1.25 : 1.0);
            return b;
        }

        public void SetClass(Unit u, string cls, bool up)
        {
            double ratio = u.hp / GD.Max(1.0, u.max_hp);
            u.cls = cls;
            u.up = up;
            u.max_hp = Stat(u, SK.hp);
            u.hp = GD.Max(1.0, u.max_hp * GD.Max(ratio, 0.75));
            u.cd_ability = 0.0;
        }

        public string ClassLabel(Unit u)
        {
            if (moba != null && u.kq != null) return Moba.HEROES[u.hid].name;
            return u.up ? (UPGRADE_NAME.TryGetValue(u.cls, out var n) ? n : "") : CLASSES[u.cls].name;
        }

        public void Respawn(Unit u, bool first = false)
        {
            Vec2 sp = Spawn(u.team);
            double rx = rng.RandfRange(-1.0, 1.0);
            double ry = rng.RandfRange(-1.0, 1.0);
            u.pos = sp + new Vec2(rx, ry) * (Keep.FOUNTAIN_R - 0.6);
            u.face = u.team == 0 ? Math.PI : 0.0;
            u.max_hp = Stat(u, SK.hp);
            u.hp = u.max_hp;
            u.state = "idle";
            u.t = 0.0;
            u.stun = 0.0;
            u.path = new List<Vec2>();
            if (moba != null && u.hero && !first && u.team >= 0 && u.team <= 1)
                moba.last_respawn[u.team] = time;
            if (!first) Emit("spawn", "id", u.id);
        }

        // ---------- events ----------
        public Ev Emit(string kind, Ev data)
        {
            data["k"] = kind;
            data["at"] = time;
            events.Add(data);
            return data;
        }

        public Ev Emit(string kind, params object[] kv)
        {
            var e = new Ev();
            for (int i = 0; i + 1 < kv.Length; i += 2) e[(string)kv[i]] = kv[i + 1];
            return Emit(kind, e);
        }

        public List<Ev> DrainEvents()
        {
            var o = events;
            events = new List<Ev>();
            return o;
        }

        // ---------- helpers ----------
        public static Vec2 DirOf(double angle) => new Vec2(Math.Sin(angle), Math.Cos(angle));

        public static double AngleOf(Vec2 v) => Math.Atan2(v.x, v.y);

        public bool Alive(Unit u) => u.state != "dead";

        static readonly string[] HEAL_FOCUS = { "priest", "mage" };

        public Unit NearestEnemy(Unit u, double max_d, bool prefer_front = false)
        {
            Unit best = null;
            double best_score = GD.INF;
            Vec2 fwd = DirOf(u.face);
            bool ranged = CLASSES[u.cls].ranged;
            foreach (var o in units)
            {
                if (o.team == u.team || !Alive(o)) continue;
                Vec2 off = o.pos - u.pos;
                double d = off.Length();
                if (d > max_d) continue;
                if (Vanished(o) && d > 1.6) continue;
                if (moba != null && !moba.CanSee(u.team, o)) continue;
                double s = d;
                if (prefer_front && d > 0.01) s += (1.0 - fwd.Dot(off / d)) * 2.0;
                if (u.bot)
                {
                    if (o.hp < o.max_hp * 0.35) s -= 3.0;
                    if (ranged && (o.cls == "priest" || o.cls == "mage")) s -= 2.0;
                }
                if (s < best_score)
                {
                    best_score = s;
                    best = o;
                }
            }
            return best;
        }

        // ---------- input (from HUD or bot brain) ----------
        static bool IsFightAction(string a) => a == "attack" || a == "ability" || a == "block" || a == "dodge" || a == "ult" || a == "spell";

        /// <summary>act(id, action, arg): arg is an int (pick, shop_sell), a string (spell, learn, shop_buy) or null.</summary>
        public bool Act(string id, string action, object arg = null)
        {
            by_id.TryGetValue(id, out Unit u);
            if (u != null && IsFightAction(action)) RecallCancel(u);
            if (u != null && !ended && moba != null && (action == "shop_buy" || action == "shop_sell"))
                return action == "shop_buy" ? moba.Buy(u, V.Str(arg)) : moba.Sell(u, V.ToInt(arg));
            if (u != null && !ended && moba != null && action == "learn") return moba.Learn(u, V.Str(arg));
            if (u == null || ended || !Alive(u)) return false;
            switch (action)
            {
                case "attack":
                    return u.cls == "priest" ? Beam(u) : StartAttack(u, "attack");
                case "ability":
                    if (moba != null && u.kq != null) return moba.kits.Spell(u, "q");
                    if (moba != null && u.hero && moba.Rank(u, "q") <= 0) return false;
                    switch (AbilityOf(u))
                    {
                        case "block": return Block(u);
                        case "whirlwind": return Whirl(u);
                        case "hammer": return ThrowHammer(u);
                        case "resurrect": return Resurrect(u);
                        case "vanish": return Vanish(u);
                        default: return StartAttack(u, "ability");
                    }
                case "block":
                    return u.cls == "knight" ? Block(u) : false;
                case "dodge": return Dodge(u);
                case "pick":
                    return moba != null && moba.Pick(u, V.ToInt(arg));
                case "ult":
                    return moba != null && moba.Ult(u);
                case "spell":
                    return moba != null && moba.kits.Spell(u, V.Str(arg));
                case "ward":
                    return moba != null && moba.Ward(u);
                case "recall":
                    return RecallStart(u);
                case "shop_buy":
                    return moba != null && moba.Buy(u, V.Str(arg));
                case "shop_sell":
                    return moba != null && moba.Sell(u, V.ToInt(arg));
            }
            return false;
        }

        // ---------- RECALL (0.31.181) ----------
        public const double RECALL_TIME = 6.0;

        public bool Recalling(Unit u) => u.recall_until > 0.0;

        bool RecallStart(Unit u)
        {
            if (moba == null || !u.hero || !CanAct(u) || Recalling(u) || u.team > 1) return false;
            if (u.pos.DistanceTo(Spawn(u.team)) < Keep.FOUNTAIN_R + 1.0) return false;
            u.recall_until = time + RECALL_TIME;
            u.move = Vec2.Zero;
            u.path = new List<Vec2>();
            Emit("recall", "id", u.id, "until", u.recall_until);
            return true;
        }

        public void RecallCancel(Unit u)
        {
            if (Recalling(u))
            {
                u.recall_until = -1.0;
                Emit("recall_cancel", "id", u.id);
            }
        }

        void StepRecall(Unit u)
        {
            if (u.move.Length() > 0.1 || u.stun > 0.0 || u.state != "idle") RecallCancel(u);
            else if (time >= u.recall_until)
            {
                Vec2 from = u.pos;
                double k = (double)(Math.Abs((long)GHash.Str(u.id)) % 360) * Math.PI / 180.0;
                u.pos = Spawn(u.team) + Vec2.FromAngle(k) * (Keep.FOUNTAIN_R - 0.8);
                u.face = u.team == 0 ? Math.PI : 0.0;
                u.path = new List<Vec2>();
                u.recall_until = -1.0;
                Emit("recall_done", "id", u.id, "from", from, "to", u.pos);
            }
        }

        public void SetMove(string id, Vec2 v)
        {
            if (by_id.TryGetValue(id, out var u)) u.move = v.LimitLength(1.0);
        }

        public bool CanAct(Unit u) => Alive(u) && u.stun <= 0.0 && (u.state == "idle" || u.state == "move");

        public void Aim(Unit u, double reach)
        {
            Unit target = NearestEnemy(u, reach, true);
            u.aim_d = 0.0;
            Vec2 aim_p = Vec2.Inf;
            if (target != null) aim_p = target.pos;
            if (moba != null && !u.bot)
            {
                var st = moba.AimStructure(u, reach);
                if (st != null)
                {
                    double us = GD.INF;
                    if (target != null)
                    {
                        Vec2 off = target.pos - u.pos;
                        double d = off.Length();
                        us = d + (d > 0.01 ? (1.0 - DirOf(u.face).Dot(off / d)) * 2.0 : 0.0);
                    }
                    if (st.score < us) aim_p = st.p;
                }
            }
            if (aim_p != Vec2.Inf)
            {
                u.face = AngleOf(aim_p - u.pos);
                u.aim_d = u.pos.DistanceTo(aim_p);
            }
        }

        public const double COMBO_GAP = 0.9;

        public bool StartAttack(Unit u, string kind, bool aim = true)
        {
            if (kind == "ability" && moba != null && u.kq != null) return moba.kits.Spell(u, "q");
            if (!CanAct(u) || Blocking(u) || Whirling(u)) return false;
            if (u.hammer_out >= 0) return false;
            ClassDef c = CLASSES[u.cls];
            if (kind == "ability")
            {
                if (c.ability == "" || u.cd_ability > 0.0) return false;
                u.cd_ability = c.ab_cd;
            }
            double reach = Stat(u, SK.range) * (c.ranged ? 1.0 : 1.9);
            if (kind == "ability" && c.ability == "lunge") reach = 6.0;
            if (aim) Aim(u, reach);
            u.state = "wind";
            u.atk = kind;
            u.t = Stat(u, SK.windup) * (kind == "ability" ? 1.3 : 1.0);
            u.lunge_hit = false;
            int combo = 0;
            if (kind == "attack")
            {
                if (time - u.combo_t <= Stat(u, SK.windup) + Stat(u, SK.recover) + COMBO_GAP)
                    combo = (u.combo + 1) % 3;
                u.combo = combo;
                u.combo_t = time;
            }
            Emit("attack", "id", u.id, "kind", kind, "ability", kind == "ability" ? c.ability : "", "combo", combo);
            return true;
        }

        // ---------- knight block / berserker whirlwind ----------
        public string AbilityOf(Unit u)
        {
            if (u.kq != null) return u.kq;
            if (u.up)
            {
                switch (u.cls)
                {
                    case "barbarian": return "whirlwind";
                    case "knight": return "hammer";
                    case "priest": return "resurrect";
                    case "rogue": return "vanish";
                    case "ranger": return "pierce";
                    case "mage": return "meteor";
                }
            }
            return CLASSES[u.cls].ability;
        }

        public bool Blocking(Unit u) => u.cls == "knight" && time < u.block_until && Alive(u);

        public bool Whirling(Unit u) => time < u.whirl_until && Alive(u);

        public Vec2[] ShieldSeg(Unit k)
        {
            Vec2 f = new Vec2(Math.Sin(k.face), Math.Cos(k.face));
            Vec2 c = k.pos + f * SHIELD_FWD;
            Vec2 side = new Vec2(f.y, -f.x) * SHIELD_HALF * (k.up ? 1.4 : 1.0);
            return new[] { c - side, c + side };
        }

        public static bool SegCross(Vec2 p1, Vec2 p2, Vec2 q1, Vec2 q2)
        {
            double d1 = (p2 - p1).Cross(q1 - p1);
            double d2 = (p2 - p1).Cross(q2 - p1);
            double d3 = (q2 - q1).Cross(p1 - q1);
            double d4 = (q2 - q1).Cross(p2 - q1);
            return d1 * d2 < 0.0 && d3 * d4 < 0.0;
        }

        public bool ShieldBlocks(Vec2 from, Unit dst)
        {
            foreach (var k in _blockers)
            {
                if (k.team != dst.team) continue;
                if (k == dst)
                {
                    if (new Vec2(Math.Sin(k.face), Math.Cos(k.face)).Dot(from - k.pos) > 0.0) return true;
                    continue;
                }
                Vec2[] s = ShieldSeg(k);
                if (SegCross(from, dst.pos, s[0], s[1])) return true;
            }
            return false;
        }

        bool IsWindRecoverDodge(Unit u) => u.state == "wind" || u.state == "recover" || u.state == "dodge";

        public bool Block(Unit u)
        {
            if (u.kq != null) return false;
            if (!Alive(u) || u.stun > 0.0 || IsWindRecoverDodge(u)) return false;
            if (!Blocking(u)) Emit("block_up", "id", u.id);
            u.block_until = time + BLOCK_HOLD;
            return true;
        }

        bool Whirl(Unit u)
        {
            if (u.cd_ability > 0.0 || !CanAct(u)) return false;
            u.whirl_until = time + WHIRL_TIME;
            u.whirl_t = 0.0;
            u.cd_ability = WHIRL_CD;
            Emit("whirl", "id", u.id);
            return true;
        }

        void StepWhirl(Unit u, double dt)
        {
            if (!Whirling(u)) return;
            if (u.stun > 0.0)
            {
                u.whirl_until = 0.0;
                return;
            }
            u.face += dt * 26.0;
            u.whirl_t -= dt;
            if (u.whirl_t > 0.0) return;
            u.whirl_t = WHIRL_TICK;
            double dmg = Stat(u, SK.dmg) * WHIRL_DMG;
            for (int oi = 0; oi < units.Count; oi++)
            {
                Unit o = units[oi];
                if (o.team != u.team && Alive(o) && o.pos.DistanceTo(u.pos) <= WHIRL_R) Damage(u, o, dmg);
            }
            if (moba != null) moba.AbilityKing(u, dmg, u.pos, WHIRL_R);
            foreach (var g in gates)
                if (g.team != u.team && GateBlocks(g) && u.pos.DistanceTo(SegClosest(u.pos, g.a, g.b)) <= WHIRL_R)
                    DamageGate(u, g, dmg * CLASSES[u.cls].gate);
        }

        // ---------- priest beam ----------
        public Unit BeamTarget(Unit u)
        {
            double reach = CLASSES["priest"].range;
            Unit best = null, any = null;
            double bd = GD.INF, ad = GD.INF;
            foreach (var a in units)
            {
                if (a.id == u.id || a.team != u.team || !Alive(a)) continue;
                double d = u.pos.DistanceTo(a.pos);
                if (d > reach) continue;
                if (d < ad)
                {
                    ad = d;
                    any = a;
                }
                if (a.hp < a.max_hp - 0.5 && d < bd)
                {
                    bd = d;
                    best = a;
                }
            }
            return best ?? any;
        }

        public bool Beam(Unit u)
        {
            if (!Alive(u) || u.stun > 0.0 || IsWindRecoverDodge(u)) return false;
            if (IsNecro(u)) return NecroBeam(u);
            by_id.TryGetValue(u.beam, out Unit cur);
            if (cur == null || !Alive(cur) || cur.hp >= cur.max_hp - 0.5 || u.pos.DistanceTo(cur.pos) > CLASSES["priest"].range + 1.0)
                cur = BeamTarget(u);
            if (cur == null)
            {
                u.beam = "";
                return false;
            }
            if (u.beam != cur.id) Emit("beam", "id", u.id, "to", cur.id);
            u.beam = cur.id;
            u.beam_until = time + BEAM_HOLD;
            u.face = AngleOf(cur.pos - u.pos);
            return true;
        }

        void StepBeam(Unit u, double dt)
        {
            if (u.beam == "") return;
            by_id.TryGetValue(u.beam, out Unit t);
            if (time > u.beam_until || u.cls != "priest" || !Alive(u) || t == null || !Alive(t)
                || u.pos.DistanceTo(t.pos) > CLASSES["priest"].range + 1.0)
            {
                u.beam = "";
                u.beam2 = "";
                return;
            }
            if (IsNecro(u))
            {
                StepDrain(u, t, dt);
                return;
            }
            double rate = CLASSES["priest"].heal * (u.up ? 1.4 : 1.0);
            Heal(u, t, rate * dt * BeamShare(t));
        }

        public void Heal(Unit by, Unit t, double amount)
        {
            amount *= by.m_heal;
            double before = t.hp;
            t.hp = GD.Min(t.max_hp, t.hp + amount);
            if (by != t)
            {
                by.healed = by.healed + (t.hp - before);
                if (moba != null && t.hp > before) moba.NoteHeal(by, t);
            }
        }

        public bool Dodge(Unit u)
        {
            if (!Alive(u) || u.stun > 0.0 || u.cd_dodge > 0.0 || u.state == "wind" || u.state == "dodge") return false;
            Vec2 d = u.move.Length() > 0.2 ? u.move : DirOf(u.face);
            u.dodge_dir = d.Normalized();
            u.face = AngleOf(u.dodge_dir);
            u.state = "dodge";
            u.t = 0.3;
            u.cd_dodge = 2.2;
            Emit("dodge", "id", u.id);
            return true;
        }

        public static bool InCastle(Vec2 p, int team) => Keep.Inside(team == 0 ? p : -p);

        // ---------- damage ----------
        public void Damage(Unit src, Unit dst, double amount, double stun = 0.0)
        {
            if (src != null && Vanished(src))
            {
                amount *= VANISH_STRIKE;
                Unvanish(src);
            }
            if (Vanished(dst)) Unvanish(dst);
            if (!Alive(dst) || dst.state == "dodge") return;
            if (_blockers.Count > 0 && src != null && src.hasPos && ShieldBlocks(src.pos, dst))
            {
                Emit("blocked", "id", dst.id, "pos", dst.pos);
                return;
            }
            if (moba != null) amount = moba.ModDamage(src, dst, amount);
            dst.hp -= amount;
            if (amount > 0.0 && Recalling(dst)) RecallCancel(dst);
            if (moba != null) moba.OnDamage(src, dst, amount);
            if (stun > 0.0)
            {
                dst.stun = GD.Max(dst.stun, stun);
                if (moba != null) moba.NoteCc(src, dst);
            }
            Emit("hit", "id", dst.id, "by", src != null ? src.id : "", "dmg", GD.RoundI(amount));
            if (src != null && src.hasPos && src.id != "" && src.team != dst.team)
            {
                dst.hurt_by = src.id;
                dst.hurt_at = time;
            }
            if (dst.hp <= 0.0) Kill(src, dst);
            _next_push = Vec3.Zero;
        }

        public void Kill(Unit src, Unit dst)
        {
            dst.hammer_out = -1;
            RecallCancel(dst);
            dst.hp = 0.0;
            dst.state = "dead";
            dst.beam = "";
            dst.beam2 = "";
            dst.block_until = 0.0;
            dst.whirl_until = 0.0;
            Vec3 push = _next_push;
            _next_push = Vec3.Zero;
            if (push == Vec3.Zero)
            {
                Vec2 away = Vec2.Zero;
                if (src != null && src.hasPos) away = dst.pos - src.pos;
                away = away.Length() > 0.01 ? away.Normalized() : DirOf(dst.face + Math.PI);
                push = new Vec3(away.x * 3.2, 1.6, away.y * 3.2);
            }
            dst.death_push = push;
            if (moba != null)
            {
                moba.OnKill(src, dst);
                return;
            }
            MultiKill(src, dst);
            dst.died_at = time;
            dst.respawn_at = time + RESPAWN_TIME;
            dst.deaths += 1;
            if (src != null)
            {
                kills[src.team] += 1;
                if (src.real) src.kills += 1;
            }
            Emit("death", "id", dst.id, "by", src != null ? src.id : "",
                "push", new List<object> { GD.Snapped(push.x, 0.01), GD.Snapped(push.y, 0.01), GD.Snapped(push.z, 0.01) });
        }

        public void DamageGate(Unit src, Gate g, double amount)
        {
            if (!GateBlocks(g)) return;
            int st = src != null ? src.team : 0;
            if (moba != null && (!moba.GateOpen(g) || st > 1)) return;
            if (moba != null) amount *= moba.GateMult(src);
            g.hp = GD.Max(0.0, g.hp - amount);
            g.hit_at = time;
            if (src != null && src.real) src.gate_dmg += amount;
            Emit("gate_hit", "gate", g.id, "team", g.team, "by", src != null ? src.id : "", "dmg", GD.RoundI(amount));
            if (g.hp <= 0.0)
            {
                g.broken = true;
                g.broken_at = time;
                UpdateGateNav();
                Emit("gate_broken", "gate", g.id, "team", g.team, "by", src != null ? src.id : "");
            }
        }

        public int Melee(Unit u, double reach, double arc, double dmg, double stun = 0.0)
        {
            Vec2 fwd = DirOf(u.face);
            int hits = 0;
            bool spare_mon = moba != null && u.minion && !u.summon;
            for (int oi = 0; oi < units.Count; oi++)
            {
                Unit o = units[oi];
                if (o.team == u.team || !Alive(o)) continue;
                if (spare_mon && o.team > 1) continue;
                Vec2 off = o.pos - u.pos;
                double d = off.Length();
                if (d > reach + UNIT_R) continue;
                if (arc > -1.0 && d > 0.3 && fwd.Dot(off / d) < arc) continue;
                Damage(u, o, dmg, stun);
                hits += 1;
            }
            foreach (var g in gates)
            {
                if (g.team == u.team || !GateBlocks(g)) continue;
                Vec2 cp = SegClosest(u.pos, g.a, g.b);
                Vec2 off2 = cp - u.pos;
                double d2 = off2.Length();
                if (d2 > reach + g.r + 0.3) continue;
                if (arc > -1.0 && d2 > 0.3 && fwd.Dot(off2 / d2) < arc - 0.2) continue;
                DamageGate(u, g, dmg * CLASSES[u.cls].gate);
                hits += 1;
            }
            if (moba != null && u.atk == "attack") hits += moba.MeleeTowers(u, reach, arc, dmg);
            else if (moba != null) hits += moba.AbilityKing(u, dmg, u.pos, reach + 0.3, fwd, arc - 0.3);
            return hits;
        }

        public void Shoot(Unit u, double angle, double dmg, double aoe, double speed, double reach)
        {
            Vec2 d = DirOf(angle);
            string kind = ShotKind(u, aoe);
            projectiles.Add(new Proj { id = _next_proj, team = u.team, owner = u.id, pos = u.pos + d * 0.6, from = u.pos, hasFrom = true,
                vel = d * speed, dmg = dmg, aoe = aoe, life = reach / speed, kind = kind, basic = u.atk == "attack",
                gate_mult = CLASSES[u.cls].gate, high = HeightAt(u.pos) >= 1.5 });
            Emit("proj", "pid", _next_proj, "kind", ShotKind(u, aoe));
            _next_proj += 1;
        }

        string ShotKind(Unit u, double aoe) => u.shot ?? (aoe > 0.0 ? "fire" : "arrow");

        void ResolveAttack(Unit u)
        {
            ClassDef c = CLASSES[u.cls];
            double dmg = Stat(u, SK.dmg);
            if (u.atk == "attack")
            {
                if (moba != null) dmg *= moba.kits.OnBasic(u);
                if (c.ranged)
                {
                    if (c.proj_speed <= 0.0) return;
                    Shoot(u, u.face, dmg * (u.cls == "mage" ? MAGE_BOLT : 1.0), Stat(u, SK.aoe), Stat(u, SK.proj_speed), Stat(u, SK.range));
                }
                else
                {
                    _basic_by = u.id;
                    Melee(u, Stat(u, SK.range), Stat(u, SK.arc), dmg);
                    _basic_by = "";
                }
                return;
            }
            switch (AbilityOf(u))
            {
                case "pierce":
                    PierceShot(u, dmg);
                    u.cd_ability = PIERCE_CD;
                    return;
                case "meteor":
                    CallMeteor(u, dmg);
                    u.cd_ability = METEOR_CD;
                    return;
            }
            switch (c.ability)
            {
                case "bash":
                    Melee(u, 2.3, 0.3, dmg * 0.7, 1.3);
                    break;
                case "spin":
                    Melee(u, 2.8, -2.0, dmg * 1.15);
                    break;
                case "volley":
                    for (int i = 0; i < 5; i++) Shoot(u, u.face + (i - 2) * 0.13, dmg * 0.8, 0.0, c.proj_speed, c.range);
                    break;
                case "nova":
                    Melee(u, NOVA_R, -2.0, dmg * 1.4);
                    Emit("nova", "id", u.id);
                    break;
                case "sanctuary":
                {
                    double amount = SANCTUARY_HEAL * (u.up ? 1.4 : 1.0);
                    foreach (var a in units)
                        if (Alive(a) && a.team == u.team && a.pos.DistanceTo(u.pos) <= SANCTUARY_R && time - a.sanct_t >= SANCT_ONCE)
                        {
                            a.sanct_t = time;
                            Heal(u, a, amount);
                        }
                    Emit("sanctuary", "id", u.id, "team", u.team);
                    break;
                }
            }
        }

        // ---------- stepping ----------
        public void Step(double dt = TICK)
        {
            if (ended) return;
            time += dt;
            for (int ui = 0; ui < units.Count; ui++)
            {
                Unit u = units[ui];
                if (u.bot && time >= u.think_at)
                {
                    double every = AiEvery(u);
                    u.think_at = time + every;
                    u.ai_dt = every;
                    Think(u);
                }
                else if (u.bot && u.cls == "knight" && projectiles.Count > 0 && Alive(u) && !Blocking(u) && u.kq == null)
                    ShieldReflex(u);
            }
            _blockers = new List<Unit>();
            foreach (var k in units)
                if (Blocking(k)) _blockers.Add(k);
            for (int ui = 0; ui < units.Count; ui++) StepUnit(units[ui], dt);
            Separate();
            StepProjectiles(dt);
            StepWorld(dt);
            if (moba != null) moba.Step(dt);
            if (time >= match_time) Finish("time");
        }

        void StepUnit(Unit u, double dt)
        {
            if (u.state == "dead")
            {
                if (time >= u.respawn_at) Respawn(u);
                return;
            }
            if (u.state == "idle" && u.mon >= 0 && u.stun <= 0.0 && u.move == Vec2.Zero)
            {
                u.cd_dodge = GD.Max(0.0, u.cd_dodge - dt);
                u.cd_ability = GD.Max(0.0, u.cd_ability - dt);
                return;
            }
            if (Recalling(u)) StepRecall(u);
            u.cd_dodge = GD.Max(0.0, u.cd_dodge - dt);
            u.cd_ability = GD.Max(0.0, u.cd_ability - dt * u.m_cdr / (moba != null && u.rk != null ? moba.RankCd(u, "q") : 1.0));
            StepBeam(u, dt);
            StepWhirl(u, dt);
            if (u.stun > 0.0)
            {
                u.stun -= dt;
                return;
            }
            double speed = Stat(u, SK.speed);
            switch (u.state)
            {
                case "wind":
                    u.t -= dt;
                    if (CLASSES[u.cls].ability == "lunge" && u.atk == "ability")
                    {
                        u.pos += DirOf(u.face) * 15.0 * dt;
                        if (!u.lunge_hit)
                        {
                            int hit = Melee(u, 1.1, 0.2, Stat(u, SK.dmg) * 2.0);
                            u.lunge_hit = hit > 0;
                        }
                    }
                    if (u.t <= 0.0)
                    {
                        if (!(CLASSES[u.cls].ability == "lunge" && u.atk == "ability")) ResolveAttack(u);
                        u.state = "recover";
                        u.t = Stat(u, SK.recover);
                    }
                    return;
                case "recover":
                    u.t -= dt;
                    if (!NetMoves(u)) u.pos += u.move * speed * 0.25 * dt;
                    if (u.t <= 0.0) u.state = "idle";
                    return;
                case "dodge":
                    u.t -= dt;
                    if (!NetMoves(u)) u.pos += u.dodge_dir * DODGE_SPEED * dt;
                    if (u.t <= 0.0) u.state = "idle";
                    return;
                case "dash":
                    if (moba != null) moba.kits.StepDash(u, dt);
                    else u.state = "idle";
                    return;
            }
            double mult = MoveMult(u);
            bool beaming = u.beam != "";
            bool shield_up = Blocking(u);
            if (u.move.Length() > 0.08)
            {
                if (!NetMoves(u)) u.pos += u.move * speed * mult * dt;
                if (NetMoves(u)) { }
                else if (Whirling(u)) { }
                else if (shield_up) u.face = GD.LerpAngle(u.face, AngleOf(u.move), GD.Min(1.0, dt * 2.5));
                else if (!beaming) u.face = GD.LerpAngle(u.face, AngleOf(u.move), GD.Min(1.0, dt * 14.0));
                u.state = "move";
            }
            else u.state = "idle";
        }

        // ---------- client-side prediction (0.18.4) ----------
        public const double DODGE_SPEED = 13.0;

        public static double WaterDepth(Vec2 p)
        {
            if (Land.RiverOff(p) > 1.6) return 0.0;
            return GD.Max(0.0, Land.WATER_Y - HeightAt(p));
        }

        public double MoveMult(Unit u, double mult = 1.0)
        {
            double wd = WaterDepth(u.pos);
            if (wd > 0.0) mult *= GD.Lerp(1.0, WATER_MOVE, GD.Clamp(wd / 0.35, 0.0, 1.0));
            if (u.beam != "") mult = GD.Min(mult, BEAM_MOVE);
            if (Blocking(u)) mult = GD.Min(mult, BLOCK_MOVE);
            return mult;
        }

        public bool ClientDrivable(Unit u)
        {
            if (!Alive(u) || u.stun > 0.0) return false;
            if (u.state == "wind" && CLASSES[u.cls].ability == "lunge" && u.atk == "ability") return false;
            return u.state == "idle" || u.state == "move" || u.state == "recover" || u.state == "dodge" || u.state == "wind";
        }

        bool NetMoves(Unit u) => u.net_driven && ClientDrivable(u);

        public void PredictStep(Unit u, Vec2 move, double dt)
        {
            double speed = Stat(u, SK.speed);
            switch (u.state)
            {
                case "dodge":
                    u.pos += u.dodge_dir * DODGE_SPEED * dt;
                    u.t -= dt;
                    if (u.t <= 0.0) u.state = "idle";
                    break;
                case "recover":
                    u.pos += move * speed * 0.25 * dt;
                    u.t -= dt;
                    if (u.t <= 0.0) u.state = "idle";
                    break;
                case "wind":
                    u.t -= dt;
                    if (u.t <= 0.0)
                    {
                        u.state = "recover";
                        u.t = Stat(u, SK.recover);
                    }
                    break;
                default:
                    if (move.Length() > 0.08)
                    {
                        u.pos += move * speed * MoveMult(u) * dt;
                        if (!Whirling(u) && u.beam == "")
                            u.face = GD.LerpAngle(u.face, AngleOf(move), GD.Min(1.0, dt * (Blocking(u) ? 2.5 : 14.0)));
                        u.state = "move";
                    }
                    else u.state = "idle";
                    break;
            }
            u.pos = ClampToField(PushOut(ClampToField(u.pos), UNIT_R, u.team));
        }

        public bool AcceptClientPos(Unit u, Vec2 p, double face, double elapsed)
        {
            if (!ClientDrivable(u)) return false;
            double top = GD.Max(Stat(u, SK.speed) * MoveMult(u), u.state == "dodge" ? DODGE_SPEED : 0.0);
            if (p.DistanceTo(u.pos) > top * GD.Clamp(elapsed, 0.0, 0.5) * 1.35 + 0.6) return false;
            u.pos = ClampToField(PushOut(ClampToField(p), UNIT_R, u.team));
            u.face = face;
            return true;
        }

        public bool BlockedPoint(Vec2 p, int team, double r)
        {
            foreach (int wi in _bucket_walls[Bucket(p)])
            {
                Wall w = walls[wi];
                if (p.DistanceTo(SegClosest(p, w.a, w.b)) < w.r + r) return true;
            }
            foreach (var g in gates)
                if (g.team != team && GateBlocks(g) && p.DistanceTo(SegClosest(p, g.a, g.b)) < g.r + r) return true;
            return false;
        }

        public Vec2 PushOut(Vec2 p, double r, int team = -1)
        {
            int bi = Bucket(p);
            foreach (int oi in _bucket_obs[bi])
            {
                Obstacle ob = obstacles[oi];
                Vec2 off = p - ob.p;
                double min_d = ob.r + r;
                double d = off.Length();
                if (d < min_d) p = ob.p + (d > 0.001 ? off / d : new Vec2(1f, 0f)) * min_d;
            }
            for (int pass_i = 0; pass_i < 3; pass_i++)
            {
                Vec2 before = p;
                foreach (int wi in _bucket_walls[bi])
                {
                    Wall w = walls[wi];
                    p = PushSeg(p, w.a, w.b, w.r + r);
                }
                if (p.DistanceSquaredTo(before) < 0.000001) break;
            }
            foreach (var g in gates)
                if (team != g.team && GateBlocks(g) && !LetsOut(g, p)) p = PushSeg(p, g.a, g.b, g.r + r);
            return p;
        }

        public void Knockback(Unit u, Vec2 push)
        {
            int steps = Math.Max(1, (int)Math.Ceiling(push.Length() / 0.25));
            Vec2 p = u.pos;
            for (int i = 0; i < steps; i++)
            {
                Vec2 q = ClampToField(p + push / (double)steps);
                if (BlockedPoint(q, u.team, UNIT_R)) break;
                p = q;
            }
            u.pos = ClampToField(PushOut(p, UNIT_R, u.team));
        }

        Vec2 PushSeg(Vec2 p, Vec2 a, Vec2 b, double min_d)
        {
            Vec2 cp = SegClosest(p, a, b);
            Vec2 off = p - cp;
            double d = off.Length();
            if (d >= min_d) return p;
            if (d < 0.001)
            {
                Vec2 n = new Vec2(-(b - a).y, (b - a).x).Normalized();
                return cp + n * min_d;
            }
            return cp + off / d * min_d;
        }

        public Vec2 ClampToField(Vec2 p) => new Vec2(GD.Clamp(p.x, -HALF_W, HALF_W), GD.Clamp(p.y, -HALF_L, HALF_L));

        readonly Dictionary<string, (Vec2 p, int epoch)> _po_cache = new Dictionary<string, (Vec2, int)>();
        int _po_epoch = 0;
        int _po_tick = 0;
        public const double SEP_CELL = 0.9;
        /// <summary>false: the Godot sim's separation exactly (see Separate); true: every pair in neighbouring cells pushes.</summary>
        public static bool FIX_SEPARATE = false;

        void Separate()
        {
            var live = new List<Unit>();
            foreach (var u in units)
                if (Alive(u)) live.Add(u);
            int n = live.Count;
            var pos = new Vec2[n];
            for (int i = 0; i < n; i++) pos[i] = live[i].pos;
            double r2 = UNIT_R * 2.0;
            var cells = new Dictionary<Vec2i, List<int>>();
            var keys = new Vec2i[n];
            for (int i = 0; i < n; i++)
            {
                Vec2i k = new Vec2i((int)Math.Floor(pos[i].x / SEP_CELL), (int)Math.Floor(pos[i].y / SEP_CELL));
                keys[i] = k;
                if (!cells.TryGetValue(k, out var lst)) cells[k] = new List<int> { i };
                else if (FIX_SEPARATE) lst.Add(i);
                // (else: GDScript's `(lst as PackedInt32Array).append(i)` appended to a copy -- each cell only ever held
                // its first unit, so two units in one cell never pushed apart. Kept for parity with the Godot server.)
            }
            for (int i = 0; i < n; i++)
            {
                Vec2 pa = pos[i];
                Vec2i ck = keys[i];
                for (int dx = 0; dx < 3; dx++)
                    for (int dy = 0; dy < 3; dy++)
                    {
                        if (!cells.TryGetValue(new Vec2i(ck.x + dx - 1, ck.y + dy - 1), out var lst)) continue;
                        foreach (int j in lst)
                        {
                            if (j <= i) continue;
                            Vec2 off = pos[j] - pa;
                            double dd = off.LengthSquared();
                            if (dd < r2 * r2 && dd > 0.00000001)
                            {
                                double d = Math.Sqrt(dd);
                                Vec2 push = off / d * (r2 - d) * 0.5;
                                pa -= push;
                                pos[j] += push;
                            }
                        }
                    }
                pos[i] = pa;
            }
            for (int i = 0; i < n; i++) live[i].pos = pos[i];
            _po_tick += 1;
            if (_po_tick % 30 == 0)
            {
                _po_epoch += 1;
                _po_cache.Clear();
            }
            foreach (var u in units)
            {
                if (!Alive(u)) continue;
                if (_po_cache.TryGetValue(u.id, out var pc) && pc.epoch == _po_epoch && pc.p == u.pos) continue;
                u.pos = ClampToField(PushOut(ClampToField(u.pos), UNIT_R, u.team));
                _po_cache[u.id] = (u.pos, _po_epoch);
            }
        }

        void StepProjectiles(double dt)
        {
            if (projectiles.Count == 0) return;
            var tpos = new List<Vec2>[] { new List<Vec2>(), new List<Vec2>(), new List<Vec2>() };
            var tunit = new List<Unit>[] { new List<Unit>(), new List<Unit>(), new List<Unit>() };
            foreach (var o in units)
            {
                if (!Alive(o)) continue;
                int ti = o.team == 0 ? 0 : (o.team == 1 ? 1 : 2);
                tpos[ti].Add(o.pos);
                tunit[GD.ClampI(o.team, 0, 2)].Add(o);
            }
            double hit_r2 = (UNIT_R + 0.25) * (UNIT_R + 0.25);
            for (int i = projectiles.Count - 1; i > -1; i--)
            {
                Proj p = projectiles[i];
                if (p.kind == "hammer")
                {
                    if (StepHammer(p, dt, tunit)) projectiles.RemoveAt(i);
                    continue;
                }
                Vec2 prev = p.pos;
                p.pos += p.vel * dt;
                bool shielded = false;
                foreach (var k in _blockers)
                {
                    if (k.team != p.team)
                    {
                        Vec2[] sg = ShieldSeg(k);
                        if (SegCross(prev, p.pos, sg[0], sg[1]))
                        {
                            shielded = true;
                            break;
                        }
                    }
                }
                if (shielded)
                {
                    Emit("blocked", "pos", p.pos);
                    Emit("proj_end", "pid", p.id, "pos", p.pos);
                    projectiles.RemoveAt(i);
                    continue;
                }
                p.life -= dt;
                Unit hit = null;
                int et = p.team >= 0 ? (1 - p.team) : -1;
                int[] foe_teams = et < 0 ? new[] { 0, 1, 2 } : (p.team <= 1 ? new[] { et, 2 } : new[] { 0, 1 });
                if (et >= 0 && moba != null && moba.LaneMinion(p.owner)) foe_teams = new[] { et };
                Vec2 from = p.hasFrom ? p.from : prev;
                p.hasFrom = false;
                double best_t = GD.INF;
                Vec2 impact = Vec2.Zero;
                foreach (int t in foe_teams)
                {
                    var arr = tpos[t];
                    for (int k = 0; k < arr.Count; k++)
                    {
                        Vec2 c = arr[k];
                        Vec2 cp = SegClosest(c, from, p.pos);
                        if (c.DistanceSquaredTo(cp) < hit_r2)
                        {
                            Unit o = tunit[t][k];
                            double along = from.DistanceSquaredTo(cp);
                            if (Alive(o) && along < best_t)
                            {
                                best_t = along;
                                hit = o;
                                impact = cp;
                            }
                        }
                    }
                }
                if (p.kind == "pierce")
                {
                    var already = p.hit ?? new List<string>();
                    by_id.TryGetValue(p.owner, out Unit owner_p);
                    foreach (int t2 in foe_teams)
                    {
                        var arr2 = tpos[t2];
                        for (int k2 = 0; k2 < arr2.Count; k2++)
                        {
                            Unit o2 = tunit[t2][k2];
                            if (already.Contains(o2.id) || !Alive(o2)) continue;
                            if (arr2[k2].DistanceSquaredTo(SegClosest(arr2[k2], from, p.pos)) < hit_r2)
                            {
                                already.Add(o2.id);
                                _next_push = PushAlong(p.vel, 4.0, 1.4);
                                Damage(owner_p, o2, p.dmg, p.stun);
                                Emit("pierce_hit", "id", o2.id, "pos", o2.pos);
                            }
                        }
                    }
                    p.hit = already;
                    hit = null;
                }
                if (hit != null) p.pos = impact;
                bool blocked = false;
                Gate hit_gate = null;
                int hit_tw = -1, hit_kg = -1;
                int pb = Bucket(p.pos);
                foreach (int oi in _bucket_obs_proj[pb])
                {
                    Obstacle ob = obstacles[oi];
                    if (p.pos.DistanceTo(ob.p) < ob.r)
                    {
                        blocked = true;
                        hit_tw = ob.tw;
                        hit_kg = ob.kg;
                        break;
                    }
                }
                if (!blocked)
                {
                    bool high = p.high;
                    foreach (int wi in _bucket_walls_proj[pb])
                    {
                        Wall w = walls[wi];
                        if (high && (w.kind == "wall" || w.kind == "backwall")) continue;
                        if (p.pos.DistanceTo(SegClosest(p.pos, w.a, w.b)) < w.r * 0.8)
                        {
                            blocked = true;
                            break;
                        }
                    }
                }
                if (!blocked && !p.high && Land.KeepDist(p.pos) >= Keep.R - 3.0 && Land.KeepDist(p.pos) <= Keep.R + 3.0)
                {
                    foreach (var g in gates)
                        if (g.team != p.team && GateBlocks(g) && p.pos.DistanceTo(SegClosest(p.pos, g.a, g.b)) < g.r * 0.8)
                        {
                            hit_gate = g;
                            blocked = true;
                            break;
                        }
                }
                if (hit == null && !blocked && p.life > 0.0 && Math.Abs(p.pos.x) < HALF_W + 2 && Math.Abs(p.pos.y) < HALF_L + 2) continue;
                if (!by_id.TryGetValue(p.owner, out Unit owner)) owner = Unit.Pseudo(null, p.team, null);
                bool spell_p = p.spell != null;
                if (hit_gate != null && !spell_p) DamageGate(owner, hit_gate, p.dmg * p.gate_mult);
                bool basic_p = p.basic && !spell_p;
                if (hit_tw >= 0 && moba != null && hit == null && basic_p)
                    moba.HitTower(owner, hit_tw, p.dmg, p.hasFrom ? p.from : (owner.hasPos ? owner.pos : Vec2.Inf));
                if (hit_kg >= 0 && moba != null && hit == null) moba.HitKing(owner, hit_kg, p.dmg);
                else if (moba != null && !basic_p && p.aoe > 0.0) moba.AbilityKing(owner, p.dmg * 0.6, p.pos, p.aoe);
                _basic_by = p.basic ? p.owner : "";
                if (p.aoe > 0.0)
                {
                    if (hit != null)
                    {
                        _next_push = PushAlong(p.vel, 3.6, 1.4);
                        Damage(owner, hit, p.dmg);
                    }
                    bool spare_mon = moba != null && moba.LaneMinion(p.owner);
                    for (int oi = 0; oi < units.Count; oi++)
                    {
                        Unit o = units[oi];
                        if (o != hit && o.team != p.team && Alive(o) && o.pos.DistanceTo(p.pos) <= p.aoe && !(spare_mon && o.team > 1))
                        {
                            _next_push = PushFrom(p.pos, o.pos, 4.0, 2.4);
                            Damage(owner, o, p.dmg * 0.6);
                        }
                    }
                    Emit("boom", "pos", p.pos);
                }
                else if (hit != null)
                {
                    _next_push = PushAlong(p.vel, 3.2, 1.2);
                    Damage(owner, hit, p.dmg, p.stun);
                    if (spell_p && moba != null) moba.kits.ProjHit(p, hit);
                }
                _basic_by = "";
                Emit("proj_end", "pid", p.id, "pos", p.pos);
                projectiles.RemoveAt(i);
            }
        }

        int _gate_tick = 0;

        void StepWorld(double dt)
        {
            _gate_tick += 1;
            bool gate_look = _gate_tick % 3 == 0;
            foreach (var g in gates)
            {
                if (!gate_look) continue;
                bool open = open_gates;
                if (GateBlocks(g))
                {
                    var near = moba != null ? moba.UnitsNear(g.c, GATE_OPEN_RADIUS) : units;
                    foreach (var u in near)
                        if (u.team == g.team && Alive(u) && u.pos.DistanceTo(g.c) < GATE_OPEN_RADIUS)
                        {
                            open = true;
                            break;
                        }
                    if (!open && g.hasIn)
                        foreach (var u in near)
                            if (u.team != g.team && Alive(u) && LetsOut(g, u.pos) && u.pos.DistanceTo(g.c) < GATE_OPEN_RADIUS)
                            {
                                open = true;
                                break;
                            }
                }
                if (open != g.open)
                {
                    g.open = open;
                    if (!open_gates) Emit(open ? "gate_open" : "gate_close", "gate", g.id, "team", g.team);
                }
            }
            StepMeteors(dt);
        }

        void Finish(string reason)
        {
            ended = true;
            end_reason = reason;
            if (score[0] != score[1]) winner = score[0] > score[1] ? 0 : 1;
            else if (moba != null && moba.Tiebreak() >= 0) winner = moba.Tiebreak();
            else if (kills[0] != kills[1]) winner = kills[0] > kills[1] ? 0 : 1;
            else winner = -1;
            Emit("end", "winner", winner, "reason", reason);
        }

        public void FinishNow(string reason) => Finish(reason);

        public void SetupMoba(string hero, long seed_value)
        {
            moba = new Moba();
            moba.Begin(this, hero, seed_value);
        }

        public void NavTo(Unit u, Vec2 goal, double stop = 0.5)
        {
            if (u.pos.DistanceTo(goal) <= stop)
            {
                u.move = Vec2.Zero;
                return;
            }
            if (u.unstick > 0.0)
            {
                u.move = u.unstick_dir;
                return;
            }
            bool replan = u.path.Count == 0 || u.path_goal.DistanceTo(goal) > 1.5 || time - u.path_at > 1.5
                || u.path_ver != nav_version || u.path_i >= u.path.Count;
            if (replan)
            {
                u.path = FindPath(u.team, u.pos, goal);
                u.path_i = 0;
                u.path_goal = goal;
                u.path_at = time;
                u.path_ver = nav_version;
            }
            var path = u.path;
            while (u.path_i < path.Count && u.pos.DistanceTo(path[u.path_i]) < 0.75) u.path_i += 1;
            Vec2 target = u.path_i >= path.Count ? goal : path[u.path_i];
            Vec2 d = target - u.pos;
            u.move = d.Length() > 0.05 ? d.Normalized() : Vec2.Zero;
        }

        double AiEvery(Unit u)
        {
            if (moba != null && (u.minion || u.mon >= 0) && !u.hero) return MINION_AI_EVERY;
            return AI_EVERY;
        }

        public void UnstickCheck(Unit u)
        {
            double every = u.ai_dt;
            u.unstick = GD.Max(0.0, u.unstick - every);
            if (u.move.Length() > 0.1 && u.pos.DistanceTo(u.last_pos) < 0.1 * every / AI_EVERY)
            {
                u.stuck_t += every;
                if (u.stuck_t >= 0.75)
                {
                    double side = rng.Randf() < 0.5 ? 1.0 : -1.0;
                    u.unstick_dir = (new Vec2(-u.move.y, u.move.x) * side - u.move * 0.3).Normalized();
                    u.unstick = 0.6;
                    u.stuck_t = 0.0;
                    u.path = new List<Vec2>();
                }
            }
            else u.stuck_t = 0.0;
            u.last_pos = u.pos;
        }

        void Think(Unit u)
        {
            if (moba != null) moba.Think(u);
        }

        public bool ThinkPriest(Unit u)
        {
            if (AbilityOf(u) == "resurrect" && u.cd_ability <= 0.0 && ResurrectTarget(u) != null)
            {
                u.move = Vec2.Zero;
                return Resurrect(u);
            }
            if (IsNecro(u))
            {
                double reach = CLASSES["priest"].range;
                Unit foe = NearestEnemy(u, reach);
                if (foe != null)
                {
                    u.move = Vec2.Zero;
                    return Beam(u);
                }
                Unit near = NearestEnemy(u, 16.0);
                if (near != null)
                {
                    NavTo(u, near.pos, reach * 0.8);
                    return true;
                }
                return false;
            }
            Unit best = null;
            double worst = 0.98;
            foreach (var a in units)
            {
                if (a.id == u.id || a.team != u.team || !Alive(a)) continue;
                double d = u.pos.DistanceTo(a.pos);
                double ratio = a.hp / GD.Max(1.0, a.max_hp);
                if (d <= 16.0 && ratio < worst)
                {
                    worst = ratio;
                    best = a;
                }
            }
            if (best == null) return false;
            if (u.pos.DistanceTo(best.pos) > CLASSES["priest"].range * 0.7) NavTo(u, best.pos, 1.0);
            else u.move = Vec2.Zero;
            Beam(u);
            int nearN = 0;
            foreach (var a in units)
                if (a.team == u.team && Alive(a) && a.pos.DistanceTo(u.pos) <= SANCTUARY_R && a.hp < a.max_hp * 0.7) nearN += 1;
            if (nearN >= 2 && AbilityOf(u) == "sanctuary") StartAttack(u, "ability");
            return true;
        }

        bool ShieldReflex(Unit u)
        {
            Vec2 incoming = Vec2.Zero;
            double soonest = 0.7;
            foreach (var p in projectiles)
            {
                if (p.team == u.team) continue;
                Vec2 v = p.vel;
                double vv = v.LengthSquared();
                if (vv < 0.01) continue;
                double t = (u.pos - p.pos).Dot(v) / vv;
                if (t < 0.0 || t > soonest) continue;
                if ((p.pos + v * t).DistanceTo(u.pos) < 1.3)
                {
                    soonest = t;
                    incoming = -v.Normalized();
                }
            }
            if (incoming == Vec2.Zero) return false;
            if (u.hp >= u.max_hp * 0.5 && NearestEnemy(u, Stat(u, SK.range) + UNIT_R + 0.3) != null) return false;
            u.face = AngleOf(incoming);
            Block(u);
            return true;
        }

        public void Fight(Unit u, Unit foe)
        {
            ClassDef c = CLASSES[u.cls];
            double d = u.pos.DistanceTo(foe.pos);
            if (u.bot && u.up && (u.cls == "rogue" || u.cls == "ranger" || u.cls == "mage") && BotUpgradeAbility(u, foe)) return;
            double reach = Stat(u, SK.range);
            bool kq = u.kq != null;
            if (c.ranged)
            {
                if (d < reach * 0.45) u.move = (u.pos - foe.pos).Normalized();
                else if (d > reach * 0.85) NavTo(u, foe.pos, 0.5);
                else u.move = Vec2.Zero;
                if (d <= reach * 0.9)
                {
                    u.face = AngleOf(foe.pos - u.pos);
                    bool nova_now = c.ability == "nova" && MeleeCount(u, NOVA_R) >= 2;
                    if (!kq && u.cd_ability <= 0.0 && (nova_now || (c.ability != "nova" && rng.Randf() < 0.35)))
                        StartAttack(u, "ability");
                    else StartAttack(u, "attack");
                }
                return;
            }
            if (d <= reach + UNIT_R + 0.1)
            {
                u.move = Vec2.Zero;
                u.face = AngleOf(foe.pos - u.pos);
                string ab = c.ability;
                int crowd = MeleeCount(u, 2.8);
                if (!kq && u.cd_ability <= 0.0 && ((ab == "spin" && crowd >= 2) || ab == "bash" || rng.Randf() < 0.3))
                    StartAttack(u, "ability");
                else StartAttack(u, "attack");
                return;
            }
            if (!kq && c.ability == "lunge" && d < 5.5 && u.cd_ability <= 0.0)
            {
                u.face = AngleOf(foe.pos - u.pos);
                StartAttack(u, "ability");
                return;
            }
            NavTo(u, foe.pos, reach * 0.8);
        }

        int MeleeCount(Unit u, double r)
        {
            int n = 0;
            foreach (var o in units)
                if (o.team != u.team && Alive(o) && o.pos.DistanceTo(u.pos) <= r) n += 1;
            return n;
        }

        // ---------- the Crusader's Hammer Throw (0.30.5) ----------
        public const double HAMMER_RANGE = 9.0;
        public const double HAMMER_SPEED = 17.0;
        public const double HAMMER_CD = 10.0;
        public const double HAMMER_HIT_R = 0.55;

        bool ThrowHammer(Unit u)
        {
            if (!Alive(u) || u.stun > 0.0 || u.cd_ability > 0.0 || u.state == "wind" || u.state == "dodge" || u.hammer_out >= 0) return false;
            Aim(u, HAMMER_RANGE);
            Vec2 d = DirOf(u.face);
            int id = _next_proj;
            projectiles.Add(new Proj { id = id, team = u.team, owner = u.id, pos = u.pos + d * 0.6, from = u.pos, hasFrom = true,
                vel = d * HAMMER_SPEED, dmg = Stat(u, SK.dmg), aoe = 0.0, life = 99.0, kind = "hammer", gate_mult = 0.0, high = false,
                @out = true, trav = 0.0, hit = new List<string>() });
            Emit("proj", "pid", id, "kind", "hammer");
            _next_proj += 1;
            u.hammer_out = id;
            u.cd_ability = HAMMER_CD;
            u.state = "recover";
            u.t = 0.25;
            Emit("attack", "id", u.id, "kind", "ability", "ability", "hammer");
            return true;
        }

        bool StepHammer(Proj p, double dt, List<Unit>[] tunit)
        {
            by_id.TryGetValue(p.owner, out Unit owner);
            if (owner == null || !Alive(owner) || owner.hammer_out != p.id) return true;
            Vec2 prev = p.pos;
            if (p.@out)
            {
                p.pos += p.vel * dt;
                p.trav = p.trav + p.vel.Length() * dt;
                if (p.trav >= HAMMER_RANGE || BlockedPoint(p.pos, p.team, 0.15) || Math.Abs(p.pos.x) > HALF_W || Math.Abs(p.pos.y) > HALF_L)
                {
                    p.pos = BlockedPoint(p.pos, p.team, 0.15) ? prev : p.pos;
                    p.@out = false;
                    p.hit = new List<string>();
                }
            }
            else
            {
                Vec2 to = owner.pos - p.pos;
                double step = HAMMER_SPEED * dt;
                if (to.Length() <= GD.Max(step, 0.7))
                {
                    owner.hammer_out = -1;
                    return true;
                }
                p.vel = to.Normalized() * HAMMER_SPEED;
                p.pos += p.vel * dt;
            }
            double r = UNIT_R + HAMMER_HIT_R;
            var targets = new List<Unit>(tunit[1 - p.team]);
            targets.AddRange(tunit[2]);
            foreach (var o in targets)
            {
                if (p.hit.Contains(o.id) || !Alive(o)) continue;
                if (o.pos.DistanceTo(p.pos) < r)
                {
                    p.hit.Add(o.id);
                    _next_push = PushAlong(p.vel, 4.6, 2.2);
                    Damage(owner, o, p.dmg);
                }
            }
            if (moba != null && !p.hit.Contains("king") && moba.KingInReach(owner, p.pos, HAMMER_HIT_R) >= 0)
            {
                p.hit.Add("king");
                moba.AbilityKing(owner, p.dmg, p.pos, HAMMER_HIT_R);
            }
            return false;
        }

        // ---------- the High Priest's Resurrection (0.31.1) ----------
        public const double RESURRECT_R = 6.0;
        public const double RESURRECT_CD = 30.0;
        public const double RESURRECT_HP = 0.4;

        public Unit ResurrectTarget(Unit u)
        {
            Unit best = null;
            double latest = double.NegativeInfinity;
            foreach (var a in units)
            {
                if (a.team != u.team || a.state != "dead" || a.id == u.id) continue;
                if (a.pos.DistanceTo(u.pos) <= RESURRECT_R && a.died_at > latest)
                {
                    latest = a.died_at;
                    best = a;
                }
            }
            return best;
        }

        bool Resurrect(Unit u)
        {
            if (!Alive(u) || u.stun > 0.0 || u.cd_ability > 0.0 || u.state == "wind" || u.state == "dodge") return false;
            Unit a = ResurrectTarget(u);
            if (a == null) return false;
            a.max_hp = Stat(a, SK.hp);
            a.hp = a.max_hp * RESURRECT_HP;
            a.state = "idle";
            a.t = 0.0;
            a.stun = 0.0;
            a.respawn_at = GD.INF;
            u.cd_ability = RESURRECT_CD;
            u.face = AngleOf(a.pos - u.pos);
            u.state = "recover";
            u.t = 0.4;
            Emit("resurrect", "id", a.id, "by", u.id, "team", u.team, "pos", a.pos);
            return true;
        }

        // ---------- the Necromancer's drain (0.31.2) ----------
        public const double DRAIN_DPS = 14.0;
        public const double NECRO_ALLY_HEAL = 22.0;
        public const double DRAIN_CHUNK = 7.0;
        public const double DRAIN_SELF = 0.5;
        public const double MAGE_BOLT = 0.9;

        public bool IsNecro(Unit u) => u.cls == "priest" && u.up;

        bool NecroBeam(Unit u)
        {
            double reach = CLASSES["priest"].range;
            by_id.TryGetValue(u.beam, out Unit foe);
            if (foe == null || !Alive(foe) || foe.team == u.team || u.pos.DistanceTo(foe.pos) > reach + 1.0) foe = NearestEnemy(u, reach);
            if (foe == null)
            {
                u.beam = "";
                u.beam2 = "";
                return false;
            }
            if (u.beam != foe.id) Emit("drain", "id", u.id, "to", foe.id);
            u.beam = foe.id;
            u.beam_until = time + BEAM_HOLD;
            u.face = AngleOf(foe.pos - u.pos);
            Unit ally = BeamTarget(u);
            u.beam2 = ally != null && ally.hp < ally.max_hp - 0.5 ? ally.id : "";
            return true;
        }

        void StepDrain(Unit u, Unit foe, double dt)
        {
            double take = DRAIN_DPS * dt;
            u.hp = GD.Min(u.max_hp, u.hp + take * DRAIN_SELF);
            u.drain_acc = u.drain_acc + take;
            if (u.drain_acc >= DRAIN_CHUNK)
            {
                double chunk = u.drain_acc;
                u.drain_acc = 0.0;
                Damage(u, foe, chunk);
            }
            by_id.TryGetValue(u.beam2, out Unit ally);
            if (ally != null && Alive(ally) && u.pos.DistanceTo(ally.pos) <= CLASSES["priest"].range + 1.0)
                Heal(u, ally, NECRO_ALLY_HEAL * dt * BeamShare(ally));
            else u.beam2 = "";
        }

        double BeamShare(Unit t)
        {
            if (t.beam_heal_t == time) return BEAM_STACK;
            t.beam_heal_t = time;
            return 1.0;
        }

        // ---------- the killing blow's push (0.31.20) ----------
        public Vec3 PushAlong(Vec2 v, double speed, double up)
        {
            Vec2 d = v.Length() > 0.01 ? v.Normalized() : new Vec2(0.0f, 1.0f);
            return new Vec3(d.x * speed, up, d.y * speed);
        }

        public Vec3 PushFrom(Vec2 from, Vec2 to, double speed, double up)
        {
            Vec2 d = to - from;
            d = d.Length() > 0.01 ? d.Normalized() : DirOf(rng.Randf() * GD.TAU);
            return new Vec3(d.x * speed, up, d.y * speed);
        }

        // ---------- predicted ability starts (0.31.23, online) ----------
        public bool PredictAbility(Unit u)
        {
            if (!CanAct(u) || u.cd_ability > 0.0) return false;
            switch (AbilityOf(u))
            {
                case "block": return Block(u);
                case "whirlwind": return Whirl(u);
                case "hammer":
                    u.cd_ability = HAMMER_CD;
                    return StartAttack(u, "ability");
                case "resurrect":
                    u.cd_ability = RESURRECT_CD;
                    return StartAttack(u, "ability");
                default:
                    return StartAttack(u, "ability");
            }
        }

        // ---------- multi-kills (0.31.29) ----------
        public const double MULTI_WINDOW = 4.0;
        public static readonly string[] MULTI_NAMES = { "", "", "DOUBLE KILL", "TRIPLE KILL", "QUADRA KILL", "PENTA KILL", "LEGENDARY" };

        void MultiKill(Unit src, Unit dst)
        {
            if (src == null || !src.hasPos || src.team == dst.team || !by_id.ContainsKey(src.id)) return;
            int n = 1;
            if (time - src.mk_t <= MULTI_WINDOW) n = src.mk_n + 1;
            src.mk_n = n;
            src.mk_t = time;
            if (n >= 2)
            {
                src.best_multi = Math.Max(src.best_multi, n);
                Emit("multikill", "id", src.id, "team", src.team, "n", n, "name", MULTI_NAMES[Math.Min(n, MULTI_NAMES.Length - 1)]);
            }
        }

        // ---------- the three upgrades' own abilities (0.31.32) ----------
        public const double VANISH_TIME = 4.0;
        public const double VANISH_CD = 14.0;
        public const double VANISH_STRIKE = 2.0;

        public bool Vanished(Unit u) => time < u.vanish_until && Alive(u);

        bool Vanish(Unit u)
        {
            if (!CanAct(u) || u.cd_ability > 0.0) return false;
            u.vanish_until = time + VANISH_TIME;
            u.cd_ability = VANISH_CD;
            Emit("vanish", "id", u.id, "team", u.team, "until", time + VANISH_TIME);
            return true;
        }

        void Unvanish(Unit u)
        {
            if (u.vanish_until > time)
            {
                u.vanish_until = time;
                Emit("unvanish", "id", u.id);
            }
        }

        public const double PIERCE_RANGE = 30.0;
        public const double PIERCE_SPEED = 42.0;
        public const double PIERCE_DMG = 2.2;
        public const double PIERCE_CD = 9.0;

        void PierceShot(Unit u, double dmg)
        {
            Vec2 d = DirOf(u.face);
            projectiles.Add(new Proj { id = _next_proj, team = u.team, owner = u.id, pos = u.pos + d * 0.6, from = u.pos, hasFrom = true,
                vel = d * PIERCE_SPEED, dmg = dmg * PIERCE_DMG, aoe = 0.0, life = PIERCE_RANGE / PIERCE_SPEED, kind = "pierce",
                gate_mult = 0.6, hit = new List<string>(), high = HeightAt(u.pos) >= 1.5 });
            Emit("proj", "pid", _next_proj, "kind", "pierce");
            _next_proj += 1;
        }

        public const double METEOR_RANGE = 12.0;
        public const double METEOR_DELAY = 1.0;
        public const double METEOR_R = 3.2;
        public const double METEOR_DMG = 2.4;
        public const double METEOR_BURN = 3.5;
        public const double BURN_DPS = 9.0;
        public const double METEOR_CD = 12.0;
        public List<Meteor> meteors = new List<Meteor>();

        void CallMeteor(Unit u, double dmg)
        {
            Unit foe = NearestEnemy(u, METEOR_RANGE, true);
            Vec2 at = foe != null ? foe.pos : u.pos + DirOf(u.face) * METEOR_RANGE * 0.75;
            at = PushOut(at, 0.2);
            meteors.Add(new Meteor { team = u.team, owner = u.id, at = at, t_hit = time + METEOR_DELAY, dmg = dmg * METEOR_DMG, burn_until = -1.0 });
            Emit("meteor_warn", "id", u.id, "team", u.team, "pos", at, "delay", METEOR_DELAY);
        }

        Unit OwnerOr(Unit owner, int team) => owner ?? Unit.Pseudo("", team, null);

        void StepMeteors(double dt)
        {
            for (int i = meteors.Count - 1; i > -1; i--)
            {
                Meteor m = meteors[i];
                by_id.TryGetValue(m.owner, out Unit owner);
                if (m.burn_until < 0.0)
                {
                    if (time < m.t_hit) continue;
                    for (int oi = 0; oi < units.Count; oi++)
                    {
                        Unit o = units[oi];
                        if (o.team == m.team || !Alive(o)) continue;
                        double d = o.pos.DistanceTo(m.at);
                        if (d <= METEOR_R)
                        {
                            _next_push = PushFrom(m.at, o.pos, 4.6, 3.8);
                            Damage(OwnerOr(owner, m.team), o, m.dmg * (1.0 - 0.5 * d / METEOR_R), 0.4);
                        }
                    }
                    if (moba != null)
                    {
                        int kt = moba.KingInReach(Unit.Pseudo(null, m.team, null), m.at, METEOR_R);
                        if (kt >= 0)
                        {
                            double kd = GD.Max(0.0, moba.KingPos(kt).DistanceTo(m.at) - Moba.KING_R);
                            moba.HitKing(OwnerOr(owner, m.team), kt, m.dmg * (1.0 - 0.5 * GD.Min(1.0, kd / METEOR_R)));
                        }
                    }
                    m.burn_until = time + METEOR_BURN;
                    Emit("meteor_hit", "team", m.team, "pos", m.at, "burn", METEOR_BURN);
                    continue;
                }
                if (time >= m.burn_until)
                {
                    meteors.RemoveAt(i);
                    continue;
                }
                for (int oi = 0; oi < units.Count; oi++)
                {
                    Unit o = units[oi];
                    if (o.team != m.team && Alive(o) && o.pos.DistanceTo(m.at) <= METEOR_R * 0.8)
                    {
                        o.hp -= BURN_DPS * dt;
                        if (o.hp <= 0.0)
                        {
                            o.hp = 0.1;
                            Damage(OwnerOr(owner, m.team), o, 1.0);
                        }
                    }
                }
                if (moba != null && moba.KingInReach(Unit.Pseudo(null, m.team, null), m.at, METEOR_R * 0.8) >= 0)
                {
                    m.kburn = m.kburn + BURN_DPS * dt;
                    if (m.kburn >= BURN_DPS * 0.5)
                    {
                        moba.AbilityKing(OwnerOr(owner, m.team), m.kburn, m.at, METEOR_R * 0.8);
                        m.kburn = 0.0;
                    }
                }
            }
        }

        bool BotUpgradeAbility(Unit u, Unit foe)
        {
            if (u.cd_ability > 0.0 || !CanAct(u) || foe == null) return false;
            double d = u.pos.DistanceTo(foe.pos);
            switch (AbilityOf(u))
            {
                case "vanish":
                    if (d > 3.0 && d < 11.0 && !Vanished(u)) return Vanish(u);
                    break;
                case "pierce":
                    if (d > 6.0 && d < PIERCE_RANGE * 0.9)
                    {
                        int line = 0;
                        Vec2 dirv = (foe.pos - u.pos).Normalized();
                        foreach (var o in units)
                        {
                            if (o.team != u.team && Alive(o))
                            {
                                Vec2 off = o.pos - u.pos;
                                double along = off.Dot(dirv);
                                if (along > 0.0 && along < PIERCE_RANGE && Math.Abs(off.Cross(dirv)) < 1.0) line += 1;
                            }
                        }
                        if (line >= 2 || d > 16.0)
                        {
                            u.face = AngleOf(foe.pos - u.pos);
                            return StartAttack(u, "ability");
                        }
                    }
                    break;
                case "meteor":
                    if (d < METEOR_RANGE)
                    {
                        int crowd = 0;
                        foreach (var o in units)
                            if (o.team != u.team && Alive(o) && o.pos.DistanceTo(foe.pos) <= METEOR_R) crowd += 1;
                        if (crowd >= 2 || (d > 5.0 && rng.Randf() < 0.2))
                        {
                            u.face = AngleOf(foe.pos - u.pos);
                            return StartAttack(u, "ability");
                        }
                    }
                    break;
            }
            return false;
        }
    }
}
