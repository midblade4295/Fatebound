// Ported from godot/scripts/siege/siege_view.gd (Fatebound 0.31.222).
// The match's whole 3D presentation, split into partial files by the .gd's sections (each in the .gd's order):
// SiegeView.cs (consts, setup, ambience, water), SiegeView.World.cs (blood, world, terrain, foliage, whirls/shields/beams),
// SiegeView.Castle.cs (plasma, scenery, castle kits, keeps, ridges, fords), SiegeView.Actors.cs (looks, bodies, weapons,
// the pool, actors, sync), SiegeView.Moba.cs (5v5: towers, fog, brush, wards, ultimates, kits, events, kings,
// projectiles), SiegeView.Fx.cs (effects, camera, capes, explosions, smoke, shockwave, ragdolls, vanish, meteors).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector2i = Fatebound.Sim.Vec2i;
using Vector3 = Fatebound.Sim.Vec3;
using Vector4 = Fatebound.Sim.Vec4;
using Color = Fatebound.GUI.Col;
using Transform3D = Fatebound.Sim.Xform3;
using Quaternion = Fatebound.Sim.Quat;
using AABB = Fatebound.Sim.Aabb;
using Material = Fatebound.GUI.GMaterial;
using Environment = Fatebound.GUI.Environment;

namespace Fatebound.Game
{
    // (the script preloads; inside the namespace so `Sim` is the sim class, not the Fatebound.Sim namespace)
    using Eco = Fatebound.Game.Economy;
    using Stage = Fatebound.Game.AssetCache;
    using Land = Fatebound.Sim.Land;
    using Keep = Fatebound.Sim.Keep;
    using Sim = Fatebound.Sim.SiegeSim;

    public partial class SiegeView : Node3D
    {
        // Presentation only: mirrors siege_sim state every frame and never changes it.
        public const double FLOOR_TILE = 3.2;            // the keeps' floor texture's period in metres (the old castle_mesh.gd's, as on the map paths)
        // (Keep: 0.31.165: the Rift's keeps (the Siege castles' builders are unused))
        public static bool CASTLE_KITS = true;      // 0.31.74 Meshy castle kits (castle_kit.gd); false = the KayKit castle (tools compare)
        public static readonly Texture2D PATH_TEX = ResourceLoader.Load<Texture2D>("res://assets/terrain/path.png");       // (the castle floors' herringbone when there's no kit)
        public static readonly Texture2D DIRT_TEX = ResourceLoader.Load<Texture2D>("res://assets/terrain/dirt.png");       // 0.31.126: the map's dirt paths (tools/make_dirt_texture.py)
        // (SpellFx: 0.31.201: the abilities' effects)
        public SpellFx fxs = null;                                                   // (SpellFx, a child; made in setup_steps)
        // (EyeFx: 0.31.192: the Necromancer's glowing, smoking eyes; WyrmBody: 0.31.166: the Grave Wyrm (a body without a
        // rig); Foliage: 0.31.173: the Meshy trees and bushes; Towers: 0.31.172: the 5v5's towers (Meshy, breaking as they're hurt))
        public event Action<Vector3, int> TowerBroke;                    // (siege_mode plays the crumble)

        public const string HEX = "res://assets/kaykit/hex/";
        public const string FOREST = "res://assets/kaykit/forest/";
        public static readonly Color[] TEAM_COLORS = { new Color("#5fd2f0"), new Color("#ff7b52"), new Color("#e2c85c") };      // (0.31.157: the third, the jungle's monsters)
        public static readonly Color GOLD = new Color("#ffd46a");
        // The Vulkan (Mobile renderer) look; the only renderer since 0.31.92 (OpenGL removed). 0.31.71 (Kevin, comparing the
        // two renderers side by side: "OpenGL looks better"): retuned so Vulkan matches the OpenGL render -- deeper shadows, brighter sunlit tops, the same
        // colour. Measured on the same shots (tools/building_shot.gd, FB_VK_* env), luminance p10/p50/p90 and saturation:
        // OpenGL .10/.40/.72 s.54; Vulkan before (1.55, 2.25, 1, 1) .29/.47/.69 s.46; now .18/.38/.74 s.56.
        public static double VULKAN_EXPOSURE = 2.0;     // was 1.55
        public static double VULKAN_AMBIENT = 1.05;     // was 2.25
        public static double VULKAN_CONTRAST = 1.2;     // Vulkan-only multipliers on the colour adjustments
        public static double VULKAN_SATURATION = 0.96;

