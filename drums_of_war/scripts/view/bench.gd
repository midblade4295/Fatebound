extends RefCounted
## A cost meter that runs on the device itself.
##
## Guessing what is slow from another machine does not work: phones differ too much. This turns
## each part of the picture off in turn for about a second, reads how long the graphics chip
## and the processor really took per frame with and without it, puts everything back, and
## lists what each part costs, heaviest first. The battle screen starts it when the FPS readout
## is tapped, pauses the battle while it runs, and shows the list for a screenshot.
##
## Times come from the engine's own render timers (GPU and CPU milliseconds per frame), which
## are not rounded to the screen's refresh the way a frame counter is.

var settle: int = 14          # frames to let a change take effect before measuring
var measure: int = 40         # frames averaged

var running: bool = false
var done: bool = false
var lines: PackedStringArray = []       # the finished report
var progress: String = ""

var _screen: Node
var _world: Node
var _viewport: Viewport
var _rid: RID
var _steps: Array = []      # [name, Callable(bool on)]
var _index: int = -1        # -1 while the baseline is measured
var _frames: int = 0
var _gpu: float = 0.0
var _cpu: float = 0.0
var _frame: float = 0.0
var _count: int = 0
var _last_usec: int = 0
var _base: Array = [0.0, 0.0, 0.0]      # gpu, cpu, frame (ms)
var _found: Array = []      # [name, gpu saved, cpu saved, frame saved]
var _saved_level: int = 0
var _saved_vsync: int = 0
var _base_tris: int = 0
var _base_draws: int = 0
var _base_script: float = 0.0


func start(screen: Node) -> void:
	_screen = screen
	_world = screen.world
	_viewport = screen.get_viewport()
	_rid = _viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_rid, true)
	var arena: Node = _world.arena
	_steps = [
		["Bloom", func(on: bool) -> void: _world._env.glow_enabled = on],
		["Antialiasing (2x)", func(on: bool) -> void: _viewport.msaa_3d = Viewport.MSAA_2X if on else Viewport.MSAA_DISABLED],
		["Live shadows", func(on: bool) -> void: _world._sun.shadow_enabled = on],
		["Fill and rim lights", func(on: bool) -> void:
			_world._fill.visible = on
			_world._rim.visible = on],
		["Trees and bushes", func(on: bool) -> void: arena.show_group("plants", on)],
		["Grass and flowers", func(on: bool) -> void: arena.show_group("grass", on)],
		["Fences, rocks, bridge", func(on: bool) -> void: arena.show_group("props", on)],
		["Buildings", func(on: bool) -> void:
			for id in _world._structures:
				_world._structures[id].visible = on],
		["River", func(on: bool) -> void: arena.show_group("water", on)],
		["Ground detail", func(on: bool) -> void: arena.set_plain_ground(not on)],
		["Leaves and motes", func(on: bool) -> void:
			arena.show_group("litter", on)
			arena.set_extras(on)],
		["Troops and smoke", func(on: bool) -> void: _world.show_troops(on)],
		["HUD and cards", func(on: bool) -> void: _screen.set_hud_hidden(not on)],
		["(test) half resolution", func(on: bool) -> void: _viewport.scaling_3d_scale = 1.0 if on else 0.5],
		["(test) whole 3D scene", func(on: bool) -> void: _viewport.disable_3d = not on],
	]
	_saved_level = screen.quality.level
	screen.quality.level = 0
	screen.quality.apply(_world, _viewport)
	# Let frames come as fast as the device can make them, if it will allow that.
	_saved_vsync = DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_found.clear()
	lines = PackedStringArray()
	_index = -1
	_begin_step()
	running = true
	done = false


func _begin_step() -> void:
	_frames = 0
	_gpu = 0.0
	_cpu = 0.0
	_frame = 0.0
	_count = 0
	_last_usec = 0
	progress = "Measuring %d of %d: %s" % [_index + 2, _steps.size() + 1, "everything on" if _index < 0 else String(_steps[_index][0])]


## Call once per drawn frame while running.
func tick() -> void:
	if not running:
		return
	var now := Time.get_ticks_usec()
	_frames += 1
	if _frames > settle and _last_usec > 0:
		_gpu += RenderingServer.viewport_get_measured_render_time_gpu(_rid)
		_cpu += RenderingServer.viewport_get_measured_render_time_cpu(_rid) + RenderingServer.get_frame_setup_time_cpu()
		_frame += (now - _last_usec) / 1000.0
		_count += 1
	_last_usec = now
	if _count < measure:
		return
	var got := [_gpu / _count, _cpu / _count, _frame / _count]
	if _index < 0:
		_base = got
		_base_tris = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		_base_draws = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		_base_script = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	else:
		_found.append([_steps[_index][0], _base[0] - got[0], _base[1] - got[1], _base[2] - got[2]])
		(_steps[_index][1] as Callable).call(true)
	_index += 1
	if _index >= _steps.size():
		_finish()
		return
	(_steps[_index][1] as Callable).call(false)
	_begin_step()


func _finish() -> void:
	running = false
	done = true
	DisplayServer.window_set_vsync_mode(_saved_vsync)
	_screen.quality.level = _saved_level
	_screen.quality.apply(_world, _viewport)
	var has_gpu: bool = _base[0] > 0.05
	var size := DisplayServer.window_get_size()
	lines.append("%s  |  %s" % [OS.get_model_name(), RenderingServer.get_video_adapter_name()])
	var hz := DisplayServer.screen_get_refresh_rate()
	lines.append("%d x %d px, screen %s Hz, %s" % [size.x, size.y, str(int(hz)) if hz >= 1.0 and hz < 1000.0 else "?", String(RenderingServer.get_current_rendering_method())])
	lines.append("Everything on:  frame %.1f ms (%d FPS)   GPU %.1f ms   CPU draw %.1f ms   scripts %.1f ms" % [
			_base[2], int(round(1000.0 / maxf(_base[2], 0.1))), _base[0], _base[1], _base_script])
	lines.append("%d triangles, %d draw calls per frame" % [_base_tris, _base_draws])
	lines.append("")
	lines.append("What each part costs per frame, in ms (heaviest first):" + ("" if has_gpu else "  (no GPU timer here: frame time only)"))
	var key := 1 if has_gpu else 3
	_found.sort_custom(func(a: Array, b: Array) -> bool: return float(a[key]) > float(b[key]))
	for f: Array in _found:
		if has_gpu:
			lines.append("%s:   GPU %.1f   CPU %.1f   whole frame %.1f" % [f[0], float(f[1]), float(f[2]), float(f[3])])
		else:
			lines.append("%s:   whole frame %.1f   CPU %.1f" % [f[0], float(f[3]), float(f[2])])
	lines.append("")
	lines.append("60 FPS needs the whole frame under 16.7 ms. Small or negative numbers are noise.")
	lines.append("Screenshot this, then tap to close.")
	print("DRUMS_BENCH\n" + "\n".join(lines))
