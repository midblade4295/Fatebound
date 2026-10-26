extends SceneTree
# Runs ws_server.gd alone (tools/parity/services.sh starts it for the C# WebSocketPeer test): writes its port to
# $FB_WS_PORT_FILE, serves until $FB_WS_PORT_FILE.stop exists or 120 s pass.

func _init() -> void:
	var srv = preload("ws_server.gd").new()
	var port: int = srv.start(0)
	var port_file := OS.get_environment("FB_WS_PORT_FILE")
	var f := FileAccess.open(port_file, FileAccess.WRITE)
	f.store_string(str(port))
	f.close()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 120000 and not FileAccess.file_exists(port_file + ".stop"):
		srv.step()
		OS.delay_msec(1)
	quit()