        // Model, weapons (right/left hand) and clips per class. Clip keys: g general, m melee, r ranged,
        // mb movement basic, ma movement advanced. (0.31.169: the KayKit Tools set -- chopping, fishing, carrying -- went with Siege.)
        // 0.31.128 (Kevin: "make their idle animations the same as knight so the others aren't bouncing up and down so much"):
        // every class stands in the Knight's g/Idle_A (its hips move 1.5 cm; g/Idle_B's 10 cm, Melee_2H_Idle's 3.6 cm) -- but
        // the two archers, whose r/Ranged_Bow_Idle doesn't bob at all (0 cm) and holds the bow up with its string toward them:
        // in g/Idle_A the bow hand is the Knight's shield hand and every bow's string turned away (tests/weapon_grip_test.gd).
        // The *_kaykit entries below keep theirs (tools/retarget_meshy.gd's reference bodies only).
        public static readonly GDict LOOKS = new GDict
        {
            // 0.31.76 (Kevin picked concepts "A2 both"): the Worker a Meshy straw-hat farmer (green overalls, red bandana,
            // gloves); he was the KayKit Rogue. (Siege's class: his weapons still come round in the shop.)
            { "worker", GDict.Of("model", "meshy:worker", "r", "mw/work_hatchet", "l", "", "idle", "g/Idle_A", "attack", "m/Melee_1H_Attack_Chop", "ability", "m/Melee_1H_Attack_Chop", "combo", GArray.Of("m/Melee_1H_Attack_Chop", "m/Melee_1H_Attack_Slice_Horizontal", "m/Melee_1H_Attack_Stab")) },
            { "knight", GDict.Of("model", "meshy:knight", "r", "mw/squire_sword", "l", "mw/squire_shield", "idle", "g/Idle_A", "attack", "m/Melee_1H_Attack_Slice_Diagonal", "ability", "m/Melee_Blocking", "combo", GArray.Of("m/Melee_1H_Attack_Slice_Diagonal", "m/Melee_1H_Attack_Slice_Horizontal", "m/Melee_Block_Attack")) },
            { "crusader", GDict.Of("model", "meshy:crusader", "r", "mw/templar_sword", "l", "mw/templar_shield", "idle", "g/Idle_A", "attack", "m/Melee_1H_Attack_Slice_Diagonal", "ability", "m/Melee_Blocking", "combo", GArray.Of("m/Melee_1H_Attack_Slice_Diagonal", "m/Melee_1H_Attack_Slice_Horizontal", "m/Melee_Block_Attack")) },
            // Upgraded barbarian (Round 11): two-handed greatsword, whirlwind.
            { "berserker", GDict.Of("model", "meshy:berserker", "r", "mw/ironhewer_greatsword", "l", "", "idle", "g/Idle_A", "attack", "m/Melee_2H_Attack_Chop", "ability", "m/Melee_2H_Attack_Spinning", "combo", GArray.Of("m/Melee_2H_Attack_Chop", "m/Melee_2H_Attack_Slice", "m/Melee_2H_Attack_Spin")) },
            { "barbarian", GDict.Of("model", "meshy:barbarian", "r", "mw/woodsplitter_axe", "l", "", "idle", "g/Idle_A", "attack", "m/Melee_2H_Attack_Slice", "ability", "m/Melee_2H_Attack_Spin", "combo", GArray.Of("m/Melee_2H_Attack_Slice", "m/Melee_2H_Attack_Chop", "m/Melee_2H_Attack_Stab")) },
            { "rogue", GDict.Of("model", "meshy:rogue", "r", "mw/cutpurse_dagger", "l", "mw/cutpurse_dagger", "idle", "g/Idle_A", "attack", "m/Melee_Dualwield_Attack_Stab", "ability", "m/Melee_1H_Attack_Jump_Chop", "combo", GArray.Of("m/Melee_Dualwield_Attack_Stab", "m/Melee_Dualwield_Attack_Slice", "m/Melee_Dualwield_Attack_Chop")) },
            { "ranger", GDict.Of("model", "meshy:ranger", "r", "", "l", "mw/ashwood_bow", "idle", "r/Ranged_Bow_Idle", "attack", "r/Ranged_Bow_Release", "ability", "r/Ranged_Bow_Release_Up") },
            { "mage", GDict.Of("model", "meshy:mage", "r", "mw/apprentice_staff", "l", "", "idle", "g/Idle_A", "attack", "r/Ranged_Magic_Shoot", "ability", "r/Ranged_Magic_Spellcasting") },
            // Healer: a body of his own since 0.31.80 (white and gold robes, sun emblem, gold circlet), with a wand.
            { "priest", GDict.Of("model", "meshy:priest", "r", "mw/acolyte_wand", "l", "", "idle", "g/Idle_A", "attack", "r/Ranged_Magic_Spellcasting_Long", "ability", "r/Ranged_Magic_Raise") },
            // Upgraded priest (0.31.2, Kevin): the Necromancer from KayKit Skeletons (CC0, same Rig_Medium) with the skull staff.
            // 0.31.32: the last three upgrades get their own looks
            { "assassin", GDict.Of("model", "meshy:assassin", "r", "mw/shade_dagger", "l", "mw/shade_dagger", "idle", "g/Idle_A", "attack", "m/Melee_Dualwield_Attack_Stab", "ability", "m/Melee_1H_Attack_Jump_Chop", "tint", "#5b4f73", "combo", GArray.Of("m/Melee_Dualwield_Attack_Stab", "m/Melee_Dualwield_Attack_Slice", "m/Melee_Dualwield_Attack_Chop")) },
            { "sniper", GDict.Of("model", "meshy:sniper", "r", "mw/marksman_crossbow", "l", "", "idle", "r/Ranged_Bow_Idle", "attack", "r/Ranged_Bow_Release", "ability", "r/Ranged_Bow_Draw", "tint", "#4f6b4a") },
            { "archmage", GDict.Of("model", "meshy:archmage", "r", "mw/magister_staff", "l", "mw/magister_book", "idle", "g/Idle_A", "attack", "r/Ranged_Magic_Shoot", "ability", "r/Ranged_Magic_Summon", "tint", "#a33d3d") },
            { "necromancer", GDict.Of("model", "meshy:necromancer", "r", "mw/bonecaller_staff", "l", "", "idle", "g/Idle_A", "attack", "r/Ranged_Magic_Spellcasting_Long", "ability", "r/Ranged_Magic_Raise") },
            { "necromancer_kaykit", GDict.Of("model", "Necromancer", "r", "Skeleton_Staff", "l", "", "idle", "g/Idle_B", "attack", "r/Ranged_Magic_Spellcasting_Long", "ability", "r/Ranged_Magic_Raise") },          // 0.31.63: the stock body, kept for tools/retarget_meshy.gd
            { "villager_kaykit", GDict.Of("model", "Rogue", "r", "", "l", "", "idle", "g/Idle_A", "attack", "m/Melee_Unarmed_Attack_Punch_A", "ability", "m/Melee_Unarmed_Attack_Kick") },          // 0.31.76: the old body of both, kept for tools/retarget_meshy.gd
            // 0.31.80 (Kevin picked base-class concepts): the six base classes are Meshy bodies too; their stock KayKit bodies stay
            // here for tools/retarget_meshy.gd (the skeleton and height each bake starts from) -- the Priest's was the Mage's.
            { "knight_kaykit", GDict.Of("model", "Knight", "r", "", "l", "", "idle", "g/Idle_A", "attack", "m/Melee_1H_Attack_Slice_Diagonal", "ability", "m/Melee_Blocking") },
            { "barbarian_kaykit", GDict.Of("model", "Barbarian", "r", "", "l", "", "idle", "m/Melee_2H_Idle", "attack", "m/Melee_2H_Attack_Slice", "ability", "m/Melee_2H_Attack_Spin") },
            { "rogue_kaykit", GDict.Of("model", "Rogue_Hooded", "r", "", "l", "", "idle", "g/Idle_B", "attack", "m/Melee_Dualwield_Attack_Stab", "ability", "m/Melee_1H_Attack_Jump_Chop") },
            { "ranger_kaykit", GDict.Of("model", "Ranger", "r", "", "l", "", "idle", "r/Ranged_Bow_Idle", "attack", "r/Ranged_Bow_Release", "ability", "r/Ranged_Bow_Release_Up") },
            { "mage_kaykit", GDict.Of("model", "Mage", "r", "", "l", "", "idle", "g/Idle_B", "attack", "r/Ranged_Magic_Shoot", "ability", "r/Ranged_Magic_Spellcasting") },
            // 0.31.157 5V5 -- the jungle's monsters and the Necromancer's LEGION: KayKit Skeletons 1.0 (CC0; their own embedded
            // animations stripped out -- the rig is the Adventurers' one, so the game's Rig_Medium libraries drive them)
            { "skel_minion", GDict.Of("model", "Skeleton_Minion", "r", "Skeleton_Blade", "l", "", "idle", "g/Idle_A", "attack", "m/Melee_1H_Attack_Chop", "ability", "m/Melee_1H_Attack_Jump_Chop", "combo", GArray.Of("m/Melee_1H_Attack_Chop", "m/Melee_1H_Attack_Slice_Diagonal", "m/Melee_1H_Attack_Slice_Horizontal")) },
            { "skel_warrior", GDict.Of("model", "Skeleton_Warrior", "r", "Skeleton_Axe", "l", "Skeleton_Shield_Small_A", "idle", "g/Idle_A", "attack", "m/Melee_1H_Attack_Chop", "ability", "m/Melee_2H_Attack_Spin", "combo", GArray.Of("m/Melee_1H_Attack_Chop", "m/Melee_1H_Attack_Slice_Horizontal", "m/Melee_Block_Attack")) },
            { "skel_rogue", GDict.Of("model", "Skeleton_Rogue", "r", "Skeleton_Crossbow", "l", "", "idle", "r/Ranged_Bow_Idle", "attack", "r/Ranged_Bow_Release", "ability", "r/Ranged_Bow_Release_Up") },
            { "skel_mage", GDict.Of("model", "Skeleton_Mage", "r", "Skeleton_Staff", "l", "", "idle", "g/Idle_A", "attack", "r/Ranged_Magic_Shoot", "ability", "r/Ranged_Magic_Spellcasting", "tint", "#b9a8ff") },
            { "skel_brute", GDict.Of("model", "Skeleton_Warrior", "r", "Skeleton_Axe", "l", "Skeleton_Shield_Large_A", "idle", "g/Idle_A", "attack", "m/Melee_1H_Attack_Chop", "ability", "m/Melee_2H_Attack_Spin", "tint", "#ff9b7a", "combo", GArray.Of("m/Melee_1H_Attack_Chop", "m/Melee_1H_Attack_Slice_Horizontal", "m/Melee_Block_Attack")) },
            // 0.31.159 5V5 lane minions (Kevin picked the A1 concepts, "the King's levy"): Meshy bodies of their own -- a kettle-
            // helm footman (short sword, round buckler), a wide-brimmed crossbowman (hand crossbow, the bow's clips as the Ranger's), a
            // goggled bombardier (powder keg on his back, a bronze hand-cannon thrust out to fire -- the Mage's shot), a castle
            // champion (a big war hammer). (KayKit's 1H / 2H gun clips hold a piece fit like the crossbows straight up.) Their props are Meshy pieces from one parts sheet, fit to KayKit templates (MESHY_WEAPON_LIKE).
            { "minion_melee", GDict.Of("model", "meshy:minion_melee", "r", "mw/minion_sword", "l", "mw/minion_buckler", "idle", "g/Idle_A", "attack", "m/Melee_1H_Attack_Slice_Diagonal", "ability", "m/Melee_1H_Attack_Stab", "combo", GArray.Of("m/Melee_1H_Attack_Slice_Diagonal", "m/Melee_1H_Attack_Slice_Horizontal", "m/Melee_1H_Attack_Stab")) },
            { "minion_caster", GDict.Of("model", "meshy:minion_caster", "r", "mw/minion_crossbow", "l", "", "idle", "r/Ranged_Bow_Idle", "attack", "r/Ranged_Bow_Release", "ability", "r/Ranged_Bow_Draw") },
            { "minion_siege", GDict.Of("model", "meshy:minion_siege", "r", "mw/minion_cannon", "l", "", "idle", "g/Idle_A", "attack", "r/Ranged_Magic_Shoot", "ability", "r/Ranged_Magic_Spellcasting") },
            { "minion_super", GDict.Of("model", "meshy:minion_super", "r", "mw/minion_hammer", "l", "", "idle", "m/Melee_2H_Idle", "attack", "m/Melee_2H_Attack_Chop", "ability", "m/Melee_2H_Attack_Spin", "combo", GArray.Of("m/Melee_2H_Attack_Chop", "m/Melee_2H_Attack_Slice", "m/Melee_2H_Attack_Stab")) },
            { "skel_lord", GDict.Of("model", "Skeleton_Warrior", "r", "Skeleton_Axe", "l", "Skeleton_Shield_Large_A", "idle", "g/Idle_A", "attack", "m/Melee_1H_Attack_Chop", "ability", "m/Melee_2H_Attack_Spin", "tint", "#a993d6", "combo", GArray.Of("m/Melee_1H_Attack_Chop", "m/Melee_1H_Attack_Slice_Horizontal", "m/Melee_Block_Attack")) },
            // 0.31.166 (Kevin picked concept "A"): the Grave Wyrm, a skeletal dragon from Meshy -- a body of its own with no rig
            // (wyrm_body.gd: its limbs bent in a shader, its clips its own). "size": its scale in place of BODY_SCALE x mscale
            // (the model is 4 m tall); "ring": its ring's radius.
            { "wyrm", GDict.Of("model", "prop:wyrm", "r", "", "l", "", "idle", "w/Idle", "attack", "w/Bite", "ability", "w/Swipe", "combo", GArray.Of("w/Bite", "w/Bite", "w/Swipe"), "size", 1.0, "ring", 2.4) },
            // 0.31.168 (Kevin picked six new 5v5 heroes, one a role): Meshy bodies (KK_FOR in tools/retarget_meshy.gd) and Meshy
            // props from one parts sheet of the six concepts (assets/meshy/weapons): the Golem's rune hammer and stone slab shield,
            // the Dragoon's halberd, the Duelist's rapier (and a parrying dagger), the Stormcaller's trident staff, the
            // Musketeer's flintlock, the Druid's living-wood staff. Not cosmetics: unit_cosmetic leaves them as they are.
            { "golem", GDict.Of("model", "meshy:golem", "r", "mw/golem_hammer", "l", "mw/golem_shield", "idle", "g/Idle_A", "attack", "m/Melee_1H_Attack_Chop", "ability", "m/Melee_Block_Attack", "combo", GArray.Of("m/Melee_1H_Attack_Chop", "m/Melee_1H_Attack_Slice_Horizontal", "m/Melee_Block_Attack")) },
            { "dragoon", GDict.Of("model", "meshy:dragoon", "r", "mw/dragoon_halberd", "l", "", "idle", "g/Idle_A", "attack", "m/Melee_2H_Attack_Stab", "ability", "m/Melee_2H_Attack_Slice", "combo", GArray.Of("m/Melee_2H_Attack_Stab", "m/Melee_2H_Attack_Slice", "m/Melee_2H_Attack_Chop")) },
            { "duelist", GDict.Of("model", "meshy:duelist", "r", "mw/duelist_rapier", "l", "mw/needlepoint_stiletto", "idle", "g/Idle_A", "attack", "m/Melee_1H_Attack_Stab", "ability", "m/Melee_1H_Attack_Jump_Chop", "combo", GArray.Of("m/Melee_1H_Attack_Stab", "m/Melee_Dualwield_Attack_Slice", "m/Melee_1H_Attack_Stab")) },
            { "stormcaller", GDict.Of("model", "meshy:stormcaller", "r", "mw/storm_staff", "l", "", "idle", "g/Idle_A", "attack", "r/Ranged_Magic_Shoot", "ability", "r/Ranged_Magic_Spellcasting") },
            { "musketeer", GDict.Of("model", "meshy:musketeer", "r", "mw/musket", "l", "", "idle", "r/Ranged_Bow_Idle", "attack", "r/Ranged_Bow_Release", "ability", "r/Ranged_Bow_Draw") },
            { "druid", GDict.Of("model", "meshy:druid", "r", "mw/druid_staff", "l", "", "idle", "g/Idle_A", "attack", "r/Ranged_Magic_Shoot", "ability", "r/Ranged_Magic_Raise") },
        };
        public static readonly GDict MINION_LOOKS = GDict.Of("melee", "minion_melee", "caster", "minion_caster", "siege", "minion_siege", "super", "minion_super");
        public static readonly string[] LOOP_HINTS = { "Idle", "Running", "Walking", "Hammering", "Holding", "Aiming", "_Pose", "Blocking", "Chopping", "Pickaxing" };

