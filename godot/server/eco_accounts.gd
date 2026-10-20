extends RefCounted
# 0.31.108 (Kevin: "make sure everything is verified by server so players can't edit gems ect"): the accounts.
# Every player's profile lives here, in the server's state directory, and changes only through this file:
#   - the ops a phone sends ("eco" message): each one replayed with the game's own Profile code (Profile.apply_op), so
#     every price, balance and rule is checked exactly as the phone checked it, with the server's clock;
#   - a VS BOTS result: only against a ticket this server issued when the match began (a phone must be online to
#     start one -- Kevin: "Always online"), at least MIN_MATCH_S later, every number clamped to what a match can give;
#   - an online match's result: taken from the server's own match (siege_server.gd + match_ledger.gd), never the phone's;
#   - a purchase Google confirmed (iap_verify.gd), granted once per purchase token across ALL accounts.
# The phone's copy is a prediction: every answer carries the account as it stands, and the phone takes it.
#
# Files (STATE_DIRECTORY, /var/lib/fatebound-siege under systemd): accounts/<id>.json (the profile, Profile's own atomic
# save), accounts/<id>.meta.json (the key's hash, the last op applied, tickets), purchase_tokens.json (token hash ->
# account). The key itself is never stored, only its SHA-256.
# 0.31.132 (the iOS port, IOS_PORT_SPEC_FOR_CLAUDE.md §4, §6): the account between phones -- a transfer code
# (link_new / link_use: 8 characters, 10 minutes, once), the Game Center player linked to an account (gc_links.json:
# a hash of the teamPlayerID, never the id itself), extra keys for an account's other phones (meta.keys, hashes), and
# deleting an account (delete_account) from the app.
const Profile = preload("res://scripts/meta/profile.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const Net = preload("res://scripts/siege/siege_net.gd")

const MIN_MATCH_S := 150             # a VS BOTS result needs at least this long since its ticket (real matches: 4-12 min)
const TICKET_LIFE := 24 * 3600       # a result can come in late (the phone lost its connection at the end)
const MAX_TICKETS := 4
const MAX_OPS := 64                  # ops per message
const CACHE_MAX := 256               # profiles kept in memory
const READY_GRACE := 30              # a chest counts as unlocked 30 s early (the phone's clock may run a little ahead)
const IMPORT_UNTIL := 1796083200     # 2026-12-01 UTC: until then a new account takes in the phone's existing progress
const NEW_PER_HOUR := 240            # new accounts the whole server makes in an hour (a flood is refused, "busy")
const CLASSES := ["knight", "barbarian", "rogue", "ranger", "mage", "priest", "worker", "crusader", "berserker",
	"necromancer", "assassin", "sniper", "archmage", "villager"]

var dir := ""
var state := ""
var cache := {}                      # id -> {"id", "p": Profile, "meta": Dictionary, "used": msec}
var tokens := {}                     # purchase token hash (16 hex) -> account id ("" = checked by Google, granted by an older app)
var tokens_path := ""
var log_fn: Callable = func(_s): pass
var now_override := -1               # tests
# 0.31.132: the account between phones
const LINK_LIFE := 600               # a transfer code lasts 10 minutes
const LINK_CHARS := "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"   # 32: no 0/O, 1/I (256 % 32 == 0: every one as likely)
const LINK_LEN := 8
const LINK_PER_HOUR := 5             # codes one account makes in an hour
const LINK_TRIES := 10               # wrong codes one address may try in LINK_TRY_WINDOW
const LINK_TRIES_ALL := 60           # ... and the whole server (behind the proxy every address looks the same)
const LINK_TRY_WINDOW := 600
const MAX_KEYS := 8                  # other phones' keys an account keeps (the oldest goes)
var links := {}                      # code -> {"id", "until"} (memory only: a restart drops the codes)
var link_made := {}                  # id -> [unix] (codes made)
var link_tries := {}                 # address -> [unix] (wrong codes)
var link_tries_all: Array = []
var gc_links := {}                   # gc_hash(teamPlayerID) -> account id
var gc_path := ""
var _made: Array = []                # when the last new accounts were made (the hourly limit)

func _init(state_dir := "") -> void:
	state = state_dir
	if state == "":
		state = OS.get_environment("STATE_DIRECTORY") if OS.has_environment("STATE_DIRECTORY") else "user://"
	dir = state.path_join("accounts")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	tokens_path = state.path_join("purchase_tokens.json")
	_load_tokens()
	gc_path = state.path_join("gc_links.json")
	if FileAccess.file_exists(gc_path):
		var g: Variant = JSON.parse_string(FileAccess.get_file_as_string(gc_path))
		gc_links = g if g is Dictionary else {}

func now() -> int:
	return now_override if now_override >= 0 else int(Time.get_unix_time_from_system())

func count() -> int:
	var n := 0
	var da := DirAccess.open(dir)
	if da != null:
		for f in da.get_files():
			if f.ends_with(".meta.json"):
				n += 1
	return n

# ---------------- purchase tokens ----------------
static func token_hash(token: String) -> String:
	return token.sha256_text().left(16)            # (iap_verify.gd's ledger keeps the same 16)

func _load_tokens() -> void:
	tokens = {}
	if FileAccess.file_exists(tokens_path):
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(tokens_path))
		if v is Dictionary:
			tokens = v
	# purchases Google confirmed for an older app (granted on the phone): known, not yet tied to an account
	var ledger := state.path_join("iap_ledger.jsonl")
	if FileAccess.file_exists(ledger):
		var f := FileAccess.open(ledger, FileAccess.READ)
		while f != null and not f.eof_reached():
			var line := f.get_line().strip_edges()
			if line == "":
				continue
			var ln: Variant = JSON.parse_string(line)
			if ln is Dictionary and str(ln.get("v", "")) == "ok" and not tokens.has(str(ln.get("tok", ""))):
				tokens[str(ln.tok)] = ""

