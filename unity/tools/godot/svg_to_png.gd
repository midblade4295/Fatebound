extends SceneTree
# Rasterises an SVG the way Godot's importer does (svg/scale), for sync_assets.py:
#   godot --headless -s svg_to_png.gd -- <in.svg> <out.png> <scale>
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var img := Image.new()
	var err := img.load_svg_from_string(FileAccess.get_file_as_string(a[0]), float(a[2]))
	if err != OK:
		push_error("svg: %s" % err)
		quit(1)
		return
	img.save_png(a[1])
	quit(0)
