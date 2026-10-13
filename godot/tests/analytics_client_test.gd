extends SceneTree
# 0.31.118 (Kevin's spec, ANALYTICS_SPEC_FOR_CLAUDE.md section 7): the phone's side of the usage statistics,
# scripts/meta/analytics.gd on its own (nothing is sent: auto_start off, no server).
#   - an event: a 16-hex id, the session, the build, only its own props (a name, chat text or IP never get in; a long
#     word is cut to 40); an unknown event isn't logged
#   - the queue cap (events and bytes): the oldest go and are counted; the count goes up first in the next batch as
#     q_dropped; a batch is at most 100
#   - the queue and the dropped count survive a restart (read back from disk)
#   - an answer lets go of exactly the acknowledged ids
#   - sessions: session_start waits for the network's answer; session_end with its length; clean_session at the next
#     cold start (not after a safe start, which logs error boot_stuck); a session that never ended is closed "lost" at
#     the next start with its last note's time; level_up when the level goes up
#   - opt-out: everything waiting goes, one opt_out (no props), nothing more logged; the hellos say "an_off"
#   - the Settings toggle ("Share anonymous usage stats", PRIVACY) is in the real Settings screen and turns it off
#   godot --headless --path godot -s res://tests/analytics_client_test.gd
const Analytics = preload("res://scripts/meta/analytics.gd")
const Events = preload("res://scripts/meta/analytics_events.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Diag = preload("res://scripts/siege/siege_diag.gd")

var fails: Array = []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func make(path: String, p) -> Node:
	var a = Analytics.new()
	a.auto_start = false
	a.setup(p)
	return a

func evs(a, name: String) -> Array:
	return a.queue.filter(func(e): return str(e.ev) == name)

func _init() -> void:
	var path := "user://anclient-%d.json" % Time.get_ticks_usec()
	var p = Profile.new(path, "user://none.json")
	p.load_or_create()
	p.d.account.id = "a".repeat(20)
	p.d.account.key = "k".repeat(64)
	var a = make(path, p)
	a.now_override = 1791800000
	# --- an event
	a.sid = "0badc0de"
	a.log_ev("forge", {"item":"sword_basic", "stars":3, "name":"Kevin", "text":"hello there", "ip":"10.0.0.7"})
	var e: Dictionary = a.queue[0]
	check(Events.CLIENT.has("forge") and str(e.id).length() == 16 and str(e.id).is_valid_hex_number() and str(e.sid) == "0badc0de"
		and str(e.b) == Diag.BUILD and int(e.ts) == 1791800000, "an event: id (16 hex), session, build, time")
	check((e.p as Dictionary).keys() == ["item", "stars"], "only the event's own props (no name, text or IP): %s" % str(e.p))
	a.log_ev("shop_view", {"tab":"x".repeat(100)})
	check(str(a.queue[1].p.tab).length() == 40, "a long word is cut to 40")
	a.log_ev("made_up", {"a":1})
	check(a.queue.size() == 2, "an unknown event isn't logged")
	# no prop on any event's list could carry a name or text
	var bad := ["name", "text", "x", "msg", "chat", "ip", "token", "order", "device", "email", "pid"]
	var leaks := []
	for t in [Events.CLIENT, Events.SERVER]:
		for k in t:
			for prop in t[k]:
				if str(prop) in bad:
					leaks.append("%s.%s" % [k, prop])
	check(leaks.is_empty(), "no event may carry a name, text, IP, token or order id: %s" % str(leaks))
	# --- the cap: events
	a.queue.clear()
	a.bytes = 0
	a._rewrite()
	a.max_events = 10
	for i in 15:
		a.log_ev("level_up", {"lvl":i})
	check(a.queue.size() == 10 and a.dropped == 5 and int(a.queue[0].p.lvl) == 5 and int(a.queue[9].p.lvl) == 14,
		"500 events at most (10 here): the oldest 5 go and are counted")
	# --- the cap: bytes
	a.max_events = 500
	a.max_bytes = 1000
	for i in 20:
		a.log_ev("chest_open", {"rarity":"legendary", "src":"win"})
	check(a.bytes <= 1000 and a.dropped > 5 and a.queue.size() < 30, "256 KB at most (1 KB here): %d bytes, %d dropped" % [a.bytes, a.dropped])
	a.max_bytes = 256 * 1024
	# --- a restart
	var ids: Array = a.queue.map(func(x): return str(x.id))
	var dropped_before := int(a.dropped)
	var b = make(path, p)
	check(b.queue.map(func(x): return str(x.id)) == ids and int(b.dropped) == dropped_before and b.bytes > 0,
		"the queue and the dropped count are read back after a restart (%d events, %d dropped)" % [b.queue.size(), b.dropped])
	b.free()
	# --- the batch: q_dropped first, at most 100
	for i in 150:
		a.log_ev("chest_open", {"rarity":"rare", "src":"win"})
	var bt: Dictionary = a.batch()
	check((bt.ev as Array).size() == 100 and str(bt.ev[0].ev) == "q_dropped" and int(bt.ev[0].p.n) == a.dropped and int(bt.dropped) == a.dropped,
		"a batch: the dropped count first (q_dropped %d), 100 at most" % int(a.dropped))
	# --- an answer lets go of exactly what it names
	var n0: int = a.queue.size()
	var acked := []
	for i in range(0, 40, 2):
		acked.append(str(a.queue[i].id))
	var kept_id := str(a.queue[1].id)
	a.ack(acked + [str(bt.qid), "ffffffffffffffff"], int(bt.dropped))
	check(a.queue.size() == n0 - 20 and a.dropped == 0 and a.queue.any(func(x): return str(x.id) == kept_id)
		and not a.queue.any(func(x): return acked.has(str(x.id))), "an answer lets go of the 20 acknowledged ids only; the dropped count is reported")
	var c = make(path, p)
	check(c.queue.size() == n0 - 20 and int(c.dropped) == 0, "...and that's on disk too")
	c.free()
	# --- sessions
	a.queue.clear()
	a.bytes = 0
	a.meta = {}
	a.begin_session(true, false)
	var s1: String = a.sid
	check(s1.length() == 8 and evs(a, "session_start").is_empty() and evs(a, "clean_session").is_empty(), "a first start: no session_start until the network answers")
	a.set_net(true)
	var ss := evs(a, "session_start")
	check(ss.size() == 1 and bool(ss[0].p.cold) and not bool(ss[0].p.safe_boot) and str(ss[0].p.net) == "online", "session_start: cold, not a safe start, online")
	a.now_override += 125
	a.end_session()
	var se := evs(a, "session_end")
	check(se.size() == 1 and int(se[0].p.dur_s) == 125 and str(se[0].sid) == s1, "session_end with its length (125 s)")
	a.end_session()
	check(evs(a, "session_end").size() == 1, "ending twice counts once")
	a.begin_session(false, false, "online")                   # back from the background
	check(evs(a, "clean_session").is_empty() and evs(a, "session_start").size() == 2 and not bool(evs(a, "session_start")[1].p.cold),
		"back from the background: a new warm session (no clean_session)")
	a.now_override += 40
	a.end_session()
	a.begin_session(true, false, "offline")                   # the next cold start after a clean end
	var cl := evs(a, "clean_session")
	check(cl.size() == 1 and str(cl[0].p.prev_sid) != "" and str(evs(a, "session_start")[2].p.net) == "offline", "a cold start after a clean end: clean_session (prev %s)" % str(cl[0].p.prev_sid if not cl.is_empty() else ""))
	var s3: String = a.sid
	a.meta.last = a.now() + 70                                # its last note 70 s in; then the phone dies
	a._save_meta()
	var d = make(path, p)
	d.now_override = a.now() + 3600
	d.begin_session(true, false)
	var lost: Array = evs(d, "session_end").filter(func(x): return bool(x.p.get("lost", false)))
	check(lost.size() == 1 and str(lost[0].sid) == s3 and int(lost[0].p.dur_s) == 70 and evs(d, "clean_session").size() == 1,
		"a session that never ended: closed 'lost' at the next start (70 s, its own session id); no new clean_session")
	d.watch_errors()
	d._errs.n = 3                                             # (three script errors this session: a real one would fail the run)
	d.end_session()
	var se3 := evs(d, "error").filter(func(x): return str(x.p.kind) == "script_error")
	check(se3.size() == 1 and int(se3[0].p.n) == 3 and (se3[0].p as Dictionary).size() == 2 and d._errs.n == 0, "script errors: how many, with the session's end (no text)")
	d.begin_session(true, true)
	check(evs(d, "clean_session").size() == 1 and d.queue.any(func(x): return str(x.ev) == "error" and str(x.p.kind) == "boot_stuck"),
		"a safe start: no clean_session, error boot_stuck")
	d.note_level(int(d.meta.lvl) + 2)
	check(evs(d, "level_up").size() == 1 and int(evs(d, "level_up")[0].p.lvl) == int(d.meta.lvl), "level_up when the level goes up")
	d.note_level(int(d.meta.lvl))
	check(evs(d, "level_up").size() == 1, "...once")
	d.free()
	# --- opt-out
	check(Analytics.hello_flags(p).is_empty(), "on: the hellos carry nothing extra")
	p.d.settings.analytics = false
	a.set_enabled(false)
	check(a.queue.size() == 1 and str(a.queue[0].ev) == "opt_out" and (a.queue[0].p as Dictionary).is_empty() and a.dropped == 0,
		"off: the queue is cleared, one opt_out goes (no props)")
	a.log_ev("forge", {"item":"x", "stars":1})
	a.begin_session(true, false, "online")
	a.end_session()
	a.dropped = 7
	check(a.queue.size() == 1 and (a.batch().ev as Array).size() == 1, "off: nothing more is logged (not even the dropped count)")
	check(Analytics.hello_flags(p) == {"an_off":1}, "off: the match and social hellos say an_off")
	var e2 = make(path, p)
	check(e2.queue.size() == 1 and str(e2.queue[0].ev) == "opt_out", "...and after a restart only the opt_out is waiting")
	e2.free()
	p.d.settings.analytics = true
	a.dropped = 0
	a.log_ev("forge", {"item":"x", "stars":1})
	check(evs(a, "forge").size() == 1, "on again: logging again")
	a.free()
	_settings_toggle(path)

func _settings_toggle(path: String) -> void:
	# the real Settings screen has the toggle, under PRIVACY
	var src := FileAccess.get_file_as_string("res://scripts/app/screens.gd")
	check(src.contains("\"Share anonymous usage stats\"") and src.contains("UI2.divider(px, \"PRIVACY\"") and src.contains("app.analytics.set_enabled(on)"),
		"Settings has \"Share anonymous usage stats\" under PRIVACY, and it calls set_enabled")
	for f in [path, path.get_basename() + ".analytics_q.jsonl", path.get_basename() + ".analytics.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	print("ANALYTICS_CLIENT_PASS" if fails.is_empty() else "ANALYTICS_CLIENT_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
