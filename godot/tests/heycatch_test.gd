extends SceneTree
# 0.31.212 (Kevin: "Set up HeyCatch analytics ... following https://heycatch.ai/agents.md exactly"; its native guide's
# plain-HTTP route): scripts/meta/heycatch.gd against a stand-in for HeyCatch's ingest (a local HTTP server here --
# nothing reaches in.heycatch.ai).
#   - on a desktop it sends nothing unless told to (tests, tools)
#   - POST /batch/, JSON: HeyCatch's token as api_key; each event: name, distinct_id, an ISO 8601 UTC timestamp, its
#     props, and the project key twice -- heycatch_project_key and $groups.project (the guide: without them "the event
#     belongs to no project")
#   - what the app logs for our server goes too (session_start, tutorial_start: their props); screen views ($screen,
#     $screen_name; the same one twice in a row once); a purchase (purchase_completed)
#   - before an account: an "anon_" id; with one: a single $identify ($anon_distinct_id) and then "fb_" + 20 hex --
#     never the account id or its key in any request
#   - an ingest that fails (500): sent again; one that refuses (400): dropped; an event over an hour old: dropped
#   - Settings > "Share anonymous usage stats" off: what's waiting goes, nothing more is sent (not even opt_out)
#   godot --headless --path godot -s res://tests/heycatch_test.gd
const Analytics = preload("res://scripts/meta/analytics.gd")
const HeyCatch = preload("res://scripts/meta/heycatch.gd")
const Profile = preload("res://scripts/meta/profile.gd")

const PORT := 8141
const ACCT := "acct0123456789abcdef"
const KEY := "keykeykeykeykeykeykeykeykeykeykeykeykeykeykeykeykeykeykeykeykeyk"

var fails: Array = []
var srv := TCPServer.new()
var conns: Array = []              # [{peer, buf}]
var got: Array = []                # each request: {"path", "headers", "body" (parsed), "raw"}
var answers: Array = []            # status codes to answer with, in turn (then 200)
var p
var an
var hc
var phase := 0
var t := 0.0
var t_phase := 0.0
var notes := {}

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	check(srv.listen(PORT, "127.0.0.1") == OK, "a stand-in ingest on %d" % PORT)
	p = Profile.new("user://hc-%d.json" % Time.get_ticks_usec(), "user://none.json")
	p.load_or_create()
	p.d.account.id = ""
	p.d.account.key = ""
	p.d.name = "Zanzibar Quokka"
	an = Analytics.new()
	an.auto_start = false
	an.setup(p)
	root.add_child(an)
	# --- a desktop, not told to: nothing
	var off = HeyCatch.new()
	off.setup(p)
	root.add_child(off)
	off.capture("forge", {"item":"x"})
	off.screen("home")
	check(not HeyCatch.on_phone() and not off.active() and off.queue.is_empty(), "a desktop run sends nothing (not told to)")
	off.queue_free()
	hc = HeyCatch.new()
	hc.force = true
	hc.url = "http://127.0.0.1:%d/batch/" % PORT
	hc.retry = [0.4]
	hc.setup(p)
	root.add_child(hc)
	an.hc = hc

func _ingest() -> void:
	while srv.is_connection_available():
		conns.append({"peer":srv.take_connection(), "buf":PackedByteArray()})
	for c in conns.duplicate():
		var peer: StreamPeerTCP = c.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			conns.erase(c)
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			var r: Array = peer.get_data(n)
			if int(r[0]) == OK:
				c.buf.append_array(r[1])
		var s: String = (c.buf as PackedByteArray).get_string_from_utf8()
		var hend := s.find("\r\n\r\n")
		if hend < 0:
			continue
		var head := s.substr(0, hend)
		var len_ := 0
		for ln in head.split("\r\n"):
			if ln.to_lower().begins_with("content-length:"):
				len_ = int(ln.split(":", true, 1)[1].strip_edges())
		var body_bytes: PackedByteArray = (c.buf as PackedByteArray).slice(hend + 4)
		if body_bytes.size() < len_:
			continue
		var body := body_bytes.get_string_from_utf8()
		var first := head.split("\r\n")[0]
		got.append({"line":first, "head":head, "body":JSON.parse_string(body), "raw":body})
		var code: int = answers.pop_front() if not answers.is_empty() else 200
		var out := "{\"status\": \"Ok\"}" if code == 200 else "{\"error\": \"x\"}"
		var msg := "HTTP/1.1 %d X\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [code, out.length(), out]
		peer.put_data(msg.to_utf8_buffer())
		peer.disconnect_from_host()
		conns.erase(c)

func evs(req: Dictionary) -> Array:
	return (req.body as Dictionary).get("batch", []) if req.body is Dictionary else []

