extends SceneTree
# Loads every GDScript in scripts/, server/ and tests/ and fails on any parse/compile error.
var errors := []
var count := 0

func walk(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			var path := dir.path_join(f)
			var s: Script = load(path)
			count += 1
			if s == null or not s.can_instantiate():
				errors.append(path)
	for sub in d.get_directories():
		walk(dir.path_join(sub))

func _init() -> void:
	for root_dir in ["res://scripts", "res://server", "res://tests"]:
		walk(root_dir)
	print("PARSE_ALL_PASS %d scripts" % count if errors.is_empty() else "PARSE_ALL_FAIL %s" % str(errors))
	quit(0 if errors.is_empty() else 1)