        public static GDict _libs = new GDict();
        // Shared GPU resources: one mesh/shader per effect type instead of one per hit, so fights don't
        // churn buffers or trigger new shader compiles mid-match.
        public static SphereMesh _spark_mesh;
        public static GDict _rings = new GDict();

        public SiegeSim sim;
        public string player_id = "you";
        // 0.31.85 (Kevin: "When on the other team, it still thinks I'm on the other team ... health bars are red for my team"):
        // your side is always drawn blue and the other red -- rings, health bars, castle roofs and banners, throne, King,
        // outposts, hat shops. `my_side` is the player's team (0 offline; online, whichever the server seated you on); vt() maps a
        // team to the colour it is drawn in. Positions and facing still use the real team.
        public int my_side = 0;
        public GDict player_names = new GDict();                     // unit id -> name: the live players online (0.31.86; the server's "pn")
        public GDict player_titles = new GDict();                    // unit id -> title id (0.31.87; the "pn" message's "tt")
        public string my_name = "";                          // 0.31.88: your own name and title, from your profile -- your plate shows
        public string my_title = "";                         // offline and online, whatever the server sends
        public GDict player_tags = new GDict();                      // 0.31.134: unit id -> clan tag (the "pn" message's "ct")
        public string my_tag = "";                           // 0.31.134: your own clan's tag (from the app)
        public GDict player_crests = new GDict();                    // 0.31.196: unit id -> clan crest code (the "pn" message's "cc")
        public string my_crest = "";                         // 0.31.196: your own clan's crest (from the app)
        public static int _kit_side = 0;                  // the side the cached merged castle walls (_kit_merged) were tinted for

