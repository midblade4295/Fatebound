// Ported from godot/scripts/siege/siege_mode.gd (Fatebound 0.31.222), its last part: the match's sound (the cues by
// event, footsteps, ambience, music), the Herald, the announcements and quick chat. (The rest: SiegeMode.cs.)
// The sounds read the sim's Ev records (online: SiegeNet.ToEv of the snapshot's event).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector3 = Fatebound.Sim.Vec3;
using Color = Fatebound.GUI.Col;

namespace Fatebound.Game
{
    using Sim = Fatebound.Sim.SiegeSim;
    using Land = Fatebound.Sim.Land;
    using Keep = Fatebound.Sim.Keep;
    using Net = Fatebound.Game.SiegeNet;
    using Moba = Fatebound.Sim.Moba;

    public partial class SiegeMode
    {
        public const double HEAR_R = 24.0;
        public Rng _snd_rng = new Rng(unchecked((ulong)DateTime.UtcNow.Ticks * 6364136223846793005UL + 1442695040888963407UL));
        public double _step_t = 0.0;
        public Vector2 _step_last = Vector2.INF;
        public Dictionary<string, AudioStreamPlayer> _amb = new Dictionary<string, AudioStreamPlayer>();

        // Match music (0.30.9): the trailers' song, looping at a steady, quiet level under everything (Kevin: no dipping;
        // quiet enough not to drown out other sound). Only the Music slider moves it.
        public const string MUSIC_PATH = "res://assets/music/match.ogg";
        public const double MUSIC_GAIN = 0.064;         // x master x music (0.045 until 0.30.11, Kevin: "just a bit louder": +3 dB); track at -16 LUFS
        public AudioStreamPlayer _music = null;

        public Vector2 _Listener()
        {
            if (sim.by_id.TryGetValue(GD.Str(hud.player_id), out var me) && me != null)
                return me.pos;
            return _step_last != Vector2.INF ? _step_last : Vector2.ZERO;
        }

        // 0.31.167: each W/E's sound -- [cue, takes, gain]. 0.31.171 (step 3, hero polish): every one its own (tools/
        // build_hero_sfx.py, "ab_<spell>"); a spell that lands a moment later (FIRE PILLAR, ENTANGLE) or answers a blow
        // (RIPOSTE) keeps a light cast and has its own sound where it lands ("pillar", "burst", "riposte").
        public struct Cue
        {
            public string name;
            public int n;
            public double gain;
            public Cue(string name, int n, double gain) { this.name = name; this.n = n; this.gain = gain; }
        }

