extends RefCounted
# Fatebound Siege economy: currencies, levels, Siege Pass, challenges, shop rotation, cosmetics and
# match rewards. Pure data + pure functions (no I/O) so it is easy to test and tune; the player's
# state lives in scripts/meta/profile.gd.
#
# Everything sold is cosmetic. The forge still decides your class in battle.

const CLASSES := ["knight", "barbarian", "rogue", "ranger", "mage", "priest", "worker"]
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
const SEASON_NAMES := ["The King's Keep", "Ashen Ramparts", "Frost Siege", "The Fish Wars", "Iron Tide", "Summer of Stones"]

static func season_id(unix: int) -> int:
	return 1 + maxi(0, int(floor(float(unix - SEASON_EPOCH) / (SEASON_DAYS * 86400.0))))

static func season_name(sid: int) -> String:
	return SEASON_NAMES[(sid - 1) % SEASON_NAMES.size()]

static func season_ends(sid: int) -> int:
	return SEASON_EPOCH + sid * SEASON_DAYS * 86400

static func pass_reward(sid: int, tier: int, premium: bool) -> Dictionary:
	# tier is 1..PASS_TIERS. Deterministic per season; cosmetic items rotate by season.
	# 0.31.42 (Kevin: less gear on the free side, the best-looking gear and more unlocks on the paid side): the free
	# track has PASS_FREE_ITEMS (3) cosmetics at tiers 10/20/30, the lowest rarities of the season; the premium track has
	# PASS_PREMIUM_ITEMS (13), every epic and legendary among them, the best at tier 30 and a strong one at tier 1.
	var items: Array = pass_items(sid)
	if not premium:
		var fi := FREE_ITEM_TIERS.find(tier)
		if fi >= 0:
			if str(CATALOG[items[fi]].kind) == "title":
				return {"gems": 30}
			return {"item": items[fi]}
		if tier == 12 or tier == 24:
			return {"chest": "silver"}
		if tier % 4 == 0:
			return {"gems": 30}
		if tier % 4 == 2:
			return {"embers": PASS_EMBERS_FREE}        # 0.31.93: Embers for the Forge on both tracks
		return {"gold": 150 + 5 * tier}
	var pi := PREMIUM_ITEM_TIERS.find(tier)
	if pi >= 0:
		var it: String = items[PASS_FREE_ITEMS + pi]
		if str(CATALOG[it].kind) == "title":
			return {"gems": PASS_TITLE_GEMS.get(str(CATALOG[it].rarity), 50)}     # (0.31.87: titles are earned now)
		return {"item": it}
	if tier == 8 or tier == 16:
		return {"chest": "gold"}
	if tier == 22:
		return {"chest": "royal"}
	if tier % 4 == 0:
		return {"gems": 60}
	if tier % 4 == 2:
		return {"embers": PASS_EMBERS_PREMIUM}
	return {"gold": 300 + 10 * tier}

const PASS_FREE_ITEMS := 3
const PASS_PREMIUM_ITEMS := 13
const FREE_ITEM_TIERS := [10, 20, 30]
const PREMIUM_ITEM_TIERS := [1, 3, 5, 7, 9, 12, 15, 18, 21, 24, 26, 28, 30]
const RARITY_RANK := {"common":0, "rare":1, "epic":2, "legendary":3}

# 0.31.87: the five titles the pass used to give stay in its draw (so every season's pass keeps the tiers it had), and
# the tiers that drew one give gems instead.
const PASS_LEGACY_TITLES := ["title_cake_baron", "title_lightbringer", "title_shieldwall", "title_siege_lord", "title_whirlwind"]
const PASS_TITLE_GEMS := {"epic": 50, "legendary": 100}

static func pass_cosmetics(sid: int) -> Dictionary:
	# How many cosmetics the premium track really gives (the title tiers are gems now): {"n", "legendary"}
	var items: Array = pass_items(sid)
	var out := {"n": 0, "legendary": 0}
	for k in range(PASS_FREE_ITEMS, items.size()):
		if str(CATALOG[items[k]].kind) != "title":
			out.n += 1
			if str(CATALOG[items[k]].rarity) == "legendary":
				out.legendary += 1
	return out

static func pass_items(sid: int) -> Array:
	# PASS_FREE_ITEMS free + PASS_PREMIUM_ITEMS premium cosmetics for season `sid`, from the "pass" pool: shuffled per
	# season, then ranked by rarity -- the free track takes the lowest, the premium track the rest in rising rarity
	# (tier 1 gets the second-best of its rank band so the first premium unlock feels good; tier 30 the best).
	var pool: Array = PASS_LEGACY_TITLES.duplicate()
	for id in CATALOG:
		if CATALOG[id].get("source", "") == "pass":
			pool.append(id)
	pool.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("pass-%d" % sid)
	var shuffled := []
	var src := pool.duplicate()
	while not src.is_empty():
		shuffled.append(src.pop_at(rng.randi() % src.size()))
	shuffled.sort_custom(func(a, b): return int(RARITY_RANK.get(str(CATALOG[a].rarity), 1)) < int(RARITY_RANK.get(str(CATALOG[b].rarity), 1)))
	var want := PASS_FREE_ITEMS + PASS_PREMIUM_ITEMS
	while shuffled.size() < want:
		shuffled.push_front(shuffled[shuffled.size() % maxi(1, pool.size())])
	var free := shuffled.slice(0, PASS_FREE_ITEMS)
	var prem := shuffled.slice(shuffled.size() - PASS_PREMIUM_ITEMS)       # the best PASS_PREMIUM_ITEMS, rising rarity
	if prem.size() >= 3:
		var opener: String = prem[prem.size() - 2]                          # a strong one to open the premium track
		prem.remove_at(prem.size() - 2)
		prem.push_front(opener)
	return free + prem