        public int Vt(int t)
        {
            return t < 0 || t > 1 || my_side == 0 ? t : 1 - t;
        }
        public Camera3D camera;
        public GDict actors = new GDict();
        public GArray oracle_nodes = new GArray();
        public GDict gate_nodes = new GDict();
        public GDict proj_nodes = new GDict();
        public double proj_lead = 0.0;          // offline: seconds since the last sim tick (projectiles drawn ahead by vel * this)
        public GArray _fx = new GArray();
        public double _time = 0.0;
        public Vector3 _cam_target = Vector3.ZERO;
        public bool low_fx = false;
        public bool hq_gfx = true;          // High-quality graphics (Round 30): set by SiegeMode from Settings before _ready

        public static GDict Libraries()
        {
            if (_libs.IsEmpty())
            {
                var files = GDict.Of("g", "General", "m", "CombatMelee", "r", "CombatRanged", "mb", "MovementBasic", "ma", "MovementAdvanced");
                foreach (var key in files)
                {
                    var packed = Stage.Scene(GD.Fmt("res://assets/kaykit/anim/Rig_Medium_%s.glb", files[key]));
                    if (packed == null)
                        continue;
                    var holder = packed.Instantiate();
                    AnimationPlayer player = holder.FindChild("AnimationPlayer", true, false) as AnimationPlayer;
                    if (player != null)
                    {
                        AnimationLibrary lib = player.GetAnimationLibrary("");
                        foreach (var n in lib.GetAnimationList())
                        {
                            foreach (var hint in LOOP_HINTS)
                            {
                                if (n.Contains(hint))
                                {
                                    lib.GetAnimation(n).LoopMode = Animation.LOOP_LINEAR;
                                    break;
                                }
                            }
                        }
                        _libs[key] = Var.Of(lib);
                    }
                    holder.Free();
                }
            }
            return _libs;
        }

        public static GDict build_times = new GDict();      // last setup's ms per step (siege_diag / tools read it)
        public const string CACHE_RES = "res://assets/terrain/cache.res";
        public static bool _cache_tried = false;

        public static void _LoadCache()
        {
            // The baked start-up cache (0.31.8): terrain and outer meshes, the foliage plan and blood textures, generated once by
            // tools/bake_land.gd. Used only when its key matches the land; otherwise the view generates (slower first start).
            if (_cache_tried)
                return;
            _cache_tried = true;
            if (!ResourceLoader.Exists(CACHE_RES))
                return;
            var c = ResourceLoader.Load(CACHE_RES) as TerrainCache;
            if (c == null || GD.Str(c.key) != Land.BakeKey())
            {
                GD.PushWarning("siege: terrain cache is stale (run tools/bake_land.gd); generating at start instead");
                return;
            }
            _terrain_meshes = c.terrain.Duplicate();
            _outer_meshes = c.outer.Duplicate();
            _foliage = c.foliage.Duplicate();
            _outer_trees = c.outer_trees.Duplicate();
            _blood_tex = new GArray();
            foreach (var img in c.blood)
                _blood_tex.Append(Var.Of(ImageTexture.CreateFromImage(img.As<Image>())));
        }

        public void Setup(SiegeSim s)
        {
            // The whole world at once (tools, tests, online: the view is built when the server's welcome arrives).
            foreach (var step in SetupSteps(s))
                step.As<Action>()();
        }

        public GArray SetupSteps(SiegeSim s)
        {
            // The build as steps the match runs one per frame behind its loading card (0.31.78: pressing Play used to freeze the
            // menu for the whole build before the card appeared). Each entry builds one part of the world and times itself
            // (build_times); the parts are independent, in this order. The world draws, and its pipelines compile, as it grows.
            sim = s;
            build_times = new GDict();
            if (fxs == null)
            {
                fxs = new SpellFx();
                fxs.view = this;
                AddChild(fxs);
            }
            my_side = sim.by_id.TryGetValue(player_id, out var me0) ? me0.team : 0;
            if (my_side != _kit_side)
            {
                _kit_merged.Clear();                 // (their tint was for the other side)
                _kit_side = my_side;
            }
            var steps = new GArray();
            foreach (var pair in new (string, Action)[] { ("cache+lighting+ambience", () =>
                        {
                            _LoadCache();
                            _BuildLighting();
                            _BuildAmbience();
                            _BuildBlood();
                        }),
                    ("terrain+water", _BuildTerrain),
                    ("outer land", _BuildOuterLand),
                    ("foliage", _BuildFoliage),
                    ("ridges+fords", () =>
                        {
                            _BuildRidges();
                            _BuildFords();
                        }),
                    ("keep 0", () =>
                        {
                            _BuildKeep(0);
                            _MergeKit(0);
                        }),          // per keep, so the one off-screen is culled as a whole
                    ("keep 1", () =>
                        {
                            _BuildKeep(1);
                            _MergeKit(1);
                        }),
                    ("towers", _BuildMoba),                // 0.31.155 5V5: the lane towers
                    ("ground marks", _BuildGroundMarks),  // 0.31.216: the carved stone on the ground (a step of its own)
                    ("edge scenery", _BuildEdgeScenery),
                    ("oracles+warm", () =>
                        {
                            for (int tm = 0; tm < 2; tm++)
                                oracle_nodes.Append(_MakeOracle(tm));
                            _WarmUp();
                        }) })
            {
                string label = GD.Str(pair.Item1);
                Action f = pair.Item2;
                steps.Append((Action)(() => _Timed(label, f)));
            }
            return steps;
        }

