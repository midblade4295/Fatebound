extends SceneTree
# The outposts' Meshy keeps (0.31.73) in a real match view (no HUD): every outpost held by nobody, then blue, then red,
# with a few of the holder's rangers up on each deck.
#   Xvfb :98 & DISPLAY=:98 godot --path godot --rendering-method mobile --resolution 1280x960 -s res://tools/outpost_shot.gd
# OUT env: file prefix (default /tmp/op_); STATES env: owners to show (default "-1,0,1"); IDS env: outposts (default all);
# GAME env: also a shot from the game camera's height. Writes <prefix><state>_<id>_<view>.png.
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Land = preload("res://scripts/siege/siege_land.gd")
var mode
var frames := 0
var shots := []          # [name, owner, [eye, target]]
var si := -1
var shot_at := -1
var prefix := "/tmp/op_"
var keep := []           # units held on the decks

func _init() -> void:
	if OS.has_environment("OUT"):
		prefix = OS.get_environment("OUT")
	var states := Array(OS.get_environment("STATES").split(",")) if OS.has_environment("STATES") else ["-1", "0", "1"]
	var ids := Array(OS.get_environment("IDS").split(",")) if OS.has_environment("IDS") else ["0", "1", "2", "3", "4"]
	for st in states:
		for i in ids:
			var id := int(i)
			var p: Vector2 = Land.outpost_positions()[id]
			var yaw := float(Land.OUTPOST_LOOKS[id].yaw)
			var door := Vector3(sin(yaw), 0.0, cos(yaw))
			var side := Vector3(door.z, 0.0, -door.x)
			var c := Vector3(p.x, Sim.height_at(p) + 1.6, p.y)
			shots.append(["%s_%d_close" % [st, id], int(st), [c + door * 11.0 + side * 5.0 + Vector3(0, 6.5, 0), c]])
			if OS.has_environment("GAME"):
				var cam_z := 26.0 if p.y >= 0.0 else -26.0
				shots.append(["%s_%d_game" % [st, id], int(st), [c + Vector3(0, 30.0, cam_z * 0.8), c]])
	mode = Mode.new()
	root.add_child(mode)
	RenderingServer.frame_post_draw.connect(func():
		if frames == shot_at and si >= 0 and si < shots.size():
			root.get_texture().get_image().save_png("%s%s.png" % [prefix, shots[si][0]])
			print("SHOT ", shots[si][0]))

func _own(owner: int) -> void:
	var sim = mode.sim
	for u in keep:
		if int(u.get("tower", -1)) >= 0:
			sim._leave_tower(u)
		u.pos = Sim.spawn(u.team)
	keep.clear()
	for op in sim.outposts:
		op.owner = owner
		op.prog = 0.0 if owner < 0 else (1.0 if owner == 0 else -1.0)
		(op.occ as Array).clear()
	if owner < 0:
		return
	var mine: Array = sim.units.filter(func(x): return x.team == owner and sim.alive(x))
	var k := 0
	for op in sim.outposts:
		for j in 3:
			if k >= mine.size():
				return
			var u: Dictionary = mine[k]
			k += 1
			sim._set_class(u, ["ranger", "mage", "ranger"][j], false)
			u.pos = (op.p as Vector2) + Vector2(1.0, 0.0).rotated(TAU * j / 3.0 + 0.4) * 2.5
			sim._enter_tower(u, op)
			u.pos = (op.p as Vector2) + Vector2(1.0, 0.0).rotated(TAU * j / 3.0 + 0.4) * 1.3
			keep.append(u)

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 3:
		mode.hud.diag = null
		mode.hud.visible = false
	mode._guard_clock = -1.0e9
	if frames == 4:
		mode.set_fps_cap(0)
	for u in keep:
		u.bot = false
		u.move = Vector2.ZERO
	var k := frames - 30
	if k >= 0 and k % 12 == 0:
		si += 1
		if si >= shots.size():
			quit(0)
			return false
		if si == 0 or int(shots[si][1]) != int(shots[si - 1][1]):
			_own(int(shots[si][1]))
		mode.view.cam_override = shots[si][2]
		shot_at = frames + 9
	return false
