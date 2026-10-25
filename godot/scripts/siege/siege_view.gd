extends Node3D
const Eco = preload("res://scripts/meta/economy.gd")
# Presentation only: mirrors siege_sim state every frame and never changes it.
const Stage = preload("res://scripts/siege/asset_cache.gd")
const Land = preload("res://scripts/siege/siege_land.gd")
const FLOOR_TILE := 3.2            # the keeps' floor texture's period in metres (the old castle_mesh.gd's, as on the map paths)
const CastleKit = preload("res://scripts/siege/castle_kit.gd")
const Keep = preload("res://scripts/siege/keep.gd")       # 0.31.165: the Rift's keeps (the Siege castles' builders are unused)
static var CASTLE_KITS := true      # 0.31.74 Meshy castle kits (castle_kit.gd); false = the KayKit castle (tools compare)
const PATH_TEX := preload("res://assets/terrain/path.png")       # (the castle floors' herringbone when there's no kit)
const DIRT_TEX := preload("res://assets/terrain/dirt.png")       # 0.31.126: the map's dirt paths (tools/make_dirt_texture.py)
const Sim = preload("res://scripts/siege/siege_sim.gd")
const WeaponFx = preload("res://scripts/siege/weapon_fx.gd")
const SpellFx = preload("res://scripts/siege/spell_fx.gd")      # 0.31.201: the abilities' effects
var fxs = null                                                   # (SpellFx, a child; made in setup_steps)
const EyeFx = preload("res://scripts/siege/eye_fx.gd")         # 0.31.192: the Necromancer's glowing, smoking eyes
const WyrmBody = preload("res://scripts/siege/wyrm_body.gd")   # 0.31.166: the Grave Wyrm (a body without a rig)
const Foliage = preload("res://scripts/siege/foliage.gd")      # 0.31.173: the Meshy trees and bushes
const Towers = preload("res://scripts/siege/towers.gd")        # 0.31.172: the 5v5's towers (Meshy, breaking as they're hurt)
signal tower_broke(at: Vector3, stage: int)                    # (siege_mode plays the crumble)

const HEX := "res://assets/kaykit/hex/"
const FOREST := "res://assets/kaykit/forest/"
const TEAM_COLORS := [Color("#5fd2f0"), Color("#ff7b52"), Color("#e2c85c")]      # (0.31.157: the third, the jungle's monsters)
const GOLD := Color("#ffd46a")
# The Vulkan (Mobile renderer) look; the only renderer since 0.31.92 (OpenGL removed). 0.31.71 (Kevin, comparing the
# two renderers side by side: "OpenGL looks better"): retuned so Vulkan matches the OpenGL render -- deeper shadows, brighter sunlit tops, the same
# colour. Measured on the same shots (tools/building_shot.gd, FB_VK_* env), luminance p10/p50/p90 and saturation:
# OpenGL .10/.40/.72 s.54; Vulkan before (1.55, 2.25, 1, 1) .29/.47/.69 s.46; now .18/.38/.74 s.56.
static var VULKAN_EXPOSURE := 2.0     # was 1.55
static var VULKAN_AMBIENT := 1.05     # was 2.25
static var VULKAN_CONTRAST := 1.2     # Vulkan-only multipliers on the colour adjustments
static var VULKAN_SATURATION := 0.96

# Model, weapons (right/left hand) and clips per class. Clip keys: g general, m melee, r ranged,
# mb movement basic, ma movement advanced. (0.31.169: the KayKit Tools set -- chopping, fishing, carrying -- went with Siege.)
# 0.31.128 (Kevin: "make their idle animations the same as knight so the others aren't bouncing up and down so much"):
# every class stands in the Knight's g/Idle_A (its hips move 1.5 cm; g/Idle_B's 10 cm, Melee_2H_Idle's 3.6 cm) -- but
# the two archers, whose r/Ranged_Bow_Idle doesn't bob at all (0 cm) and holds the bow up with its string toward them:
# in g/Idle_A the bow hand is the Knight's shield hand and every bow's string turned away (tests/weapon_grip_test.gd).
# The *_kaykit entries below keep theirs (tools/retarget_meshy.gd's reference bodies only).
const LOOKS := {
	# 0.31.76 (Kevin picked concepts "A2 both"): the Worker a Meshy straw-hat farmer (green overalls, red bandana,
	# gloves); he was the KayKit Rogue. (Siege's class: his weapons still come round in the shop.)
	"worker": {"model":"meshy:worker","r":"mw/work_hatchet","l":"","idle":"g/Idle_A","attack":"m/Melee_1H_Attack_Chop","ability":"m/Melee_1H_Attack_Chop","combo":["m/Melee_1H_Attack_Chop","m/Melee_1H_Attack_Slice_Horizontal","m/Melee_1H_Attack_Stab"]},
	"knight": {"model":"meshy:knight","r":"mw/squire_sword","l":"mw/squire_shield","idle":"g/Idle_A","attack":"m/Melee_1H_Attack_Slice_Diagonal","ability":"m/Melee_Blocking","combo":["m/Melee_1H_Attack_Slice_Diagonal","m/Melee_1H_Attack_Slice_Horizontal","m/Melee_Block_Attack"]},
	"crusader": {"model":"meshy:crusader","r":"mw/templar_sword","l":"mw/templar_shield","idle":"g/Idle_A","attack":"m/Melee_1H_Attack_Slice_Diagonal","ability":"m/Melee_Blocking","combo":["m/Melee_1H_Attack_Slice_Diagonal","m/Melee_1H_Attack_Slice_Horizontal","m/Melee_Block_Attack"]},
	# Upgraded barbarian (Round 11): two-handed greatsword, whirlwind.
	"berserker": {"model":"meshy:berserker","r":"mw/ironhewer_greatsword","l":"","idle":"g/Idle_A","attack":"m/Melee_2H_Attack_Chop","ability":"m/Melee_2H_Attack_Spinning","combo":["m/Melee_2H_Attack_Chop","m/Melee_2H_Attack_Slice","m/Melee_2H_Attack_Spin"]},
	"barbarian": {"model":"meshy:barbarian","r":"mw/woodsplitter_axe","l":"","idle":"g/Idle_A","attack":"m/Melee_2H_Attack_Slice","ability":"m/Melee_2H_Attack_Spin","combo":["m/Melee_2H_Attack_Slice","m/Melee_2H_Attack_Chop","m/Melee_2H_Attack_Stab"]},
	"rogue": {"model":"meshy:rogue","r":"mw/cutpurse_dagger","l":"mw/cutpurse_dagger","idle":"g/Idle_A","attack":"m/Melee_Dualwield_Attack_Stab","ability":"m/Melee_1H_Attack_Jump_Chop","combo":["m/Melee_Dualwield_Attack_Stab","m/Melee_Dualwield_Attack_Slice","m/Melee_Dualwield_Attack_Chop"]},
	"ranger": {"model":"meshy:ranger","r":"","l":"mw/ashwood_bow","idle":"r/Ranged_Bow_Idle","attack":"r/Ranged_Bow_Release","ability":"r/Ranged_Bow_Release_Up"},
	"mage": {"model":"meshy:mage","r":"mw/apprentice_staff","l":"","idle":"g/Idle_A","attack":"r/Ranged_Magic_Shoot","ability":"r/Ranged_Magic_Spellcasting"},
	# Healer: a body of his own since 0.31.80 (white and gold robes, sun emblem, gold circlet), with a wand.
	"priest": {"model":"meshy:priest","r":"mw/acolyte_wand","l":"","idle":"g/Idle_A","attack":"r/Ranged_Magic_Spellcasting_Long","ability":"r/Ranged_Magic_Raise"},
	# Upgraded priest (0.31.2, Kevin): the Necromancer from KayKit Skeletons (CC0, same Rig_Medium) with the skull staff.
	# 0.31.32: the last three upgrades get their own looks
	"assassin": {"model":"meshy:assassin","r":"mw/shade_dagger","l":"mw/shade_dagger","idle":"g/Idle_A","attack":"m/Melee_Dualwield_Attack_Stab","ability":"m/Melee_1H_Attack_Jump_Chop","tint":"#5b4f73","combo":["m/Melee_Dualwield_Attack_Stab","m/Melee_Dualwield_Attack_Slice","m/Melee_Dualwield_Attack_Chop"]},
	"sniper": {"model":"meshy:sniper","r":"mw/marksman_crossbow","l":"","idle":"r/Ranged_Bow_Idle","attack":"r/Ranged_Bow_Release","ability":"r/Ranged_Bow_Draw","tint":"#4f6b4a"},
	"archmage": {"model":"meshy:archmage","r":"mw/magister_staff","l":"mw/magister_book","idle":"g/Idle_A","attack":"r/Ranged_Magic_Shoot","ability":"r/Ranged_Magic_Summon","tint":"#a33d3d"},
	"necromancer": {"model":"meshy:necromancer","r":"mw/bonecaller_staff","l":"","idle":"g/Idle_A","attack":"r/Ranged_Magic_Spellcasting_Long","ability":"r/Ranged_Magic_Raise"},
	"necromancer_kaykit": {"model":"Necromancer","r":"Skeleton_Staff","l":"","idle":"g/Idle_B","attack":"r/Ranged_Magic_Spellcasting_Long","ability":"r/Ranged_Magic_Raise"},          # 0.31.63: the stock body, kept for tools/retarget_meshy.gd
	"villager_kaykit": {"model":"Rogue","r":"","l":"","idle":"g/Idle_A","attack":"m/Melee_Unarmed_Attack_Punch_A","ability":"m/Melee_Unarmed_Attack_Kick"},          # 0.31.76: the old body of both, kept for tools/retarget_meshy.gd
	# 0.31.80 (Kevin picked base-class concepts): the six base classes are Meshy bodies too; their stock KayKit bodies stay
	# here for tools/retarget_meshy.gd (the skeleton and height each bake starts from) -- the Priest's was the Mage's.
	"knight_kaykit": {"model":"Knight","r":"","l":"","idle":"g/Idle_A","attack":"m/Melee_1H_Attack_Slice_Diagonal","ability":"m/Melee_Blocking"},
	"barbarian_kaykit": {"model":"Barbarian","r":"","l":"","idle":"m/Melee_2H_Idle","attack":"m/Melee_2H_Attack_Slice","ability":"m/Melee_2H_Attack_Spin"},
	"rogue_kaykit": {"model":"Rogue_Hooded","r":"","l":"","idle":"g/Idle_B","attack":"m/Melee_Dualwield_Attack_Stab","ability":"m/Melee_1H_Attack_Jump_Chop"},
	"ranger_kaykit": {"model":"Ranger","r":"","l":"","idle":"r/Ranged_Bow_Idle","attack":"r/Ranged_Bow_Release","ability":"r/Ranged_Bow_Release_Up"},
	"mage_kaykit": {"model":"Mage","r":"","l":"","idle":"g/Idle_B","attack":"r/Ranged_Magic_Shoot","ability":"r/Ranged_Magic_Spellcasting"},
	# 0.31.157 5V5 -- the jungle's monsters and the Necromancer's LEGION: KayKit Skeletons 1.0 (CC0; their own embedded
	# animations stripped out -- the rig is the Adventurers' one, so the game's Rig_Medium libraries drive them)
	"skel_minion": {"model":"Skeleton_Minion","r":"Skeleton_Blade","l":"","idle":"g/Idle_A","attack":"m/Melee_1H_Attack_Chop","ability":"m/Melee_1H_Attack_Jump_Chop","combo":["m/Melee_1H_Attack_Chop","m/Melee_1H_Attack_Slice_Diagonal","m/Melee_1H_Attack_Slice_Horizontal"]},
	"skel_warrior": {"model":"Skeleton_Warrior","r":"Skeleton_Axe","l":"Skeleton_Shield_Small_A","idle":"g/Idle_A","attack":"m/Melee_1H_Attack_Chop","ability":"m/Melee_2H_Attack_Spin","combo":["m/Melee_1H_Attack_Chop","m/Melee_1H_Attack_Slice_Horizontal","m/Melee_Block_Attack"]},
	"skel_rogue": {"model":"Skeleton_Rogue","r":"Skeleton_Crossbow","l":"","idle":"r/Ranged_Bow_Idle","attack":"r/Ranged_Bow_Release","ability":"r/Ranged_Bow_Release_Up"},
	"skel_mage": {"model":"Skeleton_Mage","r":"Skeleton_Staff","l":"","idle":"g/Idle_A","attack":"r/Ranged_Magic_Shoot","ability":"r/Ranged_Magic_Spellcasting","tint":"#b9a8ff"},
	"skel_brute": {"model":"Skeleton_Warrior","r":"Skeleton_Axe","l":"Skeleton_Shield_Large_A","idle":"g/Idle_A","attack":"m/Melee_1H_Attack_Chop","ability":"m/Melee_2H_Attack_Spin","tint":"#ff9b7a","combo":["m/Melee_1H_Attack_Chop","m/Melee_1H_Attack_Slice_Horizontal","m/Melee_Block_Attack"]},
	# 0.31.159 5V5 lane minions (Kevin picked the A1 concepts, "the King's levy"): Meshy bodies of their own -- a kettle-
	# helm footman (short sword, round buckler), a wide-brimmed crossbowman (hand crossbow, the bow's clips as the Ranger's), a
	# goggled bombardier (powder keg on his back, a bronze hand-cannon thrust out to fire -- the Mage's shot), a castle
	# champion (a big war hammer). (KayKit's 1H / 2H gun clips hold a piece fit like the crossbows straight up.) Their props are Meshy pieces from one parts sheet, fit to KayKit templates (MESHY_WEAPON_LIKE).
	"minion_melee": {"model":"meshy:minion_melee","r":"mw/minion_sword","l":"mw/minion_buckler","idle":"g/Idle_A","attack":"m/Melee_1H_Attack_Slice_Diagonal","ability":"m/Melee_1H_Attack_Stab","combo":["m/Melee_1H_Attack_Slice_Diagonal","m/Melee_1H_Attack_Slice_Horizontal","m/Melee_1H_Attack_Stab"]},
	"minion_caster": {"model":"meshy:minion_caster","r":"mw/minion_crossbow","l":"","idle":"r/Ranged_Bow_Idle","attack":"r/Ranged_Bow_Release","ability":"r/Ranged_Bow_Draw"},
	"minion_siege": {"model":"meshy:minion_siege","r":"mw/minion_cannon","l":"","idle":"g/Idle_A","attack":"r/Ranged_Magic_Shoot","ability":"r/Ranged_Magic_Spellcasting"},
	"minion_super": {"model":"meshy:minion_super","r":"mw/minion_hammer","l":"","idle":"m/Melee_2H_Idle","attack":"m/Melee_2H_Attack_Chop","ability":"m/Melee_2H_Attack_Spin","combo":["m/Melee_2H_Attack_Chop","m/Melee_2H_Attack_Slice","m/Melee_2H_Attack_Stab"]},
	"skel_lord": {"model":"Skeleton_Warrior","r":"Skeleton_Axe","l":"Skeleton_Shield_Large_A","idle":"g/Idle_A","attack":"m/Melee_1H_Attack_Chop","ability":"m/Melee_2H_Attack_Spin","tint":"#a993d6","combo":["m/Melee_1H_Attack_Chop","m/Melee_1H_Attack_Slice_Horizontal","m/Melee_Block_Attack"]},
	# 0.31.166 (Kevin picked concept "A"): the Grave Wyrm, a skeletal dragon from Meshy -- a body of its own with no rig
	# (wyrm_body.gd: its limbs bent in a shader, its clips its own). "size": its scale in place of BODY_SCALE x mscale
	# (the model is 4 m tall); "ring": its ring's radius.
	"wyrm": {"model":"prop:wyrm","r":"","l":"","idle":"w/Idle","attack":"w/Bite","ability":"w/Swipe","combo":["w/Bite","w/Bite","w/Swipe"],"size":1.0,"ring":2.4},
	# 0.31.168 (Kevin picked six new 5v5 heroes, one a role): Meshy bodies (KK_FOR in tools/retarget_meshy.gd) and Meshy
	# props from one parts sheet of the six concepts (assets/meshy/weapons): the Golem's rune hammer and stone slab shield,
	# the Dragoon's halberd, the Duelist's rapier (and a parrying dagger), the Stormcaller's trident staff, the
	# Musketeer's flintlock, the Druid's living-wood staff. Not cosmetics: unit_cosmetic leaves them as they are.
	"golem": {"model":"meshy:golem","r":"mw/golem_hammer","l":"mw/golem_shield","idle":"g/Idle_A","attack":"m/Melee_1H_Attack_Chop","ability":"m/Melee_Block_Attack","combo":["m/Melee_1H_Attack_Chop","m/Melee_1H_Attack_Slice_Horizontal","m/Melee_Block_Attack"]},
	"dragoon": {"model":"meshy:dragoon","r":"mw/dragoon_halberd","l":"","idle":"g/Idle_A","attack":"m/Melee_2H_Attack_Stab","ability":"m/Melee_2H_Attack_Slice","combo":["m/Melee_2H_Attack_Stab","m/Melee_2H_Attack_Slice","m/Melee_2H_Attack_Chop"]},
	"duelist": {"model":"meshy:duelist","r":"mw/duelist_rapier","l":"mw/needlepoint_stiletto","idle":"g/Idle_A","attack":"m/Melee_1H_Attack_Stab","ability":"m/Melee_1H_Attack_Jump_Chop","combo":["m/Melee_1H_Attack_Stab","m/Melee_Dualwield_Attack_Slice","m/Melee_1H_Attack_Stab"]},
	"stormcaller": {"model":"meshy:stormcaller","r":"mw/storm_staff","l":"","idle":"g/Idle_A","attack":"r/Ranged_Magic_Shoot","ability":"r/Ranged_Magic_Spellcasting"},
	"musketeer": {"model":"meshy:musketeer","r":"mw/musket","l":"","idle":"r/Ranged_Bow_Idle","attack":"r/Ranged_Bow_Release","ability":"r/Ranged_Bow_Draw"},
	"druid": {"model":"meshy:druid","r":"mw/druid_staff","l":"","idle":"g/Idle_A","attack":"r/Ranged_Magic_Shoot","ability":"r/Ranged_Magic_Raise"},
}
const MINION_LOOKS := {"melee":"minion_melee", "caster":"minion_caster", "siege":"minion_siege", "super":"minion_super"}
const LOOP_HINTS := ["Idle","Running","Walking","Hammering","Holding","Aiming","_Pose","Blocking","Chopping","Pickaxing"]

static var _libs: Dictionary = {}
# Shared GPU resources: one mesh/shader per effect type instead of one per hit, so fights don't
# churn buffers or trigger new shader compiles mid-match.
static var _spark_mesh: SphereMesh
static var _rings: Dictionary = {}

var sim
var player_id := "you"
# 0.31.85 (Kevin: "When on the other team, it still thinks I'm on the other team ... health bars are red for my team"):
# your side is always drawn blue and the other red -- rings, health bars, castle roofs and banners, throne, King,
# outposts, hat shops. `my_side` is the player's team (0 offline; online, whichever the server seated you on); vt() maps a
# team to the colour it is drawn in. Positions and facing still use the real team.
var my_side := 0
var player_names := {}                     # unit id -> name: the live players online (0.31.86; the server's "pn")
var player_titles := {}                    # unit id -> title id (0.31.87; the "pn" message's "tt")
var my_name := ""                          # 0.31.88: your own name and title, from your profile -- your plate shows
var my_title := ""                         # offline and online, whatever the server sends
var player_tags := {}                      # 0.31.134: unit id -> clan tag (the "pn" message's "ct")
var my_tag := ""                           # 0.31.134: your own clan's tag (from the app)
var player_crests := {}                    # 0.31.196: unit id -> clan crest code (the "pn" message's "cc")
var my_crest := ""                         # 0.31.196: your own clan's crest (from the app)
static var _kit_side := 0                  # the side the cached merged castle walls (_kit_merged) were tinted for

func vt(t: int) -> int:
	return t if t < 0 or t > 1 or my_side == 0 else 1 - t
var camera: Camera3D
var actors: Dictionary = {}
var oracle_nodes: Array = []
var gate_nodes: Dictionary = {}
var proj_nodes: Dictionary = {}
var proj_lead := 0.0          # offline: seconds since the last sim tick (projectiles drawn ahead by vel * this)
var _fx: Array = []
var _time := 0.0
var _cam_target := Vector3.ZERO
var low_fx := false
var hq_gfx := true          # High-quality graphics (Round 30): set by SiegeMode from Settings before _ready

static func libraries() -> Dictionary:
	if _libs.is_empty():
		var files := {"g":"General","m":"CombatMelee","r":"CombatRanged","mb":"MovementBasic","ma":"MovementAdvanced"}
		for key in files:
			var packed := Stage.scene("res://assets/kaykit/anim/Rig_Medium_%s.glb" % files[key])
			if packed == null:
				continue
			var holder := packed.instantiate()
			var player: AnimationPlayer = holder.find_child("AnimationPlayer", true, false)
			if player != null:
				var lib: AnimationLibrary = player.get_animation_library("")
				for n in lib.get_animation_list():
					for hint in LOOP_HINTS:
						if n.contains(hint):
							lib.get_animation(n).loop_mode = Animation.LOOP_LINEAR
							break
				_libs[key] = lib
			holder.free()
	return _libs

static var build_times := {}      # last setup's ms per step (siege_diag / tools read it)
const CACHE_RES := "res://assets/terrain/cache.res"
static var _cache_tried := false

static func _load_cache() -> void:
	# The baked start-up cache (0.31.8): terrain and outer meshes, the foliage plan and blood textures, generated once by
	# tools/bake_land.gd. Used only when its key matches the land; otherwise the view generates (slower first start).
	if _cache_tried:
		return
	_cache_tried = true
	if not ResourceLoader.exists(CACHE_RES):
		return
	var c = load(CACHE_RES)
	if c == null or str(c.get("key")) != Land.bake_key():
		push_warning("siege: terrain cache is stale (run tools/bake_land.gd); generating at start instead")
		return
	_terrain_meshes = c.terrain.duplicate()
	_outer_meshes = c.outer.duplicate()
	_foliage = c.foliage.duplicate()
	_outer_trees = c.outer_trees.duplicate()
	_blood_tex = []
	for img in c.blood:
		_blood_tex.append(ImageTexture.create_from_image(img))

func setup(s) -> void:
	# The whole world at once (tools, tests, online: the view is built when the server's welcome arrives).
	for step in setup_steps(s):
		step.call()

func setup_steps(s) -> Array:
	# The build as steps the match runs one per frame behind its loading card (0.31.78: pressing Play used to freeze the
	# menu for the whole build before the card appeared). Each entry builds one part of the world and times itself
	# (build_times); the parts are independent, in this order. The world draws, and its pipelines compile, as it grows.
	sim = s
	build_times = {}
	if fxs == null:
		fxs = SpellFx.new()
		fxs.view = self
		add_child(fxs)
	my_side = int(sim.by_id.get(player_id, {}).get("team", 0))
	if my_side != _kit_side:
		_kit_merged.clear()                 # (their tint was for the other side)
		_kit_side = my_side
	var steps := []
	for pair in [["cache+lighting+ambience", func():
				_load_cache()
				_build_lighting()
				_build_ambience()
				_build_blood()],
			["terrain+water", _build_terrain],
			["outer land", _build_outer_land],
			["foliage", _build_foliage],
			["ridges+fords", func():
				_build_ridges()
				_build_fords()],
			["keep 0", func():
				_build_keep(0)
				_merge_kit(0)],          # per keep, so the one off-screen is culled as a whole
			["keep 1", func():
				_build_keep(1)
				_merge_kit(1)],
			["towers", _build_moba],                # 0.31.155 5V5: the lane towers
			["ground marks", _build_ground_marks],  # 0.31.216: the carved stone on the ground (a step of its own)
			["edge scenery", _build_edge_scenery],
			["oracles+warm", func():
				for tm in 2:
					oracle_nodes.append(_make_oracle(tm))
				_warm_up()]]:
		steps.append(_timed.bind(str(pair[0]), pair[1]))
	return steps

func _timed(label: String, f: Callable) -> void:
	var t := Time.get_ticks_msec()
	f.call()
	build_times[label] = Time.get_ticks_msec() - t

func _warm_up() -> void:
	# Draw one of every effect/projectile type in view during the first frames, so their shader
	# variants compile while the match is loading instead of freezing the first fight.
	var at := Vector3(Sim.spawn(0).x, 0.5, Sim.spawn(0).y)
	ring_at(at, GOLD, 1.0, 0.2)
	spark(at, GOLD)
	number(at, "0", false)
	for kind in (["arrow", "fire", "bolt", "ball", "thorn", "boulder"] if sim.moba != null else ["arrow", "fire"]):
		var n := _make_projectile(kind)
		n.position = at
		get_tree().create_timer(0.3).timeout.connect(n.queue_free)
	if sim.moba != null:
		# 0.31.166: the Grave Wyrm's body and soul-fire (their shaders, before it rises at 3:00)
		var wm := WyrmBody.make(Stage.scene(WyrmBody.MODEL), _cast_static)
		if not wm.is_empty():
			(wm.body as Node3D).position = at + Vector3(0, 0, -3.0)
			add_child(wm.body)
			get_tree().create_timer(0.3).timeout.connect((wm.body as Node3D).queue_free)
		_soul_fire(at, Vector3.UP, 0.3, 0.1)

# ---------- High-quality ambience (Round 32: "add even more effects to make the game look more beautiful") ----------
const CLOUD_STRENGTH := 0.2
static var _cloud_tex: NoiseTexture2D = null
var _motes: GPUParticles3D = null
var _torches: Array = []          # [light, flame, base energy, phase]

static func _clouds() -> NoiseTexture2D:
	if _cloud_tex == null:
		_cloud_tex = NoiseTexture2D.new()
		_cloud_tex.width = 256
		_cloud_tex.height = 256
		_cloud_tex.seamless = true
		var fn := FastNoiseLite.new()
		fn.frequency = 0.02
		fn.fractal_octaves = 4
		_cloud_tex.noise = fn
	return _cloud_tex

static var _cloud_floor_shader: Shader = null

static func _cloud_floor_material(tex: Texture2D, tint_col: Color, uv_scale := 1.0) -> ShaderMaterial:
	# The castle floor with the terrain's drifting cloud shadows, so they don't stop at the castle walls.
	# uv_scale: the castle floors' UVs run one unit per FLOOR_TILE metres; a texture whose tile covers
	# T metres takes FLOOR_TILE / T (0.31.74: each castle area its own floor).
	if _cloud_floor_shader == null:
		_cloud_floor_shader = Shader.new()
		_cloud_floor_shader.code = """
shader_type spatial;
render_mode specular_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 tint_col : source_color;
uniform float cloud_strength = 0.2;
uniform float uv_scale = 1.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float cl = smoothstep(0.46, 0.74, texture(cloud_tex, wpos.xz / 95.0 + vec2(TIME * 0.006, TIME * 0.0035)).r);
	ALBEDO = texture(tex, UV * uv_scale).rgb * tint_col.rgb * (1.0 - cloud_strength * cl);
	ROUGHNESS = 0.95;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _cloud_floor_shader
	m.set_shader_parameter("uv_scale", uv_scale)
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("tint_col", tint_col)
	m.set_shader_parameter("cloud_tex", _clouds())
	m.set_shader_parameter("cloud_strength", CLOUD_STRENGTH)
	return m

static func _bright(c: Color) -> Color:
	# Effects bright enough for the glow to bloom (High-quality graphics); rings and decals don't use this.
	if not _cast_static:
		return c
	return Color(c.r * 1.8, c.g * 1.8, c.b * 1.8, c.a)

static func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t

func _build_ambience() -> void:
	if not _hq():
		return
	# Warm motes of pollen drifting in the sunlight around where the camera looks.
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(20.0, 2.5, 20.0)
	pm.gravity = Vector3(0.0, 0.06, 0.0)
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.25
	pm.direction = Vector3(0.3, 0.4, 0.2)
	pm.spread = 180.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.add_point(0.2, Color(1, 1, 1, 1))
	ramp.add_point(0.8, Color(1, 1, 1, 1))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mm.vertex_color_use_as_albedo = true
	mm.albedo_texture = _soft_dot()
	mm.albedo_color = Color(2.2, 2.0, 1.4, 0.75)
	quad.material = mm
	_motes = GPUParticles3D.new()
	_motes.amount = 90
	_motes.lifetime = 9.0
	_motes.preprocess = 9.0
	_motes.local_coords = false
	_motes.process_material = pm
	_motes.draw_pass_1 = quad
	_motes.visibility_aabb = AABB(Vector3(-24, -4, -24), Vector3(48, 10, 48))
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_motes)
	# Wall torches either side of each keep's middle gate, on the wall's inner face: a warm, flickering light (the KayKit
	# RPG Tools torch). (In each Siege castle's dungeon until 0.31.165.)
	var torch_scene := Stage.scene("res://assets/kaykit/tools/torch.gltf")
	for t in 2:
		var gm: Vector2 = Keep.gate_c(1)
		for spot in [gm + Vector2(-4.3, 1.4), gm + Vector2(4.3, 1.4)]:
			var into0: Vector2 = (Keep.C - spot).normalized()
			var p: Vector2 = Sim._m(t, spot)
			var into: Vector2 = Sim._m(t, spot + into0) - p
			var fy := Sim.height_at(p + into * 0.6) + 1.9
			if torch_scene != null:
				var tm: Node3D = torch_scene.instantiate()
				tm.scale = Vector3.ONE * 2.2
				add_child(tm)
				tm.global_position = Vector3(p.x, fy - 1.3, p.y) + Vector3(into.x, 0.0, into.y) * 0.35
				tm.rotation = Vector3(0.0, Sim.angle_of(into), 0.0)
				tm.rotate_object_local(Vector3.RIGHT, 0.35)
			var light := OmniLight3D.new()
			light.light_color = Color("#ffb05a")
			light.light_energy = 1.6
			light.omni_range = 6.0
			light.omni_attenuation = 1.3
			light.shadow_enabled = false
			add_child(light)
			light.global_position = Vector3(p.x, fy, p.y) + Vector3(into.x, 0.0, into.y) * 0.6
			var flame := MeshInstance3D.new()
			var fq := QuadMesh.new()
			fq.size = Vector2(0.6, 0.9)
			var fmat := StandardMaterial3D.new()
			fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			fmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			fmat.albedo_texture = _soft_dot()
			fmat.albedo_color = Color(2.4, 1.3, 0.45, 0.9)
			fq.material = fmat
			flame.mesh = fq
			flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(flame)
			flame.global_position = light.global_position + Vector3(0.0, -0.15, 0.0)
			_torches.append([light, flame, 1.6, randf() * 10.0])

func _sync_ambience(_dt: float) -> void:
	if _motes != null and is_instance_valid(camera) and camera.is_inside_tree():
		var cp := camera.global_position
		var fwd := -camera.global_transform.basis.z
		if fwd.y < -0.05:
			var hit := cp + fwd * (-cp.y / fwd.y)
			_motes.global_position = hit + Vector3(0.0, 2.2, 0.0)
	for tr in _torches:
		var ph: float = float(tr[3])
		var k := 0.82 + 0.1 * sin(_time * 9.0 + ph) + 0.08 * sin(_time * 23.0 + ph * 1.7)
		(tr[0] as OmniLight3D).light_energy = float(tr[2]) * k
		(tr[1] as Node3D).scale = Vector3.ONE * (0.9 + 0.12 * k)

# ---------- Water you can wade through, with simulated waves (Round 33) ----------
# Kevin: "make the water look much more realistic, like actually simulated water ... realistic physics that create
# wakes". A height field over the river (RIP_W x RIP_H, ~13 cm cells) is stepped every frame on the GPU with the
# wave equation (two SubViewports ping-pong: R = height now, G = height a step ago). Each wading unit pushes on it in
# proportion to its speed, so wakes, rings and bank reflections come out of the physics. The water shader lights the
# resulting slopes (plus flowing detail), reflects the sky at grazing angles, is see-through over the bed, and foams
# on the banks and the wave crests. High-quality graphics only; without it the old water stays.
# 0.30.0: the field is wider and the river opens into a lake round the island, so the simulated patch spans the
# whole field and the lake's full width (still ~13 cm cells). UV.y on the water mesh is this patch's across
# coordinate (centred on the river line); UV2.y runs 0..1 bank to bank for the shallows.
const RIP_W := 680
const WATER_ROWS := 10                      # 0.31.21: vertices across the river, so waves can lift the surface
const RIP_H := 198
const RIP_HALF := Land.HALF_W                  # the simulated stretch: x in [-44, 44]
const RIP_ACROSS := (Land.RIVER_HW + Land.LAKE_EXTRA + 0.35) * 2.0     # the lake at its widest
var _rip_vp: Array = []
var _rip_mat: Array = []
var _rip_i := 0
var _rip_prev: Dictionary = {}                 # unit id -> [last pos, was wet]

func _water_hq_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_opaque;
uniform sampler2D ripples : filter_linear_mipmap, repeat_enable;
uniform sampler2D rip_tex : filter_linear, repeat_disable;
uniform float rip_half = 34.0;
uniform vec2 rip_texel = vec2(0.001953, 0.019231);
uniform float rip_strength = 28.0;
uniform float wake_tint = 4.5;            // crests lighter, troughs darker: how the wakes show without foam
uniform vec3 deep_col : source_color = vec3(0.05, 0.33, 0.40);
uniform vec3 shallow_col : source_color = vec3(0.26, 0.66, 0.62);
uniform vec3 sky_col : source_color = vec3(0.62, 0.80, 0.95);
uniform float glint = 0.0;
uniform float wave_height = 1.5;          // 0.31.21: the surface rises and falls with the simulated waves
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 ruv = vec2((wpos.x + rip_half) / (2.0 * rip_half), UV.y);
	float inside = step(0.0, ruv.x) * step(ruv.x, 1.0);
	float h = textureLod(rip_tex, ruv, 0.0).r * inside;
	h = (isnan(h) || isinf(h)) ? 0.0 : h;
	float edge = smoothstep(0.0, 0.1, UV2.y) * smoothstep(1.0, 0.9, UV2.y);     // held at the banks
	VERTEX.y += h * wave_height * edge;
	wpos.y += h * wave_height * edge;
}
float detail(vec2 p) {
	return texture(ripples, p * 0.11 + vec2(-TIME * 0.035, 0.0)).r * 0.6
		+ texture(ripples, p * 0.23 + vec2(-TIME * 0.05, TIME * 0.02)).r * 0.4;
}
void fragment() {
	// Flowing detail (the river runs toward -x) from finite differences of two scrolling layers.
	float e = 0.2;
	float d0 = detail(wpos.xz);
	vec2 slope = vec2(detail(wpos.xz + vec2(e, 0.0)) - d0, detail(wpos.xz + vec2(0.0, e)) - d0) / e * 0.22;
	// The simulated waves.
	vec2 ruv = vec2((wpos.x + rip_half) / (2.0 * rip_half), UV.y);
	float inside = step(0.0, ruv.x) * step(ruv.x, 1.0);
	float h = texture(rip_tex, ruv).r * inside;
	float hx = (texture(rip_tex, ruv + vec2(rip_texel.x, 0.0)).r - texture(rip_tex, ruv - vec2(rip_texel.x, 0.0)).r) * inside;
	float hz = (texture(rip_tex, ruv + vec2(0.0, rip_texel.y)).r - texture(rip_tex, ruv - vec2(0.0, rip_texel.y)).r) * inside;
	if (isnan(h + hx + hz) || isinf(h + hx + hz)) { h = 0.0; hx = 0.0; hz = 0.0; }
	slope += clamp(vec2(hx, hz) * rip_strength, vec2(-1.5), vec2(1.5));
	vec3 wn = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	float edge = min(UV2.y, 1.0 - UV2.y);
	float depth = smoothstep(0.02, 0.4, edge);
	vec3 col = mix(shallow_col, deep_col, depth);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	col = mix(col, sky_col, clamp(fres * 0.3, 0.0, 0.25));     // (0.31.216: 0.5 -- the river bed shows through now)
	// No foam (Round 34, Kevin). The wakes read as light crests and dark troughs instead.
	col *= 1.0 + clamp(h, -0.12, 0.12) * wake_tint;
	ALBEDO = col;
	ALPHA = mix(0.38, 0.66, depth);              // (0.31.216: 0.58 .. 0.86: the painted river bed shows through)
	ROUGHNESS = 0.16;                 // 0.30.11: was 0.05 / 0.75 -- the sun's glare spread white over the wide lake
	SPECULAR = 0.35;
	float sg = texture(ripples, wpos.xz * 0.19 + vec2(-TIME * 0.09, TIME * 0.05)).r * texture(ripples, wpos.xz * 0.13 + vec2(TIME * 0.07, -TIME * 0.04)).r;
	EMISSION = vec3(1.0, 0.97, 0.88) * smoothstep(0.58, 0.64, sg) * glint;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.04
	nt.noise = fn
	m.set_shader_parameter("ripples", nt)
	m.set_shader_parameter("glint", 1.3)
	m.set_shader_parameter("rip_half", RIP_HALF)
	m.set_shader_parameter("rip_texel", Vector2(1.0 / RIP_W, 1.0 / RIP_H))
	return m

var _rip_kicks: Array = []

func water_blast(at: Vector2, power: float) -> void:
	# 0.31.21 (Kevin: "the water to react to the bomb explosion and make huge waves"): a blast in or beside the river
	# pushes the water down hard where it hits for a few frames; the wave equation throws the rings out across it.
	# Also a column of spray.
	var c := Land.river_c(at.x)
	var hw := Land.river_hw(at.x)
	var off := at.y - c
	var reach := absf(off) - hw                   # how far from the water's edge (negative: in the water)
	if reach > 5.0 or absf(at.x) > RIP_HALF - 1.0:
		return
	var p := Vector2(at.x, c + clampf(off, -hw + 0.6, hw - 0.6))
	var k := power * clampf(1.0 - maxf(reach, 0.0) / 5.0, 0.25, 1.0)
	_rip_kicks.append({"p":p, "frames":4, "r":2.4 * sqrt(power), "s":-0.5 * k})
	var sp := Vector3(p.x, Land.WATER_Y + 0.1, p.y)
	for i in int(30 * k):
		spark(sp + Vector3(randf_range(-1.2, 1.2), randf_range(0.0, 3.5 * k), randf_range(-1.2, 1.2)), Color(0.88, 0.95, 1.0))
	ring_at(sp, Color(0.85, 0.95, 1.0), 4.0 * k + 1.0, 0.9)

func _build_ripples() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
render_mode blend_disabled;
uniform sampler2D prev : filter_nearest, repeat_disable;
uniform vec2 texel;
uniform vec2 cell_m;
uniform vec4 drops[16];
uniform int drop_count = 0;
uniform float damping = 0.989;            // wakes trail longer (Round 34)
void fragment() {
	vec4 p = texture(prev, UV);
	float n = texture(prev, UV + vec2(texel.x, 0.0)).r + texture(prev, UV - vec2(texel.x, 0.0)).r
		+ texture(prev, UV + vec2(0.0, texel.y)).r + texture(prev, UV - vec2(0.0, texel.y)).r;
	float h = (n * 0.5 - p.g) * damping;
	for (int i = 0; i < 16; i++) {
		if (i >= drop_count) { break; }
		vec2 d = (UV - drops[i].xy) / texel * cell_m;
		float r = drops[i].z;
		h += drops[i].w * exp(-dot(d, d) / (r * r));
	}
	h *= smoothstep(0.0, 0.03, UV.y) * smoothstep(1.0, 0.97, UV.y);
	// 0.30.11: the lake made the simulated patch 5x bigger. A bad cell (NaN/inf) would spread and the water would
	// render white (Kevin's screenshot): clamp and scrub every step.
	h = (isnan(h) || isinf(h)) ? 0.0 : clamp(h, -0.6, 0.6);
	float pr = (isnan(p.r) || isinf(p.r)) ? 0.0 : clamp(p.r, -0.6, 0.6);
	COLOR = vec4(h, pr, 0.0, 1.0);
}
"""
	for k in 2:
		var vp := SubViewport.new()
		vp.size = Vector2i(RIP_W, RIP_H)
		vp.use_hdr_2d = true
		vp.disable_3d = true
		vp.transparent_bg = false
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var cr := ColorRect.new()
		cr.size = Vector2(RIP_W, RIP_H)
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("texel", Vector2(1.0 / RIP_W, 1.0 / RIP_H))
		m.set_shader_parameter("cell_m", Vector2(2.0 * RIP_HALF / RIP_W, RIP_ACROSS / RIP_H))
		cr.material = m
		vp.add_child(cr)
		add_child(vp)
		_rip_vp.append(vp)
		_rip_mat.append(m)

