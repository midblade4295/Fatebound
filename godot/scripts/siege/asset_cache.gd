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
#
# 0.31.91: ONE load at a time, no sub-threads. Kevin's S21 froze on the Godot splash on the first start of a fresh
# install (Vulkan; the testers' "frozen splash" phones were fresh installs too). Reproduced on desktop Vulkan with an
# empty shader cache: the start hangs forever, every thread asleep. Godot 4.7.2, scene_shader_forward_mobile.cpp
# ShaderData::is_valid() holds SceneShaderForwardMobile::singleton_mutex while ShaderRD::version_is_valid() waits for
# the shader's compile tasks (a WorkerThreadPool group, shader_rd.cpp _compile_version_end). Those tasks need a free
# pool thread, but the ~200 parallel loads (each waiting load lets another start) filled every pool thread with loads
# blocked on that same mutex. With a warm shader cache nothing compiles, so it only hit first starts (and would hit
# after a shader change). With one load in flight the pool always has a free thread for the compile.
const PRELOAD_LIST := "res://content/preload.json"   # (.txt files are not exported; JSON is. 0.31.95: in the base build, not a pack)
static var _queue: Array = []            # paths not requested yet, in list order
static var _loading := ""                # the one path loading on a pool thread, or ""

static func preload_async() -> void:
	if not _queue.is_empty() or _loading != "" or not FileAccess.file_exists(PRELOAD_LIST):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PRELOAD_LIST))
	if not parsed is Array:
		return
	for line in parsed:
		var path := str(line).strip_edges()
		if path == "" or _cache.has(path) or _queue.has(path) or not ResourceLoader.exists(path):
			continue
		_queue.append(path)
	_next()

static func _next() -> void:
	# Request the next queued path (one in flight at a time).
	while _loading == "" and not _queue.is_empty():
		var path: String = _queue.pop_front()
		if _cache.has(path):
			continue
		if ResourceLoader.load_threaded_request(path, "", false) == OK:
			_loading = path

static func poll() -> void:
	# Move a finished load into the cache and start the next (call every frame while in the menus).
	if _loading != "":
		var st := ResourceLoader.load_threaded_get_status(_loading)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			_cache[_loading] = ResourceLoader.load_threaded_get(_loading)
			_loading = ""
		elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_loading = ""
	_next()

static func pending() -> int:
	return _queue.size() + (1 if _loading != "" else 0)

static func finish(path: String) -> Variant:
	# Needed right now: wait for it if it is the one loading; if it is only queued, the caller loads it directly.
	if path == _loading:
		_loading = ""
		return ResourceLoader.load_threaded_get(path)
	_queue.erase(path)
	return null
