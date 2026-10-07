extends SceneTree
# The castles in a real match view (no HUD): blue's from the field (how the enemy sees it), from above and behind
# (how its own team sees it), a gate close-up, and red's from the field.
#   Xvfb :98 & DISPLAY=:98 godot --path godot --rendering-method mobile --resolution 1280x960 -s res://tools/castle_shot.gd
# OUT env: file prefix (default /tmp/castle_); ONLY env: shot names to take. Writes <prefix><shot>.png.
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
var mode
var frames := 0
var shots := []
var si := -1
var shot_at := -1
var prefix := "/tmp/castle_"

func _init() -> void:
	if OS.has_environment("OUT"):
		prefix = OS.get_environment("OUT")
	for t in 2:
		var c2: Vector2 = Sim._c(t, Vector2(0.0, 16.0))          # the castle's middle
		var f2: Vector2 = Sim._c(t, Vector2(0.0, -26.0))         # out on the field in front of it
		var b2: Vector2 = Sim._c(t, Vector2(0.0, 52.0))          # behind it
		var g2: Vector2 = Sim._c(t, Vector2(7.0, 3.0))           # a gate
		var gf: Vector2 = Sim._c(t, Vector2(10.0, -7.0))
		var c := Vector3(c2.x, 2.0, c2.y)
		var n := "blue" if t == 0 else "red"
		shots.append(["%s_field" % n, [Vector3(f2.x, 26.0, f2.y), c]])
		shots.append(["%s_low" % n, [Vector3(f2.x * 0.6 + c2.x * 0.4, 9.0, f2.y * 0.6 + c2.y * 0.4), c + Vector3(0, 3, 0)]])
		var th: Vector2 = Sim._c(t, Vector2(0.0, 28.0))
		var the: Vector2 = Sim._c(t, Vector2(0.0, 19.0))
		var cc: Vector2 = Sim._c(t, Vector2(0.0, 9.0))
		var ce: Vector2 = Sim._c(t, Vector2(0.0, 22.0))
		shots.append(["%s_throne" % n, [Vector3(the.x, 9.0, the.y), Vector3(th.x, 4.6, th.y)]])
		shots.append(["%s_court" % n, [Vector3(ce.x, 12.0, ce.y), Vector3(cc.x, 0.5, cc.y)]])
		if t == 1:
			shots.append(["red_own", [Vector3(b2.x, 34.0, b2.y), c - Vector3(0, 0, -4)]])
		if t == 0:
			# The dungeon wing: from the first terrace looking west through the doorway, and from above.
			var dd: Vector2 = Sim._c(t, Vector2(-21.0, 18.5))
			var de: Vector2 = Sim._c(t, Vector2(-11.0, 15.0))
			var dt: Vector2 = Sim._c(t, Vector2(-25.0, 16.0))
			var da: Vector2 = Sim._c(t, Vector2(-16.0, 2.0))
			shots.append(["blue_dungeon_in", [Vector3(de.x, 8.0, de.y), Vector3(dd.x, 0.5, dd.y)]])
			shots.append(["blue_dungeon_top", [Vector3(da.x, 24.0, da.y), Vector3(dt.x, -1.0, dt.y)]])
			shots.append(["blue_own", [Vector3(b2.x, 34.0, b2.y), c - Vector3(0, 0, 4)]])
			shots.append(["blue_gate", [Vector3(gf.x, 6.0, gf.y), Vector3(g2.x, 2.5, g2.y)]])
	if OS.has_environment("ONLY"):
		var only := Array(OS.get_environment("ONLY").split(","))
		shots = shots.filter(func(sh): return only.has(sh[0]))
	mode = Mode.new()
	root.add_child(mode)
	RenderingServer.frame_post_draw.connect(func():
		if frames == shot_at and si >= 0 and si < shots.size():
			root.get_texture().get_image().save_png("%s%s.png" % [prefix, shots[si][0]])
			print("SHOT ", shots[si][0]))

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 3:
		mode.hud.diag = null
		mode.hud.visible = false
	mode._guard_clock = -1.0e9
	if frames == 4:
		mode.set_fps_cap(0)
	var k := frames - 30
	if k >= 0 and k % 10 == 0:
		si += 1
		if si >= shots.size():
			quit(0)
			return false
		mode.view.cam_override = shots[si][1]
		shot_at = frames + 7
	return false