func _sync_ripples(dt: float) -> void:
	if _rip_vp.is_empty() or _water_mat == null:
		return
	var drops := []
	for u in sim.units:
		if not sim.alive(u) or _fogged(u):
			_rip_prev.erase(u.id)
			continue
		var p: Vector2 = u.pos
		var wet := Sim.water_depth(p) > 0.05 and absf(p.x) < RIP_HALF - 0.5     # (0.31.165: the Rift's shallow river)
		var last: Array = _rip_prev.get(u.id, [p, false])
		var spd: float = (p - (last[0] as Vector2)).length() / maxf(dt, 0.001)
		if wet and drops.size() < 16:
			var v := (p.y - (Land.river_c(p.x) - RIP_ACROSS * 0.5)) / RIP_ACROSS
			var strength := 0.005 + minf(spd, 6.0) * 0.0085          # (Round 34: twice as strong, no foam to hide it)
			var radius := 0.42
			if not bool(last[1]):
				strength = 0.06                              # stepping in: a splash
				radius = 0.7
				var sp := Vector3(p.x, Land.WATER_Y + 0.05, p.y)
				for k in 8:
					spark(sp + Vector3(randf_range(-0.4, 0.4), randf_range(0.0, 0.6), randf_range(-0.4, 0.4)), Color(0.9, 0.96, 1.0))
			drops.append(Vector4((p.x + RIP_HALF) / (2.0 * RIP_HALF), v, radius, strength))
		_rip_prev[u.id] = [p, wet]
	for i in range(_rip_kicks.size() - 1, -1, -1):
		var kk: Dictionary = _rip_kicks[i]
		var kp: Vector2 = kk.p
		var kv := (kp.y - (Land.river_c(kp.x) - RIP_ACROSS * 0.5)) / RIP_ACROSS
		drops.push_front(Vector4((kp.x + RIP_HALF) / (2.0 * RIP_HALF), kv, float(kk.r), float(kk.s)))
		kk.frames = int(kk.frames) - 1
		if int(kk.frames) <= 0:
			_rip_kicks.remove_at(i)
	if drops.size() > 16:
		drops.resize(16)
	var cur := _rip_i % 2
	var other := 1 - cur
	var m: ShaderMaterial = _rip_mat[cur]
	m.set_shader_parameter("prev", (_rip_vp[other] as SubViewport).get_texture())
	var arr := PackedVector4Array()
	arr.resize(16)
	for i in drops.size():
		arr[i] = drops[i]
	m.set_shader_parameter("drops", arr)
	m.set_shader_parameter("drop_count", drops.size())
	(_rip_vp[cur] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
	_water_mat.set_shader_parameter("rip_tex", (_rip_vp[other] as SubViewport).get_texture())
	_rip_i += 1

# ---------- Blood (Round 37, Kevin: "blood will splatter on the ground when hit, and when a player dies there will be
# a pool of blood") ----------
# Flat, lit, glossy marks on the ground (procedural splatter textures), droplets flung away from the attacker that
# land as small spots, and a pool that spreads under a body. Recycled pools of nodes with hard caps; each mark fades
# after a while. Not on the river.
const BLOOD_COL := Color(0.56, 0.03, 0.04)      # a red that reads as blood from the game camera (darker went black)
const SPLAT_MAX := 90
const POOL_MAX := 24
const DROP_MAX := 60
const SPLAT_LIFE := 18.0
const POOL_LIFE := 25.0
const BLOOD_FADE := 3.0
static var _blood_tex: Array = []          # [splat variants..., pool]
var _splats: Array = []                    # {mi, born, life, r0, r1, grow}
var _splat_i := 0
var _pools: Array = []
var _pool_i := 0
var _drops: Array = []                     # {mi, p: Vector3, v: Vector3, size}
var _drop_i := 0
var _blood_layer := 0

static func _blood_texture(seed_v: int, pool: bool) -> ImageTexture:
	return ImageTexture.create_from_image(_blood_image(seed_v, pool))

static func _blood_image(seed_v: int, pool: bool) -> Image:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var c := Vector2(n, n) * 0.5
	var phases := []
	for k in 6:
		phases.append([rng.randf() * TAU, rng.randf_range(0.04, 0.12) * (0.4 if pool else 1.0), 2 + k * (1 if pool else 2)])
	var base_r := n * (0.36 if pool else 0.26)
	var drops := []
	if not pool:
		for k in rng.randi_range(5, 9):
			var ang := rng.randf() * TAU
			var dist := base_r * rng.randf_range(1.15, 1.7)
			drops.append([c + Vector2(cos(ang), sin(ang)) * dist, rng.randf_range(1.6, 4.5)])
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := p - c
			var ang := atan2(d.y, d.x)
			var r := base_r
			for ph in phases:
				r *= 1.0 + float(ph[1]) * sin(ang * float(ph[2]) + float(ph[0]))
			var a := clampf((r - d.length()) / 1.6, 0.0, 1.0)
			for dr in drops:
				a = maxf(a, clampf((float(dr[1]) - p.distance_to(dr[0])) / 1.2, 0.0, 1.0))
			# a little darker toward the middle, where it's thicker
			var shade := 1.0 - 0.25 * clampf(1.0 - d.length() / maxf(r, 1.0), 0.0, 1.0)
			img.set_pixel(x, y, Color(shade, shade, shade, a))
	return img

func _blood_mat(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = BLOOD_COL
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.22                     # wet
	m.metallic_specular = 0.6
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m

func _build_blood() -> void:
	if _blood_tex.is_empty():
		for k in 4:
			_blood_tex.append(_blood_texture(71 + k * 13, false))
		_blood_tex.append(_blood_texture(503, true))
	var quad := PlaneMesh.new()
	quad.size = Vector2(1.0, 1.0)
	for k in SPLAT_MAX:
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = _blood_mat(_blood_tex[k % 4])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_splats.append({"mi": mi, "born": -999.0, "life": SPLAT_LIFE, "r0": 1.0, "r1": 1.0, "grow": 0.0})
	for k in POOL_MAX:
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = _blood_mat(_blood_tex[4])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_pools.append({"mi": mi, "born": -999.0, "life": POOL_LIFE, "r0": 0.2, "r1": 1.0, "grow": 3.0})
	var dm := SphereMesh.new()
	dm.radius = 0.045
	dm.height = 0.09
	dm.radial_segments = 6
	dm.rings = 3
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = BLOOD_COL
	dmat.roughness = 0.25
	dm.material = dmat
	for k in DROP_MAX:
		var mi := MeshInstance3D.new()
		mi.mesh = dm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_drops.append({"mi": mi, "p": Vector3.ZERO, "v": Vector3.ZERO, "size": 0.2, "on": false})

func _blood_mark(list: Array, idx: int, p: Vector2, radius: float, grow: float, life: float) -> void:
	# Lay one mark flat on the ground at p (not on the river).
	if Sim.water_depth(p) > 0.05:
		return
	var m: Dictionary = list[idx]
	var mi: MeshInstance3D = m.mi
	_blood_layer = (_blood_layer + 1) % 40
	mi.position = Vector3(p.x, Sim.height_at(p) + 0.02 + _blood_layer * 0.0006, p.y)
	mi.rotation = Vector3(0.0, randf() * TAU, 0.0)
	m.born = _time
	m.life = life
	m.r1 = radius
	m.r0 = radius * (0.2 if grow > 0.0 else 1.0)
	m.grow = grow
	mi.scale = Vector3.ONE * (m.r0 * 2.0)
	(mi.material_override as StandardMaterial3D).albedo_color = BLOOD_COL
	mi.visible = true

func blood_hit(target: Vector2, from: Vector2, dmg: float) -> void:
	if _splats.is_empty():
		return
	var away := (target - from).normalized() if target.distance_to(from) > 0.05 else Vector2.from_angle(randf() * TAU)
	var amt := clampf(dmg / 40.0, 0.35, 1.6)
	var sp := target + away * randf_range(0.35, 0.8) + Vector2(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2))
	_blood_mark(_splats, _splat_i, sp, randf_range(0.45, 0.68) * (0.7 + amt * 0.5), 0.0, SPLAT_LIFE)
	_splat_i = (_splat_i + 1) % SPLAT_MAX
	var y0 := Sim.height_at(target) + 1.0
	for k in int(3 + amt * 3):
		var d: Dictionary = _drops[_drop_i]
		_drop_i = (_drop_i + 1) % DROP_MAX
		var dir2 := away.rotated(randf_range(-0.7, 0.7))
		d.p = Vector3(target.x, y0 + randf_range(-0.2, 0.3), target.y)
		d.v = Vector3(dir2.x, 0.0, dir2.y) * randf_range(1.5, 3.8) + Vector3(0.0, randf_range(1.0, 2.8), 0.0)
		d.size = randf_range(0.13, 0.24)
		d["g"] = y0 - 1.0                           # 0.31.160: the ground under the hit, looked up once (they land within ~2 m)
		d.on = true
		(d.mi as MeshInstance3D).position = d.p
		(d.mi as MeshInstance3D).visible = true

func blood_pool(p: Vector2) -> void:
	if _pools.is_empty():
		return
	_blood_mark(_pools, _pool_i, p, randf_range(1.45, 1.8), 3.0, POOL_LIFE)
	_pool_i = (_pool_i + 1) % POOL_MAX

func _sync_blood(dt: float) -> void:
	for d in _drops:
		if not bool(d.on):
			continue
		d.v += Vector3(0.0, -9.8, 0.0) * dt
		d.p += d.v * dt
		if d.p.y <= float(d.get("g", 0.0)) + 0.03:
			d.on = false
			(d.mi as MeshInstance3D).visible = false
			_blood_mark(_splats, _splat_i, Vector2(d.p.x, d.p.z), float(d.size), 0.0, SPLAT_LIFE * 0.8)
			_splat_i = (_splat_i + 1) % SPLAT_MAX
		else:
			(d.mi as MeshInstance3D).position = d.p
	for list in [_splats, _pools]:
		for m in list:
			var mi: MeshInstance3D = m.mi
			if not mi.visible:
				continue
			var age: float = _time - float(m.born)
			if age > float(m.life) + BLOOD_FADE:
				mi.visible = false
				continue
			if float(m.grow) > 0.0 and age < float(m.grow):
				var k := 1.0 - pow(1.0 - age / float(m.grow), 3.0)          # spreads fast, then slows
				mi.scale = Vector3.ONE * lerpf(float(m.r0), float(m.r1), k) * 2.0
			if age > float(m.life):
				var c := BLOOD_COL
				c.a = 1.0 - (age - float(m.life)) / BLOOD_FADE
				(mi.material_override as StandardMaterial3D).albedo_color = c

# ---------- world ----------
var _hq_cached := -1
static var _cast_static := false     # for the static make_body: set from _hq() before any unit is built

func _hq() -> bool:
	# High-quality graphics, except under the software renderer this project is built and tested with (it hung
	# on shadow-casting Kings in the full scene): there only when FB_FORCE_HQ is set, to check the look. Cached.
	if _hq_cached < 0:
		var soft := RenderingServer.get_video_adapter_name().to_lower().contains("llvmpipe")
		_hq_cached = 1 if hq_gfx and (not soft or OS.has_environment("FB_FORCE_HQ")) else 0
	return _hq_cached == 1

func _cast() -> GeometryInstance3D.ShadowCastingSetting:
	# Solid things (castles, buildings, blocks, iron bars, units) cast shadows in high quality; ground, water,
	# grass, decals and effects never do (they only receive).
	return GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _hq() else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _apply_hq(env: Environment, sun: DirectionalLight3D) -> void:
	# Round 30 (Kevin: "increase the graphical fidelity -- lighting, shadows"). The Mobile renderer has no SSAO,
	# SSR or GI, so: real sun shadows (castles, buildings, trees, units, Kings; grass and flowers stay out),
	# a warm sun against cool sky-blue shade instead of flat grey, a subtle glow on the brightest highlights
	# (low glow levels only: the cheap passes), and 2x MSAA (cheap on tile-based phone GPUs).
	sun.shadow_enabled = true
	# One shadow pass reaching the top of the screen (Round 36, Kevin: "I don't see shadows from trees"). The camera
	# is 38 m up: the visible ground is 28 m deep at the bottom of the screen and ~70 m at the top, so 0.27.2's 45 m
	# left the upper half (field, trees, rocks, bridges) unshadowed. tests/battle_bench.gd with MSAA 2x: one pass to
	# 75 m costs +4 % over 45 m (two splits to 80 m +7 %) -- the 21 fps was MSAA 4x, not shadow reach.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 75.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.1
	sun.shadow_blur = 1.3
	sun.shadow_opacity = 1.0
	# Rebalanced so shadows read: the ambient fill was tuned for a shadowless world (about as strong as the sun,
	# so a shadow only removed half the light and the tonemap flattened it). Less fill, more sun: sunlit ground
	# about as bright as before, shade ~40 % of it, tinted cool blue.
	sun.light_energy = 1.45
	RenderingServer.directional_shadow_atlas_set_size(2048, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	env.ambient_light_color = Color("#a9bcd8")
	env.ambient_light_energy *= 0.75
	env.glow_enabled = true
	for i in 7:
		env.set_glow_level(i, i == 1 or i == 2)
	env.glow_intensity = 0.6
	env.glow_strength = 0.95
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_saturation = 1.12 * VULKAN_SATURATION
	env.adjustment_contrast = 1.08 * VULKAN_CONTRAST
	env.tonemap_exposure *= 1.05                # the shade costs ~6 % mean brightness: give it back

func _build_lighting() -> void:
	_cast_static = _hq()
	var env := Environment.new()
	# A real sky (0.19.4, Kevin: "there needs to be a sky, mainly for the trailer"). Background only:
	# ambient stays a flat colour and reflections are off, so lighting on the field is unchanged and
	# no radiance map is computed.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#3a79c8")
	sky_mat.sky_horizon_color = Color("#bcd8ea")
	sky_mat.sky_curve = 0.12
	# Below the horizon = the fog colour: wherever no land is drawn it reads as distant haze, never
	# as a grey patch.
	sky_mat.ground_horizon_color = Color("#b3cfe1")
	sky_mat.ground_bottom_color = Color("#b3cfe1")
	sky_mat.sun_angle_max = 24.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#c3c9c4")
	env.ambient_light_energy = 0.5 * VULKAN_AMBIENT
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Vulkan/Mobile lights in linear space and read darker than the old OpenGL render with the same settings; the
	# multipliers keep the look Kevin picked (0.31.71).
	env.tonemap_exposure = 0.84 * VULKAN_EXPOSURE
	env.tonemap_white = 3.0
	# More colourful, like the Fat Princess references (Kevin, Round 7b).
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08 * VULKAN_SATURATION
	env.adjustment_contrast = 1.04 * VULKAN_CONTRAST
	env.fog_enabled = true
	env.fog_light_color = Color("#b3cfe1")      # the sky's horizon: distant hills fade into it
	env.fog_mode = Environment.FOG_MODE_DEPTH
	# 0.31.14 atmosphere (Kevin: "more atmosphere ... better lighting"): the haze starts nearer (aerial depth over the far
	# side of the field), scatters warm towards the sun, and settles a little in the low ground (river, gorges).
	env.fog_depth_begin = 48.0
	env.fog_depth_end = 270.0                  # the land ends at ~300 m: fully fogged there, so no rim shows
	env.fog_density = 0.9
	env.fog_sun_scatter = 0.22
	env.fog_height = -0.2
	env.fog_height_density = 0.05
	env.fog_sky_affect = 0.0                   # the sky itself stays clear
	# No glow in battle (0.14.3): it is full-screen blur passes at native resolution (~7 % of the
	# frame in tests/perf_bench.gd, and bandwidth-heavy on phones) for a bloom too faint to see.
	env.glow_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#ffdfb4")         # warmer (0.31.14), against the cool sky ambient
	sun.light_energy = 1.08
	sun.rotation_degrees = Vector3(-47, -33, 0)  # a little lower: longer, softer shadows give the ground depth
	# No real-time shadows: at this zoom they doubled every triangle for little visual gain.
	# Units are marked by team rings; HP bars are drawn on the 2D HUD.
	sun.shadow_enabled = false
	if _hq():
		_apply_hq(env, sun)
	add_child(sun)
	# Single directional light: the Compatibility renderer can add a per-object pass for each extra
	# directional light, so the old cool fill light is folded into ambient instead.
	camera = Camera3D.new()
	camera.fov = CAM_FOV
	camera.near = 0.3
	camera.far = 190.0
	add_child(camera)

func _mesh_of(path: String) -> Dictionary:
	var packed := Stage.scene(path)
	if packed == null:
		return {}
	var holder := packed.instantiate()
	var found := holder.find_children("*", "MeshInstance3D", true, false)
	var out := {}
	if not found.is_empty():
		var mi: MeshInstance3D = found[0]
		out = {"mesh":mi.mesh, "material":mi.get_active_material(0)}
	holder.free()
	return out

static var _terrain_meshes: Array = []
static var _terrain_mat: ShaderMaterial = null
const PAINT := "res://assets/terrain/paint/"            # 0.31.216: the painted ground, plants and decals (tools/ground_paint.py)
const PAINT_TINT := Vector3(0.66, 0.68, 0.70)
static var _water_mat: ShaderMaterial = null

static func _terrain_material() -> ShaderMaterial:
	if _terrain_mat == null:
		var m := ShaderMaterial.new()
		m.shader = load("res://scripts/siege/terrain.gdshader")
		# 0.31.216 (Kevin: "use eleven to draw detailed paint on ground"): the ground ElevenLabs painted
		# (tools/ground_paint.py) -- two lawns, the lanes' flagstones, the jungle's earth, the cliff rock, the river bed
		m.set_shader_parameter("grass_tex", Stage.texture(PAINT + "grass.webp"))
		m.set_shader_parameter("grass2_tex", Stage.texture(PAINT + "grass2.webp"))
		m.set_shader_parameter("lane_tex", Stage.texture(PAINT + "lane.webp"))
		m.set_shader_parameter("path_tex", Stage.texture(PAINT + "dirt.webp"))
		m.set_shader_parameter("rock_tex", Stage.texture(PAINT + "rock.webp"))
		m.set_shader_parameter("bed_tex", Stage.texture(PAINT + "riverbed.webp"))
		m.set_shader_parameter("path_mask", ImageTexture.create_from_image(load(Land.MASK_RES)))
		var r := Land.bake_rect()
		m.set_shader_parameter("mask_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
		# The battle view's Vulkan compensation (exposure x1.55) brightens everything; a neutral darkening keeps the
		# painting's own colours (0.31.216: re-set for the painted ground; the Fat Princess grass took 0.64/0.73/0.80).
		m.set_shader_parameter("tint", PAINT_TINT)
		m.set_shader_parameter("grass_sat", 1.0)
		var mt := NoiseTexture2D.new()
		mt.width = 256
		mt.height = 256
		mt.seamless = true
		var fn := FastNoiseLite.new()
		fn.frequency = 0.012
		fn.fractal_octaves = 3
		mt.noise = fn
		m.set_shader_parameter("macro_tex", mt)
		m.set_shader_parameter("cloud_tex", _clouds())
		m.set_shader_parameter("cloud_strength", CLOUD_STRENGTH if _cast_static else 0.0)
		_terrain_mat = m
	return _terrain_mat

# ---------- the land beyond the playfield (0.19.4) ----------
static var _outer_meshes: Array = []
static var _outer_mat: ShaderMaterial = null
const OUTER_RINGS := [-1.0, 0.0, 2.0, 5.0, 9.0, 14.0, 21.0, 30.0, 42.0, 58.0, 80.0, 110.0, 150.0, 200.0, 260.0]
# (0.31.173: the outer woods are Foliage.OUTER_TREES -- the light *_far copies of the Meshy trees; were KayKit's
# Tree_1_A / 2_A / 4_A)

static func _outer_side_points(side: int) -> Array:
	# Points along one side of the baked rect, with their outward directions; each side also owns
	# the fan of directions around its first corner, so the four sides tile the ring.
	var r := Land.bake_rect()
	var c := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var nrm := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
	var a: Vector2 = c[side]
	var b: Vector2 = c[(side + 1) % 4]
	var n: Vector2 = nrm[side]
	var prev: Vector2 = nrm[(side + 3) % 4]
	var pts := []
	for k in 6:                                   # corner fan from the previous side's normal to ours
		pts.append([a, prev.slerp(n, k / 6.0).normalized()])
	var len := a.distance_to(b)
	var steps := int(ceil(len / 2.0))
	for k in steps + 1:
		pts.append([a.lerp(b, float(k) / steps), n])
	return pts

static func _make_outer_meshes() -> Array:
	var out := []
	for side in 4:
		var pts := _outer_side_points(side)
		var np := pts.size()
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var idx := PackedInt32Array()
		for ring in OUTER_RINGS.size():
			var d: float = OUTER_RINGS[ring]
			for pt in pts:
				var p: Vector2 = (pt[0] as Vector2) + (pt[1] as Vector2) * d
				# The first ring tucks 1 m under the terrain's edge so no crack can show.
				var y: float = Land.terrain_height(pt[0]) - 0.06 if d <= 0.0 else Land.outer_height(p)
				verts.append(Vector3(p.x, y, p.y))
				var e := 1.0
				var hx := Land.outer_height(p + Vector2(e, 0)) - Land.outer_height(p - Vector2(e, 0))
				var hz := Land.outer_height(p + Vector2(0, e)) - Land.outer_height(p - Vector2(0, e))
				norms.append(Vector3(-hx, 2.0 * e, -hz).normalized())
		for ring in OUTER_RINGS.size() - 1:
			for k in np - 1:
				var a := ring * np + k
				var b := a + np
				# Every side runs the same way round the map with rings going outward, so one winding
				# faces up on all four. (0.19.4 special-cased sides 1 and 2 the wrong way round: they
				# were culled and the sky's grey underside showed through -- Kevin's screenshots.)
				idx.append_array([a, b, a + 1, a + 1, b, b + 1])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_INDEX] = idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.append(am)
	return out

func _build_outer_land() -> void:
	if _outer_meshes.is_empty():
		_outer_meshes = _make_outer_meshes()
	if _outer_mat == null:
		var tm: ShaderMaterial = _terrain_material()
		_outer_mat = ShaderMaterial.new()
		_outer_mat.shader = load("res://scripts/siege/outer_land.gdshader")
		for k in ["grass_tex", "rock_tex", "path_mask", "mask_rect", "grass_scale", "rock_scale", "tint", "grass_sat",
				"cloud_tex", "cloud_strength", "macro_tex", "rock_col"]:
			_outer_mat.set_shader_parameter(k, tm.get_shader_parameter(k))
	for m in _outer_meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = _outer_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta("perf", "outer_land")
		add_child(mi)
	_build_outer_trees()

static var _outer_trees: Dictionary = {}      # "side:type" -> Array[Transform3D]: planned once (or from the baked cache)

static func _plan_outer_trees() -> Dictionary:
	# Groves in the meadows and on the lower hills, batched per side and tree type. Not in the river, not on steep or
	# high ground. Deterministic (seed 911), so tools/bake_land.gd bakes the plan into the start-up cache (0.31.78: the
	# 9,000 tries cost ~90 ms of every match start).
	var r := Land.bake_rect()
	var rng := RandomNumberGenerator.new()
	rng.seed = 911
	var per := {}
	var placed := 0
	var tries := 0
	while placed < 420 and tries < 9000:             # 260 until 0.31.12: the valley's hills get their woods too
		tries += 1
		var d := 2.0 + pow(rng.randf(), 1.7) * 150.0           # denser near the playfield
		var side := rng.randi() % 4
		if side == 1 and rng.randf() < 0.5:
			d = 30.0 + rng.randf() * 190.0                      # the valley beyond the cliff side: woods all the way up
		var along := rng.randf()
		var q: Vector2
		var n: Vector2
		match side:
			0: q = Vector2(lerpf(r.position.x, r.end.x, along), r.position.y); n = Vector2(0, -1)
			1: q = Vector2(r.end.x, lerpf(r.position.y, r.end.y, along)); n = Vector2(1, 0)
			2: q = Vector2(lerpf(r.end.x, r.position.x, along), r.end.y); n = Vector2(0, 1)
			_: q = Vector2(r.position.x, lerpf(r.end.y, r.position.y, along)); n = Vector2(-1, 0)
		var p := q + n * d + Vector2(n.y, -n.x) * rng.randf_range(-6.0, 6.0)
		# Groves, not an even carpet.
		if sin(p.x * 0.09 + 1.1) * sin(p.y * 0.08 + 0.3) + rng.randf() * 0.6 < 0.25:
			continue
		if absf(p.y - Land.river_c(p.x)) < Land.RIVER_HW + 4.0:
			continue
		var h := Land.outer_height(p)
		var slope := absf(Land.outer_height(p + Vector2(1, 0)) - Land.outer_height(p - Vector2(1, 0))) \
			+ absf(Land.outer_height(p + Vector2(0, 1)) - Land.outer_height(p - Vector2(0, 1)))
		if h > 22.0 or slope > 1.4 or p.distance_to(q) < 1.5:
			continue
		var kind := Foliage.pick(rng, Foliage.OUTER_TREES) + "_far"          # (0.31.173: was one of three KayKit trees)
		var sc := rng.randf_range(0.6, 1.0)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(p.x, h - 0.1, p.y))
		var key := "%d:%s" % [side, kind]
		if not per.has(key):
			per[key] = []
		(per[key] as Array).append(xf)
		placed += 1
	return per

func _build_outer_trees() -> void:
	# The woods beyond the field: the light *_far trees, one MultiMesh per kind and 24 m square (0.31.173: was one per
	# side and kind -- a whole side drawn when any of it was on screen).
	if _outer_trees.is_empty():
		_outer_trees = _plan_outer_trees()
	var per := {}
	for key in _outer_trees:
		var kind := str(key).split(":")[1]
		if not per.has(kind):
			per[kind] = []
		(per[kind] as Array).append_array(_outer_trees[key])
	for kind in per:
		_plant_batch(kind, per[kind], GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "outer_trees", 24.0)

static func _make_terrain_meshes() -> Array:
	# One mesh per 32 m square (tight AABBs -> off-screen squares are culled; 0.31.216: squares, the yawed landscape
	# camera sees a diagonal of the map -- 32 m bands across its whole width until then), vertices every BAKE_STEP
	# metres straight from the baked height map, normals by central differences.
	var img: Image = load(Land.HEIGHT_RES)
	var nx := img.get_width()
	var nz := img.get_height()
	var h := img.get_data().to_float32_array()
	var r := Land.bake_rect()
	var st := Land.BAKE_STEP
	var out := []
	var band := int(32.0 / st)
	var j0 := 0
	while j0 < nz - 1:
		var j1 := mini(nz - 1, j0 + band)
		var i0 := 0
		while i0 < nx - 1:
			var i1 := mini(nx - 1, i0 + band)
			var cols := i1 - i0 + 1
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			var idx := PackedInt32Array()
			for j in range(j0, j1 + 1):
				for i in range(i0, i1 + 1):
					var y := h[j * nx + i]
					verts.append(Vector3(r.position.x + i * st, y, r.position.y + j * st))
					var hl := h[j * nx + maxi(i - 1, 0)]
					var hr := h[j * nx + mini(i + 1, nx - 1)]
					var hd := h[maxi(j - 1, 0) * nx + i]
					var hu := h[mini(j + 1, nz - 1) * nx + i]
					norms.append(Vector3(hl - hr, 2.0 * st, hd - hu).normalized())
			for jj in j1 - j0:
				for ii in cols - 1:
					var a := jj * cols + ii
					idx.append_array([a, a + 1, a + cols, a + 1, a + cols + 1, a + cols])
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = verts
			arr[Mesh.ARRAY_NORMAL] = norms
			arr[Mesh.ARRAY_INDEX] = idx
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			out.append(am)
			i0 = i1
		j0 = j1
	return out

func _build_terrain() -> void:
	# Round 7: a single height-mapped ground (grass, herringbone paths, rock ledges) built from the
	# baked landscape; cached for the session so rematches don't rebuild it.
	if _terrain_meshes.is_empty():
		_terrain_meshes = _make_terrain_meshes()
	for m in _terrain_meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = _terrain_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta("perf", "terrain")
		add_child(mi)
	_build_water()

func _build_water() -> void:
	_water_mat = null                 # rebuilt per match: the High-quality setting may have changed
	if _hq():
		_water_mat = _water_hq_material()
		_build_ripples()
	if _water_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_opaque;
uniform sampler2D ripples : filter_linear_mipmap, repeat_enable;
uniform float glint = 0.0;
void fragment() {
	vec2 w = UV * vec2(18.0, 1.0);
	float a = texture(ripples, w * 0.35 + vec2(TIME * 0.05, TIME * 0.02)).r;
	float b = texture(ripples, w * 0.21 - vec2(TIME * 0.03, 0.0)).r;
	float n = a * 0.6 + b * 0.4;
	float shore = 1.0 - smoothstep(0.0, 0.16, min(UV2.y, 1.0 - UV2.y));
	vec3 deep = vec3(0.06, 0.36, 0.44);            // (0.31.216: teal over the painted bed; was a solid blue)
	vec3 shallow = vec3(0.24, 0.64, 0.62);
	vec3 col = mix(deep, shallow, smoothstep(0.35, 0.75, n));
	col *= 1.0 - shore * 0.18;                     // no foam (Round 34): the banks just shade a little
	ALBEDO = col;
	ALPHA = mix(0.5, 0.72, smoothstep(0.0, 0.4, min(UV2.y, 1.0 - UV2.y)));
	ROUGHNESS = 0.18;
	SPECULAR = 0.35;                  // 0.30.11: was 0.6 (see the high-quality water)
	// Sun glints (High-quality graphics): sparse sparkles where two scrolling layers line up; bright enough to glow.
	float sg = texture(ripples, w * 1.3 + vec2(-TIME * 0.09, TIME * 0.05)).r * texture(ripples, w * 0.9 + vec2(TIME * 0.07, -TIME * 0.04)).r;
	EMISSION = vec3(1.0, 0.97, 0.88) * smoothstep(0.58, 0.64, sg) * glint;      // sparse: only the brightest crossings
}
"""
		var m := ShaderMaterial.new()
		m.shader = sh
		var nt := NoiseTexture2D.new()
		nt.width = 256
		nt.height = 256
		nt.seamless = true
		var fn := FastNoiseLite.new()
		fn.frequency = 0.04
		nt.noise = fn
		m.set_shader_parameter("ripples", nt)
		m.set_shader_parameter("glint", 1.3 if _cast_static else 0.0)
		_water_mat = m
	# The river runs on out of the map both ways (0.19.4; 0.31.13: no more waterfall -- the east is a valley like the west).
	var x0 := -Sim.HALF_W - Land.BAKE_MARGIN - Land.OUTER_REACH
	var x1 := Sim.HALF_W + Land.BAKE_MARGIN + Land.OUTER_REACH
	var span := 2.0 * (Sim.HALF_W + Land.BAKE_MARGIN)
	_water_strip(x0, x1, Land.WATER_Y, span, "water")

func _water_strip(xa: float, xb: float, y: float, span: float, tag: String) -> void:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()
	var n := int(ceil(xb - xa))
	var rows := WATER_ROWS
	for k in n + 1:
		var x := minf(xa + k, xb)
		var c := Land.river_c(x)
		var hw := Land.river_hw(x) + 0.35
		for r in rows + 1:
			var f := float(r) / float(rows)
			verts.append(Vector3(x, y, c - hw + 2.0 * hw * f))
			uvs.append(Vector2((x - xa) / span, 0.5 + (2.0 * f - 1.0) * hw / RIP_ACROSS))
			uv2s.append(Vector2(0.0, f))
		if k < n:
			for r in rows:
				var a := k * (rows + 1) + r
				var b := a + rows + 1
				idx.append_array([a, b, a + 1, a + 1, b, b + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = _water_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("perf", tag)
	add_child(mi)

# ---------- foliage: grass tufts + flowers (Round 7b) ----------
# 44-triangle tufts only (Grass_1_B is 132 triangles; dropped in 0.14.2 for frame rate).
const TUFTS := ["Grass_1_A_Color1", "Grass_2_A_Color1"]
const FLOWERS := ["red", "blue", "yellow", "white"]
static var _foliage: Dictionary = {}          # kind -> Array[Transform3D], built once per session

static func _foliage_ok(p: Vector2, mask: Image, obstacles: Array, allow_slope := false) -> bool:
	if absf(p.x) > Sim.HALF_W - 0.6 or absf(p.y) > Sim.HALF_L - 0.6:
		return false
	if Land.shore(p) < 0.9 or Land.edge_dist(p) > -0.9:
		return false
	if Land.keep_dist(p) < Keep.R + 1.5:
		return false                          # (0.31.165: the keeps' floors)
	if Land.in_dungeon_pit(p, 1.5):
		return false                          # the dungeon wing's floor and walls (Kevin: grass on the floor)
	var r := Land.bake_rect()
	var px := Vector2i(clampi(int((p.x - r.position.x) * Land.MASK_PPM), 0, mask.get_width() - 1),
		clampi(int((p.y - r.position.y) * Land.MASK_PPM), 0, mask.get_height() - 1))
	var mk := mask.get_pixelv(px)
	if mk.r > 0.46 or mk.a > 0.4:
		return false                          # on a dirt path (0.31.126: R is 0.5 at the track's edge), on a lane's paving
	var rd := Land.ridge_dist(p)
	if rd.x < rd.y + 1.1:
		return false                          # (0.31.216) under a rock formation, which stands wider than its wall
	if not allow_slope and mk.g > 0.3:
		return false                          # on a ledge rim / cliff band
	for ob in obstacles:
		if p.distance_to(ob.p) < float(ob.r) + 0.5:
			return false
	return true

static func _foliage_xf(p: Vector2, rng: RandomNumberGenerator, s0: float, s1: float) -> Transform3D:
	var y := Land.ground_height(p, false)
	var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(s0, s1))
	return Transform3D(b, Vector3(p.x, y - 0.03, p.y))

func _plan_foliage() -> Dictionary:
	# 0.31.216 (Kevin: "need new models for grass"): the painted grass clumps and flower patches (ground_cards.gd) --
	# clumps lining both edges of every lane's paving, clusters across the fields and the jungle, flowers lying in the
	# grass. {kind: [Transform3D...], kind + "_c": [Color...] (INSTANCE_CUSTOM)}. Seeded: the same every match (and baked
	# into the start-up cache by tools/bake_land.gd). (KayKit's grass tufts and the Blender flowers until then.)
	var rng := RandomNumberGenerator.new()
	rng.seed = 707
	var mask: Image = load(Land.MASK_RES)
	var obs: Array = sim.obstacles
	var brushes: Array = []
	if sim.moba != null and sim.moba.vision != null:
		brushes = sim.moba.vision.brushes
	var out := {"blades": [], "blades_c": [], "flowers": [], "flowers_c": []}
	var clump := func(p: Vector2, s0: float, s1: float) -> void:
		if _foliage_ok(p, mask, obs) and not _in_brush(p, brushes, 0.3):
			out.blades.append(_foliage_xf(p, rng, s0, s1))
			out.blades_c.append(GroundCards.custom(rng.randi() % 8, rng))
	# 1. Both edges of every lane's paving: where the slabs stop (the mask's A just under 0.5) the grass grows long.
	for pl in Land.paths():
		for i in range(pl.size() - 1):
			var a: Vector2 = pl[i]
			var b: Vector2 = pl[i + 1]
			var d := (b - a).normalized()
			var n := Vector2(-d.y, d.x)
			for side in [-1.0, 1.0]:
				if rng.randf() < 0.7:
					var q: Vector2 = a + d * rng.randf_range(0.0, a.distance_to(b)) + n * float(side) * (Land.LANE_PAVE_HALF + rng.randf_range(0.1, 0.9))
					clump.call(q, 0.75, 1.1)
	# 2. Clusters across the fields and the jungle.
	var area := Sim.HALF_W * Sim.HALF_L
	for c in int(area * 0.042):
		var cp := Vector2(rng.randf_range(-Sim.HALF_W, Sim.HALF_W), rng.randf_range(-Sim.HALF_L, Sim.HALF_L))
		if not Land.inside_field(cp):
			continue
		for k in rng.randi_range(3, 7):
			clump.call(cp + Vector2(rng.randf_range(-1.1, 1.1), rng.randf_range(-1.1, 1.1)), 0.6, 1.0)
	# 3. Flower patches.
	for c in int(area * 0.02):
		var fp := Vector2(rng.randf_range(-Sim.HALF_W, Sim.HALF_W), rng.randf_range(-Sim.HALF_L, Sim.HALF_L))
		if Land.inside_field(fp) and _foliage_ok(fp, mask, obs) and not _in_brush(fp, brushes, 0.6):
			var xf := _foliage_xf(fp, rng, 0.75, 1.15)
			xf.origin.y = Land.terrain_height(fp) + 0.02
			out.flowers.append(xf)
			out.flowers_c.append(GroundCards.custom(rng.randi() % 9, rng))
	return out

static func _in_brush(p: Vector2, brushes: Array, margin: float) -> bool:
	for b in brushes:
		if p.distance_to(b.p) < float(b.r) + margin:
			return true
	return false

const GroundCards = preload("res://scripts/siege/ground_cards.gd")

func _build_foliage() -> void:
	# One MultiMesh per kind and FOLIAGE_CELL square, so off-screen squares are culled (0.31.216: squares, not 32 m bands
	# across the whole map: the yawed camera sees a diagonal of the map).
	if _foliage.is_empty() or not _foliage.has("blades"):
		_foliage = _plan_foliage()
	for kind in ["blades", "flowers"]:
		var xfs: Array = _foliage.get(kind, [])
		var cs: Array = _foliage.get(kind + "_c", [])
		var cells := {}
		for i in xfs.size():
			if low_fx and i % 2 == 1:
				continue                                  # "Reduce effects": every other one
			var o: Vector3 = (xfs[i] as Transform3D).origin
			var key := Vector2i(int(floor(o.x / FOLIAGE_CELL)), int(floor(o.z / FOLIAGE_CELL)))
			if not cells.has(key):
				cells[key] = []
			cells[key].append(i)
		for key in cells:
			var ids: Array = cells[key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = GroundCards.mesh(kind)
			mm.instance_count = ids.size()
			for j in ids.size():
				mm.set_instance_transform(j, xfs[ids[j]])
				mm.set_instance_custom_data(j, cs[ids[j]])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = GroundCards.material(kind, PAINT_TINT * CARD_LIGHT)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.set_meta("perf", "foliage")
			mmi.set_meta("perf_kind", kind)
			mmi.visibility_range_end = 70.0
			add_child(mmi)

const FOLIAGE_CELL := 24.0
const CARD_LIGHT := 1.32               # the painted cards stand in the light (the ground's tint is for a surface facing up)

static var _tuft_mat: StandardMaterial3D = null
static var _tuft_wind: ShaderMaterial = null
static func _tuft_material(base: Material) -> Material:
	if _cast_static:
		# High-quality graphics: the tufts sway in rolling gusts (tips move, roots stay), lit per vertex like before.
		if _tuft_wind == null:
			var sh := Shader.new()
			sh.code = """
shader_type spatial;
render_mode cull_disabled, vertex_lighting, specular_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 albedo_col : source_color = vec4(1.0);
uniform bool use_tex = false;
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp(VERTEX.y / 0.5, 0.0, 1.0);
	float gust = sin(TIME * 1.3 + wp.x * 0.18 + wp.z * 0.11) * 0.5 + 0.5;
	float flutter = sin(TIME * 4.2 + wp.x * 1.3 + wp.z * 0.9);
	float sway = (gust * 0.10 + flutter * 0.025) * h;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.5;
}
void fragment() {
	vec3 c = albedo_col.rgb;
	if (use_tex) { c *= texture(albedo_tex, UV).rgb; }
	ALBEDO = c;
}
"""
			var m := ShaderMaterial.new()
			m.shader = sh
			var sm := base as StandardMaterial3D
			var col := Color(1.0, 1.18, 0.82)
			if sm != null:
				col = sm.albedo_color * Color(1.0, 1.18, 0.82)
				if sm.albedo_texture != null:
					m.set_shader_parameter("albedo_tex", sm.albedo_texture)
					m.set_shader_parameter("use_tex", true)
			m.set_shader_parameter("albedo_col", col)
			_tuft_wind = m
		return _tuft_wind
	return _tuft_material_plain(base)

static func _tuft_material_plain(base: Material) -> StandardMaterial3D:
	# Match the tufts to the terrain's green; per-vertex lighting (identical on tiny triangles,
	# cheaper per pixel on phones).
	if _tuft_mat == null:
		_tuft_mat = (base as StandardMaterial3D).duplicate() if base is StandardMaterial3D else StandardMaterial3D.new()
		_tuft_mat.albedo_color = Color(1.0, 1.18, 0.82)
		_tuft_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		_tuft_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return _tuft_mat

static var _flower_meshes: Dictionary = {}
static func _cheap_flower_mesh(mesh: Mesh) -> Mesh:
	# The Blender flowers export double-sided; their petals are closed shapes, so back faces are
	# never seen: cull them, and light per vertex. A MultiMesh has no per-surface overrides, so
	# this is a cached copy of the mesh with the cheaper materials baked in.
	if not _flower_meshes.has(mesh):
		var copy: Mesh = mesh.duplicate()
		for sidx in copy.get_surface_count():
			var base := copy.surface_get_material(sidx)
			if base is StandardMaterial3D:
				var m: StandardMaterial3D = (base as StandardMaterial3D).duplicate()
				m.cull_mode = BaseMaterial3D.CULL_BACK
				m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
				m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				copy.surface_set_material(sidx, m)
		_flower_meshes[mesh] = copy
	return _flower_meshes[mesh]

# Whirlwind FX (Round 12, Kevin: "spin visuals like World of Warcraft"): two translucent blade-trail
# ribbons (partial rings fading along their arc) circling the berserker at different heights and
# tilts, spinning faster than the body; built once per unit, then only rotated (transform only).
var whirl_nodes: Dictionary = {}
static var _whirl_mesh: ArrayMesh = null
static var _whirl_mat: StandardMaterial3D = null

static func _whirl_ribbon() -> ArrayMesh:
	if _whirl_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var seg := 28
		var arc := TAU * 0.72
		for i in seg:
			var t0 := float(i) / seg
			var t1 := float(i + 1) / seg
			var pts := []
			for t in [t0, t1]:
				var ang: float = arc * t
				var fade: float = pow(t, 1.6)                  # bright at the leading edge
				var inner := Vector3(cos(ang), 0, sin(ang)) * 0.62
				var outer := Vector3(cos(ang), 0, sin(ang)) * 1.0
				pts.append([inner + Vector3(0, -0.12, 0), outer + Vector3(0, 0.12, 0), fade])
			var a0: Array = pts[0]
			var a1: Array = pts[1]
			for v in [[a0[0], a0[2]], [a1[0], a1[2]], [a1[1], a1[2]], [a0[0], a0[2]], [a1[1], a1[2]], [a0[1], a0[2]]]:
				st.set_color(Color(1, 1, 1, float(v[1])))
				st.add_vertex(v[0])
		_whirl_mesh = st.commit()
	return _whirl_mesh

func _sync_whirls() -> void:
	if _whirl_mat == null:
		_whirl_mat = StandardMaterial3D.new()
		_whirl_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_whirl_mat.vertex_color_use_as_albedo = true
		_whirl_mat.albedo_color = Color(0.92, 0.95, 1.0, 0.75)
		_whirl_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_whirl_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_whirl_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for u in sim.units:
		var fx: Node3D = whirl_nodes.get(u.id)
		if not sim.whirling(u):
			if fx != null:
				fx.visible = false
			continue
		if fx == null:
			fx = Node3D.new()
			for k in 2:
				var mi := MeshInstance3D.new()
				mi.mesh = _whirl_ribbon()
				mi.material_override = _whirl_mat
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				fx.add_child(mi)
			add_child(fx)
			whirl_nodes[u.id] = fx
		var a: Dictionary = actors.get(u.id, {})
		if a.is_empty() or not (a.root as Node3D).visible:
			fx.visible = false
			continue
		fx.visible = true
		fx.position = (a.root as Node3D).position
		var r0 := fx.get_child(0) as Node3D
		var r1 := fx.get_child(1) as Node3D
		# Faster than the body (4 turns/s): ~7 and ~5.5 turns/s, tilted opposite ways.
		r0.transform = Transform3D(Basis(Vector3.UP, -_time * 44.0).rotated(Vector3.RIGHT, 0.18).scaled(Vector3(2.3, 1.0, 2.3)), Vector3(0, 1.05, 0))
		r1.transform = Transform3D(Basis(Vector3.UP, -_time * 34.0 + 2.0).rotated(Vector3.RIGHT, -0.22).scaled(Vector3(2.7, 1.0, 2.7)), Vector3(0, 0.6, 0))

var shield_nodes: Dictionary = {}        # knight id -> translucent shield-wall panel
static var _shield_mat: StandardMaterial3D = null

func _sync_shields() -> void:
	# A translucent panel where the sim's shield segment is, while a knight blocks (transform only).
	if _shield_mat == null:
		_shield_mat = StandardMaterial3D.new()
		_shield_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shield_mat.albedo_color = Color(0.55, 0.8, 1.0, 0.32)
		_shield_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shield_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for u in sim.units:
		if u.cls != "knight":
			continue
		var n: MeshInstance3D = shield_nodes.get(u.id)
		if not sim.blocking(u) or _fogged(u):
			if n != null:
				n.visible = false
			continue
		if n == null:
			n = MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(1.0, 1.6)
			n.mesh = q
			n.material_override = _shield_mat
			n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(n)
			shield_nodes[u.id] = n
		var sg: Array = sim.shield_seg(u)
		var a2: Vector2 = sg[0]
		var b2: Vector2 = sg[1]
		var mid := (a2 + b2) * 0.5
		var y := Sim.height_at(mid) + 0.85
		var along := Vector3(b2.x - a2.x, 0, b2.y - a2.y)
		n.visible = true
		n.transform = Transform3D(Basis(along, Vector3.UP, along.normalized().cross(Vector3.UP)), Vector3(mid.x, y, mid.y))

var beam_nodes: Dictionary = {}          # priest unit id -> MeshInstance3D (unit-length cylinder)

static var _beam_mats := {}

func _beam_material(key: String) -> StandardMaterial3D:
	if not _beam_mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = {"heal":Color(1.0, 0.95, 0.55, 0.75), "drain":Color(0.35, 1.0, 0.4, 0.85), "white":Color(1.0, 1.0, 1.0, 0.85)}[key]
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_beam_mats[key] = m
	return _beam_mats[key]

var _beam_ids := {}                              # units that have had a beam (their nodes may need hiding)

func _sync_beams() -> void:
	# The Priest's gold healing beam; the Necromancer's green drain on an enemy plus a white heal to an ally (0.31.2).
	for u in sim.units:
		# 0.31.160: a unit with no beam that never had one: nothing to show or hide (this ran its two slots -- arrays,
		# strings, lookups -- for every unit, every frame)
		if str(u.get("beam", "")) == "" and str(u.get("beam2", "")) == "" and not _beam_ids.has(u.id):
			continue
		_beam_ids[u.id] = true
		var necro: bool = u.cls == "priest" and bool(u.get("up", false))
		for slot in [["beam", str(u.id), "drain" if necro else "heal"], ["beam2", str(u.id) + "#2", "white"]]:
			var n: MeshInstance3D = beam_nodes.get(slot[1])
			var to: Dictionary = sim.by_id.get(str(u.get(slot[0], "")), {})
			if slot[2] == "drain" or plasma_nodes.has(slot[1]):
				_sync_plasma(slot[1], u, to if slot[2] == "drain" and sim.alive(u) and not _fogged(u) else {})
				if slot[2] == "drain":
					continue
			if to.is_empty() or not sim.alive(u) or _fogged(u):
				if n != null:
					n.visible = false
				continue
			if n == null:
				n = MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.07
				cm.bottom_radius = 0.07
				cm.height = 1.0
				cm.radial_segments = 6
				cm.rings = 1
				n.mesh = cm
				n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(n)
				beam_nodes[slot[1]] = n
			n.material_override = _beam_material(slot[2])
			var a: Dictionary = actors.get(u.id, {})
			var b: Dictionary = actors.get(to.id, {})
			if a.is_empty() or b.is_empty():
				n.visible = false
				continue
			var p0: Vector3 = (a.root as Node3D).position + Vector3(0, 1.35, 0) + Vector3(sin(float(u.face)), 0, cos(float(u.face))) * 0.35
			var p1: Vector3 = (b.root as Node3D).position + Vector3(0, 1.1, 0)
			var len := p0.distance_to(p1)
			if len < 0.05:
				n.visible = false
				continue
			n.visible = true
			# A unit cylinder along Y, stretched to the beam's length and aimed at the target; it flickers a little in width.
			var up := (p1 - p0) / len
			var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
			var fwd := side.cross(up)
			var w := (1.25 if slot[2] == "drain" else 1.0) + 0.25 * sin(_time * 25.0 + float(hash(slot[1]) % 100))
			n.transform = Transform3D(Basis(side * w, up * len, fwd * w), (p0 + p1) * 0.5)

# ---------- the Necromancer's plasma siphon (0.31.50) ----------
# Kevin: "a plasma beam" for the drain. Our own shader (plasma_beam.gdshader): a twisting plasma sheath round a hot core,
# pulses running from the victim into the Necromancer, a soft glow at each end -- the victim's a darker, purple-green
# wound, the Necromancer's a bright green bloom.
var plasma_nodes: Dictionary = {}
static var _plasma_mats := {}
const PLASMA_SHADER := preload("res://scripts/siege/plasma_beam.gdshader")

static func _plasma_mat(kind: String) -> Material:
	if not _plasma_mats.has(kind):
		if kind == "glow_src" or kind == "glow_dst":
			var gt := GradientTexture2D.new()
			gt.fill = GradientTexture2D.FILL_RADIAL
			gt.fill_from = Vector2(0.5, 0.5)
			gt.fill_to = Vector2(1.0, 0.5)
			var gr := Gradient.new()
			gr.set_color(0, Color(1, 1, 1, 1))
			gr.set_color(1, Color(1, 1, 1, 0))
			gr.add_point(0.35, Color(1, 1, 1, 0.55))
			gt.gradient = gr
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			m.no_depth_test = false
			m.albedo_texture = gt
			m.albedo_color = Color(0.3, 0.75, 0.35, 0.8) if kind == "glow_dst" else Color(0.45, 0.2, 0.75, 0.8)
			_plasma_mats[kind] = m
		else:
			var sm := ShaderMaterial.new()
			sm.shader = PLASMA_SHADER
			sm.set_shader_parameter("core", 1.0 if kind == "core" else 0.0)
			sm.set_shader_parameter("intensity", 1.35 if kind == "core" else 1.1)
			sm.set_shader_parameter("twist", 3.0)
			sm.set_shader_parameter("flow_dir", -1.0)     # 0.31.51 (Kevin): flowing back INTO the Necromancer (it ran out)
			_plasma_mats[kind] = sm
	return _plasma_mats[kind]

func _make_plasma() -> Node3D:
	var root := Node3D.new()
	for part in [["sheath", 0.3, 18], ["core", 0.07, 8]]:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = float(part[1])
		cm.bottom_radius = float(part[1])
		cm.height = 1.0
		cm.radial_segments = int(part[2])
		cm.rings = 1
		mi.mesh = cm
		mi.material_override = _plasma_mat(str(part[0]))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = str(part[0])
		root.add_child(mi)
	for g in [["glow_src", 0.9], ["glow_dst", 1.1]]:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2.ONE * float(g[1])
		q.mesh = qm
		q.material_override = _plasma_mat(str(g[0]))
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.name = str(g[0])
		root.add_child(q)
	return root

func _sync_plasma(key: String, u: Dictionary, to: Dictionary) -> void:
	var pb: Node3D = plasma_nodes.get(key)
	var a: Dictionary = actors.get(u.id, {})
	var b: Dictionary = actors.get(to.get("id", ""), {}) if not to.is_empty() else {}
	if to.is_empty() or a.is_empty() or b.is_empty():
		if pb != null:
			pb.visible = false
		return
	if pb == null:
		pb = _make_plasma()
		add_child(pb)
		plasma_nodes[key] = pb
	var p0: Vector3 = (a.root as Node3D).position + Vector3(0, 1.35, 0) + Vector3(sin(float(u.face)), 0, cos(float(u.face))) * 0.35
	var p1: Vector3 = (b.root as Node3D).position + Vector3(0, 1.1, 0)
	var len := p0.distance_to(p1)
	if len < 0.05:
		pb.visible = false
		return
	pb.visible = true
	var up := (p1 - p0) / len
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	var fwd := side.cross(up)
	var mid := (p0 + p1) * 0.5
	var h := float(hash(key) % 100)
	var wob := 1.0 + 0.14 * sin(_time * 13.0 + h) + 0.06 * sin(_time * 31.0 + h * 0.7)
	var sheath := pb.get_node("sheath") as MeshInstance3D
	var core := pb.get_node("core") as MeshInstance3D
	sheath.transform = Transform3D(Basis(side * wob, up * len, fwd * wob), mid)
	core.transform = Transform3D(Basis(side, up * len, fwd), mid)
	sheath.set_instance_shader_parameter("beam_len", len)
	core.set_instance_shader_parameter("beam_len", len)
	var g_src := pb.get_node("glow_src") as Node3D        # on the victim: the wound the plasma is pulled from
	var g_dst := pb.get_node("glow_dst") as Node3D        # at the Necromancer's hands
	g_src.position = p1
	g_dst.position = p0
	g_src.scale = Vector3.ONE * (0.9 + 0.2 * sin(_time * 9.0 + h))
	g_dst.scale = Vector3.ONE * (0.85 + 0.3 * pow(0.5 + 0.5 * sin(_time * 9.0 + h + 1.3), 3.0))

func _beacon_fire(at: Vector3) -> GPUParticles3D:
	# A fire basket's fire (the keep kit's braziers): soft additive flame puffs rising from the basket, shrinking as
	# they go; the ramp only shapes brightness and fade.
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.45
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 1.3
	pm.initial_velocity_max = 2.3
	pm.gravity = Vector3(0.0, 1.2, 0.0) + SMOKE_WIND * 0.3
	pm.damping_min = 0.6
	pm.damping_max = 1.0
	pm.scale_min = 0.7
	pm.scale_max = 1.25
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.7))
	sc.add_point(Vector2(0.25, 1.0))
	sc.add_point(Vector2(1.0, 0.15))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.12, 0.55, 1.0])
	g.colors = PackedColorArray([Color(1.25, 1.25, 1.25, 0.0), Color(1.2, 1.2, 1.2, 1.0), Color(0.9, 0.9, 0.9, 0.75),
		Color(0.6, 0.6, 0.6, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	var q := QuadMesh.new()
	q.size = Vector2(0.75, 1.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA      # mixed, not added: added flames wash out to white
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot()
	q.material = m
	var p := GPUParticles3D.new()
	p.process_material = pm
	p.draw_pass_1 = q
	p.amount = 36
	p.lifetime = 0.8
	p.preprocess = 1.0
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.fixed_fps = 30
	p.interpolate = true
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 5, 4))
	if low_fx:
		p.amount_ratio = 0.6
	add_child(p)
	p.global_position = at
	return p

func _place(path: String, pos: Vector3, rot := 0.0, s := 1.0) -> Node3D:
	var packed := Stage.scene(path)
	if packed == null:
		return null
	var node: Node3D = packed.instantiate()
	node.position = pos
	node.rotation.y = rot
	node.scale = Vector3.ONE * s
	add_child(node)
	return node

func _build_edge_scenery() -> void:
	# Scenery beyond the field's edge (0.26.0): trees along the tops of the rock walls, none over
	# the cliff side or in the river's gorge; a few wooded hills further out.
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var per := {}                                   # (0.31.173: the Meshy trees, batched per kind; were KayKit trees, a node each)
	var loop := Land.edge_loop()
	for i in loop.size():
		var a: Vector2 = loop[i]
		var b: Vector2 = loop[(i + 1) % loop.size()]
		var L := a.distance_to(b)
		var nrm := Vector2((b - a).y, -(b - a).x).normalized()
		if Land.inside_field((a + b) * 0.5 + nrm * 1.5):
			nrm = -nrm
		var t := rng.randf_range(0.0, 2.0)
		while t < L:
			var q := a.lerp(b, t / L) + nrm * rng.randf_range(3.5, 7.5)
			if absf(q.y - Land.river_c(q.x)) > Land.RIVER_HW + 3.5 and not Land.in_dungeon_pit(q, 2.0):
				var kind := Foliage.pick(rng, Foliage.OUTER_TREES)
				if not per.has(kind):
					per[kind] = []
				(per[kind] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * (0.6 + rng.randf() * 0.25)),
					Vector3(q.x, Land.terrain_height(q), q.y)))
			t += rng.randf_range(4.0, 6.5)
	for kind in per:
		_plant_batch(kind, per[kind], _cast(), "edge_trees")
	for p in [Vector3(-Sim.HALF_W - 8, 0.5, -40), Vector3(-Sim.HALF_W - 8, 0.5, 14), Vector3(-Sim.HALF_W - 8, 0.5, -10),
			Vector3(Sim.HALF_W - 4, 0.5, 64), Vector3(Sim.HALF_W - 4, 0.5, -64), Vector3(0, 0.5, -Sim.HALF_L - 8), Vector3(0, 0.5, Sim.HALF_L + 8)]:
		_place(HEX + "mountain_A_grass_trees.gltf", Vector3(p.x, Land.terrain_height(Vector2(p.x, p.z)) - 0.3, p.z), rng.randf()*TAU, 1.6)

const COLOR := ["blue", "red"]
static var _floor_mats: Dictionary = {}

func _wall_run(a: Vector2, b: Vector2, path: String, y := 0.0, clip := true, inside := Vector2.INF) -> void:
	# inside (optional): a point inside what the wall encloses. The kit wall's stone face is its local +Z
	# (the other side has the walkway lip); pieces turn so the stone faces AWAY from it (Round 14,
	# Kevin: "the castle walls are backwards" -- the rotation came from the segment's direction, and
	# the red castle's mirrored walls run the other way; the model is centred, so turning doesn't shift it).
	# Lay 5.2 m wall models along a segment (clipped to the field unless told not to), stretched to fit.
	var aa := Vector2(clampf(a.x, -Sim.HALF_W, Sim.HALF_W), clampf(a.y, -Sim.HALF_L, Sim.HALF_L)) if clip else a
	var bb := Vector2(clampf(b.x, -Sim.HALF_W, Sim.HALF_W), clampf(b.y, -Sim.HALF_L, Sim.HALF_L)) if clip else b
	var length := aa.distance_to(bb)
	if length < 0.5:
		return
	var n := maxi(1, int(round(length / Sim.SEG)))
	var piece := length / float(n)
	var rot := -atan2(bb.y - aa.y, bb.x - aa.x)
	if inside != Vector2.INF:
		var d := (bb - aa).normalized()
		var stone := Vector2(-d.y, d.x)                  # where local +Z points with this rotation
		if stone.dot((aa + bb) * 0.5 - inside) < 0.0:
			rot += PI
	for i in n:
		var c := aa.lerp(bb, (float(i) + 0.5) / float(n))
		var node := _place(path, Vector3(c.x, y, c.y), rot, Sim.WALL_SCALE)
		if node != null:
			node.scale.x = Sim.WALL_SCALE * piece / Sim.SEG
			_kit_nodes.append(node)

var _kit_nodes: Array = []

# ---------- Meshy castle kits (0.31.74, castle_kit.gd) ----------
func _kit_piece(model: String, t: int, merge: bool) -> Node3D:
	# One kit model (foot at its origin), added to the view. merge: baked into the castle's merged meshes with the
	# other copies of it (_merge_kit; the many wall pieces); otherwise a node of its own (keeps its LODs).
	var root := CastleKit.piece(model, vt(t))
	add_child(root)
	if merge:
		_kit_nodes.append(root)
	else:
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = _cast()
			mi.set_meta("perf", "castle")
	return root

func _kit_wall_run(t: int, a: Vector2, b: Vector2, y: float, clip: bool, inside: Vector2) -> void:
	# The kit's curtain wall along a sim wall line -- as _wall_run (same clipping, decorated face away from inside),
	# in pieces of about the kit's length, stretched to fit.
	if _kit_skip:
		return
	var k: Dictionary = CastleKit.kit(t).wall
	var aa := Vector2(clampf(a.x, -Sim.HALF_W, Sim.HALF_W), clampf(a.y, -Sim.HALF_L, Sim.HALF_L)) if clip else a
	var bb := Vector2(clampf(b.x, -Sim.HALF_W, Sim.HALF_W), clampf(b.y, -Sim.HALF_L, Sim.HALF_L)) if clip else b
	var length := aa.distance_to(bb)
	if length < 0.5:
		return
	var n := maxi(1, int(round(length / float(k.len))))
	var piece := length / float(n)
	var rot := -atan2(bb.y - aa.y, bb.x - aa.x)
	if inside != Vector2.INF:
		var d := (bb - aa).normalized()
		if Vector2(-d.y, d.x).dot((aa + bb) * 0.5 - inside) < 0.0:
			rot += PI
	for i in n:
		var c := aa.lerp(bb, (float(i) + 0.5) / float(n))
		var root := _kit_piece(str(k.m), t, true)
		var size: Vector3 = root.get_meta("size")
		root.position = Vector3(c.x, y, c.y)
		root.rotation.y = rot
		root.scale = Vector3(piece / size.x, float(k.h) / size.y, float(k.depth) / size.z)

func _kit_fire(root: Node3D, model_pt: Vector3, _size: Vector3) -> void:
	# A small flame at a point given in the model's own units (a brazier's bowl, the forge, a torch).
	var at := root.to_global(model_pt + Vector3(root.get_meta("lift")))
	var s := root.scale.x
	var f := _beacon_fire(at)
	f.scale = Vector3.ONE * clampf(s * 0.22, 0.22, 0.5)
	((f.draw_pass_1 as QuadMesh).material as StandardMaterial3D).albedo_color = Color(1.5, 0.62, 0.18, 0.8)
	f.amount = 14

static var _kit_merged: Dictionary = {}      # team -> [[material, merged mesh], ...]: a castle's walls, kept for rematches
var _kit_skip := false                      # building a castle whose merged walls are cached: the pieces aren't made

func _merge_kit(team := -1) -> void:
	# All KayKit hex models share one atlas material: bake every static castle piece (walls,
	# terrace walls, towers, buildings, props, banners, trees) into ONE mesh per material instead
	# of ~70 separate draw calls per castle. Animated pieces (gates, catapults) and the hat stands
	# stay separate. 0.31.78: the merged meshes of a kit castle are kept (per team) for the next match of the session,
	# which then skips the ~40 wall pieces and the merge (~80 ms a castle here).
	if team >= 0 and _kit_merged.has(team):
		for pair in _kit_merged[team]:
			var mi := MeshInstance3D.new()
			mi.mesh = pair[1]
			mi.material_override = pair[0]
			mi.cast_shadow = _cast()
			mi.set_meta("perf", "castle")
			add_child(mi)
		_kit_nodes.clear()
		_kit_skip = false
		return
	var tools := {}
	for n in _kit_nodes:
		if n == null or not is_instance_valid(n):
			continue
		for mi in (n as Node).find_children("*", "MeshInstance3D", true, false):
			var m3 := mi as MeshInstance3D
			var xf: Transform3D = global_transform.affine_inverse() * m3.global_transform
			for si in m3.mesh.get_surface_count():
				var mat: Material = m3.get_active_material(si)
				if not tools.has(mat):
					var st := SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					tools[mat] = st
				(tools[mat] as SurfaceTool).append_from(m3.mesh, si, xf)
		(n as Node).queue_free()
	_kit_nodes.clear()
	var merged := []
	for mat in tools:
		var mi := MeshInstance3D.new()
		mi.mesh = (tools[mat] as SurfaceTool).commit()
		mi.material_override = mat
		mi.cast_shadow = _cast()
		mi.set_meta("perf", "castle")
		add_child(mi)
		merged.append([mat, mi.mesh])
	if team >= 0 and CASTLE_KITS:
		_kit_merged[team] = merged
	_kit_skip = false

# ---------- 0.31.165: the Rift's keeps (keep.gd), ridges and fords (siege_land.gd) ----------
func _build_keep(t: int) -> void:
	# A keep: its paved floor; the kit's curtain wall along the sim's ring (so collision and visuals agree), a tower on
	# every third joint; a gatehouse with doors at each gate (they swing open for the keep's own side, break into
	# rubble -- the gates are League's inhibitors); the throne with the kit's canopy behind it and a carpet down to the
	# middle gate; the fountain at the back where heroes come back.
	var kit: Dictionary = CastleKit.kit(t)
	var face := 0.0 if t == 0 else PI
	var cen: Vector2 = Sim._m(t, Keep.C)
	_kit_skip = CASTLE_KITS and _kit_merged.has(t)
	_keep_floor(t, cen)
	for w in sim.walls:
		if int(w.team) == t and str(w.kind) == "wall":
			# (a little longer than the chord: the pieces overlap at the joints, no wedge of sky between them)
			var d: Vector2 = ((w.b as Vector2) - (w.a as Vector2)).normalized()
			_kit_wall_run(t, (w.a as Vector2) - d * 0.4, (w.b as Vector2) + d * 0.4, 0.0, false, cen)
	var tk: Dictionary = kit.tower
	var joints := Keep.joints()
	for k in joints.size():
		if k % 3 != 0:
			continue
		var jp: Vector2 = Sim._m(t, joints[k])
		var out: Vector2 = (jp - cen).normalized()
		var tw := _kit_piece(str(tk.m), t, false)
		tw.position = Vector3(jp.x, 0.0, jp.y)
		tw.rotation.y = atan2(out.x, out.y)
		tw.scale = Vector3.ONE * float(tk.s)
	var gk: Dictionary = kit.gatehouse
	var big := Keep.GATEHOUSE_K
	for g in sim.gates:
		if int(g.team) != t:
			continue
		var out: Vector2 = -(g["in"] as Vector2)
		var rot := atan2(out.x, out.y)                   # local +Z (the stone face) outwards
		var node := _place(HEX + "wall_straight_gate.gltf", Vector3(g.c.x, 0, g.c.y), rot, Sim.WALL_SCALE)
		var gh := _kit_piece(str(gk.m), t, false)
		var gp: Vector2 = (g.c as Vector2) + out * float(gk.out)
		gh.position = Vector3(gp.x, 0.0, gp.y)
		gh.rotation.y = rot
		gh.scale = Vector3.ONE * float(gk.s) * big
		node.scale = Vector3.ONE * float(gk.door) * big
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			if not str(mi.name).contains("door"):
				(mi as MeshInstance3D).mesh = null          # its wall piece (the doors are its children: hiding it hid them)
		var doors := []
		for mi in node.find_children("*door*", "MeshInstance3D", true, false):
			doors.append({"node":mi, "sign":1.0 if str(mi.name).contains("left") else -1.0})
		var rubble := Node3D.new()
		rubble.position = Vector3(g.c.x, 0, g.c.y)
		add_child(rubble)
		var along := Vector2(out.y, -out.x)
		for i in 3:
			var rp: Vector2 = (g.c as Vector2) + along * (i - 1) * 1.1 + out * randf_range(-0.3, 0.3)
			var r := _place(HEX + ["rock_single_D.gltf", "rock_single_E.gltf", "crate_open.gltf"][i],
				Vector3(rp.x, 0, rp.y), randf() * TAU, [3.2, 3.2, 1.7][i])
			if r != null:
				r.reparent(rubble, true)
		rubble.visible = false
		gate_nodes[g.id] = {"doors":doors, "rubble":rubble, "open":0.0, "broken":false}
	# the throne: the kit's canopy behind it, the Blender throne (velvet in the side's colour), a carpet to the gate
	var thk: Dictionary = kit.throne
	var tp: Vector2 = Sim._m(t, Keep.THRONE_SEAT)
	var cpiece := _kit_piece(str(thk.m), t, false)
	var csize: Vector3 = cpiece.get_meta("size")
	var s3 := float(thk.s)
	var bp: Vector2 = Sim._m(t, Keep.THRONE_SEAT + Vector2(0.0, 0.55))
	cpiece.position = Vector3(bp.x, -float(thk.get("sink", 0.0)), bp.y)
	cpiece.rotation.y = face + PI
	cpiece.scale = Vector3(s3, s3 * float(thk.ys), s3)
	for fp in (kit.fires as Dictionary).get(str(thk.m), []):
		_kit_fire(cpiece, Vector3(fp), csize)
	var throne := _place("res://assets/props/throne.glb", Vector3(tp.x, float(thk.lift), tp.y), PI if t == 0 else 0.0, 1.0)
	if throne != null:
		var velvet := StandardMaterial3D.new()
		velvet.albedo_color = Color("#2d58b8") if vt(t) == 0 else Color("#b3223a")
		velvet.roughness = 0.85
		for mi in throne.find_children("*", "MeshInstance3D", true, false):
			var m: MeshInstance3D = mi
			for si in m.mesh.get_surface_count():
				var sm := m.mesh.surface_get_material(si)
				if sm != null and str(sm.resource_name) == "Velvet":
					m.set_surface_override_material(si, velvet)
	_carpet(Sim._m(t, Keep.KING + Vector2(0.0, 1.2)), Sim._m(t, Keep.gate_c(1) + Vector2(0.0, 1.6)), 2.6,
		Color("#2f5f8a") if vt(t) == 0 else Color("#8a3a2f"))
	var th: Vector2 = Sim.throne(t)
	_decal(Vector3(th.x, 0.06, th.y), 2.2, TEAM_COLORS[vt(t)], 0.6)            # (the old throne's reach)
	# the fountain: the kit's fountain on a round dais, a ring of light round where heroes come back and heal
	var fpos: Vector2 = Sim._m(t, Keep.FOUNTAIN)
	_keep_prop(t, Keep.FOUNTAIN_MODEL, Keep.FOUNTAIN, 0.0, 2.2)
	_decal(Vector3(fpos.x, 0.07, fpos.y), Keep.FOUNTAIN_R + 0.2, TEAM_COLORS[vt(t)], 0.55)
	# a few of the kit's props against the back of the wall (clear of the fighting in the middle)
	for pr in Keep.PROPS:
		_keep_prop(t, str(pr[0]), pr[1], float(pr[2]), float(pr[3]))

func _keep_prop(t: int, model: String, spot: Vector2, turn_deg: float, height: float) -> Node3D:
	# a kit prop at a spot in blue's keep (world coordinates, mirrored for red): turn 0 = its front faces the keep's front
	var root := _kit_piece(model, t, false)
	var size: Vector3 = root.get_meta("size")
	var p: Vector2 = Sim._m(t, spot)
	root.position = Vector3(p.x, 0.0, p.y)
	root.rotation.y = (0.0 if t == 0 else PI) + PI + deg_to_rad(turn_deg)
	root.scale = Vector3.ONE * (height / size.y)
	for fp in (CastleKit.kit(t).fires as Dictionary).get(model, []):
		_kit_fire(root, Vector3(fp), size)
	return root

static var _keep_floor_mats: Dictionary = {}
const KEEP_PAVE_M := 6.0

func _keep_floor(t: int, cen: Vector2) -> void:
	# the kit's courtyard paving over the whole keep (under the wall's foot), the cloud shadows drifting over it too
	if not _keep_floor_mats.has(t):
		# 0.31.216: the royal paving ElevenLabs painted (tools/ground_paint.py: cream and gold sandstone, carved tiles here
		# and there), KEEP_PAVE_M metres a tile; the castle kit's court floor until then
		var tex: Texture2D = Stage.texture(PAINT + "keep.webp")
		var tint := Color(0.9, 0.88, 0.86)
		var uv := FLOOR_TILE / KEEP_PAVE_M
		if _cast_static:
			_keep_floor_mats[t] = _cloud_floor_material(tex, tint, uv)
		else:
			var fm := StandardMaterial3D.new()
			fm.albedo_texture = tex
			fm.albedo_color = tint
			fm.uv1_scale = Vector3(uv, uv, 1.0)
			fm.roughness = 0.95
			fm.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			_keep_floor_mats[t] = fm
	var n := 48
	var rad := Keep.R + 0.6
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.append(Vector3(cen.x, 0.03, cen.y))
	uvs.append(cen / FLOOR_TILE)
	norms.append(Vector3.UP)
	for k in n:
		var q := cen + Vector2.from_angle(TAU * k / n) * rad
		verts.append(Vector3(q.x, 0.03, q.y))
		uvs.append(q / FLOOR_TILE)
		norms.append(Vector3.UP)
	for k in n:
		idx.append_array([0, 1 + k, 1 + (k + 1) % n])        # (clockwise seen from above: the front)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = _keep_floor_mats[t]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("perf", "castle")
	add_child(mi)

func _carpet(a: Vector2, b: Vector2, w: float, color: Color) -> void:
	var key := color.to_html()
	if not _floor_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.95
		_floor_mats[key] = m
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, a.distance_to(b))
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = _floor_mats[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var c := (a + b) * 0.5
	mi.position = Vector3(c.x, 0.05, c.y)
	mi.rotation.y = atan2(b.x - a.x, b.y - a.y)
	add_child(mi)

const RIDGE_ROCKS := ["Rock_1_D_Color1", "Rock_1_E_Color1", "Rock_1_F_Color1"]
const RIDGE_SMALL := ["Rock_1_A_Color1", "Rock_1_B_Color1", "Rock_1_C_Color1"]
static var _ridge_plan: Dictionary = {}       # model -> Array[Transform3D], built once per session

static func _plan_ridges() -> Dictionary:
	# Along each of the Rift's ridges (Land.ridges(): the sim's "rock" walls): boulders shouldered together along the
	# line with smaller stones at their feet, or a stand of trees with bushes under them. Seeded: the same every match.
	var rng := RandomNumberGenerator.new()
	rng.seed = 165
	var out := {}
	for k in RIDGE_ROCKS + RIDGE_SMALL + Foliage.RIDGE_TREES.keys() + Foliage.RIDGE_BUSHES.keys():
		out[k] = []
	for rg in Land.ridges():
		var pts: Array = rg.pts
		var r := float(rg.r)
		var trees: bool = str(rg.look) == "trees"
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var L := a.distance_to(b)
			var d := (b - a) / L
			var nrm := Vector2(-d.y, d.x)
			var t := 0.0 if i == 0 else rng.randf_range(0.4, 0.9)
			while t <= L + 0.01:
				var q := a + d * t + nrm * rng.randf_range(-0.35, 0.35) * r
				var y := Land.terrain_height(q) - 0.15
				if trees:
					# (0.31.173: the Meshy trees and bushes of foliage.gd; were KayKit's)
					var s := rng.randf_range(0.78, 0.98)
					out[Foliage.pick(rng, Foliage.RIDGE_TREES)].append(
						Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(q.x, y, q.y)))
					for side in [-1.0, 1.0]:
						if rng.randf() < 0.7:
							var bq: Vector2 = q + nrm * side * (r + rng.randf_range(-0.2, 0.3)) + d * rng.randf_range(-0.6, 0.6)
							var bs := rng.randf_range(1.3, 1.9)
							out[Foliage.pick(rng, Foliage.RIDGE_BUSHES)].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(
								Vector3.ONE * bs), Vector3(bq.x, Land.ground_height(bq, false) - 0.05, bq.y)))
					t += rng.randf_range(1.8, 2.4)
				elif not SCULPTED_ROCKS:
					var s2 := (2.0 * r + 0.4) * rng.randf_range(0.95, 1.2)
					var sy := rng.randf_range(0.75, 1.05)
					out[RIDGE_ROCKS[rng.randi() % RIDGE_ROCKS.size()]].append(Transform3D(
						Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s2, s2 * sy, s2)), Vector3(q.x, y - 0.25, q.y)))
					for side in [-1.0, 1.0]:
						if rng.randf() < 0.45:
							var sq: Vector2 = q + nrm * side * (r + rng.randf_range(0.0, 0.4)) + d * rng.randf_range(-0.7, 0.7)
							var ss := rng.randf_range(0.9, 1.6)
							out[RIDGE_SMALL[rng.randi() % RIDGE_SMALL.size()]].append(Transform3D(
								Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * ss), Vector3(sq.x, Land.ground_height(sq, false) - 0.08, sq.y)))
					t += rng.randf_range(1.1, 1.5) * r
				else:
					break                                  # (0.31.216: rock_sculpt.gd builds the rock walls)
	return out

# 0.31.216 (Kevin: "need new models for grass and rock formations"; sculpted in code): the rock walls and the pits'
# rims are Honor of Kings' chunky blue-grey formations (rock_sculpt.gd, rock_formation.gdshader), not KayKit's rocks
const SCULPTED_ROCKS := true
const RockSculpt = preload("res://scripts/siege/rock_sculpt.gd")
static var _rock_mat: ShaderMaterial = null

static func _rock_material() -> ShaderMaterial:
	if _rock_mat == null:
		_rock_mat = ShaderMaterial.new()
		_rock_mat.shader = load("res://scripts/siege/rock_formation.gdshader")
		_rock_mat.set_shader_parameter("rock_tex", Stage.texture(PAINT + "rock.webp"))
		_rock_mat.set_shader_parameter("moss_tex", Stage.texture(PAINT + "grass.webp"))
		_rock_mat.set_shader_parameter("macro_tex", _terrain_material().get_shader_parameter("macro_tex"))
		_rock_mat.set_shader_parameter("tint", PAINT_TINT * 1.12)
	return _rock_mat

func _build_ridges() -> void:
	# One MultiMesh per model and 32 m band (off-screen bands are culled); they cast shadows like the keeps do.
	if SCULPTED_ROCKS:
		for m in RockSculpt.meshes():
			var mi := MeshInstance3D.new()
			mi.mesh = m
			mi.material_override = _rock_material()
			mi.cast_shadow = _cast()
			mi.set_meta("perf", "ridges")
			mi.set_meta("perf_kind", "sculpted")
			add_child(mi)
	if _ridge_plan.is_empty():
		_ridge_plan = _plan_ridges()
	for kind in _ridge_plan:
		var xfs: Array = _ridge_plan[kind]
		if xfs.is_empty():
			continue
		if Foliage.is_plant(str(kind)):
			# (0.31.173) a Meshy tree or bush: trees cast shadows, bushes don't
			_plant_batch(str(kind), xfs, _cast() if str(kind).begins_with("tree") else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "ridges")
			continue
		var packed := Stage.scene(FOREST + str(kind) + ".gltf")
		if packed == null:
			continue
		var node: Node3D = packed.instantiate()
		var src: MeshInstance3D = node.find_children("*", "MeshInstance3D", true, false)[0]
		var bands := {}
		for xf in xfs:
			var bkey := int(floor(((xf as Transform3D).origin.z + Sim.HALF_L) / 32.0))
			if not bands.has(bkey):
				bands[bkey] = []
			bands[bkey].append(xf)
		for bkey in bands:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = src.mesh
			mm.instance_count = bands[bkey].size()
			for i in mm.instance_count:
				mm.set_instance_transform(i, (bands[bkey][i] as Transform3D) * src.transform)
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = _cast()
			mmi.set_meta("perf", "ridges")
			mmi.set_meta("perf_kind", kind)
			add_child(mmi)
		node.free()

const PLANT_CELL := 16.0

func _plant_batch(kind: String, xfs: Array, shadow: GeometryInstance3D.ShadowCastingSetting, perf: String, cell := PLANT_CELL) -> void:
	# 0.31.173: a Meshy tree or bush (foliage.gd) at these places -- one MultiMesh per PLANT_CELL square: the portrait
	# view sees a strip a fraction of the field's width, so whole-width bands drew ~3x the plants on screen, and a
	# small cell's distance lets the far ones take the engine's lighter LODs (only where the difference is under a pixel).
	# A tree's shadow is drawn from its shadow copy (Foliage.shadow_of: the same model remeshed by Meshy, its canopy just
	# inside the tree's own -- tools/foliage_prep.py --shadow) in a shadow-only MultiMesh; the tree itself casts none:
	# a third of the triangles in the shadow pass for the same shadow on the ground.
	var tm := Foliage.mesh(kind)
	if tm == null:
		return
	var sk := Foliage.shadow_of(kind) if shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF else ""
	var sm: Mesh = Foliage.mesh(sk) if sk != "" else null
	var cells := {}
	for xf in xfs:
		var o: Vector3 = (xf as Transform3D).origin
		var ckey := Vector2i(int(floor(o.x / cell)), int(floor(o.z / cell)))
		if not cells.has(ckey):
			cells[ckey] = []
		cells[ckey].append(xf)
	for ckey in cells:
		var mmi := _plant_mm(tm, cells[ckey], Foliage.material(kind), GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if sm != null else shadow)
		mmi.set_meta("perf", perf)
		mmi.set_meta("perf_kind", kind)
		mmi.set_meta("places", cells[ckey])          # (the instances' transforms live in the renderer: tests read them here)
		mmi.name = "%s_%s_%d_%d" % ["Brush" if perf == "brush" else "Plants", kind, ckey.x, ckey.y]     # (tests and the bench find the brush by name)
		add_child(mmi)
		if sm != null:
			var smi := _plant_mm(sm, cells[ckey], Foliage.material(sk), GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
			smi.set_meta("perf", perf + "_shadow")
			smi.set_meta("perf_kind", sk)
			smi.name = "Shadows_%s_%d_%d" % [kind, ckey.x, ckey.y]
			add_child(smi)

static func _plant_mm(m: Mesh, xfs: Array, mat: Material, shadow: GeometryInstance3D.ShadowCastingSetting) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m
	mm.instance_count = xfs.size()
	for i in mm.instance_count:
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = shadow
	return mmi

func _build_fords() -> void:
	# The fords' stepping stones: flat stones across each (Land.FORDS), a little proud of the water, in staggered rows.
	var rng := RandomNumberGenerator.new()
	rng.seed = 166
	var src := _mesh_of(FOREST + "Rock_1_E_Color1.gltf")
	if src.is_empty():
		return
	var xfs := []
	for f in Land.FORDS:
		var fx := float(f[0])
		var hw := float(f[1])
		if absf(fx) < 1.0 or absf(absf(fx) - Land.SIDE_CORNER_X) < 1.0:
			continue                               # (0.31.216: a lane's ford is its paving, laid through the water)
		var c := Land.river_c(fx)
		var reach := Land.river_hw(fx) + 0.6
		var y := c - reach
		var row := 0
		while y <= c + reach:
			var x := fx - hw + (0.55 if row % 2 == 1 else 0.0) + rng.randf_range(0.0, 0.3)
			while x <= fx + hw:
				var q := Vector2(x, y + rng.randf_range(-0.15, 0.15))
				if Land.shore(q) < 0.4 and Land.island_off(q) > 0.2:
					var s := rng.randf_range(0.7, 0.95)
					xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, 0.16, s)),
						Vector3(q.x, Land.FORD_Y - 0.12, q.y)))
				x += rng.randf_range(1.1, 1.4)
			y += 1.15
			row += 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = src.mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sm := StandardMaterial3D.new()                   # pale, water-worn stone (the forest rocks' grey read as a dark cobble patch)
	sm.albedo_color = Color("#8d949a")             # (0.31.216: the lanes' grey-blue slabs; #b9b2a2 until then)
	sm.roughness = 0.9
	mmi.material_override = sm
	mmi.set_meta("perf", "fords")
	add_child(mmi)

func _sync_castle(dt: float) -> void:
	_sync_beams()
	_sync_shields()
	_sync_whirls()
	for g in sim.gates:
		var gn: Dictionary = gate_nodes.get(g.id, {})
		if gn.is_empty():
			continue
		var broken: bool = not sim.gate_blocks(g)
		# (0.31.78: transforms and visibility are set only when they change -- a closed gate's doors were re-posed every
		# frame, every tree re-scaled, every stockpile piece re-shown: each a transform update for the renderer)
		if broken != bool(gn.broken):
			gn.broken = broken
			(gn.rubble as Node3D).visible = broken
			for d in gn.doors:
				(d.node as Node3D).visible = not broken
		var want := 1.0 if (g.open and not broken) else 0.0
		var was := float(gn.open)
		gn.open = move_toward(was, want, dt * 2.5)
		if float(gn.open) != was:
			for d in gn.doors:
				(d.node as Node3D).rotation.y = float(d.sign) * float(gn.open) * PI * 0.5
	for t in 2:
		var o_node: Dictionary = oracle_nodes[t] if t < oracle_nodes.size() else {}
		if not o_node.is_empty() and o_node.body != null:
			var body: Node3D = o_node.body
			var breathe := 1.0 + 0.018 * sin(_time * 2.4 + t)
			body.scale = Vector3(2.0 - breathe, breathe, 2.0 - breathe)
			body.rotation = Vector3(0.0, 0.08 * sin(_time * 0.9 + t * 2.0), 0.035 * sin(_time * 1.3 + t))

func _unshaded(color: Color, additive := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	return m

func _ring_mesh(radius: float, width := 0.14) -> TorusMesh:
	var key := "%.2f:%.2f" % [radius, width]
	if _rings.has(key):
		return _rings[key]
	var tm := TorusMesh.new()
	tm.inner_radius = radius - width
	tm.outer_radius = radius
	tm.rings = 32
	tm.ring_segments = 4
	_rings[key] = tm
	return tm

func _decal(pos: Vector3, radius: float, color: Color, alpha: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh(radius, 0.18)
	mi.scale = Vector3(1, 0.15, 1)
	var c := color
	c.a = alpha
	mi.material_override = _unshaded(c)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	add_child(mi)
	return mi

# ---------- actors ----------
# What the players wear (0.31.101, Kevin: "I want players to see everything the other players are wearing"): mine from
# the profile, the other live players' from the server's "pn" (set_unit_looks); bots wear the defaults. 0.31.188 (Kevin:
# "I only want the cosmetics to be an entire outfit"): an outfit -- the hero's body repainted and its own weapon
# (Eco.SKINS) -- is all there is; the weapons and Forge stars per class (0.31.101-0.31.187) are gone.
var player_skins: Dictionary = {}            # 0.31.186: hero -> the outfit I wear on him (Profile.d.skin_on)
var unit_skins: Dictionary = {}              # 0.31.186: unit id -> the outfits that player wears (the looks' "_sk")
var _skin_cos: Dictionary = {}               # unit id -> {"skin", "out"}: an outfit's cosmetic, made once
const NO_LOOK := {}

func set_unit_looks(wire: Dictionary) -> void:
	# the server's {unit id: looks} -> the outfits each other player wears
	unit_skins = {}
	for uid in wire:
		if str(uid) == player_id:
			continue
		if wire[uid] is Dictionary and str((wire[uid] as Dictionary).get("_sk", "")) != "":
			unit_skins[str(uid)] = str(wire[uid]._sk).split(",")      # 0.31.186: the outfits they wear

func unit_cosmetic(u: Dictionary) -> Dictionary:
	# what this unit wears: the outfit on this hero (mine, or theirs online) -- made once, the same dictionary every frame
	var skin := unit_skin(u)
	if skin == "":
		return NO_LOOK
	var c: Dictionary = _skin_cos.get(u.id, {})
	if c.is_empty() or str(c.skin) != skin:
		c = {"skin": skin, "out": {"skin": skin, "lite": low_fx and str(u.id) != player_id}}
		_skin_cos[u.id] = c
	return c.out

func unit_skin(u: Dictionary) -> String:
	# 0.31.186: the skin this hero wears -- the one of mine (or that player's) made for him; bots wear none
	var hid := str(u.get("hid", ""))
	if hid == "" or not bool(u.get("hero", true)):
		return ""
	if str(u.id) == player_id:
		var mine := str(player_skins.get(hid, ""))
		return mine if Eco.SKINS.has(mine) and str(Eco.SKINS[mine].hero) == hid else ""
	for id in unit_skins.get(str(u.id), []):
		if Eco.SKINS.has(str(id)) and str(Eco.SKINS[str(id)].hero) == hid:
			return str(id)
	return ""
static var _tint_mats: Dictionary = {}

static func look_key(u: Dictionary) -> String:
	if u.has("look"):
		return str(u.look)                      # 0.31.157: a jungle monster, a LEGION skeleton
	if bool(u.get("minion", false)) and MINION_LOOKS.has(str(u.get("mk", ""))):
		return str(MINION_LOOKS[str(u.mk)])     # 0.31.159: the lane minions' own bodies
	if u.cls == "barbarian" and u.up:
		return "berserker"
	if u.cls == "priest" and u.up:
		return "necromancer"
	if u.cls == "knight" and u.up:
		return "crusader"                     # 0.31.60: his own (Meshy) body
	if u.up and u.cls in ["rogue", "ranger", "mage"]:
		return {"rogue":"assassin", "ranger":"sniper", "mage":"archmage"}[u.cls]
	return u.cls

# ---------- Meshy characters (0.31.52, Kevin: a new Assassin model from Meshy) ----------
# A Meshy-generated, Meshy-rigged character stands in for a KayKit one. Its bones are renamed to the KayKit names (and
# hand slots added) so weapons, hats and the rest of the view find what they expect; its animations are the game's
# KayKit animations baked onto its own skeleton by tools/retarget_meshy.gd (anims_<library>.res, same names), and
# rig.json carries the fit scale and the hand-slot rests the tool worked out.
const MESHY := {"assassin": "res://assets/meshy/assassin/", "archmage": "res://assets/meshy/archmage/", "crusader": "res://assets/meshy/crusader/",
	"berserker": "res://assets/meshy/berserker/", "sniper": "res://assets/meshy/sniper/",
	"necromancer": "res://assets/meshy/necromancer/", "worker": "res://assets/meshy/worker/",
	"knight": "res://assets/meshy/knight/", "barbarian": "res://assets/meshy/barbarian/", "rogue": "res://assets/meshy/rogue/",
	"ranger": "res://assets/meshy/ranger/", "mage": "res://assets/meshy/mage/", "priest": "res://assets/meshy/priest/",
	# 5v5 lane minions (Kevin picked the A1 concepts: the King's levy)
	"minion_melee": "res://assets/meshy/minion_melee/", "minion_caster": "res://assets/meshy/minion_caster/",
	"minion_siege": "res://assets/meshy/minion_siege/", "minion_super": "res://assets/meshy/minion_super/",
	# 0.31.168: the six new 5v5 heroes
	"golem": "res://assets/meshy/golem/", "dragoon": "res://assets/meshy/dragoon/", "duelist": "res://assets/meshy/duelist/",
	"stormcaller": "res://assets/meshy/stormcaller/", "musketeer": "res://assets/meshy/musketeer/", "druid": "res://assets/meshy/druid/"}
const MESHY_RENAME := {"Hips":"hips", "Spine02":"spine", "Spine":"chest", "Head":"head",
	"LeftArm":"upperarm.l", "LeftForeArm":"lowerarm.l", "LeftHand":"wrist.l",
	"RightArm":"upperarm.r", "RightForeArm":"lowerarm.r", "RightHand":"wrist.r",
	"LeftUpLeg":"upperleg.l", "LeftLeg":"lowerleg.l", "LeftFoot":"foot.l", "LeftToeBase":"toes.l",
	"RightUpLeg":"upperleg.r", "RightLeg":"lowerleg.r", "RightFoot":"foot.r", "RightToeBase":"toes.r"}
static var _meshy_libs := {}
static var _meshy_rig := {}

static func meshy_rig(name: String) -> Dictionary:
	if not _meshy_rig.has(name):
		var f := FileAccess.open(str(MESHY[name]) + "rig.json", FileAccess.READ)
		_meshy_rig[name] = JSON.parse_string(f.get_as_text()) if f != null else {}
	return _meshy_rig[name]

static func _xf(a: Array) -> Transform3D:
	return Transform3D(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8]), Vector3(a[9], a[10], a[11]))

static func meshy_body(name: String) -> Dictionary:
	var packed := Stage.scene(str(MESHY[name]) + "rigged.glb")
	if packed == null:
		return {}
	var body: Node3D = packed.instantiate()
	for ap in body.find_children("*", "AnimationPlayer", true, false):
		ap.free()                                   # Meshy's own sample player
	var sk: Skeleton3D = body.find_child("Skeleton3D", true, false)
	for i in sk.get_bone_count():
		if MESHY_RENAME.has(sk.get_bone_name(i)):
			sk.set_bone_name(i, MESHY_RENAME[sk.get_bone_name(i)])
	var skins: Array = []
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var skin: Skin = (mi as MeshInstance3D).skin
		if skin != null:
			skin = skin.duplicate()                               # per body: we rename and rescale it
			(mi as MeshInstance3D).skin = skin
			skins.append(skin)
			for b in skin.get_bind_count():                       # the skin binds bones by name: rename them too
				if MESHY_RENAME.has(str(skin.get_bind_name(b))):
					skin.set_bind_name(b, MESHY_RENAME[str(skin.get_bind_name(b))])
	var rig: Dictionary = meshy_rig(name)
	for hand in ["r", "l"]:
		if rig.has("slot_" + hand) and sk.find_bone("handslot." + hand) < 0:
			var bi := sk.get_bone_count()
			sk.add_bone("handslot." + hand)
			sk.set_bone_parent(bi, sk.find_bone("wrist." + hand))
			sk.set_bone_rest(bi, _xf(rig["slot_" + hand]))
	sk.reset_bone_poses()
	# 0.31.53: put the rig in metres at scale 1 (Meshy rigs are centimetres under a 0.01 Armature; with the fit to the
	# KayKit height on top) -- the ragdoll's physics bodies can't live under a scaled skeleton. Every bone rest's offset
	# and every skin bind is scaled by the same factor, then the nodes' scales are reset: the mesh draws exactly as before.
	var a := float(rig.get("fit", 1.0))
	var n: Node = sk
	while n != null and n != body:
		if n is Node3D:
			a *= (n as Node3D).scale.x
			(n as Node3D).scale = Vector3.ONE
		n = n.get_parent()
	for i in sk.get_bone_count():
		var r := sk.get_bone_rest(i)
		sk.set_bone_rest(i, Transform3D(r.basis, r.origin * a))
	var S := Transform3D(Basis.from_scale(Vector3.ONE * a), Vector3.ZERO)
	for skin in skins:
		for b in (skin as Skin).get_bind_count():
			(skin as Skin).set_bind_pose(b, S * (skin as Skin).get_bind_pose(b))
	sk.reset_bone_poses()
	body.set_meta("meshy", name)
	return {"body":body, "skeleton":sk, "chain":1.0}

# 0.31.192 (Kevin: "add glow/smoky effects to the necromancers eyes"): a body's eyes glow and smoke (eye_fx.gd). pts:
# each eye's middle on the mesh, in the rigged GLB's own space (found from the texels of the Necromancer's painted green
# eyes, set a hair in front of the face); col: the glow's colour, per outfit -- his own lime green, the Frostbound's
# ice, the Gravekeeper's lantern green.
const EYE_FX := {"meshy:necromancer": {"pts": [Vector3(0.057, 0.7185, 0.153), Vector3(-0.057, 0.7185, 0.153)],
	"col": "#9dff5a", "skins": {"necromancer_frost": "#86ecff", "necromancer_gravekeeper": "#7dff9a"}}}

static func _eyes(body: Node3D, skeleton: Skeleton3D, model: String, skin: String, lite: bool) -> void:
	var e: Dictionary = EYE_FX.get(model, {})
	if e.is_empty() or skeleton.find_bone("head") < 0:
		return
	var sk: Skin = null
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).skin != null:
			sk = (mi as MeshInstance3D).skin
			break
	if sk == null:
		return
	var bind := -1
	for b in sk.get_bind_count():
		if str(sk.get_bind_name(b)) == "head" or (str(sk.get_bind_name(b)) == "" and sk.get_bind_bone(b) == skeleton.find_bone("head")):
			bind = b
	if bind < 0:
		return
	var att := BoneAttachment3D.new()
	att.name = "Eyes"
	att.bone_name = "head"
	skeleton.add_child(att)
	var fx: Node3D = EyeFx.new()
	fx.name = "EyeFx"
	fx.col = Color(str((e.get("skins", {}) as Dictionary).get(skin, e.col)))
	fx.lite = lite
	var bp := sk.get_bind_pose(bind)
	for p in e.pts:
		fx.pts.append(bp * (p as Vector3))                          # the eye where the skin puts that vertex
	fx.up = bp.basis * Vector3.UP                                   # (the GLB's +Y up, +Z the face's front)
	fx.fwd = bp.basis * Vector3.BACK
	att.add_child(fx)

static func meshy_libraries(name: String) -> Dictionary:
	if not _meshy_libs.has(name):
		var libs := {}
		for key in ["g", "m", "r", "mb", "ma"]:
			var path := str(MESHY[name]) + "anims_%s.res" % key
			var lib := Stage.res(path)
			if lib != null:
				libs[key] = lib
		_meshy_libs[name] = libs
	return _meshy_libs[name]

static func make_body(cls: String, cosmetic: Dictionary = {}) -> Dictionary:
	var look: Dictionary = (LOOKS.get(cls, LOOKS.knight) as Dictionary).duplicate()
	# 0.31.188: an outfit brings its own weapon (Eco.SKINS "weapon": {"r", "l"}), or his own repainted ("weapon_tex")
	var outfit: Dictionary = Eco.SKINS.get(str(cosmetic.get("skin", "")), {})
	var owpn: Dictionary = outfit.get("weapon", {})
	for hand in ["r", "l"]:
		if owpn.has(hand):
			look[hand] = owpn[hand]
		if cosmetic.has(hand):
			look[hand] = cosmetic[hand]                # (an explicit hand wins: the portraits' busts hold nothing)
	if str(look.model) == "prop:wyrm":
		return WyrmBody.make(Stage.scene(WyrmBody.MODEL), _cast_static)
	if str(look.model) in ["Knight", "meshy:knight", "meshy:crusader"] and str(look.l) == "":
		look.l = "bits/shield_B"            # 0.31.41 (Kevin): a Knight (and a Crusader) always carries a shield
	var meshy := str(look.model).begins_with("meshy:")
	var body: Node3D
	var skeleton: Skeleton3D
	var chain := 1.0
	if meshy:
		var mb := meshy_body(str(look.model).substr(6))
		if mb.is_empty():
			return {}
		body = mb.body
		skeleton = mb.skeleton
		chain = float(mb.chain)
		if str(cosmetic.get("skin", "")) != "":
			apply_skin(body, str(cosmetic.skin))        # 0.31.186: before the weapons go in his hands (they keep theirs)
	else:
		var packed := Stage.scene("res://assets/kaykit/heroes/%s.glb" % look.model)
		if packed == null:
			return {}
		body = packed.instantiate()
		skeleton = body.find_child("Skeleton3D", true, false)
		var rig := body.get_node_or_null("Rig")
		if rig != null and body.get_node_or_null("Rig_Medium") == null:
			rig.name = "Rig_Medium"            # 0.31.157: a Skeletons 1.0 body -- the libraries' tracks name the rig so
	var staffs: Array = []
	var hand_models: Array = []           # [model, hand, the KayKit file it is held like]
	if skeleton != null:
		for hand in ["r","l"]:
			var file := str(look.get(hand, ""))
			if file.is_empty():
				continue
			var slot := BoneAttachment3D.new()
			slot.bone_name = "handslot.%s" % hand
			skeleton.add_child(slot)
			# "bits/<name>" = KayKit Fantasy Weapons Bits (Round 11): larger models, scaled down.
			# "mw/<name>" = an Armory Reforged Meshy weapon (0.31.93): placed in the space of the KayKit model it replaced,
			# so it is held like that one (MESHY_WEAPON_LIKE).
			var fit_as := weapon_template(file)
			var weapon := Stage.scene(weapon_path(file))
			if weapon != null:
				var model: Node3D = weapon.instantiate()
				if str(outfit.get("weapon_tex", "")) != "":
					apply_weapon_skin(model, file, str(outfit.weapon_tex))     # 0.31.188: his own weapon, repainted
				_fit_weapon(model, fit_as, str(look.model), hand)
				hand_models.append([model, hand, fit_as])
				if is_staff(fit_as):
					staffs.append([model, fit_as, hand])
				if meshy:
					var holder := Node3D.new()         # undo the rig's centimetre scale: weapons keep their size
					holder.scale = Vector3.ONE / chain
					holder.add_child(model)
					slot.add_child(holder)
				else:
					slot.add_child(model)
	var player := AnimationPlayer.new()
	body.add_child(player)
	player.root_node = NodePath("..")
	var libs: Dictionary = meshy_libraries(str(look.model).substr(6)) if meshy else libraries()
	for key in libs:
		player.add_animation_library(key, libs[key])
	for st in staffs:
		_face_staff(st[0], str(st[1]), str(st[2]), skeleton, libs, str(look.idle), str(look.model))
	for hm in hand_models:                                       # 0.31.100: a signature weapon's own effects (0.31.188: an outfit's)
		var hf := str(look.get(str(hm[1]), ""))
		if WeaponFx.wants(hf):
			WeaponFx.apply(hm[0], hf, str(hm[1]) == "r" or hand_models.size() == 1, str(hm[2]), bool(cosmetic.get("lite", false)))
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _cast_static else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	if meshy and EYE_FX.has(str(look.model)):
		_eyes(body, skeleton, str(look.model), str(cosmetic.get("skin", "")), bool(cosmetic.get("lite", false)))
	if not cosmetic.has("tint") and look.has("tint"):
		cosmetic = cosmetic.duplicate()
		cosmetic["tint"] = look.tint
	if cosmetic.has("tint") and not meshy:                   # (a Meshy model is painted already)
		_apply_tint(body, str(look.model), Color(str(cosmetic.tint)))
	return {"body":body, "player":player}

# 0.31.186: a hero skin -- his own meshes painted with the skin's texture (Eco.skin_texture: the same UVs as his own,
# Meshy's retexture kept them). One material per skin and original material, shared by every body wearing it.
static var _skin_mats: Dictionary = {}

static func apply_skin(body: Node3D, skin: String) -> bool:
	var path := Eco.skin_texture(skin)
	if not ResourceLoader.exists(path):
		return false
	return _paint(body, load(path), skin)

# 0.31.188: an outfit's repainted weapon -- the piece's own meshes with the outfit's texture for it (Eco.skin_weapon_texture,
# Meshy's retexture of that piece with its UVs kept), one material per texture and original, shared
static func apply_weapon_skin(model: Node3D, file: String, key: String) -> bool:
	var path := Eco.skin_weapon_texture(file, key)
	if not ResourceLoader.exists(path):
		return false
	return _paint(model, load(path), path)

static func _paint(root: Node3D, tex: Texture2D, key0: String) -> bool:
	var done := false
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		if m3.mesh == null:
			continue
		for surf in m3.mesh.get_surface_count():
			var base := m3.get_active_material(surf)
			if not (base is BaseMaterial3D):
				continue
			var key := "%s|%d" % [key0, base.get_instance_id()]
			if not _skin_mats.has(key):
				var mat := (base as BaseMaterial3D).duplicate() as BaseMaterial3D
				mat.albedo_texture = tex
				_skin_mats[key] = mat
			m3.set_surface_override_material(surf, _skin_mats[key])
			done = true
	return done

# ---------- staffs: the face turns toward the body (0.31.66, Kevin) ----------
# 0.31.65 stood every staff upright; Kevin: "make the staffs held how it was before but just make the face of it face
# towards the body -- the skull, for example, faces the player model". So the hold is the old one again, and the staff
# is only turned about its own length until its face (STAFF_FACE, in the model's own space: the side the ornament
# looks out of) points at the holder's chest. Measured from the meshes' heads: the skull bulges out along -X
# (centroid x -0.24); the flat heads (staff, staff_B, staff_D) are wide in X and thin in Z, so they face +-Z; staff_A
# (a thin knotted rod) and staff_C (round all the way round) have no face and are left alone. Worked out from the
# pose, not by eye: the idle animation's frame 0 is applied down the bone chain to the hand slot and to the chest
# (each bone's rest overridden by its tracks), and the roll about the staff's +Y that points the face at the chest,
# across the staff, is computed per body, idle and hand. Wands and every other weapon are unchanged.
const STAFF_FACE := {"Skeleton_Staff": Vector3(-1, 0, 0), "staff": Vector3(0, 0, 1), "bits/staff_B": Vector3(0, 0, 1),
	"bits/staff_D": Vector3(0, 0, 1)}
static var _staff_pose := {}

static func is_staff(file: String) -> bool:
	return STAFF_FACE.has(file)

static func _pose_tracks(anim: Animation) -> Dictionary:
	# bone name -> {"p": track, "r": track, "s": track} for an animation's 3D transform tracks
	var out := {}
	for i in anim.get_track_count():
		var tp := anim.track_get_path(i)
		if tp.get_subname_count() == 0:
			continue
		var bn := str(tp.get_subname(0))
		var e: Dictionary = out.get(bn, {})
		match anim.track_get_type(i):
			Animation.TYPE_POSITION_3D: e["p"] = i
			Animation.TYPE_ROTATION_3D: e["r"] = i
			Animation.TYPE_SCALE_3D: e["s"] = i
		out[bn] = e
	return out

static func _posed_bone(sk: Skeleton3D, anim: Animation, tracks: Dictionary, bone: int) -> Transform3D:
	# a bone's skeleton-space transform in the animation's frame 0
	var bones: Array = []
	while bone >= 0:
		bones.push_front(bone)
		bone = sk.get_bone_parent(bone)
	var g := Transform3D.IDENTITY
	for b in bones:
		var rest := sk.get_bone_rest(b)
		var pos := rest.origin
		var rot := rest.basis.get_rotation_quaternion()
		var scl := rest.basis.get_scale()
		var tr: Dictionary = tracks.get(sk.get_bone_name(b), {})
		if tr.has("p"):
			pos = anim.position_track_interpolate(int(tr.p), 0.0)
		if tr.has("r"):
			rot = anim.rotation_track_interpolate(int(tr.r), 0.0)
		if tr.has("s"):
			scl = anim.scale_track_interpolate(int(tr.s), 0.0)
		g = g * Transform3D(Basis(rot) * Basis.from_scale(scl), pos)
	return g

static func _face_staff(model: Node3D, file: String, hand: String, sk: Skeleton3D, libs: Dictionary, idle: String, body_key: String) -> void:
	var key := "%s|%s|%s" % [body_key, idle, hand]
	if not _staff_pose.has(key):
		var parts := idle.split("/")
		var lib: AnimationLibrary = libs.get(parts[0]) if parts.size() == 2 else null
		var anim: Animation = lib.get_animation(parts[1]) if lib != null and lib.has_animation(parts[1]) else null
		var si := sk.find_bone("handslot." + hand)
		var ci := sk.find_bone("chest")
		if ci < 0:
			ci = sk.find_bone("hips")
		if anim == null or si < 0 or ci < 0:
			_staff_pose[key] = []
		else:
			var tracks := _pose_tracks(anim)
			_staff_pose[key] = [_posed_bone(sk, anim, tracks, si), _posed_bone(sk, anim, tracks, ci).origin]
	var pose: Array = _staff_pose[key]
	if pose.is_empty():
		return
	var slot: Transform3D = pose[0]
	var chest: Vector3 = pose[1]
	var top := 0.0                                         # the head: the top of the staff along its +Y
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		top = maxf(top, (m3.transform * m3.get_aabb()).end.y)
	var to_skel := slot.basis * model.basis                # model space -> skeleton space
	var axis := (to_skel * Vector3.UP).normalized()
	var head := slot.origin + to_skel * Vector3(0, top * 0.85, 0)
	var d := chest - head
	d -= axis * d.dot(axis)                                # across the staff only
	if d.length() < 0.001:
		return
	var dm := to_skel.inverse() * d                        # in the model's own space
	var face: Vector3 = STAFF_FACE[file]
	model.rotate_object_local(Vector3.UP, atan2(dm.x, dm.z) - atan2(face.x, face.z))

# 0.31.43 (Kevin: weapons upside down / wrongly sized -- "staffs shouldn't be super short"). Measured: the Bits pack uses
# the SAME convention and scale as the Adventurers weapons (grip at the origin, business end along +Y: sword_A 1.77 m
# vs sword_1handed 1.78, staff_A 2.15 vs staff 2.15), so the old flat 0.55 on every Bits model made them all small --
# a staff came out 1.2 m. Bits models now keep their size, with a few of the giants brought down to the Adventurers'
# two-handers (sword_E 3.25 -> 2.4; spears, the big bows, staff_D, the halberd), and shields a little larger than life
# so a Knight's is obvious. Bows: the Adventurers bow lies along Z and wants a half turn; the Bits bows lie along X and
# want a quarter turn -- 0.31.104 (Kevin's Hawkeye screenshot: "A lot of the weapons are still not gripped correctly"):
# the OTHER way round. The quarter turn the same way as the half turn left every Bits bow's string on the far side, away
# from the archer (Hawkeye, Stag Hunter, Galeshot, Longshot, Heartseeker); tests/weapon_grip_test.gd measures it.
const WEAPON_SCALE := {"bits/sword_E":0.75, "bits/spear_A":0.8, "bits/spear_B":0.8, "bits/bow_C_withString":0.75, "bits/staff_D":0.85,
	"bits/halberd":0.85, "bits/shield_D":0.78, "bits/shield_C":0.85, "bits/shield_B":0.9, "bits/shield_A":1.0, "bits/sword_F":0.9, "bits/hammer_D":0.9,
	"Skeleton_Axe":0.85, "Skeleton_Shield_Large_A":0.8}      # (0.31.157: the jungle's skeletons)

# 0.31.44 (Kevin's screenshots): crossbows stood up like bows -- they lie forward (a quarter turn about X); shields sat
# on the hand so the fist poked through the face -- they move out along the slot's Z so the hand is behind the board;
# the clawed knuckles faced backwards (half turn); the single-bladed cleaver's edge pointed up in the two-handed grip
# (half turn); the Twin Axes were two axes in a two-handed grip (now one double-bitted axe, in economy.gd).
const WEAPON_ROT := {"bits/fistweapon_C_left":Vector3(0, 180, 0), "bits/fistweapon_C_right":Vector3(0, 180, 0)}
# 0.31.46 (side-view renders): in the Knight's one-handed idle the hand holds the weapon's long axis horizontal, so a
# halberd lay flat; a quarter turn about Z stands it upright, head up. The Rogue's idle does the same to the scythe
# (blade up, grim-reaper style). Crossbows lie forward with a quarter turn about X -- opposite signs for the two hands
# (0.31.45's right-hand crossbows pointed backwards).
# 0.31.47 (Kevin: back the 90 degrees, and the blade turned 180): the hold he called "right way but backwards" in
# 0.31.45 -- lying along the arm, axe blade / scythe blade hanging down -- but with the head forward: a half roll about
# the weapon's own long axis instead of the half turn about Z (which also swung the head behind him).
const WEAPON_ROT_FOR := {"Knight":{"bits/halberd":Vector3(0, 180, 0)}, "Rogue_Hooded":{"bits/scythe":Vector3(0, 180, 0)}, "Rogue":{"bits/scythe":Vector3(0, 180, 0)},
	"meshy:knight":{"bits/halberd":Vector3(0, 180, 0)}, "meshy:rogue":{"bits/scythe":Vector3(0, 180, 0)}}     # (0.31.80: same holds)

# 0.31.48 (Kevin: turn these blades 180): the one-handed axe (Worker, Axe & Ale, Axe & Buckler -- its edge faced back
# in the chop), the Great Cleaver and the Oathkeeper: a half roll about the weapon's own long axis.
static var WEAPON_ROLL_TEST := {}     # (tools only: try a roll without editing the table)
# 0.31.64 (Kevin): the Necromancer's staff skull faces the floor (it faced the sky: worked out from the pose -- the
# skull sits on the model's -X side, and a 195-degree roll points that straight down in the idle); the open
# spellbook's pages face whoever holds it (cover outward).
const WEAPON_ROLL := {"axe_1handed":180.0, "bits/axe_D":180.0, "bits/sword_G":180.0, "spellbook_open":180.0}       # (Skeleton_Staff: see _face_staff, 0.31.66)

# ---------- Armory Reforged (0.31.93, Kevin: "redo all the weapon models ... more unique and badass") ----------
# Meshy models made from the approved concept sheets by tools/meshy_weapon.py: each piece is fitted offline into the
# space of the KayKit model it replaces (same length / face area, grip and facing), so the hand slots, fits, rolls and
# staff turns tuned for that model apply unchanged. id -> the KayKit file it stands in for. 0.31.94: every class (a
# piece drawn upright is first turned onto the template's axes where that lies along Z or X -- bows, crossbows, claws;
# a left-hand claw is the right one mirrored).
const MESHY_WEAPON_LIKE := {
	# (0.31.188, Kevin: "Remove the forge and the individual weapon skins": the catalog's weapons and the quests'
	# legendaries are gone, models and all -- 0.31.93-0.31.187 in git history)
	# 0.31.188: the outfits' own weapons (economy.gd OUTFITS) -- each held like its hero's own (tools/meshy_weapon.py fit)
	"lion_sword": "sword_1handed", "lion_shield": "bits/shield_B", "mammoth_axe": "axe_2handed",
	"coin_dagger": "dagger", "orchard_bow": "bow_withString", "phoenix_staff": "staff", "bell_scepter": "wand",
	"ember_hammer": "bits/hammer_C", "ashen_shield": "bits/shield_B", "bloodmoon_greatsword": "bits/sword_E",
	"ribbon_dagger": "dagger", "wolf_crossbow": "crossbow_2handed", "orrery_staff": "staff",
	"starchart_tome": "spellbook_open", "lantern_shovel": "staff", "geode_hammer": "bits/hammer_C",
	"geode_shield": "bits/shield_A", "dragon_halberd": "bits/halberd", "rose_rapier": "sword_1handed",
	"thorn_stiletto": "bits/dagger_A", "lightning_rod_staff": "staff", "brass_blunderbuss": "crossbow_2handed",
	"blossom_staff": "staff",
	# 0.31.168: the six new 5v5 heroes' props (not cosmetics)
	"golem_hammer": "bits/hammer_C", "golem_shield": "bits/shield_A", "dragoon_halberd": "bits/halberd",
	"duelist_rapier": "sword_1handed", "needlepoint_stiletto": "bits/dagger_A", "storm_staff": "staff",
	"druid_staff": "staff", "musket": "crossbow_2handed",
	# 0.31.159: the 5v5 lane minions' props (not cosmetics)
	"minion_sword": "sword_1handed", "minion_buckler": "shield_round", "minion_crossbow": "crossbow_1handed",
	"minion_cannon": "crossbow_2handed", "minion_hammer": "axe_2handed",
	# each class's own (siege_view LOOKS; 0.31.93 Armory Reforged)
	"squire_sword": "sword_1handed", "squire_shield": "bits/shield_B", "woodsplitter_axe": "axe_2handed",
	"cutpurse_dagger": "dagger", "ashwood_bow": "bow_withString", "apprentice_staff": "staff", "acolyte_wand": "wand",
	"work_hatchet": "axe_1handed", "templar_sword": "sword_1handed", "templar_shield": "bits/shield_B",
	"ironhewer_greatsword": "bits/sword_E", "bonecaller_staff": "Skeleton_Staff", "shade_dagger": "dagger",
	"marksman_crossbow": "crossbow_2handed", "magister_staff": "staff", "magister_book": "spellbook_open"
}

static func weapon_path(file: String) -> String:
	if file.begins_with("mw/"):
		return "res://assets/meshy/weapons/%s.glb" % file.substr(3)
	if file.begins_with("bits/"):
		return "res://assets/kaykit/bits/%s.gltf" % file.substr(5)
	return "res://assets/kaykit/weapons/%s.gltf" % file

static func weapon_template(file: String) -> String:
	# the KayKit file whose hold a weapon file uses (itself, for a KayKit file)
	return str(MESHY_WEAPON_LIKE.get(file.substr(3), file)) if file.begins_with("mw/") else file

static func _model_box(model: Node3D) -> AABB:
	return WeaponFx.box_of(model)

static func _fit_weapon(model: Node3D, file: String, body_model := "", hand := "r") -> void:
	model.scale = Vector3.ONE * float(WEAPON_SCALE.get(file, 1.0))
	if file.contains("crossbow"):
		model.rotation.x = deg_to_rad(-90.0 if hand == "r" else 90.0)
		if hand == "r":
			# 0.31.190 (Kevin: "Now some of weapons are upside down like the musketeer weapons"): 0.31.46's -90 turned the
			# right hand's crossbows forward but also upside down (the stock's drop and the trigger on top, a gun's lock
			# underneath) -- a half roll about the piece's own length puts them upright, still pointing forward
			model.rotate_object_local(Vector3.BACK, PI)
	elif file.contains("bow"):
		model.rotation.y = -PI * 0.5 if file.begins_with("bits/") else PI
	if WEAPON_ROT.has(file):
		var r: Vector3 = WEAPON_ROT[file]
		model.rotation = Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z))
	var per: Dictionary = WEAPON_ROT_FOR.get(body_model, {})
	if per.has(file):
		var pr: Vector3 = per[file]
		model.rotation = Vector3(deg_to_rad(pr.x), deg_to_rad(pr.y), deg_to_rad(pr.z))
	if WEAPON_ROLL_TEST.has(file):
		model.rotate_object_local(Vector3.UP, deg_to_rad(float(WEAPON_ROLL_TEST[file])))
	elif WEAPON_ROLL.has(file):
		model.rotate_object_local(Vector3.UP, deg_to_rad(float(WEAPON_ROLL[file])))
	if file.contains("shield"):
		model.position = Vector3(0.0, 0.0, 0.14 if file.begins_with("bits/") else 0.15)

static func _apply_tint(body: Node3D, model: String, tint: Color) -> void:
	# A skin = the model's own material with its albedo multiplied by the tint. Made once per
	# (model, surface, tint) and cached; set once when the body is built, never per frame.
	var skel: Skeleton3D = body.find_child("Skeleton3D", true, false)
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		if skel != null and not skel.is_ancestor_of(m3):
			continue
		var under_hand := false
		var n: Node = m3.get_parent()
		while n != null and n != body:
			if n is BoneAttachment3D:
				under_hand = true
				break
			n = n.get_parent()
		if under_hand:
			continue                       # weapons keep their own colours
		for surf in m3.mesh.get_surface_count():
			var base := m3.get_active_material(surf)
			if not (base is StandardMaterial3D):
				continue
			var key := "%s|%s|%d|%s" % [model, m3.name, surf, tint.to_html()]
			if not _tint_mats.has(key):
				var m2: StandardMaterial3D = (base as StandardMaterial3D).duplicate()
				m2.albedo_color = (base as StandardMaterial3D).albedo_color * tint
				_tint_mats[key] = m2
			m3.set_surface_override_material(surf, _tint_mats[key])

static var _red_mats := {}

static func _team_red(body: Node) -> void:
	# 0.31.159: a body (and what it holds) painted in the blue team's colours, in the red team's: each texture's
	# <name>_red.jpg beside it (tools/team_red_tex.py) on a copy of its material -- the same shader, so nothing new to
	# compile mid-match; textures without a red copy (steel, wood) stay as they are
	for m3 in body.find_children("*", "MeshInstance3D", true, false):
		var mi := m3 as MeshInstance3D
		if mi.mesh == null:
			continue
		for surf in mi.mesh.get_surface_count():
			var base := mi.get_active_material(surf) as StandardMaterial3D
			if base == null or base.albedo_texture == null:
				continue
			var path := base.albedo_texture.resource_path
			if not _red_mats.has(path):
				var red := path.get_basename() + "_red.jpg"
				var m2: StandardMaterial3D = null
				if path != "" and ResourceLoader.exists(red):
					m2 = base.duplicate()
					m2.albedo_texture = Stage.texture(red)
				_red_mats[path] = m2
			if _red_mats[path] != null:
				mi.set_surface_override_material(surf, _red_mats[path])

# 0.31.128 (Kevin: "make the base class models the same size as the advanced class"): every body at the upgraded
# classes' 1.14 (the base classes were 1.0); an upgraded one still shows by its own model and its gold ring.
const BODY_SCALE := 1.14

# 0.31.207 (Kevin: "The match keeps getting stutters"): a wave of 36 lane minions was 36 bodies built in one frame --
# the phone's log had a 100-350 ms frame every half minute (tools/hitch_bench.gd: +504 nodes in the frame the first wave
# came). Now a minion's actor, when its minion goes, waits hidden in a pool (by body and team) for the next one; the
# match's loading card fills the pool with a wave's worth (prefill_minions); and any other body still to build waits
# its turn -- BUILD_PER_FRAME a frame (heroes never wait).
const MINION_POOL_MAX := 30                     # (each body and team)
const BUILD_PER_FRAME := 3
var _minion_pool := {}                    # "minion_melee|0" -> [actor, ...]
var _built_now := 0                       # bodies built this frame
var pool_reused := 0                      # (tests, the bench)
var _prefilling := false
var pool_built := 0

func _pool_key(u: Dictionary) -> String:
	if not bool(u.get("minion", false)) or not MINION_LOOKS.has(str(u.get("mk", ""))) or u.has("look"):
		return ""
	return "%s|%d" % [look_key(u), vt(int(u.team))]

func _pool_put(a: Dictionary) -> bool:
	# a minion's actor, its minion gone: hidden, its animation still, kept for the next of its kind and side
	var k := str(a.get("pool_key", ""))
	if k == "" or not is_instance_valid(a.root) or a.get("body") == null or not is_instance_valid(a.body) or bool(a.get("vanish_on", false)):
		return false
	var list: Array = _minion_pool.get(k, [])
	if list.size() >= MINION_POOL_MAX:
		return false
	if a.get("rag") != null:
		_ragdoll_end(a)                           # (its bones back to the animation)
	(a.root as Node3D).visible = false
	if is_instance_valid(a.player):
		(a.player as AnimationPlayer).active = false
	list.append(a)
	_minion_pool[k] = list
	return true

func _pool_take(k: String, u: Dictionary) -> Dictionary:
	var list: Array = _minion_pool.get(k, [])
	if list.is_empty():
		return {}
	var a: Dictionary = list.pop_back()
	var root: Node3D = a.root
	var p := Vector3(u.pos.x, Sim.height_at(u.pos), u.pos.y)
	root.position = p
	root.rotation = Vector3(0.0, float(u.get("face", 0.0)), 0.0)
	root.visible = true
	for kk in ["snap", "gp", "gy", "fog_vis", "whirl_spin", "kick_last", "hit_flip"]:
		a.erase(kk)
	a["snap"] = true
	a.last = p
	a.dead = false
	a.busy_until = 0.0
	a.clip = ""
	a.team = u.team
	a.cls = u.cls
	a.up = u.up
	# what flew out of his hands when he fell (copies) -- his own back in them
	for slot in (a.body as Node3D).find_children("*", "BoneAttachment3D", true, false):
		if str((slot as BoneAttachment3D).bone_name).begins_with("handslot"):
			for w in (slot as Node).get_children():
				if w is Node3D:
					(w as Node3D).visible = true
	(a.ring as MeshInstance3D).visible = true
	if is_instance_valid(a.player):
		(a.player as AnimationPlayer).active = true
	_play(a, str(LOOKS.get(str(a.mlook) if str(a.get("mlook", "")) != "" else u.cls, LOOKS.knight).idle))
	pool_reused += 1
	return a

func prefill_minions(per_lane: Dictionary, lanes := 3) -> Array:
	# the match's loading card: bodies for a wave's minions on each side, hidden in the pool (a job a body, to spread
	# them over the card's frames) -> [Callable, ...]
	var jobs := []
	for t in 2:
		for mk in per_lane:
			for i in int(per_lane[mk]) * lanes:
				var team: int = t
				var kind: String = mk
				jobs.append(func():
					var u := {"id":"__pool_%d_%s_%d" % [team, kind, i], "cls":"knight", "up":false, "minion":true, "mk":kind, "team":team,
						"pos":Vector2(0.0, 300.0), "face":0.0, "state":"idle", "hp":1.0, "max_hp":1.0}
					var k := _pool_key(u)
					if k == "" or (_minion_pool.get(k, []) as Array).size() >= int(per_lane[kind]) * lanes:
						return
					var was := _built_now
					_built_now = 0                # (the card's own budget: not the frame's)
					_prefilling = true            # (a new body, not one from the pool)
					var a := _ensure_actor(u)
					_prefilling = false
					_built_now = was
					actors.erase(u.id)
					if a.is_empty():
						return
					if not _pool_put(a):
						(a.root as Node).queue_free()
					elif (_minion_pool[k] as Array).size() == 1:
						_warm_show(a))           # (the first of each kind and side: drawn once, beside you)
	return jobs

func pool_size() -> int:
	var n := 0
	for k in _minion_pool:
		n += (_minion_pool[k] as Array).size()
	return n

var _pool_shown: Array = []               # the pooled bodies shown on the loading card (warm_end hides them)

func _warm_show(a: Dictionary) -> void:
	var me: Dictionary = actors.get(player_id, {})
	if me.is_empty() or not is_instance_valid(me.root):
		return
	var root: Node3D = a.root
	root.position = (me.root as Node3D).position + Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-3.0, 3.0))
	root.visible = true
	if is_instance_valid(a.player):
		(a.player as AnimationPlayer).active = true
	_pool_shown.append(a)

func warm_fight() -> Array:
	# the loading card: a fight's own looks once beside you -- a hit's spark, number and blood, a pool of it, a body
	# falling and its weapons flying (the first of each drew late on the phone)
	var jobs := []
	jobs.append(func():
		var me: Dictionary = actors.get(player_id, {})
		if me.is_empty() or not is_instance_valid(me.root):
			return
		var at: Vector3 = (me.root as Node3D).position
		var p2 := Vector2(at.x, at.z)
		spark(at + Vector3(0, 1.3, 0), Color("#ffd27a"))
		number(at + Vector3(0, 2.2, 0), "12", false)
		number(at + Vector3(0.6, 2.2, 0), "12", true)
		number(at + Vector3(-0.6, 2.2, 0), "+12", false, true)
		blood_hit(p2 + Vector2(1.5, 0.0), p2, 40.0)
		blood_pool(p2 + Vector2(2.0, 1.0)))
	jobs.append(func():
		for a in _pool_shown:
			if is_instance_valid(a.root) and (a.root as Node3D).visible and a.get("rag") == null:
				_drop_weapons(a, Vector3(0.0, 1.6, 0.0))
				_ragdoll(a, Vector3(0.0, 1.6, 0.0))
				return)
	return jobs

func warm_end() -> void:
	# the loading card lifts: what it showed, gone (the bodies back in the pool, hidden; blood and loose weapons away)
	for a in _pool_shown:
		var k := str(a.get("pool_key", ""))
		if not (_minion_pool.get(k, []) as Array).has(a) or not is_instance_valid(a.root):
			continue                                   # (already taken for a minion)
		if a.get("rag") != null:
			_ragdoll_end(a)
		(a.root as Node3D).visible = false
		if is_instance_valid(a.player):
			(a.player as AnimationPlayer).active = false
	_pool_shown.clear()
	for d in _debris:
		if is_instance_valid(d.node):
			(d.node as Node).queue_free()
		if is_instance_valid(d.ground):
			(d.ground as Node).queue_free()
	_debris.clear()
	for list in [_splats, _pools]:
		for m in list:
			(m.mi as MeshInstance3D).visible = false
	for d in _drops:
		d.on = false
		(d.mi as MeshInstance3D).visible = false
	for sh in _shocks:                             # (each shown again every frame it lasts)
		if is_instance_valid(sh.node):
			(sh.node as Node).queue_free()
	_shocks.clear()

const WARM_LOOKS := ["skel_minion", "skel_warrior", "skel_rogue", "skel_mage", "skel_brute", "skel_lord"]

func warm_bodies(me_id: String) -> Array:
	# the loading card: the jungle's monsters (they first come at 0:30, the Lord at 5:00) shown once beside you -- their
	# materials made and drawn -- then gone (a job a body)
	var jobs := []
	for look in WARM_LOOKS:
		var lk: String = look
		jobs.append(func():
			var a: Dictionary = actors.get(me_id, {})
			if not LOOKS.has(lk) or a.is_empty() or not is_instance_valid(a.root):
				return
			var made := make_body(lk)
			if made.is_empty():
				return
			var b: Node3D = made.body
			add_child(b)
			b.position = (a.root as Node3D).position + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
			b.scale = Vector3.ONE * BODY_SCALE
			get_tree().create_timer(2.0).timeout.connect(b.queue_free))
	return jobs

func _ensure_actor(u: Dictionary) -> Dictionary:
	var a: Dictionary = actors.get(u.id, {})
	# The usual case first, without building keys: the actor exists and wears this class (0.31.78: this ran for every
	# unit every frame, formatting a string -- with the player's cosmetics dictionary in it -- 32 times a frame).
	if not a.is_empty() and a.cls == u.cls and a.up == u.up and str(a.get("lk", "")) == str(u.get("look", "")) \
			and ((u.id != player_id and a.cosmetic.is_empty() and not unit_skins.has(u.id)) or a.cosmetic == unit_cosmetic(u)):
		return a                                    # (0.31.170: and the same body -- online a player's hero takes a bot's seat)
	# 0.31.38: an upgraded class wears its own cosmetics (the Crusader's, the Berserker's...), not the base class's.
	# 0.31.101: every live player's, not only mine (unit_cosmetic)
	var cosmetic: Dictionary = unit_cosmetic(u)
	if not a.is_empty() and u.state == "dead" and a.get("body") != null:
		return a                                    # 0.31.20: the body stays as it fell until he respawns
	var root: Node3D
	var pk := _pool_key(u) if cosmetic.is_empty() else ""
	if a.is_empty():
		if pk != "" and not _prefilling:
			var pa := _pool_take(pk, u)            # 0.31.207: a minion's body from the pool
			if not pa.is_empty():
				actors[u.id] = pa
				return pa
		if not bool(u.get("hero", false)) and _built_now >= BUILD_PER_FRAME:
			return {}                              # (0.31.207: its turn next frame)
		_built_now += 1
		pool_built += 1
		root = Node3D.new()
		add_child(root)
		root.position = Vector3(u.pos.x, 0, u.pos.y)
		var ring := MeshInstance3D.new()
		ring.mesh = _ring_mesh(0.62 if u.id == player_id else 0.5, 0.12)
		ring.scale = Vector3(1, 0.2, 1)
		var col: Color = GOLD if u.id == player_id else TEAM_COLORS[vt(int(u.team))]
		col.a = 0.9
		ring.material_override = _unshaded(col)
		ring.position.y = 0.05
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ring)
		# HP bars are drawn by the 2D HUD (as in the dice battle); no blob-shadow shader quads.
		a = {"root":root, "ring":ring, "body":null, "player":null, "clip":"", "busy_until":0.0, "dead":false, "last":root.position,
			"team":u.team, "cls":"", "up":false, "cosmetic":{}}
		actors[u.id] = a
	else:
		root = a.root
		if is_instance_valid(a.body):
			a.body.queue_free()
	var made := make_body(look_key(u), cosmetic)
	if made.is_empty():
		return a
	root.add_child(made.body)
	var minion_look := bool(u.get("minion", false)) and MINION_LOOKS.has(str(u.get("mk", "")))
	a["mlook"] = look_key(u) if u.has("look") or minion_look else ""     # 0.31.157: a monster's own clips (0.31.159: a minion's)
	if minion_look and vt(int(u.team)) == 1:
		_team_red(made.body)                    # 0.31.159: the minions are painted in the blue team's colours
	made.body.scale = Vector3.ONE * BODY_SCALE * (MINION_SCALE if bool(u.get("minion", false)) else 1.0) * float(u.get("mscale", 1.0))   # 0.31.157: big monsters; 0.31.128 (Kevin): every class the upgraded size (base was 1.0); 0.31.155: 5v5 minions smaller
	var look: Dictionary = LOOKS.get(look_key(u), {})
	if look.has("size"):
		made.body.scale = Vector3.ONE * float(look.size)     # 0.31.166: the Wyrm, at its own size
	a.body = made.body
	a.player = made.player
	a["pool_key"] = pk                            # (0.31.207: back to the pool when it goes)
	_cape_setup(a)
	a.cls = u.cls
	a.up = u.up
	a["lk"] = str(u.get("look", ""))
	a.cosmetic = cosmetic
	a.clip = ""
	a.busy_until = 0.0
	_play(a, str(LOOKS.get(str(a.mlook) if str(a.mlook) != "" else u.cls, LOOKS.knight).idle))
	a["big"] = float(look.get("ring", 0.0))                # (0.31.166: a body far wider than a man)
	if a.big > 0.0 and sim.alive(u) and (sim.moba == null or sim.moba.can_see(_my_team(), u)):
		_play(a, "w/Rise", 1.0, 1.6)                        # up out of its pit when it comes (seen)
	# Upgraded: a gold ring (no material overrides on skinned meshes; 0.31.128: no longer a bigger body too).
	var rc: Color = GOLD if (u.up or u.id == player_id) else TEAM_COLORS[vt(int(u.team))]
	rc.a = 0.9
	(a.ring as MeshInstance3D).material_override = _fx_mat(rc)
	(a.ring as MeshInstance3D).mesh = _ring_mesh(0.75 if u.up else (0.62 if u.id == player_id else 0.5), 0.14 if u.up else 0.12)
	if float(a.big) > 0.0:
		(a.ring as MeshInstance3D).mesh = _ring_mesh(float(a.big), 0.22)
	return a

func _play(a: Dictionary, clip: String, speed := 1.0, busy := 0.0) -> void:
	var player: AnimationPlayer = a.player
	if not is_instance_valid(player):
		return
	if not player.has_animation(clip):
		clip = "g/Idle_A"
	if busy > 0.0:
		a.busy_until = _time + busy
	if a.clip == clip and player.is_playing() and busy <= 0.0:
		player.speed_scale = speed
		return
	a.clip = clip
	player.play(clip, 0.1)
	player.speed_scale = speed

# Animation culling (0.14.3): characters outside the camera view don't run their AnimationPlayer
# (so no skeleton update or skinning upload either); they resume the moment they come into view.
var anim_cull := true
var anim_active := 0

func _on_screen(p: Vector3, planes: Array, r := 1.8) -> bool:
	# Bounding sphere (1.8 m; 0.31.166: a big body's own) against the camera frustum planes.
	var c := p + Vector3(0, 1.0, 0)
	for pl in planes:
		if (pl as Plane).distance_to(c) > r:
			return false
	return true

var prof_on := false                      # (tests/moba_bench.gd: microseconds per part of sync in prof)
var prof := {}

func _pv(key: String, t0: int) -> int:
	var now := Time.get_ticks_usec()
	prof[key] = int(prof.get(key, 0)) + (now - t0)
	return now

func sync(dt: float) -> void:
	var tp := Time.get_ticks_usec() if prof_on else 0
	_time += dt
	_sync_meteor_fx(dt)
	_sync_recall_fx(dt)
	if prof_on: tp = _pv("pre.meteors", tp)
	_sync_shocks()
	_kick_debris()
	if prof_on: tp = _pv("pre.shocks+debris", tp)
	_sync_ambience(dt)
	if prof_on: tp = _pv("pre.amb", tp)
	_sync_ripples(dt)
	if prof_on: tp = _pv("pre.ripples", tp)
	_sync_blood(dt)
	if prof_on: tp = _pv("pre.blood", tp)
	var seen := {}
	_built_now = 0                                 # 0.31.207: bodies built this frame (BUILD_PER_FRAME)
	var planes: Array = camera.get_frustum() if anim_cull and is_instance_valid(camera) and camera.is_inside_tree() else []
	anim_active = 0
	# 0.31.160 (Kevin's phone log: the 5v5's view 12-16 ms a frame): per actor, only what changed -- the ground height
	# looked up again only when the unit moved (Sim.height_at is ~6 us), the transform written only while it's still
	# easing in (snapped once within a millimetre / a fraction of a degree), and the hand, load, Vanish, animation and
	# cape left alone while the body isn't drawn (in the fog, or off the screen; the dead and the just-respawned
	# always). A body hidden in the fog isn't moved at all: it snaps to its place when it's seen again.
	var my_team := _my_team()
	var pos_k := 1.0 - exp(-dt * 22.0)
	var rot_k := 1.0 - exp(-dt * 18.0)
	for u in sim.units:
		seen[u.id] = true
		var tu := Time.get_ticks_usec() if prof_on else 0
		var a := _ensure_actor(u)
		if prof_on: tu = _pv("a.ensure", tu)
		if a.is_empty() or not is_instance_valid(a.root):
			continue
		var root: Node3D = a.root
		var alive_u: bool = sim.alive(u)
		if sim.moba != null:
			# 0.31.158 5V5 fog of war: an enemy (or a monster) your side can't see isn't drawn (one that falls in sight
			# stays shown where he fell)
			var fv: bool = int(u.team) == my_team or (alive_u and sim.moba.can_see(my_team, u)) \
				or (not alive_u and bool(a.get("fog_vis", false)))
			if alive_u:
				a["fog_vis"] = fv
			if root.visible != fv:
				root.visible = fv
				if fv:
					a["snap"] = true
			if not fv:
				if is_instance_valid(a.player) and (a.player as AnimationPlayer).active:
					(a.player as AnimationPlayer).active = false
				if prof_on: tu = _pv("a.place+fog", tu)
				continue
		var up: Vector2 = u.pos
		var gy: float
		if a.get("gp", Vector2.INF) == up:
			gy = float(a.gy)
		else:
			gy = Sim.height_at(up)
			a["gp"] = up
			a["gy"] = gy
		var target := Vector3(up.x, gy, up.y)
		if u.state == "dash" and u.has("dash") and bool(u.dash.get("leap", false)):
			# 0.31.168: a leap arcs (LEAP, VAULT, DRAGON DIVE): up and down over the dash, higher the longer it is
			var dd: Dictionary = u.dash
			var tot := maxf(0.5, float(dd.get("total", dd.left)))
			var k := clampf(1.0 - float(dd.left) / tot, 0.0, 1.0)
			target.y += sin(k * PI) * minf(4.5, 0.35 * tot)
		var before := root.position
		# Smooth between 30 Hz sim ticks; snap on respawn teleports (and coming out of the fog).
		var newp := target
		if bool(a.get("snap", false)):
			a.erase("snap")
		elif before.distance_squared_to(target) <= 36.0:
			newp = before.lerp(target, pos_k)
			if newp.distance_squared_to(target) < 0.000001:
				newp = target
		if newp != before:
			root.position = newp
		var vel := (newp - before).length() / maxf(dt, 0.001)
		if sim.whirling(u) and u.state != "dead":
			# 0.31.16 (Kevin: "the barbarian model should spin with the vfx"): he turns with his whirlwind -- the same way
			# round as its ribbons and nearly as fast (they turn at 44 and 34 rad/s; he at 38).
			a["whirl_spin"] = float(a.get("whirl_spin", 0.0)) + dt * 38.0
			root.rotation.y = float(u.face) - float(a.whirl_spin)
		else:
			if float(a.get("whirl_spin", 0.0)) != 0.0:
				a["whirl_spin"] = 0.0
			var ry := root.rotation.y
			if absf(angle_difference(ry, float(u.face))) > 0.0005:
				root.rotation.y = lerp_angle(ry, float(u.face), rot_k)
		(a.ring as MeshInstance3D).visible = u.state != "dead"
		if prof_on: tu = _pv("a.place+fog", tu)
		var show := root.visible and (planes.is_empty() or _on_screen(newp, planes, 1.8 if float(a.get("big", 0.0)) <= 0.0 else 5.0))
		if show or not alive_u or bool(a.dead):
			_sync_vanish(a, u)
			if prof_on: tu = _pv("a.vanish", tu)
			_animate(a, u, vel)
			if prof_on: tu = _pv("a.animate", tu)
			if a.get("cape") != null:
				_cape_step(a, dt)
		if is_instance_valid(a.player):
			if (a.player as AnimationPlayer).active != show:
				(a.player as AnimationPlayer).active = show
			if show:
				anim_active += 1
	if prof_on: tp = _pv("actors", tp)
	for id in actors.keys():
		if not seen.has(id):
			if _pool_put(actors[id]):                  # 0.31.207: a minion's body waits for the next one
				actors.erase(id)
				continue
			if actors[id].get("rag") != null:
				_ragdoll_end(actors[id])               # 0.31.160: its ground patch and its place among the RAG_MAX go too
			actors[id].root.queue_free()
			actors.erase(id)
	_sync_oracles(dt)
	if prof_on: tp = _pv("oracles", tp)
	_sync_castle(dt)
	if prof_on: tp = _pv("castle", tp)
	_sync_projectiles()
	if prof_on: tp = _pv("projectiles", tp)
	if sim.moba != null:
		_sync_moba()
		_sync_falling(dt)                          # 0.31.172: a tower's broken-off pieces
	if prof_on: tp = _pv("moba", tp)
	_step_fx()
	if fxs != null:
		fxs.step(dt)                               # 0.31.201: the abilities' effects
	if prof_on: tp = _pv("fx", tp)
	_update_camera(dt)
	if prof_on: tp = _pv("camera", tp)

# ---------- 5V5 (0.31.155, scripts/siege/moba.gd) ----------
# The lane towers, their range on the ground when you're near an enemy one (red when it's aiming at you), their shots
# (a fireball from the brazier that homes in on its target). 0.31.172 (Kevin: "new tower models ... I want them to
# visually break as their health gets lower"): the Meshy towers of towers.gd -- the lane tower (a little bigger each
# tier) and the King tower -- breaking in stages as they're hurt: cracks spreading, pieces breaking off and tumbling
# down (_tower_stage, _sync_falling), the brazier going out, smoke and then fire from the broken top; when one falls,
# all but its foot comes down in a burst of rubble. (Was KayKit hex towers in the side's colour; a stump once fallen.)
const MINION_SCALE := 0.78
const TOWER_SMOKE_H := [0.0, 0.0, 0.74, 0.52, 0.2]       # by stage: where the smoke rises from (of the tower's height)
var moba_towers: Dictionary = {}           # tower id -> {node, mesh, ring, stage, tier, h, top, fire, smoke, flames, dmg}
var _tshots: Array = []                    # {node, from, id, t0, flight, to}
var _falling: Array = []                   # broken-off pieces: {node, vel, spin, ground, t, rest}

func _build_moba() -> void:
	if sim.moba == null:
		return
	_build_brush()
	_build_fog()
	for tw in sim.moba.towers:
		var gy := Sim.height_at(tw.p)
		var tier := int(tw.tier)
		# its front (the brazier's gem; the King tower's stairs) towards the other side's keep
		var d: Vector2 = Sim.throne(1 - int(tw.team)) - (tw.p as Vector2)
		var node := Towers.instance(tier, vt(int(tw.team)))
		node.position = Vector3(tw.p.x, gy, tw.p.y)
		node.rotation.y = atan2(d.x, d.y)
		add_child(node)
		var top: Vector3 = node.position + Basis(Vector3.UP, node.rotation.y) * Towers.brazier(tier)
		var ring := MeshInstance3D.new()
		ring.mesh = _ring_mesh(sim.moba.TOWER_RANGE, 0.16)
		ring.scale = Vector3(1, 0.15, 1)
		ring.material_override = _unshaded(Color(1.0, 0.85, 0.5, 0.55))
		ring.position = Vector3(tw.p.x, gy + 0.08, tw.p.y)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.visible = false
		add_child(ring)
		var fire := _beacon_fire(top - Vector3(0, 0.25, 0))
		fire.scale = Vector3.ONE * (0.2 if tier < 4 else 0.26)          # (a small flame in the bowl, under the gem)
		fire.amount = 8
		((fire.draw_pass_1 as QuadMesh).material as StandardMaterial3D).albedo_color = Color(1.5, 0.62, 0.18, 0.8)
		moba_towers[int(tw.id)] = {"node":node, "mesh":node.get_meta("mesh", null), "ring":ring, "stage":-1, "tier":tier,
			"h":Towers.height(tier), "top":top, "fire":fire, "smoke":null, "flames":null, "dmg":-1.0}
		var tmi: MeshInstance3D = node.get_meta("mesh", null)
		if tmi != null:
			Towers.chunks(Towers.kind_of(tier), tmi.mesh)      # (the pieces made now, not in the middle of a fight)

func _tower_stage(tw: Dictionary, mt: Dictionary, stage: int, animate: bool) -> void:
	# A tower's look at a stage (towers.gd): that stage's cells hidden in its mesh and, when it happens before your
	# eyes, dropped as pieces; the brazier out from stage 3; smoke from 2, flames from the broken top at 3; at 4 (it
	# fell) the foot smoulders.
	var old := int(mt.stage)
	mt.stage = stage
	var mi: MeshInstance3D = mt.mesh
	if mi != null:
		mi.set_instance_shader_parameter("broken", float(stage))
		mi.set_instance_shader_parameter("lit", 1.0 if stage < 3 else 0.0)
	var node: Node3D = mt.node
	var base: Vector3 = node.position
	if animate and old >= 0 and stage > old and mi != null:
		var pieces := Towers.chunks(Towers.kind_of(int(mt.tier)), mi.mesh)
		var mid := Vector3.ZERO
		var n := 0
		for c in pieces:
			if int(c.stage) > old and int(c.stage) <= stage:
				var at: Vector3 = node.to_global((c.center as Vector3) * float(mt.h))
				_drop_piece(c, mt, at, base)
				mid += at
				n += 1
		if n > 0:
			mid /= float(n)
			smoke_cloud(mid, 0.28 if stage < 4 else 0.7, 5 if stage < 4 else 14, 3.0)
			tower_broke.emit(mid, stage)
	if stage >= 3 and is_instance_valid(mt.fire):
		(mt.fire as Node).queue_free()
		mt.fire = null
	if stage >= 2:
		var sh: Vector3 = base + Vector3(0, float(mt.h) * float(TOWER_SMOKE_H[mini(stage, 4)]), 0)
		if mt.smoke == null or not is_instance_valid(mt.smoke):
			mt.smoke = _tower_smoke(sh)
		(mt.smoke as Node3D).position = sh
		(mt.smoke as GPUParticles3D).amount_ratio = 1.0 if stage < 4 else 0.5
	if stage == 3 and (mt.flames == null or not is_instance_valid(mt.flames)):
		mt.flames = _beacon_fire(base + Vector3(0, float(mt.h) * 0.5, 0))
		(mt.flames as Node3D).scale = Vector3.ONE * 0.3
		(((mt.flames as GPUParticles3D).draw_pass_1 as QuadMesh).material as StandardMaterial3D).albedo_color = Color(1.5, 0.62, 0.18, 0.8)
	elif stage >= 4 and mt.flames != null and is_instance_valid(mt.flames):
		(mt.flames as Node).queue_free()
		mt.flames = null

func _drop_piece(c: Dictionary, mt: Dictionary, at: Vector3, base: Vector3) -> void:
	# a broken-off piece: thrown out from the tower's middle, tumbling, it bounces once and settles, then sinks away
	if _falling.size() >= 90:
		return
	var p := MeshInstance3D.new()
	p.mesh = c.mesh
	p.material_override = (mt.mesh as MeshInstance3D).material_override
	p.set_instance_shader_parameter("dmg", float(mt.dmg))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if low_fx else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	p.position = at
	p.basis = (mt.node as Node3D).basis.scaled(Vector3.ONE * float(mt.h))
	add_child(p)
	var out := Vector2(at.x - base.x, at.z - base.z)
	out = out.normalized() if out.length() > 0.05 else Vector2.from_angle(randf() * TAU)
	var spd := randf_range(1.2, 3.4)
	_falling.append({"node":p, "vel":Vector3(out.x * spd, randf_range(0.5, 2.6), out.y * spd),
		"spin":Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(2.0, 6.0),
		"ground":Sim.height_at(Vector2(at.x, at.z)), "bounced":false, "rest":-1.0, "t":0.0})

func _sync_falling(dt: float) -> void:
	for i in range(_falling.size() - 1, -1, -1):
		var f: Dictionary = _falling[i]
		var p: MeshInstance3D = f.node
		if not is_instance_valid(p):
			_falling.remove_at(i)
			continue
		f.t = float(f.t) + dt
		if float(f.rest) < 0.0:
			var v: Vector3 = f.vel
			v.y -= 22.0 * dt
			p.position += v * dt
			var sp: Vector3 = f.spin
			if sp.length() > 0.01:
				p.basis = Basis(sp.normalized(), sp.length() * dt) * p.basis
			var gy := float(f.ground) + 0.15
			if p.position.y <= gy:
				p.position.y = gy
				if not bool(f.bounced):
					f.bounced = true
					v = Vector3(v.x * 0.45, -v.y * 0.28, v.z * 0.45)
					f.spin = sp * 0.4
					if randf() < 0.5:
						spark(p.position + Vector3(0, 0.1, 0), Color("#d9cdb4"))
				else:
					f.rest = float(f.t)
			f.vel = v
		elif float(f.t) - float(f.rest) > 2.6:
			p.position.y -= dt * 0.5                     # (sinks into the ground, then goes)
			if float(f.t) - float(f.rest) > 4.2:
				p.queue_free()
				_falling.remove_at(i)

func _tower_smoke(at: Vector3) -> GPUParticles3D:
	# a broken tower's smoke: a thin grey column drifting with the breeze, as long as it stands (and from its foot after)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.5
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 10.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.5
	pm.gravity = Vector3(0.0, 0.5, 0.0) + SMOKE_WIND * 1.4
	pm.damping_min = 0.2
	pm.damping_max = 0.4
	pm.scale_min = 0.9
	pm.scale_max = 1.5
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.5))
	sc.add_point(Vector2(1.0, 2.2))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 0.6, 1.0])
	g.colors = PackedColorArray([Color(0.22, 0.2, 0.19, 0.0), Color(0.25, 0.23, 0.22, 0.55), Color(0.42, 0.41, 0.4, 0.3),
		Color(0.55, 0.55, 0.55, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	var q := QuadMesh.new()
	q.size = Vector2(1.3, 1.3)
	q.material = _smoke_draw_mat()
	var ps := GPUParticles3D.new()
	ps.process_material = pm
	ps.draw_pass_1 = q
	ps.amount = 5 if low_fx else 9
	ps.lifetime = 5.0
	ps.preprocess = 3.0
	ps.local_coords = false
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ps.visibility_aabb = AABB(Vector3(-6, -1, -6), Vector3(12, 12, 12))
	ps.position = at
	add_child(ps)
	return ps

func _sync_moba() -> void:
	_sync_rains()
	_sync_auras()
	_sync_breaths()
	_sync_kits()                               # 0.31.167: W and E
	_sync_fog()
	_sync_wards()
	var me: Dictionary = sim.by_id.get(player_id, {})
	for tw in sim.moba.towers:
		var mt: Dictionary = moba_towers.get(int(tw.id), {})
		if mt.is_empty():
			continue
		# 0.31.172: breaking with its health (a first look -- a match joined late -- shows it as it is, nothing falls)
		var stg := Towers.stage_of(float(tw.hp), float(tw.max_hp), bool(tw.dead))
		if stg != int(mt.stage) and stg > int(mt.stage):
			_tower_stage(tw, mt, stg, int(mt.stage) >= 0)
		var dm := 1.0 if bool(tw.dead) else clampf(1.0 - float(tw.hp) / maxf(float(tw.max_hp), 1.0), 0.0, 1.0)
		if absf(dm - float(mt.dmg)) > 0.01 and mt.mesh != null:
			mt.dmg = dm
			(mt.mesh as MeshInstance3D).set_instance_shader_parameter("dmg", dm)
		var ring: MeshInstance3D = mt.ring
		var show: bool = not bool(tw.dead) and not me.is_empty() and int(tw.team) != int(me.team) and sim.alive(me) \
			and (me.pos as Vector2).distance_to(tw.p) <= float(sim.moba.TOWER_RANGE) + 5.0
		ring.visible = show
		if show:
			var on_me: bool = str(tw.target) == str(me.id)
			(ring.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.2, 0.15, 0.8) if on_me else Color(1.0, 0.85, 0.5, 0.45)
	for i in range(_tshots.size() - 1, -1, -1):
		var sh: Dictionary = _tshots[i]
		var k := clampf((_time - float(sh.t0)) / float(sh.flight), 0.0, 1.0)
		var a: Dictionary = actors.get(str(sh.id), {})
		if not a.is_empty() and is_instance_valid(a.root):
			sh.to = (a.root as Node3D).position + Vector3(0, 1.1, 0)
		var at: Vector3 = (sh.from as Vector3).lerp(sh.to, k)
		at.y += sin(k * PI) * 0.8
		if is_instance_valid(sh.node):
			(sh.node as Node3D).position = at
		if k >= 1.0:
			if is_instance_valid(sh.node):
				(sh.node as Node3D).queue_free()
			for j in 4:
				spark(sh.to + Vector3(randf_range(-0.3, 0.3), randf_range(-0.2, 0.4), randf_range(-0.3, 0.3)), Color("#ffb04a"))
			_tshots.remove_at(i)

# ---------- 0.31.158: the fog of war (moba_vision.gd) ----------
# A dark veil over what your side can't see -- ground, trees and castles alike: one Decal over the whole field, its
# texture a coarse mask (FOG_CELL m a texel, filtered smooth) redrawn FOG_EVERY s from your side's sight
# (moba_vision.sources) -- each source a clear disc, brush patches dark again unless one of yours stands (or a ward of
# yours stands) in them. (The texture is replaced, not updated: a decal keeps its own copy until its texture is
# replaced. A screen-space veil from the depth buffer was tried: the depth buffer isn't there with the battle's MSAA on
# the Mobile renderer.) Brush patches are KayKit bushes. Your side's wards show as little glowing posts; the enemy's
# don't.
const FOG_CELL := 2.0
const FOG_ALPHA := 200
const FOG_TINT := Color8(16, 22, 36)               # (a cool, dim veil: the decal mixes it in at FOG_ALPHA)
const FOG_EVERY := 0.15
var _fog := {}
var _ward_nodes := {}
var fog_on := true                         # (tests and render tools can turn the veil off)

func _fogged(u: Dictionary) -> bool:
	# (0.31.158) the unit's body is hidden in the fog of war -- its effects go too
	var a: Dictionary = actors.get(str(u.get("id", "")), {})
	return not a.is_empty() and is_instance_valid(a.root) and not (a.root as Node3D).visible

func _my_team() -> int:
	var me = sim.by_id.get(player_id)               # (0.31.160: no throwaway {} per call -- it's asked per unit, per frame)
	return int((me as Dictionary).get("team", my_side)) if me != null else my_side

func _build_fog() -> void:
	var r := Land.bake_rect()
	var w := int(ceil(r.size.x / FOG_CELL))
	var h := int(ceil(r.size.y / FOG_CELL))
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var tex := ImageTexture.create_from_image(img)
	var d := Decal.new()
	d.size = Vector3(float(w) * FOG_CELL, 40.0, float(h) * FOG_CELL)
	d.position = Vector3(r.position.x + float(w) * FOG_CELL * 0.5, 8.0, r.position.y + float(h) * FOG_CELL * 0.5)
	d.texture_albedo = tex
	d.albedo_mix = 1.0
	d.upper_fade = 0.0
	d.lower_fade = 0.0
	d.normal_fade = 0.0
	d.name = "FogOfWar"
	add_child(d)
	_fog = {"decal":d, "img":img, "tex":tex, "w":w, "h":h, "rect":r, "at":-10.0}

func fog_alpha_at(p: Vector2) -> int:
	# (tests) the veil over p: 0 clear .. FOG_ALPHA
	if _fog.is_empty():
		return 0
	var r: Rect2 = _fog.rect
	var cx := int((p.x - r.position.x) / FOG_CELL)
	var cz := int((p.y - r.position.y) / FOG_CELL)
	if cx < 0 or cz < 0 or cx >= int(_fog.w) or cz >= int(_fog.h):
		return 0
	return (_fog.img as Image).get_pixel(cx, cz).a8

func _stamp(img: Image, w: int, h: int, r: Rect2, c: Vector2, rad: float, col: Color) -> void:
	# a disc of texels, a row at a time
	var cx := (c.x - r.position.x) / FOG_CELL - 0.5
	var cz := (c.y - r.position.y) / FOG_CELL - 0.5
	var rr := rad / FOG_CELL
	var z0 := maxi(0, int(floor(cz - rr)))
	var z1 := mini(h - 1, int(ceil(cz + rr)))
	for z in range(z0, z1 + 1):
		var dz := float(z) - cz
		var span := rr * rr - dz * dz
		if span < 0.0:
			continue
		var half := sqrt(span)
		var x0 := maxi(0, int(ceil(cx - half)))
		var x1 := mini(w - 1, int(floor(cx + half)))
		if x1 >= x0:
			img.fill_rect(Rect2i(x0, z, x1 - x0 + 1, 1), col)

func _sync_fog() -> void:
	if _fog.is_empty() or sim.moba == null or sim.moba.vision == null:
		return
	(_fog.decal as Decal).visible = fog_on
	if _time - float(_fog.at) < FOG_EVERY or not fog_on:
		return
	_fog.at = _time
	var img: Image = _fog.img
	var w: int = _fog.w
	var h: int = _fog.h
	var r: Rect2 = _fog.rect
	var dark := Color(FOG_TINT, float(FOG_ALPHA) / 255.0)
	var clear := Color(FOG_TINT, 0.0)
	img.fill(dark)
	var vis = sim.moba.vision
	var src: Array = vis.sources(_my_team())
	var done := []
	var in_brush := {}
	for sr in src:
		if int(sr[2]) >= 0:
			in_brush[int(sr[2])] = true
		var skip := false
		for d in done:
			if (sr[0] as Vector2).distance_to(d[0]) < 3.0 and float(d[1]) >= float(sr[1]) - 0.1:
				skip = true                              # (a pack of minions: one disc)
				break
		if skip:
			continue
		done.append(sr)
		_stamp(img, w, h, r, sr[0], float(sr[1]), clear)
	for b in vis.brushes:
		if not in_brush.has(int(b.id)):
			_stamp(img, w, h, r, b.p, float(b.r), dark)        # (looking in from outside: nothing)
	(_fog.tex as ImageTexture).set_image(img)

func _build_brush() -> void:
	# The brush you hide in (moba_vision.gd's patches). 0.31.216 (Kevin: "need new models for grass"): Honor of Kings' tall
	# lavender-tipped grass painted by ElevenLabs (ground_cards.gd BRUSH), thick enough to fill its circle -- a ring of
	# tall clumps round its edge, more through the middle -- with the field's grass clumps at its foot. (0.31.173: the
	# Meshy bushes and grasses of foliage.gd's BRUSH_SETS; KayKit's before.)
	if sim.moba == null or sim.moba.vision == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 158
	var n := 0
	for b in sim.moba.vision.brushes:
		var c: Vector2 = b.p
		var rad: float = b.r
		var tall := []
		var tall_c := []
		var low := []
		var low_c := []
		var ring := int(ceil(TAU * (rad - 0.4) / 0.95))
		for k in ring:
			var a := TAU * (float(k) + rng.randf_range(-0.3, 0.3)) / ring
			tall.append(_brush_xf(c + Vector2.from_angle(a) * (rad - 0.45) * rng.randf_range(0.9, 1.05), rng, 2.0, 2.5))
			tall_c.append(GroundCards.custom(rng.randi() % 2, rng))
		var inner := int(rad * rad * 1.1)
		for k in inner:
			var q := c + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * (rad - 0.9)
			tall.append(_brush_xf(q, rng, 2.1, 2.6))
			tall_c.append(GroundCards.custom(rng.randi() % 2, rng))
		for k in int(ring * 0.8):
			var q := c + Vector2.from_angle(rng.randf() * TAU) * (rad + rng.randf_range(-0.1, 0.35))
			low.append(_brush_xf(q, rng, 0.6, 0.9))
			low_c.append(GroundCards.custom(rng.randi() % 8, rng))
		# one MultiMesh a patch and kind (Brush_*: tests/moba_ui_test.gd, foliage_test.gd count them)
		for pair in [["brush", tall, tall_c], ["blades", low, low_c]]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = GroundCards.mesh(str(pair[0]))
			mm.instance_count = (pair[1] as Array).size()
			for i in mm.instance_count:
				mm.set_instance_transform(i, pair[1][i])
				mm.set_instance_custom_data(i, pair[2][i])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Brush_%s_%d" % [str(pair[0]), n]
			mmi.multimesh = mm
			mmi.material_override = GroundCards.material(str(pair[0]), PAINT_TINT * CARD_LIGHT)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.set_meta("perf", "brush")
			mmi.set_meta("perf_kind", str(pair[0]))
			mmi.set_meta("places", pair[1])
			add_child(mmi)
		n += 1

static func _brush_xf(q: Vector2, rng: RandomNumberGenerator, s0: float, s1: float) -> Transform3D:
	var sc := rng.randf_range(s0, s1)
	var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc * rng.randf_range(0.9, 1.2), sc, sc * rng.randf_range(0.9, 1.2)))
	return Transform3D(b, Vector3(q.x, Sim.height_at(q) - 0.06, q.y))

# 0.31.216 (Kevin: "use eleven to draw detailed paint on ground"): carved stone circles where Honor of Kings has them --
# the river's crossing in the middle, the pits' floors, the lanes outside each keep's gates and halfway down the
# middle lane and the side lanes -- and a ring of carved stone round every tower's foot (ground_cards.gd decals).
const MARK_CIRCLES := [[Vector2(0.0, 0.0), 8.5], [Vector2(0.0, 41.0), 6.0], [Vector2(-60.0, 33.0), 6.0],
	[Vector2(60.0, 33.0), 6.0]]
const MARK_RING := 6.4                 # a tower's ring, across (its hole ~2.4 m: the tower's foot stands in it)

func _build_ground_marks() -> void:
	# (the ground's own height: the ridges' rock, where a mark runs under it, hides it -- and the build step is a quarter
	# of the time terrain_height's took)
	var h := func(p: Vector2) -> float: return Land.ground_height(p, false)
	var spots := []
	for c in MARK_CIRCLES:
		spots.append(["circle.png", c[0], float(c[1])])
		if (c[0] as Vector2).length() > 0.1:
			spots.append(["circle.png", -(c[0] as Vector2), float(c[1])])
	for i in 2:
		spots.append(["circle.png", Land.pit_c(i), Land.PIT_R * 1.9])
	for t in 2:
		for g in Keep.GATE_ANG.size():
			var gc: Vector2 = Keep.gate_c(g)
			var out := (gc - Keep.C).normalized()
			spots.append(["circle.png", Sim._m(t, gc + out * 6.2), 5.2])
	if sim.moba != null:
		for tw in sim.moba.towers:
			spots.append(["ring.png", tw.p, MARK_RING])
	var rng := RandomNumberGenerator.new()
	rng.seed = 216
	for sp in spots:
		var mi := MeshInstance3D.new()
		mi.mesh = GroundCards.decal_mesh(sp[1], float(sp[2]), h)
		var m: ShaderMaterial = GroundCards.decal_material(str(sp[0]), PAINT_TINT * 1.05).duplicate()
		m.set_shader_parameter("spin", rng.randf() * TAU)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta("perf", "marks")
		add_child(mi)

func _sync_wards() -> void:
	if sim.moba == null or sim.moba.vision == null:
		return
	var team := _my_team()
	var live := {}
	for w in sim.moba.vision.wards:
		if int(w.team) != team:
			continue                                    # (the enemy's wards are hidden)
		live[int(w.id)] = true
		if not _ward_nodes.has(int(w.id)):
			_ward_nodes[int(w.id)] = _make_ward(w.p)
	for id in _ward_nodes.keys():
		if not live.has(id):
			if is_instance_valid(_ward_nodes[id]):
				(_ward_nodes[id] as Node3D).queue_free()
			_ward_nodes.erase(id)

func _make_ward(p: Vector2) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(p.x, Sim.height_at(p), p.y)
	var post := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.09
	cm.height = 1.0
	post.mesh = cm
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("#5a3d22")
	post.material_override = wood
	post.position.y = 0.5
	root.add_child(post)
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	orb.mesh = sm
	orb.material_override = _fx_mat(Color("#7fd8ff"))
	orb.position.y = 1.1
	root.add_child(orb)
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh(0.45, 0.06)
	ring.scale = Vector3(1, 0.2, 1)
	ring.material_override = _unshaded(Color(0.5, 0.85, 1.0, 0.7))
	ring.position.y = 0.06
	root.add_child(ring)
	add_child(root)
	return root

# ---------- 0.31.157: ultimates, the jungle, gold ----------
const ULT_COL := {"knight":"#ffd65a", "barbarian":"#ff5a3a", "rogue":"#7a5ab8", "ranger":"#cfe8b8", "mage":"#ff8a3a",
	"priest":"#fff1a8", "crusader":"#ffd65a", "berserker":"#ff2a2a", "assassin":"#9a6bff", "sniper":"#dff4ff",
	"archmage":"#c070ff", "necromancer":"#7dff8a"}
const AURA_COL := {"dr":"#ffd65a", "bl":"#ff5a3a", "ud":"#ff2a2a", "arcane":"#7fb8ff", "ember":"#ff8a3a", "lord":"#c9a6ff"}
var _rain_fx: Array = []                   # {at, r, until, next}
var _aura_at := 0.0

func _ground(p: Vector2, up := 0.1) -> Vector3:
	return Vector3(p.x, Sim.height_at(p) + up, p.y)

func _moba_fx(e: Dictionary) -> void:
	var a: Dictionary = actors.get(str(e.get("id", "")), {})
	match str(e.k):
		"ult":
			# 0.31.201: each ultimate its own look (spell_fx.gd ult); the Ranger's arrows still fall here (_sync_rains)
			var at: Vector3 = (a.root as Node3D).position if not a.is_empty() and is_instance_valid(a.root) else _ground(e.pos)
			var sp := str(e.get("spell", ""))
			if sp != "" and not a.is_empty() and NEW_ULT_CLIP.has(sp):
				_play(a, str(NEW_ULT_CLIP[sp]), 1.2, 0.45)
			if str(e.ult) == "ranger":
				var c2: Vector2 = e.get("c", e.pos)
				_rain_fx.append({"at":c2, "r":float(e.get("r", 4.5)), "until":_time + float(e.get("dur", 2.0)), "next":_time})
			fxs.ult(str(e.ult), e, a, at)
		"flurry_hit":
			fxs.event(e)
		"lord_slam":
			var lp := _ground(e.pos, 0.2)
			ring_at(lp, Color("#c9a6ff"), 2.0 * float(sim.moba.LORD_SLAM_R) - 0.4, 0.5)
			shockwave(lp, float(sim.moba.LORD_SLAM_R))
			for i in 8:
				spark(lp + Vector3(randf_range(-2.0, 2.0), 0.3 + randf() * 0.8, randf_range(-2.0, 2.0)), Color("#d8c2ff"))
			var me: Dictionary = sim.by_id.get(player_id, {})
			if not me.is_empty() and (me.pos as Vector2).distance_to(e.pos) < 14.0:
				shake(0.35)
		"camp_up":
			for id in e.get("ids", []):
				var ca: Dictionary = actors.get(str(id), {})
				var cu: Dictionary = sim.by_id.get(str(id), {})
				if cu.is_empty():
					continue
				var cp := _ground(cu.pos)
				ring_at(cp, TEAM_COLORS[2], 1.8, 0.6)
				for i in 6:
					spark(cp + Vector3(randf_range(-0.5, 0.5), randf() * 0.8, randf_range(-0.5, 0.5)), Color("#e8dcc0"))
				if not ca.is_empty() and is_instance_valid(ca.root):
					(ca.root as Node3D).position = cp - Vector3(0, 0.1, 0)
		"buff":
			if not a.is_empty() and is_instance_valid(a.root):
				var bc := Color(str(AURA_COL.get(str(e.buff), "#ffffff")))
				for i in 2:
					ring_at((a.root as Node3D).position, bc, 2.4 + i * 1.6, 0.7 + 0.2 * i)
				for i in 10:
					spark((a.root as Node3D).position + Vector3(randf_range(-0.5, 0.5), 0.3 + randf() * 2.0, randf_range(-0.5, 0.5)), bc)
		"lord_down":
			var ld := _ground(sim.moba.BOSS_P, 0.2)
			_pack_explosion("heavy", ld + Vector3(0, 1.4, 0), 1.6)
			for i in 3:
				ring_at(ld, Color("#c9a6ff"), 3.0 + i * 2.0, 0.8 + i * 0.2)
			shake(0.6)
		"gold":
			if str(e.id) == player_id:
				number(_ground(e.pos, 2.4), "+%d" % int(e.n), true, true)
		"lord_march":                                       # 0.31.158: the Bone Lord out of the slayers' castle
			var lu: Dictionary = sim.by_id.get(str(e.get("id", "")), {})
			if not lu.is_empty() and (int(e.team) == _my_team() or sim.moba.can_see(_my_team(), lu)):
				var lm := _ground(lu.pos, 0.2)
				for i in 3:
					ring_at(lm, TEAM_COLORS[vt(int(e.team))].lightened(0.2), 2.0 + i * 1.6, 0.7 + i * 0.2)
				for i in 12:
					spark(lm + Vector3(randf_range(-1.2, 1.2), 0.3 + randf() * 2.4, randf_range(-1.2, 1.2)), Color("#d8c2ff"))
		"wyrm_breath":                                      # 0.31.166: the Grave Wyrm's soul-fire
			if a.is_empty() or not is_instance_valid(a.root) or not (a.root as Node3D).visible:
				return
			_play(a, "w/Breath", 1.0, 1.4)
			var bd: Vector2 = (e.get("dir", Vector2(0, 1)) as Vector2).normalized()
			var root3: Node3D = a.root
			var mouth: Vector3 = root3.position + Basis(Vector3.UP, Sim.angle_of(bd)) * (WyrmBody.mouth_local() * (a.body as Node3D).scale.x)
			_breaths.append({"at":_time + WyrmBody.BREATH_AT, "from":mouth, "dir":bd})
		"wyrm_down":                                        # 0.31.166: its soul-fire bursts out of it
			var wd := _ground(sim.moba.WYRM_P, 0.2)
			for id in actors:
				if float(actors[id].get("big", 0.0)) > 0.0 and is_instance_valid(actors[id].root):
					wd = (actors[id].root as Node3D).position + Vector3(0, 0.2, 0)
			for i in 3:
				ring_at(wd, WYRM_FIRE, 3.0 + i * 2.2, 0.8 + i * 0.25)
			_soul_fire(wd + Vector3(0, 1.6, 0), Vector3.UP, 1.4, 0.9)
			shockwave(wd + Vector3(0, 0.3, 0), 7.0)
			for i in 16:
				spark(wd + Vector3(randf_range(-2.5, 2.5), 0.4 + randf() * 3.0, randf_range(-2.5, 2.5)), WYRM_FIRE)
			shake(0.6)
		"ward":
			if int(e.get("team", -1)) == _my_team():
				var wp3 := _ground(e.pos, 0.15)
				ring_at(wp3, Color("#8fe3ff"), 3.0, 0.5)
				for i in 5:
					spark(wp3 + Vector3(randf_range(-0.3, 0.3), 0.4 + randf() * 1.0, randf_range(-0.3, 0.3)), Color("#bdf0ff"))

# ---------- 0.31.167: W and E (moba_kits.gd) ----------
# Each cast: its caster's clip (SPELL_CLIP) and a burst in its colour (SPELL_COL) shaped by what it is -- rings for the
# area ones, a trail for the dashes, sparks at both ends of a blink or a shadow step, a fan for the knives, a pillar of
# light for HOLY LIGHT, fire for the pillar's eruption. What lasts is drawn while it lasts (_sync_kits): a shield is a
# glowing bubble round its hero, a slow a pale ring at his feet, a mark or a curse a red one, poison green sparks rising;
# holy ground and caltrops a ring on the ground for their time, a fire pillar's warning circle until it erupts; your
# side's bear traps (theirs are hidden).
const SPELL_CLIP := {"bash":"m/Melee_Block_Attack", "rally":"r/Ranged_Magic_Raise", "consecrate":"r/Ranged_Magic_Raise",
	"leap":"m/Melee_1H_Attack_Jump_Chop", "bloodlust":"r/Ranged_Magic_Raise", "charge":"mb/Running_B", "frenzy":"r/Ranged_Magic_Raise",
	"caltrops":"g/Throw", "poison":"g/Use_Item", "shadowstep":"m/Melee_Dualwield_Attack_Stab", "knives":"g/Throw",
	"tumble":"ma/Dodge_Forward", "snare":"r/Ranged_Bow_Release", "trap":"g/Interact", "mark":"g/Interact",
	"pillar":"r/Ranged_Magic_Spellcasting", "missiles":"r/Ranged_Magic_Shoot", "manashield":"r/Ranged_Magic_Raise",
	"holylight":"r/Ranged_Magic_Spellcasting", "dazzle":"r/Ranged_Magic_Raise", "boneshield":"r/Ranged_Magic_Spellcasting",
	"curse":"r/Ranged_Magic_Shoot",
	# 0.31.168: the six new heroes
	"boulder":"g/Throw", "stoneskin":"r/Ranged_Magic_Raise", "quake":"m/Melee_1H_Attack_Jump_Chop", "sweep":"m/Melee_2H_Attack_Slice",
	"impale":"m/Melee_2H_Attack_Stab", "vault":"mb/Jump_Full_Long", "thrust":"m/Melee_1H_Attack_Stab", "riposte":"m/Melee_Blocking",
	"feint":"ma/Dodge_Backward", "chain":"r/Ranged_Magic_Shoot", "static":"r/Ranged_Magic_Spellcasting", "gust":"r/Ranged_Magic_Shoot",
	"buckshot":"r/Ranged_Bow_Release", "keg":"g/Throw", "smokeroll":"ma/Dodge_Forward", "rejuv":"r/Ranged_Magic_Spellcasting",
	"entangle":"r/Ranged_Magic_Summon", "barkskin":"r/Ranged_Magic_Raise"}
const SPELL_COL := {"bash":"#bcd8ff", "rally":"#ffd65a", "consecrate":"#ffe9a6", "leap":"#e0c9a0", "bloodlust":"#ff3a2a",
	"charge":"#ff6a3a", "frenzy":"#ff5a3a", "caltrops":"#b8b8b8", "poison":"#7dff6a", "shadowstep":"#9a6bff", "knives":"#d8d0ff",
	"tumble":"#e0d0b0", "snare":"#cfe8b8", "trap":"#a08060", "mark":"#ff4a4a", "pillar":"#ff8a3a", "blink":"#8fc8ff",
	"missiles":"#c070ff", "manashield":"#7fb8ff", "holylight":"#fff1a8", "dazzle":"#ffffff", "boneshield":"#e8e0c8",
	"curse":"#b04aff",
	# 0.31.168
	"boulder":"#9a978e", "stoneskin":"#b8b2a4", "quake":"#c8b48a", "sweep":"#e8e4dc", "impale":"#f0d0a0", "vault":"#ffcf8a",
	"thrust":"#f4f0ff", "riposte":"#ffe27a", "feint":"#c9b8ff", "chain":"#9fd4ff", "static":"#6fb4ff", "gust":"#d8f4ff",
	"buckshot":"#ffe0a0", "keg":"#ff9a3a", "smokeroll":"#c8c8c8", "smoke":"#b8b8b8", "rejuv":"#8dff6a", "entangle":"#6fbf3a",
	"barkskin":"#a07a4a", "landslide":"#b0a48a", "dragondive":"#ff7a3a", "challenge":"#ffe27a", "thunderstorm":"#7fb8ff",
	"quickdraw":"#ffd890", "wildgrowth":"#6aff7a"}
var _zone_nodes := {}                      # zone id -> its ring
var _trap_nodes := {}                      # trap id -> its mesh
var _kit_marks := {}                       # unit id -> {"shield": node, "slow": node, "amp": node}
var _kit_next := 0.0

func _kit_fx(e: Dictionary) -> void:
	var a: Dictionary = actors.get(str(e.get("id", "")), {})
	var shown: bool = not a.is_empty() and is_instance_valid(a.root) and (a.root as Node3D).visible
	match str(e.k):
		"spell":
			var sp := str(e.spell)
			var col := Color(str(SPELL_COL.get(sp, "#ffffff")))
			if not shown and int(e.get("team", -1)) != _my_team():
				return
			if not a.is_empty() and SPELL_CLIP.has(sp):
				_play(a, str(SPELL_CLIP[sp]), 1.4 if sp != "charge" else 1.8, 0.45)
			var at: Vector3 = (a.root as Node3D).position if shown else _ground(e.pos)
			fxs.cast(sp, e, a, at, str(e.get("hid", "")))     # 0.31.201: each its own look (spell_fx.gd)
		"slam", "pillar", "burst", "zap", "riposte":
			fxs.event(e)                               # 0.31.201 (spell_fx.gd event)
		"trap_snap":
			fxs.event(e)
			if _trap_nodes.has(int(e.trap)):
				(_trap_nodes[int(e.trap)] as Node3D).queue_free()
				_trap_nodes.erase(int(e.trap))
		"trap_gone":
			if _trap_nodes.has(int(e.trap)):
				(_trap_nodes[int(e.trap)] as Node3D).queue_free()
				_trap_nodes.erase(int(e.trap))

func _shake_near(p: Vector2, r: float, k: float) -> void:
	var me: Dictionary = sim.by_id.get(player_id, {})
	if not me.is_empty() and (me.pos as Vector2).distance_to(p) < r:
		shake(k)

const NEW_ULT_CLIP := {"landslide":"mb/Running_B", "dragondive":"mb/Jump_Full_Long", "thunderstorm":"r/Ranged_Magic_Summon",
	"quickdraw":"r/Ranged_Bow_Release", "wildgrowth":"r/Ranged_Magic_Raise"}
static var _bolt_mesh: BoxMesh

func _bolt_line(from: Vector3, to: Vector3, col: Color, life: float, jag: float) -> void:
	# a jagged streak of light (chain lightning, the storm's bolts, a musket's tracer): a few thin boxes, each from one
	# kink to the next, thinning out over its life (_step_fx "bolt")
	if low_fx and life < 0.2:
		return
	if _bolt_mesh == null:
		_bolt_mesh = BoxMesh.new()
		_bolt_mesh.size = Vector3(0.16, 0.16, 1.0)
	var n := maxi(1, int(from.distance_to(to) / 1.2))
	var prev := from
	for i in n:
		var t := float(i + 1) / float(n)
		var nxt := from.lerp(to, t)
		if i < n - 1:
			nxt += Vector3(randf_range(-jag, jag), randf_range(-jag, jag) * 0.6, randf_range(-jag, jag)) * 0.5
		var seg := MeshInstance3D.new()
		seg.mesh = _bolt_mesh
		seg.material_override = _fx_mat(col)
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(seg)
		var mid := (prev + nxt) * 0.5
		var len := maxf(0.05, prev.distance_to(nxt))
		seg.position = mid
		if len > 0.06:
			seg.look_at_from_position(mid, nxt, Vector3.UP if absf((nxt - prev).normalized().y) < 0.95 else Vector3.RIGHT)
		seg.scale = Vector3(1.0, 1.0, len)
		_fx.append({"node":seg, "at":_time, "life":life, "kind":"bolt"})
		prev = nxt

func _lob(from: Vector3, to: Vector3, dur: float, col: Color) -> void:
	# a thrown thing's arc (the powder keg): _step_fx's "shell"
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.22
	cm.bottom_radius = 0.22
	cm.height = 0.42
	mi.mesh = cm
	mi.material_override = _shot_mat("keg", col, 0.0, 0.8)
	mi.position = from
	add_child(mi)
	_fx.append({"node":mi, "at":_time, "life":dur, "kind":"shell", "p0":from, "p1":to})

func _vines(at: Vector3, r: float) -> void:
	# roots bursting up (ENTANGLE, WILD GROWTH): a ring of green spikes that sink back (_step_fx "spark" moves them)
	for i in 8:
		var ang := TAU * float(i) / 8.0 + randf() * 0.3
		var mi := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.18, 0.9, 0.18)
		mi.mesh = pm
		mi.material_override = _shot_mat("vine", Color("#4f8f2a"), 0.4, 0.8)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var p := at + Vector3(cos(ang) * r * 0.5, 0.3, sin(ang) * r * 0.5)
		mi.position = p
		mi.rotation = Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4))
		add_child(mi)
		_fx.append({"node":mi, "at":_time, "life":0.9, "kind":"spark", "p0":p, "dir":Vector3(0, -0.3, 0)})

func _sync_kits() -> void:
	var kits = sim.moba.kits
	var t: float = sim.time
	var my := _my_team()
	# zones (0.31.201: each its own ground, spell_fx.gd zone -- holy rays, lightning, smoke, the grove)
	var live := {}
	for z in kits.zones:
		var zid := int(z.zid)
		live[zid] = true
		if not _zone_nodes.has(zid):
			_zone_nodes[zid] = fxs.zone(z)
	for z in _zone_nodes.keys():
		if not live.has(z):
			fxs.release("zone:%d" % int(z))
			_zone_nodes.erase(z)
	# your side's traps
	for tr in kits.traps:
		if int(tr.team) != my or _trap_nodes.has(int(tr.id)):
			continue
		_trap_nodes[int(tr.id)] = fxs.trap_node(_ground(tr.at, 0.05), TEAM_COLORS[vt(my)])
	# what lasts on heroes: shields, slows, marks, skins, parries, poison, dashes, the ultimates' auras (spell_fx.gd)
	for id in actors:
		var u: Dictionary = sim.by_id.get(str(id), {})
		if u.is_empty() or not bool(u.get("hero", false)):
			continue
		var a: Dictionary = actors[id]
		if not is_instance_valid(a.root):
			continue
		var vis: bool = (a.root as Node3D).visible and sim.alive(u)
		fxs.sync_unit(str(id), u, a, vis)

# ---------- the Grave Wyrm's soul-fire (0.31.166) ----------
# A pale cyan-green flame poured from its jaws along the breath's line: a GPU particle stream (the smoke puff sprite, added
# on, white-hot to green to nothing, swelling as it goes) spread to the sim's cone (moba.gd WYRM_BREATH_ARC, out to
# WYRM_BREATH_R), cinders, and the ground it reaches scorched with a ring.
const WYRM_FIRE := Color("#7dffd0")
var _breaths: Array = []                   # {at, from, dir}: soul-fire to pour (once the clip has lunged)
static var _soul_pm: ParticleProcessMaterial = null
static var _soul_draw: StandardMaterial3D = null

func _sync_breaths() -> void:
	for i in range(_breaths.size() - 1, -1, -1):
		var b: Dictionary = _breaths[i]
		if _time < float(b.at):
			continue
		_breaths.remove_at(i)
		var d2: Vector2 = b.dir
		var from: Vector3 = b.from
		var from2 := Vector2(from.x, from.z)
		var reach: float = float(sim.moba.WYRM_BREATH_R)
		_soul_fire(from, (Vector3(d2.x, 0.0, d2.y) + Vector3(0, -0.28, 0)).normalized(), 1.0, 0.85)
		ring_at(_ground(from2 + d2 * reach * 0.8), WYRM_FIRE, reach * 0.9, 0.7)
		for k in 10:
			var off := d2.rotated(randf_range(-1.0, 1.0) * float(sim.moba.WYRM_BREATH_ARC)) * randf_range(0.3, 1.0) * reach
			spark(_ground(from2 + off, 0.3 + randf() * 0.8), WYRM_FIRE)
		var me: Dictionary = sim.by_id.get(player_id, {})
		if not me.is_empty() and (me.pos as Vector2).distance_to(from2) < 12.0:
			shake(0.3)

func _soul_fire(at: Vector3, dir: Vector3, size: float, pour: float) -> void:
	# the flame stream, poured for `pour` seconds along dir from at; straight up (Vector3.UP), one burst
	if _soul_pm == null:
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.25
		pm.direction = Vector3(0, 0, -1)
		pm.spread = 30.0                                  # about WYRM_BREATH_ARC (0.6 rad) either side
		pm.initial_velocity_min = 10.0
		pm.initial_velocity_max = 14.0
		pm.damping_min = 9.0
		pm.damping_max = 13.0
		pm.gravity = Vector3(0, 2.2, 0)                   # flames rise
		pm.angle_min = -180.0
		pm.angle_max = 180.0
		pm.angular_velocity_min = -90.0
		pm.angular_velocity_max = 90.0
		pm.scale_min = 0.7
		pm.scale_max = 1.1
		var sc := Curve.new()
		sc.add_point(Vector2(0.0, 0.3))
		sc.add_point(Vector2(0.35, 1.0))
		sc.add_point(Vector2(1.0, 1.7))
		var sct := CurveTexture.new()
		sct.curve = sc
		pm.scale_curve = sct
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.12, 0.45, 1.0])
		g.colors = PackedColorArray([Color(0.75, 1.0, 0.95, 0.0), Color(0.45, 1.0, 0.8, 0.5), Color(0.12, 0.7, 0.5, 0.32), Color(0.0, 0.2, 0.15, 0.0)])
		var gt := GradientTexture1D.new()
		gt.gradient = g
		pm.color_ramp = gt
		pm.lifetime_randomness = 0.3
		_soul_pm = pm
		var m := StandardMaterial3D.new()
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = SMOKE_TEX
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_soul_draw = m
	var p := GPUParticles3D.new()
	p.process_material = _soul_pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = _soul_draw
	p.draw_pass_1 = q
	p.amount = 90
	p.lifetime = 0.9
	p.fixed_fps = 30
	p.interpolate = true
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-10, -4, -10), Vector3(20, 14, 20))
	if low_fx:
		p.amount_ratio = 0.5
	p.position = at
	var burst := absf(dir.normalized().dot(Vector3.UP)) > 0.99
	if burst:
		p.basis = Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3.ONE * size)          # its -Z up
		p.explosiveness = 0.8
		p.one_shot = true
	else:
		p.basis = Basis.looking_at(dir, Vector3.UP).scaled(Vector3.ONE * size)
	add_child(p)
	p.restart()
	if not burst:
		get_tree().create_timer(pour).timeout.connect(func():
			if is_instance_valid(p):
				p.emitting = false)
	get_tree().create_timer(pour + p.lifetime + 0.5).timeout.connect(p.queue_free)

func _sync_rains() -> void:
	for i in range(_rain_fx.size() - 1, -1, -1):
		var rf: Dictionary = _rain_fx[i]
		if _time >= float(rf.until):
			_rain_fx.remove_at(i)
			continue
		if _time < float(rf.next):
			continue
		rf.next = _time + (0.12 if low_fx else 0.05)
		var packed := Stage.scene("res://assets/kaykit/weapons/arrow_bow.gltf")
		if packed == null:
			continue
		var ang := randf() * TAU
		var to2: Vector2 = (rf.at as Vector2) + Vector2(cos(ang), sin(ang)) * sqrt(randf()) * float(rf.r)
		var to := _ground(to2, 0.2)
		var arrow: Node3D = packed.instantiate()
		arrow.scale = Vector3.ONE * 1.3
		arrow.rotation.x = PI * 0.5                   # nose down
		add_child(arrow)
		_fx.append({"node":arrow, "at":_time, "life":0.32, "kind":"fall", "p0":to + Vector3(randf_range(-1.0, 1.0), 9.0, randf_range(-1.0, 1.0)), "p1":to})

func _sync_auras() -> void:
	pass                                           # (0.31.201: spell_fx.gd sync_unit, from _sync_kits)

func _tower_shot(e: Dictionary) -> void:
	var tw: Dictionary = sim.moba.towers[int(e.tw)]
	var mt0: Dictionary = moba_towers.get(int(e.tw), {})
	var from: Vector3 = mt0.top if not mt0.is_empty() else Vector3(tw.p.x, Sim.height_at(tw.p) + 4.4, tw.p.y)   # (its brazier)
	var node := _make_projectile("fire")
	node.position = from
	if int(e.get("ramp", 0)) >= 2:
		node.scale = Vector3.ONE * (1.0 + 0.2 * float(int(e.ramp)))      # (a tower warmed up on a hero: bigger shots)
	var a: Dictionary = actors.get(str(e.id), {})
	var to: Vector3 = (a.root as Node3D).position + Vector3(0, 1.1, 0) if not a.is_empty() and is_instance_valid(a.root) else from
	_tshots.append({"node":node, "from":from, "id":str(e.id), "t0":_time, "flight":float(e.get("flight", 0.3)), "to":to})

func _tower_down(e: Dictionary) -> void:
	# it falls: all but its foot comes down (_tower_stage 4), a blast of rubble and dust
	var tw: Dictionary = sim.moba.towers[int(e.tw)]
	var mt: Dictionary = moba_towers.get(int(e.tw), {})
	var gy := Sim.height_at(tw.p)
	var at := Vector3(tw.p.x, gy, tw.p.y)
	if not mt.is_empty():
		(mt.ring as MeshInstance3D).visible = false
		if int(mt.stage) < 4:
			_tower_stage(tw, mt, 4, int(mt.stage) >= 0)
	_pack_explosion("heavy", at + Vector3(0, 2.0, 0), 1.6)
	for i in 3:
		ring_at(at + Vector3(0, 0.2, 0), Color("#e0c9a0"), 3.0 + i, 0.7 + i * 0.2)
	_shake = maxf(_shake, 0.5)

func _animate(a: Dictionary, u: Dictionary, vel: float) -> void:
	var look: Dictionary = LOOKS.get(str(a.get("mlook", "")) if str(a.get("mlook", "")) != "" else u.cls, LOOKS.knight)
	if u.state == "dead":
		if not a.dead:
			a.dead = true
			if a.get("rag") == null:
				_play(a, "g/Death_A", 1.0, 99.0)       # far off (no ragdoll): the old fall
		return
	if a.dead:
		a.dead = false
		_ragdoll_end(a)
		a.busy_until = 0.0
	if _time < float(a.busy_until):
		return
	if u.stun > 0.0:
		_play(a, "g/Hit_B", 0.6)
	elif u.state == "dodge":
		_play(a, "ma/Dodge_Forward", 1.6, 0.3)
	elif sim.whirling(u):
		_play(a, "m/Melee_2H_Attack_Spinning", 1.8)
	elif sim.blocking(u):
		_play(a, "m/Melee_Blocking")
	elif str(u.get("beam", "")) != "":
		_play(a, "r/Ranged_Magic_Spellcasting_Long")
	elif vel > 0.6:
		_play(a, "mb/Running_A", clampf(vel / 5.2, 0.7, 1.4))
	else:
		_play(a, str(look.idle))

var ev_log = null                          # (tools/hitch_bench.gd: what happened, frame by frame)

func on_event(e: Dictionary) -> void:
	if ev_log != null:
		ev_log.append(str(e.k) + ("/" + str(e.spell) if e.has("spell") else "") + ("/" + str(e.ult) if e.has("ult") else ""))
	var a: Dictionary = actors.get(str(e.get("id", "")), {})
	match str(e.k):
		"attack":
			if a.is_empty():
				return
			var look: Dictionary = LOOKS.get(str(a.get("mlook", "")) if str(a.get("mlook", "")) != "" else a.cls, LOOKS.knight)
			var clip := str(look.ability if e.kind == "ability" else look.attack)
			if e.kind == "attack" and look.has("combo"):                  # 0.31.62: the combo's swing
				var cb: Array = look.combo
				clip = str(cb[int(e.get("combo", 0)) % cb.size()])
			_play(a, clip, 1.7, 0.55)
			if e.kind == "ability":
				var qu: Dictionary = sim.by_id.get(str(e.id), {})
				if not qu.is_empty() and (a.root as Node3D).visible:
					fxs.q(sim.ability_of(qu), a, qu)        # 0.31.201: the old classes' Q, each its own look
		"blocked":                                                        # 0.31.62: the shield takes it
			if not a.is_empty():
				_play(a, "m/Melee_Block_Hit", 1.6, 0.3)
		"hit":
			if a.is_empty() or not (a.root as Node3D).visible:
				return                                    # (0.31.158: nothing shown for a hit in the fog)
			spark(a.root.position + Vector3(0, 1.3, 0), Color("#ffd27a"))
			var hu: Dictionary = sim.by_id.get(str(e.id), {})
			if not hu.is_empty():
				var src: Dictionary = sim.by_id.get(str(e.get("by", "")), {})
				blood_hit(hu.pos, src.pos if not src.is_empty() else (hu.pos as Vector2) - Vector2.from_angle(float(hu.face)), float(e.get("dmg", 20)))
			number(a.root.position + Vector3(0, 2.2, 0), str(e.dmg), e.id == player_id)
			if _time >= float(a.busy_until):
				a["hit_flip"] = not bool(a.get("hit_flip", false))      # 0.31.62: the two flinches take turns
				_play(a, "g/Hit_B" if a.hit_flip else "g/Hit_A", 1.4, 0.3)
		"death":
			var du: Dictionary = sim.by_id.get(str(e.get("id", "")), {})
			if not du.is_empty():
				blood_pool(du.pos)
			if not a.is_empty() and (a.root as Node3D).visible:
				# (0.31.161: everyone's weapons fly out again -- Kevin: "I want the minions weapons to fly out of hands";
				# not for a body hidden in the 5v5's fog: nothing to see, and it isn't moved while hidden)
				var pa: Array = e.get("push", [0.0, 1.6, 0.0])
				var push := Vector3(float(pa[0]), float(pa[1]), float(pa[2])) if pa.size() >= 3 else Vector3(0.0, 1.6, 0.0)
				_drop_weapons(a, push)
				_ragdoll(a, push)
		"spawn":
			if not a.is_empty():
				a.root.position = Vector3(sim.by_id[e.id].pos.x, 0, sim.by_id[e.id].pos.y)
				ring_at(a.root.position, TEAM_COLORS[vt(int(sim.by_id[e.id].team))], 1.6, 0.6)
		"vanish":
			if sim.by_id.has(str(e.id)):
				sim.by_id[str(e.id)]["vanish_until"] = float(e.until)
			if not a.is_empty() and (a.root as Node3D).visible:
				fxs.q("vanish", a, sim.by_id[str(e.id)])
		"unvanish":
			if sim.by_id.has(str(e.id)):
				sim.by_id[str(e.id)]["vanish_until"] = sim.time
		"meteor_warn":
			_meteor_warn(e.pos, float(e.delay), int(e.team))
			fxs.event(e)
		"meteor_hit":
			_recent_blasts.append([e.pos, _time])
			_meteor_hit(e.pos, float(e.burn))
			fxs.event(e)
		"pierce_hit", "nova", "resurrect", "sanctuary", "boom", "block_up", "dodge", "proj":
			fxs.event(e)                                          # 0.31.201: spell_fx.gd event
		"gate_hit":
			var g: Dictionary = sim.gates[int(e.gate)]
			var gp: Vector2 = g.c + (Vector2(randf_range(-1.0, 1.0), 0.0))
			var gy := Sim.height_at(g.c)
			spark(Vector3(gp.x, gy + 1.4 + randf() * 1.2, gp.y), Color("#e8d6b0"))
			if randf() < 0.35:
				number(Vector3(g.c.x, gy + 3.2, g.c.y), str(e.dmg), false)
		"gate_broken":
			var g2: Dictionary = sim.gates[int(e.gate)]
			var gy2 := Sim.height_at(g2.c)
			for i in 3:
				ring_at(Vector3(g2.c.x, gy2 + 0.2, g2.c.y), Color("#e0c9a0"), 2.5 + i, 0.7 + i * 0.2)
			for i in 12:
				spark(Vector3(g2.c.x + randf_range(-2, 2), gy2 + 0.5 + randf() * 2.5, g2.c.y + randf_range(-1, 1)), Color("#c8b89a"))
		"tower_hit":
			# 0.31.177 (Kevin: "towers aren't targetable"): a hit on a tower shows -- chips of stone off the side it came
			# from, and the damage over it when it's yours
			var mt: Dictionary = moba_towers.get(int(e.tw), {})
			if mt.is_empty() or sim.moba == null:
				return
			var twp: Vector2 = sim.moba.towers[int(e.tw)].p
			var by_u: Dictionary = sim.by_id.get(str(e.get("by", "")), {})
			var side := ((by_u.pos as Vector2) - twp).normalized() if not by_u.is_empty() else Vector2.ZERO
			var ty := Sim.height_at(twp)
			var chip := Vector3(twp.x + side.x * sim.moba.TOWER_R, ty + 1.0 + randf() * 1.6, twp.y + side.y * sim.moba.TOWER_R)
			spark(chip, Color("#e8d6b0"))
			if str(e.get("by", "")) == player_id:
				spark(chip, Color("#ffd27a"))
				number((mt.top as Vector3) + Vector3(0, 1.1, 0), str(e.dmg), false)
		"recall_done":                            # 0.31.181: gone from there, here now
			var ru: Dictionary = sim.by_id.get(str(e.get("id", "")), {})
			if not a.is_empty() and not ru.is_empty():
				a.root.position = Vector3(ru.pos.x, Sim.height_at(ru.pos), ru.pos.y)     # (no gliding across the map)
				if str(e.id) == player_id and has_method("snap_camera"):
					call("snap_camera")
			for key in ["from", "to"]:
				var rp: Vector2 = e.get(key, Vector2.ZERO)
				var ry := Sim.height_at(rp)
				ring_at(Vector3(rp.x, ry + 0.1, rp.y), RECALL_COL, 2.6, 0.7)
				for i in 10:
					spark(Vector3(rp.x + randf_range(-0.6, 0.6), ry + 0.3 + randf() * 2.2, rp.y + randf_range(-0.6, 0.6)), RECALL_COL)
		"tshot":
			_tower_shot(e)                        # 0.31.155 5V5
		"tower_down":
			_tower_down(e)
		"king_slam":
			var kp: Vector2 = sim.moba.king_pos(int(e.team))              # 0.31.156 5V5: the King hits back
			var ky := Sim.height_at(kp)
			ring_at(Vector3(kp.x, ky + 0.2, kp.y), Color("#ffd65a"), float(sim.moba.KING_REACH), 0.5)
			for i in 6:
				spark(Vector3(kp.x + randf_range(-1.5, 1.5), ky + 0.4 + randf() * 1.0, kp.y + randf_range(-1.5, 1.5)), Color("#ffd65a"))
		"spell", "slam", "pillar", "trap_snap", "trap_gone", "burst", "zap", "riposte":
			_kit_fx(e)                            # 0.31.167 5V5: W and E (0.31.168: the new heroes' bursts, bolts, ripostes)
		"ult", "flurry_hit", "lord_slam", "camp_up", "buff", "lord_down", "gold", "lord_march", "ward", "wyrm_breath", "wyrm_down":
			_moba_fx(e)                           # 0.31.157 5V5: ultimates, the jungle, gold (0.31.166: the Wyrm; and the
			                                      # Lord's march and a placed ward, whose effects were never reached)
		"king_down":
			var kd: Vector2 = sim.moba.king_pos(int(e.team))
			var kdy := Sim.height_at(kd)
			_pack_explosion("heavy", Vector3(kd.x, kdy + 1.6, kd.y), 1.8)
			for i in 3:
				ring_at(Vector3(kd.x, kdy + 0.2, kd.y), Color("#ffd65a"), 3.0 + i * 1.5, 0.8 + i * 0.2)
			_shake = maxf(_shake, 0.8)
# ---------- the Kings ----------
# Each side's KING on his throne, the heart of its base (models 0.20.2, Kevin). The model isn't rigged, so he's
# animated by hand: breathing and a sway. Kevin named them kingT1 / kingT2; matched by robe colour: T2 (purple) leads
# blue, T1 (red) leads red. (Internal names -- sim.oracles, oracle_nodes -- stay: players never see them.)
const KING_HEIGHT := 2.6              # the Knight hero is 2.54; the king a touch taller (and much wider)

func _make_oracle(team: int) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var body := Node3D.new()                     # the part that breathes and sways
	root.add_child(body)
	var packed := Stage.scene("res://assets/kings/king_%s_fat.glb" % ("blue" if vt(team) == 0 else "red"))
	var m: Node3D = packed.instantiate() if packed != null else Node3D.new()
	m.scale = Vector3.ONE * (KING_HEIGHT / 1.9)          # the models are 1.9 tall, feet at 0
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _hq() else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(m)
	var ground_ring := _decal(Vector3.ZERO, 1.0, TEAM_COLORS[vt(team)], 0.8)
	ground_ring.reparent(root, false)
	return {"root":root, "body":body, "ground":ground_ring}

func _sync_oracles(dt: float) -> void:
	for t in 2:
		var n: Dictionary = oracle_nodes[t]
		var o: Dictionary = sim.oracles[t]
		var root: Node3D = n.root
		var target := Vector3(o.pos.x, Sim.height_at(o.pos), o.pos.y)
		# Facing (Kevin: "the king is facing the wall"): on his throne he looks out over his base.
		if (o.pos as Vector2).distance_to(Sim.throne(t)) < 1.5:
			root.rotation.y = lerp_angle(root.rotation.y, Sim.angle_of(Sim._m(t, Keep.gate_c(1)) - Sim.throne(t)), 1.0 - exp(-dt * 6.0))
		var pulse := 0.8 + sin(_time * 4.0) * 0.2
		(n.ground as Node3D).scale = Vector3(pulse, 0.15, pulse)
		root.position = target if root.position.distance_to(target) > 5.0 else root.position.lerp(target, 1.0 - exp(-dt * 20.0))

# ---------- projectiles ----------
func _sync_projectiles() -> void:
	var live := {}
	for p in sim.projectiles:
		live[p.id] = true
		var node: Node3D = proj_nodes.get(p.id)
		if node == null:
			node = _make_projectile(str(p.kind))
			if bool(p.get("big", false)):
				node.scale = Vector3.ONE * 2.2             # 0.31.157: the Ranger's DEADEYE
			proj_nodes[p.id] = node
			fxs.proj_trail(node, p)                        # 0.31.201: what it leaves behind it
		# Offline the sim ticks at 30 Hz while frames run at 60: draw it where it is *now*.
		var at: Vector2 = p.pos + (p.vel as Vector2) * proj_lead
		var y := 1.2 + Sim.height_at(at)
		node.position = Vector3(at.x, y, at.y)
		node.rotation = Vector3(0.0, Sim.angle_of(p.vel), 0.0)
		if str(p.kind) == "hammer" or str(p.kind) == "boulder":
			var sp := node.get_node_or_null("spin") as Node3D
			if sp != null:
				sp.rotation.x = Time.get_ticks_msec() * (0.018 if str(p.kind) == "hammer" else 0.012)   # end over end; the boulder rolls
	for id in proj_nodes.keys():
		if not live.has(id):
			proj_nodes[id].queue_free()
			proj_nodes.erase(id)

func _make_projectile(kind: String) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	if kind == "hammer":
		# The Crusader's hammer (0.30.5): a glowing gold head on a wooden handle, spinning end over end.
		var spin := Node3D.new()
		spin.name = "spin"
		root.add_child(spin)
		var handle := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.05
		hm.bottom_radius = 0.06
		hm.height = 0.8
		handle.mesh = hm
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color("#7a4e2a")
		handle.material_override = wood
		spin.add_child(handle)
		var head := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.46, 0.26, 0.26)
		head.mesh = bm
		head.position = Vector3(0.0, 0.4, 0.0)
		var gold := StandardMaterial3D.new()
		gold.albedo_color = Color("#f2c94c")
		gold.emission_enabled = true
		gold.emission = Color("#ffd766")
		gold.emission_energy_multiplier = 1.3
		gold.metallic = 0.6
		gold.roughness = 0.35
		head.material_override = gold
		spin.add_child(head)
		root.scale = Vector3.ONE * 1.25
		return root
	if kind == "pierce":
		# the Sniper's shot (0.31.32): a long arrow with a pale glowing streak behind it
		var pr := Node3D.new()
		var pk := Stage.scene("res://assets/kaykit/weapons/arrow_bow.gltf")
		if pk != null:
			var ar: Node3D = pk.instantiate()
			ar.scale = Vector3(1.6, 1.6, 2.0)
			pr.add_child(ar)
		var streak := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.06
		cm.bottom_radius = 0.0
		cm.height = 3.2
		streak.mesh = cm
		streak.material_override = _fx_mat(Color(0.85, 0.95, 1.0))
		streak.rotation.x = PI * 0.5
		streak.position.z = -1.7
		pr.add_child(streak)
		add_child(pr)
		return pr
	if kind in ["bolt", "ball", "thorn", "boulder"]:
		_make_shot_fx(root, kind)                    # 0.31.168: the new heroes' shots
		return root
	if kind == "arrow":
		var packed := Stage.scene("res://assets/kaykit/weapons/arrow_bow.gltf")
		if packed != null:
			var arrow: Node3D = packed.instantiate()
			# The model already lies along +Z, arrowhead forward (measured: z -0.64..0.62, the narrow end at
			# +Z), and the root turns +Z onto the flight path. The old 90 deg turn about X stood every arrow
			# on its tip (Kevin: "arrows flying sideways instead of straight").
			arrow.scale = Vector3.ONE * 1.3
			root.add_child(arrow)
			return root
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.28 if kind == "fire" else 0.12
	sm.height = sm.radius * 2.0
	ball.mesh = sm
	ball.material_override = _unshaded(_bright(Color(1.0, 0.55, 0.15, 0.95) if kind == "fire" else Color(1, 1, 0.8, 0.9)))
	root.add_child(ball)
	return root

static var _shot_mats := {}

func _shot_mat(key: String, col: Color, glow: float, rough := 0.6) -> StandardMaterial3D:
	if not _shot_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = rough
		if glow > 0.0:
			m.emission_enabled = true
			m.emission = col
			m.emission_energy_multiplier = glow
		_shot_mats[key] = m
	return _shot_mats[key]

func _make_shot_fx(root: Node3D, kind: String) -> void:
	# 0.31.168: the Stormcaller's bolt (a crackling blue streak), the Musketeer's ball (a lead shot and its white trail),
	# the Druid's thorn (a glowing green seed), the Golem's boulder (a carved stone with a cyan rune, rolling)
	match kind:
		"bolt":
			var core := MeshInstance3D.new()
			var cm := CapsuleMesh.new()
			cm.radius = 0.07
			cm.height = 1.1
			core.mesh = cm
			core.rotation.x = PI * 0.5
			core.material_override = _fx_mat(Color(0.85, 0.95, 1.0))
			root.add_child(core)
			var glow := MeshInstance3D.new()
			var gm := CapsuleMesh.new()
			gm.radius = 0.16
			gm.height = 1.4
			glow.mesh = gm
			glow.rotation.x = PI * 0.5
			glow.material_override = _unshaded(Color(0.35, 0.6, 1.0, 0.45))
			root.add_child(glow)
		"ball":
			var ball := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.09
			sm.height = 0.18
			ball.mesh = sm
			ball.material_override = _shot_mat("ball", Color(0.35, 0.36, 0.4), 0.0, 0.3)
			root.add_child(ball)
			var trail := MeshInstance3D.new()
			var tm := CylinderMesh.new()
			tm.top_radius = 0.07
			tm.bottom_radius = 0.0
			tm.height = 1.6
			trail.mesh = tm
			trail.rotation.x = PI * 0.5
			trail.position.z = -0.85
			trail.material_override = _unshaded(Color(1.0, 0.97, 0.9, 0.55))
			root.add_child(trail)
		"thorn":
			var seed := MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = Vector3(0.16, 0.5, 0.16)
			seed.mesh = pm
			seed.rotation.x = PI * 0.5
			seed.material_override = _fx_mat(Color(0.55, 1.0, 0.35))
			root.add_child(seed)
			var halo := MeshInstance3D.new()
			var hm := SphereMesh.new()
			hm.radius = 0.2
			hm.height = 0.4
			halo.mesh = hm
			halo.material_override = _unshaded(Color(0.4, 1.0, 0.3, 0.35))
			root.add_child(halo)
		"boulder":
			var spin := Node3D.new()
			spin.name = "spin"
			root.add_child(spin)
			var rock := MeshInstance3D.new()
			var rm := SphereMesh.new()
			rm.radius = 0.48
			rm.height = 0.9
			rm.radial_segments = 9
			rm.rings = 5
			rock.mesh = rm
			rock.material_override = _shot_mat("boulder", Color("#8d8a82"), 0.0, 0.95)
			spin.add_child(rock)
			var rune := MeshInstance3D.new()
			rune.mesh = _ring_mesh(0.3, 0.06)
			rune.rotation.z = PI * 0.5
			rune.position.x = 0.44
			rune.material_override = _fx_mat(Color("#5fe8ff"))
			spin.add_child(rune)
			spin.position.y = -0.6

# ---------- effects ----------
# No material or text writes per frame here. In Godot's GLES3 renderer every material parameter
# change re-uploads that material's buffer (glBufferData), and changing a Label3D's modulate
# rebuilds its mesh and materials. Field logs showed the Adreno driver hanging after ~5-6k frames
# of that churn, so effects share cached materials and fade by scale only, and damage numbers
# are drawn by the 2D HUD instead of Label3D.
static var _fx_mats: Dictionary = {}
var numbers: Array = []   # [{pos: Vector3, text, mine, at}] read by the HUD

func _fx_mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _fx_mats.has(key):
		_fx_mats[key] = _unshaded(_bright(color))
	return _fx_mats[key]

var _shake := 0.0

func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)

# 0.31.181: a hero recalling -- a violet ring rising round his feet and motes going up, faster as he's nearly gone;
# where he left and where he arrives a flash (on_event "recall_done")
var _recall_t := 0.0
const RECALL_COL := Color("#b9a8ff")

func _sync_recall_fx(dt: float) -> void:
	if sim == null or sim.moba == null:
		return
	_recall_t -= dt
	if _recall_t > 0.0:
		return
	_recall_t = 0.22
	for u in sim.units:
		if not bool(u.get("hero", false)) or not sim.recalling(u):
			continue
		var a: Dictionary = actors.get(str(u.id), {})
		if a.is_empty() or not (a.root as Node3D).visible:
			continue
		var p: Vector3 = (a.root as Node3D).position
		var k := 1.0 - clampf((float(u.recall_until) - float(sim.time)) / sim.RECALL_TIME, 0.0, 1.0)
		ring_at(p + Vector3(0, 0.08, 0), RECALL_COL, 0.6 + 0.8 * k, 0.55)
		for i in 1 + int(k * 3.0):
			spark(p + Vector3(randf_range(-0.5, 0.5), 0.2 + randf() * 1.6, randf_range(-0.5, 0.5)), RECALL_COL)

func ring_at(at: Vector3, color: Color, grow := 2.2, life := 0.6) -> void:
	if low_fx and life < 0.5:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh(0.5, 0.12)
	var c := color
	c.a = 0.85
	mi.material_override = _fx_mat(c)
	mi.position = at + Vector3(0, 0.08, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_fx.append({"node":mi, "at":_time, "life":life, "kind":"ring", "grow":grow})

func spark(at: Vector3, color: Color) -> void:
	if low_fx:
		return
	var mi := MeshInstance3D.new()
	if _spark_mesh == null:
		_spark_mesh = SphereMesh.new()
		_spark_mesh.radius = 0.12
		_spark_mesh.height = 0.24
		_spark_mesh.radial_segments = 6
		_spark_mesh.rings = 3
	mi.mesh = _spark_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _fx_mat(color)
	mi.position = at
	add_child(mi)
	var dir := Vector3(randf_range(-1, 1), randf_range(0.6, 1.6), randf_range(-1, 1))
	_fx.append({"node":mi, "at":_time, "life":0.45, "kind":"spark", "p0":at, "dir":dir})

func number(at: Vector3, text: String, mine: bool, gold := false) -> void:
	numbers.append({"pos":at, "text":text, "mine":mine, "at":_time, "gold":gold})
	if numbers.size() > 40:
		numbers.pop_front()

func _step_fx() -> void:
	for i in range(_fx.size()-1, -1, -1):
		var fx: Dictionary = _fx[i]
		var age := _time - float(fx.at)
		var node: Node3D = fx.node
		if age > float(fx.life) or not is_instance_valid(node):
			if is_instance_valid(node):
				node.queue_free()
			_fx.remove_at(i)
			continue
		var u := age / float(fx.life)
		match str(fx.kind):
			"ring":
				# Grow outward and disappear at the end of its life (no alpha fade).
				var s := 0.4 + u * float(fx.grow)
				node.scale = Vector3(s, 0.3, s)
			"shell":
				var p0: Vector3 = fx.p0
				var p1: Vector3 = fx.p1
				node.position = p0.lerp(p1, u) + Vector3(0, 7.0 * u * (1.0 - u), 0)
				node.rotation.x += 0.25
			"spark":
				node.position = fx.p0 + fx.dir * u * 1.2
				node.scale = Vector3.ONE * maxf(0.05, 1.0 - u)
			"fall":                                     # 0.31.157: an ARROW RAIN arrow
				node.position = (fx.p0 as Vector3).lerp(fx.p1, u)
			"bolt":                                     # 0.31.168: a lightning segment -- thins out and goes
				var w := maxf(0.05, 1.0 - u * u)
				node.scale = Vector3(w, w, 1.0)
	for i in range(numbers.size()-1, -1, -1):
		if _time - float(numbers[i].at) > 0.8:
			numbers.remove_at(i)

# ---------- camera ----------
var cam_override: Array = []   # [eye: Vector3, target: Vector3] for tests/screenshots only

func snap_camera() -> void:
	# Jump straight to the player next frame (after a teleport) instead of gliding across the map.
	_cam_target = Vector3.ZERO

# 0.31.216: the landscape camera (Honor of Kings'): its turn round the map, its tilt, how far it stands from the point it
# looks at, how far ahead of you (up the screen) that point is, its field of view (vertical, 16:9 .. 21:9 phones
# showing more or less across). (Until 0.31.216: portrait, looking straight up the field, 38 m up and 30 m back, fov 50.)
const CAM_YAW := PI / 4.0           # the screen's up, for blue: the world's -y (up the field) turned this far toward -x
const CAM_PITCH := 0.9076         # 52 degrees
const CAM_DIST := 22.0
const CAM_AHEAD := 2.0
const CAM_FOV := 34.0

static func screen_up(team: int) -> Vector2:
	# the world direction (x, z) the top of the screen looks along: blue's keep bottom-left, red's top-right
	var u := Vector2(0.0, -1.0).rotated(-CAM_YAW)
	return u if team == 0 else -u

static func screen_to_world(v: Vector2, team: int) -> Vector2:
	# a direction on the screen (x right, y down) as a world direction (x, z)
	var up := screen_up(team)
	var right := Vector2(-up.y, up.x)
	return right * v.x - up * v.y

func _update_camera(dt: float) -> void:
	if cam_override.size() == 2:
		camera.position = cam_override[0]
		camera.look_at(cam_override[1], Vector3.UP)
		return
	var me: Dictionary = sim.by_id.get(player_id, {})
	var focus := Vector3.ZERO
	var a: Dictionary = actors.get(player_id, {})
	if not a.is_empty():
		focus = a.root.position
	if not me.is_empty() and me.state == "dead" and not a.is_empty():
		# 0.31.22 (Kevin): the camera stays with your body through the countdown (it cut to your spawn) -- with the
		# ragdoll's hips if it has one, so it follows where you were thrown
		var rg = a.get("rag")
		focus = a.root.position
		if rg != null and is_instance_valid(rg.sim):
			for pb in (rg.sim as Node).get_children():
				if pb is PhysicalBone3D and str((pb as PhysicalBone3D).bone_name) == "hips":
					focus = (pb as Node3D).global_position
					focus.y = 0.0
					break
	# 0.31.216 (Kevin: "The game needs to change from vertical to horizontal", Honor of Kings' camera): landscape, turned
	# CAM_YAW so the square map sits square on the screen -- your keep bottom-left, theirs top-right (red's view turned
	# half way round, as before) -- looking down at CAM_PITCH, a little ahead of you (up the screen).
	var up := screen_up(int(me.get("team", 0)))
	var target := focus + Vector3(up.x, 0.0, up.y) * CAM_AHEAD
	_cam_target = target if _cam_target == Vector3.ZERO else _cam_target.lerp(target, 1.0 - exp(-dt * 6.0))
	camera.position = _cam_target + Vector3(-up.x, 0.0, -up.y) * CAM_DIST * cos(CAM_PITCH) + Vector3(0.0, CAM_DIST * sin(CAM_PITCH), 0.0)
	camera.look_at(_cam_target, Vector3.UP)
	if _shake > 0.01:
		# Short camera shake for the tantrum shockwave.
		camera.position += Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * _shake * 0.5
		_shake = maxf(0.0, _shake - dt * 1.6)

var _bar_y := {}                                  # 0.31.160: a tower's / King's bar height (they don't move; was height_at a frame)
const MY_BAR := Color("#7dff8a")

func bars() -> Array:
	# [{pos, fill, color}] for the HUD to draw 2D health bars over living units.
	var out := []
	if sim.moba != null:
		for tw in sim.moba.towers:                 # 0.31.155 5V5: the towers' health (wide)
			if not bool(tw.dead):
				if not _bar_y.has(tw.id):
					_bar_y[tw.id] = Sim.height_at(tw.p) + Towers.height(int(tw.tier)) + 0.5     # (0.31.172: over the new towers)
				out.append({"pos":Vector3(tw.p.x, float(_bar_y[tw.id]), tw.p.y), "fill":clampf(float(tw.hp) / float(tw.max_hp), 0.0, 1.0),
					"color":TEAM_COLORS[vt(int(tw.team))], "wide":true})
		for kt in 2:                               # 0.31.156: the Kings (the hearts)
			if not bool(sim.moba.kings[kt].dead):
				var kp: Vector2 = sim.moba.king_pos(kt)
				if not _bar_y.has("k%d" % kt):
					_bar_y["k%d" % kt] = Sim.height_at(kp) + 3.4
				out.append({"pos":Vector3(kp.x, float(_bar_y["k%d" % kt]), kp.y), "fill":sim.moba.king_frac(kt), "color":Color("#ffd65a"), "wide":true})
	for u in sim.units:
		if u.state == "dead":
			continue
		var a: Dictionary = actors.get(u.id, {})
		if a.is_empty() or not is_instance_valid(a.root) or not (a.root as Node3D).visible:
			continue                                    # (0.31.158: in the fog -- no bar either)
		var c: Color = MY_BAR if u.id == player_id else TEAM_COLORS[vt(int(u.team))]
		var bar := {"pos": (a.root as Node3D).position + Vector3(0, 2.7 * float(u.get("mscale", 1.0)), 0), "fill": clampf(u.hp / maxf(1.0, u.max_hp), 0.0, 1.0), "color": c}
		if u.has("mon") and float(u.get("mscale", 1.0)) > 1.0:
			bar["name"] = str(sim.moba.MONSTERS[str(u.mkind)].name)        # 0.31.157: the buff monsters and the Bone Lord
			bar["name_color"] = Color("#ffe9a6")
			if str(u.mkind) in ["lord", "wyrm"]:
				bar["wide"] = true
		elif bool(u.get("lordling", false)):
			bar["name"] = "Bone Lord"                                       # 0.31.158: marching for a side
			bar["name_color"] = TEAM_COLORS[vt(int(u.team))].lightened(0.3)
			bar["wide"] = true
		if u.id == player_id and my_name != "":
			# 0.31.88 (Kevin: "Show the nameplate for the players own name also"): yours from your profile, so it's there
			# against bots too and doesn't wait on the server
			bar["name"] = ("[%s] %s" % [my_tag, my_name]) if my_tag != "" else my_name
			bar["crest"] = my_crest
			bar["title"] = my_title
			bar["name_color"] = Color("#8cf0a8")       # (0.31.195: yours green -- no yellow text; gold until then)
		elif player_names.has(u.id):
			# 0.31.86 (Kevin: "shows the player names on the battlefield above their heads. Only live players will show
			# names."): over the bar -- yours gold (green since 0.31.195), your side's light blue, theirs light red (0.31.177: bots by their names)
			bar["name"] = str(player_names[u.id])
			if str(player_tags.get(u.id, "")) != "":
				bar["name"] = "[%s] %s" % [str(player_tags[u.id]), str(player_names[u.id])]   # 0.31.134: their clan's tag
				bar["crest"] = str(player_crests.get(u.id, ""))                                # 0.31.196: and crest
			bar["title"] = str(player_titles.get(u.id, ""))
			bar["name_color"] = Color("#8cf0a8") if u.id == player_id else (Color("#bfeeff") if vt(int(u.team)) == 0 else Color("#ffc4b4"))
		elif bool(u.get("hero", false)) and bool(u.get("bot", false)) and sim.moba != null:
			# 0.31.177 (Kevin: "Put the player names above the players so people know if it's player or minion easier. If
			# it's a bot then give bot name like "bot Alfred""): a bot's hero too, by its seat's name, a shade softer
			bar["name"] = sim.moba.bot_label(u)
			bar["name_color"] = Color("#a8dcef") if vt(int(u.team)) == 0 else Color("#f0b4a6")
		out.append(bar)
	return out

func gate_bars() -> Array:
	# Damaged gates (either team) get a health bar over the arch.
	var out := []
	for g in sim.gates:
		if not sim.gate_blocks(g) or g.hp >= g.max_hp:
			continue
		out.append({"pos": Vector3(g.c.x, 4.2, g.c.y), "fill": g.hp / g.max_hp, "color": TEAM_COLORS[vt(int(g.team))]})
	return out

func unit_world(id: String) -> Vector3:
	# 0.31.111: where a unit is drawn (the HUD pins quick chat bubbles over it); INF when there's no such unit
	var a: Dictionary = actors.get(id, {})
	if a.is_empty() or not is_instance_valid(a.root):
		return Vector3.INF
	return (a.root as Node3D).position

func screen_point(world: Vector3) -> Vector2:
	return camera.unproject_position(world)

func is_on_screen(world: Vector3) -> bool:
	return not camera.is_position_behind(world) and Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).has_point(camera.unproject_position(world))


# ---------- cloth capes (0.31.17, Kevin: "realistic cloth physics for the capes"; 0.31.18: "floating capes ... very
# jittery") ----------
# The Knight, Mage, Ranger and both Rogues wear a cape (a skinned 56-vertex mesh in the KayKit models, rigid on the
# torso). Near the camera it hangs from a small spring grid -- CAPE_COLS x CAPE_ROWS points, the top row pinned across
# the shoulders to the chest bone, the rest falling under gravity with a little wind, held by stretch and bend links,
# kept behind the back, outside the torso and above the ground -- stepped at a fixed 30 Hz and eased onto the screen.
# The cape mesh itself is bent by the grid in its vertex shader, so there is no separate cloth object to be left
# behind (0.31.17's floating capes) and no mesh rebuilt each frame (its cost on phones).
const CAPE_COLS := 3
const CAPE_ROWS := 4
const CAPE_NEAR := 32.0          # ground distance from the camera
const CAPE_GRAVITY := 7.5
const CAPE_DAMP := 0.9
const CAPE_ITERS := 2
const CAPE_STEP := 1.0 / 30.0
const CAPE_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness = 0.5;
uniform vec3 offs[12];
void vertex() {
	// model-space position -> place on the 3 x 4 grid (shoulders at y 1.2, hem at 0.12, 0.94 m across)
	float u = clamp((VERTEX.x + 0.47) / 0.94, 0.0, 1.0) * 2.0;
	float v = clamp((1.2 - VERTEX.y) / 1.08, 0.0, 1.0) * 3.0;
	int c0 = int(min(floor(u), 1.0));
	int r0 = int(min(floor(v), 2.0));
	float fu = u - float(c0);
	float fv = v - float(r0);
	vec3 a = mix(offs[r0 * 3 + c0], offs[r0 * 3 + c0 + 1], fu);
	vec3 b = mix(offs[(r0 + 1) * 3 + c0], offs[(r0 + 1) * 3 + c0 + 1], fu);
	VERTEX += mix(a, b, fv);
}
void fragment() {
	vec4 t = texture(albedo_tex, UV) * albedo;
	ALBEDO = t.rgb;
	ROUGHNESS = roughness;
}
"""
static var _cape_shader: Shader = null
static var cape_usec := 0           # time spent in cloth this session (diag/tests)
static var cape_active := 0

