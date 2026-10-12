extends SceneTree
# 0.31.114 (Kevin: "The characters on main screen are too hudled together and clipping into each other. Is there a way
# you can redesign the home screen so it's cleaner"):
#  - no hero on Home's dais reaches into another (each one's box, weapons included, clear of every other's);
#  - at phone size (420 x 933) the heroes stand clear of the side medallions and above PLAY, and the front row's three
#    don't cover each other;
#  - the "16 v 16 SIEGE" ribbon is gone (it sat on their feet) and the line under PLAY still says 16 vs 16.
#   godot --headless --path godot -s res://tests/home_heroes_test.gd
const App = preload("res://scripts/app/siege_app.gd")
const Roster = preload("res://scripts/app/roster.gd")
const Screens = preload("res://scripts/app/screens.gd")

var app
var phone
var fails: Array = []
var t := 0.0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func has_text(node: Node, s: String) -> bool:
	if node is Label and (node as Label).text.contains(s) and (node as Label).is_visible_in_tree():
		return true
	for c in node.get_children():
		if has_text(c, s):
			return true
	return false

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")      # nothing listens there
	var base := "user://homeheroes-%d" % Time.get_ticks_usec()
	app = App.new()
	app.eco_autostart = false
	app.social_autostart = false
	app.version_check = false
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	root.add_child(app)
	phone = Roster.new()                                     # the line-up as a 420-wide phone lays it out
	phone.size = Vector2(420, 340)
	root.add_child(phone)

func _box(slot: Node3D, weapons := true) -> AABB:
	# the hero's box on the stage: his body (its skinned mesh's bounds), and with weapons, the exact extent of the
	# weapons he holds (their vertices where they are now; a rotated mesh's own box would be far too big). Not the
	# shadow under him.
	var box := AABB()
	var first := true
	for v in slot.find_children("*", "MeshInstance3D", true, false):
		var mi := v as MeshInstance3D
		if mi.mesh == null or mi.mesh is QuadMesh or not mi.is_visible_in_tree():
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		if mi.skin == null:
			if not weapons:
				continue
			var vfirst := true
			for si in mi.mesh.get_surface_count():
				for p in (mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
					var q: Vector3 = mi.global_transform * p
					b = AABB(q, Vector3.ZERO) if vfirst else b.expand(q)
					vfirst = false
		box = b if first else box.merge(b)
		first = false
	return box

func _screen(r, box: AABB) -> Rect2:
	# the box's corners on the phone's screen (the layer's control px, then where Home places the layer at 420 wide)
	var w := 420.0
	var h := w * App.BG_ASPECT
	var dais := -0.405 * w + 0.858 * h
	var rect := Rect2()
	for i in 8:
		var p: Vector2 = r.cam.unproject_position(box.get_endpoint(i)) * (r.size.x / float(r.viewport.size.x))
		p += Vector2(0, dais - Roster.FEET_Y)
		rect = Rect2(p, Vector2.ZERO) if i == 0 else rect.expand(p)
	return rect

func _process(d: float) -> bool:
	t += d
	if t < 1.5:
		if not bool(app.profile.d.get("tutorial_done", false)):
			app.profile.d.tutorial_done = true                   # (the players-online line under PLAY, not the tutorial)
			app.rebuild()
		return false
	# ---- no hero reaches into another
	var built: Dictionary = phone._built
	check(built.size() == 7, "all seven classes on the dais (%d)" % built.size())
	var boxes := {}
	var bodies := {}
	for c in built:
		boxes[c] = _box(built[c].node)
		bodies[c] = _box(built[c].node, false)
	var hits := []
	var names: Array = boxes.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			if (boxes[names[i]] as AABB).grow(0.03).intersects(boxes[names[j]]):
				hits.append("%s/%s" % [names[i], names[j]])
	check(hits.is_empty(), "no hero (weapons included) reaches within 6 cm of another %s" % str(hits))
	for hn in hits:
		for c in str(hn).split("/"):
			print("   ", c, " ", boxes[c])
	# ---- at phone size
	var off: float = app.find_children("*", "Button", true, false).filter(func(b): return str(b.get_meta("action_key", "")) == "side_pass")[0].global_position.y - float(Screens.MED_Y[0])
	var med_bottom := off + float(Screens.MED_Y[2]) + 80.0           # QUESTS / FRIENDS and their labels
	var rects := {}
	var feet_r := {}
	for c in boxes:
		rects[c] = _screen(phone, boxes[c])
		feet_r[c] = _screen(phone, bodies[c])
	var clear := true
	var why := ""
	for c in rects:
		var r: Rect2 = rects[c]
		if (r.position.x < 76.0 or r.end.x > 344.0) and r.position.y < med_bottom:
			clear = false
			why += " %s %s" % [c, str(r)]
	check(clear, "every hero clear of the side medallions (they end at y %.0f)%s" % [med_bottom, why])
	var hh := 933.0 - (6.0 + App.TOP_H) - float(App.ChatTicker.H) - App.TAB_H - 30.0
	var play_y := off + float(Screens.home_layout(hh).play)
	var feet := 0.0
	for c in feet_r:
		feet = maxf(feet, (feet_r[c] as Rect2).end.y)
	check(feet < play_y, "the heroes stand above PLAY (feet %.0f, PLAY %.0f)" % [feet, play_y])
	var fr: Array = [feet_r.barbarian, feet_r.knight, feet_r.mage]
	check(fr[0].end.x <= fr[1].position.x + 2.0 and fr[1].end.x <= fr[2].position.x + 2.0,
		"the front row's three stand side by side, not in front of each other: %s" % str(fr))
	# ---- the ribbon
	check(not has_text(app.content, "16 v 16 SIEGE") and has_text(app.content, "16 vs 16"), "no ribbon on Home; the line under PLAY says 16 vs 16")
	print("HOME_HEROES_PASS" if fails.is_empty() else "HOME_HEROES_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
	return true
