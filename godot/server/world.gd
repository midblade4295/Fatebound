extends RefCounted
# 0.31.135 (Kevin, Crown War step 2 -- the "Crown War" design doc): the war map's state on the server. Which house and
# clan holds each territory (scripts/meta/war_map.gd), each clan's capture points on each territory, the battles
# running, and each clan member's attempts today. It rides the social socket (server/social.gd): "war_*" messages.
#   war_open / war_close   the map is on the phone's screen: it gets {"k":"war", ...} now and on every change
#   war_go {tid, call}     a clan member starts a battle for a territory: one their house can attack (linked to land it
#                          holds or to its home; not a home -- King's Day is a later step), with an attempt left. One
#                          battle a territory at a time: asking for one already started by their house joins it. ->
#                          {"k":"war_go", "ok", "bid", "tid", "side":"att"} or {"ok":false, "why"}; with "call" the
#                          clan's members online get {"k":"war_call"} (JOIN); the holding clan's members online get
#                          {"k":"war_alarm"} (DEFEND).
# The battle itself is an ordinary 16-a-side Siege match in a room of its own (siege_server.gd: room_fn makes it):
# the attackers' house on one side, the holders' house on the other (nobody defends a territory nobody holds -- bots
# do), bots in every empty seat. A member of the attacking clan with an attempt left spends it when seated
# (seated()); at the end (battle_over()) each such member adds Map.points(crowns, won) to the clan's bar on that
# territory -- a crown each for a gate broken, the King rescued and the match won; a loss takes PTS_LOSS off; one who
# quit counts as a loss. The first clan whose bar reaches NEED_NEUTRAL (nobody holds it) or NEED_OWNED takes it for its
# house; every bar on it starts again.
# Weeks run Monday 00:00 UTC to Monday (the leaderboard's): when one ends, the house holding the most territory wins it
# (tally) and every territory is free again (the land rush). Attempts are per UTC day.
# Kept in world.json in the state directory (holders, bars, today's attempts, the weeks won, recent captures).
const Map = preload("res://scripts/meta/war_map.gd")
const Leaderboard = preload("res://server/leaderboard.gd")

const SAVE_DELAY := 3.0
const PUSH_GAP := 0.5              # s between map pushes to the phones that have it open
const ROLL_EVERY := 10.0           # s between looks at the clock for a new week
const LOG_MAX := 30

var soc                            # server/social.gd (users, sockets, clans)
var path := ""
var week := ""
var owners := {}                   # tid -> {"h": house, "c": clan id, "ct": tag, "cn": clan name, "at": unix}
var bars := {}                     # tid -> {clan id: points}
var attempts := {}                 # pid -> {"d": "YYYY-MM-DD", "n": used that day}
var tally := {}                    # house -> weeks won
var last := {}                     # the week before: {"week", "won": house or "", "counts": {house: territories}}
var captures: Array = []           # newest first: {"at", "tid", "h", "ct", "from"}
var battles := {}                  # bid -> {"bid", "tid", "ah", "ac", "act", "acn", "dh", "dc", "dct", "by", "at", "room", "state", "scorers"}
var watchers := {}                 # pid -> true: the map is open on their phone
var room_fn: Callable = func(_b: Dictionary) -> int: return 0   # siege_server: a room for a battle (0: every room busy)
var event_fn: Callable = func(_acct, _ev, _p): pass               # usage statistics
var now_override := -1
var next_bid := 1
var _dirty_at := -1.0
var _push_due := false
var _push_clock := 0.0
var _roll_clock := 0.0

func _init(state_dir: String, social) -> void:
	soc = social
	path = state_dir.path_join("world.json")
	_load()
	_roll()

func unix() -> int:
	return now_override if now_override >= 0 else soc.unix()

static func day_of(t: int) -> String:
	return Time.get_date_string_from_unix_time(t)

# ---------------- storage ----------------
func _load() -> void:
	if not FileAccess.file_exists(path):
		return
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (v is Dictionary):
		return
	week = str(v.get("week", ""))
	for k in ["owners", "bars", "attempts", "tally", "last"]:
		if v.get(k, null) is Dictionary:
			set(k, v[k])
	if v.get("captures", null) is Array:
		captures = v.captures
	next_bid = maxi(1, int(v.get("next_bid", 1)))

func save_now() -> void:
	var today := day_of(unix())
	for pid in attempts.keys():
		if str(attempts[pid].get("d", "")) != today:
			attempts.erase(pid)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"v":1, "week":week, "owners":owners, "bars":bars, "attempts":attempts, "tally":tally,
		"last":last, "captures":captures, "next_bid":next_bid}))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	_dirty_at = -1.0

