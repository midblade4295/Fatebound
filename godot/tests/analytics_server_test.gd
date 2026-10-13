extends SceneTree
# 0.31.118 (Kevin's spec, ANALYTICS_SPEC_FOR_CLAUDE.md section 7): the server's side of the usage statistics,
# server/analytics.gd on its own (a fake account check, a clock of our choosing), then the phone against an OLDER server.
#  1. a key that doesn't open the account: nothing written; unknown events and unknown props dropped (but acknowledged);
#     a phone's online match_* dropped (the server counts those); a batch sent again written once (and again after a
#     restart: the ids are read back from the files); at most 100 a batch and the daily cap per account; the file is
#     named for the UTC day it arrived (not the phone's day); a phone clock 40 days out is clamped and marked; files 0600 in
#     a 0700 folder; a 3-day-old file gzipped (and still readable), yesterday's left as it is, a 91-day-old one deleted,
#     an 89-day-old one kept; opt-out: the opt_out event is kept, then no server events until the phone sends events
#     again (and the opt-out survives a restart); no line ever has an IP address, a name, a key or text.
#  2. the phone against an older server that doesn't know "an" (a WebSocket server that never answers): the queue
#     stays as it was and the next try waits (eco_sync's backoff); and a phone whose server never said "an":1 never
#     sends at all.
#   godot --headless --path godot -s res://tests/analytics_server_test.gd
const Analytics = preload("res://server/analytics.gd")
const Events = preload("res://scripts/meta/analytics_events.gd")
const ClientAnalytics = preload("res://scripts/meta/analytics.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Net = preload("res://scripts/siege/siege_net.gd")

const T0 := 1791849600 - 1800      # 2026-10-12 23:30 UTC (the phone, an hour ahead, already says the 13th)
const ACCT := "a1a1a1a1a1a1a1a1a1a1"
const ACCT2 := "b2b2b2b2b2b2b2b2b2b2"
const KEY := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

var fails: Array = []
var port := 8101
var srv := TCPServer.new()
var peers: Array = []
var got_an := 0
var phase := "start"
var t_phase := 0.0
var an
var p

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

class FakeEco:
	func open(id: String, key: String) -> Dictionary:
		return {"id":id} if id in ["a1a1a1a1a1a1a1a1a1a1", "b2b2b2b2b2b2b2b2b2b2"] and key == "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" else {}

static func id_n(n: int) -> String:
	return "%016x" % (0xabc000 + n)

func lines_of(path: String) -> Array:
	var out := []
	if not FileAccess.file_exists(path):
		return out
	for ln in FileAccess.get_file_as_string(path).split("\n", false):
		var v: Variant = JSON.parse_string(ln)
		if v is Dictionary:
			out.append(v)
	return out

func mode_of(path: String) -> String:
	var o := []
	OS.execute("stat", ["-c", "%a", ProjectSettings.globalize_path(path)], o)
	return str(o[0]).strip_edges() if not o.is_empty() else "?"

func _init() -> void:
	_part1()
	_part2_start()

# ---------------- 1. server/analytics.gd ----------------
func _part1() -> void:
	var state := OS.get_user_data_dir().path_join("antest-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(state)
	var dir := state.path_join("analytics")
	# old files first (the maintenance at start handles them)
	DirAccess.make_dir_recursive_absolute(dir)
	var old_days := {"d3":Analytics.day_of(T0 - 3 * 86400), "d1":Analytics.day_of(T0 - 86400), "d91":Analytics.day_of(T0 - 91 * 86400),
		"d89":Analytics.day_of(T0 - 89 * 86400)}
	for k in old_days:
		var f := FileAccess.open(dir.path_join(old_days[k] + ".jsonl"), FileAccess.WRITE)
		f.store_line(JSON.stringify({"rt":T0, "acct":ACCT, "ev":"session_online", "ts":T0, "sid":"", "b":"", "p":{}, "src":"s", "id":id_n(900 + old_days.keys().find(k))}))
		f.close()
	var gz91 := FileAccess.open(dir.path_join(Analytics.day_of(T0 - 95 * 86400) + ".jsonl.gz"), FileAccess.WRITE)
	gz91.store_buffer("{}\n".to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP))
	gz91.close()
	var a = _make(state)
	check(not FileAccess.file_exists(dir.path_join(old_days.d3 + ".jsonl")) and FileAccess.file_exists(dir.path_join(old_days.d3 + ".jsonl.gz")),
		"a 3-day-old file is gzipped at start")
	var gzb := FileAccess.get_file_as_bytes(dir.path_join(old_days.d3 + ".jsonl.gz")).decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	check(gzb.get_string_from_utf8().contains("session_online") and mode_of(dir.path_join(old_days.d3 + ".jsonl.gz")) == "600",
		"the gzipped file reads back (standard gzip), mode 0600")
	check(FileAccess.file_exists(dir.path_join(old_days.d1 + ".jsonl")), "yesterday's file stays as it is")
	check(not FileAccess.file_exists(dir.path_join(old_days.d91 + ".jsonl")) and not FileAccess.file_exists(dir.path_join(Analytics.day_of(T0 - 95 * 86400) + ".jsonl.gz")),
		"files older than 90 days are deleted (plain and gzipped)")
	check(FileAccess.file_exists(dir.path_join(old_days.d89 + ".jsonl.gz")), "an 89-day-old file is kept (gzipped)")
	check(mode_of(dir) == "700", "the analytics folder is 0700 (%s)" % mode_of(dir))
	var eco := FakeEco.new()
	# --- a wrong key: nothing
	var ev1 := [{"id":id_n(1), "ev":"session_start", "ts":T0 + 3600, "sid":"aaaa0001", "b":"0.31.118-fatebound", "p":{"cold":true, "safe_boot":false, "net":"online"}}]
	var today_path := dir.path_join("2026-10-12.jsonl")
	check(a.handle({"t":"an", "acct":ACCT, "key":"f".repeat(64), "ev":ev1}, eco).is_empty() and a.handle({"t":"an", "acct":"", "key":KEY, "ev":ev1}, eco).is_empty()
		and a.handle({"t":"an", "acct":"c".repeat(20), "key":KEY, "ev":ev1}, eco).is_empty(), "a key that doesn't open the account: refused")
	a.flush()
	check(not FileAccess.file_exists(today_path), "...and nothing written")
	# --- a batch: known, unknown, extra props, a phone's online match, a bad id
	var batch := [
		ev1[0],
		{"id":id_n(2), "ev":"forge", "ts":T0, "sid":"aaaa0001", "b":"0.31.118-fatebound",
			"p":{"item":"sword_basic", "stars":3, "name":"Kevin Real Name", "ip":"203.0.113.9", "text":"secret chat", "x":"y"}},
		{"id":id_n(3), "ev":"made_up_event", "ts":T0, "p":{"a":1}},
		{"id":id_n(4), "ev":"match_start", "ts":T0, "p":{"match":"1-1", "mode":"online", "class":"knight"}},
		{"id":id_n(5), "ev":"match_start", "ts":T0, "p":{"match":"b-1", "mode":"bots", "class":"knight"}},
		{"id":"not-hex-at-all!!", "ev":"forge", "ts":T0, "p":{}},
		{"id":id_n(6), "ev":"shop_view", "ts":T0 - 40 * 86400, "p":{"tab":"x".repeat(200)}},
		{"id":id_n(7), "ev":"level_up", "ts":T0 + 5 * 86400, "p":{"lvl":7.0}},
		"not an event",
	]
	var r: Dictionary = a.handle({"t":"an", "acct":ACCT, "key":KEY, "ev":batch}, eco)
	a.flush()
	var ok_ids: Array = r.get("ok", [])
	check(ok_ids.size() == 7 and not ok_ids.has("not-hex-at-all!!") and int(r.kept) == 5,
		"every well-formed id acknowledged (7), 5 kept (unknown event and the phone's online match dropped): %s" % str(r))
	var L := lines_of(today_path)
	check(L.size() == 5, "the file is named for the UTC day it arrived (2026-10-12), not the phone's day: %d lines" % L.size())
	var by_id := {}
	for l in L:
		by_id[str(l.id)] = l
	check(by_id.has(id_n(1)) and int(by_id[id_n(1)].ts) == T0 + 3600 and int(by_id[id_n(1)].rt) == T0 and str(by_id[id_n(1)].acct) == ACCT
		and str(by_id[id_n(1)].src) == "c" and str(by_id[id_n(1)].sid) == "aaaa0001", "a line: rt, acct (the checked one), ts, sid, src")
	check(by_id.has(id_n(2)) and (by_id[id_n(2)].p as Dictionary).keys().size() == 2 and str(by_id[id_n(2)].p.item) == "sword_basic" and int(by_id[id_n(2)].p.stars) == 3,
		"props not on the event's list are dropped (name, ip, text): %s" % str(by_id.get(id_n(2), {}).get("p", {})))
	check(not by_id.has(id_n(3)) and not by_id.has(id_n(4)) and by_id.has(id_n(5)), "unknown event dropped; a phone's online match dropped, its bots match kept")
	check(by_id.has(id_n(6)) and bool(by_id[id_n(6)].get("ts_bad", false)) and int(by_id[id_n(6)].ts) == T0 - Analytics.TS_PAST
		and str(by_id[id_n(6)].p.tab).length() == Events.MAX_STR, "a phone clock 40 days back: clamped to 30 days, marked ts_bad; a long word cut to 40")
	check(by_id.has(id_n(7)) and bool(by_id[id_n(7)].get("ts_bad", false)) and int(by_id[id_n(7)].ts) == T0 + Analytics.TS_FUTURE and typeof(by_id[id_n(7)].p.lvl) == TYPE_FLOAT and int(by_id[id_n(7)].p.lvl) == 7,
		"5 days ahead: clamped to 1 day")
	check(mode_of(today_path) == "600", "the day file is 0600 (%s)" % mode_of(today_path))
	# --- the same batch again: acknowledged, written once
	r = a.handle({"t":"an", "acct":ACCT, "key":KEY, "ev":batch}, eco)
	a.flush()
	check((r.ok as Array).size() == 7 and int(r.kept) == 0 and lines_of(today_path).size() == 5, "a batch sent again: acknowledged, nothing written twice")
	# --- at most 100 a batch
	var big := []
	for i in 150:
		big.append({"id":id_n(1000 + i), "ev":"chest_open", "ts":T0, "p":{"rarity":"rare", "src":"win"}})
	r = a.handle({"t":"an", "acct":ACCT2, "key":KEY, "ev":big}, eco)
	check((r.ok as Array).size() == 100 and int(r.kept) == 100, "150 in a batch: the first 100 taken (%d)" % (r.ok as Array).size())
	# --- the daily cap (lowered for the test)
	a.per_day_max = 110
	big = []
	for i in 30:
		big.append({"id":id_n(2000 + i), "ev":"chest_open", "ts":T0, "p":{"rarity":"rare", "src":"win"}})
	r = a.handle({"t":"an", "acct":ACCT2, "key":KEY, "ev":big}, eco)
	check((r.ok as Array).size() == 30 and int(r.kept) == 10, "an account's daily cap: 10 more kept, 20 acknowledged and dropped (%d)" % int(r.kept))
	a.server_event(ACCT2, "session_online", {})
	a.flush()
	var n2 := lines_of(today_path).filter(func(l): return str(l.acct) == ACCT2).size()
	check(n2 == 110, "the cap holds server events too (%d)" % n2)
	a.per_day_max = 2000
	# --- server events
	a.server_event(ACCT, "purchase_verified", {"product":"gems_80", "test":false, "token":"tok-secret", "order":"GPA.1234"})
	a.server_event(ACCT, "chat_send", {"kind":"global", "x":"hello secret"})
	a.server_event(ACCT, "not_an_event", {})
	a.server_event("", "session_online", {})
	a.flush()
	L = lines_of(today_path)
	var pv := L.filter(func(l): return str(l.ev) == "purchase_verified")
	var cs := L.filter(func(l): return str(l.ev) == "chat_send")
	check(pv.size() == 1 and (pv[0].p as Dictionary).keys().size() == 2 and str(pv[0].src) == "s" and Analytics.valid_id(str(pv[0].id))
		and cs.size() == 1 and (cs[0].p as Dictionary).keys() == ["kind"], "server events: only their own props (no token, order id or text), src s, an id")
	check(L.filter(func(l): return str(l.ev) == "not_an_event").is_empty(), "an unknown server event is ignored")
	# --- opt-out
	r = a.handle({"t":"an", "acct":ACCT, "key":KEY, "ev":[{"id":id_n(50), "ev":"opt_out", "ts":T0, "p":{"why":"x"}}]}, eco)
	a.flush()
	var before := lines_of(today_path).size()
	a.server_event(ACCT, "session_online", {})
	a.server_event(ACCT, "match_start", {"match":"1-1", "mode":"online", "class":"knight"})
	a.flush()
	L = lines_of(today_path)
	var oo := L.filter(func(l): return str(l.ev) == "opt_out")
	check(int(r.kept) == 1 and oo.size() == 1 and (oo[0].p as Dictionary).is_empty() and L.size() == before and a.opted.has(ACCT),
		"the opt_out event is kept (no props); after it the server writes nothing for that account")
	var opt_file := dir.path_join("opt_out.json")
	check(FileAccess.file_exists(opt_file) and mode_of(opt_file) == "600", "who opted out is kept on disk (0600)")
	# --- a restart: ids, counts and opt-outs read back
	a.close()
	var a2 = _make(state)
	r = a2.handle({"t":"an", "acct":ACCT, "key":KEY, "ev":batch}, eco)
	a2.server_event(ACCT, "session_online", {})
	a2.flush()
	check(int(r.kept) == 0 and lines_of(today_path).size() == before, "after a restart: the old batch is still known, the opt-out still holds")
	check(int(a2.per_day.get("2026-10-12", {}).get(ACCT2, 0)) == 110, "after a restart: the day's count per account is read back")
	# --- they turn it back on: their events come again, and so do the server's
	r = a2.handle({"t":"an", "acct":ACCT, "key":KEY, "ev":[{"id":id_n(60), "ev":"session_start", "ts":T0, "p":{"cold":true, "safe_boot":false, "net":"online"}}]}, eco)
	a2.server_event(ACCT, "session_online", {})
	a2.flush()
	check(int(r.kept) == 1 and not a2.opted.has(ACCT) and lines_of(today_path).size() == before + 2, "events again: the opt-out ends, server events come again")
	# --- a hello with an_off
	a2.set_opt_out(ACCT2, true)
	a2.server_event(ACCT2, "match_finish", {"match":"1-1", "mode":"online", "result":"win"})
	a2.flush()
	check(lines_of(today_path).size() == before + 2, "an account opted out by its hello: no server events")
	# --- a new UTC day: a new file
	a2.now_override = T0 + 3600
	a2.handle({"t":"an", "acct":ACCT, "key":KEY, "ev":[{"id":id_n(70), "ev":"session_end", "ts":T0 + 3600, "p":{"dur_s":60}}]}, eco)
	a2.flush()
	check(lines_of(dir.path_join("2026-10-13.jsonl")).size() == 1, "past midnight UTC: the next day's file")
	# --- 90 days later (now_override): everything older is deleted at the hourly maintenance
	a2.now_override = T0 + 92 * 86400
	a2.tick(Analytics.MAINT_EVERY + 1.0)
	var left := DirAccess.get_files_at(dir)
	var day_files := Array(left).filter(func(f): return str(f).begins_with("20"))
	check(day_files.is_empty(), "92 days on, the hourly maintenance has deleted every day file: %s" % str(left))
	# --- nothing a person could be found by
	var raw := ""
	for f in DirAccess.get_files_at(dir):
		var path := dir.path_join(f)
		raw += FileAccess.get_file_as_bytes(path).decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP).get_string_from_utf8() if f.ends_with(".gz") else FileAccess.get_file_as_string(path)
	raw += FileAccess.get_file_as_string(today_path) if FileAccess.file_exists(today_path) else ""
	var rx := RegEx.create_from_string("\\b\\d{1,3}(\\.\\d{1,3}){3}\\b|\"ip\"|Kevin|secret|tok-|GPA\\.|" + KEY)
	check(rx.search(raw) == null, "no IP address, name, chat text, token, order id or key anywhere")
	a2.close()

