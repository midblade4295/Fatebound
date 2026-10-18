extends RefCounted
# Fatebound's online protocol, shared by the headless server (server/siege_server.gd) and the phone (siege_mode.gd).
# The server runs the real sim; clients keep a mirror sim (same map from setup()) whose dynamic state is overwritten
# from snapshots, so the view and HUD render online matches unchanged. (0.31.169: Siege's state -- carrying, loads,
# tasks, items, bombs, launchers, nodes, outposts, hat stands, ladders, the Kings' carrying -- is gone from the
# snapshot with Siege; the online 5v5 adds the 5v5's. The protocol number stays: the economy and the leaderboard send it
# too, and the match rooms stay shut until the online 5v5.)
#
# Transport: WebSocket binary frames, each one var_to_bytes(Dictionary). Never bytes_to_var with
# objects: decode() uses the default allow_objects=false.
const Sim = preload("res://scripts/siege/siege_sim.gd")

const VERSION := 35              # 35 = the "block" action (the Crusader's shield, 0.31.61); 34 = the Sniper's piercing shot (PROJ_KINDS); 33 = the player launcher (state "fly", "la"); 32 = one snapshot for all + "m" task messages, timed interpolation; 31 = the bomb (bm); 30 = smaller snapshots: packed projectiles/items/Kings, slow state only when it changes (0.31.8); 29 = no class caps; per-class stand stock/restock, no heal stacking, armory +8 %, worker 80 hp; 28 = class caps; 27 = the Necromancer (drain + heal beams, unit field 32); 26 = Resurrection, bigger nova/sanctuary; 25 = logs/rocks (it); 24 = the Crusader and its thrown hammer; 23 = tower shot heights, run off a deck; 22 = wide roofless towers; 21 = natural hills, every class climbs; 20 = bigger towers; 19 = the bigger natural map; 18 = no "water" in the dungeons (wading only in the river); 17 = rampart shots
const DEFAULT_URL := "wss://136-113-125-3.sslip.io/fatebound/siege/ws"
# Refusals: the server sends {"t":"bye", "why":..., "need":VERSION} and then closes with one of these codes.
# Since 0.31.73 the version refusal's close reason is "version:<server protocol>" (older servers: just "version").
const CLOSE_NO_HELLO := 4000
const CLOSE_VERSION := 4001
const CLOSE_FULL := 4002
const DEFAULT_PORT := 8082
const SNAP_HZ := 20.0            # 15 -> 20 (0.31.23); 10 -> 15 (0.18.4)
const INTERP_DELAY := 1.5 / SNAP_HZ   # 0.31.23: remote units are drawn this far behind the newest snapshot (75 ms)
const HIST := 4
const FULL_EVERY := 15           # 0.31.8: slow-changing state (the gates) rides along only when it changed, and in full
                                 # once a second
const PROJ_KINDS := ["arrow", "fire", "hammer", "pierce"]
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
	{"x":"Stop the carrier!", "c":"#ff6a6a"},
	{"x":"Need help!", "c":"#ff6a6a"},
	{"x":"Follow me!", "c":"#9dff8a"},
	{"x":"Thanks!", "c":"#e6e6e6"},
	{"x":"Good game!", "c":"#e6c2ff", "all":true},
]
const QC_GAP := 2.0              # s between one player's quick chats

const STATES := ["idle", "move", "wind", "recover", "dodge", "dead"]
const CLASSES := ["knight", "barbarian", "rogue", "ranger", "mage", "priest"]
const ATKS := ["", "attack", "ability"]
# Actions a client may ask for (anything else is ignored by the server).
const ACTIONS := ["attack", "ability", "block", "dodge"]

