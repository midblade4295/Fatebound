extends RefCounted
# The player's Siege profile: currencies, level, Siege Pass, challenges, owned/equipped cosmetics,
# stats. Saved to user://siege_profile.json (atomic write). On first run it migrates once from the
# dice-era save (user://fatebound-save.json), which is left untouched on disk.
const Eco = preload("res://scripts/meta/economy.gd")
const Net = preload("res://scripts/siege/siege_net.gd")

const SCHEMA := 1
var path := "user://siege_profile.json"
var legacy_path := "user://fatebound-save.json"
var d: Dictionary = {}
var now_override := -1          # tests: fixed clock (unix seconds)
var last_error := ""
var saves := 0                  # 0.31.102: saves this run (play_games.gd: did it change while an upload was out?)

# ---------------- 0.31.108: the server owns the economy (Kevin: "make sure everything is verified by server so players
# can't edit gems ect") ----------------
# The Siege server keeps every player's profile (server/eco_accounts.gd) and is the only one whose copy counts. Every
# change a player makes is an "op" -- the method's name and its arguments -- that the server replays with this same
# code on its own copy (apply_op), with its own clock; what it answers replaces the phone's copy (the app's
# eco_sync.gd), the phone's unsent ops re-applied on top. So the phone shows a change at once, and an edited save file
# changes nothing: the next answer from the server puts it back. What only the server may do (grant a purchase, take a
# match's result) is not an op the phone can send.
var on_op: Callable             # the app's EcoSync: (op, args) after each change made here
var replaying := false          # applying ops (on the server, or the phone re-applying its unsent ones): not recorded
var server_side := false        # the server's own copy
var server_mode := false        # the phone, with the server's economy on: things only a local save allowed are off
var clock_offset := 0           # the phone: server time - phone time (so a chest's timer agrees with the server's)
var ready_grace := 0            # the server: a chest counts as unlocked this many seconds early (clocks differ a little)
const OPS := {
	# op -> argument types (JSON numbers arrive as floats; ints are converted)
	"claim_tier": [TYPE_INT, TYPE_BOOL], "claim_all": [], "skip_tiers": [], "buy_premium": [],
	"buy": [TYPE_STRING], "buy_pack": [TYPE_STRING], "exchange": [TYPE_STRING],
	"equip": [TYPE_STRING], "unequip": [TYPE_STRING, TYPE_STRING],
	"reroll_daily": [TYPE_INT], "claim_challenge": [TYPE_STRING, TYPE_INT],
	"claim_quest": [TYPE_STRING], "forge": [TYPE_STRING, TYPE_STRING], "set_forge_element": [TYPE_STRING, TYPE_STRING],
	"start_unlock": [TYPE_INT], "skip_chest": [TYPE_INT], "open_chest": [TYPE_INT],
	"set_name": [TYPE_STRING], "finish_tutorial": [],
	"claim_login": [],                                           # 0.31.119: the daily login reward
	"claim_discord": [],                                         # 0.31.124: JOIN OUR DISCORD, once
	"buy_hero": [TYPE_STRING],                                   # 0.31.168: a 5v5 hero for gold
}

func _rec(op: String, args: Array) -> void:
	if not replaying and on_op.is_valid():
		on_op.call(op, args)

func apply_op(op: String, args: Variant) -> Dictionary:
	# Replay one op (the server's copy, or the phone's unsent ones over the server's answer). Chest ops carry the
	# chest's id, not its slot. -> the method's own result ({"ok": false, "error"} for an unknown or malformed op).
	if not OPS.has(op) or not (args is Array):
		return {"ok":false, "error":"unknown op"}
	var types: Array = OPS[op]
	var a: Array = args
	if a.size() != types.size():
		return {"ok":false, "error":"bad args"}
	var v := []
	for i in types.size():
		var x: Variant = a[i]
		match int(types[i]):
			TYPE_INT:
				if not (x is int or x is float) or not is_finite(float(x)):
					return {"ok":false, "error":"bad args"}
				v.append(int(x))
			TYPE_BOOL:
				if not (x is bool):
					return {"ok":false, "error":"bad args"}
				v.append(x)
			_:
				if not (x is String) or (x as String).length() > 64:
					return {"ok":false, "error":"bad args"}
				v.append(x)
	var was := replaying
	replaying = true
	var out: Variant = null
	match op:
		"start_unlock", "skip_chest", "open_chest":
			var ix := chest_index(int(v[0]))
			if ix < 0:
				out = {"ok":false, "error":"no such chest"}
			elif op == "start_unlock":
				out = {"ok":start_unlock(ix)}
			elif op == "skip_chest":
				out = skip_chest(ix)
			else:
				out = open_chest(ix)
		"claim_all":
			out = {"ok":true, "got":claim_all()}
		"reroll_daily":
			out = {"ok":reroll_daily(int(v[0]))}
		"unequip":
			unequip(str(v[0]), str(v[1]))
			out = {"ok":true}
		"set_forge_element":
			out = {"ok":set_forge_element(str(v[0]), str(v[1]))}
		_:
			out = callv(op, v)
	replaying = was
	return out if out is Dictionary else {"ok":bool(out)}

func chest_index(id: int) -> int:
	for i in (d.chests.slots as Array).size():
		if int(d.chests.slots[i].id) == id:
			return i
	return -1

signal changed

func _init(save_path := "user://siege_profile.json", legacy := "user://fatebound-save.json") -> void:
	path = save_path
	legacy_path = legacy

func now() -> int:
	return now_override if now_override >= 0 else int(Time.get_unix_time_from_system()) + clock_offset

