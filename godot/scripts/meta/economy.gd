extends RefCounted
# Fatebound Siege economy: currencies, levels, Siege Pass, challenges, shop rotation, cosmetics and
# match rewards. Pure data + pure functions (no I/O) so it is easy to test and tune; the player's
# state lives in scripts/meta/profile.gd.
#
# Everything sold is cosmetic -- but the 5v5's six sold heroes (0.31.168 for gold; 0.31.185, League's way, for gems too:
# HERO_GEMS), each also earned with gold from playing, and twelve heroes everyone's. The store listing's "Everything you
# unlock is cosmetic" line needs Kevin's rewording (store-listing/listing/STORE_LISTING.md).
# 0.31.188 (Kevin: "Remove the forge and the individual weapon skins. I only want the cosmetics to be an entire outfit.
# Each outfit has its own specific looking weapon"): the 75 weapons (CATALOG), the Arsenal packs, the shop's daily and
# featured weapons, the Forge (stars, elements, Embers' heir) are gone. The only cosmetics are outfits (SKINS): a hero's
# whole look -- his body repainted and a weapon of its own -- bought for gems. Titles (earned name tags) stay. What gave
# weapons gives gold, gems, hero shards and chests: chests, the pass's item tiers, a quest's last step, the starter pack
# (a Hero Token). Owned weapons and Forge stars simply drop from a save (Kevin: "Remove, no refund").
# 0.31.189 (Kevin: "Now check the gold and gem economy and make sure it's balanced"; tools/economy_sim.gd plays it out):
# gold had almost nothing left to buy -- a light player owned all six sold heroes in 5 days and sat on 190,000 gold by
# week 16 -- and free gems ran at about twice 0.31.108's targets (the premium pass paid back ~880 of its 950). Kevin's
# calls: a hero takes a casual player (3 matches a day) about 10 days of gold (HERO_PRICES 25,000, launch 50,000), and
# once the heroes are his, gold buys the Frostbound outfits (SKIN_GOLD; the heroes' own sets stay gems-only). Free gems
# back near the review's targets (light ~300 a season, casual ~550, regular ~600, grinder ~650: chests, weekly orders,
# the quests' last step), the premium track paying back about half its price, fewer hero shards.

# 0.31.168 (Kevin: "Unlock with gold"): the 5v5 heroes you buy with gold (moba.gd HEROES; Profile.buy_hero). The twelve
# from the old classes are everyone's.
# 0.31.189: 25,000 each (was 2,000 -- bought in the first days; Kevin: "About 10 days" for a casual player)
const HERO_PRICES := {"golem":25000, "dragoon":25000, "duelist":25000, "stormcaller":25000, "musketeer":25000, "druid":25000}
# 0.31.185 (Kevin: "I want the same IAP system as league of legends"): heroes the way League sells champions --
#  - gold (League's Blue Essence, earned only: the gem -> gold packs are gone) OR gems (its RP): HERO_GEMS;
#  - a new hero launches dearer (HERO_LAUNCH: when it came out) for LAUNCH_DAYS, then drops to its price -- and only
#    then joins the free rotation (League: a new champion joins it in its third week);
#  - a free rotation: FREE_HEROES of them free to play each week (Monday 00:00 UTC), in turn so each comes round;
#  - hero shards (League's champion shards): from chests (CHESTS "shard") and the pass's free track -- unlock that hero
#    for SHARD_UNLOCK of its gold price, or melt one for SHARD_MELT of it;
#  - a Hero Token on the premium pass (tier 1): any locked hero, yours.
const HERO_GEMS := 450
# hero id -> unix it came out. A static var, not a const, so a test can put a hero in (or out of) its launch; a new
# hero's line goes here when he ships. 0.31.187 (Kevin: "Make the champions the higher price since they are new"): the
# six launch together on 2026-10-19 00:00 UTC -- LAUNCH_GOLD / LAUNCH_GEMS until 2026-11-02, then 2,000 / 450.
const SIX_LAUNCH := 1792368000
static var HERO_LAUNCH := {"golem": SIX_LAUNCH, "dragoon": SIX_LAUNCH, "duelist": SIX_LAUNCH, "stormcaller": SIX_LAUNCH,
	"musketeer": SIX_LAUNCH, "druid": SIX_LAUNCH}
const LAUNCH_DAYS := 14
const LAUNCH_GOLD := 50000             # (0.31.189: 4,000 until then -- twice the price, as before)
const LAUNCH_GEMS := 600
const FREE_HEROES := 2
const SHARD_UNLOCK := 0.6
const SHARD_MELT := 0.1                  # (0.31.189: 0.2 -- with the heroes at 25,000 a melted shard was 5,000)

# 0.31.186 (League's way, the fourth part): hero skins -- the hero's own model repainted (Meshy's retexture with his
# UVs kept, tools/meshy_retexture.py; the textures tools/build_skins.py, assets/skins/<id>.jpg): same mesh, rig and
# silhouette, so every hero still reads as himself, with the team ring under him. Bought for gems (SKIN_GEMS by rarity);
# like League, a skin of a hero you haven't unlocked comes with him. Worn per hero (Profile.wear_skin), seen by everyone
# online ("_sk" in the looks, siege_net.clean_looks).
# 0.31.188 (Kevin: "I only want the cosmetics to be an entire outfit. Each outfit has its own specific looking weapon" /
# "Make all new sets for every hero and make each one unique to their class and lore along with the weapons"): a skin is
# a whole outfit -- the body and a weapon of its own:
#  - OUTFITS: one set made for each hero (his class and his story, champions.gd), its weapon a model of its own
#    ("weapon": {"r", "l"}, assets/meshy/weapons/<model>.glb, held like the hero's own -- siege_view MESHY_WEAPON_LIKE),
#    epic;
#  - Frostbound (SKIN_LINES, every hero): his own weapon repainted in frost ("weapon_tex": assets/skins/weapons/
#    <model>_frost.jpg -- skin_weapon_texture), rare.
const SKIN_GEMS := {"rare": 390, "epic": 750, "legendary": 1350}
# 0.31.189 (Kevin: "Frostbound for gold"): a rare outfit (the Frostbound line) is also sold for gold -- what gold buys once
# the heroes are yours (about two weeks of a casual player's gold). The heroes' own sets (epic) are gems only.
const SKIN_GOLD := {"rare": 40000}
const SKIN_LINES := {"frost": "Frostbound"}
const SKIN_HEROES := {"knight":"Knight", "barbarian":"Barbarian", "rogue":"Rogue", "ranger":"Archer", "mage":"Mage",
	"priest":"Priest", "crusader":"Crusader", "berserker":"Berserker", "assassin":"Assassin", "sniper":"Ranger",
	"archmage":"Archmage", "necromancer":"Necromancer", "golem":"Golem", "dragoon":"Dragoon", "duelist":"Duelist",
	"stormcaller":"Stormcaller", "musketeer":"Musketeer", "druid":"Druid"}
# id ("<hero>_<set key>") -> {set (its name), weapon {"r", "l"}} -- each hero's own set
const OUTFITS := {
	"knight_lion":             {"set": "Lionguard", "weapon": {"r": "mw/lion_sword", "l": "mw/lion_shield"}},
	"barbarian_mammoth":       {"set": "Mammoth Hunter", "weapon": {"r": "mw/mammoth_axe"}},
	"rogue_velvet":            {"set": "Velvet Thief", "weapon": {"r": "mw/coin_dagger", "l": "mw/coin_dagger"}},
	"ranger_orchard":          {"set": "Orchard Warden", "weapon": {"l": "mw/orchard_bow"}},
	"mage_phoenix":            {"set": "Phoenix", "weapon": {"r": "mw/phoenix_staff"}},
	"priest_bell":             {"set": "Bellringer", "weapon": {"r": "mw/bell_scepter"}},
	"crusader_ashen":          {"set": "Ashen Templar", "weapon": {"r": "mw/ember_hammer", "l": "mw/ashen_shield"}},
	"berserker_bloodmoon":     {"set": "Blood Moon", "weapon": {"r": "mw/bloodmoon_greatsword"}},
	"assassin_ribbon":         {"set": "Red Ribbon", "weapon": {"r": "mw/ribbon_dagger", "l": "mw/ribbon_dagger"}},
	"sniper_wolf":             {"set": "Wolfstalker", "weapon": {"r": "mw/wolf_crossbow"}},
	"archmage_stargazer":      {"set": "Stargazer", "weapon": {"r": "mw/orrery_staff", "l": "mw/starchart_tome"}},
	"necromancer_gravekeeper": {"set": "Gravekeeper", "weapon": {"r": "mw/lantern_shovel"}},
	"golem_geode":             {"set": "Geode", "weapon": {"r": "mw/geode_hammer", "l": "mw/geode_shield"}},
	"dragoon_dragonscale":     {"set": "Dragonscale", "weapon": {"r": "mw/dragon_halberd"}},
	"duelist_rose":            {"set": "Golden Rose", "weapon": {"r": "mw/rose_rapier", "l": "mw/thorn_stiletto"}},
	"stormcaller_stormforged": {"set": "Stormforged", "weapon": {"r": "mw/lightning_rod_staff"}},
	"musketeer_privateer":     {"set": "Privateer", "weapon": {"r": "mw/brass_blunderbuss"}},
	"druid_blossom":           {"set": "Cherry Blossom", "weapon": {"r": "mw/blossom_staff"}},
}
static var SKINS := _make_skins()