func _save_tokens() -> void:
	_write(tokens_path, JSON.stringify(tokens))

func note_verified(token: String) -> void:
	# an older app's purchase Google confirmed (the phone grants it itself): remembered, so its import counts it once
	var h := token_hash(token)
	if not tokens.has(h):
		tokens[h] = ""
		_save_tokens()

# ---------------- files ----------------
static func _write(path: String, text: String) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path)) == OK

static func valid_id(id: String) -> bool:
	if id.length() != 20:
		return false
	for ch in id:
		if not ch in "0123456789abcdef":
			return false
	return true

func _profile(id: String):
	var p = Profile.new(dir.path_join(id + ".json"), "")
	p.server_side = true
	p.ready_grace = READY_GRACE
	p.now_override = now_override
	return p

func _save_meta(e: Dictionary) -> void:
	_write(dir.path_join(str(e.id) + ".meta.json"), JSON.stringify(e.meta))

func _trim_cache() -> void:
	while cache.size() > CACHE_MAX:
		var oldest := ""
		var t := 1 << 62
		for id in cache:
			if int(cache[id].used) < t:
				t = int(cache[id].used)
				oldest = id
		cache.erase(oldest)

func _load(id: String) -> Dictionary:
	# the account, from memory or disk ({} when there is none) -- no key check: callers check it
	if not valid_id(id):
		return {}
	if cache.has(id):
		var c: Dictionary = cache[id]
		c.used = Time.get_ticks_msec()
		c.p.now_override = now_override
		return c
	var mp := dir.path_join(id + ".meta.json")
	if not FileAccess.file_exists(mp) or not FileAccess.file_exists(dir.path_join(id + ".json")):
		return {}
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(mp))
	if not (meta is Dictionary):
		return {}
	var p = _profile(id)
	p.load_or_create()
	var e := {"id":id, "p":p, "meta":meta, "used":Time.get_ticks_msec()}
	cache[id] = e
	_trim_cache()
	return e

func open(id: String, key: String) -> Dictionary:
	if key.length() != 64:
		return {}
	var e := _load(id)
	if e.is_empty():
		return {}
	var h := key.sha256_text()
	if str(e.meta.get("key", "")) != h and not (e.meta.get("keys", []) as Array).has(h):    # (0.31.132: another phone's key)
		return {}
	return e