static func defaults() -> Dictionary:
	var equip := {}
	for c in Eco.CLASSES + Eco.UP_CLASSES:
		equip[c] = {"skin":"", "weapon":""}
	return {"schema":SCHEMA, "name":"Player", "gold":0, "gems":0, "level":1, "xp":0,
		"pass":{"season":0, "xp":0, "premium":false, "free":[], "prem":[], "swaps":{}},
		"owned":[], "equip":equip, "title":"",
		"heroes":[],                                                 # 0.31.168: the 5v5 heroes bought with gold (Eco.HERO_PRICES)
		"challenges":{"day":"", "daily":[], "week":"", "weekly":[], "rerolled":false},
		"stats":{"matches":0, "wins":0, "rescues":0, "kills":0, "gates":0, "gathered":0, "fed":0,
			"lifts":0, "repaired":0, "healed":0, "best_multi":0, "streak":0, "best_streak":0},     # (0.31.87: for the titles)
		"tutorial_done":false,
		"first_win_day":"", "history":[], "migration":{},
		"login":{"day":"", "n":0},                                   # 0.31.119: the last day claimed, claims so far
		"discord":false,                                             # 0.31.124: the Discord reward claimed
		"prizes":[],                                                 # 0.31.120: weekly leaderboard prizes paid (newest first)
		"war_rewards":[],                                            # 0.31.151: the war's rewards paid (0.31.169: no more -- Crown War is gone; kept in saves)
		"paid":[],                                                   # 0.31.134: gold the server took (a clan), newest first
		"referral":{"by":"", "notes":[]},                            # 0.31.120: whose code was entered; friend rewards (newest first)
		"forge":{"stars":{}, "wins":{}, "element":{}},              # 0.31.93: per weapon (Eco.forge_id): stars 0-3, wins, aura element
		"iap":{"done":[], "starter":false},                          # 0.31.90: purchase tokens already granted
		"chests":{"slots":[], "next":1, "pity":0, "queue":[], "salt":0},   # 0.31.108: queue (reward chests waiting), salt (the rolls' seed)
		"quests":{},                                                  # 0.31.97: class -> quest steps claimed (0-3)
		"cloud":{"stamp":"", "dirty":false, "at":0},                  # 0.31.102: the Google Play save this is in step with
		"account":{"id":"", "key":""},                                # 0.31.108: the phone's key to its account on the server
		"settings":{"master":1.0, "music":1.0, "sfx":1.0, "reduce_motion":false, "audio_max":true}}      # (0.31.110: 100% by default)

# ---------------- load / save ----------------
func load_or_create() -> void:
	if FileAccess.file_exists(path):
		var txt := FileAccess.get_file_as_string(path)
		var v: Variant = JSON.parse_string(txt)
		if v is Dictionary:
			d = _normalized(v)
			refresh()
			# 0.31.87: titles earned from the stats the profile already had (a veteran's first start with titles)
			var got := check_titles()
			if not got.is_empty():
				d["title_note"] = got
				save()
			return
		last_error = "Profile was unreadable; kept a copy as .corrupt and started fresh"
		DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".corrupt"))
	d = defaults()
	_migrate_legacy()
	refresh()
	save()

func _normalized(v: Dictionary) -> Dictionary:
	var out := v.duplicate(true)
	_merge_missing(out, defaults())
	for k in ["gold", "gems", "xp"]:
		out[k] = maxi(0, int(out[k]))
	out.level = maxi(1, int(out.level))
	var owned := []
	for id in out.owned:
		if Eco.CATALOG.has(str(id)) and not owned.has(str(id)):
			owned.append(str(id))
	out.owned = owned
	# 0.31.39: skins were removed -- give back what any bought ones cost, once
	if not bool(out.get("skins_refunded", false)):
		var back := {"gold":0, "gems":0}
		for sid in v.get("owned", []):
			if Eco.REMOVED_SKIN_REFUND.has(str(sid)):
				var pr: Dictionary = Eco.REMOVED_SKIN_REFUND[str(sid)]
				back.gold += int(pr.get("gold", 0))
				back.gems += int(pr.get("gems", 0))
		out.gold = int(out.gold) + back.gold
		out.gems = int(out.gems) + back.gems
		out["skins_refunded"] = true
		if back.gold + back.gems > 0:
			out["refund_note"] = back
	for c in Eco.CLASSES + Eco.UP_CLASSES:
		if not out.equip.has(c):
			out.equip[c] = {"skin":"", "weapon":""}
		for slot in ["skin", "weapon"]:
			var id := str(out.equip[c].get(slot, ""))
			if id != "" and not owned.has(id):
				out.equip[c][slot] = ""
	if out.title != "" and not owned.has(str(out.title)):
		out.title = ""
	# JSON numbers come back as floats: make tier lists and challenge progress ints again.
	for track in ["free", "prem"]:
		var tiers := []
		for t in out.pass[track]:
			if _is_num(t) and not tiers.has(int(t)):
				tiers.append(int(t))
		out.pass[track] = tiers
	out.pass.season = int(out.pass.season)
	out.pass.xp = maxi(0, int(out.pass.xp))
	for span in ["daily", "weekly"]:
		for c in out.challenges[span]:
			c.progress = int(c.get("progress", 0))
	# 0.31.184 (Kevin: "Maybe let's have the two currency so it's more simple"): Embers (0.31.90-0.31.183, the Forge's
	# material) are gold now, Eco.EMBER_GOLD each -- a save from before is turned once (the key goes with it)
	if out.has("embers"):
		out.gold = int(out.gold) + maxi(0, int(out.embers if _is_num(out.embers) else 0)) * Eco.EMBER_GOLD
		out.erase("embers")
	# 0.31.93: the Forge -- ints again, nothing out of range
	for part in ["stars", "wins", "element"]:
		if not (out.forge.get(part) is Dictionary):
			out.forge[part] = {}
	for wid in out.forge.stars.keys():
		out.forge.stars[wid] = clampi(int(out.forge.stars[wid]), 0, Eco.FORGE_STARS.size())
	for wid in out.forge.wins.keys():
		out.forge.wins[wid] = maxi(0, int(out.forge.wins[wid]))
	# 0.31.110 (Kevin: "make it so the audio sliders are max by default"): once, each slider still on its old default
	# (master 80%, effects 80%, music 60%) goes to 100%; one someone moved stays where they put it
	# (asked of the saved settings: the defaults merged in above carry the mark)
	var st: Dictionary = out.settings
	var saved_st: Variant = v.get("settings")
	if not (saved_st is Dictionary and bool(saved_st.get("audio_max", false))):
		for k in ["master", "sfx", "music"]:
			if is_equal_approx(float(st.get(k, 1.0)), 0.6 if k == "music" else 0.8):
				st[k] = 1.0
		st["audio_max"] = true
	# 0.31.97: quest steps claimed -- known classes, 0..3
	var qs := {}
	for c in out.quests.keys():
		if Eco.QUESTS.has(str(c)):
			qs[str(c)] = clampi(int(out.quests[c]), 0, Eco.QUESTS[str(c)].steps.size())
	out.quests = qs
	return out

static func _is_num(v: Variant) -> bool:
	return v is int or v is float

static func _merge_missing(target: Dictionary, base: Dictionary) -> void:
	# JSON loads every number as a float, so int/float count as the same type here (treating
	# them as different reset every saved number to its default on load).
	for k in base:
		var bv: Variant = base[k]
		var same_type: bool = target.has(k) and (typeof(target[k]) == typeof(bv) or (_is_num(target[k]) and _is_num(bv)))
		if not same_type:
			target[k] = bv.duplicate(true) if (bv is Dictionary or bv is Array) else bv
		elif bv is Dictionary:
			_merge_missing(target[k], bv)

