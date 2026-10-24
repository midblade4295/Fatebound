extends Node
# 0.31.212 (Kevin: "Set up HeyCatch analytics in this project following https://heycatch.ai/agents.md exactly"):
# HeyCatch (heycatch.ai), by its native install guide (/agents-native.md, which agents.md sends a native app to). Its
# ingest speaks PostHog's protocol: a Swift / Kotlin / Flutter app puts PostHog's own SDK on it. A Godot game has none
# of those, so this is the guide's plain-HTTP route ("Send to HeyCatch directly"): POST <HOST>/batch/ in the standard
# PostHog capture format, with HeyCatch's write-only ingest token, every event's properties carrying the project key
# twice -- as heycatch_project_key and as the "project" group ($groups) -- or it belongs to no project.
#
# What goes: every event the app logs for our own server (scripts/meta/analytics.gd log_ev hands each one here, its
# allowed props as they are: numbers and short words), screen views ($screen, $screen_name: the tab, "match",
# "tutorial"), a purchase granted (purchase_completed, product), and one $identify when the phone first has an account.
# distinct_id: never the account id (it is half of how the account signs in) -- "fb_" + 20 hex of a SHA-256 of it;
# before the account exists, a random "anon_" id, merged into the account's by that $identify ($anon_distinct_id).
# No name, chat text, email, device or ad id. Only while Settings > "Share anonymous usage stats" is on (off: what's
# waiting goes, nothing more -- the server's own opt_out event isn't sent here). Only on a phone (Android, iOS): a
# desktop run sends nothing unless HEYCATCH=1 (HEYCATCH=0: never), so tests and tools never reach HeyCatch.
# Sent promptly (the guide: "events held in a long offline queue can be dropped"): in memory, every FLUSH_S or BATCH
# events, and at once when the app goes to the background; older than MAX_AGE_S: dropped. 2xx = accepted; 4xx: that
# batch dropped (it would never be); no answer / 5xx: tried again, RETRY.
const Diag = preload("res://scripts/siege/siege_diag.gd")
const Platform = preload("res://scripts/meta/platform.gd")

# HeyCatch's two values, the same for every app (the guide: "safe to ship inside an app binary - not secrets")
const TOKEN := "phc_oiDt6uXiBiEA2aT43SMzMAFE9D4gMVkRP3BtvYRsmHqe"
const HOST := "https://in.heycatch.ai"
# this game's HeyCatch project (Kevin's dashboard, Install page)
const PROJECT_KEY := "hck_pk_C3_tEJ-DQtuqB8czseyEd74j-gmKBQ4G"

const FLUSH_S := 10.0
const BATCH := 50
const MAX_QUEUE := 300
const MAX_AGE_S := 3600
const RETRY := [5.0, 15.0, 30.0, 60.0, 120.0]
const TIMEOUT := 15.0

var profile
var url := HOST + "/batch/"
var force := false                    # tests: send even on a desktop (to their own url)
var retry: Array = RETRY.duplicate()
var queue: Array = []
var sent_batches := 0                 # (tests, the verification run)
var last_code := -1
var last_screen := ""
var _req: HTTPRequest = null
var _busy: Array = []                 # the batch on its way
var _clock := 0.0
var _send_at := -1.0
var _fails := 0
var _flush_next := false
var _ids := {}                        # {"anon", "ided"} -- kept beside the profile
var _ids_path := ""
var now_override := -1

func setup(p) -> void:
	profile = p
	if p != null and str(p.path) != "":
		_ids_path = str(p.path).get_basename() + ".heycatch.json"
		var t := FileAccess.get_file_as_string(_ids_path) if FileAccess.file_exists(_ids_path) else ""
		var v: Variant = JSON.parse_string(t) if t != "" else null
		if v is Dictionary:
			_ids = v

func _ready() -> void:
	_req = HTTPRequest.new()
	_req.timeout = TIMEOUT
	_req.use_threads = false
	add_child(_req)
	_req.request_completed.connect(_on_done)

static func on_phone() -> bool:
	return OS.get_name() in ["Android", "iOS"]          # (the real one: a test's Platform.forced sends nothing)

func active() -> bool:
	if OS.get_environment("HEYCATCH") == "0":
		return false
	if not (force or on_phone() or OS.get_environment("HEYCATCH") == "1"):
		return false
	return profile == null or bool(profile.d.settings.get("analytics", true))

func now() -> int:
	return now_override if now_override >= 0 else int(Time.get_unix_time_from_system())

