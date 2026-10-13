extends RefCounted
# 0.31.120 (Kevin: "SEND TO DEVELOPER"): a player sends the game's diagnostics log (Settings > SEND TO DEVELOPER, every
# send asked for). A phone sends it on its own socket, no hello, zstd-compressed (Net.encode(msg, true)):
#   {"t":"diag", "v", "acct"?, "key"? (when it has an account), "name", "build", "dev": {"model", "os", "gpu"},
#    "note" (what went wrong, the player's words, optional), "log" (siege_diag.gd read_logs)}
#   -> {"t":"diag", "ok": true, "id": "7F3A9C"} or {"ok": false, "why": "busy" | "empty" | "full"}
# Kept as <state>/diag/YYYYMMDD-HHMMSS-<id>.txt: a JSON header line, then the log. tools/diag_reports.py lists and shows
# them. The account id is kept only when the key opened it (otherwise the report is "anonymous": a phone that can't
# get an account -- stuck at start -- can still send). Limits: PER_HOUR from one account or one address, PER_DAY in
# all, the newest KEEP_FILES / KEEP_BYTES kept.
const MAX_LOG := 400000
const MAX_NOTE := 500
const PER_HOUR := 4
const PER_DAY := 300
const KEEP_FILES := 1000
const KEEP_BYTES := 80 * 1024 * 1024
var keep_files := KEEP_FILES
var keep_bytes := KEEP_BYTES

var dir := ""
var now_override := -1
var log_fn: Callable = func(_s): pass
var _recent := {}            # account id or "ip:<address>" -> [unix times]
var _day := ""
var _day_n := 0

func _init(state_dir := "") -> void:
	var state := state_dir
	if state == "":
		state = OS.get_environment("STATE_DIRECTORY") if OS.has_environment("STATE_DIRECTORY") else "user://"
	dir = state.path_join("diag")
	DirAccess.make_dir_recursive_absolute(dir)

func now() -> int:
	return now_override if now_override >= 0 else int(Time.get_unix_time_from_system())

static var _ctl: RegEx = null

static func clean(s: String, n: int) -> String:
	# printable text only (keeps newlines and tabs), at most n characters
	if _ctl == null:
		_ctl = RegEx.create_from_string("[\\x00-\\x08\\x0B-\\x1F\\x7F]")
	return _ctl.sub(s.left(n), "", true)

func handle(msg: Dictionary, eco, address: String) -> Dictionary:
	var t := now()
	var log_text := clean(str(msg.get("log", "")), MAX_LOG)
	var note := clean(str(msg.get("note", "")), MAX_NOTE).strip_edges()
	if log_text.strip_edges() == "" and note == "":
		return {"t":"diag", "ok":false, "why":"empty"}
	var acct := ""
	var a := str(msg.get("acct", ""))
	if a != "" and eco != null and not eco.open(a, str(msg.get("key", ""))).is_empty():
		acct = a
	var who := acct if acct != "" else "ip:" + address
	var times: Array = (_recent.get(who, []) as Array).filter(func(x): return t - int(x) < 3600)
	var day := Time.get_date_string_from_unix_time(t)
	if day != _day:
		_day = day
		_day_n = 0
	if times.size() >= PER_HOUR or _day_n >= PER_DAY:
		_recent[who] = times
		return {"t":"diag", "ok":false, "why":"busy"}
	times.append(t)
	_recent[who] = times
	_day_n += 1
	var id := Crypto.new().generate_random_bytes(3).hex_encode().to_upper()
	var dev: Dictionary = msg.get("dev", {}) if msg.get("dev", {}) is Dictionary else {}
	var head := {"id":id, "at":t, "acct":acct, "name":clean(str(msg.get("name", "")), 24), "build":clean(str(msg.get("build", "")), 40),
		"model":clean(str(dev.get("model", "")), 60), "os":clean(str(dev.get("os", "")), 60), "gpu":clean(str(dev.get("gpu", "")), 80),
		"note":note, "bytes":log_text.length()}
	var stamp := Time.get_datetime_string_from_unix_time(t).replace("-", "").replace(":", "").replace("T", "-")
	var path := dir.path_join("%s-%s.txt" % [stamp, id])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"t":"diag", "ok":false, "why":"full"}
	f.store_string(JSON.stringify(head) + "\n" + log_text)
	f.close()
	_prune()
	log_fn.call("diag report %s from %s (%s, %s, %d chars%s)" % [id, acct if acct != "" else "anonymous", head.build, head.model,
		log_text.length(), ", with a note" if note != "" else ""])
	return {"t":"diag", "ok":true, "id":id}

func list_files() -> Array:
	# oldest first
	var out := []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for fn in da.get_files():
		if fn.ends_with(".txt"):
			out.append(fn)
	out.sort()
	return out

func _prune() -> void:
	var files := list_files()
	var total := 0
	var sizes := {}
	for fn in files:
		var fa := FileAccess.open(dir.path_join(fn), FileAccess.READ)
		sizes[fn] = fa.get_length() if fa != null else 0
		total += int(sizes[fn])
	while not files.is_empty() and (files.size() > keep_files or total > keep_bytes):
		var fn: String = files.pop_front()
		total -= int(sizes[fn])
		DirAccess.remove_absolute(dir.path_join(fn))
