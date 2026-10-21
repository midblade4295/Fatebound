extends SceneTree
# 0.31.198: the Royal Herald's welcome (scripts/app/herald_intro.gd) on a fresh install's Home, step by step: his hello,
# a name he won't write, the name field, the name announced, what Fatebound is, each stop of the menu tour, the
# tutorial offer. intro_NN_<step>.png in SHOT_DIR.
#   DISPLAY=:99 SHOT_DIR=/tmp/x SIEGE_URL=ws://127.0.0.1:1 godot --rendering-method mobile --resolution 420x910 \
#     --path godot -s res://tools/herald_intro_shot.gd
const App = preload("res://scripts/app/siege_app.gd")

var app
var dir := "/tmp"
var n := 0

func _init() -> void:
	if OS.has_environment("SHOT_DIR"):
		dir = OS.get_environment("SHOT_DIR")
	var base := "user://introshot-%d" % Time.get_ticks_usec()
	app = App.new()
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	root.add_child(app)
	_run.call_deferred()

func _wait(frames: int) -> void:
	for i in frames:
		await process_frame

func _shot(tag: String) -> void:
	await _wait(3)
	n += 1
	root.get_viewport().get_texture().get_image().save_png(dir.path_join("intro_%02d_%s.png" % [n, tag]))

func _run() -> void:
	await _wait(90)
	app.open_intro()
	var it = app.modal
	await _wait(40)
	await _shot("hello")
	it.shown = 9999.0
	it.next()
	await _wait(20)
	await _shot("name_box")
	it.submit_name("player")
	await _wait(60)
	await _shot("quip")
	it.submit_name("Midblade")
	await _wait(30)
	await _shot("named")
	while it.step != "ask":
		it.shown = 9999.0
		it.next()
		await _wait(50)
		await _shot(it.step)
	await _wait(240)
	it.shown = 9999.0
	it.voice.stop()
	await _wait(10)
	await _shot("choice")
	print("HERALD_INTRO_SHOTS done %d" % n)
	quit(0)
