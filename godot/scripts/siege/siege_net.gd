extends RefCounted
# Fatebound's online protocol, shared by the headless server (server/siege_server.gd) and the phone (siege_mode.gd).
# The server runs the real sim; clients keep a mirror sim (the same map and heroes from setup() + setup_moba()) brought to
# each snapshot, so the view and HUD draw an online match as they draw one against bots. (0.31.170: the online 5v5 --
# its minions, monsters and summons come and go, its heroes level, shop and cast; snapshot() below. The protocol number
# stays 35: the economy, the leaderboard and the version check send it too and a bump would force every app to update;
# a 5v5 app says so in its hello ("five":1) and a 5v5 server in its answers, and the server refuses a match to an app
# without it as too old -- the Update screen.)
#
# Transport: WebSocket binary frames, each one var_to_bytes(Dictionary). Never bytes_to_var with
# objects: decode() uses the default allow_objects=false.
const Sim = preload("res://scripts/siege/siege_sim.gd")

const VERSION := 36              # 36 = the Honor of Kings map (0.31.216: the square, corner keeps, gates at -135/-90/-45 degrees); 35 = the "block" action (the Crusader's shield, 0.31.61); 34 = the Sniper's piercing shot (PROJ_KINDS); 33 = the player launcher (state "fly", "la"); 32 = one snapshot for all + "m" task messages, timed interpolation; 31 = the bomb (bm); 30 = smaller snapshots: packed projectiles/items/Kings, slow state only when it changes (0.31.8); 29 = no class caps; per-class stand stock/restock, no heal stacking, armory +8 %, worker 80 hp; 28 = class caps; 27 = the Necromancer (drain + heal beams, unit field 32); 26 = Resurrection, bigger nova/sanctuary; 25 = logs/rocks (it); 24 = the Crusader and its thrown hammer; 23 = tower shot heights, run off a deck; 22 = wide roofless towers; 21 = natural hills, every class climbs; 20 = bigger towers; 19 = the bigger natural map; 18 = no "water" in the dungeons (wading only in the river); 17 = rampart shots
const DEFAULT_URL := "wss://136-113-125-3.sslip.io/fatebound/siege/ws"
# Refusals: the server sends {"t":"bye", "why":..., "need":VERSION} and then closes with one of these codes.
# Since 0.31.73 the version refusal's close reason is "version:<server protocol>" (older servers: just "version").
const CLOSE_NO_HELLO := 4000
const CLOSE_VERSION := 4001
const CLOSE_FULL := 4002
const DEFAULT_PORT := 8082
const SNAP_HZ := 20.0            # 15 -> 20 (0.31.23); 10 -> 15 (0.18.4)
const PROJ_HIST := 6                # 0.31.207: a projectile's positions kept (300 ms at 20 Hz: past the render delay)
const INTERP_DELAY := 1.5 / SNAP_HZ   # 0.31.23: remote units are drawn this far behind the newest snapshot (75 ms)
const HIST := 4
# 0.31.170: the 5v5's shots too (a kind + 16 = a big one, the Ranger's DEADEYE)
const PROJ_KINDS := ["arrow", "fire", "hammer", "pierce", "bolt", "ball", "thorn", "boulder"]
const PREDICT_SNAP := 2.5        # m: a predicting phone snaps to the server beyond this
const PREDICT_SOFT := 0.7        # m: beyond this it is eased back toward the server's position (0.31.24)
const MAX_PACKET := 64 * 1024            # client -> server; anything larger is dropped
const TEAM_SIZE := 5               # (0.31.169: the 5v5's; 16 a side in Siege)
# 0.31.111 (Kevin: "add the quick chat pings"): the in-match quick chat. {"t":"qc", "i": index} from a player; the
# server sends {"t":"qc", "u": unit, "i"} to their side ("all": to both sides). Additive: an older server ignores it,
# an older app never sends it.
const QUICK_CHAT := [
	{"x":"Attack!", "c":"#ff8a5c"},
	{"x":"Defend the gate!", "c":"#7ec8ff"},
	{"x":"Get our King!", "c":"#ffd65a"},
	{"x":"Take the tower!", "c":"#ff6a6a"},          # (0.31.170: "Stop the carrier!" went with Siege)
	{"x":"Need help!", "c":"#ff6a6a"},
	{"x":"Follow me!", "c":"#9dff8a"},
	{"x":"Thanks!", "c":"#e6e6e6"},
	{"x":"Good game!", "c":"#e6c2ff", "all":true},
]
const QC_GAP := 2.0              # s between one player's quick chats

const STATES := ["idle", "move", "wind", "recover", "dodge", "dead", "dash"]
# Actions a client may ask for (anything else is ignored by the server), and what each takes (clean_arg). 0.31.170: the
# 5v5's -- a level-up pick, the ultimate, W and E, a ward, the shop.
const ACTIONS := ["attack", "ability", "block", "dodge", "pick", "ult", "spell", "ward", "shop_buy", "shop_sell", "recall"]
const FIVE := 1                  # 0.31.170: the online 5v5 (the hello's "five", the server's answers' "five")

static func clean_arg(action: String, arg: Variant) -> Array:
	# -> [ok, the argument as the sim takes it] for an action from a phone
	match action:
		"pick":
			return [true, int(arg)] if (arg is int or arg is float) and int(arg) >= 0 and int(arg) <= 2 else [false, null]
		"spell":
			return [true, str(arg)] if arg is String and str(arg) in ["w", "e"] else [false, null]
		"shop_buy":
			return [true, str(arg)] if arg is String and str(arg).length() <= 24 and _word(str(arg), true) else [false, null]
		"shop_sell":
			return [true, int(arg)] if (arg is int or arg is float) and int(arg) >= 0 and int(arg) < 8 else [false, null]
	return [ACTIONS.has(action), null]

