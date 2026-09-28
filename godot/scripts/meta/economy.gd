extends RefCounted
# Fatebound Siege economy: currencies, levels, Siege Pass, challenges, shop rotation, cosmetics and
# match rewards. Pure data + pure functions (no I/O) so it is easy to test and tune; the player's
# state lives in scripts/meta/profile.gd.
#
# Everything sold is cosmetic. The forge still decides your class in battle.

const CLASSES := ["knight", "barbarian", "rogue", "ranger", "mage", "worker"]
const CLASS_NAMES := {"knight":"Knight", "barbarian":"Barbarian", "rogue":"Rogue", "ranger":"Ranger", "mage":"Mage", "worker":"Worker"}
const RARITY_COLOR := {"common":"#b8c4c9", "rare":"#5fb6ff", "epic":"#c47bff", "legendary":"#ffb13d"}

# ---------------- account level ----------------
static func level_xp(level: int) -> int:
	return 500 + 150 * (level - 1)

static func level_reward(level: int) -> Dictionary:
	# Reward for reaching `level`.
	var r := {"gold":100 + 10 * level}
	if level % 5 == 0:
		r["gems"] = 25
	return r

# ---------------- Siege Pass ----------------
const SEASON_EPOCH := 1790812800         # 2026-10-01 00:00 UTC; seasons before that are season 1
const SEASON_DAYS := 42
const PASS_TIERS := 30
const TIER_XP := 1000
const PREMIUM_COST := 950                # gems
const SEASON_NAMES := ["The Oracle's Keep", "Ashen Ramparts", "Frost Siege", "The Cake Wars", "Iron Tide", "Summer of Stones"]

static func season_id(unix: int) -> int:
	return 1 + maxi(0, int(floor(float(unix - SEASON_EPOCH) / (SEASON_DAYS * 86400.0))))

static func season_name(sid: int) -> String:
	return SEASON_NAMES[(sid - 1) % SEASON_NAMES.size()]

static func season_ends(sid: int) -> int:
	return SEASON_EPOCH + sid * SEASON_DAYS * 86400

static func pass_reward(sid: int, tier: int, premium: bool) -> Dictionary:
	# tier is 1..PASS_TIERS. Deterministic per season; cosmetic items rotate by season.
	var season_skins: Array = pass_items(sid)
	if not premium:
		if tier % 10 == 0:
			return {"item": season_skins[tier / 10 - 1]}                      # 3 free cosmetics
		if tier % 5 == 0:
			return {"gems": 30}
		return {"gold": 150 + 5 * tier}
	if tier % 6 == 0:
		return {"item": season_skins[3 + tier / 6 - 1]}                        # 5 premium cosmetics
	if tier % 3 == 0:
		return {"gems": 60}
	return {"gold": 300 + 10 * tier}

static func pass_items(sid: int) -> Array:
	# 3 free + 5 premium cosmetics for season `sid`, chosen from the "pass" pool.
	var pool: Array = []
	for id in CATALOG:
		if CATALOG[id].get("source", "") == "pass":
			pool.append(id)
	pool.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("pass-%d" % sid)
	var out := []
	var src := pool.duplicate()
	while out.size() < 8 and not src.is_empty():
		out.append(src.pop_at(rng.randi() % src.size()))
	while out.size() < 8:
		out.append(pool[out.size() % pool.size()])
	return out