        public static readonly Dictionary<string, Cue> SPELL_CUE = new Dictionary<string, Cue>
        {
            { "bash", new Cue("ab_bash", 1, 1.0) }, { "rally", new Cue("ab_rally", 1, 1.0) }, { "consecrate", new Cue("ab_consecrate", 1, 1.0) },
            { "leap", new Cue("ab_leap", 1, 1.0) }, { "bloodlust", new Cue("ab_bloodlust", 1, 1.0) }, { "charge", new Cue("ab_charge", 1, 1.0) },
            { "frenzy", new Cue("ab_frenzy", 1, 1.0) }, { "caltrops", new Cue("ab_caltrops", 1, 1.0) }, { "poison", new Cue("ab_poison", 1, 1.0) },
            { "shadowstep", new Cue("ab_shadowstep", 1, 1.0) }, { "knives", new Cue("ab_knives", 1, 1.0) }, { "tumble", new Cue("ab_tumble", 1, 1.0) },
            { "snare", new Cue("ab_snare", 1, 1.0) }, { "trap", new Cue("ab_trap", 1, 1.0) }, { "mark", new Cue("ab_mark", 1, 1.0) },
            { "pillar", new Cue("tm_firespray", 2, 0.5) }, { "blink", new Cue("ab_blink", 1, 1.0) }, { "missiles", new Cue("ab_missiles", 1, 1.0) },
            { "manashield", new Cue("ab_manashield", 1, 1.0) }, { "holylight", new Cue("ab_holylight", 1, 1.0) }, { "dazzle", new Cue("ab_dazzle", 1, 1.0) },
            { "boneshield", new Cue("ab_boneshield", 1, 1.0) }, { "curse", new Cue("ab_curse", 1, 1.0) },
            // 0.31.168: the six new heroes
            { "boulder", new Cue("ab_boulder", 1, 1.0) }, { "stoneskin", new Cue("ab_stoneskin", 1, 1.0) }, { "quake", new Cue("ab_quake", 1, 1.0) },
            { "sweep", new Cue("ab_sweep", 1, 1.0) }, { "impale", new Cue("ab_impale", 1, 1.0) }, { "vault", new Cue("ab_vault", 1, 1.0) },
            { "thrust", new Cue("ab_thrust", 1, 1.0) }, { "riposte", new Cue("tm_sword_block", 3, 0.8) }, { "feint", new Cue("ab_feint", 1, 1.0) },
            { "chain", new Cue("ab_chain", 1, 1.0) }, { "static", new Cue("ab_static", 1, 1.0) }, { "gust", new Cue("ab_gust", 1, 1.0) },
            { "buckshot", new Cue("ab_buckshot", 1, 1.0) }, { "keg", new Cue("ab_keg", 1, 1.0) }, { "smokeroll", new Cue("ab_smokeroll", 1, 1.0) },
            { "rejuv", new Cue("ab_rejuv", 1, 1.0) }, { "entangle", new Cue("tm_crumble", 2, 0.4) }, { "barkskin", new Cue("ab_barkskin", 1, 1.0) },
        };
        static readonly Cue SPELL_CUE_DEFAULT = new Cue("tm_spell_hit", 3, 0.8);
        // 0.31.171: the new heroes' basic attacks and their hits (by HERO_SHOT, and the Golem's stone hammer)
        public static readonly Dictionary<string, string> SHOT_CUE = new Dictionary<string, string> { { "ball", "atk_musket" }, { "bolt", "atk_bolt" }, { "thorn", "atk_thorn" } };
        public static readonly Dictionary<string, string> HIT_CUE = new Dictionary<string, string> { { "musketeer", "hit_musket" }, { "stormcaller", "hit_bolt" }, { "druid", "hit_thorn" }, { "golem", "hit_golem" } };
        static readonly string[] KB_MULTI = { "", "", "kb_double", "kb_triple", "kb_quadra", "kb_penta" };
        static readonly string[] MK_NAME = { "", "", "double", "triple", "quadra", "penta", "legendary" };

        public void _Cue(string @base, int n, Vector2 at, double reach = HEAR_R, bool always = false, double gain = 1.0)
        {
            if (audio == null)
                return;
            double d = always ? 0.0 : _Listener().DistanceTo(at);
            if (d > reach)
                return;
            double v = GD.Clampf(1.0 - (d - 6.0) / GD.Max(reach - 6.0, 1.0), 0.0, 1.0);
            string cue = n <= 1 ? @base : @base + (1 + _snd_rng.Randi() % (uint)n);
            audio.Play(cue, false, v * gain);
        }

        public Vector2 _UnitPos(string id)
        {
            return sim.by_id.TryGetValue(id ?? "", out var u) && u != null ? u.pos : Vector2.INF;
        }

        public Vector2 _GatePos(string gid)
        {
            foreach (var g in sim.gates)
                if (GD.Str(g.id) == gid)
                    return Sim.GateFront(g);
            return Vector2.INF;
        }

        public void _OnTowerBroke(Vector3 at, int stage)
        {
            // 0.31.172: a tower breaking as it's hurt -- stone crumbling (louder when it falls)
            _Cue("tm_crumble", 2, new Vector2(at.x, at.z), 40.0, false, stage < 4 ? 0.65 : 1.1);
            if (stage >= 4)
                _Cue("tm_rock_hit", 2, new Vector2(at.x, at.z), 40.0, false, 1.0);
        }