# ---------------- version mismatch (0.31.73: the "Update required" screen) ----------------
# What the client should do about the server's protocol `server_v`, compared with ours (VERSION):
#   "update"     the server is newer: this build is too old -> the blocking Update screen
#   "server_old" the server is older: a new build went out before the server was redeployed -> "Servers are updating"
#   "ok"         same protocol
#   "unknown"    no answer (offline, or a server too old to answer the version check)
# Nothing here hard-codes a protocol number, so every future bump of VERSION works the same way.
# ---------------- titles (0.31.87) ----------------
# Kevin: "make it so their titles show (use correct punctuation when putting the titles on the name)" and "players have
# to earn the titles". Every title the game has: id -> [text, form, rarity]. The form says how it joins a name:
#   "the"    an epithet, no comma           Midblade the Gatebreaker   (as "Alexander the Great")
#   "of"     an "of" phrase, no comma       Midblade of Many Hats
#   "prefix" a rank in front, no comma      Squire Midblade            (as "Sir Lancelot")
#   "office" an office after it, a comma    Midblade, Siege Lord       (as "Arthur, King of the Britons")
# Here (not in the economy) because the server builds the over-head text from it too: a hello names a title id, never
# free text. How each is earned: scripts/meta/economy.gd TITLE_GOALS.
# 0.31.90 in-app purchases (Kevin: "I want to incorporate IAP"). Google Play only, in the Play app; the server checks
# each purchase with Google before the phone grants it (server/iap_verify.gd). The IDs are permanent in Play Console
# (godot/PLAY_IAP_HANDOFF.md): never rename one. "once": acknowledged, never consumed, so Google sells it once.
const IAP_PACKAGE := "com.fatebound.game"
const IAP := {
	"gems_80":      {"gems":80,   "usd":"0.99"},
	"gems_500":     {"gems":500,  "usd":"4.99"},
	"gems_1100":    {"gems":1100, "usd":"9.99", "tag":"A SIEGE PASS"},
	"gems_2400":    {"gems":2400, "usd":"19.99"},
	"gems_6500":    {"gems":6500, "usd":"49.99", "tag":"BEST VALUE"},
	# 0.31.108 (the economy review): a $99.99 pack. "play_only": shown only once Google Play returns its price (the
	# product has to be created in Play Console first, PLAY_IAP_HANDOFF.md); it then takes BEST VALUE from gems_6500.
	"gems_14000":   {"gems":14000, "usd":"99.99", "tag":"BEST VALUE", "play_only":true},
	# 0.31.108: 300 gems + 150 Embers + a rare -> 500 + 300 + an epic (about 2.6x its price; was 1.5x). 0.31.184 (no more
	# Embers): 500 gems + 3,000 gold + an epic -- the 300 Embers at economy.gd EMBER_GOLD. 0.31.188 (no more weapons): a
	# Hero Token for the epic -- any locked hero (the product ID, type and price stay; its store text is Kevin's to change)
	"starter_pack": {"gems":500,  "gold":3000, "token":1, "once":true, "usd":"2.99"},
}

const TITLES := {
	# --- for everyone
	"title_squire":         ["Squire", "prefix", "common"],
	"title_victor":         ["the Victor", "the", "common"],
	"title_brawler":        ["the Brawler", "the", "common"],
	"title_woodcutter":     ["the Woodcutter", "the", "common"],
	"title_fishmonger":     ["the Fishmonger", "the", "common"],
	"title_gatebreaker":    ["the Gatebreaker", "the", "rare"],
	"title_kingbearer":     ["Kingbearer", "office", "rare"],
	"title_many_hats":      ["of Many Hats", "of", "rare"],
	"title_tempest":        ["the Tempest", "the", "epic"],
	"title_relentless":     ["the Relentless", "the", "epic"],
	"title_cake_baron":     ["Fish Baron", "office", "epic"],
	"title_siege_lord":     ["Siege Lord", "office", "epic"],
	"title_oracle_sworn":   ["the Kingsworn", "the", "legendary"],
	"title_unstoppable":    ["the Unstoppable", "the", "legendary"],
	"title_undefeated":     ["the Undefeated", "the", "legendary"],
	"title_legend":         ["the Legend", "the", "legendary"],
	# --- per class (each upgrade counts as its class)
	"title_sir":            ["Sir", "prefix", "rare"],
	"title_shieldwall":     ["the Shieldwall", "the", "epic"],
	"title_hammer_realm":   ["Hammer of the Realm", "office", "legendary"],
	"title_wild":           ["the Wild", "the", "rare"],
	"title_whirlwind":      ["the Whirlwind", "the", "epic"],
	"title_unchained":      ["the Unchained", "the", "legendary"],
	"title_sly":            ["the Sly", "the", "rare"],
	"title_shadows":        ["of the Shadows", "of", "epic"],
	"title_knives":         ["Master of Knives", "office", "legendary"],
	"title_keen_eyed":      ["the Keen-Eyed", "the", "rare"],
	"title_deadeye":        ["the Deadeye", "the", "epic"],
	"title_warden":         ["Warden of the Wilds", "office", "legendary"],
	"title_apprentice":     ["Apprentice", "prefix", "rare"],
	"title_stormcaller":    ["the Stormcaller", "the", "epic"],
	"title_starborn":       ["the Starborn", "the", "legendary"],
	"title_acolyte":        ["Acolyte", "prefix", "rare"],
	"title_merciful":       ["the Merciful", "the", "epic"],
	"title_lightbringer":   ["the Lightbringer", "the", "legendary"],
	"title_foreman":        ["Foreman", "prefix", "rare"],
	"title_mason":          ["the Mason", "the", "epic"],
	"title_master_builder": ["Master Builder", "office", "legendary"],
	# --- 0.31.120: the weekly leaderboard's
	"title_champion":       ["Champion", "prefix", "legendary"],
	"title_contender":      ["the Contender", "the", "epic"],
	"title_top_ten":        ["of the Ten", "of", "rare"],
}

static func title_parts(name: String, title_id: String) -> Array:
	# The name with its title, in reading order: [[text, is_title], ...] (the punctuation is part of the name's side).
	var t: Array = TITLES.get(title_id, [])
	if t.is_empty():
		return [[name, false]]
	match str(t[1]):
		"prefix": return [[str(t[0]), true], [" " + name, false]]
		"office": return [[name + ",", false], [" " + str(t[0]), true]]     # (spaces lead a part: measured widths keep them)
		_: return [[name, false], [" " + str(t[0]), true]]

