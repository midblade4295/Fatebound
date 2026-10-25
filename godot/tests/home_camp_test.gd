extends SceneTree
# Home (0.31.194, Kevin: "Now let's design a new home screen" -- he picked B2, the champions' camp, keeping the chest
# slots, the chat bar and the Discord / server pill; the side buttons go to "Menu button"):
#  - the backdrop is the camp painting (bg_camp.webp), as wide as the screen and reaching from the top to near the bottom
#    on 16:9 to 21:9 phones, standing so the champions' feet are just over the PLAY plaque (never hidden under it);
#  - alive: the fire's tongues sway and its light flickers on the painting (the shader's clock and flicker run), the
#    lanterns flicker, embers and smoke rise, the magic breathes and sparkles, the windows dim now and then, the stars
#    twinkle, a star falls, the fireflies wander; Reduce Motion holds it all still (no particles, no fireflies, the
#    shader's motion 0); a safe start sends no particles;
#  - 0.31.215: the picture is the 3D render (tools/render_home_camp.gd): the Mage's gem and the Stormcaller's crystal
#    are the magic; no lit windows, lamps or pennants in view (the checks follow the scene's lists)
#  - in the app: Home's backdrop is the camp (no 3D heroes); no side buttons; the top row is the 5v5 pill and JOIN OUR
#    DISCORD side by side; PLAY is the new plaque with FIRST WIN as a tab under it, above the chest panels (each with its
#    name), all on screen; the top bar's menu button opens ORDERS, QUESTS, RANKS and the TUTORIAL; its badge counts
#    what's ready (a "!" and a glow until the tutorial's played);
#  - (kept) each empty chest slot shows a dim chest; the players online line (0.31.140).
#   godot --headless --path godot -s res://tests/home_camp_test.gd
const App = preload("res://scripts/app/siege_app.gd")
const CampScene = preload("res://scripts/app/camp_scene.gd")
const Screens = preload("res://scripts/app/screens.gd")
const Eco = preload("res://scripts/meta/economy.gd")

var app
var phone                                # the camp as a 420 x 933 phone lays it out
var still                                # ... with reduce motion
var bare                                 # ... on a safe start
var fails: Array = []
var t := 0.0
var step := 0
var snap := {}

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func has_text(node: Node, s: String) -> bool:
	if node is Label and (node as Label).text.contains(s) and (node as Label).is_visible_in_tree():
		return true
	for c in node.get_children():
		if has_text(c, s):
			return true
	return false

func btn(key: String) -> Button:
	for n in root.find_children("*", "Button", true, false):
		if n.has_meta("action_key") and str(n.get_meta("action_key")) == key and not n.is_queued_for_deletion() and n.is_inside_tree():
			return n
	return null

func _scene(calm: bool, safe: bool, sz := Vector2(420, 933)) -> Control:
	var box := Control.new()
	box.size = sz
	root.add_child(box)
	var s := CampScene.new(calm, safe)
	s.size = sz
	box.add_child(s)
	return s

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")      # nothing listens there
	var base := "user://homecamp-%d" % Time.get_ticks_usec()
	app = App.new()
	app.eco_autostart = false
	app.social_autostart = false
	app.version_check = false
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	root.add_child(app)
	phone = _scene(false, false)
	still = _scene(true, false)
	bare = _scene(false, true)

func _play_top(w: float, h: float) -> float:
	# PLAY's top on a phone this size (siege_app.home_play_top, no notch)
	var hh := h - (6.0 + App.TOP_H) - float(App.ChatTicker.H) - App.TAB_H - 30.0
	return 6.0 + App.TOP_H + 4.0 + float(Screens.home_layout(hh).play)