        /// <summary>e.get(key, dflt) as a Vector2: an event's position, or dflt when it has none.</summary>
        static Vector2 _EvPos(Ev e, string key, Vector2 dflt)
        {
            return e.TryGetValue(key, out var v) && v != null ? V.ToVec2(v) : dflt;
        }

        Unit _ById(string id) => sim.by_id.TryGetValue(id ?? "", out var u) ? u : null;

        public void _EventSound(Ev e)
        {
            if (audio == null)
                return;
            string pid = GD.Str(hud.player_id);
            bool mine = e.S("id", "") == pid;
            switch (e.S("k", ""))
            {
                case "attack":
                {
                    var src = _ById(e.S("id", ""));
                    if (src == null)
                        return;
                    string ab = e.S("ability", "");
                    if (ab == "hammer")
                        _Cue("hammerThrow", 1, src.pos, HEAR_R + 4.0, mine);
                    else if (e.S("kind", "") == "ability" && GD.Str(sim.AbilityOf(src)) == "pierce")
                        _Cue("ab_pierce", 1, src.pos, HEAR_R + 4.0, mine);                // 0.31.171: the Sniper's PIERCE
                    else if (SHOT_CUE.ContainsKey(src.shot ?? ""))
                        // 0.31.168: the Musketeer's flintlock, the Stormcaller's bolt, the Druid's thorn (0.31.171: their own)
                        _Cue(SHOT_CUE[src.shot], 1, src.pos, HEAR_R + (src.shot == "ball" ? 6.0 : 0.0), mine);
                    else if ((src.hid ?? "") == "golem")
                        _Cue("atk_golem", 1, src.pos, HEAR_R, mine);                      // 0.31.171: his stone hammer
                    else if (src.cls == "ranger")
                        _Cue("tm_bow_shot", 2, src.pos, HEAR_R, mine);
                    else if (src.cls == "mage")
                    {
                        if (ab == "")
                            _Cue("tm_fireball", 3, src.pos, HEAR_R, mine);
                    }
                    else if (src.cls != "priest")
                        _Cue("tm_sword_swing", 3, src.pos, HEAR_R, mine);
                    break;
                }
                case "hit":
                {
                    var at = _UnitPos(e.S("id", ""));
                    if (at == Vector2.INF)
                        return;
                    var by = _ById(e.S("by", ""));
                    bool hurt_me = mine || e.S("by", "") == pid;
                    if (by == null || by.cls == "priest")
                        return;                                       // a drain is silent
                    if (HIT_CUE.ContainsKey(by.hid ?? ""))
                        _Cue(HIT_CUE[by.hid], 1, at, HEAR_R, hurt_me);          // 0.31.171: the new heroes' hits
                    else if (by.cls == "ranger")
                        _Cue("tm_bow_hit", 3, at, HEAR_R, hurt_me);
                    else if (by.cls == "mage")
                        _Cue("tm_spell_hit", 3, at, HEAR_R, hurt_me);
                    else
                        _Cue("tm_sword_hit", 3, at, HEAR_R, hurt_me);
                    break;
                }
                case "blocked":
                    _Cue("tm_sword_block", 3, _EvPos(e, "pos", _UnitPos(e.S("id", ""))), HEAR_R, mine);
                    break;
                case "nova":
                    _Cue("tm_firespray", 2, _UnitPos(e.S("id", "")), HEAR_R, mine);
                    break;
                case "whirl":
                    _Cue("ab_whirl", 1, _UnitPos(e.S("id", "")), HEAR_R, mine);       // 0.31.171: the Berserker's WHIRLWIND
                    break;
                case "block_up":
                    _Cue("ab_shield", 1, _UnitPos(e.S("id", "")), HEAR_R, mine);      // 0.31.171: the Knight's Q, the Crusader's W
                    break;
                case "gate_hit":
                    _Cue("tm_gate_hit", 2, _GatePos(e.S("gate", "")), HEAR_R + 6.0);
                    break;
                case "tower_hit":
                {
                    // 0.31.177: a hero's hit on a tower thuds on its stone (yours always heard; the minions' left quiet)
                    var tb = _ById(e.S("by", ""));
                    int tw = e.I("tw", -1);
                    if (tb != null && tb.hero && sim.moba != null && tw >= 0 && tw < sim.moba.towers.Count)
                        _Cue("tm_gate_hit", 2, sim.moba.towers[tw].p, HEAR_R, e.S("by", "") == pid, 0.8);
                    break;
                }
                case "gate_broken":
                    _Cue("tm_crumble", 2, _GatePos(e.S("gate", "")), 48.0);
                    _AnnounceGate(e);
                    break;
                case "gate_rebuilt":
                    _Cue("tm_gate_close", 1, _GatePos(e.S("gate", "")), 18.0);
                    break;
                case "gate_open":
                    _Cue("tm_gate_open", 1, _GatePos(e.S("gate", "")), 12.0, false, 0.55);
                    break;
                case "kb":                                           // 0.31.180: the kill banners' sounds (siege_hud.gd kill_banner)
                {
                    string kind = e.S("kind", "kill");
                    bool mine_kb = e.S("by", "") == pid || e.S("id", "") == pid;
                    switch (kind)
                    {
                        case "first_blood":
                            _Cue("kb_first_blood", 1, Vector2.ZERO, HEAR_R, true, 0.9);
                            _HeraldSay("kb_first_blood");
                            break;
                        case "multi":
                            int mn = GD.Clampi(e.I("n", 2), 2, 5);
                            _Cue(KB_MULTI[mn], 1, Vector2.ZERO, HEAR_R, true,
                                mine_kb || mn >= 4 ? 1.0 : 0.7);     // (a PENTAKILL is heard across the map, whoever's)
                            break;
                        case "shutdown":
                            _Cue("kb_shutdown", 1, Vector2.ZERO, HEAR_R, true, 0.9);
                            _HeraldSay("kb_shutdown");
                            break;
                        default:
                            _Cue("kb_kill", 1, Vector2.ZERO, HEAR_R, true, mine_kb ? 0.8 : 0.5);
                            break;
                    }
                    break;
                }
                case "recall":                                       // 0.31.181: the recall's hum, and its arrival
                    _Cue("recall_start", 1, _UnitPos(e.S("id", "")), HEAR_R, mine, 0.8);
                    break;
                case "recall_done":
                    _Cue("recall_done", 1, _EvPos(e, "to", Vector2.ZERO), HEAR_R, mine, 0.9);
                    break;
                case "ace":
                    _Cue("kb_ace", 1, Vector2.ZERO, HEAR_R, true, 0.9);
                    _HeraldSay("kb_ace");
                    break;
                case "multikill":                                    // 0.31.29: the Herald calls your multi-kills
                    if (e.S("id", "") == hud.player_id && sim.by_id.TryGetValue(hud.player_id, out var meu) && meu != null)
                        // (0.31.37: kept on my unit online too, where the sim's own count lives on the server -- a chest rule)
                        meu.best_multi = GD.Maxi(meu.best_multi, e.I("n"));
                    if (e.S("id", "") == hud.player_id)
                        _HeraldSay("mk_" + MK_NAME[GD.Mini(e.I("n"), 6)]);
                    break;
                case "vanish":                                       // 0.31.32: the three upgrades' new abilities
                    // (0.31.171: the Assassin's own; the Duelist's FEINT has its spell's)
                    if ((_ById(e.S("id", ""))?.hid ?? "") != "duelist")
                        _Cue("ab_vanish", 1, _UnitPos(e.S("id", "")), 14.0, false, 0.8);
                    break;
                case "meteor_warn":
                    _Cue("tm_fireball", 3, e.P("pos"), 40.0, false, 0.9);
                    break;
                case "meteor_hit":                                   // 0.31.58 (Kevin): quieter, less dramatic than Siege's bomb
                    _Cue("tm_fireball", 3, e.P("pos"), 45.0, false, 0.55);
                    _Cue("tm_crumble", 2, e.P("pos"), 32.0, false, 0.3);
                    break;
                case "pierce_hit":
                    _Cue("tm_bow_hit", 3, e.P("pos"), HEAR_R, false, 1.1);
                    break;
                case "ult":                                          // 0.31.157 5V5: each ultimate its own sound
                {
                    // (0.31.171: all eighteen from tools/build_hero_sfx.py, "ult_<hero>")
                    string hid = e.S("ult", "");
                    _Cue(Moba.HEROES.ContainsKey(hid) ? "ult_" + hid : "surge", 1, _EvPos(e, "pos", _UnitPos(e.S("id", ""))), 40.0, mine);
                    break;
                }
                case "flurry_hit":
                    // 0.31.171: the Assassin's FLURRY slashes, the Duelist's GRAND CHALLENGE thrusts
                    if ((_ById(e.S("id", ""))?.hid ?? "") == "duelist")
                        _Cue("ab_thrust", 1, _EvPos(e, "pos", Vector2.INF), HEAR_R, mine, 0.9);
                    else
                        _Cue("flurry", 3, _EvPos(e, "pos", Vector2.INF), HEAR_R, mine);
                    break;
                case "lord_slam":
                    _Cue("tm_rock_hit", 2, _EvPos(e, "pos", Vector2.INF), 40.0, false, 1.0);
                    break;
                case "lord_down":
                case "camp_up":
                case "lord_march":
                case "wyrm_down":
                {
                    string ck = e.S("kind", "");
                    if (e.S("k", "") != "camp_up" || ck == "lord" || ck == "wyrm")
                        _Cue("horn", 1, Vector2.INF, 0.0, true, 0.8);
                    break;
                }
                case "spell":                                               // 0.31.167: W and E, each its sound
                {
                    if (!SPELL_CUE.TryGetValue(e.S("spell", ""), out var sc))
                        sc = SPELL_CUE_DEFAULT;
                    _Cue(sc.name, sc.n, _EvPos(e, "pos", Vector2.INF), 30.0, mine, sc.gain);
                    break;
                }
                case "slam":
                {
                    // a leap's landing (0.31.171: LEAP's and DRAGON DIVE's own)
                    string h = _ById(e.S("id", ""))?.hid ?? "";
                    string land = h == "barbarian" ? "ab_leap_land" : (h == "dragoon" ? "ult_dragoon_land" : "");
                    if (land != "")
                        _Cue(land, 1, _EvPos(e, "pos", Vector2.INF), 30.0, mine);
                    else
                        _Cue("tm_rock_hit", 2, _EvPos(e, "pos", Vector2.INF), 30.0, false, 0.9);
                    break;
                }
                case "pillar":
                    _Cue("ab_pillar", 1, _EvPos(e, "c", Vector2.INF), 30.0, false, 1.0);         // 0.31.171: the eruption
                    break;
                case "trap_snap":
                    _Cue("ab_trap_snap", 1, _EvPos(e, "pos", Vector2.INF), 24.0, false, 1.0);
                    break;
                case "burst":                                               // 0.31.168: a powder keg, roots
                    if (e.S("spell", "") == "keg")
                        _Cue("tm_bomb_blast", 1, _EvPos(e, "c", Vector2.INF), 36.0, false, 0.8);
                    else
                        _Cue("ab_entangle", 1, _EvPos(e, "c", Vector2.INF), 24.0, false, 1.0);  // 0.31.171: the roots
                    break;
                case "zap":                                                 // 0.31.168: a THUNDERSTORM bolt
                    _Cue("hit_bolt", 1, _EvPos(e, "c", Vector2.INF), 36.0, false, 1.0);
                    break;
                case "riposte":
                    _Cue("ab_riposte", 1, _EvPos(e, "pos", Vector2.INF), HEAR_R, mine, 1.0);    // 0.31.171: the answer
                    break;
                case "wyrm_breath":                                         // 0.31.166: the Grave Wyrm's soul-fire
                    _Cue("tm_fireball", 3, _EvPos(e, "pos", Vector2.INF), 40.0, false, 1.0);
                    break;
                case "buff":
                    _Cue("surge", 1, _UnitPos(e.S("id", "")), 24.0, mine, 0.8);
                    break;
                case "ult_ready":
                    if (mine)
                        _Cue("levelUp", 1, Vector2.INF, 0.0, true, 0.8);
                    break;
                case "gold":
                    if (mine)
                        _Cue("coin", 1, Vector2.INF, 0.0, true, 0.45);
                    break;
                case "boom":
                    _Cue("tm_spell_hit", 3, _EvPos(e, "pos", Vector2.INF), HEAR_R);
                    break;
                case "dodge":
                    _Cue("tm_jump_dirt", 1, _UnitPos(e.S("id", "")), 14.0, mine);
                    break;
                case "resurrect":
                    _Cue("tm_revive", 1, _EvPos(e, "pos", Vector2.INF), HEAR_R, e.S("by", "") == pid || mine);
                    break;
            }
        }