func save(changed_here := true) -> bool:
	# Write to a temp file then rename, so a crash mid-write can't corrupt the profile.
	# 0.31.102: every save but the cloud sync's own marks the profile as changed since the Google Play copy
	# (play_games.gd uploads it); kept in the file, so a change made just before the app is killed still goes up.
	if changed_here:
		d.cloud.dirty = true
		saves += 1
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "Could not write profile (%s)" % error_string(FileAccess.get_open_error())
		return false
	f.store_string(JSON.stringify(d))
	f.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	if err != OK:
		last_error = "Could not replace profile (%s)" % error_string(err)
		return false
	changed.emit()
	return true

# ---------------- the Google Play copy (0.31.102, scripts/meta/play_games.gd) ----------------
const CLOUD_VERSION := 1

func summary() -> Dictionary:
	# what the "which progress to keep?" choice shows of each side
	return {"level":int(d.level), "wins":int(d.stats.wins), "matches":int(d.stats.matches), "gold":int(d.gold),
		"gems":int(d.gems), "items":(d.owned as Array).size(), "name":str(d.name)}

func is_fresh() -> bool:
	# a new install: nothing played, bought or earned -- Google Play's copy simply replaces it
	return int(d.stats.matches) == 0 and (d.owned as Array).is_empty() and (d.iap.done as Array).is_empty() \
		and int(d.level) <= 1 and int(d.xp) == 0 and int(d.pass.xp) == 0

func cloud_payload(stamp: String, device := "") -> Dictionary:
	var prof := d.duplicate(true)
	prof.erase("cloud")
	return {"v":CLOUD_VERSION, "stamp":stamp, "at":now(), "device":device, "sum":summary(), "profile":prof}

func restore_cloud(prof: Variant, stamp: String) -> bool:
	# Google Play's copy replaces this phone's progress; this phone's sound and graphics settings stay
	if not (prof is Dictionary) or not (prof as Dictionary).has("stats"):
		return false
	var keep: Dictionary = d.settings.duplicate(true)
	d = _normalized(prof)
	d.settings = keep
	d.cloud = {"stamp":stamp, "dirty":false, "at":now()}
	refresh()
	return save(false)

func _migrate_legacy() -> void:
	if not FileAccess.file_exists(legacy_path):
		d.migration = {"from":"none"}
		return
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(legacy_path))
	if not (v is Dictionary):
		d.migration = {"from":"unreadable"}
		return
	import_legacy(v)

func import_legacy(old: Dictionary) -> Dictionary:
	# One-time conversion of a dice-era save (at first launch; 0.31.123: Settings no longer has a paste-in import).
	if not d.migration.is_empty() and str(d.migration.get("from", "")) == "legacy":
		return {"ok":false, "error":"Old progress was already imported"}
	if server_mode or server_side:
		return {"ok":false, "error":"Old progress can't be imported any more"}     # (0.31.108: unverifiable)
	var conv := Eco.legacy_conversion(old)
	d.gold += int(conv.gold)
	d.gems += int(conv.gems)
	d.level = maxi(int(d.level), int(conv.level))
	d.migration = {"from":"legacy", "at":now(), "gold":conv.gold, "gems":conv.gems, "level":conv.level,
		"weapons":conv.weapons, "chests":conv.chests}
	return {"ok":true, "summary":conv}

# ---------------- time-based state ----------------
func refresh() -> void:
	# New season -> reset pass progress; new day/week -> new challenges.
	var t := now()
	var sid := Eco.season_id(t)
	if int(d.pass.season) != sid:
		d.pass = {"season":sid, "xp":0, "premium":false, "free":[], "prem":[], "swaps":{}}
	var day := Eco.day_key(t)
	var week := Eco.week_key(t)
	var ch: Dictionary = d.challenges
	if ch.day != day:
		ch.day = day
		ch.daily = Eco.roll_challenges("daily", day, Eco.DAILY_COUNT)
		ch.rerolled = false
	if ch.week != week:
		ch.week = week
		ch.weekly = Eco.roll_challenges("weekly", week, Eco.WEEKLY_COUNT)
	_retire_challenges(ch.daily, "daily", str(ch.day))
	_retire_challenges(ch.weekly, "weekly", str(ch.week))

func _retire_challenges(list: Array, span: String, key: String) -> void:
	# 0.31.164 (Kevin: "5v5 only"): a saved Siege challenge (King rescues, fish, gathering, King lifts) is swapped in place
	# for a 5v5 one -- the same slot (the server replays claims by index) and the same claimed state; the same rolls on
	# the phone and the server
	var keep := []
	for c in list:
		if c is Dictionary and Eco.CHALLENGES.has(str(c.get("id", ""))):
			keep.append(str(c.id))
	if keep.size() == list.size():
		return
	var fresh := Eco.roll_challenges(span, key + "-5v5", list.size() - keep.size(), keep)
	var fi := 0
	for i in list.size():
		var c: Variant = list[i]
		if c is Dictionary and Eco.CHALLENGES.has(str(c.get("id", ""))):
			continue
		if fi >= fresh.size():
			break
		var nc: Dictionary = fresh[fi]
		fi += 1
		if c is Dictionary and bool(c.get("claimed", false)):
			nc.claimed = true
			nc.progress = int(Eco.CHALLENGES[nc.id].goal)
		list[i] = nc
	for i in range(list.size() - 1, -1, -1):
		if not (list[i] is Dictionary) or not Eco.CHALLENGES.has(str(list[i].get("id", ""))):
			list.remove_at(i)                          # (nothing left to swap in: dropped)

# ---------------- level / pass ----------------
func pass_tier() -> int:
	return mini(Eco.PASS_TIERS, int(d.pass.xp) / Eco.TIER_XP)

func _add_xp(amount: int, out: Dictionary) -> void:
	d.xp += amount
	while d.xp >= Eco.level_xp(int(d.level)):
		d.xp -= Eco.level_xp(int(d.level))
		d.level += 1
		var r := Eco.level_reward(int(d.level))
		d.gold += int(r.get("gold", 0))
		d.gems += int(r.get("gems", 0))
		if r.has("chest"):
			add_chest(str(r.chest), out, true)
		out.levels.append({"level":d.level, "reward":r})