func _cape_setup(a: Dictionary) -> void:
	a["cape"] = null
	var body: Node3D = a.body
	var orig: MeshInstance3D = null
	for c in body.find_children("*_Cape", "MeshInstance3D", true, false):
		orig = c
		break
	var skel: Skeleton3D = body.find_child("Skeleton3D", true, false)
	if orig == null or skel == null or skel.find_bone("chest") < 0:
		return
	if _cape_shader == null:
		_cape_shader = Shader.new()
		_cape_shader.code = CAPE_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = _cape_shader
	var src = orig.get_active_material(0)
	if src is BaseMaterial3D:
		sm.set_shader_parameter("albedo_tex", (src as BaseMaterial3D).albedo_texture)
		sm.set_shader_parameter("albedo", (src as BaseMaterial3D).albedo_color)
		sm.set_shader_parameter("roughness", (src as BaseMaterial3D).roughness)
	var zero := PackedVector3Array()
	zero.resize(CAPE_COLS * CAPE_ROWS)
	sm.set_shader_parameter("offs", zero)
	orig.material_override = sm
	var rest := PackedVector3Array()
	for r in CAPE_ROWS:
		var fv := float(r) / float(CAPE_ROWS - 1)
		for c2 in CAPE_COLS:
			var fu := float(c2) / float(CAPE_COLS - 1)
			var half := lerpf(0.40, 0.47, fv)
			rest.append(Vector3(lerpf(-half, half, fu), lerpf(1.2, 0.12, fv), lerpf(-0.08, -0.36, fv)))
	var chest := skel.find_bone("chest")
	a["cape"] = {"skel":skel, "chest":chest, "b0i":skel.get_bone_global_rest(chest).affine_inverse(), "rest":rest,
		"pos":PackedVector3Array(), "prev":PackedVector3Array(), "shown":zero.duplicate(), "mat":sm, "on":false, "acc":0.0}

