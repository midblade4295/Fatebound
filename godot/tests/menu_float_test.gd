extends SceneTree
# 0.31.116 (Kevin: "The icons in the menus that float up and down are not smooth"):
#  - controls aren't rounded to whole canvas pixels any more (gui/common/snap_controls_to_pixels off): on a phone a canvas
#    pixel is 3-4 screen pixels, so a 3-5 px float moved in visible steps;
#  - a floating icon in a container (UI2.bob) floats inside a holder the container lays out: while the container lays
#    itself out again every frame (a timer's text changing next to it) the icon moves a little at a time and floats the
#    whole way, and when the line above it grows it floats lower with it (before, it stayed pinned where it started);
#  - one outside a container floats as before.
#   godot --headless --path godot -s res://tests/menu_float_test.gd
const UI2 = preload("res://scripts/app/ui2.gd")

var fails: Array = []
var t := 0.0
var box: VBoxContainer
var label: Label
var icon: TextureRect
var free_icon: TextureRect
var ys: Array = []
var free_ys: Array = []
var before: Array = []
var after: Array = []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	check(ProjectSettings.get_setting("gui/common/snap_controls_to_pixels", true) == false, "controls aren't snapped to whole canvas pixels")
	var host := Control.new()
	host.size = Vector2(400, 400)
	root.add_child(host)
	box = VBoxContainer.new()
	box.position = Vector2(20, 20)
	box.size = Vector2(200, 200)
	host.add_child(box)
	label = Label.new()
	box.add_child(label)
	icon = UI2.img(box, "", 48.0)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UI2.bob(icon, 6.0, 0.5)
	var plain := Control.new()
	plain.position = Vector2(250, 20)
	host.add_child(plain)
	free_icon = UI2.img(plain, "", 48.0)
	free_icon.position = Vector2(0, 10)
	UI2.bob(free_icon, 6.0, 0.5)

var done := false

func _process(d: float) -> bool:
	if done:
		return true
	# where things are now is where the last frame drew them (its tweens ran and its containers laid out)
	if t > 0.3 and t < 1.5:
		ys.append(icon.global_position.y)
		free_ys.append(free_icon.global_position.y)
		before.append(icon.global_position.y)
	if t > 1.8:
		after.append(icon.global_position.y)
	t += d
	label.text = "%.3f" % t                       # the box lays itself out again every frame
	label.custom_minimum_size.y = (20.0 if t < 1.5 else 50.0) + float(Engine.get_process_frames() % 3) * 0.5
	if t < 2.8:
		return false
	check(root.get_viewport().gui_snap_controls_to_pixels == false, "the window's viewport doesn't snap controls either")
	check(icon.get_parent() != box and icon.get_parent().get_parent() == box, "the icon in the box floats inside a holder the box lays out")
	var big := 0.0
	for i in range(1, ys.size()):
		big = maxf(big, absf(float(ys[i]) - float(ys[i - 1])))
	var lo: float = ys.min()
	var hi: float = ys.max()
	# 6 px each way in 0.5 s on a sine: at most ~19 px/s, so well under 2 px between frames even at 15 fps
	check(ys.size() > 20 and big < 2.0, "it moves a little at a time (largest step %.2f px over %d frames)" % [big, ys.size()])
	check(hi - lo > 5.0 and hi - lo < 6.5, "it floats the whole way (%.2f px)" % (hi - lo))
	var fbig := 0.0
	for i in range(1, free_ys.size()):
		fbig = maxf(fbig, absf(float(free_ys[i]) - float(free_ys[i - 1])))
	var flo: float = free_ys.min()
	var fhi: float = free_ys.max()
	check(fbig < 2.0 and fhi - flo > 5.0, "one outside a container floats as before (%.2f px, largest step %.2f)" % [fhi - flo, fbig])
	var mb := 0.0
	for v in before:
		mb += float(v) / before.size()
	var ma := 0.0
	for v in after:
		ma += float(v) / after.size()
	check(absf(ma - mb - 30.0) < 2.5, "the line above it grows 30 px and it floats 30 px lower (%.1f)" % (ma - mb))
	done = true
	print("MENU_FLOAT_PASS" if fails.is_empty() else "MENU_FLOAT_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
	return true