func _add_pass_xp(amount: int, out: Dictionary) -> void:
	var before := pass_tier()
	d.pass.xp = mini(int(d.pass.xp) + amount, Eco.PASS_TIERS * Eco.TIER_XP)
	for tier in range(before + 1, pass_tier() + 1):
		out.tiers.append(tier)

func can_claim(tier: int, premium: bool) -> bool:
	if tier < 1 or tier > pass_tier():
		return false
	if premium and not bool(d.pass.premium):
		return false
	return not (d.pass.prem if premium else d.pass.free).has(tier)

func pass_reward_for(tier: int, premium: bool) -> Dictionary:
	# 0.31.108: what this tier gives this player -- the season's reward, or, for an item already owned, its swap (a
	# claimed tier: what it gave)
	var key := ("p%d" if premium else "f%d") % tier
	var sw: Dictionary = d.pass.get("swaps", {})
	if sw.has(key) and (d.pass.prem if premium else d.pass.free).has(tier):
		return sw[key]
	var r := Eco.pass_reward(int(d.pass.season), tier, premium)
	var id := str(r.get("item", ""))
	if id != "" and owns(id):
		return Eco.pass_swap(int(d.pass.season), tier, premium, id, d.owned)
	return r

func _claim(tier: int, premium: bool) -> Dictionary:
	var r := pass_reward_for(tier, premium)
	if r.has("swap"):
		if not d.pass.has("swaps"):
			d.pass["swaps"] = {}
		d.pass.swaps[("p%d" if premium else "f%d") % tier] = r
	_grant(r)
	(d.pass.prem if premium else d.pass.free).append(tier)
	return r

func claim_tier(tier: int, premium: bool) -> Dictionary:
	if not can_claim(tier, premium):
		return {"ok":false}
	var r := _claim(tier, premium)
	save()
	_rec("claim_tier", [tier, premium])
	return {"ok":true, "reward":r}

func claim_all() -> Array:
	var got := []
	for tier in range(1, pass_tier() + 1):
		for prem in [false, true]:
			if can_claim(tier, prem):
				got.append(_claim(tier, prem))
	if not got.is_empty():
		save()
		_rec("claim_all", [])
	return got

func skip_offer() -> Dictionary:
	# the pass's tier skip as it stands: {tiers, gems} (tiers 0 when the pass is complete)
	var n := mini(Eco.TIER_SKIP, Eco.PASS_TIERS - pass_tier())
	return {"tiers": maxi(n, 0), "gems": maxi(n, 0) * Eco.TIER_SKIP_GEMS}

func skip_tiers() -> Dictionary:
	# 0.31.107: buy the next (up to) 10 tiers -- the pass XP for them, the progress into the current tier kept; their
	# rewards wait to be claimed like any others
	var o := skip_offer()
	if int(o.tiers) <= 0:
		return {"ok":false, "error":"The pass is already complete"}
	if int(d.gems) < int(o.gems):
		return {"ok":false, "error":"Not enough gems"}
	d.gems -= int(o.gems)
	var out := {"tiers": []}
	_add_pass_xp(int(o.tiers) * Eco.TIER_XP, out)
	d.pass["skipped"] = int(d.pass.get("skipped", 0)) + int(o.tiers)
	save()
	_rec("skip_tiers", [])
	return {"ok":true, "tiers":out.tiers, "gems":int(o.gems)}

func buy_premium() -> Dictionary:
	if bool(d.pass.premium):
		return {"ok":false, "error":"You already own this season's premium pass"}
	if int(d.gems) < Eco.PREMIUM_COST:
		return {"ok":false, "error":"Not enough gems"}
	d.gems -= Eco.PREMIUM_COST
	d.pass.premium = true
	save()
	_rec("buy_premium", [])
	return {"ok":true}

func _grant(r: Dictionary) -> void:
	d.gold += int(r.get("gold", 0))
	d.gems += int(r.get("gems", 0))
	if r.has("chest"):
		add_chest(str(r.chest), {}, true)
	var id := str(r.get("item", ""))
	if id != "" and not d.owned.has(id):
		d.owned.append(id)

# ---------------- shop / locker ----------------
func owns(id: String) -> bool:
	return d.owned.has(id)

func can_afford(price: Dictionary) -> bool:
	return int(d.gold) >= int(price.get("gold", 0)) and int(d.gems) >= int(price.get("gems", 0))

func buy(id: String) -> Dictionary:
	var price := Eco.item_price(id, now())
	if price.is_empty():
		return {"ok":false, "error":"Not for sale"}
	if owns(id):
		return {"ok":false, "error":"Already owned"}
	if not (Eco.shop_daily(now()).has(id) or Eco.shop_featured(now()).has(id)):
		return {"ok":false, "error":"Not in today's shop"}
	if not can_afford(price):
		return {"ok":false, "error":"Not enough " + ("gems" if price.has("gems") else "gold")}
	d.gold -= int(price.get("gold", 0))
	d.gems -= int(price.get("gems", 0))
	d.owned.append(id)
	save()
	_rec("buy", [id])
	return {"ok":true}

# 0.31.168 (Kevin: "Unlock with gold"): the 5v5's six new heroes are bought with gold, once; the rest are everyone's
func owns_hero(hid: String) -> bool:
	return not Eco.HERO_PRICES.has(hid) or (d.get("heroes", []) as Array).has(hid)

func buy_hero(hid: String) -> Dictionary:
	if not Eco.HERO_PRICES.has(hid):
		return {"ok":false, "error":"Not for sale"}
	if owns_hero(hid):
		return {"ok":false, "error":"Already yours"}
	var price := {"gold":int(Eco.HERO_PRICES[hid])}
	if not can_afford(price):
		return {"ok":false, "error":"Not enough gold"}
	d.gold -= int(price.gold)
	if not d.has("heroes"):
		d["heroes"] = []
	(d.heroes as Array).append(hid)
	save()
	_rec("buy_hero", [hid])
	return {"ok":true}

func buy_pack(pack_id: String) -> Dictionary:
	var pk: Dictionary = Eco.PACKS.get(pack_id, {})
	if pk.is_empty():
		return {"ok":false, "error":"Not for sale"}
	var gems := Eco.pack_price(pack_id, d.owned)
	if gems <= 0:
		return {"ok":false, "error":"You already own everything in it"}
	if not can_afford({"gems": gems}):
		return {"ok":false, "error":"Not enough gems"}
	d.gems -= gems
	for id in pk.items:
		if not d.owned.has(id):
			d.owned.append(id)
	save()
	_rec("buy_pack", [pack_id])
	return {"ok":true, "gems":gems}