static func _make_skins() -> Dictionary:
	# id -> {hero, line (the set's key), set (its name), name, rarity, gems, gold (0.31.189: rare ones -- or gold),
	# weapon {"r","l"} | weapon_tex (a key)}
	var out := {}
	for id in OUTFITS:
		var o: Dictionary = OUTFITS[id]
		var h := str(id).substr(0, str(id).find("_"))
		out[id] = {"hero": h, "line": str(id).substr(h.length() + 1), "set": str(o.set),
			"name": "%s %s" % [str(o.set), SKIN_HEROES[h]], "rarity": "epic", "gems": int(SKIN_GEMS.epic),
			"weapon": (o.weapon as Dictionary).duplicate()}
	for line in SKIN_LINES:
		for h in SKIN_HEROES:
			out["%s_%s" % [h, line]] = {"hero": h, "line": line, "set": str(SKIN_LINES[line]),
				"name": "%s %s" % [SKIN_LINES[line], SKIN_HEROES[h]], "rarity": "rare", "gems": int(SKIN_GEMS.rare),
				"gold": int(SKIN_GOLD.rare), "weapon_tex": line}
	return out

static func skin_texture(id: String) -> String:
	return "res://assets/skins/%s.jpg" % id

static func skin_weapon_texture(file: String, key: String) -> String:
	# an outfit's repainting of a weapon piece ("mw/squire_sword", "frost" -> assets/skins/weapons/squire_sword_frost.jpg)
	return "res://assets/skins/weapons/%s_%s.jpg" % [file.get_file(), key]

static func skins_of(hid: String) -> Array:
	var out := []
	for id in SKINS:
		if str(SKINS[id].hero) == hid:
			out.append(id)
	return out

static func launching(hid: String, unix: int) -> bool:
	return HERO_LAUNCH.has(hid) and unix < int(HERO_LAUNCH[hid]) + LAUNCH_DAYS * 86400

static func hero_price(hid: String, unix: int) -> Dictionary:
	# {"gold", "gems"} to unlock hid at this time; {} when it isn't sold (everyone's)
	if not HERO_PRICES.has(hid):
		return {}
	if launching(hid, unix):
		return {"gold": LAUNCH_GOLD, "gems": LAUNCH_GEMS}
	return {"gold": int(HERO_PRICES[hid]), "gems": HERO_GEMS}

static func shard_unlock_gold(hid: String, unix: int) -> int:
	return int(round(float(hero_price(hid, unix).get("gold", 0)) * SHARD_UNLOCK / 10.0)) * 10

static func shard_melt_gold(hid: String, unix: int) -> int:
	return int(round(float(hero_price(hid, unix).get("gold", 0)) * SHARD_MELT / 10.0)) * 10

static func week_index(unix: int) -> int:
	# weeks since the Monday before 1970-01-01 (weeks start Monday 00:00 UTC, as week_key)
	var days := int(floor(unix / 86400.0))
	return int(floor(float(days + 3) / 7.0))

static func free_heroes(unix: int) -> Array:
	# this week's free rotation: FREE_HEROES of the sold heroes, in a fixed shuffled order so each comes round in turn
	# (a launching one waits until its launch price ends -- 0.31.187: unless too few are left to fill it, as while all six
	# launch together: then the rotation goes on with every one of them, the same weeks the server keeps)
	var pool: Array = HERO_PRICES.keys().filter(func(h): return not launching(str(h), unix))
	if pool.size() < FREE_HEROES:
		pool = HERO_PRICES.keys()
	pool.sort()
	if pool.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("free-heroes")
	var order := []
	while not pool.is_empty():
		order.append(pool.pop_at(rng.randi() % pool.size()))
	var out := []
	var w := week_index(unix)
	for i in mini(FREE_HEROES, order.size()):
		out.append(order[(w * FREE_HEROES + i) % order.size()])
	return out

static func pick_shard(seed_text: String, heroes_owned: Array) -> String:
	# a pass shard: one of the heroes not owned yet (any, once all are), the same on the phone and the server
	var pool: Array = HERO_PRICES.keys().filter(func(h): return not heroes_owned.has(h))
	if pool.is_empty():
		pool = HERO_PRICES.keys()
	pool.sort()
	return str(pool[absi(hash(seed_text)) % pool.size()])

const CLASSES := ["knight", "barbarian", "rogue", "ranger", "mage", "priest", "worker"]
# 0.31.164 (Kevin: "Remove them now: 5v5 only"): the classes a 5v5 hero can be -- the Worker was Siege's (his quest and
# titles are kept for the record but not shown, see RETIRED)
const HERO_CLASSES := ["knight", "barbarian", "rogue", "ranger", "mage", "priest"]
# 0.31.38: the upgraded classes have their own cosmetics (and equip slots): what they upgrade from, and which body
# the game builds for them (the Crusader is a Knight body)
const UP_CLASSES := ["crusader", "berserker", "necromancer", "assassin", "sniper", "archmage"]
const UP_BASE := {"crusader":"knight", "berserker":"barbarian", "necromancer":"priest", "assassin":"rogue", "sniper":"ranger", "archmage":"mage"}
const UP_LOOK := {"crusader":"crusader", "berserker":"berserker", "necromancer":"necromancer", "assassin":"assassin", "sniper":"sniper", "archmage":"archmage"}
const CLASS_NAMES := {"knight":"Knight", "barbarian":"Barbarian", "rogue":"Rogue", "ranger":"Archer", "mage":"Mage", "priest":"Priest", "worker":"Worker",
	"crusader":"Crusader", "berserker":"Berserker", "necromancer":"Necromancer", "assassin":"Assassin", "sniper":"Ranger", "archmage":"Archmage"}     # 0.31.61: Ranger -> Archer, Sniper -> Ranger

static func cosmetic_class(cls: String, up: bool) -> String:
	# which equip slot dresses a unit: the upgraded one once he wears the upgraded hat
	if up:
		for k in UP_BASE:
			if UP_BASE[k] == cls:
				return k
	return cls
const RARITY_COLOR := {"common":"#b8c4c9", "rare":"#5fb6ff", "epic":"#c47bff", "legendary":"#ffb13d"}

# ---------------- account level ----------------
static func level_xp(level: int) -> int:
	return 500 + 150 * (level - 1)

static func level_reward(level: int) -> Dictionary:
	# Reward for reaching `level`.
	var r := {"gold":100 + 10 * level}
	if level % 10 == 0:
		r["chest"] = "royal"                 # 0.31.37: chests (was 25 gems every 5 levels)
	elif level % 5 == 0:
		r["chest"] = "gold"
	return r

# ---------------- Siege Pass ----------------
const SEASON_EPOCH := 1790812800         # 2026-10-01 00:00 UTC; seasons before that are season 1
const SEASON_DAYS := 28                  # 4 weeks (Kevin, 0.31.36; was 42)
const PASS_TIERS := 30
# 0.31.36: measured -- a match gives ~420 pass XP, the three dailies ~1,300, the weeklies ~5,700 a week; at 1,000 a tier
# the 30 tiers filled in 8-9 days. At 2,500 (75,000 in all): ~20 days at 3 matches a day with the challenges done,
# ~23 at 2 a day, ~16 at 5 a day -- inside the 28 days for a regular player, a goal for a casual one.
const TIER_XP := 2500
const PREMIUM_COST := 950                # gems
# 0.31.107 (Kevin: "put tier skips for the battlepass. Players can buy 10 tiers for gems"): 10 tiers at a time, 100 gems
# a tier (fewer near the end: only what's left). Any 10 tiers give back at most ~270 gems over both tracks, so a skip is
# never a way to make gems.
const TIER_SKIP := 10
const TIER_SKIP_GEMS := 100              # per tier
const SEASON_NAMES := ["The King's Keep", "Ashen Ramparts", "Frost Siege", "The Fish Wars", "Iron Tide", "Summer of Stones"]

static func season_id(unix: int) -> int:
	return 1 + maxi(0, int(floor(float(unix - SEASON_EPOCH) / (SEASON_DAYS * 86400.0))))

static func season_name(sid: int) -> String:
	return SEASON_NAMES[(sid - 1) % SEASON_NAMES.size()]

static func season_ends(sid: int) -> int:
	return SEASON_EPOCH + sid * SEASON_DAYS * 86400

