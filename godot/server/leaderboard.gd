extends RefCounted
# 0.31.119 (Kevin: "Do all" -- 4. leaderboards): the week's best players, from this server's own count of online matches.
#
# Each paid online match (siege_server _pay_match: the server's ledger, never the phone's word) adds to the account's
# week: points (the scoreboard's: rescue 300, knockout 20, fish fed 30, gathering 2, gate damage 1 per 10, + WIN_BONUS
# for a win), wins, matches, rescues, knockouts. Weeks start Monday 00:00 UTC; when one ends its top 3 are kept as
# last week's champions and the board starts empty. Kept in leaderboard.json in the state directory (written a few
# seconds after a change).
#
# A phone asks on its own socket ({"t":"lb", "acct", "key"}, no hello, like "eco") and gets
#   {"t":"lb", "week": "YYYY-MM-DD" (its Monday), "ends": unix, "top": [row x TOP_N], "me": row or {}, "friends": [row],
#    "players": how many are on the board, "last": [last week's top 3]}
#   row = {"rank", "name", "title", "pts", "w", "m", "r", "k", "you": true on your own}
# Names and titles are the accounts' own (what everyone already sees over their heads). No account ids go out.
const WIN_BONUS := 100
const TOP_N := 50
const SAVE_DELAY := 3.0
const P_RESCUE := 300
const P_KO := 20
const P_FED := 30
const P_GATHER := 2
const P_GATE := 0.1

var path := ""
var week := ""
var rows := {}                     # acct -> {"name", "title", "pts", "w", "m", "r", "k", "at"}
var last := []                     # last week's top 3: [{"name", "title", "pts"}]
var now_override := -1
var log_fn: Callable = func(_s): pass
var _dirty_at := -1.0
var _clock := 0.0

func _init(state_dir := "", now_at := -1) -> void:
	var state := state_dir
	if state == "":
		state = OS.get_environment("STATE_DIRECTORY") if OS.has_environment("STATE_DIRECTORY") else "user://"
	path = state.path_join("leaderboard.json")
	now_override = now_at
	_load()
	_roll()

func now() -> int:
	return now_override if now_override >= 0 else int(Time.get_unix_time_from_system())

static func week_of(t: int) -> String:
	# the Monday (UTC) of t's week, "YYYY-MM-DD" (1970-01-01 was a Thursday)
	var day := int(floor(t / 86400.0))
	var monday := day - posmod(day + 3, 7)
	return Time.get_date_string_from_unix_time(monday * 86400)

static func week_end(t: int) -> int:
	var day := int(floor(t / 86400.0))
	return (day - posmod(day + 3, 7) + 7) * 86400

static func points_of(me: Dictionary, won: bool) -> int:
	return int(me.get("rescues", 0)) * P_RESCUE + int(me.get("kills", 0)) * P_KO + int(me.get("fed", 0)) * P_FED \
		+ int(me.get("gathered", 0)) * P_GATHER + int(float(me.get("gate_dmg", 0.0)) * P_GATE) + (WIN_BONUS if won else 0)

func add_match(acct: String, name: String, title: String, me: Dictionary, won: bool) -> void:
	if acct == "":
		return
	_roll()
	var r: Dictionary = rows.get(acct, {"pts":0, "w":0, "m":0, "r":0, "k":0})
	r.name = name
	r.title = title
	r.pts = int(r.pts) + maxi(0, points_of(me, won))
	r.w = int(r.w) + (1 if won else 0)
	r.m = int(r.m) + 1
	r.r = int(r.r) + maxi(0, int(me.get("rescues", 0)))
	r.k = int(r.k) + maxi(0, int(me.get("kills", 0)))
	r.at = now()
	rows[acct] = r
	_mark()

func ranked() -> Array:
	# accounts best first: points, then wins, then fewer matches, then who got there first
	var ids := rows.keys()
	ids.sort_custom(func(a, b):
		var ra: Dictionary = rows[a]
		var rb: Dictionary = rows[b]
		if int(ra.pts) != int(rb.pts):
			return int(ra.pts) > int(rb.pts)
		if int(ra.w) != int(rb.w):
			return int(ra.w) > int(rb.w)
		if int(ra.m) != int(rb.m):
			return int(ra.m) < int(rb.m)
		return int(ra.get("at", 0)) < int(rb.get("at", 0)))
	return ids

func _row(acct: String, rank: int, mine: bool) -> Dictionary:
	var r: Dictionary = rows[acct]
	var out := {"rank":rank, "name":str(r.get("name", "Player")), "title":str(r.get("title", "")), "pts":int(r.pts),
		"w":int(r.w), "m":int(r.m), "r":int(r.r), "k":int(r.k)}
	if mine:
		out["you"] = true
	return out

func answer(acct: String, friend_accts: Array) -> Dictionary:
	_roll()
	var order := ranked()
	var rank_of := {}
	for i in order.size():
		rank_of[order[i]] = i + 1
	var top := []
	for i in mini(TOP_N, order.size()):
		top.append(_row(order[i], i + 1, order[i] == acct))
	var me := _row(acct, int(rank_of[acct]), true) if rows.has(acct) else {}
	var fr := []
	for a in friend_accts + [acct]:
		if rows.has(a) and not fr.any(func(x): return x.get("_a", "") == a):
			var row := _row(a, int(rank_of[a]), a == acct)
			row["_a"] = a
			fr.append(row)
	fr.sort_custom(func(x, y): return int(x.rank) < int(y.rank))
	for row in fr:
		row.erase("_a")
	return {"t":"lb", "week":week, "ends":week_end(now()), "top":top, "me":me, "friends":fr, "players":order.size(), "last":last}

# ---------------- the week ----------------
func _roll() -> void:
	var w := week_of(now())
	if w == week:
		return
	if week != "" and not rows.is_empty():
		var order := ranked()
		last = []
		for i in mini(3, order.size()):
			var r: Dictionary = rows[order[i]]
			last.append({"name":str(r.get("name", "Player")), "title":str(r.get("title", "")), "pts":int(r.pts)})
		log_fn.call("leaderboard: week %s over, %d players; champion %s (%d pts)" % [week, rows.size(), last[0].name if not last.is_empty() else "-",
			int(last[0].pts) if not last.is_empty() else 0])
	week = w
	rows = {}
	_mark()

# ---------------- the file ----------------
func _load() -> void:
	if not FileAccess.file_exists(path):
		return
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if v is Dictionary:
		week = str(v.get("week", ""))
		rows = v.get("rows", {}) if v.get("rows", {}) is Dictionary else {}
		last = v.get("last", []) if v.get("last", []) is Array else []

func _mark() -> void:
	if _dirty_at < 0.0:
		_dirty_at = _clock

func tick(delta: float) -> void:
	_clock += delta
	if _dirty_at >= 0.0 and _clock - _dirty_at >= SAVE_DELAY:
		save_now()
	if int(_clock) % 60 == 0 and int(_clock - delta) % 60 != 0:
		_roll()                                       # (a new week starts on time even with nobody playing)

func save_now() -> void:
	_dirty_at = -1.0
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		log_fn.call("leaderboard: can't write %s" % path)
		return
	f.store_string(JSON.stringify({"week":week, "rows":rows, "last":last}))
	f.close()
