extends SceneTree
# Play Store screenshots, in-match scenes (real game, real HUD, the dev fps line blanked).
#   Xvfb ... godot --rendering-method mobile --resolution 1080x1920 -s res://tools/store_shots_match.gd
# Writes /tmp/store_<name>.png. SCENES env (comma list) picks a subset.
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
var mode
var frames := 0
var scenes := ["battle", "rescue", "hats", "abilities", "feed"]
var si := -1
var shot_at := -1

func _init() -> void:
	if OS.has_environment("SCENES"):
		scenes = Array(OS.get_environment("SCENES").split(","))
	mode = Mode.new()
	root.add_child(mode)
	RenderingServer.frame_post_draw.connect(func():
		if frames == shot_at and si >= 0 and si < scenes.size():
			root.get_texture().get_image().save_png("/tmp/store_%s.png" % scenes[si])
			print("SHOT ", scenes[si]))

func _me() -> Dictionary:
	return mode.sim.by_id[mode.hud.player_id]

func _revive(u: Dictionary) -> void:
	u.state = "idle"
	u.max_hp = float(mode.sim.stat(u, "hp"))
	u.hp = u.max_hp
	u.respawn_at = 0.0
	u.stun = 0.0

func _stage(name: String) -> void:
	var s = mode.sim
	var me := _me()
	for u in s.units:
		_revive(u)
		u.carrying = false
		u.lifting = -1
		u.offering = false
	# Both Oracles back in their cells (the rescue scene lifts ours again itself).
	for t in 2:
		s.oracles[t] = s._new_oracle(t)
	match name:
		"battle":
			# A blue assault at the enemy gate: every bot fighting, our knight in the middle of it.
			var eg: Dictionary = s.gates.filter(func(g): return g.team != me.team)[0]
			var front: Vector2 = Sim.gate_front(eg)
			var out: Vector2 = (front - (eg.c as Vector2)).normalized()
			var side := Vector2(out.y, -out.x)
			s._set_class(me, "knight", true)
			me.bot = true
			me.pos = front + out * 4.0
			var b := 0
			var r := 0
			var mix := ["knight", "barbarian", "ranger", "mage", "priest", "rogue"]
			for u in s.units:
				if u.id == me.id:
					continue
				u.bot = true
				if u.team == me.team and b < 11:
					s._set_class(u, mix[b % mix.size()], b % 3 == 0)
					u.pos = front + out * (3.0 + (b % 3) * 2.2) + side * ((b / 3) * 2.4 - 3.6)
					b += 1
				elif u.team != me.team and r < 10:
					s._set_class(u, mix[(r + 2) % mix.size()], r % 4 == 0)
					u.pos = front + out * (0.6 + (r % 2) * 1.2) + side * ((r / 2) * 2.0 - 4.0)
					r += 1
				_revive(u)
		"feature":
			# The feature graphic: the same gate assault, wide, no HUD, a pulled-back camera.
			_stage("battle")
			mode.hud.visible = false
			var eg2: Dictionary = s.gates.filter(func(g): return g.team != me.team)[0]
			var c2: Vector2 = Sim.gate_front(eg2)
			var out2: Vector2 = (c2 - (eg2.c as Vector2)).normalized()
			var eye := c2 + out2 * 17.0 + Vector2(out2.y, -out2.x) * 6.0
			mode.view.cam_override = [Vector3(eye.x, 14.0, eye.y), Vector3(c2.x - out2.x * 3.0, 1.2, c2.y - out2.y * 3.0)]
			return
		"rescue":
			# Carrying our Oracle home across the field, allies around, the enemy in pursuit.
			me.bot = false
			s._set_class(me, "knight", true)
			var o: Dictionary = s.oracles[me.team]
			me.pos = o.pos + Vector2(0.5, 0)
			s.act(mode.hud.player_id, "interact")
			var home: Vector2 = Sim.gate_front(s.gates.filter(func(g): return g.team == me.team)[0])
			var spot := home + Vector2(4.0, -10.0)
			me.pos = spot
			o.pos = spot
			me.move = (home - spot).normalized()
			var k := 0
			for u in s.units:
				if u.id == me.id or not s.alive(u):
					continue
				u.bot = true
				if u.team == me.team and k < 5:
					u.pos = spot + Vector2(-2.5 + k * 1.3, -1.5 + (k % 2) * 2.8)
					k += 1
				elif u.team != me.team and k < 12:
					u.pos = spot + Vector2(-5.0 + (k - 5) * 1.6, -7.5 - (k % 2) * 1.5)
					k += 1
		"hats":
			# The courtyard: hat shops with their titles, recruits picking hats.
			me.bot = false
			s._set_class(me, "villager", false)
			me.pos = Sim._c(me.team, Vector2(-9.0, 8.4))
			me.move = Vector2.ZERO
			var picks := ["knight", "rogue", "barbarian"]
			var j := 0
			for u in s.units:
				if u.team == me.team and u.id != me.id and s.alive(u) and j < 3:
					u.bot = false
					u.move = Vector2.ZERO
					var st: Dictionary = s.stands.filter(func(x): return x.team == me.team and x.cls == picks[j])[0]
					u.pos = (st.p as Vector2) + (Sim.spawn(me.team) - (st.p as Vector2)).normalized() * 1.0
					j += 1
				elif u.team != me.team:
					u.pos = Sim.spawn(u.team)
		"abilities":
			# A berserker's whirlwind in the thick of it, a knight holding the shield wall beside it.
			var field := Vector2(-6.0, 16.0) if me.team == 0 else Vector2(6.0, -16.0)
			s._set_class(me, "barbarian", true)
			me.bot = false
			me.pos = field
			me.cd_ability = 0.0
			var kn: Dictionary = {}
			var foes := 0
			for u in s.units:
				if u.id == me.id or not s.alive(u):
					continue
				if u.team == me.team and kn.is_empty():
					kn = u
					s._set_class(kn, "knight", false)
					kn.bot = false
					kn.pos = field + Vector2(-3.4, 2.4)
					kn.face = Sim.angle_of(field - (kn.pos as Vector2))
				elif u.team != me.team and foes < 6:
					# Sturdy and standing still, so they're still around the whirlwind for the shot.
					u.bot = false
					u.move = Vector2.ZERO
					s._set_class(u, ["knight", "rogue", "barbarian", "ranger", "mage", "rogue"][foes], false)
					u.pos = field + Vector2(cos(foes * 1.05 + 0.3) * 2.0, sin(foes * 1.05 + 0.3) * 2.0)
					u.max_hp = 5000.0
					u.hp = 5000.0
					foes += 1
			set_meta("knight", kn.id if not kn.is_empty() else "")
			s.act(mode.hud.player_id, "ability")
		"feed":
			# Cake for their Oracle, held in our dungeon.
			s._set_class(me, "rogue", false)
			me.bot = false
			var cap: Dictionary = s.oracles[1 - int(me.team)]
			me.pos = (cap.pos as Vector2) + Vector2(0.0, -1.6 if me.team == 0 else 1.6)
			me.offering = true
			me.move = Vector2.ZERO
	mode.view.snap_camera()
	# Let the fight get going before the shot (swings, arrows, spells in the air).
	for i in (45 if name == "battle" else (2 if name == "abilities" else 6)):
		s.step(Sim.TICK)
		s.drain_events()

func _process(delta: float) -> bool:
	frames += 1
	if frames == 3:
		mode.hud.diag = null                      # no dev perf line in store shots
	# The heat guard reads llvmpipe's slow frames as a hot phone (30 fps toast, 75 % 3D resolution):
	# keep it from ever running during store renders.
	mode._guard_clock = -1.0e9
	if frames == 4:
		mode.set_fps_cap(0)
	# One scene every 30 frames: stage at +0, keep abilities alive, shoot at +24.
	var k := frames - 10
	if k >= 0 and k % 30 == 0:
		si += 1
		if si >= scenes.size():
			quit(0)
			return false
		_stage(str(scenes[si]))
		shot_at = frames + 24
	if si >= 0 and si < scenes.size() and str(scenes[si]) == "abilities":
		var kid := str(get_meta("knight", ""))
		if kid != "":
			mode.sim.act(kid, "ability")          # hold the shield up
	return false