# ---------------- a new account ----------------
func create(import_d: Variant) -> Dictionary:
	var cr := Crypto.new()
	var id := cr.generate_random_bytes(10).hex_encode()
	while FileAccess.file_exists(dir.path_join(id + ".meta.json")):
		id = cr.generate_random_bytes(10).hex_encode()
	var key := cr.generate_random_bytes(32).hex_encode()
	var p = _profile(id)
	p.d = Profile.defaults()
	var meta := {"v":1, "key":key.sha256_text(), "created":now(), "seq":0, "tickets":[], "rev":0}
	if import_d is Dictionary and not (import_d as Dictionary).is_empty() and now() < IMPORT_UNTIL:
		meta["imported"] = _import(p, import_d, id)
	p.d.chests.salt = int(cr.generate_random_bytes(4).decode_u32(0) & 0x7fffffff)
	p.d.migration = {"from":"server", "at":now()}
	p.refresh()
	p.save()
	var e := {"id":id, "p":p, "meta":meta, "used":Time.get_ticks_msec()}
	cache[id] = e
	_trim_cache()
	_save_meta(e)
	log_fn.call("account %s created%s" % [id, (" (imported: %s)" % JSON.stringify(meta.imported)) if meta.has("imported") else ""])
	e["key_plain"] = key
	return e

func _import(p, src: Dictionary, id: String) -> Dictionary:
	# The phone's progress from before the server kept it, taken in once. It can't be checked, so the numbers are held
	# to what that many matches could have earned, plus the purchases Google confirmed (each token counted for one
	# account only). Cosmetics owned stay owned, up to what that many matches could have brought.
	var v: Dictionary = p._normalized(src)
	var matches := clampi(int(v.stats.get("matches", 0)), 0, 20000)
	var paid_gems := 0
	var paid_gold := 0
	var done := []
	for t in v.iap.get("done", []):
		var tok := str((t as Dictionary).get("t", "")) if t is Dictionary else ""
		var prod := str((t as Dictionary).get("p", "")) if t is Dictionary else ""
		var h := token_hash(tok)
		if tok != "" and tokens.has(h) and str(tokens[h]) == "" and Net.IAP.has(prod):
			tokens[h] = id
			paid_gems += int(Net.IAP[prod].get("gems", 0))
			# (0.31.184: a starter pack bought before gave 300 Embers -- gold now, ten for one, as the phone's balance was turned)
			paid_gold += int(Net.IAP[prod].get("gold", 0))
			done.append(t)
	if not done.is_empty():
		_save_tokens()
	# 0.31.184: Embers are gold (Profile._normalized turned them, Eco.EMBER_GOLD each): the gold cap takes in what the
	# Embers' was (200 + 40 a match, up to 20,000)
	var caps := {"gems": paid_gems + mini(3000, 300 + 12 * matches),
		"gold": paid_gold + mini(400000, 5000 + 900 * matches) + mini(20000, 200 + 40 * matches) * Eco.EMBER_GOLD,
		"level": mini(150, 3 + matches / 2),
		"pass": mini(Eco.PASS_TIERS * Eco.TIER_XP, 5000 + 1500 * matches), "items": 15 + matches / 2 + (30 if paid_gems > 0 else 0)}
	var out := {"matches":matches, "gems":[int(v.gems), mini(int(v.gems), caps.gems)], "gold":[int(v.gold), mini(int(v.gold), caps.gold)],
		"paid":paid_gems}
	var keep := Profile.defaults()
	for k in ["name", "level", "xp", "pass", "owned", "title", "challenges", "stats", "first_win_day", "history",
			"chests", "quests", "tutorial_done"]:            # (0.31.188: no "equip" / "forge" -- the weapons are gone)
		if v.has(k):
			keep[k] = v[k]
	keep.gems = mini(int(v.gems), caps.gems)
	keep.gold = mini(int(v.gold), caps.gold)
	keep.level = clampi(int(v.level), 1, caps.level)
	keep.xp = clampi(int(v.xp), 0, Eco.level_xp(int(keep.level)) - 1)
	keep.pass.xp = clampi(int(v.pass.xp), 0, caps.pass)
	keep.iap = {"done":done, "starter":bool(v.iap.get("starter", false)) and done.any(func(t): return str(t.get("p", "")) == "starter_pack")}
	var owned: Array = keep.owned
	if owned.size() > int(caps.items):
		owned.resize(int(caps.items))                  # (the earliest kept: owned is in the order they were got)
	var ok_owned := owned.duplicate()                  # (titles; 0.31.97-0.31.187 a quest's legendary only with its quest done)
	keep.owned = ok_owned
	keep.chests.slots = (keep.chests.slots as Array).slice(0, Eco.CHEST_SLOTS)
	keep.chests.queue = (keep.chests.get("queue", []) as Array).slice(0, Eco.CHEST_QUEUE_MAX)
	keep.history = (keep.history as Array).slice(0, 20)
	p.d = p._normalized(keep)
	out["items"] = [owned.size(), ok_owned.size()]
	return out

