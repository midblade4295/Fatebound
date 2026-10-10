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

signal changed

func _init(save_path := "user://siege_profile.json", legacy := "user://fatebound-save.json") -> void:
	path = save_path
	legacy_path = legacy

func now() -> int:
	return now_override if now_override >= 0 else int(Time.get_unix_time_from_system())

static func defaults() -> Dictionary:
	var equip := {}
	for c in Eco.CLASSES + Eco.UP_CLASSES:
		equip[c] = {"skin":"", "weapon":""}
	return {"schema":SCHEMA, "name":"Player", "gold":0, "gems":0, "level":1, "xp":0,
		"pass":{"season":0, "xp":0, "premium":false, "free":[], "prem":[]},
		"owned":[], "equip":equip, "title":"",
		"challenges":{"day":"", "daily":[], "week":"", "weekly":[], "rerolled":false},
		"stats":{"matches":0, "wins":0, "rescues":0, "kills":0, "gates":0, "gathered":0, "fed":0,
			"lifts":0, "repaired":0, "healed":0, "best_multi":0, "streak":0, "best_streak":0},     # (0.31.87: for the titles)
		"first_win_day":"", "history":[], "migration":{},
		"embers":0,                                                  # 0.31.90: the Forge's material
		"forge":{"stars":{}, "wins":{}, "element":{}},              # 0.31.93: per weapon (Eco.forge_id): stars 0-3, wins, aura element
		"iap":{"done":[], "starter":false},                          # 0.31.90: purchase tokens already granted
		"chests":{"slots":[], "next":1, "pity":0},
		"settings":{"master":0.8, "music":0.6, "sfx":0.8, "reduce_motion":false}}

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
	# 0.31.93: the Forge -- ints again, nothing out of range
	out.embers = maxi(0, int(out.get("embers", 0)))
	for part in ["stars", "wins", "element"]:
		if not (out.forge.get(part) is Dictionary):
			out.forge[part] = {}
	for wid in out.forge.stars.keys():
		out.forge.stars[wid] = clampi(int(out.forge.stars[wid]), 0, Eco.FORGE_STARS.size())
	for wid in out.forge.wins.keys():
		out.forge.wins[wid] = maxi(0, int(out.forge.wins[wid]))
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

func save() -> bool:
	# Write to a temp file then rename, so a crash mid-write can't corrupt the profile.
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
	# One-time conversion of a dice-era save; also used by Settings > Import old progress.
	if not d.migration.is_empty() and str(d.migration.get("from", "")) == "legacy":
		return {"ok":false, "error":"Old progress was already imported"}
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
		d.pass = {"season":sid, "xp":0, "premium":false, "free":[], "prem":[]}
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
			add_chest(str(r.chest), out)
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

func claim_tier(tier: int, premium: bool) -> Dictionary:
	if not can_claim(tier, premium):
		return {"ok":false}
	var r := Eco.pass_reward(int(d.pass.season), tier, premium)
	_grant(r)
	(d.pass.prem if premium else d.pass.free).append(tier)
	save()
	return {"ok":true, "reward":r}

func claim_all() -> Array:
	var got := []
	for tier in range(1, pass_tier() + 1):
		for prem in [false, true]:
			if can_claim(tier, prem):
				var r := Eco.pass_reward(int(d.pass.season), tier, prem)
				_grant(r)
				(d.pass.prem if prem else d.pass.free).append(tier)
				got.append(r)
	if not got.is_empty():
		save()
	return got

func buy_premium() -> Dictionary:
	if bool(d.pass.premium):
		return {"ok":false, "error":"You already own this season's premium pass"}
	if int(d.gems) < Eco.PREMIUM_COST:
		return {"ok":false, "error":"Not enough gems"}
	d.gems -= Eco.PREMIUM_COST
	d.pass.premium = true
	save()
	return {"ok":true}

func _grant(r: Dictionary) -> void:
	d.gold += int(r.get("gold", 0))
	d.gems += int(r.get("gems", 0))
	d.embers = int(d.get("embers", 0)) + int(r.get("embers", 0))
	if r.has("chest"):
		add_chest(str(r.chest), {})
	var id := str(r.get("item", ""))
	if id != "" and not d.owned.has(id):
		d.owned.append(id)

# ---------------- shop / locker ----------------
func owns(id: String) -> bool:
	return d.owned.has(id)

func can_afford(price: Dictionary) -> bool:
	return int(d.gold) >= int(price.get("gold", 0)) and int(d.gems) >= int(price.get("gems", 0))

func buy(id: String) -> Dictionary:
	var price := Eco.item_price(id)
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
	return {"ok":true, "gems":gems}

# ---------------- in-app purchases (0.31.90) ----------------
func iap_granted(token: String) -> bool:
	for e in d.iap.done:
		if str((e as Dictionary).get("t", "")) == token:
			return true
	return false

func grant_iap(product: String, token: String) -> Dictionary:
	# A purchase Google and the server have confirmed: add what it holds. Idempotent per token (a retry after a crash,
	# or the same purchase seen again on the next start, grants nothing twice). -> {ok, gems, embers, item, again}
	var pk: Dictionary = Net.IAP.get(product, {})
	if pk.is_empty() or token == "":
		return {"ok":false, "error":"Unknown purchase"}
	if iap_granted(token):
		return {"ok":true, "again":true, "gems":0, "embers":0, "item":""}
	var out := {"ok":true, "again":false, "gems":int(pk.get("gems", 0)), "embers":int(pk.get("embers", 0)), "item":""}
	d.gems = int(d.gems) + int(out.gems)
	d.embers = int(d.get("embers", 0)) + int(out.embers)
	if str(pk.get("weapon", "")) != "":
		# a weapon of that rarity the player doesn't own yet (shop pool), picked from the token so a retry picks the same
		var pool: Array = []
		for id in Eco.chest_pool(str(pk.weapon)):
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
	return {"ok":true}

