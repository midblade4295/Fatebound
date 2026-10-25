extends SceneTree
# The title. 0.31.113 (Kevin: "I like the all tied up one. Can you also make it so the king swings back and forth from the
# rope"): the "All Tied Up" title (scripts/app/title_logo.gd), its two layers matching the art, the King swinging both
# ways about the knot, still with Reduce Motion.
# 0.31.139 (Kevin: "remove the fatebound title and instead put that in a startup screen and any loading screens. Give
# the starting title screen a little jingle tune and have title animate in there like slamming onto the wall"):
#  - the app opens on the title screen (title_screen.gd) over Home, and Home has no title of its own any more;
#  - the castle wall, the jingle playing, the title flying in big and tilted and slamming onto the wall (the thud's
#    sound there, the shake, the dust), then TAP TO START; a tap lifts it off Home;
#  - Reduce Motion: no flight, no shake, the King still;
#  - the loading screens have it: the first-start download screen (the wall and the title from the base build), the
#    match's warm-up cover (the wall and the swinging title), and the boot splash is the wall.
# 0.31.141 (Kevin: "Make the intro splash screen more exciting and also load faster"):
#  - the torches flare alight, the title flies in trailing afterimages, the jingle starts so its first note lands on
#    the hit; the hit: shockwave ring, gold sparks, a punch-in zoom (back to 1), the King knocked into a big swing that
#    dies down to his gentle one; light rays behind the title and a glint sweeping across the letters;
#  - TAP TO START only once the game behind says Home is ready (LOADING... until; a tap meanwhile lifts it the moment
#    it is). (The boot order itself: boot_title_test.)
# 0.31.142 (Kevin: "Getting freezes during it now"): the show waits for the game behind: before it the wall and the
#  torches (the pre-roll); the game goes in behind a still LOADING... (hold_for_game: the embers fade, the torches hold
#  steady, then can_swap); a tap while loading goes straight in once ready, without the show; the game's background
#  loading starts once the show is over.
# 0.31.193 (Kevin: "Let's make a brand new title graphic that fits new game style" -> C4, "make the flags on side blow
#  around and the lighting effect in middle show effects"): the Rift title -- its layers match the art (the word, the two
#  flags, the rift's glow); the flags wave all the time and whip about on the slam, then settle back to a breeze; the
#  rift crackles with lightning (bolts, a flickering glow, sparks) and flares on the slam; Reduce Motion: all still.
#  (Until then the "All Tied Up" title's King swung from his rope.)
#   godot --headless --path godot -s res://tests/title_logo_test.gd
const App = preload("res://scripts/app/siege_app.gd")
const TitleLogo = preload("res://scripts/app/title_logo.gd")
const TitleScreen = preload("res://scripts/app/title_screen.gd")
const UI2 = preload("res://scripts/app/ui2.gd")

var app
var still                                # a title screen with Reduce Motion
var waiting                              # a title screen with no game behind it yet (as the boot screen puts it up)
var waiting_gone := false
var kick := 0.0
var swept := false
var punch_max := 1.0
var fails: Array = []
var t := 0.0
var step := 0
var flare_max := 0.0
var made0 := 0
var glow_lo := 1.0
var glow_hi := 0.0
var flag_t0 := 0.0
var boost_end := 0.0
var seen := {}
var gone := false

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")      # nothing listens there
	OS.set_environment("FB_TITLE", "1")                       # (the title screen, as the real app opens)
	var base := "user://titlelogo-%d" % Time.get_ticks_usec()
	app = App.new()
	app.eco_autostart = false
	app.social_autostart = false
	app.version_check = false
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	root.add_child(app)
	still = TitleScreen.new(null, true)
	still.size = Vector2(933, 420)
	root.add_child(still)
	still.home_ready()                       # (a game behind it, ready: the show plays)
	waiting = TitleScreen.new(null, false)
	waiting.size = Vector2(933, 420)
	waiting.done.connect(func(): waiting_gone = true)
	root.add_child(waiting)