        public void _Timed(string label, Action f)
        {
            var t = Time.GetTicksMsec();
            f();
            build_times[label] = Time.GetTicksMsec() - t;
        }

        public void _WarmUp()
        {
            // Draw one of every effect/projectile type in view during the first frames, so their shader
            // variants compile while the match is loading instead of freezing the first fight.
            var at = new Vector3(Sim.Spawn(0).x, 0.5, Sim.Spawn(0).y);
            RingAt(at, GOLD, 1.0, 0.2);
            Spark(at, GOLD);
            Number(at, "0", false);
            foreach (var kind in (sim.moba != null ? new[] { "arrow", "fire", "bolt", "ball", "thorn", "boulder" } : new[] { "arrow", "fire" }))
            {
                var n = _MakeProjectile(kind);
                n.Position = at;
                GetTree().CreateTimer(0.3).Timeout += n.QueueFree;
            }
            if (sim.moba != null)
            {
                // 0.31.166: the Grave Wyrm's body and soul-fire (their shaders, before it rises at 3:00)
                var wm = WyrmBody.Make(Stage.Scene(WyrmBody.MODEL), _cast_static);
                if (!wm.IsEmpty())
                {
                    var wbody = wm["body"].As<Node3D>();
                    wbody.Position = at + new Vector3(0, 0, -3.0);
                    AddChild(wbody);
                    GetTree().CreateTimer(0.3).Timeout += wbody.QueueFree;
                }
                _SoulFire(at, Vector3.UP, 0.3, 0.1);
            }
        }

        // ---------- High-quality ambience (Round 32: "add even more effects to make the game look more beautiful") ----------
        public const double CLOUD_STRENGTH = 0.2;
        public static NoiseTexture2D _cloud_tex = null;
        public GPUParticles3D _motes = null;
        public GArray _torches = new GArray();          // [light, flame, base energy, phase]

        public static NoiseTexture2D _Clouds()
        {
            if (_cloud_tex == null)
            {
                _cloud_tex = new NoiseTexture2D();
                _cloud_tex.Width = 256;
                _cloud_tex.Height = 256;
                _cloud_tex.Seamless = true;
                var fn = new FastNoiseLite();
                fn.Frequency = 0.02;
                fn.FractalOctaves = 4;
                _cloud_tex.Noise = fn;
            }
            return _cloud_tex;
        }

        public static Shader _cloud_floor_shader = null;

        public static ShaderMaterial _CloudFloorMaterial(Texture2D tex, Color tint_col, double uv_scale = 1.0)
        {
            // The castle floor with the terrain's drifting cloud shadows, so they don't stop at the castle walls.
            // uv_scale: the castle floors' UVs run one unit per FLOOR_TILE metres; a texture whose tile covers
            // T metres takes FLOOR_TILE / T (0.31.74: each castle area its own floor).
            if (_cloud_floor_shader == null)
            {
                _cloud_floor_shader = new Shader();
                _cloud_floor_shader.Code = "\n" +
                    "shader_type spatial;\n" +
                    "render_mode specular_disabled;\n" +
                    "uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;\n" +
                    "uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;\n" +
                    "uniform vec4 tint_col : source_color;\n" +
                    "uniform float cloud_strength = 0.2;\n" +
                    "uniform float uv_scale = 1.0;\n" +
                    "varying vec3 wpos;\n" +
                    "void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }\n" +
                    "void fragment() {\n" +
                    "\tfloat cl = smoothstep(0.46, 0.74, texture(cloud_tex, wpos.xz / 95.0 + vec2(TIME * 0.006, TIME * 0.0035)).r);\n" +
                    "\tALBEDO = texture(tex, UV * uv_scale).rgb * tint_col.rgb * (1.0 - cloud_strength * cl);\n" +
                    "\tROUGHNESS = 0.95;\n" +
                    "}\n";
            }
            var m = new ShaderMaterial();
            m.Shader = _cloud_floor_shader;
            m.SetShaderParameter("uv_scale", uv_scale);
            m.SetShaderParameter("tex", tex);
            m.SetShaderParameter("tint_col", tint_col);
            m.SetShaderParameter("cloud_tex", _Clouds());
            m.SetShaderParameter("cloud_strength", CLOUD_STRENGTH);
            return m;
        }

        public static Color _Bright(Color c)
        {
            // Effects bright enough for the glow to bloom (High-quality graphics); rings and decals don't use this.
            if (!_cast_static)
                return c;
            return new Color(c.r * 1.8, c.g * 1.8, c.b * 1.8, c.a);
        }

        public static GradientTexture2D _SoftDot()
        {
            var g = new Gradient();
            g.SetColor(0, new Color(1, 1, 1, 1));
            g.SetColor(1, new Color(1, 1, 1, 0));
            var t = new GradientTexture2D();
            t.Gradient = g;
            t.Fill = GradientTexture2D.FillEnum.Radial;
            t.FillFrom = new Vector2(0.5, 0.5);
            t.FillTo = new Vector2(1.0, 0.5);
            t.Width = 64;
            t.Height = 64;
            return t;
        }