# ---------------- the messages ----------------
static func public_profile(d: Dictionary) -> Dictionary:
	# what the phone gets back: the whole profile but the purchase tokens (the phone keeps its own) and what is the
	# phone's alone (its key, sound/graphics settings, the cloud save's state)
	var out := d.duplicate(true)
	for k in ["account", "settings", "cloud"]:
		out.erase(k)
	out.iap = {"starter":bool(d.iap.get("starter", false)), "n":(d.iap.get("done", []) as Array).size()}
	return out

func handle(msg: Dictionary) -> Dictionary:
	# {"t":"eco", "acct", "key", "ops":[{"s", "op", "a", "tk"?}], "ticket":bool} or {"t":"eco", "new":true, "import":{...}}
	# -> {"t":"eco", "ok", "acct", "key" (a new account only), "seq" (the last op applied), "results", "profile", "now", "ticket"?}
	var e := {}
	var out := {"t":"eco", "ok":true}
	if bool(msg.get("new", false)):
		while not _made.is_empty() and now() - int(_made[0]) > 3600:
			_made.pop_front()
		if _made.size() >= NEW_PER_HOUR:
			return {"t":"eco", "ok":false, "why":"busy"}
		_made.append(now())
		e = create(msg.get("import", {}))
		out["key"] = str(e.key_plain)
		e.erase("key_plain")
	else:
		e = open(str(msg.get("acct", "")), str(msg.get("key", "")))
		if e.is_empty():
			return {"t":"eco", "ok":false, "why":"auth"}
	var p = e.p
	p.refresh()
	var results := []
	var ops: Variant = msg.get("ops", [])
	if ops is Array and (ops as Array).size() <= MAX_OPS:
		for o in ops:
			if not (o is Dictionary):
				continue
			var s := int(o.get("s", 0))
			if s <= int(e.meta.seq):
				results.append({"s":s, "ok":true, "dup":true})       # (sent again after a lost answer: done already)
				continue
			var r: Dictionary = _match(e, o) if str(o.get("op", "")) == "match" else p.apply_op(str(o.get("op", "")), o.get("a", []))
			e.meta.seq = s
			results.append({"s":s, "ok":bool(r.get("ok", false)), "error":str(r.get("error", ""))})
	if bool(msg.get("ticket", false)):
		out["ticket"] = _ticket(e)
	e.meta.rev = int(e.meta.get("rev", 0)) + 1
	_save_meta(e)
	out.merge({"acct":e.id, "seq":int(e.meta.seq), "rev":int(e.meta.rev), "results":results, "now":now(),
		"profile":public_profile(p.d)}, true)
	return out

func _ticket(e: Dictionary) -> String:
	var tk := Crypto.new().generate_random_bytes(6).hex_encode()
	var list: Array = e.meta.get("tickets", [])
	list.append({"id":tk, "at":now(), "used":false})
	while list.size() > MAX_TICKETS:
		list.pop_front()
	e.meta.tickets = list
	return tk