        public void _Footsteps(double delta)
        {
            // Your own footsteps, by what you're walking on: water when wading, stone in the keeps and on the fords, earth
            // elsewhere. Knights (and Crusaders) clink in mail.
            if (audio == null)
                return;
            var me = _ById(GD.Str(hud.player_id));
            if (me == null || !sim.Alive(me))
            {
                _step_last = Vector2.INF;
                return;
            }
            Vector2 p = me.pos;
            double moved = _step_last == Vector2.INF ? 0.0 : p.DistanceTo(_step_last);
            _step_last = p;
            if (moved / GD.Max(delta, 0.001) < 1.2)
            {
                _step_t = 0.12;                                       // first step lands soon after you start moving
                return;
            }
            _step_t -= delta;
            if (_step_t > 0.0)
                return;
            double speed = moved / GD.Max(delta, 0.001);
            _step_t = GD.Clampf(1.55 / GD.Max(speed, 1.0), 0.24, 0.42);
            string surf = "dirt";
            if (Sim.WaterDepth(p) > 0.05)                // (0.31.165: the Rift's river is shallow -- 0.15 m at its deepest)
                surf = "water";
            else if (Land.KeepDist(p) < Keep.R + 0.5 || Land.OnFord(p))
                surf = "stone";                        // (0.31.126: the paths are dirt now, so only the keeps and the fords sound of stone)
            string chain = me.cls == "knight" ? "_chain" : "";
            audio.Play("tm_step_" + surf + chain + (1 + _snd_rng.Randi() % 5u), false, 1.0);
        }