func _cape_step(a: Dictionary, dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_cape_step_inner(a, dt)
	cape_usec += Time.get_ticks_usec() - t0

func _cape_step_inner(a: Dictionary, dt: float) -> void:
	var cp: Dictionary = a.cape
	var skel: Skeleton3D = cp.skel
	if not is_instance_valid(skel):
		a["cape"] = null
		return
	var ap: Vector3 = (a.root as Node3D).global_position
	var cpos: Vector3 = camera.global_position if is_instance_valid(camera) else ap
	var near := Vector2(ap.x - cpos.x, ap.z - cpos.z).length() < CAPE_NEAR and skel.is_visible_in_tree()
	var n := CAPE_COLS * CAPE_ROWS
	if not near:
		if bool(cp.on):                                  # back to the plain cape
			cp.on = false
			var z := PackedVector3Array()
			z.resize(n)
			cp.shown = z
			(cp.mat as ShaderMaterial).set_shader_parameter("offs", z)
		return
	var model: Transform3D = skel.global_transform
	var rig_m: Transform3D = skel.get_bone_global_pose(int(cp.chest)) * (cp.b0i as Transform3D)   # model space, rigid on the chest
	var rig: Transform3D = model * rig_m
	var rest: PackedVector3Array = cp.rest
	var pos: PackedVector3Array = cp.pos
	var prev: PackedVector3Array = cp.prev
	if not bool(cp.on) or pos.size() != n:
		pos.resize(n)
		prev.resize(n)
		for i in n:
			pos[i] = rig * rest[i]
			prev[i] = pos[i]
		cp.on = true
		cp.acc = 0.0
	# fixed 30 Hz steps (frame times vary on phones; a variable step made it shiver)
	cp.acc = minf(float(cp.acc) + dt, CAPE_STEP * 3.0)
	var h2 := CAPE_STEP * CAPE_STEP
	var inv := rig.affine_inverse()
	var ground := ap.y + 0.03
	var wind := Vector3(sin(_time * 1.3 + float(int(cp.chest) + rest.size())) * 0.8, 0.0, cos(_time * 0.9) * 0.5)
	while float(cp.acc) >= CAPE_STEP:
		cp.acc = float(cp.acc) - CAPE_STEP
		for i in n:
			if i < CAPE_COLS:
				prev[i] = pos[i]
				pos[i] = rig * rest[i]                         # pinned across the shoulders
				continue
			var p: Vector3 = pos[i]
			var v: Vector3 = (p - prev[i]) * CAPE_DAMP
			prev[i] = p
			pos[i] = p + v + (Vector3(0.0, -CAPE_GRAVITY, 0.0) + wind) * h2
		for it in CAPE_ITERS:
			for r in CAPE_ROWS:
				for c in CAPE_COLS:
					var i := r * CAPE_COLS + c
					if c + 1 < CAPE_COLS:
						_cape_link(pos, rest, i, i + 1, r == 0)
					if r + 1 < CAPE_ROWS:
						_cape_link(pos, rest, i, i + CAPE_COLS, r == 0)
					if r + 2 < CAPE_ROWS:
						_cape_link(pos, rest, i, i + 2 * CAPE_COLS, r == 0)
			for i in range(CAPE_COLS, n):
				var m: Vector3 = inv * pos[i]
				var moved := false
				if m.z > -0.07:
					m.z = -0.07
					moved = true
				var rxz := Vector2(m.x, m.z)
				if m.y > 0.05 and m.y < 1.3 and rxz.length() < 0.3:
					rxz = rxz.normalized() * 0.3 if rxz.length() > 0.001 else Vector2(0.0, -0.3)
					m.x = rxz.x
					m.z = rxz.y
					moved = true
				if moved:
					pos[i] = rig * m
				if pos[i].y < ground:
					pos[i].y = ground
	cp.pos = pos
	cp.prev = prev
	# the bend each point makes, in the cape's model space, eased onto the screen
	var inv_model := model.affine_inverse()
	var shown: PackedVector3Array = cp.shown
	var k := 1.0 - exp(-dt * 30.0)
	for i in n:
		var off: Vector3 = inv_model * pos[i] - rig_m * rest[i]
		shown[i] = shown[i].lerp(off, k)
	cp.shown = shown
	(cp.mat as ShaderMaterial).set_shader_parameter("offs", shown)
	cape_active += 1

func _cape_link(pos: PackedVector3Array, rest: PackedVector3Array, i: int, j: int, pin_i: bool) -> void:
	var d: Vector3 = pos[j] - pos[i]
	var l := d.length()
	if l < 0.0001:
		return
	var want: float = rest[i].distance_to(rest[j])
	var corr := d * ((l - want) / l)
	if pin_i:
		pos[j] -= corr                                     # the shoulder end doesn't move
	else:
		pos[i] += corr * 0.5
		pos[j] -= corr * 0.5


func _blast_bodies(at2: Vector2, radius: float, speed: float) -> void:
	# 0.31.21: the dead and the loose weapons lying round a blast are thrown by it
	var at := Vector3(at2.x, Sim.height_at(at2), at2.y)
	for a in _ragdolls:
		var rg = a.get("rag")
		if rg == null or not is_instance_valid(rg.sim):
			continue
		for pb in (rg.sim as Node).get_children():
			if not (pb is PhysicalBone3D):
				continue
			var d: Vector3 = (pb as Node3D).global_position - at
			var dist := Vector2(d.x, d.z).length()
			if dist > radius:
				continue
			var dir := Vector3(d.x, 0.0, d.z).normalized() if dist > 0.05 else Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).normalized()
			var f := speed * (1.0 - 0.6 * dist / radius)
			(pb as PhysicalBone3D).linear_velocity += dir * f + Vector3(0.0, f * 0.7, 0.0)
			(pb as PhysicalBone3D).angular_velocity += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * f
	for db in _debris:
		var rb = db.node
		if not is_instance_valid(rb):
			continue
		var d2: Vector3 = (rb as Node3D).global_position - at
		var dist2 := Vector2(d2.x, d2.z).length()
		if dist2 > radius:
			continue
		var dir2 := Vector3(d2.x, 0.0, d2.z).normalized() if dist2 > 0.05 else Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).normalized()
		var f2 := speed * 1.2 * (1.0 - 0.6 * dist2 / radius)
		(rb as RigidBody3D).sleeping = false
		(rb as RigidBody3D).linear_velocity += dir2 * f2 + Vector3(0.0, f2 * 0.8, 0.0)
		(rb as RigidBody3D).angular_velocity += Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))

