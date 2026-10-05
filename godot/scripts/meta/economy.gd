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
const UP_LOOK := {"crusader":"knight", "berserker":"berserker", "necromancer":"necromancer", "assassin":"assassin", "sniper":"sniper", "archmage":"archmage"}
const CLASS_NAMES := {"knight":"Knight", "barbarian":"Barbarian", "rogue":"Rogue", "ranger":"Ranger", "mage":"Mage", "priest":"Priest", "worker":"Worker",
	"crusader":"Crusader", "berserker":"Berserker", "necromancer":"Necromancer", "assassin":"Assassin", "sniper":"Sniper", "archmage":"Archmage"}

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
	var season_skins: Array = pass_items(sid)
	# Round 11: 6 free + 10 premium cosmetics per season (was 3 + 5).
	if not premium:
		if tier % 5 == 0:
			return {"item": season_skins[tier / 5 - 1]}                       # tiers 5..30: 6 free
		if tier == 12 or tier == 24:
			return {"chest": "silver"}                                         # 0.31.37
		if tier % 4 == 0:
			return {"gems": 30}
		return {"gold": 150 + 5 * tier}
	if tier % 3 == 0:
		return {"item": season_skins[PASS_FREE_ITEMS + tier / 3 - 1]}        # tiers 3..30: 10 premium
	if tier == 8 or tier == 16:
		return {"chest": "gold"}                                               # 0.31.37
	if tier == 28:
		return {"chest": "royal"}
	if tier % 4 == 0:
		return {"gems": 60}
	return {"gold": 300 + 10 * tier}

const PASS_FREE_ITEMS := 6
const PASS_PREMIUM_ITEMS := 10

static func pass_items(sid: int) -> Array:
	# 6 free + 10 premium cosmetics for season `sid`, chosen from the "pass" pool.
	var pool: Array = []
	for id in CATALOG:
		if CATALOG[id].get("source", "") == "pass":
			pool.append(id)
	pool.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("pass-%d" % sid)
	var out := []
	var src := pool.duplicate()
	var want := PASS_FREE_ITEMS + PASS_PREMIUM_ITEMS
	while out.size() < want and not src.is_empty():
		out.append(src.pop_at(rng.randi() % src.size()))
	while out.size() < want:
		out.append(pool[out.size() % pool.size()])
	return out

