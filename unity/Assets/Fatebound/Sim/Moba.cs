// The 5v5 (moba.gd, 0.31.155-0.31.222): heroes, levels and skill points, lanes and minion waves, towers (League's
// rules), the Kings (the hearts), ultimates, gold and the shop, the jungle and its epic monsters, the bots. The sim's
// hooks hand over to this when SetupMoba() made one. Tables in MobaData.cs.
using System;
using System.Collections.Generic;

namespace Fatebound.Sim
{
    public sealed partial class Moba
    {
        public SiegeSim s;
        public MobaKits kits;
        public MobaVision vision;
        public Rng rng = new Rng();
        public List<Tower> towers = new List<Tower>();
        public List<TowerShot> shots = new List<TowerShot>();
        public double wave_at = WAVE_FIRST;
        public int waves = 0;
        int _mid = 0;
        public List<string>[] heroes = { new List<string>(), new List<string>() };
        public Dictionary<string, string> hero_of = new Dictionary<string, string>();
        double _immune_note = -10.0;
        double _far_note = -10.0;
        public KingSt[] kings = { new KingSt(), new KingSt() };
        public List<Camp> camps = new List<Camp>();
        public List<Rain> rains = new List<Rain>();
        public bool[] boss_go = { false, false };
        public bool[] wyrm_go = { false, false };
        public int[] wyrm_stacks = { 0, 0 };
        public bool first_blood = false;
        public double[] last_respawn = { double.NegativeInfinity, double.NegativeInfinity };
        public Dictionary<string, int[]> epic_kills = new Dictionary<string, int[]> { { "lord", new[] { 0, 0 } }, { "wyrm", new[] { 0, 0 } } };
        double _boss_check = 0.0;
        int _jid = 0;
        int _zid = 0;
        double _shop_clock = 0.0;

        public static string BotLabel(Unit u)
        {
            string n = u.bot_name ?? "";
            if (n == "") n = BOT_NAMES[(int)(Math.Abs((long)GHash.Str(u.id ?? "")) % BOT_NAMES.Length)];
            return "Bot " + n;
        }

        // ---------- the units by GRID-m cell (0.31.160) ----------
        Dictionary<Vec2i, List<Unit>> _grid = new Dictionary<Vec2i, List<Unit>>();
        double _grid_time = -1.0;
        int _grid_n = -1;
        static readonly List<Unit> EMPTY = new List<Unit>();

        public List<Unit> UnitsNear(Vec2 p, double r)
        {
            if (s.time != _grid_time || s.units.Count != _grid_n)
            {
                _grid_time = s.time;
                _grid_n = s.units.Count;
                _grid = new Dictionary<Vec2i, List<Unit>>();
                foreach (var u in s.units)
                {
                    Vec2 up = u.pos;
                    Vec2i c = new Vec2i((int)Math.Floor(up.x / GRID), (int)Math.Floor(up.y / GRID));
                    if (!_grid.TryGetValue(c, out var cell)) _grid[c] = new List<Unit> { u };
                    else cell.Add(u);
                }
            }
            double rr = r + GRID_PAD;
            int x0 = (int)Math.Floor((p.x - rr) / GRID);
            int x1 = (int)Math.Floor((p.x + rr) / GRID);
            int y0 = (int)Math.Floor((p.y - rr) / GRID);
            int y1 = (int)Math.Floor((p.y + rr) / GRID);
            if (x0 == x1 && y0 == y1) return _grid.TryGetValue(new Vec2i(x0, y0), out var one) ? one : new List<Unit>();
            var o = new List<Unit>();
            for (int cx = x0; cx < x1 + 1; cx++)
                for (int cy = y0; cy < y1 + 1; cy++)
                    if (_grid.TryGetValue(new Vec2i(cx, cy), out var cell)) o.AddRange(cell);
            return o;
        }

        // ---------- setup ----------
        public void Begin(SiegeSim sim, string my_hero, long seed_value)
        {
            s = sim;
            rng.Seed = unchecked((ulong)seed_value);
            kits = new MobaKits();
            kits.Setup(this);
            s.match_time = MATCH_5V5;
            foreach (var b in TOWERS_BLUE) AddTower(0, b.lane, b.tier, b.p);
            foreach (var b in TOWERS_BLUE) AddTower(1, b.lane >= 0 ? 2 - b.lane : -1, b.tier, -b.p);
            foreach (var g in s.gates)
            {
                g.hp = GATE_HP_5V5;
                g.max_hp = GATE_HP_5V5;
            }
            s.open_gates = true;
            s.UpdateGateNav();
            for (int t = 0; t < 2; t++)
            {
                Oracle o = s.oracles[t];
                o.state = "home";
                o.pos = SiegeSim.Throne(t);
                kings[t] = new KingSt { hp = KING_HP, max_hp = KING_HP, dead = false, next = 0.0, quiet = 0.0 };
                s.obstacles.Add(new Obstacle { p = o.pos, r = KING_R, kind = "moba_king", kg = t, team = t });
            }
            s.BuildBuckets();
            s.BuildNav();
            for (int t = 0; t < 2; t++)
            {
                string mine = t == 0 ? (my_hero != "" ? (HEROES.ContainsKey(my_hero) ? my_hero : "knight") : "") : "";
                var team = Draft(mine);
                int i = 0;
                foreach (var u in s.units)
                {
                    if (u.team != t || i >= team.Count) continue;
                    var pk = team[i];
                    string post = pk.post;
                    MakeHero(u, pk.hid, (t == 0 && i == 0 && mine != "") ? -1 : POST_LANE[post], post == "top" || post == "mid");
                    u.post = post;
                    i += 1;
                }
            }
            var nr = new Rng();
            nr.Seed = unchecked((ulong)(seed_value * 7919 + 13));
            var pool = new List<string>(BOT_NAMES);
            var all = new List<string>(heroes[0]);
            all.AddRange(heroes[1]);
            foreach (var hid in all)
            {
                int k = nr.RandiRange(0, pool.Count - 1);
                s.by_id[hid].bot_name = pool[k];
                pool.RemoveAt(k);
            }
            vision = new MobaVision();
            vision.Setup(this);
            for (int t = 0; t < 2; t++)
                foreach (var c in CAMPS_BLUE) AddCamp(c.kind, t, t == 0 ? c.p : -c.p);
            AddCamp("lord", -1, BOSS_P);
            AddCamp("wyrm", -1, WYRM_P);
        }

        void AddTower(int team, int lane, int tier, Vec2 p)
        {
            int id = towers.Count;
            towers.Add(new Tower { id = id, team = team, lane = lane, tier = tier, p = p, hp = TOWER_HP[tier], max_hp = TOWER_HP[tier],
                dead = false, target = "", ramp = 0, ramp_id = "", next = 0.0 });
            s.obstacles.Add(new Obstacle { p = p, r = TOWER_R, kind = "moba_tower", tw = id, team = team });
        }

        public List<(string hid, string post)> Draft(string mine)
        {
            var o = new List<(string hid, string post)>();
            var taken = new List<string>();
            var open = new List<string>(POSTS);
            if (mine != "")
            {
                string mp = ROLE_POST.TryGetValue(MobaKits.RoleOf(mine), out var rp) ? rp : "top";
                o.Add((mine, mp));
                taken.Add(mine);
                open.Remove(mp);
            }
            foreach (var post in new[] { "bot", "support", "mid", "jungle", "top" })
            {
                if (!open.Contains(post)) continue;
                string hid = "";
                foreach (var role in POST_ROLES[post])
                {
                    var c = new List<string>();
                    foreach (var h in HERO_ORDER)
                        if (!taken.Contains(h) && MobaKits.RoleOf(h) == role) c.Add(h);
                    if (c.Count > 0)
                    {
                        hid = c[rng.RandiRange(0, c.Count - 1)];
                        break;
                    }
                }
                if (hid == "")
                {
                    var any = new List<string>();
                    foreach (var h in HERO_ORDER)
                        if (!taken.Contains(h)) any.Add(h);
                    hid = any[rng.RandiRange(0, any.Count - 1)];
                }
                taken.Add(hid);
                o.Add((hid, post));
            }
            var head = mine != "" ? o.GetRange(0, 1) : new List<(string hid, string post)>();
            var rest = o.GetRange(head.Count, o.Count - head.Count);
            GSort.Sort(rest, (a, b) => Array.IndexOf(POSTS, a.post) < Array.IndexOf(POSTS, b.post));
            head.AddRange(rest);
            return head;
        }

        void MakeHero(Unit u, string hid, int lane, bool king_runner)
        {
            HeroDef h = HEROES[hid];
            u.cls = h.cls;
            u.up = h.up;
            u.hero = true;
            u.hid = hid;
            if (MobaKits.KitQ(hid) != "")
            {
                u.kq = MobaKits.KitQ(hid);
                u.look = hid;
            }
            if (HERO_SHOT.TryGetValue(hid, out var shot)) u.shot = shot;
            if (HERO_SCALE.TryGetValue(hid, out var sc)) u.mscale = sc;
            u.lane = lane;
            u.kr = king_runner && u.bot;
            u.level = 1;
            u.xp = 0.0;
            u.picks = new List<List<string>>();
            u.ups = new ODict<string, int>();
            u.rk = new ODict<string, int>();
            u.rk["q"] = 0; u.rk["w"] = 0; u.rk["e"] = 0; u.rk["r"] = 0;
            u.sp = 1;
            u.ult_cd = 0.0;
            u.gold = GOLD_START;
            u.gold_total = 0.0;
            u.items = new List<string>();
            u.bought = new List<string>();
            u.buffs = new ODict<string, double>();
            heroes[u.team].Add(u.id);
            hero_of[u.id] = hid;
            Apply(u);
            s.Respawn(u, true);
            if (u.bot) BotLearn(u);
        }

        public void SwapHero(Unit u, string hid)
        {
            if (!HEROES.ContainsKey(hid) || u.hid == hid) return;
            double ratio = u.hp / GD.Max(1.0, u.max_hp);
            HeroDef h = HEROES[hid];
            u.cls = h.cls;
            u.up = h.up;
            u.hid = hid;
            u.kq = null; u.look = null; u.shot = null; u.mscale = 1.0;
            if (MobaKits.KitQ(hid) != "")
            {
                u.kq = MobaKits.KitQ(hid);
                u.look = hid;
            }
            if (HERO_SHOT.TryGetValue(hid, out var shot)) u.shot = shot;
            if (HERO_SCALE.TryGetValue(hid, out var sc)) u.mscale = sc;
            u.cd_ability = 0.0;
            u.cd_w = 0.0;
            u.cd_e = 0.0;
            hero_of[u.id] = hid;
            var offers = u.picks ?? new List<List<string>>();
            for (int i = 0; i < offers.Count; i++) offers[i] = Offer(u);
            Apply(u);
            if (s.Alive(u)) u.hp = GD.Max(1.0, u.max_hp * ratio);
        }

        // ---------- stats ----------
        public double Stat(Unit u, SK key, double b)
        {
            if (HERO_BASE.TryGetValue(u.hid ?? "", out var hb) && hb[(int)key].HasValue) b = hb[(int)key].Value;
            switch (key)
            {
                case SK.hp:
                    return b * (u.up ? 1.15 : 1.0) * u.m_hp;
                case SK.dmg:
                    return b * (u.up ? 1.1 : 1.0) * u.m_dmg;
                case SK.speed:
                    return b * u.m_spd * (s.time < u.bl_until ? WARCRY_SPD : 1.0) * (kits != null ? kits.SpeedMult(u) : 1.0);
                case SK.windup:
                case SK.recover:
                    return b * u.m_as * (s.time < u.bl_until ? WARCRY_AS : 1.0) * (kits != null ? kits.SwingMult(u) : 1.0);
            }
            return b;
        }

        public void Apply(Unit u)
        {
            var ups = u.ups;
            int UpsGet(string k) => ups != null ? ups.Get(k, 0) : 0;
            double lv = (double)(u.level - 1);
            double before = u.max_hp;
            var it = ItemStats(u);
            u.m_hp = HERO_HP * (1.0 + LEVEL_GROW * lv) * (1.0 + 0.15 * (double)UpsGet("hp")) * (1.0 + it.Get("hp", 0.0))
                * (1.0 + WYRM_HIDE * (double)wyrm_stacks[GD.ClampI(u.team, 0, 1)]);
            u.m_dmg = (1.0 + LEVEL_GROW * lv) * (1.0 + 0.15 * (double)UpsGet("dmg")) * (1.0 + it.Get("dmg", 0.0));
            u.m_spd = 1.0 + 0.08 * (double)UpsGet("spd") + it.Get("spd", 0.0);
            u.m_as = Math.Pow(0.88, (double)UpsGet("as")) / (1.0 + it.Get("as", 0.0));
            u.m_cdr = 1.0 + 0.25 * (double)UpsGet("cdr") + it.Get("cdr", 0.0);
            u.m_ls = 0.08 * (double)UpsGet("ls") + it.Get("ls", 0.0);
            u.m_regen = 0.01 * (double)UpsGet("regen") + it.Get("regen", 0.0);
            u.m_armor = GD.Min(ARMOR_MAX, it.Get("armor", 0.0));
            u.m_heal = 1.0 + it.Get("heal", 0.0);
            double after = s.Stat(u, SK.hp);
            u.max_hp = after;
            if (before > 0.0 && s.Alive(u)) u.hp = GD.Min(after, u.hp + GD.Max(0.0, after - before));
            else if (u.hp > after) u.hp = after;
        }

        public double Need(int level) => XP_BASE + XP_STEP * (double)(level - 1);

        public void AddXp(Unit u, double x)
        {
            if (u == null || !u.hero || u.level >= LEVEL_MAX) return;
            u.xp = u.xp + x;
            while (u.level < LEVEL_MAX && u.xp >= Need(u.level))
            {
                u.xp = u.xp - Need(u.level);
                u.level = u.level + 1;
                u.sp = u.sp + 1;
                Apply(u);
                s.Emit("level", "id", u.id, "team", u.team, "level", u.level);
                if (u.bot) BotLearn(u);
            }
            if (u.level >= LEVEL_MAX) u.xp = 0.0;
        }