static func pass_reward(sid: int, tier: int, premium: bool) -> Dictionary:
	# tier is 1..PASS_TIERS. 0.31.188: no cosmetics on the pass (outfits are bought) -- the tiers that held a weapon give
	# chests, gems and hero shards (PASS_FREE_EXTRA / PASS_PREMIUM_EXTRA); the rest as before.
	if not premium:
		if PASS_SHARD_TIERS.has(tier):
			return {"shard": ""}                       # 0.31.185: a hero shard (which one: Profile.pass_reward_for)
		if PASS_FREE_EXTRA.has(tier):
			return (PASS_FREE_EXTRA[tier] as Dictionary).duplicate()
		if tier == 12 or tier == 24:
			return {"chest": "silver"}
		if tier % 4 == 0:
			return {"gems": 30}
		if tier % 4 == 2:
			return {"gold": PASS_GOLD_FREE}            # (0.31.93-0.31.183: 20 Embers)
		return {"gold": 150 + 5 * tier}
	if tier == PASS_TOKEN_TIER:
		return {"token": 1}                            # 0.31.185: the Hero Token -- any locked hero
	if PASS_PREMIUM_EXTRA.has(tier):
		return (PASS_PREMIUM_EXTRA[tier] as Dictionary).duplicate()
	if tier == 8 or tier == 16:
		return {"chest": "gold"}
	if tier == 22:
		return {"chest": "royal"}
	if tier % 4 == 0:
		return {"gold": PASS_GOLD_GEM_TIER} if sid >= 2 else {"gems": 60}     # 0.31.108: not gems from season 2 (until 0.31.184 60 Embers)
	if tier % 4 == 2:
		return {"gold": PASS_GOLD_PREMIUM}         # (0.31.93-0.31.183: 40 Embers)
	return {"gold": 300 + 10 * tier}

# 0.31.188: the tiers that held the pass's weapons (free 10/20/30, premium 2 ... 30)
const PASS_FREE_EXTRA := {10: {"chest": "gold"}, 20: {"chest": "gold"}, 30: {"chest": "royal"}}
# 0.31.189 (the balance check): the track paid back ~880 of its 950 gems (500 on its tiers, ~380 in its chests); now about
# half -- 260 on its tiers (7, 15, 24, 30) and ~190 in its chests; tiers 2 and 28 a Silver and a Gold chest
const PASS_PREMIUM_EXTRA := {2: {"chest": "silver"}, 3: {"chest": "gold"}, 5: {"chest": "silver"}, 7: {"gems": 50},
	9: {"chest": "gold"}, 12: {"shard": ""}, 15: {"gems": 50}, 18: {"chest": "royal"}, 21: {"shard": ""},
	24: {"gems": 60}, 26: {"chest": "royal"}, 28: {"chest": "gold"}, 30: {"chest": "royal", "gems": 100}}
# 0.31.185 (League's pass: Blue Essence and champion capsules on the free track): free tiers 5, 15 and 25 give a hero
# shard (they gave gold); the premium track opens with a Hero Token
const PASS_SHARD_TIERS := [15]             # (0.31.189: 5 and 25 too until then -- they give gold again)
const PASS_TOKEN_TIER := 1
# 0.31.184 (Kevin: "Maybe let's have the two currency so it's more simple"): the Embers the pass gave are gold, ten for
# one (EMBER_GOLD)
const PASS_GOLD_FREE := 200
const PASS_GOLD_PREMIUM := 400
const PASS_GOLD_GEM_TIER := 600

# ---------------- cosmetics ----------------
# 0.31.188: the titles (kind "title": text shown with the name, all earned -- TITLE_GOALS, the leaderboard's prizes).
# The weapons that were here (0.31.39-0.31.187) are gone; each hero's own weapon is siege_view.gd LOOKS, and an outfit's
# its own (SKINS).
# Each class's own weapon has a name (0.31.93 Armory Reforged, Kevin's roster).
const STARTER_NAMES := {"knight": "Squire's Blade", "barbarian": "Woodsplitter", "rogue": "Cutpurse Daggers",
	"ranger": "Ashwood Bow", "mage": "Apprentice Staff", "priest": "Acolyte's Wand", "worker": "Work Hatchet",
	"crusader": "Templar's Sword", "berserker": "Ironhewer", "necromancer": "Bonecaller", "assassin": "Shade Daggers",
	"sniper": "Marksman's Crossbow", "archmage": "Magister's Staff"}

const CATALOG := {
	# --- Titles (0.31.87, Kevin: "players have to earn the titles instead by doing tasks in the game"): source "earn" --
	# not sold, not in the pass or chests; how each is earned is TITLE_GOALS, its text/form/rarity siege_net.TITLES
	# (the same name and rarity here). Owned ones from before (shop, pass, the Knight Arsenal) stay owned.
	"title_squire":         {"kind":"title", "class":"", "name":"Squire", "rarity":"common", "source":"earn"},
	"title_victor":         {"kind":"title", "class":"", "name":"the Victor", "rarity":"common", "source":"earn"},
	"title_brawler":        {"kind":"title", "class":"", "name":"the Brawler", "rarity":"common", "source":"earn"},
	"title_woodcutter":     {"kind":"title", "class":"", "name":"the Woodcutter", "rarity":"common", "source":"earn"},
	"title_fishmonger":     {"kind":"title", "class":"", "name":"the Fishmonger", "rarity":"common", "source":"earn"},
	"title_gatebreaker":    {"kind":"title", "class":"", "name":"the Gatebreaker", "rarity":"rare", "source":"earn"},
	"title_kingbearer":     {"kind":"title", "class":"", "name":"Kingbearer", "rarity":"rare", "source":"earn"},
	"title_many_hats":      {"kind":"title", "class":"", "name":"of Many Hats", "rarity":"rare", "source":"earn"},
	"title_tempest":        {"kind":"title", "class":"", "name":"the Tempest", "rarity":"epic", "source":"earn"},
	"title_relentless":     {"kind":"title", "class":"", "name":"the Relentless", "rarity":"epic", "source":"earn"},
	"title_cake_baron":     {"kind":"title", "class":"", "name":"Fish Baron", "rarity":"epic", "source":"earn"},
	"title_siege_lord":     {"kind":"title", "class":"", "name":"Siege Lord", "rarity":"epic", "source":"earn"},
	"title_oracle_sworn":   {"kind":"title", "class":"", "name":"the Kingsworn", "rarity":"legendary", "source":"earn"},
	"title_unstoppable":    {"kind":"title", "class":"", "name":"the Unstoppable", "rarity":"legendary", "source":"earn"},
	"title_undefeated":     {"kind":"title", "class":"", "name":"the Undefeated", "rarity":"legendary", "source":"earn"},
	"title_legend":         {"kind":"title", "class":"", "name":"the Legend", "rarity":"legendary", "source":"earn"},
	"title_sir":            {"kind":"title", "class":"", "name":"Sir", "rarity":"rare", "source":"earn"},
	"title_shieldwall":     {"kind":"title", "class":"", "name":"the Shieldwall", "rarity":"epic", "source":"earn"},
	"title_hammer_realm":   {"kind":"title", "class":"", "name":"Hammer of the Realm", "rarity":"legendary", "source":"earn"},
	"title_wild":           {"kind":"title", "class":"", "name":"the Wild", "rarity":"rare", "source":"earn"},
	"title_whirlwind":      {"kind":"title", "class":"", "name":"the Whirlwind", "rarity":"epic", "source":"earn"},
	"title_unchained":      {"kind":"title", "class":"", "name":"the Unchained", "rarity":"legendary", "source":"earn"},
	"title_sly":            {"kind":"title", "class":"", "name":"the Sly", "rarity":"rare", "source":"earn"},
	"title_shadows":        {"kind":"title", "class":"", "name":"of the Shadows", "rarity":"epic", "source":"earn"},
	"title_knives":         {"kind":"title", "class":"", "name":"Master of Knives", "rarity":"legendary", "source":"earn"},
	"title_keen_eyed":      {"kind":"title", "class":"", "name":"the Keen-Eyed", "rarity":"rare", "source":"earn"},
	"title_deadeye":        {"kind":"title", "class":"", "name":"the Deadeye", "rarity":"epic", "source":"earn"},
	"title_warden":         {"kind":"title", "class":"", "name":"Warden of the Wilds", "rarity":"legendary", "source":"earn"},
	"title_apprentice":     {"kind":"title", "class":"", "name":"Apprentice", "rarity":"rare", "source":"earn"},
	"title_stormcaller":    {"kind":"title", "class":"", "name":"the Stormcaller", "rarity":"epic", "source":"earn"},
	"title_starborn":       {"kind":"title", "class":"", "name":"the Starborn", "rarity":"legendary", "source":"earn"},
	"title_acolyte":        {"kind":"title", "class":"", "name":"Acolyte", "rarity":"rare", "source":"earn"},
	"title_merciful":       {"kind":"title", "class":"", "name":"the Merciful", "rarity":"epic", "source":"earn"},
	"title_lightbringer":   {"kind":"title", "class":"", "name":"the Lightbringer", "rarity":"legendary", "source":"earn"},
	"title_foreman":        {"kind":"title", "class":"", "name":"Foreman", "rarity":"rare", "source":"earn"},
	"title_mason":          {"kind":"title", "class":"", "name":"the Mason", "rarity":"epic", "source":"earn"},
	"title_master_builder": {"kind":"title", "class":"", "name":"Master Builder", "rarity":"legendary", "source":"earn"},
	# --- 0.31.120: only from the weekly leaderboard (LB_PRIZES)
	"title_champion":       {"kind":"title", "class":"", "name":"Champion", "rarity":"legendary", "source":"prize"},
	"title_contender":      {"kind":"title", "class":"", "name":"the Contender", "rarity":"epic", "source":"prize"},
	"title_top_ten":        {"kind":"title", "class":"", "name":"of the Ten", "rarity":"rare", "source":"prize"},
}

