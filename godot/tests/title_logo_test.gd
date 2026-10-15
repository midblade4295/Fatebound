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
#   godot --headless --path godot -s res://tests/title_logo_test.gd
const App = preload("res://scripts/app/siege_app.gd")
const TitleLogo = preload("res://scripts/app/title_logo.gd")
const TitleScreen = preload("res://scripts/app/title_screen.gd")
const UI2 = preload("res://scripts/app/ui2.gd")

var app
var still                                # a title screen with Reduce Motion
var fails: Array = []
var t := 0.0
var step := 0
var lo := 0.0
var hi := 0.0
var knot0 := Vector2.ZERO
var knot_moved := 0.0
var seen := {}
var gone := false

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _knot() -> Vector2:
	var k: Control = app.title_screen.logo.king
	return k.get_global_transform() * k.pivot_offset

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
	still.size = Vector2(420, 933)
	root.add_child(still)

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
			check(ts.jingle != null and ts.jingle.playing and ts.jingle.stream is AudioStreamOggVorbis, "the jingle plays")
			check(ResourceLoader.exists("res://assets/sounds/titleSlam.wav"), "the slam's sound is there")
			var bt: Texture2D = UI2.tex(UI2.V2 + "logo_base.webp")
			var kt: Texture2D = UI2.tex(UI2.V2 + "logo_king.webp")
			check(bt != null and Vector2(bt.get_size()) == TitleLogo.BASE and kt != null and Vector2(kt.get_size()) == TitleLogo.KING_SIZE,
				"the title's two layers match title_logo.gd")
			step = 1
		1:
			var ts = app.title_screen
			if t >= 0.32 and t < 0.42 and not seen.has("flying"):
				seen["flying"] = [ts.logo.scale.x, ts.logo.modulate.a, ts.landed]
			if ts.landed and not seen.has("hit"):
				seen["hit"] = [t, ts.shake, (ts._bursts[0] as CPUParticles2D).emitting]
			if ts.landed and t > 1.0 and not seen.has("settled"):
				seen["settled"] = [ts.logo.scale, ts.tap.modulate.a]
			if t < 1.8:
				return false
			var f: Array = seen.get("flying", [0.0, 1.0, true])
			check(float(f[0]) > 1.3 and not bool(f[2]), "the title flies in big from the viewer (scale %.2f)" % float(f[0]))
			var h: Array = seen.get("hit", [99.0, 0.0, false])
			check(float(h[0]) < 0.7 and float(h[1]) > 0.5 and bool(h[2]), "...and slams onto the wall at %.2f s: the screen shakes, the dust bursts" % float(h[0]))
			check((ts.logo.scale as Vector2).distance_to(Vector2.ONE) < 0.02 and ts.stage.position.length() < 0.5 and ts.cracks.grow >= 1.0,
				"it settles on the wall, cracks run out round it, the shake dies down")
			check(ts.tap.text == "TAP TO START" and ts.tap.modulate.a > 0.4, "TAP TO START")
			knot0 = _knot()
			step = 2
			t = 0.0
		2:
			var r: float = rad_to_deg(app.title_screen.logo.king.rotation)
			lo = minf(lo, r)
			hi = maxf(hi, r)
			knot_moved = maxf(knot_moved, _knot().distance_to(knot0))
			if t < 3.0:
				return false
			check(lo < -TitleLogo.SWING_DEG * 0.8 and hi > TitleLogo.SWING_DEG * 0.8, "the King swings both ways (%.1f to %.1f degrees)" % [lo, hi])
			check(lo >= -TitleLogo.SWING_DEG - 0.01 and hi <= TitleLogo.SWING_DEG + 0.01, "no further than %.0f degrees" % TitleLogo.SWING_DEG)
			check(knot_moved < 0.5, "he turns about the knot (it moved %.2f px)" % knot_moved)
			check(still.landed and still.logo.scale == Vector2.ONE and still.stage.position == Vector2.ZERO
				and absf(still.logo.king.rotation) < 0.0001, "with Reduce Motion: no flight, no shake, the King hangs still")
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
	# the match's warm-up cover
	var sm := Control.new()
	sm.set_script(load("res://scripts/siege/siege_mode.gd"))
	sm._cover_show()
	var cover: Control = sm._cover
	var walls := cover.find_children("*", "TextureRect", false, false).filter(func(n): return (n as TextureRect).texture != null and (n as TextureRect).texture.resource_path.ends_with("bg_title_wall.webp"))
	var logos := cover.find_children("*", "", true, false).filter(func(n): return n.get_script() == TitleLogo)
	check(walls.size() == 1 and logos.size() == 1, "the warm-up cover: the castle wall and the swinging title")
	sm.free()
	# the boot splash
	var img := str(ProjectSettings.get_setting("application/boot_splash/image", ""))
	check(img == "res://assets/branding/splash.png" and FileAccess.file_exists(img) and int(ProjectSettings.get_setting("application/boot_splash/stretch_mode", 0)) == 4,
		"the boot splash is the castle wall, covering the screen")