        // ---------- 0.31.217: skill points ----------
        public int Rank(Unit u, string slot) => u.rk != null ? u.rk.Get(slot, 0) : 0;

        public int RankNeed(string slot, int r)
        {
            if (slot == "r") return r <= 1 ? ULT_LEVEL : ULT_RANK2;
            return 2 * r - 1;
        }

        public bool CanLearn(Unit u, string slot)
        {
            if (!u.hero || u.sp <= 0 || !SKILL_MAX.ContainsKey(slot)) return false;
            int r = Rank(u, slot);
            return r < SKILL_MAX[slot] && u.level >= RankNeed(slot, r + 1);
        }

        static readonly string[] SLOTS = { "q", "w", "e", "r" };

        public List<string> Learnable(Unit u)
        {
            var o = new List<string>();
            foreach (var slot in SLOTS)
                if (CanLearn(u, slot)) o.Add(slot);
            return o;
        }

        public bool Learn(Unit u, string slot)
        {
            if (!CanLearn(u, slot)) return false;
            u.sp = u.sp - 1;
            var rk = u.rk;
            rk[slot] = rk.Get(slot, 0) + 1;
            u.rk = rk.Duplicate();
            s.Emit("learn", "id", u.id, "team", u.team, "slot", slot, "rank", rk[slot]);
            if (slot == "r") s.Emit("ult_ready", "id", u.id, "team", u.team, "rank", UltRank(u));
            return true;
        }

        void BotLearn(Unit u)
        {
            while (u.sp > 0)
            {
                var opts = Learnable(u);
                if (opts.Count == 0) return;
                if (opts.Contains("r"))
                {
                    Learn(u, "r");
                    continue;
                }
                string best = opts[0];
                foreach (var o in opts)
                    if (Rank(u, o) < Rank(u, best)) best = o;
                Learn(u, best);
            }
        }

        public double RankPower(Unit u, string slot) => 1.0 + RANK_POWER * (double)Math.Max(0, Rank(u, slot) - 1);

        public double RankCd(Unit u, string slot) => 1.0 - RANK_CD * (double)Math.Max(0, Rank(u, slot) - 1);

        List<string> Offer(Unit u)
        {
            var pool = new List<string>();
            foreach (var up in UPGRADES)
            {
                string k = up.key;
                if ((u.ups != null ? u.ups.Get(k, 0) : 0) >= UP_MAX) continue;
                if (u.cls == "priest" && (k == "dmg" || k == "ls")) continue;
                pool.Add(k);
            }
            var o = new List<string>();
            while (o.Count < 3 && pool.Count > 0)
            {
                int i = rng.RandiRange(0, pool.Count - 1);
                o.Add(pool[i]);
                pool.RemoveAt(i);
            }
            return o;
        }

        public bool Pick(Unit u, int i)
        {
            var picks = u.picks;
            if (picks == null || picks.Count == 0) return false;
            var offer = picks[0];
            if (i < 0 || i >= offer.Count) return false;
            string k = offer[i];
            u.ups[k] = u.ups.Get(k, 0) + 1;
            picks.RemoveAt(0);
            Apply(u);
            s.Emit("pick", "id", u.id, "up", k);
            return true;
        }

        // ---------- the match ----------
        public void Step(double dt)
        {
            if (s.time >= wave_at)
            {
                wave_at += s.time < MID_AT ? WAVE_EVERY : (s.time < LATE_AT ? WAVE_EVERY_MID : WAVE_EVERY_LATE);
                waves += 1;
                for (int t = 0; t < 2; t++)
                    for (int l = 0; l < 3; l++) SpawnWave(t, l);
            }
            StepTowers(dt);
            StepKings(dt);
            StepCamps(dt);
            StepRains(dt);
            kits.Step(dt);
            vision.Step(dt);
            bool gold_on = s.time >= WAVE_FIRST;
            var gone = new List<Unit>();
            for (int ui = 0; ui < s.units.Count; ui++)
            {
                Unit u = s.units[ui];
                if (!s.Alive(u))
                {
                    if ((u.minion || u.mon >= 0) && s.time >= u.gone_at) gone.Add(u);
                    if (u.hero && gold_on) u.gold = u.gold + GOLD_PASSIVE * dt;
                    continue;
                }
                if (u.hero)
                {
                    double heal = u.m_regen;
                    if (SiegeSim.InCastle(u.pos, u.team)) heal += FOUNTAIN;
                    if (heal > 0.0 && u.hp < u.max_hp) u.hp = GD.Min(u.max_hp, u.hp + u.max_hp * heal * dt);
                    bool arcane = s.time < u.buffs.Get("arcane", -1.0);
                    u.ult_cd = GD.Max(0.0, u.ult_cd - dt * u.m_cdr * (arcane ? ARCANE_CDR : 1.0));
                    if (arcane && u.cd_ability > 0.0) u.cd_ability = GD.Max(0.0, u.cd_ability - dt * u.m_cdr * (ARCANE_CDR - 1.0));
                    double cdk = dt * u.m_cdr * (arcane ? ARCANE_CDR : 1.0);
                    if (u.cd_w > 0.0) u.cd_w = GD.Max(0.0, u.cd_w - cdk);
                    if (u.cd_e > 0.0) u.cd_e = GD.Max(0.0, u.cd_e - cdk);
                    if (gold_on) u.gold = u.gold + GOLD_PASSIVE * dt;
                    if (u.dance != null) StepDance(u);
                }
                else if (u.summon && s.time >= u.expire) s.Kill(null, u);
            }
            foreach (var u in gone)
            {
                s.units.Remove(u);
                s.by_id.Remove(u.id);
            }
            _shop_clock += dt;
            if (_shop_clock >= 1.0)
            {
                _shop_clock = 0.0;
                for (int t = 0; t < 2; t++)
                    foreach (var hid in heroes[t].ToArray())
                    {
                        if (s.by_id.TryGetValue(hid, out var h) && h.bot && CanShop(h)) BotShop(h);
                    }
            }
            _boss_check += dt;
            if (_boss_check >= 2.0)
            {
                _boss_check = 0.0;
                BossCall();
            }
        }

        public List<string> WaveKinds(int t, int l, int n)
        {
            int sup = 0;
            if (LaneGateDown(t, l)) sup = GatesDown(1 - t) >= 2 ? 2 : 1;
            bool siege = false;
            if (sup == 0) siege = s.time < MID_AT ? (n % 3 == 0) : (s.time < LATE_AT ? (n % 2 == 0) : true);
            var o = new List<string>();
            for (int i = 0; i < sup; i++) o.Add("super");
            int nm = siege && s.time >= MID_AT ? 2 : 3;
            for (int i = 0; i < nm; i++) o.Add("melee");
            if (siege) o.Add("siege");
            for (int i = 0; i < 3; i++) o.Add("caster");
            return o;
        }

        int GatesDown(int team)
        {
            int n = 0;
            foreach (var tw in towers)
                if (tw.team == team && tw.tier == 3 && tw.dead) n += 1;
            return n;
        }

        void SpawnWave(int t, int l)
        {
            int alive = 0;
            foreach (var u in s.units)
                if (u.minion && !u.summon && u.team == t && s.Alive(u)) alive += 1;
            bool lord = LordBuff(t);
            double up = 1.0 + MINION_UP * Math.Floor(s.time / MINION_UP_EVERY);
            var kinds = WaveKinds(t, l, waves);
            Vec2 start = Wp(t, l, 0);
            Vec2 ahead = (Wp(t, l, 1) - start).Normalized();
            Vec2 side = new Vec2(-ahead.y, ahead.x);
            int rows = (int)Math.Ceiling((double)kinds.Count / 2.0);
            var ids = new List<object>();
            for (int k = 0; k < kinds.Count; k++)
            {
                if (alive >= MINION_CAP) break;
                alive += 1;
                Unit u = NewMinion(t, l, kinds[k], up, lord);
                u.wp = 1;
                int row = k / 2;
                int col = k % 2;
                u.pos = start + ahead * (1.3 * (double)(rows - 1 - row) + 0.5) + side * (col == 0 ? 0.8 : -0.8);
                u.face = SiegeSim.AngleOf(ahead);
                u.think_at = s.time + SiegeSim.TICK * (double)(k + 1);
                s.units.Add(u);
                s.by_id[u.id] = u;
                ids.Add(u.id);
            }
            if (ids.Count > 0) s.Emit("wave", "team", t, "lane", l, "ids", ids);
        }

        Unit NewMinion(int t, int l, string mk, double up, bool lord)
        {
            _mid += 1;
            Unit u = s.NewUnit("m" + _mid, t, true);
            u.cls = MINION_CLS[mk];
            u.minion = true;
            u.mk = mk;
            u.lane = l;
            u.m_hp = MINION_KIND_HP[mk] * up * (lord ? LORD_MINION : 1.0);
            u.m_dmg = MINION_KIND_DMG[mk] * up * (lord ? LORD_MINION : 1.0);
            u.m_spd = MINION_SPD;
            if (mk == "super") u.super = true;
            if (MINION_KIND_SCALE.TryGetValue(mk, out var sc)) u.mscale = sc;
            if (lord) u.lordly = true;
            u.max_hp = s.Stat(u, SK.hp);
            u.hp = u.max_hp;
            return u;
        }

        public List<string> PlaceMinions(int t, int l, List<string> kinds, Vec2 at)
        {
            double up = 1.0 + MINION_UP * Math.Floor(s.time / MINION_UP_EVERY);
            Vec2 fwd = t == 0 ? new Vec2(0f, -1f) : new Vec2(0f, 1f);
            int wi = LaneLen(l) - 1;
            for (int i = 0; i < LaneLen(l); i++)
                if ((Wp(t, l, i) - at).Dot(fwd) > 1.0)
                {
                    wi = i;
                    break;
                }
            Vec2 ahead = (Wp(t, l, wi) - at).Normalized();
            Vec2 side = new Vec2(-ahead.y, ahead.x);
            var ids = new List<string>();
            var idsO = new List<object>();
            for (int k = 0; k < kinds.Count; k++)
            {
                Unit u = NewMinion(t, l, kinds[k], up, false);
                u.wp = wi;
                u.pos = at - ahead * (1.3 * (double)(k / 2)) + side * (k % 2 == 0 ? 0.8 : -0.8);
                u.face = SiegeSim.AngleOf(ahead);
                u.think_at = s.time + SiegeSim.TICK * (double)(k + 1);
                s.units.Add(u);
                s.by_id[u.id] = u;
                ids.Add(u.id);
                idsO.Add(u.id);
            }
            if (ids.Count > 0) s.Emit("wave", "team", t, "lane", l, "ids", idsO);
            return ids;
        }

        bool LaneGateDown(int t, int l)
        {
            foreach (var tw in towers)
                if (tw.team == 1 - t && tw.lane == l && tw.tier == 3 && tw.dead) return true;
            return false;
        }

        public Vec2 Wp(int t, int l, int i)
        {
            var pts = LANES[l];
            i = GD.ClampI(i, 0, pts.Length - 1);
            return t == 0 ? pts[i] : pts[pts.Length - 1 - i];
        }

        public int LaneLen(int l) => LANES[l].Length;

        // ---------- towers ----------
        public bool Vulnerable(Tower tw)
        {
            if (tw.dead) return false;
            if (tw.tier == 1) return true;
            foreach (var o in towers)
                if (o.team == tw.team && o.lane == tw.lane && o.tier == tw.tier - 1 && !o.dead) return false;
            return true;
        }

        public int TowersDown(int team)
        {
            int n = 0;
            foreach (var tw in towers)
                if (tw.team == team && tw.dead) n += 1;
            return n;
        }

        public bool GateOpen(Gate g)
        {
            for (int l = 0; l < 3; l++)
            {
                Vec2 end = Wp(1 - g.team, l, LaneLen(l) - 1);
                if (end.DistanceTo(g.c) > 6.0) continue;
                foreach (var tw in towers)
                    if (tw.team == g.team && tw.lane == l && tw.tier == 3 && tw.dead) return true;
            }
            return false;
        }

        int TowerTier(Unit o)
        {
            if (o.summon) return 0;
            if (o.minion)
            {
                switch (o.mk ?? "melee")
                {
                    case "siege":
                    case "super":
                    case "lord":
                        return 1;
                    case "caster": return 3;
                    default: return 2;
                }
            }
            return 4;
        }

        double TowerPct(Unit o)
        {
            if (o.summon) return TOWER_PCT["pet"];
            return TOWER_PCT.TryGetValue(o.mk ?? "melee", out var v) ? v : TOWER_PCT_ELSE;
        }