# 0.31.39 (Kevin: "only the weapons are cosmetics -- so it's easy to tell who's playing what class"): the skins (tints)
# are gone. Anyone who bought one gets its price back once (Profile._normalized).
const REMOVED_SKIN_REFUND := {
	"knight_skin_royal":{"gold":1200},
	"knight_skin_gilded":{"gems":400},
	"barb_skin_ember":{"gold":1200},
	"rogue_skin_night":{"gold":1200},
	"ranger_skin_forest":{"gold":1200},
	"ranger_skin_dusk":{"gems":400},
	"mage_skin_arcane":{"gold":1200},
	"mage_skin_solar":{"gems":400},
	"worker_skin_miner":{"gold":600},
	"priest_skin_dawn":{"gold":1200},
	"crus_skin_holy":{"gold":1500},
	"crus_skin_templar":{"gold":2800},
	"crus_skin_sunforged":{"gems":400},
	"bers_skin_bloodrage":{"gold":1500},
	"bers_skin_glacier":{"gold":2800},
	"bers_skin_volcanic":{"gems":400},
	"necro_skin_plague":{"gold":1500},
	"necro_skin_frost":{"gold":2800},
	"necro_skin_boneking":{"gems":400},
	"assn_skin_crimson":{"gold":1500},
	"assn_skin_midnight":{"gold":2800},
	"assn_skin_phantom":{"gems":400},
	"snip_skin_desert":{"gold":1500},
	"snip_skin_winter":{"gold":2800},
	"snip_skin_golden":{"gems":400},
	"arch_skin_frost":{"gold":1500},
	"arch_skin_void":{"gold":2800},
	"arch_skin_starborn":{"gems":400}}

static func item(id: String) -> Dictionary:
	return CATALOG.get(id, {})

# ---------------- the shop's days and weeks ----------------
# (0.31.36-0.31.187: the daily gold weapons and the weekly gem weapons rotated here -- 0.31.188 the shop sells outfits,
# heroes, the pass and gem packs. 0.31.106-0.31.184 EXCHANGE: gold for gems. 0.31.185, League's way: gold is earned only)

const FEATURED_OUTFITS := 3

# 0.31.203 (Kevin: "For featured outfits, let's make them discounted. A new set of on sale skins will rotate once per
# week"): the week's featured outfits are the WEEKLY SALE -- each at its own discount (SALE_OFF, in the order of the
# week's picks), in gems and, for the rare line, in gold too. Bought with the "buy_sale" op (Profile.buy_sale), which
# names the week whose sale the buyer saw: this week's, or last week's for SALE_GRACE after it ended (a buy still on its
# way to the server, or made offline just before midnight on Sunday).
const SALE_OFF := [50, 35, 25]
const SALE_GRACE := 86400
const SALE_GEM_STEP := 5                                   # sale prices round to these
const SALE_GOLD_STEP := 500

static func week_start(unix: int) -> int:
	# the Monday 00:00 UTC that began this week
	return (week_index(unix) * 7 - 3) * 86400

static func sale_off_week(id: String, week: int) -> int:
	# an outfit's discount (percent) in that week's sale; 0 when it isn't in it
	var i := featured_outfits_week(week).find(id)
	return int(SALE_OFF[i]) if i >= 0 and i < SALE_OFF.size() else 0

static func sale_off(id: String, unix: int) -> int:
	return sale_off_week(id, week_index(unix))

static func sale_price(full: int, off: int, step: int) -> int:
	if off <= 0 or full <= 0:
		return full
	return maxi(step, int(round(full * (100 - off) / 100.0 / step)) * step)

static func skin_offer(id: String, unix: int) -> Dictionary:
	# what an outfit costs now: gems, gold (0: not for gold), off (%, 0: full price), was_gems / was_gold (the full
	# prices), week (the sale's, for the op)
	var sk: Dictionary = SKINS.get(id, {})
	var w := week_index(unix)
	var off := sale_off_week(id, w)
	var full_gems := int(sk.get("gems", 0))
	var full_gold := int(sk.get("gold", 0))
	return {"gems": sale_price(full_gems, off, SALE_GEM_STEP), "gold": sale_price(full_gold, off, SALE_GOLD_STEP),
		"off": off, "was_gems": full_gems, "was_gold": full_gold, "week": w}

static func featured_outfits(unix: int) -> Array:
	return featured_outfits_week(week_index(unix))

static func featured_outfits_week(w: int) -> Array:
	# 0.31.188: the shop's featured outfits this week (Monday 00:00 UTC) -- a fixed shuffle of every outfit, three a week
	# in turn so each comes round; a hero's own set first in the shuffle's draw (they're the new ones). 0.31.203: the
	# week's sale, by week number (Profile.buy_sale checks last week's too)
	var pool: Array = SKINS.keys()
	pool.sort()
	if pool.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("featured-outfits")
	var order := []
	while not pool.is_empty():
		order.append(pool.pop_at(rng.randi() % pool.size()))
	order.sort_custom(func(a, b): return SKINS[a].has("weapon") and not SKINS[b].has("weapon"))
	var out := []
	var n := mini(FEATURED_OUTFITS, order.size())
	for i in n:
		out.append(order[(w * n + i) % order.size()])
	return out

static func day_key(unix: int) -> String:
	var d := Time.get_date_dict_from_unix_time(unix)
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]

static func week_key(unix: int) -> String:
	# Weeks start Monday 00:00 UTC.
	var days := int(floor(unix / 86400.0))
	var monday := days - ((days + 3) % 7)            # 1970-01-01 was a Thursday
	return day_key(monday * 86400)

# ---------------- challenges ----------------
# stat keys come from match_stats(): wins, matches, rescues, kills, gates (gate damage / 100),
# gathered, fed, lifts (Oracle lifts joined), class_<name> (matches finished as that class).
# 0.31.164 (Kevin: "5v5 only"): the 5v5's challenges -- Siege's (King rescues, fish, gathering, King lifts) are gone; a
# saved one of those is swapped for a new one when the profile refreshes (Profile._retire_challenges). "gates" is now
# the damage dealt to towers, gates and the King (per 100).
const CHALLENGES := {
	"win1":     {"text":"Win a match", "stat":"wins", "goal":1, "pass":500, "gold":100, "span":"daily"},
	"play3":    {"text":"Play 3 matches", "stat":"matches", "goal":3, "pass":400, "gold":80, "span":"daily"},
	"kos5":     {"text":"Knock out 5 enemy heroes", "stat":"kills", "goal":5, "pass":400, "gold":80, "span":"daily"},
	"gate5":    {"text":"Deal 500 damage to towers and gates", "stat":"gates", "goal":5, "pass":450, "gold":90, "span":"daily"},
	"tower2":   {"text":"Destroy 2 towers", "stat":"towers", "goal":2, "pass":500, "gold":100, "span":"daily"},
	"camps4":   {"text":"Clear 4 jungle camps", "stat":"camps", "goal":4, "pass":450, "gold":90, "span":"daily"},
	"lh60":     {"text":"Last-hit 60 minions", "stat":"lh", "goal":60, "pass":400, "gold":80, "span":"daily"},
	"epic1":    {"text":"Defeat an epic monster", "stat":"epics", "goal":1, "pass":600, "gold":120, "span":"daily"},
	"w_win5":   {"text":"Win 5 matches", "stat":"wins", "goal":5, "pass":2000, "gems":15, "span":"weekly"},
	"w_kos30":  {"text":"Knock out 30 enemy heroes", "stat":"kills", "goal":30, "pass":1800, "gems":12, "span":"weekly"},
	"w_gate30": {"text":"Deal 3,000 damage to towers and gates", "stat":"gates", "goal":30, "pass":1800, "gems":12, "span":"weekly"},
	"w_tower12":{"text":"Destroy 12 towers", "stat":"towers", "goal":12, "pass":2000, "gems":15, "span":"weekly"},
	"w_camps20":{"text":"Clear 20 jungle camps", "stat":"camps", "goal":20, "pass":1800, "gems":12, "span":"weekly"},
	"w_play12": {"text":"Play 12 matches", "stat":"matches", "goal":12, "pass":1600, "gems":10, "span":"weekly"},
}
# (0.31.189: the weeklies' gems 25-40 -> 10-15: they were a third of all free gems, ~400 a season)
const DAILY_COUNT := 3
const WEEKLY_COUNT := 3

