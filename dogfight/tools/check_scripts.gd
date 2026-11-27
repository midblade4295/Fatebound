extends Node
## Loads every script in the project so that parse errors show up in one run
## (with the autoloads present, unlike --check-only). Run:
##   godot --headless --path . res://tools/CheckScripts.tscn


func _ready() -> void:
	var failed: int = 0
	for path: String in _scripts_in("res://scripts") + _scripts_in("res://tests") + _scripts_in("res://tools"):
		if path.ends_with("check_scripts.gd"):
			continue
		var script: Resource = load(path)
		if script == null or not (script is GDScript) or not (script as GDScript).can_instantiate():
			print("BROKEN: ", path)
			failed += 1
	print("check_scripts: %d broken" % failed)
	get_tree().quit(1 if failed > 0 else 0)


func _scripts_in(folder: String) -> Array[String]:
	var found: Array[String] = []
	var directory: DirAccess = DirAccess.open(folder)
	if directory == null:
		return found
	for file: String in directory.get_files():
		if file.ends_with(".gd"):
			found.append(folder.path_join(file))
	for sub: String in directory.get_directories():
		found.append_array(_scripts_in(folder.path_join(sub)))
	return found
