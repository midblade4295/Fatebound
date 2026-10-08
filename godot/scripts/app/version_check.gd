extends Node
# Version check on the menu (0.31.73, Kevin: "when server has newer version than players installed game it'll force
# them to update"). Opens a WebSocket to the Siege server, asks {"t":"ver"} and reads the protocol it speaks, without
# joining a match. Emits `done(server_v)` once and frees itself:
#   server_v >= 0  the server's protocol (compare with Net.version_verdict)
#   -1             no answer: offline, server down, or a server older than 0.31.73 (it ignores "ver"); the connect
#                  path (siege_mode.gd) still catches a mismatch when the player taps PLAY.
const Net = preload("res://scripts/siege/siege_net.gd")

signal done(server_v: int)

var url := Net.DEFAULT_URL
var timeout := 6.0
var ws: WebSocketPeer = null
var _t := 0.0
var _sent := false
var _bye: Dictionary = {}
var _finished := false

func _ready() -> void:
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 16
	ws.outbound_buffer_size = 1 << 12
	if ws.connect_to_url(url) != OK:
		_finish(-1)

func _process(delta: float) -> void:
	if _finished or ws == null:
		return
	_t += delta
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and not _sent:
		ws.put_packet(Net.encode({"t":"ver", "v":Net.VERSION}))
		_sent = true
	while ws.get_available_packet_count() > 0:
		var m := Net.decode(ws.get_packet())
		match str(m.get("t", "")):
			"ver":
				_finish(int(m.get("v", -1)))
				return
			"bye":
				_bye = m
				var sv := Net.refused_version(_bye, -1, "")
				if sv >= 0:
					_finish(sv)
					return
	if st == WebSocketPeer.STATE_CLOSED:
		var sv2 := Net.refused_version(_bye, ws.get_close_code(), ws.get_close_reason())
		# A legacy server never answers "ver"; it closes with 4000 "no hello" after its timeout -> unknown.
		_finish(sv2 if sv2 > 0 else -1)
		return
	if _t > timeout:
		_finish(-1)

func _finish(server_v: int) -> void:
	if _finished:
		return
	_finished = true
	if ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.close(1000, "done")
	done.emit(server_v)
	queue_free()
