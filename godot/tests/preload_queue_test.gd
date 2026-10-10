extends SceneTree
# 0.31.91: the background preload keeps ONE load on a pool thread at a time (scripts/siege/asset_cache.gd: with many in
# flight and an empty shader cache, Godot 4.7.2 deadlocks -- every pool thread ends up waiting on the shader mutex).
# Checks the queue: one in flight, a queued path asked for now is loaded directly and leaves the queue, a path loading
# now is waited for, and the queue drains to the cache.
#   godot --headless --path godot -s res://tests/preload_queue_test.gd
const Assets = preload("res://scripts/siege/asset_cache.gd")
var fails := []
var frames := 0
var most_in_flight := 0
var start_pending := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)
	print(("ok   " if ok else "FAIL ") + what)

func _init() -> void:
	Assets.preload_async()
	start_pending = Assets.pending()
	check(start_pending > 20, "the list is queued (%d paths)" % start_pending)
	check(Assets._loading != "" and not Assets._queue.has(Assets._loading), "one path requested right away: %s" % Assets._loading)
	# A queued path needed now: loaded directly, gone from the queue, never requested later.
	var queued: String = Assets._queue[Assets._queue.size() - 1]
	var got := Assets.res(queued)
	check(got != null and Assets.has(queued) and not Assets._queue.has(queued), "a queued path asked for now loads directly")
	# The path loading on the pool thread: waited for.
	var current := Assets._loading
	var got2 := Assets.res(current)
	check(got2 != null and Assets._loading == "" and Assets.has(current), "the path loading now is waited for")
	Assets.preload_async()
	check(Assets.pending() == start_pending - 2, "preload_async again doesn't queue anything twice")
	Assets.poll()
	check(Assets._loading != "", "the next poll starts the next load")

func _process(_d: float) -> bool:
	frames += 1
	Assets.poll()
	most_in_flight = maxi(most_in_flight, 1 if Assets._loading != "" else 0)
	if Assets.pending() == 0:
		check(most_in_flight == 1, "never more than one load in flight")
		var missing := 0
		for line in JSON.parse_string(FileAccess.get_file_as_string(Assets.PRELOAD_LIST)):
			if ResourceLoader.exists(str(line)) and not Assets.has(str(line)):
				missing += 1
		check(missing == 0, "every listed path is in the cache (%d missing) after %d frames" % [missing, frames])
		print("PRELOAD_QUEUE_PASS" if fails.is_empty() else "PRELOAD_QUEUE_FAIL %s" % [fails])
		quit(0 if fails.is_empty() else 1)
	elif frames > 20000:
		print("PRELOAD_QUEUE_FAIL timeout, %d pending" % Assets.pending())
		quit(1)
	return false