        void StepTowers(double dt)
        {
            foreach (var tw in towers)
            {
                if (tw.dead) continue;
                s.by_id.TryGetValue(tw.target, out Unit cur);
                if (cur == null || !s.Alive(cur) || cur.pos.DistanceTo(tw.p) > TOWER_RANGE + SiegeSim.UNIT_R) cur = null;
                if (cur == null || !cur.hero)
                {
                    foreach (var hid in heroes[tw.team])
                    {
                        s.by_id.TryGetValue(hid, out Unit h);
                        if (h == null || !s.Alive(h) || s.time - h.hh_at > HELP_FOR || h.pos.DistanceTo(tw.p) > TOWER_HELP_R) continue;
                        s.by_id.TryGetValue(h.hh_by, out Unit a);
                        if (a != null && s.Alive(a) && a.pos.DistanceTo(tw.p) <= TOWER_RANGE + SiegeSim.UNIT_R)
                        {
                            cur = a;
                            break;
                        }
                    }
                }
                if (cur == null)
                {
                    Unit best = null;
                    int bt = 9;
                    double bd = GD.INF;
                    foreach (var o in UnitsNear(tw.p, TOWER_RANGE + SiegeSim.UNIT_R))
                    {
                        if (o.team == tw.team || o.team > 1 || !s.Alive(o)) continue;
                        double d = o.pos.DistanceTo(tw.p);
                        if (d > TOWER_RANGE + SiegeSim.UNIT_R) continue;
                        int tier = TowerTier(o);
                        if (tier < bt || (tier == bt && d < bd))
                        {
                            bt = tier;
                            bd = d;
                            best = o;
                        }
                    }
                    cur = best;
                }
                tw.target = cur != null ? cur.id : "";
                if (s.time - tw.ramp_at > TOWER_RAMP_COOL) tw.ramp = 0;
                if (cur == null || s.time < tw.next) continue;
                tw.next = s.time + TOWER_EVERY;
                double dmg;
                int ramp = 0;
                if (cur.hero)
                {
                    ramp = tw.ramp;
                    dmg = TOWER_HERO_DMG * (1.0 + TOWER_RAMP * (double)ramp) * (1.0 + TOWER_GROW * s.time / 60.0);
                    tw.ramp = Math.Min(ramp + 1, TOWER_RAMP_MAX);
                    tw.ramp_at = s.time + TOWER_FLIGHT;
                }
                else dmg = cur.max_hp * TowerPct(cur);
                shots.Add(new TowerShot { tw = tw.id, target = cur.id, t = TOWER_FLIGHT, dmg = dmg });
                s.Emit("tshot", "tw", tw.id, "id", cur.id, "flight", TOWER_FLIGHT, "ramp", ramp);
            }
            for (int i = shots.Count - 1; i > -1; i--)
            {
                TowerShot sh = shots[i];
                sh.t = sh.t - dt;
                if (sh.t > 0.0) continue;
                shots.RemoveAt(i);
                Tower tw2 = towers[sh.tw];
                if (tw2.dead) continue;
                s.by_id.TryGetValue(sh.target, out Unit u);
                if (u != null && s.Alive(u))
                {
                    s._next_push = Vec3.Zero;
                    s.Damage(Unit.Pseudo("tower" + tw2.id, tw2.team, tw2.p, "idle"), u, sh.dmg);
                }
            }
        }

        public double TowerMult(Unit src)
        {
            if (src != null && src.hero && !(SiegeSim.CLASSES.TryGetValue(src.cls ?? "", out var cd) && cd.ranged)) return MELEE_VS_TOWER;
            if (src != null && src.lordling) return LORD_SIEGE;
            if (LaneMinion(src != null ? src.id : "")) return MINION_TOWER.TryGetValue(src.mk ?? "melee", out var v) ? v : 0.4;
            return 1.0;
        }

        public void HitTower(Unit src, int id, double amount, Vec2 from)
        {
            if (id < 0 || id >= towers.Count) return;
            Tower tw = towers[id];
            int st = src != null ? src.team : -1;
            if (tw.dead || st == tw.team || st < 0 || st > 1) return;
            bool srcBot = src == null || src.bot;
            if (!Vulnerable(tw))
            {
                if (s.time - _immune_note > 1.5 && !srcBot)
                {
                    _immune_note = s.time;
                    s.Emit("tower_immune", "tw", id, "team", tw.team);
                }
                return;
            }
            if (from != Vec2.Inf && !InTowerRange(tw, from))
            {
                if (s.time - _far_note > 1.5 && !srcBot)
                {
                    _far_note = s.time;
                    s.Emit("tower_far", "tw", id, "team", tw.team, "by", src != null ? src.id : "");
                }
                return;
            }
            bool minions_near = false;
            foreach (var o in UnitsNear(tw.p, TOWER_RANGE))
                if (o.minion && o.team == src.team && s.Alive(o) && o.pos.DistanceTo(tw.p) <= TOWER_RANGE)
                {
                    minions_near = true;
                    break;
                }
            if (!minions_near) amount *= BACKDOOR;
            amount *= TowerMult(src);
            double before = tw.hp;
            tw.hp = GD.Max(0.0, tw.hp - amount);
            if (src != null && src.real) src.gate_dmg = src.gate_dmg + GD.Min(amount, before);
            s.Emit("tower_hit", "tw", id, "dmg", GD.RoundI(amount), "by", src != null ? src.id : "");
            if (tw.tier == 1 && s.time < PLATES_UNTIL && tw.hp > 0.0)
            {
                double step = tw.max_hp / (double)PLATES;
                int lost = (int)Math.Floor((tw.max_hp - tw.hp) / step) - (int)Math.Floor((tw.max_hp - before) / step);
                for (int k = 0; k < lost; k++)
                {
                    tw.plates = tw.plates + 1;
                    var paid = new List<object>();
                    foreach (var h in HeroesNear(1 - tw.team, tw.p, 12.0, src))
                    {
                        AddGold(h, GOLD_PLATE, tw.p);
                        paid.Add(h.id);
                    }
                    s.Emit("plate", "tw", id, "team", tw.team, "n", tw.plates, "ids", paid, "gold", GOLD_PLATE);
                }
            }
            if (tw.hp <= 0.0)
            {
                tw.dead = true;
                tw.target = "";
                s.Emit("tower_down", "tw", id, "team", tw.team, "lane", tw.lane, "tier", tw.tier, "by", src != null ? src.id : "");
                int et = 1 - tw.team;
                bool first = TowersDown(0) + TowersDown(1) == 1;
                foreach (var hid in heroes[et].ToArray())
                {
                    s.by_id.TryGetValue(hid, out Unit hh);
                    AddXp(hh, TOWER_XP);
                    AddGold(hh, (double)GOLD_TOWER_GLOBAL[tw.tier], Vec2.Inf);
                }
                var near = HeroesNear(et, tw.p, TOWER_LOCAL_R, src);
                foreach (var h in near)
                {
                    AddGold(h, (double)(GOLD_TOWER_LOCAL + (first ? GOLD_FIRST_TOWER : 0)) / (double)near.Count, tw.p);
                    h.towers = h.towers + 1;
                }
                s.UpdateGateNav();
            }
        }

        List<Unit> HeroesNear(int team, Vec2 p, double r, Unit src)
        {
            var o = new List<Unit>();
            Unit by_h = Credit(src);
            if (by_h != null && by_h.team == team) o.Add(by_h);
            foreach (var hid in heroes[team])
            {
                s.by_id.TryGetValue(hid, out Unit h);
                if (h != null && !o.Contains(h) && s.Alive(h) && h.pos.DistanceTo(p) <= r) o.Add(h);
            }
            return o;
        }

        public AimSt AimStructure(Unit u, double reach)
        {
            AimSt best = null;
            Vec2 fwd = SiegeSim.DirOf(u.face);
            var cands = new List<(Vec2 p, double r)>();
            foreach (var tw in towers)
                if (tw.team != u.team && Vulnerable(tw) && InTowerRange(tw, u.pos)) cands.Add((tw.p, TOWER_R));
            int et = 1 - u.team;
            if (et >= 0 && et <= 1 && !kings[et].dead && KingOpen(et)) cands.Add((KingPos(et), KING_R));
            foreach (var g in s.gates)
                if (g.team != u.team && s.GateBlocks(g) && GateOpen(g)) cands.Add((SiegeSim.SegClosest(u.pos, g.a, g.b), 0.0));
            foreach (var c in cands)
            {
                Vec2 off = c.p - u.pos;
                double d = off.Length();
                double edge = d - c.r;
                if (edge > reach) continue;
                double sc = GD.Max(0.0, edge);
                if (d > 0.01) sc += (1.0 - fwd.Dot(off / d)) * 2.0;
                if (best == null || sc < best.score) best = new AimSt { p = c.p, d = d, score = sc };
            }
            return best;
        }

        public int MeleeTowers(Unit u, double reach, double arc, double dmg)
        {
            if (u.team > 1) return 0;
            Vec2 fwd = SiegeSim.DirOf(u.face);
            int hits = 0;
            foreach (var tw in towers)
            {
                if (tw.dead || tw.team == u.team) continue;
                Vec2 off = tw.p - u.pos;
                double d = off.Length();
                if (d - TOWER_R > reach + 0.3) continue;
                if (arc > -1.0 && d > 0.3 && fwd.Dot(off / d) < arc - 0.3) continue;
                HitTower(u, tw.id, dmg, u.pos);
                hits += 1;
            }
            int t2 = 1 - u.team;
            Vec2 off2 = KingPos(t2) - u.pos;
            double d2 = off2.Length();
            if (!kings[t2].dead && d2 - KING_R <= reach + 0.3 && (arc <= -1.0 || d2 < 0.3 || fwd.Dot(off2 / d2) >= arc - 0.3))
            {
                HitKing(u, t2, dmg);
                hits += 1;
            }
            return hits;
        }

        public bool InTowerRange(Tower tw, Vec2 p) => p.DistanceTo(tw.p) <= TOWER_RANGE + SiegeSim.UNIT_R;

        public Tower TowerInRange(int team_of_tower, Vec2 p, double extra = 0.0)
        {
            foreach (var tw in towers)
                if (tw.team == team_of_tower && !tw.dead && p.DistanceTo(tw.p) <= TOWER_RANGE + extra) return tw;
            return null;
        }

        // ---------- the Kings, the hearts (0.31.156) ----------
        public Vec2 KingPos(int t) => s.oracles[t].pos;

        public bool KingOpen(int t)
        {
            if (kings[t].dead) return false;
            return GatesDown(t) > 0;
        }

        public double KingFrac(int t) => kings[t].hp / kings[t].max_hp;

        public int Tiebreak()
        {
            if (Math.Abs(KingFrac(0) - KingFrac(1)) > 0.001) return KingFrac(1) < KingFrac(0) ? 0 : 1;
            if (TowersDown(0) != TowersDown(1)) return TowersDown(1) > TowersDown(0) ? 0 : 1;
            if (s.kills[0] != s.kills[1]) return s.kills[0] > s.kills[1] ? 0 : 1;
            return -1;
        }

        public Unit KingThreat(int t)
        {
            Unit best = null;
            double bd = KING_GUARD;
            Vec2 kp = KingPos(t);
            foreach (var o in UnitsNear(kp, KING_GUARD))
            {
                if (o.team != t && o.team <= 1 && s.Alive(o))
                {
                    double d = o.pos.DistanceTo(kp);
                    if (d < bd)
                    {
                        bd = d;
                        best = o;
                    }
                }
            }
            return best;
        }

        public void HitKing(Unit src, int t, double amount)
        {
            KingSt k = kings[t];
            int st = src != null ? src.team : -1;
            if (k.dead || st == t || st < 0 || st > 1 || s.ended) return;
            if (!KingOpen(t))
            {
                if (s.time - _immune_note > 1.5 && !(src == null || src.bot))
                {
                    _immune_note = s.time;
                    s.Emit("king_immune", "team", t);
                }
                return;
            }
            if (src.real) src.gate_dmg = src.gate_dmg + GD.Min(amount, k.hp);
            k.hp = GD.Max(0.0, k.hp - amount);
            k.quiet = 0.0;
            s.Emit("king_hit", "team", t, "dmg", GD.RoundI(amount));
            if (k.hp <= 0.0)
            {
                k.dead = true;
                s.score[1 - t] += 1;
                s.Emit("king_down", "team", t, "by", src.id);
                s.FinishNow("king");
            }
        }

        public int KingInReach(Unit src, Vec2 at, double r, Vec2 d = default, double cos_arc = -2.0, double width = -1.0)
        {
            int st = src != null ? src.team : -1;
            if (st < 0 || st > 1) return -1;
            int t = 1 - st;
            if (kings[t].dead) return -1;
            Vec2 off = KingPos(t) - at;
            double dist = off.Length();
            if (width >= 0.0)
            {
                double along = off.Dot(d);
                if (along < -KING_R || along > r + KING_R || Math.Abs(off.Cross(d)) > width + KING_R) return -1;
                return t;
            }
            if (dist > r + KING_R) return -1;
            if (cos_arc > -1.0 && dist > KING_R + 0.8 && d != Vec2.Zero)
            {
                double half = Math.Acos(GD.Clamp(cos_arc, -1.0, 1.0)) + Math.Asin(GD.Clamp(KING_R / dist, 0.0, 1.0));
                if (Math.Abs(d.AngleTo(off)) > half) return -1;
            }
            return t;
        }

        public int AbilityKing(Unit src, double amount, Vec2 at, double r, Vec2 d = default, double cos_arc = -2.0, double width = -1.0)
        {
            int t = KingInReach(src, at, r, d, cos_arc, width);
            if (t < 0) return 0;
            HitKing(src, t, amount);
            return 1;
        }

        void StepKings(double dt)
        {
            for (int t = 0; t < 2; t++)
            {
                KingSt k = kings[t];
                if (k.dead) continue;
                Vec2 kp = KingPos(t);
                var near = new List<Unit>();
                bool any = false;
                foreach (var o in s.units)
                {
                    if (o.team == t || o.team > 1 || !s.Alive(o)) continue;
                    double d = o.pos.DistanceTo(kp);
                    if (d <= KING_GUARD) any = true;
                    if (d <= KING_REACH + SiegeSim.UNIT_R) near.Add(o);
                }
                if (near.Count > 0 && s.time >= k.next)
                {
                    k.next = s.time + KING_EVERY;
                    double dmg = KING_SLAM * (1.0 + TOWER_GROW * s.time / 60.0);
                    s.Emit("king_slam", "team", t);
                    foreach (var o in near)
                    {
                        s._next_push = s.PushFrom(kp, o.pos, 5.0, 2.6);
                        s.Damage(Unit.Pseudo("king" + t, t, kp, "idle"), o, dmg * (o.minion ? KING_SLAM_MINION : 1.0));
                    }
                }
                if (any) k.quiet = 0.0;
                else
                {
                    k.quiet = k.quiet + dt;
                    if (k.quiet >= KING_QUIET && k.hp < k.max_hp) k.hp = GD.Min(k.max_hp, k.hp + k.max_hp * KING_REGEN * dt);
                }
            }
        }

