extends RefCounted
# Shared resource cache for Siege: models (PackedScene), textures and baked animation libraries, loaded once per
# session (was the dice-era kaykit_stage.gd's scene cache; 0.31.78: any resource, so the background preload covers the
# textures and the Meshy bodies' animations too, which used to load synchronously -- and the first Crusader or Berserker
# of a match froze the phone for a moment).
static var _cache: Dictionary = {}       # path -> Resource (null when the file is missing)

static func res(path: String) -> Resource:
	if not _cache.has(path):
		var got: Variant = finish(path)
		_cache[path] = got if got != null else (load(path) if ResourceLoader.exists(path) else null)
	return _cache[path]

static func scene(path: String) -> PackedScene:
	return res(path) as PackedScene

static func texture(path: String) -> Texture2D:
	return res(path) as Texture2D

static func has(path: String) -> bool:
	return _cache.has(path)

# ---- background preload (0.31.8: "the game takes long to start after pressing Play") ----
# At app start the menus are idle, so everything a match needs is loaded on a thread then (the list is written by
# tools/preload_list.gd: whatever a match build asked the cache for, every class body with its animations, and the
# start-up cache). Pressing Play then finds it all here; a path still loading is waited for (finish).
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
		if path == "" or _cache.has(path) or _pending.has(path) or not ResourceLoader.exists(path):
			continue
		if ResourceLoader.load_threaded_request(path, "", true) == OK:
			_pending.append(path)

static func poll() -> void:
	# Move finished loads into the cache (call from a timer or _process while in the menus).
	for i in range(_pending.size() - 1, -1, -1):
		var path: String = _pending[i]
		var st := ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			_cache[path] = ResourceLoader.load_threaded_get(path)
			_pending.remove_at(i)
		elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_pending.remove_at(i)

static func pending() -> int:
	return _pending.size()

static func finish(path: String) -> Variant:
	# A pending load that is needed right now: wait for it.
	if _pending.has(path):
		_pending.erase(path)
		return ResourceLoader.load_threaded_get(path)
	return null