func _mark() -> void:
	if _dirty_at < 0.0:
		_dirty_at = soc.clock
	_push_due = true

func tick(delta: float) -> void:
	_roll_clock += delta
	if _roll_clock >= ROLL_EVERY:
		_roll_clock = 0.0
		_roll()
	if _dirty_at >= 0.0 and soc.clock - _dirty_at >= SAVE_DELAY:
		save_now()
	_push_clock += delta
	if _push_due and _push_clock >= PUSH_GAP:
		_push_clock = 0.0
		_push_due = false
		for pid in watchers.keys():
			if soc.online.has(pid):
				soc._send(pid, map_msg(pid))
			else:
				watchers.erase(pid)

# ---------------- the week ----------------
func counts() -> Dictionary:
	var out := {}
	for h in Map.HOUSES:
		out[h] = 0
	for tid in owners:
		var h := str(owners[tid].get("h", ""))
		if out.has(h):
			out[h] = int(out[h]) + 1
	return out

func _roll() -> void:
	var w := Leaderboard.week_of(unix())
	if w == week:
		return
	if week != "":
		var cn := counts()
		var best := ""
		var best_n := 0
		var tie := false
		for h in Map.HOUSES:
			if int(cn[h]) > best_n:
				best = h
				best_n = int(cn[h])
				tie = false
			elif int(cn[h]) == best_n and best_n > 0:
				tie = true
		var won := best if not tie else ""
		if won != "":
			tally[won] = int(tally.get(won, 0)) + 1
		last = {"week":week, "won":won, "counts":cn}
		soc.log_fn.call("war: week %s over -- %s (%s); the map is free again" % [week, ("House " + won + " won") if won != "" else "no winner", str(cn)])
	week = w
	owners = {}
	bars = {}
	_mark()

func week_end() -> int:
	return Leaderboard.week_end(unix())

# ---------------- who may do what ----------------
func house_of_pid(pid: String) -> String:
	if soc.clans == null:
		return ""
	var id: String = soc.clans.clan_of(pid)
	return str(soc.clans.clans[id].house) if id != "" and soc.clans.clans.has(id) else ""

func holder(tid: String) -> String:
	if Map.is_home(tid):
		return str(Map.T[tid].home)
	return str(owners.get(tid, {}).get("h", ""))

func need_for(tid: String) -> int:
	return Map.NEED_OWNED if owners.has(tid) else Map.NEED_NEUTRAL

func attempts_left(pid: String) -> int:
	var a: Dictionary = attempts.get(pid, {})
	if str(a.get("d", "")) != day_of(unix()):
		return Map.ATTEMPTS
	return maxi(0, Map.ATTEMPTS - int(a.get("n", 0)))

func reach(house: String, tid: String) -> String:
	# "" when the house can attack the territory, else why not
	if not Map.T.has(tid):
		return "There's no such place"
	if Map.is_home(tid):
		return "Homes can't be attacked yet"
	if holder(tid) == house:
		return "Your house holds it"
	for n in Map.neighbours(tid):
		if holder(str(n)) == house:
			return ""
	return "It isn't linked to your house's land"

func battle_on(tid: String) -> Dictionary:
	for bid in battles:
		if str(battles[bid].tid) == tid and str(battles[bid].state) != "over":
			return battles[bid]
	return {}

func side_for(pid: String, bid: String) -> String:
	# siege_server: which side of a battle this player may take ("att", "def" or "")
	var b: Dictionary = battles.get(bid, {})
	if b.is_empty() or str(b.state) == "over":
		return ""
	var h := house_of_pid(pid)
	if h == "":
		return ""
	if h == str(b.ah):
		return "att"
	if h == str(b.dh) and str(b.dh) != "":
		return "def"
	return ""

# ---------------- messages ----------------
func handle(pid: String, msg: Dictionary) -> void:
	match str(msg.get("k", "")):
		"war_open":
			watchers[pid] = true
			soc._send(pid, map_msg(pid))
		"war_close":
			watchers.erase(pid)
		"war_go":
			_go(pid, str(msg.get("tid", "")), bool(msg.get("call", true)))

func unwatch(pid: String) -> void:
	watchers.erase(pid)

func _refuse(pid: String, tid: String, why: String) -> void:
	soc._send(pid, {"t":"so", "k":"war_go", "ok":false, "tid":tid, "why":why})