# ---------------- cosmetics ----------------
# kind "weapon": right/left hand models for a class (0.31.39: the only class cosmetic -- no skins/tints, so every
# class keeps its own readable look). kind "title": text on the profile.
# kind "title": text shown on the profile. source "shop" (gold/gems), "pass", "level".
# 0.31.93 Armory Reforged: each class's starting weapon has a name too (Kevin approved the roster, 2026-10-09); the
# Knight's shipped first, every other class in 0.31.94.
const STARTER_NAMES := {"knight": "Squire's Blade", "barbarian": "Woodsplitter", "rogue": "Cutpurse Daggers",
	"ranger": "Ashwood Bow", "mage": "Apprentice Staff", "priest": "Acolyte's Wand", "worker": "Work Hatchet",
	"crusader": "Templar's Sword", "berserker": "Ironhewer", "necromancer": "Bonecaller", "assassin": "Shade Daggers",
	"sniper": "Marksman's Crossbow", "archmage": "Magister's Staff"}

const CATALOG := {
	# --- Knight
	"knight_wpn_greatsword":{"kind":"weapon", "class":"knight", "name":"Highguard", "rarity":"rare", "r":"mw/highguard_sword", "l":"mw/highguard_shield", "gold":900, "source":"shop"},
	"knight_wpn_crest":    {"kind":"weapon", "class":"knight", "name":"Lionheart", "rarity":"rare", "r":"mw/lionheart_sword", "l":"mw/lionheart_shield", "gold":1100, "source":"shop"},
	"knight_wpn_tower":    {"kind":"weapon", "class":"knight", "name":"Dawnwall", "rarity":"epic", "r":"mw/dawnwall_sword", "l":"mw/dawnwall_shield", "gems":250, "source":"shop"},
	"knight_wpn_crimson":  {"kind":"weapon", "class":"knight", "name":"Bloodmoon", "rarity":"epic", "r":"mw/bloodmoon_sword", "l":"mw/bloodmoon_shield", "source":"pass"},
	# --- Barbarian
	"barb_wpn_raider":     {"kind":"weapon", "class":"barbarian", "name":"Raider's Bite", "rarity":"rare", "r":"mw/raider_axe", "l":"mw/raider_shield", "gold":1000, "source":"shop"},
	"barb_wpn_spiked":     {"kind":"weapon", "class":"barbarian", "name":"Thornhide", "rarity":"epic", "r":"mw/thornhide_axe", "l":"mw/thornhide_shield", "gems":250, "source":"shop"},
	# --- Rogue
	"rogue_wpn_bomb":      {"kind":"weapon", "class":"rogue", "name":"Smokescreen", "rarity":"rare", "r":"mw/smokescreen_dagger", "l":"mw/smokescreen_bomb", "gold":900, "source":"shop"},
	"rogue_wpn_bolt":      {"kind":"weapon", "class":"rogue", "name":"Whisperbolt", "rarity":"epic", "r":"mw/whisperbolt_dagger", "l":"mw/whisperbolt_dagger", "gems":250, "source":"shop"},   # (0.31.98, Kevin: no crossbow for the Rogue -- the daggers)
	# --- Ranger
	"ranger_wpn_crossbow": {"kind":"weapon", "class":"ranger", "name":"Ironjaw", "rarity":"epic", "r":"mw/ironjaw_crossbow", "l":"", "source":"pass"},
	"ranger_wpn_quiver":   {"kind":"weapon", "class":"ranger", "name":"Trailblazer", "rarity":"rare", "r":"mw/trailblazer_quiver", "l":"mw/trailblazer_bow", "gold":900, "source":"shop"},
	# --- Mage
	"mage_wpn_tome":       {"kind":"weapon", "class":"mage", "name":"Spellwright", "rarity":"rare", "r":"mw/spellwright_wand", "l":"mw/spellwright_tome", "gold":1000, "source":"shop"},
	"mage_wpn_wand":       {"kind":"weapon", "class":"mage", "name":"Sparkstick", "rarity":"common", "r":"mw/sparkstick_wand", "l":"", "gold":500, "source":"shop"},
	# --- Worker
	"worker_wpn_mug":      {"kind":"weapon", "class":"worker", "name":"Tavern Brawler", "rarity":"rare", "r":"mw/brawler_axe", "l":"mw/brawler_mug", "source":"pass"},
	# --- Round 11: KayKit Fantasy Weapons Bits ("bits/<model>") and the Priest
	"knight_wpn_bastion":  {"kind":"weapon", "class":"knight", "name":"Stonewarden", "rarity":"epic", "r":"mw/stonewarden_sword", "l":"mw/stonewarden_shield", "gems":280, "source":"shop"},
	"knight_wpn_oath":     {"kind":"weapon", "class":"knight", "name":"Kingsoath", "rarity":"legendary", "r":"mw/kingsoath_sword", "l":"mw/kingsoath_shield", "source":"pass"},
	"knight_wpn_halberd":  {"kind":"weapon", "class":"knight", "name":"Thornspire", "rarity":"epic", "r":"mw/thornspire_halberd", "l":"mw/thornspire_shield", "source":"pass"},
	"barb_wpn_hammer":     {"kind":"weapon", "class":"barbarian", "name":"Skullknocker", "rarity":"rare", "r":"mw/skullknocker_hammer", "l":"", "gold":1100, "source":"shop"},
	"barb_wpn_twinaxe":    {"kind":"weapon", "class":"barbarian", "name":"Twin Fury", "rarity":"epic", "r":"mw/twinfury_axe", "l":"", "source":"pass"},
	"barb_wpn_cleaver":    {"kind":"weapon", "class":"barbarian", "name":"Worldsplitter", "rarity":"legendary", "r":"mw/worldsplitter_axe", "l":"", "source":"pass"},
	"rogue_wpn_fangs":     {"kind":"weapon", "class":"rogue", "name":"Viper Fangs", "rarity":"rare", "r":"mw/viper_fang", "l":"mw/viper_fang", "gold":1000, "source":"shop"},
	"rogue_wpn_knuckles":  {"kind":"weapon", "class":"rogue", "name":"Ravenclaws", "rarity":"epic", "r":"mw/ravenclaw_r", "l":"mw/ravenclaw_l", "source":"pass"},
	"rogue_wpn_reaper":    {"kind":"weapon", "class":"rogue", "name":"Grimgrin", "rarity":"legendary", "r":"mw/grimgrin_scythe", "l":"", "source":"pass"},
	"ranger_wpn_recurve":  {"kind":"weapon", "class":"ranger", "name":"Hawkeye", "rarity":"rare", "r":"", "l":"mw/hawkeye_bow", "gold":1000, "source":"shop"},
	"ranger_wpn_longbow":  {"kind":"weapon", "class":"ranger", "name":"Galeshot", "rarity":"epic", "r":"", "l":"mw/galeshot_bow", "source":"pass"},
	"ranger_wpn_spear":    {"kind":"weapon", "class":"ranger", "name":"Boarsbane", "rarity":"rare", "r":"mw/boarsbane_spear", "l":"", "source":"pass"},
	"mage_wpn_crystal":    {"kind":"weapon", "class":"mage", "name":"Starshard", "rarity":"epic", "r":"mw/starshard_staff", "l":"", "gems":250, "source":"shop"},
	"mage_wpn_elder":      {"kind":"weapon", "class":"mage", "name":"Eye of the Archon", "rarity":"legendary", "r":"mw/archon_staff", "l":"", "source":"pass"},
	"mage_wpn_twinwand":   {"kind":"weapon", "class":"mage", "name":"Twin Sparks", "rarity":"rare", "r":"mw/twinsparks_fire", "l":"mw/twinsparks_frost", "source":"pass"},
	"priest_wpn_sun":      {"kind":"weapon", "class":"priest", "name":"Solaris", "rarity":"legendary", "r":"mw/solaris_staff", "l":"", "source":"pass"},
	"priest_wpn_light":    {"kind":"weapon", "class":"priest", "name":"Candlewand", "rarity":"rare", "r":"mw/candle_wand", "l":"", "gold":900, "source":"shop"},
	"worker_wpn_mallet":   {"kind":"weapon", "class":"worker", "name":"Brickbreaker", "rarity":"rare", "r":"mw/brickbreaker_mallet", "l":"", "source":"pass"},
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
	# --- 0.31.38: the upgraded classes (0.31.39: weapons only)
	"crus_wpn_mace":       {"kind":"weapon", "class":"crusader", "name":"Penitent", "rarity":"rare", "r":"mw/penitent_mace", "l":"mw/penitent_shield", "gold":1200, "source":"shop"},
	"crus_wpn_warhammer":  {"kind":"weapon", "class":"crusader", "name":"Hallowed Bulwark", "rarity":"epic", "r":"mw/bulwark_hammer", "l":"mw/bulwark_shield", "gold":2400, "source":"shop"},
	"bers_wpn_twinaxe":    {"kind":"weapon", "class":"berserker", "name":"Ragebiter", "rarity":"rare", "r":"mw/ragebiter_axe", "l":"", "gold":1200, "source":"shop"},
	"bers_wpn_halberd":    {"kind":"weapon", "class":"berserker", "name":"Stormcleaver", "rarity":"epic", "r":"mw/stormcleaver_axe", "l":"", "gold":2400, "source":"shop"},
	"necro_wpn_tome":      {"kind":"weapon", "class":"necromancer", "name":"Gravecaller's Tome", "rarity":"rare", "r":"mw/gravecaller_staff", "l":"mw/gravecaller_tome", "gold":1200, "source":"shop"},
	"necro_wpn_scythe":    {"kind":"weapon", "class":"necromancer", "name":"Soulreaper", "rarity":"epic", "r":"mw/soulreaper_scythe", "l":"", "gold":2400, "source":"shop"},
	"assn_wpn_fangs":      {"kind":"weapon", "class":"assassin", "name":"Asp & Adder", "rarity":"rare", "r":"mw/asp_dagger", "l":"mw/asp_dagger", "gold":1200, "source":"shop"},
	"assn_wpn_fists":      {"kind":"weapon", "class":"assassin", "name":"Shadow Talons", "rarity":"epic", "r":"mw/shadow_talon_r", "l":"mw/shadow_talon_l", "gold":2400, "source":"shop"},
	"snip_wpn_recurve":    {"kind":"weapon", "class":"sniper", "name":"Longshot", "rarity":"rare", "r":"", "l":"mw/longshot_bow", "gold":1200, "source":"shop"},
	"snip_wpn_heartwood":  {"kind":"weapon", "class":"sniper", "name":"Heartseeker", "rarity":"epic", "r":"", "l":"mw/heartseeker_bow", "gold":2400, "source":"shop"},
	"arch_wpn_crystal":    {"kind":"weapon", "class":"archmage", "name":"Prism Staff", "rarity":"rare", "r":"mw/prism_staff", "l":"mw/prism_tome", "gold":1200, "source":"shop"},
	"arch_wpn_rod":        {"kind":"weapon", "class":"archmage", "name":"Voidrod", "rarity":"epic", "r":"mw/voidrod_staff", "l":"", "gold":2400, "source":"shop"},
	# --- 0.31.40: the rest of the KayKit weapons, given to the classes they suit (one-handed swords/axes/maces with
	# shields to the Knight and Crusader, big blades and axes to the Barbarian and Berserker, daggers and knuckles to the
	# Rogue and Assassin, bows to the archers, staves to the casters) ---
	"knight_wpn_arming":   {"kind":"weapon", "class":"knight", "name":"Steadfast", "rarity":"rare", "r":"mw/steadfast_sword", "l":"mw/steadfast_shield", "gold":1000, "source":"shop"},
	"knight_wpn_longsword":{"kind":"weapon", "class":"knight", "name":"Frostward", "rarity":"epic", "r":"mw/frostward_sword", "l":"mw/frostward_shield", "gold":2000, "source":"shop"},
	"knight_wpn_spiked":   {"kind":"weapon", "class":"knight", "name":"Ironbriar", "rarity":"epic", "r":"mw/ironbriar_sword", "l":"mw/ironbriar_shield", "gold":2200, "source":"shop"},
	"barb_wpn_bearded":    {"kind":"weapon", "class":"barbarian", "name":"Frostbeard", "rarity":"rare", "r":"mw/frostbeard_axe", "l":"mw/frostbeard_shield", "gold":1000, "source":"shop"},
	"barb_wpn_butcher":    {"kind":"weapon", "class":"barbarian", "name":"Bonecarver", "rarity":"epic", "r":"mw/bonecarver_cleaver", "l":"", "gold":2000, "source":"shop"},
	"barb_wpn_gauntlets":  {"kind":"weapon", "class":"barbarian", "name":"Rockfists", "rarity":"epic", "r":"mw/rockfist_r", "l":"mw/rockfist_l", "gold":2200, "source":"shop"},
	"rogue_wpn_stilettos": {"kind":"weapon", "class":"rogue", "name":"Needlepoint", "rarity":"rare", "r":"mw/needlepoint_stiletto", "l":"mw/needlepoint_stiletto", "gold":1000, "source":"shop"},
	"rogue_wpn_brass":     {"kind":"weapon", "class":"rogue", "name":"Alley Knuckles", "rarity":"rare", "r":"mw/alley_knuckles", "l":"mw/alley_knuckles", "gold":900, "source":"shop"},
	"ranger_wpn_hunting":  {"kind":"weapon", "class":"ranger", "name":"Stag Hunter", "rarity":"rare", "r":"", "l":"mw/staghunter_bow", "gold":1000, "source":"shop"},
	"mage_wpn_ritual":     {"kind":"weapon", "class":"mage", "name":"Hexblade", "rarity":"rare", "r":"mw/hex_knife", "l":"mw/hex_tome", "gold":1000, "source":"shop"},
	"priest_wpn_pilgrim":  {"kind":"weapon", "class":"priest", "name":"Wayfarer's Lantern", "rarity":"rare", "r":"mw/wayfarer_staff", "l":"", "gold":1000, "source":"shop"},
	"priest_wpn_mace":     {"kind":"weapon", "class":"priest", "name":"Sunrise Mace", "rarity":"epic", "r":"mw/sunrise_mace", "l":"mw/sunrise_shield", "gold":2000, "source":"shop"},
	"worker_wpn_felling":  {"kind":"weapon", "class":"worker", "name":"Timberfall", "rarity":"rare", "r":"mw/timberfall_axe", "l":"", "gold":900, "source":"shop"},
	"crus_wpn_maul":       {"kind":"weapon", "class":"crusader", "name":"Final Verdict", "rarity":"legendary", "r":"mw/verdict_maul", "l":"mw/verdict_shield", "gold":3600, "source":"shop"},
	"bers_wpn_broad":      {"kind":"weapon", "class":"berserker", "name":"Hidesplitter", "rarity":"rare", "r":"mw/hidesplitter_cleaver", "l":"", "gold":1200, "source":"shop"},
	"necro_wpn_spear":     {"kind":"weapon", "class":"necromancer", "name":"Wraithspine", "rarity":"epic", "r":"mw/wraithspine_spear", "l":"", "gold":2400, "source":"shop"},
	"assn_wpn_night":      {"kind":"weapon", "class":"assassin", "name":"Eclipse Blades", "rarity":"epic", "r":"mw/eclipse_dagger", "l":"mw/eclipse_dagger", "gold":2400, "source":"shop"},
	"snip_wpn_repeater":   {"kind":"weapon", "class":"sniper", "name":"Rattlesnake", "rarity":"rare", "r":"mw/rattlesnake_crossbow", "l":"", "gold":1200, "source":"shop"},
	"arch_wpn_elder":      {"kind":"weapon", "class":"archmage", "name":"Rootwise", "rarity":"rare", "r":"mw/rootwise_staff", "l":"mw/rootwise_tome", "gold":1200, "source":"shop"},
	# --- 0.31.97 (Kevin: "Build the quest system and I want quests for each class"): each class's legendary, earned by
	# its quest (QUESTS) -- never sold, not in the pass or chests
	"knight_wpn_kingsguard":  {"kind":"weapon", "class":"knight", "name":"Kingsguard", "rarity":"legendary", "r":"mw/kingsguard_sword", "l":"mw/kingsguard_shield", "source":"quest"},
	"barb_wpn_skyrender":     {"kind":"weapon", "class":"barbarian", "name":"Skyrender", "rarity":"legendary", "r":"mw/skyrender_axe", "l":"", "source":"quest"},
	"rogue_wpn_moonfang":     {"kind":"weapon", "class":"rogue", "name":"Moonfang", "rarity":"legendary", "r":"mw/moonfang_dagger", "l":"mw/moonfang_dagger", "source":"quest"},
	"ranger_wpn_dawnpiercer": {"kind":"weapon", "class":"ranger", "name":"Dawnpiercer", "rarity":"legendary", "r":"", "l":"mw/dawnpiercer_bow", "source":"quest"},
	"mage_wpn_emberheart":    {"kind":"weapon", "class":"mage", "name":"Emberheart", "rarity":"legendary", "r":"mw/emberheart_staff", "l":"", "source":"quest"},
	"priest_wpn_seraph":      {"kind":"weapon", "class":"priest", "name":"Seraph's Grace", "rarity":"legendary", "r":"mw/seraph_staff", "l":"", "source":"quest"},
	"worker_wpn_sledge":      {"kind":"weapon", "class":"worker", "name":"The Golden Sledge", "rarity":"legendary", "r":"mw/goldensledge_hammer", "l":"", "source":"quest"},
	"crus_wpn_oathbound":     {"kind":"weapon", "class":"crusader", "name":"Oathbound", "rarity":"legendary", "r":"mw/oathbound_hammer", "l":"mw/oathbound_shield", "source":"quest"},
	"bers_wpn_bloodroar":     {"kind":"weapon", "class":"berserker", "name":"Bloodroar", "rarity":"legendary", "r":"mw/bloodroar_demon", "l":"", "source":"quest"},
	"necro_wpn_lichcrown":    {"kind":"weapon", "class":"necromancer", "name":"Lichcrown", "rarity":"legendary", "r":"mw/lichcrown_staff", "l":"", "source":"quest"},
	"assn_wpn_lastbreath":    {"kind":"weapon", "class":"assassin", "name":"Last Breath", "rarity":"legendary", "r":"mw/lastbreath_dagger", "l":"mw/lastbreath_dagger", "source":"quest"},
	"snip_wpn_hawk":          {"kind":"weapon", "class":"sniper", "name":"Hawk's Judgment", "rarity":"legendary", "r":"mw/hawksjudgment_crossbow", "l":"", "source":"quest"},
	"arch_wpn_astral":        {"kind":"weapon", "class":"archmage", "name":"Astral Codex", "rarity":"legendary", "r":"mw/astral_staff", "l":"mw/astral_book", "source":"quest"},
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

# ---------------- packs (Round 11) ----------------
# Bundles sold for gems in the shop. You pay only for what you don't own yet (proportional to the
# items' value); a pack you fully own can't be bought.
const PACKS := {
	# 0.31.39: weapon bundles (each had a skin); priced at about 80 % of the items' value
	"pack_crusader": {"name":"Knight Arsenal", "class":"knight", "rarity":"epic", "gems":280, "items":["knight_wpn_bastion", "knight_wpn_crest"]},   # (0.31.87: the Gatebreaker title is earned now; 330 -> 280)
	"pack_warlord":  {"name":"Warlord Arsenal", "class":"barbarian", "rarity":"epic", "gems":260, "items":["barb_wpn_spiked", "barb_wpn_hammer"]},
	"pack_shadow":   {"name":"Shadow Arsenal", "class":"rogue", "rarity":"epic", "gems":250, "items":["rogue_wpn_bolt", "rogue_wpn_fangs"]},
	"pack_hunter":   {"name":"Hunter Arsenal", "class":"ranger", "rarity":"rare", "gems":120, "items":["ranger_wpn_recurve", "ranger_wpn_quiver"]},
	"pack_arcane":   {"name":"Arcane Arsenal", "class":"mage", "rarity":"epic", "gems":250, "items":["mage_wpn_crystal", "mage_wpn_tome"]},
}

static func item_value_gems(id: String) -> float:
	# Rough value of an item in gems (gold at the exchange's best rate, 4500 gold = 300 gems).
	var pr := item_price(id)
	if pr.has("gems"):
		return float(pr.gems)
	return float(pr.get("gold", 0)) * 300.0 / 4500.0

static func pack_price(pack_id: String, owned: Array) -> int:
	# Gems for the part of the pack not owned yet; 0 when everything is owned.
	var pk: Dictionary = PACKS.get(pack_id, {})
	if pk.is_empty():
		return 0
	var total := 0.0
	var missing := 0.0
	for id in pk.items:
		var v := item_value_gems(id)
		total += v
		if not owned.has(id):
			missing += v
	if missing <= 0.0:
		return 0
	return maxi(10, int(round(float(pk.gems) * missing / maxf(1.0, total) / 10.0)) * 10)

static func item(id: String) -> Dictionary:
	return CATALOG.get(id, {})

static func item_price(id: String) -> Dictionary:
	var it := item(id)
	if it.has("gems"):
		return {"gems": int(it.gems)}
	if it.has("gold"):
		return {"gold": int(it.gold)}
	return {}

# ---------------- shop rotation ----------------
const DAILY_SLOTS := 6              # 0.31.38: 4 -> 6 (gold items in rotation went 19 -> 43 with the upgraded classes)
const FEATURED_SLOTS := 3           # 2 -> 3 (gem items 9 -> 15)
const EXCHANGE := [{"id":"gold_s", "gems":50, "gold":600}, {"id":"gold_m", "gems":120, "gold":1600}, {"id":"gold_l", "gems":300, "gold":4500}]

static func day_key(unix: int) -> String:
	var d := Time.get_date_dict_from_unix_time(unix)
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]