func _kick_debris() -> void:
	# loose weapons are kicked along by whoever walks into them
	if _debris.is_empty():
		return
	# (0.31.160: each actor's place once a frame -- it was looked up for every weapon on the ground, for every actor)
	var walkers := []
	for a in actors.values():
		if not (a.get("dead", false) or a.get("rag") != null) and (a.root as Node3D).visible:
			walkers.append(a)
	for db in _debris:
		var rb = db.node
		if not is_instance_valid(rb):
			continue
		var wp: Vector3 = (rb as Node3D).position         # (both the view's children: its own space)
		for a in walkers:
			var ap: Vector3 = (a.root as Node3D).position
			var d := Vector2(wp.x - ap.x, wp.z - ap.z)
			if d.length() > 0.62 or absf(wp.y - ap.y) > 1.2:
				continue
			var lp: Vector3 = a.get("kick_last", ap)
			var mv := Vector2(ap.x - lp.x, ap.z - lp.z)
			if mv.length() < 0.004:
				continue
			var dir := (d.normalized() * 0.5 + mv.normalized() * 0.5).normalized()
			(rb as RigidBody3D).sleeping = false
			(rb as RigidBody3D).linear_velocity = Vector3(dir.x * 3.2, 1.0, dir.y * 3.2)
			(rb as RigidBody3D).angular_velocity += Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
	for a in actors.values():
		a["kick_last"] = (a.root as Node3D).position

