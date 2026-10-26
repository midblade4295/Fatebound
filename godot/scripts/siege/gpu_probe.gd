extends Node
# 0.31.219 (Kevin: "Honor of kings gives me 120fps solid. This game I can hardly hit 30"): what each part of the picture
# costs the phone's graphics chip, measured on the phone. The engine's own per-pass timings are only for its editor
# profiler, so a test build switches one thing off for OFF_T seconds, measures the graphics chip's time on the 3D view
# (gpu3d) and on the screen (gpuhud), switches it back and measures again right after: the difference is that thing's
# cost, in the same fight. Two rounds of every test from START seconds into a 5v5 against bots, each written to the
# match log as a PROBE line and summed up at the end (PROBE SUMMARY). The ones that would hide what you're playing
# with (the HUD) wait until you're down. Off (never made) online, in the training, headless, or with FB_NO_PROBE.
const View = preload("res://scripts/siege/siege_view.gd")
const START := 40.0          # match seconds before the first test (the first waves are fighting by then)
const OFF_T := 2.0
const ON_T := 2.0
const SETTLE := 0.6          # (the first part of each half not measured: the change shows a frame or two late)
const ROUNDS := 2
const TESTS := ["none", "shadows", "hard_shadows", "glow", "msaa", "fog", "scale40", "terrain_plain", "plants", "outer", "vignette", "hud"]
const DEAD_ONLY := ["hud"]
const PLANT_KINDS := ["ridges", "edge_trees", "brush", "foliage", "fords"]
const OUTER_KINDS := ["outer_land", "outer_trees"]

var mode
var _queue: Array = []
var _cur := ""
var _half := ""              # "off" | "on"
var _t := 0.0
var _acc := [0.0, 0.0, 0, 0.0]   # gpu3d, gpuhud, frames, seconds
var _off := []
var _results := {}           # test -> [[saves3d, saveshud], ...]
var _restore: Callable
var _plain: Shader = null
var _done := false

static func wanted(m) -> bool:
	return not m.online and not m.tutorial and DisplayServer.get_name() != "headless" and not OS.has_environment("FB_NO_PROBE") \
		and RenderingServer.get_rendering_device() != null

var _start := START

func _ready() -> void:
	if OS.has_environment("FB_PROBE_START"):
		_start = float(OS.get_environment("FB_PROBE_START"))       # (tools)
	for r in ROUNDS:
		_queue.append_array(TESTS)

func _sim_ok() -> bool:
	return mode != null and mode.sim != null and is_instance_valid(mode.view) and not mode.sim.ended

func _process(delta: float) -> void:
	if _done or not _sim_ok():
		return
	if _cur == "":
		if float(mode.sim.time) < _start or not mode.warmed():
			return
		_next()
		return
	_t += delta
	var settle := SETTLE + (0.6 if _cur == "terrain_plain" else 0.0)   # (its stand-in shader compiles first)
	if _t >= settle:
		var v3: RID = mode.viewport.get_viewport_rid()
		var root: RID = get_viewport().get_viewport_rid()
		_acc[0] += RenderingServer.viewport_get_measured_render_time_gpu(v3)
		_acc[1] += RenderingServer.viewport_get_measured_render_time_gpu(root)
		_acc[2] += 1
		_acc[3] += delta
	if _half == "off" and _t >= OFF_T:
		_off = _acc.duplicate()
		_undo()
		_half = "on"
		_t = 0.0
		_acc = [0.0, 0.0, 0, 0.0]
	elif _half == "on" and _t >= ON_T:
		_report(_cur, _off, _acc)
		_cur = ""
		_next()

func _next() -> void:
	# the next test that can run now (the HUD's waits until you're down)
	var me: Dictionary = mode.sim.by_id.get(mode.hud.player_id, {})
	var dead: bool = str(me.get("state", "")) == "dead" and float(me.get("respawn_at", 0.0)) - float(mode.sim.time) > OFF_T + ON_T
	for i in _queue.size():
		var name: String = _queue[i]
		if name in DEAD_ONLY and not dead:
			continue
		_queue.remove_at(i)
		if not _apply(name):
			_write("PROBE %s: skipped (already off here)" % name)
			return
		_cur = name
		_half = "off"
		_t = 0.0
		_acc = [0.0, 0.0, 0, 0.0]
		return
	if _queue.is_empty() or _queue.all(func(n): return n in DEAD_ONLY) and float(mode.sim.time) > _start + 600.0:
		_finish()