        // ---------- hits and knockouts ----------
        public void OnDamage(Unit src, Unit dst, double amount)
        {
            if (src == null || src.team == dst.team) return;
            if (vision != null && s.by_id.ContainsKey(src.id)) vision.Reveal(src);
            double ls = src.m_ls + kits.LifestealAdd(src);
            if (ls > 0.0 && amount > 0.0 && src.real && s.Alive(src)) s.Heal(src, src, amount * ls);
            if (s._basic_by != "" && s._basic_by == src.id && src.poison_n > 0) kits.PoisonHit(src, dst, amount);
            if (dst.hero && src.hero)
            {
                dst.hh_by = src.id;
                dst.hh_at = s.time;
            }
            if (dst.hero)
            {
                Unit hb = Credit(src);
                if (hb != null)
                {
                    if (dst.hit_log == null) dst.hit_log = new ODict<string, double>();
                    dst.hit_log[hb.id] = s.time;
                }
            }
            if (dst.mon >= 0 && (src.team == 0 || src.team == 1) && s.by_id.ContainsKey(src.id))
            {
                Camp camp = camps[dst.mon];
                camp.hits[src.id] = s.time;
                double lr = Leash(camp);
                switch (camp.reset)
                {
                    case "hard":
                        break;
                    case "soft":
                        if (src.pos.DistanceTo(camp.p) <= lr && dst.pos.DistanceTo(camp.p) <= lr)
                        {
                            camp.reset = "";
                            camp.target = src.id;
                            camp.patience = GD.Max(camp.patience, 0.6);
                        }
                        break;
                    default:
                        s.by_id.TryGetValue(camp.target, out Unit cur);
                        if (cur == null || !s.Alive(cur)) camp.target = src.id;
                        else if (src.pos.DistanceTo(camp.p) <= lr) camp.patience = GD.Min(1.0, camp.patience + 0.15);
                        break;
                }
            }
        }

        public void OnKill(Unit src, Unit dst)
        {
            kits.Clear(dst);
            dst.died_at = s.time;
            dst.deaths = dst.deaths + 1;
            Vec3 push = dst.death_push;
            Unit by_h = Credit(src);
            if (dst.mon >= 0)
            {
                dst.respawn_at = GD.INF;
                dst.gone_at = s.time + MINION_GONE;
                MonsterDown(dst, by_h);
            }
            else if (dst.summon)
            {
                dst.respawn_at = GD.INF;
                dst.gone_at = s.time + MINION_GONE;
            }
            else if (dst.minion)
            {
                dst.respawn_at = GD.INF;
                dst.gone_at = s.time + MINION_GONE;
                var near = new List<Unit>();
                foreach (var hid in heroes[1 - dst.team])
                {
                    s.by_id.TryGetValue(hid, out Unit h);
                    if (h != null && s.Alive(h) && h.pos.DistanceTo(dst.pos) <= XP_R) near.Add(h);
                }
                double mxp = MINION_XP_BY.TryGetValue(dst.mk ?? "melee", out var mx) ? mx : MINION_XP;
                foreach (var h in near) AddXp(h, mxp * (near.Count == 1 ? 1.0 : 0.65));
                if (by_h != null && by_h.team != dst.team)
                {
                    AddGold(by_h, MinionGold(dst), dst.pos, "cs");
                    by_h.lh = by_h.lh + 1;
                }
            }
            else if (dst.hero)
            {
                dst.respawn_at = s.time + RESPAWN_BASE + RESPAWN_LVL * (double)dst.level;
                dst.dance = null;
                Unit killer = KillCredit(dst, by_h);
                int et = 1 - dst.team;
                if (killer != null || (src != null && src.team == et)) s.kills[et] += 1;
                int n = 0;
                if (killer != null)
                {
                    killer.kills = killer.kills + 1;
                    n = Multi(killer, dst);
                }
                double reward = HERO_XP + HERO_XP_LVL * (double)dst.level;
                if (killer != null) AddXp(killer, reward);
                foreach (var hid in heroes[et].ToArray())
                {
                    s.by_id.TryGetValue(hid, out Unit h2);
                    if (h2 != null && h2 != killer && s.Alive(h2) && h2.pos.DistanceTo(dst.pos) <= XP_R) AddXp(h2, reward * 0.5);
                }
                int shown = BountyShown(dst);
                double paid = HeroDownGold(dst, killer);
                PassBuffs(dst, by_h);
                if (killer != null)
                {
                    string kind = "kill";
                    if (!first_blood) kind = "first_blood";
                    else if (n >= 2) kind = "multi";
                    else if (shown >= BOUNTY_SHOW) kind = "shutdown";
                    first_blood = true;
                    s.Emit("kb", "kind", kind, "n", n, "by", killer.id, "id", dst.id, "team", et, "bounty", GD.RoundI(paid),
                        "shut", shown >= BOUNTY_SHOW);
                }
                bool all_down = true;
                foreach (var hid3 in heroes[dst.team])
                {
                    s.by_id.TryGetValue(hid3, out Unit h3);
                    if (h3 != null && s.Alive(h3))
                    {
                        all_down = false;
                        break;
                    }
                }
                if (all_down && (killer != null || (src != null && src.team == et)))
                    s.Emit("ace", "team", et, "by", killer != null ? killer.id : "", "ids", new List<object>(heroes[dst.team]));
            }
            s.Emit("death", "id", dst.id, "by", src != null ? src.id : "",
                "push", new List<object> { GD.Snapped(push.x, 0.01), GD.Snapped(push.y, 0.01), GD.Snapped(push.z, 0.01) },
                "minion", dst.minion, "mon", dst.mon >= 0);
        }

        // ---------- the bots ----------
        public void Think(Unit u)
        {
            if (!s.Alive(u) || u.stun > 0.0 || u.state == "wind" || u.state == "recover" || u.state == "dodge") return;
            s.UnstickCheck(u);
            if (u.mon >= 0) ThinkMonster(u);
            else if (u.summon) ThinkSummon(u);
            else if (u.minion) ThinkMinion(u);
            else ThinkHero(u);
        }

        Vec2 Forward(Unit u) => u.team == 0 ? new Vec2(0f, -1f) : new Vec2(0f, 1f);
        static Vec2 Forward(int team) => team == 0 ? new Vec2(0f, -1f) : new Vec2(0f, 1f);

        void ThinkMinion(Unit u)
        {
            var tg = MinionTarget(u, out int tgTw);
            if (tgTw >= 0)
            {
                u.mt = "";
                u.mt_tw = tgTw;
                HitStructure(u, towers[tgTw]);
                return;
            }
            if (tg != null)
            {
                u.mt = tg.id;
                u.mt_tw = -1;
                s.Fight(u, tg);
                return;
            }
            u.mt = "";
            u.mt_pri = 9;
            ClassDef c = SiegeSim.CLASSES[u.cls];
            double reach = !c.ranged ? ACQ_R : GD.Max(ACQ_R, s.Stat(u, SK.range) * 0.8);
            Tower tw = EnemyTowerNear(u, reach + TOWER_R);
            if (tw != null)
            {
                u.mt_tw = tw.id;
                HitStructure(u, tw);
                return;
            }
            u.mt_tw = -1;
            int eteam = 1 - u.team;
            if (KingOpen(eteam) && u.pos.DistanceTo(KingPos(eteam)) < reach + KING_R + 2.0)
            {
                HitPoint(u, KingPos(eteam), KING_R);
                return;
            }
            March(u);
        }

        /// <summary>League's minion targeting; a unit, or (tw >= 0) an enemy tower, or null.</summary>
        Unit MinionTarget(Unit u, out int tw_out)
        {
            tw_out = -1;
            int team = u.team;
            ClassDef c = SiegeSim.CLASSES[u.cls];
            double acq = !c.ranged ? ACQ_R : GD.Max(ACQ_R, s.Stat(u, SK.range) * 0.8);
            s.by_id.TryGetValue(u.mt, out Unit cur);
            int cur_pri = u.mt_pri;
            if (cur == null || !s.Alive(cur) || cur.team == team || cur.team > 1 || cur.pos.DistanceTo(u.pos) > acq + 3.0 || !CanSee(team, cur))
            {
                cur = null;
                cur_pri = 9;
            }
            bool on_tower = u.mt_tw >= 0;
            Unit best = null;
            int bp = 9;
            double bd = GD.INF;
            if (!on_tower)
            {
                foreach (var hid in heroes[team])
                {
                    s.by_id.TryGetValue(hid, out Unit h);
                    if (h == null || !s.Alive(h) || s.time - h.hh_at > HELP_FOR || h.pos.DistanceTo(u.pos) > HELP_R) continue;
                    s.by_id.TryGetValue(h.hh_by, out Unit a);
                    if (a == null || !s.Alive(a) || !CanSee(team, a)) continue;
                    double da = a.pos.DistanceTo(u.pos);
                    if (da <= acq + 4.0 && (bp > 1 || da < bd))
                    {
                        bp = 1;
                        bd = da;
                        best = a;
                    }
                }
            }
            foreach (var o in UnitsNear(u.pos, acq))
            {
                if (o.team == team || o.team > 1 || !s.Alive(o)) continue;
                double d = o.pos.DistanceTo(u.pos);
                if (d > acq || !CanSee(team, o)) continue;
                int pri;
                if (o.minion)
                {
                    pri = 5;
                    s.by_id.TryGetValue(o.mt, out Unit ot);
                    if (ot != null && ot.team == team) pri = ot.hero ? 2 : 3;
                }
                else if (o.hero) pri = 6;
                else continue;
                if (pri < bp || (pri == bp && d < bd))
                {
                    bp = pri;
                    bd = d;
                    best = o;
                }
            }
            if (bp > 4)
            {
                foreach (var tw in towers)
                {
                    if (tw.team == team || tw.dead || tw.p.DistanceTo(u.pos) > acq + TOWER_R + 2.0) continue;
                    s.by_id.TryGetValue(tw.target, out Unit tt);
                    if (tt != null && tt.team == team && tt.minion)
                    {
                        u.mt_pri = 4;
                        tw_out = tw.id;
                        return null;
                    }
                }
            }
            if (cur != null && cur_pri <= bp) return cur;
            u.mt_pri = bp;
            return best;
        }

        Tower EnemyTowerNear(Unit u, double r)
        {
            Tower best = null;
            double bd = r;
            foreach (var tw in towers)
            {
                if (tw.team == u.team || tw.dead) continue;
                double d = u.pos.DistanceTo(tw.p);
                if (d < bd)
                {
                    bd = d;
                    best = tw;
                }
            }
            return best;
        }

        bool BotRecall(Unit u)
        {
            if (SiegeSim.InCastle(u.pos, u.team) || TowerInRange(1 - u.team, u.pos, 1.0) != null) return false;
            foreach (var o in UnitsNear(u.pos, BOT_RECALL_SAFE))
                if (o.team == 1 - u.team && s.Alive(o) && o.hero && o.pos.DistanceTo(u.pos) < BOT_RECALL_SAFE) return false;
            u.move = Vec2.Zero;
            return s.Act(u.id, "recall");
        }

        void HitStructure(Unit u, Tower tw) => HitPoint(u, tw.p, TOWER_R, TOWER_RANGE - 0.6);

        void HitPoint(Unit u, Vec2 p, double r, double within = double.PositiveInfinity)
        {
            ClassDef c = SiegeSim.CLASSES[u.cls];
            double d = u.pos.DistanceTo(p) - r;
            double reach = GD.Min(s.Stat(u, SK.range) * (c.ranged ? 0.85 : 1.0), within - r);
            if (d > reach)
            {
                s.NavTo(u, p, r + reach * 0.8);
                return;
            }
            u.move = Vec2.Zero;
            u.face = SiegeSim.AngleOf(p - u.pos);
            s.StartAttack(u, "attack", false);
        }

        void March(Unit u)
        {
            int l = u.lane;
            int i = u.wp;
            Vec2 goal = Wp(u.team, l, i);
            if (u.pos.DistanceTo(goal) < 2.5 && i < LaneLen(l) - 1)
            {
                u.wp = i + 1;
                goal = Wp(u.team, l, i + 1);
            }
            if (i >= LaneLen(l) - 1)
            {
                Gate g = GateAt(1 - u.team, goal);
                if (g != null && s.GateBlocks(g))
                {
                    HitGate(u, g);
                    return;
                }
                goal = SiegeSim.Throne(1 - u.team);
            }
            s.NavTo(u, goal, 0.8);
        }

        Gate GateAt(int team, Vec2 p)
        {
            foreach (var g in s.gates)
                if (g.team == team && g.c.DistanceTo(p) < 6.0) return g;
            return null;
        }

        void HitGate(Unit u, Gate g)
        {
            ClassDef c = SiegeSim.CLASSES[u.cls];
            Vec2 cp = SiegeSim.SegClosest(u.pos, g.a, g.b);
            double d = u.pos.DistanceTo(cp);
            double reach = s.Stat(u, SK.range) * (c.ranged ? 0.8 : 1.0);
            if (d > reach + SiegeSim.WALL_R)
            {
                s.NavTo(u, cp + g.@in * -1.2, 0.6);
                return;
            }
            u.move = Vec2.Zero;
            u.face = SiegeSim.AngleOf(cp - u.pos);
            s.StartAttack(u, "attack", false);
        }

