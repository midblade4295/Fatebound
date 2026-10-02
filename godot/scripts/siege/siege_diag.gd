extends Node
# Siege field diagnostics (alpha builds). Writes user://siege_diag.log, flushed every line so it
# survives a freeze or force-close:
#  - one stats line per second (fps, worst frame, memory, video memory, draw calls, objects, match state)
#  - every engine/script error and warning, via an OS logger
#  - a watchdog thread: if frames stop for >2 s it logs which phase the main thread was last in,
#    which separates "stuck in game code" from "stuck in the renderer/driver".
const PATH := "user://siege_diag.log"
const PREV_PATH := "user://siege_diag_prev.log"
const BUILD := "0.31.6-fatebound"

class ErrorCapture:
	extends Logger
	var sink: Callable
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		sink.call("%s %s:%d %s %s %s" % [["ERROR","WARNING","SCRIPT","SHADER"][clampi(error_type, 0, 3)], file.get_file(), line, function, code, rationale])
	func _log_message(message: String, error: bool) -> void:
		if error:
			sink.call("STDERR " + message.strip_edges())

var mode  # siege_mode, for match state
var _file: FileAccess
var _mutex := Mutex.new()
var _logger: ErrorCapture
var _watchdog: Thread
var _quit := false
var _phase := "start"
var _beat_ms := 0
var _stalled := false
var _stall_at := 0
var _second := 0.0
var _worst_ms := 0.0
var _last_frame_us := 0
var _events := 0
var _error_lines := 0
var fps_text := ""
var _times := {}   # label -> [total_us, max_us, count]

func add_time(label: String, us: int) -> void:
	var t: Array = _times.get(label, [0, 0, 0])
	t[0] += us
	t[1] = maxi(t[1], us)
	t[2] += 1
	_times[label] = t

func _times_text() -> String:
	var parts := PackedStringArray()
	for k in _times:
		var t: Array = _times[k]
		parts.append("%s=%.1f/%.1fms" % [k, t[0] / 1000.0 / maxf(1, t[2]), t[1] / 1000.0])
	_times.clear()
	return " ".join(parts)

func _viewport_text() -> String:
	# Draw calls/triangles split by the 3D SubViewport vs the HUD canvas.
	if mode == null or mode.viewport == null:
		return ""
	var v3: RID = mode.viewport.get_viewport_rid()
	var root: RID = get_viewport().get_viewport_rid()
	var I := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE
	var C := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS
	var D := RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME
	var P := RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME
	return "3d_draws=%d 3d_prims=%d hud_draws=%d" % [RenderingServer.viewport_get_render_info(v3, I, D),
		RenderingServer.viewport_get_render_info(v3, I, P), RenderingServer.viewport_get_render_info(root, C, D)]

func _ready() -> void:
	# Keep the previous session's log (the one that froze) before starting a new one.
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREV_PATH))
		DirAccess.rename_absolute(ProjectSettings.globalize_path(PATH), ProjectSettings.globalize_path(PREV_PATH))
	_file = FileAccess.open(PATH, FileAccess.WRITE)
	write("SESSION %s | %s %s | %s | %s | GPU %s %s | renderer %s (%s)" % [Time.get_datetime_string_from_system(), OS.get_name(), OS.get_version(),
		OS.get_model_name(), BUILD, RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_name(),
		RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_api_version()])
	_logger = ErrorCapture.new()
	_logger.sink = func(line: String):
		_error_lines += 1
		if _error_lines <= 400:
			write(line)
	OS.add_logger(_logger)
	_beat_ms = Time.get_ticks_msec()
	RenderingServer.frame_post_draw.connect(_on_frame_drawn)
	_watchdog = Thread.new()
	_watchdog.start(_watch)

func _exit_tree() -> void:
	_mutex.lock()
	_quit = true
	_mutex.unlock()
	if _watchdog != null and _watchdog.is_started():
		_watchdog.wait_to_finish()
	if RenderingServer.frame_post_draw.is_connected(_on_frame_drawn):
		RenderingServer.frame_post_draw.disconnect(_on_frame_drawn)
	if _logger != null:
		OS.remove_logger(_logger)
	write("SESSION END")

var _writing := false

func write(line: String) -> void:
	_mutex.lock()
	if _file != null and not _writing:
		_writing = true
		_file.store_line("%8.2f %s" % [Time.get_ticks_msec() / 1000.0, line])
		_file.flush()
		_writing = false
	_mutex.unlock()

func mark(phase: String) -> void:
	# Breadcrumb for the watchdog: the last phase the main thread entered.
	_mutex.lock()
	_phase = phase
	_mutex.unlock()

func event() -> void:
	_events += 1

func _capture_logcat(label: String) -> void:
	write("LOGCAT BEGIN (%s)" % label)
	var t0 := Time.get_ticks_msec()
	var text := logcat_tail(60)
	for line in text.split("\n", false):
		write("LOGCAT " + line)
	write("LOGCAT END (%d ms)" % (Time.get_ticks_msec() - t0))

func _on_frame_drawn() -> void:
	# If a stall's last phase is "frame drawn" or "hud draw", the main thread finished our code and
	# hung inside rendering/the GPU driver rather than in game logic.
	mark("frame drawn")

