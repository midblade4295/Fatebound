extends Node
# 0.31.118 (Kevin's spec, ANALYTICS_SPEC_FOR_CLAUDE.md: self-hosted analytics on the Siege server -- what Firebase
# Analytics would do, with no SDK and no third party): the phone's side.
#
# log(ev, props) puts an event in a queue kept on disk (<profile>.analytics_q.jsonl, one JSON line each):
#   {"id": 16 random hex (the server's dedupe key), "ev", "ts": unix s, "sid": the session (8 hex), "b": Diag.BUILD,
#    "p": props -- only the ones scripts/meta/analytics_events.gd allows that event, numbers or short words}
# At most MAX_EVENTS (500) / MAX_BYTES (256 KB): when full the oldest go and are counted; the count goes up as a
# q_dropped event with the next batch. Once the server has said "an":1 (the version check or the status) and the
# phone has an account, batches of up to 100 go up on their own socket ({"t":"an", ..., "acct", "key", "ev":[...]},
# compressed like "eco"); the answer {"t":"an", "ok":[ids]} lets those go. No answer (an older server, no
# connection): the queue stays and it tries again later (eco_sync's RETRY). Sending a batch twice is safe.
# Sessions: one per time in the foreground -- session_start when the app starts or comes back, session_end when it goes
# to the background or quits (a session that never ended is closed at the next start, "lost"); clean_session at the
# next start when the last one ended properly and this start isn't a safe start (crash-free = clean / ended).
# Script errors are counted (watch_errors) and go up as one error event a session (kind script_error, n): no text.
# Settings > "Share anonymous usage stats" (settings.analytics, on by default): off clears the queue, sends one
# opt_out event (nothing else) and logs nothing more; the match and social hellos then carry "an_off" so the server
# writes nothing for this account either. No device id, ad id, IP, name, chat text or Play Games id is ever logged.
const Net = preload("res://scripts/siege/siege_net.gd")
const Platform = preload("res://scripts/meta/platform.gd")       # 0.31.132: session_start's "plat"
const Diag = preload("res://scripts/siege/siege_diag.gd")
const Events = preload("res://scripts/meta/analytics_events.gd")

const BATCH := 100
const TIMEOUT := 15.0
const RETRY := [3.0, 6.0, 15.0, 30.0, 60.0]
const BEAT := 30.0                        # s between notes of "still here" (a session that dies still has a length)
const NET_WAIT := 10.0                    # s session_start waits to learn whether the server answered

var profile
var url := OS.get_environment("SIEGE_URL") if OS.has_environment("SIEGE_URL") else Net.DEFAULT_URL
var auto_start := true                    # tests turn this off (nothing goes up until start())
var server_ok := false                    # the server said "an":1
var max_events := 500
var max_bytes := 256 * 1024
var timeout := TIMEOUT
var queue: Array = []
var bytes := 0
var dropped := 0
var sid := ""
var started := false
var q_path := ""
var meta_path := ""
var meta := {}                            # {"sid", "start", "last", "ended", "dropped", "lvl", "net"}
var now_override := -1
var _req := {}
var _send_at := 0.0
var _fails := 0
var _clock := 0.0
var _beat := 0.0
var _pending_start := {}                  # session_start waiting for the network's answer
var _pending_at := 0.0
var _errs: ErrCount = null

class ErrCount:
	# script errors this session (the app's watch_errors): only how many, never the text or a path
	extends Logger
	var n := 0
	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_SCRIPT:
			n += 1

# ---------------- setup ----------------
func setup(p) -> void:
	profile = p
	var base := str(p.path).get_basename()
	q_path = base + ".analytics_q.jsonl"
	meta_path = base + ".analytics.json"
	_load()

func _ready() -> void:
	if auto_start:
		start()

func start() -> void:
	started = true

func watch_errors() -> void:
	# the app: count script errors; each session's count goes up with its session_end (error script_error n)
	if _errs == null:
		_errs = ErrCount.new()
		OS.add_logger(_errs)

func _exit_tree() -> void:
	if _errs != null:
		OS.remove_logger(_errs)
		_errs = null

func enabled() -> bool:
	return profile == null or bool(profile.d.settings.get("analytics", true))

func has_account() -> bool:
	return profile != null and str(profile.d.account.get("id", "")) != "" and str(profile.d.account.get("key", "")) != ""

