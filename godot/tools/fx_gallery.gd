extends SceneTree
# 0.31.201: review shots of the abilities' effects (spell_fx.gd) -- a hero's Q, W, E and R, each caught a few times
# after the cast, from a close camera.
#   Xvfb :97 & DISPLAY=:97 FB_FORCE_HQ=1 godot --rendering-method mobile --fixed-fps 30 --resolution 900x1600 --path godot -s res://tools/fx_gallery.gd
# HERO (default knight), CASTS (comma list; default q,w,e,r), OUT (prefix, default /tmp/fx_), AT (comma list of frames
# after the cast to shoot; default 3,9,18,32), LEVEL (default 6), CAM (close | far; default close).
# You stand on open ground in the middle lane at level 6, an enemy hero 4 m ahead and a hurt ally beside you.
const Mode = preload("res://scripts/siege/siege_mode.gd")
var mode
var frames := 0
var casts: Array = ["q", "w", "e", "r"]
var ats: Array = [3, 9, 18, 32]
var ci := -1
var cast_at := -1
var next_at := 60
var shots := {}                                  # frame -> file
var prefix := "/tmp/fx_"
var hero := "knight"

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")
	if OS.has_environment("HERO"):
		hero = OS.get_environment("HERO")
	if OS.has_environment("CASTS"):
		casts = Array(OS.get_environment("CASTS").split(","))
	if OS.has_environment("AT"):
		ats = []
		for a in OS.get_environment("AT").split(","):
			ats.append(int(a))
	if OS.has_environment("OUT"):
		prefix = OS.get_environment("OUT")
	mode = Mode.new()
	mode.moba_hero = hero
	mode.match_seed = 4402
	root.add_child(mode)
	RenderingServer.frame_post_draw.connect(func():
		if shots.has(frames):
			root.get_texture().get_image().save_png(str(shots[frames]))
			print("SHOT ", shots[frames])
			shots.erase(frames))

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
		var lv := int(OS.get_environment("LEVEL")) if OS.has_environment("LEVEL") else 6
		while int(me.level) < lv:
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
				u.move = Vector2.ZERO
				u.task = {}
		if OS.get_environment("CAM") != "far":
			mode.view.cam_override = [Vector3(6.0, 11.0, 52.5), Vector3(0.0, 0.8, 41.5)]
		frames = 41
	if frames >= next_at:
		ci += 1
		if ci >= casts.size():
			if shots.is_empty():
				quit(0)
			return false
		var c := str(casts[ci])
		var me2: Dictionary = s.by_id["you"]
		me2.face = s.angle_of(Vector2(0, -1))
		me2.pos = Vector2(0.0, 44.0)
		me2.stun = 0.0
		var foe2: Dictionary = s.by_id["r1"]
		if s.alive(foe2):
			foe2.pos = Vector2(0.0, 40.0)
			foe2.move = Vector2.ZERO
			foe2.stun = 0.0
			foe2.hp = 50000.0
		var ok := false
		match c:
			"q": ok = s.act("you", "ability")
			"r": ok = s.act("you", "ult")
			"a": ok = s.act("you", "attack")
			_: ok = s.act("you", "spell", c)
		print("CAST ", c, " ", ok)
		for k in ats.size():
			shots[frames + int(ats[k])] = "%s%s_%s_%d.png" % [prefix, hero, c, k]
		next_at = frames + int(ats[ats.size() - 1]) + 50
	return false
