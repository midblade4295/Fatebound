extends SceneTree
# 0.31.118 (Kevin's spec, ANALYTICS_SPEC_FOR_CLAUDE.md sections 5, 7 and 8): the usage statistics end to end against
# the REAL server (its own process, port 8100, real time). Two accounts made by the app's own EcoSync: A shares its usage,
# B has turned it off (its hellos say "an_off").
#   - "ver" and "status" say "an":1; a batch with a made-up key is refused (4005 "an")
#   - the deploy probe (server/siege_probe.gd) with A's account: PROBE_OK, its batch acknowledged
#   - A's phone (scripts/meta/analytics.gd) sends its queue: acknowledged, the queue empties; its own online match_start
#     is not written (the server counts online matches)
#   - social: A's chat line, friend request and party invite are one event each (never the text); B's friend accept and
#     party join are not written (opted out)
#   - an online match left early: match_quit (quit_at_s); a full online match with B on A's side (a party):
#     match_start and match_finish with the result, team_n 2 and the length; quick chat; a verified purchase
#     (SIEGE_IAP_FAKE: product, test -- no token, no order id)
#   - an app below the minimum build: the server's update_screen for A, nothing for B
#   - B: not one line. Every id unique. No line has an IP address, a name, chat text, a token, an order id or a key.
#   godot --headless --path godot -s res://tests/analytics_events_test.gd
const Profile = preload("res://scripts/meta/profile.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const EcoSync = preload("res://scripts/meta/eco_sync.gd")
const Analytics = preload("res://scripts/meta/analytics.gd")
const Social = preload("res://server/social.gd")
const Diag = preload("res://scripts/siege/siege_diag.gd")

const SECRET_NAME := "Zanzibar Quokka"
const SECRET_CHAT := "meet me behind the walrus gate"
const TOKEN := "tok-analytics-e2e-0001"

var fails: Array = []
var port := 8100
var url := ""
var pid := -1
var state := ""
var phase := "boot"
var t := 0.0
var t_phase := 0.0
var pa                                  # A's profile
var pb                                  # B's profile
var sync_a
var sync_b
var an
var socks := {}                         # name -> WebSocketPeer
var inbox := {}                         # name -> [messages]
var sent := {}
var notes := {}

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	state = OS.get_user_data_dir().path_join("anev-srv-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(state)
	url = "ws://127.0.0.1:%d/" % port
	OS.set_environment("SIEGE_PORT", str(port))
	OS.set_environment("SIEGE_HOST", "127.0.0.1")
	OS.set_environment("SIEGE_LOBBY", "0.5")
	OS.set_environment("SIEGE_TEST_MATCH_S", "6")
	OS.set_environment("SIEGE_IAP_FAKE", "1")
	OS.set_environment("STATE_DIRECTORY", state)
	OS.set_environment("SIEGE_MIN_BUILD", "0.31.100")
	pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://server/siege_server.gd"])
	check(pid > 0, "server process started")

func _go(ph: String) -> void:
	phase = ph
	t_phase = 0.0

func open(name: String) -> void:
	var ws := WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 21
	ws.connect_to_url(url)
	socks[name] = ws
	inbox[name] = []
	sent.erase(name)

func send_once(name: String, msg: Dictionary, compress := false) -> bool:
	# true once the message is out
	if sent.has(name):
		return true
	var ws: WebSocketPeer = socks[name]
	if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	ws.put_packet(Net.encode(msg, compress))
	sent[name] = true
	return true

func say(name: String, msg: Dictionary) -> void:
	(socks[name] as WebSocketPeer).put_packet(Net.encode(msg))

func got(name: String, tt: String) -> Array:
	return (inbox.get(name, []) as Array).filter(func(m): return str(m.get("t", "")) == tt)

func ended(name: String) -> bool:
	for m in got(name, "s"):
		for ev in m.get("e", []):
			if str(ev.get("k", "")) == "end":
				return true
	return false

func hello(name: String, p, build := Diag.BUILD, off := false) -> Dictionary:
	var h := {"t":"hello", "v":Net.VERSION, "name":SECRET_NAME, "build":build, "acct":str(p.d.account.id), "key":str(p.d.account.key)}
	if off:
		h["an_off"] = 1
	return h

func make_phone(tag: String):
	var p = Profile.new("user://anev-%s-%d.json" % [tag, Time.get_ticks_usec()], "user://none.json")
	p.load_or_create()
	p.d.stats.matches = 3
	p.save()
	var s = EcoSync.new()
	s.url = url
	s.auto_start = false
	s.setup(p)
	root.add_child(s)
	s.start()
	return [p, s]

func _process(delta: float) -> bool:
	t += delta
	t_phase += delta
	for n in socks:
		var ws: WebSocketPeer = socks[n]
		ws.poll()
		while ws.get_available_packet_count() > 0:
			(inbox[n] as Array).append(Net.decode(ws.get_packet()))
	match phase:
		"boot":
			if t_phase > 2.5:
				var a_: Array = make_phone("a")
				pa = a_[0]
				sync_a = a_[1]
				var b_: Array = make_phone("b")
				pb = b_[0]
				sync_b = b_[1]
				pb.d.settings.analytics = false            # B: Settings > "Share anonymous usage stats" off
				pb.save()
				open("ver")
				open("status")
				open("badkey")
				_go("accounts")
		"accounts":
			send_once("ver", {"t":"ver"})
			send_once("status", {"t":"status"})
			send_once("badkey", {"t":"an", "v":Net.VERSION, "build":Diag.BUILD, "acct":"0".repeat(20), "key":"1".repeat(64),
				"ev":[{"id":"0123456789abcdef", "ev":"forge", "ts":1, "p":{}}]}, true)
			var bk: WebSocketPeer = socks.badkey
			if sync_a.enabled and sync_b.enabled and not got("ver", "ver").is_empty() and not got("status", "status").is_empty() \
					and bk.get_ready_state() == WebSocketPeer.STATE_CLOSED:
				check(int(got("ver", "ver")[0].get("an", 0)) == 1 and int(got("status", "status")[0].get("an", 0)) == 1, "\"ver\" and \"status\" say \"an\":1")
				check(bk.get_close_code() == 4005 and bk.get_close_reason() == "an" and got("badkey", "an").is_empty(),
					"a batch with a made-up key: refused (4005 \"an\"), no answer (%d '%s')" % [bk.get_close_code(), bk.get_close_reason()])
				check(str(pa.d.account.id).length() == 20 and str(pb.d.account.id).length() == 20 and pa.d.account.id != pb.d.account.id, "two accounts made by the app's EcoSync")
				_go("probe")
			elif t_phase > 15.0:
				check(false, "accounts, ver, status and the refusal within 15 s")
				_finish()
		"probe":
			# the deploy's probe, with A's account (blocking: the server is its own process)
			OS.set_environment("SIEGE_PROBE_URL", url)
			OS.set_environment("SIEGE_PROBE_ACCT", str(pa.d.account.id))
			OS.set_environment("SIEGE_PROBE_KEY", str(pa.d.account.key))
			var out := []
			OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://server/siege_probe.gd"], out, true)
			var o := "\n".join(out)
			var line := ""
			for l in o.split("\n"):
				if l.begins_with("PROBE_"):
					line = l
			check(line.begins_with("PROBE_OK") and line.contains("an=batch acknowledged"), "the probe with an account: %s" % line.right(140))
			OS.set_environment("SIEGE_PROBE_ACCT", "")
			OS.set_environment("SIEGE_PROBE_KEY", "")
			out = []
			OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://server/siege_probe.gd"], out, true)
			line = ""
			for l in "\n".join(out).split("\n"):
				if l.begins_with("PROBE_"):
					line = l
			check(line.begins_with("PROBE_OK") and line.contains("made-up key refused"), "the probe without one writes nothing: %s" % line.right(120))
			# A's phone: a few events, then they go up
			an = Analytics.new()
			an.auto_start = false
			an.url = url
			an.setup(pa)
			root.add_child(an)
			an.begin_session(true, false, "online")
			an.log_ev("tutorial_start", {})
			an.log_ev("forge", {"item":"sword_basic", "stars":2})
			an.log_ev("match_start", {"match":"x", "mode":"online", "class":"knight"})   # (the server's to count)
			notes["queued"] = an.queue.size()
			an.server_ok = true
			an.start()
			_go("phone")
		"phone":
			if an.queue.is_empty() and an._req.is_empty():
				check(int(notes.queued) == 4, "A's phone sent its %d events: acknowledged, the queue is empty" % int(notes.queued))
				open("so_a")
				open("so_b")
				_go("social")
			elif t_phase > 10.0:
				check(false, "A's queue went up within 10 s (%d left, fails %d)" % [an.queue.size(), an._fails])
				_finish()
		"social":
			send_once("so_a", {"t":"so", "k":"hi", "v":Net.VERSION, "acct":str(pa.d.account.id), "key":str(pa.d.account.key)})
			send_once("so_b", {"t":"so", "k":"hi", "v":Net.VERSION, "acct":str(pb.d.account.id), "key":str(pb.d.account.key), "an_off":1})
			var A := Social.pid_of(str(pa.d.account.id))
			var B := Social.pid_of(str(pb.d.account.id))
			var step := int(notes.get("so_step", 0))
			if t_phase > 0.6 and step == 0:
				say("so_a", {"t":"so", "k":"chat", "ch":"global", "x":SECRET_CHAT})
				say("so_a", {"t":"so", "k":"add", "pid":B})
				notes.so_step = 1
			elif t_phase > 1.2 and step == 1:
				say("so_b", {"t":"so", "k":"add", "pid":A})          # (B accepts: friends)
				notes.so_step = 2
			elif t_phase > 1.8 and step == 2:
				say("so_a", {"t":"so", "k":"invite", "pid":B})
				notes.so_step = 3
			elif t_phase > 2.4 and step == 3:
				var inv := (inbox.so_b as Array).filter(func(m): return str(m.get("k", "")) == "inv")
				check(not inv.is_empty(), "B got A's party invite")
				if not inv.is_empty():
					say("so_b", {"t":"so", "k":"join", "party":str(inv[0].party)})
				notes.so_step = 4
			elif t_phase > 3.0 and step == 4:
				open("m_a")
				_go("quit_match")
		"quit_match":
			# A plays a little and leaves before the end
			send_once("m_a", hello("m_a", pa))
			if not got("m_a", "welcome").is_empty() and got("m_a", "s").size() >= 10:
				(socks.m_a as WebSocketPeer).close()
				socks.erase("m_a")
				_go("quit_wait")
			elif t_phase > 15.0:
				check(false, "A seated within 15 s")
				_finish()
		"quit_wait":
			if t_phase > 1.0:
				open("m_a")
				open("m_b")
				_go("match")
		"match":
			send_once("m_a", hello("m_a", pa))
			send_once("m_b", hello("m_b", pb, Diag.BUILD, true))
			if not got("m_a", "welcome").is_empty() and not notes.has("qc") and got("m_a", "s").size() >= 5:
				say("m_a", {"t":"qc", "i":0})
				notes.qc = true
			if ended("m_a"):
				check(not got("m_b", "welcome").is_empty(), "B played the match too")
				(socks.m_a as WebSocketPeer).close()
				(socks.m_b as WebSocketPeer).close()
				open("iap")
				open("old_a")
				open("old_b")
				_go("after")
			elif t_phase > 30.0:
				check(false, "the online match ended within 30 s")
				_finish()
		"after":
			send_once("iap", {"t":"iap", "v":Net.VERSION, "product":"gems_80", "token":TOKEN, "acct":str(pa.d.account.id), "key":str(pa.d.account.key)})
			send_once("old_a", hello("old_a", pa, "0.31.90-fatebound"))
			send_once("old_b", hello("old_b", pb, "0.31.90-fatebound", true))
			if not got("iap", "iap").is_empty() and not got("old_a", "bye").is_empty() and not got("old_b", "bye").is_empty():
				check(bool(got("iap", "iap")[0].get("ok", false)), "the purchase was granted (SIEGE_IAP_FAKE)")
				check(str(got("old_a", "bye")[0].get("why", "")) == "version", "an app below the minimum build is sent to the update screen")
				_go("flush")
			elif t_phase > 20.0:
				check(false, "purchase and update answers within 20 s")
				_finish()
		"flush":
			if t_phase > 2.0:
				_check_file()
				_finish()
	return false

func _check_file() -> void:
	var dir := state.path_join("analytics")
	var L := []
	var raw := ""
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".jsonl"):
			var s := FileAccess.get_file_as_string(dir.path_join(f))
			raw += s
			for ln in s.split("\n", false):
				var v: Variant = JSON.parse_string(ln)
				if v is Dictionary:
					L.append(v)
	var A := str(pa.d.account.id)
	var B := str(pb.d.account.id)
	var la := L.filter(func(l): return str(l.acct) == A and not str(l.b).ends_with("-probe"))
	var lb := L.filter(func(l): return str(l.acct) == B)
	var probe := L.filter(func(l): return str(l.b).ends_with("-probe"))
	print("  lines: %d (A %d, B %d, probe %d)" % [L.size(), la.size(), lb.size(), probe.size()])
	for l in la:
		print("    %s %s %s" % [l.src, l.ev, JSON.stringify(l.p)])
	var of := func(ev: String, src: String) -> Array:
		return la.filter(func(l): return str(l.ev) == ev and str(l.src) == src)
	check(probe.size() == 1 and str(probe[0].acct) == A and str(probe[0].ev) == "error", "the probe's one event, marked by its build")
	check(of.call("session_start", "c").size() == 1 and of.call("tutorial_start", "c").size() == 1 and of.call("forge", "c").size() == 1,
		"A's phone events are in the day file")
	check(of.call("match_start", "c").is_empty(), "A's phone's online match_start was not written (no double count)")
	check(of.call("session_online", "s").size() >= 2, "session_online for each match hello (%d)" % of.call("session_online", "s").size())
	var ms: Array = of.call("match_start", "s")
	var mq: Array = of.call("match_quit", "s")
	var mf: Array = of.call("match_finish", "s")
	check(ms.size() == 2 and ms.all(func(l): return str(l.p.mode) == "online" and str(l.p.class) != "" and str(l.p.match).contains("-")),
		"the server's match_start, one per match played: %s" % str(ms.map(func(l): return l.p)))
	check(mq.size() == 1 and int(mq[0].p.quit_at_s) >= 0 and int(mq[0].p.quit_at_s) <= 10 and str(mq[0].p.match) == str(ms[0].p.match) if mq.size() == 1 and ms.size() == 2 else false,
		"leaving early: match_quit with quit_at_s (%s)" % str(mq.map(func(l): return l.p)))
	var f0: Dictionary = mf[0].p if mf.size() == 1 else {}
	check(mf.size() == 1 and str(f0.get("result", "")) in ["win", "loss", "draw"] and int(f0.get("team_n", 0)) == 2 and int(f0.get("dur_s", -1)) >= 3
		and int(f0.get("dur_s", 99)) <= 20 and str(f0.get("class0", "")) != "" and str(f0.get("match", "")) == str(ms[1].p.match) if ms.size() == 2 else false,
		"the full match: match_finish with result, team_n 2 (B on A's side), length, classes: %s" % str(f0))
	check(of.call("quick_chat", "s").size() == 1 and int(of.call("quick_chat", "s")[0].p.i) == 0, "quick chat: one event, its index")
	var pv: Array = of.call("purchase_verified", "s")
	# (0.31.131: and which store -- "google" here, "apple" for the App Store)
	check(pv.size() == 1 and str(pv[0].p.product) == "gems_80" and str(pv[0].p.get("store", "")) == "google" and (pv[0].p as Dictionary).keys().size() == 3,
		"the purchase: product, test and store only: %s" % str(pv.map(func(l): return l.p)))
	check(of.call("chat_send", "s").size() == 1 and str(of.call("chat_send", "s")[0].p.kind) == "global" and of.call("friend_add", "s").size() == 1
		and of.call("party_create", "s").size() == 1 and of.call("party_invite", "s").size() == 1 and of.call("friend_accept", "s").is_empty(),
		"social: A's chat line, request and invite -- one event each")
	var us: Array = of.call("update_screen", "s")
	check(us.size() == 1 and str(us[0].p.from_build) == "0.31.90-fatebound" and str(us[0].p.need) == "0.31.100", "below the minimum build: the server's update_screen for A")
	check(lb.is_empty(), "B (opted out): not one line (%s)" % str(lb.map(func(l): return l.ev)))
	var ids := {}
	for l in L:
		ids[str(l.id)] = true
	check(ids.size() == L.size(), "every id is unique (%d lines)" % L.size())
	var rx := RegEx.create_from_string("\\b\\d{1,3}(\\.\\d{1,3}){3}\\b|\"ip\"|\"order\"|\"token\"|\"name\"|tok-|GPA\\.")
	check(rx.search(raw) == null and not raw.contains(SECRET_NAME) and not raw.contains(SECRET_CHAT) and not raw.contains("walrus")
		and not raw.contains(str(pa.d.account.key)) and not raw.contains(str(pb.d.account.key)),
		"no IP address, name, chat text, token, order id or key in any line")

func _finish() -> void:
	if pid > 0:
		OS.kill(pid)
		OS.execute("kill", ["-9", str(pid)])
		pid = -1
	print("ANALYTICS_EVENTS_PASS" if fails.is_empty() else "ANALYTICS_EVENTS_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
