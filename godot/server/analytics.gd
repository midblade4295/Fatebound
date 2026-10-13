extends RefCounted
# 0.31.118 (Kevin's spec, ANALYTICS_SPEC_FOR_CLAUDE.md: "self-hosted analytics on the Siege server ... Everything goes to
# our own Siege server and stays there"): the server's side of the game's own usage statistics.
#
# Two kinds of events, one JSON line each in analytics/YYYY-MM-DD.jsonl in the state directory (the UTC date it arrived):
#   {"rt", "acct", "ev", "ts", "sid", "b", "p", "src", "id"}  (+ "ts_bad": true when the phone's clock was far out)
#   - the phone's ({"t":"an", "acct", "key", "ev":[...]}, one batch per socket, like "eco"): the account must open with
#     its key or nothing is written (the socket is refused, 4005 "an"). Each event: a known name
#     (analytics_events.gd CLIENT), only its own props, ts within 30 days back / 1 day ahead (clamped, ts_bad), at most
#     100 a batch and 2,000 an account a day. Every well-formed id is acknowledged -- kept, dropped or seen before -- so
#     the phone can let go of it; ids seen today or yesterday are written once.
#   - the server's own (server_event): the online match (start, finish, quit), verified purchases, chat/friends/parties
#     (never the text), quick chat, the update screen, and session_online (a hello with an account: the day's active
#     players even when a phone's batches never arrive).
# The account is always the one the server checked, never one named in an event. No IP address, device id, name, chat
# text, purchase token or order id is ever written. An account that opted out (the opt_out event, or a hello carrying
# "an_off") gets no server events until it sends events again. Files: dir 0700, files 0600; a file older than 2 days is
# gzipped (.jsonl.gz), one older than 90 days deleted (at start and every hour). Lines are flushed every second.
const Events = preload("res://scripts/meta/analytics_events.gd")

const MAX_BATCH := 100
const KEEP_DAYS := 90
const GZIP_AFTER_DAYS := 2
const FLUSH_EVERY := 1.0
const MAINT_EVERY := 3600.0
const TS_PAST := 30 * 86400
const TS_FUTURE := 86400
const DIR_MODE := 0x1C0                  # 0700
const FILE_MODE := 0x180                 # 0600

var state := ""
var dir := ""
var per_day_max := 2000                  # an account's events a day (tests lower it)
var now_override := -1                   # tests: the unix time
var log_fn: Callable = func(_s): pass
var seen := {}                           # day -> {id: true} (today and yesterday)
var per_day := {}                        # day -> {acct: n}
var opted := {}                          # acct -> true: opted out
var written := 0
var _files := {}                         # day -> FileAccess (open for appending)
var _dirty := false
var _flush_clock := 0.0
var _maint_clock := 0.0
var _opt_path := ""

func _init(state_dir := "", now_at := -1) -> void:
	state = state_dir
	now_override = now_at                     # (tests: their clock, before the files are read)
	if state == "":
		state = OS.get_environment("STATE_DIRECTORY") if OS.has_environment("STATE_DIRECTORY") else "user://"
	dir = state.path_join("analytics")
	var g := ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(g)
	FileAccess.set_unix_permissions(g, DIR_MODE)
	_opt_path = dir.path_join("opt_out.json")
	_load_opt()
	rebuild()
	maintain()

func now() -> int:
	return now_override if now_override >= 0 else int(Time.get_unix_time_from_system())

static func day_of(t: int) -> String:
	return Time.get_date_string_from_unix_time(t)          # UTC, "YYYY-MM-DD"

static func valid_id(id: String) -> bool:
	return id.length() == 16 and id.is_valid_hex_number()

static func _rand_id() -> String:
	return Crypto.new().generate_random_bytes(8).hex_encode()

# ---------------- the phone's batches ----------------
func handle(msg: Dictionary, eco) -> Dictionary:
	# -> {"t":"an", "ok":[ids], "kept":n}, or {} when the account doesn't open (nothing written)
	var acct := str(msg.get("acct", ""))
	if eco == null or acct == "" or eco.open(acct, str(msg.get("key", ""))).is_empty():
		return {}
	var evs: Variant = msg.get("ev", [])
	var ok := []
	var kept := 0
	if evs is Array:
		for e in (evs as Array).slice(0, MAX_BATCH):
			if not (e is Dictionary):
				continue
			var id := str((e as Dictionary).get("id", ""))
			if not valid_id(id):
				continue
			ok.append(id)
			if _client_event(acct, e):
				kept += 1
	return {"t":"an", "ok":ok, "kept":kept}

func _client_event(acct: String, e: Dictionary) -> bool:
	var ev := str(e.get("ev", ""))
	if not Events.CLIENT.has(ev):
		return false
	var p := Events.clean_props(Events.CLIENT[ev], e.get("p", {}))
	if ev.begins_with("match_") and str(p.get("mode", "")) != "bots":
		return false                                     # (online matches: the server's own count)
	var rt := now()
	var id := str(e.id)
	if _seen(id, rt):
		return false
	var day := day_of(rt)
	if int(per_day.get(day, {}).get(acct, 0)) >= per_day_max:
		return false
	var ts := int(e.get("ts", rt)) if (e.get("ts", null) is float or e.get("ts", null) is int) else rt
	var line := {"rt":rt, "acct":acct, "ev":ev, "ts":ts, "sid":str(e.get("sid", "")).left(8), "b":str(e.get("b", "")).left(40),
		"p":p, "src":"c", "id":id}
	if ts < rt - TS_PAST or ts > rt + TS_FUTURE:
		line.ts = clampi(ts, rt - TS_PAST, rt + TS_FUTURE)
		line["ts_bad"] = true
	if ev == "opt_out":
		_write(line)
		set_opt_out(acct, true)
		return true
	if opted.has(acct):
		set_opt_out(acct, false)                         # (events again: they turned it back on)
	_write(line)
	return true

