extends SceneTree
# Writes assets/terrain/preload.json: everything a match loads through the asset cache (models, textures, the Meshy
# bodies' baked animations), every class body a match can call for (0.31.78: so the first Crusader, Berserker, Assassin,
# Sniper, Archmage or Necromancer of a match doesn't load its body and 110 animations on the spot), the KayKit animation
# libraries and the start-up cache -- so the app can load it all in the background while the menus are up.
#   godot --headless --path godot -s res://tools/preload_list.gd
const Mode = preload("res://scripts/siege/siege_mode.gd")
const View = preload("res://scripts/siege/siege_view.gd")
const Cache = preload("res://scripts/siege/asset_cache.gd")
var mode
var frames := 0
func _init() -> void:
	mode = Mode.new()
	root.add_child(mode)
func _process(_d: float) -> bool:
	frames += 1
	if frames < 4:
		return false
	# Every class body (with its weapons and animations) through the same cache, so their files are listed too.
	for cls in View.LOOKS:
		if cls.ends_with("_kaykit"):
			continue                                   # tools-only bodies
		var made: Dictionary = View.make_body(cls)
		if not made.is_empty():
			(made.body as Node).free()
	var paths: Array = Cache._cache.keys().filter(func(p): return Cache._cache[p] != null)
	paths.append("res://assets/terrain/cache.res")
	var dir := DirAccess.open("res://assets/kaykit/anim")
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".glb") or f.ends_with(".gltf"):
				paths.append("res://assets/kaykit/anim/" + f)
	paths.sort()
	var uniq := []
	for p in paths:
		if not uniq.has(p):
			uniq.append(p)
	var fa := FileAccess.open("res://assets/terrain/preload.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify(uniq, "\n"))
	fa.close()
	print("PRELOAD_LIST %d paths" % uniq.size())
	quit()
	return true