func now() -> int:
	return now_override if now_override >= 0 else int(Time.get_unix_time_from_system())

static func hex(n: int) -> String:
	return Crypto.new().generate_random_bytes(n).hex_encode()

static func hello_flags(p) -> Dictionary:
	# what a hello (match or social) adds: "an_off" when this phone opted out
	if p != null and not bool(p.d.settings.get("analytics", true)):
		return {"an_off":1}
	return {}

# ---------------- sessions ----------------
func begin_session(cold: bool, safe_boot := false, net := "") -> void:
	var prev := meta.duplicate()
	if prev.has("sid") and str(prev.sid) != "":
		if bool(prev.get("ended", false)):
			if cold and not safe_boot:
				log_ev("clean_session", {"prev_sid":str(prev.sid)})
		else:
			# the last session never said it ended (killed, crashed, or the phone switched off): its length to its last note
			log_ev("session_end", {"dur_s":maxi(0, int(prev.get("last", 0)) - int(prev.get("start", 0))), "lost":true},
				str(prev.sid), int(prev.get("last", now())))
	sid = hex(4)
	var lvl := int(profile.d.get("level", 1)) if profile != null else 1
	meta = {"sid":sid, "start":now(), "last":now(), "ended":false, "dropped":dropped, "lvl":int(meta.get("lvl", lvl))}
	_save_meta()
	_pending_start = {"cold":cold, "safe_boot":safe_boot}
	_pending_at = _clock
	if net != "":
		set_net(net == "online")
	if safe_boot:
		log_ev("error", {"kind":"boot_stuck"})

func set_net(online: bool) -> void:
	# the version check answered (or didn't): session_start goes in with what it found
	meta["net"] = "online" if online else "offline"
	if not _pending_start.is_empty():
		var ps := _pending_start
		_pending_start = {}
		log_ev("session_start", {"cold":bool(ps.cold), "safe_boot":bool(ps.safe_boot), "net":meta.net, "plat":Platform.plat()})

func end_session() -> void:
	if not _pending_start.is_empty():
		set_net(str(meta.get("net", "")) == "online")
	if sid == "" or bool(meta.get("ended", false)):
		return
	if _errs != null and _errs.n > 0:
		log_ev("error", {"kind":"script_error", "n":_errs.n})
		_errs.n = 0
	log_ev("session_end", {"dur_s":maxi(0, now() - int(meta.get("start", now())))})
	meta.ended = true
	meta.last = now()
	_save_meta()

func note_level(lvl: int) -> void:
	# a level up since the last look (the server's count arrives with the account, so it's checked whenever it does)
	if lvl > int(meta.get("lvl", lvl)):
		log_ev("level_up", {"lvl":lvl})
	if lvl != int(meta.get("lvl", -1)):
		meta.lvl = lvl
		_save_meta()

# ---------------- the queue ----------------
func log_ev(ev: String, props := {}, sid_over := "", ts_over := -1) -> void:
	if not enabled() and ev != "opt_out":
		return
	if not Events.CLIENT.has(ev):
		push_warning("analytics: unknown event " + ev)
		return
	var e := {"id":hex(8), "ev":ev, "ts":ts_over if ts_over >= 0 else now(), "sid":sid_over if sid_over != "" else sid,
		"b":Diag.BUILD.left(40), "p":Events.clean_props(Events.CLIENT[ev], props)}
	var line := JSON.stringify(e)
	queue.append(e)
	bytes += line.length() + 1
	if queue.size() > max_events or bytes > max_bytes:
		while queue.size() > 1 and (queue.size() > max_events or bytes > max_bytes):
			var old: Dictionary = queue.pop_front()
			bytes -= JSON.stringify(old).length() + 1
			dropped += 1
		meta.dropped = dropped
		_save_meta()
		_rewrite()
	else:
		_append(line)
	if _send_at <= _clock:
		_send_at = _clock + 2.0                     # (a few together; a retry already waiting keeps its time)

func set_enabled(on: bool) -> void:
	# Settings: off -- everything waiting goes, one opt_out goes up, nothing more is logged
	if on:
		return
	queue.clear()
	bytes = 0
	dropped = 0
	meta.dropped = 0
	_pending_start = {}
	_save_meta()
	_rewrite()
	log_ev("opt_out", {})
	_send_at = _clock