# ---------- the EffectBlocks explosions (0.31.57, Kevin) ----------
# The pack's heavy explosion (fireball, sparks, rolling smoke, burning debris with smoke trails) on the bomb and the
# meteor, its light one (a small pop, sparks, puffs) on catapult stones. Copies in assets/vfx/effectblocks without the
# pack's demo script and sound. Every emitter is switched to local coordinates so the node's scale sizes the whole
# effect; half the particles on low effects; freed when the longest emitter is done.
static var _fire_cool: ParticleProcessMaterial = null
const PACK_EXPLOSIONS := {"heavy": preload("res://assets/vfx/effectblocks/explosion_heavy.tscn"),
	"light": preload("res://assets/vfx/effectblocks/explosion_light.tscn")}

func _pack_explosion(kind: String, at: Vector3, size: float, own_smoke := false) -> void:
	var n: Node3D = (PACK_EXPLOSIONS[kind] as PackedScene).instantiate()
	if own_smoke and n.has_node("Smoke"):
		n.get_node("Smoke").free()                    # 0.31.59: our physical smoke replaces the pack's smoke
	if own_smoke and n.has_node("Fire"):
		# the pack's fireball cools to an opaque near-black ball; ours cools to a thin grey and fades, handing over to
		# the smoke cloud
		var fire := n.get_node("Fire") as GPUParticles3D
		if _fire_cool == null:
			_fire_cool = (fire.process_material as ParticleProcessMaterial).duplicate()
			var g := Gradient.new()
			g.offsets = PackedFloat32Array([0.0, 0.16, 0.3, 0.55])
			g.colors = PackedColorArray([Color(0.95, 0.5, 0.0, 1.0), Color(0.85, 0.27, 0.04, 1.0), Color(0.3, 0.26, 0.23, 0.5), Color(0.34, 0.33, 0.32, 0.0)])
			var gt := GradientTexture1D.new()
			gt.gradient = g
			_fire_cool.color_ramp = gt
		fire.process_material = _fire_cool
	n.position = at
	n.scale = Vector3.ONE * size
	add_child(n)
	var life := 0.5
	for gp in n.find_children("*", "GPUParticles3D", true, false):
		var p3 := gp as GPUParticles3D
		p3.local_coords = true
		if low_fx:
			p3.amount_ratio = 0.5
		life = maxf(life, p3.lifetime * 1.6)
		p3.restart()
	get_tree().create_timer(life + 0.5).timeout.connect(n.queue_free)