func _make(state: String):
	return Analytics.new(state, T0)            # (the test's clock before the files are read and tidied)

# ---------------- 2. the phone against an older server ----------------
func _part2_start() -> void:
	srv.listen(port, "127.0.0.1")
	p = Profile.new("user://antest-phone-%d.json" % Time.get_ticks_usec(), "user://none.json")
	p.load_or_create()
	p.d.account.id = ACCT
	p.d.account.key = KEY
	an = ClientAnalytics.new()
	an.auto_start = false
	an.url = "ws://127.0.0.1:%d/" % port
	an.timeout = 2.0
	an.setup(p)
	root.add_child(an)
	for i in 5:
		an.log_ev("chest_open", {"rarity":"rare", "src":"win"})
	an.start()
	phase = "no_an"

func _process(delta: float) -> bool:
	t_phase += delta
	while srv.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.accept_stream(srv.take_connection())
		peers.append(ws)
	for ws in peers:
		ws.poll()
		while ws.get_available_packet_count() > 0:
			var m := Net.decode(ws.get_packet())
			if str(m.get("t", "")) == "an":
				got_an += 1                          # (an older server: it doesn't know "an" and says nothing)
	match phase:
		"no_an":
			if t_phase > 3.0:
				check(got_an == 0 and peers.is_empty() and an.queue.size() == 5, "the server never said \"an\":1: nothing sent, the queue waits")
				an.server_ok = true
				t_phase = 0.0
				phase = "old"
		"old":
			if got_an >= 1 and an._req.is_empty() and an._fails >= 1:
				var ids: Array = an.queue.map(func(e): return str(e.id))
				check(an.queue.size() == 5 and an._send_at > an._clock + 1.0, "an older server (no \"ok\"): the queue stays (%d) and the next try waits" % an.queue.size())
				var a2 = ClientAnalytics.new()
				a2.auto_start = false
				a2.setup(p)
				check(a2.queue.map(func(e): return str(e.id)) == ids, "...and is still on disk")
				a2.free()
				_finish()
			elif t_phase > 12.0:
				check(false, "the phone tried the older server and gave up within 12 s (sent %d, fails %d)" % [got_an, an._fails])
				_finish()
	return false

func _finish() -> void:
	srv.stop()
	print("ANALYTICS_SERVER_PASS" if fails.is_empty() else "ANALYTICS_SERVER_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