func _process(delta: float) -> bool:
	t += delta
	t_phase += delta
	_ingest()
	match phase:
		0:
			# no account yet: a session, a tutorial, two screens (home twice: once)
			an.begin_session(true, false, "online")
			an.log_ev("tutorial_start", {})
			hc.screen("home")
			hc.screen("home")
			hc.screen("shop")
			hc.flush()
			_go(1)
		1:
			if got.size() >= 1:
				var r: Dictionary = got[0]
				var b: Array = evs(r)
				check(str(r.line).begins_with("POST /batch/ ") and str(r.head).to_lower().contains("content-type: application/json"),
					"POST /batch/, JSON (%s)" % str(r.line))
				check(r.body is Dictionary and str(r.body.get("api_key", "")) == HeyCatch.TOKEN,
					"HeyCatch's ingest token as api_key")
				check(b.map(func(e): return str(e.event)) == ["session_start", "tutorial_start", "$screen", "$screen"],
					"the app's events, then the screens (home once): %s" % str(b.map(func(e): return e.event)))
				var keyed := b.all(_keyed)
				check(keyed and HeyCatch.PROJECT_KEY.begins_with("hck_pk_"), "every event: the project key as heycatch_project_key and $groups.project")
				var iso := RegEx.create_from_string("^\\d{4}-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\dZ$")
				check(b.all(func(e): return iso.search(str(e.timestamp)) != null), "ISO 8601 UTC timestamps: %s" % str(b.map(func(e): return e.timestamp)))
				var anon := str(b[0].distinct_id) if not b.is_empty() else ""
				notes.anon = anon
				check(anon.begins_with("anon_") and b.all(func(e): return str(e.distinct_id) == anon), "no account yet: one anonymous id (%s)" % anon)
				check(b.size() == 4 and str(b[0].properties.get("net", "")) == "online" and b[0].properties.has("cold")
					and str(b[2].properties.get("$screen_name", "")) == "home" and str(b[3].properties.get("$screen_name", "")) == "shop",
					"session_start's props; $screen_name home, shop")
				# the phone gets its account: $identify once, then the account's id
				p.d.account.id = ACCT
				p.d.account.key = KEY
				answers = [500]
				an.log_ev("forge", {"item":"sword_basic", "stars":2})
				hc.capture("purchase_completed", {"product":"gems_80"})
				hc.flush()
				_go(2)
			elif t_phase > 5.0:
				check(false, "the first batch within 5 s")
				_finish()
		2:
			if got.size() >= 3 and hc._busy.is_empty():
				var a1: Array = evs(got[1])
				var a2: Array = evs(got[2])
				var names := a2.map(func(e): return str(e.event))
				check(a1.map(func(e): return str(e.event)) == names, "the ingest failed (500): the same batch again (%s)" % str(names))
				check(names == ["$identify", "forge", "purchase_completed"], "an account: $identify first, then the events: %s" % str(names))
				var me := "fb_" + HeyCatch._sha(ACCT).left(20)
				check(a2.all(func(e): return str(e.distinct_id) == me) and me.length() == 23, "then the account's own id, not the account id (%s)" % me)
				check(not a2.is_empty() and str(a2[0].properties.get("$anon_distinct_id", "")) == str(notes.get("anon", "-")),
					"$identify carries the anonymous id (its events join the account's)")
				check(a2.size() == 3 and str(a2[1].properties.get("item", "")) == "sword_basic" and str(a2[2].properties.get("product", "")) == "gems_80",
					"forge's props, the purchase's product")
				var raw := "".join(got.map(func(r): return str(r.raw)))
				check(not raw.contains(ACCT) and not raw.contains(KEY) and not raw.contains("Quokka"),
					"never the account id, its key or the player's name in a request")
				check(hc.queue.is_empty(), "accepted: nothing left waiting")
				# a refused batch is dropped; an hour-old event never goes
				answers = [400]
				hc.capture("forge", {"item":"x"})
				hc.capture("forge", {"item":"old"}, int(Time.get_unix_time_from_system()) - 7200)
				hc.flush()
				_go(3)
			elif t_phase > 6.0:
				check(false, "the account's batch (and its retry) within 6 s: %d requests" % got.size())
				_finish()
		3:
			if got.size() >= 4 and t_phase > 1.5:
				var b4: Array = evs(got[3])
				check(got.size() == 4 and b4.size() == 1 and str(b4[0].properties.get("item", "")) == "x" and hc.queue.is_empty(),
					"refused (400): dropped, not sent again; the hour-old event never went (%d requests)" % got.size())
				# Settings > "Share anonymous usage stats" off
				hc.capture("forge", {"item":"waiting"})
				p.d.settings.analytics = false
				an.set_enabled(false)
				an.log_ev("forge", {"item":"after"})
				hc.screen("settings")
				hc.capture("purchase_completed", {"product":"gems_80"})
				hc.flush()
				check(hc.queue.is_empty() and not hc.active(), "statistics off: what was waiting is gone, nothing more is queued")
				_go(4)
			elif t_phase > 5.0:
				check(false, "the refused batch within 5 s")
				_finish()
		4:
			if t_phase > 1.5:
				check(got.size() == 4, "statistics off: no request (not even opt_out) -- %d" % got.size())
				_finish()
	return false

func _keyed(e: Dictionary) -> bool:
	var pr: Dictionary = e.get("properties", {})
	var g: Variant = pr.get("$groups", {})
	return str(pr.get("heycatch_project_key", "")) == HeyCatch.PROJECT_KEY and g is Dictionary and str(g.get("project", "")) == HeyCatch.PROJECT_KEY

func _go(ph: int) -> void:
	phase = ph
	t_phase = 0.0

func _finish() -> void:
	srv.stop()
	print("HEYCATCH_PASS" if fails.is_empty() else "HEYCATCH_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
