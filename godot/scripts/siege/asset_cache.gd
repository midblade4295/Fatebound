extends RefCounted
# Shared PackedScene cache for Siege models (was part of the removed dice-era kaykit_stage.gd).
static var _scene_cache: Dictionary = {}

static func scene(path: String) -> PackedScene:
	if not _scene_cache.has(path):
		_scene_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _scene_cache[path]