        static double _Lv(GDict lv, string key) => GD.Float(lv.Get(key, 1.0));

        public void _Ambience(double delta)
        {
            // Forest birds under the whole match; the river louder as you near it.
            if (_amb.Count == 0)
            {
                foreach (var k in new[] { "forest_day", "river" })
                {
                    var st = ResourceLoader.Load<AudioStream>("res://assets/sounds/ambience/" + k + ".ogg");
                    if (st == null)
                        continue;
                    _SetLoop(st);
                    var pl = new AudioStreamPlayer();
                    pl.Stream = st;
                    pl.VolumeDb = -80.0;
                    AddChild(pl);
                    pl.Play(GD.Randf() * 50.0);
                    _amb[k] = pl;
                }
            }
            bool muted = audio == null || audio.muted || !GetWindow().HasFocus();
            GDict lv = audio != null && audio.levels != null ? audio.levels : GDict.Of("master", 1.0, "combat", 1.0);
            double @base = muted ? 0.0 : _Lv(lv, "master") * _Lv(lv, "combat");
            var at = _Listener();
            // 0.30.9 (Kevin: "lower the volume of the river"): 0.55 -> 0.14 and the waterfall 0.7 -> 0.12. The river file
            // is ~5 dB hotter than the forest bed and the waterfall ~9 dB, so these now peak near the bed's level.
            double river = 0.14 * GD.Clampf(1.0 - Land.RiverOff(at) / 16.0, 0.0, 1.0);
            foreach (var kv in _amb)
            {
                var pl = kv.Value;
                double g = (kv.Key == "forest_day" ? 0.22 : kv.Key == "river" ? river : 0.0) * @base;
                double cur = GD.DbToLinear(pl.VolumeDb);
                pl.VolumeDb = GD.LinearToDb(GD.Max(GD.Lerpf(cur, g, Math.Min(1.0, delta * 3.0)), 0.00001));
            }
            _MusicStep(delta, muted, lv);
        }

