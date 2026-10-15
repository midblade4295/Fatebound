extends SceneTree
# 0.31.147 (Kevin: "Create a tutorial for everyone that walks them through how the map works and joining a clan. When
# they click join clan it put the list of available clans or they have option to start clan. Also then the map opens up
# have camera zoom to it as animation"), through the app's own buttons, with a war on the map (no server: the map the
# server would push is put in place):
#  - PLAY pushes Home's view into the war table (Home's buttons fading, nothing else pressable), then the war map opens
#    and its camera dives onto the land (the window fading in, the camera far and high first, then where it settles);
#  - the first time, the Royal Herald's tour runs by itself: a spotlight on what each line is about, the camera on the
#    places (close on a keep, on the place it picks), NEXT finishing the line first, the step count;
#  - not in a clan, it ends on JOIN A CLAN / LATER: JOIN A CLAN opens the CLAN window on joining, the tour marked seen,
#    Home out of its push again;
#  - the next PLAY: no tour; "?" runs it again; SKIP ends it (the map back to the whole land);
#  - in a clan, the tour ends on your house and tag (FINISH); reduce motion: no push, no dive.
#   godot --headless --path godot -s res://tests/war_tour_test.gd
const App = preload("res://scripts/app/siege_app.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const WarTable = preload("res://scripts/app/war_table.gd")
const Tour = preload("res://scripts/app/war_tour.gd")
const ClanPanel = preload("res://scripts/app/clan_panel.gd")
const Map = preload("res://scripts/meta/war_map.gd")

var fails: Array = []
var phase := "boot"
var t := 0.0
var t_phase := 0.0
var app
var shots := ""
var seen_scale := 1.0
var seen_alpha := 1.0
var intro_dist := 0.0
var steps_seen := 0

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

func _table():
	return app.modal if is_instance_valid(app.modal) and app.modal is WarTable else null

func _tour():
	var tb = _table()
	return tb._tour if tb != null and is_instance_valid(tb._tour) else null

static func war_fixture() -> Dictionary:
	# what the server pushes (server/world.gd map_msg) for a player in no clan: the Stags hold the Old Tower, the Lions
	# the Mill, a bar on the Tower
	var terr := {}
	for id in Map.T:
		terr[id] = {"h": ""} if not Map.is_home(id) else {"h": str(id).trim_prefix("home_")}
		if not Map.is_home(id):
			terr[id]["need"] = Map.NEED_NEUTRAL
			terr[id]["bars"] = []
	terr.tower = {"h":"stags", "ct":"STAG", "cn":"Stag Party", "need":Map.NEED_OWNED, "bars":[{"c":"clion", "ct":"LION", "h":"lions", "p":350}]}
	terr.mill = {"h":"lions", "ct":"LION", "cn":"Lion Hearts", "need":Map.NEED_OWNED, "bars":[]}
	# 0.31.149: three battles on (the hot zones): the Lions at the Stags' Tower (5 + 2 players), the Ravens on the free
	# Ford (starting), the Stags at the Mill (1)
	terr.tower["b"] = {"bid":"b1aa", "ah":"lions", "act":"LION", "state":"on", "na":5, "nd":2}
	terr.ford["b"] = {"bid":"b2bb", "ah":"ravens", "act":"RVN", "state":"lobby", "na":0, "nd":0}
	terr.mill["b"] = {"bid":"b3cc", "ah":"stags", "act":"STAG", "state":"on", "na":1, "nd":0}
	return {"week":"2026-10-12", "ends":int(Time.get_unix_time_from_system()) + 3 * 86400, "terr":terr, "tally":{}, "last":{},
		"counts":{"lions":1, "stags":1, "ravens":0}, "house":"", "clan":"", "att":Map.ATTEMPTS, "max":Map.ATTEMPTS, "caps":[]}

func _process(delta: float) -> bool:
	t += delta
	t_phase += delta
	if t > 90.0:
		check(false, "timed out in phase %s" % phase)
		return _finish()
	match phase:
		"boot":
			var base := "user://wartour-%d" % Time.get_ticks_usec()
			var p = Profile.new(base + "-profile.json", base + "-none.json")
			p.load_or_create()
			p.d.name = "Alice"
			p.d.tutorial_done = true
			p.save()
			app = App.new()
			app.profile_path = base + "-profile.json"
			app.legacy_path = base + "-none.json"
			root.add_child(app)
			_go("home")
		"home":
			if t_phase > 1.0:
				app.social.war = war_fixture()
				app.social.has_war = true
				check(app.war_tour_due(), "a phone that hasn't seen it: the tour is due")
				check(app.hero_node != null and app.hero_node.has_method("table_center"), "Home has its war table (the push aims at it)")
				press("play")
				check(app.modal == null and app._zooming and app.get_node_or_null("ZoomBlock") != null,
					"PLAY: Home pushes into the table first (the map not open yet; nothing else pressable)")
				_go("pushing")
		"pushing":
			seen_scale = maxf(seen_scale, app.hero_layer.scale.x)
			if t_phase < HOME_SECS() * 0.5:
				return false
			seen_alpha = minf(seen_alpha, app.content.modulate.a)
			var tb = _table()
			if tb == null:
				if t_phase > 3.0:
					check(false, "the war map opens after the push")
					return _finish()
				return false
			check(seen_scale > 1.5 and seen_alpha < 0.6, "Home's view pushed in on the table (x%.2f), its buttons fading (%.2f)" % [seen_scale, seen_alpha])
			check(tb._intro_on and tb.modulate.a < 0.5, "the war map fades in (%.2f) with the camera's dive on" % tb.modulate.a)
			_shot("tour_dive")
			_go("diving")
		"diving":
			var tb = _table()
			if tb._intro_on and tb._intro_t > 0.0 and tb._fit_size != Vector2i.ZERO:
				intro_dist = maxf(intro_dist, tb._cam.global_position.distance_to(tb._cam_at))
			if tb._intro_on:
				if t_phase > 4.0:
					check(false, "the dive ends")
					return _finish()
				return false
			var settled: float = tb._cam.global_position.distance_to(tb._cam_at)
			check(intro_dist > settled * 1.2 and tb.modulate.a > 0.99, "the camera dove onto the land (%.1f -> %.1f m), the window whole" % [intro_dist, settled])
			_go("tour_starts")
		"tour_starts":
			var tour = _tour()
			if tour == null:
				if t_phase > 2.0:
					check(false, "the Herald's tour starts by itself the first time")
					return _finish()
				return false
			check(tour.step == 0 and has_text(tour, "THE ROYAL HERALD") and has_text(tour, "1 / %d" % tour.steps.size()) and str(tour.steps[0].target) == "map",
				"the first time, the Herald's tour starts by itself: step 1 of %d, the spotlight on the map" % tour.steps.size())
			check(not has_text(tour, "JOIN A CLAN") and btn("war_tour_skip") != null and btn("war_tour_next") != null, "SKIP and NEXT")
			_go("typing")
		"typing":
			var tour = _tour()
			if t_phase > 0.15:
				var full := str(tour.steps[0].text).length()
				check(tour.shown < float(full), "the line types out")
				press("war_tour_next")
				check(tour.step == 0 and tour.shown >= float(full), "NEXT finishes the line first")
				_shot("tour_1")
				press("war_tour_next")
				check(tour.step == 1 and str(tour.steps[1].id) == "tour_homes", "...then the next line (the keeps)")
				_go("homes")
		"homes":
			var tb = _table()
			if t_phase > 1.2:
				check(tb._zoom > 1.8, "the camera goes close on a keep (zoom %.2f)" % tb._zoom)
				_shot("tour_2")
				var tour = _tour()
				tour.shown = 9999.0
				press("war_tour_next")
				_go("land")
		"land":
			var tb = _table()
			var tour = _tour()
			if t_phase > 1.2:
				var ex := str(tour.steps[2].pick)
				check(ex != "" and str(tb.sel) == ex and has_text(tb, Map.name_of(ex).to_upper()) and has_text(tb, "Held by House"),
					"a land: a held place picked (%s), its sheet up" % ex)
				var hole: Rect2 = tour._hole
				var sheet: Rect2 = tb.tour_rect("sheet")
				check(hole.grow(-8.0).encloses(Rect2(sheet.position + Vector2(4, 4), sheet.size - Vector2(8, 8))) or hole.intersects(sheet),
					"the spotlight on the place's sheet")
				_shot("tour_3")
				_go("walk")
		"walk":
			var tour = _tour()
			if tour == null:
				check(false, "the tour runs to its end")
				return _finish()
			if t_phase > 0.25:
				t_phase = 0.0
				if tour.steps[tour.step].has("end"):
					var last: Dictionary = tour.steps[tour.step]
					check(str(last.id) == "tour_clan" and btn("war_tour_join") != null and btn("war_tour_later") != null and btn("war_tour_next") == null,
						"the last step (no clan): JOIN A CLAN or LATER")
					var ids: Array = tour.steps.map(func(s): return str(s.id))
					check(ids.has("tour_bars") and ids.has("tour_take") and ids.has("tour_links") and ids.has("tour_battles") and ids.has("tour_week") and ids.has("tour_hot") and not ids.has("tour_quick"),
						"the tour covers the bars, taking land, the roads, the day's battles, the week, BATTLES NOW (%s)" % str(ids))
					check(steps_seen > 0, "the spotlight on BATTLES NOW on its step")
					_shot("tour_last")
					press("war_tour_join")
					_go("joined")
					return false
				if str(tour.steps[tour.step].id) == "tour_hot":
					var hole: Rect2 = tour._target
					var q: Rect2 = Rect2(tour.table.tour_rect("hot").position - tour.global_position, tour.table.tour_rect("hot").size)
					if hole.encloses(q) and q.size.y > 20.0:
						steps_seen += 1
					_shot("tour_hot")
				tour.shown = 9999.0
				press("war_tour_next")
		"joined":
			if t_phase > 0.6:
				check(app.modal is ClanPanel and str(app.modal.focus) == "join", "JOIN A CLAN opens the CLAN window on joining")
				check(not app.war_tour_due() and bool(app.profile.d.settings.get("war_tour", false)), "the tour is marked seen (on this phone)")
				check(app.hero_layer.scale.x < 1.05 and app.content.modulate.a > 0.95, "Home out of its push again")
				app.close_modal()
				_go("again")
		"again":
			if t_phase > 0.5:
				press("play")
				_go("again_open")
		"again_open":
			var tb = _table()
			if tb != null and not tb._intro_on and t_phase > 2.0:
				check(_tour() == null, "the next PLAY: no tour")
				press("war_help")
				check(_tour() != null and _tour().step == 0, "\"?\" runs it again")
				_go("skip")
		"skip":
			if t_phase > 0.3:
				var tb = _table()
				press("war_tour_skip")
				check(_tour() == null or _tour()._done, "SKIP ends it")
				_go("skipped")
		"skipped":
			if t_phase > 1.2:
				var tb = _table()
				check(_tour() == null and str(tb.sel) == "" and tb._zoom < 1.05, "...the map back on the whole land, nothing picked")
				# in a clan: the tour ends on your house and tag
				var st: Array = Tour.make_steps(war_fixture(), true, "lions", "LION")
				check(str(st[-1].id) == "tour_ready" and str(st[-1].text).contains("House Lions") and str(st[-1].text).contains("[LION]") and str(st[-1].end) == "clan"
					and str(st[1].cam[1]) == "home_lions", "in a clan: the last step is your house and tag, FINISH; the keep shown is your house's")
				check(Tour.example_place(war_fixture(), "lions") == "tower", "the place shown to a Lion: the Stags' Tower")
				_go("hot")
		"hot":
			# 0.31.149 (Kevin: "Remove the quick play so the player needs to choose where to fight. Maybe show hot zones where
			# players are actively fighting and players can jump right into that battle")
			if t_phase > 0.3:
				var tb = _table()
				check(btn("war_quick") == null and not has_text(tb, "QUICK BATTLE"), "no QUICK BATTLE")
				var hot: Array = tb.hot_list()
				check(hot.size() == 3 and str(hot[0].tid) == "tower" and int(hot[0].n) == 7 and str(hot[0].can) == "free",
					"BATTLES NOW: the three battles, the busiest first (the Tower, 7 fighting), each open to a player with no clan")
				check(has_text(tb, "BATTLES NOW") and has_text(tb, "3 ON") and has_text(tb, "OLD TOWER") and has_text(tb, "Lions attack Stags  ·  7 fighting")
					and has_text(tb, "+1 more") and btn("war_hot_fight_tower") != null and btn("war_hot_fight_tower").text == "JOIN LIONS",
					"two rows (the Tower: Lions attack Stags, 7 fighting; JOIN LIONS), +1 more on the map")
				var tl: PanelContainer = tb._labels.tower
				check(tl.visible and str((tl.get_meta("sub") as Label).text) == "⚔ 7 FIGHTING", "the map: the Tower's label, ⚔ 7 FIGHTING")
				_shot("hot_zones")
				press("war_hot_tower")
				_go("hot_pick")
		"hot_pick":
			if t_phase > 1.2:
				var tb = _table()
				check(str(tb.sel) == "tower" and tb._zoom > 1.5 and btn("war_fight_att") != null and btn("war_fight_def") != null
					and btn("war_fight_def").text == "DEFEND FOR STAGS", "a tap on the row: the camera on the Tower, its sheet -- JOIN LIONS or DEFEND FOR STAGS")
				_shot("hot_pick")
				app.close_modal()
				app.profile.d.settings["reduce_motion"] = true
				_go("calm")
		"calm":
			if t_phase > 0.5:
				press("play")
				var tb = _table()
				check(tb != null and not tb._intro_on and tb.modulate.a > 0.99 and app.hero_layer.scale.x < 1.01,
					"reduce motion: the map opens at once, no push, no dive")
				return _finish()
	return false

func HOME_SECS() -> float:
	return float(App.HOME_ZOOM_SECS)

func _finish() -> bool:
	print("WAR_TOUR_PASS" if fails.is_empty() else "WAR_TOUR_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
	return true