# ---------- physical smoke (0.31.59, Kevin: realistic, physics-based smoke that lingers after explosions) ----------
# A one-shot GPU particle cloud per blast: puffs (a generated, lumpy smoke texture) are thrown out of a sphere at the
# blast, slowed hard by air drag (damping), lifted by buoyancy and pushed by a steady breeze (both as gravity), and
# stirred by a turbulence noise field so the cloud boils and curls instead of moving in straight lines. Each puff swells
# as it rises, turns slowly, starts dark and fire-warm, then thins to a pale grey and fades -- the cloud lingers for
# 8-10 s. Depth-sorted, soft where it meets the ground (proximity fade), no shadows; 40 % of the puffs on low effects.
const SMOKE_TEX := preload("res://assets/vfx/smoke/smoke_puff.png")
const SMOKE_WIND := Vector3(0.45, 0.0, 0.18)
static var _smoke_draw: StandardMaterial3D = null

static func _smoke_draw_mat() -> StandardMaterial3D:
	if _smoke_draw == null:
		var m := StandardMaterial3D.new()
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = SMOKE_TEX
		m.proximity_fade_enabled = true
		m.proximity_fade_distance = 1.4
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_smoke_draw = m
	return _smoke_draw

func smoke_cloud(at: Vector3, size: float, amount: int, life: float) -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.1 * size
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 80.0
	pm.initial_velocity_min = 2.6 * size
	pm.initial_velocity_max = 6.5 * size
	pm.damping_min = 2.4 * size                       # air drag: the blast's push dies within a second or so
	pm.damping_max = 3.6 * size
	pm.gravity = Vector3(0.0, 0.55, 0.0) + SMOKE_WIND  # buoyancy up, the breeze sideways
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.8
	pm.turbulence_noise_scale = 3.2 * size
	pm.turbulence_noise_speed = Vector3(0.15, 0.3, 0.1)
	pm.turbulence_noise_speed_random = 0.3
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.16
	pm.lifetime_randomness = 0.35
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -14.0
	pm.angular_velocity_max = 14.0
	pm.scale_min = 2.0 * size
	pm.scale_max = 3.4 * size
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.35))
	sc.add_point(Vector2(0.2, 0.85))
	sc.add_point(Vector2(1.0, 1.45))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.04, 0.12, 0.45, 1.0])
	g.colors = PackedColorArray([Color(0.55, 0.32, 0.16, 0.0), Color(0.42, 0.28, 0.2, 0.92), Color(0.24, 0.23, 0.22, 0.9),
		Color(0.42, 0.41, 0.4, 0.62), Color(0.62, 0.62, 0.62, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	var gi := Gradient.new()                          # each puff a little lighter or darker than the next
	gi.colors = PackedColorArray([Color(0.82, 0.82, 0.82), Color(1.12, 1.1, 1.08)])
	var git := GradientTexture1D.new()
	git.gradient = gi
	pm.color_initial_ramp = git
	var p := GPUParticles3D.new()
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = _smoke_draw_mat()
	p.draw_pass_1 = q
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.85
	p.randomness = 0.4
	p.fixed_fps = 30
	p.interpolate = true
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-22, -4, -22) * size, Vector3(44, 34, 44) * size)
	if low_fx:
		p.amount_ratio = 0.4
	p.position = at
	add_child(p)
	p.restart()
	get_tree().create_timer(life * 1.4 + 1.0).timeout.connect(p.queue_free)

# ---------- shockwave (0.31.56, Kevin: the EffectBlocks pack's shockwave on the bomb and meteor blasts) ----------
# The pack's effect (assets/other/shockwave.tscn): one torus, inner 0.8 / outer 1.0, triangular section, growing from
# nothing to its full size over 0.74 s on an ease-in curve, drawn with its screen-distortion shader (in
# assets/vfx/effectblocks/shockwave.gdshader, adapted to bend round the ring's own centre; distortion 0.1, noise 0.273
# as in its material). Here it's a plain
# MeshInstance3D animated in _sync_shocks (one particle never needed a particle system), sized to each blast, and
# skipped on low effects (the screen copy it reads costs a little on phones).
const SHOCK_SHADER := preload("res://assets/vfx/effectblocks/shockwave.gdshader")
const SHOCK_LIFE := 0.74
static var _shock_mat: ShaderMaterial = null
static var _shock_mesh: TorusMesh = null
var _shocks: Array = []

func shockwave(at: Vector3, radius: float, delay := 0.0) -> void:
	if low_fx:
		return
	if _shock_mat == null:
		_shock_mat = ShaderMaterial.new()
		_shock_mat.shader = SHOCK_SHADER
		_shock_mat.set_shader_parameter("distortion_intensity", 0.1)
		_shock_mat.set_shader_parameter("noise_influence", 0.273)
		_shock_mesh = TorusMesh.new()
		_shock_mesh.inner_radius = 0.8
		_shock_mesh.outer_radius = 1.0
		_shock_mesh.rings = 40
		_shock_mesh.ring_segments = 3
	var mi := MeshInstance3D.new()
	mi.mesh = _shock_mesh
	mi.material_override = _shock_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	mi.scale = Vector3.ONE * 0.001
	mi.visible = false
	add_child(mi)
	_shocks.append({"node":mi, "t0":_time + delay, "r":radius})

func _sync_shocks() -> void:
	for i in range(_shocks.size() - 1, -1, -1):
		var sh: Dictionary = _shocks[i]
		var mi: MeshInstance3D = sh.node
		var t: float = (_time - float(sh.t0)) / SHOCK_LIFE
		if t >= 1.0 or not is_instance_valid(mi):
			if is_instance_valid(mi):
				mi.queue_free()
			_shocks.remove_at(i)
			continue
		if t < 0.0:
			continue
		mi.visible = true
		# the pack's scale curve: (0,0) leaving at slope 0.227, (1,1) arriving at 1.392 -- a cubic Hermite
		var c := (2.0*t*t*t - 3.0*t*t + 1.0) * 0.0 + (t*t*t - 2.0*t*t + t) * 0.227 + (-2.0*t*t*t + 3.0*t*t) * 1.0 + (t*t*t - t*t) * 1.392
		mi.scale = Vector3.ONE * maxf(0.001, float(sh.r) * c)
		mi.set_instance_shader_parameter("fade", 1.0 - t * t)

# ---------- ragdolls and dropped weapons (0.31.20, Kevin: "ragdoll physics so when they die they fall to the ground
# in a way that they were killed"; "when a player dies their weapons fall on the ground too") ----------
# A death near the camera turns the body into a ragdoll: 11 physics bodies on the KayKit skeleton (hips, chest, head,
# upper and lower arms and legs) joined by cones (hips, shoulders, neck) and hinges (elbows, knees), thrown with the
# killing blow's push from the sim (a sword: back from the killer; an arrow or hammer: the way it flew; a bomb or a
# catapult stone: up and away from the blast) and tumbling. The ground under it is a small height-field patch sampled
# from the land (castle floors included). The weapons in his hands come loose as rigid bodies thrown the same way.
# All of it is freed when he respawns; at most RAG_MAX at once (the oldest is let go).
const RAG_MAX := 8
const RAG_NEAR := 40.0
const RAG_SPEC := [
	# bone, child bone (for its length), radius, joint (0 none, 1 cone, 2 hinge), mass
	["hips", "spine", 0.24, 0, 3.0], ["chest", "head", 0.27, 1, 3.0], ["head", "", 0.4, 1, 2.0],
	["upperarm.l", "lowerarm.l", 0.08, 1, 0.6], ["lowerarm.l", "wrist.l", 0.07, 2, 0.5],
	["upperarm.r", "lowerarm.r", 0.08, 1, 0.6], ["lowerarm.r", "wrist.r", 0.07, 2, 0.5],
	["upperleg.l", "lowerleg.l", 0.1, 1, 0.9], ["lowerleg.l", "foot.l", 0.09, 2, 0.7],
	["upperleg.r", "lowerleg.r", 0.1, 1, 0.9], ["lowerleg.r", "foot.r", 0.09, 2, 0.7]]
var _ragdolls: Array = []
var _debris: Array = []

var _patch_h := {}                       # 0.31.160: the land's height at whole metres, for the ragdolls' ground patches

func _ground_patch(c: Vector3, half: int = 7) -> StaticBody3D:
	# 0.31.160: sampled at the whole metres the patch sits on (it was offset by the death spot's fractions: up to half a
	# metre off) and remembered -- a patch is 169 or 441 Sim.height_at, ~6 us each here and several times that on the
	# phone, for every death in view; a wave's deaths keep landing on the same few metres of lane
	var hm := HeightMapShape3D.new()
	var w := half * 2 + 1
	hm.map_width = w
	hm.map_depth = w
	var data := PackedFloat32Array()
	data.resize(w * w)
	var cx := int(roundf(c.x))
	var cz := int(roundf(c.z))
	if _patch_h.size() > 40000:
		_patch_h.clear()
	for zi in w:
		for xi in w:
			var k := Vector2i(cx + xi - half, cz + zi - half)
			var h = _patch_h.get(k)
			if h == null:
				h = Sim.height_at(Vector2(k))
				_patch_h[k] = h
			data[zi * w + xi] = h
	hm.map_data = data
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = hm
	sb.add_child(cs)
	sb.position = Vector3(float(cx), 0.0, float(cz))
	sb.physics_material_override = PhysicsMaterial.new()
	sb.physics_material_override.friction = 0.9
	add_child(sb)
	return sb

func _ragdoll(a: Dictionary, push: Vector3) -> void:
	if a.get("rag") != null or a.get("body") == null:
		return
	var root: Node3D = a.root
	if is_instance_valid(camera) and Vector2(root.global_position.x - camera.global_position.x, root.global_position.z - camera.global_position.z).length() > RAG_NEAR:
		return
	var skel: Skeleton3D = (a.body as Node3D).find_child("Skeleton3D", true, false)
	if skel == null:
		return
	while _ragdolls.size() >= RAG_MAX:
		_ragdoll_end(_ragdolls[0])
	var sim3 := PhysicalBoneSimulator3D.new()
	skel.add_child(sim3)
	var bones: Array = []
	for sp in RAG_SPEC:
		var bi := skel.find_bone(str(sp[0]))
		if bi < 0:
			continue
		var length := 0.6
		var dir := Vector3.UP
		if str(sp[1]) != "":
			var ci := skel.find_bone(str(sp[1]))
			if ci >= 0:
				var co: Vector3 = skel.get_bone_rest(ci).origin
				length = maxf(co.length(), 0.05)
				dir = co / length
		var pb := PhysicalBone3D.new()
		pb.bone_name = str(sp[0])
		var r: float = sp[2]
		var basis := Basis(Quaternion(Vector3.UP, dir)) if dir.distance_to(Vector3.UP) > 0.001 else Basis()
		var reach := length * 0.5 if str(sp[0]) != "head" else 0.42
		pb.body_offset = Transform3D(basis, dir * reach)
		pb.joint_offset = Transform3D(Basis(), Vector3(0.0, -reach, 0.0))
		var cs := CollisionShape3D.new()
		if str(sp[0]) == "head":
			var sph := SphereShape3D.new()
			sph.radius = r
			cs.shape = sph
		else:
			var cap := CapsuleShape3D.new()
			cap.radius = r
			cap.height = maxf(length, r * 2.0 + 0.02)
			cs.shape = cap
		pb.add_child(cs)
		pb.mass = float(sp[4])
		pb.friction = 0.85
		pb.bounce = 0.05
		pb.linear_damp = 0.6
		pb.angular_damp = 1.6
		match int(sp[3]):
			1:
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			2:
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
			_:
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
		sim3.add_child(pb)
		if int(sp[3]) == 1:
			pb.set("joint_constraints/swing_span", 50.0)
			pb.set("joint_constraints/twist_span", 25.0)
		elif int(sp[3]) == 2:
			pb.set("joint_constraints/angular_limit_enabled", true)
			pb.set("joint_constraints/angular_limit_upper", 0.0)
			pb.set("joint_constraints/angular_limit_lower", -110.0)
		bones.append(pb)
	if bones.is_empty():
		sim3.queue_free()
		return
	var ground := _ground_patch(root.global_position, 10)       # room for the throw (a bomb carries them ~4 m)
	if a.get("player") != null:
		(a.player as AnimationPlayer).pause()
	sim3.physical_bones_start_simulation()
	var spin := push.length() * 0.9
	for pb in bones:
		(pb as PhysicalBone3D).linear_velocity = push + Vector3(randf_range(-0.4, 0.4), randf_range(0.0, 0.3), randf_range(-0.4, 0.4))
		(pb as PhysicalBone3D).angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spin
	(a.ring as MeshInstance3D).visible = false
	a["rag"] = {"sim":sim3, "ground":ground, "t0":_time}
	_ragdolls.append(a)

func _ragdoll_end(a: Dictionary) -> void:
	var rg = a.get("rag")
	if rg == null:
		return
	if is_instance_valid(rg.sim):
		(rg.sim as PhysicalBoneSimulator3D).physical_bones_stop_simulation()
		(rg.sim as Node).queue_free()
	if is_instance_valid(rg.ground):
		(rg.ground as Node).queue_free()
	a["rag"] = null
	if a.get("player") != null and is_instance_valid(a.player):
		(a.player as AnimationPlayer).play()
	_ragdolls.erase(a)

func _drop_weapons(a: Dictionary, push: Vector3) -> void:
	# whatever he held comes loose: each weapon or shield becomes a tumbling rigid body thrown with him
	if a.get("body") == null:
		return
	var root: Node3D = a.root
	if is_instance_valid(camera) and Vector2(root.global_position.x - camera.global_position.x, root.global_position.z - camera.global_position.z).length() > RAG_NEAR:
		return
	var ground: StaticBody3D = null
	for slot in (a.body as Node3D).find_children("*", "BoneAttachment3D", true, false):
		if not str((slot as BoneAttachment3D).bone_name).begins_with("handslot"):
			continue
		for w in (slot as Node3D).get_children():
			if not (w is Node3D) or not (w as Node3D).visible:
				continue
			var aabb := _node_aabb(w as Node3D)
			if aabb.size.length() < 0.05:
				continue
			if ground == null:
				ground = _ground_patch(root.global_position, 6)
			var rb := RigidBody3D.new()
			var gt: Transform3D = (w as Node3D).global_transform
			var copy := (w as Node3D).duplicate() as Node3D
			rb.add_child(copy)
			copy.transform = Transform3D(gt.basis, Vector3.ZERO)
			var cs := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			bx.size = Vector3(maxf(aabb.size.x, 0.08), maxf(aabb.size.y, 0.08), maxf(aabb.size.z, 0.08)) * gt.basis.get_scale()
			cs.shape = bx
			cs.transform = Transform3D(gt.basis.orthonormalized(), gt.basis * aabb.get_center())
			rb.add_child(cs)
			rb.mass = 0.8
			rb.physics_material_override = PhysicsMaterial.new()
			rb.physics_material_override.bounce = 0.2
			rb.physics_material_override.friction = 0.7
			add_child(rb)
			rb.global_position = gt.origin
			rb.linear_velocity = push * 1.1 + Vector3(randf_range(-0.8, 0.8), 1.2 + randf(), randf_range(-0.8, 0.8))
			rb.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
			(w as Node3D).visible = false
			_debris.append({"node":rb, "ground":ground, "t0":_time, "id":str(a.get("id", ""))})
	# loose weapons lie a while, then go (with their bit of ground)
	for i in range(_debris.size() - 1, -1, -1):
		if _time - float(_debris[i].t0) > 30.0 or _debris.size() > 24:
			var d: Dictionary = _debris[i]
			if is_instance_valid(d.node):
				(d.node as Node).queue_free()
			if is_instance_valid(d.ground) and _debris.filter(func(x): return x.ground == d.ground).size() <= 1:
				(d.ground as Node).queue_free()
			_debris.remove_at(i)

func _node_aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false) + ([n] if n is MeshInstance3D else []):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var b := n.global_transform.affine_inverse() * mi.global_transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