        void ThinkHero(Unit u)
        {
            double reach = s.Stat(u, SK.range);
            Unit th = KingThreat(u.team);
            if (th != null && u.pos.DistanceTo(KingPos(u.team)) < 45.0 && u.hp > u.max_hp * 0.35)
            {
                FightH(u, th);
                return;
            }
            int eteam = 1 - u.team;
            if (KingOpen(eteam) && ((u.kr && u.hp > u.max_hp * 0.45) || (EndPush(u.team) && u.hp > u.max_hp * 0.35)))
            {
                foreach (var o in UnitsNear(u.pos, reach + 3.0))
                {
                    if (o.team == eteam && s.Alive(o) && o.hero && o.pos.DistanceTo(u.pos) < reach + 3.0 && CanSee(u.team, o))
                    {
                        FightH(u, o);
                        return;
                    }
                }
                HitPoint(u, KingPos(eteam), KING_R);
                return;
            }
            if (BotUlt(u) || kits.BotSpells(u)) return;
            if (s.Recalling(u))
            {
                u.move = Vec2.Zero;
                return;
            }
            if (u.back)
            {
                if (u.hp >= u.max_hp * 0.92) u.back = false;
                else
                {
                    if (!BotRecall(u)) s.NavTo(u, SiegeSim.Spawn(u.team), 1.5);
                    return;
                }
            }
            if (u.hp < u.max_hp * 0.3 && !SiegeSim.InCastle(u.pos, u.team))
            {
                u.back = true;
                if (!BotRecall(u)) s.NavTo(u, SiegeSim.Spawn(u.team), 1.5);
                return;
            }
            if (boss_go[u.team] && u.hp > u.max_hp * 0.45 && GoLord(u)) return;
            if (wyrm_go[u.team] && u.hp > u.max_hp * 0.4 && GoEpic(u, WyrmUnit(), WYRM_GATHER)) return;
            if (u.cls == "priest" && s.ThinkPriest(u)) return;
            Tower tw = TowerInRange(1 - u.team, u.pos, 0.6);
            if (tw != null && (tw.target == u.id || !OurMinionsNear(u.team, tw.p)))
            {
                Vec2 away = (u.pos - tw.p).Normalized();
                u.move = (away - Forward(u) * 0.6).Normalized();
                return;
            }
            Unit foe = null;
            double fd = reach + 4.0;
            foreach (var o in UnitsNear(u.pos, fd))
            {
                if (o.team == u.team || !s.Alive(o) || !o.hero || !CanSee(u.team, o)) continue;
                double d = o.pos.DistanceTo(u.pos);
                if (d < fd && (TowerInRange(1 - u.team, o.pos) == null || OurMinionsNear(u.team, o.pos)))
                {
                    fd = d;
                    foe = o;
                }
            }
            if (foe != null)
            {
                FightH(u, foe);
                return;
            }
            Unit jm = MonsterOn(u);
            if (jm != null)
            {
                FightH(u, jm);
                return;
            }
            if (u.lane == JUNGLE && ThinkJungle(u)) return;
            Unit m = null;
            double md = GD.Max(reach + 2.0, 7.0);
            foreach (var o in UnitsNear(u.pos, md))
            {
                if (o.team == u.team || !s.Alive(o) || !o.minion || !CanSee(u.team, o)) continue;
                double d2 = o.pos.DistanceTo(u.pos);
                if (d2 < md && TowerInRange(1 - u.team, o.pos) == null)
                {
                    md = d2;
                    m = o;
                }
            }
            if (m != null)
            {
                FightH(u, m);
                return;
            }
            Tower et = EnemyTowerNear(u, reach + 8.0);
            if (et != null && Vulnerable(et) && OurMinionsNear(u.team, et.p) && et.target != u.id)
            {
                HitStructure(u, et);
                return;
            }
            foreach (var g in s.gates)
            {
                if (g.team == u.team || !s.GateBlocks(g) || !GateOpen(g)) continue;
                if (g.c.DistanceTo(u.pos) < reach + 10.0 && OurMinionsNear(u.team, g.c))
                {
                    HitGate(u, g);
                    return;
                }
            }
            int l = u.lane;
            if (l == JUNGLE) l = u.gank;
            if (l < 0) l = 1;
            Unit front = null;
            int fi = -1;
            foreach (var o in s.units)
            {
                if (o.team != u.team || !s.Alive(o) || !o.minion || o.lane != l) continue;
                if (o.wp > fi || (o.wp == fi && o.pos.Dot(Forward(u)) > front.pos.Dot(Forward(u))))
                {
                    fi = o.wp;
                    front = o;
                }
            }
            Vec2 goal = front != null ? front.pos - Forward(u) * 3.0 : HomeTowerSpot(u.team, l);
            s.NavTo(u, goal, 1.2);
        }

        void FightH(Unit u, Unit foe)
        {
            if (u.cls != "priest")
            {
                s.Fight(u, foe);
                return;
            }
            double d = u.pos.DistanceTo(foe.pos);
            if (u.up && d <= SiegeSim.CLASSES["priest"].range - 1.5)
            {
                u.move = Vec2.Zero;
                u.face = SiegeSim.AngleOf(foe.pos - u.pos);
                s.Beam(u);
                return;
            }
            s.NavTo(u, foe.pos, u.up ? SiegeSim.CLASSES["priest"].range - 2.5 : 6.0);
        }

        bool EndPush(int team)
        {
            var up = new int[] { 0, 0 };
            for (int t = 0; t < 2; t++)
                foreach (var hid in heroes[t])
                    if (s.by_id.TryGetValue(hid, out var h) && s.Alive(h)) up[t] += 1;
            return up[team] >= 3 && up[team] >= up[1 - team] + 2;
        }

        bool OurMinionsNear(int team, Vec2 p)
        {
            foreach (var o in UnitsNear(p, TOWER_RANGE))
                if (o.minion && o.team == team && s.Alive(o) && o.pos.DistanceTo(p) <= TOWER_RANGE) return true;
            return false;
        }

        Vec2 HomeTowerSpot(int team, int l)
        {
            Tower best = null;
            foreach (var tw in towers)
                if (tw.team == team && tw.lane == l && !tw.dead && (best == null || tw.tier < best.tier)) best = tw;
            if (best == null) return Wp(team, l, 1);
            Vec2 fwd = team == 0 ? new Vec2(0f, -1f) : new Vec2(0f, 1f);
            return best.p - fwd * 3.0;
        }

        bool EnemyGateDown(int team)
        {
            foreach (var g in s.gates)
                if (g.team != team && !s.GateBlocks(g)) return true;
            return false;
        }

        // ======================= ULTIMATES (0.31.157) =======================
        public int UltRank(Unit u) => Rank(u, "r");

        public UltDef UltInfo(Unit u) => ULTS.TryGetValue(u.hid ?? "", out var d) ? d : null;

        public double UltMaxCd(Unit u) => (UltInfo(u)?.cd ?? 60.0) * (UltRank(u) >= 2 ? RANK2_CD : 1.0);

        public bool UltReady(Unit u) => u.hero && UltRank(u) > 0 && u.ult_cd <= 0.0 && s.Alive(u);

        public bool Ult(Unit u)
        {
            if (!UltReady(u) || !s.CanAct(u) || u.dance != null) return false;
            double k = UltRank(u) >= 2 ? RANK2_POWER : 1.0;
            double dmg = s.Stat(u, SK.dmg);
            string hid = u.hid;
            var ev = new Ev { ["id"] = u.id, ["team"] = u.team, ["ult"] = hid, ["pos"] = u.pos };
            switch (hid)
            {
                case "knight":
                {
                    var ids = new List<object>();
                    foreach (var o in s.units)
                    {
                        if (o.team == u.team && s.Alive(o) && o.pos.DistanceTo(u.pos) <= BULWARK_R && (o.hero || o.minion))
                        {
                            o.dr_until = s.time + BULWARK_TIME * k;
                            o.dr = GD.Min(0.7, BULWARK_DR * (1.0 + (k - 1.0) * 0.5));
                            ids.Add(o.id);
                        }
                    }
                    ev["ids"] = ids;
                    break;
                }
                case "barbarian":
                    u.bl_until = s.time + WARCRY_TIME * k;
                    break;
                case "rogue":
                {
                    Unit tgt = WeakestHero(u, EXECUTE_R);
                    if (tgt == null) tgt = s.NearestEnemy(u, EXECUTE_R);
                    if (tgt == null) return false;
                    Vec2 behind = tgt.pos - SiegeSim.DirOf(tgt.face) * 1.1;
                    ev["from"] = u.pos;
                    u.pos = s.ClampToField(s.PushOut(behind, SiegeSim.UNIT_R, u.team));
                    u.face = SiegeSim.AngleOf(tgt.pos - u.pos);
                    s._next_push = s.PushFrom(u.pos, tgt.pos, 5.0, 2.0);
                    s.Damage(u, tgt, dmg * EXECUTE_DMG * k + EXECUTE_MISSING * GD.Max(0.0, tgt.max_hp - tgt.hp));
                    ev["to"] = u.pos;
                    ev["target"] = tgt.id;
                    break;
                }
                case "ranger":
                {
                    Vec2 at = UltAim(u, RAIN_RANGE, u.pos + SiegeSim.DirOf(u.face) * 9.0);
                    rains.Add(new Rain { team = u.team, owner = u.id, at = at, r = RAIN_R, left = RAIN_TICKS, next = s.time + 0.25,
                        dmg = dmg * RAIN_DMG * k });
                    u.face = SiegeSim.AngleOf(at - u.pos);
                    ev["c"] = at;
                    ev["r"] = RAIN_R;
                    ev["dur"] = 0.25 + RAIN_EVERY * (double)RAIN_TICKS;
                    break;
                }
                case "mage":
                    foreach (var o in EnemiesIn(u, u.pos, INFERNO_R))
                    {
                        s._next_push = s.PushFrom(u.pos, o.pos, 6.0, 3.0);
                        s.Damage(u, o, dmg * INFERNO_DMG * k, INFERNO_STUN);
                    }
                    AbilityKing(u, dmg * INFERNO_DMG * k, u.pos, INFERNO_R);
                    ev["r"] = INFERNO_R;
                    break;
                case "priest":
                {
                    var ids2 = new List<object>();
                    foreach (var hid2 in heroes[u.team].ToArray())
                    {
                        s.by_id.TryGetValue(hid2, out Unit h);
                        if (h != null && s.Alive(h))
                        {
                            s.Heal(u, h, h.max_hp * GRACE_HEAL * k);
                            ids2.Add(h.id);
                        }
                    }
                    ev["ids"] = ids2;
                    break;
                }
                case "crusader":
                    foreach (var o in EnemiesIn(u, u.pos, JUDGMENT_R))
                    {
                        s._next_push = s.PushFrom(u.pos, o.pos, 4.0, 2.4);
                        s.Damage(u, o, dmg * JUDGMENT_DMG * k, JUDGMENT_STUN);
                    }
                    AbilityKing(u, dmg * JUDGMENT_DMG * k, u.pos, JUDGMENT_R);
                    for (int oi = 0; oi < s.units.Count; oi++)
                    {
                        Unit o2 = s.units[oi];
                        if (o2.team == u.team && s.Alive(o2) && o2.pos.DistanceTo(u.pos) <= JUDGMENT_R) s.Heal(u, o2, o2.max_hp * JUDGMENT_HEAL * k);
                    }
                    ev["r"] = JUDGMENT_R;
                    break;
                case "berserker":
                    u.ud_until = s.time + UNDYING_TIME * (1.0 + (k - 1.0) * 0.6);
                    break;
                case "assassin":
                {
                    var tg = new List<string>();
                    var pool = EnemiesIn(u, u.pos, FLURRY_R);
                    Vec2 me_p = u.pos;
                    GSort.Sort(pool, (a, b) => FlurryKey(a, me_p) < FlurryKey(b, me_p));
                    foreach (var o in pool)
                    {
                        if (tg.Count >= FLURRY_N + (k > 1.0 ? 1 : 0)) break;
                        tg.Add(o.id);
                    }
                    if (tg.Count == 0) return false;
                    u.dance = new Dance { ids = tg, i = 0, next = s.time, dmg = dmg * FLURRY_DMG * k };
                    ev["ids"] = new List<object>(tg);
                    break;
                }
                case "sniper":
                {
                    Vec2 aim = UltAimHero(u, DEADEYE_RANGE * 0.8);
                    if (aim != Vec2.Inf) u.face = SiegeSim.AngleOf(aim - u.pos);
                    Vec2 d = SiegeSim.DirOf(u.face);
                    s.projectiles.Add(new Proj { id = s._next_proj, team = u.team, owner = u.id, pos = u.pos + d * 0.6, from = u.pos, hasFrom = true,
                        vel = d * DEADEYE_SPEED, dmg = dmg * DEADEYE_DMG * k, aoe = 0.0, life = DEADEYE_RANGE / DEADEYE_SPEED, kind = "pierce",
                        gate_mult = 0.0, hit = new List<string>(), high = true, stun = DEADEYE_STUN, big = true });
                    s.Emit("proj", "pid", s._next_proj, "kind", "pierce");
                    s._next_proj += 1;
                    break;
                }
                case "archmage":
                {
                    Vec2 c = UltAim(u, STORM_RANGE, u.pos + SiegeSim.DirOf(u.face) * 9.0);
                    u.face = SiegeSim.AngleOf(c - u.pos);
                    int n = STORM_N + (k > 1.0 ? 2 : 0);
                    for (int i = 0; i < n; i++)
                    {
                        Vec2 off = Vec2.Zero;
                        if (i != 0)
                        {
                            Vec2 dir = Vec2.FromAngle(rng.Randf() * GD.TAU);
                            off = dir * rng.RandfRange(1.0, STORM_SPREAD);
                        }
                        Vec2 at2 = s.PushOut(c + off, 0.2);
                        double delay = 0.6 + 0.3 * (double)i;
                        s.meteors.Add(new Meteor { team = u.team, owner = u.id, at = at2, t_hit = s.time + delay, dmg = dmg * STORM_DMG, burn_until = -1.0 });
                        s.Emit("meteor_warn", "id", u.id, "team", u.team, "pos", at2, "delay", delay);
                    }
                    ev["c"] = c;
                    break;
                }
                case "necromancer":
                {
                    var ids3 = new List<object>();
                    int n2 = LEGION_N + (k > 1.0 ? 2 : 0);
                    for (int i = 0; i < n2; i++)
                    {
                        Unit z = RaiseSkeleton(u, u.pos + Vec2.FromAngle(GD.TAU * (double)i / (double)n2 + 0.4) * 1.8);
                        ids3.Add(z.id);
                    }
                    ev["ids"] = ids3;
                    break;
                }
                default:
                    if (!kits.Ult(u, k, dmg, ev)) return false;
                    break;
            }
            u.ult_cd = UltMaxCd(u);
            if (hid != "rogue" && hid != "assassin" && u.state != "dash" && u.dance == null)
            {
                u.state = "recover";
                u.t = 0.35;
                u.move = Vec2.Zero;
            }
            s.Emit("ult", ev);
            return true;
        }