func _process(d: float) -> bool:
	t += d
	match step:
		0:
			if t < 0.05:
				return false
			var ts = app.title_screen
			check(ts != null and ts.is_visible_in_tree() and (ts.get_parent() as CanvasLayer).layer >= 90 and app.tab == "home",
				"the app opens on the title screen, over Home")
			check(app.hero_layer.find_children("*", "", true, false).filter(func(n): return n.get_script() == TitleLogo).is_empty(),
				"Home has no title of its own any more")
			var wall: Texture2D = ts.wall.texture
			check(wall != null and wall.get_size() == Vector2(1152, 2560), "the castle wall (%s)" % (str(wall.get_size()) if wall else "none"))
			check(ts.jingle != null and ts.jingle.stream is AudioStreamOggVorbis and not ts.jingle.playing, "the jingle is ready (it starts on the way to the hit)")
			check(ResourceLoader.exists("res://assets/sounds/titleSlam.wav"), "the slam's sound is there")
			check(not ts.can_swap(), "the game isn't put in behind before the screen has settled for it")
			check(not app._background, "the game's background loading waits for the show")
			var bt: Texture2D = UI2.tex(UI2.V2 + "title_rift_base.webp")
			var lt: Texture2D = UI2.tex(UI2.V2 + "title_flag_l.webp")
			var rt: Texture2D = UI2.tex(UI2.V2 + "title_flag_r.webp")
			var gt: Texture2D = UI2.tex(UI2.V2 + "title_rift_glow.webp")
			check(bt != null and Vector2(bt.get_size()) == TitleLogo.BASE and lt != null and Vector2(lt.get_size()) == TitleLogo.FLAG_L[1]
				and rt != null and Vector2(rt.get_size()) == TitleLogo.FLAG_R[1] and gt != null and Vector2(gt.get_size()) == TitleLogo.GLOW[1],
				"the title's layers match title_logo.gd (the word, the two flags, the rift's glow)")
			check(not ResourceLoader.exists(UI2.V2 + "logo_king.webp"), "(the old title's King is gone)")
			step = 1
		1:
			var ts = app.title_screen
			if ts.t >= 0.1 and ts.t < 0.2 and not seen.has("ignite"):
				seen["ignite"] = [float(ts._flames[0].boost), float(ts.vignette.modulate.a)]
			if ts.t >= 0.32 and ts.t < 0.42 and not seen.has("flying"):
				seen["flying"] = [ts.logo.scale.x, ts.logo.modulate.a, ts.landed, (ts.ghosts[0] as Control).modulate.a,
					(ts.ghosts[0] as Control).scale.x]
			if ts.landed and not seen.has("hit"):
				seen["hit"] = [ts._land_t, ts.shake, (ts._bursts[0] as CPUParticles2D).emitting, ts.jingle != null and ts.jingle.playing,
					ts.ring.p >= 0.0, (ts._bursts[2] as CPUParticles2D).emitting, ts.stage.scale.x, ts._launch]
			if ts.landed and ts.t - ts._land_t < 0.3:
				punch_max = maxf(punch_max, ts.stage.scale.x)
			if ts.landed and ts.t < 1.6:
				kick = maxf(kick, float(ts.logo.boost))
				flare_max = maxf(flare_max, float(ts.logo.rift.flare))
			if ts.t < 1.8:                     # (the title's own clock: a long frame slows its show)
				return false
			var ig: Array = seen.get("ignite", [0.0, 0.0])
			check(float(ig[0]) > 0.5 and float(ig[1]) > 0.1, "the torches flare alight as the edges darken (flare %.2f)" % float(ig[0]))
			var f: Array = seen.get("flying", [0.0, 1.0, true, 0.0, 0.0])
			check(float(f[0]) > 1.3 and not bool(f[2]), "the title flies in big from the viewer (scale %.2f)" % float(f[0]))
			check(float(f[3]) > 0.05 and float(f[4]) > float(f[0]), "...trailing afterimages (%.2f, scale %.2f)" % [float(f[3]), float(f[4])])
			var h: Array = seen.get("hit", [99.0, 0.0, false, false, false, false, 1.0, -1.0])
			check(float(h[0]) < 0.75 and float(h[1]) > 0.5 and bool(h[2]), "...and slams onto the wall at %.2f s: the screen shakes, the dust bursts" % float(h[0]))
			check(bool(h[3]), "the jingle is playing as it hits")
			check(bool(h[4]) and bool(h[5]) and punch_max > 1.03, "the hit: a shockwave ring, gold sparks, a punch-in zoom (%.3f)" % punch_max)
			check(float(h[7]) >= ts.START - 0.001 and absf(float(h[0]) - float(h[7]) - ts.FLIGHT) < 0.06,
				"the show sets off once the game is ready (%.2f s) and hits %.2f s later" % [float(h[7]), float(h[0]) - float(h[7])])
			check(kick > 1.5, "the slam whips the flags about (%.1f times their swing)" % (1.0 + kick))
			check(flare_max > 0.5, "...and the rift flares (%.2f)" % flare_max)
			check((ts.logo.scale as Vector2).distance_to(Vector2.ONE) < 0.02 and ts.stage.position.length() < 0.5 and ts.cracks.grow >= 1.0
				and absf(ts.stage.scale.x - 1.0) < 0.002, "it settles on the wall, cracks run out round it, the shake and the zoom die down")
			check(float(ts.rays_mat.get_shader_parameter("power")) > 0.3, "light rays behind the title")
			check(ts.tap.text == "TAP TO START" and ts.tap.modulate.a > 0.4 and ts.home_is_ready, "TAP TO START (the game behind is ready)")
			check(app._background, "...and with the show over, the game's background loading has started")
			waiting.hold_for_game()                  # (the boot screen: the game has loaded, about to go in)
			made0 = int(app.title_screen.logo.rift.made)
			flag_t0 = float((app.title_screen.logo.flag_l.material as ShaderMaterial).get_shader_parameter("t"))
			step = 2
			t = 0.0
		2:
			var gs: float = app.title_screen.glint_mat.get_shader_parameter("sweep")
			swept = swept or (gs > 0.2 and gs < 0.8)
			var lg = app.title_screen.logo
			var ga: float = lg.rift.glow.modulate.a
			glow_lo = minf(glow_lo, ga)
			glow_hi = maxf(glow_hi, ga)
			if t < 6.0:
				return false
			check(swept, "a gold glint sweeps across the letters")
			var lm := lg.flag_l.material as ShaderMaterial
			var rm := lg.flag_r.material as ShaderMaterial
			check(float(lm.get_shader_parameter("t")) - flag_t0 > 5.0 and lg.flag_amp() > 0.0 and float(rm.get_shader_parameter("amp")) > 0.0
				and float(lm.get_shader_parameter("side")) == 1.0 and float(rm.get_shader_parameter("side")) == -1.0,
				"both flags wave from their poles all the while (swing %.1f px)" % lg.flag_amp())
			check(float(lg.boost) < 0.1 and lg.flag_amp() < TitleLogo.FLAG_AMP * 1.15, "...the slam's whipping died back to a breeze (%.2f)" % float(lg.boost))
			var bolts := int(lg.rift.made) - made0
			check(bolts >= 15 and (lg.rift.sparks as CPUParticles2D).emitting and glow_hi - glow_lo > 0.1,
				"the rift crackles: %d bolts in 6 s, sparks, its glow flickering (%.2f to %.2f)" % [bolts, glow_lo, glow_hi])
			check(still.landed and still.logo.scale == Vector2.ONE and still.stage.position == Vector2.ZERO
				and still.logo.flag_amp() == 0.0 and int(still.logo.rift.made) == 0 and not (still.logo.rift.sparks as CPUParticles2D).emitting,
				"with Reduce Motion: no flight, no shake, the flags and the rift still")
			# no game behind it: LOADING..., no show; held still for the game going in; a tap is kept, and the moment
			# the game is ready the screen lifts, straight in
			check(waiting.tap.text == "LOADING..." and waiting.tap.modulate.a > 0.2 and not waiting.home_is_ready and waiting._launch < 0.0
				and not waiting.landed, "with no game behind it yet: LOADING..., and the show waits")
			check(waiting.holding and waiting.can_swap() and waiting._drift.modulate.a < 0.01 and absf(waiting.tap.modulate.a - 0.6) < 0.01,
				"held for the game going in: still (the embers gone, LOADING... not pulsing), then it may go in")
			var ev0 := InputEventMouseButton.new()
			ev0.button_index = MOUSE_BUTTON_LEFT
			ev0.pressed = true
			waiting._gui_input(ev0)
			check(waiting.want_leave and not waiting.leaving, "a tap while loading is kept")
			waiting.home_ready()
			check(waiting.leaving and waiting._launch < 0.0, "...and lifts the screen the moment the game is ready, straight in")
			# a tap lifts it off Home
			app.title_screen.done.connect(func(): gone = true)
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = true
			app.title_screen._gui_input(ev)
			step = 3
			t = 0.0
		3:
			if t < 0.8:
				return false
			check(gone and app.title_screen == null and app.tab == "home", "a tap lifts the title screen off Home")
			check(waiting_gone, "(the waiting one is gone too)")
			_loading_screens()
			print("TITLE_LOGO_PASS" if fails.is_empty() else "TITLE_LOGO_FAIL %s" % str(fails))
			quit(0 if fails.is_empty() else 1)
			return true
	return false