# Per-unit values in the snapshot, in this order, each packed as a signed 16-bit integer of
# value * SCALE[i] (positions to 1 cm, angles to 0.001 rad, timers to 0.01 s):
#   hp, max hp, x, z, facing, state, class, upgraded, stun, ability recharge, dodge recharge, knockouts, downs,
#   gate damage, bot, respawn at, swing kind, beam target, blocking, whirl left, second beam target
const F := 21
const SCALE := [1.0, 1.0, 100.0, 100.0, 1000.0, 1.0, 1.0, 1.0, 100.0, 100.0,
	100.0, 1.0, 1.0, 0.1, 1.0, 10.0, 1.0, 1.0, 1.0, 100.0, 1.0]

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
	# 0.31.108: 300 gems + 150 Embers + a rare -> 500 + 300 + an epic (about 2.6x its price; was 1.5x)
	"starter_pack": {"gems":500,  "embers":300, "weapon":"epic", "once":true, "usd":"2.99"},
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
# Kevin: "I want players to see everything the other players are wearing". A hello may carry "lk": {class: "weapon
# id|stars|element"} for each class the player has dressed (Profile.wire_looks: the equipped weapon and its Forge stars
# and element). The server keeps only well-formed entries (clean_looks: one of LOOK_CLASSES, an id of a-z 0-9 _, stars
# 0-3, an element word) and sends them in "pn" as "lk": {unit id: {class: entry}}, as it does names and titles. Ids are
# not checked against the catalog here (the server carries no economy, and a newer app may know newer items): each app
# makes the look with its own catalog (Eco.looks_from_wire) and shows the starter for an id it doesn't know.
# Additive: an older server ignores "lk" in a hello, an older app ignores it in "pn"; the protocol stays.
const LOOK_CLASSES := ["knight", "barbarian", "rogue", "ranger", "mage", "priest", "worker",
	"crusader", "berserker", "necromancer", "assassin", "sniper", "archmage"]
const LOOK_STARS := 3                # Eco.FORGE_STARS.size()

static func clean_looks(v: Variant) -> Dictionary:
	var out := {}
	if not (v is Dictionary):
		return out
	for k in v:
		var cls := str(k)
		if LOOK_CLASSES.has(cls) and v[k] is String:
			var e := clean_look(v[k])
			if e != "":
				out[cls] = e
	return out

static func clean_look(s: String) -> String:
	# "weapon id|stars|element" with every part checked, or "" (a bad element is dropped, the rest kept)
	if s.length() > 64:
		return ""
	var p := s.split("|")
	if p.size() != 3 or p[0].length() > 40 or not _word(p[0], true) or not p[1].is_valid_int():
		return ""
	var n := clampi(p[1].to_int(), 0, LOOK_STARS)
	var el := p[2] if p[2].length() <= 12 and _word(p[2], false) else ""
	if p[0] == "" and n == 0:
		return ""
	return "%s|%d|%s" % [p[0], n, el]

static func _word(s: String, digits: bool) -> bool:
	for ch in s:
		var c := ch.unicode_at(0)
		if not ((c >= 97 and c <= 122) or c == 95 or (digits and c >= 48 and c <= 57)):
			return false
	return true

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

static func _pack(arr: PackedByteArray, i: int, v: float) -> void:
	arr.encode_s16(i * 2, clampi(int(round(v * SCALE[i % F])), -32768, 32767))

static func _unpack(arr: PackedByteArray, i: int) -> float:
	return float(arr.decode_s16(i * 2)) / SCALE[i % F]

static func _code(list: Array, value: Variant) -> int:
	var i := list.find(value)
	return maxi(0, i)

# ---------------- server side ----------------
static var _slow_hash := {}
static var _slow_n := 0