        double FlurryKey(Unit o, Vec2 p) => (o.hero ? 0.0 : 100.0) + o.pos.DistanceTo(p);

        List<Unit> EnemiesIn(Unit u, Vec2 at, double r)
        {
            var o = new List<Unit>();
            foreach (var x in s.units)
                if (x.team != u.team && s.Alive(x) && x.pos.DistanceTo(at) <= r) o.Add(x);
            return o;
        }

        Unit WeakestHero(Unit u, double r)
        {
            Unit best = null;
            double bf = GD.INF;
            foreach (var o in s.units)
            {
                if (o.team == u.team || o.team > 1 || !s.Alive(o) || !o.hero || !CanSee(u.team, o)) continue;
                if (o.pos.DistanceTo(u.pos) > r) continue;
                double f = o.hp / GD.Max(1.0, o.max_hp);
                if (f < bf)
                {
                    bf = f;
                    best = o;
                }
            }
            return best;
        }

        Vec2 UltAim(Unit u, double r, Vec2 fallback)
        {
            Unit h = null;
            double hd = r;
            foreach (var o in s.units)
            {
                if (o.team != u.team && o.team <= 1 && s.Alive(o) && o.hero && CanSee(u.team, o))
                {
                    double d = o.pos.DistanceTo(u.pos);
                    if (d < hd)
                    {
                        hd = d;
                        h = o;
                    }
                }
            }
            if (h == null) h = s.NearestEnemy(u, r);
            return h != null ? h.pos : s.ClampToField(fallback);
        }

        Vec2 UltAimHero(Unit u, double r)
        {
            Vec2 best = Vec2.Inf;
            double bd = r;
            foreach (var o in s.units)
            {
                if (o.team != u.team && o.team <= 1 && s.Alive(o) && o.hero && CanSee(u.team, o))
                {
                    double d = o.pos.DistanceTo(u.pos);
                    if (d < bd)
                    {
                        bd = d;
                        best = o.pos;
                    }
                }
            }
            return best;
        }

        void StepRains(double dt)
        {
            for (int i = rains.Count - 1; i > -1; i--)
            {
                Rain r = rains[i];
                if (s.time < r.next) continue;
                r.next = r.next + RAIN_EVERY;
                r.left = r.left - 1;
                if (!s.by_id.TryGetValue(r.owner, out Unit owner)) owner = Unit.Pseudo("", r.team, null);
                for (int oi = 0; oi < s.units.Count; oi++)
                {
                    Unit o = s.units[oi];
                    if (o.team != r.team && s.Alive(o) && o.pos.DistanceTo(r.at) <= r.r) s.Damage(owner, o, r.dmg);
                }
                AbilityKing(owner, r.dmg, r.at, r.r);
                if (r.left <= 0) rains.RemoveAt(i);
            }
        }

        void StepDance(Unit u)
        {
            Dance dn = u.dance;
            if (s.time < dn.next) return;
            var ids = dn.ids;
            while (dn.i < ids.Count)
            {
                s.by_id.TryGetValue(ids[dn.i], out Unit t);
                dn.i = dn.i + 1;
                if (t == null || !s.Alive(t)) continue;
                Vec2 side = Vec2.FromAngle(rng.Randf() * GD.TAU) * 1.0;
                Vec2 from = u.pos;
                u.pos = s.ClampToField(s.PushOut(t.pos + side, SiegeSim.UNIT_R, u.team));
                u.face = SiegeSim.AngleOf(t.pos - u.pos);
                u.state = "recover";
                u.t = FLURRY_EVERY + 0.05;
                u.move = Vec2.Zero;
                s._next_push = s.PushFrom(u.pos, t.pos, 4.0, 1.6);
                s.Damage(u, t, dn.dmg + dn.missing * GD.Max(0.0, t.max_hp - t.hp));
                s.Emit("flurry_hit", "id", u.id, "target", t.id, "from", from, "pos", u.pos);
                s.Emit("attack", "id", u.id, "kind", "attack", "ability", "", "combo", dn.i % 3);
                dn.next = s.time + FLURRY_EVERY;
                return;
            }
            u.dance = null;
        }

        public double ModDamage(Unit src, Unit dst, double amount)
        {
            double a = amount;
            double t = s.time;
            if (src != null)
            {
                if (src.atk == "ability" && src.hero && src.kq == null) a *= RankPower(src, "q");
                a *= src.m_out;
                if (t < src.bl_until) a *= WARCRY_DMG;
                if (t < src.ud_until) a *= UNDYING_DMG;
                var b = src.buffs;
                if (b != null && !b.IsEmpty)
                {
                    if (t < b.Get("ember", -1.0)) a *= EMBER_DMG;
                    if (t < b.Get("lord", -1.0)) a *= LORD_DMG;
                }
            }
            if (dst.hero && LaneMinion(src != null ? src.id : "")) a *= MINION_VS_HERO;
            if (t < dst.dr_until) a *= 1.0 - dst.dr;
            a *= 1.0 - dst.m_armor;
            if (kits != null) a = kits.Taken(src, dst, a);
            if (t < dst.ud_until) a = GD.Min(a, GD.Max(0.0, dst.hp - 1.0));
            if (dst.mon >= 0 && camps[dst.mon].reset == "hard") a = 0.0;
            return a;
        }

        Unit RaiseSkeleton(Unit owner, Vec2 at)
        {
            _zid += 1;
            string id = "z" + _zid;
            Unit z = s.NewUnit(id, owner.team, true);
            z.cls = "rogue";
            z.summon = true;
            z.minion = true;
            z.lane = -1;
            z.owner = owner.id;
            z.expire = s.time + LEGION_TIME;
            z.look = "skel_minion";
            double lv = (double)(owner.level - 1);
            z.m_hp = LEGION_HP * (1.0 + LEVEL_GROW * lv);
            z.m_dmg = LEGION_DMG * (1.0 + LEVEL_GROW * lv);
            z.m_spd = 1.0;
            z.max_hp = s.Stat(z, SK.hp);
            z.hp = z.max_hp;
            z.pos = s.ClampToField(s.PushOut(at, SiegeSim.UNIT_R, owner.team));
            z.face = owner.face;
            z.think_at = s.time + SiegeSim.TICK;
            s.units.Add(z);
            s.by_id[id] = z;
            return z;
        }

        void ThinkSummon(Unit u)
        {
            s.by_id.TryGetValue(u.owner, out Unit owner);
            Vec2 b = owner != null && s.Alive(owner) ? owner.pos : u.pos;
            Unit best = null;
            double bd = 12.0;
            foreach (var o in UnitsNear(b, bd))
            {
                if (o.team == u.team || !s.Alive(o)) continue;
                if (o.mon >= 0 && camps[o.mon].target == "") continue;
                if (!CanSee(u.team, o)) continue;
                double d = o.pos.DistanceTo(b);
                if (d < bd)
                {
                    bd = d;
                    best = o;
                }
            }
            if (best != null)
            {
                s.Fight(u, best);
                return;
            }
            s.NavTo(u, b, 2.5);
        }

        bool BotUlt(Unit u)
        {
            if (!UltReady(u) || !s.CanAct(u)) return false;
            string hid = u.hid;
            int et = 1 - u.team;
            int near_h = 0, near_any = 0;
            Unit closest = null;
            double cd = GD.INF;
            foreach (var o in s.units)
            {
                if (o.team == u.team || !s.Alive(o) || !CanSee(u.team, o)) continue;
                double d = o.pos.DistanceTo(u.pos);
                if (o.team == et && o.hero)
                {
                    if (d < cd)
                    {
                        cd = d;
                        closest = o;
                    }
                    if (d <= 7.0) near_h += 1;
                }
                if (d <= 7.0 && (o.team == et || (o.mon >= 0 && camps[o.mon].target != ""))) near_any += 1;
            }
            bool lord_fight = false;
            Unit lord = LordUnit();
            if (lord != null && camps[lord.mon].target != "" && lord.pos.DistanceTo(u.pos) < 8.0) lord_fight = true;
            switch (hid)
            {
                case "knight":
                    return (near_h >= 1 && (u.hp < u.max_hp * 0.6 || AlliesNear(u, BULWARK_R) >= 2)) && Ult(u);
                case "barbarian":
                    return ((cd < 4.0) || lord_fight) && Ult(u);
                case "rogue":
                {
                    Unit w = WeakestHero(u, EXECUTE_R);
                    return w != null && w.hp < w.max_hp * 0.45 && Ult(u);
                }
                case "ranger":
                case "archmage":
                {
                    if (closest == null || cd > (hid == "ranger" ? RAIN_RANGE : STORM_RANGE)) return lord_fight && Ult(u);
                    int crowd = 0;
                    foreach (var o in s.units)
                        if (o.team == et && s.Alive(o) && o.pos.DistanceTo(closest.pos) <= 4.5) crowd += 1;
                    return (crowd >= 3 || closest.hp < closest.max_hp * 0.4) && Ult(u);
                }
                case "mage":
                    return ((near_h >= 2) || (near_h >= 1 && near_any >= 4) || lord_fight) && Ult(u);
                case "priest":
                {
                    int low = 0;
                    foreach (var hid2 in heroes[u.team])
                    {
                        s.by_id.TryGetValue(hid2, out Unit h);
                        if (h != null && s.Alive(h))
                        {
                            if (h.hp < h.max_hp * 0.3) return Ult(u);
                            if (h.hp < h.max_hp * 0.6) low += 1;
                        }
                    }
                    return low >= 2 && Ult(u);
                }
                case "crusader":
                    return ((near_h >= 1 && near_any >= 2) || lord_fight) && Ult(u);
                case "berserker":
                    return u.hp < u.max_hp * 0.3 && (near_h >= 1 || lord_fight) && Ult(u);
                case "assassin":
                    return ((near_h >= 1 && (near_any >= 2 || (closest != null && closest.hp < closest.max_hp * 0.5))) || lord_fight) && Ult(u);
                case "sniper":
                {
                    Vec2 aim = UltAimHero(u, DEADEYE_RANGE * 0.8);
                    if (aim == Vec2.Inf) return false;
                    foreach (var o in s.units)
                        if (o.team == et && s.Alive(o) && o.hero && o.pos == aim) return o.hp < o.max_hp * 0.4 && Ult(u);
                    return false;
                }
                case "necromancer":
                    return (near_h >= 1 || near_any >= 3 || lord_fight) && Ult(u);
                default:
                    return kits.BotUlt(u, near_h, near_any, closest, cd, lord_fight) && Ult(u);
            }
        }

        int AlliesNear(Unit u, double r)
        {
            int n = 0;
            foreach (var o in s.units)
                if (o != u && o.team == u.team && s.Alive(o) && o.hero && o.pos.DistanceTo(u.pos) <= r) n += 1;
            return n;
        }

        // ======================= GOLD AND THE SHOP (0.31.157) =======================
        public double GateMult(Unit src)
        {
            if (src != null && src.lordling) return LORD_SIEGE;
            return LaneMinion(src != null ? src.id : "") ? (MINION_TOWER.TryGetValue(src.mk ?? "melee", out var v) ? v : 0.4) : 1.0;
        }

        public double MinionGold(Unit u)
        {
            string mk = u.mk ?? "melee";
            if (u.lordling) return 150.0;
            double g = GOLD_MINION.TryGetValue(mk, out var gv) ? gv : 14;
            if (mk == "siege" || mk == "super") g = GD.Min(90.0, g + 3.0 * Math.Floor(s.time / MINION_UP_EVERY));
            return g;
        }

        public bool CanSee(int team, Unit u) => vision == null || vision.CanSee(team, u);

        public bool Ward(Unit u) => vision != null && vision.PlaceWard(u);

        public bool LaneMinion(string id)
        {
            if (id == null || !s.by_id.TryGetValue(id, out var u)) return false;
            return u.minion && !u.summon;
        }

        public Unit Credit(Unit src)
        {
            if (src == null) return null;
            if (src.hero) return src;
            if (src.summon)
            {
                if (s.by_id.TryGetValue(src.owner ?? "", out var o) && o.hero) return o;
            }
            return null;
        }

        public void AddGold(Unit u, double n, Vec2 at, string kind = "")
        {
            if (u == null || !u.hero || n <= 0.0) return;
            if (kind == "kill" || kind == "cs") u.bounty = u.bounty + n * (kind == "kill" ? BOUNTY_KILL : BOUNTY_CS);
            u.gold = u.gold + n;
            u.gold_total = u.gold_total + n;
            s.Emit("gold", "id", u.id, "n", GD.RoundI(n), "pos", at != Vec2.Inf ? at : u.pos);
        }

        double HeroDownGold(Unit dst, Unit killer)
        {
            int et = 1 - dst.team;
            double paid = 0.0;
            if (killer != null && killer.team == et)
            {
                double raw = GD.Min(dst.bounty, BOUNTY_MAX);
                paid = raw * (1.0 - Devalue(dst.team));
                dst.bounty = dst.bounty - raw;
                AddGold(killer, GOLD_HERO + paid, dst.pos, "kill");
            }
            var hlog = dst.hit_log;
            var clog = dst.cc_log;
            var heals = killer != null ? killer.heal_log : null;
            var helpers = new List<Unit>();
            foreach (var hid in heroes[et])
            {
                s.by_id.TryGetValue(hid, out Unit h);
                if (h == null || h == killer) continue;
                double t_last = GD.Max(hlog != null ? hlog.Get(hid, -99.0) : -99.0,
                    GD.Max(clog != null ? clog.Get(hid, -99.0) : -99.0, heals != null ? heals.Get(hid, -99.0) : -99.0));
                if (s.time - t_last <= ASSIST_WINDOW) helpers.Add(h);
            }
            foreach (var h in helpers)
            {
                AddGold(h, (double)GOLD_ASSIST / (double)helpers.Count, dst.pos, "kill");
                h.assists = h.assists + 1;
            }
            dst.hit_log = new ODict<string, double>();
            dst.cc_log = new ODict<string, double>();
            return paid;
        }

