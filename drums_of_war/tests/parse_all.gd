extends SceneTree
## Loads every script and scene in the project so a syntax error anywhere fails loudly.
## Prints DRUMS_PARSE_PASS.


func _init() -> void:
	var bad := 0
	var count := 0
	for dir_path: String in ["res://scripts", "res://scenes", "res://tests", "res://tools"]:
		for path: String in _walk(dir_path):
			if not (path.ends_with(".gd") or path.ends_with(".tscn")):
				continue
			count += 1
			if load(path) == null:
				print("  cannot load ", path)
				bad += 1
	print("%d files loaded, %d failed" % [count, bad])
	if bad == 0:
		print("DRUMS_PARSE_PASS")
	quit(0 if bad == 0 else 1)


func _walk(path: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(path)
	if d == null:
		return out
	for f: String in d.get_files():
		out.append(path + "/" + f)
	for sub: String in d.get_directories():
		out.append_array(_walk(path + "/" + sub))
	return out
