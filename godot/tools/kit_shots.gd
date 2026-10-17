extends SceneTree
# 0.31.167: review shots of the 5v5 kits -- the HUD's Q W E R and each cast's effect, from the match's own camera.
#   Xvfb :98 & DISPLAY=:98 godot --rendering-method mobile --resolution 900x1600 --path godot -s res://tools/kit_shots.gd
# HERO (default knight), CASTS (comma list of w / e / q / r, a shot after each), OUT (prefix, default /tmp/kit_).
# You stand on open ground in the middle lane at level 6, an enemy hero 4 m ahead and a hurt ally beside you.
const Mode = preload("res://scripts/siege/siege_mode.gd")
var mode
var frames := 0
var casts: Array = ["w", "e"]
var ci := -2
var shot_at := -1
var next_at := 60
var prefix := "/tmp/kit_"
var hero := "knight"

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")
	if OS.has_environment("HERO"):
		hero = OS.get_environment("HERO")
	if OS.has_environment("CASTS"):
		casts = Array(OS.get_environment("CASTS").split(","))
	if OS.has_environment("OUT"):
		prefix = OS.get_environment("OUT")
	mode = Mode.new()
	mode.moba_hero = hero
	mode.match_seed = 4402
	root.add_child(mode)
	RenderingServer.frame_post_draw.connect(func():
		if frames == shot_at:
			var nm := "hud" if ci < 0 else "%d_%s" % [ci, str(casts[ci])]
			root.get_texture().get_image().save_png("%s%s.png" % [prefix, nm])
			var f: Dictionary = mode.sim.by_id["r1"]
			var a: Dictionary = mode.view.actors.get("r1", {})
			print("SHOT ", nm, " foe ", f.pos, " ", f.state, " hp ", int(f.hp), " seen ", mode.sim.moba.can_see(0, f),
				" drawn ", (not a.is_empty() and (a.root as Node3D).visible)))

func _process(_delta: float) -> bool:
	frames += 1
	if mode.sim == null or not mode._build_queue.is_empty() or frames < 40:
		return false
	var s = mode.sim
	if frames == 40:
		s.moba.wave_at = INF
		for c in s.moba.camps:
			c.next = INF
		var me: Dictionary = s.by_id["you"]
		while int(me.level) < 6:
			s.moba.add_xp(me, s.moba.need(int(me.level)))
		me.picks = []
		me.pos = Vector2(0.0, 44.0)
		me.face = s.angle_of(Vector2(0, -1))
		var foe: Dictionary = s.by_id["r1"]
		foe.bot = false
		foe.pos = Vector2(0.0, 40.0)
		foe.max_hp = 50000.0
		foe.hp = 50000.0
		var mate: Dictionary = s.by_id["b1"]
		mate.bot = false
		mate.pos = Vector2(1.6, 44.5)
		mate.hp = float(mate.max_hp) * 0.4
		for u in s.units:
			if u != me and u != foe and u != mate and bool(u.get("hero", false)):
				u.bot = false
				u.pos = s.spawn(int(u.team))
			if bool(u.get("hero", false)):
				u.move = Vector2.ZERO                  # (0.31.168: a bot's last step kept them walking)
				u.task = {}
		if OS.get_environment("CLOSE") == "1":
			# 0.31.168: a close camera on the two of them (CLOSE=1)
			mode.view.cam_override = [Vector3(5.0, 10.0, 52.0), Vector3(0.0, 0.8, 41.5)]
		frames = 41
	if frames >= next_at:
		ci += 1
		if ci >= casts.size():
			quit(0)
			return false
		if ci >= 0:
			var c := str(casts[ci])
			var me2: Dictionary = s.by_id["you"]
			me2.face = s.angle_of(Vector2(0, -1))
			var foe2: Dictionary = s.by_id["r1"]              # (0.31.168: each cast at him where he stood)
			if s.alive(foe2):
				foe2.pos = Vector2(0.0, 40.0)
				foe2.move = Vector2.ZERO
				foe2.stun = 0.0
			match c:
				"q": s.act("you", "ability")
				"r": s.act("you", "ult")
				_: s.act("you", "spell", c)
		shot_at = frames + 9
		next_at = frames + 40
	return false