static func title_text(name: String, title_id: String) -> String:
	var s := ""
	for p in title_parts(name, title_id):
		s += str(p[0])
	return s

static func title_rarity(title_id: String) -> String:
	var t: Array = TITLES.get(title_id, [])
	return str(t[2]) if not t.is_empty() else ""

# ---------------- what the players wear (0.31.101) ----------------
# Kevin: "I want players to see everything the other players are wearing". A hello may carry "lk": what the player wears
# (Profile.wire_looks); the server keeps only well-formed entries (clean_looks) and sends them in "pn" as "lk": {unit id:
# looks}, as it does names and titles. 0.31.188 (Kevin: "I only want the cosmetics to be an entire outfit"): the outfits
# worn, "_sk", are all there is -- the weapons' "<class>": "weapon id|stars|element" entries (0.31.101-0.31.187) are
# dropped (an older app still sending them: left out). Additive: an older server ignores "lk", an older app ignores "_sk".
static func clean_looks(v: Variant) -> Dictionary:
	var out := {}
	if not (v is Dictionary):
		return out
	if v.get("_sk") is String:
		var sk := clean_skins(v["_sk"])
		if sk != "":
			out["_sk"] = sk
	return out

# 0.31.186: the hero skins worn, "_sk": "knight_frost,golem_frost" -- ids of a-z 0-9 _, at most SKINS_MAX (each app
# shows the one for the hero being played, from its own catalog; an id it doesn't know: the hero's own look)
const SKINS_MAX := 24

static func clean_skins(s: String) -> String:
	if s.length() > 600:
		return ""
	var keep := []
	for id in s.split(","):
		if id != "" and id.length() <= 40 and _word(id, true) and not keep.has(id) and keep.size() < SKINS_MAX:
			keep.append(id)
	return ",".join(keep)

static func _word(s: String, digits: bool) -> bool:
	for ch in s:
		var c := ch.unicode_at(0)
		if not ((c >= 97 and c <= 122) or c == 95 or (digits and c >= 48 and c <= 57)):
			return false
	return true

# App builds ("0.31.209-fatebound"; server 0.31.84-minbuild's minimum app build). 0.31.209: here rather than in the
# server, so the app checks the server's minimum ("ver" says "min_build") at launch, before any match.
static func parse_build(b: String) -> Array:
	var head := b.strip_edges().split("-", true, 1)[0] if b.strip_edges() != "" else ""
	if head == "":
		return []
	var out := []
	for part in head.split("."):
		if not part.is_valid_int():
			return []
		out.append(part.to_int())
	return out

# -1 a < b, 0 equal, 1 a > b (missing parts count as 0: 0.31 == 0.31.0).
static func compare_builds(a: Array, b: Array) -> int:
	for i in maxi(a.size(), b.size()):
		var x: int = a[i] if i < a.size() else 0
		var y: int = b[i] if i < b.size() else 0
		if x != y:
			return -1 if x < y else 1
	return 0

# True only when both are readable and `build` is older than `minimum`. Unknown builds and "no minimum" pass.
static func build_too_old(build: String, minimum: String) -> bool:
	var m := parse_build(minimum)
	var b := parse_build(build)
	if m.is_empty() or b.is_empty():
		return false
	return compare_builds(b, m) < 0

static func version_verdict(server_v: int, client_v: int = VERSION) -> String:
	if server_v < 0:
		return "unknown"
	if server_v > client_v:
		return "update"
	if server_v < client_v:
		return "server_old"
	return "ok"

# The server's protocol from a refusal: the bye's "need" if it arrived, else the close reason "version:<n>".
# -1 = not a version refusal. A version refusal (code 4001 / bye "version") without any number comes from a server
# that predates 0.31.73 -- i.e. older than any build carrying this code -- so it maps to "server older" (0).
static func refused_version(bye: Dictionary, close_code: int, close_reason: String) -> int:
	if str(bye.get("why", "")) == "version" and bye.has("need"):
		return maxi(0, int(bye.get("need", 0)))
	if close_reason.begins_with("version:") and close_reason.substr(8).is_valid_int():
		return maxi(0, close_reason.substr(8).to_int())
	if close_code == CLOSE_VERSION or str(bye.get("why", "")) == "version" or close_reason == "version":
		return 0
	return -1

# Wire format: 1 byte tag + payload. "R" = var_to_bytes, "Z" = zstd(var_to_bytes) with the raw
# size in 4 bytes. Snapshots are compressed; small client messages go raw.
static func encode(msg: Dictionary, compress := false) -> PackedByteArray:
	var raw := var_to_bytes(msg)
	var out := PackedByteArray()
	if compress:
		var z := raw.compress(FileAccess.COMPRESSION_ZSTD)
		out.resize(5)
		out[0] = 0x5A
		out.encode_u32(1, raw.size())
		out.append_array(z)
		return out
	out.append(0x52)
	out.append_array(raw)
	return out

static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 2 or bytes.size() > MAX_PACKET * 16:
		return {}
	var raw := PackedByteArray()
	if bytes[0] == 0x5A and bytes.size() > 5:
		var n := bytes.decode_u32(1)
		if n <= 0 or n > MAX_PACKET * 64:
			return {}
		raw = bytes.slice(5).decompress(n, FileAccess.COMPRESSION_ZSTD)
	elif bytes[0] == 0x52:
		raw = bytes.slice(1)
	else:
		return {}
	var v: Variant = bytes_to_var(raw)
	return v if v is Dictionary else {}

static func _s16(arr: PackedByteArray, i: int, v: float) -> void:
	arr.encode_s16(i * 2, _i16(v))

static func _i16(v: float) -> int:
	return clampi(int(round(v)), -32768, 32767)

static func _wrap16(v: int) -> int:
	# a 16-bit difference (the phone adds it back the same way: exact whatever the values)
	return ((v + 32768) & 0xFFFF) - 32768