func ack(ids: Array, dropped_sent := 0) -> void:
	var gone := {}
	for i in ids:
		gone[str(i)] = true
	var left := []
	bytes = 0
	for e in queue:
		if not gone.has(str(e.id)):
			left.append(e)
			bytes += JSON.stringify(e).length() + 1
	queue = left
	dropped = maxi(0, dropped - dropped_sent)
	meta.dropped = dropped
	_save_meta()
	_rewrite()

func batch() -> Dictionary:
	# the next batch: {"ev": [...], "dropped": the q_dropped count it carries, "qid": its id}
	var evs := []
	var out := {"dropped":0, "qid":""}
	if dropped > 0 and enabled():
		var q := {"id":hex(8), "ev":"q_dropped", "ts":now(), "sid":sid, "b":Diag.BUILD.left(40), "p":{"n":dropped}}
		evs.append(q)
		out.dropped = dropped
		out.qid = q.id
	evs.append_array(queue.slice(0, BATCH - evs.size()))
	out["ev"] = evs
	return out

func _append(line: String) -> void:
	if q_path == "":
		return
	var f := FileAccess.open(q_path, FileAccess.READ_WRITE if FileAccess.file_exists(q_path) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(line)
	f.close()

func _rewrite() -> void:
	if q_path == "":
		return
	var f := FileAccess.open(q_path + ".tmp", FileAccess.WRITE)
	if f == null:
		return
	for e in queue:
		f.store_line(JSON.stringify(e))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(q_path + ".tmp"), ProjectSettings.globalize_path(q_path))

func _load() -> void:
	queue = []
	bytes = 0
	if q_path != "" and FileAccess.file_exists(q_path):
		var f := FileAccess.open(q_path, FileAccess.READ)
		while f != null and not f.eof_reached():
			var ln := f.get_line()
			if ln == "":
				continue
			var v: Variant = JSON.parse_string(ln)
			if v is Dictionary and str(v.get("id", "")) != "":
				queue.append(v)
				bytes += ln.length() + 1
	meta = {}
	if meta_path != "" and FileAccess.file_exists(meta_path):
		var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		if m is Dictionary:
			meta = m
	dropped = int(meta.get("dropped", 0))

func _save_meta() -> void:
	if meta_path == "":
		return
	var f := FileAccess.open(meta_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(meta))
		f.close()

# ---------------- sending ----------------
func _process(delta: float) -> void:
	_clock += delta
	if not _pending_start.is_empty() and _clock - _pending_at > NET_WAIT:
		set_net(false)                              # (no answer from the server: offline, as far as we know)
	_beat += delta
	if _beat >= BEAT and sid != "" and not bool(meta.get("ended", false)):
		_beat = 0.0
		meta.last = now()
		_save_meta()
	if not _req.is_empty():
		_poll()
		return
	if started and server_ok and has_account() and not queue.is_empty() and _clock >= _send_at:
		_send()

func _send() -> void:
	var b := batch()
	var msg := {"t":"an", "v":Net.VERSION, "build":Diag.BUILD, "acct":str(profile.d.account.id), "key":str(profile.d.account.key),
		"ev":b.ev}
	var ws := WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 16
	ws.outbound_buffer_size = 1 << 18
	if ws.connect_to_url(url) != OK:
		_failed()
		return
	_req = {"ws":ws, "sent":false, "msg":msg, "t0":_clock, "dropped":int(b.dropped)}

func _poll() -> void:
	var ws: WebSocketPeer = _req.ws
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and not bool(_req.sent):
		ws.put_packet(Net.encode(_req.msg, true))
		_req.sent = true
	while ws.get_available_packet_count() > 0:
		var m := Net.decode(ws.get_packet())
		if str(m.get("t", "")) == "an" and m.get("ok", null) is Array:
			var dr := int(_req.dropped)
			_req = {}
			if st == WebSocketPeer.STATE_OPEN:
				ws.close()
			_fails = 0
			ack(m.ok, dr)
			if not queue.is_empty():
				_send_at = _clock                    # more waiting: straight on
			return
	if st == WebSocketPeer.STATE_CLOSED or _clock - float(_req.t0) > timeout:
		_req = {}
		if st != WebSocketPeer.STATE_CLOSED:
			ws.close()
		_failed()

func _failed() -> void:
	_fails += 1
	_send_at = _clock + float(RETRY[mini(_fails - 1, RETRY.size() - 1)])
