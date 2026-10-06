extends SceneTree
# Fatebound Siege dedicated server (headless Godot). Runs the same SiegeSim as offline play,
# authoritative, 16v16 with bots in every slot no human holds.
#
#   godot --headless --path <project> -s res://server/siege_server.gd
# Env: SIEGE_HOST (default 127.0.0.1 — keep it on loopback behind Caddy), SIEGE_PORT (8082),
#      SIEGE_MAX_PLAYERS (32), SIEGE_LOG (1 = log joins/leaves/match results to stdout).
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Net = preload("res://scripts/siege/siege_net.gd")

const RESTART_AFTER := 15.0          # seconds of results screen before the next match
const IDLE_STOP := 30.0              # no players for this long -> stop simulating
const HELLO_TIMEOUT := 10.0
const MAX_MSGS_PER_SEC := 90         # per client; beyond this, messages are dropped
const TICK := Sim.TICK

var tcp := TCPServer.new()
var clients := {}                    # cid -> {ws, unit, name, hello, move, hold, joined_at, msgs, msg_clock}
var next_cid := 1
var sim = null
var match_id := 0
var match_seed := 0
var _accum := 0.0
var _snap_accum := 0.0
var _ended_at := -1.0
var _empty_since := -1.0
var _pending_events: Array = []
var host := "127.0.0.1"
var port := Net.DEFAULT_PORT
var max_players := 32
var log_on := true

func _init() -> void:
	host = OS.get_environment("SIEGE_HOST") if OS.has_environment("SIEGE_HOST") else host
	if OS.has_environment("SIEGE_PORT"):
		port = int(OS.get_environment("SIEGE_PORT"))
	if OS.has_environment("SIEGE_MAX_PLAYERS"):
		max_players = clampi(int(OS.get_environment("SIEGE_MAX_PLAYERS")), 1, 32)
	log_on = OS.get_environment("SIEGE_LOG") != "0"
	Engine.max_fps = 60              # headless would otherwise spin a core
	var err := tcp.listen(port, host)
	if err != OK:
		printerr("SIEGE_SERVER listen failed on %s:%d (%s)" % [host, port, error_string(err)])
		quit(1)
		return
	_log("SIEGE_SERVER listening on %s:%d (protocol %d, max %d players)" % [host, port, Net.VERSION, max_players])

func _log(s: String) -> void:
	if log_on:
		print("[%s] %s" % [Time.get_datetime_string_from_system(true), s])

func _process(delta: float) -> bool:
	_accept()
	_poll_clients()
	_run_match(delta)
	return false

# ---------------- connections ----------------
func _accept() -> void:
	while tcp.is_connection_available():
		var conn := tcp.take_connection()
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = Net.MAX_PACKET
		ws.outbound_buffer_size = 1 << 20
		if ws.accept_stream(conn) != OK:
			continue
		clients[next_cid] = {"ws":ws, "unit":"", "name":"", "hello":false, "move":Vector2.ZERO, "hold":false,
			"joined_at":Time.get_ticks_msec() / 1000.0, "msgs":0, "msg_clock":0.0}
		next_cid += 1

func _poll_clients() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for cid in clients.keys():
		var c: Dictionary = clients[cid]
		var ws: WebSocketPeer = c.ws
		ws.poll()
		var st := ws.get_ready_state()
		if st == WebSocketPeer.STATE_CLOSED:
			_drop(cid, "closed")
			continue
		if st != WebSocketPeer.STATE_OPEN:
			if now - float(c.joined_at) > HELLO_TIMEOUT:
				ws.close()
				_drop(cid, "handshake timeout")
			continue
		if not c.hello and now - float(c.joined_at) > HELLO_TIMEOUT:
			ws.close(4000, "no hello")
			_drop(cid, "no hello")
			continue
		if now - float(c.msg_clock) >= 1.0:
			c.msg_clock = now
			c.msgs = 0
		while ws.get_available_packet_count() > 0:
			var pkt := ws.get_packet()
			c.msgs += 1
			if c.msgs > MAX_MSGS_PER_SEC or pkt.size() > Net.MAX_PACKET:
				continue
			_handle(cid, Net.decode(pkt))

func _send(cid: int, msg: Dictionary) -> void:
	_send_raw(cid, Net.encode(msg, msg.get("t", "") == "s"))

func _send_raw(cid: int, bytes: PackedByteArray) -> void:
	var c: Dictionary = clients.get(cid, {})
	if c.is_empty():
		return
	var ws: WebSocketPeer = c.ws
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.put_packet(bytes)