        public Unit KillCredit(Unit dst, Unit by_h)
        {
            int et = 1 - dst.team;
            if (by_h != null && by_h.team == et) return by_h;
            Unit best = null;
            double bt = s.time - KILL_CREDIT;
            if (dst.hit_log != null)
            {
                foreach (var kv in dst.hit_log)
                {
                    s.by_id.TryGetValue(kv.Key, out Unit h);
                    double at = kv.Value;
                    if (h != null && h.team == et && h.hero && at >= bt)
                    {
                        best = h;
                        bt = at;
                    }
                }
            }
            return best;
        }

        int Multi(Unit k, Unit dst)
        {
            int n = 1;
            double last = k.mk_t;
            int had = k.mk_n;
            if (had == 4)
            {
                if (s.time - last <= PENTA_GAP && last_respawn[dst.team] <= last) n = 5;
            }
            else if (had >= 1 && had < 4 && s.time - last <= MULTI_GAP) n = had + 1;
            k.mk_n = n < 5 ? n : 0;
            k.mk_t = s.time;
            if (n >= 2)
            {
                k.best_multi = Math.Max(k.best_multi, n);
                s.Emit("multikill", "id", k.id, "team", k.team, "n", n, "name", MULTI_NAMES[n]);
            }
            return n;
        }

        public double Worth(Unit u)
        {
            if (u == null) return 0.0;
            double n = u.gold;
            if (u.items != null)
                foreach (var id in u.items) n += ITEMS.TryGetValue(id, out var it) ? it.cost : 0;
            return n;
        }

        public double SideWorth(int t)
        {
            double n = 0.0;
            foreach (var hid in heroes[t])
            {
                s.by_id.TryGetValue(hid, out Unit h);
                n += Worth(h);
            }
            return n;
        }

        public double Devalue(int t)
        {
            double ours = SideWorth(t);
            double theirs = SideWorth(1 - t);
            if (theirs <= 0.0 || ours >= theirs) return 0.0;
            double d = (theirs - ours) / theirs;
            if (d < DEVALUE_FROM) return 0.0;
            return GD.Lerp(DEVALUE_MIN, DEVALUE_MAX, GD.Clamp((d - DEVALUE_FROM) / (DEVALUE_FULL - DEVALUE_FROM), 0.0, 1.0));
        }

        public double BountyValue(Unit u)
        {
            if (!u.hero || u.team < 0 || u.team > 1) return 0.0;
            return GD.Min(u.bounty, BOUNTY_MAX) * (1.0 - Devalue(u.team));
        }

        public int BountyShown(Unit u)
        {
            double v = BountyValue(u);
            return v < (double)BOUNTY_SHOW ? 0 : (int)Math.Floor(v / (double)BOUNTY_STEP) * BOUNTY_STEP;
        }

        public void NoteCc(Unit by, Unit dst)
        {
            Unit hb = Credit(by);
            if (hb == null || !dst.hero || hb.team == dst.team) return;
            if (dst.cc_log == null) dst.cc_log = new ODict<string, double>();
            dst.cc_log[hb.id] = s.time;
        }

        public void NoteHeal(Unit by, Unit dst)
        {
            if (by == dst || !by.hero || !dst.hero || by.team != dst.team) return;
            if (dst.heal_log == null) dst.heal_log = new ODict<string, double>();
            dst.heal_log[by.id] = s.time;
        }

        static readonly string[] ITEM_STAT_KEYS = { "dmg", "hp", "as", "spd", "cdr", "ls", "regen", "armor", "heal" };

        public ODict<string, double> ItemStats(Unit u)
        {
            var o = new ODict<string, double>();
            if (u.items == null) return o;
            foreach (var id in u.items)
            {
                if (!ITEMS.TryGetValue(id, out var it)) continue;
                foreach (var k in ITEM_STAT_KEYS)
                    if (it.Has(k)) o[k] = o.Get(k, 0.0) + it.Stat(k);
            }
            return o;
        }

        public bool CanShop(Unit u) => u.hero;

        public string[] BuildOf(Unit u)
        {
            if (BUILDS.TryGetValue(u.hid ?? "", out var b)) return b;
            if (BUILDS.TryGetValue(u.cls ?? "knight", out var c)) return c;
            return BUILDS["knight"];
        }

        public List<string> NextBuys(Unit u, int n = 2)
        {
            var o = new List<string>();
            var seen = new Dictionary<string, int>();
            foreach (var id in BuildOf(u))
            {
                seen[id] = (seen.TryGetValue(id, out var c) ? c : 0) + 1;
                int bought = 0;
                if (u.bought != null)
                    foreach (var x in u.bought)
                        if (x == id) bought++;
                if (bought >= seen[id]) continue;
                o.Add(id);
                if (o.Count >= n) break;
            }
            return o;
        }

        List<int> CompsOwned(Unit u, string id)
        {
            var o = new List<int>();
            var inv = u.items ?? new List<string>();
            foreach (var c in ITEMS[id].from)
                for (int i = 0; i < inv.Count; i++)
                    if (inv[i] == c && !o.Contains(i))
                    {
                        o.Add(i);
                        break;
                    }
            return o;
        }

        public int Price(Unit u, string id)
        {
            if (!ITEMS.ContainsKey(id)) return 0;
            int p = ITEMS[id].cost;
            var inv = u.items ?? new List<string>();
            foreach (int i in CompsOwned(u, id)) p -= ITEMS[inv[i]].cost;
            return Math.Max(0, p);
        }

        public string BuyWhy(Unit u, string id)
        {
            if (!ITEMS.ContainsKey(id) || !u.hero) return "item";
            if (!CanShop(u)) return "where";
            var used = CompsOwned(u, id);
            var inv = u.items ?? new List<string>();
            if (inv.Count - used.Count >= ITEM_SLOTS) return "full";
            if (ITEMS[id].boots)
                for (int i = 0; i < inv.Count; i++)
                    if (ITEMS[inv[i]].boots && !used.Contains(i)) return "boots";
            if (u.gold < (double)Price(u, id)) return "gold";
            return "";
        }

        public bool Buy(Unit u, string id)
        {
            if (BuyWhy(u, id) != "") return false;
            int cost = Price(u, id);
            var used = CompsOwned(u, id);
            used.Sort();
            used.Reverse();
            foreach (int i in used) u.items.RemoveAt(i);
            u.items.Add(id);
            u.bought.Add(id);
            u.gold = u.gold - (double)cost;
            Apply(u);
            s.Emit("buy", "id", u.id, "item", id, "cost", cost);
            return true;
        }

        public bool Sell(Unit u, int slot)
        {
            var inv = u.items;
            if (!CanShop(u) || inv == null || slot < 0 || slot >= inv.Count) return false;
            string id = inv[slot];
            inv.RemoveAt(slot);
            int back = (int)((double)ITEMS[id].cost * SELL_BACK);
            u.gold = u.gold + (double)back;
            Apply(u);
            s.Emit("sell", "id", u.id, "item", id, "gold", back);
            return true;
        }

        void BotShop(Unit u)
        {
            var nb = NextBuys(u, 1);
            if (nb.Count > 0) Buy(u, nb[0]);
        }

        // ======================= THE JUNGLE (0.31.157) =======================
        void AddCamp(string kind, int side, Vec2 p)
        {
            camps.Add(new Camp { id = camps.Count, kind = kind, side = side, p = p, alive = false,
                next = kind == "lord" ? LORD_FIRST : (kind == "wyrm" ? WYRM_FIRST : CAMP_FIRST), target = "", slam = 0.0,
                patience = 1.0, reset = "", reset_at = 0.0 });
        }

        double Leash(Camp camp)
        {
            switch (camp.kind)
            {
                case "lord": return LORD_LEASH;
                case "wyrm": return WYRM_LEASH;
            }
            return LEASH;
        }

        void SpawnCamp(Camp camp)
        {
            CampKind kd = CAMP_KINDS[camp.kind];
            double grow = 1.0 + MON_GROW * s.time / 60.0;
            var ids = new List<string>();
            foreach (var m in kd.mobs)
            {
                string mk = m.mk;
                MonsterDef md = MONSTERS[mk];
                Vec2 off = m.off;
                if (camp.side == 1) off = -off;
                _jid += 1;
                string id = "j" + _jid;
                Unit u = s.NewUnit(id, 2, true);
                u.cls = md.cls;
                u.mon = camp.id;
                u.mkind = mk;
                u.look = md.look;
                u.mscale = md.scale;
                u.m_hp = md.hp * grow;
                u.m_dmg = md.dmg * grow;
                u.m_spd = md.spd;
                u.max_hp = s.Stat(u, SK.hp);
                u.hp = u.max_hp;
                u.home = camp.p + off;
                u.pos = u.home;
                u.face = camp.side >= 0 ? SiegeSim.AngleOf(camp.side == 0 ? new Vec2(0f, 1f) : new Vec2(0f, -1f)) : SiegeSim.AngleOf(new Vec2(1f, 0f));
                u.home_face = u.face;
                u.think_at = s.time + SiegeSim.TICK * (double)(ids.Count + 1);
                s.units.Add(u);
                s.by_id[id] = u;
                ids.Add(id);
            }
            camp.mobs = ids;
            camp.alive = true;
            camp.target = "";
            camp.hits = new ODict<string, double>();
            camp.patience = 1.0;
            camp.reset = "";
            camp.slam = s.time + (camp.kind == "wyrm" ? WYRM_BREATH_EVERY : LORD_SLAM_EVERY);
            s.Emit("camp_up", "camp", camp.id, "kind", camp.kind, "ids", new List<object>(ids));
        }

        public List<Unit> CampLive(Camp camp)
        {
            var o = new List<Unit>();
            foreach (var id in camp.mobs)
                if (s.by_id.TryGetValue(id, out var m) && s.Alive(m)) o.Add(m);
            return o;
        }

        void StepCamps(double dt)
        {
            foreach (var camp in camps)
            {
                if (!camp.alive)
                {
                    if (s.time >= camp.next) SpawnCamp(camp);
                    continue;
                }
                var live = CampLive(camp);
                double lr = Leash(camp);
                if (camp.reset == "soft" || camp.reset == "hard")
                {
                    double rate = camp.reset == "soft" ? SOFT_HEAL : HARD_HEAL;
                    bool settled = true;
                    foreach (var m in live)
                    {
                        if (m.hp < m.max_hp)
                        {
                            m.hp = GD.Min(m.max_hp, m.hp + m.max_hp * rate * dt);
                            settled = false;
                        }
                        if (m.pos.DistanceTo(m.home) > 0.9) settled = false;
                    }
                    if (camp.reset == "soft" && s.time >= camp.reset_at)
                    {
                        camp.reset = "hard";
                        s.Emit("camp_reset", "camp", camp.id, "hard", true);
                    }
                    if (settled)
                    {
                        camp.reset = "";
                        camp.patience = 1.0;
                        camp.hits = new ODict<string, double>();
                    }
                    continue;
                }
                s.by_id.TryGetValue(camp.target, out Unit tgt);
                if (camp.target != "" && (tgt == null || !s.Alive(tgt)))
                {
                    string best = "";
                    double bt = double.NegativeInfinity;
                    foreach (var kv in camp.hits)
                    {
                        s.by_id.TryGetValue(kv.Key, out Unit h);
                        if (h == null || !s.Alive(h) || h.pos.DistanceTo(camp.p) > lr || s.time - kv.Value > 6.0) continue;
                        if (kv.Value > bt)
                        {
                            bt = kv.Value;
                            best = kv.Key;
                        }
                    }
                    camp.target = best;
                    s.by_id.TryGetValue(best, out tgt);
                    if (best == "")
                    {
                        SoftReset(camp);
                        continue;
                    }
                }
                if (camp.target == "")
                {
                    foreach (var m in live)
                        if (m.hp < m.max_hp - 0.5)
                        {
                            SoftReset(camp);
                            break;
                        }
                    continue;
                }
                double d = tgt.pos.DistanceTo(camp.p);
                if (d > lr)
                {
                    string other = "";
                    double ot = double.NegativeInfinity;
                    foreach (var kv in camp.hits)
                    {
                        s.by_id.TryGetValue(kv.Key, out Unit h);
                        if (kv.Key == camp.target || h == null || !s.Alive(h) || h.pos.DistanceTo(camp.p) > lr || s.time - kv.Value > 6.0) continue;
                        if (kv.Value > ot)
                        {
                            ot = kv.Value;
                            other = kv.Key;
                        }
                    }
                    if (other != "")
                    {
                        camp.target = other;
                        tgt = s.by_id[other];
                    }
                    else
                    {
                        camp.patience = camp.patience - dt * (PATIENCE_DRAIN + PATIENCE_FAR * (d - lr));
                        if (camp.patience <= 0.0)
                        {
                            SoftReset(camp);
                            continue;
                        }
                    }
                }
                else camp.patience = GD.Min(1.0, camp.patience + dt * PATIENCE_BACK);
                if (camp.kind == "lord" && live.Count > 0 && s.time >= camp.slam)
                {
                    camp.slam = s.time + LORD_SLAM_EVERY;
                    Unit lord = live[0];
                    int hit = 0;
                    for (int oi = 0; oi < s.units.Count; oi++)
                    {
                        Unit o = s.units[oi];
                        if (o.team <= 1 && s.Alive(o) && o.pos.DistanceTo(lord.pos) <= LORD_SLAM_R)
                        {
                            s._next_push = s.PushFrom(lord.pos, o.pos, 6.0, 3.0);
                            s.Damage(lord, o, s.Stat(lord, SK.dmg) * LORD_SLAM_DMG);
                            hit += 1;
                        }
                    }
                    s.Emit("lord_slam", "id", lord.id, "pos", lord.pos, "n", hit);
                }
                if (camp.kind == "wyrm" && live.Count > 0 && tgt != null && s.time >= camp.slam && tgt.pos.DistanceTo(live[0].pos) <= WYRM_BREATH_R)
                {
                    camp.slam = s.time + WYRM_BREATH_EVERY;
                    Unit wy = live[0];
                    Vec2 dir = (tgt.pos - wy.pos).Normalized();
                    wy.face = SiegeSim.AngleOf(dir);
                    int burnt = 0;
                    foreach (var o in UnitsNear(wy.pos, WYRM_BREATH_R + 1.0))
                    {
                        if (o.team > 1 || !s.Alive(o)) continue;
                        Vec2 off = o.pos - wy.pos;
                        if (off.Length() <= WYRM_BREATH_R && (off.Length() < 1.0 || Math.Abs(dir.AngleTo(off)) <= WYRM_BREATH_ARC))
                        {
                            s.Damage(wy, o, s.Stat(wy, SK.dmg) * WYRM_BREATH_DMG);
                            burnt += 1;
                        }
                    }
                    s.Emit("wyrm_breath", "id", wy.id, "pos", wy.pos, "dir", dir, "n", burnt);
                }
            }
        }

