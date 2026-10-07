extends SceneTree
# Writes assets/terrain/preload.json: every model a match build loads through the asset cache, plus the animation
# libraries and the start-up cache, so the app can load them in the background while the menus are up.
#   godot --headless --path godot -s res://tools/preload_list.gd
const Mode = preload("res://scripts/siege/siege_mode.gd")
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
	var paths: Array = Cache._scene_cache.keys()
	paths.append("res://assets/terrain/cache.res")
	for extra in ["res://assets/kaykit/heroes/Necromancer.glb", "res://assets/kaykit/heroes/Knight.glb", "res://assets/kaykit/heroes/Barbarian.glb",
			"res://assets/kaykit/heroes/Rogue.glb", "res://assets/kaykit/heroes/Rogue_Hooded.glb", "res://assets/kaykit/heroes/Ranger.glb", "res://assets/kaykit/heroes/Mage.glb",
			"res://assets/meshy/worker/rigged.glb"]:          # (0.31.76: the Worker's farmer body -- bots take tools early on)
		if not paths.has(extra):
			paths.append(extra)
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
	print("PRELOAD_LIST %d paths" % paths.size())
	quit()
	return true
