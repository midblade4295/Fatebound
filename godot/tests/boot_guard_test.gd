extends SceneTree
# BootGuard's decision (0.31.72; Vulkan only since 0.31.92): when a start is a safe start and keeps the frozen start's
# log, and that the project is Vulkan with no OpenGL fallback and no renderer switch file.
const BootGuard = preload("res://scripts/app/boot_guard.gd")
const B := "0.31.92-fatebound"

func _init() -> void:
	# First start ever, and a normal start after a good one: not stuck, not safe.
	assert(BootGuard.decide({}, B) == {"stuck": false, "safe": false})
	assert(BootGuard.decide({"pending": false, "build": B}, B) == {"stuck": false, "safe": false})
	# The last start never reached the menu: a safe start that keeps that start's log.
	assert(BootGuard.decide({"pending": true, "build": B}, B) == {"stuck": true, "safe": true})
	# ... also from a 0.31.72-0.31.91 record (it stored the renderer; the renderer no longer matters).
	assert(BootGuard.decide({"pending": true, "renderer": "gl_compatibility", "build": "0.31.91-fatebound"}, B) == {"stuck": true, "safe": true})
	# Safe start sticks for the build it happened in, not the next build.
	assert(BootGuard.decide({"pending": false, "safe_build": B}, B).safe == true)
	assert(BootGuard.decide({"pending": false, "safe_build": "0.31.91-fatebound"}, B).safe == false)
	# Vulkan (Mobile) only: Godot's OpenGL fallback off, no settings override file read at start-up.
	assert(str(ProjectSettings.get_setting("rendering/renderer/rendering_method")) == "mobile")
	assert(str(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile")) == "mobile")
	assert(not bool(ProjectSettings.get_setting("rendering/rendering_device/fallback_to_opengl3")))
	assert(str(ProjectSettings.get_setting("application/config/project_settings_override")) == "")
	print("BOOT_GUARD_PASS")
	quit(0)
