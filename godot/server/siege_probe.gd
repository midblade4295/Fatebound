extends SceneTree
# Health probe for the Siege server. Connects like a player, expects a welcome and snapshots,
# then leaves (its unit goes back to a bot). 0.31.82: it first asks for the "status" (Home's players online) on a
# second connection, and waits out the lobby countdown (20 s on the live server) before its welcome.
#   godot --headless --path <project> -s res://server/siege_probe.gd
# Env: SIEGE_PROBE_URL (default ws://127.0.0.1:8082/fatebound/siege/ws).
#      SIEGE_PROBE_BUILD: the app build the probe says in its hello (default "<server SERVER_BUILD>-probe", i.e. current,
#      so a min-build server lets it in). SIEGE_PROBE_EXPECT=update: the probe plays an outdated app and passes only if
#      the server refuses it as "update required" (bye why=version, need > protocol, close 4001 "version:<need>").
#      0.31.118: when the status says "an":1 (usage statistics), one "an" batch goes up on a third connection.
#      SIEGE_PROBE_ACCT + SIEGE_PROBE_KEY (a test account of your own; never committed): one probe event, build
#      "<build>-probe" (the report leaves those out), and the server must answer {"t":"an","ok":[its id]}. Without them the
#      probe makes no account and writes nothing: a made-up key must be refused (close 4005 "an", no "ok").
# Prints PROBE_OK and exits 0 on success; PROBE_FAIL <reason> and exits 1 otherwise.
const Net = preload("res://scripts/siege/siege_net.gd")
const Server = preload("res://server/siege_server.gd")

var url := "ws://127.0.0.1:%d/fatebound/siege/ws" % Net.DEFAULT_PORT
var ws := WebSocketPeer.new()
var t := 0.0
var sent := false
var welcome := {}
var snaps := 0
var lobby_n := 0
var stat_ws := WebSocketPeer.new()
var stat_sent := false
var status := {}
var build := Server.SERVER_BUILD + "-probe"
var expect_update := false
var bye := {}
var an_ws := WebSocketPeer.new()
var an_state := ""                                    # "" (not yet), "sent", "ok", "refused", "skip"
var an_id := ""
var an_acct := OS.get_environment("SIEGE_PROBE_ACCT")
var an_key := OS.get_environment("SIEGE_PROBE_KEY")
var an_note := ""

func _init() -> void:
	if OS.has_environment("SIEGE_PROBE_URL"):
		url = OS.get_environment("SIEGE_PROBE_URL")
	if OS.has_environment("SIEGE_PROBE_BUILD"):
		build = OS.get_environment("SIEGE_PROBE_BUILD")
	expect_update = OS.get_environment("SIEGE_PROBE_EXPECT") == "update"
	ws.inbound_buffer_size = 1 << 20
	if ws.connect_to_url(url) != OK:
		_done(false, "connect_to_url failed for " + url)
	stat_ws.connect_to_url(url)

func _done(ok: bool, why: String) -> void:
	if ok and expect_update:
		print("PROBE_OK %s build=%s refused as update required: need=%s close=%d '%s' min_build=%s msg=%s" % [url, build, str(bye.get("need", "?")),
			ws.get_close_code(), ws.get_close_reason(), str(bye.get("min_build", "?")), str(bye.get("msg", ""))])
	elif ok:
		print("PROBE_OK %s build=%s unit=%s match=%s snapshots=%d lobby_msgs=%d status=%s an=%s" % [url, build, welcome.get("you", "?"), welcome.get("match", "?"), snaps,
			lobby_n, str(status) if not status.is_empty() else "none (a server before 0.31.82)", an_note])
	else:
		print("PROBE_FAIL %s: %s" % [url, why])
	# 0.31.120: leave cleanly (a dropped connection would have its seat held for a minute)
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.put_packet(Net.encode({"t":"leave"}))
	ws.close(1000, "leave")
	for i in 20:
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			break
		OS.delay_msec(25)
	quit(0 if ok else 1)

