extends RefCounted
# The WebSocket test server for the services parity test (godot_services.gd runs it in-process; godot_ws_server.gd
# runs it alone for the C# client). Binary packets: bytes_to_var; {"t":"bye"} -> a bye message, then (150 ms later)
# close(4006, "bye now"); a PackedByteArray comes back as it is; anything else as {"echo": value, "n": size}. Text
# packets come back as "echo:" + text.

var tcp := TCPServer.new()
var peers := []

func start(port := 0) -> int:
	var err := tcp.listen(port, "127.0.0.1")
	if err != OK:
		return -1
	return tcp.get_local_port()

func step() -> void:
	while tcp.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = 1 << 20
		ws.outbound_buffer_size = 1 << 20
		ws.accept_stream(tcp.take_connection())
		peers.append({"ws": ws, "bye_at": -1})
	for pd in peers:
		var ws: WebSocketPeer = pd.ws
		ws.poll()
		if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
			continue
		while ws.get_available_packet_count() > 0:
			var pkt := ws.get_packet()
			if ws.was_string_packet():
				ws.send_text("echo:" + pkt.get_string_from_utf8())
				continue
			var v = bytes_to_var(pkt)
			if v is Dictionary and v.get("t", "") == "bye":
				ws.put_packet(var_to_bytes({"t": "bye", "why": "test"}))
				pd.bye_at = Time.get_ticks_msec() + 150
			elif v is PackedByteArray:
				ws.put_packet(pkt)
			else:
				ws.put_packet(var_to_bytes({"echo": v, "n": pkt.size()}))
		if pd.bye_at >= 0 and Time.get_ticks_msec() >= pd.bye_at:
			ws.close(4006, "bye now")
			pd.bye_at = -1
	peers = peers.filter(func(pd): return pd.ws.get_ready_state() != WebSocketPeer.STATE_CLOSED)