func _watch() -> void:
	while true:
		OS.delay_msec(250)
		_mutex.lock()
		var quit := _quit
		var since := Time.get_ticks_msec() - _beat_ms
		var phase := _phase
		_mutex.unlock()
		if quit:
			return
		if since > 2000 and not _stalled:
			_stalled = true
			_stall_at = Time.get_ticks_msec()
			write("STALL no frame for %d ms; main thread last in: %s" % [since, phase])
			_capture_logcat("at stall")
		elif since > 2000 and Time.get_ticks_msec() - _stall_at > 5000:
			_stall_at = Time.get_ticks_msec()
			write("STILL STALLED %d ms; last phase: %s" % [since, phase])
			if since > 6000 and since < 12000:
				_capture_logcat("6 s into stall")
		elif since <= 2000 and _stalled:
			_stalled = false
			write("RECOVERED")

func _process(delta: float) -> void:
	_mutex.lock()
	_beat_ms = Time.get_ticks_msec()
	_mutex.unlock()
	var now := Time.get_ticks_usec()
	if _last_frame_us > 0:
		_worst_ms = maxf(_worst_ms, (now - _last_frame_us) / 1000.0)
	_last_frame_us = now
	_second += delta
	if _second < 1.0:
		return
	_second = 0.0
	var vmem := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var smem := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var fps := Engine.get_frames_per_second()
	fps_text = "%d fps · %d MB · %d vMB" % [fps, int(smem), int(vmem)]
	var state := ""
	if mode != null and mode.sim != null:
		var s = mode.sim
		var me: Dictionary = s.by_id.get("you", {})
		state = "t=%.0f score=%s kills=%s me=%s/%s hp=%.0f carry=%s fx=%d proj=%d" % [s.time, str(s.score), str(s.kills),
			me.get("cls", "?"), me.get("state", "?"), me.get("hp", 0.0), me.get("carrying", false),
			mode.view._fx.size() if mode.view != null else -1, s.projectiles.size()]
	write("STAT fps=%d worst=%.0fms %s %s proc=%.1fms mem=%.1fMB vmem=%.1fMB tex=%.1fMB draws=%d prims=%d objs=%d nodes=%d ev=%d %s" % [fps, _worst_ms, _times_text(), _viewport_text(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, smem, vmem,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT), _events, state])
	_worst_ms = 0.0
	_events = 0

# Android log capture. Only warnings and above (*:W) from the main, system and crash buffers, so
# window/touch chatter (VRI, InsetsController, ... all Info/Debug) can't crowd out a crash report.
# Native crash reports are F/DEBUG + F/libc; GPU driver errors are E/Adreno*, E/kgsl.
const LOGCAT_NOISE := ["InsetsController", "VRI[", "BLASTBuffer", "SurfaceView", "GestureDetector", "RegularContextFactory"]

static func _logcat_run(buffers: Array) -> Array:
	var args := ["-d", "-v", "time"]
	for b in buffers:
		args.append_array(["-b", b])
	args.append("*:W")
	var out: Array = []
	var err := OS.execute("/system/bin/logcat", args, out, true)
	return [err, str(out[0]) if not out.is_empty() else ""]

static func logcat_tail(keep_other := 120) -> String:
	if OS.get_name() != "Android":
		return ""
	var r := _logcat_run(["main", "system", "crash"])
	if int(r[0]) != OK or str(r[1]).strip_edges() == "" or str(r[1]).contains("Unable to open"):
		r = _logcat_run(["main", "system"])
	if int(r[0]) != OK:
		return "logcat unavailable (error %d)" % int(r[0])
	return filter_logcat(str(r[1]), keep_other)

static func filter_logcat(raw: String, keep_other := 120) -> String:
	var fatal := PackedStringArray()
	var other := PackedStringArray()
	for line in raw.split("\n", false):
		var l := line.strip_edges()
		if l == "" or l.begins_with("---------"):
			continue
		var noisy := false
		for n in LOGCAT_NOISE:
			if l.contains(n):
				noisy = true
				break
		if noisy:
			continue
		# Every fatal line (crash header, signal, abort message, full backtrace) is kept.
		if l.contains(" F/") or l.contains("F/DEBUG") or l.contains("F/libc") or l.contains("Fatal signal") or l.contains("Abort message"):
			fatal.append(l)
		else:
			other.append(l)
	if fatal.size() > 400:
		fatal = fatal.slice(fatal.size() - 400)
	if other.size() > keep_other:
		other = other.slice(other.size() - keep_other)
	return "-- fatal (%d) --\n%s\n-- errors/warnings (last %d) --\n%s" % [fatal.size(), "\n".join(fatal), other.size(), "\n".join(other)]

static func has_logs() -> bool:
	return FileAccess.file_exists(PATH) or FileAccess.file_exists(PREV_PATH)

static func read_logs(tail := 120) -> String:
	# Both sessions (older first), each trimmed to its session header, every STALL/ERROR line and
	# the last `tail` lines, so it pastes into a chat in one piece.
	var out := ""
	for p in [PREV_PATH, PATH]:
		if not FileAccess.file_exists(p):
			continue
		var lines := FileAccess.get_file_as_string(p).split("\n", false)
		var keep := PackedStringArray()
		for i in lines.size():
			var l: String = lines[i]
			if i == 0 or i >= lines.size() - tail or l.contains("STALL") or l.contains("ERROR") or l.contains("RECOVERED") or l.contains("SESSION"):
				keep.append(l)
		out += "==== %s (%d lines) ====\n%s\n" % [p.get_file(), lines.size(), "\n".join(keep)]
	var lc := logcat_tail(120)
	if lc != "":
		out += "==== logcat (this app, warnings+, crash buffer) ====\n%s\n" % lc
	return out