static func roll_challenges(span: String, key: String, count: int, exclude: Array = []) -> Array:
	var pool: Array = []
	for id in CHALLENGES:
		if CHALLENGES[id].span == span and not exclude.has(id):
			pool.append(id)
	pool.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s-%s-%d" % [span, key, exclude.size()])
	var out := []
	while out.size() < count and not pool.is_empty():
		var id: String = pool.pop_at(rng.randi() % pool.size())
		out.append({"id":id, "progress":0, "claimed":false})
	return out

# ---------------- match rewards ----------------
const FIRST_WIN := {"gold":150, "pass":500}           # (0.31.189: 300 gold -- 8,400 a month of a casual player's gold)

# 0.31.120 (Kevin: prizes for the weekly leaderboard): paid by the server to the accounts when a week ends
# (server/leaderboard.gd), among players with at least LB_MIN_MATCHES online matches that week. The titles exist only
# here. Chests are reward chests (they wait when the slots are full).
const LB_MIN_MATCHES := 3
const LB_PRIZES := [
	{"from":1, "to":1, "gems":300, "chest":"royal", "title":"title_champion"},
	{"from":2, "to":3, "gems":200, "chest":"gold", "title":"title_contender"},
	{"from":4, "to":10, "gems":100, "chest":"gold", "title":"title_top_ten"},
	{"from":11, "to":100, "gems":30, "chest":"silver"},
]

const PRIZE_TITLES := {
	"title_champion": {"task":"Finish #1 on a weekly leaderboard", "n":1, "cls":""},
	"title_contender": {"task":"Finish 2nd or 3rd on a weekly leaderboard", "n":1, "cls":""},
	"title_top_ten": {"task":"Finish in the top 10 of a weekly leaderboard", "n":1, "cls":""},
}

# 0.31.120 (Kevin: referral codes): a new player enters a friend's code within REF_DAYS of making their account and
# before level REF_LEVEL; at level REF_LEVEL both get a REF_CHEST (server/referrals.gd), a friend for at most REF_MAX.
const REF_DAYS := 7
const REF_LEVEL := 5
const REF_MAX := 20
const REF_CHEST := "gold"

static func lb_prize(rank: int) -> Dictionary:
	for t in LB_PRIZES:
		if rank >= int(t.from) and rank <= int(t.to):
			return t
	return {}

# 0.31.119 (Kevin: "Do all" -- a daily login reward): a 7-day calendar, one claim a day (UTC days, like the orders and
# the first win), round and round; a missed day doesn't reset it. Gems only on day 7 (20 a week -- the economy review
# found Silver chests were already half of all free gems). Chests are reward chests: with the slots full they wait.
const LOGIN_REWARDS := [                 # (0.31.189: gold 150 / 250 / 250 / 500 / 400 -> 100 / 150 / 150 / 300 / 250)
	{"gold":100},
	{"gold":150},
	{"chest":"silver"},
	{"gold":150},
	{"gold":300},
	{"gold":250},
	{"chest":"gold", "gems":20},
]

static func match_stats(me: Dictionary, won: bool, _draw: bool) -> Dictionary:
	# Contribution numbers from the player's unit at the end of a match (offline or online).
	var s := {"matches":1, "wins":1 if won else 0, "rescues":int(me.get("rescues", 0)), "kills":int(me.get("kills", 0)),
		"gates":int(float(me.get("gate_dmg", 0.0)) / 100.0), "gathered":int(me.get("gathered", 0)), "fed":int(me.get("fed", 0)),
		"lifts":int(me.get("lifts", 0))}
	# 0.31.164 (5v5): towers destroyed (yours or near you), jungle camps cleared, minion last hits, epic monsters slain
	for k in FIVE_STATS:
		s[k] = int(me.get(k, 0))
	s["class_" + str(me.get("cls", "villager"))] = 1
	# 0.31.87 (titles): what siege_mode gathered over the match -- the class played most (cls_main), knockouts by the
	# class they were made as, gate health repaired, health healed, the biggest burst of knockouts
	s["repaired"] = int(me.get("repaired", 0.0))
	s["healed"] = int(me.get("healed", 0.0))
	s["best_multi"] = int(me.get("best_multi", 0))
	s["main"] = str(me.get("cls_main", ""))
	var kc: Dictionary = me.get("kills_cls", {})
	for c in kc:
		s["kills_" + str(c)] = int(kc[c])
	# 0.31.97 (quests): per class as worn (Knight / Crusader apart): seconds played and what was done as it
	var q: Variant = me.get("q", {})
	s["q"] = (q as Dictionary).duplicate(true) if q is Dictionary else {}
	return s

# ---------------- titles (0.31.87) ----------------
# How each title is earned: a lifetime count (profile stats) reaching n. "cls": the class it belongs to ("" = anyone);
# each upgrade counts as its class (the sim's unit class is the base class, up = upgraded). Stats: matches, wins,
# kills, gathered, fed, gates (per 100 damage), rescues, lifts, repaired / healed (health), best_multi (most knockouts
# in one burst), best_streak (wins in a row), classes (classes played as the main class of a match), win_<cls>
# (wins with that as the main class), kills_<cls> (knockouts made as it).
const TITLE_GOALS := {
	"title_squire":         {"stat":"matches", "n":5, "task":"Play 5 matches", "cls":""},
	"title_victor":         {"stat":"wins", "n":5, "task":"Win 5 matches", "cls":""},
	"title_brawler":        {"stat":"kills", "n":50, "task":"Knock out 50 enemies", "cls":""},
	"title_woodcutter":     {"stat":"gathered", "n":200, "task":"Gather 200 wood or stone", "cls":"", "siege":true},
	"title_fishmonger":     {"stat":"fed", "n":10, "task":"Feed 10 fish to your King", "cls":"", "siege":true},
	"title_gatebreaker":    {"stat":"gates", "n":100, "task":"Deal 10,000 damage to towers and gates", "cls":""},
	"title_kingbearer":     {"stat":"lifts", "n":25, "task":"Help lift your King 25 times", "cls":"", "siege":true},
	"title_many_hats":      {"stat":"classes", "n":7, "task":"Play a match as each of the 7 classes", "cls":"", "siege":true},
	"title_tempest":        {"stat":"best_multi", "n":3, "task":"Knock out 3 enemies in one burst", "cls":""},
	"title_relentless":     {"stat":"best_streak", "n":5, "task":"Win 5 matches in a row", "cls":""},
	"title_cake_baron":     {"stat":"fed", "n":100, "task":"Feed 100 fish to your King", "cls":"", "siege":true},
	"title_siege_lord":     {"stat":"wins", "n":50, "task":"Win 50 matches", "cls":""},
	"title_oracle_sworn":   {"stat":"rescues", "n":50, "task":"Rescue your King 50 times", "cls":"", "siege":true},
	"title_unstoppable":    {"stat":"best_multi", "n":5, "task":"Knock out 5 enemies in one burst", "cls":""},
	"title_undefeated":     {"stat":"best_streak", "n":10, "task":"Win 10 matches in a row", "cls":""},
	"title_legend":         {"stat":"wins", "n":250, "task":"Win 250 matches", "cls":""},
	"title_sir":            {"stat":"win_knight", "n":10, "task":"Win 10 matches as Knight or Crusader", "cls":"knight"},
	"title_shieldwall":     {"stat":"kills_knight", "n":250, "task":"Knock out 250 enemies as Knight or Crusader", "cls":"knight"},
	"title_hammer_realm":   {"stat":"win_knight", "n":100, "task":"Win 100 matches as Knight or Crusader", "cls":"knight"},
	"title_wild":           {"stat":"win_barbarian", "n":10, "task":"Win 10 matches as Barbarian or Berserker", "cls":"barbarian"},
	"title_whirlwind":      {"stat":"kills_barbarian", "n":250, "task":"Knock out 250 enemies as Barbarian or Berserker", "cls":"barbarian"},
	"title_unchained":      {"stat":"win_barbarian", "n":100, "task":"Win 100 matches as Barbarian or Berserker", "cls":"barbarian"},
	"title_sly":            {"stat":"win_rogue", "n":10, "task":"Win 10 matches as Rogue or Assassin", "cls":"rogue"},
	"title_shadows":        {"stat":"kills_rogue", "n":250, "task":"Knock out 250 enemies as Rogue or Assassin", "cls":"rogue"},
	"title_knives":         {"stat":"win_rogue", "n":100, "task":"Win 100 matches as Rogue or Assassin", "cls":"rogue"},
	"title_keen_eyed":      {"stat":"win_ranger", "n":10, "task":"Win 10 matches as Archer or Ranger", "cls":"ranger"},
	"title_deadeye":        {"stat":"kills_ranger", "n":250, "task":"Knock out 250 enemies as Archer or Ranger", "cls":"ranger"},
	"title_warden":         {"stat":"win_ranger", "n":100, "task":"Win 100 matches as Archer or Ranger", "cls":"ranger"},
	"title_apprentice":     {"stat":"win_mage", "n":10, "task":"Win 10 matches as Mage or Archmage", "cls":"mage"},
	"title_stormcaller":    {"stat":"kills_mage", "n":250, "task":"Knock out 250 enemies as Mage or Archmage", "cls":"mage"},
	"title_starborn":       {"stat":"win_mage", "n":100, "task":"Win 100 matches as Mage or Archmage", "cls":"mage"},
	"title_acolyte":        {"stat":"win_priest", "n":10, "task":"Win 10 matches as Priest or Necromancer", "cls":"priest"},
	"title_merciful":       {"stat":"healed", "n":25000, "task":"Heal 25,000 health", "cls":"priest"},
	"title_lightbringer":   {"stat":"win_priest", "n":100, "task":"Win 100 matches as Priest or Necromancer", "cls":"priest"},
	"title_foreman":        {"stat":"win_worker", "n":10, "task":"Win 10 matches as Worker", "cls":"worker", "siege":true},
	"title_mason":          {"stat":"repaired", "n":20000, "task":"Repair 20,000 gate health", "cls":"worker", "siege":true},
	"title_master_builder": {"stat":"gathered", "n":5000, "task":"Gather 5,000 wood or stone", "cls":"worker", "siege":true},
}
# 0.31.164: "siege": true -- earned in Siege (King rescues, fish, King lifts, gathering, repairs, the Worker, all 7 classes):
# kept by whoever has it, not shown to earn any more (retired())
const TITLE_RARITY_ORDER := ["common", "rare", "epic", "legendary"]