static func week_key(unix: int) -> String:
	# Weeks start Monday 00:00 UTC.
	var days := int(floor(unix / 86400.0))
	var monday := days - ((days + 3) % 7)            # 1970-01-01 was a Thursday
	return day_key(monday * 86400)

static func shop_daily(unix: int) -> Array:
	return _rotation("daily-" + day_key(unix), "gold", DAILY_SLOTS)

static func shop_featured(unix: int) -> Array:
	return _rotation("featured-" + week_key(unix), "gems", FEATURED_SLOTS)

static func _rotation(key: String, currency: String, n: int) -> Array:
	var pool: Array = []
	for id in CATALOG:
		var it: Dictionary = CATALOG[id]
		if it.get("source", "") == "shop" and it.has(currency):
			pool.append(id)
	pool.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var out := []
	while out.size() < n and not pool.is_empty():
		out.append(pool.pop_at(rng.randi() % pool.size()))
	return out

# ---------------- challenges ----------------
# stat keys come from match_stats(): wins, matches, rescues, kills, gates (gate damage / 100),
# gathered, fed, lifts (Oracle lifts joined), class_<name> (matches finished as that class).
const CHALLENGES := {
	"win1":     {"text":"Win a match", "stat":"wins", "goal":1, "pass":500, "gold":100, "span":"daily"},
	"play3":    {"text":"Play 3 matches", "stat":"matches", "goal":3, "pass":400, "gold":80, "span":"daily"},
	"rescue1":  {"text":"Rescue your King", "stat":"rescues", "goal":1, "pass":600, "gold":120, "span":"daily"},
	"kos15":    {"text":"Knock out 15 enemies", "stat":"kills", "goal":15, "pass":400, "gold":80, "span":"daily"},
	"gate5":    {"text":"Deal 500 gate damage", "stat":"gates", "goal":5, "pass":450, "gold":90, "span":"daily"},
	"gather40": {"text":"Gather 40 wood or stone", "stat":"gathered", "goal":40, "pass":400, "gold":80, "span":"daily"},
	"feed3":    {"text":"Feed 3 fish to their King", "stat":"fed", "goal":3, "pass":450, "gold":90, "span":"daily"},
	"lift2":    {"text":"Help lift your King twice", "stat":"lifts", "goal":2, "pass":400, "gold":80, "span":"daily"},
	"w_win5":   {"text":"Win 5 matches", "stat":"wins", "goal":5, "pass":2000, "gems":40, "span":"weekly"},
	"w_rescue4":{"text":"Rescue your King 4 times", "stat":"rescues", "goal":4, "pass":2000, "gems":40, "span":"weekly"},
	"w_kos100": {"text":"Knock out 100 enemies", "stat":"kills", "goal":100, "pass":1800, "gems":30, "span":"weekly"},
	"w_gate30": {"text":"Deal 3,000 gate damage", "stat":"gates", "goal":30, "pass":1800, "gems":30, "span":"weekly"},
	"w_feed12": {"text":"Feed 12 fish", "stat":"fed", "goal":12, "pass":1800, "gems":30, "span":"weekly"},
	"w_play12": {"text":"Play 12 matches", "stat":"matches", "goal":12, "pass":1600, "gems":25, "span":"weekly"},
}
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
const FIRST_WIN := {"gold":300, "pass":500}

