extends SceneTree
# Dev tool (0.31.142): the app started from its boot screen (Boot.tscn) as the phone starts it, printing every frame
# that took over 150 ms and every frame in which the renderer compiled pipelines ("draw" ones stop the frame: the
# MSAA SubViewports did, 4.5 s on Kevin's S21). Never reaches the live server (SIEGE_URL is set dead).
#   Xvfb :98 & DISPLAY=:98 PROBE_S=30 godot --rendering-method mobile --resolution 420x933 --path godot \
#     -s res://tools/boot_probe.gd
var last := 0
var n := 0
var t0 := 0
var prev := {}
const INFO := {"canvas": RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS, "mesh": RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
	"surface": RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE, "draw": RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
	"spec": RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION}
func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")
	t0 = Time.get_ticks_msec()
	last = t0
func _process(_d: float) -> bool:
	n += 1
	if n == 2:
		change_scene_to_file("res://scenes/Boot.tscn")
	var now := Time.get_ticks_msec()
	var gap := now - last
	last = now
	var cur := current_scene
	var nm := "?" if cur == null or cur.get_script() == null else str(cur.get_script().resource_path.get_file())
	var d := ""
	for k in INFO:
		var v := RenderingServer.get_rendering_info(INFO[k])
		if v != int(prev.get(k, 0)):
			d += " %s+%d" % [k, v - int(prev.get(k, 0))]
		prev[k] = v
	if gap > 150 or d != "":
		print("F%4d %6d ms gap %5d  %s  tex %.0fMB%s" % [n, now - t0, gap, nm, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0, d])
	return now - t0 > float(OS.get_environment("PROBE_S") if OS.has_environment("PROBE_S") else "30") * 1000.0
