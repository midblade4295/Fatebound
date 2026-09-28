extends SceneTree
# Health probe for the Siege server. Connects like a player, expects a welcome and snapshots,
# then leaves (its unit goes back to a bot).
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

func _init() -> void:
	if OS.has_environment("SIEGE_PROBE_URL"):
		url = OS.get_environment("SIEGE_PROBE_URL")
	ws.inbound_buffer_size = 1 << 20
	if ws.connect_to_url(url) != OK:
		_done(false, "connect_to_url failed for " + url)

func _done(ok: bool, why: String) -> void:
	if ok:
		print("PROBE_OK %s unit=%s match=%s snapshots=%d" % [url, welcome.get("you", "?"), welcome.get("match", "?"), snaps])
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
	while ws.get_available_packet_count() > 0:
		var m := Net.decode(ws.get_packet())
		match str(m.get("t", "")):
			"welcome": welcome = m
			"s": snaps += 1
			"bye": _done(false, "server said bye: " + str(m.get("why", "")))
	if not welcome.is_empty() and snaps >= 3:
		_done(true, "")
	elif st == WebSocketPeer.STATE_CLOSED:
		_done(false, "connection closed (code %d)" % ws.get_close_code())
	elif t > 10.0:
		_done(false, "timeout (state %d, welcome %s, snapshots %d)" % [st, str(not welcome.is_empty()), snaps])
	return false
