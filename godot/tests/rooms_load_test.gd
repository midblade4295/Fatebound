extends SceneTree
# 0.31.209 (Kevin: "Make it so more rooms can be created"): the REAL server, rooms on worker threads, real time.
#   A :8141  rooms of one phone (SIEGE_MAX_PLAYERS=1), the default cap: "status" says it -- 6 a core (at least 6);
#            five phones, five rooms, five matches stepping at once (on the cores) -- each phone gets its own match's
#            snapshots at the full rate (20 a second), its clock running, none of another's; "status" says the load
#   B :8142  SIEGE_LOAD_LIMIT just over one room's share of the cores (ROOM_COST_START): the first phone gets a room, the
#            second is turned away "full" (bye full, 4002) though SIEGE_MAX_ROOMS is 8 -- one more room would keep the
#            cores busier than the limit
#   godot --headless --path godot -s res://tests/rooms_load_test.gd
const Net = preload("res://scripts/siege/siege_net.gd")
const Server = preload("res://server/siege_server.gd")

var fails: Array = []
var pids: Array = []
var phase := "boot"
var t_phase := 0.0
var socks := {}
var inbox := {}
var sent := {}
var notes := {}
const PA := 8141
const PB := 8142
const N := 5

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _server(port: int, env: Dictionary) -> void:
	var sd := OS.get_user_data_dir().path_join("roomsload-%d-%d" % [port, Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(sd)
	var base := {"SIEGE_PORT":str(port), "SIEGE_HOST":"127.0.0.1", "SIEGE_LOBBY":"0.5", "SIEGE_MAX_PLAYERS":"1",
		"STATE_DIRECTORY":sd, "SIEGE_MIN_BUILD":"off", "SIEGE_IDLE_BOT":"600", "SIEGE_IDLE_KICK":"900"}
	base.merge(env, true)
	for k in ["SIEGE_MAX_ROOMS", "SIEGE_LOAD_LIMIT", "SIEGE_THREADS"]:
		OS.unset_environment(k)
	for k in base:
		OS.set_environment(k, str(base[k]))
	var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://server/siege_server.gd"])
	check(pid > 0, "server :%d started (%s)" % [port, str(env)])
	pids.append(pid)

func _init() -> void:
	_server(PA, {"SIEGE_LOAD_LIMIT":"4"})                  # (A: five rooms whatever this machine's cores)
	# B: room for one room's cost (before any is measured: ROOM_COST_START), not two
	var lim := 1.5 * Server.ROOM_COST_START / maxf(1.0, float(OS.get_processor_count()))
	notes.lim = lim
	_server(PB, {"SIEGE_MAX_ROOMS":"8", "SIEGE_LOAD_LIMIT":"%.5f" % lim})

func _go(p: String) -> void:
	phase = p
	t_phase = 0.0

func open(name: String, port: int) -> void:
	var ws := WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 21
	ws.connect_to_url("ws://127.0.0.1:%d" % port)
	socks[name] = ws
	inbox[name] = []
	sent.erase(name)

func send_once(name: String, msg: Dictionary) -> bool:
	if sent.has(name):
		return true
	var ws: WebSocketPeer = socks[name]
	if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	ws.put_packet(Net.encode(msg))
	sent[name] = true
	return true

func got(name: String, tt: String) -> Array:
	return (inbox.get(name, []) as Array).filter(func(m): return str(m.get("t", "")) == tt)

func welcome(name: String) -> Dictionary:
	var w := got(name, "welcome")
	return w[w.size() - 1] if not w.is_empty() else {}

func hello(name: String) -> Dictionary:
	return {"t":"hello", "v":Net.VERSION, "five":Net.FIVE, "name":name, "build":"0.31.209-fatebound", "pred":false}

var _in_clock := 0.0

func _process(delta: float) -> bool:
	t_phase += delta
	_in_clock += delta
	var send_in := _in_clock >= 0.25
	if send_in:
		_in_clock = 0.0
	for n in socks:
		var ws: WebSocketPeer = socks[n]
		ws.poll()
		while ws.get_available_packet_count() > 0:
			var m := Net.decode(ws.get_packet())
			if str(m.get("t", "")) == "s":
				m = {"t":"s", "tm":float(m.get("tm", -1.0)), "at":Time.get_ticks_msec() / 1000.0}   # (kept small)
			(inbox[n] as Array).append(m)
		if send_in and not welcome(n).is_empty() and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.put_packet(Net.encode({"t":"in", "m":Vector2.ZERO, "h":false, "b":false}))    # (a seated phone keeps talking)
	match phase:
		"boot":
			if t_phase > 2.5:
				for i in N:
					open("a%d" % i, PA)
				open("st0", PA)
				_go("status0")
		"status0":
			send_once("st0", {"t":"status"})
			if not got("st0", "status").is_empty():
				var st: Dictionary = got("st0", "status")[0]
				var want := clampi(OS.get_processor_count() * Server.ROOMS_PER_CORE, Server.MAX_ROOMS, Server.MAX_ROOMS_CAP)
				check(int(st.get("max_rooms", -1)) == want and want >= 6,
					"the default cap: %d rooms -- %d a core on %d cores (at least 6)" % [int(st.get("max_rooms", -1)), Server.ROOMS_PER_CORE, OS.get_processor_count()])
				_go("seat")
			elif t_phase > 8.0:
				check(false, "a status answer within 8 s")
				_finish()
		"seat":
			for i in N:
				send_once("a%d" % i, hello("A%d" % i))
			var all_in := range(N).all(func(i): return not welcome("a%d" % i).is_empty())
			if all_in:
				var ms := {}
				for i in N:
					ms[int(welcome("a%d" % i).match)] = true
				check(ms.size() == N, "%d phones, %d rooms of one: %d matches" % [N, N, ms.size()])
				notes.mark = {}
				for i in N:
					notes.mark["a%d" % i] = got("a%d" % i, "s").size()
				_go("run")
			elif t_phase > 12.0:
				check(false, "five phones seated within 12 s")
				_finish()
		"run":
			if t_phase > 6.0:
				var rates := []
				var clocks := []
				for i in N:
					var n := "a%d" % i
					var ss: Array = got(n, "s").slice(int(notes.mark[n]))
					rates.append(ss.size() / t_phase)
					clocks.append(float(ss[-1].tm) - float(ss[0].tm) if ss.size() >= 2 else 0.0)
				check(rates.all(func(r): return r >= Net.SNAP_HZ * 0.8), "every room's snapshots at the full rate, the rooms stepping at once (%s a second)" % str(rates.map(func(r): return snappedf(r, 0.1))))
				check(clocks.all(func(c): return c >= t_phase * 0.85), "...every match's clock running (%s s in %.1f s)" % [str(clocks.map(func(c): return snappedf(c, 0.1))), t_phase])
				open("st1", PA)
				_go("status1")
		"status1":
			send_once("st1", {"t":"status"})
			if not got("st1", "status").is_empty():
				var st: Dictionary = got("st1", "status")[0]
				check(int(st.get("rooms", -1)) == N and int(st.get("in_match", -1)) == N and st.has("load"),
					"status: %d rooms, %d in matches, the cores %d%% busy" % [int(st.get("rooms", -1)), int(st.get("in_match", -1)), int(st.get("load", -1))])
				for i in N:
					(socks["a%d" % i] as WebSocketPeer).close(1000, "leave")
				open("b1", PB)
				_go("b1")
			elif t_phase > 8.0:
				check(false, "a status answer within 8 s")
				_finish()
		"b1":
			send_once("b1", hello("B1"))
			if not welcome("b1").is_empty():
				check(true, "B (load limit %.3f): the first phone gets a room" % float(notes.lim))
				open("b2", PB)
				_go("b2")
			elif t_phase > 10.0:
				check(false, "B's first phone seated within 10 s")
				_finish()
		"b2":
			send_once("b2", hello("B2"))
			var ws: WebSocketPeer = socks.b2
			if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
				var bye := got("b2", "bye")
				check(not bye.is_empty() and str(bye[0].why) == "full" and ws.get_close_code() == 4002 and welcome("b2").is_empty(),
					"...the second: \"full\" (%d) though up to 8 rooms may run -- a second room would pass the cores' limit" % ws.get_close_code())
				_finish()
			elif t_phase > 10.0:
				check(false, "B's second phone answered within 10 s (welcome %s)" % str(welcome("b2")))
				_finish()
	return false

func _finish() -> void:
	for pid in pids:
		OS.kill(pid)
		OS.execute("kill", ["-9", str(pid)])
	pids.clear()
	print("ROOMS_LOAD_PASS" if fails.is_empty() else "ROOMS_LOAD_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