func _go(pid: String, tid: String, call: bool) -> void:
	var clans = soc.clans
	var cid: String = clans.clan_of(pid) if clans != null else ""
	if cid == "":
		_refuse(pid, tid, "Join a clan to fight for territory")
		return
	var c: Dictionary = clans.clans[cid]
	var house := str(c.house)
	var why := reach(house, tid)
	if why != "":
		_refuse(pid, tid, why)
		return
	var on := battle_on(tid)
	if not on.is_empty():
		if str(on.ah) == house:
			soc._send(pid, {"t":"so", "k":"war_go", "ok":true, "bid":str(on.bid), "tid":tid, "side":"att", "joined":true})
		else:
			_refuse(pid, tid, "House %s is attacking it right now" % str(Map.HOUSE_NAMES.get(str(on.ah), on.ah)))
		return
	if attempts_left(pid) <= 0:
		_refuse(pid, tid, "No battles left today -- join your clan's battles to help, or come back tomorrow")
		return
	var own: Dictionary = owners.get(tid, {})
	var bid := "b%d%s" % [next_bid, Crypto.new().generate_random_bytes(2).hex_encode()]
	next_bid += 1
	var b := {"bid":bid, "tid":tid, "ah":house, "ac":cid, "act":str(c.tag), "acn":str(c.name), "dh":str(own.get("h", "")),
		"dc":str(own.get("c", "")), "dct":str(own.get("ct", "")), "by":pid, "at":unix(), "room":0, "state":"lobby", "scorers":{}}
	var room := int(room_fn.call(b))
	if room <= 0:
		_refuse(pid, tid, "Every battlefield is busy -- try again in a few minutes")
		return
	b.room = room
	battles[bid] = b
	_mark()
	var name: String = soc._name(pid)
	soc.log_fn.call("war: %s [%s] attacks %s (battle %s, room %d)" % [name, str(c.tag), tid, bid, room])
	event_fn.call(str(soc.users[pid].acct), "war_start", {"tid":tid, "held":own.has("h")})
	soc._send(pid, {"t":"so", "k":"war_go", "ok":true, "bid":bid, "tid":tid, "side":"att"})
	var tname := Map.name_of(tid)
	if call:
		for m in clans.members_of(cid):
			if str(m) != pid and soc.online.has(str(m)):
				soc._send(str(m), {"t":"so", "k":"war_call", "bid":bid, "tid":tid, "name":tname, "by":name, "ct":str(c.tag), "h":house})
		clans._sys(cid, "%s is attacking %s -- join the battle!" % [name, tname])
	var dc := str(own.get("c", ""))
	if dc != "" and clans.clans.has(dc):
		for m in clans.members_of(dc):
			if soc.online.has(str(m)):
				soc._send(str(m), {"t":"so", "k":"war_alarm", "bid":bid, "tid":tid, "name":tname, "ct":str(c.tag), "h":house})
		clans._sys(dc, "[%s] is attacking %s -- defend it!" % [str(c.tag), tname])

# ---------------- the battle (siege_server.gd) ----------------
func seated(bid: String, pid: String, acct: String, name: String) -> bool:
	# an attacker sat down: a member of the attacking clan with an attempt left spends it (-> true: their battle counts)
	var b: Dictionary = battles.get(bid, {})
	if b.is_empty() or soc.clans == null or str(soc.clans.clan_of(pid)) != str(b.ac):
		return false
	if (b.scorers as Dictionary).has(pid):
		return true                                    # (back on their seat: counted once)
	if attempts_left(pid) <= 0:
		return false
	var today := day_of(unix())
	var a: Dictionary = attempts.get(pid, {})
	attempts[pid] = {"d":today, "n":(int(a.get("n", 0)) if str(a.get("d", "")) == today else 0) + 1}
	b.scorers[pid] = {"acct":acct, "name":name}
	_mark()
	return true

func started(bid: String) -> void:
	if battles.has(bid) and str(battles[bid].state) == "lobby":
		battles[bid].state = "on"
		_mark()

func battle_gone(bid: String) -> void:
	# its room closed (nobody came, or everyone left after it ended)
	if battles.has(bid):
		battles.erase(bid)
		_mark()