func _match(e: Dictionary, o: Dictionary) -> Dictionary:
	# a VS BOTS result: its ticket, its time, its numbers held to what a match can give
	var a: Variant = o.get("a", [])
	if not (a is Array) or (a as Array).size() != 3 or not (a[0] is Dictionary) or not (a[1] is bool) or not (a[2] is bool):
		return {"ok":false, "error":"bad args"}
	var tk := str(o.get("tk", ""))
	var ticket := {}
	for t in e.meta.get("tickets", []):
		if str(t.id) == tk:
			ticket = t
	if ticket.is_empty() or bool(ticket.used):
		return {"ok":false, "error":"no ticket"}
	var secs := now() - int(ticket.at)
	if secs > TICKET_LIFE:
		return {"ok":false, "error":"ticket expired"}
	if secs < MIN_MATCH_S:
		return {"ok":false, "error":"too short"}
	ticket.used = true
	var p = e.p
	var was: bool = p.replaying
	p.replaying = true
	var res: Dictionary = p.apply_match(clamp_me(a[0], secs), bool(a[1]), bool(a[2]) and not bool(a[1]), false)
	p.replaying = was
	return {"ok":true, "gold":int(res.get("rewards", {}).get("gold", 0))}

static func clamp_me(me: Dictionary, secs: int) -> Dictionary:
	# A phone's claim about its own VS BOTS match: nothing beyond what one match of that length can hold.
	var mins := maxf(1.0, float(secs) / 60.0)
	var cap := {"kills": mini(150, int(mins * 12.0)), "rescues": 5, "gate_dmg": 40000.0, "gathered": mini(400, int(mins * 40.0)),
		"fed": 20, "lifts": 30, "repaired": 40000.0, "healed": 40000.0, "best_multi": 10,
		# 0.31.164 (5v5): towers destroyed (11 a side), jungle camps, minion last hits, epic monsters
		"towers": 12, "camps": mini(40, int(mins * 3.0)), "lh": mini(400, int(mins * 20.0)), "epics": 8}
	var out := {}
	for k in cap:
		var v: Variant = me.get(k, 0)
		var x := float(v) if (v is int or v is float) and is_finite(float(v)) else 0.0
		out[k] = clampf(x, 0.0, float(cap[k])) if cap[k] is float else clampi(int(x), 0, int(cap[k]))
	var cls := str(me.get("cls", "villager"))
	out["cls"] = cls if CLASSES.has(cls) else "villager"
	var main := str(me.get("cls_main", ""))
	out["cls_main"] = main if CLASSES.has(main) and main != "villager" else ""
	var kc := {}
	var left := int(out.kills)
	var kv: Variant = me.get("kills_cls", {})
	if kv is Dictionary:
		for c in kv:
			if CLASSES.has(str(c)) and (kv[c] is int or kv[c] is float) and left > 0:
				var n := clampi(int(kv[c]), 0, left)
				kc[str(c)] = n
				left -= n
	out["kills_cls"] = kc
	var q := {}
	var qv: Variant = me.get("q", {})
	if qv is Dictionary:
		var t_left := float(secs)
		for c in qv:
			if not CLASSES.has(str(c)) or not (qv[c] is Dictionary) or q.size() >= 6:
				continue
			var e: Dictionary = qv[c]
			var t := clampf(float(e.get("t", 0.0)) if (e.get("t", 0.0) is int or e.get("t", 0.0) is float) else 0.0, 0.0, t_left)
			t_left -= t
			var qe := {"t":t}
			for st in ["kills", "rescues", "gathered", "fed", "lifts", "best_multi", "towers", "camps", "lh", "epics"]:
				var x: Variant = e.get(st, 0)
				qe[st] = clampi(int(x) if (x is int or x is float) else 0, 0, int(out.get(st, 0)))
			var g: Variant = e.get("gates", 0)
			qe["gates"] = clampi(int(g) if (g is int or g is float) else 0, 0, int(float(out.gate_dmg) / 100.0))
			for st in ["healed", "repaired"]:
				var x: Variant = e.get(st, 0)
				qe[st] = clampi(int(x) if (x is int or x is float) else 0, 0, int(out[st]))
			q[str(c)] = qe
	out["q"] = q
	return out