# ---------------- cosmetics ----------------
# kind "weapon": right/left hand models for a class (0.31.39: the only class cosmetic -- no skins/tints, so every
# class keeps its own readable look). kind "title": text on the profile.
# kind "title": text shown on the profile. source "shop" (gold/gems), "pass", "level".
const CATALOG := {
	# --- Knight
	"knight_wpn_greatsword":{"kind":"weapon", "class":"knight", "name":"Greatsword", "rarity":"rare", "r":"sword_2handed", "l":"", "gold":900, "source":"shop"},
	"knight_wpn_crest":    {"kind":"weapon", "class":"knight", "name":"Sword & Crest", "rarity":"rare", "r":"sword_1handed", "l":"shield_badge_color", "gold":1100, "source":"shop"},
	"knight_wpn_tower":    {"kind":"weapon", "class":"knight", "name":"Sword & Tower Shield", "rarity":"epic", "r":"sword_1handed", "l":"shield_square_color", "gems":250, "source":"shop"},
	"knight_wpn_crimson":  {"kind":"weapon", "class":"knight", "name":"Crimson Greatsword", "rarity":"epic", "r":"sword_2handed_color", "l":"", "source":"pass"},
	# --- Barbarian
	"barb_wpn_raider":     {"kind":"weapon", "class":"barbarian", "name":"Axe & Buckler", "rarity":"rare", "r":"axe_1handed", "l":"shield_round_barbarian", "gold":1000, "source":"shop"},
	"barb_wpn_spiked":     {"kind":"weapon", "class":"barbarian", "name":"Axe & Spiked Shield", "rarity":"epic", "r":"axe_1handed", "l":"shield_spikes_color", "gems":250, "source":"shop"},
	# --- Rogue
	"rogue_wpn_bomb":      {"kind":"weapon", "class":"rogue", "name":"Dagger & Smoke Bomb", "rarity":"rare", "r":"dagger", "l":"smokebomb", "gold":900, "source":"shop"},
	"rogue_wpn_bolt":      {"kind":"weapon", "class":"rogue", "name":"Hand Crossbow", "rarity":"epic", "r":"dagger", "l":"crossbow_1handed", "gems":250, "source":"shop"},
	# --- Ranger
	"ranger_wpn_crossbow": {"kind":"weapon", "class":"ranger", "name":"Heavy Crossbow", "rarity":"epic", "r":"", "l":"crossbow_2handed", "source":"pass"},
	"ranger_wpn_quiver":   {"kind":"weapon", "class":"ranger", "name":"Bow & Quiver", "rarity":"rare", "r":"quiver", "l":"bow_withString", "gold":900, "source":"shop"},
	# --- Mage
	"mage_wpn_tome":       {"kind":"weapon", "class":"mage", "name":"Wand & Tome", "rarity":"rare", "r":"wand", "l":"spellbook_open", "gold":1000, "source":"shop"},
	"mage_wpn_wand":       {"kind":"weapon", "class":"mage", "name":"Wand", "rarity":"common", "r":"wand", "l":"", "gold":500, "source":"shop"},
	# --- Worker
	"worker_wpn_mug":      {"kind":"weapon", "class":"worker", "name":"Axe & Ale", "rarity":"rare", "r":"axe_1handed", "l":"mug_full", "source":"pass"},
	# --- Round 11: KayKit Fantasy Weapons Bits ("bits/<model>") and the Priest
	"knight_wpn_bastion":  {"kind":"weapon", "class":"knight", "name":"Bastion Guard", "rarity":"epic", "r":"bits/sword_B", "l":"bits/shield_D", "gems":280, "source":"shop"},
	"knight_wpn_oath":     {"kind":"weapon", "class":"knight", "name":"Oathkeeper", "rarity":"legendary", "r":"bits/sword_G", "l":"bits/shield_C", "source":"pass"},
	"knight_wpn_halberd":  {"kind":"weapon", "class":"knight", "name":"Halberd", "rarity":"epic", "r":"bits/halberd", "l":"", "source":"pass"},
	"barb_wpn_hammer":     {"kind":"weapon", "class":"barbarian", "name":"War Hammer", "rarity":"rare", "r":"bits/hammer_C", "l":"", "gold":1100, "source":"shop"},
	"barb_wpn_twinaxe":    {"kind":"weapon", "class":"barbarian", "name":"Twin Axes", "rarity":"epic", "r":"bits/axe_B", "l":"bits/axe_B", "source":"pass"},
	"barb_wpn_cleaver":    {"kind":"weapon", "class":"barbarian", "name":"Great Cleaver", "rarity":"legendary", "r":"bits/axe_D", "l":"", "source":"pass"},
	"rogue_wpn_fangs":     {"kind":"weapon", "class":"rogue", "name":"Fang Daggers", "rarity":"rare", "r":"bits/dagger_B", "l":"bits/dagger_B", "gold":1000, "source":"shop"},
	"rogue_wpn_knuckles":  {"kind":"weapon", "class":"rogue", "name":"Brass Knuckles", "rarity":"epic", "r":"bits/fistweapon_C_right", "l":"bits/fistweapon_C_left", "source":"pass"},
	"rogue_wpn_reaper":    {"kind":"weapon", "class":"rogue", "name":"Reaper", "rarity":"legendary", "r":"bits/scythe", "l":"", "source":"pass"},
	"ranger_wpn_recurve":  {"kind":"weapon", "class":"ranger", "name":"Recurve", "rarity":"rare", "r":"", "l":"bits/bow_B_withString", "gold":1000, "source":"shop"},
	"ranger_wpn_longbow":  {"kind":"weapon", "class":"ranger", "name":"Longbow", "rarity":"epic", "r":"", "l":"bits/bow_C_withString", "source":"pass"},
	"ranger_wpn_spear":    {"kind":"weapon", "class":"ranger", "name":"Hunter's Spear", "rarity":"rare", "r":"bits/spear_A", "l":"", "source":"pass"},
	"mage_wpn_crystal":    {"kind":"weapon", "class":"mage", "name":"Crystal Staff", "rarity":"epic", "r":"bits/staff_B", "l":"", "gems":250, "source":"shop"},
	"mage_wpn_elder":      {"kind":"weapon", "class":"mage", "name":"Elder Staff", "rarity":"legendary", "r":"bits/staff_D", "l":"", "source":"pass"},
	"mage_wpn_twinwand":   {"kind":"weapon", "class":"mage", "name":"Twin Wands", "rarity":"rare", "r":"bits/wand_A", "l":"bits/wand_A", "source":"pass"},
	"priest_wpn_sun":      {"kind":"weapon", "class":"priest", "name":"Sun Staff", "rarity":"legendary", "r":"bits/staff_C", "l":"", "source":"pass"},
	"priest_wpn_light":    {"kind":"weapon", "class":"priest", "name":"Lightwand", "rarity":"rare", "r":"bits/wand_B", "l":"", "gold":900, "source":"shop"},
	"worker_wpn_mallet":   {"kind":"weapon", "class":"worker", "name":"War Mallet", "rarity":"rare", "r":"bits/hammer_A", "l":"", "source":"pass"},
	"title_shieldwall":    {"kind":"title", "class":"", "name":"Shieldwall", "rarity":"epic", "source":"pass"},
	"title_whirlwind":     {"kind":"title", "class":"", "name":"Whirlwind", "rarity":"epic", "source":"pass"},
	"title_lightbringer":  {"kind":"title", "class":"", "name":"Lightbringer", "rarity":"legendary", "source":"pass"},
	# --- Titles
	"title_gatebreaker":   {"kind":"title", "class":"", "name":"Gatebreaker", "rarity":"rare", "gold":800, "source":"shop"},
	"title_cake_baron":    {"kind":"title", "class":"", "name":"Fish Baron", "rarity":"epic", "source":"pass"},
	"title_oracle_sworn":  {"kind":"title", "class":"", "name":"Kingsworn", "rarity":"legendary", "gems":300, "source":"shop"},
	"title_siege_lord":    {"kind":"title", "class":"", "name":"Siege Lord", "rarity":"epic", "source":"pass"},
	# --- 0.31.38: the upgraded classes (0.31.39: weapons only)
	"crus_wpn_mace":       {"kind":"weapon", "class":"crusader", "name":"Mace & Kite Shield", "rarity":"rare", "r":"bits/hammer_C", "l":"bits/shield_A", "gold":1200, "source":"shop"},
	"crus_wpn_warhammer":  {"kind":"weapon", "class":"crusader", "name":"Warhammer & Bulwark", "rarity":"epic", "r":"bits/hammer_A", "l":"bits/shield_D", "gold":2400, "source":"shop"},
	"bers_wpn_twinaxe":    {"kind":"weapon", "class":"berserker", "name":"Twin-Edged Axe", "rarity":"rare", "r":"axe_2handed", "l":"", "gold":1200, "source":"shop"},
	"bers_wpn_halberd":    {"kind":"weapon", "class":"berserker", "name":"Great Halberd", "rarity":"epic", "r":"bits/halberd", "l":"", "gold":2400, "source":"shop"},
	"necro_wpn_tome":      {"kind":"weapon", "class":"necromancer", "name":"Grim Tome", "rarity":"rare", "r":"Skeleton_Staff", "l":"spellbook_open", "gold":1200, "source":"shop"},
	"necro_wpn_scythe":    {"kind":"weapon", "class":"necromancer", "name":"Reaper's Scythe", "rarity":"epic", "r":"bits/scythe", "l":"", "gold":2400, "source":"shop"},
	"assn_wpn_fangs":      {"kind":"weapon", "class":"assassin", "name":"Serpent Fangs", "rarity":"rare", "r":"bits/dagger_B", "l":"bits/dagger_B", "gold":1200, "source":"shop"},
	"assn_wpn_fists":      {"kind":"weapon", "class":"assassin", "name":"Shadow Claws", "rarity":"epic", "r":"bits/fistweapon_C_right", "l":"bits/fistweapon_C_left", "gold":2400, "source":"shop"},
	"snip_wpn_recurve":    {"kind":"weapon", "class":"sniper", "name":"Recurve Longbow", "rarity":"rare", "r":"", "l":"bits/bow_B_withString", "gold":1200, "source":"shop"},
	"snip_wpn_heartwood":  {"kind":"weapon", "class":"sniper", "name":"Heartwood Bow", "rarity":"epic", "r":"", "l":"bits/bow_C_withString", "gold":2400, "source":"shop"},
	"arch_wpn_crystal":    {"kind":"weapon", "class":"archmage", "name":"Crystal Staff & Tome", "rarity":"rare", "r":"bits/staff_C", "l":"spellbook_open", "gold":1200, "source":"shop"},
	"arch_wpn_rod":        {"kind":"weapon", "class":"archmage", "name":"Arcane Rod", "rarity":"epic", "r":"bits/staff_D", "l":"", "gold":2400, "source":"shop"},
	# --- 0.31.40: the rest of the KayKit weapons, given to the classes they suit (one-handed swords/axes/maces with
	# shields to the Knight and Crusader, big blades and axes to the Barbarian and Berserker, daggers and knuckles to the
	# Rogue and Assassin, bows to the archers, staves to the casters) ---
	"knight_wpn_arming":   {"kind":"weapon", "class":"knight", "name":"Arming Sword & Round Shield", "rarity":"rare", "r":"bits/sword_A", "l":"shield_round", "gold":1000, "source":"shop"},
	"knight_wpn_longsword":{"kind":"weapon", "class":"knight", "name":"Longsword & Square Shield", "rarity":"epic", "r":"bits/sword_C", "l":"shield_square", "gold":2000, "source":"shop"},
	"knight_wpn_spiked":   {"kind":"weapon", "class":"knight", "name":"Broadsword & Spiked Shield", "rarity":"epic", "r":"bits/sword_D", "l":"shield_spikes", "gold":2200, "source":"shop"},
	"barb_wpn_bearded":    {"kind":"weapon", "class":"barbarian", "name":"Bearded Axe & Buckler", "rarity":"rare", "r":"bits/axe_A", "l":"shield_round_color", "gold":1000, "source":"shop"},
	"barb_wpn_butcher":    {"kind":"weapon", "class":"barbarian", "name":"Butcher's Blade", "rarity":"epic", "r":"bits/sword_F", "l":"", "gold":2000, "source":"shop"},
	"barb_wpn_gauntlets":  {"kind":"weapon", "class":"barbarian", "name":"Brawler's Gauntlets", "rarity":"epic", "r":"bits/fistweapon_B", "l":"bits/fistweapon_B", "gold":2200, "source":"shop"},
	"rogue_wpn_stilettos": {"kind":"weapon", "class":"rogue", "name":"Twin Stilettos", "rarity":"rare", "r":"bits/dagger_A", "l":"bits/dagger_A", "gold":1000, "source":"shop"},
	"rogue_wpn_brass":     {"kind":"weapon", "class":"rogue", "name":"Brass Knuckles", "rarity":"rare", "r":"bits/fistweapon_A", "l":"bits/fistweapon_A", "gold":900, "source":"shop"},
	"ranger_wpn_hunting":  {"kind":"weapon", "class":"ranger", "name":"Hunting Bow", "rarity":"rare", "r":"", "l":"bits/bow_A_withString", "gold":1000, "source":"shop"},
	"mage_wpn_ritual":     {"kind":"weapon", "class":"mage", "name":"Ritual Knife & Tome", "rarity":"rare", "r":"bits/dagger_C", "l":"spellbook_open", "gold":1000, "source":"shop"},
	"priest_wpn_pilgrim":  {"kind":"weapon", "class":"priest", "name":"Pilgrim's Staff", "rarity":"rare", "r":"bits/staff_A", "l":"", "gold":1000, "source":"shop"},
	"priest_wpn_mace":     {"kind":"weapon", "class":"priest", "name":"Mace & Holy Shield", "rarity":"epic", "r":"bits/hammer_B", "l":"shield_badge", "gold":2000, "source":"shop"},
	"worker_wpn_felling":  {"kind":"weapon", "class":"worker", "name":"Felling Axe", "rarity":"rare", "r":"bits/axe_C", "l":"", "gold":900, "source":"shop"},
	"crus_wpn_maul":       {"kind":"weapon", "class":"crusader", "name":"Judgment Maul", "rarity":"legendary", "r":"bits/hammer_D", "l":"", "gold":3600, "source":"shop"},
	"bers_wpn_broad":      {"kind":"weapon", "class":"berserker", "name":"Broadblade", "rarity":"rare", "r":"bits/sword_D", "l":"", "gold":1200, "source":"shop"},
	"necro_wpn_spear":     {"kind":"weapon", "class":"necromancer", "name":"Bone Spear", "rarity":"epic", "r":"bits/spear_B", "l":"", "gold":2400, "source":"shop"},
	"assn_wpn_night":      {"kind":"weapon", "class":"assassin", "name":"Night Blades", "rarity":"epic", "r":"bits/dagger_C", "l":"bits/dagger_C", "gold":2400, "source":"shop"},
	"snip_wpn_repeater":   {"kind":"weapon", "class":"sniper", "name":"Repeater", "rarity":"rare", "r":"", "l":"crossbow_1handed", "gold":1200, "source":"shop"},
	"arch_wpn_elder":      {"kind":"weapon", "class":"archmage", "name":"Elder Oak & Tome", "rarity":"rare", "r":"bits/staff_A", "l":"spellbook_open", "gold":1200, "source":"shop"},
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
	"pack_crusader": {"name":"Knight Arsenal", "class":"knight", "rarity":"epic", "gems":330, "items":["knight_wpn_bastion", "knight_wpn_crest", "title_gatebreaker"]},
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
	return s

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
const DUPE_GOLD := {"common":100, "rare":250, "epic":600, "legendary":1500}       # a cosmetic already owned
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
	# -> {gold, gems, item ("" if none), dupe_gold, pity (the new count)}
	var c: Dictionary = CHESTS[kind]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := {"gold":rng.randi_range(int(c.gold[0]), int(c.gold[1])), "gems":0, "item":"", "dupe_gold":0, "pity":pity}
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
				out.dupe_gold = int(DUPE_GOLD.get(rar, 250))
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
	parts.append("duplicates turn into gold")
	return " · ".join(parts)