        Unit SummonLord(int team)
        {
            _mid += 1;
            string id = "L" + _mid;
            Unit u = s.NewUnit(id, team, true);
            u.cls = "barbarian";
            u.minion = true;
            u.mk = "lord";
            u.lordling = true;
            u.look = "skel_lord";
            u.mscale = 2.2;
            u.lane = 1;
            u.wp = 1;
            double grow = 1.0 + MON_GROW * s.time / 60.0;
            u.m_hp = LORDLING_HP * grow;
            u.m_dmg = LORDLING_DMG * grow;
            u.m_spd = 0.8;
            u.max_hp = s.Stat(u, SK.hp);
            u.hp = u.max_hp;
            Vec2 start = Wp(team, 1, 0);
            Vec2 ahead = (Wp(team, 1, 1) - start).Normalized();
            u.pos = start + ahead * 2.5;
            u.face = SiegeSim.AngleOf(ahead);
            u.think_at = s.time + SiegeSim.TICK;
            s.units.Add(u);
            s.by_id[id] = u;
            s.Emit("lord_march", "team", team, "id", id);
            return u;
        }

        void SoftReset(Camp camp)
        {
            camp.reset = "soft";
            camp.reset_at = s.time + SOFT_RESET;
            camp.target = "";
            s.Emit("camp_reset", "camp", camp.id, "hard", false);
        }

        void ThinkMonster(Unit u)
        {
            Camp camp = camps[u.mon];
            Vec2 home = u.home;
            double lr = Leash(camp);
            s.by_id.TryGetValue(camp.target, out Unit tgt);
            if (camp.reset == "" && tgt != null && s.Alive(tgt))
            {
                u.resetting = false;
                if (tgt.pos.DistanceTo(camp.p) <= lr)
                {
                    s.Fight(u, tgt);
                    return;
                }
                ClassDef c = SiegeSim.CLASSES[u.cls];
                double d = u.pos.DistanceTo(tgt.pos);
                if (c.ranged && d <= s.Stat(u, SK.range) * 0.9)
                {
                    u.move = Vec2.Zero;
                    u.face = SiegeSim.AngleOf(tgt.pos - u.pos);
                    s.StartAttack(u, "attack", false);
                    return;
                }
                Vec2 edge = camp.p + (tgt.pos - camp.p).Normalized() * (lr - 0.5);
                if (u.pos.DistanceTo(edge) > 0.8) s.NavTo(u, edge, 0.5);
                else
                {
                    u.move = Vec2.Zero;
                    u.face = SiegeSim.AngleOf(tgt.pos - u.pos);
                    if (d <= s.Stat(u, SK.range) + SiegeSim.UNIT_R + 0.2) s.StartAttack(u, "attack", false);
                }
                return;
            }
            if (u.pos.DistanceTo(home) > 0.7)
            {
                u.resetting = true;
                s.NavTo(u, home, 0.4);
                return;
            }
            u.resetting = false;
            u.move = Vec2.Zero;
            u.face = GD.LerpAngle(u.face, double.IsNaN(u.home_face) ? u.face : u.home_face, 0.3);
        }

        void MonsterDown(Unit dst, Unit by_h)
        {
            Camp camp = camps[dst.mon];
            MonsterDef md = MONSTERS[dst.mkind];
            if (dst.mkind == "lord")
            {
                int side = by_h != null ? by_h.team : SideNear(dst.pos);
                if (side >= 0)
                {
                    foreach (var hid in heroes[side].ToArray())
                    {
                        if (!s.by_id.TryGetValue(hid, out Unit h)) continue;
                        AddGold(h, md.gold, dst.pos, "cs");
                        AddXp(h, md.xp);
                        h.epics = h.epics + 1;
                        if (s.Alive(h)) h.buffs["lord"] = s.time + LORD_TIME;
                    }
                    boss_go[side] = false;
                    epic_kills["lord"][side] = epic_kills["lord"][side] + 1;
                }
                s.Emit("lord_down", "team", side, "by", by_h != null ? by_h.id : "");
                if (side >= 0) SummonLord(side);
            }
            else if (dst.mkind == "wyrm")
            {
                int wside = by_h != null ? by_h.team : SideNear(dst.pos);
                if (wside >= 0)
                {
                    wyrm_stacks[wside] = Math.Min(WYRM_STACKS, wyrm_stacks[wside] + 1);
                    foreach (var hid in heroes[wside].ToArray())
                    {
                        if (!s.by_id.TryGetValue(hid, out Unit wh)) continue;
                        AddGold(wh, md.gold, dst.pos, "cs");
                        AddXp(wh, md.xp);
                        wh.epics = wh.epics + 1;
                        Apply(wh);
                    }
                    wyrm_go[wside] = false;
                    epic_kills["wyrm"][wside] = epic_kills["wyrm"][wside] + 1;
                }
                s.Emit("wyrm_down", "team", wside, "by", by_h != null ? by_h.id : "", "stacks", wside >= 0 ? wyrm_stacks[wside] : 0);
            }
            else
            {
                if (by_h != null)
                {
                    AddGold(by_h, md.gold, dst.pos, "cs");
                    var near = new List<Unit>();
                    foreach (var hid in heroes[by_h.team])
                    {
                        s.by_id.TryGetValue(hid, out Unit h2);
                        if (h2 != null && s.Alive(h2) && h2.pos.DistanceTo(dst.pos) <= XP_R) near.Add(h2);
                    }
                    foreach (var h2 in near) AddXp(h2, md.xp * (near.Count == 1 ? 1.0 : 0.7));
                    string buff = CAMP_KINDS[camp.kind].buff ?? "";
                    if (buff != "" && camp.mobs[0] == dst.id)
                    {
                        by_h.buffs[buff] = s.time + BUFF_TIME;
                        s.Emit("buff", "id", by_h.id, "team", by_h.team, "buff", buff);
                    }
                }
            }
            if (CampLive(camp).Count == 0)
            {
                if (by_h != null && dst.mkind != "lord" && dst.mkind != "wyrm") by_h.camps = by_h.camps + 1;
                camp.alive = false;
                camp.next = s.time + CAMP_KINDS[camp.kind].respawn;
                camp.target = "";
                s.Emit("camp_clear", "camp", camp.id, "kind", camp.kind, "by", by_h != null ? by_h.id : "",
                    "team", by_h != null ? by_h.team : -1);
            }
        }

        int SideNear(Vec2 p)
        {
            var n = new int[] { 0, 0 };
            for (int t = 0; t < 2; t++)
                foreach (var hid in heroes[t])
                    if (s.by_id.TryGetValue(hid, out var h) && s.Alive(h) && h.pos.DistanceTo(p) <= XP_R) n[t] += 1;
            return n[0] == n[1] ? -1 : (n[0] > n[1] ? 0 : 1);
        }

        static readonly string[] PASS_BUFFS = { "arcane", "ember" };

        void PassBuffs(Unit dst, Unit by_h)
        {
            var b = dst.buffs;
            if (b == null) return;
            foreach (var k in PASS_BUFFS)
            {
                if (s.time < b.Get(k, -1.0))
                {
                    if (by_h != null && by_h.team != dst.team)
                    {
                        by_h.buffs[k] = s.time + GD.Max(BUFF_PASS_MIN, b[k] - s.time);
                        s.Emit("buff", "id", by_h.id, "team", by_h.team, "buff", k, "from", dst.id);
                    }
                    b.Erase(k);
                }
            }
            b.Erase("lord");
        }

        public bool HasBuff(Unit u, string k) => u.buffs != null && s.time < u.buffs.Get(k, -1.0);

        public bool LordBuff(int t)
        {
            foreach (var hid in heroes[t])
                if (s.by_id.TryGetValue(hid, out var h) && s.Alive(h) && HasBuff(h, "lord")) return true;
            return false;
        }

        Unit LordUnit()
        {
            foreach (var camp in camps)
                if (camp.kind == "lord" && camp.alive)
                {
                    var live = CampLive(camp);
                    return live.Count > 0 ? live[0] : null;
                }
            return null;
        }

        Unit MonsterOn(Unit u)
        {
            Unit best = null;
            double bh = GD.INF;
            foreach (var camp in camps)
            {
                if (!camp.alive || camp.target == "") continue;
                s.by_id.TryGetValue(camp.target, out Unit tg);
                if (tg == null || tg.team != u.team || (tg != u && tg.pos.DistanceTo(u.pos) > 7.0)) continue;
                foreach (var m in CampLive(camp))
                    if (m.pos.DistanceTo(u.pos) < 12.0 && m.hp < bh)
                    {
                        bh = m.hp;
                        best = m;
                    }
            }
            return best;
        }

        bool ThinkJungle(Unit u)
        {
            Camp best = null;
            double bd = GD.INF;
            for (int pass_i = 0; pass_i < 2; pass_i++)
            {
                foreach (var camp in camps)
                {
                    if (!camp.alive || camp.kind == "lord" || camp.kind == "wyrm") continue;
                    if (pass_i == 0 && camp.side != u.team) continue;
                    if (pass_i == 1 && (camp.side == u.team || u.level < 4)) continue;
                    double d = camp.p.DistanceTo(u.pos);
                    if (d < bd)
                    {
                        bd = d;
                        best = camp;
                    }
                }
                if (best != null) break;
            }
            if (best == null)
            {
                if (s.time >= u.gank_until)
                {
                    u.gank = rng.RandiRange(0, 2);
                    u.gank_until = s.time + 25.0;
                }
                return false;
            }
            var live = CampLive(best);
            if (live.Count == 0) return false;
            Unit target = live[0];
            foreach (var m in live)
                if (m.pos.DistanceTo(u.pos) < target.pos.DistanceTo(u.pos) - 1.5) target = m;
            if (SiegeSim.CLASSES[u.cls].ranged && u.pos.DistanceTo(target.pos) > 6.0 && best.target == "")
            {
                s.NavTo(u, target.pos, 4.5);
                return true;
            }
            FightH(u, target);
            return true;
        }

        void BossCall()
        {
            Unit lord = LordUnit();
            for (int t = 0; t < 2; t++)
            {
                if (lord == null)
                {
                    boss_go[t] = false;
                    continue;
                }
                var up = new int[] { 0, 0 };
                var lv = new int[] { 0, 0 };
                for (int tt = 0; tt < 2; tt++)
                    foreach (var hid in heroes[tt])
                    {
                        if (!s.by_id.TryGetValue(hid, out var h)) continue;
                        lv[tt] += h.level;
                        if (s.Alive(h)) up[tt] += 1;
                    }
                boss_go[t] = up[t] >= 3 && (up[1 - t] <= up[t] - 2 || (lv[t] >= lv[1 - t] + 5 && up[t] >= 4));
            }
            EpicCall();
        }

        void EpicCall()
        {
            Unit wy = WyrmUnit();
            var up = new int[] { 0, 0 };
            var lv = new int[] { 0, 0 };
            for (int tt = 0; tt < 2; tt++)
                foreach (var hid in heroes[tt])
                {
                    if (!s.by_id.TryGetValue(hid, out var h)) continue;
                    lv[tt] += h.level;
                    if (s.Alive(h)) up[tt] += 1;
                }
            for (int t = 0; t < 2; t++)
                wyrm_go[t] = wy != null && !boss_go[t] && wyrm_stacks[t] < WYRM_STACKS && up[t] >= 3
                    && (up[t] > up[1 - t] || (up[t] == up[1 - t] && lv[t] >= lv[1 - t]));
        }

        bool GoLord(Unit u) => GoEpic(u, LordUnit());

        bool GoEpic(Unit u, Unit boss, int gather = 0)
        {
            if (!u.bot) return false;
            if (boss == null || boss.pos.DistanceTo(u.pos) > 60.0) return false;
            foreach (var o in UnitsNear(u.pos, 9.0))
            {
                if (o.team == 1 - u.team && s.Alive(o) && o.hero && o.pos.DistanceTo(boss.pos) < 10.0 && o.pos.DistanceTo(u.pos) < 9.0 && CanSee(u.team, o))
                {
                    FightH(u, o);
                    return true;
                }
            }
            if (gather > 0)
            {
                s.by_id.TryGetValue(camps[boss.mon].target, out Unit fighting);
                if (fighting == null || fighting.team != u.team)
                {
                    int near = 0;
                    foreach (var o in UnitsNear(boss.pos, 14.0))
                        if (o.team == u.team && o.hero && s.Alive(o)) near += 1;
                    if (near < gather)
                    {
                        Vec2 stage = boss.pos + (u.pos - boss.pos).Normalized() * 9.5;
                        if (u.pos.DistanceTo(stage) > 1.2) s.NavTo(u, stage, 1.0);
                        else u.move = Vec2.Zero;
                        return true;
                    }
                }
            }
            FightH(u, boss);
            return true;
        }

        Unit WyrmUnit()
        {
            foreach (var camp in camps)
                if (camp.kind == "wyrm" && camp.alive)
                {
                    var live = CampLive(camp);
                    return live.Count > 0 ? live[0] : null;
                }
            return null;
        }
    }
}
