extends SceneTree
# 0.31.198 (Kevin, with the server wiped so everyone starts fresh: "Have the game ask their name and after they do that
# it'll briefly say what game is and then ask if they would like to play tutorial. Make the tutorial guy pop up while
# doing this and voice it ... Make it very funny"; "Also have him briefly take player through menus"): the Royal
# Herald's welcome (scripts/app/herald_intro.gd), through the app, in REAL time.
#  - his lines are the voiced script's (art_sources/tutorial/intro_script.json without its [directions]), each with its
#    voice and one of his eight poses;
#  - a player named "Player" (a new account) gets him on Home, nobody else does;
#  - he asks the name: nothing, "player" or "King" get a word from him and no name; a name is saved (the op) and
#    announced;
#  - what Fatebound is, then the tour: PLAY, the chests, SHOP, PASS, LOCKER, ALLIANCE, the menu -- each one found on
#    Home, the shade open over it, the scroll out of its way (at the top for what's below);
#  - the offer: I'LL WING IT closes him (Home, no tutorial); SHOW ME HOW starts the tutorial.
#   godot --headless --path godot -s res://tests/herald_intro_test.gd
const App = preload("res://scripts/app/siege_app.gd")
const Intro = preload("res://scripts/app/herald_intro.gd")
const Poses = preload("res://scripts/siege/tutorial_poses.gd")

var app
var it
var t := 0.0
var step := 0
var wait_until := 0.0
var fails := []
var tour_seen := {}

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func btn(key: String, node: Node = null) -> Button:
	if node == null:
		node = app
	if node is Button and str(node.get_meta("action_key", "")) == key and node.is_visible_in_tree():
		return node
	for c in node.get_children():
		var r := btn(key, c)
		if r != null:
			return r
	return null

func press(key: String) -> bool:
	var b := btn(key)
	if b == null or b.disabled:
		check(false, "button %s present and enabled" % key)
		return false
	b.pressed.emit()
	return true

func _init() -> void:
	_script_checks()
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1/fatebound/siege/ws")   # nothing listens there
	var base := "user://heraldintro-%d" % Time.get_ticks_usec()
	app = App.new()
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	app.now_override = 1791000000
	root.add_child(app)

func _script_checks() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join("../art_sources/tutorial/intro_script.json")
	var script: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(script is Array and (script as Array).size() == Intro.LINES.size(), "the intro script has a line for each of his (%d)" % Intro.LINES.size())
	var by_id := {}
	if script is Array:
		for l in script:
			by_id[str(l[0])] = str(l[1])
	var rx := RegEx.create_from_string("\\[[^\\]]*\\]")
	var ws := RegEx.create_from_string("\\s+")
	for k in Intro.LINES:
		var l: Array = Intro.LINES[k]
		var spoken := ws.sub(rx.sub(str(by_id.get(str(l[0]), "")), "", true), " ", true).strip_edges()
		check(spoken == str(l[1]), "%s: the caption is what he says" % k)
		check(ResourceLoader.exists("res://assets/vo/tutorial/%s.ogg" % str(l[0])), "%s: voiced (%s.ogg)" % [k, str(l[0])])
		check(Poses.POSES.has(str(l[2])) and ResourceLoader.exists("res://assets/ui/tutorial/scroll_%s.png" % str(l[2])), "%s: a pose of his (%s)" % [k, str(l[2])])
	var at := "named"
	var tour := []
	while Intro.NEXT.has(at):
		at = str(Intro.NEXT[at])
		if Intro.TOUR.has(at):
			tour.append(str(Intro.TOUR[at][1]))
	check(at == "ask" and tour == ["PLAY", "CHESTS", "SHOP", "PASS", "LOCKER", "ALLIANCE", "MENU"], "named -> what -> the tour %s -> the offer" % str(tour))
	for n in ["", "  ", "player", "PLAYER", "King", "herald", "Royal Herald", "admin"]:
		check(Intro.name_quip(n) != "", "the name \"%s\" gets a word from him instead" % n)
	check(Intro.name_quip("Midblade") == "" and Intro.name_quip("Kingsley") == "", "a real name doesn't")

func _later(s: float) -> void:
	wait_until = t + s