        static void _SetLoop(AudioStream st)
        {
            if (st is AudioStreamOggVorbis o)
                o.Loop = true;
            else if (st is AudioStreamMP3 m)
                m.Loop = true;
        }

        public void _MusicStep(double delta, bool muted, GDict lv)
        {
            if (_music == null)
            {
                if (!ResourceLoader.Exists(MUSIC_PATH))
                    return;
                var st = ResourceLoader.Load<AudioStream>(MUSIC_PATH);
                if (st == null)
                    return;
                _SetLoop(st);
                _music = new AudioStreamPlayer();
                _music.Stream = st;
                _music.VolumeDb = -80.0;
                AddChild(_music);
                _music.Play();
            }
            double target = muted ? 0.0 : MUSIC_GAIN * _Lv(lv, "master") * _Lv(lv, "music");
            double cur = GD.DbToLinear(_music.VolumeDb);
            _music.VolumeDb = GD.LinearToDb(GD.Max(GD.Lerpf(cur, target, Math.Min(1.0, delta * 2.0)), 0.00001));   // eases only on mute / slider
        }

        // The Herald's in-match lines (0.31.29): assets/vo/herald/<id>.ogg, at the master volume like the tutorial's voice,
        // a newer line cutting off the one before (a quick triple steps on the double).
        public AudioStreamPlayer _herald = null;
        public double _herald_until = 0.0;                    // when the line playing ends (by its length: the playing flag can stick)
        public double _ann_clock = 0.0;                       // frame time since the match opened (the announcer's clock)
        public const double HERALD_GAIN = 0.5;      // 0.31.58 (Kevin: lower the announcer): -6 dB, under the louder game sounds