func _loading_screens() -> void:
	# the first-start download screen (built as the loader builds it, nothing downloaded)
	var cl := Control.new()
	cl.set_script(load("res://scripts/app/content_loader.gd"))
	cl._build_ui()
	var texs := cl.find_children("*", "TextureRect", true, false).map(func(n): return (n as TextureRect).texture.resource_path if (n as TextureRect).texture else "")
	check(texs.has("res://assets/branding/splash.png") and texs.has("res://assets/branding/title_logo.webp"),
		"the download screen: the castle wall and the title, from the base build (%s)" % str(texs))
	cl.free()
	# the match's warm-up cover (0.31.208: the loading screen -- its courtyard painting, not the castle wall)
	var sm := Control.new()
	sm.set_script(load("res://scripts/siege/siege_mode.gd"))
	sm._cover_show()
	var cover: Control = sm._cover
	var walls := cover.find_children("*", "TextureRect", false, false).filter(func(n): return (n as TextureRect).texture != null and (n as TextureRect).texture.resource_path.ends_with("bg_loading.webp"))
	var logos := cover.find_children("*", "", true, false).filter(func(n): return n.get_script() == TitleLogo)
	check(walls.size() == 1 and logos.size() == 1, "the warm-up cover: the loading screen's painting and the title")
	sm.free()
	# the boot splash
	var img := str(ProjectSettings.get_setting("application/boot_splash/image", ""))
	check(img == "res://assets/branding/splash_land.png" and FileAccess.file_exists(img) and int(ProjectSettings.get_setting("application/boot_splash/stretch_mode", 0)) == 4,
		"the boot splash is the castle wall, covering the screen")
