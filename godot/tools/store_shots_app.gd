extends SceneTree
# Play Store screenshots: the app's Home and Shop, and the tutorial's Herald (1080x1920).
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
var app
var mode
var frames := 0
var shots := {}
func _init() -> void:
	if OS.get_environment("PART") == "tutorial":
		mode = Mode.new()
		mode.tutorial = true
		root.add_child(mode)
	else:
		app = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
		root.add_child(app)
	RenderingServer.frame_post_draw.connect(func():
		if shots.has(frames):
			root.get_texture().get_image().save_png("/tmp/store_%s.png" % shots[frames])
			print("SHOT ", shots[frames]))
func _process(d: float) -> bool:
	frames += 1
	if mode != null:
		if frames == 3:
			mode.hud.diag = null
		mode._guard_clock = -1.0e9                # no heat-guard toast / resolution drop in renders
		var tut = mode.tut
		if tut == null:
			return false
		var me: Dictionary = mode.sim.by_id[mode.hud.player_id]
		if frames == 10:
			var guard := 0
			while not (tut.phase == "task" and str(tut.STEPS[tut.step].id) == "workshop") and guard < 300:
				guard += 1
				if tut.phase != "task":
					tut.next(); tut.next(); continue
				match str(tut.STEPS[tut.step].id):
					"move": me.pos += Vector2(0, -7)
					"hat":
						var st: Dictionary = tut._stand(me.team, "knight")
						me.pos = st.p + (Sim.spawn(me.team) - (st.p as Vector2)).normalized() * 0.9
						mode.sim.step(Sim.TICK)
					"attack":
						var foe: Dictionary = mode.sim.by_id[tut._dummy_id]
						me.pos = (foe.pos as Vector2) + Vector2(1.2, 0); me.face = Sim.angle_of(foe.pos - me.pos)
						mode.sim.act(mode.hud.player_id, "attack"); for k in 20: mode.sim.step(Sim.TICK)
					"dodge": mode.sim.act(mode.hud.player_id, "dodge")
					"block": mode.sim.act(mode.hud.player_id, "ability"); tut._block_t = 2.0
				tut._process(0.016)
			# Walk back a little so the workshop, the route and the marker are all in view.
			me.pos = Sim.workshop(me.team) + Vector2(-9.0, -3.0)
			mode.view.snap_camera()
			shots[frames + 30] = "tutorial"
		if frames > 45:
			quit(0)
		return false
	if frames == 40:
		shots[frames + 1] = "home"
	if frames == 44:
		app.show_tab("shop")
		shots[frames + 12] = "shop"
	if frames > 60:
		quit(0)
	return false
