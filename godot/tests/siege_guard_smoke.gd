extends SceneTree
# Round 32: Siege is hard-locked at 30 fps (no fps options). 0.31.163 (Kevin: "lock it to 30fps and 50% resolution.
# Remove settings so players don't see"): the 3D at 50 % too, with no RESOLUTION button and no heat guard to change it.
# Forced down to ~20 fps with a real per-frame delay, the cap stays 30, the physics 30 Hz and the resolution 50 %.
# 0.31.218 (Kevin: "Honor of kings gives me 120fps solid"): the cap 60 (Mode.FPS_CAP), the physics with it.
const Mode = preload("res://scripts/siege/siege_mode.gd")
var mode
var start := 0
func _init() -> void:
	mode = Mode.new()
	root.add_child(mode)
	start = Time.get_ticks_msec()
func _process(delta: float) -> bool:
	OS.delay_msec(48)
	if Time.get_ticks_msec() - start > 1500:
		assert(Engine.max_fps == Mode.FPS_CAP and Mode.FPS_CAP == 60, "Siege runs at a 60 fps cap (%d)" % Engine.max_fps)
		assert(Engine.physics_ticks_per_second == Mode.FPS_CAP, "physics at the cap's rate (%d)" % Engine.physics_ticks_per_second)
	if Time.get_ticks_msec() - start > 12000:          # (long enough for the old guard's 5 slow seconds)
		assert(absf(mode.render_scale - 0.5) < 0.01, "the 3D stays at 50%% (scale %.2f)" % mode.render_scale)
		var win := Vector2(DisplayServer.window_get_size())
		var logical: Vector2 = root.get_visible_rect().size
		var phys := win / logical if logical.x > 0.0 and win.x > 0.0 else Vector2.ONE     # (as siege_mode._resize_viewport)
		var want := Vector2i(maxi(64, int(mode.size.x * phys.x * 0.5)), maxi(64, int(mode.size.y * phys.y * 0.5)))
		assert(mode.viewport.size == want, "the 3D view is drawn at half the screen's pixels (%s, want %s)" % [mode.viewport.size, want])
		assert(Engine.max_fps == Mode.FPS_CAP)
		# no resolution setting in the pause menu
		if mode.hud.pause_panel == null:
			mode.hud._build_pause_panel()
		for b in mode.hud.pause_panel.find_children("*", "Button", true, false):
			assert(not str((b as Button).text).to_upper().contains("RESOLUTION"), "no RESOLUTION button in the pause menu")
		print("SIEGE_GUARD_PASS max_fps=", Engine.max_fps, " render_scale=", mode.render_scale, " 3d=", mode.viewport.size)
		mode.queue_free()
		quit(0)
	return false