# ---------------- in-app purchases (0.31.90) ----------------
func iap_granted(token: String) -> bool:
	for e in d.iap.done:
		if str((e as Dictionary).get("t", "")) == token:
			return true
	return false

func grant_iap(product: String, token: String) -> Dictionary:
	# A purchase Google and the server have confirmed: add what it holds. Idempotent per token (a retry after a crash,
	# or the same purchase seen again on the next start, grants nothing twice). -> {ok, gems, gold, item, again}
	var pk: Dictionary = Net.IAP.get(product, {})
	if pk.is_empty() or token == "":
		return {"ok":false, "error":"Unknown purchase"}
	if server_mode:
		return {"ok":false, "error":"The server grants purchases"}       # (0.31.108: eco_accounts.gd does)
	if iap_granted(token):
		return {"ok":true, "again":true, "gems":0, "gold":0, "item":""}
	var out := {"ok":true, "again":false, "gems":int(pk.get("gems", 0)), "gold":int(pk.get("gold", 0)), "item":""}
	d.gems = int(d.gems) + int(out.gems)
	d.gold = int(d.gold) + int(out.gold)
	if str(pk.get("weapon", "")) != "":
		# a weapon of that rarity the player doesn't own yet (shop pool), picked from the token so a retry picks the same
		var pool: Array = []
		for id in Eco.chest_pool(str(pk.weapon), Eco.season_id(now())):
			if not owns(id):
				pool.append(id)
		if not pool.is_empty():
			out.item = str(pool[absi(hash(token)) % pool.size()])
			d.owned.append(out.item)
		else:
			out.gems = int(out.gems) + int(Eco.DUPE_GOLD.get(str(pk.weapon), 250)) / 10     # owns them all: gems instead
			d.gems = int(d.gems) + int(Eco.DUPE_GOLD.get(str(pk.weapon), 250)) / 10
	if bool(pk.get("once", false)):
		d.iap.starter = true
	d.iap.done.append({"t":token, "p":product, "at":now()})
	while d.iap.done.size() > 300:
		d.iap.done.pop_front()
	save()
	return out

func exchange(offer_id: String) -> Dictionary:
	for off in Eco.EXCHANGE:
		if off.id == offer_id:
			if int(d.gems) < int(off.gems):
				return {"ok":false, "error":"Not enough gems"}
			d.gems -= int(off.gems)
			d.gold += int(off.gold)
			save()
			_rec("exchange", [offer_id])
			return {"ok":true}
	return {"ok":false, "error":"Unknown offer"}

func equip(id: String) -> Dictionary:
	# Equip an owned cosmetic (id "" not allowed; use unequip).
	var it := Eco.item(id)
	if it.is_empty() or not owns(id):
		return {"ok":false}
	if it.kind == "title":
		d.title = id
	else:
		d.equip[it["class"]][it.kind] = id
	save()
	_rec("equip", [id])
	return {"ok":true}

func unequip(cls: String, slot: String) -> void:
	if slot == "title":
		d.title = ""
	elif d.equip.has(cls) and slot in ["skin", "weapon"]:
		d.equip[cls][slot] = ""
	else:
		return
	save()
	_rec("unequip", [cls, slot])

func look_for(cls: String) -> Dictionary:
	# What the battle view should show for this class: {"r": model, "l": model, "forge": its stars} (0.31.39: weapons
	# only -- no skins; 0.31.93: the Forge's stars). 0.31.101: built by Eco.look_of, as the other players' looks are.
	if not d.equip.has(cls):
		return {}
	var w := str(d.equip[cls].weapon)
	var wid := Eco.forge_id(cls, w)
	return Eco.look_of(cls, w, forge_stars(wid), forge_element(wid))

func wire_looks() -> Dictionary:
	# 0.31.101: what I wear, for my hello ("lk"), so the other players see it: {class: "weapon id|stars|element"} for
	# each class with a weapon equipped or forged (the rest wear their starters anyway)
	var out := {}
	for cls in Eco.CLASSES + Eco.UP_CLASSES:
		if not d.equip.has(cls):
			continue
		var w := str(d.equip[cls].weapon)
		var wid := Eco.forge_id(cls, w)
		var n := forge_stars(wid)
		if w != "" or n > 0:
			out[cls] = "%s|%d|%s" % [w, n, forge_element(wid) if n >= Eco.FORGE_STARS.size() else ""]
	return out

# ---------------- challenges ----------------
func reroll_daily(index: int) -> bool:
	var ch: Dictionary = d.challenges
	if bool(ch.rerolled) or index < 0 or index >= ch.daily.size() or bool(ch.daily[index].claimed):
		return false
	var used := []
	for c in ch.daily:
		used.append(c.id)
	var fresh := Eco.roll_challenges("daily", str(ch.day) + "-reroll", 1, used)
	if fresh.is_empty():
		return false
	ch.daily[index] = fresh[0]
	ch.rerolled = true
	save()
	_rec("reroll_daily", [index])
	return true

func claim_challenge(span: String, index: int) -> Dictionary:
	if not span in ["daily", "weekly"]:
		return {"ok":false}
	var list: Array = d.challenges.daily if span == "daily" else d.challenges.weekly
	if index < 0 or index >= list.size():
		return {"ok":false}
	var c: Dictionary = list[index]
	var def: Dictionary = Eco.CHALLENGES[c.id]
	if bool(c.claimed) or int(c.progress) < int(def.goal):
		return {"ok":false}
	c.claimed = true
	var out := {"levels":[], "tiers":[], "chests":[]}
	_add_pass_xp(int(def.get("pass", 0)), out)
	d.gold += int(def.get("gold", 0))
	d.gems += int(def.get("gems", 0))
	var bonus := Eco.DAILY_GOLD if span == "daily" else 0      # 0.31.184 (0.31.93-0.31.183: Embers)
	d.gold += bonus
	# 0.31.37: the whole day's challenges done -> a Silver chest; the whole week's -> a Gold chest
	if list.all(func(x): return bool(x.claimed)):
		add_chest("silver" if span == "daily" else "gold", out, true)
	save()
	_rec("claim_challenge", [span, index])
	return {"ok":true, "tiers":out.tiers, "chests":out.chests, "gold":int(def.get("gold", 0)) + bonus}