        public void _BuildAmbience()
        {
            if (!_Hq())
                return;
            // Warm motes of pollen drifting in the sunlight around where the camera looks.
            var pm = new ParticleProcessMaterial();
            pm.EmissionShape = ParticleProcessMaterial.EMISSION_SHAPE_BOX;
            pm.EmissionBoxExtents = new Vector3(20.0, 2.5, 20.0);
            pm.Gravity = new Vector3(0.0, 0.06, 0.0);
            pm.InitialVelocityMin = 0.05;
            pm.InitialVelocityMax = 0.25;
            pm.Direction = new Vector3(0.3, 0.4, 0.2);
            pm.Spread = 180.0;
            pm.TurbulenceEnabled = true;
            pm.TurbulenceNoiseStrength = 0.6;
            pm.TurbulenceNoiseScale = 3.0;
            pm.ScaleMin = 0.6;
            pm.ScaleMax = 1.4;
            var ramp = new Gradient();
            ramp.SetColor(0, new Color(1, 1, 1, 0));
            ramp.AddPoint(0.2, new Color(1, 1, 1, 1));
            ramp.AddPoint(0.8, new Color(1, 1, 1, 1));
            ramp.SetColor(ramp.GetPointCount() - 1, new Color(1, 1, 1, 0));
            var rt = new GradientTexture1D();
            rt.Gradient = ramp;
            pm.ColorRamp = rt;
            var quad = new QuadMesh();
            quad.Size = new Vector2(0.16, 0.16);
            var mm = new StandardMaterial3D();
            mm.ShadingMode = BaseMaterial3D.SHADING_MODE_UNSHADED;
            mm.Transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
            mm.BlendMode = BaseMaterial3D.BLEND_MODE_ADD;
            mm.BillboardMode = BaseMaterial3D.BILLBOARD_PARTICLES;
            mm.VertexColorUseAsAlbedo = true;
            mm.AlbedoTexture = _SoftDot();
            mm.AlbedoColor = new Color(2.2, 2.0, 1.4, 0.75);
            quad.Material = mm;
            _motes = new GPUParticles3D();
            _motes.Amount = 90;
            _motes.Lifetime = 9.0;
            _motes.Preprocess = 9.0;
            _motes.LocalCoords = false;
            _motes.ProcessMaterial = pm;
            _motes.DrawPass1 = quad;
            _motes.VisibilityAabb = new AABB(new Vector3(-24, -4, -24), new Vector3(48, 10, 48));
            _motes.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            AddChild(_motes);
            // Wall torches either side of each keep's middle gate, on the wall's inner face: a warm, flickering light (the KayKit
            // RPG Tools torch). (In each Siege castle's dungeon until 0.31.165.)
            var torch_scene = Stage.Scene("res://assets/kaykit/tools/torch.gltf");
            for (int t = 0; t < 2; t++)
            {
                Vector2 gm = Keep.GateC(1);
                foreach (var spot in new[] { gm + new Vector2(-4.3, 1.4), gm + new Vector2(4.3, 1.4) })
                {
                    Vector2 into0 = (Keep.C - spot).Normalized();
                    Vector2 p = Sim.M(t, spot);
                    Vector2 into = Sim.M(t, spot + into0) - p;
                    var fy = Sim.HeightAt(p + into * 0.6) + 1.9;
                    if (torch_scene != null)
                    {
                        Node3D tm = torch_scene.Instantiate() as Node3D;
                        tm.Scale = Vector3.ONE * 2.2;
                        AddChild(tm);
                        tm.GlobalPosition = new Vector3(p.x, fy - 1.3, p.y) + new Vector3(into.x, 0.0, into.y) * 0.35;
                        tm.Rotation = new Vector3(0.0, Sim.AngleOf(into), 0.0);
                        tm.RotateObjectLocal(Vector3.RIGHT, 0.35);
                    }
                    var light = new OmniLight3D();
                    light.LightColor = new Color("#ffb05a");
                    light.LightEnergy = 1.6;
                    light.OmniRange = 6.0;
                    light.OmniAttenuation = 1.3;
                    light.ShadowEnabled = false;
                    AddChild(light);
                    light.GlobalPosition = new Vector3(p.x, fy, p.y) + new Vector3(into.x, 0.0, into.y) * 0.6;
                    var flame = new MeshInstance3D();
                    var fq = new QuadMesh();
                    fq.Size = new Vector2(0.6, 0.9);
                    var fmat = new StandardMaterial3D();
                    fmat.ShadingMode = BaseMaterial3D.SHADING_MODE_UNSHADED;
                    fmat.Transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
                    fmat.BlendMode = BaseMaterial3D.BLEND_MODE_ADD;
                    fmat.BillboardMode = BaseMaterial3D.BILLBOARD_ENABLED;
                    fmat.AlbedoTexture = _SoftDot();
                    fmat.AlbedoColor = new Color(2.4, 1.3, 0.45, 0.9);
                    fq.Material = fmat;
                    flame.Mesh = fq;
                    flame.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
                    AddChild(flame);
                    flame.GlobalPosition = light.GlobalPosition + new Vector3(0.0, -0.15, 0.0);
                    _torches.Append(GArray.Of(light, flame, 1.6, GD.Randf() * 10.0));
                }
            }
        }

        public void _SyncAmbience(double _dt)
        {
            if (_motes != null && GD.IsInstanceValid(camera) && camera.IsInsideTree())
            {
                var cp = camera.GlobalPosition;
                var fwd = -camera.GlobalTransform.basis.z;
                if (fwd.y < -0.05)
                {
                    var hit = cp + fwd * (-cp.y / fwd.y);
                    _motes.GlobalPosition = hit + new Vector3(0.0, 2.2, 0.0);
                }
            }
            foreach (var tr in _torches)
            {
                double ph = (double)tr[3];
                var k = 0.82 + 0.1 * Math.Sin(_time * 9.0 + ph) + 0.08 * Math.Sin(_time * 23.0 + ph * 1.7);
                tr[0].As<OmniLight3D>().LightEnergy = (double)tr[2] * k;
                tr[1].As<Node3D>().Scale = Vector3.ONE * (0.9 + 0.12 * k);
            }
        }

        // ---------- Water you can wade through, with simulated waves (Round 33) ----------
        // Kevin: "make the water look much more realistic, like actually simulated water ... realistic physics that create
        // wakes". A height field over the river (RIP_W x RIP_H, ~13 cm cells) is stepped every frame on the GPU with the
        // wave equation (two SubViewports ping-pong: R = height now, G = height a step ago). Each wading unit pushes on it in
        // proportion to its speed, so wakes, rings and bank reflections come out of the physics. The water shader lights the
        // resulting slopes (plus flowing detail), reflects the sky at grazing angles, is see-through over the bed, and foams
        // on the banks and the wave crests. High-quality graphics only; without it the old water stays.
        // 0.30.0: the field is wider and the river opens into a lake round the island, so the simulated patch spans the
        // whole field and the lake's full width (still ~13 cm cells). UV.y on the water mesh is this patch's across
        // coordinate (centred on the river line); UV2.y runs 0..1 bank to bank for the shallows.
        public const int RIP_W = 680;
        public const int WATER_ROWS = 10;                      // 0.31.21: vertices across the river, so waves can lift the surface
        public const int RIP_H = 198;
        public const double RIP_HALF = Land.HALF_W;                  // the simulated stretch: x in [-44, 44]
        public const double RIP_ACROSS = (Land.RIVER_HW + Land.LAKE_EXTRA + 0.35) * 2.0;     // the lake at its widest
        public GArray _rip_vp = new GArray();
        public GArray _rip_mat = new GArray();
        public int _rip_i = 0;
        public GDict _rip_prev = new GDict();                 // unit id -> [last pos, was wet]