# ---------------- what the server itself decides ----------------
func apply_online(id: String, me: Dictionary, won: bool, draw: bool) -> Dictionary:
	# an online match's result, from the server's own match
	var e := _load(id)
	if e.is_empty():
		return {}
	var p = e.p
	p.refresh()
	p.replaying = true
	var res: Dictionary = p.apply_match(me, won, draw, true)
	p.replaying = false
	e.meta.rev = int(e.meta.get("rev", 0)) + 1
	_save_meta(e)
	return res

func grant_prize(id: String, week: String, rank: int, prize: Dictionary) -> bool:
	# 0.31.120: a weekly leaderboard prize (server/leaderboard.gd when the week ends) -- once per week per account
	var e := _load(id)
	if e.is_empty():
		return false
	var p = e.p
	p.refresh()
	p.replaying = true
	var r: Dictionary = p.grant_prize(week, rank, prize)
	p.replaying = false
	if not bool(r.get("ok", false)):
		return false
	e.meta.rev = int(e.meta.get("rev", 0)) + 1
	_save_meta(e)
	return true

func pay_gold(id: String, amount: int, why: String) -> bool:
	# 0.31.134: gold the server takes from an account (server/clans.gd: starting a clan costs Clans.COST_GOLD)
	var e := _load(id)
	if e.is_empty():
		return false
	var p = e.p
	p.refresh()
	p.replaying = true
	var r: Dictionary = p.pay_gold(amount, why)
	p.replaying = false
	if not bool(r.get("ok", false)):
		return false
	e.meta.rev = int(e.meta.get("rev", 0)) + 1
	_save_meta(e)
	log_fn.call("account %s paid %d gold (%s)" % [id, amount, why])
	return true

func grant_referral(id: String, kind: String, name: String) -> bool:
	# 0.31.120: a referral's Gold chest (server/referrals.gd)
	var e := _load(id)
	if e.is_empty():
		return false
	var p = e.p
	p.refresh()
	p.replaying = true
	p.grant_referral(kind, name)
	p.replaying = false
	e.meta.rev = int(e.meta.get("rev", 0)) + 1
	_save_meta(e)
	return true

func grant_purchase(id: String, key: String, product: String, token: String, consumed := false) -> Dictionary:
	# a purchase Google confirmed: granted to this account once; a token granted to another account never again.
	# consumed: Google says the gem pack was used up already -- only "already yours" if this account got it
	var e := open(id, key)
	if e.is_empty():
		return {"ok":false, "why":"auth"}
	var h := token_hash(token)
	var owner := str(tokens.get(h, ""))
	if owner != "" and owner != id:
		log_fn.call("purchase %s: token already granted to account %s, refused for %s" % [product, owner, id])
		return {"ok":false, "why":"used"}
	if consumed and owner != id:
		return {"ok":false, "why":"used"}
	var p = e.p
	var g: Dictionary = p.grant_iap(product, token)
	tokens[h] = id
	_save_tokens()
	e.meta.rev = int(e.meta.get("rev", 0)) + 1
	_save_meta(e)
	g["profile"] = public_profile(p.d)
	return g

func wear(id: String, key: String) -> Dictionary:
	# what an account may show online: its own name, title (owned) and looks (the outfits it owns and wears); the
	# 5v5 heroes it bought (0.31.170: a hero it picks for an online match must be one of them, or free)
	var e := open(id, key)
	if e.is_empty():
		return {}
	var p = e.p
	var t := str(p.d.get("title", ""))
	return {"name":str(p.d.get("name", "Player")), "title":t if p.owns(t) and Net.TITLES.has(t) else "",
		"looks":Net.clean_looks(p.wire_looks()), "heroes":(p.d.get("heroes", []) as Array).duplicate()}   # (0.31.170: bought ones)