# ---------------- weekly leaderboard prizes (0.31.120) ----------------
func grant_prize(week: String, rank: int, prize: Dictionary) -> Dictionary:
	# the server only (server/eco_accounts.gd, when a week ends): never an op a phone can send
	for x in d.prizes:
		if str(x.get("week", "")) == week:
			return {"ok":false, "error":"paid"}
	var out := {"chests":[]}
	d.gems = int(d.gems) + int(prize.get("gems", 0))
	if str(prize.get("chest", "")) != "":
		add_chest(str(prize.chest), out, true)
	var t := str(prize.get("title", ""))
	if t != "" and not (d.owned as Array).has(t):
		d.owned.append(t)
	d.prizes.push_front({"week":week, "rank":rank, "gems":int(prize.get("gems", 0)), "chest":str(prize.get("chest", "")), "title":t})
	if (d.prizes as Array).size() > 12:
		d.prizes.resize(12)
	save()
	return {"ok":true, "chests":out.chests}

# ---------------- gold the server takes (0.31.134) ----------------
func pay_gold(amount: int, why: String) -> Dictionary:
	# the server only (server/clans.gd: starting a clan): gold taken from the account, never below zero; the phone sees
	# it with its next answer from the server (eco_sync pull)
	if amount <= 0 or int(d.gold) < amount:
		return {"ok":false, "error":"gold"}
	d.gold = int(d.gold) - amount
	if not (d.get("paid", null) is Array):
		d["paid"] = []
	d.paid.push_front({"at":now(), "gold":amount, "why":why.left(16)})
	if (d.paid as Array).size() > 12:
		d.paid.resize(12)
	save()
	return {"ok":true}

# ---------------- referrals (0.31.120) ----------------
func grant_referral(kind: String, name: String) -> Dictionary:
	# the server only (server/referrals.gd): a Gold chest -- "joined" (you reached level 5 with a friend's code) or
	# "friend" (a player who entered your code did)
	var out := {"chests":[]}
	add_chest(Eco.REF_CHEST, out, true)
	d.referral.notes.push_front({"kind":kind, "name":name.left(24), "at":now()})
	if (d.referral.notes as Array).size() > 20:
		d.referral.notes.resize(20)
	save()
	return {"ok":true, "chests":out.chests}

# ---------------- the daily login reward (0.31.119) ----------------
func login_ready() -> bool:
	return str(d.login.get("day", "")) != Eco.day_key(now())

func login_next() -> int:
	# the calendar day (0-6) the next claim gives
	return posmod(int(d.login.get("n", 0)), Eco.LOGIN_REWARDS.size())

func claim_login() -> Dictionary:
	# one a day: the calendar's next reward (the server replays this with its own clock)
	if not login_ready():
		return {"ok":false, "error":"claimed today"}
	var i := login_next()
	var rw: Dictionary = Eco.LOGIN_REWARDS[i]
	var out := {"chests":[]}
	d.gold = int(d.gold) + int(rw.get("gold", 0))
	d.gems = int(d.gems) + int(rw.get("gems", 0))
	if rw.has("chest"):
		add_chest(str(rw.chest), out, true)
	d.login.day = Eco.day_key(now())
	d.login.n = int(d.login.get("n", 0)) + 1
	save()
	_rec("claim_login", [])
	return {"ok":true, "day":i + 1, "reward":rw, "chests":out.chests}

# ---------------- matches ----------------
func apply_match(me: Dictionary, won: bool, draw: bool, online: bool) -> Dictionary:
	# Called once per finished match. Returns the itemised rewards plus level-ups, pass tiers
	# and challenge progress for the results screen.
	refresh()
	var stats := Eco.match_stats(me, won, draw)
	var today := Eco.day_key(now())
	var first_win := won and str(d.first_win_day) != today
	if first_win:
		d.first_win_day = today
	var r := Eco.match_rewards(stats, won, draw, online, first_win)
	var out := {"rewards":r, "levels":[], "tiers":[], "challenges":[], "first_win":first_win, "chests":[]}
	d.gold += int(r.gold)
	# 0.31.93: a win counts toward the equipped weapon's third star (0.31.184: the match's Embers are in its gold)
	var main := str(stats.get("main", ""))
	if won and main != "" and d.equip.has(main):
		var wid := Eco.forge_id(main, str(d.equip[main].weapon))
		d.forge.wins[wid] = int(d.forge.wins.get(wid, 0)) + 1
	# 0.31.37: chests -- every win a Wooden one (Silver for a rescue or a multi-kill); the first win of the day a Silver
	if won:
		add_chest("silver" if int(stats.get("rescues", 0)) > 0 or int(me.get("best_multi", 0)) >= 2 else "wooden", out)
	if first_win:
		add_chest("silver", out)
	_add_xp(int(r.xp), out)
	_add_pass_xp(int(r.pass), out)
	for key in ["matches", "wins", "rescues", "kills", "gates", "gathered", "fed", "lifts", "repaired", "healed"] + Eco.FIVE_STATS:
		d.stats[key] = int(d.stats.get(key, 0)) + int(stats.get(key, 0))
	_title_stats(stats, won)
	out["quests"] = _quest_stats(stats, won)
	for span in ["daily", "weekly"]:
		for c in (d.challenges.daily if span == "daily" else d.challenges.weekly):
			var def: Dictionary = Eco.CHALLENGES[c.id]
			if bool(c.claimed):
				continue
			var before := int(c.progress)
			c.progress = mini(int(def.goal), before + int(stats.get(def.stat, 0)))
			if int(c.progress) != before:
				out.challenges.append({"id":c.id, "text":def.text, "progress":c.progress, "goal":def.goal,
					"done":int(c.progress) >= int(def.goal), "span":span})
	out["titles"] = check_titles()
	d.history.push_front({"at":now(), "won":won, "draw":draw, "online":online, "gold":r.gold, "cls":str(me.get("cls", ""))})
	if d.history.size() > 20:
		d.history.resize(20)
	save()
	if not online:
		_rec("match", [slim_me(me), won, draw])     # 0.31.108: (an online match's result the server takes from its own match)
	return out

static func slim_me(me: Dictionary) -> Dictionary:
	# what a match's result needs of the unit (the op that carries it goes to the server; the unit has much more)
	var out := {}
	for k in ["kills", "rescues", "gate_dmg", "gathered", "fed", "lifts", "repaired", "healed", "best_multi", "cls", "cls_main",
			"kills_cls", "q"] + Eco.FIVE_STATS:
		if me.has(k):
			var v: Variant = me[k]
			out[k] = (v as Dictionary).duplicate(true) if v is Dictionary else v
	return out