        public ShaderMaterial _WaterHqMaterial()
        {
            var sh = new Shader();
            sh.Code = "\n" +
                "shader_type spatial;\n" +
                "render_mode cull_disabled, blend_mix, depth_draw_opaque;\n" +
                "uniform sampler2D ripples : filter_linear_mipmap, repeat_enable;\n" +
                "uniform sampler2D rip_tex : filter_linear, repeat_disable;\n" +
                "uniform float rip_half = 34.0;\n" +
                "uniform vec2 rip_texel = vec2(0.001953, 0.019231);\n" +
                "uniform float rip_strength = 28.0;\n" +
                "uniform float wake_tint = 4.5;            // crests lighter, troughs darker: how the wakes show without foam\n" +
                "uniform vec3 deep_col : source_color = vec3(0.05, 0.33, 0.40);\n" +
                "uniform vec3 shallow_col : source_color = vec3(0.26, 0.66, 0.62);\n" +
                "uniform vec3 sky_col : source_color = vec3(0.62, 0.80, 0.95);\n" +
                "uniform float glint = 0.0;\n" +
                "uniform float wave_height = 1.5;          // 0.31.21: the surface rises and falls with the simulated waves\n" +
                "varying vec3 wpos;\n" +
                "void vertex() {\n" +
                "\twpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;\n" +
                "\tvec2 ruv = vec2((wpos.x + rip_half) / (2.0 * rip_half), UV.y);\n" +
                "\tfloat inside = step(0.0, ruv.x) * step(ruv.x, 1.0);\n" +
                "\tfloat h = textureLod(rip_tex, ruv, 0.0).r * inside;\n" +
                "\th = (isnan(h) || isinf(h)) ? 0.0 : h;\n" +
                "\tfloat edge = smoothstep(0.0, 0.1, UV2.y) * smoothstep(1.0, 0.9, UV2.y);     // held at the banks\n" +
                "\tVERTEX.y += h * wave_height * edge;\n" +
                "\twpos.y += h * wave_height * edge;\n" +
                "}\n" +
                "float detail(vec2 p) {\n" +
                "\treturn texture(ripples, p * 0.11 + vec2(-TIME * 0.035, 0.0)).r * 0.6\n" +
                "\t\t+ texture(ripples, p * 0.23 + vec2(-TIME * 0.05, TIME * 0.02)).r * 0.4;\n" +
                "}\n" +
                "void fragment() {\n" +
                "\t// Flowing detail (the river runs toward -x) from finite differences of two scrolling layers.\n" +
                "\tfloat e = 0.2;\n" +
                "\tfloat d0 = detail(wpos.xz);\n" +
                "\tvec2 slope = vec2(detail(wpos.xz + vec2(e, 0.0)) - d0, detail(wpos.xz + vec2(0.0, e)) - d0) / e * 0.22;\n" +
                "\t// The simulated waves.\n" +
                "\tvec2 ruv = vec2((wpos.x + rip_half) / (2.0 * rip_half), UV.y);\n" +
                "\tfloat inside = step(0.0, ruv.x) * step(ruv.x, 1.0);\n" +
                "\tfloat h = texture(rip_tex, ruv).r * inside;\n" +
                "\tfloat hx = (texture(rip_tex, ruv + vec2(rip_texel.x, 0.0)).r - texture(rip_tex, ruv - vec2(rip_texel.x, 0.0)).r) * inside;\n" +
                "\tfloat hz = (texture(rip_tex, ruv + vec2(0.0, rip_texel.y)).r - texture(rip_tex, ruv - vec2(0.0, rip_texel.y)).r) * inside;\n" +
                "\tif (isnan(h + hx + hz) || isinf(h + hx + hz)) { h = 0.0; hx = 0.0; hz = 0.0; }\n" +
                "\tslope += clamp(vec2(hx, hz) * rip_strength, vec2(-1.5), vec2(1.5));\n" +
                "\tvec3 wn = normalize(vec3(-slope.x, 1.0, -slope.y));\n" +
                "\tNORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);\n" +
                "\tfloat edge = min(UV2.y, 1.0 - UV2.y);\n" +
                "\tfloat depth = smoothstep(0.02, 0.4, edge);\n" +
                "\tvec3 col = mix(shallow_col, deep_col, depth);\n" +
                "\tfloat fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);\n" +
                "\tcol = mix(col, sky_col, clamp(fres * 0.3, 0.0, 0.25));     // (0.31.216: 0.5 -- the river bed shows through now)\n" +
                "\t// No foam (Round 34, Kevin). The wakes read as light crests and dark troughs instead.\n" +
                "\tcol *= 1.0 + clamp(h, -0.12, 0.12) * wake_tint;\n" +
                "\tALBEDO = col;\n" +
                "\tALPHA = mix(0.38, 0.66, depth);              // (0.31.216: 0.58 .. 0.86: the painted river bed shows through)\n" +
                "\tROUGHNESS = 0.16;                 // 0.30.11: was 0.05 / 0.75 -- the sun's glare spread white over the wide lake\n" +
                "\tSPECULAR = 0.35;\n" +
                "\tfloat sg = texture(ripples, wpos.xz * 0.19 + vec2(-TIME * 0.09, TIME * 0.05)).r * texture(ripples, wpos.xz * 0.13 + vec2(TIME * 0.07, -TIME * 0.04)).r;\n" +
                "\tEMISSION = vec3(1.0, 0.97, 0.88) * smoothstep(0.58, 0.64, sg) * glint;\n" +
                "}\n";
            var m = new ShaderMaterial();
            m.Shader = sh;
            var nt = new NoiseTexture2D();
            nt.Width = 256;
            nt.Height = 256;
            nt.Seamless = true;
            var fn = new FastNoiseLite();
            fn.Frequency = 0.04;
            nt.Noise = fn;
            m.SetShaderParameter("ripples", nt);
            m.SetShaderParameter("glint", 1.3);
            m.SetShaderParameter("rip_half", RIP_HALF);
            m.SetShaderParameter("rip_texel", new Vector2(1.0 / RIP_W, 1.0 / RIP_H));
            return m;
        }

        public GArray _rip_kicks = new GArray();

        public void WaterBlast(Vector2 at, double power)
        {
            // 0.31.21 (Kevin: "the water to react to the bomb explosion and make huge waves"): a blast in or beside the river
            // pushes the water down hard where it hits for a few frames; the wave equation throws the rings out across it.
            // Also a column of spray.
            var c = Land.RiverC(at.x);
            var hw = Land.RiverHw(at.x);
            var off = at.y - c;
            var reach = Math.Abs(off) - hw;                   // how far from the water's edge (negative: in the water)
            if (reach > 5.0 || Math.Abs(at.x) > RIP_HALF - 1.0)
                return;
            var p = new Vector2(at.x, c + GD.Clampf(off, -hw + 0.6, hw - 0.6));
            var k = power * GD.Clampf(1.0 - GD.Maxf(reach, 0.0) / 5.0, 0.25, 1.0);
            _rip_kicks.Append(GDict.Of("p", p, "frames", 4, "r", 2.4 * Math.Sqrt(power), "s", -0.5 * k));
            var sp = new Vector3(p.x, Land.WATER_Y + 0.1, p.y);
            for (int i = 0; i < (int)(30 * k); i++)
                Spark(sp + new Vector3(GD.RandfRange(-1.2, 1.2), GD.RandfRange(0.0, 3.5 * k), GD.RandfRange(-1.2, 1.2)), new Color(0.88, 0.95, 1.0));
            RingAt(sp, new Color(0.85, 0.95, 1.0), 4.0 * k + 1.0, 0.9);
        }