func stats_of(id: String) -> Dictionary:
	# 0.31.120 (Kevin: player profile card): what anyone may see of an account when they tap its name -- its level and
	# lifetime numbers, the class it plays most (stats.main_<cls>: matches with it as the match's main class) and the
	# outfit it wears on that hero ("sk"; 0.31.188 -- it was the weapon it won most with). No currencies or purchases.
	var e := _load(id)
	if e.is_empty():
		return {}
	var d: Dictionary = e.p.d
	var st: Dictionary = d.get("stats", {})
	var fav := ""
	var fav_n := 0
	for k in st:
		if str(k).begins_with("main_") and int(st[k]) > fav_n:
			fav = str(k).substr(5)
			fav_n = int(st[k])
	var out := {"lv":int(d.get("level", 1)), "m":int(st.get("matches", 0)), "w":int(st.get("wins", 0)), "r":int(st.get("rescues", 0)),
		"ko":int(st.get("kills", 0)), "bs":int(st.get("best_streak", 0)), "since":int(e.meta.get("created", 0)),
		"cls":fav, "cm":fav_n, "cw":int(st.get("win_" + fav, 0)) if fav != "" else 0,
		"tw":int(st.get("towers", 0))}             # (0.31.169: towers for the card's RESCUES tile; "r" stays for older apps)
	var worn := str((d.get("skin_on", {}) as Dictionary).get(fav, "")) if d.get("skin_on") is Dictionary else ""
	if worn != "" and Eco.SKINS.has(worn):
		out["sk"] = worn
	return out

func public_of(id: String) -> Dictionary:
	# 0.31.111: what other players see of an account in chat and friends lists -- its name and title (owned only).
	# No key: the social socket checked it when it opened.
	var e := _load(id)
	if e.is_empty():
		return {}
	var p = e.p
	var t := str(p.d.get("title", ""))
	return {"name":str(p.d.get("name", "Player")), "title":t if p.owns(t) and Net.TITLES.has(t) else ""}

# ---------------- 0.31.132: the account between phones (the iOS port) ----------------
func add_key(e: Dictionary) -> String:
	# a key for another phone of this account (its hash kept; the oldest dropped past MAX_KEYS); the first key stays
	var key := Crypto.new().generate_random_bytes(32).hex_encode()
	var ks: Array = (e.meta.get("keys", []) as Array).duplicate()
	ks.append(key.sha256_text())
	while ks.size() > MAX_KEYS:
		ks.pop_front()
	e.meta["keys"] = ks
	_save_meta(e)
	return key

static func clean_code(s: String) -> String:
	var out := ""
	for ch in s.to_upper():
		if LINK_CHARS.contains(ch):
			out += ch
	return out

func _link_sweep(t: int) -> void:
	for c in links.keys():
		if int(links[c].until) <= t:
			links.erase(c)

func link_new(id: String, key: String) -> Dictionary:
	# Settings > MOVE TO ANOTHER PHONE: a code the other phone enters (Android and iPhone alike)
	var e := open(id, key)
	if e.is_empty():
		return {"t":"eco", "ok":false, "op":"link_new", "why":"auth"}
	var t := now()
	_link_sweep(t)
	var made: Array = (link_made.get(id, []) as Array).filter(func(x): return t - int(x) < 3600)
	if made.size() >= LINK_PER_HOUR:
		return {"t":"eco", "ok":false, "op":"link_new", "why":"busy"}
	for c in links.keys():
		if str(links[c].id) == id:
			links.erase(c)                           # one live code per account
	var cr := Crypto.new()
	var code := ""
	while code == "" or links.has(code):
		code = ""
		var b := cr.generate_random_bytes(LINK_LEN)
		for i in LINK_LEN:
			code += LINK_CHARS[b[i] % LINK_CHARS.length()]
	links[code] = {"id":id, "until":t + LINK_LIFE}
	made.append(t)
	link_made[id] = made
	log_fn.call("account %s: a transfer code made" % id)
	return {"t":"eco", "ok":true, "op":"link_new", "code":code, "ttl":LINK_LIFE}