func _title_stats(stats: Dictionary, won: bool) -> void:
	# 0.31.87: the lifetime numbers the titles read (Eco.TITLE_GOALS), from one match's stats
	var main := str(stats.get("main", ""))
	if main != "":
		d.stats["main_" + main] = int(d.stats.get("main_" + main, 0)) + 1
		if won:
			d.stats["win_" + main] = int(d.stats.get("win_" + main, 0)) + 1
	for key in stats:
		if str(key).begins_with("kills_"):
			d.stats[key] = int(d.stats.get(key, 0)) + int(stats[key])
	d.stats.best_multi = maxi(int(d.stats.get("best_multi", 0)), int(stats.get("best_multi", 0)))
	d.stats.streak = int(d.stats.get("streak", 0)) + 1 if won else 0          # (a draw or a loss ends the run)
	d.stats.best_streak = maxi(int(d.stats.get("best_streak", 0)), int(d.stats.streak))

func claim_discord() -> Dictionary:
	# 0.31.124: the gift for opening the Discord invite (Settings > COMMUNITY) -- once per account; the server replays it
	# on its own copy, so a phone can't take it twice
	if bool(d.get("discord", false)):
		return {"ok":false, "error":"claimed"}
	d["discord"] = true
	d.gems = int(d.gems) + Eco.DISCORD_GEMS
	save()
	_rec("claim_discord", [])
	return {"ok":true, "gems":Eco.DISCORD_GEMS}

func finish_tutorial() -> Dictionary:
	# the Herald's last line: the recruit's pay, once (0.31.108: here, so the server pays it too)
	if bool(d.get("tutorial_done", false)):
		return {"ok":false}
	d.gold = int(d.gold) + Eco.TUTORIAL_GOLD
	d["tutorial_done"] = true
	save()
	_rec("finish_tutorial", [])
	return {"ok":true}

static func clean_name(s: String) -> String:
	var out := ""
	for ch in s:
		if ch.unicode_at(0) >= 32 and ch.unicode_at(0) != 127:
			out += ch
	return out.strip_edges().left(20)

func set_name(nm: String) -> Dictionary:
	var n := clean_name(nm)
	if n == "" or n == str(d.name):
		return {"ok":false}
	d.name = n
	save()
	_rec("set_name", [n])
	return {"ok":true}

# ---------------- class quests (0.31.97) ----------------
func _quest_stats(stats: Dictionary, won: bool) -> Array:
	# Add one match to every class quest's counters (Eco.QUESTS: a base class counts its upgrade too). -> the lines the
	# results screen shows: each quest whose current step moved, with whether it is now ready to claim.
	var q: Dictionary = stats.get("q", {})
	var before := {}
	for cls in Eco.QUESTS:
		before[cls] = quest_have(cls)
	for cls in Eco.QUESTS:
		var t := 0.0
		var add := {}
		var multi := 0
		for c in Eco.quest_family(cls):
			var e: Variant = q.get(c, {})
			if not (e is Dictionary):
				continue
			t += float(e.get("t", 0.0))
			for st in Eco.QUEST_COUNTS:
				add[st] = int(add.get(st, 0)) + int(e.get(st, 0))
			multi = maxi(multi, int(e.get("best_multi", 0)))
		if t >= Eco.QUEST_MIN_TIME:
			add["matches"] = 1
			if won:
				add["wins"] = 1
		for st in add:
			if int(add[st]) > 0:
				var k := Eco.quest_key(cls, str(st))
				d.stats[k] = int(d.stats.get(k, 0)) + int(add[st])
		var mk := Eco.quest_key(cls, "best_multi")
		if multi > int(d.stats.get(mk, 0)):
			d.stats[mk] = multi
	var lines := []
	for cls in Eco.QUESTS:
		var step := quest_step(cls)
		if step >= Eco.QUESTS[cls].steps.size():
			continue
		var have := quest_have(cls)
		if have != int(before[cls]):
			var s: Dictionary = Eco.QUESTS[cls].steps[step]
			lines.append({"cls":cls, "step":step, "text":str(s.task), "progress":mini(have, int(s.n)), "goal":int(s.n),
				"done":have >= int(s.n)})
	return lines

func quest_step(cls: String) -> int:
	# the steps of cls's quest already claimed (= the index of the one being worked on)
	return int(d.quests.get(cls, 0))

func quest_have(cls: String) -> int:
	# progress on cls's current step (its stat's lifetime count)
	return Eco.quest_progress(d.stats, cls, quest_step(cls))

func quest_ready(cls: String) -> bool:
	var q: Dictionary = Eco.QUESTS.get(cls, {})
	var step := quest_step(cls)
	return not q.is_empty() and step < q.steps.size() and quest_have(cls) >= int(q.steps[step].n)

func quests_ready() -> int:
	var n := 0
	for cls in Eco.QUESTS:
		if quest_ready(cls) and str(cls) != "worker":          # (0.31.164: the Worker's is Siege's, not shown)
			n += 1
	return n

func quest_done(cls: String) -> bool:
	return Eco.QUESTS.has(cls) and quest_step(cls) >= Eco.QUESTS[cls].steps.size()

func claim_quest(cls: String) -> Dictionary:
	# Claim cls's current step: its reward (gold / gems / a chest, or the legendary on the last step).
	# -> {ok, step (the one claimed, 0-based), reward, chests, item}
	if not quest_ready(cls):
		return {"ok":false}
	var step := quest_step(cls)
	var r := Eco.quest_reward(cls, step)
	var out := {"ok":true, "step":step, "reward":r, "chests":[], "item":str(r.get("item", ""))}
	d.gold = int(d.gold) + int(r.get("gold", 0))
	d.gems = int(d.gems) + int(r.get("gems", 0))
	if r.has("chest"):
		add_chest(str(r.chest), out, true)
	if out.item != "" and not d.owned.has(out.item):
		d.owned.append(out.item)
	d.quests[cls] = step + 1
	save()
	_rec("claim_quest", [cls])
	return out

func title_progress(id: String) -> int:
	return Eco.title_progress(d.stats, id)

func check_titles() -> Array:
	# Titles whose goal is reached and that aren't owned yet: owned now. -> their ids (rarest first).
	var got := []
	for id in Eco.TITLE_GOALS:
		if not d.owned.has(id) and title_progress(id) >= int(Eco.TITLE_GOALS[id].n):
			d.owned.append(id)
			got.append(id)
	got.sort_custom(func(a, b): return Eco.TITLE_RARITY_ORDER.find(str(Eco.CATALOG[a].rarity)) > Eco.TITLE_RARITY_ORDER.find(str(Eco.CATALOG[b].rarity)))
	return got

# ---------------- the Forge (0.31.93) ----------------
func forge_stars(wid: String) -> int:
	return clampi(int(d.forge.stars.get(wid, 0)), 0, Eco.FORGE_STARS.size())

