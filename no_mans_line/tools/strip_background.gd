extends SceneTree
## Removes a flat background colour from a sprite sheet and saves a PNG with
## real transparency.
##
##   godot --headless --path . -s tools/strip_background.gd -- <in> <out> [options]
##
## Options
##   --key=RRGGBB        background colour. Default: sampled from the bottom-left corner.
##   --keep=x,y,w,h      rectangle to leave fully opaque (repeatable). Use it for
##                       full-bleed art such as a background banner.
##   --erase=x,y,w,h     rectangle to clear completely (repeatable). Use it for a
##                       stray bit of one frame that pokes into its neighbour.
##   --holes             also clear enclosed background pockets (inside barbed
##                       wire coils, between an arm and the body...).
##   --tolerance=N       colour distance (0-441) treated as background. Default 30.
##
## Why not a shader? A colour-distance shader removes EVERY pixel close to the
## key colour, including shading inside the sprites. This tool only removes
## pixels that are connected to the image border (a flood fill), so dark greys
## inside a soldier or a bunker survive.

const SOFT_EDGE := 20.0  # Width of the alpha ramp below --tolerance.
const HOLE_TOLERANCE := 10.0
const HOLE_MIN_AREA := 60


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var paths: Array[String] = []
	var keep: Array[Rect2i] = []
	var erase: Array[Rect2i] = []
	var key_set := false
	var key := Color.BLACK
	var clear_holes := false
	var tolerance := 30.0
	for arg in args:
		if arg.begins_with("--key="):
			key = Color.html(arg.trim_prefix("--key="))
			key_set = true
		elif arg.begins_with("--keep="):
			var p := arg.trim_prefix("--keep=").split(",")
			keep.append(Rect2i(int(p[0]), int(p[1]), int(p[2]), int(p[3])))
		elif arg.begins_with("--erase="):
			var p := arg.trim_prefix("--erase=").split(",")
			erase.append(Rect2i(int(p[0]), int(p[1]), int(p[2]), int(p[3])))
		elif arg.begins_with("--tolerance="):
			tolerance = float(arg.trim_prefix("--tolerance="))
		elif arg == "--holes":
			clear_holes = true
		else:
			paths.append(arg)
	if paths.size() != 2:
		printerr("usage: -s tools/strip_background.gd -- <in> <out> [--key=RRGGBB] [--keep=x,y,w,h] [--erase=x,y,w,h] [--holes]")
		quit(1)
		return

	var image := Image.load_from_file(paths[0])
	if image == null:
		printerr("cannot load ", paths[0])
		quit(1)
		return
	image.convert(Image.FORMAT_RGBA8)
	var width := image.get_width()
	var height := image.get_height()
	var data := image.get_data()

	if not key_set:
		key = _sample_corner(image)
	var key_r := key.r8
	var key_g := key.g8
	var key_b := key.b8

	# Colour distance of every pixel to the key, and the "protected" mask.
	var count := width * height
	var distance := PackedFloat32Array()
	distance.resize(count)
	var locked := PackedByteArray()
	locked.resize(count)
	for i in count:
		var dr := data[i * 4] - key_r
		var dg := data[i * 4 + 1] - key_g
		var db := data[i * 4 + 2] - key_b
		distance[i] = sqrt(float(dr * dr + dg * dg + db * db))
	for rect in keep:
		for y in range(maxi(rect.position.y, 0), mini(rect.end.y, height)):
			for x in range(maxi(rect.position.x, 0), mini(rect.end.x, width)):
				locked[y * width + x] = 1

	# 1. Flood fill inward from the image border.
	var removed := PackedByteArray()
	removed.resize(count)
	var stack := PackedInt32Array()
	for x in width:
		stack.append(x)
		stack.append((height - 1) * width + x)
	for y in height:
		stack.append(y * width)
		stack.append(y * width + width - 1)
	_flood(stack, removed, distance, locked, width, height, tolerance)

	# 2. Optional: enclosed pockets of pure background colour.
	if clear_holes:
		var visited := PackedByteArray()
		visited.resize(count)
		for start in count:
			if removed[start] or visited[start] or locked[start] or distance[start] >= HOLE_TOLERANCE:
				continue
			var region := PackedInt32Array([start])
			visited[start] = 1
			var head := 0
			while head < region.size():
				var i := region[head]
				head += 1
				var x := i % width
				for n in [i - width, i + width, i - 1 if x > 0 else -1, i + 1 if x < width - 1 else -1]:
					if n < 0 or n >= count or visited[n] or removed[n] or locked[n]:
						continue
					if distance[n] < HOLE_TOLERANCE:
						visited[n] = 1
						region.append(n)
			if region.size() >= HOLE_MIN_AREA:
				# Grow the pocket out to its real edge.
				_flood(region, removed, distance, locked, width, height, tolerance)

	# 3. Write alpha: 0 in the flat background, ramping up toward sprite edges.
	var cleared := 0
	for i in count:
		if removed[i]:
			var t := clampf((distance[i] - (tolerance - SOFT_EDGE)) / SOFT_EDGE, 0.0, 1.0)
			data[i * 4 + 3] = int(t * t * (3.0 - 2.0 * t) * 255.0)
			cleared += 1

	for rect in erase:
		for y in range(maxi(rect.position.y, 0), mini(rect.end.y, height)):
			for x in range(maxi(rect.position.x, 0), mini(rect.end.x, width)):
				data[(y * width + x) * 4 + 3] = 0

	var result := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, data)
	var error := result.save_png(paths[1])
	if error != OK:
		printerr("cannot save ", paths[1])
		quit(1)
		return
	print("%s -> %s  key=#%s  %dx%d  cleared %.1f%%" % [
		paths[0], paths[1], key.to_html(false), width, height, 100.0 * cleared / count,
	])
	quit(0)


## Average colour of an 8x8 block in the bottom-left corner.
func _sample_corner(image: Image) -> Color:
	var sum := Vector3.ZERO
	for y in 8:
		for x in 8:
			var c := image.get_pixel(x, image.get_height() - 1 - y)
			sum += Vector3(c.r, c.g, c.b)
	sum /= 64.0
	return Color(sum.x, sum.y, sum.z)


## 4-connected flood fill through pixels closer than `tolerance` to the key.
func _flood(seeds: PackedInt32Array, removed: PackedByteArray, distance: PackedFloat32Array,
		locked: PackedByteArray, width: int, height: int, tolerance: float) -> void:
	var stack := seeds.duplicate()
	var count := width * height
	for i in stack:
		if not locked[i] and distance[i] < tolerance:
			removed[i] = 1
	while not stack.is_empty():
		var i := stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		if not removed[i]:
			continue
		var x := i % width
		for n in [i - width, i + width, i - 1 if x > 0 else -1, i + 1 if x < width - 1 else -1]:
			if n < 0 or n >= count or removed[n] or locked[n]:
				continue
			if distance[n] < tolerance:
				removed[n] = 1
				stack.append(n)