func link_use(code: String, addr: String) -> Dictionary:
	# the other phone's ENTER A CODE: the account, with a key of its own for that phone (the first phone keeps its own)
	var t := now()
	_link_sweep(t)
	link_tries_all = link_tries_all.filter(func(x): return t - int(x) < LINK_TRY_WINDOW)
	var mine: Array = (link_tries.get(addr, []) as Array).filter(func(x): return t - int(x) < LINK_TRY_WINDOW)
	if mine.size() >= LINK_TRIES or link_tries_all.size() >= LINK_TRIES_ALL:
		return {"t":"eco", "ok":false, "op":"link_use", "why":"busy"}
	var c := clean_code(code)
	var e := {}
	if links.has(c):
		e = _load(str(links[c].id))
		links.erase(c)                               # once
	if e.is_empty():
		mine.append(t)
		link_tries[addr] = mine
		link_tries_all.append(t)
		return {"t":"eco", "ok":false, "op":"link_use", "why":"code"}
	var key := add_key(e)
	log_fn.call("account %s: taken to another phone with a transfer code" % str(e.id))
	return {"t":"eco", "ok":true, "op":"link_use", "acct":str(e.id), "key":key, "seq":int(e.meta.get("seq", 0)),
		"now":now(), "profile":public_profile(e.p.d)}

static func gc_hash(team_player_id: String) -> String:
	return ("fatebound-gc:" + team_player_id).sha256_text()

func _save_gc() -> void:
	_write(gc_path, JSON.stringify(gc_links))

func gc_link(id: String, key: String, team_player_id: String, relink := false) -> Dictionary:
	# a Game Center player (its identity already checked with Apple's signature): linked to this phone's account, or --
	# when it belongs to another account -- that account, with a key for this phone, for the player to choose (a fresh
	# install simply takes it, like Google Play's copy). relink: the player kept this phone's account.
	if team_player_id == "":
		return {"t":"eco", "ok":false, "op":"gc", "why":"bad"}
	var h := gc_hash(team_player_id)
	var owner := str(gc_links.get(h, ""))
	if owner != "" and _load(owner).is_empty():
		owner = ""                                   # (that account was deleted)
	var e := open(id, key) if id != "" else {}
	if not e.is_empty() and (owner == "" or owner == id or relink):
		var was := owner
		gc_links[h] = id
		_save_gc()
		if was != id:
			log_fn.call("account %s: Game Center player linked%s" % [id, " (moved from %s)" % was if was != "" else ""])
		return {"t":"eco", "ok":true, "op":"gc", "gc":"same" if was == id else "linked"}
	if owner == "":
		return {"t":"eco", "ok":true, "op":"gc", "gc":"none"}
	var o := _load(owner)
	var key2 := add_key(o)
	log_fn.call("account %s: found again through Game Center%s" % [owner, " (asked by %s)" % id if id != "" else ""])
	return {"t":"eco", "ok":true, "op":"gc", "gc":"other", "acct":owner, "key":key2, "seq":int(o.meta.get("seq", 0)),
		"sum":o.p.summary(), "now":now(), "profile":public_profile(o.p.d)}

func delete_account(id: String, key: String) -> Dictionary:
	# Settings > DELETE ACCOUNT (App Store rule 5.1.1(v); Google Play's data deletion too): the account's files, its
	# Game Center link and its codes go. Purchase tokens keep pointing at the (now empty) id, so a purchase can't be
	# granted again to anyone.
	var e := open(id, key)
	if e.is_empty():
		return {"t":"eco", "ok":false, "op":"delete", "why":"auth"}
	cache.erase(id)
	for f in [id + ".json", id + ".meta.json", id + ".json.tmp", id + ".meta.json.tmp"]:
		var path := dir.path_join(f)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var gone := false
	for h in gc_links.keys():
		if str(gc_links[h]) == id:
			gc_links.erase(h)
			gone = true
	if gone:
		_save_gc()
	for c in links.keys():
		if str(links[c].id) == id:
			links.erase(c)
	link_made.erase(id)
	log_fn.call("account %s deleted by its player" % id)
	return {"t":"eco", "ok":true, "op":"delete"}