func _apply(name: String) -> bool:
	# switch it off; _restore switches it back -> false when it's off already (nothing to measure)
	var view = mode.view
	match name:
		"none":
			_restore = func(): pass            # (nothing switched: how much two halves differ by themselves -- the noise)
		"shadows", "hard_shadows":
			var sun := _sun()
			if sun == null or not sun.shadow_enabled:
				return false
			if name == "shadows":
				sun.shadow_enabled = false
				_restore = func(): sun.shadow_enabled = true
			else:
				RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
				_restore = func(): RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
		"glow", "fog":
			var env := _env()
			if env == null:
				return false
			if name == "glow":
				if not env.glow_enabled:
					return false
				env.glow_enabled = false
				_restore = func(): env.glow_enabled = true
			else:
				if not env.fog_enabled:
					return false
				env.fog_enabled = false
				_restore = func(): env.fog_enabled = true
		"msaa":
			var was: Viewport.MSAA = mode.viewport.msaa_3d
			if was == Viewport.MSAA_DISABLED:
				return false
			mode.viewport.msaa_3d = Viewport.MSAA_DISABLED
			_restore = func(): mode.viewport.msaa_3d = was
		"scale40":
			var rs: float = mode.render_scale
			mode.set_render_scale(rs * 0.8)                  # (50 % -> 40 %: the share of the cost that goes with pixels)
			_restore = func(): mode.set_render_scale(rs)
		"terrain_plain":
			var tm: ShaderMaterial = View._terrain_mat
			if tm == null:
				return false
			if _plain == null:
				_plain = Shader.new()
				_plain.code = "shader_type spatial;\nrender_mode specular_disabled;\nvoid fragment() { ALBEDO = vec3(0.24, 0.36, 0.2); ROUGHNESS = 0.95; }\n"
			var sh: Shader = tm.shader
			tm.shader = _plain
			_restore = func(): tm.shader = sh
		"plants", "outer":
			var kinds: Array = PLANT_KINDS if name == "plants" else OUTER_KINDS
			var hid := []
			for c in view.get_children():
				if c is Node3D and (c as Node3D).visible and c.has_meta("perf") and str(c.get_meta("perf")).trim_suffix("_shadow") in kinds:
					(c as Node3D).visible = false
					hid.append(c)
			if hid.is_empty():
				return false
			_restore = func():
				for c in hid:
					if is_instance_valid(c):
						(c as Node3D).visible = true
		"vignette":
			var vg: CanvasItem = mode.vignette
			if vg == null or not vg.visible:
				return false
			vg.visible = false
			_restore = func(): vg.visible = true
		"hud":
			var h: CanvasItem = mode.hud
			if not h.visible:
				return false
			h.visible = false
			_restore = func(): h.visible = true
		_:
			return false
	return true

func _undo() -> void:
	if _restore.is_valid():
		_restore.call()
	_restore = Callable()

func _sun() -> DirectionalLight3D:
	for n in mode.view.find_children("*", "DirectionalLight3D", true, false):
		return n
	return null

func _env() -> Environment:
	for n in mode.view.find_children("*", "WorldEnvironment", true, false):
		return (n as WorldEnvironment).environment
	return null

func _report(name: String, off: Array, on: Array) -> void:
	var fo := maxf(1.0, float(off[2]))
	var fn := maxf(1.0, float(on[2]))
	var o3 := float(off[0]) / fo
	var oh := float(off[1]) / fo
	var n3 := float(on[0]) / fn
	var nh := float(on[1]) / fn
	var r: Array = _results.get(name, [])
	r.append([n3 - o3, nh - oh])
	_results[name] = r
	_write("PROBE %s: off gpu3d %.1f gpuhud %.1f ms %.0f fps | on gpu3d %.1f gpuhud %.1f ms %.0f fps | it costs %.1f + %.1f ms" % [name,
		o3, oh, float(off[2]) / maxf(0.01, float(off[3])), n3, nh, float(on[2]) / maxf(0.01, float(on[3])), n3 - o3, nh - oh])

func _finish() -> void:
	_done = true
	var parts := PackedStringArray()
	for name in TESTS:
		var r: Array = _results.get(name, [])
		if r.is_empty():
			continue
		var s3 := 0.0
		var sh := 0.0
		for x in r:
			s3 += float(x[0])
			sh += float(x[1])
		parts.append("%s %.1f+%.1f" % [name, s3 / r.size(), sh / r.size()])
	_write("PROBE SUMMARY (ms of graphics chip a frame, 3D + screen, mean of %d rounds): %s" % [ROUNDS, ", ".join(parts)])

func _write(line: String) -> void:
	if mode != null and mode.diag != null:
		mode.diag.write(line)

func _exit_tree() -> void:
	_undo()                                # (a test running as the match ends: everything back as it was)
	if not _done and not _results.is_empty():
		_finish()