static func snapshot(sim, for_unit: String, events: Array) -> Dictionary:
	# One snapshot for every player (for_unit: kept for the callers; nothing in it is private any more).
	var vals := PackedFloat32Array()
	vals.resize(sim.units.size() * F)
	var u_arr := vals
	var i := 0
	for u in sim.units:
		var b := i * F
		u_arr[b + 0] = u.hp
		u_arr[b + 1] = u.max_hp
		u_arr[b + 2] = u.pos.x
		u_arr[b + 3] = u.pos.y
		u_arr[b + 4] = u.face
		u_arr[b + 5] = _code(STATES, u.state)
		u_arr[b + 6] = _code(CLASSES, u.cls)
		u_arr[b + 7] = 1.0 if u.up else 0.0
		u_arr[b + 8] = u.stun
		u_arr[b + 9] = u.cd_ability
		u_arr[b + 10] = u.cd_dodge
		u_arr[b + 11] = u.kills
		u_arr[b + 12] = u.deaths
		u_arr[b + 13] = u.gate_dmg
		u_arr[b + 14] = 1.0 if u.bot else 0.0
		u_arr[b + 15] = u.respawn_at
		u_arr[b + 16] = _code(ATKS, u.get("atk", ""))
		# Priest beam target: its unit index + 1 (0 = none).
		u_arr[b + 17] = float(sim.units.find(sim.by_id.get(str(u.beam), {})) + 1) if str(u.get("beam", "")) != "" else 0.0
		u_arr[b + 18] = 1.0 if sim.blocking(u) else 0.0
		u_arr[b + 19] = maxf(0.0, float(u.get("whirl_until", 0.0)) - sim.time)
		u_arr[b + 20] = float(sim.units.find(sim.by_id.get(str(u.get("beam2", "")), {})) + 1) if str(u.get("beam2", "")) != "" else 0.0
		i += 1
	var packed := PackedByteArray()
	packed.resize(vals.size() * 2)
	for k in vals.size():
		_pack(packed, k, vals[k])
	# Projectiles: 6 int16 each (id, x, z, vx, vz, kind).
	var proj := PackedByteArray()
	proj.resize(sim.projectiles.size() * 12)
	var pi := 0
	for p in sim.projectiles:
		var vals_p := [int(p.id) % 65536 - 32768, (p.pos as Vector2).x * 100.0, (p.pos as Vector2).y * 100.0, (p.vel as Vector2).x * 100.0,
			(p.vel as Vector2).y * 100.0, PROJ_KINDS.find(str(p.kind))]
		for k in 6:
			proj.encode_s16((pi * 6 + k) * 2, clampi(int(round(float(vals_p[k]))), -32768, 32767))
		pi += 1
	var gates := PackedFloat32Array()
	for g in sim.gates:
		gates.append_array([g.hp, g.max_hp, 1.0 if g.broken else 0.0, 1.0 if g.open else 0.0])
	var msg := {"t":"s", "tm":sim.time, "sc":sim.score.duplicate(), "k":sim.kills.duplicate(), "end":[sim.ended, sim.winner, sim.end_reason],
		"u":packed, "p":proj, "e":events}
	# Slow-changing state: only when it changed, and in full once a second (FULL_EVERY) so a late joiner catches up.
	_slow_n += 1
	var full := _slow_n % FULL_EVERY == 0
	for pair in [["g", gates]]:
		var h := hash(pair[1])
		if full or int(_slow_hash.get(pair[0], 0)) != h:
			_slow_hash[pair[0]] = h
			msg[pair[0]] = pair[1]
	return msg

