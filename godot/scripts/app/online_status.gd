extends Node
# 0.31.82 (Kevin: "Add a players online in main menu"): asks the Siege server how many players are on it. A WebSocket
# that sends {"t":"status"} (no hello, so it never counts as a player), reads the answer and closes -- every POLL_EVERY
# seconds while Home shows (siege_app sets `active`). `info` is the last answer, {} while unknown: before the first
# one, when the server can't be reached, or a server older than 0.31.82 (it never answers a status).
const Net = preload("res://scripts/siege/siege_net.gd")
const POLL_EVERY := 15.0
const TIMEOUT := 8.0

signal changed

var url := OS.get_environment("SIEGE_URL") if OS.has_environment("SIEGE_URL") else Net.DEFAULT_URL
var active := false
var info := {}
var _ws: WebSocketPeer = null
var _sent := false
var _started := 0.0
var _next := 0.0
var _last_ok := -100.0

func set_active(on: bool) -> void:
	active = on
	if on and _now() - _last_ok > 5.0:
		_next = 0.0                                  # Home again: ask now unless the answer is fresh

func online() -> int:
	return int(info.get("online", -1)) if not info.is_empty() else -1

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _process(_delta: float) -> void:
	if _ws == null:
		if active and _now() >= _next:
			_begin()
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and not _sent:
		_ws.put_packet(Net.encode({"t":"status"}))
		_sent = true
	while _ws.get_available_packet_count() > 0:      # (read before the state: the answer comes with the close)
		var m := Net.decode(_ws.get_packet())
		if str(m.get("t", "")) == "status":
			_finish(m)
			return
	if st == WebSocketPeer.STATE_CLOSED or _now() - _started > TIMEOUT:
		_finish({})

func _begin() -> void:
	_ws = WebSocketPeer.new()
	_sent = false
	_started = _now()
	if _ws.connect_to_url(url) != OK:
		_finish({})

func _finish(m: Dictionary) -> void:
	if _ws != null and _ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_ws.close()
	_ws = null
	_next = _now() + POLL_EVERY
	if not m.is_empty():
		_last_ok = _now()
	if m != info:
		info = m
		changed.emit()
