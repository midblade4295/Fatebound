extends SceneTree
# 0.31.141 (Kevin: "Make the intro splash screen more exciting and also load faster"): the start-up order, from the
# app's first scene (Boot.tscn, content_loader.gd) as the phone runs it:
#  - the title screen is up as soon as the packs are mounted, BEFORE the game (Main.tscn) has loaded, and the game is
#    loading on a thread behind it;
#  - the game goes in behind the title only once the slam has settled (title_screen.can_swap), and takes that same
#    title over (no second one); Home ready -> TAP TO START; a tap lifts it off Home;
#  - the match's script and the windows opened later are not compiled with the game (siege_app.gd has no preload of
#    them): they load first in the background queue (asset_cache.gd), or there and then.
#   godot --headless --path godot -s res://tests/boot_title_test.gd
# (Not preloading siege_app.gd here: that would compile the game before the boot screen gets to load it.)
const MAIN := "res://scenes/Main.tscn"
const TITLE_GROUP := "title_screen"

var fails: Array = []
var t := 0.0
var step := 0
var title = null
var app = null
var title_at := -1.0
var swap_at := -1.0
var swap_landed := false
var swap_settled := 0.0
var gone := false

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")      # nothing listens there

func _is_app(n: Node) -> bool:
	return n != null and n.get_script() != null and str(n.get_script().resource_path).ends_with("siege_app.gd")

func _finish() -> bool:
	print("BOOT_TITLE_PASS" if fails.is_empty() else "BOOT_TITLE_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
	return true

func _process(d: float) -> bool:
	t += d
	match step:
		0:
			change_scene_to_file("res://scenes/Boot.tscn")
			step = 1
			t = 0.0
		1:
			var up := get_nodes_in_group(TITLE_GROUP)
			if up.is_empty():
				if t > 10.0:
					check(false, "the title screen goes up from the boot screen")
					return _finish()
				return false
			title = up[0]
			title_at = t
			var cur := current_scene
			check(cur != null and cur.has_meta("content_loader") and not _is_app(cur),
				"the title is up while the boot screen is still the scene -- before the game (%.2f s)" % t)
			check(bool(cur.get("_loading_main")) and (cur.get("_game_thread") as Thread) != null and (cur.get("_game_thread") as Thread).is_started(),
				"...and the game is loading behind it on a thread of its own (not the worker pool: cold_start_check.sh)")
			check((title.get_parent() as CanvasLayer) != null and (title.get_parent() as CanvasLayer).layer >= 90
				and title.get_parent().get_parent() == root, "it stands on its own layer under the root (the scene change leaves it)")
			check(title.app == null and not title.home_is_ready, "no game yet: the title has none behind it")
			step = 2
		2:
			if not _is_app(current_scene):
				if t > 60.0:
					check(false, "the game goes in behind the title")
					return _finish()
				return false
			app = current_scene
			swap_at = t
			swap_landed = bool(title.landed)
			swap_settled = float(title.t) - float(title._land_t)
			check(is_instance_valid(title) and swap_landed and swap_settled >= 0.4,
				"the game goes in behind the title after the slam (%.2f s after it)" % swap_settled)
			check(app.title_screen == title and title.app == app and get_nodes_in_group(TITLE_GROUP).size() == 1,
				"the game takes that title over (one title screen)")
			var consts: Dictionary = app.get_script().get_script_constant_map()
			check(not consts.has("Siege") and consts.has("SIEGE_MODE") and not consts.has("ChatPanel") and not consts.has("ClanPanel"),
				"the match's script and the later windows aren't compiled with the game")
			var Assets = load("res://scripts/siege/asset_cache.gd")
			check(Assets._loading == app.SIEGE_MODE or Assets.has(app.SIEGE_MODE),
				"...the match's script loads first in the background queue (%s)" % str(Assets._loading))
			step = 3
		3:
			if not title.home_is_ready:
				if t - swap_at > 20.0:
					check(false, "Home ready behind the title")
					return _finish()
				return false
			if float(title.t) < title.TAP_AT + 0.5:
				return false
			check(title.tap.text == "TAP TO START" and title.tap.modulate.a > 0.3 and app.tab == "home",
				"Home ready behind it: TAP TO START")
			title.done.connect(func(): gone = true)
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = true
			title._gui_input(ev)
			step = 4
			t = 0.0
		4:
			if t < 0.8:
				return false
			check(gone and app.title_screen == null and get_nodes_in_group(TITLE_GROUP).is_empty() and app.tab == "home",
				"a tap lifts the title off Home")
			check(root.get_children().filter(func(n): return n is CanvasLayer and n.name == "TitleLayer").is_empty(),
				"(its layer is gone with it)")
			var siege_script = app._later(app.SIEGE_MODE)
			check(siege_script is GDScript and (siege_script as GDScript).can_instantiate(), "the match's script is there when Play is pressed")
			var panel = app._later(app.CHAT_PANEL)
			check(panel is GDScript, "...and a window's")
			print("timings: title up %.2f s after the boot screen, the game behind it %.2f s later" % [title_at, swap_at - title_at])
			return _finish()
	return false