# ---------------- server side ----------------
# 0.31.170 (the online 5v5): one snapshot for every player, 20 a second. What changes all the time goes in full each
# time, packed; everything else only when it changed since the last snapshot (each player's socket delivers every one,
# in order, so a change sent once is never lost; a player seated, back from a drop, or whose socket couldn't take a
# snapshot gets a KEYFRAME -- the lot -- first):
#   "ids"  the units' ids, in the order of "u" (only when a unit came or went; the 5v5's minions, monsters and summons
#          come and go all match long)
#   "u"    per unit, FAST 16-bit values: health, x, z (1 cm), facing (0.001 rad), state, stun and ability recharge
#          (0.01 s)
#   "ho"/"h"  the heroes' ids (once) and per hero HERO_FAST: gold and the W, E, ultimate and ward recharges
#   "ud"   {unit id: {key: value}}: every other key of a unit that changed (its hero, level, items, buffs, the shield
#          and the times its effects end -- absolute match times, so the phone needs no clock of its own) but NO_SYNC
#   "ux"   {unit id: [keys]}: keys a unit lost (an effect that ended)
#   "o"    {"tw:3": {key: value}}: the towers', Kings', gates' and camps' changes (OBJ_SKIP: what never changes)
#   "zn" "tr" "wd" "ws" "ek"  the spells' zones and traps, the wards, the Wyrm's stacks, each side's epic monsters
#          slain (0.31.176): in full when they changed
#   "p"    the projectiles, 6 x 16 bits each (id, x, z, vx, vz, kind + 16 if big)
#   "e"    the match's events since the last snapshot (the view's and the HUD's effects, sounds, toasts)
const FAST := 7
const HERO_FAST := ["gold", "cd_w", "cd_e", "ult_cd", "ward_ch"]
const HERO_FAST_SCALE := [1.0, 100.0, 100.0, 100.0, 100.0]
# Never sent: the server's own bookkeeping (paths, the bots' thinking and targets, who hit whom for assists, the
# multi-kill window, the camps' monsters' homes) and clocks that tick all the time and the phone never reads.
const NO_SYNC := {"t":true, "move":true, "path":true, "path_i":true, "path_goal":true, "path_at":true, "path_ver":true,
	"think_at":true, "unstick":true, "unstick_dir":true, "stuck_t":true, "last_pos":true, "aim_d":true, "drain_acc":true,
	"hit_log":true, "hh_at":true, "hh_by":true, "hurt_at":true, "hurt_by":true, "mt":true, "mt_pri":true, "mt_tw":true,
	"wp":true, "home":true, "home_face":true, "healed":true, "mk_n":true, "mk_t":true, "beam_heal_t":true,
	"combo_t":true, "dodge_dir":true, "lunge_hit":true, "whirl_t":true, "net_driven":true, "id":true,
	"cc_log":true, "heal_log":true}
const FAST_KEYS := {"hp":true, "pos":true, "face":true, "state":true, "stun":true, "cd_ability":true,
	"gold":true, "cd_w":true, "cd_e":true, "ult_cd":true, "ward_ch":true}
const OBJ_SKIP := {
	"tw": {"id":true, "team":true, "lane":true, "tier":true, "p":true},
	"kg": {"quiet":true},
	"gt": {"id":true, "team":true, "a":true, "b":true, "c":true, "side":true, "lane":true, "in":true, "r":true},
	"cp": {"id":true, "kind":true, "side":true, "p":true, "patience":true, "hits":true},
}

static func _objs(sim) -> Array:
	# [prefix, the list] for the "o" channel
	var out := [["gt", sim.gates]]
	if sim.moba != null:
		out.append_array([["tw", sim.moba.towers], ["kg", sim.moba.kings], ["cp", sim.moba.camps]])
	return out

static func _blobs(sim) -> Dictionary:
	# the slow lists, as sent
	if sim.moba == null:
		return {}
	var zn := []
	for z in sim.moba.kits.zones:
		var c: Dictionary = z.duplicate()
		c.erase("next")                                 # (its next tick: the server's)
		zn.append(c)
	return {"zn":zn, "tr":sim.moba.kits.traps, "wd":sim.moba.vision.wards, "ws":sim.moba.wyrm_stacks, "ek":sim.moba.epic_kills}

static func _diff(sync: Dictionary, key: String, d: Dictionary, skip: Dictionary, changed: Dictionary, erased: Dictionary) -> void:
	# d's keys (but skip) that differ from what was last sent for `key` -> changed[key]; keys it lost -> erased[key]
	var cache: Dictionary = sync.c
	var c: Dictionary = cache.get(key, {})
	if not cache.has(key):
		cache[key] = c
	# Its keys are listed again when it gained or lost one: its size changed, or a listed key went. (A skipped or NO_SYNC
	# key never comes and goes on a unit -- else one leaving as another arrives would hide the new one.)
	var kl: Array = sync.kl.get(key, [])
	var rebuild: bool = d.size() != int(sync.ksz.get(key, -1))
	if not rebuild:
		for k in kl:
			if not d.has(k):
				rebuild = true
				break
	if rebuild:
		kl = []
		for k in d:
			if not skip.has(k) and not NO_SYNC.has(k):
				kl.append(k)
		sync.kl[key] = kl
		sync.ksz[key] = d.size()
		var gone := []
		for k in c.keys():
			if not d.has(k):
				c.erase(k)
				gone.append(k)
		if not gone.is_empty():
			erased[key] = gone
	var ch := {}
	for k in kl:
		var v: Variant = d[k]
		var cv: Variant = c.get(k)                       # (null: never sent -- no key of a unit is ever null)
		if cv == null or typeof(cv) != typeof(v) or cv != v:
			var sv: Variant = v.duplicate(true) if (v is Array or v is Dictionary) else v
			c[k] = sv
			ch[k] = sv
	if not ch.is_empty():
		changed[key] = ch

static func _sync_of(sim) -> Dictionary:
	var sync: Dictionary = sim.net_sync
	if not sync.has("c"):
		sync.merge({"c":{}, "kl":{}, "ksz":{}, "ids":PackedStringArray(), "ho":PackedStringArray(), "blob":{}, "last":{}})
	return sync

