extends SceneTree
# Online load (0.31.23, Kevin: "handle 32 players in a single match without lag and stutter"): the real server with
# 32 connected players sending inputs at 20 Hz for 25 s. Reads the server's SIEGE_STATS lines (ms of work per second
# for sim steps, snapshot build and sends; kB/s out; worst frame) and the bytes each client received.
# Run in REAL time (the server is its own process on the wall clock).
const Net = preload("res://scripts/siege/siege_net.gd")
const N := 32
var port := 8095
var pid := 0
var peers: Array = []
var hello_sent: Array = []
var rx_bytes := 0
var rx_packets := 0
var t := 0.0
var send_clock := 0.0
var stats_path := "/tmp/net_load_stats.txt"

func _init() -> void:
	if OS.has_environment("NET_TEST_PORT"):
		port = int(OS.get_environment("NET_TEST_PORT"))
	var godot := OS.get_executable_path()
	var proj := ProjectSettings.globalize_path("res://")
	if FileAccess.file_exists(stats_path):
		DirAccess.remove_absolute(stats_path)
	# the server launched directly (killing a bash wrapper would leave it running)
	OS.set_environment("SIEGE_STATS", "1")
	OS.set_environment("SIEGE_STATS_FILE", stats_path)
	OS.set_environment("SIEGE_PORT", str(port))
	OS.set_environment("SIEGE_HOST", "127.0.0.1")
	OS.set_environment("SIEGE_MAX_PLAYERS", "32")
	pid = OS.create_process(godot, ["--headless", "--path", proj, "-s", "res://server/siege_server.gd"])
	print("server pid ", pid)
	for i in N:
		var ws := WebSocketPeer.new()
		peers.append(ws)
		hello_sent.append(false)

func _process(delta: float) -> bool:
	t += delta
	if t > 1.5 and t < 1.6 and peers[0].get_ready_state() == WebSocketPeer.STATE_CLOSED:
		for ws in peers:
			ws.connect_to_url("ws://127.0.0.1:%d" % port)
	send_clock += delta
	var do_send := send_clock >= 0.05
	if do_send:
		send_clock = 0.0
	for i in N:
		var ws: WebSocketPeer = peers[i]
		ws.poll()
		if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
			continue
		if not hello_sent[i]:
			ws.put_packet(Net.encode({"t":"hello", "v":Net.VERSION, "name":"Load%d" % i, "build":"load", "pred":true}))
			hello_sent[i] = true
		while ws.get_available_packet_count() > 0:
			rx_bytes += ws.get_packet().size()
			rx_packets += 1
		if do_send:
			var ang := t * 0.7 + float(i)
			var msg := {"t":"in", "m":Vector2(cos(ang), sin(ang)), "h":(i % 3 == 0), "b":false}
			if randf() < 0.04:
				msg["a"] = "ability"
			ws.put_packet(Net.encode(msg))
	if t > 29.0:
		var open := 0
		for ws in peers:
			if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
				open += 1
		OS.kill(pid)
		OS.execute("kill", ["-9", str(pid)])            # Godot's server doesn't stop on SIGTERM
		OS.delay_msec(300)
		var lines := []
		if FileAccess.file_exists(stats_path):
			for l in FileAccess.get_file_as_string(stats_path).split("\n"):
				if l.begins_with("SIEGE_STATS"):
					lines.append(l)
		print("clients open: %d/%d; received %.1f kB/s per client (%d packets)" % [open, N, rx_bytes / 1024.0 / maxf(t - 2.0, 1.0) / N, rx_packets])
		for l in lines:
			print(l)
		var ok := open == N and lines.size() >= 3
		print("NET_LOAD_PASS" if ok else "NET_LOAD_FAIL")
		quit(0 if ok else 1)
	return false