# ---------------- client side ----------------
static func apply(sim, msg: Dictionary, me_id: String, predict := false) -> void:
	# Overwrites the mirror sim's dynamic state. Unit positions go to "net_to" so the client can
	# interpolate between snapshots; everything else is set directly.
	# The phone predicts its own unit: keep its position/facing (and a dodge it started) unless the
	# server disagrees by > PREDICT_SNAP or the unit is in a server-driven state (0.18.4).
	var mine_prev := {}
	if predict and sim.by_id.has(me_id):
		var mp: Dictionary = sim.by_id[me_id]
		mine_prev = {"pos": mp.pos, "face": mp.face, "state": mp.state, "t": float(mp.get("t", 0.0))}
	sim.time = float(msg.get("tm", sim.time))
	var snap_t: float = sim.time
	sim.score = msg.get("sc", sim.score)
	sim.kills = msg.get("k", sim.kills)
	var end: Array = msg.get("end", [false, -1, ""])
	sim.ended = bool(end[0])
	sim.winner = int(end[1])
	sim.end_reason = str(end[2])
	var packed: PackedByteArray = msg.get("u", PackedByteArray())
	var u_arr := PackedFloat32Array()
	u_arr.resize(packed.size() / 2)
	for k in u_arr.size():
		u_arr[k] = _unpack(packed, k)
	var n_units: int = mini(sim.units.size(), u_arr.size() / F)
	for i in n_units:
		var u: Dictionary = sim.units[i]
		var b := i * F
		var was_dead: bool = u.state == "dead"
		u.hp = u_arr[b + 0]
		u.max_hp = u_arr[b + 1]
		var to := Vector2(u_arr[b + 2], u_arr[b + 3])
		u["net_from"] = u.pos
		u["net_to"] = to
		_push_hist(u, snap_t, to, u_arr[b + 4])
		var state: String = STATES[clampi(int(u_arr[b + 5]), 0, STATES.size() - 1)]
		if was_dead != (state == "dead") or u.pos.distance_to(to) > 6.0:
			u.pos = to                       # respawn / teleport: no sliding across the map
			u["net_from"] = to
		u.face = u_arr[b + 4]
		u.state = state
		u.cls = CLASSES[clampi(int(u_arr[b + 6]), 0, CLASSES.size() - 1)]
		u.up = u_arr[b + 7] > 0.5
		u.stun = u_arr[b + 8]
		u.cd_ability = u_arr[b + 9]
		u.cd_dodge = u_arr[b + 10]
		u.kills = int(u_arr[b + 11])
		u.deaths = int(u_arr[b + 12])
		u.gate_dmg = u_arr[b + 13]
		u.bot = u_arr[b + 14] > 0.5
		u.respawn_at = u_arr[b + 15]
		u.atk = ATKS[clampi(int(u_arr[b + 16]), 0, ATKS.size() - 1)]
		var bi := int(round(u_arr[b + 17])) - 1
		u.beam = str(sim.units[bi].id) if bi >= 0 and bi < sim.units.size() else ""
		# The mirror doesn't step: flag the states open-ended; the next snapshot clears them.
		u.block_until = 1.0e9 if u_arr[b + 18] > 0.5 else 0.0
		u.whirl_until = 1.0e9 if u_arr[b + 19] > 0.005 else 0.0
		var b2 := int(round(u_arr[b + 20])) - 1
		u.beam2 = str(sim.units[b2].id) if b2 >= 0 and b2 < sim.units.size() else ""
	# Projectiles slide between snapshots like units (0.18.5, Kevin: "projectiles skip across the
	# screen online"): they used to be redrawn only at each snapshot's position, so an arrow at
	# 22 m/s sat still for 66 ms and then jumped 1.5 m. Now each keeps from/to: a new one starts at
	# its spawn point (on the same one-interval-behind timeline as the units it flies between), and
	# one that ended this snapshot gets one last slide to its impact point before it disappears.
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
		var from: Vector2 = prev.get("net_to", to)
		var t0: float = float(prev.get("net_t", snap_t - 1.0 / SNAP_HZ))
		sim.projectiles.append({"id":pid, "pos":from, "net_from":from, "net_to":to, "vel":Vector2(float(v[3]) / 100.0, float(v[4]) / 100.0),
			"kind":PROJ_KINDS[clampi(int(v[5]), 0, PROJ_KINDS.size() - 1)], "team":-1,
			"net_t":snap_t, "net_t0":t0, "net_dt":maxf(snap_t - t0, 0.001)})
		seen[pid] = true
	var ends := {}
	for e in msg.get("e", []):
		if e is Dictionary and str(e.get("k", "")) == "proj_end" and e.has("pos"):
			ends[e.get("pid")] = e.pos
	for id in old:
		var gone: Dictionary = old[id]
		if not seen.has(id) and ends.has(id) and not bool(gone.get("ghost", false)):
			var last: Vector2 = gone.get("net_to", gone.pos)
			sim.projectiles.append({"id":id, "pos":last, "net_from":last, "net_to":ends[id], "vel":gone.vel,
				"kind":gone.kind, "team":-1, "ghost":true})
	var gates: PackedFloat32Array = msg.get("g", PackedFloat32Array())
	for gi in mini(sim.gates.size(), gates.size() / 4):
		var g: Dictionary = sim.gates[gi]
		g.hp = gates[gi * 4]
		g.max_hp = gates[gi * 4 + 1]
		g.broken = gates[gi * 4 + 2] > 0.5
		g.open = gates[gi * 4 + 3] > 0.5
	if not mine_prev.is_empty():
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

static func interpolate(sim, alpha: float) -> void:
	# Called every frame between snapshots: slide unit positions from the previous snapshot to
	# the latest (alpha 0..1 across one snapshot interval).
	var a := clampf(alpha, 0.0, 1.0)
	for u in sim.units:
		if u.has("net_to"):
			u.pos = (u.net_from as Vector2).lerp(u.net_to, a)
	for p in sim.projectiles:
		if p.has("net_to"):
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
	for p in sim.projectiles:
		if p.has("net_to"):
			var pt := clampf((rt - float(p.get("net_t0", rt))) / maxf(float(p.get("net_dt", 1.0 / SNAP_HZ)), 0.001), 0.0, 1.2)
			p.pos = (p.net_from as Vector2).lerp(p.net_to, pt)
