extends Node
# BootGuard (autoload, 0.31.72). Kevin: "turn on the fallback to OpenGL" -- for phones whose Vulkan can't run the game.
#
# Two fallbacks, Vulkan stays the default (Kevin's S21 is unaffected):
#  1. Godot's own: rendering/rendering_device/fallback_to_opengl3 = true. On Android, Godot checks for Vulkan 1.1 and
#     creates a Vulkan context before the first frame; if either fails it starts on OpenGL (Compatibility) instead.
#     (Godot 4.7.2: Godot.kt getNativeRenderer -> DisplayServerAndroid::check_vulkan_global_context.)
#  2. This guard, for phones where Vulkan *starts* but the game never reaches the menu (testers' Pixel 7 Pro, vivo S30
#     mini, Redmi Note 15 Pro froze on the splash). Each start is marked pending until the menu has drawn OK_FRAMES
#     frames. If the last start on Vulkan never got there, this start writes RENDERER_CFG and restarts the app: Godot
#     reads that file at start-up (application/config/project_settings_override in project.godot), so the phone runs
#     on OpenGL from then on. Settings has a switch back.
# It is an autoload so its _init runs before the main scene is loaded: a hang anywhere in the start counts, and the
# start-up log (user://boot_diag.log, Diag) covers the main scene's loading too. Only active on Android (or with the
# FB_BOOT_GUARD env var, for testing on desktop): tools and tests never switch renderers.
const Diag = preload("res://scripts/siege/siege_diag.gd")
const STATE := "user://boot_state.json"
const RENDERER_CFG := "user://renderer.cfg"       # must match application/config/project_settings_override
const OK_FRAMES := 30
const GL := "gl_compatibility"

var tracking := false
var safe_boot := false
var restarting := false
var renderer := ""          # "mobile" (Vulkan) or "gl_compatibility" (OpenGL) -- what this start is running on
var diag = null
var _t0 := 0
var _frames := 0
var _done := false

static func decide(prev: Dictionary, current: String, override_on: bool, build: String) -> Dictionary:
	# What this start does, from the last start's record. Pure (tests/boot_guard_test.gd).
	var stuck := bool(prev.get("pending", false))
	var prev_vk := str(prev.get("renderer", "mobile")) != GL
	if stuck and prev_vk and current != GL and not override_on:
		return {"action": "switch_gl", "safe": true}
	return {"action": "run", "safe": stuck or str(prev.get("safe_build", "")) == build}

static func renderer_cfg_text(gl: bool) -> String:
	var m := GL if gl else "mobile"
	return "; Fatebound renderer choice (BootGuard). Delete this file to go back to the default (Vulkan).\n[rendering]\n" + \
		"renderer/rendering_method=\"%s\"\nrenderer/rendering_method.mobile=\"%s\"\n" % [m, m]

static func on_opengl_by_choice() -> bool:
	return FileAccess.file_exists(RENDERER_CFG)

func _init() -> void:
	name = "BootGuard"
	_t0 = Time.get_ticks_msec()
	renderer = RenderingServer.get_current_rendering_method()
	tracking = OS.get_name() == "Android" or OS.has_environment("FB_BOOT_GUARD")
	diag = Diag.new()
	diag.log_path = Diag.BOOT_PATH
	diag.prev_path = Diag.BOOT_PREV_PATH
	diag.start_early()
	add_child(diag)
	var why := "renderer file" if on_opengl_by_choice() else ("Godot's Vulkan check failed" if renderer == GL else "default")
	diag.write("BOOT guard up: renderer %s (%s)" % ["OpenGL" if renderer == GL else "Vulkan", why])
	if not tracking:
		return
	var prev := _read_state()
	var d := decide(prev, renderer, on_opengl_by_choice(), Diag.BUILD)
	if d.action == "switch_gl":
		_write_renderer_cfg(true)
		_write_state({"pending": false, "renderer": renderer, "build": Diag.BUILD, "switched": Diag.BUILD})
		diag.write("BOOT the last start on Vulkan never reached the menu -> this phone switches to OpenGL; restarting")
		_keep_stuck_log()
		restarting = true
		return
	safe_boot = bool(d.safe)
	_write_state({"pending": true, "renderer": renderer, "build": Diag.BUILD, "safe_build": Diag.BUILD if safe_boot else ""})
	diag.write("BOOT %s (last start %s)" % ["SAFE START" if safe_boot else "normal",
		"never reached the menu" if bool(prev.get("pending", false)) else "ok"])

func _ready() -> void:
	if restarting:
		_restart()

func _keep_stuck_log() -> void:
	# The frozen start's log is boot_diag_prev.log right now; two more starts (this restart, then OpenGL) would push it
	# out, so keep a copy for COPY DIAGNOSTICS (Diag.BOOT_STUCK_PATH).
	if FileAccess.file_exists(Diag.BOOT_PREV_PATH):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(Diag.BOOT_PREV_PATH), ProjectSettings.globalize_path(Diag.BOOT_STUCK_PATH))

func _restart() -> void:
	# Android: Godot relaunches the app on exit (Main::cleanup -> OS::create_instance -> GodotActivity rebirth). If
	# that doesn't happen, the app just closes and the next launch reads the renderer file anyway.
	if OS.get_name() == "Android":
		OS.set_restart_on_exit(true)
	get_tree().quit()

func mark(phase: String) -> void:
	if diag != null and is_instance_valid(diag):
		diag.mark(phase)
		diag.write("BOOT %s (%d ms)" % [phase, Time.get_ticks_msec() - _t0])

func _process(_delta: float) -> void:
	# Frames drawn with the menu up; at OK_FRAMES the start counts as good.
	if _done or restarting:
		return
	_frames += 1
	if _frames == 1:
		mark("first frame")
	if _frames >= OK_FRAMES:
		_done = true
		set_process(false)
		if tracking:
			_write_state({"pending": false, "renderer": renderer, "build": Diag.BUILD, "safe_build": Diag.BUILD if safe_boot else ""})
		mark("OK -- menu up%s" % (" (safe start)" if safe_boot else ""))
		var d = diag
		get_tree().create_timer(8.0).timeout.connect(func():         # a few seconds of menu stats, then stop logging
			if is_instance_valid(d):
				d.queue_free())

func set_opengl(on: bool) -> void:
	# Settings: the player's own choice (takes effect after a restart). On = write the renderer file; off = delete it.
	_write_renderer_cfg(on)
	if diag != null and is_instance_valid(diag):
		diag.write("BOOT player chose %s; restarting" % ("OpenGL" if on else "Vulkan"))
	restarting = true
	_restart()

func _write_renderer_cfg(gl: bool) -> void:
	if gl:
		var f := FileAccess.open(RENDERER_CFG, FileAccess.WRITE)
		if f != null:
			f.store_string(renderer_cfg_text(true))
			f.close()
	elif FileAccess.file_exists(RENDERER_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RENDERER_CFG))

func _read_state() -> Dictionary:
	if FileAccess.file_exists(STATE):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STATE))
		if parsed is Dictionary:
			return parsed
	return {}

func _write_state(st: Dictionary) -> void:
	var f := FileAccess.open(STATE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(st))
		f.close()