# ---------- the upgrades' new abilities in the view (0.31.32) ----------
func _sync_vanish(a: Dictionary, u: Dictionary) -> void:
	# an Assassin in Vanish: almost nothing for the enemy (8 % opaque), a ghost for his own side (45 %); ring hidden from
	# the enemy. Each mesh gets a see-through copy of its material while it lasts (GeometryInstance3D.transparency
	# didn't show on the phone renderer in the check render).
	var v: bool = sim.vanished(u)
	var want: float = 0.0
	if v:
		want = 0.55 if int(u.team) == int(sim.by_id.get(player_id, {}).get("team", 0)) else 0.92
	var on: bool = bool(a.get("vanish_on", false))
	if v and not on:
		a["vanish_on"] = true
		for mi in (a.body as Node3D).find_children("*", "MeshInstance3D", true, false):
			var m3 := mi as MeshInstance3D
			if m3.mesh == null:
				continue
			for si in m3.mesh.get_surface_count():
				var base: Material = m3.get_active_material(si)
				if base is BaseMaterial3D:
					var ghost := (base as BaseMaterial3D).duplicate() as BaseMaterial3D
					ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					ghost.albedo_color.a = 1.0 - want
					m3.set_meta("vanish_prev_%d" % si, m3.get_surface_override_material(si))
					m3.set_surface_override_material(si, ghost)
		if want > 0.9:
			(a.ring as MeshInstance3D).visible = false
	elif not v and on:
		a["vanish_on"] = false
		for mi in (a.body as Node3D).find_children("*", "MeshInstance3D", true, false):
			var m3 := mi as MeshInstance3D
			if m3.mesh == null:
				continue
			for si in m3.mesh.get_surface_count():
				if m3.has_meta("vanish_prev_%d" % si):
					m3.set_surface_override_material(si, m3.get_meta("vanish_prev_%d" % si))
					m3.remove_meta("vanish_prev_%d" % si)
	elif v and want > 0.9:
		(a.ring as MeshInstance3D).visible = false

var _meteors_fx: Array = []

func _meteor_warn(p2: Vector2, delay: float, team: int) -> void:
	var at := Vector3(p2.x, Sim.height_at(p2), p2.y)
	var ring := _decal(at + Vector3(0.0, 0.05, 0.0), Sim.METEOR_R, Color(1.0, 0.35, 0.15), 0.6)
	ring.visible = false                                        # (0.31.201: spell_fx.gd draws the warning, runes turning)
	var rock := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.9
	sm.height = 1.8
	sm.radial_segments = 10
	sm.rings = 6
	rock.mesh = sm
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.35, 0.18, 0.1)
	mm.emission_enabled = true
	mm.emission = Color(1.0, 0.45, 0.12)
	mm.emission_energy_multiplier = 2.5
	rock.material_override = mm
	var from := at + Vector3(7.0, 28.0, 5.0)
	rock.position = from
	add_child(rock)
	fxs.meteor_trail(rock)                                      # 0.31.201: fire and smoke streaming off it
	_meteors_fx.append({"ring":ring, "rock":rock, "from":from, "to":at, "t0":_time, "dur":delay})

func _meteor_hit(p2: Vector2, burn: float) -> void:
	var at := Vector3(p2.x, Sim.height_at(p2) + 0.4, p2.y)
	shockwave(at, Sim.METEOR_R + 1.2)                                          # 0.31.56
	_pack_explosion("heavy", Vector3(at.x, at.y - 0.2, at.z), 3.4, true)      # 0.31.57 (0.31.58: a bit larger)
	smoke_cloud(at, 1.05, 34, 7.5)                                         # 0.31.59
	ring_at(at, Color(1.0, 0.5, 0.15), Sim.METEOR_R * 1.3, 0.6)
	shake(0.5)
	_blast_bodies(p2, Sim.METEOR_R + 1.5, 5.0)
	water_blast(p2, 0.7)
	_meteors_fx.append({"burn_at":at, "until":_time + burn})

func _sync_meteor_fx(dt: float) -> void:
	for i in range(_meteors_fx.size() - 1, -1, -1):
		var m: Dictionary = _meteors_fx[i]
		if m.has("rock"):
			var k := clampf((_time - float(m.t0)) / maxf(float(m.dur), 0.01), 0.0, 1.0)
			if is_instance_valid(m.rock):
				(m.rock as Node3D).position = (m.from as Vector3).lerp(m.to, k * k)
				pass
			if is_instance_valid(m.ring):
				(m.ring as Node3D).scale = Vector3(1.0, 0.15, 1.0) * (0.8 + 0.2 * sin(_time * 18.0))
			if k >= 1.0:
				if is_instance_valid(m.rock):
					(m.rock as Node).queue_free()
				if is_instance_valid(m.ring):
					(m.ring as Node).queue_free()
				_meteors_fx.remove_at(i)
		else:
			if _time >= float(m.until):
				_meteors_fx.remove_at(i)
				continue
			pass                                          # (0.31.201: the burning ground is spell_fx.gd's fire disc)


var _recent_blasts: Array = []        # [pos, time]: items appearing next to one pop higher