func battle_over(bid: String, res: Dictionary) -> Dictionary:
	# res: {"won": the attackers won, "gate": they broke a gate, "king": they rescued their King, "present": [pid]}
	# -> pid -> what their battle did, for each member of the attacking clan who spent an attempt on it
	var b: Dictionary = battles.get(bid, {})
	if b.is_empty() or str(b.state) == "over":
		return {}
	b.state = "over"
	var tid := str(b.tid)
	var ac := str(b.ac)
	var won := bool(res.get("won", false))
	var crowns := int(bool(res.get("gate", false))) + int(bool(res.get("king", false))) + int(won)
	var present: Array = res.get("present", [])
	var total := 0
	var per := {}
	for pid in b.scorers:
		var p := Map.points(crowns, won) if present.has(pid) else -Map.PTS_LOSS
		per[pid] = p
		total += p
	var tb: Dictionary = bars.get(tid, {})
	var need := need_for(tid)
	var bar := maxi(0, int(tb.get(ac, 0)) + total)
	var took := false
	if soc.clans != null and soc.clans.clans.has(ac) and holder(tid) != str(b.ah):
		tb[ac] = bar
		bars[tid] = tb
		if bar >= need:
			took = true
			_capture(tid, ac)
	_mark()
	var out := {}
	for pid in per:
		out[pid] = {"tid":tid, "name":Map.name_of(tid), "pts":int(per[pid]), "crowns":crowns, "gate":bool(res.get("gate", false)),
			"king":bool(res.get("king", false)), "won":won, "bar":mini(bar, need), "need":need, "took":took, "quit":not present.has(pid)}
	var cl = soc.clans
	if cl != null and cl.clans.has(ac) and not per.is_empty():
		cl._sys(ac, "The battle for %s: %s, %d crown%s, %+d (%d/%d)%s" % [Map.name_of(tid), "won" if won else "lost", crowns,
			"" if crowns == 1 else "s", total, mini(bar, need), need, " -- it's ours!" if took else ""])
	soc.log_fn.call("war: battle %s for %s over: %s, crowns %d, %d scorers, %+d -> %d/%d%s" % [bid, tid, "won" if won else "lost",
		crowns, per.size(), total, bar, need, " TAKEN" if took else ""])
	return out

func _capture(tid: String, cid: String) -> void:
	var cl = soc.clans
	var c: Dictionary = cl.clans[cid]
	var prev: Dictionary = owners.get(tid, {})
	owners[tid] = {"h":str(c.house), "c":cid, "ct":str(c.tag), "cn":str(c.name), "at":unix()}
	bars[tid] = {}
	captures.push_front({"at":unix(), "tid":tid, "h":str(c.house), "ct":str(c.tag), "from":str(prev.get("h", ""))})
	while captures.size() > LOG_MAX:
		captures.pop_back()
	var tname := Map.name_of(tid)
	cl._sys(cid, "We took %s for House %s!" % [tname, str(Map.HOUSE_NAMES.get(str(c.house), c.house))])
	var pc := str(prev.get("c", ""))
	if pc != "" and cl.clans.has(pc):
		cl._sys(pc, "We lost %s to [%s] %s" % [tname, str(c.tag), str(c.name)])
	soc.log_fn.call("war: [%s] %s takes %s for %s (from %s)" % [str(c.tag), str(c.name), tid, str(c.house), str(prev.get("h", "nobody"))])
	var by := str(c.get("leader", ""))
	event_fn.call(str(soc.users.get(by, {}).get("acct", "")), "war_capture", {"tid":tid, "held":not prev.is_empty()})

func forget(pid: String) -> void:
	watchers.erase(pid)
	attempts.erase(pid)

# ---------------- the map for a phone ----------------
func map_msg(pid: String) -> Dictionary:
	var house := house_of_pid(pid)
	var my_clan: String = soc.clans.clan_of(pid) if soc.clans != null else ""
	var terr := {}
	for tid in Map.T:
		var t := {"h":holder(tid)}
		if Map.is_home(tid):
			terr[tid] = t
			continue
		var own: Dictionary = owners.get(tid, {})
		if not own.is_empty():
			t["ct"] = str(own.get("ct", ""))
			t["cn"] = str(own.get("cn", ""))
		t["need"] = need_for(tid)
		var tb: Dictionary = bars.get(tid, {})
		var rows := []
		for cid in tb:
			if int(tb[cid]) <= 0 or soc.clans == null or not soc.clans.clans.has(str(cid)):
				continue
			var c: Dictionary = soc.clans.clans[str(cid)]
			rows.append({"c":str(cid), "ct":str(c.tag), "h":str(c.house), "p":int(tb[cid])})
		rows.sort_custom(func(a, b): return int(a.p) > int(b.p))
		var top := rows.slice(0, 3)
		if my_clan != "" and int(tb.get(my_clan, 0)) > 0 and not top.any(func(r): return str(r.c) == my_clan):
			top.append(rows.filter(func(r): return str(r.c) == my_clan)[0])
		t["bars"] = top
		var on := battle_on(tid)
		if not on.is_empty():
			t["b"] = {"bid":str(on.bid), "ah":str(on.ah), "act":str(on.act), "state":str(on.state)}
		if house != "":
			t["why"] = reach(house, tid)
		terr[tid] = t
	return {"t":"so", "k":"war", "week":week, "ends":week_end(), "terr":terr, "tally":tally, "last":last, "counts":counts(),
		"house":house, "clan":my_clan, "att":attempts_left(pid), "max":Map.ATTEMPTS, "caps":captures.slice(0, 8)}
