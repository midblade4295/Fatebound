extends SceneTree
# What players in the menus cost the server (0.31.209, Kevin: "give me the total players supported online and total
# players supported in active matches"): the real server, BENCH_ONLINE accounts made over the eco socket, then that many
# phones' social sockets ({"so", "hi"} -- what every app keeps open while it's up) held open and idle. Prints the
# server's CPU (from /proc: user + system time over BENCH_S seconds, as % of one core), its memory (RSS) and its open
# files against its limit.
#   BENCH_ONLINE=500 BENCH_S=20 godot --headless --path godot -s res://tools/online_bench.gd
const Net = preload("res://scripts/siege/siege_net.gd")

var K := 200
var secs := 20.0
var port := 8151
var pid := 0
var phase := "boot"
var t := 0.0
var t_phase := 0.0
var eco: Array = []          # [ws, sent, acct, key]
var soc: Array = []
var made := 0
var me := 0
var cpu0 := 0
var cpu_t0 := 0.0

func _init() -> void:
	if OS.has_environment("BENCH_ONLINE"):
		K = clampi(int(OS.get_environment("BENCH_ONLINE")), 1, 5000)
	if OS.has_environment("BENCH_S"):
		secs = clampf(float(OS.get_environment("BENCH_S")), 5.0, 600.0)
	var sd := OS.get_user_data_dir().path_join("online-bench-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(sd)
	OS.set_environment("STATE_DIRECTORY", sd)
	OS.set_environment("SIEGE_PORT", str(port))
	OS.set_environment("SIEGE_HOST", "127.0.0.1")
	OS.set_environment("SIEGE_MIN_BUILD", "off")
	OS.set_environment("SIEGE_LOG", "0")
	var exe := OS.get_executable_path()
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://server/siege_server.gd"]
	if OS.has_environment("BENCH_NOFILE"):           # e.g. "1024:20000" -- the open-file limit systemd gives a service
		pid = OS.create_process("prlimit", ["--nofile=" + OS.get_environment("BENCH_NOFILE"), exe] + args)
	else:
		pid = OS.create_process(exe, args)
	print("server pid %d, %d phones online" % [pid, K])

func _cpu_ticks() -> int:
	var out := []
	OS.execute("cat", ["/proc/%d/stat" % pid], out)
	if out.is_empty():
		return 0
	var s := str(out[0])
	var f := s.substr(s.rfind(")") + 2).split(" ")
	return int(f[11]) + int(f[12])                 # utime + stime (fields 14 and 15)

func _sh(cmd: String) -> String:
	var out := []
	OS.execute("sh", ["-c", cmd], out)
	return str(out[0]).strip_edges() if not out.is_empty() else ""

func _process(delta: float) -> bool:
	t += delta
	t_phase += delta
	match phase:
		"boot":
			if t > 2.5:
				phase = "accounts"
				t_phase = 0.0
		"accounts":
			# 40 account sockets at a time
			var open_now := eco.filter(func(e): return e[1] < 2).size()
			while open_now < 40 and eco.size() < K:
				var ws := WebSocketPeer.new()
				ws.connect_to_url("ws://127.0.0.1:%d" % port)
				eco.append([ws, 0, "", ""])
				open_now += 1
			for e in eco:
				if e[1] >= 2:
					continue
				var ws: WebSocketPeer = e[0]
				ws.poll()
				if e[1] == 0 and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
					ws.put_packet(Net.encode({"t":"eco", "v":Net.VERSION, "new":true}))
					e[1] = 1
				while ws.get_available_packet_count() > 0:
					var m := Net.decode(ws.get_packet())
					if str(m.get("t", "")) == "eco" and m.has("acct"):
						e[2] = str(m.acct)
						e[3] = str(m.key)
						e[1] = 2
						made += 1
						ws.close()
				if e[1] < 2 and ws.get_ready_state() == WebSocketPeer.STATE_CLOSED and e[1] == 1:
					e[1] = 3                                # (closed without an account)
			if eco.size() >= K and eco.all(func(e): return e[1] >= 2):
				print("accounts: %d made in %.1f s" % [made, t_phase])
				phase = "social"
				t_phase = 0.0
			elif t_phase > 120.0:
				print("accounts: only %d in 120 s" % made)
				phase = "social"
				t_phase = 0.0
		"social":
			# (8 new sockets a frame -- players arrive spread out, not all in one instant; BENCH_PER_ACCT sockets an account,
			# as many as social.gd allows, MAX_CONN_PER_PLAYER: the server makes only 240 new accounts an hour)
			var per := clampi(int(OS.get_environment("BENCH_PER_ACCT")) if OS.has_environment("BENCH_PER_ACCT") else 1, 1, 2)
			var want := []
			for e in eco:
				if e[1] == 2:
					for j in per:
						want.append(e)
			var n_new := 0
			while soc.size() < want.size() and n_new < 8:
				var e: Array = want[soc.size()]
				var ws := WebSocketPeer.new()
				ws.connect_to_url("ws://127.0.0.1:%d" % port)
				soc.append([ws, false, e[2], e[3], false])
				n_new += 1
				t_phase = 0.0
			_poll_social()
			if t_phase > 15.0 or (me >= soc.size() and soc.size() >= want.size() and t_phase > 2.0):
				var codes := {}
				for so in soc:
					var w: WebSocketPeer = so[0]
					var k := "open" if w.get_ready_state() == WebSocketPeer.STATE_OPEN else "closed %d %s" % [w.get_close_code(), w.get_close_reason()]
					codes[k] = int(codes.get(k, 0)) + 1
				print("social sockets: %d of %d answered \"me\" %s" % [me, soc.size(), str(codes)])
				cpu0 = _cpu_ticks()
				cpu_t0 = t
				phase = "idle"
				t_phase = 0.0
		"idle":
			_poll_social()
			if t_phase >= secs:
				var cpu := float(_cpu_ticks() - cpu0) / 100.0 / (t - cpu_t0) * 100.0
				var still := soc.filter(func(s): return (s[0] as WebSocketPeer).get_ready_state() == WebSocketPeer.STATE_OPEN).size()
				var rss := int(_sh("ps -o rss= -p %d" % pid))
				var fds := int(_sh("ls /proc/%d/fd | wc -l" % pid))
				var lim := _sh("grep 'Max open files' /proc/%d/limits" % pid).split(" ", false)
				print("ONLINE_BENCH online=%d open=%d server_cpu=%.1f%% of a core rss=%d MB open_files=%d limit=%s" % [me, still, cpu,
					rss / 1024, fds, lim[3] if lim.size() > 3 else "?"])
				OS.kill(pid)
				OS.execute("kill", ["-9", str(pid)])
				quit(0)
	return false

func _poll_social() -> void:
	for s in soc:
		var ws: WebSocketPeer = s[0]
		ws.poll()
		if not s[1] and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.put_packet(Net.encode({"t":"so", "k":"hi", "v":Net.VERSION, "acct":s[2], "key":s[3]}))
			s[1] = true
		while ws.get_available_packet_count() > 0:
			var m := Net.decode(ws.get_packet())
			if not s[4] and str(m.get("k", "")) == "me":
				s[4] = true
				me += 1
