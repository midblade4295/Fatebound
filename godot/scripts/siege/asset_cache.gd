extends RefCounted
# Shared PackedScene cache for Siege models (was part of the removed dice-era kaykit_stage.gd).
static var _scene_cache: Dictionary = {}

static func scene(path: String) -> PackedScene:
	if not _scene_cache.has(path):
		var got: Variant = finish(path)
		_scene_cache[path] = got if got != null else (load(path) if ResourceLoader.exists(path) else null)
	return _scene_cache[path]

# ---- background preload (0.31.8: "the game takes long to start after pressing Play") ----
# At app start the menus are idle, so the models a match needs are loaded on a thread then. Pressing Play then finds
# them in the cache. The list is written by tools/preload_list.gd (everything a match build asked for).
const PRELOAD_LIST := "res://assets/terrain/preload.json"   # (.txt files are not exported; JSON is)
static var _pending: Array = []

static func preload_async() -> void:
	if not _pending.is_empty() or not FileAccess.file_exists(PRELOAD_LIST):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PRELOAD_LIST))
	if not parsed is Array:
		return
	for line in parsed:
		var path := str(line).strip_edges()
		if path == "" or _scene_cache.has(path) or _pending.has(path) or not ResourceLoader.exists(path):
			continue
		if ResourceLoader.load_threaded_request(path, "", true) == OK:
			_pending.append(path)

static func poll() -> void:
	# Move finished loads into the cache (call from a timer or _process while in the menus).
	for i in range(_pending.size() - 1, -1, -1):
		var path: String = _pending[i]
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
			_scene_cache[path] = ResourceLoader.load_threaded_get(path)
			_pending.remove_at(i)
		elif ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_FAILED:
			_pending.remove_at(i)

static func finish(path: String) -> Variant:
	# A pending load that is needed right now: wait for it.
	if _pending.has(path):
		_pending.erase(path)
		return ResourceLoader.load_threaded_get(path)
	return null
