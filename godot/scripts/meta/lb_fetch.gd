extends Node
# 0.31.119: asks the Siege server for the week's leaderboard ({"t":"lb", "acct", "key"} on its own socket, like eco_sync)
# and hands the answer to `done` -- {} when there's no answer (no connection, an older server, a key it doesn't know).
# Frees itself when done.
# 0.31.120: ask() sends any one-socket request this way (the referral code: {"t":"ref", ...} -> {"t":"ref", ...}).
const Net = preload("res://scripts/siege/siege_net.gd")
const TIMEOUT := 10.0

var url := ""
var msg := {}
var done: Callable = func(_r): pass
var reply_t := "lb"
var _ws := WebSocketPeer.new()
var _sent := false
var _t := 0.0
var _over := false

static func start(parent: Node, url_: String, acct: String, key: String, cb: Callable) -> Node:
	var f = load("res://scripts/meta/lb_fetch.gd").new()
	f.url = url_
	f.msg = {"t":"lb", "v":Net.VERSION, "acct":acct, "key":key}
	f.done = cb
	parent.add_child(f)
	return f

static func ask(parent: Node, url_: String, msg_: Dictionary, cb: Callable) -> Node:
	# the answer is the first message whose "t" is the request's
	var f = load("res://scripts/meta/lb_fetch.gd").new()
	f.url = url_
	f.msg = msg_.duplicate()
	f.msg["v"] = Net.VERSION
	f.reply_t = str(msg_.get("t", ""))
	f.done = cb
	parent.add_child(f)
	return f

func _ready() -> void:
	_ws.inbound_buffer_size = 1 << 18
	if _ws.connect_to_url(url) != OK:
		_finish({})

func _process(delta: float) -> void:
	if _over:
		return
	_t += delta
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and not _sent:
		_ws.put_packet(Net.encode(msg))
		_sent = true
	while _ws.get_available_packet_count() > 0:
		var m := Net.decode(_ws.get_packet())
		if str(m.get("t", "")) == reply_t:
			_finish(m)
			return
	if st == WebSocketPeer.STATE_CLOSED or _t > TIMEOUT:
		_finish({})

func _finish(r: Dictionary) -> void:
	if _over:
		return
	_over = true
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.close()
	done.call(r)
	queue_free()