static func retired(goal: Dictionary) -> bool:
	return bool(goal.get("siege", false))

# ---------------- class quests (0.31.97, Kevin: "Build the quest system and I want quests for each class") ----------------
# Every class has one quest: three steps, claimed in order, each paying out (QUEST_REWARDS; the third gave the class's
# legendary weapon until 0.31.188 -- now QUEST_FINAL: gems and a Royal chest). Progress is a lifetime count in the
# profile's stats, "q_<class>_<stat>", kept from 0.31.97 on and credited to the class you were when you did it: a base
# class counts its upgrade too (a Crusader's knockouts are a Knight's), an upgraded class only while in its hat. A match
# counts as played (and won) as a class after QUEST_MIN_TIME seconds as it. Stats: matches, wins, kills, rescues, gates
# (per 100 gate damage), gathered, fed, repaired / healed (health), lifts (King lifts joined), best_multi (the most
# knockouts in one burst -- a best, not a sum).
const QUEST_MIN_TIME := 60.0
const QUEST_COUNTS := ["kills", "rescues", "gates", "gathered", "fed", "repaired", "healed", "lifts", "towers", "camps", "lh", "epics"]
# 0.31.164 (5v5 only): the steps that asked for King rescues or King lifts ask for towers or jungle camps now ("gates" is
# tower and gate damage); the Worker's quest is Siege's -- kept, not shown (HERO_CLASSES)
const QUEST_REWARDS := [{"gold":700}, {"gems":50, "chest":"gold"}]      # steps 1 and 2 (0.31.184: 400 gold + 30 Embers -> 700 gold)
const QUEST_FINAL := {"gems":100, "chest":"royal"}                       # step 3 (0.31.188: was the class's legendary weapon; 0.31.189: 150 -> 100 gems)
const QUESTS := {
	"knight":      {"steps":[
		{"stat":"wins", "n":3, "task":"Win 3 matches as a Knight"},
		{"stat":"towers", "n":10, "task":"Destroy 10 towers as a Knight"},
		{"stat":"kills", "n":500, "task":"Knock out 500 enemies as a Knight"}]},
	"barbarian":   {"steps":[
		{"stat":"kills", "n":40, "task":"Knock out 40 enemies as a Barbarian"},
		{"stat":"gates", "n":100, "task":"Deal 10,000 damage to towers and gates as a Barbarian"},
		{"stat":"wins", "n":60, "task":"Win 60 matches as a Barbarian"}]},
	"rogue":       {"steps":[
		{"stat":"kills", "n":40, "task":"Knock out 40 enemies as a Rogue"},
		{"stat":"best_multi", "n":3, "task":"Knock out 3 enemies in one burst as a Rogue"},
		{"stat":"kills", "n":750, "task":"Knock out 750 enemies as a Rogue"}]},
	"ranger":      {"steps":[
		{"stat":"kills", "n":40, "task":"Knock out 40 enemies as an Archer"},
		{"stat":"wins", "n":25, "task":"Win 25 matches as an Archer"},
		{"stat":"kills", "n":750, "task":"Knock out 750 enemies as an Archer"}]},
	"mage":        {"steps":[
		{"stat":"kills", "n":40, "task":"Knock out 40 enemies as a Mage"},
		{"stat":"camps", "n":15, "task":"Clear 15 jungle camps as a Mage"},
		{"stat":"wins", "n":60, "task":"Win 60 matches as a Mage"}]},
	"priest":      {"steps":[
		{"stat":"healed", "n":2000, "task":"Heal 2,000 health as a Priest"},
		{"stat":"towers", "n":10, "task":"Destroy 10 towers as a Priest"},
		{"stat":"wins", "n":60, "task":"Win 60 matches as a Priest"}]},
	"worker":      {"steps":[
		{"stat":"gathered", "n":300, "task":"Gather 300 wood or stone"},
		{"stat":"repaired", "n":10000, "task":"Repair 10,000 gate health"},
		{"stat":"wins", "n":60, "task":"Win 60 matches as a Worker"}]},
	"crusader":    {"steps":[
		{"stat":"kills", "n":25, "task":"Knock out 25 enemies as a Crusader"},
		{"stat":"towers", "n":8, "task":"Destroy 8 towers as a Crusader"},
		{"stat":"wins", "n":30, "task":"Win 30 matches as a Crusader"}]},
	"berserker":   {"steps":[
		{"stat":"kills", "n":25, "task":"Knock out 25 enemies as a Berserker"},
		{"stat":"gates", "n":80, "task":"Deal 8,000 damage to towers and gates as a Berserker"},
		{"stat":"wins", "n":30, "task":"Win 30 matches as a Berserker"}]},
	"necromancer": {"steps":[
		{"stat":"kills", "n":25, "task":"Knock out 25 enemies as a Necromancer"},
		{"stat":"healed", "n":3000, "task":"Heal 3,000 health as a Necromancer"},
		{"stat":"wins", "n":30, "task":"Win 30 matches as a Necromancer"}]},
	"assassin":    {"steps":[
		{"stat":"kills", "n":25, "task":"Knock out 25 enemies as an Assassin"},
		{"stat":"best_multi", "n":3, "task":"Knock out 3 enemies in one burst as an Assassin"},
		{"stat":"kills", "n":400, "task":"Knock out 400 enemies as an Assassin"}]},
	"sniper":      {"steps":[
		{"stat":"kills", "n":25, "task":"Knock out 25 enemies as a Ranger"},
		{"stat":"wins", "n":20, "task":"Win 20 matches as a Ranger"},
		{"stat":"kills", "n":400, "task":"Knock out 400 enemies as a Ranger"}]},
	"archmage":    {"steps":[
		{"stat":"kills", "n":25, "task":"Knock out 25 enemies as an Archmage"},
		{"stat":"camps", "n":10, "task":"Clear 10 jungle camps as an Archmage"},
		{"stat":"wins", "n":30, "task":"Win 30 matches as an Archmage"}]},
}

static func quest_family(cls: String) -> Array:
	# the classes whose play counts toward cls's quest: a base class and its upgrade, or an upgrade alone
	var out := [cls]
	for u in UP_BASE:
		if str(UP_BASE[u]) == cls:
			out.append(u)
	return out

static func quest_key(cls: String, stat: String) -> String:
	return "q_%s_%s" % [cls, stat]

static func quest_progress(stats: Dictionary, cls: String, step: int) -> int:
	var q: Dictionary = QUESTS.get(cls, {})
	if q.is_empty() or step < 0 or step >= q.steps.size():
		return 0
	return int(stats.get(quest_key(cls, str(q.steps[step].stat)), 0))

static func quest_reward(cls: String, step: int) -> Dictionary:
	# what claiming step (0-based) gives: QUEST_REWARDS, QUEST_FINAL for the last
	if step < QUEST_REWARDS.size():
		return QUEST_REWARDS[step]
	return QUEST_FINAL.duplicate()