func unequip(cls: String, slot: String) -> void:
	if slot == "title":
		d.title = ""
	elif d.equip.has(cls):
		d.equip[cls][slot] = ""
	save()

func look_for(cls: String) -> Dictionary:
	# What the battle view should show for this class: {"tint": Color or null, "r": model, "l": model}.
	var out := {}
	if not d.equip.has(cls):
		return out
	var wpn := Eco.item(str(d.equip[cls].weapon))           # (0.31.39: weapons only -- no skins)
	if not wpn.is_empty():
		out["r"] = str(wpn.r)
		out["l"] = str(wpn.l)
	var fx := forge_fx(cls)                                    # 0.31.93: the Forge's stars
	if not fx.is_empty():
		out["forge"] = fx
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
	return true

func claim_challenge(span: String, index: int) -> Dictionary:
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
	var embers := Eco.EMBERS_DAILY if span == "daily" else 0      # 0.31.93
	d.embers = int(d.get("embers", 0)) + embers
	# 0.31.37: the whole day's challenges done -> a Silver chest; the whole week's -> a Gold chest
	if list.all(func(x): return bool(x.claimed)):
		add_chest("silver" if span == "daily" else "gold", out)
	save()
	return {"ok":true, "tiers":out.tiers, "chests":out.chests, "embers":embers}

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
	# 0.31.93: Embers for the Forge, and a win counts toward the equipped weapon's third star
	var embers := Eco.EMBERS_WIN if won else Eco.EMBERS_MATCH
	d.embers = int(d.get("embers", 0)) + embers
	out["embers"] = embers
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
	for key in ["matches", "wins", "rescues", "kills", "gates", "gathered", "fed", "lifts", "repaired", "healed"]:
		d.stats[key] = int(d.stats.get(key, 0)) + int(stats.get(key, 0))
	_title_stats(stats, won)
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
	# -> {"ok": bool, "why": what's missing ("owned" | "maxed" | "embers" | "gold" | "wins" | "element")}
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
	if int(d.get("embers", 0)) < int(cost.embers):
		return {"ok":false, "why":"embers"}
	if int(d.gold) < int(cost.gold):
		return {"ok":false, "why":"gold"}
	return {"ok":true, "why":""}

func forge(wid: String, element := "") -> Dictionary:
	var c := can_forge(wid, element)
	if not bool(c.ok):
		return c
	var next := forge_stars(wid) + 1
	var cost := Eco.forge_cost(next)
	d.embers = int(d.embers) - int(cost.embers)
	d.gold -= int(cost.gold)
	d.forge.stars[wid] = next
	if next == Eco.FORGE_STARS.size():
		d.forge.element[wid] = element
	save()
	return {"ok":true, "stars":next}

func set_forge_element(wid: String, element: String) -> bool:
	# an Ascended weapon's aura colour can be changed for free
	if forge_stars(wid) < Eco.FORGE_STARS.size() or not Eco.ELEMENTS.has(element):
		return false
	d.forge.element[wid] = element
	save()
	return true

func buy_embers(pack_id: String) -> Dictionary:
	var pk := Eco.ember_pack(pack_id)
	if pk.is_empty() or int(d.gems) < int(pk.gems):
		return {"ok":false}
	d.gems -= int(pk.gems)
	d.embers = int(d.get("embers", 0)) + int(pk.embers)
	save()
	return {"ok":true, "embers":int(pk.embers)}

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

func add_chest(kind: String, out: Dictionary) -> void:
	# a new chest takes a free slot; with all CHEST_SLOTS full it's turned into gold at once
	if not out.has("chests"):
		out["chests"] = []
	if d.chests.slots.size() >= Eco.CHEST_SLOTS:
		var g: int = int(Eco.CHEST_FULL_GOLD[kind])
		d.gold += g
		out.chests.append({"kind":kind, "full":true, "gold":g})
		return
	var c := {"id":int(d.chests.next), "kind":kind, "got":now(), "start":-1}
	d.chests.next = int(d.chests.next) + 1
	d.chests.slots.append(c)
	out.chests.append({"kind":kind, "full":false})

func chest_left(c: Dictionary) -> int:
	# seconds until it's unlocked (its full time if not started)
	var t: int = int(Eco.CHESTS[c.kind].unlock)
	if int(c.start) < 0:
		return t
	return maxi(0, int(c.start) + t - now())

func chest_ready(c: Dictionary) -> bool:
	return int(c.start) >= 0 and chest_left(c) <= 0

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
	return {"ok":true, "cost":cost}

func open_chest(index: int) -> Dictionary:
	if index < 0 or index >= d.chests.slots.size():
		return {"ok":false}
	var c: Dictionary = d.chests.slots[index]
	if not chest_ready(c):
		return {"ok":false}
	var roll := Eco.roll_chest(str(c.kind), hash([str(d.get("name", "")), int(c.id), int(c.got)]), d.owned, int(d.chests.pity))
	d.chests.pity = int(roll.pity)
	d.gold += int(roll.gold)
	d.embers = int(d.get("embers", 0)) + int(roll.get("dupe_embers", 0))
	d.gems += int(roll.gems)
	if str(roll.item) != "" and not d.owned.has(roll.item):
		d.owned.append(roll.item)
	d.chests.slots.remove_at(index)
	save()
	roll["ok"] = true
	roll["kind"] = c.kind
	return roll
