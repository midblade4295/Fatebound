extends SceneTree
# Health probe for the Siege server. Connects like a player, expects a welcome and snapshots,
# then leaves (its unit goes back to a bot). 0.31.82: it first asks for the "status" (Home's players online) on a
# second connection, and waits out the lobby countdown (20 s on the live server) before its welcome.
#   godot --headless --path <project> -s res://server/siege_probe.gd
# Env: SIEGE_PROBE_URL (default ws://127.0.0.1:8082/fatebound/siege/ws).
# Prints PROBE_OK and exits 0 on success; PROBE_FAIL <reason> and exits 1 otherwise.
const Net = preload("res://scripts/siege/siege_net.gd")

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

func _init() -> void:
	if OS.has_environment("SIEGE_PROBE_URL"):
		url = OS.get_environment("SIEGE_PROBE_URL")
	ws.inbound_buffer_size = 1 << 20
	if ws.connect_to_url(url) != OK:
		_done(false, "connect_to_url failed for " + url)
	stat_ws.connect_to_url(url)

func _done(ok: bool, why: String) -> void:
	if ok:
		print("PROBE_OK %s unit=%s match=%s snapshots=%d lobby_msgs=%d status=%s" % [url, welcome.get("you", "?"), welcome.get("match", "?"), snaps,
			lobby_n, str(status) if not status.is_empty() else "none (a server before 0.31.82)"])
	else:
		print("PROBE_FAIL %s: %s" % [url, why])
	ws.close()
	quit(0 if ok else 1)

func _process(d: float) -> bool:
	t += d
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and not sent:
		sent = true
		ws.put_packet(Net.encode({"t":"hello", "v":Net.VERSION, "name":"probe"}))
	stat_ws.poll()
	if stat_ws.get_ready_state() == WebSocketPeer.STATE_OPEN and not stat_sent:
		stat_sent = true
		stat_ws.put_packet(Net.encode({"t":"status"}))
	while stat_ws.get_available_packet_count() > 0:
		var sm := Net.decode(stat_ws.get_packet())
		if str(sm.get("t", "")) == "status":
			status = sm
			print("PROBE status: online=%d in_match=%d waiting=%d lobby=%.0f" % [int(sm.get("online", 0)), int(sm.get("in_match", 0)), int(sm.get("waiting", 0)), float(sm.get("lobby", -1))])
	while ws.get_available_packet_count() > 0:
		var m := Net.decode(ws.get_packet())
		match str(m.get("t", "")):
			"lobby": lobby_n += 1
			"welcome": welcome = m
			"s": snaps += 1
			"bye": _done(false, "server said bye: " + str(m.get("why", "")))
	if not welcome.is_empty() and snaps >= 3:
		_done(true, "")
	elif st == WebSocketPeer.STATE_CLOSED:
		_done(false, "connection closed (code %d)" % ws.get_close_code())
	elif t > 35.0:                                     # (the lobby countdown is 20 s)
		_done(false, "timeout (state %d, welcome %s, snapshots %d)" % [st, str(not welcome.is_empty()), snaps])
	return false