func _process(d: float) -> bool:
	t += d
	if t < wait_until:
		return false
	var p = app.profile if app != null else null
	match step:
		0:
			check(app.tab == "home" and btn("play") != null, "the app opens on Home")
			check(str(p.d.name) == "Player" and app.needs_intro(), "a new player (\"Player\") needs the Herald")
			check(not app.offer_intro(), "...not in a test unless asked (intro_auto)")
			app.intro_auto = true
			check(app.offer_intro() and app.modal is Intro, "on Home he pops up")
			it = app.modal
			check(it.step == "hello" and it.lines_said == ["intro_hello"] and it.pose == "peeking", "his hello, peeking round the scroll")
			check(not it.name_box.visible and it.text_label.text.begins_with("Oh! Hello."), "his line on the scroll, typing")
			_later(0.5)
		1:
			check(not it.typed(), "typed out as he says it")
			it.next()
			check(it.typed(), "a tap: the whole line")
			it.next()
			check(it.name_box.visible and btn("intro_name_ok") != null, "the next: the name field and THAT'S ME")
			it.name_edit.text = ""
			press("intro_name_ok")
			check(it.quip != "" and str(p.d.name) == "Player" and it.name_box.visible, "no name: a word from him, the field still up")
			it.name_edit.text = "player"
			press("intro_name_ok")
			check(it.text_label.text == Intro.NAME_QUIPS["player"] and str(p.d.name) == "Player", "\"player\": not a name, he says")
			it.name_edit.text = "  Midblade  "
			press("intro_name_ok")
			check(str(p.d.name) == "Midblade" and not app.needs_intro(), "a name: saved (%s)" % str(p.d.name))
			check(it.step == "named" and it.banner.visible and it.banner.text.contains("MIDBLADE"), "...and announced: %s" % it.banner.text)
			check(not app.offer_intro(), "a player with a name doesn't get him again")
			it.shown = 9999.0
			it.next()
			check(it.step == "what" and it.text_label.text.contains("This is Fatebound"), "what Fatebound is")
			check(not it.hole_want.has_area(), "...with the whole screen shaded")
			it.shown = 9999.0
			it.next()
			_later(0.6)
			step = 2
			return false
		2:
			# the tour: one stop a visit
			var k: String = it.tour_key()
			if k == "":
				check(it.step == "ask", "after the tour, the offer (%s)" % it.step)
				check(tour_seen.size() == 7, "seven stops %s" % str(tour_seen.keys()))
				_later(0.6)
				step = 3
				return false
			var r: Rect2 = it.target_rect(k)
			check(r.has_area(), "%s: %s found on Home %s" % [it.step, k, str(r)])
			check(it.hole_now.has_area() and it.hole_now.grow(-1.0).encloses(Rect2(r.get_center(), Vector2.ONE)) and it.hole_want.encloses(r),
				"%s: the shade open over it %s" % [it.step, str(it.hole_now)])
			var below: bool = r.get_center().y > float(app.size.y) * 0.42
			var art: Rect2 = it.scroll.get_global_rect()
			# (at the top: clear of what's shown on a phone's shape -- headless is square, where the scroll is as tall as the
			# screen is wide)
			var tall: bool = app.size.y > app.size.x * 1.5
			check(it.at_top == below and (not below or art.position.y <= 12.0 + float(app.safe_top)) and (not below or not tall or art.end.y < r.position.y + 4.0),
				"%s: the scroll %s, out of its way %s" % [it.step, "at the top" if below else "at the foot", str(art)])
			tour_seen[k] = true
			it.shown = 9999.0
			it.next()
			_later(0.6)
			return false
		3:
			check(not it.hole_want.has_area() and not it.at_top, "the offer: the shade shut again, the scroll back at the foot")
			it.shown = 9999.0
			it.next()
			check(it.choice_box.visible and btn("intro_tutorial_yes") != null and btn("intro_tutorial_no") != null, "SHOW ME HOW / I'LL WING IT")
			press("intro_tutorial_no")
			check(it.step == "no" and it.lines_said[-1] == "intro_no" and it.pose == "napping", "I'LL WING IT: off he goes, napping")
			it.shown = 9999.0
			it.next()
			check(app.modal == null and app.siege == null and app.tab == "home", "...and he's gone: Home, no tutorial")
			check(it.lines_said == ["intro_hello", "intro_named", "intro_what", "tour_play", "tour_chests", "tour_shop", "tour_pass",
				"tour_locker", "tour_alliance", "tour_menu", "intro_ask", "intro_no"], "every line once, in order")
			_later(0.4)
		4:
			# again, for SHOW ME HOW
			p.d.name = "Player"
			check(app.offer_intro(), "(again, a new player)")
			it = app.modal
			it.shown = 9999.0
			it.next()
			it.submit_name("Robin")
			for i in 12:
				if it.step == "ask":
					break
				it.shown = 9999.0
				it.next()
			it.shown = 9999.0
			it.next()
			press("intro_tutorial_yes")
			check(it.step == "yes" and it.lines_said[-1] == "intro_yes", "SHOW ME HOW: a recruit with sense")
			it.shown = 9999.0
			it.next()
			check(app.modal == null and app.siege != null, "...and the tutorial starts")
			_later(1.0)
		5:
			print("HERALD_INTRO_PASS" if fails.is_empty() else "HERALD_INTRO_FAIL %s" % str(fails))
			quit(0 if fails.is_empty() else 1)
			return true
	step += 1
	return false