static func match_stats(me: Dictionary, won: bool, _draw: bool) -> Dictionary:
	# Contribution numbers from the player's unit at the end of a match (offline or online).
	var s := {"matches":1, "wins":1 if won else 0, "rescues":int(me.get("rescues", 0)), "kills":int(me.get("kills", 0)),
		"gates":int(float(me.get("gate_dmg", 0.0)) / 100.0), "gathered":int(me.get("gathered", 0)), "fed":int(me.get("fed", 0)),
		"lifts":int(me.get("lifts", 0))}
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
	"title_woodcutter":     {"stat":"gathered", "n":200, "task":"Gather 200 wood or stone", "cls":""},
	"title_fishmonger":     {"stat":"fed", "n":10, "task":"Feed 10 fish to your King", "cls":""},
	"title_gatebreaker":    {"stat":"gates", "n":100, "task":"Deal 10,000 gate damage", "cls":""},
	"title_kingbearer":     {"stat":"lifts", "n":25, "task":"Help lift your King 25 times", "cls":""},
	"title_many_hats":      {"stat":"classes", "n":7, "task":"Play a match as each of the 7 classes", "cls":""},
	"title_tempest":        {"stat":"best_multi", "n":3, "task":"Knock out 3 enemies in one burst", "cls":""},
	"title_relentless":     {"stat":"best_streak", "n":5, "task":"Win 5 matches in a row", "cls":""},
	"title_cake_baron":     {"stat":"fed", "n":100, "task":"Feed 100 fish to your King", "cls":""},
	"title_siege_lord":     {"stat":"wins", "n":50, "task":"Win 50 matches", "cls":""},
	"title_oracle_sworn":   {"stat":"rescues", "n":50, "task":"Rescue your King 50 times", "cls":""},
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
	"title_foreman":        {"stat":"win_worker", "n":10, "task":"Win 10 matches as Worker", "cls":"worker"},
	"title_mason":          {"stat":"repaired", "n":20000, "task":"Repair 20,000 gate health", "cls":"worker"},
	"title_master_builder": {"stat":"gathered", "n":5000, "task":"Gather 5,000 wood or stone", "cls":"worker"},
}
const TITLE_RARITY_ORDER := ["common", "rare", "epic", "legendary"]

