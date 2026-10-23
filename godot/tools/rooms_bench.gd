extends SceneTree
# What a match room costs the server (0.31.209, Kevin: "Make it so more rooms can be created"): the real server with
# BENCH_ROOMS rooms, BENCH_PER_ROOM phones in each (default 1; SIEGE_MAX_PLAYERS is set to it, so the phones fill the
# rooms in turn; the other heroes bots), each phone sending inputs at 20 Hz. Prints the server's SIEGE_STATS lines (ms of work a second: sim steps, snapshot
# build, sends; frames a second, the worst frame) and its memory (RSS) once the rooms are all playing.
#   BENCH_ROOMS=8 BENCH_S=40 godot --headless --path godot -s res://tools/rooms_bench.gd
# Extra server settings pass through the environment (SIEGE_*), e.g. SIEGE_MAX_ROOMS.
const Net = preload("res://scripts/siege/siege_net.gd")

var N := 6
var per_room := 1
var phones := 6
var secs := 40.0
var port := 8140
var pid := 0
var peers: Array = []
var sent: Array = []
var t := 0.0
var send_clock := 0.0
var stats_path := ""
var rss_max := 0
var rss_clock := 0.0

func _init() -> void:
	if OS.has_environment("BENCH_ROOMS"):
		N = clampi(int(OS.get_environment("BENCH_ROOMS")), 1, 128)
	if OS.has_environment("BENCH_PER_ROOM"):
		per_room = clampi(int(OS.get_environment("BENCH_PER_ROOM")), 1, 10)
	phones = N * per_room
	if OS.has_environment("BENCH_S"):
		secs = clampf(float(OS.get_environment("BENCH_S")), 15.0, 600.0)
	if OS.has_environment("BENCH_PORT"):
		port = int(OS.get_environment("BENCH_PORT"))
	stats_path = OS.get_user_data_dir().path_join("rooms_bench_stats_%d.txt" % port)
	if FileAccess.file_exists(stats_path):
		DirAccess.remove_absolute(stats_path)
	OS.set_environment("SIEGE_STATS", "1")
	OS.set_environment("SIEGE_STATS_FILE", stats_path)
	OS.set_environment("SIEGE_PORT", str(port))
	OS.set_environment("SIEGE_HOST", "127.0.0.1")
	OS.set_environment("SIEGE_MAX_PLAYERS", str(per_room))
	if not OS.has_environment("SIEGE_MAX_ROOMS"):
		OS.set_environment("SIEGE_MAX_ROOMS", str(N))
	OS.set_environment("SIEGE_LOBBY", "1")
	OS.set_environment("SIEGE_IDLE_BOT", "3600")
	OS.set_environment("SIEGE_IDLE_KICK", "7200")
	OS.set_environment("SIEGE_MIN_BUILD", "off")
	var sd := OS.get_user_data_dir().path_join("rooms-bench-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(sd)
	OS.set_environment("STATE_DIRECTORY", sd)
	pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://server/siege_server.gd"])
	print("server pid %d, %d rooms of %d phones" % [pid, N, per_room])
	for i in phones:
		peers.append(WebSocketPeer.new())
		sent.append(false)

func _rss_kb() -> int:
	var out := []
	OS.execute("ps", ["-o", "rss=", "-p", str(pid)], out)
	return int(str(out[0]).strip_edges()) if not out.is_empty() and str(out[0]).strip_edges().is_valid_int() else 0

func _process(delta: float) -> bool:
	t += delta
	if t > 2.0 and not bool(peers[0].get_meta("dialed", false)):
		for ws in peers:
			ws.set_meta("dialed", true)
			ws.inbound_buffer_size = 1 << 21
			ws.connect_to_url("ws://127.0.0.1:%d" % port)
	send_clock += delta
	var do_send := send_clock >= 0.05
	if do_send:
		send_clock = 0.0
	for i in phones:
		var ws: WebSocketPeer = peers[i]
		ws.poll()
		if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
			continue
		if not sent[i]:
			ws.put_packet(Net.encode({"t":"hello", "v":Net.VERSION, "five":Net.FIVE, "name":"Bench%d" % i, "build":"bench", "pred":false}))
			sent[i] = true
		while ws.get_available_packet_count() > 0:
			ws.get_packet()
		if do_send:
			var ang := t * 0.7 + float(i)
			ws.put_packet(Net.encode({"t":"in", "m":Vector2(cos(ang), sin(ang)), "h":(i % 3 == 0), "b":false}))
	rss_clock += delta
	if t > 10.0 and rss_clock > 2.0:
		rss_clock = 0.0
		rss_max = maxi(rss_max, _rss_kb())
	if t > secs:
		var open := 0
		for ws in peers:
			if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
				open += 1
		OS.kill(pid)
		OS.execute("kill", ["-9", str(pid)])
		OS.delay_msec(300)
		var lines := []
		if FileAccess.file_exists(stats_path):
			for l in FileAccess.get_file_as_string(stats_path).split("\n"):
				if l.begins_with("SIEGE_STATS"):
					lines.append(l)
		# (the server prints its SIEGE_STATS lines itself) -- the second half's, once minions are out, summed up
		var work := 0.0
		var fps := 1000.0
		var worst := 0.0
		var n := 0
		for l in lines.slice(lines.size() / 2):
			var kv := {}
			for part in str(l).split(" "):
				if "=" in part:
					kv[part.split("=")[0]] = float(part.split("=")[1].trim_suffix("ms/s").trim_suffix("ms"))
			work += float(kv.get("step", 0.0)) + float(kv.get("snapshot", 0.0)) + float(kv.get("send", 0.0))
			fps = minf(fps, float(kv.get("frames/s", 0.0)))
			worst = maxf(worst, float(kv.get("worst_frame", 0.0)))
			n += 1
		print("ROOMS_BENCH rooms=%d phones=%d open=%d work=%.0fms/s (%.0f a room) min_fps=%.1f worst_frame=%.0fms rss_max=%d MB cores=%d" % [N,
			phones, open, work / maxi(n, 1), work / maxi(n, 1) / N, fps, worst, rss_max / 1024, OS.get_processor_count()])
		quit(0)
	return false