static func quest_note(cls: String) -> String:
	# who counts: "Crusader play counts too" for a base class with an upgrade
	var fam := quest_family(cls)
	if fam.size() > 1:
		return "%s play counts too" % str(CLASS_NAMES[fam[1]])
	if UP_BASE.has(cls):
		return "Counts while you wear the %s hat" % str(CLASS_NAMES[cls])
	return ""

static func title_progress(stats: Dictionary, id: String) -> int:
	var g: Dictionary = TITLE_GOALS.get(id, {})
	if g.is_empty():
		return 0
	if str(g.stat) == "classes":
		var n := 0
		for c in CLASSES:
			if int(stats.get("main_" + c, 0)) > 0:
				n += 1
		return n
	return int(stats.get(str(g.stat), 0))

const FIVE_STATS := ["towers", "camps", "lh", "epics"]

static func match_rewards(stats: Dictionary, won: bool, draw: bool, online: bool, first_win: bool) -> Dictionary:
	# Itemised so the results screen can show where every coin came from.
	var lines := []
	# (0.31.184: the Embers a match gave are in its gold, EMBER_GOLD each -- a win 5 -> 150 + 50, a draw or a loss 2 -> + 20)
	# (0.31.189, the balance check: a win 200 -> 150 gold, a draw 120 -> 100, a loss 95 -> 75 -- with the heroes at 25,000)
	var base: Dictionary = {"gold":150, "xp":250, "pass":400} if won else ({"gold":100, "xp":175, "pass":300} if draw else {"gold":75, "xp":125, "pass":250})
	lines.append({"label":"Victory" if won else ("Draw" if draw else "Defeat"), "gold":base.gold, "xp":base.xp, "pass":base.pass})
	var r: int = int(stats.get("rescues", 0))
	if r > 0:
		lines.append({"label":"King rescues x%d" % r, "gold":50 * r, "xp":40 * r, "pass":60 * r})
	var k: int = mini(30, int(stats.get("kills", 0)))
	if k > 0:
		lines.append({"label":"Knockouts x%d" % k, "gold":3 * k, "xp":4 * k, "pass":5 * k})
	var g: int = mini(100, int(stats.get("gathered", 0)))
	if g > 0:
		lines.append({"label":"Gathered x%d" % g, "gold":g, "xp":g, "pass":g})
	var gd: int = mini(40, int(stats.get("gates", 0)))
	if gd > 0:
		lines.append({"label":"Tower and gate damage", "gold":2 * gd, "xp":3 * gd, "pass":3 * gd})
	var f: int = mini(10, int(stats.get("fed", 0)))
	if f > 0:
		lines.append({"label":"Fish fed x%d" % f, "gold":10 * f, "xp":10 * f, "pass":15 * f})
	# 0.31.164 (5v5)
	var tw: int = mini(12, int(stats.get("towers", 0)))
	if tw > 0:
		lines.append({"label":"Towers destroyed x%d" % tw, "gold":25 * tw, "xp":30 * tw, "pass":40 * tw})
	var cp: int = mini(30, int(stats.get("camps", 0)))
	if cp > 0:
		lines.append({"label":"Jungle camps x%d" % cp, "gold":6 * cp, "xp":8 * cp, "pass":10 * cp})
	var lh: int = mini(150, int(stats.get("lh", 0)))
	if lh > 0:
		lines.append({"label":"Minion last hits x%d" % lh, "gold":lh, "xp":lh, "pass":lh})
	var ep: int = mini(6, int(stats.get("epics", 0)))
	if ep > 0:
		lines.append({"label":"Epic monsters x%d" % ep, "gold":40 * ep, "xp":40 * ep, "pass":60 * ep})
	if online:
		var sub := {"gold":0, "xp":0, "pass":0}
		for ln in lines:
			for key in sub:
				sub[key] += int(ln[key])
		lines.append({"label":"Online bonus +20%", "gold":int(sub.gold * 0.2), "xp":int(sub.xp * 0.2), "pass":int(sub.pass * 0.2)})
	if first_win:
		lines.append({"label":"First win of the day", "gold":FIRST_WIN.gold, "xp":0, "pass":FIRST_WIN.pass})
	var total := {"gold":0, "xp":0, "pass":0}
	for ln in lines:
		for key in total:
			total[key] += int(ln[key])
	total["lines"] = lines
	return total

# ---------------- migration from the dice-era save ----------------
static func legacy_conversion(old: Dictionary) -> Dictionary:
	# Old gold 1:1; old tokens -> gems 1:1; old weapons beyond the starter -> 250 gold each;
	# unopened chests -> 150 gold each; old level kept (min 1). Old Fate energy is dropped.
	var owned: Array = old.get("owned", []) if old.get("owned", []) is Array else []
	var chests: Array = old.get("chests", []) if old.get("chests", []) is Array else []
	var gold := maxi(0, int(old.get("gold", 0))) + 250 * maxi(0, owned.size() - 1) + 150 * chests.size()
	return {"gold":gold, "gems":maxi(0, int(old.get("tokens", 0))), "level":maxi(1, int(old.get("level", 1))),
		"xp":maxi(0, int(old.get("xp", 0))), "weapons":maxi(0, owned.size() - 1), "chests":chests.size()}


# ---------------- chests (0.31.37, Kevin: "a chest system"; "overtime") ----------------
# Earned by playing, never sold (so they aren't paid loot boxes). CHEST_SLOTS hold chests; one unlocks at a time
# over its timer; gems skip what's left (1 gem per 10 minutes). The contents are rolled when it's opened, from the
# chest's id (so a reload can't re-roll), and the odds are shown in the game.
const CHEST_SLOTS := 4
const TUTORIAL_GOLD := 250         # the tutorial's pay, once (0.31.108: Profile.finish_tutorial; was siege_mode's)
# 0.31.124 (Kevin: "Add the discord link to the game" / "Also give a reward for joining the discord"): Settings >
# COMMUNITY opens the invite; the first time pays DISCORD_GEMS once per account (Profile.claim_discord, replayed by the
# server). The game can't see whether the player then joins -- opening the invite is what's rewarded.
const DISCORD_URL := "https://discord.gg/H8eKXH8TmM"
const DISCORD_GEMS := 100
const CHESTS := {
	# 0.31.188 (no weapons to drop): gold, gems and hero shards only. 0.31.189 (the balance check: with six heroes to buy
	# the shards came faster than they could be used, and gems at twice the targets): Wooden 50-100 gold, no gems or shard
	# (was 80-150, 15 % of 5 gems, 5 % a shard); Silver 120-200, 25 % of 5 gems, 2 % a shard (200-320, 40 % of 5-10, 15 %);
	# Gold 300-450, 10-15 gems, 10 % a shard (500-750, 20-30, 40 %); Royal 800, 30-40 gems, a shard half the time
	# (1,200, 60-80, always)
	"wooden": {"name":"Wooden Chest", "unlock":1800, "gold":[50, 100], "gems_chance":0.0, "gems":[5, 5],
		"color":"#a8794a", "shard":0.0},
	# 0.31.108: Silver gems 5-10 every time -> a 30% chance of 5 (they were about half of all free gems)
	"silver": {"name":"Silver Chest", "unlock":3 * 3600, "gold":[120, 200], "gems_chance":0.25, "gems":[5, 5],
		"color":"#c9d3dc", "shard":0.02},
	"gold":   {"name":"Gold Chest", "unlock":8 * 3600, "gold":[300, 450], "gems_chance":1.0, "gems":[10, 15],
		"color":"#ffcf4a", "shard":0.1},
	"royal":  {"name":"Royal Chest", "unlock":12 * 3600, "gold":[800, 800], "gems_chance":1.0, "gems":[30, 40],
		"color":"#c47bff", "shard":0.5},
}
# 0.31.185 (League's champion capsules): "shard" -- the chance of a hero shard (any of the sold heroes: unlock it for
# Eco.SHARD_UNLOCK of its gold price, or melt it)
const CHEST_FULL_GOLD := {"wooden":50, "silver":120, "gold":300, "royal":700}   # slots full: the chest becomes gold
const CHEST_QUEUE_MAX := 12        # 0.31.108: reward chests waiting for a slot (beyond this they turn into gold)

static func skip_cost(remaining_s: int) -> int:
	return maxi(1, int(ceil(float(remaining_s) / 600.0)))

static func roll_chest(kind: String, seed_value: int) -> Dictionary:
	# -> {gold, gems, shard (a hero, "" if none)} -- the same on the phone and the server (the seed is the chest's)
	var c: Dictionary = CHESTS[kind]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := {"gold":rng.randi_range(int(c.gold[0]), int(c.gold[1])), "gems":0, "shard":""}
	if rng.randf() < float(c.gems_chance):
		out.gems = rng.randi_range(int(c.gems[0]), int(c.gems[1]))
	if float(c.get("shard", 0.0)) > 0.0 and rng.randf() < float(c.shard):
		var heroes: Array = HERO_PRICES.keys()
		heroes.sort()
		out.shard = str(heroes[rng.randi_range(0, heroes.size() - 1)])
	return out