static func snapshot(sim, _for_unit: String, events: Array) -> Dictionary:
	# The next snapshot for everyone in the match (_for_unit: kept for the callers; nothing in it is private).
	var sync := _sync_of(sim)
	var msg := {"t":"s", "tm":sim.time, "sc":sim.score.duplicate(), "k":sim.kills.duplicate(),
		"end":[sim.ended, sim.winner, sim.end_reason], "e":events}
	var ids := PackedStringArray()
	var n: int = sim.units.size()
	var abs_i := PackedInt32Array()                    # the values themselves (a keyframe's)
	abs_i.resize(n * FAST)
	var fast := PackedByteArray()                      # what's sent: each value less the last snapshot's (mostly 0)
	fast.resize(n * FAST * 2)
	var prev_ids: PackedStringArray = sync.ids
	var prev_i: PackedInt32Array = sync.get("abs_i", PackedInt32Array())
	var prev_at := {}
	var ud := {}
	var ux := {}
	var i := 0
	for u in sim.units:
		var id := str(u.id)
		ids.append(id)
		var b := i * FAST
		var hp := float(u.hp)
		var p: Vector2 = u.pos
		abs_i[b] = clampi(int(ceilf(hp)), 0, 32767) if hp > 0.0 else 0
		abs_i[b + 1] = clampi(int(round(p.x * 100.0)), -32768, 32767)
		abs_i[b + 2] = clampi(int(round(p.y * 100.0)), -32768, 32767)
		abs_i[b + 3] = clampi(int(round(wrapf(float(u.face), -PI, PI) * 1000.0)), -32768, 32767)
		abs_i[b + 4] = maxi(0, STATES.find(str(u.state)))
		abs_i[b + 5] = clampi(int(round(float(u.stun) * 100.0)), -32768, 32767)
		abs_i[b + 6] = clampi(int(round(float(u.cd_ability) * 100.0)), -32768, 32767)
		var j := i if i < prev_ids.size() and prev_ids[i] == id else -1
		if j < 0 and not prev_ids.is_empty():
			if prev_at.is_empty():
				for pi in prev_ids.size():
					prev_at[prev_ids[pi]] = pi
			j = int(prev_at.get(id, -1))
		if j >= 0:
			var pb := j * FAST
			for k in FAST:
				fast.encode_s16((b + k) * 2, ((abs_i[b + k] - prev_i[pb + k] + 32768) & 0xFFFF) - 32768)
		else:
			for k in FAST:
				fast.encode_s16((b + k) * 2, abs_i[b + k])
		_diff(sync, id, u, FAST_KEYS, ud, ux)
		i += 1
	if ids != sync.ids:
		# units came or went: their cached keys go with them
		var live := {}
		for id in ids:
			live[id] = true
		for id in (sync.ids as PackedStringArray):
			if not live.has(id):
				sync.c.erase(id)
				sync.kl.erase(id)
				sync.ksz.erase(id)
		sync.ids = ids
		msg["ids"] = ids
	sync["abs_i"] = abs_i
	msg["u"] = fast
	# the heroes' gold and recharges (each less the last snapshot's too)
	var ho := PackedStringArray()
	var abs_h := PackedInt32Array()
	var hf := PackedByteArray()
	if sim.moba != null:
		for t in 2:
			for hid in sim.moba.heroes[t]:
				ho.append(str(hid))
		var hn := HERO_FAST.size()
		abs_h.resize(ho.size() * hn)
		hf.resize(abs_h.size() * 2)
		var prev_h: PackedInt32Array = sync.get("abs_h", PackedInt32Array()) if ho == sync.ho else PackedInt32Array()
		var hi := 0
		for hid in ho:
			var h: Dictionary = sim.by_id.get(hid, {})
			for k in hn:
				var at := hi * hn + k
				var v := clampi(int(round(float(h.get(HERO_FAST[k], 0.0)) * float(HERO_FAST_SCALE[k]))), -32768, 32767)
				abs_h[at] = v
				hf.encode_s16(at * 2, _wrap16(v - (prev_h[at] if at < prev_h.size() else 0)))
			hi += 1
	if ho != sync.ho:
		sync.ho = ho
		msg["ho"] = ho
	sync["abs_h"] = abs_h
	msg["h"] = hf
	if not ud.is_empty():
		msg["ud"] = ud
	if not ux.is_empty():
		msg["ux"] = ux
	# towers, Kings, gates, camps
	var od := {}
	var ox := {}
	for pair in _objs(sim):
		var pre: String = pair[0]
		var list: Array = pair[1]
		for j in list.size():
			_diff(sync, pre + ":" + str(j), list[j], OBJ_SKIP[pre], od, ox)
	if not od.is_empty():
		msg["o"] = od
	if not ox.is_empty():
		msg["ox"] = ox
	# zones, traps, wards, the Wyrm's stacks
	var blobs := _blobs(sim)
	for k in blobs:
		var v: Variant = blobs[k]
		if not sync.blob.has(k) or sync.blob[k] != v:
			var sv: Variant = v.duplicate(true)
			sync.blob[k] = sv
			msg[k] = sv
	msg["p"] = _pack_proj(sim)
	sync.last = {"tm":msg.tm, "sc":msg.sc, "k":msg.k, "end":msg.end, "p":msg.p}
	return msg

static func keyframe(sim) -> Dictionary:
	# Everything a phone needs to draw the match as of the last snapshot sent (the next one builds on it): for a player
	# just seated, back from a drop, or whose socket dropped a snapshot. Nothing sent yet: the first snapshot is one.
	var sync := _sync_of(sim)
	if (sync.last as Dictionary).is_empty():
		var first := snapshot(sim, "", [])
		first["kf"] = true
		return first
	var msg := {"t":"s", "kf":true, "e":[], "ids":sync.ids, "ho":sync.ho, "u":_bytes16(sync.abs_i), "h":_bytes16(sync.abs_h)}
	msg.merge(sync.last)
	var ud := {}
	for id in (sync.ids as PackedStringArray):
		ud[id] = sync.c.get(id, {})
	msg["ud"] = ud
	var od := {}
	for k in sync.c:
		if str(k).contains(":"):
			od[k] = sync.c[k]
	msg["o"] = od
	msg.merge(sync.blob)
	return msg