func forge_wins(wid: String) -> int:
	return int(d.forge.wins.get(wid, 0))

func forge_element(wid: String) -> String:
	var e := str(d.forge.element.get(wid, ""))
	return e if Eco.ELEMENTS.has(e) else ""

func forge_owns(wid: String) -> bool:
	# a starter is always yours; a catalog weapon once owned
	return wid.begins_with("default_") and (Eco.CLASSES + Eco.UP_CLASSES).has(wid.substr(8)) or owns(wid)

func can_forge(wid: String, element := "") -> Dictionary:
	# -> {"ok": bool, "why": what's missing ("owned" | "maxed" | "gold" | "wins" | "element")}
	if not forge_owns(wid):
		return {"ok":false, "why":"owned"}
	var next := forge_stars(wid) + 1
	var cost := Eco.forge_cost(next)
	if cost.is_empty():
		return {"ok":false, "why":"maxed"}
	if next == Eco.FORGE_STARS.size():
		if forge_wins(wid) < Eco.FORGE_WINS:
			return {"ok":false, "why":"wins"}
		if not Eco.ELEMENTS.has(element):
			return {"ok":false, "why":"element"}
	if int(d.gold) < int(cost.gold):
		return {"ok":false, "why":"gold"}
	return {"ok":true, "why":""}

func forge(wid: String, element := "") -> Dictionary:
	var c := can_forge(wid, element)
	if not bool(c.ok):
		return c
	var next := forge_stars(wid) + 1
	var cost := Eco.forge_cost(next)
	d.gold -= int(cost.gold)
	d.forge.stars[wid] = next
	if next == Eco.FORGE_STARS.size():
		d.forge.element[wid] = element
	save()
	_rec("forge", [wid, element])
	return {"ok":true, "stars":next}

func set_forge_element(wid: String, element: String) -> bool:
	# an Ascended weapon's aura colour can be changed for free
	if forge_stars(wid) < Eco.FORGE_STARS.size() or not Eco.ELEMENTS.has(element):
		return false
	d.forge.element[wid] = element
	save()
	_rec("set_forge_element", [wid, element])
	return true

func forge_fx(cls: String) -> Dictionary:
	# the equipped weapon's Forge look for the battle view: {} when it has no stars
	if not d.equip.has(cls):
		return {}
	var wid := Eco.forge_id(cls, str(d.equip[cls].weapon))
	var n := forge_stars(wid)
	if n <= 0:
		return {}
	return {"stars":n, "rarity":Eco.forge_rarity(wid), "element":forge_element(wid)}

# ---------------- chests (0.31.37) ----------------
func chests() -> Array:
	return d.chests.slots

func add_chest(kind: String, out: Dictionary, reward := false) -> void:
	# a new chest takes a free slot; with all CHEST_SLOTS full a match's chest is turned into gold at once, while a
	# reward chest (a level, the pass, a quest, a whole day's / week's orders -- 0.31.108) waits for a slot
	if not out.has("chests"):
		out["chests"] = []
	if d.chests.slots.size() >= Eco.CHEST_SLOTS:
		if reward and (d.chests.queue as Array).size() < Eco.CHEST_QUEUE_MAX:
			d.chests.queue.append(kind)
			out.chests.append({"kind":kind, "full":false, "queued":true})
			return
		var g: int = int(Eco.CHEST_FULL_GOLD[kind])
		d.gold += g
		out.chests.append({"kind":kind, "full":true, "gold":g})
		return
	_new_chest(kind)
	out.chests.append({"kind":kind, "full":false})

func _new_chest(kind: String) -> void:
	var c := {"id":int(d.chests.next), "kind":kind, "got":now(), "start":-1}
	d.chests.next = int(d.chests.next) + 1
	d.chests.slots.append(c)

func _fill_slots() -> void:
	# the waiting reward chests move into the slots that are free
	while d.chests.slots.size() < Eco.CHEST_SLOTS and not (d.chests.queue as Array).is_empty():
		_new_chest(str(d.chests.queue.pop_front()))

func chests_waiting() -> int:
	return (d.chests.get("queue", []) as Array).size()

func chest_left(c: Dictionary) -> int:
	# seconds until it's unlocked (its full time if not started)
	var t: int = int(Eco.CHESTS[c.kind].unlock)
	if int(c.start) < 0:
		return t
	return maxi(0, int(c.start) + t - now())

func chest_ready(c: Dictionary) -> bool:
	return int(c.start) >= 0 and chest_left(c) <= ready_grace

func unlocking() -> Dictionary:
	for c in d.chests.slots:
		if int(c.start) >= 0 and chest_left(c) > 0:
			return c
	return {}

func start_unlock(index: int) -> bool:
	if index < 0 or index >= d.chests.slots.size() or not unlocking().is_empty():
		return false
	var c: Dictionary = d.chests.slots[index]
	if int(c.start) >= 0:
		return false
	c.start = now()
	save()
	_rec("start_unlock", [int(c.id)])
	return true

func skip_chest(index: int) -> Dictionary:
	if index < 0 or index >= d.chests.slots.size():
		return {"ok":false}
	var c: Dictionary = d.chests.slots[index]
	var cost := Eco.skip_cost(chest_left(c))
	if chest_ready(c) or int(d.gems) < cost:
		return {"ok":false, "cost":cost}
	d.gems = int(d.gems) - cost
	c.start = now() - int(Eco.CHESTS[c.kind].unlock)
	save()
	_rec("skip_chest", [int(c.id)])
	return {"ok":true, "cost":cost}

func open_chest(index: int) -> Dictionary:
	if index < 0 or index >= d.chests.slots.size():
		return {"ok":false}
	var c: Dictionary = d.chests.slots[index]
	if not chest_ready(c):
		return {"ok":false}
	# 0.31.108: the roll's seed is the account's salt and the chest's id and kind -- the phone and the server roll the
	# same (it was the name and the time it was got, which the two may not agree on)
	var roll := Eco.roll_chest(str(c.kind), hash([int(d.chests.get("salt", 0)), int(c.id), str(c.kind)]), d.owned, int(d.chests.pity),
		Eco.season_id(now()))
	d.chests.pity = int(roll.pity)
	d.gold += int(roll.gold) + int(roll.get("dupe_gold", 0))
	d.gems += int(roll.gems)
	if str(roll.item) != "" and not d.owned.has(roll.item):
		d.owned.append(roll.item)
	d.chests.slots.remove_at(index)
	_fill_slots()
	save()
	_rec("open_chest", [int(c.id)])
	roll["ok"] = true
	roll["kind"] = c.kind
	return roll