func _process(d: float) -> bool:
	t += d
	if step == 0:
		if t < 1.2:
			return false
		step = 1
		for s in [phone, still, bare]:
			s.place(_play_top(420.0, 933.0))
		phone._shooting.wait = 0.3                              # (a star falls soon)
		# three chests: one ready, one unlocking, one waiting its turn; the fourth slot empty
		var p = app.profile
		var out := {}
		for k in ["silver", "gold", "wooden"]:
			p.add_chest(k, out)
		p.chests()[0].start = p.now() - int(Eco.CHESTS.silver.unlock) - 5
		p.chests()[1].start = p.now()
		app.rebuild()
		snap = _snapshot(phone)
		snap["still"] = _snapshot(still)
		t = 0.0
		return false
	if step == 1:
		if t < 1.6:
			return false
		step = 2
		_checks_scene()
		_checks_alive()
		_checks_app()
		t = 0.0
		return false
	if step == 2:
		# the menu: open it, look, close it
		if t < 0.3:
			return false
		step = 3
		_checks_menu()
		t = 0.0
		return false
	if t < 0.3:
		return false
	print("HOME_CAMP_PASS" if fails.is_empty() else "HOME_CAMP_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
	return true

func _snapshot(s) -> Dictionary:
	var out := {"tongues": [], "lamps": [], "pulses": [], "stars": [], "flies": []}
	for tg in s._tongues:
		out.tongues.append((tg[0] as Control).scale)
	for l in s._lamps:
		out.lamps.append((l.core as Control).scale)
	for p in s._pulses:
		out.pulses.append((p[0] as Control).modulate.a)
	for st in s._stars:
		out.stars.append((st[0] as Control).modulate.a)
	if s.flies != null:
		for f in s.flies.flies:
			out.flies.append(f.p)
	var cl = (s.art.material as ShaderMaterial).get_shader_parameter("clock")
	out["clock"] = float(cl) if cl != null else 0.0
	out["flick"] = float(s.flick)
	return out

func _checks_scene() -> void:
	var tex: Texture2D = load(CampScene.ART)
	check(tex != null and tex.get_size() == CampScene.PAINT, "the camp painting is there (%s)" % str(tex.get_size() if tex != null else null))
	# laid out on phones from 16:9 to 21:9, 360 and 420 wide
	var bad := ""
	for sz in [Vector2(420, 933), Vector2(360, 780), Vector2(360, 800), Vector2(360, 840), Vector2(420, 747), Vector2(360, 640)]:
		var s: Control = _scene(false, true, sz)
		var pt := _play_top(sz.x, sz.y)
		s.place(pt)
		var feet: float = s.origin.y + CampScene.FEET_Y * s.k
		var why := ""
		if s.origin.y > 0.01 or s.origin.x > 0.01 or s.origin.x + CampScene.PAINT.x * s.k < sz.x - 0.01:
			why += " leaves a gap (origin %s)" % str(s.origin)
		if s.painting_bottom() < sz.y - CampScene.COVER_TO - 0.5:
			why += " stops at %.0f" % s.painting_bottom()
		if feet > pt + CampScene.FEET_OVER + 0.5:
			why += " the feet (%.0f) go under PLAY (%.0f)" % [feet, pt]
		if s.k > sz.x / CampScene.PAINT.x * 1.12:
			why += " too wide (k %.3f)" % s.k
		if why != "":
			bad += " %s:%s" % [str(sz), why]
		s.get_parent().queue_free()
	check(bad == "", "the camp covers the screen as wide as it is, from the top to near the bottom, the champions' feet over PLAY%s" % bad)
	check(phone.paint_layer.get_child_count() > 20 and phone.embers != null and phone.smoke != null and phone.wisps.size() == CampScene.MAGIC.size()
		and phone._tongues.size() == CampScene.TONGUES.size() and phone._lamps.size() == CampScene.LAMPS.size()
		and phone._windows.size() == CampScene.WINDOWS.size(), "the fire, the lamps, the magic, the windows and the sky are laid on it")
	var m := phone.art.material as ShaderMaterial
	check(int(m.get_shader_parameter("cloth_n")) == CampScene.BANNERS.size() and int(m.get_shader_parameter("pennant_n")) == CampScene.PENNANTS.size()
		and int(m.get_shader_parameter("lamp_n")) == CampScene.LAMPS.size(), "the shader has the banners, the pennants and the lamps")

func _checks_alive() -> void:
	var now := _snapshot(phone)
	var moved := func(a: Array, b: Array) -> int:
		var n := 0
		for i in mini(a.size(), b.size()):
			if a[i] != b[i]:
				n += 1
		return n
	check(moved.call(snap.tongues, now.tongues) == now.tongues.size() and float(now.clock) > float(snap.clock) + 1.0
		and float(now.flick) != float(snap.flick), "the fire's tongues sway, its light flickers (the shader's clock runs: %.2f)" % float(now.clock))
	check(moved.call(snap.lamps, now.lamps) == now.lamps.size(), "every lantern, torch and candle flickers (%d)" % now.lamps.size())
	check(now.pulses.size() > 0 and moved.call(snap.pulses, now.pulses) >= now.pulses.size() - 1, "the magic breathes")
	check(moved.call(snap.stars, now.stars) > now.stars.size() / 2, "the stars twinkle")
	check(phone.flies != null and phone.flies.flies.size() >= 10 and moved.call(snap.flies, now.flies) == now.flies.size(), "fireflies wander the camp")
	check(phone._shooting.made >= 1, "a star falls")
	check(phone.embers.emitting and phone.smoke.emitting and Array(phone.wisps).all(func(w): return (w as CPUParticles2D).emitting),
		"embers and smoke rise off the fire, sparkles off the magic")
	var dim := CampScene.WINDOWS.is_empty()
	for i in (0 if dim else 200):                           # (a window dims when someone passes: run its timer down)
		phone._windows[0][2] = 0.0
		phone._process(0.05)
		if float(phone._windows[0][3]) > 0.0:
			dim = true
			break
	check(dim, "a window dims now and then (if the picture has lit windows: %d)" % CampScene.WINDOWS.size())
	var st: Dictionary = snap.still
	var now_s := _snapshot(still)
	check(st.tongues == now_s.tongues and st.lamps == now_s.lamps and st.pulses == now_s.pulses and st.stars == now_s.stars
		and still.flies == null and not still.embers.emitting and not still.smoke.emitting
		and Array(still.wisps).all(func(w): return not (w as CPUParticles2D).emitting)
		and float((still.art.material as ShaderMaterial).get_shader_parameter("motion")) == 0.0
		and still._shooting.process_mode == Node.PROCESS_MODE_DISABLED,
		"Reduce Motion: the fire and the lights hold still, no particles, no fireflies, no falling stars, the painting still")
	check(bare.flies == null and not bare.embers.emitting and Array(bare.wisps).all(func(w): return not (w as CPUParticles2D).emitting),
		"a safe start: the painting and its still lights, no particles")

func _checks_app() -> void:
	check(app.home_scene is CampScene and app.home_scene.room == null and app.get("hero_node") == null,
		"Home's backdrop is the camp (no 3D heroes, no war table)")
	check(absf(app.hero_layer.size.y - app.size.y) < 1.0, "the hero layer is as tall as the app (%.0f / %.0f)" % [app.hero_layer.size.y, app.size.y])
	# no side buttons
	var side := []
	for k in ["side_pass", "side_orders", "side_quests", "side_ranks", "tutorial_start", "side_moba"]:
		if btn(k) != null:
			side.append(k)
	var trophies := 0
	for n in app.content.find_children("*", "TextureRect", true, false):
		var tx: Texture2D = (n as TextureRect).texture
		if tx != null and str(tx.resource_path).contains("icons/trophy"):
			trophies += 1
	check(side.is_empty() and trophies == 0, "no side buttons on Home %s" % str(side))
	# the top row
	var pill: Control = app.content.find_child("OnlinePill", true, false)
	var disc: Control = app.content.find_child("HomeDiscord", true, false)
	check(pill != null and disc != null and absf(pill.global_position.y - disc.global_position.y) < 2.5   # (the button bobs 2 px)
		and pill.get_global_rect().end.x < disc.global_position.x and has_text(pill, "FATEBOUND") and has_text(pill, "5 vs 5"),
		"the top row: the 5v5 pill and JOIN OUR DISCORD side by side")
	# PLAY, FIRST WIN, the chests
	var play := btn("play")
	var art: TextureRect = play.find_child("Plaque", true, false) if play != null else null
	var tag: Control = app.content.find_child("FirstWinTag", true, false)
	check(play != null and art != null and art.texture != null and art.texture.get_size() == Vector2(760, 255) and has_text(play, "PLAY"),
		"PLAY is the new plaque (the orange enamel, the gold frame, the gems)")
	check(tag != null and has_text(tag, "FIRST WIN") and tag.global_position.y > play.global_position.y + play.size.y * 0.5
		and tag.get_global_rect().end.y < play.global_position.y + play.size.y + Screens.FW_HANG + 1.0, "FIRST WIN hangs under PLAY as a tab")
	var names: Array = app.content.find_children("ChestName", "Label", true, false)
	var lowest := 0.0
	for n in app.content.find_children("*", "Control", true, false):
		if (n as Control).is_visible_in_tree() and (n as Control).has_meta("action_key") and str(n.get_meta("action_key")).begins_with("chest_"):
			lowest = maxf(lowest, (n as Control).get_global_rect().end.y)
	var chat_top: float = app.chat_ticker.global_position.y
	check(names.size() == app.profile.chests().size() and lowest > play.global_position.y + play.size.y and lowest <= chat_top + 1.0,
		"the chests on their panels, each with its name, under PLAY and over the chat line (%d named; the lowest button ends at %.0f, the chat at %.0f)"
		% [names.size(), lowest, chat_top])
	# ---- empty chest slots
	var ghosts: Array = app.content.find_children("*", "TextureRect", true, false).filter(func(n): return n.has_meta("empty_slot") and n.is_visible_in_tree())
	var empty_n: int = 4 - app.profile.chests().size()
	check(empty_n > 0 and ghosts.size() == empty_n and has_text(app.content, "WIN TO EARN"),
		"each empty chest slot shows a dim chest (%d of %d), the first says WIN TO EARN" % [ghosts.size(), empty_n])
	# ---- the online line
	var os_node := Node.new()
	os_node.set_script(load("res://scripts/app/online_status.gd"))
	app.online_status = os_node
	var main: Label = app.online_refs.get("main")
	os_node.info = {"online": 0, "in_match": 0}
	app.paint_online()
	var nobody := main.text
	os_node.info = {"online": 0, "in_match": 0, "chatting": 1}
	app.paint_online()
	var me_only := main.text
	os_node.info = {"online": 7, "in_match": 3, "chatting": 12}
	app.paint_online()
	var many := main.text
	os_node.info = {"online": 7, "in_match": 3}
	app.paint_online()
	check(nobody == "FATEBOUND" and me_only == "1 PLAYER ONLINE" and many == "12 PLAYERS ONLINE" and main.text == "7 PLAYERS ONLINE",
		"0.31.140: the players online -- everyone with the game open, you too (%s / %s / %s; an older server: %s)" % [nobody, me_only, many, main.text])
	var pill_w: float = pill.size.x
	var need: float = (main.get_theme_font("font") as Font).get_string_size("12 PLAYERS ONLINE", HORIZONTAL_ALIGNMENT_LEFT, -1, main.get_theme_font_size("font_size")).x
	check(main.size.x >= need - 1.0, "the pill fits \"12 PLAYERS ONLINE\" (%.0f of %.0f; the pill %.0f wide)" % [main.size.x, need, pill_w])

func _checks_menu() -> void:
	var p = app.profile
	# the badge: what's ready in the menu, "!" until the tutorial's played
	p.d.tutorial_done = false
	app.rebuild()
	var c: Dictionary = Screens.menu_counts(app)
	var bl: Label = app.menu_badge.find_children("*", "Label", true, false)[0]
	var n := int(c.orders) + int(c.quests)
	check(app.menu_badge.visible and bl.text == (str(n) if n > 0 else "!") and app.menu_button.get_node("MenuGlow").visible,
		"a new player: the menu button has a badge (%s) and glows" % bl.text)
	p.d.tutorial_done = true
	for ch in p.d.challenges.daily:
		ch.progress = 0
		ch.claimed = false
	for ch in p.d.challenges.weekly:
		ch.progress = 0
		ch.claimed = false
	p.d.login["day"] = Eco.day_key(p.now())                 # (today's login reward taken)
	app.rebuild()
	c = Screens.menu_counts(app)
	var quiet: bool = int(c.orders) == 0 and int(c.quests) == 0
	check(not quiet or (not app.menu_badge.visible and not app.menu_button.get_node("MenuGlow").visible),
		"nothing waiting, the tutorial played: no badge, no glow (%s)" % str(c))
	p.d.challenges.daily[0].progress = int(Eco.CHALLENGES[p.d.challenges.daily[0].id].goal)
	app.rebuild()
	c = Screens.menu_counts(app)
	check(app.menu_badge.visible and bl.text == str(int(c.orders) + int(c.quests)) and int(c.orders) >= 1, "an order ready: the badge counts it (%s)" % bl.text)
	# the menu
	btn("home_menu").pressed.emit()
	check(is_instance_valid(app.modal) and app.modal == app.home_menu and btn("side_orders") != null and btn("side_quests") != null
		and btn("side_ranks") != null and btn("tutorial_start") != null and btn("side_pass") == null,
		"the menu button opens the menu: ORDERS, QUESTS, RANKS, TUTORIAL (PASS has its tab)")
	var panel_top := 1e9
	for k in ["side_orders", "side_quests", "side_ranks", "tutorial_start"]:
		panel_top = minf(panel_top, btn(k).global_position.y)
	check(panel_top > app.menu_button.global_position.y + app.menu_button.size.y - 2.0, "it opens under the top bar")
	btn("home_menu_close").pressed.emit()
	check(app.modal == null, "a tap outside closes it")
	btn("home_menu").pressed.emit()
	btn("side_orders").pressed.emit()
	check(is_instance_valid(app.modal) and app.modal.has_method("refresh") and app.modal != app.home_menu, "ORDERS opens the orders window")
	app.close_modal()