func _process(d: float) -> bool:
	t += d
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and not sent:
		sent = true
		ws.put_packet(Net.encode({"t":"hello", "v":Net.VERSION, "name":"probe", "build":build, "five":Net.FIVE}))   # (0.31.170: a 5v5 app)
	stat_ws.poll()
	if stat_ws.get_ready_state() == WebSocketPeer.STATE_OPEN and not stat_sent:
		stat_sent = true
		stat_ws.put_packet(Net.encode({"t":"status"}))
	while stat_ws.get_available_packet_count() > 0:
		var sm := Net.decode(stat_ws.get_packet())
		if str(sm.get("t", "")) == "status":
			status = sm
			print("PROBE status: online=%d in_match=%d waiting=%d lobby=%.0f" % [int(sm.get("online", 0)), int(sm.get("in_match", 0)), int(sm.get("waiting", 0)), float(sm.get("lobby", -1))])
	_an_step()
	if an_state == "fail":
		_done(false, an_note)
		return false
	while ws.get_available_packet_count() > 0:
		var m := Net.decode(ws.get_packet())
		match str(m.get("t", "")):
			"lobby": lobby_n += 1
			"welcome": welcome = m
			"s": snaps += 1
			"bye":
				bye = m
				if not expect_update:
					_done(false, "server said bye: " + str(m.get("why", "")))
					return false
	if expect_update:
		if not welcome.is_empty():
			_done(false, "expected an update-required refusal for build %s, got a welcome" % build)
		elif st == WebSocketPeer.STATE_CLOSED:
			var need := int(bye.get("need", -1))
			var ok := str(bye.get("why", "")) == "version" and need > Net.VERSION and ws.get_close_code() == Net.CLOSE_VERSION \
				and ws.get_close_reason() == "version:%d" % need
			_done(ok, "refusal was bye=%s close=%d '%s'" % [str(bye), ws.get_close_code(), ws.get_close_reason()])
		elif t > 15.0:
			_done(false, "no refusal within 15 s for build %s (lobby msgs %d)" % [build, lobby_n])
		return false
	if not welcome.is_empty() and snaps >= 3 and an_state in ["ok", "refused", "skip"]:
		_done(true, "")
	elif st == WebSocketPeer.STATE_CLOSED:
		_done(false, "connection closed (code %d)" % ws.get_close_code())
	elif t > 35.0:                                     # (the lobby countdown is 20 s)
		_done(false, "timeout (state %d, welcome %s, snapshots %d)" % [st, str(not welcome.is_empty()), snaps])
	return false

func _an_step() -> void:
	# 0.31.118: the usage statistics socket (only on a server whose status says "an":1)
	if an_state == "":
		if status.is_empty():
			if t > 10.0:
				an_state = "skip"
				an_note = "not checked (no status)"
			return
		if int(status.get("an", 0)) != 1:
			an_state = "skip"
			an_note = "not on this server"
			return
		if an_ws.get_ready_state() == WebSocketPeer.STATE_CLOSED and an_ws.connect_to_url(url) != OK:
			an_state = "fail"
			an_note = "an: connect_to_url failed"
			return
		an_ws.poll()
		if an_ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
			return
		an_id = Crypto.new().generate_random_bytes(8).hex_encode()
		var real := an_acct != "" and an_key != ""
		var ev := [{"id":an_id, "ev":"error", "ts":int(Time.get_unix_time_from_system()), "sid":"00000000", "b":build,
			"p":{"kind":"probe", "n":0}}]
		an_ws.put_packet(Net.encode({"t":"an", "v":Net.VERSION, "build":build, "acct":an_acct if real else "00000000000000000000",
			"key":an_key if real else "probe-not-a-key", "ev":ev}, true))
		an_state = "sent"
		an_note = "sent"
		return
	if an_state != "sent":
		return
	an_ws.poll()
	var real := an_acct != "" and an_key != ""
	while an_ws.get_available_packet_count() > 0:
		var m := Net.decode(an_ws.get_packet())
		if str(m.get("t", "")) == "an":
			if not real:
				an_state = "fail"
				an_note = "an: a made-up key got an answer %s" % str(m)
				return
			if (m.get("ok", []) as Array).has(an_id):
				an_state = "ok"
				an_note = "batch acknowledged (kept %d)" % int(m.get("kept", 0))
				an_ws.close()
			else:
				an_state = "fail"
				an_note = "an: answer without our id: %s" % str(m)
			return
	if an_ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		if not real and an_ws.get_close_code() == 4005 and an_ws.get_close_reason() == "an":
			an_state = "refused"
			an_note = "made-up key refused (4005 an); set SIEGE_PROBE_ACCT/KEY to send a real batch"
		else:
			an_state = "fail"
			an_note = "an: closed %d '%s' without an answer" % [an_ws.get_close_code(), an_ws.get_close_reason()]
	elif t > 30.0:
		an_state = "fail"
		an_note = "an: no answer in time"