# ---------------- cosmetics ----------------
# kind "skin": a tint over the class model. kind "weapon": right/left hand models for a class.
# kind "title": text shown on the profile. source "shop" (gold/gems), "pass", "level".
const CATALOG := {
	# --- Knight
	"knight_skin_royal":   {"kind":"skin", "class":"knight", "name":"Royal Guard", "rarity":"rare", "tint":"#9fc3ff", "gold":1200, "source":"shop"},
	"knight_skin_gilded":  {"kind":"skin", "class":"knight", "name":"Gilded Champion", "rarity":"legendary", "tint":"#ffd36b", "gems":400, "source":"shop"},
	"knight_skin_obsidian":{"kind":"skin", "class":"knight", "name":"Obsidian Oath", "rarity":"epic", "tint":"#6f6a8a", "source":"pass"},
	"knight_wpn_greatsword":{"kind":"weapon", "class":"knight", "name":"Greatsword", "rarity":"rare", "r":"sword_2handed", "l":"", "gold":900, "source":"shop"},
	"knight_wpn_crest":    {"kind":"weapon", "class":"knight", "name":"Sword & Crest", "rarity":"rare", "r":"sword_1handed", "l":"shield_badge_color", "gold":1100, "source":"shop"},
	"knight_wpn_tower":    {"kind":"weapon", "class":"knight", "name":"Sword & Tower Shield", "rarity":"epic", "r":"sword_1handed", "l":"shield_square_color", "gems":250, "source":"shop"},
	"knight_wpn_crimson":  {"kind":"weapon", "class":"knight", "name":"Crimson Greatsword", "rarity":"epic", "r":"sword_2handed_color", "l":"", "source":"pass"},
	# --- Barbarian
	"barb_skin_ember":     {"kind":"skin", "class":"barbarian", "name":"Ember Hide", "rarity":"rare", "tint":"#ffb08a", "gold":1200, "source":"shop"},
	"barb_skin_frost":     {"kind":"skin", "class":"barbarian", "name":"Frostborn", "rarity":"epic", "tint":"#a8e6ff", "source":"pass"},
	"barb_wpn_raider":     {"kind":"weapon", "class":"barbarian", "name":"Axe & Buckler", "rarity":"rare", "r":"axe_1handed", "l":"shield_round_barbarian", "gold":1000, "source":"shop"},
	"barb_wpn_spiked":     {"kind":"weapon", "class":"barbarian", "name":"Axe & Spiked Shield", "rarity":"epic", "r":"axe_1handed", "l":"shield_spikes_color", "gems":250, "source":"shop"},
	# --- Rogue
	"rogue_skin_night":    {"kind":"skin", "class":"rogue", "name":"Nightshade", "rarity":"rare", "tint":"#8e8fc8", "gold":1200, "source":"shop"},
	"rogue_skin_venom":    {"kind":"skin", "class":"rogue", "name":"Venom", "rarity":"epic", "tint":"#9df28a", "source":"pass"},
	"rogue_wpn_bomb":      {"kind":"weapon", "class":"rogue", "name":"Dagger & Smoke Bomb", "rarity":"rare", "r":"dagger", "l":"smokebomb", "gold":900, "source":"shop"},
	"rogue_wpn_bolt":      {"kind":"weapon", "class":"rogue", "name":"Hand Crossbow", "rarity":"epic", "r":"dagger", "l":"crossbow_1handed", "gems":250, "source":"shop"},
	# --- Ranger
	"ranger_skin_forest":  {"kind":"skin", "class":"ranger", "name":"Deepwood", "rarity":"rare", "tint":"#9fd98a", "gold":1200, "source":"shop"},
	"ranger_skin_dusk":    {"kind":"skin", "class":"ranger", "name":"Duskstalker", "rarity":"legendary", "tint":"#d69cff", "gems":400, "source":"shop"},
	"ranger_wpn_crossbow": {"kind":"weapon", "class":"ranger", "name":"Heavy Crossbow", "rarity":"epic", "r":"", "l":"crossbow_2handed", "source":"pass"},
	"ranger_wpn_quiver":   {"kind":"weapon", "class":"ranger", "name":"Bow & Quiver", "rarity":"rare", "r":"quiver", "l":"bow_withString", "gold":900, "source":"shop"},
	# --- Mage
	"mage_skin_arcane":    {"kind":"skin", "class":"mage", "name":"Arcanist", "rarity":"rare", "tint":"#9fb4ff", "gold":1200, "source":"shop"},
	"mage_skin_solar":     {"kind":"skin", "class":"mage", "name":"Solar Magus", "rarity":"legendary", "tint":"#ffd89a", "gems":400, "source":"shop"},
	"mage_wpn_tome":       {"kind":"weapon", "class":"mage", "name":"Wand & Tome", "rarity":"rare", "r":"wand", "l":"spellbook_open", "gold":1000, "source":"shop"},
	"mage_wpn_wand":       {"kind":"weapon", "class":"mage", "name":"Wand", "rarity":"common", "r":"wand", "l":"", "gold":500, "source":"shop"},
	# --- Worker
	"worker_skin_miner":   {"kind":"skin", "class":"worker", "name":"Quarry Crew", "rarity":"common", "tint":"#d8c39a", "gold":600, "source":"shop"},
	"worker_wpn_mug":      {"kind":"weapon", "class":"worker", "name":"Axe & Ale", "rarity":"rare", "r":"axe_1handed", "l":"mug_full", "source":"pass"},
	# --- Titles
	"title_gatebreaker":   {"kind":"title", "class":"", "name":"Gatebreaker", "rarity":"rare", "gold":800, "source":"shop"},
	"title_cake_baron":    {"kind":"title", "class":"", "name":"Cake Baron", "rarity":"epic", "source":"pass"},
	"title_oracle_sworn":  {"kind":"title", "class":"", "name":"Oracle-Sworn", "rarity":"legendary", "gems":300, "source":"shop"},
	"title_siege_lord":    {"kind":"title", "class":"", "name":"Siege Lord", "rarity":"epic", "source":"pass"},
}

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
const DAILY_SLOTS := 4
const FEATURED_SLOTS := 2
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
	"rescue1":  {"text":"Rescue your Oracle", "stat":"rescues", "goal":1, "pass":600, "gold":120, "span":"daily"},
	"kos15":    {"text":"Knock out 15 enemies", "stat":"kills", "goal":15, "pass":400, "gold":80, "span":"daily"},
	"gate5":    {"text":"Deal 500 gate damage", "stat":"gates", "goal":5, "pass":450, "gold":90, "span":"daily"},
	"gather40": {"text":"Gather 40 wood or stone", "stat":"gathered", "goal":40, "pass":400, "gold":80, "span":"daily"},
	"feed3":    {"text":"Feed 3 cakes to their Oracle", "stat":"fed", "goal":3, "pass":450, "gold":90, "span":"daily"},
	"lift2":    {"text":"Help lift your Oracle twice", "stat":"lifts", "goal":2, "pass":400, "gold":80, "span":"daily"},
	"w_win5":   {"text":"Win 5 matches", "stat":"wins", "goal":5, "pass":2000, "gems":40, "span":"weekly"},
	"w_rescue4":{"text":"Rescue your Oracle 4 times", "stat":"rescues", "goal":4, "pass":2000, "gems":40, "span":"weekly"},
	"w_kos100": {"text":"Knock out 100 enemies", "stat":"kills", "goal":100, "pass":1800, "gems":30, "span":"weekly"},
	"w_gate30": {"text":"Deal 3,000 gate damage", "stat":"gates", "goal":30, "pass":1800, "gems":30, "span":"weekly"},
	"w_feed12": {"text":"Feed 12 cakes", "stat":"fed", "goal":12, "pass":1800, "gems":30, "span":"weekly"},
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

static func match_stats(me: Dictionary, won: bool, draw: bool) -> Dictionary:
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
		lines.append({"label":"Oracle rescues x%d" % r, "gold":50 * r, "xp":40 * r, "pass":60 * r})
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
		lines.append({"label":"Cakes fed x%d" % f, "gold":10 * f, "xp":10 * f, "pass":15 * f})
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