        public void _HeraldSay(string id)
        {
            string path = "res://assets/vo/herald/" + id + ".ogg";
            if (!ResourceLoader.Exists(path))
                return;
            double master = 1.0;
            bool muted = false;
            if (audio != null)
            {
                master = _Lv(audio.levels, "master");
                muted = audio.muted;
            }
            if (muted || master <= 0.0)
                return;
            if (_herald == null)
            {
                _herald = new AudioStreamPlayer();
                _herald.Bus = "Master";
                AddChild(_herald);
            }
            _herald.Stop();
            _herald.Stream = ResourceLoader.Load<AudioStream>(path);
            _herald.VolumeDb = GD.LinearToDb(master * HERALD_GAIN);
            _herald.Play();
            _herald_until = _ann_clock + (_herald.Stream != null ? _herald.Stream.GetLength() : 0.0);
        }

        // ---------- the Herald's match announcements (0.31.30, Kevin: "only important ones") ----------
        // assets/vo/herald/an_<key>_<n>.ogg (n variants, picked at random). From your team's side. Priorities: 3 cuts in on
        // anything (the end, the last minute, ten seconds); 2 waits for the line playing to finish; lower-priority calls that
        // can't play within 5 s are dropped. Each key has a cooldown (gates break often). Multi-kill calls (priority 2) share
        // the same voice. (0.31.169: Siege's King, jail and outpost calls went with it; a gate of a keep broken is called.)
        public static readonly Dictionary<string, (int pri, double cd)> ANNOUNCE = new Dictionary<string, (int, double)>
        {
            { "start", (2, 0.0) }, { "our_gate", (2, 45.0) }, { "their_gate", (2, 45.0) },
            { "last_minute", (3, 0.0) }, { "ten_seconds", (3, 0.0) }, { "victory", (3, 0.0) }, { "defeat", (3, 0.0) }, { "draw", (3, 0.0) },
        };
        public Dictionary<string, double> _ann_last = new Dictionary<string, double>();
        public List<(string key, int pri, double at)> _ann_queue = new List<(string, int, double)>();   // [key, priority, wanted_at]
        public HashSet<string> _ann_flags = new HashSet<string>();