# ---------------- who ----------------
func distinct_id() -> String:
	var acct := _acct()
	if acct != "":
		return "fb_" + _sha(acct).left(20)
	if str(_ids.get("anon", "")) == "":
		_ids.anon = "anon_" + Crypto.new().generate_random_bytes(10).hex_encode()
		_save_ids()
	return str(_ids.anon)

func _acct() -> String:
	if profile == null:
		return ""
	return str(profile.d.get("account", {}).get("id", ""))

static func _sha(s: String) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(("fatebound-heycatch:" + s).to_utf8_buffer())
	return h.finish().hex_encode()

func _check_identity() -> void:
	# the phone has an account now (or a different one): one $identify -- the anonymous id's events join it
	var acct := _acct()
	if acct == "":
		return
	var me := distinct_id()
	if str(_ids.get("ided", "")) == me:
		return
	var p := {"$set":{"plat":Platform.plat(), "build":Diag.BUILD.left(40)}}
	if str(_ids.get("anon", "")) != "":
		p["$anon_distinct_id"] = str(_ids.anon)
	_ids.ided = me
	_save_ids()
	_add("$identify", p, now())

func _save_ids() -> void:
	if _ids_path == "":
		return
	var f := FileAccess.open(_ids_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_ids))

# ---------------- events ----------------
func capture(ev: String, props := {}, ts := -1) -> void:
	# a business event (the same name and props the app logs for our own server)
	if not active():
		return
	_check_identity()
	_add(ev, props, ts if ts >= 0 else now())

func screen(screen_name: String) -> void:
	# a screen appeared (the same one again in a row: nothing)
	if not active() or screen_name == "" or screen_name == last_screen:
		return
	last_screen = screen_name
	_check_identity()
	_add("$screen", {"$screen_name":screen_name}, now())

func _add(ev: String, props: Dictionary, ts: int) -> void:
	var p := props.duplicate()
	p["heycatch_project_key"] = PROJECT_KEY
	p["$groups"] = {"project":PROJECT_KEY}
	p["$lib"] = "fatebound-godot"
	p["$app_version"] = Diag.BUILD.left(40)
	p["$os"] = Platform.os_name()
	queue.append({"event":ev, "distinct_id":distinct_id(), "timestamp":_iso(ts), "t":ts, "properties":p})
	while queue.size() > MAX_QUEUE:
		queue.pop_front()
	if queue.size() >= BATCH:
		_send_at = _clock
	elif _send_at < 0.0:
		_send_at = _clock + FLUSH_S

static func _iso(ts: int) -> String:
	return Time.get_datetime_string_from_unix_time(ts) + "Z"         # (ISO 8601, UTC)

func flush() -> void:
	# the app is going to the background: what's waiting goes now (this frame -- the next may be a while)
	if queue.is_empty():
		return
	if _busy.is_empty():
		_send()
	else:
		_flush_next = true                       # (straight after the batch on its way)

func clear() -> void:
	# Settings: the statistics turned off -- nothing waiting goes
	queue.clear()
	_send_at = -1.0

# ---------------- sending ----------------
func _process(delta: float) -> void:
	_clock += delta
	if _busy.is_empty() and _send_at >= 0.0 and _clock >= _send_at:
		_send()

func _send() -> void:
	_send_at = -1.0
	var cut := now() - MAX_AGE_S
	queue = queue.filter(func(e): return int(e.t) >= cut)
	if queue.is_empty() or _req == null or not active():
		return
	_busy = queue.slice(0, BATCH)
	var batch := []
	for e in _busy:
		batch.append({"event":e.event, "distinct_id":e.distinct_id, "timestamp":e.timestamp, "properties":e.properties})
	var body := JSON.stringify({"api_key":TOKEN, "batch":batch, "sent_at":_iso(now())})
	if _req.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body) != OK:
		_busy = []
		_retry()

func _on_done(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	last_code = code
	var keep := func(e): return not _busy.any(func(b): return is_same(b, e))
	if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
		queue = queue.filter(keep)
		sent_batches += 1
		_fails = 0
	elif result == HTTPRequest.RESULT_SUCCESS and code >= 400 and code < 500 and code != 408 and code != 429:
		queue = queue.filter(keep)               # (refused as it is: it never would be accepted)
		push_warning("heycatch: batch refused (%d)" % code)
	else:
		_busy = []
		_retry()
		return
	_busy = []
	if not queue.is_empty():
		_send_at = _clock + (0.0 if _flush_next else (0.5 if queue.size() >= BATCH else FLUSH_S))
	_flush_next = false

func _retry() -> void:
	_fails += 1
	_send_at = _clock + float(retry[mini(_fails - 1, retry.size() - 1)])
