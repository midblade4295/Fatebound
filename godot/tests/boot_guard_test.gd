extends SceneTree
# BootGuard's decision (0.31.72): when a start switches the phone to OpenGL, when it is a safe start, and that the
# renderer file it writes is a settings override Godot reads (both the base key and the Android ".mobile" one).
const BootGuard = preload("res://scripts/app/boot_guard.gd")
const B := "0.31.72-fatebound"

func _init() -> void:
	var VK := "mobile"
	var GL := "gl_compatibility"
	# First start ever, and a normal start after a good one: run, not safe.
	assert(BootGuard.decide({}, VK, false, B) == {"action": "run", "safe": false})
	assert(BootGuard.decide({"pending": false, "renderer": VK, "build": B}, VK, false, B).action == "run")
	# The last start on Vulkan never reached the menu: switch to OpenGL (and restart).
	assert(BootGuard.decide({"pending": true, "renderer": VK, "build": B}, VK, false, B).action == "switch_gl")
	# ... also when that record came from 0.31.70/71, which didn't store the renderer (they were Vulkan-only).
	assert(BootGuard.decide({"pending": true, "build": "0.31.71-fatebound"}, VK, false, B).action == "switch_gl")
	# Stuck on OpenGL: never switch again (no loop); a safe start instead.
	assert(BootGuard.decide({"pending": true, "renderer": GL, "build": B}, GL, true, B) == {"action": "run", "safe": true})
	# The renderer file exists but this start is still Vulkan (file not applied): don't restart forever.
	assert(BootGuard.decide({"pending": true, "renderer": VK, "build": B}, VK, true, B) == {"action": "run", "safe": true})
	# Safe start sticks for the build it happened in, not the next build.
	assert(BootGuard.decide({"pending": false, "renderer": GL, "safe_build": B}, GL, true, B).safe == true)
	assert(BootGuard.decide({"pending": false, "renderer": GL, "safe_build": "0.31.71-fatebound"}, GL, true, B).safe == false)
	# The renderer file parses as project settings with both keys.
	for gl in [true, false]:
		var cf := ConfigFile.new()
		assert(cf.parse(BootGuard.renderer_cfg_text(gl)) == OK)
		var want := GL if gl else VK
		assert(str(cf.get_value("rendering", "renderer/rendering_method")) == want)
		assert(str(cf.get_value("rendering", "renderer/rendering_method.mobile")) == want)
	# project.godot points Godot at that file, keeps Vulkan as the default and Godot's own fallback on.
	assert(str(ProjectSettings.get_setting("application/config/project_settings_override")) == BootGuard.RENDERER_CFG)
	assert(bool(ProjectSettings.get_setting("rendering/rendering_device/fallback_to_opengl3")))
	assert(str(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile")) == VK or FileAccess.file_exists(BootGuard.RENDERER_CFG))
	print("BOOT_GUARD_PASS")
	quit(0)