# Load stats (0.31.23): every STATS_EVERY s, how long the sim steps, the snapshot build and the sends took per second,
# and the bytes sent -- logged with SIEGE_STATS=1 (the net load test reads them).
const STATS_EVERY := 5.0
var _st_step := 0
var _st_snap := 0
var _st_send := 0
var _st_bytes := 0
var _st_snaps := 0
var _st_clock := 0.0
var _st_frames := 0
var _st_frame_max := 0.0
func _stats_tick(delta: float) -> void:
	_st_clock += delta
	_st_frames += 1
	_st_frame_max = maxf(_st_frame_max, delta)
	if _st_clock < STATS_EVERY:
		return
	if OS.has_environment("SIEGE_STATS"):
		var n := _human_count()
		var line := "SIEGE_STATS players=%d bots=%d step=%.1fms/s snapshot=%.1fms/s send=%.1fms/s kB/s=%.1f snaps/s=%.1f frames/s=%.1f worst_frame=%.0fms" % [
			n, sim.units.size() - n if sim != null else 0, _st_step / 1000.0 / _st_clock, _st_snap / 1000.0 / _st_clock, _st_send / 1000.0 / _st_clock,
			_st_bytes / 1024.0 / _st_clock, _st_snaps / _st_clock, _st_frames / _st_clock, _st_frame_max * 1000.0]
		print(line)
		if OS.has_environment("SIEGE_STATS_FILE"):          # flushed per line (the load test reads it while we run)
			var f := FileAccess.open(OS.get_environment("SIEGE_STATS_FILE"), FileAccess.READ_WRITE if FileAccess.file_exists(OS.get_environment("SIEGE_STATS_FILE")) else FileAccess.WRITE)
			if f != null:
				f.seek_end()
				f.store_line(line)
				f.flush()
				f.close()
	_st_step = 0
	_st_snap = 0
	_st_send = 0
	_st_bytes = 0
	_st_snaps = 0
	_st_frames = 0
	_st_frame_max = 0.0
	_st_clock = 0.0

func _drop(cid: int, why: String) -> void:
	var c: Dictionary = clients.get(cid, {})
	if c.is_empty():
		return
	if sim != null and c.unit != "" and sim.by_id.has(c.unit):
		var u: Dictionary = sim.by_id[c.unit]
		u.bot = true                   # a bot takes the slot back over
		u.move = Vector2.ZERO
		u.net_driven = false
	if c.hello:
		_log("leave %s (%s) unit=%s players=%d" % [c.name, why, c.unit, _human_count() - 1])
	clients.erase(cid)

func _human_count() -> int:
	var n := 0
	for cid in clients:
		if clients[cid].hello:
			n += 1
	return n

# ---------------- messages ----------------
func _handle(cid: int, msg: Dictionary) -> void:
	var c: Dictionary = clients[cid]
	match str(msg.get("t", "")):
		"hello":
			if c.hello:
				return
			if int(msg.get("v", -1)) != Net.VERSION:
				_send(cid, {"t":"bye", "why":"version", "need":Net.VERSION})
				(c.ws as WebSocketPeer).close(4001, "version")
				return
			if _human_count() >= max_players:
				_send(cid, {"t":"bye", "why":"full"})
				(c.ws as WebSocketPeer).close(4002, "full")
				return
			c.hello = true
			c.name = str(msg.get("name", "Player")).left(20)
			c.pred = bool(msg.get("pred", false))         # the phone moves its own unit (0.18.4)
			if sim == null:
				_new_match()
			_seat(cid)
		"in":
			if not c.hello or sim == null or c.unit == "":
				return
			var m: Variant = msg.get("m", Vector2.ZERO)
			if m is Vector2 and is_finite(m.x) and is_finite(m.y):
				c.move = (m as Vector2).limit_length(1.0)
			c.hold = bool(msg.get("h", false))
			c.bhold = bool(msg.get("b", false))
			c.khold = bool(msg.get("k", false))                # 0.31.61: the Crusader's held block
			var cp: Variant = msg.get("p", null)
			if cp is Vector2 and is_finite(cp.x) and is_finite(cp.y):
				c.cpos = cp
				c.cface = float(msg.get("f", 0.0))
				c.cpos_new = true
				c.cpos_rx = Time.get_ticks_msec() / 1000.0
			var a: String = str(msg.get("a", ""))
			if a != "" and a in Net.ACTIONS:
				var arg: Variant = msg.get("arg", null)
				if a == "buy":
					arg = str(arg) if str(arg) in Sim.UPGRADES else ""
				else:
					arg = null
				sim.act(c.unit, a, arg)

func _seat(cid: int) -> void:
	# Take over a bot on the team with fewer humans (blue on ties).
	var c: Dictionary = clients[cid]
	var humans := [0, 0]
	for other in clients:
		var oc: Dictionary = clients[other]
		if other != cid and oc.hello and oc.unit != "" and sim.by_id.has(oc.unit):
			humans[sim.by_id[oc.unit].team] += 1
	var team := 0 if humans[0] <= humans[1] else 1
	var seat := ""
	for u in sim.units:
		if u.team == team and u.bot and not _unit_taken(u.id):
			seat = u.id
			break
	if seat == "":
		for u in sim.units:
			if u.bot and not _unit_taken(u.id):
				seat = u.id
				break
	c.unit = seat
	c.move = Vector2.ZERO
	if seat != "":
		sim.by_id[seat].bot = false
	_send(cid, {"t":"welcome", "v":Net.VERSION, "you":seat, "match":match_id, "seed":match_seed,
		"team_size":Net.TEAM_SIZE, "players":_human_count()})
	# The first snapshot right away so the client can build its view.
	_send(cid, Net.snapshot(sim, seat, []))
	_log("join %s -> %s (match %d, players %d)" % [c.name, seat, match_id, _human_count()])

