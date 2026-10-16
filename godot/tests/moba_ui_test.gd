extends SceneTree
# 0.31.155 5V5 (the test) in the app:
#  1. Home: 5V5 (TEST) on the right -- under TUTORIAL until the tutorial's done, in its place after; it opens the hero
#     window: 12 heroes, the last pick kept;
#  2. a hero picked, BATTLE: an offline 5v5 as that hero (no server, no ticket);
#  3. the HUD: level and XP, the towers standing; a level-up's three upgrades tapped on the screen apply one;
#  4. the end: the results without rewards (the gold as it was).
#   godot --headless --path godot -s res://tests/moba_ui_test.gd   (SHOT_DIR=... under Xvfb for pictures)
const App = preload("res://scripts/app/siege_app.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Moba = preload("res://scripts/siege/moba.gd")
const HeroPanel = preload("res://scripts/app/moba_panel.gd")

var fails: Array = []
var phase := "fresh"
var t := 0.0
var t_phase := 0.0
var app
var shots := ""
var gold0 := 0

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

func has_text(node: Node, s: String) -> bool:
	if (node is Label and (node as Label).text.contains(s)) or (node is Button and (node as Button).text.contains(s)):
		return node.is_visible_in_tree()
	for c in node.get_children():
		if has_text(c, s):
			return true
	return false

func _init() -> void:
	shots = OS.get_environment("SHOT_DIR") if DisplayServer.get_name() != "headless" else ""
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")

func _shot(name: String) -> void:
	if shots != "":
		root.get_viewport().get_texture().get_image().save_png(shots.path_join(name + ".png"))

func _go(next: String) -> void:
	phase = next
	t_phase = 0.0

func _app(done: bool) -> void:
	var base := "user://mobaui-%d" % Time.get_ticks_usec()
	var p = Profile.new(base + "-profile.json", base + "-none.json")
	p.load_or_create()
	p.d.name = "Alice"
	p.d.tutorial_done = done
	p.save()
	app = App.new()
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	root.add_child(app)

func _process(delta: float) -> bool:
	t += delta
	t_phase += delta
	if t > 150.0:
		check(false, "timed out in phase %s" % phase)
		return _finish()
	match phase:
		"fresh":
			_app(false)
			_go("fresh_home")
		"fresh_home":
			if t_phase > 1.0:
				var tb := btn("tutorial_start")
				var mb := btn("side_moba")
				var pb := btn("play")
				check(tb != null and mb != null and has_text(mb, "5V5") and mb.global_position.y >= tb.global_position.y + tb.size.y - 8.0
					and absf(mb.global_position.x - tb.global_position.x) < 1.0 and pb != null and not mb.get_global_rect().intersects(pb.get_global_rect()),
					"no tutorial yet: 5V5 under TUTORIAL, clear of PLAY")
				app.queue_free()
				app = null
				_go("boot")
		"boot":
			if t_phase > 0.3:
				_app(true)
				_go("home")
		"home":
			if t_phase > 1.0:
				check(btn("side_moba") != null and btn("tutorial_start") == null and btn("side_commander") == null, "Home: 5V5 where the tutorial was")
				_shot("moba_home")
				press("side_moba")
				_go("heroes")
		"heroes":
			if t_phase > 0.4:
				check(app.modal is HeroPanel, "it opens the hero window")
				var n := 0
				for hid in Moba.HERO_ORDER:
					if btn("moba_hero_" + str(hid)) != null:
						n += 1
				check(n == 12 and app.modal.hero == "knight" and has_text(app.modal, "Knight: Shield up"), "12 heroes; the Knight to start, described")
				press("moba_hero_archmage")
				check(app.modal.hero == "archmage" and has_text(app.modal, "Archmage: Calls down a meteor"), "the Archmage picked")
				_shot("moba_heroes")
				gold0 = int(app.profile.d.gold)
				press("moba_battle")
				_go("match")
		"match":
			if app.siege != null and app.siege.sim != null and app.siege.hud != null and t_phase > 1.0:
				var s = app.siege
				var me: Dictionary = s.sim.by_id["you"]
				check(str(app.profile.d.settings.get("moba_hero", "")) == "archmage", "the pick kept on the phone")
				check(s.moba_hero == "archmage" and not s.online and not s.tutorial and s.sim.moba != null and me.cls == "mage" and me.up
					and s.sim.units.size() == 10, "BATTLE: an offline 5v5, you the Archmage")
				# a level up: three upgrades on the screen; tap the second
				s.sim.moba.add_xp(me, Moba.XP_BASE + 1.0)
				var offer: Array = (me.picks as Array)[0]
				var r: Rect2 = s.hud.pick_rect(1)
				s.hud._touch(0, r.get_center(), true)
				s.hud._touch(0, r.get_center(), false)
				check(int(me.level) == 2 and (me.picks as Array).is_empty() and int((me.ups as Dictionary).get(str(offer[1]), 0)) == 1,
					"level 2: three upgrades on the screen; the second tapped (%s) applies" % str(offer[1]))
				_go("play")
		"play":
			if t_phase > 0.5 and t_phase < 0.6:
				var s0 = app.siege
				s0.sim.moba.add_xp(s0.sim.by_id["you"], Moba.XP_BASE * 3.0)    # (picks waiting, for the picture)
			if t_phase > 3.0:
				_shot("moba_match")
				var s = app.siege
				check(s.hud._picks_open() and has_moba_status(s), "picks waiting on the screen; LEVEL and TOWERS under your health")
				s.sim._finish("time")
				_go("end")
		"end":
			if t_phase > 1.5:
				var s = app.siege
				check(s.hud.result_panel != null and int(app.profile.d.gold) == gold0, "the results; no rewards (the gold as it was)")
				_shot("moba_result")
				return _finish()
	return false

func has_moba_status(s) -> bool:
	# (drawn, not nodes: the HUD's status draws from these)
	var me: Dictionary = s.sim.by_id["you"]
	return int(me.level) >= 2 and s.sim.moba.towers.size() == 12

func _finish() -> bool:
	print("MOBA_UI_PASS" if fails.is_empty() else "MOBA_UI_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
	return true