static func chest_odds(kind: String) -> String:
	# for the info panel: what's in it, plainly
	var c: Dictionary = CHESTS[kind]
	var parts := ["%d-%d gold" % [int(c.gold[0]), int(c.gold[1])] if int(c.gold[0]) != int(c.gold[1]) else "%d gold" % int(c.gold[0])]
	var gems := ("%d" % int(c.gems[0])) if int(c.gems[0]) == int(c.gems[1]) else "%d-%d" % [int(c.gems[0]), int(c.gems[1])]
	if float(c.gems_chance) >= 1.0:
		parts.append("%s gems" % gems)
	elif float(c.gems_chance) > 0.0:                   # (0.31.189: a Wooden chest holds no gems)
		parts.append("%d%% chance of %s gems" % [int(round(float(c.gems_chance) * 100.0)), gems])
	if float(c.get("shard", 0.0)) > 0.0:
		parts.append("a hero shard" if float(c.shard) >= 1.0 else "%d%% chance of a hero shard" % int(round(float(c.shard) * 100.0)))
	return " · ".join(parts)


# ---------------- gold that was Embers (0.31.184) ----------------
# (0.31.93-0.31.187: the Forge, Embers until 0.31.184.) Kevin: "Maybe let's have the two currency so it's more simple" --
# what gave Embers gives gold at EMBER_GOLD a piece, and a save's Embers turn into gold once (Profile._normalized).
const EMBER_GOLD := 10
const DAILY_GOLD := 0                   # each daily order claimed (0.31.93-0.31.183: 15 Embers; 0.31.184-0.31.188: 150 gold --
                                        # 0.31.189: gone, each order pays its own gold)


# ---------------- clans (0.31.196) ----------------
# Kevin: "Now let's redo the clan system for new game" -> "Do clan chest, clan camp, crest, shard requests, 5-stack, lfg
# button, league". server/clans.gd keeps the books; the phone (scripts/app/clan_panel.gd) shows them with these numbers.
# A players' clan (not one of the three starter clans, the house clans of 0.31.148) earns CLAN POINTS from its members'
# online matches (the server's own count, siege_server _pay_match): CLAN_POINTS for the result, the towers and the KOs,
# doubled (CLAN_PARTY_X) for a member who had a clanmate in his party. A week's points (Monday 00:00 UTC, as the
# leaderboard) fill the CLAN CHEST -- CLAN_CHEST_TIERS, one chest for the highest tier reached, to every member who earned
# CLAN_CHEST_MIN that week -- and rank the clans in the CLAN LEAGUE (CLAN_LEAGUE_PRIZES: gems to the same members, and a
# frame round the crest for the next week). Every point is clan XP too (and every shard given, CLAN_GIVE_XP): CLAN_LEVELS
# -> the clan's level, which grows its camp (CLAN_CAMP_STAGE: the camp painting's four stages).
const CLAN_POINTS := {"win":10, "draw":6, "loss":4, "tower":2, "ko":1, "ko_max":10}
const CLAN_PARTY_X := 2
const CLAN_CHEST_TIERS := [[60, "wooden"], [200, "silver"], [500, "gold"], [1000, "royal"]]
const CLAN_CHEST_MIN := 10
const CLAN_LEAGUE_PRIZES := [
	{"from":1, "to":1, "gems":100, "frame":"gold"},
	{"from":2, "to":2, "gems":60, "frame":"silver"},
	{"from":3, "to":3, "gems":60, "frame":"bronze"},
	{"from":4, "to":10, "gems":30, "frame":""},
]
const CLAN_LEVELS := [0, 200, 600, 1200, 2000, 3200, 4800, 7000, 10000, 14000]   # the XP for levels 1-10
const CLAN_CAMP_STAGE := [1, 1, 2, 2, 3, 3, 3, 4, 4, 4]                           # the camp's stage at levels 1-10
const CLAN_GIVE_XP := 5
# shard requests: a member asks the clan for a shard of a hero he hasn't got (one ask open at a time, at most one every
# CLAN_ASK_GAP, open CLAN_ASK_LIFE); a member holding a shard of that hero gives it -- the asker gets the shard, the giver
# what melting it would have paid (Profile.melt_shard's gold) and the clan CLAN_GIVE_XP. A shard a clanmate gave can't be
# given on (Profile "gift_shards"): passed back and forth it would pay its melt gold every time
const CLAN_ASK_GAP := 7 * 3600              # 0.31.197 (Kevin: "put a request donation limit to once per 7 hours"; was 8)
const CLAN_ASK_LIFE := 24 * 3600
# LFG: a member says he's looking for a party (clan chat, CLAN_LFG_LIFE); clanmates JOIN straight into his party
const CLAN_LFG_LIFE := 600
# the crest: an emblem in one colour on a shield of another (assets/ui/clans/, tools/build_clan_art.py)
const CLAN_EMBLEMS := ["lion", "stag", "raven", "wolf", "dragon", "bear", "eagle", "boar", "skull", "crown", "swords", "tower",
	"tree", "flame", "moon", "bolt"]
const CLAN_FIELDS := ["#2b59c3", "#c0392b", "#1f8a4c", "#7d3cc8", "#d97a1e", "#1d2436", "#0f8f8f", "#a0284f", "#6b4a2b", "#e8e2d0"]
const CLAN_CHARGES := ["#ffffff", "#ffd65a", "#141414", "#ff6b5e", "#7fe3ff", "#8cf0a8", "#d9a8ff", "#c0c6cf"]
# the three house clans' crests (and a players' clan made with a house by an older app: 0.31.134-0.31.195)
const CLAN_HOUSE_CREST := {"lions": {"e":0, "f":4, "c":0}, "stags": {"e":1, "f":2, "c":0}, "ravens": {"e":2, "f":3, "c":0}}

static func clan_points(me: Dictionary, won: bool, draw: bool) -> int:
	# one online match's clan points (before CLAN_PARTY_X)
	var p := int(CLAN_POINTS.win if won else (CLAN_POINTS.draw if draw else CLAN_POINTS.loss))
	p += maxi(0, int(me.get("towers", 0))) * int(CLAN_POINTS.tower)
	p += mini(maxi(0, int(me.get("kills", 0))) * int(CLAN_POINTS.ko), int(CLAN_POINTS.ko_max))
	return p

static func clan_level(xp: int) -> int:
	var lv := 1
	for i in CLAN_LEVELS.size():
		if xp >= int(CLAN_LEVELS[i]):
			lv = i + 1
	return lv

static func clan_level_xp(lv: int) -> int:
	# the XP a level starts at (-1 past the last)
	return int(CLAN_LEVELS[lv - 1]) if lv >= 1 and lv <= CLAN_LEVELS.size() else -1

static func clan_camp_stage(lv: int) -> int:
	return int(CLAN_CAMP_STAGE[clampi(lv, 1, CLAN_CAMP_STAGE.size()) - 1])

static func clan_tier(pts: int) -> int:
	# the Clan Chest's tier the week's points reached (0: none yet)
	var t := 0
	for i in CLAN_CHEST_TIERS.size():
		if pts >= int(CLAN_CHEST_TIERS[i][0]):
			t = i + 1
	return t

static func clan_chest_of(tier: int) -> String:
	return str(CLAN_CHEST_TIERS[tier - 1][1]) if tier >= 1 and tier <= CLAN_CHEST_TIERS.size() else ""

static func clan_league_prize(rank: int) -> Dictionary:
	for t in CLAN_LEAGUE_PRIZES:
		if rank >= int(t.from) and rank <= int(t.to):
			return t
	return {}

static func clean_crest(c: Variant) -> Dictionary:
	# {"e", "f", "c"} within the lists ({} when it isn't one)
	if not (c is Dictionary):
		return {}
	var e := int(c.get("e", -1))
	var f := int(c.get("f", -1))
	var ch := int(c.get("c", -1))
	if e < 0 or e >= CLAN_EMBLEMS.size() or f < 0 or f >= CLAN_FIELDS.size() or ch < 0 or ch >= CLAN_CHARGES.size():
		return {}
	return {"e":e, "f":f, "c":ch}

static func crest_code(c: Dictionary) -> String:
	# "e.f.c" -- the crest on cards, chat lines, the match's names and the leaderboard ("" for none)
	var k := clean_crest(c)
	return "" if k.is_empty() else "%d.%d.%d" % [int(k.e), int(k.f), int(k.c)]

static func crest_of_code(s: String) -> Dictionary:
	var p := s.split(".")
	if p.size() != 3 or not p[0].is_valid_int() or not p[1].is_valid_int() or not p[2].is_valid_int():
		return {}
	return clean_crest({"e":int(p[0]), "f":int(p[1]), "c":int(p[2])})