func _seen(id: String, rt: int) -> bool:
	for d in [day_of(rt), day_of(rt - 86400)]:
		if (seen.get(d, {}) as Dictionary).has(id):
			return true
	return false

# ---------------- the server's own ----------------
func server_event(acct: String, ev: String, p := {}, build := "") -> void:
	if acct == "" or opted.has(acct) or not Events.SERVER.has(ev):
		return
	var rt := now()
	var day := day_of(rt)
	if int(per_day.get(day, {}).get(acct, 0)) >= per_day_max:
		return
	_write({"rt":rt, "acct":acct, "ev":ev, "ts":rt, "sid":"", "b":build.left(40), "p":Events.clean_props(Events.SERVER[ev], p),
		"src":"s", "id":_rand_id()})

func set_opt_out(acct: String, off: bool) -> void:
	if acct == "" or opted.has(acct) == off:
		return
	if off:
		opted[acct] = true
	else:
		opted.erase(acct)
	var f := FileAccess.open(_opt_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(opted.keys()))
		f.close()
		FileAccess.set_unix_permissions(ProjectSettings.globalize_path(_opt_path), FILE_MODE)

func _load_opt() -> void:
	opted = {}
	if FileAccess.file_exists(_opt_path):
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(_opt_path))
		if v is Array:
			for a in v:
				opted[str(a)] = true

# ---------------- the files ----------------
func _write(line: Dictionary) -> void:
	var day := day_of(int(line.rt))
	var f: FileAccess = _files.get(day, null)
	if f == null:
		for d in _files.keys():                        # a new day: yesterday's file is done
			(_files[d] as FileAccess).close()
		_files.clear()
		var path := dir.path_join(day + ".jsonl")
		var fresh := not FileAccess.file_exists(path)
		f = FileAccess.open(path, FileAccess.WRITE if fresh else FileAccess.READ_WRITE)
		if f == null:
			log_fn.call("analytics: can't write %s" % path)
			return
		if fresh:
			FileAccess.set_unix_permissions(ProjectSettings.globalize_path(path), FILE_MODE)
		f.seek_end()
		_files[day] = f
	f.store_line(JSON.stringify(line))
	_dirty = true
	written += 1
	var acct := str(line.acct)
	var pd: Dictionary = per_day.get(day, {})
	pd[acct] = int(pd.get(acct, 0)) + 1
	per_day[day] = pd
	var sd: Dictionary = seen.get(day, {})
	sd[str(line.id)] = true
	seen[day] = sd

func flush() -> void:
	if not _dirty:
		return
	_dirty = false
	for d in _files:
		(_files[d] as FileAccess).flush()

func close() -> void:
	flush()
	for d in _files:
		(_files[d] as FileAccess).close()
	_files.clear()

func tick(delta: float) -> void:
	_flush_clock += delta
	if _flush_clock >= FLUSH_EVERY:
		_flush_clock = 0.0
		flush()
	_maint_clock += delta
	if _maint_clock >= MAINT_EVERY:
		_maint_clock = 0.0
		maintain()

func rebuild() -> void:
	# the ids and counts of today and yesterday, from their files (dedupe and the daily cap survive a restart)
	seen = {}
	per_day = {}
	var t := now()
	for d in [day_of(t - 86400), day_of(t)]:
		var path := dir.path_join(d + ".jsonl")
		if not FileAccess.file_exists(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var sd := {}
		var pd := {}
		while not f.eof_reached():
			var ln := f.get_line()
			if ln == "":
				continue
			var v: Variant = JSON.parse_string(ln)
			if v is Dictionary:
				sd[str(v.get("id", ""))] = true
				var a := str(v.get("acct", ""))
				pd[a] = int(pd.get(a, 0)) + 1
		seen[d] = sd
		per_day[d] = pd

func maintain() -> void:
	# gzip what's older than 2 days, delete what's older than 90; forget ids older than yesterday
	var t := now()
	var today := day_of(t)
	var keep_from := day_of(t - KEEP_DAYS * 86400)
	var gzip_before := day_of(t - (GZIP_AFTER_DAYS - 1) * 86400)       # (today and yesterday stay plain)
	var da := DirAccess.open(dir)
	if da == null:
		return
	var gone := 0
	var zipped := 0
	for fn in da.get_files():
		var day := fn.get_slice(".", 0)
		if day.length() != 10 or not (fn.ends_with(".jsonl") or fn.ends_with(".jsonl.gz")):
			continue
		var path := dir.path_join(fn)
		if day < keep_from:
			if _files.has(day):
				(_files[day] as FileAccess).close()
				_files.erase(day)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			gone += 1
		elif fn.ends_with(".jsonl") and day < gzip_before and day != today:
			if _files.has(day):
				(_files[day] as FileAccess).close()
				_files.erase(day)
			var raw := FileAccess.get_file_as_bytes(path)
			var gz_path := path + ".gz"
			var out := FileAccess.open(gz_path, FileAccess.WRITE)
			if out == null:
				continue
			out.store_buffer(raw.compress(FileAccess.COMPRESSION_GZIP))
			out.close()
			FileAccess.set_unix_permissions(ProjectSettings.globalize_path(gz_path), FILE_MODE)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			zipped += 1
	for d in seen.keys():
		if d < day_of(t - 86400):
			seen.erase(d)
			per_day.erase(d)
	if gone + zipped > 0:
		log_fn.call("analytics: %d day file(s) gzipped, %d older than %d days deleted" % [zipped, gone, KEEP_DAYS])