# ---------------- class quests (0.31.97, Kevin: "Build the quest system and I want quests for each class") ----------------
# Every class has one quest: three steps, claimed in order; the first two pay out (QUEST_REWARDS), the third gives the
# class's legendary weapon (source "quest": never sold, not in the pass or chests). Progress is a lifetime count in the
# profile's stats, "q_<class>_<stat>", kept from 0.31.97 on and credited to the class you were when you did it: a base
# class counts its upgrade too (a Crusader's knockouts are a Knight's), an upgraded class only while in its hat. A match
# counts as played (and won) as a class after QUEST_MIN_TIME seconds as it. Stats: matches, wins, kills, rescues, gates
# (per 100 gate damage), gathered, fed, repaired / healed (health), lifts (King lifts joined), best_multi (the most
# knockouts in one burst -- a best, not a sum).
const QUEST_MIN_TIME := 60.0
const QUEST_COUNTS := ["kills", "rescues", "gates", "gathered", "fed", "repaired", "healed", "lifts"]
const QUEST_REWARDS := [{"gold":400, "embers":30}, {"gems":50, "chest":"gold"}]      # steps 1 and 2; step 3 is the weapon
const QUESTS := {
	"knight":      {"item":"knight_wpn_kingsguard", "steps":[
		{"stat":"wins", "n":3, "task":"Win 3 matches as a Knight"},
		{"stat":"rescues", "n":10, "task":"Rescue your King 10 times as a Knight"},
		{"stat":"kills", "n":500, "task":"Knock out 500 enemies as a Knight"}]},
	"barbarian":   {"item":"barb_wpn_skyrender", "steps":[
		{"stat":"kills", "n":40, "task":"Knock out 40 enemies as a Barbarian"},
		{"stat":"gates", "n":100, "task":"Deal 10,000 gate damage as a Barbarian"},
		{"stat":"wins", "n":60, "task":"Win 60 matches as a Barbarian"}]},
	"rogue":       {"item":"rogue_wpn_moonfang", "steps":[
		{"stat":"kills", "n":40, "task":"Knock out 40 enemies as a Rogue"},
		{"stat":"best_multi", "n":3, "task":"Knock out 3 enemies in one burst as a Rogue"},
		{"stat":"kills", "n":750, "task":"Knock out 750 enemies as a Rogue"}]},
	"ranger":      {"item":"ranger_wpn_dawnpiercer", "steps":[
		{"stat":"kills", "n":40, "task":"Knock out 40 enemies as an Archer"},
		{"stat":"wins", "n":25, "task":"Win 25 matches as an Archer"},
		{"stat":"kills", "n":750, "task":"Knock out 750 enemies as an Archer"}]},
	"mage":        {"item":"mage_wpn_emberheart", "steps":[
		{"stat":"kills", "n":40, "task":"Knock out 40 enemies as a Mage"},
		{"stat":"lifts", "n":15, "task":"Help lift your King 15 times as a Mage"},
		{"stat":"wins", "n":60, "task":"Win 60 matches as a Mage"}]},
	"priest":      {"item":"priest_wpn_seraph", "steps":[
		{"stat":"healed", "n":2000, "task":"Heal 2,000 health as a Priest"},
		{"stat":"rescues", "n":10, "task":"Rescue your King 10 times as a Priest"},
		{"stat":"wins", "n":60, "task":"Win 60 matches as a Priest"}]},
	"worker":      {"item":"worker_wpn_sledge", "steps":[
		{"stat":"gathered", "n":300, "task":"Gather 300 wood or stone"},
		{"stat":"repaired", "n":10000, "task":"Repair 10,000 gate health"},
		{"stat":"wins", "n":60, "task":"Win 60 matches as a Worker"}]},
	"crusader":    {"item":"crus_wpn_oathbound", "steps":[
		{"stat":"kills", "n":25, "task":"Knock out 25 enemies as a Crusader"},
		{"stat":"rescues", "n":8, "task":"Rescue your King 8 times as a Crusader"},
		{"stat":"wins", "n":30, "task":"Win 30 matches as a Crusader"}]},
	"berserker":   {"item":"bers_wpn_bloodroar", "steps":[
		{"stat":"kills", "n":25, "task":"Knock out 25 enemies as a Berserker"},
		{"stat":"gates", "n":80, "task":"Deal 8,000 gate damage as a Berserker"},
		{"stat":"wins", "n":30, "task":"Win 30 matches as a Berserker"}]},
	"necromancer": {"item":"necro_wpn_lichcrown", "steps":[
		{"stat":"kills", "n":25, "task":"Knock out 25 enemies as a Necromancer"},
		{"stat":"healed", "n":3000, "task":"Heal 3,000 health as a Necromancer"},
		{"stat":"wins", "n":30, "task":"Win 30 matches as a Necromancer"}]},
	"assassin":    {"item":"assn_wpn_lastbreath", "steps":[
		{"stat":"kills", "n":25, "task":"Knock out 25 enemies as an Assassin"},
		{"stat":"best_multi", "n":3, "task":"Knock out 3 enemies in one burst as an Assassin"},
		{"stat":"kills", "n":400, "task":"Knock out 400 enemies as an Assassin"}]},
	"sniper":      {"item":"snip_wpn_hawk", "steps":[
		{"stat":"kills", "n":25, "task":"Knock out 25 enemies as a Ranger"},
		{"stat":"wins", "n":20, "task":"Win 20 matches as a Ranger"},
		{"stat":"kills", "n":400, "task":"Knock out 400 enemies as a Ranger"}]},
	"archmage":    {"item":"arch_wpn_astral", "steps":[
		{"stat":"kills", "n":25, "task":"Knock out 25 enemies as an Archmage"},
		{"stat":"lifts", "n":10, "task":"Help lift your King 10 times as an Archmage"},
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
	# what claiming step (0-based) gives: QUEST_REWARDS, or the class's legendary for the last
	if step < QUEST_REWARDS.size():
		return QUEST_REWARDS[step]
	return {"item": str(QUESTS[cls].item)}

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

static func match_rewards(stats: Dictionary, won: bool, draw: bool, online: bool, first_win: bool) -> Dictionary:
	# Itemised so the results screen can show where every coin came from.
	var lines := []
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
		lines.append({"label":"Gate damage", "gold":2 * gd, "xp":3 * gd, "pass":3 * gd})
	var f: int = mini(10, int(stats.get("fed", 0)))
	if f > 0:
		lines.append({"label":"Fish fed x%d" % f, "gold":10 * f, "xp":10 * f, "pass":15 * f})
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
const CHESTS := {
	"wooden": {"name":"Wooden Chest", "unlock":1800, "gold":[60, 120], "gems_chance":0.10, "gems":[5, 5],
		"item_chance":0.15, "rarity":{"common":0.6, "rare":0.4}, "color":"#a8794a"},
	"silver": {"name":"Silver Chest", "unlock":3 * 3600, "gold":[150, 250], "gems_chance":1.0, "gems":[5, 10],
		"item_chance":0.35, "rarity":{"rare":0.75, "epic":0.25}, "color":"#c9d3dc"},
	"gold":   {"name":"Gold Chest", "unlock":8 * 3600, "gold":[400, 600], "gems_chance":1.0, "gems":[15, 25],
		"item_chance":1.0, "rarity":{"rare":0.8, "epic":0.2}, "color":"#ffcf4a"},
	"royal":  {"name":"Royal Chest", "unlock":12 * 3600, "gold":[1000, 1000], "gems_chance":1.0, "gems":[40, 60],
		"item_chance":1.0, "rarity":{"epic":0.85, "legendary":0.15}, "color":"#c47bff"},
}
const CHEST_FULL_GOLD := {"wooden":50, "silver":120, "gold":300, "royal":700}   # slots full: the chest becomes gold
const DUPE_GOLD := {"common":100, "rare":250, "epic":600, "legendary":1500}       # (until 0.31.92: a cosmetic already owned; the starter pack's fallback)
const PITY_EPIC := 10              # Gold/Royal chests: an epic or better at the latest every 10th

static func skip_cost(remaining_s: int) -> int:
	return maxi(1, int(ceil(float(remaining_s) / 600.0)))

static func chest_pool(rarity: String) -> Array:
	# cosmetics that can drop: the shop's (the pass's own stay the pass's)
	var ids := []
	for id in CATALOG:
		var it: Dictionary = CATALOG[id]
		if str(it.get("source", "")) == "shop" and str(it.get("rarity", "")) == rarity and str(it.get("kind", "")) == "weapon":
			ids.append(id)
	return ids

static func roll_chest(kind: String, seed_value: int, owned: Array, pity: int) -> Dictionary:
	# -> {gold, gems, item ("" if none), dupe_embers, pity (the new count)}
	var c: Dictionary = CHESTS[kind]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := {"gold":rng.randi_range(int(c.gold[0]), int(c.gold[1])), "gems":0, "item":"", "dupe_embers":0, "pity":pity}
	if rng.randf() < float(c.gems_chance):
		out.gems = rng.randi_range(int(c.gems[0]), int(c.gems[1]))
	if rng.randf() < float(c.item_chance):
		var rar := ""
		var roll := rng.randf()
		var acc := 0.0
		for r in c.rarity:
			acc += float(c.rarity[r])
			if roll <= acc:
				rar = r
				break
		if rar == "":
			rar = c.rarity.keys()[-1]
		var big: bool = kind in ["gold", "royal"]
		if big and pity + 1 >= PITY_EPIC and rar in ["common", "rare"]:
			rar = "epic"                              # bad-luck protection
		if big:
			out.pity = 0 if rar in ["epic", "legendary"] else pity + 1
		var pool := chest_pool(rar)
		if pool.is_empty():
			pool = chest_pool("rare")
		if not pool.is_empty():
			var id: String = pool[rng.randi_range(0, pool.size() - 1)]
			if owned.has(id):
				out.dupe_embers = int(EMBERS_DUPE.get(rar, 25))      # 0.31.93: Embers for the Forge (was gold)
			else:
				out.item = id
	return out

static func chest_odds(kind: String) -> String:
	# for the info panel: what's in it, plainly
	var c: Dictionary = CHESTS[kind]
	var parts := ["%d-%d gold" % [int(c.gold[0]), int(c.gold[1])]]
	if float(c.gems_chance) >= 1.0:
		parts.append("%d-%d gems" % [int(c.gems[0]), int(c.gems[1])])
	else:
		parts.append("%d%% chance of %d gems" % [int(round(float(c.gems_chance) * 100.0)), int(c.gems[0])])
	var rs := []
	for r in c.rarity:
		rs.append("%s %d%%" % [str(r).capitalize(), int(round(float(c.rarity[r]) * 100.0))])
	parts.append("%s: %s" % ["a cosmetic" if float(c.item_chance) >= 1.0 else "%d%% chance of a cosmetic" % int(round(float(c.item_chance) * 100.0)), ", ".join(rs)])
	if kind in ["gold", "royal"]:
		parts.append("an epic or better at least every %d" % PITY_EPIC)
	parts.append("duplicates turn into Embers for the Forge")
	return " · ".join(parts)


# ---------------- the Forge (0.31.93, Armory Reforged; Kevin: "begin the weapon models and forge system") ----------------
# Bring a weapon you own (a starter too) and raise it to three stars: the same weapon, more impressive each time. Looks
# only, never damage. Paid in Embers (earned by playing, or bought with gems here) plus gold; the third star also needs
# FORGE_WINS wins with that weapon equipped, and picks the aura's element.
const FORGE_STARS := [
	{"name":"Polished", "embers":40, "gold":500, "text":"Brighter metal and a sheen in its rarity's colour."},
	{"name":"Runed", "embers":120, "gold":1500, "text":"Glowing runes that pulse along the weapon."},
	{"name":"Ascended", "embers":300, "gold":4000, "text":"An aura and a swing trail in the element you pick."}]
const FORGE_WINS := 25
const EMBERS_DUPE := {"common":10, "rare":25, "epic":60, "legendary":150}      # a duplicate from a chest
const EMBERS_MATCH := 2                 # every finished match ...
const EMBERS_WIN := 5                   # ... or this for a win
const EMBERS_DAILY := 15                # each daily challenge claimed
const PASS_EMBERS_FREE := 20            # pass tiers 2, 6, 10 ... on the free track
const PASS_EMBERS_PREMIUM := 40         # ... and on the premium track
const EMBER_PACKS := [{"id":"embers_s", "gems":60, "embers":60}, {"id":"embers_m", "gems":150, "embers":170},
	{"id":"embers_l", "gems":400, "embers":500}]
const ELEMENTS := ["fire", "frost", "storm", "holy", "nature", "void"]
const ELEMENT_COLOR := {"fire":"#ff7a2e", "frost":"#7fd8ff", "storm":"#b48cff", "holy":"#ffd76a", "nature":"#7dff8a", "void":"#c04dff"}
const ELEMENT_NAME := {"fire":"Fire", "frost":"Frost", "storm":"Storm", "holy":"Holy", "nature":"Nature", "void":"Void"}

static func forge_id(cls: String, item_id: String) -> String:
	# what the Forge keys a weapon by: its catalog id, or "default_<cls>" for a class's starter
	return item_id if item_id != "" else "default_" + cls

static func forge_class(wid: String) -> String:
	return wid.substr(8) if wid.begins_with("default_") else str(item(wid).get("class", ""))

static func forge_rarity(wid: String) -> String:
	return "common" if wid.begins_with("default_") else str(item(wid).get("rarity", "common"))

static func forge_name(wid: String) -> String:
	if wid.begins_with("default_"):
		return str(STARTER_NAMES.get(wid.substr(8), "Default gear"))
	return str(item(wid).get("name", ""))

static func forge_cost(next_star: int) -> Dictionary:
	# next_star 1..3 -> {"embers", "gold"}; {} past the third
	if next_star < 1 or next_star > FORGE_STARS.size():
		return {}
	var f: Dictionary = FORGE_STARS[next_star - 1]
	return {"embers":int(f.embers), "gold":int(f.gold)}

static func ember_pack(id: String) -> Dictionary:
	for p in EMBER_PACKS:
		if str(p.id) == id:
			return p
	return {}