        public void _Announce(string key)
        {
            if (!ANNOUNCE.TryGetValue(key, out var a))
                return;
            double now = _ann_clock;
            double cd = a.cd;
            if (cd > 0.0 && now - (_ann_last.TryGetValue(key, out var last) ? last : -999.0) < cd)
                return;
            _ann_last[key] = now;
            int pri = a.pri;
            if (pri >= 3)
            {
                _ann_queue.Clear();
                _HeraldSay(_AnnFile(key));
            }
            else
                _ann_queue.Add((key, pri, now));
        }

        public string _AnnFile(string key)
        {
            int n = 0;
            while (ResourceLoader.Exists("res://assets/vo/herald/an_" + key + "_" + (n + 1) + ".ogg"))
                n += 1;
            return "an_" + key + "_" + GD.RandiRange(1, GD.Maxi(n, 1));
        }

        public void _AnnounceTick()
        {
            // the queue, and the clock-driven calls (start, last minute, ten seconds, the end)
            if (sim == null || (tutorial && training == 1))
                return;                              // (0.31.181: the tutorial's Herald does the talking; 0.31.217: training 1's Kael)
            double now = _ann_clock;
            if (_ann_queue.Count > 0 && now >= _herald_until)
            {
                var item = _ann_queue[0];
                _ann_queue.RemoveAt(0);
                if (now - item.at <= 5.0)
                    _HeraldSay(_AnnFile(item.key));
            }
            if (!_ann_flags.Contains("start") && sim.time > 1.0)
            {
                _ann_flags.Add("start");
                _Announce("start");
            }
            double left = sim.match_time - sim.time;
            if (!_ann_flags.Contains("minute") && left <= 60.0 && left > 55.0)
            {
                _ann_flags.Add("minute");
                _Announce("last_minute");
            }
            if (!_ann_flags.Contains("ten") && left <= 10.0 && left > 8.0 && !sim.ended)
            {
                _ann_flags.Add("ten");
                _Announce("ten_seconds");
            }
            if (!_ann_flags.Contains("end") && sim.ended)
            {
                _ann_flags.Add("end");
                var me = _ById(hud.player_id);
                int team = me != null ? me.team : 0;
                _Announce(sim.winner < 0 ? "draw" : (sim.winner == team ? "victory" : "defeat"));
            }
        }

        public void _AnnounceGate(Ev e)
        {
            // a gate of a keep broken: "our gate" / "their gate", from your side
            var me = sim != null ? _ById(hud.player_id) : null;
            int gi = e.I("gate", -1);
            if (me == null || gi < 0 || gi >= sim.gates.Count)
                return;
            _Announce(sim.gates[gi].team == me.team ? "our_gate" : "their_gate");
        }

        // ---------- quick chat (0.31.111, Kevin: "add the quick chat pings") ----------
        public double _qc_at = -100.0;

        public void _OnQuickChat(int i)
        {
            if (sim == null || i < 0 || i >= Net.QUICK_CHAT.Size())
                return;
            double now = Time.GetTicksMsec() / 1000.0;
            if (now - _qc_at < Net.QC_GAP)
            {
                hud.Toast("One quick chat every " + (int)Net.QC_GAP + " seconds", new Color("#c2cdea"));
                return;
            }
            _qc_at = now;
            hud.AddPing(hud.player_id, i, player_name);            // shown at once; the server tells the others
            _PingSound();
            if (online)
                _NetSend(GDict.Of("t", "qc", "i", i));
        }

        public void _PingSound()
        {
            if (audio != null)
                audio.Play("ping");
        }
    }
}