func _unit_taken(id: String) -> bool:
	for cid in clients:
		if clients[cid].unit == id:
			return true
	return false

# ---------------- match loop ----------------
func _new_match() -> void:
	match_id += 1
	match_seed = randi() & 0x7fffffff
	sim = Sim.new()
	sim.setup(Net.TEAM_SIZE, match_seed, -1)      # no local human; every unit starts as a bot
	_accum = 0.0
	_snap_accum = 0.0
	_ended_at = -1.0
	_pending_events.clear()
	_log("match %d start (seed %d)" % [match_id, match_seed])

func _run_match(delta: float) -> void:
	var humans := _human_count()
	if humans == 0:
		if sim != null:
			if _empty_since < 0.0:
				_empty_since = Time.get_ticks_msec() / 1000.0
			elif Time.get_ticks_msec() / 1000.0 - _empty_since > IDLE_STOP:
				_log("match %d stopped (no players)" % match_id)
				sim = null
		return
	_empty_since = -1.0
	if sim == null:
		return
	if sim.ended:
		if _ended_at < 0.0:
			_ended_at = Time.get_ticks_msec() / 1000.0
			_log("match %d end winner=%d reason=%s score=%s" % [match_id, sim.winner, sim.end_reason, str(sim.score)])
		elif Time.get_ticks_msec() / 1000.0 - _ended_at > RESTART_AFTER:
			_new_match()
			for cid in clients:
				if clients[cid].hello:
					clients[cid].unit = ""
			for cid in clients:
				if clients[cid].hello:
					_seat(cid)
			return
	# Apply held inputs, then step at a fixed 30 Hz.
	for cid in clients:
		var c: Dictionary = clients[cid]
		if c.hello and c.unit != "" and sim.by_id.has(c.unit):
			sim.set_move(c.unit, c.move)
			var ub: Dictionary = sim.by_id[c.unit]
			# Client-side prediction: take the phone's position when it's plausible (speed x time
			# since the last accepted report, not in a wall); otherwise keep ours and the phone snaps.
			# ...but only while positions keep arriving: after 0.3 s without one (packet loss, a stalled
			# phone) the server moves the unit from its inputs again instead of freezing it.
			var now_rx := Time.get_ticks_msec() / 1000.0
			ub.net_driven = bool(c.get("pred", false)) and now_rx - float(c.get("cpos_rx", -10.0)) < 0.3
			if ub.net_driven and bool(c.get("cpos_new", false)):
				c.cpos_new = false
				var now_s := Time.get_ticks_msec() / 1000.0
				if sim.accept_client_pos(ub, c.cpos, float(c.cface), now_s - float(c.get("cpos_t", now_s - 0.05))):
					c.cpos_t = now_s
					c.pos_ok = int(c.get("pos_ok", 0)) + 1
				else:
					c.pos_rejected = int(c.get("pos_rejected", 0)) + 1
			if bool(c.get("bhold", false)) and sim.ability_of(ub) == "block":
				sim.act(c.unit, "ability")
			if bool(c.get("khold", false)):
				sim.act(c.unit, "block")
			if c.hold:
				var u: Dictionary = sim.by_id[c.unit]
				if sim.can_act(u) and not u.carrying:
					sim.act(c.unit, "attack")
	_accum = minf(_accum + delta, TICK * 6)
	var t_step := Time.get_ticks_usec()
	while _accum >= TICK and not sim.ended:
		_accum -= TICK
		sim.step(TICK)
		_pending_events.append_array(sim.drain_events())
	_st_step += Time.get_ticks_usec() - t_step
	if sim.ended:
		_pending_events.append_array(sim.drain_events())
	_snap_accum += delta
	if _snap_accum >= 1.0 / Net.SNAP_HZ:
		_snap_accum = minf(_snap_accum - 1.0 / Net.SNAP_HZ, 1.0 / Net.SNAP_HZ)
		var events := _pending_events
		_pending_events = []
		var t_snap := Time.get_ticks_usec()
		var base := Net.snapshot(sim, "", events)      # built once, shared by every player
		_st_snap += Time.get_ticks_usec() - t_snap
		var t_send := Time.get_ticks_usec()
		# 0.31.23: encoded and compressed ONCE and sent to everyone; each player's private bit (their task) goes in its
		# own small "m" message, only when it changes. Before, every player's copy was encoded and compressed separately.
		var bytes := Net.encode(base, true)
		for cid in clients:
			var c: Dictionary = clients[cid]
			if not c.hello:
				continue
			_send_raw(cid, bytes)
			_st_bytes += bytes.size()
			var me: Dictionary = sim.by_id.get(c.unit, {})
			if not me.is_empty():
				var th := hash(me.task)
				if int(c.get("task_hash", -1)) != th:
					c.task_hash = th
					_send(cid, {"t":"m", "task":me.task.duplicate(true)})
		_st_send += Time.get_ticks_usec() - t_send
		_st_snaps += 1
	_stats_tick(delta)