static func _bytes16(v: PackedInt32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(v.size() * 2)
	for i in v.size():
		out.encode_s16(i * 2, v[i])
	return out

static func _pack_proj(sim) -> PackedByteArray:
	# 6 x 16 bits each: id, x, z (1 cm), vx, vz (1 cm/s), kind (+16: a big one, the Ranger's DEADEYE)
	var proj := PackedByteArray()
	proj.resize(sim.projectiles.size() * 12)
	var pi := 0
	for p in sim.projectiles:
		var vals_p := [int(p.id) % 65536 - 32768, (p.pos as Vector2).x * 100.0, (p.pos as Vector2).y * 100.0, (p.vel as Vector2).x * 100.0,
			(p.vel as Vector2).y * 100.0, maxi(0, PROJ_KINDS.find(str(p.kind))) + (16 if bool(p.get("big", false)) else 0)]
		for k in 6:
			_s16(proj, pi * 6 + k, float(vals_p[k]))
		pi += 1
	return proj

# ---------------- client side ----------------
static func apply(sim, msg: Dictionary, me_id: String, predict := false) -> void:
	# Brings the mirror sim to the snapshot. Unit positions go into each unit's history (net_hist: interpolate_at draws
	# remote units between them); everything else is set directly.
	# The phone predicts its own unit: keep its position/facing (and a dodge or swing it started) unless the server
	# disagrees by > PREDICT_SNAP or the unit is in a server-driven state (0.18.4).
	var mine_prev := {}
	if predict and sim.by_id.has(me_id):
		var mp: Dictionary = sim.by_id[me_id]
		mine_prev = {"pos": mp.pos, "face": mp.face, "state": mp.state, "t": float(mp.get("t", 0.0))}
	var sync: Dictionary = sim.net_sync
	var kf := bool(msg.get("kf", false))
	sim.time = float(msg.get("tm", sim.time))
	var snap_t: float = sim.time
	sim.score = msg.get("sc", sim.score)
	sim.kills = msg.get("k", sim.kills)
	var end: Array = msg.get("end", [false, -1, ""])
	sim.ended = bool(end[0])
	sim.winner = int(end[1])
	sim.end_reason = str(end[2])
	var ud: Dictionary = msg.get("ud", {})
	# the units: new ones made, gone ones dropped, in the server's order
	if msg.has("ids"):
		var ids: PackedStringArray = msg.ids
		var keep := []
		for id in ids:
			var u: Dictionary = sim.by_id.get(id, {})
			if u.is_empty():
				var d0: Dictionary = ud.get(id, {})
				u = sim._new_unit(id, int(d0.get("team", 0)), bool(d0.get("bot", true)))
				u["net_new"] = true
				sim.by_id[id] = u
			keep.append(u)
		var live := {}
		for id in ids:
			live[id] = true
		for u in sim.units:
			if not live.has(str(u.id)):
				sim.by_id.erase(u.id)
		sim.units.clear()
		sim.units.append_array(keep)
		sync["ids"] = ids
	var ids_now: PackedStringArray = sync.get("ids", PackedStringArray())
	var hero_changed := false
	for id in ud:
		var u: Dictionary = sim.by_id.get(id, {})
		if u.is_empty():
			continue
		var d: Dictionary = ud[id]
		if kf:
			for k in u.keys():
				if not d.has(k) and not _client_key(str(k)):
					u.erase(k)                      # (a key the server's unit doesn't have: the mirror's own draft)
		for k in d:
			u[k] = d[k]
		if d.has("hid"):
			hero_changed = true
	var ux: Dictionary = msg.get("ux", {})
	for id in ux:
		var u: Dictionary = sim.by_id.get(id, {})
		for k in ux[id]:
			u.erase(k)
	if hero_changed and sim.moba != null:
		for u in sim.units:
			if u.has("hid"):
				sim.moba.hero_of[str(u.id)] = str(u.hid)
	# the fast values: each the last snapshot's plus what this one says (a keyframe's are the values themselves)
	var fast: PackedByteArray = msg.get("u", PackedByteArray())
	var n_units: int = mini(ids_now.size(), fast.size() / (FAST * 2))
	for i in n_units:
		var u: Dictionary = sim.by_id.get(ids_now[i], {})
		if u.is_empty():
			continue
		var b := i * FAST
		var nf: PackedInt32Array = u.get("net_f", PackedInt32Array())
		if kf or nf.size() != FAST:
			nf = PackedInt32Array()
			nf.resize(FAST)
		for k in FAST:
			nf[k] = _wrap16(nf[k] + fast.decode_s16((b + k) * 2))
		u["net_f"] = nf
		var was_dead: bool = u.state == "dead"
		u.hp = float(nf[0])
		var to := Vector2(float(nf[1]) / 100.0, float(nf[2]) / 100.0)
		var face := float(nf[3]) / 1000.0
		var state: String = STATES[clampi(nf[4], 0, STATES.size() - 1)]
		if bool(u.get("net_new", false)):
			u.erase("net_new")
			u.pos = to                           # (a new unit: where it is, no sliding in from the field's middle)
			u.face = face
		_push_hist(u, snap_t, to, face)
		u["net_from"] = u.pos
		u["net_to"] = to
		if was_dead != (state == "dead") or u.pos.distance_to(to) > 6.0:
			u.pos = to                           # respawn / teleport: no sliding across the map
			u["net_from"] = to
		u.face = face
		u.state = state
		u.stun = float(nf[5]) / 100.0
		u.cd_ability = float(nf[6]) / 100.0
	if msg.has("ho"):
		sync["ho"] = msg.ho
	var ho: PackedStringArray = sync.get("ho", PackedStringArray())
	var hf: PackedByteArray = msg.get("h", PackedByteArray())
	var hn := HERO_FAST.size()
	var hv: PackedInt32Array = sync.get("hv", PackedInt32Array())
	if kf or msg.has("ho") or hv.size() != ho.size() * hn:
		hv = PackedInt32Array()
		hv.resize(ho.size() * hn)
	for hi in mini(ho.size(), hf.size() / (hn * 2)):
		var h: Dictionary = sim.by_id.get(ho[hi], {})
		for k in hn:
			var at := hi * hn + k
			hv[at] = _wrap16(hv[at] + hf.decode_s16(at * 2))
			if not h.is_empty():
				h[HERO_FAST[k]] = float(hv[at]) / float(HERO_FAST_SCALE[k])
	sync["hv"] = hv
	# towers, Kings, gates, camps
	var od: Dictionary = msg.get("o", {})
	var ox: Dictionary = msg.get("ox", {})
	if not od.is_empty() or not ox.is_empty():
		var lists := {}
		for pair in _objs(sim):
			lists[pair[0]] = pair[1]
		for key in od:
			var o: Dictionary = _obj(lists, str(key))
			if o.is_empty():
				continue
			if kf:
				for k in o.keys():
					if not (od[key] as Dictionary).has(k) and not OBJ_SKIP[str(key).get_slice(":", 0)].has(k):
						o.erase(k)
			o.merge(od[key], true)
		for key in ox:
			var o2: Dictionary = _obj(lists, str(key))
			for k in ox[key]:
				o2.erase(k)
	if sim.moba != null:
		if msg.has("zn"):
			sim.moba.kits.zones = msg.zn
		if msg.has("tr"):
			sim.moba.kits.traps = msg.tr
		if msg.has("wd"):
			sim.moba.vision.wards = msg.wd
		if msg.has("ws"):
			sim.moba.wyrm_stacks = msg.ws
		if msg.has("ek"):
			sim.moba.epic_kills = msg.ek                # 0.31.176: the epic monsters each side slew (the scoreboard)
	_apply_proj(sim, msg, snap_t)
	if not mine_prev.is_empty() and sim.by_id.has(me_id):
		var me2: Dictionary = sim.by_id[me_id]
		var server_pos: Vector2 = me2.get("net_to", me2.pos)
		me2.erase("net_to")
		me2.erase("net_from")
		me2["srv_pos"] = server_pos
		var drift: float = (mine_prev.pos as Vector2).distance_to(server_pos)
		if sim.client_drivable(me2) and drift <= PREDICT_SNAP:
			# 0.31.24: past PREDICT_SOFT the server's position pulls ours back a little each snapshot, so a correction
			# is a slide rather than a 2.5 m teleport (the server's position is a round trip old, so only a little)
			me2.pos = mine_prev.pos if drift <= PREDICT_SOFT else (mine_prev.pos as Vector2).lerp(server_pos, 0.12)
			me2.face = mine_prev.face
			# A dodge or swing we started locally keeps playing until its timer runs out (the server's
			# confirmation arrives a round trip later).
			if str(mine_prev.state) in ["dodge", "wind", "recover"] and float(mine_prev.t) > 0.0:
				me2.state = mine_prev.state
				me2.t = mine_prev.t
		else:
			me2.pos = server_pos
	# the fog of war: worked out here from what the snapshot brought, as often as the server does
	if sim.moba != null and sim.moba.vision != null and (kf or snap_t - float(sync.get("vis_at", -99.0)) >= sim.moba.vision.EVERY):
		sync["vis_at"] = snap_t
		sim.moba.vision._update()

static func _client_key(k: String) -> bool:
	# a key the phone keeps on a unit whatever a keyframe says: its own (the draw history, the prediction) and the
	# keys the snapshot carries some other way or never
	return NO_SYNC.has(k) or FAST_KEYS.has(k) or k.begins_with("net_") or k == "srv_pos"

static func _obj(lists: Dictionary, key: String) -> Dictionary:
	var list: Array = lists.get(key.get_slice(":", 0), [])
	var j := key.get_slice(":", 1).to_int()
	return list[j] if j >= 0 and j < list.size() and list[j] is Dictionary else {}

static func _apply_proj(sim, msg: Dictionary, snap_t: float) -> void:
	# Projectiles slide between snapshots like units (0.18.5, Kevin: "projectiles skip across the
	# screen online"): they used to be redrawn only at each snapshot's position, so an arrow at
	# 22 m/s sat still for 66 ms and then jumped 1.5 m. Now each keeps from/to: a new one starts at
	# its spawn point (on the same one-interval-behind timeline as the units it flies between), and
	# one that ended this snapshot gets one last slide to its impact point before it disappears.
	# 0.31.207 (Kevin: "the projectiles aren't smooth when traveling"): from/to slid against the render clock, which runs
	# INTERP_DELAY (75 ms+) behind the newest snapshot -- past each snapshot's interval -- so every 50 ms it jumped half a
	# step ahead and sat still for a moment, and it vanished a snapshot before it reached what it hit. Now a projectile
	# keeps a history of its positions with their server times, as the units do (net_hist), and is drawn on the same
	# render clock (interpolate_at): between the two samples round it, past the newest along its velocity; one that
	# ended keeps flying (a ghost) to its impact point, reached when it got there, then goes. net_to stays its newest
	# position (the tests compare it with the server's).
	var old := {}
	for p in sim.projectiles:
		old[p.id] = p
	sim.projectiles.clear()
	var seen := {}
	var pb: PackedByteArray = msg.get("p", PackedByteArray())
	for pi in pb.size() / 12:
		var v := []
		for k in 6:
			v.append(pb.decode_s16((pi * 6 + k) * 2))
		var pid := int(v[0]) + 32768
		var to := Vector2(float(v[1]) / 100.0, float(v[2]) / 100.0)
		var prev: Dictionary = old.get(pid, {})
		var kc := int(v[5])
		var hist: Array = (prev.get("net_hist", []) as Array).duplicate()
		if hist.is_empty() or float(hist[-1][0]) < snap_t:
			hist.append([snap_t, to])
		while hist.size() > PROJ_HIST:
			hist.pop_front()
		var p := {"id":pid, "pos":prev.get("pos", to), "net_to":to, "net_t":snap_t, "net_hist":hist,
			"vel":Vector2(float(v[3]) / 100.0, float(v[4]) / 100.0),
			"kind":PROJ_KINDS[clampi(kc % 16, 0, PROJ_KINDS.size() - 1)], "team":-1}
		if kc >= 16:
			p["big"] = true
		sim.projectiles.append(p)
		seen[pid] = true
	var ends := {}
	for e in msg.get("e", []):
		if e is Dictionary and str(e.get("k", "")) == "proj_end" and e.has("pos"):
			ends[e.get("pid")] = e.pos
	for id in old:
		var gone: Dictionary = old[id]
		if seen.has(id):
			continue
		if bool(gone.get("ghost", false)):
			# still on its way to where it hit (the render clock is behind): kept until it gets there
			if snap_t - float(gone.get("end_t", snap_t)) < 1.0:
				sim.projectiles.append(gone)
		elif ends.has(id) and gone.has("net_hist"):
			# it hit (or ended) since the last snapshot: one last leg from its newest sample to the impact, at its speed
			var hist2: Array = (gone.net_hist as Array).duplicate()
			var last: Array = hist2[-1]
			var endp: Vector2 = ends[id]
			var speed := maxf((gone.vel as Vector2).length(), 1.0)
			var t_end := minf(float(last[0]) + (last[1] as Vector2).distance_to(endp) / speed, snap_t)
			t_end = maxf(t_end, float(last[0]) + 0.001)
			hist2.append([t_end, endp])
			var gp := {"id":id, "pos":gone.pos, "net_to":endp, "net_t":t_end, "net_hist":hist2, "vel":gone.vel, "kind":gone.kind,
				"team":-1, "ghost":true, "end_t":t_end}
			if gone.has("big"):
				gp["big"] = true
			sim.projectiles.append(gp)

static func interpolate(sim, alpha: float) -> void:
	# Called every frame between snapshots: slide unit positions from the previous snapshot to
	# the latest (alpha 0..1 across one snapshot interval).
	var a := clampf(alpha, 0.0, 1.0)
	for u in sim.units:
		if u.has("net_to"):
			u.pos = (u.net_from as Vector2).lerp(u.net_to, a)
	for p in sim.projectiles:
		if p.has("net_from"):
			p.pos = (p.net_from as Vector2).lerp(p.net_to, a)


# ---------- timed interpolation (0.31.23) ----------
# Every snapshot's positions are kept with their server time (HIST per unit). The client draws remote units at a render
# time INTERP_DELAY behind the newest snapshot, between the two samples round that time, so a late or early packet
# doesn't freeze or jump them (the old scheme slid from the last position to the newest over an estimated interval and
# stuttered with any jitter). Past the newest sample it extrapolates a little, then holds.
static func _push_hist(o: Dictionary, t: float, pos: Vector2, face: float) -> void:
	var h: Array = o.get("net_hist", [])
	if not h.is_empty() and float(h[-1][0]) >= t:
		return
	h.append([t, pos, face])
	while h.size() > HIST:
		h.pop_front()
	o["net_hist"] = h

static func interpolate_at(sim, rt: float, skip_id: String) -> void:
	for u in sim.units:
		if u.id == skip_id or not u.has("net_hist"):
			continue
		var h: Array = u.net_hist
		if h.size() < 2:
			continue
		var newest: Array = h[-1]
		if rt >= float(newest[0]):
			# a little extrapolation, then hold (a late packet shouldn't drag him to a halt)
			var prev: Array = h[-2]
			var span := maxf(float(newest[0]) - float(prev[0]), 0.001)
			var ahead := minf(rt - float(newest[0]), 0.12)
			u.pos = (newest[1] as Vector2) + ((newest[1] as Vector2) - (prev[1] as Vector2)) * (ahead / span)
			u.face = newest[2]
			continue
		for k in range(h.size() - 1, 0, -1):
			var b: Array = h[k]
			var a2: Array = h[k - 1]
			if rt >= float(a2[0]):
				var f := clampf((rt - float(a2[0])) / maxf(float(b[0]) - float(a2[0]), 0.001), 0.0, 1.0)
				if (a2[1] as Vector2).distance_to(b[1]) > 6.0:
					f = 1.0 if f > 0.5 else 0.0            # a respawn or teleport between samples: no sliding
				u.pos = (a2[1] as Vector2).lerp(b[1], f)
				u.face = lerp_angle(float(a2[2]), float(b[2]), f)
				break
	# 0.31.207: projectiles on the same render clock (see _apply_proj): before their first sample, back along their
	# velocity from it (they left the hand within the snapshot before; held there, at the hand, until then); between
	# samples, along the line; past the newest, on along their velocity (a little); a ghost gone once the clock passes
	# its impact
	var done := false
	for p in sim.projectiles:
		if not p.has("net_hist"):
			continue
		var ph: Array = p.net_hist
		if rt <= float(ph[0][0]):
			p.pos = (ph[0][1] as Vector2) - (p.vel as Vector2) * minf(float(ph[0][0]) - rt, 1.0 / SNAP_HZ)
			continue
		var pn: Array = ph[-1]
		if rt >= float(pn[0]):
			if bool(p.get("ghost", false)):
				p["done"] = true
				done = true
				p.pos = pn[1]
				continue
			p.pos = (pn[1] as Vector2) + (p.vel as Vector2) * minf(rt - float(pn[0]), 0.25)
			continue
		for k in range(ph.size() - 1, 0, -1):
			var pa: Array = ph[k - 1]
			if rt >= float(pa[0]):
				var pb2: Array = ph[k]
				var f := clampf((rt - float(pa[0])) / maxf(float(pb2[0]) - float(pa[0]), 0.001), 0.0, 1.0)
				p.pos = (pa[1] as Vector2).lerp(pb2[1], f)
				break
	if done:
		sim.projectiles = sim.projectiles.filter(func(p): return not bool(p.get("done", false)))