        public void _BuildRipples()
        {
            var sh = new Shader();
            sh.Code = "\n" +
                "shader_type canvas_item;\n" +
                "render_mode blend_disabled;\n" +
                "uniform sampler2D prev : filter_nearest, repeat_disable;\n" +
                "uniform vec2 texel;\n" +
                "uniform vec2 cell_m;\n" +
                "uniform vec4 drops[16];\n" +
                "uniform int drop_count = 0;\n" +
                "uniform float damping = 0.989;            // wakes trail longer (Round 34)\n" +
                "void fragment() {\n" +
                "\tvec4 p = texture(prev, UV);\n" +
                "\tfloat n = texture(prev, UV + vec2(texel.x, 0.0)).r + texture(prev, UV - vec2(texel.x, 0.0)).r\n" +
                "\t\t+ texture(prev, UV + vec2(0.0, texel.y)).r + texture(prev, UV - vec2(0.0, texel.y)).r;\n" +
                "\tfloat h = (n * 0.5 - p.g) * damping;\n" +
                "\tfor (int i = 0; i < 16; i++) {\n" +
                "\t\tif (i >= drop_count) { break; }\n" +
                "\t\tvec2 d = (UV - drops[i].xy) / texel * cell_m;\n" +
                "\t\tfloat r = drops[i].z;\n" +
                "\t\th += drops[i].w * exp(-dot(d, d) / (r * r));\n" +
                "\t}\n" +
                "\th *= smoothstep(0.0, 0.03, UV.y) * smoothstep(1.0, 0.97, UV.y);\n" +
                "\t// 0.30.11: the lake made the simulated patch 5x bigger. A bad cell (NaN/inf) would spread and the water would\n" +
                "\t// render white (Kevin's screenshot): clamp and scrub every step.\n" +
                "\th = (isnan(h) || isinf(h)) ? 0.0 : clamp(h, -0.6, 0.6);\n" +
                "\tfloat pr = (isnan(p.r) || isinf(p.r)) ? 0.0 : clamp(p.r, -0.6, 0.6);\n" +
                "\tCOLOR = vec4(h, pr, 0.0, 1.0);\n" +
                "}\n";
            for (int k = 0; k < 2; k++)
            {
                var vp = new SubViewport();
                vp.Size = new Vector2i(RIP_W, RIP_H);
                vp.UseHdr2D = true;
                vp.Disable3D = true;
                vp.TransparentBg = false;
                vp.RenderTargetUpdateMode = SubViewport.UPDATE_DISABLED;
                var cr = new ColorRect();
                cr.Size = new Vector2(RIP_W, RIP_H);
                var m = new ShaderMaterial();
                m.Shader = sh;
                m.SetShaderParameter("texel", new Vector2(1.0 / RIP_W, 1.0 / RIP_H));
                m.SetShaderParameter("cell_m", new Vector2(2.0 * RIP_HALF / RIP_W, RIP_ACROSS / RIP_H));
                cr.Material = m;
                vp.AddChild(cr);
                AddChild(vp);
                _rip_vp.Append(vp);
                _rip_mat.Append(Var.Of(m));
            }
        }

        // 0.31.219: the wave field stepped at most RIP_HZ times a second -- its speed and damping were tuned at the 30 fps cap
        // (Round 33-34); at 60 fps it ran twice as fast, and an extra pass on the graphics chip every frame -- and not at all
        // once it has been still for RIP_REST seconds (no one wading, no blast: flat again by then), till someone wades in.
        public const double RIP_HZ = 30.0;
        public const double RIP_REST = 6.0;
        public double _rip_acc = 0.0;
        public double _rip_quiet = 0.0;

        public void _SyncRipples(double dt)
        {
            if (_rip_vp.IsEmpty() || _water_mat == null)
                return;
            _rip_acc += dt;
            if (_rip_acc < 1.0 / RIP_HZ - 0.002)
                return;
            dt = GD.Minf(_rip_acc, 0.1);
            _rip_acc = 0.0;
            var drops = new List<Vector4>();
            foreach (var u in sim.units)
            {
                if (!sim.Alive(u) || _Fogged(u))
                {
                    _rip_prev.Erase(u.id);
                    continue;
                }
                Vector2 p = u.pos;
                var wet = Sim.WaterDepth(p) > 0.05 && Math.Abs(p.x) < RIP_HALF - 0.5;     // (0.31.165: the Rift's shallow river)
                GArray last = _rip_prev.Get(u.id, GArray.Of(p, false)).A;
                double spd = (p - last[0].AsVec2()).Length() / GD.Maxf(dt, 0.001);
                if (wet && drops.Count < 16)
                {
                    var v = (p.y - (Land.RiverC(p.x) - RIP_ACROSS * 0.5)) / RIP_ACROSS;
                    var strength = 0.005 + GD.Minf(spd, 6.0) * 0.0085;          // (Round 34: twice as strong, no foam to hide it)
                    var radius = 0.42;
                    if (!(bool)last[1])
                    {
                        strength = 0.06;                              // stepping in: a splash
                        radius = 0.7;
                        var sp = new Vector3(p.x, Land.WATER_Y + 0.05, p.y);
                        for (int k = 0; k < 8; k++)
                            Spark(sp + new Vector3(GD.RandfRange(-0.4, 0.4), GD.RandfRange(0.0, 0.6), GD.RandfRange(-0.4, 0.4)), new Color(0.9, 0.96, 1.0));
                    }
                    drops.Add(new Vector4((p.x + RIP_HALF) / (2.0 * RIP_HALF), v, radius, strength));
                }
                _rip_prev[u.id] = GArray.Of(p, wet);
            }
            for (int i = _rip_kicks.Size() - 1; i > -1; i--)
            {
                GDict kk = _rip_kicks[i].D;
                Vector2 kp = kk["p"].AsVec2();
                var kv = (kp.y - (Land.RiverC(kp.x) - RIP_ACROSS * 0.5)) / RIP_ACROSS;
                drops.Insert(0, new Vector4((kp.x + RIP_HALF) / (2.0 * RIP_HALF), kv, (double)kk["r"], (double)kk["s"]));
                kk["frames"] = (int)kk["frames"] - 1;
                if ((int)kk["frames"] <= 0)
                    _rip_kicks.RemoveAt(i);
            }
            if (drops.Count > 16)
                drops.RemoveRange(16, drops.Count - 16);
            _rip_quiet = drops.Count != 0 ? 0.0 : _rip_quiet + dt;
            if (_rip_quiet > RIP_REST)
                return;                                     // (still: nothing to step)
            var cur = _rip_i % 2;
            var other = 1 - cur;
            ShaderMaterial m = _rip_mat[cur].As<ShaderMaterial>();
            m.SetShaderParameter("prev", _rip_vp[other].As<SubViewport>().GetTexture());
            var arr = new Vector4[16];
            for (int i = 0; i < drops.Count; i++)
                arr[i] = drops[i];
            m.SetShaderParameter("drops", arr);
            m.SetShaderParameter("drop_count", drops.Count);
            _rip_vp[cur].As<SubViewport>().RenderTargetUpdateMode = SubViewport.UPDATE_ONCE;
            _water_mat.SetShaderParameter("rip_tex", _rip_vp[other].As<SubViewport>().GetTexture());
            _rip_i += 1;
        }
    }
}
