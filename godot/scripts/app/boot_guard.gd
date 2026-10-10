extends Node
# BootGuard (autoload, 0.31.72; Vulkan only since 0.31.92). Watches the app start on the phone.
#
# 0.31.92 (Kevin: "Vulkan now works. I'd like to remove the OpenGL version"): the OpenGL (Compatibility) renderer is
# gone. Godot's own fallback is off (rendering_device/fallback_to_opengl3=false, so the Android manifest requires
# Vulkan 1.1 and Play doesn't offer the game to phones without it), project.godot no longer reads user://renderer.cfg,
# and this guard no longer switches renderers. The freezes the switch was for were the 0.31.91 preload deadlock.
#
# What it still does: each start is marked pending until the menu has drawn OK_FRAMES frames. If the last start never
# got there, this start is a SAFE START (no background model loading, no live 3D heroes; SiegeApp reads safe_boot)
# and the frozen start's log is kept as user://boot_diag_stuck.log for COPY DIAGNOSTICS. It is an autoload so its
# _init runs before the main scene loads: the start-up log (user://boot_diag.log, Diag) covers the main scene's
# loading too. Only tracks on Android (or with the FB_BOOT_GUARD env var, for testing on desktop).
const Diag = preload("res://scripts/siege/siege_diag.gd")
const STATE := "user://boot_state.json"
const OLD_RENDERER_CFG := "user://renderer.cfg"   # 0.31.72-0.31.91's OpenGL switch; deleted, no longer read
const OK_FRAMES := 30

var tracking := false
var safe_boot := false
var diag = null
var _t0 := 0
var _frames := 0
var _done := false

static func decide(prev: Dictionary, build: String) -> Dictionary:
	# What this start does, from the last start's record. Pure (tests/boot_guard_test.gd).
	var stuck := bool(prev.get("pending", false))
	return {"stuck": stuck, "safe": stuck or str(prev.get("safe_build", "")) == build}

func _init() -> void:
	name = "BootGuard"
	_t0 = Time.get_ticks_msec()
	tracking = OS.get_name() == "Android" or OS.has_environment("FB_BOOT_GUARD")
	diag = Diag.new()
	diag.log_path = Diag.BOOT_PATH
	diag.prev_path = Diag.BOOT_PREV_PATH
	diag.start_early()
	add_child(diag)
	diag.write("BOOT guard up: renderer %s" % RenderingServer.get_current_rendering_method())
	if not tracking:
		return
	if FileAccess.file_exists(OLD_RENDERER_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OLD_RENDERER_CFG))
		diag.write("BOOT removed the old OpenGL switch file")
	var prev := _read_state()
	var d := decide(prev, Diag.BUILD)
	if bool(d.stuck):
		_keep_stuck_log()
	safe_boot = bool(d.safe)
	_write_state({"pending": true, "build": Diag.BUILD, "safe_build": Diag.BUILD if safe_boot else ""})
	diag.write("BOOT %s (last start %s)" % ["SAFE START" if safe_boot else "normal",
		"never reached the menu" if bool(d.stuck) else "ok"])

func _keep_stuck_log() -> void:
	# The frozen start's log is boot_diag_prev.log right now; the next start would push it out, so keep a copy for
	# COPY DIAGNOSTICS (Diag.BOOT_STUCK_PATH).
	if FileAccess.file_exists(Diag.BOOT_PREV_PATH):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(Diag.BOOT_PREV_PATH), ProjectSettings.globalize_path(Diag.BOOT_STUCK_PATH))

func mark(phase: String) -> void:
	if diag != null and is_instance_valid(diag):
		diag.mark(phase)
		diag.write("BOOT %s (%d ms)" % [phase, Time.get_ticks_msec() - _t0])

func _process(_delta: float) -> void:
	# Frames drawn with the menu up; at OK_FRAMES the start counts as good.
	if _done:
		return
	_frames += 1
	if _frames == 1:
		mark("first frame")
	if _frames >= OK_FRAMES:
		_done = true
		set_process(false)
		if tracking:
			_write_state({"pending": false, "build": Diag.BUILD, "safe_build": Diag.BUILD if safe_boot else ""})
		mark("OK -- menu up%s" % (" (safe start)" if safe_boot else ""))
		var d = diag
		get_tree().create_timer(8.0).timeout.connect(func():         # a few seconds of menu stats, then stop logging
			if is_instance_valid(d):
				d.queue_free())

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
